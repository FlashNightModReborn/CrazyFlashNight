#!/usr/bin/env python3
"""Cross-audit the supplied JSON, text rendering, and legacy search script."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path

from .verify import verify_matrix


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _parse_text_matrix(path: Path, size: int) -> list[list[int]]:
    rows: list[list[int]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        tokens = line.split()
        if len(tokens) == size and all(re.fullmatch(r"[+-]?\d+", token) for token in tokens):
            rows.append([int(token) for token in tokens])
    if len(rows) != size:
        raise ValueError(f"found {len(rows)} numeric rows, expected {size}")
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json_input", type=Path)
    parser.add_argument("text_input", type=Path)
    parser.add_argument("script_input", type=Path)
    parser.add_argument(
        "--captured-script-output",
        type=Path,
        help="output from an isolated run with the script dependency installed",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    json_payload = json.loads(args.json_input.read_text(encoding="utf-8"))
    matrix = json_payload["matrix"]
    text_matrix = _parse_text_matrix(args.text_input, len(matrix))
    verification = verify_matrix(
        matrix,
        expected_dimension=json_payload.get("size", json_payload.get("order")),
        expected_magic_sum=json_payload.get("line_sum"),
        require_diagonals=False,
    )
    direct_run = subprocess.run(
        [sys.executable, str(args.script_input), "3", "--seed", "1", "--restarts", "1"],
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    payload = {
        "format": "prime-magic-input-audit/v1",
        "files": {
            "json": {"path": str(args.json_input), "sha256": _sha256(args.json_input)},
            "text": {"path": str(args.text_input), "sha256": _sha256(args.text_input)},
            "script": {"path": str(args.script_input), "sha256": _sha256(args.script_input)},
        },
        "jsonVerification": asdict(verification),
        "textMatrixEqualsJson": text_matrix == matrix,
        "declaredLineSumEqualsComputed": json_payload.get("line_sum") == verification.magic_sum,
        "declaredMinEqualsComputed": json_payload.get("min_prime") == verification.min_value,
        "declaredMaxEqualsComputed": json_payload.get("max_prime") == verification.max_value,
        "legacyScriptDirectRun": {
            "command": [sys.executable, str(args.script_input), "3", "--seed", "1", "--restarts", "1"],
            "exitCode": direct_run.returncode,
            "stdout": direct_run.stdout,
            "stderr": direct_run.stderr,
            "diagnosis": (
                "missing runtime dependency: sympy"
                if "No module named 'sympy'" in direct_run.stderr
                else "completed" if direct_run.returncode == 0 else "failed for another reason"
            ),
        },
    }
    if args.captured_script_output:
        captured_matrix = _parse_text_matrix(args.captured_script_output, len(matrix))
        payload["legacyScriptDependencyResolvedRun"] = {
            "path": str(args.captured_script_output),
            "sha256": _sha256(args.captured_script_output),
            "matrixEqualsJson": captured_matrix == matrix,
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if verification.valid and text_matrix == matrix else 1


if __name__ == "__main__":
    raise SystemExit(main())
