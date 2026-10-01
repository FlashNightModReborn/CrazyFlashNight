#!/usr/bin/env python3
"""嵌套时间轴立绘的计划与 SVG 装配测试：不调用 FFDec，不触碰生产资产。

timelines 结构即 bake-dialogue-portraits.swf_xml_timelines 的返回：
{"root": {标签: 根帧}, "sprites": {spriteId: {标签: sprite 内帧}}, "rootFrames": int}。
基准值来自 2026-09-13 实导核对：室友 sprite6 男@2/女@16、根1帧无标签；
artist sprite7 普通/愤怒/微笑/大笑/严肃 @1..5、根1帧无标签。
"""
from __future__ import annotations

import importlib.util
import json
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops
from dialogue_svg_fallback import rasterize_svg


ROOT = Path(__file__).resolve().parent.parent
VARIANTS_PATH = ROOT / "tools" / "dialogue_portrait_variants.py"

ROOMMATE_TIMELINES = {"root": {}, "sprites": {"6": {"男": 2, "女": 16}}, "rootFrames": 1}
ARTIST_TIMELINES = {
    "root": {},
    "sprites": {"7": {"普通": 1, "愤怒": 2, "微笑": 3, "大笑": 4, "严肃": 5}},
    "rootFrames": 1,
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_variants() -> Any:
    spec = importlib.util.spec_from_file_location("cf7_dialogue_portrait_variants", VARIANTS_PATH)
    require(spec is not None and spec.loader is not None, "cannot load portrait variants module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_drift(variants: Any, key: str, timelines: dict[str, Any]) -> None:
    try:
        variants.plans_for(key, timelines)
    except RuntimeError as error:
        require(key in str(error), f"drift error must name the source key: {error}")
    else:
        raise AssertionError(f"{key}: malformed timelines must fail closed")


def exercise_stage_expression(variants: Any) -> None:
    # 同名 shape0/gradient0 分别被衣服和脸使用；导入表情不能改衣服或其它头部件。
    stage = '''<svg xmlns="http://www.w3.org/2000/svg"
      xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:j="https://www.free-decompiler.com/flash"
      width="100px" height="100px">
      <g><use j:characterId="30" xlink:href="#shape0"/>
        <use j:characterId="40" xlink:href="#head" transform="translate(10,10)"/></g>
      <defs>
        <linearGradient id="gradient0"><stop stop-color="#336699"/></linearGradient>
        <g id="shape0"><rect x="0" y="50" width="100" height="50" fill="url(#gradient0)"/></g>
        <g id="head" transform="translate(5,5)">
          <use j:characterId="7" width="10" height="10" xlink:href="#face"
            transform="translate(15,5)"/>
          <rect width="50" height="7" fill="#222222"/>
        </g>
        <g id="face" transform="matrix(1,0,0,1,0,0)">
          <rect width="10" height="10" fill="#884400"/>
        </g>
      </defs></svg>'''
    expression = '''<svg xmlns="http://www.w3.org/2000/svg"
      xmlns:xlink="http://www.w3.org/1999/xlink" width="10px" height="10px">
      <g transform="matrix(1,0,0,1,0,0)"><use xlink:href="#shape0"/></g>
      <defs>
        <linearGradient id="gradient0"><stop stop-color="#ddccaa"/></linearGradient>
        <g id="shape0"><rect width="10" height="10" fill="url(#gradient0)"/></g>
      </defs></svg>'''
    with tempfile.TemporaryDirectory(prefix="cf7-dialogue-stage-") as directory:
        root = Path(directory)
        stage_path, expression_path, output = root / "stage.svg", root / "expression.svg", root / "output.svg"
        stage_path.write_text(stage, encoding="utf-8")
        expression_path.write_text(expression, encoding="utf-8")
        variants.compose_stage_expression_svg(stage_path, expression_path, 7, output)
        rasterize_svg(stage_path, root / "before.png", 1)
        rasterize_svg(output, root / "after.png", 1)
        with Image.open(root / "before.png") as before, Image.open(root / "after.png") as after:
            rgba = after.convert("RGBA")
            require(after.size == (100, 100), "stage canvas changed")
            require(rgba.getpixel((35, 25)) == (221, 204, 170, 255), "expression is not placed at its original registration")
            require(rgba.getpixel((50, 70)) == (51, 102, 153, 255), "expression ids overwrote the clothing")
            require(rgba.getpixel((20, 17)) == (34, 34, 34, 255), "head accessories disappeared")
            require(rgba.getpixel((0, 0))[3] == 0, "transparent stage became opaque")
            changed_bounds = ImageChops.difference(before.convert("RGB"), after.convert("RGB")).getbbox()
            # 原头部件在脸前方，继续遮住脸的前两行。
            require(changed_bounds == (30, 22, 40, 30),
                    f"expression changed pixels outside the visible face: {changed_bounds}")

        svg = "{http://www.w3.org/2000/svg}"
        character_id = "{https://www.free-decompiler.com/flash}characterId"
        for count in (0, 2):
            altered = ET.fromstring(stage)
            head = next(node for node in altered.iter() if node.get("id") == "head")
            face = next(node for node in head if node.get(character_id) == "7")
            if count == 0:
                head.remove(face)
            else:
                head.append(ET.fromstring(ET.tostring(face)))
            ET.ElementTree(altered).write(stage_path, encoding="utf-8")
            try:
                variants.compose_stage_expression_svg(stage_path, expression_path, 7, output)
            except RuntimeError:
                pass
            else:
                raise AssertionError(f"accepted {count} face placements in the stage")
        stage_path.write_text(stage, encoding="utf-8")
        altered = ET.fromstring(expression)
        altered.find(svg + "g").set("transform", "translate(1,0)")
        ET.ElementTree(altered).write(expression_path, encoding="utf-8")
        try:
            variants.compose_stage_expression_svg(stage_path, expression_path, 7, output)
        except RuntimeError:
            pass
        else:
            raise AssertionError("accepted a changed expression registration")


def main() -> None:
    variants = load_variants()

    plans = variants.plans_for("室友", ROOMMATE_TIMELINES)
    by_key = {plan["key"]: plan for plan in plans}
    require(set(by_key) == {"室友-男", "室友-女"}, f"roommate must yield exactly two explicit keys: {by_key}")
    male, female = by_key["室友-男"], by_key["室友-女"]
    for plan in (male, female):
        require(plan["sourceKey"] == "室友", "variant must keep the source key for AS2 translation")
        require(plan["spriteId"] == 6 and plan["expression"] == "普通", "roommate plan fields mismatch")
        require(plan["selection"] == {"rule": "player-gender", "gender": plan["key"].rsplit("-", 1)[1]},
                "roommate selection must bind the same gender as the key suffix")
    # 两性独立且不得反接：男取 男@2，女取 女@16。
    require(
        male["label"] == "男" and male["frame"] == 2 and male["selection"]["gender"] == "男",
        f"male variant must come from label 男@2: {male}",
    )
    require(
        female["label"] == "女" and female["frame"] == 16 and female["selection"]["gender"] == "女",
        f"female variant must come from label 女@16: {female}",
    )
    require(male["frame"] != female["frame"], "gender variants must stay distinct frames")
    require(all("renderScope" not in plan for plan in (male, female)), "roommate rendering scope changed")

    plans = variants.plans_for("artist", ARTIST_TIMELINES)
    require(len(plans) == 5 and {p["key"] for p in plans} == {"artist"}, "artist keeps its original key")
    require(
        {p["expression"]: p["frame"] for p in plans}
        == {"普通": 1, "愤怒": 2, "微笑": 3, "大笑": 4, "严肃": 5},
        "artist expression→frame mapping mismatch",
    )
    require(
        all(p["spriteId"] == 7 and p["selection"] == {"rule": "expression"} for p in plans),
        "artist plans must bind sprite 7 with plain expression selection",
    )
    require(all(p.get("renderScope") == "stage" for p in plans),
            "artist must retain its root stage instead of rendering a naked face sprite")
    exercise_stage_expression(variants)

    # 非变体源返回空表，不猜其它 SWF。
    require(variants.plans_for("Andy Law", {"root": {"普通": 1}, "sprites": {}, "rootFrames": 73}) == [],
            "unknown keys must produce no plans")

    # 缺标签/结构漂移一律拒绝，不默认补帧。
    expect_drift(variants, "室友", {"root": {}, "sprites": {}, "rootFrames": 1})
    expect_drift(variants, "室友", {"root": {}, "sprites": {"6": {"男": 2}}, "rootFrames": 1})
    expect_drift(variants, "室友", {"root": {}, "sprites": {"6": {"男": 3, "女": 16}}, "rootFrames": 1})
    expect_drift(variants, "室友", {"root": {}, "sprites": {"6": {"男": 2, "女": 16}, "9": {"x": 1}}, "rootFrames": 1})
    expect_drift(variants, "室友", {"root": {"普通": 1}, "sprites": {"6": {"男": 2, "女": 16}}, "rootFrames": 1})
    expect_drift(variants, "室友", {"root": {}, "sprites": {"6": {"男": 2, "女": 16}}, "rootFrames": 2})
    expect_drift(variants, "artist", {"root": {}, "sprites": {"7": {"普通": 1, "愤怒": 2, "微笑": 3, "大笑": 4}}, "rootFrames": 1})

    meta = variants.variant_plans_for_swf("室友", ROOMMATE_TIMELINES)
    require(
        meta["sourceSpriteId"] == 6 and meta["selectionRule"] == "player-gender" and len(meta["plans"]) == 2,
        "roommate source metadata mismatch",
    )

    print(json.dumps({
        "status": "dialogue_portrait_variants_verified",
        "roommateKeys": sorted(by_key),
        "roommateFrames": {"室友-男": 2, "室友-女": 16},
        "artistExpressions": 5,
        "artistRootStagePreserved": True,
        "onlyExpressionPixelsChanged": True,
        "expressionIdCollisionsIsolated": True,
        "stageRegistrationDriftFailsClosed": True,
        "unknownKeyNoPlans": True,
        "driftFailsClosed": True,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
