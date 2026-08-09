#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, __version__ as PILLOW_VERSION

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
REPORT_SCHEMA = "cf7.portrait-pilot-orientation-render-report.v1"


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


def verify_review_batch(batch_root: Path) -> tuple[dict[str, object], dict[str, object], dict[str, object], dict[str, object]]:
    command = [
        "node",
        str(ROOT / "tools" / "portrait-pilot" / "verify-review-decisions.js"),
        "--batch",
        core.repo_rel(batch_root),
        "--check",
    ]
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=60)
    if completed.returncode != 0:
        raise core.PilotError(f"人审回执验证失败：{completed.stderr.strip() or completed.stdout.strip()}")
    review_data = load_json(batch_root / "review-data.json", "review data")
    decisions = load_json(batch_root / "portrait-pilot-review-decisions.json", "review decisions")
    receipt = load_json(batch_root / "human-review-receipt.json", "human review receipt")
    render_report = load_json(batch_root / "render-report.json", "parent render report")
    verifier_result = json.loads(completed.stdout.strip().splitlines()[-1])
    if verifier_result.get("receiptDigest") != receipt.get("receiptDigest"):
        raise core.PilotError("Node verifier 回执摘要与文件不一致")
    return review_data, decisions, receipt, render_report


def premultiplied_rgba_mae(left: Image.Image, right: Image.Image) -> float:
    if left.size != right.size:
        raise core.PilotError("方向变换 fidelity 图片尺寸不一致")
    left_rgba = left.convert("RGBA")
    right_rgba = right.convert("RGBA")
    total = 0.0
    count = left_rgba.width * left_rgba.height * 4
    for left_pixel, right_pixel in zip(left_rgba.getdata(), right_rgba.getdata(), strict=True):
        left_alpha = left_pixel[3] / 255.0
        right_alpha = right_pixel[3] / 255.0
        total += abs(left_pixel[0] * left_alpha - right_pixel[0] * right_alpha)
        total += abs(left_pixel[1] * left_alpha - right_pixel[1] * right_alpha)
        total += abs(left_pixel[2] * left_alpha - right_pixel[2] * right_alpha)
        total += abs(left_pixel[3] - right_pixel[3])
    return total / count


def save_png(image: Image.Image, path: Path) -> None:
    image.save(path, format="PNG", optimize=True)


def render_adjustment(args: argparse.Namespace) -> None:
    source_root = ensure_pilot_child(Path(args.source_batch), "来源批次", allow_existing=True)
    output_root = ensure_pilot_child(Path(args.output), "输出目录")
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.batch_id) is None:
        raise core.PilotError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")
    review_data, decisions, receipt, render_report = verify_review_batch(source_root)
    review_key = args.review_key
    decision = decisions.get("decisions", {}).get(review_key)
    if not isinstance(decision, dict) or decision.get("status") != "adjustment":
        raise core.PilotError("方向变换只接受冻结的 adjustment 行")
    notes = decision.get("notes")
    if not isinstance(notes, str) or re.search(r"方向反转|头朝右|头朝左|朝向", notes) is None:
        raise core.PilotError("人工备注没有明确方向修正")
    review_item = next((item for item in review_data.get("items", []) if item.get("reviewKey") == review_key), None)
    if not isinstance(review_item, dict):
        raise core.PilotError("reviewKey 不在 review data")
    role = args.source_role
    proposal = review_item.get("proposals", {}).get(role)
    if not isinstance(proposal, dict):
        raise core.PilotError(f"来源角色不存在：{role}")
    report_row = next(
        (row for row in render_report.get("rows", []) if row.get("reviewKey") == review_key and row.get("role") == role),
        None,
    )
    if not isinstance(report_row, dict) or report_row.get("master") != proposal.get("master"):
        raise core.PilotError("review data 与 parent render report 的来源角色不闭合")
    source_supersample_path = core.verify_artifact_record(report_row["sourceSupersample"], "方向变换 source supersample")
    parent_master_path = core.verify_artifact_record(report_row["master"], "方向变换 parent master")
    output_root.mkdir(parents=True)
    render_root = output_root / "orientation-adjusted" / str(review_item["reviewCode"])
    render_root.mkdir(parents=True)
    with Image.open(source_supersample_path) as source_image:
        source = source_image.convert("RGBA")
        transformed = source.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        supersample_path = render_root / "source-supersample-flip-x.png"
        save_png(transformed, supersample_path)
        master = transformed.resize((512, 512), Image.Resampling.LANCZOS)
        master_path = render_root / "master-512.png"
        save_png(master, master_path)
        previews: dict[str, dict[str, object]] = {}
        for size in (80, 48, 32):
            preview = transformed.resize((size, size), Image.Resampling.LANCZOS)
            preview_path = render_root / f"preview-{size}.png"
            save_png(preview, preview_path)
            previews[str(size)] = core.artifact(preview_path)
        webp_path = render_root / "preview-80-lossless.webp"
        transformed.resize((80, 80), Image.Resampling.LANCZOS).save(webp_path, format="WEBP", lossless=True, method=6)
    with Image.open(parent_master_path) as parent_master_image, Image.open(master_path) as adjusted_master_image:
        expected = parent_master_image.convert("RGBA").transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        fidelity = premultiplied_rgba_mae(expected, adjusted_master_image.convert("RGBA"))
    if fidelity > 1e-9:
        raise core.PilotError(f"水平翻转后重新派生与 parent master 镜像不一致：MAE={fidelity}")
    row = {
        "reviewCode": review_item["reviewCode"],
        "reviewKey": review_key,
        "portraitRef": review_item["portraitRef"],
        "variantKey": review_item["variantKey"],
        "humanDecision": {
            "status": decision["status"],
            "notes": notes,
            "updatedAt": decision["updatedAt"],
        },
        "sourceRole": role,
        "candidateId": proposal["candidateId"],
        "frame": proposal["frame"],
        "operation": "flip_x",
        "sourceSupersample": report_row["sourceSupersample"],
        "parentMaster": report_row["master"],
        "outputSupersample": core.artifact(supersample_path),
        "master": core.artifact(master_path),
        "previews": previews,
        "webp80Lossless": core.artifact(webp_path),
        "fidelityComparison": {
            "metric": "premultiplied RGBA mean absolute error against horizontally mirrored parent master",
            "meanAbsoluteError": fidelity,
            "limit": 1e-9,
            "passed": True,
        },
    }
    report = {
        "schema": REPORT_SCHEMA,
        "status": "human_orientation_adjustment_checked",
        "productionReady": False,
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "batchId": args.batch_id,
        "parentBatchId": review_data["batchId"],
        "sourceDigest": review_data["sourceDigest"],
        "reviewDigest": review_data["reviewDigest"],
        "humanReviewReceiptDigest": receipt["receiptDigest"],
        "inputs": {
            "reviewData": core.artifact(source_root / "review-data.json"),
            "decisions": core.artifact(source_root / "portrait-pilot-review-decisions.json"),
            "humanReviewReceipt": core.artifact(source_root / "human-review-receipt.json"),
            "parentRenderReport": core.artifact(source_root / "render-report.json"),
        },
        "renderer": {
            "controllerSource": core.artifact(Path(__file__)),
            "python": sys.version.split()[0],
            "pillow": PILLOW_VERSION,
            "operation": "flip_x",
            "pixelSource": "parent deterministic high-resolution source supersample",
            "modelRerun": False,
        },
        "rows": [row],
        "gates": {
            "explicitHumanOrientationNoteBound": True,
            "defaultProposalRoleUsedWithoutUnstatedPreference": role == "proposal",
            "highResolutionSourceReused": True,
            "allDerivedSizesRegenerated": True,
            "modelRerun": False,
            "productionWrites": False,
        },
    }
    report["reportDigest"] = core.sha256_bytes(core.stable_bytes(report))
    report_path = output_root / "orientation-render-report.json"
    core.write_json(report_path, report)
    print(json.dumps({"status": report["status"], "report": core.repo_rel(report_path), "reportDigest": report["reportDigest"], "rows": 1, "fidelityMeanAbsoluteError": fidelity}, ensure_ascii=False))


def check_adjustment(args: argparse.Namespace) -> None:
    output_root = ensure_pilot_child(Path(args.output), "输出目录", allow_existing=True)
    report_path = output_root / "orientation-render-report.json"
    report = load_json(report_path, "方向变换报告")
    if report.get("schema") != REPORT_SCHEMA or report.get("status") != "human_orientation_adjustment_checked":
        raise core.PilotError("方向变换报告 schema 或状态非法")
    envelope = dict(report)
    digest = envelope.pop("reportDigest", None)
    if digest != core.sha256_bytes(core.stable_bytes(envelope)):
        raise core.PilotError("方向变换 reportDigest 不匹配")
    artifact_count = 0
    for record in (*report["inputs"].values(), report["renderer"]["controllerSource"]):
        core.verify_artifact_record(record, "方向变换输入")
        artifact_count += 1
    for row in report["rows"]:
        if row.get("operation") != "flip_x" or not row.get("fidelityComparison", {}).get("passed"):
            raise core.PilotError("方向变换行未通过")
        for record in (
            row["sourceSupersample"],
            row["parentMaster"],
            row["outputSupersample"],
            row["master"],
            row["webp80Lossless"],
            *row["previews"].values(),
        ):
            core.verify_artifact_record(record, "方向变换输出")
            artifact_count += 1
    print(json.dumps({"status": "human_orientation_adjustment_verified", "reportDigest": report["reportDigest"], "rows": len(report["rows"]), "artifactCount": artifact_count}, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--source-batch", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.add_argument("--review-key", required=True)
    render_parser.add_argument("--source-role", choices=("proposal", "independent_review"), default="proposal")
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.command == "render":
        render_adjustment(args)
    else:
        check_adjustment(args)


if __name__ == "__main__":
    try:
        main()
    except (core.PilotError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
