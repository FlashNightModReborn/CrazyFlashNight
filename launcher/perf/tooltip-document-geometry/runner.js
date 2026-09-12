'use strict';
/*
 * tooltip-document-geometry — legacy rich 渲染 vs document 适配渲染的真实 DOM 几何对比
 *
 * 目的（parity-web 岗位）：验证 tooltip-document.js 输出在真实浏览器排版下与
 * PanelTooltip.buildItemRichHtml（迁移前 Web 权威）结构等效：
 *   - intro panel / desc panel / icon / root 宽高
 *   - split/merge 分栏决策一致
 *   - 默认 --tt-* 主题（字体/颜色/渐变/icon blend）不被 document CSS 改写
 *   - innerText 逐行等价
 *
 * 输入来源：
 *   1. 内置合成用例（边界：merge/split/无icon/narrow/标题去重/占位图标/长行）
 *   2. --corpus <json>：parity-corpus fresh 语料（{introHTML, descHTML, name,
 *      displayName, type, use, icon, split}），document 由本 runner 按
 *      AS2 NativeTooltipDocument.buildItem 规则在本地合成（flattenMarkup 复用
 *      Web 端同模型实现 + dedupeTitleLine 移植）。
 *
 * 用法：
 *   node runner.js [--corpus <path>] [--limit N] [--out <dir>] [--shots N]
 * 输出：<out>/report.md, <out>/raw.json, <out>/shots/*.png（失败与最大 diff 样本）
 * 退出码：0=全过；1=有断言失败；2=环境缺失（playwright/浏览器不可用，明确打印 SKIP）
 */

const path = require('path');
const fs = require('fs');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const LAUNCHER_DIR = path.join(REPO_ROOT, 'launcher');
const FIXTURE_URL_PATH = 'perf/tooltip-document-geometry/fixture.html';
const FIXTURE_FILE = path.join(__dirname, 'fixture.html');

const { startServer, stopServer } = require('../lib/server.js');
const Doc = require(path.join(LAUNCHER_DIR, 'web', 'modules', 'tooltip-document.js'));
// document 合成一律走语料工具的 AS2 忠实移植（production-faithful，
// 含 dedupeTitleLine 与 tier 身份投影），不自行拼装——避免镜像失真
const Corpus = require(path.join(REPO_ROOT, 'tools', 'tooltip-parity-corpus.js'));
const CorpusDoc = Corpus.Doc;

/* ── 参数 ─────────────────────────────────────────────── */

const argv = process.argv.slice(2);
function argValue(name) {
    const i = argv.indexOf(name);
    return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
}
const CORPUS_PATH = argValue('--corpus');
const LIMIT = parseInt(argValue('--limit') || '0', 10) || 0;
const SHOTS = Math.min(48, parseInt(argValue('--shots') || '12', 10) || 12);
const OUT_DIR = path.resolve(REPO_ROOT,
    argValue('--out') || 'tmp/tooltip-document-geometry');

/* ── 阈值（不放宽：高度允许 ≤1.5px 亚像素取整差，其余必须严格相等） ── */

const TOL_H = 1.5;      // intro/desc 高度（行盒亚像素取整）
const TOL_ROOT_W = 2.0; // root 宽（desc 宽由 JS 估算，仅合并模式自然宽度可比）

/* ── AS2 buildItem 等效 document 合成 ─────────────────── */
/* 一律走 tools/tooltip-parity-corpus.js 的 §DOC 忠实移植（NativeTooltipDocument.as
 * 逐函数对应）：htmlToRuns / dedupeTitleLine / buildSectioned / buildItem。
 * tier 记录走 InventoryPanelService.buildTooltipProjection 语义：iconData =
 * 实例投影（tier 覆盖后 icon/displayname），itemData = 原始词条——
 * 上一轮直接用 rec.displayName 当 title 是镜像失真（tier 变体假双标题）。 */

/* spec = {title, iconName, layoutType, introHTML, descHTML, profile} → document */
function docFromSpec(spec) {
    var sections = [];
    var ir = Doc.flattenMarkup(spec.introHTML || '');
    if (ir.length) sections.push({ role: 'intro', runs: ir });
    var dr = Doc.flattenMarkup(spec.descHTML || '');
    if (dr.length) sections.push({ role: 'description', runs: dr });
    var title = CorpusDoc.dedupeTitleLine(spec.title || null, sections);
    var icon = spec.iconName ? { kind: 'item', name: spec.iconName } : null;
    var doc = CorpusDoc.buildSectioned(title, icon, sections, spec.profile || 'dense');
    if (spec.layoutType) doc.layoutType = spec.layoutType;
    return doc;
}

/* 物品身份索引：data/items/*.xml tier 块 + equipment_config.xml TierMapping
 * （tooltip-parity-corpus.js §XML/main 同款，icon/displayname 两字段重放） */
function buildIdentityIndex() {
    var itemsDir = path.join(REPO_ROOT, 'data', 'items');
    var itemIndex = new Map();
    fs.readdirSync(itemsDir).forEach(function (f) {
        if (!f.endsWith('.xml')) return;
        Corpus.parseItemsXml(fs.readFileSync(path.join(itemsDir, f), 'utf8'))
            .forEach(function (it) {
                if (!itemIndex.has(it.name)) itemIndex.set(it.name, it);
            });
    });
    var tierNameToKey = Corpus.parseTierNameToKey(fs.readFileSync(
        path.join(REPO_ROOT, 'data', 'equipment', 'equipment_config.xml'), 'utf8'));
    return { itemIndex: itemIndex, tierNameToKey: tierNameToKey };
}

/* corpus record → spec：buildItem 生产语义（iconData=投影，itemData=原词条） */
function specFromCorpus(rec, idents) {
    var xmlItem = idents.itemIndex.get(rec.name) || null;
    var identity = null;
    if (rec.variant === 'tier' && rec.tier && xmlItem) {
        var key = idents.tierNameToKey[rec.tier] || null;
        var block = key && xmlItem.tiers ? xmlItem.tiers[key] : null;
        if (block && (block.icon != null || block.displayname != null)) {
            identity = {};
            if (block.icon != null) identity.icon = block.icon;
            if (block.displayname != null) identity.displayname = block.displayname;
        }
    }
    var projection = {
        displayname: identity && identity.displayname != null
            ? identity.displayname : rec.displayName,
        icon: identity && identity.icon != null ? identity.icon : rec.icon
    };
    /* buildItem 同款步骤，但 htmlToRuns 用本模块 flattenMarkup（document v1
     * 新样式模型已落地：italic/underline/fontSize/fontFace）。语料工具 mirror
     * 待 parity-corpus 按 semantics notes 同步前，用它替代旧模型——
     * dedupe/投影/buildSectioned/layoutType 仍走 CorpusDoc 忠实移植。 */
    var sections = [];
    var ir = Doc.flattenMarkup(rec.introHTML || '');
    if (ir.length) sections.push({ role: 'intro', runs: ir });
    var dr = Doc.flattenMarkup(rec.descHTML || '');
    if (dr.length) sections.push({ role: 'description', runs: dr });
    var title = (projection.displayname != null && projection.displayname !== '')
        ? String(projection.displayname) : String(rec.name);
    title = CorpusDoc.dedupeTitleLine(title, sections);
    var icon = (projection.icon != null && projection.icon !== '')
        ? { kind: 'item', name: String(projection.icon) } : null;
    var document = CorpusDoc.buildSectioned(title, icon, sections, 'dense');
    var typeName = (rec.type === '消耗品' && rec.use) ? String(rec.use) : String(rec.type || '');
    document.layoutType = (typeName === '武器' || typeName === '防具'
        || typeName === '技能' || typeName === '药剂') ? 'wide' : 'narrow';
    return {
        id: 'corpus-' + rec.id + '-' + (rec.variant || 'base'),
        iconName: projection.icon || null,
        layoutType: document.layoutType || null,
        introHTML: rec.introHTML || '',
        descHTML: rec.descHTML || '',
        profile: document.profile,
        document: document,
        expectedSplit: (typeof rec.split === 'boolean') ? rec.split : null
    };
}

/* ── 内置合成用例 ─────────────────────────────────────── */

const ICON_STUB = '<div style="width:var(--tt-icon-size);height:var(--tt-icon-size);'
    + 'box-sizing:border-box;border:1px dashed rgba(255,255,255,0.3)"></div>';

const SYNTH = [
    { id: 'synth-merge-short', title: '磨刀石', iconName: '磨刀石', layoutType: 'narrow',
      introHTML: '<B>磨刀石</B><BR>消耗品<BR>$10<BR>', descHTML: '磨刀用<BR>',
      iconHtml: ICON_STUB },
    { id: 'synth-split-long', title: 'K型散弹枪', iconName: 'K型散弹枪', layoutType: 'wide',
      introHTML: '<B>K型散弹枪</B><BR>武器<BR>攻击 +120<BR>$12000<BR>',
      descHTML: ('发射多枚弹丸覆盖前方扇形区域，近距离伤害极高。'
          + '这是一段足够长的描述文字用来突破 shouldSplit 阈值并产生独立 desc 分栏。').repeat(3) + '<BR>',
      iconHtml: ICON_STUB },
    { id: 'synth-no-desc', title: '护甲片', layoutType: 'narrow',
      introHTML: '<B>护甲片</B><BR>防具<BR>防御 +15<BR>', descHTML: '' },
    { id: 'synth-no-icon', title: '补给包', layoutType: 'narrow',
      introHTML: '<B>补给包</B><BR>消耗品<BR>$50<BR>', descHTML: '恢复少量生命<BR>' },
    { id: 'synth-narrow', title: '绷带', iconName: '绷带', layoutType: 'narrow',
      introHTML: '<B>绷带</B><BR>消耗品<BR>$20<BR>', descHTML: '止血<BR>',
      iconHtml: ICON_STUB },
    { id: 'synth-tier-title', title: '龍一文字', iconName: '龍一文字', layoutType: 'wide',
      introHTML: "<B>[传说]龍一文字</B><BR>武器<BR><FONT COLOR='#FFD700'>攻击 +999</FONT><BR>",
      descHTML: '传说中的名刀<BR>', iconHtml: ICON_STUB },
    { id: 'synth-colored', title: '强化剂', layoutType: 'narrow',
      introHTML: "<B>强化剂</B><BR><FONT COLOR='#FF8080'>副作用大</FONT><BR>",
      descHTML: "<FONT COLOR='#00FF00'>临时提升</FONT>全部属性<BR>" },
    { id: 'synth-doc-icon-miss', title: '残破徽章', iconName: '__missing_icon__',
      layoutType: 'narrow', introHTML: '<B>残破徽章</B><BR>材料<BR>', descHTML: '看不出用途<BR>',
      docIcon: true },
    { id: 'synth-empty-title', title: null, layoutType: 'narrow',
      introHTML: '<B>无名物品</B><BR>材料<BR>', descHTML: '' },
    { id: 'synth-merge-boundary', title: '临界药剂', iconName: '临界药剂', layoutType: 'wide',
      introHTML: '<B>临界药剂</B><BR>药剂<BR>使用等级 30<BR>',
      descHTML: '中等长度描述，接近 split 阈值但仍在合并侧。'.repeat(2) + '<BR>',
      iconHtml: ICON_STUB },
    { id: 'synth-long-word', title: '连字号测试', layoutType: 'narrow',
      introHTML: '<B>连字号测试</B><BR>' + 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.repeat(6) + '<BR>',
      descHTML: '无空格超长行换行压力<BR>' },
    { id: 'synth-suffix-meta', title: '锁定物品', iconName: '锁定物品', layoutType: 'wide',
      introHTML: '<B>锁定物品</B><BR>武器<BR>攻击 +50<BR>',
      descHTML: ('带 meta/suffix 的分栏物品，描述需要足够长来触发分栏。'.repeat(6)) + '<BR>',
      iconHtml: ICON_STUB,
      metaHTML: '<span style="color:#fcee09">已锁定</span>',
      suffix: '<div>物品已被锁定，无法出售</div>' },
    /* document v1 扩展样式字段（italic/underline/fontSize/fontFace）：
       document 直接手写 wire 形态；legacy 侧走等价 AS2 标记。 */
    { id: 'synth-styles', layoutType: 'narrow',
      introHTML: "<B>样式测试</B><BR><I>斜体行</I><BR><U>下划行</U><BR>"
          + "<FONT SIZE='20'>大字行</FONT><BR><FONT FACE='fixedsys'>等宽行</FONT><BR>",
      descHTML: '<BR>',
      document: { version: 1, profile: 'dense', layoutType: 'narrow',
          title: '样式测试',
          sections: [{ role: 'intro', runs: [
              { text: '斜体行', italic: true }, { text: '\n' },
              { text: '下划行', underline: true }, { text: '\n' },
              { text: '大字行', fontSize: 20 }, { text: '\n' },
              { text: '等宽行', fontFace: 'fixedsys' }, { text: '\n' }] }] } },
    { id: 'synth-styles-nested', layoutType: 'narrow',
      introHTML: "<B>嵌套样式</B><BR><FONT COLOR='#FF0000' SIZE='15'><B><I><U>嵌套</U></I></B></FONT><BR>"
          + "<FONT COLOR='#0F0'><FONT SIZE='30'>层叠</FONT>还原</FONT><BR>",
      descHTML: '',
      document: { version: 1, profile: 'dense', layoutType: 'narrow',
          title: '嵌套样式',
          sections: [{ role: 'intro', runs: [
              { text: '嵌套', color: '#FF0000', bold: true, italic: true,
                underline: true, fontSize: 15 }, { text: '\n' },
              { text: '层叠', color: '#00FF00', fontSize: 30 },
              { text: '还原', color: '#00FF00' }, { text: '\n' }] }] } },
    { id: 'synth-3hex-color', layoutType: 'narrow',
      introHTML: "<B>短hex</B><BR><FONT COLOR='#F00'>红色</FONT><BR>", descHTML: '',
      document: { version: 1, profile: 'dense', layoutType: 'narrow',
          title: '短hex',
          sections: [{ role: 'intro', runs: [
              { text: '红色', color: '#FF0000' }, { text: '\n' }] }] } }
];

/* ── diff / 断言 ─────────────────────────────────────── */

function num(v) { return v == null ? null : v; }
function hdiff(a, b) { return (a == null || b == null) ? null : Math.abs(a.h - b.h); }
function wdiff(a, b) { return (a == null || b == null) ? null : Math.abs(a.w - b.w); }

function normText(s) {
    return String(s == null ? '' : s)
        .replace(/\r\n/g, '\n').split('\n')
        .map(function(l) { return l.replace(/[ \t]+$/g, ''); })
        .join('\n').replace(/\n+$/g, '');
}

function diffCase(spec, result) {
    var L = result.legacy, D = result.doc;
    var fails = [];
    function fail(msg) { fails.push(msg); }

    if (L.hasDesc !== D.hasDesc) fail('desc 分栏不一致 legacy=' + L.hasDesc + ' doc=' + D.hasDesc);
    if (L.merged !== D.merged) fail('merge 标记不一致 legacy=' + L.merged + ' doc=' + D.merged);
    if ((L.introPanel != null) !== (D.introPanel != null)) fail('introPanel 存在性不一致');
    if (L.introPanel && D.introPanel && L.introPanel.w !== D.introPanel.w) {
        fail('introPanel 宽不一致 legacy=' + L.introPanel.w + ' doc=' + D.introPanel.w);
    }
    if (hdiff(L.intro, D.intro) != null && hdiff(L.intro, D.intro) > TOL_H) {
        fail('intro 高超差 ' + L.intro.h + ' vs ' + D.intro.h);
    }
    if ((L.intro != null) !== (D.intro != null)) fail('intro 存在性不一致');
    if (L.desc && D.desc) {
        if (hdiff(L.desc, D.desc) > TOL_H) fail('desc 高超差 ' + L.desc.h + ' vs ' + D.desc.h);
        if (wdiff(L.desc, D.desc) > TOL_ROOT_W) fail('desc 宽超差 ' + L.desc.w + ' vs ' + D.desc.w);
    }
    if (L.root && D.root && wdiff(L.root, D.root) > TOL_ROOT_W) {
        fail('root 宽超差 ' + L.root.w + ' vs ' + D.root.w);
    }
    /* icon 容器/图像尺寸必须一致 */
    if ((L.icon != null) !== (D.icon != null)) fail('icon 存在性不一致');
    if (L.icon && D.icon && (wdiff(L.icon, D.icon) > 0.01 || hdiff(L.icon, D.icon) > 0.01)) {
        fail('icon 尺寸不一致 ' + JSON.stringify(L.icon) + ' vs ' + JSON.stringify(D.icon));
    }
    /* 主题权威：computed style 必须逐项相等 */
    ['fontFamily', 'fontSize', 'lineHeight', 'introColor', 'introPanelBg', 'descBg', 'iconBlend']
        .forEach(function(k) {
            if (L[k] !== D[k]) fail('computed ' + k + ' 不一致 legacy=' + L[k] + ' doc=' + D[k]);
        });
    /* Web 权威锚点：默认主题值（不是 NativeHud） */
    if (D.iconImg && D.iconBlend !== 'overlay') {
        fail('icon mix-blend-mode 应为 overlay，实际 ' + D.iconBlend);
    }
    if (L.layout !== D.layout) fail('data-layout 不一致 legacy=' + L.layout + ' doc=' + D.layout);
    if (normText(L.text) !== normText(D.text)) {
        fail('innerText 不一致\nlegacy=<<' + normText(L.text).substring(0, 300)
            + '>>\ndoc=<<' + normText(D.text).substring(0, 300) + '>>');
    }

    var maxAbs = 0;
    [hdiff(L.intro, D.intro), hdiff(L.desc, D.desc), hdiff(L.introPanel, D.introPanel),
     hdiff(L.root, D.root), wdiff(L.root, D.root), wdiff(L.desc, D.desc)]
        .forEach(function(d) { if (d != null && d > maxAbs) maxAbs = d; });

    var splitWarn = null;
    if (spec.expectedSplit != null && D.hasDesc !== spec.expectedSplit) {
        splitWarn = 'doc.hasDesc=' + D.hasDesc + ' corpus.split=' + spec.expectedSplit;
    }
    return { fails: fails, maxAbsDiff: maxAbs, splitWarn: splitWarn };
}

/* ── 浏览器 / 服务 ────────────────────────────────────── */

function edgePath() {
    var c = [
        process.env.PROGRAMFILES && path.join(process.env.PROGRAMFILES, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env['PROGRAMFILES(X86)'] && path.join(process.env['PROGRAMFILES(X86)'], 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].filter(Boolean);
    return c.find(function(p) { return fs.existsSync(p); }) || '';
}

async function launchBrowser(chromium) {
    try { return await chromium.launch({ headless: true }); }
    catch (e) {
        var ep = edgePath();
        if (!ep) throw e;
        return await chromium.launch({ headless: true, executablePath: ep });
    }
}

function percentile(sorted, p) {
    if (!sorted.length) return 0;
    var i = Math.min(sorted.length - 1, Math.ceil(p * sorted.length) - 1);
    return sorted[Math.max(0, i)];
}

async function main() {
    var chromium;
    try { chromium = require('playwright').chromium; }
    catch (e) {
        console.log('SKIP: playwright 不可用（launcher/perf/node_modules 未安装）');
        process.exit(2);
    }
    if (!fs.existsSync(FIXTURE_FILE)) { console.error('fixture 缺失: ' + FIXTURE_FILE); process.exit(1); }
    fs.mkdirSync(path.join(OUT_DIR, 'shots'), { recursive: true });

    /* 用例集：合成 + corpus */
    var cases = SYNTH.map(function(s) {
        var spec = Object.assign({}, s);
        if (!spec.document) spec.document = docFromSpec(spec);
        return spec;
    });
    if (CORPUS_PATH) {
        var raw = JSON.parse(fs.readFileSync(CORPUS_PATH, 'utf8'));
        var records = raw.records || raw;
        if (LIMIT > 0) records = records.slice(0, LIMIT);
        var idents = buildIdentityIndex();
        records.forEach(function(rec) {
            var spec = specFromCorpus(rec, idents);
            spec.iconHtml = spec.iconName ? ICON_STUB : null;
            cases.push(spec);
        });
    }
    console.log('[geometry] cases=' + cases.length + ' (synth=' + SYNTH.length + ')');

    var server = await startServer(LAUNCHER_DIR);
    var browser = null, failures = [], rows = [], splitWarns = [];
    try {
        browser = await launchBrowser(chromium);
        var page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
        await page.goto(server.url + FIXTURE_URL_PATH);
        var ready = await page.evaluate('window.__tdgReady === true');
        if (!ready) throw new Error('fixture 未就绪：PanelTooltip/PanelTooltipDocument 未加载');

        for (var i = 0; i < cases.length; i++) {
            var spec = cases[i];
            var result = await page.evaluate(function(s) { return window.__tdgRun(s); }, spec);
            var d = diffCase(spec, result);
            rows.push({ id: spec.id, maxAbsDiff: d.maxAbsDiff, fails: d.fails.length,
                        legacy: result.legacy, doc: result.doc });
            if (d.splitWarn) splitWarns.push({ id: spec.id, warn: d.splitWarn });
            if (d.fails.length) failures.push({ id: spec.id, fails: d.fails, spec: spec });
            if ((i + 1) % 500 === 0) console.log('[geometry] ' + (i + 1) + '/' + cases.length);
        }

        /* 截图证据：失败样本优先，再补最大 diff */
        var shotPick = failures.slice(0, SHOTS).map(function(f) { return f.id; });
        rows.slice().sort(function(a, b) { return b.maxAbsDiff - a.maxAbsDiff; })
            .forEach(function(r) {
                if (shotPick.length < SHOTS && shotPick.indexOf(r.id) < 0) shotPick.push(r.id);
            });
        for (var j = 0; j < shotPick.length; j++) {
            var sid = shotPick[j];
            var s2 = cases.find(function(c) { return c.id === sid; });
            if (!s2) continue;
            await page.evaluate(function(p) { return window.__tdgMount(p.which, p.spec); },
                { which: 'legacy', spec: s2 });
            await page.locator('#panel-tooltip').screenshot({
                path: path.join(OUT_DIR, 'shots', sid + '-legacy.png') });
            await page.evaluate(function(p) { return window.__tdgMount(p.which, p.spec); },
                { which: 'doc', spec: s2 });
            await page.locator('#panel-tooltip').screenshot({
                path: path.join(OUT_DIR, 'shots', sid + '-doc.png') });
        }
    } finally {
        if (browser) await browser.close();
        await stopServer(server);
    }

    /* 汇总 */
    var diffs = rows.map(function(r) { return r.maxAbsDiff; }).sort(function(a, b) { return a - b; });
    var summary = {
        total: cases.length,
        passed: cases.length - failures.length,
        failed: failures.length,
        splitWarn: splitWarns.length,
        diffPx: {
            p50: percentile(diffs, 0.5), p90: percentile(diffs, 0.9),
            p99: percentile(diffs, 0.99), max: diffs.length ? diffs[diffs.length - 1] : 0
        }
    };
    fs.writeFileSync(path.join(OUT_DIR, 'raw.json'), JSON.stringify({
        summary: summary, corpus: CORPUS_PATH, rows: rows,
        failures: failures.map(function(f) { return { id: f.id, fails: f.fails }; }),
        splitWarns: splitWarns
    }, null, 2), 'utf8');

    var md = ['# tooltip-document-geometry 对比报告', '',
        '- cases: ' + summary.total + '，pass: ' + summary.passed + '，fail: ' + summary.failed,
        '- |Δ| px：p50=' + summary.diffPx.p50 + ' p90=' + summary.diffPx.p90
            + ' p99=' + summary.diffPx.p99 + ' max=' + summary.diffPx.max,
        '- corpus.split 提示（非断言）: ' + summary.splitWarn,
        '- 截图证据: shots/（失败样本 + 最大 diff 各 ' + SHOTS + ' 组）', ''];
    failures.slice(0, 40).forEach(function(f) {
        md.push('## FAIL ' + f.id);
        f.fails.forEach(function(x) { md.push('- ' + x.replace(/\n/g, '\n  ')); });
        md.push('');
    });
    if (splitWarns.length) {
        md.push('## split 提示样本（corpus.split vs doc.hasDesc，仅前 20）');
        splitWarns.slice(0, 20).forEach(function(w) { md.push('- ' + w.id + ': ' + w.warn); });
    }
    fs.writeFileSync(path.join(OUT_DIR, 'report.md'), md.join('\n'), 'utf8');

    console.log('[geometry] total=' + summary.total + ' pass=' + summary.passed
        + ' fail=' + summary.failed + ' |Δ| p50=' + summary.diffPx.p50
        + ' p90=' + summary.diffPx.p90 + ' p99=' + summary.diffPx.p99
        + ' max=' + summary.diffPx.max);
    console.log('[geometry] report: ' + path.join(OUT_DIR, 'report.md'));
    process.exit(failures.length ? 1 : 0);
}

main().catch(function(e) { console.error('[geometry] fatal: ' + (e && e.stack || e)); process.exit(2); });
