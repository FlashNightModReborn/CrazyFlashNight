'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),crypto=require('crypto');
const {chromium}=require('../../launcher/perf/node_modules/playwright');
const root=path.resolve(__dirname,'../..'),fixture=process.env.MAP_WORKBENCH_FIXTURE;
assert(fixture&&/^ui-[a-f0-9]{32}$/.test(path.basename(fixture))&&path.basename(path.dirname(fixture))==='cf7-map-ui-fixtures','Use only an independent fixture.');
const definitionPath=path.join(fixture,'data/map/map_definition.json'),definition=JSON.parse(fs.readFileSync(definitionPath,'utf8'));
const digest=()=>crypto.createHash('sha256').update(fs.readFileSync(definitionPath)).digest('hex'),original=digest();
const url=process.env.MAP_WORKBENCH_URL||'http://127.0.0.1:18766',output=path.join(root,'tmp/map-workbench/view-modes');fs.mkdirSync(output,{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true,args:['--disable-gpu']});
 const page=await browser.newPage({viewport:{width:1280,height:720}}),errors=[],requests=[];
 page.on('pageerror',error=>errors.push(error.message));
 page.on('request',r=>{if(r.url().endsWith('/api')&&r.method()==='POST')requests.push(r.postDataJSON());});
 await page.addInitScript(()=>window.addEventListener('message',e=>{
  if(e.data?.type==='map-authoring-input'&&e.data.action==='state')window.__viewModeInput=structuredClone(e.data);
  if(parent!==window&&e.source===parent&&e.data?.type==='view-test-barrier')parent.postMessage({type:'view-test-ack',nonce:e.data.nonce},location.origin);
 }));
 const button=name=>page.getByRole('button',{name,exact:true});
 const idle=()=>page.waitForFunction(()=>/选中对象查看属性|草稿已通过/.test(document.querySelector('.mw-status')?.textContent||'')&&document.querySelector('.mw-fields')?.getAttribute('aria-busy')==='false',{},{timeout:90000});
 const saved=()=>page.evaluate(()=>({draft:localStorage.getItem('cf7.map.workbench.draft.v2'),scenarios:localStorage.getItem('cf7.map.workbench.scenarios.v2')}));
 let frame;
 const view=()=>frame.evaluate(()=>({view:MapPanel.authoring.getView(),debug:MapPanel._debugGetState(),snapshot:window.__viewModeInput.snapshot}));
 // Parent/iframe commands are asynchronous. Two FIFO round trips also consume a child's selection and the parent's reply.
 const flushMessages=()=>page.evaluate(async()=>{const host=document.querySelector('iframe');for(let i=0;i<2;i++)await new Promise(resolve=>{const nonce=crypto.randomUUID();function done(e){if(e.source===host.contentWindow&&e.data?.type==='view-test-ack'&&e.data.nonce===nonce){removeEventListener('message',done);resolve();}}addEventListener('message',done);host.contentWindow.postMessage({type:'view-test-barrier',nonce},location.origin);});});
 const settle=async(pageId,mode)=>{await flushMessages();await frame.waitForFunction(({pageId,mode})=>{const v=window.MapPanel?.authoring.getView(),d=window.MapPanel?._debugGetState(),host=parent.document.querySelector('iframe');return v?.pageId===pageId&&v.viewMode===mode&&window.__viewModeInput?.viewMode===mode&&Math.abs(window.__viewModeInput.rasterScale-host.getBoundingClientRect().width/host.clientWidth)<.001&&d.canvasPendingAssets===0&&d.canvasLastRevision===d.canvasRequestedRevision;},{pageId,mode},{timeout:30000});};
 try{
  await page.goto(url);await idle();frame=page.frames().find(f=>f.url().includes('/map/authoring/preview.html'));
  await settle('base','author');assert.equal(await button('创作视图').getAttribute('aria-pressed'),'true');
  await frame.locator('.map-page-tab[data-page-id="school"]').click();await settle('school','author');
  assert.equal(await page.getByLabel('地图页面',{exact:true}).inputValue(),'school','only an explicit inner tab selection changes the outer page');
  await page.getByLabel('地图页面',{exact:true}).selectOption('faction');await settle('faction','author');
  await frame.evaluate(()=>parent.postMessage({type:'map-authoring-preview',session:window.__viewModeInput.session,event:'view',pageId:'school',viewMode:'author',zoom:9},location.origin));
  await settle('faction','author');assert.equal(await page.getByLabel('地图页面',{exact:true}).inputValue(),'faction','a stale passive layout report cannot undo a new page selection');
  const early=await view();assert.equal(early.view.visibleInScenario,false);assert.equal(early.snapshot.pageStates.faction.visible,false);
  assert(early.debug.sceneVisualCount>0);assert.equal(early.debug.enabledHotspotIds.length,0,'editor visibility does not unlock navigation');
  assert.equal(await frame.locator('.map-page-tab:visible').count(),definition.pageOrder.length);
  assert((await frame.locator('.map-page-tab[data-page-id="faction"]').getAttribute('aria-label')).includes('当前方案隐藏'));
  assert.equal(await frame.locator('.map-filter-hotspot:visible').count(),definition.pages.faction.filters.length);
  assert.equal(await frame.locator('.map-avatar.is-visible').count(),definition.pages.faction.staticAvatars.length);
  await frame.locator('[data-filter-id="blackiron"]').first().click();await settle('faction','author');
  assert.equal((await view()).view.filterId,'blackiron');assert((await view()).debug.sceneVisualCount>0);
  const target=frame.locator('.map-authoring-target').last(),targetId=await target.getAttribute('data-target-id');
  assert((await target.getAttribute('aria-label')).includes('当前方案隐藏'));
  const badgeTheme=await target.locator('.map-authoring-hidden-badge').evaluate(n=>({color:getComputedStyle(n).color,background:getComputedStyle(n).backgroundColor}));
  assert.notEqual(badgeTheme.background,'rgba(0, 0, 0, 0)');assert.notEqual(badgeTheme.color,'rgb(0, 0, 0)','isolated preview must resolve its shared palette');
  const beforeClick=await saved();await target.click();
  await page.waitForFunction(id=>document.querySelector('.mw-identity')?.textContent.includes(id),targetId);await settle('faction','author');
  assert.deepEqual(await saved(),beforeClick,'a selection click must not create a zero-distance edit');
  assert((await page.locator('.mw-identity').textContent()).includes(targetId),'canvas selection works while a page/filter is selected');
  const box=await frame.locator('[data-target-id="'+targetId+'"]').boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();
  await page.mouse.move(box.x+box.width/2+24,box.y+box.height/2+8,{steps:6});await page.mouse.up();
  await page.waitForFunction(()=>JSON.parse(localStorage.getItem('cf7.map.workbench.draft.v2')).changes.length===1);await idle();await settle('faction','author');
  const edits=JSON.parse((await saved()).draft);assert.equal(edits.changes.length,1);assert.equal(edits.changes[0].id,targetId);assert.equal(edits.changes[0].kind,'scene');
  const source=definition.pages.faction.sceneVisuals.find(s=>s.id===targetId);assert.notEqual(edits.changes[0].values.rect.x,source.rect.x);
  await button('+').click();await settle('faction','author');
  const beforeMode=await saved(),camera=(await view()).view.camera,snapshot=(await view()).snapshot,traffic=requests.length;
  await button('玩家预览').click();await settle('faction','player');
  const notice=frame.getByRole('region',{name:'玩家预览中的隐藏页面',exact:true});assert(await notice.isVisible());
  assert.deepEqual(await notice.evaluate(n=>({color:getComputedStyle(n).color,background:getComputedStyle(n).backgroundColor})),badgeTheme,'hidden-page notice and object labels consume the same resolved palette');
  assert((await notice.textContent()).includes(definition.pages.faction.title));assert(await frame.locator('.map-panel').evaluate(n=>n.inert));
  assert.equal((await view()).debug.sceneVisualCount,0);assert.equal((await view()).debug.visibleHotspotIds.length,0);
  assert.equal(await frame.locator('.map-authoring-targets').isVisible(),false);
  await frame.evaluate(()=>{const value=window.__viewModeInput;parent.postMessage({type:'map-authoring-preview',session:value.session,event:'move',pageId:value.pageId,kind:'scene',id:value.id,dx:50,dy:50},location.origin);});
  await notice.getByRole('button',{name:'切回创作视图',exact:true}).click();await settle('faction','author');
  assert.deepEqual(await saved(),beforeMode,'view switching and stale player-view move cannot change any draft or scenario');
  assert.deepEqual((await view()).snapshot,snapshot,'author and player views receive exactly the same C# facts');
  assert.deepEqual((await view()).view.camera,camera);assert.equal((await view()).view.filterId,'blackiron');assert.equal(requests.length,traffic);
  await button('编辑 A').click();await page.getByLabel('主线：已完成的最大链序号',{exact:true}).fill('30');
  await page.getByLabel('摩托车 等级（0 为未建成）',{exact:true}).fill('1');await button('保存模拟方案').click();await idle();await settle('faction','author');
  assert.equal((await view()).view.visibleInScenario,true);assert.equal((await view()).snapshot.hotspotStates.blackiron_training.visible,false);
  await button('玩家预览').click();await settle('faction','player');
  assert(await frame.getByRole('region',{name:'玩家预览中的隐藏分层',exact:true}).isVisible());assert.equal(await frame.locator('.map-panel').evaluate(n=>n.inert),false,'other visible filters remain usable');
  await frame.locator('.map-filter-hotspot[data-filter-id="fallen"]').click();await settle('faction','player');
  assert.equal(await frame.locator('.map-authoring-page-hidden').isVisible(),false);assert((await view()).debug.sceneVisualCount>0);
  await button('创作视图').click();await settle('faction','author');await frame.locator('.map-filter-hotspot[data-filter-id="blackiron"]').click();await settle('faction','author');
  await button('编辑 A').click();await page.getByLabel('主线：已完成的最大链序号',{exact:true}).fill('80');
  await page.getByLabel('摩托车 等级（0 为未建成）',{exact:true}).fill('1');await page.getByLabel('大学：已完成的最大链序号',{exact:true}).fill('7');
  await button('保存模拟方案').click();await idle();await settle('faction','author');
  assert.equal((await view()).view.visibleInScenario,true);assert((await view()).debug.enabledHotspotIds.length>0);
  await button('玩家预览').click();await settle('faction','player');assert.equal(await notice.isVisible(),false);assert((await view()).debug.sceneVisualCount>0);
  await page.getByLabel('显示方案',{exact:true}).selectOption('B');await frame.waitForFunction(()=>MapPanel.authoring.getView().visibleInScenario===false);await settle('faction','player');assert(await notice.isVisible());
  assert.equal((await view()).debug.enabledHotspotIds.length,0);assert.equal((await view()).debug.sceneVisualCount,0);
  await button('创作视图').click();await settle('faction','author');assert((await view()).debug.sceneVisualCount>0);
  await page.getByLabel('选择内容类型：人物头像',{exact:true}).click();await settle('faction','author');
  assert(await frame.locator('.map-authoring-target.is-scenario-hidden').count()>0,'hidden NPC avatars remain author-selectable');
  await page.getByLabel('地图页面',{exact:true}).selectOption('school');await settle('school','author');
  await button('编辑 B').click();await page.getByLabel('室友外观',{exact:true}).selectOption('');await button('保存模拟方案').click();await idle();
  await frame.waitForFunction(()=>window.__viewModeInput?.snapshot.avatarAssetUrls.roommate==='');await settle('school','author');
  const roommate=frame.locator('.map-avatar[data-avatar-id="roommate"]');assert(await roommate.isVisible());
  assert.equal(await roommate.locator('img').getAttribute('src'),null,'unknown dynamic appearance uses a labelled placeholder, not a fabricated gender');
  assert.equal((await view()).snapshot.avatarVisibility.roommate,false);assert.equal((await view()).snapshot.avatarAssetUrls.roommate,'');
  await page.getByLabel('选择内容类型：人物头像',{exact:true}).click();await settle('school','author');assert(await frame.locator('[data-target-id="roommate"]').isVisible());
  await page.getByLabel('地图页面',{exact:true}).selectOption('faction');await settle('faction','author');
  const viewportSaved=await saved();
  for(const viewport of [{width:1024,height:576},{width:1600,height:900},{width:2560,height:1440}]){
   await page.setViewportSize(viewport);await page.waitForFunction(width=>Math.abs(document.querySelector('.map-workbench-panel').getBoundingClientRect().width-width)<2,viewport.width);await settle('faction','author');
   for(const modeButton of ['创作视图','玩家预览']){const b=await button(modeButton).boundingBox();assert(b.x>=0&&b.y>=0&&b.x+b.width<=viewport.width&&b.y+b.height<=viewport.height,JSON.stringify(b));}
   await frame.waitForFunction(()=>!document.querySelector('.map-panel').classList.contains('is-page-entering'));
   const geometry=await frame.evaluate(()=>{const body=document.querySelector('.map-panel-body'),rail=document.querySelector('.map-rail-shell');return {overflow:document.documentElement.scrollWidth-innerWidth,bodyWidth:body.clientWidth,railHeight:rail.clientHeight,railOverflow:getComputedStyle(rail).overflowY,buttons:[...document.querySelectorAll('.map-page-tab')].filter(n=>n.getClientRects().length).map(n=>{const r=n.getBoundingClientRect();return {text:n.textContent,x:r.x,y:r.y,right:r.right,bottom:r.bottom};})};});
   assert(geometry.overflow<=1,JSON.stringify(geometry));
   const inner=await frame.evaluate(()=>({width:innerWidth,height:innerHeight}));
   for(const b of geometry.buttons)assert(b.x>=-1&&b.right<=inner.width+1&&b.y>=-1&&b.bottom<=inner.height+1,JSON.stringify({viewport,inner,b}));
   // The production rail intentionally scrolls; every entry must be reachable inside that scroll viewport.
   assert(geometry.railHeight>160&&geometry.railOverflow==='auto',JSON.stringify(geometry));
   for(const filter of await frame.locator('.map-filter-hotspot').all()){
    await filter.scrollIntoViewIfNeeded();
    assert(await filter.evaluate(n=>{const b=n.getBoundingClientRect(),r=n.closest('.map-rail-shell').getBoundingClientRect();return b.left>=r.left-1&&b.right<=r.right+1&&b.top>=r.top-1&&b.bottom<=r.bottom+1;}),'filter must be fully reachable in the scroll rail');
   }
   await frame.locator('.map-filter-hotspot.is-active').scrollIntoViewIfNeeded();
   await page.screenshot({path:path.join(output,'author-'+viewport.width+'.png')});
   await button('玩家预览').click();await settle('faction','player');assert(await notice.isVisible());
   const hiddenGeometry=await notice.evaluate(n=>{const r=n.getBoundingClientRect(),b=n.querySelector('button').getBoundingClientRect();return {left:r.left,top:r.top,right:r.right,bottom:r.bottom,buttonBottom:b.bottom,font:parseFloat(getComputedStyle(n.querySelector('p')).fontSize)};});
   assert(hiddenGeometry.left>=0&&hiddenGeometry.top>=0&&hiddenGeometry.right<=inner.width+1&&hiddenGeometry.bottom<=inner.height+1&&hiddenGeometry.buttonBottom<=inner.height&&hiddenGeometry.font>=14,JSON.stringify(hiddenGeometry));
   await page.screenshot({path:path.join(output,'player-hidden-'+viewport.width+'.png')});
   await button('创作视图').click();await settle('faction','author');
  }
  assert.deepEqual(await saved(),viewportSaved);assert.equal(digest(),original);
  assert(requests.every(r=>['read','catalog','preview'].includes(r.op)),'presentation never applies, changes game facts, or navigates');assert.deepEqual(errors,[]);
  console.log('PASS view modes: initial locked pages/filters/scenes/avatars authorable; actual C# visibility and navigation locks unchanged; hidden-page/filter notices, other visible filters usable, explicit page selection and stale layout isolation, read-only canvas, click-only selection, hidden-object drag, mode/A-B/camera/draft preservation, unknown appearance placeholder, 3 viewport geometry; no content writes.');
 }catch(error){console.error('VIEW MODE DIAGNOSTIC',await page.locator('.mw-status').textContent().catch(()=>''),errors,frame?await view().then(v=>({view:v.view,revision:[v.debug.canvasRequestedRevision,v.debug.canvasLastRevision]})).catch(()=>null):null);await page.screenshot({path:path.join(output,'failed.png')}).catch(()=>{});throw error;}
 finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
