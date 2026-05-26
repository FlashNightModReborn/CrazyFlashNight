"""
八门金锁视觉原型 - 关键设计选择的 A/B/C/D 变体扫描

生成 4 个 mp4 让设计师对比, 每个改一个关键变量:
  baseline       — 30°/帧 + 反向旋转 + 旋进分界 (推荐起点)
  fast-rot       — 改 45°/帧 (验证"是否过快")
  same-direction — 改同向旋转 (验证"反向是否必要")
  static-split   — 黑白分界固定不旋 (验证"旋进分界是否值得")

复用 八门金锁_视觉原型.py 的绘制函数, 仅覆盖参数.
"""

import importlib.util
import sys
from pathlib import Path

# 动态导入 sibling 脚本 (文件名含中文, 不能用普通 import)
HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location(
    "proto_module", HERE / "八门金锁_视觉原型.py"
)
proto = importlib.util.module_from_spec(spec)
sys.modules["proto_module"] = proto
spec.loader.exec_module(proto)


VARIANTS = [
    # v4 基线 (锁定参数): 15 帧爆发, 宽脉冲 (amp=0.55 w=2.5), slow_rot 15°/帧, α 律动开
    {
        "name": "v4_baseline_locked",
        "BURST_FRAMES": 15,
        "PULSE_PROPAGATE": True,
        "PULSE_AMP": 0.55,
        "PULSE_WIDTH": 2.5,
        "ANG_VEL_DEG": 15.0,
        "PULSE_ALPHA_MODULATE": True,
    },
    # 验证 α 律动价值: 同 v4 但关闭 α 律动 (仅尺寸脉冲)
    {
        "name": "v4_no_alpha_pulse",
        "BURST_FRAMES": 15,
        "PULSE_PROPAGATE": True,
        "PULSE_AMP": 0.55,
        "PULSE_WIDTH": 2.5,
        "ANG_VEL_DEG": 15.0,
        "PULSE_ALPHA_MODULATE": False,
    },
    # sanity check: 完全无律动 (尺寸/α 都不变)
    {
        "name": "v4_no_pulse",
        "BURST_FRAMES": 15,
        "PULSE_PROPAGATE": False,
        "ANG_VEL_DEG": 15.0,
        "PULSE_ALPHA_MODULATE": True,  # 关闭 PULSE_PROPAGATE 后 α 律动自动失效
    },
    # 更宽脉冲探索: w=3.5 (波包跨越 7 切片, 几乎全段同时激活)
    {
        "name": "v4_xwide_pulse",
        "BURST_FRAMES": 15,
        "PULSE_PROPAGATE": True,
        "PULSE_AMP": 0.55,
        "PULSE_WIDTH": 3.5,
        "ANG_VEL_DEG": 15.0,
        "PULSE_ALPHA_MODULATE": True,
    },
    # 待机 α 探索: BASE_PULSE_ALPHA 拉低到 0.15 (脉冲外更暗, 对比度更强)
    {
        "name": "v4_dim_idle",
        "BURST_FRAMES": 15,
        "PULSE_PROPAGATE": True,
        "PULSE_AMP": 0.55,
        "PULSE_WIDTH": 2.5,
        "ANG_VEL_DEG": 15.0,
        "PULSE_ALPHA_MODULATE": True,
        "BASE_PULSE_ALPHA": 0.15,
    },
]


def apply_variant(variant_params):
    for key, value in variant_params.items():
        if key == "name":
            continue
        setattr(proto, key, value)


if __name__ == "__main__":
    out_dir = HERE / "变体输出"
    out_dir.mkdir(exist_ok=True)
    print(f"输出目录: {out_dir}\n")

    for v in VARIANTS:
        apply_variant(v)
        out_path = out_dir / v["name"]
        saved = proto.build_video(out_path)
        print(f"[ok] {v['name']:42} -> {saved.name}")
        print(f"      ω={proto.ANG_VEL_DEG}°/帧  反旋={proto.COUNTER_ROTATE}  "
              f"分界旋进={proto.COLOR_SPLIT_ROTATES}\n")
