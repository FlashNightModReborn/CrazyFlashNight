#!/usr/bin/env python3
"""Prepare the availability-clamped tail shard under the controlled Fast6 policy."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import math
import sys
from pathlib import Path
from typing import Any


CONTROLLER_PATH = Path(__file__).resolve()
V4_CONTROLLER_PATH = CONTROLLER_PATH.with_name("prepare-campaign-shard-v4.py")
FEEDBACK_CONTROLLER_PATH = CONTROLLER_PATH.with_name("build-feedback-calibration-v5.js")
POLICY_SCHEMA = "cf7.portrait-pilot-sparse-source-availability.v3"
FEEDBACK_SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v5"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


v4 = load_module(V4_CONTROLLER_PATH, "cf7_portrait_campaign_shard_v4_for_v5")
v3 = v4.v3
v2 = v3.v2
base = v4.base
core = v4.core


def verify_parent_feedback(path: Path, desired_shard_size: int, requested_source_groups: int) -> dict[str, Any]:
    feedback = core.load_json(path)
    if not isinstance(feedback, dict):
        raise core.PilotError("feedback report 顶层必须是对象")
    envelope = dict(feedback)
    digest = envelope.pop("feedbackDigest", None)
    if core.sha256_bytes(core.stable_bytes(envelope)) != digest:
        raise core.PilotError("feedback report digest 漂移")
    scaling = feedback.get("adaptiveScaling", {})
    override = scaling.get("humanScaleOverride", {})
    profile = scaling.get("executionProfile", {})
    pilot = scaling.get("concurrencyPilot", {})
    if (
        feedback.get("schema") != FEEDBACK_SCHEMA
        or feedback.get("status") != "human_feedback_calibrated"
        or feedback.get("productionReady") is not False
        or scaling.get("recommendedNextShardSize") != desired_shard_size
        or scaling.get("recommendedSourceGroups") != requested_source_groups
        or scaling.get("modelItemsPerGroup") != 4
        or scaling.get("maximumConcurrency") != 6
        or profile.get("model") != "Luna Max"
        or profile.get("serviceTier") != "fast"
        or profile.get("maximumConcurrency") != 6
        or profile.get("timeoutSeconds") != 600
        or profile.get("fallbackMaximumConcurrency") != 3
        or pilot.get("policy") != "bounded_fast6_with_fail_closed_fallback_v1"
        or pilot.get("qualityGatesUnchanged") is not True
        or override.get("active") is not True
        or override.get("targetShardSize") != desired_shard_size
        or override.get("targetSourceGroups") != requested_source_groups
    ):
        raise core.PilotError("feedback Fast6/48 身份目标与 availability clamp 请求不一致")
    return feedback


def availability_truth(
    inventory_path: Path,
    exclusion_paths: list[str],
    manifest: dict[str, Any],
    desired_shard_size: int,
) -> dict[str, Any]:
    inventory, _artifact_count = base.verify_inventory(inventory_path)
    prior_excluded, _records = v2.exclusion_closure(exclusion_paths)
    representative_refs, _fixture = base.load_representative_fixture()
    excluded = prior_excluded | representative_refs
    remaining = [item for item in inventory["items"] if item["portraitRef"] not in excluded]
    eligible = [item for item in remaining if item["sourceResolution"] in ("unique", "human_selected")]
    missing = [item for item in remaining if item["sourceResolution"] == "missing"]
    selected_refs = {item["portraitRef"] for item in manifest.get("reviewItems", [])}
    anomaly_refs = {
        item["portraitRef"]
        for item in manifest.get("campaign", {}).get("resolutionAnomalies", [])
        if isinstance(item, dict) and isinstance(item.get("portraitRef"), str)
    }
    eligible_refs = {item["portraitRef"] for item in eligible}
    if (
        selected_refs & anomaly_refs
        or selected_refs | anomaly_refs != eligible_refs
        or len(selected_refs) >= desired_shard_size
        or len(missing) + len(eligible) != len(remaining)
    ):
        raise core.PilotError("tail shard 没有闭合全部剩余可解析身份或 availability clamp 不成立")
    return {
        "policy": "exhaust_exact_named_man_tail_v1",
        "desiredShardSize": desired_shard_size,
        "effectiveShardSize": len(selected_refs),
        "remainingConsumerIdentities": len(remaining),
        "remainingResolvedSourceIdentities": len(eligible),
        "exactNamedManAvailable": len(selected_refs),
        "namedManStructuralAnomalies": len(anomaly_refs),
        "missingSourceIdentities": len(missing),
        "selectedPortraitRefs": sorted(selected_refs),
        "structuralAnomalyPortraitRefs": sorted(anomaly_refs),
        "missingSourcePortraitRefs": sorted(item["portraitRef"] for item in missing),
        "desiredScaleRetainedAsFutureCeiling": True,
        "rootTimelineFallbackForbidden": True,
        "productionWrites": False,
    }


def rebind_v5(
    manifest_path: Path,
    inventory_path: Path,
    feedback_path: Path,
    exclusion_paths: list[str],
    desired_shard_size: int,
) -> None:
    manifest = core.verify_manifest(manifest_path)
    policy = manifest.get("sourceEnvelope", {}).get("sparseSourceAvailabilityPolicy")
    if not isinstance(policy, dict):
        raise core.PilotError("availability-clamped Fast6 manifest 缺 sparse policy")
    availability = availability_truth(inventory_path, exclusion_paths, manifest, desired_shard_size)
    policy["schema"] = POLICY_SCHEMA
    policy["v4ControllerSource"] = policy["controllerSource"]
    policy["controllerSource"] = core.artifact(CONTROLLER_PATH)
    policy["feedbackControllerSource"] = core.artifact(FEEDBACK_CONTROLLER_PATH)
    policy["desiredShardSize"] = desired_shard_size
    policy["effectiveShardSize"] = availability["effectiveShardSize"]
    policy["availabilityClamp"] = availability
    policy["availabilityLimited"] = True
    policy["maximumConcurrency"] = 6
    policy["fallbackMaximumConcurrency"] = 3
    policy["concurrencyMode"] = "controlled_fast6_pilot_with_automatic_fallback"
    feedback = verify_parent_feedback(feedback_path, desired_shard_size, int(policy["requestedSourceGroups"]))
    policy["fallbackTriggers"] = feedback["adaptiveScaling"]["concurrencyPilot"]["fallbackTriggers"]
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in (CONTROLLER_PATH, V4_CONTROLLER_PATH, FEEDBACK_CONTROLLER_PATH, feedback_path, inventory_path):
        record = core.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceEnvelope"]["sparseSourceAvailabilityPolicy"] = policy
    manifest["campaign"]["sparseSourceAvailabilityPolicy"] = policy
    manifest["campaign"]["desiredShardSize"] = desired_shard_size
    manifest["campaign"]["availabilityLimited"] = True
    manifest["campaign"]["serviceTierRecommendation"] = "fast"
    manifest["campaign"]["maxConcurrencyRecommendation"] = 6
    manifest["campaign"]["fallbackConcurrencyRecommendation"] = 3
    manifest["campaign"]["timeoutSecondsRecommendation"] = 600
    manifest["sourceDigest"] = core.sha256_bytes(core.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    core.write_json(manifest_path, manifest)


def verify_v5(manifest_path: Path) -> dict[str, Any]:
    with v3.patched_sparse_base(), contextlib.redirect_stdout(io.StringIO()):
        inherited = v2.verify_transitive(manifest_path)
    manifest = core.verify_manifest(manifest_path)
    envelope_policy = manifest.get("sourceEnvelope", {}).get("sparseSourceAvailabilityPolicy")
    campaign_policy = manifest.get("campaign", {}).get("sparseSourceAvailabilityPolicy")
    if not isinstance(envelope_policy, dict) or envelope_policy != campaign_policy:
        raise core.PilotError("availability-clamped sparse policy 顶层与 source envelope 漂移")
    policy = envelope_policy
    feedback_path = core.verify_artifact_record(policy.get("feedbackReport"), "availability clamp feedback")
    feedback = verify_parent_feedback(
        feedback_path,
        int(policy.get("desiredShardSize", 0)),
        int(policy.get("requestedSourceGroups", 0)),
    )
    inventory_path = core.verify_artifact_record(manifest["sourceEnvelope"].get("inventory"), "campaign inventory")
    input_paths = [
        str(core.verify_artifact_record(record, "availability clamp prior manifest"))
        for record in manifest["sourceEnvelope"]["transitiveExclusionPolicy"]["inputManifests"]
    ]
    availability = availability_truth(
        inventory_path,
        input_paths,
        manifest,
        int(policy.get("desiredShardSize", 0)),
    )
    selected_counts = manifest["campaign"]["selectedSourceCounts"]
    expected_batches = math.ceil(manifest["counts"]["identityCount"] / 4)
    if (
        policy.get("schema") != POLICY_SCHEMA
        or policy.get("controllerSource") != core.artifact(CONTROLLER_PATH)
        or policy.get("v4ControllerSource") != core.artifact(V4_CONTROLLER_PATH)
        or policy.get("v3ControllerSource") != core.artifact(v4.V3_CONTROLLER_PATH)
        or policy.get("v2ControllerSource") != core.artifact(v3.V2_CONTROLLER_PATH)
        or policy.get("baseControllerSource") != core.artifact(v3.BASE_CONTROLLER_PATH)
        or policy.get("feedbackControllerSource") != core.artifact(FEEDBACK_CONTROLLER_PATH)
        or policy.get("availabilityClamp") != availability
        or policy.get("availabilityLimited") is not True
        or policy.get("effectiveShardSize") != manifest["counts"]["identityCount"]
        or policy.get("actualSourceGroups") != len(selected_counts)
        or policy.get("actualSelectedSourceCounts") != selected_counts
        or policy.get("identityThroughputPreserved") is not True
        or policy.get("modelItemsPerGroup") != 4
        or policy.get("modelBatchCount") != expected_batches
        or len(manifest.get("modelBatches", [])) != expected_batches
        or policy.get("maximumConcurrency") != 6
        or policy.get("fallbackMaximumConcurrency") != 3
        or policy.get("fallbackTriggers") != feedback["adaptiveScaling"]["concurrencyPilot"]["fallbackTriggers"]
        or policy.get("linkageRootFallbackForbidden") is not True
        or policy.get("productionWrites") is not False
        or manifest["campaign"].get("desiredShardSize") != policy.get("desiredShardSize")
        or manifest["campaign"].get("availabilityLimited") is not True
    ):
        raise core.PilotError("availability-clamped Fast6 sparse policy gate 非法")
    return {
        **inherited,
        "status": "campaign_tail_shard_fast6_verified",
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "desiredIdentities": policy["desiredShardSize"],
        "effectiveIdentities": policy["effectiveShardSize"],
        "structuralAnomalies": availability["namedManStructuralAnomalies"],
        "missingSources": availability["missingSourceIdentities"],
        "modelBatches": policy["modelBatchCount"],
        "maximumConcurrency": 6,
        "fallbackMaximumConcurrency": 3,
        "productionReady": False,
    }


def prepare(args: argparse.Namespace) -> None:
    feedback_path = core.ensure_below(Path(args.feedback_report), base.ROOT, "feedback report")
    inventory_path = core.ensure_below(Path(args.inventory), base.PILOT_ROOT, "campaign inventory")
    verify_parent_feedback(feedback_path, int(args.requested_shard_size), int(args.source_groups))

    def clamped_feedback(_path: Path, _shard_size: int, source_groups: int) -> dict[str, Any]:
        if source_groups != int(args.source_groups):
            raise core.PilotError("availability clamp source group 漂移")
        return verify_parent_feedback(feedback_path, int(args.requested_shard_size), source_groups)

    original_feedback = v4.verify_feedback
    original_verify = v4.verify_v4
    try:
        v4.verify_feedback = clamped_feedback
        v4.verify_v4 = lambda _manifest_path: {"status": "availability_clamp_pending"}
        with contextlib.redirect_stdout(io.StringIO()):
            v4.prepare(args)
    finally:
        v4.verify_feedback = original_feedback
        v4.verify_v4 = original_verify
    output = core.ensure_below(Path(args.output), base.PILOT_ROOT, "availability-clamped shard output")
    manifest_path = output / "candidate-manifest.json"
    rebind_v5(
        manifest_path,
        inventory_path,
        feedback_path,
        args.exclude_manifest,
        int(args.requested_shard_size),
    )
    print(json.dumps(verify_v5(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_v5(core.ensure_below(Path(args.manifest), base.PILOT_ROOT, "tail shard manifest")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare-shard")
    prepare_parser.add_argument("--inventory", required=True)
    prepare_parser.add_argument("--output", required=True)
    prepare_parser.add_argument("--batch-id", required=True)
    prepare_parser.add_argument("--representative-closure", required=True)
    prepare_parser.add_argument("--profile")
    prepare_parser.add_argument("--requested-shard-size", type=int, required=True)
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
    except (core.PilotError, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"portrait campaign shard v5 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
