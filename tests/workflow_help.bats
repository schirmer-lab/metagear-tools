#!/usr/bin/env bats

setup() {
    # Create temporary test directory
    temp_dir=$(mktemp -d)
    original_dir="$PWD"
    cd "$temp_dir"

    # Set up test environment that mimics an installed MetaGEAR
    export INSTALL_DIR="$temp_dir/metagear_install"
    mkdir -p "$INSTALL_DIR"

    # Create utilities directory structure
    mkdir -p "$INSTALL_DIR/utilities/lib"
    cp -r "$BATS_TEST_DIRNAME/../lib/"* "$INSTALL_DIR/utilities/lib/"
    cp -r "$BATS_TEST_DIRNAME/../templates" "$INSTALL_DIR/utilities/"

    # Create a minimal pipeline directory
    mkdir -p "$INSTALL_DIR/latest/conf/metagear"
    echo "// Test config" > "$INSTALL_DIR/latest/conf/metagear/base.config"

    # Create config and env files to avoid check_metagear_home failures
    echo "params { max_cpus = 4; max_memory = '8GB' }" > "$INSTALL_DIR/metagear.config"
    echo "export NXF_SINGULARITY_CACHEDIR=\$INSTALL_DIR/singularity_cache" > "$INSTALL_DIR/metagear.env"
    echo "RUN_PROFILES=\"-profile docker\"" >> "$INSTALL_DIR/metagear.env"
    echo "NF_WORK=\"./nf_work\"" >> "$INSTALL_DIR/metagear.env"
}

teardown() {
    cd "$original_dir"
    rm -rf "$temp_dir"
}

@test "qc_dna --help shows help and doesn't trigger pipeline" {
    # Run qc_dna --help
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_dna --help

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output contains expected elements
    [[ "$output" =~ "Usage: metagear qc_dna" ]]
    [[ "$output" =~ "Quality Control for DNA" ]]
    [[ "$output" =~ "--input" ]]
    [[ "$output" =~ "Input .csv file for quality control" ]]
    [[ "$output" =~ "Global parameters:" ]]
    [[ "$output" =~ "--outdir" ]]

    # Check that no pipeline files were created in working directory
    [ ! -f "qc_dna.config" ]
    [ ! -f "metagear_qc_dna.sh" ]
    [ ! -f "input_qc_dna.csv" ]
    [ ! -d "results" ]
}

@test "microbial_profiles --help shows help and doesn't trigger pipeline" {
    # Run microbial_profiles --help
    run bash "$BATS_TEST_DIRNAME/../main.sh" microbial_profiles --help

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output contains expected elements
    [[ "$output" =~ "Usage: metagear microbial_profiles" ]]
    [[ "$output" =~ "Get microbial profiles with MetaPhlAn and HUMAnN" ]]
    [[ "$output" =~ "--input" ]]
    [[ "$output" =~ "Input .csv file for microbial profiles" ]]

    # Check that no pipeline files were created
    [ ! -f "microbial_profiles.config" ]
    [ ! -f "metagear_microbial_profiles.sh" ]
    [ ! -f "input_microbial_profiles.csv" ]
    [ ! -d "results" ]
}

@test "gene_analysis --help shows help and doesn't trigger pipeline" {
    # Run gene_analysis --help
    run bash "$BATS_TEST_DIRNAME/../main.sh" gene_analysis --help

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output contains expected elements
    [[ "$output" =~ "Usage: metagear gene_analysis" ]]
    [[ "$output" =~ "Gene centric analysis workflow" ]]
    [[ "$output" =~ "--input" ]]
    [[ "$output" =~ "--contig_catalog" ]]
    [[ "$output" =~ "Contigs catalog" ]]

    # Check that no pipeline files were created
    [ ! -f "gene_analysis.config" ]
    [ ! -f "metagear_gene_analysis.sh" ]
    [ ! -f "input_gene_analysis.csv" ]
    [ ! -d "results" ]
}

@test "download_databases --help shows help and doesn't trigger pipeline" {
    # Run download_databases --help
    run bash "$BATS_TEST_DIRNAME/../main.sh" download_databases --help

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output contains expected elements
    [[ "$output" =~ "Usage: metagear download_databases" ]]
    [[ "$output" =~ "Install Databases" ]]
    [[ "$output" =~ "Kneaddata" ]]
    [[ "$output" =~ "MetaPhlAn" ]]
    [[ "$output" =~ "HUMAnN" ]]

    # Check that no pipeline files were created
    [ ! -f "download_databases.config" ]
    [ ! -f "metagear_download_databases.sh" ]
    [ ! -f "input_download_databases.csv" ]
    [ ! -d "results" ]
}

@test "qc_rna --help shows help and doesn't trigger pipeline" {
    # Run qc_rna --help
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_rna --help

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output contains expected elements
    [[ "$output" =~ "Usage: metagear qc_rna" ]]
    [[ "$output" =~ "Quality Control for RNA" ]]
    [[ "$output" =~ "--input" ]]
    [[ "$output" =~ "Input .csv file for quality control" ]]

    # Check that no pipeline files were created
    [ ! -f "qc_rna.config" ]
    [ ! -f "metagear_qc_rna.sh" ]
    [ ! -f "input_qc_rna.csv" ]
    [ ! -d "results" ]
}

@test "help flag variations work consistently" {
    # Test different help flag formats

    # Test --help
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_dna --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: metagear qc_dna" ]]

    # Test -help
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_dna -help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: metagear qc_dna" ]]
}

@test "help flag works with other parameters (should still show help)" {
    # Test that help flag takes precedence over other parameters
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_dna --input test.csv --help --outdir custom

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: metagear qc_dna" ]]

    # Check that no pipeline files were created despite other parameters
    [ ! -f "qc_dna.config" ]
    [ ! -f "metagear_qc_dna.sh" ]
    [ ! -f "input_qc_dna.csv" ]
    [ ! -f "test.csv" ]
    [ ! -d "custom" ]
}

@test "invalid workflow with --help shows error" {
    # Test that invalid workflow names show appropriate error
    run bash "$BATS_TEST_DIRNAME/../main.sh" invalid_workflow --help

    # Should fail because workflow doesn't exist
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Error:" ]]
}

@test "qc_dna without parameters shows help" {
    # Run qc_dna without any parameters
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_dna

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output contains expected elements
    [[ "$output" =~ "Usage: metagear qc_dna" ]]
    [[ "$output" =~ "Quality Control for DNA" ]]
    [[ "$output" =~ "--input" ]]
    [[ "$output" =~ "Input .csv file for quality control" ]]
    [[ "$output" =~ "Global parameters:" ]]
    [[ "$output" =~ "--outdir" ]]

    # Check that no pipeline files were created in working directory
    [ ! -f "qc_dna.config" ]
    [ ! -f "metagear_qc_dna.sh" ]
    [ ! -f "input_qc_dna.csv" ]
    [ ! -d "results" ]
}

@test "microbial_profiles without parameters shows help" {
    # Run microbial_profiles without any parameters
    run bash "$BATS_TEST_DIRNAME/../main.sh" microbial_profiles

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output contains expected elements
    [[ "$output" =~ "Usage: metagear microbial_profiles" ]]
    [[ "$output" =~ "Get microbial profiles with MetaPhlAn and HUMAnN" ]]
    [[ "$output" =~ "--input" ]]
    [[ "$output" =~ "Input .csv file for microbial profiles" ]]

    # Check that no pipeline files were created
    [ ! -f "microbial_profiles.config" ]
    [ ! -f "metagear_microbial_profiles.sh" ]
    [ ! -f "input_microbial_profiles.csv" ]
    [ ! -d "results" ]
}

@test "gene_analysis without parameters shows help" {
    # Run gene_analysis without any parameters
    run bash "$BATS_TEST_DIRNAME/../main.sh" gene_analysis

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output contains expected elements
    [[ "$output" =~ "Usage: metagear gene_analysis" ]]
    [[ "$output" =~ "Gene centric analysis workflow" ]]
    [[ "$output" =~ "--input" ]]
    [[ "$output" =~ "--contig_catalog" ]]
    [[ "$output" =~ "Contigs catalog" ]]

    # Check that no pipeline files were created
    [ ! -f "gene_analysis.config" ]
    [ ! -f "metagear_gene_analysis.sh" ]
    [ ! -f "input_gene_analysis.csv" ]
    [ ! -d "results" ]
}

@test "download_databases without parameters executes workflow (no required params)" {
    # Run download_databases without any parameters - should execute, not show help
    run bash "$BATS_TEST_DIRNAME/../main.sh" download_databases --preview

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that it DOES NOT show help output (since no required params)
    [[ ! "$output" =~ "Usage: metagear download_databases" ]]

    # Instead, should show that it's trying to execute (preview mode or execution)
    # The pipeline files should be created
    [ -f "download_databases.config" ]
    [ -f "metagear_download_databases.sh" ]
}

@test "qc_rna without parameters shows help" {
    # Run qc_rna without any parameters
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_rna

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output contains expected elements
    [[ "$output" =~ "Usage: metagear qc_rna" ]]
    [[ "$output" =~ "Quality Control for RNA" ]]
    [[ "$output" =~ "--input" ]]
    [[ "$output" =~ "Input .csv file for quality control" ]]

    # Check that no pipeline files were created
    [ ! -f "qc_rna.config" ]
    [ ! -f "metagear_qc_rna.sh" ]
    [ ! -f "input_qc_rna.csv" ]
    [ ! -d "results" ]
}

@test "command with only --preview still shows help" {
    # Test that --preview alone (without other parameters) shows help for workflows with required params
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_dna --preview

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Check that help output is shown instead of executing pipeline
    [[ "$output" =~ "Usage: metagear qc_dna" ]]
    [[ "$output" =~ "Quality Control for DNA" ]]

    # Check that no pipeline files were created
    [ ! -f "qc_dna.config" ]
    [ ! -f "metagear_qc_dna.sh" ]
    [ ! -f "input_qc_dna.csv" ]
    [ ! -d "results" ]
}

@test "download_databases with --preview executes in preview mode" {
    # Test that --preview with download_databases shows preview (since no required params)
    run bash "$BATS_TEST_DIRNAME/../main.sh" download_databases --preview

    # Check that command succeeded
    [ "$status" -eq 0 ]

    # Should NOT show help, but should show preview mode
    [[ ! "$output" =~ "Usage: metagear download_databases" ]]
    [[ "$output" =~ "Preview mode" ]]

    # Pipeline files should be created for preview
    [ -f "download_databases.config" ]
    [ -f "metagear_download_databases.sh" ]
}
