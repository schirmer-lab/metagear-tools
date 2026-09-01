# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions are date-based (`YY.MM`, or `YY.MM.N` for a fix within the same month) and are released
in lockstep with [metagear-pipeline](https://github.com/schirmer-lab/metagear-pipeline): the two
share a version number because the wrapper mirrors the pipeline's workflow and parameter definitions.

## [Unreleased]

## [26.09] - 2026-09-01

Paired with pipeline 26.09. Adopts date-based versioning; the jump from 1.0.1 is a change of scheme,
not 25 major versions.

### Added
- `metagear cluster` — brings a HyperQueue cluster up or down across the machines listed in
  `nodes.conf`, with `up`/`ensure`/`down`/`status`/`restart`/`jobs`/`scratch`/`db`/`sweep`. The server
  runs beside the Nextflow head process and workers attach from every node; nothing needs root.
  `METAGEAR_MODE=cluster` spreads a run over it, `single` (the default) keeps it on one machine.
- `cluster/mirror-dbs.sh` to replicate the reference databases to each node's local scratch, and
  `templates/cluster-nodes.conf` as the starting point for a site's node list.
- `metagear clean` reclaims a finished workspace's work directory via Nextflow's own `clean`, refusing
  while a run is still using it.
- `--reuse-from` names an earlier run's workspace to reuse outputs from, rather than only the current
  `--outdir`.
- Presets that run several workflows in order in one workspace, each reusing what the ones before it
  produced: `profiles`, `genomes`, `microbiome`.
- Support for the pipeline's new workflows in `workflow_definitions.json`: `virus`, `classification`,
  `mag`, `msp`, `structures`, and `genes` in place of `gene_analysis`.
- `metagear --version` (also `-version` / `version`) prints semver + install-time build number (YYMMDD), plus resolved utilities/pipeline paths so symlinked dev installs are obvious.
- `VERSION` file at the repo root holds the wrapper's semver.
- Install-time build stamp written to `$INSTALL_DIR/.build` on every install/re-install.
- Per-user resource overrides via `$INSTALL_DIR/resources.yaml`. `install.sh` seeds the file from `templates/resources.yaml` (skip-if-exists). `main.sh` regenerates `$INSTALL_DIR/resources.config` from it on every `metagear …` invocation, using the bash YAML generator at `lib/build_resources_config.sh`. Nextflow loads the regenerated config via `includeConfig` (per-key merging — coexists cleanly with the wrapper's existing block-level merge of `conf/metagear/*.config`).
- `--reuse-outputs` global flag: scans `--outdir` for outputs from prior runs (contigs, genes, gene/protein catalogs, abundance tables, protein annotations) and auto-injects the matching `--contigs_dir`/`--genes_dir`/`--representative_*` flags so the pipeline's existing skip-if-set logic kicks in. Mapping lives in `lib/reuse_outputs.json`; logic in `lib/auto_reuse.sh`. All-or-nothing per artifact (any sample's file missing → fall through to running fully). Explicit user-passed flags always win over auto-resolved ones. Loud logging of every match/skip on stderr.
- New `lib/build_resources_config.sh` — pure-bash 4+ generator that converts a restricted YAML schema (flow-style entries, `labels:` and `overrides:` sections) to a Nextflow config. Used both by `main.sh` (for per-user overrides) and by pipeline maintainers regenerating the pipeline's defaults from `conf/resources.yaml`.
- Fixed `merge_configuration.sh` to also recognize `withLabel:` blocks (previously only `withName:` was handled, causing label blocks in user configs to be silently dropped and prematurely close the `process { }` section).

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

[Unreleased]: https://github.com/schirmer-lab/metagear-tools/compare/26.09...HEAD
[26.09]: https://github.com/schirmer-lab/metagear-tools/releases/tag/26.09
[1.0.1]: https://github.com/schirmer-lab/metagear/releases/tag/v1.0.1
[1.0.0]: https://github.com/schirmer-lab/metagear/releases/tag/v1.0.0
