'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {startServer}=require('./lib/stage-select-dev-server');
const root=path.resolve(__dirname,'..'),out=path.join(root,'tmp/stage-select-blackiron');
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
async function main(){
 fs.mkdirSync(out,{recursive:true});const {server,origin}=await startServer(path.join(root,'launcher/web'));
 const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true});
 const page=await browser.newPage({viewport:{width:1024,height:576}}),errors=[],report={scope:'Production feature, real GLBs in Edge, mock Host. Not real save/WebView2/game entry acceptance.',checks:[]};
 page.on('pageerror',e=>errors.push(e.message));await page.route('https://cfn-fonts.local/**',r=>r.fulfill({status:204,body:''}));
 const url=origin+'/modules/stage-select/dev/harness.html?viewport=1024x576&fixture=allUnlocked&player=1&frame='+encodeURIComponent('黑铁会总部');
 const ready=()=>page.waitForFunction(()=>StageSelectDiorama.stats().state==='ready'&&!StageSelectDiorama.stats().pending&&!StageSelectDiorama.stats().moving);
 const open=async(frame='黑铁会总部')=>{await page.evaluate(frame=>StageSelectHarnessHost.open({mode:'runtime',frameLabel:frame}),frame);await ready();};
 const select=async id=>{await page.locator('.stage-select-stage-button[data-stage-id="'+id+'"] > .stage-select-stage-name').click();await ready();};
 const associations=()=>page.evaluate(()=>{
  const nodes=[...document.querySelectorAll('.stage-select-stage-button')],labels=nodes.map(n=>({id:n.dataset.stageId,r:n.querySelector('.stage-select-stage-name').getBoundingClientRect()})),paths=[],failures=[];
  for(const node of nodes){
   const line=node.querySelector('.stage-select-leader-ink'),length=line.getTotalLength(),matrix=line.getScreenCTM();
   if(parseFloat(getComputedStyle(line).strokeWidth)<2.5)failures.push(node.dataset.stageId+' thin line');
   const points=[0,length].map(t=>{const p=line.getPointAtLength(t);return {x:matrix.a*p.x+matrix.c*p.y+matrix.e,y:matrix.b*p.x+matrix.d*p.y+matrix.f};});
   paths.push({id:node.dataset.stageId,points});
   for(let t=0;t<=length;t+=1){const p=line.getPointAtLength(t),x=matrix.a*p.x+matrix.c*p.y+matrix.e,y=matrix.b*p.x+matrix.d*p.y+matrix.f;
    for(const label of labels)if(label.id!==node.dataset.stageId&&x>label.r.left-1&&x<label.r.right+1&&y>label.r.top-1&&y<label.r.bottom+1)failures.push(node.dataset.stageId+' crosses '+label.id);
   }
  }
  function side(a,b,c){return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);}
  for(let i=0;i<paths.length;i++)for(let j=i+1;j<paths.length;j++){
   const [a,b]=paths[i].points,[c,d]=paths[j].points;
   if(side(a,b,c)*side(a,b,d)<0&&side(c,d,a)*side(c,d,b)<0)failures.push(paths[i].id+' line intersects '+paths[j].id);
  }
  return {failures:[...new Set(failures)],labels:labels.length,lines:paths.length};
 });
 try{
  await page.goto(url);await ready();report.initial=await page.evaluate(()=>StageSelectDiorama.stats());
  assert.equal(report.initial.frameLabel,'黑铁会总部');assert.ok(report.initial.triangles>50000&&report.initial.calls<60);assert.equal(report.initial.width,1024);
  const order=await page.locator('.stage-select-stage-button').evaluateAll(es=>es.map(e=>e.dataset.stageId));assert.deepEqual(order,['stage_18_1','stage_18_0',...Array.from({length:9},(_,i)=>'stage_18_'+(i+2))]);
  report.checks.push('real HQ assets, fixed resolution, mainline display order and unchanged stable IDs');
  const layout=await page.evaluate(()=>{
   const nodes=[...document.querySelectorAll('.stage-select-stage-button')],boxes=[],hits=[];
   for(const node of nodes)for(const selector of ['.stage-select-stage-name','.stage-select-hit-zone']){
    const e=node.querySelector(selector),r=e.getBoundingClientRect();boxes.push({id:node.dataset.stageId,selector,x:r.x,y:r.y,w:r.width,h:r.height});
    if(!node.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)))hits.push(node.dataset.stageId+selector);
   }
   const overlap=[];for(let i=0;i<boxes.length;i++)for(let j=i+1;j<boxes.length;j++){const a=boxes[i],b=boxes[j];if(a.id!==b.id&&a.x<b.x+b.w&&b.x<a.x+a.w&&a.y<b.y+b.h&&b.y<a.y+a.h)overlap.push([a.id,b.id]);}
   return {hits,overlap,outside:boxes.filter(r=>r.x<0||r.y<0||r.x+r.w>innerWidth||r.y+r.h>innerHeight),boxes};
  });report.layout=layout;assert.deepEqual(layout.hits,[]);assert.deepEqual(layout.overlap,[]);assert.deepEqual(layout.outside,[]);
  await page.screenshot({path:path.join(out,'hq-overview.png')});report.checks.push('all 22 name/marker centers clickable without overlap or overflow at 1024x576');
  report.associations=await associations();assert.deepEqual(report.associations.failures,[]);
  assert.equal(await page.getByRole('button',{name:'黑铁会翅虎堂外围',exact:true}).count(),1);
  assert.equal(await page.getByRole('button',{name:'前往黑铁会修炼场',exact:true}).count(),1);
  report.checks.push('thick leaders avoid foreign labels and each other; compact captions preserve full accessible names');
  if(process.argv.includes('--layout-only')){
   if(await page.getByRole('button',{name:'原镜头',exact:true}).count()){
    await page.getByRole('button',{name:'原镜头',exact:true}).click();await ready();
    report.originalView=await page.evaluate(()=>StageSelectDiorama.stats());assert.equal(report.originalView.presentation,'original');
    report.originalAssociations=await associations();assert.deepEqual(report.originalAssociations.failures,[]);
    const failures=await page.evaluate(()=>{
     const boxes=[...document.querySelectorAll('.stage-select-stage-button > .stage-select-stage-name,.stage-select-stage-button > .stage-select-hit-zone')].map(e=>({id:e.parentElement.dataset.stageId,r:e.getBoundingClientRect(),e}));
     const bad=[];for(let i=0;i<boxes.length;i++){const a=boxes[i],r=a.r;if(!a.e.parentElement.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)))bad.push(a.id+' covered');for(let j=i+1;j<boxes.length;j++){const b=boxes[j];if(a.id!==b.id&&r.left<b.r.right&&b.r.left<r.right&&r.top<b.r.bottom&&b.r.top<r.bottom)bad.push(a.id+' / '+b.id);}}
     return bad;
    });assert.deepEqual(failures,[]);
    await page.screenshot({path:path.join(out,'hq-original-with-environment.png')});
    await page.getByRole('checkbox',{name:'周边环境',exact:true}).uncheck();
    report.environmentOff=await page.evaluate(()=>StageSelectDiorama.stats());assert.equal(report.environmentOff.environment,false);
    assert.equal(report.environmentOff.calls,report.originalView.calls-report.originalView.environmentDrawCalls);
    await page.screenshot({path:path.join(out,'hq-original-without-environment.png')});
    await page.getByRole('checkbox',{name:'周边环境',exact:true}).check();
    assert.equal(await page.getByRole('checkbox',{name:'方圆纹样',exact:true}).count(),0);
    await page.getByRole('button',{name:'正面俯视',exact:true}).click();await ready();
    assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().presentation),'front');
    report.frontAssociations=await associations();assert.deepEqual(report.frontAssociations.failures,[]);
    await page.locator('[data-stage-id="stage_18_8"] > .stage-select-stage-name').click();await ready();
    assert.equal(await page.locator('.stage-select-diorama-comparison').isVisible(),false);
    await page.getByRole('button',{name:'返回总览',exact:true}).click();await ready();
    assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().presentation),'front');
    report.checks.push('camera layouts hit correctly; exterior toggles independently; removed ritual overlay stays absent; focus returns to selected overview');
   }
   report.pass=true;return;
  }
  for(const id of order.filter(id=>id!=='stage_18_10')){
   await select(id);assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().focusId),id);
   assert.equal(await page.locator('.stage-focus-viewport canvas').count(),1);assert.equal(await page.locator('.stage-select-diorama-canvas').count(),1);
   if(id==='stage_18_8')await page.screenshot({path:path.join(out,'hq-focus.png')});
   await page.getByRole('button',{name:'返回总览',exact:true}).click();await ready();
  }
  report.checks.push('ten ordinary/event entries focus their own selection mesh, reuse one canvas and return to overview');
  await select('stage_18_2');await page.locator('#stage-focus-enter').click();await page.waitForFunction(()=>Panels.getActive()===null);
  assert.equal(await page.evaluate(()=>StageSelectHarnessHost.enterMessages.at(-1).stageName),'黑铁会翅虎堂内部');assert.equal(await page.evaluate(()=>StageSelectHarnessHost.enterMessages.at(-1).difficulty),'简单');
  await open();await page.locator('[data-stage-id="stage_18_10"] > .stage-select-stage-name').click();await page.waitForFunction(()=>Panels.getActive()===null);
  const jump=await page.evaluate(()=>StageSelectHarnessHost.enterMessages.at(-1));report.diplomacy=jump;assert.equal(jump.stageName,'外交-黑铁会修炼场');assert.equal(jump.entryKind,'map');assert.ok(!jump.difficulty);
  report.checks.push('ordinary and diplomacy use original Host protocol/Chinese difficulty; no demo-state adapter');
  await open();await page.evaluate(()=>StageSelectPanel._debugApplySnapshot({unlockedStages:['黑铁会总部边缘'],stageDetails:{'黑铁会总堂':{unlocked:false,lockReason:'接收端锁定检查'}}}));
  await select('stage_18_8');assert.equal(await page.locator('#stage-focus-enter').isVisible(),false);assert.match(await page.locator('#stage-select-inspector-lock').textContent(),/接收端锁定检查/);
  await page.getByRole('button',{name:'返回总览',exact:true}).click();
  await page.evaluate(()=>StageSelectRenderer.setFrame('基地门口','qa'));await ready();assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().frameLabel),'基地门口');assert.ok((await page.evaluate(()=>StageSelectDiorama.stats().triangles))>150000);
  await page.evaluate(()=>StageSelectRenderer.setFrame('黑铁会总部','qa'));await ready();assert.equal(await page.locator('.stage-select-diorama-canvas').count(),1);
  report.checks.push('authoritative locked state and HQ/city switching do not mix data or canvases');
  const cycles=[];
  for(let i=0;i<30;i++){await open();const s=await page.evaluate(()=>StageSelectDiorama.stats());await page.evaluate(()=>StageSelectHarnessHost.close());assert.equal(await page.locator('.stage-select-diorama-canvas').count(),0);cycles.push({geometries:s.geometries,textures:s.textures,calls:s.calls});}
  report.cycles=cycles;assert.equal(new Set(cycles.slice(2).map(c=>JSON.stringify(c))).size,1);report.checks.push('30 HQ opens/closes release canvas and return to bounded allocation counts');
  await open();await select('stage_18_8');await page.evaluate(()=>document.querySelector('.stage-select-diorama-canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext());
  await page.waitForFunction(()=>StageSelectDiorama.stats().state==='fallback');assert.equal(await page.locator('.stage-focus-location').isVisible(),true);assert.equal(await page.locator('.stage-select-diorama-canvas').count(),0);
  await page.getByRole('button',{name:'返回总览',exact:true}).click();assert.equal(await page.locator('#stage-select-button-layer').evaluate(e=>e.inert),false);
  await page.locator('.stage-select-diorama-status button').click();await ready();
  report.checks.push('context loss from focus preserves shared decisions using 2D map and retry recovers');
  await page.evaluate(()=>StageSelectHarnessHost.close());await page.route('**/blackiron-hq/headquarters.glb',r=>r.fulfill({status:404,body:''}));
  await page.evaluate(()=>StageSelectHarnessHost.open({mode:'runtime',frameLabel:'黑铁会总部'}));await page.waitForFunction(()=>StageSelectDiorama.stats().state==='fallback');
  assert.equal(await page.locator('.stage-select-stage-button').count(),11);assert.equal(await page.locator('#stage-select-button-layer').evaluate(e=>e.inert),false);
  await page.unroute('**/blackiron-hq/headquarters.glb');await page.locator('.stage-select-diorama-status button').click();await ready();
  report.checks.push('missing HQ model falls back without disabling the eleven entry actions; retry recovers');
  await page.evaluate(()=>StageSelectHarnessHost.close());
  await page.route('**/blackiron-hq/headquarters.glb',async r=>{await new Promise(done=>setTimeout(done,400));await r.continue().catch(()=>{});});
  await page.evaluate(()=>{StageSelectHarnessHost.open({mode:'runtime',frameLabel:'黑铁会总部'});StageSelectRenderer.setFrame('基地门口','qa');});await ready();await page.waitForTimeout(600);
  assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().frameLabel),'基地门口');assert.equal(await page.locator('.stage-select-diorama-canvas').count(),1);await page.unroute('**/blackiron-hq/headquarters.glb');
  report.checks.push('late HQ load cannot replace the current city scene');
  assert.deepEqual(errors,[]);report.pass=true;
 }catch(e){report.pass=false;report.error=e.stack;report.pageErrors=errors;await page.screenshot({path:path.join(out,'failure.png')});process.exitCode=1;}
 finally{await browser.close();server.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({pass:report.pass,checks:report.checks,error:report.error}));}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
