"""Qualify the real Modifier editor-close foreground and first fresh key chain."""

from pathlib import Path

from evidence import link, read_json, same_hash, same_path


def read_edited_close(file, acknowledgement_file, expected, startup):
    raw = read_json(file)
    acknowledgement = read_json(acknowledgement_file)
    result = {"status": "BLOCKED", "raw": link(file), "as2Raw": link(acknowledgement_file)}
    if startup.get("status") != "PASS" or raw.get("pid") != startup["process"]["pid"]:
        return result
    start = raw.get("start") or {}
    session = raw.get("traceSession")
    actual_core = (start.get("data") or {}).get("corePath")
    expected_core = str(Path(expected["processPath"]).with_suffix(".dll"))
    if (not same_hash(raw.get("buildIdentity"), expected["buildIdentity"]) or
            not same_hash(raw.get("coreSha256"), expected["coreSha256"]) or not same_path(actual_core, expected_core) or
            start.get("session") != session or start.get("data", {}).get("pid") != raw["pid"]):
        return result
    keys = raw.get("qa") or []
    observed = {event["event"]: event for event in keys}
    entry = observed.get("unitPageInput.preCloseEnter", {})
    after = observed.get("modifier.after", {})
    if any(row.get("attemptId") != startup["ready"]["attemptId"] or row.get("slot") != startup["ready"]["slot"] or
           row.get("pid") != raw["pid"] or not same_hash(row.get("payloadClosure"), expected["payloadClosure"]) for row in (entry, after)):
        return result
    rows = {key: [item for item in raw.get("trace", []) if item.get("event") == key] for key in
            ("modifier.close_requested", "modifier.close_core", "modifier.close_focus", "modifier.suspend", "modifier.close_sent", "keyboard.decision")}
    if any(len(events) != (2 if key == "keyboard.decision" else 1) for key, events in rows.items()):
        return {**result, "missingOrDuplicateTraceStages": [key for key, events in rows.items() if len(events) != (2 if key == "keyboard.decision" else 1)]}
    records = [item for events in rows.values() for item in events]
    if any(row.get("session") != session or row.get("processRunId") != start.get("processRunId") for row in records):
        return result
    request, core, transfer, suspend, delivered, down, up = records
    closed = acknowledgement.get("event") or {}
    token = request["data"].get("token")
    accepted_marker = f"session={session} event=modifier.closed token={token} accepted=true"
    if (closed.get("session") != session or closed.get("processRunId") != start.get("processRunId") or
            closed.get("event") != "as2.observation" or accepted_marker not in closed.get("data", {}).get("raw", "")):
        return result
    sequences = [item["seq"] for item in (request, core, transfer, suspend, delivered, closed, down, up)]
    guardian = observed.get("modifier.preCloseForeground", {}).get("root")
    key_start = observed.get("modifier.firstKeyBefore") or {}
    outcome = observed.get("modifier.firstKeyOutcome") or {}
    lease = entry.get("input", {}).get("currentTextLease") or {}
    condition = (isinstance(token, str) and token and all(item["data"].get("token") == token for item in (core, transfer, suspend, delivered)) and
                 sequences == sorted(set(sequences)) and request["data"].get("userInitiated") is True and core["data"].get("requestKeyboard") is True and
                 type(guardian) is int and guardian > 0 and transfer["data"].get("attempted") is True and transfer["data"].get("succeeded") is True and
                 transfer["data"].get("after") == guardian and suspend["data"].get("visible") is False and
                 suspend["data"].get("inputVisible") is False and delivered["data"].get("sent") is True and
                 str(lease.get("endpointId", "")).startswith("modifier.edit.") and after.get("input", {}).get("currentTextLease") is None and
                 [down["data"].get("message"), up["data"].get("message")] == [256, 257] and
                 all(item["data"].get("vk") == 65 and item["data"].get("foreground") == guardian and item["data"].get("blocked") is False and
                     item["data"].get("liveApplicationForeground") is True and item["data"].get("flags", 0) & 16 for item in (down, up)) and
                 key_start.get("foreground") == guardian and outcome.get("foreground") == guardian and outcome.get("moved") is True and
                 outcome.get("gameplayAdmitted") is True and outcome.get("delta", 0) < 0)
    return {**result, "status": "PASS" if condition else "FAIL", "guardian": guardian, "traceSession": session,
            "token": token, "sequences": sequences, "lease": lease, "firstNewKey": outcome,
            "afterPointerUpMs": key_start.get("afterPointerUpMs"), "inputSource": "OS SendInput observed in the production keyboard hook"}
