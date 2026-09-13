#!/usr/bin/env python3
"""对话立绘烘焙器 swf2xml 时间轴分层解析的合同测试。

覆盖的真实缺陷：`timeline_labels_from_swf_xml` 旧实现逐行累计全文
ShowFrameTag，DefineSpriteTag <subTags> 内的嵌套帧被计入根帧号，且嵌套
sprite 的 FrameLabelTag 混进根标签表。生产后果见调查快照
docs/evidence/dialogue-migration-research-2026-09-12.json 的
sourceFrameMappingAudit（11 项同名根标签帧号不符 + 13 项 missingFrames
中实际存在的帧）。

测试分两层：
1. 结构化夹具 —— 复制真实 FFDec -swf2xml 的元素形态（<tags> 直接子项 /
   DefineSpriteTag 内 <subTags> / sprite 套 sprite），固定断言帧号。
2. 当前源 SWF —— 对 Andy Law / 清水结衣 / 堕落城盗贼 / 室友 实跑 ffdec
   -swf2xml 后断言逐标签根帧号，基准值来自调查快照与文档复核。
"""
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
PRODUCTION_ASSET_ROOT = ROOT / "launcher" / "web" / "assets" / "dialogue-portraits"
BAKER_PATH = ROOT / "tools" / "bake-dialogue-portraits.py"
FFDEC_PATH = ROOT / "tools" / "ffdec" / "ffdec-cli.exe"
PORTRAIT_DIR = ROOT / "flashswf" / "portraits"
FFDEC_TIMEOUT_SECONDS = 300


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_baker() -> Any:
    spec = importlib.util.spec_from_file_location("cf7_dialogue_portrait_baker", BAKER_PATH)
    require(spec is not None and spec.loader is not None, "cannot load dialogue portrait baker")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# 结构复刻真实 FFDec 21.1.1 输出：<tags> 直接子项持有根时间轴；DefineSpriteTag
# 用 <subTags> 包自己的子时间轴。sprite 7 的 3 个嵌套帧先于根标签「微笑」——
# 旧实现会把它们计入根帧，使「微笑」=5、「严肃」=6（正确值 2 / 3）。
NESTED_BEFORE_LABEL_XML = """<?xml version="1.0" encoding="UTF-8"?>
<swf _xmlExportMajor="2" _xmlExportMinor="1" type="SWF" frameCount="3" frameRate="30.0">
  <tags>
    <item type="FileAttributesTag" actionScript3="false"/>
    <item type="SetBackgroundColorTag" forceWriteAsLong="false">
      <backgroundColor type="RGB" blue="255" green="255" red="255"/>
    </item>
    <item type="FrameLabelTag" forceWriteAsLong="true" name="普通" namedAnchor="false"/>
    <item type="ShowFrameTag" forceWriteAsLong="false"/>
    <item type="DefineSpriteTag" forceWriteAsLong="true" frameCount="3" hasEndTag="true" spriteId="7">
      <subTags>
        <item type="FrameLabelTag" forceWriteAsLong="true" name="男" namedAnchor="false"/>
        <item type="ShowFrameTag" forceWriteAsLong="false"/>
        <item type="FrameLabelTag" forceWriteAsLong="true" name="女" namedAnchor="false"/>
        <item type="ShowFrameTag" forceWriteAsLong="false"/>
        <item type="ShowFrameTag" forceWriteAsLong="false"/>
        <item type="EndTag" forceWriteAsLong="false"/>
      </subTags>
    </item>
    <item type="FrameLabelTag" forceWriteAsLong="true" name="微笑" namedAnchor="false"/>
    <item type="ShowFrameTag" forceWriteAsLong="false"/>
    <item type="FrameLabelTag" forceWriteAsLong="true" name="严肃" namedAnchor="false"/>
    <item type="ShowFrameTag" forceWriteAsLong="false"/>
    <item type="EndTag" forceWriteAsLong="false"/>
  </tags>
</swf>
"""

# sprite 套 sprite：定义标签不占帧，内层 sprite 9 的 2 帧既不能进根计数，
# 也不能抬高外层 sprite 8 自己的帧号。正确：根 {普通@1, 迟到@2}；
# sprite8 {外层@1, 外层尾@2}（内层定义位于其第 2 帧的 tag 序列里）。
NESTED_SPRITE_IN_SPRITE_XML = """<?xml version="1.0" encoding="UTF-8"?>
<swf _xmlExportMajor="2" _xmlExportMinor="1" type="SWF" frameCount="2">
  <tags>
    <item type="FrameLabelTag" forceWriteAsLong="true" name="普通" namedAnchor="false"/>
    <item type="ShowFrameTag" forceWriteAsLong="false"/>
    <item type="DefineSpriteTag" forceWriteAsLong="true" frameCount="2" hasEndTag="true" spriteId="8">
      <subTags>
        <item type="FrameLabelTag" forceWriteAsLong="true" name="外层" namedAnchor="false"/>
        <item type="ShowFrameTag" forceWriteAsLong="false"/>
        <item type="DefineSpriteTag" forceWriteAsLong="true" frameCount="2" hasEndTag="true" spriteId="9">
          <subTags>
            <item type="FrameLabelTag" forceWriteAsLong="true" name="深层" namedAnchor="false"/>
            <item type="ShowFrameTag" forceWriteAsLong="false"/>
            <item type="ShowFrameTag" forceWriteAsLong="false"/>
          </subTags>
        </item>
        <item type="FrameLabelTag" forceWriteAsLong="true" name="外层尾" namedAnchor="false"/>
        <item type="ShowFrameTag" forceWriteAsLong="false"/>
      </subTags>
    </item>
    <item type="FrameLabelTag" forceWriteAsLong="true" name="迟到" namedAnchor="false"/>
    <item type="ShowFrameTag" forceWriteAsLong="false"/>
    <item type="EndTag" forceWriteAsLong="false"/>
  </tags>
</swf>
"""

DUPLICATE_LABEL_XML = """<?xml version="1.0" encoding="UTF-8"?>
<swf _xmlExportMajor="2" _xmlExportMinor="1" type="SWF" frameCount="3">
  <tags>
    <item type="FrameLabelTag" forceWriteAsLong="true" name="普通" namedAnchor="false"/>
    <item type="ShowFrameTag" forceWriteAsLong="false"/>
    <item type="FrameLabelTag" forceWriteAsLong="true" name="普通" namedAnchor="false"/>
    <item type="ShowFrameTag" forceWriteAsLong="false"/>
    <item type="ShowFrameTag" forceWriteAsLong="false"/>
  </tags>
</swf>
"""

NO_LABEL_XML = """<?xml version="1.0" encoding="UTF-8"?>
<swf _xmlExportMajor="2" _xmlExportMinor="1" type="SWF" frameCount="1">
  <tags>
    <item type="SetBackgroundColorTag" forceWriteAsLong="false">
      <backgroundColor type="RGB" blue="255" green="255" red="255"/>
    </item>
    <item type="ShowFrameTag" forceWriteAsLong="false"/>
    <item type="EndTag" forceWriteAsLong="false"/>
  </tags>
</swf>
"""

# 调查快照复核过的当前源根标签帧（sourceFrameMappingAudit + report missingFrames
# 交叉验证：清水结衣「比划」在根帧 46，旧 manifest 请求 58；堕落城盗贼三个表情在
# 19/26/33，旧请求 43/50/70）。rootFrames 同时对照 swf 头 frameCount。
EXPECTED_REAL_TIMELINES = {
    "Andy Law": {
        "frameCount": 73,
        "root": {
            "普通": 1, "微笑": 6, "大笑": 7, "严肃": 11, "坏笑": 12,
            "愤怒": 16, "悲伤": 21, "无奈": 22, "侦察": 26, "惊讶": 27,
            "挑战": 31, "普通2": 37, "侦查2": 38, "微笑2": 43, "惊讶2": 44,
            "坏笑2": 49, "大笑2": 50, "严肃2": 55, "挑战2": 56, "愤怒2": 61,
            "悲伤2": 67, "无奈2": 68,
        },
    },
    "清水结衣": {
        "frameCount": 55,
        "root": {"普通": 1, "微笑": 10, "呲牙": 20, "难过": 31, "思考": 40, "比划": 46},
    },
    "堕落城盗贼": {
        "frameCount": 40,
        "root": {"普通": 1, "黑铁死士": 5, "黑铁游侠": 12, "摇滚学姐": 19, "掠夺少女": 26, "精锐掠夺少女": 33},
    },
}

# 室友是另一类语义：根时间轴只有 1 帧且无标签，男女标签在嵌套 sprite 6 的
# 第 2/16 帧，由运行时按玩家性别选择。静态根帧导出只应得到默认 普通@1，
# 男女必须作为嵌套变体记录而不是根标签。
EXPECTED_ROOMMATE = {
    "frameCount": 1,
    "root": {},
    "sprites": {"6": {"男": 2, "女": 16}},
}


def write_fixture(tmp: Path, name: str, body: str) -> Path:
    path = tmp / f"{name}.xml"
    path.write_text(body, encoding="utf-8")
    return path


def exercise_fixtures(baker: Any, tmp: Path) -> None:
    timelines = baker.swf_xml_timelines(write_fixture(tmp, "nested", NESTED_BEFORE_LABEL_XML))
    require(
        timelines["root"] == {"普通": 1, "微笑": 2, "严肃": 3},
        f"nested sprite frames leaked into root timeline: {timelines['root']}",
    )
    require(timelines["rootFrames"] == 3, "root frame count must ignore nested ShowFrames")
    require(
        timelines["sprites"] == {"7": {"男": 1, "女": 2}},
        f"nested sprite labels must keep their own per-sprite frames: {timelines['sprites']}",
    )
    labels = baker.timeline_labels_from_swf_xml(write_fixture(tmp, "nested2", NESTED_BEFORE_LABEL_XML))
    require("男" not in labels and "女" not in labels, "nested labels must not leak into root labels")

    timelines = baker.swf_xml_timelines(write_fixture(tmp, "deep", NESTED_SPRITE_IN_SPRITE_XML))
    require(
        timelines["root"] == {"普通": 1, "迟到": 2},
        f"sprite-in-sprite frames leaked into root timeline: {timelines['root']}",
    )
    require(
        timelines["sprites"].get("9") == {"深层": 1},
        f"innermost sprite labels must bind to the innermost sprite: {timelines['sprites']}",
    )
    require(
        timelines["sprites"].get("8") == {"外层": 1, "外层尾": 2},
        f"outer sprite frame counter must not absorb nested sprite frames: {timelines['sprites']}",
    )

    timelines = baker.swf_xml_timelines(write_fixture(tmp, "dup", DUPLICATE_LABEL_XML))
    require(timelines["root"] == {"普通": 1}, f"duplicate root label must keep first frame: {timelines['root']}")

    labels = baker.timeline_labels_from_swf_xml(write_fixture(tmp, "nolabel", NO_LABEL_XML))
    require(labels == {"普通": 1}, f"label-less timeline must default to 普通@1: {labels}")


def subtags_frames_before_label(xml_path: Path, label: str) -> bool:
    """该根标签之前是否真有一段 <subTags> 内含 ShowFrame（即误计陷阱确实存在）。"""
    depth = 0
    saw_nested_frame = False
    needle = f'name="{label}"'
    with xml_path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "<subTags" in line:
                depth += 1
            if "</subTags" in line:
                depth -= 1
            if depth > 0 and 'type="ShowFrameTag"' in line:
                saw_nested_frame = True
            if depth == 0 and 'type="FrameLabelTag"' in line and needle in line:
                return saw_nested_frame
    return False


def exercise_real_sources(baker: Any, tmp: Path) -> dict[str, Any]:
    require(FFDEC_PATH.is_file(), f"missing FFDec CLI: {FFDEC_PATH}")
    evidence: dict[str, Any] = {}
    for name, expected in EXPECTED_REAL_TIMELINES.items():
        swf = PORTRAIT_DIR / f"{name}.swf"
        require(swf.is_file(), f"missing portrait source SWF: {swf}")
        xml_path = tmp / f"real-{name}.xml"
        baker.export_swf_xml(FFDEC_PATH, ROOT, swf, xml_path, FFDEC_TIMEOUT_SECONDS)
        timelines = baker.swf_xml_timelines(xml_path)
        require(
            timelines["root"] == expected["root"],
            f"{name} root labels drifted: {timelines['root']}",
        )
        require(
            timelines["rootFrames"] == expected["frameCount"],
            f"{name} root frame count {timelines['rootFrames']} != header frameCount {expected['frameCount']}",
        )
        labels = baker.timeline_labels_from_swf_xml(xml_path)
        require(labels == expected["root"], f"{name} public labels mismatch: {labels}")
        trap_label = next(iter(sorted(expected["root"], key=expected["root"].get, reverse=True)))
        require(
            subtags_frames_before_label(xml_path, trap_label),
            f"{name}: expected nested ShowFrame before root label {trap_label} (fixture must exercise the real bug)",
        )
        evidence[name] = {"rootLabels": len(expected["root"]), "rootFrames": timelines["rootFrames"]}

    swf = PORTRAIT_DIR / "室友.swf"
    require(swf.is_file(), f"missing portrait source SWF: {swf}")
    xml_path = tmp / "real-室友.xml"
    baker.export_swf_xml(FFDEC_PATH, ROOT, swf, xml_path, FFDEC_TIMEOUT_SECONDS)
    timelines = baker.swf_xml_timelines(xml_path)
    require(timelines["root"] == EXPECTED_ROOMMATE["root"], f"室友 root must stay label-less: {timelines['root']}")
    require(
        timelines["sprites"] == EXPECTED_ROOMMATE["sprites"],
        f"室友 sprite-6 gender labels mismatch: {timelines['sprites']}",
    )
    require(timelines["rootFrames"] == EXPECTED_ROOMMATE["frameCount"], "室友 root frameCount drift")
    labels = baker.timeline_labels_from_swf_xml(xml_path)
    require(labels == {"普通": 1}, f"室友 public labels must be the single default frame: {labels}")
    evidence["室友"] = {"rootLabels": 0, "sprites": timelines["sprites"], "needsRuntimeVariant": True}
    return evidence


def exercise_selection_helpers(baker: Any) -> None:
    require(baker.parse_selection_csv("") is None, "empty selection must be None")
    require(baker.parse_selection_csv(" , ,") is None, "blank selection must be None")
    require(
        baker.parse_selection_csv("Andy Law, 清水结衣 ,") == {"Andy Law", "清水结衣"},
        "selection csv must trim and drop empties",
    )
    frames = {"普通": 1, "微笑": 10, "思考": 40}
    require(
        baker.filter_expression_frames(frames, {"微笑"}) == {"普通": 1, "微笑": 10},
        "expression filter must always retain the default expression",
    )
    require(
        baker.filter_expression_frames(frames, None) == frames,
        "no expression filter must keep all frames",
    )
    lookup = baker.swf_lookup(PORTRAIT_DIR)
    require(
        external_selected := baker.external_name_selected("boy", lookup, {"Boy"}),
        "external selection must match by SWF stem as well as list name",
    )
    require(
        not baker.external_name_selected("Andy Law", lookup, {"Boy"}),
        "external selection must not match unrelated names",
    )


def exercise_output_guards(baker: Any, tmp: Path) -> None:
    """候选/输出目录 guard 用纯函数断言：生产目录只作参数，绝不实跑 baker。"""
    trial_out = (tmp / "trial-out").resolve()
    production = PRODUCTION_ASSET_ROOT.resolve()
    baker.ensure_subset_output_dir(trial_out, production, True)
    baker.ensure_subset_output_dir(production, production, False)
    try:
        baker.ensure_subset_output_dir(production, production, True)
    except SystemExit:
        pass
    else:
        raise AssertionError("subset bake into the production asset dir must fail closed")

    # 正例必须是项目 tmp/ 下的路径（guard 只按解析后路径判断，不要求存在）。
    baker.ensure_review_candidate_dir((ROOT / "tmp" / "cf7-test-candidates").resolve(), ROOT)
    outside_tmp = Path(tmp.anchor) / "cf7-not-under-project-tmp" if tmp.anchor else Path("/cf7-not-under-project-tmp")
    try:
        baker.ensure_review_candidate_dir(outside_tmp, ROOT)
    except RuntimeError as error:
        require("tmp" in str(error), "review candidate error must name the tmp requirement")
    else:
        raise AssertionError("review candidate dir outside tmp/ must fail closed")


def exercise_image_format(baker: Any, tmp: Path) -> None:
    require(baker.stable_file("普通") == f"e_{baker.short_hash('普通')}.png", "default format must stay png")
    webp_name = baker.stable_file("普通", "webp")
    require(webp_name.endswith(".webp") and webp_name[:-5] == baker.stable_file("普通")[:-4],
            "webp uri must share the same stable hash with a .webp suffix")

    src = tmp / "1.png"
    image = Image.new("RGBA", (6, 4), (0, 0, 0, 0))
    image.putpixel((0, 0), (200, 30, 40, 0))   # 全透明但带 RGB：只有 exact=True 才保得住
    image.putpixel((2, 1), (24, 96, 180, 255))
    image.putpixel((3, 2), (240, 200, 60, 200))
    image.save(src)

    out = tmp / "webp-out"
    asset = baker.copy_asset(src, out, "internal/p_fixture", "普通", source_kind="dialogue-ui-sprite", image_format="webp")
    require(asset["uri"].endswith(".webp"), "webp asset uri must carry the .webp extension")
    require((asset["width"], asset["height"]) == (6, 4), "webp asset size must be recorded")
    dst = out / asset["uri"]
    require(baker.raster_magic(dst.read_bytes()) == "webp", "webp output must carry RIFF/WEBP magic")
    with Image.open(src) as s, Image.open(dst) as d:
        require(
            s.convert("RGBA").tobytes() == d.convert("RGBA").tobytes(),
            "lossless+exact webp must round-trip RGBA including transparent RGB",
        )
    require(
        asset["bounds"] == {"x": 2, "y": 1, "width": 2, "height": 2},
        "webp alpha bounds must come from the decoded image",
    )

    # 语义基线跨格式绝不复用：baseline 只有 PNG URI/字节，webp 输出必须新编码。
    baseline_root = tmp / "baseline-png"
    png_uri = f"internal/p_fixture/{baker.stable_file('普通', 'png')}"
    png_path = baseline_root / png_uri
    png_path.parent.mkdir(parents=True)
    baseline_image = Image.new("RGBA", (6, 4), (0, 0, 0, 0))
    baseline_image.putpixel((2, 1), (24, 96, 180, 255))
    baseline_image.putpixel((3, 2), (240, 200, 60, 200))
    baseline_image.save(png_path)
    (baseline_root / "manifest.json").write_text(
        json.dumps(
            {
                "schema": baker.SCHEMA,
                "entries": {
                    "fixture": {
                        "source": "dialogue-ui-sprite",
                        "expressions": {
                            "普通": {
                                "uri": png_uri,
                                "width": 6,
                                "height": 4,
                                "frame": 1,
                                "bounds": {"x": 2, "y": 1, "width": 2, "height": 2},
                            }
                        },
                    }
                },
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    png_baseline = baker.load_semantic_baseline(baseline_root)
    noops: list[dict[str, Any]] = []
    webp_asset = baker.copy_asset(
        src, tmp / "webp-out2", "internal/p_fixture", "普通",
        source_kind="dialogue-ui-sprite", image_format="webp",
        semantic_baseline=png_baseline, semantic_noop_assets=noops,
    )
    require(noops == [], "a PNG baseline must never be reused into a .webp output")
    require(
        baker.raster_magic((tmp / "webp-out2" / webp_asset["uri"]).read_bytes()) == "webp",
        "cross-format reuse must produce a fresh webp encode",
    )

    # 同格式 webp 基线的语义复用必须成立：可见 RGBA + alpha 边界一致 → 复用字节。
    webp_baseline_root = tmp / "baseline-webp"
    webp_uri = f"internal/p_fixture/{webp_name}"
    webp_path = webp_baseline_root / webp_uri
    webp_path.parent.mkdir(parents=True)
    baseline_image.convert("RGBA").save(webp_path, format="WEBP", lossless=True, exact=True)
    (webp_baseline_root / "manifest.json").write_text(
        json.dumps(
            {
                "schema": baker.SCHEMA,
                "entries": {
                    "fixture": {
                        "source": "dialogue-ui-sprite",
                        "expressions": {
                            "普通": {
                                "uri": webp_uri,
                                "width": 6,
                                "height": 4,
                                "frame": 1,
                                "bounds": {"x": 2, "y": 1, "width": 2, "height": 2},
                            }
                        },
                    }
                },
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    webp_baseline = baker.load_semantic_baseline(webp_baseline_root)
    noops2: list[dict[str, Any]] = []
    reused_asset = baker.copy_asset(
        src, tmp / "webp-out3", "internal/p_fixture", "普通",
        source_kind="dialogue-ui-sprite", image_format="webp",
        semantic_baseline=webp_baseline, semantic_noop_assets=noops2,
    )
    require(len(noops2) == 1, "same-format webp alpha-equivalent baseline must be reused")
    require(
        (tmp / "webp-out3" / reused_asset["uri"]).read_bytes() == webp_path.read_bytes(),
        "reused webp must carry the baseline bytes",
    )

    # 资产闭包混合格式：未引用的 .png 与 .webp 都 prune，最终集合等于 manifest。
    closure_out = tmp / "closure"
    referenced_path = closure_out / asset["uri"]
    referenced_path.parent.mkdir(parents=True, exist_ok=True)
    referenced_path.write_bytes(dst.read_bytes())
    for stray in ("stale/old.png", "stale/old.webp"):
        stray_path = closure_out / stray
        stray_path.parent.mkdir(parents=True, exist_ok=True)
        if stray.endswith(".png"):
            image.save(stray_path)
        else:
            image.convert("RGBA").save(stray_path, format="WEBP", lossless=True, exact=True)
    referenced, pruned = baker.enforce_asset_closure(
        closure_out,
        {"entries": {"fixture": {"expressions": {"普通": asset}}}},
    )
    require(referenced == {asset["uri"]}, "closure must reference exactly the manifest URIs")
    require(sorted(pruned) == ["stale/old.png", "stale/old.webp"], "both stale formats must be pruned")
    require(not (closure_out / "stale").exists(), "pruned empty dirs must be removed")


def main() -> None:
    baker = load_baker()
    exercise_selection_helpers(baker)
    with tempfile.TemporaryDirectory(prefix="cf7-dialogue-timelines-") as temp_dir:
        tmp = Path(temp_dir)
        exercise_fixtures(baker, tmp)
        exercise_output_guards(baker, tmp)
        exercise_image_format(baker, tmp)
        evidence = exercise_real_sources(baker, tmp)
    print(
        json.dumps(
            {
                "status": "dialogue_portrait_timelines_verified",
                "nestedSpriteFramesExcludedFromRoot": True,
                "spriteInSpriteIsolated": True,
                "duplicateLabelKeepsFirst": True,
                "labelLessDefaultsToNormal": True,
                "selectionHelpers": True,
                "outputGuardsFailClosed": True,
                "webpLosslessExact": True,
                "crossFormatBaselineNeverReused": True,
                "realSources": evidence,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
