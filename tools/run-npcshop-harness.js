#!/usr/bin/env node
'use strict';
const fs=require('fs'),http=require('http'),path=require('path'),url=require('url');
const ROOT=path.resolve(__dirname,'..'),WEB=path.join(ROOT,'launcher','web');
const PLAYWRIGHT=path.join(ROOT,'launcher','perf','node_modules','playwright');
const WORKBENCH_SOURCE=path.join(WEB,'modules','workbench.js');
const INVENTORY_WORKBENCH_SOURCE=path.join(WEB,'modules','inventory-workbench.js');
const INVENTORY_UI_SOURCE=path.join(WEB,'modules','inventory-ui.js');
const KSHOP_SOURCE=path.join(WEB,'modules','kshop.js');
const ITEM_FILTER_SOURCE=path.join(WEB,'modules','item-filter.js');

function audit(){
  const panel=fs.readFileSync(path.join(WEB,'modules','npcshop.js'),'utf8');
  const runtime=fs.readFileSync(path.join(WEB,'modules','npcshop-runtime.js'),'utf8');
  const css=fs.readFileSync(path.join(WEB,'css','panels.css'),'utf8');
  if(!['bag','material','intelligence'].every(v=>panel.includes("viewId:'"+v+"'")))throw new Error('right-view sibling contract missing');
  if(!panel.includes("domain:'inventory'") || !runtime.includes("options.domain || 'npcshop'"))throw new Error('npcshop/inventory domain mux missing');
  if(/unitPrice\s*\*|basePrice\s*\*/.test(panel))throw new Error('Web must not reproduce authoritative price formula');
  if(/type\s*=\s*['"]number['"]|type=['"]number['"]/.test(panel))throw new Error('NPC shop must not use native number inputs');
  if(!panel.includes("'tradePreview'")||!panel.includes("'tradeCommit'"))throw new Error('atomic settlement flow missing');
  if(!panel.includes('npcshop-settlement-page'))throw new Error('secondary settlement route missing');
  if(!panel.includes('npcshop-help-page')||!panel.includes('cf7.npcshop.guide.v1.'))throw new Error('intent-preserving help and one-time guide flow missing');
  const itemFilter=fs.readFileSync(ITEM_FILTER_SOURCE,'utf8');
  if(!panel.includes('ItemFilter.build(')||!panel.includes('ItemFilter.manualSections(')||!panel.includes('ItemFilter.branchTree(')
      ||!itemFilter.includes('function FilterNavigator(')||!itemFilter.includes('item.weaponType || item.actionType'))throw new Error('shared hierarchical grouping or manual override missing');
  if(itemFilter.includes('npcshop-category-row'))throw new Error('shared navigator leaked an NPC-shop skin class');
  if(!panel.includes('new InventoryUI.InventoryFilterControl(')||!panel.includes("setFilterSpec('背包'")
      ||!panel.includes('workbench-secondary-page npcshop-help-page')||!css.includes('top:var(--workbench-header-height,48px)'))throw new Error('shop bag authority tree or secondary-page coverage contract missing');
  if(!panel.includes("presentation:'drilldown'")||panel.includes("presentation:'popover'")
      ||!panel.includes("navigatorPresentation:'drilldown'")
      ||!panel.includes('view.chrome.title.appendChild(hint)')
      ||!itemFilter.includes('FilterNavigator.prototype._renderDrilldown'))throw new Error('unified full-width inline hierarchy navigation contract missing');
  if(!panel.includes("scope:'same_name'")||!panel.includes("policy:'plain_only'"))throw new Error('same-name protected bulk sale flow missing');
  if(!panel.includes("stepButton('+5'")||!panel.includes("stepButton('最大'"))throw new Error('equipment quantity accelerators missing');
  if(!panel.includes('InventoryRuntime.InventoryCoordinator')||!panel.includes('autoTransfer(source, target'))throw new Error('battlebox organization route must reuse inventory authority');
  if(!css.includes('.npcshop-catalog-grid::-webkit-scrollbar')||!css.includes('scrollbar-width:thin'))throw new Error('scoped shop scrollbar skin missing');
  if(!css.includes('.npcshop-help-page')||!css.includes('.npcshop-help-card'))throw new Error('secondary help page styles missing');
  if(!/#panel-container\[data-panel="npcshop"\]\s+#panel-content[\s\S]*?inset:\s*0/.test(css))throw new Error('npcshop full anchor missing');
  const workbench=fs.readFileSync(WORKBENCH_SOURCE,'utf8');
  const inventoryWorkbench=fs.readFileSync(INVENTORY_WORKBENCH_SOURCE,'utf8');
  const inventoryUi=fs.readFileSync(INVENTORY_UI_SOURCE,'utf8');
  const kshop=fs.readFileSync(KSHOP_SOURCE,'utf8');
  if(!workbench.includes('function ItemCard(')||!workbench.includes('function ItemGrid(')||!workbench.includes('function GridDensityController('))throw new Error('Workbench item/density primitives missing');
  if(!inventoryUi.includes('function OwnedInventoryViewShell(')
      ||![panel,kshop,inventoryWorkbench].every(source=>source.includes('new InventoryUI.OwnedInventoryViewShell('))
      ||[panel,kshop,inventoryWorkbench].some(source=>source.includes('new Workbench.ItemGrid(')))throw new Error('owned inventory shell boundary missing');
  if(!panel.includes('Workbench.ItemCard.renderCatalog'))throw new Error('NPC shop must render catalog cards via Workbench.ItemCard');
  if(!panel.includes('PanelTooltip.bindAsyncHover')||!inventoryWorkbench.includes('PanelTooltip.bindAsyncHover'))throw new Error('Panel async tooltip binding is not shared');
  if(!css.includes('.item-grid-compact'))throw new Error('Compact item-grid modifier styles missing');
}
function edge(){return[
  path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Microsoft','Edge','Application','msedge.exe'),
  path.join(process.env.ProgramFiles||'C:\\Program Files','Microsoft','Edge','Application','msedge.exe')
].find(fs.existsSync)}
function server(){return new Promise(resolve=>{const s=http.createServer((req,res)=>{const pathname=decodeURIComponent(url.parse(req.url).pathname);const file=path.normalize(path.join(WEB,pathname));const rel=path.relative(WEB,file);if(rel.startsWith('..')||path.isAbsolute(rel)){res.writeHead(403);res.end();return}fs.readFile(file,(err,data)=>{if(err){res.writeHead(404);res.end();return}const ext=path.extname(file);res.writeHead(200,{'Content-Type':ext==='.html'?'text/html; charset=utf-8':ext==='.css'?'text/css; charset=utf-8':ext==='.js'?'text/javascript; charset=utf-8':'application/octet-stream'});res.end(data)})});s.listen(0,'127.0.0.1',()=>resolve(s))})}
(async()=>{audit();if(!fs.existsSync(PLAYWRIGHT))throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');const executablePath=edge();if(!executablePath)throw new Error('Microsoft Edge not found');const {chromium}=require(PLAYWRIGHT),s=await server(),browser=await chromium.launch({executablePath,headless:true});try{const page=await browser.newPage({viewport:{width:1366,height:768}}),errors=[],failed=[];page.on('pageerror',e=>errors.push(e.message));page.on('requestfailed',r=>failed.push(r.url()));await page.goto('http://127.0.0.1:'+s.address().port+'/modules/npcshop/dev/harness.html',{waitUntil:'load'});await page.waitForFunction(()=>window.__qaDone===true,null,{timeout:20000});const result=await page.evaluate(()=>({result:window.__qaResult,error:window.__qaError}));if(result.error)throw new Error(result.error);if(errors.length)throw new Error('page errors: '+errors.join(' | '));if(failed.length)throw new Error('failed requests: '+failed.join(' | '));if(!result.result||result.result.passed!==result.result.total){const bad=result.result?result.result.checks.filter(c=>!c.ok):[];throw new Error('harness failed: '+JSON.stringify(bad))}console.log('NPC shop harness '+result.result.passed+'/'+result.result.total+' passed')}finally{await browser.close();await new Promise(r=>s.close(r))}})().catch(error=>{console.error(error.stack||error);process.exit(1)});
