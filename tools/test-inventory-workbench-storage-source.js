'use strict';
const assert = require('assert');
const Source = require('../launcher/web/modules/inventory-workbench-storage-source.js');
let passed = 0;
function test(name, run) { run(); console.log('ok '+(++passed)+' - '+name); }
function fixture() {
 const events=[], reads=[]; let writes=0, queries=0, destroyCount=0, settled, bagCallback;
 const base={opened:true,ready:true,busyOwner:null,refreshRequired:false};
 let snapshot={storeId:'s',revision:1,offset:0,total:1,unfilteredTotal:1,filterSpec:{major:'all'},slots:[{entryId:'s.e1',revision:1,quantity:8,occupied:true,item:{name:'a',quantity:8,itemKind:'stack'}}]};
 let leafState={ready:true,loading:false,needsReconcile:false,itemState:'idle'};
 const leaf={getSnapshot:()=>snapshot,getState:()=>leafState,getRow:id=>snapshot.slots.find(row=>row.entryId===id),ref:(row,quantity)=>({entryId:row.entryId,revision:row.revision,quantity:quantity===undefined?row.quantity:quantity}),
  refresh:cb=>{reads.push(cb);events.push('stash.read');return true;},take:(refs,target,cb)=>{writes++;settled=cb;events.push('write');leafState.itemState='write_pending';leaf.last={refs,target};return true;},
  reconcile:()=>{queries++;events.push('query');return true;},destroy:()=>destroyCount++,tooltip:()=>true,
  setPage:(_,cb)=>leaf.refresh(cb),setFilter:(_,cb)=>leaf.refresh(cb)};
 const coordinator={debugState:()=>({...base}),getWindow:()=>({slots:[]}),getRequest:()=>({offset:0,limit:50}),
  beginExternalWrite:()=>{if(base.busyOwner||base.refreshRequired)return false;base.busyOwner='stash.take';events.push('owner');return {};},
  completeExternalWrite:(_,refresh,cb)=>{if(!refresh){base.busyOwner=null;cb({success:true});return true;}events.push('bag.read');bagCallback=cb;return true;},
  retryRefresh:cb=>{events.push('bag.retry');base.busyOwner='refresh.retry';bagCallback=cb;return true;}};
 const use={resumeStash:(id,cb)=>{queries++;use.resumed=id;use.callback=cb;return true;},invokeStash:(cmd,fields,cb)=>{writes++;use.command=cmd;use.fields=fields;settled=cb;return true;}};
 const source=Source.create({coordinator,adapterFactory:()=>leaf,onChange:()=>events.push('state')});
 function adopt(value=snapshot){snapshot=value;leafState.loading=false;reads.shift()(value,{success:true});events.push('stash.adopted');}
 function resolve(result={success:true,accepted:[{entryId:'s.e1',quantity:3,destination:'背包',slot:4}],blocked:[]}) {leafState={ready:true,loading:false,itemState:'idle',needsReconcile:false};settled(result,true);}
 function bag(ok=true){base.busyOwner=null;base.ready=ok;base.refreshRequired=!ok;events.push('bag.adopted');bagCallback({success:ok});}
 function enter(){assert(source.switchSource('stash',{itemUse:use},ok=>assert(ok)));adopt();}
 return {source,base,leaf,use,events,reads,enter,adopt,resolve,bag,
  ref:()=>source.slotRef('stash',snapshot.slots[0],3),snapshot:()=>snapshot,
  unknown:()=>{leafState.itemState='needs_reconcile';leafState.needsReconcile=true;},
  counts:()=>({writes,queries,destroyCount})};
}
test('empty projection remains stable and source reads never write',()=>{
 const f=fixture();f.source.switchSource('stash',{itemUse:f.use},()=>{});
 const empty={storeId:'',revision:0,total:0,unfilteredTotal:0,offset:0,filterSpec:{major:'all'},slots:[]};f.adopt(empty);
 const a=f.source.getWindow('stash');assert.strictEqual(a,f.source.getWindow('stash'));assert.strictEqual(a.capacity,0);assert.strictEqual(f.counts().writes,0);
 f.source.destroy();
});
test('real stash IDs and exact target cross the boundary without view metadata',()=>{
 const f=fixture();f.enter();let done=0;const ref=f.ref();
 assert(!('physicalSlot' in ref));assert(!('expectedLease' in ref));
 assert(f.source.take([ref],{containerId:'背包',slot:4,expectedLease:'L4',item:{name:'x'},occupied:false},()=>done++));
 assert.deepStrictEqual(f.leaf.last,{refs:[{entryId:'s.e1',revision:1,quantity:3}],target:{containerId:'背包',slot:4,expectedLease:'L4'}});
 assert.strictEqual(f.source.switchSource('container',{},()=>{}),false);
 f.resolve();assert.strictEqual(done,0);assert.strictEqual(f.base.busyOwner,'stash.take');
 f.adopt({...f.snapshot(),revision:2});assert.strictEqual(done,0);assert.strictEqual(f.base.busyOwner,'stash.take');
 f.bag();assert.strictEqual(done,1);assert.strictEqual(f.base.busyOwner,null);f.source.destroy();
});
test('unknown write retries only the original query and keeps the shared owner',()=>{
 const f=fixture();f.enter();let done=0;f.source.take([f.ref()],null,()=>done++);f.unknown();
 assert(f.source.state(f.base).needsReconcile);assert(f.source.retry());assert.deepStrictEqual(f.counts(),{writes:1,queries:1,destroyCount:0});assert.strictEqual(done,0);
 f.resolve();f.adopt();f.bag();assert.strictEqual(done,1);f.source.destroy();
});
test('failed stash read retains owner and retries reads without repeating the write',()=>{
 const f=fixture();f.enter();let done=0;f.source.take([f.ref()],null,()=>done++);f.resolve();f.reads.shift()(null,{success:false,error:'timeout'});
 assert.strictEqual(f.base.busyOwner,'stash.take');assert.strictEqual(done,0);assert(f.source.retry());f.adopt();f.bag();assert.strictEqual(done,1);assert.strictEqual(f.counts().writes,1);f.source.destroy();
});
test('failed bag adoption blocks completion until coordinator retry adopts it',()=>{
 const f=fixture();f.enter();let done=0;f.source.take([f.ref()],null,()=>done++);f.resolve();f.adopt();f.bag(false);
 assert.strictEqual(done,0);assert(f.source.state(f.base).refreshRequired);assert(f.source.retry());f.bag();assert.strictEqual(done,1);assert.strictEqual(f.counts().writes,1);f.source.destroy();
});
test('destroy rejects late page adoption and never takes ownership of itemUse',()=>{
 const f=fixture();let done=0;f.source.switchSource('stash',{itemUse:f.use},()=>done++);f.source.destroy();f.adopt();assert.strictEqual(done,0);assert.strictEqual(f.source.getWindow('stash'),null);assert.strictEqual(f.counts().destroyCount,1);
});
test('page pending root is locked and resumed by its exact original ID',()=>{
 const f=fixture();f.source.switchSource('stash',{itemUse:f.use},()=>{});f.adopt({...f.snapshot(),pendingOperationId:'old.root'});
 assert(!f.source.state(f.base).ready);assert(f.source.state(f.base).busyOwner);let done=0;
 assert(f.source.retry(()=>done++));assert.strictEqual(f.use.resumed,'old.root');assert.strictEqual(f.counts().writes,0);
 f.use.callback({success:true});f.adopt({...f.snapshot(),pendingOperationId:''});f.bag();assert.strictEqual(done,1);f.source.destroy();
});
test('migration is explicit and holds the same owner through both fresh snapshots',()=>{
 const f=fixture();f.source.switchSource('stash',{itemUse:f.use},()=>{});f.adopt({...f.snapshot(),storeId:'',revision:0,migrationRequired:true});assert.strictEqual(f.counts().writes,0);
 let done=0;assert(f.source.retry(()=>done++));assert.strictEqual(f.use.command,'stashMigrate');assert.strictEqual(f.base.busyOwner,'stash.take');
 f.resolve({success:true});f.adopt({...f.snapshot(),storeId:'migrated',migrationRequired:false});f.bag();assert.strictEqual(done,1);f.source.destroy();
});
console.log('Storage source: '+passed+'/'+passed+' passed');
