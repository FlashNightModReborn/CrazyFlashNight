"""Connect raw FocusTrace v2 events to the operator's bounded journey windows."""

import re
import json
from pathlib import Path

from evidence import same_path


def read_focus_trace(file):
    marker = "[FocusTrace] "
    with Path(file).open(encoding="utf-8-sig") as stream:
        for line in stream:
            if marker in line:
                payload = line.split(marker, 1)[1]
            elif line.lstrip().startswith("{"):
                payload = line
            else:
                continue
            row = json.loads(payload)
            if row.get("v") == 2 and row.get("event"):
                yield row


def normalize_trace_row(row):
    data = row.get("data") or {}
    event = row["event"]
    norm = {**data, "seq": row["seq"], "event": event, "mouseId": data.get("mouseId") or row.get("gesture")}
    if event in ("mouse.down", "mouse.up", "mouse.edge"):
        edge = event[6:] if event != "mouse.edge" else data.get("edge")
        return {**norm, "edge": edge, "edgeId": f"{norm['mouseId']}:{edge}",
                "hitHwnd": (data.get("windows", {}).get("hitCandidate") or {}).get("hwnd")}
    if event == "modifier.press":
        edge = {513: "down", 514: "up"}.get(data.get("message"))
        return {**norm, "edgeId": f"{norm['mouseId']}:{edge}", "receiverHwnd": data.get("receiver"),
                "rootOwner": (data.get("receiverWindow") or {}).get("rootOwner")}
    if event in ("modifier.begin", "modifier.commit", "modifier.cancel"):
        ticket = data.get("ticket") or {}
        edge = "down" if event == "modifier.begin" else "up"
        return {**norm, "edgeId": f"{norm['mouseId']}:{edge}", "gestureId": ticket.get("GestureId", ticket.get("gestureId"))}
    if event == "modifier.page":
        return {**norm, "before": data.get("previous"), "after": data.get("tab")}
    return norm


def select_trace(file, index, expected):
    trace = list(read_focus_trace(file))
    starts = [row for row in trace if row["event"] == "trace.start" and row.get("session") == index.get("traceSession")]
    if len(starts) != 1:
        raise ValueError("The indexed FocusTrace session has no unique trace.start.")
    start = starts[0]
    observed = index.get("observed") or {}
    expected_core = str(Path(expected["processPath"]).with_suffix(".dll"))
    if start["data"].get("pid") != observed.get("pid") or not same_path(start["data"].get("corePath"), expected_core):
        raise ValueError("The raw FocusTrace PID/Core DLL does not match the observed candidate process.")
    selected = [row for row in trace if all(row.get(key) == start.get(key) for key in ("session", "generation", "processRunId"))]
    dropped = sum(row.get("count", 0) for row in selected if row["event"] == "trace.dropped")
    sequenced = [row for row in selected if type(row.get("seq")) is int]
    sequences = {row["seq"] for row in sequenced}
    missing = max(sequences) - min(sequences) + 1 - len(sequences)
    return [normalize_trace_row(row) for row in sequenced], max(dropped, missing)


def bind_journey(index, case, events):
    window = [row for row in events if case["firstSeq"] <= row["seq"] <= case["lastSeq"]]
    if not window:
        raise ValueError(f"No events in window {case['id']}.")
    opens = [row for row in window if row["event"] == "modifier.open"]
    seen_opens = []
    for mouse_id in case.get("hudOpenMouseIds", []):
        hud_hit = next((row for row in window if row["event"] == "mouse.down" and row["mouseId"] == mouse_id and
                        row.get("hitHwnd") in case.get("hudReceivers", [])), None)
        up = next((row for row in window if row["event"] == "mouse.up" and row["mouseId"] == mouse_id), None)
        if hud_hit and up and hud_hit["seq"] < up["seq"]:
            opened = next((row for row in opens if row["seq"] > up["seq"]), None)
            if opened and opened["seq"] not in seen_opens:
                opened["source"] = "normal_hud"
                opened.setdefault("journeyIds", []).append(case["id"])
                seen_opens.append(opened["seq"])
    generation = opens[0].get("generation") if opens else None
    token = opens[0].get("token") if opens else None
    surface = (opens[0].get("surface") or {}).get("hwnd") if opens else None
    receivers = [surface, *case.get("ownedReceivers", [])]

    for action in ("page", "close"):
        mouse_id = case.get(action + "MouseId")
        pair = []
        for edge in ("down", "up"):
            message = {"down": 513, "up": 514}[edge]
            path = [row for row in window if row["event"] == "mouse.route" and row["mouseId"] == mouse_id and
                    row.get("message") == message]
            physical = [row for row in window if row["event"] in ("mouse.down", "mouse.up", "mouse.edge") and
                        row["mouseId"] == mouse_id and row.get("edge") == edge]
            if len(path) == 1 and len(physical) == 1 and physical[0]["seq"] < path[0]["seq"]:
                physical[0].update(event="mouse.route", routeSequence=path[0]["seq"], route=path[0].get("route"),
                                   swallowed=path[0].get("swallowed"))
                pair.append(physical[0]["seq"])
        case[action] = {"edgeSequences": pair}

    commits = {row["mouseId"]: row for row in window if row["event"] == "modifier.commit"}
    for row in window:
        if row["event"] == "modifier.page" and row["mouseId"] in commits:
            row["gestureId"] = commits[row["mouseId"]].get("gestureId")
        if row["event"] == "modifier.close_sent" and row.get("token") == token and row.get("sent") is True:
            row["generation"] = generation
        if row["event"] == "as2.observation":
            raw = row.get("raw", "")
            match = re.search(r"\bsession=([a-f0-9]{32}) event=modifier\.closed token=(\S+) accepted=true\b", raw)
            if match and match[1] == index["traceSession"] and match[2] == token:
                row.update(event="as2.closed", token=token, generation=generation)
    return {**case, "generation": generation, "token": token, "modifierReceivers": receivers}


def with_raw_trace(index, file, expected):
    trace = (file.parent / index["trace"]).resolve()
    events, dropped = select_trace(trace, index, expected)
    cases = [bind_journey(index, case, events) for case in index.get("cases", [])]
    return {**index, "droppedEvents": dropped, "events": events, "cases": cases}
