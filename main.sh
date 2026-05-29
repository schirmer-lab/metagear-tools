#!/usr/bin/env bash

# set -o errexit    # exit immediately on any non-zero
# set -o nounset    # error on undefined variables
# set -o pipefail   # catch failures in pipelines
# set -o errtrace   # ensure ERR trap is inherited by functions
# set -o xtrace     # print each command right before executing it

# Check Bash version 4+.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Bash version 4 or higher is required (found version ${BASH_VERSINFO[0]})."
    exit 1
fi

# Resolve script directory and source common functions
UTILITIES_DIR="$INSTALL_DIR/utilities"
PIPELINE_DIR="$INSTALL_DIR/latest"
LAUNCH_DIR="$PWD"

source "${UTILITIES_DIR}/lib/common.sh"
source "${UTILITIES_DIR}/lib/workflows.sh"

# Handle --version early — must work even if config files are missing,
# since users may run `metagear --version` to debug a broken install.
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-version" ] || [ "${1:-}" = "version" ]; then
    show_version
    exit 0
fi

check_metagear_home

# Ensure a command is provided
if [ $# -eq 0 ]; then
    usage
fi

COMMAND="$1"
shift

# Handle global --help flag
if [ "$COMMAND" = "--help" ] || [ "$COMMAND" = "-help" ] || [ "$COMMAND" = "help" ]; then
    usage
fi

check_command "$COMMAND"

# Check for help flag early, before any file operations
for arg in "$@"; do
    if [ "$arg" = "--help" ] || [ "$arg" = "-help" ]; then
        # Load workflow functions to show help
        source "${UTILITIES_DIR}/lib/workflow_definitions.sh"
        show_workflow_help "$COMMAND"
        exit 0
    fi
done

# Detect preview mode and --reuse-outputs, filter both from the arguments.
PREVIEW=false
REUSE_OUTPUTS=false
REMAINING_ARGS=()
while (( $# > 0 )); do
    case "$1" in
        -preview|--preview)
            PREVIEW=true
            ;;
        -reuse-outputs|--reuse-outputs)
            REUSE_OUTPUTS=true
            ;;
        *)
            REMAINING_ARGS+=("$1")
            ;;
    esac
    shift
done

# If no arguments remain after filtering out --preview, check if help should be shown
if [ ${#REMAINING_ARGS[@]} -eq 0 ]; then
    # Load workflow functions to check if workflow has required parameters
    source "${UTILITIES_DIR}/lib/workflow_definitions.sh"

    # Only show help if the workflow has required parameters
    if workflow_has_required_parameters "$COMMAND"; then
        show_workflow_help "$COMMAND"
        exit 0
    fi
    # If no required parameters, continue with execution (empty REMAINING_ARGS is fine)
fi

# mkdir -p $LAUNCH_DIR/.metagear

# Regenerate per-user resource override config from YAML, if both the YAML
# and the pipeline-side generator are present. The output is loaded by
# Nextflow via includeConfig in nextflow.config — separate from the merge
# below, so per-key resource overrides don't clobber workflow-specific
# ext.args/publishDir from conf/metagear/.
USER_RES_YAML="$INSTALL_DIR/resources.yaml"
USER_RES_CONFIG="$INSTALL_DIR/resources.config"
RES_GENERATOR="$UTILITIES_DIR/lib/build_resources_config.sh"
if [[ -f "$USER_RES_YAML" && -f "$RES_GENERATOR" ]]; then
    if ! bash "$RES_GENERATOR" "$USER_RES_YAML" "$USER_RES_CONFIG" >/dev/null; then
        echo "Warning: failed to regenerate $USER_RES_CONFIG from $USER_RES_YAML; falling back to pipeline defaults." >&2
        rm -f "$USER_RES_CONFIG"
    fi
fi

custom_config_files=( $PIPELINE_DIR/conf/metagear/$COMMAND.config $INSTALL_DIR/metagear.config )
metagear_config_files=( $PIPELINE_DIR/conf/metagear/*.config )
all_config_files=( "${metagear_config_files[@]}" "${custom_config_files[@]}" )

$UTILITIES_DIR/lib/merge_configuration.sh ${all_config_files[@]} > $LAUNCH_DIR/$COMMAND.config

# Re-bind executor caps and per-process resourceLimits so they pick up the
# user's max_* values from $INSTALL_DIR/metagear.config. nextflow.config sets
# these too, but Groovy resolves them at *its* parse time using the pipeline
# defaults — by the time -c <merged>.config updates params.max_*, executor.cpus
# and process.resourceLimits are already locked. Re-binding them here, in the
# config that loads last, fixes the override path.
cat >> "$LAUNCH_DIR/$COMMAND.config" <<'EOF'

executor {
    cpus   = params.max_cpus as int
    memory = params.max_memory as nextflow.util.MemoryUnit
}

process {
    resourceLimits = [
        cpus  : params.max_cpus as int,
        memory: params.max_memory as nextflow.util.MemoryUnit,
        time  : params.max_time as nextflow.util.Duration,
    ]
}
EOF

nf_cmd_workflow_part=$(run_workflows $COMMAND "${REMAINING_ARGS[@]}")

# If --reuse-outputs was passed, scan ${outdir} for previously-produced
# artifacts and append corresponding --<param> <path> flags so the pipeline's
# existing skip-if-set logic (--contigs_dir, --genes_dir, --representative_*)
# kicks in. Flags the user already specified explicitly are NOT overridden.
if [[ "$REUSE_OUTPUTS" == "true" ]]; then
    source "$UTILITIES_DIR/lib/auto_reuse.sh"

    # Pull --input and --outdir out of the user's args (with sensible default
    # for outdir matching workflows.sh).
    reuse_input=""
    reuse_outdir="results"
    for ((i = 0; i < ${#REMAINING_ARGS[@]}; i++)); do
        case "${REMAINING_ARGS[i]}" in
            --input)  reuse_input="${REMAINING_ARGS[i+1]}" ;;
            --outdir) reuse_outdir="${REMAINING_ARGS[i+1]}" ;;
        esac
    done

    if [[ -n "$reuse_input" ]]; then
        reuse_flags=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && reuse_flags+=( "$line" )
        done < <(auto_reuse_emit_flags "$reuse_outdir" "$reuse_input" "${REMAINING_ARGS[@]}")

        # Walk the reuse-emitted flags and decide which to attach. Two skip cases:
        #   1. user already passed the same flag explicitly → log inline (rare,
        #      and the user wants to know their explicit choice took effect)
        #   2. the flag isn't valid for this workflow's param schema → collect
        #      silently and print one summary line at the end. This case is
        #      common (e.g. running classification in an outdir that
        #      also has genes artifacts), and a per-flag "skipped"
        #      message just produces line noise the user has to scan past.
        skipped_not_applicable=()
        i=0
        while (( i < ${#reuse_flags[@]} )); do
            flag="${reuse_flags[i]}"
            value="${reuse_flags[i+1]}"
            already_set=false
            for arg in "${REMAINING_ARGS[@]}"; do
                if [[ "$arg" == "$flag" ]]; then
                    already_set=true
                    echo "[auto-reuse]   ${flag}  skipped: user passed it explicitly" >&2
                    break
                fi
            done
            if [[ "$already_set" == "false" ]]; then
                param_name="${flag#--}"
                if is_workflow_param_allowed "$COMMAND" "$param_name"; then
                    nf_cmd_workflow_part="$nf_cmd_workflow_part $flag $value"
                else
                    skipped_not_applicable+=( "$flag" )
                fi
            fi
            i=$((i + 2))
        done

        # Single-line summary of the "found but not applicable" set. Suppressed
        # entirely when nothing was skipped that way.
        if (( ${#skipped_not_applicable[@]} > 0 )); then
            printf -- '[auto-reuse] %d other artifact(s) detected but not applicable to %s: %s\n' \
                "${#skipped_not_applicable[@]}" \
                "$COMMAND" \
                "$(IFS=', '; echo "${skipped_not_applicable[*]}")" >&2
        fi
    else
        echo "[auto-reuse] --reuse-outputs requested but --input not provided — skipping" >&2
    fi
fi

cat $INSTALL_DIR/metagear.env > $LAUNCH_DIR/metagear_$COMMAND.sh

echo "" >> $LAUNCH_DIR/metagear_$COMMAND.sh
echo "nextflow run $PIPELINE_DIR/main.nf \\
        $nf_cmd_workflow_part \\
        -c $LAUNCH_DIR/$COMMAND.config \\
        \$RUN_PROFILES -w \\
        \$NF_WORK -resume" >> $LAUNCH_DIR/metagear_$COMMAND.sh
echo "" >> $LAUNCH_DIR/metagear_$COMMAND.sh

chmod +x $LAUNCH_DIR/metagear_$COMMAND.sh

if [ "$PREVIEW" = true ]; then
    echo "------ Preview mode ------"
    cat "$LAUNCH_DIR/metagear_$COMMAND.sh"
    echo "--------------------------"
    echo "The script above was generated at $LAUNCH_DIR/metagear_$COMMAND.sh"
    echo "Run it directly or re-run this command without the preview flag to execute."
else
    $LAUNCH_DIR/metagear_$COMMAND.sh
fi
