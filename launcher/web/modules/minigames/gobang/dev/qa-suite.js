(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.GobangQA = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    function ok(detail) { return { pass: true, detail: detail || "" }; }
    function fail(detail) { return { pass: false, detail: detail || "" }; }

    function play(Core, state, moves) {
        var i;
        var result = null;
        for (i = 0; i < moves.length; i += 1) {
            result = Core.applyMove(state, moves[i][0], moves[i][1], moves[i][2], moves[i][3] || "qa");
            if (!result.valid) return result;
        }
        return result || { valid: true };
    }

    function g1_blackFiveWins(Core) {
        var s = Core.createState({ ruleset: "casual", aiEnabled: false });
        var r = play(Core, s, [
            [7, 3, 1], [0, 0, -1], [7, 4, 1], [0, 1, -1],
            [7, 5, 1], [0, 2, -1], [7, 6, 1], [0, 3, -1],
            [7, 7, 1]
        ]);
        if (!r.valid) return fail("move rejected: " + r.reason);
        if (s.status !== "win" || s.winner !== 1) return fail("black five did not win");
        return ok("black wins at move " + s.moves.length);
    }

    function g2_casualOverlineWins(Core) {
        var s = Core.createState({ ruleset: "casual", aiEnabled: false });
        var r = play(Core, s, [
            [6, 1, 1], [0, 0, -1], [6, 2, 1], [0, 2, -1],
            [6, 3, 1], [0, 4, -1], [6, 4, 1], [0, 6, -1],
            [6, 6, 1], [0, 8, -1], [6, 5, 1]
        ]);
        if (!r.valid) return fail("move rejected: " + r.reason);
        if (s.status !== "win" || s.winner !== 1) return fail("casual overline did not win");
        return ok("casual overline accepted as win");
    }

    function g3_renjuBlackOverlineForbidden(Core) {
        var s = Core.createState({ ruleset: "renju", aiEnabled: false });
        var r = play(Core, s, [
            [6, 1, 1], [0, 0, -1], [6, 2, 1], [0, 2, -1],
            [6, 3, 1], [0, 4, -1], [6, 4, 1], [0, 6, -1],
            [6, 6, 1], [0, 8, -1], [6, 5, 1]
        ]);
        if (r.valid) return fail("renju overline unexpectedly accepted");
        if (r.reason !== "overline") return fail("expected overline, got " + r.reason);
        if (s.moves.length !== 10) return fail("forbidden move mutated history");
        return ok("black overline rejected without mutating state");
    }

    function g4_renjuDoubleThreeForbidden(Core) {
        var s = Core.createState({ ruleset: "renju", aiEnabled: false });
        var r = play(Core, s, [
            [7, 6, 1], [0, 0, -1],
            [7, 8, 1], [0, 1, -1],
            [6, 7, 1], [0, 2, -1],
            [8, 7, 1], [0, 3, -1],
            [7, 7, 1]
        ]);
        if (r.valid) return fail("double-three unexpectedly accepted");
        if (r.reason !== "double_three") return fail("expected double_three, got " + r.reason);
        return ok("cross double-three rejected");
    }

    function g5_renjuDoubleFourForbidden(Core) {
        var s = Core.createState({ ruleset: "renju", aiEnabled: false });
        var r = play(Core, s, [
            [7, 5, 1], [0, 0, -1],
            [7, 6, 1], [0, 2, -1],
            [7, 8, 1], [0, 4, -1],
            [5, 7, 1], [0, 6, -1],
            [6, 7, 1], [0, 8, -1],
            [8, 7, 1], [0, 10, -1],
            [7, 7, 1]
        ]);
        if (r.valid) return fail("double-four unexpectedly accepted");
        if (r.reason !== "double_four") return fail("expected double_four, got " + r.reason);
        return ok("cross double-four rejected");
    }

    function g6_undoAndIllegalMove(Core) {
        var s = Core.createState({ ruleset: "casual", aiEnabled: false });
        var a = Core.applyMove(s, 7, 7, 1, "player");
        var b = Core.applyMove(s, 7, 7, -1, "player");
        if (!a.valid) return fail("first move rejected");
        if (b.valid || b.reason !== "occupied") return fail("occupied move not rejected");
        Core.undo(s, 1);
        if (s.moves.length !== 0) return fail("undo did not remove move");
        if (Core.getCell(s.board, 7, 7) !== 0) return fail("undo did not clear board");
        if (s.currentRole !== 1) return fail("undo did not restore black turn");
        return ok("occupied rejected and undo restored empty board");
    }

    function g8_inspectThreatsAt(Core) {
        if (typeof Core.inspectThreatsAt !== "function") return fail("inspectThreatsAt not exported");

        // 场景 A：三颗相连两端皆空 => openThree
        var a = Core.createState({ ruleset: "casual", aiEnabled: false });
        Core.applyMove(a, 7, 6, 1, "qa");
        Core.applyMove(a, 0, 0, -1, "qa");
        Core.applyMove(a, 7, 7, 1, "qa");
        Core.applyMove(a, 0, 1, -1, "qa");
        Core.applyMove(a, 7, 8, 1, "qa");
        var openThree = Core.inspectThreatsAt(a.board, 7, 8, 1);
        if (openThree.openThree < 1) return fail("expected openThree >= 1, got " + JSON.stringify(openThree));

        // 场景 B：三颗一端堵 => halfThree，非 openThree
        var b = Core.createState({ ruleset: "casual", aiEnabled: false });
        Core.applyMove(b, 7, 5, -1, "qa"); // 左端白堵
        Core.applyMove(b, 0, 0, 1, "qa");
        Core.applyMove(b, 7, 6, 1, "qa");
        Core.applyMove(b, 0, 1, -1, "qa");
        Core.applyMove(b, 7, 7, 1, "qa");
        Core.applyMove(b, 0, 2, -1, "qa");
        Core.applyMove(b, 7, 8, 1, "qa");
        var blocked = Core.inspectThreatsAt(b.board, 7, 8, 1);
        if (blocked.openThree !== 0) return fail("blocked three should not be openThree: " + JSON.stringify(blocked));
        if (blocked.halfThree < 1) return fail("blocked three should be halfThree: " + JSON.stringify(blocked));

        // 场景 C：四颗至少一端空 => four
        var c = Core.createState({ ruleset: "casual", aiEnabled: false });
        Core.applyMove(c, 7, 5, 1, "qa");
        Core.applyMove(c, 0, 0, -1, "qa");
        Core.applyMove(c, 7, 6, 1, "qa");
        Core.applyMove(c, 0, 1, -1, "qa");
        Core.applyMove(c, 7, 7, 1, "qa");
        Core.applyMove(c, 0, 2, -1, "qa");
        Core.applyMove(c, 7, 8, 1, "qa");
        var fourThreat = Core.inspectThreatsAt(c.board, 7, 8, 1);
        if (fourThreat.four < 1) return fail("expected four >= 1, got " + JSON.stringify(fourThreat));

        return ok("openThree/halfThree/four 区分正确");
    }

    function g7_serializationAndDifficulty(Core) {
        var s = Core.createState({ difficulty: "hard", ruleset: "renju", playerRole: -1 });
        Core.applyMove(s, 7, 7, 1, "ai");
        var exported = Core.buildSessionExport(s);
        if (s.timeLimit !== 3000) return fail("hard timeLimit expected 3000, got " + s.timeLimit);
        if (exported.Session.ruleset !== "renju") return fail("export ruleset mismatch");
        if (exported.Session.moves.length !== 1) return fail("export moves mismatch");
        exported.Session.moves[0].row = 0;
        if (s.moves[0].row === 0) return fail("export did not clone moves");
        return ok("difficulty maps to 3000ms and export is detached");
    }

    var SUITE = [
        { id: "g1", title: "五连胜负判定", run: g1_blackFiveWins },
        { id: "g2", title: "休闲规则长连胜", run: g2_casualOverlineWins },
        { id: "g3", title: "竞技规则黑长连禁手", run: g3_renjuBlackOverlineForbidden },
        { id: "g4", title: "竞技规则双三禁手", run: g4_renjuDoubleThreeForbidden },
        { id: "g5", title: "竞技规则双四禁手", run: g5_renjuDoubleFourForbidden },
        { id: "g6", title: "非法落子与悔棋", run: g6_undoAndIllegalMove },
        { id: "g7", title: "序列化与难度时间", run: g7_serializationAndDifficulty },
        { id: "g8", title: "威胁识别 inspectThreatsAt", run: g8_inspectThreatsAt }
    ];

    function runOne(Core, id) {
        var i;
        for (i = 0; i < SUITE.length; i += 1) {
            if (SUITE[i].id !== id) continue;
            var started = typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
            var outcome;
            try {
                outcome = SUITE[i].run(Core);
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

    function runAll(Core) {
        var results = [];
        var i;
        var passed = 0;
        var failed = 0;
        for (i = 0; i < SUITE.length; i += 1) {
            results.push(runOne(Core, SUITE[i].id));
        }
        for (i = 0; i < results.length; i += 1) {
            if (results[i].pass) passed += 1;
            else failed += 1;
        }
        return { results: results, passed: passed, failed: failed, total: results.length };
    }

    return {
        SUITE: SUITE,
        runOne: runOne,
        runAll: runAll
    };
});
