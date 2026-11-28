import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from entry import gesture_result, read_entry
from evidence import focused_groups, legacy_latency, paired_ordinary_latency, read_focus, read_smoke, read_trx
from live_focus import checked_chain_cases, classify_chain_focus
from materials import combined_material
from report import independent_reviews, qualification


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.expected = {"installRoot": str(self.root), "processPath": str(self.root / "Core.exe"),
                         "coreSha256": "E" * 64, "payloadClosure": "C" * 64, "buildIdentity": "B" * 64}

    def write(self, name, data):
        file = self.root / name
        file.write_text(json.dumps(data), encoding="utf-8")
        return file

    def test_smoke_foreground_block_is_not_a_machine_pass(self):
        raw = {"candidate": str(self.root), "coreSha256": self.expected["coreSha256"],
               "identity": {"buildIdentityHash": self.expected["buildIdentity"],
                            "payloadClosureHash": self.expected["payloadClosure"]},
               "state": "failed", "reportPixelsVerified": False, "gameE2e": False,
               "kind": "isolated-composition-fixture", "failure": "probe timed out: fixture initial foreground admitted",
               "checks": [{"label": "real WebView2 endpoint ready", "passed": True}]}
        file = self.write("smoke.json", raw)
        report = read_smoke(file, self.expected, {"threadDesktop": "exebox", "inputDesktop": "Default"})
        self.assertEqual(("BLOCKED", "failed", "NOT_RUN"), (report["status"], report["rawState"], report["interactiveChecks"]))
        self.assertEqual("FAIL", read_smoke(file, self.expected)["foregroundAdmission"])
        self.assertIsNone(read_smoke(file, self.expected)["nonInputDesktopObserved"])
        fixture_failure = self.write("smoke-red.json", {**raw, "failure": "old source visible after admission"})
        self.assertEqual("FAIL", read_smoke(fixture_failure, self.expected)["status"])
        file = self.write("smoke-green.json", {**raw, "state": "fixture_executed", "reportPixelsVerified": True, "failure": None})
        report = read_smoke(file, self.expected)
        self.assertEqual("PASS", report["status"])
        self.assertFalse(report["gameE2e"])
        self.assertEqual("BLOCKED", read_smoke(file, {**self.expected, "payloadClosure": "A" * 64})["status"])

    def test_trx_reads_not_executed_outcome_even_with_zero_summary(self):
        file = self.root / "recheck.trx"
        file.write_text('''<TestRun id="run" xmlns="test"><Results>
        <UnitTestResult testId="1" testName="Pass" outcome="Passed"/>
        <UnitTestResult testId="2" testName="Skip" outcome="NotExecuted"/>
        </Results><ResultSummary><Counters notExecuted="0"/></ResultSummary></TestRun>''', encoding="utf-8")
        self.assertEqual({"PASS": 1, "NOT_RUN": 1}, read_trx(file)["observedCounts"])

    def test_trx_resource_tick_drift_preserves_original_outcome_but_blocks_test(self):
        file = self.root / "recheck.trx"
        file.write_text('''<TestRun id="run" xmlns="test"><Results>
        <UnitTestResult testId="1" testName="FixtureGuard" outcome="Failed"><Output><ErrorInfo><Message>System.OperationCanceledException : Resource qualification cancelled at case.begin Example expired=False inputReadSucceeded=True expectedTick=14 observedTick=19</Message></ErrorInfo></Output></UnitTestResult>
        <UnitTestResult testId="2" testName="ActualFault" outcome="Failed"><Output><ErrorInfo><Message>System.OperationCanceledException : Actual error</Message></ErrorInfo></Output></UnitTestResult>
        </Results></TestRun>''', encoding="utf-8")
        result = read_trx(file)
        self.assertEqual({"BLOCKED": 1, "FAIL": 1}, result["observedCounts"])
        self.assertEqual("Failed", result["tests"][0]["outcome"])

    def test_focused_recheck_cannot_use_other_source_to_close_a_gap(self):
        archived = {"sameFinalSource": False, "status": "PASS", "tests": [{"name": "NeedEditor", "status": "PASS"}]}
        final = {"sameFinalSource": True, "sourceAndLoadedTestBinariesBound": True, "status": "PASS",
                 "tests": [{"name": "ActualOther", "status": "PASS"}]}
        with patch("evidence.checked_out_sources", return_value=set()), patch("evidence.subprocess.check_output", return_value="head"), \
             patch("evidence.focused_grounding", side_effect=[archived, final]):
            result = focused_groups([self.root / "old", self.root / "new"], self.root, ["NeedEditor"])
        self.assertEqual("BLOCKED", result["status"])
        self.assertEqual(["NeedEditor"], result["missingRequired"])

    def test_old_latency_boolean_is_diagnostic_only(self):
        file = self.write("perf.json", {"withinBudget": True, "summary": {"candidateP95Ms": 41.2331}})
        status = legacy_latency(file)
        self.assertEqual("BLOCKED", status["status"])
        self.assertIsNone(status["diagnostic"]["baselineP95Ms"])

    def test_absent_focus_telemetry_never_yields_a_verified_zero(self):
        observed = {"pid": 321, **self.expected}
        file = self.write("focus.json", {"schema": "cf7-input-authority-focus.v1", "observed": observed,
                                         "coveredCases": ["startup"], "records": [], "droppedRecords": 0})
        result = read_focus(file, self.expected)
        self.assertEqual("BLOCKED", result["status"])
        self.assertIsNone(result["verifiedRuntimeFlashFocused"])
        self.assertIsNone(result["passiveFocusCounts"]["runtimeRawFocus"])

    def test_product_failure_has_priority_over_complete_independent_reviews(self):
        reviews = {"T1": {"status": "PASS"}, "T3": {"status": "PASS"}}
        self.assertEqual("FAIL", qualification(["T1", "T3"], [{"status": "FAIL"}], reviews))
        self.assertEqual("BLOCKED", qualification(["T1", "T3"], [{"status": "PASS"}], {"T1": reviews["T1"]}))

    def test_same_runtime_cannot_bind_a_review_of_old_loose_assets(self):
        old = combined_material({**self.expected, "assets": [{"path": "bounty.swf", "sha256": "5" * 64}]})
        new = combined_material({**self.expected, "assets": [{"path": "bounty.swf", "sha256": "6" * 64}]})
        raw = self.write("review.json", {"schema": "cf7-input-authority-independent-reviews.v1",
                                       "reviewer": "Independent", "candidate": {**self.expected, "combinedMaterialSha256": old}})
        self.assertNotEqual(old, new)
        with self.assertRaises(ValueError):
            independent_reviews(raw, {**self.expected, "combinedMaterialSha256": new}, {"gates": [], "retirements": []})

    def test_chain_retains_bootstrap_failure_and_requires_a_qualified_runtime_window(self):
        boot = ("12:00:00.500 event=r1_passive_focus_audit stage=bootstrap queried=True root=0x10 flash=0x12 "
                "flashFocused=True sourceThreadFocus=0x12 rootThreadFocus=0x12")
        runtime = ("event=r1_passive_focus_audit stage=runtime queried=True root=0x10 flash=0x12 "
                   "flashFocused=False sourceThreadFocus=0x10 rootThreadFocus=0x10")
        focus_rows = [{"threadId": 10, "flashFocused": False, "hwndFocus": "0x10", "readSucceeded": True},
                      {"threadId": 20, "flashFocused": False, "hwndFocus": "0x10", "readSucceeded": True}]
        case = {"R1-P01": {"checks": {"focus": {"status": "FAIL", "evidence": {"reported": False, "win32": focus_rows}}}}}
        raw = {"candidate": {"observed": {"pid": 40}},
               "hwnds": {"S": "0x10", "P": "0x11", "F": "0x12",
                         "line": "12:00:02.000 event=world_compositor_identity S=0x10 P=0x11 F=0x12 hostPid=40"},
               "runtimeReady": {"attemptId": "ready1", "slot": "isolated"},
               "windowTopology": {"topWindows": [{"hwnd": "0x10", "pid": 40, "taskbarActivatableRoot": True},
                                                   {"hwnd": "0x11", "pid": 40, "owner": "0x10"}]},
               "observations": {"startBoundary": {"terminalSessionPid": 40, "terminalLifecycleId": "test",
                                                   "snapshot": {"sessionPid": 40}},
                                "initialPassive": {"i1Bound": True, "flashHwnd": "0x12", "flashHasKeyboardFocus": False, "sessionId": "bound"}},
               "rawLogs": [{"label": "startup", "lines": ["12:00:00.100 [Guardian] Flash Player started, PID=50",
                            "12:00:01.000 [SaveManager.preload] savePath=isolated|[Bootstrap] sent bootstrap_ready attemptId=ready1 ok=true"]}],
               "flashPlayer": {"pid": 50}, "win32FocusSamples": [{"flashPid": 50, "hwnd": "0x12", "focusSamples": focus_rows}],
               "probeCalls": [{"response": {"flashHwnd": "0x12", "sessionId": "bound", "flashHasKeyboardFocus": False,
                   "passiveFocusCounts": {"sourceHook": True, "hostHook": True, "samples": 8, "failedQueries": 0,
                                          "runtimeRawFocus": 0, "runtimeFocusNotifications": 0, "runtimeStyleViolations": 0}}}],
               "sourceFocus": {"status": "FAIL", "evidence": [boot, "12:00:03.000 " + runtime, "12:00:04.000 " + runtime]}}
        actual = classify_chain_focus(raw)
        self.assertEqual(("PASS", "FAIL"), (actual["businessStatus"], actual["lifecycleStatus"]))
        retained, scoped = checked_chain_cases(case, actual)
        self.assertEqual("FAIL", retained["R1-P01"]["focus"])
        self.assertEqual("PASS", scoped["R1-P01"]["focus"])
        counters = raw["probeCalls"][0]["response"]["passiveFocusCounts"]
        counters["runtimeRawFocus"] = 1
        self.assertEqual("FAIL", classify_chain_focus(raw)["businessStatus"])
        counters["runtimeRawFocus"] = 0
        for stage in ("stage=runtime", "stage=bootstrap", ""):
            with self.subTest(late_stage=stage):
                raw["sourceFocus"]["evidence"][-1] = boot.replace("12:00:00.500", "12:00:04.000").replace("stage=bootstrap", stage)
                actual = classify_chain_focus(raw)
                self.assertEqual("FAIL", actual["businessStatus"])
                self.assertEqual("FAIL", checked_chain_cases(case, actual)[1]["R1-P01"]["focus"])
        raw["sourceFocus"]["evidence"][-1] = "12:00:04.000 " + runtime
        raw["sourceFocus"]["evidence"][0] = boot.replace("stage=bootstrap", "")
        actual = classify_chain_focus(raw)
        self.assertEqual("BLOCKED", actual["businessStatus"])
        self.assertEqual("BLOCKED", checked_chain_cases(case, actual)[1]["R1-P01"]["focus"])

        raw.update(expectedAttemptId="ready1", slot="isolated")
        held = boot.replace("00.500", "01.200")
        clear = ("12:00:01.500 event=r1_passive_focus_audit stage=bootstrap queried=True enabled=False root=0x10 flash=0x12 "
                 "flashFocused=False sourceThreadFocus=0x10 rootThreadFocus=0x10")
        raw["sourceFocus"]["evidence"] = [boot, held, "12:00:03.000 " + runtime, "12:00:04.000 " + runtime]
        direct = [
            "12:00:00.010 [Prewarm] triggered attemptId=ready1",
            "12:00:00.100 [Guardian] Flash Player started, PID=50",
            "12:00:00.110 event=world_pointer_bridge_start hostPid=40 owner=0x10 ownerPid=40 source=0x12 sourcePid=50 phase=before_create",
            boot,
            "12:00:00.560 event=passive_bootstrap_publication stage=pending flash=0x12 pid=50 epoch=2",
            '12:00:01.000 [XmlSocket:JSON] {"payload":{"attemptId":"ready1"},"task":"bootstrap_ready"}',
            held, clear,
            "12:00:01.505 event=passive_bootstrap_publication stage=published source=passive_focus_available flash=0x12 pid=50 epoch=2",
            "12:00:01.510 [LaunchFlow] OnEmbedResult=True",
            "12:00:01.511 [LaunchFlow] Embedding -> WaitingGameReady",
            "12:00:01.512 [LaunchFlow] WaitingGameReady -> Ready",
            "12:00:01.520 [LaunchFlow] performing reveal (panel swap)",
            raw["hwnds"]["line"],
        ]
        with self.subTest(boundary="observable host publication after client readiness and raw focus"):
            report = classify_chain_focus(raw, direct)
            self.assertEqual(("PASS", "FAIL"), (report["businessStatus"], report["lifecycleStatus"]))
            self.assertEqual("verified_host_publication", report["boundarySource"])
            self.assertIn(held, report["bootstrapPositiveLines"])
            self.assertEqual("FAIL", checked_chain_cases(case, report)[0]["R1-P01"]["focus"])
        with self.subTest(boundary="post-ready raw focus in supplied launcher log alone"):
            late = boot.replace("00.500", "04.500")
            report = classify_chain_focus(raw, direct + [late])
            self.assertEqual("FAIL", report["businessStatus"])
            self.assertIn(late, report["runtimeViolations"])
        with self.subTest(boundary="real legacy host Ready already advanced while raw focus remained"):
            legacy = [line for line in direct if "passive_bootstrap_publication" not in line and "WaitingGameReady -> Ready" not in line]
            legacy.insert(5, "12:00:01.100 [LaunchFlow] WaitingGameReady -> Ready")
            report = classify_chain_focus(raw, legacy)
            self.assertEqual("FAIL", report["businessStatus"])
            self.assertIn(held, report["runtimeViolations"])
        for malformed in (direct[:5] + [direct[5].replace("ready1", "another-attempt")] + direct[6:],
                          [line for line in direct if "WaitingGameReady -> Ready" not in line],
                          [line.replace("enabled=False", "enabled=True") if line == clear else line for line in direct]):
            with self.subTest(boundary="missing, unsafe, or unrelated evidence"):
                self.assertEqual("BLOCKED", classify_chain_focus(raw, malformed)["businessStatus"])

    def test_os_handoff_fails_when_both_edges_arrive_without_modifier_ingress(self):
        case = {"page": {"edgeSequences": [1, 2]}}
        events = {i: {"event": "mouse.route", "edge": edge, "injected": True, "edgeId": edge,
                      "hitHwnd": 123, "seq": i} for i, edge in enumerate(("down", "up"), 1)}
        self.assertEqual("FAIL", gesture_result(case, events, "page", True)["status"])
        self.assertEqual("BLOCKED", gesture_result(case, events, "page", False)["status"])

    def test_normal_trace_requires_as2_ack_and_an_accepted_exact_ticket(self):
        label = "c" * 32
        rows = []

        def put(event, data=None, gesture=None):
            rows.append({"v": 2, "session": label, "processRunId": "run", "generation": 1, "seq": len(rows) + 1,
                         "event": event, "data": data or {}, "gesture": gesture})

        def mouse(mouse_id, stage, target_hwnd):
            put("mouse." + stage, {"mouseId": mouse_id, "injected": True,
                                    "windows": {"hitCandidate": {"hwnd": target_hwnd}}})
            put("mouse.route", {"mouseId": mouse_id, "message": 513 if stage == "down" else 514})

        def open_modifier(mouse_id, generation):
            mouse(mouse_id, "down", 10)
            mouse(mouse_id, "up", 10)
            put("modifier.open", {"generation": generation, "token": f"token-{generation}", "surface": {"hwnd": 22}})

        put("trace.start", {"pid": 229, "corePath": str(self.root / "Core.dll")})
        cases = []
        for generation, held in ((3, False), (7, True)):
            start = len(rows) + 1
            token = f"token-{generation}"
            opened = f"open-{generation}"
            reopened = f"reopen-{generation}"
            open_modifier(opened, generation)
            for action in ("page", "close"):
                target = "modifier.button." + ("tab:items" if action == "page" else "close")
                mouse_id = f"{action}-{generation}"
                ticket = 200 + len(rows)
                for edge in ("down", "up"):
                    mouse(mouse_id, edge, 22)
                    put("modifier.press", {"mouseId": mouse_id, "receiver": 22, "generation": generation,
                                           "message": 513 if edge == "down" else 514, "receiverWindow": {"rootOwner": 22}})
                    put("modifier.begin" if edge == "down" else "modifier.commit", {"generation": generation,
                        "target": target, "ticket": {"GestureId": ticket}, "accepted": True}, mouse_id)
                if action == "page":
                    put("modifier.page", {"generation": generation, "previous": "economy", "tab": "items"}, mouse_id)
                else:
                    for stage in ("close_requested", "close_core", "suspend", "close_sent"):
                        put("modifier." + stage, {"generation": generation, "token": token, "visible": False, "sent": True})
                    put("as2.observation", {"raw": f"[FocusTraceAS2] session={label} event=modifier.closed token={token} accepted=true"})
            open_modifier(reopened, generation + 1)
            cases.append({"id": f"case-{generation}", "firstSeq": start, "lastSeq": len(rows), "hudReceivers": [10],
                          "hudOpenMouseIds": [opened, reopened], "pageMouseId": f"page-{generation}",
                          "closeMouseId": f"close-{generation}", "holdDShift": held,
                          "keyboard": {"beforeAdmittedD": True, "afterAdmittedD": True, "beforeAdmittedShift": True,
                                       "afterAdmittedShift": True, "epochBefore": 5, "epochAfter": 5}})
        trace = self.root / "FocusTrace.jsonl"

        def flush_trace():
            trace.write_text("\n".join("[FocusTrace] " + json.dumps(row) for row in rows), encoding="utf-8")

        index = self.write("entry.json", {"schema": "cf7-modifier-default-entry.v1", "runId": "entry", "trace": trace.name,
            "traceSession": label, "observed": {**self.expected, "pid": 229, "runtimeMode": "isolated_candidate"},
            "desktop": {"inputDesktop": "Default", "threadDesktop": "Default"}, "slot": "cf7_agent_test",
            "attemptId": "valid-attempt", "stimulus": "os-sendinput", "windowCompleted": True, "cases": cases})
        flush_trace()
        self.assertEqual("PASS", read_entry(index, self.expected)["status"])
        next(row for row in rows if row["event"] == "as2.observation")["data"]["raw"] = "unrelated AS2 log"
        flush_trace()
        self.assertEqual("BLOCKED", read_entry(index, self.expected)["status"])
        next(row for row in rows if row["event"] == "modifier.begin")["data"]["accepted"] = False
        flush_trace()
        self.assertEqual("FAIL", read_entry(index, self.expected)["status"])

    def test_latency_interval_is_recomputed_from_raw_brackets(self):
        def row(after):
            return {"id": 1, "before": {"requestedMs": 9, "returnedMs": 11, "frame": 7, "inputFrame": 41,
                                        "keyEpoch": 1, "key": False, "x": 500},
                    "injection": {"exit": 0, "requestedMs": 12, "edges": [{"edge": "down", "receivedMs": 14},
                                                                         {"edge": "up", "receivedMs": 134}]},
                    "observations": [{"requestedMs": 20, "returnedMs": 25, "frame": 7, "inputFrame": 41,
                                      "keyEpoch": 1, "key": False, "x": 500},
                                     {"requestedMs": 27, "returnedMs": after, "frame": 8, "inputFrame": 42,
                                      "keyEpoch": 1, "key": True, "x": 501}],
                    "osToLatch": {"lowerMs": -999, "upperMs": -999}}

        left = {**self.expected, "buildIdentity": "A" * 64, "runtimeMode": "isolated_candidate"}
        shared = {"schema": "cf7-input-authority-ordinary-latency.v1", "scene": "quiet room", "stimulus": "os-sendinput",
                  "observer": "latched-movement", "vk": 68, "holdMs": 120, "perPulseMs": 650, "plannedSamples": 1,
                  "sessionStayedBound": True}
        before = self.write("base.json", {**shared, "role": "baseline", "observed": left, "samples": [row(37)]})
        after = self.write("candidate.json", {**shared, "role": "candidate", "observed": self.expected, "samples": [row(42)]})
        result = paired_ordinary_latency(before, after, self.expected)
        self.assertEqual("BLOCKED", result["status"])
        self.assertEqual([[6, 25]], result["bounds"]["latch"]["baseline"])
        self.assertEqual([[6, 30]], result["bounds"]["latch"]["candidate"])
        self.assertEqual([[-19, 24]], result["bounds"]["latch"]["pairedDelta"])
        self.assertIsNone(result["presentationLatency"])


if __name__ == "__main__":
    unittest.main()
