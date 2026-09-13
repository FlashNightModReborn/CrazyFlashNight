#!/usr/bin/env python3
"""嵌套时间轴立绘变体的纯计划测试：不调用 FFDec，不触碰生产烘焙。

timelines 结构即 bake-dialogue-portraits.swf_xml_timelines 的返回：
{"root": {标签: 根帧}, "sprites": {spriteId: {标签: sprite 内帧}}, "rootFrames": int}。
基准值来自 2026-09-13 实导核对：室友 sprite6 男@2/女@16、根1帧无标签；
artist sprite7 普通/愤怒/微笑/大笑/严肃 @1..5、根1帧无标签。
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any


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
        "unknownKeyNoPlans": True,
        "driftFailsClosed": True,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
