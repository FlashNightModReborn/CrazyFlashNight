"use strict";

function normalizeBundle(bundle) {
    if (bundle && Array.isArray(bundle.results)) return bundle;
    return {
        results: [],
        passed: 0,
        failed: 0,
        total: 0
    };
}

function formatBundle(game, bundle) {
    var lines = [];
    var safe = normalizeBundle(bundle);
    lines.push("[" + game + "] " + safe.passed + "/" + safe.total + " passed");
    var i;
    for (i = 0; i < safe.results.length; i += 1) {
        var item = safe.results[i];
        lines.push((item.pass ? "  PASS " : "  FAIL ") + item.id + " " + item.title + (item.detail ? " :: " + item.detail : ""));
    }
    return lines.join("\n");
}

function runGameSuite(game, suite, args, caseId) {
    if (!suite) throw new Error("suite missing for " + game);
    if (caseId) {
        var single = suite.runOne.apply(null, args.concat(caseId));
        return {
            results: [single],
            passed: single.pass ? 1 : 0,
            failed: single.pass ? 0 : 1,
            total: 1
        };
    }
    return normalizeBundle(suite.runAll.apply(null, args));
}

module.exports = {
    formatBundle: formatBundle,
    runGameSuite: runGameSuite
};
