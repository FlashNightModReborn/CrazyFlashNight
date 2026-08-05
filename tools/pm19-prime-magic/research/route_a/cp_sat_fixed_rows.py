#!/usr/bin/env python3
"""CP-SAT feasibility model for a fixed row permutation (361 Booleans)."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path


HERE = Path(__file__).resolve().parent
if (HERE / "vendor").is_dir():
    sys.path.insert(0, str(HERE / "vendor"))
from ortools.sat.python import cp_model  # noqa: E402


ROOT = HERE.parents[1]
INPUT = ROOT / "upload" / "prime_semimagic_19(2).json"


class FirstSolution(cp_model.CpSolverSolutionCallback):
    def __init__(self) -> None:
        super().__init__()
        self.first_wall_time: float | None = None

    def on_solution_callback(self) -> None:
        if self.first_wall_time is None:
            self.first_wall_time = self.WallTime()


def solve(row_perm: list[int], seconds: float, seed: int, workers: int) -> dict:
    obj = json.loads(INPUT.read_text())
    a: list[list[int]] = obj["matrix"]
    target = int(obj["line_sum"])
    n = len(a)
    center = target // n
    assert sorted(row_perm) == list(range(n))

    model = cp_model.CpModel()
    x = [[model.NewBoolVar(f"x_{i}_{c}") for c in range(n)] for i in range(n)]
    for i in range(n):
        model.AddExactlyOne(x[i])
    for c in range(n):
        model.AddExactlyOne(x[i][c] for i in range(n))

    # Divide the two exact residual equations by their universal factor 2.
    w = [[(a[r][c] - center) // 2 for c in range(n)] for r in range(n)]
    assert all(a[r][c] - center == 2 * w[r][c] for r in range(n) for c in range(n))
    model.Add(sum(w[row_perm[i]][c] * x[i][c] for i in range(n) for c in range(n)) == 0)
    model.Add(
        sum(w[row_perm[n - 1 - i]][c] * x[i][c] for i in range(n) for c in range(n)) == 0
    )

    # The supplied column order is a deterministic starting hint. Hints need
    # not satisfy the side constraints; CP-SAT repairs it.
    for i in range(n):
        for c in range(n):
            model.AddHint(x[i][c], int(i == c))

    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = seconds
    solver.parameters.num_search_workers = workers
    solver.parameters.random_seed = seed
    solver.parameters.randomize_search = True
    solver.parameters.log_search_progress = True
    solver.parameters.log_to_stdout = True
    solver.parameters.cp_model_presolve = True
    solver.parameters.linearization_level = 2
    callback = FirstSolution()
    started = time.perf_counter()
    status = solver.Solve(model, callback)
    elapsed = time.perf_counter() - started
    report: dict = {
        "status": solver.StatusName(status),
        "elapsed_seconds": elapsed,
        "first_solution_wall_time": callback.first_wall_time,
        "row_permutation": row_perm,
        "random_seed": seed,
        "workers": workers,
        "response_stats": solver.ResponseStats(),
        "num_booleans": solver.NumBooleans(),
        "num_branches": solver.NumBranches(),
        "num_conflicts": solver.NumConflicts(),
        "wall_time": solver.WallTime(),
    }
    if status in (cp_model.FEASIBLE, cp_model.OPTIMAL):
        col_perm = [next(c for c in range(n) if solver.BooleanValue(x[i][c])) for i in range(n)]
        board = [[a[row_perm[i]][col_perm[j]] for j in range(n)] for i in range(n)]
        d1 = sum(board[i][i] for i in range(n))
        d2 = sum(board[i][n - 1 - i] for i in range(n))
        report.update(
            {
                "column_permutation": col_perm,
                "main_sum_reverified": d1,
                "secondary_sum_reverified": d2,
                "exact_solution": d1 == target and d2 == target,
                "matrix": board,
            }
        )
    return report


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=300)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--row-seed", type=int)
    ap.add_argument("--output", type=Path, default=HERE / "cp_sat_result.json")
    args = ap.parse_args()
    row_perm = list(range(19))
    if args.row_seed is not None:
        import random

        random.Random(args.row_seed).shuffle(row_perm)
    report = solve(row_perm, args.seconds, args.seed, args.workers)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print("RESULT_JSON")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
