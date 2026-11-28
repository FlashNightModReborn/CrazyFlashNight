"""Recompute the observed authored Flash drag recovery from raw primary-input rows."""

import re

from evidence import digest, link, read_json, same_hash
from journeys import active_process


def read_bounty_recovery(file, observer_receipt, production_proof, root, expected, startup, materials):
    production_asset = "flashswf/UI/通缉令界面.swf"
    result = {"status": "BLOCKED", "raw": link(file),
              "scope": "An instrumented version of the authored asset inside the real game; OS primary-button input."}
    raw = read_json(file)
    if (not active_process(raw.get("identity", {}), expected, startup) or raw["slot"] != startup["process"]["slot"] or
            raw["attemptId"] != startup["ready"]["attemptId"] or materials.get("stages", {}).get("ready", {}).get("status") != "PASS"):
        return result
    case = raw["cases"]["bounty-watch"]
    observer = read_json(observer_receipt)
    proof = read_json(production_proof)
    actual_observer = (root / observer["swf"]).resolve()
    exact_assets = (actual_observer.is_relative_to(root) and actual_observer.as_uri() == case["fixtureLoad"][0] == case["mountState"][0] and
                    observer["exitCode"] == 0 and same_hash(digest(actual_observer), observer["after"]) and
                    materials.get("looseAssets", {}).get(production_asset) is True and
                    same_hash(digest(root / production_asset), proof["swfSha256"]) and
                    all(same_hash(digest(root / relative), source_sha) for relative, source_sha in proof["sourceSha256"].items()))
    if not exact_assets:
        return result
    result.update(observer=link(observer_receipt), production=link(production_proof),
                  observedAssetSha256=observer["after"], productionAssetSha256=proof["swfSha256"],
                  materialIdentity=materials["combinedMaterialSha256"], pid=raw["identity"]["pid"], slot=raw["slot"], attempt=raw["attemptId"])

    rows = [row.split("|") for row in case["rows"]]
    if not rows or not all(len(row) == 14 and int(row[0]) == number for number, row in enumerate(rows, start=1)):
        return result
    by_phase = {phase: [row for row in rows if row[1] == phase]
                for phase in ("normal-1", "normal-2", "cancel-down", "cancel", "old-up", "fresh-down")}

    def records(phase, event, value):
        return [row for row in by_phase[phase] if row[2:4] == [event, value]]

    controls = case["controls"]
    if [row["phase"] for row in controls] != ["normal-1", "normal-2"]:
        return result
    cancelled = case["cancelRound"]
    fresh = case["fresh"]
    pressed = [row["down"] for row in controls] + [cancelled["down"], fresh["down"]]
    released = [row["up"] for row in controls] + [cancelled["oldUp"], fresh["up"]]
    target = fresh["down"]["buttonTarget"]
    os_edges = all(row["operation"] == "left-" + label and row["pid"] == raw["identity"]["pid"] and
                   row["stimulus"] == "OS SendInput injected" and row["target"] == row["hwnd"]
                   for label, samples in (("down", pressed), ("up", released)) for row in samples)
    target_exact = bool(target and all(row["buttonTarget"] == target and row["geometryStableAfterDown"] is True for row in pressed))
    normal = all(len(records(phase, "begin-return", "true")) == len(records(phase, "end-return", "true")) == 1
                 for phase in ("normal-1", "normal-2"))
    ack = cancelled["ack"]["receipt"].split("|")
    nonce = re.search(r"event=world_pointer_cancel epoch=(\d+) ", case["nativeMatchingCancel"])
    accepted = (len(ack) == 7 and ack[:2] == ["I1", "WorldPointerCancelled"] and ack[6] == "1" and
                ack[2] == cancelled["ack"]["authority"]["sessionId"] and
                int(ack[3]) == cancelled["ack"]["authority"]["connectionIncarnation"] and nonce and ack[5] == nonce[1] and
                fresh["after"]["receipt"] == cancelled["ack"]["receipt"])
    old_up_suppressed = not records("old-up", "mouse", "Up") and not records("old-up", "end-return", "true")
    cleared = bool(records("cancel", "cursor", "手型普通")) and len(records("cancel-down", "begin-return", "true")) == 1
    trace = case["nativeAndCursor"]
    native = {}
    for name, message in (("down", "0x201"), ("up", "0x202")):
        posted = [m[1] for line in trace if (m := re.search(r"event=world_pointer_posted msg=" + message + r" seq=(\d+) ", line))]
        if not posted:
            return result
        seq = posted[-1]
        original = [m[1] for line in trace if (m := re.search(
            r"event=world_pointer_bridge TRACE .* stage=(\d+) seq=" + seq + r" .* msg=" + message + " ", line))]
        native[name] = {"seq": int(seq), "stages": original}
    native_bound = all(row["stages"] == ["1", "2"] for row in native.values())
    starts = records("fresh-down", "begin-return", "true")
    ends = records("fresh-down", "end-return", "true")
    hit = len(starts) == 1 and starts[0][11] == "true"
    actual_pairs = (len(records("fresh-down", "mouse", "Down")) == len(records("fresh-down", "mouse", "Up")) == 1)
    prerequisites = all((os_edges, target_exact, normal, accepted, old_up_suppressed, cleared, native_bound, actual_pairs))
    if prerequisites and hit and len(ends) == 1 and int(starts[0][0]) < int(ends[0][0]):
        result["status"] = "PASS"
    elif prerequisites and case["status"] == "FAIL" and not starts:
        result["status"] = "FAIL"
    return {**result, "twoOrdinaryControls": normal, "worldCancelReceipt": "|".join(ack), "exactWorldAck": bool(accepted),
            "oldReleaseSuppressed": old_up_suppressed, "cursorResetOnCancel": cleared, "freshNativeOriginal": native,
            "oneFreshBegin": len(starts) == 1, "oneFreshEnd": len(ends) == 1, "freshHitTest": hit,
            "additionalRejectedFreshEndCallbacks": len(records("fresh-down", "end-return", "false")),
            "keyboardEpochs": [sample["authority"]["keyboardEpoch"] for sample in
                               (cancelled["before"], cancelled["ack"], fresh["after"])]}
