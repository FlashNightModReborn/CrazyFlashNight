"""Validate the scoped operator journeys saved by the Default desktop driver."""

import json
import re

from evidence import digest, identities_match, link, read_json, same_hash, same_path


def read_json_lines(file):
    with file.open(encoding="utf-8-sig") as stream:
        return [json.loads(line) for line in stream if line.strip()]


def real_desktop(sample):
    return (sample.get("threadDesktop") == "Default" and sample.get("inputDesktop") == "Default" and
            sample.get("threadReceivesInput") is True)


def active_process(sample, expected, startup):
    return (startup.get("status") == "PASS" and sample.get("pid") == startup["process"]["pid"] and
            identities_match(sample, expected) and same_path(sample.get("processPath"), expected["processPath"]))


def read_global_panels(file, expected, startup):
    data = read_json(file)
    result = {"status": "BLOCKED", "raw": link(file), "routes": {},
              "scope": "Default desktop Help and KShop entry, displayed content and exact Escape return."}
    if data.get("schema") != "cf7-review-g46-global-routes.v1" or not active_process(data["candidate"], expected, startup):
        return result
    for route in data.get("routes", []):
        panel = route["panel"]
        if panel not in ("help", "kshop") or panel in result["routes"]:
            return result
        instance = route["instance"]
        rows = {row["event"]: row for row in route["qa"]}
        order = [rows[panel + "." + event] for event in ("before", "opened", "beforeClose", "closed")]
        before, opened, before_close, closed = order
        desktops = route["desktop"]
        click, display, returned = desktops[-3:]
        root = returned["root"]
        popup = display["foreground"]
        snapshots = [link(file.parent / image["file"]) for image in route["screenshots"]]
        screenshot_matches = len(snapshots) >= 4 and all(same_hash(found["sha256"], image["sha256"])
            for found, image in zip(snapshots, route["screenshots"], strict=True))
        active = {"name": panel, "instanceId": instance}
        inactive = {"name": None, "instanceId": None}
        qa_bound = all(row["pid"] == startup["process"]["pid"] and row["attemptId"] == before["attemptId"] and
                       row["runId"] == before["runId"] and
                       all(same_hash(row.get(locus), expected[locus]) for locus in ("buildIdentity", "payloadClosure"))
                       for row in order)
        desktop_bound = all(row["pid"] == startup["process"]["pid"] and row["root"] == root and real_desktop(row["desktop"])
                            for row in desktops)
        escaped = (rows.get("keyboard", {}).get("action") == "Escape" and
                   rows["keyboard"].get("source") == "OS SendInput, injected")
        observed = (qa_bound and desktop_bound and escaped and click.get("stimulus") == "OS SendInput, injected" and
                    click.get("targetBeforeDown") and click["foreground"] == root and popup != root and
                    any(win["hwnd"] == popup and win["owner"] == root for win in display["windows"]) and
                    returned["foreground"] == root and all(win["hwnd"] != popup for win in returned["windows"]) and
                    opened["activePanel"] == before_close["activePanel"] == active and
                    before["activePanel"] == closed["activePanel"] == inactive and
                    opened["input"]["gameKeyboardAdmitted"] is False and closed["input"]["gameKeyboardAdmitted"] is True and
                    closed["input"]["flashHasKeyboardFocus"] is False and screenshot_matches)
        result["routes"][panel] = {
            "status": "PASS" if observed else "BLOCKED", "instanceId": instance,
            "guardianHwnd": root, "popupHwnd": popup, "screenshots": snapshots,
            "screenshotContentReviewed": route.get("visibleContentConfirmedFromScreenshot"),
            "uiaDocumentObserved": route.get("uiaDocumentObserved"),
        }
    if set(result["routes"]) == {"help", "kshop"} and all(route["status"] == "PASS" for route in result["routes"].values()):
        result["status"] = "PASS"
    return result


def read_native_editors(file, expected, startup):
    summary = read_json(file)
    base = file.parent
    process = read_json(base / "process.json")
    desktop = base / "desktop.jsonl"
    raw = base / "qa-events.jsonl"
    result = {"status": "BLOCKED", "raw": link(file), "operatorRows": link(raw), "fields": {},
              "scope": "Seven named native fields, typed drafts, Enter and Escape on the Default desktop."}
    if (not active_process(process, expected, startup) or not identities_match(summary, expected) or
            summary["pid"] != process["pid"] or summary["slot"] != process["slot"] or
            not same_hash(summary["evidenceSha256"], result["operatorRows"]["sha256"])):
        return result
    visits = read_json_lines(desktop)
    if not visits or not all(row["pid"] == process["pid"] and real_desktop(row["desktop"]) for row in visits):
        return result
    rows = read_json_lines(raw)
    expected_fields = {"itemQuery", "itemQuantity", "itemPageInput", "taskId", "unitLevel", "unitCount", "unitPageInput"}
    fields = {row["field"]: row for row in summary["nativeFields"]}
    if fields.keys() != expected_fields:
        return result
    for field, receipt in fields.items():
        run = [row for row in rows if row.get("runId") == receipt["runId"]]
        status_rows = {row["event"]: row for row in run if row["event"].startswith(field + ".")}
        initial, committed, cancelled = (status_rows[field + "." + stage] for stage in ("focus", "enter", "escape"))
        exact = all(row["pid"] == process["pid"] and row["attemptId"] == summary["attempt"] and
                    all(same_hash(row.get(key), expected[key]) for key in ("buildIdentity", "payloadClosure"))
                    for row in (initial, committed, cancelled))
        endpoint = "modifier.edit." + field
        lease_live = all(row["input"]["currentTextLease"]["endpointId"] == endpoint and
                         row["input"]["gameKeyboardAdmitted"] is False for row in (initial, committed))
        lease_gone = cancelled["input"]["currentTextLease"] is None
        matching = [row for row in run if row.get("field") == field and row["event"] == "draftObserved"]
        native = [row for row in run if row.get("field") == field and row["event"] == "nativeField"]
        commit_draft, escape_draft = matching[:2]
        draft_valid = (commit_draft["text"] == commit_draft["expected"] == receipt["restored"] and
                       escape_draft["text"] == escape_draft["expected"] != receipt["restored"] and
                       commit_draft["editor"] == escape_draft["editor"] == receipt["editor"] and
                       any(row["focus"] == receipt["editor"] and "WindowsForms10.Edit." in row["focusClass"] for row in native))
        raw_matched = sum(row == receipt for row in run) == 1
        result["fields"][field] = {"status": "PASS" if exact and lease_live and lease_gone and draft_valid and raw_matched
                                   else "BLOCKED", "editorHwnd": receipt["editor"], "restored": receipt["restored"]}
    tabs = [row["action"] for row in rows if row["event"] == "keyboard" and row["action"] in ("Tab", "Shift+Tab") and
            row["source"] == "OS SendInput, injected"]
    result["tabMoves"] = tabs
    if tabs == summary["tabSequence"] and set(tabs) == {"Tab", "Shift+Tab"} and all(
            row["status"] == "PASS" for row in result["fields"].values()):
        result["status"] = "PASS"
    return result


def read_passive_session(directory, expected, startup):
    status_file = directory / "passive-status.jsonl"
    result = {"status": "BLOCKED", "raw": link(status_file),
              "scope": "Passive probes sampled in this live session. General runtime and shutdown require separate coverage."}
    process = read_json(directory / "process.json")
    desktop_file = directory / "desktop.jsonl"
    desktop = read_json_lines(desktop_file)
    if not active_process(process, expected, startup) or not desktop or not all(
            row["pid"] == process["pid"] and real_desktop(row["desktop"]) for row in desktop):
        return result
    rows = read_json_lines(status_file)
    if not rows or not all(row.get("success") is True and row.get("i1Bound") is True for row in rows):
        return result
    counters = [row["passiveFocusCounts"] for row in rows]
    keys = ("samples", "failedQueries", "startupRawFocus", "startupCorrections", "runtimeRawFocus",
            "runtimeFocusNotifications", "runtimeStyleViolations")
    if not all(row.get("sourceHook") is True and row.get("hostHook") is True and
               all(type(row.get(key)) is int and row[key] >= 0 for key in keys) for row in counters):
        return result
    if not all(left[key] <= right[key] for left, right in zip(counters, counters[1:]) for key in keys):
        return result
    first, last = counters[0], counters[-1]
    raw_runtime = any(row.get("flashHasKeyboardFocus") is True for row in rows) or any(
        last[key] > 0 for key in ("runtimeRawFocus", "runtimeFocusNotifications", "runtimeStyleViolations"))
    if raw_runtime:
        result["status"] = "FAIL"
    elif len(rows) > 1 and last["samples"] > first["samples"] and last["failedQueries"] == 0:
        result["status"] = "PASS"
    return {**result, "pid": process["pid"], "desktop": link(desktop_file), "checks": len(rows),
            "firstUtc": rows[0]["utc"], "lastUtc": rows[-1]["utc"], "startupAndRuntimeCounters": last}


def read_focus_audit(file, expected, startup, passive):
    data = read_json(file)
    result = {"status": "BLOCKED", "raw": link(file), "scope": "Actual frozen launcher focus audit for one process."}
    if (passive.get("status") not in ("PASS", "FAIL") or startup.get("status") != "PASS" or
            startup["process"]["pid"] != data.get("pid") or not same_hash(data.get("buildIdentity"), expected["buildIdentity"])):
        return result
    root = data["rootHwnd"]
    root_desktop = [row for row in read_json_lines(file.parent / "desktop.jsonl") if row["root"] == root]
    if not root_desktop or not all(real_desktop(row["desktop"]) and row["pid"] == data["pid"] for row in root_desktop):
        return result
    events = data["events"]
    line_nums = [row["line"] for row in events]
    if line_nums != sorted(set(line_nums)):
        return result
    parsed = [dict(re.findall(r"([A-Za-z_]+)=([^ ]+)", row["text"])) for row in events]
    audits = [row for row in parsed if row.get("event") == "r1_passive_focus_audit"]
    bootstrap = [row for row in audits if row.get("stage") == "bootstrap"]
    runtime = [row for row in audits if row.get("stage") == "runtime"]
    transfers = [row for row in parsed if row.get("event") == "passive_bootstrap_focus"]
    aligned = all(int(row["root"], 16) == root for row in audits) and len(audits) == len(runtime) + len(bootstrap)
    transferred = all(row.get("valid") == "True" for row in transfers)
    same_source = {row["flash"] for row in runtime} == {row["flash"] for row in transfers}
    runtime_queried = [row for row in runtime if row.get("queried") == "True"]
    runtime_seen = [row for row in runtime_queried if row.get("flashFocused") == "True" or
                    row["flash"] in (row["sourceThreadFocus"], row["rootThreadFocus"])]
    valid_status_literals = all(row["flashFocused"] in ("True", "False") and row["enabled"] in ("True", "False")
                                for row in runtime_queried)
    original = file.parent / "launcher.log"
    original_rehashed = original.exists() and same_hash(digest(original), data["fullFileSha256"])
    if original_rehashed:
        lines = original.read_text(encoding="utf-8-sig").splitlines()
        if any(row["text"] != lines[row["line"] - 1] for row in events):
            return result
    if aligned and runtime_seen:
        result["status"] = "FAIL"
    elif (aligned and runtime and runtime_queried == runtime and transferred and same_source and valid_status_literals and
          passive["status"] == "PASS" and {row["stage"] for row in transfers} == {"early_reparent", "embed_reveal"}):
        result["status"] = "PASS"
    return {**result, "pid": data["pid"], "rootHwnd": root, "originalLogSha256": data["fullFileSha256"],
            "archivedFullLogRehashed": original_rehashed, "runtimeSamples": len(runtime),
            "runtimeQueriesSucceeded": len(runtime_queried), "runtimeFlashFocused": len(runtime_seen),
            "runtimeSourceReenabled": sum(row["enabled"] == "True" for row in runtime_queried),
            "bootstrapSamples": len(bootstrap), "bootstrapRawFlashFocused": sum(
                row.get("queried") == "True" and row.get("flashFocused") == "True" for row in bootstrap),
            "bootstrapTransitions": transfers}
