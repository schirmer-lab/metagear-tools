#!/usr/bin/env bash
# build_resources_config.sh — generate a Nextflow resources config from YAML.
#
# Reads a restricted YAML subset:
#
#     labels:
#       process_high: { cpus: 12, memory_gb: 72, time_h: 16 }
#       process_long: { time_h: 20 }                                  # partial OK
#
#     processes:
#       SAMPLESHEET_CHECK: { label: process_single }                  # info-only
#       MEGAHIT:           { label: process_high, cpus: 12, memory_gb: 24, time_h: 16 }
#       'GENOMAD_PASS.*':  { label: process_high, cpus: 12, memory_gb: 24, note: "..." }
#
# Semantics:
#   - `labels:` rows define `withLabel:NAME { … }` blocks.
#   - `processes:` rows are documentation + optional override:
#       * `label:` is informational (the actual label is in the module file).
#       * `cpus`/`memory_gb`/`time_h` are emitted as a `withName:` block when
#         present. If all three are absent, the row is skipped at emit time
#         (the module's label takes effect).
#
# Constraints (anything outside these is unsupported by this parser):
#   - Top-level keys are exactly `labels:` and/or `processes:`.
#   - Each entry on a single line, flow style ({ … }), one indent level.
#   - Field names: cpus, memory_gb, time_h, note, label. All optional.
#   - No `,` inside any value (the parser splits the body on `,`).
#   - No YAML anchors/aliases/multi-line scalars.
#   - `#` starts a comment to end of line (outside quotes).
#
# Generated output wraps cpu/memory/time in `* task.attempt` so retries
# escalate. Memory unit is GB; time unit is hours.
#
# Usage:
#     bash lib/build_resources_config.sh INPUT.yaml OUTPUT.config

set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
    echo "Error: bash 4+ required (found ${BASH_VERSINFO[0]})." >&2
    exit 1
fi

INPUT="${1:-}"
OUTPUT="${2:-}"
if [[ -z "$INPUT" || -z "$OUTPUT" ]]; then
    echo "Usage: $0 INPUT_YAML OUTPUT_CONFIG" >&2
    exit 1
fi
if [[ ! -f "$INPUT" ]]; then
    echo "Error: input file not found: $INPUT" >&2
    exit 1
fi

# ─── helpers ───────────────────────────────────────────────────────────────

# Strip an unquoted '#…' tail from a line (preserves '#' inside quotes).
strip_comment() {
    local line="$1" out="" c
    local in_s=0 in_d=0 i
    for (( i = 0; i < ${#line}; i++ )); do
        c="${line:i:1}"
        if   [[ $c == "'" && $in_d -eq 0 ]]; then in_s=$((1 - in_s))
        elif [[ $c == '"' && $in_s -eq 0 ]]; then in_d=$((1 - in_d))
        elif [[ $c == "#" && $in_s -eq 0 && $in_d -eq 0 ]]; then break
        fi
        out+="$c"
    done
    printf '%s' "$out"
}

# Trim leading + trailing whitespace.
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Parse a flow-style body "k: v, k: v, …" into the caller's _cpus, _memory_gb,
# _time_h, _note vars. Unknown keys are ignored.
parse_body() {
    local body="$1"
    _cpus="" _memory_gb="" _time_h="" _note=""
    local IFS=','
    local -a pairs=( $body )
    unset IFS
    local pair k v
    for pair in "${pairs[@]}"; do
        pair="$(trim "$pair")"
        [[ -z "$pair" ]] && continue
        if [[ "$pair" =~ ^([a-zA-Z_]+)[[:space:]]*:[[:space:]]*(.*)$ ]]; then
            k="${BASH_REMATCH[1]}"
            v="$(trim "${BASH_REMATCH[2]}")"
            # strip a single layer of surrounding quotes
            if   [[ "$v" =~ ^\"(.*)\"$ ]]; then v="${BASH_REMATCH[1]}"
            elif [[ "$v" =~ ^\'(.*)\'$ ]]; then v="${BASH_REMATCH[1]}"
            fi
            case "$k" in
                cpus)      _cpus="$v" ;;
                memory_gb) _memory_gb="$v" ;;
                time_h)    _time_h="$v" ;;
                note)      _note="$v" ;;
                label)     ;;  # informational only — module declares the actual label
            esac
        fi
    done
}

# Render one withLabel/withName block into a global buffer array.
declare -a OUT_LABELS=()
declare -a OUT_OVERRIDES=()

emit_block() {
    local kind="$1" name="$2"
    # Skip if no resource directives at all (e.g. only `note:`).
    if [[ -z "$_cpus" && -z "$_memory_gb" && -z "$_time_h" ]]; then
        return
    fi
    local -a block=()
    if [[ "$kind" == "label" ]]; then
        block+=( "    withLabel:${name} {" )
    else
        block+=( "    withName: '${name}' {" )
    fi
    [[ -n "$_note"      ]] && block+=( "        // ${_note}" )
    [[ -n "$_cpus"      ]] && block+=( "        cpus   = { ${_cpus} * task.attempt }" )
    [[ -n "$_memory_gb" ]] && block+=( "        memory = { ${_memory_gb}.GB * task.attempt }" )
    [[ -n "$_time_h"    ]] && block+=( "        time   = { ${_time_h}.h * task.attempt }" )
    block+=( "    }" "" )

    if [[ "$kind" == "label" ]]; then
        OUT_LABELS+=( "${block[@]}" )
    else
        OUT_OVERRIDES+=( "${block[@]}" )
    fi
}

# ─── parse ─────────────────────────────────────────────────────────────────

section=""
n_labels=0
n_overrides=0

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="$(strip_comment "$raw_line")"
    line="${line%"${line##*[![:space:]]}"}"  # rtrim
    [[ -z "$line" ]] && continue

    # Section header at column 0
    if [[ "$line" =~ ^(labels|processes):[[:space:]]*$ ]]; then
        section="${BASH_REMATCH[1]}"
        continue
    fi

    # Indented entry: <indent>['name'|name]: { … }
    if [[ -n "$section" && "$line" =~ ^[[:space:]]+\'?([^\':]+)\'?[[:space:]]*:[[:space:]]*\{(.*)\}[[:space:]]*$ ]]; then
        name="${BASH_REMATCH[1]}"
        body="${BASH_REMATCH[2]}"
        parse_body "$body"
        if [[ "$section" == "labels" ]]; then
            emit_block "label" "$name"
            : $((n_labels++))
        else
            # `processes:` row — emit a withName: only if there's an override
            # (any of cpus/memory_gb/time_h). Label-only rows are informational
            # documentation; no withName needed.
            if [[ -n "$_cpus" || -n "$_memory_gb" || -n "$_time_h" ]]; then
                emit_block "override" "$name"
                : $((n_overrides++))
            fi
        fi
    fi
done < "$INPUT"

# ─── emit ──────────────────────────────────────────────────────────────────

input_basename="$(basename "$INPUT")"
output_basename="$(basename "$OUTPUT")"

{
    cat <<EOF
/*
 *  ${output_basename}
 *  ────────────────────────────────────────────────────────────────────────
 *  AUTO-GENERATED from ${input_basename} by metagear-tools/lib/build_resources_config.sh
 *  DO NOT EDIT BY HAND. Edit ${input_basename} and re-run the generator.
 *
 *  Layered semantics:
 *    - \`withLabel:\` blocks define resource tiers consumed by \`label '...'\`
 *      declarations in modules.
 *    - \`withName:\` blocks override resources for individual processes.
 *    - Memory/time are wrapped in \`* task.attempt\` for retry escalation;
 *      \`process.resourceLimits\` (in nextflow.config) caps the result.
 */

process {

EOF

    if (( ${#OUT_LABELS[@]} > 0 )); then
        echo "    /* ===== Resource tiers (consumed by \`label '<name>'\` in modules) ===== */"
        echo ""
        printf '%s\n' "${OUT_LABELS[@]}"
    fi

    if (( ${#OUT_OVERRIDES[@]} > 0 )); then
        echo "    /* ===== Per-process overrides ===== */"
        echo ""
        printf '%s\n' "${OUT_OVERRIDES[@]}"
    fi

    echo "}"
} > "$OUTPUT"

echo "Wrote ${OUTPUT}: ${n_labels} labels, ${n_overrides} overrides."
