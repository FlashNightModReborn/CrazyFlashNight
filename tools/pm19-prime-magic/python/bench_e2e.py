#!/usr/bin/env python3
"""End-to-end benchmark: route-A search, packaging, and independent verification."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import statistics
import tempfile
import time
from pathlib import Path
from typing import Any

from prime_magic.compiler import (
    CompilerConfig,
    _derive_seed,
    _load_semimagic,
    _run_independent_verifier,
    _write_result,
    compile_upgrade,
)


def percentile(sorted_values: list[float], probability: float) -> float | None:
    if not sorted_values:
        return None
    position = (len(sorted_values) - 1) * probability
    lower = int(position)
    upper = min(lower + 1, len(sorted_values) - 1)
    fraction = position - lower
    return sorted_values[lower] + (sorted_values[upper] - sorted_values[lower]) * fraction


def summary(values: list[float]) -> dict[str, float | None]:
    ordered = sorted(values)
    return {
        "min": min(ordered) if ordered else None,
        "median": statistics.median(ordered) if ordered else None,
        "p95": percentile(ordered, 0.95),
        "p99": percentile(ordered, 0.99),
        "max": max(ordered) if ordered else None,
        "mean": statistics.mean(ordered) if ordered else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--seed", type=int, default=20260805)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("samples must be positive")

    matrix, magic_sum = _load_semimagic(args.input)
    source_sha256 = hashlib.sha256(args.input.read_bytes()).hexdigest()
    search_times: list[float] = []
    packaging_times: list[float] = []
    verification_times: list[float] = []
    end_to_end_times: list[float] = []
    records: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    wall_start = time.perf_counter()

    with tempfile.TemporaryDirectory(prefix="prime-magic-e2e-") as temporary:
        temporary_path = Path(temporary)
        for index in range(args.samples):
            started = time.perf_counter()
            compiler_seed = _derive_seed(args.seed, index)
            try:
                search_started = time.perf_counter()
                result = compile_upgrade(matrix, magic_sum, CompilerConfig(seed=compiler_seed))
                search_seconds = time.perf_counter() - search_started

                packaging_started = time.perf_counter()
                files = _write_result(
                    result,
                    magic_sum,
                    temporary_path / f"prime_magic_{len(matrix)}_seed_{index:03d}",
                    source_sha256,
                )
                packaging_seconds = time.perf_counter() - packaging_started

                verification_started = time.perf_counter()
                json_report = _run_independent_verifier(
                    temporary_path / files["json"], require_checksum=True
                )
                binary_report = _run_independent_verifier(temporary_path / files["binary"])
                verification_seconds = time.perf_counter() - verification_started
                if not json_report.get("valid") or not binary_report.get("valid"):
                    raise AssertionError("independent verifier returned an invalid report")

                end_to_end_seconds = time.perf_counter() - started
                search_times.append(search_seconds)
                packaging_times.append(packaging_seconds)
                verification_times.append(verification_seconds)
                end_to_end_times.append(end_to_end_seconds)
                records.append(
                    {
                        "index": index,
                        "compilerSeed": compiler_seed,
                        "searchSeconds": search_seconds,
                        "packagingSeconds": packaging_seconds,
                        "verificationSeconds": verification_seconds,
                        "endToEndSeconds": end_to_end_seconds,
                    }
                )
            except Exception as exc:
                failures.append(
                    {"index": index, "compilerSeed": compiler_seed, "error": str(exc)}
                )

    payload = {
        "format": "prime-magic-compiler-e2e-benchmark/v1",
        "machine": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "processor": platform.processor(),
            "logicalCpuCount": os.cpu_count(),
        },
        "samples": args.samples,
        "baseSeed": args.seed,
        "successes": len(records),
        "failures": len(failures),
        "wallSeconds": time.perf_counter() - wall_start,
        "searchSeconds": summary(search_times),
        "packagingSeconds": summary(packaging_times),
        "verificationSeconds": summary(verification_times),
        "endToEndSeconds": summary(end_to_end_times),
        "records": records,
        "failureRecords": failures,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {key: payload[key] for key in (
                "samples",
                "successes",
                "failures",
                "searchSeconds",
                "packagingSeconds",
                "verificationSeconds",
                "endToEndSeconds",
            )},
            indent=2,
            sort_keys=True,
        )
    )
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
