# MetaGEAR Tools

Command-line wrapper and installer for [**MetaGEAR Workflows**](https://github.com/schirmer-lab/metagear-pipeline) — a Nextflow / nf-core pipeline for end-to-end microbiome metagenomic analysis.

This repository is part of the [**MetaGEAR Platform**](https://metagear-platform.schirmerlab.de/), which comprises:

- **MetaGEAR Workflows** — the Nextflow pipeline that produces harmonized outputs (formerly _metagear-pipeline_)
- **MetaGEAR Explorer** — the web portal at <https://metagear-explorer.schirmerlab.de> (formerly _MetaGEAR Web_)
- **MetaGEAR Tools** _(this repo)_ — the CLI wrapper and installer that drives the workflows

## Quick start

1. **Install**: `curl -L http://get-metagear.schirmerlab.de | bash`
2. **Configure**: review `~/.metagear/metagear.config` and `~/.metagear/metagear.env`
3. **Download databases**: `metagear download_databases`
4. **Run a workflow**: `metagear qc_dna --input samples.csv`

For full instructions, see the [📖 documentation](https://metagear-platform.schirmerlab.de/).

## Prerequisites

- [Java 17+](https://ubuntu.com/tutorials/install-jre#2-installing-openjdk-jre)
- [Nextflow 25+](https://www.nextflow.io/docs/latest/install.html)
- [Docker](https://docs.docker.com/engine/install/) or [Singularity](https://docs.sylabs.io/guides/3.0/user-guide/installation.html)

## Installation

Latest release:

```bash
curl -L http://get-metagear.schirmerlab.de | bash
```

Pin a specific MetaGEAR Workflows version:

```bash
curl -L http://get-metagear.schirmerlab.de | bash -s -- --pipeline 1.0
```

The installer auto-detects available CPUs/RAM and sets resource limits to roughly 80% of the host (capped at 48 CPUs and 80 GB).

> ⚠️ Review and customize `~/.metagear/metagear.config` and `~/.metagear/metagear.env` before running workflows.

➡️ See the [Installation Guide](https://metagear-platform.schirmerlab.de/get-started) for full setup instructions.

## Basic usage

```bash
# Download databases
metagear download_databases

# Run workflows
metagear qc_dna --input samples.csv
metagear microbial_profiles --input samples.csv

# Generate the launch script without executing it
metagear qc_dna --input samples.csv -preview
```

Input CSV format:

```csv
sample,fastq_1,fastq_2
SAMPLE-01,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
SAMPLE-02,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz
```

➡️ See the [Usage Guide](https://metagear-platform.schirmerlab.de/tools) for the complete reference.

## Documentation

- 🚀 [Get started](https://metagear-platform.schirmerlab.de/get-started)
- 🔧 [MetaGEAR Tools reference](https://metagear-platform.schirmerlab.de/tools)
- 🔬 [Workflows](https://metagear-platform.schirmerlab.de/workflows)
- 📰 [Release news](https://metagear-platform.schirmerlab.de/news)
- 📑 [How to cite](https://metagear-platform.schirmerlab.de/cite)

The documentation site is built and published from [`schirmer-lab/metagear-platform`](https://github.com/schirmer-lab/metagear-platform).

### Developing on the wrapper

- [Architecture](docs/architecture.md) — how `main.sh`, `lib/`, `templates/` and `cluster/` fit together
- [Development guide](docs/development_guide.md) — installing from a local checkout, install parameters
- [Contributing](docs/contributing.md)
- [Release guide](docs/release_guide.md) — changelog workflow and cutting a release
- [Troubleshooting](docs/troubleshooting.md) — installation, configuration and runtime problems

## Support

- 📖 [Documentation](https://metagear-platform.schirmerlab.de/)
- 🐛 [MetaGEAR Workflows issues](https://github.com/schirmer-lab/metagear-pipeline/issues)
- 🐛 [MetaGEAR Tools issues](https://github.com/schirmer-lab/metagear-tools/issues)

## License

MIT — see [LICENSE](LICENSE).
