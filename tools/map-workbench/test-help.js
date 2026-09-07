'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),crypto=require('crypto');
const {chromium}=require('../../launcher/perf/node_modules/playwright');
const root=path.resolve(__dirname,'../..'),fixture=process.env.MAP_WORKBENCH_FIXTURE;
assert(fixture&&path.basename(fixture).startsWith('ui-')&&path.basename(path.dirname(fixture))==='cf7-map-ui-fixtures','Use a new independent fixture, never the real checkout.');
const definitionFile=path.join(fixture,'data/map/map_definition.json');
const hash=()=>crypto.createHash('sha256').update(fs.readFileSync(definitionFile)).digest('hex');
const originalHash=hash(),url=process.env.MAP_WORKBENCH_URL||'http://127.0.0.1:18766';
const guide=fs.readFileSync(path.join(root,'launcher/web/help/map-workbench.md'),'utf8');
const output=path.join(root,'tmp/map-workbench/help-verification');fs.mkdirSync(output,{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true,args:['--disable-gpu']});
 const page=await browser.newPage({viewport:{width:1280,height:720}}),errors=[],requests=[],network=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('request',r=>{if(r.url().endsWith('/api')&&r.method()==='POST')requests.push(r.postDataJSON());});
 page.on('response',r=>{if(r.url().endsWith('/api'))network.push({op:r.request().postDataJSON()?.op,status:r.status()});});
 page.on('requestfailed',r=>{if(r.url().endsWith('/api'))network.push({op:r.postDataJSON()?.op,error:r.failure()?.errorText});});
 await page.addInitScript(()=>{if(location.protocol==='http:'&&!sessionStorage.getItem('map-help-seeded')){
  sessionStorage.setItem('map-help-seeded','1');localStorage.setItem('cf7.map.workbench.draft.v2',JSON.stringify({digest:'0'.repeat(64),taskDigest:'0'.repeat(64),changes:[],operation:'',unknown:false}));}});
 async function ready(){await page.waitForFunction(()=>/选中对象查看属性|草稿已通过内容与引用检查/.test(document.querySelector('.mw-status')?.textContent||''),{},{timeout:90000});}
 async function show(){await page.getByRole('button',{name:'第一次使用：跟着做一遍',exact:true}).click();await page.locator('.mw-guide article:visible h2').waitFor();
  await page.waitForFunction(()=>{const style=getComputedStyle(document.querySelector('.mw-guide'));return style.opacity==='1'&&style.transform==='none';});}
 async function snapshot(){return page.evaluate(()=>({draft:localStorage.getItem('cf7.map.workbench.draft.v2'),selected:document.querySelector('.mw-identity').textContent,
  a:document.querySelector('[aria-label="方案 A"]').value,b:document.querySelector('[aria-label="方案 B"]').value,
  camera:document.querySelector('iframe').contentWindow.MapPanel.authoring.getView().camera}));}
 try{
  await page.goto(url);await ready();await page.evaluate(()=>document.fonts.ready);
  assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')).digest),originalHash.toUpperCase(),'empty draft adopts updated upstream content');
  await page.waitForFunction(()=>!!document.querySelector('iframe')?.contentWindow.MapPanel?.authoring.getView().pageId);
  const oldX=await page.locator('#mw-x').inputValue();
  await page.locator('#mw-x').fill(String(Number(oldX)+10));await page.locator('#mw-x').press('Tab');await ready();
  await page.waitForFunction(()=>document.querySelector('.mw-count').textContent.startsWith('1 '));
  const before=await snapshot(),traffic=requests.length;
  await show();
  assert.equal(await page.locator('.mw-guide article:visible h2').textContent(),'入门练习');
  assert.equal(await page.locator('.mw-guide-nav button').count(),10);
  assert(await page.evaluate(()=>!!document.querySelector('.mw-library').closest('[inert]')),'editor must be inert while reading');
  await page.getByRole('searchbox',{name:'搜索帮助主题'}).fill('固定');
  assert(await page.locator('.mw-guide-nav button:visible').count()>0);
  await page.getByRole('searchbox',{name:'搜索帮助主题'}).fill('zzzz不存在的帮助');
  assert.equal(await page.locator('.mw-guide-nav button:visible').count(),0);
  assert.equal(await page.locator('.mw-guide article:visible').count(),0);
  await page.getByRole('searchbox',{name:'搜索帮助主题'}).fill('');
  await page.locator('.mw-guide-nav').getByRole('button',{name:'剧情条件与双方案',exact:true}).click();
  assert((await page.locator('.mw-guide article:visible').textContent()).includes('编辑 B'));
  for(let i=0;i<24;i++){await page.keyboard.press('Tab');assert(await page.evaluate(()=>!!document.activeElement.closest('.mw-guide')),'Tab must remain in help');}
  await page.keyboard.press('Escape');
  await page.locator('.mw-guide').waitFor({state:'hidden'});
  assert.equal(await page.locator('.mw-guide').isVisible(),false);
  assert.equal(await page.evaluate(()=>document.activeElement.textContent),'第一次使用：跟着做一遍');
  assert.deepEqual(await snapshot(),before,'help return preserves exact draft, selection, scenarios and camera');
  assert.equal(requests.length,traffic,'reading, searching and closing help must not send domain requests');
  await page.locator('summary').filter({hasText:'人物驻点'}).first().click();
  await page.getByRole('button',{name:'怎样编辑这类对象？',exact:true}).click();
  assert.equal(await page.locator('.mw-guide article:visible h2').textContent(),'人物身份与驻点');
  await page.getByRole('button',{name:'← 返回编辑',exact:true}).click();
  const aId=await page.getByLabel('方案 A',{exact:true}).inputValue(),bId=await page.getByLabel('方案 B',{exact:true}).inputValue();
  assert.notEqual(aId,bId);
  const aBefore=await page.evaluate(id=>JSON.parse(localStorage.getItem('cf7.map.workbench.scenarios.v2')).find(s=>s.id===id),aId);
  await page.getByRole('button',{name:'编辑 B',exact:true}).click();
  await page.getByLabel('主线：已完成的最大链序号',{exact:true}).fill('30');
  await page.getByRole('button',{name:'保存模拟方案',exact:true}).click();await ready();
  const scenarios=await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.scenarios.v2')));
  assert.deepEqual(scenarios.find(s=>s.id===aId),aBefore,'editing B must not mutate a distinct A');
  assert.equal(scenarios.find(s=>s.id===bId).facts.chains.主线,30);
  for(const size of [{width:1024,height:576},{width:1600,height:900},{width:2560,height:1440}]){
   await page.setViewportSize(size);await show();
   const geometry=await page.evaluate(()=>{
    const dialog=document.querySelector('.mw-guide'),content=document.querySelector('.mw-guide-content'),nav=document.querySelector('.mw-guide-nav');
    const back=dialog.querySelector('[data-secondary-action="back"]').getBoundingClientRect(),close=dialog.querySelector('[data-secondary-action="close"]').getBoundingClientRect(),r=dialog.getBoundingClientRect();
    return {width:r.width,height:r.height,left:r.left,right:r.right,top:r.top,bottom:r.bottom,contentX:content.scrollWidth-content.clientWidth,navX:nav.scrollWidth-nav.clientWidth,closeRight:close.right,backRight:back.right,font:parseFloat(getComputedStyle(content).fontSize)};
   });
   assert(geometry.left>=-1&&geometry.top>=-1&&geometry.right<=size.width+1&&geometry.bottom<=size.height+1,JSON.stringify(geometry));
   assert(geometry.contentX<=1&&geometry.navX<=1&&geometry.font>=14,JSON.stringify(geometry));
   assert(geometry.closeRight>geometry.backRight,'panel Close must remain rightmost');
   await page.screenshot({path:path.join(output,'guide-'+size.width+'.png')});
   await page.getByRole('button',{name:'← 返回编辑',exact:true}).click();
  }
  await show();await page.getByRole('button',{name:'关闭工作台',exact:true}).click();
  await page.locator('.mw-guide').waitFor({state:'hidden'});
  assert.equal(await page.locator('#panel-container').isVisible(),false);
  assert.equal(await page.locator('.mw-guide').isVisible(),false);
  await page.getByRole('button',{name:'打开地图工作台',exact:true}).click();await ready();
  await page.getByRole('button',{name:'撤销草稿末步',exact:true}).click();await ready();
  assert.equal(hash(),originalHash,'all help exercises remain file-read-only');
  assert(requests.every(r=>['read','catalog','preview'].includes(r.op)),'no apply, undo, recover or asset writes');

  // A fresh document exercises retry and a response arriving after closing help.
  let failures=1,hold=false,release,arrived;
  await page.route('**/help/map-workbench.md',async route=>{
   if(failures-- > 0){await route.fulfill({status:503,body:'temporary fixture failure'});return;}
   if(hold){arrived();await new Promise(resolve=>{release=resolve;});}
   try{await route.fulfill({status:200,contentType:'text/markdown; charset=utf-8',body:guide});}catch(_){}
  });
  await page.reload();await ready();await page.getByRole('button',{name:'第一次使用：跟着做一遍',exact:true}).click();
  await page.getByRole('button',{name:'重新读取帮助',exact:true}).waitFor();
  await page.getByRole('button',{name:'重新读取帮助',exact:true}).click();await page.locator('.mw-guide article:visible h2').waitFor();
  await page.getByRole('button',{name:'← 返回编辑',exact:true}).click();
  hold=true;const arrival=new Promise(resolve=>{arrived=resolve;});
  await page.reload();await ready();await page.getByRole('button',{name:'第一次使用：跟着做一遍',exact:true}).click();await arrival;
  await page.getByRole('button',{name:'← 返回编辑',exact:true}).click();hold=false;release();
  await show();assert.equal(await page.locator('.mw-guide article:visible h2').textContent(),'入门练习');
  await page.getByRole('button',{name:'← 返回编辑',exact:true}).click();
  const shape=JSON.parse(fs.readFileSync(definitionFile,'utf8')).pages.base.sceneVisuals[0];
  const stale={digest:'0'.repeat(64),taskDigest:'0'.repeat(64),changes:[{kind:'scene',pageId:'base',id:shape.id,values:{rect:{...shape.rect,x:shape.rect.x+10}}}],operation:'',unknown:false};
  await page.evaluate(value=>localStorage.setItem('cf7.map.workbench.draft.v2',JSON.stringify(value)),stale);
  let catalogFailure=true,queryState='';
  await page.route('**/api',async route=>{const request=route.request().postDataJSON();if(catalogFailure&&request?.op==='catalog'){
   catalogFailure=false;await route.fulfill({contentType:'application/json',body:JSON.stringify({success:false,error:'目录测试读取失败'})});
  }else if(queryState&&request?.op==='query'){
   await route.fulfill({contentType:'application/json',body:JSON.stringify({success:true,data:{state:queryState}})});
  }else await route.continue();});
  const previewsBeforeConflict=requests.filter(r=>r.op==='preview').length;
  await page.reload();await page.waitForFunction(()=>document.querySelector('.mw-status')?.textContent.includes('目录测试读取失败'));
  assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')).changes),stale.changes,'catalog failure cannot erase saved draft');
  const conflict=page.getByRole('region',{name:'处理旧草稿冲突',exact:true});
  assert(await conflict.isVisible(),'catalog failure must still expose the preserved conflict');
  await page.reload();await page.waitForFunction(()=>document.querySelector('.mw-status')?.textContent.includes('项目已变化'));
  assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')).changes),stale.changes,'real stale draft is preserved');
  assert(await conflict.isVisible());
  assert.equal(await conflict.locator('h2').textContent(),'旧草稿与当前项目不一致');
  assert((await conflict.textContent()).includes('已保留 1 项未应用修改'));
  assert((await conflict.textContent()).includes('继续等待不会自动解决'));
  assert((await page.locator('.mw-caption').textContent()).startsWith('预览已暂停'));
  assert.equal(await page.locator('iframe').isVisible(),false,'conflict must not expose a blank or stale preview');
  for(const label of ['新建','复制','删除','检查并应用','撤销草稿末步','导入草稿','编辑 A','编辑 B','复制 A 为模拟','读取游戏事实','玩家取景','聚焦所选','素材库 / 导入']){
   assert(await page.getByRole('button',{name:label,exact:true}).isDisabled(),label+' must wait for conflict resolution');
  }
  for(const label of ['地图页面','方案 A','方案 B','显示方案','对比保存前','编辑边框'])assert(await page.getByLabel(label,{exact:true}).isDisabled(),label);
  const conflictSaved=await page.evaluate(()=>localStorage.getItem('cf7.map.workbench.draft.v2'));
  for(const size of [{width:1024,height:576},{width:1600,height:900}]){
   await page.setViewportSize(size);await page.evaluate(()=>document.fonts.ready);
   await page.waitForFunction(width=>Math.abs(document.querySelector('.map-workbench-panel').getBoundingClientRect().width-width)<2,size.width);
   const geometry=await conflict.evaluate(region=>{
    const card=region.querySelector('.mw-conflict-card'),r=region.getBoundingClientRect();
    return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,font:parseFloat(getComputedStyle(card).fontSize),overflowX:region.scrollWidth-region.clientWidth,
     actions:Array.from(region.querySelectorAll('button')).filter(b=>!b.hidden).map(b=>{const a=b.getBoundingClientRect();return {label:b.textContent,left:a.left,right:a.right,top:a.top,bottom:a.bottom,height:a.height};})};
   });
   assert(geometry.left>=-1&&geometry.top>=-1&&geometry.right<=size.width+1&&geometry.bottom<=size.height+1,JSON.stringify(geometry));
   assert(geometry.font>=14&&geometry.overflowX<=1,JSON.stringify(geometry));
   assert.equal(geometry.actions.length,2);
   for(const action of geometry.actions)assert(action.left>=geometry.left&&action.right<=geometry.right&&action.top>=geometry.top&&action.bottom<=geometry.bottom&&action.height>=38,JSON.stringify({size,geometry}));
   await page.screenshot({path:path.join(output,'conflict-'+size.width+'.png')});
  }
  const downloadPending=page.waitForEvent('download');
  await conflict.getByRole('button',{name:'导出保留的草稿',exact:true}).click();const download=await downloadPending;
  assert.equal(download.suggestedFilename(),'map-content-draft.json');
  const exported=JSON.parse(fs.readFileSync(await download.path(),'utf8'));
  assert.deepEqual(exported,{version:2,expectedDigest:stale.digest,expectedTaskDigest:stale.taskDigest,changes:stale.changes},'export must preserve the old baseline and exact operations');
  assert.equal(await page.evaluate(()=>localStorage.getItem('cf7.map.workbench.draft.v2')),conflictSaved,'export does not clear or rebase the draft');
  await page.getByRole('button',{name:'关闭',exact:true}).click();
  await page.getByRole('button',{name:'打开地图工作台',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('.mw-status')?.textContent.includes('项目已变化')&&document.querySelector('.mw-fields')?.getAttribute('aria-busy')==='false'&&!document.querySelector('.mw-draft-conflict')?.hidden);
  assert(await conflict.isVisible());
  assert.equal(await page.evaluate(()=>localStorage.getItem('cf7.map.workbench.draft.v2')),conflictSaved,'close/reopen keeps the exact unresolved draft');
  await page.getByRole('button',{name:'重读 / 核对结果',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('.mw-fields')?.getAttribute('aria-busy')==='false');
  assert((await page.locator('.mw-caption').textContent()).startsWith('预览已暂停'));
  assert.equal(requests.filter(r=>r.op==='preview').length,previewsBeforeConflict,'conflict, retry and reopen cannot project old edits onto new content');
  await conflict.getByRole('button',{name:'放弃试用草稿并加载当前项目',exact:true}).press('Enter');await ready();
  await page.waitForFunction(()=>!!document.querySelector('iframe')?.contentWindow.MapPanel?.authoring.getView().pageId);
  assert.equal(await conflict.isVisible(),false);assert(await page.locator('iframe').isVisible());
  assert(await page.getByRole('button',{name:'编辑 A',exact:true}).isEnabled());
  const discarded=await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')));
  assert.deepEqual(discarded.changes,[]);assert.equal(discarded.digest,originalHash.toUpperCase());
  assert.notEqual(discarded.taskDigest,stale.taskDigest);assert.equal(hash(),originalHash,'discard only edits the fixture browser draft, not project files');
  queryState='partial';const unknownQueriesBefore=requests.filter(r=>r.op==='query').length;
  await page.evaluate(()=>localStorage.setItem('cf7.map.workbench.draft.v2',JSON.stringify({digest:'0'.repeat(64),taskDigest:'0'.repeat(64),changes:[],operation:'a'.repeat(32),operationKind:'apply',unknown:true})));
  await page.reload();await page.waitForFunction(()=>document.querySelector('.mw-status')?.textContent.includes('批次尚未完成'));
  assert.equal(requests.filter(r=>r.op==='query').length,unknownQueriesBefore+1,'reopen must query the original unknown write before judging content conflict');
  assert.equal(requests.filter(r=>r.op==='query').at(-1).operationId,'a'.repeat(32));
  assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')).unknown),true,'unknown write is not discarded as an empty draft');
  assert((await conflict.locator('h2').textContent()).includes('写入尚未确认完成'));
  assert(await conflict.getByRole('button',{name:'核对写入结果',exact:true}).isVisible());
  assert.equal(await conflict.getByRole('button',{name:'放弃试用草稿并加载当前项目',exact:true}).count(),0,'unknown write cannot offer discard');
  assert(await page.getByRole('button',{name:'放弃草稿重读',exact:true}).isDisabled());
  await page.screenshot({path:path.join(output,'conflict-unknown.png')});
  queryState='not_found';const queriesBefore=requests.filter(r=>r.op==='query').length;
  await conflict.getByRole('button',{name:'核对写入结果',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('.mw-status')?.textContent.includes('没有发生本次写入'));
  assert.equal(requests.filter(r=>r.op==='query').length,queriesBefore+1);
  assert.equal(requests.filter(r=>r.op==='query').at(-1).operationId,'a'.repeat(32),'query uses the retained operation, never a new write');
  assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')).unknown),false);
  assert(await conflict.getByRole('button',{name:'放弃试用草稿并加载当前项目',exact:true}).isVisible());
  await page.getByRole('button',{name:'放弃草稿重读',exact:true}).click();await ready();
  assert.equal(await conflict.isVisible(),false);assert(await page.locator('iframe').isVisible());
  const unchangedBaseline=await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')));
  const missingWrite={...unchangedBaseline,changes:stale.changes,operation:'b'.repeat(32),operationKind:'apply',unknown:true};
  await page.evaluate(value=>localStorage.setItem('cf7.map.workbench.draft.v2',JSON.stringify(value)),missingWrite);
  const missingQueriesBefore=requests.filter(r=>r.op==='query').length;
  await page.reload();await page.waitForFunction(()=>document.querySelector('.mw-status')?.textContent.includes('没有发生本次写入'));
  const unwritten=await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')));
  assert.equal(unwritten.unknown,false);assert.deepEqual(unwritten.changes,stale.changes,'a confirmed absent write keeps all unapplied edits');
  assert.equal(requests.filter(r=>r.op==='query').length,missingQueriesBefore+1);
  assert.equal(requests.filter(r=>r.op==='query').at(-1).operationId,missingWrite.operation);
  assert.equal(await conflict.isVisible(),false);assert(await page.locator('iframe').isVisible());
  assert(await page.getByRole('button',{name:'检查并应用',exact:true}).isEnabled(),'unchanged baseline resumes a checked preview without replaying the write');
  await page.getByRole('button',{name:'放弃草稿重读',exact:true}).click();await ready();
  assert.equal(hash(),originalHash);assert.deepEqual(errors,[]);
  assert(requests.every(r=>['read','catalog','preview','query'].includes(r.op)));
  console.log('PASS map help: 10 searchable topics, source-only tutorial, contextual routing, exact inert/Tab/Esc/return/close, independent B editing, 3 viewports, retry/late response; empty upstream adoption, preserved stale/unknown draft and catalog failure; visible conflict and locked edits, 2 viewport action geometry, exact export/reopen, zero conflict previews, explicit discard recovery, unknown-write query-only; no content writes.');
 }catch(error){console.error('HELP DIAGNOSTIC',await page.evaluate(()=>({status:document.querySelector('.mw-status')?.textContent,guide:document.querySelector('.mw-guide')?.hidden})),{errors,requests:requests.map(r=>r.op),network});throw error;}
 finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
