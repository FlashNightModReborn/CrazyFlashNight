"""嵌套时间轴立绘变体：把标签藏在 DefineSprite 子时间轴里的源显式展开。

只处理两个已核对的源，其它 SWF 不猜：

- 室友：根时间轴 1 帧、无根标签；sprite 6 内 男@2 / 女@16。其帧脚本
  frame1/15/31 执行 ``gotoAndPlay(_root.性别)``，frame2 遇 ``_root.性别=="女"``
  跳「女」、frame16 遇 ``_root.性别=="男"`` 跳「男」——选择规则是**当前玩家
  性别**，生成 室友-男 / 室友-女 两个显式 manifest key，由 AS2 侧把源 key
  「室友」按性别转换后查询；不得反向猜异性。
- artist：根 1 帧、无根标签；sprite 7 内 普通/愤怒/微笑/大笑/严肃 @1..5。
  保留原 key「artist」，五标签就是五种 expression。

计划中的 ``frame`` 一律是 **sprite 内帧号**（sprite-local），不是根帧号；
渲染经 FFDec ``sprite:svg`` 导出（每 sprite 一次）+ ``dialogue_svg_fallback``
的 cairosvg 栅格化生成 PNG 中间帧。最终 WebP 编码与 manifest 入库由主烘焙器
``copy_asset`` 完成；key 选择策略（如 ``--keys``）也由主烘焙器裁决。
"""
from __future__ import annotations

from pathlib import Path
from typing import Any


# 每个源必须满足的整体结构：根帧数、无根标签、以及 sprites 映射精确等于
# {spriteId: {label: sprite 内帧号}}。任何一项不符即报错——变体契约不允许
# 源漂移后静默降级。
NESTED_VARIANT_SOURCES: dict[str, dict[str, Any]] = {
    "室友": {
        "spriteId": 6,
        "rootFrames": 1,
        "spriteLabels": {"男": 2, "女": 16},
        "selectionRule": "player-gender",
        "variants": [
            {"key": "室友-男", "expression": "普通", "label": "男", "frame": 2, "gender": "男"},
            {"key": "室友-女", "expression": "普通", "label": "女", "frame": 16, "gender": "女"},
        ],
    },
    "artist": {
        "spriteId": 7,
        "rootFrames": 1,
        "spriteLabels": {"普通": 1, "愤怒": 2, "微笑": 3, "大笑": 4, "严肃": 5},
        "selectionRule": "expression",
        "variants": [
            {"key": "artist", "expression": label, "label": label, "frame": frame}
            for label, frame in {"普通": 1, "愤怒": 2, "微笑": 3, "大笑": 4, "严肃": 5}.items()
        ],
    },
}


def plans_for(key: str, timelines: dict[str, Any]) -> list[dict[str, Any]]:
    """返回 key 的嵌套变体渲染计划；非变体源返回空表。

    ``timelines`` 取 ``bake-dialogue-portraits.swf_xml_timelines`` 的返回
    （{"root","sprites","rootFrames"}）。已知变体源必须满足整张结构表：
    根帧数、空根标签、唯一带标签 sprite 及其 标签→sprite 内帧号 精确匹配，
    任一不符抛 RuntimeError，绝不默认补帧。
    """
    key = str(key).strip()
    spec = NESTED_VARIANT_SOURCES.get(key)
    if spec is None:
        return []
    sprite_id = spec["spriteId"]
    expected = {str(sprite_id): dict(spec["spriteLabels"])}
    actual_sprites = {str(sid): dict(labels) for sid, labels in (timelines.get("sprites") or {}).items()}
    problems = []
    if timelines.get("rootFrames") != spec["rootFrames"]:
        problems.append(f"rootFrames={timelines.get('rootFrames')} != {spec['rootFrames']}")
    if timelines.get("root"):
        problems.append(f"unexpected root labels: {sorted(timelines['root'])}")
    if actual_sprites != expected:
        problems.append(f"sprite labels {actual_sprites} != {expected}")
    if problems:
        raise RuntimeError(f"Nested portrait variant source drift for {key}: " + "; ".join(problems))
    plans = []
    for variant in spec["variants"]:
        plan = {
            "key": variant["key"],
            "sourceKey": key,
            "expression": variant["expression"],
            "label": variant["label"],
            "spriteId": sprite_id,
            "frame": variant["frame"],  # sprite 内帧号，非根帧号
            "selection": {"rule": spec["selectionRule"]},
        }
        if spec["selectionRule"] == "player-gender":
            plan["selection"]["gender"] = variant["gender"]
        plans.append(plan)
    return plans


def variant_plans_for_swf(key: str, timelines: dict[str, Any]) -> dict[str, Any]:
    """同 plans_for，附带源级元数据，供 manifest/AS2 性别转换使用。"""
    key = str(key).strip()
    plans = plans_for(key, timelines)
    if not plans:
        return {"key": key, "plans": []}
    spec = NESTED_VARIANT_SOURCES[key]
    return {
        "key": key,
        "sourceSpriteId": spec["spriteId"],
        "selectionRule": spec["selectionRule"],
        "plans": plans,
    }


def render_variant_frames(
    ffdec: Path,
    project_root: Path,
    swf: Path,
    plans: list[dict[str, Any]],
    out_dir: Path,
    zoom: int,
    timeout_seconds: int,
) -> list[dict[str, Any]]:
    """按计划从同一 SWF 导 sprite:svg（每 sprite 一次）并栅格化为 PNG 中间帧。

    目录布局：``out_dir/svg/sprite_<id>/`` 给 FFDec 一次性导出（要求空目录，
    不删除已有内容），``out_dir/frames/sprite_<id>/<frame>.png`` 为产物。
    每条结果携带 key/expression/frame(sprite 内)/sourceSpriteId/png/renderer
    及栅格化尺寸证据；最终 WebP 编码与 manifest 归主烘焙器 copy_asset。
    """
    try:
        from dialogue_svg_fallback import recover_sprite_frames
    except ImportError:  # 允许被 importlib 按文件路径加载时仍能取到同目录实现
        import importlib.util

        spec = importlib.util.spec_from_file_location(
            "dialogue_svg_fallback", Path(__file__).resolve().parent / "dialogue_svg_fallback.py"
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        recover_sprite_frames = module.recover_sprite_frames

    ffdec = Path(ffdec)
    project_root = Path(project_root)
    swf = Path(swf)
    out_dir = Path(out_dir)
    if not isinstance(zoom, int) or not 1 <= zoom <= 8:
        raise ValueError(f"Variant raster zoom must be an int in [1,8]: {zoom!r}")
    by_sprite: dict[int, list[dict[str, Any]]] = {}
    for plan in plans:
        sprite_id = plan.get("spriteId")
        frame = plan.get("frame")
        if not isinstance(sprite_id, int) or not isinstance(frame, int) or frame < 1:
            raise ValueError(f"Invalid variant plan: {plan!r}")
        by_sprite.setdefault(sprite_id, []).append(plan)
    results: list[dict[str, Any]] = []
    for sprite_id in sorted(by_sprite):
        sprite_plans = by_sprite[sprite_id]
        frames = sorted({plan["frame"] for plan in sprite_plans})
        frames_dir = out_dir / "frames" / f"sprite_{sprite_id}"
        svg_dir = out_dir / "svg" / f"sprite_{sprite_id}"
        evidence = recover_sprite_frames(
            ffdec, project_root, swf, sprite_id, frames, frames_dir, svg_dir, zoom, timeout_seconds,
            minimum_visible_height=512 * zoom
        )
        for plan in sprite_plans:
            info = evidence[plan["frame"]]
            png_path = frames_dir / f"{plan['frame']}.png"
            if not png_path.is_file():
                raise RuntimeError(f"Variant raster missing: {png_path}")
            results.append(
                {
                    "key": plan["key"],
                    "sourceKey": plan["sourceKey"],
                    "expression": plan["expression"],
                    "frame": plan["frame"],
                    "sourceSpriteId": sprite_id,
                    "png": png_path.relative_to(out_dir).as_posix(),
                    "renderer": info["renderer"],
                    "width": info["width"],
                    "height": info["height"],
                    "zoom": info["zoom"],
                    "resolutionScale": info.get("resolutionScale", 1),
                    "minimumVisibleHeight": info["minimumVisibleHeight"],
                    "selection": plan["selection"],
                }
            )
    return results
