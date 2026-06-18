#!/usr/bin/env python
from __future__ import annotations

import importlib.util
import json
import shutil
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools"
WORK_DIR = PROJECT_ROOT / "tmp" / "test-icon-animated-budget"


def load_icon_tool():
    sys.path.insert(0, str(TOOLS_DIR))
    spec = importlib.util.spec_from_file_location("bake_icons_offline_budget_test", TOOLS_DIR / "bake-icons-offline.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load bake-icons-offline.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["bake_icons_offline_budget_test"] = module
    spec.loader.exec_module(module)
    return module


def write_png(path: Path, color: tuple[int, int, int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", (8, 8), color).save(path, format="PNG", optimize=True)


def make_entry() -> dict:
    return {
        "f1": "sample_1.png",
        "playback": "nested-animation",
        "animated": True,
        "fps": 24,
        "format": "layered-png-sequence",
        "nestedAnimation": {
            "strategy": "direct-layered-icon-canvas",
            "base": {"uri": "sample_base.png"},
            "layers": [
                {
                    "characterId": 10,
                    "frames": [
                        {
                            "frame": 1,
                            "sourceFrame": 1,
                            "uri": "sample_layer10_1.png",
                            "cropX": 2,
                            "cropY": 3,
                            "cropWidth": 4,
                            "cropHeight": 5,
                            "canvasWidth": 8,
                            "canvasHeight": 8,
                        },
                        {
                            "frame": 2,
                            "sourceFrame": 2,
                            "uri": "sample_layer10_2.png",
                            "cropX": 2,
                            "cropY": 4,
                            "cropWidth": 4,
                            "cropHeight": 4,
                            "canvasWidth": 8,
                            "canvasHeight": 8,
                        },
                    ],
                }
            ],
        },
    }


def make_visually_static_entry() -> dict:
    entry = make_entry()
    for frame in entry["nestedAnimation"]["layers"][0]["frames"]:
        frame["uri"] = "sample_layer10_1.png"
        frame["cropX"] = 2
        frame["cropY"] = 3
        frame["cropWidth"] = 4
        frame["cropHeight"] = 5
        frame["canvasWidth"] = 8
        frame["canvasHeight"] = 8
    entry["nestedAnimation"]["layers"][0]["timelineFrames"] = [
        {
            "frame": 1,
            "sourceFrame": 1,
            "uri": "sample_layer10_1.png",
            "cropX": 2,
            "cropY": 3,
            "cropWidth": 4,
            "cropHeight": 5,
            "canvasWidth": 8,
            "canvasHeight": 8,
            "durationFrames": 2,
        }
    ]
    return entry


def make_crop_motion_entry() -> dict:
    entry = make_visually_static_entry()
    entry["nestedAnimation"]["layers"][0]["timelineFrames"] = [
        {
            "frame": 1,
            "sourceFrame": 1,
            "uri": "sample_layer10_1.png",
            "cropX": 2,
            "cropY": 3,
            "cropWidth": 4,
            "cropHeight": 5,
            "canvasWidth": 8,
            "canvasHeight": 8,
        },
        {
            "frame": 2,
            "sourceFrame": 2,
            "uri": "sample_layer10_1.png",
            "cropX": 3,
            "cropY": 3,
            "cropWidth": 4,
            "cropHeight": 5,
            "canvasWidth": 8,
            "canvasHeight": 8,
        },
    ]
    return entry


def prepare_files() -> None:
    shutil.rmtree(WORK_DIR, ignore_errors=True)
    write_png(WORK_DIR / "sample_1.png", (255, 0, 0, 255))
    write_png(WORK_DIR / "sample_base.png", (0, 0, 0, 0))
    write_png(WORK_DIR / "sample_layer10_1.png", (0, 255, 0, 160))
    write_png(WORK_DIR / "sample_layer10_2.png", (0, 0, 255, 160))


def main() -> None:
    tool = load_icon_tool()
    prepare_files()
    entry = make_entry()
    referenced = tool.manifest_entry_files(entry)
    assert referenced == {
        "sample_1.png",
        "sample_base.png",
        "sample_layer10_1.png",
        "sample_layer10_2.png",
    }

    report = {"counts": defaultdict(int)}
    downgraded = tool.apply_animated_icon_budget(
        output_dir=WORK_DIR,
        entry=entry,
        icon_name="sample",
        linkage_id="图标-sample",
        max_bytes=1,
        dry_run=False,
        report=report,
    )
    assert downgraded["playback"] == "static-first-frame"
    assert downgraded["animated"] is False
    assert set(tool.manifest_entry_files(downgraded)) == {"sample_1.png"}
    assert (WORK_DIR / "sample_1.png").exists()
    assert not (WORK_DIR / "sample_base.png").exists()
    assert not (WORK_DIR / "sample_layer10_1.png").exists()
    assert not (WORK_DIR / "sample_layer10_2.png").exists()
    assert report["counts"]["animated_icon_budget_skipped"] == 1
    assert report["counts"]["animated_budget_purged_files"] == 3

    prepare_files()
    report_keep = {"counts": defaultdict(int)}
    kept = tool.apply_animated_icon_budget(
        output_dir=WORK_DIR,
        entry=make_entry(),
        icon_name="sample",
        linkage_id="图标-sample",
        max_bytes=10_000_000,
        dry_run=False,
        report=report_keep,
    )
    assert kept["animated"] is True
    assert report_keep["counts"]["animated_icon_budget_checked"] == 1
    assert report_keep["counts"].get("animated_icon_budget_skipped", 0) == 0
    assert all((WORK_DIR / filename).exists() for filename in tool.manifest_entry_files(kept))

    prepare_files()
    report_static = {"counts": defaultdict(int)}
    visually_static = tool.downgrade_visually_static_animation(
        output_dir=WORK_DIR,
        entry=make_visually_static_entry(),
        icon_name="sample",
        linkage_id="鍥炬爣-sample",
        dry_run=False,
        report=report_static,
    )
    assert visually_static["animated"] is False
    assert visually_static["playback"] == "static-first-frame"
    assert report_static["counts"]["animated_visual_static_downgraded"] == 1
    assert set(tool.manifest_entry_files(visually_static)) == {"sample_1.png"}
    assert not (WORK_DIR / "sample_base.png").exists()
    assert not (WORK_DIR / "sample_layer10_1.png").exists()

    prepare_files()
    report_motion = {"counts": defaultdict(int)}
    motion = tool.downgrade_visually_static_animation(
        output_dir=WORK_DIR,
        entry=make_crop_motion_entry(),
        icon_name="sample",
        linkage_id="鍥炬爣-sample",
        dry_run=False,
        report=report_motion,
    )
    assert motion["animated"] is True
    assert report_motion["counts"].get("animated_visual_static_downgraded", 0) == 0
    assert all((WORK_DIR / filename).exists() for filename in tool.manifest_entry_files(motion))

    print(
        json.dumps(
            {
                "referencedFiles": sorted(referenced),
                "downgraded": downgraded,
                "skipCounts": report["counts"],
                "keepCounts": report_keep["counts"],
                "visualStaticCounts": report_static["counts"],
                "visualMotionCounts": report_motion["counts"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
