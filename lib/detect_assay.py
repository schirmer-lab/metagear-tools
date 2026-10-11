#!/usr/bin/env python3
"""Guess whether a samplesheet holds DNA or RNA libraries, or say it cannot tell.

What separates them is not rRNA content -- measuring that means aligning against the very
reference the answer would select -- but how concentrated the library is. An RNA library is
dominated by a handful of transcripts; a shotgun DNA library is not, even when almost all of it
is host. The share of reads taken by the ten commonest sequences measures that directly, from
the reads alone, in a few seconds.

Measured on this lab's own cohorts, under exactly the constants below: all 20 DNA samples
of hms_mri_2026/test_batch_prebiomics, and 20 RNA from kch-followup/90-1119906168.

    top-10 share   DNA  0.021% - 0.590%      RNA  3.02% - 24.3%

A gap of 5.1x. An earlier calibration on 12 hand-picked DNA samples put the DNA ceiling at
0.069% and claimed a 43x gap; measuring the whole batch found one sample 8.5x above the rest.
MUNICH-001-382_Vagina scores 0.590%: 4.6 M read pairs, 92% host, 1.2% surviving QC. It is the
low-biomass over-amplified library this docstring already warned was untested, and it is
concentrated for reasons that have nothing to do with being RNA. It is also real data from the
lab's own test batch, so the thresholds have to hold for it.

The margin is consequently 1.7x above the highest DNA sample and 1.5x below the lowest RNA one,
not the 3x claimed before. That is thin enough that `--assay` remains the dependable answer and
this is a convenience; anything landing between the thresholds is reported as unknown rather
than guessed, and the caller is told which sample was responsible.

Two cohorts from two facilities is still the whole of the evidence. The mechanism is biological
rather than instrumental, which is why it is worth trusting at all, but an amplicon library or a
single-isolate genome at depth would both be concentrated without being RNA, and neither was
tested.

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
DNA_BELOW = 0.010  # 1.0%, 1.7x above the highest DNA sample measured (0.590%)
RNA_ABOVE = 0.020  # 2.0%, 1.5x below the lowest RNA sample measured (3.02%)

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

    # Keep the sample name alongside the score: when this refuses, the one thing the caller
    # needs is which library was responsible, not an aggregate they cannot act on.
    scored = [
        (r.get("sample") or r["fastq_1"], s)
        for r, s in ((r, concentration(r["fastq_1"].strip())) for r in rows[: args.samples])
        if s
    ]
    if not scored:
        print("unknown")
        return 0
    scores = [s for _, s in scored]

    # Every sample inspected has to agree. A sheet whose rows disagree is either mixed or is a
    # case the thresholds do not cover, and both want a person rather than a default.
    if all(s < DNA_BELOW for s in scores):
        answer = "dna"
    elif all(s > RNA_ABOVE for s in scores):
        answer = "rna"
    else:
        answer = "unknown"

    print(answer)
    name, worst = max(scored, key=lambda pair: pair[1])
    if answer == "unknown":
        # Name the sample, its score and the band it missed. The caller turns this into a
        # stopped run, and "could not tell" with no number is not something anyone can act on.
        print(
            f"detect-assay: cannot tell DNA from RNA. {name} has a top-10 read share of "
            f"{100 * worst:.3f}%, between the DNA ceiling ({100 * DNA_BELOW:.1f}%) and the RNA "
            f"floor ({100 * RNA_ABOVE:.1f}%). Pass --assay dna or --assay rna.",
            file=sys.stderr,
        )
        return 0
    print(
        f"detect-assay: {answer}, top-10 read share {100 * worst:.3f}% over "
        f"{len(scores)} sample(s), highest {name}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
