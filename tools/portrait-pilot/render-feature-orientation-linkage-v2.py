#!/usr/bin/env python3
"""Render orientation-aware portraits while accepting a unique FFDec linkage suffix."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import sys

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
ORIENTATION_CONTROLLER = Path(__file__).with_name("render-feature-orientation-v1.py").resolve()
EXPECTED_ORIENTATION_SHA256 = "F9C70E63B100AD132AC76486B3293A34407A305A998D5CA493ECD54B3722D4BA"
MAXIMUM_ALLOWED_AXIS = 16_384


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load_orientation():
    if file_sha256(ORIENTATION_CONTROLLER) != EXPECTED_ORIENTATION_SHA256:
        raise RuntimeError("历史方向 renderer 字节漂移；拒绝运行 linkage v2 包装器")
    spec = importlib.util.spec_from_file_location("portrait_orientation_linkage_base", ORIENTATION_CONTROLLER)
    if spec is None or spec.loader is None:
        raise RuntimeError("无法加载历史方向 renderer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def install_linkage_exporter(base) -> None:
    def export_selected_sprite_frames(
        adapter,
        output_dir,
        swf_path,
        character_id,
        frames,
        zoom,
        group_id,
        attempt_tag,
    ):
        export_root = output_dir / f"selected-high-resolution-{attempt_tag}" / group_id
        if export_root.exists():
            raise base.PilotError(f"高分辨率逐帧目录已存在：{export_root}")
        frame_csv = ",".join(str(frame) for frame in frames)
        run = base.run_logged_tool(
            [
                str(adapter["java"]["path"]),
                "-cp",
                str(adapter["runtimeClasspath"]),
                "SelectedSpriteFrameExporter",
                str(swf_path),
                str(export_root),
                str(character_id),
                str(zoom),
                frame_csv,
            ],
            output_dir,
            f"{attempt_tag}-{group_id}-selected-frames",
            900,
        )
        sprite_directories = [
            child
            for child in export_root.iterdir()
            if child.is_dir() and re.fullmatch(rf"DefineSprite_{character_id}(?:_.+)?", child.name)
        ]
        if len(sprite_directories) != 1:
            raise base.PilotError(
                f"FFDec selected frame 目录不唯一：id={character_id} matches={len(sprite_directories)}"
            )
        records = {}
        for frame in frames:
            frame_path = sprite_directories[0] / f"{frame}.png"
            if not frame_path.is_file():
                raise base.PilotError(f"FFDec selected frame 缺失：id={character_id} frame={frame}")
            records[frame] = base.artifact(frame_path)
        actual_files = [child for child in export_root.rglob("*") if child.is_file()]
        if len(actual_files) != len(frames):
            raise base.PilotError(
                f"FFDec selected frame 输出不精确：id={character_id} expected={len(frames)} actual={len(actual_files)}"
            )
        return {
            **run,
            "sourceSwf": base.artifact(swf_path),
            "characterId": character_id,
            "frames": frames,
            "zoom": zoom,
            "spriteDirectory": base.repo_rel(sprite_directories[0]),
            "linkageSuffixAccepted": sprite_directories[0].name != f"DefineSprite_{character_id}",
            "outputs": [records[frame] for frame in frames],
        }, records

    base.export_selected_sprite_frames = export_selected_sprite_frames


def pilot_path(value: str, label: str, must_exist: bool) -> Path:
    path = (ROOT / value).resolve()
    try:
        path.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise RuntimeError(f"{label} 必须位于 tmp/portrait-pilot 下") from error
    if must_exist and not path.exists():
        raise RuntimeError(f"{label} 不存在：{path}")
    if not must_exist and path.exists():
        raise RuntimeError(f"{label} 已存在，禁止覆盖：{path}")
    return path


def manifest_axis(manifest: dict[str, object]) -> int:
    try:
        maximum_axis = int(manifest["featureContract"]["highResolutionRender"]["maximumSourceFrameDimension"])
    except (KeyError, TypeError, ValueError) as error:
        raise RuntimeError("manifest 缺合法 maximumSourceFrameDimension") from error
    if maximum_axis < 1 or maximum_axis > MAXIMUM_ALLOWED_AXIS:
        raise RuntimeError(f"maximumSourceFrameDimension 越界：{maximum_axis}")
    return maximum_axis


def annotate_report(base, manifest_path: Path) -> dict[str, object]:
    report_path = manifest_path.parent / "render-report.json"
    report = base.load_json(report_path)
    renderer = report.setdefault("renderer", {})
    renderer["linkageCompatibilityControllerSource"] = base.artifact(Path(__file__).resolve())
    renderer["linkageDirectoryPolicy"] = {
        "version": "unique_ffdec_define_sprite_linkage_suffix_v1",
        "acceptedPattern": "DefineSprite_<characterId>(_<linkageName>)?",
        "exactCharacterIdRequired": True,
        "uniqueDirectoryRequired": True,
        "arbitraryDirectoryFallback": False,
    }
    report.setdefault("gates", {})["uniqueLinkageSuffixCompatibilityBound"] = True
    report.pop("renderDigest", None)
    report["renderDigest"] = base.sha256_bytes(base.stable_bytes(report))
    base.write_json(report_path, report)
    return report


def annotate_bounded_retry(
    base,
    manifest_path: Path,
    maximum_axis: int,
    original_limit: int | None,
    source_manifest: Path,
    source_model: Path,
) -> dict[str, object]:
    report_path = manifest_path.parent / "render-report.json"
    report = base.load_json(report_path)
    base.verify_digest_object(report, "renderDigest", "linkage render report")
    renderer = report.setdefault("renderer", {})
    renderer["boundedLargeFrameDecode"] = {
        "controllerSource": base.artifact(Path(__file__).resolve()),
        "maximumSourceFrameDimension": maximum_axis,
        "maximumDecodedPixels": maximum_axis * maximum_axis,
        "originalPillowMaxImagePixels": original_limit,
        "scope": "fresh isolated linkage-compatible retry render process only",
        "unboundedDecode": False,
    }
    renderer["isolatedRetry"] = {
        "reason": "standard linkage-compatible renderer exceeded Pillow default pixel threshold before report creation",
        "sourceManifest": base.artifact(source_manifest),
        "sourceModelReport": base.artifact(source_model),
        "copiedInputsByteIdentical": True,
        "sourceInputsMutated": False,
    }
    report.setdefault("gates", {})["boundedLargeFrameDecode"] = True
    report["gates"]["isolatedRetryCopiedInputs"] = True
    report.pop("renderDigest", None)
    report["renderDigest"] = base.sha256_bytes(base.stable_bytes(report))
    base.write_json(report_path, report)
    return report


def verify_linkage_report(base, orientation, args: argparse.Namespace) -> dict[str, object]:
    report = orientation.verify_render(base, args)
    renderer = report.get("renderer", {})
    policy = renderer.get("linkageDirectoryPolicy", {})
    if (
        base.verify_artifact_record(
            renderer.get("linkageCompatibilityControllerSource"),
            "linkage renderer controller",
        )
        != Path(__file__).resolve()
        or policy.get("version") != "unique_ffdec_define_sprite_linkage_suffix_v1"
        or policy.get("exactCharacterIdRequired") is not True
        or policy.get("uniqueDirectoryRequired") is not True
        or policy.get("arbitraryDirectoryFallback") is not False
        or report.get("gates", {}).get("uniqueLinkageSuffixCompatibilityBound") is not True
    ):
        raise base.PilotError("linkage 目录兼容策略闭包漂移")
    return report


def render_bounded_retry(args: argparse.Namespace, orientation) -> tuple[object, dict[str, object], Path]:
    base = orientation.load_base()
    install_linkage_exporter(base)
    source_manifest = pilot_path(args.manifest, "来源 manifest", must_exist=True)
    source_model = pilot_path(args.model_report, "来源 model report", must_exist=True)
    if not source_manifest.is_file() or not source_model.is_file():
        raise RuntimeError("来源 manifest/model report 必须是文件")
    manifest = base.verify_manifest(source_manifest)
    model_report = base.load_json(source_model)
    base.verify_digest_object(model_report, "reportDigest", "model report")
    if model_report.get("sourceDigest") != manifest.get("sourceDigest"):
        raise base.PilotError("manifest/model report sourceDigest 不一致")
    output = pilot_path(args.output, "隔离输出", must_exist=False)
    output.mkdir(parents=False)
    copied_manifest = output / "candidate-manifest.json"
    copied_model = output / "model-report.json"
    shutil.copy2(source_manifest, copied_manifest)
    shutil.copy2(source_model, copied_model)
    if file_sha256(copied_manifest) != file_sha256(source_manifest) or file_sha256(copied_model) != file_sha256(source_model):
        raise RuntimeError("隔离重试输入复制不一致")
    maximum_axis = manifest_axis(manifest)
    original_limit = Image.MAX_IMAGE_PIXELS
    try:
        Image.MAX_IMAGE_PIXELS = maximum_axis * maximum_axis
        orientation.render_with_orientation(
            base,
            argparse.Namespace(manifest=str(copied_manifest), model_report=str(copied_model)),
        )
    finally:
        Image.MAX_IMAGE_PIXELS = original_limit
    annotate_report(base, copied_manifest)
    report = annotate_bounded_retry(
        base,
        copied_manifest,
        maximum_axis,
        original_limit,
        source_manifest,
        source_model,
    )
    return base, report, copied_manifest


def verify_bounded_retry(args: argparse.Namespace, orientation) -> tuple[object, dict[str, object]]:
    output = pilot_path(args.output, "隔离输出", must_exist=True)
    manifest_path = output / "candidate-manifest.json"
    model_path = output / "model-report.json"
    base = orientation.load_base()
    install_linkage_exporter(base)
    report = verify_linkage_report(
        base,
        orientation,
        argparse.Namespace(manifest=str(manifest_path), model_report=str(model_path)),
    )
    bounded = report.get("renderer", {}).get("boundedLargeFrameDecode", {})
    retry = report.get("renderer", {}).get("isolatedRetry", {})
    maximum_axis = int(bounded.get("maximumSourceFrameDimension", -1))
    if (
        maximum_axis < 1
        or maximum_axis > MAXIMUM_ALLOWED_AXIS
        or bounded.get("maximumDecodedPixels") != maximum_axis * maximum_axis
        or bounded.get("unboundedDecode") is not False
        or retry.get("copiedInputsByteIdentical") is not True
        or retry.get("sourceInputsMutated") is not False
        or report.get("gates", {}).get("boundedLargeFrameDecode") is not True
        or report.get("gates", {}).get("isolatedRetryCopiedInputs") is not True
    ):
        raise base.PilotError("linkage 大帧隔离重试边界不闭合")
    base.verify_artifact_record(bounded.get("controllerSource"), "大帧 linkage 控制器")
    base.verify_artifact_record(retry.get("sourceManifest"), "来源 manifest")
    base.verify_artifact_record(retry.get("sourceModelReport"), "来源 model report")
    return base, report


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    for name in ("render", "check"):
        command = subparsers.add_parser(name)
        command.add_argument("--manifest", required=True)
        command.add_argument("--model-report", required=True)
    bounded = subparsers.add_parser("render-bounded")
    bounded.add_argument("--manifest", required=True)
    bounded.add_argument("--model-report", required=True)
    bounded.add_argument("--output", required=True)
    bounded_check = subparsers.add_parser("check-bounded")
    bounded_check.add_argument("--output", required=True)
    subparsers.add_parser("self-test")
    return result


def main() -> None:
    args = parser().parse_args()
    orientation = load_orientation()
    if args.command == "self-test":
        orientation.self_test()
        print(json.dumps({
            "status": "linkage_orientation_renderer_self_tested",
            "historicalOrientationControllerPreserved": True,
            "uniqueLinkageSuffixOnly": True,
        }, ensure_ascii=False))
        return
    if args.command == "render-bounded":
        base, report, manifest_path = render_bounded_retry(args, orientation)
        base, report = verify_bounded_retry(argparse.Namespace(output=args.output), orientation)
        print(json.dumps({
            "status": "model_oriented_linkage_bounded_large_frame_checked",
            "report": base.repo_rel(manifest_path.parent / "render-report.json"),
            "renderDigest": report["renderDigest"],
            "rows": len(report["rows"]),
            "flipX": report["orientationSummary"]["flipX"],
            "maximumDecodedPixels": report["renderer"]["boundedLargeFrameDecode"]["maximumDecodedPixels"],
        }, ensure_ascii=False))
        return
    if args.command == "check-bounded":
        base, report = verify_bounded_retry(args, orientation)
        print(json.dumps({
            "status": "model_oriented_linkage_bounded_large_frame_verified",
            "renderDigest": report["renderDigest"],
            "rows": len(report["rows"]),
            "flipX": report["orientationSummary"]["flipX"],
            "maximumDecodedPixels": report["renderer"]["boundedLargeFrameDecode"]["maximumDecodedPixels"],
        }, ensure_ascii=False))
        return
    base = orientation.load_base()
    install_linkage_exporter(base)
    manifest_path = Path(args.manifest).resolve()
    if args.command == "render":
        orientation.render_with_orientation(base, args)
        report = annotate_report(base, manifest_path)
        report = verify_linkage_report(base, orientation, args)
        print(json.dumps({
            "status": "model_oriented_linkage_compatible_automated_checked",
            "report": base.repo_rel(manifest_path.parent / "render-report.json"),
            "renderDigest": report["renderDigest"],
            "rows": len(report["rows"]),
            "flipX": report["orientationSummary"]["flipX"],
        }, ensure_ascii=False))
    else:
        report = verify_linkage_report(base, orientation, args)
        print(json.dumps({
            "status": "model_oriented_linkage_compatible_render_verified",
            "renderDigest": report["renderDigest"],
            "rows": len(report["rows"]),
            "flipX": report["orientationSummary"]["flipX"],
        }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
