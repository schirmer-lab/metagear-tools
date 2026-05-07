#!/usr/bin/env bats

# Setup function to create temporary environment and load workflow_definitions.sh
setup() {
    # Create temporary directory for this test
    export TEST_TEMP_DIR=$(mktemp -d)
    export ORIGINAL_PWD="$PWD"

    # Copy necessary files to temp directory
    cp -r "$BATS_TEST_DIRNAME/../lib" "$TEST_TEMP_DIR/"

    # Change to temp directory
    cd "$TEST_TEMP_DIR"

    # Set up environment variables for the temp location
    export SCRIPT_DIR="$TEST_TEMP_DIR"
    export JSON_DEFINITIONS_FILE="$TEST_TEMP_DIR/lib/workflow_definitions.json"

    # Source the workflow definitions from temp location
    source "$TEST_TEMP_DIR/lib/workflow_definitions.sh"
}

# Teardown function to clean up temporary files
teardown() {
    # Return to original directory
    cd "$ORIGINAL_PWD"

    # Clean up temporary directory
    rm -rf "$TEST_TEMP_DIR"
}

@test "get_available_workflows returns all workflows from JSON" {
    run get_available_workflows
    [ "$status" -eq 0 ]

    # Check that all expected workflows are returned
    [[ "$output" =~ "download_databases" ]]
    [[ "$output" =~ "qc_dna" ]]
    [[ "$output" =~ "qc_rna" ]]
    [[ "$output" =~ "microbial_profiles" ]]
    [[ "$output" =~ "gene_analysis" ]]

    # Count the number of workflows (should be 5)
    workflow_count=$(echo "$output" | wc -l)
    [ "$workflow_count" -eq 5 ]
}

@test "workflow_exists returns true for valid workflows" {
    run workflow_exists "qc_dna"
    [ "$status" -eq 0 ]

    run workflow_exists "microbial_profiles"
    [ "$status" -eq 0 ]
}

@test "workflow_exists returns false for invalid workflows" {
    run workflow_exists "nonexistent_workflow"
    [ "$status" -eq 1 ]

    run workflow_exists ""
    [ "$status" -eq 1 ]
}

@test "get_workflow_description returns correct description" {
    run get_workflow_description "qc_dna"
    [ "$status" -eq 0 ]
    [ "$output" = "Quality Control for DNA" ]

    run get_workflow_description "microbial_profiles"
    [ "$status" -eq 0 ]
    [ "$output" = "Get microbial profiles with MetaPhlAn and HUMAnN" ]
}

@test "get_workflow_description returns empty for nonexistent workflow" {
    run get_workflow_description "nonexistent_workflow"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "get_workflow_parameters returns correct parameters for qc_dna" {
    run get_workflow_parameters "qc_dna"
    [ "$status" -eq 0 ]

    # Should return one parameter (input)
    param_count=$(echo "$output" | wc -l)
    [ "$param_count" -eq 1 ]

    # Check that the parameter contains the expected fields (adjust for compact JSON from jq)
    [[ "$output" =~ "\"name\":\"input\"" ]]
    [[ "$output" =~ "\"required\":true" ]]
    [[ "$output" =~ "Input .csv file for quality control" ]]
}

@test "get_workflow_parameters returns correct parameters for gene_analysis" {
    run get_workflow_parameters "gene_analysis"
    [ "$status" -eq 0 ]

    # Should return two parameters (input and catalog)
    param_count=$(echo "$output" | wc -l)
    [ "$param_count" -eq 3 ]

    # Check for both parameters (adjust for compact JSON from jq)
    [[ "$output" =~ "\"name\":\"input\"" ]]
    [[ "$output" =~ "\"name\":\"contig_catalog\"" ]]
    [[ "$output" =~ "\"name\":\"metaphlan_profiles\"" ]]
}

@test "get_workflow_parameters returns empty for download_databases" {
    run get_workflow_parameters "download_databases"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "get_global_parameters returns all global parameters" {
    run get_global_parameters
    [ "$status" -eq 0 ]

    # Should return 3 global parameters
    param_count=$(echo "$output" | wc -l)
    [ "$param_count" -eq 4 ]

    # Check for expected global parameters (adjust for compact JSON from jq)
    [[ "$output" =~ "\"name\":\"outdir\"" ]]
    [[ "$output" =~ "\"name\":\"help\"" ]]
    [[ "$output" =~ "\"name\":\"debug\"" ]]
    [[ "$output" =~ "\"name\":\"config\"" ]]
    [[ "$output" =~ "\"default\":\"results\"" ]]
    [[ "$output" =~ "\"default\":false" ]]
}

@test "validate_workflow_and_parameters accepts valid parameters" {
    run validate_workflow_and_parameters "qc_dna" --input "test.csv" --outdir "results"
    [ "$status" -eq 0 ]

    # Check that output contains expected parameter assignments
    [[ "$output" =~ "input=test.csv" ]]
    [[ "$output" =~ "outdir=results" ]]
}

@test "validate_workflow_and_parameters rejects invalid workflow" {
    run validate_workflow_and_parameters "nonexistent_workflow" --input "test.csv"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Workflow 'nonexistent_workflow' not found." ]]
}

@test "validate_workflow_and_parameters rejects invalid parameters" {
    run validate_workflow_and_parameters "qc_dna" --input "test.csv" --invalid-param "value"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Invalid option: --invalid-param for qc_dna workflow." ]]
}

@test "validate_workflow_and_parameters requires mandatory parameters" {
    run validate_workflow_and_parameters "qc_dna" --outdir "results"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: --input is required for qc_dna workflow." ]]
}

@test "validate_workflow_and_parameters accepts global parameters" {
    run validate_workflow_and_parameters "qc_dna" --input "test.csv" --debug "true" --help ""
    [ "$status" -eq 0 ]

    # Check that global parameters are included
    [[ "$output" =~ "debug=true" ]]
    [[ "$output" =~ "help=" ]]
    [[ "$output" =~ "input=test.csv" ]]
}

@test "validate_workflow_and_parameters applies default values" {
    run validate_workflow_and_parameters "qc_dna" --input "test.csv"
    [ "$status" -eq 0 ]

    # Should include default outdir and debug values
    [[ "$output" =~ "outdir=results" ]]
    [[ "$output" =~ "debug=false" ]]
    [[ "$output" =~ "input=test.csv" ]]
}

@test "validate_workflow_and_parameters handles workflow with no specific parameters" {
    run validate_workflow_and_parameters "download_databases" --outdir "custom_dir"
    [ "$status" -eq 0 ]

    # Should only have global parameters
    [[ "$output" =~ "outdir=custom_dir" ]]
    [[ "$output" =~ "debug=false" ]]
}

@test "validate_workflow_and_parameters rejects parameter without value" {
    run validate_workflow_and_parameters "qc_dna" --input
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Option --input requires a value." ]]
}

@test "get_workflow_list displays workflows with descriptions" {
    run get_workflow_list
    [ "$status" -eq 0 ]

    # Check that all workflows are listed with descriptions
    [[ "$output" =~ "download_databases" ]]
    [[ "$output" =~ "Install Databases" ]]
    [[ "$output" =~ "qc_dna" ]]
    [[ "$output" =~ "Quality Control for DNA" ]]
    [[ "$output" =~ "microbial_profiles" ]]
    [[ "$output" =~ "MetaPhlAn and HUMAnN" ]]

    # Count lines (should be 5 workflows)
    workflow_count=$(echo "$output" | wc -l)
    [ "$workflow_count" -eq 5 ]
}

@test "JSON file exists and is readable" {
    [ -f "$JSON_DEFINITIONS_FILE" ]
    [ -r "$JSON_DEFINITIONS_FILE" ]

    # Verify JSON is valid
    run python3 -c "import json; json.load(open('$JSON_DEFINITIONS_FILE'))"
    [ "$status" -eq 0 ]
}

@test "JSON parser is correctly detected and loaded" {
    # Verify that a JSON parser was loaded
    [[ -n "$JSON_PARSER" ]]

    # Should be either "jq" or "python"
    [[ "$JSON_PARSER" = "jq" || "$JSON_PARSER" = "python" ]]

    # If jq is available, it should be preferred
    if command -v jq >/dev/null 2>&1; then
        [ "$JSON_PARSER" = "jq" ]
    else
        [ "$JSON_PARSER" = "python" ]
    fi
}

@test "JSON parser modules are available" {
    # Check that parser modules exist in temp directory
    [ -f "$TEST_TEMP_DIR/lib/json_parser_jq.sh" ]
    [ -f "$TEST_TEMP_DIR/lib/json_parser_python.sh" ]

    # Verify they are executable/sourceable
    run bash -n "$TEST_TEMP_DIR/lib/json_parser_jq.sh"
    [ "$status" -eq 0 ]

    run bash -n "$TEST_TEMP_DIR/lib/json_parser_python.sh"
    [ "$status" -eq 0 ]
}
