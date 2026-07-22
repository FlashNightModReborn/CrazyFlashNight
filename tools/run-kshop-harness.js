#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');
const {readCssBundle} = require('./lib/read-css-bundle.js');

const ROOT = path.resolve(__dirname, '..');
const WEB_ROOT = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const WORKBENCH_SOURCE = path.join(WEB_ROOT, 'modules', 'workbench.js');
const WORKBENCH_PRIMITIVES_SOURCE = path.join(WEB_ROOT, 'modules', 'workbench-primitives.js');
const WORKBENCH_COMPONENTS_SOURCE = path.join(WEB_ROOT, 'modules', 'workbench-components.js');
const INVENTORY_RUNTIME_SOURCE = path.join(WEB_ROOT, 'modules', 'inventory-runtime.js');
const INVENTORY_UI_SOURCE = path.join(WEB_ROOT, 'modules', 'inventory-ui.js');
const ITEM_FILTER_SOURCE = path.join(WEB_ROOT, 'modules', 'item-filter.js');
const INVENTORY_WORKBENCH_SOURCE = path.join(WEB_ROOT, 'modules', 'inventory-workbench.js');
const GAME_UI_BEHAVIOR_SOURCE = path.join(WEB_ROOT, 'modules', 'game-ui-behavior.js');
const KSHOP_SOURCE = path.join(WEB_ROOT, 'modules', 'kshop.js');
const NPCSHOP_SOURCE = path.join(WEB_ROOT, 'modules', 'npcshop.js');
const KSHOP_VIEWS_SOURCE = path.join(WEB_ROOT, 'modules', 'kshop-views.js');
const KSHOP_MODULE_SOURCES = [
    'kshop-cart-controller.js', 'kshop-catalog-presenter.js',
    'kshop-owned-inventory-presenter.js', 'kshop-tooltip-presenter.js'
].map(name => path.join(WEB_ROOT, 'modules', name));
const NPCSHOP_SECONDARY_SOURCE = path.join(WEB_ROOT, 'modules', 'npcshop-secondary-pages.js');
const INVENTORY_WORKBENCH_MODULE_SOURCES = [
    'inventory-workbench-config.js', 'inventory-workbench-header.js',
    'inventory-workbench-quick-transfer.js', 'inventory-workbench-owned-view.js'
].map(name => path.join(WEB_ROOT, 'modules', name));
const PANELS_SOURCE = path.join(WEB_ROOT, 'modules', 'panels.js');
const PANELS_CSS_SOURCE = path.join(WEB_ROOT, 'css', 'panels.css');
const visualArg = process.argv.find(arg => arg.startsWith('--visual='));
const shotArg = process.argv.find(arg => arg.startsWith('--shot='));
const viewportArg = process.argv.find(arg => arg.startsWith('--viewport='));

function parseViewport() {
    if (!viewportArg) return {width:1366,height:768};
    const match = viewportArg.slice('--viewport='.length).match(/^(\d+)x(\d+)$/);
    if (!match) throw new Error('Invalid --viewport, expected WIDTHxHEIGHT');
    return {width:Number(match[1]),height:Number(match[2])};
}

function auditArchitectureBoundaries() {
    const source = fs.readFileSync(WORKBENCH_SOURCE, 'utf8');
    const forbidden = ['ShopTask', 'InventoryTask', 'callId', 'saveCart', 'checkout', 'claim', 'sortAndMerge'];
    const hits = forbidden.filter(token => source.includes(token));
    if (hits.length) throw new Error('Workbench boundary violation: ' + hits.join(', '));
    const rendererStart = source.indexOf('function GridRenderer(');
    const rendererEnd = source.indexOf('function ContainerViewAdapter(', rendererStart);
    const rendererBody = source.slice(rendererStart, rendererEnd);
    if (/pending|requestMux|timerMap/.test(rendererBody)) {
        throw new Error('GridRenderer boundary violation: transport state detected');
    }
    if (/BackpackView|WarehouseView|背包\s*[×xX]\s*仓库|仓库\s*[×xX]\s*背包/.test(source)) {
        throw new Error('Workbench boundary violation: concrete owned-view pair branch detected');
    }
    const inventorySource = fs.readFileSync(INVENTORY_RUNTIME_SOURCE, 'utf8');
    const resolverStart = inventorySource.indexOf('function operationForIntent(');
    const resolverEnd = inventorySource.indexOf('function wireRef(', resolverStart);
    const resolverBody = inventorySource.slice(resolverStart, resolverEnd);
    if (/containerId\s*===|containerId\s*!==/.test(resolverBody)) {
        throw new Error('Inventory operation resolver branches on concrete container pair');
    }
    const kshopSource = fs.readFileSync(KSHOP_SOURCE, 'utf8');
    const npcshopSource = fs.readFileSync(NPCSHOP_SOURCE, 'utf8');
    const kshopUiSource = [kshopSource].concat(KSHOP_MODULE_SOURCES.map(file => fs.readFileSync(file, 'utf8'))).join('\n');
    const npcshopUiSource = npcshopSource + '\n' + fs.readFileSync(NPCSHOP_SECONDARY_SOURCE, 'utf8');
    const kshopViewsSource = fs.readFileSync(KSHOP_VIEWS_SOURCE, 'utf8');
    const workbenchComponentsSource = fs.readFileSync(WORKBENCH_COMPONENTS_SOURCE, 'utf8');
    const inventoryUiSource = fs.readFileSync(INVENTORY_UI_SOURCE, 'utf8');
    const inventoryWorkbenchSource = fs.readFileSync(INVENTORY_WORKBENCH_SOURCE, 'utf8');
    const inventoryWorkbenchUiSource = [inventoryWorkbenchSource].concat(
        INVENTORY_WORKBENCH_MODULE_SOURCES.map(file => fs.readFileSync(file, 'utf8'))
    ).join('\n');
    const panelsSource = fs.readFileSync(PANELS_SOURCE, 'utf8');
    const panelsCssSource = readCssBundle(PANELS_CSS_SOURCE, {rootDir:path.join(WEB_ROOT, 'css')});
    if (kshopSource.includes('same_container_unsupported')) {
        throw new Error('KShop still rejects generic same-container owned transfer');
    }
    if (!kshopUiSource.includes('new KShopViews.SettlementPage(')
            || !kshopViewsSource.includes('function SettlementPage(')
            || !kshopViewsSource.includes('function createCatalog(')
            || !kshopViewsSource.includes('function createOrder(')) {
        throw new Error('KShop view/settlement composition boundary is incomplete');
    }
    if (!['function SecondaryPage(', 'function ChoiceGroup(', 'function CommitBar(', 'function OwnedInventoryPane(']
            .every(token => workbenchComponentsSource.includes(token))
            || !workbenchComponentsSource.includes("require('./workbench-lifecycle.js')")
            || workbenchComponentsSource.includes('this._disposers')
            || !kshopUiSource.includes('new WorkbenchComponents.ChoiceGroup(')
            || !kshopUiSource.includes('new WorkbenchComponents.OwnedInventoryPane(')
            || !npcshopUiSource.includes('.SecondaryPage(')
            || !npcshopUiSource.includes('.CommitBar(')
            || !inventoryWorkbenchUiSource.includes('.OwnedInventoryPane(')) {
        throw new Error('Shared workbench component composition boundary is incomplete');
    }
    const extractedUiTokens = ['function warehousePageState(', 'function renderWarehousePageMenu(',
        'function onWarehousePageShortcut(', 'function changeWarehousePage(', 'function jumpWarehouseToPage('];
    const uiLeaks = extractedUiTokens.filter(token => kshopSource.includes(token));
    if (uiLeaks.length) throw new Error('KShop still owns extracted inventory UI: ' + uiLeaks.join(', '));
    if (!inventoryUiSource.includes('function InventoryWindowPager(')
            || !inventoryUiSource.includes('function InventorySortControls(')
            || !inventoryUiSource.includes('function InventoryFilterControl(')
            || !inventoryUiSource.includes('function OwnedInventoryViewShell(')
            || !inventoryUiSource.includes('function derivePageState(')
            || !inventoryUiSource.includes('function renderOwnedSlot(')) {
        throw new Error('Inventory UI component boundary is incomplete');
    }
    if ([inventoryUiSource, inventoryWorkbenchUiSource, kshopUiSource].some(text =>
            text.includes('DisplaySortControl') || text.includes('displaySortMethod')
            || text.includes('inventory-display-sort'))) {
        throw new Error('Owned inventory display sort must stay retired in favor of the authority tree');
    }
    if (!inventoryUiSource.includes('item-card item-card-owned inventory-slot-card')
            || !inventoryUiSource.includes('item-card-body inventory-slot-copy')
            || !npcshopUiSource.includes('item-card-auxiliary item-card-selection-marker')
            || !panelsCssSource.includes('.item-grid-compact .item-card-auxiliary')) {
        throw new Error('Semantic item-card density contract is incomplete');
    }
    const ownedCompositions = [kshopUiSource, npcshopUiSource, inventoryWorkbenchUiSource];
    if (!kshopUiSource.includes('new InventoryUI.OwnedInventoryViewShell(')
            || !npcshopUiSource.includes('new InventoryUI.OwnedInventoryViewShell(')
            || !inventoryWorkbenchUiSource.includes('.OwnedInventoryViewShell(')
            || ownedCompositions.some(text => text.includes('new Workbench.ItemGrid('))) {
        throw new Error('Owned inventory composition bypasses OwnedInventoryViewShell');
    }
    if (inventoryWorkbenchUiSource.includes("requestShop(")
            || inventoryWorkbenchUiSource.includes("'bulkQuery'")
            || inventoryWorkbenchUiSource.includes('shopPanelOpen')) {
        throw new Error('Standalone inventory workbench leaked into shop lifecycle');
    }
    if (!kshopUiSource.includes('InventoryUI.renderOwnedSlot(')
            || !inventoryWorkbenchUiSource.includes('.renderOwnedSlot(')) {
        throw new Error('Owned-slot renderer is not shared by shop and standalone workbench');
    }
    if (!panelsSource.includes('ensureRequiredAssets(')
            || !panelsSource.includes('Icons.load(finishRequiredAssets)')
            || !panelsSource.includes('openAfterRequiredAssets(id)')) {
        throw new Error('Panels lifecycle no longer gates first open on the shared icon manifest');
    }
    const fullAnchorBlocks = panelsCssSource.match(/[^{}]+\{[^{}]*inset:\s*0\s*;[^{}]*\}/g) || [];
    if (!fullAnchorBlocks.some(block => block.includes('#panel-container[data-panel="workbench"] #panel-content'))) {
        throw new Error('Standalone workbench no longer uses the full panel anchor');
    }
    const behaviorSource = fs.readFileSync(GAME_UI_BEHAVIOR_SOURCE, 'utf8');
    const behaviorEvents = ['selectstart', 'dragstart', 'contextmenu'];
    if (!behaviorEvents.every(eventName => behaviorSource.includes(eventName))
            || !behaviorSource.includes('[data-browser-native]')) {
        throw new Error('Game UI behavior guard is missing a required native-browser boundary');
    }
    const primitivesSource = fs.readFileSync(WORKBENCH_PRIMITIVES_SOURCE, 'utf8');
    if (!primitivesSource.includes('function EntityTile(') || !primitivesSource.includes('function ItemCard(') || !source.includes('function ItemGrid(')
            || !source.includes('function GridDensityController(')) {
        throw new Error('Workbench item/density primitives missing');
    }
    const tooltipSource = fs.readFileSync(path.join(WEB_ROOT, 'modules', 'tooltip.js'), 'utf8');
    if (!tooltipSource.includes('function bindAsync(')
            || !tooltipSource.includes('function createScope(')
            || !tooltipSource.includes('function releaseTree(')
            || !tooltipSource.includes('function bindAsyncHover(node, options) { return bindAsync(node, options); }')) {
        throw new Error('PanelTooltip binding, ownership scope, subtree release, or compatibility alias missing');
    }
    const itemFilterSource = fs.readFileSync(ITEM_FILTER_SOURCE, 'utf8');
    if (!itemFilterSource.includes('function FilterNavigator(')
            || !itemFilterSource.includes('function branchTree(')
            || !kshopUiSource.includes('itemFilter.build(')
            || !kshopUiSource.includes("{id:'curated', label:'专柜'")
            || !npcshopSource.includes('ItemFilter.build(')) {
        throw new Error('Shared item taxonomy/navigation boundary is incomplete');
    }
    if (kshopUiSource.includes('weaponSubtype:false')
            || !panelsCssSource.includes('height:48px;')
            || !panelsCssSource.includes('transition:none;')) {
        throw new Error('KShop subtype drilldown or stable category rail contract is incomplete');
    }
    if (!kshopUiSource.includes('Workbench.ItemCard.renderCatalog') || !npcshopUiSource.includes('Workbench.ItemCard.renderCatalog')) {
        throw new Error('KShop/NpcShop must render catalog cards via Workbench.ItemCard');
    }
    if (!kshopUiSource.includes('PanelTooltip.bindAsyncHover') || !npcshopUiSource.includes('.bindAsyncHover(node,')
            || !inventoryWorkbenchUiSource.includes('PanelTooltip.bindAsyncHover')) {
        throw new Error('Panel async tooltip binding is not shared across shop and workbench panels');
    }
    if (!kshopSource.includes("PanelTooltip.createScope('kshop')")
            || !kshopSource.includes('_tooltipScope.dispose()')
            || !kshopUiSource.includes('this._intent.bindAsyncHover(node, options)')) {
        throw new Error('KShop tooltip bindings are not owned by the panel session scope');
    }
    if (!panelsCssSource.includes('.item-grid-compact')) {
        throw new Error('Compact item-grid modifier styles missing');
    }
    return {
        forbiddenTokens:forbidden,
        gridRendererTransportFree:true,
        ownedPairBranchFree:true,
        sameContainerTransfer:true,
        inventoryUiComponents:true,
        authorityTreeReplacesDisplaySort:true,
        unifiedOwnedInventoryShell:true,
        semanticItemCardDensityContract:true,
        kshopViewComposition:true,
        sharedWorkbenchComponents:true,
        standaloneBattleboxWorkbench:true,
        sharedIconManifestGate:true,
        workbenchFullAnchor:true,
        nativeBehaviorGuard:behaviorEvents
    };
}

function edgePath() {
    const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : null
    ].filter(Boolean);
    return candidates.find(fs.existsSync);
}

function createServer() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(WEB_ROOT, pathname));
            const relative = path.relative(WEB_ROOT, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) {
                response.writeHead(403); response.end(); return;
            }
            fs.readFile(file, (error, data) => {
                if (error) { response.writeHead(404); response.end(); return; }
                const extension = path.extname(file);
                const mime = extension === '.html' ? 'text/html; charset=utf-8'
                    : extension === '.css' ? 'text/css; charset=utf-8'
                    : extension === '.js' ? 'text/javascript; charset=utf-8'
                    : 'application/octet-stream';
                response.writeHead(200, {'Content-Type': mime});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function runPhysicalTooltipPointerProbe(page) {
    const owner = page.locator('#tooltip-physical-hover-probe');
    const legacyOwner = page.locator('#tooltip-legacy-hover-probe');
    const blank = page.locator('#tooltip-physical-blank-probe');
    const tooltip = page.locator('#panel-tooltip');
    const ownerBox = await owner.boundingBox();
    const legacyOwnerBox = await legacyOwner.boundingBox();
    const blankBox = await blank.boundingBox();
    if (!ownerBox || !legacyOwnerBox || !blankBox) throw new Error('Physical tooltip pointer probes are missing');
    const ownerPoint = {x:ownerBox.x + ownerBox.width / 2, y:ownerBox.y + ownerBox.height / 2};
    const legacyOwnerPoint = {
        x:legacyOwnerBox.x + legacyOwnerBox.width / 2,
        y:legacyOwnerBox.y + legacyOwnerBox.height / 2
    };
    const blankPoint = {x:blankBox.x + blankBox.width / 2, y:blankBox.y + blankBox.height / 2};

    await page.mouse.move(ownerPoint.x, ownerPoint.y);
    await page.waitForFunction(() => PanelTooltip.isVisible(), null, {timeout:1000});
    const visibleOnOwner = await page.evaluate(() => PanelTooltip.isVisible());
    const tooltipBox = await tooltip.boundingBox();
    if (!tooltipBox) throw new Error('Physical pointer tooltip did not render');
    const tooltipPoint = {
        x:tooltipBox.x + Math.max(2, Math.min(tooltipBox.width - 2, tooltipBox.width / 2)),
        y:tooltipBox.y + Math.max(2, Math.min(tooltipBox.height - 2, tooltipBox.height / 2))
    };
    await page.mouse.move(tooltipPoint.x, tooltipPoint.y, {steps:4});
    await page.waitForTimeout(170);
    const hoverBridgePersistent = await page.evaluate(() => PanelTooltip.isVisible());

    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.waitForTimeout(170);
    const hoverSurfaceExitHidden = await page.evaluate(() => !PanelTooltip.isVisible());

    await page.mouse.move(ownerPoint.x, ownerPoint.y);
    await page.waitForFunction(() => PanelTooltip.isVisible(), null, {timeout:1000});
    await page.mouse.move(blankPoint.x, blankPoint.y);
    const blankLandingWasOutside = await page.evaluate(point => {
        const tip = document.getElementById('panel-tooltip');
        const hit = document.elementFromPoint(point.x, point.y);
        return !!(hit && tip && hit !== tip && !tip.contains(hit));
    }, blankPoint);
    await page.waitForTimeout(170);
    const rapidBlankLandingHidden = await page.evaluate(() => !PanelTooltip.isVisible());

    await page.mouse.move(ownerPoint.x, ownerPoint.y);
    await page.waitForFunction(() => PanelTooltip.isVisible(), null, {timeout:1000});
    await page.mouse.move(blankPoint.x, blankPoint.y);
    const geometryCoveredBlank = await page.evaluate(point => {
        const tip = document.getElementById('panel-tooltip');
        if (!tip) return false;
        tip.style.left = (point.x - 12) + 'px';
        tip.style.top = (point.y - 12) + 'px';
        // Fault injection for the browser's delayed geometry-enter ordering. It follows a
        // real owner -> blank mouse sequence but deliberately does not send a tooltip move.
        tip.dispatchEvent(new MouseEvent('mouseenter', {
            bubbles:false,clientX:point.x,clientY:point.y,relatedTarget:document.body
        }));
        const hit = document.elementFromPoint(point.x, point.y);
        return hit === tip || tip.contains(hit);
    }, blankPoint);
    await page.waitForTimeout(170);
    const lateGeometryEnterIgnored = await page.evaluate(() => !PanelTooltip.isVisible());

    // 手工 showAtMouse/hideHover 路径有独立的 global pending/timer 状态，
    // 必须也由浏览器真实 hit-test 覆盖，不能只用 bindAsync probe 代替。
    await page.mouse.move(legacyOwnerPoint.x, legacyOwnerPoint.y);
    await page.waitForFunction(() => PanelTooltip.isVisible(), null, {timeout:1000});
    const legacyVisibleOnOwner = await page.evaluate(() => PanelTooltip.isVisible());
    const legacyTooltipBox = await tooltip.boundingBox();
    if (!legacyTooltipBox) throw new Error('Legacy physical pointer tooltip did not render');
    const legacyTooltipPoint = {
        x:legacyTooltipBox.x + Math.max(2, Math.min(legacyTooltipBox.width - 2, legacyTooltipBox.width / 2)),
        y:legacyTooltipBox.y + Math.max(2, Math.min(legacyTooltipBox.height - 2, legacyTooltipBox.height / 2))
    };
    await page.mouse.move(legacyTooltipPoint.x, legacyTooltipPoint.y, {steps:4});
    await page.waitForTimeout(170);
    const legacyHoverBridgePersistent = await page.evaluate(() => PanelTooltip.isVisible());
    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.waitForTimeout(170);
    const legacyHoverSurfaceExitHidden = await page.evaluate(() => !PanelTooltip.isVisible());

    return {
        visibleOnOwner,
        hoverBridgePersistent,
        hoverSurfaceExitHidden,
        blankLandingWasOutside,
        rapidBlankLandingHidden,
        geometryCoveredBlank,
        lateGeometryEnterIgnored,
        legacyVisibleOnOwner,
        legacyHoverBridgePersistent,
        legacyHoverSurfaceExitHidden
    };
}

(async function() {
    const architectureAudit = auditArchitectureBoundaries();
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgePath();
    if (!executablePath) throw new Error('Microsoft Edge executable not found');
    const { chromium } = require(PLAYWRIGHT);
    const server = await createServer();
    const browser = await chromium.launch({executablePath, headless:true});
    const page = await browser.newPage({viewport:parseViewport()});
    const pageErrors = [];
    const failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message || String(error)));
    page.on('requestfailed', request => failedRequests.push(request.url()));
    const visualMode = visualArg ? visualArg.slice('--visual='.length) : '';
    const targetQuery = visualMode ? '?visual=' + encodeURIComponent(visualMode) : '?qa=1';
    await page.goto('http://127.0.0.1:' + server.address().port + '/modules/kshop/dev/harness.html' + targetQuery, {waitUntil:'load'});
    if (visualMode) {
        await page.waitForFunction(() => window.__visualReady === true, null, {timeout:20000});
        const physicalTooltipPointer = visualMode === 'battlebox-real-icons'
            ? await runPhysicalTooltipPointerProbe(page) : null;
        if (shotArg) {
            const shotPath = path.resolve(ROOT, shotArg.slice('--shot='.length));
            await page.screenshot({path:shotPath,fullPage:true});
        }
        const visualState = await page.evaluate(mode => ({
            state:mode.indexOf('battlebox') === 0 ? InventoryWorkbench.debugState() : KShop.debugState(),
            shellRect:(() => { const r=document.querySelector('.workbench-shell').getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; })(),
            contentRect:(() => { const r=document.getElementById('panel-content').getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; })(),
            fullAnchor:(() => { const r=document.getElementById('panel-content').getBoundingClientRect(); return Math.abs(r.x)<1 && Math.abs(r.y)<1 && Math.abs(r.width-innerWidth)<1 && Math.abs(r.height-innerHeight)<1; })(),
            headerLayout:(() => {
                const header=document.querySelector('.workbench-header');
                const actions=header && header.querySelector('.workbench-header-actions');
                if(!header || !actions) return null;
                const rectOf=node => { const r=node.getBoundingClientRect(); return {x:r.x,width:r.width,right:r.right}; };
                return {
                    header:rectOf(header), actions:rectOf(actions),
                    overflow:actions.scrollWidth>actions.clientWidth || actions.getBoundingClientRect().right>innerWidth+1,
                    children:Array.from(actions.children).map(node=>({text:(node.textContent||'').replace(/\s+/g,' ').trim(),display:getComputedStyle(node).display,rect:rectOf(node)}))
                };
            })(),
            inventoryLayout:(() => {
                const out={};
                ['backpack','warehouse','battlebox'].forEach(name => {
                    const root=document.querySelector('.inventory-owned-'+name);
                    if(!root) return;
                    if(name==='warehouse' && root.classList.contains('inventory-owned-battlebox')) return;
                    const title=root.querySelector('.workbench-view-title');
                    const toolbar=root.querySelector('.inventory-container-toolbar');
                    const grid=root.querySelector('.inventory-owned-grid');
                    out[name]={
                        occupied:root.querySelectorAll('.inventory-slot-card.occupied').length,
                        compact:!!(grid && grid.classList.contains('item-grid-compact')),
                        cardHeight:(() => { const card=root.querySelector('.inventory-slot-card'); return card ? parseFloat(getComputedStyle(card).height) : 0; })(),
                        iconHeight:(() => { const icon=root.querySelector('.inventory-slot-icon-frame'); return icon ? parseFloat(getComputedStyle(icon).height) : 0; })(),
                        title:title ? title.textContent : '',
                        titleClipped:!!(title && (title.scrollWidth-title.clientWidth>2 || title.scrollHeight-title.clientHeight>2)),
                        toolbarOverflow:!!(toolbar && (toolbar.scrollWidth>toolbar.clientWidth || toolbar.scrollHeight>toolbar.clientHeight)),
                        gridOverflow:!!(grid && (grid.scrollWidth>grid.clientWidth || grid.scrollHeight>grid.clientHeight))
                    };
                });
                return out;
            })(),
            tooltip:window.__visualTooltipState || null,
            bodyOverflow:document.body.scrollWidth > document.body.clientWidth || document.body.scrollHeight > document.body.clientHeight
        }), visualMode);
        if (visualState.tooltip) visualState.tooltip.physicalPointer = physicalTooltipPointer;
        await browser.close();
        server.close();
        process.stdout.write(JSON.stringify({browser:'edge',executablePath,visualMode,visualState,pageErrors,failedRequests},null,2)+'\n');
        const tooltipFailed = visualMode === 'battlebox-real-icons'
            && (!visualState.tooltip || !visualState.tooltip.visible || !visualState.tooltip.basicStyled
                || !visualState.tooltip.hasRichLayout || !visualState.tooltip.hasIcon
                || !visualState.tooltip.focusDescription || !visualState.tooltip.focusFallbackVisible
                || !visualState.tooltip.focusExitHidden || !visualState.tooltip.asyncFocusVisible
                || !visualState.tooltip.lateResponseStayedHidden || !visualState.tooltip.teardownStayedHidden
                || !visualState.tooltip.teardownIdempotent || !visualState.tooltip.anchoredRichRepositioned
                || !visualState.tooltip.anchoredRichInsideViewport || !visualState.tooltip.anchoredScaleGapStable
                || !visualState.tooltip.focusOwnerInitiallyVisible || !visualState.tooltip.hoverOwnerTookControl
                || !visualState.tooltip.focusedOwnerRestored || !visualState.tooltip.restoredOwnerExitHidden
                || !visualState.tooltip.hoverSurfacePersistent || !visualState.tooltip.wheelScrollsLongDescription
                || !visualState.tooltip.forcedHideResetsHoverState
                || !visualState.tooltip.penPointerHoverPersistent
                || !visualState.tooltip.lateGeometryEnterIgnored
                || !visualState.tooltip.physicalPointer
                || !visualState.tooltip.physicalPointer.visibleOnOwner
                || !visualState.tooltip.physicalPointer.hoverBridgePersistent
                || !visualState.tooltip.physicalPointer.hoverSurfaceExitHidden
                || !visualState.tooltip.physicalPointer.blankLandingWasOutside
                || !visualState.tooltip.physicalPointer.rapidBlankLandingHidden
                || !visualState.tooltip.physicalPointer.geometryCoveredBlank
                || !visualState.tooltip.physicalPointer.lateGeometryEnterIgnored
                || !visualState.tooltip.physicalPointer.legacyVisibleOnOwner
                || !visualState.tooltip.physicalPointer.legacyHoverBridgePersistent
                || !visualState.tooltip.physicalPointer.legacyHoverSurfaceExitHidden
                || !visualState.tooltip.keyboardScrollsLongDescription || !visualState.tooltip.escapeDismissesTooltip
                || !visualState.tooltip.detachedOwnerNotRestored || !visualState.tooltip.scopeCleanupComplete
                || !visualState.tooltip.placement || visualState.tooltip.placement.pointerOverlap > 0
                || visualState.tooltip.placement.anchorOverlap > 0);
        if (pageErrors.length || failedRequests.length || tooltipFailed) process.exit(1);
        return;
    }
    await page.waitForFunction(() => window.__qaResult && window.__qaResult.qa, null, {timeout:20000});
    const qa = await page.evaluate(() => window.__qaResult.qa);
    await page.goto('http://127.0.0.1:' + server.address().port + '/modules/kshop/dev/harness.html?visual=battlebox-real-icons', {waitUntil:'load'});
    await page.waitForFunction(() => window.__visualReady === true, null, {timeout:20000});
    const realTooltip = await page.evaluate(() => window.__visualTooltipState || null);
    if (realTooltip) realTooltip.physicalPointer = await runPhysicalTooltipPointerProbe(page);
    await browser.close();
    server.close();

    const output = {browser:'edge',executablePath,architectureAudit,qa,realTooltip,pageErrors,failedRequests};
    process.stdout.write(JSON.stringify(output, null, 2) + '\n');
    const tooltipFailed = !realTooltip || !realTooltip.visible || !realTooltip.basicStyled
        || !realTooltip.hasRichLayout || !realTooltip.hasIcon
        || !realTooltip.focusDescription || !realTooltip.focusFallbackVisible
        || !realTooltip.focusExitHidden || !realTooltip.asyncFocusVisible
        || !realTooltip.lateResponseStayedHidden || !realTooltip.teardownStayedHidden
        || !realTooltip.teardownIdempotent || !realTooltip.anchoredRichRepositioned
        || !realTooltip.anchoredRichInsideViewport || !realTooltip.anchoredScaleGapStable
        || !realTooltip.focusOwnerInitiallyVisible || !realTooltip.hoverOwnerTookControl
        || !realTooltip.focusedOwnerRestored || !realTooltip.restoredOwnerExitHidden
        || !realTooltip.hoverSurfacePersistent || !realTooltip.wheelScrollsLongDescription
        || !realTooltip.forcedHideResetsHoverState
        || !realTooltip.penPointerHoverPersistent
        || !realTooltip.lateGeometryEnterIgnored
        || !realTooltip.physicalPointer
        || !realTooltip.physicalPointer.visibleOnOwner
        || !realTooltip.physicalPointer.hoverBridgePersistent
        || !realTooltip.physicalPointer.hoverSurfaceExitHidden
        || !realTooltip.physicalPointer.blankLandingWasOutside
        || !realTooltip.physicalPointer.rapidBlankLandingHidden
        || !realTooltip.physicalPointer.geometryCoveredBlank
        || !realTooltip.physicalPointer.lateGeometryEnterIgnored
        || !realTooltip.physicalPointer.legacyVisibleOnOwner
        || !realTooltip.physicalPointer.legacyHoverBridgePersistent
        || !realTooltip.physicalPointer.legacyHoverSurfaceExitHidden
        || !realTooltip.keyboardScrollsLongDescription || !realTooltip.escapeDismissesTooltip
        || !realTooltip.detachedOwnerNotRestored || !realTooltip.scopeCleanupComplete
        || !realTooltip.placement || realTooltip.placement.pointerOverlap > 0
        || realTooltip.placement.anchorOverlap > 0;
    if (qa.failed || tooltipFailed || pageErrors.length || failedRequests.length) process.exit(1);
})().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(2);
});
