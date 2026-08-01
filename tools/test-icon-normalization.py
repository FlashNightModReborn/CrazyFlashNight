#!/usr/bin/env python
from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

from PIL import Image


def load_bake_module():
    module_path = Path(__file__).resolve().with_name("bake-icons-offline.py")
    spec = importlib.util.spec_from_file_location("bake_icons_offline", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load bake-icons-offline.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def alpha_bbox(image: Image.Image):
    return image.convert("RGBA").getchannel("A").getbbox()


def bbox_size(bbox):
    if bbox is None:
        return 0, 0
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def make_large_ffdec_canvas() -> Image.Image:
    image = Image.new("RGBA", (1016, 615), (0, 0, 0, 0))
    icon = Image.new("RGBA", (240, 240), (255, 255, 255, 255))
    image.alpha_composite(icon, (381, 249))
    return image


def main() -> None:
    bake = load_bake_module()
    bake.ICON_SIZE = 128

    large_canvas = make_large_ffdec_canvas()

    normalized = bake.normalize_icon_image(large_canvas)
    bbox = alpha_bbox(normalized)
    width, height = bbox_size(bbox)
    assert normalized.size == (128, 128)
    assert width == 128 and height == 128, (bbox, width, height)

    # Full bakes may use the first f1 icon as a profile. That profile is only a
    # sizing hint; it must not crop a symbol whose FFDec canvas is much larger.
    profiled = bake.normalize_icon_image(large_canvas, (247, 250))
    profiled_bbox = alpha_bbox(profiled)
    profiled_width, profiled_height = bbox_size(profiled_bbox)
    assert profiled_bbox is not None
    assert profiled_bbox[0] > 0 and profiled_bbox[1] > 0, profiled_bbox
    assert profiled_bbox[2] < 128 and profiled_bbox[3] < 128, profiled_bbox
    assert profiled_width >= 120 and profiled_height >= 120, (profiled_bbox, profiled_width, profiled_height)

    preserved = bake.normalize_icon_image(large_canvas, (1016, 615), preserve_canvas=True)
    preserved_bbox = alpha_bbox(preserved)
    preserved_width, preserved_height = bbox_size(preserved_bbox)
    assert preserved_width < 40 and preserved_height < 60, preserved_bbox

    transparent = bake.normalize_icon_image(Image.new("RGBA", (100, 100), (0, 0, 0, 0)))
    assert transparent.size == (128, 128)
    assert alpha_bbox(transparent) is None

    # Layout protection may auto-refresh only across a trusted, identical render recipe
    # when both the source artifact and exact normalized pixels changed. Timestamps are
    # audit metadata, never the authority by themselves.
    previous = {
        "schema": bake.STATIC_BAKE_PROVENANCE_SCHEMA,
        "mode": "ffdec-static-f1",
        "sourceSwf": "flashswf/arts/things.swf",
        "linkageId": "图标-测试",
        "characterId": 42,
        "sourceArtifactSha256": "source-old",
        "sourceArtifactMtimeNs": 100,
        "renderRecipeSha256": "recipe-a",
        "renderRgbaSha256": "render-old",
    }
    current = dict(previous)
    current.update({
        "sourceArtifactSha256": "source-new",
        "sourceArtifactMtimeNs": 200,
        "renderRgbaSha256": "render-new",
    })
    allowed, reason = bake.source_aware_layout_refresh_decision(previous, current, "render-old")
    assert allowed and reason == "source_and_render_changed"

    recipe_changed = dict(current, renderRecipeSha256="recipe-b")
    assert bake.source_aware_layout_refresh_decision(previous, recipe_changed, "render-old") == (
        False, "render_recipe_changed"
    )
    assert bake.source_aware_layout_refresh_decision(previous, current, "manual-output") == (
        False, "output_drifted_from_provenance"
    )
    source_unchanged = dict(current, sourceArtifactSha256="source-old")
    assert bake.source_aware_layout_refresh_decision(previous, source_unchanged, "render-old") == (
        False, "source_artifact_unchanged"
    )
    assert bake.source_aware_layout_refresh_decision(None, current, "render-old") == (
        False, "provenance_missing"
    )

    transparent_rgb_a = Image.new("RGBA", (1, 1), (255, 80, 20, 0))
    transparent_rgb_b = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    assert bake.rgba_render_digest(transparent_rgb_a) == bake.rgba_render_digest(transparent_rgb_b)
    transparent_rgb_a.putpixel((0, 0), (255, 80, 20, 1))
    assert bake.rgba_render_digest(transparent_rgb_a) != bake.rgba_render_digest(transparent_rgb_b)

    # A normal bake may ignore a tiny pixel delta to preserve established layout,
    # but an explicit/source-authorized refresh must write it exactly so the result
    # can become a trustworthy provenance root.
    with tempfile.TemporaryDirectory() as temp_dir:
        output_dir = Path(temp_dir)
        filename = "micro.webp"
        existing = Image.new("RGBA", (128, 128), (20, 30, 40, 255))
        candidate = existing.copy()
        candidate.putpixel((64, 64), (21, 30, 40, 255))
        bake.save_static_icon(existing, output_dir / filename)

        action, stats = bake.write_icon_if_needed(
            output_dir,
            filename,
            candidate,
            dry_run=False,
            protect_existing_layout=True,
        )
        assert action == "unchanged" and stats.micro
        assert bake.decoded_icon_digest(output_dir / filename) == bake.rgba_render_digest(existing)

        action, stats = bake.write_icon_if_needed(
            output_dir,
            filename,
            candidate,
            dry_run=False,
            protect_existing_layout=False,
        )
        assert action == "updated" and stats.micro
        assert bake.decoded_icon_digest(output_dir / filename) == bake.rgba_render_digest(candidate)


if __name__ == "__main__":
    main()
