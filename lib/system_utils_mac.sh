#!/usr/bin/env bash

# macOS-specific utilities for system information

# Get total installed memory in GB
get_total_memory_gb() {
    local mem_bytes
    mem_bytes=$(sysctl -n hw.memsize)
    awk -v mem="$mem_bytes" 'BEGIN {printf "%.2f", mem/1024/1024/1024}'
}

# Get the number of available CPUs
get_cpu_count() {
    sysctl -n hw.ncpu
}

