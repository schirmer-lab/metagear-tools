#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# Share parameter configuration with other scripts
source "$SCRIPT_DIR/lib/workflow_definitions.sh"

LAUNCH_DIR="$PWD"

function run_workflows() {
    workflow="$1"
    shift

    local default_input_file="$LAUNCH_DIR/input_${workflow}.csv"

    # Check if JSON definitions are available
    if [ -f "$JSON_DEFINITIONS_FILE" ]; then
        # Use JSON-based validation
        local validation_result
        if ! validation_result=$(validate_workflow_and_parameters "$workflow" "$@"); then
            echo "$validation_result" >&2
            usage
        fi

        # Parse validated parameters
        declare -A values=()
        while IFS='=' read -r param value; do
            [ -n "$param" ] && values["$param"]="$value"
        done <<< "$validation_result"

    else
        echo "Error: workflow definitions file not found at $JSON_DEFINITIONS_FILE" >&2
        echo "JSON-based workflow definitions are required." >&2
        exit 1
    fi

    local outdir="${values[outdir]:-results}"

    # Handle input parameter if present
    if [[ -v values[input] ]] && [ -n "${values[input]:-}" ]; then
        cp "${values[input]}" "$default_input_file"
    fi

    mkdir -p "$outdir"

    # Build the command
    cmd="--workflow $workflow"
    for param in "${!values[@]}"; do
        [[ "$param" == "outdir" ]] && continue
        if [ -n "${values[$param]:-}" ]; then
            cmd+=" --$param ${values[$param]}"
        fi
    done
    cmd+=" --outdir $outdir"

    echo "$cmd"
}

