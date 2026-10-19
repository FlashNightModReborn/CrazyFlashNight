#!/usr/bin/env node
"use strict";

// Read-only: full Git objects and current protected source scope, never save/game probes.
const Common = require("./common");
const Scope = require("./scope-manifest");
const Materialize = require("./materialize");
function diagnose(rootValue, runIdValue, scopeValue) {
  const root = Common.assertCanonicalRoot(rootValue || Common.CANONICAL_ROOT);
  Materialize.gitEnvironment();
  const layout = Materialize.materializationLayout(root, runIdValue);
  const scope = scopeValue || Scope.captureCurrentTreeScope(root);
  let budget;
  try { budget = Materialize.assertWorktreePathBudget(root, layout.destination, scope); }
  catch (error) {
    if (error.code !== "material_shop_worktree_path_budget_exceeded") throw error;
    budget = error.details;
  }
  const maximumCanonicalRootUtf16 = root.length + budget.maximumPathLength - budget.longestPathLength;
  const result = { ok: budget.longestPathLength <= budget.maximumPathLength,
    diagnosticOnly: true, readOnly: true, intentSchema: layout.schema,
    canonicalRoot: root, canonicalRootUtf16: root.length,
    runId: layout.runId, runIdUtf16: layout.runId.length,
    evidenceRunDir: layout.runDir, destination: layout.destination,
    relativeMaximumUtf16: budget.longestRelativePath.length,
    maximumCanonicalRootUtf16,
    maximumNewRunIdUtf16: Math.max(0, Math.min(100,
      layout.runId.length + budget.maximumPathLength - budget.longestPathLength)),
    budget,
    note: "Only this exact current HEAD plus sealed overlay is projected. Historical exceptions do not apply. Deep roots fail before prepare writes. No global long-path settings, external work base, symlink or subst is used." };
  return result;
}
function parseArgs(argv) {
  if (argv.length !== 2 || argv[0] !== "--run-id") {
    Common.fail("material_shop_layout_diagnostic_arguments_invalid", "materialize",
      "use --run-id <one-new-closed-run-id>; this command is read-only");
  }
  return argv[1];
}
function main() {
  try {
    const value = diagnose(Common.CANONICAL_ROOT, parseArgs(process.argv.slice(2)));
    process.stdout.write(JSON.stringify(value, null, 2) + "\n");
    if (!value.ok) process.exitCode = 1;
  } catch (error) {
    process.stderr.write(JSON.stringify(Object.assign(Common.publicError(error), { details: error.details || null })) + "\n");
    process.exitCode = 1;
  }
}
module.exports = { diagnose, parseArgs };
if (require.main === module) main();
