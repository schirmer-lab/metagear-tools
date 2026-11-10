#!/usr/bin/env python3
"""Size the abundance processes for one node, from what earlier runs actually used.

Mapping against a large catalog is bounded by memory, not cores: every concurrent
bwa mem holds its own copy of the index, and the counting and merge steps hold a
whole feature-by-sample table. Nextflow's local executor does not enforce the
declared memory, it only bin-packs by it, so a declaration well below real use
makes it start more tasks than the node can hold.

This reads the peak_rss of earlier runs out of their execution traces, pairs each
assay's numbers with the size of the bwa index it mapped against, and projects
from there to a new catalog and library count. Every number it prints is either
measured or derived from measurements it names.

Usage:
    check_mapping_resources.py --cpus 224 --memory-gb 480 \\
        --results-root /path/to/results-parent \\
        --catalog-bases 7441251543 --libraries 350 \\
        [--resources conf/resources.yaml] [--batch-size 50] [--class all.genes]
"""

import argparse
import glob
import os
import re
import statistics
import sys

# bwa's index is .bwt + .sa + .pac, which scale with bases, plus .ann, which scales
# with the number of sequences. Both rates are measured from the reference assay's
# own published index rather than assumed.

# The nf-core bwa/index module requests `6.B * fasta.size()`.
BWA_INDEX_REQUEST_FACTOR = 6

PROCESSES = ("COVERM_MAKE", "COVERM_CONTIG", "COVERM_CONTIG_MERGE")

ENTRY = re.compile(r"^\s*'?([A-Za-z0-9_.*()\[\]\\-]+)'?:\s*\{(.*)\}\s*$")
SIZE = re.compile(r"([\d.]+)\s*([KMGT]?B)")
UNITS = {"B": 1e-9, "KB": 1e-6, "MB": 1e-3, "GB": 1.0, "TB": 1e3}


def parse_resources(path):
    """Read the `processes:` rows of the restricted YAML build_resources_config.sh accepts."""
    rows, section = {}, None
    with open(path) as handle:
        for raw in handle:
            line = raw.split("#", 1)[0].rstrip()
            if not line.strip():
                continue
            if not line.startswith(" "):
                section = line.rstrip(":").strip()
                continue
            match = ENTRY.match(line)
            if not match or section != "processes":
                continue
            fields = {}
            for part in match.group(2).split(","):
                if ":" in part:
                    key, value = part.split(":", 1)
                    fields[key.strip()] = value.strip().strip('"').strip("'")
            rows[match.group(1)] = fields
    return rows


def to_minutes(value):
    total = 0.0
    for number, unit in re.findall(r"([\d.]+)\s*(ms|s|m|h)", value.strip()):
        total += float(number) * {"ms": 1 / 60000, "s": 1 / 60, "m": 1.0, "h": 60.0}[unit]
    return total


def to_gb(value):
    match = SIZE.match(value.strip())
    return float(match.group(1)) * UNITS[match.group(2)] if match else None


def index_sizes(results_root, klass):
    """Index size per assay, and its per-base and per-sequence parts, as published."""
    sizes, parts = {}, {}
    for path in sorted(glob.glob(os.path.join(results_root, "results-*", "abundance", klass, "bwa_index"))):
        assay = path.split("results-")[1].split(os.sep)[0]
        by_ext = {}
        for root, _, names in os.walk(path):
            for name in names:
                by_ext[os.path.splitext(name)[1]] = by_ext.get(os.path.splitext(name)[1], 0) + \
                    os.path.getsize(os.path.join(root, name))
        total = sum(by_ext.values())
        if total:
            sizes[assay] = total / 1e9
            parts[assay] = {"per_base": sum(by_ext.get(e, 0) for e in (".bwt", ".sa", ".pac")),
                            "per_seq": by_ext.get(".ann", 0)}
    return sizes, parts


def catalog_shape(results_root, assay, klass):
    """Sequences and bases of the catalog an assay indexed."""
    pattern = os.path.join(results_root, f"results-{assay}", "catalogs", "genes",
                           f"{klass}.representative.fa.gz")
    matches = glob.glob(pattern)
    if not matches:
        return None, None
    import gzip
    sequences = bases = 0
    with gzip.open(matches[0], "rb") as handle:
        for line in handle:
            if line.startswith(b">"):
                sequences += 1
            else:
                bases += len(line.strip())
    return sequences, bases


def trace_peaks(results_root, klass):
    """peak_rss per assay and process, for tasks that ran against this catalog class."""
    peaks = {}
    for path in glob.glob(os.path.join(results_root, "results-*", "pipeline_info", "*execution_trace*.txt")):
        assay = path.split("results-")[1].split(os.sep)[0]
        with open(path) as handle:
            header = handle.readline().rstrip("\n").split("\t")
            idx = {key: i for i, key in enumerate(header)}
            if "peak_rss" not in idx:
                continue
            for line in handle:
                fields = line.rstrip("\n").split("\t")
                if len(fields) < len(header) or fields[idx["status"]] != "COMPLETED":
                    continue
                name = fields[idx["name"]]
                process = name.split(" (")[0].split(":")[-1]
                if process not in PROCESSES:
                    continue
                tag = name.split(" (")[1].rstrip(")") if " (" in name else ""
                if ": " in tag:                      # COVERM_MAKE: "<sample>: <class>"
                    tag = tag.split(": ", 1)[1]
                if re.sub(r"_(\d+|count|rpkm|tpm|covered_bases)$", "", tag) != klass:
                    continue
                rss = to_gb(fields[idx["peak_rss"]])
                cpu = fields[idx["%cpu"]].rstrip("%")
                if rss is not None:
                    peaks.setdefault((assay, process), []).append(
                        (rss, float(cpu) if re.match(r"^[\d.]+$", cpu) else None,
                         to_minutes(fields[idx["realtime"]])))
    return peaks


def table_shape(results_root, assay, klass):
    """Features and libraries of a published matrix: rows and columns of <class>.count.tsv."""
    path = os.path.join(results_root, f"results-{assay}", "abundance", klass, f"{klass}.count.tsv")
    if not os.path.exists(path):
        return None, None
    with open(path, "rb") as handle:
        libraries = len(handle.readline().rstrip(b"\n").split(b"\t")) - 1
        rows = 0
        while True:
            chunk = handle.read(1 << 22)
            if not chunk:
                break
            rows += chunk.count(b"\n")
    return rows, libraries


def summarise(values):
    rss = sorted(v[0] for v in values)
    cpu = [v[1] for v in values if v[1] is not None]
    minutes = [v[2] for v in values if len(v) > 2 and v[2]]
    p95 = rss[min(len(rss) - 1, int(0.95 * len(rss)))]
    return (len(rss), statistics.median(rss), p95, max(rss),
            statistics.median(cpu) if cpu else 0.0,
            statistics.median(minutes) if minutes else 0.0)


def fit_line(points):
    """Least squares through (x, y); returns (intercept, slope) or None for fewer than two x values."""
    xs = sorted({x for x, _ in points})
    if len(xs) < 2:
        return None
    n = len(points)
    mean_x = sum(x for x, _ in points) / n
    mean_y = sum(y for _, y in points) / n
    denom = sum((x - mean_x) ** 2 for x, _ in points)
    if denom == 0:
        return None
    slope = sum((x - mean_x) * (y - mean_y) for x, y in points) / denom
    return mean_y - slope * mean_x, slope


def concurrency(cpus, memory_gb, task_cpus, task_memory_gb, tasks=None):
    by_cpu = cpus // task_cpus if task_cpus else 0
    by_memory = int(memory_gb // task_memory_gb) if task_memory_gb else 0
    n = min(by_cpu, by_memory)
    if tasks is not None:
        n = min(n, tasks)
    return n, by_cpu, by_memory


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cpus", type=int, required=True, help="max_cpus for the run")
    parser.add_argument("--memory-gb", type=float, required=True, help="max_memory for the run, in GB")
    parser.add_argument("--results-root", required=True,
                        help="directory holding the results-<assay> trees of earlier runs")
    parser.add_argument("--catalog-bases", type=int, required=True, help="bases in the new catalog")
    parser.add_argument("--catalog-features", type=int,
                        help="sequences in the new catalog (defaults to bases/824, this cohort's mean)")
    parser.add_argument("--libraries", type=int, required=True, help="libraries to map")
    parser.add_argument("--batch-size", type=int, default=50, help="files_batch_size (default 50)")
    parser.add_argument("--class", dest="klass", default="all.genes",
                        help="catalog class to learn from (default all.genes)")
    parser.add_argument("--resources", help="conf/resources.yaml, to report what is declared now")
    parser.add_argument("--safety", type=float, default=1.15,
                        help="multiplier on the projection when recommending (default 1.15)")
    args = parser.parse_args()

    sizes, index_parts = index_sizes(args.results_root, args.klass)
    peaks = trace_peaks(args.results_root, args.klass)
    if not sizes or not peaks:
        sys.exit(f"no indexes or traces for class {args.klass} under {args.results_root}")

    features = args.catalog_features
    if features is None:
        sys.exit("--catalog-features is required: the index has a per-sequence part")

    index_reference = max(sizes, key=lambda a: sizes[a])
    ref_seqs, ref_bases = catalog_shape(args.results_root, index_reference, args.klass)
    if not ref_bases:
        sys.exit(f"cannot measure {index_reference}'s catalog under {args.results_root}")
    rate_base = index_parts[index_reference]["per_base"] / ref_bases
    rate_seq = index_parts[index_reference]["per_seq"] / ref_seqs
    target_index = (args.catalog_bases * rate_base + features * rate_seq) / 1e9

    print(f"learning from {args.klass} in {args.results_root}")
    print(f"{index_reference} catalog: {ref_seqs:,} sequences, {ref_bases:,} bases, "
          f"index {sizes[index_reference]:.2f} GB")
    print(f"{'assay':6} {'index GB':>9} {'features':>10} {'libs':>5} {'process':22} "
          f"{'n':>5} {'med':>7} {'p95':>7} {'max':>7} {'%cpu':>6} {'min med':>8}")
    observed, shapes, runtimes = {}, {}, {}
    for assay in sorted(sizes):
        shapes[assay] = table_shape(args.results_root, assay, args.klass)
    for (assay, process), values in sorted(peaks.items()):
        if assay not in sizes:
            continue
        n, med, p95, mx, cpu, mins = summarise(values)
        feats, libs = shapes.get(assay, (None, None))
        print(f"{assay:6} {sizes[assay]:9.2f} {(feats or 0):10,d} {(libs or 0):5d} {process:22} "
              f"{n:5d} {med:7.1f} {p95:7.1f} {mx:7.1f} {cpu:6.0f} {mins:8.1f}")
        runtimes[(assay, process)] = mins
        observed.setdefault(process, []).append((sizes[assay], p95))
    print()

    print(f"new catalog: {args.catalog_bases:,} bases, {features:,} features, "
          f"{args.libraries} libraries")
    print(f"projected bwa index: {target_index:.1f} GB "
          f"({rate_base:.2f} bytes/base and {rate_seq:.0f} bytes/sequence, both measured on "
          f"{index_reference})")

    need = {}
    fit = fit_line(observed.get("COVERM_MAKE", []))
    if fit:
        intercept, slope = fit
        need["COVERM_MAKE"] = intercept + slope * target_index
        print(f"COVERM_MAKE         p95 fits {intercept:.1f} + {slope:.2f} x index GB over "
              f"{len(observed['COVERM_MAKE'])} assays -> {need['COVERM_MAKE']:.0f} GB per mapping")

    # The counting and merge steps hold per-feature state, so they scale on the
    # published table's own dimensions rather than on catalog bases.
    reference = max(((a, s) for a, s in sizes.items() if shapes.get(a, (None,))[0]),
                    key=lambda kv: kv[1], default=(None, None))[0]
    if reference:
        ref_features, ref_libraries = shapes[reference]
        for process, scale, why in (
            ("COVERM_CONTIG", features / ref_features, "features"),
            ("COVERM_CONTIG_MERGE", (features / ref_features) * (args.libraries / ref_libraries),
             "features and libraries"),
        ):
            values = peaks.get((reference, process))
            if not values:
                continue
            _, _, p95, _, _, _ = summarise(values)
            need[process] = p95 * scale
            print(f"{process:20}{p95:6.0f} GB measured on {reference} "
                  f"({ref_features:,} features, {ref_libraries} libraries), "
                  f"x{scale:.2f} by {why} -> {need[process]:.0f} GB")

    batches = -(-args.libraries // args.batch_size)
    tasks = {"COVERM_MAKE": args.libraries, "COVERM_CONTIG": batches, "COVERM_CONTIG_MERGE": 4}

    findings = []
    if args.resources and os.path.exists(args.resources):
        declared = parse_resources(args.resources)
        print()
        print(f"{'process':22} {'cpus':>5} {'declared':>9} {'projected':>10} {'starts':>7} "
              f"{'wants GB':>9} {'of':>5}")
        for process in PROCESSES:
            fields = declared.get(process)
            if not fields:
                continue
            task_cpus = int(fields.get("cpus", 0) or 0)
            task_memory = float(fields.get("memory_gb", 0) or 0)
            n, _, _ = concurrency(args.cpus, args.memory_gb, task_cpus, task_memory, tasks.get(process))
            projected = need.get(process)
            wants = n * projected if projected else None
            print(f"{process:22} {task_cpus:5d} {task_memory:9.0f} "
                  f"{(projected if projected else 0):10.0f} {n:7d} "
                  f"{(wants if wants else 0):9.0f} {args.memory_gb:5.0f}")
            if wants and wants > args.memory_gb:
                findings.append(f"{process}: the declared {task_memory:.0f} GB lets Nextflow start {n} "
                                f"at once, which would want {wants:.0f} GB on a {args.memory_gb:.0f} GB node")

    print()
    print("// conf/metagear/easy_map.config")
    print("process {")
    for process in PROCESSES:
        projected = need.get(process)
        if not projected:
            continue
        memory = int(projected * args.safety) + 1
        if process == "COVERM_MAKE":
            fits = int(args.memory_gb // memory)
            task_cpus = max(1, min(args.cpus // max(1, fits), args.cpus))
            print(f"    withName: '.*:EASY_MAP:ABUNDANCE:{process}' {{")
            print(f"        cpus   = {{ {task_cpus} * task.attempt }}")
            print(f"        memory = {{ {memory}.GB * task.attempt }}")
            print(f"    }}   // {fits} in parallel, {fits * task_cpus} of {args.cpus} cores")
        else:
            fits = max(1, int(args.memory_gb // memory))
            print(f"    withName: '.*:EASY_MAP:ABUNDANCE:{process}' {{")
            print(f"        memory = {{ {memory}.GB * task.attempt }}")
            print(f"    }}   // {fits} in parallel of {tasks.get(process)} task(s)")
    print("}")

    # Wall time, from the reference assay's own medians. Per-library time is not
    # scaled for the larger index or the thread count, so read it as a floor.
    if reference:
        parallel = {}
        for process in PROCESSES:
            projected = need.get(process)
            if not projected:
                continue
            memory = int(projected * args.safety) + 1
            fits = max(1, int(args.memory_gb // memory))
            if process == "COVERM_MAKE":
                fits = min(fits, args.cpus)
            parallel[process] = min(fits, tasks.get(process) or fits)
        total = 0.0
        print()
        for process in PROCESSES:
            per = runtimes.get((reference, process))
            if not per or process not in parallel:
                continue
            count = tasks.get(process) or 1
            waves = -(-count // parallel[process])
            stage = waves * per
            total += stage
            print(f"{process:22} {count:4d} task(s), {parallel[process]:2d} at a time, "
                  f"{per:6.1f} min each on {reference} -> {stage / 60:5.1f} h")
        print(f"{'total':22} {total / 60:.1f} h, plus the index build. Per-task time is held at "
              f"{reference}'s median, so a larger index pushes it up and more threads per task "
              f"pull it down; it is an estimate, not a bound.")

    if findings:
        print("\nfindings")
        for item in findings:
            print(f"  - {item}")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
