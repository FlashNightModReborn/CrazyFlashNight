#!/usr/bin/env python3
"""Independent verifier for prime (semi-)magic squares.

This module intentionally does not import the compiler.  Its primality,
serialization, and invariant checks are a separate implementation so that a
compiler defect cannot silently validate its own output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence


JS_MAX_SAFE_INTEGER = (1 << 53) - 1
U64_LIMIT = 1 << 64
BINARY_MAGIC = b"PM19"
BINARY_VERSION = 1
BINARY_HEADER = struct.Struct("<4sHHQ")


@dataclass(frozen=True)
class ValidationReport:
    valid: bool
    complete_magic: bool
    dimension: int
    declared_dimension: Any
    dimension_matches_declaration: bool
    element_count: int
    integer_validity: bool
    primality: bool
    global_uniqueness: bool
    row_sums_equal: bool
    column_sums_equal: bool
    row_column_sum_match: bool
    main_diagonal_matches: bool
    secondary_diagonal_matches: bool
    magic_sum: int | None
    main_diagonal_sum: int | None
    secondary_diagonal_sum: int | None
    declared_magic_sum: Any
    magic_sum_declaration_valid: bool
    expected_magic_sum_matches: bool
    min_value: int | None
    max_value: int | None
    safe_integer_range: bool
    canonical_checksum: str | None
    declared_checksum: Any
    serialized_checksum_matches: bool | None
    errors: tuple[str, ...]


def is_prime_u64(value: int) -> bool:
    """Deterministic Miller-Rabin primality test for 0 <= value < 2**64.

    The seven bases below are proven sufficient over the unsigned 64-bit
    interval.  Small-prime division also handles trivial composites and makes
    the witness loop cheaper for the seed's roughly 10-million-sized values.
    """

    if not isinstance(value, int) or isinstance(value, bool):
        return False
    if value < 2:
        return False
    if value >= U64_LIMIT:
        raise ValueError("deterministic Miller-Rabin range is value < 2**64")

    small_primes = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37)
    for prime in small_primes:
        if value == prime:
            return True
        if value % prime == 0:
            return False

    odd_part = value - 1
    power_of_two = 0
    while odd_part & 1 == 0:
        power_of_two += 1
        odd_part >>= 1

    for base in (2, 325, 9_375, 28_178, 450_775, 9_780_504, 1_795_265_022):
        if base % value == 0:
            continue
        witness = pow(base, odd_part, value)
        if witness in (1, value - 1):
            continue
        for _ in range(power_of_two - 1):
            witness = (witness * witness) % value
            if witness == value - 1:
                break
        else:
            return False
    return True


def _canonical_bytes(matrix: Sequence[Sequence[int]], magic_sum: int) -> bytes:
    size = len(matrix)
    payload = {
        "magicSum": magic_sum,
        "size": size,
        "values": [value for row in matrix for value in row],
    }
    return json.dumps(
        payload,
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("ascii")


def canonical_checksum(matrix: Sequence[Sequence[int]], magic_sum: int) -> str:
    return hashlib.sha256(_canonical_bytes(matrix, magic_sum)).hexdigest()


def encode_binary(matrix: Sequence[Sequence[int]], magic_sum: int) -> bytes:
    if isinstance(matrix, (str, bytes, bytearray)) or not isinstance(matrix, Sequence):
        raise ValueError("matrix must be a non-empty square sequence")
    size = len(matrix)
    if not 0 < size <= 0xFFFF:
        raise ValueError("binary format supports 1 <= size <= 65535")
    if any(
        isinstance(row, (str, bytes, bytearray))
        or not isinstance(row, Sequence)
        or len(row) != size
        for row in matrix
    ):
        raise ValueError(f"matrix must have square shape {size}x{size}")
    values = [value for row in matrix for value in row]
    if not isinstance(magic_sum, int) or isinstance(magic_sum, bool):
        raise ValueError("binary format requires a strict integer magic sum")
    if not 0 <= magic_sum < U64_LIMIT:
        raise ValueError("binary format requires an unsigned 64-bit magic sum")
    if any(
        not isinstance(value, int)
        or isinstance(value, bool)
        or not 0 <= value <= 0xFFFF_FFFF
        for value in values
    ):
        raise ValueError("binary format stores elements as unsigned 32-bit integers")
    return BINARY_HEADER.pack(BINARY_MAGIC, BINARY_VERSION, size, magic_sum) + struct.pack(
        f"<{len(values)}I", *values
    )


def decode_binary(data: bytes) -> tuple[list[list[int]], int]:
    if len(data) < BINARY_HEADER.size:
        raise ValueError("truncated PM19 header")
    magic, version, size, magic_sum = BINARY_HEADER.unpack_from(data)
    if magic != BINARY_MAGIC:
        raise ValueError("invalid PM19 binary magic")
    if version != BINARY_VERSION:
        raise ValueError(f"unsupported PM19 binary version {version}")
    if size == 0:
        raise ValueError("PM19 binary order must be positive")
    count = size * size
    expected_length = BINARY_HEADER.size + count * 4
    if len(data) != expected_length:
        raise ValueError(
            f"binary length {len(data)} does not match expected {expected_length}"
        )
    flat = list(struct.unpack_from(f"<{count}I", data, BINARY_HEADER.size))
    return [flat[offset : offset + size] for offset in range(0, count, size)], magic_sum


def verify_matrix(
    matrix: Any,
    *,
    expected_dimension: Any = None,
    expected_magic_sum: Any = None,
    expected_checksum: str | None = None,
    require_declared_dimension: bool = False,
    require_declared_magic_sum: bool = False,
    require_checksum: bool = False,
    require_diagonals: bool = True,
) -> ValidationReport:
    errors: list[str] = []
    if not isinstance(matrix, list) or not matrix:
        return ValidationReport(
            valid=False,
            complete_magic=False,
            dimension=0,
            declared_dimension=expected_dimension,
            dimension_matches_declaration=False,
            element_count=0,
            integer_validity=False,
            primality=False,
            global_uniqueness=False,
            row_sums_equal=False,
            column_sums_equal=False,
            row_column_sum_match=False,
            main_diagonal_matches=False,
            secondary_diagonal_matches=False,
            magic_sum=None,
            main_diagonal_sum=None,
            secondary_diagonal_sum=None,
            declared_magic_sum=expected_magic_sum,
            magic_sum_declaration_valid=False,
            expected_magic_sum_matches=False,
            min_value=None,
            max_value=None,
            safe_integer_range=False,
            canonical_checksum=None,
            declared_checksum=expected_checksum,
            serialized_checksum_matches=None,
            errors=("matrix must be a non-empty list of rows",),
        )

    size = len(matrix)
    dimension_is_strict_integer = isinstance(expected_dimension, int) and not isinstance(
        expected_dimension, bool
    )
    if expected_dimension is None:
        dimension_matches_declaration = not require_declared_dimension
        if require_declared_dimension:
            errors.append("a declared dimension is required but was not provided")
    else:
        dimension_matches_declaration = bool(
            dimension_is_strict_integer and expected_dimension == size
        )
        if not dimension_is_strict_integer:
            errors.append("declared dimension is not a strict integer")
        elif expected_dimension != size:
            errors.append(
                f"matrix dimension {size} != declared dimension {expected_dimension}"
            )
    magic_sum_is_strict_integer = isinstance(expected_magic_sum, int) and not isinstance(
        expected_magic_sum, bool
    )
    if expected_magic_sum is None:
        magic_sum_declaration_valid = not require_declared_magic_sum
        if require_declared_magic_sum:
            errors.append("a declared magic sum is required but was not provided")
    else:
        magic_sum_declaration_valid = magic_sum_is_strict_integer
        if not magic_sum_is_strict_integer:
            errors.append("declared magic sum is not a strict integer")
    rows_are_lists = all(isinstance(row, list) for row in matrix)
    shape_valid = rows_are_lists and all(len(row) == size for row in matrix)
    if not shape_valid:
        errors.append(f"matrix shape is not {size}x{size}")

    flat = [value for row in matrix if isinstance(row, list) for value in row]
    element_count = len(flat)
    if element_count != size * size:
        errors.append(f"element count {element_count} != {size * size}")

    integer_validity = all(isinstance(value, int) and not isinstance(value, bool) for value in flat)
    if not integer_validity:
        errors.append("one or more values are not strict integers")

    min_value = min(flat) if flat and integer_validity else None
    max_value = max(flat) if flat and integer_validity else None
    safe_integer_range = bool(integer_validity and flat) and all(
        -JS_MAX_SAFE_INTEGER <= value <= JS_MAX_SAFE_INTEGER for value in flat
    )
    if integer_validity and shape_valid:
        all_sums = [sum(row) for row in matrix]
        all_sums.extend(sum(matrix[i][j] for i in range(size)) for j in range(size))
        all_sums.append(sum(matrix[index][index] for index in range(size)))
        all_sums.append(
            sum(matrix[index][size - 1 - index] for index in range(size))
        )
        safe_integer_range = safe_integer_range and all(
            -JS_MAX_SAFE_INTEGER <= value <= JS_MAX_SAFE_INTEGER for value in all_sums
        )
    if not safe_integer_range:
        errors.append("an element or line sum is outside JavaScript's safe integer range")

    global_uniqueness = integer_validity and len(set(flat)) == element_count
    if not global_uniqueness:
        errors.append("values are not globally unique")

    primality = False
    if integer_validity:
        try:
            primality = all(is_prime_u64(value) for value in flat)
        except ValueError as exc:
            errors.append(str(exc))
        if not primality and not any("Miller-Rabin" in error for error in errors):
            errors.append("one or more values are composite")

    row_sums_equal = column_sums_equal = row_column_sum_match = False
    magic_sum: int | None = None
    main_sum: int | None = None
    secondary_sum: int | None = None
    main_matches = secondary_matches = False
    checksum: str | None = None
    expected_sum_matches = expected_magic_sum is None and not require_declared_magic_sum
    checksum_matches: bool | None = False if require_checksum and expected_checksum is None else None
    if require_checksum and expected_checksum is None:
        errors.append("a canonical checksum is required but was not declared")
    if expected_checksum is not None and not isinstance(expected_checksum, str):
        checksum_matches = False
        errors.append("declared canonical checksum is not a string")

    if shape_valid and integer_validity:
        row_sums = [sum(row) for row in matrix]
        column_sums = [sum(matrix[i][j] for i in range(size)) for j in range(size)]
        row_sums_equal = len(set(row_sums)) == 1
        column_sums_equal = len(set(column_sums)) == 1
        row_column_sum_match = row_sums_equal and column_sums_equal and row_sums[0] == column_sums[0]
        magic_sum = row_sums[0] if row_column_sum_match else None
        if not row_sums_equal:
            errors.append("row sums differ")
        if not column_sums_equal:
            errors.append("column sums differ")
        if row_sums_equal and column_sums_equal and not row_column_sum_match:
            errors.append("common row and column sums differ")
        expected_sum_matches = bool(
            (expected_magic_sum is None and not require_declared_magic_sum)
            or (magic_sum_is_strict_integer and magic_sum == expected_magic_sum)
        )
        if not expected_sum_matches:
            errors.append(f"computed magic sum {magic_sum} != expected {expected_magic_sum}")

        main_sum = sum(matrix[i][i] for i in range(size))
        secondary_sum = sum(matrix[i][size - 1 - i] for i in range(size))
        main_matches = magic_sum is not None and main_sum == magic_sum
        secondary_matches = magic_sum is not None and secondary_sum == magic_sum
        if require_diagonals and not main_matches:
            errors.append(f"main diagonal sum {main_sum} != magic sum {magic_sum}")
        if require_diagonals and not secondary_matches:
            errors.append(f"secondary diagonal sum {secondary_sum} != magic sum {magic_sum}")
        if magic_sum is not None:
            checksum = canonical_checksum(matrix, magic_sum)
            if isinstance(expected_checksum, str):
                normalized = expected_checksum.removeprefix("sha256:").lower()
                checksum_matches = normalized == checksum
                if not checksum_matches:
                    errors.append(
                        f"declared canonical checksum {normalized} != computed {checksum}"
                    )

    complete_magic = bool(
        shape_valid
        and integer_validity
        and primality
        and global_uniqueness
        and row_column_sum_match
        and main_matches
        and secondary_matches
        and safe_integer_range
        and dimension_matches_declaration
        and magic_sum_declaration_valid
        and expected_sum_matches
        and (checksum_matches is not False)
    )
    semimagic_valid = bool(
        shape_valid
        and integer_validity
        and primality
        and global_uniqueness
        and row_column_sum_match
        and safe_integer_range
        and dimension_matches_declaration
        and magic_sum_declaration_valid
        and expected_sum_matches
        and (checksum_matches is not False)
    )
    valid = complete_magic if require_diagonals else semimagic_valid
    return ValidationReport(
        valid=valid,
        complete_magic=complete_magic,
        dimension=size,
        declared_dimension=expected_dimension,
        dimension_matches_declaration=dimension_matches_declaration,
        element_count=element_count,
        integer_validity=integer_validity,
        primality=primality,
        global_uniqueness=global_uniqueness,
        row_sums_equal=row_sums_equal,
        column_sums_equal=column_sums_equal,
        row_column_sum_match=row_column_sum_match,
        main_diagonal_matches=main_matches,
        secondary_diagonal_matches=secondary_matches,
        magic_sum=magic_sum,
        main_diagonal_sum=main_sum,
        secondary_diagonal_sum=secondary_sum,
        declared_magic_sum=expected_magic_sum,
        magic_sum_declaration_valid=magic_sum_declaration_valid,
        expected_magic_sum_matches=expected_sum_matches,
        min_value=min_value,
        max_value=max_value,
        safe_integer_range=safe_integer_range,
        canonical_checksum=checksum,
        declared_checksum=expected_checksum,
        serialized_checksum_matches=checksum_matches,
        errors=tuple(errors),
    )


def load_matrix(
    path: Path,
) -> tuple[list[list[int]], Any, str | None, str | None, Any]:
    suffix = path.suffix.lower()
    if suffix == ".bin":
        matrix, magic_sum = decode_binary(path.read_bytes())
        return matrix, magic_sum, None, "prime-magic-binary/v1", len(matrix)
    if suffix == ".json":
        payload = json.loads(path.read_text(encoding="utf-8"))
        if "matrix" in payload:
            matrix = payload["matrix"]
        elif "values" in payload and "size" in payload:
            size = payload["size"]
            if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
                raise ValueError("JSON size must be a positive strict integer")
            flat = payload["values"]
            if not isinstance(flat, list):
                raise ValueError("JSON values must be a list")
            matrix = [flat[offset : offset + size] for offset in range(0, len(flat), size)]
        else:
            raise ValueError("JSON must contain matrix or size+values")
        return (
            matrix,
            payload.get("magicSum", payload.get("line_sum")),
            payload.get("checksum"),
            payload.get("format"),
            payload.get("size", payload.get("order")),
        )
    raise ValueError(f"unsupported input format: {suffix}")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--semimagic", action="store_true", help="do not require diagonal equality")
    parser.add_argument(
        "--require-checksum",
        action="store_true",
        help="reject JSON without a declared canonical SHA-256",
    )
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    try:
        (
            matrix,
            declared_sum,
            declared_checksum,
            declared_format,
            declared_dimension,
        ) = load_matrix(args.input)
    except (OSError, ValueError, TypeError, json.JSONDecodeError, struct.error) as exc:
        payload = asdict(verify_matrix(None))
        payload["errors"] = [f"input decode error: {exc}"]
        payload["declared_format"] = None
        payload["format_supported"] = False
        payload["input_file_sha256"] = file_sha256(args.input) if args.input.is_file() else None
        rendered = json.dumps(payload, indent=2, sort_keys=True)
        print(rendered)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(rendered + "\n", encoding="utf-8")
        return 1
    seed_schema = isinstance(declared_format, str) and declared_format.startswith(
        "prime-magic-seed/"
    )
    format_supported = declared_format in (
        None,
        "prime-magic-seed/v1",
        "prime-magic-binary/v1",
    )
    checksum_required = args.require_checksum or seed_schema
    report = verify_matrix(
        matrix,
        expected_dimension=declared_dimension,
        expected_magic_sum=declared_sum,
        expected_checksum=declared_checksum,
        require_declared_dimension=seed_schema,
        require_declared_magic_sum=seed_schema,
        require_checksum=checksum_required,
        require_diagonals=not args.semimagic,
    )
    payload = asdict(report)
    payload["declared_format"] = declared_format
    payload["format_supported"] = format_supported
    if not format_supported:
        payload["valid"] = False
        payload["errors"] = [
            *payload["errors"],
            f"unsupported or non-string declared format {declared_format!r}",
        ]
    payload["input_file_sha256"] = file_sha256(args.input)
    rendered = json.dumps(payload, indent=2, sort_keys=True)
    print(rendered)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered + "\n", encoding="utf-8")
    return 0 if payload["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
