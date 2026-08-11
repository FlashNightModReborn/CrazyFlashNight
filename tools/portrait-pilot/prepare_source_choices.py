#!/usr/bin/env python3
"""Build the enemy portrait conflict/duplicate source-choice queue."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
DATA_SCHEMA = "cf7.enemy-portrait-source-choice-candidates.v1"
DECISION_SCHEMA = "cf7.enemy-portrait-source-choice-decisions.v1"
REVIEWER_PATHS = [
    ROOT / "tools" / "portrait-pilot" / "prepare_source_choices.py",
    ROOT / "tools" / "portrait-pilot" / "prepare_pilot.py",
    ROOT / "tools" / "portrait-pilot" / "verify-source-choice-decisions.js",
    ROOT / "tools" / "portrait-pilot" / "open-source-choice.js",
    ROOT / "launcher" / "web" / "modules" / "portrait-pilot-review" / "dev" / "source-choice.html",
    ROOT / "launcher" / "web" / "modules" / "portrait-pilot-review" / "dev" / "source-choice.js",
    ROOT / "launcher" / "web" / "modules" / "portrait-pilot-review" / "dev" / "source-choice.css",
    ROOT / "launcher" / "web" / "modules" / "portrait-pilot-review" / "dev" / "review.css",
]


def source_candidate_key(portrait_ref: str, source: dict[str, object]) -> str:
    payload = {
        "portraitRef": portrait_ref,
        "swf": source.get("swf"),
        "symbolName": source.get("symbolName"),
        "orphan": bool(source.get("orphan")),
    }
    return "SC-" + hashlib.sha256(core.stable_bytes(payload)).hexdigest().upper()[:20]


def verify_artifact(record: dict[str, object], label: str) -> None:
    if not isinstance(record, dict) or not isinstance(record.get("path"), str):
        raise core.PilotError(f"{label} artifact 记录不闭合")
    path = (ROOT / str(record["path"])).resolve()
    try:
        path.relative_to(ROOT.resolve())
    except ValueError as error:
        raise core.PilotError(f"{label} artifact 越出仓库") from error
    if not path.is_file() or core.artifact(path) != record:
        raise core.PilotError(f"{label} artifact 字节闭包不匹配：{record.get('path')}")


def verify_dataset(data_path: Path) -> tuple[dict[str, object], int]:
    dataset = core.load_json(data_path)
    if not isinstance(dataset, dict) or dataset.get("schema") != DATA_SCHEMA:
        raise core.PilotError("source choice data schema 不受支持")
    envelope = dataset.get("sourceEnvelope")
    if not isinstance(envelope, dict) or core.sha256_bytes(core.stable_bytes(envelope)) != dataset.get("sourceDigest"):
        raise core.PilotError("source choice sourceDigest 不匹配")
    digest_input = dict(dataset)
    digest_input.pop("manifestDigest", None)
    if core.sha256_bytes(core.stable_bytes(digest_input)) != dataset.get("manifestDigest"):
        raise core.PilotError("source choice manifestDigest 不匹配")
    if dataset.get("productionReady") is not False or dataset.get("phase") != "SOURCE_CHOICE":
        raise core.PilotError("source choice 状态非法")
    gates = dataset.get("gates", {})
    expected_gates = {
        "enemyIdentityOnly": True,
        "sourceCandidatesRemainIdentityAlternatives": True,
        "selectedOutputVariantKey": "default",
        "humanSelectionRequired": True,
        "modelInferenceRequired": False,
        "productionWrites": False,
    }
    if gates != expected_gates:
        raise core.PilotError("source choice gates 漂移")

    artifact_count = 0
    for record in [
        envelope.get("assetMap"),
        envelope.get("enemyList"),
        envelope.get("pets"),
        *(envelope.get("enemyFiles") or []),
        *(envelope.get("sourceSwfs") or []),
        *(envelope.get("controllerFiles") or []),
        *(envelope.get("reviewerFiles") or []),
        *(envelope.get("ffdec", {}).get("files") or []),
    ]:
        verify_artifact(record, "source choice source")
        artifact_count += 1
    for run in dataset.get("ffdecRuns", []):
        for field in ("stdout", "stderr", "commandRecord"):
            verify_artifact(run.get(field), f"FFDec run {field}")
            artifact_count += 1

    items = dataset.get("items")
    if not isinstance(items, list) or not items:
        raise core.PilotError("source choice 没有审核行")
    review_keys: set[str] = set()
    source_keys: set[str] = set()
    renderable_count = 0
    manual_count = 0
    conflict_count = 0
    duplicate_count = 0
    for item in items:
        review_key = item.get("reviewKey")
        if not isinstance(review_key, str) or review_key in review_keys:
            raise core.PilotError("source choice reviewKey 缺失或重复")
        review_keys.add(review_key)
        classification = item.get("sourceClassification")
        if classification not in ("duplicate", "conflict"):
            raise core.PilotError(f"source choice 分类非法：{review_key}")
        conflict_count += int(classification == "conflict")
        duplicate_count += int(classification == "duplicate")
        sources = item.get("sources")
        if not isinstance(sources, list) or len(sources) < 2:
            raise core.PilotError(f"source choice 来源不足：{review_key}")
        for source in sources:
            key = source.get("sourceCandidateKey")
            if not isinstance(key, str) or key in source_keys:
                raise core.PilotError("sourceCandidateKey 缺失或重复")
            source_keys.add(key)
            if source_candidate_key(item["portraitRef"], source) != key:
                raise core.PilotError(f"sourceCandidateKey 漂移：{key}")
            if source.get("renderable"):
                renderable_count += 1
                for field in ("ffdecXml", "ffdecGif"):
                    verify_artifact(source.get(field), f"{key} {field}")
                    artifact_count += 1
                frames = source.get("frames")
                if not isinstance(frames, list) or not frames:
                    raise core.PilotError(f"可渲染来源没有候选帧：{key}")
                for frame in frames:
                    verify_artifact(frame.get("artifact"), f"{key} frame")
                    artifact_count += 1
                if source.get("renderStrategy") not in ("first_frame_named_man_instance", "linkage_root_fallback"):
                    raise core.PilotError(f"渲染策略非法：{key}")
            else:
                manual_count += 1
                if source.get("unrenderableReason") != "orphan_without_symbol_name" or source.get("frames") != []:
                    raise core.PilotError(f"人工来源状态非法：{key}")

    counts = dataset.get("counts", {})
    expected_counts = {
        "identityCount": len(items),
        "sourceCandidateCount": len(source_keys),
        "renderableSourceCandidateCount": renderable_count,
        "manualSourceCandidateCount": manual_count,
        "conflictIdentityCount": conflict_count,
        "duplicateIdentityCount": duplicate_count,
    }
    if counts != expected_counts:
        raise core.PilotError(f"source choice counts 不闭合：expected={expected_counts} actual={counts}")
    return dataset, artifact_count


def prepare(args: argparse.Namespace) -> None:
    output_dir = core.ensure_below(Path(args.output), PILOT_ROOT, "输出目录")
    if output_dir.exists():
        raise core.PilotError(f"输出目录已存在，禁止覆盖：{output_dir}")
    if not args.batch_id or len(args.batch_id) > 128 or not all(character.isalnum() or character in "._-" for character in args.batch_id):
        raise core.PilotError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")
    try:
        args.batch_id.encode("ascii")
    except UnicodeEncodeError as error:
        raise core.PilotError("batch id 必须是 ASCII") from error
    output_dir.mkdir(parents=True)

    asset_records = core.parse_asset_map()
    enemy_ids, pet_ids, enemy_files = core.load_consumers()
    queue = [
        (portrait_ref, record)
        for portrait_ref, record in asset_records.items()
        if portrait_ref.startswith("敌人-")
        and record.get("classification") in ("duplicate", "conflict")
        and (portrait_ref in enemy_ids or portrait_ref in pet_ids)
    ]
    queue.sort(key=lambda entry: entry[0])
    if not queue:
        raise core.PilotError("当前资产映射没有敌人 duplicate/conflict")

    ffdec = core.verify_ffdec()
    items: list[dict[str, object]] = []
    sources_by_swf: dict[str, list[tuple[dict[str, object], dict[str, object]]]] = {}
    for item_index, (portrait_ref, record) in enumerate(queue, start=1):
        item = {
            "reviewCode": f"S{item_index:02d}",
            "reviewKey": f"{portrait_ref}::source",
            "portraitRef": portrait_ref,
            "variantKey": "default",
            "sourceClassification": record["classification"],
            "consumers": {
                "enemy": portrait_ref in enemy_ids,
                "petIds": sorted(pet_ids.get(portrait_ref, [])),
            },
            "sources": [],
        }
        for source_index, raw_source in enumerate(record["sources"], start=1):
            source = {
                "sourceCode": f"S{item_index:02d}C{source_index:02d}",
                "sourceCandidateKey": source_candidate_key(portrait_ref, raw_source),
                "swf": raw_source["swf"],
                "symbolName": raw_source.get("symbolName"),
                "orphan": bool(raw_source.get("orphan")),
                "renderable": bool(raw_source.get("symbolName")),
                "unrenderableReason": None if raw_source.get("symbolName") else "orphan_without_symbol_name",
                "frames": [],
            }
            item["sources"].append(source)
            if source["renderable"]:
                sources_by_swf.setdefault(source["swf"], []).append((item, source))
        items.append(item)

    ffdec_runs: list[dict[str, object]] = []
    swf_evidence: list[dict[str, object]] = []
    for swf_index, (swf_rel, source_pairs) in enumerate(sorted(sources_by_swf.items()), start=1):
        swf_path = ROOT / swf_rel
        if not swf_path.is_file():
            raise core.PilotError(f"来源 SWF 缺失：{swf_rel}")
        swf_evidence.append(core.artifact(swf_path))
        xml_path = output_dir / "ffdec-xml" / f"source-{swf_index:03d}.xml"
        xml_path.parent.mkdir(parents=True, exist_ok=True)
        ffdec_runs.append(core.run_ffdec(
            ["-onerror", "abort", "-swf2xml", str(swf_path), str(xml_path)],
            output_dir,
            f"source-{swf_index:03d}-xml",
        ))
        exports = core.export_assets_from_xml(xml_path)
        frame_counts = core.sprite_frame_counts(xml_path)
        render_ids: list[int] = []
        for item, source in source_pairs:
            matches = exports.get(item["portraitRef"], [])
            if len(matches) != 1:
                raise core.PilotError(
                    f"来源候选 linkage → characterId 不唯一：{item['portraitRef']} matches={matches} source={swf_rel}"
                )
            root_id = matches[0]
            if root_id not in frame_counts:
                raise core.PilotError(f"来源候选 linkage 不是 DefineSprite：{item['portraitRef']} id={root_id}")
            man_id = core.first_frame_named_instance(xml_path, root_id, "man")
            render_id = man_id or root_id
            if render_id not in frame_counts:
                raise core.PilotError(f"来源候选渲染目标不是 DefineSprite：root={root_id} render={render_id}")
            source.update({
                "rootCharacterId": root_id,
                "rootDeclaredFrameCount": frame_counts[root_id],
                "renderCharacterId": render_id,
                "renderDeclaredFrameCount": frame_counts[render_id],
                "renderStrategy": "first_frame_named_man_instance" if man_id is not None else "linkage_root_fallback",
                "renderStrategyWarning": None if man_id is not None else "named_man_missing",
                "ffdecXml": core.artifact(xml_path),
            })
            render_ids.append(render_id)

        gif_root = output_dir / "ffdec-gif" / f"source-{swf_index:03d}"
        gif_root.mkdir(parents=True)
        ffdec_runs.append(core.run_ffdec(
            [
                "-onerror", "abort", "-ignorebackground", "-zoom", "2",
                "-selectid", ",".join(str(value) for value in sorted(set(render_ids))),
                "-format", "sprite:gif", "-export", "sprite", str(gif_root), str(swf_path),
            ],
            output_dir,
            f"source-{swf_index:03d}-gif",
        ))
        for _item, source in source_pairs:
            matches = list(gif_root.glob(f"DefineSprite_{source['renderCharacterId']}*/frames.gif"))
            if len(matches) != 1:
                raise core.PilotError(
                    f"来源候选 FFDec GIF 不唯一：{source['sourceCandidateKey']} matches={len(matches)}"
                )
            gif_path = matches[0]
            inspected = core.inspect_gif_frames(gif_path)
            if not inspected:
                raise core.PilotError(f"来源候选没有非空帧：{source['sourceCandidateKey']}")
            selected = core.choose_evenly(inspected, 6)
            source["frames"] = core.save_selected_frames(
                gif_path,
                selected,
                output_dir / "source-candidates" / source["sourceCode"],
                source["sourceCode"].lower(),
            )
            source["ffdecGif"] = core.artifact(gif_path)
            source["exportedFrameCount"] = len(inspected)

    controller_files = [core.artifact(path) for path in REVIEWER_PATHS[:2]]
    reviewer_files = [core.artifact(path) for path in REVIEWER_PATHS[2:]]
    source_envelope = {
        "assetMap": core.artifact(core.ASSET_MAP_PATH),
        "enemyList": core.artifact(core.ENEMY_LIST_PATH),
        "pets": core.artifact(core.PETS_PATH),
        "enemyFiles": [core.artifact(path) for path in enemy_files],
        "ffdec": ffdec,
        "sourceSwfs": swf_evidence,
        "controllerFiles": controller_files,
        "reviewerFiles": reviewer_files,
    }
    dataset = {
        "schema": DATA_SCHEMA,
        "phase": "SOURCE_CHOICE",
        "status": "source_candidates_extracted",
        "productionReady": False,
        "batchId": args.batch_id,
        "createdAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "decisionSchema": DECISION_SCHEMA,
        "sourceEnvelope": source_envelope,
        "sourceDigest": core.sha256_bytes(core.stable_bytes(source_envelope)),
        "counts": {
            "identityCount": len(items),
            "sourceCandidateCount": sum(len(item["sources"]) for item in items),
            "renderableSourceCandidateCount": sum(source["renderable"] for item in items for source in item["sources"]),
            "manualSourceCandidateCount": sum(not source["renderable"] for item in items for source in item["sources"]),
            "conflictIdentityCount": sum(item["sourceClassification"] == "conflict" for item in items),
            "duplicateIdentityCount": sum(item["sourceClassification"] == "duplicate" for item in items),
        },
        "ffdecRuns": ffdec_runs,
        "items": items,
        "gates": {
            "enemyIdentityOnly": True,
            "sourceCandidatesRemainIdentityAlternatives": True,
            "selectedOutputVariantKey": "default",
            "humanSelectionRequired": True,
            "modelInferenceRequired": False,
            "productionWrites": False,
        },
    }
    dataset["manifestDigest"] = core.sha256_bytes(core.stable_bytes(dataset))
    data_path = output_dir / "source-choice-data.json"
    core.write_json(data_path, dataset)
    checked, artifact_count = verify_dataset(data_path)
    print(json.dumps({
        "status": checked["status"],
        "path": core.repo_rel(data_path),
        "manifestDigest": checked["manifestDigest"],
        "sourceDigest": checked["sourceDigest"],
        "rows": checked["counts"]["identityCount"],
        "candidates": checked["counts"]["sourceCandidateCount"],
        "renderable": checked["counts"]["renderableSourceCandidateCount"],
        "manual": checked["counts"]["manualSourceCandidateCount"],
        "artifactCount": artifact_count,
    }, ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    output_dir = core.ensure_below(Path(args.output), PILOT_ROOT, "输出目录")
    dataset, artifact_count = verify_dataset(output_dir / "source-choice-data.json")
    print(json.dumps({
        "status": "source_choice_data_verified",
        "manifestDigest": dataset["manifestDigest"],
        "sourceDigest": dataset["sourceDigest"],
        "rows": dataset["counts"]["identityCount"],
        "candidates": dataset["counts"]["sourceCandidateCount"],
        "artifactCount": artifact_count,
    }, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--output", required=True)
    prepare_parser.add_argument("--batch-id", required=True)
    prepare_parser.set_defaults(handler=prepare)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    check_parser.set_defaults(handler=check)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    args.handler(args)


if __name__ == "__main__":
    try:
        main()
    except (core.PilotError, OSError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=__import__("sys").stderr)
        raise SystemExit(1)
