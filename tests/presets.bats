#!/usr/bin/env bats
#
# Presets: a named sequence of workflows, run in order against the same inputs.

setup() {
    temp_dir=$(mktemp -d)
    original_dir="$PWD"
    cd "$temp_dir"

    # An installation laid out the way main.sh expects to find one, as the other suites do.
    export INSTALL_DIR="$temp_dir/metagear_install"
    mkdir -p "$INSTALL_DIR/utilities/lib" "$INSTALL_DIR/latest/conf/metagear"
    cp -r "$BATS_TEST_DIRNAME/../lib/"* "$INSTALL_DIR/utilities/lib/"
    cp -r "$BATS_TEST_DIRNAME/../templates" "$INSTALL_DIR/utilities/"
    cp "$BATS_TEST_DIRNAME/../main.sh" "$INSTALL_DIR/utilities/"
    echo "// Test config" > "$INSTALL_DIR/latest/conf/metagear/base.config"
    echo "params { max_cpus = 4; max_memory = '8GB' }" > "$INSTALL_DIR/metagear.config"
    echo "export NXF_SINGULARITY_CACHEDIR=\$INSTALL_DIR/singularity_cache" > "$INSTALL_DIR/metagear.env"
    echo "RUN_PROFILES=\"-profile docker\"" >> "$INSTALL_DIR/metagear.env"
    echo "NF_WORK=\"./nf_work\"" >> "$INSTALL_DIR/metagear.env"

    source "$INSTALL_DIR/utilities/lib/workflow_definitions.sh"
}

teardown() {
    cd "$original_dir"
    rm -rf "$temp_dir"
}

@test "every preset names workflows that exist" {
    # A preset that names a workflow nobody ships is a command that fails four hours in, on the
    # step nobody was watching.
    for preset in $(get_presets); do
        for step in $(get_preset_steps "$preset"); do
            run workflow_exists "$step"
            [ "$status" -eq 0 ]
        done
    done
}

@test "the documented paths are offered" {
    run get_presets
    [ "$status" -eq 0 ]
    [[ "$output" =~ "genomes" ]]
    [[ "$output" =~ "microbiome" ]]
    [[ "$output" =~ "profiles" ]]
}

@test "the assembled path runs the four workflows in dependency order" {
    run get_preset_steps "genomes"
    [ "$status" -eq 0 ]
    # mag needs classification's bins and msp needs the gene catalog, so the order is not
    # cosmetic: reversing any of it means a step reading a directory that is not written yet.
    [ "$(echo "$output" | tr '\n' ' ')" = "genes classification mag msp " ]
}

@test "an unknown preset is not invented" {
    run get_preset_steps "not-a-preset"
    [ "$output" = "" ]
}

@test "a preset shows its plan without running anything" {
    run bash "$INSTALL_DIR/utilities/main.sh" genomes --input /tmp/none.csv --outdir /tmp/none --preview
    [ "$status" -eq 0 ]
    [[ "$output" =~ "step 1/4: genes" ]]
    [[ "$output" =~ "step 4/4: msp" ]]
    # Reuse is what makes a chain a chain; without it every step starts from the reads.
    [[ "$output" =~ "--reuse-outputs" ]]
    # Nothing was launched.
    [ ! -f "genes.config" ]
    [ ! -f "metagear_genes.sh" ]
}

@test "a preset explains itself" {
    run bash "$INSTALL_DIR/utilities/main.sh" microbiome --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: metagear microbiome" ]]
    [[ "$output" =~ "virus" ]]
}
