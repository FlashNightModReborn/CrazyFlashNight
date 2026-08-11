#!/usr/bin/env python3
"""Render frozen human framing guidance directly from bound FFDec high-resolution frames."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, __version__ as PILLOW_VERSION

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
REPORT_SCHEMA = "cf7.portrait-pilot-human-framing-render-report.v1"


def load_json(path: Path, label: str) -> dict[str, object]:
    if not path.is_file():
        raise core.PilotError(f"{label} 缺失：{path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise core.PilotError(f"{label} 不是合法 JSON：{error}") from error
    if not isinstance(value, dict):
        raise core.PilotError(f"{label} 顶层必须是对象")
    return value


def ensure_pilot_child(path: Path, label: str, allow_existing: bool = False) -> Path:
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise core.PilotError(f"{label} 必须位于 tmp/portrait-pilot 下") from error
    if not relative.parts:
        raise core.PilotError(f"{label} 不能是 tmp/portrait-pilot 根目录")
    if resolved.exists() and not allow_existing:
        raise core.PilotError(f"{label} 已存在，禁止覆盖：{resolved}")
    return resolved


def verify_guidance_receipt(batch_root: Path) -> tuple[dict[str, object], dict[str, object], dict[str, object], dict[str, object]]:
    command = [
        "node",
        str(ROOT / "tools" / "portrait-pilot" / "verify-framing-guidance.js"),
        "--batch",
        core.repo_rel(batch_root),
        "--check",
    ]
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=60)
    if completed.returncode != 0:
        raise core.PilotError(f"框选指导回执验证失败：{completed.stderr.strip() or completed.stdout.strip()}")
    dataset = load_json(batch_root / "framing-guidance-data.json", "框选指导数据")
    guidance = load_json(batch_root / "portrait-pilot-framing-guidance.json", "框选指导")
    receipt = load_json(batch_root / "human-framing-guidance-receipt.json", "框选指导回执")
    verifier_result = json.loads(completed.stdout.strip().splitlines()[-1])
    if verifier_result.get("receiptDigest") != receipt.get("receiptDigest"):
        raise core.PilotError("Node verifier 回执摘要与文件不一致")
    return dataset, guidance, receipt, verifier_result


def normalized_guidance_crop(choice: dict[str, object], value: object) -> tuple[float, float, float, float, float]:
    if (
        not isinstance(value, list)
        or len(value) != 4
        or any(not isinstance(entry, (int, float)) or not math.isfinite(float(entry)) for entry in value)
    ):
        raise core.PilotError("人工 cropBox 必须是四个有限数字")
    x0, y0, x1, y1 = (float(entry) for entry in value)
    if not -0.5 <= x0 < x1 <= 1.5 or not -0.5 <= y0 < y1 <= 1.5:
        raise core.PilotError(f"人工 cropBox 越界或顺序错误：{value}")
    width = float(choice["candidateWidth"])
    height = float(choice["candidateHeight"])
    pixel_width = (x1 - x0) * width
    pixel_height = (y1 - y0) * height
    if abs(pixel_width - pixel_height) > 1.5:
        raise core.PilotError(f"人工 cropBox 不是像素正方形：{value}")
    side = (pixel_width + pixel_height) / 2
    minimum = max(48.0, float(choice["minimumCandidateCropSide"]), min(width, height) * 0.1)
    if side + 1e-6 < minimum:
        raise core.PilotError(f"人工 cropBox 导致高分辨率来源不足：actual={side:.3f} minimum={minimum:.3f}")
    return x0, y0, x1, y1, side


def render_guidance(args: argparse.Namespace) -> None:
    guidance_root = ensure_pilot_child(Path(args.guidance_batch), "框选指导批次", allow_existing=True)
    output_root = ensure_pilot_child(Path(args.output), "输出目录")
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.batch_id) is None:
        raise core.PilotError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")
    dataset, guidance, receipt, verifier_result = verify_guidance_receipt(guidance_root)
    render_contract = dataset.get("renderContract")
    if not isinstance(render_contract, dict):
        raise core.PilotError("框选指导缺高分辨率渲染合同")
    target_size = int(render_contract["targetSupersampleSize"])
    minimum_size = int(render_contract["minimumSourceCropSize"])
    fidelity_limit = float(render_contract["fidelityMeanAbsoluteErrorLimit"])
    items = {item["reviewKey"]: item for item in dataset["items"]}
    guidance_map = guidance.get("guidance")
    if not isinstance(guidance_map, dict) or set(guidance_map) != set(items):
        raise core.PilotError("框选指导没有覆盖全部待调整行")

    output_root.mkdir(parents=True)
    render_root = output_root / "human-guided-renders"
    rows: list[dict[str, object]] = []
    fidelity_values: list[float] = []
    for item in dataset["items"]:
        review_key = item["reviewKey"]
        entry = guidance_map[review_key]
        choice = next(
            (
                candidate
                for candidate in item["choices"]
                if candidate["sourceRole"] == entry.get("sourceRole")
                and candidate["candidateId"] == entry.get("candidateId")
                and candidate["sourceCandidate"]["sha256"] == entry.get("sourceCandidateSha256")
            ),
            None,
        )
        if choice is None:
            raise core.PilotError(f"人工框选来源角色、候选或 hash 不闭合：{review_key}")
        x0, y0, _, _, side = normalized_guidance_crop(choice, entry.get("cropBox"))
        candidate = {
            "candidateId": choice["candidateId"],
            "width": int(choice["candidateWidth"]),
            "height": int(choice["candidateHeight"]),
            "sourceSize": choice["sourceSize"],
            "sourceCropBounds": choice["sourceCropBounds"],
        }
        candidate_path = core.verify_artifact_record(choice["sourceCandidate"], f"框选候选 {review_key}")
        high_resolution_path = core.verify_artifact_record(choice["sourceHighResolution"], f"框选高分辨率帧 {review_key}")
        with Image.open(high_resolution_path) as high_resolution_image:
            high_resolution = high_resolution_image.convert("RGBA")
        with Image.open(candidate_path) as candidate_image:
            candidate_rgba = candidate_image.convert("RGBA")
        restored, source_scale = core.candidate_from_high_resolution(high_resolution, candidate)
        fidelity_mean, fidelity_channels = core.image_mean_absolute_error(restored, candidate_rgba)
        if fidelity_mean > fidelity_limit:
            raise core.PilotError(
                f"人工框选高分辨率帧保真度失败：{review_key} mean={fidelity_mean:.4f} limit={fidelity_limit:.4f}"
            )
        fidelity_values.append(fidelity_mean)
        geometry = {
            "candidateCropWindow": [
                x0 * candidate["width"],
                y0 * candidate["height"],
                side,
                side,
            ]
        }
        supersample, crop_mapping = core.crop_high_resolution_selection(
            high_resolution,
            candidate,
            geometry,
            source_scale,
            target_size,
            minimum_size,
        )
        row_root = render_root / item["reviewCode"]
        row_root.mkdir(parents=True)
        supersample_path = row_root / "source-supersample.png"
        master_path = row_root / "master-512.png"
        webp_path = row_root / "preview-80-lossless.webp"
        supersample.save(supersample_path, format="PNG", optimize=False, compress_level=9)
        master = supersample.resize((512, 512), Image.Resampling.LANCZOS)
        if master.getchannel("A").getbbox() is None:
            raise core.PilotError(f"人工框选最终头像无可见像素：{review_key}")
        master.save(master_path, format="PNG", optimize=False, compress_level=9)
        previews: dict[str, dict[str, object]] = {}
        for size_value in (80, 48, 32):
            preview_path = row_root / f"preview-{size_value}.png"
            master.resize((size_value, size_value), Image.Resampling.LANCZOS).save(
                preview_path,
                format="PNG",
                optimize=False,
                compress_level=9,
            )
            previews[str(size_value)] = core.artifact(preview_path)
        master.resize((80, 80), Image.Resampling.LANCZOS).save(
            webp_path,
            format="WEBP",
            lossless=True,
            method=6,
        )
        rows.append(
            {
                "reviewCode": item["reviewCode"],
                "reviewKey": review_key,
                "portraitRef": item["portraitRef"],
                "variantKey": item["variantKey"],
                "humanGuidance": entry,
                "selectedChoice": {
                    "sourceRole": choice["sourceRole"],
                    "candidateId": choice["candidateId"],
                    "frame": choice["frame"],
                    "sourceCandidate": choice["sourceCandidate"],
                    "sourceHighResolution": choice["sourceHighResolution"],
                },
                "cropMapping": crop_mapping,
                "fidelityComparison": {
                    "metric": "premultiplied RGBA mean absolute error",
                    "meanAbsoluteError": fidelity_mean,
                    "perChannel": {
                        "red": fidelity_channels[0],
                        "green": fidelity_channels[1],
                        "blue": fidelity_channels[2],
                        "alpha": fidelity_channels[3],
                    },
                    "limit": fidelity_limit,
                    "passed": True,
                },
                "sourceSupersample": core.artifact(supersample_path),
                "sourceSupersampleSize": supersample.width,
                "master": core.artifact(master_path),
                "previews": previews,
                "webp80Lossless": core.artifact(webp_path),
            }
        )

    report = {
        "schema": REPORT_SCHEMA,
        "status": "human_guided_automated_checked",
        "productionReady": False,
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "batchId": args.batch_id,
        "guidanceBatchId": dataset["batchId"],
        "guidanceDigest": dataset["guidanceDigest"],
        "parentReceiptDigest": dataset["parent"]["receiptDigest"],
        "framingGuidanceReceiptDigest": receipt["receiptDigest"],
        "inputs": {
            "guidanceData": core.artifact(guidance_root / "framing-guidance-data.json"),
            "guidance": core.artifact(guidance_root / "portrait-pilot-framing-guidance.json"),
            "guidanceReceipt": core.artifact(guidance_root / "human-framing-guidance-receipt.json"),
            "nodeVerifier": verifier_result,
        },
        "renderer": {
            "controllerSource": core.artifact(Path(__file__)),
            "python": sys.version.split()[0],
            "pillow": PILLOW_VERSION,
            "pixelSource": "parent FFDec FrameExporter API selected exact man frame PNG",
            "selectionSource": "digest-bound human source role and pixel-square crop",
            "targetSupersampleSize": target_size,
            "minimumSourceCropSize": minimum_size,
            "masterSize": 512,
            "previewSizes": [80, 48, 32],
            "transparent": True,
            "noModelRerun": True,
            "noUpscale": True,
        },
        "fidelitySummary": {
            "meanAbsoluteErrorLimit": fidelity_limit,
            "maximumMeanAbsoluteError": max(fidelity_values),
            "averageMeanAbsoluteError": sum(fidelity_values) / len(fidelity_values),
            "passedRows": len(fidelity_values),
        },
        "rows": rows,
        "gates": {
            "frozenHumanGuidanceBound": True,
            "exactCandidateHashBound": True,
            "pixelSquareCropChecked": True,
            "highResolutionFrameFidelityChecked": True,
            "minimumSourceCropSizeChecked": True,
            "livePreviewGeometryReproduced": True,
            "modelRerun": False,
            "productionWrites": False,
        },
    }
    report["reportDigest"] = core.sha256_bytes(core.stable_bytes(report))
    report_path = output_root / "human-framing-render-report.json"
    core.write_json(report_path, report)
    print(
        json.dumps(
            {
                "status": report["status"],
                "report": core.repo_rel(report_path),
                "reportDigest": report["reportDigest"],
                "rows": len(rows),
                "maximumFidelityMeanAbsoluteError": max(fidelity_values),
            },
            ensure_ascii=False,
        )
    )


def check_render(args: argparse.Namespace) -> None:
    output_root = ensure_pilot_child(Path(args.output), "输出目录", allow_existing=True)
    report_path = output_root / "human-framing-render-report.json"
    report = load_json(report_path, "人工框选渲染报告")
    if report.get("schema") != REPORT_SCHEMA or report.get("status") != "human_guided_automated_checked":
        raise core.PilotError("人工框选渲染报告 schema 或状态非法")
    envelope = dict(report)
    digest = envelope.pop("reportDigest", None)
    if digest != core.sha256_bytes(core.stable_bytes(envelope)):
        raise core.PilotError("人工框选渲染 reportDigest 不匹配")
    core.verify_artifact_record(report["renderer"]["controllerSource"], "人工框选 renderer source")
    for record in report["inputs"].values():
        if isinstance(record, dict) and {"path", "bytes", "sha256"}.issubset(record):
            core.verify_artifact_record(record, "人工框选输入")
    artifact_count = 1
    for row in report["rows"]:
        for record in (
            row["selectedChoice"]["sourceCandidate"],
            row["selectedChoice"]["sourceHighResolution"],
            row["sourceSupersample"],
            row["master"],
            row["webp80Lossless"],
            *row["previews"].values(),
        ):
            core.verify_artifact_record(record, f"人工框选渲染 {row['reviewKey']}")
            artifact_count += 1
    print(
        json.dumps(
            {
                "status": "human_framing_render_verified",
                "reportDigest": report["reportDigest"],
                "rows": len(report["rows"]),
                "artifactCount": artifact_count,
            },
            ensure_ascii=False,
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--guidance-batch", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.set_defaults(handler=render_guidance)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    check_parser.set_defaults(handler=check_render)
    args = parser.parse_args()
    try:
        args.handler(args)
    except (core.PilotError, subprocess.SubprocessError) as error:
        print(f"[portrait-framing-render] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
