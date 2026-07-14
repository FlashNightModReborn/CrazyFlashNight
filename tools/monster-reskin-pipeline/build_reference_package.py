#!/usr/bin/env python3
"""Build a human-redraw reference package from FFDec monster exports."""

from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


REPO_ROOT = Path(__file__).resolve().parents[2]
MANAGED_OUTPUT_ROOT = REPO_ROOT / "tmp" / "monster-reskin"
GENERATED_DIRS = {"whole", "keyposes", "parts", "sheets"}
GENERATED_FILES = {"manifest.json", "README.md", "imagegen-prompt.txt", "component-imagegen-prompt.txt"}


def repo_path(value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else REPO_ROOT / path


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate(config: dict[str, Any]) -> None:
    missing = [key for key in ["monster", "outputDir", "source", "export", "keyposes", "parts"] if key not in config]
    if missing:
        raise ValueError(f"配置缺少字段：{', '.join(missing)}")
    sequences = config.get("sequences", [])
    sequence_slugs = [sequence["slug"] for sequence in sequences]
    if len(sequence_slugs) != len(set(sequence_slugs)):
        raise ValueError("sequences.slug 不得重复")
    if any(int(sequence["characterId"]) < 1 for sequence in sequences):
        raise ValueError("sequences.characterId 必须是正整数")
    for sequence in sequences:
        start = int(sequence.get("startFrame", 1))
        end = int(sequence.get("endFrame", start))
        if start < 1 or end < start:
            raise ValueError(f"无效序列帧范围：{sequence['slug']} {start}..{end}")

    pose_slugs = [pose["slug"] for pose in config["keyposes"]]
    if not pose_slugs or len(pose_slugs) != len(set(pose_slugs)):
        raise ValueError("keyposes.slug 必须存在且不得重复")
    pose_frames = []
    for pose in config["keyposes"]:
        frame = int(pose["frame"])
        if frame < 1:
            raise ValueError("keyposes.frame 必须是正整数")
        sequence = pose.get("sequence", "root")
        if sequences and sequence not in sequence_slugs:
            raise ValueError(f"关键姿势引用未知序列：{pose['slug']} -> {sequence}")
        pose_frames.append((sequence, frame))
    if len(pose_frames) != len(set(pose_frames)):
        raise ValueError("keyposes 的 sequence + frame 组合不得重复")
    slugs = [part["slug"] for part in config["parts"]]
    if len(slugs) != len(set(slugs)):
        raise ValueError("parts.slug 不得重复")


def require_safe_output(path: Path) -> Path:
    resolved = path.resolve()
    root = MANAGED_OUTPUT_ROOT.resolve()
    try:
        relative = resolved.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"outputDir 必须位于 {root} 下：{resolved}") from exc
    if not relative.parts:
        raise ValueError(f"outputDir 不得直接指向受管根目录：{root}")
    return resolved


def clean_generated(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    for name in GENERATED_DIRS:
        path = output / name
        if path.exists():
            shutil.rmtree(path)
    for name in GENERATED_FILES:
        path = output / name
        if path.exists():
            path.unlink()


def numeric_frames(frame_dir: Path) -> dict[int, Path]:
    result = {int(path.stem): path for path in frame_dir.glob("*.png") if path.stem.isdigit()}
    if not result:
        raise FileNotFoundError(f"未找到数字帧 PNG：{frame_dir}")
    return dict(sorted(result.items()))


def prepare_frame_canvas(path: Path, config: dict[str, Any]) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    crop = config.get("subjectCrop")
    if crop:
        image = image.crop(tuple(int(value) for value in crop))
    ignore = float(config.get("ignoreTopFraction", 0.0))
    if ignore:
        cutoff = min(image.height, max(0, int(image.height * ignore)))
        if cutoff >= image.height:
            raise ValueError(f"ignoreTopFraction 清空了整帧：{path.name}")
        boundary = image.getchannel("A").crop((0, cutoff, image.width, cutoff + 1))
        if boundary.getbbox():
            raise ValueError(
                f"ignoreTopFraction 穿过非透明内容：{path.name} y={cutoff}；"
                "请改用无 UI 的动作 Sprite 或安全裁剪区域"
            )
        cleared = Image.new("RGBA", image.size, (0, 0, 0, 0))
        cleared.alpha_composite(image.crop((0, cutoff, image.width, image.height)), (0, cutoff))
        image = cleared
    return image


def crop_subject(path: Path, config: dict[str, Any]) -> Image.Image:
    image = prepare_frame_canvas(path, config)
    bbox = image.getchannel("A").getbbox()
    if not bbox:
        raise ValueError(f"清理 UI 后帧为空：{path.name}")
    padding = int(config.get("keyposePadding", 24))
    # Pillow 会把超出原图的 RGBA crop 区域补为透明像素。不要在源画布
    # 边界 clamp，否则贴边动作会悄悄丢掉约定的 keypose 留白。
    left = bbox[0] - padding
    top = bbox[1] - padding
    right = bbox[2] + padding
    bottom = bbox[3] + padding
    return image.crop((left, top, right, bottom))


def fit(image: Image.Image, max_size: tuple[int, int]) -> Image.Image:
    copy = image.copy()
    copy.thumbnail(max_size, Image.Resampling.LANCZOS)
    return copy


def sheet_font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def contact_sheet(entries: list[tuple[str, Image.Image, str]], columns: int, cell: tuple[int, int]) -> Image.Image:
    columns = max(1, columns)
    rows = max(1, math.ceil(len(entries) / columns))
    sheet = Image.new("RGBA", (cell[0] * columns, cell[1] * rows), (242, 242, 238, 255))
    draw = ImageDraw.Draw(sheet)
    label_font = sheet_font(17, bold=True)
    note_font = sheet_font(13)
    for index, (label, source, note) in enumerate(entries):
        x0 = (index % columns) * cell[0]
        y0 = (index // columns) * cell[1]
        preview = fit(source, (cell[0] - 24, cell[1] - 70))
        px = x0 + (cell[0] - preview.width) // 2
        py = y0 + 34 + (cell[1] - 70 - preview.height) // 2
        sheet.alpha_composite(preview, (px, py))
        draw.text((x0 + 10, y0 + 8), label, fill=(24, 24, 24, 255), font=label_font)
        if note:
            draw.text((x0 + 10, y0 + cell[1] - 25), note[:38], fill=(82, 82, 82, 255), font=note_font)
        draw.rectangle((x0, y0, x0 + cell[0] - 1, y0 + cell[1] - 1), outline=(190, 190, 184, 255), width=1)
    return sheet


def origin_overlay(image: Image.Image, origin: dict[str, float] | None) -> tuple[Image.Image, dict[str, int]]:
    source = image.copy().convert("RGBA")
    if not origin:
        return source, {"x": 0, "y": 0}
    x, y = round(float(origin["x"])), round(float(origin["y"]))
    radius = max(12, min(source.size) // 18)
    marker_margin = radius + 6
    offset_x = max(0, marker_margin - x)
    offset_y = max(0, marker_margin - y)
    right = max(source.width + offset_x, x + offset_x + marker_margin + 1)
    bottom = max(source.height + offset_y, y + offset_y + marker_margin + 1)
    result = Image.new("RGBA", (right, bottom), (0, 0, 0, 0))
    result.alpha_composite(source, (offset_x, offset_y))
    marker_x = x + offset_x
    marker_y = y + offset_y
    draw = ImageDraw.Draw(result)
    draw.line((marker_x - radius, marker_y, marker_x + radius, marker_y), fill=(255, 30, 30, 255), width=3)
    draw.line((marker_x, marker_y - radius, marker_x, marker_y + radius), fill=(255, 30, 30, 255), width=3)
    draw.ellipse(
        (marker_x - 4, marker_y - 4, marker_x + 4, marker_y + 4),
        outline=(255, 255, 255, 255),
        width=2,
    )
    return result, {"x": offset_x, "y": offset_y}


def validate_export_identity(config: dict[str, Any], export_manifest: dict[str, Any]) -> None:
    source = config["source"]
    errors: list[str] = []
    expected_swf = rel(repo_path(source["swf"]))
    if export_manifest.get("monster") != config["monster"]:
        errors.append("monster")
    if export_manifest.get("sourceSwf") != expected_swf:
        errors.append("sourceSwf")
    if int(export_manifest.get("root", {}).get("characterId", -1)) != int(source["rootCharacterId"]):
        errors.append("root.characterId")

    exported_parts = {item.get("slug"): item for item in export_manifest.get("parts", [])}
    for part in config["parts"]:
        exported = exported_parts.get(part["slug"])
        if not exported or int(exported.get("characterId", -1)) != int(part["characterId"]):
            errors.append(f"parts.{part['slug']}.characterId")

    configured_sequences = config.get("sequences", [])
    if configured_sequences:
        exported_sequences = {item.get("slug"): item for item in export_manifest.get("sequences", [])}
        for sequence in configured_sequences:
            exported = exported_sequences.get(sequence["slug"])
            if not exported or int(exported.get("characterId", -1)) != int(sequence["characterId"]):
                errors.append(f"sequences.{sequence['slug']}.characterId")
    if errors:
        raise ValueError("FFDec 导出清单与当前配置不一致：" + ", ".join(errors))


def write_readme(config: dict[str, Any], output: Path, part_records: list[dict[str, Any]]) -> None:
    source = config["source"]
    lines = [
        f"# {config['monster']} 换皮参考包",
        "",
        "本目录由只读导出工具生成，用于人类重绘和 img2img 构思，不修改原始 XFL/SWF。",
        "",
        "## 来源",
        "",
        f"- XFL：`{source.get('xfl', '')}`",
        f"- SWF：`{source['swf']}`",
        f"- linkage：`{config.get('linkage', config['monster'])}`",
        f"- 根 SWF character：`{source['rootCharacterId']}`",
        "",
        "## 使用顺序",
        "",
        "1. 先看 `sheets/keyposes.png`，确认站立、跑、扑咬、受击、击倒与死亡的轮廓极值。",
        "2. 看 `sheets/parts-normal-rig.png` 重绘共享骨架件；红十字是局部原点，必须保留。",
        "3. 单独检查 `sheets/parts-death-only.png`；若使用原血腥死亡动画，这组也必须随皮肤重绘。",
        "4. 在 XFL 中复制原美术依赖，新建 linkage；保留时间轴脚本、攻击点、碰撞和装配矩阵。",
        "5. 用 `whole/full-sequence/<动作>/` 的固定画布序列检查遮挡、脚掌滑动、咬合端点和翻滚露缝。",
        "",
        "## 零件",
        "",
    ]
    for part in part_records:
        lines.append(f"- `{part['symbol']}` / SWF `{part['characterId']}`：{part['label']}（{part['group']}）。")
    if config.get("variants"):
        lines.extend(["", "## 犬型可行度", ""])
        for variant in config["variants"]:
            lines.append(f"- **{variant['name']}**：{variant['feasibility']}。{variant['boundary']}")
    if config.get("tailPlans"):
        lines.extend(["", "## 尾巴换皮范围", ""])
        for plan in config["tailPlans"]:
            lines.append(f"- **{plan['variant']}**：原长 `{plan['lengthScale']}×`。{plan['reason']}")
    if config.get("warlordRecognitionYoke"):
        yoke = config["warlordRecognitionYoke"]
        lines.extend([
            "",
            "## 军阀反渗透识别鞍",
            "",
            f"- 设定：{yoke['lore']}",
            f"- 外观：{yoke['visual']}",
            f"- 边界：{yoke['boundary']}",
        ])
    if config.get("vectorRedrawGuardrails"):
        lines.extend(["", "## 矢量重绘约束", ""])
        lines.extend(f"- {item}" for item in config["vectorRedrawGuardrails"])
    if config.get("componentConcepts"):
        lines.extend(["", "## 三犬常规 13 件组件参考", ""])
        for concept in config["componentConcepts"]:
            lines.append(
                f"- **{concept['variant']}**：`{concept['file']}`。"
                f"独立分件：`{concept.get('splitDir', '')}`。"
                f"{concept.get('designBrief', '')}{concept['allocation']}"
            )
    if config.get("componentSheetOrder"):
        lines.extend(["", "### 组件板格序", ""])
        lines.extend(f"- {item}" for item in config["componentSheetOrder"])
    if config.get("componentRedrawCaveats"):
        lines.extend(["", "### 回填注意事项", ""])
        lines.extend(f"- {item}" for item in config["componentRedrawCaveats"])
    if config.get("guardrails"):
        lines.extend(["", "## 护栏", ""])
        lines.extend(f"- {item}" for item in config["guardrails"])
    lines.append("")
    (output / "README.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()

    config_path = repo_path(args.config)
    config = load_json(config_path)
    validate(config)
    export_manifest_path = repo_path(config["export"]["stagingDir"]) / "export-manifest.json"
    if not export_manifest_path.exists():
        raise FileNotFoundError(f"缺少 FFDec 导出清单，请先运行 export_ffdec_assets.py：{export_manifest_path}")
    export_manifest = load_json(export_manifest_path)
    validate_export_identity(config, export_manifest)
    part_exports = {item["slug"]: item for item in export_manifest["parts"]}
    sequence_specs = config.get("sequences", [])
    if sequence_specs:
        sequence_exports = {item["slug"]: item for item in export_manifest["sequences"]}
    else:
        sequence_specs = [{
            "slug": "root",
            "label": "root",
            "characterId": int(config["source"]["rootCharacterId"]),
            "startFrame": 1,
            "endFrame": int(export_manifest["root"]["frameCount"]),
        }]
        sequence_exports = {"root": export_manifest["root"]}

    sequences: dict[str, dict[str, Any]] = {}
    for spec in sequence_specs:
        exported = sequence_exports[spec["slug"]]
        available = numeric_frames(repo_path(exported["frameDir"]))
        start = int(spec.get("startFrame", 1))
        end = int(spec.get("endFrame", max(available)))
        selected = {frame: path for frame, path in available.items() if start <= frame <= end}
        missing_range = [frame for frame in range(start, end + 1) if frame not in selected]
        if missing_range:
            raise ValueError(f"序列导出不完整：{spec['slug']} missing frames={missing_range}")
        sequences[spec["slug"]] = {"spec": spec, "exported": exported, "frames": selected}

    missing_frames = [
        f"{pose.get('sequence', 'root')}:{pose['frame']}"
        for pose in config["keyposes"]
        if int(pose["frame"]) not in sequences[pose.get("sequence", "root")]["frames"]
    ]
    missing_parts = [part["slug"] for part in config["parts"] if part["slug"] not in part_exports]
    if missing_frames or missing_parts:
        raise ValueError(f"导出不完整：missing frames={missing_frames}, missing parts={missing_parts}")
    if args.check_only:
        frame_count = sum(len(sequence["frames"]) for sequence in sequences.values())
        print(f"OK: {config['monster']} / {len(sequences)} sequences / {frame_count} frames / {len(part_exports)} parts")
        return 0

    output = require_safe_output(repo_path(config["outputDir"]))
    clean_generated(output)
    for directory in ["whole/full-sequence", "keyposes", "parts/png", "parts/svg", "parts/with-origin", "sheets"]:
        (output / directory).mkdir(parents=True, exist_ok=True)

    prepared_frames: dict[tuple[str, int], Image.Image] = {}
    sequence_records: list[dict[str, Any]] = []
    for slug, sequence in sequences.items():
        target_dir = output / "whole/full-sequence" / slug
        target_dir.mkdir(parents=True, exist_ok=True)
        for frame_no, path in sequence["frames"].items():
            image = prepare_frame_canvas(path, config)
            if not image.getchannel("A").getbbox():
                continue
            prepared_frames[(slug, frame_no)] = image
            image.save(target_dir / f"{frame_no:04d}.png", optimize=True)
        sequence_records.append({
            "slug": slug,
            "label": sequence["spec"].get("label", slug),
            "characterId": int(sequence["spec"]["characterId"]),
            "startFrame": int(sequence["spec"].get("startFrame", 1)),
            "endFrame": int(sequence["spec"].get("endFrame", max(sequence["frames"]))),
            "visibleFrameCount": sum(1 for key in prepared_frames if key[0] == slug),
            "directory": f"whole/full-sequence/{slug}",
        })

    key_entries: list[tuple[str, Image.Image, str]] = []
    key_records: list[dict[str, Any]] = []
    key_images: dict[str, Image.Image] = {}
    for pose in config["keyposes"]:
        sequence_slug = pose.get("sequence", "root")
        frame_no = int(pose["frame"])
        frame_path = sequences[sequence_slug]["frames"][frame_no]
        image = crop_subject(frame_path, config)
        filename = f"{frame_no:04d}_{pose['slug']}.png"
        image.save(output / "keyposes" / filename, optimize=True)
        key_images[pose["slug"]] = image
        key_entries.append((f"{pose['label']} · {sequence_slug}:{frame_no}", image, pose.get("note", "")))
        key_records.append({**pose, "sequence": sequence_slug, "file": f"keyposes/{filename}"})
    contact_sheet(key_entries, int(config.get("keyposeColumns", 4)), (330, 270)).convert("RGB").save(output / "sheets/keyposes.png", quality=95)
    hero_pose = config.get("heroPose", config["keyposes"][0]["slug"])
    if hero_pose not in key_images:
        raise ValueError(f"heroPose 未命中关键姿势：{hero_pose}")
    key_images[hero_pose].save(output / "whole/core.png", optimize=True)

    part_records: list[dict[str, Any]] = []
    group_entries: dict[str, list[tuple[str, Image.Image, str]]] = {}
    for index, part in enumerate(config["parts"], start=1):
        exported = part_exports[part["slug"]]
        png_source = repo_path(exported["png"])
        svg_source = repo_path(exported["svg"])
        base = f"{index:02d}_{part['slug']}"
        png_target = output / "parts/png" / f"{base}.png"
        svg_target = output / "parts/svg" / f"{base}.svg"
        shutil.copy2(png_source, png_target)
        shutil.copy2(svg_source, svg_target)
        image = Image.open(png_source).convert("RGBA")
        origin = part.get("localOriginPx") or exported.get("localOriginPx")
        overlay, overlay_offset = origin_overlay(image, origin)
        overlay.save(output / "parts/with-origin" / f"{base}.png", optimize=True)
        group = part.get("group", "normal-rig")
        group_entries.setdefault(group, []).append((f"{part['characterId']} {part['label']}", overlay, part.get("symbol", "")))
        part_records.append({
            **part,
            "group": group,
            "png": f"parts/png/{base}.png",
            "svg": f"parts/svg/{base}.svg",
            "originOverlay": f"parts/with-origin/{base}.png",
            "localOriginPx": origin,
            "originOverlayOffsetPx": overlay_offset,
        })
    for group, entries in group_entries.items():
        contact_sheet(entries, int(config.get("partColumns", 4)), (320, 250)).convert("RGB").save(output / "sheets" / f"parts-{group}.png", quality=95)

    manifest = {
        "schemaVersion": 1,
        "monster": config["monster"],
        "source": config["source"],
        "exportManifest": rel(export_manifest_path),
        "heroPose": hero_pose,
        "sequences": sequence_records,
        "exportedSequenceFrameCount": len(prepared_frames),
        "keyposes": key_records,
        "parts": part_records,
        "variants": config.get("variants", []),
        "tailPlans": config.get("tailPlans", []),
        "warlordRecognitionYoke": config.get("warlordRecognitionYoke"),
        "vectorRedrawGuardrails": config.get("vectorRedrawGuardrails", []),
        "componentSheetOrder": config.get("componentSheetOrder", []),
        "componentConcepts": config.get("componentConcepts", []),
        "componentRedrawCaveats": config.get("componentRedrawCaveats", []),
        "componentImagegenPromptTemplate": config.get("componentImagegenPromptTemplate", ""),
        "guardrails": config.get("guardrails", []),
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "imagegen-prompt.txt").write_text(config.get("imagegenPrompt", "") + "\n", encoding="utf-8")
    (output / "component-imagegen-prompt.txt").write_text(
        config.get("componentImagegenPromptTemplate", "") + "\n",
        encoding="utf-8",
    )
    write_readme(config, output, part_records)
    print(f"OK: {output} / {len(sequences)} sequences / {len(prepared_frames)} visible frames / {len(part_records)} parts")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
