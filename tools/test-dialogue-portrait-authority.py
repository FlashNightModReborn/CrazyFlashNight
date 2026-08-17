#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
BAKER_PATH = ROOT / "tools" / "bake-dialogue-portraits.py"
POLICY_PATH = ROOT / "tools" / "dialogue-portrait-source-review" / "authority-policy.json"
PRODUCTION_ASSET_ROOT = ROOT / "launcher" / "web" / "assets" / "dialogue-portraits"
EXPECTED_COLLISIONS = ["宝石线人", "丽丽丝", "格格巫", "迷之盔甲君", "酒保", "小F"]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_baker() -> Any:
    spec = importlib.util.spec_from_file_location("cf7_dialogue_portrait_baker", BAKER_PATH)
    require(spec is not None and spec.loader is not None, "cannot load dialogue portrait baker")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def entry(key: str, source: str) -> dict[str, Any]:
    return {
        "key": key,
        "aliases": [],
        "source": source,
        "sourcePath": f"fixture/{source}/{key}.swf",
        "defaultExpression": "普通",
        "expressions": {"普通": {"uri": f"{source}/{key}.png"}},
    }


def exercise_order(baker: Any, decisions: dict[str, str], sources: list[str]) -> None:
    manifest: dict[str, Any] = {"entries": {}, "aliases": {}}
    report: dict[str, Any] = {"sourceCollisions": []}
    for name in EXPECTED_COLLISIONS:
        for source in sources:
            baker.append_entry(manifest, entry(name, source), decisions, report)
    baker.rebuild_aliases(manifest)
    require(
        all(manifest["entries"][name]["source"] == "external-swf" for name in EXPECTED_COLLISIONS),
        f"authority selection changed with append order {sources}",
    )
    require(len(report["sourceCollisions"]) == len(EXPECTED_COLLISIONS), "collision report count mismatch")
    require(
        all(item["selectedSource"] == "external-swf" for item in report["sourceCollisions"]),
        "collision report selected source mismatch",
    )
    baker.validate_baked_authority(manifest, report, EXPECTED_COLLISIONS, decisions)


def exercise_asset_filters(baker: Any) -> None:
    with tempfile.TemporaryDirectory(prefix="cf7-dialogue-asset-filter-") as temp_dir:
        root = Path(temp_dir)
        baseline_root = root / "baseline"
        output_root = root / "output"
        changed_output_root = root / "changed-output"
        uri = f"internal/p_fixture/{baker.stable_file('普通')}"
        baseline_path = baseline_root / uri
        baseline_path.parent.mkdir(parents=True)
        baseline_image = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
        baseline_image.paste((24, 96, 180, 255), (1, 1, 3, 3))
        baseline_image.save(baseline_path)
        baseline_manifest = {
            "schema": baker.SCHEMA,
            "entries": {
                "fixture": {
                    "source": "dialogue-ui-sprite",
                    "expressions": {
                        "普通": {
                            "uri": uri,
                            "width": 4,
                            "height": 4,
                            "frame": 1,
                            "bounds": {"x": 1, "y": 1, "width": 2, "height": 2},
                        }
                    },
                }
            },
        }
        (baseline_root / "manifest.json").write_text(
            json.dumps(baseline_manifest, ensure_ascii=False),
            encoding="utf-8",
        )
        semantic_baseline = baker.load_semantic_baseline(baseline_root)

        candidate_path = root / "1.png"
        candidate_image = Image.new("RGBA", (6, 4), (0, 0, 0, 0))
        candidate_image.paste((24, 96, 180, 255), (1, 1, 3, 3))
        candidate_image.save(candidate_path)
        semantic_noops: list[dict[str, Any]] = []
        reused_asset = baker.copy_asset(
            candidate_path,
            output_root,
            "internal/p_fixture",
            "普通",
            source_kind="dialogue-ui-sprite",
            semantic_baseline=semantic_baseline,
            semantic_noop_assets=semantic_noops,
        )
        require((output_root / uri).read_bytes() == baseline_path.read_bytes(), "transparent canvas no-op must reuse baseline PNG")
        require(reused_asset["width"] == 4 and reused_asset["height"] == 4, "reused PNG metadata must match baseline bytes")
        require(len(semantic_noops) == 1, "transparent canvas no-op must be reported")

        changed_image = candidate_image.copy()
        changed_image.putpixel((2, 2), (220, 32, 16, 255))
        changed_image.save(candidate_path)
        changed_noops: list[dict[str, Any]] = []
        changed_asset = baker.copy_asset(
            candidate_path,
            changed_output_root,
            "internal/p_fixture",
            "普通",
            source_kind="dialogue-ui-sprite",
            semantic_baseline=semantic_baseline,
            semantic_noop_assets=changed_noops,
        )
        require((changed_output_root / uri).read_bytes() != baseline_path.read_bytes(), "visible pixel change must not reuse baseline PNG")
        require(changed_asset["width"] == 6 and changed_noops == [], "visible pixel change must remain a fresh asset")

        dead_path = output_root / "internal/dead.png"
        dead_path.parent.mkdir(parents=True, exist_ok=True)
        candidate_image.save(dead_path)
        closure_manifest = {
            "entries": {
                "fixture": {
                    "expressions": {"普通": reused_asset},
                }
            }
        }
        review_candidate_root = root / "review-candidates"
        referenced, pruned = baker.enforce_asset_closure(
            output_root,
            closure_manifest,
            review_candidate_root,
        )
        require(referenced == {uri}, "asset closure referenced set mismatch")
        require(pruned == ["internal/dead.png"] and not dead_path.exists(), "unreferenced PNG must be pruned")
        require(
            (review_candidate_root / "internal/dead.png").is_file(),
            "pruned source candidate must remain available outside the production closure",
        )
        require(
            {path.relative_to(output_root).as_posix() for path in output_root.rglob("*.png")} == referenced,
            "asset closure disk set must equal manifest URI set",
        )


def main() -> None:
    baker = load_baker()
    exercise_asset_filters(baker)
    with tempfile.TemporaryDirectory(prefix="cf7-dialogue-export-id-") as temp_dir:
        fixture = Path(temp_dir) / "source.xml"
        fixture.write_text(
            """<swf><item type="ExportAssetsTag"><tags><item>981</item></tags>"""
            """<names><item>对话框肖像</item></names></item></swf>""",
            encoding="utf-8",
        )
        require(
            baker.exported_asset_id_from_swf_xml(fixture, "对话框肖像") == 981,
            "exported sprite id must be resolved from the current SWF",
        )
    policy, decisions, digest = baker.load_authority_policy(POLICY_PATH)
    collisions = baker.discover_source_collisions(ROOT)
    require(policy["schema"] == baker.AUTHORITY_POLICY_SCHEMA, "policy schema mismatch")
    require(len(digest) == 64, "policy digest must be sha256")
    require(collisions == EXPECTED_COLLISIONS, f"unexpected collision set: {collisions}")
    require(set(decisions) == set(EXPECTED_COLLISIONS), "policy must cover exactly the current collisions")
    require(set(decisions.values()) == {"external-swf"}, "reviewed authority must be external-swf")
    baker.validate_authority_policy_coverage(decisions, collisions, require_exact=True)
    exercise_order(baker, decisions, ["external-swf", "dialogue-ui-sprite"])
    exercise_order(baker, decisions, ["dialogue-ui-sprite", "external-swf"])

    production_manifest = json.loads((PRODUCTION_ASSET_ROOT / "manifest.json").read_text(encoding="utf-8"))
    production_report = json.loads((PRODUCTION_ASSET_ROOT / "report.json").read_text(encoding="utf-8"))
    baker.validate_baked_authority(production_manifest, production_report, collisions, decisions)
    require(production_report["missingExternalSwf"] == [], "production report has missing external SWFs")
    require(production_report["internalPortraitSpriteId"] > 0, "production report lacks dynamic internal sprite id")
    require(
        production_manifest["sourceAuthority"]["policySha256"] == digest,
        "production manifest authority policy digest mismatch",
    )
    require(
        production_report["sourceAuthority"]["policySha256"] == digest,
        "production report authority policy digest mismatch",
    )
    expected_entries = (
        production_report["externalEntries"]
        + production_report["internalEntries"]
        - len(collisions)
    )
    require(len(production_manifest["entries"]) == expected_entries, "production manifest entry count mismatch")
    assets = [
        expression
        for portrait in production_manifest["entries"].values()
        for expression in portrait["expressions"].values()
    ]
    require(assets, "production manifest has no portrait assets")
    bounded_assets = [asset for asset in assets if "bounds" in asset]
    bounds_coverage = len(bounded_assets) / len(assets)
    require(bounds_coverage >= 0.99, "production manifest bounds coverage must remain at least 99%")
    require(
        all((PRODUCTION_ASSET_ROOT / asset["uri"]).is_file() for asset in assets),
        "production manifest references a missing PNG",
    )
    referenced_assets = {asset["uri"] for asset in assets}
    on_disk_assets = {
        path.relative_to(PRODUCTION_ASSET_ROOT).as_posix()
        for path in PRODUCTION_ASSET_ROOT.rglob("*.png")
    }
    require(on_disk_assets == referenced_assets, "production PNG set must exactly equal manifest URI set")
    asset_closure = production_report.get("assetClosure") or {}
    require(
        asset_closure.get("referencedPngs") == len(referenced_assets)
        and asset_closure.get("onDiskPngs") == len(on_disk_assets),
        "production asset closure report mismatch",
    )

    try:
        baker.validate_authority_policy_coverage(
            {key: value for key, value in decisions.items() if key != "宝石线人"},
            collisions,
            require_exact=True,
        )
    except RuntimeError as error:
        require("宝石线人" in str(error), "missing authority error lost identity")
    else:
        raise AssertionError("missing authority decision must fail closed")

    manifest: dict[str, Any] = {"entries": {}, "aliases": {}}
    report: dict[str, Any] = {"sourceCollisions": []}
    baker.append_entry(manifest, entry("未裁决", "external-swf"), decisions, report)
    try:
        baker.append_entry(manifest, entry("未裁决", "dialogue-ui-sprite"), decisions, report)
    except RuntimeError as error:
        require("Unreviewed" in str(error), "unreviewed collision error mismatch")
    else:
        raise AssertionError("unreviewed collision must fail closed")

    try:
        baker.validate_baked_authority(
            {"entries": {"宝石线人": entry("宝石线人", "external-swf")}},
            {"sourceCollisions": []},
            ["宝石线人"],
            decisions,
        )
    except RuntimeError as error:
        require("closure mismatch" in str(error), "missing baked collision postcondition error mismatch")
    else:
        raise AssertionError("missing baked collision evidence must fail closed")

    print(
        json.dumps(
            {
                "status": "dialogue_portrait_authority_verified",
                "collisions": len(collisions),
                "selectedSource": "external-swf",
                "appendOrderIndependent": True,
                "unreviewedCollisionFailsClosed": True,
                "dynamicSpriteIdResolution": True,
                "bakedCollisionClosureRequired": True,
                "transparentCanvasNoopReuse": True,
                "exactAssetClosure": True,
                "productionManifestVerified": True,
                "productionEntries": len(production_manifest["entries"]),
                "productionAssets": len(assets),
                "boundsCoverage": f"{len(bounded_assets)}/{len(assets)}",
                "policyDigest": digest,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
