#!/usr/bin/env python
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools"
WORK_DIR = PROJECT_ROOT / "tmp" / "test-icon-animation-candidate-filter"


def load_icon_tool():
    sys.path.insert(0, str(TOOLS_DIR))
    spec = importlib.util.spec_from_file_location(
        "bake_icons_offline_candidate_filter_test",
        TOOLS_DIR / "bake-icons-offline.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load bake-icons-offline.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["bake_icons_offline_candidate_filter_test"] = module
    spec.loader.exec_module(module)
    return module


def main() -> None:
    tool = load_icon_tool()
    layered = {
        "classification": "direct-layered-candidate",
        "maxNestedDescendantFrameCount": 24,
    }
    single = {
        "classification": "single-child-canvas-candidate",
        "maxNestedDescendantFrameCount": 32,
    }
    heavy = {
        "classification": "direct-layered-candidate",
        "maxNestedDescendantFrameCount": 120,
    }
    unsupported = {
        "classification": "nested-animation-unsupported",
        "maxNestedDescendantFrameCount": 10,
    }

    assert tool.animation_candidate_filter_decision(
        layered,
        strategy="all",
        max_source_frames=0,
    ) == (True, "selected")
    assert tool.animation_candidate_filter_decision(
        single,
        strategy="direct-layered",
        max_source_frames=0,
    ) == (False, "strategy_not_direct_layered")
    assert tool.animation_candidate_filter_decision(
        layered,
        strategy="single-child",
        max_source_frames=0,
    ) == (False, "strategy_not_single_child")
    assert tool.animation_candidate_filter_decision(
        heavy,
        strategy="all",
        max_source_frames=60,
    ) == (False, "source_frame_budget")
    assert tool.animation_candidate_filter_decision(
        unsupported,
        strategy="all",
        max_source_frames=0,
    ) == (False, "nested-animation-unsupported")

    WORK_DIR.mkdir(parents=True, exist_ok=True)
    report_path = WORK_DIR / "structure-report.json"
    report_path.write_text(
        json.dumps(
            {
                "animationStructureCandidates": [
                    {"name": "layered", **layered},
                    {"name": "single", **single},
                    {"name": "heavy", **heavy},
                    {"name": "unsupported", **unsupported},
                ]
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    names, info = tool.load_animation_candidate_report_targets(
        report_path,
        strategy="all",
        max_source_frames=32,
    )
    assert names == {"layered", "single"}
    assert info["counts"]["checked"] == 4
    assert info["counts"]["selected"] == 2
    assert info["counts"]["skipped_source_frame_budget"] == 1
    assert info["counts"]["skipped_nested-animation-unsupported"] == 1

    print(
        json.dumps(
            {
                "selected": tool.animation_candidate_filter_decision(
                    layered,
                    strategy="all",
                    max_source_frames=0,
                ),
                "strategySkip": tool.animation_candidate_filter_decision(
                    single,
                    strategy="direct-layered",
                    max_source_frames=0,
                ),
                "frameBudgetSkip": tool.animation_candidate_filter_decision(
                    heavy,
                    strategy="all",
                    max_source_frames=60,
                ),
                "unsupportedSkip": tool.animation_candidate_filter_decision(
                    unsupported,
                    strategy="all",
                    max_source_frames=0,
                ),
                "reportNames": sorted(names),
                "reportCounts": info["counts"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
