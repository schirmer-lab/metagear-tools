#!/usr/bin/env bats
#
# The two JSON backends must answer identically. jq is chosen whenever it exists, so the Python
# fallback is the one nothing exercises — a broken function there stays hidden until it is the
# only one available.

setup() {
    export JSON_DEFINITIONS_FILE="$BATS_TEST_DIRNAME/../lib/workflow_definitions.json"
    export JSON_PRESETS_FILE="$JSON_DEFINITIONS_FILE"
    LIB="$BATS_TEST_DIRNAME/../lib"
}

ask() {   # ask <backend> <function> [arg]
    bash -c "
        JSON_DEFINITIONS_FILE='$JSON_DEFINITIONS_FILE'
        JSON_PRESETS_FILE='$JSON_PRESETS_FILE'
        source '$LIB/json_parser_$1.sh'
        $2 ${3:-}
    "
}

@test "both backends define the same public interface" {
    for fn in get_available_workflows workflow_exists get_workflow_description \
              get_workflow_parameters get_global_parameters get_parameter_field \
              get_presets get_preset_steps get_preset_description; do
        run ask jq "type -t $fn"
        [ "$output" = "function" ]
        run ask python "type -t $fn"
        [ "$output" = "function" ]
    done
}

@test "no function is defined twice in either backend" {
    # A duplicate means an edit landed inside an existing definition: the later one silently wins
    # and the earlier body is orphaned.
    for backend in jq python; do
        run bash -c "grep -oE '^[a-z_]+\(\)' '$LIB/json_parser_$backend.sh' | sort | uniq -d"
        [ -z "$output" ]
    done
}

@test "both backends list the same workflows" {
    run ask jq get_available_workflows
    jq_out="$output"
    run ask python get_available_workflows
    [ "$output" = "$jq_out" ]
}

@test "both backends list the same presets and steps" {
    run ask jq get_presets
    jq_out="$output"
    run ask python get_presets
    [ "$output" = "$jq_out" ]

    run ask jq get_preset_steps genomes
    jq_steps="$output"
    run ask python get_preset_steps genomes
    [ "$output" = "$jq_steps" ]
}

@test "both backends agree on whether a workflow exists" {
    run ask jq "workflow_exists genes && echo yes || echo no"
    [ "$output" = "yes" ]
    run ask python "workflow_exists genes && echo yes || echo no"
    [ "$output" = "yes" ]
    run ask python "workflow_exists not_a_workflow && echo yes || echo no"
    [ "$output" = "no" ]
}
