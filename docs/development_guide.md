# Development Guide

This repository includes a small test suite written with [Bats](https://bats-core.readthedocs.io/).
To run the tests locally, make sure `bats` is installed and then execute:

```bash
bats tests
```

The tests verify helper functions used by the CLI.

## Project Structure

- `main.sh` – CLI entrypoint executed by the `metagear` wrapper. It prepares a Nextflow command using helper functions from `lib`.
- `install.sh` – Bootstrap script that downloads the pipeline and utilities into `~/.metagear` and creates a relocatable wrapper.
- `lib/` – Bash helper scripts used by the CLI:
  - `common.sh` defines commands, usage output and requirement checks.
  - `workflows.sh` builds workflow arguments.
  - `system_utils.sh` provides CPU and memory detection functions.
  - `merge_configuration.sh` merges multiple Nextflow configuration files.
- `templates/` – Default configuration (`metagear.config`) and environment file (`metagear.env`).
- `docs/` – Documentation site (includes README).
- `tests/` – Bats tests covering functions in `lib`.

The bulk of the functionality is implemented in Bash. `main.sh` calls the helper scripts to assemble and run a Nextflow pipeline located in `~/.metagear/latest`.

### Development workflow

1. Install [Bats](https://bats-core.readthedocs.io/).
2. Run `bats tests` to ensure helper functions behave as expected.
3. Modify the scripts in `lib/` or the wrapper as needed.

### Local pipeline development

Developers can point the `latest` symlink to a local checkout of
`metagear-pipeline` by passing the `--pipeline /path/to/pipeline` option to
`install.sh`. The script still downloads the tagged pipeline version, but the
`latest` link will reference the provided directory instead, allowing the
wrapper to execute your local code.

## Installation Parameters

The `install.sh` script accepts the following optional parameters:

- `--install-dir <path>` – Specify a custom installation directory (default: `~/.metagear`)
- `--pipeline <path|version>` – Use a local pipeline directory for development OR specify a specific version to install
- `--utilities <path>` – Use a custom wrapper repository path instead of the default repository

### Examples

```bash
# Install with custom directory
./install.sh --install-dir /opt/metagear

# Install a specific version
./install.sh --pipeline 1.0

# Install with local pipeline for development
./install.sh --pipeline /path/to/local/metagear-pipeline

# Install with custom utilities repository
./install.sh --utilities /path/to/custom/wrapper
```

### Version Management

The installer automatically:

- Detects and installs the latest available release when no version is specified
- Validates that specified versions exist as GitHub releases
- Falls back to version 1.0 if the latest release cannot be determined

The `--pipeline` parameter is flexible:

- **Directory path**: Creates a symbolic link to the local pipeline (for development)
- **Version string**: Downloads and installs the specified release version

## Testing

The test suite uses [Bats](https://bats-core.readthedocs.io/) to verify the functionality of helper scripts.

### Running Tests

```bash
# Run all tests
bats tests

# Run specific test file
bats tests/install.bats

# Run with verbose output
bats -t tests
```

### Test Structure

- `tests/install.bats` – Tests for installation functions
- `tests/preview.bats` – Tests for preview functionality
- `tests/workflow_definitions.bats` – Tests for workflow definition parsing

### Writing Tests

When adding new functionality, write corresponding tests in the `tests/` directory:

```bash
# Example test structure
@test "function_name should do something" {
    source lib/common.sh
    run function_name "test_input"
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected_output"* ]]
}
```

## Code Style

Follow these conventions when contributing:

### Bash Scripting

- Use `set -euo pipefail` for strict error handling
- Quote variables properly: `"$variable"`
- Use `local` for function variables
- Add comments for complex logic
- Use descriptive function and variable names

### Function Documentation

Document functions with clear descriptions:

```bash
# Description: Brief function description
# Parameters:
#   $1 - Parameter description
# Returns: Description of return value or side effects
function_name() {
    local param1="$1"
    # Function implementation
}
```

## Debugging

### Enable Debug Mode

Use the `--debug` flag to enable verbose output:

```bash
metagear workflow_name --input file.csv --debug
```

### Common Issues

1. **Permission errors**: Check file permissions and ownership
2. **Path issues**: Verify all paths are absolute and accessible
3. **Missing dependencies**: Ensure all required tools are installed
4. **Configuration conflicts**: Check for conflicting settings in config files

### Debugging Workflow Execution

To debug workflow execution without running the actual pipeline:

```bash
# Generate script without execution
metagear workflow_name --input file.csv --preview

# Examine generated script
cat metagear_workflow_name.sh
```

## Development Environment Setup

### Prerequisites

1. **Bash 4.0+** (macOS users may need to install via Homebrew)
2. **Git** for version control
3. **Bats** for testing
4. **Nextflow** (for pipeline testing)

### Installation

```bash
# Clone the repository
git clone https://github.com/schirmer-lab/metagear-tools.git
cd metagear

# Install Bats (if not already installed)
# On macOS with Homebrew:
brew install bats-core

# On Ubuntu/Debian:
sudo apt-get install bats

# Run tests to verify setup
bats tests
```

### Local Development Workflow

1. **Make changes** to the wrapper code
2. **Run tests** to ensure functionality
3. **Test with local pipeline** using `--pipeline` flag
4. **Update documentation** if necessary
5. **Submit pull request** with changes

## Configuration

### Development Configuration

For development, you may want to customize certain settings:

```bash
# Create development config
cp templates/metagear.config ~/.metagear/dev.config

# Edit development-specific settings
vim ~/.metagear/dev.config

# Use custom config
metagear workflow_name --input file.csv --config ~/.metagear/dev.config
```

[← Back to Developer Info Overview](index.md){: .btn .btn-outline }
