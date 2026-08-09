#!/usr/bin/env python3
"""Direct regression checks for the v2 renderer's bounded image decoder."""

from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools" / "portrait-pilot" / "render-feature-fidelity-v2.py"


def load_module():
    spec = importlib.util.spec_from_file_location("render_feature_fidelity_v2", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("无法加载 render-feature-fidelity-v2.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeImage:
    def __init__(self, width: int, height: int):
        self.width = width
        self.height = height
        self.converted = False
        self.closed = False

    def __enter__(self):
        return self

    def __exit__(self, _kind, _value, _traceback):
        return False

    def convert(self, _mode: str):
        self.converted = True
        return self

    def close(self):
        self.closed = True


def main() -> None:
    module = load_module()
    manifest = {
        "featureContract": {
            "highResolutionRender": {"maximumSourceFrameDimension": 16_384}
        }
    }
    maximum_dimension, maximum_pixels = module.bounded_pixel_limit(manifest)
    assert maximum_dimension == 16_384
    assert maximum_pixels == 240_000_000

    oversized = FakeImage(15_500, 15_500)
    original_open = module.Image.open
    module.Image.open = lambda _path: oversized
    try:
        try:
            module.load_bounded_rgba(
                Path("synthetic.png"),
                "synthetic oversized frame",
                maximum_dimension,
                maximum_pixels,
            )
        except module.FidelityError:
            pass
        else:
            raise AssertionError("pixel-area overflow was not rejected")
        assert not oversized.converted, "oversized image must be rejected before decode/convert"
        assert oversized.closed, "oversized lazy image must be closed after header rejection"
    finally:
        module.Image.open = original_open

    exact_boundary = FakeImage(15_000, 16_000)
    module.Image.open = lambda _path: exact_boundary
    try:
        accepted = module.load_bounded_rgba(
            Path("synthetic-boundary.png"),
            "synthetic exact-boundary frame",
            maximum_dimension,
            maximum_pixels,
        )
        assert accepted is exact_boundary and exact_boundary.converted
    finally:
        module.Image.open = original_open

    over_dimension = FakeImage(16_385, 1)
    module.Image.open = lambda _path: over_dimension
    try:
        try:
            module.load_bounded_rgba(
                Path("synthetic-over-dimension.png"),
                "synthetic over-dimension frame",
                maximum_dimension,
                maximum_pixels,
            )
        except module.FidelityError:
            pass
        else:
            raise AssertionError("single-axis overflow was not rejected")
        assert not over_dimension.converted, "over-dimension image must be rejected before decode/convert"
    finally:
        module.Image.open = original_open

    # Simulate prepare_pilot.py's direct Image.open(...).convert(...) call. The
    # wrapper installed around core.render must reject before convert executes.
    core_oversized = FakeImage(15_500, 15_500)
    guarded_core_open = module.bounded_image_opener(
        lambda _path: core_oversized,
        maximum_dimension,
        maximum_pixels,
        "synthetic base renderer source",
    )
    try:
        guarded_core_open(Path("synthetic-core-source.png")).convert("RGBA")
    except module.FidelityError:
        pass
    else:
        raise AssertionError("base renderer source overflow was not rejected")
    assert not core_oversized.converted
    assert core_oversized.closed

    module.Image.open = lambda _path: (_ for _ in ()).throw(
        module.Image.DecompressionBombError("synthetic open-time bomb")
    )
    try:
        try:
            module.load_bounded_rgba(
                Path("synthetic-open-time-bomb.png"),
                "synthetic open-time bomb",
                maximum_dimension,
                maximum_pixels,
            )
        except module.FidelityError as error:
            assert "Pillow 有界解码门拒绝" in str(error)
        else:
            raise AssertionError("Pillow open-time decompression bomb was not normalized")
    finally:
        module.Image.open = original_open

    print({"status": "render_feature_fidelity_bounds_verified", "maximumPixels": maximum_pixels})


if __name__ == "__main__":
    main()
