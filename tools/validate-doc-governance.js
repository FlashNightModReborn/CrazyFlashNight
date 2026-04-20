#!/usr/bin/env node

var fs = require("fs");
var path = require("path");

var ROOT = path.resolve(__dirname, "..");
var errors = [];

function relPath(p) {
    return p.split(path.sep).join("/");
}

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

expectContains("AGENTS.md", /最后核对代码基线.*commit `[\da-f]{7,40}`/, "AGENTS baseline missing");
expectContains("AGENTS.md", /Context Packs（按任务最小加载，最后核对 commit `[\da-f]{7,40}`）/, "AGENTS Context Packs baseline missing");
expectContains("README.md", /最后核对代码基线.*commit `[\da-f]{7,40}`/, "root README baseline missing");
expectContains("agentsDoc/architecture.md", /最后核对代码基线.*commit `[\da-f]{7,40}`/, "architecture baseline missing");
expectContains("agentsDoc/testing-guide.md", /最后核对代码基线.*commit `[\da-f]{7,40}`/, "testing-guide baseline missing");
expectContains("agentsDoc/coding-standards.md", /最后核对代码基线.*commit `[\da-f]{7,40}`/, "coding-standards baseline missing");
expectContains("agentsDoc/documentation-governance.md", /最后核对代码基线.*commit `[\da-f]{7,40}`/, "documentation-governance baseline missing");
expectContains("docs/tech-stack-rationalization.md", /最后核对代码基线.*commit `[\da-f]{7,40}`/, "tech-stack baseline missing");
expectContains("launcher/README.md", /文档角色/, "launcher README role note missing");
expectContains("launcher/README.md", /commit `[\da-f]{7,40}`/, "launcher README commit baseline missing");

expectContains("docs/tech-stack-rationalization.md", /## 2\. 三段式矩阵/, "tech-stack matrix heading missing");
expectContains("docs/tech-stack-rationalization.md", /### Hard Keep/, "Hard Keep section missing");
expectContains("docs/tech-stack-rationalization.md", /### Contain/, "Contain section missing");
expectContains("docs/tech-stack-rationalization.md", /### Retire \/ Stop Expanding/, "Retire section missing");

expectContains("agentsDoc/testing-guide.md", /compile_test\.ps1/, "testing-guide missing Flash smoke command");
expectContains("agentsDoc/testing-guide.md", /launcher\/build\.ps1/, "testing-guide missing launcher build command");
expectContains("agentsDoc/testing-guide.md", /--bus-only/, "testing-guide missing bus-only");
expectContains("agentsDoc/testing-guide.md", /run-minigame-qa\.js/, "testing-guide missing minigame QA");
expectContains("agentsDoc/testing-guide.md", /validate-doc-governance\.js/, "testing-guide missing doc governance validation");

expectContains("agentsDoc/self-optimization.md", /validate-doc-governance\.js/, "self-optimization missing governance validation");
expectContains("agentsDoc/documentation-governance.md", /维护触发器/, "documentation-governance missing trigger section");

expectNotContains("AGENTS.md", /AS2 \+ Flash CS6 技术栈/, "stale AS2-only summary leaked into AGENTS");
expectNotContains("README.md", /内置Node\.js本地服务器/, "stale Node server description leaked into root README");
expectNotContains("README.md", /Node\.js：14\.0\+/, "stale Node version leaked into root README");
expectNotContains("automation/README.md", /Node\.js 服务器/, "stale Node server language leaked into automation README");
expectNotContains("agentsDoc/coding-standards.md", /\.NET Framework 4\.5\b/, "stale .NET version leaked into coding-standards");

if (errors.length) {
    console.error("[doc-governance] failed");
    for (var k = 0; k < errors.length; k++) {
        console.error(" - " + errors[k]);
    }
    process.exit(1);
}

console.log("[doc-governance] ok");
