# Release Management Guide

This guide explains how to manage releases and maintain the changelog for the MetaGEAR Pipeline Wrapper.

## Changelog Management

We follow the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format with semantic versioning.

### Adding Changes to the Changelog

#### Manual Method

Edit `CHANGELOG.md` directly and add entries under the appropriate section in `[Unreleased]`:

```markdown
## [Unreleased]

### Added

- New pipeline wrapper features
- Enhanced pipeline configuration management

### Fixed

- Pipeline wrapper installation improvements
- Configuration validation enhancements
```

#### Using the Helper Script

Use the `scripts/update-changelog.sh` script:

```bash
# Add to unreleased section
./scripts/update-changelog.sh add "Added new feature X" "added"
./scripts/update-changelog.sh add "Fixed bug Y" "fixed"
./scripts/update-changelog.sh add "Changed behavior Z" "changed"
```

### Changelog Categories

Use these standard categories:

- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Vulnerability fixes

## Release Process

### 1. Pre-Release Preparation

#### Update Version Numbers

```bash
# Update version in relevant files
vim install.sh          # Update VERSION variable
vim main.sh             # Update version output
vim docs/index.md       # Update documentation version
```

#### Update Changelog

```bash
# Move unreleased items to new version section
./scripts/update-changelog.sh release "1.2.0"
```

#### Run Tests

```bash
# Ensure all tests pass
bats tests

# Test installation
./install.sh --install-dir /tmp/test-install
```

### 2. Create Release

#### Tag Creation

```bash
# Create annotated tag
git tag -a v1.2.0 -m "Release version 1.2.0"

# Push tag to remote
git push origin v1.2.0
```

#### GitHub Release

1. **Go to GitHub Releases page**
2. **Click "Create a new release"**
3. **Fill in release information**:
   - Tag version: `v1.2.0`
   - Release title: `MetaGEAR Wrapper v1.2.0`
   - Description: Copy from changelog

#### Release Notes Template

````markdown
## MetaGEAR Pipeline Wrapper v1.2.0

### What's New

- Feature 1: Description
- Feature 2: Description

### Bug Fixes

- Fix 1: Description
- Fix 2: Description

### Breaking Changes

- Change 1: Migration guide
- Change 2: Migration guide

### Installation

```bash
curl -fsSL https://get-metagear.schirmerlab.de | bash
```
````

See the [documentation](https://metagear-platform.schirmerlab.de/) for detailed installation and usage instructions.

### Full Changelog

**Added**

- New feature descriptions

**Fixed**

- Bug fix descriptions

**Changed**

- Change descriptions

````

### 3. Post-Release

#### Update Documentation
```bash
# Update documentation if needed
git checkout main
git pull origin main

# Make any post-release documentation updates
vim docs/index.md
git commit -m "docs: update for v1.2.0 release"
git push origin main
````

#### Verify Installation

```bash
# Test that new release installs correctly
curl -fsSL https://get-metagear.schirmerlab.de | bash
metagear --version
```

## Versioning Strategy

### Semantic Versioning

We follow [Semantic Versioning 2.0.0](https://semver.org/):

- **MAJOR**: Incompatible API changes
- **MINOR**: Backward-compatible functionality additions
- **PATCH**: Backward-compatible bug fixes

### Version Incrementing Guidelines

#### MAJOR Version (1.0.0 → 2.0.0)

- Breaking changes to CLI interface
- Removal of deprecated features
- Major architectural changes
- Incompatible configuration changes

#### MINOR Version (1.1.0 → 1.2.0)

- New workflow support
- New command-line options
- New configuration options
- Backward-compatible enhancements

#### PATCH Version (1.1.1 → 1.1.2)

- Bug fixes
- Documentation updates
- Security patches
- Performance improvements (no interface changes)

### Pre-Release Versions

For development and testing:

- **Alpha**: `1.2.0-alpha.1` (early development)
- **Beta**: `1.2.0-beta.1` (feature complete, testing)
- **RC**: `1.2.0-rc.1` (release candidate)

## Release Checklist

### Pre-Release Checklist

- [ ] All tests pass (`bats tests`)
- [ ] Documentation is up to date
- [ ] Changelog is updated with all changes
- [ ] Version numbers are incremented
- [ ] Breaking changes are documented
- [ ] Installation script works correctly
- [ ] Examples in documentation are tested

### Release Checklist

- [ ] Git tag created with correct version
- [ ] GitHub release created with release notes
- [ ] Release notes include changelog entries
- [ ] Installation URL works correctly
- [ ] Documentation site is updated
- [ ] Version command shows correct version

### Post-Release Checklist

- [ ] Installation verified from public URL
- [ ] Documentation site reflects new version
- [ ] GitHub release page is properly formatted
- [ ] Social media/communication (if applicable)
- [ ] Next version preparation (update unreleased section)

## Hotfix Process

For critical bug fixes that need immediate release:

### 1. Create Hotfix Branch

```bash
git checkout v1.2.0
git checkout -b hotfix/1.2.1
```

### 2. Apply Fix

```bash
# Make minimal fix
vim affected_file.sh
git commit -m "fix: critical bug description"
```

### 3. Update Version and Changelog

```bash
# Update version
vim install.sh

# Update changelog
./scripts/update-changelog.sh add "Fixed critical bug" "fixed"
./scripts/update-changelog.sh release "1.2.1"
```

### 4. Create Hotfix Release

```bash
git tag -a v1.2.1 -m "Hotfix version 1.2.1"
git push origin hotfix/1.2.1
git push origin v1.2.1
```

### 5. Merge Back

```bash
# Merge into main
git checkout main
git merge hotfix/1.2.1
git push origin main

# Clean up
git branch -d hotfix/1.2.1
```

## Automation Scripts

### Changelog Helper (`scripts/update-changelog.sh`)

```bash
#!/bin/bash
# Add entry to changelog
./scripts/update-changelog.sh add "Description" "category"

# Create release from unreleased items
./scripts/update-changelog.sh release "1.2.0"
```

### Release Helper (`scripts/create-release.sh`)

```bash
#!/bin/bash
# Automated release creation
./scripts/create-release.sh 1.2.0 "Release description"
```

## Communication

### Release Announcements

- GitHub release page
- Project documentation
- User mailing list (if applicable)
- Social media channels

### Breaking Changes

For releases with breaking changes:

1. **Document migration path**
2. **Provide deprecation warnings** in previous versions
3. **Update all examples** and documentation
4. **Consider backward compatibility** where possible

## Rollback Procedure

If a release has critical issues:

### 1. Immediate Response

```bash
# Remove problematic tag
git tag -d v1.2.0
git push origin :refs/tags/v1.2.0

# Delete GitHub release
# (Manual action on GitHub web interface)
```

### 2. Communication

- Update GitHub release with warning
- Document issues in release notes
- Provide workaround instructions

### 3. Fix and Re-release

```bash
# Create patch version
git checkout v1.1.0
git checkout -b hotfix/1.2.1
# Apply fixes
git tag -a v1.2.1 -m "Fixed release"
```

## Best Practices

### Release Timing

- **Regular Schedule**: Monthly or bi-monthly minor releases
- **Emergency Releases**: For critical security issues
- **Coordinate with Pipeline**: Align with MetaGEAR pipeline releases

### Quality Assurance

- **Test on Multiple Platforms**: Linux, macOS
- **Test Different Configurations**: HPC, local, containers
- **Validate Examples**: Ensure all documentation examples work
- **Performance Testing**: Check for regressions

### Documentation

- **Keep Changelog Current**: Update with every change
- **Document Breaking Changes**: Clear migration instructions
- **Update Version References**: All documentation should reflect current version
- **Example Updates**: Verify all examples work with new version

[← Back to Developer Info Overview](index.md){: .btn .btn-outline }
