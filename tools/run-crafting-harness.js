#!/usr/bin/env node
'use strict';
const fs=require('fs'),http=require('http'),path=require('path'),url=require('url');
const ROOT=path.resolve(__dirname,'..'),WEB=path.join(ROOT,'launcher','web');
const PLAYWRIGHT=path.join(ROOT,'launcher','perf','node_modules','playwright');
function audit(){
  const panel=fs.readFileSync(path.join(WEB,'modules','crafting.js'),'utf8');
  const runtime=fs.readFileSync(path.join(WEB,'modules','crafting-runtime.js'),'utf8');
  const css=fs.readFileSync(path.join(WEB,'css','panels.css'),'utf8');
  const registry=fs.readFileSync(path.join(WEB,'modules','panels-lazy-registry.js'),'utf8');
  const inventoryWorkbench=fs.readFileSync(path.join(WEB,'modules','inventory-workbench.js'),'utf8');
  if(!panel.includes("new Workbench.DualPaneShell")||!panel.includes("leftLabel:'配方目录'")||!panel.includes("rightLabel:'合成详情'"))throw new Error('dual-pane contract missing');
  if(!panel.includes("request('preview'")||!panel.includes("request('commit'")||!panel.includes('expectedCraftToken'))throw new Error('preview/token/commit flow missing');
  if(/price\s*\*|smithLevel\s*\*/.test(panel))throw new Error('Web must not reproduce authoritative crafting formulas');
  if(!panel.includes('requiresReconcile')||!panel.includes('requestPreview();'))throw new Error('ambiguous write reconcile flow missing');
  if(!panel.includes('ItemFilter.FilterNavigator')||!panel.includes("visualStyle:'catalog'")||!panel.includes('craftCount:requestedCount')||!panel.includes("Panels.open('workbench'"))throw new Error('filter, batch, or organizer route missing');
  if(!panel.includes('canCraftOne === true')||!panel.includes('craftableOnly:_craftableOnly')||!panel.includes('crafting-craftable-toggle'))throw new Error('snapshot availability or craftable-only contract missing');
  if(!inventoryWorkbench.includes('function returnToPanel()')||!inventoryWorkbench.includes("target.panel !== 'crafting'"))throw new Error('battlebox return contract missing');
  if(!runtime.includes("domain:'crafting'")||!runtime.includes('entry.generation !== this._generation'))throw new Error('strict crafting mux missing');
  if(!registry.includes("registerLazy('crafting'")||!registry.includes("'modules/item-filter.js'")||!css.includes('.crafting-commit-btn')||!css.includes('.crafting-catalog-grid::-webkit-scrollbar'))throw new Error('lazy registry or crafting skin missing');
  if(!css.includes('.item-filter-catalog .item-filter-option')||!css.includes('grid-template-columns:minmax(0,1.55fr) 28px minmax(330px,.95fr)')||!css.includes('.crafting-recipe-card.craftable'))throw new Error('shared filter, 60:40 layout, or craftable marker skin missing');
  if(!css.includes('#panel-container[data-panel="crafting"] #panel-content')||!css.includes('#panel-container[data-panel="crafting"] #panel-backdrop'))throw new Error('crafting full-screen anchor contract missing');
}
function edge(){return[
  path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Microsoft','Edge','Application','msedge.exe'),
  path.join(process.env.ProgramFiles||'C:\\Program Files','Microsoft','Edge','Application','msedge.exe')
].find(fs.existsSync)}
function server(){return new Promise(resolve=>{const s=http.createServer((req,res)=>{const pathname=decodeURIComponent(url.parse(req.url).pathname);const file=path.normalize(path.join(WEB,pathname));const rel=path.relative(WEB,file);if(rel.startsWith('..')||path.isAbsolute(rel)){res.writeHead(403);res.end();return}fs.readFile(file,(err,data)=>{if(err){res.writeHead(404);res.end();return}const ext=path.extname(file);res.writeHead(200,{'Content-Type':ext==='.html'?'text/html; charset=utf-8':ext==='.css'?'text/css; charset=utf-8':ext==='.js'?'text/javascript; charset=utf-8':'application/octet-stream'});res.end(data)})});s.listen(0,'127.0.0.1',()=>resolve(s))})}
(async()=>{audit();if(!fs.existsSync(PLAYWRIGHT))throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');const executablePath=edge();if(!executablePath)throw new Error('Microsoft Edge not found');const {chromium}=require(PLAYWRIGHT),s=await server(),browser=await chromium.launch({executablePath,headless:true});try{const page=await browser.newPage({viewport:{width:1366,height:768}}),errors=[],failed=[];page.on('pageerror',e=>errors.push(e.message));page.on('requestfailed',r=>failed.push(r.url()));await page.goto('http://127.0.0.1:'+s.address().port+'/modules/crafting/dev/harness.html',{waitUntil:'load'});await page.waitForFunction(()=>window.__qaDone===true,null,{timeout:20000});const result=await page.evaluate(()=>({result:window.__qaResult,error:window.__qaError}));if(result.error)throw new Error(result.error);if(errors.length)throw new Error('page errors: '+errors.join(' | '));if(failed.length)throw new Error('failed requests: '+failed.join(' | '));if(!result.result||result.result.passed!==result.result.total){const bad=result.result?result.result.checks.filter(c=>!c.ok):[];throw new Error('harness failed: '+JSON.stringify(bad))}console.log('Crafting harness '+result.result.passed+'/'+result.result.total+' passed')}finally{await browser.close();await new Promise(r=>s.close(r))}})().catch(error=>{console.error(error.stack||error);process.exit(1)});
