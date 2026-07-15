#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');

function parseArgs(argv) {
    const args = { browser: 'edge', headed: false, viewport: '' };
    for (let i = 0; i < argv.length; i += 1) {
        if (argv[i] === '--browser') args.browser = argv[++i] || 'edge';
        else if (argv[i] === '--viewport') args.viewport = argv[++i] || '';
        else if (argv[i] === '--headed') args.headed = true;
        else if (argv[i] === '--help' || argv[i] === '-h') {
            console.log('usage: node tools/run-skills-harness.js [--browser edge|chrome] [--viewport 1366x768] [--headed]');
            process.exit(0);
        } else throw new Error('unknown argument: ' + argv[i]);
    }
    return args;
}

function read(relative) { return fs.readFileSync(path.join(ROOT, relative), 'utf8'); }

function staticAudit() {
    const panel = read('launcher/web/modules/skills.js');
    const runtime = read('launcher/web/modules/skills-runtime.js');
    const workbench = read('launcher/web/modules/workbench.js');
    const panels = read('launcher/web/modules/panels.js');
    const registry = read('launcher/web/modules/panels-lazy-registry.js');
    const css = read('launcher/web/css/panels.css');
    const build = read('launcher/build.ps1');
    if (!panel.includes("Panels.register('skills'") || !panel.includes('new Workbench.DualPaneShell')) throw new Error('skills production panel registration/shell missing');
    if (!panel.includes("writeCommand('equip'") || !panel.includes("writeCommand('learnCommit'") || !panel.includes('expectedLearnToken')) throw new Error('skill manage/trainer write flow missing');
    if (!panel.includes('function handleTrainerExpired') || !panel.includes('requestClose();')) throw new Error('trainer capability expiry must close and require a fresh dialogue');
    if (!panel.includes("panel:'skills', cmd:'close', panelInstanceId") || !panel.includes('onRebind: onRebind')) throw new Error('instance-bound close or rebind missing');
    if (!panel.includes("cmd:'switch_manage'") || !panel.includes('focusSkillKey') || !panel.includes('skills-switch-manage-btn')) throw new Error('trainer to manage rebind UX/contract missing');
    if (!panel.includes("cmd:'switch_trainer'") || !panel.includes('canReturnTrainer') || !panel.includes('skills-switch-trainer-btn')) throw new Error('scoped manage to trainer return UX/contract missing');
    if (!panel.includes('PanelTooltip.bindAsyncHover') || !panel.includes('PanelTooltip.buildItemRichHtml') || !panel.includes('normalizeAS2Description')) throw new Error('skills must use the shared sanitized annotation system');
    if (!panel.includes('new Workbench.GridDensityController') || !panel.includes("compactClass:'skills-density-compact'")) throw new Error('skills full/compact density controller missing');
    if (!panel.includes('new Workbench.PointerDragController') || !panel.includes('new Workbench.InteractionBroker') || !panel.includes('skills-drag-ghost')) throw new Error('shared skills drag interaction missing');
    if (!panel.includes('new ItemFilter.FilterNavigator') || !panel.includes('skillFilterDefinitions')
        || !panel.includes('filterPathsForView') || !panel.includes('matchesSkillFilter')) throw new Error('direct composable skill facet integration missing');
    if (!panel.includes('function setSearchExpanded') || !panel.includes("event.key !== '/'") || !panel.includes('skills-search-toggle')) throw new Error('on-demand skill search/keyboard entry missing');
    if (!panel.includes('function openHelp') || !panel.includes("kind:'skills-help'") || !panel.includes('skills-help-btn')) throw new Error('contextual skill help modal missing');
    if (!panel.includes('cf7.skills.loadoutConfirmationMode') || !panel.includes('manageHelpDetail')
        || !panel.includes("_loadoutConfirmationMode === 'fast'") || !panel.includes("kind:'skills-learn-confirm'")) throw new Error('scoped safe/fast loadout confirmation preference missing');
    if (!panel.includes('function buildDiagnosticRecord') || !panel.includes('redactDiagnosticValue') || !panel.includes('snapshotDiagnostics') || !panel.includes('skills-header-diagnostic')) throw new Error('exception-only player diagnostic copy/redaction missing');
    if (panel.includes("setMetric('revision'") || panel.includes("setStatus('权威状态已同步'")) throw new Error('routine technical skill chrome must stay hidden from players');
    if (/domain\s*:\s*['"]inventory['"]/.test(panel) || /domain\s*:\s*['"]inventory['"]/.test(runtime)) throw new Error('skills must not call the item-grid domain');
    if (!runtime.includes("state = 'needs_reconcile'") || !runtime.includes('reconcileAfterCallId') || !runtime.includes('lastAppliedWriteEpoch')) throw new Error('explicit Skill reconcile/watermark contract missing');
    if (!runtime.includes("payload: clonePayload(payload)") || !runtime.includes("panel: 'skills'") || !runtime.includes("domain: 'skills'") || !runtime.includes('panelInstanceId: entry.panelInstanceId')) throw new Error('strict instance-bound nested skills envelope missing');
    if (!panels.includes('activePanel.onRebind(activePanel._el, initData)')) throw new Error('Panels same-name rebind hook missing');
    if (!panels.includes("pending.id === 'skills'") || !panels.includes('closeMessage.panelInstanceId')) throw new Error('skills lazy-cancel must use the instance-bound exact close envelope');
    if (!registry.includes("registerLazy('skills'") || !registry.includes("'modules/item-filter.js'") || !registry.includes("'modules/skills-runtime.js'")) throw new Error('skills lazy registry/filter dependency missing');
    if (!workbench.includes("gesture.target.accepted === false") || !workbench.includes('this.compactClass')) throw new Error('shared drag rejection/custom density hooks missing');
    if (!panel.includes("operationId:'reorder_skill'") || !panel.includes('adjacentVisibleEntry')
        || !panel.includes("reorderBlockReason(source, 'source')") || !panel.includes("reorderBlockReason(target, 'target')")
        || panel.includes("button('上移'") || panel.includes("button('下移'")) throw new Error('skill tile swap/keyboard fallback contract missing');
    if (!css.includes('#panel-container[data-panel="skills"] #panel-content') || !css.includes('grid-template-columns:repeat(12,64px)')
        || !css.includes('.skills-density-compact') || !css.includes('--workbench-compact-tile-size:48px')
        || !css.includes('.skills-slot-icon { width:48px; height:48px; box-sizing:border-box') || !css.includes('.skills-slot:focus-within .skills-slot-clear')
        || !css.includes('.skills-slot:focus-within .skills-slot-level') || css.includes('.skills-slot.selected .skills-slot-clear')
        || !css.includes('.skills-library-row.workbench-drop-active')
        || !css.includes('.skills-filter-board') || !css.includes('.skills-filter-group') || !css.includes('.skills-tooltip')
        || !css.includes('.skills-library-controls[hidden]') || !css.includes('.skills-header-diagnostic')
        || !css.includes('.skills-panel .workbench-slot-marker') || !css.includes('data-modal-kind="skills-help"')) throw new Error('skills band/tile/tooltip/filter/search/diagnostic/help CSS missing');
    if (/\.skills-density-compact\s+\.skills-(?:loadout|slot)/.test(css)) throw new Error('skill-library density must not resize the fixed gameplay hotbar');
    if (!build.includes('"modules\\skills-runtime.js"') || !build.includes('"modules\\skills.js"')) throw new Error('launcher build required asset list missing skills');
}

function browserPath(name) {
    const chrome = name === 'chrome';
    const candidates = chrome ? [
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Google', 'Chrome', 'Application', 'chrome.exe')
    ] : [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : ''
    ];
    const found = candidates.find(candidate => candidate && fs.existsSync(candidate));
    if (!found) throw new Error('Cannot find ' + name + ' executable.');
    return found;
}

function parseViewport(value) {
    const match = String(value || '').match(/^(\d+)x(\d+)$/);
    if (!match) throw new Error('invalid viewport: ' + value);
    return { width: Number(match[1]), height: Number(match[2]), label: value };
}

function serve() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(WEB, pathname));
            const relative = path.relative(WEB, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) { response.writeHead(403); response.end(); return; }
            fs.readFile(file, (error, data) => {
                if (error) { response.writeHead(404); response.end(); return; }
                const ext = path.extname(file);
                const type = ext === '.html' ? 'text/html; charset=utf-8' : ext === '.css' ? 'text/css; charset=utf-8'
                    : ext === '.js' ? 'text/javascript; charset=utf-8' : 'application/octet-stream';
                response.writeHead(200, {'Content-Type': type}); response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function runViewport(browser, server, viewport) {
    const page = await browser.newPage({viewport});
    const pageErrors = [], failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message || String(error)));
    page.on('requestfailed', request => failedRequests.push(request.url()));
    await page.goto(`http://127.0.0.1:${server.address().port}/modules/skills/dev/harness.html`, {waitUntil:'load'});
    await page.waitForFunction(() => window.__qaDone === true, null, {timeout:20000});
    const state = await page.evaluate(() => ({result:window.__qaResult,error:window.__qaError}));
    await page.close();
    if (state.error) throw new Error(viewport.label + ': ' + state.error);
    if (pageErrors.length) throw new Error(viewport.label + ' page errors: ' + pageErrors.join(' | '));
    if (failedRequests.length) throw new Error(viewport.label + ' failed requests: ' + failedRequests.join(' | '));
    const bad = state.result && state.result.checks ? state.result.checks.filter(check => !check.ok) : [];
    if (!state.result || state.result.passed !== state.result.total) throw new Error(viewport.label + ' harness failed: ' + JSON.stringify(bad));
    return state.result;
}

(async function main() {
    const args = parseArgs(process.argv.slice(2));
    staticAudit();
    if (!fs.existsSync(PLAYWRIGHT)) throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    const {chromium} = require(PLAYWRIGHT);
    const executablePath = browserPath(args.browser);
    const viewports = (args.viewport ? [args.viewport] : ['1024x576','1366x768','1920x1080']).map(parseViewport);
    const server = await serve();
    const browser = await chromium.launch({executablePath,headless:!args.headed});
    const results = [];
    try {
        for (const viewport of viewports) results.push(await runViewport(browser, server, viewport));
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
    const cases = results[0] ? results[0].total : 0;
    console.log(`Skills harness ${cases}/${cases} passed across ${results.length} viewport(s): ${viewports.map(v => v.label).join(', ')}`);
})().catch(error => { console.error(error.stack || error); process.exit(1); });
