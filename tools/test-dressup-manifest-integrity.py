#!/usr/bin/env python
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "launcher/web/assets/dressup/manifest.json"
REPORT_PATH = PROJECT_ROOT / "launcher/web/assets/dressup/report.json"
DRESSUP_IDENTITY_KEYS = ("uri", "width", "height", "originX", "originY")
A_CORPS_BODY_KEYS = (
    "男变装-A兵团精致战术背心身体",
    "女变装-A兵团精致战术背心身体",
)
REQUIRED_APPEARANCE_KEYS = (
    "男变装-基本脸型",
    "女变装-基本脸型",
    "发型-男式-黑韩式头",
    "枪-手枪-m9",
)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def frame_key(frame: dict[str, Any]) -> tuple[Any, ...]:
    return tuple(frame.get(key) for key in DRESSUP_IDENTITY_KEYS)


def is_compressible(frames: list[dict[str, Any]]) -> bool:
    return any(frame_key(left) == frame_key(right) for left, right in zip(frames, frames[1:]))


def distinct_keys(frames: list[dict[str, Any]]) -> set[tuple[Any, ...]]:
    return {frame_key(frame) for frame in frames}


def frame_lists_from_entry(entry: dict[str, Any], owner: str) -> Iterable[tuple[str, list[dict[str, Any]], bool]]:
    frames = entry.get("frames") or []
    if frames:
        yield owner + ".frames", frames, False
    timeline = entry.get("timelineFrames") or []
    if timeline:
        yield owner + ".timelineFrames", timeline, True

    export = entry.get("export") or {}
    export_frames = export.get("frames") or []
    if export_frames:
        yield owner + ".export.frames", export_frames, False
    export_timeline = export.get("timelineFrames") or []
    if export_timeline:
        yield owner + ".export.timelineFrames", export_timeline, True


def nested_layers(entry: dict[str, Any]) -> list[dict[str, Any]]:
    export = entry.get("export") or {}
    nested = export.get("nestedAnimation") or entry.get("nestedAnimation") or {}
    return nested.get("layers") or []


def walk_layers(layers: list[dict[str, Any]], owner: str) -> Iterable[tuple[str, dict[str, Any]]]:
    for index, layer in enumerate(layers):
        layer_owner = f"{owner}.layers[{index}]#{layer.get('characterId', '?')}"
        yield layer_owner, layer
        yield from walk_layers(nested_layers(layer), layer_owner)


def assert_frame_list(
    manifest_dir: Path,
    failures: list[str],
    owner: str,
    frames: list[dict[str, Any]],
    is_timeline: bool,
) -> None:
    seen_frame_numbers: set[int] = set()
    for index, frame in enumerate(frames, start=1):
        uri = frame.get("uri")
        if not uri:
            failures.append(f"{owner}[{index}] missing uri")
            continue
        if uri.startswith(("http:", "https:", "data:", "blob:", "/")):
            failures.append(f"{owner}[{index}] uses non-local uri: {uri}")
            continue
        if not (manifest_dir / uri).exists():
            failures.append(f"{owner}[{index}] missing file: {uri}")
        if Path(uri).suffix.lower() != ".png":
            failures.append(f"{owner}[{index}] is not png: {uri}")
        for key in ("width", "height", "originX", "originY"):
            if key not in frame:
                failures.append(f"{owner}[{index}] missing {key}")
        duplicate_of = frame.get("duplicateOfFrame")
        if not is_timeline and duplicate_of is not None and int(duplicate_of) not in seen_frame_numbers:
            failures.append(f"{owner}[{index}] duplicateOfFrame points forward/missing: {duplicate_of}")
        if not is_timeline and "frame" in frame:
            seen_frame_numbers.add(int(frame["frame"]))
        duration = int(frame.get("durationFrames") or frame.get("holdFrames") or 1)
        if duration <= 0:
            failures.append(f"{owner}[{index}] invalid durationFrames/holdFrames: {duration}")


def assert_compression_contract(failures: list[str], owner: str, entry: dict[str, Any]) -> None:
    frames = entry.get("frames") or []
    if not frames or not is_compressible(frames):
        return
    timeline = entry.get("timelineFrames") or []
    if not timeline:
        failures.append(f"{owner} is compressible but missing timelineFrames")
        return
    if len(timeline) >= len(frames):
        failures.append(f"{owner} timelineFrames did not shrink frames")
    if sum(int(frame.get("durationFrames") or frame.get("holdFrames") or 1) for frame in timeline) != len(frames):
        failures.append(f"{owner} timelineFrames duration does not match logical frame count")


def assert_a_corps_body(manifest: dict[str, Any], failures: list[str]) -> None:
    for key in A_CORPS_BODY_KEYS:
        entry = manifest.get("skinKeys", {}).get(key)
        if not entry:
            failures.append(f"missing sample skinKey: {key}")
            continue

        export = entry.get("export") or {}
        if export.get("playback") != "nested-animation":
            failures.append(f"{key} playback should be nested-animation, got {export.get('playback')}")
        if len(entry.get("frames") or []) > 1:
            failures.append(f"{key} parent timeline should be frozen to frame 1")

        nested = export.get("nestedAnimation") or {}
        if nested.get("strategy") != "direct-layered":
            failures.append(f"{key} nested strategy should be direct-layered")
        layers = nested.get("layers") or []
        if not layers:
            failures.append(f"{key} missing nestedAnimation.layers")
            continue

        animated_layers = []
        for owner, layer in walk_layers(layers, key):
            matrix = layer.get("matrix") or {}
            for field in ("a", "b", "c", "d", "tx", "ty"):
                if not isinstance(matrix.get(field), (int, float)):
                    failures.append(f"{owner} missing numeric matrix.{field}")
            frames = layer.get("frames") or []
            if len(frames) > 1 and len(distinct_keys(frames)) > 1:
                animated_layers.append((owner, layer))
            assert_compression_contract(failures, owner, layer)

        if not animated_layers:
            failures.append(f"{key} should keep at least one animated first-frame child layer")


def assert_required_appearance_keys(manifest: dict[str, Any], failures: list[str]) -> None:
    for key in REQUIRED_APPEARANCE_KEYS:
        entry = manifest.get("skinKeys", {}).get(key)
        if not entry:
            failures.append(f"missing required appearance/resource skinKey: {key}")
            continue
        if not entry.get("covered"):
            failures.append(f"{key} should be covered")
        if not entry.get("export"):
            failures.append(f"{key} should have export metadata")


def main() -> None:
    manifest = read_json(MANIFEST_PATH)
    report = read_json(REPORT_PATH) if REPORT_PATH.exists() else {}
    manifest_dir = MANIFEST_PATH.parent
    failures: list[str] = []

    counts = report.get("counts") or {}
    for key in ("metadataErrors", "timelineScriptErrors", "spriteGraphErrors", "nestedLayerUnsupportedDescendants"):
        if int(counts.get(key) or 0) != 0:
            failures.append(f"report counts.{key} should be 0, got {counts.get(key)}")

    for skin_key, skin in (manifest.get("skinKeys") or {}).items():
        for owner, frames, is_timeline in frame_lists_from_entry(skin, f"skinKeys[{skin_key}]"):
            assert_frame_list(manifest_dir, failures, owner, frames, is_timeline)
        assert_compression_contract(failures, f"skinKeys[{skin_key}]", skin)
        for owner, layer in walk_layers(nested_layers(skin), f"skinKeys[{skin_key}].nestedAnimation"):
            for frame_owner, frames, is_timeline in frame_lists_from_entry(layer, owner):
                assert_frame_list(manifest_dir, failures, frame_owner, frames, is_timeline)
            assert_compression_contract(failures, owner, layer)

    for gender, gender_data in ((manifest.get("rig") or {}).get("genders") or {}).items():
        for holder in gender_data.get("holders") or []:
            basic = holder.get("basic") or {}
            if not basic:
                continue
            owner_prefix = f"rig.genders[{gender}].holders[{holder.get('field')}].basic"
            for owner, frames, is_timeline in frame_lists_from_entry(basic, owner_prefix):
                assert_frame_list(manifest_dir, failures, owner, frames, is_timeline)
            assert_compression_contract(failures, owner_prefix, basic)

    assert_a_corps_body(manifest, failures)
    assert_required_appearance_keys(manifest, failures)

    layer_count = 0
    compressed_layer_count = 0
    for skin in (manifest.get("skinKeys") or {}).values():
        for _owner, layer in walk_layers(nested_layers(skin), "skin"):
            layer_count += 1
            if layer.get("timelineFrames"):
                compressed_layer_count += 1

    payload = {
        "skinKeys": len(manifest.get("skinKeys") or {}),
        "nestedLayers": layer_count,
        "compressedNestedLayers": compressed_layer_count,
        "reportTimelineCompressedFrameRefs": counts.get("timelineCompressedFrameRefs"),
        "failures": failures[:20],
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
