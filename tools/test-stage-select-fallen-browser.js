'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {startServer}=require('./lib/stage-select-dev-server');
const root=path.resolve(__dirname,'..'),out=path.join(root,'tmp/stage-select-fallen');
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
async function main(){
 fs.mkdirSync(out,{recursive:true});const {server,origin}=await startServer(path.join(root,'launcher/web'));
 const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true});
 const page=await browser.newPage({viewport:{width:1024,height:576}}),errors=[],report={scope:'Production panel and real GLBs with mock Host; no real save/game/WebView2 acceptance',checks:[]};
 page.on('pageerror',e=>errors.push(e.message));await page.route('https://cfn-fonts.local/**',r=>r.fulfill({status:204,body:''}));
 const ready=()=>page.waitForFunction(()=>StageSelectDiorama.stats().state==='ready'&&!StageSelectDiorama.stats().pending&&!StageSelectDiorama.stats().moving);
 const open=async()=>{await page.evaluate(()=>StageSelectHarnessHost.open({mode:'runtime',frameLabel:'基地车库'}));await ready();};
 try{
  await page.goto(origin+'/modules/stage-select/dev/harness.html?viewport=1024x576&frame='+encodeURIComponent('基地车库')+'&fixture=allUnlocked&player=1&review=P8-I1');await ready();
  report.initial=await page.evaluate(()=>StageSelectDiorama.stats());assert.equal(report.initial.calls,55);assert.equal(report.initial.indexCompatibility[0].outputChunks,5);assert.equal(report.initial.indexCompatibility[0].inputTriangles,report.initial.indexCompatibility[0].outputTriangles);assert.equal(Object.keys(report.initial.loadedHashes).length,2);assert.equal(await page.locator('.stage-select-stage-button').count(),19);
  await page.screenshot({path:path.join(out,'overview.png')});
  for(const index of [9,5,17,7,8]){
   const id='stage_10_'+index;await page.locator('[data-stage-id="'+id+'"].stage-select-stage-button > .stage-select-stage-name').click();await ready();
   const s=await page.evaluate(()=>StageSelectDiorama.stats());assert.equal(s.focusId,id);assert.equal(await page.locator('.stage-select-diorama-canvas').count(),1);
   if(index===9){assert.ok(s.selectedParts.some(p=>p.unit==='AS01'&&p.part==='assembly'));assert.ok(!s.selectedParts.some(p=>p.unit==='AS01'&&p.part==='residential'));await page.screenshot({path:path.join(out,'suppression-focus.png')});}
   if(index===5){assert.ok(s.selectedParts.some(p=>p.unit==='AS01'&&p.part==='residential'));assert.ok(!s.selectedParts.some(p=>p.unit==='AS01'&&p.part==='assembly'));}
   if(index===17)assert.ok(s.selectedParts.some(p=>p.unit==='BA01')&&s.selectedParts.some(p=>p.unit==='MK01')&&s.selectedParts.some(p=>p.unit==='RK01'));
   await page.getByRole('button',{name:'返回总览',exact:true}).click();await ready();
  }
  report.checks.push('AS01 event/residential partitions; campaign multi-area selection; deep-city and trial focus; one canvas');
  await page.getByRole('button',{name:'前往堕落城酒吧',exact:true}).hover();assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().cutaway),true);await page.mouse.move(1000,560);assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().cutaway),false);
  await page.getByRole('button',{name:'前往堕落城酒吧',exact:true}).click();await page.waitForFunction(()=>Panels.getActive()===null);
  const entry=await page.evaluate(()=>StageSelectHarnessHost.enterMessages.at(-1));assert.equal(entry.stageName,'外交-堕落城酒吧');assert.equal(entry.entryKind,'map');assert.ok(!entry.difficulty);report.checks.push('bar cutaway restores; diplomacy uses original entry command');
  await open();await page.getByRole('button',{name:'进入黑铁会总部',exact:true}).click();await ready();assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().frameLabel),'黑铁会总部');
  await open();await page.getByRole('button',{name:'进入试炼场深处',exact:true}).click();assert.equal(await page.locator('.stage-select-diorama-canvas').count(),0);report.checks.push('headquarters and 2D trial routing preserve actions and retire fallen canvas');
  report.cycles=[];for(let i=0;i<5;i++){await open();const s=await page.evaluate(()=>StageSelectDiorama.stats());report.cycles.push({geometries:s.geometries,textures:s.textures,calls:s.calls});await page.evaluate(()=>StageSelectHarnessHost.close());assert.equal(await page.locator('.stage-select-diorama-canvas').count(),0);}assert.equal(new Set(report.cycles.map(s=>JSON.stringify(s))).size,1);
  await open();await page.evaluate(()=>document.querySelector('.stage-select-diorama-canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext());await page.waitForFunction(()=>StageSelectDiorama.stats().state==='fallback');assert.equal(await page.locator('.stage-select-diorama-canvas').count(),0);assert.equal(await page.locator('.stage-select-stage-button').count(),19);await page.getByRole('button',{name:'重试',exact:true}).click();await ready();
  report.checks.push('five close/open cycles have stable resource counts; actual context loss falls back and retry restores');assert.deepEqual(errors,[]);report.pass=true;
 }catch(e){report.pass=false;report.error=e.stack;report.pageErrors=errors;process.exitCode=1;await page.screenshot({path:path.join(out,'failure.png')});}
 finally{await browser.close();server.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
