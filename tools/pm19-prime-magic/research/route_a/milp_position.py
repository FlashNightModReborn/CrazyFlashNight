#!/usr/bin/env python3
"""Exact MILP model for the row/column double-permutation problem.

M[i,r,c] says that the main diagonal at display position i uses A[r,c].
N[i,r,c] says that the secondary diagonal at position i uses A[r,c].
The row at N-position i equals the row at M-position i, while the column at
N-position i equals the column at M-position n-1-i.  This is precisely the
row/column-permutation model, without bilinear products.

The 9 mirrored position-pairs are otherwise indistinguishable.  Linear
symmetry breakers put the smaller row on the left and sort pairs by that row,
removing a factor 9!*2**9 from the branch-and-bound tree without excluding a
solution.
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


def load() -> tuple[np.ndarray, int]:
    obj = json.loads(INPUT.read_text())
    return np.asarray(obj["matrix"], dtype=np.int64), int(obj["line_sum"])


def solve(time_limit: float, center_row: int | None, seed: int) -> dict:
    a, target = load()
    n = len(a)
    cells = n * n
    layer = n * cells
    nvar = 2 * layer

    def vi(which: int, pos: int, row: int, col: int) -> int:
        return which * layer + pos * cells + row * n + col

    rr: list[int] = []
    cc: list[int] = []
    dd: list[float] = []
    lo: list[float] = []
    hi: list[float] = []

    def add(entries: list[tuple[int, float]], lower: float, upper: float) -> None:
        q = len(lo)
        for col, value in entries:
            rr.append(q)
            cc.append(col)
            dd.append(value)
        lo.append(lower)
        hi.append(upper)

    # M chooses one matrix edge at each display position.
    for i in range(n):
        add([(vi(0, i, r, c), 1.0) for r in range(n) for c in range(n)], 1, 1)

    # M is globally a perfect matching between original rows and columns.
    for r in range(n):
        add([(vi(0, i, r, c), 1.0) for i in range(n) for c in range(n)], 1, 1)
    for c in range(n):
        add([(vi(0, i, r, c), 1.0) for i in range(n) for r in range(n)], 1, 1)

    # The displayed row permutation is shared by both diagonals.
    for i in range(n):
        for r in range(n):
            add(
                [(vi(0, i, r, c), 1.0) for c in range(n)]
                + [(vi(1, i, r, c), -1.0) for c in range(n)],
                0,
                0,
            )

    # The N column at i is the M column at R(i).
    for i in range(n):
        j = n - 1 - i
        for c in range(n):
            add(
                [(vi(1, i, r, c), 1.0) for r in range(n)]
                + [(vi(0, j, r, c), -1.0) for r in range(n)],
                0,
                0,
            )

    # Remove the common ~10M offset and the universal factor two.  Every prime
    # and target/n are odd, so all coefficients and a feasible residual are
    # integral after division by two.
    center = target // n
    assert target == n * center
    weights = ((a - center) // 2).astype(np.int64)
    assert np.all(a - center == 2 * weights)
    for which in (0, 1):
        add(
            [
                (vi(which, i, r, c), float(weights[r, c]))
                for i in range(n)
                for r in range(n)
                for c in range(n)
            ],
            0,
            0,
        )

    # Canonicalize the nine unordered row pairs.
    half = n // 2
    for i in range(half):
        j = n - 1 - i
        add(
            [(vi(0, i, r, c), float(r)) for r in range(n) for c in range(n)]
            + [(vi(0, j, r, c), float(-r)) for r in range(n) for c in range(n)],
            -np.inf,
            -1,
        )
    for i in range(half - 1):
        add(
            [(vi(0, i, r, c), float(r)) for r in range(n) for c in range(n)]
            + [(vi(0, i + 1, r, c), float(-r)) for r in range(n) for c in range(n)],
            -np.inf,
            -1,
        )

    lb = np.zeros(nvar)
    ub = np.ones(nvar)
    if center_row is not None:
        mid = half
        for r in range(n):
            if r != center_row:
                for c in range(n):
                    ub[vi(0, mid, r, c)] = 0
                    ub[vi(1, mid, r, c)] = 0
        # Once the center is known, the first canonical pair starts with the
        # smallest non-center row.
        first = 0 if center_row != 0 else 1
        for r in range(n):
            if r != first:
                for c in range(n):
                    ub[vi(0, 0, r, c)] = 0
                    ub[vi(1, 0, r, c)] = 0

    mat = coo_matrix((dd, (rr, cc)), shape=(len(lo), nvar)).tocsr()
    constraints = LinearConstraint(mat, np.asarray(lo), np.asarray(hi))

    # A tiny deterministic random objective steers HiGHS toward vertices while
    # leaving the two exact diagonal equalities hard constraints.
    rng = np.random.default_rng(seed)
    objective = rng.uniform(-1.0, 1.0, nvar) * 1e-5
    started = time.perf_counter()
    result = milp(
        objective,
        integrality=np.ones(nvar, dtype=np.uint8),
        bounds=Bounds(lb, ub),
        constraints=constraints,
        options={
            "disp": True,
            "presolve": True,
            "time_limit": time_limit,
            "mip_rel_gap": 0.0,
        },
    )
    elapsed = time.perf_counter() - started
    report: dict = {
        "success": bool(result.success),
        "status": int(result.status),
        "message": str(result.message),
        "elapsed_seconds": elapsed,
        "mip_node_count": getattr(result, "mip_node_count", None),
        "mip_gap": getattr(result, "mip_gap", None),
        "center_row_constraint": center_row,
        "random_objective_seed": seed,
        "variables": nvar,
        "constraints": len(lo),
        "matrix_nonzeros": int(mat.nnz),
    }
    if result.x is not None:
        x = result.x
        rows: list[int] = []
        cols: list[int] = []
        fractional = float(np.max(np.abs(x - np.rint(x))))
        for i in range(n):
            selected = np.argwhere(x[i * cells : (i + 1) * cells] > 0.5).ravel()
            if len(selected) != 1:
                break
            edge = int(selected[0])
            rows.append(edge // n)
            cols.append(edge % n)
        report["max_integrality_error"] = fractional
        if len(rows) == n:
            board = a[np.ix_(rows, cols)]
            report.update(
                {
                    "row_permutation": rows,
                    "column_permutation": cols,
                    "main_sum_reverified": int(np.trace(board)),
                    "secondary_sum_reverified": int(np.trace(np.fliplr(board))),
                }
            )
            if report["main_sum_reverified"] == target and report["secondary_sum_reverified"] == target:
                report["exact_solution"] = True
                report["matrix"] = board.tolist()
    return report


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--time-limit", type=float, default=300.0)
    ap.add_argument("--center-row", type=int)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--output", type=Path, default=HERE / "milp_result.json")
    args = ap.parse_args()
    report = solve(args.time_limit, args.center_row, args.seed)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
