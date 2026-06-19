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
REQUIRED_ATTACK_MODE_VARIANT_KEY = "枪-手枪-极品UZI战术版"
REQUIRED_ITEM_HELMET_FLAGS = {
    "圣诞帽": True,
    "剑圣头部装甲": True,
    "锐刻幻影夜视仪": False,
}
BATTLE_STATES = ("空手站立", "长枪站立", "手枪站立", "手枪2站立", "双枪站立", "兵器站立")
BATTLE_REQUIRED_FIELDS = {
    "空手站立": ("身体", "上臂", "左下臂", "左手", "右手", "屁股", "左大腿", "右大腿", "小腿", "脚", "脸型", "发型", "面具"),
    "长枪站立": ("身体", "上臂", "左下臂", "左手", "右手", "屁股", "左大腿", "右大腿", "小腿", "脚", "脸型", "发型", "面具", "长枪_装扮"),
    "手枪站立": ("身体", "上臂", "左下臂", "左手", "右手", "屁股", "左大腿", "右大腿", "小腿", "脚", "脸型", "发型", "面具", "手枪_装扮"),
    "手枪2站立": ("身体", "上臂", "左下臂", "左手", "右手", "屁股", "左大腿", "右大腿", "小腿", "脚", "脸型", "发型", "面具", "手枪2_装扮"),
    "双枪站立": ("身体", "上臂", "左下臂", "左手", "右手", "屁股", "左大腿", "右大腿", "小腿", "脚", "脸型", "发型", "面具", "手枪_装扮", "手枪2_装扮"),
    "兵器站立": ("身体", "上臂", "左下臂", "左手", "右手", "屁股", "左大腿", "右大腿", "小腿", "脚", "脸型", "发型", "面具", "刀_装扮"),
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def frame_key(frame: dict[str, Any]) -> tuple[Any, ...]:
    return tuple(frame.get(key) for key in DRESSUP_IDENTITY_KEYS)


def export_asset_identity_for_test(entry: dict[str, Any]) -> tuple[Any, ...]:
    asset = entry.get("asset") or {}
    return (
        asset.get("swf") or "",
        asset.get("symbolName") or "",
        bool(asset.get("conflict")),
    )


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


def is_local_uri(uri: str) -> bool:
    return bool(uri) and not uri.startswith(("http:", "https:", "data:", "blob:", "/"))


def entry_frame_uris(entry: dict[str, Any], owner: str) -> set[str]:
    uris: set[str] = set()
    for _frame_owner, frames, _is_timeline in frame_lists_from_entry(entry, owner):
        for frame in frames:
            uri = frame.get("uri")
            if isinstance(uri, str) and is_local_uri(uri):
                uris.add(uri)
    for variant_name, variant in (entry.get("runtimeVariants") or {}).items():
        if isinstance(variant, dict):
            uris.update(entry_frame_uris(variant, f"{owner}.runtimeVariants[{variant_name}]"))
    for layer_owner, layer in walk_layers(nested_layers(entry), f"{owner}.nestedAnimation"):
        for _frame_owner, frames, _is_timeline in frame_lists_from_entry(layer, layer_owner):
            for frame in frames:
                uri = frame.get("uri")
                if isinstance(uri, str) and is_local_uri(uri):
                    uris.add(uri)
    return uris


def iter_basic_entries(manifest: dict[str, Any]) -> Iterable[dict[str, Any]]:
    for gender_data in ((manifest.get("rig") or {}).get("genders") or {}).values():
        for holder in gender_data.get("holders") or []:
            basic = holder.get("basic") or {}
            if basic:
                yield basic
    for rig in (manifest.get("rigs") or {}).values():
        for gender_data in (rig.get("genders") or {}).values():
            for state in (gender_data.get("states") or {}).values():
                for holder in state.get("holders") or []:
                    basic = holder.get("basic") or {}
                    if basic:
                        yield basic


def referenced_skin_pngs(manifest: dict[str, Any]) -> set[str]:
    uris: set[str] = set()
    for skin_key, skin in (manifest.get("skinKeys") or {}).items():
        uris.update(entry_frame_uris(skin, f"skinKeys[{skin_key}]"))
    for basic in iter_basic_entries(manifest):
        uris.update(entry_frame_uris(basic, "basic"))
    return {uri for uri in uris if uri.startswith("skins/") and Path(uri).suffix.lower() == ".png"}


def is_exportable_skin(skin: dict[str, Any]) -> bool:
    asset = skin.get("asset") or {}
    return bool(skin.get("covered") and asset and not asset.get("conflict"))


def exportable_skins_missing_frames(manifest: dict[str, Any]) -> list[str]:
    missing: list[str] = []
    for skin_key, skin in (manifest.get("skinKeys") or {}).items():
        if is_exportable_skin(skin) and (not skin.get("export") or not skin.get("frames")):
            missing.append(skin_key)
    return missing


def orphan_skin_pngs(manifest_dir: Path, manifest: dict[str, Any]) -> list[str]:
    skin_dir = manifest_dir / "skins"
    if not skin_dir.exists():
        return []
    referenced = referenced_skin_pngs(manifest)
    actual = {path.relative_to(manifest_dir).as_posix() for path in skin_dir.glob("*.png")}
    return sorted(actual - referenced)


def assert_export_completeness(manifest: dict[str, Any], failures: list[str]) -> list[str]:
    missing = exportable_skins_missing_frames(manifest)
    for skin_key in missing[:20]:
        failures.append(f"{skin_key} covered asset missing export/frames")
    if len(missing) > 20:
        failures.append(f"{len(missing) - 20} additional covered assets missing export/frames")
    return missing


def assert_no_orphan_skin_pngs(manifest_dir: Path, manifest: dict[str, Any], failures: list[str]) -> list[str]:
    orphaned = orphan_skin_pngs(manifest_dir, manifest)
    for uri in orphaned[:20]:
        failures.append(f"unreferenced skin png: {uri}")
    if len(orphaned) > 20:
        failures.append(f"{len(orphaned) - 20} additional unreferenced skin pngs")
    return orphaned


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


def assert_required_item_helmet_flags(manifest: dict[str, Any], failures: list[str]) -> None:
    items = manifest.get("items") or {}
    for item_name, expected in REQUIRED_ITEM_HELMET_FLAGS.items():
        item = items.get(item_name)
        if not item:
            failures.append(f"missing required item for helmet flag check: {item_name}")
            continue
        if item.get("helmet") is not expected:
            failures.append(f"{item_name} helmet should be {expected}")


def assert_battle_rig(manifest: dict[str, Any], failures: list[str]) -> None:
    battle = ((manifest.get("rigs") or {}).get("battle") or {})
    if not battle:
        failures.append("manifest.rigs.battle missing")
        return
    if battle.get("auditErrors"):
        failures.append(f"battle rig should have no auditErrors: {battle.get('auditErrors')[:3]}")
    if tuple(battle.get("states") or []) != BATTLE_STATES:
        failures.append(f"battle rig states mismatch: {battle.get('states')}")

    for gender in ("男", "女"):
        gender_data = (battle.get("genders") or {}).get(gender)
        if not gender_data:
            failures.append(f"battle rig missing gender {gender}")
            continue
        states = gender_data.get("states") or {}
        for state_label in BATTLE_STATES:
            state = states.get(state_label)
            if not state:
                failures.append(f"battle rig {gender}/{state_label} missing")
                continue
            holders = state.get("holders") or []
            if not holders:
                failures.append(f"battle rig {gender}/{state_label} has no holders")
                continue
            field_counts: dict[str, int] = {}
            for holder in holders:
                field = holder.get("field")
                field_counts[field] = field_counts.get(field, 0) + 1
                if holder.get("rig") != "battle":
                    failures.append(f"battle holder {gender}/{state_label}/{field} missing rig marker")
                matrix = holder.get("matrix") or {}
                for key in ("a", "b", "c", "d", "tx", "ty"):
                    if not isinstance(matrix.get(key), (int, float)):
                        failures.append(f"battle holder {gender}/{state_label}/{field} missing numeric matrix.{key}")
            for required in BATTLE_REQUIRED_FIELDS[state_label]:
                if field_counts.get(required, 0) <= 0:
                    failures.append(f"battle rig {gender}/{state_label} missing field {required}")


def assert_attack_mode_runtime_variant(manifest: dict[str, Any], failures: list[str]) -> None:
    entry = (manifest.get("skinKeys") or {}).get(REQUIRED_ATTACK_MODE_VARIANT_KEY)
    if not entry:
        failures.append(f"missing required attack-mode variant skinKey: {REQUIRED_ATTACK_MODE_VARIANT_KEY}")
        return
    visibility = entry.get("conditionalVisibility") or {}
    if visibility.get("property") != "攻击模式":
        failures.append(f"{REQUIRED_ATTACK_MODE_VARIANT_KEY} conditionalVisibility.property should be 攻击模式")
    if visibility.get("hiddenVariant") != "neutral":
        failures.append(f"{REQUIRED_ATTACK_MODE_VARIANT_KEY} hiddenVariant should be neutral")
    expected_modes = {"手枪", "手枪2", "双枪"}
    if set(visibility.get("visibleWhen") or []) != expected_modes:
        failures.append(f"{REQUIRED_ATTACK_MODE_VARIANT_KEY} visibleWhen mismatch: {visibility.get('visibleWhen')}")
    neutral = ((entry.get("runtimeVariants") or {}).get("neutral") or {})
    if not neutral.get("export") or not neutral.get("frames"):
        failures.append(f"{REQUIRED_ATTACK_MODE_VARIANT_KEY} missing runtimeVariants.neutral export/frames")
        return
    main_width = int((entry.get("export") or {}).get("width") or 0)
    neutral_width = int((neutral.get("export") or {}).get("width") or 0)
    if not main_width or not neutral_width or neutral_width >= main_width:
        failures.append(
            f"{REQUIRED_ATTACK_MODE_VARIANT_KEY} neutral variant should be narrower than active export: "
            f"{neutral_width} >= {main_width}"
        )


def assert_audit_references(
    manifest: dict[str, Any],
    failures: list[str],
    owner: str,
    audit_entries: dict[str, Any],
    require_merc_usage: bool,
) -> None:
    items = manifest.get("items") or {}
    refs_with_merc_usage = 0
    for skin_key, audit_entry in audit_entries.items():
        references = audit_entry.get("references") or []
        if not references:
            failures.append(f"{skin_key} missingSourceAudit entry should include references")
            continue
        for ref in references:
            item_name = ref.get("item")
            item = items.get(item_name)
            if not item:
                failures.append(f"{skin_key} reference item not found in manifest: {item_name}")
                continue
            if ref.get("sourceFile") != item.get("sourceFile"):
                failures.append(f"{skin_key}/{item_name} reference sourceFile mismatch")
            if ref.get("use") != item.get("use"):
                failures.append(f"{skin_key}/{item_name} reference use mismatch")
            for field_ref in ref.get("fields") or []:
                gender = field_ref.get("gender")
                field = field_ref.get("field")
                if gender == "<dressup>":
                    if item.get("dressup") != skin_key:
                        failures.append(f"{skin_key}/{item_name} dressup reference mismatch")
                    continue
                fields = (item.get("fieldsByGender") or {}).get(gender) or {}
                if fields.get(field) != skin_key:
                    failures.append(f"{skin_key}/{item_name}/{gender}/{field} reference mismatch")
            merc_usage_count = ref.get("mercUsageCount")
            if not isinstance(merc_usage_count, int):
                failures.append(f"{skin_key}/{item_name} mercUsageCount should be int")
            if merc_usage_count:
                refs_with_merc_usage += 1
            if not isinstance(ref.get("mercUsageSamples") or [], list):
                failures.append(f"{skin_key}/{item_name} mercUsageSamples should be list")
    if require_merc_usage and refs_with_merc_usage <= 0:
        failures.append(f"{owner} references should include at least one merc usage sample")


def assert_missing_source_references(manifest: dict[str, Any], report: dict[str, Any], failures: list[str]) -> None:
    audit_entries = ((report.get("missingSourceAudit") or {}).get("entries") or {})
    missing_count = int((report.get("counts") or {}).get("missingSkinKeys") or 0)
    if missing_count > 0 and not audit_entries:
        failures.append("report missingSourceAudit.entries should not be empty while missingSkinKeys > 0")
        return
    assert_audit_references(manifest, failures, "missingSourceAudit", audit_entries, bool(audit_entries))


def assert_compat_alias_audit(manifest: dict[str, Any], report: dict[str, Any], failures: list[str]) -> None:
    skin_keys = manifest.get("skinKeys") or {}
    alias_skins = {key: skin for key, skin in skin_keys.items() if skin.get("compatAlias")}
    audit_entries = ((report.get("compatAliasAudit") or {}).get("entries") or {})
    if len(audit_entries) != len(alias_skins):
        failures.append(f"compatAliasAudit entry count mismatch: {len(audit_entries)} != {len(alias_skins)}")
    for skin_key, skin in alias_skins.items():
        alias = skin.get("compatAlias") or {}
        source_key = alias.get("sourceKey")
        source_skin = skin_keys.get(source_key)
        if not source_skin:
            failures.append(f"{skin_key} compatAlias source missing: {source_key}")
            continue
        if not skin.get("covered") or not skin.get("asset"):
            failures.append(f"{skin_key} compatAlias should be covered")
        if not skin.get("export"):
            failures.append(f"{skin_key} compatAlias should preserve export metadata from {source_key}")
        if export_asset_identity_for_test(skin) != export_asset_identity_for_test(source_skin):
            failures.append(f"{skin_key} compatAlias asset should match source {source_key}")
        audit_entry = audit_entries.get(skin_key)
        if not audit_entry:
            failures.append(f"{skin_key} missing compatAliasAudit entry")
            continue
        if audit_entry.get("sourceKey") != source_key:
            failures.append(f"{skin_key} compatAliasAudit sourceKey mismatch")
    assert_audit_references(manifest, failures, "compatAliasAudit", audit_entries, bool(audit_entries))


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
        for variant_name, variant in (skin.get("runtimeVariants") or {}).items():
            variant_owner = f"skinKeys[{skin_key}].runtimeVariants[{variant_name}]"
            for owner, frames, is_timeline in frame_lists_from_entry(variant, variant_owner):
                assert_frame_list(manifest_dir, failures, owner, frames, is_timeline)
            assert_compression_contract(failures, variant_owner, variant)
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

    for rig_name, rig in (manifest.get("rigs") or {}).items():
        if rig_name == "dialogue":
            continue
        for gender, gender_data in (rig.get("genders") or {}).items():
            for state_label, state in (gender_data.get("states") or {}).items():
                for holder in state.get("holders") or []:
                    basic = holder.get("basic") or {}
                    if not basic:
                        continue
                    owner_prefix = f"rigs[{rig_name}].genders[{gender}].states[{state_label}].holders[{holder.get('field')}].basic"
                    for owner, frames, is_timeline in frame_lists_from_entry(basic, owner_prefix):
                        assert_frame_list(manifest_dir, failures, owner, frames, is_timeline)
                    assert_compression_contract(failures, owner_prefix, basic)

    assert_a_corps_body(manifest, failures)
    assert_required_appearance_keys(manifest, failures)
    assert_required_item_helmet_flags(manifest, failures)
    assert_battle_rig(manifest, failures)
    assert_attack_mode_runtime_variant(manifest, failures)
    assert_missing_source_references(manifest, report, failures)
    assert_compat_alias_audit(manifest, report, failures)
    missing_exportable = assert_export_completeness(manifest, failures)
    orphaned_skin_pngs = assert_no_orphan_skin_pngs(manifest_dir, manifest, failures)

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
        "exportableMissingExport": len(missing_exportable),
        "orphanSkinPngs": len(orphaned_skin_pngs),
        "reportTimelineCompressedFrameRefs": counts.get("timelineCompressedFrameRefs"),
        "failures": failures[:20],
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
