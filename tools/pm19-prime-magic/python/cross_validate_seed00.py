#!/usr/bin/env python3
"""Independent cross-check of the main compiler's seed00 and reduction witness.

No code is imported from prime-magic-19.  Primality uses exhaustive trial
division, and the binary format is decoded directly with struct.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
SOURCE = PROJECT / "fixtures" / "prime_semimagic_19.json"
SEED_JSON = PROJECT / "seeds" / "prime_magic_19_seed_00.json"
SEED_BIN = PROJECT / "seeds" / "prime_magic_19_seed_00.bin"


def prime_by_trial_division(value: int) -> bool:
    if not isinstance(value, int) or isinstance(value, bool) or value < 2:
        return False
    if value % 2 == 0:
        return value == 2
    limit = math.isqrt(value)
    divisor = 3
    while divisor <= limit:
        if value % divisor == 0:
            return False
        divisor += 2
    return True


def canonical_checksum(matrix: list[list[int]], magic_sum: int) -> str:
    payload = {
        "magicSum": magic_sum,
        "size": len(matrix),
        "values": [value for row in matrix for value in row],
    }
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("ascii")
    return hashlib.sha256(raw).hexdigest()


def main() -> None:
    source_raw = SOURCE.read_bytes()
    source = json.loads(source_raw)
    seed_raw = SEED_JSON.read_bytes()
    seed = json.loads(seed_raw)
    binary = SEED_BIN.read_bytes()
    a = source["matrix"]
    b = seed["matrix"]
    n = seed["size"]
    target = seed["magicSum"]
    meta = seed["compiler"]
    rho = meta["rowPermutation"]
    kappa = meta["columnPermutation"]
    assignment = meta["mainAssignment"]
    tau = meta["rowInvolution"]
    R = lambda i: n - 1 - i

    checks: dict[str, bool] = {}
    checks["source_sha256"] = hashlib.sha256(source_raw).hexdigest() == seed["sourceFileSha256"]
    checks["dimension"] = n == 19 and len(b) == n and all(len(row) == n for row in b)
    checks["strict_integers"] = all(
        isinstance(x, int) and not isinstance(x, bool) for row in b for x in row
    )
    checks["row_permutation"] = sorted(rho) == list(range(n))
    checks["column_permutation"] = sorted(kappa) == list(range(n))
    checks["main_assignment_bijection"] = sorted(assignment) == list(range(n))
    checks["matrix_is_claimed_double_permutation"] = b == [
        [a[rho[i]][kappa[j]] for j in range(n)] for i in range(n)
    ]

    checks["tau_is_involution"] = (
        sorted(tau) == list(range(n)) and all(tau[tau[r]] == r for r in range(n))
    )
    fixed = [r for r in range(n) if tau[r] == r]
    transpositions = [(r, tau[r]) for r in range(n) if r < tau[r]]
    checks["tau_cycle_type_2pow9_1"] = len(fixed) == 1 and len(transpositions) == 9

    checks["column_order_is_assignment_of_row_order"] = all(
        kappa[i] == assignment[rho[i]] for i in range(n)
    )
    checks["mirrored_row_order_realizes_tau"] = all(
        rho[R(i)] == tau[rho[i]] for i in range(n)
    )
    main_assignment_sum = sum(a[r][assignment[r]] for r in range(n))
    crossed_assignment_sum = sum(a[r][assignment[tau[r]]] for r in range(n))
    checks["first_assignment_exact"] = main_assignment_sum == target
    checks["crossed_assignment_exact"] = crossed_assignment_sum == target
    checks["crossed_assignment_bijection"] = sorted(
        assignment[tau[r]] for r in range(n)
    ) == list(range(n))

    values = [x for row in b for x in row]
    source_values = [x for row in a for x in row]
    checks["same_element_multiset"] = sorted(values) == sorted(source_values)
    checks["global_uniqueness"] = len(set(values)) == n * n
    checks["all_prime_exhaustive_trial_division"] = all(prime_by_trial_division(x) for x in values)
    row_sums = [sum(row) for row in b]
    column_sums = [sum(b[i][j] for i in range(n)) for j in range(n)]
    main_diagonal = sum(b[i][i] for i in range(n))
    secondary_diagonal = sum(b[i][R(i)] for i in range(n))
    checks["rows_exact"] = all(x == target for x in row_sums)
    checks["columns_exact"] = all(x == target for x in column_sums)
    checks["main_diagonal_exact"] = main_diagonal == target
    checks["secondary_diagonal_exact"] = secondary_diagonal == target
    checks["javascript_safe"] = max(values + row_sums + column_sums) < 2**53
    checksum = canonical_checksum(b, target)
    checks["canonical_checksum"] = seed["checksum"] == "sha256:" + checksum

    magic, version, binary_n, binary_sum = struct.unpack_from("<4sHHQ", binary)
    count = binary_n * binary_n
    decoded = list(struct.unpack_from(f"<{count}I", binary, struct.calcsize("<4sHHQ")))
    checks["binary_header"] = (magic, version, binary_n, binary_sum) == (b"PM19", 1, n, target)
    checks["binary_exact_length"] = len(binary) == struct.calcsize("<4sHHQ") + count * 4
    checks["binary_values_match_json"] = decoded == values
    assert all(checks.values()), {name: ok for name, ok in checks.items() if not ok}

    report = {
        "verdict": "VALID: seed00 and its two-stage reduction witness independently confirmed",
        "checks": checks,
        "fixed_row": fixed[0],
        "transpositions": transpositions,
        "main_assignment_sum": main_assignment_sum,
        "crossed_assignment_sum": crossed_assignment_sum,
        "main_diagonal_sum": main_diagonal,
        "secondary_diagonal_sum": secondary_diagonal,
        "canonical_checksum": checksum,
        "json_sha256": hashlib.sha256(seed_raw).hexdigest(),
        "binary_sha256": hashlib.sha256(binary).hexdigest(),
        "binary_bytes": len(binary),
    }
    (PROJECT / "reports" / "seed00_cross_validation.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
