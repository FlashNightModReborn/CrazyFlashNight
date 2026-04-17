#!/usr/bin/env node
"use strict";

var core = require("../core/index.js");
var levels = require("../app/level-specs.js");

function readArg(name, fallback) {
    var index = process.argv.indexOf(name);
    if (index === -1 || index + 1 >= process.argv.length) return fallback;
    return process.argv[index + 1];
}

var specId = readArg("--spec", "mvp-3pin-v1");
var seed = readArg("--seed", "dev-default");
var turns = parseInt(readArg("--turns", "6"), 10);

var spec = levels.getSpec(specId);
var state = core.createState(spec, seed);
var step = 0;
while (state.status === "ongoing" && step < turns) {
    var hint = core.getHint(state);
    if (!hint) break;
    if (state.clampCharge >= state.spec.clamp.cost && step > 1) {
        core.armClamp(state);
    }
    core.trySwap(state, hint.from, hint.to);
    step += 1;
}

var replay = core.serializeReplay(state);
var replayed = core.replayFromLog(spec, seed, replay);
var originalHash = core.computeStateHash(state);
var replayHash = core.computeStateHash(replayed);
var ok = originalHash === replayHash;

process.stdout.write(JSON.stringify({
    ok: ok,
    originalHash: originalHash,
    replayHash: replayHash,
    actions: replay.actions.length,
    status: state.status,
    replayStatus: replayed.status
}, null, 2) + "\n");

process.exit(ok ? 0 : 1);
