#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from asset_timeline_export import compressed_timeline_entries


DRESSUP_TIMELINE_IDENTITY_KEYS = ("uri", "width", "height", "originX", "originY")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Normalize an existing dressup manifest by adding timelineFrames/durationFrames "
            "for already-exported frame lists without re-running FFDec."
        )
    )
    parser.add_argument(
        "--manifest",
        default="launcher/web/assets/dressup/manifest.json",
        help="Dressup manifest path.",
    )
    parser.add_argument(
        "--report",
        default="launcher/web/assets/dressup/report.json",
        help="Dressup report path to update with timeline compression counts.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print summary without writing files.")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def nested_layers(entry: dict[str, Any]) -> list[dict[str, Any]]:
    export = entry.get("export") or {}
    nested = export.get("nestedAnimation") or entry.get("nestedAnimation") or {}
    return nested.get("layers") or []


def sync_export_timeline_metadata(entry: dict[str, Any], frame_count: int, timeline_count: int) -> None:
    export = entry.get("export")
    if not isinstance(export, dict):
        return
    if timeline_count < frame_count:
        export["logicalFrameCount"] = frame_count
        export["timelineFrameCount"] = timeline_count
        export["compressedFrameRefs"] = frame_count - timeline_count
        return
    for key in ("logicalFrameCount", "timelineFrameCount", "compressedFrameRefs"):
        export.pop(key, None)


def normalize_entry(entry: dict[str, Any], owner: str, export_report: dict[str, Any]) -> int:
    frames = entry.get("frames") or []
    changed = 0
    if frames:
        timeline = compressed_timeline_entries(
            frames,
            export_report,
            owner=owner,
            identity_keys=DRESSUP_TIMELINE_IDENTITY_KEYS,
        )
        old_timeline = entry.get("timelineFrames") or []
        if len(timeline) < len(frames):
            if old_timeline != timeline:
                changed += 1
            entry["timelineFrames"] = timeline
        else:
            if "timelineFrames" in entry:
                changed += 1
            entry.pop("timelineFrames", None)
        sync_export_timeline_metadata(entry, len(frames), len(timeline))

    for index, layer in enumerate(nested_layers(entry)):
        changed += normalize_entry(layer, f"{owner}.layers[{index}]#{layer.get('characterId', '?')}", export_report)
    return changed


def normalize_manifest(manifest: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    export_report: dict[str, Any] = {
        "timelineLogicalFrames": 0,
        "timelineFrameEntries": 0,
        "timelineCompressedFrameRefs": 0,
        "timelineCompressionSamples": [],
    }
    changed = 0

    for skin_key, skin in (manifest.get("skinKeys") or {}).items():
        changed += normalize_entry(skin, f"skinKeys[{skin_key}]", export_report)

    for gender, gender_data in ((manifest.get("rig") or {}).get("genders") or {}).items():
        for holder in gender_data.get("holders") or []:
            basic = holder.get("basic")
            if isinstance(basic, dict):
                owner = f"rig.genders[{gender}].holders[{holder.get('field')}].basic"
                changed += normalize_entry(basic, owner, export_report)

    export_report["timelineCompressionSamples"] = export_report["timelineCompressionSamples"][:200]
    return changed, export_report


def update_report(report: dict[str, Any], export_report: dict[str, Any]) -> None:
    counts = report.setdefault("counts", {})
    asset_export = report.setdefault("assetExport", {})
    for key, value in export_report.items():
        if key == "timelineCompressionSamples":
            asset_export[key] = value
            continue
        counts[key] = value
        asset_export[key] = value


def main() -> int:
    args = parse_args()
    project_root = Path(__file__).resolve().parents[1]
    manifest_path = (project_root / args.manifest).resolve()
    report_path = (project_root / args.report).resolve()
    manifest = read_json(manifest_path)
    report = read_json(report_path) if report_path.exists() else {"counts": {}}
    changed, export_report = normalize_manifest(manifest)
    update_report(report, export_report)
    summary = {
        "manifest": str(manifest_path),
        "report": str(report_path),
        "changedEntries": changed,
        "timelineLogicalFrames": export_report["timelineLogicalFrames"],
        "timelineFrameEntries": export_report["timelineFrameEntries"],
        "timelineCompressedFrameRefs": export_report["timelineCompressedFrameRefs"],
        "timelineCompressionSamples": export_report["timelineCompressionSamples"][:10],
        "dryRun": args.dry_run,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if not args.dry_run:
        write_json(manifest_path, manifest)
        write_json(report_path, report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
