#!/bin/bash

# Script to help manage changelog updates
# Usage: ./scripts/update-changelog.sh [version] [type] [description]
#   version: the version number (e.g., 1.1.0)
#   type: Added, Changed, Deprecated, Removed, Fixed, Security
#   description: description of the change

set -e

CHANGELOG_FILE="CHANGELOG.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGELOG_PATH="$REPO_ROOT/$CHANGELOG_FILE"

usage() {
    echo "Usage: $0 [version] [type] [description]"
    echo ""
    echo "Arguments:"
    echo "  version     Version number (e.g., 1.1.0) - optional for adding to unreleased"
    echo "  type        Type of change: Added, Changed, Deprecated, Removed, Fixed, Security"
    echo "  description Description of the change"
    echo ""
    echo "Examples:"
    echo "  $0 Added \"New gene analysis workflow\""
    echo "  $0 1.1.0 Added \"New gene analysis workflow\""
    echo "  $0 Fixed \"Fix memory leak in processing pipeline\""
    echo ""
    echo "Commands:"
    echo "  $0 release [version]  Prepare changelog for release"
    echo "  $0 help              Show this help message"
}

if [ $# -eq 0 ] || [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
    exit 0
fi

if [ "$1" = "release" ]; then
    if [ $# -ne 2 ]; then
        echo "Error: Release command requires version number"
        echo "Usage: $0 release [version]"
        exit 1
    fi

    VERSION="$2"
    DATE=$(date +%Y-%m-%d)

    # Replace [Unreleased] with the version and add new [Unreleased] section
    sed "s/## \[Unreleased\]/## [$VERSION] - $DATE/" "$CHANGELOG_PATH" > "$CHANGELOG_PATH.tmp" && mv "$CHANGELOG_PATH.tmp" "$CHANGELOG_PATH"

    # Add new unreleased section at the top
    sed "/## \[$VERSION\] - $DATE/i\\
## [Unreleased]\\
\\
### Added\\
\\
### Changed\\
\\
### Deprecated\\
\\
### Removed\\
\\
### Fixed\\
\\
### Security\\
" "$CHANGELOG_PATH" > "$CHANGELOG_PATH.tmp" && mv "$CHANGELOG_PATH.tmp" "$CHANGELOG_PATH"

    # Update the links at the bottom
    echo "" >> "$CHANGELOG_PATH"
    echo "[Unreleased]: https://github.com/schirmer-lab/metagear/compare/v$VERSION...HEAD" >> "$CHANGELOG_PATH"
    echo "[$VERSION]: https://github.com/schirmer-lab/metagear/releases/tag/v$VERSION" >> "$CHANGELOG_PATH"

    echo "Changelog updated for release v$VERSION"
    exit 0
fi

# Parse arguments for adding changelog entries
if [ $# -eq 2 ]; then
    # Format: type description (add to unreleased)
    TYPE="$1"
    DESCRIPTION="$2"
elif [ $# -eq 3 ]; then
    # Check if first argument is a version number
    if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Format: version type description
        VERSION="$1"
        TYPE="$2"
        DESCRIPTION="$3"
    else
        # Format: type description (with spaces in description)
        TYPE="$1"
        DESCRIPTION="$2 $3"
    fi
else
    echo "Error: Invalid number of arguments"
    usage
    exit 1
fi

# Validate type
case "$TYPE" in
    Added|Changed|Deprecated|Removed|Fixed|Security)
        ;;
    *)
        echo "Error: Invalid type '$TYPE'"
        echo "Valid types: Added, Changed, Deprecated, Removed, Fixed, Security"
        exit 1
        ;;
esac

# Add entry to changelog
if [ -z "${VERSION:-}" ]; then
    # Add to unreleased section
    sed "/^### $TYPE$/a\\
- $DESCRIPTION
" "$CHANGELOG_PATH" > "$CHANGELOG_PATH.tmp" && mv "$CHANGELOG_PATH.tmp" "$CHANGELOG_PATH"
    echo "Added to unreleased section: [$TYPE] $DESCRIPTION"
else
    # Add to specific version (if it exists)
    if grep -q "## \[$VERSION\]" "$CHANGELOG_PATH"; then
        sed "/^## \[$VERSION\]/,/^## \[/s/^### $TYPE$/&\\
- $DESCRIPTION/" "$CHANGELOG_PATH" > "$CHANGELOG_PATH.tmp" && mv "$CHANGELOG_PATH.tmp" "$CHANGELOG_PATH"
        echo "Added to version $VERSION: [$TYPE] $DESCRIPTION"
    else
        echo "Error: Version $VERSION not found in changelog"
        exit 1
    fi
fi
