'use strict';
// Only a new-test-fixture.ps1 independent copy may be used for mutation journeys.
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {chromium}=require('../../launcher/perf/node_modules/playwright');
const root=path.resolve(__dirname,'../..'),url=process.env.MAP_WORKBENCH_URL||'http://127.0.0.1:18766';
const fixture=path.resolve(process.env.MAP_WORKBENCH_FIXTURE||root);
assert(/^ui-[a-f0-9]{32}$/.test(path.basename(fixture))&&path.basename(path.dirname(fixture))==='cf7-map-ui-fixtures','Explicit independent fixture root required.');
assert.notEqual(fixture.toLowerCase(),root.toLowerCase());
const definitionPath=path.join(fixture,'data/map/map_definition.json'),original=fs.readFileSync(definitionPath);
const output=path.join(root,'tmp/map-workbench/phase2-ui');
(async()=>{
 const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true,args:['--disable-gpu']});
 const page=await browser.newPage({viewport:{width:1280,height:720}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 const button=name=>page.getByRole('button',{name,exact:true});
 const dialog=()=>page.getByRole('dialog');
 const idle=()=>page.waitForFunction(()=>/^(选中对象查看属性|草稿已通过|已应用到项目|已精确撤回|已确认)/.test(document.querySelector('.mw-status')?.textContent||'')&&document.querySelector('.mw-fields')?.getAttribute('aria-busy')==='false',{},{timeout:90000});
 const draftOps=()=>page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')).changes);
 async function type(name){await page.getByLabel('选择内容类型：'+name,{exact:true}).click();}
 async function create(name,label,configure){await type(name);await button('新建').click();await dialog().getByLabel('名称',{exact:true}).fill(label);if(configure)await configure(dialog());await button('加入草稿').click();await idle();return (await draftOps()).at(-1).id;}
 async function select(name,label){const summary=page.getByLabel('选择内容类型：'+name,{exact:true});if(!await summary.evaluate(n=>n.parentElement.open))await summary.click();await page.getByRole('treeitem',{name:'选择'+name+'：'+label,exact:true}).click();}
 async function openHistory(){if(!await page.locator('.mw-history').evaluate(n=>n.open))await page.locator('.mw-history > summary').click();}
 async function undo(){await openHistory();await button('撤回所选批次').click();await idle();assert.deepEqual(fs.readFileSync(definitionPath),original);}
 try{
  await page.goto(url);await idle();assert.equal((await draftOps()).length,0,'Fixture must start with no browser draft.');
  const newPage=await create('地图页','测试第五页');
  assert.equal(await page.getByLabel('地图页面',{exact:true}).inputValue(),newPage);
  assert.equal(await page.getByLabel('地图页面',{exact:true}).locator('option').count(),5);
  const location=await create('物理地点','测试新场景');
  const hotspot=await create('地点表现','测试入口',d=>d.getByLabel('复用的物理地点',{exact:true}).selectOption(location));
  await type('场景图块');assert.equal(await page.locator('.mw-identity').textContent(),'可新建对象或选择已有内容。','Empty categories must still support creation.');
  await button('素材库 / 导入').click();await dialog().waitFor();
  await page.waitForFunction(()=>document.querySelector('.mw-fields')?.getAttribute('aria-busy')==='false');
  const png=await page.evaluate(()=>{const c=document.createElement('canvas');c.width=8;c.height=6;const x=c.getContext('2d');x.fillStyle='#fc6040';x.fillRect(1,1,4,4);x.fillStyle='rgba(40,160,240,.5)';x.fillRect(4,2,4,4);return c.toDataURL('image/png').split(',')[1];});
  const chooser=page.waitForEvent('filechooser');await button('从图片文件导入').click();await (await chooser).setFiles({name:'透明边缘测试.png',mimeType:'image/png',buffer:Buffer.from(png,'base64')});
  await page.waitForFunction(()=>document.querySelector('.mw-asset-library select')?.selectedOptions[0]?.textContent.includes('8×6')&&document.querySelector('.mw-asset-compare img'));
  await page.waitForFunction(()=>document.querySelector('.mw-fields')?.getAttribute('aria-busy')==='false');
  const imported=await dialog().getByLabel('已有图片 / 未应用候选',{exact:true}).inputValue();
  assert(!fs.existsSync(path.join(fixture,'launcher/web',imported)),'Import is candidate-only.');
  await button('裁切成新候选').click();await dialog().getByLabel('像素宽度',{exact:true}).fill('4');await dialog().getByLabel('像素高度',{exact:true}).fill('3');await button('生成候选').click();
  await page.waitForFunction(()=>document.querySelector('.mw-asset-library select')?.selectedOptions[0]?.textContent.includes('4×3')&&document.querySelector('.mw-asset-compare img'));
  await page.waitForFunction(()=>document.querySelector('.mw-fields')?.getAttribute('aria-busy')==='false');
  const cropped=await dialog().getByLabel('已有图片 / 未应用候选',{exact:true}).inputValue();assert.notEqual(cropped,imported);
  await button('返回').click();
  const visual=await create('场景图块','新图片图块',async d=>{await d.getByLabel('已校验的图片',{exact:true}).selectOption(cropped);await d.getByLabel('关联地点表现',{exact:true}).selectOption(hotspot);});
  await select('物理地点','测试新场景');await page.getByRole('button',{name:/^可进入条件：/}).click();
  await dialog().getByLabel('判断方式',{exact:true}).selectOption('any');await dialog().getByLabel('判断方式',{exact:true}).nth(1).selectOption('chain');
  await dialog().getByLabel('任务链',{exact:true}).selectOption('主线');await dialog().getByLabel('至少',{exact:true}).fill('30');
  await button('增加子条件').click();await dialog().getByLabel('判断方式',{exact:true}).nth(2).selectOption('infra');
  await dialog().getByLabel('基建项目',{exact:true}).selectOption('摩托车');await button('加入草稿').click();await idle();
  await select('场景图块','新图片图块');await page.getByRole('button',{name:/^编辑剧情外观变化/}).click();await button('增加外观变化').click();
  await dialog().getByLabel('图片',{exact:true}).selectOption(imported);await page.getByRole('button',{name:/^条件：/}).click();
  await dialog().getByLabel('判断方式',{exact:true}).selectOption('chain');await dialog().getByLabel('任务链',{exact:true}).selectOption('主线');await dialog().getByLabel('至少',{exact:true}).fill('60');
  await button('加入草稿').click();await dialog().getByText('剧情外观变化',{exact:true}).waitFor();await button('加入草稿').click();await idle();
  await select('物理地点','测试新场景');await button('删除').click();assert(await dialog().getByText(/需要先处理/).count()>0);assert.equal(await button('从草稿删除').count(),0);await button('返回').click();
  await select('地图页','测试第五页');await button('复制').click();await idle();
  const copiedPage=await page.getByLabel('地图页面',{exact:true}).inputValue();assert.notEqual(copiedPage,newPage);assert.equal(await page.getByLabel('地图页面',{exact:true}).locator('option').count(),6);
  assert.deepEqual(fs.readFileSync(definitionPath),original,'Draft previews do not write content.');
  await button('检查并应用').click();assert(await dialog().getByText(/data\/map\/map_definition.json/).count());assert.equal(await dialog().locator('.mw-impact p').filter({hasText:/^(新增|更新)：/}).count(),3);
  await page.getByRole('button',{name:'应用以上 3 个文件',exact:true}).click();await idle();
  const applied=JSON.parse(fs.readFileSync(definitionPath));assert.equal(applied.pageOrder.length,6);assert.equal(Object.keys(applied.locations).length,Object.keys(JSON.parse(original).locations).length+1);
  assert.equal(applied.pages[copiedPage].hotspots[0].locationId,location);assert.notEqual(applied.pages[copiedPage].hotspots[0].id,hotspot);assert.notEqual(applied.pages[copiedPage].sceneVisuals[0].id,visual);
  assert(fs.existsSync(path.join(fixture,'launcher/web',imported)));assert(fs.existsSync(path.join(fixture,'launcher/web',cropped)));
  const batch=await page.getByLabel('已应用批次',{exact:true}).inputValue();assert(batch);
  await button('关闭').click();await page.locator('#reopen').click();await idle();assert.equal(await page.getByLabel('地图页面',{exact:true}).locator('option').count(),6);
  await openHistory();await page.getByLabel('已应用批次',{exact:true}).selectOption(batch);await undo();
  assert(!fs.existsSync(path.join(fixture,'launcher/web',imported)));assert(!fs.existsSync(path.join(fixture,'launcher/web',cropped)));
  // A response can be lost after a completed write: reconcile the exact operation, never replay it.
  await page.getByLabel('地图页面',{exact:true}).selectOption('base');await page.getByLabel('显示名称',{exact:true}).fill('响应丢失测试');await page.getByLabel('显示名称',{exact:true}).press('Tab');await idle();
  let lost=false;await page.route('**/api',async route=>{const body=route.request().postDataJSON();if(body.op==='apply'&&!lost){lost=true;const response=await route.fetch();assert((await response.json()).success);await route.fulfill({contentType:'application/json',body:JSON.stringify({success:false,clientSynthetic:true,error:'测试：应用响应丢失'})});}else await route.continue();});
  await button('检查并应用').click();await page.getByRole('button',{name:'应用以上 1 个文件',exact:true}).click();await idle();assert(lost);assert.equal(JSON.parse(fs.readFileSync(definitionPath)).pages.base.title,'响应丢失测试');
  await page.unroute('**/api');if(!await page.locator('.mw-history').evaluate(n=>n.open))await page.locator('.mw-history > summary').click();await button('撤回所选批次').click();await idle();assert.deepEqual(fs.readFileSync(definitionPath),original);
  // Close before the backend saves; reopen/restart must query that exact batch before calling it a conflict.
  for(const reopenMode of ['panel','document']){
   await page.getByLabel('地图页面',{exact:true}).selectOption('base');
   await page.getByLabel('显示名称',{exact:true}).fill('关闭后保存测试-'+reopenMode);await page.getByLabel('显示名称',{exact:true}).press('Tab');await idle();
   let arrive,allowApply,announceSaved,allowReply,finishReply,applyRequest;
   const arrival=new Promise(resolve=>{arrive=resolve;}),applyAllowed=new Promise(resolve=>{allowApply=resolve;});
   const saved=new Promise(resolve=>{announceSaved=resolve;}),replyAllowed=new Promise(resolve=>{allowReply=resolve;}),replyFinished=new Promise(resolve=>{finishReply=resolve;});
   const traffic=[];
   await page.route('**/api',async route=>{
    const request=route.request().postDataJSON();traffic.push(request);
    if(request.op!=='apply'||applyRequest){await route.continue();return;}
    applyRequest=request;arrive();await applyAllowed;
    try{const response=await route.fetch();announceSaved(await response.json());await replyAllowed;
     try{await route.fulfill({response});}catch(_){}
    }catch(error){announceSaved({success:false,error:error.message});}finally{finishReply();}
   });
   try{
    await button('检查并应用').click();await button('应用以上 1 个文件').click();await arrival;
    const pending=await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')));
    assert.equal(pending.unknown,true);assert.equal(pending.operation,applyRequest.operationId);assert.equal(pending.changes.length,1);
    await button('关闭').click();assert.equal(await page.locator('#panel-container').isVisible(),false);
    allowApply();assert.equal((await saved).success,true,'the backend must finish saving after the panel closed');
    assert.equal(JSON.parse(fs.readFileSync(definitionPath)).pages.base.title,'关闭后保存测试-'+reopenMode);
    if(reopenMode==='panel')await page.locator('#reopen').click();else await page.reload();
    await page.waitForFunction(()=>/已确认应用完成|项目已变化/.test(document.querySelector('.mw-status')?.textContent||'')&&document.querySelector('.mw-fields')?.getAttribute('aria-busy')==='false',{},{timeout:90000});
    const restored=await page.evaluate(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')));
    assert.equal(restored.unknown,false,'an applied batch must not remain an unknown stale draft');assert.deepEqual(restored.changes,[]);
    assert.equal(await page.locator('.mw-draft-conflict').isVisible(),false);assert(await page.locator('iframe').isVisible());
    assert.equal(traffic.filter(r=>r.op==='apply').length,1,'reopen never replays the write');
    assert.deepEqual(traffic.filter(r=>r.op==='query').map(r=>r.operationId),[applyRequest.operationId]);
    await page.getByLabel('地图页面',{exact:true}).selectOption('base');
    await page.getByLabel('显示名称',{exact:true}).fill('迟到响应不得清除新草稿');await page.getByLabel('显示名称',{exact:true}).press('Tab');await idle();
    const newer=await page.evaluate(()=>localStorage.getItem('cf7.map.workbench.draft.v2'));
    allowReply();await replyFinished;
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    assert.equal(await page.evaluate(()=>localStorage.getItem('cf7.map.workbench.draft.v2')),newer,'late old reply cannot adopt over newer edits');
    await button('放弃草稿重读').click();await idle();
    await openHistory();await page.getByLabel('已应用批次',{exact:true}).selectOption(applyRequest.operationId);await undo();
   }finally{allowApply();allowReply();await page.unroute('**/api');}
  }
  fs.mkdirSync(output,{recursive:true});for(const viewport of [{width:1024,height:576},{width:1280,height:720},{width:1920,height:1080}]){await page.setViewportSize(viewport);await page.screenshot({path:path.join(output,`content-${viewport.width}.png`)});const box=await button('检查并应用').boundingBox();assert(box.x>=0&&box.y>=0&&box.y+box.height<=viewport.height+1,'Apply remains inside every viewport.');}
  await button('专注画布').click();await page.keyboard.press('Escape');assert(await button('专注画布').count());
  await button('关闭').click();await page.locator('#reopen').click();await idle();assert.equal((await draftOps()).length,0);assert.deepEqual(errors,[]);
  console.log('PASS V2 UI: fifth page/new physical scene, empty-category creation, upload/crop/variants/OR, copied identities, reference refusal, multi-file apply/reopen/byte-exact undo, lost-response reconcile, save-after-close with panel/document reopen query-only and late-reply isolation, 3 viewports and focus/close. Fixture restored:',fixture);
 }catch(e){console.error('STATUS:',await page.locator('.mw-status').textContent().catch(()=>''),'ERRORS:',errors,'FIXTURE:',fixture);await page.screenshot({path:path.join(output,'mutation-failed.png')}).catch(()=>{});throw e;}
 finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
