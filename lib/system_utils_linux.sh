#!/usr/bin/env bash

# Linux-specific utilities for system information

# Get total installed memory in GB
get_total_memory_gb() {
    local mem_total_kb
    mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    awk -v mem="$mem_total_kb" 'BEGIN {printf "%.2f", mem/1048576}'
}

# Get the number of available CPUs
get_cpu_count() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    else
        echo "1"
    fi
}

