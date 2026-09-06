#!/usr/bin/env python3
"""刷新商店身份来源记录；渲染输入和已发布头像必须保持原闭包。"""
from __future__ import annotations

import copy
import importlib.util
import shutil
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "launcher/web/assets/shop-portraits"


def load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def refresh() -> None:
    baker = load("shop_source_baker", "bake-shop-portraits.py")
    validator = load("shop_source_validator", "test-shop-portrait-assets.py")
    active, source = baker.read_active_shops(ROOT)
    validator.validate_identity_contract()
    entries, _ = validator.validate_manifest(active)
    validator.validate_receipt(entries)
    previous = baker.read_json(ASSETS / "provenance.json", "portrait provenance")
    previous_source = previous["activeShopSource"]
    # 商店 JSON 在已绑定版本的 read_active_shops 中只贡献 shopId。
    # 身份顺序、清单文件与文档路径不能借刷新入口发生变化。
    if any(previous_source[key] != source[key] for key in
           ("list", "listedCount", "activeCount", "excludedShopIds")):
        raise RuntimeError("Shop list identity changed; rebuild portraits explicitly.")
    if [item["path"] for item in previous_source["shopDocuments"]] != [item["path"] for item in source["shopDocuments"]]:
        raise RuntimeError("Shop document paths changed; rebuild portraits explicitly.")
    if previous_source == source:
        validator.validate_provenance(active, entries)
        print("Shop portrait sources unchanged; complete existing closure verified.")
        return
    updated = copy.deepcopy(previous)
    updated["activeShopSource"] = source
    updated["shopSourceRefresh"] = {
        "mode": "shop-id-metadata-only",
        "tool": baker.artifact(Path(__file__).resolve(), ROOT),
        "previousActiveSourceSha256": baker.sha256_bytes(baker.canonical_json(previous_source)),
    }
    receipt = baker.read_json(ASSETS / "promotion-receipt.json", "portrait receipt")
    receipt["provenanceSha256"] = baker.sha256_bytes(baker.canonical_json(updated))
    temporary_root = (ROOT / "tmp").resolve()
    temporary_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="shop-source-refresh-", dir=temporary_root) as directory:
        stage = Path(directory).resolve()
        if not stage.is_relative_to(temporary_root):
            raise RuntimeError("Temporary portrait directory escaped the workspace.")
        shutil.copytree(ASSETS / "subjects", stage / "subjects")
        shutil.copyfile(ASSETS / "manifest.json", stage / "manifest.json")
        (stage / "provenance.json").write_bytes(baker.canonical_json(updated))
        (stage / "promotion-receipt.json").write_bytes(baker.canonical_json(receipt))
        validator.ASSET_ROOT = stage
        validator.MANIFEST_PATH = stage / "manifest.json"
        validator.PROVENANCE_PATH = stage / "provenance.json"
        validator.RECEIPT_PATH = stage / "promotion-receipt.json"
        # 复用完整校验：不跳过任何 SWF、XFL、渲染器、工具或图片摘要。
        validator.validate_manifest(active)
        validator.validate_provenance(active, entries)
        validator.validate_receipt(entries)
        baker.promote_stage(stage, ASSETS)
        baker.compare_tree(stage, ASSETS)
    print("Shop portrait source metadata refreshed; all 34 portraits and runtime manifest preserved.")


if __name__ == "__main__":
    refresh()
