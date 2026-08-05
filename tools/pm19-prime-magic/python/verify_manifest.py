#!/usr/bin/env python3
"""Verify every JSON/binary/checksum binding in a compiled seed-bank manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from prime_magic.verify import load_matrix, verify_matrix


MASK64 = (1 << 64) - 1


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_sha256_hex(value: object) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def derive_seed(base: int, index: int) -> int:
    """Independent copy of the documented SplitMix-style job derivation."""

    value = (base + 0x9E37_79B9_7F4A_7C15 * (index + 1)) & MASK64
    value ^= value >> 30
    value = (value * 0xBF58_476D_1CE4_E5B9) & MASK64
    value ^= value >> 27
    value = (value * 0x94D0_49BB_1331_11EB) & MASK64
    return value ^ (value >> 31)


def strict_permutation(value: object, size: int) -> bool:
    return (
        isinstance(value, list)
        and len(value) == size
        and all(isinstance(item, int) and not isinstance(item, bool) for item in value)
        and sorted(value) == list(range(size))
    )


def verify_route_a_witness(
    source: list[list[int]], seed_payload: dict[str, object], target_sum: int
) -> list[str]:
    errors: list[str] = []
    matrix = seed_payload.get("matrix")
    compiler = seed_payload.get("compiler")
    size = len(source)
    if not isinstance(matrix, list) or not isinstance(compiler, dict):
        return ["missing matrix/compiler witness"]
    rho = compiler.get("rowPermutation")
    kappa = compiler.get("columnPermutation")
    assignment = compiler.get("mainAssignment")
    involution = compiler.get("rowInvolution")
    if not all(
        strict_permutation(value, size)
        for value in (rho, kappa, assignment, involution)
    ):
        return ["route-A witness arrays are not strict permutations"]

    # The type guard above proves these are lists of ints.
    rho_values = rho  # type: ignore[assignment]
    kappa_values = kappa  # type: ignore[assignment]
    assignment_values = assignment  # type: ignore[assignment]
    tau_values = involution  # type: ignore[assignment]
    if not all(tau_values[tau_values[row]] == row for row in range(size)):
        errors.append("rowInvolution is not an involution")
    if sum(tau_values[row] == row for row in range(size)) != 1:
        errors.append("rowInvolution does not have cycle type 1^1 2^m")
    if not all(
        kappa_values[position] == assignment_values[rho_values[position]]
        for position in range(size)
    ):
        errors.append("column permutation is not assignment after row permutation")
    if not all(
        rho_values[size - 1 - position] == tau_values[rho_values[position]]
        for position in range(size)
    ):
        errors.append("mirrored row order does not realize rowInvolution")
    try:
        reconstructed = [
            [source[rho_values[row]][kappa_values[column]] for column in range(size)]
            for row in range(size)
        ]
        if matrix != reconstructed:
            errors.append("seed matrix does not match declared row/column witness")
        first_sum = sum(source[row][assignment_values[row]] for row in range(size))
        crossed_sum = sum(
            source[row][assignment_values[tau_values[row]]] for row in range(size)
        )
        if first_sum != target_sum or crossed_sum != target_sum:
            errors.append("assignment/involution witness sums do not equal manifest magicSum")
    except (IndexError, TypeError):
        errors.append("route-A witness references malformed source data")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    decoded = json.loads(args.manifest.read_text(encoding="utf-8"))
    base = args.manifest.parent
    errors: list[str] = []
    if isinstance(decoded, dict):
        payload = decoded
    else:
        payload = {}
        errors.append("manifest root must be an object")
    if payload.get("format") != "prime-magic-seed-manifest/v1":
        errors.append("invalid manifest format")
    if not isinstance(payload.get("source"), str) or not payload.get("source"):
        errors.append("manifest source must be a non-empty string")
    if not is_sha256_hex(payload.get("sourceSha256")):
        errors.append("manifest sourceSha256 must be lowercase 64-hex")
    manifest_magic_sum = payload.get("magicSum")
    if not isinstance(manifest_magic_sum, int) or isinstance(manifest_magic_sum, bool):
        errors.append("manifest magicSum must be a strict integer")
    configuration = payload.get("configuration")
    if not isinstance(configuration, dict):
        errors.append("manifest configuration must be an object")
    configuration_hash = hashlib.sha256(
        json.dumps(configuration, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    if configuration_hash != payload.get("configurationSha256"):
        errors.append("configuration SHA-256 mismatch")
    if args.source and sha256(args.source) != payload.get("sourceSha256"):
        errors.append("source SHA-256 mismatch")
    source_matrix: list[list[int]] | None = None
    if args.source:
        try:
            source_payload = json.loads(args.source.read_text(encoding="utf-8"))
            candidate_source = source_payload.get("matrix")
            if (
                isinstance(candidate_source, list)
                and candidate_source
                and all(
                    isinstance(row, list) and len(row) == len(candidate_source)
                    for row in candidate_source
                )
            ):
                source_matrix = candidate_source
            else:
                errors.append("source matrix is malformed")
        except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
            errors.append(f"source decode error: {exc}")

    base_seed = configuration.get("baseSeed") if isinstance(configuration, dict) else None
    worker_count = configuration.get("workers") if isinstance(configuration, dict) else None
    algorithm = configuration.get("algorithm") if isinstance(configuration, dict) else None
    if not isinstance(base_seed, int) or isinstance(base_seed, bool):
        errors.append("configuration baseSeed must be a strict integer")
    if (
        not isinstance(worker_count, int)
        or isinstance(worker_count, bool)
        or worker_count < 1
    ):
        errors.append("configuration workers must be a positive strict integer")
    if not isinstance(algorithm, str) or not algorithm:
        errors.append("configuration algorithm must be a non-empty string")

    seed_records = payload.get("seeds")
    if not isinstance(seed_records, list) or not seed_records:
        errors.append("manifest seeds must be a non-empty list")
        seed_records = []

    records = []
    canonical_seen: set[str] = set()
    for expected_index, record in enumerate(seed_records):
        if not isinstance(record, dict):
            item_errors = ["seed record must be an object"]
            records.append({"index": expected_index, "valid": False, "errors": item_errors})
            errors.extend(f"seed {expected_index}: {error}" for error in item_errors)
            continue
        item_errors: list[str] = []
        if record.get("index") != expected_index:
            item_errors.append("record index is not contiguous")
        files = record.get("files")
        if not isinstance(files, dict):
            item_errors.append("files must be an object")
            records.append({"index": record.get("index"), "valid": False, "errors": item_errors})
            errors.extend(f"seed {record.get('index')}: {error}" for error in item_errors)
            continue
        json_name = files.get("json")
        binary_name = files.get("binary")
        if not isinstance(json_name, str) or not isinstance(binary_name, str):
            item_errors.append("invalid JSON or binary file name")
            records.append({"index": record.get("index"), "valid": False, "errors": item_errors})
            errors.extend(f"seed {record.get('index')}: {error}" for error in item_errors)
            continue
        resolved_base = base.resolve()
        json_path = (base / json_name).resolve()
        binary_path = (base / binary_name).resolve()
        if json_path.parent != resolved_base or binary_path.parent != resolved_base:
            item_errors.append("artifact path escapes manifest directory")
            records.append({"index": record.get("index"), "valid": False, "errors": item_errors})
            errors.extend(f"seed {record.get('index')}: {error}" for error in item_errors)
            continue
        if not json_path.is_file() or not binary_path.is_file():
            item_errors.append("missing JSON or binary file")
            records.append({"index": record.get("index"), "valid": False, "errors": item_errors})
            errors.extend(f"seed {record.get('index')}: {error}" for error in item_errors)
            continue

        json_file_hash = sha256(json_path)
        binary_file_hash = sha256(binary_path)
        if json_file_hash != files.get("jsonSha256"):
            item_errors.append("JSON file SHA-256 mismatch")
        if binary_file_hash != files.get("binarySha256"):
            item_errors.append("binary file SHA-256 mismatch")
        if binary_path.stat().st_size != files.get("binaryBytes"):
            item_errors.append("binary byte length mismatch")

        try:
            json_payload = json.loads(json_path.read_text(encoding="utf-8"))
            (
                json_matrix,
                json_sum,
                declared_checksum,
                _json_format,
                json_dimension,
            ) = load_matrix(json_path)
            (
                binary_matrix,
                binary_sum,
                _binary_checksum,
                _binary_format,
                binary_dimension,
            ) = load_matrix(binary_path)
            json_report = verify_matrix(
                json_matrix,
                expected_dimension=json_dimension,
                expected_magic_sum=json_sum,
                expected_checksum=declared_checksum,
                require_declared_dimension=True,
                require_declared_magic_sum=True,
                require_checksum=True,
            )
            binary_report = verify_matrix(
                binary_matrix,
                expected_dimension=binary_dimension,
                expected_magic_sum=binary_sum,
                require_declared_dimension=True,
                require_declared_magic_sum=True,
            )
        except (ValueError, TypeError, json.JSONDecodeError) as exc:
            item_errors.append(f"artifact decode/verification error: {exc}")
            records.append(
                {
                    "index": record.get("index"),
                    "valid": False,
                    "jsonFileSha256": json_file_hash,
                    "binaryFileSha256": binary_file_hash,
                    "errors": item_errors,
                }
            )
            errors.extend(f"seed {record.get('index')}: {error}" for error in item_errors)
            continue
        if not json_report.valid:
            item_errors.append(f"JSON invariant verification failed: {json_report.errors}")
        if not binary_report.valid:
            item_errors.append(f"binary invariant verification failed: {binary_report.errors}")
        if json_matrix != binary_matrix or json_sum != binary_sum:
            item_errors.append("JSON and binary values/magic sum differ")
        if json_sum != manifest_magic_sum or binary_sum != manifest_magic_sum:
            item_errors.append("seed magic sum differs from manifest magicSum")
        compiler_metadata = json_payload.get("compiler") if isinstance(json_payload, dict) else None
        if (
            not isinstance(compiler_metadata, dict)
            or compiler_metadata.get("algorithm") != algorithm
            or json_payload.get("sourceFileSha256") != payload.get("sourceSha256")
        ):
            item_errors.append("seed compiler/source metadata binding mismatch")

        expected_job_seed = (
            derive_seed(base_seed, expected_index)
            if isinstance(base_seed, int) and not isinstance(base_seed, bool)
            else None
        )
        worker_records = record.get("workers")
        successful_workers: list[int] = []
        if not isinstance(worker_records, list) or worker_count is None or len(worker_records) != worker_count:
            item_errors.append("worker record count mismatch")
        elif expected_job_seed is not None:
            for worker_id, worker_record in enumerate(worker_records):
                expected_worker_seed = (
                    expected_job_seed
                    if worker_id == 0
                    else derive_seed(expected_job_seed, worker_id)
                )
                if (
                    not isinstance(worker_record, dict)
                    or worker_record.get("worker") != worker_id
                    or worker_record.get("seed") != expected_worker_seed
                    or not isinstance(worker_record.get("success"), bool)
                ):
                    item_errors.append("worker seed/status derivation mismatch")
                    break
                if worker_record["success"]:
                    successful_workers.append(worker_id)
        if successful_workers and expected_job_seed is not None:
            selected_worker = min(successful_workers)
            selected_seed = (
                expected_job_seed
                if selected_worker == 0
                else derive_seed(expected_job_seed, selected_worker)
            )
            if (
                record.get("requestedBaseSeed") != base_seed
                or record.get("compilerSeed") != selected_seed
                or not isinstance(compiler_metadata, dict)
                or compiler_metadata.get("randomSeed") != selected_seed
            ):
                item_errors.append("record/compiler selected seed binding mismatch")
        else:
            item_errors.append("worker records contain no successful worker")

        if source_matrix is not None and isinstance(json_payload, dict) and isinstance(manifest_magic_sum, int):
            item_errors.extend(
                verify_route_a_witness(source_matrix, json_payload, manifest_magic_sum)
            )
        if json_report.canonical_checksum != files.get("canonicalChecksum"):
            item_errors.append("manifest canonical checksum mismatch")
        verification_record = record.get("verification")
        if not isinstance(verification_record, dict):
            item_errors.append("verification record must be an object")
        else:
            if verification_record.get("jsonValid") is not True:
                item_errors.append("verification record does not mark JSON valid")
            if verification_record.get("binaryValid") is not True:
                item_errors.append("verification record does not mark binary valid")
            if (
                verification_record.get("canonicalChecksum")
                != json_report.canonical_checksum
            ):
                item_errors.append("verification record canonical checksum mismatch")
            if binary_file_hash != verification_record.get("binaryFileSha256"):
                item_errors.append("verification record binary SHA-256 mismatch")
        if json_report.canonical_checksum:
            canonical_seen.add(json_report.canonical_checksum)

        records.append(
            {
                "index": record.get("index"),
                "valid": not item_errors,
                "jsonFileSha256": json_file_hash,
                "binaryFileSha256": binary_file_hash,
                "canonicalChecksum": json_report.canonical_checksum,
                "errors": item_errors,
            }
        )
        errors.extend(f"seed {record.get('index')}: {error}" for error in item_errors)

    if len(canonical_seen) != len(records):
        errors.append("seed canonical checksums are not globally distinct")
    report = {
        "format": "prime-magic-manifest-verification/v1",
        "valid": not errors,
        "seedCount": len(records),
        "distinctCanonicalChecksums": len(canonical_seen),
        "sourceSha256Checked": args.source is not None,
        "configurationSha256": configuration_hash,
        "records": records,
        "errors": errors,
    }
    rendered = json.dumps(report, indent=2, sort_keys=True)
    print(rendered)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8", newline="\n")
    return 0 if report["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
