#!/usr/bin/env python3
"""Independent, dependency-free audit of the generated PM19 artifacts.

This deliberately imports no code from ``prime_magic``.  It validates the
source square, generated JSON/binary pairs, compiler witness metadata, and the
external manifest/checkpoint using separate parsing and primality logic.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "prime-magic-19"
SEEDS = PROJECT / "seeds"
SOURCE = PROJECT / "fixtures" / "prime_semimagic_19.json"
HEADER = struct.Struct("<4sHHQ")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def is_prime_trial_division(n: int) -> bool:
    """Exact for arbitrary Python ints; deliberately unrelated to MR code."""

    if type(n) is not int or n < 2:
        return False
    if n % 2 == 0:
        return n == 2
    limit = math.isqrt(n)
    divisor = 3
    while divisor <= limit:
        if n % divisor == 0:
            return False
        divisor += 2
    return True


def canonical_checksum(matrix: list[list[int]], magic_sum: int) -> str:
    payload = {
        "magicSum": magic_sum,
        "size": len(matrix),
        "values": [value for row in matrix for value in row],
    }
    encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("ascii")
    return sha256_bytes(encoded)


def assert_square(matrix: object, size: int) -> list[list[int]]:
    assert isinstance(matrix, list) and len(matrix) == size
    assert all(isinstance(row, list) and len(row) == size for row in matrix)
    assert all(type(value) is int for row in matrix for value in row)
    return matrix


def check_lines(matrix: list[list[int]], expected: int, diagonals: bool) -> None:
    n = len(matrix)
    assert all(sum(row) == expected for row in matrix)
    assert all(sum(matrix[i][j] for i in range(n)) == expected for j in range(n))
    if diagonals:
        assert sum(matrix[i][i] for i in range(n)) == expected
        assert sum(matrix[i][n - 1 - i] for i in range(n)) == expected


def decode_binary(path: Path) -> tuple[list[list[int]], int]:
    data = path.read_bytes()
    assert len(data) >= HEADER.size
    magic, version, n, magic_sum = HEADER.unpack_from(data)
    assert magic == b"PM19"
    assert version == 1
    assert len(data) == HEADER.size + 4 * n * n
    flat = list(struct.unpack_from(f"<{n*n}I", data, HEADER.size))
    return [flat[i * n : (i + 1) * n] for i in range(n)], magic_sum


def permutation(value: object, n: int) -> list[int]:
    assert isinstance(value, list)
    assert all(type(item) is int for item in value)
    assert sorted(value) == list(range(n))
    return value


def main() -> None:
    source_bytes = SOURCE.read_bytes()
    source_payload = json.loads(source_bytes)
    source = assert_square(source_payload["matrix"], 19)
    assert source_payload["order"] == len(source) == 19
    source_sum = source_payload["line_sum"]
    check_lines(source, source_sum, diagonals=False)
    source_flat = [x for row in source for x in row]
    assert len(set(source_flat)) == 361
    assert all(is_prime_trial_division(x) for x in source_flat)

    manifest = json.loads((SEEDS / "manifest.json").read_text())
    checkpoint = json.loads((SEEDS / "checkpoint.json").read_text())
    assert manifest["format"] == "prime-magic-seed-manifest/v1"
    assert checkpoint["format"] == "prime-magic-checkpoint/v1"
    configuration_bytes = json.dumps(
        manifest["configuration"], separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    configuration_sha256 = sha256_bytes(configuration_bytes)
    assert manifest["configurationSha256"] == configuration_sha256
    assert checkpoint["configurationSha256"] == configuration_sha256
    assert checkpoint["configuration"] == manifest["configuration"]
    assert manifest["magicSum"] == source_sum == 190_000_361
    assert manifest["sourceSha256"] == sha256_bytes(source_bytes)
    assert checkpoint["sourceSha256"] == sha256_bytes(source_bytes)
    assert checkpoint["completed"] == len(manifest["seeds"]) == 8
    assert checkpoint["manifest"] == manifest

    manifest_by_index = {record["index"]: record for record in manifest["seeds"]}
    assert sorted(manifest_by_index) == list(range(8))
    summaries: list[dict[str, object]] = []
    all_canonical: set[str] = set()

    for index in range(8):
        stem = SEEDS / f"prime_magic_19_seed_{index:02d}"
        json_path = stem.with_suffix(".json")
        bin_path = stem.with_suffix(".bin")
        report_path = SEEDS / f"prime_magic_19_seed_{index:02d}.verify.json"
        payload = json.loads(json_path.read_text())
        matrix = assert_square(payload["matrix"], 19)
        flat = [x for row in matrix for x in row]
        magic_sum = payload["magicSum"]

        assert payload["format"] == "prime-magic-seed/v1"
        assert payload["size"] == 19
        assert magic_sum == source_sum
        assert payload["sourceFileSha256"] == sha256_bytes(source_bytes)
        assert len(flat) == len(set(flat)) == 361
        assert set(flat) == set(source_flat)
        # Primality is checked independently for every serialized seed, even
        # though the set-equality check would be sufficient after source audit.
        assert all(is_prime_trial_division(x) for x in flat)
        check_lines(matrix, magic_sum, diagonals=True)
        assert max(flat) < 2**32
        assert magic_sum < 2**53

        canonical = canonical_checksum(matrix, magic_sum)
        assert payload["checksum"] == f"sha256:{canonical}"
        assert canonical not in all_canonical
        all_canonical.add(canonical)

        binary_matrix, binary_sum = decode_binary(bin_path)
        assert binary_matrix == matrix
        assert binary_sum == magic_sum

        compiler = payload["compiler"]
        rows = permutation(compiler["rowPermutation"], 19)
        columns = permutation(compiler["columnPermutation"], 19)
        assignment = permutation(compiler["mainAssignment"], 19)
        involution = permutation(compiler["rowInvolution"], 19)
        assert all(involution[involution[i]] == i for i in range(19))
        assert sum(involution[i] == i for i in range(19)) == 1
        assert all(columns[i] == assignment[rows[i]] for i in range(19))
        reconstructed = [[source[rows[i]][columns[j]] for j in range(19)] for i in range(19)]
        assert reconstructed == matrix
        assert sum(source[r][assignment[r]] for r in range(19)) == magic_sum
        assert sum(source[r][assignment[involution[r]]] for r in range(19)) == magic_sum

        record = manifest_by_index[index]
        assert record["compilerSeed"] == compiler["randomSeed"]
        assert record["files"]["canonicalChecksum"] == canonical
        assert record["files"]["jsonSha256"] == sha256_file(json_path)
        assert record["files"]["binarySha256"] == sha256_file(bin_path)
        assert record["files"]["binaryBytes"] == bin_path.stat().st_size == 1460
        assert record["verification"]["jsonValid"] is True
        assert record["verification"]["binaryValid"] is True
        assert record["verification"]["canonicalChecksum"] == canonical
        assert record["verification"]["binaryFileSha256"] == sha256_file(bin_path)
        manifest_json = Path(record["files"]["json"])
        manifest_binary = Path(record["files"]["binary"])
        if not manifest_json.is_absolute():
            manifest_json = SEEDS / manifest_json
        if not manifest_binary.is_absolute():
            manifest_binary = SEEDS / manifest_binary
        assert manifest_json.resolve() == json_path.resolve()
        assert manifest_binary.resolve() == bin_path.resolve()

        prior_report = json.loads(report_path.read_text())
        assert prior_report["valid"] is True
        assert prior_report["canonical_checksum"] == canonical
        assert prior_report["input_file_sha256"] == sha256_file(json_path)

        summaries.append(
            {
                "index": index,
                "canonicalChecksum": canonical,
                "jsonSha256": sha256_file(json_path),
                "binarySha256": sha256_file(bin_path),
                "compilerSeed": compiler["randomSeed"],
            }
        )

    output = {
        "source": {
            "sha256": sha256_bytes(source_bytes),
            "size": 19,
            "magicSum": source_sum,
            "mainDiagonalSum": sum(source[i][i] for i in range(19)),
            "secondaryDiagonalSum": sum(source[i][18 - i] for i in range(19)),
            "uniquePrimeCount": len(set(source_flat)),
        },
        "seedsValidated": len(summaries),
        "allJsonBinaryPairsExact": True,
        "allCompilerWitnessesExact": True,
        "manifestAndCheckpointExact": True,
        "summaries": summaries,
    }
    destination = Path(__file__).with_name("independent_verification.json")
    destination.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(json.dumps(output, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
