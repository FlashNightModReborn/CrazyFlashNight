"""Check a bounded event window for the normal HUD Modifier journey."""

from evidence import identities_match, link, read_json, same_path
from trace_entry import with_raw_trace


def positive(value):
    return type(value) is int and value > 0


def hwnd(value):
    if type(value) is int:
        return value
    if isinstance(value, str) and value.startswith("0x"):
        return int(value, 16)
    return 0


def gesture_result(case, events, action, expected_injected):
    handoff = case.get(action) or {}
    selected = [events.get(sequence) for sequence in handoff.get("edgeSequences", [])]
    if len(selected) != 2 or any(row is None for row in selected):
        return {"status": "BLOCKED", "reason": "The independent normal OS Down and Up were not both recorded."}
    down, up = selected
    valid_edges = ((down.get("event"), down.get("edge"), up.get("event"), up.get("edge")) ==
                   ("mouse.route", "down", "mouse.route", "up") and
                   all(row.get("injected") is expected_injected for row in selected) and
                   0 < down["seq"] < up["seq"] and len({row.get("edgeId") for row in selected}) == 2 and
                   all(row.get("edgeId") and hwnd(row.get("hitHwnd")) for row in selected))
    if not valid_edges:
        return {"status": "BLOCKED", "reason": "Normal OS stimulus, provenance or hit-window evidence is missing."}
    down_id, up_id = down["edgeId"], up["edgeId"]
    presses = [row for row in events.values() if row.get("event") == "modifier.press" and row.get("edgeId") in (down_id, up_id)]
    begins = [row for row in events.values() if row.get("event") == "modifier.begin" and row.get("edgeId") == down_id]
    if len(presses) != 2 or len(begins) != 1:
        unpaired = [row["seq"] for row in events.values() if row.get("event") == "modifier.press" and
                    not row.get("mouseId") and row.get("generation") == case.get("generation") and
                    down["seq"] < row["seq"]]
        if unpaired:
            return {"status": "BLOCKED", "reason": "Modifier press observed without an unambiguous hook edge ID.",
                    "unpairedSequences": unpaired}
        return {"status": "FAIL", "reason": "Mouse route recorded both edges but Modifier ingress or begin was incomplete.",
                "pressSequences": [row["seq"] for row in presses], "beginSequences": [row["seq"] for row in begins]}
    expected_receivers = {hwnd(value) for value in case.get("modifierReceivers", [])} - {0}
    if ({row.get("edgeId") for row in presses} != {down_id, up_id} or
            any(hwnd(row.get("receiverHwnd")) not in expected_receivers or not hwnd(row.get("rootOwner")) for row in presses)):
        return {"status": "BLOCKED", "reason": "The receiving HWND or its session root-owner was not confirmed."}
    begin = begins[0]
    ticket = begin.get("gestureId")
    instance = case.get("generation")
    expected_target = {"page": "modifier.button.tab:items", "close": "modifier.button.close"}[action]
    if begin.get("accepted") is not True or not ticket or begin.get("target") != expected_target or begin.get("generation") != instance:
        return {"status": "FAIL", "reason": "The intended Modifier target did not acquire an exact instance ticket.",
                "beginSequence": begin["seq"]}
    related = [row for row in events.values() if row.get("gestureId") == ticket and row.get("generation") == instance]
    commits = [row for row in related if row.get("event") == "modifier.commit" and row.get("edgeId") == up_id]
    cancellations = [row for row in related if row.get("event") == "modifier.cancel"]
    if (len(commits) != 1 or cancellations or commits[0].get("target") != expected_target or
            not down["seq"] < begin["seq"] < up["seq"] < commits[0]["seq"]):
        return {"status": "FAIL", "reason": "The gesture did not commit exactly once after the matching Up.",
                "gestureId": ticket, "commitSequences": [row["seq"] for row in commits],
                "cancellationSequences": [row["seq"] for row in cancellations]}
    if action == "page":
        pages = [row for row in related if row.get("event") == "modifier.page" and row.get("after") == "items" and
                 row.get("before") != "items"]
        return {"status": "PASS" if len(pages) == 1 else "FAIL", "gestureId": ticket,
                "commitSequence": commits[0]["seq"], "pageSequences": [row["seq"] for row in pages]}

    token = case.get("token")
    if not isinstance(token, str) or not token:
        return {"status": "BLOCKED", "reason": "No AS2 session token was linked to the UI instance."}
    close_events = ("modifier.close_requested", "modifier.close_core", "modifier.suspend", "modifier.close_sent", "as2.closed")
    events_after_commit = [row for row in events.values() if row.get("generation") == instance and
                           row.get("token") == token and row["seq"] > up["seq"]]
    matches = [[row for row in events_after_commit if row.get("event") == name] for name in close_events]
    if any(len(group) > 1 for group in matches):
        return {"status": "FAIL", "reason": "A close lifecycle stage executed more than once for the same token."}
    missing = [name for name, group in zip(close_events, matches) if not group]
    if missing:
        return {"status": "BLOCKED" if missing == ["as2.closed"] else "FAIL", "missingCloseStages": missing}
    ordered = [group[0]["seq"] for group in matches]
    return {"status": "PASS" if ordered == sorted(ordered) and matches[2][0].get("visible") is False else "FAIL",
            "gestureId": ticket, "commitSequence": commits[0]["seq"], "closeSequences": dict(zip(close_events, ordered))}


def read_entry(file, expected):
    run = read_json(file)
    trace = link((file.parent / run["trace"]).resolve()) if run.get("trace") else None
    if trace:
        run = with_raw_trace(run, file, expected)
    session = run.get("observed") or {}
    desktop = run.get("desktop") or {}
    matches = (run.get("schema") == "cf7-modifier-default-entry.v1" and run.get("runId") and positive(session.get("pid")) and
               identities_match(session, expected) and same_path(session.get("processPath"), expected["processPath"]) and
               session.get("runtimeMode") == "isolated_candidate")
    data = {"status": "BLOCKED", "identityMatched": bool(matches), "stimulus": run.get("stimulus"),
            "cases": {}, "raw": link(file), "trace": trace}
    if not matches:
        return {**data, "reason": "Runtime identity/actual process was not verified."}
    if any(desktop.get(key) != "Default" for key in ("inputDesktop", "threadDesktop")):
        return {**data, "reason": "Both the target window and stimulus must use the Default input desktop."}
    if (not str(run.get("slot", "")).startswith("cf7_agent_") or not run.get("attemptId") or
            run.get("windowCompleted") is not True or type(run.get("droppedEvents")) is not int or run["droppedEvents"] != 0):
        return {**data, "reason": "Exact isolated attempt or bounded observation window is missing."}
    if run.get("stimulus") not in ("os-sendinput", "operator-physical"):
        return {**data, "reason": "A direct HWND message or probe does not exercise normal OS ingress."}
    raw_events = run.get("events") or []
    sequences = [row.get("seq") for row in raw_events]
    if any(not positive(seq) for seq in sequences) or sequences != sorted(set(sequences)):
        return {**data, "reason": "Ambiguous event ordering in the observation window."}
    events = {row["seq"]: row for row in raw_events}
    groups = run.get("cases") or []
    if len({row.get("id") for row in groups}) != len(groups):
        return {**data, "reason": "Duplicate journey case identifier."}
    held_case_seen = False
    stable_case_seen = False
    for case in groups:
        row = {"page": gesture_result(case, events, "page", run["stimulus"] == "os-sendinput"),
               "close": gesture_result(case, events, "close", run["stimulus"] == "os-sendinput")}
        group_events = [event for event in raw_events if event.get("caseId") == case.get("id") or
                        case.get("id") in event.get("journeyIds", [])]
        opens = [event for event in group_events if event.get("event") == "modifier.open" and event.get("source") == "normal_hud"]
        generations = [event.get("generation") for event in opens]
        observed_close = row["close"].get("closeSequences", {}).get("as2.closed")
        row["openReopen"] = (len(generations) == 2 and all(positive(value) for value in generations) and
                             generations[0] == case.get("generation") and generations[1] > generations[0] and
                             (not observed_close or opens[0]["seq"] < observed_close < opens[1]["seq"]))
        keys = case.get("keyboard") or {}
        held_group = case.get("holdDShift") is True
        row["heldKeyboardUnchanged"] = (keys.get("beforeAdmittedD") is True and keys.get("afterAdmittedD") is True and
                                        keys.get("beforeAdmittedShift") is True and keys.get("afterAdmittedShift") is True and
                                        positive(keys.get("epochBefore")) and keys.get("epochBefore") == keys.get("epochAfter")) if held_group else None
        held_case_seen |= held_group
        stable_case_seen |= not held_group
        data["cases"][case["id"]] = row
    rows = data["cases"].values()
    if any(row[step]["status"] == "FAIL" for row in rows for step in ("page", "close")):
        return {**data, "status": "FAIL"}
    if (stable_case_seen and held_case_seen and all(row["page"]["status"] == row["close"]["status"] == "PASS" and
            row["openReopen"] and row["heldKeyboardUnchanged"] is not False for row in rows)):
        return {**data, "status": "PASS"}
    return data
