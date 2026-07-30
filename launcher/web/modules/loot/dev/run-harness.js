#!/usr/bin/env node
'use strict';
const fs=require('fs'),http=require('http'),path=require('path'),url=require('url');
require('./test-player-copy.js').assertPlayerCopy();
const ROOT=path.resolve(__dirname,'../../../../..');
const WEB=path.join(ROOT,'launcher','web');
const PLAYWRIGHT=path.join(ROOT,'launcher','perf','node_modules','playwright');
function edge(){return[
  path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Microsoft','Edge','Application','msedge.exe'),
  path.join(process.env.ProgramFiles||'C:\\Program Files','Microsoft','Edge','Application','msedge.exe')
].find(fs.existsSync)}
function server(){return new Promise(resolve=>{const instance=http.createServer((request,response)=>{
  const pathname=decodeURIComponent(url.parse(request.url).pathname),file=path.normalize(path.join(WEB,pathname)),relative=path.relative(WEB,file);
  if(relative.startsWith('..')||path.isAbsolute(relative)){response.writeHead(403);response.end();return}
  fs.readFile(file,(error,data)=>{if(error){response.writeHead(404);response.end();return}
    const ext=path.extname(file);response.writeHead(200,{'Content-Type':ext==='.html'?'text/html; charset=utf-8':ext==='.css'?'text/css; charset=utf-8':ext==='.js'?'text/javascript; charset=utf-8':'application/octet-stream'});response.end(data)})
});instance.listen(0,'127.0.0.1',()=>resolve(instance))})}
(async()=>{
  if(!fs.existsSync(PLAYWRIGHT))throw new Error('Missing launcher/perf Playwright installation');
  const executablePath=edge();if(!executablePath)throw new Error('Microsoft Edge not found');
  const {chromium}=require(PLAYWRIGHT),instance=await server(),browser=await chromium.launch({executablePath,headless:true});
  try{
    async function runPage(file,label,viewport){
      const page=await browser.newPage({viewport:viewport||{width:1366,height:768}}),errors=[],failed=[];
      page.on('pageerror',error=>errors.push(error.message));page.on('requestfailed',request=>failed.push(request.url()));
      try{
        await page.goto('http://127.0.0.1:'+instance.address().port+'/modules/loot/dev/'+file,{waitUntil:'load'});
        await page.waitForFunction(()=>window.__qaDone===true,null,{timeout:20000});
        const value=await page.evaluate(()=>({result:window.__qaResult,error:window.__qaError}));
        if(value.error)throw new Error(value.error);if(errors.length)throw new Error('page errors: '+errors.join(' | '));
        if(failed.length)throw new Error('failed requests: '+failed.join(' | '));
        if(!value.result||value.result.passed!==value.result.total)throw new Error('failed checks: '+JSON.stringify(value.result&&value.result.checks.filter(check=>!check.ok)));
        console.log(label+' '+value.result.passed+'/'+value.result.total+' passed');
      }finally{await page.close()}
    }
    await runPage('harness.html','Loot browser harness',{width:1024,height:576});
    await runPage('panels-lazy-cancel-harness.html','Loot lazy-cancel harness');
  }finally{
    await browser.close();
    // Edge may leave an HTTP keep-alive socket briefly open after the page assertions finish.
    // Close those test-only connections before awaiting server.close(), otherwise a green
    // harness can hang until the outer process timeout and be misreported as a test failure.
    if(typeof instance.closeAllConnections==='function')instance.closeAllConnections();
    await new Promise(resolve=>instance.close(resolve));
  }
})().catch(error=>{console.error(error.stack||error);process.exit(1)});
