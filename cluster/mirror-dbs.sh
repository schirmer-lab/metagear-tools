#!/usr/bin/env bash
# mirror-dbs.sh - mirror the MetaGEAR databases from /nfs onto a node's local disk.
#
#   mirror-dbs.sh [plan|sync|verify|manifest] [jobs] [filter]
#
# `filter` narrows every mode to the databases whose path contains it, which is how
# you re-copy or re-check just one after a failure:  mirror-dbs.sh sync 1 iphop141
#
# Run this ON the destination node (Node01). The writes are then local and only the
# reads cross NFS, which is the way round that matters: /data does ~830 MB/s under
# concurrent writers, the 10 GbE NFS link is the bottleneck either way, and a local
# write does not compete with the pipeline's own NFS traffic.
#
# Incremental and safe to re-run. rsync skips what is already in place, so an
# interrupted mirror is resumed by running `sync` again - there is no separate
# resume mode and no state to clean up.
#
# The tree under DEST mirrors /nfs/data/database exactly, path for path. That is
# deliberate, and it is the whole point of the layout: it lets a later bind mount
# route Node01's tasks to the local copy without editing a single database path in
# metagear.config. A partial mirror would then hide the databases it is missing,
# so the list below is every database the config references, not a subset.

set -uo pipefail

SRC=${METAGEAR_DB_SRC:-/nfs/data/database}
# No default: a mirror root is a decision about a particular disk on a particular machine, and
# guessing one means writing a terabyte of databases somewhere nobody chose.
DEST=${METAGEAR_DB_MIRROR:?set METAGEAR_DB_MIRROR to the local mirror root, e.g. /data/db}
LOGS=${DEST}-mirror-logs   # outside DEST, so the mirror stays a faithful copy
MANIFEST=${DEST}.manifest  # what the HQ worker reads to build its bind list
MODE=${1:-plan}
JOBS=${2:-4}
FILTER=${3:-}

# Every database metagear.config points at, as a path relative to $SRC, with its
# measured size in GiB. Ordered largest first: with $JOBS workers that keeps the
# long tail from being what everyone waits on at the end.
DBS=(
    "metagear/mmseqs_taxa|317.0"
    "metagear/iphop141|293.7"
    "metagear/dram|162.2"
    "metagear/gtdb_tk/r226|137.4"
    "metagear/humann/uniref|33.8"
    "metagear/metaphlan/vJun23|33.6"
    "metagear/humann/chocophlan|15.4"
    "metagear/phold|13.0"
    "metagear/virsorter2|11.0"
    "metagear/checkv|6.4"
    "hg38_bt2|4.0"
    "metagear/checkm2|2.9"
    "metagear/pharokka|1.9"
    "metagear/phabox|1.6"
    "metagear/genomad|1.4"
    "metagear/amrfinderplus|0.04"
)

if [ -n "$FILTER" ]; then
    SELECTED=()
    for entry in "${DBS[@]}"; do
        case "${entry%%|*}" in *"$FILTER"*) SELECTED+=("$entry") ;; esac
    done
    [ ${#SELECTED[@]} -gt 0 ] || { echo "no database matches '$FILTER'" >&2; exit 1; }
    DBS=("${SELECTED[@]}")
fi

# -a minus -og: the sources are owned by half the lab, and a non-root rsync cannot
# reproduce that. Permissions and mtimes are preserved, which is all that matters -
# the mtimes are also what make the re-run cheap.
#
# A function, not an array: xargs spawns a fresh bash for each database, and bash
# carries exported functions into it but never arrays.
mirror_rsync() {
    rsync -rlptD --no-o --no-g --partial --human-readable "$@"
}

write_manifest() {
    local rel present=0
    {
        echo "# metagear database mirror - written by mirror-dbs.sh, read by cluster-worker.sh"
        echo "# src=$SRC"
        for entry in "${DBS[@]}"; do
            rel=${entry%%|*}
            # Only what is actually here. A half-finished mirror then binds only the
            # databases it really holds, and the rest keep being read over NFS.
            [ -e "$DEST/$rel" ] && { echo "$rel"; present=$((present + 1)); }
        done
    } > "$MANIFEST"
    echo "manifest: $present database(s) listed in $MANIFEST"
}

copy_one() {
    local entry="$1" rel size parent slug log
    rel=${entry%%|*}; size=${entry##*|}
    parent=$(dirname "$rel")
    slug=${rel//\//_}
    log="$LOGS/$slug.log"
    mkdir -p "$DEST/$parent" "$LOGS" || return 1
    echo "[$(date +%H:%M:%S)] start $rel (${size} GiB)"
    # No trailing slash on the source: it copies the entry itself into the parent,
    # which is what makes this work unchanged for checkm2, a single 3 GB file.
    if mirror_rsync --info=stats2 "$SRC/$rel" "$DEST/$parent/" > "$log" 2>&1; then
        echo "[$(date +%H:%M:%S)] done  $rel"
    else
        echo "[$(date +%H:%M:%S)] FAIL  $rel  (see $log)"
        return 1
    fi
}

verify_one() {
    local entry="$1" rel parent diff
    rel=${entry%%|*}; parent=$(dirname "$rel")
    # -n -i: rsync itself is the comparison. Anything it would still transfer is a
    # difference, so an empty result is the mirror being complete and current.
    diff=$(mirror_rsync -ni "$SRC/$rel" "$DEST/$parent/" 2>/dev/null | grep -vc '^$')
    if [ "$diff" = "0" ]; then
        printf '  %-34s in sync\n' "$rel"
    else
        printf '  %-34s %s item(s) still to copy\n' "$rel" "$diff"
    fi
}

export -f copy_one verify_one mirror_rsync
export SRC DEST LOGS

case "$MODE" in
    plan)
        total=0
        echo "source:      $SRC"
        echo "destination: $DEST   (on $(hostname))"
        echo "parallel:    $JOBS rsync jobs"
        echo
        printf '  %-34s %8s  %s\n' DATABASE GiB STATUS
        for entry in "${DBS[@]}"; do
            rel=${entry%%|*}; size=${entry##*|}
            total=$(awk -v a="$total" -v b="$size" 'BEGIN{printf "%.1f", a+b}')
            if [ -e "$DEST/$rel" ]; then status="present (would re-check)"; else status="to copy"; fi
            [ -e "$SRC/$rel" ] || status="MISSING AT SOURCE"
            printf '  %-34s %8s  %s\n' "$rel" "$size" "$status"
        done
        echo
        printf '  %-34s %8s GiB\n' TOTAL "$total"
        echo
        df -h "$(dirname "$DEST")" | tail -1 | awk '{printf "  free on %s: %s of %s\n", $6, $4, $2}'
        echo
        echo "nothing was written. run:  $0 sync $JOBS"
        ;;
    sync)
        mkdir -p "$DEST" "$LOGS" || { echo "cannot create $DEST" >&2; exit 1; }
        echo "mirroring $SRC -> $DEST with $JOBS parallel jobs; logs in $LOGS"
        echo "started $(date)"
        printf '%s\n' "${DBS[@]}" | xargs -P "$JOBS" -I{} bash -c 'copy_one "$@"' _ {}
        rc=$?
        echo "finished $(date)"
        du -sh "$DEST" 2>/dev/null
        write_manifest
        [ $rc -eq 0 ] && echo "all databases mirrored" || echo "one or more failed - re-run 'sync' to retry only what is missing" >&2
        exit $rc
        ;;
    manifest)
        write_manifest
        ;;
    verify)
        echo "comparing $DEST against $SRC (dry run, nothing written)"
        for entry in "${DBS[@]}"; do verify_one "$entry"; done
        ;;
    *)
        echo "usage: $0 {plan|sync|verify|manifest} [jobs] [filter]" >&2; exit 1 ;;
esac
