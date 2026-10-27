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
    const css = readCssBundle(path.join(ROOT, 'launcher/web/css/panels.css'), {rootDir:path.join(ROOT, 'launcher/web')});
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
    if (!/panel:'skills',\s*cmd:'close',\s*panelInstanceId/.test(panel)
        || !panel.includes('onRebind: onRebind')) throw new Error('instance-bound close or rebind missing');
    if (!panel.includes("requestNavigation('manage')") || !interactions.includes("'switch_manage'")
        || !interactions.includes('focusSkillKey') || !panel.includes('skills-switch-manage-btn')) throw new Error('trainer to manage rebind UX/contract missing');
    if (!panel.includes("requestNavigation('trainer')") || !interactions.includes("'switch_trainer'") || !interactions.includes('canReturnTrainer')
        || !panel.includes('skills-switch-trainer-btn')) throw new Error('scoped manage to trainer return UX/contract missing');
    if (!interactions.includes('sent === false') || !panel.includes('function beginSwitchWait')
        || !panel.includes('switchPending:_switchPending')) throw new Error('skill switch transport/pending watchdog contract missing');
    if (!interactions.includes('function canReturnCharacterBuild') || !interactions.includes('canReturnCharacterBuild === true')
        || !interactions.includes('canReturnTrainer !== true') || !panel.includes('skills-return-character-btn')
        || !interactions.includes("reason:'navigate_character_build'")
        || !panel.includes("requestNavigation('character_build')")
        || !panel.includes('Interactions.requestNavigation({')) throw new Error('character-origin skills manage return capability/contract missing');
    if (!interactions.includes('shell && shell.hasModal()') || !interactions.includes("reason !== 'escape'")
        || !interactions.includes('if (context.searchExpanded)')
        || !interactions.includes('return popFilterPath(') || !panel.includes('Interactions.consumeClose(')
        || !panel.includes("function() { requestClose('header'); }")
        || !panel.includes("Bridge.send({type:'panel', panel:'skills', cmd:'close',")
        || !/panelInstanceId:panelInstanceId\}\)\s*===\s*false/.test(panel)
        || !panel.includes("技能面板保持打开"))
        throw new Error('skills close must consume modal, search and filter path before ordinary four-key panel close');
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
    if (!panel.includes('new WorkbenchComponents.HelpAction')
        || !panel.includes('function skillHelpSpec')
        || !panel.includes("kind:'skills-help'")
        || !panel.includes('skills-help-btn')) throw new Error('shared contextual skill HelpAction missing');
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
    const rebindStart = panels.indexOf('if (activePanel && activePanel.onRebind)');
    const rebindEnd = panels.indexOf('if (!rebindAccepted)', rebindStart);
    const rebindBody = rebindStart >= 0 && rebindEnd > rebindStart
        ? panels.slice(rebindStart, rebindEnd) : '';
    if (!rebindBody.includes('activePanel.onRebind(')
            || !rebindBody.includes('activePanel._el, initData')
            || !rebindBody.includes('catch (e)')) {
        throw new Error('Panels same-name rebind hook missing');
    }
    const panelCloseStart = panels.indexOf('function panelCloseMessage(');
    const panelCloseEnd = panels.indexOf('function hostOwnsPanelMount(', panelCloseStart);
    const panelCloseBody = panelCloseStart >= 0 && panelCloseEnd > panelCloseStart
        ? panels.slice(panelCloseStart, panelCloseEnd) : '';
    const pendingCancelStart = panels.indexOf('function cancelPendingOpen(');
    const pendingCancelEnd = panels.indexOf('function init()', pendingCancelStart);
    const pendingCancelBody = pendingCancelStart >= 0 && pendingCancelEnd > pendingCancelStart
        ? panels.slice(pendingCancelStart, pendingCancelEnd) : '';
    if (!panelCloseBody.includes("id === 'skills'")
        || !panelCloseBody.includes('closeMessage.panelInstanceId = readPanelInstanceId(initData)')
        || !panels.includes('return sendExactCloseNotification(id, initData, reason, context)')
        || !/sendPanelCloseNotification\(\s*pending\.id,\s*pending\.initData,\s*reason/.test(pendingCancelBody))
        throw new Error('skills lazy-cancel must use the instance-bound exact close envelope');
    const skillsRegistryStart = registry.indexOf("Panels.registerLazy('skills'");
    const skillsRegistryEnd = registry.indexOf('noop);', skillsRegistryStart);
    const skillsRegistry = skillsRegistryStart >= 0 && skillsRegistryEnd > skillsRegistryStart
        ? registry.slice(skillsRegistryStart, skillsRegistryEnd) : '';
    const requiredSkillsDependencies = [
        'modules/panel-runtime.js',
        'modules/workbench-lifecycle.js',
        'modules/workbench-focus.js',
        'modules/workbench-primitives.js',
        'modules/workbench-profile.js',
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
        || !css.includes('.skills-return-character-btn')
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

async function probeSemanticRejectMotion(page) {
    async function snapshot() {
        return page.evaluate(() => {
            let fixture = document.getElementById('skills-g3-motion-fixture');
            if (!fixture) {
                fixture = document.createElement('div');
                fixture.id = 'skills-g3-motion-fixture';
                fixture.className = 'workbench-shell';
                fixture.setAttribute('data-profile', 'library-decision');
                fixture.style.cssText = 'position:fixed;left:0;top:0;width:320px;height:80px;z-index:9999';
                const probe = document.createElement('div');
                probe.className = 'skills-library-row workbench-drop-rejected';
                probe.textContent = '拒绝状态仍可见';
                const role = document.createElement('span');
                role.setAttribute('data-reject-role-probe', '');
                role.style.cssText = 'position:absolute;color:var(--wb-role-reject)';
                fixture.appendChild(probe);
                fixture.appendChild(role);
                document.body.appendChild(fixture);
            }
            const probe = fixture.querySelector('.workbench-drop-rejected');
            const style = getComputedStyle(probe);
            const rect = probe.getBoundingClientRect();
            return {
                animationName:style.animationName,
                animationDuration:style.animationDuration,
                animationTimingFunction:style.animationTimingFunction,
                animationIterationCount:style.animationIterationCount,
                animationCount:typeof probe.getAnimations === 'function' ? probe.getAnimations().length : 0,
                outlineStyle:style.outlineStyle,
                outlineColor:style.outlineColor,
                roleColor:getComputedStyle(fixture.querySelector('[data-reject-role-probe]')).color,
                display:style.display,
                width:rect.width,
                height:rect.height,
                text:probe.textContent
            };
        });
    }

    await page.emulateMedia({reducedMotion:'no-preference'});
    const normal = await snapshot();
    await page.emulateMedia({reducedMotion:'reduce'});
    const reduced = await snapshot();
    await page.evaluate(() => {
        const fixture = document.getElementById('skills-g3-motion-fixture');
        if (fixture) fixture.remove();
    });
    await page.emulateMedia({reducedMotion:'no-preference'});
    return {
        normal,
        reduced,
        pass:normal.animationName === 'wb-reject-pulse'
            && normal.animationDuration === '0.25s'
            && normal.animationTimingFunction === 'cubic-bezier(0.2, 0.8, 0.25, 1)'
            && normal.animationIterationCount === '2'
            && normal.animationCount > 0
            && normal.outlineStyle !== 'none'
            && normal.display !== 'none' && normal.width > 0 && normal.height > 0
            && normal.text === '拒绝状态仍可见'
            && reduced.animationName === 'none'
            && reduced.animationDuration === '0s'
            && reduced.animationCount === 0
            && reduced.outlineStyle !== 'none'
            && reduced.outlineColor === reduced.roleColor
            && reduced.display !== 'none' && reduced.width > 0 && reduced.height > 0
            && reduced.text === '拒绝状态仍可见'
    };
}

async function probeSkillFeatures(page, viewport) {
    // Consume the production AS2 catalog, rather than maintaining a second feature list in the fixture.
    const registry = read('scripts/类定义/org/flashNight/arki/skill/SkillFeatureRegistry.as');
    const match = /definitions\s*=\s*(\[[\s\S]*?\]);/.exec(registry);
    if (!match) throw new Error('AS2 feature catalog literal is unavailable');
    const definitions = JSON.parse(JSON.stringify(vm.runInNewContext(match[1], {}, {timeout:1000})));
    const checks = [];
    const check = (name, ok, detail) => { checks.push({name, ok:!!ok, detail:detail || ''}); if (!ok) throw new Error(name + ': ' + JSON.stringify(detail)); };
    await page.evaluate(defs => window.__openFeatureFixture(defs), definitions);
    await page.evaluate(() => { document.getElementById('qa-output').style.display = 'none'; });
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'idle');
    const reset = page.locator('.skills-filter-reset');
    if (await reset.count() && await reset.isVisible()) await reset.click();
    await page.locator('.skills-library-row[data-skill-key="冲击连携"]').click();
    await page.locator('[data-focus-key="action:features"]').click();
    const featurePage = page.locator('.skills-feature-page');
    await featurePage.waitFor({state:'visible'});
    const half = () => page.locator('[data-feature-id="impact_chain.half_reload"]');
    check('production catalog is rendered as independent switches', await featurePage.locator('[role="switch"]').count() === definitions.filter(d => d.skillKey === '冲击连携').length);
    check('underlay is inert while the feature editor owns focus', await page.evaluate(() => document.querySelector('.workbench-body').inert && document.querySelector('.workbench-header').inert));
    const helpWrites = await page.evaluate(() => __sent.filter(x => x.cmd === 'setFeature').length);
    await featurePage.getByRole('button', {name:'子能力设置帮助',exact:true}).click();
    await page.getByRole('button', {name:'知道了',exact:true}).click();
    check('shared help returns to the editor without a business write', await featurePage.isVisible() && await page.evaluate(() => __sent.filter(x => x.cmd === 'setFeature').length) === helpWrites);
    await half().click();
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'idle' && document.querySelector('[data-feature-id="impact_chain.half_reload"]').getAttribute('aria-checked') === 'false');
    check('half reload toggle keeps main-hand firepower opted in', await page.locator('[data-feature-id="impact_chain.pistol_power"]').getAttribute('aria-checked') === 'true');
    await page.keyboard.press('Tab');
    check('keyboard focus follows the restored switch after a write', await page.evaluate(() => document.activeElement.getAttribute('data-feature-id')) === 'impact_chain.pistol_power');
    await page.keyboard.press('Space');
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'idle' && document.querySelector('[data-feature-id="impact_chain.pistol_power"]').getAttribute('aria-checked') === 'false');
    await page.keyboard.press('Space');
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'idle' && document.querySelector('[data-feature-id="impact_chain.pistol_power"]').getAttribute('aria-checked') === 'true');
    check('Space toggles the focused child independently', await half().getAttribute('aria-checked') === 'false');
    const writesBefore = await page.evaluate(() => __sent.filter(x => x.cmd === 'setFeature').length);
    await page.evaluate(() => { __host.unknownNextWrite = true; __host.unknownDelayMs = 4000; });
    await page.locator('[data-feature-id="impact_chain.offhand_impact"]').click();
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'needs_reconcile');
    check('unknown child write freezes every child control', await featurePage.locator('[role="switch"]:not([disabled])').count() === 0);
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'needs_reconcile' && SkillsPanel.debugState().coordinator.mux.pendingCount === 0);
    await page.evaluate(() => { __host.pendingWriteUntil = 0; });
    await featurePage.locator('.skills-feature-footer button').click();
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'idle');
    check('reconciliation adopts a fresh result without replaying the child write', await page.evaluate(() => __sent.filter(x => x.cmd === 'setFeature').length) === writesBefore + 1);
    await page.locator('[data-feature-id="impact_chain.offhand_impact"]').click();
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'idle');
    await featurePage.getByRole('button', {name:'← 返回技能',exact:true}).click();
    check('back restores the current opener after its DOM was refreshed', await page.evaluate(() => document.activeElement.getAttribute('data-focus-key') === 'action:features'));
    await page.getByRole('button', {name:'停用被动',exact:true}).click();
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'idle');
    await page.locator('[data-focus-key="action:features"]').click();
    check('parent-off preserves the child choice while suspending its siblings', await half().getAttribute('aria-checked') === 'false' && (await featurePage.innerText()).includes('随父技能停用'));
    await page.keyboard.press('Escape');
    await featurePage.waitFor({state:'hidden'});
    check('Escape closes only the top feature page', !(await featurePage.isVisible()) && await page.locator('.skills-panel').isVisible());
    await page.getByRole('button', {name:'启用被动',exact:true}).click();
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'idle');
    await page.locator('[data-focus-key="action:features"]').click();
    const rejected = await page.evaluate(() => {
        const faults = [s => s.features.push(copy(s.features[0])), s => {s.features[0].extra = true;},
            s => {s.features[0].skillKey = '不存在的父技能';}, s => {s.features[0].effectiveEnabled = !s.features[0].effectiveEnabled;},
            s => {s.features[0].minLevel = '1';}, s => {s.features[0].id += '\n';}, s => {s.features = {};}];
        return faults.every(fault => {const s = authoritativeSnapshot('manage');fault(s);return SkillsPanel.validateSnapshot(s).ok === false;});
    });
    check('duplicate, foreign, malformed and inconsistent feature projections are rejected', rejected);
    await featurePage.locator('.skills-feature-list').hover(); await page.mouse.wheel(0,3000);
    await page.waitForFunction(() => {const list = document.querySelector('.skills-feature-list'); return list.scrollHeight <= list.clientHeight + 1 || list.scrollTop > 0;});
    const geometry = await page.evaluate(() => {
        const page = document.querySelector('.skills-feature-page'), list = page.querySelector('.skills-feature-list');
        const r = page.getBoundingClientRect();
        return {left:r.left,top:r.top,right:r.right,bottom:r.bottom,width:innerWidth,height:innerHeight,
            horizontal:list.scrollWidth > list.clientWidth + 1,
            scrollable:list.scrollHeight > list.clientHeight + 1,scrolled:list.scrollTop > 0,
            minimumControl:getComputedStyle(page.querySelector('[role="switch"]')).minHeight};
    });
    check('editor fits the viewport with bounded vertical scroll and full-size controls', geometry.left >= -1 && geometry.top >= -1 && geometry.right <= geometry.width+1 && geometry.bottom <= geometry.height+1 && !geometry.horizontal && (!geometry.scrollable || geometry.scrolled) && geometry.minimumControl === '40px', geometry);
    await page.mouse.wheel(0,-3000);
    await page.waitForFunction(() => document.querySelector('.skills-feature-list').scrollTop === 0 && Number(getComputedStyle(document.querySelector('.skills-feature-page')).opacity) > 0.99);
    const output = path.join(ROOT,'tmp','skills-harness');fs.mkdirSync(output,{recursive:true});
    const screenshot = path.join(output,'features-' + viewport.label + '.png');
    await page.screenshot({path:screenshot});
    await featurePage.getByRole('button', {name:'← 返回技能',exact:true}).click();
    await page.locator('.skills-library-row[data-skill-key="剑气释放"]').click();
    await page.locator('[data-focus-key="action:features"]').click();
    check('sword group renders its own four production abilities', await featurePage.locator('[role="switch"]').count() === 4);
    await page.locator('[data-feature-id="sword.double_wave"]').click();
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'idle' && document.querySelector('[data-feature-id="sword.double_wave"]').getAttribute('aria-checked') === 'false');
    check('one sword variant can be disabled while the other variants remain enabled', await page.locator('[data-feature-id="sword.wave"]').getAttribute('aria-checked') === 'true' && await page.locator('[data-feature-id="sword.sand"]').getAttribute('aria-checked') === 'true' && await page.locator('[data-feature-id="sword.shadow"]').getAttribute('aria-checked') === 'true');
    await page.screenshot({path:path.join(output,'sword-features-' + viewport.label + '.png')});
    await featurePage.getByRole('button', {name:'← 返回技能',exact:true}).click();
    await page.locator('.skills-library-row[data-skill-key="冲击连携"]').click();
    await page.locator('[data-focus-key="action:features"]').click();
    check('switching parent groups preserves the impact-chain choice', await half().getAttribute('aria-checked') === 'false');
    await featurePage.locator('.skills-feature-header .workbench-close-btn').click();
    await page.waitForFunction(() => SkillsPanel.debugState().coordinator.state === 'closed');
    check('panel close destroys the child view and releases pending work', await page.locator('.skills-feature-page').count() === 0 && await page.evaluate(() => SkillsPanel.debugState().coordinator.mux.pendingCount) === 0);
    return {passed:checks.length,total:checks.length,checks,geometry,screenshot};
}

async function runViewport(browser, server, viewport) {
    const page = await browser.newPage({viewport});
    const pageErrors = [], failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message || String(error)));
    page.on('requestfailed', request => {
        const target = request.url();
        if (!/^https?:\/\/cfn-fonts\.local\//i.test(target)) failedRequests.push(target);
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/modules/skills/dev/harness.html`, {waitUntil:'load'});
    await page.waitForFunction(() => window.__qaDone === true, null, {timeout:20000});
    const state = await page.evaluate(() => ({result:window.__qaResult,error:window.__qaError}));
    const featureChecks = state.error ? null : await probeSkillFeatures(page, viewport).catch(async error => {
        const detail = await page.evaluate(() => ({state:SkillsPanel.debugState(),sent:__sent.slice(-8),text:document.body.innerText.slice(-3000)}));
        throw new Error(error.message + '\nFeature state: ' + JSON.stringify(detail));
    });
    const semanticRejectMotion = state.error ? null : await probeSemanticRejectMotion(page);
    await page.waitForLoadState('networkidle');
    await page.close();
    if (state.error) throw new Error(viewport.label + ': ' + state.error);
    if (pageErrors.length) throw new Error(viewport.label + ' page errors: ' + pageErrors.join(' | '));
    if (failedRequests.length) throw new Error(viewport.label + ' failed requests: ' + failedRequests.join(' | '));
    const bad = state.result && state.result.checks ? state.result.checks.filter(check => !check.ok) : [];
    if (!state.result || state.result.passed !== state.result.total) throw new Error(viewport.label + ' harness failed: ' + JSON.stringify(bad));
    if (!semanticRejectMotion || !semanticRejectMotion.pass) {
        throw new Error(viewport.label + ' semantic reject motion failed: ' + JSON.stringify(semanticRejectMotion));
    }
    state.result.semanticRejectMotion = semanticRejectMotion;
    state.result.featureChecks = featureChecks;
    state.result.passed += featureChecks.passed; state.result.total += featureChecks.total;
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
    console.log(`Skills harness ${cases}/${cases} passed across ${results.length} viewport(s): ${viewports.map(v => v.label).join(', ')}; G3 reject motion normal/reduced passed`);
})().catch(error => { console.error(error.stack || error); process.exit(1); });
