#!/usr/bin/env python3
"""Executable checks for the universal prime-magic orbit subgroup.

Primality is deliberately irrelevant here: the transformations only move
positions.  A Siamese odd-order integer magic square gives distinct labels and
therefore detects both broken line sums and duplicate coordinate maps.
"""

from __future__ import annotations

import argparse
import itertools
import math
import random
from collections.abc import Iterable, Sequence


Matrix = list[list[int]]
CoordinateMap = tuple[int, ...]


def reverse(i: int, n: int) -> int:
    return n - 1 - i


def siamese_magic(n: int) -> Matrix:
    if n < 3 or n % 2 == 0:
        raise ValueError("Siamese construction requires odd n >= 3")
    out = [[0] * n for _ in range(n)]
    r, c = 0, n // 2
    for value in range(1, n * n + 1):
        out[r][c] = value
        nr, nc = (r - 1) % n, (c + 1) % n
        if out[nr][nc]:
            r = (r + 1) % n
        else:
            r, c = nr, nc
    return out


def verify_magic(a: Sequence[Sequence[int]]) -> None:
    n = len(a)
    if n == 0 or any(len(row) != n for row in a):
        raise AssertionError("not square")
    target = sum(a[0])
    assert all(sum(row) == target for row in a)
    assert all(sum(a[r][c] for r in range(n)) == target for c in range(n))
    assert sum(a[i][i] for i in range(n)) == target
    assert sum(a[i][n - 1 - i] for i in range(n)) == target
    flat = [value for row in a for value in row]
    assert len(flat) == len(set(flat))


def centralizer_permutations(n: int) -> Iterable[tuple[int, ...]]:
    """Enumerate C_{S_n}(R), practical only for small n."""
    m = n // 2
    fixed = [n // 2] if n % 2 else []
    pairs = [(i, reverse(i, n)) for i in range(m)]
    for pair_order in itertools.permutations(range(m)):
        for flips in range(1 << m):
            p = [-1] * n
            for source_pair, target_pair in enumerate(pair_order):
                sa, sb = pairs[source_pair]
                ta, tb = pairs[target_pair]
                if flips >> source_pair & 1:
                    ta, tb = tb, ta
                p[sa], p[sb] = ta, tb
            for center in fixed:
                p[center] = center
            yield tuple(p)


def random_centralizer(n: int, rng: random.Random) -> tuple[int, ...]:
    m = n // 2
    targets = list(range(m))
    rng.shuffle(targets)
    p = [-1] * n
    for source_pair, target_pair in enumerate(targets):
        sa, sb = source_pair, reverse(source_pair, n)
        ta, tb = target_pair, reverse(target_pair, n)
        if rng.getrandbits(1):
            ta, tb = tb, ta
        p[sa], p[sb] = ta, tb
    if n % 2:
        p[m] = m
    return tuple(p)


def source_map(n: int, p: Sequence[int], coset: int) -> CoordinateMap:
    """Return output-cell -> source-cell map for one of four G/H cosets.

    coset 0: (p(i), p(j))
    coset 1: (p(i), R p(j))
    coset 2: (p(j), p(i))
    coset 3: (p(j), R p(i))
    """
    out: list[int] = []
    for i in range(n):
        for j in range(n):
            if coset == 0:
                r, c = p[i], p[j]
            elif coset == 1:
                r, c = p[i], reverse(p[j], n)
            elif coset == 2:
                r, c = p[j], p[i]
            elif coset == 3:
                r, c = p[j], reverse(p[i], n)
            else:
                raise ValueError(coset)
            out.append(r * n + c)
    return tuple(out)


def apply_source_map(a: Sequence[Sequence[int]], f: CoordinateMap) -> Matrix:
    n = len(a)
    return [[a[f[i * n + j] // n][f[i * n + j] % n] for j in range(n)] for i in range(n)]


def compose(f: CoordinateMap, g: CoordinateMap) -> CoordinateMap:
    """Composition of coordinate permutations, f after g."""
    return tuple(f[g[position]] for position in range(len(f)))


def inverse(f: CoordinateMap) -> CoordinateMap:
    out = [-1] * len(f)
    for source, target in enumerate(f):
        out[target] = source
    return tuple(out)


def exhaustive_small_order(n: int) -> None:
    base = siamese_magic(n)
    h = list(centralizer_permutations(n))
    maps: set[CoordinateMap] = set()
    for p in h:
        assert all(p[reverse(i, n)] == reverse(p[i], n) for i in range(n))
        for q in range(4):
            f = source_map(n, p, q)
            verify_magic(apply_source_map(base, f))
            maps.add(f)
    expected_h = math.factorial(n // 2) * (1 << (n // 2))
    assert len(h) == expected_h
    assert len(maps) == 4 * expected_h
    identity = tuple(range(n * n))
    assert identity in maps
    assert all(inverse(f) in maps for f in maps)
    assert all(compose(f, g) in maps for f in maps for g in maps)
    print(
        f"n={n}: |H|={len(h)}, |G|={len(maps)} "
        "(exhaustive identity/inverse/closure/properties passed)"
    )


def randomized_nineteen(iterations: int, seed: int) -> None:
    n = 19
    base = siamese_magic(n)
    rng = random.Random(seed)
    for _ in range(iterations):
        p = random_centralizer(n, rng)
        q = rng.randrange(4)
        verify_magic(apply_source_map(base, source_map(n, p, q)))
    print(f"n=19: {iterations} random group transforms passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=10_000)
    parser.add_argument("--seed", type=int, default=0x19_361)
    args = parser.parse_args()
    exhaustive_small_order(3)
    exhaustive_small_order(5)
    randomized_nineteen(args.iterations, args.seed)


if __name__ == "__main__":
    main()
