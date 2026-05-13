#!/usr/bin/env bash
# auto_reuse.sh — discover reusable outputs in a previous run's outdir.
#
# Reads lib/reuse_outputs.json (a map of param → canonical-path-under-outdir),
# checks which artifacts exist, and prints CLI flags to stdout. main.sh appends
# them to the nextflow command so the pipeline's existing skip semantics
# (--contigs_dir, --genes_dir, --representative_*, etc.) take effect.
#
# Behavior:
#   - "dir" entries:  emit --<param> <dir> ONLY if every sample_id from the
#                     input CSV has a file at <outdir>/<subdir>/<id><suffix>.
#                     All-or-nothing — partial reuse is not supported.
#   - "file" entries: emit --<param> <file> if the file exists.
#
# All matches are echoed to stderr so the launch log shows what's being reused.

set -o pipefail

# Resolve path to the JSON map. Works whether sourced (BASH_SOURCE is set) or
# invoked as a script. We *don't* enable `set -u` here because the script may
# also be sourced into a parent context that uses unset positional vars.
_auto_reuse_self="${BASH_SOURCE[0]:-$0}"
REUSE_MAP_FILE="$(cd "$(dirname "$_auto_reuse_self")" && pwd)/reuse_outputs.json"

# Parse the reuse map into TSV rows: param<TAB>kind<TAB>subdir<TAB>suffix<TAB>path
# Tries jq, then python3. Returns non-zero if neither is available.
_reuse_parse_map() {
    local map_file="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r '.reusable[] | [.param, .kind, (.subdir // ""), (.per_sample_suffix // ""), (.path // "")] | join("|")' "$map_file"
        return $?
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, sys
with open('$map_file') as fh:
    data = json.load(fh)
for e in data.get('reusable', []):
    print('|'.join([
        e.get('param', ''),
        e.get('kind', ''),
        e.get('subdir', ''),
        e.get('per_sample_suffix', ''),
        e.get('path', ''),
    ]))
"
        return $?
    fi
    echo "auto-reuse: neither jq nor python3 available; --reuse-outputs ignored" >&2
    return 1
}

# Extract sample IDs (column 1) from the input CSV. Skips the header line and
# any row whose sample id starts with '#' (used as a comment marker upstream).
_reuse_sample_ids() {
    local input_csv="$1"
    awk -F, 'NR>1 && $1 != "" && $1 !~ /^#/ {print $1}' "$input_csv"
}

# Public: print CLI flags to stdout, log lines to stderr.
auto_reuse_emit_flags() {
    local outdir="$1"
    local input_csv="$2"

    if [[ ! -d "$outdir" ]]; then
        echo "[auto-reuse] outdir $outdir does not exist — nothing to reuse" >&2
        return 0
    fi
    if [[ ! -f "$input_csv" ]]; then
        echo "[auto-reuse] input CSV $input_csv not found — skipping" >&2
        return 0
    fi

    local sample_ids
    sample_ids="$(_reuse_sample_ids "$input_csv")"
    local n_samples
    n_samples=$(echo "$sample_ids" | grep -c .)
    if (( n_samples == 0 )); then
        echo "[auto-reuse] no sample ids parsed from $input_csv — skipping" >&2
        return 0
    fi

    echo "[auto-reuse] scanning $outdir for reusable outputs ($n_samples samples)..." >&2

    local map_rows
    if ! map_rows="$(_reuse_parse_map "$REUSE_MAP_FILE")"; then
        return 0
    fi

    local found=0
    # NOTE: `|` separator (not TAB) — bash's `read` with whitespace-only IFS
    # collapses consecutive delimiters and drops empty fields, which would
    # mangle rows where subdir/suffix are empty (the `file` kind).
    while IFS='|' read -r param kind subdir suffix path; do
        [[ -z "$param" ]] && continue
        case "$kind" in
            dir)
                local target_dir="$outdir/$subdir"
                if [[ ! -d "$target_dir" ]]; then
                    continue
                fi
                local missing_count=0
                while IFS= read -r s; do
                    [[ -z "$s" ]] && continue
                    if [[ ! -f "$target_dir/${s}${suffix}" ]]; then
                        missing_count=$((missing_count + 1))
                    fi
                done <<< "$sample_ids"
                if (( missing_count == 0 )); then
                    printf -- '--%s\n%s\n' "$param" "$target_dir"
                    echo "[auto-reuse]   --${param}  ⇐  ${target_dir}  (${n_samples} samples)" >&2
                    found=$((found + 1))
                else
                    echo "[auto-reuse]   --${param}  skipped: ${missing_count}/${n_samples} samples missing under ${target_dir}" >&2
                fi
                ;;
            file)
                local target_file="$outdir/$path"
                if [[ -f "$target_file" ]]; then
                    printf -- '--%s\n%s\n' "$param" "$target_file"
                    echo "[auto-reuse]   --${param}  ⇐  ${target_file}" >&2
                    found=$((found + 1))
                fi
                ;;
            *)
                echo "[auto-reuse] unknown kind '$kind' for param '$param' — ignored" >&2
                ;;
        esac
    done <<< "$map_rows"

    if (( found == 0 )); then
        echo "[auto-reuse] no reusable outputs found — running pipeline fully" >&2
    fi
}
