#!/usr/bin/env node

// tools/validate-doc-governance.js 的纯文本 / 临时目录 fixture 单测。
// 只用 Node 原生 assert + os.tmpdir() 临时目录；不读真实仓库业务文件、不写存档、不触 runtime。
// 运行：node tools/test-doc-governance.js

var assert = require("node:assert");
var cp = require("node:child_process");
var fs = require("node:fs");
var os = require("node:os");
var path = require("node:path");

var v = require("./validate-doc-governance.js");

var passed = 0;
var failed = 0;
function test(name, fn) {
    try {
        fn();
        passed++;
        console.log("ok - " + name);
    } catch (e) {
        failed++;
        console.error("not ok - " + name);
        console.error(e && e.stack ? e.stack : e);
    }
}

// 在系统临时目录下建一个最小 fixture 仓库，返回 { root, io, cleanup }。
// io 与 live 侧同形：{ exists(absPath), anchors(absPath) }，锚点按路径缓存。
function makeFixtureRepo(files) {
    var root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-doc-governance-"));
    var keys = Object.keys(files);
    for (var i = 0; i < keys.length; i++) {
        var p = path.join(root, keys[i]);
        fs.mkdirSync(path.dirname(p), { recursive: true });
        fs.writeFileSync(p, files[keys[i]]);
    }
    var anchorCache = {};
    var io = {
        exists: function (absPath) { return fs.existsSync(absPath); },
        anchors: function (absPath) {
            if (!Object.prototype.hasOwnProperty.call(anchorCache, absPath)) {
                var t = null;
                try { t = fs.readFileSync(absPath, "utf8"); } catch (e) { /* missing */ }
                anchorCache[absPath] = t === null ? null : v.collectAnchors(t);
            }
            return anchorCache[absPath];
        }
    };
    return {
        root: root,
        io: io,
        check: function (rel) {
            return v.checkMarkdownLinks(root, path.join(root, rel), rel.replace(/\\/g, "/"), fs.readFileSync(path.join(root, rel), "utf8"), io);
        },
        cleanup: function () { fs.rmSync(root, { recursive: true, force: true }); }
    };
}

test("exports are functions and require does not run the CLI", function () {
    var names = ["extractMarkdownLinks", "slugifyHeading", "collectAnchors", "splitLinkTarget",
        "findReadabilityIssues", "exceedsByteBudget", "lineCountOf", "lineBudgetNotice", "diffExactSet",
        "findMustReadCycles", "isMustReadLine", "classifyLinkClause", "extractMustReadTargets",
        "checkMarkdownLinks", "parseGitDiffAddedLines", "linkIssueSeverity", "collectChangedMarkdownLines"];
    for (var i = 0; i < names.length; i++) assert.strictEqual(typeof v[names[i]], "function", names[i]);
});

test("valid inline link + valid fragment pass; invalid fragment fails", function () {
    var repo = makeFixtureRepo({
        "a.md": '# A\n\n<a id="good"></a>\n\n[x](b.md) [y](b.md#good) [z](b.md#missing)\n',
        "b.md": '# B\n\n<a id="good"></a>\n'
    });
    try {
        var issues = repo.check("a.md");
        assert.strictEqual(issues.length, 1);
        assert.ok(/broken fragment #missing/.test(issues[0].message), issues[0].message);
        assert.ok(/\[a\.md:5\]/.test(issues[0].message), issues[0].message);
    } finally { repo.cleanup(); }
});

test("same-file anchors are validated", function () {
    var repo = makeFixtureRepo({
        "a.md": '# A\n\n<a id="self"></a>\n\n[ok](#self) [bad](#nope)\n'
    });
    try {
        var issues = repo.check("a.md");
        assert.strictEqual(issues.length, 1);
        assert.ok(/broken same-file fragment #nope/.test(issues[0].message), issues[0].message);
    } finally { repo.cleanup(); }
});

test("Chinese heading slug and GitHub-style punctuation stripping", function () {
    assert.strictEqual(v.slugifyHeading("持久写与恢复"), "持久写与恢复");
    assert.strictEqual(v.slugifyHeading("2.5 角色构筑会话、默认入口（复核至 2026-07-29 工作树）"),
        "25-角色构筑会话默认入口复核至-2026-07-29-工作树");
    var repo = makeFixtureRepo({
        "a.md": "[x](b.md#持久写与恢复) [y](b.md#持久写)\n",
        "b.md": "## 持久写与恢复\n"
    });
    try {
        var issues = repo.check("a.md");
        assert.strictEqual(issues.length, 1);
        assert.ok(/broken fragment #持久写/.test(issues[0].message), issues[0].message);
    } finally { repo.cleanup(); }
});

test("duplicate headings get -1/-2 suffix anchors", function () {
    var repo = makeFixtureRepo({
        "a.md": "[first](b.md#配置) [second](b.md#配置-1) [third](b.md#配置-2)\n",
        "b.md": "## 配置\n\nx\n\n## 配置\n"
    });
    try {
        var issues = repo.check("a.md");
        assert.strictEqual(issues.length, 1);
        assert.ok(/#配置-2/.test(issues[0].message), issues[0].message);
    } finally { repo.cleanup(); }
});

test("percent-encoded fragment is URL-decoded before matching", function () {
    var repo = makeFixtureRepo({
        "a.md": "[x](b.md#" + encodeURI("持久写与恢复") + ")\n",
        "b.md": "## 持久写与恢复\n"
    });
    try {
        assert.strictEqual(repo.check("a.md").length, 0);
    } finally { repo.cleanup(); }
});

test("reference-style links and definitions are resolved and checked", function () {
    var repo = makeFixtureRepo({
        "a.md": "[x][r] [y][missing]\n\n[r]: b.md\n",
        "b.md": "# B\n"
    });
    try {
        assert.strictEqual(repo.check("a.md").length, 0);
    } finally { repo.cleanup(); }
    var broken = makeFixtureRepo({
        "a.md": "[x][r]\n\n[r]: gone.md\n"
    });
    try {
        var issues = broken.check("a.md");
        // 定义行与引用处各报一次同一目标，两处定位都保留
        assert.strictEqual(issues.length, 2);
        assert.ok(/gone\.md/.test(issues[0].message));
    } finally { broken.cleanup(); }
});

test("links and headings inside code fences are ignored", function () {
    var repo = makeFixtureRepo({
        "a.md": '```\n[x](gone.md)\n## 假标题\n```\n\n[y](#假标题)\n',
        "b.md": "# B\n"
    });
    try {
        var issues = repo.check("a.md");
        // fence 内的假链接不报；fence 内的假标题不产生锚点，故 #假标题 必须报
        assert.strictEqual(issues.length, 1);
        assert.ok(/#假标题/.test(issues[0].message), JSON.stringify(issues));
    } finally { repo.cleanup(); }
});

test("inline code spans are not treated as links", function () {
    var repo = makeFixtureRepo({
        "a.md": "`[x](gone.md)` 与 [y](b.md)\n",
        "b.md": "# B\n"
    });
    try {
        assert.strictEqual(repo.check("a.md").length, 0);
    } finally { repo.cleanup(); }
});

test("relative links escaping the repo root are rejected; in-root .. is allowed", function () {
    var repo = makeFixtureRepo({
        "sub/a.md": "[ok](../b.md) [bad](../../outside.md)\n",
        "b.md": "# B\n",
        "outside.md": "# outside\n"
    });
    try {
        var issues = repo.check("sub/a.md");
        assert.strictEqual(issues.length, 1);
        assert.ok(/escapes repo root/.test(issues[0].message), issues[0].message);
    } finally { repo.cleanup(); }
});

test("external schemes, mailto and bare autolinks are skipped", function () {
    // 提取层原样返回行内目标；scheme 过滤发生在 splitLinkTarget（返回 null）。裸 <url> autolink 不提取。
    var links = v.extractMarkdownLinks(
        "[a](https://example.com/x.md) [b](mailto:x@y.z) <https://bare.example> [c](#local)\n");
    assert.strictEqual(links.length, 3);
    assert.strictEqual(v.splitLinkTarget(links[0].target), null);
    assert.strictEqual(v.splitLinkTarget(links[1].target), null);
    assert.deepStrictEqual(v.splitLinkTarget(links[2].target), { file: "", fragment: "local" });
});

test("query strings are stripped before existence check", function () {
    var repo = makeFixtureRepo({
        "a.md": "[x](b.md?v=1#frag)\n",
        "b.md": '<a id="frag"></a>\n'
    });
    try {
        assert.strictEqual(repo.check("a.md").length, 0);
    } finally { repo.cleanup(); }
});

test("readability: long line and long paragraph reported; boundaries pass", function () {
    var line321 = new Array(322).join("x");
    var line320 = new Array(321).join("x");
    var issues = v.findReadabilityIssues(line320 + "\n\n" + line321 + "\n", 320, 2048);
    assert.strictEqual(issues.length, 1);
    assert.strictEqual(issues[0].kind, "line");
    assert.strictEqual(issues[0].line, 3);
    // 段落字节：两行各 1100 字节 = 2201（含换行）> 2048；恰 2048 字节段落通过
    var longPara = new Array(1101).join("y") + "\n" + new Array(1101).join("y");
    var paraIssues = v.findReadabilityIssues(longPara, 320, 2048);
    assert.strictEqual(paraIssues.filter(function (i) { return i.kind === "paragraph"; }).length, 1);
    // 段落恰 2048 字节（1024 + 1 换行 + 1023）通过；超过才报
    var exact = new Array(1025).join("z") + "\n" + new Array(1024).join("z");
    assert.strictEqual(Buffer.byteLength(exact, "utf8"), 2048);
    assert.strictEqual(v.findReadabilityIssues(exact, 4096, 2048).length, 0);
});

test("byte budget boundary: exact budget passes, one byte over fails", function () {
    assert.strictEqual(v.exceedsByteBudget(12288, 12288), false);
    assert.strictEqual(v.exceedsByteBudget(12289, 12288), true);
});

test("lineCountOf matches legacy line-count semantics", function () {
    assert.strictEqual(v.lineCountOf(""), 0);
    assert.strictEqual(v.lineCountOf("a"), 1);
    assert.strictEqual(v.lineCountOf("a\n"), 1);
    assert.strictEqual(v.lineCountOf("a\nb\n"), 2);
});

test("background cross-links do not count as must-read edges; strong directives do", function () {
    var background = "详见 [b](b.md)；另见 [c](c.md)。\n参考 [d](d.md) 与背景 [e](e.md) 见 [f](f.md)。\n";
    assert.strictEqual(v.extractMustReadTargets(background).length, 0);
    var strong = "先读 [b](b.md)，必读 [c](c.md#x)；先 [d](d.md)。\n";
    var targets = v.extractMustReadTargets(strong).map(function (t) { return t.target; });
    assert.deepStrictEqual(targets.sort(), ["b.md", "c.md", "d.md"]);
});

test("findMustReadCycles: acyclic graph passes, must-read cycle is detected", function () {
    assert.deepStrictEqual(v.findMustReadCycles([["AGENTS.md", "agentsDoc/testing-guide.md"],
        ["agentsDoc/testing-guide.md", "agentsDoc/data-schemas.md"],
        ["CLAUDE.md", "AGENTS.md"]]), []);
    var cycles = v.findMustReadCycles([["a", "b"], ["b", "a"]]);
    assert.strictEqual(cycles.length, 1);
    assert.deepStrictEqual(cycles[0], ["a", "b"]);
    // 自环也是循环
    assert.strictEqual(v.findMustReadCycles([["a", "a"]]).length, 1);
});

test("must-read edges from entry texts form a cycle only via strong directives", function () {
    var repo = makeFixtureRepo({
        "A.md": "先读 [B](B.md) 后施工。\n详见 [C](C.md)。\n",
        "B.md": "本节依赖 [A](A.md)，详见即可。\n先读 [C](C.md)。\n",
        "C.md": "背景互链：[A](A.md)。\n"
    });
    try {
        var edges = [];
        ["A.md", "B.md", "C.md"].forEach(function (rel) {
            var targets = v.extractMustReadTargets(fs.readFileSync(path.join(repo.root, rel), "utf8"));
            targets.forEach(function (t) {
                edges.push([rel, path.relative(repo.root, path.resolve(repo.root, t.target)).replace(/\\/g, "/")]);
            });
        });
        // A→B、B→C；C 的「详见/背景」边不计入，无环
        assert.deepStrictEqual(v.findMustReadCycles(edges), []);
        // 把 C 改成强指令回链后应检出环
        var edges2 = edges.concat([["C.md", "A.md"]]);
        assert.strictEqual(v.findMustReadCycles(edges2).length, 1);
    } finally { repo.cleanup(); }
});

test("diffExactSet reports missing and unexpected entries", function () {
    var diff = v.diffExactSet(["a", "b"], ["a", "b", "c"]);
    assert.deepStrictEqual(diff.missing, ["c"]);
    assert.deepStrictEqual(diff.unexpected, []);
    var diff2 = v.diffExactSet(["a", "b", "x"], ["a", "b"]);
    assert.deepStrictEqual(diff2.unexpected, ["x"]);
    assert.deepStrictEqual(v.diffExactSet(["b", "a"], ["a", "b"]), { missing: [], unexpected: [] });
});

test("legacy machine gates still present in validator source", function () {
    var src = fs.readFileSync(path.join(__dirname, "validate-doc-governance.js"), "utf8");
    var signatures = [
        "runtime-release-consensus.json",      // runtime consensus/manifest 一致性
        "cf7-runtime-manifest.tsv",
        "launcher-config-registry",            // launcher 各 registry 精确集合
        "launcher-user-prefs-registry",
        "launcher-cli-registry",
        "launcher-bootstrap-command-registry",
        "launcher-test-taxonomy",
        "launcher-panel-registry",
        "CORE_EARLY_EXIT_GRACE_MS",            // bootstrap 早退观察窗
        "validate-equip-fn-coverage",          // 装备 coverage delegated gate
        "稳定节名",                            // worldbuilding guards
        "validateLocalMarkdownLinks",          // 既有本地链接门（共存）
        "markedBlock",
        "expectExactSet"
    ];
    for (var i = 0; i < signatures.length; i++) {
        assert.ok(src.indexOf(signatures[i]) !== -1, "validator source still contains: " + signatures[i]);
    }
});

// ---- F1：新增/改动行阻断（git diff 识别） ----

test("F1 parseGitDiffAddedLines maps new-side line numbers", function () {
    var diff = [
        "diff --git a/docs/x.md b/docs/x.md",
        "index 1111111..2222222 100644",
        "--- a/docs/x.md",
        "+++ b/docs/x.md",
        "@@ -10,2 +10,3 @@",
        "-old ten",
        "-old eleven",
        "+new ten",
        "+new eleven",
        "+new twelve",
        "@@ -30,0 +32,1 @@",
        "+inserted",
        "diff --git a/docs/new.md b/docs/new.md",
        "new file mode 100644",
        "--- /dev/null",
        "+++ b/docs/new.md",
        "@@ -0,0 +1,2 @@",
        "+l1",
        "+l2",
        "diff --git a/docs/gone.md b/docs/gone.md",
        "deleted file mode 100644",
        "--- a/docs/gone.md",
        "+++ /dev/null",
        "@@ -1,2 +0,0 @@",
        "-bye",
        "-bye2",
        ""
    ].join("\n");
    var changed = v.parseGitDiffAddedLines(diff);
    assert.deepStrictEqual(Object.keys(changed["docs/x.md"]).sort(), ["10", "11", "12", "32"]);
    assert.deepStrictEqual(Object.keys(changed["docs/new.md"]).sort(), ["1", "2"]);
    assert.ok(!changed["docs/gone.md"], "deleted file contributes no new-side lines");
});

test("F1 linkIssueSeverity: block list / new line / unchanged line / untracked / degraded", function () {
    var changed = { "docs/x.md": { 11: true } };
    var untracked = { "docs/u.md": true };
    // 名单内文件任意行一律 error
    assert.strictEqual(v.linkIssueSeverity("AGENTS.md", 1, { "AGENTS.md": true }, changed, untracked), "error");
    // 名单外新增/改动行 → error
    assert.strictEqual(v.linkIssueSeverity("docs/x.md", 11, {}, changed, untracked), "error");
    // 名单外未改动行 → warn
    assert.strictEqual(v.linkIssueSeverity("docs/x.md", 99, {}, changed, untracked), "warn");
    // 未跟踪文件全部行算新增
    assert.strictEqual(v.linkIssueSeverity("docs/u.md", 1, {}, changed, untracked), "error");
    // git 降级（null）时名单外只 warn
    assert.strictEqual(v.linkIssueSeverity("docs/x.md", 11, {}, null, null), "warn");
});

test("F1 real git pipeline in a temp repo (skipped when git unavailable)", function () {
    var root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-doc-governance-git-"));
    function git(args) {
        return cp.spawnSync("git", args, { cwd: root, stdio: ["ignore", "pipe", "ignore"] });
    }
    try {
        if (git(["--version"]).status !== 0) {
            console.log("  (skipped: git unavailable)");
            return;
        }
        assert.strictEqual(git(["init", "--quiet"]).status, 0);
        fs.writeFileSync(path.join(root, "a.md"), "# A\n\n[x](b.md)\n");
        fs.writeFileSync(path.join(root, "b.md"), "# B\n");
        assert.strictEqual(git(["add", "-A"]).status, 0);
        assert.strictEqual(git(["-c", "user.email=fixture@example.invalid", "-c", "user.name=fixture",
            "commit", "--quiet", "-m", "init"]).status, 0);
        fs.appendFileSync(path.join(root, "a.md"), "\n[new](gone.md)\n");
        fs.writeFileSync(path.join(root, "u.md"), "[x](gone2.md)\n");
        var info = v.collectChangedMarkdownLines(root);
        assert.ok(info, "collectChangedMarkdownLines returns info");
        assert.ok(info.changed["a.md"] && info.changed["a.md"][5],
            "appended line 5 recorded: " + JSON.stringify(info.changed));
        assert.ok(!info.changed["b.md"], "untouched file has no added lines");
        assert.strictEqual(info.untracked["u.md"], true);
        assert.strictEqual(v.linkIssueSeverity("a.md", 5, {}, info.changed, info.untracked), "error");
        assert.strictEqual(v.linkIssueSeverity("a.md", 3, {}, info.changed, info.untracked), "warn");
    } finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

// ---- F2：分句级强弱指令 ----

test("F2 mixed strong/weak line: acceptance counterexample now detects the cycle", function () {
    // 验收反例：AGENTS.md 同行先读 + 参考；旧整行判定吞掉必读边，新分句判定必须保留
    var agentsText = "先读 [说明](README.md)，参考 [案例](docs/history.md)\n";
    var targets = v.extractMustReadTargets(agentsText).map(function (t) { return t.target; });
    assert.deepStrictEqual(targets, ["README.md"]);
    var edges = [["AGENTS.md", "README.md"]];
    v.extractMustReadTargets("先读 [规则](AGENTS.md)\n").forEach(function (t) {
        edges.push(["README.md", t.target]);
    });
    var cycles = v.findMustReadCycles(edges);
    assert.strictEqual(cycles.length, 1);
    assert.deepStrictEqual(cycles[0], ["AGENTS.md", "README.md"]);
});

test("F2 clause order independence and tone inheritance", function () {
    // 语序无关：弱词子句在前不吞后面的强指令链接
    var t1 = v.extractMustReadTargets("参考 [A](a.md)，先读 [B](b.md)\n").map(function (t) { return t.target; });
    assert.deepStrictEqual(t1, ["b.md"]);
    // 无词子句延续该行最近的前向强语气
    var t2 = v.extractMustReadTargets("先读 [A](a.md)；[C](c.md) 同样处理\n").map(function (t) { return t.target; });
    assert.deepStrictEqual(t2.sort(), ["a.md", "c.md"]);
    // 行首无语气按默认（背景），导航回链不报
    assert.deepStrictEqual(v.extractMustReadTargets("[A](a.md) 与 [B](b.md) 都只是导航回链\n"), []);
    // 整行弱词互指仍是合法背景互链
    assert.deepStrictEqual(v.extractMustReadTargets("详见 [A](a.md)，另见 [B](b.md)\n"), []);
});

// ---- F3：行数预算降级为提示 ----

test("F3 line budget is notice-level while byte budget stays hard", function () {
    assert.strictEqual(v.lineBudgetNotice(150, 150), null);
    var notice = v.lineBudgetNotice(151, 150);
    assert.ok(notice && notice.indexOf("line budget notice") === 0, notice);
    assert.ok(/压行/.test(notice), notice);
    // 字节预算保持硬门：恰等于通过、超 1 字节失败
    assert.strictEqual(v.exceedsByteBudget(20480, 20480), false);
    assert.strictEqual(v.exceedsByteBudget(20481, 20480), true);
});

// ---- M1：显式活跃记忆范围；历史/topic 不进入新增硬门 ----

test("M1 only the explicit active memory is scanned; historical and private trees stay excluded", function () {
    var repo = makeFixtureRepo({
        "AGENTS.md": "# Router\n",
        ".workbuddy/memory/MEMORY.md": "[rules](../../AGENTS.md)\n",
        ".workbuddy/memory/2026-10-27.md": "[old](gone.md)\n",
        ".workbuddy/memory/topics/history.md": "[old](gone.md)\n",
        ".workbuddy/other/MEMORY.md": "[old](gone.md)\n",
        ".workbuddy-ai/session.md": "[old](gone.md)\n",
        "docs/history.md": "# Existing public history\n"
    });
    try {
        assert.deepStrictEqual(v.listRepoMarkdownFiles(repo.root), [
            ".workbuddy/memory/MEMORY.md", "AGENTS.md", "docs/history.md"
        ]);
    } finally { repo.cleanup(); }
});

test("M1 active memory links and fragments are hard errors even on unchanged lines", function () {
    var rel = ".workbuddy/memory/MEMORY.md";
    var repo = makeFixtureRepo({
        ".workbuddy/memory/MEMORY.md": "[good](../../AGENTS.md#rules)\n[bad](../../AGENTS.md#gone)\n[missing](gone.md)\n",
        "AGENTS.md": "# Rules\n"
    });
    try {
        var issues = repo.check(rel);
        assert.strictEqual(issues.length, 2);
        issues.forEach(function (issue) {
            assert.strictEqual(v.linkIssueSeverity(rel, issue.line, v.LINK_BLOCK_FILES, {}, {}), "error");
        });
        assert.strictEqual(v.LINK_BLOCK_FILES[".workbuddy/memory/topics/history.md"], undefined);
    } finally { repo.cleanup(); }
});

test("M1 untracked active entry is included by real git enumeration; its sibling history is not", function () {
    var root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-active-memory-git-"));
    function git(args) { return cp.spawnSync("git", args, { cwd: root, stdio: ["ignore", "pipe", "ignore"] }); }
    try {
        if (git(["--version"]).status !== 0) { console.log("  (skipped: git unavailable)"); return; }
        assert.strictEqual(git(["init", "--quiet"]).status, 0);
        fs.writeFileSync(path.join(root, "AGENTS.md"), "# Router\n");
        assert.strictEqual(git(["add", "AGENTS.md"]).status, 0);
        assert.strictEqual(git(["-c", "user.email=fixture@example.invalid", "-c", "user.name=fixture",
            "commit", "--quiet", "-m", "init"]).status, 0);
        fs.mkdirSync(path.join(root, ".workbuddy/memory"), { recursive: true });
        fs.writeFileSync(path.join(root, ".workbuddy/memory/MEMORY.md"), "# Router\n");
        fs.writeFileSync(path.join(root, ".workbuddy/memory/2026-10-27.md"), "# History\n");
        var info = v.collectChangedMarkdownLines(root);
        assert.strictEqual(info.untracked[".workbuddy/memory/MEMORY.md"], true);
        assert.strictEqual(info.untracked[".workbuddy/memory/2026-10-27.md"], undefined);
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

// ---- M2：target 来自现役 resolver；只核对可证明的字面别名 ----

var compileResolverFixture = [
    "switch -Regex ($Target.ToLower()) {",
    "    '^(test|testloader)$' { $targetPath = 'test.xfl' }",
    "    '^(publish|asloader)$' { $targetPath = 'asLoader.xfl' }",
    "    '^(main|mainfile|empire)$' { $targetPath = 'main.xfl' }",
    "    default { $targetPath = $Target }",
    "}"
].join("\n");
var activeMemoryRel = ".workbuddy/memory/MEMORY.md";

test("M2 reads aliases from the resolver and follows a newly added source alias", function () {
    assert.deepStrictEqual(v.parseCompileTargetAliases(compileResolverFixture),
        ["asloader", "empire", "main", "mainfile", "publish", "test", "testloader"]);
    var changed = compileResolverFixture.replace("test|testloader", "test|testloader|focused");
    assert.deepStrictEqual(v.checkActiveMemoryTargets(activeMemoryRel,
        "`scripts/compile_test.ps1 -Target focused`", changed), []);
});

test("M2 accepts current aliases, case-insensitive quoted values and colon syntax", function () {
    var text = "`scripts/compile_test.ps1 -Target PUBLISH`\n" +
        "`scripts/compile_test.ps1 -target:'TestLoader'`\n" +
        '`scripts/compile_test.ps1 -Target "empire"`\n';
    assert.strictEqual(v.collectLiteralCompileTargets(text).length, 3);
    assert.deepStrictEqual(v.checkActiveMemoryTargets(activeMemoryRel, text, compileResolverFixture), []);
});

test("M2 rejects known obsolete levels in the original Target table shape", function () {
    var text = "## Compile\n`powershell -File scripts/compile_test.ps1 -Target <target>`\n\n" +
        "| Changes | Target |\n| --- | --- |\n| scripts | `publish` |\n| UI | `levels` |\n";
    var issues = v.checkActiveMemoryTargets(activeMemoryRel, text, compileResolverFixture)
        .filter(function (issue) { return issue.severity === "error"; });
    assert.strictEqual(issues.length, 1);
    assert.strictEqual(issues[0].line, 7);
    assert.ok(/unsupported literal compile target alias: levels/.test(issues[0].message));
});

test("M2 fenced current commands and multiline commands are checked", function () {
    var text = '```powershell\nscripts/compile_test.ps1 -Target levels\n```\n\n' +
        '```powershell\nscripts/compile_test.ps1 `\n  -Target obsolete\n```\n';
    var issues = v.checkActiveMemoryTargets(activeMemoryRel, text, compileResolverFixture);
    assert.deepStrictEqual(issues.map(function (i) { return i.line; }), [2, 7]);
});

test("M2 quoted historical mistakes, sibling topics and unrelated Target parameters are allowed", function () {
    var history = '> Historical command, not a current instruction:\n> `scripts/compile_test.ps1 -Target levels`\n';
    assert.deepStrictEqual(v.checkActiveMemoryTargets(activeMemoryRel, history, compileResolverFixture), []);
    assert.deepStrictEqual(v.checkActiveMemoryTargets(".workbuddy/memory/topics/old.md",
        "scripts/compile_test.ps1 -Target levels", compileResolverFixture), []);
    var other = "build.ps1 -Target custom\n| Change | Target |\n| --- | --- |\n| another tool | custom |\n";
    assert.deepStrictEqual(v.checkActiveMemoryTargets(activeMemoryRel, other, compileResolverFixture), []);
    var mixed = "```powershell\nscripts/compile_test.ps1 -Target publish\nbuild.ps1 -Target custom\n```\n";
    assert.deepStrictEqual(v.checkActiveMemoryTargets(activeMemoryRel, mixed, compileResolverFixture), []);
    var sameLine = "build.ps1 -Target before; scripts/compile_test.ps1 -Target publish; build.ps1 -Target after";
    var uncertain = v.checkActiveMemoryTargets(activeMemoryRel, sameLine, compileResolverFixture);
    assert.ok(uncertain.length > 0);
    assert.ok(uncertain.every(function (issue) { return issue.severity === "warn"; }));
});

test("M2 explicit XFL paths, variables, placeholders and parameter abbreviations are outside alias proof", function () {
    var text = 'scripts/compile_test.ps1 -Target "flashswf/arts/a/a.xfl"\n' +
        'scripts/compile_test.ps1 -Target "C:\\work\\a.fla"\n' +
        'scripts/compile_test.ps1 -Target $chosen\n' +
        'scripts/compile_test.ps1 -Target <target>\n' +
        'scripts/compile_test.ps1 -Tar levels\n';
    assert.deepStrictEqual(v.collectLiteralCompileTargets(text), []);
    var notices = v.checkActiveMemoryTargets(activeMemoryRel, text, compileResolverFixture);
    assert.strictEqual(notices.length, 5);
    assert.ok(notices.every(function (issue) { return issue.severity === "warn"; }));
});

test("M2 CRLF and a continued parameter value retain the exact directive line", function () {
    var text = "```powershell\r\nscripts/compile_test.ps1 `\r\n  -Target `\r\n  levels\r\n```\r\n";
    var issues = v.checkActiveMemoryTargets(activeMemoryRel, text, compileResolverFixture);
    assert.strictEqual(issues.length, 1);
    assert.strictEqual(issues[0].line, 3);
    var unindented = text.replace("  -Target", "-Target");
    assert.strictEqual(v.checkActiveMemoryTargets(activeMemoryRel, unindented, compileResolverFixture)[0].line, 3);
});

test("M2 resolver shape changes are reported as unverifiable, never as invented alias facts", function () {
    var changed = compileResolverFixture.replace("'^(test|testloader)$'", "'test.*'");
    assert.strictEqual(v.parseCompileTargetAliases(changed), null);
    var issues = v.checkActiveMemoryTargets(activeMemoryRel,
        "scripts/compile_test.ps1 -Target test", changed);
    assert.strictEqual(issues.length, 1);
    assert.ok(/cannot verify/.test(issues[0].message));
    assert.strictEqual(issues[0].severity, "warn");
    assert.deepStrictEqual(v.checkActiveMemoryTargets(activeMemoryRel, "[compile](../../compile.md)", changed), []);
    var bareCase = compileResolverFixture.replace("    default", "    levels { $targetPath = 'levels.xfl' }\n    default");
    assert.strictEqual(v.parseCompileTargetAliases(bareCase), null);
    var bareIssues = v.checkActiveMemoryTargets(activeMemoryRel, "scripts/compile_test.ps1 -Target levels", bareCase);
    assert.ok(bareIssues.length > 0);
    assert.ok(bareIssues.every(function (issue) { return issue.severity === "warn"; }));
});

// 独立审阅发现的误报回归：语法不明只能 warn，不能扩大为语义硬门。
test("M3 independent inline commands and prose mentions never share their arguments", function () {
    var text = '`scripts/compile_test.ps1 -Target publish` 与 `build.ps1 -Target custom`\n' +
        '`scripts/compile_test.ps1` 是编译器。另一个工具用 `build.ps1 -Target custom`。\n';
    assert.deepStrictEqual(v.checkActiveMemoryTargets(activeMemoryRel, text, compileResolverFixture), []);
});

test("M3 shell and HTML comments are not current target declarations", function () {
    var text = '```powershell\nscripts/compile_test.ps1 -Target publish # old -Target levels is invalid\n' +
        '# scripts/compile_test.ps1 -Target levels\n' +
        'scripts/compile_test.ps1 -Target publish -VerifySwf "path -Target levels"\n```\n' +
        '<!-- scripts/compile_test.ps1 -Target levels -->\n' +
        '<!--\nscripts/compile_test.ps1 -Target levels\n-->\n';
    assert.deepStrictEqual(v.checkActiveMemoryTargets(activeMemoryRel, text, compileResolverFixture), []);
    var tokenHash = v.checkActiveMemoryTargets(activeMemoryRel,
        '`scripts/compile_test.ps1 -Target levels#part`', compileResolverFixture);
    assert.ok(tokenHash.length > 0);
    assert.ok(tokenHash.every(function (issue) { return issue.severity === "warn"; }));
});

test("M3 Target tables follow the nearest explicit tool; ambiguous context only warns", function () {
    var before = '## Tools\n`compile_test.ps1 -Target publish`\n\n';
    var table = '| Parameter | Target |\n| --- | --- |\n| build target | custom |\n';
    assert.deepStrictEqual(v.checkActiveMemoryTargets(activeMemoryRel,
        before + '`build.ps1` 的参数：\n' + table, compileResolverFixture), []);
    var issues = v.checkActiveMemoryTargets(activeMemoryRel,
        before + '接下来是另一种工具的参数。\n' + table, compileResolverFixture);
    assert.ok(issues.length > 0);
    assert.ok(issues.every(function (issue) { return issue.severity === "warn"; }));
});

test("M3 complex shell expressions and invocation options are review warnings", function () {
    var inputs = [
        '`scripts/compile_test.ps1 -Target publish; build.ps1 -Target custom`',
        '`powershell -Command scripts/compile_test.ps1 -Target levels`',
        '`scripts/compile_test.ps1 -Target $selected`'
    ];
    inputs.forEach(function (text) {
        var issues = v.checkActiveMemoryTargets(activeMemoryRel, text, compileResolverFixture);
        assert.ok(issues.length > 0, text);
        assert.ok(issues.every(function (issue) { return issue.severity === "warn"; }), text);
    });
});

test("M3 the real MEMORY compile preamble keeps a suffix mention from stealing its table context", function () {
    // 固定基线 MEMORY 原文摘录：独立的 `.sh` 是扩展名提示，不是第二个脚本。
    var text = '## 编译（Flash CS6 自动化）\n\n' +
        '计划任务拉起 `Flash.exe` 跑 JSFL（`publish()`/`testMovie()`）；CS6 仍在链路上。唯一入口：\n' +
        '`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target <目标> -TimeoutSeconds 180`（Git Bash 用 `.sh`），别单独跑 `compile_action.jsfl`。\n\n' +
        '| 改动位置 | Target |\n| --- | --- |\n| `scripts/类定义/` | `publish` |\n| `flashswf/UI levels` | `levels` |\n';
    var errors = v.checkActiveMemoryTargets(activeMemoryRel, text, compileResolverFixture)
        .filter(function (issue) { return issue.severity === "error"; });
    assert.strictEqual(errors.length, 1);
    assert.strictEqual(errors[0].line, 9);
    assert.ok(/levels/.test(errors[0].message));
});

if (failed) {
    console.error("[test-doc-governance] failed: " + failed + " failed, " + passed + " passed");
    process.exit(1);
}
console.log("[test-doc-governance] ok: " + passed + " passed");
