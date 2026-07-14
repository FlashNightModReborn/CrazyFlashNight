#!/usr/bin/env python3
"""Synthetic smoke test for the reskin package builder."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

from audit_dressup_reskin import (
    REQUIRED_BATTLE_STATES,
    REQUIRED_COMPONENT_PLACEMENTS,
    REQUIRED_UNIQUE_SKINS,
    evaluate_battle_rig_acceptance,
    retarget_component,
)


TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[1]
MANAGED_OUTPUT_ROOT = REPO_ROOT / "tmp" / "monster-reskin"
BUILDER = TOOL_DIR / "build_reference_package.py"
CHILD_ENV = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONUTF8": "1"}


def main() -> int:
    MANAGED_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="smoke-", dir=MANAGED_OUTPUT_ROOT) as temp_value:
        temp = Path(temp_value)
        frames = temp / "frames"
        parts_png = temp / "parts-png"
        parts_svg = temp / "parts-svg"
        staging = temp / "staging"
        output = temp / "package"
        for path in [frames, parts_png, parts_svg, staging]:
            path.mkdir(parents=True)

        for frame in [1, 2, 3]:
            image = Image.new("RGBA", (320, 220), (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            draw.rectangle((10, 10, 140, 40), fill=(60, 220, 60, 255))
            draw.ellipse((120 + frame * 8, 100, 240 + frame * 8, 180), fill=(100, 70, 50, 255), outline=(0, 0, 0, 255), width=3)
            image.save(frames / f"{frame}.png")
        part = Image.new("RGBA", (120, 80), (0, 0, 0, 0))
        ImageDraw.Draw(part).ellipse((10, 10, 110, 70), fill=(110, 80, 60, 255))
        part.save(parts_png / "7.png")
        (parts_svg / "7.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg"><g transform="matrix(4, 0, 0, 4, -40, -30)"><path d="M0 0L1 1"/></g></svg>\n',
            encoding="utf-8",
        )
        export_manifest = {
            "schemaVersion": 2,
            "monster": "smoke-dog",
            "sourceSwf": "fixture.swf",
            "root": {"characterId": 99},
            "sequences": [{"slug": "action", "characterId": 99, "frameDir": str(frames), "frameCount": 3}],
            "parts": [{"slug": "body", "characterId": 7, "png": str(parts_png / "7.png"), "svg": str(parts_svg / "7.svg"), "localOriginPx": {"x": -40, "y": -30}}],
        }
        (staging / "export-manifest.json").write_text(json.dumps(export_manifest), encoding="utf-8")
        config = {
            "monster": "smoke-dog",
            "outputDir": str(output),
            "heroPose": "attack",
            "source": {"xfl": "fixture.xfl", "swf": "fixture.swf", "rootCharacterId": 99},
            "export": {"stagingDir": str(staging)},
            "sequences": [{"slug": "action", "characterId": 99, "startFrame": 1, "endFrame": 3}],
            "keyposes": [
                {"slug": "idle", "label": "idle", "sequence": "action", "frame": 1},
                {"slug": "attack", "label": "attack", "sequence": "action", "frame": 2},
            ],
            "parts": [{"slug": "body", "label": "body", "symbol": "Symbol 1", "characterId": 7, "group": "normal-rig"}],
            "guardrails": ["keep origin"],
        }
        config_path = temp / "config.json"
        config_path.write_text(json.dumps(config), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(BUILDER), "--config", str(config_path)],
            text=True,
            capture_output=True,
            encoding="utf-8",
            env=CHILD_ENV,
        )
        if result.returncode != 0:
            print(result.stdout)
            print(result.stderr, file=sys.stderr)
            return result.returncode
        expected = [
            output / "whole/core.png",
            output / "sheets/keyposes.png",
            output / "sheets/parts-normal-rig.png",
            output / "manifest.json",
            output / "README.md",
        ]
        missing = [str(path) for path in expected if not path.exists()]
        if missing:
            print(f"ERROR: missing {missing}", file=sys.stderr)
            return 1
        manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        if manifest["exportedSequenceFrameCount"] != 3 or len(manifest["parts"]) != 1:
            print("ERROR: bad manifest", file=sys.stderr)
            return 1
        for keypose_path in (output / "keyposes").glob("*.png"):
            alpha = Image.open(keypose_path).convert("RGBA").getchannel("A")
            bbox = alpha.getbbox()
            if bbox is None or bbox[0] == 0 or bbox[1] == 0 or bbox[2] == alpha.width or bbox[3] == alpha.height:
                print(f"ERROR: keypose padding was clipped: {keypose_path.name}", file=sys.stderr)
                return 1
        sequence_sizes = {
            Image.open(path).size
            for path in (output / "whole/full-sequence/action").glob("*.png")
        }
        if sequence_sizes != {(320, 220)}:
            print(f"ERROR: sequence canvas drifted: {sequence_sizes}", file=sys.stderr)
            return 1
        part_record = manifest["parts"][0]
        offset = part_record.get("originOverlayOffsetPx", {})
        overlay = Image.open(output / part_record["originOverlay"]).convert("RGBA")
        marker_x = round(part_record["localOriginPx"]["x"]) + int(offset.get("x", 0))
        marker_y = round(part_record["localOriginPx"]["y"]) + int(offset.get("y", 0))
        if offset.get("x", 0) <= 0 or offset.get("y", 0) <= 0 or overlay.getpixel((marker_x, marker_y))[3] == 0:
            print("ERROR: out-of-canvas origin marker was not preserved", file=sys.stderr)
            return 1

        stale_config = dict(config)
        stale_config["source"] = {**config["source"], "rootCharacterId": 100}
        stale_path = temp / "stale-config.json"
        stale_path.write_text(json.dumps(stale_config), encoding="utf-8")
        stale = subprocess.run(
            [sys.executable, str(BUILDER), "--config", str(stale_path), "--check-only"],
            text=True,
            capture_output=True,
            encoding="utf-8",
            env=CHILD_ENV,
        )
        if stale.returncode == 0 or "root.characterId" not in stale.stderr:
            print("ERROR: stale export manifest was accepted", file=sys.stderr)
            return 1

        unsafe_config = dict(config)
        unsafe_config["outputDir"] = str(REPO_ROOT)
        unsafe_path = temp / "unsafe-config.json"
        unsafe_path.write_text(json.dumps(unsafe_config), encoding="utf-8")
        repo_readme = REPO_ROOT / "README.md"
        unsafe = subprocess.run(
            [sys.executable, str(BUILDER), "--config", str(unsafe_path)],
            text=True,
            capture_output=True,
            encoding="utf-8",
            env=CHILD_ENV,
        )
        if unsafe.returncode == 0 or not repo_readme.exists() or "outputDir 必须位于" not in unsafe.stderr:
            print("ERROR: unsafe outputDir was not rejected", file=sys.stderr)
            return 1

        clipped_config = dict(config)
        clipped_config["ignoreTopFraction"] = 0.5
        clipped_path = temp / "clipped-config.json"
        clipped_path.write_text(json.dumps(clipped_config), encoding="utf-8")
        clipped = subprocess.run(
            [sys.executable, str(BUILDER), "--config", str(clipped_path)],
            text=True,
            capture_output=True,
            encoding="utf-8",
            env=CHILD_ENV,
        )
        if clipped.returncode == 0 or "穿过非透明内容" not in clipped.stderr:
            print("ERROR: destructive alpha cutoff was not rejected", file=sys.stderr)
            return 1

        preview_source = Image.new("RGBA", (80, 120), (0, 0, 0, 0))
        ImageDraw.Draw(preview_source).rounded_rectangle((0, 0, 79, 119), radius=12, fill=(80, 80, 80, 255))
        preview_concept = Image.new("RGBA", (220, 100), (0, 0, 0, 0))
        ImageDraw.Draw(preview_concept).rounded_rectangle((10, 10, 210, 90), radius=18, fill=(190, 40, 30, 255))
        fit_preview, fit_metrics = retarget_component(preview_concept, preview_source, "fit")
        masked_preview, masked_metrics = retarget_component(preview_concept, preview_source, "masked")
        if fit_preview.size != preview_source.size or masked_preview.size != preview_source.size:
            print("ERROR: dressup preview retarget changed the source canvas", file=sys.stderr)
            return 1
        if masked_preview.getchannel("A").tobytes() != preview_source.getchannel("A").tobytes():
            print("ERROR: masked dressup preview did not restore the source alpha", file=sys.stderr)
            return 1
        if (
            fit_metrics["aspectDriftPercent"] <= 0
            or fit_metrics["retargetSize"][1] >= preview_source.height
            or masked_metrics["retargetSize"][0] < preview_source.width
            or masked_metrics["retargetSize"][1] < preview_source.height
        ):
            print("ERROR: dressup preview retarget metrics are invalid", file=sys.stderr)
            return 1

        acceptance_artifact = temp / "battle-acceptance.png"
        Image.new("RGBA", (64, 64), (20, 30, 40, 255)).save(acceptance_artifact)
        skin_keys = [f"skin-key-{index:02d}" for index in range(REQUIRED_UNIQUE_SKINS)]
        override_keys = [f"skins/{index:02d}.png" for index in range(REQUIRED_UNIQUE_SKINS)]
        equipment = {
            "head": "head",
            "upper": "upper",
            "lower": "lower",
            "hands": "hands",
            "feet": "feet",
        }
        battle_preset = {
            "gender": "男",
            "rig": "battle",
            "equipment": equipment,
            "componentSkinKeysByGender": {"男": skin_keys},
            "rigReuseConstraints": {
                "uniqueSkinKeysPerGender": REQUIRED_UNIQUE_SKINS,
                "holderPlacementsPerPose": REQUIRED_COMPONENT_PLACEMENTS,
                "verifiedStateLabels": list(REQUIRED_BATTLE_STATES),
            },
        }
        component_metrics = [
            {"skinKey": skin_key, "overrideKey": override_key}
            for skin_key, override_key in zip(skin_keys, override_keys)
        ]
        state_records = []
        for state in REQUIRED_BATTLE_STATES:
            harness = {}
            for mode in ("baseline", "fit", "masked"):
                harness[mode] = {
                    "probe": {"width": 64, "height": 64, "alphaPixels": 4096},
                    "status": {
                        "rig": "battle",
                        "stateLabel": state,
                        "gender": "男",
                        "equipment": equipment,
                        "missing": 0,
                        "keyMap": {f"field-{index:02d}": key for index, key in enumerate(skin_keys)},
                    },
                    "skinOverrides": (
                        {"count": 0, "hits": {}, "missing": []}
                        if mode == "baseline"
                        else {
                            "count": REQUIRED_UNIQUE_SKINS,
                            "hits": {key: 1 for key in override_keys},
                            "missing": [],
                        }
                    ),
                }
            state_records.append(
                {
                    "stateLabel": state,
                    "captures": {mode: str(acceptance_artifact) for mode in ("baseline", "fit", "masked")},
                    "harness": harness,
                    "sheet": str(acceptance_artifact),
                }
            )
        semantic_gate = {
            "passed": True,
            "reviewer": "smoke-test",
            "checks": [{"component": "fixture", "passed": True}],
        }
        acceptance = evaluate_battle_rig_acceptance(
            battle_preset,
            component_metrics,
            state_records,
            acceptance_artifact,
            semantic_gate,
        )
        if not acceptance["passed"]:
            print(f"ERROR: valid battle-rig acceptance failed: {acceptance['failures']}", file=sys.stderr)
            return 1

        broken_records = json.loads(json.dumps(state_records, ensure_ascii=False))
        broken_records[0]["harness"]["fit"]["skinOverrides"]["hits"].pop(override_keys[0])
        broken_acceptance = evaluate_battle_rig_acceptance(
            battle_preset,
            component_metrics,
            broken_records[:-1],
            acceptance_artifact,
            semantic_gate,
        )
        if broken_acceptance["passed"] or not any(
            "override hit set" in failure for failure in broken_acceptance["failures"]
        ) or not any("six battle states" in failure for failure in broken_acceptance["failures"]):
            print("ERROR: broken battle-rig acceptance was not rejected", file=sys.stderr)
            return 1

        missing_semantic_acceptance = evaluate_battle_rig_acceptance(
            battle_preset,
            component_metrics,
            state_records,
            acceptance_artifact,
            None,
        )
        if missing_semantic_acceptance["passed"] or not any(
            "semanticGate" in failure for failure in missing_semantic_acceptance["failures"]
        ):
            print("ERROR: missing semantic gate was not rejected", file=sys.stderr)
            return 1
    print("OK: monster-reskin-pipeline smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
