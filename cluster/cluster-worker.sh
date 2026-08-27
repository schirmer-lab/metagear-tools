#!/usr/bin/env bash
# Start a HyperQueue worker on this node and attach it to the MetaGEAR cluster.
#
# Invoked by `metagear-cluster up`, locally on the server node and over ssh on
# the others. Sizes itself from this node's own /proc, so the same script gives
# 144c/566G on Node02 and 48c/377G on Node01 without a hardcoded table.
#
# Args: <server_dir> <server_ip> <worker_port> <pct> <label> <scratch_root> <scratch_slots> [db_mirror]
set -euo pipefail

# `--sweep-only <root>` reclaims scratch and returns, so `metagear-cluster sweep` can reuse
# this exact logic rather than keeping a second copy of it.
if [ "${1:-}" = "--sweep-only" ]; then
    SWEEP_ONLY_ROOT="$2"
else
    SERVER_DIR="$1"; SERVER_IP="$2"; WORKER_PORT="$3"; PCT="$4"
    LABEL="$5"; SCRATCH_ROOT="$6"; SLOTS="$7"; DB_MIRROR="${8:--}"
fi

# A task's scratch directory is its working directory, so a live one is held open by the
# process running in it and `fuser` sees that. Killing a run - which is how you stop a
# pipeline - leaves its directories behind with nothing holding them, and the previous
# rule (older than 180 minutes, only at `up`) let those survive for hours. Ask what is
# actually in use instead: it is exact, and it is safe to run at any time, including
# while the other node is mid-cohort.
#
# The age floor is only a race guard, for the moment between a task creating its
# directory and chdir-ing into it.
sweep_scratch() {
    local root="$1" host="$2" freed=0 dir
    [ -d "$root" ] || return 0
    while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        fuser -s "$dir" 2>/dev/null && continue
        rm -rf "$dir" 2>/dev/null && freed=$((freed + 1))
    done < <(find "$root" -maxdepth 1 -name 'nxf.*' -type d -mmin +2 2>/dev/null)
    [ "$freed" -gt 0 ] && echo "[$host] swept $freed orphaned scratch dir(s)"
    return 0
}

if [ -n "${SWEEP_ONLY_ROOT:-}" ]; then
    sweep_scratch "$SWEEP_ONLY_ROOT" "$(hostname -s)"
    exit 0
fi

HQ_BIN="$(dirname "$(readlink -f "$0")")/bin/hq"
LOG_DIR="$(dirname "$(readlink -f "$0")")/logs"
HOST="$(hostname -s)"
mkdir -p "$LOG_DIR"

# $PCT of this node's cores and RAM. HyperQueue reads `mem` in MiB, which is the
# same unit Nextflow emits for `--resource mem=` (MemoryUnit.toMega), so a
# `memory 120.GB` directive packs against this pool exactly as executor.memory
# does for the local executor.
#
# CPU may be oversubscribed past 100%: HyperQueue will then hand out more cores
# than exist and the tasks share them, which is only inefficient. Memory may not,
# and the cap here is deliberately not the caller's business - a worker that
# promises more RAM than the machine has gets its tasks killed by the OOM killer,
# which ends the run's stage rather than slowing it. Same ceiling as metagear.env
# applies to a single-node run, so the two modes behave identically.
MEM_CEILING_PCT=95
MEM_PCT=$PCT
[ "$MEM_PCT" -gt "$MEM_CEILING_PCT" ] && MEM_PCT=$MEM_CEILING_PCT
CPUS=$(( $(nproc) * PCT / 100 ))
[ "$CPUS" -lt 1 ] && CPUS=1
MEM_MIB=$(awk -v p="$MEM_PCT" '/MemTotal/ { printf "%d", $2 / 1024 * p / 100 }' /proc/meminfo)

# Two resources, doing different jobs.
#
# `diskio` rations scratch-heavy processes: both nodes have it, so those
# processes run on either, but only $SLOTS of them at once here. Sized to this
# node's scratch disk, not to its cores.
#
# The node's own name is a pool large enough never to bind, so it works as a
# plain identity label for pinning something here by hand. The size matters:
# HyperQueue treats `sum(1)` as a single unit, so a resource with a pool of one
# becomes a mutex and serialises the whole node to one task at a time -
# placement still looks correct in `hq worker list`, which makes it a silent
# throughput bug rather than a visible failure.
LABEL_POOL=1000000

# Prefer a direct connection to the server. Node02 runs ufw and drops inbound
# from Node01, so fall back to an ssh tunnel plus a local copy of access.json
# with worker.host rewritten to 127.0.0.1. Adding
#   sudo ufw allow from <other node> to any port <client>,<worker> proto tcp
# on the server node makes the direct path succeed and skips all of this.
USE_DIR="$SERVER_DIR"
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${SERVER_IP}/${WORKER_PORT}" 2>/dev/null; then
    echo "[$HOST] direct connection to ${SERVER_IP}:${WORKER_PORT}"
else
    echo "[$HOST] direct connection blocked - using ssh tunnel"
    # Reuse a live tunnel if one is already forwarding; only rebuild when it is
    # absent or dead. Bind explicitly to 127.0.0.1 so ssh does not also try
    # [::1], which fails with "Address already in use" against a stale tunnel.
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${WORKER_PORT}" 2>/dev/null; then
        echo "[$HOST] reusing existing tunnel on 127.0.0.1:${WORKER_PORT}"
    else
        pkill -f ":127.0.0.1:${WORKER_PORT} " 2>/dev/null || true
        pkill -f ":127.0.0.1:${WORKER_PORT}$" 2>/dev/null || true
        sleep 1
        ssh -N -f -o BatchMode=yes -o ExitOnForwardFailure=yes \
            -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
            -L "127.0.0.1:${WORKER_PORT}:127.0.0.1:${WORKER_PORT}" "${METAGEAR_CLUSTER_USER:-$USER}@${SERVER_IP}" \
            || { echo "[$HOST] ssh tunnel failed" >&2; exit 1; }
        sleep 2
    fi
    USE_DIR="/tmp/metagear-hq-server"
    rm -rf "$USE_DIR"; mkdir -p "$USE_DIR/001"
    python3 - "$SERVER_DIR/hq-current/access.json" "$USE_DIR/001/access.json" <<'PY'
import json, os, sys
cfg = json.load(open(sys.argv[1]))
cfg["worker"]["host"] = "127.0.0.1"
with open(sys.argv[2], "w") as fh:
    json.dump(cfg, fh)
os.chmod(sys.argv[2], 0o400)
PY
    ln -sfn "$USE_DIR/001" "$USE_DIR/hq-current"
fi

# Local scratch root. Tasks run here and only their declared outputs are copied
# back to the shared work dir, so this is where the sort temps and assembly
# intermediates land instead of on NFS.
mkdir -p "$SCRATCH_ROOT" 2>/dev/null || echo "[$HOST] warning: cannot create $SCRATCH_ROOT"

sweep_scratch "$SCRATCH_ROOT" "$HOST"
if [ -d "$SCRATCH_ROOT" ]; then
    echo "[$HOST] scratch $SCRATCH_ROOT - $(df -h "$SCRATCH_ROOT" | awk 'NR==2{print $4" free of "$2}')"
fi

# METAGEAR_SCRATCH is how a single `scratch` value in the Nextflow config resolves
# to a different path per node. Nextflow only ever runs on Node02, so its config is
# one string for the whole cluster — but that string is expanded inside the job
# script, on whichever node runs the task. HyperQueue passes the worker's
# environment through to its tasks, so exporting it here is what makes it per-node.
export METAGEAR_SCRATCH="$SCRATCH_ROOT"

# METAGEAR_DB_BIND is the same hinge applied to the databases: the Nextflow config
# carries one literal '$METAGEAR_DB_BIND', and each worker fills it in with the
# mirror it actually has. Node02 has none, so it expands to nothing there and the
# databases keep being read from /nfs.
#
# One bind per database rather than one bind of the whole database root. A root
# bind would REPLACE /nfs/data/database inside the container, so any database not
# in the mirror would disappear instead of falling back to NFS. Bound one by one
# the mirror is purely additive, and a partial mirror is merely partial.
#
# The list comes from the mirror's own manifest, so this script never holds a
# second copy of it to drift out of step with mirror-dbs.sh.
DB_BIND=""
DB_COUNT=0
if [ "${DB_MIRROR:--}" != "-" ] && [ -f "${DB_MIRROR}.manifest" ]; then
    DB_SRC=$(sed -n 's/^# src=//p' "${DB_MIRROR}.manifest" | head -1)
    if [ -n "$DB_SRC" ]; then
        while IFS= read -r rel; do
            case "$rel" in ''|'#'*) continue ;; esac
            [ -e "$DB_MIRROR/$rel" ] || continue
            DB_BIND="$DB_BIND -B $DB_MIRROR/$rel:$DB_SRC/$rel"
            DB_COUNT=$((DB_COUNT + 1))
        done < "${DB_MIRROR}.manifest"
    fi
fi
export METAGEAR_DB_BIND="$DB_BIND"
if [ "$DB_COUNT" -gt 0 ]; then
    echo "[$HOST] database mirror $DB_MIRROR - $DB_COUNT served locally"
else
    echo "[$HOST] no database mirror - reading databases from /nfs"
fi

HQ_SERVER_DIR="$USE_DIR" setsid nohup "$HQ_BIN" worker start \
    --cpus="$CPUS" \
    --resource "mem=sum(${MEM_MIB})" \
    --resource "diskio=sum(${SLOTS})" \
    --resource "${LABEL}=sum(${LABEL_POOL})" \
    > "$LOG_DIR/worker-${HOST}.log" 2>&1 < /dev/null &

sleep 3
if pgrep -x hq > /dev/null; then
    if [ "$MEM_PCT" != "$PCT" ]; then
        echo "[$HOST] worker up: ${CPUS} cpus (${PCT}%), ${MEM_MIB} MiB (held at ${MEM_CEILING_PCT}%), ${SLOTS} scratch slot(s)"
    else
        echo "[$HOST] worker up: ${CPUS} cpus, ${MEM_MIB} MiB (${PCT}%), ${SLOTS} scratch slot(s)"
    fi
else
    echo "[$HOST] WORKER FAILED - see $LOG_DIR/worker-${HOST}.log" >&2
    tail -5 "$LOG_DIR/worker-${HOST}.log" >&2
    exit 1
fi
