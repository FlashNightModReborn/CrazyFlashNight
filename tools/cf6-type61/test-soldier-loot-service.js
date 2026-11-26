'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const path = require('node:path');
const {loadStaticClass} = require('../cf6-soldier-assets/offline/as2-source');

const classes = path.resolve(__dirname, '../../scripts/类定义/org/flashNight/arki/scene');
function fixture() {
  const context = vm.createContext({length: v => typeof v === 'string' ? v.length : 0, trace() {}});
  const run = source => vm.runInContext(source, context);
  run(`
    var commits = 0, rolls = 0, choices = 0, queries = 0, admissions = 0, attaches = 0;
    var outcome = 'committed', gateHit = true, category = 0, pending = null, stored = null;
    var worldItems = [], failOnce = '', reenter = false;
    var clone = v => JSON.parse(JSON.stringify(v));
    var PersistedSnapshot = {cloneData: clone, cloneArrayData: clone,
      sameData: (before, after) => JSON.stringify(before) === JSON.stringify(after)};
    var _root = {
      savePath: 'cf7_env_cf6_fixture',
      _saveExt: {bookRun: {bookId:'cf6-sting',routeId:'type61',slot:'cf7_env_cf6_fixture',
        seed:7,startedAt:8,planSeed:9,outcome:'active',cf6SoldierLoot:null}},
      存档系统: {dirtyMark:false}, gameworld: {mark:{}},
      getNextHighestDepth() { return 1; }, createEmptyMovieClip() { return {_name:'watcher'}; }
    };
    var StageReturnFlow = {worldIdentity: world => world.mark};
    var Cf6Type61Service = {isActive() { return true; }};
    var BookDefinition = {get() { return {type61:{soldiers:config}}; }};
    var Cf6SoldierActions = {actorValid: record => record.valid, context: () => ({mapId:'A19'})};
    var ItemUtil = {isItem: name => name === '透镜'};
    var PlayerAssetTransaction = {
      current() { return null; }, markDirtyRequired(owner) { owner.dirtyMark = true; }
    };
    var DropLuckRoller = {
      getLuckBonus() { return .2; },
      rollDropWithContext(key, item, luck, prd) {
        rolls++;
        prd.state[key] = (prd.state[key] || 0) + 1;
        return gateHit;
      }
    };
    var LinearCongruentialEngine = {instance:{nextFloat() { choices++; return category; }}};
    function PseudoRandomDistribution(state) { this.state = state; }
    var WeaponAmmoRuntime = {quoteInventoryPacks: (rounds,reserve,capacity) => Math.ceil((rounds-reserve)/capacity)};
    var manager = {createCollectible(name, quantity, x, z, fly, spec, receipt) {
      attaches++;
      if (reenter) Cf6SoldierLoot.combatDeath(actor);
      if (failOnce === 'known' && name === 'G1111') { failOnce = ''; receipt.state = 'not_created'; return; }
      if (failOnce === 'unknown' && name === 'MP7' && worldItems.length === 1) {
        failOnce = ''; receipt.state = 'unknown'; throw Error('unknown attach');
      }
      worldItems.push({item:clone(spec.pickupItemData), x, z});
      receipt.state = 'created';
      if (failOnce === 'post_attach') { failOnce = ''; throw Error('post attach initialization'); }
    }};
    _root.pickupItemManager = manager;
    function settle(committed) {
      const operation = pending;
      if (committed) stored = clone(_root._saveExt);
      else _root._saveExt = operation.before;
      pending = null;
      operation.callback(committed,operation.domain);
    }
    var RewardStashService = {
      lastError:'',
      pendingOperationId() { return pending ? pending.id : ''; },
      begin(id,origin,callback,domain) {
        if (pending) return false;
        pending = {id,callback,domain,before:clone(_root._saveExt)};
        _root._saveExt = clone(_root._saveExt);
        return true;
      },
      admit(items,preferInventory,owned) {
        if (!owned) throw Error('legacy migration needs ownership');
        admissions++;
        const destination = preferInventory ? 'inventory' : 'stash';
        const target = _root._saveExt[destination] || (_root._saveExt[destination] = []);
        for (const item of items) target.push(clone(item));
        return true;
      },
      end() {
        commits++;
        if (outcome === 'committed') { settle(true); return {success:true}; }
        if (outcome === 'not_committed') { settle(false); return {success:false,error:'save_not_committed'}; }
        return {success:false,error:'commit_pending'};
      },
      resume(id) {
        queries++;
        if (!pending || pending.id !== id) throw Error('different pending operation');
        if (outcome === 'committed') settle(true);
      },
      cancel() { if (pending && outcome !== 'unknown') settle(false); }
    };
  `);
  context.config = run('JSON.parse('+JSON.stringify(JSON.stringify({
    version:'fixed-v2', lootPolicy:require('./soldier-loot-policy.source.json')
  }))+')');
  const rules = loadStaticClass(context, path.join(classes,'Cf6SoldierLootRules.as'),'Cf6SoldierLootRules');
  const api = loadStaticClass(context, path.join(classes,'Cf6SoldierLoot.as'),'Cf6SoldierLoot',['PseudoRandomDistribution']);
  run(`
    var actor = {cf6UnitIdentity:'A',cf6LootProfile:'major_rifle_xor_pair_xor_material',
      cf6LootMaterial:'透镜',soldierPhase:2,soldierIsElite:true,hp:0,
      cf6ActionRecord:{valid:true,key:'birth.A'},_x:200,Z轴坐标:300,
      长枪:{name:'G1111',lastUpdate:1,value:{level:13,mods:[],shot:4,reloadCount:8,isRocketMode:false,__extra:{kept:1}}},
      手枪:{name:'MP7',lastUpdate:2,value:{level:13,mods:[],shot:2}},
      手枪2:{name:'MP7',lastUpdate:3,value:{level:13,mods:[],shot:7}},
      长枪属性:{capacity:15,clipname:'步枪弹药'},手枪属性:{capacity:40,clipname:'手枪弹药'},
      手枪2属性:{capacity:40,clipname:'手枪弹药'}};
    function legacy(id,state) {
      var l = _root._saveExt.bookRun.cf6SoldierLoot;
      if (!l) l = _root._saveExt.bookRun.cf6SoldierLoot = Cf6SoldierLootRules.create(config.version,config.lootPolicy.version);
      var hit = state !== 'DECIDED_MISS';
      var header = {sourceKey:'old.'+id,unitIdentity:id,spawnIdentity:id,rosterVersion:'old',configurationFingerprint:'old'};
      var snapshot = {primary:actor.长枪,ground:{mapId:'A19',x:200,z:300}};
      var roll = {recorded:true,gateEvaluated:true,hit,nominalPercent:3,luckBonus:0,prdPoolKey:'old',reason:hit?'roll_hit':'roll_miss'};
      var items = hit ? [{name:'步枪弹药',value:1,lastUpdate:1}] : [];
      var packet = Cf6SoldierLootRules.packet(header,snapshot,hit?'longgun':'none',roll,items);
      packet.state = state;
      if (!Cf6SoldierLootRules.reserve(l,packet)) throw Error('invalid old fixture');
    }
    function death(id) { actor.cf6UnitIdentity = id; return Cf6SoldierLoot.combatDeath(actor); }
    function tick(n) { for (let i=0;i<n;i++) Cf6SoldierLoot.tick(); }
    function ledger() { return _root._saveExt.bookRun.cf6SoldierLoot; }
  `);
  // AVM1 treats missing-property reads as undefined.
  api.context = run('({identity:{}})');
  assert.equal(api.bind(context.config),true);
  return {run,rules,context,api};
}

test('death freezes real item data and consumes a quota with no asset commit', () => {
  const f=fixture();
  assert.equal(f.run("death('A')"),true);
  assert.equal(f.run("worldItems[0].item.value.shot"),4);
  f.run("actor.长枪.value.shot=99");
  assert.equal(f.run("worldItems[0].item.value.shot"),4);
  assert.equal(f.run("worldItems[1].item.name"),"步枪弹药");
  assert.equal(f.run("ledger().v"),3);
  assert.equal(f.run("ledger().records['u.A'].items"),undefined);
  assert.equal(f.run("ledger().weaponInstances"),1);
  assert.equal(f.run("_root.存档系统.dirtyMark"),true);
  assert.equal(f.run("commits+admissions"),0);
});

test('same death reentering during attach observes the prior reservation', () => {
  const f=fixture();
  f.run("reenter=true; death('A'); death('A'); tick(60)");
  assert.equal(f.run("rolls"),1);
  assert.equal(f.run("attaches"),2);
});

test('verified zero creation retries only the missing frozen child', () => {
  const f=fixture();
  f.run("failOnce='known';death('A');actor.长枪.value.shot=99;tick(60)");
  assert.equal(f.run("rolls"),1);
  assert.equal(f.run("attaches"),3);
  assert.equal(f.run("worldItems[1].item.value.shot"),4);
  assert.equal(f.run("worldItems[0].item.name"),"步枪弹药");
});

test('unknown second twin creation cannot replay either twin or the summed ammo', () => {
  const f=fixture();
  f.run("category=.6;failOnce='unknown';death('A');tick(90)");
  assert.equal(f.run("attaches"),3);
  assert.equal(f.run("worldItems.length"),2);
  assert.equal(f.run("worldItems[1].item.value"),2);
  assert.equal(f.run("ledger().weaponInstances"),2);
});

test('known created entity cannot replay after its initialization exception', () => {
  const f=fixture();
  f.run("failOnce='post_attach';death('A');tick(90)");
  assert.equal(f.run("attaches"),2);
  assert.equal(f.run("worldItems.length"),2);
});

test('unpicked assets and retries do not carry into a new world', () => {
  const f=fixture();
  f.run("failOnce='known';death('A');_root.gameworld={mark:{}};worldItems=[];tick(60)");
  assert.equal(f.run("attaches"),2);
  assert.equal(f.run("worldItems.length"),0);
  assert.equal(f.run("ledger().packages"),1);
  assert.equal(f.run("commits+admissions"),0);
});

test('an intervening asset write defers generation without eating the death count on world change', () => {
  const f=fixture();
  f.run("pending={id:'other.owner'};death('A');_root.gameworld={mark:{}};pending=null;tick(30)");
  assert.equal(f.run("ledger().eligibleDeaths"),1);
  assert.equal(f.run("rolls"),1);
  assert.equal(f.run("worldItems.length"),0);
  assert.equal(f.run("commits+admissions"),0);
});

test('eighth evaluated death guarantees a rifle after old misses and an ineligible death', () => {
  const f=fixture();
  f.run("gateHit=false; for(let i=0;i<7;i++)legacy('miss'+i,'DECIDED_MISS');actor.Z轴坐标=NaN;death('ineligible');actor.Z轴坐标=300;death('A')");
  assert.equal(f.run("ledger().records['u.ineligible'].eligible"),false);
  assert.equal(f.run("ledger().eligibleDeaths"),8);
  assert.equal(f.run("ledger().records['u.A'].kind"),"longgun");
  assert.equal(f.run("rolls"),1);
  assert.equal(f.run("choices"),0);
});

test('material and weapon quotas apply on generation even when nothing is picked up', () => {
  const f=fixture();
  f.run("category=.99;death('A');death('B');death('C');category=0;for(let i=0;i<7;i++)death('extra'+i)");
  assert.equal(f.run("ledger().materials"),2);
  assert.equal(f.run("ledger().packages"),6);
  assert.equal(f.run("worldItems.filter(x=>x.item.name==='透镜').length"),2);
  assert.equal(f.run("commits+admissions"),0);
});

test('old hit keeps original entitlement and exact pending operation until confirmation', () => {
  const f=fixture();
  f.run("legacy('hit','DECIDED_HIT'); outcome='unknown'");
  assert.equal(f.api.settleLegacyBeforeReplacement(),false);
  const operation = f.run("pending.id");
  assert.equal(f.api.settleLegacyBeforeReplacement(),false);
  assert.equal(f.run("pending.id"),operation);
  assert.equal(f.run("commits"),1);
  f.run("tick(60); outcome='committed';tick(60)");
  assert.equal(f.run("stored.bookRun.cf6SoldierLoot.v"),3);
  assert.equal(f.run("stored.stash.length"),1);
  assert.equal(f.run("stored.inventory[0].value"),1);
  assert.equal(f.run("worldItems.length+rolls"),0);
});

test('a confirmed pre-exposure rejection preserves old state for exact future migration', () => {
  const f=fixture();
  f.run("legacy('hit','DECIDED_HIT');outcome='not_committed'");
  assert.equal(f.api.settleLegacyBeforeReplacement(),false);
  assert.equal(f.run("ledger().records['u.hit'].state"),"DECIDED_HIT");
  assert.equal(f.run("_root._saveExt.stash"),undefined);
  f.run("outcome='committed';tick(60)");
  assert.equal(f.run("stored.stash.length"),1);
});

test('already owned and serialized pending states never prompt a new grant', () => {
  const owned=fixture();
  owned.run("legacy('owned','OWNED');gateHit=false;death('A')");
  assert.equal(owned.run("ledger().records['u.owned'].kind"),"longgun");
  assert.equal(owned.run("commits+admissions"),0);

  const pending=fixture();
  pending.run("legacy('pending','COMMIT_PENDING')");
  assert.equal(pending.api.settleLegacyBeforeReplacement(),false);
  assert.equal(pending.run("ledger().v"),2);
  assert.equal(pending.run("commits+admissions"),0);
});

test('the compatible generation-off policy reads v2 and v3 without creating assets', () => {
  const f=fixture();
  f.run("legacy('miss','DECIDED_MISS');config.lootPolicy.groundDropsEnabled=false");
  assert.equal(f.run("Cf6SoldierLootRules.normalizeLedger(ledger()).ok"),true);
  assert.equal(f.run("death('A')"),false);
  f.run("_root._saveExt.bookRun.cf6SoldierLoot=Cf6SoldierLootRules.toGroundLedger(ledger())");
  assert.equal(f.run("Cf6SoldierLootRules.normalizeLedger(ledger()).ok"),true);
  assert.equal(f.run("death('B')"),false);
  assert.equal(f.run("rolls+commits+admissions+attaches"),0);
});

test('a reload may keep the exact old promise but may not erase it or revive it from v3', () => {
  const f=fixture();
  f.run("legacy('hit','DECIDED_HIT');var incoming=clone(_root._saveExt.bookRun)");
  assert.equal(f.run("Cf6SoldierLootRules.preservesLoadedLedger(_root._saveExt.bookRun,incoming)"),true);
  assert.equal(f.run("delete incoming.cf6SoldierLoot.records['u.hit'];Cf6SoldierLootRules.preservesLoadedLedger(_root._saveExt.bookRun,incoming)"),false);
  f.run("incoming=clone(_root._saveExt.bookRun);Cf6SoldierLoot.settleLegacyBeforeReplacement()");
  assert.equal(f.run("Cf6SoldierLootRules.preservesLoadedLedger(_root._saveExt.bookRun,incoming)"),false);
});
