#!/usr/bin/env bash

# INSTALL_DIR is set in environment.

# Load platform-specific utilities (Linux/macOS)
source "$INSTALL_DIR/utilities/lib/system_utils.sh"
source "$INSTALL_DIR/utilities/lib/workflow_definitions.sh"

# Usage message
function usage() {
    echo ""
    echo "Usage: metagear <command> [options]"
    echo "Commands:"
    get_workflow_list
    echo ""
    exit 1
}


function check_command {
    # Check if the command exists in the JSON workflow definitions
    if [ -f "$INSTALL_DIR/utilities/lib/workflow_definitions.json" ]; then
        if ! workflow_exists "$1"; then
            echo "Error: Command '$1' not found."
            usage
            exit 1
        fi
    else
        echo "Error: workflow definitions file not found." >&2
        exit 1
    fi
}


check_requirements() {
    # Array to store error messages.
    local errors=()

    # Check Bash version 4+.
    if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        errors+=("Bash version 4 or higher is required (found version ${BASH_VERSINFO[0]}).")
    fi

    # Check for nextflow.
    if ! command -v nextflow >/dev/null 2>&1; then
        errors+=("Nextflow is not installed.")
    fi

    # Check for a container engine: either singularity or docker.
    if ! command -v singularity >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
        errors+=("Neither Singularity nor Docker is installed (one is required).")
    fi

    # If there are missing requirements, report them and exit.
    if [ ${#errors[@]} -gt 0 ]; then
        echo "---------------------------------------" >&2
        echo "The following requirements are missing:" >&2
        echo "---------------------------------------" >&2
        for error in "${errors[@]}"; do
            echo "   - $error" >&2
        done
        echo "---------------------------------------" >&2
        echo "Please install the missing requirements and try again." >&2
    fi

}



function check_metagear_home() {

    user_config_file=$INSTALL_DIR/metagear.config
    user_env_file=$INSTALL_DIR/metagear.env

    # Check if configuration files exist
    if [ ! -f "$user_config_file" ]; then
        echo "Error: Configuration file not found at $user_config_file" >&2
        echo "This suggests MetaGEAR was not properly installed." >&2
        echo "Please run the installation script again." >&2
        exit 1
    fi

    if [ ! -f "$user_env_file" ]; then
        echo "Error: Environment file not found at $user_env_file" >&2
        echo "This suggests MetaGEAR was not properly installed." >&2
        echo "Please run the installation script again." >&2
        exit 1
    fi

}



detect_container_tool() {
    # Check for singularity first and return it if found.
    if command -v singularity >/dev/null 2>&1; then
        echo "singularity"
    # Else check for docker and return it if found.
    elif command -v docker >/dev/null 2>&1; then
        echo "docker"
    # Return "none" if neither is available.
    else
        echo "Error: MetaGEAR requires Singularity (recommended) or Docker. Please install one of those in your system." >&2
        echo "  Singularity: https://docs.sylabs.io/guides/3.0/user-guide/installation.html" >&2
        echo "  Docker: https://docs.docker.com/engine/install/" >&2
        exit 1
    fi
}
