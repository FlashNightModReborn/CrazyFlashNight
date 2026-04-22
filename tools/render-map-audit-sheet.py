from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from PIL import Image, ImageColor, ImageDraw, ImageFont


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render visual audit sheets for CF7 map hotspots and avatars.")
    parser.add_argument("--page", action="append", dest="pages", default=[], help="Page id to render. Repeatable.")
    parser.add_argument("--kind", choices=["all", "hotspot", "avatar"], default="all", help="Sheet kind to render.")
    parser.add_argument("--out-dir", default="tmp/map-audit-sheets", help="Output directory relative to repo root.")
    parser.add_argument("--scale", type=float, default=1.0, help="Output scale multiplier.")
    return parser.parse_args()


def load_json(command: list[str], cwd: Path) -> dict:
    result = subprocess.run(
        command,
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return json.loads(result.stdout)


def resolve_asset_path(repo_root: Path, asset_ref: str) -> Path:
    return repo_root / "launcher" / "web" / Path(*asset_ref.split("/"))


def rgba(hex_color: str, alpha: int) -> tuple[int, int, int, int]:
    rgb = ImageColor.getrgb(hex_color)
    return rgb[0], rgb[1], rgb[2], alpha


def scaled_rect(rect: dict, scale: float) -> tuple[int, int, int, int]:
    left = int(round(rect["x"] * scale))
    top = int(round(rect["y"] * scale))
    right = int(round((rect["x"] + rect["w"]) * scale))
    bottom = int(round((rect["y"] + rect["h"]) * scale))
    return left, top, right, bottom


def draw_label(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, font: ImageFont.ImageFont) -> None:
    bbox = draw.textbbox((x, y), text, font=font)
    pad_x = 5
    pad_y = 3
    bg = (14, 22, 18, 220)
    fg = (214, 255, 178, 255)
    draw.rounded_rectangle(
        (bbox[0] - pad_x, bbox[1] - pad_y, bbox[2] + pad_x, bbox[3] + pad_y),
        radius=4,
        fill=bg,
        outline=(94, 140, 64, 235),
        width=1,
    )
    draw.text((x, y), text, fill=fg, font=font)


def paste_asset(canvas: Image.Image, asset_path: Path, rect: dict, scale: float) -> None:
    left, top, right, bottom = scaled_rect(rect, scale)
    width = max(1, right - left)
    height = max(1, bottom - top)
    if asset_path.exists():
        asset = Image.open(asset_path).convert("RGBA").resize((width, height), Image.Resampling.LANCZOS)
        canvas.alpha_composite(asset, (left, top))
        return

    placeholder = Image.new("RGBA", (width, height), (40, 16, 16, 110))
    canvas.alpha_composite(placeholder, (left, top))


def create_base_canvas(size: dict, scale: float) -> Image.Image:
    width = max(1, int(round(size["width"] * scale)))
    height = max(1, int(round(size["height"] * scale)))
    background = Image.new("RGBA", (width, height), (6, 10, 9, 255))
    vignette = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    vignette_draw = ImageDraw.Draw(vignette)
    vignette_draw.rectangle((0, 0, width, height), fill=(10, 18, 13, 220))
    background.alpha_composite(vignette)
    return background


def render_hotspot_sheet(repo_root: Path, manifest: dict, audit_rows: list[dict], out_path: Path, scale: float) -> None:
    page_size = manifest["size"]
    scene_nodes = [node for node in manifest["sceneNodes"] if node.get("kind") == "sceneVisual"]
    filter_nodes = [node for node in manifest["sceneNodes"] if node.get("kind") == "filter" and node.get("buttonRect")]
    rows = [row for row in audit_rows if row["kind"] == "hotspot"]

    canvas = create_base_canvas(page_size, scale)
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()

    for node in scene_nodes:
        paste_asset(canvas, resolve_asset_path(repo_root, node["asset"]), node["rect"], scale)

    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)

    for row in rows:
        current_rect = row.get("currentRect")
        component_rect = row.get("componentRect")
        if component_rect:
            overlay_draw.rectangle(scaled_rect(component_rect, scale), outline=rgba("#ffd75f", 255), width=3)
        if current_rect:
            overlay_draw.rectangle(scaled_rect(current_rect, scale), outline=rgba("#b8ff5c", 255), width=2)
        if current_rect and component_rect:
            current_center = (
                int(round((current_rect["x"] + current_rect["w"] / 2) * scale)),
                int(round((current_rect["y"] + current_rect["h"] / 2) * scale)),
            )
            component_center = (
                int(round((component_rect["x"] + component_rect["w"] / 2) * scale)),
                int(round((component_rect["y"] + component_rect["h"] / 2) * scale)),
            )
            overlay_draw.line((current_center, component_center), fill=rgba("#ff6a5c", 210), width=2)

    canvas.alpha_composite(overlay)

    for node in filter_nodes:
        left, top, right, bottom = scaled_rect(node["buttonRect"], scale)
        draw.rounded_rectangle((left, top, right, bottom), radius=6, outline=rgba("#86a84c", 180), width=2)

    for row in rows:
        current_rect = row.get("currentRect") or row.get("componentRect")
        if not current_rect:
            continue
        label_x = int(round(current_rect["x"] * scale))
        label_y = max(4, int(round((current_rect["y"] - 14) * scale)))
        drift = row.get("boxVsComponent") or {}
        iou = row.get("boxVsComponentIou")
        label = f'{row["label"]}  Δ({drift.get("centerDx", 0)},{drift.get("centerDy", 0)}) IoU {iou}'
        draw_label(draw, label_x, label_y, label, font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)


def render_avatar_sheet(repo_root: Path, manifest: dict, audit_rows: list[dict], out_path: Path, scale: float) -> None:
    page_size = manifest["size"]
    scene_nodes = [node for node in manifest["sceneNodes"] if node.get("kind") == "sceneVisual"]
    rows = [row for row in audit_rows if row["kind"] == "avatar"]

    canvas = create_base_canvas(page_size, scale)
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()

    for node in scene_nodes:
        paste_asset(canvas, resolve_asset_path(repo_root, node["asset"]), node["rect"], scale)

    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)

    for row in rows:
        runtime_rect = row.get("runtimeRect") or row.get("currentRect")
        authored_rect = row.get("authoredRect")
        source_rect = row.get("sourceRect")
        asset_ref = row.get("assetUrl") or f'assets/map/avatars/{row.get("symbolName", "")}.png'
        asset_path = resolve_asset_path(repo_root, asset_ref)

        if runtime_rect:
            paste_asset(canvas, asset_path, runtime_rect, scale)
            overlay_draw.ellipse(scaled_rect(runtime_rect, scale), outline=rgba("#9dff73", 240), width=2)
        if authored_rect:
            overlay_draw.ellipse(scaled_rect(authored_rect, scale), outline=rgba("#ff6ef3", 210), width=2)
        if source_rect:
            overlay_draw.ellipse(scaled_rect(source_rect, scale), outline=rgba("#65d7ff", 210), width=1)
        if runtime_rect and authored_rect:
            runtime_center = (
                int(round((runtime_rect["x"] + runtime_rect["w"] / 2) * scale)),
                int(round((runtime_rect["y"] + runtime_rect["h"] / 2) * scale)),
            )
            authored_center = (
                int(round((authored_rect["x"] + authored_rect["w"] / 2) * scale)),
                int(round((authored_rect["y"] + authored_rect["h"] / 2) * scale)),
            )
            overlay_draw.line((runtime_center, authored_center), fill=rgba("#ff7e59", 190), width=1)

    canvas.alpha_composite(overlay)

    for row in rows:
        runtime_rect = row.get("runtimeRect") or row.get("currentRect")
        if not runtime_rect:
            continue
        authored_delta = row.get("authoredDelta") or {}
        label = f'{row["label"]}  authored Δ({authored_delta.get("dx", 0)},{authored_delta.get("dy", 0)})'
        draw_label(
            draw,
            int(round(runtime_rect["x"] * scale)),
            max(4, int(round((runtime_rect["y"] - 14) * scale))),
            label,
            font,
        )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)


def main() -> None:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    pages = args.pages or ["base", "faction", "defense", "school"]
    out_dir = repo_root / args.out_dir
    index: dict[str, dict] = {}

    for page_id in pages:
        manifest = load_json(["node", "tools/export-map-manifest.js", "--page", page_id], repo_root)
        audit = load_json(["node", "tools/audit-map-layout.js", "--page", page_id, "--json"], repo_root)
        index[page_id] = {"summary": audit["summary"]["byPage"].get(page_id, {})}

        if args.kind in ("all", "hotspot"):
            hotspot_out = out_dir / f"{page_id}-hotspot-audit.png"
            render_hotspot_sheet(repo_root, manifest, audit["rows"], hotspot_out, args.scale)
            index[page_id]["hotspotSheet"] = str(hotspot_out.relative_to(repo_root)).replace("\\", "/")

        if args.kind in ("all", "avatar"):
            avatar_out = out_dir / f"{page_id}-avatar-audit.png"
            render_avatar_sheet(repo_root, manifest, audit["rows"], avatar_out, args.scale)
            index[page_id]["avatarSheet"] = str(avatar_out.relative_to(repo_root)).replace("\\", "/")

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "audit-index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[map-audit-sheet] wrote sheets -> {out_dir}")


if __name__ == "__main__":
    main()
