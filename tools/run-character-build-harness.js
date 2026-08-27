#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const VIEWPORTS = [[1024,576], [1366,768], [1920,1080]];
const shotArg = process.argv.find(arg => arg.startsWith('--shot-dir='));
const checks = [];

function check(ok, title, detail) {
    checks.push({ok:!!ok, title, detail:detail == null ? '' : String(detail)});
    if (!ok) throw new Error(title + (detail == null ? '' : ': ' + detail));
}

function read(rel) { return fs.readFileSync(path.join(ROOT, rel), 'utf8'); }

function staticAudit() {
    const focus = read('launcher/web/modules/workbench-focus.js');
    const inventory = read('launcher/web/modules/inventory-ui.js');
    const view = read('launcher/web/modules/character-build-view.js');
    const template = read(
        'launcher/web/modules/character-build/character-build-template.js');
    const loadoutPresenter = read(
        'launcher/web/modules/character-build/character-build-loadout-presenter.js');
    const slotGrid = read(
        'launcher/web/modules/loadout-picker/loadout-picker-slot-grid.js');
    const candidatePane = read(
        'launcher/web/modules/loadout-picker/loadout-picker-candidate-pane.js');
    const loadoutPicker = read(
        'launcher/web/modules/loadout-picker/loadout-picker.js');
    const presentation = [view, template, loadoutPresenter, slotGrid, candidatePane, loadoutPicker].join('\n');
    const actionView = read(
        'launcher/web/modules/loadout-picker/loadout-picker-action-view.js');
    const candidateState = read(
        'launcher/web/modules/loadout-picker/loadout-picker-candidate-state.js');
    const facetCounts = read(
        'launcher/web/modules/character-build/character-build-facet-counts.js');
    const candidatePresentation = presentation + '\n' + candidateState;
    const statsView = read(
        'launcher/web/modules/character-build/character-build-stats-view.js');
    const dollPreview = read(
        'launcher/web/modules/character-build/character-build-doll-preview.js');
    const pose = read(
        'launcher/web/modules/character-build/character-build-pose.js');
    const controller = read('launcher/web/modules/character-build.js');
    const renderer = read('launcher/web/modules/dressup-doll-renderer.js');
    const facade = read('launcher/web/modules/inventory-workbench.js');
    const config = read(
        'launcher/web/modules/inventory-workbench-config.js');
    const headerModule = read('launcher/web/modules/inventory-workbench-header.js');
    const cssFacade = read('launcher/web/css/panels.css');
    const css = read('launcher/web/css/workbench/loadout-picker.css')
        + read('launcher/web/css/workbench/character-build.css')
        + read('launcher/web/css/workbench/character-build-stats.css');
    const harness = read('launcher/web/modules/character-build/dev/harness.html');
    const workbenchHarness = read(
        'launcher/web/modules/character-build/dev/workbench-harness.html');
    const menuKeydown = inventory.slice(
        inventory.indexOf('InventoryWindowPager.prototype._onMenuKeyDown'),
        inventory.indexOf('InventoryWindowPager.prototype.requestRelative'));

    check(focus.includes('function RovingGridFocus(')
        && focus.includes('RovingGridFocus:RovingGridFocus')
        && focus.includes('getNeighbor'), 'shared roving-grid focus is exported with explicit adjacency');
    check(inventory.includes('new RovingGridFocus({')
        && !/Arrow(?:Left|Right|Up|Down)/.test(menuKeydown),
        'inventory page menu consumes the extracted arrow-key primitive');
    check(view.includes('new WorkbenchFocus.RovingGridFocus')
        && view.includes('new WorkbenchComponents.SecondaryPage')
        && view.includes('new StatsViewModule.StatsView')
        && view.includes('DollPreviewModule.create')
        && presentation.includes("classPrefix + '-slot-card'")
        && presentation.includes('this._renderOwnedSlot')
        && inventory.includes("options.tagName === 'span' ? 'span' : 'article'"),
        'character build composes shared focus, SecondaryPage and owned-item primitives');
    check(presentation.includes("this._interactionState !== 'idle'")
        && actionView.includes("nodes[i].setAttribute('inert', '')"),
        'candidate articles enforce busy state at the event boundary and roving focus boundary');
    check(!/Panels\.register|Bridge\.send|PanelRequestMux|domain\s*:|cmd\s*:/.test(view),
        'presentation view has no production route, transport, or write command');
    check(statsView.includes('data-weight-ratio')
        && statsView.includes('当前组相对量级')
        && !/getWeightSpeedRatio|candidate.*predict/i.test(statsView),
        'stats presenter consumes authority rows without recreating combat formulas');
    check((presentation.match(/createElement\('canvas'\)|<canvas/g) || []).length === 1
        && presentation.includes('single-canvas-candidate-overlay')
        && !/<canvas|createElement\(['"]canvas/.test(dollPreview)
        && dollPreview.includes('this._mount.appendChild(this._stage)')
        && dollPreview.includes('this._home.insertBefore(this._stage')
        && dollPreview.includes('InspectionViewport.create({')
        && dollPreview.includes('target:this._canvas')
        && dollPreview.includes('this._inspection.activate({reset:true})')
        && dollPreview.includes('this._inspection.deactivate()'),
        'view declares one Canvas and the enlarged preview reparents it behind a transient shared camera');
    check(['空手站立','长枪站立','手枪站立','手枪2站立','双枪站立','兵器站立']
        .every(label => pose.includes("'" + label + "'"))
        && pose.includes('cameraEnvelopePoses:cameraEnvelopePoses')
        && pose.includes('cameraFitFields:cameraFitFields')
        && pose.includes('drawFields:drawFields')
        && controller.includes('DressupDollRenderer.withFitEnvelope')
        && controller.includes('Pose.cameraFitFields()')
        && !controller.includes("this._panelInstanceId + '|' + state.gender")
        && renderer.includes('function measureEnvelope(')
        && renderer.includes('fitEnvelopeApplied'),
        'character build recomputes one structural-body envelope across all six battle poses');
    check(!/READ ONLY SPIKE|<span>LOOK<\/span>|<span>LOADOUT<\/span>|<span>COMPARE<\/span>|单 Canvas|全宽 SecondaryPage/.test(presentation),
        'visible view copy contains no prototype or implementation labels');
    check(['头部装备','上装装备','下装装备','手部装备','脚部装备','颈部装备',
        '长枪','手枪','手枪2','刀','手雷'].every(key => template.includes("id:'" + key + "'"))
        && view.includes('TemplateModule.armorSlots')
        && view.includes('TemplateModule.weaponSlots'),
        'template freezes and view consumes the exact eleven equipment protocol keys');
    check(candidateState.includes("statement:'先选择左侧槽位'")
        && candidateState.includes("statement:'正在查找可用装备'")
        && candidateState.includes("statement:'此槽位暂无可用候选'")
        && candidateState.includes("statement:'暂时无法读取候选'")
        && candidateState.includes("statement:'候选与数量已同步'")
        && headerModule.includes("append(buildActions, 'back-build', '← 返回构筑'")
        && facade.includes('statsRoot.insertBefore(header, statsRoot.firstChild)')
        && !view.includes('class="character-build-stats-back"'),
        'candidate five-state contract and single main-header stats return are explicit');
    check(facetCounts.includes("if (kind === 'drug') return model.useCounts['药剂']")
        && facetCounts.includes("if (id === '手枪2')")
        && facetCounts.includes("return count == null ? '—' : String(count)")
        && facetCounts.includes('decorateSlot:decorateSlot')
        && !/Bridge\.send|PanelRequestMux|domain\s*:|cmd\s*:/.test(facetCounts),
        'candidate count leaf maps the fixed 11+8 targets without transport or taxonomy guessing');
    check(template.includes('data-drug-grid role="grid"')
        && (template.match(/data-drug-bank="[01]" role="rowgroup"/g) || []).length === 2
        && (template.match(/data-drug-bank-grid="[01]" role="row"/g) || []).length === 2,
        'two drug banks preserve one grid with two labeled rowgroups and two rows');
    check(candidatePresentation.includes('WorkbenchPrimitives.EntityTile.bindActivation')
        && candidatePresentation.includes('inspectable:true')
        && candidatePresentation.includes('actionable:false')
        && candidatePresentation.includes('onBlocked:function')
        && candidatePresentation.includes('data-candidate-retry'),
        'blocked candidates use shared inspectable semantics and error exposes one retry port');
    check(headerModule.includes("stats:action(buildMode, '个人信息', locked, lockReason)")
        && headerModule.includes("skills:action(buildMode && !preparationNavigationV1, '技能配置'")
        && headerModule.includes("'preparation-menu':action(")
        && headerModule.includes("'back-build':action(statsMode")
        && headerModule.includes('applyProjection(state.buttons, projection)')
        && facade.includes('InventoryWorkbenchHeader.renderWorkbenchHeader(')
        && config.includes("returnFocusAction === 'skills'")
        && config.includes("returnFocusAction === 'preparation-menu'")
        && config.includes("typeof initData.returnFocusAction !== 'string'")
        && config.includes('returnFocusAction === null')
        && facade.includes("launch.returnFocusAction === 'skills'")
        && !facade.includes('initData.returnFocusAction')
        && !/querySelector\s*\([^)]*returnFocusAction/.test(config + '\n' + facade)
        && facade.includes('_buttons.skills.focus()')
        && workbenchHarness.includes(
            "visibleHeaderActions().join('|') === 'back-build|help|close'")
        && workbenchHarness.includes(
            "=== 'preparation-menu|stats|help|close'")
        && workbenchHarness.includes("returnFocusAction:'preparation-menu'")
        && workbenchHarness.includes("returnFocusAction:'skills'")
        && workbenchHarness.includes('document.activeElement === trigger')
        && workbenchHarness.includes('document.activeElement === skillsButton'),
        'stats hides navigation; gate-paired focus parsing restores the production preparation trigger or legacy Skills action');
    check(!presentation.includes('character-build-vitals') && !presentation.includes('data-preview-action')
        && !presentation.includes('data-info-action') && !presentation.includes('data-info-panel')
        && !actionView.includes('data-info-action') && !actionView.includes('data-info-panel')
        && presentation.includes('role="toolbar" aria-label="当前槽位与候选操作"')
        && presentation.includes('<div class="character-build-pane-tools"><div data-build-density-mount></div></div>')
        && presentation.includes('class="character-build-candidate-count" data-candidate-count')
        && presentation.indexOf('character-build-candidate-focus-summary')
            < presentation.indexOf('character-build-candidate-actions')
        && presentation.indexOf('character-build-candidate-scope-row')
            < presentation.indexOf('character-build-candidate-focus-summary')
        && !presentation.includes('character-build-candidate-actions p')
        && actionView.includes("event.key === 'Enter' && !event.repeat && selected")
        && actionView.includes("event.key === ' ' && selected")
        && actionView.includes('this._clearCandidateSelection()')
        && actionView.includes('this._tryCommit(this._getCandidate())')
        && actionView.includes("this._state === 'mutation_reconcile'")
        && actionView.includes("action === 'unequip'"),
        'main snapshot invents no vitals or candidate detail/pin surface and embeds one action toolbar in the candidate context row');
    check(presentation.includes('class="character-build-loadout-tools"')
        && presentation.includes('data-focus-summary')
        && presentation.includes('data-doll-preview-action-host')
        && template.indexOf('data-focus-summary')
            < template.indexOf('data-doll-preview-action-host')
        && presentation.includes('character-build-loadout-heading-copy')
        && !presentation.includes('data-slot-count')
        && !presentation.includes('护具 · 6')
        && !presentation.includes('武装 · 5')
        && !presentation.includes('药剂 · 4')
        && !presentation.includes('<div class="character-build-focus-summary"'),
        'loadout heading keeps the browse summary left, preview action right, and removes redundant counts');
    check(!/Read-only|read-only|只读/.test(presentation)
        && !/Read-only|read-only|只读/.test(read('launcher/web/modules/character-build.js'))
        && !/Read-only|read-only|只读/.test(harness),
        'editing view, controller and harness contain no stale read-only phase copy');
    const visibleImplementationCopy = /['"][^'"\r\n]*(?:B1|接线|spike|prototype)[^'"\r\n]*['"]/i;
    check(!visibleImplementationCopy.test(presentation)
        && !visibleImplementationCopy.test(facade)
        && !visibleImplementationCopy.test(read('launcher/web/modules/character-build.js')),
        'production-visible character-build copy contains no implementation-stage vocabulary');
    check(cssFacade.includes('@import url("./workbench/character-build.css");')
        && cssFacade.includes('@import url("./workbench/character-build-stats.css");')
        && css.includes('var(--wb-') && !/:root\s*\{/.test(css),
        'feature CSS reuses the shared token system without a second root palette');
    check(harness.includes('fixtures.empty') && harness.includes('fixtures.cooldown')
        && harness.includes('fixtures.blocked')
        && harness.includes('fixtures.long') && harness.includes('fixtures.unknown')
        && harness.includes('candidateFacets:candidateFacets()')
        && presentation.includes('当前装备保持不变'),
        'static harness includes zero/unknown counts, empty, paired cooldown, blocked, long-copy, and honest preview fixtures');
}

function edgeExecutable() {
    return [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].find(fs.existsSync);
}

function createServer() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(WEB, pathname));
            const relative = path.relative(WEB, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) {
                response.writeHead(403); response.end(); return;
            }
            fs.readFile(file, (error, data) => {
                if (error) { response.writeHead(404); response.end(); return; }
                const extension = path.extname(file);
                const contentType = extension === '.html' ? 'text/html; charset=utf-8'
                    : extension === '.css' ? 'text/css; charset=utf-8'
                        : extension === '.js' ? 'text/javascript; charset=utf-8' : 'application/octet-stream';
                response.writeHead(200, {'Content-Type':contentType});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function metrics(page) {
    return page.evaluate(() => {
        const root = document.querySelector('.character-build-workbench');
        const visible = node => {
            if (!node || node.getAttribute('aria-hidden') === 'true') return false;
            const style = getComputedStyle(node);
            return style.display !== 'none' && style.visibility !== 'hidden';
        };
        const fontNodes = Array.from(root.querySelectorAll(
            '.character-build-body button,.character-build-body [data-body-copy],'
            + '.character-build-slot-label,.character-build-slot-name,.character-build-candidate small'));
        const fontSizes = fontNodes.filter(visible).map(node => parseFloat(getComputedStyle(node).fontSize));
        const scrollRegions = Array.from(root.querySelectorAll('[data-scroll-region]')).filter(node => {
            if (!visible(node)) return false;
            for (let current = node.parentElement; current && current !== root; current = current.parentElement) {
                if (current.getAttribute('aria-hidden') === 'true') return false;
            }
            const overflow = getComputedStyle(node).overflowY;
            return (overflow === 'auto' || overflow === 'scroll') && node.scrollHeight > node.clientHeight + 1;
        }).map(node => node.getAttribute('data-scroll-region'));
        const horizontalNodes = [root, root.querySelector('.character-build-body')]
            .concat(Array.from(root.querySelectorAll('.character-build-pane')));
        const horizontalOverflow = horizontalNodes.some(node => node && node.scrollWidth > node.clientWidth + 1);
        const armor = Array.from(root.querySelectorAll('[data-slot-kind="armor"]'));
        const weapons = Array.from(root.querySelectorAll('[data-slot-kind="weapon"]'));
        const equipment = armor.concat(weapons);
        const drugs = Array.from(root.querySelectorAll('[data-slot-kind="drug"]'));
        const candidates = Array.from(root.querySelectorAll('.character-build-candidate'));
        const previewAction = root.querySelector('[data-doll-preview-open]').getBoundingClientRect();
        const actionToolbar = root.querySelector('.character-build-candidate-actions');
        const candidateContextRow = root.querySelector(
            '.character-build-candidate-pane > .character-build-candidate-context-row');
        const loadoutHeading = root.querySelector(
            '.character-build-composite-pane > .character-build-pane-heading');
        const loadoutTools = loadoutHeading.querySelector('.character-build-loadout-tools');
        const focusSummary = loadoutHeading.querySelector('[data-focus-summary]');
        const previewButton = loadoutHeading.querySelector('[data-doll-preview-open]');
        const slotCount = loadoutHeading.querySelector('[data-slot-count]');
        const candidateOverlay = root.querySelector('[data-layer="candidate-preview"]');
        const routineNotice = root.querySelector('[data-build-notice]');
        const visibleActionButtons = Array.from(actionToolbar.querySelectorAll('button')).filter(
            node => !node.hidden && getComputedStyle(node).display !== 'none'
                && getComputedStyle(node).visibility !== 'hidden');
        const actionRects = visibleActionButtons.map(node => node.getBoundingClientRect());
        const actionToolbarRect = actionToolbar.getBoundingClientRect();
        const candidateContextRowRect = candidateContextRow.getBoundingClientRect();
        const candidateScroll = root.querySelector('.character-build-candidate-scroll');
        const body = root.querySelector('.character-build-body');
        const directPanes = Array.from(body.children).filter(node => node.hasAttribute('data-build-pane'));
        const candidatePane = body.querySelector(':scope > [data-build-pane="candidates"]');
        const loadoutPane = body.querySelector(':scope > [data-build-pane="loadout"]');
        const composite = loadoutPane.querySelector('.character-build-composite');
        const visualColumn = composite.querySelector('.character-build-visual-column');
        const loadoutColumn = composite.querySelector('.character-build-loadout-column');
        const slotGrids = Array.from(loadoutColumn.querySelectorAll(
            '.character-build-slot-grid,.character-build-drug-grid'));
        const compositeRect = composite.getBoundingClientRect();
        const visualColumnRect = visualColumn.getBoundingClientRect();
        const loadoutColumnRect = loadoutColumn.getBoundingClientRect();
        const slotGridRects = slotGrids.map(node => node.getBoundingClientRect());
        const slotRowRightEdges = slotGrids.map(grid => Math.max.apply(Math,
            Array.from(grid.children).map(node => node.getBoundingClientRect().right)));
        const drugTops = drugs.map(node => node.getBoundingClientRect().top);
        const candidateWidth = candidatePane.getBoundingClientRect().width;
        const loadoutWidth = loadoutPane.getBoundingClientRect().width;
        const hitTargets = equipment.concat(drugs, candidates)
            .map(node => node.getBoundingClientRect().height);
        const hitTargetGroups = {
            armor:armor.map(node => node.getBoundingClientRect().height),
            weapons:weapons.map(node => node.getBoundingClientRect().height),
            drugs:drugs.map(node => node.getBoundingClientRect().height),
            candidates:candidates.map(node => node.getBoundingClientRect().height)
        };
        const hitTargetComputed = equipment.concat(drugs, candidates).slice(0, 4).map(node => ({
            kind:node.getAttribute('data-slot-kind') || 'candidate',
            minHeight:getComputedStyle(node).minHeight,
            height:getComputedStyle(node).height
        }));
        const protocolKeys = equipment.map(node => node.getAttribute('data-slot-protocol-key'));
        const slotCandidateCounts = {};
        equipment.concat(drugs).forEach(node => {
            const key = node.getAttribute('data-slot-kind') + ':'
                + node.getAttribute('data-slot-id');
            const badge = node.querySelector('[data-slot-candidate-count]');
            const badgeRect = badge.getBoundingClientRect();
            const cardRect = node.querySelector('.character-build-slot-card')
                .getBoundingClientRect();
            slotCandidateCounts[key] = {
                text:badge.textContent,
                state:badge.getAttribute('data-count-state'),
                value:node.getAttribute('data-candidate-count'),
                aria:node.getAttribute('aria-label'),
                fontSize:parseFloat(getComputedStyle(badge).fontSize),
                insideCard:badgeRect.top >= cardRect.top - 1
                    && badgeRect.right <= cardRect.right + 1
                    && badgeRect.bottom <= cardRect.bottom + 1
            };
        });
        const state = CharacterBuildHarness.view.debugState();
        return {
            equipment:equipment.length,
            armor:armor.length,
            weapons:weapons.length,
            drugs:drugs.length,
            drugRowGroups:root.querySelectorAll(
                '[data-drug-grid] > [role="rowgroup"]').length,
            drugRows:root.querySelectorAll(
                '[data-drug-grid] [role="row"]').length,
            occupied:equipment.concat(drugs).filter(node => node.getAttribute('data-empty') === 'false').length,
            slotIcons:root.querySelectorAll(
                '.character-build-slot-card .inventory-owned-icon[data-icon-name]').length,
            candidates:candidates.length,
            canvasCount:root.querySelectorAll('canvas').length,
            overlayCount:root.querySelectorAll('[data-layer="candidate-preview"]').length,
            canvasSize:(() => {
                const rect = root.querySelector('canvas').getBoundingClientRect();
                return {width:rect.width, height:rect.height};
            })(),
            renderModel:root.getAttribute('data-render-model'),
            minFont:fontSizes.length ? Math.min.apply(Math, fontSizes) : 0,
            previewActionHeight:previewAction.height,
            candidateActionCount:visibleActionButtons.length,
            infoActionCount:root.querySelectorAll('[data-info-action]').length,
            infoPanelCount:root.querySelectorAll('[data-info-panel],.character-build-info-panel').length,
            loadoutHeadingStructure:!!loadoutTools && !!focusSummary
                && !!previewButton,
            focusSummaryInHeading:!!focusSummary
                && focusSummary.closest('.character-build-pane-heading') === loadoutHeading,
            focusSummaryInHeadingCopy:!!focusSummary
                && focusSummary.parentNode.classList.contains(
                    'character-build-loadout-heading-copy'),
            focusSummaryLeftOfPreview:!!focusSummary && !!previewButton
                && focusSummary.getBoundingClientRect().right
                    <= previewButton.getBoundingClientRect().left,
            previewActionInHeading:!!previewButton
                && previewButton.closest('.character-build-pane-heading') === loadoutHeading,
            slotCountInHeading:!!slotCount
                && slotCount.closest('.character-build-pane-heading') === loadoutHeading,
            slotGroupHeadings:Array.from(
                root.querySelectorAll('.character-build-slot-section > h3'))
                .map(node => (node.childNodes[0] || node).textContent.trim()),
            legacyLowerFocusSummaryCount:root.querySelectorAll(
                '.character-build-composite-pane > .character-build-focus-summary,'
                + '.character-build-loadout-column > .character-build-focus-summary').length,
            loadoutEyebrow:(loadoutHeading.querySelector(':scope > div > span') || {}).textContent || '',
            loadoutTitle:(loadoutHeading.querySelector('h2') || {}).textContent || '',
            loadoutHeadingOverflow:loadoutHeading.scrollWidth > loadoutHeading.clientWidth + 1
                || loadoutTools.scrollWidth > loadoutTools.clientWidth + 1,
            actionsAboveCandidates:actionToolbarRect.bottom
                <= candidateScroll.getBoundingClientRect().top + 1,
            actionsInContextRow:actionToolbar.closest('.character-build-candidate-context-row')
                === candidateContextRow,
            actionLabels:visibleActionButtons.map(node => node.textContent.trim()),
            actionAria:visibleActionButtons.map(node => node.getAttribute('aria-label')),
            actionSameRow:Math.max.apply(Math, actionRects.map(rect => rect.top))
                - Math.min.apply(Math, actionRects.map(rect => rect.top)) <= 1,
            actionInsideContextRow:actionToolbarRect.left >= candidateContextRowRect.left - 1
                && actionToolbarRect.right <= candidateContextRowRect.right + 1
                && actionToolbarRect.top >= candidateContextRowRect.top - 1
                && actionToolbarRect.bottom <= candidateContextRowRect.bottom + 1,
            actionOverflow:actionToolbar.scrollWidth > actionToolbar.clientWidth + 1
                || candidateContextRow.scrollWidth > candidateContextRow.clientWidth + 1,
            actionClipped:visibleActionButtons.some(
                node => node.scrollWidth > node.clientWidth + 1),
            actionWrapped:actionToolbarRect.height
                > Math.max.apply(Math, actionRects.map(rect => rect.height)) + 2,
            minActionWidth:Math.min.apply(Math, actionRects.map(rect => rect.width)),
            previewActionCount:root.querySelectorAll('[data-preview-action]').length,
            vitalCount:root.querySelectorAll('.character-build-vitals,[data-vital]').length,
            duplicateActionHelp:root.querySelectorAll('.character-build-candidate-actions p').length,
            scrollRegions,
            horizontalOverflow,
            armorTabStops:armor.filter(node => node.tabIndex === 0).length,
            weaponTabStops:weapons.filter(node => node.tabIndex === 0).length,
            drugTabStops:drugs.filter(node => node.tabIndex === 0).length,
            candidateTabStops:candidates.filter(node => node.tabIndex === 0).length,
            directPaneCount:directPanes.length,
            directPaneNames:directPanes.map(node => node.getAttribute('data-build-pane')),
            candidateRatio:candidateWidth / (candidateWidth + loadoutWidth),
            candidatePaneWidth:candidateWidth,
            loadoutPaneWidth:loadoutWidth,
            innerLayout:{
                compositeWidth:compositeRect.width,
                visualColumnWidth:visualColumnRect.width,
                loadoutColumnWidth:loadoutColumnRect.width,
                trailingSlack:compositeRect.right - loadoutColumnRect.right,
                slotRowTrailingSlack:slotRowRightEdges.map(
                    right => compositeRect.right - right),
                drugTwoRows:drugTops.length === 8
                    && Math.max.apply(Math, drugTops.slice(0, 4))
                        - Math.min.apply(Math, drugTops.slice(0, 4)) <= 1
                    && Math.max.apply(Math, drugTops.slice(4))
                        - Math.min.apply(Math, drugTops.slice(4)) <= 1
                    && drugTops[4] > drugTops[0],
                horizontalOverflow:[composite, visualColumn, loadoutColumn].concat(slotGrids)
                    .some(node => node.scrollWidth > node.clientWidth + 1),
                overflowByNode:[composite, visualColumn, loadoutColumn].concat(slotGrids)
                    .map(node => ({
                        className:node.className,
                        clientWidth:node.clientWidth,
                        scrollWidth:node.scrollWidth
                    })),
                slotGridWidths:slotGridRects.map(rect => rect.width)
            },
            minHitTarget:hitTargets.length ? Math.min.apply(Math, hitTargets) : 0,
            hitTargetGroups,
            hitTargetComputed,
            protocolKeys,
            slotCandidateCounts,
            slotCandidateBadgeCount:root.querySelectorAll(
                '[data-slot-candidate-count]').length,
            focusSummaryText:focusSummary.textContent,
            selectedSlots:equipment.concat(drugs).filter(node => node.getAttribute('aria-selected') === 'true').length,
            selectedCandidates:candidates.filter(node => node.getAttribute('aria-selected') === 'true').length,
            selectedSlotKey:state.selectedSlotKey,
            selectedCandidateKey:state.selectedCandidateKey,
            overlayCopy:root.querySelector('[data-overlay-copy]').textContent,
            overlayHidden:candidateOverlay.hidden
                && getComputedStyle(candidateOverlay).display === 'none',
            routineNoticeKind:routineNotice.getAttribute('data-notice-kind'),
            routineNoticeHidden:getComputedStyle(routineNotice).display === 'none',
            candidateState:(root.querySelector('[data-candidate-list]') || {})
                .getAttribute('data-candidate-state'),
            candidateStatement:(root.querySelector('.character-build-candidate-statement') || {})
                .textContent || '',
            candidateNextStep:(root.querySelector('.character-build-candidate-next-step') || {})
                .textContent || '',
            rootRect:(() => {
                const rect = document.querySelector('.workbench-shell').getBoundingClientRect();
                return {left:rect.left, top:rect.top, width:rect.width, height:rect.height};
            })()
        };
    });
}

async function runViewport(browser, port, viewport) {
    const label = viewport.join('x');
    const page = await browser.newPage({viewport:{width:viewport[0], height:viewport[1]}});
    const pageErrors = [];
    const failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    page.on('requestfailed', request => failedRequests.push(request.url()));
    try {
        await page.goto('http://127.0.0.1:' + port + '/modules/character-build/dev/harness.html', {waitUntil:'load'});
        await page.waitForFunction(() => window.__qaReady === true, null, {timeout:15000});
        check(pageErrors.length === 0, label + ' has no page errors', pageErrors.join(' | '));
        check(failedRequests.length === 0, label + ' has no failed requests', failedRequests.join(' | '));

        const base = await metrics(page);
        const statsDegradation = await page.evaluate(() => {
            const host = document.createElement('div');
            const scroll = document.createElement('div');
            const hint = document.createElement('span');
            const copy = document.createElement('span');
            const glyph = document.createElement('i');
            const presenter = new CharacterBuildStatsView.StatsView({
                host, scroll, hint, copy, glyph
            });
            const invalid = CharacterBuildStatsFixture.create();
            invalid.groups[1].rows[2].value = 60;
            presenter.render(invalid);
            const invalidResult = {
                gauge:!!host.querySelector('[data-stats-encumbrance]'),
                detailRows:host.querySelectorAll('[data-stats-detail-grid] [data-stat-key]').length,
                rawThreshold:host.querySelector(
                    '[data-stat-key="mediumHeavyThreshold"] dd').textContent
            };
            const nullRatio = CharacterBuildStatsFixture.create();
            nullRatio.groups[1].rows.find(row => row.key === 'weightRatio').value = null;
            presenter.render(nullRatio);
            invalidResult.nullRatioGauge =
                !!host.querySelector('[data-stats-encumbrance]');
            invalidResult.nullRatioDetail =
                host.querySelector('[data-stat-key="weightRatio"] dd').textContent;
            const negativeResistance = CharacterBuildStatsFixture.create();
            negativeResistance.groups.find(group => group.key === 'resistance')
                .rows[0].value = -5;
            presenter.render(negativeResistance);
            invalidResult.negativeResistanceCharts = Array.from(
                host.querySelectorAll('[data-chart]'),
                node => node.getAttribute('data-chart'));
            invalidResult.negativeResistanceRaw =
                host.querySelector('[data-stat-key="energyResistance"] dd').textContent;
            invalidResult.negativeResistanceDetailIcons = host.querySelectorAll(
                '[data-stats-group="resistance"] [data-resistance-key]').length;
            const nullResistance = CharacterBuildStatsFixture.create();
            nullResistance.groups.find(group => group.key === 'resistance')
                .rows[2].value = null;
            presenter.render(nullResistance);
            invalidResult.nullResistanceCharts = Array.from(
                host.querySelectorAll('[data-chart]'),
                node => node.getAttribute('data-chart'));
            invalidResult.nullResistanceRaw =
                host.querySelector('[data-stat-key="corrosionResistance"] dd').textContent;
            const zeroResistance = CharacterBuildStatsFixture.create();
            zeroResistance.groups.find(group => group.key === 'resistance')
                .rows.forEach(row => { row.value = 0; });
            presenter.render(zeroResistance);
            invalidResult.zeroResistanceCharts = Array.from(
                host.querySelectorAll('[data-chart]'),
                node => node.getAttribute('data-chart'));
            invalidResult.zeroResistanceDetailIcons = host.querySelectorAll(
                '[data-stats-group="resistance"] [data-resistance-key]').length;
            const negativePower = CharacterBuildStatsFixture.create();
            negativePower.groups.find(group => group.key === 'power').rows[0].value = -1;
            presenter.render(negativePower);
            invalidResult.negativePowerCharts = Array.from(
                host.querySelectorAll('[data-chart]'),
                node => node.getAttribute('data-chart'));
            const emptyResult = presenter.render({v:1, groups:[]});
            invalidResult.emptyResult = emptyResult;
            invalidResult.unavailable = !!host.querySelector(
                '.character-build-stats-unavailable[role="status"]');
            return invalidResult;
        });
        check(!statsDegradation.gauge && statsDegradation.detailRows === 47
            && statsDegradation.rawThreshold === '60kg'
            && !statsDegradation.nullRatioGauge
            && statsDegradation.nullRatioDetail === '—'
            && statsDegradation.negativeResistanceCharts.join('|') === 'power'
            && statsDegradation.negativeResistanceRaw === '-5'
            && statsDegradation.negativeResistanceDetailIcons === 8
            && statsDegradation.nullResistanceCharts.join('|') === 'power'
            && statsDegradation.nullResistanceRaw === '—'
            && statsDegradation.zeroResistanceCharts.join('|') === 'power'
            && statsDegradation.zeroResistanceDetailIcons === 8
            && statsDegradation.negativePowerCharts.join('|') === 'resistance'
            && statsDegradation.emptyResult === false && statsDegradation.unavailable,
            label + ' stats invalid scalar and signed-chart inputs fail closed without fabricated visuals',
            JSON.stringify(statsDegradation));
        check(base.armor === 6 && base.weapons === 5 && base.drugs === 8
            && base.drugRowGroups === 2 && base.drugRows === 2
            && base.occupied === 19 && base.slotIcons === 19,
            label + ' renders full 6 armor + 5 weapon + two explicit four-slot drug banks', JSON.stringify(base));
        check(base.protocolKeys.join('|') === [
            '头部装备','上装装备','下装装备','手部装备','脚部装备','颈部装备',
            '长枪','手枪','手枪2','刀','手雷'
        ].join('|'), label + ' keeps exact ordered equipment protocol mapping', base.protocolKeys);
        check(base.directPaneCount === 2
            && base.directPaneNames.join('|') === 'loadout|candidates',
            label + ' body has exactly two direct panes', JSON.stringify(base));
        check(Math.abs(base.candidateRatio - 0.45) <= 0.006
            && base.loadoutPaneWidth > base.candidatePaneWidth
            && base.candidatePaneWidth >= 360
            && base.canvasSize.width >= 300
            && base.canvasSize.width * base.canvasSize.height >= 80000,
            label + ' loadout/candidate panes preserve the 55/45 split and enlarged doll area',
            JSON.stringify({
                candidateRatio:base.candidateRatio,
                loadoutPaneWidth:base.loadoutPaneWidth,
                candidatePaneWidth:base.candidatePaneWidth,
                canvasSize:base.canvasSize
            }));
        check(base.innerLayout.loadoutColumnWidth <= 205
            && base.innerLayout.visualColumnWidth > base.innerLayout.loadoutColumnWidth
            && Math.abs(base.innerLayout.trailingSlack) <= 1
            && base.innerLayout.slotRowTrailingSlack.every(slack => Math.abs(slack) <= 1)
            && base.innerLayout.drugTwoRows
            && !base.innerLayout.horizontalOverflow,
            label + ' inner loadout shrinks to content, aligns right and returns width to the doll',
            JSON.stringify(base.innerLayout));
        check(base.canvasCount === 1 && base.overlayCount === 1
            && base.renderModel === 'single-canvas-candidate-overlay',
            label + ' keeps one Canvas and one semantic candidate overlay');
        check(base.minFont >= 9, label + ' keeps compact labels at least 9px', base.minFont);
        check(base.previewActionHeight >= 44 && base.minHitTarget >= 44 && base.minActionWidth >= 44
            && base.actionsAboveCandidates && base.actionsInContextRow && base.actionInsideContextRow
            && base.actionSameRow && !base.actionOverflow && !base.actionClipped
            && !base.actionWrapped && base.candidateActionCount <= 3,
            label + ' keeps targets at least 44px and embeds actions in one unclipped context row',
            JSON.stringify({
                previewActionHeight:base.previewActionHeight,
                candidateActionCount:base.candidateActionCount,
                actionsAboveCandidates:base.actionsAboveCandidates,
                actionsInContextRow:base.actionsInContextRow,
                actionLabels:base.actionLabels,
                actionAria:base.actionAria,
                minHitTarget:base.minHitTarget,
                minActionWidth:base.minActionWidth,
                hitTargetGroups:base.hitTargetGroups,
                hitTargetComputed:base.hitTargetComputed
            }));
        check(base.loadoutHeadingStructure && base.focusSummaryInHeading
            && base.focusSummaryInHeadingCopy && base.focusSummaryLeftOfPreview
            && base.previewActionInHeading && !base.slotCountInHeading
            && base.legacyLowerFocusSummaryCount === 0
            && base.slotGroupHeadings.join('|') === '护具|武装|药剂'
            && base.loadoutEyebrow === '外观与配置' && base.loadoutTitle === '当前构筑'
            && !base.loadoutHeadingOverflow,
            label + ' keeps browse status left and enlarged preview right without redundant counts',
            JSON.stringify({
                structure:base.loadoutHeadingStructure,
                focusSummaryInHeading:base.focusSummaryInHeading,
                focusSummaryInHeadingCopy:base.focusSummaryInHeadingCopy,
                focusSummaryLeftOfPreview:base.focusSummaryLeftOfPreview,
                previewActionInHeading:base.previewActionInHeading,
                slotCountInHeading:base.slotCountInHeading,
                slotGroupHeadings:base.slotGroupHeadings,
                legacyLowerFocusSummaryCount:base.legacyLowerFocusSummaryCount,
                eyebrow:base.loadoutEyebrow,
                title:base.loadoutTitle,
                overflow:base.loadoutHeadingOverflow
            }));
        check(base.infoActionCount === 0 && base.infoPanelCount === 0,
            label + ' exposes no candidate detail or pin action/panel', JSON.stringify(base));
        check(base.previewActionCount === 0 && base.vitalCount === 0
            && base.duplicateActionHelp === 0,
            label + ' has no fake state switch, invented vitals, or duplicate action help', JSON.stringify(base));
        check(!base.horizontalOverflow, label + ' has no horizontal workbench overflow');
        check(base.scrollRegions.length === 0,
            label + ' fresh empty candidate state does not create a phantom scroll region', base.scrollRegions);
        check(base.armorTabStops === 1 && base.weaponTabStops === 1
            && base.drugTabStops === 1 && base.candidateTabStops === 0,
            label + ' fresh view exposes only the three populated slot roving groups', JSON.stringify(base));
        check(base.selectedSlots === 0 && base.selectedCandidates === 0
            && base.selectedSlotKey === '' && base.selectedCandidateKey === ''
            && base.overlayCopy === '' && base.overlayHidden && base.candidates === 0
            && base.routineNoticeKind === 'browsing' && base.routineNoticeHidden
            && base.candidateState === 'unselected'
            && base.candidateStatement === '先选择左侧槽位'
            && base.candidateNextStep.indexOf('选择一个槽位') >= 0,
            label + ' fresh open hides empty preview and routine footer chrome',
            JSON.stringify(base));
        check(base.slotCandidateBadgeCount === 19
            && base.slotCandidateCounts['armor:头部装备'].value === '2'
            && base.slotCandidateCounts['armor:下装装备'].value === '0'
            && base.slotCandidateCounts['armor:颈部装备'].value === '0'
            && base.slotCandidateCounts['weapon:长枪'].value === '3'
            && base.slotCandidateCounts['weapon:手枪'].value === '2'
            && base.slotCandidateCounts['weapon:手枪2'].value === '3'
            && base.slotCandidateCounts['weapon:刀'].value === '0'
            && base.slotCandidateCounts['weapon:手雷'].value === '5'
            && ['drug:drug1','drug:drug2','drug:drug3','drug:drug4',
                'drug:drug5','drug:drug6','drug:drug7','drug:drug8']
                .every(key => base.slotCandidateCounts[key].value === '7')
            && Object.values(base.slotCandidateCounts).every(count =>
                count.state === 'known' && count.fontSize >= 10
                    && count.insideCard && count.aria.indexOf('背包候选') >= 0),
            label + ' initial unselected snapshot renders authoritative 11+8 counts, explicit zero and pistol alias',
            JSON.stringify(base.slotCandidateCounts));
        const countFallback = await page.evaluate(() => {
            const harness = CharacterBuildHarness;
            const key = 'weapon:长枪';
            const readsBefore = harness.actionLog.candidateReads.length;
            const scroll = document.querySelector(
                '.character-build-candidate-scroll');
            document.querySelector(
                '[data-roving-key="' + key + '"]').focus();
            const scrollBefore = scroll.scrollTop;
            harness.setScenario('unknown');
            const badges = Array.from(document.querySelectorAll(
                '[data-slot-candidate-count]'));
            const unknown = {
                badgeCount:badges.length,
                allUnknown:badges.every(node =>
                    node.getAttribute('data-count-state') === 'unknown'
                        && node.textContent === '—'),
                focusKey:document.activeElement
                    && document.activeElement.getAttribute('data-roving-key'),
                summary:document.querySelector('[data-focus-summary]').textContent,
                scrollTop:scroll.scrollTop
            };
            harness.setScenario('full');
            return {
                unknown,
                restoredCount:document.querySelector(
                    '[data-roving-key="' + key + '"]')
                    .getAttribute('data-candidate-count'),
                restoredFocus:document.activeElement
                    && document.activeElement.getAttribute('data-roving-key'),
                reads:harness.actionLog.candidateReads.length - readsBefore,
                scrollStable:scroll.scrollTop === scrollBefore
            };
        });
        check(countFallback.unknown.badgeCount === 19
            && countFallback.unknown.allUnknown
            && countFallback.unknown.focusKey === 'weapon:长枪'
            && countFallback.unknown.summary.indexOf('暂不可用') >= 0
            && countFallback.restoredCount === '3'
            && countFallback.restoredFocus === 'weapon:长枪'
            && countFallback.reads === 0 && countFallback.scrollStable,
            label + ' legacy omission stays unknown while snapshot redraw preserves focus/scroll and emits no business read',
            JSON.stringify(countFallback));
        const candidateStates = await page.evaluate(() => {
            const harness = CharacterBuildHarness;
            const host = document.querySelector('[data-candidate-list]');
            function state() {
                const debug = harness.view.debugState();
                return {
                    kind:host.getAttribute('data-candidate-state'),
                    statement:host.getAttribute('data-candidate-statement'),
                    nextStep:host.getAttribute('data-candidate-next-step'),
                    role:host.getAttribute('role'),
                    busy:host.getAttribute('aria-busy'),
                    requestKey:debug.candidateRequestKey,
                    count:debug.candidateCount
                };
            }
            const states = [state()];
            harness.holdCandidateRead();
            document.querySelector('[data-roving-key="armor:头部装备"]').click();
            states.push(state());
            harness.resolveCandidateRead('empty');
            states.push(state());
            harness.holdCandidateRead();
            document.querySelector('[data-roving-key="armor:上装装备"]').click();
            harness.resolveCandidateRead('error');
            states.push(state());
            const failedRequestKey = harness.view.debugState().candidateRequestKey;
            const readsBeforeRetry = harness.actionLog.candidateReads.length;
            const retry = document.querySelector('[data-candidate-retry]');
            retry.focus();
            retry.click();
            retry.click();
            const lateAccepted = harness.view.setCandidates(
                failedRequestKey, harness.fixtures.full.candidates);
            states.push(state());
            const result = {
                states,
                retryRequests:harness.actionLog.candidateReads.length - readsBeforeRetry,
                lateAccepted,
                retryDetached:!retry.isConnected,
                retryBindingGone:!retry.onclick,
                focusRestored:document.activeElement
                    && document.activeElement.hasAttribute('data-candidate-key')
            };
            harness.reset();
            return result;
        });
        check(candidateStates.states.map(state => state.kind).join('|')
                === 'unselected|loading|empty|error|ready'
            && new Set(candidateStates.states.map(state => state.statement)).size === 5
            && new Set(candidateStates.states.map(state => state.nextStep)).size === 5
            && candidateStates.states.map(state => state.role).join('|')
                === 'status|status|status|alert|listbox'
            && candidateStates.states.map(state => state.busy).join('|')
                === 'false|true|false|false|false',
            label + ' candidate presenter distinguishes all five statement/next-step states',
            JSON.stringify(candidateStates));
        check(candidateStates.retryRequests === 1 && !candidateStates.lateAccepted
            && candidateStates.retryDetached && candidateStates.retryBindingGone
            && candidateStates.focusRestored && candidateStates.states[4].count === 12
            && candidateStates.states[3].requestKey !== candidateStates.states[4].requestKey,
            label + ' error retry issues once, restores focus, and rejects the late request',
            JSON.stringify(candidateStates));
        check(Math.abs(base.rootRect.width - 1024) < 1 && Math.abs(base.rootRect.height - 576) < 1,
            label + ' preserves the 1024x576 design canvas', JSON.stringify(base.rootRect));
        await page.evaluate(() => {
            window.__dollCanvasIdentity = document.querySelector('.character-build-doll-canvas');
        });
        const embeddedWheel = await page.evaluate(() => {
            const mount = document.querySelector('[data-doll-preview-mount]');
            const canvas = document.querySelector('.character-build-doll-canvas');
            const event = new WheelEvent('wheel', {
                deltaY:-120, clientX:20, clientY:20, bubbles:true, cancelable:true
            });
            const accepted = mount.dispatchEvent(event);
            return {
                accepted,
                defaultPrevented:event.defaultPrevented,
                transform:canvas.style.transform,
                camera:CharacterBuildHarness.view._dollPreview.getCameraState(),
                controlsDisabled:Array.from(document.querySelectorAll(
                    '[data-inspection-action]')).every(node => node.disabled)
            };
        });
        check(embeddedWheel.accepted && !embeddedWheel.defaultPrevented
            && embeddedWheel.transform === '' && !embeddedWheel.camera.enabled
            && embeddedWheel.camera.zoom === 1 && embeddedWheel.camera.panX === 0
            && embeddedWheel.camera.panY === 0 && embeddedWheel.controlsDisabled,
            label + ' embedded build leaves wheel ownership and camera state untouched',
            JSON.stringify(embeddedWheel));
        await page.click('[data-doll-preview-open]');
        const expandedPreview = await page.evaluate(() => {
            const root = document.querySelector('.character-build-workbench');
            const canvas = root.querySelector('.character-build-doll-canvas');
            const rect = canvas.getBoundingClientRect();
            const previewPage = root.querySelector('[data-doll-preview-page]');
            const mount = root.querySelector('[data-doll-preview-mount]');
            const footer = root.querySelector('.character-build-doll-preview-footer');
            const controls = root.querySelector('.workbench-inspection-controls');
            const closeRect = root.querySelector('[data-doll-preview-close]').getBoundingClientRect();
            const controlButtons = Array.from(root.querySelectorAll(
                '[data-inspection-action]'));
            const header = root.closest('.inventory-workbench-panel')
                && root.closest('.inventory-workbench-panel').querySelector('.workbench-header');
            return {
                state:CharacterBuildHarness.view.debugState(),
                camera:CharacterBuildHarness.view._dollPreview.getCameraState(),
                canvasIdentity:canvas === window.__dollCanvasIdentity,
                canvasCount:root.querySelectorAll('canvas').length,
                overlayCount:root.querySelectorAll('[data-layer="candidate-preview"]').length,
                area:rect.width * rect.height,
                bodyInert:root.querySelector('.character-build-body').hasAttribute('inert'),
                headerInert:!header || header.hasAttribute('inert'),
                focus:document.activeElement === mount,
                stageParent:root.querySelector('.character-build-doll-stage').parentNode === mount,
                actions:controlButtons.map(node => node.getAttribute('data-inspection-action')),
                closeTarget:{width:closeRect.width, height:closeRect.height},
                hitTargets:controlButtons.map(node => {
                    const controlRect = node.getBoundingClientRect();
                    return {
                        width:controlRect.width,
                        height:controlRect.height,
                        layoutWidth:node.offsetWidth,
                        layoutHeight:node.offsetHeight,
                        minWidth:getComputedStyle(node).minWidth,
                        minHeight:getComputedStyle(node).minHeight
                    };
                }),
                noHorizontalOverflow:[previewPage, mount, footer, controls].every(node =>
                    node.scrollWidth <= node.clientWidth + 1),
                canvasTransform:canvas.style.transform,
                stageTransform:root.querySelector('.character-build-doll-stage').style.transform,
                overlayTransform:root.querySelector(
                    '[data-layer="candidate-preview"]').style.transform
            };
        });
        check(expandedPreview.state.dollPreviewOpen && expandedPreview.canvasIdentity
            && expandedPreview.canvasCount === 1 && expandedPreview.overlayCount === 1
            && expandedPreview.area > base.canvasSize.width * base.canvasSize.height * 1.5
            && expandedPreview.bodyInert && expandedPreview.headerInert && expandedPreview.focus
            && expandedPreview.stageParent && expandedPreview.camera.enabled
            && expandedPreview.camera.zoom === 1 && expandedPreview.camera.panX === 0
            && expandedPreview.camera.panY === 0
            && expandedPreview.actions.join('|')
                === 'left|up|down|right|zoom-out|zoom-in|fit'
            && expandedPreview.closeTarget.width >= 44 && expandedPreview.closeTarget.height >= 44
            && expandedPreview.hitTargets.every(rect =>
                rect.layoutWidth >= 44 && rect.layoutHeight >= 44
                && rect.width >= 43.9 && rect.height >= 43.9)
            && expandedPreview.noHorizontalOverflow
            && expandedPreview.canvasTransform.includes('scale(1)')
            && expandedPreview.stageTransform === '' && expandedPreview.overlayTransform === '',
            label + ' enlarged preview reparents one live Canvas into a focused camera with 44px controls',
            JSON.stringify(expandedPreview));
        const wheelZoom = await page.evaluate(() => {
            const mount = document.querySelector('[data-doll-preview-mount]');
            const rect = mount.getBoundingClientRect();
            const event = new WheelEvent('wheel', {
                deltaY:-120,
                clientX:rect.left + rect.width / 2,
                clientY:rect.top + rect.height / 2,
                bubbles:true,
                cancelable:true
            });
            const accepted = mount.dispatchEvent(event);
            const canvas = document.querySelector('.character-build-doll-canvas');
            const transformed = Array.from(document.querySelectorAll(
                '[data-doll-preview-page] [style]')).filter(node => node.style.transform);
            return {
                accepted,
                defaultPrevented:event.defaultPrevented,
                camera:CharacterBuildHarness.view._dollPreview.getCameraState(),
                status:document.querySelector('.workbench-inspection-status').textContent,
                canvasTransform:canvas.style.transform,
                onlyCanvasTransformed:transformed.length === 1 && transformed[0] === canvas
            };
        });
        check(!wheelZoom.accepted && wheelZoom.defaultPrevented
            && wheelZoom.camera.zoom === 1.2 && Math.abs(wheelZoom.camera.panX) <= 0.25
            && Math.abs(wheelZoom.camera.panY) <= 0.25 && wheelZoom.status === '120%'
            && wheelZoom.canvasTransform.includes('scale(1.2)')
            && wheelZoom.onlyCanvasTransformed,
            label + ' expanded wheel zoom is consumed and transforms the Canvas only',
            JSON.stringify(wheelZoom));
        await page.click('[data-inspection-action="zoom-in"]');
        const plusZoom = await page.evaluate(() => ({
            camera:CharacterBuildHarness.view._dollPreview.getCameraState(),
            status:document.querySelector('.workbench-inspection-status').textContent
        }));
        await page.click('[data-inspection-action="zoom-out"]');
        const minusZoom = await page.evaluate(() => ({
            camera:CharacterBuildHarness.view._dollPreview.getCameraState(),
            status:document.querySelector('.workbench-inspection-status').textContent
        }));
        check(plusZoom.camera.zoom === 1.4 && plusZoom.status === '140%'
            && minusZoom.camera.zoom === 1.2 && minusZoom.status === '120%',
            label + ' explicit plus and minus controls adjust the same camera',
            JSON.stringify({plusZoom, minusZoom}));
        await page.focus('[data-doll-preview-mount]');
        await page.keyboard.press('ArrowRight');
        const arrowPan = await page.evaluate(() => ({
            camera:CharacterBuildHarness.view._dollPreview.getCameraState(),
            canvasTransform:document.querySelector(
                '.character-build-doll-canvas').style.transform
        }));
        check(arrowPan.camera.zoom === 1.2 && Math.abs(arrowPan.camera.panX - 34) <= 0.25
            && Math.abs(arrowPan.camera.panY) <= 0.25
            && arrowPan.canvasTransform.includes('translate3d(34px')
            && arrowPan.canvasTransform.includes('scale(1.2)'),
            label + ' focused preview moves with arrow keys', JSON.stringify(arrowPan));
        await page.click('[data-inspection-action="fit"]');
        const fittedPreview = await page.evaluate(() => ({
            camera:CharacterBuildHarness.view._dollPreview.getCameraState(),
            status:document.querySelector('.workbench-inspection-status').textContent,
            transform:document.querySelector('.character-build-doll-canvas').style.transform
        }));
        check(fittedPreview.camera.zoom === 1 && fittedPreview.camera.panX === 0
            && fittedPreview.camera.panY === 0 && fittedPreview.status === '100%'
            && fittedPreview.transform.includes('translate3d(0px')
            && fittedPreview.transform.includes('scale(1)'),
            label + ' full-view control restores fit zoom and origin', JSON.stringify(fittedPreview));
        await page.click('[data-inspection-action="zoom-in"]');
        await page.focus('[data-doll-preview-mount]');
        await page.keyboard.press('ArrowDown');
        await page.keyboard.press('Escape');
        const escapedPreview = await page.evaluate(() => {
            const state = CharacterBuildHarness.view.debugState();
            return {
                closed:!state.dollPreviewOpen,
                camera:CharacterBuildHarness.view._dollPreview.getCameraState(),
                canvasIdentity:document.querySelector('.character-build-doll-canvas')
                    === window.__dollCanvasIdentity,
                stageHome:document.querySelector('.character-build-doll-stage').parentNode
                    .hasAttribute('data-doll-stage-home'),
                focus:document.activeElement.hasAttribute('data-doll-preview-open'),
                transform:document.querySelector('.character-build-doll-canvas').style.transform
            };
        });
        check(escapedPreview.closed && !escapedPreview.camera.enabled
            && escapedPreview.camera.zoom === 1 && escapedPreview.camera.panX === 0
            && escapedPreview.camera.panY === 0 && escapedPreview.canvasIdentity
            && escapedPreview.stageHome && escapedPreview.focus
            && escapedPreview.transform === '',
            label + ' preview Escape restores stage, opener and a cleared transient camera',
            JSON.stringify(escapedPreview));
        await page.click('[data-doll-preview-open]');
        const reopenedPreview = await page.evaluate(() => ({
            state:CharacterBuildHarness.view.debugState(),
            camera:CharacterBuildHarness.view._dollPreview.getCameraState(),
            canvasIdentity:document.querySelector('.character-build-doll-canvas')
                === window.__dollCanvasIdentity,
            focus:document.activeElement === document.querySelector('[data-doll-preview-mount]'),
            transform:document.querySelector('.character-build-doll-canvas').style.transform
        }));
        check(reopenedPreview.state.dollPreviewOpen && reopenedPreview.camera.enabled
            && reopenedPreview.camera.zoom === 1 && reopenedPreview.camera.panX === 0
            && reopenedPreview.camera.panY === 0 && reopenedPreview.canvasIdentity
            && reopenedPreview.focus && reopenedPreview.transform.includes('scale(1)'),
            label + ' reopening starts from a clean full-view camera on the same Canvas',
            JSON.stringify(reopenedPreview));
        await page.keyboard.press('Escape');
        if (shotArg) {
            await page.waitForFunction(() => {
                const preview = document.querySelector('[data-doll-preview-page]');
                return preview && preview.getAttribute('aria-hidden') === 'true'
                    && getComputedStyle(preview).visibility === 'hidden';
            }, null, {timeout:3000});
            const directory = path.resolve(shotArg.slice('--shot-dir='.length));
            fs.mkdirSync(directory, {recursive:true});
            await page.screenshot({
                path:path.join(directory, 'character-build-' + label + '-fresh.png'),
                fullPage:true
            });
        }

        await page.focus('[data-armor-grid] [data-roving-key="armor:头部装备"]');
        await page.keyboard.press('ArrowRight');
        check(await page.evaluate(() => document.activeElement.getAttribute('data-roving-key')) === 'armor:上装装备',
            label + ' ArrowRight follows armor columns');
        await page.keyboard.press('ArrowDown');
        const armorArrow = await page.evaluate(() => ({
            active:document.activeElement.getAttribute('data-roving-key'),
            summary:document.querySelector('[data-focus-summary]').textContent,
            state:CharacterBuildHarness.view.debugState(),
            selected:document.querySelectorAll('.character-build-slot[aria-selected="true"]').length,
            overlay:document.querySelector('[data-overlay-copy]').textContent,
            overlayHidden:document.querySelector(
                '[data-layer="candidate-preview"]').hidden
        }));
        check(armorArrow.active === 'armor:脚部装备'
            && armorArrow.summary.includes('脚部') && armorArrow.state.selectedSlotKey === ''
            && armorArrow.state.selectedCandidateKey === '' && armorArrow.selected === 0
            && armorArrow.overlay === '' && armorArrow.overlayHidden,
            label + ' armor Arrow navigation updates summary without selecting or previewing',
            JSON.stringify(armorArrow));

        await page.evaluate(() => CharacterBuildHarness.setScenario('empty'));
        const empty = await page.evaluate(() => ({
            empty:document.querySelectorAll('.character-build-slot[data-empty="true"]').length,
            active:document.activeElement && document.activeElement.getAttribute('data-roving-key'),
            state:CharacterBuildHarness.view.debugState()
        }));
        check(empty.empty === 4, label + ' empty fixture renders four explicit empty slots', JSON.stringify(empty));
        check(empty.active === 'armor:脚部装备' && empty.state.selectedSlotKey === ''
            && empty.state.selectedCandidateKey === '',
            label + ' DOM rebuild restores focus without inventing a selection', JSON.stringify(empty));

        await page.evaluate(() => CharacterBuildHarness.setScenario('cooldown'));
        const cooldown = await page.evaluate(() => {
            const nodes = ['drug1','drug5'].map(id => document.querySelector(
                '[data-roving-key="drug:' + id + '"]'));
            return {
                ready:nodes.map(node => node.getAttribute('data-drug-ready')),
                blocked:nodes.map(node => node.getAttribute('data-blocked')),
                disabled:nodes.map(node => node.getAttribute('aria-disabled')),
                progress:nodes.map(node => node.getAttribute('data-cooldown-progress')),
                remaining:nodes.map(node => node.getAttribute('data-cooldown-remaining-ms')),
                switchStatus:document.querySelector('[data-drug-switch-status]').textContent
            };
        });
        check(cooldown.ready.every(value => value === 'false')
            && cooldown.blocked.every(value => value === 'true')
            && cooldown.disabled.every(value => value === 'true')
            && cooldown.progress.every(value => value === '33')
            && cooldown.remaining.every(value => value === '2000')
            && cooldown.switchStatus.includes('冷却 2.0s'),
            label + ' paired drug slots and switch affordance expose the same cooldown lock',
            JSON.stringify(cooldown));

        await page.evaluate(() => CharacterBuildHarness.setScenario('full'));
        await page.focus('[data-armor-grid] [data-roving-key="armor:头部装备"]');
        await page.keyboard.press('Enter');
        const afterSlotActivation = await metrics(page);
        check(afterSlotActivation.selectedSlotKey === 'armor:头部装备'
            && afterSlotActivation.selectedCandidateKey === ''
            && afterSlotActivation.candidates === 12
            && afterSlotActivation.overlayCopy === '' && afterSlotActivation.overlayHidden
            && afterSlotActivation.candidateTabStops === 1
            && afterSlotActivation.scrollRegions.every(region => region === 'candidates'),
            label + ' native Enter selects a slot before candidates become reachable',
            JSON.stringify(afterSlotActivation));
        await page.focus('.character-build-candidate[data-roving-key="candidate-1"]');
        await page.keyboard.press('ArrowRight');
        const candidateArrow = await page.evaluate(() => ({
            active:document.activeElement.getAttribute('data-roving-key'),
            summary:document.querySelector('[data-candidate-focus-summary]').textContent,
            state:CharacterBuildHarness.view.debugState(),
            selected:document.querySelectorAll('.character-build-candidate[aria-selected="true"]').length,
            overlay:document.querySelector('[data-overlay-copy]').textContent,
            overlayHidden:document.querySelector(
                '[data-layer="candidate-preview"]').hidden
        }));
        check(candidateArrow.active === 'candidate-2'
            && candidateArrow.summary.includes('烈火吉他')
            && candidateArrow.state.selectedCandidateKey === ''
            && candidateArrow.selected === 0 && candidateArrow.overlay === ''
            && candidateArrow.overlayHidden,
            label + ' candidate Arrow navigation updates summary without selecting or previewing',
            JSON.stringify(candidateArrow));
        await page.click('.character-build-candidate[data-roving-key="candidate-2"]');
        await page.click('.character-build-candidate[data-roving-key="candidate-2"]');
        const pointerDeselection = await page.evaluate(() => ({
            state:CharacterBuildHarness.view.debugState(),
            selected:document.querySelectorAll(
                '.character-build-candidate[aria-selected="true"]').length,
            overlayHidden:document.querySelector(
                '[data-layer="candidate-preview"]').hidden
        }));
        check(pointerDeselection.state.selectedCandidateKey === ''
            && pointerDeselection.selected === 0 && pointerDeselection.overlayHidden,
            label + ' repeated pointer activation clears a legal empty preview state',
            JSON.stringify(pointerDeselection));
        await page.keyboard.press('Space');
        const explicitSelection = await page.evaluate(() => ({
            state:CharacterBuildHarness.view.debugState(),
            slots:document.querySelectorAll('.character-build-slot[aria-selected="true"]').length,
            candidates:document.querySelectorAll('.character-build-candidate[aria-selected="true"]').length,
            overlay:document.querySelector('[data-overlay-copy]').textContent,
            overlayHidden:document.querySelector(
                '[data-layer="candidate-preview"]').hidden
        }));
        check(explicitSelection.state.selectedSlotKey === 'armor:头部装备'
            && explicitSelection.state.selectedCandidateKey === 'candidate-2'
            && explicitSelection.slots === 1 && explicitSelection.candidates === 1
            && !explicitSelection.overlayHidden
            && explicitSelection.overlay === '预览 · 烈火吉他',
            label + ' native Space activation explicitly selects the candidate preview',
            JSON.stringify(explicitSelection));
        const threeActionRow = await metrics(page);
        check(threeActionRow.candidateActionCount === 3
            && threeActionRow.actionLabels.join('|') === '装备|调制候选|卸下'
            && threeActionRow.actionAria.join('|') ===
                '装备所选候选|调制所选候选：烈火吉他|卸下当前物品'
            && threeActionRow.actionSameRow && threeActionRow.actionInsideContextRow
            && !threeActionRow.actionOverflow && !threeActionRow.actionClipped
            && !threeActionRow.actionWrapped && threeActionRow.minActionWidth >= 44
            && threeActionRow.infoActionCount === 0 && threeActionRow.infoPanelCount === 0,
            label + ' three candidate actions stay on one context row with full accessible names',
            JSON.stringify(threeActionRow));
        check(await page.evaluate(() => CharacterBuildHarness.actionLog.commits.length === 0),
            label + ' first candidate activation never submits');
        await page.keyboard.press('Space');
        const spaceDeselection = await page.evaluate(() => ({
            state:CharacterBuildHarness.view.debugState(),
            selected:document.querySelectorAll(
                '.character-build-candidate[aria-selected="true"]').length,
            overlayHidden:document.querySelector(
                '[data-layer="candidate-preview"]').hidden
        }));
        check(spaceDeselection.state.selectedCandidateKey === ''
            && spaceDeselection.selected === 0 && spaceDeselection.overlayHidden
            && await page.evaluate(() => CharacterBuildHarness.actionLog.commits.length === 0),
            label + ' repeated Space clears the preview without submitting',
            JSON.stringify(spaceDeselection));
        await page.evaluate(() => document.activeElement.dispatchEvent(new KeyboardEvent(
            'keydown', {key:'Enter', repeat:true, bubbles:true, cancelable:true})));
        check(await page.evaluate(() => CharacterBuildHarness.actionLog.commits.length === 0
                && CharacterBuildHarness.view.debugState().selectedCandidateKey === 'candidate-2'),
            label + ' an auto-repeat Enter may restore preview but cannot cross the shared commit gate');
        await page.keyboard.press('Enter');
        check(await page.evaluate(() =>
            CharacterBuildHarness.actionLog.commits.join('|') === 'candidate-2'),
            label + ' a deliberate Enter on the same preview submits exactly once');

        await page.focus('[data-armor-grid] [data-roving-key="armor:头部装备"]');
        await page.keyboard.press('Tab');
        const tabWeapon = await page.evaluate(() => document.activeElement.getAttribute('data-slot-kind'));
        await page.keyboard.press('Tab');
        const tabDrug = await page.evaluate(() => document.activeElement.getAttribute('data-slot-kind'));
        await page.keyboard.press('Tab');
        const tabScope = await page.evaluate(() => document.activeElement.getAttribute('data-choice'));
        await page.keyboard.press('Tab');
        const tabScopeAlt = await page.evaluate(() => document.activeElement.getAttribute('data-choice'));
        await page.keyboard.press('Tab');
        const tabAction = await page.evaluate(() => ({
            action:document.activeElement.getAttribute('data-build-action'),
            label:document.activeElement.getAttribute('aria-label')
        }));
        check(tabWeapon === 'weapon' && tabDrug === 'drug'
            && tabScope === 'compatible' && tabScopeAlt === 'backpack'
            && tabAction.action === 'commit' && tabAction.label === '装备所选候选',
            label + ' Tab order follows the visual hierarchy: loadout groups then candidate scope and actions',
            JSON.stringify({tabWeapon, tabDrug, tabScope, tabScopeAlt, tabAction}));

        await page.focus('.character-build-candidate[data-roving-key="candidate-1"]');
        await page.keyboard.press('ArrowDown');
        const candidateDown = await page.evaluate(() => {
            const state = CharacterBuildHarness.view.debugState();
            const grid = document.querySelector('[data-candidate-list]');
            return {
                active:document.activeElement.getAttribute('data-roving-key'),
                columns:getComputedStyle(grid).gridTemplateColumns.split(/\s+/).length,
                selected:state.selectedCandidateKey,
                overlay:document.querySelector('[data-overlay-copy]').textContent
            };
        });
        check(candidateDown.active === 'candidate-' + (candidateDown.columns + 1)
            && candidateDown.selected === 'candidate-2'
            && candidateDown.overlay.indexOf('烈火吉他') >= 0,
            label + ' canonical candidate grid ArrowDown moves focus without changing preview',
            JSON.stringify(candidateDown));

        await page.click('[data-header-action="stats"]');
        const stats = await page.evaluate(() => {
            const root = document.querySelector('.character-build-workbench').getBoundingClientRect();
            const page = document.querySelector('.character-build-stats-page');
            const rect = page.getBoundingClientRect();
            const scroll = page.querySelector('[data-scroll-region="stats"]');
            const grid = page.querySelector('[data-stats-detail-grid]');
            const rows = Array.from(grid.querySelectorAll('dl > div'));
            const labels = rows.map(row => row.querySelector('dt'));
            const fontNodes = Array.from(grid.querySelectorAll('h4,dt,dd'));
            const visibleTextNodes = Array.from(page.querySelectorAll(
                '[data-stats-grid] *')).filter(node => {
                const style = getComputedStyle(node);
                return node.childElementCount === 0 && node.textContent.trim()
                    && style.display !== 'none' && style.visibility !== 'hidden';
            });
            const columns = getComputedStyle(grid).gridTemplateColumns.trim().split(/\s+/).filter(Boolean);
            const encumbrance = page.querySelector('[data-stats-encumbrance]');
            const chartKeys = Array.from(page.querySelectorAll('[data-chart]'))
                .map(node => node.getAttribute('data-chart'));
            const resistanceChartIcons = Array.from(page.querySelectorAll(
                '[data-chart="resistance"] [data-resistance-key]'));
            const resistanceDetailIcons = Array.from(page.querySelectorAll(
                '[data-stats-group="resistance"] [data-resistance-key]'));
            const resistanceSvgs = resistanceChartIcons.concat(resistanceDetailIcons)
                .map(node => node.querySelector('svg'));
            const visibleHeaderActions = Array.from(document.querySelectorAll(
                '.character-build-header [data-header-action]')).filter(node => {
                const style = getComputedStyle(node);
                return !node.hidden && style.display !== 'none' && style.visibility !== 'hidden';
            }).map(node => node.getAttribute('data-header-action'));
            return {
                active:page.getAttribute('aria-hidden') === 'false' && page.classList.contains('active'),
                focused:document.activeElement === scroll,
                fullWidth:Math.abs(rect.left - root.left) <= 2 && Math.abs(rect.right - root.right) <= 2,
                scrolls:scroll.scrollHeight > scroll.clientHeight + 1,
                visibleHeaderActions,
                bodyBackButtons:page.querySelectorAll('.character-build-stats-heading button').length,
                rowCount:rows.length,
                columns:columns.length,
                chartKeys,
                resistanceChartIcons:resistanceChartIcons.length,
                resistanceDetailIcons:resistanceDetailIcons.length,
                resistanceIconOrder:resistanceChartIcons.map(
                    node => node.getAttribute('data-resistance-key')),
                resistanceSvgSafe:resistanceSvgs.every(svg =>
                    svg && svg.getAttribute('aria-hidden') === 'true'
                    && svg.getAttribute('focusable') === 'false'),
                weightRatio:Number(encumbrance.getAttribute('data-weight-ratio')),
                weightCopy:encumbrance.textContent.replace(/\s+/g, ' ').trim(),
                styledTitleParts:page.querySelectorAll('[data-styled-title] > span').length,
                ratioDetail:page.querySelector('[data-stat-key="weightRatio"] dd').textContent,
                minFont:Math.min.apply(Math, fontNodes.map(node => parseFloat(getComputedStyle(node).fontSize))),
                minVisibleTextFont:Math.min.apply(Math, visibleTextNodes.map(
                    node => parseFloat(getComputedStyle(node).fontSize))),
                labelsUnclipped:labels.every(node => {
                    const style = getComputedStyle(node);
                    return style.textOverflow !== 'ellipsis' && style.whiteSpace !== 'nowrap'
                        && node.scrollWidth <= node.clientWidth + 1;
                })
            };
        });
        check(stats.active && stats.focused && stats.fullWidth,
            label + ' stats opens as a full-width focused SecondaryPage', JSON.stringify(stats));
        check(stats.visibleHeaderActions.join('|') === 'back-build|help|close'
            && stats.bodyBackButtons === 0,
            label + ' stats uses the main header with exactly back/help/close actions',
            JSON.stringify(stats));
        check(stats.scrolls, label + ' stats SecondaryPage owns its one vertical scroll region');
        check(stats.rowCount === 47 && stats.columns === 3 && stats.minFont >= 11
            && stats.minVisibleTextFont >= 11
            && stats.labelsUnclipped && stats.chartKeys.join('|') === 'power|resistance'
            && stats.resistanceChartIcons === 8 && stats.resistanceDetailIcons === 8
            && stats.resistanceSvgSafe
            && stats.resistanceIconOrder.join('|') === [
                'energyResistance','heatResistance','corrosionResistance','poisonResistance',
                'coldResistance','lightningResistance','waveResistance','impactResistance'
            ].join('|')
            && stats.styledTitleParts === 1 && stats.ratioDetail === '36.3%'
            && Math.abs(stats.weightRatio - 0.36267605633802817) < 0.000001
            && ['103kg','14.6m/s','71kg','142kg','284kg'].every(
                value => stats.weightCopy.includes(value)),
            label + ' stats renders exact 47 rows in 3x3 groups with an icon-assisted 4x2 resistance matrix',
            JSON.stringify(stats));
        if (shotArg) {
            const directory = path.resolve(shotArg.slice('--shot-dir='.length));
            fs.mkdirSync(directory, {recursive:true});
            await page.waitForTimeout(250);
            await page.screenshot({
                path:path.join(directory, 'character-build-' + label + '-stats.png'),
                fullPage:true
            });
        }
        await page.keyboard.press('Escape');
        await page.waitForFunction(() => {
            const statsPage = document.querySelector('.character-build-stats-page');
            const style = getComputedStyle(statsPage);
            return statsPage.getAttribute('aria-hidden') === 'true'
                && style.opacity === '0' && style.visibility === 'hidden';
        });
        check(await page.evaluate(() => {
            const actions = Array.from(document.querySelectorAll(
                '.character-build-header [data-header-action]')).filter(node => !node.hidden
                    && getComputedStyle(node).display !== 'none').map(node => node.getAttribute('data-header-action'));
            return document.activeElement.getAttribute('data-header-action') === 'stats'
                && actions.join('|') === 'storage|stats|help|close';
        }), label + ' Escape closes stats, restores its opener and main header actions');
        await page.evaluate(() => {
            window.__characterBuildOuterCloseCount = 0;
            CharacterBuildHarness.view._onRequestClose = function() {
                window.__characterBuildOuterCloseCount += 1;
                return true;
            };
            CharacterBuildHarness.view.consumeEscape();
        });
        check(await page.evaluate(() => {
            const state = CharacterBuildHarness.view.debugState();
            return state.selectedCandidateKey === '' && window.__characterBuildOuterCloseCount === 0;
        }), label + ' parent Escape dispatch clears the uncommitted candidate before closing');
        await page.focus('[data-armor-grid] [data-roving-key="armor:头部装备"]');
        await page.keyboard.press('Escape');
        check(await page.evaluate(() => window.__characterBuildOuterCloseCount === 1),
            label + ' a subsequent in-view Escape propagates one outer close request');

        await page.evaluate(() => CharacterBuildHarness.setScenario('blocked'));
        await page.click('[data-armor-grid] [data-roving-key="armor:头部装备"]');
        const blockedBefore = await page.evaluate(() =>
            CharacterBuildHarness.actionLog.commits.length);
        await page.evaluate(() => {
            const node = document.querySelector(
                '.character-build-candidate[data-roving-key="candidate-1"]');
            window.__characterBuildBlockedCandidate = node;
            node.dispatchEvent(new MouseEvent('click', {
                button:0, bubbles:true, cancelable:true
            }));
            node.focus();
            node.dispatchEvent(new KeyboardEvent('keydown', {
                key:'Enter', bubbles:true, cancelable:true
            }));
            node.dispatchEvent(new KeyboardEvent('keydown', {
                key:' ', bubbles:true, cancelable:true
            }));
        });
        const blocked = await page.evaluate(() => ({
            previewActions:document.querySelectorAll('[data-preview-action]').length,
            blockedCandidates:document.querySelectorAll('.character-build-candidate[data-blocked="true"]').length,
            blockedAria:Array.from(document.querySelectorAll(
                '.character-build-candidate[data-blocked="true"]')).every(
                    node => node.getAttribute('aria-disabled') === 'true' && !node.disabled),
            notice:document.querySelector('[data-build-notice]').getAttribute('data-notice-kind'),
            active:document.activeElement && document.activeElement.getAttribute('data-roving-key'),
            focusSummary:document.querySelector('[data-candidate-focus-summary]').textContent,
            focusTitle:document.querySelector('[data-candidate-focus-summary]').title,
            selected:document.querySelectorAll('.character-build-candidate[aria-selected="true"]').length,
            commitDisabled:document.querySelector('[data-build-action="commit"]').disabled,
            commits:CharacterBuildHarness.actionLog.commits.length,
            candidateState:CharacterBuildHarness.view.debugState().candidateState,
            reason:document.querySelector('.character-build-candidate-blocked-reason').textContent,
            reasonOpacity:getComputedStyle(document.querySelector(
                '.character-build-candidate-blocked-reason')).opacity,
            cardOpacity:getComputedStyle(document.querySelector(
                '.character-build-candidate[data-blocked="true"]')).opacity,
            describedBy:document.querySelector(
                '.character-build-candidate[data-blocked="true"]').getAttribute('aria-describedby'),
            overlayHidden:document.querySelector('[data-layer="candidate-preview"]').hidden
        }));
        check(blocked.previewActions === 0 && blocked.blockedCandidates === 12 && blocked.blockedAria
            && blocked.notice === 'blocked' && blocked.focusSummary.indexOf('不可装备') >= 0
            && blocked.focusTitle === ''
            && blocked.selected === 0 && blocked.commitDisabled
            && blocked.commits === blockedBefore && blocked.overlayHidden
            && blocked.candidateState.blockedActivations === 3
            && blocked.candidateState.lastBlockedOrigin === 'keyboard'
            && blocked.reason.indexOf('不兼容') >= 0
            && blocked.reasonOpacity === '1' && blocked.cardOpacity === '1'
            && !!blocked.describedBy,
            label + ' blocked pointer/Enter/Space explains once via status notice with zero business intent',
            JSON.stringify(blocked));
        if (shotArg) {
            const directory = path.resolve(shotArg.slice('--shot-dir='.length));
            await page.screenshot({
                path:path.join(directory, 'character-build-' + label + '-blocked.png'),
                fullPage:true
            });
        }

        await page.evaluate(() => CharacterBuildHarness.setScenario('long'));
        check(await page.evaluate(() => {
            const old = window.__characterBuildBlockedCandidate;
            return old && !old.isConnected && old.__workbenchEntityTileBinding === null;
        }), label + ' candidate rerender tears down the blocked EntityTile binding');
        const longCopy = await metrics(page);
        check(!longCopy.horizontalOverflow && longCopy.minFont >= 9,
            label + ' long Chinese copy stays inside the canvas without shrinking body text',
            JSON.stringify(longCopy));

        await page.evaluate(() => {
            CharacterBuildHarness.setScenario('full');
            CharacterBuildHarness.setDensity('compact');
        });
        await page.click('[data-armor-grid] [data-roving-key="armor:头部装备"]');
        const compactCards = await page.evaluate(() => {
            const nodes = Array.from(document.querySelectorAll(
                '.character-build-candidate.inventory-slot-card'));
            const firstRect = nodes[0] && nodes[0].getBoundingClientRect();
            const secondRect = nodes[1] && nodes[1].getBoundingClientRect();
            return nodes.length === 12 && nodes.every(node =>
                Math.abs(node.getBoundingClientRect().height - 48) < 1
                && Math.abs(node.getBoundingClientRect().width - 48) < 1
                && getComputedStyle(node.querySelector('.inventory-slot-copy')).display === 'none'
                && node.querySelector('.inventory-owned-icon').getBoundingClientRect().width >= 40)
                && firstRect && secondRect
                && secondRect.left - firstRect.right <= 6
                && document.querySelectorAll('button > article').length === 0;
        });
        check(compactCards,
            label + ' compact density becomes the shared 48px icon-first candidate grid');
        const densityRoundTrip = await page.evaluate(() => {
            const grid = document.querySelector('[data-candidate-list]');
            const first = grid.querySelector('[data-candidate-key]');
            first.focus();
            const keys = Array.from(grid.querySelectorAll('[data-candidate-key]'))
                .map(node => node.getAttribute('data-candidate-key')).join('|');
            CharacterBuildHarness.setDensity('full');
            const full = first === grid.querySelector('[data-candidate-key]')
                && first.getBoundingClientRect().height >= 68
                && getComputedStyle(first.querySelector('.inventory-slot-copy')).display !== 'none';
            CharacterBuildHarness.setDensity('compact');
            return {
                full,
                sameKeys:keys === Array.from(grid.querySelectorAll('[data-candidate-key]'))
                    .map(node => node.getAttribute('data-candidate-key')).join('|'),
                focusPreserved:document.activeElement === first,
                compact:grid.classList.contains('item-grid-compact')
            };
        });
        check(densityRoundTrip.full && densityRoundTrip.sameKeys
            && densityRoundTrip.focusPreserved && densityRoundTrip.compact,
            label + ' density round-trip changes only presentation and preserves DOM identity/focus/order',
            JSON.stringify(densityRoundTrip));
        await page.click('[data-drug-grid] .character-build-slot');
        check(await page.evaluate(() => {
            const commit = document.querySelector('[data-build-action="commit"]');
            return commit.textContent === '装入'
                && commit.getAttribute('aria-label') === '装入所选药剂'
                && document.querySelector('[data-build-action="tune"]').hidden;
        }), label + ' drug slots use a short visible action with full semantics and no tuning action');
        await page.click('.character-build-candidate[data-roving-key="candidate-2"]');
        await page.click('[data-armor-grid] [data-roving-key="armor:颈部装备"]');
        await page.click('.character-build-candidate[data-roving-key="candidate-3"]');
        const candidateDecisionSurface = await page.evaluate(() => ({
            actionCount:Array.from(document.querySelectorAll(
                '.character-build-candidate-actions button')).filter(node =>
                !node.hidden && getComputedStyle(node).display !== 'none').length,
            infoActions:document.querySelectorAll('[data-info-action]').length,
            infoPanels:document.querySelectorAll(
                '[data-info-panel],.character-build-info-panel').length,
            state:CharacterBuildHarness.view.debugState(),
            statsOpacity:getComputedStyle(document.querySelector('.character-build-stats-page')).opacity,
            statsVisibility:getComputedStyle(document.querySelector('.character-build-stats-page')).visibility
        }));
        check(candidateDecisionSurface.actionCount === 3
            && candidateDecisionSurface.infoActions === 0
            && candidateDecisionSurface.infoPanels === 0
            && candidateDecisionSurface.state.selectedSlotKey === 'armor:颈部装备'
            && candidateDecisionSurface.state.selectedCandidateKey === 'candidate-3'
            && candidateDecisionSurface.statsOpacity === '0'
            && candidateDecisionSurface.statsVisibility === 'hidden',
            label + ' slot/candidate changes expose only the three direct decision actions',
            JSON.stringify(candidateDecisionSurface));
        await page.click('[data-build-action="commit"]');
        await page.click('[data-build-action="unequip"]');
        check(await page.evaluate(() => CharacterBuildHarness.actionLog.commits.length === 2
            && CharacterBuildHarness.actionLog.unequips === 1),
            label + ' the unique CTA commits once and occupied slot exposes explicit unequip');
        await page.focus('.character-build-candidate[data-roving-key="candidate-3"]');
        await page.evaluate(() => CharacterBuildHarness.view.setInteractionState('write_pending'));
        check(await page.evaluate(() =>
            Array.from(document.querySelectorAll('.character-build-slot')).every(node => node.disabled)
            && Array.from(document.querySelectorAll('.character-build-candidate')).every(node =>
                node.hasAttribute('inert') && node.getAttribute('aria-disabled') === 'true')
            && document.querySelectorAll('[data-roving-key][tabindex="0"]').length === 0
            && document.querySelector('[data-build-action="commit"]').disabled
            && document.querySelector('[data-build-action="unequip"]').disabled
            && document.querySelector('.character-build-workbench').getAttribute('aria-busy') === 'true'
            && document.querySelector('[data-build-notice]').getAttribute('role') === 'status'),
            label + ' write_pending removes locked roving options and announces the busy state');
        const busyBoundary = await page.evaluate(() => {
            const before = CharacterBuildHarness.view.debugState().selectedCandidateKey;
            const commits = CharacterBuildHarness.actionLog.commits.length;
            const target = document.querySelector(
                '.character-build-candidate[data-roving-key="candidate-1"]');
            target.dispatchEvent(new MouseEvent('click', {bubbles:true}));
            target.dispatchEvent(new KeyboardEvent('keydown', {key:' ', bubbles:true}));
            return {
                before,
                after:CharacterBuildHarness.view.debugState().selectedCandidateKey,
                commits,
                afterCommits:CharacterBuildHarness.actionLog.commits.length
            };
        });
        check(busyBoundary.before === 'candidate-3' && busyBoundary.after === 'candidate-3'
            && busyBoundary.commits === busyBoundary.afterCommits,
            label + ' busy candidate article rejects synthetic pointer and keyboard activation',
            JSON.stringify(busyBoundary));
        await page.evaluate(() => CharacterBuildHarness.view.setInteractionState('mutation_reconcile'));
        await page.click('[data-build-action="commit"]');
        check(await page.evaluate(() =>
            CharacterBuildHarness.actionLog.reconciles === 1
            && document.querySelector('[data-build-action="commit"]').textContent === '确认'
            && document.querySelector('[data-build-action="commit"]')
                .getAttribute('aria-label') === '重新确认结果'),
            label + ' needs_reconcile exposes only the explicit watermark retry CTA');
        await page.evaluate(() => CharacterBuildHarness.view.setInteractionState('idle'));
        check(await page.evaluate(() => {
            const groups = ['[data-armor-grid]','[data-weapon-grid]',
                '[data-drug-grid]','[data-candidate-list]'];
            return document.activeElement.getAttribute('data-roving-key') === 'candidate-3'
                && groups.every(selector => document.querySelectorAll(
                    selector + ' [data-roving-key][tabindex="0"]').length === 1)
                && Array.from(document.querySelectorAll('[data-roving-key]')).every(node => !node.disabled)
                && document.querySelector('.character-build-workbench').getAttribute('aria-busy') === 'false'
                && document.querySelector('[data-build-notice]').textContent.indexOf('交互已恢复') >= 0;
        }), label + ' reconcile unlock rebuilds roving tab stops, restores stable focus and reports recovery');

        if (shotArg) {
            const directory = path.resolve(shotArg.slice('--shot-dir='.length));
            fs.mkdirSync(directory, {recursive:true});
            await page.waitForFunction(() => {
                const style = getComputedStyle(document.querySelector('.character-build-stats-page'));
                return style.opacity === '0' && style.visibility === 'hidden';
            });
            await page.screenshot({
                path:path.join(directory, 'character-build-' + label + '-compact.png'),
                fullPage:true
            });
        }
        const candidateDestroy = await page.evaluate(() => {
            CharacterBuildHarness.setScenario('blocked');
            document.querySelector('[data-roving-key="armor:头部装备"]').click();
            const tile = document.querySelector(
                '.character-build-candidate[data-blocked="true"]');
            const first = CharacterBuildHarness.view.destroy();
            return {
                first,
                second:CharacterBuildHarness.view.destroy(),
                detached:!tile.isConnected,
                binding:tile.__workbenchEntityTileBinding,
                rootCount:document.querySelectorAll('.character-build-workbench').length
            };
        });
        check(candidateDestroy.first && !candidateDestroy.second
            && candidateDestroy.detached && candidateDestroy.binding === null
            && candidateDestroy.rootCount === 0,
            label + ' candidate presenter destroy is idempotent and removes EntityTile listeners',
            JSON.stringify(candidateDestroy));
    } finally {
        await page.close();
    }
}

(async function main() {
    staticAudit();
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgeExecutable();
    if (!executablePath) throw new Error('Microsoft Edge not found');
    const {chromium} = require(PLAYWRIGHT);
    const server = await createServer();
    const browser = await chromium.launch({executablePath, headless:true});
    try {
        for (const viewport of VIEWPORTS) await runViewport(browser, server.address().port, viewport);
        const passed = checks.filter(item => item.ok).length;
        console.log('Character build harness: ' + passed + '/' + checks.length
            + ' passed across ' + VIEWPORTS.length + ' viewports');
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
})().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
