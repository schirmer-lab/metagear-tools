#!/usr/bin/env bash
set -euo pipefail

# Factory-style loader for platform-specific implementations
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

case "$(uname)" in
    Linux)
        source "$SCRIPT_DIR/system_utils_linux.sh"
        ;;
    Darwin)
        source "$SCRIPT_DIR/system_utils_mac.sh"
        ;;
    *)
        # Fallback implementations
        get_total_memory_gb() { echo "0"; }
        get_cpu_count() { echo "1"; }
        ;;
esac

