(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.LockboxQA = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    function ok(detail) { return { pass: true, detail: detail || "" }; }
    function fail(detail) { return { pass: false, detail: detail || "" }; }

    function makeRequest(profile, familySeed, variantIndex) {
        return {
            profile: profile || "standard",
            familySeed: familySeed >>> 0,
            variantIndex: variantIndex | 0
        };
    }

    function generate(Generator, request) {
        return Generator.generatePuzzle(request.profile, request.familySeed, request.variantIndex);
    }

    function serialize(value) {
        return JSON.stringify(value);
    }

    function sameJson(a, b) {
        return serialize(a) === serialize(b);
    }

    function l1_deterministicGeneration(Core, Generator) {
        var request = makeRequest("standard", 0x12345678, 1);
        var first = generate(Generator, request);
        var second = generate(Generator, request);
        if (!sameJson(first.config, second.config)) return fail("config differs across deterministic generation");
        if (!sameJson(first.puzzle, second.puzzle)) return fail("puzzle differs across deterministic generation");
        if (!sameJson(first.report, second.report)) return fail("report differs across deterministic generation");
        return ok("stable config+puzzle+report for " + request.profile + ":" + request.familySeed + ":" + request.variantIndex);
    }

    function l2_solverReportMatches(Core, Generator, Solver) {
        var request = makeRequest("elite7", 0x31415926, 0);
        var generated = generate(Generator, request);
        var replay = Solver.solvePuzzle(
            generated.config,
            generated.puzzle.matrix,
            generated.puzzle.seqA,
            generated.puzzle.seqB,
            generated.puzzle.seqC
        );
        if (!sameJson(generated.report, replay)) return fail("solver replay report diverged from generator report");
        return ok("solver replay matches generator report exactly");
    }

    function tokensForPath(matrix, path) {
        var out = [];
        var i;
        for (i = 0; i < path.length; i += 1) out.push(matrix[path[i].r][path[i].c]);
        return out;
    }

    function l3_canonicalMainPathSolvesAB(Core, Generator) {
        var generated = generate(Generator, makeRequest("standard", 0x6c6f636b, 0));
        var path = generated.report.canonicalMainPath;
        if (!path || !path.length) return fail("canonicalMainPath missing");
        var completion = Core.evaluateBuffer(tokensForPath(generated.puzzle.matrix, path), generated.puzzle.seqA, generated.puzzle.seqB, generated.puzzle.seqC);
        if (!completion.a || !completion.b) return fail("canonicalMainPath did not solve A/B");
        return ok("canonicalMainPath solves A/B in " + path.length + " picks");
    }

    function l4_canonicalFullPathSolvesABC(Core, Generator) {
        var generated = generate(Generator, makeRequest("elite6", 0x2468ace0, 2));
        var path = generated.report.canonicalFullPath;
        if (!path || !path.length) return fail("canonicalFullPath missing");
        var completion = Core.evaluateBuffer(tokensForPath(generated.puzzle.matrix, path), generated.puzzle.seqA, generated.puzzle.seqB, generated.puzzle.seqC);
        if (!completion.a || !completion.b || !completion.c) return fail("canonicalFullPath did not solve A/B/C");
        return ok("canonicalFullPath solves A/B/C in " + path.length + " picks");
    }

    function l5_exportIsDeepClone(Core, Generator) {
        var generated = generate(Generator, makeRequest("standard", 0x5eed1234, 0));
        var exported = Core.buildSessionExport(generated.config, generated.puzzle, generated.report, {
            metrics: { traceValue: 0.42 }
        });
        exported.PuzzleConfig.id = "mutated";
        exported.PuzzleInstance.familySeed = 0;
        exported.SolveReport.profile = "mutated";
        if (generated.config.id === "mutated") return fail("config not cloned");
        if (generated.puzzle.familySeed === 0) return fail("puzzle not cloned");
        if (generated.report.profile === "mutated") return fail("report not cloned");
        return ok("session export detaches config/puzzle/report");
    }

    function l6_profileCoverage(Core, Generator) {
        var profiles = ["standard", "elite6", "elite7"];
        var i;
        for (i = 0; i < profiles.length; i += 1) {
            var generated = generate(Generator, makeRequest(profiles[i], 0x0badc0de + i, i));
            if (generated.config.id !== profiles[i]) return fail("wrong config id for " + profiles[i]);
            if (generated.puzzle.matrix.length !== generated.config.size) return fail("matrix rows mismatch for " + profiles[i]);
            if (generated.puzzle.matrix[0].length !== generated.config.size) return fail("matrix cols mismatch for " + profiles[i]);
            if ((generated.puzzle.bufferCap || generated.config.bufferCap) !== generated.config.bufferCap) return fail("bufferCap mismatch for " + profiles[i]);
        }
        return ok("all profiles generated with matching matrix + buffer metadata");
    }

    var SUITE = [
        { id: "l1", title: "same request => same puzzle/report", run: l1_deterministicGeneration },
        { id: "l2", title: "solver replay matches generator report", run: l2_solverReportMatches },
        { id: "l3", title: "canonicalMainPath solves A/B", run: l3_canonicalMainPathSolvesAB },
        { id: "l4", title: "canonicalFullPath solves A/B/C", run: l4_canonicalFullPathSolvesABC },
        { id: "l5", title: "buildSessionExport deep clones", run: l5_exportIsDeepClone },
        { id: "l6", title: "all profiles generate coherent metadata", run: l6_profileCoverage }
    ];

    function runOne(Core, Generator, Solver, id) {
        var i;
        for (i = 0; i < SUITE.length; i += 1) {
            if (SUITE[i].id !== id) continue;
            var started = typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
            var outcome;
            try {
                outcome = SUITE[i].run(Core, Generator, Solver);
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

    function runAll(Core, Generator, Solver) {
        var results = [];
        var i;
        var passed = 0;
        var failed = 0;
        for (i = 0; i < SUITE.length; i += 1) {
            results.push(runOne(Core, Generator, Solver, SUITE[i].id));
        }
        for (i = 0; i < results.length; i += 1) {
            if (results[i].pass) passed += 1;
            else failed += 1;
        }
        return {
            results: results,
            passed: passed,
            failed: failed,
            total: results.length
        };
    }

    return {
        SUITE: SUITE,
        runOne: runOne,
        runAll: runAll
    };
});
