#!/usr/bin/env python3
"""Build and render a non-destructive Web Dressup reskin assembly audit.

The generated component concepts are not treated as drop-in assets.  This tool
creates two diagnostic retargets for every original skin canvas, intercepts the
corresponding PNG requests in the existing Dressup Playwright harness, and
captures the real battle rig in every requested state.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Any, Iterable

from PIL import Image, ImageChops, ImageDraw, ImageFont


PROJECT_ROOT = Path(__file__).resolve().parents[2]
PIPELINE_OUTPUT_ROOT = (PROJECT_ROOT / "tmp" / "monster-reskin").resolve()
STATE_SLUGS = {
    "空手站立": "unarmed-stand",
    "长枪站立": "longgun-stand",
    "手枪站立": "handgun-stand",
    "手枪2站立": "handgun2-stand",
    "双枪站立": "dualgun-stand",
    "兵器站立": "melee-stand",
}
REQUIRED_BATTLE_STATES = tuple(STATE_SLUGS)
REQUIRED_UNIQUE_SKINS = 12
REQUIRED_COMPONENT_PLACEMENTS = 15


def project_path(value: str | Path) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = PROJECT_ROOT / path
    return path.resolve()


def require_inside(path: Path, parent: Path, description: str) -> Path:
    try:
        path.relative_to(parent)
    except ValueError as exc:
        raise ValueError(f"{description} must stay inside {parent}: {path}") from exc
    return path


def relative_project_path(path: Path) -> str:
    return path.resolve().relative_to(PROJECT_ROOT).as_posix()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return data


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("Image has no non-transparent pixels")
    return bbox


def resized_size(width: int, height: int, scale: float) -> tuple[int, int]:
    return max(1, round(width * scale)), max(1, round(height * scale))


def retarget_component(
    concept: Image.Image,
    source: Image.Image,
    mode: str,
) -> tuple[Image.Image, dict[str, Any]]:
    source = source.convert("RGBA")
    concept = concept.convert("RGBA")
    source_bbox = alpha_bbox(source)
    concept_bbox = alpha_bbox(concept)
    concept_crop = concept.crop(concept_bbox)
    source_width, source_height = source.size
    crop_width, crop_height = concept_crop.size
    source_ratio = source_width / max(1, source_height)
    concept_ratio = crop_width / max(1, crop_height)

    if mode == "fit":
        scale = min(source_width / crop_width, source_height / crop_height)
        target_size = resized_size(crop_width, crop_height, scale)
        resized = concept_crop.resize(target_size, Image.Resampling.LANCZOS)
        result = Image.new("RGBA", source.size, (0, 0, 0, 0))
        offset = (
            round((source_width - target_size[0]) / 2),
            round((source_height - target_size[1]) / 2),
        )
        result.alpha_composite(resized, offset)
    elif mode == "masked":
        scale = max(source_width / crop_width, source_height / crop_height)
        target_size = resized_size(crop_width, crop_height, scale)
        resized = concept_crop.resize(target_size, Image.Resampling.LANCZOS)
        offset = (
            round((source_width - target_size[0]) / 2),
            round((source_height - target_size[1]) / 2),
        )
        staging = Image.new("RGBA", source.size, (18, 20, 23, 255))
        staging.alpha_composite(resized, offset)
        staging.putalpha(source.getchannel("A"))
        result = staging
    else:
        raise ValueError(f"Unknown retarget mode: {mode}")

    return result, {
        "sourceSize": [source_width, source_height],
        "sourceAlphaBBox": list(source_bbox),
        "conceptSize": list(concept.size),
        "conceptAlphaBBox": list(concept_bbox),
        "sourceAspect": round(source_ratio, 6),
        "conceptAspect": round(concept_ratio, 6),
        "aspectDriftPercent": round(abs(concept_ratio / source_ratio - 1) * 100, 2),
        "scale": round(scale, 6),
        "retargetSize": list(target_size),
        "offset": list(offset),
    }


def skin_override_key(source_uri: str) -> str:
    normalized = str(source_uri or "").replace("\\", "/")
    marker = "launcher/web/assets/dressup/"
    if not normalized.startswith(marker):
        raise ValueError(f"sourceUri must start with {marker}: {source_uri}")
    key = normalized[len(marker) :]
    if not re.fullmatch(r"skins/[^/]+\.(?:png|webp|jpe?g)", key, flags=re.IGNORECASE):
        raise ValueError(f"Unsupported dressup skin URI: {source_uri}")
    return key


def prepare_preview_skins(
    component_manifest_path: Path,
    output_dir: Path,
) -> tuple[dict[str, Path], list[dict[str, Any]]]:
    manifest = read_json(component_manifest_path)
    manifest_dir = component_manifest_path.parent
    components = manifest.get("components")
    if not isinstance(components, list) or not components:
        raise ValueError("component manifest must contain a non-empty components array")

    override_files: dict[str, Path] = {}
    metrics: list[dict[str, Any]] = []
    for mode in ("fit", "masked"):
        (output_dir / "preview-skins" / mode).mkdir(parents=True, exist_ok=True)

    for component in components:
        if not isinstance(component, dict):
            raise ValueError("component entries must be objects")
        source_path = (manifest_dir / str(component["source"])).resolve()
        concept_path = (manifest_dir / str(component["alphaOutput"])).resolve()
        require_inside(source_path, PROJECT_ROOT, "component source")
        require_inside(concept_path, PROJECT_ROOT, "component concept")
        if not source_path.is_file() or not concept_path.is_file():
            raise FileNotFoundError(f"Missing component input: {source_path} / {concept_path}")

        key = skin_override_key(str(component["sourceUri"]))
        file_name = Path(key).name
        with Image.open(source_path) as source_image, Image.open(concept_path) as concept_image:
            mode_metrics: dict[str, Any] = {}
            for mode in ("fit", "masked"):
                preview, preview_metrics = retarget_component(concept_image, source_image, mode)
                destination = output_dir / "preview-skins" / mode / file_name
                preview.save(destination)
                mode_metrics[mode] = preview_metrics
                override_files[f"{mode}:{key}"] = destination
        metrics.append(
            {
                "index": component.get("index"),
                "field": component.get("field"),
                "skinKey": component.get("skinKey"),
                "source": relative_project_path(source_path),
                "concept": relative_project_path(concept_path),
                "overrideKey": key,
                "sharedNonMirrored": bool(component.get("sharedNonMirrored")),
                "fit": mode_metrics["fit"],
                "masked": mode_metrics["masked"],
            }
        )

    override_paths: dict[str, Path] = {}
    for mode in ("fit", "masked"):
        overrides = {
            composite_key.split(":", 1)[1]: relative_project_path(file_path)
            for composite_key, file_path in override_files.items()
            if composite_key.startswith(mode + ":")
        }
        override_path = output_dir / f"skin-overrides-{mode}.json"
        write_json(override_path, {"schema": 1, "mode": mode, "overrides": overrides})
        override_paths[mode] = override_path

    return override_paths, metrics


def state_slug(index: int, state: str) -> str:
    known = STATE_SLUGS.get(state)
    if known:
        return f"{index:02d}-{known}"
    safe = re.sub(r"[^0-9A-Za-z_-]+", "-", state).strip("-") or "state"
    return f"{index:02d}-{safe}"


def run_harness(
    harness_path: Path,
    preset_path: Path,
    browser: str,
    state: str,
    canvas_path: Path,
    override_path: Path | None,
) -> dict[str, Any]:
    command = [
        "node",
        relative_project_path(harness_path),
        "--browser",
        browser,
        "--init-file",
        relative_project_path(preset_path),
        "--state-label",
        state,
        "--freeze-ms",
        "0",
        "--canvas-shot",
        relative_project_path(canvas_path),
    ]
    if override_path is not None:
        command.extend(["--skin-override-file", relative_project_path(override_path)])
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    completed = subprocess.run(
        command,
        cwd=PROJECT_ROOT,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            "Dressup harness did not return JSON.\n"
            f"command: {' '.join(command)}\n"
            f"stdout: {completed.stdout}\n"
            f"stderr: {completed.stderr}"
        ) from exc
    if completed.returncode != 0 or payload.get("qa", {}).get("failed"):
        raise RuntimeError(
            "Dressup harness failed.\n"
            f"command: {' '.join(command)}\n"
            f"payload: {json.dumps(payload, ensure_ascii=False, indent=2)}\n"
            f"stderr: {completed.stderr}"
        )
    return payload


def binary_alpha(image: Image.Image, threshold: int = 8) -> Image.Image:
    alpha = image.convert("RGBA").getchannel("A")
    return alpha.point(lambda value: 255 if value > threshold else 0)


def mask_count(mask: Image.Image) -> int:
    return sum(mask.histogram()[1:])


def alpha_comparison(reference: Image.Image, candidate: Image.Image) -> dict[str, Any]:
    reference_mask = binary_alpha(reference)
    candidate_mask = binary_alpha(candidate)
    reference_count = mask_count(reference_mask)
    candidate_count = mask_count(candidate_mask)
    changed = ImageChops.difference(reference_mask, candidate_mask)
    changed_count = mask_count(changed)
    union = ImageChops.lighter(reference_mask, candidate_mask)
    union_count = mask_count(union)
    return {
        "referenceAlphaPixels": reference_count,
        "candidateAlphaPixels": candidate_count,
        "alphaPixelDelta": candidate_count - reference_count,
        "symmetricDifferencePixels": changed_count,
        "symmetricDifferenceOfUnion": round(changed_count / max(1, union_count), 6),
    }


def alpha_difference_image(reference: Image.Image, candidate: Image.Image) -> Image.Image:
    reference_mask = binary_alpha(reference)
    candidate_mask = binary_alpha(candidate)
    reference_only = ImageChops.subtract(reference_mask, candidate_mask)
    candidate_only = ImageChops.subtract(candidate_mask, reference_mask)
    shared = ImageChops.darker(reference_mask, candidate_mask)
    result = Image.new("RGBA", reference.size, (15, 18, 23, 255))
    result.paste((91, 98, 112, 255), mask=shared)
    result.paste((255, 70, 88, 255), mask=reference_only)
    result.paste((31, 220, 235, 255), mask=candidate_only)
    return result


def load_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/msyhbd.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def flatten_for_review(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    background = Image.new("RGBA", rgba.size, (15, 18, 23, 255))
    background.alpha_composite(rgba)
    return background.convert("RGB")


def review_tile(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    flattened = flatten_for_review(image)
    flattened.thumbnail(size, Image.Resampling.LANCZOS)
    tile = Image.new("RGB", size, (15, 18, 23))
    offset = ((size[0] - flattened.width) // 2, (size[1] - flattened.height) // 2)
    tile.paste(flattened, offset)
    return tile


def shared_review_crop(images: Iterable[Image.Image], padding: int = 28) -> tuple[int, int, int, int]:
    images = [image.convert("RGBA") for image in images]
    if not images:
        raise ValueError("At least one image is required for a shared review crop")
    union = Image.new("L", images[0].size, 0)
    for image in images:
        if image.size != images[0].size:
            raise ValueError("Review images must share one canvas size")
        union = ImageChops.lighter(union, image.getchannel("A"))
    bbox = union.getbbox() or (0, 0, images[0].width, images[0].height)
    return (
        max(0, bbox[0] - padding),
        max(0, bbox[1] - padding),
        min(images[0].width, bbox[2] + padding),
        min(images[0].height, bbox[3] + padding),
    )


def build_review_sheets(
    output_dir: Path,
    state_records: list[dict[str, Any]],
) -> Path:
    sheets_dir = output_dir / "sheets"
    sheets_dir.mkdir(parents=True, exist_ok=True)
    tile_size = (440, 313)
    label_height = 44
    columns = ["原版", "比例保真回填", "原蒙版裁切诊断（非资产）", "比例回填 alpha 差异"]
    font = load_font(24)
    small_font = load_font(20)

    summary = Image.new(
        "RGB",
        (tile_size[0] * len(columns), label_height + (tile_size[1] + label_height) * len(state_records)),
        (10, 12, 16),
    )
    summary_draw = ImageDraw.Draw(summary)
    for column_index, label in enumerate(columns):
        summary_draw.text(
            (column_index * tile_size[0] + 14, 8),
            label,
            font=font,
            fill=(235, 239, 246),
        )

    for row_index, record in enumerate(state_records):
        with Image.open(project_path(record["captures"]["baseline"])) as baseline_source:
            baseline = baseline_source.convert("RGBA")
        with Image.open(project_path(record["captures"]["fit"])) as fit_source:
            fit = fit_source.convert("RGBA")
        with Image.open(project_path(record["captures"]["masked"])) as masked_source:
            masked = masked_source.convert("RGBA")
        diff = alpha_difference_image(baseline, fit)
        images = [baseline, fit, masked, diff]
        crop_box = shared_review_crop((baseline, fit, masked))
        review_images = [image.crop(crop_box) for image in images]
        record["reviewCrop"] = list(crop_box)

        state_sheet = Image.new(
            "RGB",
            (tile_size[0] * len(columns), tile_size[1] + label_height),
            (10, 12, 16),
        )
        state_draw = ImageDraw.Draw(state_sheet)
        for column_index, (label, image) in enumerate(zip(columns, review_images)):
            x = column_index * tile_size[0]
            state_draw.text((x + 14, 8), label, font=small_font, fill=(235, 239, 246))
            state_sheet.paste(review_tile(image, tile_size), (x, label_height))
        state_sheet_path = sheets_dir / f"{record['slug']}.png"
        state_sheet.save(state_sheet_path)
        record["sheet"] = relative_project_path(state_sheet_path)

        row_y = label_height + row_index * (tile_size[1] + label_height)
        summary_draw.text(
            (14, row_y + 8),
            f"{row_index + 1:02d} · {record['stateLabel']}",
            font=small_font,
            fill=(255, 211, 94),
        )
        for column_index, image in enumerate(review_images):
            summary.paste(
                review_tile(image, tile_size),
                (column_index * tile_size[0], row_y + label_height),
            )

    summary_path = sheets_dir / "all-states-assembly-review.png"
    summary.save(summary_path)
    return summary_path


def artifact_exists(value: str | Path | None) -> bool:
    if not value:
        return False
    path = project_path(value)
    return path.is_file() and path.stat().st_size > 0


def evaluate_battle_rig_acceptance(
    preset: dict[str, Any],
    component_metrics: list[dict[str, Any]],
    state_records: list[dict[str, Any]],
    summary_sheet: Path,
    semantic_gate: Any,
) -> dict[str, Any]:
    failures: list[str] = []

    def require(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    required_states = list(REQUIRED_BATTLE_STATES)
    semantic_checks = semantic_gate.get("checks") if isinstance(semantic_gate, dict) else None
    semantic_review_passed = (
        isinstance(semantic_gate, dict)
        and semantic_gate.get("passed") is True
        and isinstance(semantic_gate.get("reviewer"), str)
        and bool(semantic_gate["reviewer"].strip())
        and isinstance(semantic_checks, list)
        and bool(semantic_checks)
        and all(isinstance(check, dict) and check.get("passed") is True for check in semantic_checks)
    )
    require(
        semantic_review_passed,
        "component manifest must record a passed human semanticGate with reviewer and checks",
    )

    configured_states = preset.get("rigReuseConstraints", {}).get("verifiedStateLabels")
    require(preset.get("rig") == "battle", "preset rig must be battle")
    require(
        configured_states == required_states,
        "preset verifiedStateLabels must contain the canonical six battle states in order",
    )

    reuse_constraints = preset.get("rigReuseConstraints", {})
    require(
        reuse_constraints.get("uniqueSkinKeysPerGender") == REQUIRED_UNIQUE_SKINS,
        f"preset uniqueSkinKeysPerGender must be {REQUIRED_UNIQUE_SKINS}",
    )
    require(
        reuse_constraints.get("holderPlacementsPerPose") == REQUIRED_COMPONENT_PLACEMENTS,
        f"preset holderPlacementsPerPose must be {REQUIRED_COMPONENT_PLACEMENTS}",
    )

    gender = preset.get("gender")
    expected_skin_keys = preset.get("componentSkinKeysByGender", {}).get(gender)
    if not isinstance(expected_skin_keys, list):
        expected_skin_keys = []
    expected_skin_key_set = set(expected_skin_keys)
    require(
        len(expected_skin_keys) == REQUIRED_UNIQUE_SKINS
        and len(expected_skin_key_set) == REQUIRED_UNIQUE_SKINS,
        f"preset gender {gender!r} must resolve to {REQUIRED_UNIQUE_SKINS} unique skinKeys",
    )

    component_skin_keys = [item.get("skinKey") for item in component_metrics]
    override_keys = [item.get("overrideKey") for item in component_metrics]
    override_key_set = {key for key in override_keys if isinstance(key, str) and key}
    require(
        len(component_metrics) == REQUIRED_UNIQUE_SKINS,
        f"component manifest must contain {REQUIRED_UNIQUE_SKINS} components",
    )
    require(
        set(component_skin_keys) == expected_skin_key_set,
        "component manifest skinKeys must exactly match the preset gender closure",
    )
    require(
        len(override_key_set) == REQUIRED_UNIQUE_SKINS,
        f"component manifest must resolve to {REQUIRED_UNIQUE_SKINS} unique override PNGs",
    )

    executed_states = [record.get("stateLabel") for record in state_records]
    require(
        executed_states == required_states,
        "audit must execute the canonical six battle states exactly once and in order",
    )
    require(artifact_exists(summary_sheet), "all-states assembly review sheet must exist and be non-empty")

    records_by_state = {record.get("stateLabel"): record for record in state_records}
    expected_equipment = preset.get("equipment")
    for state in required_states:
        record = records_by_state.get(state)
        if not isinstance(record, dict):
            failures.append(f"{state}: state record is missing")
            continue
        require(artifact_exists(record.get("sheet")), f"{state}: state review sheet is missing")
        captures = record.get("captures") or {}
        harness = record.get("harness") or {}
        for mode in ("baseline", "fit", "masked"):
            require(artifact_exists(captures.get(mode)), f"{state}/{mode}: canvas capture is missing")
            mode_report = harness.get(mode) or {}
            status = mode_report.get("status") or {}
            probe = mode_report.get("probe") or {}
            require(status.get("rig") == "battle", f"{state}/{mode}: renderer did not report battle rig")
            require(status.get("stateLabel") == state, f"{state}/{mode}: renderer stateLabel mismatch")
            require(status.get("gender") == gender, f"{state}/{mode}: renderer gender mismatch")
            require(status.get("equipment") == expected_equipment, f"{state}/{mode}: equipment closure mismatch")
            require(status.get("missing") == 0, f"{state}/{mode}: renderer reported missing assets")
            key_map = status.get("keyMap") or {}
            require(
                isinstance(key_map, dict)
                and len(key_map) == REQUIRED_UNIQUE_SKINS
                and set(key_map.values()) == expected_skin_key_set,
                f"{state}/{mode}: runtime keyMap does not match all {REQUIRED_UNIQUE_SKINS} skinKeys",
            )
            require(
                isinstance(probe.get("alphaPixels"), int) and probe["alphaPixels"] > 0,
                f"{state}/{mode}: canvas is empty",
            )
            require(
                isinstance(probe.get("width"), int)
                and probe["width"] > 0
                and isinstance(probe.get("height"), int)
                and probe["height"] > 0,
                f"{state}/{mode}: canvas dimensions are invalid",
            )
            overrides = mode_report.get("skinOverrides") or {}
            if mode == "baseline":
                require(
                    overrides.get("count") == 0
                    and not overrides.get("hits")
                    and not overrides.get("missing"),
                    f"{state}/baseline: original assembly was contaminated by skin overrides",
                )
            else:
                hits = overrides.get("hits") or {}
                require(
                    overrides.get("count") == REQUIRED_UNIQUE_SKINS,
                    f"{state}/{mode}: override count is not {REQUIRED_UNIQUE_SKINS}",
                )
                require(not overrides.get("missing"), f"{state}/{mode}: declared overrides were not requested")
                require(
                    set(hits) == override_key_set
                    and all(isinstance(count, int) and count > 0 for count in hits.values()),
                    f"{state}/{mode}: override hit set does not cover all component PNGs",
                )

    return {
        "passed": not failures,
        "requiredRig": "battle",
        "requiredStates": required_states,
        "executedStates": executed_states,
        "requiredUniqueSkins": REQUIRED_UNIQUE_SKINS,
        "requiredComponentPlacementsPerPose": REQUIRED_COMPONENT_PLACEMENTS,
        "semanticComponentReviewPassed": semantic_review_passed,
        "expectedSkinKeys": expected_skin_keys,
        "expectedOverrideKeys": sorted(override_key_set),
        "failures": failures,
    }


def report_markdown(report: dict[str, Any]) -> str:
    acceptance = report["battleRigAcceptance"]
    acceptance_label = "PASS" if acceptance["passed"] else "FAIL"
    if report["gate"]["diagnosticOnly"]:
        acceptance_label += " (diagnostic run; not an acceptance claim)"
    lines = [
        "# Dressup Reskin Assembly Audit",
        "",
        f"- Mandatory battle-rig reassembly: **{acceptance_label}**",
        f"- Pipeline execution: **{'PASS' if report['gate']['pipelineExecuted'] else 'FAIL'}**",
        f"- Harness assembly: **{'PASS' if report['gate']['technicalAssemblyPassed'] else 'FAIL'}**",
        f"- Human component semantics: **{'PASS' if report['gate']['semanticComponentReviewPassed'] else 'FAIL'}**",
        f"- Geometry review: **{'REQUIRED' if report['gate']['geometryReviewRequired'] else 'PASS'}**",
        f"- States: {len(report['states'])}",
        f"- Components: {len(report['components'])}",
        "",
    ]
    if acceptance["failures"]:
        lines.extend(["## Battle-rig acceptance failures", ""])
        lines.extend(f"- {failure}" for failure in acceptance["failures"])
        lines.append("")
    lines.extend([
        "## Component geometry priority",
        "",
        "| Priority | Field | Aspect drift | Shared non-mirrored | Action |",
        "|---:|---|---:|:---:|---|",
    ])
    for index, component in enumerate(report["componentPriority"], start=1):
        lines.append(
            f"| {index} | {component['field']} | {component['aspectDriftPercent']:.2f}% | "
            f"{'yes' if component['sharedNonMirrored'] else 'no'} | {component['action']} |"
        )
    lines.extend(
        [
            "",
            "## State captures",
            "",
            "| State | Baseline alpha | Fit alpha delta | Fit symmetric diff | Masked symmetric diff |",
            "|---|---:|---:|---:|---:|",
        ]
    )
    for state in report["states"]:
        fit = state["alphaComparison"]["fit"]
        masked = state["alphaComparison"]["masked"]
        lines.append(
            f"| {state['stateLabel']} | {fit['referenceAlphaPixels']} | {fit['alphaPixelDelta']:+d} | "
            f"{fit['symmetricDifferenceOfUnion']:.4f} | {masked['symmetricDifferenceOfUnion']:.4f} |"
        )
    lines.extend(
        [
            "",
            "## Reading the sheet",
            "",
            "- Red pixels in the alpha-difference column exist only in the original assembly.",
            "- Cyan pixels exist only in the aspect-preserving generated assembly.",
            "- Gray pixels are shared silhouette coverage.",
            "- The masked preview is only a crop/occupancy diagnostic; zero alpha difference does not prove mechanical continuity and it is never a final asset.",
            "",
            "Summary sheet: `sheets/all-states-assembly-review.png`",
            "",
        ]
    )
    return "\n".join(lines)


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(value)


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--component-manifest", required=True)
    parser.add_argument("--dressup-preset", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--harness", default="tools/run-dressup-harness.js")
    parser.add_argument("--browser", default="edge", choices=("edge", "chrome"))
    parser.add_argument("--state", action="append", dest="states")
    parser.add_argument(
        "--diagnostic-only",
        action="store_true",
        help="Allow a partial --state run without claiming the mandatory battle-rig acceptance gate",
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    component_manifest_path = require_inside(
        project_path(args.component_manifest), PROJECT_ROOT, "component manifest"
    )
    preset_path = require_inside(project_path(args.dressup_preset), PROJECT_ROOT, "dressup preset")
    harness_path = require_inside(project_path(args.harness), PROJECT_ROOT, "dressup harness")
    output_dir = require_inside(project_path(args.output), PIPELINE_OUTPUT_ROOT, "output directory")
    if not component_manifest_path.is_file() or not preset_path.is_file() or not harness_path.is_file():
        raise FileNotFoundError("component manifest, dressup preset, and harness must all exist")
    output_dir.mkdir(parents=True, exist_ok=True)

    preset = read_json(preset_path)
    states = args.states or list(REQUIRED_BATTLE_STATES)
    if not isinstance(states, list) or not states or not all(isinstance(state, str) and state for state in states):
        raise ValueError("No valid Dressup states were provided")
    if not args.diagnostic_only and states != list(REQUIRED_BATTLE_STATES):
        raise ValueError(
            "Partial --state runs cannot satisfy the mandatory battle-rig gate; "
            "remove --state or add --diagnostic-only"
        )

    component_manifest = read_json(component_manifest_path)
    override_paths, component_metrics = prepare_preview_skins(component_manifest_path, output_dir)
    state_records: list[dict[str, Any]] = []
    for index, state in enumerate(states, start=1):
        slug = state_slug(index, state)
        captures: dict[str, str] = {}
        harness_reports: dict[str, Any] = {}
        for mode in ("baseline", "fit", "masked"):
            canvas_path = output_dir / "captures" / mode / f"{slug}.png"
            canvas_path.parent.mkdir(parents=True, exist_ok=True)
            payload = run_harness(
                harness_path=harness_path,
                preset_path=preset_path,
                browser=args.browser,
                state=state,
                canvas_path=canvas_path,
                override_path=None if mode == "baseline" else override_paths[mode],
            )
            captures[mode] = relative_project_path(canvas_path)
            harness_reports[mode] = {
                "headerText": payload["qa"].get("headerText"),
                "probe": payload["qa"].get("firstProbe"),
                "status": payload["qa"].get("status"),
                "skinOverrides": payload.get("skinOverrides"),
            }

        with Image.open(project_path(captures["baseline"])) as baseline_image:
            baseline = baseline_image.convert("RGBA")
        comparisons: dict[str, Any] = {}
        for mode in ("fit", "masked"):
            with Image.open(project_path(captures[mode])) as candidate_image:
                comparisons[mode] = alpha_comparison(baseline, candidate_image.convert("RGBA"))
        state_records.append(
            {
                "stateLabel": state,
                "slug": slug,
                "captures": captures,
                "alphaComparison": comparisons,
                "harness": harness_reports,
            }
        )

    summary_sheet = build_review_sheets(output_dir, state_records)
    priority: list[dict[str, Any]] = []
    for component in sorted(
        component_metrics,
        key=lambda item: item["fit"]["aspectDriftPercent"],
        reverse=True,
    ):
        drift = component["fit"]["aspectDriftPercent"]
        if drift >= 25:
            action = "regenerate boundary before Flash redraw"
        elif drift >= 15:
            action = "inspect joint envelope and regenerate if needed"
        else:
            action = "alignment/ownership review first"
        priority.append(
            {
                "field": component.get("field"),
                "skinKey": component.get("skinKey"),
                "sharedNonMirrored": component.get("sharedNonMirrored"),
                "aspectDriftPercent": drift,
                "action": action,
            }
        )

    technical_pass = all(
        record["harness"][mode]["status"].get("missing") == 0
        and not record["harness"][mode]["skinOverrides"].get("missing", [])
        for record in state_records
        for mode in ("fit", "masked")
    )
    battle_rig_acceptance = evaluate_battle_rig_acceptance(
        preset,
        component_metrics,
        state_records,
        summary_sheet,
        component_manifest.get("semanticGate"),
    )
    geometry_review_required = any(item["aspectDriftPercent"] >= 15 for item in priority)
    report = {
        "schema": 2,
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "componentManifest": relative_project_path(component_manifest_path),
        "dressupPreset": relative_project_path(preset_path),
        "outputDir": relative_project_path(output_dir),
        "modes": {
            "fit": "preserve generated aspect ratio inside the original canvas",
            "masked": "diagnostic projection only: cover the original canvas and restore the original alpha; never treat it as regenerated mechanical artwork",
        },
        "gate": {
            "pipelineExecuted": True,
            "technicalAssemblyPassed": technical_pass,
            "semanticComponentReviewPassed": battle_rig_acceptance[
                "semanticComponentReviewPassed"
            ],
            "battleRigReassemblyPassed": battle_rig_acceptance["passed"],
            "diagnosticOnly": bool(args.diagnostic_only),
            "geometryReviewRequired": geometry_review_required,
        },
        "battleRigAcceptance": battle_rig_acceptance,
        "components": component_metrics,
        "componentPriority": priority,
        "states": state_records,
        "summarySheet": relative_project_path(summary_sheet),
    }
    write_json(output_dir / "audit.json", report)
    write_text(output_dir / "README.md", report_markdown(report))
    print(json.dumps(report["gate"], ensure_ascii=False))
    print(relative_project_path(output_dir / "sheets" / "all-states-assembly-review.png"))
    if args.diagnostic_only:
        return 0 if technical_pass else 1
    return 0 if battle_rig_acceptance["passed"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise
