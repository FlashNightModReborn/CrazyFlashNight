#!/usr/bin/env python3
"""Reproducible latency distribution benchmark for the route-A compiler."""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import time
from dataclasses import asdict
from pathlib import Path

from prime_magic.compiler import CompilerConfig, _derive_seed, _load_semimagic, compile_upgrade


def percentile(sorted_values: list[float], probability: float) -> float:
    position = (len(sorted_values) - 1) * probability
    lower = int(position)
    upper = min(lower + 1, len(sorted_values) - 1)
    fraction = position - lower
    return sorted_values[lower] + (sorted_values[upper] - sorted_values[lower]) * fraction


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--seed", type=int, default=20260805)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    matrix, magic_sum = _load_semimagic(args.input)

    records = []
    failures = []
    started = time.perf_counter()
    for index in range(args.samples):
        compiler_seed = _derive_seed(args.seed, index)
        config = CompilerConfig(seed=compiler_seed)
        try:
            result = compile_upgrade(matrix, magic_sum, config)
            records.append(
                {
                    "index": index,
                    "seed": compiler_seed,
                    "elapsedSeconds": result.stats["elapsed_seconds"],
                    "candidateMoves": result.stats["candidate_moves"],
                    "candidateMovesPerSecond": result.stats["candidate_moves_per_second"],
                    "peakRssKiB": result.stats["peak_rss_kib"],
                }
            )
        except RuntimeError as exc:
            failures.append({"index": index, "seed": compiler_seed, "error": str(exc)})

    latencies = sorted(record["elapsedSeconds"] for record in records)
    payload = {
        "format": "prime-magic-compiler-benchmark/v1",
        "machine": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "processor": platform.processor(),
            "logicalCpuCount": __import__("os").cpu_count(),
        },
        "configuration": {
            "samples": args.samples,
            "baseSeed": args.seed,
            "compilerConfig": asdict(CompilerConfig(seed=0)),
        },
        "summary": {
            "successes": len(records),
            "failures": len(failures),
            "wallSeconds": time.perf_counter() - started,
            "latencySeconds": {
                "min": min(latencies) if latencies else None,
                "median": statistics.median(latencies) if latencies else None,
                "p95": percentile(latencies, 0.95) if latencies else None,
                "p99": percentile(latencies, 0.99) if latencies else None,
                "max": max(latencies) if latencies else None,
                "mean": statistics.mean(latencies) if latencies else None,
            },
            "candidateMovesPerSecondMedian": statistics.median(
                record["candidateMovesPerSecond"] for record in records
            ) if records else None,
            "peakRssKiBMax": max((record["peakRssKiB"] for record in records), default=None),
        },
        "records": records,
        "failureRecords": failures,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload["summary"], indent=2, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
