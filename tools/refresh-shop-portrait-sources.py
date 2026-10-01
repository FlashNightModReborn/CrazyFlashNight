#!/usr/bin/env python3
"""刷新商店身份来源记录；渲染输入和已发布头像必须保持原闭包。"""
from __future__ import annotations

import copy
import argparse
import ast
import importlib.util
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "launcher/web/assets/shop-portraits"


def load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def refresh_dialogue_metadata(previous: dict, updated: dict, baker, baseline_dir: Path,
                             baker_ref: str) -> None:
    """只允许未被商店调用的 bake_external 和非商店对白条目发生变化。

    对话资源的原始快照与 Git 源必须分别匹配旧 provenance；其余模块 AST、
    所有 active shop 条目与共用窗口完全一致，才更新未被消费的整文件摘要。
    图片、真正的渲染输入、原生成环境与输出证据仍由完整 validator 校验。
    """
    old_manifest_path = baseline_dir / "manifest.json"
    if baker.sha256_file(old_manifest_path) != previous["dialogueManifest"]["sha256"]:
        raise RuntimeError("Dialogue baseline does not match the bound manifest.")
    result = subprocess.run(["git", "show", f"{baker_ref}:tools/bake-dialogue-portraits.py"],
                            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    old_source = result.stdout
    if baker.sha256_bytes(old_source) != previous["toolchain"]["dialogueBaker"]["sha256"]:
        raise RuntimeError("Dialogue baker ref does not match the bound recipe.")
    source_path = ROOT / "tools/bake-dialogue-portraits.py"
    def consumed_module(source: bytes) -> str:
        tree = ast.parse(source.decode("utf-8"))
        tree.body = [node for node in tree.body
                     if not (isinstance(node, ast.FunctionDef) and node.name == "bake_external")]
        return ast.dump(tree, include_attributes=False)
    old_module = consumed_module(old_source)
    if old_module != consumed_module(source_path.read_bytes()):
        raise RuntimeError("Consumed dialogue helper code changed; rebuild portraits explicitly.")
    shop_tree = ast.parse((ROOT / "tools/bake-shop-portraits.py").read_text(encoding="utf-8"))
    helpers = {node.attr for node in ast.walk(shop_tree) if isinstance(node, ast.Attribute)
               and isinstance(node.value, ast.Name) and node.value.id == "dialogue_baker"}
    if "bake_external" in helpers:
        raise RuntimeError("Shop portraits consume the changed external-dialogue baker.")
    old_manifest = json.loads(old_manifest_path.read_text(encoding="utf-8"))
    manifest_path = ROOT / "launcher/web/assets/dialogue-portraits/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for key in ("schema", "zoom", "baseSize", "portraitWindow", "sourceAuthority"):
        if old_manifest[key] != manifest[key]:
            raise RuntimeError(f"Consumed dialogue manifest contract changed: {key}")
    active, _ = baker.read_active_shops(ROOT)
    for shop_id in active:
        if old_manifest["entries"].get(shop_id) != manifest["entries"].get(shop_id):
            raise RuntimeError(f"Consumed dialogue portrait changed: {shop_id}")
    updated["dialogueManifest"] = baker.artifact(manifest_path, ROOT)
    updated["toolchain"]["dialogueBaker"] = baker.artifact(source_path, ROOT)
    updated["dialogueMetadataRefresh"] = {
        "mode": "unconsumed-dialogue-metadata-only",
        "tool": baker.artifact(Path(__file__).resolve(), ROOT),
        "previousManifestSha256": previous["dialogueManifest"]["sha256"],
        "previousBakerSha256": previous["toolchain"]["dialogueBaker"]["sha256"],
        "consumedModuleAstSha256": baker.sha256_bytes(old_module.encode("utf-8")),
        "unchangedShopDialogueHelpers": sorted(helpers),
        "unchangedShopEntries": len(active),
    }


def refresh(dialogue_baseline_dir: Path | None = None, dialogue_baker_ref: str = "HEAD") -> None:
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
    if previous_source == source and dialogue_baseline_dir is None:
        validator.validate_provenance(active, entries)
        print("Shop portrait sources unchanged; complete existing closure verified.")
        return
    updated = copy.deepcopy(previous)
    if previous_source != source:
        updated["activeShopSource"] = source
        updated["shopSourceRefresh"] = {
            "mode": "shop-id-metadata-only",
            "tool": baker.artifact(Path(__file__).resolve(), ROOT),
            "previousActiveSourceSha256": baker.sha256_bytes(baker.canonical_json(previous_source)),
        }
    if dialogue_baseline_dir is not None:
        refresh_dialogue_metadata(previous, updated, baker, dialogue_baseline_dir, dialogue_baker_ref)
    # 既有商店来源刷新记录继续绑定当前工具；输出与渲染输入仍须通过下面的完整检查。
    if "shopSourceRefresh" in updated:
        updated["shopSourceRefresh"]["tool"] = baker.artifact(Path(__file__).resolve(), ROOT)
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
    print(f"Shop portrait source metadata refreshed; all {len(entries)} portraits and runtime manifest preserved.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dialogue-baseline-dir", type=Path)
    parser.add_argument("--dialogue-baker-ref", default="HEAD")
    args = parser.parse_args()
    refresh(args.dialogue_baseline_dir, args.dialogue_baker_ref)
