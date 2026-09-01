# Contributing to MetaGEAR Pipeline Wrapper

Thank you for your interest in contributing to the MetaGEAR Pipeline Wrapper! This document provides guidelines for contributors.

## 🚀 Getting Started

### Prerequisites

- Bash 4.0+ (for the wrapper scripts)
- [Bats](https://bats-core.readthedocs.io/) (for running tests)
- Git

### Development Setup

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/metagear.git
   cd metagear
   ```
3. Install Bats for testing:

   ```bash
   # On Ubuntu/Debian
   sudo apt-get install bats

   # On macOS
   brew install bats-core
   ```

## 🧪 Testing

Always run tests before submitting changes:

```bash
# Run all tests
bats tests

# Run specific test file
bats tests/install.bats

# Run with verbose output
bats -t tests
```

## 📝 Making Changes

### 1. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Code Style Guidelines

#### Bash Scripts

- Use `set -euo pipefail` for strict error handling
- Quote variables: `"$variable"`
- Use `local` for function variables
- Follow existing naming conventions
- Add comments for complex logic

#### Function Documentation

```bash
# Description: Brief function description
# Parameters:
#   $1 - Parameter description
# Returns: Description of return value
function_name() {
    local param1="$1"
    # Implementation
}
```

### 3. Writing Tests

Add tests for new functionality in the `tests/` directory:

```bash
@test "function should do something" {
    source lib/common.sh
    run function_name "input"
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected"* ]]
}
```

### 4. Documentation Updates

- Update relevant documentation files
- Add examples for new features
- Update help text if adding new options

## 🔄 Submission Process

### 1. Commit Guidelines

Use clear, descriptive commit messages:

```bash
# Good examples
git commit -m "Add support for custom config directory"
git commit -m "Fix workflow argument parsing for spaces"
git commit -m "Update installation documentation"

# Follow conventional commits format when applicable
git commit -m "feat: add debug logging option"
git commit -m "fix: handle missing input file gracefully"
git commit -m "docs: update contributing guidelines"
```

### 2. Pull Request Process

1. **Push your changes**:

   ```bash
   git push origin feature/your-feature-name
   ```

2. **Create a Pull Request** on GitHub with:
   - Clear title describing the change
   - Detailed description of what was changed and why
   - Reference any related issues
   - Screenshots/examples if applicable

3. **PR Template** (use this structure):

   ```markdown
   ## Description

   Brief description of changes

   ## Type of Change

   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Performance improvement
   - [ ] Code refactoring

   ## Testing

   - [ ] Tests pass locally
   - [ ] New tests added for new functionality
   - [ ] Manual testing completed

   ## Checklist

   - [ ] Code follows project style guidelines
   - [ ] Self-review completed
   - [ ] Documentation updated
   - [ ] Tests added/updated
   ```

### 3. Review Process

- Maintainers will review your PR
- Address any feedback or requested changes
- Once approved, your PR will be merged

## 🐛 Reporting Issues

### Bug Reports

Use the issue template and include:

- **Environment**: OS, Bash version, installation method
- **Steps to reproduce**: Exact commands and inputs
- **Expected behavior**: What should happen
- **Actual behavior**: What actually happens
- **Error messages**: Full error output
- **Additional context**: Any other relevant information

### Feature Requests

- Describe the feature and its use case
- Explain why it would be valuable
- Provide examples of how it would work
- Consider implementation complexity

## 📋 Issue Labels

- `bug`: Something isn't working
- `enhancement`: New feature or request
- `documentation`: Improvements or additions to docs
- `good first issue`: Good for newcomers
- `help wanted`: Extra attention is needed
- `priority:high`: High priority issues
- `priority:low`: Low priority issues

## 🎯 Areas for Contribution

### High Priority

- Bug fixes
- Performance improvements
- Test coverage improvements
- Documentation updates

### Medium Priority

- New workflow support
- Configuration enhancements
- Error handling improvements
- Code refactoring

### Good First Issues

- Documentation improvements
- Small bug fixes
- Test additions
- Help text updates

## 💬 Communication

- **Issues**: Use GitHub issues for bug reports and feature requests
- **Discussions**: Use GitHub discussions for questions and ideas
- **Email**: Contact maintainers for sensitive issues

## 📜 Code of Conduct

### Our Standards

- Be respectful and inclusive
- Focus on constructive feedback
- Help create a welcoming environment
- Be patient with newcomers

### Unacceptable Behavior

- Harassment of any kind
- Discriminatory language or behavior
- Public or private attacks
- Publishing private information

## 📚 Resources

### Documentation

- [Development Guide](development_guide.md)
- [Architecture Overview](architecture.md)

### External Resources

- [Bash Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Bats Testing Framework](https://bats-core.readthedocs.io/)
- [Conventional Commits](https://www.conventionalcommits.org/)

## 🙏 Recognition

Contributors will be:

- Listed in the repository contributors
- Mentioned in release notes for significant contributions
- Acknowledged in project documentation

Thank you for contributing to MetaGEAR!

[← Back to Developer Info Overview](index.md){: .btn .btn-outline }
