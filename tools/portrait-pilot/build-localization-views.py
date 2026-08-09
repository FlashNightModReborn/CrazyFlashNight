#!/usr/bin/env python3
"""Build enlarged, grid-aligned selected-frame views for a localization-only model pass."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
PORTRAIT_TMP = ROOT / "tmp" / "portrait-pilot"
SCHEMA = "cf7.portrait-pilot-localization-views.v1"
SELECTION_LOCK_SCHEMA = "cf7.portrait-pilot-selection-lock.v1"
Image.MAX_IMAGE_PIXELS = 200_000_000


class ViewError(RuntimeError):
    pass


def stable_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def relative(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def artifact(path: Path) -> dict[str, object]:
    return {"path": relative(path), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def resolve_repo(value: str, label: str) -> Path:
    path = (ROOT / value).resolve()
    try:
        path.relative_to(ROOT)
    except ValueError as error:
        raise ViewError(f"{label} 越出仓库") from error
    if not path.is_file():
        raise ViewError(f"{label} 缺失：{path}")
    return path


def resolve_output(value: str, must_exist: bool) -> Path:
    path = (ROOT / value).resolve()
    try:
        relative_path = path.relative_to(PORTRAIT_TMP)
    except ValueError as error:
        raise ViewError("output 必须位于 tmp/portrait-pilot 下") from error
    if not relative_path.parts:
        raise ViewError("output 不能是 portrait-pilot 根目录")
    if must_exist and not path.is_dir():
        raise ViewError(f"output 目录缺失：{path}")
    if not must_exist and path.exists():
        raise ViewError(f"output 已存在，禁止覆盖：{path}")
    return path


def read_json(path: Path, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ViewError(f"{label} 不是合法 JSON：{error}") from error
    if not isinstance(value, dict):
        raise ViewError(f"{label} 必须是对象")
    return value


def verify_digest(value: dict[str, object], field: str, label: str) -> None:
    envelope = dict(value)
    digest = envelope.pop(field, None)
    if not isinstance(digest, str) or sha256_bytes(stable_bytes(envelope)) != digest:
        raise ViewError(f"{label} {field} 不匹配")


def verify_record(record: dict[str, object], label: str) -> Path:
    if not isinstance(record, dict):
        raise ViewError(f"{label} artifact 非对象")
    path_value = record.get("path")
    if not isinstance(path_value, str):
        raise ViewError(f"{label} artifact 缺 path")
    path = resolve_repo(path_value, label)
    if path.stat().st_size != record.get("bytes") or sha256_file(path) != record.get("sha256"):
        raise ViewError(f"{label} artifact 字节闭包不匹配")
    return path


def verify_review_digest(dataset: dict[str, object]) -> None:
    envelope = {
        "schema": dataset.get("schema"),
        "sourceDigest": dataset.get("sourceDigest"),
        "manifestDigest": dataset.get("manifestDigest"),
        "modelReportDigest": dataset.get("modelReportDigest"),
        "renderDigest": dataset.get("renderDigest"),
        "decisionSchema": dataset.get("decisionSchema"),
        "reviewer": dataset.get("reviewer"),
        "statuses": dataset.get("statuses"),
        "items": dataset.get("items"),
    }
    if dataset.get("schema") == "cf7.portrait-pilot-review-data.v2":
        envelope["decisionSemantics"] = dataset.get("decisionSemantics")
        envelope["counts"] = dataset.get("counts")
    if sha256_bytes(stable_bytes(envelope)) != dataset.get("reviewDigest"):
        raise ViewError("source reviewDigest 不匹配")


def checkerboard(size: tuple[int, int], square: int = 32) -> Image.Image:
    width, height = size
    image = Image.new("RGBA", size, (35, 39, 46, 255))
    draw = ImageDraw.Draw(image)
    alternate = (56, 62, 72, 255)
    for top in range(0, height, square):
        for left in range(0, width, square):
            if ((left // square) + (top // square)) % 2:
                draw.rectangle((left, top, min(width, left + square), min(height, top + square)), fill=alternate)
    return image


def render_view(
    high_resolution_path: Path,
    candidate: dict[str, object],
    output_path: Path,
    max_dimension: int,
) -> tuple[list[int], list[int]]:
    with Image.open(high_resolution_path) as source_image:
        source = source_image.convert("RGBA")
    if max(source.size) > 16_384:
        raise ViewError(f"高分辨率帧超过 16384：{high_resolution_path}")
    source_size = candidate.get("sourceSize")
    crop_bounds = candidate.get("sourceCropBounds")
    if (
        not isinstance(source_size, list) or len(source_size) != 2 or
        not isinstance(crop_bounds, list) or len(crop_bounds) != 4
    ):
        raise ViewError("候选缺 sourceSize/sourceCropBounds")
    scale_x = source.width / float(source_size[0])
    scale_y = source.height / float(source_size[1])
    left = round(float(crop_bounds[0]) * scale_x)
    top = round(float(crop_bounds[1]) * scale_y)
    right = round(float(crop_bounds[2]) * scale_x)
    bottom = round(float(crop_bounds[3]) * scale_y)
    if left < 0 or top < 0 or right > source.width or bottom > source.height or left >= right or top >= bottom:
        raise ViewError(f"高分辨率候选裁切越界：{[left, top, right, bottom]}/{source.size}")
    cropped = source.crop((left, top, right, bottom))
    resize_scale = min(1.0, max_dimension / max(cropped.size))
    target_size = (
        max(1, round(cropped.width * resize_scale)),
        max(1, round(cropped.height * resize_scale)),
    )
    if target_size != cropped.size:
        cropped = cropped.resize(target_size, Image.Resampling.LANCZOS)
    background = checkerboard(cropped.size, max(16, round(max(cropped.size) / 64)))
    background.alpha_composite(cropped)
    overlay = Image.new("RGBA", background.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    line_width = max(1, round(max(background.size) / 900))
    for index in range(11):
        x = round(index * (background.width - 1) / 10)
        y = round(index * (background.height - 1) / 10)
        color = (100, 235, 255, 150) if index in (0, 5, 10) else (255, 255, 255, 75)
        draw.line((x, 0, x, background.height - 1), fill=color, width=line_width)
        draw.line((0, y, background.width - 1, y), fill=color, width=line_width)
        if 0 < index < 10:
            label = f".{index}"
            draw.text((x + 3, 3), label, fill=(255, 255, 255, 210), stroke_width=1, stroke_fill=(0, 0, 0, 220))
            draw.text((3, y + 2), label, fill=(255, 255, 255, 210), stroke_width=1, stroke_fill=(0, 0, 0, 220))
    background.alpha_composite(overlay)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    background.convert("RGB").save(output_path, format="PNG", optimize=True)
    return [left, top, right, bottom], [background.width, background.height]


def build(args: argparse.Namespace) -> dict[str, object]:
    manifest_path = resolve_repo(args.manifest, "experimental manifest")
    manifest = read_json(manifest_path, "experimental manifest")
    verify_digest(manifest, "manifestDigest", "experimental manifest")
    source_batch = (ROOT / args.source_review_batch).resolve()
    try:
        source_batch.relative_to(PORTRAIT_TMP)
    except ValueError as error:
        raise ViewError("source review batch 必须位于 tmp/portrait-pilot 下") from error
    review_data_path = source_batch / "review-data.json"
    review_data = read_json(review_data_path, "source review data")
    verify_review_digest(review_data)
    selection_lock_path: Path | None = None
    selection_lock: dict[str, object] | None = None
    locks_by_key: dict[str, dict[str, object]] = {}
    if args.selection_lock:
        selection_lock_path = resolve_repo(args.selection_lock, "selection lock")
        selection_lock = read_json(selection_lock_path, "selection lock")
        verify_digest(selection_lock, "selectionDigest", "selection lock")
        if selection_lock.get("schema") != SELECTION_LOCK_SCHEMA or selection_lock.get("productionReady") is not False:
            raise ViewError("selection lock schema/productionReady 非法")
        verify_record(selection_lock.get("input", {}).get("manifest"), "selection lock manifest")
        verify_record(selection_lock.get("input", {}).get("modelReport"), "selection lock model report")
        verify_record(selection_lock.get("controller"), "selection lock controller")
        for row in selection_lock.get("rows", []):
            review_key = row.get("reviewKey")
            if not isinstance(review_key, str) or review_key in locks_by_key:
                raise ViewError("selection lock 含非法或重复 reviewKey")
            verify_record(row.get("candidateArtifact"), f"selection lock candidate {review_key}")
            locks_by_key[review_key] = row
    output = resolve_output(args.output, False)
    if args.max_dimension < 1024 or args.max_dimension > 4096:
        raise ViewError("max-dimension 必须为 1024–4096")
    manifest_items = {item["reviewKey"]: item for item in manifest.get("reviewItems", []) if not item.get("blocked")}
    review_items = {item["reviewKey"]: item for item in review_data.get("items", []) if not item.get("blocked")}
    if set(manifest_items) != set(review_items):
        raise ViewError("experimental manifest 与 source review 的 eligible reviewKey 不一致")
    if selection_lock is not None and set(locks_by_key) != set(manifest_items):
        raise ViewError("selection lock 与 experimental manifest 的 eligible reviewKey 不一致")
    output.mkdir(parents=True)
    rows: list[dict[str, object]] = []
    try:
        for review_key in sorted(manifest_items):
            item = manifest_items[review_key]
            review_item = review_items[review_key]
            lock = locks_by_key.get(review_key)
            lock_role = lock.get("lockedRole") if lock is not None else args.lock_role
            candidate_id = lock.get("candidateId") if lock is not None else None
            proposal = review_item.get("proposals", {}).get(lock_role)
            if not isinstance(proposal, dict):
                raise ViewError(f"缺锁定角色提案：{review_key}/{lock_role}")
            if candidate_id is None:
                candidate_id = proposal.get("candidateId")
            elif proposal.get("candidateId") != candidate_id:
                raise ViewError(f"selection lock 与 source review 角色候选不一致：{review_key}")
            candidate = next((entry for entry in item.get("candidates", []) if entry.get("candidateId") == candidate_id), None)
            if not isinstance(candidate, dict):
                raise ViewError(f"锁定候选不在 experimental manifest：{review_key}/{candidate_id}")
            if candidate.get("artifact", {}).get("sha256") != proposal.get("sourceCandidate", {}).get("sha256"):
                raise ViewError(f"锁定候选 hash 不一致：{review_key}")
            if lock is not None and candidate.get("artifact", {}).get("sha256") != lock.get("candidateArtifact", {}).get("sha256"):
                raise ViewError(f"selection lock 候选 hash 与 experimental manifest 不一致：{review_key}")
            source_high = proposal.get("sourceHighResolution")
            high_path = verify_record(source_high, f"source high resolution {review_key}")
            filename = f"{item['reviewCode']}-{candidate_id}.png"
            view_path = output / "views" / filename
            pixel_crop, view_size = render_view(high_path, candidate, view_path, args.max_dimension)
            rows.append({
                "reviewCode": item["reviewCode"],
                "reviewKey": review_key,
                "lockedRole": lock_role,
                "candidateId": candidate_id,
                "candidateArtifact": candidate["artifact"],
                "candidateWidth": candidate["width"],
                "candidateHeight": candidate["height"],
                "sourceSize": candidate["sourceSize"],
                "sourceCropBounds": candidate["sourceCropBounds"],
                "sourceHighResolution": source_high,
                "sourceHighResolutionSize": list(Image.open(high_path).size),
                "sourceHighResolutionPixelCrop": pixel_crop,
                "viewSize": view_size,
                "view": artifact(view_path),
                "normalizedCoordinatesMatchCandidate": True,
            })
    except Exception:
        # Keep partial files for diagnosis but never write a valid manifest.
        raise
    controller_path = Path(__file__).resolve()
    report: dict[str, object] = {
        "schema": SCHEMA,
        "status": "localization_views_ready",
        "productionReady": False,
        "generatedAt": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat().replace("+00:00", "Z"),
        "input": {
            "manifest": artifact(manifest_path),
            "manifestDigest": manifest["manifestDigest"],
            "sourceReviewData": artifact(review_data_path),
            "sourceReviewDigest": review_data["reviewDigest"],
            "lockRole": "deterministic_per_row" if selection_lock is not None else args.lock_role,
            "selectionLock": artifact(selection_lock_path) if selection_lock_path is not None else None,
            "selectionDigest": selection_lock.get("selectionDigest") if selection_lock is not None else None,
        },
        "renderContract": {
            "maxDimension": args.max_dimension,
            "gridStep": 0.1,
            "coordinateSpace": "locked candidate normalized 0..1",
            "targetHumanGeometryTransmitted": False,
        },
        "controller": artifact(controller_path),
        "rows": rows,
        "counts": {"rows": len(rows), "uniqueViews": len({row["view"]["sha256"] for row in rows})},
        "gates": {
            "exactCandidateHashBinding": True,
            "deterministicSelectionLock": selection_lock is not None,
            "highResolutionSourceVerified": True,
            "normalizedCandidateMapping": True,
            "humanTargetGeometryExcluded": True,
            "productionWrites": False,
        },
    }
    report["viewDigest"] = sha256_bytes(stable_bytes(report))
    report_path = output / "localization-view-manifest.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def check(args: argparse.Namespace) -> dict[str, object]:
    output = resolve_output(args.output, True)
    report_path = output / "localization-view-manifest.json"
    report = read_json(report_path, "localization view manifest")
    verify_digest(report, "viewDigest", "localization view manifest")
    if report.get("schema") != SCHEMA or report.get("productionReady") is not False:
        raise ViewError("localization view manifest schema/status 非法")
    verify_record(report["input"]["manifest"], "input manifest")
    verify_record(report["input"]["sourceReviewData"], "source review data")
    if report.get("input", {}).get("selectionLock") is not None:
        selection_lock_path = verify_record(report["input"]["selectionLock"], "selection lock")
        selection_lock = read_json(selection_lock_path, "selection lock")
        verify_digest(selection_lock, "selectionDigest", "selection lock")
        if selection_lock.get("selectionDigest") != report.get("input", {}).get("selectionDigest"):
            raise ViewError("selection lock digest 与 localization view manifest 不一致")
    verify_record(report["controller"], "localization view controller")
    rows = report.get("rows")
    if not isinstance(rows, list) or len(rows) != report.get("counts", {}).get("rows"):
        raise ViewError("localization view rows/counts 不闭合")
    for row in rows:
        verify_record(row["candidateArtifact"], f"candidate {row.get('reviewKey')}")
        verify_record(row["sourceHighResolution"], f"high resolution {row.get('reviewKey')}")
        view_path = verify_record(row["view"], f"view {row.get('reviewKey')}")
        with Image.open(view_path) as image:
            if list(image.size) != row.get("viewSize"):
                raise ViewError(f"view 尺寸不匹配：{row.get('reviewKey')}")
        if row.get("normalizedCoordinatesMatchCandidate") is not True:
            raise ViewError(f"view 坐标映射未闭合：{row.get('reviewKey')}")
    return report


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    subparsers = result.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--manifest", required=True)
    render_parser.add_argument("--source-review-batch", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--lock-role", choices=("proposal", "independent_review"), default="proposal")
    render_parser.add_argument("--selection-lock")
    render_parser.add_argument("--max-dimension", type=int, default=2048)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    return result


def main() -> None:
    args = parser().parse_args()
    report = build(args) if args.command == "render" else check(args)
    print(json.dumps({
        "status": report["status"] if args.command == "render" else "localization_views_verified",
        "viewDigest": report["viewDigest"],
        "counts": report["counts"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except ViewError as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=__import__("sys").stderr)
        raise SystemExit(1)
