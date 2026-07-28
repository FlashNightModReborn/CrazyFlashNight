#!/usr/bin/env node
'use strict';
const fs=require('fs'),http=require('http'),path=require('path'),url=require('url');
const {readCssBundle}=require('./lib/read-css-bundle.js');
const ROOT=path.resolve(__dirname,'..'),WEB=path.join(ROOT,'launcher','web');
const PLAYWRIGHT=path.join(ROOT,'launcher','perf','node_modules','playwright');

function hasAll(source,fragments){return fragments.every(fragment=>source.includes(fragment))}
function inOrder(source,fragments){
  let cursor=0;
  return fragments.every(fragment=>{const index=source.indexOf(fragment,cursor);if(index<0)return false;cursor=index+fragment.length;return true})
}
function between(source,start,end){
  const from=source.indexOf(start);if(from<0)return '';
  const to=source.indexOf(end,from+start.length);return to<0?'':source.slice(from,to);
}
function audit(){
  const readModule=name=>fs.readFileSync(path.join(WEB,'modules',name),'utf8');
  const runtime=fs.readFileSync(path.join(WEB,'modules','equipment-tuning-runtime.js'),'utf8');
  const inventoryRuntime=fs.readFileSync(path.join(WEB,'modules','inventory-runtime.js'),'utf8');
  const view=readModule('equipment-tuning-view.js');
  const model=readModule('equipment-tuning-model.js');
  const render=readModule('equipment-tuning-render.js');
  const inspectionViewport=readModule('workbench-inspection-viewport.js');
  const inspector=readModule('equipment-inspector.js');
  const tuningSource=[model,render,view].join('\n');
  const config=readModule('inventory-workbench-config.js');
  const header=readModule('inventory-workbench-header.js');
  const ownedView=readModule('inventory-workbench-owned-view.js');
  const quickTransfer=readModule('inventory-workbench-quick-transfer.js');
  const tuningScope=readModule('inventory-tuning-scope.js');
  const workbench=readModule('inventory-storage-workbench.js');
  const facade=readModule('inventory-workbench.js');
  const inventorySource=[config,header,ownedView,quickTransfer,tuningScope,workbench,facade].join('\n');
  const registry=readModule('panels-lazy-registry.js');
  const registryWorkbench=between(registry,"Panels.registerLazy('workbench'","Panels.registerLazy('npcshop'");
  const css=readCssBundle(path.join(WEB,'css','panels.css'),{rootDir:path.join(WEB,'css')});
  const infoProjection=between(render,'TuningView.prototype._renderHeader','TuningView.prototype._renderInstalledState');
  const operationTransition=between(view,'TuningView.prototype.setOperation','TuningView.prototype._selectReplacementCandidate');
  if(!hasAll(runtime,["domain:'equipment_tuning'",'panelInstanceId','viewSessionId',"'disconnected') return !!"]))throw new Error('strict tuning mux or definitive disconnect rule missing');
  if(!hasAll(model,['function quickCommitEligible','enhance|convert|install_tier|install_mod|replace_mod|detach_mod|detach_all_mods'])
      ||!hasAll(view,['expectedTuningToken',"requestPreview('convert'","if (operation === 'replace_mod')"])
      ||!hasAll(render,["replacementMode ? 'replace_mod' : 'install_mod'","requestPreview('detach_all_mods'","_mux.request('tooltip'"]))throw new Error('seven-operation preview/token/tooltip flow missing');
  if(/\(i\s*-\s*1\)\s*\*\s*\(i\s*-\s*1\)|smith.*0\.05/i.test(tuningSource))throw new Error('Web must not reproduce equipment formulas');
  if(!hasAll(view,['reconcileAfterCallId','_refreshRetryRequired','retryInventoryRefresh','this._completeWrite'])
      ||!hasAll(workbench,['completeWrite:function(operation, needsRefresh, callback)','_coordinator.completeExternalWrite(operation, needsRefresh, callback)']))throw new Error('unknown-write reconcile or inventory refresh recovery missing');

  const buildProfile=between(workbench,'function buildProfileDOM','function switchView');
  const switchView=between(workbench,'function switchView','function finishViewSwitch');
  const open=between(workbench,'function activate','function openInventory');
  const openInventory=between(workbench,'function openInventory','function openTuningHelp');
  const close=between(workbench,'function prepareExit','function prepareLeave');
  if(!hasAll(config,['function resolveView(initData)',"view === 'storage' || view === 'tuning' || view === 'build'",'function isViewAllowed'])
      ||!hasAll(header,['function TuningHeaderController','this._onSwitch',"self._onSwitch(self._view === 'tuning' ? 'storage' : 'tuning')"])
      ||!hasAll(workbench,['activate:activate','deactivate:cleanup','function maybeSelectFirstTunable'])
      ||/Panels\.register|InventoryWorkbenchHeader|new Workbench\.DualPaneShell/.test(workbench)
      ||!hasAll(facade,["Panels.register('workbench'",'new Workbench.DualPaneShell',
        'new InventoryWorkbenchHeader.TuningHeaderController','function requestView(next)',
        'InventoryStorageWorkbench.activate(','controllerPorts(),','initialView);',
        'InventoryStorageWorkbench.deactivate()',
        'function rebind(el, initData)'])
      ||!hasAll(buildProfile,['_viewMode = initialView',"if (_viewMode === 'tuning') _tuningView.openSession(_panelInstanceId)","_viewMode === 'tuning' ? _tuningView : _rightView"])
      ||!hasAll(switchView,['_tuningView.canClose()','_tuningView.detachSession','finishViewSwitch'])
      ||!hasAll(open,["requestedView === 'tuning' && !EquipmentTuningRuntime.safeToken(_panelInstanceId)",'buildProfileDOM(profileConfig, requestedView, context)'])
      ||!openInventory.includes('else maybeSelectFirstTunable();')
      ||!hasAll(close,['_tuningView.canClose()','_tuningView.detachSession']))throw new Error('workbench view/rebind/direct-open/detach gate contract missing');

  if(!hasAll(config,['function resolveProfile','function resolveReturnTarget','function ConfirmationPreference'])
      ||!hasAll(ownedView,['function createView','function createToolbar','new Components.OwnedInventoryPane'])
      ||!hasAll(quickTransfer,['function QuickTransferController','QuickTransferController.prototype.acceptClick','QuickTransferController.prototype.isBusy'])
      ||!hasAll(workbench,['new InventoryWorkbenchConfig.ConfirmationPreference','InventoryWorkbenchOwnedView.createView','InventoryWorkbenchOwnedView.createToolbar','new InventoryWorkbenchQuickTransfer.QuickTransferController','_quickTransfer.acceptClick']))throw new Error('inventory workbench split-module composition missing');
  if(!inventoryRuntime.includes('readProjection')||!hasAll(workbench,['_coordinator.readProjection','loadTuningConversionCandidates','loadConversionCandidates:loadTuningConversionCandidates'])
      ||!view.includes('selectConversionTarget')||!render.includes('equipment-tuning-conversion-candidates'))throw new Error('isolated right-pane conversion projection missing');
  if(!hasAll(inventoryRuntime,['normalizeProjectionScope','replaceWindowRequest','normalizeProjectionScope(snapshot.scope) !== normalizeProjectionScope(request.scope)'])
      ||!hasAll(tuningScope,['function Transition','prepareInitial','_captureViewport','Transition.prototype.enter','Transition.prototype.leave','Transition.prototype.restore'])
      ||!hasAll(workbench,["scope:'equipment'",'_tuningScope.enter','_tuningScope.leave','_tuningScope.restore',"setAuthorityDisabled(blocked || _viewMode === 'tuning')"]))throw new Error('equipment-only tuning scope or exact return-state boundary missing');
  if(!hasAll(inspectionViewport,['root.WorkbenchInspectionViewport = api','Camera.prototype.setZoom','Camera.prototype.shift','Camera.prototype.reset'])
      ||!hasAll(inspector,['var EquipmentInspector','resolveItemSource: resolveProductSource','DEFAULT_ZOOM = 1.85','WorkbenchInspectionViewport.create'])
      ||!hasAll(view,['_openInspector','_closeInspector','inspectCurrentEquipment','inspectConversionTarget','this._snapshot.gender'])
      ||!hasAll(render,['equipment-tuning-inspect-trigger','equipment-tuning-convert-inspect'])
      ||!hasAll(workbench,['EquipmentInspector.open','openInspector:openEquipmentInspector','closeInspector:closeEquipmentInspector',"gender !== '男' && gender !== '女'"]))throw new Error('shared tuning equipment inspector adapter missing');
  if(inventorySource.includes('syncTuningConversionFilter')||inventorySource.includes('_conversionFilterRestore')
      ||tuningSource.includes('syncConversionFilter')||tuningSource.includes('_conversionFilterActive'))throw new Error('legacy conversion mutation of visible bag filter remains');
  if(!hasAll(view,['EquipmentTuningView load order: item-filter.js, equipment-tuning-model.js, equipment-tuning-render.js, then equipment-tuning-view.js.','Renderer.install(TuningView, Model)'])
      ||!render.includes('function install(TuningView, Model)'))throw new Error('tuning model/render split or explicit browser load-order diagnosis missing');
  if(!hasAll(render,['function focusRestoreVisible','this._renderFocusDeferred','root.addEventListener(\'pointerdown\''])
      ||!hasAll(fs.readFileSync(path.join(WEB,'modules','equipment-tuning','dev','harness.html'),'utf8'),
        ['blank pointer intent cancels deferred focus','disabled-to-enabled async redraw','aria-hidden or inert ancestors']))throw new Error('tuning deferred-focus ownership gates or counterexamples missing');
  if(!hasAll(model,['function sameLoadoutIdentity','left.sessionGeneration === right.sessionGeneration',
        'left.slotKey === right.slotKey'])
      ||!hasAll(view,["kind:'known'","kind:'unknown'",'Model.sameLoadoutIdentity(source, expectedSource)'])
      ||!hasAll(infoProjection,['equipment-tuning-info-panel','data-tuning-info-title',
        "info.textContent = '调制说明'","info.setAttribute('aria-expanded'",
        "close.setAttribute('data-tuning-focus-key', 'info:close')",
        'TuningView.prototype.consumeEscape','return this._closeInfoPanel();'])
      ||/(?:aria-pressed|data-pinned|info:pin|_infoPanelPinned|_setInfoPinned)/.test(infoProjection)
      ||/_infoPanelPinned|_setInfoPinned/.test(view)
      ||!hasAll(operationTransition,['this._infoSubject = null','this.render({preserveScroll:false})'])
      ||!hasAll(css,['font:700 11px/1 "Microsoft YaHei",sans-serif',
        '.equipment-tuning-commit {','width:100%; margin-top:7px; min-height:40px;',
        '[data-title]:focus-visible::after']))throw new Error('loadout identity or tuning usability debt gate missing');
  if(!inOrder(registryWorkbench,["'modules/item-filter.js'","'modules/asset-timeline.js'","'modules/dressup-doll-renderer.js'","'modules/workbench-inspection-viewport.js'","'modules/equipment-inspector.js'","'modules/inventory-runtime.js'","'modules/inventory-ui.js'","'modules/equipment-tuning-runtime.js'","'modules/equipment-tuning-model.js'","'modules/equipment-tuning-render.js'","'modules/equipment-tuning-view.js'","'modules/inventory-workbench-config.js'","'modules/inventory-workbench-header.js'","'modules/inventory-workbench-quick-transfer.js'","'modules/inventory-workbench-owned-view.js'","'modules/inventory-tuning-scope.js'","'modules/inventory-storage-workbench.js'","'modules/character-build-session.js'","'modules/character-build/character-build-stats-view.js'","'modules/character-build/character-build-doll-preview.js'","'modules/character-build/character-build-template.js'","'modules/character-build-view.js'","'modules/character-build/character-build-tuning.js'","'modules/character-build/character-build-slot-transition.js'","'modules/character-build.js'","'modules/inventory-workbench.js'"])
      ||!hasAll(css,['.equipment-tuning-commit','.equipment-tuning-main-icon','.equipment-tuning-convert-inspect','.workbench-modal[data-modal-kind="equipment-inspector"]']))throw new Error('lazy split assets, load order, or tuning inspector skin missing');
}
function edge(){return[
  path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Microsoft','Edge','Application','msedge.exe'),
  path.join(process.env.ProgramFiles||'C:\\Program Files','Microsoft','Edge','Application','msedge.exe')
].find(fs.existsSync)}
function server(){return new Promise(resolve=>{const s=http.createServer((req,res)=>{const pathname=decodeURIComponent(url.parse(req.url).pathname);const file=path.normalize(path.join(WEB,pathname));const rel=path.relative(WEB,file);if(rel.startsWith('..')||path.isAbsolute(rel)){res.writeHead(403);res.end();return}fs.readFile(file,(err,data)=>{if(err){res.writeHead(404);res.end();return}const ext=path.extname(file);res.writeHead(200,{'Content-Type':ext==='.html'?'text/html; charset=utf-8':ext==='.css'?'text/css; charset=utf-8':ext==='.js'?'text/javascript; charset=utf-8':'application/octet-stream'});res.end(data)})});s.listen(0,'127.0.0.1',()=>resolve(s))})}
(async()=>{
  audit();
  if(!fs.existsSync(PLAYWRIGHT))throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
  const executablePath=edge();if(!executablePath)throw new Error('Microsoft Edge not found');
  const {chromium}=require(PLAYWRIGHT),s=await server(),browser=await chromium.launch({executablePath,headless:true});
  try{
    const viewports=[[1024,576],[1366,768],[1920,1080]];let baseline=null;
    for(const viewport of viewports){
      const page=await browser.newPage({viewport:{width:viewport[0],height:viewport[1]}}),errors=[],failed=[];
      page.on('pageerror',e=>errors.push(e.message));page.on('requestfailed',r=>failed.push(r.url()));
      await page.goto('http://127.0.0.1:'+s.address().port+'/modules/equipment-tuning/dev/harness.html',{waitUntil:'load'});
      await page.waitForFunction(()=>window.__qaDone===true,null,{timeout:20000});
      const result=await page.evaluate(()=>({result:window.__qaResult,error:window.__qaError}));
      if(result.error)throw new Error(viewport.join('x')+': '+result.error);
      if(errors.length)throw new Error(viewport.join('x')+' page errors: '+errors.join(' | '));
      if(failed.length)throw new Error(viewport.join('x')+' failed requests: '+failed.join(' | '));
      if(!result.result||result.result.passed!==result.result.total){const bad=result.result?result.result.checks.filter(c=>!c.ok):[];throw new Error(viewport.join('x')+' harness failed: '+JSON.stringify(bad))}
      baseline=result.result;await page.close();
    }
    console.log('Equipment tuning harness 3 viewports '+baseline.passed+'/'+baseline.total+' passed');
  }finally{await browser.close();await new Promise(r=>s.close(r))}
})().catch(error=>{console.error(error.stack||error);process.exit(1)});
