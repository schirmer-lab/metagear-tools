#!/usr/bin/env python3
"""Guess whether a samplesheet holds DNA or RNA libraries, or say it cannot tell.

What separates them is not rRNA content -- measuring that means aligning against the very
reference the answer would select -- but how concentrated the library is. An RNA library is
dominated by a handful of transcripts; a shotgun DNA library is not, even when almost all of it
is host. The share of reads taken by the ten commonest sequences measures that directly, from
the reads alone, in a few seconds.

Measured on this lab's own cohorts (12 DNA samples from hms_mri_2026, 12 RNA from kch-followup,
300k reads each after skipping the first 200k):

    top-10 share   DNA  0.016% - 0.078%      RNA  3.0% - 28.4%

A gap of 39x, with the closest DNA sample being one that was 98.8% human. The thresholds below
sit either side of that gap with an order of magnitude to spare in both directions, and anything
landing between them is reported as unknown rather than guessed. The caller must then be told
which it is: a wrong answer here is silent, and the run that follows looks entirely normal.

Prints "dna", "rna" or "unknown", and exits 0 unless something went wrong reading the input.
"""

import argparse
import collections
import csv
import gzip
import sys

# Either side of a 39x gap. Chosen for the room on both sides rather than fitted to the samples:
# a library landing between them is one nobody has measured, and that is the case to refuse.
DNA_BELOW = 0.005  # 0.5%, about 6x above the highest DNA sample seen
RNA_ABOVE = 0.015  # 1.5%, about 2x below the lowest RNA sample seen

READS = 200_000  # per sample, after the skip
SKIP = 100_000  # the first tile of a flow cell is not representative of the run
PREFIX = 50  # bases compared, so differing read lengths do not matter


def concentration(path: str) -> float | None:
    """Share of reads taken by the ten commonest sequences. None if the file cannot be read."""
    seen: list[str] = []
    try:
        with gzip.open(path, "rt") as handle:
            for index, line in enumerate(handle):
                if index % 4 != 1:
                    continue
                if index // 4 < SKIP:
                    continue
                seen.append(line.strip()[:PREFIX])
                if len(seen) >= READS:
                    break
    except (OSError, EOFError):
        return None
    # Too few reads to say anything: a tiny file is not evidence either way.
    if len(seen) < 20_000:
        return None
    counts = collections.Counter(seen)
    return sum(n for _, n in counts.most_common(10)) / len(seen)


def main() -> int:
    parsed = argparse.ArgumentParser(description=__doc__)
    parsed.add_argument("samplesheet")
    parsed.add_argument("--samples", type=int, default=3, help="how many rows to look at")
    args = parsed.parse_args()

    try:
        with open(args.samplesheet, newline="", encoding="utf-8") as handle:
            rows = [r for r in csv.DictReader(handle) if (r.get("fastq_1") or "").strip()]
    except (OSError, csv.Error):
        print("unknown")
        return 0

    scores = [s for s in (concentration(r["fastq_1"].strip()) for r in rows[: args.samples]) if s]
    if not scores:
        print("unknown")
        return 0

    # Every sample inspected has to agree. A sheet whose rows disagree is either mixed or is a
    # case the thresholds do not cover, and both want a person rather than a default.
    if all(s < DNA_BELOW for s in scores):
        answer = "dna"
    elif all(s > RNA_ABOVE for s in scores):
        answer = "rna"
    else:
        answer = "unknown"

    print(answer)
    worst = max(scores)
    print(
        f"detect-assay: top-10 read share {100 * worst:.3f}% over {len(scores)} sample(s)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
