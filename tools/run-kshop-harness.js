#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');
const {readCssBundle} = require('./lib/read-css-bundle.js');
const BrowserChildResourceClosure = require(
    './workbench-live-e2e/lib/browser-child-resource-closure.js');

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
const INSPECTION_VIEWPORT_SOURCE = path.join(WEB_ROOT, 'modules', 'workbench-inspection-viewport.js');
const KSHOP_SOURCE = path.join(WEB_ROOT, 'modules', 'kshop.js');
const KSHOP_RUNTIME_SOURCE = path.join(WEB_ROOT, 'modules', 'kshop-runtime.js');
const KSHOP_HARNESS_SOURCE = path.join(WEB_ROOT, 'modules', 'kshop', 'dev', 'harness.html');
const NPCSHOP_SOURCE = path.join(WEB_ROOT, 'modules', 'npcshop.js');
const KSHOP_VIEWS_SOURCE = path.join(WEB_ROOT, 'modules', 'kshop-views.js');
const KSHOP_MODULE_SOURCES = [
    'kshop-cart-controller.js', 'kshop-catalog-presenter.js',
    'kshop-owned-inventory-presenter.js', 'kshop-tooltip-presenter.js'
].map(name => path.join(WEB_ROOT, 'modules', name));
const NPCSHOP_SECONDARY_SOURCE = path.join(WEB_ROOT, 'modules', 'npcshop-secondary-pages.js');
const NPCSHOP_MATERIAL_NAVIGATION_SOURCE = path.join(WEB_ROOT, 'modules', 'npcshop-material-navigation.js');
const INVENTORY_WORKBENCH_MODULE_SOURCES = [
    'inventory-workbench-config.js', 'inventory-workbench-preparation-menu.js',
    'inventory-workbench-navigation.js', 'inventory-workbench-header.js',
    'inventory-workbench-quick-transfer.js', 'inventory-workbench-owned-view.js',
    'inventory-tuning-scope.js',
    'inventory-storage-workbench.js', 'crafting-inventory-organizer.js'
].map(name => path.join(WEB_ROOT, 'modules', name));
const PANELS_SOURCE = path.join(WEB_ROOT, 'modules', 'panels.js');
const PANELS_CSS_SOURCE = path.join(WEB_ROOT, 'css', 'panels.css');
const visualArg = process.argv.find(arg => arg.startsWith('--visual='));
const shotArg = process.argv.find(arg => arg.startsWith('--shot='));
const viewportArg = process.argv.find(arg => arg.startsWith('--viewport='));
const identityOnly = process.argv.includes('--identity-only');

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
    const kshopRuntimeSource = fs.readFileSync(KSHOP_RUNTIME_SOURCE, 'utf8');
    const kshopHarnessSource = fs.readFileSync(KSHOP_HARNESS_SOURCE, 'utf8');
    if (!kshopSource.includes('onRebind: onRebind')
            || !kshopHarnessSource.includes("assert('kshop-owner2'")
            || !kshopHarnessSource.includes('商城 same-name rebind 丢弃旧业务/Inventory 回包')) {
        throw new Error('KShop same-name owner rebind journey missing');
    }
    if (!kshopRuntimeSource.includes("session.ownerPanel === 'kshop'")
            || !kshopRuntimeSource.includes("message.panel = 'kshop'")
            || !kshopRuntimeSource.includes('message.panelInstanceId = context.session.panelInstanceId')
            || !kshopRuntimeSource.includes("!Object.prototype.hasOwnProperty.call(data, 'domain')")
            || !kshopRuntimeSource.includes('data.panelInstanceId === entry.session.panelInstanceId')
            || !kshopSource.includes("ownerPanel:'kshop'")
            || !kshopHarnessSource.includes('mixedKShopOwnerRejected')
            || !kshopHarnessSource.includes('mixedKShopDomainRejected')) {
        throw new Error('KShop domain-less exact owner mux contract missing');
    }
    const inspectionViewportSource = fs.readFileSync(INSPECTION_VIEWPORT_SOURCE, 'utf8');
    const viewportScriptIndex = kshopHarnessSource.indexOf('modules/workbench-inspection-viewport.js');
    const inspectorScriptIndex = kshopHarnessSource.indexOf('modules/equipment-inspector.js');
    if (viewportScriptIndex < 0 || inspectorScriptIndex <= viewportScriptIndex
            || !inspectionViewportSource.includes('function Camera(')
            || !inspectionViewportSource.includes('Camera.prototype.destroy')) {
        throw new Error('KShop harness must load the shared inspection viewport before EquipmentInspector');
    }
    const npcshopSource = fs.readFileSync(NPCSHOP_SOURCE, 'utf8');
    const kshopUiSource = [kshopSource].concat(KSHOP_MODULE_SOURCES.map(file => fs.readFileSync(file, 'utf8'))).join('\n');
    const npcshopUiSource = [npcshopSource,
        fs.readFileSync(NPCSHOP_SECONDARY_SOURCE, 'utf8'),
        fs.readFileSync(NPCSHOP_MATERIAL_NAVIGATION_SOURCE, 'utf8')].join('\n');
    const kshopViewsSource = fs.readFileSync(KSHOP_VIEWS_SOURCE, 'utf8');
    const workbenchComponentsSource = fs.readFileSync(WORKBENCH_COMPONENTS_SOURCE, 'utf8');
    const inventoryUiSource = fs.readFileSync(INVENTORY_UI_SOURCE, 'utf8');
    const inventoryWorkbenchSource = fs.readFileSync(INVENTORY_WORKBENCH_SOURCE, 'utf8');
    const quickTransferSource = fs.readFileSync(
        path.join(WEB_ROOT, 'modules', 'inventory-workbench-quick-transfer.js'), 'utf8');
    const storageWorkbenchSource = fs.readFileSync(
        path.join(WEB_ROOT, 'modules', 'inventory-storage-workbench.js'), 'utf8');
    const inventoryWorkbenchHeaderSource = fs.readFileSync(
        path.join(WEB_ROOT, 'modules', 'inventory-workbench-header.js'), 'utf8');
    const craftingOrganizerSource = fs.readFileSync(
        path.join(WEB_ROOT, 'modules', 'crafting-inventory-organizer.js'), 'utf8');
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
    if (!kshopViewsSource.includes('new this._components.SecondaryPage({')
            || !kshopViewsSource.includes("role:'dialog'")
            || !kshopViewsSource.includes('this._lineRecords = {}')
            || !kshopViewsSource.includes("name.className = 'kshop-settlement-inspect'")
            || !kshopViewsSource.includes('sliderMax:authorityMaximum')
            || !workbenchComponentsSource.includes("event.key === 'PageUp'")
            || !workbenchComponentsSource.includes("this.numberInput.setAttribute('aria-invalid'")) {
        throw new Error('KShop settlement must use stable shared secondary-page and adaptive quantity semantics');
    }
    if (!['function SecondaryPage(', 'function ChoiceGroup(', 'function CommitBar(', 'function OwnedInventoryPane(']
            .every(token => workbenchComponentsSource.includes(token))
            || !workbenchComponentsSource.includes('function HelpAction(')
            || !workbenchComponentsSource.includes("require('./workbench-lifecycle.js')")
            || workbenchComponentsSource.includes('this._disposers')
            || !kshopUiSource.includes('new WorkbenchComponents.ChoiceGroup(')
            || !kshopUiSource.includes('new WorkbenchComponents.OwnedInventoryPane(')
            || !npcshopUiSource.includes('.SecondaryPage(')
            || !npcshopUiSource.includes('.CommitBar(')
            || !inventoryWorkbenchUiSource.includes('.OwnedInventoryPane(')) {
        throw new Error('Shared workbench component composition boundary is incomplete');
    }
    if (!kshopSource.includes('new WorkbenchComponents.HelpAction(')
            || !kshopSource.includes("kind:'kshop-help'")
            || !inventoryWorkbenchSource.includes('components:WorkbenchComponents')
            || !inventoryWorkbenchUiSource.includes('new options.components.HelpAction(')
            || !inventoryWorkbenchUiSource.includes("kind:'inventory-storage-help'")) {
        throw new Error('KShop and battlebox must use the standard workbench help capability');
    }
    const retiredQuantityTokens = ['kshop-qty-popup', 'showQuantityInput', 'kshop-qty-btn'];
    const retiredQuantityHits = retiredQuantityTokens.filter(token => kshopUiSource.includes(token));
    if (retiredQuantityHits.length || !kshopUiSource.includes('kshop-cart-remove-btn')
            || !kshopViewsSource.includes("name.className = 'kshop-settlement-inspect'")) {
        throw new Error('KShop quantity editing must exist only on settlement: '
            + retiredQuantityHits.join(', '));
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
            || !npcshopUiSource.includes('new inventoryUI.OwnedInventoryViewShell(')
            || !inventoryWorkbenchUiSource.includes('.OwnedInventoryViewShell(')
            || ownedCompositions.some(text => text.includes('new Workbench.ItemGrid('))) {
        throw new Error('Owned inventory composition bypasses OwnedInventoryViewShell');
    }
    if (inventoryWorkbenchUiSource.includes("requestShop(")
            || inventoryWorkbenchUiSource.includes("'bulkQuery'")
            || inventoryWorkbenchUiSource.includes('shopPanelOpen')) {
        throw new Error('Standalone inventory workbench leaked into shop lifecycle');
    }
    if (!quickTransferSource.includes('function createCommandBar(')
            || !quickTransferSource.includes("root.className = 'inventory-quick-transfer-bar'")
            || !storageWorkbenchSource.includes('InventoryWorkbenchQuickTransfer.createCommandBar({')
            || !storageWorkbenchSource.includes('body.appendChild(_quickBarView.root)')
            || inventoryWorkbenchSource.includes('inventory-quick-transfer-bar')) {
        throw new Error('Battlebox batch transfer must live in the body command bar, outside global header composition');
    }
    const workbenchRequestCloseStart = inventoryWorkbenchSource.indexOf('function requestClose(');
    const workbenchRequestCloseEnd = inventoryWorkbenchSource.indexOf('function teardown(', workbenchRequestCloseStart);
    const workbenchRequestCloseBody = inventoryWorkbenchSource.slice(
        workbenchRequestCloseStart, workbenchRequestCloseEnd);
    if (workbenchRequestCloseStart < 0 || workbenchRequestCloseEnd < 0
            || workbenchRequestCloseBody.includes('openReturnTarget(')
            || /reason\s*!==\s*['"]header['"]/.test(workbenchRequestCloseBody)) {
        throw new Error('Inventory workbench implicit close must not navigate to crafting returnTarget');
    }
    if (!craftingOrganizerSource.includes(
            "var message = {type:'panel', cmd:'close', panel:'crafting',")
            || !craftingOrganizerSource.includes('panelInstanceId:_owner.panelInstanceId')
            || !craftingOrganizerSource.includes('accepted = Bridge.send(message) !== false')
            || !craftingOrganizerSource.includes('catch (_) { accepted = false; }')
            || !craftingOrganizerSource.includes("工作台保持打开")
            || !craftingOrganizerSource.includes("kind:'crafting-organizer'")) {
        throw new Error('Embedded crafting organizer must close its explicit Host owner and remain open on transport failure');
    }
    if (panelsSource.includes('function isNestedCraftingOrganizer(')
            || panelsSource.includes('_activeHostOwner')
            || !panelsSource.includes('sendPanelCloseNotification(')
            || !panelsSource.includes('sendExactCloseNotification(')
            || !panelsSource.includes('retryExactCloseNotification(')
            || !panelsSource.includes("sendMountFailureClose(id, initData, 'mount_failed')")
            || !panelsSource.includes('panel mount threw for ')
            || !panelsSource.includes('panel rebind threw for ')
            || !panelsSource.includes('var activeOrdinary = !!_active && !hostOwnsPanelMount(_active)')
            || !panelsSource.includes('if (!pendingExact && !activeExact) return;')) {
        throw new Error('Panels must keep exact standalone failure handling without a crafting/workbench alias');
    }
    if (inventoryWorkbenchSource.includes('function returnToPanel(')
            || inventoryWorkbenchSource.includes('openReturnTarget(')
            || inventoryWorkbenchSource.includes('onReturnPanel')
            || inventoryWorkbenchHeaderSource.includes("'return-panel'")
            || inventoryWorkbenchHeaderSource.includes('options.returnTarget')
            || inventoryWorkbenchHeaderSource.includes('options.onReturnPanel')
            || !craftingOrganizerSource.includes('function requestReturn()')
            || !craftingOrganizerSource.includes("button('返回合成'")
            || !craftingOrganizerSource.includes('inventory-return-crafting-btn')
            || !craftingOrganizerSource.includes('owner.onReturn()')
            || craftingOrganizerSource.includes("Panels.open('workbench'")) {
        throw new Error('Embedded crafting organizer requires the explicit local return path');
    }
    if (!kshopUiSource.includes('InventoryUI.renderOwnedSlot(')
            || !inventoryWorkbenchUiSource.includes('.renderOwnedSlot(')) {
        throw new Error('Owned-slot renderer is not shared by shop and standalone workbench');
    }
    if (!panelsSource.includes('ensureRequiredAssets(')
            || !panelsSource.includes('Icons.load(finishRequiredAssets)')
            || !panelsSource.includes('openAfterRequiredAssets(pending)')
            || !panelsSource.includes('ensureRequiredAssets(function() { openAfterRequiredAssets(pending); })')) {
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
    if (!kshopUiSource.includes('Workbench.ItemCard.renderCatalog')
            || !npcshopUiSource.includes('workbench.ItemCard.renderCatalog')) {
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
        explicitCraftingReturnOnly:true,
        sharedIconManifestGate:true,
        inspectionViewportLoadOrder:true,
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

function createServer(resourceLedger) {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(WEB_ROOT, pathname));
            const relative = path.relative(WEB_ROOT, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) {
                response.writeHead(403); response.end(); return;
            }
            const resourceOccurrence = resourceLedger.begin(request.url, file);
            fs.readFile(file, (error, data) => {
                if (error) {
                    resourceOccurrence.failure('read_failed');
                    response.writeHead(404); response.end(); return;
                }
                const extension = path.extname(file);
                const mime = extension === '.html' ? 'text/html; charset=utf-8'
                    : extension === '.css' ? 'text/css; charset=utf-8'
                    : extension === '.js' ? 'text/javascript; charset=utf-8'
                    : 'application/octet-stream';
                resourceOccurrence.success(data, mime);
                response.writeHead(200, {'Content-Type': mime});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

function closeServer(server) {
    return new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}

async function runPhysicalTooltipPointerProbe(page) {
    const keyboardStart = page.locator('#tooltip-physical-keyboard-start');
    const owner = page.locator('#tooltip-physical-hover-probe');
    const ownerB = page.locator('#tooltip-physical-hover-probe-b');
    const legacyOwner = page.locator('#tooltip-legacy-hover-probe');
    const blank = page.locator('#tooltip-physical-blank-probe');
    const tooltip = page.locator('#panel-tooltip');
    const keyboardStartBox = await keyboardStart.boundingBox();
    const ownerBox = await owner.boundingBox();
    const ownerBBox = await ownerB.boundingBox();
    const legacyOwnerBox = await legacyOwner.boundingBox();
    const blankBox = await blank.boundingBox();
    if (!keyboardStartBox || !ownerBox || !ownerBBox || !legacyOwnerBox || !blankBox) {
        throw new Error('Physical tooltip pointer probes are missing');
    }
    const ownerPoint = {x:ownerBox.x + ownerBox.width / 2, y:ownerBox.y + ownerBox.height / 2};
    const ownerBPoint = {x:ownerBBox.x + ownerBBox.width / 2, y:ownerBBox.y + ownerBBox.height / 2};
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

    // 用户原始路径：真实鼠标 click 会让 DOM 保留 focus，但不能把它登记成 keyboard owner。
    await page.mouse.move(ownerPoint.x, ownerPoint.y);
    await page.mouse.down();
    await page.mouse.up();
    const pointerClickFocused = await page.evaluate(() =>
        document.activeElement === document.getElementById('tooltip-physical-hover-probe'));
    const pointerClickHasNoKeyboardOwner = await page.evaluate(() =>
        !PanelTooltip.debugState().keyboardOwnerActive);
    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.waitForTimeout(170);
    const pointerClickBlankHidden = await page.evaluate(() => !PanelTooltip.isVisible());
    const hiddenOwnerEscapePassedThrough = await page.evaluate(() => {
        const ownerNode = document.getElementById('tooltip-physical-hover-probe');
        let passed = false;
        ownerNode.addEventListener('keydown', event => {
            passed = !event.defaultPrevented;
            event.stopImmediatePropagation();
        }, {once:true});
        ownerNode.dispatchEvent(new KeyboardEvent('keydown', {
            key:'Escape', bubbles:true, cancelable:true
        }));
        return passed && !PanelTooltip.isVisible();
    });
    await page.mouse.move(ownerPoint.x, ownerPoint.y);
    await page.mouse.down();
    await page.mouse.up();
    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(170);
    const keyboardIntentDuringLeaveGraceAnchored = await page.evaluate(() => {
        const ownerNode = document.getElementById('tooltip-physical-hover-probe');
        const tip = document.getElementById('panel-tooltip');
        const state = PanelTooltip.debugState();
        return document.activeElement === ownerNode && state.keyboardOwnerActive
            && !state.pointerOwnerActive && PanelTooltip.isVisible()
            && tip.textContent.indexOf('tooltip A') >= 0
            && ownerNode.getAttribute('aria-describedby') === 'panel-tooltip';
    });
    await keyboardStart.focus();

    // click A 留下的 DOM focus 不是恢复目标；hover B 后落空白也不能把 A 复活。
    await page.mouse.move(ownerPoint.x, ownerPoint.y);
    await page.mouse.down();
    await page.mouse.up();
    await page.mouse.move(ownerBPoint.x, ownerBPoint.y);
    await page.waitForFunction(() => {
        const tip = document.getElementById('panel-tooltip');
        return PanelTooltip.isVisible() && tip && tip.textContent.indexOf('tooltip B') >= 0;
    }, null, {timeout:1000});
    const pointerOtherOwnerTookControl = true;
    await page.waitForTimeout(170);
    const stalePreviousTimerIgnored = await page.evaluate(() => {
        const tip = document.getElementById('panel-tooltip');
        return PanelTooltip.isVisible() && tip && tip.textContent.indexOf('tooltip B') >= 0
            && PanelTooltip.debugState().pointerOwnerActive;
    });
    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.waitForTimeout(170);
    const pointerClickOtherBlankHidden = await page.evaluate(() => !PanelTooltip.isVisible());

    // 真实 Tab 才建立 keyboard owner。pointer B 临时覆盖时撤下 A 的 ARIA 关联，
    // B 离开后只恢复仍与 activeElement 一致的 A。
    await keyboardStart.focus();
    await page.keyboard.press('Tab');
    await page.waitForFunction(() => {
        const ownerNode = document.getElementById('tooltip-physical-hover-probe');
        const tip = document.getElementById('panel-tooltip');
        return document.activeElement === ownerNode && PanelTooltip.isVisible()
            && tip && tip.textContent.indexOf('tooltip A') >= 0;
    }, null, {timeout:1000});
    const keyboardOwnerAcquired = await page.evaluate(() => {
        const ownerNode = document.getElementById('tooltip-physical-hover-probe');
        const state = PanelTooltip.debugState();
        return document.activeElement === ownerNode && state.keyboardOwnerActive
            && ownerNode.getAttribute('aria-describedby') === 'panel-tooltip';
    });
    await page.mouse.move(ownerBPoint.x, ownerBPoint.y);
    await page.waitForFunction(() => {
        const tip = document.getElementById('panel-tooltip');
        return tip && tip.textContent.indexOf('tooltip B') >= 0;
    }, null, {timeout:1000});
    const keyboardDescriptionSuspended = await page.evaluate(() =>
        !document.getElementById('tooltip-physical-hover-probe').hasAttribute('aria-describedby'));
    const dualOwnerBounded = await page.evaluate(() => {
        const state = PanelTooltip.debugState();
        return state.activeBindingCount === 2 && state.pointerOwnerActive && state.keyboardOwnerActive;
    });
    const coveredKeyboardEscapePassedThrough = await page.evaluate(() => {
        const ownerNode = document.getElementById('tooltip-physical-hover-probe');
        const tip = document.getElementById('panel-tooltip');
        let passed = false;
        ownerNode.addEventListener('keydown', event => {
            passed = !event.defaultPrevented;
            event.stopImmediatePropagation();
        }, {once:true});
        ownerNode.dispatchEvent(new KeyboardEvent('keydown', {
            key:'Escape', bubbles:true, cancelable:true
        }));
        const state = PanelTooltip.debugState();
        return passed && state.pointerOwnerActive && state.keyboardOwnerActive
            && PanelTooltip.isVisible() && tip.textContent.indexOf('tooltip B') >= 0;
    });
    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.waitForTimeout(170);
    const keyboardOwnerRestored = await page.evaluate(() => {
        const ownerNode = document.getElementById('tooltip-physical-hover-probe');
        const tip = document.getElementById('panel-tooltip');
        return document.activeElement === ownerNode && PanelTooltip.isVisible()
            && tip && tip.textContent.indexOf('tooltip A') >= 0
            && ownerNode.getAttribute('aria-describedby') === 'panel-tooltip';
    });

    // 点击一个已经由键盘聚焦的节点不会再次派发 focusin；pointerdown 必须显式撤权。
    await page.mouse.move(ownerPoint.x, ownerPoint.y);
    await page.mouse.down();
    await page.mouse.up();
    const pointerReclickRevokedKeyboard = await page.evaluate(() =>
        !PanelTooltip.debugState().keyboardOwnerActive
        && !document.getElementById('tooltip-physical-hover-probe').hasAttribute('aria-describedby'));
    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.waitForTimeout(170);
    const pointerReclickBlankHidden = await page.evaluate(() => !PanelTooltip.isVisible());

    // Escape 撤销 owner 而不只关闭视觉层；随后 hover B 的离开不能复活仍聚焦的 A。
    await keyboardStart.focus();
    await page.keyboard.press('Tab');
    await page.waitForFunction(() => PanelTooltip.isVisible(), null, {timeout:1000});
    await page.keyboard.press('Escape');
    const escapeReleasedOwners = await page.evaluate(() => {
        const state = PanelTooltip.debugState();
        return !PanelTooltip.isVisible() && !state.pointerOwnerActive && !state.keyboardOwnerActive;
    });
    await page.mouse.move(ownerBPoint.x, ownerBPoint.y);
    await page.waitForFunction(() => PanelTooltip.isVisible(), null, {timeout:1000});
    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.waitForTimeout(170);
    const escapeOwnerNotRestored = await page.evaluate(() => !PanelTooltip.isVisible());

    // pointercancel 是确定性终态，不经过 tooltip surface 的 140ms bridge。
    const pointerCancelHidden = await page.evaluate(() => {
        if (!window.PointerEvent) return true;
        const probe = document.getElementById('tooltip-physical-hover-probe-b');
        const rect = probe.getBoundingClientRect();
        const init = {
            bubbles:false, clientX:rect.left + rect.width / 2, clientY:rect.top + rect.height / 2,
            pointerId:91, pointerType:'pen', isPrimary:true
        };
        probe.dispatchEvent(new PointerEvent('pointerenter', init));
        probe.dispatchEvent(new PointerEvent('pointercancel', init));
        return !PanelTooltip.isVisible() && !PanelTooltip.debugState().pointerOwnerActive;
    });
    await keyboardStart.focus();
    await page.keyboard.press('Tab');
    await page.waitForFunction(() => PanelTooltip.isVisible(), null, {timeout:1000});
    const pointerCancelRestoredKeyboard = await page.evaluate(() => {
        if (!window.PointerEvent) return true;
        const probe = document.getElementById('tooltip-physical-hover-probe-b');
        const keyboardOwner = document.getElementById('tooltip-physical-hover-probe');
        const tip = document.getElementById('panel-tooltip');
        const rect = probe.getBoundingClientRect();
        const init = {
            bubbles:false, clientX:rect.left + rect.width / 2, clientY:rect.top + rect.height / 2,
            pointerId:92, pointerType:'pen', isPrimary:true
        };
        probe.dispatchEvent(new PointerEvent('pointerenter', init));
        probe.dispatchEvent(new PointerEvent('pointercancel', init));
        const state = PanelTooltip.debugState();
        return state.keyboardOwnerActive && !state.pointerOwnerActive && PanelTooltip.isVisible()
            && tip.textContent.indexOf('tooltip A') >= 0
            && keyboardOwner.getAttribute('aria-describedby') === 'panel-tooltip';
    });

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

    // 最后直接打开真实 KShop 目录锁住用户反馈，而不是只用合成按钮证明共享层。
    await page.evaluate(() => window.KShopHarnessHost.open());
    const catalogCards = page.locator('.kshop-card:not(.kshop-card-locked)');
    await catalogCards.first().waitFor({state:'visible', timeout:1000});
    const catalogA = catalogCards.nth(0);
    const catalogB = catalogCards.nth(1);
    const catalogABox = await catalogA.boundingBox();
    const catalogBBox = await catalogB.boundingBox();
    if (!catalogABox || !catalogBBox) throw new Error('KShop catalog tooltip probes are missing');
    const catalogAPoint = {x:catalogABox.x + 18, y:catalogABox.y + 18};
    const catalogBPoint = {x:catalogBBox.x + 18, y:catalogBBox.y + 18};
    await page.mouse.move(catalogAPoint.x, catalogAPoint.y);
    await page.waitForFunction(() => PanelTooltip.isVisible(), null, {timeout:1000});
    await page.mouse.down();
    await page.mouse.up();
    const catalogClickFocused = await page.evaluate(() => {
        const card = document.querySelector('.kshop-card:not(.kshop-card-locked)');
        return !!(card && (document.activeElement === card || card.contains(document.activeElement)));
    });
    const catalogClickHasNoKeyboardOwner = await page.evaluate(() =>
        !PanelTooltip.debugState().keyboardOwnerActive);
    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.waitForTimeout(170);
    const catalogClickBlankHidden = await page.evaluate(() => !PanelTooltip.isVisible());

    await page.mouse.move(catalogAPoint.x, catalogAPoint.y);
    await page.mouse.down();
    await page.mouse.up();
    await page.mouse.move(catalogBPoint.x, catalogBPoint.y);
    await page.waitForFunction(() => PanelTooltip.isVisible(), null, {timeout:1000});
    await page.mouse.move(blankPoint.x, blankPoint.y);
    await page.waitForTimeout(170);
    const catalogClickOtherBlankHidden = await page.evaluate(() => !PanelTooltip.isVisible());

    return {
        visibleOnOwner,
        hoverBridgePersistent,
        hoverSurfaceExitHidden,
        blankLandingWasOutside,
        rapidBlankLandingHidden,
        geometryCoveredBlank,
        lateGeometryEnterIgnored,
        pointerClickFocused,
        pointerClickHasNoKeyboardOwner,
        pointerClickBlankHidden,
        hiddenOwnerEscapePassedThrough,
        keyboardIntentDuringLeaveGraceAnchored,
        pointerOtherOwnerTookControl,
        stalePreviousTimerIgnored,
        pointerClickOtherBlankHidden,
        keyboardOwnerAcquired,
        keyboardDescriptionSuspended,
        dualOwnerBounded,
        coveredKeyboardEscapePassedThrough,
        keyboardOwnerRestored,
        pointerReclickRevokedKeyboard,
        pointerReclickBlankHidden,
        escapeReleasedOwners,
        escapeOwnerNotRestored,
        pointerCancelHidden,
        pointerCancelRestoredKeyboard,
        legacyVisibleOnOwner,
        legacyHoverBridgePersistent,
        legacyHoverSurfaceExitHidden,
        catalogClickFocused,
        catalogClickHasNoKeyboardOwner,
        catalogClickBlankHidden,
        catalogClickOtherBlankHidden
    };
}

function tooltipRegressionFailed(state) {
    const required = [
        'visible', 'basicStyled', 'hasRichLayout', 'hasIcon',
        'keyboardFocusDescription', 'keyboardFocusFallbackVisible', 'focusExitHidden',
        'asyncFocusVisible', 'lateResponseStayedHidden', 'teardownStayedHidden',
        'teardownIdempotent', 'anchoredRichRepositioned', 'anchoredRichInsideViewport',
        'anchoredScaleGapStable', 'focusOwnerInitiallyVisible', 'hoverOwnerTookControl',
        'keyboardDescriptionSuspendedDuringPointer', 'focusedOwnerRestored',
        'restoredOwnerExitHidden', 'hoverSurfacePersistent', 'wheelScrollsLongDescription',
        'forcedHideResetsHoverState', 'forcedHideReleasedOwners',
        'penPointerHoverPersistent', 'lateGeometryEnterIgnored',
        'keyboardScrollsLongDescription', 'escapeDismissesTooltip', 'escapeReleasedOwners',
        'detachedOwnerNotRestored', 'scopeCleanupComplete'
    ];
    const physicalRequired = [
        'visibleOnOwner', 'hoverBridgePersistent', 'hoverSurfaceExitHidden',
        'blankLandingWasOutside', 'rapidBlankLandingHidden', 'geometryCoveredBlank',
        'lateGeometryEnterIgnored', 'pointerClickFocused', 'pointerClickHasNoKeyboardOwner',
        'pointerClickBlankHidden', 'hiddenOwnerEscapePassedThrough',
        'keyboardIntentDuringLeaveGraceAnchored',
        'pointerOtherOwnerTookControl', 'stalePreviousTimerIgnored',
        'pointerClickOtherBlankHidden',
        'keyboardOwnerAcquired', 'keyboardDescriptionSuspended', 'dualOwnerBounded',
        'coveredKeyboardEscapePassedThrough',
        'keyboardOwnerRestored',
        'pointerReclickRevokedKeyboard', 'pointerReclickBlankHidden', 'pointerCancelHidden',
        'pointerCancelRestoredKeyboard',
        'escapeReleasedOwners', 'escapeOwnerNotRestored',
        'legacyVisibleOnOwner', 'legacyHoverBridgePersistent', 'legacyHoverSurfaceExitHidden',
        'catalogClickFocused', 'catalogClickHasNoKeyboardOwner', 'catalogClickBlankHidden',
        'catalogClickOtherBlankHidden'
    ];
    return !state
        || required.some(key => !state[key])
        || !state.physicalPointer
        || physicalRequired.some(key => !state.physicalPointer[key])
        || !state.placement
        || state.placement.pointerOverlap > 0
        || state.placement.anchorOverlap > 0;
}

async function snapshotSecondaryPage(page, selector) {
    return page.$eval(selector, node => {
        const style = getComputedStyle(node);
        return {
            display:style.display,
            zIndex:style.zIndex,
            visibility:style.visibility,
            opacity:Number(style.opacity),
            pointerEvents:style.pointerEvents,
            transform:style.transform,
            transitionDuration:style.transitionDuration,
            ariaHidden:node.getAttribute('aria-hidden'),
            animationCount:typeof node.getAnimations === 'function'
                ? node.getAnimations().length : 0
        };
    });
}

function isReducedSecondaryTerminal(state, active) {
    return state.display === 'grid'
        && state.zIndex === '55'
        && state.transitionDuration === '0s'
        && state.animationCount === 0
        && state.transform === 'none'
        && (active
            ? state.visibility === 'visible' && state.opacity === 1
                && state.pointerEvents === 'auto' && state.ariaHidden === 'false'
            : state.visibility === 'hidden' && state.opacity === 0
                && state.pointerEvents === 'none' && state.ariaHidden === 'true');
}

async function probeSemanticBusyMotion(page) {
    async function snapshot() {
        return page.evaluate(() => {
            let fixture = document.getElementById('kshop-g3-motion-fixture');
            if (!fixture) {
                fixture = document.createElement('div');
                fixture.id = 'kshop-g3-motion-fixture';
                fixture.className = 'workbench-shell kshop-workbench';
                fixture.setAttribute('data-profile', 'catalog-checkout');
                fixture.setAttribute('data-workbench-skin', 'shop');
                fixture.style.cssText = 'position:fixed;left:0;top:0;width:360px;height:160px;z-index:9999';
                fixture.innerHTML = '<div class="workbench-status" data-state="busy">处理中</div>'
                    + '<div class="inventory-slot-card quick-transfer-inflight">转移中</div>'
                    + '<div class="kshop-loading">读取中</div>';
                document.body.appendChild(fixture);
            }
            const panel = document.getElementById('panel-container');
            const tooltip = document.getElementById('panel-tooltip');
            if (!window.__kshopG4TooltipRestore) {
                window.__kshopG4TooltipRestore = {
                    panelKind:panel ? panel.getAttribute('data-panel') : null,
                    display:tooltip ? tooltip.style.display : ''
                };
            }
            if (panel) panel.setAttribute('data-panel', 'kshop');
            let tooltipLoading = document.getElementById('kshop-g4-tooltip-motion-probe');
            if (!tooltipLoading && tooltip) {
                tooltipLoading = document.createElement('div');
                tooltipLoading.id = 'kshop-g4-tooltip-motion-probe';
                tooltipLoading.className = 'kshop-tt-loading';
                tooltipLoading.textContent = '读取说明中';
                tooltip.appendChild(tooltipLoading);
                tooltip.style.display = 'block';
            }
            function animationNode(node, pseudo) {
                const style = getComputedStyle(node, pseudo || null);
                const rect = node.getBoundingClientRect();
                return {
                    animationName:style.animationName,
                    animationDuration:style.animationDuration,
                    animationTimingFunction:style.animationTimingFunction,
                    animationIterationCount:style.animationIterationCount,
                    content:pseudo ? style.content : node.textContent,
                    display:style.display,
                    opacity:Number(style.opacity),
                    width:rect.width,
                    height:rect.height
                };
            }
            return {
                status:animationNode(fixture.querySelector('.workbench-status'), '::before'),
                transfer:animationNode(fixture.querySelector('.quick-transfer-inflight'), '::before'),
                loading:animationNode(fixture.querySelector('.kshop-loading')),
                tooltip:animationNode(tooltipLoading)
            };
        });
    }
    function visible(state) {
        return state.display !== 'none'
            && state.width > 0 && state.height > 0
            && state.opacity > 0
            && state.content !== 'none' && state.content !== 'normal'
            && state.content !== '';
    }
    function normalState(state) {
        return visible(state)
            && state.animationName === 'wb-pulse-busy'
            && state.animationDuration === '1s'
            && state.animationTimingFunction === 'cubic-bezier(0.2, 0.8, 0.25, 1)'
            && state.animationIterationCount === 'infinite';
    }
    function reducedState(state) {
        return visible(state)
            && state.animationName === 'none'
            && state.animationDuration === '0s';
    }

    await page.emulateMedia({reducedMotion:'no-preference'});
    const normal = await snapshot();
    await page.emulateMedia({reducedMotion:'reduce'});
    const reduced = await snapshot();
    const outOfScopeTooltip = await page.evaluate(() => {
        const panel = document.getElementById('panel-container');
        const node = document.getElementById('kshop-g4-tooltip-motion-probe');
        if (panel) panel.setAttribute('data-panel', 'tasks');
        const style = getComputedStyle(node);
        return {
            animationName:style.animationName,
            animationDuration:style.animationDuration,
            animationTimingFunction:style.animationTimingFunction,
            animationIterationCount:style.animationIterationCount,
            content:node.textContent,
            display:style.display,
            opacity:Number(style.opacity),
            width:node.getBoundingClientRect().width,
            height:node.getBoundingClientRect().height,
            outsideShell:!node.closest('.workbench-shell')
        };
    });
    await page.evaluate(() => {
        const fixture = document.getElementById('kshop-g3-motion-fixture');
        if (fixture) fixture.remove();
        const tooltipProbe = document.getElementById('kshop-g4-tooltip-motion-probe');
        if (tooltipProbe) tooltipProbe.remove();
        const restore = window.__kshopG4TooltipRestore;
        const panel = document.getElementById('panel-container');
        const tooltip = document.getElementById('panel-tooltip');
        if (panel && restore) {
            if (restore.panelKind == null) panel.removeAttribute('data-panel');
            else panel.setAttribute('data-panel', restore.panelKind);
        }
        if (tooltip && restore) tooltip.style.display = restore.display;
        delete window.__kshopG4TooltipRestore;
    });
    await page.emulateMedia({reducedMotion:'no-preference'});
    return {
        normal,
        reduced,
        outOfScopeTooltip,
        pass:Object.keys(normal).every(key => normalState(normal[key]))
            && Object.keys(reduced).every(key => reducedState(reduced[key]))
            && outOfScopeTooltip.outsideShell
            && normalState(outOfScopeTooltip)
    };
}

async function probeEquipmentInspectorMotion(page) {
    async function snapshot(reducedMotion) {
        await page.emulateMedia({reducedMotion});
        return page.evaluate(async () => {
            const shell = new Workbench.DualPaneShell({
                profile:'catalog-decision',
                title:'G4 inspector motion fixture',
                leftLabel:'SOURCE',
                rightLabel:'TARGET'
            });
            const shellRoot = shell.getRoot();
            shellRoot.style.cssText = 'position:fixed;left:0;top:0;width:720px;height:520px;z-index:9998';
            document.body.appendChild(shellRoot);
            const controller = EquipmentInspector.open({
                shell,
                item:{
                    name:'图标-测试药剂',
                    displayName:'G4 静态检视',
                    majorType:'消耗品',
                    icon:'图标-测试药剂'
                },
                context:'g4-motion-probe'
            });
            const stage = shellRoot.querySelector('.equipment-inspector-stage');
            stage.style.transform = 'translate3d(0px,0px,0) scale(1)';
            stage.getBoundingClientRect();
            stage.style.transform = 'translate3d(12px,0px,0) scale(1)';
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            const style = getComputedStyle(stage);
            const state = controller.debugState();
            const result = {
                reduced:matchMedia('(prefers-reduced-motion: reduce)').matches,
                animationEnabled:state.animationEnabled,
                source:state.source,
                transitionProperty:style.transitionProperty,
                transitionDuration:style.transitionDuration,
                transitionCount:typeof stage.getAnimations === 'function'
                    ? stage.getAnimations().length : 0,
                stageInShell:stage.closest('.workbench-shell') === shellRoot,
                modalInShell:!!shellRoot.querySelector(
                    '.workbench-modal[data-modal-kind="equipment-inspector"]')
            };
            controller.destroy();
            shell.destroy();
            return result;
        });
    }
    const normal = await snapshot('no-preference');
    const reduced = await snapshot('reduce');
    await page.emulateMedia({reducedMotion:'no-preference'});
    return {
        normal,
        reduced,
        pass:normal.reduced === false
            && normal.animationEnabled === true
            && normal.source === 'icon'
            && normal.transitionProperty === 'transform'
            && parseFloat(normal.transitionDuration) > 0
            && normal.transitionCount > 0
            && normal.stageInShell && normal.modalInShell
            && reduced.reduced === true
            && reduced.animationEnabled === false
            && reduced.transitionDuration === '0s'
            && reduced.transitionCount === 0
            && reduced.stageInShell && reduced.modalInShell
    };
}

async function probeReducedSecondaryPage(page, origin) {
    await page.emulateMedia({reducedMotion:'reduce'});
    await page.goto(origin + '/modules/kshop/dev/harness.html?visual=settlement', {waitUntil:'load'});
    await page.waitForFunction(() => window.__visualReady === true, null, {timeout:5000});
    const active = await snapshotSecondaryPage(page, '.kshop-settlement-page');
    await page.$eval('[data-kshop-settlement-back]', node => node.click());
    const inactive = await snapshotSecondaryPage(page, '.kshop-settlement-page');
    await page.emulateMedia({reducedMotion:'no-preference'});
    return {
        active,
        inactive,
        pass:isReducedSecondaryTerminal(active, true)
            && isReducedSecondaryTerminal(inactive, false)
    };
}

async function probeOwnedInventoryScrollbar(page, origin, viewport) {
    await page.setViewportSize({width:1024,height:576});
    await page.goto(origin + '/modules/kshop/dev/harness.html?visual=battlebox-owned-overflow', {waitUntil:'load'});
    await page.waitForFunction(() => window.__visualReady === true, null, {timeout:20000});
    const result = await page.$eval('.inventory-owned-backpack .inventory-owned-grid', grid => {
        const style = getComputedStyle(grid);
        const bar = getComputedStyle(grid, '::-webkit-scrollbar');
        const track = getComputedStyle(grid, '::-webkit-scrollbar-track');
        const thumb = getComputedStyle(grid, '::-webkit-scrollbar-thumb');
        const button = getComputedStyle(grid, '::-webkit-scrollbar-button');
        const corner = getComputedStyle(grid, '::-webkit-scrollbar-corner');
        grid.scrollTop = Math.min(60, grid.scrollHeight - grid.clientHeight);
        return {
            overflow:grid.scrollHeight > grid.clientHeight,
            horizontalOverflow:grid.scrollWidth > grid.clientWidth + 1,
            scrollTop:grid.scrollTop,
            standardWidth:style.scrollbarWidth,
            width:bar.width,
            track:track.backgroundColor,
            thumb:thumb.backgroundColor,
            thumbBorder:thumb.borderTopWidth,
            buttonDisplay:button.display,
            buttonWidth:button.width,
            corner:corner.backgroundColor
        };
    });
    await page.setViewportSize(viewport);
    result.pass = result.overflow && !result.horizontalOverflow && result.scrollTop > 0
        && result.standardWidth === 'thin'
        && parseFloat(result.width) > 0 && parseFloat(result.width) <= 8
        && result.track !== 'rgba(0, 0, 0, 0)'
        && result.thumb !== 'rgba(0, 0, 0, 0)'
        && parseFloat(result.thumbBorder) >= 1
        && (result.buttonDisplay === 'none' || parseFloat(result.buttonWidth) === 0)
        && result.corner !== 'rgba(0, 0, 0, 0)';
    return result;
}

async function run() {
    const architectureAudit = identityOnly ? {identityOnly:true} : auditArchitectureBoundaries();
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgePath();
    if (!executablePath) throw new Error('Microsoft Edge executable not found');
    const { chromium } = require(PLAYWRIGHT);
    const resourceLedger = BrowserChildResourceClosure.createServedResourceLedger({root:WEB_ROOT});
    const server = await createServer(resourceLedger);
    const browser = await chromium.launch({executablePath, headless:true});
    const page = await browser.newPage({viewport:parseViewport()});
    const pageErrors = [];
    const failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message || String(error)));
    page.on('requestfailed', request => failedRequests.push(request.url()));
    const visualMode = visualArg ? visualArg.slice('--visual='.length) : '';
    const batchVisualMatch = /^battlebox-batch(?:-(0|1|5|50))?$/.exec(visualMode);
    const expectedBatchCount = batchVisualMatch ? Number(batchVisualMatch[1] || 5) : null;
    const targetQuery = identityOnly ? '?identity=1'
        : visualMode ? '?visual=' + encodeURIComponent(visualMode) : '?qa=1';
    await page.goto('http://127.0.0.1:' + server.address().port + '/modules/kshop/dev/harness.html' + targetQuery, {waitUntil:'load'});
    if (visualMode) {
        await page.waitForFunction(() => window.__visualReady === true
            || window.__qaResult && window.__qaResult.qa && window.__qaResult.qa.failed > 0, null, {timeout:20000});
        const visualFatal = await page.evaluate(() => {
            if (window.__visualReady === true || !window.__qaResult || !window.__qaResult.qa) return null;
            const failed = (window.__qaResult.qa.results || []).find(item => item && item.pass === false);
            return failed ? failed.detail || failed.title || 'visual scenario failed' : 'visual scenario failed';
        });
        if (visualFatal) throw new Error(visualFatal);
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
                const rectOf=node => { const r=node.getBoundingClientRect(); return {
                    x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom
                }; };
                const visibleChildren=Array.from(actions.children).filter(node=>getComputedStyle(node).display!=='none');
                const headerRect=header.getBoundingClientRect();
                return {
                    header:rectOf(header), actions:rectOf(actions),
                    overflow:actions.scrollWidth>actions.clientWidth || actions.getBoundingClientRect().right>innerWidth+1,
                    verticalOverflow:actions.scrollHeight>actions.clientHeight+1
                        || visibleChildren.some(node=>{
                            const rect=node.getBoundingClientRect();
                            return rect.top<headerRect.top-1 || rect.bottom>headerRect.bottom+1
                                || node.scrollHeight>node.clientHeight+1 || node.scrollWidth>node.clientWidth+1;
                        }),
                    children:Array.from(actions.children).map(node=>({
                        text:(node.textContent||'').replace(/\s+/g,' ').trim(),
                        display:getComputedStyle(node).display,
                        clientWidth:node.clientWidth,scrollWidth:node.scrollWidth,
                        clientHeight:node.clientHeight,scrollHeight:node.scrollHeight,
                        rect:rectOf(node)
                    }))
                };
            })(),
            batchLayout:(() => {
                const bar=document.querySelector('.inventory-quick-transfer-bar');
                const body=document.querySelector('.inventory-workbench-panel .workbench-body');
                if(!bar || !body) return null;
                const rect=bar.getBoundingClientRect(),bodyRect=body.getBoundingClientRect();
                const visible=Array.from(bar.children).filter(node=>getComputedStyle(node).display!=='none'&&!node.hidden);
                let overlap=false;
                for(let i=0;i<visible.length;i++)for(let j=i+1;j<visible.length;j++){
                    const a=visible[i].getBoundingClientRect(),b=visible[j].getBoundingClientRect();
                    if(Math.min(a.right,b.right)-Math.max(a.left,b.left)>1
                        &&Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top)>1) overlap=true;
                }
                return {
                    mode:bar.getAttribute('data-mode')||'',
                    staged:Number(bar.getAttribute('data-staged')||0),
                    rect:{x:rect.x,y:rect.y,width:rect.width,height:rect.height,right:rect.right,bottom:rect.bottom},
                    insideBody:rect.left>=bodyRect.left-1&&rect.right<=bodyRect.right+1
                        &&rect.top>=bodyRect.top-1&&rect.bottom<=bodyRect.bottom+1,
                    overflow:bar.scrollWidth>bar.clientWidth+1||bar.scrollHeight>bar.clientHeight+1,
                    overlap,
                    children:visible.map(node=>({text:(node.textContent||'').replace(/\s+/g,' ').trim(),
                        rect:(()=>{const r=node.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height};})()}))
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
            scrollbar:window.__visualScrollbarState || null,
            bodyOverflow:document.body.scrollWidth > document.body.clientWidth || document.body.scrollHeight > document.body.clientHeight
        }), visualMode);
        const physicalTooltipPointer = visualMode === 'battlebox-real-icons'
            ? await runPhysicalTooltipPointerProbe(page) : null;
        if (visualState.tooltip) visualState.tooltip.physicalPointer = physicalTooltipPointer;
        await browser.close();
        await closeServer(server);
        const servedResourceLedger = resourceLedger.snapshot();
        const output = {browser:'edge',executablePath,visualMode,visualState,
            servedResourceLedger,pageErrors,failedRequests};
        const tooltipFailed = visualMode === 'battlebox-real-icons'
            && tooltipRegressionFailed(visualState.tooltip);
        const headerFailed = visualMode.indexOf('battlebox') === 0
            && (!visualState.headerLayout || visualState.headerLayout.overflow
                || visualState.headerLayout.verticalOverflow);
        const batchFailed = visualMode.indexOf('battlebox') === 0
            && (!visualState.batchLayout || !visualState.batchLayout.insideBody
                || visualState.batchLayout.overflow || visualState.batchLayout.overlap)
            || expectedBatchCount != null
                && (visualState.batchLayout.mode !== 'deposit'
                    || visualState.batchLayout.staged !== expectedBatchCount);
        const scrollbarFailed = visualMode === 'cart-overflow'
            && (!visualState.scrollbar || !visualState.scrollbar.overflow
                || !(parseFloat(visualState.scrollbar.width) > 0
                    && parseFloat(visualState.scrollbar.width) <= 8)
                || visualState.scrollbar.track === 'rgba(0, 0, 0, 0)'
                || visualState.scrollbar.thumb === 'rgba(0, 0, 0, 0)'
                || !(parseFloat(visualState.scrollbar.thumbBorder) >= 1)
                || !(visualState.scrollbar.buttonDisplay === 'none'
                    || parseFloat(visualState.scrollbar.buttonWidth) === 0));
        if (pageErrors.length || failedRequests.length || tooltipFailed
                || headerFailed || batchFailed || scrollbarFailed || visualState.bodyOverflow) {
            const error = new Error('KShop visual browser harness failed');
            error.exitCode = 1;
            error.result = output;
            throw error;
        }
        return output;
    }
    await page.waitForFunction(() => window.__qaResult && window.__qaResult.qa, null, {timeout:20000});
    const qa = await page.evaluate(() => window.__qaResult.qa);
    if (identityOnly) {
        await browser.close();
        await closeServer(server);
        const servedResourceLedger = resourceLedger.snapshot();
        const output = {browser:'edge',executablePath,
            mode:'identity-only',qa,servedResourceLedger,pageErrors,failedRequests};
        if (qa.total !== 7 || qa.passed !== 7 || qa.failed !== 0
                || pageErrors.length || failedRequests.length) {
            const error = new Error('KShop identity browser harness failed');
            error.exitCode = 1;
            error.result = output;
            throw error;
        }
        return output;
    }
    const origin = 'http://127.0.0.1:' + server.address().port;
    const semanticBusyMotion = await probeSemanticBusyMotion(page);
    const equipmentInspectorMotion = await probeEquipmentInspectorMotion(page);
    const reducedSecondaryMotion = await probeReducedSecondaryPage(page, origin);
    const ownedInventoryScrollbar = await probeOwnedInventoryScrollbar(page, origin, parseViewport());
    await page.goto('http://127.0.0.1:' + server.address().port + '/modules/kshop/dev/harness.html?visual=battlebox-real-icons', {waitUntil:'load'});
    await page.waitForFunction(() => window.__visualReady === true, null, {timeout:20000});
    const realTooltip = await page.evaluate(() => window.__visualTooltipState || null);
    if (realTooltip) realTooltip.physicalPointer = await runPhysicalTooltipPointerProbe(page);
    await browser.close();
    await closeServer(server);
    const servedResourceLedger = resourceLedger.snapshot();

    const output = {browser:'edge',executablePath,architectureAudit,qa,semanticBusyMotion,equipmentInspectorMotion,reducedSecondaryMotion,ownedInventoryScrollbar,
        realTooltip,servedResourceLedger,pageErrors,failedRequests};
    const tooltipFailed = tooltipRegressionFailed(realTooltip);
    if (qa.failed || !semanticBusyMotion.pass || !equipmentInspectorMotion.pass
            || !reducedSecondaryMotion.pass || !ownedInventoryScrollbar.pass || tooltipFailed
            || pageErrors.length || failedRequests.length) {
        const error = new Error('KShop browser harness failed');
        error.exitCode = 1;
        error.result = output;
        throw error;
    }
    return output;
}

module.exports = {run};
if (require.main === module) {
    run().then(output => {
        process.stdout.write(JSON.stringify(output, null, 2) + '\n');
    }).catch(error => {
        console.error(error && error.stack ? error.stack : String(error));
        if (error && error.result) console.error(JSON.stringify(error.result));
        process.exitCode = error && error.exitCode || 2;
    });
}
