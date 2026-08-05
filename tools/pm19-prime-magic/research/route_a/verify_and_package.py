#!/usr/bin/env python3
"""Independent verification and deterministic packaging of the Route-A seed.

This script shares no delta-update or search code with the C++ generator.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = ROOT / "upload" / "prime_semimagic_19(2).json"
SEARCH_RESULT = HERE / "heuristic_seed3.json"


def is_prime(n: int) -> bool:
    if not isinstance(n, int) or isinstance(n, bool) or n < 2:
        return False
    if n % 2 == 0:
        return n == 2
    d = 3
    limit = math.isqrt(n)
    while d <= limit:
        if n % d == 0:
            return False
        d += 2
    return True


def main() -> None:
    src_bytes = SOURCE.read_bytes()
    src = json.loads(src_bytes)
    result = json.loads(SEARCH_RESULT.read_text())
    a = src["matrix"]
    n = src["order"]
    target = src["line_sum"]
    rho = result["row_permutation"]
    kappa = result["column_permutation"]
    supplied_board = result["matrix"]

    checks: dict[str, object] = {}
    checks["dimension"] = n == 19 and len(a) == n and all(len(row) == n for row in a)
    checks["row_permutation_bijection"] = sorted(rho) == list(range(n))
    checks["column_permutation_bijection"] = sorted(kappa) == list(range(n))
    derived = [[a[rho[i]][kappa[j]] for j in range(n)] for i in range(n)]
    checks["packaged_matrix_equals_permutation_result"] = derived == supplied_board

    values = [x for row in derived for x in row]
    checks["element_count"] = len(values) == n * n
    checks["all_integer"] = all(isinstance(x, int) and not isinstance(x, bool) for x in values)
    checks["all_distinct"] = len(set(values)) == n * n
    checks["same_element_set_as_source"] = sorted(values) == sorted(x for row in a for x in row)
    checks["all_prime_by_independent_trial_division"] = all(is_prime(x) for x in values)
    row_sums = [sum(row) for row in derived]
    col_sums = [sum(derived[i][j] for i in range(n)) for j in range(n)]
    d1 = sum(derived[i][i] for i in range(n))
    d2 = sum(derived[i][n - 1 - i] for i in range(n))
    checks["all_row_sums_equal_target"] = all(x == target for x in row_sums)
    checks["all_column_sums_equal_target"] = all(x == target for x in col_sums)
    checks["main_diagonal_equals_target"] = d1 == target
    checks["secondary_diagonal_equals_target"] = d2 == target
    checks["safe_integer_range"] = max(values + row_sums + col_sums + [d1, d2]) < 2**53
    assert all(v is True for v in checks.values()), checks

    row_major = struct.pack(f"<{n*n}I", *values)
    header = struct.pack("<8sHHIQ", b"PM19U32\0", 1, n, n * n, target)
    compact = header + row_major
    compact_path = HERE / "prime_magic_19_route_a.bin"
    compact_path.write_bytes(compact)

    packaged = {
        "format": "prime-magic-seed-v1",
        "order": n,
        "line_sum": target,
        "min_prime": min(values),
        "max_prime": max(values),
        "source_semimagic_json_sha256": hashlib.sha256(src_bytes).hexdigest(),
        "construction": "row-column double permutation",
        "row_permutation_zero_based": rho,
        "column_permutation_zero_based": kappa,
        "matrix_row_major_u32le_sha256": hashlib.sha256(row_major).hexdigest(),
        "compact_binary_sha256": hashlib.sha256(compact).hexdigest(),
        "matrix": derived,
    }
    canonical_without_checksum = json.dumps(
        packaged, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("ascii")
    packaged["canonical_payload_sha256"] = hashlib.sha256(canonical_without_checksum).hexdigest()
    json_path = HERE / "prime_magic_19_route_a.json"
    json_path.write_text(json.dumps(packaged, indent=2) + "\n")

    verification = {
        "verdict": "VALID COMPLETE 19x19 DISTINCT-PRIME MAGIC SQUARE",
        "checks": checks,
        "line_sum_recomputed": target,
        "row_sums": row_sums,
        "column_sums": col_sums,
        "main_diagonal_sum": d1,
        "secondary_diagonal_sum": d2,
        "matrix_row_major_u32le_sha256": packaged["matrix_row_major_u32le_sha256"],
        "compact_binary_sha256": packaged["compact_binary_sha256"],
        "canonical_payload_sha256": packaged["canonical_payload_sha256"],
        "compact_binary_bytes": len(compact),
    }
    (HERE / "solution_verification.json").write_text(json.dumps(verification, indent=2) + "\n")
    print(json.dumps(verification, indent=2))


if __name__ == "__main__":
    main()
