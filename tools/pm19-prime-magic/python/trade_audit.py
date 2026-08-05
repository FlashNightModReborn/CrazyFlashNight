#!/usr/bin/env python3
"""Audit exact multiset-preserving, margin-preserving trades in a square.

The useful family is a two-row subset trade (or its transpose): swap the two
values in every selected column.  Columns are preserved cell-pair by cell-pair;
the two rows are preserved iff the selected signed differences sum to zero.
For n=19 all zero subsets are enumerated exactly by meet in the middle.
"""

from __future__ import annotations

import argparse
import collections
import json
from collections.abc import Iterable, Sequence
from dataclasses import dataclass


Matrix = list[list[int]]


@dataclass(frozen=True)
class Trade:
    axis: str
    first: int
    second: int
    mask: int
    delta_main: int
    delta_anti: int


def subset_sums(values: Sequence[int]) -> list[int]:
    out = [0] * (1 << len(values))
    for mask in range(1, len(out)):
        bit = mask & -mask
        out[mask] = out[mask ^ bit] + values[bit.bit_length() - 1]
    return out


def zero_subset_masks(values: Sequence[int]) -> Iterable[int]:
    split = len(values) // 2
    left = subset_sums(values[:split])
    right = subset_sums(values[split:])
    bins: dict[int, list[int]] = collections.defaultdict(list)
    for mask, total in enumerate(left):
        bins[total].append(mask)
    for right_mask, total in enumerate(right):
        for left_mask in bins.get(-total, ()):
            yield left_mask | (right_mask << split)


def diagonal_delta(a: Matrix, axis: str, first: int, second: int, mask: int) -> tuple[int, int]:
    n = len(a)
    rev = lambda i: n - 1 - i
    main = anti = 0
    if axis == "row":
        if mask >> first & 1:
            main += a[second][first] - a[first][first]
        if mask >> second & 1:
            main += a[first][second] - a[second][second]
        if mask >> rev(first) & 1:
            anti += a[second][rev(first)] - a[first][rev(first)]
        if mask >> rev(second) & 1:
            anti += a[first][rev(second)] - a[second][rev(second)]
    elif axis == "column":
        if mask >> first & 1:
            main += a[first][second] - a[first][first]
        if mask >> second & 1:
            main += a[second][first] - a[second][second]
        if mask >> rev(first) & 1:
            anti += a[rev(first)][second] - a[rev(first)][first]
        if mask >> rev(second) & 1:
            anti += a[rev(second)][first] - a[rev(second)][second]
    else:
        raise ValueError(axis)
    return main, anti


def enumerate_trades(a: Matrix, *, include_axis_swaps: bool) -> Iterable[Trade]:
    n = len(a)
    full = (1 << n) - 1
    for first in range(n):
        for second in range(first + 1, n):
            row_differences = [a[second][column] - a[first][column] for column in range(n)]
            for mask in zero_subset_masks(row_differences):
                if mask == 0 or (mask == full and not include_axis_swaps):
                    continue
                dm, da = diagonal_delta(a, "row", first, second, mask)
                yield Trade("row", first, second, mask, dm, da)

            column_differences = [a[row][second] - a[row][first] for row in range(n)]
            for mask in zero_subset_masks(column_differences):
                if mask == 0 or (mask == full and not include_axis_swaps):
                    continue
                dm, da = diagonal_delta(a, "column", first, second, mask)
                yield Trade("column", first, second, mask, dm, da)


def apply_trade(a: Matrix, trade: Trade) -> None:
    n = len(a)
    if trade.axis == "row":
        for column in range(n):
            if trade.mask >> column & 1:
                a[trade.first][column], a[trade.second][column] = (
                    a[trade.second][column],
                    a[trade.first][column],
                )
    else:
        for row in range(n):
            if trade.mask >> row & 1:
                a[row][trade.first], a[row][trade.second] = (
                    a[row][trade.second],
                    a[row][trade.first],
                )


def line_sums(a: Matrix) -> tuple[list[int], list[int], int, int]:
    n = len(a)
    return (
        [sum(row) for row in a],
        [sum(a[row][column] for row in range(n)) for column in range(n)],
        sum(a[i][i] for i in range(n)),
        sum(a[i][n - 1 - i] for i in range(n)),
    )


def exact_two_by_two_counts(a: Matrix) -> tuple[int, int]:
    n = len(a)
    horizontal = vertical = 0
    for r1 in range(n):
        for r2 in range(r1 + 1, n):
            for c1 in range(n):
                for c2 in range(c1 + 1, n):
                    x00, x01 = a[r1][c1], a[r1][c2]
                    x10, x11 = a[r2][c1], a[r2][c2]
                    horizontal += x00 + x10 == x01 + x11
                    vertical += x00 + x01 == x10 + x11
    return horizontal, vertical


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("matrix_json")
    parser.add_argument("--greedy-steps", type=int, default=3)
    args = parser.parse_args()
    payload = json.load(open(args.matrix_json, encoding="utf-8"))
    a: Matrix = payload["matrix"]
    n = len(a)
    target = payload.get("line_sum", sum(a[0]))
    rows, columns, d1, d2 = line_sums(a)
    assert n and all(len(row) == n for row in a)
    assert len({value for row in a for value in row}) == n * n
    assert rows == [target] * n and columns == [target] * n

    h2, v2 = exact_two_by_two_counts(a)
    proper = list(enumerate_trades(a, include_axis_swaps=False))
    print(json.dumps({
        "n": n,
        "target": target,
        "initial_diagonals": [d1, d2],
        "initial_residuals": [d1 - target, d2 - target],
        "two_by_two_rowwise_swaps": h2,
        "two_by_two_columnwise_swaps": v2,
        "proper_row_subset_trades": sum(t.axis == "row" for t in proper),
        "proper_column_subset_trades": sum(t.axis == "column" for t in proper),
    }, indent=2))

    for step in range(args.greedy_steps):
        _, _, d1, d2 = line_sums(a)
        old_score = abs(d1 - target) + abs(d2 - target)
        best: tuple[int, Trade] | None = None
        for trade in enumerate_trades(a, include_axis_swaps=True):
            score = abs(d1 + trade.delta_main - target) + abs(d2 + trade.delta_anti - target)
            if score < old_score and (best is None or score < best[0]):
                best = score, trade
        if best is None:
            break
        score, trade = best
        apply_trade(a, trade)
        rows2, columns2, nd1, nd2 = line_sums(a)
        assert rows2 == rows and columns2 == columns
        assert len({value for row in a for value in row}) == n * n
        print(json.dumps({
            "greedy_step": step + 1,
            "axis": trade.axis,
            "first": trade.first,
            "second": trade.second,
            "mask": trade.mask,
            "delta": [trade.delta_main, trade.delta_anti],
            "residuals": [nd1 - target, nd2 - target],
            "E1": score,
        }))


if __name__ == "__main__":
    main()
