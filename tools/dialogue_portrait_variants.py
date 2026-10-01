"""嵌套时间轴立绘变体：把标签藏在 DefineSprite 子时间轴里的源显式展开。

只处理两个已核对的源，其它 SWF 不猜：

- 室友：根时间轴 1 帧、无根标签；sprite 6 内 男@2 / 女@16。其帧脚本
  frame1/15/31 执行 ``gotoAndPlay(_root.性别)``，frame2 遇 ``_root.性别=="女"``
  跳「女」、frame16 遇 ``_root.性别=="男"`` 跳「男」——选择规则是**当前玩家
  性别**，生成 室友-男 / 室友-女 两个显式 manifest key，由 AS2 侧把源 key
  「室友」按性别转换后查询；不得反向猜异性。
- artist：根 1 帧、无根标签；sprite 7 是「男变装-基本脸型」，五种表情
  在其 1..5 帧。必须保留根舞台的身体与 sprite 40 的发型/面罩/眼镜，
  只替换 sprite 7 的 SVG 定义；不能把脸部件单独放大为整个角色。

计划中的 ``frame`` 一律是 **sprite 内帧号**（sprite-local），不是根帧号；
室友直接渲染 sprite；artist 在原根舞台内替换表情，并保留舞台坐标与作者取景。
渲染经同一 SWF 的 FFDec SVG 导出 + ``dialogue_svg_fallback`` 的 CairoSVG
栅格化生成 PNG 中间帧。最终 WebP 编码与 manifest 入库由主烘焙器
``copy_asset`` 完成；key 选择策略（如 ``--keys``）也由主烘焙器裁决。
"""
from __future__ import annotations

import copy
import re
import subprocess
import xml.etree.ElementTree as ET
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
        "renderScope": "stage",
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
        if spec.get("renderScope") == "stage":
            plan["renderScope"] = "stage"
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


def compose_stage_expression_svg(stage_svg: Path, expression_svg: Path,
                                 sprite_id: int, output_svg: Path) -> None:
    """在作者根舞台中替换唯一脸部定义，保留所有放置矩阵和其它部件。

    FFDec 给 use 写入真实 characterId；SVG 的 sprite13 等 id 只是导出时的编号，
    不得将它们当作 SWF characterId。两份 SVG 的局部 id 会重名，导入表情定义
    时必须同时重写 href 与 url(#...)，不能覆盖身体或衣服使用的原定义。
    """
    svg = "{http://www.w3.org/2000/svg}"
    href = "{http://www.w3.org/1999/xlink}href"
    character_id = "{https://www.free-decompiler.com/flash}characterId"
    stage = ET.parse(stage_svg).getroot()
    expression = ET.parse(expression_svg).getroot()
    stage_defs = stage.find(svg + "defs")
    expression_defs = expression.find(svg + "defs")
    groups = expression.findall(svg + "g")
    uses = [node for node in stage.iter(svg + "use")
            if node.get(character_id) == str(sprite_id)]
    if stage_defs is None or expression_defs is None or len(groups) != 1 or len(uses) != 1:
        raise RuntimeError(f"Stage portrait requires one expression sprite {sprite_id} and SVG definitions")
    reference = uses[0].get(href, "")
    targets = [node for node in stage_defs if reference == "#" + node.get("id", "")]
    if len(targets) != 1 or not reference.startswith("#"):
        raise RuntimeError(f"Stage portrait expression definition missing: {reference}")
    if sum(node.get(href) == reference for node in stage.iter(svg + "use")) != 1:
        raise RuntimeError("Stage portrait expression definition is shared by another placement")
    target = targets[0]
    group = copy.deepcopy(groups[0])
    # 同一次 sprite 导出的各表情共用画布和注册点；漂移时拒绝，不猜新的平移。
    if group.get("transform") != target.get("transform"):
        raise RuntimeError("Stage portrait expression registration changed")
    for dimension in ("width", "height"):
        if float(expression.get(dimension, "").removesuffix("px")) != float(uses[0].get(dimension, "0")):
            raise RuntimeError(f"Stage portrait expression {dimension} changed")
    definitions = [copy.deepcopy(node) for node in expression_defs]
    imported = [group, *definitions]
    ids = [node.get("id") for subtree in imported for node in subtree.iter() if node.get("id")]
    if len(set(ids)) != len(ids):
        raise RuntimeError("Duplicate expression SVG identifiers")
    renamed = {name: f"expression_{sprite_id}_{name}" for name in ids}
    stage_ids = {node.get("id") for node in stage.iter() if node.get("id")}
    if stage_ids.intersection(renamed.values()):
        raise RuntimeError("Expression SVG identifiers collide with the stage")
    for subtree in imported:
        for node in subtree.iter():
            if node.get("id") in renamed:
                node.set("id", renamed[node.get("id")])
            for attribute, value in list(node.attrib.items()):
                if attribute == href and value.startswith("#"):
                    value = "#" + renamed.get(value[1:], value[1:])
                value = re.sub(r"url\(#([^)]*)\)",
                               lambda match: "url(#" + renamed.get(match[1], match[1]) + ")", value)
                node.set(attribute, value)
    group.set("id", target.get("id"))
    position = list(stage_defs).index(target)
    stage_defs.remove(target)
    stage_defs.insert(position, group)
    stage_defs.extend(definitions)
    output_svg.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(stage).write(output_svg, encoding="utf-8", xml_declaration=True)


def render_variant_frames(
    ffdec: Path,
    project_root: Path,
    swf: Path,
    plans: list[dict[str, Any]],
    out_dir: Path,
    zoom: int,
    timeout_seconds: int,
) -> list[dict[str, Any]]:
    """按计划从同一 SWF 导 SVG；stage 范围只替换脸部，其余直接渲染 sprite。

    目录布局：``out_dir/svg/sprite_<id>/`` 给 FFDec 一次性导出（要求空目录，
    不删除已有内容），``out_dir/frames/sprite_<id>/<frame>.png`` 为产物。
    每条结果携带 key/expression/frame(sprite 内)/sourceSpriteId/png/renderer
    及栅格化尺寸证据；最终 WebP 编码与 manifest 归主烘焙器 copy_asset。
    """
    try:
        from dialogue_svg_fallback import recover_sprite_frames, rasterize_svg, svg_dimensions
    except ImportError:  # 允许被 importlib 按文件路径加载时仍能取到同目录实现
        import importlib.util

        spec = importlib.util.spec_from_file_location(
            "dialogue_svg_fallback", Path(__file__).resolve().parent / "dialogue_svg_fallback.py"
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        recover_sprite_frames = module.recover_sprite_frames
        rasterize_svg = module.rasterize_svg
        svg_dimensions = module.svg_dimensions

    ffdec = Path(ffdec)
    project_root = Path(project_root)
    swf = Path(swf)
    out_dir = Path(out_dir)
    if not isinstance(zoom, int) or not 1 <= zoom <= 8:
        raise ValueError(f"Variant raster zoom must be an int in [1,8]: {zoom!r}")
    if not plans:
        return []
    scopes = {plan.get("renderScope", "sprite") for plan in plans}
    if len(scopes) != 1 or not scopes.issubset({"sprite", "stage"}):
        raise ValueError("Variant render scopes must be uniform and explicit")
    stage_scope = scopes == {"stage"}
    stage_svg = out_dir / "svg" / "stage" / "1.svg"
    if stage_scope:
        if stage_svg.parent.exists() and any(stage_svg.parent.iterdir()):
            raise ValueError("Stage SVG candidate directory must be empty")
        stage_svg.parent.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(ffdec), "-ignorebackground", "-format", "frame:svg",
                                 "-select", "1", "-export", "frame", str(stage_svg.parent), str(swf)],
                                cwd=project_root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=timeout_seconds, check=False)
        (stage_svg.parent / "export.log").write_bytes(result.stdout)
        if result.returncode or not stage_svg.is_file():
            raise RuntimeError("Stage portrait SVG export failed; see stage/export.log")
        if svg_dimensions(stage_svg) != (1024, 576):
            raise RuntimeError("Stage portrait must retain the 1024x576 author canvas")
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
            ffdec, project_root, swf, sprite_id, frames,
            out_dir / "component-frames" / f"sprite_{sprite_id}" if stage_scope else frames_dir,
            svg_dir, 1 if stage_scope else zoom, timeout_seconds,
            minimum_visible_height=0 if stage_scope else 512 * zoom
        )
        if stage_scope:
            source_dirs = [path for path in svg_dir.iterdir() if path.is_dir()
                           and (f"_{sprite_id}_" in path.name or path.name.endswith(f"_{sprite_id}"))]
            if len(source_dirs) != 1:
                raise RuntimeError(f"Expected one expression SVG source for sprite {sprite_id}")
            for frame in frames:
                composed = out_dir / "svg" / f"composed_{sprite_id}" / f"{frame}.svg"
                compose_stage_expression_svg(stage_svg, source_dirs[0] / f"{frame}.svg", sprite_id, composed)
                evidence[frame] = rasterize_svg(composed, frames_dir / f"{frame}.png", zoom)
                evidence[frame]["renderer"] = "ffdec-svg-cairosvg-root-stage"
                evidence[frame]["minimumVisibleHeight"] = 0
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
                    **({"coordinateSpace": "stage", "sourceRootFrame": 1} if stage_scope else {}),
                }
            )
    return results
