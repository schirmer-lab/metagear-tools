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

# Nextflow's own `clean`, not rm -rf: .nextflow/cache indexes the work dir and must go with it.
# Safe for results because every publishDir here is mode: 'copy'.
metagear_clean() {
    local dir="" dry=true keep="-k" but="" force=false verbose=false

    while (( $# > 0 )); do
        case "$1" in
            -n|--dry-run)    dry=true ;;
            -f|--force)      force=true; dry=false ;;
            -k|--keep-logs)  keep="-k" ;;
            --drop-logs)     keep="" ;;
            --but)           but="$2"; shift ;;
            --but=*)         but="${1#--but=}" ;;
            -v|--verbose)    verbose=true ;;
            -h|--help)
                cat <<'CLEANHELP'
Usage: metagear clean [DIRECTORY] [options]

  Reclaim the work directory of a finished workspace. Results are untouched:
  every output is published by copy, so results/ holds real files.

  DIRECTORY   the workspace to clean (default: the current directory). It is the
              directory holding .nextflow/ and nf_work/ — one level above results/.

Options:
  -n, --dry-run     list what would be removed and remove nothing (the default)
  -f, --force       actually remove it
  -k, --keep-logs   keep execution history and metadata (default)
      --drop-logs   remove the history too; the workspace can no longer -resume
      --but RUN     keep this run's work, clean the rest
  -v, --verbose     list every task directory instead of just the count
CLEANHELP
                return 0 ;;
            -*)  echo "metagear clean: unknown option $1" >&2; return 1 ;;
            *)   dir="$1" ;;
        esac
        shift
    done

    dir="${dir:-$PWD}"
    if [ ! -d "$dir/.nextflow" ]; then
        echo "metagear clean: $dir is not a workspace — no .nextflow/ there." >&2
        echo "  Point at the directory holding nf_work/, one level above results/." >&2
        return 1
    fi

    # Nextflow reports a held session lock as an "unable to acquire lock" stack trace that reads
    # like corruption; nearly always a run is simply still going. /proc needs no lsof.
    local live=""
    local proc cwd
    for proc in /proc/[0-9]*; do
        cwd=$(readlink "$proc/cwd" 2>/dev/null) || continue
        case "$cwd" in
            "$dir"|"$dir"/*) live="${proc#/proc/}"; break ;;
        esac
    done
    if [ -n "$live" ]; then
        echo "metagear clean: a run is still using $dir (pid $live)." >&2
        echo "  Wait for it to finish, or stop it, before reclaiming the work directory." >&2
        return 1
    fi

    # errexit and pipefail are inherited from system_utils.sh, so an unguarded `du` on a workspace
    # whose work directory is already gone would abort the whole command without printing anything.
    local before=""
    if [ -d "$dir/nf_work" ]; then
        before=$(du -sh "$dir/nf_work" 2>/dev/null | cut -f1 || true)
    fi
    echo "[clean] workspace $dir"
    if [ -n "$before" ]; then
        echo "[clean] work directory currently $before"
    else
        echo "[clean] no work directory here — nothing left to reclaim."
        return 0
    fi

    local args=( clean -f )
    [ -n "$keep" ] && args+=( "$keep" )
    [ -n "$but" ] && args+=( -but "$but" )
    # -n is Nextflow's own dry run: it prints what it would remove and removes nothing.
    $dry && args+=( -n )

    # Nextflow prints one line per task directory, which for a real cohort is thousands of lines
    # of hex. The count is the useful part; keep the list behind --verbose.
    local out rc
    out=$(cd "$dir" && nextflow "${args[@]}" 2>&1)
    rc=$?

    if $verbose; then
        echo "$out"
    else
        echo "$out" | grep -v -e '^Would remove' -e '^Removed' || true
    fi

    local n
    n=$(echo "$out" | grep -c -e '^Would remove' -e '^Removed' || true)
    if $dry; then
        echo "[clean] $n task directories would be removed, reclaiming about ${before:-0}."
        echo "[clean] nothing was removed. Re-run with --force to reclaim it."
    else
        local after
        after=$(du -sh "$dir/nf_work" 2>/dev/null | cut -f1 || true)
        echo "[clean] removed $n task directories; work directory now ${after:-empty}."
    fi
    return $rc
}


# A named sequence of workflows. Every step takes the same --input/--outdir and hands off
# through the shared workspace, so a preset is just a list of names -- see workflow_definitions.json.
metagear_preset() {
    local preset="$1"; shift
    local steps=()
    while IFS= read -r step; do [ -n "$step" ] && steps+=("$step"); done < <(get_preset_steps "$preset")

    local preview=false
    for arg in "$@"; do
        case "$arg" in
            --preview|--dry-run) preview=true ;;
            -h|--help)
                echo ""
                echo "Usage: metagear ${preset} --input <samplesheet> --outdir <directory> [options]"
                echo ""
                echo "  $(get_preset_description "$preset")"
                echo ""
                echo "  Runs, in order:"
                printf '    %s\n' "${steps[@]}"
                echo ""
                echo "  Each step reuses what the ones before it produced. Options are passed to"
                echo "  every step, so anything a single workflow accepts works here too."
                echo ""
                echo "  --preview   show the plan without running anything"
                return 0 ;;
        esac
    done

    echo "[$preset] $(get_preset_description "$preset")"
    echo "[$preset] ${#steps[@]} steps: $(printf '%s -> ' "${steps[@]}" | sed 's/ -> $//')"

    # Reuse is what makes a chain a chain: without it every step would start from the reads.
    # Added once, and only if the caller has not already asked for it.
    local passthrough=("$@")
    local reuse=true
    for arg in "$@"; do [ "$arg" = "--reuse-outputs" ] && reuse=false; done
    $reuse && passthrough+=("--reuse-outputs")

    local index=0
    for step in "${steps[@]}"; do
        index=$((index + 1))
        echo ""
        echo "[$preset] step $index/${#steps[@]}: $step"
        if $preview; then
            echo "         metagear $step ${passthrough[*]}"
            continue
        fi
        if ! "$UTILITIES_DIR/main.sh" "$step" "${passthrough[@]}"; then
            echo "" >&2
            echo "[$preset] $step failed; the steps after it were not started." >&2
            echo "  Fix what it reported and run the same command again: the steps that already" >&2
            echo "  finished resume from their own caches rather than starting over." >&2
            return 1
        fi
    done

    echo ""
    echo "[$preset] all ${#steps[@]} steps finished."
    return 0
}


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

# Utilities and presets are dispatched before check_command, which only knows about workflows.
if [ "$COMMAND" = "clean" ]; then
    metagear_clean "$@"
    exit $?
fi

if get_presets 2>/dev/null | grep -qx -- "$COMMAND"; then
    metagear_preset "$COMMAND" "$@"
    exit $?
fi

if [ "$COMMAND" = "cluster" ]; then
    # Invoked where installed: the scripts keep state beside themselves (hq binary, server dir).
    cluster_bin="${INSTALL_DIR}/cluster/metagear-cluster"
    if [ ! -x "$cluster_bin" ]; then
        echo "metagear cluster: the cluster tools are not installed at $cluster_bin." >&2
        echo "  Re-run install.sh to add them." >&2
        exit 1
    fi
    exec "$cluster_bin" "$@"
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

# Detect preview mode, --reuse-outputs and --reuse-from; filter all three from the
# arguments so they never reach nextflow.
PREVIEW=false
REUSE_OUTPUTS=false
# Where to look for reusable outputs. Empty means this run's own --outdir, which is
# what it always did: reuse only worked when the run executed in the previous run's
# directory. Naming a directory here separates "where my results go" from "where the
# work I am reusing already is", so a run can pick up a catalog from anywhere the
# account can read without also inheriting that run's workspace.
REUSE_FROM=""
REMAINING_ARGS=()
while (( $# > 0 )); do
    case "$1" in
        -preview|--preview)
            PREVIEW=true
            ;;
        -reuse-outputs|--reuse-outputs)
            REUSE_OUTPUTS=true
            ;;
        -reuse-from|--reuse-from)
            # Naming a source implies wanting one: --reuse-from alone is enough, and
            # having to pass both flags would only be a way to get it half-right.
            REUSE_FROM="${2:-}"
            REUSE_OUTPUTS=true
            shift
            ;;
        -reuse-from=*|--reuse-from=*)
            REUSE_FROM="${1#*=}"
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

    # An explicit source wins over the run's own outdir.
    if [[ -n "$REUSE_FROM" ]]; then
        if [[ ! -d "$REUSE_FROM" ]]; then
            echo "metagear: --reuse-from $REUSE_FROM is not a directory" >&2
            exit 1
        fi
        reuse_outdir="$REUSE_FROM"
        echo "[auto-reuse] reusing from $reuse_outdir (not this run's own outdir)" >&2
    fi

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
