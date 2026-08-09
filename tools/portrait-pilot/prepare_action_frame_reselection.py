#!/usr/bin/env python3
"""Build a frozen frame-review batch from a named action-state ``man`` instance."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

from prepare_pilot import (
    FFDEC_EXPECTED_VERSION,
    PILOT_ROOT,
    ROOT,
    PilotError,
    artifact,
    inspect_gif_frames,
    load_json,
    repo_rel,
    run_ffdec,
    save_selected_frames,
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
EXPANSION_RECEIPT_SCHEMA = "cf7.enemy-portrait-frame-reselection-receipt.v1"
DEFAULT_FRAMES = [12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34]
REVIEWER_FILES = [
    ROOT / "tools/portrait-pilot/prepare_action_frame_reselection.py",
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


def parse_frames(value: str) -> list[int]:
    try:
        frames = [int(part.strip()) for part in value.split(",") if part.strip()]
    except ValueError as error:
        raise PilotError("--frames 必须是逗号分隔的正整数") from error
    if len(frames) < 2 or len(frames) != len(set(frames)) or any(frame < 1 for frame in frames):
        raise PilotError("--frames 至少包含两个不重复正整数")
    return frames


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expansion-batch", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--batch-id", required=True)
    parser.add_argument("--review-key", required=True)
    parser.add_argument("--action-label", default="空手攻击")
    parser.add_argument("--instance-name", default="man")
    parser.add_argument("--expected-library-item", default="双枪狂徒/sprite/平a")
    parser.add_argument("--frames", default=",".join(str(frame) for frame in DEFAULT_FRAMES))
    return parser.parse_args()


def pilot_child(value: str, label: str, must_exist: bool) -> Path:
    path = (ROOT / value).resolve()
    try:
        path.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise PilotError(f"{label} 必须位于 tmp/portrait-pilot 下") from error
    if must_exist and not path.is_dir():
        raise PilotError(f"{label} 不存在：{repo_rel(path)}")
    if not must_exist and path.exists():
        raise PilotError(f"{label} 已存在，禁止覆盖：{repo_rel(path)}")
    return path


def verify_expansion_batch(batch_root: Path, review_key: str) -> tuple[dict[str, object], dict[str, object], dict[str, object]]:
    completed = subprocess.run(
        [
            "node",
            str(ROOT / "tools/portrait-pilot/verify-frame-reselection.js"),
            "--batch",
            repo_rel(batch_root),
            "--check",
        ],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise PilotError(f"父扩帧回执验证失败：{detail}")
    dataset_path = batch_root / "frame-reselection-data.json"
    decisions_path = batch_root / "portrait-pilot-frame-reselection.json"
    receipt_path = batch_root / "human-frame-reselection-receipt.json"
    dataset = require_object(load_json(dataset_path), "父扩帧数据")
    decisions = require_object(load_json(decisions_path), "父扩帧决定")
    receipt = require_object(load_json(receipt_path), "父扩帧回执")
    if receipt.get("schema") != EXPANSION_RECEIPT_SCHEMA or receipt.get("status") != "human_frame_search_expansion_required":
        raise PilotError("父回执不是已验证的继续抽帧请求")
    rows = require_list(receipt.get("rows"), "父扩帧回执行")
    matches = [row for row in rows if isinstance(row, dict) and row.get("reviewKey") == review_key]
    if len(matches) != 1 or matches[0].get("status") != "expand_search":
        raise PilotError(f"父扩帧回执没有唯一 expand_search 行：{review_key}")
    return dataset, decisions, receipt


def find_entity(manifest: dict[str, object], portrait_ref: str) -> dict[str, object]:
    entities = require_list(manifest.get("entities"), "candidate manifest entities")
    matches = [entity for entity in entities if isinstance(entity, dict) and entity.get("portraitRef") == portrait_ref]
    if len(matches) != 1:
        raise PilotError(f"candidate manifest 身份不唯一：{portrait_ref}")
    return matches[0]


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def read_fla_entries(fla_path: Path, entry_names: list[str]) -> dict[str, bytes]:
    try:
        with zipfile.ZipFile(fla_path) as archive:
            return {name: archive.read(name) for name in entry_names}
    except (KeyError, zipfile.BadZipFile):
        powershell = r'''
Add-Type -AssemblyName System.IO.Compression.FileSystem
$entryNames = ConvertFrom-Json $env:CF7_PORTRAIT_FLA_ENTRIES_JSON
$archive = [System.IO.Compression.ZipFile]::OpenRead($env:CF7_PORTRAIT_FLA_PATH)
try {
  $rows = @()
  foreach ($name in $entryNames) {
    $entry = $archive.GetEntry($name)
    if ($null -eq $entry) { throw "FLA entry missing: $name" }
    $stream = $entry.Open()
    $memory = [System.IO.MemoryStream]::new()
    try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
    try {
      $rows += [Convert]::ToBase64String($memory.ToArray())
    } finally { $memory.Dispose() }
  }
  $rows | ConvertTo-Json -Compress
} finally { $archive.Dispose() }
'''
        environment = os.environ.copy()
        environment["CF7_PORTRAIT_FLA_PATH"] = str(fla_path)
        environment["CF7_PORTRAIT_FLA_ENTRIES_JSON"] = json.dumps(entry_names, ensure_ascii=False)
        completed = subprocess.run(
            [
                "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive",
                "-ExecutionPolicy", "Bypass", "-Command", powershell,
            ],
            cwd=ROOT,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if completed.returncode != 0:
            detail = completed.stderr.decode("utf-8", errors="replace").strip()
            raise PilotError(f"Flash FLA .NET 读取失败：{detail}")
        try:
            rows = json.loads(completed.stdout.decode("ascii"))
            if isinstance(rows, str):
                rows = [rows]
            if not isinstance(rows, list) or len(rows) != len(entry_names):
                raise ValueError("FLA entry count mismatch")
            values = {name: base64.b64decode(data) for name, data in zip(entry_names, rows)}
        except (json.JSONDecodeError, ValueError, UnicodeDecodeError) as error:
            raise PilotError("Flash FLA .NET 读取输出非法") from error
        if set(values) != set(entry_names):
            raise PilotError("Flash FLA .NET 读取条目不闭合")
        return values


def resolve_fla_action_instance(
    fla_path: Path,
    root_symbol_name: str,
    action_label: str,
    instance_name: str,
    expected_library_item: str,
) -> dict[str, object]:
    root_entry = f"LIBRARY/{root_symbol_name}.xml"
    target_entry = f"LIBRARY/{expected_library_item}.xml"
    entries = read_fla_entries(fla_path, [root_entry, target_entry])
    root = ET.fromstring(entries[root_entry])
    target_root = ET.fromstring(entries[target_entry])
    if root.attrib.get("name") != root_symbol_name or target_root.attrib.get("name") != expected_library_item:
        raise PilotError("FLA 库元件名称与条目路径不一致")
    action_indexes = {
        int(frame.attrib["index"])
        for frame in root.iter()
        if local_name(frame.tag) == "DOMFrame" and frame.attrib.get("name") == action_label
    }
    if len(action_indexes) != 1:
        raise PilotError(f"FLA 动作标签不唯一：{action_label} indexes={sorted(action_indexes)}")
    action_index = next(iter(action_indexes))
    matches: list[dict[str, object]] = []
    for layer in (node for node in root.iter() if local_name(node.tag) == "DOMLayer"):
        for frame in (node for node in layer.iter() if local_name(node.tag) == "DOMFrame"):
            if int(frame.attrib.get("index", "-1")) != action_index:
                continue
            for instance in (node for node in frame.iter() if local_name(node.tag) == "DOMSymbolInstance"):
                if instance.attrib.get("name") == instance_name:
                    matches.append(
                        {
                            "layerName": layer.attrib.get("name", ""),
                            "xflFrameIndex": action_index,
                            "xflFrameNumber": action_index + 1,
                            "libraryItemName": instance.attrib.get("libraryItemName", ""),
                        }
                    )
    if len(matches) != 1:
        raise PilotError(f"FLA 动作状态内命名实例不唯一：{action_label}/{instance_name} matches={len(matches)}")
    if matches[0]["libraryItemName"] != expected_library_item:
        raise PilotError(
            f"FLA 动作状态命中其他库元件：{matches[0]['libraryItemName']} != {expected_library_item}"
        )
    return {"rootEntry": root_entry, "targetEntry": target_entry, **matches[0]}


def resolve_swf_action_instance(
    xml_path: Path,
    root_character_id: int,
    action_label: str,
    instance_name: str,
) -> dict[str, int]:
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
    matches: list[int] = []
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
        if action_frame == frame_number and node.attrib.get("name") == instance_name and node.attrib.get("characterId"):
            matches.append(int(node.attrib["characterId"]))
    if action_frame is None or len(set(matches)) != 1:
        raise PilotError(f"SWF 动作状态内命名实例不唯一：{action_label}/{instance_name} ids={sorted(set(matches))}")
    render_character_id = matches[0]
    target = definitions.get(render_character_id)
    if target is None:
        raise PilotError(f"SWF 动作 man 不是 DefineSprite：{render_character_id}")
    return {
        "actionFrameNumber": action_frame,
        "renderCharacterId": render_character_id,
        "renderDeclaredFrameCount": int(target.attrib.get("frameCount", "0")),
    }


def candidate_fields(candidate: dict[str, object]) -> dict[str, object]:
    return {
        key: candidate[key]
        for key in [
            "candidateId",
            "frame",
            "width",
            "height",
            "sourceSize",
            "sourceCropBounds",
            "vectorCanvasSize",
            "artifact",
            "vectorArtifact",
        ]
    }


def main() -> None:
    options = parse_args()
    frames = parse_frames(options.frames)
    if not options.batch_id or any(character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-" for character in options.batch_id):
        raise PilotError("batch id 非法")
    expansion_root = pilot_child(options.expansion_batch, "父扩帧批次", must_exist=True)
    output_root = pilot_child(options.output, "输出目录", must_exist=False)
    expansion_data, expansion_decisions, expansion_receipt = verify_expansion_batch(expansion_root, options.review_key)

    expansion_items = require_list(expansion_data.get("items"), "父扩帧 items")
    old_items = [item for item in expansion_items if isinstance(item, dict) and item.get("reviewKey") == options.review_key]
    if len(old_items) != 1:
        raise PilotError(f"父扩帧数据没有唯一审核行：{options.review_key}")
    old_item = old_items[0]
    portrait_ref = str(old_item.get("portraitRef", ""))
    parent = require_object(expansion_data.get("parent"), "父扩帧 parent")
    parent_files = require_object(parent.get("files"), "父扩帧 parent.files")
    manifest_record = require_object(parent_files.get("candidateManifest"), "父 candidate manifest artifact")
    manifest_path = verify_artifact_record(manifest_record, "父 candidate manifest")
    manifest = require_object(load_json(manifest_path), "父 candidate manifest")
    verify_digest_object(manifest, "manifestDigest", "父 candidate manifest")
    entity = find_entity(manifest, portrait_ref)

    source_swf_rel = str(entity.get("sourceSwf", ""))
    swf_records = require_list(require_object(manifest.get("sourceEnvelope"), "sourceEnvelope").get("sourceSwfs"), "sourceSwfs")
    matching_swf_records = [record for record in swf_records if isinstance(record, dict) and record.get("path") == source_swf_rel]
    if len(matching_swf_records) != 1:
        raise PilotError(f"来源 SWF 闭包不唯一：{source_swf_rel}")
    swf_record = matching_swf_records[0]
    swf_path = verify_artifact_record(swf_record, "来源 SWF")
    xml_record = require_object(entity.get("ffdecXml"), "来源 FFDec XML artifact")
    xml_path = verify_artifact_record(xml_record, "来源 FFDec XML")
    fla_path = swf_path.with_suffix(".fla")
    if not fla_path.is_file():
        raise PilotError(f"来源 FLA 缺失：{repo_rel(fla_path)}")

    selected_source = require_object(entity.get("selectedSource"), "selectedSource")
    root_symbol_name = str(selected_source.get("symbolName", ""))
    fla_resolution = resolve_fla_action_instance(
        fla_path,
        root_symbol_name,
        options.action_label,
        options.instance_name,
        options.expected_library_item,
    )
    swf_resolution = resolve_swf_action_instance(
        xml_path,
        int(entity["characterId"]),
        options.action_label,
        options.instance_name,
    )
    if fla_resolution["xflFrameNumber"] != swf_resolution["actionFrameNumber"]:
        raise PilotError("FLA 与 SWF 动作起始帧不一致")
    if max(frames) > swf_resolution["renderDeclaredFrameCount"]:
        raise PilotError("候选帧越出动作 man 时间轴")

    output_root.mkdir(parents=False)
    ffdec = verify_ffdec()
    render_character_id = swf_resolution["renderCharacterId"]
    gif_export_root = output_root / "ffdec-gif"
    svg_export_root = output_root / "ffdec-svg"
    gif_export_root.mkdir()
    svg_export_root.mkdir()
    gif_run = run_ffdec(
        [
            "-onerror", "abort", "-ignorebackground", "-zoom", "2",
            "-selectid", str(render_character_id), "-format", "sprite:gif",
            "-export", "sprite", str(gif_export_root), str(swf_path),
        ],
        output_root,
        "action-man-gif",
        timeout_seconds=600,
    )
    svg_run = run_ffdec(
        [
            "-onerror", "abort", "-ignorebackground",
            "-selectid", str(render_character_id), "-format", "sprite:svg",
            "-export", "sprite", str(svg_export_root), str(swf_path),
        ],
        output_root,
        "action-man-svg",
        timeout_seconds=600,
    )
    gif_matches = list(gif_export_root.glob(f"DefineSprite_{render_character_id}*/frames.gif"))
    svg_matches = [path for path in svg_export_root.glob(f"DefineSprite_{render_character_id}*") if path.is_dir()]
    if len(gif_matches) != 1 or len(svg_matches) != 1:
        raise PilotError("FFDec 动作 man 导出目录不唯一")
    gif_path = gif_matches[0]
    svg_root = svg_matches[0]
    inspected = inspect_gif_frames(gif_path)
    inspected_by_frame = {int(row["frame"]): row for row in inspected}
    missing = [frame for frame in frames if frame not in inspected_by_frame]
    if missing:
        raise PilotError(f"指定候选帧为空或视觉重复：{missing}")
    selected = [inspected_by_frame[frame] for frame in sorted(frames)]
    new_candidates = save_selected_frames(gif_path, selected, output_root / "candidates" / "e09p", "e09p")
    for candidate in new_candidates:
        svg_path = svg_root / f"{candidate['frame']}.svg"
        if not svg_path.is_file():
            raise PilotError(f"FFDec SVG 缺候选帧：{candidate['frame']}")
        candidate["vectorCanvasSize"] = list(svg_canvas_size(svg_path))
        candidate["vectorArtifact"] = artifact(svg_path)

    old_candidates_raw = require_list(old_item.get("candidates"), "旧候选")
    old_candidates = []
    for candidate in old_candidates_raw:
        record = require_object(candidate, "旧候选")
        verify_artifact_record(require_object(record.get("artifact"), "旧候选 PNG"), "旧候选 PNG")
        verify_artifact_record(require_object(record.get("vectorArtifact"), "旧候选 SVG"), "旧候选 SVG")
        old_candidates.append(candidate_fields(record))
    rejected_ids = [str(candidate["candidateId"]) for candidate in old_candidates]
    candidates = [candidate_fields(candidate) for candidate in new_candidates] + old_candidates

    source_envelope = {
        "parentSourceDigest": expansion_data.get("sourceDigest"),
        "sourceSwf": swf_record,
        "sourceFla": artifact(fla_path),
        "ffdecXml": xml_record,
        "rootCharacterId": int(entity["characterId"]),
        "actionLabel": options.action_label,
        "actionFrameNumber": swf_resolution["actionFrameNumber"],
        "instanceName": options.instance_name,
        "libraryItemName": fla_resolution["libraryItemName"],
        "renderCharacterId": render_character_id,
        "renderDeclaredFrameCount": swf_resolution["renderDeclaredFrameCount"],
    }
    source_digest = sha256_bytes(stable_bytes(source_envelope))
    reviewer_files = [artifact(path) for path in REVIEWER_FILES]
    expansion_data_path = expansion_root / "frame-reselection-data.json"
    expansion_decisions_path = expansion_root / "portrait-pilot-frame-reselection.json"
    expansion_receipt_path = expansion_root / "human-frame-reselection-receipt.json"
    closure_files = {
        "candidateManifest": manifest_record,
        "expansionData": artifact(expansion_data_path),
        "expansionDecisions": artifact(expansion_decisions_path),
        "expansionReceipt": artifact(expansion_receipt_path),
        "sourceSwf": swf_record,
        "sourceFla": artifact(fla_path),
        "ffdecXml": xml_record,
        "ffdecGif": artifact(gif_path),
        "gifCommandRecord": gif_run["commandRecord"],
        "svgCommandRecord": svg_run["commandRecord"],
    }
    dataset = {
        "schema": DATA_SCHEMA,
        "phase": "FRAME_RESELECTION",
        "status": "action_state_frame_candidates_ready",
        "productionReady": False,
        "batchId": options.batch_id,
        "createdAt": utc_now(),
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
            "strategy": "named_action_state_man_instance",
            "humanDirective": "旧候选全部禁用；改用空手攻击状态内的平a man 抽帧。",
            "fla": fla_resolution,
            "swf": swf_resolution,
            "sourceEnvelope": source_envelope,
            "candidateFrames": sorted(frames),
            "allPreviousCandidatesRejected": True,
        },
        "generation": {
            "ffdec": ffdec,
            "ffdecVersion": FFDEC_EXPECTED_VERSION,
            "runs": [gif_run, svg_run],
            "usableUniqueFrameCount": len(inspected),
            "exportedFrameCount": swf_resolution["renderDeclaredFrameCount"],
        },
        "reviewer": {
            "files": reviewer_files,
            "sourceClosureDigest": sha256_bytes(stable_bytes(reviewer_files)),
        },
        "counts": {
            "identityCount": 1,
            "candidateCount": len(candidates),
            "rejectedCandidateCount": len(rejected_ids),
            "selectableCandidateCount": len(new_candidates),
        },
        "items": [
            {
                "reviewCode": old_item.get("reviewCode"),
                "reviewKey": options.review_key,
                "portraitRef": portrait_ref,
                "variantKey": "default",
                "category": old_item.get("category"),
                "humanDecision": {
                    "status": "wrong_pose",
                    "notes": "旧候选全部不可用；改从空手攻击 → 平a 的 man 时间轴重选。",
                    "updatedAt": expansion_receipt.get("verifiedAt"),
                },
                "rejectedCandidateIds": rejected_ids,
                "candidates": candidates,
            }
        ],
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
    data_path = output_root / "frame-reselection-data.json"
    write_json(data_path, dataset)
    print(
        json.dumps(
            {
                "status": dataset["status"],
                "path": repo_rel(data_path),
                "datasetDigest": dataset["datasetDigest"],
                "sourceDigest": source_digest,
                "actionFrameNumber": swf_resolution["actionFrameNumber"],
                "renderCharacterId": render_character_id,
                "selectable": len(new_candidates),
                "rejected": len(rejected_ids),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except (PilotError, KeyError, ValueError, zipfile.BadZipFile) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1)
