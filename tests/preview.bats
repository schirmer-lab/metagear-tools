#!/usr/bin/env bats

# Helper function to create test CSV file
create_test_csv() {
    cat > test.csv << EOF
sample,fastq_1,fastq_2
sample1,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
sample2,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz
sample3,/path/to/sample3_R1.fastq.gz,/path/to/sample3_R2.fastq.gz
EOF
}

# Helper function to setup development environment
setup_dev_environment() {
    export INSTALL_DIR="$BATS_TEST_DIRNAME/.."
    
    # Create a single symlink to the lib directory
    mkdir -p "$INSTALL_DIR/utilities"
    ln -sf "$INSTALL_DIR/lib" "$INSTALL_DIR/utilities/"
    ln -sf "$INSTALL_DIR/templates" "$INSTALL_DIR/utilities/"
    mkdir -p "$INSTALL_DIR/latest/conf/metagear"
    
    # Create configuration files to avoid first-time setup process
    cp "$INSTALL_DIR/templates/metagear.config" "$INSTALL_DIR/metagear.config"
    cp "$INSTALL_DIR/templates/metagear.env" "$INSTALL_DIR/metagear.env"
}

# Helper function to cleanup development environment
cleanup_dev_environment() {
    rm -rf "$INSTALL_DIR/utilities" 2>/dev/null || true
    rm -rf "$INSTALL_DIR/latest" 2>/dev/null || true
    rm -f "$INSTALL_DIR/metagear.config" 2>/dev/null || true
    rm -f "$INSTALL_DIR/metagear.env" 2>/dev/null || true
}

@test "main.sh qc_dna --preview creates script and shows preview mode message" {
    # 0) Create and change to temporary working directory
    temp_work_dir=$(mktemp -d)
    original_dir="$PWD"
    cd "$temp_work_dir"
    
    # 1) Create test.csv file with required columns and dummy values
    create_test_csv
    
    # 2) Set up environment variables and directory structure
    setup_dev_environment
    
    # 3) Run the command: ../main.sh qc_dna --input test.csv --preview
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_dna --input test.csv --preview
    
    # 4) Check that the command completed successfully
    [ "$status" -eq 0 ]
    
    # 5) Check that metagear_qc_dna.sh file has been created
    [ -f metagear_qc_dna.sh ]
    
    # 6) Check that "Preview mode" message is printed in the output
    [[ "$output" =~ "Preview mode" ]]
    
    # Clean up
    cd "$original_dir"
    rm -rf "$temp_work_dir"
    cleanup_dev_environment
}

@test "main.sh qc_dna with invalid parameter shows error message" {
    # 0) Create and change to temporary working directory
    temp_work_dir=$(mktemp -d)
    original_dir="$PWD"
    cd "$temp_work_dir"
    
    # 1) Create test.csv file with required columns and dummy values
    create_test_csv
    
    # 2) Set up environment variables and directory structure
    setup_dev_environment
    
    # 3) Run the command with invalid parameter: ../main.sh qc_dna --input test.csv --wrong-param value
    run bash "$BATS_TEST_DIRNAME/../main.sh" qc_dna --input test.csv --wrong-param value --preview
    
    # 4) Check that the error message contains "Invalid option: --wrong-param for qc_dna workflow."
    [[ "$output" =~ "Invalid option: --wrong-param for qc_dna workflow." ]]
    
    # Clean up
    cd "$original_dir"
    rm -rf "$temp_work_dir"
    cleanup_dev_environment
}
