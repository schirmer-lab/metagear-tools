#!/usr/bin/env python3
"""Guess whether a samplesheet holds DNA or RNA libraries, or say it cannot tell.

What separates them is not rRNA content -- measuring that means aligning against the very
reference the answer would select -- but how concentrated the library is. An RNA library is
dominated by a handful of transcripts; a shotgun DNA library is not, even when almost all of it
is host. The share of reads taken by the ten commonest sequences measures that directly, from
the reads alone, in a few seconds.

Measured on this lab's own cohorts, under exactly the constants below (12 DNA samples from
hms_mri_2026, 12 RNA from kch-followup):

    top-10 share   DNA  0.021% - 0.069%      RNA  3.02% - 28.3%

A gap of 43x. The closest DNA sample to it was MUNICH-001-518_Vagina, which was 67% host, so
host content alone does not push a DNA library into the RNA range. The thresholds below sit
about 3x clear of the nearest measured sample on each side, and anything landing between them
is reported as unknown rather than guessed. The caller must then be told which it is: a wrong
answer here is silent, and the run that follows looks entirely normal.

Two cohorts from two facilities is the whole of the evidence. The mechanism is biological
rather than instrumental, which is why it is worth trusting at all, but an amplicon library, a
single-isolate genome at depth or an over-amplified low-biomass library would all be
concentrated for reasons that have nothing to do with being RNA, and none was tested.

Prints "dna", "rna" or "unknown", and exits 0 unless something went wrong reading the input.
"""

import argparse
import collections
import csv
import gzip
import sys

# Either side of the gap, with the same multiplicative margin on each so neither class is
# favoured. A library landing between them is one nobody here has measured, and that is exactly
# the case to refuse rather than round to the nearer side.
DNA_BELOW = 0.002  # 0.2%, about 3x above the highest DNA sample measured (0.069%)
RNA_ABOVE = 0.010  # 1.0%, about 3x below the lowest RNA sample measured (3.02%)

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
