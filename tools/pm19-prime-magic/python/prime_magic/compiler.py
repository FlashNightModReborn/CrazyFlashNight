#!/usr/bin/env python3
"""Offline compiler upgrading a prime semimagic square by row/column permutations.

The core reduction is two-stage:

1. Find a zero-deviation assignment ``f`` (one column per row).  It becomes the
   main diagonal.
2. Find an involution ``tau`` on the rows with cycle type ``2^m 1`` such that
   ``r -> f(tau(r))`` is a second zero-deviation assignment.  It becomes the
   secondary diagonal after ordering paired rows symmetrically.

Both searches use deterministic iterated local search.  An optional bounded
exact DFS can finish/exhaust the involution subproblem for a fixed assignment.
The compiler contains no primality checker; final output must be accepted by
the separately implemented ``prime_magic.verify`` executable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import multiprocessing as mp
import os
import struct
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable

try:
    import resource
except ImportError:  # Windows
    resource = None  # type: ignore[assignment]


MASK64 = (1 << 64) - 1
BINARY_HEADER = struct.Struct("<4sHHQ")
ALGORITHM_ID = "two-zero-assignments-with-involution/v1"


class Pcg32:
    """Small serializable PCG-XSH-RR generator with unbiased bounded draws."""

    __slots__ = ("state", "increment")

    def __init__(self, seed: int, stream: int = 0x9E37_79B9_7F4A_7C15) -> None:
        self.state = 0
        self.increment = ((stream << 1) | 1) & MASK64
        self.next_u32()
        self.state = (self.state + (seed & MASK64)) & MASK64
        self.next_u32()

    @classmethod
    def restore(cls, state: int, increment: int) -> "Pcg32":
        instance = cls.__new__(cls)
        instance.state = state & MASK64
        instance.increment = increment & MASK64
        return instance

    def next_u32(self) -> int:
        old = self.state
        self.state = (old * 6364136223846793005 + self.increment) & MASK64
        xorshifted = (((old >> 18) ^ old) >> 27) & 0xFFFF_FFFF
        rotation = old >> 59
        return ((xorshifted >> rotation) | (xorshifted << ((-rotation) & 31))) & 0xFFFF_FFFF

    def randbelow(self, bound: int) -> int:
        if not 0 < bound <= 0x1_0000_0000:
            raise ValueError("PCG bounded draws require 0 < bound <= 2**32")
        # Equivalent to unsigned ``(-bound) % bound`` in the reference PCG
        # implementation; Python integers do not wrap, so spell out 2**32.
        threshold = (1 << 32) % bound
        while True:
            value = self.next_u32()
            if value >= threshold:
                return value % bound

    def shuffle(self, values: list[Any]) -> None:
        for index in range(len(values) - 1, 0, -1):
            other = self.randbelow(index + 1)
            values[index], values[other] = values[other], values[index]


@dataclass
class SearchStats:
    started_unix_ns: int = field(default_factory=time.time_ns)
    elapsed_seconds: float = 0.0
    candidate_moves: int = 0
    accepted_moves: int = 0
    improving_moves: int = 0
    kick_moves: int = 0
    assignment_restarts: int = 0
    involution_restarts: int = 0
    outer_attempts: int = 0
    exact_solver_nodes: int = 0
    exact_solver_exhausted: bool = False
    exact_solver_exhausted_subproblems: int = 0
    exact_solver_budget_stops: int = 0
    best_assignment_error: int | None = None
    best_secondary_error: int | None = None
    longest_plateau: int = 0
    peak_rss_kib: int = 0
    peak_rss_available: bool = False
    # A search residual of r represents an actual diagonal error of
    # r*objective_error_scale_numerator/objective_error_scale_denominator.
    objective_error_scale_numerator: int = 1
    objective_error_scale_denominator: int = 1
    objective_trace: list[dict[str, int | str]] = field(default_factory=list)

    def finish(self, start: float) -> None:
        self.elapsed_seconds = time.perf_counter() - start
        if resource is not None:
            raw = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            # Linux reports KiB; macOS reports bytes.
            self.peak_rss_kib = int(raw / 1024) if sys.platform == "darwin" else int(raw)
            self.peak_rss_available = True

    def metrics(self) -> dict[str, Any]:
        elapsed = max(self.elapsed_seconds, 1e-12)
        return {
            **asdict(self),
            "candidate_moves_per_second": self.candidate_moves / elapsed,
            # Best-improvement scans evaluate a full neighborhood, so there is
            # no SA-style one-proposal acceptance probability.  Report the
            # precisely defined selection ratio and keep kicks separate.
            "acceptance_rate": self.improving_moves / max(self.candidate_moves, 1),
            "acceptance_rate_definition": (
                "selected improving moves / evaluated candidate neighbors; "
                "kick moves excluded"
            ),
            "state_change_units_per_candidate": (
                self.accepted_moves / max(self.candidate_moves, 1)
            ),
        }


@dataclass(frozen=True)
class CompilerConfig:
    seed: int = 1
    outer_attempts: int = 64
    assignment_restarts: int = 128
    assignment_steps: int = 256
    assignment_kick_swaps: int = 3
    involution_restarts: int = 128
    involution_steps: int = 512
    exact_tail_nodes: int = 0


@dataclass(frozen=True)
class UpgradeResult:
    matrix: list[list[int]]
    row_permutation: list[int]
    column_permutation: list[int]
    main_assignment: list[int]
    row_involution: list[int]
    stats: dict[str, Any]
    compiler_seed: int


def _load_semimagic(path: Path) -> tuple[list[list[int]], int]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    matrix = payload.get("matrix")
    if not isinstance(matrix, list) or not matrix:
        raise ValueError("input JSON has no non-empty matrix")
    size = len(matrix)
    declared_size = payload.get("size", payload.get("order"))
    if declared_size is not None and (
        not isinstance(declared_size, int)
        or isinstance(declared_size, bool)
        or declared_size != size
    ):
        raise ValueError(
            f"input declared dimension {declared_size!r} does not match matrix dimension {size}"
        )
    if size % 2 != 1 or any(not isinstance(row, list) or len(row) != size for row in matrix):
        raise ValueError("route A requires a square matrix of odd order")
    if size > 0xFFFF:
        raise ValueError("PM19 binary v1 requires order <= 65535")
    if any(not isinstance(value, int) or isinstance(value, bool) for row in matrix for value in row):
        raise ValueError("matrix contains a non-integer value")
    if any(not 0 <= value <= 0xFFFF_FFFF for row in matrix for value in row):
        raise ValueError("PM19 binary v1 requires every element to fit unsigned 32-bit")

    row_sums = [sum(row) for row in matrix]
    column_sums = [sum(matrix[row][column] for row in range(size)) for column in range(size)]
    if len(set(row_sums)) != 1 or len(set(column_sums)) != 1 or row_sums[0] != column_sums[0]:
        raise ValueError("input is not semimagic")
    if not 0 <= row_sums[0] < (1 << 64):
        raise ValueError("PM19 binary v1 requires an unsigned 64-bit magic sum")
    return matrix, row_sums[0]


def _run_independent_verifier(
    path: Path, *, semimagic: bool = False, require_checksum: bool = False
) -> dict[str, Any]:
    """Run the separately implemented verifier as a process boundary."""

    command = [sys.executable, "-m", "prime_magic.verify", str(path)]
    if semimagic:
        command.append("--semimagic")
    if require_checksum:
        command.append("--require-checksum")
    completed = subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        diagnostic = completed.stdout.strip() or completed.stderr.strip()
        raise ValueError(
            f"independent verifier rejected {path}: {diagnostic[:4000]}"
        )
    return json.loads(completed.stdout)


def _verify_completed_checkpoint_artifacts(
    manifest: dict[str, Any], output_directory: Path, completed: int
) -> None:
    """Reject stale/corrupt completed work instead of silently skipping it."""

    base = output_directory.resolve()
    records = manifest.get("seeds", [])
    configuration = manifest.get("configuration")
    if not isinstance(configuration, dict):
        raise ValueError("checkpoint manifest configuration is invalid")
    base_seed = configuration.get("baseSeed")
    worker_count = configuration.get("workers")
    if (
        not isinstance(base_seed, int)
        or isinstance(base_seed, bool)
        or not isinstance(worker_count, int)
        or isinstance(worker_count, bool)
        or worker_count < 1
    ):
        raise ValueError("checkpoint manifest seed/worker configuration is invalid")
    if len(records) != completed:
        raise ValueError("checkpoint seed-record count does not match completed count")
    for expected_index, record in enumerate(records):
        if record.get("index") != expected_index:
            raise ValueError("checkpoint seed indices are not contiguous")
        files = record.get("files", {})
        json_name = files.get("json")
        binary_name = files.get("binary")
        if not isinstance(json_name, str) or not isinstance(binary_name, str):
            raise ValueError(f"checkpoint seed {expected_index} has invalid file names")
        json_path = (base / json_name).resolve()
        binary_path = (base / binary_name).resolve()
        if json_path.parent != base or binary_path.parent != base:
            raise ValueError("checkpoint artifact path escapes the output directory")
        if not json_path.is_file() or not binary_path.is_file():
            raise ValueError(f"checkpoint seed {expected_index} artifact is missing")
        if binary_path.stat().st_size != files.get("binaryBytes"):
            raise ValueError(f"checkpoint seed {expected_index} binary length mismatch")
        json_hash = hashlib.sha256(json_path.read_bytes()).hexdigest()
        binary_hash = hashlib.sha256(binary_path.read_bytes()).hexdigest()
        if json_hash != files.get("jsonSha256") or binary_hash != files.get("binarySha256"):
            raise ValueError(f"checkpoint seed {expected_index} artifact SHA-256 mismatch")
        json_report = _run_independent_verifier(json_path, require_checksum=True)
        binary_report = _run_independent_verifier(binary_path)
        seed_payload = json.loads(json_path.read_text(encoding="utf-8"))
        compiler_metadata = seed_payload.get("compiler")
        worker_records = record.get("workers")
        verification_record = record.get("verification")
        job_seed = _derive_seed(base_seed, expected_index)
        if not isinstance(worker_records, list) or len(worker_records) != worker_count:
            raise ValueError(f"checkpoint seed {expected_index} worker records are invalid")
        successful_workers: list[int] = []
        for worker_id, worker_record in enumerate(worker_records):
            expected_worker_seed = job_seed if worker_id == 0 else _derive_seed(job_seed, worker_id)
            if (
                not isinstance(worker_record, dict)
                or worker_record.get("worker") != worker_id
                or worker_record.get("seed") != expected_worker_seed
                or not isinstance(worker_record.get("success"), bool)
            ):
                raise ValueError(
                    f"checkpoint seed {expected_index} worker derivation record mismatch"
                )
            if worker_record["success"]:
                successful_workers.append(worker_id)
        if not successful_workers:
            raise ValueError(f"checkpoint seed {expected_index} records no successful worker")
        selected_worker = min(successful_workers)
        selected_seed = job_seed if selected_worker == 0 else _derive_seed(job_seed, selected_worker)
        if (
            record.get("requestedBaseSeed") != base_seed
            or record.get("compilerSeed") != selected_seed
            or not isinstance(compiler_metadata, dict)
            or compiler_metadata.get("algorithm") != ALGORITHM_ID
            or compiler_metadata.get("randomSeed") != selected_seed
            or seed_payload.get("sourceFileSha256") != manifest.get("sourceSha256")
        ):
            raise ValueError(f"checkpoint seed {expected_index} compiler witness binding mismatch")
        if (
            not isinstance(verification_record, dict)
            or verification_record.get("jsonValid") is not True
            or verification_record.get("binaryValid") is not True
            or verification_record.get("canonicalChecksum") != files.get("canonicalChecksum")
            or verification_record.get("binaryFileSha256") != files.get("binarySha256")
        ):
            raise ValueError(f"checkpoint seed {expected_index} verification record mismatch")
        if (
            json_report.get("canonical_checksum") != files.get("canonicalChecksum")
            or binary_report.get("canonical_checksum") != files.get("canonicalChecksum")
            or json_report.get("magic_sum") != manifest.get("magicSum")
            or binary_report.get("magic_sum") != manifest.get("magicSum")
            or binary_report.get("input_file_sha256") != files.get("binarySha256")
        ):
            raise ValueError(f"checkpoint seed {expected_index} verification binding mismatch")


def _deviation_matrix(matrix: list[list[int]], magic_sum: int) -> tuple[list[list[int]], int]:
    size = len(matrix)
    # ``sum A[r,f(r)] == S`` iff ``sum (n*A[r,f(r)]-S) == 0``.
    # This integer form also works when the average S/n is non-integral.
    raw = [[size * value - magic_sum for value in row] for row in matrix]
    scale = 0
    for row in raw:
        for value in row:
            scale = math.gcd(scale, abs(value))
    scale = max(scale, 1)
    return [[value // scale for value in row] for row in raw], scale


def _assignment_sum(weights: list[list[int]], permutation: list[int]) -> int:
    return sum(weights[row][column] for row, column in enumerate(permutation))


def _record_best(stats: SearchStats, field_name: str, value: int) -> None:
    scaled_absolute = abs(value)
    numerator = scaled_absolute * stats.objective_error_scale_numerator
    denominator = stats.objective_error_scale_denominator
    if numerator % denominator:
        raise AssertionError("search residual does not map to an integral diagonal error")
    absolute = numerator // denominator
    previous = getattr(stats, field_name)
    if previous is None or absolute < previous:
        setattr(stats, field_name, absolute)
        stats.objective_trace.append(
            {
                "phase": field_name,
                "absoluteError": absolute,
                "scaledResidual": scaled_absolute,
                "candidateMoves": stats.candidate_moves,
                "acceptedMoves": stats.accepted_moves,
            }
        )


def _find_zero_assignment(
    weights: list[list[int]],
    rng: Pcg32,
    config: CompilerConfig,
    stats: SearchStats,
) -> list[int] | None:
    size = len(weights)
    for _ in range(config.assignment_restarts):
        stats.assignment_restarts += 1
        permutation = list(range(size))
        rng.shuffle(permutation)
        residual = _assignment_sum(weights, permutation)
        plateau = 0
        for _step in range(config.assignment_steps):
            _record_best(stats, "best_assignment_error", residual)
            if residual == 0:
                return permutation

            current_absolute = abs(residual)
            best_absolute = current_absolute
            candidates: list[tuple[int, int, int]] = []
            for left in range(size - 1):
                left_column = permutation[left]
                for right in range(left + 1, size):
                    right_column = permutation[right]
                    candidate = (
                        residual
                        + weights[left][right_column]
                        + weights[right][left_column]
                        - weights[left][left_column]
                        - weights[right][right_column]
                    )
                    stats.candidate_moves += 1
                    candidate_absolute = abs(candidate)
                    if candidate_absolute < best_absolute:
                        best_absolute = candidate_absolute
                        candidates = [(left, right, candidate)]
                    elif candidate_absolute == best_absolute and candidate_absolute < current_absolute:
                        candidates.append((left, right, candidate))

            if candidates:
                left, right, residual = candidates[rng.randbelow(len(candidates))]
                permutation[left], permutation[right] = permutation[right], permutation[left]
                stats.accepted_moves += 1
                stats.improving_moves += 1
                plateau = 0
                if residual == 0:
                    _record_best(stats, "best_assignment_error", residual)
                    return permutation
            else:
                plateau += 1
                stats.longest_plateau = max(stats.longest_plateau, plateau)
                for _ in range(config.assignment_kick_swaps):
                    left = rng.randbelow(size)
                    right = rng.randbelow(size - 1)
                    if right >= left:
                        right += 1
                    left_column, right_column = permutation[left], permutation[right]
                    residual += (
                        weights[left][right_column]
                        + weights[right][left_column]
                        - weights[left][left_column]
                        - weights[right][right_column]
                    )
                    permutation[left], permutation[right] = right_column, left_column
                    stats.accepted_moves += 1
                    stats.kick_moves += 1
                    if residual == 0:
                        _record_best(stats, "best_assignment_error", residual)
                        return permutation
        if residual == 0:
            _record_best(stats, "best_assignment_error", residual)
            return permutation
    return None


def _cross_edge(weights: list[list[int]], assignment: list[int], left: int, right: int) -> int:
    return weights[left][assignment[right]] + weights[right][assignment[left]]


def _involution_residual(
    weights: list[list[int]],
    assignment: list[int],
    center: int,
    pairs: list[list[int]],
) -> int:
    return weights[center][assignment[center]] + sum(
        _cross_edge(weights, assignment, left, right) for left, right in pairs
    )


def _find_zero_involution(
    weights: list[list[int]],
    assignment: list[int],
    rng: Pcg32,
    config: CompilerConfig,
    stats: SearchStats,
) -> list[int] | None:
    size = len(weights)
    pair_count = size // 2
    for _ in range(config.involution_restarts):
        stats.involution_restarts += 1
        shuffled = list(range(size))
        rng.shuffle(shuffled)
        center = shuffled.pop()
        pairs = [[shuffled[index], shuffled[index + 1]] for index in range(0, size - 1, 2)]
        residual = _involution_residual(weights, assignment, center, pairs)
        plateau = 0

        for _step in range(config.involution_steps):
            _record_best(stats, "best_secondary_error", residual)
            if residual == 0:
                return _pairs_to_involution(size, center, pairs)

            current_absolute = abs(residual)
            best_absolute = current_absolute
            moves: list[tuple[str, int, int, int, int]] = []

            for first in range(pair_count - 1):
                a, b = pairs[first]
                for second in range(first + 1, pair_count):
                    c, d = pairs[second]
                    old = _cross_edge(weights, assignment, a, b) + _cross_edge(weights, assignment, c, d)
                    candidate = residual - old + _cross_edge(weights, assignment, a, c) + _cross_edge(weights, assignment, b, d)
                    stats.candidate_moves += 1
                    best_absolute, moves = _consider_move(
                        current_absolute, best_absolute, abs(candidate), moves,
                        ("rewire", first, second, 0, candidate),
                    )
                    candidate = residual - old + _cross_edge(weights, assignment, a, d) + _cross_edge(weights, assignment, b, c)
                    stats.candidate_moves += 1
                    best_absolute, moves = _consider_move(
                        current_absolute, best_absolute, abs(candidate), moves,
                        ("rewire", first, second, 1, candidate),
                    )

            old_fixed = weights[center][assignment[center]]
            for pair_index, (a, b) in enumerate(pairs):
                old_edge = _cross_edge(weights, assignment, a, b)
                candidate = residual - old_fixed - old_edge + weights[a][assignment[a]] + _cross_edge(weights, assignment, center, b)
                stats.candidate_moves += 1
                best_absolute, moves = _consider_move(
                    current_absolute, best_absolute, abs(candidate), moves,
                    ("center", pair_index, 0, 0, candidate),
                )
                candidate = residual - old_fixed - old_edge + weights[b][assignment[b]] + _cross_edge(weights, assignment, a, center)
                stats.candidate_moves += 1
                best_absolute, moves = _consider_move(
                    current_absolute, best_absolute, abs(candidate), moves,
                    ("center", pair_index, 1, 0, candidate),
                )

            if moves:
                kind, first, second, orientation, residual = moves[rng.randbelow(len(moves))]
                if kind == "rewire":
                    a, b = pairs[first]
                    c, d = pairs[second]
                    if orientation == 0:
                        pairs[first], pairs[second] = [a, c], [b, d]
                    else:
                        pairs[first], pairs[second] = [a, d], [b, c]
                else:
                    a, b = pairs[first]
                    if second == 0:
                        pairs[first], center = [center, b], a
                    else:
                        pairs[first], center = [a, center], b
                stats.accepted_moves += 1
                stats.improving_moves += 1
                plateau = 0
                if residual == 0:
                    _record_best(stats, "best_secondary_error", residual)
                    return _pairs_to_involution(size, center, pairs)
            else:
                plateau += 1
                stats.longest_plateau = max(stats.longest_plateau, plateau)
                flattened = [value for pair in pairs for value in pair]
                rng.shuffle(flattened)
                pairs = [[flattened[index], flattened[index + 1]] for index in range(0, size - 1, 2)]
                residual = _involution_residual(weights, assignment, center, pairs)
                stats.accepted_moves += pair_count
                stats.kick_moves += pair_count
                if residual == 0:
                    _record_best(stats, "best_secondary_error", residual)
                    return _pairs_to_involution(size, center, pairs)
        if residual == 0:
            _record_best(stats, "best_secondary_error", residual)
            return _pairs_to_involution(size, center, pairs)
    return None


def _consider_move(
    current_absolute: int,
    best_absolute: int,
    candidate_absolute: int,
    moves: list[tuple[str, int, int, int, int]],
    move: tuple[str, int, int, int, int],
) -> tuple[int, list[tuple[str, int, int, int, int]]]:
    if candidate_absolute < best_absolute:
        return candidate_absolute, [move]
    if candidate_absolute == best_absolute and candidate_absolute < current_absolute:
        moves.append(move)
    return best_absolute, moves


def _pairs_to_involution(size: int, center: int, pairs: list[list[int]]) -> list[int]:
    involution = list(range(size))
    involution[center] = center
    for left, right in pairs:
        involution[left] = right
        involution[right] = left
    return involution


def _exact_involution_search(
    weights: list[list[int]],
    assignment: list[int],
    node_budget: int,
    stats: SearchStats,
) -> list[int] | None:
    """Complete over all ``2^m 1`` involutions unless node_budget stops it."""

    # This compatibility flag describes this call; aggregate diagnostics use
    # the two explicit counters below and therefore cannot become "sticky".
    stats.exact_solver_exhausted = False
    size = len(weights)
    full_mask = (1 << size) - 1
    stopped = False

    def dfs(mask: int, residual: int, pairs: list[list[int]]) -> list[list[int]] | None:
        nonlocal stopped
        if node_budget and stats.exact_solver_nodes >= node_budget:
            stopped = True
            return None
        stats.exact_solver_nodes += 1
        if mask == 0:
            return [pair[:] for pair in pairs] if residual == 0 else None

        left_bit = mask & -mask
        left = left_bit.bit_length() - 1
        rest = mask ^ left_bit
        candidates: list[tuple[int, int]] = []
        scan = rest
        while scan:
            right_bit = scan & -scan
            right = right_bit.bit_length() - 1
            candidates.append((_cross_edge(weights, assignment, left, right), right))
            scan ^= right_bit
        candidates.sort(key=lambda item: abs(residual + item[0]))
        for edge, right in candidates:
            pairs.append([left, right])
            result = dfs(rest ^ (1 << right), residual + edge, pairs)
            pairs.pop()
            if result is not None or stopped:
                return result
        return None

    for center in range(size):
        fixed = weights[center][assignment[center]]
        pairs = dfs(full_mask ^ (1 << center), fixed, [])
        if pairs is not None:
            stats.exact_solver_exhausted = False
            return _pairs_to_involution(size, center, pairs)
        if stopped:
            stats.exact_solver_budget_stops += 1
            return None
    stats.exact_solver_exhausted = not stopped
    if stats.exact_solver_exhausted:
        stats.exact_solver_exhausted_subproblems += 1
    return None


def _permutations_from_solution(
    assignment: list[int], involution: list[int]
) -> tuple[list[int], list[int]]:
    size = len(assignment)
    half = size // 2
    center_candidates = [index for index, image in enumerate(involution) if image == index]
    if len(center_candidates) != 1:
        raise AssertionError("involution must have exactly one fixed point")
    center = center_candidates[0]
    representatives = [index for index in range(size) if index < involution[index]]
    if len(representatives) != half:
        raise AssertionError("involution has the wrong cycle type")
    representatives.sort()
    row_permutation = [0] * size
    for position, row in enumerate(representatives):
        row_permutation[position] = row
        row_permutation[size - 1 - position] = involution[row]
    row_permutation[half] = center
    column_permutation = [assignment[row] for row in row_permutation]
    return row_permutation, column_permutation


def _apply_permutations(
    matrix: list[list[int]], row_permutation: list[int], column_permutation: list[int]
) -> list[list[int]]:
    size = len(matrix)
    return [
        [matrix[row_permutation[row]][column_permutation[column]] for column in range(size)]
        for row in range(size)
    ]


def _internal_exact_sum_guard(matrix: list[list[int]], expected_sum: int) -> None:
    """Minimal construction guard, intentionally not a complete validator."""

    size = len(matrix)
    lines = [sum(row) for row in matrix]
    lines.extend(sum(matrix[row][column] for row in range(size)) for column in range(size))
    lines.append(sum(matrix[index][index] for index in range(size)))
    lines.append(sum(matrix[index][size - 1 - index] for index in range(size)))
    if any(value != expected_sum for value in lines):
        raise AssertionError("constructed square failed exact line-sum guard")


def compile_upgrade(matrix: list[list[int]], magic_sum: int, config: CompilerConfig) -> UpgradeResult:
    start = time.perf_counter()
    rng = Pcg32(config.seed)
    stats = SearchStats()
    weights, scale = _deviation_matrix(matrix, magic_sum)
    stats.objective_error_scale_numerator = scale
    stats.objective_error_scale_denominator = len(matrix)

    for _outer in range(config.outer_attempts):
        stats.outer_attempts += 1
        assignment = _find_zero_assignment(weights, rng, config, stats)
        if assignment is None:
            continue
        involution = _find_zero_involution(weights, assignment, rng, config, stats)
        if involution is None and config.exact_tail_nodes:
            involution = _exact_involution_search(
                weights, assignment, config.exact_tail_nodes, stats
            )
        if involution is None:
            continue

        row_permutation, column_permutation = _permutations_from_solution(assignment, involution)
        upgraded = _apply_permutations(matrix, row_permutation, column_permutation)
        _internal_exact_sum_guard(upgraded, magic_sum)
        stats.finish(start)
        return UpgradeResult(
            matrix=upgraded,
            row_permutation=row_permutation,
            column_permutation=column_permutation,
            main_assignment=assignment,
            row_involution=involution,
            stats=stats.metrics(),
            compiler_seed=config.seed,
        )

    stats.finish(start)
    raise RuntimeError(json.dumps({"error": "search budget exhausted", "stats": stats.metrics()}))


def _canonical_checksum(matrix: list[list[int]], magic_sum: int) -> str:
    payload = {
        "magicSum": magic_sum,
        "size": len(matrix),
        "values": [value for row in matrix for value in row],
    }
    data = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("ascii")
    return hashlib.sha256(data).hexdigest()


def _write_result(
    result: UpgradeResult,
    magic_sum: int,
    output_stem: Path,
    source_sha256: str,
) -> dict[str, Any]:
    output_stem.parent.mkdir(parents=True, exist_ok=True)
    size = len(result.matrix)
    values = [value for row in result.matrix for value in row]
    checksum = _canonical_checksum(result.matrix, magic_sum)
    payload = {
        "format": "prime-magic-seed/v1",
        "size": size,
        "magicSum": magic_sum,
        "checksum": f"sha256:{checksum}",
        "sourceFileSha256": source_sha256,
        "compiler": {
            "algorithm": ALGORITHM_ID,
            "randomSeed": result.compiler_seed,
            "rowPermutation": result.row_permutation,
            "columnPermutation": result.column_permutation,
            "mainAssignment": result.main_assignment,
            "rowInvolution": result.row_involution,
        },
        "matrix": result.matrix,
    }
    json_path = output_stem.with_suffix(".json")
    bin_path = output_stem.with_suffix(".bin")
    json_bytes = (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode("utf-8")
    # Construct both serializations fully before touching their final paths.
    binary = BINARY_HEADER.pack(b"PM19", 1, size, magic_sum) + struct.pack(
        f"<{len(values)}I", *values
    )
    json_temporary = json_path.with_suffix(json_path.suffix + ".tmp")
    binary_temporary = bin_path.with_suffix(bin_path.suffix + ".tmp")
    json_temporary.write_bytes(json_bytes)
    binary_temporary.write_bytes(binary)
    os.replace(json_temporary, json_path)
    os.replace(binary_temporary, bin_path)
    return {
        # Manifest paths are relative to the manifest directory so a packaged
        # seed bank remains relocatable.
        "json": json_path.name,
        "binary": bin_path.name,
        "canonicalChecksum": checksum,
        "jsonSha256": hashlib.sha256(json_bytes).hexdigest(),
        "binarySha256": hashlib.sha256(binary).hexdigest(),
        "binaryBytes": len(binary),
    }


def _derive_seed(base: int, index: int) -> int:
    value = (base + 0x9E37_79B9_7F4A_7C15 * (index + 1)) & MASK64
    value ^= value >> 30
    value = (value * 0xBF58_476D_1CE4_E5B9) & MASK64
    value ^= value >> 27
    value = (value * 0x94D0_49BB_1331_11EB) & MASK64
    return value ^ (value >> 31)


def _worker_compile(arguments: tuple[list[list[int]], int, CompilerConfig, int]) -> tuple[int, UpgradeResult | None, str | None]:
    matrix, magic_sum, config, worker_id = arguments
    try:
        return worker_id, compile_upgrade(matrix, magic_sum, config), None
    except Exception as exc:  # returned as diagnostics to the parent
        return worker_id, None, str(exc)


def compile_farm(
    matrix: list[list[int]], magic_sum: int, config: CompilerConfig, workers: int
) -> tuple[UpgradeResult, list[dict[str, Any]]]:
    if workers <= 1:
        result = compile_upgrade(matrix, magic_sum, config)
        return result, [{"worker": 0, "seed": config.seed, "success": True}]

    jobs = []
    for worker in range(workers):
        worker_seed = config.seed if worker == 0 else _derive_seed(config.seed, worker)
        worker_config = CompilerConfig(**{**asdict(config), "seed": worker_seed})
        jobs.append((matrix, magic_sum, worker_config, worker))
    context = mp.get_context("spawn")
    with context.Pool(workers) as pool:
        outcomes = pool.map(_worker_compile, jobs)
    diagnostics = [
        {
            "worker": worker,
            "seed": jobs[worker][2].seed,
            "success": result is not None,
            "error": error,
        }
        for worker, result, error in outcomes
    ]
    successes = [(worker, result) for worker, result, _error in outcomes if result is not None]
    if not successes:
        raise RuntimeError(json.dumps({"error": "all workers exhausted", "workers": diagnostics}))
    successes.sort(key=lambda item: item[0])
    return successes[0][1], diagnostics  # deterministic lowest worker id


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--outer-attempts", type=int, default=64)
    parser.add_argument("--assignment-restarts", type=int, default=128)
    parser.add_argument("--assignment-steps", type=int, default=256)
    parser.add_argument("--involution-restarts", type=int, default=128)
    parser.add_argument("--involution-steps", type=int, default=512)
    parser.add_argument("--exact-tail-nodes", type=int, default=0)
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()
    if args.count < 1 or args.workers < 1:
        parser.error("count and workers must be positive")

    # Search code never gets an opportunity to promote composite/duplicate
    # input under the prime-magic seed format.
    _run_independent_verifier(args.input, semimagic=True)
    matrix, magic_sum = _load_semimagic(args.input)
    source_sha256 = hashlib.sha256(args.input.read_bytes()).hexdigest()
    configuration = {
        "algorithm": ALGORITHM_ID,
        "baseSeed": args.seed,
        "workers": args.workers,
        "outerAttempts": args.outer_attempts,
        "assignmentRestarts": args.assignment_restarts,
        "assignmentSteps": args.assignment_steps,
        "involutionRestarts": args.involution_restarts,
        "involutionSteps": args.involution_steps,
        "exactTailNodes": args.exact_tail_nodes,
        "outputDirectory": str(args.output_dir.resolve()),
    }
    configuration_sha256 = hashlib.sha256(
        json.dumps(configuration, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    manifest: dict[str, Any] = {
        "format": "prime-magic-seed-manifest/v1",
        "source": str(args.input),
        "sourceSha256": source_sha256,
        "magicSum": magic_sum,
        "configuration": configuration,
        "configurationSha256": configuration_sha256,
        "seeds": [],
    }
    completed = 0
    if args.checkpoint and args.checkpoint.exists():
        checkpoint = json.loads(args.checkpoint.read_text(encoding="utf-8"))
        if not isinstance(checkpoint, dict):
            raise ValueError("checkpoint root must be an object")
        if (
            checkpoint.get("format") != "prime-magic-checkpoint/v1"
            or checkpoint.get("sourceSha256") != source_sha256
            or checkpoint.get("configurationSha256") != configuration_sha256
            or checkpoint.get("configuration") != configuration
        ):
            raise ValueError("checkpoint source/configuration identity does not match")
        completed_value = checkpoint.get("completed", 0)
        if not isinstance(completed_value, int) or isinstance(completed_value, bool):
            raise ValueError("checkpoint completed count must be a strict integer")
        completed = completed_value
        if completed < 0 or completed > args.count:
            raise ValueError("checkpoint completed count is outside the requested range")
        manifest = checkpoint.get("manifest", manifest)
        manifest_seed_records = manifest.get("seeds") if isinstance(manifest, dict) else None
        if (
            not isinstance(manifest, dict)
            or manifest.get("format") != "prime-magic-seed-manifest/v1"
            or manifest.get("source") != str(args.input)
            or manifest.get("sourceSha256") != source_sha256
            or manifest.get("magicSum") != magic_sum
            or manifest.get("configuration") != configuration
            or manifest.get("configurationSha256") != configuration_sha256
            or not isinstance(manifest_seed_records, list)
            or len(manifest_seed_records) != completed
        ):
            raise ValueError("checkpoint manifest is internally inconsistent")
        _verify_completed_checkpoint_artifacts(manifest, args.output_dir, completed)

    if args.log:
        args.log.parent.mkdir(parents=True, exist_ok=True)
    for index in range(completed, args.count):
        seed_job_started = time.perf_counter()
        seed = _derive_seed(args.seed, index)
        config = CompilerConfig(
            seed=seed,
            outer_attempts=args.outer_attempts,
            assignment_restarts=args.assignment_restarts,
            assignment_steps=args.assignment_steps,
            involution_restarts=args.involution_restarts,
            involution_steps=args.involution_steps,
            exact_tail_nodes=args.exact_tail_nodes,
        )
        result, workers = compile_farm(matrix, magic_sum, config, args.workers)
        packaging_started = time.perf_counter()
        files = _write_result(
            result,
            magic_sum,
            args.output_dir / f"prime_magic_{len(matrix)}_seed_{index:02d}",
            source_sha256,
        )
        packaging_seconds = time.perf_counter() - packaging_started
        verification_started = time.perf_counter()
        json_verification = _run_independent_verifier(
            args.output_dir / files["json"], require_checksum=True
        )
        binary_verification = _run_independent_verifier(
            args.output_dir / files["binary"]
        )
        verification_seconds = time.perf_counter() - verification_started
        record = {
            "index": index,
            "requestedBaseSeed": args.seed,
            "compilerSeed": result.compiler_seed,
            "files": files,
            "stats": result.stats,
            "packagingSeconds": packaging_seconds,
            "verificationSeconds": verification_seconds,
            "endToEndSeconds": time.perf_counter() - seed_job_started,
            "workers": workers,
            "verification": {
                "jsonValid": json_verification["valid"],
                "binaryValid": binary_verification["valid"],
                "canonicalChecksum": json_verification["canonical_checksum"],
                "binaryFileSha256": binary_verification["input_file_sha256"],
            },
        }
        manifest["seeds"].append(record)
        if args.log:
            with args.log.open("a", encoding="utf-8") as log:
                log.write(json.dumps(record, sort_keys=True) + "\n")
        if args.checkpoint:
            checkpoint_payload = {
                "format": "prime-magic-checkpoint/v1",
                "sourceSha256": source_sha256,
                "configuration": configuration,
                "configurationSha256": configuration_sha256,
                "completed": index + 1,
                "manifest": manifest,
            }
            temporary = args.checkpoint.with_suffix(args.checkpoint.suffix + ".tmp")
            temporary.parent.mkdir(parents=True, exist_ok=True)
            temporary.write_text(json.dumps(checkpoint_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            os.replace(temporary, args.checkpoint)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = args.output_dir / "manifest.json"
    manifest_temporary = manifest_path.with_suffix(manifest_path.suffix + ".tmp")
    manifest_temporary.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.replace(manifest_temporary, manifest_path)
    print(json.dumps({"manifest": str(manifest_path), "seedCount": len(manifest["seeds"])}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
