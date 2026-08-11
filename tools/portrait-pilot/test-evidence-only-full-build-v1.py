#!/usr/bin/env python3
"""Prove the in-process base+supplement build uses the exact committed evidence set.

The supplement controller normally re-runs four historical Node/Python
verifiers.  Those subprocesses have their own source-input contracts and were
covered by the real normal supplement promotion plus their standalone checks;
an audit hook in this process cannot observe their filesystem access.  This
regression therefore stubs only that verifier dispatch and proves the
promotion build/check path, including a fresh phase-two evidence state, never
reads live PILOT_ROOT.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SUPPLEMENT_CONTROLLER = Path(__file__).with_name("promote-arena-portrait-supplement-v1.py")


class EvidenceOnlyBuildError(RuntimeError):
    pass


def load_supplement_controller() -> Any:
    spec = importlib.util.spec_from_file_location("cf7_evidence_only_full_build", SUPPLEMENT_CONTROLLER)
    if spec is None or spec.loader is None:
        raise EvidenceOnlyBuildError("无法加载 Arena supplement controller")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run() -> dict[str, Any]:
    os.environ["CF7_PORTRAIT_EVIDENCE_ONLY"] = "1"
    S = load_supplement_controller()
    P = S.P
    T = S.T
    pilot_root = T.PILOT_ROOT.resolve()
    observed: set[str] = set()
    blocked_events: list[str] = []

    def record_path(path: Path) -> None:
        resolved = path.resolve()
        materialized = T._MATERIALIZED_ARTIFACTS.get(resolved)
        if isinstance(materialized, dict) and isinstance(materialized.get("path"), str):
            logical = materialized["path"]
        else:
            try:
                logical = resolved.relative_to(ROOT).as_posix()
            except ValueError:
                return
        observed.add(logical)

    original_resolve_input_path = T.resolve_input_path
    original_verify_artifact_record = T.verify_artifact_record
    original_artifact = T.artifact

    def traced_resolve_input_path(path: Path, label: str) -> Path:
        record_path(path)
        return original_resolve_input_path(path, label)

    def traced_verify_artifact_record(record: Any, label: str) -> Path:
        if isinstance(record, dict) and isinstance(record.get("path"), str):
            logical = record["path"]
            observed.add(logical)
        return original_verify_artifact_record(record, label)

    def traced_artifact(path: Path) -> dict[str, Any]:
        record_path(path)
        return original_artifact(path)

    T.resolve_input_path = traced_resolve_input_path
    T.verify_artifact_record = traced_verify_artifact_record
    T.artifact = traced_artifact

    # Keep the filesystem audit claim honest: Python audit hooks are not
    # inherited by the four historical-verifier subprocesses.  They are
    # covered by real normal supplement promotion and standalone checks; this
    # test covers the in-process consumer and exact immutable-evidence closure.
    S.verify_input_controllers = lambda *_args, **_kwargs: None

    def audit_hook(event: str, args: tuple[Any, ...]) -> None:
        if event not in {"open", "os.listdir", "os.scandir"} or not args:
            return
        raw = args[0]
        if not isinstance(raw, (str, bytes, os.PathLike)):
            return
        try:
            resolved = Path(os.fsdecode(raw)).resolve()
            resolved.relative_to(pilot_root)
        except (OSError, TypeError, ValueError):
            return
        blocked_events.append(f"{event}:{resolved}")
        raise EvidenceOnlyBuildError(f"evidence-only 禁止读取 live PILOT_ROOT：{event}:{resolved}")

    with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as directory:
        test_root = Path(directory)
        cache_root = test_root / "system-temp"
        cache_root.mkdir()
        tempfile.tempdir = str(cache_root)
        sys.addaudithook(audit_hook)

        base = test_root / "base"
        base.mkdir()
        original_default_output = T.DEFAULT_OUTPUT
        base_manifest = P.build_pack(
            T.DEFAULT_INVENTORY,
            P.DEFAULT_CAMPAIGN,
            T.DEFAULT_REPRESENTATIVE_CLOSURE,
            T.DEFAULT_TEAM_GAP_BATCH,
            base,
            logical_output=base,
        )
        P.check_manifest(base / "manifest.json", logical_output=base)

        phase_one_state = T._load_evidence_state()
        supplemental_master_paths = {
            "tmp/portrait-pilot/arena-direct-gap-localization-r215-five-fast3-20260809T211500Z/renders-v1/proposal/R01/master-512.png",
            "tmp/portrait-pilot/arena-direct-gap-localization-r215-five-fast3-20260809T211500Z/renders-v1/proposal/R02/master-512.png",
            "tmp/portrait-pilot/arena-direct-gap-localization-r215-five-fast3-20260809T211500Z/renders-v1/proposal/R03/master-512.png",
            "tmp/portrait-pilot/arena-direct-gap-localization-r215-five-fast3-20260809T211500Z/renders-v1/proposal/R04/master-512.png",
            "tmp/portrait-pilot/arena-direct-gap-orientation-r217-r215-home-robot-20260809T162700Z/orientation-adjusted/R05/master-512.png",
        }
        for path in supplemental_master_paths:
            record = phase_one_state["recordsByPath"].get(path)
            if not isinstance(record, dict):
                raise EvidenceOnlyBuildError(f"supplement selected master 未 raw-captured：{path}")
            former_basis = base / "subjects" / f"{record['sha256'][:24].lower()}.png"
            if former_basis.exists():
                raise EvidenceOnlyBuildError(f"base-cleaned root 意外保留 supplement master basis：{former_basis}")

        # Model the real two-stage publication boundary: the base exact-fileset
        # is now the only runtime basis root, and no materialized evidence or
        # decoded pack state may leak into the supplement phase.
        T._EVIDENCE_STATE = None
        T._MATERIALIZED_ARTIFACTS.clear()
        phase_two_cache = test_root / "system-temp-phase-two"
        phase_two_cache.mkdir()
        tempfile.tempdir = str(phase_two_cache)
        T.DEFAULT_OUTPUT = base

        collected = S.collect_inputs(
            S.DEFAULT_REVIEW_BATCH,
            S.DEFAULT_ORIENTATION_BATCH,
            S.DEFAULT_ALIAS_BATCH,
        )
        supplemented = test_root / "supplemented"
        operational_evidence = test_root / "operational-evidence"
        supplemental_manifest = S.build_staging(
            base,
            supplemented,
            operational_evidence,
            collected,
            logical_output=base,
        )
        P.check_manifest(supplemented / "manifest.json", logical_output=base)
        T.DEFAULT_OUTPUT = original_default_output

        state = T._load_evidence_state()
        declared_all = set(state["allRecordsByPath"])
        declared = {
            path for path in state["allRecordsByPath"] if path.startswith("tmp/portrait-pilot/")
        }
        observed_pilot = {path for path in observed if path.startswith("tmp/portrait-pilot/")}
        missing = sorted(declared - observed_pilot)
        extra = sorted(observed_pilot - declared)
        if missing or extra:
            raise EvidenceOnlyBuildError(
                f"base+supplement evidence 请求集漂移：missing={missing} extra={extra}"
            )
        unused_declared = sorted(declared_all - observed)
        if unused_declared:
            raise EvidenceOnlyBuildError(f"immutable evidence 含未消费 records：{unused_declared}")
        if len(declared) != 560 or len(state["recordsByPath"]) != 353 or len(state["derivedMasterRecords"]) != 211:
            raise EvidenceOnlyBuildError(
                "evidence exact counts 漂移："
                f"pilot={len(declared)} explicit={len(state['recordsByPath'])} "
                f"derived={len(state['derivedMasterRecords'])}"
            )
        if blocked_events:
            raise EvidenceOnlyBuildError(f"发生 live PILOT_ROOT 读取：{blocked_events}")
        return {
            "status": "in_process_evidence_only_build_verified",
            "boundary": "historical verifier subprocesses excluded",
            "pilotArtifactPaths": len(declared),
            "allArtifactPaths": len(declared_all),
            "unusedArtifactPaths": 0,
            "explicitArtifactPaths": len(state["recordsByPath"]),
            "derivedMasterRecords": len(state["derivedMasterRecords"]),
            "baseAcceptedVariants": base_manifest["counts"]["humanAcceptedVariantCount"],
            "supplementAcceptedVariants": supplemental_manifest["counts"]["humanAcceptedVariantCount"],
            "inProcessLivePilotReads": 0,
        }


def main() -> int:
    try:
        print(json.dumps(run(), ensure_ascii=False, sort_keys=True))
        return 0
    except RuntimeError as error:
        print(f"[evidence-only-full-build] ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
