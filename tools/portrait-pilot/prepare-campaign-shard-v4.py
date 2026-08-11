#!/usr/bin/env python3
"""Prepare a 48-identity sparse campaign shard with a controlled Fast6 policy."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import math
import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


CONTROLLER_PATH = Path(__file__).resolve()
V3_CONTROLLER_PATH = CONTROLLER_PATH.with_name("prepare-campaign-shard-v3.py")
FEEDBACK_CONTROLLER_PATH = CONTROLLER_PATH.with_name("build-feedback-calibration-v5.js")
POLICY_SCHEMA = "cf7.portrait-pilot-sparse-source-availability.v2"
FEEDBACK_SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v5"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


v3 = load_module(V3_CONTROLLER_PATH, "cf7_portrait_campaign_shard_v3")
core = v3.core
base = v3.base


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
    profile = scaling.get("executionProfile", {})
    pilot = scaling.get("concurrencyPilot", {})
    if (
        feedback.get("schema") != FEEDBACK_SCHEMA
        or feedback.get("status") != "human_feedback_calibrated"
        or feedback.get("productionReady") is not False
        or scaling.get("recommendedNextShardSize") != shard_size
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
        or override.get("targetShardSize") != shard_size
        or override.get("targetSourceGroups") != requested_source_groups
    ):
        raise core.PilotError("feedback Fast6/48 身份指令与 sparse shard 请求不一致")
    return feedback


@contextmanager
def patched_v3() -> Iterator[None]:
    original_controller = v3.CONTROLLER_PATH
    original_policy_schema = v3.POLICY_SCHEMA
    original_feedback_schema = v3.FEEDBACK_SCHEMA
    original_verify_feedback = v3.verify_feedback
    try:
        v3.CONTROLLER_PATH = CONTROLLER_PATH
        v3.POLICY_SCHEMA = POLICY_SCHEMA
        v3.FEEDBACK_SCHEMA = FEEDBACK_SCHEMA
        v3.verify_feedback = verify_feedback
        yield
    finally:
        v3.CONTROLLER_PATH = original_controller
        v3.POLICY_SCHEMA = original_policy_schema
        v3.FEEDBACK_SCHEMA = original_feedback_schema
        v3.verify_feedback = original_verify_feedback


def rebind_v4(manifest_path: Path, feedback_path: Path) -> None:
    manifest = core.verify_manifest(manifest_path)
    policy = manifest.get("sourceEnvelope", {}).get("sparseSourceAvailabilityPolicy")
    if not isinstance(policy, dict):
        raise core.PilotError("Fast6 sparse manifest 缺 policy")
    policy["schema"] = POLICY_SCHEMA
    policy["controllerSource"] = core.artifact(CONTROLLER_PATH)
    policy["v3ControllerSource"] = core.artifact(V3_CONTROLLER_PATH)
    policy["feedbackControllerSource"] = core.artifact(FEEDBACK_CONTROLLER_PATH)
    policy["maximumConcurrency"] = 6
    policy["fallbackMaximumConcurrency"] = 3
    policy["concurrencyMode"] = "controlled_fast6_pilot_with_automatic_fallback"
    policy["fallbackTriggers"] = verify_feedback(
        feedback_path,
        int(policy["requestedShardSize"]),
        int(policy["requestedSourceGroups"]),
    )["adaptiveScaling"]["concurrencyPilot"]["fallbackTriggers"]
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in (CONTROLLER_PATH, V3_CONTROLLER_PATH, FEEDBACK_CONTROLLER_PATH, feedback_path):
        record = core.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceEnvelope"]["sparseSourceAvailabilityPolicy"] = policy
    manifest["campaign"]["sparseSourceAvailabilityPolicy"] = policy
    manifest["campaign"]["serviceTierRecommendation"] = "fast"
    manifest["campaign"]["maxConcurrencyRecommendation"] = 6
    manifest["campaign"]["fallbackConcurrencyRecommendation"] = 3
    manifest["campaign"]["timeoutSecondsRecommendation"] = 600
    manifest["sourceDigest"] = core.sha256_bytes(core.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    core.write_json(manifest_path, manifest)


def verify_v4(manifest_path: Path) -> dict[str, Any]:
    with v3.patched_sparse_base(), contextlib.redirect_stdout(io.StringIO()):
        inherited = v3.v2.verify_transitive(manifest_path)
    manifest = core.verify_manifest(manifest_path)
    envelope_policy = manifest.get("sourceEnvelope", {}).get("sparseSourceAvailabilityPolicy")
    campaign_policy = manifest.get("campaign", {}).get("sparseSourceAvailabilityPolicy")
    if not isinstance(envelope_policy, dict) or envelope_policy != campaign_policy:
        raise core.PilotError("Fast6 sparse policy 顶层与 source envelope 漂移")
    policy = envelope_policy
    feedback_path = core.verify_artifact_record(policy.get("feedbackReport"), "Fast6 sparse feedback")
    feedback = verify_feedback(
        feedback_path,
        int(policy.get("requestedShardSize", 0)),
        int(policy.get("requestedSourceGroups", 0)),
    )
    selected_counts = manifest["campaign"]["selectedSourceCounts"]
    expected_batches = math.ceil(manifest["counts"]["identityCount"] / 4)
    if (
        policy.get("schema") != POLICY_SCHEMA
        or policy.get("controllerSource") != core.artifact(CONTROLLER_PATH)
        or policy.get("v3ControllerSource") != core.artifact(V3_CONTROLLER_PATH)
        or policy.get("v2ControllerSource") != core.artifact(v3.V2_CONTROLLER_PATH)
        or policy.get("baseControllerSource") != core.artifact(v3.BASE_CONTROLLER_PATH)
        or policy.get("feedbackControllerSource") != core.artifact(FEEDBACK_CONTROLLER_PATH)
        or policy.get("actualSourceGroups") != len(selected_counts)
        or policy.get("actualSelectedSourceCounts") != selected_counts
        or policy.get("identityThroughputPreserved") is not True
        or policy.get("modelItemsPerGroup") != 4
        or policy.get("modelBatchCount") != expected_batches
        or len(manifest.get("modelBatches", [])) != expected_batches
        or policy.get("maximumConcurrency") != 6
        or policy.get("fallbackMaximumConcurrency") != 3
        or policy.get("concurrencyMode") != "controlled_fast6_pilot_with_automatic_fallback"
        or policy.get("fallbackTriggers") != feedback["adaptiveScaling"]["concurrencyPilot"]["fallbackTriggers"]
        or policy.get("linkageRootFallbackForbidden") is not True
        or policy.get("productionWrites") is not False
        or manifest["campaign"].get("maxConcurrencyRecommendation") != 6
        or manifest["campaign"].get("fallbackConcurrencyRecommendation") != 3
        or feedback["adaptiveScaling"]["recommendedNextShardSize"] != manifest["counts"]["identityCount"]
    ):
        raise core.PilotError("Fast6 sparse source availability policy gate 非法")
    return {
        **inherited,
        "status": "campaign_sparse_shard_fast6_verified",
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "identities": manifest["counts"]["identityCount"],
        "requestedSourceGroups": policy["requestedSourceGroups"],
        "actualSourceGroups": policy["actualSourceGroups"],
        "modelBatches": policy["modelBatchCount"],
        "maximumConcurrency": 6,
        "fallbackMaximumConcurrency": 3,
        "productionReady": False,
    }


def prepare(args: argparse.Namespace) -> None:
    feedback_path = core.ensure_below(Path(args.feedback_report), base.ROOT, "feedback report")
    verify_feedback(feedback_path, int(args.shard_size), int(args.source_groups))
    with patched_v3(), v3.patched_sparse_base(), contextlib.redirect_stdout(io.StringIO()):
        v3.v2.prepare(args)
        output = core.ensure_below(Path(args.output), base.PILOT_ROOT, "Fast6 sparse shard output")
        manifest_path = output / "candidate-manifest.json"
        v3.bind_sparse_policy(manifest_path, feedback_path)
    rebind_v4(manifest_path, feedback_path)
    print(json.dumps(verify_v4(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_v4(core.ensure_below(Path(args.manifest), base.PILOT_ROOT, "Fast6 sparse manifest")), ensure_ascii=False))


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
    except (core.PilotError, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"portrait campaign shard v4 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
