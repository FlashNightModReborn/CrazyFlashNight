(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.PinAlignQA = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    function ok(detail) { return { pass: true, detail: detail || "" }; }
    function fail(detail) { return { pass: false, detail: detail || "" }; }

    function specOf(Levels) { return Levels.getSpec("mvp-3pin-v1"); }

    function playUntilStatus(Core, state, maxMoves) {
        var results = [];
        var tries = 0;
        while (state.status === "ongoing" && tries < maxMoves) {
            var h = Core.getHint(state);
            if (!h) break;
            var r = Core.trySwap(state, h.from, h.to);
            results.push(r);
            tries += 1;
        }
        return { results: results, moves: tries };
    }

    function a1_determinism(Core, Levels) {
        var spec = specOf(Levels);
        var seed = "qa-determinism";
        var s1 = Core.createState(spec, seed);
        var s2 = Core.createState(spec, seed);
        var p1 = playUntilStatus(Core, s1, 12);
        var p2 = playUntilStatus(Core, s2, 12);
        if (p1.moves !== p2.moves) return fail("move counts differ: " + p1.moves + " vs " + p2.moves);
        if (s1.alertRemaining !== s2.alertRemaining) return fail("alertRemaining differs: " + s1.alertRemaining + " vs " + s2.alertRemaining);
        if (s1.status !== s2.status) return fail("status differs: " + s1.status + " vs " + s2.status);
        var h1 = Core.computeStateHash(s1);
        var h2 = Core.computeStateHash(s2);
        if (h1 !== h2) return fail("state hash differs: " + h1 + " vs " + h2);
        return ok(p1.moves + " moves replayed, hash=" + h1);
    }

    function a2_illegalSwapNoCost(Core, Levels) {
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-illegal");
        var snapshot = captureGameplayState(s);
        var cases = [
            ["non-adjacent", {row: 0, col: 0}, {row: 7, col: 7}],
            ["out-of-bounds", {row: 0, col: 0}, {row: -1, col: 0}],
            ["same-cell", {row: 3, col: 3}, {row: 3, col: 3}],
            ["status-check-with-preview-after", {row: 2, col: 2}, {row: 4, col: 4}]
        ];
        var i;
        for (i = 0; i < cases.length; i += 1) {
            var r = Core.trySwap(s, cases[i][1], cases[i][2]);
            if (r.valid) return fail(cases[i][0] + " swap unexpectedly valid");
        }
        var diff = diffGameplayState(snapshot, captureGameplayState(s));
        if (diff) return fail("gameplay state changed after illegal swaps: " + diff);
        return ok("gameplay state intact after " + cases.length + " illegal swaps (invalidSwaps=" + s.telemetry.invalidSwaps + ")");
    }

    function captureGameplayState(s) {
        return {
            alert: s.alertRemaining,
            moveIndex: s.moveIndex,
            movePrepared: s.movePrepared,
            clampArmed: s.clampArmed,
            clampActive: s.clampActiveThisMove,
            pinStates: s.pins.map(function(p) { return p.state + ":" + p.currentHeight + ":" + !!p.guardThisMove; }).join("|"),
            actionLogLen: s.actionLog.length,
            lastHintKey: hintKey(s.lastHint),
            jamCount: s.telemetry.jamCount
        };
    }

    function hintKey(h) {
        if (!h) return "null";
        return h.from.row + "," + h.from.col + "->" + h.to.row + "," + h.to.col;
    }

    function diffGameplayState(a, b) {
        var keys = ["alert", "moveIndex", "movePrepared", "clampArmed", "clampActive", "pinStates", "actionLogLen", "lastHintKey", "jamCount"];
        var i;
        for (i = 0; i < keys.length; i += 1) {
            if (a[keys[i]] !== b[keys[i]]) return keys[i] + " " + a[keys[i]] + " → " + b[keys[i]];
        }
        return null;
    }

    function a3_signalAdvancesPin(Core, Levels) {
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-signal-adv");
        var p = playUntilStatus(Core, s, 30);
        var observed = 0;
        var i;
        var e;
        for (i = 0; i < p.results.length; i += 1) {
            if (!p.results[i].valid) continue;
            for (e = 0; e < p.results[i].events.length; e += 1) {
                var ev = p.results[i].events[e];
                if (ev.pinTransitions.length === 0) continue;
                if (ev.signalTiles.length === 0) return fail("move " + i + " event " + e + ": pin transitioned with 0 signal tiles");
                observed += ev.pinTransitions.length;
            }
        }
        if (observed === 0) return fail("no pin transitions seen in " + p.moves + " moves");
        return ok(observed + " pin transitions, all within events that had Signal tiles");
    }

    function a4_effectNeverAdvances(Core, Levels) {
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-effect-inert");
        var p = playUntilStatus(Core, s, 30);
        var checked = 0;
        var i;
        var e;
        var t;
        for (i = 0; i < p.results.length; i += 1) {
            if (!p.results[i].valid) continue;
            for (e = 0; e < p.results[i].events.length; e += 1) {
                for (t = 0; t < p.results[i].events[e].pinTransitions.length; t += 1) {
                    var reason = p.results[i].events[e].pinTransitions[t].reason;
                    if (reason !== "signal" && reason !== "overshoot" && reason !== "guarded_overshoot" && reason !== "calibrator") {
                        return fail("unexpected transition reason: " + reason);
                    }
                    checked += 1;
                }
            }
        }
        if (checked === 0) return fail("no transitions to inspect");
        return ok(checked + " transitions, all caused by Signal/calibrator/overshoot — none by Effect");
    }

    function a5_onePerPinPerEvent(Core, Levels) {
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-once-per-event");
        var p = playUntilStatus(Core, s, 30);
        var i;
        var e;
        var t;
        for (i = 0; i < p.results.length; i += 1) {
            if (!p.results[i].valid) continue;
            for (e = 0; e < p.results[i].events.length; e += 1) {
                var seen = {};
                for (t = 0; t < p.results[i].events[e].pinTransitions.length; t += 1) {
                    var pid = p.results[i].events[e].pinTransitions[t].pinId;
                    if (seen[pid]) return fail("pin " + pid + " transitioned twice in move " + i + " event " + e);
                    seen[pid] = true;
                }
            }
        }
        return ok("no pin transitioned twice within any single event across " + p.moves + " moves");
    }

    function a6_lockedOnlyAtCommit(Core, Levels) {
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-commit-timing");
        var p = playUntilStatus(Core, s, 80);
        var sawSet = 0;
        var lockedInEvent = 0;
        var lockedFinal = 0;
        var i;
        var e;
        var t;
        for (i = 0; i < p.results.length; i += 1) {
            if (!p.results[i].valid) continue;
            for (e = 0; e < p.results[i].events.length; e += 1) {
                for (t = 0; t < p.results[i].events[e].pinTransitions.length; t += 1) {
                    var tr = p.results[i].events[e].pinTransitions[t];
                    if (tr.toState === "set") sawSet += 1;
                    if (tr.toState === "locked") lockedInEvent += 1;
                }
            }
        }
        for (i = 0; i < s.pins.length; i += 1) {
            if (s.pins[i].state === "locked") lockedFinal += 1;
        }
        if (lockedInEvent > 0) return fail(lockedInEvent + " locked transitions inside event logs (should only occur at commit)");
        if (sawSet === 0 && lockedFinal === 0) return fail("no set nor locked pin observed — scenario inconclusive");
        return ok("saw " + sawSet + " set transitions in events, " + lockedFinal + " pins locked via commit");
    }

    function a7_winTruncatesAndBlocks(Core, Levels) {
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-win-block");
        var p = playUntilStatus(Core, s, 200);
        if (s.status !== "win") return fail("did not reach win in 200 moves (ended " + s.status + ")");
        var postSwap = Core.trySwap(s, {row: 0, col: 0}, {row: 0, col: 1});
        if (postSwap.valid) return fail("trySwap was valid after win");
        if (postSwap.reason !== "status") return fail("post-win trySwap reason: " + postSwap.reason + " (expected status)");
        return ok("won after " + p.moves + " moves; post-win trySwap correctly blocked with reason=status");
    }

    function a8_productiveMoveApi(Core, Levels) {
        if (typeof Core.listProductiveMoves !== "function") return fail("listProductiveMoves not exported");
        if (typeof Core.countProductiveMoves !== "function") return fail("countProductiveMoves not exported");
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-productive");
        var list = Core.listProductiveMoves(s);
        if (!Array.isArray(list)) return fail("listProductiveMoves did not return an array");
        var count = Core.countProductiveMoves(s);
        if (count !== list.length) return fail("countProductiveMoves " + count + " ≠ list.length " + list.length);
        return ok("productive-move API present; initial board has " + list.length + " productive moves");
    }

    function a9_noBareMathRandom(Core, Levels) {
        var orig = Math.random;
        var called = 0;
        Math.random = function() { called += 1; return orig.call(Math); };
        var detail;
        try {
            var spec = specOf(Levels);
            var s = Core.createState(spec, "qa-no-math-random");
            playUntilStatus(Core, s, 6);
            detail = s.moveIndex + " moves + createState completed";
        } finally {
            Math.random = orig;
        }
        if (called > 0) return fail("Math.random called " + called + " times during gameplay");
        return ok(detail + "; Math.random never invoked");
    }

    function a10_noForbiddenFeatures(Core, Levels) {
        var forbidden = ["activateSpecial", "comboSpecials", "kilnAdvance", "flowGlaze", "sealAchievement", "directSpecial"];
        var i;
        for (i = 0; i < forbidden.length; i += 1) {
            if (typeof Core[forbidden[i]] === "function") return fail("forbidden API exported: " + forbidden[i]);
        }
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-no-combo");
        var p = playUntilStatus(Core, s, 30);
        var comboHits = 0;
        var r;
        var e;
        var g;
        for (r = 0; r < p.results.length; r += 1) {
            if (!p.results[r].valid) continue;
            for (e = 0; e < p.results[r].events.length; e += 1) {
                var gens = p.results[r].events[e].generatedSpecials || [];
                for (g = 0; g < gens.length; g += 1) {
                    if (gens[g].comboPartners) comboHits += 1;
                }
            }
        }
        if (comboHits > 0) return fail(comboHits + " special+special combo events observed");
        return ok("no forbidden APIs exposed; " + p.moves + " moves with 0 combo activations");
    }

    function a11_calibratorRespectsOvershoot(Core, Levels) {
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-calibrator-overshoot");
        var p = playUntilStatus(Core, s, 100);
        var calibratorHits = 0;
        var silentBypass = 0;
        var r;
        var e;
        var t;
        for (r = 0; r < p.results.length; r += 1) {
            if (!p.results[r].valid) continue;
            for (e = 0; e < p.results[r].events.length; e += 1) {
                var trs = p.results[r].events[e].pinTransitions || [];
                for (t = 0; t < trs.length; t += 1) {
                    var tr = trs[t];
                    if (tr.triggeredBy === "calibrator") calibratorHits += 1;
                    if (tr.reason === "calibrator" && tr.fromState === "set" && tr.toState === "set") {
                        silentBypass += 1;
                    }
                }
            }
        }
        if (silentBypass > 0) return fail(silentBypass + " silent calibrator-over-set bypasses observed");
        if (calibratorHits === 0) return ok("no calibrator events in " + p.moves + " moves (inconclusive but no violation)");
        return ok(calibratorHits + " calibrator events, 0 silent bypasses (set pins either deflected or properly jammed)");
    }

    function a12_cascadeTruncatesOnAllSet(Core, Levels) {
        var spec = specOf(Levels);
        var s = Core.createState(spec, "qa-cascade-trunc");
        var p = playUntilStatus(Core, s, 200);
        var truncEvents = 0;
        var badTruncs = 0;
        var r;
        for (r = 0; r < p.results.length; r += 1) {
            if (!p.results[r].valid) continue;
            if (!p.results[r].cascadeTruncated) continue;
            truncEvents += 1;
            var pinsAfter = p.results[r].pinsAfter || [];
            var allSetOrLocked = pinsAfter.every(function(pn) { return pn.state === "set" || pn.state === "locked"; });
            if (!allSetOrLocked) badTruncs += 1;
        }
        if (badTruncs > 0) return fail(badTruncs + " cascade truncations happened without all-set-or-locked state");
        if (truncEvents === 0) return ok("no cascade truncation in " + p.moves + " moves (not every run triggers it)");
        return ok(truncEvents + " cascade truncations, all satisfied allPinsSetOrLocked invariant");
    }

    var SUITE = [
        { id: "a1", title: "同 seed + 同输入 = 同 outcome", run: a1_determinism },
        { id: "a2", title: "非法交换不改变任何 gameplay state", run: a2_illegalSwapNoCost },
        { id: "a3", title: "只有 Signal 推进锁针", run: a3_signalAdvancesPin },
        { id: "a4", title: "Effect 永不推进锁针", run: a4_effectNeverAdvances },
        { id: "a5", title: "同一事件每 pin ≤ 1 推进", run: a5_onePerPinPerEvent },
        { id: "a6", title: "set→locked 只在 move 末 commit", run: a6_lockedOnlyAtCommit },
        { id: "a7", title: "win 后交换被阻断", run: a7_winTruncatesAndBlocks },
        { id: "a8", title: "hasProductiveMove API 存在", run: a8_productiveMoveApi },
        { id: "a9", title: "gameplay 不裸调 Math.random", run: a9_noBareMathRandom },
        { id: "a10", title: "无 direct special / combo / kiln / flow / seal", run: a10_noForbiddenFeatures },
        { id: "a11", title: "calibrator 不偷偷绕过 overshoot", run: a11_calibratorRespectsOvershoot },
        { id: "a12", title: "所有 pin set/locked 时 cascade 短路", run: a12_cascadeTruncatesOnAllSet }
    ];

    function runOne(Core, Levels, id) {
        var i;
        for (i = 0; i < SUITE.length; i += 1) {
            if (SUITE[i].id !== id) continue;
            var started = typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
            var outcome;
            try {
                outcome = SUITE[i].run(Core, Levels);
            } catch (err) {
                outcome = fail("threw: " + (err && err.message ? err.message : String(err)));
            }
            var ended = typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
            outcome.id = SUITE[i].id;
            outcome.title = SUITE[i].title;
            outcome.durationMs = Math.round((ended - started) * 100) / 100;
            return outcome;
        }
        return fail("unknown case: " + id);
    }

    function runAll(Core, Levels) {
        var results = [];
        var i;
        for (i = 0; i < SUITE.length; i += 1) {
            results.push(runOne(Core, Levels, SUITE[i].id));
        }
        var passed = 0;
        var failed = 0;
        for (i = 0; i < results.length; i += 1) {
            if (results[i].pass) passed += 1; else failed += 1;
        }
        return { results: results, passed: passed, failed: failed, total: results.length };
    }

    return {
        SUITE: SUITE,
        runOne: runOne,
        runAll: runAll
    };
});
