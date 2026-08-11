#!/usr/bin/env python3
"""Build or verify the committed, clean-checkout enemy portrait evidence pack."""

from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import lzma
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PACK_PATH = Path(__file__).with_name("evidence") / "enemy-portrait-evidence-pack-v1.json"
RAW_SUPPLEMENT_PATH = PACK_PATH.with_name("enemy-portrait-evidence-raw-supplement-v1.json")
PILOT_PREFIX = "tmp/portrait-pilot/"
SUBJECT_ROOT = ROOT / "launcher" / "web" / "assets" / "enemy-portraits" / "subjects"
GENERATOR_PATH = Path(__file__).resolve()

SUPPLEMENTAL_RAW_PATHS = (
    "tmp/portrait-pilot/campaign-framing-r3-20260806T043659Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-framing-r8-chunk1-20260806T051538Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-framing-r8-chunk2-20260806T051538Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r106-r103-crop-only-20260807T114600Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r127-r125-adjustments-clamped-20260808T001143Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r152-r151-qitian-adjustment-20260808T030700Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r18-r16-adjustments-20260806T074741Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r185-r184-adjustments-20260809T090100Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r24-r22-all-adjustments-20260806T082340Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r31-r29-all-adjustments-20260806T091916Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r37-r35-all-adjustments-20260806T102030Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r45-r42-all-adjustments-20260806T110457Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r53-r52-all-adjustments-20260806T122503Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r63-r62-all-adjustments-20260806T135712Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r82-r80-adjustments-20260807T075500Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guidance-r94-r90-crop-only-20260807T101600Z/framing-guidance-data.json",
    "tmp/portrait-pilot/p3-human-framing-hires-r11-20260806T024409Z/framing-guidance-data.json",
    "tmp/portrait-pilot/campaign-guided-render-r186-r185-adjustments-20260809T091000Z/human-guided-renders/ISR-06/master-512.png",
    "tmp/portrait-pilot/campaign-guided-render-r186-r185-adjustments-20260809T091000Z/human-guided-renders/ISR-07/master-512.png",
    "tmp/portrait-pilot/campaign-guided-render-r186-r185-adjustments-20260809T091000Z/human-guided-renders/ISR-14/master-512.png",
)

OPERATIONAL_COPY_PATHS = {
    "tmp/portrait-pilot/arena-supplemental-promotion-r219-final6-20260809T170000Z/base-manifest.json",
    "tmp/portrait-pilot/arena-supplemental-promotion-r219-final6-20260809T170000Z/base-promotion-receipt.json",
}

UNSELECTED_DERIVED_MASTER_PATHS = {
    "tmp/portrait-pilot/campaign-guided-render-r128-r127-6-20260808T001608Z/human-guided-renders/R19/master-512.png",
    "tmp/portrait-pilot/campaign-render-r83-r82-human-guided-20260807T082200Z/human-guided-renders/R07/master-512.png",
    "tmp/portrait-pilot/campaign-shard-r125-v16-review-ready-24-20260807T235231Z/renders-v1/independent_review/R17/master-512.png",
    "tmp/portrait-pilot/campaign-shard-r80-v13-localization-20260807T004500Z/renders-v1/independent_review/R11/master-512.png",
}

SUPPLEMENTAL_SELECTED_MASTER_PATHS = {
    "tmp/portrait-pilot/arena-direct-gap-localization-r215-five-fast3-20260809T211500Z/renders-v1/proposal/R01/master-512.png",
    "tmp/portrait-pilot/arena-direct-gap-localization-r215-five-fast3-20260809T211500Z/renders-v1/proposal/R02/master-512.png",
    "tmp/portrait-pilot/arena-direct-gap-localization-r215-five-fast3-20260809T211500Z/renders-v1/proposal/R03/master-512.png",
    "tmp/portrait-pilot/arena-direct-gap-localization-r215-five-fast3-20260809T211500Z/renders-v1/proposal/R04/master-512.png",
    "tmp/portrait-pilot/arena-direct-gap-orientation-r217-r215-home-robot-20260809T162700Z/orientation-adjusted/R05/master-512.png",
}

RAW_CAPTURE_PATHS = SUPPLEMENTAL_RAW_PATHS + tuple(sorted(SUPPLEMENTAL_SELECTED_MASTER_PATHS))

TRACKED_PROVENANCE_PATHS = {
    "tools/portrait-pilot/build-orientation-human-review-v1.js",
    "tools/portrait-pilot/promote-arena-portrait-supplement-v1.py",
    "tools/portrait-pilot/record-orientation-human-review-v1.js",
    "tools/portrait-pilot/verify-orientation-human-decisions-v1.js",
}


class EvidenceBuildError(RuntimeError):
    pass


def stable_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def artifact(path: Path) -> dict[str, Any]:
    value = path.read_bytes()
    return {
        "path": path.resolve().relative_to(ROOT).as_posix(),
        "bytes": len(value),
        "sha256": sha256_bytes(value),
    }


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def decode_archive(descriptor: Any, label: str) -> dict[str, bytes]:
    if not isinstance(descriptor, dict) or descriptor.get("encoding") != "sha256-base64-json+xz+base64":
        raise EvidenceBuildError(f"{label} encoding 非法")
    try:
        compressed = base64.b64decode("".join(descriptor.get("dataChunks", [])), validate=True)
    except (TypeError, ValueError) as error:
        raise EvidenceBuildError(f"{label} base64 非法") from error
    if len(compressed) != descriptor.get("compressedBytes") or sha256_bytes(compressed) != descriptor.get("compressedSha256"):
        raise EvidenceBuildError(f"{label} 压缩字节漂移")
    try:
        plain = lzma.decompress(compressed)
        encoded = json.loads(plain.decode("utf-8"))
    except (lzma.LZMAError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceBuildError(f"{label} 解压失败") from error
    if len(plain) != descriptor.get("uncompressedBytes") or not isinstance(encoded, dict):
        raise EvidenceBuildError(f"{label} 长度/结构漂移")
    result: dict[str, bytes] = {}
    for digest, value in encoded.items():
        try:
            blob = base64.b64decode(value, validate=True)
        except (TypeError, ValueError) as error:
            raise EvidenceBuildError(f"{label} blob base64 非法：{digest}") from error
        if sha256_bytes(blob) != digest:
            raise EvidenceBuildError(f"{label} blob sha256 漂移：{digest}")
        result[digest] = blob
    return result


def encode_archive(blobs: dict[str, bytes]) -> dict[str, Any]:
    encoded = {digest: base64.b64encode(blobs[digest]).decode("ascii") for digest in sorted(blobs)}
    plain = json.dumps(encoded, sort_keys=True, separators=(",", ":")).encode("utf-8")
    compressed = lzma.compress(plain, format=lzma.FORMAT_XZ, preset=9)
    value = base64.b64encode(compressed).decode("ascii")
    return {
        "encoding": "sha256-base64-json+xz+base64",
        "uncompressedBytes": len(plain),
        "compressedBytes": len(compressed),
        "compressedSha256": sha256_bytes(compressed),
        "dataChunks": [value[index : index + 4096] for index in range(0, len(value), 4096)],
    }


def decode_inline_blobs(pack: dict[str, Any]) -> dict[str, bytes]:
    result: dict[str, bytes] = {}
    for digest, descriptor in pack.get("inlineArtifacts", {}).items():
        if not isinstance(descriptor, dict) or descriptor.get("encoding") != "base64":
            raise EvidenceBuildError(f"inline artifact 非法：{digest}")
        blob = base64.b64decode(descriptor.get("data", ""), validate=True)
        if len(blob) != descriptor.get("bytes") or sha256_bytes(blob) != digest:
            raise EvidenceBuildError(f"inline artifact 漂移：{digest}")
        result[digest] = blob
    return result


def collect_derived_master_paths(
    pack: dict[str, Any], records_by_path: dict[str, dict[str, Any]], primary_blobs: dict[str, bytes]
) -> list[str]:
    json_blobs = {**primary_blobs, **decode_inline_blobs(pack)}
    candidates: set[str] = set()

    def visit(value: Any) -> None:
        if isinstance(value, dict):
            if {"path", "bytes", "sha256"}.issubset(value):
                path_value = value.get("path")
                digest = value.get("sha256")
                if (
                    isinstance(path_value, str)
                    and isinstance(value.get("bytes"), int)
                    and isinstance(digest, str)
                    and path_value.startswith(PILOT_PREFIX)
                    and Path(path_value).name == "master-512.png"
                    and path_value not in records_by_path
                ):
                    basis = SUBJECT_ROOT / f"{digest[:24].lower()}.png"
                    if basis.is_file():
                        blob = basis.read_bytes()
                        if len(blob) == value["bytes"] and sha256_bytes(blob) == digest:
                            candidates.add(path_value)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    for record in records_by_path.values():
        if Path(record["path"]).suffix.lower() != ".json" or record["path"] in RAW_CAPTURE_PATHS:
            continue
        blob = json_blobs.get(record["sha256"])
        if blob is None:
            continue
        try:
            visit(json.loads(blob.decode("utf-8")))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise EvidenceBuildError(f"JSON evidence 不可读：{record['path']}") from error
    if len(candidates) != 215 or not UNSELECTED_DERIVED_MASTER_PATHS.issubset(candidates):
        raise EvidenceBuildError(
            f"derived master 候选漂移：count={len(candidates)} missingExcluded={sorted(UNSELECTED_DERIVED_MASTER_PATHS - candidates)}"
        )
    selected = candidates - UNSELECTED_DERIVED_MASTER_PATHS
    if len(selected) != 211 or SUPPLEMENTAL_SELECTED_MASTER_PATHS.intersection(selected):
        raise EvidenceBuildError("derived master 精确选择集漂移")
    return sorted(selected)


def check() -> dict[str, Any]:
    pack = json.loads(PACK_PATH.read_text(encoding="utf-8"))
    clone = copy.deepcopy(pack)
    digest = clone.pop("packDigest", None)
    if not isinstance(digest, str) or sha256_bytes(stable_bytes(clone)) != digest:
        raise EvidenceBuildError("evidence pack digest 漂移")
    if pack.get("producer") != artifact(GENERATOR_PATH):
        raise EvidenceBuildError("evidence pack producer 漂移")
    if pack.get("supplementalRawArchive") != artifact(RAW_SUPPLEMENT_PATH):
        raise EvidenceBuildError("evidence raw supplement artifact 漂移")
    sidecar = json.loads(RAW_SUPPLEMENT_PATH.read_text(encoding="utf-8"))
    sidecar_clone = copy.deepcopy(sidecar)
    sidecar_digest = sidecar_clone.pop("archiveDigest", None)
    if (
        sidecar.get("schema") != "cf7.enemy-portrait-evidence-raw-archive.v1"
        or sidecar.get("status") != "immutable_lossless_evidence"
        or not isinstance(sidecar_digest, str)
        or sha256_bytes(stable_bytes(sidecar_clone)) != sidecar_digest
    ):
        raise EvidenceBuildError("evidence raw supplement digest/schema 漂移")
    supplemental_blobs = decode_archive(sidecar.get("archive"), "supplemental raw archive")
    records_by_path = {record["path"]: record for record in pack.get("records", [])}
    supplemental_records = [records_by_path.get(path) for path in RAW_CAPTURE_PATHS]
    if any(not isinstance(record, dict) for record in supplemental_records):
        raise EvidenceBuildError("supplemental raw record 缺失")
    expected_digests = {record["sha256"] for record in supplemental_records if isinstance(record, dict)}
    if set(supplemental_blobs) != expected_digests:
        raise EvidenceBuildError("supplemental raw blob exact-set 漂移")
    for record in supplemental_records:
        assert isinstance(record, dict)
        blob = supplemental_blobs[record["sha256"]]
        if len(blob) != record["bytes"] or sha256_bytes(blob) != record["sha256"]:
            raise EvidenceBuildError(f"supplemental raw record 漂移：{record['path']}")
    if OPERATIONAL_COPY_PATHS.intersection(records_by_path):
        raise EvidenceBuildError("operational copies 不得进入 immutable evidence")
    for path in TRACKED_PROVENANCE_PATHS:
        if records_by_path.get(path) != artifact(ROOT / path):
            raise EvidenceBuildError(f"tracked provenance record 漂移：{path}")
    derived = pack.get("derivedMasterPaths")
    if not isinstance(derived, list) or len(derived) != 211 or len(set(derived)) != 211:
        raise EvidenceBuildError("derivedMasterPaths exact-set 漂移")
    if UNSELECTED_DERIVED_MASTER_PATHS.intersection(derived):
        raise EvidenceBuildError("未选择 master 进入 derivedMasterPaths")
    return {
        "status": "enemy_portrait_evidence_pack_verified",
        "packDigest": digest,
        "artifactPaths": len(records_by_path),
        "derivedMasterRecords": len(derived),
        "supplementalRawBlobs": len(supplemental_blobs),
    }


def build() -> dict[str, Any]:
    pack = json.loads(PACK_PATH.read_text(encoding="utf-8"))
    pack.pop("packDigest", None)
    pack.pop("supplementalRawArchive", None)
    pack.pop("derivedMasterPaths", None)
    pack.pop("producer", None)

    records_by_path = {record["path"]: copy.deepcopy(record) for record in pack.get("records", [])}
    if len(records_by_path) != len(pack.get("records", [])):
        raise EvidenceBuildError("原 evidence records 路径重复")
    primary_blobs = decode_archive(pack.get("rawArchive"), "primary raw archive")
    present_operational_paths = OPERATIONAL_COPY_PATHS.intersection(records_by_path)
    if present_operational_paths not in (set(), OPERATIONAL_COPY_PATHS):
        raise EvidenceBuildError(
            f"operational record 只存在部分，拒绝迁移：{sorted(present_operational_paths)}"
        )
    for path in present_operational_paths:
        record = records_by_path.pop(path)
        primary_blobs.pop(record["sha256"], None)

    if not TRACKED_PROVENANCE_PATHS.issubset(records_by_path):
        raise EvidenceBuildError("tracked provenance records 缺失")
    for path in sorted(TRACKED_PROVENANCE_PATHS):
        previous = records_by_path[path]
        current = artifact(ROOT / path)
        if previous != current:
            if not any(
                other_path != path and record.get("sha256") == previous["sha256"]
                for other_path, record in records_by_path.items()
            ):
                primary_blobs.pop(previous["sha256"], None)
            primary_blobs[current["sha256"]] = (ROOT / path).read_bytes()
            records_by_path[path] = current

    supplemental_blobs: dict[str, bytes] = {}
    for path in RAW_CAPTURE_PATHS:
        source = ROOT / path
        if not source.is_file():
            raise EvidenceBuildError(f"构建 evidence 缺原始输入：{path}")
        blob = source.read_bytes()
        digest = sha256_bytes(blob)
        records_by_path[path] = {"path": path, "bytes": len(blob), "sha256": digest}
        supplemental_blobs[digest] = blob
    if len(supplemental_blobs) != len(RAW_CAPTURE_PATHS):
        raise EvidenceBuildError("supplemental raw 输入发生 digest 重复")

    binary_reconstructions = pack.get("binaryReconstructions", {})
    pack["binaryReconstructions"] = {
        digest: descriptor
        for digest, descriptor in binary_reconstructions.items()
        if isinstance(descriptor, dict) and descriptor.get("encoding") == "identity-committed-file-v1"
    }
    if len(pack["binaryReconstructions"]) != 3:
        raise EvidenceBuildError("identity binary reconstruction 数漂移")

    pack["rawArchive"] = encode_archive(primary_blobs)
    pack["records"] = [records_by_path[path] for path in sorted(records_by_path)]
    pack["derivedMasterPaths"] = collect_derived_master_paths(pack, records_by_path, primary_blobs)

    sidecar: dict[str, Any] = {
        "schema": "cf7.enemy-portrait-evidence-raw-archive.v1",
        "status": "immutable_lossless_evidence",
        "artifactCount": len(supplemental_blobs),
        "archive": encode_archive(supplemental_blobs),
    }
    sidecar["archiveDigest"] = sha256_bytes(stable_bytes(sidecar))
    write_json(RAW_SUPPLEMENT_PATH, sidecar)

    pack["producer"] = artifact(GENERATOR_PATH)
    pack["supplementalRawArchive"] = artifact(RAW_SUPPLEMENT_PATH)
    pack["counts"] = {
        "artifactPaths": len(records_by_path),
        "rawBlobs": len(primary_blobs) + len(supplemental_blobs),
        "supplementalRawBlobs": len(supplemental_blobs),
        "inlineBlobs": len(pack.get("inlineArtifacts", {})),
        "binaryReconstructedBlobs": len(pack["binaryReconstructions"]),
        "derivedMasterRecords": len(pack["derivedMasterPaths"]),
        "reconstructedSvgBlobs": len(pack.get("svgReconstructions", {})),
        "preservedSubjects": len(pack.get("preservedSubjects", [])),
    }
    pack["packDigest"] = sha256_bytes(stable_bytes(pack))
    write_json(PACK_PATH, pack)
    return check()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build", "check"))
    args = parser.parse_args()
    result = build() if args.command == "build" else check()
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
