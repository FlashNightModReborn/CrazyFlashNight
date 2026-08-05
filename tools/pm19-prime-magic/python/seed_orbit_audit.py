#!/usr/bin/env python3
"""Determine whether unique-valued seeds share the universal orbit G."""

from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path
from typing import Any


Matrix = list[list[int]]


def group_relation(source: Matrix, target: Matrix) -> dict[str, Any] | None:
    n = len(source)
    if len(target) != n or any(len(row) != n for row in source + target):
        return None
    positions = {
        source[row][column]: (row, column)
        for row in range(n)
        for column in range(n)
    }
    if len(positions) != n * n:
        raise ValueError("source values must be globally unique")
    if set(positions) != {value for row in target for value in row}:
        return None

    reverse = lambda index: n - 1 - index
    for transpose in (False, True):
        for axis_reversal in (False, True):
            permutation: list[int | None] = [None] * n
            valid = True
            if not transpose:
                for row in range(n):
                    source_rows = {positions[target[row][column]][0] for column in range(n)}
                    if len(source_rows) != 1:
                        valid = False
                        break
                    permutation[row] = next(iter(source_rows))
                if not valid:
                    continue
                for column in range(n):
                    source_columns = {positions[target[row][column]][1] for row in range(n)}
                    lookup = reverse(column) if axis_reversal else column
                    if len(source_columns) != 1 or next(iter(source_columns)) != permutation[lookup]:
                        valid = False
                        break
            else:
                for column in range(n):
                    source_rows = {positions[target[row][column]][0] for row in range(n)}
                    if len(source_rows) != 1:
                        valid = False
                        break
                    permutation[column] = next(iter(source_rows))
                if not valid:
                    continue
                for row in range(n):
                    source_columns = {positions[target[row][column]][1] for column in range(n)}
                    lookup = reverse(row) if axis_reversal else row
                    if len(source_columns) != 1 or next(iter(source_columns)) != permutation[lookup]:
                        valid = False
                        break

            concrete = [int(value) for value in permutation]
            if (
                valid
                and sorted(concrete) == list(range(n))
                and all(concrete[reverse(index)] == reverse(concrete[index]) for index in range(n))
            ):
                return {
                    "transpose": transpose,
                    "axisReversal": axis_reversal,
                    "permutation": concrete,
                }
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seeds", type=Path, nargs="+")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    boards = [json.loads(path.read_text(encoding="utf-8"))["matrix"] for path in args.seeds]
    relations = []
    for left, right in itertools.combinations(range(len(boards)), 2):
        relation = group_relation(boards[left], boards[right])
        if relation is not None:
            relations.append({"left": left, "right": right, **relation})
    payload = {
        "format": "prime-magic-seed-orbit-audit/v1",
        "seedCount": len(boards),
        "pairCount": len(boards) * (len(boards) - 1) // 2,
        "relatedPairCount": len(relations),
        "pairwiseDistinctUniversalOrbits": not relations,
        "universalOrbitSizePerSeed": 743_178_240,
        "combinedStateCount": 743_178_240 * len(boards) if not relations else None,
        "relations": relations,
    }
    rendered = json.dumps(payload, indent=2, sort_keys=True)
    print(rendered)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    return 0 if not relations else 1


if __name__ == "__main__":
    raise SystemExit(main())
