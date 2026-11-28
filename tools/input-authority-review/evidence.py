"""Read independent input-authority qualification evidence without editing it."""

from collections import Counter
from datetime import datetime
from hashlib import file_digest
import json
from pathlib import Path
import re
from statistics import median
import subprocess
from xml.etree import ElementTree

from live_focus import checked_chain_cases, classify_chain_focus


SOURCE_INPUT_SCOPES = (
    "launcher/src", "launcher/tests", "launcher/contracts", "data/combat_visuals", "scripts/类定义",
)
PRIVATE_TEST_SOURCE_INPUT_SCOPES = (
    "global.json", "Directory.Packages.props", "launcher/CRAZYFLASHER7MercenaryEmpire.csproj",
    "launcher/resolve-dotnet.ps1", *SOURCE_INPUT_SCOPES,
)
ASLOADER_PATHS = {
    "resident": "scripts/asLoader.swf",
    "shared": "scripts/asLoaderShared.swf",
    "boot": "scripts/asLoaderLogic.swf",
}
TEST_BINARIES = ("launcher.tests.dll", "crazyflasher7mercenaryempire.core.dll")


def read_json(file):
    with Path(file).open(encoding="utf-8-sig") as stream:
        return json.load(stream)


def digest(file):
    with Path(file).open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest().upper()


def link(file):
    return {"path": str(file), "sha256": digest(file)}


def same_hash(first, second):
    return (isinstance(first, str) and isinstance(second, str) and
            re.fullmatch(r"[0-9a-f]{64}", first, re.I) is not None and first.upper() == second.upper())


def same_path(first, second):
    return isinstance(first, str) and isinstance(second, str) and Path(first).resolve() == Path(second).resolve()


def identities_match(actual, expected):
    return isinstance(actual, dict) and all(same_hash(actual.get(key), expected.get(key)) for key in
                                            ("buildIdentity", "payloadClosure", "coreSha256"))


def candidate_identity(root, candidate):
    # Keep candidate manifest/path parsing in the same implementation as the live runners.
    helper = root / "tools/lib/runtime-process-identity.js"
    command = "console.log(JSON.stringify(require(process.argv[1]).resolveExpectedRuntimeIdentity(process.argv[2],process.argv[3])))"
    value = json.loads(subprocess.check_output(
        ["node", "-e", command, str(helper), str(root), str(candidate)], encoding="utf-8"))
    return value


def read_candidate_verification(file, expected):
    data = read_json(file)
    matches = (data.get("schema") == "cf7-runtime-bundle-verification.v2" and
               same_hash(data.get("buildIdentityHash"), expected["buildIdentity"]) and
               same_hash(data.get("payloadClosureHash"), expected["payloadClosure"]))
    status = "BLOCKED"
    if matches:
        if data.get("passed") is False or data.get("state") == "invalid":
            status = "FAIL"
        elif data.get("passed") is True and type(data.get("files")) is int and data["files"] > 0:
            if data.get("state") in ("integrity-only", "coherent"):
                status = "PASS"
    return {"status": status, "identityMatched": matches,
            "worktreeCoherent": status == "PASS" and data.get("state") == "coherent" and data.get("mode") == "worktree",
            "verifiedFiles": data.get("files"), "raw": link(file)}


def read_trx(file):
    root = ElementTree.parse(file).getroot()
    rows = []
    for row in root.findall("./{*}Results/{*}UnitTestResult"):
        outcome = row.attrib["outcome"]
        status = {"Passed": "PASS", "NotExecuted": "NOT_RUN", "Skipped": "NOT_RUN"}.get(outcome, "FAIL")
        message = row.findtext("./{*}Output/{*}ErrorInfo/{*}Message")
        guard = re.search(r"^System\.OperationCanceledException\s*:\s*Resource qualification cancelled at .+? "
                          r"expired=(True|False) inputReadSucceeded=(True|False) expectedTick=(\d+) observedTick=(\d+)", message or "")
        if status == "FAIL" and guard and (guard[1] == "True" or guard[2] == "False" or guard[3] != guard[4]):
            status = "BLOCKED"
        rows.append({"id": row.attrib["testId"], "name": row.attrib["testName"], "status": status, "outcome": outcome,
                     **({"message": message} if message else {})})
    counters = root.find("./{*}ResultSummary/{*}Counters")
    storages = sorted({row.attrib["storage"] for row in root.findall("./{*}TestDefinitions/{*}UnitTest") if row.get("storage")})
    desktop_ready = any("desktopQuery=True receivesInput=1" in (row.findtext("./{*}Output/{*}StdOut") or "")
                        for row in root.findall("./{*}Results/{*}UnitTestResult"))
    return {"runId": root.attrib.get("id"), "tests": rows,
            "counters": dict(counters.attrib) if counters is not None else {},
            "observedCounts": dict(Counter(row["status"] for row in rows)), "raw": link(file),
            "testAssemblyStorage": storages, "inputDesktopPositiveControlObserved": desktop_ready}


def checked_out_sources(root, scopes=SOURCE_INPUT_SCOPES):
    result = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z", "--cached", "--others",
                                      "--exclude-standard", "--", *scopes])
    paths = set(result.decode("utf-8").split("\0")) - {""}
    return {file for file in paths if (root / file).is_file()}


def current_source_inputs(file, root, paths, digest_cache):
    records = read_json(file)
    file_paths = [row["path"] for row in records]
    if len(file_paths) != len(set(file_paths)) or set(file_paths) != paths:
        return False
    for record in records:
        path = record["path"]
        if path not in digest_cache:
            digest_cache[path] = digest(root / path)
        if not same_hash(record["sha256"], digest_cache[path]):
            return False
    return True


def focused_grounding(directory, root, paths, head, digest_cache):
    command = read_json(directory / "command.json")
    result = read_trx(directory / "recheck.trx")
    tests_assembly = str(root / "launcher/tests/bin/Release/Launcher.Tests.dll")
    stored_in_expected_assembly = bool(result["testAssemblyStorage"]) and all(
        same_path(storage, tests_assembly) for storage in result["testAssemblyStorage"])
    assemblies = command.get("testAssemblies") or {}
    recorded = {Path(name).name.lower(): value for name, value in assemblies.items()}
    pair = (recorded.get(TEST_BINARIES[0]), recorded.get(TEST_BINARIES[1]))
    pair = tuple(value.upper() for value in pair) if all(same_hash(value, value) for value in pair) else ()
    snapshots = (directory / "source-inputs-before.json").is_file()
    fingerprint = directory / ("source-inputs-before.json" if snapshots else "source-inputs.json")
    if not fingerprint.is_file():
        default_replay = (command.get("head") == head and same_path(command.get("repository"), str(root)) and
                          command.get("expectedInputDesktop") == "Default" and command.get("noBuild") is True and
                          command.get("runnerExitCode") == 0 and stored_in_expected_assembly and result["inputDesktopPositiveControlObserved"])
        return {**result, "status": "BLOCKED", "sameFinalSource": False, "sourceAndLoadedTestBinariesBound": False,
                "defaultReplayRequiresBuildAnchor": default_replay, "testArtifactPair": pair,
                "command": link(directory / "command.json"), "exitCode": command.get("runnerExitCode"),
                "filter": command.get("filter")}

    inputs = link(fingerprint)
    same_final_source = (command.get("head") == head and same_hash(command.get("sourceInputsSha256"), inputs["sha256"]) and
                         current_source_inputs(fingerprint, root, paths[snapshots], digest_cache))
    exit_code = command.get("exit") if snapshots else read_json(directory / "exit.json").get("exit")
    loaded_path = directory / "loaded-binaries.json"
    loaded = read_json(loaded_path) if loaded_path.is_file() else {}
    has_binary_identity = all(same_hash(loaded.get(key), loaded.get(key)) for key in ("testsSha256", "coreSha256"))
    filter_name = command.get("filter")
    after_inputs = None
    build_log = directory / "build.log"
    if snapshots:
        after_inputs = link(directory / "source-inputs-after.json")
        same_final_source = (same_final_source and same_path(command.get("repo"), str(root)) and command.get("sourcesChanged") == [] and
                             same_hash(command.get("sourceInputsAfterSha256"), inputs["sha256"]) and
                             same_hash(after_inputs["sha256"], inputs["sha256"]))
        arguments = command["argv"]
        filter_name = arguments[arguments.index("-Filter") + 1] if "-Filter" in arguments else None
        build_log = directory / "runner.log" if "-NoBuild" not in arguments else None
        has_binary_identity = has_binary_identity and all(same_hash(loaded.get(hash_key), assemblies.get(loaded.get(path_key)))
            for hash_key, path_key in (("testsSha256", "testsPath"), ("coreSha256", "corePath")))
    has_build = build_log is not None and build_log.is_file()
    anchor = (snapshots and same_final_source and has_build and stored_in_expected_assembly and pair and exit_code == 0 and
              command.get("testSeams") is True and bool(result["tests"]))
    evidence_bound = (same_final_source and has_build and has_binary_identity) or bool(anchor)
    status = "BLOCKED"
    only_prerequisite_failures = (result["observedCounts"].get("BLOCKED", 0) > 0 and
                                  result["observedCounts"].get("FAIL", 0) == 0)
    if same_final_source and (result["observedCounts"].get("FAIL", 0) > 0 or (exit_code != 0 and not only_prerequisite_failures)):
        status = "FAIL"
    elif (evidence_bound and exit_code == 0 and result["tests"] and
          all(row["status"] == "PASS" for row in result["tests"])):
        status = "PASS"
    return {**result, "status": status, "sameFinalSource": same_final_source,
            "testSeams": command.get("testSeams"), "filter": filter_name, "exitCode": exit_code,
            "sourceAndLoadedTestBinariesBound": evidence_bound, "testArtifactPair": pair,
            "buildAnchor": bool(anchor), "privateReplayRequiresBuildAnchor": snapshots and same_final_source and has_binary_identity,
            "sourceInputs": inputs, "afterSourceInputs": after_inputs, "command": link(directory / "command.json"),
            "loadedBinaries": loaded, "freshBuildLog": link(build_log) if has_build else None}


def focused_groups(directories, root, required):
    if not directories:
        return {"status": "NOT_RUN", "runs": [], "missingRequired": required}
    same_tree = {False: checked_out_sources(root), True: checked_out_sources(root, PRIVATE_TEST_SOURCE_INPUT_SCOPES)}
    head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    cache = {}
    runs = [focused_grounding(directory, root, same_tree, head, cache) for directory in directories]
    anchors = {row["testArtifactPair"]: row for row in runs if row.get("buildAnchor")}
    for row in runs:
        is_replay = row.get("defaultReplayRequiresBuildAnchor") or row.get("privateReplayRequiresBuildAnchor")
        if is_replay and not row["sourceAndLoadedTestBinariesBound"] and row.get("testArtifactPair") in anchors:
            anchor = anchors[row["testArtifactPair"]]
            row.update(sameFinalSource=True, sourceAndLoadedTestBinariesBound=True, assemblyBuildAnchor=anchor["command"])
            if row["exitCode"] == 0 and row["tests"] and all(test["status"] == "PASS" for test in row["tests"]):
                row["status"] = "PASS"
    status_by_name = {}
    for row in runs:
        if row.get("sourceAndLoadedTestBinariesBound"):
            for test in row["tests"]:
                status_by_name.setdefault(test["name"], set()).add(test["status"])
    named = {name: next(state for state in ("FAIL", "PASS", "BLOCKED", "NOT_RUN") if state in outcomes)
             for name, outcomes in status_by_name.items()}
    tested = {name for name, status in named.items() if status == "PASS"}
    missing = [name for name in required if not any(name in test for test in tested)]
    # Preserve a real failure on the selected source instead of overwriting it with a later pass.
    if any(row["status"] == "FAIL" for row in runs):
        status = "FAIL"
    elif tested and required and not missing and set(named.values()) == {"PASS"}:
        status = "PASS"
    else:
        status = "BLOCKED"
    recovered = sorted(name for name, outcomes in status_by_name.items()
                       if named[name] == "PASS" and outcomes & {"BLOCKED", "NOT_RUN"})
    return {"status": status, "runs": runs, "requiredTestNameIncludes": required, "missingRequired": missing,
            "sameSourceNamedCounts": dict(Counter(named.values())), "namedFixtureGapsRecovered": recovered}


def read_native(file, expected):
    receipt = read_json(file)
    log_file = file.parent / "selftest.log"
    source = link(log_file)
    text = log_file.read_text(encoding="utf-8-sig", errors="replace")
    # Windows PowerShell redirection can write UTF-16LE.
    if "\x00" in text:
        text = log_file.read_text(encoding="utf-16")
    bridge_passes = len(re.findall(r"^PASS \S+", text, re.M))
    shake = re.search(r"^WorldShakeSelfTest: (\d+)/(\d+) checks passed", text, re.M)
    native_ok = (receipt.get("exitCode") == 0 and bridge_passes > 0 and
                 re.search(r"^RESULT PASS failures=0\s*$", text, re.M) is not None and
                 re.search(r"^(FAIL\b|RESULT FAIL\b)", text, re.M) is None and
                 shake is not None and int(shake[1]) == int(shake[2]) > 0)
    matches = (receipt.get("schema") == "cf7-input-authority-native-selftest.v1" and
               identities_match(receipt, expected) and receipt.get("worktreeCoherent") is True and
               same_hash(receipt.get("logSha256"), source["sha256"]))
    return {"status": ("PASS" if native_ok else "FAIL") if matches else "BLOCKED", "identityMatched": matches,
            "inputBridgeChecks": bridge_passes, "worldShakeChecks": int(shake[1]) if shake else None,
            "exitCode": receipt.get("exitCode"), "log": source, "raw": link(file)}


def read_smoke(file, expected, desktop=None):
    value = read_json(file)
    manifest = value.get("identity", {})
    matches = (same_path(value.get("candidate"), expected["installRoot"]) and identities_match({
        "buildIdentity": manifest.get("buildIdentityHash"), "payloadClosure": manifest.get("payloadClosureHash"),
        "coreSha256": value.get("coreSha256"),
    }, expected))
    raw_state = value.get("state")
    reason = value.get("failure") or ""
    checks = value.get("checks") or []
    foreground_missing = raw_state == "failed" and "fixture initial foreground admitted" in reason
    non_input = bool(isinstance(desktop, dict) and desktop.get("threadDesktop") and desktop.get("inputDesktop") and
                     desktop["threadDesktop"] != desktop["inputDesktop"])
    status = "BLOCKED"
    if matches and value.get("kind") == "isolated-composition-fixture" and value.get("gameE2e") is False:
        if raw_state == "failed" and not foreground_missing:
            status = "FAIL"
        if raw_state == "fixture_executed" and value.get("reportPixelsVerified") is True and checks and all(
                row.get("passed") is True for row in checks):
            status = "PASS"
    return {"status": status, "rawState": raw_state, "identityMatched": matches, "gameE2e": value.get("gameE2e"),
            "reportPixelsVerified": value.get("reportPixelsVerified"), "failure": reason, "checks": checks,
            "foregroundAdmission": "FAIL" if foreground_missing else "PASS" if status == "PASS" else None,
            "nonInputDesktopObserved": non_input if desktop else None,
            "interactiveChecks": "NOT_RUN" if foreground_missing else status, "raw": link(file)}


def read_live(file, expected, host_launcher_log=None):
    data = read_json(file)
    session = data.get("candidate", {}).get("observed") or {}
    ready = data.get("runtimeReady") or {}
    matches = (data.get("schema") == "cf7-r5-live.v1" and identities_match(session, expected) and
               same_path(session.get("processPath"), expected["processPath"]) and session.get("runtimeMode") == "isolated_candidate" and
               type(session.get("pid")) is int and session["pid"] > 0 and data.get("closureVerified") is True)
    executed = bool(matches and ready.get("slot") == data.get("slot") and ready.get("slot") and
                    ready.get("attemptId") == data.get("expectedAttemptId") and ready.get("attemptId"))
    cases = data.get("cases") or {}
    launcher_lines = host_launcher_log.read_text(encoding="utf-8-sig").splitlines() if host_launcher_log else None
    focus_partition = (classify_chain_focus(data, launcher_lines) if executed else
                       {"businessStatus": "NOT_RUN", "lifecycleStatus": "NOT_RUN"})
    if host_launcher_log:
        focus_partition["hostLauncherLog"] = link(host_launcher_log)
    raw_checks, checks = checked_chain_cases(cases, {
        "bootstrapPositiveLines": [], **focus_partition})
    return {"status": "PASS" if executed else "BLOCKED", "identityMatched": matches, "session": session,
            "runtimeReady": ready, "desktopEnvironment": data.get("desktopEnvironment"), "desktopChecks": data.get("desktopChecks"),
            "caseChecks": checks, "rawCaseChecks": raw_checks, "rawCaseStatuses": {key: row.get("status") for key, row in cases.items()},
            "focusPartition": focus_partition, "profile": data.get("profile"), "errors": data.get("errors"), "raw": link(file)}


def read_startup(process_file, expected):
    process = read_json(process_file)
    ready_file = process_file.parent / "ready.json"
    ready = read_json(ready_file)
    matches = (identities_match(process, expected) and same_path(process.get("processPath"), expected["processPath"]) and
               process.get("runtimeMode") == "isolated_candidate" and same_path(process.get("candidate"), expected["installRoot"]) and
               type(process.get("pid")) is int and process["pid"] > 0)
    complete = (matches and str(process.get("slot", "")).startswith("cf7_agent_") and ready.get("slot") == process["slot"] and
                ready.get("attemptId") and ready.get("decision") == "snapshot" and
                datetime.fromisoformat(process["startedAt"]) <= datetime.fromisoformat(ready["utc"]))
    return {"status": "PASS" if complete else "BLOCKED", "identityMatched": matches,
            "process": process, "ready": ready, "raw": link(process_file), "readyArtifact": link(ready_file)}


def read_original_route(file, expected, startup):
    raw = read_json(file)
    result = {"status": "BLOCKED", "raw": link(file), "route": raw.get("order"), "stimulus": raw.get("stimulus"),
              "declaredLimits": raw.get("limits"), "motion": {}}
    if (startup.get("status") != "PASS" or raw.get("pid") != startup["process"]["pid"] or
            raw.get("attempt") != startup["ready"]["attemptId"] or not same_hash(raw.get("buildIdentity"), expected["buildIdentity"])):
        return result
    expected_order = ["新手练习场", "超市废墟", "废墟武器店"]
    rows = raw.get("reports") or []
    for row in rows:
        direction = row.get("directions") or {}
        measured = all(type(direction.get(label, {}).get("samples")) is int and direction[label]["samples"] > 1 and
                       type(direction[label].get("netDisplacement")) in (int, float) and multiplier * direction[label]["netDisplacement"] > 0 and
                       direction[label].get("heldInAllSamples") is True and (direction[label].get("observedWindowMs") or 0) > 0
                       for label, multiplier in (("left", -1), ("right", 1)))
        result["motion"][row["name"]] = {"status": "PASS" if measured and row.get("sceneMarker") else "BLOCKED",
                                         "sceneMarker": row.get("sceneMarker"), "directions": direction}
    if [row["name"] for row in rows] == expected_order == raw.get("order") and "os sendinput" in str(raw.get("stimulus", "")).lower() and all(
            row["status"] == "PASS" for row in result["motion"].values()):
        result["status"] = "PASS"
    return result


def read_consumer_review(file, root, expected):
    raw = read_json(file)
    result = {"status": "BLOCKED", "raw": link(file), "items": [], "publishedAssets": []}
    if raw.get("schema") != "cf7-input-authority-consumer-review.v1" or not identities_match(raw.get("candidate"), expected):
        return result
    for item in raw.get("items", []):
        artifacts = []
        for artifact in item.get("evidence", []):
            path = (file.parent / artifact["path"]).resolve()
            artifacts.append({**artifact, "path": str(path), "hashVerified": same_hash(artifact.get("sha256"), digest(path))})
        result["items"].append({**item, "evidence": artifacts})
    for proof in raw.get("publishedAssets", []):
        swf = root / proof["path"]
        result["publishedAssets"].append({**proof, "installedHashMatched": swf.is_file() and same_hash(digest(swf), proof.get("sha256"))})
    return result


def read_asloader(file, root):
    data = read_json(file)
    modules = data.get("modules", {})
    evidence = {}
    for name, relative in ASLOADER_PATHS.items():
        module = modules.get(name) or {}
        proof = module.get("origin", {}).get("proof") or {}
        installed = root / relative
        fresh = data.get("run") and proof.get("run") == data["run"] and proof.get("module") == name
        exact = installed.is_file() and same_hash(module.get("sha256"), digest(installed)) and same_hash(
            proof.get("sha256"), module.get("sha256"))
        compiler_values = [proof.get(field) for field in ("compilerErrors", "compilerWarnings", "retry32K")]
        evidence[name] = {"fresh": bool(fresh), "installedHashMatched": exact, "compilerCounts": compiler_values,
                          "hashes": {field: proof.get(field) for field in ("compilerSha256", "outputSha256", "consoleSha256")}}
    status = "BLOCKED"
    if data.get("schema") == "cf7-asloader-run.v1" and same_path(data.get("destination"), str(root)):
        if data.get("state") == "failed":
            status = "FAIL"
        elif data.get("state") == "compiled" and all(row["fresh"] and row["installedHashMatched"] and
                all(type(value) is int and value == 0 for value in row["compilerCounts"]) for row in evidence.values()):
            status = "PASS"
    return {"status": status, "run": data.get("run"), "sourceSnapshotId": data.get("sourceSnapshotId"),
            "modules": evidence, "raw": link(file)}


def legacy_latency(file):
    data = read_json(file)
    # Old receipts timed different work on each side. Preserve the values as diagnostics only.
    summary = data.get("summary") or {}
    return {"status": "BLOCKED", "raw": link(file), "diagnostic": {field: summary.get(field) for field in
            ("baselineP50Ms", "baselineP95Ms", "candidateP50Ms", "candidateP95Ms")},
            "reason": "No verified same-stimulus sample pairs from input edge through presentation; no budget claim."}


def ordinary_lifecycle(file, observation, expected):
    folder = file.parent
    startup = read_startup(folder / "process.json", expected)
    process = startup["process"]
    observed = observation["observed"]
    initial_file = folder / "initial-conditions.json"
    initial = read_json(initial_file)
    cleanup_file = folder / "cleanup.json"
    cleanup = read_json(cleanup_file)
    desktop_file = folder / "desktop.jsonl"
    with desktop_file.open(encoding="utf-8-sig") as stream:
        desktop = [json.loads(line) for line in stream if line.strip()]
    roots = {row["root"] for row in desktop if row["pid"] == process["pid"] and row["foregroundAfter"] == row["root"] and
             row["desktop"]["threadReceivesInput"] is True and
             row["desktop"]["threadDesktop"] == row["desktop"]["inputDesktop"] == "Default"}
    if (startup["status"] != "PASS" or observed["pid"] != process["pid"] or len(roots) != 1 or
            not identities_match(observed, expected) or not same_path(observed["processPath"], expected["processPath"]) or
            observation["attemptId"] != startup["ready"]["attemptId"] or
            observation["slot"] != process["slot"] or cleanup["slot"] != process["slot"] or
            cleanup["cloneRemoved"] is not True or cleanup["sameMarker"] is not True or
            cleanup["playerFiles"]["ok"] is not True or not cleanup["playerFiles"]["checkedFiles"]):
        raise ValueError("Ordinary pulse lifecycle cross-check failed.")
    root = roots.pop()
    edges = [edge for sample in observation["samples"] for edge in sample["injection"]["edges"]]
    if not edges or not all(edge["foreground"] == root and
                            (edge.get("pid") == process["pid"] if edge["edge"] == "down" else
                             edge.get("pid", process["pid"]) == process["pid"]) for edge in edges):
        raise ValueError("Ordinary pulse foreground diverged from the verified Guardian.")
    return {"initial": initial, "initialRaw": link(initial_file), "startup": startup["raw"], "ready": startup["readyArtifact"],
            "cleanup": link(cleanup_file), "desktop": link(desktop_file), "startUtc": process["startedAt"],
            "cleanupUtc": cleanup["utc"], "projectRoot": process["root"]}


def paired_ordinary_latency(baseline_file, candidate_file, expected, plan_file=None, baseline_anchor_file=None):
    baseline = read_json(baseline_file)
    candidate = read_json(candidate_file)
    baseline_identity = baseline.get("observed") or {}
    matching_profile = (baseline.get("role") == "baseline" and candidate.get("role") == "candidate" and
                        all(baseline.get(field) == candidate.get(field) for field in
                            ("scene", "stimulus", "observer", "vk", "holdMs", "perPulseMs", "plannedSamples", "conditioningPulses",
                             "recenterVk", "recenterHoldMs", "originTolerance")) and
                        candidate.get("observer") in ("movement", "latched-movement") and
                        baseline.get("schema") == candidate.get("schema") == "cf7-input-authority-ordinary-latency.v1" and
                        baseline.get("scene") and candidate.get("stimulus") == "os-sendinput" and
                        baseline.get("sessionStayedBound") is True and candidate.get("sessionStayedBound") is True and
                        baseline_identity.get("runtimeMode") == "isolated_candidate" and
                        all(same_hash(baseline_identity.get(key), baseline_identity.get(key)) for key in
                            ("buildIdentity", "payloadClosure", "coreSha256")) and
                        identities_match(candidate.get("observed"), expected) and
                        same_path(candidate["observed"].get("processPath"), expected["processPath"]) and
                        not same_hash(baseline_identity.get("buildIdentity"), expected["buildIdentity"]))
    result = {"status": "BLOCKED", "matchingProfile": bool(matching_profile), "bounds": None,
              "presentationLatency": None, "baseline": link(baseline_file), "raw": link(candidate_file),
              "reason": "Ordinary diagnostic covers bounded SendInput-to-latch/action observations only."}
    if not matching_profile:
        return {**result, "reason": "Paired observations do not have matching roles/profile or candidate identity."}
    if plan_file or baseline_anchor_file:
        if not (plan_file and baseline_anchor_file):
            return {**result, "matchingProfile": False, "reason": "A repeatable pair requires the plan and exact baseline anchor."}
        plan = read_json(plan_file)
        anchor = read_json(baseline_anchor_file)
        before_run = ordinary_lifecycle(baseline_file, baseline, anchor["candidate"])
        after_run = ordinary_lifecycle(candidate_file, candidate, expected)
        source = plan["observer"]
        seed = plan["seed"]
        if re.fullmatch(r"cf7_agent_[a-zA-Z0-9_]+", seed) is None:
            raise ValueError("Ordinary latency pair did not use the exact isolated seed.")
        seeds_match = all(same_hash(plan["seedSha256"], digest(Path(run["projectRoot"]) / "saves" / (seed + ".json")))
                          for run in (before_run, after_run))
        start_left = before_run["initial"]
        start_right = after_run["initial"]
        same_position = (start_left["clientSize"] == start_right["clientSize"] and
                         abs(start_left["actorX"] - start_right["actorX"]) <= 0.1)
        plan_matches = (anchor.get("schema") == "cf7-input-authority-qualification.v1" and
                        plan["scene"] == candidate["scene"] and plan["samples"] == candidate["plannedSamples"] and
                        same_hash(source["sha256"], digest(source["path"])) and seeds_match and same_position and
                        datetime.fromisoformat(before_run["cleanupUtc"]) <= datetime.fromisoformat(after_run["startUtc"]))
        if not plan_matches:
            return {**result, "matchingProfile": False, "reason": "The pair plan, initial conditions or lifecycle do not match."}
        result.update(pairPlan=link(plan_file), baselineAnchor=link(baseline_anchor_file),
                      verifiedLifecycle={"baseline": before_run, "candidate": after_run})

    def measure(row, key):
        if key == "latch" and candidate["observer"] != "latched-movement":
            return None
        if row.get("invalidReason") or row.get("injection", {}).get("exit") != 0 or not row.get("before"):
            return None
        stimulus = row["injection"]
        first = stimulus.get("edges", [])
        if len(first) != 2 or (first[0].get("edge"), first[1].get("edge")) != ("down", "up"):
            return None
        prior = row["before"]
        for observation in row.get("observations", []):
            if observation.get("keyEpoch") != row["before"].get("keyEpoch"):
                return None
            if key == "latch":
                positive = observation["key"] is True and observation["inputFrame"] > row["before"]["inputFrame"]
            else:
                positive = ((candidate["observer"] == "movement" or observation["frame"] > row["before"]["frame"]) and
                            observation["x"] - row["before"]["x"] > 0.1)
            if positive:
                earliest = max(0, prior["requestedMs"] - first[0]["receivedMs"])
                latest = observation["returnedMs"] - stimulus["requestedMs"]
                return [earliest, latest] if 0 <= earliest <= latest else None
            prior = observation
        return None

    left = {row["id"]: row for row in baseline.get("samples", [])}
    right = {row["id"]: row for row in candidate.get("samples", [])}
    if len(left) != len(baseline.get("samples", [])) or len(right) != len(candidate.get("samples", [])):
        return {**result, "matchingProfile": False, "reason": "Duplicate latency sample identifiers."}
    sample_ids = sorted(left.keys() & right.keys())
    segments = {}
    for key in ("latch", "movement"):
        segments[key] = {"baseline": [], "candidate": [], "pairedDelta": []}
        current = segments[key]
        for sample in sample_ids:
            before, after = measure(left[sample], key), measure(right[sample], key)
            if before is not None and after is not None:
                current["baseline"].append(before)
                current["candidate"].append(after)
                current["pairedDelta"].append([after[0] - before[1], after[1] - before[0]])
        current["matchedSamples"] = len(current["pairedDelta"])
        current["baselineMedianMs"] = [median(edge) for edge in zip(*current["baseline"])]
        current["candidateMedianMs"] = [median(edge) for edge in zip(*current["candidate"])]
        current["pairedDeltaMedianMs"] = [median(edge) for edge in zip(*current["pairedDelta"])]
    return {**result, "bounds": segments, "requested": candidate.get("plannedSamples"), "pairedPossible": len(sample_ids),
            "baselineErrors": baseline.get("errors"), "candidateErrors": candidate.get("errors")}


def read_domain(receipt_path, expected):
    receipt = read_json(receipt_path)
    file = receipt_path.parent / "result.json"
    raw = read_json(file)
    same_candidate = (receipt.get("schema") == "cf7-modifier-domain-run.v1" and
                      same_path(receipt.get("candidateRoot"), expected["installRoot"]) and identities_match(receipt, expected) and
                      same_hash(receipt.get("rawSha256"), digest(file)) and same_hash(raw.get("coreSha256"), expected["coreSha256"]))
    valid_run = (raw.get("schema") == "cf7-modifier-domain-probe.v1" and raw.get("runId") and
                 raw.get("desktop") == "CF7Review-" + raw["runId"] and raw.get("inputDesktop") and
                 raw["inputDesktop"] != raw["desktop"] and type(raw.get("pid")) is int and raw["pid"] > 0 and
                 raw.get("completedUtc") and raw.get("stimulus") == "known_hwnd_wm_messages")
    trials = raw.get("trials") or []
    expected_cases = {(target, mutation, order, move) for target in ("close", "tab:items")
                      for mutation in ("stable", "world-only") for order in ("geometry-first", "stable-first")
                      for move in (False, True)}
    expected_controls = {(target, "local-geometry", "cancellation-control", True) for target in ("close", "tab:items")}

    def key(row):
        return row.get("Target"), row.get("Mutation"), row.get("Order"), row.get("Move")

    def status(expected_rows):
        picked = [row for row in trials if key(row) in expected_rows]
        if not same_candidate or not valid_run:
            return "BLOCKED"
        correct = []
        for row in picked:
            local = row["Mutation"] == "local-geometry"
            world = row["Mutation"] == "world-only"
            values_present = all(type(row.get(name)) is int for name in ("GeometryAfter", "GeometryBefore", "EarlyCommit", "ActionDelta"))
            success = (values_present and row.get("ValidOnDown") is True and row["EarlyCommit"] == 0 and
                       (row["GeometryAfter"] > row["GeometryBefore"] if world else row["GeometryAfter"] == row["GeometryBefore"]) and
                       row.get("LocalUnchanged") is (not local) and
                       row.get("HitBeforeUp") == row["Target"] and row.get("ValidBeforeMove") is (not local) and
                       row.get("ValidBeforeUp") is (not local) and row["ActionDelta"] == int(not local) and
                       row.get("Settled") is True and row.get("KeyboardUnchanged") is True and row.get("PointerEpochUnchanged") is True and
                       (not local or (row.get("FreshActionDelta") == 1 and row.get("FreshSettled") is True)))
            correct.append(success)
        if not all(correct):
            return "FAIL"
        if len(picked) == len(expected_rows) and {key(row) for row in picked} == expected_rows and receipt.get("exitCode") in (0, 2):
            return "PASS"
        return "BLOCKED"

    return {"status": status(expected_cases), "localCancellation": status(expected_controls),
            "identityMatched": same_candidate, "runId": raw.get("runId"), "pid": raw.get("pid"),
            "desktop": raw.get("desktop"), "stimulus": raw.get("stimulus"), "trials": trials,
            "exitCode": receipt.get("exitCode"), "raw": link(file), "receipt": link(receipt_path)}


def read_focus(file, expected):
    data = read_json(file)
    scope = set(data.get("coveredCases") or [])
    required = {"startup", "text", "transition", "external_focus_loss", "fault", "exit"}
    rows = data.get("records") or []
    declared_pid = data.get("observed", {}).get("pid")
    matches = (data.get("schema") == "cf7-input-authority-focus.v1" and type(declared_pid) is int and declared_pid > 0 and
               identities_match(data.get("observed"), expected) and
               same_path(data["observed"].get("processPath"), expected["processPath"]))
    runtime_rows = [row for row in rows if row.get("stage") == "runtime"]
    bootstrap_rows = [row for row in rows if row.get("stage") == "bootstrap"]
    queried = [row for row in runtime_rows if row.get("querySucceeded") is True and
               type(row.get("beforeFlashFocused")) is bool and type(row.get("correctionAttempted")) is bool]
    probe_path = (file.parent / data["probeStatus"]).resolve() if data.get("probeStatus") else None
    probe = read_json(probe_path) if probe_path else {}
    counters = probe.get("passiveFocusCounts") or {}
    numeric = ("samples", "failedQueries", "startupRawFocus", "startupCorrections", "runtimeRawFocus",
               "runtimeFocusNotifications", "runtimeStyleViolations")
    qualified_counts = (all(type(counters.get(name)) is int and counters[name] >= 0 for name in numeric) and
                        counters["samples"] > 0 and counters.get("sourceHook") is True and counters.get("hostHook") is True)
    complete = (matches and runtime_rows and qualified_counts and
                len(queried) == len(runtime_rows) and required <= scope and
                required <= {row.get("case") for row in queried + bootstrap_rows} and
                type(data.get("droppedRecords")) is int and data["droppedRecords"] == 0)
    before = sum(row["beforeFlashFocused"] for row in queried)
    corrections = sum(row["correctionAttempted"] for row in queried)
    status = "BLOCKED"
    positive_runtime_count = any(type(counters.get(key)) is int and counters[key] > 0 for key in
                                 ("runtimeRawFocus", "runtimeFocusNotifications"))
    if matches and (before or corrections or positive_runtime_count):
        status = "FAIL"
    elif complete:
        status = "PASS"
    return {"status": status, "identityMatched": matches, "bootstrapSamples": len(bootstrap_rows),
            "runtimeSamples": len(runtime_rows), "rawBeforeFocusSamples": len(queried),
            "observedRuntimeFlashFocused": before if queried else None, "observedRuntimeCorrections": corrections if queried else None,
            "verifiedRuntimeFlashFocused": before if complete else None, "verifiedRuntimeCorrections": corrections if complete else None,
            "passiveFocusCounts": {key: counters.get(key) for key in (*numeric, "sourceHook", "hostHook")},
            "probeStatus": link(probe_path) if probe_path else None,
            "missingLifecycleCases": sorted(required - scope), "raw": link(file)}
