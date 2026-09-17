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
    var diff = diffExactSet(actual, expected);
    expect(
        diff.missing.length === 0 && diff.unexpected.length === 0,
        label + " exact-set mismatch; missing=[" + diff.missing.join(", ") + "] unexpected=[" + diff.unexpected.join(", ") + "]");
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

// ---- Pure text helpers (exported for tools/test-doc-governance.js fixtures) ----
// 以下函数不读文件系统、不写 errors/warnings；live 侧在 main() 内包一层 IO 适配。

function blankInlineCode(line) {
    return line.replace(/`[^`]*`/g, function (m) {
        return new Array(m.length + 1).join(" ");
    });
}

function eachNonFenceLine(text, cb) {
    var lines = text.split(/\r?\n/);
    var inFence = false;
    var fenceChar = "";
    for (var i = 0; i < lines.length; i++) {
        var marker = /^[ ]{0,3}(```+|~~~+)/.exec(lines[i]);
        if (marker) {
            if (!inFence) {
                inFence = true;
                fenceChar = marker[1].charAt(0);
            } else if (marker[1].charAt(0) === fenceChar) {
                inFence = false;
            }
            continue;
        }
        if (!inFence) cb(lines[i], i + 1);
    }
}

function normalizeRefLabel(label) {
    return label.replace(/\s+/g, " ").trim().toLowerCase();
}

// 提取行内 [t](u)、引用式 [t][r]/[t][] 与引用定义 [r]: u；裸 <url> autolink 不算。
// 返回 [{ target, line, column, kind }]，line 为 1 起始，column 为行内 0 起始偏移；代码围栏与行内代码段内容不计。
function extractMarkdownLinks(text) {
    var refDefs = {};
    eachNonFenceLine(text, function (line, lineNo) {
        var def = /^[ ]{0,3}\[([^\]]+)\]:\s*<?([^<>\s]+)>?/.exec(line);
        if (def) {
            var label = normalizeRefLabel(def[1]);
            if (!refDefs[label]) refDefs[label] = { target: def[2], line: lineNo };
        }
    });
    var links = [];
    eachNonFenceLine(text, function (line, lineNo) {
        var clean = blankInlineCode(line);
        var def = /^[ ]{0,3}\[([^\]]+)\]:\s*<?([^<>\s]+)>?/.exec(clean);
        if (def) links.push({ target: def[2], line: lineNo, column: def.index, kind: "definition" });
        var m;
        var inlineRe = /\[[^\]]*\]\(\s*<?([^<>\s)]+)>?[^)]*\)/g;
        while ((m = inlineRe.exec(clean)) !== null) {
            links.push({ target: m[1], line: lineNo, column: m.index, kind: "inline" });
        }
        var refRe = /\[([^\]]*)\]\[([^\]]*)\]/g;
        while ((m = refRe.exec(clean)) !== null) {
            var label = normalizeRefLabel(m[2] || m[1]);
            if (refDefs[label]) links.push({ target: refDefs[label].target, line: lineNo, column: m.index, kind: "reference" });
        }
    });
    return links;
}

// GitHub 风格标题 slug：小写化、去标点、空白转连字符、CJK 字符保留。
function slugifyHeading(raw) {
    var t = raw;
    t = t.replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1");
    t = t.replace(/\[([^\]]*)\]\([^)]*\)/g, "$1");
    t = t.replace(/\[([^\]]*)\]\[[^\]]*\]/g, "$1");
    t = t.replace(/`([^`]*)`/g, "$1");
    t = t.replace(/<[^>]*>/g, "");
    t = t.replace(/[*_~]/g, "");
    t = t.trim().toLowerCase();
    t = t.replace(/[^\p{L}\p{N}_\-\s]/gu, "");
    t = t.replace(/\s+/g, "-");
    return t;
}

// 目标文件可用锚点集合：显式 <a id|name="..."> 加 GitHub 风格标题 slug（重复标题依次追加 -1/-2）。
// 返回小写锚点名 → true 的 map。
function collectAnchors(text) {
    var anchors = {};
    var slugCounts = {};
    eachNonFenceLine(text, function (line) {
        var anchorRe = /<a\s+(?:[^>]*?\s)?(?:id|name)\s*=\s*(?:"([^"]*)"|'([^']*)')/gi;
        var m;
        while ((m = anchorRe.exec(line)) !== null) {
            anchors[(m[1] || m[2]).toLowerCase()] = true;
        }
        var heading = /^[ ]{0,3}#{1,6}\s+(.*?)\s*#*\s*$/.exec(line);
        if (heading) {
            var slug = slugifyHeading(heading[1]);
            if (!slug) return;
            if (slugCounts[slug] === undefined) {
                slugCounts[slug] = 0;
                anchors[slug] = true;
            } else {
                slugCounts[slug]++;
                anchors[slug + "-" + slugCounts[slug]] = true;
            }
        }
    });
    return anchors;
}

// 拆链接目标为 { file, fragment }；外部 scheme（http/https/mailto 等）与协议相对目标返回 null。
// file 与 fragment 都做 URL decode（失败则保留原样，由后续存在性/锚点检查报告）。
function splitLinkTarget(raw) {
    var target = raw.trim();
    if (!target) return { file: "", fragment: "" };
    if (/^[a-z][a-z0-9+.-]*:/i.test(target)) return null;
    if (/^\/\//.test(target)) return null;
    var fragment = "";
    var hashIdx = target.indexOf("#");
    if (hashIdx !== -1) {
        fragment = target.slice(hashIdx + 1);
        target = target.slice(0, hashIdx);
    }
    var queryIdx = target.indexOf("?");
    if (queryIdx !== -1) target = target.slice(0, queryIdx);
    try { target = decodeURIComponent(target); } catch (e) { /* existence check reports it */ }
    try { fragment = decodeURIComponent(fragment); } catch (e) { /* anchor check reports it */ }
    return { file: target, fragment: fragment };
}

// 可读性规则：单行字符数（maxLineChars）与连续非空行段落的 UTF-8 字节数（maxParagraphBytes）。
// 返回 [{ kind: "line"|"paragraph", line, size, limit }]。
function findReadabilityIssues(text, maxLineChars, maxParagraphBytes) {
    var issues = [];
    var lines = text.split(/\r?\n/);
    var paraStart = -1;
    var paraBytes = 0;
    for (var i = 0; i <= lines.length; i++) {
        var line = i < lines.length ? lines[i] : "";
        if (i < lines.length && line.length > maxLineChars) {
            issues.push({ kind: "line", line: i + 1, size: line.length, limit: maxLineChars });
        }
        if (/\S/.test(line)) {
            if (paraStart === -1) {
                paraStart = i + 1;
                paraBytes = 0;
            } else {
                paraBytes += 1;
            }
            paraBytes += Buffer.byteLength(line, "utf8");
        } else if (paraStart !== -1) {
            if (paraBytes > maxParagraphBytes) {
                issues.push({ kind: "paragraph", line: paraStart, size: paraBytes, limit: maxParagraphBytes });
            }
            paraStart = -1;
            paraBytes = 0;
        }
    }
    return issues;
}

function exceedsByteBudget(byteCount, budget) {
    return byteCount > budget;
}

function lineCountOf(text) {
    var n = 0;
    for (var k = 0; k < text.length; k++) if (text.charCodeAt(k) === 10) n++;
    if (text.length && text.charCodeAt(text.length - 1) !== 10) n++;
    return n;
}

function diffExactSet(actual, expected) {
    var a = uniqueSorted(actual);
    var e = uniqueSorted(expected);
    var missing = [];
    var unexpected = [];
    for (var i = 0; i < e.length; i++) if (a.indexOf(e[i]) === -1) missing.push(e[i]);
    for (var j = 0; j < a.length; j++) if (e.indexOf(a[j]) === -1) unexpected.push(a[j]);
    return { missing: missing, unexpected: unexpected };
}

// edges = [[from, to], ...]（有向图）。返回循环列表，每个循环是排序后的节点数组；
// SCC 大小 > 1 或节点自环即视为循环。空数组表示无环。
function findMustReadCycles(edges) {
    var adj = {};
    var nodes = [];
    for (var i = 0; i < edges.length; i++) {
        var from = edges[i][0];
        var to = edges[i][1];
        if (!adj[from]) { adj[from] = []; nodes.push(from); }
        if (!adj[to]) { adj[to] = []; nodes.push(to); }
        if (adj[from].indexOf(to) === -1) adj[from].push(to);
    }
    var index = 0;
    var stack = [];
    var onStack = {};
    var idx = {};
    var low = {};
    var sccs = [];
    function strongconnect(v) {
        idx[v] = index;
        low[v] = index;
        index++;
        stack.push(v);
        onStack[v] = true;
        var targets = adj[v];
        for (var k = 0; k < targets.length; k++) {
            var w = targets[k];
            if (idx[w] === undefined) {
                strongconnect(w);
                low[v] = Math.min(low[v], low[w]);
            } else if (onStack[w]) {
                low[v] = Math.min(low[v], idx[w]);
            }
        }
        if (low[v] === idx[v]) {
            var scc = [];
            var w2;
            do {
                w2 = stack.pop();
                onStack[w2] = false;
                scc.push(w2);
            } while (w2 !== v);
            sccs.push(scc);
        }
    }
    for (var n = 0; n < nodes.length; n++) {
        if (idx[nodes[n]] === undefined) strongconnect(nodes[n]);
    }
    var cycles = [];
    for (var s = 0; s < sccs.length; s++) {
        var scc = sccs[s];
        if (scc.length > 1 || adj[scc[0]].indexOf(scc[0]) !== -1) cycles.push(scc.slice().sort());
    }
    cycles.sort();
    return cycles;
}

// 必读边判定（F2，分句级）：行先按句读切成子句，每个链接只看自己所在子句的指令语气。
// 子句含强指令词（先读/必读/先 [）→ 必读边；只含弱词（详见/参考/另见/参见/见 [）→ 背景边；
// 无词子句延续该行最近的前向语气，行首尚无语气时按现行默认（背景）。
var MUST_READ_STRONG_RE = /先读|必读|先\s*(?=\[)/;
var MUST_READ_WEAK_RE = /详见|另见|参考|参见|见\s*(?=\[)/;
var CLAUSE_SPLIT_RE = /[，。；;！？!?：:]/;

function classifyLinkClause(line, column) {
    var lastTone = null;
    var start = 0;
    for (var i = 0; i <= line.length; i++) {
        if (i < line.length && !CLAUSE_SPLIT_RE.test(line.charAt(i))) continue;
        var clause = line.slice(start, i);
        var tone;
        if (MUST_READ_STRONG_RE.test(clause)) tone = true;
        else if (MUST_READ_WEAK_RE.test(clause)) tone = false;
        else tone = lastTone === null ? false : lastTone;
        if (MUST_READ_STRONG_RE.test(clause) || MUST_READ_WEAK_RE.test(clause)) lastTone = tone;
        if (column >= start && column <= i) return tone;
        start = i + 1;
    }
    return false;
}

// 行级兼容判定：该行是否存在任一被分句规则判为必读的链接。
function isMustReadLine(line) {
    var links = extractMarkdownLinks(line);
    for (var i = 0; i < links.length; i++) {
        if (classifyLinkClause(line, links[i].column)) return true;
    }
    return false;
}

// 从单个入口文件文本提取必读边目标（本地链接的目标文件部分；同文件页内锚点与外部链接忽略）。
function extractMustReadTargets(text) {
    var lines = text.split(/\r?\n/);
    var out = [];
    var links = extractMarkdownLinks(text);
    for (var i = 0; i < links.length; i++) {
        var link = links[i];
        if (!classifyLinkClause(lines[link.line - 1] || "", link.column)) continue;
        var parsed = splitLinkTarget(link.target);
        if (!parsed || !parsed.file) continue;
        out.push({ target: parsed.file, line: link.line });
    }
    return out;
}

// 校验单文件内的本地链接与 fragment 锚点。io = { exists(absPath), anchors(absPath) }。
// 相对路径解析后逃出 rootAbs 直接报；返回 [{ line, message }]，message 自带 [file:line]。
function checkMarkdownLinks(rootAbs, sourceAbs, sourceRel, text, io) {
    var issues = [];
    var selfAnchors = null;
    var links = extractMarkdownLinks(text);
    for (var i = 0; i < links.length; i++) {
        var link = links[i];
        var parsed = splitLinkTarget(link.target);
        if (!parsed) continue;
        if (!parsed.file) {
            if (!parsed.fragment) continue;
            if (selfAnchors === null) selfAnchors = io.anchors(sourceAbs) || {};
            if (!selfAnchors[parsed.fragment.toLowerCase()]) {
                issues.push({ line: link.line, message: "broken same-file fragment #" + parsed.fragment + " [" + sourceRel + ":" + link.line + "]" });
            }
            continue;
        }
        var resolved = path.resolve(path.dirname(sourceAbs), parsed.file);
        var relToRoot = path.relative(rootAbs, resolved);
        if (relToRoot === ".." || relToRoot.indexOf(".." + path.sep) === 0 || path.isAbsolute(relToRoot)) {
            issues.push({ line: link.line, message: "markdown link escapes repo root: " + link.target + " [" + sourceRel + ":" + link.line + "]" });
            continue;
        }
        if (!io.exists(resolved)) {
            issues.push({ line: link.line, message: "broken local markdown link: " + parsed.file + " [" + sourceRel + ":" + link.line + "]" });
            continue;
        }
        if (parsed.fragment && /\.md$/i.test(resolved)) {
            var anchors = io.anchors(resolved);
            if (anchors && !anchors[parsed.fragment.toLowerCase()]) {
                issues.push({ line: link.line, message: "broken fragment #" + parsed.fragment + " -> " + parsed.file + " [" + sourceRel + ":" + link.line + "]" });
            }
        }
    }
    return issues;
}

// 解析 `git diff -U0` 输出，收集每个文件的新侧新增行行号（hunk 头 @@ -a,b +c,d @@ 的 c 起算；
// + 行记录并递增，- 行不占新侧行号）。返回 { 文件: { 行号: true } }；调用方需用 -c core.quotePath=false 取原始 UTF-8 路径。
function parseGitDiffAddedLines(diffText) {
    var result = {};
    var current = null;
    var inHunk = false;
    var newLine = 0;
    var lines = diffText.split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.indexOf("diff --git ") === 0) {
            current = null;
            inHunk = false;
            continue;
        }
        if (!inHunk && line.indexOf("+++ ") === 0) {
            var p = line.slice(4);
            if (p === "/dev/null") {
                current = null;
                continue;
            }
            current = p.replace(/^b\//, "");
            if (!result[current]) result[current] = {};
            continue;
        }
        var hunk = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(line);
        if (hunk) {
            inHunk = true;
            newLine = parseInt(hunk[1], 10);
            continue;
        }
        if (!inHunk || !current) continue;
        var first = line.charAt(0);
        if (first === "+") {
            result[current][newLine] = true;
            newLine++;
        } else if (first === "-") {
            // 删除行不占新侧行号
        } else if (line.indexOf("\\") === 0) {
            // "\ No newline at end of file"
        } else {
            newLine++;
        }
    }
    return result;
}

// 坏链接/坏锚点分级：治理闭包名单内文件一律 error；名单外落在新增/改动行（含未跟踪文件全部行）→ error；
// 落在未改动行 → warn 债务。changedFiles/untrackedSet 为 null 时表示 git 降级，仅按名单阻断。
function linkIssueSeverity(rel, line, blockFiles, changedFiles, untrackedSet) {
    if (blockFiles[rel]) return "error";
    if (untrackedSet && untrackedSet[rel]) return "error";
    if (changedFiles && changedFiles[rel] && changedFiles[rel][line]) return "error";
    return "warn";
}

// 行数预算是提示级（warn），不是硬门：新增锚点/章节不受行数门逼迫；超限应删重复/缩小范围而非压行。
function lineBudgetNotice(lineCount, budget) {
    if (lineCount <= budget) return null;
    return "line budget notice: " + lineCount + " lines, budget " + budget +
        "；行数只作提示，新增锚点/章节不受行数门逼迫；超限应删重复/缩小范围而非压行";
}

var REQUIRED_FILES = [
    "AGENTS.md",
    "CLAUDE.md",
    "README.md",
    "agentsDoc/architecture.md",
    "agentsDoc/testing-guide.md",
    "agentsDoc/testing-details.md",
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
    "docs/testing-guide-history-2026-09-17.md",
    "docs/tech-stack-rationalization.md",
    "scripts/FlashCS6自动化编译.md",
    "tools/validate-doc-governance.js",
    "tools/test-doc-governance.js"
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

// 链接/锚点校验的阻断范围：只含本批文档治理闭包；其余 .md 的缺陷一律 warn（既有债务逐条报告，不静默豁免）。
var LINK_BLOCK_FILES = {
    "AGENTS.md": true,
    "CLAUDE.md": true,
    "README.md": true,
    "agentsDoc/testing-guide.md": true,
    "agentsDoc/testing-details.md": true,
    "agentsDoc/documentation-governance.md": true,
    "agentsDoc/as2-web-panel-migration.md": true,
    "agentsDoc/workbench-ui-system.md": true,
    "agentsDoc/architecture.md": true,
    "agentsDoc/data-schemas.md": true,
    "agentsDoc/self-optimization.md": true,
    "launcher/README.md": true,
    "automation/README.md": true,
    "docs/runtime-build-reproducibility.md": true,
    "docs/AS2-UI迁移剩余清单与难度评估-2026-09-12.md": true
};

// 这两个文件的目标存在性检查仍由 validateLocalMarkdownLinks 以 error 承担；
// 全仓扫描对它们只补 fragment/越界校验，避免同一行同一目标重复报错。
var LEGACY_LINK_GATE_FILES = {
    "launcher/README.md": true,
    "docs/launcher-save-editor-audio-migration-incident-2026-04-28.md": true
};

// 必读环检测的边来源：只从四个入口文件提取强指令（先读/必读）边；条件/背景互链不构成 DAG 节点义务。
var MUST_READ_ENTRIES = ["AGENTS.md", "CLAUDE.md", "README.md", "agentsDoc/testing-guide.md"];

function listRepoMarkdownFiles() {
    var SKIP_DIRS = { ".git": true, "node_modules": true, "tmp": true, ".workbuddy": true, ".workbuddy-ai": true };
    var out = [];
    function walk(relDir) {
        var names = fs.readdirSync(relDir ? abs(relDir) : ROOT);
        for (var i = 0; i < names.length; i++) {
            var name = names[i];
            if (SKIP_DIRS[name]) continue;
            var rel = relDir ? relDir + "/" + name : name;
            if (fs.statSync(abs(rel)).isDirectory()) walk(rel);
            else if (/\.md$/i.test(name)) out.push(rel);
        }
    }
    walk("");
    return out.sort();
}

// 文件内容与锚点索引按绝对路径缓存：链接扫描近似 O(总受检字节 + 边数)。
var cachedFileText = {};
function readCachedAbs(absPath) {
    if (!Object.prototype.hasOwnProperty.call(cachedFileText, absPath)) {
        try {
            cachedFileText[absPath] = fs.readFileSync(absPath, "utf8");
        } catch (e) {
            cachedFileText[absPath] = null;
        }
    }
    return cachedFileText[absPath];
}

var cachedAnchors = {};
var liveMarkdownIo = {
    exists: function (absPath) { return fs.existsSync(absPath); },
    anchors: function (absPath) {
        if (!Object.prototype.hasOwnProperty.call(cachedAnchors, absPath)) {
            var t = readCachedAbs(absPath);
            cachedAnchors[absPath] = t === null ? null : collectAnchors(t);
        }
        return cachedAnchors[absPath];
    }
};

// 一次 git diff + 一次 ls-files 拿到全部 .md 的新增行与未跟踪集合；任何一步失败返回 null（调用方降级为名单行为）。
function runGitText(root, args) {
    var r = cp.spawnSync("git", args, {
        cwd: root,
        stdio: ["ignore", "pipe", "ignore"],
        maxBuffer: 64 * 1024 * 1024
    });
    if (r.error || r.status !== 0) return null;
    return r.stdout.toString("utf8");
}

function collectChangedMarkdownLines(root) {
    // `git diff HEAD` 同时覆盖 staged 与 unstaged（相对 HEAD）；未跟踪文件不在 diff 内，需单独枚举。
    var diff = runGitText(root, ["-c", "core.quotePath=false", "diff", "HEAD", "-U0", "--", "*.md"]);
    if (diff === null) return null;
    var others = runGitText(root, ["-c", "core.quotePath=false", "ls-files", "--others", "--exclude-standard"]);
    if (others === null) return null;
    var untracked = {};
    var skipRe = /(^|\/)(?:\.git|node_modules|tmp|\.workbuddy|\.workbuddy-ai)(\/|$)/;
    var otherLines = others.split(/\r?\n/);
    for (var i = 0; i < otherLines.length; i++) {
        var rel = otherLines[i];
        if (!/\.md$/i.test(rel) || skipRe.test(rel)) continue;
        untracked[rel] = true;
    }
    return { changed: parseGitDiffAddedLines(diff), untracked: untracked };
}

function main() {

for (var i = 0; i < REQUIRED_FILES.length; i++) expectFile(REQUIRED_FILES[i]);
for (var j = 0; j < AGENTS_REFERENCES.length; j++) expectFile(AGENTS_REFERENCES[j]);

// ---- Baseline commit markers ----

var BASELINE_DOCS = [
    "AGENTS.md",
    "README.md",
    "agentsDoc/architecture.md",
    "agentsDoc/testing-guide.md",
    "agentsDoc/testing-details.md",
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

expectContains("AGENTS.md", /## 硬约束/, "AGENTS hard-constraints section missing");
expectContains("AGENTS.md", /## 按任务读取/, "AGENTS task-routing section missing");
expectContains("agentsDoc/testing-guide.md", /<a id="select"><\/a>/, "testing-guide select anchor missing");
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

// ---- Doc size budget (bytes / lines / readability) ----
// Source of truth: agentsDoc/documentation-governance.md §7 的 doc-read-budgets 标记块。
// 此处不手填第二份常量；行数门不得被用作压行激励。

function lineCount(rel) {
    return lineCountOf(read(rel));
}

var budgetBlock = markedBlock("agentsDoc/documentation-governance.md", "doc-read-budgets");
var docBudgets = null;
try {
    docBudgets = JSON.parse(budgetBlock.trim());
} catch (e) {
    expect(false, "doc-read-budgets marker block is not valid JSON [agentsDoc/documentation-governance.md]");
}
if (docBudgets) {
    var byteBudgets = docBudgets.byteBudgets || {};
    for (var bf in byteBudgets) {
        if (!Object.prototype.hasOwnProperty.call(byteBudgets, bf)) continue;
        if (!exists(bf)) {
            expect(false, "byte budget target missing: " + bf);
            continue;
        }
        // 原始字节判定：直接 Buffer.length，不做文本转码。
        var byteCount = fs.readFileSync(abs(bf)).length;
        expect(!exceedsByteBudget(byteCount, byteBudgets[bf]),
            "byte budget exceeded: " + bf + " has " + byteCount + " bytes, budget " + byteBudgets[bf]);
    }
    var lineBudgets = docBudgets.lineBudgets || {};
    for (var lf in lineBudgets) {
        if (!Object.prototype.hasOwnProperty.call(lineBudgets, lf)) continue;
        if (!exists(lf)) continue;
        var lc = lineCount(lf);
        // F3：行数预算是提示级 warn，不硬失败；字节预算与可读性保持 error。
        var notice = lineBudgetNotice(lc, lineBudgets[lf]);
        if (notice) warnings.push(notice + " [" + lf + "]");
    }
    var readability = docBudgets.readability || {};
    var appliesTo = readability.appliesTo || [];
    for (var ri = 0; ri < appliesTo.length; ri++) {
        var readRel = appliesTo[ri];
        if (!exists(readRel)) {
            expect(false, "readability target missing: " + readRel);
            continue;
        }
        var rIssues = findReadabilityIssues(read(readRel), readability.maxLineChars, readability.maxParagraphBytes);
        for (var rj = 0; rj < rIssues.length; rj++) {
            var issue = rIssues[rj];
            expect(false, "readability " + issue.kind + " over " + issue.limit +
                (issue.kind === "line" ? " chars" : " bytes") + ": " + readRel + ":" + issue.line +
                " (actual " + issue.size + ")");
        }
    }
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
var cliSource = read("launcher/src/Program.cs") + "\n" + read("launcher/src/Audio/AudioQualificationDiagnosticsV1.cs") + "\n" + read("launcher/src/Guardian/HotkeyGuard.cs");
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
    // dotnet test --logger 的默认报告目录不是测试源码分类；保留报告也应能检查文档。
    // 只接受报告产物，误放源码仍报错，不能把它用作未登记测试目录。
    if (testEntries[td] === "TestResults") {
        expect(listFiles("launcher/tests/TestResults", function (rel) {
            return /\.(cs|js|ts|ps1)$/i.test(rel);
        }).length === 0, "launcher/tests/TestResults must contain generated reports, not test source");
        continue;
    }
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

// ---- Testing matrix/details must keep canonical commands ----
// 义务不变，定位改为：选择矩阵（testing-guide.md）或其可达正文（testing-details.md）仍承载该命令，逐项对照。

var TESTING_COMMANDS = [
    [/compile_test\.ps1/, "Flash smoke command"],
    [/launcher\/build\.ps1/, "launcher build command"],
    [/--bus-only/, "bus-only"],
    [/run-minigame-qa\.js/, "minigame QA"],
    [/validate-doc-governance\.js/, "doc governance validation"]
];
var testingCorpus = read("agentsDoc/testing-guide.md") + "\n" + read("agentsDoc/testing-details.md");
for (var tc = 0; tc < TESTING_COMMANDS.length; tc++) {
    expect(TESTING_COMMANDS[tc][0].test(testingCorpus), "matrix/details missing " + TESTING_COMMANDS[tc][1]);
}

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

// ---- Repo-wide local markdown link & fragment audit ----
// 扫描全仓 .md（排除 .git/node_modules/tmp/.workbuddy/.workbuddy-ai）。
// 分级（F1）：LINK_BLOCK_FILES 治理闭包内一律 error；名单外落在 git 新增/改动行（或未跟踪文件）→ error；
// 未改动行的旧缺陷逐条 warn，不静默豁免。与 validateLocalMarkdownLinks 共存：
// LEGACY_LINK_GATE_FILES 的存在性错误仍由旧门承担，此处不重复报。

var changedMdInfo = hasGit ? collectChangedMarkdownLines(ROOT) : null;
if (!changedMdInfo) {
    warnings.push("git diff unavailable: new/changed-line link blocking degraded to LINK_BLOCK_FILES-only mode（名单外新增行的坏链接本次只记 warn）");
}

var repoMdFiles = listRepoMarkdownFiles();
var linkDebt = [];
for (var md = 0; md < repoMdFiles.length; md++) {
    var mdRel = repoMdFiles[md];
    var mdText = readCachedAbs(abs(mdRel));
    if (mdText === null) continue;
    var linkIssues = checkMarkdownLinks(ROOT, abs(mdRel), mdRel, mdText, liveMarkdownIo);
    for (var li = 0; li < linkIssues.length; li++) {
        var linkIssue = linkIssues[li];
        if (LEGACY_LINK_GATE_FILES[mdRel] && linkIssue.message.indexOf("broken local markdown link") === 0) continue;
        var severity = linkIssueSeverity(
            mdRel,
            linkIssue.line,
            LINK_BLOCK_FILES,
            changedMdInfo && changedMdInfo.changed,
            changedMdInfo && changedMdInfo.untracked);
        if (severity === "error") {
            errors.push(linkIssue.message + (LINK_BLOCK_FILES[mdRel] ? "" : " (new/changed line)"));
        } else {
            linkDebt.push({ file: mdRel, message: linkIssue.message });
        }
    }
}
if (linkDebt.length > 200) {
    // 既有债务过多时按文件汇总 + 前几条示例，避免刷屏；不静默豁免。
    var debtPerFile = {};
    for (var ld = 0; ld < linkDebt.length; ld++) {
        debtPerFile[linkDebt[ld].file] = (debtPerFile[linkDebt[ld].file] || 0) + 1;
    }
    var debtFiles = [];
    for (var df in debtPerFile) {
        if (Object.prototype.hasOwnProperty.call(debtPerFile, df)) debtFiles.push(df);
    }
    debtFiles.sort(function (a, b) { return debtPerFile[b] - debtPerFile[a] || (a < b ? -1 : 1); });
    var debtSummary = [];
    var debtShown = Math.min(debtFiles.length, 20);
    for (var ds = 0; ds < debtShown; ds++) debtSummary.push(debtFiles[ds] + ": " + debtPerFile[debtFiles[ds]]);
    warnings.push("repo-wide markdown link debt: " + linkDebt.length + " defects in " + debtFiles.length +
        " files (non-blocking, historical); per-file top: " + debtSummary.join("; ") +
        (debtFiles.length > debtShown ? "; ... and " + (debtFiles.length - debtShown) + " more files" : ""));
    var exLimit = Math.min(linkDebt.length, 10);
    for (var ex = 0; ex < exLimit; ex++) warnings.push("link debt example: " + linkDebt[ex].message);
} else {
    for (var lw = 0; lw < linkDebt.length; lw++) warnings.push(linkDebt[lw].message);
}

// ---- Must-read cycle detection (entry docs only) ----
// 只从四个入口文件提取「先读/必读」强指令边；详见/参考类背景互链不计入，不把所有链接当 DAG。

var mustReadEdges = [];
for (var mr = 0; mr < MUST_READ_ENTRIES.length; mr++) {
    var entryRel = MUST_READ_ENTRIES[mr];
    if (!exists(entryRel)) continue;
    var mrTargets = extractMustReadTargets(read(entryRel));
    for (var mt = 0; mt < mrTargets.length; mt++) {
        var toAbs = path.resolve(path.dirname(abs(entryRel)), mrTargets[mt].target);
        var toRel = path.relative(ROOT, toAbs).replace(/\\/g, "/");
        if (toRel === entryRel || toRel === ".." || toRel.indexOf("../") === 0) continue;
        mustReadEdges.push([entryRel, toRel]);
    }
}
var mustReadCycles = findMustReadCycles(mustReadEdges);
expect(mustReadCycles.length === 0, "must-read cycle among entry docs: " +
    mustReadCycles.map(function (c) { return c.join(" <-> "); }).join("; "));

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

}

if (require.main === module) {
    main();
}

// 纯文本检查函数导出，供 tools/test-doc-governance.js 的 fixture 复用；require 本文件不触发巡检。
module.exports = {
    blankInlineCode: blankInlineCode,
    eachNonFenceLine: eachNonFenceLine,
    extractMarkdownLinks: extractMarkdownLinks,
    slugifyHeading: slugifyHeading,
    collectAnchors: collectAnchors,
    splitLinkTarget: splitLinkTarget,
    findReadabilityIssues: findReadabilityIssues,
    exceedsByteBudget: exceedsByteBudget,
    lineCountOf: lineCountOf,
    lineBudgetNotice: lineBudgetNotice,
    diffExactSet: diffExactSet,
    findMustReadCycles: findMustReadCycles,
    isMustReadLine: isMustReadLine,
    classifyLinkClause: classifyLinkClause,
    extractMustReadTargets: extractMustReadTargets,
    checkMarkdownLinks: checkMarkdownLinks,
    parseGitDiffAddedLines: parseGitDiffAddedLines,
    linkIssueSeverity: linkIssueSeverity,
    collectChangedMarkdownLines: collectChangedMarkdownLines
};
