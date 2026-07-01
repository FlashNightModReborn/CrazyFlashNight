#!/usr/bin/env python3
"""Build a consolidated review package for intelligence icons.

Input is a TSV manifest with at least:
id, slug, title, status, source, note

The script copies selected PNGs into a stable final folder and emits review
sheets, alpha stats, and a normalized status TSV. It deliberately uses an
explicit manifest because final picks may come from main rounds or later
single-icon retune folders.
"""

from __future__ import annotations

import argparse
import csv
import shutil
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


@dataclass(frozen=True)
class IconEntry:
    id: str
    slug: str
    title: str
    status: str
    source: Path
    note: str

    @property
    def output_name(self) -> str:
        return f"{self.id}-{self.slug}.png"


def read_manifest(path: Path) -> list[IconEntry]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"id", "slug", "title", "status", "source", "note"}
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise ValueError(f"manifest missing columns: {sorted(missing)}")
        entries = [
            IconEntry(
                id=row["id"].zfill(2),
                slug=row["slug"],
                title=row["title"],
                status=row["status"],
                source=Path(row["source"]),
                note=row["note"],
            )
            for row in reader
            if row.get("id")
        ]
    return sorted(entries, key=lambda item: int(item.id))


def checker(size: tuple[int, int], cell: int = 12) -> Image.Image:
    width, height = size
    image = Image.new("RGBA", size, (245, 245, 245, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, height, cell):
        for x in range(0, width, cell):
            if ((x // cell) + (y // cell)) % 2:
                draw.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(210, 210, 210, 255))
    return image


def fit_icon(path: Path, size: int) -> Image.Image:
    icon = Image.open(path).convert("RGBA")
    icon.thumbnail((size, size), Image.Resampling.LANCZOS)
    background = checker((size, size), max(4, size // 16))
    background.alpha_composite(icon, ((size - icon.width) // 2, (size - icon.height) // 2))
    return background


def load_fonts() -> tuple[ImageFont.ImageFont, ImageFont.ImageFont]:
    try:
        return ImageFont.truetype("arial.ttf", 18), ImageFont.truetype("arial.ttf", 13)
    except OSError:
        return ImageFont.load_default(), ImageFont.load_default()


def copy_finals(entries: list[IconEntry], final_dir: Path) -> list[tuple[IconEntry, Path]]:
    final_dir.mkdir(parents=True, exist_ok=True)
    copied: list[tuple[IconEntry, Path]] = []
    for entry in entries:
        if not entry.source.exists():
            raise FileNotFoundError(f"missing source for #{entry.id}: {entry.source}")
        target = final_dir / entry.output_name
        shutil.copy2(entry.source, target)
        copied.append((entry, target))
    return copied


def write_status(copied: list[tuple[IconEntry, Path]], review_dir: Path) -> None:
    with (review_dir / "final-status.tsv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(["id", "slug", "title", "status", "note", "source", "file"])
        for entry, path in copied:
            writer.writerow(
                [
                    entry.id,
                    entry.slug,
                    entry.title,
                    entry.status,
                    entry.note,
                    entry.source.as_posix(),
                    path.as_posix(),
                ]
            )


def write_alpha_stats(copied: list[tuple[IconEntry, Path]], review_dir: Path) -> None:
    with (review_dir / "final-alpha-stats.tsv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(["id", "file", "size", "transparent", "semi", "opaque", "corners_alpha_zero"])
        for entry, path in copied:
            image = Image.open(path).convert("RGBA")
            alphas = [pixel[3] for pixel in image.getdata()]
            corners = [
                image.getpixel((0, 0))[3],
                image.getpixel((image.width - 1, 0))[3],
                image.getpixel((0, image.height - 1))[3],
                image.getpixel((image.width - 1, image.height - 1))[3],
            ]
            writer.writerow(
                [
                    entry.id,
                    path.name,
                    f"{image.width}x{image.height}",
                    sum(a == 0 for a in alphas),
                    sum(0 < a < 255 for a in alphas),
                    sum(a == 255 for a in alphas),
                    all(a == 0 for a in corners),
                ]
            )


def draw_overview(copied: list[tuple[IconEntry, Path]], review_dir: Path) -> None:
    font, small = load_fonts()
    cols = 6
    thumb = 150
    cell_w = 210
    cell_h = 225
    margin = 20
    header = 52
    rows = (len(copied) + cols - 1) // cols
    sheet = Image.new("RGBA", (margin * 2 + cols * cell_w, header + margin + rows * cell_h), (238, 238, 238, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 14), "Intelligence icons final review package", fill=(20, 20, 20), font=font)
    for index, (entry, path) in enumerate(copied):
        x = margin + (index % cols) * cell_w
        y = header + (index // cols) * cell_h
        draw.text((x, y + 4), f"#{entry.id} {entry.title}", fill=(20, 20, 20), font=small)
        sheet.alpha_composite(fit_icon(path, thumb), (x, y + 28))
        draw.text((x, y + 186), entry.note[:34], fill=(70, 70, 70), font=small)
    sheet.convert("RGB").save(review_dir / "final-overview-sheet.png")


def draw_preview(copied: list[tuple[IconEntry, Path]], review_dir: Path) -> None:
    _, small = load_fonts()
    cols = 18
    cell_w = 58
    cell_h = 82
    rows = (len(copied) + cols - 1) // cols
    sheet = Image.new("RGBA", (20 + cols * cell_w, 30 + rows * cell_h), (238, 238, 238, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((10, 6), "Final 32px preview", fill=(20, 20, 20), font=small)
    for index, (entry, path) in enumerate(copied):
        x = 10 + (index % cols) * cell_w
        y = 28 + (index // cols) * cell_h
        sheet.alpha_composite(fit_icon(path, 32), (x + 13, y))
        draw.text((x + 10, y + 44), f"#{entry.id}", fill=(20, 20, 20), font=small)
    sheet.convert("RGB").save(review_dir / "final-preview-32-sheet.png")


def write_readme(out_dir: Path, icon_count: int, remaining_count: int) -> None:
    if remaining_count:
        remaining_section = """## 剩余施工范围

下一轮只剩高风险 smoke 组：

- `#15 学校与摇滚敌对的缘由？`
- `#16 从宝石线人视角一窥新经济野望`
- `#19 ECHO-034的加密日志`
- `#24 丽丽丝的芯片数据`
- `#36 堕落城净水材料供应告急`

主要风险：`gem-read`、`tool-read`、强物件抢主轮廓。
"""
    else:
        remaining_section = """## 剩余施工范围

当前无剩余未施工项；41 张情报图标已全部进入冻结包。
"""

    readme = f"""# Intelligence Icons Final Review Package

日期：2026-06-30

本目录聚合当前已确认的情报图标抽卡结果，用于集中审阅与后续接入前对账。

## 状态

- 已冻结：`{icon_count}/41`
- 未施工：`{remaining_count}/41`
- 未施工清单：`manifest/remaining-unbuilt.tsv`

## 目录

- `final/`：已确认最终 PNG，使用稳定 `NN-slug.png` 文件名。
- `manifest/final-icons.tsv`：每张最终 PNG 的来源路径、状态和备注。
- `manifest/remaining-unbuilt.tsv`：剩余未施工项与下一轮 smoke 风险。
- `review/final-overview-sheet.png`：大图总览。
- `review/final-preview-32-sheet.png`：32px 总览。
- `review/final-alpha-stats.tsv`：透明度与四角 alpha 检查。
- `review/final-status.tsv`：聚合后的最终状态表。

## 重新生成

```powershell
python tools/intelligence-icons/build_review_package.py `
  --manifest outputs/intelligence-icons/final-review-2026-06-30/manifest/final-icons.tsv `
  --remaining outputs/intelligence-icons/final-review-2026-06-30/manifest/remaining-unbuilt.tsv `
  --out outputs/intelligence-icons/final-review-2026-06-30 `
  --clean
```

{remaining_section}
"""
    (out_dir / "README.md").write_text(readme, encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--remaining", type=Path)
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()

    manifest_bytes = args.manifest.read_bytes()
    remaining_bytes = args.remaining.read_bytes() if args.remaining else None
    entries = read_manifest(args.manifest)
    remaining_count = 0
    if remaining_bytes is not None:
        remaining_text = remaining_bytes.decode("utf-8-sig")
        remaining_count = max(0, len([line for line in remaining_text.splitlines() if line.strip()]) - 1)
    if args.clean and args.out.exists():
        shutil.rmtree(args.out)
    final_dir = args.out / "final"
    review_dir = args.out / "review"
    manifest_dir = args.out / "manifest"
    review_dir.mkdir(parents=True, exist_ok=True)
    manifest_dir.mkdir(parents=True, exist_ok=True)

    (manifest_dir / "final-icons.tsv").write_bytes(manifest_bytes)
    if remaining_bytes is not None:
        (manifest_dir / "remaining-unbuilt.tsv").write_bytes(remaining_bytes)

    copied = copy_finals(entries, final_dir)
    write_status(copied, review_dir)
    write_alpha_stats(copied, review_dir)
    draw_overview(copied, review_dir)
    draw_preview(copied, review_dir)
    write_readme(args.out, len(copied), remaining_count)

    print(f"built {args.out}")
    print(f"icons={len(copied)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
