#!/usr/bin/env python
from __future__ import annotations

import importlib.util
import sys
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


if __name__ == "__main__":
    main()
