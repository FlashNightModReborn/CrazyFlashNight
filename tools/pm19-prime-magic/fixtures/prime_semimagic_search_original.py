#!/usr/bin/env python3
"""
Construct an n×n semimagic square of pairwise-distinct primes.

Every row and every column has the same sum. Diagonals are not constrained.

Method:
1. Build n-1 disjoint rows, each containing n primes summing to T=n*center.
2. Permute entries inside those rows.
3. The final row is forced by column deficits:
       last[j] = T - sum(rows[i][j], i=0..n-2)
   Since the first n-1 rows each sum to T, the forced last row also sums to T.
4. Greedily swap two entries within one existing row. Such a swap preserves
   all completed row sums and changes only two forced last-row values.

This is a practical randomized Las Vegas search: every returned result is
verified exactly, but runtime is not polynomially guaranteed.
"""

from __future__ import annotations

import argparse
import random
from typing import List, Optional, Sequence, Tuple

from sympy import isprime, primerange


Matrix = List[List[int]]


def _good_flags(deficits: Sequence[int], used: set[int]) -> List[bool]:
    counts: dict[int, int] = {}
    for value in deficits:
        counts[value] = counts.get(value, 0) + 1
    return [
        value > 2
        and isprime(value)
        and value not in used
        and counts[value] == 1
        for value in deficits
    ]


def _score(deficits: Sequence[int], used: set[int]) -> int:
    return sum(_good_flags(deficits, used))


def _column_deficits(rows: Matrix, target: int, n: int) -> List[int]:
    return [
        target - sum(rows[i][j] for i in range(n - 1))
        for j in range(n)
    ]


def _build_equal_sum_rows(
    n: int,
    center: int,
    width: int,
    rng: random.Random,
    max_attempts: int,
) -> Tuple[Matrix, set[int], int]:
    target = n * center
    candidates = list(primerange(center - width, center + width))
    if len(candidates) < n * (n - 1):
        raise RuntimeError("Prime window is too narrow for the requested order.")

    used: set[int] = set()
    rows: Matrix = []
    attempts = 0

    while len(rows) < n - 1 and attempts < max_attempts:
        attempts += 1
        prefix = rng.sample(candidates, n - 1)
        if any(value in used for value in prefix):
            continue

        final = target - sum(prefix)
        if (
            final <= 2
            or final in used
            or final in prefix
            or not isprime(final)
            or not (center - width < final < center + width)
        ):
            continue

        row = prefix + [final]
        rows.append(row)
        used.update(row)

    if len(rows) != n - 1:
        raise RuntimeError(
            f"Could not build {n - 1} equal-sum rows after {attempts} attempts. "
            "Increase center/width/max_attempts or change seed."
        )

    return rows, used, target


def _repair_last_row(
    rows: Matrix,
    used: set[int],
    target: int,
    n: int,
    rng: random.Random,
    restarts: int,
) -> Optional[Matrix]:
    original = [row[:] for row in rows]

    for _restart in range(restarts):
        rows = [row[:] for row in original]
        for row in rows:
            rng.shuffle(row)

        deficits = _column_deficits(rows, target, n)
        current_score = _score(deficits, used)

        while current_score < n:
            flags = _good_flags(deficits, used)
            bad_columns = [j for j, ok in enumerate(flags) if not ok]
            rng.shuffle(bad_columns)

            best_move: Optional[Tuple[int, int, int, int, int]] = None
            best_score = current_score

            for j in bad_columns:
                for row_index in range(n - 1):
                    left = rows[row_index][j]
                    for k in range(n):
                        if k == j:
                            continue
                        right = rows[row_index][k]
                        delta = right - left

                        old_j, old_k = deficits[j], deficits[k]
                        deficits[j] = old_j - delta
                        deficits[k] = old_k + delta
                        candidate_score = _score(deficits, used)
                        deficits[j], deficits[k] = old_j, old_k

                        if candidate_score > best_score:
                            best_score = candidate_score
                            best_move = (
                                row_index,
                                j,
                                k,
                                old_j - delta,
                                old_k + delta,
                            )
                            if best_score == n:
                                break
                    if best_score == n:
                        break
                if best_score == n:
                    break

            if best_move is None:
                break

            row_index, j, k, new_j, new_k = best_move
            rows[row_index][j], rows[row_index][k] = (
                rows[row_index][k],
                rows[row_index][j],
            )
            deficits[j], deficits[k] = new_j, new_k
            current_score = best_score

        if current_score == n:
            result = rows + [deficits]
            verify(result)
            return result

    return None


def find_prime_semimagic(
    n: int,
    center: int = 10_000_019,
    width: int = 50_000,
    seed: int = 1,
    row_attempts: int = 1_000_000,
    restarts: int = 100,
) -> Matrix:
    if n < 1:
        raise ValueError("n must be a positive integer.")
    if n == 1:
        return [[2]]
    if n == 2:
        raise ValueError("A 2×2 square with distinct entries and equal row/column sums is impossible.")

    rng = random.Random(seed)
    rows, used, target = _build_equal_sum_rows(
        n=n,
        center=center,
        width=width,
        rng=rng,
        max_attempts=row_attempts,
    )
    result = _repair_last_row(
        rows=rows,
        used=used,
        target=target,
        n=n,
        rng=rng,
        restarts=restarts,
    )
    if result is None:
        raise RuntimeError(
            "Search plateaued. Change seed or increase width/restarts."
        )
    return result


def verify(square: Matrix) -> None:
    n = len(square)
    if any(len(row) != n for row in square):
        raise AssertionError("Matrix is not square.")

    values = [value for row in square for value in row]
    if len(set(values)) != n * n:
        raise AssertionError("Entries are not pairwise distinct.")
    if not all(isprime(value) for value in values):
        raise AssertionError("At least one entry is not prime.")

    row_sums = {sum(row) for row in square}
    column_sums = {
        sum(square[i][j] for i in range(n))
        for j in range(n)
    }
    if len(row_sums) != 1 or row_sums != column_sums:
        raise AssertionError("Row/column sums are not all equal.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("n", type=int, nargs="?", default=19)
    parser.add_argument("--center", type=int, default=10_000_019)
    parser.add_argument("--width", type=int, default=50_000)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--restarts", type=int, default=100)
    args = parser.parse_args()

    square = find_prime_semimagic(
        n=args.n,
        center=args.center,
        width=args.width,
        seed=args.seed,
        restarts=args.restarts,
    )
    line_sum = sum(square[0])
    values = [value for row in square for value in row]

    print(f"order={args.n}")
    print(f"line_sum={line_sum}")
    print(f"prime_range={min(values)}..{max(values)}")
    for row in square:
        print(" ".join(map(str, row)))


if __name__ == "__main__":
    main()
