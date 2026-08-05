#!/usr/bin/env python3
"""Independent, dependency-free audit of the supplied 19x19 instance.

This deliberately does not import any code from prime_semimagic_search.py.
For the present input range (< 2**32), trial division through isqrt(n) is a
deterministic primality proof, not a probable-prime test.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
JSON_PATH = ROOT / "upload" / "prime_semimagic_19(2).json"
TXT_PATH = ROOT / "upload" / "prime_semimagic_19(2).txt"


def is_prime_trial(n: int) -> bool:
    if not isinstance(n, int) or isinstance(n, bool) or n < 2:
        return False
    small = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37)
    if n in small:
        return True
    if any(n % p == 0 for p in small):
        return False
    # Check only residues coprime to 2, 3, 5. A simple odd loop would also be
    # fast enough here; this wheel keeps the audit visibly independent.
    d = 41
    while d <= math.isqrt(n):
        if n % d == 0:
            return False
        d += 2
        while d % 3 == 0 or d % 5 == 0:
            d += 2
    return True


def parse_txt_matrix(text: str, n: int) -> list[list[int]]:
    rows: list[list[int]] = []
    for line in text.splitlines():
        tokens = re.findall(r"\d+", line)
        if len(tokens) == n:
            rows.append([int(x) for x in tokens])
    if len(rows) != n:
        raise ValueError(f"TXT contains {len(rows)} candidate matrix rows, expected {n}")
    return rows


def canonical_binary(matrix: list[list[int]]) -> bytes:
    # Auditable compact convention used only for cross-checking here:
    # ASCII tag, uint16 little-endian order, then row-major uint32 LE values.
    n = len(matrix)
    return b"PM19-U32LE-v1\0" + struct.pack("<H", n) + struct.pack(
        f"<{n*n}I", *(x for row in matrix for x in row)
    )


def main() -> None:
    raw_json = JSON_PATH.read_bytes()
    obj = json.loads(raw_json)
    matrix = obj["matrix"]
    n = obj["order"]
    txt_matrix = parse_txt_matrix(TXT_PATH.read_text(encoding="ascii"), n)

    assert isinstance(n, int) and n == 19
    assert len(matrix) == n and all(len(row) == n for row in matrix)
    assert matrix == txt_matrix, "JSON and TXT matrices differ"

    values = [x for row in matrix for x in row]
    assert len(values) == n * n
    assert all(isinstance(x, int) and not isinstance(x, bool) for x in values)
    assert len(set(values)) == n * n
    composite = [x for x in values if not is_prime_trial(x)]
    assert not composite, f"composite entries: {composite}"

    row_sums = [sum(row) for row in matrix]
    col_sums = [sum(matrix[r][c] for r in range(n)) for c in range(n)]
    assert len(set(row_sums)) == 1
    assert len(set(col_sums)) == 1
    assert row_sums[0] == col_sums[0]
    line_sum = row_sums[0]
    assert line_sum == obj["line_sum"]
    assert min(values) == obj["min_prime"]
    assert max(values) == obj["max_prime"]

    main_diag = sum(matrix[i][i] for i in range(n))
    anti_diag = sum(matrix[i][n - 1 - i] for i in range(n))
    result = {
        "dimension": [n, n],
        "element_count": len(values),
        "all_integer": True,
        "all_prime_deterministic_trial_division": True,
        "all_distinct": True,
        "json_txt_identical": True,
        "line_sum": line_sum,
        "all_row_sums_equal": True,
        "all_column_sums_equal": True,
        "main_diagonal_sum_original": main_diag,
        "main_diagonal_residual": main_diag - line_sum,
        "secondary_diagonal_sum_original": anti_diag,
        "secondary_diagonal_residual": anti_diag - line_sum,
        "min": min(values),
        "max": max(values),
        "number_max_safe": max(max(values), line_sum) < 2**53,
        "input_json_sha256": hashlib.sha256(raw_json).hexdigest(),
        "canonical_u32le_sha256": hashlib.sha256(canonical_binary(matrix)).hexdigest(),
    }
    out = Path(__file__).with_name("input_audit.json")
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
