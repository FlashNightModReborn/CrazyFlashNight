'use strict';
const {chromium}=require('../../launcher/perf/node_modules/playwright');
const path=require('path'),assert=require('assert');
(async()=>{
 const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true});
 try {
  for(const viewport of [{width:1024,height:576},{width:1600,height:900},{width:2560,height:1440}]){
   const page=await browser.newPage({viewport,deviceScaleFactor:1.5}),errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.goto('http://127.0.0.1:18765/');await page.frameLocator('iframe').locator('.map-authoring-target.is-selected').waitFor();
   const box=await page.locator('iframe').boundingBox();assert(box.width>viewport.width*.7);
   const library=await page.locator('.mw-library').evaluate(n=>({width:n.clientWidth,scroll:n.scrollWidth}));assert(library.scroll<=library.width+1);
   await page.getByRole('button',{name:'保存到项目',exact:true}).scrollIntoViewIfNeeded();
   await page.getByRole('button',{name:'专注画布',exact:true}).click();assert((await page.locator('iframe').boundingBox()).width>viewport.width*.95);
   assert.deepEqual(errors,[]);console.log('PASS '+viewport.width+'x'+viewport.height+' DPR1.5; iframe '+Math.round(box.width)+'x'+Math.round(box.height)+'; no sidebar horizontal overflow');
   await page.close();
  }
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
