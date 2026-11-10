# Troubleshooting Guide

{: .no_toc }

Common issues and solutions for the MetaGEAR Pipeline Wrapper.

## 🚨 Installation Issues

### Problem: `curl` command fails

```bash
curl: (7) Failed to connect to get-metagear.schirmerlab.de
```

**Solutions:**

1. Check internet connectivity
2. Try with `--insecure` flag if SSL issues
3. Download manually and run `./install.sh`

### Problem: Permission denied during installation

```bash
Permission denied: cannot create directory ~/.metagear
```

**Solutions:**

1. Check home directory permissions
2. Use custom install directory: `./install.sh --install-dir /tmp/metagear`
3. Run with appropriate permissions

## 🔧 Configuration Issues

### Problem: Singularity containers not found

```bash
ERROR: Cannot find Singularity executable
```

**Solutions:**

1. Install Singularity/Apptainer
2. Update PATH to include Singularity
3. Switch to Docker profile in `~/.metagear/metagear.config`

### Problem: Mount points not accessible

```bash
ERROR: Input file not found
```

**Solutions:**

1. Add mount points to `~/.metagear/metagear.config`:
   ```
   singularity.runOptions = "--writable-tmpfs -B /nfs:/nfs -B /data:/data"
   ```
2. Ensure paths are absolute
3. Check file permissions

## 🏃 Runtime Issues

### Problem: Out of memory errors

```bash
java.lang.OutOfMemoryError: Java heap space
```

**Solutions:**

1. Reduce `maxForks` in configuration
2. Increase available memory
3. Use `--max_memory` parameter

### Problem: Java version conflicts

```bash
ERROR: Java 17+ required
```

**Solutions:**

1. Install Java 17 or higher
2. Update JAVA_HOME environment variable
3. Use `module load java` on HPC systems

### Problem: Database download failures

```bash
ERROR: Failed to download databases
```

**Solutions:**

1. Check internet connectivity
2. Verify disk space availability
3. Try downloading individual databases:
   ```bash
   metagear download_databases --database kneaddata
   ```

## 📁 File and Path Issues

### Problem: Input file format errors

```bash
ERROR: Invalid sample sheet format
```

**Solutions:**

1. Verify CSV format with headers: `sample,fastq_1,fastq_2`
2. Check for special characters in file paths
3. Ensure all files exist and are readable

### Problem: Output directory permissions

```bash
ERROR: Cannot write to output directory
```

**Solutions:**

1. Check directory permissions
2. Create directory manually first
3. Use different output location

## 🐳 Container Issues

### Problem: Docker daemon not running

```bash
ERROR: Cannot connect to Docker daemon
```

**Solutions:**

1. Start Docker daemon: `sudo systemctl start docker`
2. Add user to docker group: `sudo usermod -aG docker $USER`
3. Switch to Singularity profile

### Problem: Container download failures

```bash
ERROR: Failed to pull container image
```

**Solutions:**

1. Check internet connectivity
2. Verify container registry access
3. Try pulling manually: `docker pull quay.io/biocontainers/...`

## 🖥️ HPC and Cluster Issues

### Problem: Scheduler integration

```bash
ERROR: Job submission failed
```

**Solutions:**

1. Configure appropriate Nextflow profile for your scheduler
2. Update `~/.metagear/metagear.config` with cluster settings
3. Check scheduler-specific documentation

### Problem: Module loading

```bash
command not found: nextflow
```

**Solutions:**

1. Load required modules in `~/.metagear/metagear.env`:
   ```bash
   module load nextflow java singularity
   ```
2. Update PATH in environment file

## 📊 Performance Issues

### Problem: Slow execution

**Solutions:**

1. Increase `maxForks` in configuration (if resources allow)
2. Use local storage for work directory
3. Optimize container caching

### Problem: High memory usage

**Solutions:**

1. Reduce parallel processes (`maxForks`)
2. Use `--max_memory` to limit memory per process
3. Monitor system resources

## 🔍 Debugging Tips

### Enable verbose logging

```bash
export NXF_DEBUG=1
metagear qc_dna --input samples.csv
```

### Check configuration

```bash
# Verify merged configuration
metagear qc_dna --input samples.csv -preview
```

### Test installation

```bash
# Run basic tests
cd ~/.metagear/utils
bats tests
```

### Check system requirements

```bash
# Verify Java version
java -version

# Check available resources
free -h
nproc
```

## 📞 Getting Help

If you're still experiencing issues:

1. **Check the logs** in the work directory
2. **Search existing issues** on GitHub
3. **Create a new issue** with:
   - Operating system and version
   - Command that failed
   - Complete error message
   - Configuration files (remove sensitive data)

## 🔗 Useful Commands

```bash
# Check wrapper version
metagear --version

# Validate sample sheet
head -5 your_samples.csv

# Test configuration
metagear qc_dna --input samples.csv -preview

# Check disk space
df -h

# Monitor resource usage
top
htop
```
