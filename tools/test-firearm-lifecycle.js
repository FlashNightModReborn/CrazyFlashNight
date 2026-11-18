'use strict';
// Executes unchanged AS2 method bodies with types erased. Plain-object / scheduler
// adapters only: this does NOT emulate AVM1, MovieClip references or frame scripts.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const cp = require('node:child_process');
const {loadStaticClass,eraseTypes} = require('./cf6-soldier-assets/offline/as2-source');
const root = path.resolve(__dirname, '..');
const folder = 'scripts/类定义/org/flashNight/arki/unit/Action/Shoot';
const sourceFiles=Object.fromEntries(['ShootCore','ShootInitCore','ReloadManager','LongGunSubWeaponCore']
  .map(name=>[name,folder+'/'+name+'.as']));
sourceFiles.StateTransition='scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransition.as';
const args = process.argv.slice(2);
const sourceRef = args.includes('--source-ref') ? args[args.indexOf('--source-ref') + 1] : null;
const expectedBaseline = args.includes('--expect-baseline');
const sourceDir = sourceRef ? fs.mkdtempSync(path.join(os.tmpdir(), 'firearm-source-')) : path.join(root, folder);
if (sourceRef) for (const name of Object.keys(sourceFiles)) {
  fs.writeFileSync(path.join(sourceDir, name + '.as'), cp.execFileSync('git', ['show', sourceRef + ':' + sourceFiles[name]], {cwd:root}));
}

function environment() {
  let nextId = 1, stock = 10, queries = 0, submits = 0;
  let getTotalQueries = 0, singleContainQueries = 0;
  const tasks = new Map();
  const wheel = {
    addTask(fn, delay, repeat, ...params) {const id=nextId++; tasks.set(id,{fn,delay,repeat,params}); return id;},
    removeTask(id) {tasks.delete(id);},
    removeTaskByLabel() {},
    addOrUpdateTask(owner,label,fn,delay,repeat,count,params) {return this.addTask(fn,delay,repeat,...params);},
  };
  const bag = {revision:0, getMutationRevision(){return this.revision;}};
  const drugs = {revision:0, getMutationRevision(){return this.revision;}};
  const c = vm.createContext({
    _root:{暂停:false,控制目标:'hero',gameworld:{},物品栏:{背包:bag,药剂栏:drugs},
      帧计时器:{当前帧数:0},玩家信息界面:{玩家必要信息界面:{}},存档系统:{},发布消息(){}},
    ItemUtil:{singleContain(){queries++;singleContainQueries++;return stock>0?{}:null;},
      getTotal(){queries++;getTotalQueries++;return stock;},
      singleSubmit(){submits++;if(stock<1)return false;stock--;bag.revision++;return true;},
      isMaterial(){return false;},isInformation(){return false;}},
    TargetCacheManager:{findHero(){return c.hero;}},
    EnhancedCooldownWheel:{I(){return wheel;}},
    Dictionary:{getStaticUID(){return 1;}},
    getTimer(){return 10000;},
    WeaponAmmoRuntime:{canReload(){return true;},reserve(){return 0;},beginReload(){},
      ensure(){return null;},supplyValue(v){v.shot=0;}},
    org:{flashNight:{arki:{
      unit:{Action:{Shoot:{},Input:{}}},
      scene:{Cf6SoldierSignals:{reloadCommitted(){}}}
    }}},
  });
  for (const name of Object.keys(sourceFiles)) {
    const sourcePath=sourceRef?path.join(sourceDir,name+'.as'):path.join(root,sourceFiles[name]);
    // Whole class shape check catches orphan statements that method extraction
    // alone could skip. This JS grammar check is still not a CS6 compile.
    const shape=eraseTypes(fs.readFileSync(sourcePath,'utf8'),
      ['EnhancedCooldownWheel','EventDispatcher','WeaponStateManager'])
      .replace(/^\uFEFF/,'').replace(/^import [^;]+;\s*/gm,'')
      .replace(/class org\.flashNight\.[\w.]+/,'class '+name)
      .replace(/\b(public|private)\s+/g,'').replace(/\bstatic var /g,'static ')
      .replace(/\bstatic function /g,'static ');
    new vm.Script(shape,{filename:name+'.shape.js'});
    loadStaticClass(c,sourcePath,name,['EnhancedCooldownWheel','EventDispatcher','WeaponStateManager']);
    if(name!=='StateTransition')c.org.flashNight.arki.unit.Action.Shoot[name]=c[name];
  }
  // These two collaborators are outside the reload-input proof. The cadence and
  // task tests below use the real ShootCore callbacks, not this handoff adapter.
  const realStopForReload=c.ShootCore.stopForReload;
  c.ShootCore.stopForReload = u => {u.主手射击中=false;u.副武器射击中=false;};
  // This only isolates external class-qualified calls. Unqualified calls inside
  // the extracted class retain the real method binding and its counted APIs.
  c.LongGunSubWeaponCore.updateAmmoDisplay = () => {};
  function fixture(mainLoaded=0,subLoaded=1) {
    const u={_name:'hero',hp:100,攻击模式:'长枪',状态:'长枪站立',动作A:true,动作B:true,动作C:false,
      长枪:{value:{shot:5-mainLoaded}},长枪弹匣容量:5,长枪属性:{reloadType:'magazine'},
      被动技能:{枪械师:{启用:false}},长枪副武器:{value:{shot:2-subLoaded,reloadCount:0}},
      长枪副武器状态:{capacity:2,loaded:subLoaded,nextFireTime:0,reloadCount:0},
      长枪副武器配置:{capacity:2,consumeMode:'onLoadGroup',clipCostPerLoad:1,reserveName:'probe',manualReloadPenalty:0},
      长枪副武器弹匣容量:2,长枪副武器属性:{},手枪:{value:{shot:0}},手枪2:{value:{shot:0}},
      手枪弹匣容量:5,手枪2弹匣容量:5};
    const m={_parent:u,换弹标签:false,射击许可标签:true,使用弹匣名称:'probe',剩余弹匣数:10,subweaponReloadRequest:{},
      gotoAndPlay(label){this.label=label;},gotoAndStop(label){this.label=label;},
      开始射击(){this.mainRequests=(this.mainRequests||0)+1;},
      开始副武器射击(){this.subRequests=(this.subRequests||0)+1;}};
    u.man=m;c.hero=u;c._root.gameworld.hero=u;
    m.开始副武器换弹=()=>c.LongGunSubWeaponCore.startManualReloadAnimation(u);
    return {u,m};
  }
  return {c,wheel,tasks,fixture,bag,drugs,realStopForReload,
    stock(n){stock=n;bag.revision++;},get queries(){return queries;},get submits(){return submits;},
    get getTotalQueries(){return getTotalQueries;},get singleContainQueries(){return singleContainQueries;}};
}

const cases=[], observations={};
function test(name,fn,baselineFailure=false){cases.push({name,fn,baselineFailure});}
test('261 primary reload survives inherited J/K',()=>{
  const e=environment(),{u,m}=e.fixture();
  e.c.ReloadManager.startReload(m,u,e.c._root);
  assert.ok(m.换弹标签);
  for(let i=0;i<30;i++)e.c.ReloadManager.handleReloadInput(m,u);
  assert.ok(m.换弹标签,'held K must not cancel primary reload');
  assert.equal(m.subRequests,undefined);
},true);
test('261 release and new K can interrupt with loaded subweapon',()=>{
  const e=environment(),{u,m}=e.fixture();
  e.c.ReloadManager.startReload(m,u,e.c._root);
  u.动作B=false;e.c.ReloadManager.handleReloadInput(m,u);u.动作B=true;
  assert.equal(e.c.ReloadManager.tryCancelForFire(m,u,'长枪副武器'),true);
  assert.equal(m.换弹标签,false);
});
test('261 subweapon-first empty requests its own reload',()=>{
  const e=environment(),{u,m}=e.fixture(4,0);
  e.c.LongGunSubWeaponCore.requestShoot(u);
  assert.ok(m.换弹标签,'empty K must start a reload');
  assert.equal(m.subweaponReloadRequest.kind,'manual');
  assert.equal(u.长枪.value.shot,1,'primary ammo must not change');
},true);
test('261 manual subweapon reload survives inherited J',()=>{
  const e=environment(),{u,m}=e.fixture(4,0);
  assert.ok(e.c.LongGunSubWeaponCore.startManualReloadAnimation(u));
  e.c.ReloadManager.handleReloadInput(m,u);
  assert.ok(m.换弹标签,'old J must not cancel subweapon reload');
},true);
test('261 no-stock empty K is bounded and notices replenishment',()=>{
  const e=environment(),{u,m}=e.fixture(4,0);e.stock(0);
  u.主手射击中=true;
  for(let i=0;i<100;i++)e.c.LongGunSubWeaponCore.requestShoot(u);
  observations.emptyK100Requests={inventoryQueries:e.queries,
    inventoryCalls:{getTotal:e.getTotalQueries,singleContain:e.singleContainQueries},pendingTasks:e.tasks.size};
  assert.equal(m.换弹标签,false);
  assert.equal(u.主手射击中,true,'denied secondary reload must not stop a loaded primary');
  assert.ok(e.queries<=2,'unchanged denied stock must not be scanned every frame');
  assert.equal(e.tasks.size,0);
  e.stock(2);e.c.LongGunSubWeaponCore.requestShoot(u);
  assert.ok(m.换弹标签,'stock revision rearms the empty request without a key release');
},true);
test('261 AI empty subweapon must not spend player stock',()=>{
  const e=environment(),{u,m}=e.fixture(4,0);e.c._root.控制目标='other';
  e.c.LongGunSubWeaponCore.requestShoot(u);
  assert.equal(m.换弹标签,false);assert.equal(e.submits,0);
});
test('261 paused empty K cannot enter reload or scan inventory',()=>{
  const e=environment(),{u,m}=e.fixture(4,0);e.c._root.暂停=true;
  e.c.LongGunSubWeaponCore.requestShoot(u);
  assert.equal(m.换弹标签,false);assert.equal(e.queries,0);
},true);
test('165 dual reload still requires a fresh press for each hand',()=>{
  const e=environment(),{u,m}=e.fixture();u.攻击模式='双枪';
  e.c.ReloadManager.beginDualReloadSequence(m,u,'主手');
  assert.equal(e.c.ReloadManager.tryCancelForFire(m,u,'手枪2'),false);
  u.动作B=false;e.c.ReloadManager.handleReloadInput(m,u);u.动作B=true;
  assert.equal(e.c.ReloadManager.tryCancelForFire(m,u,'手枪2'),true);
});
test('261 no-stock cache distinguishes replaced inventory at the same revision',()=>{
  const e=environment(),{u}=e.fixture(4,0);e.stock(0);
  e.c.LongGunSubWeaponCore.requestShoot(u);const first=e.queries;
  e.c.LongGunSubWeaponCore.requestShoot(u);assert.equal(e.queries,first);
  e.c._root.物品栏.背包={getMutationRevision(){return e.bag.revision;}};
  e.c.LongGunSubWeaponCore.requestShoot(u);assert.equal(e.queries,first+1);
},true);
test('261 empty K from run waits for the new body initialization',()=>{
  const e=environment(),{u,m}=e.fixture(4,0);u.状态='长枪跑';u.移动射击=true;
  u.状态改变=function(state){this.状态=state;this.man={_parent:this,换弹标签:false};};
  e.c.LongGunSubWeaponCore.requestShoot(u);
  assert.equal(u.状态,'长枪行走');assert.equal(m.label,undefined);assert.equal(e.queries,0);
  e.c.LongGunSubWeaponCore.requestShoot(u);assert.equal(e.queries,0,'unready body must not acquire reload ownership');
  const fresh=u.man;fresh.subweaponReloadRequest={};fresh.gotoAndPlay=function(label){this.label=label;};
  fresh.开始副武器换弹=()=>e.c.LongGunSubWeaponCore.startManualReloadAnimation(u);
  e.c.LongGunSubWeaponCore.requestShoot(u);assert.ok(fresh.换弹标签);assert.equal(fresh.label,'换弹匣');
},true);
test('164 late rate owner cannot clear replacement budget',()=>{
  const e=environment(),{u}=e.fixture();
  // AS2 permits undefined.taskId. Make that optional record explicit in JS.
  e.c.ShootCore._lastShotTimes.hero_keepshooting={};
  e.c.ShootCore.armRateLimit(u,'keepshooting',1000);
  const old=e.c.ShootCore._lastShotTimes.hero_keepshooting;
  e.c.ShootCore.armRateLimit(u,'keepshooting',1000);
  const fresh=e.c.ShootCore._lastShotTimes.hero_keepshooting;
  e.c.ShootCore._clearRateLimit('hero_keepshooting',old);
  assert.equal(e.c.ShootCore._lastShotTimes.hero_keepshooting,fresh);
  assert.equal(e.tasks.size,1);
});
test('265 competing hypothesis: R bypasses semi press and shooting flag',()=>{
  const e=environment(),{u,m}=e.fixture(0,0);
  u._semiLock_keepshooting=true;u.主手射击中=true;
  e.c.ReloadManager.startReload(m,u,e.c._root);
  assert.ok(m.换弹标签,'these flags alone do not explain R failure');
});
test('reload completion rejects equal-generation replacement identity',()=>{
  const e=environment(),{u,m}=e.fixture();
  e.c.ReloadManager.bumpReloadGeneration(m);const late=m.结束换弹;
  const generation=m.__reloadGeneration;m.__reloadIdentity={};m.换弹标签=true;
  late();assert.equal(m.__reloadGeneration,generation);assert.ok(m.换弹标签);
  assert.equal(m.label,undefined);
});
test('gunslinger dual release retires its polling task',()=>{
  const e=environment(),{u}=e.fixture();u.动作A=false;
  const poll='_gunslingerReleasePoll_keepshooting',chain='_gunslingerChain_keepshooting';
  u[poll]=e.wheel.addTask(()=>{},33,true);u[chain]=e.wheel.addTask(()=>{},1000,false);
  if(e.c.ShootCore._gunslingerReleasePoll)e.c.ShootCore._gunslingerReleasePoll(u,'动作A',chain,'_semiReleased_keepshooting');
  else e.c.ShootCore._pollGunslingerRelease(u,poll,chain,'动作A');
  observations.gunslingerRelease={remainingTasks:e.tasks.size};
  assert.equal(e.tasks.size,0,'release must stop the repeating poll as well as the chain');
},true);

// The resource decision/commit methods remain extracted production AS2 bodies.
// These adapters provide only UI/type/skill collaborators outside this proof.
function prepareB1ResourceAdapters(e, u) {
  e.c.BulletTypeUtil = {isVertical() { return false; }};
  e.c.org.flashNight.arki.skill = {SkillFeaturePolicy:{isEnabled() { return false; }}};
  Object.assign(u.长枪副武器配置, {
    consumeTiming:'onReloadCommit', hitBehavior:{}, basePower:100,
    powerMultiplier:1, hostPowerMultiplier:1, impact:1, cd:1000,
  });
  u.长枪副武器状态.groupPaid = false;
}

test('261 denied reserve probe invalidates on drug-container mutation', () => {
  const e=environment(), {u}=e.fixture(4,0); e.stock(0);
  assert.equal(e.c.LongGunSubWeaponCore.canReloadManual(u),false);
  const before=e.queries, unchangedBagRevision=e.bag.revision;
  e.stock(3); e.bag.revision=unchangedBagRevision; e.drugs.revision++;
  assert.equal(e.c.LongGunSubWeaponCore.canReloadManual(u),true);
  assert.equal(e.queries,before+1,'drug revision participates in contain eligibility');
});

test('261 failed subweapon payment restores both recovery fields and ammunition', () => {
  const e=environment(), {u}=e.fixture(4,0); prepareB1ResourceAdapters(e,u);
  u.被动技能.枪械师={启用:true,等级:10};
  u.长枪副武器配置.capacity=5;
  u.长枪副武器状态.capacity=5;
  u.长枪副武器弹匣容量=5;
  u.长枪副武器.value.shot=3; // Two remaining rounds recover before failed payment.
  u.长枪副武器状态.loaded=2;
  u.长枪副武器.value.reloadCount=1;
  u.长枪副武器状态.reloadCount=1;
  let attempts=0;
  e.c.ItemUtil.singleSubmit=()=>{attempts++;return false;};
  assert.equal(e.c.LongGunSubWeaponCore.canReloadManual(u),true);
  assert.equal(e.c.LongGunSubWeaponCore.reloadManual(u),false);
  assert.equal(attempts,1);
  assert.equal(u.长枪.value.shot,1,'failed secondary payment cannot touch primary ammunition');
  assert.equal(u.长枪副武器.value.shot,3);
  assert.equal(e.c.LongGunSubWeaponCore.getLoadedCount(u),2);
  assert.equal(u.长枪副武器.value.reloadCount,1,'virtual recovery rolls back to its exact old value');
  assert.equal(u.长枪副武器状态.reloadCount,1,'state recovery mirror rolls back too');
  assert.equal(u.长枪副武器状态.groupPaid,false,'failed submit never grants a paid group');
});

test('261 reserve denial does not hide later tactical-free eligibility', () => {
  const e=environment(), {u}=e.fixture(4,0); prepareB1ResourceAdapters(e,u); e.stock(0);
  assert.equal(e.c.LongGunSubWeaponCore.canReloadManual(u),false);
  const before=e.queries;
  // Independent non-inventory input changes, with the stock revisions unchanged.
  u.被动技能.枪械师={启用:true,等级:10};
  u.长枪副武器.value.reloadCount=2;
  u.长枪副武器状态.reloadCount=2;
  assert.equal(e.c.LongGunSubWeaponCore.canReloadManual(u),true);
  assert.equal(e.queries,before,'tactical eligibility requires no fresh inventory scan');
  assert.equal(e.c.LongGunSubWeaponCore.reloadManual(u),true);
  assert.equal(e.submits,0,'free recovery never spends an inventory pack');
  assert.equal(e.c.LongGunSubWeaponCore.getLoadedCount(u),2);
  assert.equal(u.长枪副武器.value.reloadCount,0);
  assert.equal(u.长枪副武器状态.reloadCount,0);
  assert.equal(u.长枪副武器状态.groupPaid,true);
},true);

test('261 failed primary commit never commits the linked secondary', () => {
  const e=environment(), {u,m}=e.fixture(0,0); prepareB1ResourceAdapters(e,u);
  m.使用弹匣名称='primary-pack';u.长枪副武器配置.reserveName='secondary-pack';
  const attempts=[];
  e.c.ItemUtil.singleSubmit=(name)=>{attempts.push(name);return false;};
  e.c.ReloadManager.startReload(m,u,e.c._root);
  assert.equal(m.subweaponReloadRequest.kind,'linked');
  e.c.ReloadManager.reloadMagazine(m,u,e.c._root);
  assert.deepEqual(attempts,['primary-pack'],'linked payment cannot occur after failed primary payment');
  assert.equal(u.长枪.value.shot,5);
  assert.equal(u.长枪副武器.value.shot,2);
  assert.equal(e.c.LongGunSubWeaponCore.getLoadedCount(u),0);
  assert.equal(u.长枪副武器状态.groupPaid,false);
});

test('261 both-empty sequence commits each paid magazine exactly once', () => {
  const e=environment(), {u,m}=e.fixture(0,0); prepareB1ResourceAdapters(e,u); e.stock(2);
  m.使用弹匣名称='primary-pack';u.长枪副武器配置.reserveName='secondary-pack';
  const attempts=[], submit=e.c.ItemUtil.singleSubmit;
  e.c.ItemUtil.singleSubmit=(name,amount,context)=>{
    attempts.push({name,amount});return submit(name,amount,context);
  };
  e.c.ReloadManager.startReload(m,u,e.c._root);
  assert.equal(m.subweaponReloadRequest.kind,'linked');
  e.c.ReloadManager.reloadMagazine(m,u,e.c._root);
  assert.deepEqual(attempts,[{name:'primary-pack',amount:1},{name:'secondary-pack',amount:1}]);
  assert.equal(e.submits,2);
  assert.equal(u.长枪.value.shot,0);
  assert.equal(u.长枪副武器.value.shot,0);
  assert.equal(e.c.LongGunSubWeaponCore.getLoadedCount(u),2);
  assert.equal(u.长枪副武器状态.groupPaid,true);
  e.c.ReloadManager.finishReload(m);
  e.c.ReloadManager.reloadMagazine(m,u,e.c._root);
  assert.equal(e.submits,2,'late commit after sequence completion is inert');
});

function deferredFixture() {
  const e=environment(), {u,m}=e.fixture(4,2);
  prepareB1ResourceAdapters(e,u);
  u.状态='长枪跑';u.移动射击=true;
  m.枪={枪:{装扮:{}}};
  u.状态改变=function(state){this.状态=state;};
  let accepted=0;
  // We observe the real eligibility/route boundary, not projectile dispatch or
  // AVM1 timeline effects. Existing native LongGun tests own cost/shot checks.
  e.c.ShootCore.startShootingAs=()=>{accepted++;return true;};
  assert.equal(e.c.LongGunSubWeaponCore.requestShoot(u),true);
  assert.equal(e.tasks.size,1);
  const [id,task]=[...e.tasks][0];
  return {e,u,m,id,task,get accepted(){return accepted;},ready(){m.枪.枪.装扮.枪口位置={};},
    run(t=task,taskId=id){e.tasks.delete(taskId);t.fn(...t.params);}};
}
test('deferred fire cannot cross equipment state replacement',()=>{
  const d=deferredFixture(), old=d.u.长枪副武器状态;
  d.u.长枪副武器状态={...old};delete d.u.长枪副武器状态.pendingFire;
  d.ready();d.run();
  assert.equal(d.accepted,0,'old equipment action cannot acquire the new state');
},true);
test('deferred old callback cannot steal a newer pending action',()=>{
  const d=deferredFixture();
  d.e.c.LongGunSubWeaponCore.cancelPendingFire(d.u);
  d.u.状态='长枪跑';d.e.c.LongGunSubWeaponCore.requestShoot(d.u);
  const fresh=d.u.长枪副武器状态.pendingFire;
  d.ready();d.run();
  assert.equal(d.accepted,0,'a retired callback must not fire using the fresh action');
  assert.equal(d.u.长枪副武器状态.pendingFire,fresh);
  assert.equal(d.e.tasks.size,1,'only the replacement readiness task survives');
},true);
test('deferred pause retires the pending action before shoot admission',()=>{
  const d=deferredFixture();d.ready();d.e.c._root.暂停=true;d.run();
  assert.equal(d.accepted,0,'the wheel still ticks while paused');
  assert.equal(d.e.tasks.size,0);
  assert.equal(d.u.长枪副武器状态.pendingFire,undefined);
},true);
test('deferred readiness rechecks a renewed secondary cooldown',()=>{
  const d=deferredFixture();d.u.长枪副武器状态.nextFireTime=10500;d.ready();d.run();
  assert.equal(d.accepted,0,'readiness does not grant a stale cooldown quote');
  assert.equal(d.u.长枪副武器状态.nextFireTime,10500);
},true);
test('deferred missing muzzle has a bounded retry count',()=>{
  const d=deferredFixture();let callbacks=0;
  while(d.e.tasks.size && callbacks<12){const [id,t]=[...d.e.tasks][0];d.run(t,id);callbacks++;}
  assert.equal(d.accepted,0);assert.equal(callbacks,4);assert.equal(d.e.tasks.size,0);
  assert.equal(d.u.长枪副武器状态.pendingFire,undefined);
  assert.equal(d.u.长枪副武器状态.nextFireTime,0);
});
test('accepted state replacement cancels deferred fire before goto',()=>{
  const d=deferredFixture();
  d.e.c.StateTransitionPlan={snapshot(){return {};},build(){return {
    storeFlyState:false,earlyReturn:false,transition:true,poseOnly:false,removeDynamicMan:false,
    attackMode:'长枪',oldState:'长枪行走',newLogicalState:'空中',gotoLabel:'空中'}}};
  d.e.c.RoutingIntent={executeStateTransitionJob(){},clearStateTransitionJob(){}};
  d.e.c.org.flashNight.arki.scene.Cf6SoldierSignals.playerState=()=>{};
  d.u.读取当前飞行状态=()=>{};
  d.u.gotoAndStop=function(){assert.equal(d.e.tasks.size,0,'retirement must precede native goto');};
  d.e.c.StateTransition.apply(d.u,'空中');
  d.ready();d.u.状态='长枪行走';d.run();
  assert.equal(d.accepted,0,'returning to the same action path cannot revive an old callback');
},true);
test('real reload cleanup retires secondary readiness without refunding cooldown',()=>{
  const d=deferredFixture();
  d.e.c.ShootCore.stopForReload=d.e.realStopForReload;
  // This test executes real stopForReload/cleanup/cleanupLane and cancellation.
  // Only the unrelated aggregate presentation projection is isolated.
  d.e.c.ShootCore.updateAggregateRecoil=()=>{};
  d.u.长枪副武器状态.nextFireTime=10500;
  d.e.c.ReloadManager.startReload(d.m,d.u,d.e.c._root);
  assert.ok(d.m.换弹标签);
  assert.equal(d.e.tasks.size,0,'reload must cancel the pending wheel task immediately');
  assert.equal(d.u.长枪副武器状态.pendingFire,undefined);
  assert.equal(d.u.长枪副武器状态.nextFireTime,10500,'cancellation does not release fire cadence');
},true);

let failed=0, unexpected=0;
try {
  for(const item of cases){
    let error=null;try{item.fn();}catch(e){error=e;}
    if(error)failed++;
    const expected=expectedBaseline&&item.baselineFailure;
    if(!!error!==expected || (error && error.name!=='AssertionError'))unexpected++;
    console.log(JSON.stringify({case:item.name,status:error?'FAIL':'PASS',expectedFailure:expected,
      ...(error?{reason:error.message}:{})}));
  }
  console.log(JSON.stringify({source:sourceRef||'working-tree',evidence:'AS2_SOURCE_BODY_WITH_ADAPTERS_NOT_AVM1',
    cases:cases.length,passed:cases.length-failed,failed,unexpected,baselineMode:expectedBaseline,observations}));
  process.exitCode=unexpected?1:0;
} finally {if(sourceRef)fs.rmSync(sourceDir,{recursive:true,force:true});}
