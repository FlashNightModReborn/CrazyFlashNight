'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {chromium}=require('../../launcher/perf/node_modules/playwright');
const root=path.resolve(__dirname,'../..'),url=process.env.MAP_WORKBENCH_URL||'http://127.0.0.1:18766',fixture=path.resolve(process.env.MAP_WORKBENCH_FIXTURE||root);
assert(/^ui-[a-f0-9]{32}$/.test(path.basename(fixture))&&path.basename(path.dirname(fixture))==='cf7-map-ui-fixtures','Explicit independent fixture required.');
const original=fs.readFileSync(path.join(fixture,'data/map/map_definition.json'));
(async()=>{
 const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true,args:['--disable-gpu']});
 const page=await browser.newPage({viewport:{width:1280,height:720}}),errors=[];let projection;
 page.on('pageerror',e=>errors.push(e.message));page.on('response',async r=>{try{if(r.url()===url+'/api'&&r.request().postDataJSON().op==='preview'){const data=await r.json();if(data.success)projection=data.data;}}catch(e){}});
 const idle=()=>page.waitForFunction(()=>/^(选中对象查看属性|草稿已通过|已应用到项目|已精确撤回)/.test(document.querySelector('.mw-status')?.textContent||'')&&document.querySelector('.mw-fields')?.getAttribute('aria-busy')==='false',{},{timeout:90000});
 const button=name=>page.getByRole('button',{name,exact:true});
 async function select(type,kind,id){const summary=page.getByLabel('选择内容类型：'+type,{exact:true});if(!await summary.evaluate(n=>n.parentElement.open))await summary.click();await page.locator('[data-mw-tree="'+kind+'/'+id+'"]').click();}
 try{
  await page.goto(url);await idle();
  const catalog=await page.evaluate(async()=>{const r=await fetch('/api',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"op":"catalog"}'});return (await r.json()).data;});
  const d=JSON.parse(original),npc=Object.keys(d.npcs).find(id=>d.npcs[id].label==='前治安官');assert(npc);
  const placements=Object.keys(d.placements).filter(id=>d.placements[id].npcId===npc);assert.equal(placements.length,2);
  const taskList=catalog.tasks.filter(t=>t.finish_npc==='前治安官'&&!t.finish_endpoint).slice(0,2);assert.equal(taskList.length,2);
  const taskBefore=new Map(taskList.map(t=>[t.sourceFile,fs.readFileSync(path.join(fixture,t.sourceFile))]));
  for(let i=0;i<placements.length;i++){
   const id=placements[i],p=d.placements[id],scene=d.locations[p.locationId].sceneName;
   const occurrence=Object.values(catalog.occurrences).find(o=>o.ready&&o.sceneKey===scene&&[...d.npcs[npc].runtimeNames,...d.npcs[npc].aliases].includes(o.taskName));assert(occurrence);
   await select('人物驻点','placement',id);await page.getByLabel('真实场景中的 NPC 实例',{exact:true}).selectOption(occurrence.occurrenceId);await idle();
   await page.getByRole('button',{name:/^人物在场条件：/}).click();const dialog=page.getByRole('dialog');await dialog.getByLabel('判断方式',{exact:true}).selectOption('chain');await dialog.getByLabel('任务链',{exact:true}).selectOption('主线');
   if(i===0)await dialog.getByLabel('至多（留空表示无上限）',{exact:true}).fill('29');else await dialog.getByLabel('至少',{exact:true}).fill('30');
   await button('加入草稿').click();await idle();
  }
  await select('人物身份','npc',npc);await page.getByLabel('驻点数量策略',{exact:true}).selectOption('unique');await idle();
  for(let i=0;i<taskList.length;i++){
   await select('任务端点','task',taskList[i].id);await button('编辑接取 / 交付端点').click();const finish=page.getByRole('dialog').locator('.mw-endpoint').nth(1);
   await finish.getByLabel('选择方式',{exact:true}).selectOption(i===0?'fixed':'followCurrent');await finish.getByLabel('人物身份',{exact:true}).selectOption(npc);
   if(i===0)await finish.getByLabel('固定驻点',{exact:true}).selectOption(placements[0]);await button('加入草稿').click();await idle();
  }
  await button('编辑 A').click();await page.getByLabel('主线：已完成的最大链序号',{exact:true}).fill('60');
  const scenarioResponse=page.waitForResponse(r=>r.url()===url+'/api'&&r.request().postDataJSON().op==='preview');
  await button('保存模拟方案').click();await idle();projection=(await (await scenarioResponse).json()).data;
  assert.equal(projection.projection.taskEndpoints[taskList[0].id].finish.resolved,false,'Fixed target cannot move when its presence ends.');
  assert.equal(projection.projection.taskEndpoints[taskList[1].id].finish.placementId,placements[1]);assert.equal(projection.projection.taskEndpoints[taskList[1].id].finish.resolved,true);
  assert.equal(projection.compareProjection.taskEndpoints[taskList[1].id].finish.placementId,placements[0]);assert.equal(projection.compareProjection.taskEndpoints[taskList[0].id].finish.resolved,true);
  await select('人物驻点','placement',placements[0]);await button('删除').click();assert(await page.getByRole('dialog').getByText(/固定驻点/).count());assert.equal(await button('从草稿删除').count(),0);await button('返回').click();
  assert.deepEqual(fs.readFileSync(path.join(fixture,'data/map/map_definition.json')),original);
  await button('检查并应用').click();const changed=projection.impact.length;assert.equal(changed,taskBefore.size+1);
  await button('应用以上 '+changed+' 个文件').click();await idle();
  const after=JSON.parse(fs.readFileSync(path.join(fixture,'data/map/map_definition.json')));assert.equal(after.npcs[npc].placementPolicy,'unique');
  for(let i=0;i<taskList.length;i++){const t=JSON.parse(fs.readFileSync(path.join(fixture,taskList[i].sourceFile),'utf8').replace(/^\uFEFF/,'')).tasks.find(t=>String(t.id)===String(taskList[i].id));assert(!('finish_npc' in t));assert(!('finish_npc_hotspot' in t));assert.equal(t.finish_endpoint.mode,i===0?'fixed':'followCurrent');}
  const batch=await page.getByLabel('已应用批次',{exact:true}).inputValue();await button('关闭').click();await page.locator('#reopen').click();await idle();
  await page.locator('.mw-history > summary').click();await page.getByLabel('已应用批次',{exact:true}).selectOption(batch);await button('撤回所选批次').click();await idle();
  assert.deepEqual(fs.readFileSync(path.join(fixture,'data/map/map_definition.json')),original);for(const [file,bytes] of taskBefore)assert.deepEqual(fs.readFileSync(path.join(fixture,file)),bytes);
  assert.deepEqual(errors,[]);console.log('PASS NPC UI: two real source bindings, mutually exclusive presence, fixed/follow source-owned task endpoints, early/late same C# projection, reference refusal and exact map+task byte undo. No actual Flash interaction is claimed.');
 }catch(e){console.error('STATUS:',await page.locator('.mw-status').textContent().catch(()=>''),'ERRORS:',errors,'FIXTURE:',fixture);throw e;}
 finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
