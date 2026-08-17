#!/usr/bin/env python3
"""Validate the promoted ShopPortraits asset closure without invoking FFDec."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Iterable

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
ASSET_ROOT = ROOT / "launcher" / "web" / "assets" / "shop-portraits"
MANIFEST_PATH = ASSET_ROOT / "manifest.json"
PROVENANCE_PATH = ASSET_ROOT / "provenance.json"
RECEIPT_PATH = ASSET_ROOT / "promotion-receipt.json"
SUBJECTS_ROOT = ASSET_ROOT / "subjects"
SHOP_LIST_PATH = ROOT / "data" / "shops" / "list.xml"

MANIFEST_SCHEMA = "cf7-shop-portraits-v1"
PROVENANCE_SCHEMA = "cf7-shop-portrait-provenance-v1"
RECEIPT_SCHEMA = "cf7-shop-portrait-promotion-receipt-v1"
GEOMETRY = {"width": 256, "height": 256}
EXPECTED_LIST_COUNT = 35
EXPECTED_ACTIVE_COUNT = 34
EXCLUDED_SHOP = "幸存老兵-暂时停用"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
URI_RE = re.compile(r"^subjects/([0-9a-f]{64})\.png$")


class CheckError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CheckError(message)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise CheckError(f"Invalid {label}: {path}: {error}") from error
    require(isinstance(value, dict), f"{label} must be an object")
    return value


def is_identity(value: Any, max_units: int = 80) -> bool:
    return (
        isinstance(value, str)
        and bool(value)
        and value.strip() == value
        and not value.isspace()
        and value.casefold() != "undefined"
        and len(value.encode("utf-16-le")) // 2 <= max_units
        and not any(unicodedata.category(char) == "Cc" for char in value)
    )


def validate_identity_contract() -> None:
    generator_path = ROOT / "tools" / "bake-shop-portraits.py"
    spec = importlib.util.spec_from_file_location("cf7_shop_portrait_baker_contract", generator_path)
    require(spec is not None and spec.loader is not None, "Cannot load ShopPortraits baker contract")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    generator_identity = getattr(module, "is_identity", None)
    require(callable(generator_identity), "ShopPortraits baker has no Identity(80) validator")

    valid = ["Andy Law", "迷之盔甲君", "a" * 80, "😀" * 40]
    invalid: list[Any] = [
        None,
        1,
        "",
        " ",
        chr(0x3000),
        " leading",
        "trailing ",
        chr(0xA0) + "leading",
        "trailing" + chr(0xA0),
        "inside" + chr(0x09) + "control",
        chr(0x00) + "nul",
        chr(0x1F) + "c0",
        chr(0x7F) + "del",
        chr(0x80) + "c1",
        "c1" + chr(0x9F),
        "undefined",
        "UnDeFiNeD",
        "a" * 81,
        "😀" * 41,
    ]
    for value in valid:
        require(is_identity(value) and generator_identity(value), f"Identity(80) rejected valid value: {value!r}")
    for value in invalid:
        require(not is_identity(value) and not generator_identity(value), f"Identity(80) accepted invalid value: {value!r}")


def active_shop_ids() -> list[str]:
    require(SHOP_LIST_PATH.is_file(), f"Missing shop list: {SHOP_LIST_PATH}")
    try:
        root = ET.parse(SHOP_LIST_PATH).getroot()
    except ET.ParseError as error:
        raise CheckError(f"Invalid shop list XML: {error}") from error
    all_ids: list[str] = []
    for node in root.iter("shops"):
        relative = (node.text or "").strip()
        relative_path = Path(relative)
        require(relative and not relative_path.is_absolute() and ".." not in relative_path.parts, f"Unsafe shop path: {relative!r}")
        document_path = (ROOT / "data" / "shops" / relative_path).resolve()
        try:
            document_path.relative_to((ROOT / "data" / "shops").resolve())
        except ValueError as error:
            raise CheckError(f"Shop path escapes data/shops: {relative!r}") from error
        document = read_json(document_path, "shop document")
        shop_id = document.get("shopId")
        require(is_identity(shop_id), f"Invalid shopId in {document_path}: {shop_id!r}")
        all_ids.append(shop_id)
    require(len(all_ids) == EXPECTED_LIST_COUNT, f"Shop list count drift: {len(all_ids)}")
    require(len(set(all_ids)) == EXPECTED_LIST_COUNT, "Shop list contains duplicate shopId")
    require(all_ids.count(EXCLUDED_SHOP) == 1, "Disabled-shop exclusion drift")
    active = [shop_id for shop_id in all_ids if shop_id != EXCLUDED_SHOP]
    require(len(active) == EXPECTED_ACTIVE_COUNT and len(set(active)) == EXPECTED_ACTIVE_COUNT, "Active-shop closure drift")
    return active


def alpha_bounds(path: Path) -> dict[str, int]:
    try:
        with Image.open(path) as image:
            require(image.format == "PNG", f"Subject is not PNG: {path.name}")
            require(image.size == (256, 256), f"Subject geometry drift: {path.name} -> {image.size}")
            require(image.mode == "RGBA", f"Subject mode drift: {path.name} -> {image.mode}")
            bbox = image.getchannel("A").getbbox()
    except (OSError, ValueError) as error:
        raise CheckError(f"Invalid subject image {path}: {error}") from error
    require(bbox is not None, f"Subject alpha is empty: {path.name}")
    left, top, right, bottom = bbox
    return {"x": left, "y": top, "width": right - left, "height": bottom - top}


def subject_closure(entries: dict[str, dict[str, Any]]) -> str:
    lines = [f"{shop_id}\0{entry['uri']}\0{entry['sha256']}" for shop_id, entry in sorted(entries.items())]
    return sha256_bytes(("\n".join(lines) + "\n").encode("utf-8"))


def artifact_records(value: Any) -> Iterable[dict[str, Any]]:
    if isinstance(value, dict):
        if {"path", "sha256", "bytes"}.issubset(value):
            yield value
        for child in value.values():
            yield from artifact_records(child)
    elif isinstance(value, list):
        for child in value:
            yield from artifact_records(child)


def validate_artifact(record: dict[str, Any]) -> None:
    relative = record.get("path")
    digest = record.get("sha256")
    size = record.get("bytes")
    require(isinstance(relative, str) and relative and "\\" not in relative, f"Invalid artifact path: {relative!r}")
    require(SHA256_RE.fullmatch(digest or "") is not None, f"Invalid artifact SHA: {relative}")
    require(isinstance(size, int) and size >= 0, f"Invalid artifact size: {relative}")
    path = (ROOT / relative).resolve()
    try:
        path.relative_to(ROOT)
    except ValueError as error:
        raise CheckError(f"Artifact escapes project root: {relative}") from error
    require(path.is_file(), f"Missing provenance artifact: {relative}")
    require(path.stat().st_size == size, f"Artifact size drift: {relative}")
    require(sha256_file(path) == digest, f"Artifact SHA drift: {relative}")


def validate_manifest(active: list[str]) -> tuple[dict[str, dict[str, Any]], int]:
    manifest = read_json(MANIFEST_PATH, "ShopPortraits manifest")
    require(set(manifest) == {"schema", "geometry", "entries"}, f"Manifest core keys drift: {sorted(manifest)}")
    require(manifest.get("schema") == MANIFEST_SCHEMA, "Manifest schema drift")
    require(manifest.get("geometry") == GEOMETRY, "Manifest geometry drift")
    entries = manifest.get("entries")
    require(isinstance(entries, dict), "Manifest entries must be an object")
    require(list(entries) == active, "Manifest entries must exactly follow active shop list order")
    require(len(entries) == EXPECTED_ACTIVE_COUNT, f"Manifest coverage drift: {len(entries)}")

    referenced: set[str] = set()
    total_bytes = 0
    for shop_id, entry in entries.items():
        require(is_identity(shop_id), f"Invalid manifest shopId: {shop_id!r}")
        require(isinstance(entry, dict), f"Manifest entry is not an object: {shop_id}")
        require(set(entry) == {"uri", "width", "height", "bounds", "sha256"}, f"Manifest entry keys drift: {shop_id}")
        require(entry.get("width") == 256 and entry.get("height") == 256, f"Entry geometry drift: {shop_id}")
        uri = entry.get("uri")
        match = URI_RE.fullmatch(uri or "")
        require(match is not None, f"Invalid content-addressed URI: {shop_id} -> {uri!r}")
        require(entry.get("sha256") == match.group(1), f"URI/SHA mismatch: {shop_id}")
        require(uri not in referenced, f"Shop subjects must be one-to-one: {shop_id} -> {uri}")
        referenced.add(uri)
        subject_path = ASSET_ROOT / uri
        require(subject_path.is_file(), f"Missing subject: {shop_id} -> {uri}")
        require(sha256_file(subject_path) == entry["sha256"], f"Subject SHA drift: {shop_id}")
        bounds = entry.get("bounds")
        require(isinstance(bounds, dict) and set(bounds) == {"x", "y", "width", "height"}, f"Bounds shape drift: {shop_id}")
        require(all(isinstance(bounds[key], int) for key in bounds), f"Bounds must be integers: {shop_id}")
        require(bounds["x"] >= 0 and bounds["y"] >= 0 and bounds["width"] > 0 and bounds["height"] > 0, f"Invalid bounds: {shop_id}")
        require(bounds["x"] + bounds["width"] <= 256 and bounds["y"] + bounds["height"] <= 256, f"Bounds escape canvas: {shop_id}")
        require(alpha_bounds(subject_path) == bounds, f"Alpha-bounds drift: {shop_id}")
        total_bytes += subject_path.stat().st_size

    files = {f"subjects/{path.name}" for path in SUBJECTS_ROOT.glob("*.png") if path.is_file()}
    require(files == referenced, f"Subject-file closure drift: missing={sorted(referenced - files)} extra={sorted(files - referenced)}")
    require(len(files) == EXPECTED_ACTIVE_COUNT, f"Subject-file count drift: {len(files)}")
    return entries, total_bytes


def validate_provenance(active: list[str], entries: dict[str, dict[str, Any]]) -> dict[str, Any]:
    provenance = read_json(PROVENANCE_PATH, "ShopPortraits provenance")
    require(provenance.get("schema") == PROVENANCE_SCHEMA, "Provenance schema drift")
    require(provenance.get("generatorVersion") == "1.0.0", "Generator version drift")
    require(provenance.get("geometry") == {**GEOMETRY, "padding": 16, "fit": "alpha-bounds-contain-center"}, "Provenance geometry drift")
    require(provenance.get("sourcePartition") == {"externalDialogue": 31, "internalDialogue": 2, "exactXflSwfPilot": 1}, "Source partition drift")
    require(provenance.get("dialogueManifest", {}).get("path") == "launcher/web/assets/dialogue-portraits/manifest.json", "Dialogue manifest provenance drift")

    toolchain = provenance.get("toolchain")
    require(isinstance(toolchain, dict), "Toolchain provenance is missing")
    require(toolchain.get("generator", {}).get("path") == "tools/bake-shop-portraits.py", "Generator path drift")
    require(toolchain.get("dialogueBaker", {}).get("path") == "tools/bake-dialogue-portraits.py", "Dialogue baker path drift")
    require(isinstance(toolchain.get("python"), str) and toolchain["python"], "Python version is missing")
    require(isinstance(toolchain.get("pillow"), str) and toolchain["pillow"], "Pillow version is missing")
    require(toolchain.get("ffdecVersion") == "21.1.1", "FFDec version drift")

    active_source = provenance.get("activeShopSource")
    require(isinstance(active_source, dict), "Active-shop source provenance is missing")
    require(active_source.get("listedCount") == 35 and active_source.get("activeCount") == 34, "Active-shop counts drift")
    require(active_source.get("excludedShopIds") == [EXCLUDED_SHOP], "Active-shop exclusion drift")

    sources = provenance.get("sources")
    require(isinstance(sources, dict) and list(sources) == active, "Provenance source closure/order drift")
    kinds = {"external-dialogue-swf": 0, "dialogue-ui-linkage": 0, "exact-xfl-swf-pilot": 0}
    for shop_id, source in sources.items():
        require(isinstance(source, dict), f"Invalid source record: {shop_id}")
        kind = source.get("kind")
        require(kind in kinds, f"Unsupported source kind: {shop_id} -> {kind!r}")
        kinds[kind] += 1
        require(SHA256_RE.fullmatch(source.get("extractedPngSha256") or "") is not None, f"Invalid extracted PNG SHA: {shop_id}")
        require(source.get("output") == entries[shop_id], f"Provenance/output mismatch: {shop_id}")
    require(kinds == {"external-dialogue-swf": 31, "dialogue-ui-linkage": 2, "exact-xfl-swf-pilot": 1}, f"Source-kind count drift: {kinds}")

    weapon = sources.get("武器大师", {})
    require(
        {
            "kind": weapon.get("kind"),
            "sourceSwf": weapon.get("sourceSwf", {}).get("path"),
            "sourceXfl": weapon.get("sourceXfl", {}).get("path"),
            "linkage": weapon.get("linkage"),
            "characterId": weapon.get("characterId"),
            "declaredFrameCount": weapon.get("declaredFrameCount"),
            "xflFrameIndex": weapon.get("xflFrameIndex"),
            "frame1Based": weapon.get("frame1Based"),
            "duration": weapon.get("duration"),
        }
        == {
            "kind": "dialogue-ui-linkage",
            "sourceSwf": "flashswf/UI/对话框界面.swf",
            "sourceXfl": "flashswf/UI/对话框界面/LIBRARY/对话框肖像.xml",
            "linkage": "对话框肖像",
            "characterId": 981,
            "declaredFrameCount": 262,
            "xflFrameIndex": 256,
            "frame1Based": 257,
            "duration": 6,
        },
        "Weapon Master current-source closure drift",
    )

    heeho = sources.get("heeho君", {})
    require(
        {
            "kind": heeho.get("kind"),
            "sourceSwf": heeho.get("sourceSwf", {}).get("path"),
            "mapLinkage": heeho.get("mapLinkage"),
            "mapCharacterId": heeho.get("mapCharacterId"),
            "outerLibraryItem": heeho.get("outerLibraryItem"),
            "outerCharacterId": heeho.get("outerCharacterId"),
            "outerDeclaredFrameCount": heeho.get("outerDeclaredFrameCount"),
            "bodyLibraryItem": heeho.get("bodyLibraryItem"),
            "characterId": heeho.get("characterId"),
            "declaredFrameCount": heeho.get("declaredFrameCount"),
            "xflNeutralFrameIndex": heeho.get("xflNeutralFrameIndex"),
            "frame1Based": heeho.get("frame1Based"),
            "identityAccessories": heeho.get("identityAccessories"),
            "ordinaryJackAlias": heeho.get("ordinaryJackAlias"),
        }
        == {
            "kind": "exact-xfl-swf-pilot",
            "sourceSwf": "flashswf/levels/地图-彩蛋地图.swf",
            "mapLinkage": "地图-彩蛋地图",
            "mapCharacterId": 381,
            "outerLibraryItem": "NPC/NPC-heeho君/NPC-heeho君",
            "outerCharacterId": 270,
            "outerDeclaredFrameCount": 10,
            "bodyLibraryItem": "NPC/NPC-heeho君/霜精",
            "characterId": 268,
            "declaredFrameCount": 37,
            "xflNeutralFrameIndex": 0,
            "frame1Based": 1,
            "identityAccessories": ["NPC/NPC-heeho君/零件/带帽霜精头", "NPC/NPC-heeho君/零件/墨镜"],
            "ordinaryJackAlias": False,
        },
        "heeho exact XFL/SWF closure drift",
    )

    records = list(artifact_records(provenance))
    require(len(records) >= 40, f"Provenance artifact coverage unexpectedly small: {len(records)}")
    for record in records:
        validate_artifact(record)
    return provenance


def validate_receipt(entries: dict[str, dict[str, Any]]) -> None:
    receipt = read_json(RECEIPT_PATH, "ShopPortraits promotion receipt")
    require(set(receipt) == {"schema", "promotionOrder", "subjectsFirst", "manifestLast", "shopCount", "subjectFileCount", "subjectClosureSha256", "provenanceSha256", "manifestSha256"}, "Promotion receipt keys drift")
    require(receipt.get("schema") == RECEIPT_SCHEMA, "Promotion receipt schema drift")
    require(receipt.get("promotionOrder") == ["subjects", "provenance.json", "promotion-receipt.json", "manifest.json"], "Promotion order drift")
    require(receipt.get("subjectsFirst") is True and receipt.get("manifestLast") is True, "Promotion ordering guarantees are missing")
    require(receipt.get("shopCount") == 34 and receipt.get("subjectFileCount") == 34, "Promotion closure count drift")
    require(receipt.get("subjectClosureSha256") == subject_closure(entries), "Subject closure SHA drift")
    require(receipt.get("provenanceSha256") == sha256_file(PROVENANCE_PATH), "Provenance receipt SHA drift")
    require(receipt.get("manifestSha256") == sha256_file(MANIFEST_PATH), "Manifest receipt SHA drift")


def main() -> None:
    try:
        validate_identity_contract()
        active = active_shop_ids()
        entries, subject_bytes = validate_manifest(active)
        validate_provenance(active, entries)
        validate_receipt(entries)
        tree_bytes = sum(path.stat().st_size for path in ASSET_ROOT.rglob("*") if path.is_file())
        print(
            json.dumps(
                {
                    "status": "passed",
                    "schema": MANIFEST_SCHEMA,
                    "listedShops": 35,
                    "activeShops": len(entries),
                    "subjects": len(entries),
                    "subjectBytes": subject_bytes,
                    "assetTreeBytes": tree_bytes,
                    "weaponMaster": {"characterId": 981, "frame1Based": 257},
                    "heeho": {"characterId": 268, "frame1Based": 1},
                    "subjectsFirst": True,
                    "manifestLast": True,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
    except CheckError as error:
        raise SystemExit(f"shop portrait asset check failed: {error}") from error


if __name__ == "__main__":
    main()
