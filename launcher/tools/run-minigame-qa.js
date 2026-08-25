#!/usr/bin/env node
"use strict";

var childProcess = require("child_process");
var path = require("path");
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
        },
        gobang: {
            suite: require("../web/modules/minigames/gobang/dev/qa-suite.js"),
            args: [
                require("../web/modules/minigames/gobang/core/index.js")
            ]
        },
        blackmarket: {
            suite: require("../web/modules/minigames/blackmarket/dev/qa-suite.js"),
            args: [
                require("../web/modules/minigames/blackmarket/core/index.js"),
                require("../../tools/fixtures/blackmarket/black-market-shadow-catalog.v1.json"),
                require("../web/modules/minigames/blackmarket/visual/item-surface.js"),
                require("../web/modules/minigames/blackmarket/visual/equipment-preview.js"),
                require("../web/assets/dressup/manifest.json")
            ]
        },
        warlord: {
            external: path.resolve(__dirname,
                "../web/modules/minigames/warlord/dev/node-qa.mjs")
        }
    };
}

function runExternalSuite(name, suite, selectedCase) {
    var externalArgs = [suite.external];
    if (selectedCase) externalArgs.push("--case", selectedCase);
    var result = childProcess.spawnSync(process.execPath, externalArgs, {
        cwd: path.dirname(suite.external),
        encoding: "utf8",
        windowsHide: true
    });
    var lines = String(result.stdout || "").trim().split(/\r?\n/).filter(Boolean);
    try {
        var bundle = JSON.parse(lines[lines.length - 1] || "");
        if (result.status !== 0 && !bundle.failed) throw new Error("external suite exited " + result.status);
        return bundle;
    } catch (error) {
        return {
            results: [{
                id: selectedCase || "external-suite",
                title: "external " + name + " suite",
                pass: false,
                detail: (error && error.message ? error.message : String(error))
                    + (result.stderr ? " :: " + result.stderr.trim() : "")
            }],
            passed: 0,
            failed: 1,
            total: 1
        };
    }
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
        var bundle = suites[names[i]].external
            ? runExternalSuite(names[i], suites[names[i]], caseId || null)
            : runner.runGameSuite(names[i], suites[names[i]].suite, suites[names[i]].args, caseId || null);
        console.log(runner.formatBundle(names[i], bundle));
        if (bundle.failed) overallFailed = true;
    }
    if (overallFailed) process.exitCode = 1;
}

main();
