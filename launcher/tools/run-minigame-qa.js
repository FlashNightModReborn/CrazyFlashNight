#!/usr/bin/env node
"use strict";

var runner = require("../web/modules/minigames/shared/dev/node-qa-runner.js");

var args = process.argv.slice(2);
var game = readArg("--game", "all");
var caseId = readArg("--case", "");

function readArg(name, fallback) {
    var idx = args.indexOf(name);
    if (idx >= 0 && idx + 1 < args.length) return args[idx + 1];
    return fallback;
}

function getSuites() {
    return {
        lockbox: {
            suite: require("../web/modules/minigames/lockbox/dev/qa-suite.js"),
            args: [
                require("../web/modules/minigames/lockbox/core/index.js"),
                require("../web/modules/minigames/lockbox/core/generator.js"),
                require("../web/modules/minigames/lockbox/core/solver.js")
            ]
        },
        pinalign: {
            suite: require("../web/modules/minigames/pinalign/dev/qa-suite.js"),
            args: [
                require("../web/modules/minigames/pinalign/core/index.js"),
                require("../web/modules/minigames/pinalign/app/level-specs.js")
            ]
        }
    };
}

function main() {
    var suites = getSuites();
    var names = game === "all" ? Object.keys(suites) : [game];
    var overallFailed = false;
    var i;
    for (i = 0; i < names.length; i += 1) {
        if (!suites[names[i]]) {
            console.error("unknown game: " + names[i]);
            process.exitCode = 1;
            return;
        }
        var bundle = runner.runGameSuite(names[i], suites[names[i]].suite, suites[names[i]].args, caseId || null);
        console.log(runner.formatBundle(names[i], bundle));
        if (bundle.failed) overallFailed = true;
    }
    if (overallFailed) process.exitCode = 1;
}

main();
