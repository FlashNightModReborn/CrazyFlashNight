#!/usr/bin/env node
'use strict';
const fs=require('fs'),http=require('http'),path=require('path'),url=require('url');
const {readCssBundle}=require('./lib/read-css-bundle.js');
const BrowserChildResourceClosure=require('./workbench-live-e2e/lib/browser-child-resource-closure.js');
const ROOT=path.resolve(__dirname,'..'),WEB=path.join(ROOT,'launcher','web');
const PLAYWRIGHT=path.join(ROOT,'launcher','perf','node_modules','playwright');
const IDENTITY_ONLY=process.argv.includes('--identity-only');
const INVENTORY_WORKBENCH_MODULES=[
  'inventory-workbench-config.js','inventory-workbench-preparation-menu.js',
  'inventory-workbench-navigation.js','inventory-workbench-header.js',
  'inventory-workbench-quick-transfer.js','inventory-workbench-owned-view.js',
  'inventory-storage-workbench.js',
  'crafting-inventory-organizer.js'
];
function audit(){
  const panel=fs.readFileSync(path.join(WEB,'modules','crafting.js'),'utf8');
  const materials=fs.readFileSync(path.join(WEB,'modules','crafting-materials.js'),'utf8');
  const detailPresenter=fs.readFileSync(path.join(WEB,'modules','crafting-detail-presenter.js'),'utf8');
  const harness=fs.readFileSync(path.join(WEB,'modules','crafting','dev','harness.html'),'utf8');
  const equipmentInspector=fs.readFileSync(path.join(WEB,'modules','equipment-inspector.js'),'utf8');
  const craftingInspector=fs.readFileSync(path.join(WEB,'modules','crafting-inspector.js'),'utf8');
  const inspectionViewport=fs.readFileSync(path.join(WEB,'modules','workbench-inspection-viewport.js'),'utf8');
  const dressupRenderer=fs.readFileSync(path.join(WEB,'modules','dressup-doll-renderer.js'),'utf8');
  const runtime=fs.readFileSync(path.join(WEB,'modules','crafting-runtime.js'),'utf8');
  const panelRuntime=fs.readFileSync(path.join(WEB,'modules','panel-runtime.js'),'utf8');
  const craftingServicePath=path.join(ROOT,'scripts','类定义','org','flashNight','arki','item','CraftingPanelService.as');
  const craftingServiceBytes=fs.readFileSync(craftingServicePath);
  const craftingService=craftingServiceBytes.toString('utf8').replace(/\r\n/g,'\n');
  const css=readCssBundle(path.join(WEB,'css','panels.css'),{rootDir:path.join(WEB,'css')});
  const registry=fs.readFileSync(path.join(WEB,'modules','panels-lazy-registry.js'),'utf8');
  const inventoryWorkbench=INVENTORY_WORKBENCH_MODULES
    .map(name=>fs.readFileSync(path.join(WEB,'modules',name),'utf8')).join('\n');
  if(!panel.includes("new Workbench.DualPaneShell")
      ||!panel.includes("leftLabel:_mode === 'materials' ? '材料目录' : '配方目录'")
      ||!panel.includes("rightLabel:_mode === 'materials' ? '来源与用途' : '合成详情'"))throw new Error('dual-pane contract missing');
  if(!panel.includes("initData.view === 'materials'")||!panel.includes("request('materials'")||!panel.includes("request('materialDetail'")
      ||!panel.includes('CraftingMaterials.create')||!materials.includes("title:'材料目录'")
      ||!materials.includes("'从哪里获得'")||!materials.includes("'会用在哪里'"))throw new Error('material catalog/detail contract missing');
  if(!panel.includes("panelId:'crafting-materials'")||!panel.includes('new WorkbenchComponents.HelpAction(')
      ||!materials.includes("layoutMode:options.densityController")
      ||!materials.includes("state.layoutMode === 'compact' ? 7 : 2")
      ||!css.includes('.crafting-material-grid.item-grid-compact')
      ||!harness.includes('material archive exposes the shared full/compact switch and defaults to compact')
      ||!harness.includes('material archive uses the standard workbench help entry')) {
    throw new Error('material density or standard-help contract missing');
  }
  if(!panel.includes("request('preview'")||!panel.includes("request('commit'")||!panel.includes('expectedCraftToken'))throw new Error('preview/token/commit flow missing');
  if(/price\s*\*|smithLevel\s*\*/.test(panel))throw new Error('Web must not reproduce authoritative crafting formulas');
  if(!panel.includes('function isWriteAmbiguous')||!panel.includes('dispatched && isTransportUncertain(response)')
      ||!panel.includes('function requiresReconcile')||panel.includes('function isAmbiguous'))throw new Error('read/write reconcile classification missing');
  if(!panel.includes('function restorePreviewCheckpoint')||!panel.includes('function requiresAuthorityRefresh')
      ||!panel.includes('_needsRefresh')||!panel.includes('return Bridge.send(message)'))throw new Error('preview checkpoint or read-refresh contract missing');
  if(!harness.includes("mode:'delay'")||!harness.includes("mode:'drop'")||!harness.includes("mode:'send_false'")
      ||!harness.includes("error:'malformed_response'")||!harness.includes("'item_not_found'")
      ||!harness.includes("'insufficient_money'"))throw new Error('transport and authority fault regression matrix missing');
  if(!panel.includes('ItemFilter.FilterNavigator')||!panel.includes("visualStyle:'catalog'")
      ||!panel.includes('craftCount:intent.craftCount')
      ||!panel.includes('CraftingInventoryOrganizer.mount(_shellEl')
      ||panel.includes("Panels.open('workbench'"))throw new Error('filter, batch, or embedded organizer route missing');
  if(!panel.includes('function dispatchPreviewIntent')||!panel.includes('function responseMatchesPreviewIntent')
      ||!panel.includes('Superseded read replies are deliberately silent')
      ||!detailPresenter.includes('new WorkbenchComponents.QuantityControl')
      ||!detailPresenter.includes('new WorkbenchComponents.CommitBar')
      ||!detailPresenter.includes('max:99')||!detailPresenter.includes('sliderMax:99')
      ||!detailPresenter.includes('Presenter.prototype.destroy')
      ||detailPresenter.includes('craftToken')||detailPresenter.includes('expectedCraftToken')) {
    throw new Error('stable detail presenter or latest-wins quantity protocol missing');
  }
  if(!panel.includes('canCraftOne === true')||!panel.includes('craftableOnly:_craftableOnly')||!panel.includes('crafting-craftable-toggle'))throw new Error('snapshot availability or craftable-only contract missing');
  if(!inventoryWorkbench.includes('function requestReturn()')
      ||!inventoryWorkbench.includes("kind:'crafting-organizer'")
      ||!inventoryWorkbench.includes("panel:'crafting'")
      ||!inventoryWorkbench.includes('ownerPanel:_owner.panel')
      ||!inventoryWorkbench.includes('panelInstanceId:_owner.panelInstanceId')
      ||!inventoryWorkbench.includes("data-workbench-owner-context', 'crafting-organizer'")
      ||!panel.includes("Panels.getActive() !== 'crafting'")
      ||!panel.includes('panelInstanceId:_panelInstanceId')
      ||!panel.includes('onReturn:restoreFromOrganizer'))throw new Error('embedded battlebox owner contract missing');
  if(!harness.includes("__craftingHarnessScenario==='pg-craft-current-coverage'")
      ||!harness.includes("script.setAttribute('data-pg-craft-dependency',dep)")
      ||!harness.includes('runPgCraftCurrentCoverage()')
      ||!harness.includes('real organizer mount throw fails closed once')
      ||!harness.includes("verifyOrganizerMountCloseFault('send_false'")
      ||!harness.includes("verifyOrganizerMountCloseFault('throw'")
      ||!panel.includes('function recoverOrganizerMountFailure()')
      ||!panel.includes('if (!closeAccepted)')) {
    throw new Error('dynamic crafting organizer current-coverage scenario missing');
  }
  if(!harness.includes("__craftingHarnessScenario==='pg-inventory-owner-fault'")
      ||!harness.includes('runPgInventoryOwnerFault()')
      ||!harness.includes('blocks the next writer while reconciliation is still required')
      ||!harness.includes('rejects the retired instance response after close and rebinds')) {
    throw new Error('crafting owner inventory fault scenario missing');
  }
  if(!harness.includes("__craftingHarnessScenario==='pg-crafting-identity'")
      ||!harness.includes('runPgCraftingIdentity()')
      ||!harness.includes('display search does not expose the internal lookup key')
      ||!panel.includes("iconHtml(output.icon, 'kshop-icon')")
      ||!panel.includes('escapeHtml(value.displayName')
      ||panel.includes('output.icon || output.name')
      ||panel.includes('value.icon || value.name')
      ||materials.includes('item.icon || item.name')
      ||materials.includes('item.displayName || item.name')
      ||materials.includes('source.displayName || source.enemyType')
      ||materials.includes('source.title || source.questId')) {
    throw new Error('crafting identity triple projection contract missing');
  }
  if(craftingServiceBytes[0]!==0xef||craftingServiceBytes[1]!==0xbb||craftingServiceBytes[2]!==0xbf
      ||!craftingService.includes('private static function projectLegacyIdentityField(value, name:String):String')
      ||!craftingService.includes('trimmed.toLowerCase() == "undefined"')
      ||!craftingService.includes('private static function projectVisibleSourceLabel')
      ||!craftingService.includes('"未知敌人"')
      ||!craftingService.includes('"未知任务"')
      ||!craftingService.includes('displayName:projectLegacyIdentityField(data.displayname, name)')
      ||!craftingService.includes('icon:projectLegacyIdentityField(data.icon, name)')
      ||!craftingService.includes('crafted:current.output')) {
    throw new Error('CraftingPanelService AS2 identity projection/BOM contract missing');
  }
  if(!runtime.includes("require('./panel-runtime.js')")||!runtime.includes('new PanelRuntime.PanelRequestMux')
      ||!runtime.includes("session.ownerPanel === 'crafting'")
      ||!runtime.includes('panelInstanceId:context.session.panelInstanceId')
      ||!runtime.includes("data.panel === 'crafting'")
      ||!runtime.includes('data.panelInstanceId === entry.session.panelInstanceId')
      ||!runtime.includes('validateBusinessResponse(data, entry)')
      ||!runtime.includes("require('./inventory-runtime.js')")
      ||!runtime.includes('InventoryRuntime.isValidItemProjection')
      ||!runtime.includes('validOutputReceipt(data.outputReceipt, data.acceptedPlan, data.crafted)')
      ||!runtime.includes("'outputPrototype'")
      ||!runtime.includes("'outputReceipt'")
      ||!runtime.includes('metadata:{payload:frozenPayload}')
      ||!runtime.includes('data.material.name === payload.itemName')
      ||!runtime.includes('data.itemName === payload.itemName')
      ||!panel.includes("ownerPanel:'crafting'")
      ||!harness.includes('mixedCraftingOwnerRejected')
      ||!panelRuntime.includes('entry.generation !== this._generation'))throw new Error('strict shared crafting exact-owner mux missing');
  if(!registry.includes("registerLazy('crafting'")||!registry.includes("'modules/item-filter.js'")
      ||!registry.includes("'modules/crafting-materials.js'")||!registry.includes("'modules/crafting-detail-presenter.js'")
      ||!css.includes('.crafting-commit-btn')||!css.includes('.crafting-catalog-grid::-webkit-scrollbar')
      ||!css.includes('.crafting-material-card')||!css.includes('[data-profile="archive-reference"]')
      ||!panel.includes("profile:_mode === 'materials' ? 'archive-reference' : 'catalog-decision'"))
    throw new Error('lazy registry, profile mapping, or crafting skin missing');
  if(!css.includes('.item-filter-catalog .item-filter-option')||!css.includes('grid-template-columns:minmax(0,1.55fr) 28px minmax(330px,.95fr)')||!css.includes('.crafting-recipe-card.craftable'))throw new Error('shared filter, 60:40 layout, or craftable marker skin missing');
  if(!css.includes('.crafting-commit-bar')||!css.includes('flex:1 1 auto')
      ||!css.includes('.crafting-detail-view [data-title]:focus-visible::after')
      ||!css.includes('font:11px/1.25 "Microsoft YaHei",sans-serif')
      ||!harness.includes('returning to the in-flight value cancels a superseded queued preview')
      ||!harness.includes('overflow CTA is a visible hit-testable scroller sibling at this viewport')
      ||!harness.includes('embedded organizer destroys the recipe detail presenter and its detached quantity listeners')) {
    throw new Error('fixed crafting CTA, keyboard tooltip, or A4 lifecycle coverage missing');
  }
  if(!css.includes('grid-template-columns:minmax(0,44fr) 28px minmax(360px,56fr)')
      ||!css.includes('grid-template-rows:minmax(0,1fr)')
      ||!css.includes('grid-auto-rows:minmax(58px,auto)')
      ||!css.includes('.crafting-panel .crafting-material-card')
      ||!harness.includes('for(var i=3;i<=223;i++)')
      ||!harness.includes("firstCardRect.height>=58")) {
    throw new Error('material 44:56 geometry, readable-row, or 223-entry reachability coverage missing');
  }
  if(!css.includes('#panel-container[data-panel="crafting"] #panel-content')||!css.includes('#panel-container[data-panel="crafting"] #panel-backdrop'))throw new Error('crafting full-screen anchor contract missing');
  if(!panel.includes('CraftingInspector.open')||!panel.includes('gender: _snapshot && _snapshot.gender')||!panel.includes('PanelTooltip.hide()'))throw new Error('crafting inspector entry or gender contract missing');
  const harnessViewportIndex=harness.indexOf('workbench-inspection-viewport.js');
  const harnessInspectorIndex=harness.indexOf('equipment-inspector.js');
  if(harnessViewportIndex<0||harnessInspectorIndex<=harnessViewportIndex)throw new Error('crafting harness must load the shared inspection viewport before EquipmentInspector');
  const harnessMaterialsIndex=harness.indexOf('crafting-materials.js');
  const harnessPresenterIndex=harness.indexOf('crafting-detail-presenter.js');
  const harnessRuntimeIndex=harness.indexOf('crafting-runtime.js');
  if(harnessMaterialsIndex<0||harnessPresenterIndex<=harnessMaterialsIndex||harnessRuntimeIndex<=harnessPresenterIndex
      ||!harness.includes("Panels.open('crafting',{view:'materials'")
      ||!harness.includes("message.cmd==='materials'")
      ||!harness.includes("message.cmd==='materialDetail'"))throw new Error('crafting material harness coverage or dependency order missing');
  const craftingRegistry=registry.slice(registry.indexOf("registerLazy('crafting'"),registry.indexOf("registerLazy('skills'"));
  const orderedInspectorDeps=['modules/asset-timeline.js','modules/dressup-doll-renderer.js','modules/workbench-inspection-viewport.js','modules/equipment-inspector.js','modules/crafting-inspector.js','modules/crafting-materials.js','modules/crafting-detail-presenter.js','modules/crafting-runtime.js','modules/crafting.js'];
  let previousDependencyIndex=-1;
  orderedInspectorDeps.forEach(dependency=>{
    const dependencyIndex=craftingRegistry.indexOf("'"+dependency+"'");
    if(dependencyIndex<=previousDependencyIndex)throw new Error('crafting inspector lazy dependency order missing: '+dependency);
    previousDependencyIndex=dependencyIndex;
  });
  if(!craftingInspector.includes('EquipmentInspector.open(copyOptions(options))')||
      !craftingInspector.includes('EquipmentInspector.resolveItemSource(output, gender, manifest)')||
      !craftingInspector.includes("result.kind = 'crafting-inspector'")||
      !craftingInspector.includes("result.context = 'crafting'"))throw new Error('CraftingInspector compatibility adapter contract missing');
  if(!inspectionViewport.includes('function Camera(')
      ||!inspectionViewport.includes('Camera.prototype.activate')
      ||!inspectionViewport.includes('Camera.prototype.deactivate')
      ||!equipmentInspector.includes('WorkbenchInspectionViewport.create'))throw new Error('shared inspection viewport contract missing');
  if(!equipmentInspector.includes("majorType === '武器'")||!equipmentInspector.includes("majorType === '防具'")||!equipmentInspector.includes('attackMode: source.use')||!equipmentInspector.includes('Icons.resolveStatic(iconState.name)'))throw new Error('equipment inspector route, variant, or icon animation contract missing');
  if(!dressupRenderer.includes('state.directSkinKey')||!dressupRenderer.includes("rig: 'product-direct'")
      ||!dressupRenderer.includes('strictFields')||!equipmentInspector.includes("'刀2_装扮'")||!equipmentInspector.includes("'刀3_装扮'")
      ||!equipmentInspector.includes('ignoreCssTransforms: true')||!dressupRenderer.includes('animationFrameInterval')
      ||!dressupRenderer.includes('setPixelRatio: function')||!equipmentInspector.includes('renderer.setPixelRatio(currentPixelRatio())')
      ||!equipmentInspector.includes("'holder_contract_failed'")||!equipmentInspector.includes("'asset_load_failed'"))throw new Error('strict composite paper-doll renderer, 24fps throttle, responsive backing, or fail-safe fallback contract missing');
}
function edge(){return[
  path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Microsoft','Edge','Application','msedge.exe'),
  path.join(process.env.ProgramFiles||'C:\\Program Files','Microsoft','Edge','Application','msedge.exe')
].find(fs.existsSync)}
function server(resourceLedger){return new Promise(resolve=>{const s=http.createServer((req,res)=>{const pathname=decodeURIComponent(url.parse(req.url).pathname);const file=path.normalize(path.join(WEB,pathname));const rel=path.relative(WEB,file);if(rel.startsWith('..')||path.isAbsolute(rel)){res.writeHead(403);res.end();return}const occurrence=resourceLedger.begin(req.url,file);fs.readFile(file,(err,data)=>{if(err){occurrence.failure('read_failed');res.writeHead(404);res.end();return}const ext=path.extname(file),mime=ext==='.html'?'text/html; charset=utf-8':ext==='.css'?'text/css; charset=utf-8':ext==='.js'?'text/javascript; charset=utf-8':'application/octet-stream';occurrence.success(data,mime);res.writeHead(200,{'Content-Type':mime});res.end(data)})});s.listen(0,'127.0.0.1',()=>resolve(s))})}
async function runViewport(browser,serverInstance,viewport,query){
  const page=await browser.newPage({viewport}),errors=[],failed=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('requestfailed',request=>failed.push(request.url()));
  try{
    await page.goto('http://127.0.0.1:'+serverInstance.address().port+'/modules/crafting/dev/harness.html'+(query||''),{waitUntil:'load'});
    const doneWait={timeout:25000};
    // The legacy 120-check baseline observes the runner's RAF poll as its
    // ambient animation-frame baseline.  The dedicated cleanup scenario must
    // instead see only product frames so it can require a strict zero.
    if(query)doneWait.polling=50;
    await page.waitForFunction(()=>window.__qaDone===true,null,doneWait);
    const result=await page.evaluate(()=>({result:window.__qaResult,error:window.__qaError}));
    if(result.error)throw new Error(viewport.width+'x'+viewport.height+': '+result.error);
    if(errors.length)throw new Error(viewport.width+'x'+viewport.height+' page errors: '+errors.join(' | '));
    if(failed.length)throw new Error(viewport.width+'x'+viewport.height+' failed requests: '+failed.join(' | '));
    if(!result.result||result.result.passed!==result.result.total){
      const bad=result.result?result.result.checks.filter(check=>!check.ok):[];
      throw new Error(viewport.width+'x'+viewport.height+' harness failed: '+JSON.stringify(bad));
    }
    return result.result;
  }finally{await page.close()}
}
async function run(){
  audit();
  if(!fs.existsSync(PLAYWRIGHT))throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
  const executablePath=edge();if(!executablePath)throw new Error('Microsoft Edge not found');
  const resourceLedger=BrowserChildResourceClosure.createServedResourceLedger({root:WEB});
  const {chromium}=require(PLAYWRIGHT),serverInstance=await server(resourceLedger),
    browser=await chromium.launch({executablePath,headless:true});
  const viewports=[{width:1024,height:576},{width:1366,height:768},{width:1920,height:1080}];
  let output;
  try{
    if(IDENTITY_ONLY){
      const identity=[];
      for(const viewport of viewports){
        const result=await runViewport(browser,serverInstance,viewport,'?scenario=pg-crafting-identity');
        if(result.total!==10)throw new Error('PG-CRAFTING-IDENTITY must contain exactly 10 checks, got '+result.total);
        identity.push(result);
      }
      output={mode:'identity-only',executablePath,viewports,identity,
        summary:'PG-CRAFTING-IDENTITY '+identity[0].passed+'/'+identity[0].total
          +' passed at '+viewports.map(viewport=>viewport.width+'x'+viewport.height).join(', ')};
    }else{
      const baseline=[],coverage=[],fault=[],identity=[];
      for(const viewport of viewports){
        const result=await runViewport(browser,serverInstance,viewport);
        if(result.total!==120)throw new Error('baseline crafting harness must preserve all 120 checks, got '+result.total);
        baseline.push(result);
        const coverageResult=await runViewport(browser,serverInstance,viewport,'?scenario=pg-craft-current-coverage');
        if(coverageResult.total!==15)throw new Error('PG-CRAFT-CURRENT-COVERAGE must contain exactly 15 checks, got '+coverageResult.total);
        coverage.push(coverageResult);
        const faultResult=await runViewport(browser,serverInstance,viewport,'?scenario=pg-inventory-owner-fault');
        if(faultResult.total!==8)throw new Error('PG-INVENTORY-FAULT owner journey must contain exactly 8 checks, got '+faultResult.total);
        fault.push(faultResult);
        const identityResult=await runViewport(browser,serverInstance,viewport,'?scenario=pg-crafting-identity');
        if(identityResult.total!==10)throw new Error('PG-CRAFTING-IDENTITY must contain exactly 10 checks, got '+identityResult.total);
        identity.push(identityResult);
      }
      output={mode:'full',executablePath,viewports,baseline,coverage,fault,identity,
        summary:'Crafting harness baseline '+baseline[0].passed+'/'+baseline[0].total
          +' + PG-CRAFT-CURRENT-COVERAGE '+coverage[0].passed+'/'+coverage[0].total
          +' + PG-INVENTORY-FAULT owner journey '+fault[0].passed+'/'+fault[0].total
          +' + PG-CRAFTING-IDENTITY '+identity[0].passed+'/'+identity[0].total
          +' passed at '+viewports.map(viewport=>viewport.width+'x'+viewport.height).join(', ')};
    }
  }finally{
    await browser.close();
    await new Promise(resolve=>serverInstance.close(resolve));
  }
  output.servedResourceLedger=resourceLedger.snapshot();
  return output;
}
module.exports={run};
if(require.main===module)run().then(result=>console.log(result.summary))
  .catch(error=>{console.error(error.stack||error);process.exitCode=1});
