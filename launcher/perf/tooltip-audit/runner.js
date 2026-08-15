#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const {chromium} = require('playwright');
const {startServer, stopServer} = require('../lib/server.js');

const ROOT = path.resolve(__dirname, '..', '..', '..');
const CORPUS_PATH = path.join(ROOT, 'tmp', 'tooltip-audit', 'tooltip-corpus.json');
const REPORT_DIR = path.join(ROOT, 'tmp', 'tooltip-audit');
const REPORT_JSON = path.join(REPORT_DIR, 'report.json');
const REPORT_MD = path.join(REPORT_DIR, 'report.md');
const FIXTURE_URL = 'launcher/perf/tooltip-audit/fixture.html';
const BATCH_SIZE = 48;
const VIEWPORTS = [
    {id:'1024x576',width:1024,height:576},
    {id:'1366x768',width:1366,height:768},
    {id:'1920x1080',width:1920,height:1080}
];
const DENSITIES = ['full', 'compact'];
const PINNED_SUFFIX = 'kshop-locked-balance';

function fail(message, evidence) {
    const error = new Error(message);
    error.evidence = evidence;
    throw error;
}

function assert(condition, message, evidence) {
    if (!condition) fail(message, evidence);
}

function edgePath() {
    const candidates = [
        process.env.PROGRAMFILES && path.join(process.env.PROGRAMFILES, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env['PROGRAMFILES(X86)'] && path.join(process.env['PROGRAMFILES(X86)'], 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].filter(Boolean);
    return candidates.find(candidate => fs.existsSync(candidate)) || '';
}

function readSuffixRegistry() {
    const filename = path.join(__dirname, 'suffix-registry.js');
    const context = {};
    vm.createContext(context);
    vm.runInContext(fs.readFileSync(filename, 'utf8'), context, {filename});
    const registry = context.TooltipAuditSuffixRegistry;
    assert(Array.isArray(registry) && registry.length >= 4, 'Tooltip suffix registry is incomplete', registry);
    assert(registry[0].id === 'none', 'Tooltip suffix registry must begin with none', registry);
    return registry;
}

function staticAudit(suffixes) {
    const source = relative => fs.readFileSync(path.join(ROOT, relative), 'utf8');
    const tooltip = source('launcher/web/modules/tooltip.js');
    const css = source('launcher/web/css/panels/foundation-rest.css');
    const bootTooltip = source('launcher/web/modules/boot-tooltip.js');
    const welcomeCss = source('launcher/web/css/welcome.css');
    const notch = source('launcher/web/modules/notch.js');
    const overlayCss = source('launcher/web/css/overlay.css');
    const kshop = source('launcher/web/modules/kshop-tooltip-presenter.js');
    const workbench = source('launcher/web/modules/workbench-primitives.js');
    const intelligence = source('launcher/web/modules/intelligence-panel.js');
    const denseConsumers = [
        'launcher/web/modules/character-build-view.js',
        'launcher/web/modules/character-build/character-build-candidate-tooltip.js',
        'launcher/web/modules/crafting.js',
        'launcher/web/modules/equipment-tuning-view.js',
        'launcher/web/modules/intelligence-panel.js',
        'launcher/web/modules/inventory-storage-workbench.js',
        'launcher/web/modules/kshop.js',
        'launcher/web/modules/loot/loot-view.js',
        'launcher/web/modules/merc-panel.js',
        'launcher/web/modules/npcshop.js',
        'launcher/web/modules/skills.js',
        'launcher/web/modules/tasks/task-panel.js',
        'launcher/web/modules/arena/arena-challenge-browser.js'
    ];
    const simpleConsumers = [
        'launcher/web/modules/arena/arena-custom-editor.js',
        'launcher/web/modules/loot/loot-organizer.js',
        'launcher/web/modules/merc-panel.js',
        'launcher/web/modules/pet-panel.js'
    ];
    const checks = [
        [tooltip.includes("var PROFILE_SIMPLE = 'simple-tooltip'"), 'simple-tooltip profile missing'],
        [tooltip.includes("var PROFILE_DENSE = 'dense-inspect'"), 'dense-inspect profile missing'],
        [tooltip.includes("var PROFILE_PINNED = 'pinned-inspector'"), 'pinned-inspector profile missing'],
        [tooltip.includes('function showPinned('), 'showPinned API missing'],
        [css.includes('#panel-tooltip[data-tooltip-profile="dense-inspect"]'), 'dense-inspect CSS missing'],
        [css.includes('#panel-tooltip[data-tooltip-profile="pinned-inspector"]'), 'pinned-inspector CSS missing'],
        [/#panel-tooltip\[data-tooltip-profile="pinned-inspector"\]\s*\{[^}]*pointer-events\s*:\s*auto/s.test(css),
            'pinned inspector is not independently interactive'],
        [/#panel-tooltip\[data-tooltip-profile="pinned-inspector"\]\s*\{[^}]*padding\s*:\s*0/s.test(css),
            'pinned inspector outer box still inflates beyond its viewport cap'],
        [kshop.includes('PanelTooltip.showPinned'), 'KShop explicit detail does not use pinned inspector'],
        [kshop.includes("placement:'right'"), 'KShop pinned inspector does not use its fixed right rail'],
        [bootTooltip.includes('var DELAY = 300'), 'BootTooltip short-hint delay changed without audit'],
        [bootTooltip.includes('layer.textContent = text'), 'BootTooltip no longer uses text-only projection'],
        [/\.boot-tooltip\s*\{[^}]*pointer-events\s*:\s*none/s.test(welcomeCss), 'BootTooltip can intercept pointer input'],
        [notch.includes('function buildTooltipHTML(fps, idx)'), 'Sparkline numeric tooltip source missing'],
        [/\.spark-tooltip\s*\{[^}]*pointer-events\s*:\s*none/s.test(overlayCss), 'Sparkline tooltip can intercept pointer input'],
        [workbench.includes('balance-tooltip-meta'), 'Workbench balance suffix source missing'],
        [intelligence.includes('已发现 ') && intelligence.includes(' 页</div>'), 'Intelligence page-count suffix source missing'],
        [kshop.includes('flash-tt-lock-banner kshop-tt-lock-banner'), 'KShop lock suffix source missing']
    ];
    for (const relative of denseConsumers) {
        const consumerSource = source(relative);
        checks.push([consumerSource.includes('dense-inspect'), relative + ' is not on dense-inspect']);
        checks.push([!/(?:PanelTooltip|tooltipBinder)\.(?:showAtMouse|followMouse|hideHover)\s*\(/.test(consumerSource),
            relative + ' still owns legacy floating-tooltip pointer choreography']);
        checks.push([!/(?:\btitle=["']|\.title\s*=|\.setAttribute\(\s*["']title["']\s*,)[^\r\n;]*(?:introHTML|descHTML)/.test(consumerSource),
            relative + ' routes dense tooltip body into native title']);
    }
    for (const relative of simpleConsumers) {
        checks.push([source(relative).includes('simple-tooltip'), relative + ' does not explicitly retain simple-tooltip']);
    }
    const suffixText = JSON.stringify(suffixes);
    checks.push([suffixText.includes('balance-tooltip-meta'), 'balance suffix is absent from registry']);
    checks.push([suffixText.includes('已发现 12 / 12 页'), 'intelligence suffix is absent from registry']);
    checks.push([suffixText.includes('flash-tt-lock-banner kshop-tt-lock-banner'), 'lock suffix is absent from registry']);
    const failures = checks.filter(check => !check[0]).map(check => check[1]);
    assert(failures.length === 0, 'Static tooltip contract audit failed', failures);
    const productionRoots = [path.join(ROOT, 'launcher', 'web', 'bootstrap.html'), path.join(ROOT, 'launcher', 'web', 'overlay.html')];
    function collectProductionSources(directory) {
        for (const entry of fs.readdirSync(directory, {withFileTypes:true})) {
            if (entry.name === 'dev' || entry.name === 'lib') continue;
            const absolute = path.join(directory, entry.name);
            if (entry.isDirectory()) collectProductionSources(absolute);
            else if (/\.(?:js|html)$/i.test(entry.name)) productionRoots.push(absolute);
        }
    }
    collectProductionSources(path.join(ROOT, 'launcher', 'web', 'modules'));
    const nativeTitleFiles = productionRoots.map(filename => {
        const text = fs.readFileSync(filename, 'utf8');
        // Attribute literals deliberately require no whitespace before '=' so
        // local declarations such as `var title = '...'` are not inventory hits.
        const attributeBindings = (text.match(/(?:^|[\s<])title=["']/gm) || []).length;
        const propertyBindings = (text.match(/\.title\s*=/g) || []).length;
        const setAttributeBindings = (text.match(/\.setAttribute\(\s*["']title["']\s*,/g) || []).length;
        return {
            file:path.relative(ROOT, filename).replace(/\\/g, '/'),
            bindings:attributeBindings + propertyBindings + setAttributeBindings
        };
    }).filter(entry => entry.bindings > 0);
    const nativeTitleBindings = nativeTitleFiles.reduce((count, entry) => count + entry.bindings, 0);
    return {
        passed:checks.length,total:checks.length,failures,
        inventory:{
            panelTooltipDenseConsumers:denseConsumers.length,
            panelTooltipSimpleConsumers:simpleConsumers.length,
            auxiliaryHosts:['BootTooltip','spark-tooltip','native-title'],
            nativeTitleBindings,
            nativeTitleFiles
        }
    };
}

function percentile(values, ratio) {
    if (!values.length) return 0;
    const sorted = values.slice().sort((a, b) => a - b);
    return Number(sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * ratio))].toFixed(2));
}

function concise(row) {
    return {
        identity:row.identity,id:row.id,name:row.name,variant:row.variant,type:row.type,
        use:row.use,suffix:row.suffix,width:Number(row.width.toFixed(2)),
        height:Number(row.height.toFixed(2)),scrollable:row.scrollable,
        descScrollHeight:row.descScrollHeight,descClientHeight:row.descClientHeight,
        overlapTiles:row.overlapTiles,overlapPixels:Number(row.overlapPixels.toFixed(2)),
        anchorOverlap:Number(row.anchorOverlap.toFixed(2)),placement:row.placement
    };
}

function pushWorst(list, row, metric, limit) {
    list.push(concise(row));
    list.sort((a, b) => Number(b[metric]) - Number(a[metric]));
    if (list.length > limit) list.length = limit;
}

function createBucket(meta) {
    return Object.assign({
        count:0,insideViewportFailures:0,pointerHitFailures:0,pointerEventFailures:0,
        profileFailures:0,scrollable:0,stacked:0,split:0,overlapCases:0,
        anchorOverlapCases:0,widths:[],heights:[],descHeights:[],worstHeight:[],
        worstOverlap:[],failureExamples:[]
    }, meta);
}

function absorb(bucket, row) {
    bucket.count += 1;
    bucket.widths.push(row.width);
    bucket.heights.push(row.height);
    bucket.descHeights.push(row.descScrollHeight);
    if (!row.insideViewport) bucket.insideViewportFailures += 1;
    if (!row.pointerHitsAnchor) bucket.pointerHitFailures += 1;
    if (row.pointerEvents !== 'none') bucket.pointerEventFailures += 1;
    if (row.profile !== 'dense-inspect') bucket.profileFailures += 1;
    if (row.scrollable) bucket.scrollable += 1;
    if (row.stacked) bucket.stacked += 1;
    if (row.split) bucket.split += 1;
    if (row.overlapTiles > 0) bucket.overlapCases += 1;
    if (row.anchorOverlap > .5) bucket.anchorOverlapCases += 1;
    pushWorst(bucket.worstHeight, row, 'height', 8);
    pushWorst(bucket.worstOverlap, row, 'overlapPixels', 8);
    if ((!row.insideViewport || !row.pointerHitsAnchor || row.pointerEvents !== 'none'
            || row.profile !== 'dense-inspect') && bucket.failureExamples.length < 16) {
        bucket.failureExamples.push(concise(row));
    }
}

function finishBucket(bucket) {
    const result = Object.assign({}, bucket, {
        width:{p50:percentile(bucket.widths,.5),p90:percentile(bucket.widths,.9),p99:percentile(bucket.widths,.99),max:percentile(bucket.widths,1)},
        height:{p50:percentile(bucket.heights,.5),p90:percentile(bucket.heights,.9),p99:percentile(bucket.heights,.99),max:percentile(bucket.heights,1)},
        descScrollHeight:{p50:percentile(bucket.descHeights,.5),p90:percentile(bucket.descHeights,.9),p99:percentile(bucket.descHeights,.99),max:percentile(bucket.descHeights,1)}
    });
    delete result.widths;
    delete result.heights;
    delete result.descHeights;
    return result;
}

async function measureItemMatrix(page, corpus, suffixId, bucket, globalBucket) {
    for (let offset = 0; offset < corpus.records.length; offset += BATCH_SIZE) {
        const batch = corpus.records.slice(offset, offset + BATCH_SIZE);
        const rows = await page.evaluate(({records,suffix}) => window.__tooltipAudit.measureItems(records, suffix), {
            records:batch,suffix:suffixId
        });
        for (const row of rows) {
            absorb(bucket, row);
            absorb(globalBucket, row);
        }
    }
}

function createPinnedBucket(meta) {
    return Object.assign({
        count:0,insideViewportFailures:0,pointerEventFailures:0,profileFailures:0,
        scrollable:0,widths:[],heights:[],bodyHeights:[],placements:{},failureExamples:[]
    }, meta);
}

function absorbPinned(bucket, row) {
    bucket.count += 1;
    bucket.widths.push(row.width);
    bucket.heights.push(row.height);
    bucket.bodyHeights.push(row.bodyScrollHeight);
    if (!row.insideViewport) bucket.insideViewportFailures += 1;
    if (row.pointerEvents !== 'auto') bucket.pointerEventFailures += 1;
    if (row.profile !== 'pinned-inspector') bucket.profileFailures += 1;
    if (row.bodyScrollable) bucket.scrollable += 1;
    bucket.placements[row.placement] = (bucket.placements[row.placement] || 0) + 1;
    if ((!row.insideViewport || row.pointerEvents !== 'auto'
            || row.profile !== 'pinned-inspector') && bucket.failureExamples.length < 16) {
        bucket.failureExamples.push(row);
    }
}

function finishPinnedBucket(bucket) {
    const result = Object.assign({}, bucket, {
        width:{p50:percentile(bucket.widths,.5),p90:percentile(bucket.widths,.9),p99:percentile(bucket.widths,.99),max:percentile(bucket.widths,1)},
        height:{p50:percentile(bucket.heights,.5),p90:percentile(bucket.heights,.9),p99:percentile(bucket.heights,.99),max:percentile(bucket.heights,1)},
        bodyScrollHeight:{p50:percentile(bucket.bodyHeights,.5),p90:percentile(bucket.bodyHeights,.9),p99:percentile(bucket.bodyHeights,.99),max:percentile(bucket.bodyHeights,1)}
    });
    delete result.widths;
    delete result.heights;
    delete result.bodyHeights;
    return result;
}

async function measurePinnedMatrix(page, corpus, suffixId, bucket, globalBucket) {
    for (let offset = 0; offset < corpus.records.length; offset += BATCH_SIZE) {
        const batch = corpus.records.slice(offset, offset + BATCH_SIZE);
        const rows = await page.evaluate(({records,suffix}) => window.__tooltipAudit.measurePinnedItems(records, suffix), {
            records:batch,suffix:suffixId
        });
        for (const row of rows) {
            absorbPinned(bucket, row);
            absorbPinned(globalBucket, row);
        }
    }
}

async function measureSkillMatrix(page, bucket, globalBucket) {
    const rows = await page.evaluate(() => window.__tooltipAudit.measureSkills());
    for (const row of rows) {
        absorb(bucket, row);
        absorb(globalBucket, row);
    }
    return rows.length;
}

function markdown(report) {
    const lines = [];
    lines.push('# Tooltip 全量排版审计');
    lines.push('');
    lines.push('- 语料：' + report.corpus.summary.records + ' 条实际物品变体（全部基础物品 / 合法 tier / 每装备 1 与 3 插件宿主形态 / 每个插件定义至少一条合法安装路径）。');
    lines.push('- 插件：' + report.corpus.summary.modsCovered + ' / ' + report.corpus.summary.modDefinitions + ' 个正式定义具有实际安装语料，未覆盖 0。');
    lines.push('- 技能：' + report.coverage.skillSourceCount + ' 条实际 `skills.xml` 输入。');
    lines.push('- 使用面：' + report.static.inventory.panelTooltipDenseConsumers + ' 个 dense consumer 文件、'
        + report.static.inventory.panelTooltipSimpleConsumers + ' 个显式 simple consumer 文件；另盘点 BootTooltip、spark-tooltip 与 '
        + report.static.inventory.nativeTitleBindings + ' 处 production native title 属性绑定。');
    lines.push('- 矩阵：3 个视口 × 2 种网格密度 × ' + report.suffixes.length + ' 种实际 Web 后缀。');
    lines.push('- 实测：物品 ' + report.coverage.measuredItems + ' 次，技能 ' + report.coverage.measuredSkills + ' 次。');
    lines.push('- 固定检视器：物品 ' + report.coverage.measuredPinnedItems + ' 次；视口越界 '
        + report.pinned.insideViewportFailures + '，pointer-events/profile 错误 '
        + (report.pinned.pointerEventFailures + report.pinned.profileFailures)
        + '，需要检视器自身滚动 ' + report.pinned.scrollable + ' 次。');
    lines.push('- 几何硬失败：视口越界 ' + report.global.insideViewportFailures
        + '，鼠标热点失守 ' + report.global.pointerHitFailures
        + '，hit-test/profile 错误 ' + (report.global.pointerEventFailures + report.global.profileFailures) + '。');
    lines.push('- 内容约束：需要滚动 ' + report.global.scrollable + ' 次；覆盖相邻格 ' + report.global.overlapCases
        + ' 次，但 dense-inspect 浮层不参与命中，因此不阻断扫格。');
    lines.push('');
    lines.push('| 类别 | 视口 | 密度 | 后缀 | 数量 | 越界 | 可滚动 | stacked | 覆盖格 | 高度 p99/max |');
    lines.push('|---|---:|---|---|---:|---:|---:|---:|---:|---:|');
    for (const row of report.matrices) {
        lines.push('| ' + row.kind + ' | ' + row.viewport + ' | ' + row.density + ' | ' + row.suffix
            + ' | ' + row.count + ' | ' + row.insideViewportFailures + ' | ' + row.scrollable
            + ' | ' + row.stacked + ' | ' + row.overlapCases + ' | ' + row.height.p99 + '/' + row.height.max + ' |');
    }
    lines.push('');
    lines.push('## 最高样本');
    lines.push('');
    for (const row of report.global.worstHeight.slice(0, 12)) {
        lines.push('- ' + row.identity + '：' + row.height + 'px，' + row.name + '，' + row.variant + '，' + row.suffix);
    }
    lines.push('');
    lines.push('报告为临时验证产物，不进入版本库。');
    return lines.join('\n') + '\n';
}

async function run() {
    assert(fs.existsSync(CORPUS_PATH), 'Parsed tooltip corpus is missing; run tools/parse-tooltip-corpus.js first', CORPUS_PATH);
    const corpus = JSON.parse(fs.readFileSync(CORPUS_PATH, 'utf8'));
    assert(corpus.schema === 'cf7.tooltip-corpus.v1' && Array.isArray(corpus.records) && corpus.records.length > 0,
        'Tooltip corpus schema is invalid');
    const suffixes = readSuffixRegistry();
    const staticResult = staticAudit(suffixes);
    const executablePath = edgePath();
    assert(executablePath, 'Microsoft Edge executable not found');
    const server = await startServer(ROOT);
    const browser = await chromium.launch({executablePath,headless:true});
    const matrices = [];
    const globalBucket = createBucket({kind:'all',viewport:'all',density:'all',suffix:'all'});
    const pinnedMatrices = [];
    const pinnedGlobalBucket = createPinnedBucket({kind:'pinned',viewport:'all',suffix:PINNED_SUFFIX});
    const pageErrors = [];
    let skillSourceCount = null;
    try {
        const page = await browser.newPage({viewport:{width:VIEWPORTS[0].width,height:VIEWPORTS[0].height}});
        page.on('pageerror', error => pageErrors.push(String(error && error.stack || error)));
        for (const viewport of VIEWPORTS) {
            await page.setViewportSize({width:viewport.width,height:viewport.height});
            await page.goto(server.url + FIXTURE_URL, {waitUntil:'load'});
            await page.waitForFunction(() => window.__tooltipAuditReady === true || !!window.__tooltipAuditError);
            const fixtureError = await page.evaluate(() => window.__tooltipAuditError || '');
            assert(!fixtureError, 'Tooltip audit fixture failed', fixtureError);
            const fixtureSuffixes = await page.evaluate(() => window.__tooltipAudit.suffixes());
            assert(JSON.stringify(fixtureSuffixes) === JSON.stringify(suffixes.map(entry => entry.id)),
                'Runner/fixture suffix registry mismatch', {fixtureSuffixes,suffixes});
            const currentSkillCount = await page.evaluate(() => window.__tooltipAudit.skills().length);
            if (skillSourceCount == null) skillSourceCount = currentSkillCount;
            assert(currentSkillCount === skillSourceCount && currentSkillCount > 0,
                'Skill corpus is empty or unstable', {skillSourceCount,currentSkillCount});

            for (const density of DENSITIES) {
                await page.evaluate(value => window.__tooltipAudit.configure(value), density);
                for (const suffix of suffixes) {
                    const bucket = createBucket({kind:'item',viewport:viewport.id,density,suffix:suffix.id});
                    await measureItemMatrix(page, corpus, suffix.id, bucket, globalBucket);
                    assert(bucket.count === corpus.records.length, 'Item matrix coverage mismatch', bucket);
                    matrices.push(finishBucket(bucket));
                }
                const skillBucket = createBucket({kind:'skill',viewport:viewport.id,density,suffix:'none'});
                const measuredSkills = await measureSkillMatrix(page, skillBucket, globalBucket);
                assert(measuredSkills === skillSourceCount, 'Skill matrix coverage mismatch', skillBucket);
                matrices.push(finishBucket(skillBucket));
            }
            const pinnedBucket = createPinnedBucket({kind:'pinned',viewport:viewport.id,suffix:PINNED_SUFFIX});
            await measurePinnedMatrix(page, corpus, PINNED_SUFFIX, pinnedBucket, pinnedGlobalBucket);
            assert(pinnedBucket.count === corpus.records.length, 'Pinned item matrix coverage mismatch', pinnedBucket);
            pinnedMatrices.push(finishPinnedBucket(pinnedBucket));
        }
        await page.close();
    } finally {
        await browser.close();
        await stopServer(server);
    }
    assert(pageErrors.length === 0, 'Tooltip audit browser errors', pageErrors);

    const measuredItems = matrices.filter(row => row.kind === 'item').reduce((sum, row) => sum + row.count, 0);
    const measuredSkills = matrices.filter(row => row.kind === 'skill').reduce((sum, row) => sum + row.count, 0);
    const expectedItems = corpus.records.length * VIEWPORTS.length * DENSITIES.length * suffixes.length;
    const expectedSkills = skillSourceCount * VIEWPORTS.length * DENSITIES.length;
    const measuredPinnedItems = pinnedGlobalBucket.count;
    const expectedPinnedItems = corpus.records.length * VIEWPORTS.length;
    assert(measuredItems === expectedItems && measuredSkills === expectedSkills
            && measuredPinnedItems === expectedPinnedItems,
        'Global tooltip audit coverage mismatch', {
            measuredItems,expectedItems,measuredSkills,expectedSkills,
            measuredPinnedItems,expectedPinnedItems
        });
    const global = finishBucket(globalBucket);
    const pinned = finishPinnedBucket(pinnedGlobalBucket);
    const report = {
        schema:'cf7.tooltip-layout-audit.v1',generatedAt:new Date().toISOString(),browser:'edge',
        executablePath,static:staticResult,corpus:{summary:corpus.summary,stats:corpus.stats},
        viewports:VIEWPORTS,densities:DENSITIES,suffixes:suffixes.map(entry => entry.id),
        coverage:{expectedItems,measuredItems,expectedSkills,measuredSkills,skillSourceCount,
            expectedPinnedItems,measuredPinnedItems},
        global,pinned,matrices,pinnedMatrices,pageErrors
    };
    fs.mkdirSync(REPORT_DIR, {recursive:true});
    fs.writeFileSync(REPORT_JSON, JSON.stringify(report, null, 2), 'utf8');
    fs.writeFileSync(REPORT_MD, markdown(report), 'utf8');
    assert(global.insideViewportFailures === 0, 'Tooltip layouts escaped the viewport', global.failureExamples);
    assert(global.pointerHitFailures === 0, 'Dense tooltip blocked its source anchor', global.failureExamples);
    assert(global.pointerEventFailures === 0 && global.profileFailures === 0,
        'Dense tooltip profile/hit-test contract failed', global.failureExamples);
    assert(pinned.insideViewportFailures === 0, 'Pinned inspectors escaped the viewport', pinned.failureExamples);
    assert(pinned.pointerEventFailures === 0 && pinned.profileFailures === 0,
        'Pinned inspector interaction contract failed', pinned.failureExamples);
    return report;
}

if (require.main === module) {
    run().then(report => {
        process.stdout.write(JSON.stringify({
            schema:report.schema,static:report.static,coverage:report.coverage,
            failures:{insideViewport:report.global.insideViewportFailures,
                pointerHit:report.global.pointerHitFailures,
                pointerEvents:report.global.pointerEventFailures,profile:report.global.profileFailures},
            constraints:{scrollable:report.global.scrollable,stacked:report.global.stacked,
                overlapCases:report.global.overlapCases,anchorOverlapCases:report.global.anchorOverlapCases},
            pinned:{count:report.pinned.count,insideViewport:report.pinned.insideViewportFailures,
                pointerEvents:report.pinned.pointerEventFailures,profile:report.pinned.profileFailures,
                scrollable:report.pinned.scrollable},
            reportJson:REPORT_JSON,reportMarkdown:REPORT_MD
        }, null, 2) + '\n');
    }).catch(error => {
        console.error(error && error.stack || String(error));
        if (error && error.evidence) console.error(JSON.stringify(error.evidence, null, 2));
        process.exitCode = 1;
    });
}

module.exports = {run,staticAudit};
