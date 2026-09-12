'use strict';
const assert=require('assert'),path=require('path'),fs=require('fs');
const {chromium}=require('../launcher/perf/node_modules/playwright');
const root=path.resolve(__dirname,'..');
function css(file){return fs.readFileSync(file,'utf8').replace(/@import url\("([^"]+)"\);/g,(_,part)=>css(path.resolve(path.dirname(file),part)));}
(async()=>{
 const executablePath=['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe','C:/Program Files/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);
 const browser=await chromium.launch({executablePath,headless:true});
 try{
 for(const entryRoute of ['build','battlebox']){
 const page=await browser.newPage({viewport:{width:1024,height:576}}), errors=[];
 async function hoverText(selector,expected){
  await page.mouse.move(5,5);await page.locator(selector).hover();
  try{await page.waitForFunction(text=>PanelTooltip.isVisible()&&document.getElementById('panel-tooltip').textContent.includes(text),expected,{timeout:3000});}
  catch(error){throw Error(entryRoute+' hover '+expected+' failed: '+JSON.stringify(await page.evaluate(()=>PanelTooltip.debugState())));}
 }
 page.on('pageerror',e=>{errors.push(e.message);console.error('PAGE ERROR',e.message);});page.on('console',m=>{if(m.type()==='warning'||m.type()==='error')console.log('browser:',m.text());});
 await page.setContent('<html lang="zh-CN"><body style="margin:0;background:#080b0d"><div id="panel-tooltip" class="panel-tooltip"></div></body></html>');
 await page.addStyleTag({content:css(path.join(root,'launcher/web/css/panels.css'))});
 await page.evaluate(()=>{
  window.fixture={messages:[],writes:[],reads:[],seq:1,revision:1,state:'idle',bag:{},full:false,unknown:false,queries:0};
  window.Toast={add:message=>fixture.messages.push(message)};
  window.Bridge={on:()=>{},send:message=>{setTimeout(()=>fixture.respond(message),10);return true;}};
 });
 for(const name of ['panel-runtime','tooltip-document','tooltip','workbench-lifecycle','workbench-focus','workbench-primitives','workbench-profile','workbench','workbench-components','item-filter','inventory-runtime','inventory-ui','inventory-workbench-config','inventory-workbench-quick-transfer','inventory-workbench-owned-view','inventory-workbench-stash-source','inventory-workbench-storage-source','inventory-workbench-storage-controls','inventory-storage-workbench','inventory-workbench-stash-navigation','character-build/character-build-stash-transport'])
  await page.addScriptTag({path:path.join(root,'launcher/web/modules',name+'.js')});
 await page.evaluate(entryRoute=>{
  const f=fixture;
  f.item=(name,major,quantity,kind='stack')=>({name,displayName:name,icon:'fixture-item',majorType:major,use:major,actionType:'',weaponType:'',setId:'',setName:'',setOrder:0,itemKind:kind,quantity,enhancementLevel:0,maxEnhancementLevel:13,isMaxEnhancement:false,tierSlotAvailable:false,tierSlotUsed:false,modSlotCapacity:0,modSlotUsed:0,modSlots:[],modMeta:null,rarity:''});
  f.bag[0]=f.item('背包测试弹药','消耗品',5);f.chest={0:f.item('战备箱测试步枪','武器',1,'equipment')};
  f.rows=Array.from({length:42},(_,i)=>({entryId:'s.e'+i,revision:1,quantity:i===0?12:i===1?8:i<32?1:7,item:f.item(i===0?'普通hp药剂':i===1?'手枪通用弹药':i<32?'备用步枪 '+i:'维修材料 '+i,i<2?'消耗品':i<32?'武器':'材料',i===0?12:i===1?8:i<32?1:7,i>1&&i<32?'equipment':'stack')}));
  f.facets=items=>['consumable','weapon','material'].map((id,i)=>({id,label:['消耗品','武器','材料'][i],count:items.filter(item=>item.majorType===['消耗品','武器','材料'][i]).length,order:i,children:[]})).filter(x=>x.count);
  f.snapshot=request=>{
   const capacity=request.containerId==='背包'?50:40,offset=Math.min(request.offset,capacity-1),limit=Math.min(request.limit,capacity-offset),seq=++f.seq;
   const rows=Array.from({length:limit},(_,i)=>{const physicalSlot=offset+i,item=request.containerId==='背包'?f.bag[physicalSlot]:f.chest[physicalSlot];
    const slot={physicalSlot,occupied:!!item,slotLease:'lease.'+seq+'.'+physicalSlot};if(item){slot.item=item;slot.confirmProjection={itemKind:item.itemKind,name:item.name,displayName:item.displayName,quantity:item.quantity,enhancementLevel:item.enhancementLevel,rarity:item.rarity,tier:'',modSignature:'',lastUpdate:1};}return slot;});
   const snapshot={containerId:request.containerId,capacity,accessibleCapacity:capacity,viewCapacity:capacity,filterKey:request.filterKey||'all',pageSizeHint:50,locked:false,snapshotSeq:seq,containerEpoch:1,containerVersion:f.revision,offset,limit,slots:rows,filterFacets:f.facets(rows.filter(r=>r.occupied).map(r=>r.item)),filterItemCount:rows.filter(r=>r.occupied).length,setFacets:[],setFilterItemCount:0};
   if(request.filterSpec)snapshot.filterSpec=request.filterSpec;return snapshot;
  };
  f.respond=message=>{if(message.domain!=='inventory')throw Error('unexpected domain');
   if(message.cmd==='tooltip'){const source=message.payload.source,item=(source.containerId==='背包'?f.bag:f.chest)[source.slot];
    PanelRuntime.sharedResponseRouter.handleResponse({...message,type:'panel_resp',v:1,success:true,
    introHTML:item.name,descHTML:'共享物品注释',itemType:item.majorType});return;}
   if(message.cmd!=='snapshot')throw Error('unexpected inventory write '+message.cmd);
   if(message.payload.requests.some(r=>r.containerId==='stash'))throw Error('stash leaked to physical inventory wire');
   PanelRuntime.sharedResponseRouter.handleResponse({...message,type:'panel_resp',v:1,success:true,snapshots:message.payload.requests.map(f.snapshot)});
  };
  function TooltipTransport() {}
  CharacterBuildStashTransport.install(TooltipTransport);
  const tooltipTransport=new TooltipTransport();tooltipTransport._base=()=>({});
  tooltipTransport._mux={request:(cmd,payload,opts,cb)=>{const row=f.rows.find(r=>r.entryId===payload.entryId);
   const respond=()=>cb({success:true,data:{success:true,tooltip:{itemName:row.item.name,displayname:row.item.displayName,
    iconName:'',itemType:row.item.majorType,introHTML:row.item.displayName+'<br>HP+150',descHTML:'恢复体力，加速伤口愈合'}}});
   if(f.holdTooltip)f.delayedTooltip=respond;else setTimeout(respond,10);return true;}};
  f.itemUse={debugState:()=>({state:f.state}),requestStashTooltip:tooltipTransport.requestStashTooltip.bind(tooltipTransport),
   requestStashPage:(offset,cb,spec)=>{f.reads.push({offset,spec});setTimeout(()=>{const all=f.rows,specification=spec||{major:'all'},major={weapon:'武器',material:'材料',consumable:'消耗品'}[specification.major];const rows=major?all.filter(r=>r.item.majorType===major):all;offset=rows.length?Math.min(offset,Math.floor((rows.length-1)/32)*32):0;
    cb({success:true,storeId:'s',revision:f.revision,offset,total:rows.length,entries:JSON.parse(JSON.stringify(rows.slice(offset,offset+32))),migrationRequired:false,pendingOperationId:'',filterSpec:specification,filterFacets:f.facets(all.map(r=>r.item)),filterItemCount:all.length,unfilteredTotal:all.length,setFacets:[],setFilterItemCount:0},{success:true});},10);return true;},
   invokeStash:(cmd,fields,cb)=>{if(f.state!=='idle')return false;f.writes.push({cmd,fields});f.state='write_pending';
    const settle=()=>{const accepted=[],blocked=[];for(const ref of fields.entries){const row=f.rows.find(r=>r.entryId===ref.entryId);if(f.full&&row.item.itemKind==='equipment'){blocked.push({entryId:ref.entryId,reason:'inventory_full'});continue;}
     const destination=row.item.name==='普通hp药剂'?'药剂栏':row.item.majorType==='材料'?'材料':'背包';
     if(fields.target&&destination!=='背包'){blocked.push({entryId:ref.entryId,reason:'target_incompatible'});continue;}
     let slot;if(destination==='背包'){slot=fields.target?fields.target.slot:0;while(!fields.target&&f.bag[slot])slot++;f.bag[slot]={...row.item,quantity:ref.quantity};}
     if(destination==='药剂栏')f.drugQuantity=(f.drugQuantity||0)+ref.quantity;
     accepted.push({entryId:ref.entryId,quantity:ref.quantity,destination,...(fields.target?{slot}:{})});row.quantity-=ref.quantity;row.item.quantity=row.quantity;row.revision++;}
     f.rows=f.rows.filter(r=>r.quantity>0);f.revision++;f.state='idle';cb({success:true,accepted,blocked},true);};
    if(f.unknown){f.state='needs_reconcile';f.pendingSettle=settle;}else setTimeout(settle,10);return true;},
   reconcile:()=>{f.queries++;f.unknown=false;setTimeout(f.pendingSettle,10);return true;}};
  f.shell=new Workbench.DualPaneShell({profile:'transfer-pair',title:'战备箱',status:'同步中',leftLabel:'背包',rightLabel:'战备箱'});
  f.root=f.shell.getRoot();f.root.classList.add('kshop-workbench','inventory-workbench-panel');f.root.setAttribute('data-workbench-skin','inventory');f.root.style.cssText='position:relative;width:1024px;height:576px';document.body.appendChild(f.root);
  f.density=new Workbench.GridDensityController({panelId:'stash-test',defaultMode:'compact'});
  const context={view:'build',epoch:1,storageReady:false,panelInstanceId:'stash.fixture',runtimeConfig:{},shell:f.shell};
  window.InventoryWorkbenchFeatureLoader={loadFeature:()=>Promise.resolve()};
  const openStorage=next=>{context.storageReady=InventoryStorageWorkbench.activate({profileConfig:InventoryWorkbenchConfig.resolveProfile({profile:'battlebox'}),
    ownerPanel:'workbench',panelInstanceId:'stash.fixture',shell:f.shell,root:f.root,densityController:f.density,
    isPanelActive:()=>true,addHeaderAction:node=>f.shell.addHeaderAction(node),requestStorageSource:source=>f.switch(source)},next);
    f.firstReadOwner=InventoryStorageWorkbench.debugState().coordinator.busyOwner;
    context.view=next;f.stashNav.onView(next);return context.storageReady;};
  f.stashNav=InventoryWorkbenchStashNavigation.create({context:()=>context,storage:InventoryStorageWorkbench,active:()=>true,
   authorityModule:{create:()=>({acquire:cb=>cb({itemUse:f.itemUse}),release:()=>{},canClose:()=>true,destroy:()=>{},debugState:()=>({session:null})})},requestView:openStorage});
  f.switch=next=>f.stashNav.request(next);
  if(entryRoute==='battlebox')openStorage('storage');
  else if(!f.stashNav.request('stash'))throw Error('direct stash entry rejected');
 },entryRoute);
 if(entryRoute==='battlebox'){
  await page.waitForFunction(()=>InventoryStorageWorkbench.debugState().coordinator.ready);
  await hoverText('.inventory-owned-warehouse [data-physical-slot="0"]','战备箱测试步枪');
  await hoverText('.inventory-owned-backpack [data-physical-slot="0"]','背包测试弹药');
  await page.locator('.inventory-source-action').click();
 }
 await page.waitForFunction(()=>InventoryStorageWorkbench.getSource()==='stash'&&document.querySelectorAll('[data-entry-id]').length===32,{},{timeout:10000});
 assert.strictEqual(await page.evaluate(()=>fixture.firstReadOwner),'bootstrap');
 assert.strictEqual(await page.locator('.workbench-slot').count(),2);assert.strictEqual(await page.locator('.character-build-stash').count(),0);
 // 不经筛选/翻页重建格子：直接验证用户遇到的第一次进入及往返。
 await hoverText('[data-entry-id="s.e0"]','恢复体力，加速伤口愈合');
 await hoverText('.inventory-owned-backpack [data-physical-slot="0"]','背包测试弹药');
 for(let cycle=0;cycle<3;cycle++){
  await page.locator('.inventory-source-action').click();await page.waitForFunction(()=>InventoryStorageWorkbench.getSource()==='container');
  await hoverText('.inventory-owned-warehouse [data-physical-slot="0"]','战备箱测试步枪');
  await hoverText('.inventory-owned-backpack [data-physical-slot="0"]','背包测试弹药');
  await page.locator('.inventory-source-action').click();await page.waitForFunction(()=>InventoryStorageWorkbench.getSource()==='stash');
  await hoverText('[data-entry-id="s.e0"]','恢复体力，加速伤口愈合');
  assert.strictEqual(await page.evaluate(()=>PanelTooltip.debugState().detachedBindingCount),0);
 }
 await page.evaluate(()=>{fixture.holdTooltip=true;});
 await page.locator('[data-entry-id="s.e2"]').hover();await page.waitForFunction(()=>fixture.delayedTooltip);
 await page.locator('.inventory-source-action').click();await page.waitForFunction(()=>InventoryStorageWorkbench.getSource()==='container');
 await hoverText('.inventory-owned-warehouse [data-physical-slot="0"]','战备箱测试步枪');
 await page.evaluate(()=>{fixture.holdTooltip=false;fixture.delayedTooltip();});
 assert((await page.locator('#panel-tooltip').innerText()).includes('战备箱测试步枪'),'retired source reply must not replace the current tooltip');
 assert.strictEqual(await page.evaluate(()=>PanelTooltip.debugState().detachedBindingCount),0);
 await page.locator('.inventory-source-action').click();await page.waitForFunction(()=>InventoryStorageWorkbench.getSource()==='stash');
 await page.locator('.inventory-owned-warehouse [data-filter-path$="material"]').click();
 await page.waitForFunction(()=>document.querySelectorAll('[data-entry-id]').length===10);
 assert.strictEqual(await page.evaluate(()=>fixture.reads.at(-1).spec.major),'material');
 await page.locator('.inventory-source-action').click();await page.waitForFunction(()=>InventoryStorageWorkbench.getSource()==='container');
 await page.locator('.inventory-source-action').click();await page.waitForFunction(()=>document.querySelectorAll('[data-entry-id]').length===32);
 await page.locator('[data-quick-mode="withdraw"]').click();await page.locator('.inventory-select-page').click();
 assert.strictEqual(await page.evaluate(()=>InventoryStorageWorkbench.debugState().quickTransfer.pending),32);
 await page.locator('.inventory-page-next').click();await page.waitForFunction(()=>document.querySelector('[data-entry-id="s.e32"]'));
 assert.strictEqual(await page.evaluate(()=>InventoryStorageWorkbench.debugState().quickTransfer.pending),0);
 await page.locator('.inventory-page-prev').click();await page.waitForFunction(()=>document.querySelector('[data-entry-id="s.e0"]'));
 await page.screenshot({path:path.join(root,'tmp/stash-shared-20260912/shared-storage-initial.png')});
 await page.locator('[data-entry-id="s.e0"]').hover();
 await page.waitForFunction(()=>document.getElementById('panel-tooltip').textContent.includes('恢复体力，加速伤口愈合'));
 assert((await page.locator('#panel-tooltip').innerText()).includes('HP+150'));
 await page.locator('[data-entry-id="s.e1"]').click();
 assert.strictEqual(await page.locator('.workbench-modal').count(),0);
 await page.locator('.inventory-inline-quantity input[type="number"]').fill('3');
 await page.locator('.inventory-owned-backpack [data-physical-slot="4"]').click();
 await page.waitForFunction(()=>fixture.bag[4]&&fixture.bag[4].quantity===3&&!InventoryStorageWorkbench.debugState().coordinator.busyOwner);
 assert.deepStrictEqual(await page.evaluate(()=>fixture.writes[0].fields.entries),[{entryId:'s.e1',revision:1,quantity:3}]);
 assert.strictEqual(await page.evaluate(()=>fixture.writes[0].fields.target.slot),4);
 await page.locator('[data-entry-id="s.e0"]').click();
 await page.screenshot({path:path.join(root,'tmp/stash-shared-20260912/shared-inline-quantity.png')});
 const drugBefore=await page.evaluate(()=>fixture.writes.length);
 await page.locator('.inventory-inline-quantity input[type="number"]').fill('13');
 assert(await page.locator('.inventory-move-selected').isDisabled());
 await page.locator('[data-entry-id="s.e0"]').click({modifiers:['Control']});
 assert.strictEqual(await page.evaluate(()=>fixture.writes.length),drugBefore);
 await page.locator('.inventory-inline-quantity input[type="number"]').fill('3');
 await page.locator('.inventory-move-selected').click();
 await page.waitForFunction(()=>fixture.drugQuantity===3&&!InventoryStorageWorkbench.debugState().coordinator.busyOwner);
 assert.strictEqual(await page.evaluate(()=>fixture.writes.at(-1).fields.target),undefined);
 await page.locator('[data-entry-id="s.e0"]').click();
 assert.strictEqual(await page.locator('.inventory-inline-quantity input[type="number"]').inputValue(),'9');
 await page.locator('.inventory-move-selected').click();
 await page.waitForFunction(()=>fixture.drugQuantity===12&&!InventoryStorageWorkbench.debugState().coordinator.busyOwner);
 assert(await page.evaluate(()=>fixture.messages.some(m=>m.includes('药剂栏'))));
 const dragBefore=await page.evaluate(()=>fixture.writes.length);
 const dragStart=await page.locator('[data-entry-id="s.e2"]').boundingBox(),dragEnd=await page.locator('.inventory-owned-backpack [data-physical-slot="5"]').boundingBox();
 await page.mouse.move(dragStart.x+dragStart.width/2,dragStart.y+dragStart.height/2);await page.mouse.down();
 await page.mouse.move(dragEnd.x+dragEnd.width/2,dragEnd.y+dragEnd.height/2,{steps:12});await page.mouse.up();
 await page.waitForFunction(n=>fixture.writes.length===n+1&&fixture.bag[5]&&!InventoryStorageWorkbench.debugState().coordinator.busyOwner,dragBefore);
 assert.strictEqual(await page.evaluate(()=>fixture.writes.at(-1).fields.target.slot),5);
 assert.strictEqual(await page.evaluate(()=>fixture.writes.at(-1).fields.entries[0].entryId),'s.e2');
 await page.locator('[data-entry-id="s.e1"]').click();
 await page.locator('.inventory-inline-quantity input[type="range"]').press('Home');
 await page.locator('.inventory-inline-quantity input[type="range"]').press('ArrowRight');
 assert.strictEqual(await page.locator('.inventory-inline-quantity input[type="number"]').inputValue(),'2');
 const stackStart=await page.locator('[data-entry-id="s.e1"]').boundingBox(),stackEnd=await page.locator('.inventory-owned-backpack [data-physical-slot="6"]').boundingBox();
 await page.mouse.move(stackStart.x+stackStart.width/2,stackStart.y+stackStart.height/2);await page.mouse.down();
 await page.mouse.move(stackEnd.x+stackEnd.width/2,stackEnd.y+stackEnd.height/2,{steps:12});await page.mouse.up();
 await page.waitForFunction(()=>fixture.bag[6]&&!InventoryStorageWorkbench.debugState().coordinator.busyOwner);
 assert.strictEqual(await page.evaluate(()=>fixture.bag[6].quantity),2);
 await page.locator('.inventory-page-next').click();await page.waitForFunction(()=>document.querySelector('[data-entry-id="s.e35"]'));
 const before=await page.evaluate(()=>fixture.writes.length);
 await page.locator('[data-entry-id="s.e35"]').click({modifiers:['Control']});await page.waitForFunction(n=>fixture.writes.length===n+1&&fixture.state==='idle'&&!InventoryStorageWorkbench.debugState().coordinator.busyOwner,before);
 await page.locator('.inventory-source-action').click();await page.waitForFunction(()=>InventoryStorageWorkbench.getSource()==='container');
 await page.locator('.inventory-source-action').click();await page.waitForFunction(()=>InventoryStorageWorkbench.getSource()==='stash'&&document.querySelector('[data-entry-id="s.e1"]'));
 await page.evaluate(()=>{fixture.full=true;});await page.locator('[data-quick-mode="withdraw"]').click();await page.locator('[data-entry-id="s.e3"]').click();await page.locator('[data-entry-id="s.e1"]').click();
 await page.locator('.inventory-quick-transfer-commit').click();await page.waitForFunction(()=>!InventoryStorageWorkbench.debugState().quickTransfer.committing&&fixture.writes.length>=3);
 assert(await page.evaluate(()=>fixture.messages.some(m=>m.includes('仍保留在暂存'))));
 await page.locator('.inventory-page-next').click();await page.waitForFunction(()=>document.querySelector('[data-entry-id="s.e40"]'));
 await page.evaluate(()=>{fixture.unknown=true;});await page.locator('[data-entry-id="s.e40"]').click({modifiers:['Control']});await page.waitForFunction(()=>fixture.state==='needs_reconcile');
 assert.strictEqual(await page.evaluate(()=>fixture.switch('container')),false);
 assert.strictEqual(await page.evaluate(()=>InventoryStorageWorkbench.prepareClose('close',()=>{})),false);
 const issued=await page.evaluate(()=>fixture.writes.length);await page.getByRole('button',{name:'核对领取结果',exact:true}).click();
 await page.waitForFunction(()=>fixture.state==='idle'&&!InventoryStorageWorkbench.debugState().coordinator.busyOwner);assert.strictEqual(await page.evaluate(()=>fixture.writes.length),issued);assert.strictEqual(await page.evaluate(()=>fixture.queries),1);
 assert.deepStrictEqual(errors,[]);const geometry=await page.evaluate(()=>({width:document.documentElement.scrollWidth,height:fixture.root.getBoundingClientRect().height}));assert(geometry.width<=1024&&geometry.height<=576,JSON.stringify(geometry));
 fs.mkdirSync(path.join(root,'tmp/stash-shared-20260912'),{recursive:true});await page.screenshot({path:path.join(root,'tmp/stash-shared-20260912/shared-storage.png')});
 await page.evaluate(()=>{fixture.stashNav.destroy();InventoryStorageWorkbench.deactivate();fixture.shell.destroy();fixture.density.destroy();});
 assert.strictEqual(await page.evaluate(()=>PanelTooltip.debugState().bindingCount),0);
 await page.close();
 console.log('Immediate tooltip lifecycle passed for '+entryRoute+' entry, three source round trips, late retired-source reply and close cleanup.');
 }
 console.log('Shared storage DOM: production tooltip envelope, inline quantity, explicit partial/full potion claim, invalid quantity, exact target, pointer drag, Ctrl, paging, source reuse, non-prefix batch, unknown reconciliation, close lock and 1024x576 passed.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
