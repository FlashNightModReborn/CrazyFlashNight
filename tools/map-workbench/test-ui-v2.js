'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {chromium}=require('../../launcher/perf/node_modules/playwright');
const root=path.resolve(__dirname,'../..'),url=process.env.MAP_WORKBENCH_URL||'http://127.0.0.1:18766';
(async()=>{
 const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true,args:['--disable-gpu']});
 const page=await browser.newPage({viewport:{width:1280,height:720}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 try{
  await page.goto(url);await page.waitForFunction(()=>document.querySelector('.mw-status')?.textContent.includes('选中对象查看属性'),{},{timeout:90000});
  await page.frameLocator('iframe').locator('.map-authoring-target.is-selected').waitFor({timeout:20000});
  assert.deepEqual(errors,[]);
  assert.equal(await page.getByRole('button',{name:'检查并应用',exact:true}).isEnabled(),false);
  assert.equal(await page.getByRole('button',{name:'读取游戏事实',exact:true}).isEnabled(),false);
  const frame=page.frames().find(f=>f.url().includes('/map/authoring/preview.html'));
  const state=await frame.evaluate(()=>({view:MapPanel.authoring.getView(),debug:MapPanel._debugGetState(),version:MapDefinitionData.version}));
  assert.equal(state.version,2);
  assert.equal(state.view.pageId,'base');
  assert(await page.locator('[role=treeitem]').count()>100);
  // The explicit view switch consumes one row; retain at least 320 logical px of preview at 125% scale.
  const box=await page.locator('iframe').boundingBox();assert(box.width>850&&box.height>=400,JSON.stringify(box));
  fs.mkdirSync(path.join(root,'tmp/map-workbench/phase2-ui'),{recursive:true});
  await page.screenshot({path:path.join(root,'tmp/map-workbench/phase2-ui/initial.png')});
  await page.getByRole('button',{name:'编辑 A',exact:true}).click();
  await page.getByRole('dialog').waitFor();
  await page.getByLabel('主线：已完成的最大链序号',{exact:true}).fill('80');
  await page.getByLabel('摩托车 等级（0 为未建成）',{exact:true}).fill('1');
  await page.getByLabel('大学：已完成的最大链序号',{exact:true}).fill('7');
  await page.getByRole('button',{name:'保存模拟方案',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('.mw-status')?.textContent.includes('选中对象查看属性'),{},{timeout:90000});
  assert.equal(await page.getByRole('button',{name:'检查并应用',exact:true}).isEnabled(),false,'simulation must not create content edits');
  await page.getByLabel('地图页面',{exact:true}).selectOption('school');
  await page.waitForFunction(()=>document.querySelector('iframe').contentWindow.MapPanel.authoring.getView().pageId==='school');
  const late=await frame.evaluate(()=>MapPanel._debugGetState());
  assert(late.enabledHotspotIds.length>0);
  await page.getByRole('button',{name:'玩家预览',exact:true}).click();
  await frame.waitForFunction(()=>MapPanel.authoring.getView().viewMode==='player');
  await page.getByLabel('显示方案',{exact:true}).selectOption('B');
  await page.waitForFunction(()=>document.querySelector('iframe').contentWindow.MapPanel._debugGetState().enabledHotspotIds.length===0);
  await page.screenshot({path:path.join(root,'tmp/map-workbench/phase2-ui/early-school.png')});
  assert.deepEqual(errors,[]);
  console.log('PASS V2 real C# + production MapPanel; independent scenario A/B, page visibility, no content writes.');
 }catch(e){console.error('STATUS:',await page.locator('.mw-status').textContent().catch(()=>''),'ERRORS:',errors);throw e;}
 finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
