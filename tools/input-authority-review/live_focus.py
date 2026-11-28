"""Separate the recorded pre-ready Flash focus from runtime focus violations."""

from collections import Counter
import json
import re


_FIELDS = re.compile(r"([A-Za-z_]+)=([^ ]+)")
_TIME = re.compile(r"^(\d\d):(\d\d):(\d\d)\.(\d{3})\b")
_DAY_MS = 24 * 60 * 60 * 1000
_FOCUS_CHECKS = {
    ("R1-P01", "focus"), ("R1-P02", "focus"), ("R1-P12", "focus"),
    ("R5-G58", "focus"), ("R5-G55-G57", "zeroFlashFocusAndHandoff"),
}


def fields(line):
    return dict(_FIELDS.findall(line))


def stamp(line):
    if found := _TIME.match(line):
        hour, minute, second, millisecond = map(int, found.groups())
        return ((hour * 60 + minute) * 60 + second) * 1000 + millisecond
    return None


def relative_time(timestamp, anchor):
    # A short test can cross midnight. Both times are from the same launcher log.
    return (timestamp - anchor + _DAY_MS // 2) % _DAY_MS - _DAY_MS // 2


def hwnd(value):
    if isinstance(value, str) and re.fullmatch(r"0x[0-9a-f]+", value, re.I):
        return int(value, 16)
    return None


def query_rows(sample):
    return (isinstance(sample, list) and len(sample) >= 2 and
            len({row.get("threadId") for row in sample if row.get("threadId")}) >= 2 and
            all(row.get("readSucceeded") is True and type(row.get("flashFocused")) is bool for row in sample))


def host_publication_boundary(data, lines):
    """Identify the actual Host publication associated with this game's exact attempt and P/S/F."""
    ready = data.get("runtimeReady") or {}
    windows = data.get("hwnds") or {}
    root, flash = hwnd(windows.get("S")), hwnd(windows.get("F"))
    host_pid = ((data.get("candidate") or {}).get("observed") or {}).get("pid")
    flash_pid = (data.get("flashPlayer") or {}).get("pid")
    attempt = ready.get("attemptId")
    if not (root and flash and host_pid and flash_pid and attempt == data.get("expectedAttemptId") and
            ready.get("slot") == data.get("slot") and ready.get("slot")):
        return None

    def find_one(text):
        matches = [index for index, line in enumerate(lines) if text == line[13:]]
        return matches[0] if len(matches) == 1 else None

    prewarm = find_one(f"[Prewarm] triggered attemptId={attempt}")
    spawn = find_one(f"[Guardian] Flash Player started, PID={flash_pid}")
    identity = [index for index, line in enumerate(lines) if line == windows.get("line")]
    if prewarm is None or spawn is None or len(identity) != 1 or not prewarm < spawn < identity[0]:
        return None
    segment = [(index, lines[index], fields(lines[index])) for index in range(prewarm, identity[0] + 1)]
    bridges = [index for index, _, row in segment if row.get("event") == "world_pointer_bridge_start" and
               row.get("hostPid") == str(host_pid) and hwnd(row.get("owner")) == root and row.get("ownerPid") == str(host_pid) and
               hwnd(row.get("source")) == flash and row.get("sourcePid") == str(flash_pid) and row.get("phase") == "before_create"]
    if len(bridges) != 1 or not spawn < bridges[0]:
        return None
    transitions = ("[LaunchFlow] OnEmbedResult=True", "[LaunchFlow] Embedding -> WaitingGameReady",
                   "[LaunchFlow] WaitingGameReady -> Ready", "[LaunchFlow] performing reveal (panel swap)")
    actual = [[(index, line) for index, line, _ in segment if line[13:] == expected] for expected in transitions]
    if len(actual[2]) != 1 or stamp(actual[2][0][1]) is None:
        return None
    host_ready = actual[2][0][0]
    # The AS2 message may be queued while Embed is still pending. Bind it to the
    # attempt, but use the Host publication as the start of live authority.
    requests = []
    for index, line, _ in segment:
        prefix = "[XmlSocket:JSON] "
        if not line[13:].startswith(prefix) or '"task":"bootstrap_ready"' not in line:
            continue
        try:
            message = json.loads(line[13 + len(prefix):])
        except json.JSONDecodeError:
            continue
        if message.get("task") == "bootstrap_ready" and message.get("payload", {}).get("attemptId") == attempt:
            requests.append((index, line))
    if not requests or not bridges[0] < requests[0][0] <= host_ready:
        return None

    def receipt(item):
        return {"lineNumber": item[0] + 1, "line": item[1]}

    next_attempt = next((index for index in range(identity[0] + 1, len(lines))
                         if lines[index][13:].startswith("[Prewarm] triggered attemptId=")), len(lines))
    selected_audits = []
    for index in range(spawn, next_attempt):
        line = lines[index]
        row = fields(line)
        if (row.get("event") in ("r1_passive_focus_audit", "flash_focus_handoff") and
                hwnd(row.get("root")) == root and hwnd(row.get("flash")) == flash):
            selected_audits.append(receipt((index, line)))
    proof = {"verified": False, "clientReady": receipt(requests[0]), "hostReady": receipt(actual[2][0]),
             "hostPid": host_pid, "flashPid": flash_pid, "attempt": attempt, "rootHwnd": root, "flashHwnd": flash,
             "audits": selected_audits}
    records = [item for item in segment if item[2].get("event") == "passive_bootstrap_publication" and
               hwnd(item[2].get("flash")) == flash and item[2].get("pid") == str(flash_pid)]
    published = [item for item in records if item[2].get("stage") == "published"]
    pending = [item for item in records if item[2].get("stage") == "pending"]
    if len(published) != 1 or len(pending) > 1 or not all(len(found) == 1 for found in actual):
        return proof
    publication, published_line, event = published[0]
    on_embed, waiting, _, reveal = (found[0][0] for found in actual)
    if not (bridges[0] < publication < on_embed < waiting < host_ready < reveal < identity[0] and
            str(event.get("epoch", "")).isdigit() and
            (not pending or bridges[0] < pending[0][0] < publication and pending[0][2].get("epoch") == event.get("epoch"))):
        return proof

    audit = [(index, line, row) for index, line, row in segment if row.get("event") == "r1_passive_focus_audit" and
             hwnd(row.get("root")) == root and hwnd(row.get("flash")) == flash and index < publication]
    if not audit:
        return proof
    cleared_at, cleared_line, cleared = audit[-1]
    if not (bridges[0] < cleared_at < publication and cleared.get("stage") == "bootstrap" and
            cleared.get("queried") == "True" and cleared.get("enabled") == cleared.get("flashFocused") == "False" and
            all(hwnd(cleared.get(key)) is not None and hwnd(cleared[key]) != flash for key in ("sourceThreadFocus", "rootThreadFocus")) and
            stamp(published_line) is not None and stamp(cleared_line) is not None and
            relative_time(stamp(published_line), stamp(cleared_line)) >= 0):
        return proof

    return {**proof, "verified": True, "publication": receipt((publication, published_line)),
            "pending": receipt(pending[0]) if pending else None, "clear": receipt((cleared_at, cleared_line)),
            "hostEmbedResult": receipt(actual[0][0]), "hostReveal": receipt(actual[3][0]), "epoch": event["epoch"]}


def classify_chain_focus(data, launcher_lines=None):
    reported = data.get("sourceFocus") or {}
    result = {"businessStatus": "BLOCKED", "lifecycleStatus": reported.get("status", "NOT_RUN"),
              "originalAggregate": reported.get("status", "NOT_RUN"), "scope": "One qualified game/probe window.",
              "runtimeViolations": [], "bootstrapPositiveLines": [], "unresolved": []}
    windows = data.get("hwnds") or {}
    root, present, flash = (hwnd(windows.get(key)) for key in ("S", "P", "F"))
    identity = fields(windows.get("line", ""))
    candidate = data.get("candidate", {}).get("observed") or {}
    start = data.get("observations", {}).get("startBoundary") or {}
    runtime_ready = data.get("runtimeReady") or {}
    topology = data.get("windowTopology", {}).get("topWindows", [])
    initial = data.get("observations", {}).get("initialPassive") or {}
    pid = candidate.get("pid")
    ready_attempt = runtime_ready.get("attemptId")
    roots_match = (root and present and flash and len({root, present, flash}) == 3 and
                   (hwnd(identity.get("S")), hwnd(identity.get("P")), hwnd(identity.get("F"))) == (root, present, flash) and
                   type(pid) is int and identity.get("hostPid") == str(pid) and start.get("terminalSessionPid") == pid and
                   start.get("terminalLifecycleId") and start.get("snapshot", {}).get("sessionPid") == pid and
                   any(hwnd(win.get("hwnd")) == root and win.get("pid") == pid and win.get("taskbarActivatableRoot") is True for win in topology) and
                   any(hwnd(win.get("hwnd")) == present and win.get("pid") == pid and hwnd(win.get("owner")) == root for win in topology))
    launch = [line for window in data.get("rawLogs", []) if window.get("label") == "startup" for line in window.get("lines", [])]
    flash_pid = data.get("flashPlayer", {}).get("pid")
    slot = runtime_ready.get("slot")
    ready_pattern = (re.compile(r"\[Bootstrap\] sent bootstrap_ready attemptId=" + re.escape(ready_attempt) + r" ok=true\b")
                     if isinstance(ready_attempt, str) else None)
    slot_pattern = re.compile(r"\[SaveManager\.preload\] savePath=" + re.escape(slot) + r"\b") if isinstance(slot, str) else None
    reached = [line for line in launch if ready_pattern and slot_pattern and ready_pattern.search(line) and slot_pattern.search(line)]
    if not (roots_match and initial.get("i1Bound") is True and hwnd(initial.get("flashHwnd")) == flash and
            type(flash_pid) is int and any(f"[Guardian] Flash Player started, PID={flash_pid}" in line for line in launch) and
            len(reached) == 1 and stamp(reached[0]) is not None and stamp(windows["line"]) is not None):
        return result
    publication = host_publication_boundary(data, launcher_lines) if launcher_lines is not None else None
    verified_host = bool(publication and publication["verified"])
    anchor_source = ("publication" if verified_host else "hostReady")
    anchor = stamp(publication[anchor_source]["line"]) if publication else stamp(reached[0]) if launcher_lines is None else None
    result.update(launchBoundary=reached[0].split(" ", 1)[0] + " " + ready_pattern.search(reached[0])[0],
                  worldIdentity=windows["line"], pid=pid, guardianHwnd=root, flashHwnd=flash,
                  boundarySource="verified_host_publication" if verified_host else
                  "legacy_as2_ready_receipt" if launcher_lines is None else "unverified_host_publication",
                  hostPublication=publication)
    samples = data.get("win32FocusSamples") or []
    qualified = [sample for sample in samples if sample.get("flashPid") == flash_pid and hwnd(sample.get("hwnd")) == flash and
                 query_rows(sample.get("focusSamples"))]
    wins_focus = [sample for sample in qualified if any(row["flashFocused"] or hwnd(row.get("hwndFocus")) == flash
                                                       for row in sample["focusSamples"])]
    result["win32QuerySamples"] = len(qualified)
    result["runtimeViolations"].extend(wins_focus)
    if initial.get("flashHasKeyboardFocus") is True:
        result["runtimeViolations"].append({"initialPassive": initial})
    probe_rows = [call["response"] for call in data.get("probeCalls", []) if isinstance(call.get("response"), dict) and
                  "flashHasKeyboardFocus" in call["response"]]
    probe_qualified = [row for row in probe_rows if hwnd(row.get("flashHwnd")) == flash and
                       row.get("sessionId") == initial.get("sessionId") and type(row["flashHasKeyboardFocus"]) is bool]
    counters = [row["passiveFocusCounts"] for row in probe_qualified if isinstance(row.get("passiveFocusCounts"), dict)]
    runtime_metrics = ("runtimeRawFocus", "runtimeFocusNotifications", "runtimeStyleViolations")
    counter_data_valid = bool(counters) and all(row.get("sourceHook") is True and row.get("hostHook") is True and
        all(type(row.get(key)) is int and row[key] >= 0 for key in ("samples", "failedQueries", *runtime_metrics))
        for row in counters)
    result["postReadyProbeSamples"] = len(probe_qualified)
    result["postReadyLastCounters"] = counters[-1] if counters else None
    if positive_probe := next((row for row in probe_qualified if row["flashHasKeyboardFocus"]), None):
        result["runtimeViolations"].append({"probeStatus": positive_probe})
    if positive_counter := next((row for row in counters if any(
            isinstance(row.get(key), int) and row[key] > 0 for key in runtime_metrics[:2])), None):
        result["runtimeViolations"].append({"probeCounter": positive_counter})
    observed_lines = list(reported.get("evidence") or [])
    if publication:
        observed_lines.extend(row["line"] for row in publication["audits"])
    rows = [(line, fields(line), stamp(line)) for line in dict.fromkeys(observed_lines)]
    verified_runtime = [(line, row, time) for line, row, time in rows if time is not None and row.get("stage") == "runtime" and
                        hwnd(row.get("root")) == root and hwnd(row.get("flash")) == flash and row.get("queried") == "True"]
    start_of_runtime = min((relative_time(time, anchor) for _, _, time in verified_runtime), default=0) if anchor is not None else None
    audited = Counter()
    for line, row, time in rows:
        event = row.get("event")
        if event not in ("r1_passive_focus_audit", "flash_focus_handoff"):
            result["unresolved"].append(line)
            continue
        exact = hwnd(row.get("root")) == root and hwnd(row.get("flash")) == flash
        relative = relative_time(time, anchor) if time is not None and anchor is not None else None
        positive = (event == "flash_focus_handoff" or row.get("flashFocused") == "True" or
                    any(hwnd(row.get(name)) == flash for name in ("sourceThreadFocus", "rootThreadFocus")))
        if not exact or time is None:
            result["unresolved"].append(line)
            continue
        if event == "r1_passive_focus_audit" and (row.get("queried") != "True" or
                row.get("flashFocused") not in ("True", "False") or
                any(hwnd(row.get(name)) is None for name in ("sourceThreadFocus", "rootThreadFocus"))):
            result["unresolved"].append(line)
            continue
        stage = row.get("stage")
        if stage not in ("runtime", "bootstrap"):
            result["unresolved"].append(line)
            if positive and relative is not None and relative >= 0:
                result["runtimeViolations"].append(line)
            continue
        if relative is None:
            if positive and stage == "runtime":
                result["runtimeViolations"].append(line)
            else:
                result["unresolved"].append(line)
            continue
        genuinely_early = stage == "bootstrap" and relative < min(0, start_of_runtime)
        if positive:
            if genuinely_early:
                result["bootstrapPositiveLines"].append(line)
            else:
                result["runtimeViolations"].append(line)
        if stage == "runtime" and event == "r1_passive_focus_audit":
            audited["runtime"] += 1
            if relative >= 0:
                audited["postReady"] += 1
                if relative >= relative_time(stamp(windows["line"]), anchor):
                    audited["postPresentationIdentity"] += 1
        if genuinely_early:
            audited["bootstrap"] += 1
    result["auditCounts"] = dict(audited)
    if result["runtimeViolations"]:
        result["businessStatus"] = "FAIL"
        result["lifecycleStatus"] = "FAIL"
    elif ((launcher_lines is None or verified_host) and qualified and len(qualified) == len(samples) and
          len(probe_qualified) == len(probe_rows) and counter_data_valid and
          all(row["failedQueries"] == 0 and row["runtimeStyleViolations"] == 0 for row in counters) and
          audited["postPresentationIdentity"] >= 2 and not result["unresolved"]):
        result["businessStatus"] = "PASS"
    if result["bootstrapPositiveLines"]:
        result["lifecycleStatus"] = "FAIL"
    return result


def checked_chain_cases(cases, focus):
    raw = {case: {name: detail.get("status") for name, detail in value.get("checks", {}).items()}
           for case, value in cases.items()}
    scoped = {case: checks.copy() for case, checks in raw.items()}
    for case, control in _FOCUS_CHECKS:
        if case not in raw or raw[case].get(control) != "FAIL":
            continue
        detail = cases[case]["checks"][control].get("evidence") or {}
        if control == "focus":
            win32 = detail.get("win32")
            qualified = query_rows(win32)
            if detail.get("reported") is True or (qualified and any(row["flashFocused"] for row in win32)):
                continue
            distinguishable = detail.get("reported") is False and qualified
        else:
            violations = detail.get("focusViolations") or []
            distinguishable = bool(violations) and set(violations) == set(focus["bootstrapPositiveLines"])
        if focus["businessStatus"] == "FAIL":
            continue
        scoped[case][control] = ("PASS" if focus["businessStatus"] == "PASS" and distinguishable and focus["bootstrapPositiveLines"]
                                 else "BLOCKED")
    return raw, scoped
