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

# Detect preview mode and filter it from the arguments
PREVIEW=false
REMAINING_ARGS=()
while (( $# > 0 )); do
    case "$1" in
        -preview|--preview)
            PREVIEW=true
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

custom_config_files=( $PIPELINE_DIR/conf/metagear/$COMMAND.config $INSTALL_DIR/metagear.config )
metagear_config_files=( $PIPELINE_DIR/conf/metagear/*.config )
all_config_files=( "${metagear_config_files[@]}" "${custom_config_files[@]}" )

$UTILITIES_DIR/lib/merge_configuration.sh ${all_config_files[@]} > $LAUNCH_DIR/$COMMAND.config

nf_cmd_workflow_part=$(run_workflows $COMMAND "${REMAINING_ARGS[@]}")

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
