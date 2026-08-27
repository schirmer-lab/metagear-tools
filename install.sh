#!/usr/bin/env bash
set -euo pipefail

# Color codes for terminal output
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
RESET=$(tput sgr0)

# Function to show usage information
show_usage() {
    echo "MetaGEAR Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --install-dir <path>     Specify custom installation directory (default: ~/.metagear)"
    echo "  --pipeline <path|version> Use local pipeline directory OR specify version to install"
    echo "                           Examples: --pipeline /path/to/pipeline OR --pipeline 1.0"
    echo "  --utilities <path>       Use custom utilities repository path"
    echo "  --help, -h              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Install latest release"
    echo "  $0 --pipeline 1.0                    # Install specific version"
    echo "  $0 --pipeline /path/to/pipeline       # Use local development pipeline"
    echo "  $0 --install-dir /opt/metagear        # Custom installation directory"
    echo ""
}

# 1) Config
INSTALL_DIR="${HOME}/.metagear"
ORGANIZATION="schirmer-lab"
PIPELINE_REPOSITORY="metagear-pipeline"
PIPELINE_VERSION=""  # Will be set to latest release or user-specified version
UTILS_REPOSITORY="metagear-tools"
SCRIPT="main.sh"

# Function to get the latest release version from GitHub API
get_latest_release() {
    local org="$1"
    local repo="$2"
    local api_url="https://api.github.com/repos/${org}/${repo}/releases/latest"
    
    # Try to get latest release using wget
    if command -v wget >/dev/null 2>&1; then
        latest_version=$(wget -qO- "$api_url" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' | head -1)
    elif command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -s "$api_url" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' | head -1)
    else
        echo "Error: Neither wget nor curl is available for downloading" >&2
        return 1
    fi
    
    if [[ -n "$latest_version" ]]; then
        echo "$latest_version"
        return 0
    else
        echo "Error: Could not retrieve latest release information" >&2
        return 1
    fi
}

# Function to check if a version exists as a release
# 0 exists, 1 does not, 2 could not tell. The third matters: the anonymous API allowance is sixty
# requests an hour, and reporting exhaustion as "does not exist" is a lie about a real release.
check_version_exists() {
    local org="$1"
    local repo="$2"
    local version="$3"
    local api_url="https://api.github.com/repos/${org}/${repo}/releases/tags/${version}"
    local code=""

    if command -v curl >/dev/null 2>&1; then
        code="$(curl -s -o /dev/null -w '%{http_code}' "$api_url" 2>/dev/null || true)"
    elif command -v wget >/dev/null 2>&1; then
        # wget prints the status line to stderr; the last response code is the one that counts.
        code="$(wget -q -S --spider "$api_url" 2>&1 | awk '/^  HTTP\//{c=$2} END{print c}' || true)"
    fi

    case "$code" in
        200) return 0 ;;
        404) return 1 ;;
        *)   return 2 ;;   # 403 rate limit, 5xx, no network, no client
    esac
}

WRAPPER_NAME="metagear"
WRAPPER_PATH="${PWD}/${WRAPPER_NAME}"

# Optional development pipeline path
CUSTOM_PIPELINE_PATH=""

# Optional custom utilities repository
CUSTOM_UTILS_PATH=""

# Parse optional arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_usage
      exit 0
      ;;
    --install-dir)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --install-dir requires a path argument" >&2
        exit 1
      fi
      INSTALL_DIR="$(realpath "$1")"
      shift
      ;;
    --pipeline)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --pipeline requires a path or version argument" >&2
        exit 1
      fi
      # Check if the argument is a directory path or a version
      if [[ -d "$1" ]]; then
        # It's a directory path
        CUSTOM_PIPELINE_PATH="$(realpath "$1")"
      else
        # It's a version specification
        PIPELINE_VERSION="$1"
      fi
      shift
      ;;
    --utilities)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --utilities requires a repository argument" >&2
        exit 1
      fi
      CUSTOM_UTILS_PATH="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# Set PIPELINE_VERSION to latest release if not specified
if [[ -z "$PIPELINE_VERSION" && -z "$CUSTOM_PIPELINE_PATH" ]]; then
    echo "Getting latest release information..."
    if PIPELINE_VERSION=$(get_latest_release "$ORGANIZATION" "$PIPELINE_REPOSITORY"); then
        echo "Found latest release: $PIPELINE_VERSION"
    else
        echo "Warning: Could not get latest release, falling back to version 1.0"
        PIPELINE_VERSION="1.0"
    fi
elif [[ -n "$PIPELINE_VERSION" && -z "$CUSTOM_PIPELINE_PATH" ]]; then
    # Validate that the specified version exists
    echo "Checking if version $PIPELINE_VERSION exists..."
    # `|| version_check=$?` because errexit is on: a bare call that returns non-zero ends the
    # script before the case below ever sees which non-zero it was.
    version_check=0
    check_version_exists "$ORGANIZATION" "$PIPELINE_REPOSITORY" "$PIPELINE_VERSION" || version_check=$?
    case $version_check in
        0) echo "Version $PIPELINE_VERSION confirmed" ;;
        1) echo "Error: Version $PIPELINE_VERSION does not exist as a release" >&2; exit 1 ;;
        # Refusing to install would be worse than trying: the download below says plainly whether
        # the release is there, and the commonest reason for landing here is the anonymous API
        # allowance, which has nothing to do with whether this version exists.
        *) echo "  Could not reach the GitHub API to confirm it; continuing anyway." >&2 ;;
    esac
fi


# 2) Prepare install directory
mkdir -p "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"/downloads

# Welcome message
echo "Welcome to the MetaGEAR installation script!"
if [[ -n "$CUSTOM_PIPELINE_PATH" ]]; then
    echo "This script will install MetaGEAR from local path: $CUSTOM_PIPELINE_PATH"
else
    echo "This script will install MetaGEAR v${PIPELINE_VERSION} and its utilities."
fi
echo ""

# 3) Install utilities
echo "${GREEN}→ Setting Up MetaGEAR utilities${RESET}"

rm -rf "${INSTALL_DIR}/utilities"

if [[ -n "${CUSTOM_UTILS_PATH}" ]]; then # If utilities path is provided, we use it directly
  echo "  Using custom utilities directoy: ${CUSTOM_UTILS_PATH}"
  ln -s "${CUSTOM_UTILS_PATH}" "${INSTALL_DIR}/utilities"

else # Otherwise, download the default utilities
  echo "  Downloading MetaGEAR utilities from default repository..."
  UTILS_ZIP_URL="https://github.com/${ORGANIZATION}/${UTILS_REPOSITORY}/archive/refs/heads/main.zip"
  UTILS_TMP_ZIP="${INSTALL_DIR}/downloads/utilities.zip"
  UTILS_EXTRACTED_DIR="${INSTALL_DIR}/downloads/utilities"

  wget -qO "${UTILS_TMP_ZIP}" "${UTILS_ZIP_URL}"
  echo "  Extracting to ${UTILS_EXTRACTED_DIR}"
  unzip -qo "${UTILS_TMP_ZIP}" -d "${UTILS_EXTRACTED_DIR}"

  mv ${UTILS_EXTRACTED_DIR}/metagear-tools-main ${INSTALL_DIR}/utilities
fi


# 4) Install the Pipeline
echo ""
echo "${GREEN}→ Installing MetaGEAR${RESET}"

rm -rf "${INSTALL_DIR}/latest"

if [[ -n "${CUSTOM_PIPELINE_PATH}" ]]; then # If pipeline path is provided, we use it directly
  echo "  Using custom pipeline directory: ${CUSTOM_PIPELINE_PATH}"
  ln -s "${CUSTOM_PIPELINE_PATH}" "${INSTALL_DIR}/latest"

else # Otherwise, download the default pipeline
  echo "  Installing v${PIPELINE_VERSION} from GitHub"

  EXTRACTED_DIR="${INSTALL_DIR}/downloads/v${PIPELINE_VERSION}"
  PIPELINE_DIR="${INSTALL_DIR}/v${PIPELINE_VERSION}"

  ZIP_URL="https://github.com/${ORGANIZATION}/${PIPELINE_REPOSITORY}/archive/refs/tags/${PIPELINE_VERSION}.zip"
  TMP_ZIP="${INSTALL_DIR}/downloads/metagear-${PIPELINE_VERSION}.zip"

  rm -rf "${PIPELINE_DIR}"

  wget -qO "${TMP_ZIP}" "${ZIP_URL}"

  echo "  Extracting to ${EXTRACTED_DIR}"
  unzip -qo "${TMP_ZIP}" -d "${EXTRACTED_DIR}"
  mv ${EXTRACTED_DIR}/${PIPELINE_REPOSITORY}-${PIPELINE_VERSION} ${PIPELINE_DIR}

  ln -s "${PIPELINE_DIR}" "${INSTALL_DIR}/latest"

fi


# 5) Create the relocatable wrapper
#
# ~/.local/bin: the stock ~/.profile adds it when it exists, but only at login — so whether it is
# on PATH right now is checked below rather than assumed.
BIN_DIR="${METAGEAR_BIN_DIR:-${HOME}/.local/bin}"
mkdir -p "${BIN_DIR}"
WRAPPER_PATH="${BIN_DIR}/${WRAPPER_NAME}"

cat > "${WRAPPER_PATH}" << EOF
#!/usr/bin/env bash
export INSTALL_DIR="${INSTALL_DIR}"
exec "\${INSTALL_DIR}/utilities/${SCRIPT}" "\$@"
EOF
chmod +x "${WRAPPER_PATH}"

# 5b) Install the cluster tools. Copied rather than symlinked because they keep state beside
#     themselves; nodes.conf is this site's topology and is never overwritten.
if [ -d "${INSTALL_DIR}/utilities/cluster" ]; then
  mkdir -p "${INSTALL_DIR}/cluster"
  cp "${INSTALL_DIR}/utilities/cluster/metagear-cluster" \
     "${INSTALL_DIR}/utilities/cluster/cluster-worker.sh" \
     "${INSTALL_DIR}/utilities/cluster/mirror-dbs.sh" "${INSTALL_DIR}/cluster/"
  chmod +x "${INSTALL_DIR}/cluster/metagear-cluster" \
           "${INSTALL_DIR}/cluster/cluster-worker.sh" \
           "${INSTALL_DIR}/cluster/mirror-dbs.sh"
  if [ ! -f "${INSTALL_DIR}/cluster/nodes.conf" ]; then
    cp "${INSTALL_DIR}/utilities/templates/cluster-nodes.conf" "${INSTALL_DIR}/cluster/nodes.conf"
    echo "  Cluster tools installed. Describe this site's machines in"
    echo "    ${INSTALL_DIR}/cluster/nodes.conf"
    echo "  before running 'metagear cluster up'."
  else
    echo "  Cluster tools updated (nodes.conf left as it was)."
  fi
fi

# 6) Create configuration files
echo ""
echo "${GREEN}→ Creating configuration files${RESET}"

# Load system utilities to get system information
source "${INSTALL_DIR}/utilities/lib/system_utils.sh"

user_config_file="${INSTALL_DIR}/metagear.config"
user_env_file="${INSTALL_DIR}/metagear.env"

total_cpu_count=$(get_cpu_count)
total_memory_gb=$(get_total_memory_gb)

echo "  - Found ${total_cpu_count} CPUs and ${total_memory_gb} GB of Memory in the system."

if (( total_cpu_count < 48 )) && (( $(printf '%.0f' "$total_memory_gb") < 80 )); then
    default_cpu_count=$(( total_cpu_count * 80 / 100 ))
    if (( default_cpu_count < 1 )); then
        default_cpu_count=1
    fi
    default_memory_gb=$(awk -v mem="$total_memory_gb" 'BEGIN{printf "%.0f", mem*0.8}')
else
    default_cpu_count=48
    default_memory_gb=80
fi

echo "  - MetaGEAR will use ${default_cpu_count} CPUs and ${default_memory_gb} GB of Memory."

# Export variables for envsubst
export INSTALL_DIR="${INSTALL_DIR}"
export MAX_CPUS="${default_cpu_count}"
export MAX_MEMORY="${default_memory_gb}"

# Create configuration file with environment variable substitution
if [[ -f "$user_config_file" ]]; then
    echo "  - Configuration file already exists, skipping: ${INSTALL_DIR}/metagear.config"
else
    envsubst < "${INSTALL_DIR}/utilities/templates/metagear.config" > "$user_config_file"
    echo "  - User configuration created: ${INSTALL_DIR}/metagear.config"
fi

# Create environment file with INSTALL_DIR substitution
if [[ -f "$user_env_file" ]]; then
    echo "  - Environment file already exists, skipping: ${INSTALL_DIR}/metagear.env"
else
    envsubst < "${INSTALL_DIR}/utilities/templates/metagear.env" > "$user_env_file"
    echo "  - Environment file created: ${INSTALL_DIR}/metagear.env"
fi

# Create per-user resource override stub (skip if it already exists so users
# don't lose their tuned values on re-install). main.sh regenerates
# $INSTALL_DIR/resources.config from this YAML on every invocation.
user_resources_yaml="${INSTALL_DIR}/resources.yaml"
if [[ -f "$user_resources_yaml" ]]; then
    echo "  - Resources YAML already exists, skipping: ${user_resources_yaml}"
else
    cp "${INSTALL_DIR}/utilities/templates/resources.yaml" "$user_resources_yaml"
    echo "  - Resources YAML stub created: ${user_resources_yaml}"
fi

# Record install-time build number (YYMMDD). Read by `metagear --version`.
# Always overwritten on re-install so the build advances with each install.
BUILD_NUMBER="$(date +%y%m%d)"
echo "${BUILD_NUMBER}" > "${INSTALL_DIR}/.build"
echo "  - Build number: ${BUILD_NUMBER}"

# Check dependencies and provide informational warnings
echo ""
echo "${GREEN}→ Checking runtime dependencies${RESET}"

dep_missing=false

# Check Bash version 4+
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "  ⚠ WARNING: Bash version 4 or higher is required (found version ${BASH_VERSINFO[0]})" >&2
    dep_missing=true
fi

# Check for nextflow
if ! command -v nextflow >/dev/null 2>&1; then
    echo "  ⚠ WARNING: Nextflow is not installed"
    dep_missing=true
fi

# Check for container engines
if ! command -v singularity >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
    echo "  ⚠ WARNING: Neither Singularity nor Docker is installed (one is required)"
    dep_missing=true
fi

if [ "$dep_missing" = false ]; then
    echo "  ✓ All runtime dependencies are available"
fi

# 7) Remove temporary files
rm -rf "${INSTALL_DIR}/downloads"


# 8) Done
echo
echo "${GREEN}✔ Installed MetaGEAR Pipeline${RESET}"
echo "  • Installation directory: ${INSTALL_DIR}"
echo "    - Pipeline"
echo "    - Utilities"
echo "    - Configuration files"
echo ""
echo "${YELLOW}Next steps:${RESET}"
# Say which of the two situations this is, rather than giving advice that may already be done.
case ":${PATH}:" in
  *":${BIN_DIR}:"*)
    echo "  • Run 'metagear --help' to start using MetaGEAR"
    ;;
  *)
    echo "  • ${WRAPPER_NAME} is installed at ${WRAPPER_PATH}, which is not on your \$PATH yet."
    echo "    On most systems it is added automatically at your next login. To use it now:"
    echo ""
    echo "        export PATH=\"${BIN_DIR}:\$PATH\""
    echo ""
    echo "    Add that line to your ~/.bashrc (or ~/.zshrc) to keep it."
    ;;
esac
echo "  • Review ${INSTALL_DIR}/metagear.config and adjust as needed"
