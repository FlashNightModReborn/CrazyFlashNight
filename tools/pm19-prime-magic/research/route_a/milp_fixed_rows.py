#!/usr/bin/env python3
"""Exact 361-binary MILP after fixing a row permutation.

For fixed displayed rows rho[i], only the displayed column permutation kappa
remains.  Binary x[i,c] assigns original column c to display position i.
The main weight at (i,c) is A[rho[i],c]; the secondary diagonal re-indexes to
A[rho[R(i)],c].  Hence both diagonal constraints are linear side constraints
on an ordinary assignment polytope.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
from scipy.optimize import Bounds, LinearConstraint, milp
from scipy.sparse import coo_matrix


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
INPUT = ROOT / "upload" / "prime_semimagic_19(2).json"


def solve(row_permutation: list[int], time_limit: float, seed: int) -> dict:
    obj = json.loads(INPUT.read_text())
    a = np.asarray(obj["matrix"], dtype=np.int64)
    target = int(obj["line_sum"])
    n = len(a)
    assert sorted(row_permutation) == list(range(n))

    # x[i,c], row-major.
    nvar = n * n
    rows: list[int] = []
    cols: list[int] = []
    data: list[float] = []
    lower: list[float] = []
    upper: list[float] = []

    def add(entries: list[tuple[int, float]], lo: float, hi: float) -> None:
        q = len(lower)
        for col, value in entries:
            rows.append(q)
            cols.append(col)
            data.append(value)
        lower.append(lo)
        upper.append(hi)

    for i in range(n):
        add([(i * n + c, 1.0) for c in range(n)], 1, 1)
    for c in range(n):
        add([(i * n + c, 1.0) for i in range(n)], 1, 1)

    center = target // n
    assert target == center * n
    w = (a - center) // 2
    assert np.all(a - center == 2 * w)
    add(
        [(i * n + c, float(w[row_permutation[i], c])) for i in range(n) for c in range(n)],
        0,
        0,
    )
    add(
        [
            (i * n + c, float(w[row_permutation[n - 1 - i], c]))
            for i in range(n)
            for c in range(n)
        ],
        0,
        0,
    )

    matrix = coo_matrix((data, (rows, cols)), shape=(len(lower), nvar)).tocsr()
    rng = np.random.default_rng(seed)
    # Unit-scale random costs select one feasible vertex and avoid a completely
    # flat objective. Exact diagonal sums remain hard equalities.
    cost = rng.uniform(-1.0, 1.0, nvar)
    started = time.perf_counter()
    result = milp(
        cost,
        integrality=np.ones(nvar, dtype=np.uint8),
        bounds=Bounds(np.zeros(nvar), np.ones(nvar)),
        constraints=LinearConstraint(matrix, np.asarray(lower), np.asarray(upper)),
        options={"disp": True, "presolve": True, "time_limit": time_limit, "mip_rel_gap": 0.0},
    )
    elapsed = time.perf_counter() - started
    report: dict = {
        "success": bool(result.success),
        "status": int(result.status),
        "message": str(result.message),
        "elapsed_seconds": elapsed,
        "mip_node_count": getattr(result, "mip_node_count", None),
        "mip_gap": getattr(result, "mip_gap", None),
        "variables": nvar,
        "binary_variables": nvar,
        "constraints": len(lower),
        "matrix_nonzeros": int(matrix.nnz),
        "row_permutation": row_permutation,
        "objective_seed": seed,
    }
    if result.x is not None:
        rounded = np.rint(result.x)
        report["max_integrality_error"] = float(np.max(np.abs(result.x - rounded)))
        col_perm: list[int] = []
        for i in range(n):
            chosen = np.flatnonzero(result.x[i * n : (i + 1) * n] > 0.5)
            if len(chosen) != 1:
                break
            col_perm.append(int(chosen[0]))
        if len(col_perm) == n and len(set(col_perm)) == n:
            board = a[np.ix_(row_permutation, col_perm)]
            d1 = int(np.trace(board))
            d2 = int(np.trace(np.fliplr(board)))
            report.update(
                {
                    "column_permutation": col_perm,
                    "main_sum_reverified": d1,
                    "secondary_sum_reverified": d2,
                    "exact_solution": d1 == target and d2 == target,
                }
            )
            if report["exact_solution"]:
                report["matrix"] = board.tolist()
    return report


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--time-limit", type=float, default=300)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--row-seed", type=int, help="shuffle rows deterministically; omit for identity")
    ap.add_argument("--output", type=Path, default=HERE / "fixed_rows_result.json")
    args = ap.parse_args()
    row_perm = list(range(19))
    if args.row_seed is not None:
        row_perm = np.random.default_rng(args.row_seed).permutation(19).tolist()
    report = solve(row_perm, args.time_limit, args.seed)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
