# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [1.0.1] - 2025-08-20

### Added
- Automatic detection and installation of latest MetaGEAR Pipeline release
- Version specification support via `--pipeline` parameter (e.g., `--pipeline 1.0`)
- Validation of specified versions against GitHub releases
- Enhanced `--pipeline` parameter to accept both directory paths and version numbers

### Changed
- Now using MetaGEAR Pipeline v1.0 (previously v.0.1.1)
- Installation script now defaults to latest release instead of hardcoded version
- `--pipeline` parameter help text updated to reflect new dual functionality

### Deprecated

### Removed

### Fixed

### Security

## [1.0.0] - 2025-08-14

### Added
- Initial release of MetaGEAR Pipeline Wrapper
- Easy installation and setup tools for MetaGEAR Pipeline
- Command-line interface for launching Nextflow/NF-Core microbiome metagenomic workflows
- Quality control & trimming workflow launcher (FastQC, TrimGalore)
- Host- and contaminant-read removal workflow launcher (Kneaddata)
- Microbial Profiling workflow launcher (MetaPhlAn, HUMAnN)
- Database download functionality for Kneaddata, MetaPhlAn, HUMAnN
- Preview mode for workflow execution and script generation
- Automated installation script with environment detection
- Gene analysis workflow launcher
- Configuration management and default settings
- Comprehensive documentation and usage examples

### Changed
- Refactored JSON parser to use factory pattern for better maintainability
- Refactored workflow definitions for better maintainability
- Updated Jekyll configuration for documentation

### Fixed
- Documentation improvements and fixes
- Various bugfixes throughout development

[Unreleased]: https://github.com/schirmer-lab/metagear/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/schirmer-lab/metagear/releases/tag/v1.0.0

[Unreleased]: https://github.com/schirmer-lab/metagear/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/schirmer-lab/metagear/releases/tag/v1.0.1
