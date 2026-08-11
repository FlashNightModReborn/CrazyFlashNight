#!/usr/bin/env python3
"""Promote human-accepted Team portraits into an identity-first Web asset pack.

The generated SVG keeps the accepted crop as a viewBox over the original FFDec
vector frame.  The exact accepted 512 px PNG is retained as a fail-soft fallback
and as pixel provenance.  Presentation (frame, atmosphere and color theme) stays
in Web code rather than in this generated identity manifest.
"""

from __future__ import annotations

import argparse
import base64
import copy
import datetime as dt
import hashlib
import io
import json
import lzma
import math
import os
import re
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
WEB_ROOT = ROOT / "launcher" / "web"
DEFAULT_INVENTORY = (
    PILOT_ROOT
    / "campaign-inventory-r155-xfl-embedded-rescue5-20260808T032000Z"
    / "portrait-inventory.json"
)
DEFAULT_CAMPAIGN = (
    PILOT_ROOT
    / "campaign-shard-r164-xfl-rescue5-feedback186-20260808T045000Z"
    / "candidate-manifest.json"
)
DEFAULT_REPRESENTATIVE_CLOSURE = (
    PILOT_ROOT / "representative-closure-r13-20260806T031054Z" / "representative-closure.json"
)
DEFAULT_OUTPUT = WEB_ROOT / "assets" / "enemy-portraits"
EVIDENCE_SUBJECT_ROOT = WEB_ROOT / "assets" / "enemy-portraits" / "subjects"
EVIDENCE_PACK = ROOT / "tools" / "portrait-pilot" / "evidence" / "enemy-portrait-evidence-pack-v1.json"
EVIDENCE_RAW_SUPPLEMENT = EVIDENCE_PACK.with_name("enemy-portrait-evidence-raw-supplement-v1.json")
EVIDENCE_PACK_PRODUCER = ROOT / "tools" / "portrait-pilot" / "build-enemy-portrait-evidence-pack-v1.py"
DEFAULT_TEAM_GAP_BATCH = (
    PILOT_ROOT / "team-gap-render-r174-final3-large-20260808T071000Z"
)
REPRESENTATIVE_DIRECT_REPORTS = (
    PILOT_ROOT / "p3-feature-hires-r7-20260806T090000Z" / "render-report-v2.json",
    PILOT_ROOT / "p3-selective-r8-fast6-20260806T014119Z" / "render-report.json",
    PILOT_ROOT / "p3-selective-r10-fast6-20260806T021124Z" / "render-report.json",
)
ALIAS_RECEIPT = (
    PILOT_ROOT
    / "campaign-alias-r43-mimic-to-ark-demoness-20260806T104741Z"
    / "portrait-alias-receipt.json"
)
UNIMPLEMENTED_REF = "敌人-不知火舞"
TEAM_GAP_REFS = {"敌人-Lady", "敌人-巨臂僵尸", "敌人-方舟爪豪"}
JK_REF = "敌人-武装JK"
EXPECTED_FLIPPED_VARIANTS = {
    "敌人-终结者T800::default",
    "敌人-重型改造僵尸::default",
    "敌人-铠甲勇士战马形态::default",
    "敌人-黑铁会改造人::default",
    "敌人-黑白无常::default",
    "敌人-暴走重型改造僵尸::default",
    "敌人-圣诞白忍::default",
    "敌人-诺艾尔::default",
}
ORIENTATION_AUDIT_TEAM_TOGGLES = {
    "敌人-忍者兵::default",
    "敌人-忍者BOSS::default",
}
ORIENTATION_SOURCES = {
    "direct_model_orientation",
    "explicit_correction_orientation",
    "explicit_human_post_crop_flip",
    "selected_model_orientation_inherited_after_human_crop",
    "legacy_orientation_unassessed",
    "production_visual_audit_model_verified_keep",
    "explicit_production_orientation_human_audit",
}
SVG_RASTER_HEAVY_MIN_BYTES = 512 * 1024
SVG_RASTER_HEAVY_RATIO = 2
SVG_RASTER_HEAVY_IMAGE_COUNT = 4

_EVIDENCE_STATE: dict[str, Any] | None = None
_MATERIALIZED_ARTIFACTS: dict[Path, dict[str, Any]] = {}


class PromotionError(RuntimeError):
    pass


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def load_json(path: Path, label: str) -> dict[str, Any]:
    path = resolve_input_path(path, label)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PromotionError(f"{label}不可读：{path}: {error}") from error
    if not isinstance(value, dict):
        raise PromotionError(f"{label}顶层必须是对象：{path}")
    return value


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def repo_rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError as error:
        raise PromotionError(f"路径越出仓库：{path}") from error


def stable_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _load_evidence_state() -> dict[str, Any]:
    global _EVIDENCE_STATE
    if _EVIDENCE_STATE is not None:
        return _EVIDENCE_STATE
    if not EVIDENCE_PACK.is_file():
        raise PromotionError(f"敌人头像 immutable evidence pack 缺失：{EVIDENCE_PACK}")
    try:
        pack = json.loads(EVIDENCE_PACK.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PromotionError(f"敌人头像 immutable evidence pack 不可读：{error}") from error
    if (
        not isinstance(pack, dict)
        or pack.get("schema") != "cf7.enemy-portrait-evidence-pack.v1"
        or pack.get("status") != "immutable_lossless_evidence"
    ):
        raise PromotionError("敌人头像 immutable evidence pack schema/status 非法")
    clone = copy.deepcopy(pack)
    expected_pack_digest = clone.pop("packDigest", None)
    if not isinstance(expected_pack_digest, str) or sha256_bytes(stable_bytes(clone)) != expected_pack_digest:
        raise PromotionError("敌人头像 immutable evidence pack digest 漂移")

    def verify_committed_artifact(record: Any, expected_path: Path, label: str) -> None:
        expected_relative = expected_path.resolve().relative_to(ROOT).as_posix()
        if (
            not isinstance(record, dict)
            or set(record) != {"path", "bytes", "sha256"}
            or record.get("path") != expected_relative
            or not isinstance(record.get("bytes"), int)
            or not isinstance(record.get("sha256"), str)
            or not expected_path.is_file()
            or expected_path.stat().st_size != record["bytes"]
            or sha256_file(expected_path) != record["sha256"]
        ):
            raise PromotionError(f"敌人头像 evidence {label} artifact 漂移")

    verify_committed_artifact(pack.get("producer"), EVIDENCE_PACK_PRODUCER, "producer")
    verify_committed_artifact(
        pack.get("supplementalRawArchive"), EVIDENCE_RAW_SUPPLEMENT, "raw supplement"
    )

    records_by_path: dict[str, dict[str, Any]] = {}
    for record in pack.get("records", []):
        if (
            not isinstance(record, dict)
            or not isinstance(record.get("path"), str)
            or not isinstance(record.get("bytes"), int)
            or not isinstance(record.get("sha256"), str)
        ):
            raise PromotionError("敌人头像 evidence artifact record 非法")
        resolved = (ROOT / record["path"]).resolve()
        try:
            resolved.relative_to(ROOT)
        except ValueError as error:
            raise PromotionError(f"敌人头像 evidence artifact 路径越界：{record['path']}") from error
        if record["path"] in records_by_path:
            raise PromotionError(f"敌人头像 evidence artifact 路径重复：{record['path']}")
        records_by_path[record["path"]] = copy.deepcopy(record)

    def decode_raw_archive(archive: Any, label: str) -> dict[str, bytes]:
        if not isinstance(archive, dict) or archive.get("encoding") != "sha256-base64-json+xz+base64":
            raise PromotionError(f"敌人头像 evidence {label} encoding 非法")
        try:
            compressed = base64.b64decode("".join(archive.get("dataChunks", [])), validate=True)
        except (TypeError, ValueError) as error:
            raise PromotionError(f"敌人头像 evidence {label} base64 非法") from error
        if (
            len(compressed) != archive.get("compressedBytes")
            or sha256_bytes(compressed) != archive.get("compressedSha256")
        ):
            raise PromotionError(f"敌人头像 evidence {label} 压缩字节漂移")
        try:
            archive_bytes = lzma.decompress(compressed)
            encoded_blobs = json.loads(archive_bytes.decode("utf-8"))
        except (lzma.LZMAError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise PromotionError(f"敌人头像 evidence {label} 解压失败：{error}") from error
        if len(archive_bytes) != archive.get("uncompressedBytes") or not isinstance(encoded_blobs, dict):
            raise PromotionError(f"敌人头像 evidence {label} 长度/结构漂移")
        result: dict[str, bytes] = {}
        for digest, encoded in encoded_blobs.items():
            try:
                blob = base64.b64decode(encoded, validate=True)
            except (TypeError, ValueError) as error:
                raise PromotionError(f"敌人头像 evidence blob base64 非法：{digest}") from error
            if sha256_bytes(blob) != digest:
                raise PromotionError(f"敌人头像 evidence blob 原始 sha256 漂移：{digest}")
            result[digest] = blob
        return result

    primary_raw_blobs = decode_raw_archive(pack.get("rawArchive"), "raw archive")
    try:
        supplemental_archive = json.loads(EVIDENCE_RAW_SUPPLEMENT.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PromotionError(f"敌人头像 evidence raw supplement 不可读：{error}") from error
    supplemental_clone = copy.deepcopy(supplemental_archive)
    supplemental_digest = supplemental_clone.pop("archiveDigest", None)
    if (
        supplemental_archive.get("schema") != "cf7.enemy-portrait-evidence-raw-archive.v1"
        or supplemental_archive.get("status") != "immutable_lossless_evidence"
        or not isinstance(supplemental_digest, str)
        or sha256_bytes(stable_bytes(supplemental_clone)) != supplemental_digest
    ):
        raise PromotionError("敌人头像 evidence raw supplement schema/digest 漂移")
    supplemental_raw_blobs = decode_raw_archive(
        supplemental_archive.get("archive"), "supplemental raw archive"
    )
    duplicate_archive_digests = set(primary_raw_blobs) & set(supplemental_raw_blobs)
    if duplicate_archive_digests:
        raise PromotionError(
            f"敌人头像 evidence raw archives 重复 digest：{sorted(duplicate_archive_digests)}"
        )
    raw_blobs = {**primary_raw_blobs, **supplemental_raw_blobs}

    inline_artifacts = pack.get("inlineArtifacts", {})
    if not isinstance(inline_artifacts, dict):
        raise PromotionError("敌人头像 evidence inlineArtifacts 非法")
    inline_blobs: dict[str, bytes] = {}
    for digest, descriptor in inline_artifacts.items():
        if (
            not isinstance(descriptor, dict)
            or descriptor.get("encoding") != "base64"
            or set(descriptor) != {"encoding", "bytes", "data"}
        ):
            raise PromotionError(f"敌人头像 evidence inline artifact descriptor 非法：{digest}")
        try:
            blob = base64.b64decode(descriptor["data"], validate=True)
        except (TypeError, ValueError) as error:
            raise PromotionError(f"敌人头像 evidence inline artifact base64 非法：{digest}") from error
        if len(blob) != descriptor.get("bytes") or sha256_bytes(blob) != digest:
            raise PromotionError(f"敌人头像 evidence inline artifact 原始字节漂移：{digest}")
        inline_blobs[digest] = blob

    binary_reconstructions = pack.get("binaryReconstructions", {})
    if not isinstance(binary_reconstructions, dict):
        raise PromotionError("敌人头像 evidence binaryReconstructions 非法")
    binary_blobs: dict[str, bytes] = {}
    for digest, descriptor in binary_reconstructions.items():
        basis = descriptor.get("basis") if isinstance(descriptor, dict) else None
        if (
            not isinstance(descriptor, dict)
            or descriptor.get("encoding") != "identity-committed-file-v1"
            or set(descriptor) != {"encoding", "basis"}
            or not isinstance(basis, dict)
            or set(basis) != {"path", "bytes", "sha256"}
            or not isinstance(basis.get("path"), str)
            or not isinstance(basis.get("bytes"), int)
            or not isinstance(basis.get("sha256"), str)
            or basis.get("sha256") != digest
        ):
            raise PromotionError(f"敌人头像 evidence binary reconstruction descriptor 非法：{digest}")
        basis_path = (ROOT / basis["path"]).resolve()
        try:
            basis_path.relative_to(ROOT)
        except ValueError as error:
            raise PromotionError(f"敌人头像 evidence binary basis 越界：{basis.get('path')}") from error
        if (
            not basis_path.is_file()
            or basis_path.stat().st_size != basis.get("bytes")
            or sha256_file(basis_path) != basis["sha256"]
        ):
            raise PromotionError(f"敌人头像 evidence binary basis 漂移：{basis.get('path')}")
        binary_blobs[digest] = basis_path.read_bytes()

    svg_reconstructions = pack.get("svgReconstructions")
    if not isinstance(svg_reconstructions, dict):
        raise PromotionError("敌人头像 evidence SVG reconstruction 索引非法")
    preserved_subjects = pack.get("preservedSubjects")
    if not isinstance(preserved_subjects, list):
        raise PromotionError("敌人头像 evidence preservedSubjects 非法")
    expected_raw_digests = {
        record["sha256"]
        for record in records_by_path.values()
        if Path(record["path"]).suffix.lower() != ".svg"
    }
    expected_svg_digests = {
        record["sha256"]
        for record in records_by_path.values()
        if Path(record["path"]).suffix.lower() == ".svg"
    }
    actual_binary_digests = set(raw_blobs) | set(inline_blobs) | set(binary_blobs)
    duplicate_binary_digests = (
        (set(raw_blobs) & set(inline_blobs))
        | (set(raw_blobs) & set(binary_blobs))
        | (set(inline_blobs) & set(binary_blobs))
    )
    if duplicate_binary_digests or actual_binary_digests != expected_raw_digests:
        raise PromotionError(
            "敌人头像 evidence raw blob exact-set 漂移："
            f"missing={sorted(expected_raw_digests - actual_binary_digests)} "
            f"orphan={sorted(actual_binary_digests - expected_raw_digests)} "
            f"duplicate={sorted(duplicate_binary_digests)}"
        )
    if set(svg_reconstructions) != expected_svg_digests:
        raise PromotionError(
            "敌人头像 evidence SVG reconstruction exact-set 漂移："
            f"missing={sorted(expected_svg_digests - set(svg_reconstructions))} "
            f"orphan={sorted(set(svg_reconstructions) - expected_svg_digests)}"
        )
    reconstructed_svg_blobs: dict[str, bytes] = {}
    for digest, descriptor in svg_reconstructions.items():
        if (
            not isinstance(descriptor, dict)
            or descriptor.get("encoding") != "inverse-published-svg-v1"
            or descriptor.get("sha256") != digest
        ):
            raise PromotionError(f"敌人头像 evidence SVG descriptor 非法：{digest}")
        blob = _invert_published_svg(descriptor)
        if len(blob) != descriptor.get("bytes") or sha256_bytes(blob) != digest:
            raise PromotionError(f"敌人头像 evidence SVG descriptor 原始字节漂移：{digest}")
        reconstructed_svg_blobs[digest] = blob

    explicit_blobs = {
        **raw_blobs,
        **inline_blobs,
        **binary_blobs,
        **reconstructed_svg_blobs,
    }
    derived_master_paths = pack.get("derivedMasterPaths")
    if (
        not isinstance(derived_master_paths, list)
        or any(not isinstance(path, str) for path in derived_master_paths)
        or len(set(derived_master_paths)) != len(derived_master_paths)
    ):
        raise PromotionError("敌人头像 evidence derivedMasterPaths 非法或重复")
    allowed_derived_master_paths = set(derived_master_paths)
    for path_value in allowed_derived_master_paths:
        resolved = (ROOT / path_value).resolve()
        try:
            resolved.relative_to(PILOT_ROOT.resolve())
        except ValueError as error:
            raise PromotionError(f"敌人头像 evidence derived master allowlist 路径越界：{path_value}") from error
        if Path(path_value).name != "master-512.png":
            raise PromotionError(f"敌人头像 evidence derived master allowlist 文件名非法：{path_value}")
    derived_master_records: dict[str, dict[str, Any]] = {}
    derived_master_blobs: dict[str, bytes] = {}

    def collect_derived_master_records(value: Any) -> None:
        if isinstance(value, dict):
            if {"path", "bytes", "sha256"}.issubset(value):
                path_value = value.get("path")
                digest_value = value.get("sha256")
                if (
                    isinstance(path_value, str)
                    and isinstance(value.get("bytes"), int)
                    and isinstance(digest_value, str)
                    and path_value.startswith("tmp/portrait-pilot/")
                    and Path(path_value).name == "master-512.png"
                    and path_value not in records_by_path
                    and path_value in allowed_derived_master_paths
                ):
                    if re.fullmatch(r"[0-9A-F]{64}", digest_value) is None:
                        raise PromotionError(f"敌人头像 evidence derived master sha256 非法：{path_value}")
                    path = (ROOT / path_value).resolve()
                    try:
                        path.relative_to(PILOT_ROOT.resolve())
                    except ValueError as error:
                        raise PromotionError(f"敌人头像 evidence derived master 路径越界：{path_value}") from error
                    basis = DEFAULT_OUTPUT / "subjects" / f"{digest_value[:24].lower()}.png"
                    if (
                        not basis.is_file()
                        or basis.stat().st_size != value["bytes"]
                        or sha256_file(basis) != digest_value
                    ):
                        return
                    record = {
                        "path": path_value,
                        "bytes": value["bytes"],
                        "sha256": digest_value,
                    }
                    previous = derived_master_records.get(path_value)
                    if previous is not None and previous != record:
                        raise PromotionError(f"敌人头像 evidence derived master 路径碰撞：{path_value}")
                    derived_master_records[path_value] = record
                    derived_master_blobs[digest_value] = basis.read_bytes()
            for child in value.values():
                collect_derived_master_records(child)
        elif isinstance(value, list):
            for child in value:
                collect_derived_master_records(child)

    for record in records_by_path.values():
        if Path(record["path"]).suffix.lower() != ".json":
            continue
        blob = explicit_blobs.get(record["sha256"])
        if blob is None:
            raise PromotionError(f"敌人头像 evidence JSON blob 缺失：{record['path']}")
        try:
            document = json.loads(blob.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise PromotionError(f"敌人头像 evidence JSON blob 不可读：{record['path']}") from error
        collect_derived_master_records(document)

    if set(derived_master_records) != allowed_derived_master_paths:
        raise PromotionError(
            "敌人头像 evidence derived master exact-set 漂移："
            f"missing={sorted(allowed_derived_master_paths - set(derived_master_records))} "
            f"orphan={sorted(set(derived_master_records) - allowed_derived_master_paths)}"
        )

    preserved_paths: set[str] = set()
    for record in preserved_subjects:
        if (
            not isinstance(record, dict)
            or not isinstance(record.get("path"), str)
            or not isinstance(record.get("bytes"), int)
            or not isinstance(record.get("sha256"), str)
            or record.get("purpose") != "orientation-source-byte-preservation"
            or record["path"] in preserved_paths
        ):
            raise PromotionError("敌人头像 evidence preserved subject record 重复或非法")
        preserved_paths.add(record["path"])
        path = (ROOT / record["path"]).resolve()
        expected_parent = EVIDENCE_SUBJECT_ROOT.resolve()
        if (
            path.parent != expected_parent
            or path.stem.lower() != record["sha256"][:24].lower()
            or not path.is_file()
            or path.stat().st_size != record["bytes"]
            or sha256_file(path) != record["sha256"]
        ):
            raise PromotionError(f"敌人头像 evidence preserved subject 漂移：{record['path']}")

    counts = pack.get("counts")
    expected_counts = {
        "artifactPaths": len(records_by_path),
        "rawBlobs": len(raw_blobs),
        "supplementalRawBlobs": len(supplemental_raw_blobs),
        "inlineBlobs": len(inline_blobs),
        "binaryReconstructedBlobs": len(binary_blobs),
        "derivedMasterRecords": len(derived_master_records),
        "reconstructedSvgBlobs": len(svg_reconstructions),
        "preservedSubjects": len(preserved_subjects),
    }
    if counts != expected_counts:
        raise PromotionError(f"敌人头像 evidence pack counts 漂移：expected={expected_counts} actual={counts}")
    for record in records_by_path.values():
        digest = record["sha256"]
        blob = raw_blobs.get(digest)
        if blob is None:
            blob = inline_blobs.get(digest)
        if blob is None:
            blob = binary_blobs.get(digest)
        if blob is None:
            blob = reconstructed_svg_blobs[digest]
        if len(blob) != record["bytes"] or sha256_bytes(blob) != digest:
            raise PromotionError(f"敌人头像 evidence pack artifact 未逐条闭合：{record['path']}")
    _EVIDENCE_STATE = {
        "pack": pack,
        "packDigest": expected_pack_digest,
        "recordsByPath": records_by_path,
        "allRecordsByPath": {**records_by_path, **derived_master_records},
        "rawBlobs": {**raw_blobs, **inline_blobs, **binary_blobs, **derived_master_blobs},
        "inlineBlobs": inline_blobs,
        "binaryBlobs": binary_blobs,
        "derivedMasterRecords": derived_master_records,
        "derivedMasterPaths": list(derived_master_paths),
        "svgReconstructions": svg_reconstructions,
        "reconstructedSvgBlobs": reconstructed_svg_blobs,
        "preservedSubjects": copy.deepcopy(preserved_subjects),
    }
    return _EVIDENCE_STATE


def _invert_published_svg(descriptor: dict[str, Any]) -> bytes:
    basis = descriptor.get("basis")
    if not isinstance(basis, dict) or not isinstance(basis.get("path"), str):
        raise PromotionError("敌人头像 evidence SVG basis 缺失")
    basis_path = (ROOT / basis["path"]).resolve()
    try:
        basis_path.relative_to(ROOT)
    except ValueError as error:
        raise PromotionError(f"敌人头像 evidence SVG basis 越界：{basis_path}") from error
    if (
        not basis_path.is_file()
        or basis_path.stat().st_size != basis.get("bytes")
        or sha256_file(basis_path) != basis.get("sha256")
    ):
        raise PromotionError(f"敌人头像 evidence SVG basis 漂移：{basis.get('path')}")
    try:
        opening = base64.b64decode(descriptor.get("sourceOpeningBase64"), validate=True).decode("utf-8")
        text = basis_path.read_text(encoding="utf-8")
    except (TypeError, ValueError, UnicodeDecodeError, OSError) as error:
        raise PromotionError(f"敌人头像 evidence SVG reconstruction 数据非法：{error}") from error
    match = re.search(r"<svg\b[^>]*>", text, flags=re.IGNORECASE | re.DOTALL)
    if match is None:
        raise PromotionError(f"敌人头像 evidence SVG basis 缺根元素：{basis.get('path')}")
    if descriptor.get("basisFlipX") is True:
        flip_open = re.match(
            r'\n  <g data-cf7-portrait-flip="x" transform="[^"]+">',
            text[match.end() :],
        )
        if flip_open is None:
            raise PromotionError(f"敌人头像 evidence SVG basis 缺 flip 开标签：{basis.get('path')}")
        text = text[: match.end()] + text[match.end() + flip_open.end() :]
        closing = text.lower().rfind("</svg>")
        marker = "\n  </g>\n"
        close_group = text.rfind(marker, 0, closing + 1)
        if closing < 0 or close_group < 0:
            raise PromotionError(f"敌人头像 evidence SVG basis 缺 flip 闭标签：{basis.get('path')}")
        text = text[:close_group] + text[close_group + len(marker) :]
        match = re.search(r"<svg\b[^>]*>", text, flags=re.IGNORECASE | re.DOTALL)
        if match is None:
            raise PromotionError(f"敌人头像 evidence SVG basis 逆变换后缺根元素：{basis.get('path')}")
    text = text[: match.start()] + opening + text[match.end() :]
    if descriptor.get("sourceNewlines") == "crlf":
        text = text.replace("\n", "\r\n")
    elif descriptor.get("sourceNewlines") != "lf":
        raise PromotionError("敌人头像 evidence SVG newline encoding 非法")
    return text.encode("utf-8")


def _evidence_bytes(record: dict[str, Any]) -> bytes | None:
    state = _load_evidence_state()
    frozen = state["allRecordsByPath"].get(record.get("path"))
    if frozen != record:
        return None
    digest = record["sha256"]
    blob = state["rawBlobs"].get(digest)
    if blob is None:
        descriptor = state["svgReconstructions"].get(digest)
        if not isinstance(descriptor, dict) or descriptor.get("encoding") != "inverse-published-svg-v1":
            raise PromotionError(f"敌人头像 evidence 未覆盖 artifact：{record['path']}")
        blob = state["reconstructedSvgBlobs"][digest]
    if len(blob) != record["bytes"] or sha256_bytes(blob) != digest:
        raise PromotionError(f"敌人头像 evidence artifact 原始字节漂移：{record['path']}")
    return blob


def _materialize_evidence(record: dict[str, Any], blob: bytes) -> Path:
    state = _load_evidence_state()
    cache_root = (
        Path(tempfile.gettempdir())
        / "cf7-portrait-evidence-v1"
        / state["packDigest"][:16].lower()
    )
    cache_root.mkdir(parents=True, exist_ok=True)
    suffix = Path(record["path"]).suffix.lower()
    path_key = sha256_bytes(record["path"].encode("utf-8"))[:16].lower()
    target = cache_root / f"{record['sha256'][:24].lower()}-{path_key}{suffix}"
    if target.is_file() and target.stat().st_size == len(blob) and sha256_file(target) == record["sha256"]:
        _MATERIALIZED_ARTIFACTS[target.resolve()] = copy.deepcopy(record)
        return target
    with tempfile.NamedTemporaryFile(dir=cache_root, prefix="artifact-", suffix=".tmp", delete=False) as stream:
        stream.write(blob)
        temporary = Path(stream.name)
    try:
        os.replace(temporary, target)
    finally:
        if temporary.exists():
            temporary.unlink()
    _MATERIALIZED_ARTIFACTS[target.resolve()] = copy.deepcopy(record)
    return target


def resolve_input_path(path: Path, label: str) -> Path:
    resolved = path.resolve()
    materialized = _MATERIALIZED_ARTIFACTS.get(resolved)
    if materialized is not None:
        if (
            resolved.is_file()
            and resolved.stat().st_size == materialized["bytes"]
            and sha256_file(resolved) == materialized["sha256"]
        ):
            return resolved
        raise PromotionError(f"{label}materialized evidence 漂移：{resolved}")
    try:
        relative = resolved.relative_to(ROOT).as_posix()
    except ValueError as error:
        raise PromotionError(f"{label}路径越出仓库：{resolved}") from error
    frozen = _load_evidence_state()["allRecordsByPath"].get(relative)
    if isinstance(frozen, dict):
        if (
            os.environ.get("CF7_PORTRAIT_EVIDENCE_ONLY") != "1"
            and
            resolved.is_file()
            and resolved.stat().st_size == frozen["bytes"]
            and sha256_file(resolved) == frozen["sha256"]
        ):
            return resolved
        blob = _evidence_bytes(frozen)
        if blob is None:
            raise PromotionError(f"{label}immutable evidence record 不匹配：{relative}")
        return _materialize_evidence(frozen, blob)
    if os.environ.get("CF7_PORTRAIT_EVIDENCE_ONLY") == "1" and resolved.is_relative_to(PILOT_ROOT.resolve()):
        raise PromotionError(f"{label}ignored tmp artifact 未进入 immutable evidence pack：{relative}")
    if resolved.is_file():
        return resolved
    raise PromotionError(f"{label}不存在且未被 immutable evidence 覆盖：{resolved}")


def pilot_stable_bytes(value: Any) -> bytes:
    """Match prepare_pilot.py digest normalization for render reports."""

    def normalize(entry: Any) -> Any:
        if isinstance(entry, dict):
            return {key: normalize(child) for key, child in entry.items()}
        if isinstance(entry, list):
            return [normalize(child) for child in entry]
        if isinstance(entry, float) and entry.is_integer():
            return int(entry)
        return entry

    return stable_bytes(normalize(value))


def artifact(path: Path) -> dict[str, Any]:
    resolved = path.resolve()
    materialized = _MATERIALIZED_ARTIFACTS.get(resolved)
    if materialized is not None:
        return copy.deepcopy(materialized)
    try:
        relative = resolved.relative_to(ROOT).as_posix()
    except ValueError as error:
        raise PromotionError(f"产物路径越出仓库：{resolved}") from error
    frozen = _load_evidence_state()["allRecordsByPath"].get(relative)
    if os.environ.get("CF7_PORTRAIT_EVIDENCE_ONLY") == "1" and resolved.is_relative_to(PILOT_ROOT.resolve()):
        if not isinstance(frozen, dict) or _evidence_bytes(frozen) is None:
            raise PromotionError(f"ignored tmp artifact 未进入 immutable evidence pack：{relative}")
        return copy.deepcopy(frozen)
    if resolved.is_file():
        return {"path": relative, "bytes": resolved.stat().st_size, "sha256": sha256_file(resolved)}
    if not isinstance(frozen, dict) or _evidence_bytes(frozen) is None:
        raise PromotionError(f"产物不存在且未被 immutable evidence 覆盖：{path}")
    return copy.deepcopy(frozen)


def logical_artifact_path(path: Path) -> Path:
    """Return the repository path represented by an evidence-cache artifact."""

    resolved = path.resolve()
    materialized = _MATERIALIZED_ARTIFACTS.get(resolved)
    if materialized is None:
        return resolved
    return (ROOT / materialized["path"]).resolve()


def verify_artifact_record(record: Any, label: str) -> Path:
    if not isinstance(record, dict) or not isinstance(record.get("path"), str):
        raise PromotionError(f"{label}缺产物记录")
    path = (ROOT / record["path"]).resolve()
    try:
        path.relative_to(ROOT)
    except ValueError as error:
        raise PromotionError(f"{label}路径越界：{path}") from error
    evidence_only_blob = (
        _evidence_bytes(record)
        if os.environ.get("CF7_PORTRAIT_EVIDENCE_ONLY") == "1"
        else None
    )
    if evidence_only_blob is not None:
        return _materialize_evidence(record, evidence_only_blob)
    if os.environ.get("CF7_PORTRAIT_EVIDENCE_ONLY") == "1" and path.is_relative_to(PILOT_ROOT.resolve()):
        raise PromotionError(f"{label}ignored tmp artifact 未进入 immutable evidence pack：{record['path']}")
    if (
        path.is_file()
        and path.stat().st_size == record.get("bytes")
        and sha256_file(path) == record.get("sha256")
    ):
        return path
    blob = _evidence_bytes(record)
    if blob is not None:
        return _materialize_evidence(record, blob)
    if not path.is_file():
        raise PromotionError(f"{label}文件缺失且 immutable evidence 未覆盖：{path}")
    raise PromotionError(f"{label}哈希或字节数漂移：{record.get('path')}")


def manifest_digest(value: dict[str, Any]) -> str:
    clone = copy.deepcopy(value)
    clone.pop("manifestDigest", None)
    return sha256_bytes(stable_bytes(clone))


def unique_paths(paths: list[Path]) -> list[Path]:
    seen: set[Path] = set()
    result: list[Path] = []
    for path in paths:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            result.append(resolved)
    return result


def collect_calibration(
    campaign_path: Path,
    *,
    expected_decision_count: int = 186,
    expected_statuses: dict[str, int] | None = None,
    expected_correction_count: int = 110,
) -> tuple[
    dict[str, tuple[dict[str, Any], Path]],
    list[tuple[dict[str, Any], Path]],
    dict[str, tuple[int, dict[str, Any], Path, dict[str, Any]]],
    list[Path],
]:
    manifests: list[Path] = []
    receipt_paths: list[Path] = []
    direct_report_paths: list[Path] = []
    correction_report_paths: list[Path] = []
    path: Path | None = campaign_path.resolve()
    seen: set[Path] = set()
    while path is not None and path not in seen:
        seen.add(path)
        manifests.append(path)
        manifest = load_json(path, "campaign manifest")
        calibration = manifest.get("humanPreferenceCalibration")
        if not isinstance(calibration, dict):
            raise PromotionError(f"campaign manifest 缺 humanPreferenceCalibration：{path}")

        for record in calibration.get("humanReviewReceipts", []):
            receipt_paths.append(verify_artifact_record(record, "人类审核回执"))
        for record in calibration.get("parentRenderReports", []):
            direct_report_paths.append(verify_artifact_record(record, "父渲染报告"))
        current = calibration.get("currentHumanReview", {})
        if isinstance(current, dict) and isinstance(current.get("receipt"), dict):
            receipt_path = verify_artifact_record(current["receipt"], "当前人类审核回执")
            receipt_paths.append(receipt_path)
            current_report = resolve_input_path(
                logical_artifact_path(receipt_path).parent / "render-report.json",
                "当前人类审核渲染报告",
            )
            direct_report_paths.append(current_report)
        for field in ("humanGuidedRenderReports", "orientationReports", "guidedOrientationReports"):
            for record in calibration.get(field, []):
                correction_report_paths.append(verify_artifact_record(record, field))
        current_guidance = calibration.get("currentHumanGuidance", {})
        if isinstance(current_guidance, dict) and isinstance(current_guidance.get("guidedRender"), dict):
            correction_report_paths.append(
                verify_artifact_record(current_guidance["guidedRender"], "当前人工框选渲染报告")
            )
        parent = calibration.get("parentManifest")
        path = verify_artifact_record(parent, "偏好标注父 manifest") if isinstance(parent, dict) else None

    decisions: dict[str, tuple[dict[str, Any], Path]] = {}
    for receipt_path in unique_paths(receipt_paths):
        receipt = load_json(receipt_path, "人类审核回执")
        for row in receipt.get("decisions", []):
            if not isinstance(row, dict) or not isinstance(row.get("reviewKey"), str):
                raise PromotionError(f"人类审核回执行非法：{receipt_path}")
            key = row["reviewKey"]
            previous = decisions.get(key)
            if previous is None or str(row.get("updatedAt", "")) >= str(previous[0].get("updatedAt", "")):
                decisions[key] = (row, receipt_path)

    direct_rows: list[tuple[dict[str, Any], Path]] = []
    for report_path in unique_paths(direct_report_paths):
        report = load_json(report_path, "特征渲染报告")
        for row in report.get("rows", []):
            if isinstance(row, dict):
                direct_rows.append((row, report_path))

    correction_rows: dict[str, tuple[int, dict[str, Any], Path, dict[str, Any]]] = {}
    for report_path in unique_paths(correction_report_paths):
        report = load_json(report_path, "人工修正渲染报告")
        name = logical_artifact_path(report_path).name
        if name == "guided-orientation-render-report.json":
            priority = 3
        elif name == "orientation-render-report.json":
            priority = 2
        else:
            priority = 1
        for row in report.get("rows", []):
            if not isinstance(row, dict) or not isinstance(row.get("reviewKey"), str):
                continue
            key = row["reviewKey"]
            previous = correction_rows.get(key)
            if previous is None or priority >= previous[0]:
                correction_rows[key] = (priority, row, report_path, report)

    if expected_statuses is None:
        expected_statuses = {"adjustment": 110, "pass": 75, "source": 1}
    if len(decisions) != expected_decision_count:
        raise PromotionError(
            f"累计人类决策数漂移：expected={expected_decision_count} actual={len(decisions)}"
        )
    statuses: dict[str, int] = {}
    for decision, _path in decisions.values():
        status = str(decision.get("status"))
        statuses[status] = statuses.get(status, 0) + 1
    if statuses != expected_statuses:
        raise PromotionError(f"累计人类决策状态漂移：{statuses}")
    if len(correction_rows) != expected_correction_count:
        raise PromotionError(
            f"人工修正产物数漂移：expected={expected_correction_count} actual={len(correction_rows)}"
        )
    return decisions, direct_rows, correction_rows, manifests


def verify_object_digest(value: dict[str, Any], field: str, label: str, *, pilot: bool = False) -> None:
    clone = copy.deepcopy(value)
    expected = clone.pop(field, None)
    encoded = pilot_stable_bytes(clone) if pilot else stable_bytes(clone)
    if not isinstance(expected, str) or sha256_bytes(encoded) != expected:
        raise PromotionError(f"{label}{field}摘要漂移")


def collect_team_gap(
    batch_path: Path,
) -> tuple[
    dict[str, tuple[dict[str, Any], Path]],
    list[tuple[dict[str, Any], Path]],
    list[Path],
]:
    batch = batch_path.resolve()
    try:
        batch.relative_to(PILOT_ROOT.resolve())
    except ValueError as error:
        raise PromotionError(f"Team 尾项批次越出 tmp/portrait-pilot：{batch}") from error
    receipt_path = batch / "human-review-receipt.json"
    review_data_path = batch / "review-data.json"
    render_path = batch / "render-report.json"
    manifest_path = batch / "candidate-manifest.json"
    model_path = batch / "model-report.json"

    receipt = load_json(receipt_path, "Team 尾项人审回执")
    verify_object_digest(receipt, "receiptDigest", "Team 尾项人审回执")
    if (
        receipt.get("schema") != "cf7.portrait-pilot-human-review-receipt.v1"
        or receipt.get("status") != "human_reviewed_approved"
        or receipt.get("productionReady") is not False
        or receipt.get("gates", {}).get("artAcceptance") is not True
        or receipt.get("gates", {}).get("productionWrites") is not False
    ):
        raise PromotionError("Team 尾项人审回执 schema/status/gates 非法")
    bound_review_data = verify_artifact_record(
        receipt.get("inputs", {}).get("reviewData"), "Team 尾项 review-data"
    )
    verify_artifact_record(receipt.get("inputs", {}).get("decisions"), "Team 尾项 decisions")
    if logical_artifact_path(bound_review_data) != review_data_path.resolve():
        raise PromotionError("Team 尾项回执未精确绑定当前 review-data")

    review_data = load_json(review_data_path, "Team 尾项 review-data")
    render = load_json(render_path, "Team 尾项 render report")
    verify_object_digest(render, "renderDigest", "Team 尾项 render report", pilot=True)
    manifest = load_json(manifest_path, "Team 尾项 candidate manifest")
    if manifest_digest(manifest) != manifest.get("manifestDigest"):
        raise PromotionError("Team 尾项 candidate manifest 摘要漂移")
    model = load_json(model_path, "Team 尾项 model report")
    verify_object_digest(model, "reportDigest", "Team 尾项 model report")
    if (
        review_data.get("reviewDigest") != receipt.get("reviewDigest")
        or review_data.get("sourceDigest") != receipt.get("sourceDigest")
        or review_data.get("renderDigest") != render.get("renderDigest")
        or review_data.get("manifestDigest") != manifest.get("manifestDigest")
        or review_data.get("modelReportDigest") != model.get("reportDigest")
        or render.get("manifestDigest") != manifest.get("manifestDigest")
        or render.get("modelReportDigest") != model.get("reportDigest")
        or render.get("sourceDigest") != receipt.get("sourceDigest")
    ):
        raise PromotionError("Team 尾项 manifest/model/render/review/receipt 摘要未闭合")
    required_gates = {
        "artifactHashesClosed",
        "boundedLargeFrameDecode",
        "dimensionsAndAlphaChecked",
        "minimumSourceCropSizeChecked",
        "mustIncludeSafeMarginChecked",
        "noCandidateRasterUpscale",
        "renderedFeatureOccupancyChecked",
        "selectedFramesOnly",
    }
    if render.get("schema") != "cf7.portrait-pilot-render-report.v4" or any(
        render.get("gates", {}).get(key) is not True for key in required_gates
    ):
        raise PromotionError("Team 尾项 render schema/gates 未闭合")

    decisions: dict[str, tuple[dict[str, Any], Path]] = {}
    for row in receipt.get("decisions", []):
        key = row.get("reviewKey") if isinstance(row, dict) else None
        if not isinstance(key, str) or row.get("status") != "pass" or row.get("blocked") is not False:
            raise PromotionError(f"Team 尾项决定非 pass：{row}")
        decisions[key] = (row, receipt_path)
    expected_keys = {f"{portrait_ref}::default" for portrait_ref in TEAM_GAP_REFS}
    if set(decisions) != expected_keys or receipt.get("counts", {}).get("eligiblePassed") != 3:
        raise PromotionError(f"Team 尾项人审键漂移：{sorted(decisions)}")

    direct_rows: list[tuple[dict[str, Any], Path]] = []
    role_pairs: set[tuple[str, str]] = set()
    for row in render.get("rows", []):
        if not isinstance(row, dict):
            raise PromotionError("Team 尾项 render 行非对象")
        key = row.get("reviewKey")
        role = row.get("role")
        if key not in expected_keys or role not in {"proposal", "independent_review"}:
            raise PromotionError(f"Team 尾项 render 行越界：{key}/{role}")
        master = row.get("master")
        if role == "proposal":
            # A pass decision promotes Luna A by contract, so its exact bytes
            # must be available in the immutable evidence pack.
            verify_artifact_record(master, f"Team 尾项 master {key}/{role}")
        else:
            # Luna B remains a report-bound audit alternative and is never a
            # production input for these three pass decisions.  Keep its
            # record/path exact without requiring ignored candidate pixels in
            # a clean checkout.
            if (
                not isinstance(master, dict)
                or not isinstance(master.get("path"), str)
                or not isinstance(master.get("bytes"), int)
                or not re.fullmatch(r"[0-9A-F]{64}", str(master.get("sha256", "")))
            ):
                raise PromotionError(f"Team 尾项 audit-only master record 非法：{key}/{role}")
            audit_path = (ROOT / master["path"]).resolve()
            try:
                audit_path.relative_to(batch)
            except ValueError as error:
                raise PromotionError(f"Team 尾项 audit-only master 路径越界：{key}/{role}") from error
            if audit_path.name != "master-512.png":
                raise PromotionError(f"Team 尾项 audit-only master 文件名非法：{key}/{role}")
        verify_artifact_record(row.get("sourceGeometrySvg"), f"Team 尾项 SVG {key}/{role}")
        role_pairs.add((key, role))
        direct_rows.append((row, render_path))
    expected_pairs = {(key, role) for key in expected_keys for role in ("proposal", "independent_review")}
    if role_pairs != expected_pairs or len(direct_rows) != 6:
        raise PromotionError("Team 尾项 A/B render 行未闭合")
    return decisions, direct_rows, [manifest_path, model_path, render_path, review_data_path, receipt_path]


def row_report_digest(report: dict[str, Any]) -> str | None:
    for field in ("reportDigest", "renderDigest"):
        value = report.get(field)
        if isinstance(value, str):
            return value
    return None


def proposal_for(
    review_key: str, direct_rows: list[tuple[dict[str, Any], Path]]
) -> tuple[dict[str, Any], Path]:
    matches = [(row, path) for row, path in direct_rows if row.get("reviewKey") == review_key and row.get("role") == "proposal"]
    if not matches:
        raise PromotionError(f"pass 行找不到 Luna A proposal：{review_key}")
    return matches[-1]


def direct_source_for_correction(
    corrected: dict[str, Any], direct_rows: list[tuple[dict[str, Any], Path]]
) -> tuple[dict[str, Any], Path]:
    review_key = corrected.get("reviewKey")
    choice = corrected.get("selectedChoice") if isinstance(corrected.get("selectedChoice"), dict) else {}
    role = choice.get("sourceRole") or corrected.get("sourceRole")
    candidate_id = choice.get("candidateId") or corrected.get("candidateId")
    source_sha = (choice.get("sourceCandidate") or {}).get("sha256")
    # For guided-orientation rows parentMaster is the intermediate human crop,
    # not a direct model render.  The source-candidate hash is authoritative in
    # that case; parentMaster only disambiguates orientation-only corrections.
    parent_sha = None if source_sha else (corrected.get("parentMaster") or {}).get("sha256")
    matches: list[tuple[dict[str, Any], Path]] = []
    for row, path in direct_rows:
        if row.get("reviewKey") != review_key or row.get("role") != role or row.get("candidateId") != candidate_id:
            continue
        if source_sha and (row.get("sourceCandidate") or {}).get("sha256") != source_sha:
            continue
        if parent_sha and (row.get("master") or {}).get("sha256") != parent_sha:
            continue
        matches.append((row, path))
    if len(matches) > 1:
        # A later frame-reselection batch may render the same exact source
        # candidate again with a different model crop.  Human guidance is
        # expressed over the full candidate, so those rows are equivalent as
        # long as their source vector frame is byte-identical.
        vector_hashes = {
            (row.get("sourceGeometrySvg") or {}).get("sha256") for row, _path in matches
        }
        if len(vector_hashes) == 1 and None not in vector_hashes:
            return matches[-1]
    if len(matches) != 1:
        raise PromotionError(f"人工修正找不到唯一原始矢量行：{review_key} matches={len(matches)}")
    return matches[0]


def parse_svg_dimension(value: str | None, label: str) -> float:
    if not isinstance(value, str):
        raise PromotionError(f"SVG 缺 {label}")
    normalized = value.strip()
    if normalized.endswith("px"):
        normalized = normalized[:-2]
    try:
        parsed = float(normalized)
    except ValueError as error:
        raise PromotionError(f"SVG {label} 非数值：{value}") from error
    if not math.isfinite(parsed) or parsed <= 0:
        raise PromotionError(f"SVG {label} 非正数：{value}")
    return parsed


def guided_view_box(
    corrected: dict[str, Any], correction_report: dict[str, Any], source_svg: Path
) -> list[float]:
    inputs = correction_report.get("inputs")
    data_record = inputs.get("guidanceData") if isinstance(inputs, dict) else None
    guidance_path = verify_artifact_record(data_record, "人工框选 guidanceData")
    guidance_data = load_json(guidance_path, "人工框选 guidanceData")
    item = next(
        (entry for entry in guidance_data.get("items", []) if entry.get("reviewKey") == corrected.get("reviewKey")),
        None,
    )
    if not isinstance(item, dict):
        raise PromotionError(f"guidanceData 缺审核键：{corrected.get('reviewKey')}")
    selected = corrected.get("selectedChoice", {})
    human = corrected.get("humanGuidance", {})
    choice = next(
        (
            entry
            for entry in item.get("choices", [])
            if entry.get("sourceRole") == selected.get("sourceRole")
            and entry.get("candidateId") == selected.get("candidateId")
            and (entry.get("sourceCandidate") or {}).get("sha256")
            == human.get("sourceCandidateSha256")
        ),
        None,
    )
    if not isinstance(choice, dict):
        raise PromotionError(f"guidanceData 找不到人工选择：{corrected.get('reviewKey')}")
    crop = human.get("cropBox")
    if not isinstance(crop, list) or len(crop) != 4:
        raise PromotionError(f"人工 cropBox 非法：{corrected.get('reviewKey')}")
    x0, y0, x1, y1 = (float(value) for value in crop)
    candidate_width = float(choice["candidateWidth"])
    candidate_height = float(choice["candidateHeight"])
    pixel_width = (x1 - x0) * candidate_width
    pixel_height = (y1 - y0) * candidate_height
    side = (pixel_width + pixel_height) / 2
    if side <= 0 or abs(pixel_width - pixel_height) > 1.5:
        raise PromotionError(f"人工 cropBox 不是像素正方形：{corrected.get('reviewKey')}")
    source_width, source_height = (float(value) for value in choice["sourceSize"])
    svg_root = ET.parse(source_svg).getroot()
    svg_width = parse_svg_dimension(svg_root.get("width"), "width")
    svg_height = parse_svg_dimension(svg_root.get("height"), "height")
    ratio_x = source_width / svg_width
    ratio_y = source_height / svg_height
    if not 1.90 <= ratio_x <= 2.10 or not 1.90 <= ratio_y <= 2.10:
        raise PromotionError(
            f"人工框选 raster/vector 比例漂移：{corrected.get('reviewKey')} ratio={ratio_x:.4f},{ratio_y:.4f}"
        )
    crop_left, crop_top, _crop_right, _crop_bottom = (float(value) for value in choice["sourceCropBounds"])
    center_x = (crop_left + x0 * candidate_width + side / 2) / ratio_x
    center_y = (crop_top + y0 * candidate_height + side / 2) / ratio_y
    vector_side = max(side / ratio_x, side / ratio_y)
    return [center_x - vector_side / 2, center_y - vector_side / 2, vector_side, vector_side]


def vector_selection(
    selected_row: dict[str, Any],
    selected_report_path: Path,
    direct_rows: list[tuple[dict[str, Any], Path]],
    correction_report: dict[str, Any] | None = None,
) -> tuple[Path, list[float], bool, Path, str, bool]:
    if correction_report is None:
        initial = selected_row
        initial_report_path = selected_report_path
        geometry = initial.get("geometry")
        if not isinstance(geometry, dict) or not isinstance(geometry.get("vectorViewBox"), list):
            raise PromotionError(f"直接接受行缺 vectorViewBox：{selected_row.get('reviewKey')}")
        view_box = [float(value) for value in geometry["vectorViewBox"]]
    else:
        initial, initial_report_path = direct_source_for_correction(selected_row, direct_rows)
        if isinstance(selected_row.get("humanGuidance"), dict):
            svg_path = verify_artifact_record(initial.get("sourceGeometrySvg"), "原始矢量帧")
            view_box = guided_view_box(selected_row, correction_report, svg_path)
        else:
            geometry = initial.get("geometry")
            if not isinstance(geometry, dict) or not isinstance(geometry.get("vectorViewBox"), list):
                raise PromotionError(f"方向修正原始行缺 vectorViewBox：{selected_row.get('reviewKey')}")
            view_box = [float(value) for value in geometry["vectorViewBox"]]
    source_svg = verify_artifact_record(initial.get("sourceGeometrySvg"), "原始矢量帧")
    operation = str(selected_row.get("operation", ""))
    selected_action = selected_row.get("orientationAction")
    initial_action = initial.get("orientationAction")
    correction_schema = correction_report.get("schema") if correction_report is not None else None
    raw_human_crop = correction_schema == "cf7.portrait-pilot-human-framing-render-report.v1"

    # Human framing is performed over the unmirrored FFDec candidate/high-resolution
    # frame.  A framing-only adjustment must therefore inherit the orientation of
    # the selected Luna A/B proposal.  Explicit orientation renderers already
    # transform their PNG master and remain authoritative over the model action.
    if correction_report is None and initial_action in {"keep", "flip_x"}:
        flip = initial_action == "flip_x"
        orientation_source = "direct_model_orientation"
        raster_needs_flip = False
    elif operation.startswith("flip_x"):
        flip = True
        orientation_source = "explicit_human_post_crop_flip"
        raster_needs_flip = False
    elif selected_action in {"keep", "flip_x"}:
        flip = selected_action == "flip_x"
        orientation_source = "explicit_correction_orientation"
        raster_needs_flip = raw_human_crop and flip
    elif raw_human_crop and initial_action in {"keep", "flip_x"}:
        flip = initial_action == "flip_x"
        orientation_source = "selected_model_orientation_inherited_after_human_crop"
        raster_needs_flip = flip
    elif initial_action in {"keep", "flip_x"}:
        flip = initial_action == "flip_x"
        orientation_source = "direct_model_orientation"
        raster_needs_flip = False
    else:
        # Direction inference was not part of the earliest model schema. Preserve
        # those pixels until the full visual audit supplies real evidence.
        flip = False
        orientation_source = "legacy_orientation_unassessed"
        raster_needs_flip = False
    return (
        source_svg,
        view_box,
        flip,
        initial_report_path,
        orientation_source,
        raster_needs_flip,
    )


def format_number(value: float) -> str:
    if not math.isfinite(value):
        raise PromotionError(f"SVG viewBox 含非有限数：{value}")
    text = f"{value:.9f}".rstrip("0").rstrip(".")
    return text if text not in ("-0", "") else "0"


def empty_ffdec_filter_ids(text: str) -> list[str]:
    return sorted(
        {
            match.group(2)
            for match in re.finditer(
                r"<filter\b[^>]*\bid=([\"'])([^\"']+)\1[^>]*/\s*>",
                text,
                flags=re.IGNORECASE,
            )
        }
    )


def svg_representation_evidence(svg_bytes: bytes, png_bytes: bytes) -> dict[str, Any]:
    try:
        text = svg_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PromotionError(f"接受的 SVG 不是 UTF-8：{error}") from error
    image_tags = re.findall(r"<image\b[^>]*>", text, flags=re.IGNORECASE | re.DOTALL)
    embedded_raster_count = 0
    for tag in image_tags:
        href = re.search(
            r"(?:href|xlink:href)\s*=\s*([\"'])(.*?)\1",
            tag,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if href is None or not href.group(2).lower().startswith("data:image/"):
            raise PromotionError("接受的 SVG 含未内容寻址的外部 image 引用")
        embedded_raster_count += 1
    is_raster_heavy = embedded_raster_count > 0 and (
        len(svg_bytes) >= SVG_RASTER_HEAVY_MIN_BYTES
        or len(svg_bytes) >= SVG_RASTER_HEAVY_RATIO * len(png_bytes)
        or embedded_raster_count >= SVG_RASTER_HEAVY_IMAGE_COUNT
    )
    return {
        "preferredFormat": "png" if embedded_raster_count > 0 else "svg",
        "embeddedRasterCount": embedded_raster_count,
        "isRasterHeavy": is_raster_heavy,
    }


def evidence_preserved_subject_records() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for frozen in _load_evidence_state()["preservedSubjects"]:
        if not isinstance(frozen, dict) or not isinstance(frozen.get("path"), str):
            raise PromotionError("敌人头像 evidence preserved subject record 非法")
        prefix = "launcher/web/"
        if not frozen["path"].startswith(prefix):
            raise PromotionError(f"敌人头像 evidence preserved subject 路径非法：{frozen['path']}")
        records.append({
            "url": frozen["path"][len(prefix) :],
            "bytes": frozen.get("bytes"),
            "sha256": frozen.get("sha256"),
            "purpose": frozen.get("purpose"),
        })
    return sorted(records, key=lambda record: record["url"])


def evidence_svg_basis_subject_records() -> list[dict[str, Any]]:
    """Return every committed subject used to losslessly reconstruct an SVG."""

    records: dict[str, dict[str, Any]] = {}
    for descriptor in _load_evidence_state()["svgReconstructions"].values():
        basis = descriptor.get("basis") if isinstance(descriptor, dict) else None
        if not isinstance(basis, dict) or not isinstance(basis.get("path"), str):
            raise PromotionError("敌人头像 evidence SVG basis record 非法")
        prefix = "launcher/web/"
        if not basis["path"].startswith(prefix):
            raise PromotionError(f"敌人头像 evidence SVG basis 路径非法：{basis['path']}")
        record = {
            "url": basis["path"][len(prefix) :],
            "bytes": basis.get("bytes"),
            "sha256": basis.get("sha256"),
            "purpose": "evidence-svg-reconstruction-basis",
        }
        previous = records.get(record["url"])
        if previous is not None and previous != record:
            raise PromotionError(f"敌人头像 evidence SVG basis URL 碰撞：{record['url']}")
        records[record["url"]] = record
    return [records[url] for url in sorted(records)]


def subject_asset_path(asset_root: Path, url: str) -> Path:
    prefix = "assets/enemy-portraits/"
    if not url.startswith(prefix):
        raise PromotionError(f"敌人头像 URL 越界：{url}")
    relative = Path(url[len(prefix) :])
    if relative.is_absolute() or ".." in relative.parts:
        raise PromotionError(f"敌人头像 URL 路径越界：{url}")
    path = (asset_root / relative).resolve()
    try:
        path.relative_to(asset_root.resolve())
    except ValueError as error:
        raise PromotionError(f"敌人头像 URL 解析越界：{url}") from error
    return path


def verify_exact_subject_fileset(manifest: dict[str, Any], asset_root: Path) -> None:
    declared: dict[str, dict[str, Any]] = {}

    def bind(record: Any, label: str) -> None:
        if (
            not isinstance(record, dict)
            or not isinstance(record.get("url"), str)
            or not isinstance(record.get("bytes"), int)
            or not isinstance(record.get("sha256"), str)
        ):
            raise PromotionError(f"{label} artifact record 非法")
        path = subject_asset_path(asset_root, record["url"])
        if path.parent != (asset_root / "subjects").resolve():
            raise PromotionError(f"{label} 不在 subjects 根目录：{record['url']}")
        name = path.name
        if Path(name).stem.lower() != record["sha256"][:24].lower():
            raise PromotionError(f"{label} 文件名未内容寻址：{record['url']}")
        normalized = {"url": record["url"], "bytes": record["bytes"], "sha256": record["sha256"]}
        if name in declared and declared[name] != normalized:
            raise PromotionError(f"{label} subjects 文件名碰撞：{name}")
        declared[name] = normalized

    for portrait_ref, entry in manifest.get("entries", {}).items():
        for variant_key, variant in entry.get("variants", {}).items():
            if variant.get("status") != "human_accepted":
                continue
            subject = variant.get("subject", {})
            bind(subject.get("svg"), f"runtime subject {portrait_ref}::{variant_key}/svg")
            bind(subject.get("pngFallback"), f"runtime subject {portrait_ref}::{variant_key}/png")

    preserved = manifest.get("preservedEvidence")
    if not isinstance(preserved, dict) or preserved.get("schema") != "cf7.enemy-portrait-preserved-evidence.v1":
        raise PromotionError("敌人头像 preservedEvidence schema 缺失")
    preserved_subjects = preserved.get("subjects")
    if not isinstance(preserved_subjects, list):
        raise PromotionError("敌人头像 preservedEvidence subjects 非法")
    for index, record in enumerate(preserved_subjects):
        if (
            not isinstance(record, dict)
            or record.get("purpose") not in {
                "orientation-source-byte-preservation",
                "evidence-svg-reconstruction-basis",
            }
        ):
            raise PromotionError(f"敌人头像 preservedEvidence purpose 非法：{index}")
        bind(record, f"preserved subject {index}")

    subject_root = (asset_root / "subjects").resolve()
    if not subject_root.is_dir():
        raise PromotionError(f"敌人头像 subjects 目录缺失：{subject_root}")
    actual = {path.name for path in subject_root.iterdir() if path.is_file()}
    non_files = [path.name for path in subject_root.iterdir() if not path.is_file()]
    if non_files or actual != set(declared):
        raise PromotionError(
            "敌人头像 subjects fileset 漂移："
            f"missing={sorted(set(declared) - actual)} extra={sorted(actual - set(declared))} nonFiles={sorted(non_files)}"
        )
    for name, record in declared.items():
        path = subject_root / name
        if path.stat().st_size != record["bytes"] or sha256_file(path) != record["sha256"]:
            raise PromotionError(f"敌人头像 subjects artifact 漂移：{record['url']}")


def strip_empty_ffdec_filters(text: str) -> tuple[str, list[str]]:
    filter_ids = empty_ffdec_filter_ids(text)
    for filter_id in filter_ids:
        text = re.sub(
            rf"\sfilter=([\"'])url\(#{re.escape(filter_id)}\)\1",
            "",
            text,
            flags=re.IGNORECASE,
        )
    text = re.sub(
        r"\s*<filter\b[^>]*\bid=([\"'])([^\"']+)\1[^>]*/\s*>",
        "",
        text,
        flags=re.IGNORECASE,
    )
    return text, filter_ids


def build_cropped_svg(source_svg: Path, view_box: list[float], flip: bool) -> bytes:
    if len(view_box) != 4 or view_box[2] <= 0 or view_box[3] <= 0:
        raise PromotionError(f"SVG viewBox 非法：{view_box}")
    text = source_svg.read_text(encoding="utf-8")
    # FFDec occasionally emits a self-closing <filter/> placeholder and binds
    # it to every visible <use>. Chromium treats those uses as transparent even
    # though the SVG request succeeds. The placeholder has no visual operation,
    # so remove both it and its references before publishing the vector crop.
    text, _empty_filter_ids = strip_empty_ffdec_filters(text)
    match = re.search(r"<svg\b[^>]*>", text, flags=re.IGNORECASE | re.DOTALL)
    if match is None:
        raise PromotionError(f"SVG 根元素不可识别：{source_svg}")
    opening = match.group(0)
    opening = re.sub(r"\s(?:viewBox|preserveAspectRatio|width|height)=([\"']).*?\1", "", opening, flags=re.IGNORECASE)
    view_text = " ".join(format_number(value) for value in view_box)
    opening = opening[:-1] + f' width="512" height="512" viewBox="{view_text}" preserveAspectRatio="xMidYMid meet">'
    text = text[: match.start()] + opening + text[match.end() :]
    if flip:
        closing = text.lower().rfind("</svg>")
        if closing < 0:
            raise PromotionError(f"SVG 缺关闭标签：{source_svg}")
        center_x = view_box[0] + view_box[2] / 2
        transform = f'translate({format_number(2 * center_x)} 0) scale(-1 1)'
        insert_at = match.start() + len(opening)
        text = text[:insert_at] + f'\n  <g data-cf7-portrait-flip="x" transform="{transform}">' + text[insert_at:closing] + "\n  </g>\n" + text[closing:]
    return text.encode("utf-8")


def png_alpha_evidence(path: Path) -> dict[str, Any]:
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
        if image.size != (512, 512):
            raise PromotionError(f"接受的 PNG master 不是 512x512：{path} size={image.size}")
        alpha = image.getchannel("A")
        visible = alpha.getbbox()
        extrema = alpha.getextrema()
    if visible is None:
        raise PromotionError(f"接受的 PNG master 全透明：{path}")
    if extrema[0] >= 255:
        raise PromotionError(f"接受的 PNG master 没有透明背景：{path}")
    return {"size": [512, 512], "alphaExtrema": [int(extrema[0]), int(extrema[1])], "visibleBounds": list(visible)}


def legacy_url(pet_ids: list[int], portrait_ref: str, variant_key: str) -> str | None:
    if not pet_ids:
        return None
    pet_id = min(int(value) for value in pet_ids)
    if portrait_ref == JK_REF and variant_key == "orange":
        return f"assets/pets/pet_{pet_id}_1.png"
    return f"assets/pets/pet_{pet_id}.png"


def accepted_selection(
    review_key: str,
    decisions: dict[str, tuple[dict[str, Any], Path]],
    direct_rows: list[tuple[dict[str, Any], Path]],
    corrections: dict[str, tuple[int, dict[str, Any], Path, dict[str, Any]]],
) -> dict[str, Any] | None:
    value = decisions.get(review_key)
    if value is None:
        return None
    decision, receipt_path = value
    status = decision.get("status")
    if status == "pass":
        row, report_path = proposal_for(review_key, direct_rows)
        report = load_json(report_path, "直接接受渲染报告")
        source_svg, view_box, flip, vector_report_path, orientation_source, raster_needs_flip = vector_selection(
            row, report_path, direct_rows
        )
        resolution = "human_passed_luna_a_proposal"
    elif status == "adjustment":
        correction = corrections.get(review_key)
        if correction is None:
            raise PromotionError(f"adjustment 缺最终修正产物：{review_key}")
        _priority, row, report_path, report = correction
        source_svg, view_box, flip, vector_report_path, orientation_source, raster_needs_flip = vector_selection(
            row, report_path, direct_rows, report
        )
        resolution = "human_guided_adjustment"
    else:
        return None
    master_path = verify_artifact_record(row.get("master"), "人类接受 PNG master")
    return {
        "reviewKey": review_key,
        "resolution": resolution,
        "decision": decision,
        "receiptPath": receipt_path,
        "reportPath": report_path,
        "reportDigest": row_report_digest(report),
        "vectorReportPath": vector_report_path,
        "masterPath": master_path,
        "sourceSvg": source_svg,
        "viewBox": view_box,
        "flipX": flip,
        "orientationSource": orientation_source,
        "rasterNeedsFlip": raster_needs_flip,
    }


def representative_selections(
    closure_path: Path, direct_rows: list[tuple[dict[str, Any], Path]]
) -> dict[str, dict[str, Any]]:
    closure = load_json(closure_path, "代表集 closure")
    representative_direct: list[tuple[dict[str, Any], Path]] = []
    for report_path in REPRESENTATIVE_DIRECT_REPORTS:
        report = load_json(report_path, "代表集渲染报告")
        representative_direct.extend((row, report_path) for row in report.get("rows", []) if isinstance(row, dict))
    all_direct = direct_rows + representative_direct
    guided_record = closure.get("inputs", {}).get("guidedRender", {}).get("reportFile")
    guided_path = verify_artifact_record(guided_record, "代表集人工框选报告")
    guided_report = load_json(guided_path, "代表集人工框选报告")
    guided_by_key = {row["reviewKey"]: row for row in guided_report.get("rows", [])}
    results: dict[str, dict[str, Any]] = {}
    for closure_row in closure.get("rows", []):
        review_key = closure_row.get("reviewKey")
        resolution = closure_row.get("resolution")
        if resolution == "human_passed_luna_a_proposal":
            row, report_path = proposal_for(review_key, representative_direct)
            report = load_json(report_path, "代表集直接接受报告")
            source_svg, view_box, flip, vector_report_path, orientation_source, raster_needs_flip = vector_selection(
                row, report_path, all_direct
            )
            receipt_path = next(
                verify_artifact_record(batch["files"]["receipt"], "代表集审核回执")
                for batch in closure.get("inputs", {}).get("reviewedBatches", [])
                if batch.get("receiptDigest") == closure_row.get("receiptDigest")
            )
        elif resolution == "human_guided_high_resolution_render":
            row = guided_by_key.get(review_key)
            if row is None:
                raise PromotionError(f"代表集人工框选行缺失：{review_key}")
            report_path = guided_path
            report = guided_report
            source_svg, view_box, flip, vector_report_path, orientation_source, raster_needs_flip = vector_selection(
                row, report_path, all_direct, report
            )
            receipt_path = verify_artifact_record(
                guided_report.get("inputs", {}).get("guidanceReceipt"), "代表集框选回执"
            )
        else:
            raise PromotionError(f"代表集 closure resolution 非法：{review_key}={resolution}")
        master_path = verify_artifact_record(row.get("master"), "代表集接受 PNG master")
        results[review_key] = {
            "reviewKey": review_key,
            "resolution": resolution,
            "decision": {"status": "pass", "notes": "representative closure"},
            "receiptPath": receipt_path,
            "reportPath": report_path,
            "reportDigest": row_report_digest(report),
            "vectorReportPath": vector_report_path,
            "masterPath": master_path,
            "sourceSvg": source_svg,
            "viewBox": view_box,
            "flipX": flip,
            "orientationSource": orientation_source,
            "rasterNeedsFlip": raster_needs_flip,
        }
    return results


def write_subject_assets(staging: Path, selection: dict[str, Any]) -> dict[str, Any]:
    subject_root = staging / "subjects"
    subject_root.mkdir(parents=True, exist_ok=True)
    master_path: Path = selection["masterPath"]
    raster_needs_flip = selection.get("rasterNeedsFlip") is True
    if raster_needs_flip:
        with Image.open(master_path) as opened:
            transformed = opened.convert("RGBA").transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            stream = io.BytesIO()
            transformed.save(stream, format="PNG", optimize=False, compress_level=9)
            png_bytes = stream.getvalue()
        with Image.open(io.BytesIO(png_bytes)) as derived:
            image = derived.convert("RGBA")
            if image.size != (512, 512):
                raise PromotionError(f"派生 PNG master 不是 512x512：{master_path} size={image.size}")
            alpha_channel = image.getchannel("A")
            visible = alpha_channel.getbbox()
            extrema = alpha_channel.getextrema()
        if visible is None or extrema[0] >= 255:
            raise PromotionError(f"派生 PNG master 透明度非法：{master_path}")
        alpha = {
            "size": [512, 512],
            "alphaExtrema": [int(extrema[0]), int(extrema[1])],
            "visibleBounds": list(visible),
        }
    else:
        alpha = png_alpha_evidence(master_path)
        png_bytes = master_path.read_bytes()
    png_sha = sha256_bytes(png_bytes)
    if not raster_needs_flip and png_sha != sha256_file(master_path):
        raise PromotionError(f"PNG master 读取期间漂移：{master_path}")
    png_name = f"{png_sha[:24].lower()}.png"
    png_path = subject_root / png_name
    if png_path.exists() and png_path.read_bytes() != png_bytes:
        raise PromotionError(f"PNG 内容寻址碰撞：{png_name}")
    if not png_path.exists():
        png_path.write_bytes(png_bytes)

    source_svg_text = selection["sourceSvg"].read_text(encoding="utf-8")
    source_empty_filter_ids = empty_ffdec_filter_ids(source_svg_text)
    svg_bytes = build_cropped_svg(selection["sourceSvg"], selection["viewBox"], selection["flipX"])
    representation = svg_representation_evidence(svg_bytes, png_bytes)
    svg_sha = sha256_bytes(svg_bytes)
    svg_name = f"{svg_sha[:24].lower()}.svg"
    svg_path = subject_root / svg_name
    if svg_path.exists() and svg_path.read_bytes() != svg_bytes:
        raise PromotionError(f"SVG 内容寻址碰撞：{svg_name}")
    if not svg_path.exists():
        svg_path.write_bytes(svg_bytes)

    report_path: Path = selection["reportPath"]
    receipt_path: Path = selection["receiptPath"]
    vector_report_path: Path = selection["vectorReportPath"]
    source_svg: Path = selection["sourceSvg"]
    raster_transform = selection.get("rasterOrientationTransform")
    if raster_transform is None:
        raster_transform = (
            "flip_x_after_human_crop"
            if selection.get("orientationSource") == "selected_model_orientation_inherited_after_human_crop"
            and raster_needs_flip
            else "none"
        )
    provenance = {
        "reviewKey": selection["reviewKey"],
        "resolution": selection["resolution"],
        "decisionStatus": selection["decision"].get("status"),
        "decisionNotes": selection["decision"].get("notes", ""),
        "orientationAction": "flip_x" if selection["flipX"] else "keep",
        "orientationSource": selection["orientationSource"],
        "rasterOrientationTransform": raster_transform,
        "humanReceipt": artifact(receipt_path),
        "acceptedRenderReport": artifact(report_path),
        "acceptedRenderDigest": selection.get("reportDigest"),
        "vectorGeometryReport": artifact(vector_report_path),
        "sourceVectorFrame": artifact(source_svg),
    }
    if isinstance(selection.get("orientationAudit"), dict):
        provenance["orientationAudit"] = copy.deepcopy(selection["orientationAudit"])
    svg_record = {
        "url": f"assets/enemy-portraits/subjects/{svg_name}",
        "bytes": len(svg_bytes),
        "sha256": svg_sha,
        "viewBox": [float(value) for value in selection["viewBox"]],
        "flipX": bool(selection["flipX"]),
        "embeddedRasterCount": representation["embeddedRasterCount"],
        "isRasterHeavy": representation["isRasterHeavy"],
    }
    if source_empty_filter_ids:
        svg_record["compatibilityTransforms"] = [
            {
                "kind": "strip_empty_ffdec_filters",
                "filterIds": source_empty_filter_ids,
            }
        ]
        provenance["svgCompatibilityTransform"] = "strip_empty_ffdec_filters"
    return {
        "status": "human_accepted",
        "subject": {
            "preferredFormat": representation["preferredFormat"],
            "svg": svg_record,
            "pngFallback": {
                "url": f"assets/enemy-portraits/subjects/{png_name}",
                "bytes": len(png_bytes),
                "sha256": png_sha,
                **alpha,
            },
        },
        "provenance": provenance,
    }


def alias_manifest_record() -> dict[str, Any]:
    receipt = load_json(ALIAS_RECEIPT, "头像别名回执")
    rows = receipt.get("rows") or receipt.get("aliases") or []
    alias_row = next(
        (
            row
            for row in rows
            if isinstance(row, dict)
            and row.get("portraitRef") == "敌人-拟态投影"
            and (row.get("targetPortraitRef") or row.get("reusePortraitRef")) == "敌人-方舟妖姬"
        ),
        None,
    )
    if alias_row is None:
        # The receipt schema stores the same pair under source/target in older batches.
        raw = json.dumps(receipt, ensure_ascii=False)
        if "敌人-拟态投影" not in raw or "敌人-方舟妖姬" not in raw:
            raise PromotionError("头像别名回执不含拟态投影 -> 方舟妖姬")
    return {
        "敌人-拟态投影": {
            "targetPortraitRef": "敌人-方舟妖姬",
            "variantKey": "default",
            "provenance": artifact(ALIAS_RECEIPT),
        }
    }


def build_pack(
    inventory_path: Path,
    campaign_path: Path,
    closure_path: Path,
    team_gap_batch: Path,
    staging: Path,
) -> dict[str, Any]:
    inventory = load_json(inventory_path, "portrait inventory")
    decisions, direct_rows, corrections, calibration_manifests = collect_calibration(campaign_path)
    gap_decisions, gap_direct_rows, gap_inputs = collect_team_gap(team_gap_batch)
    overlap = set(decisions).intersection(gap_decisions)
    if overlap:
        raise PromotionError(f"Team 尾项决定与累计回执重复：{sorted(overlap)}")
    decisions.update(gap_decisions)
    direct_rows.extend(gap_direct_rows)
    representatives = representative_selections(closure_path, direct_rows)
    pet_items = sorted(
        (item for item in inventory.get("items", []) if item.get("consumers", {}).get("petIds")),
        key=lambda item: item["portraitRef"],
    )
    if len(pet_items) != 98:
        raise PromotionError(f"战队 identity 数漂移：expected=98 actual={len(pet_items)}")

    entries: dict[str, Any] = {}
    accepted_variants = 0
    pending_refs: set[str] = set()
    excluded_refs: set[str] = set()
    for item in pet_items:
        portrait_ref = item["portraitRef"]
        pet_ids = sorted(int(value) for value in item["consumers"]["petIds"])
        variant_keys = list(item.get("variantKeys") or ["default"])
        default_variant = "orange" if portrait_ref == JK_REF else variant_keys[0]
        variants: dict[str, Any] = {}
        for variant_key in variant_keys:
            review_key = f"{portrait_ref}::{variant_key}"
            selection = accepted_selection(review_key, decisions, direct_rows, corrections)
            if selection is None:
                selection = representatives.get(review_key)
            legacy = legacy_url(pet_ids, portrait_ref, variant_key)
            if selection is not None:
                variant = write_subject_assets(staging, selection)
                accepted_variants += 1
            elif portrait_ref == UNIMPLEMENTED_REF:
                variant = {
                    "status": "excluded_unimplemented",
                    "reason": "pets.xml explicitly marks this asset as not considered implemented; only unused FLA exists",
                }
                excluded_refs.add(portrait_ref)
            elif portrait_ref in TEAM_GAP_REFS:
                variant = {
                    "status": "pending_human_review",
                    "reason": "source was resolved after prior exclusion; final feature framing still requires human acceptance",
                }
                pending_refs.add(portrait_ref)
            else:
                raise PromotionError(f"战队头像没有人类接受产物也不在受控例外中：{review_key}")
            if legacy:
                variant["legacyUrl"] = legacy
            variants[variant_key] = variant
        entry_status = "ready" if all(row["status"] == "human_accepted" for row in variants.values()) else (
            "excluded_unimplemented" if portrait_ref == UNIMPLEMENTED_REF else "pending_human_review"
        )
        entries[portrait_ref] = {
            "portraitRef": portrait_ref,
            "petIds": pet_ids,
            "status": entry_status,
            "defaultVariant": default_variant,
            "variants": variants,
        }

    if pending_refs:
        raise PromotionError(f"待真人审核战队 identity 未清零：{sorted(pending_refs)}")
    if excluded_refs != {UNIMPLEMENTED_REF}:
        raise PromotionError(f"未实装战队 identity 漂移：{sorted(excluded_refs)}")
    if accepted_variants != 98:
        raise PromotionError(f"已接受战队 variant 数漂移：expected=98 actual={accepted_variants}")
    jk = entries.get(JK_REF, {})
    if set(jk.get("variants", {})) != {"orange", "white"}:
        raise PromotionError("JK 双头像 variant 不闭合")
    orange = jk["variants"]["orange"]["subject"]["pngFallback"]["sha256"]
    white = jk["variants"]["white"]["subject"]["pngFallback"]["sha256"]
    if orange == white:
        raise PromotionError("JK 橙发/白发接受头像不得相同")

    source_records = [artifact(inventory_path), artifact(campaign_path), artifact(closure_path)]
    source_records.extend(artifact(path) for path in calibration_manifests if path != campaign_path.resolve())
    source_records.extend(artifact(path) for path in gap_inputs)
    manifest: dict[str, Any] = {
        "schema": "cf7.team-enemy-portrait-manifest.v1",
        "status": "team_portraits_promoted",
        "generatedAt": utc_now(),
        "consumerContract": {
            "identityKey": "portraitRef + variantKey",
            "primaryFormat": "per-variant subject.preferredFormat; PNG is primary for every SVG containing embedded raster images",
            "fallbackFormat": "the alternate signed subject format, then caller legacy asset",
            "presentationOwnedBy": "launcher/web/modules/portrait-resolver.js and consumer CSS",
            "arenaCompatible": True,
        },
        "counts": {
            "identityCount": len(entries),
            "variantCount": sum(len(entry["variants"]) for entry in entries.values()),
            "humanAcceptedVariantCount": accepted_variants,
            "pendingHumanReviewIdentityCount": len(pending_refs),
            "excludedUnimplementedIdentityCount": len(excluded_refs),
        },
        "sourceEnvelope": {"inputs": source_records},
        "aliases": alias_manifest_record(),
        "entries": entries,
    }
    manifest["manifestDigest"] = manifest_digest(manifest)
    manifest_path = staging / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    receipt = {
        "schema": "cf7.team-enemy-portrait-promotion-receipt.v1",
        "status": "team_portrait_pack_promoted",
        "generatedAt": manifest["generatedAt"],
        "manifest": artifact(manifest_path),
        "manifestDigest": manifest["manifestDigest"],
        "counts": manifest["counts"],
        "gates": {
            "allPreviouslyAcceptedTeamVariantsPromoted": True,
            "allTeamVariantsWithRuntimeSourcesPromoted": True,
            "jkTwoDistinctVariantsPromoted": True,
            "directPassOrientationAppliedToSvg": True,
            "humanCropSelectedOrientationInherited": True,
            "svgPrimaryAndExactPngFallbackBound": True,
            "allPngMastersHaveTransparentBackground": True,
            "threeLateSourceResolutionsHumanAccepted": True,
            "maiRemainsExplicitlyUnimplemented": True,
            "presentationSeparatedFromIdentityManifest": True,
            "productionWrites": True,
        },
    }
    receipt["receiptDigest"] = sha256_bytes(stable_bytes(receipt))
    (staging / "promotion-receipt.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


def resolve_output(path: Path) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(WEB_ROOT.resolve())
    except ValueError as error:
        raise PromotionError(f"生产输出必须位于 launcher/web：{resolved}") from error
    return resolved


def promote(args: argparse.Namespace) -> None:
    output = resolve_output(Path(args.output))
    replacing = output.exists()
    if replacing and not args.replace_existing:
        raise PromotionError(f"生产输出已存在，禁止覆盖；先运行 check 或显式做新版本迁移：{output}")
    staging = output.with_name(f"{output.name}.staging-{os.getpid()}")
    if staging.exists():
        raise PromotionError(f"staging 已存在，禁止覆盖：{staging}")
    staging.mkdir(parents=True)
    manifest = build_pack(
        Path(args.inventory).resolve(),
        Path(args.campaign_manifest).resolve(),
        Path(args.representative_closure).resolve(),
        Path(args.team_gap_batch).resolve(),
        staging,
    )
    backup: Path | None = None
    if replacing:
        old_manifest = load_json(output / "manifest.json", "上一版战队头像 manifest")
        old_digest = old_manifest.get("manifestDigest")
        if not isinstance(old_digest, str):
            raise PromotionError("上一版战队头像 manifest 缺 digest")
        backup_root = PILOT_ROOT / "team-portrait-production-backups"
        backup_root.mkdir(parents=True, exist_ok=True)
        backup = backup_root / f"enemy-portraits-{old_digest[:16].lower()}"
        if backup.exists():
            raise PromotionError(f"上一版备份已存在，禁止覆盖：{backup}")
        os.replace(output, backup)
    try:
        os.replace(staging, output)
        checked = check_manifest(output / "manifest.json")
    except Exception:
        failed_root = PILOT_ROOT / "failed-team-promotion-staging"
        failed_root.mkdir(parents=True, exist_ok=True)
        failed_stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        failed = failed_root / f"{output.name}.failed-{failed_stamp}-{os.getpid()}"
        collision_index = 0
        while failed.exists():
            collision_index += 1
            failed = failed_root / (
                f"{output.name}.failed-{failed_stamp}-{os.getpid()}-{collision_index}"
            )
        if output.exists():
            os.replace(output, failed)
        if backup is not None and backup.exists():
            os.replace(backup, output)
        raise
    print(
        json.dumps(
            {
                "status": "team_portrait_pack_promoted",
                "output": repo_rel(output),
                "manifestDigest": manifest["manifestDigest"],
                "counts": checked["counts"],
                "rollbackBackup": repo_rel(backup) if backup is not None else None,
            },
            ensure_ascii=False,
        )
    )


def check_manifest(manifest_path: Path) -> dict[str, Any]:
    manifest = load_json(manifest_path, "战队头像 manifest")
    schema = manifest.get("schema")
    universal = schema == "cf7.enemy-portrait-manifest.v1"
    if schema not in {"cf7.team-enemy-portrait-manifest.v1", "cf7.enemy-portrait-manifest.v1"}:
        raise PromotionError("战队头像 manifest schema 非法")
    expected_status = "human_accepted_portraits_promoted" if universal else "team_portraits_promoted"
    if manifest.get("status") != expected_status:
        raise PromotionError("战队头像 manifest 尚未全量 promotion")
    if manifest_digest(manifest) != manifest.get("manifestDigest"):
        raise PromotionError("战队头像 manifestDigest 漂移")
    all_entries = manifest.get("entries")
    if not isinstance(all_entries, dict):
        raise PromotionError("战队头像 manifest entries 非法")
    if universal:
        inventory = load_json(DEFAULT_INVENTORY, "portrait inventory")
        team_refs = {
            item["portraitRef"]
            for item in inventory.get("items", [])
            if (item.get("consumers") or {}).get("petIds")
        }
        if len(team_refs) != 98 or not team_refs.issubset(all_entries):
            raise PromotionError("通用头像 manifest 未闭合 98 个 Team identity 子集")
        entries = {portrait_ref: all_entries[portrait_ref] for portrait_ref in team_refs}
    else:
        entries = all_entries
        if len(entries) != 98:
            raise PromotionError("战队头像 manifest identityCount 不闭合")
    accepted = 0
    pending: set[str] = set()
    excluded: set[str] = set()
    flipped: set[str] = set()
    for portrait_ref, entry in entries.items():
        variants = entry.get("variants")
        if not isinstance(variants, dict) or entry.get("defaultVariant") not in variants:
            raise PromotionError(f"战队头像 variant/default 不闭合：{portrait_ref}")
        for variant_key, variant in variants.items():
            status = variant.get("status")
            if status == "human_accepted":
                accepted += 1
                subject = variant.get("subject", {})
                for kind in ("svg", "pngFallback"):
                    record = subject.get(kind)
                    if not isinstance(record, dict) or not isinstance(record.get("url"), str):
                        raise PromotionError(f"战队头像 subject 记录缺失：{portrait_ref}::{variant_key}/{kind}")
                    prefix = "assets/enemy-portraits/"
                    if not record["url"].startswith(prefix):
                        raise PromotionError(f"战队头像 URL 越界：{record['url']}")
                    path = WEB_ROOT / record["url"]
                    if path.stat().st_size != record.get("bytes") or sha256_file(path) != record.get("sha256"):
                        raise PromotionError(f"战队头像产物漂移：{record['url']}")
                png_path = WEB_ROOT / subject["pngFallback"]["url"]
                svg_path = WEB_ROOT / subject["svg"]["url"]
                representation = svg_representation_evidence(svg_path.read_bytes(), png_path.read_bytes())
                if (
                    subject.get("preferredFormat") != representation["preferredFormat"]
                    or subject["svg"].get("embeddedRasterCount") != representation["embeddedRasterCount"]
                    or subject["svg"].get("isRasterHeavy") != representation["isRasterHeavy"]
                ):
                    raise PromotionError(f"战队头像 SVG/PNG representation 证据漂移：{portrait_ref}::{variant_key}")
                if png_alpha_evidence(png_path) != {
                    key: subject["pngFallback"][key] for key in ("size", "alphaExtrema", "visibleBounds")
                }:
                    raise PromotionError(f"战队头像 alpha 证据漂移：{portrait_ref}::{variant_key}")
                review_key = f"{portrait_ref}::{variant_key}"
                flip_x = subject["svg"].get("flipX") is True
                expected_action = "flip_x" if flip_x else "keep"
                provenance = variant.get("provenance", {})
                if provenance.get("orientationAction") != expected_action:
                    raise PromotionError(f"战队头像方向 provenance 漂移：{review_key}")
                orientation_source = provenance.get("orientationSource")
                raster_transform = provenance.get("rasterOrientationTransform")
                if orientation_source not in ORIENTATION_SOURCES:
                    raise PromotionError(f"战队头像方向证据来源非法：{review_key}={orientation_source}")
                orientation_audit = provenance.get("orientationAudit")
                if orientation_source in {
                    "production_visual_audit_model_verified_keep",
                    "explicit_production_orientation_human_audit",
                }:
                    if not isinstance(orientation_audit, dict):
                        raise PromotionError(f"战队头像方向全量审计 lineage 缺失：{review_key}")
                    if orientation_audit.get("finalAction") != expected_action:
                        raise PromotionError(f"战队头像方向全量审计 finalAction 漂移：{review_key}")
                    decision = orientation_audit.get("decision")
                    base_action = orientation_audit.get("sourceProductionAction")
                    if orientation_source == "production_visual_audit_model_verified_keep":
                        if decision != "model_verified_keep" or base_action != expected_action:
                            raise PromotionError(f"战队头像模型方向闭合 lineage 漂移：{review_key}")
                    elif decision == "keep":
                        if base_action != expected_action:
                            raise PromotionError(f"战队头像真人 keep lineage 漂移：{review_key}")
                    elif decision == "flip_x":
                        if base_action == expected_action:
                            raise PromotionError(f"战队头像真人 flip 未切换方向：{review_key}")
                    else:
                        raise PromotionError(f"战队头像真人方向决定非法：{review_key}={decision}")
                    expected_transform = orientation_audit.get("finalRasterOrientationTransform")
                else:
                    if orientation_audit is not None:
                        raise PromotionError(f"战队头像旧方向来源不得携带全量审计 lineage：{review_key}")
                    expected_transform = (
                        "flip_x_after_human_crop"
                        if orientation_source == "selected_model_orientation_inherited_after_human_crop" and flip_x
                        else "none"
                    )
                if raster_transform != expected_transform:
                    raise PromotionError(
                        f"战队头像 PNG 方向变换漂移：{review_key} expected={expected_transform} actual={raster_transform}"
                    )
                if orientation_source == "legacy_orientation_unassessed" and flip_x:
                    raise PromotionError(f"未审计旧头像不得凭空反转：{review_key}")
                svg_text = svg_path.read_text(encoding="utf-8")
                has_flip_group = 'data-cf7-portrait-flip="x"' in svg_text
                if has_flip_group != flip_x:
                    raise PromotionError(f"战队头像 SVG 方向标记漂移：{review_key}")
                if empty_ffdec_filter_ids(svg_text):
                    raise PromotionError(f"战队头像 SVG 仍含 Chromium 空白 filter：{review_key}")
                source_svg = verify_artifact_record(provenance.get("sourceVectorFrame"), "战队头像源矢量帧")
                source_filter_ids = empty_ffdec_filter_ids(source_svg.read_text(encoding="utf-8"))
                expected_compatibility = ([{
                    "kind": "strip_empty_ffdec_filters",
                    "filterIds": source_filter_ids,
                }] if source_filter_ids else [])
                if subject["svg"].get("compatibilityTransforms", []) != expected_compatibility:
                    raise PromotionError(f"战队头像 SVG 兼容变换证据漂移：{review_key}")
                expected_transform = "strip_empty_ffdec_filters" if source_filter_ids else None
                if provenance.get("svgCompatibilityTransform") != expected_transform:
                    raise PromotionError(f"战队头像 SVG 兼容 provenance 漂移：{review_key}")
                if flip_x:
                    flipped.add(review_key)
            elif status == "pending_human_review":
                pending.add(portrait_ref)
            elif status == "excluded_unimplemented":
                excluded.add(portrait_ref)
            else:
                raise PromotionError(f"战队头像状态非法：{portrait_ref}::{variant_key}={status}")
    counts = manifest.get("counts")
    expected_counts = {
        "identityCount": 98,
        "variantCount": 99,
        "humanAcceptedVariantCount": 98,
        "pendingHumanReviewIdentityCount": 0,
        "excludedUnimplementedIdentityCount": 1,
    }
    if ((not universal and counts != expected_counts)
            or accepted != 98 or pending or excluded != {UNIMPLEMENTED_REF}):
        raise PromotionError(
            f"战队头像闭包计数漂移：counts={counts} accepted={accepted} pending={sorted(pending)} excluded={sorted(excluded)}"
        )
    expected_flipped = EXPECTED_FLIPPED_VARIANTS
    if universal and isinstance(manifest.get("orientationAudit"), dict):
        expected_flipped = EXPECTED_FLIPPED_VARIANTS.symmetric_difference(ORIENTATION_AUDIT_TEAM_TOGGLES)
    if flipped != expected_flipped:
        raise PromotionError(f"战队头像方向闭包漂移：expected={sorted(expected_flipped)} actual={sorted(flipped)}")
    jk = entries[JK_REF]
    if set(jk["variants"]) != {"orange", "white"} or jk.get("defaultVariant") != "orange":
        raise PromotionError("JK 双头像合同漂移")
    if (
        jk["variants"]["orange"]["subject"]["pngFallback"]["sha256"]
        == jk["variants"]["white"]["subject"]["pngFallback"]["sha256"]
    ):
        raise PromotionError("JK 双头像像素相同")
    receipt_path = manifest_path.parent / "promotion-receipt.json"
    receipt = load_json(receipt_path, "战队头像 promotion receipt")
    if (receipt.get("manifestDigest") != manifest["manifestDigest"]
            or (not universal and receipt.get("counts") != counts)):
        raise PromotionError("战队头像 promotion receipt 漂移")
    required_receipt_gates = {
        "allPreviouslyAcceptedTeamVariantsPromoted",
        "allTeamVariantsWithRuntimeSourcesPromoted",
        "jkTwoDistinctVariantsPromoted",
        "directPassOrientationAppliedToSvg",
        "humanCropSelectedOrientationInherited",
        "svgPrimaryAndExactPngFallbackBound",
        "allPngMastersHaveTransparentBackground",
        "threeLateSourceResolutionsHumanAccepted",
        "maiRemainsExplicitlyUnimplemented",
        "presentationSeparatedFromIdentityManifest",
        "productionWrites",
    }
    if any(receipt.get("gates", {}).get(key) is not True for key in required_receipt_gates):
        raise PromotionError("战队头像 promotion receipt gates 未闭合")
    clone = copy.deepcopy(receipt)
    expected_receipt_digest = clone.pop("receiptDigest", None)
    if sha256_bytes(stable_bytes(clone)) != expected_receipt_digest:
        raise PromotionError("战队头像 receiptDigest 漂移")
    return manifest


def check(args: argparse.Namespace) -> None:
    manifest = check_manifest(Path(args.manifest).resolve())
    print(
        json.dumps(
            {
                "status": "team_portrait_pack_verified",
                "manifest": repo_rel(Path(args.manifest).resolve()),
                "manifestDigest": manifest["manifestDigest"],
                "counts": manifest["counts"],
            },
            ensure_ascii=False,
        )
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    promote_parser = subparsers.add_parser("promote")
    promote_parser.add_argument("--inventory", default=str(DEFAULT_INVENTORY))
    promote_parser.add_argument("--campaign-manifest", default=str(DEFAULT_CAMPAIGN))
    promote_parser.add_argument("--representative-closure", default=str(DEFAULT_REPRESENTATIVE_CLOSURE))
    promote_parser.add_argument("--team-gap-batch", default=str(DEFAULT_TEAM_GAP_BATCH))
    promote_parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    promote_parser.add_argument("--replace-existing", action="store_true")
    promote_parser.set_defaults(handler=promote)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--manifest", default=str(DEFAULT_OUTPUT / "manifest.json"))
    check_parser.set_defaults(handler=check)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        args.handler(args)
    except PromotionError as error:
        print(f"[team-portrait-promotion] ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
