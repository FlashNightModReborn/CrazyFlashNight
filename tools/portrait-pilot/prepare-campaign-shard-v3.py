#!/usr/bin/env python3
"""Prepare a transitive campaign shard from a sparse source pool with uneven source counts."""

from __future__ import annotations

import argparse
import contextlib
import copy
import importlib.util
import inspect
import io
import json
import sys
import textwrap
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


CONTROLLER_PATH = Path(__file__).resolve()
V2_CONTROLLER_PATH = CONTROLLER_PATH.with_name("prepare-campaign-shard-v2.py")
BASE_CONTROLLER_PATH = CONTROLLER_PATH.with_name("prepare_campaign.py")
POLICY_SCHEMA = "cf7.portrait-pilot-sparse-source-availability.v1"
FEEDBACK_SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v4"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


v2 = load_module(V2_CONTROLLER_PATH, "cf7_portrait_campaign_shard_v2")
base = v2.base
core = v2.core


PREPARE_VALIDATION_OLD = '''\
    shard_size = int(args.shard_size)
    source_groups = int(args.source_groups)
    if shard_size < 4 or shard_size > 48 or source_groups < 1 or source_groups > 12 or shard_size % source_groups:
        raise core.PilotError("shard-size 必须为 4..48 且能被 1..12 的 source-groups 整除")
    per_source = shard_size // source_groups
    if per_source > 16:
        raise core.PilotError("每个来源 SWF 的单 shard 身份数不得超过 16")
'''

PREPARE_VALIDATION_NEW = '''\
    shard_size = int(args.shard_size)
    requested_source_groups = int(args.source_groups)
    if shard_size < 4 or shard_size > 48 or requested_source_groups < 1 or requested_source_groups > 12:
        raise core.PilotError("shard-size 必须为 4..48，requested source-groups 必须为 1..12")
    target_per_source = (shard_size + requested_source_groups - 1) // requested_source_groups
    if target_per_source > 16:
        raise core.PilotError("每个来源 SWF 的单 shard 目标身份数不得超过 16")
'''

PREPARE_SELECTION_OLD = '''\
    eligible = [
        item
        for item in inventory["items"]
        if item["sourceResolution"] in ("unique", "human_selected") and item["portraitRef"] not in excluded
    ]
    buckets: dict[str, list[dict[str, object]]] = defaultdict(list)
    for item in eligible:
        buckets[item["selectedSource"]["swf"]].append(item)
    ordered_buckets = sorted(buckets.items(), key=lambda entry: (-len(entry[1]), entry[0]))
    output_dir.mkdir(parents=True)
    ffdec = core.verify_ffdec()
    ffdec_runs: list[dict[str, object]] = []
    probe_swf_records: list[dict[str, object]] = []
    resolution_anomalies: list[dict[str, object]] = []
    selected_groups: list[tuple[str, list[dict[str, object]]]] = []
    bucket_counter = 0
    for swf_rel, rows in ordered_buckets:
        if len(selected_groups) == source_groups:
            break
        if len(rows) < per_source:
            continue
        bucket_counter += 1
        run, resolved, anomalies = resolve_bucket(
            output_dir,
            bucket_counter,
            swf_rel,
            sorted(rows, key=lambda row: row["portraitRef"]),
        )
        ffdec_runs.append(run)
        probe_swf_records.append(core.artifact(ROOT / swf_rel))
        resolution_anomalies.extend(anomalies)
        if len(resolved) >= per_source:
            selected_groups.append((swf_rel, resolved[:per_source]))
    if len(selected_groups) != source_groups:
        raise core.PilotError(
            f"无法组成 {source_groups} 个含 {per_source} 个唯一 man 的来源组；actual={len(selected_groups)}"
        )
'''

PREPARE_SELECTION_NEW = '''\
    eligible = [
        item
        for item in inventory["items"]
        if item["sourceResolution"] in ("unique", "human_selected") and item["portraitRef"] not in excluded
    ]
    buckets: dict[str, list[dict[str, object]]] = defaultdict(list)
    for item in eligible:
        buckets[item["selectedSource"]["swf"]].append(item)
    ordered_buckets = sorted(buckets.items(), key=lambda entry: (-len(entry[1]), entry[0]))
    output_dir.mkdir(parents=True)
    ffdec = core.verify_ffdec()
    ffdec_runs: list[dict[str, object]] = []
    probe_swf_records: list[dict[str, object]] = []
    resolution_anomalies: list[dict[str, object]] = []
    selected_groups: list[tuple[str, list[dict[str, object]]]] = []
    selected_identity_count = 0
    bucket_counter = 0
    for swf_rel, rows in ordered_buckets:
        if selected_identity_count >= shard_size:
            break
        bucket_counter += 1
        run, resolved, anomalies = resolve_bucket(
            output_dir,
            bucket_counter,
            swf_rel,
            sorted(rows, key=lambda row: row["portraitRef"]),
        )
        ffdec_runs.append(run)
        probe_swf_records.append(core.artifact(ROOT / swf_rel))
        resolution_anomalies.extend(anomalies)
        take = min(len(resolved), target_per_source, shard_size - selected_identity_count)
        if take > 0:
            selected_groups.append((swf_rel, resolved[:take]))
            selected_identity_count += take
    if selected_identity_count != shard_size:
        raise core.PilotError(
            f"稀疏来源池只能闭合 {selected_identity_count}/{shard_size} 个唯一 man；probed={bucket_counter}"
        )
    source_groups = len(selected_groups)
    per_source = None
'''

PREPARE_CAMPAIGN_OLD = '''\
    campaign = {
        "inventoryDigest": inventory["inventoryDigest"],
        "selectionStrategy": "remaining_identity_count_desc_then_swf_path; portraitRef_ascending; exact_named_man_only",
        "shardSize": shard_size,
        "sourceGroups": source_groups,
        "identitiesPerSourceGroup": per_source,
        "selectedSourceCounts": dict(sorted(source_counts.items())),
        "selectedPortraitRefs": [entity["portraitRef"] for entity in entities],
        "excludedRepresentativeRefs": sorted(representative_refs),
        "excludedPriorRefs": sorted(excluded - representative_refs),
        "resolutionAnomalies": resolution_anomalies,
        "serviceTierRecommendation": "fast",
        "maxConcurrencyRecommendation": 6,
        "expectedModelJobs": len(model_batches) * 2,
    }
'''

PREPARE_CAMPAIGN_NEW = '''\
    campaign = {
        "inventoryDigest": inventory["inventoryDigest"],
        "selectionStrategy": "remaining_identity_count_desc_then_swf_path; dense_bucket_fill_up_to_target; portraitRef_ascending; exact_named_man_only",
        "shardSize": shard_size,
        "requestedSourceGroups": requested_source_groups,
        "sourceGroups": source_groups,
        "sourceGroupLayout": "sparse_uneven",
        "identitiesPerSourceGroup": per_source,
        "maximumIdentitiesPerSourceGroup": target_per_source,
        "selectedSourceCounts": dict(sorted(source_counts.items())),
        "selectedPortraitRefs": [entity["portraitRef"] for entity in entities],
        "excludedRepresentativeRefs": sorted(representative_refs),
        "excludedPriorRefs": sorted(excluded - representative_refs),
        "resolutionAnomalies": resolution_anomalies,
        "serviceTierRecommendation": "fast",
        "maxConcurrencyRecommendation": 6,
        "expectedModelJobs": len(model_batches) * 2,
    }
'''

PREPARE_GATES_OLD = '''\
            "semanticFeatureRequired": True,
            "humanReviewRequired": True,
            "productionWrites": False,
'''

PREPARE_GATES_NEW = '''\
            "semanticFeatureRequired": True,
            "humanReviewRequired": True,
            "sparseSourceAvailabilityBound": True,
            "productionWrites": False,
'''

VERIFY_SOURCE_OLD = '''\
    source_counts = Counter(entity["sourceSwf"] for entity in entities)
    expected_per_source = campaign["identitiesPerSourceGroup"]
    if (
        len(source_counts) != campaign.get("sourceGroups")
        or any(count != expected_per_source for count in source_counts.values())
        or dict(sorted(source_counts.items())) != campaign.get("selectedSourceCounts")
        or len(manifest.get("modelBatches", [])) * 2 != campaign.get("expectedModelJobs")
    ):
        raise core.PilotError("campaign shard 来源分组或 Fast 6 job 闭包错误")
'''

VERIFY_SOURCE_NEW = '''\
    source_counts = Counter(entity["sourceSwf"] for entity in entities)
    requested_source_groups = campaign.get("requestedSourceGroups")
    maximum_per_source = campaign.get("maximumIdentitiesPerSourceGroup")
    if (
        campaign.get("sourceGroupLayout") != "sparse_uneven"
        or campaign.get("identitiesPerSourceGroup") is not None
        or not isinstance(requested_source_groups, int)
        or requested_source_groups < 1
        or requested_source_groups > 12
        or len(source_counts) != campaign.get("sourceGroups")
        or len(source_counts) < requested_source_groups
        or not isinstance(maximum_per_source, int)
        or maximum_per_source < 1
        or any(count < 1 or count > maximum_per_source for count in source_counts.values())
        or sum(source_counts.values()) != campaign.get("shardSize")
        or dict(sorted(source_counts.items())) != campaign.get("selectedSourceCounts")
        or len(manifest.get("modelBatches", [])) * 2 != campaign.get("expectedModelJobs")
        or manifest.get("gates", {}).get("sparseSourceAvailabilityBound") is not True
    ):
        raise core.PilotError("campaign sparse source grouping 或 model job 闭包错误")
'''


def transformed(function: Any, replacements: list[tuple[str, str]], name: str):
    source = textwrap.dedent(inspect.getsource(function))
    for old, new in replacements:
        if source.count(old) != 1:
            raise core.PilotError(f"{name} source transform 锚点漂移")
        source = source.replace(old, new)
    namespace: dict[str, Any] = {}
    exec(compile(source, f"<{name}-sparse-v1>", "exec"), base.__dict__, namespace)
    return namespace[function.__name__]


SPARSE_PREPARE = transformed(
    base.prepare_shard,
    [
        (PREPARE_VALIDATION_OLD, PREPARE_VALIDATION_NEW),
        (PREPARE_SELECTION_OLD, PREPARE_SELECTION_NEW),
        (PREPARE_CAMPAIGN_OLD, PREPARE_CAMPAIGN_NEW),
        (PREPARE_GATES_OLD, PREPARE_GATES_NEW),
    ],
    "prepare-campaign-shard",
)
SPARSE_VERIFY = transformed(base.verify_shard, [(VERIFY_SOURCE_OLD, VERIFY_SOURCE_NEW)], "verify-campaign-shard")


@contextmanager
def patched_sparse_base() -> Iterator[None]:
    original_prepare = base.prepare_shard
    original_verify = base.verify_shard
    try:
        base.prepare_shard = SPARSE_PREPARE
        base.verify_shard = SPARSE_VERIFY
        yield
    finally:
        base.prepare_shard = original_prepare
        base.verify_shard = original_verify


def verify_feedback(path: Path, shard_size: int, requested_source_groups: int) -> dict[str, Any]:
    feedback = core.load_json(path)
    if not isinstance(feedback, dict):
        raise core.PilotError("feedback report 顶层必须是对象")
    envelope = dict(feedback)
    digest = envelope.pop("feedbackDigest", None)
    if core.sha256_bytes(core.stable_bytes(envelope)) != digest:
        raise core.PilotError("feedback report digest 漂移")
    scaling = feedback.get("adaptiveScaling", {})
    override = scaling.get("humanScaleOverride", {})
    if (
        feedback.get("schema") != FEEDBACK_SCHEMA
        or feedback.get("status") != "human_feedback_calibrated"
        or feedback.get("productionReady") is not False
        or scaling.get("recommendedNextShardSize") != shard_size
        or scaling.get("recommendedSourceGroups") != requested_source_groups
        or scaling.get("maximumConcurrency") != 3
        or override.get("active") is not True
        or override.get("targetShardSize") != shard_size
        or override.get("targetSourceGroups") != requested_source_groups
    ):
        raise core.PilotError("feedback 扩容指令与 sparse shard 请求不一致")
    return feedback


def bind_sparse_policy(manifest_path: Path, feedback_path: Path) -> None:
    manifest = core.verify_manifest(manifest_path)
    campaign = manifest.get("campaign", {})
    feedback = verify_feedback(
        feedback_path,
        int(campaign.get("shardSize", 0)),
        int(campaign.get("requestedSourceGroups", 0)),
    )
    selected_counts = campaign.get("selectedSourceCounts", {})
    policy = {
        "schema": POLICY_SCHEMA,
        "controllerSource": core.artifact(CONTROLLER_PATH),
        "v2ControllerSource": core.artifact(V2_CONTROLLER_PATH),
        "baseControllerSource": core.artifact(BASE_CONTROLLER_PATH),
        "feedbackReport": core.artifact(feedback_path),
        "requestedShardSize": campaign["shardSize"],
        "requestedSourceGroups": campaign["requestedSourceGroups"],
        "requestedIdentitiesPerSource": (campaign["shardSize"] + campaign["requestedSourceGroups"] - 1)
        // campaign["requestedSourceGroups"],
        "actualSourceGroups": campaign["sourceGroups"],
        "actualSelectedSourceCounts": selected_counts,
        "uniformRequestedLayoutFeasible": all(
            count == campaign["maximumIdentitiesPerSourceGroup"] for count in selected_counts.values()
        )
        and campaign["sourceGroups"] == campaign["requestedSourceGroups"],
        "identityThroughputPreserved": manifest.get("counts", {}).get("identityCount") == campaign["shardSize"],
        "modelItemsPerGroup": feedback["adaptiveScaling"]["modelItemsPerGroup"],
        "modelBatchCount": len(manifest.get("modelBatches", [])),
        "maximumConcurrency": feedback["adaptiveScaling"]["maximumConcurrency"],
        "linkageRootFallbackForbidden": True,
        "productionWrites": False,
    }
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in (CONTROLLER_PATH, V2_CONTROLLER_PATH, BASE_CONTROLLER_PATH, feedback_path):
        record = core.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceEnvelope"]["sparseSourceAvailabilityPolicy"] = policy
    manifest["campaign"]["sparseSourceAvailabilityPolicy"] = policy
    manifest["gates"]["sparseSourceAvailabilityBound"] = True
    manifest["sourceDigest"] = core.sha256_bytes(core.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    core.write_json(manifest_path, manifest)


def verify_sparse(manifest_path: Path) -> dict[str, Any]:
    with patched_sparse_base(), contextlib.redirect_stdout(io.StringIO()):
        result = v2.verify_transitive(manifest_path)
    manifest = core.verify_manifest(manifest_path)
    envelope_policy = manifest.get("sourceEnvelope", {}).get("sparseSourceAvailabilityPolicy")
    campaign_policy = manifest.get("campaign", {}).get("sparseSourceAvailabilityPolicy")
    if not isinstance(envelope_policy, dict) or envelope_policy != campaign_policy:
        raise core.PilotError("sparse source policy 顶层与 source envelope 漂移")
    policy = envelope_policy
    feedback_path = core.verify_artifact_record(policy.get("feedbackReport"), "sparse feedback report")
    feedback = verify_feedback(
        feedback_path,
        int(policy.get("requestedShardSize", 0)),
        int(policy.get("requestedSourceGroups", 0)),
    )
    selected_counts = manifest["campaign"]["selectedSourceCounts"]
    if (
        policy.get("schema") != POLICY_SCHEMA
        or policy.get("controllerSource") != core.artifact(CONTROLLER_PATH)
        or policy.get("v2ControllerSource") != core.artifact(V2_CONTROLLER_PATH)
        or policy.get("baseControllerSource") != core.artifact(BASE_CONTROLLER_PATH)
        or policy.get("actualSourceGroups") != len(selected_counts)
        or policy.get("actualSelectedSourceCounts") != selected_counts
        or policy.get("identityThroughputPreserved") is not True
        or policy.get("modelItemsPerGroup") != 4
        or policy.get("modelBatchCount") != 6
        or policy.get("maximumConcurrency") != 3
        or policy.get("linkageRootFallbackForbidden") is not True
        or policy.get("productionWrites") is not False
        or feedback["adaptiveScaling"]["recommendedNextShardSize"] != manifest["counts"]["identityCount"]
    ):
        raise core.PilotError("sparse source availability policy gate 非法")
    return {
        **result,
        "status": "campaign_sparse_shard_verified",
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "identities": manifest["counts"]["identityCount"],
        "requestedSourceGroups": policy["requestedSourceGroups"],
        "actualSourceGroups": policy["actualSourceGroups"],
        "modelBatches": policy["modelBatchCount"],
        "maximumConcurrency": policy["maximumConcurrency"],
        "productionReady": False,
    }


def prepare(args: argparse.Namespace) -> None:
    feedback_path = core.ensure_below(Path(args.feedback_report), base.ROOT, "feedback report")
    verify_feedback(feedback_path, int(args.shard_size), int(args.source_groups))
    with patched_sparse_base(), contextlib.redirect_stdout(io.StringIO()):
        v2.prepare(args)
    output = core.ensure_below(Path(args.output), base.PILOT_ROOT, "sparse shard output")
    manifest_path = output / "candidate-manifest.json"
    bind_sparse_policy(manifest_path, feedback_path)
    print(json.dumps(verify_sparse(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(
        json.dumps(
            verify_sparse(core.ensure_below(Path(args.manifest), base.PILOT_ROOT, "sparse shard manifest")),
            ensure_ascii=False,
        )
    )


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare-shard")
    prepare_parser.add_argument("--inventory", required=True)
    prepare_parser.add_argument("--output", required=True)
    prepare_parser.add_argument("--batch-id", required=True)
    prepare_parser.add_argument("--representative-closure", required=True)
    prepare_parser.add_argument("--profile")
    prepare_parser.add_argument("--shard-size", type=int, required=True)
    prepare_parser.add_argument("--source-groups", type=int, required=True)
    prepare_parser.add_argument("--exclude-manifest", action="append", default=[])
    prepare_parser.add_argument("--feedback-report", required=True)
    prepare_parser.set_defaults(handler=prepare)
    check_parser = commands.add_parser("check-shard")
    check_parser.add_argument("--manifest", required=True)
    check_parser.set_defaults(handler=check)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (core.PilotError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"portrait campaign shard v3 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
