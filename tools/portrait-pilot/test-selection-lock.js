#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const { chooseRole, flagCount } = require("./build-selection-lock");

assert.equal(flagCount({ flags: ["none"] }), 0);
assert.equal(flagCount({ flags: ["safe_margin_risk", "variant_uncertain"] }), 2);

assert.deepEqual(
  chooseRole(
    { flags: ["none"], confidence: 0.4 },
    { flags: ["feature_uncertain"], confidence: 0.99 },
  ),
  { role: "proposal", reason: "fewer_non_none_flags" },
);

assert.deepEqual(
  chooseRole(
    { flags: ["feature_uncertain"], confidence: 0.7 },
    { flags: ["safe_margin_risk"], confidence: 0.8 },
  ),
  { role: "independent_review", reason: "higher_confidence_after_flag_tie" },
);

assert.deepEqual(
  chooseRole(
    { flags: ["variant_uncertain"], confidence: 0.8 },
    { flags: ["safe_margin_risk"], confidence: 0.8 },
  ),
  { role: "proposal", reason: "proposal_stable_tie_break" },
);

process.stdout.write("selection_lock_policy_test_passed\n");
