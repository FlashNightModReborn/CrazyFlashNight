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
  const tuningSource=[model,render,view].join('\n');
  const config=readModule('inventory-workbench-config.js');
  const header=readModule('inventory-workbench-header.js');
  const ownedView=readModule('inventory-workbench-owned-view.js');
  const quickTransfer=readModule('inventory-workbench-quick-transfer.js');
  const workbench=readModule('inventory-workbench.js');
  const inventorySource=[config,header,ownedView,quickTransfer,workbench].join('\n');
  const registry=readModule('panels-lazy-registry.js');
  const registryWorkbench=between(registry,"Panels.registerLazy('workbench'","Panels.registerLazy('npcshop'");
  const css=readCssBundle(path.join(WEB,'css','panels.css'),{rootDir:path.join(WEB,'css')});
  if(!hasAll(runtime,["domain:'equipment_tuning'",'panelInstanceId','viewSessionId',"'disconnected') return !!"]))throw new Error('strict tuning mux or definitive disconnect rule missing');
  if(!hasAll(model,['function quickCommitEligible','enhance|convert|install_tier|install_mod|replace_mod|detach_mod|detach_all_mods'])
      ||!hasAll(view,['expectedTuningToken',"requestPreview('convert'","if (operation === 'replace_mod')"])
      ||!hasAll(render,["replacementMode ? 'replace_mod' : 'install_mod'","requestPreview('detach_all_mods'","_mux.request('tooltip'"]))throw new Error('seven-operation preview/token/tooltip flow missing');
  if(/\(i\s*-\s*1\)\s*\*\s*\(i\s*-\s*1\)|smith.*0\.05/i.test(tuningSource))throw new Error('Web must not reproduce equipment formulas');
  if(!hasAll(view,['reconcileAfterCallId','_refreshRetryRequired','retryInventoryRefresh','this._completeWrite'])
      ||!hasAll(workbench,['completeWrite:function(operation, needsRefresh, callback)','_coordinator.completeExternalWrite(operation, needsRefresh, callback)']))throw new Error('unknown-write reconcile or inventory refresh recovery missing');

  const buildProfile=between(workbench,'function buildProfileDOM','function switchWorkbenchView');
  const switchView=between(workbench,'function switchWorkbenchView','function finishWorkbenchViewSwitch');
  const open=between(workbench,'function onOpen','function openInventory');
  const openInventory=between(workbench,'function openInventory','function openTuningHelp');
  const rebind=between(workbench,'function onRebind','function cleanup');
  const close=between(workbench,'function closePanel','function finishClosePanel');
  if(!hasAll(config,['function resolveView(initData)',"view === 'storage' || view === 'tuning'"])
      ||!hasAll(header,['function TuningHeaderController','this._onSwitch',"self._onSwitch(self._view === 'tuning' ? 'storage' : 'tuning')"])
      ||!hasAll(workbench,['onRebind: onRebind','function maybeSelectFirstTunable'])
      ||!hasAll(buildProfile,['new InventoryWorkbenchHeader.TuningHeaderController','onSwitch:switchWorkbenchView','_viewMode = initialView',"if (_viewMode === 'tuning') _tuningView.openSession(_panelInstanceId)","_viewMode === 'tuning' ? _tuningView : _rightView"])
      ||!hasAll(switchView,['_tuningView.canClose()','_tuningView.detachSession','finishWorkbenchViewSwitch'])
      ||!hasAll(open,['InventoryWorkbenchConfig.resolveView(initData)',"requestedView === 'tuning' && !EquipmentTuningRuntime.safeToken(_panelInstanceId)",'buildProfileDOM(profileConfig, requestedView)'])
      ||!openInventory.includes('else maybeSelectFirstTunable();')
      ||!hasAll(rebind,['cleanup();','onOpen(el, initData || {});'])
      ||!hasAll(close,['_tuningView.canClose()','_tuningView.detachSession']))throw new Error('workbench view/rebind/direct-open/detach gate contract missing');

  if(!hasAll(config,['function resolveProfile','function resolveReturnTarget','function ConfirmationPreference'])
      ||!hasAll(ownedView,['function createView','function createToolbar','new Components.OwnedInventoryPane'])
      ||!hasAll(quickTransfer,['function QuickTransferController','QuickTransferController.prototype.acceptClick','QuickTransferController.prototype.isBusy'])
      ||!hasAll(workbench,['new InventoryWorkbenchConfig.ConfirmationPreference','InventoryWorkbenchOwnedView.createView','InventoryWorkbenchOwnedView.createToolbar','new InventoryWorkbenchQuickTransfer.QuickTransferController','_quickTransfer.acceptClick']))throw new Error('inventory workbench split-module composition missing');
  if(!inventoryRuntime.includes('readProjection')||!hasAll(workbench,['_coordinator.readProjection','loadTuningConversionCandidates','loadConversionCandidates:loadTuningConversionCandidates'])
      ||!view.includes('selectConversionTarget')||!render.includes('equipment-tuning-conversion-candidates'))throw new Error('isolated right-pane conversion projection missing');
  if(inventorySource.includes('syncTuningConversionFilter')||inventorySource.includes('_conversionFilterRestore')
      ||tuningSource.includes('syncConversionFilter')||tuningSource.includes('_conversionFilterActive'))throw new Error('legacy conversion mutation of visible bag filter remains');
  if(!hasAll(view,['EquipmentTuningView load order: item-filter.js, equipment-tuning-model.js, equipment-tuning-render.js, then equipment-tuning-view.js.','Renderer.install(TuningView, Model)'])
      ||!render.includes('function install(TuningView, Model)'))throw new Error('tuning model/render split or explicit browser load-order diagnosis missing');
  if(!inOrder(registryWorkbench,["'modules/item-filter.js'","'modules/inventory-runtime.js'","'modules/inventory-ui.js'","'modules/equipment-tuning-runtime.js'","'modules/equipment-tuning-model.js'","'modules/equipment-tuning-render.js'","'modules/equipment-tuning-view.js'","'modules/inventory-workbench-config.js'","'modules/inventory-workbench-header.js'","'modules/inventory-workbench-quick-transfer.js'","'modules/inventory-workbench-owned-view.js'","'modules/inventory-workbench.js'"])
      ||!css.includes('.equipment-tuning-commit'))throw new Error('lazy split assets, load order, or tuning skin missing');
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
