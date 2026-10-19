#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const vm = require("vm");
const Budget = require("./worktree-path-budget");
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-a5-budget-"));
const repository = path.join(temporary, "objects.git");
const destination = path.join(temporary, "uncreated", "resources");
let passed = 0;

function test(name, callback) {
  callback();
  passed += 1;
  process.stdout.write("ok - " + name + "\n");
}
function rejects(callback, suffix) {
  assert.throws(callback, (error) => error.code === "material_shop_worktree_path_budget_" + suffix);
}
function git(args, input) {
  const result = childProcess.spawnSync("git", ["-C", repository].concat(args), {
    encoding: null, input, env: Object.assign({}, process.env, {
      GIT_AUTHOR_NAME: "Path budget fixture", GIT_AUTHOR_EMAIL: "fixture@example.invalid",
      GIT_COMMITTER_NAME: "Path budget fixture", GIT_COMMITTER_EMAIL: "fixture@example.invalid",
      GIT_AUTHOR_DATE: "2026-01-01T00:00:00Z", GIT_COMMITTER_DATE: "2026-01-01T00:00:00Z",
    }),
  });
  assert.strictEqual(result.status, 0, String(result.stderr || result.error));
  return result.stdout.toString("utf8").trim();
}
function commit(files) {
  const directories = {};
  const blob = git(["hash-object", "-w", "--stdin"], "fixture\n");
  files.forEach((entry) => {
    const segments = entry.relativePath.split("/");
    let node = directories;
    segments.slice(0, -1).forEach((segment) => { node[segment] = node[segment] || {}; node = node[segment]; });
    node[segments[segments.length - 1]] = { oid: blob, mode: entry.mode || "100644" };
  });
  function tree(node) {
    const records = Object.keys(node).map((name) => {
      const entry = node[name];
      return entry.oid ? entry.mode + " blob " + entry.oid + "\t" + name + "\0"
        : "040000 tree " + tree(entry) + "\t" + name + "\0";
    });
    return git(["mktree", "-z"], Buffer.from(records.join(""), "utf8"));
  }
  return git(["commit-tree", tree(directories)], "isolated object fixture\n");
}
const overlay = [{ relativePath: "overlay.txt" }];
function scope(head, files) { return { head, files: files || overlay }; }
function record(name, mode, type) {
  return Buffer.from((mode || "100644") + " " + (type || "blob") + " " + "a".repeat(40) + "\t" + name + "\0");
}

try {
  const initialized = childProcess.spawnSync("git", ["init", "--bare", repository], { encoding: "utf8" });
  assert.strictEqual(initialized.status, 0, initialized.stderr);

  [239, 240, 241].forEach((length) => test("actual Git full HEAD projects boundary " + length, () => {
    const relativePath = "x".repeat(length - destination.length - 1);
    const head = commit([{ relativePath }]);
    if (length <= 240) {
      const result = Budget.assertWorktreePathBudget(repository, destination, scope(head));
      assert.strictEqual(result.longestPathLength, length);
      assert.strictEqual(result.headEntryCount, 1);
      assert.strictEqual(result.projectedEntryCount, 2);
    } else {
      assert.throws(() => Budget.assertWorktreePathBudget(repository, destination, scope(head)), (error) => {
        assert.strictEqual(error.code, "material_shop_worktree_path_budget_exceeded");
        assert.strictEqual(error.details.longestRelativePath, relativePath);
        assert.strictEqual(error.details.longestPathLength, 241);
        return true;
      });
    }
    assert.strictEqual(fs.existsSync(destination), false);
  }));

  test("overlay additions and their directories are checked with all HEAD entries", () => {
    const head = commit([{ relativePath: "tracked/original.txt" }]);
    const relativePath = "overlay/" + "z".repeat(241 - destination.length - 1 - "overlay/".length);
    rejects(() => Budget.assertWorktreePathBudget(repository, destination, scope(head, [{ relativePath }])), "exceeded");
    const result = Budget.assertWorktreePathBudget(repository, destination, scope(head, [
      { relativePath: "tracked/original.txt" }, { relativePath: "new/overlay.txt" },
    ]));
    assert.strictEqual(result.headEntryCount, 2);
    assert.strictEqual(result.projectedEntryCount, 4);
  });

  test("Chinese and non-BMP names count original UTF-16 units without normalization", () => {
    const relativePath = "中文/\u{1f680}e\u0301.txt";
    const head = commit([{ relativePath }]);
    const result = Budget.assertWorktreePathBudget(repository, destination, scope(head, [{ relativePath }]));
    assert.strictEqual(result.longestPathLength, destination.length + 1 + relativePath.length);
    assert.strictEqual(result.longestRelativePath, relativePath);
  });

  test("NUL parser preserves raw tabs/newlines instead of line-splitting or Git display quoting", () => {
    const name = "folder/tab\tnewline\n中文.txt";
    const parsed = Budget.parseTree(record(name));
    assert.strictEqual(parsed.length, 1);
    assert.strictEqual(parsed[0].relativePath, name);
    rejects(() => Budget.assertRelative(name), "invalid");
  });
  test("invalid UTF-8 fails closed", () => {
    rejects(() => Budget.parseTree(Buffer.concat([
      record("x").subarray(0, -2), Buffer.from([0xff, 0]),
    ])), "incomplete");
  });
  test("empty, truncated and malformed trees fail closed", () => {
    [Buffer.alloc(0), record("x").subarray(0, -1), Buffer.from("broken\0")].forEach((data) => {
      rejects(() => Budget.parseTree(data), "incomplete");
    });
    rejects(() => Budget.parseTree(record("x", "040000", "blob")), "incomplete");
  });
  test("symlinks and gitlinks do not receive fake complete coverage", () => {
    rejects(() => Budget.parseTree(record("link", "120000", "blob")), "unsupported");
    rejects(() => Budget.parseTree(record("submodule", "160000", "commit")), "unsupported");
    const head = commit([{ relativePath: "link", mode: "120000" }]);
    rejects(() => Budget.assertWorktreePathBudget(repository, destination, scope(head)), "unsupported");
  });
  test("malformed/unsafe overlay and Windows-colliding names fail closed", () => {
    ["../escape", "/absolute", "a//b", "a\\b", "x:", "con.txt", "tail.", "tail ", "bad\ud800"].forEach((name) => {
      rejects(() => Budget.projectPaths(destination, [{ relativePath: "head", kind: "file" }],
        [{ relativePath: name }]), "invalid");
    });
    rejects(() => Budget.projectPaths(destination, [{ relativePath: "HEAD", kind: "file" }],
      [{ relativePath: "head" }]), "invalid");
    rejects(() => Budget.projectPaths(destination, [{ relativePath: "head", kind: "file" }],
      [{ relativePath: "head/child" }]), "invalid");
    rejects(() => Budget.projectPaths(destination, [{ relativePath: "dir/child", kind: "file" }], overlay), "incomplete");
  });
  test("trailing root separator is joined once with no repeated projection suffix", () => {
    const entries = [{ relativePath: "resources/runtime.config", kind: "file" },
      { relativePath: "resources", kind: "directory" }];
    const result = Budget.projectPaths(destination + path.sep, entries, overlay);
    assert.strictEqual(result.longestAbsolutePath, path.join(destination, "resources", "runtime.config"));
  });
  test("unavailable repository, missing commit and mutable names are incomplete/invalid", () => {
    rejects(() => Budget.assertWorktreePathBudget(repository + "-missing", destination, scope("a".repeat(40))), "incomplete");
    rejects(() => Budget.assertWorktreePathBudget(repository, destination, scope("a".repeat(40))), "incomplete");
    rejects(() => Budget.assertWorktreePathBudget(repository, destination, scope("HEAD")), "invalid");
    assert.strictEqual(fs.existsSync(repository + "-missing"), false);
  });
  test("Git reads do not create a worktree, index, refs or destination", () => {
    assert.strictEqual(fs.existsSync(destination), false);
    assert.strictEqual(fs.existsSync(path.join(repository, "index")), false);
    assert.strictEqual(fs.existsSync(path.join(repository, "worktrees")), false);
    assert.strictEqual(git(["for-each-ref"]), "");
  });
  test("replace refs cannot make the actual worktree differ from the preflighted commit", () => {
    const original = commit([{ relativePath: "safe.txt" }]);
    const replacementName = "x".repeat(225);
    const replacement = commit([{ relativePath: replacementName }]);
    const replaceRef = "refs/replace/" + original;
    git(["update-ref", replaceRef, replacement]);
    const checkedOut = path.join(temporary, "actual-checkout");
    try {
      assert.strictEqual(git(["ls-tree", "--name-only", original]), replacementName);
      const result = Budget.assertWorktreePathBudget(repository, checkedOut,
        scope(original, [{ relativePath: "safe.txt" }]));
      assert.strictEqual(result.longestRelativePath, "safe.txt");
      // Expose the unchanged private wrapper only inside this test's lexical
      // harness, then run its real spawnSync/worktree command on the tiny fixture.
      const file = path.join(__dirname, "materialize.js");
      const imports = { child_process: childProcess, fs, path, "../lib/evidence-artifact": {},
        "./common": { fail: () => { throw new Error("fixture command failed"); } },
        "./scope-manifest": {}, "./worktree-path-budget": Budget };
      const localRequire = (id) => imports[id];
      const module = { exports: {} };
      const wrapper = new vm.Script("(function(require, module, exports) {\n"
        + fs.readFileSync(file, "utf8") + "\nreturn runGit;\n})", { filename: file }).runInThisContext();
      const runGit = wrapper(localRequire, module, module.exports);
      runGit(repository, ["worktree", "add", "--detach", checkedOut, original]);
      assert.strictEqual(fs.existsSync(path.join(checkedOut, "safe.txt")), true);
      assert.strictEqual(fs.existsSync(path.join(checkedOut, replacementName)), false);
      runGit(repository, ["worktree", "remove", checkedOut]);
    } finally {
      git(["update-ref", "-d", replaceRef]);
    }
  });
  test("actual materialize and prepare rejection leave owned roots and markers absent", () => {
    const head = commit([{ relativePath: "x".repeat(225) }]);
    const sealed = Object.assign(scope(head), { root: repository });
    const ownedRelative = path.join("tmp", "workbench-live-e2e", "material-shop");
    const owned = path.join(repository, ownedRelative);
    let writes = 0;
    const guardedFs = Object.create(fs);
    ["mkdirSync", "writeFileSync", "copyFileSync", "renameSync", "unlinkSync", "openSync"].forEach((name) => {
      guardedFs[name] = () => { writes += 1; throw new Error("unexpected filesystem write: " + name); };
    });
    const common = {
      CANONICAL_ROOT: repository, OWNED_BASE_RELATIVE: ownedRelative,
      assertCanonicalRoot: (root) => root,
      assertDedicatedSlots: (seedSlot, targetSlot, recoverySlot) => ({ seedSlot, targetSlot, recoverySlot }),
      ID_RE: /^[a-z]+$/,
      resolveWithin: (root, relative) => ({ relative, absolute: path.join(root, ...relative.split("/")) }),
      fail: (code, phase, message, details) => {
        const error = new Error(message); Object.assign(error, { code, phase, details }); throw error;
      },
    };
    const evidence = { pathInside: (root, target) => {
      const relative = path.relative(root, target);
      return !!relative && relative !== ".." && !relative.startsWith(".." + path.sep) && !path.isAbsolute(relative);
    } };
    function load(name, dependencies) {
      const file = path.join(__dirname, name);
      const module = { exports: {} };
      const imports = Object.assign({ fs: guardedFs, path, child_process: childProcess,
        "./common": common, "../lib/evidence-artifact": evidence,
        "./worktree-path-budget": Budget }, dependencies);
      const localRequire = (id) => {
        assert(Object.prototype.hasOwnProperty.call(imports, id), "unexpected import " + id);
        return imports[id];
      };
      const wrapper = new vm.Script("(function(require, module, exports, __dirname, __filename) {\n"
        + fs.readFileSync(file, "utf8") + "\n})", { filename: file }).runInThisContext();
      wrapper(localRequire, module, module.exports, __dirname, file);
      return module.exports;
    }
    const materialize = load("materialize.js", { "./scope-manifest": { verifyScopeManifest: () => {} } });
    rejects(() => materialize.materializeScope({ root: repository, sourceRoot: repository,
      scope: sealed, destination: path.join(owned, "materialized", "one", "resources") }), "exceeded");
    const prepare = load("prepare.js", {
      "./materialize": materialize, "./production-closure": { captureProductionClosure: () => ({ scope: sealed }) },
      "./protocol": { AGENT_RUNTIME_SLOT: "target" }, "./applicability": {}, "./admission": {},
      "../lib/playwright-websocket-toolchain": {},
    });
    rejects(() => prepare.prepare({ root: repository, runId: "one", agentRuntimeJsonl: true,
      seedSlot: "seed", targetSlot: "target", recoverySlot: "recovery" }), "exceeded");
    assert.strictEqual(writes, 0);
    assert.strictEqual(fs.existsSync(owned), false);
    assert.strictEqual(fs.existsSync(path.join(repository, "worktrees")), false);
  });
  test("both production entrypoints put the new gate before all materialized side effects", () => {
    const materialize = fs.readFileSync(path.join(__dirname, "materialize.js"), "utf8");
    const start = materialize.indexOf("function materializeScope(");
    const gate = materialize.indexOf("WorktreePathBudget.assertWorktreePathBudget(root, settings.destination, settings.scope)", start);
    ["writeJsonAtomicNew(path.join(runDir", "acquireMaterializationProducer(runDir)",
      "runGit(root, [\"worktree\", \"add\"", "fs.mkdirSync(destination)", "fs.copyFileSync(source.path"].forEach((needle) => {
      assert(materialize.indexOf(needle, start) > gate && gate > start, needle);
    });
    const prepare = fs.readFileSync(path.join(__dirname, "prepare.js"), "utf8");
    const prepareGate = prepare.indexOf("Materialize.assertWorktreePathBudget(root, resourcesRoot, closure.scope)");
    assert(prepareGate > 0 && prepareGate < prepare.indexOf("Materialize.ensureDirectDirectoryChain(root, base"));
    assert(/if \(!fixtureMode\) \{\r?\n    WorktreePathBudget\.assertWorktreePathBudget/.test(materialize));
    const manifest = fs.readFileSync(path.join(__dirname, "scope-manifest.js"), "utf8");
    ["worktree-path-budget.js", "test-worktree-path-budget.js"].forEach((name) => assert(manifest.includes(name)));
  });
  process.stdout.write(passed + "/" + passed + " worktree path-budget tests passed\n");
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
