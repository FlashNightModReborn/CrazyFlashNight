"""FFDec Java2D 曲线裁剪失败时，从同一 SWF/Sprite 的 SVG 帧恢复像素。

只供离线烘焙调用。CairoSVG 不参与游戏运行；源文件、帧号与倍率仍由主烘焙器裁决。
"""
from __future__ import annotations

import re
import math
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path


def svg_dimensions(svg_path: Path) -> tuple[float, float]:
    root = ET.parse(svg_path).getroot()
    values = []
    for name in ("width", "height"):
        value = root.get(name, "")
        if not re.fullmatch(r"\d+(?:\.\d+)?(?:px)?", value):
            raise ValueError(f"Unexpected SVG {name}: {value!r}")
        values.append(float(value.removesuffix("px")))
    if not all(0 < value <= 8192 for value in values):
        raise ValueError("SVG dimensions outside portrait budget")
    return values[0], values[1]


def rasterize_svg(svg_path: Path, png_path: Path, zoom: int, resolution_scale: int = 1) -> dict:
    import cairosvg
    import cairocffi

    if not isinstance(zoom, int) or not 1 <= zoom <= 8:
        raise ValueError("Portrait zoom must be an integer from 1 to 8")
    if not isinstance(resolution_scale, int) or not 1 <= resolution_scale <= 32:
        raise ValueError("Portrait resolution scale must be an integer from 1 to 32")
    width, height = svg_dimensions(svg_path)
    output_width, output_height = round(width * zoom * resolution_scale), round(height * zoom * resolution_scale)
    if output_width * output_height > 64 * 1024 * 1024:
        raise ValueError("Portrait raster exceeds 64M pixels")
    png_path.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(url=str(svg_path), write_to=str(png_path),
                    output_width=output_width, output_height=output_height)
    return {"renderer": "ffdec-svg-cairosvg", "cairoSvgVersion": cairosvg.__version__,
            "cairoVersion": cairocffi.cairo_version_string(),
            "width": output_width, "height": output_height, "zoom": zoom,
            "resolutionScale": resolution_scale}


def recover_sprite_frames(ffdec: Path, project_root: Path, swf: Path, sprite_id: int,
                          frames: list[int], output_dir: Path, svg_dir: Path,
                          zoom: int, timeout_seconds: int = 180,
                          minimum_visible_height: int = 0) -> dict[int, dict]:
    """导出一次 SVG，仅栅格化调用方缺失的帧；不删除目录、不接受其它 SWF 的缓存。"""
    if not frames or any(not isinstance(frame, int) or frame < 1 for frame in frames):
        raise ValueError("Positive explicit frame numbers required")
    if not isinstance(sprite_id, int) or sprite_id < 1:
        raise ValueError("Positive sprite id required")
    if not isinstance(minimum_visible_height, int) or not 0 <= minimum_visible_height <= 8192:
        raise ValueError("Minimum visible height outside portrait budget")
    if svg_dir.exists() and any(svg_dir.iterdir()):
        raise ValueError("SVG candidate directory must be empty")
    svg_dir.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([str(ffdec), "-ignorebackground", "-format", "sprite:svg",
                             "-selectid", str(sprite_id), "-export", "sprite",
                             str(svg_dir), str(swf)], cwd=project_root,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=timeout_seconds, check=False)
    (svg_dir / "export.log").write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError(f"FFDec SVG export failed ({result.returncode}); see {svg_dir / 'export.log'}")
    matches = [path for path in svg_dir.iterdir() if path.is_dir()
               and (f"_{sprite_id}_" in path.name or path.name.endswith(f"_{sprite_id}"))]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one exported sprite {sprite_id}, got {len(matches)}")
    evidence = {}
    for frame in sorted(set(frames)):
        svg = matches[0] / f"{frame}.svg"
        if not svg.is_file():
            raise RuntimeError(f"Missing same-source SVG frame: {frame}")
        evidence[frame] = rasterize_svg(svg, output_dir / f"{frame}.png", zoom)
    if minimum_visible_height:
        # 同 sprite 的所有目标帧使用同一倍率，保留表情与男女变体的源坐标关系。
        # 从 alpha 区域计量，透明大画布不能冒充人物分辨率；重新从矢量出图。
        from PIL import Image
        scale = 1
        for frame in evidence:
            with Image.open(output_dir / f"{frame}.png") as image:
                bounds = image.convert("RGBA").getchannel("A").getbbox()
                if bounds is None:
                    raise ValueError(f"Empty nested portrait frame: {frame}")
                scale = max(scale, math.ceil(minimum_visible_height / (bounds[3] - bounds[1])))
        if scale > 1:
            for frame in evidence:
                evidence[frame] = rasterize_svg(matches[0] / f"{frame}.svg", output_dir / f"{frame}.png", zoom, scale)
        for value in evidence.values():
            value["minimumVisibleHeight"] = minimum_visible_height
    return evidence
