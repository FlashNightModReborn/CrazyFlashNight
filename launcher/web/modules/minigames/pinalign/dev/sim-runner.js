#!/usr/bin/env node
"use strict";

var fs = require("fs");
var path = require("path");
var core = require("../core/index.js");
var levels = require("../app/level-specs.js");

function readArg(name, fallback) {
    var index = process.argv.indexOf(name);
    if (index === -1 || index + 1 >= process.argv.length) return fallback;
    return process.argv[index + 1];
}

var specId = readArg("--spec", "mvp-3pin-v1");
var iterations = parseInt(readArg("--iterations", "50"), 10);
var policy = readArg("--policy", "greedy");
var outPath = readArg("--out", "");
var seedPrefix = readArg("--seed-prefix", specId);

var spec = levels.getSpec(specId);
var result = core.runSimulation(spec, {
    iterations: iterations,
    policy: policy,
    masterSeedPrefix: seedPrefix
});

var payload = JSON.stringify(result, null, 2);
if (outPath) {
    var resolved = path.resolve(process.cwd(), outPath);
    fs.mkdirSync(path.dirname(resolved), { recursive: true });
    fs.writeFileSync(resolved, payload, "utf8");
}
process.stdout.write(payload + "\n");
