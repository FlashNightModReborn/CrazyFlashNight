#!/usr/bin/env python3
"""Bind all frozen campaign human labels into the next Luna contact sheets.

The derived manifest continues to reference the base shard's candidates and
vector sources.  It only replaces the contact sheets with fresh composites
whose lower section contains digest-bound human preference examples.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
SCHEMA = "cf7.portrait-pilot-human-preference-atlas.v1"
MODE = "bound_all_human_labels_visual_examples"


class AtlasError(RuntimeError):
    pass


def stable_bytes(value: object) -> bytes:
    def normalize(entry: object) -> object:
        if isinstance(entry, dict):
            return {key: normalize(child) for key, child in entry.items()}
        if isinstance(entry, list):
            return [normalize(child) for child in entry]
        if isinstance(entry, float) and entry.is_integer():
            return int(entry)
        return entry

    return json.dumps(
        normalize(value), ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def repo_path(value: str | Path, label: str) -> Path:
    candidate = Path(value)
    resolved = candidate.resolve() if candidate.is_absolute() else (ROOT / candidate).resolve()
    try:
        resolved.relative_to(ROOT.resolve())
    except ValueError as error:
        raise AtlasError(f"{label} 必须位于仓库内：{resolved}") from error
    return resolved


def repo_rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT.resolve()).as_posix()


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise AtlasError(f"{label} 缺失：{path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AtlasError(f"{label} 顶层必须是对象")
    return value


def write_json(path: Path, value: object) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def artifact(path: Path) -> dict[str, object]:
    checked = repo_path(path, "artifact")
    if not checked.is_file():
        raise AtlasError(f"artifact 缺失：{checked}")
    return {
        "path": repo_rel(checked),
        "bytes": checked.stat().st_size,
        "sha256": sha256_file(checked),
    }


def verify_artifact(record: object, label: str) -> Path:
    if not isinstance(record, dict):
        raise AtlasError(f"{label} artifact 不是对象")
    record_path = record.get("path")
    record_bytes = record.get("bytes")
    record_sha = record.get("sha256")
    if not isinstance(record_path, str) or not isinstance(record_bytes, int) or not isinstance(record_sha, str):
        raise AtlasError(f"{label} artifact 记录不闭合")
    path = repo_path(record_path, label)
    if not path.is_file() or path.stat().st_size != record_bytes or sha256_file(path) != record_sha:
        raise AtlasError(f"{label} artifact 字节闭包不匹配：{record_path}")
    return path


def verify_digest(value: dict[str, Any], field: str, label: str) -> None:
    expected = value.get(field)
    envelope = dict(value)
    envelope.pop(field, None)
    if not isinstance(expected, str) or sha256_bytes(stable_bytes(envelope)) != expected:
        raise AtlasError(f"{label} {field} 不匹配")


def verify_font(manifest: dict[str, Any]) -> Path:
    record = manifest.get("sourceEnvelope", {}).get("font")
    if not isinstance(record, dict) or not isinstance(record.get("path"), str):
        raise AtlasError("base manifest 缺字体证据")
    path = Path(record["path"]).resolve()
    if not path.is_file() or sha256_file(path) != record.get("sha256"):
        raise AtlasError("base manifest 字体证据漂移")
    return path


def load_reports(paths: list[str], digest_field: str, label: str) -> list[tuple[Path, dict[str, Any]]]:
    reports: list[tuple[Path, dict[str, Any]]] = []
    for raw in paths:
        path = repo_path(raw, label)
        value = load_json(path, label)
        verify_digest(value, digest_field, label)
        reports.append((path, value))
    return reports


def role_rows(render_reports: list[tuple[Path, dict[str, Any]]]) -> dict[tuple[str, str], dict[str, Any]]:
    rows: dict[tuple[str, str], dict[str, Any]] = {}
    for _path, report in render_reports:
        if report.get("status") != "automated_checked" or report.get("productionReady") is not False:
            raise AtlasError("parent render report gate 非法")
        for row in report.get("rows", []):
            key = (row.get("reviewKey"), row.get("role"))
            if not all(isinstance(part, str) for part in key) or key in rows:
                raise AtlasError(f"parent render row 重复或非法：{key}")
            verify_artifact(row.get("master"), f"parent master {key}")
            rows[key] = row
    return rows


def decision_rows(receipts: list[tuple[Path, dict[str, Any]]]) -> dict[str, dict[str, Any]]:
    decisions: dict[str, dict[str, Any]] = {}
    for _path, receipt in receipts:
        if (
            receipt.get("schema") != "cf7.portrait-pilot-human-review-receipt.v1"
            or receipt.get("productionReady") is not False
            or receipt.get("counts", {}).get("total") != len(receipt.get("decisions", []))
        ):
            raise AtlasError("human review receipt gate 非法")
        for row in receipt["decisions"]:
            key = row.get("reviewKey")
            if not isinstance(key, str) or key in decisions:
                raise AtlasError(f"human decision 重复或非法：{key}")
            decisions[key] = {**row, "parentBatchId": receipt.get("batchId")}
    return decisions


def guided_rows(reports: list[tuple[Path, dict[str, Any]]]) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for _path, report in reports:
        if (
            report.get("status") != "human_guided_automated_checked"
            or report.get("productionReady") is not False
            or report.get("gates", {}).get("modelRerun") is not False
        ):
            raise AtlasError("human-guided report gate 非法")
        for row in report.get("rows", []):
            key = row.get("reviewKey")
            if not isinstance(key, str) or key in rows:
                raise AtlasError(f"human-guided row 重复或非法：{key}")
            verify_artifact(row.get("master"), f"human-guided master {key}")
            rows[key] = row
    return rows


def wrap_text(value: str, width: int) -> list[str]:
    text = value.strip()
    if not text:
        return []
    return [text[index : index + width] for index in range(0, len(text), width)]


def checker(size: tuple[int, int], cell: int = 12) -> Image.Image:
    image = Image.new("RGB", size, "#20252C")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2 == 0:
                draw.rectangle((x, y, min(x + cell - 1, size[0] - 1), min(y + cell - 1, size[1] - 1)), fill="#2C333D")
    return image


def paste_contained(canvas: Image.Image, source_path: Path, box: tuple[int, int, int, int]) -> None:
    left, top, right, bottom = box
    width = right - left
    height = bottom - top
    background = checker((width, height))
    canvas.paste(background, (left, top))
    with Image.open(source_path) as raw:
        source = raw.convert("RGBA")
        scale = min(width / source.width, height / source.height)
        size = (max(1, round(source.width * scale)), max(1, round(source.height * scale)))
        resized = source.resize(size, Image.Resampling.LANCZOS)
        x = left + (width - size[0]) // 2
        y = top + (height - size[1]) // 2
        canvas.paste(resized, (x, y), resized)


def note_category(note: str, source_role: str | None = None) -> str:
    lowered = note.lower()
    labels: list[str] = []
    if "全身" in note:
        labels.append("全身→头像")
    if any(token in note for token in ("枪", "导弹", "视觉重心")):
        labels.append("移除武器焦点")
    if "右" in note:
        labels.append("去右侧死区")
    if any(token in note for token in ("上部", "上方", "顶部")):
        labels.append("去顶部死区")
    if "放大" in note:
        labels.append("强化特写")
    if source_role == "independent_review" or "luna b" in lowered or "lunab" in lowered:
        labels.append("采用独立审阅构图")
    return " / ".join(dict.fromkeys(labels)) or "人工收紧构图"


def portrait_name(review_key: str) -> str:
    return review_key.removesuffix("::default").removeprefix("敌人-")


def build_atlas(
    output_path: Path,
    font_path: Path,
    decisions: dict[str, dict[str, Any]],
    initial_rows: dict[tuple[str, str], dict[str, Any]],
    guided: dict[str, dict[str, Any]],
    orientation_rows: list[dict[str, Any]],
    feedback: dict[str, Any],
) -> dict[str, Any]:
    adjustment_keys = {key for key, row in decisions.items() if row.get("status") == "adjustment"}
    pass_keys = sorted(key for key, row in decisions.items() if row.get("status") == "pass")
    guided_keys = set(guided)
    orientation_keys = {row.get("reviewKey") for row in orientation_rows}
    if adjustment_keys != guided_keys | orientation_keys or guided_keys & orientation_keys:
        raise AtlasError(
            "全部 adjustment 必须精确分解为 human-guided crop 或 orientation；"
            f"adjustment={len(adjustment_keys)} guided={len(guided_keys)} orientation={len(orientation_keys)}"
        )
    if set(decisions) != set(pass_keys) | guided_keys | orientation_keys:
        raise AtlasError("human label 视觉覆盖不闭合")

    accepted: list[dict[str, Any]] = []
    for key in pass_keys:
        initial = initial_rows.get((key, "proposal"))
        if initial is None:
            raise AtlasError(f"pass 行缺 proposal master：{key}")
        accepted.append(
            {
                "reviewKey": key,
                "notes": decisions[key].get("notes", ""),
                "master": verify_artifact(initial["master"], f"accepted master {key}"),
            }
        )

    corrections: list[dict[str, Any]] = []
    for key in sorted(guided):
        row = guided[key]
        role = row.get("selectedChoice", {}).get("sourceRole")
        initial = initial_rows.get((key, role))
        if initial is None:
            raise AtlasError(f"guided 行缺绑定的模型初稿：{key}/{role}")
        corrections.append(
            {
                "reviewKey": key,
                "notes": decisions[key].get("notes", ""),
                "category": note_category(decisions[key].get("notes", ""), role),
                "sourceRole": role,
                "initial": verify_artifact(initial["master"], f"initial master {key}/{role}"),
                "human": verify_artifact(row["master"], f"human master {key}"),
            }
        )
    for row in orientation_rows:
        key = row["reviewKey"]
        if key not in decisions or decisions[key].get("status") != "adjustment":
            raise AtlasError(f"orientation 行未绑定 adjustment：{key}")
        corrections.append(
            {
                "reviewKey": key,
                "notes": decisions[key].get("notes", ""),
                "category": "朝向修正：保持明确的正向约定",
                "sourceRole": row.get("sourceRole"),
                "initial": verify_artifact(row["parentMaster"], f"orientation parent {key}"),
                "human": verify_artifact(row["master"], f"orientation human {key}"),
            }
        )
    corrections.sort(key=lambda row: row["reviewKey"])

    width = 1885
    pad = 24
    header_height = 92
    summary_height = 112
    accepted_title_height = 42
    accepted_height = 224
    correction_title_height = 48
    columns = 3
    correction_height = 238
    correction_rows = math.ceil(len(corrections) / columns)
    height = (
        header_height
        + summary_height
        + accepted_title_height
        + accepted_height
        + correction_title_height
        + correction_rows * correction_height
        + pad
    )
    canvas = Image.new("RGB", (width, height), "#10151C")
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(str(font_path), 28)
    section_font = ImageFont.truetype(str(font_path), 22)
    body_font = ImageFont.truetype(str(font_path), 17)
    small_font = ImageFont.truetype(str(font_path), 15)

    draw.rectangle((0, 0, width, header_height), fill="#172430")
    draw.rectangle((0, 0, 12, height), fill="#43C7B7")
    draw.text((pad, 16), "BOUND HUMAN PREFERENCE EXAMPLES — NOT CANDIDATES", font=title_font, fill="#F4FCFF")
    draw.text((pad, 54), "已冻结人类偏好像素证据；只校准构图，不得选择其中角色、candidateId 或坐标", font=body_font, fill="#9FE7DD")

    summary_top = header_height
    draw.rectangle((12, summary_top, width, summary_top + summary_height), fill="#1B2028")
    geometry = feedback.get("geometryCalibration", {})
    scaling = feedback.get("adaptiveScaling", {})
    summary_lines = [
        f"完整覆盖：{len(decisions)} 条人类标签 = {len(accepted)} pass + {len(corrections)} adjustment；"
        f"{len(guided)} 个真实框选 + {len(orientation_rows)} 个确定性朝向修正。",
        f"累计框选：{geometry.get('rows') and len(geometry['rows']) or 0} 条；中位放大 {geometry.get('medianZoomIn')}×，"
        f"范围 {geometry.get('minimumZoomIn')}–{geometry.get('maximumZoomIn')}×。不要机械套倍率。",
        f"规模门：24 × {scaling.get('estimatedFailureRate')} = {scaling.get('expectedRevisionsAtDoubledSize')} > "
        f"{scaling.get('expectedRevisionBudget')}；下一批保持 {scaling.get('recommendedNextShardSize')}，Fast 并发上限 "
        f"{scaling.get('maximumConcurrency')}。",
    ]
    for index, line in enumerate(summary_lines):
        draw.text((pad, summary_top + 10 + index * 31), line, font=body_font, fill="#D6DEE8")

    accepted_title_top = summary_top + summary_height
    draw.text((pad, accepted_title_top + 8), "HUMAN PASS ANCHORS / 人类直接通过的构图", font=section_font, fill="#7EE2A8")
    accepted_top = accepted_title_top + accepted_title_height
    accepted_cell_width = (width - 2 * pad) // max(1, len(accepted))
    for index, row in enumerate(accepted):
        left = pad + index * accepted_cell_width
        right = left + accepted_cell_width - 10
        draw.rounded_rectangle((left, accepted_top, right, accepted_top + accepted_height - 10), radius=10, fill="#17231F", outline="#3B8D68", width=2)
        image_size = 154
        image_left = left + (right - left - image_size) // 2
        paste_contained(canvas, row["master"], (image_left, accepted_top + 12, image_left + image_size, accepted_top + 12 + image_size))
        draw.text((left + 10, accepted_top + 171), portrait_name(row["reviewKey"])[:16], font=body_font, fill="#F0F6F3")
        note = row["notes"].strip()
        label = "PASS" if not note else f"PASS；附注：{note[:16]}"
        draw.text((left + 10, accepted_top + 196), label, font=small_font, fill="#8BD7AD")

    correction_title_top = accepted_top + accepted_height
    draw.rectangle((12, correction_title_top, width, correction_title_top + correction_title_height), fill="#271E22")
    draw.text((pad, correction_title_top + 10), "ALL HUMAN CORRECTIONS / MODEL INITIAL → HUMAN ACCEPTED", font=section_font, fill="#FFB3BC")
    grid_top = correction_title_top + correction_title_height
    cell_width = (width - 2 * pad) // columns
    image_size = 144
    for index, row in enumerate(corrections):
        column = index % columns
        line = index // columns
        left = pad + column * cell_width
        top = grid_top + line * correction_height
        right = left + cell_width - 12
        bottom = top + correction_height - 10
        draw.rounded_rectangle((left, top, right, bottom), radius=10, fill="#1D2027", outline="#6A454E", width=2)
        initial_left = left + 14
        human_left = initial_left + image_size + 54
        image_top = top + 42
        draw.text((initial_left, top + 12), "MODEL INITIAL", font=small_font, fill="#E1A4AC")
        draw.text((human_left, top + 12), "HUMAN ACCEPTED", font=small_font, fill="#86E2B1")
        paste_contained(canvas, row["initial"], (initial_left, image_top, initial_left + image_size, image_top + image_size))
        paste_contained(canvas, row["human"], (human_left, image_top, human_left + image_size, image_top + image_size))
        draw.text((initial_left + image_size + 15, image_top + 55), "→", font=title_font, fill="#FFD166")
        text_left = human_left + image_size + 14
        draw.text((text_left, image_top), portrait_name(row["reviewKey"])[:15], font=body_font, fill="#F3F5F8")
        draw.text((text_left, image_top + 27), row["category"][:18], font=small_font, fill="#FFD166")
        for line_index, value in enumerate(wrap_text(row["notes"], 18)[:4]):
            draw.text((text_left, image_top + 54 + line_index * 23), value, font=small_font, fill="#BFC7D1")
        draw.text((text_left, bottom - 27), f"source={row['sourceRole']}", font=small_font, fill="#8292A6")

    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    return {
        "schema": SCHEMA,
        "mode": MODE,
        "decisionCount": len(decisions),
        "passAnchorCount": len(accepted),
        "guidedCorrectionCount": len(guided),
        "orientationCorrectionCount": len(orientation_rows),
        "adjustmentCount": len(corrections),
        "allHumanLabelsVisualized": set(decisions) == set(pass_keys) | guided_keys | orientation_keys,
        "reviewKeys": sorted(decisions),
        "dimensions": [width, height],
    }


def composite_sheet(base_record: dict[str, Any], atlas_path: Path, output_path: Path) -> dict[str, Any]:
    base_path = verify_artifact(base_record, "base contact sheet")
    with Image.open(base_path) as base_raw, Image.open(atlas_path) as atlas_raw:
        base = base_raw.convert("RGB")
        atlas = atlas_raw.convert("RGB")
        width = max(base.width, atlas.width)
        canvas = Image.new("RGB", (width, base.height + atlas.height), "#10151C")
        canvas.paste(base, ((width - base.width) // 2, 0))
        canvas.paste(atlas, ((width - atlas.width) // 2, base.height))
        canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
        return {
            "base": base_record,
            "composite": artifact(output_path),
            "baseDimensions": [base.width, base.height],
            "compositeDimensions": [width, base.height + atlas.height],
        }


def attach(args: argparse.Namespace) -> None:
    base_path = repo_path(args.base_manifest, "base manifest")
    output_dir = repo_path(args.output, "output")
    try:
        output_dir.relative_to(PILOT_ROOT.resolve())
    except ValueError as error:
        raise AtlasError("output 必须位于 tmp/portrait-pilot") from error
    if output_dir.exists():
        raise AtlasError(f"输出目录已存在，禁止覆盖：{output_dir}")
    if not args.batch_id or len(args.batch_id) > 128 or not all(character.isalnum() or character in "._-" for character in args.batch_id):
        raise AtlasError("batch-id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")

    base = load_json(base_path, "base manifest")
    verify_digest(base, "manifestDigest", "base manifest")
    if sha256_bytes(stable_bytes(base.get("sourceEnvelope"))) != base.get("sourceDigest"):
        raise AtlasError("base manifest sourceDigest 不匹配")
    if base.get("status") != "campaign_shard_prepared" or base.get("productionReady") is not False:
        raise AtlasError("base manifest 尚不是未投产 campaign shard")
    font_path = verify_font(base)

    feedback_path = repo_path(args.feedback_report, "feedback report")
    feedback = load_json(feedback_path, "feedback report")
    verify_digest(feedback, "feedbackDigest", "feedback report")
    scaling = feedback.get("adaptiveScaling", {})
    if (
        scaling.get("humanReviewPageLimit") is not None
        or scaling.get("reviewConsolidationPolicy") != "single_page_preferred"
        or scaling.get("recommendedNextShardSize") != base.get("campaign", {}).get("shardSize")
        or scaling.get("maximumConcurrency") != 6
    ):
        raise AtlasError("feedback adaptive scaling 与下一 shard 不一致")

    receipt_reports = load_reports(args.human_review_receipt, "receiptDigest", "human review receipt")
    render_reports = load_reports(args.parent_render_report, "renderDigest", "parent render report")
    guided_reports = load_reports(args.guided_report, "reportDigest", "human-guided report")
    orientation_path = repo_path(args.orientation_report, "orientation report")
    orientation = load_json(orientation_path, "orientation report")
    verify_digest(orientation, "reportDigest", "orientation report")
    if (
        orientation.get("status") != "human_orientation_adjustment_checked"
        or orientation.get("productionReady") is not False
        or orientation.get("gates", {}).get("modelRerun") is not False
    ):
        raise AtlasError("orientation report gate 非法")

    decisions = decision_rows(receipt_reports)
    initial = role_rows(render_reports)
    guided = guided_rows(guided_reports)
    orientation_rows = orientation.get("rows", [])
    geometry_keys = {row.get("reviewKey") for row in feedback.get("geometryCalibration", {}).get("rows", [])}
    if geometry_keys != set(guided):
        raise AtlasError("累计 geometry 行与 human-guided visuals 不闭合")

    output_dir.mkdir(parents=True)
    atlas_path = output_dir / "feedback-preference-atlas.png"
    coverage = build_atlas(atlas_path, font_path, decisions, initial, guided, orientation_rows, feedback)
    atlas_record = artifact(atlas_path)

    sheet_records: list[dict[str, Any]] = []
    full_sheet = composite_sheet(base["contactSheet"], atlas_path, output_dir / "feature-contact-sheet-with-feedback.png")
    sheet_records.append(full_sheet)
    model_sheets: list[dict[str, Any]] = []
    for model_batch in base["modelBatches"]:
        name = f"{model_batch['modelBatchId']}-with-feedback.png"
        record = composite_sheet(model_batch["contactSheet"], atlas_path, output_dir / name)
        sheet_records.append(record)
        model_sheets.append(record["composite"])

    derived = copy.deepcopy(base)
    derived.pop("manifestDigest", None)
    derived["batchId"] = args.batch_id
    derived["createdAt"] = utc_now()
    derived["contactSheet"] = full_sheet["composite"]
    for model_batch, contact_sheet in zip(derived["modelBatches"], model_sheets):
        model_batch["contactSheet"] = contact_sheet

    evidence_paths = [
        base_path,
        feedback_path,
        orientation_path,
        Path(__file__).resolve(),
        *(path for path, _value in receipt_reports),
        *(path for path, _value in render_reports),
        *(path for path, _value in guided_reports),
        atlas_path,
    ]
    source_files = list(derived["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in evidence_paths:
        record = artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])

    calibration = {
        "schema": SCHEMA,
        "mode": MODE,
        "baseManifest": artifact(base_path),
        "feedbackReport": artifact(feedback_path),
        "humanReviewReceipts": [artifact(path) for path, _value in receipt_reports],
        "parentRenderReports": [artifact(path) for path, _value in render_reports],
        "humanGuidedRenderReports": [artifact(path) for path, _value in guided_reports],
        "orientationReport": artifact(orientation_path),
        "controllerSource": artifact(Path(__file__).resolve()),
        "atlas": atlas_record,
        "coverage": coverage,
        "contactSheets": sheet_records,
        "adaptiveScaling": scaling,
        "gates": {
            "allHumanLabelsVisualized": coverage["allHumanLabelsVisualized"],
            "rawHumanReceiptsBound": True,
            "deterministicHumanOutputsBound": True,
            "examplesAreNotCandidates": True,
            "noHumanPageSizeLimit": True,
            "modelTrainingClaim": False,
            "productionWrites": False,
        },
    }
    derived["sourceEnvelope"]["batchId"] = args.batch_id
    derived["sourceEnvelope"]["sourceFiles"] = source_files
    derived["sourceEnvelope"]["humanPreferenceCalibration"] = calibration
    derived["sourceDigest"] = sha256_bytes(stable_bytes(derived["sourceEnvelope"]))
    derived["humanPreferenceCalibration"] = calibration
    derived["manifestDigest"] = sha256_bytes(stable_bytes(derived))
    manifest_path = output_dir / "candidate-manifest.json"
    write_json(manifest_path, derived)
    checked = verify_derived(manifest_path)
    print(json.dumps(checked, ensure_ascii=False))


def verify_derived(manifest_path: Path) -> dict[str, Any]:
    manifest = load_json(manifest_path, "derived manifest")
    verify_digest(manifest, "manifestDigest", "derived manifest")
    envelope = manifest.get("sourceEnvelope")
    if not isinstance(envelope, dict) or sha256_bytes(stable_bytes(envelope)) != manifest.get("sourceDigest"):
        raise AtlasError("derived sourceDigest 不匹配")
    calibration = envelope.get("humanPreferenceCalibration")
    if (
        not isinstance(calibration, dict)
        or calibration.get("schema") != SCHEMA
        or calibration.get("mode") != MODE
        or calibration.get("gates", {}).get("allHumanLabelsVisualized") is not True
        or calibration.get("gates", {}).get("examplesAreNotCandidates") is not True
        or calibration.get("gates", {}).get("productionWrites") is not False
    ):
        raise AtlasError("derived human preference calibration gate 非法")
    for index, record in enumerate(envelope.get("sourceFiles", [])):
        verify_artifact(record, f"source file {index}")
    atlas_path = verify_artifact(calibration.get("atlas"), "feedback atlas")
    with Image.open(atlas_path) as atlas:
        if list(atlas.size) != calibration.get("coverage", {}).get("dimensions"):
            raise AtlasError("feedback atlas 尺寸漂移")
    expected_sheets = 1 + len(manifest.get("modelBatches", []))
    if len(calibration.get("contactSheets", [])) != expected_sheets:
        raise AtlasError("calibrated contact sheet 数不闭合")
    records = [manifest.get("contactSheet"), *(batch.get("contactSheet") for batch in manifest.get("modelBatches", []))]
    for index, record in enumerate(records):
        path = verify_artifact(record, f"calibrated contact sheet {index}")
        evidence = calibration["contactSheets"][index]
        if evidence.get("composite") != record:
            raise AtlasError("calibrated contact sheet evidence 漂移")
        with Image.open(path) as image:
            if list(image.size) != evidence.get("compositeDimensions"):
                raise AtlasError("calibrated contact sheet 尺寸漂移")
    coverage = calibration["coverage"]
    if (
        coverage.get("decisionCount") != 24
        or coverage.get("passAnchorCount") != 6
        or coverage.get("guidedCorrectionCount") != 17
        or coverage.get("orientationCorrectionCount") != 1
        or coverage.get("adjustmentCount") != 18
    ):
        raise AtlasError("当前两轮人类标签覆盖数不闭合")
    return {
        "status": "campaign_human_preference_atlas_verified",
        "manifest": repo_rel(manifest_path),
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "atlasSha256": calibration["atlas"]["sha256"],
        "humanLabels": coverage["decisionCount"],
        "passAnchors": coverage["passAnchorCount"],
        "adjustments": coverage["adjustmentCount"],
        "contactSheets": expected_sheets,
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    manifest_path = repo_path(args.manifest, "derived manifest")
    print(json.dumps(verify_derived(manifest_path), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    attach_parser = commands.add_parser("attach")
    attach_parser.add_argument("--base-manifest", required=True)
    attach_parser.add_argument("--feedback-report", required=True)
    attach_parser.add_argument("--human-review-receipt", action="append", required=True)
    attach_parser.add_argument("--parent-render-report", action="append", required=True)
    attach_parser.add_argument("--guided-report", action="append", required=True)
    attach_parser.add_argument("--orientation-report", required=True)
    attach_parser.add_argument("--output", required=True)
    attach_parser.add_argument("--batch-id", required=True)
    attach_parser.set_defaults(handler=attach)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--manifest", required=True)
    check_parser.set_defaults(handler=check)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (AtlasError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"portrait feedback atlas error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
