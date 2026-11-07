'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const vm=require('node:vm');
const {loadStaticClass}=require('../cf6-soldier-assets/offline/as2-source');
const context=vm.createContext({isFinite,Math});
vm.runInContext('var PersistedSnapshot={cloneData:function(v){return JSON.parse(JSON.stringify(v));},cloneArrayData:function(v){return JSON.parse(JSON.stringify(v));}};',context);
const rules=loadStaticClass(context,path.resolve(__dirname,'../../scripts/类定义/org/flashNight/arki/scene/Cf6SoldierLootRules.as'),'Cf6SoldierLootRules');
const data=value=>vm.runInContext('JSON.parse('+JSON.stringify(JSON.stringify(value))+')',context);
const plain=value=>JSON.parse(JSON.stringify(value));
const weapon=(name='G1111',shot=3)=>({name,lastUpdate:100,value:{level:13,mods:[],shot,reloadCount:7,
  subweaponShot:2,subweaponReloadCount:1,isRocketMode:false,ammoState:{v:1,capacity:15,paidNormal:2,reserve:8},
  customField:{kept:true},__serializedExtension:{retained:17}}});
function snapshot(){return data({primary:weapon(),left:weapon('MP7',4),right:weapon('MP7',9),material:'透镜',lastUpdate:123,
  primaryAmmo:{capacity:15,clipname:'突击步枪通用弹药'},leftAmmo:{capacity:40,clipname:'冲锋枪通用弹药'},
  rightAmmo:{capacity:40,clipname:'冲锋枪通用弹药'},subAmmo:null});}
function header(id='person1'){return data({sourceKey:'run1.'+id,unitIdentity:id,spawnIdentity:'world1.'+id,
  rosterVersion:'fixed158-v2',configurationFingerprint:'fixed158-v2|candidate1'});}
function roll(hit=true,reason=hit?'roll_hit':'roll_miss',evaluated=true){return data({recorded:true,gateEvaluated:evaluated,
  reason,nominalPercent:10,luckBonus:0.5,prdPoolKey:'cf6.fixed158.major',hit});}
const packs=(rounds,reserve,capacity)=>Math.max(0,Math.ceil((rounds-reserve)/capacity));
function packet(kind='longgun',id='person1',snap=snapshot()){
  return rules.packet(header(id),snap,kind,roll(kind!=='none'),rules.ammoQuote(snap,kind,packs));
}
const weights=data({longgun:45,sidearm_pair:35,mod_material:20});

test('fresh ledger is valid; unknown schema and mismatched counts are refused',()=>{
  const l=rules.create('fixed158-v2','candidate1');assert.equal(rules.validLedger(l),true);
  l.v=3;assert.equal(rules.validLedger(l),false);l.v=2;l.packages=1;assert.equal(rules.validLedger(l),false);
});
test('full item snapshot retains false Boolean, ammunition, unknown serialized fields and independent copies',()=>{
  const s=snapshot(),p=packet('longgun','a',s);
  assert.equal(rules.validPacket(p),true);assert.deepEqual(plain(p.items[0]),plain(s.primary));
  s.primary.value.ammoState.reserve=99;s.primary.value.isRocketMode=true;s.primary.value.mods.push('changed');
  assert.equal(p.items[0].value.ammoState.reserve,8);assert.equal(p.items[0].value.isRocketMode,false);
  assert.equal(p.items[0].value.mods.length,0);assert.equal(p.items[0].value.__serializedExtension.retained,17);
});
test('same-name dual guns remain two exact instances with separate spent ammunition',()=>{
  const p=packet('sidearm_pair');assert.equal(rules.validPacket(p),true);
  assert.equal(p.items.length,2);assert.notEqual(p.items[0].value,p.items[1].value);
  assert.deepEqual(p.items.map(x=>x.value.shot).join(','),'4,9');
  p.items[0].value.shot=100;assert.equal(p.items[1].value.shot,9);
});
test('same ammunition for two hands sums to two full ordinary reloads',()=>{
  const result=rules.ammoQuote(snapshot(),'sidearm_pair',packs);
  assert.deepEqual(plain(result),[{name:'冲锋枪通用弹药',value:2,lastUpdate:123}]);
});
test('different ammunition for two hands is quoted separately',()=>{
  const s=snapshot();s.rightAmmo.clipname='手枪通用弹药';s.rightAmmo.capacity=7;
  assert.deepEqual(plain(rules.ammoQuote(s,'sidearm_pair',packs)),[
    {name:'冲锋枪通用弹药',value:1,lastUpdate:123},{name:'手枪通用弹药',value:1,lastUpdate:123}]);
});
test('primary and actual on-load subweapon cost are in one packet',()=>{
  const s=snapshot();s.subAmmo=data({capacity:3,reserveName:'12号霰弹弹药',consumeMode:'onLoadGroup',clipCostPerLoad:1});
  const p=packet('longgun','a',s);assert.equal(rules.validPacket(p),true);
  assert.deepEqual(plain(p.consumables),[{name:'突击步枪通用弹药',value:1,lastUpdate:123},{name:'12号霰弹弹药',value:1,lastUpdate:123}]);
  assert.equal(p.items[0].value.subweaponShot,2);assert.equal(p.items[0].value.shot,3);
});
test('on-fire group costs multiply actual capacity and aggregate by exact name',()=>{
  const s=snapshot();s.subAmmo=data({capacity:3,reserveName:'突击步枪通用弹药',consumeMode:'onFire',fireCost:2});
  assert.equal(rules.ammoQuote(s,'longgun',packs)[0].value,7);
});
test('material and no-drop outcomes receive no ammunition',()=>{
  for(const kind of ['mod_material','none']){
    const p=packet(kind);assert.equal(p.consumables.length,0);assert.equal(rules.validPacket(p),true);
  }
});
test('unknown consume modes and nonintegral inventory costs fail the quote',()=>{
  for(const sub of [{capacity:3,reserveName:'a',consumeMode:'guess',clipCostPerLoad:1},
    {capacity:3,reserveName:'a',consumeMode:'onLoadGroup',clipCostPerLoad:0.5},
    {capacity:3,reserveName:'a',consumeMode:'onFire',fireCost:-1}]){
    const s=snapshot();s.subAmmo=data(sub);assert.equal(rules.ammoQuote(s,'longgun',packs),null);
  }
});
test('reference quote delegates ordinary capacity without mutating saved live balance',()=>{
  const s=snapshot(),before=JSON.stringify(s),calls=[];
  rules.ammoQuote(s,'sidearm_pair',(rounds,reserve,cap)=>{calls.push([rounds,reserve,cap]);return packs(rounds,reserve,cap);});
  assert.deepEqual(calls,[[40,0,40],[40,0,40]]);assert.equal(JSON.stringify(s),before);
});
test('no invalid ordinary capacity or missing inventory name is guessed',()=>{
  for(const value of [0,-1,0.5,Infinity,NaN]){const s=snapshot();s.primaryAmmo.capacity=value;assert.equal(rules.ammoQuote(s,'longgun',packs),null);}
  const s=snapshot();s.primaryAmmo.clipname='';assert.equal(rules.ammoQuote(s,'longgun',packs),null);
});
test('one identity cannot reserve again with a new actor or spawn token',()=>{
  const l=rules.create('fixed158-v2','candidate1'),p=packet();
  assert.equal(rules.reserve(l,p),true);p.spawnIdentity='replacement';assert.equal(rules.reserve(l,p),false);
  assert.equal(l.packages,1);assert.equal(rules.validLedger(l),true);
});
test('decision hits reserve chapter quota before admission and retain it while pending',()=>{
  const l=rules.create('fixed158-v2','candidate1'),p=packet('sidearm_pair');rules.reserve(l,p);
  assert.equal(l.weaponInstances,2);assert.equal(l.pairs,1);
  const stored=l.records['u.person1'];stored.state='COMMIT_PENDING';assert.equal(rules.validLedger(l),true);
  stored.state='OWNED';assert.equal(rules.validLedger(l),true);assert.equal(l.weaponInstances,2);
});
test('chapter package cap is six with no missing-person compensation',()=>{
  const l=rules.create('fixed158-v2','candidate1');
  for(let i=0;i<6;i++)assert.equal(rules.reserve(l,packet('longgun','p'+i)),true);
  assert.equal(rules.reserve(l,packet('longgun','extra')),false);assert.equal(rules.available(l,snapshot(),weights).total,0);
  assert.equal(l.packages,6);assert.equal(rules.validLedger(l),true);
});
test('pair cap two and weapon instance cap eight are enforced independently',()=>{
  const l=rules.create('fixed158-v2','candidate1');
  for(let i=0;i<2;i++)assert.equal(rules.reserve(l,packet('sidearm_pair','d'+i)),true);
  assert.equal(rules.reserve(l,packet('sidearm_pair','d2')),false);
  assert.equal(rules.available(l,snapshot(),weights).sidearm_pair,0);
  for(let i=0;i<4;i++)assert.equal(rules.reserve(l,packet('longgun','r'+i)),true);
  assert.equal(l.weaponInstances,8);assert.equal(rules.validLedger(l),true);
});
test('material cap is two and does not spend weapon quota',()=>{
  const l=rules.create('fixed158-v2','candidate1');
  assert.equal(rules.reserve(l,packet('mod_material','m1')),true);assert.equal(rules.reserve(l,packet('mod_material','m2')),true);
  assert.equal(rules.reserve(l,packet('mod_material','m3')),false);assert.equal(l.weaponInstances,0);
  assert.equal(rules.available(l,snapshot(),weights).mod_material,0);
});
test('quota and eligibility are filtered before a weighted category choice',()=>{
  const l=rules.create('fixed158-v2','candidate1'),s=snapshot();s.left=null;s.right=null;
  const pool=rules.available(l,s,weights);assert.equal(pool.sidearm_pair,0);
  assert.equal(rules.choose(pool,0),'longgun');assert.equal(rules.choose(pool,0.9999),'mod_material');
  assert.equal(rules.choose(pool,1),'none');assert.equal(rules.choose(pool,-1),'none');
});
test('miss and pre-roll ineligible decisions are recorded without package reservation',()=>{
  const l=rules.create('fixed158-v2','candidate1'),s=snapshot();
  for(const reason of ['roll_miss','quota_exhausted','ineligible']){
    const p=rules.packet(header(reason),s,'none',roll(false,reason,reason==='roll_miss'),data([]));
    assert.equal(rules.reserve(l,p),true);
  }
  assert.equal(l.packages,0);assert.equal(Object.keys(l.records).length,3);assert.equal(rules.validLedger(l),true);
});
test('NPC action ownership and target fields cannot enter a reward',()=>{
  for(const key of ['cf6G1111FixedMode','__cf6G1111','autoTarget','dangerPermit','cf6DamageGroup']){
    const s=snapshot();s.primary.value[key]=false;assert.equal(rules.validWeapon(s.primary),false,key);
  }
});
test('G1111 false is required as a Boolean, never a string or absent default',()=>{
  const s=snapshot();assert.equal(rules.validWeapon(s.primary),true);
  s.primary.value.isRocketMode='false';assert.equal(rules.validWeapon(s.primary),false);
  delete s.primary.value.isRocketMode;assert.equal(rules.validWeapon(s.primary),false);
});
test('malformed packet shape cannot become a third gun or ammunition-only award',()=>{
  const p=packet('sidearm_pair');p.items.push(p.items[0]);assert.equal(rules.validPacket(p),false);
  const empty=packet('longgun');empty.items=[];assert.equal(rules.validPacket(empty),false);
  const material=packet('mod_material');material.consumables=data([{name:'a',value:1,lastUpdate:1}]);assert.equal(rules.validPacket(material),false);
});
test('duplicate consumable names and duplicate record source keys are rejected on reload',()=>{
  const p=packet();p.consumables.push(p.consumables[0]);assert.equal(rules.validPacket(p),false);
  const l=rules.create('fixed158-v2','candidate1');rules.reserve(l,packet('longgun','a'));
  const b=packet('longgun','b');b.sourceKey=l.records['u.a'].sourceKey;assert.equal(rules.reserve(l,b),false);
  l.records['u.b']=b;l.packages++;l.weaponInstances++;assert.equal(rules.validLedger(l),false);
});
test('roll chance is probabilistic data, never an implicit guaranteed top-gun award',()=>{
  const policy=require('./soldier-loot-policy.source.json');
  for(const row of Object.values(policy.profiles))assert.ok(row.nominalPercent>0&&row.nominalPercent<100);
  assert.deepEqual(policy.caps,{packages:6,pairs:2,weaponInstances:8,materials:2});
});
test('invalid weapon numbers, duplicate mods and runtime functions fail before the gate',()=>{
  const s=snapshot();s.primary.value.shot=NaN;assert.equal(rules.validWeapon(s.primary),false);
  s.primary.value.shot=0;s.primary.value.mods=data(['m','m']);assert.equal(rules.validWeapon(s.primary),false);
  s.primary.value.mods=data([]);s.primary.value.callback=()=>{};assert.equal(rules.validWeapon(s.primary),false);
});
test('reserved packets do not alias the input plan or its equipment values',()=>{
  const l=rules.create('fixed158-v2','candidate1'),p=packet();rules.reserve(l,p);
  p.items[0].value.shot=99;p.consumables[0].value=99;p.roll.reason='changed';
  assert.equal(l.records['u.person1'].items[0].value.shot,3);
  assert.equal(l.records['u.person1'].consumables[0].value,1);
  assert.equal(l.records['u.person1'].roll.reason,'roll_hit');
});

test('known cold AMF0 empty arrays repair without revising historical outcomes or source data',()=>{
  const l=rules.create('earlier-roster','earlier-policy');rules.reserve(l,packet('longgun','a'));
  rules.reserve(l,packet('none','b'));
  l.records['u.a'].items[0].value.mods=data({});l.records['u.b'].items=data({});l.records['u.b'].consumables=data({});
  const before=JSON.stringify(l),r=rules.normalizeLedger(l);
  assert.equal(r.ok,true);assert.equal(r.changed,true);assert.equal(JSON.stringify(l),before);
  assert.equal(rules.validLedger(r.feature),true);assert.equal(r.feature.rosterVersion,'earlier-roster');
  assert.equal(r.feature.records['u.a'].items[0].value.isRocketMode,false);
  assert.equal(r.feature.records['u.b'].state,'DECIDED_MISS');
  assert.equal(rules.normalizeLedger(r.feature).changed,false);
});

test('cold normalization rejects future schema and malformed nonempty objects without erasure',()=>{
  const l=rules.create('v1','p1');rules.reserve(l,packet());
  l.records['u.person1'].items[0].value.mods=data({wrong:'mod'});
  const before=JSON.stringify(l);assert.equal(rules.normalizeLedger(l).ok,false);assert.equal(JSON.stringify(l),before);
  l.v=99;assert.equal(rules.normalizeLedger(l).ok,false);
  assert.equal(rules.normalizeSaveData(data({ext:{bookRun:{oldField:17}}})),true);
});

test('first-weapon guard respects eligibility, existing captures, packet availability and typed threshold',()=>{
  const ledger=rules.create('fixed158-v2','candidate2');
  for(let i=0;i<7;i++)assert.equal(rules.reserve(ledger,packet('none','miss'+i)),true);
  const policy=data({firstWeaponGuarantee:{afterEligibleDeaths:8}}),pool=rules.available(ledger,snapshot(),weights);
  assert.equal(rules.firstWeaponDue(ledger,pool,policy,true),true);
  assert.equal(rules.firstWeaponDue(ledger,pool,policy,false),false);
  pool.longgun=0;assert.equal(rules.firstWeaponDue(ledger,pool,policy,true),false);pool.longgun=45;
  for(const threshold of [0,'8',8.5,159]){policy.firstWeaponGuarantee.afterEligibleDeaths=threshold;assert.equal(rules.firstWeaponDue(ledger,pool,policy,true),false);}
  policy.firstWeaponGuarantee.afterEligibleDeaths=8;ledger.weaponInstances=1;
  assert.equal(rules.firstWeaponDue(ledger,pool,policy,true),false);
});
test('guarantee packet requires complete evidence and exact quota reservation ordinal',()=>{
  const ledger=rules.create('fixed158-v2','candidate2');for(let i=0;i<7;i++)rules.reserve(ledger,packet('none','m'+i));
  const p=packet('longgun','guarantee');p.roll.reason='first_weapon_guarantee';
  assert.equal(rules.validPacket(p),false);Object.assign(p.roll,{naturalHit:false,guaranteeAfter:8,eligibleOrdinal:8});
  assert.equal(rules.validPacket(p),true);p.roll.eligibleOrdinal=9;assert.equal(rules.reserve(ledger,p),false);
  p.roll.eligibleOrdinal=8;assert.equal(rules.reserve(ledger,p),true);assert.equal(rules.validLedger(ledger),true);
  const duplicate=packet('longgun','other');Object.assign(duplicate.roll,{reason:'first_weapon_guarantee',naturalHit:false,guaranteeAfter:8,eligibleOrdinal:9});
  assert.equal(rules.reserve(ledger,duplicate),false);assert.equal(ledger.packages,1);assert.equal(ledger.weaponInstances,1);
});

test('missing ledger cannot silently reserve a valid packet in AVM1',()=>{
  assert.equal(rules.reserve(null,packet('longgun','missing-ledger')),false);
  assert.equal(rules.reserve(data({}),packet('longgun','missing-records')),false);
});
