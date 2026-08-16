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

function listFiles(relDir, predicate) {
    var out = [];
    var dir = abs(relDir);
    if (!fs.existsSync(dir)) return out;
    var names = fs.readdirSync(dir);
    for (var i = 0; i < names.length; i++) {
        var rel = path.join(relDir, names[i]).replace(/\\/g, "/");
        var full = abs(rel);
        var st = fs.statSync(full);
        if (st.isDirectory()) {
            out = out.concat(listFiles(rel, predicate));
        } else if (!predicate || predicate(rel)) {
            out.push(rel);
        }
    }
    return out;
}

function uniqueSorted(values) {
    var seen = {};
    var out = [];
    for (var i = 0; i < values.length; i++) {
        var value = values[i];
        if (seen[value]) continue;
        seen[value] = true;
        out.push(value);
    }
    return out.sort();
}

function expectExactSet(label, actual, expected) {
    var a = uniqueSorted(actual);
    var e = uniqueSorted(expected);
    var missing = [];
    var unexpected = [];
    for (var i = 0; i < e.length; i++) if (a.indexOf(e[i]) === -1) missing.push(e[i]);
    for (var j = 0; j < a.length; j++) if (e.indexOf(a[j]) === -1) unexpected.push(a[j]);
    expect(
        missing.length === 0 && unexpected.length === 0,
        label + " exact-set mismatch; missing=[" + missing.join(", ") + "] unexpected=[" + unexpected.join(", ") + "]");
}

function markedBlock(rel, markerName) {
    var text = read(rel);
    var startMarker = "<!-- " + markerName + ":start -->";
    var endMarker = "<!-- " + markerName + ":end -->";
    var start = text.indexOf(startMarker);
    var end = text.indexOf(endMarker);
    expect(start !== -1, "missing registry start marker " + markerName + " [" + rel + "]");
    expect(end !== -1 && end > start, "missing registry end marker " + markerName + " [" + rel + "]");
    expect(start === text.lastIndexOf(startMarker), "duplicate registry start marker " + markerName + " [" + rel + "]");
    expect(end === text.lastIndexOf(endMarker), "duplicate registry end marker " + markerName + " [" + rel + "]");
    if (start === -1 || end === -1 || end <= start) return "";
    return text.slice(start + startMarker.length, end);
}

function markdownTableRows(block) {
    var rows = [];
    var lines = block.split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
        if (!/^\|\s*`/.test(lines[i])) continue;
        var cells = lines[i].split("|").slice(1, -1);
        for (var c = 0; c < cells.length; c++) cells[c] = cells[c].trim();
        var key = cells[0].replace(/^`|`$/g, "");
        rows.push({ key: key, cells: cells, line: lines[i] });
    }
    return rows;
}

function sectionText(rel, heading) {
    var lines = read(rel).split(/\r?\n/);
    var start = -1;
    var end = lines.length;
    for (var i = 0; i < lines.length; i++) {
        if (lines[i] === "## " + heading) {
            start = i;
            continue;
        }
        if (start !== -1 && i > start && /^##\s+/.test(lines[i])) {
            end = i;
            break;
        }
    }
    expect(start !== -1, "missing section ## " + heading + " [" + rel + "]");
    return start === -1 ? "" : lines.slice(start, end).join("\n");
}

function validateLocalMarkdownLinks(rel) {
    var text = read(rel);
    var re = /\[[^\]]*\]\(([^)]+)\)/g;
    var match;
    while ((match = re.exec(text)) !== null) {
        var target = match[1].trim().replace(/^<|>$/g, "");
        if (/^(?:https?:|mailto:|#)/i.test(target)) continue;
        target = target.split("#")[0].split("?")[0];
        if (!target) continue;
        try { target = decodeURIComponent(target); } catch (e) { /* existence check reports it */ }
        var resolved = path.resolve(path.dirname(abs(rel)), target);
        expect(fs.existsSync(resolved), "broken local markdown link: " + match[1] + " [" + rel + "]");
    }
}

var REQUIRED_FILES = [
    "AGENTS.md",
    "CLAUDE.md",
    "README.md",
    "agentsDoc/architecture.md",
    "agentsDoc/testing-guide.md",
    "agentsDoc/as2-web-panel-migration.md",
    "agentsDoc/workbench-ui-system.md",
    "agentsDoc/coding-standards.md",
    "agentsDoc/self-optimization.md",
    "agentsDoc/documentation-governance.md",
    "agentsDoc/agent-harness.md",
    "agentsDoc/human-care.md",
    "automation/README.md",
    "launcher/README.md",
    "docs/launcher-save-editor-audio-migration-incident-2026-04-28.md",
    "docs/tech-stack-rationalization.md",
    "scripts/FlashCS6自动化编译.md",
    "tools/validate-doc-governance.js"
];

var AGENTS_REFERENCES = [
    "agentsDoc/as2-anti-hallucination.md",
    "agentsDoc/as2-web-panel-migration.md",
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
    "agentsDoc/as2-web-panel-migration.md",
    "agentsDoc/workbench-ui-system.md",
    "agentsDoc/coding-standards.md",
    "agentsDoc/documentation-governance.md",
    "agentsDoc/self-optimization.md",
    "agentsDoc/agent-harness.md",
    "agentsDoc/human-care.md",
    "launcher/README.md",
    "docs/launcher-save-editor-audio-migration-incident-2026-04-28.md",
    "docs/tech-stack-rationalization.md",
    "scripts/FlashCS6自动化编译.md",
    "docs/asLoader-README.md",
    "docs/asLoader重构-架构设计-2026-06-15.md",
    "docs/asLoader-BootSequencer-构建标准-2026-06-16.md"
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
    "launcher/README.md": 430,
    "agentsDoc/testing-guide.md": 114,
    "agentsDoc/agent-harness.md": 90,
    "agentsDoc/human-care.md": 90,
    "agentsDoc/documentation-governance.md": 150,
    "agentsDoc/self-optimization.md": 135
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

var launcherReadmeLines = read("launcher/README.md").split(/\r?\n/);
for (var lr = 0; lr < launcherReadmeLines.length; lr++) {
    expect(
        launcherReadmeLines[lr].length <= 320,
        "launcher README line exceeds 320 characters [launcher/README.md:" + (lr + 1) + "]");
}

// ---- Launcher README machine-derived governance ----

validateLocalMarkdownLinks("launcher/README.md");
validateLocalMarkdownLinks("docs/launcher-save-editor-audio-migration-incident-2026-04-28.md");
expectNotContains("launcher/README.md", /\[[^\]]*:\d+(?:-\d+)?\]\(/, "launcher README must not use drifting source-line labels");
expectNotContains("launcher/README.md", /plans\/cursor-overlay-decoupling\.md/, "stale cursor plan path leaked into launcher README");
expectNotContains("launcher/README.md", /(?:cloud build|cloud run|post-promotion audit run|deployment commit)/i, "release receipt leaked into launcher README");
expectNotContains("launcher/README.md", /\b(?:request|identity|closure)\s+`[A-F0-9]{40,64}`/i, "release identity value leaked into launcher README");
expectNotContains("launcher/README.md", /\b\d+\s*(?:passed|pass)\s*\+\s*\d+/i, "dynamic test totals leaked into launcher README");
expectNotContains("launcher/README.md", /\b\d{1,6}\/\d{1,6}\b/, "dynamic pass/count fraction leaked into launcher README");
expectNotContains("launcher/README.md", /(?:bootstrap|Core|manifest|runtime).{0,80}\b\d+(?:\.\d+)?\s*(?:KB|MB|MiB)\b/i, "runtime artifact size leaked into launcher README");
expectNotContains("launcher/README.md", /启动 Core 后立即退出/, "stale bootstrap immediate-exit narrative leaked into launcher README");

var launcherBaselineSections = [
    "源码职责地图",
    "构建、候选与发布",
    "测试入口与证据边界",
    "Panel 与 minigame 注册表"
];
for (var lbs = 0; lbs < launcherBaselineSections.length; lbs++) {
    expect(
        /最后核对代码基线.*commit `[\da-f]{7,40}`/.test(sectionText("launcher/README.md", launcherBaselineSections[lbs])),
        "launcher high-change section missing code baseline: " + launcherBaselineSections[lbs]);
}

var currentRuntimeSection = sectionText("launcher/README.md", "当前真值与阅读顺序");
expect(currentRuntimeSection.indexOf("runtime-release-consensus.json") !== -1, "launcher current truth missing runtime consensus link");
expect(currentRuntimeSection.indexOf("cf7-runtime-manifest.tsv") !== -1, "launcher current truth missing runtime manifest link");
expect(currentRuntimeSection.indexOf("runtime-build-reproducibility.md") !== -1, "launcher current truth missing release canonical link");
expect(!/[A-F0-9]{64}/i.test(currentRuntimeSection), "launcher current truth must link machine identity instead of copying 64-hex receipts");

var consensus = JSON.parse(read("config/build/runtime-release-consensus.json"));
var manifestLines = read("runtime/cf7-runtime-manifest.tsv").split(/\r?\n/);
var manifestMeta = {};
for (var ml = 0; ml < manifestLines.length; ml++) {
    var manifestCols = manifestLines[ml].split("\t");
    if (manifestCols.length === 2) manifestMeta[manifestCols[0]] = manifestCols[1];
}
expect(manifestLines[0] === "cf7-runtime-manifest-v2", "formal runtime manifest is not v2");
expect(consensus.schema === "cf7-runtime-release-consensus.v2", "formal runtime consensus is not v2");
expect(consensus.buildIdentityHash === manifestMeta.buildIdentityHash, "runtime consensus/manifest build identity mismatch");
expect(consensus.payloadClosureHash === manifestMeta.payloadClosureHash, "runtime consensus/manifest payload closure mismatch");

var bootstrapSource = read("launcher/native/bootstrap/bootstrap.cpp");
var graceMatch = /CORE_EARLY_EXIT_GRACE_MS\s*=\s*(\d+)/.exec(bootstrapSource);
expect(!!graceMatch, "bootstrap early-exit grace constant missing");
if (graceMatch) {
    var graceMs = parseInt(graceMatch[1], 10);
    expect(graceMs % 1000 === 0, "bootstrap early-exit grace is not whole seconds");
    expect(
        read("launcher/README.md").indexOf((graceMs / 1000) + " 秒早退观察窗") !== -1,
        "launcher README bootstrap observation window does not match native constant");
}

var configRows = markdownTableRows(markedBlock("launcher/README.md", "launcher-config-registry"));
var configDocKeys = configRows.map(function (row) { return row.key; });
var appConfigSource = read("launcher/src/Config/AppConfig.cs");
var configSourceKeys = [];
var configKeyRe = /string\.Equals\(key,\s*"([^"]+)"/g;
var configMatch;
while ((configMatch = configKeyRe.exec(appConfigSource)) !== null) configSourceKeys.push(configMatch[1]);
expectExactSet("launcher config registry", configDocKeys, configSourceKeys);
var envRe = /GetEnvironmentVariable\("([^"]+)"\)/g;
while ((configMatch = envRe.exec(appConfigSource)) !== null) {
    expect(markedBlock("launcher/README.md", "launcher-config-registry").indexOf("`" + configMatch[1] + "`") !== -1,
        "launcher config registry missing environment override " + configMatch[1]);
}
var shippedConfigKeys = [];
var shippedConfigLines = read("config.toml").split(/\r?\n/);
for (var scl = 0; scl < shippedConfigLines.length; scl++) {
    var shippedMatch = /^\s*([A-Za-z][A-Za-z0-9]*)\s*=/.exec(shippedConfigLines[scl]);
    if (shippedMatch) shippedConfigKeys.push(shippedMatch[1]);
}
for (var sck = 0; sck < shippedConfigKeys.length; sck++) {
    expect(configSourceKeys.indexOf(shippedConfigKeys[sck]) !== -1,
        "config.toml contains an unrecognized AppConfig key: " + shippedConfigKeys[sck]);
}

var prefsBlock = markedBlock("launcher/README.md", "launcher-user-prefs-registry");
var prefsDocKeys = [];
var prefsDocRe = /`([A-Za-z][A-Za-z0-9]*)`/g;
var prefsMatch;
while ((prefsMatch = prefsDocRe.exec(prefsBlock)) !== null) prefsDocKeys.push(prefsMatch[1]);
var userPrefsSource = read("launcher/src/Config/UserPrefs.cs");
var prefsSourceKeys = [];
var prefsReadRe = /obj\.Value<[^>]+>\("([A-Za-z][A-Za-z0-9]*)"\)/g;
var prefsWriteRe = /obj\["([A-Za-z][A-Za-z0-9]*)"\]/g;
while ((prefsMatch = prefsReadRe.exec(userPrefsSource)) !== null) prefsSourceKeys.push(prefsMatch[1]);
while ((prefsMatch = prefsWriteRe.exec(userPrefsSource)) !== null) prefsSourceKeys.push(prefsMatch[1]);
expectExactSet("launcher user prefs registry", prefsDocKeys, prefsSourceKeys);

var cliRows = markdownTableRows(markedBlock("launcher/README.md", "launcher-cli-registry"));
var cliDocFlags = cliRows.map(function (row) { return row.key.split(/\s+/)[0]; });
var cliSource = read("launcher/src/Program.cs") + "\n" + read("launcher/src/Audio/AudioQualificationDiagnosticsV1.cs");
var cliSourceFlags = [];
var cliRe = /"(--[a-z0-9][a-z0-9-]*)"/g;
var cliMatch;
while ((cliMatch = cliRe.exec(cliSource)) !== null) cliSourceFlags.push(cliMatch[1]);
expectExactSet("launcher Core/bootstrap CLI registry", cliDocFlags, cliSourceFlags);

var commandRows = markdownTableRows(markedBlock("launcher/README.md", "launcher-bootstrap-command-registry"));
var commandDocIds = commandRows.map(function (row) { return row.key; });
var bootstrapHandlerSource = read("launcher/src/Guardian/BootstrapMessageHandler.cs");
var commandSourceIds = [];
var commandRe = /case\s+"([^"]+)"/g;
var commandMatch;
while ((commandMatch = commandRe.exec(bootstrapHandlerSource)) !== null) commandSourceIds.push(commandMatch[1]);
expectExactSet("launcher Bootstrap cmd registry", commandDocIds, commandSourceIds);

var testRows = markdownTableRows(markedBlock("launcher/README.md", "launcher-test-taxonomy"));
var testDocDirs = testRows.map(function (row) { return row.key.replace(/\/$/, ""); });
var testSourceDirs = ["<root>"];
var testEntries = fs.readdirSync(abs("launcher/tests"));
for (var td = 0; td < testEntries.length; td++) {
    if (testEntries[td] === "bin" || testEntries[td] === "obj") continue;
    if (fs.statSync(abs("launcher/tests/" + testEntries[td])).isDirectory()) testSourceDirs.push(testEntries[td]);
}
expectExactSet("launcher test taxonomy", testDocDirs, testSourceDirs);

var panelRows = markdownTableRows(markedBlock("launcher/README.md", "launcher-panel-registry"));
var panelDocIds = panelRows.map(function (row) { return row.key; });
var panelDocModules = {};
var panelDocMinigames = [];
for (var pr = 0; pr < panelRows.length; pr++) {
    panelDocModules[panelRows[pr].key] = panelRows[pr].cells[2].replace(/^`|`$/g, "");
    if (panelRows[pr].cells[1] === "minigame") panelDocMinigames.push(panelRows[pr].key);
}
var panelRegistrySource = read("launcher/web/modules/panels-lazy-registry.js");
var panelSourceIds = [];
var panelRe = /Panels\.registerLazy\(\s*'([^']+)'\s*,\s*\[([\s\S]*?)\]\s*,\s*noop\s*\)/g;
var panelMatch;
while ((panelMatch = panelRe.exec(panelRegistrySource)) !== null) {
    var deps = [];
    var depRe = /'([^']+)'/g;
    var depMatch;
    while ((depMatch = depRe.exec(panelMatch[2])) !== null) deps.push(depMatch[1]);
    panelSourceIds.push(panelMatch[1]);
    expect(deps.length > 0, "lazy panel has empty dependency closure: " + panelMatch[1]);
    if (deps.length > 0) {
        expect(panelDocModules[panelMatch[1]] === deps[deps.length - 1],
            "launcher panel final module mismatch for " + panelMatch[1] + ": doc=" + panelDocModules[panelMatch[1]] + " source=" + deps[deps.length - 1]);
    }
}
expectExactSet("launcher panel registry", panelDocIds, panelSourceIds);

var minigameDirs = [];
var minigameEntries = fs.readdirSync(abs("launcher/web/modules/minigames"));
for (var mg = 0; mg < minigameEntries.length; mg++) {
    var minigameReadme = "launcher/web/modules/minigames/" + minigameEntries[mg] + "/README.md";
    if (exists(minigameReadme)) minigameDirs.push(minigameEntries[mg]);
}
expectExactSet("launcher minigame registry", panelDocMinigames, minigameDirs);

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
expectContains("agentsDoc/human-care.md", /第一性目标/, "human-care missing first-principles objective");
expectContains("agentsDoc/human-care.md", /无人值守默认/, "human-care missing unattended-by-default section");
expectContains("agentsDoc/human-care.md", /明令禁止的腐化形式/, "human-care missing anti-corruption section");
expectContains("agentsDoc/as2-web-panel-migration.md", /迁移闭环表/, "as2-web-panel-migration missing closure table section");
expectContains("agentsDoc/as2-web-panel-migration.md", /Web cmd.*C# action.*AS2 handler/, "as2-web-panel-migration missing protocol closure columns");
expectContains("agentsDoc/as2-web-panel-migration.md", /ResolvePanelCloseGameCommand/, "as2-web-panel-migration missing close lifecycle guard");
expectContains("agentsDoc/as2-web-panel-migration.md", /数据权威/, "as2-web-panel-migration missing data authority guard");
expectContains("agentsDoc/workbench-ui-system.md", /最后核对代码基线.*commit `[\da-f]{7,40}`/, "workbench-ui-system baseline marker missing");
expectContains("agentsDoc/workbench-ui-system.md", /Visual atlas 与验证矩阵/, "workbench-ui-system missing visual atlas contract");
expectContains("agentsDoc/as2-web-panel-migration.md", /workbench-ui-system\.md/, "as2-web-panel-migration missing workbench UI system link");
expectContains("agentsDoc/testing-guide.md", /workbench-ui-system\.md/, "testing-guide missing workbench UI system link");
expectContains("launcher/README.md", /workbench-ui-system\.md/, "launcher README missing workbench UI system link");

// ---- Stale narrative guards ----

expectNotContains("AGENTS.md", /AS2 \+ Flash CS6 技术栈/, "stale AS2-only summary leaked into AGENTS");
expectNotContains("README.md", /内置Node\.js本地服务器/, "stale Node server description leaked into root README");
expectNotContains("README.md", /Node\.js：14\.0\+/, "stale Node version leaked into root README");
expectNotContains("automation/README.md", /Node\.js 服务器/, "stale Node server language leaked into automation README");
expectNotContains("agentsDoc/coding-standards.md", /\.NET Framework 4\.5\b/, "stale .NET version leaked into coding-standards");

// ---- Worldbuilding stable-section guards ----

var WORLDBUILDING_DOCS = listFiles("docs/worldbuilding", function (rel) {
    return /\.md$/.test(rel);
});
if (exists("docs/reports/worldbuilding-version-history.md")) {
    WORLDBUILDING_DOCS.push("docs/reports/worldbuilding-version-history.md");
}

var stableSectionDefinitions = {};
for (var ws = 0; ws < WORLDBUILDING_DOCS.length; ws++) {
    var worldRel = WORLDBUILDING_DOCS[ws];
    if (worldRel.indexOf("docs/worldbuilding/") !== 0) continue;
    var worldText = read(worldRel);
    var worldLines = worldText.split(/\r?\n/);
    for (var wl = 0; wl < worldLines.length; wl++) {
        if (worldLines[wl].indexOf("稳定节名") === -1) continue;
        var defs = worldLines[wl].match(/`([0-9]{2}·[^`]+)`/g) || [];
        for (var wd = 0; wd < defs.length; wd++) {
            stableSectionDefinitions[defs[wd].slice(1, -1)] = worldRel + ":" + (wl + 1);
        }
    }
}

var STALE_WORLDBUILDING_ANCHORS = [
    /08-1\.5/,
    /1\.5·Oracle查询目标/,
    /08-4\.1\.1/,
    /§\d+\./,
    /:line\s+\d+/i,
    /#L\d+\b/
];

for (var wr = 0; wr < WORLDBUILDING_DOCS.length; wr++) {
    var wbRel = WORLDBUILDING_DOCS[wr];
    var wbText = read(wbRel);
    for (var sa = 0; sa < STALE_WORLDBUILDING_ANCHORS.length; sa++) {
        expect(!STALE_WORLDBUILDING_ANCHORS[sa].test(wbText), "stale worldbuilding line/section anchor leaked [" + wbRel + "]");
    }

    var wbLines = wbText.split(/\r?\n/);
    for (var wli = 0; wli < wbLines.length; wli++) {
        var refs = wbLines[wli].match(/`([0-9]{2}·[^`]+)`/g) || [];
        for (var rf = 0; rf < refs.length; rf++) {
            var refName = refs[rf].slice(1, -1);
            expect(!!stableSectionDefinitions[refName], "worldbuilding stable section reference missing definition: `" + refName + "` [" + wbRel + ":" + (wli + 1) + "]");
        }
    }
}

// ---- Worldbuilding governance gates (T4: 治理护栏自动化) ----
// 把原手维护纪律转成校验门。来源：GPT Pro 治理交付包的 worldbuilding 子检查，
// 移植进本仓真 validator（适配 docs/worldbuilding/ 路径，保留 equip-fn 与全仓校验）。
// 设计依据见 docs/reports/worldbuilding-治理诊断-2026-06-27.md（T1/T2/T4）。

// (G1) 文件名卫生：禁止 #Uxxxx 转义中文名泄漏（zip 往返曾出现）
for (var fn = 0; fn < WORLDBUILDING_DOCS.length; fn++) {
    var fnRel = WORLDBUILDING_DOCS[fn];
    if (fnRel.indexOf("docs/worldbuilding/") !== 0) continue;
    expect(!/#U[0-9A-Fa-f]{4}/.test(fnRel), "worldbuilding 文件名出现 #Uxxxx 转义泄漏，应直写 UTF-8 中文名 [" + fnRel + "]");
}

// (G2) 稳定节名重复定义检测（严格定义行 **稳定节名**：，避开 README 索引行）
var strictDefSeen = {};
for (var sd = 0; sd < WORLDBUILDING_DOCS.length; sd++) {
    var sdRel = WORLDBUILDING_DOCS[sd];
    if (sdRel.indexOf("docs/worldbuilding/") !== 0) continue;
    var sdLines = read(sdRel).split(/\r?\n/);
    for (var sl = 0; sl < sdLines.length; sl++) {
        if (!/^\s*>?\s*\*\*稳定节名\*\*[:：]/.test(sdLines[sl])) continue;
        var sdDefs = sdLines[sl].match(/`([0-9]{2}·[^`]+)`/g) || [];
        for (var sdi = 0; sdi < sdDefs.length; sdi++) {
            var sdName = sdDefs[sdi].slice(1, -1);
            if (strictDefSeen[sdName]) {
                expect(false, "worldbuilding 稳定节名重复定义 `" + sdName + "` [" + sdRel + ":" + (sl + 1) + " / 已见 " + strictDefSeen[sdName] + "]");
            } else {
                strictDefSeen[sdName] = sdRel + ":" + (sl + 1);
            }
        }
    }
}

// (G3) 00 矩阵：双登记镜像区『拟揭露候选』删除后不得回潮（诊断 T1）
var wbMatrix = "docs/worldbuilding/00-结论归属矩阵.md";
if (exists(wbMatrix)) {
    expect(!/(^|\r?\n)##\s+拟揭露候选/.test(read(wbMatrix)), "00 矩阵双登记镜像区『拟揭露候选』不得恢复（改用 当前主假说 + 支线映射 + 20 权威路由）[" + wbMatrix + "]");
}

// (G4) 20 权威表存在 + 必备稳定节名 + 事实域唯一（诊断 T2 单一权威）
var wbAuthority = "docs/worldbuilding/20-权威表.md";
expect(exists(wbAuthority), "缺少世界观权威表 docs/worldbuilding/20-权威表.md（诊断 T2 权威路由枢纽）");
if (exists(wbAuthority)) {
    var authText = read(wbAuthority);
    var reqAnchors = ["20·权威表节", "20·08枢纽节", "20·事实域路由节", "20·边界路由节"];
    for (var qa = 0; qa < reqAnchors.length; qa++) {
        expect(authText.indexOf("`" + reqAnchors[qa] + "`") !== -1, "20 权威表缺少必备稳定节名 `" + reqAnchors[qa] + "`");
    }
    var domainSeen = {};
    var authLines = authText.split(/\r?\n/);
    for (var ad = 0; ad < authLines.length; ad++) {
        var aln = authLines[ad];
        if (aln.charAt(0) !== "|") continue;
        if (/^\|\s*-+/.test(aln)) continue;
        if (aln.indexOf("事实域 | canonical") !== -1) continue;
        var aparts = aln.split("|");
        var acols = aparts.slice(1, aparts.length - 1);
        if (acols.length >= 3) {
            var dom = acols[0].replace(/^\s+|\s+$/g, "");
            if (!dom || dom === "边界") continue;
            if (domainSeen[dom]) {
                expect(false, "20 权威表事实域重复『" + dom + "』(行 " + (ad + 1) + " / 已见 " + domainSeen[dom] + ")，破坏单一权威");
            } else {
                domainSeen[dom] = ad + 1;
            }
        }
    }
}

// (G5) 01-04 分层纪律：框架文档不得承载假说/支线真相整节（诊断 T4）
for (var lp = 0; lp < WORLDBUILDING_DOCS.length; lp++) {
    var lpRel = WORLDBUILDING_DOCS[lp];
    if (lpRel.indexOf("docs/worldbuilding/") !== 0) continue;
    var lpBase = lpRel.replace(/^.*\//, "");
    if (!/^0[1-4]-/.test(lpBase)) continue;
    var lpLines = read(lpRel).split(/\r?\n/);
    for (var ll = 0; ll < lpLines.length; ll++) {
        if (/^##+\s+.*(当前主假说|支线真相|提案级)/.test(lpLines[ll])) {
            expect(false, "框架文档 01-04 不得出现假说/支线真相整节 [" + lpRel + ":" + (ll + 1) + "]");
        }
    }
}

// (G6) README 必须登记 20 权威表
var wbReadme = "docs/worldbuilding/README.md";
if (exists(wbReadme)) {
    expect(read(wbReadme).indexOf("20-权威表.md") !== -1, "worldbuilding README 必须登记 20-权威表.md");
}

// (G7) worldbuilding 内同目录 markdown 链接必须可解析（跳过 http/mailto/../）
for (var lk = 0; lk < WORLDBUILDING_DOCS.length; lk++) {
    var lkRel = WORLDBUILDING_DOCS[lk];
    if (lkRel.indexOf("docs/worldbuilding/") !== 0) continue;
    var lkLines = read(lkRel).split(/\r?\n/);
    for (var ll2 = 0; ll2 < lkLines.length; ll2++) {
        var lkMatches = lkLines[ll2].match(/\]\(([^)#]+\.md)(?:#[^)]*)?\)/g) || [];
        for (var lm = 0; lm < lkMatches.length; lm++) {
            var tgt = lkMatches[lm].match(/\]\(([^)#]+\.md)/);
            if (!tgt) continue;
            var tpath = tgt[1];
            if (/^(https?:|mailto:)/.test(tpath)) continue;
            if (tpath.indexOf("../") === 0) continue;
            expect(exists("docs/worldbuilding/" + tpath), "worldbuilding 本地链接目标不存在: " + tpath + " [" + lkRel + ":" + (ll2 + 1) + "]");
        }
    }
}

// ---- Equipment-function coverage (delegated) ----
// 装备函数三方一致性（目录 ≡ frame37 #include ≡ README 索引）。详见该脚本头注。

var equipCov = cp.spawnSync("node", [abs("tools/validate-equip-fn-coverage.js")], {
    cwd: ROOT,
    stdio: ["ignore", "inherit", "inherit"]
});
if (equipCov.status !== 0) {
    errors.push("装备函数覆盖校验失败：node tools/validate-equip-fn-coverage.js（见上方明细）");
}

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
