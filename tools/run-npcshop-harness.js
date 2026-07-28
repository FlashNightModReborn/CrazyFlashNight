#!/usr/bin/env node
'use strict';
const fs=require('fs'),http=require('http'),path=require('path'),url=require('url');
const {readCssBundle}=require('./lib/read-css-bundle.js');
const ROOT=path.resolve(__dirname,'..'),WEB=path.join(ROOT,'launcher','web');
const PLAYWRIGHT=path.join(ROOT,'launcher','perf','node_modules','playwright');
const WORKBENCH_SOURCE=path.join(WEB,'modules','workbench.js');
const WORKBENCH_PRIMITIVES_SOURCE=path.join(WEB,'modules','workbench-primitives.js');
const INVENTORY_WORKBENCH_SOURCE=path.join(WEB,'modules','inventory-workbench.js');
const INVENTORY_UI_SOURCE=path.join(WEB,'modules','inventory-ui.js');
const KSHOP_SOURCE=path.join(WEB,'modules','kshop.js');
const ITEM_FILTER_SOURCE=path.join(WEB,'modules','item-filter.js');
const WORKBENCH_COMPONENTS_SOURCE=path.join(WEB,'modules','workbench-components.js');
const NPCSHOP_SECONDARY_SOURCE=path.join(WEB,'modules','npcshop-secondary-pages.js');
const PANEL_CONTRACT_SOURCE=path.join(ROOT,'launcher','contracts','panel-contracts.v2.json');
const KSHOP_MODULE_SOURCES=['kshop-cart-controller.js','kshop-catalog-presenter.js','kshop-owned-inventory-presenter.js','kshop-tooltip-presenter.js'];
const INVENTORY_WORKBENCH_MODULE_SOURCES=['inventory-workbench-config.js','inventory-workbench-header.js','inventory-workbench-quick-transfer.js','inventory-workbench-owned-view.js','inventory-tuning-scope.js','inventory-storage-workbench.js'];

function audit(){
  const panel=fs.readFileSync(path.join(WEB,'modules','npcshop.js'),'utf8');
  const secondary=fs.readFileSync(NPCSHOP_SECONDARY_SOURCE,'utf8');
  const panelUi=panel+'\n'+secondary;
  const runtime=fs.readFileSync(path.join(WEB,'modules','npcshop-runtime.js'),'utf8');
  const css=readCssBundle(path.join(WEB,'css','panels.css'),{rootDir:path.join(WEB,'css')});
  if(!['bag','material','intelligence'].every(v=>panel.includes("viewId:'"+v+"'")))throw new Error('right-view sibling contract missing');
  if(!panel.includes("domain:'inventory'") || !runtime.includes("options.domain || 'npcshop'"))throw new Error('npcshop/inventory domain mux missing');
  if(/unitPrice\s*\*|basePrice\s*\*/.test(panel))throw new Error('Web must not reproduce authoritative price formula');
  if(/type\s*=\s*['"]number['"]|type=['"]number['"]/.test(panel))throw new Error('NPC shop must not use native number inputs');
  if(!panel.includes("'tradePreview'")||!panel.includes("'tradeCommit'"))throw new Error('atomic settlement flow missing');
  if(!panelUi.includes('npcshop-settlement-page'))throw new Error('secondary settlement route missing');
  if(!panelUi.includes('npcshop-help-page')||!panel.includes('cf7.npcshop.guide.v1.'))throw new Error('intent-preserving help and one-time guide flow missing');
  const itemFilter=fs.readFileSync(ITEM_FILTER_SOURCE,'utf8');
  if(!panel.includes('ItemFilter.build(')||!panel.includes('ItemFilter.manualSections(')||!panel.includes('ItemFilter.branchTree(')
      ||!itemFilter.includes('function FilterNavigator(')||!itemFilter.includes('item.weaponType || item.actionType'))throw new Error('shared hierarchical grouping or manual override missing');
  if(itemFilter.includes('npcshop-category-row'))throw new Error('shared navigator leaked an NPC-shop skin class');
  if(!panel.includes('new InventoryUI.InventoryFilterControl(')||!panel.includes("setFilterSpec('背包'")
      ||!panelUi.includes('workbench-secondary-page npcshop-help-page')||!css.includes('top:var(--workbench-header-height,48px)'))throw new Error('shop bag authority tree or secondary-page coverage contract missing');
  if(!panel.includes("presentation:'drilldown'")||panel.includes("presentation:'popover'")
      ||!panel.includes("navigatorPresentation:'drilldown'")
      ||!panel.includes('view.chrome.title.appendChild(hint)')
      ||!itemFilter.includes('FilterNavigator.prototype._renderDrilldown'))throw new Error('unified full-width inline hierarchy navigation contract missing');
  if(!panel.includes("scope:'same_name'")||!panel.includes("policy:'plain_only'"))throw new Error('same-name protected bulk sale flow missing');
  const workbenchComponents=fs.readFileSync(WORKBENCH_COMPONENTS_SOURCE,'utf8');
  const workbenchComponentsCss=fs.readFileSync(path.join(WEB,'css','workbench','components.css'),'utf8');
  if(!secondary.includes('new this._components.QuantityControl')
      ||!secondary.includes('showPlusFive:true')||!secondary.includes('showMax:true')||!secondary.includes('showRange:true')
      ||!workbenchComponents.includes("this.numberInput.type = 'number'")
      ||!workbenchComponents.includes("this.rangeInput.type = 'range'"))throw new Error('shared numeric and slider quantity control missing');
  if(!secondary.includes('sliderMax:authorityMaximum')
      ||!secondary.includes('presetMax:effective')
      ||!secondary.includes("maxLabel:'可用'")
      ||!secondary.includes('this._lineRecords = {purchase:{}, sale:{}}')
      ||!workbenchComponents.includes('Math.log(quantity - this._min + 1)')
      ||!workbenchComponents.includes('linearSliderThreshold || 200')
      ||!workbenchComponents.includes("this.rangeInput.setAttribute('aria-valuetext'")
      ||!workbenchComponents.includes("event.key === 'PageUp'")
      ||!workbenchComponents.includes("this.numberInput.setAttribute('aria-invalid'")
      ||!workbenchComponentsCss.includes('.workbench-quantity-range::-webkit-slider-runnable-track')
      ||!workbenchComponentsCss.includes('var(--quantity-accent) 0 var(--quantity-progress)')
      ||workbenchComponentsCss.includes('accent-color:')) {
    throw new Error('adaptive authority-bounded quantity slider, validation, or inherited skin contract missing');
  }
  if(!panel.includes('InventoryRuntime.InventoryCoordinator')
      ||!panelUi.includes('.OwnedInventoryPane')
      ||!panelUi.includes('_inventoryCoordinator.autoTransfer(source, target')
      ||!workbenchComponents.includes('OwnedInventoryPane.prototype.quickTransfer'))throw new Error('battlebox organization route must reuse inventory authority through owned-pane coordination');
  if(!css.includes('.npcshop-catalog-grid::-webkit-scrollbar')||!css.includes('scrollbar-width:thin'))throw new Error('scoped shop scrollbar skin missing');
  if(!css.includes('.npcshop-help-page')||!css.includes('.npcshop-help-card'))throw new Error('secondary help page styles missing');
  if(!/#panel-container\[data-panel="npcshop"\]\s+#panel-content[\s\S]*?inset:\s*0/.test(css))throw new Error('npcshop full anchor missing');
  const workbench=fs.readFileSync(WORKBENCH_SOURCE,'utf8');
  const primitives=fs.readFileSync(WORKBENCH_PRIMITIVES_SOURCE,'utf8');
  const inventoryWorkbench=[fs.readFileSync(INVENTORY_WORKBENCH_SOURCE,'utf8')].concat(INVENTORY_WORKBENCH_MODULE_SOURCES.map(name=>fs.readFileSync(path.join(WEB,'modules',name),'utf8'))).join('\n');
  const inventoryUi=fs.readFileSync(INVENTORY_UI_SOURCE,'utf8');
  const kshop=[fs.readFileSync(KSHOP_SOURCE,'utf8')].concat(KSHOP_MODULE_SOURCES.map(name=>fs.readFileSync(path.join(WEB,'modules',name),'utf8'))).join('\n');
  if(!primitives.includes('function EntityTile(')||!primitives.includes('function ItemCard(')||!workbench.includes('function ItemGrid(')||!workbench.includes('function GridDensityController('))throw new Error('Workbench item/density primitives missing');
  if(!inventoryUi.includes('function OwnedInventoryViewShell(')
      ||![panel,kshop].every(source=>source.includes('new InventoryUI.OwnedInventoryViewShell('))
      ||!inventoryWorkbench.includes('.OwnedInventoryViewShell(')
      ||[panel,kshop,inventoryWorkbench].some(source=>source.includes('new Workbench.ItemGrid(')))throw new Error('owned inventory shell boundary missing');
  if(!panel.includes('Workbench.ItemCard.renderCatalog'))throw new Error('NPC shop must render catalog cards via Workbench.ItemCard');
  const tooltip=fs.readFileSync(path.join(WEB,'modules','tooltip.js'),'utf8');
  if(!panel.includes('.bindAsyncHover(node,')||!panel.includes("PanelTooltip.createScope('npcshop')")
      ||!tooltip.includes('function createScope(')||!tooltip.includes('function releaseTree(')
      ||!inventoryWorkbench.includes('PanelTooltip.bindAsyncHover'))throw new Error('Panel async tooltip ownership scope is not shared');
  if(!css.includes('.item-grid-compact'))throw new Error('Compact item-grid modifier styles missing');
}
function contractQuantityProbe(){
  const contract=JSON.parse(fs.readFileSync(PANEL_CONTRACT_SOURCE,'utf8'));
  const npcDomain=contract&&Array.isArray(contract.domains)&&contract.domains.find(domain=>domain&&domain.id==='npcshop');
  const quantityField=npcDomain&&Array.isArray(npcDomain.numericFields)&&npcDomain.numericFields.find(field=>field&&field.id==='purchaseQuantity');
  const policy=quantityField&&quantityField.interactionPolicy;
  const requiredPolicy={previewInputMaximumField:'purchaseLimit',directCommitMaximumField:'maxPurchasable',maximumAction:'set-direct-commit-maximum',infeasibleIntent:'allow-preview-block-commit',previewInFlight:'visible-lock'};
  const policyKeys=policy&&Object.keys(policy).sort(),requiredPolicyKeys=Object.keys(requiredPolicy).sort();
  if(!policy||JSON.stringify(policyKeys)!==JSON.stringify(requiredPolicyKeys)||requiredPolicyKeys.some(key=>policy[key]!==requiredPolicy[key]))throw new Error('NPC purchase quantity interaction policy drift');
  const values=contract&&contract.vectors&&contract.vectors.npcshop&&contract.vectors.npcshop.purchaseQuantity&&contract.vectors.npcshop.purchaseQuantity.valid;
  if(!Array.isArray(values))throw new Error('NPC purchase quantity contract vector missing');
  const probe=values.find(value=>Number(value)===4549)||values.find(value=>Number.isInteger(value)&&value>100&&value<999999);
  if(!probe)throw new Error('NPC purchase quantity contract needs a representative value above 100');
  return Number(probe);
}
function edge(){return[
  path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Microsoft','Edge','Application','msedge.exe'),
  path.join(process.env.ProgramFiles||'C:\\Program Files','Microsoft','Edge','Application','msedge.exe')
].find(fs.existsSync)}
function server(){return new Promise(resolve=>{const s=http.createServer((req,res)=>{const pathname=decodeURIComponent(url.parse(req.url).pathname);const file=path.normalize(path.join(WEB,pathname));const rel=path.relative(WEB,file);if(rel.startsWith('..')||path.isAbsolute(rel)){res.writeHead(403);res.end();return}fs.readFile(file,(err,data)=>{if(err){res.writeHead(404);res.end();return}const ext=path.extname(file);res.writeHead(200,{'Content-Type':ext==='.html'?'text/html; charset=utf-8':ext==='.css'?'text/css; charset=utf-8':ext==='.js'?'text/javascript; charset=utf-8':'application/octet-stream'});res.end(data)})});s.listen(0,'127.0.0.1',()=>resolve(s))})}
(async()=>{audit();const contractQuantity=contractQuantityProbe();if(!fs.existsSync(PLAYWRIGHT))throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');const executablePath=edge();if(!executablePath)throw new Error('Microsoft Edge not found');const {chromium}=require(PLAYWRIGHT),s=await server(),browser=await chromium.launch({executablePath,headless:true});try{const page=await browser.newPage({viewport:{width:1366,height:768}}),errors=[],failed=[];page.on('pageerror',e=>errors.push(e.message));page.on('requestfailed',r=>failed.push(r.url()));await page.goto('http://127.0.0.1:'+s.address().port+'/modules/npcshop/dev/harness.html?contractQuantity='+encodeURIComponent(contractQuantity),{waitUntil:'load'});await page.waitForFunction(()=>window.__qaDone===true,null,{timeout:20000});const result=await page.evaluate(()=>({result:window.__qaResult,error:window.__qaError}));if(result.error)throw new Error(result.error);if(errors.length)throw new Error('page errors: '+errors.join(' | '));if(failed.length)throw new Error('failed requests: '+failed.join(' | '));if(!result.result||result.result.passed!==result.result.total){const bad=result.result?result.result.checks.filter(c=>!c.ok):[];throw new Error('harness failed: '+JSON.stringify(bad))}console.log('NPC shop harness '+result.result.passed+'/'+result.result.total+' passed (contract quantity '+contractQuantity+')')}finally{await browser.close();await new Promise(r=>s.close(r))}})().catch(error=>{console.error(error.stack||error);process.exit(1)});
