#!/usr/bin/env bash
# Workflow parameter and description configuration shared by CLI scripts

# Get the directory where this script is located
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# Set JSON_DEFINITIONS_FILE prioritizing pipeline-specific definitions
if [ -f "$INSTALL_DIR/latest/workflow_definitions.json" ]; then
    JSON_DEFINITIONS_FILE="$INSTALL_DIR/latest/workflow_definitions.json"
else
    JSON_DEFINITIONS_FILE="$SCRIPT_DIR/workflow_definitions.json"
fi

# Factory-style loader for JSON parser implementations
# Load appropriate JSON parser based on availability (jq takes priority)
if [ -f "$SCRIPT_DIR/json_parser_jq.sh" ]; then
    source "$SCRIPT_DIR/json_parser_jq.sh"
    if check_jq_available; then
        JSON_PARSER="jq"
    fi
fi

if [ -z "${JSON_PARSER:-}" ] && [ -f "$SCRIPT_DIR/json_parser_python.sh" ]; then
    source "$SCRIPT_DIR/json_parser_python.sh"
    if check_python_available; then
        JSON_PARSER="python"
    fi
fi

# Error if no parser is available
if [ -z "${JSON_PARSER:-}" ]; then
    echo "Error: Neither 'jq' nor 'python3' is available for JSON parsing." >&2
    echo "Please install one of them to use JSON workflow definitions." >&2
    exit 1
fi

# Function to check if workflow has required parameters
workflow_has_required_parameters() {
    local workflow_name="$1"

    # Check if workflow exists
    if ! workflow_exists "$workflow_name"; then
        return 1
    fi

    # Check only workflow-specific parameters for required ones (exclude global parameters)
    while IFS= read -r param_json; do
        [ -z "$param_json" ] && continue
        local required
        required=$(get_parameter_field "$param_json" "required")
        if [ "$required" = "true" ]; then
            return 0  # Found at least one required parameter
        fi
    done < <(get_workflow_parameters "$workflow_name")

    return 1  # No required parameters found
}

# Function to validate workflow and parameters
validate_workflow_and_parameters() {
    local workflow_name="$1"
    shift
    local -A provided_params=()
    local -A allowed_params=()
    local -A required_params=()
    local -A default_values=()

    # Check if workflow exists
    if ! workflow_exists "$workflow_name"; then
        echo "Error: Workflow '$workflow_name' not found." >&2
        return 1
    fi

    # Parse provided parameters
    while (( $# > 0 )); do
        case "$1" in
            --*)
                local param="${1#--}"
                shift
                if (( $# == 0 )); then
                    echo "Error: Option --$param requires a value." >&2
                    return 1
                fi
                provided_params["$param"]="$1"
                ;;
            *)
                echo "Error: Invalid option: $1" >&2
                return 1
                ;;
        esac
        shift
    done

    # Load global parameters
    while IFS= read -r param_json; do
        [ -z "$param_json" ] && continue
        local name required default desc
        name=$(get_parameter_field "$param_json" "name")
        required=$(get_parameter_field "$param_json" "required")
        default=$(get_parameter_field "$param_json" "default")

        [ -n "$name" ] || continue
        allowed_params["$name"]=1
        [ "$required" = "true" ] && required_params["$name"]=1
        [ -n "$default" ] && default_values["$name"]="$default"
    done < <(get_global_parameters)

    # Load workflow-specific parameters
    while IFS= read -r param_json; do
        [ -z "$param_json" ] && continue
        local name required default desc
        name=$(get_parameter_field "$param_json" "name")
        required=$(get_parameter_field "$param_json" "required")
        default=$(get_parameter_field "$param_json" "default")

        [ -n "$name" ] || continue
        allowed_params["$name"]=1
        [ "$required" = "true" ] && required_params["$name"]=1
        [ -n "$default" ] && default_values["$name"]="$default"
    done < <(get_workflow_parameters "$workflow_name")

    # Validate provided parameters
    for param in "${!provided_params[@]}"; do
        if [[ ! -v allowed_params["$param"] ]]; then
            echo "Error: Invalid option: --$param for $workflow_name workflow." >&2
            return 1
        fi
    done

    # Check required parameters
    for param in "${!required_params[@]}"; do
        if [[ ! -v provided_params["$param"] ]]; then
            echo "Error: --$param is required for $workflow_name workflow." >&2
            return 1
        fi
    done

    # Output final parameter values (provided + defaults)
    local -A final_params=()

    # Start with defaults
    for param in "${!default_values[@]}"; do
        final_params["$param"]="${default_values[$param]}"
    done

    # Override with provided values
    for param in "${!provided_params[@]}"; do
        final_params["$param"]="${provided_params[$param]}"
    done

    # Output parameters in format: param=value
    for param in "${!final_params[@]}"; do
        echo "$param=${final_params[$param]}"
    done

    return 0
}

# Function to get workflow list for usage display
get_workflow_list() {
    if [ -f "$JSON_DEFINITIONS_FILE" ]; then
        # Use JSON definitions
        while IFS= read -r workflow; do
            [ -z "$workflow" ] && continue
            local desc
            desc=$(get_workflow_description "$workflow")
            printf "  %-20s %s\n" "$workflow" "$desc"
        done < <(get_available_workflows)
    else
        echo "Error: workflow definitions file not found at $JSON_DEFINITIONS_FILE" >&2
        return 1
    fi
}

# Function to display workflow-specific help
show_workflow_help() {
    local workflow_name="$1"

    if ! workflow_exists "$workflow_name"; then
        echo "Error: Workflow '$workflow_name' not found." >&2
        return 1
    fi

    local desc
    desc=$(get_workflow_description "$workflow_name")

    echo ""
    echo "Usage: metagear $workflow_name [options]"
    echo "Description: $desc"
    echo ""

    # Get workflow-specific parameters
    local has_workflow_params=false
    while IFS= read -r param_json; do
        [ -z "$param_json" ] && continue
        if [ "$has_workflow_params" = false ]; then
            echo "Workflow-specific parameters:"
            has_workflow_params=true
        fi
        local name required default description
        name=$(get_parameter_field "$param_json" "name")
        required=$(get_parameter_field "$param_json" "required")
        default=$(get_parameter_field "$param_json" "default")
        description=$(get_parameter_field "$param_json" "description")

        [ -n "$name" ] || continue

        local req_text=""
        [ "$required" = "true" ] && req_text=" (required)"

        local default_text=""
        [ -n "$default" ] && [ "$default" != "null" ] && default_text=" [default: $default]"

        printf "  --%-18s %s%s%s\n" "$name" "$description" "$req_text" "$default_text"
    done < <(get_workflow_parameters "$workflow_name")

    # Add separator if we had workflow-specific parameters
    [ "$has_workflow_params" = true ] && echo ""

    # Get global parameters
    echo "Global parameters:"
    while IFS= read -r param_json; do
        [ -z "$param_json" ] && continue
        local name required default description
        name=$(get_parameter_field "$param_json" "name")
        required=$(get_parameter_field "$param_json" "required")
        default=$(get_parameter_field "$param_json" "default")
        description=$(get_parameter_field "$param_json" "description")

        [ -n "$name" ] || continue

        local req_text=""
        [ "$required" = "true" ] && req_text=" (required)"

        local default_text=""
        [ -n "$default" ] && [ "$default" != "null" ] && default_text=" [default: $default]"

        printf "  --%-18s %s%s%s\n" "$name" "$description" "$req_text" "$default_text"
    done < <(get_global_parameters)

    echo ""
}
