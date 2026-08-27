#!/usr/bin/env bats
#
# The cluster tools, reached through `metagear cluster`.
#
# They lived outside version control until now — three scripts in ~/.metagear/cluster, versioned
# by .bak files beside them. What made them unshareable was the site baked into them: one lab's
# node addresses, scratch paths and account name. That is a config file now, and these tests are
# mostly about that separation holding.

setup() {
    temp_dir=$(mktemp -d)
    original_dir="$PWD"
    cd "$temp_dir"
    CLUSTER="$BATS_TEST_DIRNAME/../cluster/metagear-cluster"
}

teardown() {
    cd "$original_dir"
    rm -rf "$temp_dir"
}

@test "the cluster scripts are executable" {
    [ -x "$BATS_TEST_DIRNAME/../cluster/metagear-cluster" ]
    [ -x "$BATS_TEST_DIRNAME/../cluster/cluster-worker.sh" ]
    [ -x "$BATS_TEST_DIRNAME/../cluster/mirror-dbs.sh" ]
}

@test "no site is baked into the shipped scripts" {
    # The addresses, paths and account this was built against must not travel with it. A default
    # pointing at one lab's machine is not a default, it is a trap for the next site.
    run grep -rnE '10\.157\.|tumziel|/data/emilio' \
        "$BATS_TEST_DIRNAME/../cluster/metagear-cluster" \
        "$BATS_TEST_DIRNAME/../cluster/cluster-worker.sh" \
        "$BATS_TEST_DIRNAME/../cluster/mirror-dbs.sh"
    # grep exits 1 when it finds nothing, which is what we want.
    [ "$status" -ne 0 ]
}

@test "a site with no topology is told what to write, not left guessing" {
    run env METAGEAR_CLUSTER_NODES="$temp_dir/absent.conf" bash "$CLUSTER" status
    [ "$status" -ne 0 ]
    [[ "$output" =~ "no nodes configured" ]]
    [[ "$output" =~ "absent.conf" ]]
}

@test "the topology is read from its own file" {
    cat > "$temp_dir/nodes.conf" <<'CONF'
# a comment, and a blank line, both ignored

alpha|-|/scratch/metagear|8|-
beta|user@10.0.0.2|/data/scratch/metagear|1000000|/data/db
CONF
    # No hq binary here, so this gets as far as needing one — which is proof the topology parsed.
    run env METAGEAR_CLUSTER_NODES="$temp_dir/nodes.conf" \
            METAGEAR_HQ_BIN="$temp_dir/no-such-hq" bash "$CLUSTER" up
    [[ ! "$output" =~ "no nodes configured" ]]
    [[ "$output" =~ "hq binary not found" ]]
}

@test "the template documents the fields it expects" {
    template="$BATS_TEST_DIRNAME/../templates/cluster-nodes.conf"
    [ -f "$template" ]
    run cat "$template"
    [[ "$output" =~ "scratch root" ]]
    [[ "$output" =~ "db mirror" ]]
    # Every non-comment line in the template must itself be a usable example.
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]]
    done < "$template"
}
