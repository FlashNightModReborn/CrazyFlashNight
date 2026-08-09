#!/usr/bin/env python3
"""Prepare a campaign shard while carrying prior exclusion closure transitively."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import sys
from pathlib import Path
from typing import Any


CONTROLLER_PATH = Path(__file__).resolve()
BASE_CONTROLLER_PATH = CONTROLLER_PATH.with_name("prepare_campaign.py")
POLICY_SCHEMA = "cf7.portrait-pilot-transitive-exclusion-policy.v1"


def load_base():
    spec = importlib.util.spec_from_file_location("cf7_portrait_prepare_campaign_base", BASE_CONTROLLER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 campaign controller：{BASE_CONTROLLER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load_base()
core = base.core
BASE_LOAD_EXCLUSIONS = base.load_exclusions


def manifest_path(value: str) -> Path:
    return core.ensure_below(Path(value), base.PILOT_ROOT, "传递排除 manifest")


def exclusion_closure(paths: list[str]) -> tuple[set[str], list[dict[str, object]]]:
    excluded: set[str] = set()
    records: list[dict[str, object]] = []
    for raw_path in paths:
        path = manifest_path(raw_path)
        manifest = core.verify_manifest(path)
        for item in manifest.get("reviewItems", []):
            if isinstance(item.get("portraitRef"), str):
                excluded.add(item["portraitRef"])
        campaign = manifest.get("campaign", {})
        for field in ("excludedPriorRefs",):
            for portrait_ref in campaign.get(field, []):
                if isinstance(portrait_ref, str):
                    excluded.add(portrait_ref)
        for anomaly in campaign.get("resolutionAnomalies", []):
            if isinstance(anomaly.get("portraitRef"), str):
                excluded.add(anomaly["portraitRef"])
        records.append(core.artifact(path))
    return excluded, records


def transitive_loader(paths: list[str]) -> tuple[set[str], list[dict[str, object]]]:
    excluded, records = BASE_LOAD_EXCLUSIONS(paths)
    carried, expected_records = exclusion_closure(paths)
    if records != expected_records:
        raise core.PilotError("基础排除 loader 与传递排除输入 artifact 漂移")
    excluded.update(carried)
    return excluded, records


def bind_policy(output_root: Path, input_paths: list[str]) -> Path:
    manifest_path_value = output_root / "candidate-manifest.json"
    manifest = core.verify_manifest(manifest_path_value)
    closure, input_records = exclusion_closure(input_paths)
    representative_refs, _ = base.load_representative_fixture()
    expected_prior = sorted(closure - representative_refs)
    if manifest.get("campaign", {}).get("excludedPriorRefs") != expected_prior:
        raise core.PilotError("prepared shard 没有完整承接传递排除集合")
    selected = {item.get("portraitRef") for item in manifest.get("reviewItems", [])}
    if selected & closure:
        raise core.PilotError("prepared shard 回流了已处理 identity")

    policy = {
        "schema": POLICY_SCHEMA,
        "controllerSource": core.artifact(CONTROLLER_PATH),
        "baseControllerSource": core.artifact(BASE_CONTROLLER_PATH),
        "inputManifests": input_records,
        "inputManifestCount": len(input_records),
        "transitivelyExcludedIdentityCount": len(expected_prior),
        "carriedCampaignExcludedPriorRefs": True,
        "selectedIdentityOverlapCount": 0,
        "productionWrites": False,
    }
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in (CONTROLLER_PATH, BASE_CONTROLLER_PATH):
        record = core.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceEnvelope"]["transitiveExclusionPolicy"] = policy
    manifest["campaign"]["transitiveExclusionPolicy"] = policy
    manifest["gates"]["transitivePriorExclusionsBound"] = True
    manifest["sourceDigest"] = core.sha256_bytes(core.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    core.write_json(manifest_path_value, manifest)
    return manifest_path_value


def verify_transitive(path: Path) -> dict[str, Any]:
    manifest, artifact_count = base.verify_shard(path)
    envelope_policy = manifest.get("sourceEnvelope", {}).get("transitiveExclusionPolicy")
    campaign_policy = manifest.get("campaign", {}).get("transitiveExclusionPolicy")
    if not isinstance(envelope_policy, dict) or envelope_policy != campaign_policy:
        raise core.PilotError("传递排除 policy 顶层与 source envelope 漂移")
    policy = envelope_policy
    if (
        policy.get("schema") != POLICY_SCHEMA
        or policy.get("controllerSource") != core.artifact(CONTROLLER_PATH)
        or policy.get("baseControllerSource") != core.artifact(BASE_CONTROLLER_PATH)
        or policy.get("carriedCampaignExcludedPriorRefs") is not True
        or policy.get("selectedIdentityOverlapCount") != 0
        or policy.get("productionWrites") is not False
        or manifest.get("gates", {}).get("transitivePriorExclusionsBound") is not True
    ):
        raise core.PilotError("传递排除 policy gate 非法")
    input_paths = [str(core.verify_artifact_record(record, "传递排除输入 manifest")) for record in policy.get("inputManifests", [])]
    if len(input_paths) != policy.get("inputManifestCount") or not input_paths:
        raise core.PilotError("传递排除输入 manifest 数不闭合")
    closure, records = exclusion_closure(input_paths)
    if records != policy.get("inputManifests"):
        raise core.PilotError("传递排除输入 manifest artifact 漂移")
    representative_refs, _ = base.load_representative_fixture()
    expected_prior = sorted(closure - representative_refs)
    selected = {item.get("portraitRef") for item in manifest.get("reviewItems", [])}
    if (
        manifest.get("campaign", {}).get("excludedPriorRefs") != expected_prior
        or policy.get("transitivelyExcludedIdentityCount") != len(expected_prior)
        or selected & closure
    ):
        raise core.PilotError("传递排除集合或新 identity disjoint gate 不闭合")
    return {
        "status": "campaign_shard_transitive_exclusions_verified",
        "manifest": core.repo_rel(path),
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "identities": manifest["counts"]["identityCount"],
        "sourceGroups": manifest["campaign"]["sourceGroups"],
        "transitivelyExcludedIdentities": len(expected_prior),
        "selectedIdentityOverlap": 0,
        "artifactCount": artifact_count + len(input_paths) + 2,
        "productionReady": False,
    }


def prepare(args: argparse.Namespace) -> None:
    if not args.exclude_manifest:
        raise core.PilotError("传递排除准备至少需要一个 --exclude-manifest")
    original_loader = base.load_exclusions
    original_file = base.__file__
    try:
        base.load_exclusions = transitive_loader
        base.__file__ = str(CONTROLLER_PATH)
        with contextlib.redirect_stdout(io.StringIO()):
            base.prepare_shard(args)
    finally:
        base.load_exclusions = original_loader
        base.__file__ = original_file
    output_root = core.ensure_below(Path(args.output), base.PILOT_ROOT, "campaign shard 输出目录")
    path = bind_policy(output_root, args.exclude_manifest)
    print(json.dumps(verify_transitive(path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(
        json.dumps(
            verify_transitive(core.ensure_below(Path(args.manifest), base.PILOT_ROOT, "campaign shard manifest")),
            ensure_ascii=False,
        )
    )


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    shard = commands.add_parser("prepare-shard")
    shard.add_argument("--inventory", required=True)
    shard.add_argument("--output", required=True)
    shard.add_argument("--batch-id", required=True)
    shard.add_argument("--representative-closure", required=True)
    shard.add_argument("--profile")
    shard.add_argument("--shard-size", type=int, default=12)
    shard.add_argument("--source-groups", type=int, default=3)
    shard.add_argument("--exclude-manifest", action="append", default=[])
    shard.set_defaults(handler=prepare)
    shard_check = commands.add_parser("check-shard")
    shard_check.add_argument("--manifest", required=True)
    shard_check.set_defaults(handler=check)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (core.PilotError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"portrait campaign shard v2 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
