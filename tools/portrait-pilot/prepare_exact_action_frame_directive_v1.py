#!/usr/bin/env python3
"""Freeze an explicit human action-state frame directive into a verified review batch."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

from PIL import Image

import prepare_action_frame_reselection as action_base
from prepare_pilot import (
    FFDEC_EXPECTED_VERSION,
    ROOT,
    PilotError,
    artifact,
    compile_selected_frame_exporter,
    expanded_bbox,
    export_selected_sprite_frames,
    load_json,
    repo_rel,
    run_ffdec,
    sha256_bytes,
    stable_bytes,
    svg_canvas_size,
    verify_artifact_record,
    verify_digest_object,
    verify_ffdec,
    write_json,
)


DATA_SCHEMA = "cf7.enemy-portrait-frame-reselection-candidates.v1"
DECISION_SCHEMA = "cf7.enemy-portrait-frame-reselection-decisions.v1"
RECEIPT_SCHEMA = "cf7.enemy-portrait-frame-reselection-receipt.v1"
REVIEWER_FILES = [
    ROOT / "tools/portrait-pilot/prepare_exact_action_frame_directive_v1.py",
    ROOT / "tools/portrait-pilot/prepare_action_frame_reselection.py",
    ROOT / "tools/portrait-pilot/prepare_pilot.py",
    ROOT / "tools/portrait-pilot/SelectedSpriteFrameExporter.java",
    ROOT / "tools/portrait-pilot/verify-frame-reselection.js",
    ROOT / "tools/portrait-pilot/open-frame-reselection.js",
    ROOT / "tools/portrait-pilot/test-frame-reselection.js",
    ROOT / "launcher/web/modules/portrait-pilot-review/dev/frame-reselection.html",
    ROOT / "launcher/web/modules/portrait-pilot-review/dev/frame-reselection.js",
    ROOT / "launcher/web/modules/portrait-pilot-review/dev/source-choice.css",
    ROOT / "launcher/web/modules/portrait-pilot-review/dev/review.css",
]


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def require_object(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise PilotError(f"{label} 必须是对象")
    return value


def require_list(value: object, label: str) -> list[object]:
    if not isinstance(value, list):
        raise PilotError(f"{label} 必须是数组")
    return value


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def symbol_frame_count(root: ET.Element) -> int:
    ends = []
    for frame in root.iter():
        if local_name(frame.tag) != "DOMFrame":
            continue
        index = int(frame.attrib.get("index", "-1"))
        duration = int(frame.attrib.get("duration", "1"))
        if index >= 0 and duration >= 1:
            ends.append(index + duration)
    if not ends:
        raise PilotError("XFL 目标元件没有有效帧")
    return max(ends)


def resolve_xfl_action_instance(
    project_root: Path,
    root_symbol_name: str,
    action_label: str,
    library_item_name: str,
) -> dict[str, object]:
    root_path = project_root / "LIBRARY" / Path(*root_symbol_name.split("/"))
    target_path = project_root / "LIBRARY" / Path(*library_item_name.split("/"))
    root_path = root_path.with_suffix(".xml")
    target_path = target_path.with_suffix(".xml")
    if not root_path.is_file() or not target_path.is_file():
        raise PilotError(f"XFL 根或动作元件缺失：{repo_rel(root_path)} / {repo_rel(target_path)}")
    root = ET.parse(root_path).getroot()
    target = ET.parse(target_path).getroot()
    if root.attrib.get("name") != root_symbol_name or target.attrib.get("name") != library_item_name:
        raise PilotError("XFL 库元件名称与路径不一致")
    action_indexes = {
        int(frame.attrib["index"])
        for frame in root.iter()
        if local_name(frame.tag) == "DOMFrame" and frame.attrib.get("name") == action_label
    }
    if len(action_indexes) != 1:
        raise PilotError(f"XFL 动作标签不唯一：{action_label} indexes={sorted(action_indexes)}")
    action_index = next(iter(action_indexes))
    placements: list[dict[str, object]] = []
    for layer in (node for node in root.iter() if local_name(node.tag) == "DOMLayer"):
        for frame in (node for node in layer.iter() if local_name(node.tag) == "DOMFrame"):
            if int(frame.attrib.get("index", "-1")) != action_index:
                continue
            for instance in (node for node in frame.iter() if local_name(node.tag) == "DOMSymbolInstance"):
                if instance.attrib.get("libraryItemName") == library_item_name:
                    placements.append({
                        "layerName": layer.attrib.get("name", ""),
                        "instanceName": instance.attrib.get("name"),
                        "libraryItemName": library_item_name,
                    })
    if len(placements) != 1:
        raise PilotError(f"XFL 动作状态没有唯一目标人物元件：{action_label}/{library_item_name} matches={len(placements)}")
    return {
        "project": artifact(project_root / f"{project_root.name}.xfl"),
        "document": artifact(project_root / "DOMDocument.xml"),
        "rootSymbol": artifact(root_path),
        "targetSymbol": artifact(target_path),
        "rootSymbolName": root_symbol_name,
        "rootLinkageIdentifier": root.attrib.get("linkageIdentifier"),
        "actionLabel": action_label,
        "xflFrameIndex": action_index,
        "xflFrameNumber": action_index + 1,
        "targetFrameCount": symbol_frame_count(target),
        **placements[0],
    }


def resolve_swf_action_instance(
    xml_path: Path,
    root_character_id: int,
    action_label: str,
    target_frame_count: int,
) -> dict[str, object]:
    root = ET.parse(xml_path).getroot()
    definitions = {
        int(node.attrib["spriteId"]): node
        for node in root.iter("item")
        if node.attrib.get("type") == "DefineSpriteTag"
    }
    root_sprite = definitions.get(root_character_id)
    if root_sprite is None:
        raise PilotError(f"SWF XML 缺根 DefineSprite：{root_character_id}")
    sub_tags = root_sprite.find("subTags")
    if sub_tags is None:
        raise PilotError(f"SWF 根 DefineSprite 缺 subTags：{root_character_id}")
    frame_number = 1
    action_frame: int | None = None
    placements: list[int] = []
    for node in sub_tags.findall("item"):
        tag_type = node.attrib.get("type")
        if tag_type == "ShowFrameTag":
            frame_number += 1
            continue
        if tag_type == "FrameLabelTag" and node.attrib.get("name") == action_label:
            if action_frame is not None:
                raise PilotError(f"SWF 动作标签重复：{action_label}")
            action_frame = frame_number
            continue
        if action_frame == frame_number and node.attrib.get("characterId"):
            placements.append(int(node.attrib["characterId"]))
    if action_frame is None:
        raise PilotError(f"SWF 缺动作标签：{action_label}")
    matching = sorted({
        character_id
        for character_id in placements
        if character_id in definitions
        and int(definitions[character_id].attrib.get("frameCount", "0")) == target_frame_count
    })
    if len(matching) != 1:
        raise PilotError(
            f"SWF 动作状态不能按 XFL 帧数唯一对齐人物元件：placements={sorted(set(placements))} matching={matching}"
        )
    render_character_id = matching[0]
    return {
        "actionLabel": action_label,
        "actionFrameNumber": action_frame,
        "placementsAtActionFrame": sorted(set(placements)),
        "renderCharacterId": render_character_id,
        "renderDeclaredFrameCount": int(definitions[render_character_id].attrib.get("frameCount", "0")),
    }


def create_candidate(
    output_root: Path,
    swf_path: Path,
    character_id: int,
    frame_number: int,
    candidate_id: str,
) -> tuple[dict[str, object], dict[str, object]]:
    adapter = compile_selected_frame_exporter(output_root, "exact-action-frame-v1")
    png_run, records = export_selected_sprite_frames(
        adapter,
        output_root,
        swf_path,
        character_id,
        [frame_number],
        2,
        f"exact-action-character-{character_id}",
        "exact-action-frame-v1",
    )
    source_path = verify_artifact_record(records[frame_number], "精确人物帧 PNG")
    with Image.open(source_path) as opened:
        rgba = opened.convert("RGBA")
    alpha_bounds = rgba.getchannel("A").getbbox()
    if not alpha_bounds or alpha_bounds[2] - alpha_bounds[0] < 8 or alpha_bounds[3] - alpha_bounds[1] < 8:
        raise PilotError("精确人物帧为空或过小")
    crop_bounds = expanded_bbox(alpha_bounds, rgba.size)
    cropped = rgba.crop(crop_bounds)
    candidate_root = output_root / "candidates" / candidate_id.split("-c", 1)[0]
    candidate_root.mkdir(parents=True)
    candidate_path = candidate_root / f"{candidate_id}-frame-{frame_number:04d}.png"
    cropped.save(candidate_path, format="PNG", optimize=False, compress_level=9)
    visual_hash = sha256_bytes(f"{cropped.width}x{cropped.height}:".encode("ascii") + cropped.tobytes())

    svg_export_root = output_root / "ffdec-svg"
    svg_export_root.mkdir()
    svg_run = run_ffdec(
        [
            "-onerror", "abort", "-ignorebackground",
            "-selectid", str(character_id), "-format", "sprite:svg",
            "-export", "sprite", str(svg_export_root), str(swf_path),
        ],
        output_root,
        "exact-action-svg",
        timeout_seconds=600,
    )
    sprite_roots = [path for path in svg_export_root.glob(f"DefineSprite_{character_id}*") if path.is_dir()]
    if len(sprite_roots) != 1:
        raise PilotError(f"FFDec SVG 人物目录不唯一：{sprite_roots}")
    vector_path = sprite_roots[0] / f"{frame_number}.svg"
    if not vector_path.is_file():
        raise PilotError(f"FFDec SVG 缺精确帧：{frame_number}")
    candidate = {
        "candidateId": candidate_id,
        "frame": frame_number,
        "sourceSize": list(rgba.size),
        "alphaBounds": list(alpha_bounds),
        "sourceCropBounds": list(crop_bounds),
        "visualSha256": visual_hash,
        "artifact": artifact(candidate_path),
        "width": cropped.width,
        "height": cropped.height,
        "vectorCanvasSize": list(svg_canvas_size(vector_path)),
        "vectorArtifact": artifact(vector_path),
    }
    runs = {
        "adapter": {key: value for key, value in adapter.items() if key != "runtimeClasspath"},
        "png": png_run,
        "svg": svg_run,
    }
    return candidate, runs


def verifier(batch_root: Path, check: bool) -> dict[str, object]:
    argv = [
        "node",
        str(ROOT / "tools/portrait-pilot/verify-frame-reselection.js"),
        "--batch",
        repo_rel(batch_root),
    ]
    if check:
        argv.append("--check")
    completed = subprocess.run(
        argv,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise PilotError(f"精确选帧回执验证失败：{detail}")
    try:
        return require_object(json.loads(completed.stdout.decode("utf-8")), "精确选帧回执输出")
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PilotError("精确选帧回执输出不是合法 JSON") from error


def candidate_fields(candidate: dict[str, object]) -> dict[str, object]:
    return {
        key: copy.deepcopy(candidate[key])
        for key in [
            "candidateId", "frame", "width", "height", "sourceSize", "sourceCropBounds",
            "vectorCanvasSize", "artifact", "vectorArtifact",
        ]
    }


def render(options: argparse.Namespace) -> dict[str, object]:
    if options.frame < 1:
        raise PilotError("--frame 必须是正整数")
    if options.orientation_action not in {"keep", "flip_x"}:
        raise PilotError("--orientation-action 仅接受 keep|flip_x")
    if not options.batch_id or any(character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-" for character in options.batch_id):
        raise PilotError("batch id 非法")
    expansion_root = action_base.pilot_child(options.expansion_batch, "父扩帧批次", must_exist=True)
    output_root = action_base.pilot_child(options.output, "输出目录", must_exist=False)
    expansion_data, _expansion_decisions, expansion_receipt = action_base.verify_expansion_batch(
        expansion_root,
        options.review_key,
    )
    matching_items = [
        item for item in require_list(expansion_data.get("items"), "父扩帧 items")
        if isinstance(item, dict) and item.get("reviewKey") == options.review_key
    ]
    if len(matching_items) != 1:
        raise PilotError(f"父扩帧数据没有唯一审核行：{options.review_key}")
    old_item = matching_items[0]
    portrait_ref = str(old_item.get("portraitRef", ""))
    parent = require_object(expansion_data.get("parent"), "父扩帧 parent")
    parent_files = require_object(parent.get("files"), "父扩帧 parent.files")
    manifest_record = require_object(parent_files.get("candidateManifest"), "父 candidate manifest")
    manifest_path = verify_artifact_record(manifest_record, "父 candidate manifest")
    manifest = require_object(load_json(manifest_path), "父 candidate manifest")
    verify_digest_object(manifest, "manifestDigest", "父 candidate manifest")
    entity = action_base.find_entity(manifest, portrait_ref)

    source_swf_rel = str(entity.get("sourceSwf", ""))
    swf_records = require_list(require_object(manifest.get("sourceEnvelope"), "sourceEnvelope").get("sourceSwfs"), "sourceSwfs")
    matching_swf_records = [record for record in swf_records if isinstance(record, dict) and record.get("path") == source_swf_rel]
    if len(matching_swf_records) != 1:
        raise PilotError(f"来源 SWF 闭包不唯一：{source_swf_rel}")
    swf_record = matching_swf_records[0]
    swf_path = verify_artifact_record(swf_record, "来源 SWF")
    xml_record = require_object(entity.get("ffdecXml"), "来源 FFDec XML")
    xml_path = verify_artifact_record(xml_record, "来源 FFDec XML")
    project_root = swf_path.with_suffix("")
    if not project_root.is_dir():
        raise PilotError(f"来源 XFL 工程目录缺失：{repo_rel(project_root)}")

    xfl = resolve_xfl_action_instance(
        project_root,
        options.root_symbol,
        options.action_label,
        options.library_item,
    )
    if xfl.get("rootLinkageIdentifier") != portrait_ref:
        raise PilotError(f"XFL 根 linkage 与 portraitRef 不一致：{xfl.get('rootLinkageIdentifier')} != {portrait_ref}")
    swf = resolve_swf_action_instance(
        xml_path,
        int(entity["characterId"]),
        options.action_label,
        int(xfl["targetFrameCount"]),
    )
    if int(xfl["xflFrameNumber"]) != int(swf["actionFrameNumber"]):
        raise PilotError("XFL 与 SWF 动作起始帧不一致")
    if options.frame > int(swf["renderDeclaredFrameCount"]):
        raise PilotError("人类指定帧越出动作人物时间轴")

    output_root.mkdir(parents=False)
    ffdec = verify_ffdec()
    candidate, runs = create_candidate(
        output_root,
        swf_path,
        int(swf["renderCharacterId"]),
        options.frame,
        options.candidate_id,
    )
    old_candidates = []
    for raw in require_list(old_item.get("candidates"), "旧候选"):
        record = require_object(raw, "旧候选")
        verify_artifact_record(require_object(record.get("artifact"), "旧候选 PNG"), "旧候选 PNG")
        verify_artifact_record(require_object(record.get("vectorArtifact"), "旧候选 SVG"), "旧候选 SVG")
        old_candidates.append(candidate_fields(record))
    rejected_ids = [str(item["candidateId"]) for item in old_candidates]
    candidates = [candidate_fields(candidate), *old_candidates]

    source_envelope = {
        "parentSourceDigest": expansion_data.get("sourceDigest"),
        "parentExpansionReceiptDigest": expansion_receipt.get("receiptDigest"),
        "sourceSwf": swf_record,
        "ffdecXml": xml_record,
        "xfl": xfl,
        "swf": swf,
        "humanDirective": options.human_directive,
        "frame": options.frame,
        "orientationAction": options.orientation_action,
    }
    source_digest = sha256_bytes(stable_bytes(source_envelope))
    reviewer_files = [artifact(path) for path in REVIEWER_FILES]
    closure_files = {
        "candidateManifest": manifest_record,
        "expansionData": artifact(expansion_root / "frame-reselection-data.json"),
        "expansionDecisions": artifact(expansion_root / "portrait-pilot-frame-reselection.json"),
        "expansionReceipt": artifact(expansion_root / "human-frame-reselection-receipt.json"),
        "sourceSwf": swf_record,
        "sourceProject": xfl["project"],
        "sourceRootSymbol": xfl["rootSymbol"],
        "sourceTargetSymbol": xfl["targetSymbol"],
        "ffdecXml": xml_record,
        "selectedFrameCommand": require_object(runs["png"], "PNG run")["commandRecord"],
        "svgCommand": require_object(runs["svg"], "SVG run")["commandRecord"],
    }
    created_at = utc_now()
    dataset: dict[str, object] = {
        "schema": DATA_SCHEMA,
        "phase": "FRAME_RESELECTION",
        "status": "human_exact_action_frame_candidate_ready",
        "productionReady": False,
        "batchId": options.batch_id,
        "createdAt": created_at,
        "decisionSchema": DECISION_SCHEMA,
        "sourceDigest": source_digest,
        "parent": {
            "batchId": expansion_data.get("batchId"),
            "manifestDigest": manifest.get("manifestDigest"),
            "modelReportDigest": parent.get("modelReportDigest"),
            "reviewDigest": parent.get("reviewDigest"),
            "receiptDigest": expansion_receipt.get("receiptDigest"),
            "files": closure_files,
        },
        "sourceSelection": {
            "strategy": "human_directive_exact_action_state_instance_frame",
            "humanDirective": options.human_directive,
            "orientationAction": options.orientation_action,
            "xfl": xfl,
            "swf": swf,
            "sourceEnvelope": source_envelope,
            "candidateFrames": [options.frame],
            "allPreviousCandidatesRejected": True,
        },
        "generation": {
            "ffdec": ffdec,
            "ffdecVersion": FFDEC_EXPECTED_VERSION,
            "runs": [runs["png"], runs["svg"]],
            "usableUniqueFrameCount": 1,
            "exportedFrameCount": int(swf["renderDeclaredFrameCount"]),
        },
        "reviewer": {
            "files": reviewer_files,
            "sourceClosureDigest": sha256_bytes(stable_bytes(reviewer_files)),
        },
        "counts": {
            "identityCount": 1,
            "candidateCount": len(candidates),
            "rejectedCandidateCount": len(rejected_ids),
            "selectableCandidateCount": 1,
        },
        "items": [{
            "reviewCode": old_item.get("reviewCode"),
            "reviewKey": options.review_key,
            "portraitRef": portrait_ref,
            "variantKey": "default",
            "category": old_item.get("category"),
            "humanDecision": {
                "status": "wrong_pose",
                "notes": options.human_directive,
                "updatedAt": created_at,
            },
            "rejectedCandidateIds": rejected_ids,
            "candidates": candidates,
        }],
        "gates": {
            "onlyFrozenWrongPoseRows": True,
            "rejectedCurrentFramesNotSelectable": True,
            "vectorFramesShownAtLargeSize": True,
            "humanFrameSelectionRequired": True,
            "localizationRerunRequiredAfterSelection": True,
            "modelGeometryNotReused": True,
            "productionWrites": False,
        },
    }
    dataset["datasetDigest"] = sha256_bytes(stable_bytes(dataset))
    write_json(output_root / "frame-reselection-data.json", dataset)

    decision = {
        "schema": DECISION_SCHEMA,
        "batchId": options.batch_id,
        "sourceDigest": source_digest,
        "datasetDigest": dataset["datasetDigest"],
        "complete": True,
        "exportedAt": created_at,
        "choices": {
            options.review_key: {
                "status": "selected",
                "candidateId": options.candidate_id,
                "candidateSha256": require_object(candidate["artifact"], "候选 PNG")["sha256"],
                "vectorArtifactSha256": require_object(candidate["vectorArtifact"], "候选 SVG")["sha256"],
                "frame": options.frame,
                "notes": f"{options.human_directive}；方向派生={options.orientation_action}。",
                "updatedAt": created_at,
            }
        },
    }
    write_json(output_root / "portrait-pilot-frame-reselection.json", decision)
    built = verifier(output_root, check=False)
    checked = verifier(output_root, check=True)
    receipt = require_object(load_json(output_root / "human-frame-reselection-receipt.json"), "精确选帧回执")
    if receipt.get("schema") != RECEIPT_SCHEMA or receipt.get("status") != "human_frame_reselection_verified":
        raise PilotError("精确选帧没有得到 selected 回执")
    return {
        "status": "human_exact_action_frame_verified",
        "output": repo_rel(output_root),
        "datasetDigest": dataset["datasetDigest"],
        "receiptDigest": receipt["receiptDigest"],
        "candidateId": options.candidate_id,
        "frame": options.frame,
        "orientationAction": options.orientation_action,
        "xflActionFrame": xfl["xflFrameNumber"],
        "renderCharacterId": swf["renderCharacterId"],
        "renderDeclaredFrameCount": swf["renderDeclaredFrameCount"],
        "verifier": {"build": built.get("status"), "check": checked.get("status")},
    }


def check(options: argparse.Namespace) -> dict[str, object]:
    output_root = action_base.pilot_child(options.output, "输出目录", must_exist=True)
    data = require_object(load_json(output_root / "frame-reselection-data.json"), "精确选帧数据")
    verify_digest_object(data, "datasetDigest", "精确选帧数据")
    if data.get("status") != "human_exact_action_frame_candidate_ready":
        raise PilotError("精确选帧数据状态漂移")
    for record in [*require_object(data.get("parent"), "parent")["files"].values(), *require_object(data.get("reviewer"), "reviewer")["files"]]:
        verify_artifact_record(require_object(record, "闭包 artifact"), "精确选帧闭包")
    selection = require_object(data.get("sourceSelection"), "sourceSelection")
    if selection.get("strategy") != "human_directive_exact_action_state_instance_frame":
        raise PilotError("精确选帧策略漂移")
    verified = verifier(output_root, check=True)
    receipt = require_object(load_json(output_root / "human-frame-reselection-receipt.json"), "精确选帧回执")
    row = require_object(require_list(receipt.get("rows"), "回执行")[0], "回执行")
    if row.get("status") != "selected" or row.get("frame") != selection.get("candidateFrames", [None])[0]:
        raise PilotError("精确选帧回执与人类指定帧不一致")
    return {
        "status": "human_exact_action_frame_checked",
        "datasetDigest": data["datasetDigest"],
        "receiptDigest": receipt["receiptDigest"],
        "frame": row["frame"],
        "orientationAction": selection["orientationAction"],
        "verifier": verified.get("status"),
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--expansion-batch", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.add_argument("--review-key", required=True)
    render_parser.add_argument("--root-symbol", required=True)
    render_parser.add_argument("--action-label", required=True)
    render_parser.add_argument("--library-item", required=True)
    render_parser.add_argument("--frame", type=int, required=True)
    render_parser.add_argument("--candidate-id", required=True)
    render_parser.add_argument("--orientation-action", choices=["keep", "flip_x"], required=True)
    render_parser.add_argument("--human-directive", required=True)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    return result


def main() -> None:
    options = parser().parse_args()
    report = render(options) if options.command == "render" else check(options)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, PilotError, KeyError, ValueError, json.JSONDecodeError, ET.ParseError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
