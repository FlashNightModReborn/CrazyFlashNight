#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const Common = require("./common");
const Materialize = require("./materialize");

const SHOP_SUBJECT = "launcher/web/assets/shop-portraits/subjects/"
  + "0".repeat(64) + ".png";
const scope = { files: [{ relativePath: SHOP_SUBJECT }] };
const base = path.resolve(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
  Materialize.MATERIALIZED_DIRECTORY);
const destination = (runId) => path.join(base, runId, "resources");
let passed = 0;

function test(name, callback) {
  callback();
  passed += 1;
  process.stdout.write("ok - " + name + "\n");
}

test("13-character run id keeps the longest shop subject at 259", () => {
  const result = Materialize.assertMaterializedPathBudget(
    destination("a5-0813-1903x"), scope);
  assert.strictEqual(result.runIdLength, 13);
  assert.strictEqual(result.longestRelativePath, SHOP_SUBJECT);
  assert.strictEqual(result.longestPathLength, 259);
  assert.strictEqual(result.maximumPathLength, 259);
  assert.strictEqual(result.safeRunIdMax, 13);
});

test("14-character run id fails before any destination is created", () => {
  const target = destination("a5-0813-1903xy");
  const existedBefore = fs.existsSync(target);
  assert.throws(() => Materialize.assertMaterializedPathBudget(target, scope), (error) => {
    assert.strictEqual(error.code, "material_shop_materialized_path_budget_exceeded");
    assert.strictEqual(error.phase, "materialize");
    assert.strictEqual(error.details.longestRelativePath, SHOP_SUBJECT);
    assert.strictEqual(error.details.longestPathLength, 260);
    assert.strictEqual(error.details.maximumPathLength, 259);
    assert.strictEqual(error.details.safeRunIdMax, 13);
    assert.strictEqual(error.details.longestAbsolutePath,
      path.join(target, SHOP_SUBJECT.replace(/\//g, path.sep)));
    return true;
  });
  assert.strictEqual(fs.existsSync(target), existedBefore);
});

test("historical t1903 run id projects the observed 282-character path and fails", () => {
  assert.throws(() => Materialize.assertMaterializedPathBudget(
    destination("a5-material-shop-agent-20260813t1903"), scope), (error) => {
    assert.strictEqual(error.code, "material_shop_materialized_path_budget_exceeded");
    assert.strictEqual(error.details.runIdLength, 36);
    assert.strictEqual(error.details.longestPathLength, 282);
    assert.strictEqual(error.details.safeRunIdMax, 13);
    return true;
  });
});

test("prepare invokes the budget gate before creating its owned directories", () => {
  const source = fs.readFileSync(path.join(__dirname, "prepare.js"), "utf8");
  const gate = source.indexOf("Materialize.assertMaterializedPathBudget(resourcesRoot, closure.scope)");
  const firstMkdir = source.indexOf("fs.mkdirSync(base", gate);
  assert(gate >= 0 && firstMkdir > gate);
});

process.stdout.write(passed + "/" + passed + " materialized path-budget tests passed\n");
