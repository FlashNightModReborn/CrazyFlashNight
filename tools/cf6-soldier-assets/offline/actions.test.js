'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const path = require('node:path');
const fs = require('node:fs');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const { loadFunctions } = require('./as2-source');
const root = path.resolve(__dirname, '../../..');
const generated = spawnSync('python', ['-X', 'utf8', '-c',
  'import sys,json;sys.path.insert(0,"tools/cf6-type61");import fixed_roster;items=fixed_roster.item_catalog();print(json.dumps({r["unitIdentity"]:fixed_roster.profile(r,items) for r in fixed_roster.read_source()["roster"]}))'],
{ cwd: root, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
assert.equal(generated.status, 0, generated.stderr);
const profiles = JSON.parse(generated.stdout);
const rules = vm.createContext({ Math, isFinite });
for (const file of ['FixedActionRules.as', 'FixedActionTriggers.as']) {
  const full = path.join(root, 'tools/cf6-soldier-assets', file);
  const names = [...fs.readFileSync(full, 'utf8').matchAll(/^(cf6Rule\w+)=function\(/gm)].map(x => x[1]);
  loadFunctions(rules, full, names);
}
const byTactic = name => Object.values(profiles).find(p => p.program.trigger === name);
function fixture(p) {
  const o = { world:'world1', birth:'birth1', actorVersion:7, frame:0, paused:false,
    alive:true, retired:false, controlled:false, interrupted:false, phase:1,
    targetValid:true, targetKey:'player1', targetVersion:3, visible:true, lineClear:true, sameLane:true,
    distance:230, height:0, inFront:true, retreatAvailable:true, atAnchor:true,
    movingAway:true, approaching:true, subReady:true, primaryLoaded:true, throwReady:true,
    attackEvent:1, attackAge:0, shieldEvent:1, wingsEvent:1, wingsRecovery:true,
    reloadEvent:1, commitEvent:1, commitAge:0, reserveEvent:1, robotEvent:1,
    robotRecovery:true, crossEvent:1, pairEligible:true, fixedModeValid:true, pairTurn:true,
    humanGuardValid:true, guardThreat:true, guardTether:true, behindBirth:false,
    permit:true, subPermit:true, modeReady:true, readyMode:'primary', chargeTerminal:0,
    moveBlocked:false, projectilesTerminal:true, targetX:300,targetY:200,targetZ:300,faceSign:1 };
  if (['reverse_rear_guard','range_rotation','feint_retreat','punish_commit'].includes(p.program.trigger)) o.phase=2;
  const s=rules.cf6RuleCreate(o.world,o.birth,o.actorVersion), c={};
  return {p,o,s,c,events:[],warnings:new Map()};
}
function units(p, bit) {
  if (bit===1) return p.budget.primaryFinalDamageUnitsPerAction===undefined?p.budget.primarySplit:p.budget.primaryFinalDamageUnitsPerAction/p.budget.primaryTriggerLimit;
  if (bit===8) return p.budget.subweaponFinalDamageUnitsPerAction;
  if (bit===16) return 2;
  return p.budget.sidearmProjectilesPerAction/(2*p.budget.sidearmSynchronizedTriggerLimit);
}
function tick(f, commit=true) {
  if(f.o.frame>5000)throw new Error('Bounded source-action fixture exceeded 5000 frames: '+f.p.program.trigger);
  const {p,o,s,c}=f;
  if(s.active) {
    const stage=p.program[s.variant][s.index];
    o.readyMode=stage.mode;
    if(stage.kind==='charge' && o.frame-s.entered>=15) o.chargeTerminal=1;
    if(stage.kind==='move') s.stageMoved+=stage.distance/stage.frames;
  }
  rules.cf6RuleStep(s,p,o,c);
  if(c.warning)f.warnings.set(c.stage,(f.warnings.get(c.stage)||0)+1);
  if(commit) for(const bit of [1,2,4,8,16]) if(c.fireMask&bit){
    const cost=units(p,bit);
    assert.equal(rules.cf6RuleCanCommit(s,p,o,bit,cost),true,`${p.program.trigger} bit ${bit}`);
    rules.cf6RuleCommitted(s,p,o,bit,cost);
    f.events.push({frame:o.frame,bit,stage:s.index});
    assert.equal(rules.cf6RuleCanCommit(s,p,o,bit,cost),false,'same-frame duplicate commit');
  }
  o.frame++;
}

test('all 158 profiles compile to bounded closed programs; all 22 main cycles terminate',()=>{
  assert.equal(Object.keys(profiles).length,158);
  const instructors=Object.values(profiles).filter(p=>p.roleClass==='instructor');
  assert.equal(new Set(instructors.map(p=>p.program.trigger)).size,22);
  for(const p of instructors){
    const f=fixture(p);
    while(f.s.terminal===0 && f.o.frame<1600)tick(f);
    assert.equal(f.s.cancelReason,'complete',p.program.trigger);
    assert.equal(f.s.cycle,1,p.program.trigger);
    assert.ok(f.events.length>0,p.program.trigger);
    assert.ok(f.s.primary<=p.budget.primaryTriggerLimit);
    assert.ok(f.s.left<=p.budget.sidearmSynchronizedTriggerLimit);
    assert.ok(f.s.right<=p.budget.sidearmSynchronizedTriggerLimit);
    assert.ok(f.s.damageUnits<=p.budget.scriptedCycleDamageUnits);
    for(const [i,seen]of f.warnings)assert.ok(seen>=p.program.stages[i].frames+1);
  }
});

test('no primary can occur in charge, movement, draw, warning, handoff or recovery',()=>{
  for(const p of Object.values(profiles).filter(p=>p.roleClass==='instructor')){
    const f=fixture(p);
    while(!f.s.terminal && f.o.frame<1600){
      tick(f,false);
      if(f.c.kind!=='fire')for(const bit of [1,2,4,8,16])
        assert.equal(rules.cf6RuleCanCommit(f.s,p,{...f.o,frame:f.o.frame-1},bit,1),false,p.program.trigger);
      if(f.c.kind==='fire'){
        f.o.frame--;
        for(const bit of [1,2,4,8,16])if(f.c.fireMask&bit)rules.cf6RuleCommitted(f.s,p,f.o,bit,units(p,bit));
        f.o.frame++;
      }
    }
  }
});

test('ordinary precision unit opens fire within four active frames of an eligible target',()=>{
  const p=Object.values(profiles).find(p=>p.roleClass==='ordinary'&&p.role==='precision');
  const f=fixture(p);f.o.distance=p.program.fireDistance+1;
  for(let i=0;i<60;i++)tick(f);
  assert.equal(f.s.cycle,0);f.o.distance=300;
  while(!f.events.length)tick(f);
  assert.ok(f.events[0].frame>=60 && f.events[0].frame<=64);
});

test('fixed target generation and final lock cannot silently retarget',()=>{
  const f=fixture(byTactic('judgment_line'));
  while(!f.s.locked){f.o.targetX+=2;tick(f,false);}
  const lockedX=f.s.aimX;
  f.o.targetX=900;tick(f,false);
  assert.equal(f.s.aimX,lockedX);
  f.o.targetVersion++;tick(f);
  assert.equal(f.s.cancelReason,'target_or_permission');
  assert.equal(f.events.length,0);
});

test('mode readiness cannot consume invisible warning frames',()=>{
  const f=fixture(byTactic('punish_commit'));f.o.modeReady=false;
  for(let i=0;i<20;i++)tick(f);
  assert.equal(f.events.length,0);assert.equal(f.warnings.size,0);
  f.o.modeReady=true;
  while(!f.events.length)tick(f);
  assert.ok(f.events[0].frame>=20 && f.events[0].frame<=25);
});

test('offscreen, death, hit, retirement, control, world, actor and phase changes cancel before a real commit',()=>{
  const mutations=[{visible:false},{alive:false},{interrupted:true},{retired:true},{controlled:true},
    {world:'new-world'},{actorVersion:8},{phase:2},{targetKey:'replacement'},{targetVersion:4}];
  for(const mutation of mutations){
    const f=fixture(byTactic('bright_burst'));
    while(!f.c.fireMask)tick(f,false);
    f.o.frame--;Object.assign(f.o,mutation);
    assert.equal(rules.cf6RuleCanCommit(f.s,f.p,f.o,1,5),false,JSON.stringify(mutation));
    f.o.frame++;tick(f);
    assert.equal(f.s.active,false);
    assert.ok(f.s.readyAt>f.o.frame);
  }
});

test('phase transition and cancelled pose retain event receipt and recovery, without regrant',()=>{
  const f=fixture(byTactic('reserve_gate'));
  while(!f.events.length)tick(f);
  const used=f.s.primary,consumed=f.s.reserveConsumed;
  f.o.phase=2;tick(f);
  assert.equal(f.s.primary,used);assert.equal(f.s.reserveConsumed,consumed);
  for(let i=0;i<180;i++)tick(f);
  assert.equal(f.s.cycle,1);
  f.o.reserveEvent++;while(f.s.cycle<2)tick(f);
  assert.equal(f.s.reserveConsumed,2);
});

test('actual projectile terminal gates the advance; timeout does not imply terminal',()=>{
  const f=fixture(byTactic('advance_flush'));f.o.projectilesTerminal=false;
  while(f.c.kind!=='projectile_wait')tick(f);
  f.o.subReady=false; // the real paid grenade is now empty
  while(!f.s.terminal)tick(f);
  assert.equal(f.s.cancelReason,'projectile_unknown');
  assert.equal(f.s.primary,3);assert.equal(f.s.sub,1);
  const g=fixture(byTactic('advance_flush'));g.o.projectilesTerminal=false;
  while(g.c.kind!=='projectile_wait')tick(g);
  g.o.subReady=false;for(let i=0;i<12;i++)tick(g);
  g.o.projectilesTerminal=true;
  while(!g.s.terminal)tick(g);
  assert.equal(g.s.cancelReason,'complete');
});

test('one initial launcher token, fresh reload token, no refund after cancellation',()=>{
  const f=fixture(byTactic('relocate_then_flush'));
  tick(f);f.o.visible=false;tick(f);f.o.visible=true;
  for(let i=0;i<240;i++)tick(f);
  assert.equal(f.s.cycle,1);assert.equal(f.events.length,0);
  f.o.reloadEvent++;while(!f.s.active)tick(f);
  assert.equal(f.s.cycle,2);
});

test('observer tactics do not fire without real event receipts',()=>{
  for(const name of ['landing_watch','reserve_gate','robot_observer','threshold_flush','punish_commit','reverse_rear_guard']){
    const f=fixture(byTactic(name));
    for(const key of ['wingsEvent','reserveEvent','robotEvent','crossEvent','commitEvent','attackEvent'])f.o[key]=0;
    for(let i=0;i<600;i++)tick(f);
    assert.equal(f.events.length,0,name);
  }
});

test('pause is inert; delayed old callback and excess damage units are denied',()=>{
  const f=fixture(byTactic('bright_burst'));
  tick(f);f.o.paused=true;
  const before=JSON.stringify(f.s);for(let i=0;i<20;i++)rules.cf6RuleStep(f.s,f.p,f.o,f.c);
  assert.equal(JSON.stringify(f.s),before);f.o.paused=false;
  while(!f.c.fireMask)tick(f,false);
  assert.equal(rules.cf6RuleCanCommit(f.s,f.p,f.o,1,5),false,'old frame');
  f.o.frame--;
  assert.equal(rules.cf6RuleCanCommit(f.s,f.p,f.o,1,11),false,'unbudgeted event');
});

test('instructor combat signatures remain distinct at the real event level',()=>{
  const expected={segmented_lane:[3,0,0],landing_watch:[2,0,0],bright_burst:[2,0,0],
    relocate_then_flush:[1,0,0],advance_flush:[3,0,1],range_rotation:[3,1,0],
    weapon_handoff:[2,1,0],punish_commit:[2,0,0],reserve_gate:[1,0,0],threshold_flush:[2,0,0]};
  for(const [name,counts]of Object.entries(expected)){
    const f=fixture(byTactic(name));while(!f.s.terminal)tick(f);
    assert.deepEqual([f.s.primary,f.s.left,f.s.sub],counts,name);
    if(name==='landing_watch')assert.ok(f.events[1].frame-f.events[0].frame>=30);
    if(name==='punish_commit')assert.ok(f.events[1].frame-f.events[0].frame>=9);
    if(name==='threshold_flush')assert.ok(f.events[1].frame-f.events[0].frame>=7);
  }
});

test('hard obstruction cancels an unissued warning and cannot pass the real commit gate',()=>{
 const p=byTactic('judgment_line'),f=fixture(p);tick(f);f.o.lineClear=false;tick(f);
 assert.equal(f.s.active,false);assert.equal(f.s.primary,0);
 assert.equal(rules.cf6RuleCanCommit(f.s,p,f.o,1,1),false);
});

test('finite grenades charge carrier and explosion once across later action cycles',()=>{
 const p=profiles['CF6-C-WA-K-05'],f=fixture(p);f.o.phase=2;f.o.frame=100;
 while(f.s.terminal<3)tick(f);
 assert.equal(f.events.filter(e=>e.bit===16).length,1);assert.equal(f.s.throwUsed,1);
});

test('a reactive instructor applies bounded gun pressure while its authored signal is absent',()=>{
  const f=fixture(byTactic('reserve_gate'));f.o.reserveEvent=0;f.o.pressureReady=true;
  while(!f.s.terminal)tick(f);
  assert.equal(f.s.variant,'pressure');assert.ok(f.events.length>0 && f.events.length<=3);
  assert.equal(f.s.reserveConsumed,0);
  f.o.reserveEvent=1;tick(f);assert.equal(f.s.variant,'stages');
});
test('an interrupted unissued shot reacquires quickly; issued rounds retain their recovery',()=>{
  const early=fixture(byTactic('judgment_line'));tick(early,false);
  early.o.interrupted=true;const before=early.o.frame;tick(early,false);
  assert.equal(early.s.readyAt,before+2);
  const fired=fixture(byTactic('bright_burst'));while(!fired.events.length)tick(fired);
  fired.o.interrupted=true;const when=fired.o.frame;tick(fired);
  assert.ok(fired.s.readyAt>=when+fired.p.program.recovery);
});

test('empty FSC7 and the active smoke fade cannot start a pressure cycle',()=>{
  const f=fixture(byTactic('relocate_then_flush'));
  Object.assign(f.o,{pressureReady:true,reloadEvent:0,primaryLoaded:false});
  for(let i=0;i<12;i++)tick(f);
  assert.equal(f.s.cycle,0);
  Object.assign(f.o,{primaryLoaded:true,reloadHidden:true});
  for(let i=0;i<12;i++)tick(f);
  assert.equal(f.s.cycle,0);
  Object.assign(f.o,{reloadHidden:false,reloadEvent:2});
  tick(f);
  assert.equal(f.s.variant,'stages');
});

test('every seat preserves the screen boundary, primary-only distance band and final commit range',()=>{
  let extended=0;
  for(const [identity,p] of Object.entries(profiles)){
    const f=fixture(p), a=p.program;
    assert.ok(a.fireDistance>=a.maxDistance && a.fireDistance<=1200,identity);
    assert.ok(a.stopDistance<a.fireDistance,identity);
    Object.assign(f.o,{distance:a.fireDistance,visible:false,pressureReady:true});
    for(let i=0;i<10;i++)tick(f);
    assert.equal(f.s.cycle,0,identity+' offscreen');
    if(a.fireDistance===a.maxDistance)continue;
    extended++;f.o.visible=true;
    for(let i=0;i<16 && !f.events.length;i++){
      tick(f,false);
      if(!f.c.fireMask)continue;
      const at=f.o.frame-1;
      const cost=units(p,1);
      assert.equal(f.s.variant,'pressure',identity);
      assert.equal(f.c.fireMask,1,identity);
      assert.equal(rules.cf6RuleCanCommit(f.s,p,{...f.o,frame:at,distance:a.fireDistance+1},1,cost),false,identity);
      assert.equal(rules.cf6RuleCanCommit(f.s,p,{...f.o,frame:at,visible:false},1,cost),false,identity);
      assert.equal(rules.cf6RuleCanCommit(f.s,p,{...f.o,frame:at,lineClear:false},1,cost),false,identity);
      assert.equal(rules.cf6RuleCanCommit(f.s,p,{...f.o,frame:at},1,cost),true,identity);
      f.events.push({bit:1});
    }
    assert.equal(f.events.length,1,identity+' visible, aligned shot');
  }
  assert.ok(extended>=150);
});

test('a blocked gunner takes a walkable corner, reuses it, and drops it on a collision revision', () => {
  const room = {};
  const bounds = {Xmin: 80, Xmax: 1430, Ymin: 400, Ymax: 520, collisionLayer: {}};
  const nav = vm.createContext({_root: bounds, Math});
  const names = ['cf6NavSegment', 'cf6NavSpace', 'cf6NavGridRoute', 'cf6NavWaypoint'];
  loadFunctions(nav, path.resolve(__dirname, '../FixedNavigation.as'), names);
  const actor = {_x: 976, Z轴坐标: 479, cf6NavStalls: 0, cf6NavPlans: 0,
    cf6Collision: {revision: 1}, cf6ActionApi: {context: () => room},
    cf6Ground: {isPointValid: (x, z) => !(x >= 830 && x <= 1228 && z < 477)}};
  for (const name of names) actor[name] = nav[name];
  const target = {_x: 1230, Z轴坐标: 425, version: 5};
  const obs = {frame: 10};
  assert.equal(actor.cf6NavWaypoint(target, obs, 180), null);
  actor.cf6NavStalls = 3;
  const corner = actor.cf6NavWaypoint(target, obs, 180);
  assert.equal(corner.z, 479);
  assert.ok(corner.x > target._x);
  assert.equal(actor.cf6NavWaypoint(target, {...obs, frame: 11}, 180), corner);
  assert.equal(actor.cf6NavPlans, 1);
  assert.equal(room.groundNavigation, undefined);
  actor.cf6Collision.revision++;
  assert.equal(actor.cf6NavWaypoint(target, {...obs, frame: 12}, 180), null);
  assert.equal(actor.cf6GroundRoute, null);
});
