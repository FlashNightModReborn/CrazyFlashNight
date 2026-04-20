#!/usr/bin/env node

var fs = require("fs");
var path = require("path");
var cp = require("child_process");

var ROOT = path.resolve(__dirname, "..");
var errors = [];
var warnings = [];

function abs(rel) {
    return path.join(ROOT, rel);
}

function read(rel) {
    return fs.readFileSync(abs(rel), "utf8");
}

function exists(rel) {
    return fs.existsSync(abs(rel));
}

function expect(condition, message) {
    if (!condition) errors.push(message);
}

function warn(condition, message) {
    if (!condition) warnings.push(message);
}

function expectFile(rel) {
    expect(exists(rel), "missing file: " + rel);
}

function expectContains(rel, pattern, message) {
    var text = read(rel);
    expect(pattern.test(text), message + " [" + rel + "]");
}

function expectNotContains(rel, pattern, message) {
    var text = read(rel);
    expect(!pattern.test(text), message + " [" + rel + "]");
}

var REQUIRED_FILES = [
    "AGENTS.md",
    "CLAUDE.md",
    "README.md",
    "agentsDoc/architecture.md",
    "agentsDoc/testing-guide.md",
    "agentsDoc/coding-standards.md",
    "agentsDoc/self-optimization.md",
    "agentsDoc/documentation-governance.md",
    "agentsDoc/agent-harness.md",
    "agentsDoc/human-care.md",
    "automation/README.md",
    "launcher/README.md",
    "docs/tech-stack-rationalization.md",
    "scripts/FlashCS6自动化编译.md",
    "tools/validate-doc-governance.js"
];

var AGENTS_REFERENCES = [
    "agentsDoc/as2-anti-hallucination.md",
    "agentsDoc/testing-guide.md",
    "scripts/FlashCS6自动化编译.md",
    "agentsDoc/coding-standards.md",
    "agentsDoc/as2-performance.md",
    "agentsDoc/game-systems.md",
    "agentsDoc/data-schemas.md",
    "agentsDoc/game-design.md",
    "agentsDoc/agent-harness.md",
    "agentsDoc/human-care.md",
    "launcher/README.md",
    "agentsDoc/architecture.md",
    "docs/tech-stack-rationalization.md",
    "tools/cfn-cli.sh",
    "automation/README.md",
    "agentsDoc/documentation-governance.md",
    "agentsDoc/self-optimization.md",
    "agentsDoc/shared-notes.md",
    "README.md"
];

for (var i = 0; i < REQUIRED_FILES.length; i++) expectFile(REQUIRED_FILES[i]);
for (var j = 0; j < AGENTS_REFERENCES.length; j++) expectFile(AGENTS_REFERENCES[j]);

// ---- Baseline commit markers ----

var BASELINE_DOCS = [
    "AGENTS.md",
    "README.md",
    "agentsDoc/architecture.md",
    "agentsDoc/testing-guide.md",
    "agentsDoc/coding-standards.md",
    "agentsDoc/documentation-governance.md",
    "agentsDoc/self-optimization.md",
    "agentsDoc/agent-harness.md",
    "agentsDoc/human-care.md",
    "docs/tech-stack-rationalization.md"
];

for (var b = 0; b < BASELINE_DOCS.length; b++) {
    expectContains(BASELINE_DOCS[b], /最后核对代码基线.*commit `[\da-f]{7,40}`/, "baseline marker missing");
}

expectContains("AGENTS.md", /Context Packs（按任务最小加载，最后核对 commit `[\da-f]{7,40}`）/, "AGENTS Context Packs baseline missing");
expectContains("launcher/README.md", /文档角色/, "launcher README role note missing");
expectContains("launcher/README.md", /commit `[\da-f]{7,40}`/, "launcher README commit baseline missing");

// ---- Baseline commit must exist in git history ----

function gitHasCommit(sha) {
    var r = cp.spawnSync("git", ["rev-parse", "--verify", "--quiet", sha], {
        cwd: ROOT,
        stdio: ["ignore", "pipe", "ignore"]
    });
    return r.status === 0 && (r.stdout + "").trim().length > 0;
}

var hasGit = false;
try {
    var r0 = cp.spawnSync("git", ["rev-parse", "--git-dir"], {
        cwd: ROOT,
        stdio: ["ignore", "ignore", "ignore"]
    });
    hasGit = r0.status === 0;
} catch (e) {
    hasGit = false;
}
if (!hasGit) {
    warnings.push("git not available; skipping baseline commit existence check");
}

if (hasGit) {
    var seen = {};
    for (var d = 0; d < BASELINE_DOCS.length; d++) {
        var docRel = BASELINE_DOCS[d];
        var text = read(docRel);
        var re = /commit `([\da-f]{7,40})`/g;
        var m;
        while ((m = re.exec(text)) !== null) {
            var sha = m[1];
            if (seen[sha] === undefined) seen[sha] = gitHasCommit(sha);
            expect(seen[sha], "baseline commit `" + sha + "` not in git history [" + docRel + "]");
        }
    }
}

// ---- Doc size budget (lines) ----
// Source of truth: agentsDoc/documentation-governance.md §7

var SIZE_BUDGET = {
    "AGENTS.md": 80,
    "CLAUDE.md": 20,
    "README.md": 120,
    "agentsDoc/testing-guide.md": 110,
    "agentsDoc/agent-harness.md": 90,
    "agentsDoc/human-care.md": 90,
    "agentsDoc/documentation-governance.md": 130,
    "agentsDoc/self-optimization.md": 130
};

function lineCount(rel) {
    var text = read(rel);
    var n = 0;
    for (var k = 0; k < text.length; k++) if (text.charCodeAt(k) === 10) n++;
    if (text.length && text.charCodeAt(text.length - 1) !== 10) n++;
    return n;
}

for (var f in SIZE_BUDGET) {
    if (!Object.prototype.hasOwnProperty.call(SIZE_BUDGET, f)) continue;
    if (!exists(f)) continue;
    var lc = lineCount(f);
    expect(lc <= SIZE_BUDGET[f], "size budget exceeded: " + f + " has " + lc + " lines, budget " + SIZE_BUDGET[f]);
}

// ---- Tech stack matrix shape ----

expectContains("docs/tech-stack-rationalization.md", /## 2\. 三段式矩阵/, "tech-stack matrix heading missing");
expectContains("docs/tech-stack-rationalization.md", /### Hard Keep/, "Hard Keep section missing");
expectContains("docs/tech-stack-rationalization.md", /### Contain/, "Contain section missing");
expectContains("docs/tech-stack-rationalization.md", /### Retire \/ Stop Expanding/, "Retire section missing");

// ---- Testing guide must keep canonical commands ----

expectContains("agentsDoc/testing-guide.md", /compile_test\.ps1/, "testing-guide missing Flash smoke command");
expectContains("agentsDoc/testing-guide.md", /launcher\/build\.ps1/, "testing-guide missing launcher build command");
expectContains("agentsDoc/testing-guide.md", /--bus-only/, "testing-guide missing bus-only");
expectContains("agentsDoc/testing-guide.md", /run-minigame-qa\.js/, "testing-guide missing minigame QA");
expectContains("agentsDoc/testing-guide.md", /validate-doc-governance\.js/, "testing-guide missing doc governance validation");

// ---- Self-optimization must reference governance + human-care ----

expectContains("agentsDoc/self-optimization.md", /validate-doc-governance\.js/, "self-optimization missing governance validation");
expectContains("agentsDoc/self-optimization.md", /human-care\.md/, "self-optimization missing human-care link");
expectContains("agentsDoc/documentation-governance.md", /维护触发器/, "documentation-governance missing trigger section");
expectContains("agentsDoc/documentation-governance.md", /## 7\. 文档体量预算/, "documentation-governance missing size budget section");

// ---- Wiring of new canonical docs ----

expectContains("AGENTS.md", /agentsDoc\/agent-harness\.md/, "AGENTS missing agent-harness link");
expectContains("AGENTS.md", /agentsDoc\/human-care\.md/, "AGENTS missing human-care link");
expectContains("CLAUDE.md", /agentsDoc\/agent-harness\.md/, "CLAUDE missing agent-harness link");
expectContains("CLAUDE.md", /agentsDoc\/human-care\.md/, "CLAUDE missing human-care link");

// ---- New doc minimum content shape ----

expectContains("agentsDoc/agent-harness.md", /任务粒度/, "agent-harness missing task granularity");
expectContains("agentsDoc/agent-harness.md", /Subagent/, "agent-harness missing subagent");
expectContains("agentsDoc/agent-harness.md", /Flash smoke/, "agent-harness missing project-specific Flash smoke note");
expectContains("agentsDoc/human-care.md", /主动行为/, "human-care missing active-behavior section");
expectContains("agentsDoc/human-care.md", /软停/, "human-care missing soft-stop section");

// ---- Stale narrative guards ----

expectNotContains("AGENTS.md", /AS2 \+ Flash CS6 技术栈/, "stale AS2-only summary leaked into AGENTS");
expectNotContains("README.md", /内置Node\.js本地服务器/, "stale Node server description leaked into root README");
expectNotContains("README.md", /Node\.js：14\.0\+/, "stale Node version leaked into root README");
expectNotContains("automation/README.md", /Node\.js 服务器/, "stale Node server language leaked into automation README");
expectNotContains("agentsDoc/coding-standards.md", /\.NET Framework 4\.5\b/, "stale .NET version leaked into coding-standards");

// ---- Output ----

if (warnings.length) {
    for (var w = 0; w < warnings.length; w++) {
        console.warn("[doc-governance] warn: " + warnings[w]);
    }
}

if (errors.length) {
    console.error("[doc-governance] failed");
    for (var e = 0; e < errors.length; e++) {
        console.error(" - " + errors[e]);
    }
    process.exit(1);
}

console.log("[doc-governance] ok");
