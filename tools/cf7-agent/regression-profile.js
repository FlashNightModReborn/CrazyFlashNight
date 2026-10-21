"use strict";

const path = require("node:path");
const assert = require("node:assert/strict");
const SCHEMA = "cf7.regression-runtime.v1";
const SLOTS = Object.freeze([
  "cf7_agent_152_a28", "cf7_agent_152_b29", "cf7_agent_152_c68",
  "cf7_agent_152_d69", "cf7_agent_152_e69"
]);
const CANDIDATE = /^c-[0-9a-f]{12}-[0-9a-f]{10}-[a-z0-9][a-z0-9-]{0,31}$/;

function resolve(preparation) {
  if (preparation?.schema !== SCHEMA) return null;
  assert(SLOTS.includes(preparation.slots?.targetSlot), "Regression target must belong to the closed test cohort");
  assert(CANDIDATE.test(preparation.candidateId || ""), "Regression requires an immutable isolated candidate");
  assert(path.isAbsolute(preparation.resourcesRoot || ""), "Regression resourcesRoot must be absolute");
  return { slot: preparation.slots.targetSlot, candidateId: preparation.candidateId };
}

module.exports = { SCHEMA, SLOTS, CANDIDATE, resolve };
