#!/usr/bin/env python
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools"


def load_tool_module(module_name: str, filename: str):
    sys.path.insert(0, str(TOOLS_DIR))
    spec = importlib.util.spec_from_file_location(module_name, TOOLS_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {filename}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def make_controls(*, parent_stop: bool, child_2_stop: bool, child_3_stop: bool, child_6_stop: bool) -> dict[int, dict[str, Any]]:
    def control(stop: bool) -> dict[str, Any]:
        return {"frameScripts": {1: ["stop();"]} if stop else {}, "clipActions": []}

    return {
        1: control(parent_stop),
        2: control(child_2_stop),
        3: control(child_3_stop),
        4: control(False),
        5: control(False),
        6: control(child_6_stop),
    }


def make_graph() -> dict[int, dict[str, Any]]:
    return {
        1: {
            "frameCount": 6,
            "children": [2, 3, 4, 5],
            "childrenByFrame": {"1": [2, 3, 4], "2": [5]},
            "childInstances": [
                {"characterId": 2, "frame": 1, "depth": 1},
                {"characterId": 3, "frame": 1, "depth": 2},
                {"characterId": 4, "frame": 1, "depth": 3},
                {"characterId": 5, "frame": 2, "depth": 4},
            ],
        },
        2: {"frameCount": 5, "children": [], "childrenByFrame": {}, "childInstances": []},
        3: {"frameCount": 7, "children": [], "childrenByFrame": {}, "childInstances": []},
        4: {
            "frameCount": 1,
            "children": [6],
            "childrenByFrame": {"1": [6]},
            "childInstances": [{"characterId": 6, "frame": 1, "depth": 1}],
        },
        5: {"frameCount": 9, "children": [], "childrenByFrame": {}, "childInstances": []},
        6: {"frameCount": 4, "children": [], "childrenByFrame": {}, "childInstances": []},
    }


def descendant_ids(descendants: list[dict[str, Any]]) -> list[int]:
    return [int(item["characterId"]) for item in descendants]


def main() -> None:
    icons = load_tool_module("bake_icons_offline", "bake-icons-offline.py")
    dressup = load_tool_module("bake_dressup_offline", "bake-dressup-offline.py")
    graph = make_graph()

    parent_stop_controls = make_controls(
        parent_stop=True,
        child_2_stop=False,
        child_3_stop=True,
        child_6_stop=False,
    )
    icon_descendants, stopped_count = icons.animated_descendants(graph, parent_stop_controls, 1)
    dressup_descendants = dressup.animated_descendants(graph, parent_stop_controls, 1)
    icon_audit = icons.nested_animation_audit(graph, parent_stop_controls, 1)
    icon_payload = icons.icon_animation_structure_payload(
        icons.IconTarget("sample", "linkage", "items", "test"),
        "sample.swf",
        1,
        graph,
        parent_stop_controls,
    )
    dressup_playback = dressup.playback_metadata(parent_stop_controls, graph, 1, 6, "auto")

    assert descendant_ids(icon_descendants) == [2, 6]
    assert descendant_ids(dressup_descendants) == [2, 6]
    assert stopped_count == 1
    assert icon_audit["nestedAnimatedDescendantCount"] == 2
    assert icon_audit["nestedStoppedDescendantCount"] == 1
    assert icon_payload["parentPlainFrame1Stop"] is True
    assert icon_payload["parentPlayback"] == "static-first-frame"
    assert dressup_playback["playback"] == "static-parent-nested-animation"
    assert dressup_playback["staticReason"] == "frame1_plain_stop_with_nested_animation"

    all_stopped_controls = make_controls(
        parent_stop=True,
        child_2_stop=True,
        child_3_stop=True,
        child_6_stop=True,
    )
    icon_static_descendants, icon_static_stopped = icons.animated_descendants(graph, all_stopped_controls, 1)
    dressup_static_descendants = dressup.animated_descendants(graph, all_stopped_controls, 1)
    dressup_static_playback = dressup.playback_metadata(all_stopped_controls, graph, 1, 6, "auto")

    assert icon_static_descendants == []
    assert dressup_static_descendants == []
    assert icon_static_stopped == 3
    assert dressup_static_playback["playback"] == "static-first-frame"

    controlled_goto_controls = {
        1: {
            "frameScripts": {
                1: [
                    "stop();\n"
                    "var targetFrame = _parent._parent._parent.牙狼剑帧;\n"
                    "if(targetFrame != undefined)\n"
                    "{\n"
                    "   gotoAndStop(targetFrame);\n"
                    "}\n"
                ]
            },
            "clipActions": [],
        }
    }
    controlled_goto_playback = dressup.playback_metadata(controlled_goto_controls, {}, 1, 11, "auto")
    assert controlled_goto_playback["playback"] == "static-first-frame"
    assert controlled_goto_playback["staticReason"] == "frame1_stop_with_host_controlled_goto"

    fixed_goto_controls = {1: {"frameScripts": {1: ["stop(); gotoAndStop(5);"]}, "clipActions": []}}
    fixed_goto_playback = dressup.playback_metadata(fixed_goto_controls, {}, 1, 11, "auto")
    assert fixed_goto_playback["playback"] == "loop"

    with tempfile.TemporaryDirectory(prefix="cf7-stopped-item-f2-") as temp_text:
        temp_dir = Path(temp_text)
        frame1 = temp_dir / "frame1.png"
        frame2 = temp_dir / "frame2.png"
        duplicate_frame2 = temp_dir / "frame2-duplicate.png"
        hidden_rgb_duplicate_frame2 = temp_dir / "frame2-hidden-rgb-duplicate.png"
        transparent_frame2 = temp_dir / "frame2-transparent.png"
        Image.new("RGBA", (8, 8), (80, 120, 160, 255)).save(frame1)
        Image.new("RGBA", (8, 8), (160, 120, 80, 255)).save(frame2)
        Image.new("RGBA", (8, 8), (80, 120, 160, 255)).save(duplicate_frame2)
        hidden_rgb_duplicate = Image.new("RGBA", (8, 8), (80, 120, 160, 255))
        hidden_rgb_duplicate.putpixel((0, 0), (255, 40, 20, 0))
        hidden_rgb_duplicate.save(hidden_rgb_duplicate_frame2)
        frame1_with_transparent_pixel = Image.open(frame1).convert("RGBA")
        frame1_with_transparent_pixel.putpixel((0, 0), (0, 0, 0, 0))
        frame1_with_transparent_pixel.save(frame1)
        duplicate_with_transparent_pixel = Image.open(duplicate_frame2).convert("RGBA")
        duplicate_with_transparent_pixel.putpixel((0, 0), (0, 0, 0, 0))
        duplicate_with_transparent_pixel.save(duplicate_frame2)
        Image.new("RGBA", (8, 8), (0, 0, 0, 0)).save(transparent_frame2)

        item_target = icons.IconTarget("item", "item-linkage", "item", "test")
        item_tier_target = icons.IconTarget("item-tier", "item-tier-linkage", "item-tier", "test")
        skill_target = icons.IconTarget("skill", "skill-linkage", "skill", "test")

        assert icons.stopped_item_has_semantic_frame2(
            item_target,
            parent_frame1_stop=True,
            frame1=frame1,
            frame2=frame2,
            profile_size=(8, 8),
        )
        assert icons.stopped_item_has_semantic_frame2(
            item_tier_target,
            parent_frame1_stop=True,
            frame1=frame1,
            frame2=frame2,
            profile_size=(8, 8),
        )
        assert not icons.stopped_item_has_semantic_frame2(
            skill_target,
            parent_frame1_stop=True,
            frame1=frame1,
            frame2=frame2,
            profile_size=(8, 8),
        )
        assert not icons.stopped_item_has_semantic_frame2(
            item_target,
            parent_frame1_stop=False,
            frame1=frame1,
            frame2=frame2,
            profile_size=(8, 8),
        )
        assert not icons.stopped_item_has_semantic_frame2(
            item_target,
            parent_frame1_stop=True,
            frame1=frame1,
            frame2=duplicate_frame2,
            profile_size=(8, 8),
        )
        assert not icons.stopped_item_has_semantic_frame2(
            item_target,
            parent_frame1_stop=True,
            frame1=frame1,
            frame2=hidden_rgb_duplicate_frame2,
            profile_size=(8, 8),
        )
        assert not icons.stopped_item_has_semantic_frame2(
            item_target,
            parent_frame1_stop=True,
            frame1=frame1,
            frame2=transparent_frame2,
            profile_size=(8, 8),
        )
        assert icons.static_frame_pairs(True, True) == ((1, "f1"), (2, "f2"))
        assert icons.static_frame_pairs(True, False) == ((1, "f1"),)
        assert icons.static_frame_pairs(False, False) == ((1, "f1"), (2, "f2"))

    explicit_play_controls = {1: {"frameScripts": {1: ["stop(); play();"]}, "clipActions": []}}
    explicit_play_playback = dressup.playback_metadata(explicit_play_controls, {}, 1, 11, "auto")
    assert explicit_play_playback["playback"] == "loop"

    parent_loop_controls = make_controls(
        parent_stop=False,
        child_2_stop=False,
        child_3_stop=True,
        child_6_stop=False,
    )
    icon_loop_descendants, _ = icons.animated_descendants(graph, parent_loop_controls, 1)
    dressup_loop_descendants = dressup.animated_descendants(graph, parent_loop_controls, 1)
    assert sorted(descendant_ids(icon_loop_descendants)) == [2, 5, 6]
    assert sorted(descendant_ids(dressup_loop_descendants)) == [2, 5, 6]

    print(
        json.dumps(
            {
                "parentStopNested": {
                    "iconDescendants": descendant_ids(icon_descendants),
                    "dressupDescendants": descendant_ids(dressup_descendants),
                    "stoppedDescendants": stopped_count,
                    "iconParentPlayback": icon_payload["parentPlayback"],
                    "dressupPlayback": dressup_playback["playback"],
                },
                "allChildrenStopped": {
                    "stoppedDescendants": icon_static_stopped,
                    "dressupPlayback": dressup_static_playback["playback"],
                },
                "parentLoop": {
                    "iconDescendants": descendant_ids(icon_loop_descendants),
                    "dressupDescendants": descendant_ids(dressup_loop_descendants),
                },
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
