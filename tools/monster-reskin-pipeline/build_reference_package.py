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
    frames = [int(pose["frame"]) for pose in config["keyposes"]]
    if not frames or min(frames) < 1 or len(frames) != len(set(frames)):
        raise ValueError("keyposes.frame 必须是互不重复的正整数")
    slugs = [part["slug"] for part in config["parts"]]
    if len(slugs) != len(set(slugs)):
        raise ValueError("parts.slug 不得重复")


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


def crop_subject(path: Path, config: dict[str, Any]) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    crop = config.get("subjectCrop")
    if crop:
        image = image.crop(tuple(int(value) for value in crop))
    ignore = float(config.get("ignoreTopFraction", 0.0))
    if ignore:
        cutoff = min(image.height, max(0, int(image.height * ignore)))
        cleared = Image.new("RGBA", image.size, (0, 0, 0, 0))
        cleared.alpha_composite(image.crop((0, cutoff, image.width, image.height)), (0, cutoff))
        image = cleared
    bbox = image.getchannel("A").getbbox()
    if not bbox:
        raise ValueError(f"清理 UI 后帧为空：{path.name}")
    padding = int(config.get("keyposePadding", 24))
    left = max(0, bbox[0] - padding)
    top = max(0, bbox[1] - padding)
    right = min(image.width, bbox[2] + padding)
    bottom = min(image.height, bbox[3] + padding)
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


def origin_overlay(image: Image.Image, origin: dict[str, float] | None) -> Image.Image:
    result = image.copy().convert("RGBA")
    if not origin:
        return result
    x, y = round(float(origin["x"])), round(float(origin["y"]))
    draw = ImageDraw.Draw(result)
    radius = max(12, min(result.size) // 18)
    draw.line((x - radius, y, x + radius, y), fill=(255, 30, 30, 255), width=3)
    draw.line((x, y - radius, x, y + radius), fill=(255, 30, 30, 255), width=3)
    draw.ellipse((x - 4, y - 4, x + 4, y + 4), outline=(255, 255, 255, 255), width=2)
    return result


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
        "5. 用 `whole/full-sequence/` 检查遮挡、脚掌滑动、咬合端点和翻滚露缝。",
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
    frame_dir = repo_path(export_manifest["root"]["frameDir"])
    frames = numeric_frames(frame_dir)
    part_exports = {item["slug"]: item for item in export_manifest["parts"]}
    missing_frames = [pose["frame"] for pose in config["keyposes"] if int(pose["frame"]) not in frames]
    missing_parts = [part["slug"] for part in config["parts"] if part["slug"] not in part_exports]
    if missing_frames or missing_parts:
        raise ValueError(f"导出不完整：missing frames={missing_frames}, missing parts={missing_parts}")
    if args.check_only:
        print(f"OK: {config['monster']} / {len(frames)} frames / {len(part_exports)} parts")
        return 0

    output = repo_path(config["outputDir"])
    clean_generated(output)
    for directory in ["whole/full-sequence", "keyposes", "parts/png", "parts/svg", "parts/with-origin", "sheets"]:
        (output / directory).mkdir(parents=True, exist_ok=True)

    cropped_frames: dict[int, Image.Image] = {}
    for frame_no, path in frames.items():
        try:
            image = crop_subject(path, config)
        except ValueError:
            continue
        cropped_frames[frame_no] = image
        image.save(output / "whole/full-sequence" / f"{frame_no:04d}.png", optimize=True)
    hero_frame = int(config.get("heroFrame", config["keyposes"][0]["frame"]))
    if hero_frame not in cropped_frames:
        raise ValueError(f"heroFrame 清理后为空：{hero_frame}")
    cropped_frames[hero_frame].save(output / "whole/core.png", optimize=True)

    key_entries: list[tuple[str, Image.Image, str]] = []
    key_records: list[dict[str, Any]] = []
    for pose in config["keyposes"]:
        frame_no = int(pose["frame"])
        if frame_no not in cropped_frames:
            raise ValueError(f"关键帧清理后为空：{frame_no}")
        filename = f"{frame_no:04d}_{pose['slug']}.png"
        cropped_frames[frame_no].save(output / "keyposes" / filename, optimize=True)
        key_entries.append((f"{frame_no}. {pose['label']}", cropped_frames[frame_no], pose.get("note", "")))
        key_records.append({**pose, "file": f"keyposes/{filename}"})
    contact_sheet(key_entries, int(config.get("keyposeColumns", 4)), (330, 270)).convert("RGB").save(output / "sheets/keyposes.png", quality=95)

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
        overlay = origin_overlay(image, origin)
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
        })
    for group, entries in group_entries.items():
        contact_sheet(entries, int(config.get("partColumns", 4)), (320, 250)).convert("RGB").save(output / "sheets" / f"parts-{group}.png", quality=95)

    manifest = {
        "schemaVersion": 1,
        "monster": config["monster"],
        "source": config["source"],
        "exportManifest": rel(export_manifest_path),
        "heroFrame": hero_frame,
        "exportedSequenceFrameCount": len(cropped_frames),
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
    print(f"OK: {output} / {len(cropped_frames)} visible frames / {len(part_records)} parts")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
