# Developer Info

{: .no_toc }

This section contains documentation specifically for MetaGEAR Pipeline Wrapper developers and contributors.

## Quick Start for Developers

1. Clone the repository and install test dependencies
   ```bash
   git clone https://github.com/schirmer-lab/metagear-tools.git
   cd metagear
   # Install development dependencies (Bats for testing)
   ```
2. Run tests
   ```bash
   bats tests
   ```
3. Local pipeline development
   ```bash
   ./install.sh --pipeline /path/to/local/metagear-pipeline
   ```

See [Contributing Guidelines](contributing.md) for detailed guidelines.

[← Back to Home](https://metagear-platform.schirmerlab.de/){: .btn .btn-outline }
