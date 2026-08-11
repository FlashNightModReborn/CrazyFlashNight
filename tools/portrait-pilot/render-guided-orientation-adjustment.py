#!/usr/bin/env python3
"""Apply a frozen human orientation instruction after a frozen human crop."""

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
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
REPORT_SCHEMA = "cf7.portrait-pilot-guided-orientation-render-report.v1"
REPORT_NAME = "guided-orientation-render-report.json"
ORIENTATION_NOTE = re.compile(r"方向反转|头朝右|头朝左|朝向|翻转")


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


def run_json(command: list[str], label: str) -> dict[str, object]:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
    )
    if completed.returncode != 0:
        raise core.PilotError(f"{label}失败：{completed.stderr.strip() or completed.stdout.strip()}")
    try:
        result = json.loads(completed.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as error:
        raise core.PilotError(f"{label}没有返回合法 JSON") from error
    if not isinstance(result, dict):
        raise core.PilotError(f"{label}返回值必须是对象")
    return result


def verify_review_batch(batch_root: Path) -> tuple[dict[str, object], dict[str, object], dict[str, object], dict[str, object]]:
    verifier = run_json(
        [
            "node",
            str(ROOT / "tools" / "portrait-pilot" / "verify-review-decisions.js"),
            "--batch",
            core.repo_rel(batch_root),
            "--check",
        ],
        "人审回执验证",
    )
    review_data = load_json(batch_root / "review-data.json", "review data")
    decisions = load_json(batch_root / "portrait-pilot-review-decisions.json", "review decisions")
    receipt = load_json(batch_root / "human-review-receipt.json", "human review receipt")
    if verifier.get("receiptDigest") != receipt.get("receiptDigest"):
        raise core.PilotError("人审 Node verifier 与回执摘要不一致")
    return review_data, decisions, receipt, verifier


def verify_guidance_batch(batch_root: Path) -> tuple[dict[str, object], dict[str, object], dict[str, object], dict[str, object]]:
    verifier = run_json(
        [
            "node",
            str(ROOT / "tools" / "portrait-pilot" / "verify-framing-guidance.js"),
            "--batch",
            core.repo_rel(batch_root),
            "--check",
        ],
        "框选指导回执验证",
    )
    data = load_json(batch_root / "framing-guidance-data.json", "framing guidance data")
    guidance = load_json(batch_root / "portrait-pilot-framing-guidance.json", "framing guidance")
    receipt = load_json(batch_root / "human-framing-guidance-receipt.json", "framing guidance receipt")
    if verifier.get("receiptDigest") != receipt.get("receiptDigest"):
        raise core.PilotError("框选 Node verifier 与回执摘要不一致")
    return data, guidance, receipt, verifier


def guided_report_path(value: str) -> Path:
    resolved = ensure_pilot_child(Path(value), "人工框选渲染", allow_existing=True)
    return resolved / "human-framing-render-report.json" if resolved.is_dir() else resolved


def verify_guided_report(path: Path) -> tuple[dict[str, object], dict[str, object]]:
    if path.name != "human-framing-render-report.json":
        raise core.PilotError("人工框选渲染必须指向批次目录或 human-framing-render-report.json")
    report = load_json(path, "human framing render report")
    check = run_json(
        [
            sys.executable,
            str(ROOT / "tools" / "portrait-pilot" / "render-framing-guidance.py"),
            "check",
            "--output",
            core.repo_rel(path.parent),
        ],
        "人工框选渲染验证",
    )
    if check.get("reportDigest") != report.get("reportDigest"):
        raise core.PilotError("人工框选渲染 verifier 与 reportDigest 不一致")
    return report, check


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
    image.save(path, format="PNG", optimize=False, compress_level=9)


def render_adjustment(args: argparse.Namespace) -> None:
    review_root = ensure_pilot_child(Path(args.review_batch), "人审批次", allow_existing=True)
    guidance_root = ensure_pilot_child(Path(args.guidance_batch), "框选指导批次", allow_existing=True)
    guided_path = guided_report_path(args.guided_render)
    output_root = ensure_pilot_child(Path(args.output), "输出目录")
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.batch_id) is None:
        raise core.PilotError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")

    review_data, decisions, review_receipt, review_verifier = verify_review_batch(review_root)
    guidance_data, guidance, guidance_receipt, guidance_verifier = verify_guidance_batch(guidance_root)
    guided_report, guided_verifier = verify_guided_report(guided_path)

    parent = guidance_data.get("parent")
    if not isinstance(parent, dict):
        raise core.PilotError("框选指导缺 parent 绑定")
    expected_parent = {
        "batchId": review_data.get("batchId"),
        "sourceDigest": review_data.get("sourceDigest"),
        "reviewDigest": review_data.get("reviewDigest"),
        "receiptDigest": review_receipt.get("receiptDigest"),
    }
    if any(parent.get(key) != value for key, value in expected_parent.items()):
        raise core.PilotError("框选指导与人审批次绑定不一致")
    if guidance_receipt.get("parentReceiptDigest") != review_receipt.get("receiptDigest"):
        raise core.PilotError("框选指导回执没有绑定目标人审回执")
    expected_guided = {
        "guidanceBatchId": guidance_data.get("batchId"),
        "guidanceDigest": guidance_data.get("guidanceDigest"),
        "parentReceiptDigest": review_receipt.get("receiptDigest"),
        "framingGuidanceReceiptDigest": guidance_receipt.get("receiptDigest"),
    }
    if any(guided_report.get(key) != value for key, value in expected_guided.items()):
        raise core.PilotError("人工框选渲染没有精确绑定框选指导与人审回执")

    review_key = args.review_key
    decision = decisions.get("decisions", {}).get(review_key)
    if not isinstance(decision, dict) or decision.get("status") != "adjustment":
        raise core.PilotError("方向变换只接受冻结的 adjustment 行")
    notes = decision.get("notes")
    if not isinstance(notes, str) or ORIENTATION_NOTE.search(notes) is None:
        raise core.PilotError("人工备注没有明确方向修正")
    guidance_entry = guidance.get("guidance", {}).get(review_key)
    if not isinstance(guidance_entry, dict):
        raise core.PilotError("reviewKey 不在冻结框选指导中")
    guidance_item = next((item for item in guidance_data.get("items", []) if item.get("reviewKey") == review_key), None)
    if not isinstance(guidance_item, dict):
        raise core.PilotError("reviewKey 不在框选指导数据中")
    guided_row = next((row for row in guided_report.get("rows", []) if row.get("reviewKey") == review_key), None)
    if not isinstance(guided_row, dict):
        raise core.PilotError("reviewKey 不在人工框选渲染中")
    if guided_row.get("humanGuidance") != guidance_entry:
        raise core.PilotError("人工框选渲染行与冻结框选数据不一致")
    selected = guided_row.get("selectedChoice")
    if not isinstance(selected, dict):
        raise core.PilotError("人工框选渲染行缺 selectedChoice")
    expected_choice = next(
        (
            choice
            for choice in guidance_item.get("choices", [])
            if choice.get("sourceRole") == guidance_entry.get("sourceRole")
            and choice.get("candidateId") == guidance_entry.get("candidateId")
            and choice.get("sourceCandidate", {}).get("sha256") == guidance_entry.get("sourceCandidateSha256")
        ),
        None,
    )
    if not isinstance(expected_choice, dict):
        raise core.PilotError("冻结框选所选候选不在 guidance choices")
    for key in ("sourceRole", "candidateId", "frame", "sourceCandidate", "sourceHighResolution"):
        if selected.get(key) != expected_choice.get(key):
            raise core.PilotError(f"人工框选渲染 selectedChoice.{key} 与指导数据不一致")

    source_path = core.verify_artifact_record(guided_row["sourceSupersample"], "人工框选 source supersample")
    parent_master_path = core.verify_artifact_record(guided_row["master"], "人工框选 parent master")
    output_root.mkdir(parents=True)
    render_root = output_root / "guided-orientation-adjusted" / str(guided_row["reviewCode"])
    render_root.mkdir(parents=True)
    with Image.open(source_path) as source_image:
        transformed = source_image.convert("RGBA").transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        supersample_path = render_root / "source-supersample-flip-x.png"
        save_png(transformed, supersample_path)
        master = transformed.resize((512, 512), Image.Resampling.LANCZOS)
        master_path = render_root / "master-512.png"
        save_png(master, master_path)
        previews: dict[str, dict[str, object]] = {}
        for size in (80, 48, 32):
            preview_path = render_root / f"preview-{size}.png"
            save_png(master.resize((size, size), Image.Resampling.LANCZOS), preview_path)
            previews[str(size)] = core.artifact(preview_path)
        webp_path = render_root / "preview-80-lossless.webp"
        master.resize((80, 80), Image.Resampling.LANCZOS).save(
            webp_path,
            format="WEBP",
            lossless=True,
            method=6,
        )
    with Image.open(parent_master_path) as parent_master_image, Image.open(master_path) as adjusted_master_image:
        expected = parent_master_image.convert("RGBA").transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        fidelity = premultiplied_rgba_mae(expected, adjusted_master_image.convert("RGBA"))
    if fidelity > 1e-9:
        raise core.PilotError(f"翻转后派生结果与人工框选 master 镜像不一致：MAE={fidelity}")

    row = {
        "reviewCode": guided_row["reviewCode"],
        "reviewKey": review_key,
        "portraitRef": guided_row["portraitRef"],
        "variantKey": guided_row["variantKey"],
        "humanDecision": {
            "status": decision["status"],
            "notes": notes,
            "updatedAt": decision["updatedAt"],
        },
        "humanGuidance": guidance_entry,
        "selectedChoice": selected,
        "operation": "flip_x_after_human_crop",
        "sourceSupersample": guided_row["sourceSupersample"],
        "parentMaster": guided_row["master"],
        "outputSupersample": core.artifact(supersample_path),
        "master": core.artifact(master_path),
        "previews": previews,
        "webp80Lossless": core.artifact(webp_path),
        "fidelityComparison": {
            "metric": "premultiplied RGBA mean absolute error against horizontally mirrored human-guided master",
            "meanAbsoluteError": fidelity,
            "limit": 1e-9,
            "passed": True,
        },
    }
    report = {
        "schema": REPORT_SCHEMA,
        "status": "human_guided_orientation_adjustment_checked",
        "productionReady": False,
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "batchId": args.batch_id,
        "parentBatchId": review_data["batchId"],
        "sourceDigest": review_data["sourceDigest"],
        "reviewDigest": review_data["reviewDigest"],
        "humanReviewReceiptDigest": review_receipt["receiptDigest"],
        "guidanceBatchId": guidance_data["batchId"],
        "guidanceDigest": guidance_data["guidanceDigest"],
        "humanFramingGuidanceReceiptDigest": guidance_receipt["receiptDigest"],
        "guidedRenderBatchId": guided_report["batchId"],
        "guidedRenderReportDigest": guided_report["reportDigest"],
        "inputs": {
            "reviewData": core.artifact(review_root / "review-data.json"),
            "decisions": core.artifact(review_root / "portrait-pilot-review-decisions.json"),
            "humanReviewReceipt": core.artifact(review_root / "human-review-receipt.json"),
            "guidanceData": core.artifact(guidance_root / "framing-guidance-data.json"),
            "guidance": core.artifact(guidance_root / "portrait-pilot-framing-guidance.json"),
            "humanFramingGuidanceReceipt": core.artifact(guidance_root / "human-framing-guidance-receipt.json"),
            "guidedRenderReport": core.artifact(guided_path),
            "reviewVerifier": review_verifier,
            "guidanceVerifier": guidance_verifier,
            "guidedRenderVerifier": guided_verifier,
        },
        "renderer": {
            "controllerSource": core.artifact(Path(__file__)),
            "python": sys.version.split()[0],
            "pillow": PILLOW_VERSION,
            "operation": "flip_x_after_human_crop",
            "pixelSource": "frozen human-guided high-resolution source supersample",
            "modelRerun": False,
        },
        "rows": [row],
        "gates": {
            "explicitHumanOrientationNoteBound": True,
            "frozenHumanGuidanceBound": True,
            "guidedRenderDigestBound": True,
            "highResolutionHumanCropReused": True,
            "allDerivedSizesRegenerated": True,
            "modelRerun": False,
            "productionWrites": False,
        },
    }
    report["reportDigest"] = core.sha256_bytes(core.stable_bytes(report))
    report_path = output_root / REPORT_NAME
    core.write_json(report_path, report)
    print(
        json.dumps(
            {
                "status": report["status"],
                "report": core.repo_rel(report_path),
                "reportDigest": report["reportDigest"],
                "rows": 1,
                "fidelityMeanAbsoluteError": fidelity,
            },
            ensure_ascii=False,
        )
    )


def check_adjustment(args: argparse.Namespace) -> None:
    output_root = ensure_pilot_child(Path(args.output), "输出目录", allow_existing=True)
    report_path = output_root / REPORT_NAME
    report = load_json(report_path, "人工框选后方向变换报告")
    if report.get("schema") != REPORT_SCHEMA or report.get("status") != "human_guided_orientation_adjustment_checked":
        raise core.PilotError("人工框选后方向变换报告 schema 或状态非法")
    if report.get("productionReady") is not False or report.get("gates", {}).get("productionWrites") is not False:
        raise core.PilotError("人工框选后方向变换 production gate 非法")
    envelope = dict(report)
    digest = envelope.pop("reportDigest", None)
    if digest != core.sha256_bytes(core.stable_bytes(envelope)):
        raise core.PilotError("人工框选后方向变换 reportDigest 不匹配")
    artifact_count = 0
    for record in report.get("inputs", {}).values():
        if isinstance(record, dict) and {"path", "bytes", "sha256"}.issubset(record):
            core.verify_artifact_record(record, "人工框选后方向变换输入")
            artifact_count += 1
    core.verify_artifact_record(report["renderer"]["controllerSource"], "人工框选后方向变换 controller")
    artifact_count += 1
    rows = report.get("rows")
    if not isinstance(rows, list) or len(rows) != 1:
        raise core.PilotError("人工框选后方向变换必须精确包含一行")
    for row in rows:
        fidelity = row.get("fidelityComparison", {})
        if (
            row.get("operation") != "flip_x_after_human_crop"
            or fidelity.get("passed") is not True
            or float(fidelity.get("meanAbsoluteError", 1.0)) > float(fidelity.get("limit", 0.0))
        ):
            raise core.PilotError("人工框选后方向变换行未通过")
        for record in (
            row["selectedChoice"]["sourceCandidate"],
            row["selectedChoice"]["sourceHighResolution"],
            row["sourceSupersample"],
            row["parentMaster"],
            row["outputSupersample"],
            row["master"],
            row["webp80Lossless"],
            *row["previews"].values(),
        ):
            core.verify_artifact_record(record, "人工框选后方向变换输出")
            artifact_count += 1
    print(
        json.dumps(
            {
                "status": "human_guided_orientation_adjustment_verified",
                "reportDigest": report["reportDigest"],
                "rows": len(rows),
                "artifactCount": artifact_count,
            },
            ensure_ascii=False,
        )
    )


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    render_parser = commands.add_parser("render")
    render_parser.add_argument("--review-batch", required=True)
    render_parser.add_argument("--guidance-batch", required=True)
    render_parser.add_argument("--guided-render", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.add_argument("--review-key", required=True)
    render_parser.set_defaults(handler=render_adjustment)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--output", required=True)
    check_parser.set_defaults(handler=check_adjustment)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (core.PilotError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"portrait guided orientation error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
