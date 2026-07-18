#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');
const vm = require('vm');
const {readCssBundle} = require('./lib/read-css-bundle.js');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');

function inOrder(source, fragments) {
    let cursor = 0;
    return fragments.every(fragment => {
        const index = source.indexOf(fragment, cursor);
        if (index < 0) return false;
        cursor = index + fragment.length;
        return true;
    });
}

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
    const library = read('launcher/web/modules/skills-library.js');
    const trainer = read('launcher/web/modules/skills-trainer.js');
    const loadout = read('launcher/web/modules/skills-loadout.js');
    const interactions = read('launcher/web/modules/skills-interactions.js');
    const renderer = read('launcher/web/modules/skills-render.js');
    const diagnostics = read('launcher/web/modules/skills-diagnostics.js');
    const skillsSource = [panel, library, trainer, loadout, interactions, renderer, diagnostics].join('\n');
    const panelService = read('scripts/类定义/org/flashNight/arki/skill/SkillPanelService.as');
    const panelServiceTest = read('scripts/类定义/org/flashNight/arki/skill/SkillPanelServiceTest.as');
    const loadoutService = read('scripts/类定义/org/flashNight/arki/skill/SkillLoadoutService.as');
    const loadoutServiceTest = read('scripts/类定义/org/flashNight/arki/skill/SkillLoadoutServiceTest.as');
    const bridge = read('launcher/web/modules/bridge.js');
    const runtime = read('launcher/web/modules/skills-runtime.js');
    const workbench = read('launcher/web/modules/workbench.js');
    const workbenchPrimitives = read('launcher/web/modules/workbench-primitives.js');
    const panels = read('launcher/web/modules/panels.js');
    const registry = read('launcher/web/modules/panels-lazy-registry.js');
    const css = readCssBundle(path.join(ROOT, 'launcher/web/css/panels.css'), {rootDir:path.join(ROOT, 'launcher/web/css')});
    const build = read('launcher/build.ps1');
    const releasePolicy = read('tools/validate-launcher-release-policy.ps1');
    if (!panel.includes("Panels.register('skills'") || !panel.includes('new Workbench.DualPaneShell')) throw new Error('skills production panel registration/shell missing');
    if (!panel.includes("writeCommand('equip'") || !panel.includes("writeCommand('learnCommit'") || !panel.includes('expectedLearnToken')) throw new Error('skill manage/trainer write flow missing');
    if (!panel.includes('function handleTrainerExpired') || !renderer.includes('function renderTrainerExpired')
        || !panel.includes("_trainerExpired = true") || !renderer.includes('返回游戏并重新对话')) throw new Error('trainer capability expiry must remain visible with explicit recovery');
    if (!panel.includes('function scheduleLearnPreview') || !panel.includes('function hasFreshPreviewToken')
        || panel.includes("button('计算消耗'")) throw new Error('trainer selection must auto-preview and refresh stale learn tokens without a routine calculate button');
    if (!renderer.includes("range.type = 'range'") || !panel.includes('function stageDesiredLevel')
        || !panel.includes('function targetMarkLevels') || !renderer.includes("value.type = 'number'")
        || skillsSource.includes("button('升 1 级'")) throw new Error('trainer target level must support exact discrete range/number selection without a redundant plus-one preset');
    if (!renderer.includes("result.classList.add('stale')") || !renderer.includes('appendPreviewUpdateStatus')
        || !renderer.includes('上次消耗')) throw new Error('target adjustment must retain and clearly mark the previous authority preview');
    if (!panelService.includes('lastTouchedAt') || !panelService.includes('session.lastTouchedAt = now()')
        || !panelServiceTest.includes('testSuccessfulReadRenewsTrainerLease') || !panelServiceTest.includes('testIdleTrainerLeaseExpires'))
        throw new Error('trainer capability must use a tested renewable idle lease');
    if (!panel.includes("panel:'skills', cmd:'close', panelInstanceId") || !panel.includes('onRebind: onRebind')) throw new Error('instance-bound close or rebind missing');
    if (!panel.includes("cmd:'switch_manage'") || !panel.includes('focusSkillKey') || !panel.includes('skills-switch-manage-btn')) throw new Error('trainer to manage rebind UX/contract missing');
    if (!panel.includes("cmd:'switch_trainer'") || !panel.includes('canReturnTrainer') || !panel.includes('skills-switch-trainer-btn')) throw new Error('scoped manage to trainer return UX/contract missing');
    if (!panel.includes('sent === false') || !panel.includes('function beginSwitchWait') || !panel.includes('switchPending:_switchPending')) throw new Error('skill switch transport/pending watchdog contract missing');
    if (!bridge.includes("typeof window.chrome.webview.postMessage !== 'function'") || !bridge.includes('return true;') || !bridge.includes('return false;')) throw new Error('Bridge.send boolean transport contract missing');
    if (!panel.includes('PanelTooltip.bindAsyncHover') || !renderer.includes('PanelTooltip.buildItemRichHtml') || !skillsSource.includes('normalizeAS2Description')) throw new Error('skills must use the shared sanitized annotation system');
    if (!panel.includes('new Workbench.GridDensityController') || !panel.includes("compactClass:'skills-density-compact'")) throw new Error('skills full/compact density controller missing');
    if (!panel.includes('new Workbench.PointerDragController') || !panel.includes('new Workbench.InteractionBroker') || !panel.includes('skills-drag-ghost')) throw new Error('shared skills drag interaction missing');
    if (!panel.includes("writeCommand('moveSlot'") || !runtime.includes('moveSlot: true') || !skillsSource.includes("operationId:'move_quick_slot'")
        || !skillsSource.includes("subjectKind:'quick_slot'") || !panel.includes("event.key !== 'ArrowLeft'")
        || !panelService.includes('skillMoveSlot') || !panelService.includes('executeWrite("moveSlot"')
        || !loadoutService.includes('function moveSlot') || !loadoutServiceTest.includes('testMoveSlotSwapsOccupied'))
        throw new Error('quick-slot atomic move/swap protocol and interaction missing');
    if (!panel.includes('new ItemFilter.FilterNavigator') || !panel.includes('skillFilterDefinitions')
        || !panel.includes('filterPathsForView') || !panel.includes('matchesSkillFilter')) throw new Error('direct composable skill facet integration missing');
    if (!panel.includes('function setSearchExpanded') || !panel.includes("event.key !== '/'") || !panel.includes('skills-search-toggle')) throw new Error('on-demand skill search/keyboard entry missing');
    if (!panel.includes('function openHelp') || !panel.includes("kind:'skills-help'") || !panel.includes('skills-help-btn')) throw new Error('contextual skill help modal missing');
    if (!panel.includes('cf7.skills.loadoutConfirmationMode') || !panel.includes('manageHelpDetail')
        || !panel.includes('createLoadoutConfirmationToggle') || !panel.includes('skills-confirmation-toggle')
        || panel.includes("id:'confirmation-mode'") || !panel.includes("_loadoutConfirmationMode === 'fast'")
        || !panel.includes("kind:'skills-learn-confirm'")) throw new Error('visible header safe/fast preference or learning confirmation boundary missing');
    if (!panel.includes('function buildDiagnosticRecord') || !panel.includes('redactDiagnosticValue')
        || !diagnostics.includes('snapshotDiagnostics') || !panel.includes('skills-header-diagnostic')) throw new Error('exception-only player diagnostic copy/redaction missing');
    if (panel.includes("setMetric('revision'") || panel.includes("setStatus('权威状态已同步'")) throw new Error('routine technical skill chrome must stay hidden from players');
    if (/domain\s*:\s*['"]inventory['"]/.test(panel) || /domain\s*:\s*['"]inventory['"]/.test(runtime)) throw new Error('skills must not call the item-grid domain');
    if (!runtime.includes("state = 'needs_reconcile'") || !runtime.includes('reconcileAfterCallId') || !runtime.includes('lastAppliedWriteEpoch')) throw new Error('explicit Skill reconcile/watermark contract missing');
    if (!runtime.includes("require('./panel-runtime.js')") || !runtime.includes('new PanelRuntime.PanelRequestMux')
        || !runtime.includes('payload:clonePayload(context.payload)') || !runtime.includes("panel:'skills'")
        || !runtime.includes("domain:'skills'") || !runtime.includes('panelInstanceId:context.session.panelInstanceId')) throw new Error('strict shared instance-bound nested skills envelope missing');
    if (!panels.includes('activePanel.onRebind(activePanel._el, initData)')) throw new Error('Panels same-name rebind hook missing');
    if (!panels.includes("pending.id === 'skills'") || !panels.includes('closeMessage.panelInstanceId')) throw new Error('skills lazy-cancel must use the instance-bound exact close envelope');
    const skillsRegistryStart = registry.indexOf("Panels.registerLazy('skills'");
    const skillsRegistryEnd = registry.indexOf('noop);', skillsRegistryStart);
    const skillsRegistry = skillsRegistryStart >= 0 && skillsRegistryEnd > skillsRegistryStart
        ? registry.slice(skillsRegistryStart, skillsRegistryEnd) : '';
    const requiredSkillsDependencies = [
        'modules/panel-runtime.js',
        'modules/workbench-lifecycle.js',
        'modules/workbench-focus.js',
        'modules/workbench-primitives.js',
        'modules/workbench.js',
        'modules/workbench-components.js',
        'modules/item-filter.js',
        'modules/skills-runtime.js',
        'modules/skills-library.js',
        'modules/skills-trainer.js',
        'modules/skills-loadout.js',
        'modules/skills-interactions.js',
        'modules/skills-render.js',
        'modules/skills-diagnostics.js',
        'modules/skills.js'
    ];
    const orderedSkillsDependencies = requiredSkillsDependencies.map(dependency => "'" + dependency + "'");
    if (!skillsRegistry || !inOrder(skillsRegistry, orderedSkillsDependencies)) {
        throw new Error('skills lazy registry dependency closure/order missing');
    }
    if (!workbenchPrimitives.includes("gesture.target.accepted === false")
        || !workbenchPrimitives.includes('this._allowInteractiveSource')
        || !workbench.includes('this.compactClass')) throw new Error('shared drag rejection/custom density hooks missing');
    if (!skillsSource.includes("operationId:'reorder_skill'") || !panel.includes('adjacentVisibleEntry')
        || !interactions.includes("blockReason(source, 'source')") || !interactions.includes("blockReason(target, 'target')")
        || panel.includes("button('上移'") || panel.includes("button('下移'")) throw new Error('skill tile swap/keyboard fallback contract missing');
    if (!panel.includes('SkillsPanel load order: item-filter.js, skills-library.js, skills-trainer.js, skills-loadout.js, skills-interactions.js, skills-render.js, skills-diagnostics.js, then skills.js.')
        || !library.includes('function visibleEntries') || !trainer.includes('function hasFreshPreviewToken')
        || !loadout.includes('function equipPlan') || !interactions.includes('function probeReorder')
        || !renderer.includes('function renderDetail') || !diagnostics.includes('function buildRecord'))
        throw new Error('skills feature modules or explicit browser load-order diagnosis missing');
    if (!css.includes('#panel-container[data-panel="skills"] #panel-content') || !css.includes('grid-template-columns:repeat(12,64px)')
        || !css.includes('.skills-density-compact') || !css.includes('--workbench-compact-tile-size:48px')
        || !css.includes('.skills-slot-icon { width:48px; height:48px; box-sizing:border-box') || !css.includes('.skills-slot:focus-within .skills-slot-clear')
        || !css.includes('.skills-slot:focus-within .skills-slot-level') || css.includes('.skills-slot.selected .skills-slot-clear')
        || !css.includes('.skills-slot.movable.dragging')
        || !css.includes('.skills-library-row.workbench-drop-active')
        || !css.includes('.skills-filter-board') || !css.includes('.skills-filter-group') || !css.includes('.skills-tooltip')
        || !css.includes('.skills-library-controls[hidden]') || !css.includes('.skills-header-diagnostic')
        || !css.includes('.skills-trainer-summary') || !css.includes('.skills-cost-card') || !css.includes('.skills-trainer-footer')
        || !css.includes('.skills-level-range') || !css.includes('.skills-level-mark') || !css.includes('.skills-level-value')
        || !css.includes('.skills-preview-result.stale') || !css.includes('.skills-preview-result.updating')
        || !css.includes('.skills-trainer-expired') || !css.includes('.skills-confirmation-toggle')
        || !css.includes('font:600 11px/1.1 Consolas,"Microsoft YaHei",sans-serif')
        || !css.includes('.skills-panel .workbench-slot-marker') || !css.includes('data-modal-kind="skills-help"')) throw new Error('skills band/tile/tooltip/filter/search/diagnostic/help CSS missing');
    if (/\.skills-density-compact\s+\.skills-(?:loadout|slot)/.test(css)) throw new Error('skill-library density must not resize the fixed gameplay hotbar');
    const requiredSkillsBuildAssets = requiredSkillsDependencies.map(dependency => dependency.replace(/\//g, '\\'));
    if (!build.includes('validate-launcher-release-policy.ps1')
        || requiredSkillsBuildAssets.some(asset => !releasePolicy.includes(asset))) {
        throw new Error('launcher release policy required asset list missing skills dependency');
    }
}

function bridgeSendAudit() {
    const source = read('launcher/web/modules/bridge.js');
    const end = source.indexOf('var OverlayViewportMetrics');
    if (end < 0) throw new Error('cannot isolate Bridge module for transport audit');
    const moduleSource = source.slice(0, end);

    function load(webview) {
        const context = {window:webview ? {chrome:{webview}} : {},console};
        vm.runInNewContext(moduleSource, context, {filename:'bridge.js'});
        return context.Bridge;
    }

    let delivered = null;
    const available = load({
        postMessage(message) { delivered = message; },
        addEventListener() {}
    });
    const sample = {type:'panel',cmd:'switch_manage'};
    if (available.send(sample) !== true || delivered !== sample) throw new Error('Bridge.send must return true after local WebView2 delivery');
    if (load(null).send(sample) !== false) throw new Error('Bridge.send must return false when WebView2 is unavailable');
    const throwing = load({postMessage() { throw new Error('transport down'); },addEventListener() {}});
    if (throwing.send(sample) !== false) throw new Error('Bridge.send must return false when postMessage throws');
    let callbackCount = 0;
    if (throwing.task('skills', {}, response => { if (response === null) callbackCount += 1; }) !== null || callbackCount !== 1) {
        throw new Error('Bridge.task must cleanly fail when local delivery throws');
    }
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
    bridgeSendAudit();
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
