#!/usr/bin/env python3
"""Reproducibility and seed-sensitivity benchmark for the C++ search."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import statistics
import subprocess
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BINARY = HERE / "double_permutation_search"
INPUT = ROOT / "upload" / "prime_semimagic_19(2).json"


def one(seed: int, seconds: float) -> dict:
    output = HERE / f".benchmark_{seed}.json"
    p = subprocess.run(
        [str(BINARY), str(INPUT), str(output), str(seed), str(seconds)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    result = json.loads(output.read_text())
    output.unlink()
    result["process_returncode"] = p.returncode
    return result


def percentile(xs: list[float], q: float) -> float:
    ys = sorted(xs)
    pos = (len(ys) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(ys) - 1)
    return ys[lo] + (ys[hi] - ys[lo]) * (pos - lo)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=100)
    ap.add_argument("--seconds", type=float, default=1.0)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--output", type=Path, default=HERE / "heuristic_benchmark.json")
    args = ap.parse_args()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
        results = list(ex.map(lambda s: one(s, args.seconds), range(1, args.runs + 1)))
    wins = [r for r in results if r["exact_solution"]]
    losses = [r for r in results if not r["exact_solution"]]
    lat = [float(r["elapsed_seconds"]) for r in wins]
    report = {
        "runs": args.runs,
        "per_run_time_limit_seconds": args.seconds,
        "parallel_processes": args.workers,
        "successes": len(wins),
        "failures": len(losses),
        "success_rate": len(wins) / args.runs,
        "successful_latency_seconds": {
            "min": min(lat) if lat else None,
            "median": statistics.median(lat) if lat else None,
            "p95": percentile(lat, 0.95) if lat else None,
            "p99": percentile(lat, 0.99) if lat else None,
            "max": max(lat) if lat else None,
        },
        "successful_iterations": {
            "median": statistics.median([r["iterations"] for r in wins]) if wins else None,
            "max": max((r["iterations"] for r in wins), default=None),
        },
        "successful_random_seeds": [r["random_seed"] for r in wins],
        "failure_best_residuals_divided_by_2": [r["best_residual_divided_by_2"] for r in losses],
        "results": results,
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "results"}, indent=2))


if __name__ == "__main__":
    main()
