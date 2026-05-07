#!/usr/bin/env bash
# JSON parser implementation using Python
# This file provides JSON parsing functions for workflow definitions

# Check if python3 is available
check_python_available() {
    command -v python3 >/dev/null 2>&1
}

# Get all available workflows using Python
python_get_available_workflows() {
    local json_file="$1"
    python3 -c "
import json
with open('$json_file', 'r') as f:
    data = json.load(f)
for workflow in data['metagear']['workflows']['definitions']:
    print(workflow['name'])
"
}

# Check if a workflow exists using Python
python_workflow_exists() {
    local json_file="$1"
    local workflow_name="$2"
    python3 -c "
import json, sys
with open('$json_file', 'r') as f:
    data = json.load(f)
for workflow in data['metagear']['workflows']['definitions']:
    if workflow['name'] == '$workflow_name':
        sys.exit(0)
sys.exit(1)
"
}

# Get workflow description using Python
python_get_workflow_description() {
    local json_file="$1"
    local workflow_name="$2"
    python3 -c "
import json
with open('$json_file', 'r') as f:
    data = json.load(f)
for workflow in data['metagear']['workflows']['definitions']:
    if workflow['name'] == '$workflow_name':
        print(workflow.get('description', ''))
        break
"
}

# Get workflow parameters using Python
python_get_workflow_parameters() {
    local json_file="$1"
    local workflow_name="$2"
    python3 -c "
import json
with open('$json_file', 'r') as f:
    data = json.load(f)
for workflow in data['metagear']['workflows']['definitions']:
    if workflow['name'] == '$workflow_name':
        for param in workflow.get('parameters', []):
            print(json.dumps(param))
        break
"
}

# Get global parameters using Python
python_get_global_parameters() {
    local json_file="$1"
    python3 -c "
import json
with open('$json_file', 'r') as f:
    data = json.load(f)
for param in data['metagear']['workflows']['global_parameters']:
    print(json.dumps(param))
"
}

# Unified interface functions (factory pattern)
get_available_workflows() {
    python_get_available_workflows "$JSON_DEFINITIONS_FILE"
}

workflow_exists() {
    python_workflow_exists "$JSON_DEFINITIONS_FILE" "$1"
}

get_workflow_description() {
    python_get_workflow_description "$JSON_DEFINITIONS_FILE" "$1"
}

get_workflow_parameters() {
    python_get_workflow_parameters "$JSON_DEFINITIONS_FILE" "$1"
}

get_global_parameters() {
    python_get_global_parameters "$JSON_DEFINITIONS_FILE"
}

get_parameter_field() {
    local param_json="$1"
    local field="$2"
    echo "$param_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    result = data.get('$field', '')
    if isinstance(result, bool):
        print(str(result).lower())
    else:
        print(result)
except:
    print('')
"
}
