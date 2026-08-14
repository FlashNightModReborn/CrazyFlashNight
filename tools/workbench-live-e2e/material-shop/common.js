"use strict";

const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");

const CANONICAL_ROOT = path.resolve(__dirname, "..", "..", "..");
const OWNED_BASE_RELATIVE = path.join("tmp", "workbench-live-e2e", "material-shop");
const SOURCE_FIXTURE_SLOT = "cf7_agent_character_build_b4";
const ID_RE = /^[A-Za-z0-9._~-]{1,160}$/;
const SHA256_RE = /^[a-f0-9]{64}$/;
const GIT_OID_RE = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
const SEED_SLOT_RE = /^cf7_agent_a5_material_shop_seed(?:_[A-Za-z0-9_-]{1,48})?$/;
const TARGET_SLOT_RE = /^cf7_agent_a5_material_shop_run(?:_[A-Za-z0-9_-]{1,48})?$/;
const RECOVERY_SLOT_RE = /^cf7_agent_a5_material_shop_recovery(?:_[A-Za-z0-9_-]{1,48})?$/;

function fail(code, phase, message, details) {
  Evidence.contractFail(code, phase, message, details);
}

function exactKeys(value, keys, code, phase) {
  if (!Evidence.isPlainObject(value)
      || Evidence.canonicalJson(Object.keys(value).sort())
        !== Evidence.canonicalJson(keys.slice().sort())) {
    fail(code, phase, "object key set is not exact", {
      expected: keys.slice().sort(), actual: Evidence.isPlainObject(value)
        ? Object.keys(value).sort() : null,
    });
  }
  return value;
}

function normalizeRelative(relativePath) {
  const value = String(relativePath || "").replace(/\\/g, "/");
  if (!value || value.startsWith("/") || /^[A-Za-z]:/.test(value)
      || value.split("/").some((part) => !part || part === "." || part === "..")) {
    fail("material_shop_relative_path_invalid", "scope", "relative path is unsafe", {
      relativePath,
    });
  }
  return value;
}

function assertCanonicalRoot(rootValue) {
  const root = path.resolve(rootValue || "");
  if (root.toLowerCase() !== CANONICAL_ROOT.toLowerCase()) {
    fail("material_shop_canonical_root_mismatch", "scope",
      "A5 current-tree scope must be captured from the canonical workspace", {
        expected: CANONICAL_ROOT, actual: root,
      });
  }
  const marker = path.join(root, ".git");
  if (!fs.existsSync(marker)) {
    fail("material_shop_git_root_missing", "scope", "canonical workspace lacks .git");
  }
  return root;
}

function resolveWithin(rootValue, relativePath, phase) {
  const root = path.resolve(rootValue);
  const relative = normalizeRelative(relativePath);
  const absolute = path.resolve(root, relative.replace(/\//g, path.sep));
  const projected = path.relative(root, absolute).replace(/\\/g, "/");
  if (projected !== relative || projected.startsWith("../")) {
    fail("material_shop_path_escape", phase || "scope", "path escaped its declared root", {
      root, relative,
    });
  }
  return { root, relative, absolute };
}

function assertDedicatedSlots(seedSlot, targetSlot, recoverySlot) {
  const seed = String(seedSlot || "");
  const target = String(targetSlot || "");
  const recovery = String(recoverySlot || "");
  if (!SEED_SLOT_RE.test(seed) || !TARGET_SLOT_RE.test(target)
      || !RECOVERY_SLOT_RE.test(recovery)
      || new Set([seed.toLowerCase(), target.toLowerCase(), recovery.toLowerCase()]).size !== 3) {
    fail("material_shop_dedicated_slots_invalid", "clone",
      "seed, target, and recovery must be three distinct dedicated cf7_agent A5 slots", {
        seedSlot: seed, targetSlot: target, recoverySlot: recovery,
      });
  }
  return { seedSlot: seed, targetSlot: target, recoverySlot: recovery };
}

function publicError(error) {
  return {
    ok: false,
    code: error && error.code || "material_shop_unexpected_error",
    phase: error && error.phase || "material_shop",
    message: error && error.message || String(error),
  };
}

module.exports = {
  CANONICAL_ROOT,
  GIT_OID_RE,
  ID_RE,
  OWNED_BASE_RELATIVE,
  RECOVERY_SLOT_RE,
  SEED_SLOT_RE,
  SHA256_RE,
  SOURCE_FIXTURE_SLOT,
  TARGET_SLOT_RE,
  assertCanonicalRoot,
  assertDedicatedSlots,
  exactKeys,
  fail,
  normalizeRelative,
  publicError,
  resolveWithin,
};
