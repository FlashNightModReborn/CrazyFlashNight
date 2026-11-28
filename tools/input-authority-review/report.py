"""Build a fail-closed R5 qualification report from existing runners and raw observations."""

import argparse
import json
from pathlib import Path
import subprocess
from xml.etree import ElementTree

from entry import read_entry
from consumers import read_bounty_recovery
from edited_close import read_edited_close
from journeys import read_focus_audit, read_global_panels, read_native_editors, read_passive_session
from hud_pixels import read_hud_capture
from materials import combined_material, read_material_session
from wgc_game import read_g2, read_game_wgc
from evidence import (
    candidate_identity, digest, focused_groups, identities_match, legacy_latency, link,
    read_asloader, read_candidate_verification, read_consumer_review, read_domain, read_focus, read_json, read_live,
    read_native, read_original_route, read_smoke, read_startup, same_hash, paired_ordinary_latency,
)


LIVE_OBSERVATIONS = {
    "G04": ("R1-P01",), "G07": ("R1-P11", "R5-G58"), "G08": ("R5-G58",),
    "G14": ("R1-P01",), "G15": ("R1-P01", "R1-P05"), "G17": ("R1-P02",),
    "G19": ("R1-P01",), "G20": ("R5-G53",), "G22": ("R1-P08",),
    "G23": ("R1-P06", "R1-P07"), "G24": ("R1-P09", "R1-P12"),
    "G25": ("R1-P09",), "G26": ("R1-P09",), "G29": ("R1-P04",),
    "G32": ("R1-P04",), "G33": ("R1-P11",), "G34": ("R1-P05", "R1-P12"),
    "G36": ("R1-P05",), "G38": ("R1-P10",), "G41": ("R1-P10",),
    "G43": ("R1-P12",), "G49": ("R1-P11",), "G53": ("R5-G53",),
    "G55": ("R5-G55-G57",), "G56": ("R5-G55-G57",), "G57": ("R5-G55-G57",),
    "G58": ("R5-G58",),
}

SUPPORTING_CHECKS = {
    "G01": ("candidateVerification",), "G02": ("historicalRetirement", "currentRetirement"),
    "G03": ("consumerClosure", "consumerReview", "bountyRecovery", "asLoader", "materialSession"),
    "G04": ("focus", "focusAudit", "chainBusinessFocus"),
    "G05": ("focused", "native", "focus", "passiveSession", "focusAudit"), "G06": ("asLoader",), "G09": ("sceneFixture",),
    "G12": ("M-EDIT-EXIT",), "G13": ("sceneFixture",),
    "G14": ("asLoader",), "G16": ("consumerClosure", "consumerReview"), "G17": ("bountyRecovery", "focusAudit"),
    "G19": ("liveWgc", "wgcFixture"), "G20": ("sceneFixture", "wgcFixture"),
    "G29": ("native",), "G32": ("bountyRecovery",), "G33": ("M-DOMAIN", "M-CANCEL-LOCAL", "bountyRecovery"),
    "G38": ("M-DOMAIN", "M-ENTRY"), "G39": ("M-PRESENT-HUD",), "G40": ("M-EDIT-EXIT", "nativeEditors"), "G45": ("sceneFixture",),
    "G46": ("globalPanelRoutes",),
    "G49": ("native",), "G51": ("latency",), "G52": ("sceneFixture",),
    "G54": ("consumerClosure", "consumerReview", "bountyRecovery"),
    "G55": ("focus", "focusAudit", "chainBusinessFocus", "historicalRetirement", "currentRetirement"),
    "G56": ("historicalRetirement", "currentRetirement"), "G57": ("historicalRetirement", "currentRetirement"),
    "G58": ("originalMapRoute",),
    "G59": ("candidateVerification", "asLoader", "live", "startup", "materialSession"), "G60": ("M-ENTRY", "M-PRESENT-HUD", "M-EDIT-EXIT"),
}

REQUIRED_STIMULUS = {"T4": "wgc", "T5": "operator-physical", "T6": "maintainer"}
RETIREMENT_PARTS = ("productionInbound", "replacementBehavior", "runtimeZeroOrNarrow")
FOCUSED_TEST_CASES = {
    "G09": ("SceneTransitionResumeTests",), "G10": ("L0AdversarialTests",),
    "G11": ("PanelCloseTransactionTests",), "G12": ("WindowManagerFocusRestoreTests",),
    "G13": ("SceneTransitionResumeTests", "PanelHostSceneTransitionAdmissionTests"),
    "G28": ("PhysicalInputLedgerTests",), "G30": ("WorldPointerBridgeBoundaryTests",),
    "G33": ("R1UiAdapterTests",), "G35": ("R1AdversarialTests", "R2ProtocolAndReducerMutationTests"),
    "G37": ("R2ProtocolAndReducerMutationTests",), "G38": ("R1UiAdapterTests",),
    "G39": ("PlayerInfoSplitSurfaceTests", "PlayerHudVisualTests", "NativeDialogueWidgetTests"),
    "G40": ("ModifierEditorReleasesItsLeaseOnEscapeAndClickOutsideTheEditor",),
    "G41": ("R1UiAdapterTests", "R3ConsumerCutoverTests"), "G44": ("KeyboardHookStateTests",),
    "G46": ("PanelCloseTransactionTests", "WebOverlayFormPanelCloseTests"),
    "G47": ("R1UiAdapterTests", "R3ConsumerCutoverTests"),
    "G50": ("DesktopCursorForegroundGuardTests",), "G52": ("OpaqueHudGpuTests",),
    "G55": ("R4RetirementZeroCallTests",),
}


def safe_evidence(label, load, *args):
    try:
        return load(*args)
    except (OSError, ValueError, KeyError, IndexError, TypeError, AttributeError, ElementTree.ParseError) as error:
        return {"status": "BLOCKED", "reason": f"{label}: {error}"}


def collect_evidence(spec, evidence_root, root, expected):
    def path(key):
        return (evidence_root / spec[key]).resolve()

    def optional(key, load, *args):
        return safe_evidence(key, load, path(key), *args) if spec.get(key) else {"status": "NOT_RUN"}

    verification = optional("candidateVerification", read_candidate_verification, expected)
    live = optional("live", read_live, expected, path("liveHostLauncherLog") if spec.get("liveHostLauncherLog") else None)
    live_focus = live.get("focusPartition") or {}
    chain_business = {"status": live_focus.get("businessStatus", live["status"]), "raw": live.get("raw"),
                      "fullLifecycleStatus": live_focus.get("lifecycleStatus")}
    desktop = optional("smokeDesktop", read_json) if spec.get("smokeDesktop") else None
    focused = safe_evidence("focused", focused_groups,
                            [(evidence_root / name).resolve() for name in spec.get("focusedRuns", [])],
                            root, spec.get("requiredFocusedTests", []))
    domain = optional("domain", read_domain, expected)
    local_cancel = {"status": domain.get("localCancellation", domain["status"]), "raw": domain.get("raw")}
    startup = optional("startupProcess", read_startup, expected)
    passive_session = optional("passiveSession", read_passive_session, expected, startup)
    material_session = optional("materialManifest", read_material_session, root, expected, startup)
    bounty = (safe_evidence("authored drag recovery", read_bounty_recovery, path("bountyLive"), path("bountyObserverCompile"),
                           path("bountyProductionProof"), root, expected, startup, material_session)
              if all(spec.get(key) for key in ("bountyLive", "bountyObserverCompile", "bountyProductionProof")) else {"status": "NOT_RUN"})
    edited_close = (safe_evidence("edited close", read_edited_close, path("editedClose"), path("editedCloseAs2"), expected, startup)
                    if spec.get("editedClose") and spec.get("editedCloseAs2") else {"status": "NOT_RUN"})
    wgc = (safe_evidence("G2 WGC fixture", read_g2, path("wgcFixtureSummary"), path("wgcFixturePreparation"), expected,
                         path("wgcFixtureRun") if spec.get("wgcFixtureRun") else None)
           if spec.get("wgcFixtureSummary") and spec.get("wgcFixturePreparation") else {"status": "NOT_RUN"})
    latency = (safe_evidence("ordinary latency", paired_ordinary_latency, path("ordinaryLatencyBaseline"),
                            path("ordinaryLatencyCandidate"), expected,
                            path("ordinaryLatencyPairPlan") if spec.get("ordinaryLatencyPairPlan") else None,
                            path("ordinaryLatencyBaselineAnchor") if spec.get("ordinaryLatencyBaselineAnchor") else None)
               if spec.get("ordinaryLatencyBaseline") and spec.get("ordinaryLatencyCandidate") else
               optional("legacyLatency", legacy_latency))
    known = {"candidateVerification": verification, "focused": focused, "live": live, "chainBusinessFocus": chain_business, "M-DOMAIN": domain,
             "M-CANCEL-LOCAL": local_cancel, "M-ENTRY": optional("entry", read_entry, expected),
             "M-PRESENT-HUD": optional("hudCapture", read_hud_capture, expected),
             "M-EDIT-EXIT": edited_close,
             "materialSession": material_session, "bountyRecovery": bounty,
             "nativeEditors": optional("nativeEditors", read_native_editors, expected, startup),
             "globalPanelRoutes": optional("globalPanelRoutes", read_global_panels, expected, startup),
             "passiveSession": passive_session, "focusAudit": optional("focusAudit", read_focus_audit, expected, startup, passive_session),
             "startup": startup, "liveWgc": optional("liveGpuTrace", read_game_wgc, expected, startup), "wgcFixture": wgc,
             "originalMapRoute": optional("originalMapRoute", read_original_route, expected, startup),
             "native": optional("native", read_native, expected), "sceneFixture": optional("smoke", read_smoke, expected, desktop),
             "asLoader": optional("asLoader", read_asloader, root), "focus": optional("focus", read_focus, expected),
             "latency": latency, "consumerClosure": optional("consumerClosure", archived_consumers),
             "consumerReview": optional("consumerReview", read_consumer_review, root, expected),
             "historicalRetirement": optional("historicalRetirement", archived_retirement),
             "currentRetirement": optional("currentRetirement", archived_retirement)}
    return known


def archived_consumers(file):
    data = read_json(file)
    return {"status": "BLOCKED", "closedByThisReceipt": False, "raw": link(file),
            "productionBlockers": data.get("r3ProductionBlockers"), "coverageGaps": data.get("coverageGaps"),
            "evidenceLevel": data.get("evidenceLevel")}


def archived_retirement(file):
    data = read_json(file)
    items = {row["retirementId"]: {"disposition": row.get("disposition"), "proofCase": row.get("verificationCase")}
             for row in data["items"]}
    static_ok = (len(items) == 26 and data.get("blockedRetirementIds") == [] and
                 all(row["disposition"] in ("STATIC_ZERO", "STATIC_NARROWED") for row in items.values()))
    return {"status": "BLOCKED", "raw": link(file), "scannedSource": data.get("sourceIdentity"),
            "scannedFileCount": data.get("sourceFilesScanned"), "scanBlockedItems": data.get("blockedRetirementIds"),
            "staticScanStatus": "PASS" if static_ok else "BLOCKED", "items": items}


def independent_reviews(path, expected, criteria):
    if not path:
        return {}
    document = read_json(path)
    candidate = document.get("candidate")
    chosen_material = expected.get("combinedMaterialSha256")
    if (document.get("schema") != "cf7-input-authority-independent-reviews.v1" or not document.get("reviewer") or
            not identities_match(candidate, expected) or
            (chosen_material and not same_hash(candidate.get("combinedMaterialSha256"), chosen_material))):
        raise ValueError("Independent review must name a reviewer and match the selected candidate identity.")
    allowed = {(row["id"], part) for row in criteria["gates"] for part in row["levels"]}
    allowed.update((row["id"], part) for row in criteria["retirements"] for part in RETIREMENT_PARTS)
    valid = {}
    for row in document.get("reviews", []):
        part = row["part"]
        key = (row["id"], part)
        if key not in allowed:
            raise ValueError(f"Unknown review gate or part: {key}.")
        if key in valid:
            raise ValueError(f"Duplicate independent review for {key}; keep older reviews in their original files.")
        artifacts = []
        for source in row.get("raw", []):
            artifact = (path.parent / source["path"]).resolve()
            if not same_hash(digest(artifact), source.get("sha256")) or not source.get("locator"):
                raise ValueError(f"Raw path/hash/locator mismatch for {key}.")
            artifacts.append({**source, "path": str(artifact)})
        valid_statuses = ("PASS", "FAIL", "BLOCKED", "NOT_APPLICABLE") if key == ("G18", "T1") else ("PASS", "FAIL", "BLOCKED")
        if (not artifacts or not row.get("reason") or row.get("status") not in valid_statuses or
                (part in REQUIRED_STIMULUS and row.get("stimulus") != REQUIRED_STIMULUS[part])):
            raise ValueError(f"Incomplete scoped independent review for {key}.")
        valid[key] = {**row, "raw": artifacts, "reviewer": document["reviewer"], "reviewReceipt": str(path)}
    return valid


def qualification(parts, references, reviews):
    if any(row["status"] == "FAIL" for row in reviews.values()) or any(row["status"] == "FAIL" for row in references):
        return "FAIL"
    if all(reviews.get(part, {}).get("status") == "PASS" for part in parts):
        return "PASS"
    return "BLOCKED" if reviews or any(row["status"] != "NOT_RUN" for row in references) else "NOT_RUN"


def focused_observations(runs, gate_id):
    patterns = FOCUSED_TEST_CASES.get(gate_id, ())
    for run in runs:
        if not run.get("sourceAndLoadedTestBinariesBound"):
            continue
        tests = [row for row in run["tests"] if any(pattern in row["name"] for pattern in patterns)]
        if tests:
            statuses = {row["status"] for row in tests}
            state = "FAIL" if "FAIL" in statuses else "BLOCKED" if statuses & {"NOT_RUN", "BLOCKED"} else "PASS"
            yield {"check": "focused-tests", "status": state, "tests": [row["name"] for row in tests], "raw": run["raw"]}


def gate_matrix(criteria, receipts, reviews):
    matrix = {}
    live = receipts["live"]
    for row in criteria["gates"]:
        gate_id = row["id"]
        refs = [{"check": key, "status": receipts[key]["status"], "raw": receipts[key].get("raw")}
                for key in SUPPORTING_CHECKS.get(gate_id, ())]
        refs.extend(focused_observations(receipts["focused"].get("runs", []), gate_id))
        if gate_id in LIVE_OBSERVATIONS and live["status"] == "PASS":
            for case in LIVE_OBSERVATIONS[gate_id]:
                checks = live.get("caseChecks", {}).get(case) or {}
                # Probes are scoped observations. An actual failure is retained; a pass does not cover other stimuli.
                state = ("FAIL" if "FAIL" in checks.values() else "PASS" if checks and set(checks.values()) == {"PASS"}
                         else "BLOCKED" if checks else "NOT_RUN")
                refs.append({"check": case, "status": state, "checks": checks,
                             "rawChecks": live.get("rawCaseChecks", {}).get(case), "raw": live["raw"]})
        review = {part: reviews[(gate_id, part)] for part in row["levels"] if (gate_id, part) in reviews}
        # Fixture outcomes are reviewed separately before attributing a live product failure.
        gate_refs = [ref for ref in refs if ref["check"] != "sceneFixture"]
        status = qualification(row["levels"], gate_refs, review)
        if status == "NOT_RUN" and any(ref["status"] != "NOT_RUN" for ref in refs):
            status = "BLOCKED"
        verified_disabled = (live["status"] == "PASS" and live.get("profile") == "disabled_unconditional_default" and
                             live.get("caseChecks", {}).get("R1-P01", {}).get("windowProfile") == "PASS")
        if gate_id == "G18" and (verified_disabled or review.get("T1", {}).get("status") == "NOT_APPLICABLE"):
            status = "NOT_APPLICABLE"
        matrix[gate_id] = {**row, "status": status, "observations": refs, "independentReviews": review,
                           "missingLevels": [] if status == "NOT_APPLICABLE" else
                           [part for part in row["levels"] if review.get(part, {}).get("status") != "PASS"]}
    return matrix


def retirement_matrix(criteria, receipts, reviews, gates):
    matrix = {}
    history = receipts["historicalRetirement"].get("items", {})
    current = receipts["currentRetirement"].get("items", {})
    for row in criteria["retirements"]:
        item = row["id"]
        review = {part: reviews[(item, part)] for part in RETIREMENT_PARTS if (item, part) in reviews}
        old = history.get(item)
        current_static = current.get(item)
        notes = [{"status": "BLOCKED"}] if old or current_static else []
        matrix[item] = {**row, "status": qualification(RETIREMENT_PARTS, notes, review), "originalStaticDisposition": old,
                        "currentStaticDisposition": current_static,
                        "linkedGateStatuses": {gate: gates[gate]["status"] for gate in row["gates"]},
                        "independentReviews": review,
                        "missingParts": [part for part in RETIREMENT_PARTS if review.get(part, {}).get("status") != "PASS"]}
    return matrix


def result_summary(receipts, gates, retirements):
    closure = receipts["candidateVerification"]
    executed_statuses = {receipts["live"]["status"], receipts["startup"]["status"]}
    executed = "PASS" if "PASS" in executed_statuses else "BLOCKED" if "BLOCKED" in executed_statuses else "NOT_RUN"
    if "FAIL" in (closure["status"], receipts["asLoader"]["status"]):
        compiled = "FAIL"
    elif closure.get("worktreeCoherent") and receipts["asLoader"]["status"] == "PASS":
        compiled = "PASS"
    else:
        compiled = "BLOCKED"
    complete = [row["status"] for row in (*gates.values(), *retirements.values())]
    repair_checks = ("M-DOMAIN", "M-CANCEL-LOCAL", "M-ENTRY", "M-PRESENT-HUD", "M-EDIT-EXIT", "focused", "native", "sceneFixture")
    if "FAIL" in complete or any(receipts[key]["status"] == "FAIL" for key in ("M-DOMAIN", "M-CANCEL-LOCAL", "M-ENTRY")):
        e2e = "FAIL"
    elif (complete and all(state in ("PASS", "NOT_APPLICABLE") for state in complete) and
          closure.get("worktreeCoherent") and executed == "PASS" and compiled == "PASS" and
          receipts["materialSession"]["status"] in ("PASS", "NOT_RUN") and
          all(receipts[key]["status"] == "PASS" for key in repair_checks)):
        e2e = "PASS"
    else:
        e2e = "BLOCKED"
    return {"compiled": compiled, "candidate_built": closure["status"], "candidate_executed": executed,
            "e2e_verified": e2e, "promoted": "NOT_DEPLOYED", "standard_entry_verified": "NOT_RUN"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--candidate-root", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True, help="Input evidence index. Relative paths resolve beside the index.")
    parser.add_argument("--output", type=Path, required=True, help="New report file. Existing evidence is preserved.")
    parser.add_argument("--require", action="append", default=[], help="Require one gate or check to pass. May repeat.")
    args = parser.parse_args()
    root = args.project_root.resolve(strict=True)
    spec_file = args.evidence.resolve(strict=True)
    if args.output.exists():
        parser.error("Use a new output path to retain prior reports.")
    spec = read_json(spec_file)
    if spec.get("schema") != "cf7-input-authority-evidence.v1":
        parser.error("Expected cf7-input-authority-evidence.v1.")
    criteria_file = Path(__file__).with_name("criteria.json")
    criteria = read_json(criteria_file)
    expected = candidate_identity(root, args.candidate_root.resolve(strict=True))
    if spec.get("materialManifest"):
        expected["combinedMaterialSha256"] = combined_material(read_json(spec_file.parent / spec["materialManifest"]))
    refs = collect_evidence(spec, spec_file.parent, root, expected)
    reviews_file = (spec_file.parent / spec["independentReviews"]).resolve() if spec.get("independentReviews") else None
    reviews = independent_reviews(reviews_file, expected, criteria)
    gates = gate_matrix(criteria, refs, reviews)
    retirements = retirement_matrix(criteria, refs, reviews, gates)
    states = result_summary(refs, gates, retirements)
    checks = {key: value["status"] for key, value in (refs | gates | retirements).items()} | states
    unknown = set(args.require) - checks.keys()
    if unknown:
        parser.error(f"Unknown check IDs: {', '.join(sorted(unknown))}")
    unmet = {key: checks[key] for key in args.require if checks[key] != "PASS"}
    report = {"schema": "cf7-input-authority-qualification.v1", "candidate": expected,
              "criteria": link(criteria_file), "evidenceIndex": link(spec_file), "states": states,
              "gates": gates, "retirements": retirements, "receipts": refs, "requiredUnmet": unmet}
    with args.output.open("x", encoding="utf-8", newline="\n") as output:
        json.dump(report, output, ensure_ascii=False, indent=2)
        output.write("\n")
    print(json.dumps({"states": states, "requiredUnmet": unmet, "output": str(args.output.resolve())}, ensure_ascii=False))
    return 1 if unmet or "FAIL" in checks.values() else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as exception:
        raise SystemExit(str(exception)) from exception
