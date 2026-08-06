#!/usr/bin/env node
'use strict';
const fs=require('fs'),http=require('http'),path=require('path'),url=require('url');
const {readCssBundle}=require('./lib/read-css-bundle.js');
const BrowserChildResourceClosure=require('./workbench-live-e2e/lib/browser-child-resource-closure.js');
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
  const decisionPresenter=readModule('equipment-tuning-decision-presenter.js');
  const render=readModule('equipment-tuning-render.js');
  const confirmation=readModule('equipment-tuning-confirmation.js');
  const interaction=readModule('equipment-tuning-interaction.js');
  const writeLifecycle=readModule('equipment-tuning-write-lifecycle.js');
  const loadoutLifecycle=readModule('equipment-tuning-loadout-lifecycle.js');
  const sourceMarker=readModule('equipment-tuning-source-marker.js');
  const inspectionViewport=readModule('workbench-inspection-viewport.js');
  const inspector=readModule('equipment-inspector.js');
  const tuningSource=[model,decisionPresenter,render,confirmation,interaction,writeLifecycle,loadoutLifecycle,sourceMarker,view].join('\n');
  const config=readModule('inventory-workbench-config.js');
  const preparationMenu=readModule('inventory-workbench-preparation-menu.js');
  const header=readModule('inventory-workbench-header.js');
  const ownedView=readModule('inventory-workbench-owned-view.js');
  const quickTransfer=readModule('inventory-workbench-quick-transfer.js');
  const tuningScope=readModule('inventory-tuning-scope.js');
  const featureLoader=readModule('inventory-workbench-feature-loader.js');
  const workbench=readModule('inventory-storage-workbench.js');
  const facade=readModule('inventory-workbench.js');
  const inventorySource=[config,preparationMenu,header,ownedView,quickTransfer,tuningScope,featureLoader,workbench,facade].join('\n');
  const registry=readModule('panels-lazy-registry.js');
  const registryWorkbench=between(registry,"Panels.registerLazy('workbench'","Panels.registerLazy('loot'");
  const tuningHarness=fs.readFileSync(path.join(WEB,'modules','equipment-tuning','dev','harness.html'),'utf8');
  const css=readCssBundle(path.join(WEB,'css','panels.css'),{rootDir:path.join(WEB,'css')});
  const infoProjection=between(render,'TuningView.prototype._renderHeader','TuningView.prototype._renderInstalledState');
  const operationTransition=between(view,'TuningView.prototype.setOperation','TuningView.prototype._selectReplacementCandidate');
  if(!hasAll(runtime,["domain:'equipment_tuning'",'panelInstanceId','viewSessionId',"'disconnected') return !!"]))throw new Error('strict tuning mux or definitive disconnect rule missing');
  if(!hasAll(runtime,['response_tuple_mismatch','pendingKinds:state.pendingKinds'])
      ||!hasAll(model,['function diagnosticAuthoritySourceKey','expectedLoadoutRevision','expectedLease'])
      ||!hasAll(interaction,["String(pendingKinds[pendingIndex]) !== 'tooltip'",'authorityPending'])
      ||!hasAll(view,["type:'debug'","scope:'equipment_tuning'",'preview_issued','preview_adopted','commit_issued','inventory_refresh_settled','reconcile_issued','reconcile_adopted'])
      ||!hasAll(tuningHarness,['tooltip-first response interleave preserves candidate activation and adopts the preview token','preview-first response interleave keeps the adopted preview when the late tooltip settles','commit and inventory refresh expose redacted current-build receipts','reconcile issued and adopted expose the exact unknown-write watermark without raw authority data']))throw new Error('tuning concurrency diagnostics or exact authority receipt gate missing');
  if(!hasAll(model,['function quickCommitEligible','enhance|convert|install_tier|install_mod|replace_mod|detach_mod|detach_all_mods'])
      ||!hasAll(view,['expectedTuningToken',"requestPreview('convert'","if (operation === 'replace_mod')"])
      ||!hasAll(render,["replacementMode ? 'replace_mod' : 'install_mod'","requestPreview('detach_all_mods'","_mux.request('tooltip'"]))throw new Error('seven-operation preview/token/tooltip flow missing');
  if(render.includes('item.displayName || item.name')
      ||render.includes('item.icon || item.name')
      ||render.includes('candidate.icon || candidate.itemName')
      ||render.includes('candidate.displayName || candidate.itemName')
      ||render.includes('materialIconHtml(material.itemName')
      ||render.includes('escapeHtml(material.itemName')
      ||render.includes('removedMods.join'))
      throw new Error('Web renderer must consume strict displayName/icon projections without internal-name fallback');
  if(!hasAll(model,['function modPresentationForItem','function equipmentDiff(left, right, modCandidates)','UNKNOWN_MOD_DISPLAY'])
      ||!hasAll(render,['var presentation = modPresentationForItem(','currentCandidates, itemName);','equipmentDiff(left, right, modCandidates)']))
      throw new Error('equipment mod rule arrays must render through the local canonical presentation map');
  if(/\(i\s*-\s*1\)\s*\*\s*\(i\s*-\s*1\)|smith.*0\.05/i.test(tuningSource))throw new Error('Web must not reproduce equipment formulas');
  if(!hasAll(tuningSource,['reconcileAfterCallId','_refreshRetryRequired'])
      ||!hasAll(writeLifecycle,['retryInventoryRefresh','this._completeWrite','authoritativeSnapshot'])
      ||!hasAll(workbench,['completeWrite:function(operation, needsRefresh, callback)','_coordinator.completeExternalWrite(operation, needsRefresh, callback)']))throw new Error('unknown-write reconcile or inventory refresh recovery missing');

  const buildProfile=between(workbench,'function buildProfileDOM','function switchView');
  const switchView=between(workbench,'function switchView','function finishViewSwitch');
  const open=between(workbench,'function activate','function openInventory');
  const openInventory=between(workbench,'function openInventory','function openHelp');
  const close=between(workbench,'function prepareExit','function prepareLeave');
  if(!hasAll(config,['function resolveView(initData)',"view === 'storage' || view === 'tuning' || view === 'build'",'function isViewAllowed'])
      ||!hasAll(header,['function TuningHeaderController','this._onSwitch',
        "self._view === 'tuning' ? 'storage' : 'tuning'"])
      ||!hasAll(workbench,['activate:activate','deactivate:cleanup','function maybeSelectFirstTunable'])
      ||/Panels\.register|InventoryWorkbenchHeader|new Workbench\.DualPaneShell/.test(workbench)
      ||!hasAll(header,['function createWorkbenchHeader','new TuningHeaderController'])
      ||!hasAll(facade,["Panels.register('workbench'",'new Workbench.DualPaneShell',
        'InventoryWorkbenchHeader.createWorkbenchHeader','function requestView(next, options)',
        'InventoryWorkbenchFeatureLoader.createPanelGate({',
        '_featureGate.run(next, function()',
        'InventoryStorageWorkbench.activate(','controllerPorts(),','initialView);',
        'InventoryStorageWorkbench.deactivate()',
        'function rebind(el, initData)'])
      ||!hasAll(buildProfile,['_viewMode = initialView',"if (_viewMode === 'tuning') _tuningView.openSession(_panelInstanceId)","_viewMode === 'tuning' ? _tuningView : _rightView"])
      ||!hasAll(switchView,['_tuningView.canClose()','_tuningView.detachSession','finishViewSwitch'])
      ||!hasAll(open,["requestedView === 'tuning' && !EquipmentTuningRuntime.safeToken(_panelInstanceId)",'buildProfileDOM(profileConfig, requestedView, context)'])
      ||!openInventory.includes('else maybeSelectFirstTunable();')
      ||!hasAll(close,['_tuningView.canClose()','_tuningView.detachSession']))throw new Error('workbench view/rebind/direct-open/detach gate contract missing');

  if(!hasAll(config,['function resolveProfile','function resolveLaunchContext','function ConfirmationPreference'])
      ||!hasAll(ownedView,['function createView','function createToolbar','new Components.OwnedInventoryPane'])
      ||!hasAll(quickTransfer,['function QuickTransferController','QuickTransferController.prototype.acceptClick','QuickTransferController.prototype.isBusy'])
      ||!hasAll(workbench,['EquipmentTuningConfirmation.shared.read()','InventoryWorkbenchOwnedView.createView','InventoryWorkbenchOwnedView.createToolbar','new InventoryWorkbenchQuickTransfer.QuickTransferController','_quickTransfer.acceptClick']))throw new Error('inventory workbench split-module composition missing');
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
  if(!hasAll(view,['model, decision presenter, renderer, confirmation, interaction, write lifecycle, loadout lifecycle, then view.',
        'WriteLifecycle.install(TuningView, Model)','LoadoutLifecycle.install(TuningView, Model)','DecisionPresenter.install(TuningView, Model)','Renderer.install(TuningView, Model)'])
      ||!render.includes('function install(TuningView, Model)')
      ||!decisionPresenter.includes('function install(TuningView, Model)')
      ||!writeLifecycle.includes('function install(TuningView, Model)')
      ||!loadoutLifecycle.includes('function install(TuningView, Model)')
      ||!interaction.includes('function interactionLockProjection')
      ||!sourceMarker.includes('function projectInventory'))
      throw new Error('tuning leaf composition or explicit browser load-order diagnosis missing');
  if(!hasAll(confirmation,['function ConfirmationPort','function disabledReason',
        '逐次确认','单件快捷','批量、连锁与卸下全部始终需要确认'])
      ||!hasAll(render,['new Components.ChoiceGroup','data-confirmation-mode',
        'equipment-tuning-confirmation-reason'])
      ||!hasAll(view,['Confirmation.project','this._confirmationPort.subscribe',
         'TuningView.prototype.openHelp','var quickIntentReady',
         'quickIntentReady && self._tryQuickCommit(intentKey)'])
      ||!hasAll(writeLifecycle,[
         "intent.operation === 'install_mod' ? 0 : 1",
         "this._setModIntentPhase('write_pending')"])
      ||render.includes('equipment-tuning-detach-selected')
      ||header.includes('confirmationRoot')
      ||workbench.includes('new InventoryWorkbenchConfig.ConfirmationPreference'))
      throw new Error('shared confirmation preference, ChoiceGroup, or help projection missing');
  if(!hasAll(render,['function focusRestoreVisible','this._renderFocusDeferred','root.addEventListener(\'pointerdown\''])
      ||!hasAll(tuningHarness,
        ['blank pointer intent cancels deferred focus','mod preview acknowledges the clicked intent in-frame',
         'editing draft preserves control identity, focus, value, and detail scroll',
        'aria-hidden or inert ancestors']))throw new Error('tuning focus ownership gates or counterexamples missing');
  if(!hasAll(model,['function sameLoadoutIdentity','left.sessionGeneration === right.sessionGeneration',
        'left.slotKey === right.slotKey'])
      ||!hasAll(loadoutLifecycle,["kind:'known'","kind:'unknown'",'Model.sameLoadoutIdentity(source, expectedSource)'])
      ||!hasAll(infoProjection,['equipment-tuning-info-panel','data-tuning-info-title',
        "info.textContent = '调制说明'","info.setAttribute('aria-expanded'",
        "close.setAttribute('data-tuning-focus-key', 'info:close')",
        'TuningView.prototype.consumeEscape','if (this._closeInfoPanel()) return true;',
        'if (this._replaceCandidateKey) return this._clearReplacementCandidate();'])
      ||/(?:aria-pressed|data-pinned|info:pin|_infoPanelPinned|_setInfoPinned)/.test(infoProjection)
      ||/_infoPanelPinned|_setInfoPinned/.test(view)
      ||!hasAll(operationTransition,['this._infoSubject = null','this.render({preserveScroll:false})'])
      ||!hasAll(css,['font:700 11px/1 "Microsoft YaHei",sans-serif',
        '.equipment-tuning-detail {','.equipment-tuning-commit-bar {',
        '[data-title]:focus-visible::after']))throw new Error('loadout identity or tuning usability debt gate missing');
  const eagerWorkbenchClosure=[
    "'modules/item-filter.js'",
    "'modules/inventory-runtime.js'",
    "'modules/inventory-ui.js'",
    "'modules/inventory-workbench-config.js'",
    "'modules/inventory-workbench-preparation-menu.js'",
    "'modules/inventory-workbench-navigation.js'",
    "'modules/inventory-workbench-header.js'",
    "'modules/inventory-workbench-quick-transfer.js'",
    "'modules/inventory-workbench-owned-view.js'",
    "'modules/inventory-workbench-feature-loader.js'",
    "'modules/inventory-storage-workbench.js'",
    "'modules/inventory-workbench.js'"
  ];
  const tuningFeatureClosure=[
    "'modules/asset-timeline.js'",
    "'modules/dressup-doll-renderer.js'",
    "'modules/workbench-inspection-viewport.js'",
    "'modules/equipment-inspector.js'",
    "'modules/equipment-tuning-runtime.js'",
    "'modules/equipment-tuning-model.js'",
    "'modules/equipment-tuning-decision-presenter.js'",
    "'modules/equipment-tuning-render.js'",
    "'modules/equipment-tuning-confirmation.js'",
    "'modules/equipment-tuning-interaction.js'",
    "'modules/equipment-tuning-write-lifecycle.js'",
    "'modules/equipment-tuning-loadout-lifecycle.js'",
    "'modules/equipment-tuning-source-marker.js'",
    "'modules/equipment-tuning-view.js'",
    "'modules/inventory-tuning-scope.js'"
  ];
  const buildFeatureClosure=[
    "'modules/character-build/character-build-mutation.js'",
    "'modules/character-build/character-build-session-contract.js'",
    "'modules/character-build-session.js'",
    "'modules/character-build/character-build-action-view.js'",
    "'modules/character-build/character-build-tuning-adapter.js'",
    "'modules/character-build/character-build-candidate-tooltip.js'",
    "'modules/character-build/character-build-candidate-state.js'",
    "'modules/character-build/character-build-facet-counts.js'",
    "'modules/character-build/character-build-stats-view.js'",
    "'modules/character-build/character-build-doll-preview.js'",
    "'modules/character-build/character-build-template.js'",
    "'modules/character-build/character-build-loadout-presenter.js'",
    "'modules/character-build/character-build-candidate-pane.js'",
    "'modules/character-build-view.js'",
    "'modules/character-build/character-build-tuning.js'",
    "'modules/character-build/character-build-slot-transition.js'",
    "'modules/character-build/character-build-pose.js'",
    "'modules/character-build/character-build-candidate-eligibility.js'",
    "'modules/character-build/character-build-projection.js'",
    "'modules/character-build/character-build-transport.js'",
    "'modules/character-build/character-build-candidate-channel.js'",
    "'modules/character-build.js'"
  ];
  if(!inOrder(registryWorkbench,eagerWorkbenchClosure)
      ||tuningFeatureClosure.concat(buildFeatureClosure).some(token=>registryWorkbench.includes(token))
      ||!inOrder(featureLoader,tuningFeatureClosure)
      ||!inOrder(featureLoader,buildFeatureClosure)
      ||!hasAll(css,['.equipment-tuning-commit','.equipment-tuning-main-icon','.equipment-tuning-convert-inspect','.workbench-modal[data-modal-kind="equipment-inspector"]']))throw new Error('lazy split assets, load order, or tuning inspector skin missing');
}
function edge(){return[
  path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Microsoft','Edge','Application','msedge.exe'),
  path.join(process.env.ProgramFiles||'C:\\Program Files','Microsoft','Edge','Application','msedge.exe')
].find(fs.existsSync)}
function server(resourceLedger){return new Promise(resolve=>{const s=http.createServer((req,res)=>{const pathname=decodeURIComponent(url.parse(req.url).pathname);const file=path.normalize(path.join(WEB,pathname));const rel=path.relative(WEB,file);if(rel.startsWith('..')||path.isAbsolute(rel)){res.writeHead(403);res.end();return}const occurrence=resourceLedger.begin(req.url,file);fs.readFile(file,(err,data)=>{if(err){occurrence.failure('read_failed');res.writeHead(404);res.end();return}const ext=path.extname(file);const mime=ext==='.html'?'text/html; charset=utf-8':ext==='.css'?'text/css; charset=utf-8':ext==='.js'?'text/javascript; charset=utf-8':'application/octet-stream';occurrence.success(data,mime);res.writeHead(200,{'Content-Type':mime});res.end(data)})});s.listen(0,'127.0.0.1',()=>resolve(s))})}
function closeServer(value){return new Promise((resolve,reject)=>value.close(error=>error?reject(error):resolve()))}
async function probeAmbientMotion(page){
  async function snapshot(){
    return page.evaluate(()=>{
      let fixture=document.getElementById('equipment-tuning-g4-motion-fixture');
      if(!fixture){
        fixture=document.createElement('div');
        fixture.id='equipment-tuning-g4-motion-fixture';
        fixture.className='workbench-shell';
        fixture.setAttribute('data-profile','library-decision');
        fixture.style.cssText='position:fixed;left:0;top:0;width:180px;height:100px;z-index:9999';
        fixture.innerHTML='<div class="equipment-tuning-stone-core"></div>';
        document.body.appendChild(fixture);
      }
      const core=fixture.querySelector('.equipment-tuning-stone-core');
      const style=getComputedStyle(core,'::after'),rect=core.getBoundingClientRect();
      return{
        reduced:matchMedia('(prefers-reduced-motion: reduce)').matches,
        animationName:style.animationName,
        animationDuration:style.animationDuration,
        animationTimingFunction:style.animationTimingFunction,
        animationIterationCount:style.animationIterationCount,
        opacity:Number(style.opacity),
        animationCount:typeof core.getAnimations==='function'?core.getAnimations({subtree:true}).length:0,
        width:rect.width,height:rect.height
      };
    });
  }
  await page.emulateMedia({reducedMotion:'no-preference'});const normal=await snapshot();
  await page.waitForTimeout(30);
  await page.emulateMedia({reducedMotion:'reduce'});const reduced=await snapshot();
  await page.evaluate(()=>{const fixture=document.getElementById('equipment-tuning-g4-motion-fixture');if(fixture)fixture.remove()});
  await page.emulateMedia({reducedMotion:'no-preference'});
  return{normal,reduced,pass:normal.reduced===false
    &&normal.animationName==='equipment-tuning-core-pulse'
    &&normal.animationDuration==='1.8s'
    &&normal.animationTimingFunction==='cubic-bezier(0.2, 0.8, 0.25, 1)'
    &&normal.animationIterationCount==='infinite'&&normal.animationCount>0
    &&normal.width===56&&normal.height===56&&normal.opacity>0
    &&reduced.reduced===true&&reduced.animationName==='none'
    &&reduced.animationDuration==='0s'&&reduced.animationCount===0
    &&Math.abs(reduced.opacity-.55)<.001&&reduced.width===56&&reduced.height===56};
}
async function run(){
  audit();
  if(!fs.existsSync(PLAYWRIGHT))throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
  const executablePath=edge();if(!executablePath)throw new Error('Microsoft Edge not found');
  const {chromium}=require(PLAYWRIGHT),resourceLedger=BrowserChildResourceClosure.createServedResourceLedger({root:WEB});
  const s=await server(resourceLedger);let browser=null;let output=null;
  try{
    browser=await chromium.launch({executablePath,headless:true});
    const viewports=[[1024,576],[1366,768],[1920,1080]],runs=[];let motionProof=null;
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
      const checks=result.result.checks||[],names=checks.map(check=>check&&check.name);
      if(checks.length!==result.result.total||checks.some(check=>!check||check.ok!==true)
          ||names.some(name=>typeof name!=='string'||!name)||new Set(names).size!==names.length)
        throw new Error(viewport.join('x')+' harness check identity closure failed');
      if(!motionProof){motionProof=await probeAmbientMotion(page);if(!motionProof.pass)throw new Error('ambient normal/reduced motion contract failed: '+JSON.stringify(motionProof))}
      runs.push({viewport:{width:viewport[0],height:viewport[1]},total:result.result.total,
        passed:result.result.passed,checks:checks.map(check=>({name:check.name,ok:check.ok,detail:check.detail}))});
      await page.close();
    }
    output={mode:'full',viewports:viewports.map(viewport=>({width:viewport[0],height:viewport[1]})),
      runs,motionProof,executablePath};
  }finally{if(browser)await browser.close();await closeServer(s)}
  output.servedResourceLedger=resourceLedger.snapshot();
  return output;
}
module.exports={run};
if(require.main===module){run().then(output=>process.stdout.write(JSON.stringify(output,null,2)+'\n'))
  .catch(error=>{console.error(error.stack||error);process.exitCode=1})}
