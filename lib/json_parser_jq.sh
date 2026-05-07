#!/usr/bin/env bash
# JSON parser implementation using jq
# This file provides JSON parsing functions for workflow definitions

# Check if jq is available
check_jq_available() {
    command -v jq >/dev/null 2>&1
}

# Get all available workflows using jq
jq_get_available_workflows() {
    local json_file="$1"
    jq -r '.metagear.workflows.definitions[].name' "$json_file"
}

# Check if a workflow exists using jq
jq_workflow_exists() {
    local json_file="$1"
    local workflow_name="$2"
    # Use jq -e and convert exit codes: 0 -> 0 (found), 4 -> 1 (not found), others -> error
    if jq -e --arg name "$workflow_name" '.metagear.workflows.definitions[] | select(.name == $name)' "$json_file" >/dev/null 2>&1; then
        return 0  # found
    else
        local exit_code=$?
        if [ $exit_code -eq 4 ]; then
            return 1  # not found (jq returns 4 when no results with -e)
        else
            return $exit_code  # other error
        fi
    fi
}

# Get workflow description using jq
jq_get_workflow_description() {
    local json_file="$1"
    local workflow_name="$2"
    jq -r --arg name "$workflow_name" '.metagear.workflows.definitions[] | select(.name == $name) | .description // ""' "$json_file"
}

# Get workflow parameters using jq
jq_get_workflow_parameters() {
    local json_file="$1"
    local workflow_name="$2"
    jq -c --arg name "$workflow_name" '.metagear.workflows.definitions[] | select(.name == $name) | .parameters[]?' "$json_file"
}

# Get global parameters using jq
jq_get_global_parameters() {
    local json_file="$1"
    jq -c '.metagear.workflows.global_parameters[]' "$json_file"
}

# Helper function to extract parameter field values with proper boolean handling
jq_get_parameter_field() {
    local param_json="$1"
    local field="$2"
    echo "$param_json" | jq -r "if has(\"$field\") then (.$field | if type == \"boolean\" then tostring else . end) else \"\" end"
}

# Unified interface functions (factory pattern)
get_available_workflows() {
    jq_get_available_workflows "$JSON_DEFINITIONS_FILE"
}

workflow_exists() {
    jq_workflow_exists "$JSON_DEFINITIONS_FILE" "$1"
}

get_workflow_description() {
    jq_get_workflow_description "$JSON_DEFINITIONS_FILE" "$1"
}

get_workflow_parameters() {
    jq_get_workflow_parameters "$JSON_DEFINITIONS_FILE" "$1"
}

get_global_parameters() {
    jq_get_global_parameters "$JSON_DEFINITIONS_FILE"
}

get_parameter_field() {
    jq_get_parameter_field "$1" "$2"
}
