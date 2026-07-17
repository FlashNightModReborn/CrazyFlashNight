#!/usr/bin/env node
'use strict';
const fs=require('fs'),http=require('http'),path=require('path'),url=require('url');
const ROOT=path.resolve(__dirname,'..'),WEB=path.join(ROOT,'launcher','web');
const PLAYWRIGHT=path.join(ROOT,'launcher','perf','node_modules','playwright');

function audit(){
  const runtime=fs.readFileSync(path.join(WEB,'modules','equipment-tuning-runtime.js'),'utf8');
  const inventoryRuntime=fs.readFileSync(path.join(WEB,'modules','inventory-runtime.js'),'utf8');
  const view=fs.readFileSync(path.join(WEB,'modules','equipment-tuning-view.js'),'utf8');
  const workbench=fs.readFileSync(path.join(WEB,'modules','inventory-workbench.js'),'utf8');
  const registry=fs.readFileSync(path.join(WEB,'modules','panels-lazy-registry.js'),'utf8');
  const css=fs.readFileSync(path.join(WEB,'css','panels.css'),'utf8');
  if(!runtime.includes("domain:'equipment_tuning'")||!runtime.includes('panelInstanceId')||!runtime.includes('viewSessionId')||!runtime.includes("'disconnected') return !!"))throw new Error('strict tuning mux or definitive disconnect rule missing');
  if(!view.includes('expectedTuningToken')||!view.includes("requestPreview('convert'")||!view.includes("requestPreview('detach_all_mods'")||!view.includes("'replace_mod'")||!view.includes("_mux.request('tooltip'"))throw new Error('seven-operation preview/token/tooltip flow missing');
  if(/\(i\s*-\s*1\)\s*\*\s*\(i\s*-\s*1\)|smith.*0\.05/i.test(view))throw new Error('Web must not reproduce equipment formulas');
  if(!view.includes('reconcileAfterCallId')||!view.includes('_refreshRetryRequired')||!view.includes('retryInventoryRefresh')||!view.includes('completeExternalWrite')&&!workbench.includes('completeExternalWrite'))throw new Error('unknown-write reconcile or inventory refresh recovery missing');
  if(!workbench.includes('onRebind: onRebind')||!workbench.includes("switchWorkbenchView(_viewMode === 'tuning'")||!workbench.includes('maybeSelectFirstTunable')||!workbench.includes('_tuningView.canClose()')||!workbench.includes('_tuningView.detachSession'))throw new Error('workbench view/rebind/direct-open/detach gate contract missing');
  if(!inventoryRuntime.includes('readProjection')||!workbench.includes('_coordinator.readProjection')||!workbench.includes('loadTuningConversionCandidates')||!view.includes('selectConversionTarget')||!view.includes('equipment-tuning-conversion-candidates'))throw new Error('isolated right-pane conversion projection missing');
  if(workbench.includes('syncTuningConversionFilter')||workbench.includes('_conversionFilterRestore')||view.includes('syncConversionFilter')||view.includes('_conversionFilterActive'))throw new Error('legacy conversion mutation of visible bag filter remains');
  if(!registry.includes("'modules/equipment-tuning-runtime.js'")||!registry.includes("'modules/equipment-tuning-view.js'")||!css.includes('.equipment-tuning-commit'))throw new Error('lazy assets or tuning skin missing');
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
