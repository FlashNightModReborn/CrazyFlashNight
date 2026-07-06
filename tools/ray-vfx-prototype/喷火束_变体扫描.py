"""
喷火束视觉原型 - 关键参数变体扫描

复用 喷火束_视觉原型.py 的 draw_frame()/build_video()，只覆盖顶层参数。
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location(
    "flame_proto_module",
    HERE / "喷火束_视觉原型.py",
)
proto = importlib.util.module_from_spec(spec)
sys.modules["flame_proto_module"] = proto
spec.loader.exec_module(proto)


BASELINE = {
    "GROW_SPEED": proto.GROW_SPEED,
    "RETRACT_SPEED": proto.RETRACT_SPEED,
    "OUTER_MAX_HALF_WIDTH": proto.OUTER_MAX_HALF_WIDTH,
    "BODY_MAX_HALF_WIDTH": proto.BODY_MAX_HALF_WIDTH,
    "WAVE_AMP": proto.WAVE_AMP,
    "OUTER_WAVE_AMP": proto.OUTER_WAVE_AMP,
    "EDGE_NOISE_AMP": proto.EDGE_NOISE_AMP,
    "POLY_STEPS": proto.POLY_STEPS,
    "TONGUE_STEPS": proto.TONGUE_STEPS,
    "TONGUE_LAYER_COUNT": proto.TONGUE_LAYER_COUNT,
    "EDGE_STREAK_COUNT": proto.EDGE_STREAK_COUNT,
    "DETAIL_ALPHA_SCALE": proto.DETAIL_ALPHA_SCALE,
    "HOT_TONGUE_MAX_HALF_WIDTH": proto.HOT_TONGUE_MAX_HALF_WIDTH,
    "EMBER_COUNT": proto.EMBER_COUNT,
}


VARIANTS = [
    {
        "name": "baseline",
    },
    {
        "name": "slow_growth",
        "GROW_SPEED": 70.0,
    },
    {
        "name": "hard_retract",
        "RETRACT_SPEED": 320.0,
    },
    {
        "name": "wide_cone",
        "OUTER_MAX_HALF_WIDTH": 60.0,
        "BODY_MAX_HALF_WIDTH": 42.0,
        "HOT_TONGUE_MAX_HALF_WIDTH": 22.0,
        "WAVE_AMP": 38.0,
        "OUTER_WAVE_AMP": 54.0,
    },
    {
        "name": "dense_layered",
        "POLY_STEPS": 34,
        "TONGUE_STEPS": 24,
        "TONGUE_LAYER_COUNT": 5,
        "EDGE_STREAK_COUNT": 11,
        "DETAIL_ALPHA_SCALE": 1.18,
        "EMBER_COUNT": 9,
    },
    {
        "name": "tight_torch",
        "OUTER_MAX_HALF_WIDTH": 34.0,
        "BODY_MAX_HALF_WIDTH": 24.0,
        "HOT_TONGUE_MAX_HALF_WIDTH": 13.0,
        "WAVE_AMP": 18.0,
        "OUTER_WAVE_AMP": 28.0,
        "POLY_STEPS": 18,
        "TONGUE_STEPS": 12,
        "EDGE_STREAK_COUNT": 5,
    },
    {
        "name": "violent_tail",
        "WAVE_AMP": 46.0,
        "OUTER_WAVE_AMP": 62.0,
        "EDGE_NOISE_AMP": 8.0,
        "EDGE_STREAK_COUNT": 10,
    },
    {
        "name": "performance_lod",
        "POLY_STEPS": 14,
        "TONGUE_STEPS": 8,
        "TONGUE_LAYER_COUNT": 2,
        "EDGE_STREAK_COUNT": 3,
        "DETAIL_ALPHA_SCALE": 0.82,
        "EMBER_COUNT": 3,
    },
]


def reset_baseline():
    for key, value in BASELINE.items():
        setattr(proto, key, value)


def apply_variant(variant):
    reset_baseline()
    for key, value in variant.items():
        if key == "name":
            continue
        setattr(proto, key, value)


if __name__ == "__main__":
    out_dir = HERE / "变体输出" / "喷火束"
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"输出目录: {out_dir}\n")

    for variant in VARIANTS:
        apply_variant(variant)
        out_path = out_dir / variant["name"]
        saved = proto.build_video(out_path)
        print(f"[ok] {variant['name']:16} -> {saved.name}")
        print(
            f"      grow={proto.GROW_SPEED}/f retract={proto.RETRACT_SPEED}/f "
            f"bodyW={proto.BODY_MAX_HALF_WIDTH} outerW={proto.OUTER_MAX_HALF_WIDTH} "
            f"wave={proto.WAVE_AMP}/{proto.OUTER_WAVE_AMP} "
            f"steps={proto.POLY_STEPS}/{proto.TONGUE_STEPS} "
            f"tongues={proto.TONGUE_LAYER_COUNT} streaks={proto.EDGE_STREAK_COUNT}\n"
        )
