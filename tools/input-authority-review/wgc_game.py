"""Read current production WGC source-tag and presentation diagnostics."""

from collections import Counter, defaultdict
from pathlib import Path

from evidence import digest, identities_match, link, read_json, same_hash, same_path
from trace_entry import read_focus_trace


def read_game_wgc(focus_file, expected, startup):
    result = {"status": "BLOCKED", "raw": link(focus_file)}
    if startup.get("status") != "PASS":
        return {**result, "reason": "The same live candidate process must be independently verified."}
    pid = startup["process"]["pid"]
    rows = list(read_focus_trace(focus_file))
    dll = str(Path(expected["processPath"]).with_suffix(".dll"))
    starts = [row for row in rows if row["event"] == "trace.start" and row["data"].get("pid") == pid and
              same_path(row["data"].get("corePath"), dll)]
    if len(starts) != 1:
        return {**result, "reason": "No unique FocusTrace PID and loaded Core handshake."}
    start = starts[0]
    selected = [row for row in rows if all(row.get(key) == start.get(key) for key in ("session", "processRunId", "generation"))]
    sources = [row for row in selected if row["event"] == "world.bullet_source"]
    present = [row for row in selected if row["event"] == "world.presentation_timing"]
    capture = defaultdict(list)
    for row in sources:
        data = row.get("data", {})
        if (data.get("TagValid") == 1 and data.get("status") == "matched" and
                data.get("SourceEpoch") == data.get("MatchedOrdinaryEpoch") and data.get("SourceFrame") == data.get("MatchedOrdinaryFrame") and
                all(type(data.get(key)) is int and data[key] >= 0 for key in ("SourceEpoch", "SourceFrame")) and
                isinstance(data.get("CaptureQpcMs"), (int, float)) and data["CaptureQpcMs"] > 0):
            capture[data["SourceEpoch"]].append({"seq": row["seq"], "frame": data["SourceFrame"], "captureQpcMs": data["CaptureQpcMs"]})
    qualified_sources = any(by_epoch[0]["frame"] < by_epoch[-1]["frame"] and
                            by_epoch[0]["captureQpcMs"] < by_epoch[-1]["captureQpcMs"] for by_epoch in capture.values())
    presenting = [row for row in present if row.get("data", {}).get("ready") is True and
                  row["data"].get("advancing") is True and type(row["data"].get("presented")) is int]
    advancing = bool(presenting and presenting[0]["data"]["presented"] < presenting[-1]["data"]["presented"])
    return {**result, "status": "PASS" if qualified_sources and advancing else "BLOCKED", "pid": pid,
            "traceSession": start.get("session"), "sourceSampleCounts": dict(Counter(row["data"].get("status") for row in sources)),
            "matchedSourceTags": sum(len({sample["frame"] for sample in taken}) for taken in capture.values()),
            "matchedSourceWindows": {epoch: {"first": samples[0], "last": samples[-1]} for epoch, samples in capture.items()},
            "presentationSamples": len(present), "presentationAdvanced": advancing,
            "firstPresentation": presenting[0] if presenting else None, "lastPresentation": presenting[-1] if presenting else None,
            "scope": "Actual game sampled source-tag progression and separate production Present timing.",
            "actionToPresentationMs": None, "physicalScanoutVerified": False,
            "sourceStallNegativeControl": "NOT_RUN", "pMarkerLoopbackNegativeControl": "NOT_RUN"}


def read_g2(summary_file, preparation_file, expected, run_file=None):
    prepare = read_json(preparation_file)
    native = Path(expected["installRoot"]) / "runtime/FlashCompositorNative.dll"
    same_candidate = (prepare.get("schema") == "cf7-input-authority-wgc-fixture-preparation.v1" and
                      identities_match(prepare, expected) and same_path(prepare.get("candidateRoot"), expected["installRoot"]) and
                      same_hash(prepare.get("nativeSha256"), digest(native)))
    staged = prepare.get("fixtureFiles") or []
    staged_checked = bool(staged and all(same_hash(row["sha256"], digest(row["path"])) for row in staged) and any(
        Path(row["path"]).name == "FlashCompositorNative.dll" and same_hash(row["sha256"], prepare["nativeSha256"]) for row in staged))
    result = {"raw": link(summary_file), "preparation": link(preparation_file), "identityMatched": same_candidate,
              "stagedFixtureStillExact": staged_checked, "scope": "Owned G2 fixture sources and staged candidate native binary.",
              "abi": prepare.get("abi"), "status": "BLOCKED", "cases": {}, "cliNegativeControls": {}}
    if run_file:
        run = read_json(run_file)
        real_desktop = all(run.get(key, {}).get("threadDesktop") == "Default" and
                           run[key].get("inputDesktop") == "Default" and run[key].get("threadReceivesInput") is True
                           for key in ("desktopBefore", "desktopAfter"))
        replay_bound = (run.get("schema") == "cf7-input-authority-wgc-fixture-run.v1" and
                        same_path(run.get("summary"), str(summary_file)) and same_hash(run.get("summarySha256"), digest(summary_file)) and
                        same_hash(run.get("preparationSha256"), digest(preparation_file)) and
                        same_hash(run.get("logSha256"), digest(run["log"])))
        result.update(defaultDesktopVerified=real_desktop, runReceiptVerified=replay_bound, runReceipt=link(run_file))
        if not (real_desktop and replay_bound):
            return result
    if not same_candidate or not staged_checked:
        return result
    summary = read_json(summary_file)
    managed = next((row["sha256"] for row in staged if Path(row["path"]).name == "FlashCompositorProbe.dll"), None)
    suite_cases = {"positive", "stall-f", "hold-frames", "capture-output", "flash"}
    cli_cases = {f"invalid-{index}" for index in range(4)}
    for row in summary:
        name = row["name"]
        if name not in suite_cases and name not in cli_cases:
            continue
        path = Path(row["report"])
        if path.resolve() != (summary_file.parent / (name + ".json")).resolve():
            continue
        raw = read_json(path)
        if name in cli_cases:
            valid_rejection = row["exitCode"] == 1 and raw.get("success") is False and isinstance(raw.get("error"), str)
            result["cliNegativeControls"][name] = {"status": "PASS" if row.get("passed") is True and valid_rejection else "BLOCKED",
                                                   "raw": link(path)}
            continue
        binaries_match = same_hash(raw.get("nativeSha256"), prepare["nativeSha256"]) and same_hash(raw.get("managedSha256"), managed)
        experiment = raw.get("topologyExperiment") or {}
        marker = experiment.get("marker") or {}
        phases = {phase["phase"]: phase for phase in experiment.get("contentPhases", [])}
        covered = phases.get("covered", {})
        stalled = phases.get("covered-stalled", {})
        flowing = (covered.get("verdict") == "streaming-under-cover" and covered.get("inputPixelsChanged") is True and
                   covered.get("outputCorrelated") is True)
        intended_outcome = False
        if name in ("positive", "flash"):
            intended_outcome = (row["exitCode"] == 0 and raw.get("success") is True and flowing and
                                marker.get("sampled") is True and marker.get("markerVisibleOnP") is True and
                                marker.get("markerInCapturedSource") is False)
        elif name == "stall-f":
            intended_outcome = (row["exitCode"] == 2 and raw.get("success") is False and flowing and
                                stalled.get("verdict") == "s-chrome-only" and (stalled.get("capturedFrames") or 0) > 0 and
                                (stalled.get("presentedFrames") or 0) > 0 and stalled.get("inputPixelsChanged") is False and
                                len(stalled.get("proofs") or []) >= 2)
        elif name == "hold-frames":
            intended_outcome = (row["exitCode"] == 2 and raw.get("success") is False and covered.get("verdict") == "stalled-under-cover" and
                                covered.get("capturedFrames") == 0 and (covered.get("presentedFrames") or 0) > 0 and
                                covered.get("inputPixelsChanged") is False and len(covered.get("proofs") or []) >= 2)
        elif name == "capture-output":
            intended_outcome = (row["exitCode"] == 2 and raw.get("success") is False and covered.get("verdict") == "marker-leak" and
                                experiment.get("negativeControl") == "detected" and marker.get("markerInCapturedSource") is True)
        result["cases"][name] = {"status": "PASS" if row.get("passed") is True and intended_outcome and binaries_match else "BLOCKED",
                                 "rawExit": row["exitCode"], "rawSuccess": raw.get("success"), "raw": link(path),
                                 "binariesMatch": binaries_match, "failure": raw.get("failure"),
                                 "coveredVerdict": covered.get("verdict"), "stalledVerdict": stalled.get("verdict"),
                                 "coveredCapturedFrames": covered.get("capturedFrames"), "coveredPresentedFrames": covered.get("presentedFrames"),
                                 "stalledCapturedFrames": stalled.get("capturedFrames"), "stalledPresentedFrames": stalled.get("presentedFrames"),
                                 "markerInCapturedSource": marker.get("markerInCapturedSource")}
    cli = result["cliNegativeControls"]
    if (result["cases"].keys() == suite_cases and all(row["status"] == "PASS" for row in result["cases"].values()) and
            cli.keys() == cli_cases and all(row["status"] == "PASS" for row in cli.values()) and run_file and run.get("exitCode") == 0):
        result["status"] = "PASS"
    return result
