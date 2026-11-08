'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const path=require('node:path');
const {loadStaticClass}=require('../cf6-soldier-assets/offline/as2-source');
const root=path.resolve(__dirname,'../../scripts/类定义/org/flashNight/arki/scene');
function fixture(){
  const c=vm.createContext({isFinite,Math,length:value=>typeof value==='string'?value.length:0,trace:()=>{}});
  vm.runInContext(`
    var writes=0,rolls=0,choices=0,queries=0,admits=0,notices=0;
    var outcome='committed',gateHit=true,category=0,domainPending=null,saved=null;
    var PersistedSnapshot={cloneData:function(v){return JSON.parse(JSON.stringify(v));},cloneArrayData:function(v){return JSON.parse(JSON.stringify(v));}};
    var _root={savePath:'cf7_test_loot',_saveExt:{bookRun:{bookId:'cf6-sting',routeId:'type61',slot:'cf7_test_loot',seed:7,startedAt:8,planSeed:9,outcome:'active'}},
      getNextHighestDepth:function(){return 1;},createEmptyMovieClip:function(){return {_name:'watcher'};},发布消息:function(){notices++;}};
    var PauseManager={count:0,install:function(){},lease:function(){this.count++;return 'loot';},releaseLease:function(){this.count--;}};
    var Cf6Type61Service={isActive:function(){return true;}},BookDefinition={get:function(){return {type61:{soldiers:config}};}};
    var Cf6SoldierActions={actorValid:function(r){return r.valid;},context:function(){return null;}};
    // This legacy admission model has no world. Real ground transfer is covered in AVM1 with the imported prefab.
    var Cf6SoldierGroundPickup={busy:function(){return false;},tick:function(){},reconcile:function(){},status:function(){return {};}};
    var ItemUtil={isItem:function(n){return n==='透镜';}};
    var DropLuckRoller={getLuckBonus:function(){return .2;},rollDropWithContext:function(key,row,luck,prd){rolls++;prd.state[key]=(prd.state[key]||0)+1;return gateHit;}};
    var LinearCongruentialEngine={instance:{nextFloat:function(){choices++;return category;}}};
    function PseudoRandomDistribution(state){this.state=state;}
    var WeaponAmmoRuntime={quoteInventoryPacks:function(rounds,reserve,capacity){return Math.max(0,Math.ceil((rounds-reserve)/capacity));}};
    function settle(committed){
      var p=domainPending;if(!p)return;
      if(committed)saved=PersistedSnapshot.cloneData(_root._saveExt);
      else _root._saveExt=p.before;
      domainPending=null;p.callback(committed,p.domain);
    }
    var RewardStashService={lastError:'',
      pendingOperationId:function(){return domainPending?domainPending.id:'';},
      begin:function(id,origin,callback,domain){
        if(domainPending)return false;
        domainPending={id:id,callback:callback,domain:domain,before:PersistedSnapshot.cloneData(_root._saveExt)};
        _root._saveExt=PersistedSnapshot.cloneData(_root._saveExt);return true;
      },
      end:function(){writes++;if(outcome==='committed'){settle(true);return {success:true};}
        if(outcome==='not_committed'){settle(false);return {success:false,error:'save_not_committed'};}
        return {success:false,error:'commit_pending'};},
      resume:function(id){queries++;if(!domainPending||id!==domainPending.id)throw Error('wrong query');
        if(outcome==='committed')settle(true);return {};},
      admit:function(items,preferInventory,allowStash){
        if(preferInventory||!allowStash)throw Error('wrong admission');
        admits++;if(outcome==='admission_throw')throw Error('admission_throw');
        var stash=_root._saveExt.stash||(_root._saveExt.stash=[]);
        for(var i=0;i<items.length;i++)stash.push(PersistedSnapshot.cloneData(items[i]));return true;
      },
      cancel:function(){if(domainPending)settle(false);return {success:false,error:'cancelled'};}
    };
  `,c);
  c.config=vm.runInContext('JSON.parse('+JSON.stringify(JSON.stringify({version:'fixed-v2',lootPolicy:require('./soldier-loot-policy.source.json')}))+')',c);
  loadStaticClass(c,path.join(root,'Cf6SoldierLootRules.as'),'Cf6SoldierLootRules');
  const api=loadStaticClass(c,path.join(root,'Cf6SoldierLoot.as'),'Cf6SoldierLoot',['PseudoRandomDistribution']);
  vm.runInContext(`
    _root._saveExt.bookRun.cf6SoldierLoot=Cf6SoldierLootRules.create(config.version,config.lootPolicy.version);
    var actor={cf6UnitIdentity:'A',cf6ProfileId:'p1',cf6RosterVersion:config.version,
      cf6LootProfile:'major_rifle_xor_pair_xor_material',cf6LootMaterial:'透镜',soldierPhase:2,soldierIsElite:true,hp:0,
      cf6ActionRecord:{valid:true,key:'birth.A'},
      长枪:{name:'G1111',lastUpdate:1,value:{level:13,mods:[],shot:4,reloadCount:8,isRocketMode:false,__extra:{kept:1}}},
      手枪:{name:'MP7',lastUpdate:2,value:{level:13,mods:[],shot:2}},
      手枪2:{name:'MP7',lastUpdate:3,value:{level:13,mods:[],shot:7}},
      长枪属性:{capacity:15,clipname:'步枪弹药'},手枪属性:{capacity:40,clipname:'手枪弹药'},手枪2属性:{capacity:40,clipname:'手枪弹药'}};
  `,c);
  // AS2 missing-property reads are permissive; seed the unbound shape explicitly.
  api.context=vm.runInContext('({identity:{}})',c);
  assert.equal(api.bind(c.config),true);
  return {c,api,run:s=>vm.runInContext(s,c)};
}
function death(f){assert.equal(f.api.combatDeath(f.c.actor),true);}
function decide(f){assert.equal(f.api.prepareForTransition(),false);}
function drain(f){for(let i=0;i<5&&!f.api.prepareForTransition();i++);}
function status(f){return JSON.parse(JSON.stringify(f.api.status()));}

test('same-source service freezes exact values, records once and atomically admits paired ammunition',()=>{
  const f=fixture();death(f);f.c.actor.长枪.value.shot=99;
  decide(f);assert.equal(f.c.rolls,1);assert.equal(f.c.admits,0);
  drain(f);assert.equal(f.c.writes,2);assert.equal(f.c.admits,1);
  const item=f.c.saved.stash[0];assert.equal(item.value.shot,4);assert.equal(item.value.isRocketMode,false);assert.equal(item.value.__extra.kept,1);
  assert.equal(f.c.saved.stash[1].value,1);assert.equal(f.c.saved.bookRun.cf6SoldierLoot.records['u.A'].state,'OWNED');
  death(f);drain(f);assert.equal(f.c.rolls,1);assert.equal(f.c.writes,2);assert.equal(f.c.PauseManager.count,0);
});
test('known decision rollback retries the frozen roll and category without extra PRD advancement',()=>{
  const f=fixture();death(f);f.c.outcome='not_committed';decide(f);
  assert.equal(f.c.rolls,1);assert.equal(f.c.choices,1);assert.equal(f.c._root._saveExt.bookRun.cf6SoldierLoot.packages,0);
  f.c.outcome='committed';drain(f);
  assert.equal(f.c.rolls,1);assert.equal(f.c.choices,1);assert.equal(f.c.saved.bookRun.cf6SoldierLoot.prd['cf6.fixed158.major_rifle_xor_pair_xor_material'],1);
  assert.equal(f.c.saved.stash.length,2);
});
test('unknown decision only queries the exact operation; no second roll, write or award',()=>{
  const f=fixture();death(f);f.c.outcome='unknown';decide(f);const id=status(f).operationId;
  for(let i=0;i<3;i++)assert.equal(f.api.prepareForTransition(),false);
  assert.equal(status(f).operationId,id);assert.equal(f.c.writes,1);assert.equal(f.c.rolls,1);assert.equal(f.c.admits,0);
  f.c.outcome='committed';drain(f);assert.equal(f.c.writes,2);assert.equal(f.c.admits,1);assert.equal(f.c.rolls,1);
});
test('unknown admission retains its candidate and package until an exact query resolves it',()=>{
  const f=fixture();death(f);decide(f);f.c.outcome='unknown';assert.equal(f.api.prepareForTransition(),false);
  assert.equal(f.c.admits,1);const id=status(f).operationId;
  f.api.prepareForTransition();assert.equal(status(f).operationId,id);assert.equal(f.c.admits,1);
  f.c.outcome='committed';drain(f);assert.equal(f.c.admits,1);assert.equal(f.c.saved.stash.length,2);assert.equal(f.c.rolls,1);
});
test('known admission failure restores durable hit and retries the same equipment and ammo',()=>{
  const f=fixture();death(f);decide(f);f.c.outcome='admission_throw';decide(f);
  assert.equal(f.c._root._saveExt.stash,undefined);assert.equal(f.c._root._saveExt.bookRun.cf6SoldierLoot.records['u.A'].state,'DECIDED_HIT');
  f.c.outcome='committed';drain(f);assert.equal(f.c.rolls,1);assert.equal(f.c.saved.stash.length,2);assert.equal(f.c.PauseManager.count,0);
});
test('miss is persisted once with no equipment or ammo fallback',()=>{
  const f=fixture();f.c.gateHit=false;death(f);drain(f);
  assert.equal(f.c.writes,1);assert.equal(f.c.admits,0);assert.equal(f.c.choices,0);
  assert.equal(f.c.saved.bookRun.cf6SoldierLoot.records['u.A'].state,'DECIDED_MISS');death(f);drain(f);assert.equal(f.c.rolls,1);
});
test('death during shield break, retirement or foreign actor ownership cannot enter the queue',()=>{
  for(const mutation of ['actor.soldierPhase=1','actor.cf6EncounterRetired=true','actor.cf6ActionRecord.valid=false','actor.hp=1']){
    const f=fixture();f.run(mutation);assert.equal(f.api.combatDeath(f.c.actor),false);assert.equal(status(f).queued,0);assert.equal(f.c.rolls,0);
  }
});
test('reloaded durable hit resumes admission without replaying its random gate',()=>{
  const f=fixture();death(f);decide(f);f.api.context=f.run('({identity:{}})');f.api.captured=f.run('({})');
  assert.equal(f.api.bind(f.c.config),true);drain(f);assert.equal(f.c.rolls,1);assert.equal(f.c.admits,1);
});
test('same-name sidearms remain independent and use summed ordinary reload cost',()=>{
  const f=fixture();f.c.category=.6;death(f);drain(f);
  const items=f.c.saved.stash;assert.equal(items.length,3);assert.equal(items[0].value.shot,2);assert.equal(items[1].value.shot,7);
  assert.equal(items[2].value,2);assert.notEqual(items[0].value,items[1].value);
});
test('changed slot cannot rebind or admit an unresolved old run',()=>{
  const f=fixture();death(f);f.c.outcome='unknown';decide(f);f.run("_root.savePath='other'");
  assert.equal(f.api.prepareForTransition(),false);assert.equal(f.c.admits,0);assert.equal(f.c.writes,1);
});

test('save success remains blocked across the two durable stages and deferred exit',()=>{
  const f=fixture();assert.equal(f.api.blocksSaveSuccess(),false);death(f);
  assert.equal(f.api.blocksSaveSuccess(),true);decide(f);assert.equal(f.api.blocksSaveSuccess(),true);
  drain(f);assert.equal(f.api.blocksSaveSuccess(),false);
});

test('no installed material filters that category while preserving the single weapon gate and tier',()=>{
  const f=fixture();f.c.actor.cf6LootMaterial=null;f.c.actor.长枪.value.tier='狱火';
  f.c.actor.cf6FirepowerProfile={gunOnly:123,nano:4};death(f);drain(f);
  assert.equal(f.c.rolls,1);assert.equal(f.c.admits,1);
  const packet=f.c.saved.bookRun.cf6SoldierLoot.records['u.A'];
  assert.equal(packet.kind,'longgun');assert.equal(packet.items[0].value.tier,'狱火');
  assert.equal(packet.items[0].value.cf6FirepowerProfile,undefined);
  assert.equal(packet.items[0].cf6FirepowerProfile,undefined);
  death(f);drain(f);assert.equal(f.c.rolls,1);
});

test('an unknown nonempty material remains invalid instead of widening admission',()=>{
  const f=fixture();f.c.actor.cf6LootMaterial='unknown';death(f);drain(f);
  assert.equal(f.c.rolls,0);assert.equal(f.c.admits,0);
});

function missUntil(f,count) {
  f.c.gateHit=false;
  for(let i=0;i<count;i++) {
    f.c.actor.cf6UnitIdentity='pity-'+i;f.c.actor.cf6ActionRecord.key='birth.pity-'+i;
    death(f);drain(f);
  }
}
test('eighth evaluated death freezes one guaranteed primary and leaves seven historical misses intact',()=>{
  const f=fixture();missUntil(f,7);
  const before=JSON.stringify(f.c.saved.bookRun.cf6SoldierLoot.records);
  f.c.actor.cf6UnitIdentity='eighth';f.c.actor.cf6ActionRecord.key='birth.eighth';
  death(f);drain(f);const ledger=f.c.saved.bookRun.cf6SoldierLoot;
  assert.equal(f.c.rolls,8);assert.equal(f.c.choices,0);assert.equal(ledger.weaponInstances,1);assert.equal(ledger.packages,1);
  const p=ledger.records['u.eighth'];assert.equal(p.kind,'longgun');assert.equal(p.roll.reason,'first_weapon_guarantee');
  assert.equal(p.roll.naturalHit,false);assert.equal(p.roll.eligibleOrdinal,8);
  const old={...ledger.records};delete old['u.eighth'];assert.equal(JSON.stringify(old),before);
  death(f);drain(f);assert.equal(f.c.rolls,8);assert.equal(f.c.admits,1);
});
test('unknown guarantee decision queries the same frozen operation without advancing RNG or quota twice',()=>{
  const f=fixture();missUntil(f,7);f.c.actor.cf6UnitIdentity='unknown-eighth';f.c.actor.cf6ActionRecord.key='birth.unknown-eighth';
  death(f);f.c.outcome='unknown';decide(f);const op=status(f).operationId;
  f.api.prepareForTransition();assert.equal(status(f).operationId,op);assert.equal(f.c.rolls,8);assert.equal(f.c.admits,0);
  f.c.outcome='committed';drain(f);assert.equal(f.c.rolls,8);assert.equal(f.c.admits,1);assert.equal(f.c.saved.bookRun.cf6SoldierLoot.packages,1);
});
test('already received weapon suppresses first-weapon guarantee even after eight later misses',()=>{
  const f=fixture();death(f);drain(f);missUntil(f,9);
  assert.equal(f.c.rolls,10);assert.equal(f.c.saved.bookRun.cf6SoldierLoot.weaponInstances,1);
  assert.equal(Object.values(f.c.saved.bookRun.cf6SoldierLoot.records).filter(p=>p.roll.reason==='first_weapon_guarantee').length,0);
});
test('legacy eight-miss ledger qualifies on the next new death without revising a durable identity',()=>{
  const f=fixture();delete f.c.config.lootPolicy.firstWeaponGuarantee;missUntil(f,8);
  f.c.config.lootPolicy.firstWeaponGuarantee=vm.runInContext('({afterEligibleDeaths:8})',f.c);
  const old=JSON.stringify(f.c.saved.bookRun.cf6SoldierLoot.records);
  f.c.actor.cf6UnitIdentity='legacy-next';f.c.actor.cf6ActionRecord.key='birth.legacy-next';death(f);drain(f);
  const ledger=f.c.saved.bookRun.cf6SoldierLoot;assert.equal(ledger.records['u.legacy-next'].roll.eligibleOrdinal,9);
  const previous={...ledger.records};delete previous['u.legacy-next'];assert.equal(JSON.stringify(previous),old);
});
