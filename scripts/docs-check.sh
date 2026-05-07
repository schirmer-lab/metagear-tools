#!/bin/bash

# Documentation maintenance script
# Usage: ./scripts/docs-check.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "📚 MetaGEAR Documentation Check"
echo "==============================="

# Check for broken internal links
echo "🔗 Checking internal links..."
find "$REPO_ROOT/docs" -name "*.md" -exec grep -l "\[.*\](.*\.md)" {} \; | while read -r file; do
    echo "Checking $file"
    grep -o "\[.*\](.*\.md)" "$file" | while read -r link; do
        target=$(echo "$link" | sed 's/.*](\(.*\))/\1/')
        if [[ "$target" =~ ^http ]]; then
            continue  # Skip external links
        fi

        # Convert relative path to absolute
        if [[ "$target" =~ ^/ ]]; then
            full_path="$REPO_ROOT$target"
        else
            dir=$(dirname "$file")
            full_path="$dir/$target"
        fi

        if [ ! -f "$full_path" ]; then
            echo "  ❌ Broken link: $target in $file"
        fi
    done
done

# Check for TODO items
echo ""
echo "📝 Checking for TODO items..."
find "$REPO_ROOT" -name "*.md" -exec grep -Hn "TODO\|FIXME\|XXX" {} \;

# Check for consistent formatting
echo ""
echo "📐 Checking formatting consistency..."

# Check for consistent header styles
echo "Headers should use # style (not underline style):"
find "$REPO_ROOT/docs" -name "*.md" -exec grep -Hn "^===\|^---" {} \;

# Check for consistent code block formatting
echo "Code blocks should use "\`\`\`" (not indentation):"
find "$REPO_ROOT/docs" -name "*.md" -exec grep -Hn "^    [a-zA-Z]" {} \;

# Generate documentation index
echo ""
echo "📋 Documentation Structure:"
echo ""
find "$REPO_ROOT/docs" -name "*.md" | sort | while read -r file; do
    rel_path=${file#$REPO_ROOT/}
    title=$(grep "^# " "$file" | head -1 | sed 's/^# //')
    echo "- [$title]($rel_path)"
done

echo ""
echo "✅ Documentation check complete!"
echo ""
echo "💡 Tips:"
echo "- Keep README.md as the main entry point"
echo "- Use docs/developers/ for contributor documentation"
echo "- Use docs/ root for user documentation"
echo "- Update CHANGELOG.md for all user-facing changes"
