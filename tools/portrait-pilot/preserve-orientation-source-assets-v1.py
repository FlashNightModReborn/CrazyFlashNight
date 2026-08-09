#!/usr/bin/env python3
"""Preserve immutable source-production portrait assets after orientation promotion."""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = Path(__file__).with_name("promote-enemy-portraits-v1.py")


class PreserveError(RuntimeError):
    pass


def load_controller() -> Any:
    spec = importlib.util.spec_from_file_location("cf7_orientation_source_asset_preserver", CONTROLLER)
    if spec is None or spec.loader is None:
        raise PreserveError("无法加载通用头像 promotion controller")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


E = load_controller()
T = E.T


def expected_assets() -> dict[Path, dict[str, Any]]:
    closure = E.load_orientation_closure()
    source_manifest_path = T.verify_artifact_record(
        closure["receipt"]["inputs"]["sourceProductionManifest"], "方向审计源生产 manifest"
    )
    manifest = T.load_json(source_manifest_path, "方向审计源生产 manifest")
    result: dict[Path, dict[str, Any]] = {}
    bindings = 0
    for entry in manifest.get("entries", {}).values():
        for variant in entry.get("variants", {}).values():
            if variant.get("status") != "human_accepted":
                continue
            for kind in ("svg", "pngFallback"):
                record = variant.get("subject", {}).get(kind)
                url = record.get("url") if isinstance(record, dict) else None
                if not isinstance(url, str) or not url.startswith("assets/enemy-portraits/subjects/"):
                    raise PreserveError(f"方向审计源生产资产 URL 非法：{url}")
                target = (T.WEB_ROOT / url).resolve()
                try:
                    target.relative_to(T.DEFAULT_OUTPUT.resolve())
                except ValueError as error:
                    raise PreserveError(f"方向审计源生产资产越界：{target}") from error
                bindings += 1
                existing = result.get(target)
                if existing is not None and existing.get("sha256") != record.get("sha256"):
                    raise PreserveError(f"内容寻址文件名碰撞：{target.name}")
                result[target] = record
    if bindings != 434 or len(result) != 432:
        raise PreserveError(f"方向审计源资产计数漂移：bindings={bindings} unique={len(result)}")
    return result


def verify_file(path: Path, record: dict[str, Any], label: str) -> None:
    if (
        not path.is_file()
        or path.stat().st_size != record.get("bytes")
        or T.sha256_file(path) != record.get("sha256")
    ):
        raise PreserveError(f"{label}字节闭包漂移：{path}")


def backup_root(value: str) -> Path:
    resolved = (ROOT / value).resolve()
    expected_root = (T.PILOT_ROOT / "enemy-portrait-production-backups").resolve()
    try:
        relative = resolved.relative_to(expected_root)
    except ValueError as error:
        raise PreserveError("backup 必须位于 enemy-portrait-production-backups") from error
    if not relative.parts or not resolved.is_dir():
        raise PreserveError("backup 不存在或指向备份根")
    return resolved


def restore(backup: Path) -> dict[str, int]:
    assets = expected_assets()
    restored = 0
    existing = 0
    for target, record in assets.items():
        if target.exists():
            verify_file(target, record, "现有历史资产")
            existing += 1
            continue
        relative = target.relative_to(T.DEFAULT_OUTPUT.resolve())
        source = backup / relative
        verify_file(source, record, "回滚备份资产")
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as output:
            output.write(source.read_bytes())
        verify_file(target, record, "恢复后的历史资产")
        restored += 1
    return {"expectedUnique": len(assets), "existing": existing, "restored": restored}


def check() -> dict[str, int]:
    assets = expected_assets()
    for target, record in assets.items():
        verify_file(target, record, "保留的历史资产")
    return {"expectedUnique": len(assets), "verified": len(assets)}


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    restore_parser = sub.add_parser("restore")
    restore_parser.add_argument("--backup", required=True)
    sub.add_parser("check")
    args = parser.parse_args()
    try:
        if args.command == "restore":
            counts = restore(backup_root(args.backup))
            status = "orientation_source_assets_restored"
        else:
            counts = check()
            status = "orientation_source_assets_verified"
    except (PreserveError, T.PromotionError, OSError, ValueError, KeyError) as error:
        print(f"[orientation-source-assets] ERROR: {error}")
        return 1
    print(json.dumps({"status": status, "counts": counts}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
