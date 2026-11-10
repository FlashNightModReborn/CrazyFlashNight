'use strict';
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const vm=require('vm');
const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'scripts/类定义/org/flashNight/arki/scene/StageManager.as'),'utf8');
function extract(name,input=source,prefix='public function ') {
    const start=input.indexOf(prefix+name+'(');
    assert(start>=0);const open=input.indexOf('{',start);let depth=1,end=open+1;
    for(;depth&&end<input.length;end++) {if(input[end]==='{')depth++;else if(input[end]==='}')depth--;}
    assert.equal(depth,0);
    return input.slice(open+1,end-1).replace(/\bvar ([\p{L}\p{N}_$]+):[\p{L}\p{N}_$.]+/gu,'var $1');
}
const body=extract('onPlayerReady');
function fixture(mode,held=false) {
    const state={ready:true,held,start:0,waves:0,failures:0};
    const gate={published:true};
    let run;
    const manager={
        onPlayerInitializationFailed(g,error){assert.strictEqual(g,gate);assert(error);state.failures++;state.ready=false;},
    };
    gate.manager=manager;
    const context={
        org:{flashNight:{arki:{scene:{
            PlayerSceneLifecycle:{isReady:g=>g===gate&&state.ready},
            StageIntroService:{deferStart:g=>{assert.strictEqual(g,gate);return state.held;},noteStart:()=>{}},
        }}}},
        gameworld:{dispatcher:{publish(name){assert.equal(name,'Start');state.start++;
            if(mode==='reenter')run.call(manager,gate);
            if(mode==='retire')state.ready=false;
            if(mode==='throw')throw Error('listener failed');
        }}},
        currentStageInfo:{waveInfo:[]},spawner:{init(){state.waves++;}},
        onPlayerInitializationFailed:(g,error)=>manager.onPlayerInitializationFailed(g,error),
    };
    vm.createContext(context);run=vm.runInContext('(function(gate){'+body+'})',context);
    return {state,gate,ready:()=>run.call(manager,gate)};
}
let h=fixture('reenter');h.ready();h.ready();
assert.equal(h.state.start,1);assert.equal(h.state.waves,1,'synchronous Start reentry cannot initialize waves twice');
h=fixture('retire');h.ready();assert.equal(h.state.start,1);assert.equal(h.state.waves,0,'retired world is rechecked after dispatch');
h=fixture('ordinary',true);h.ready();assert.equal(h.state.start,0);assert.equal(h.state.waves,0);
h.state.held=false;h.ready();h.ready();assert.equal(h.state.start,1);assert.equal(h.state.waves,1,'eligible intro resumes pending Start exactly once');
h=fixture('throw');h.ready();assert.equal(h.state.failures,1);assert.equal(h.state.waves,0);
assert.equal(h.gate.startDispatching,false,'failed listener does not leave a live transaction claim');
h.ready();assert.equal(h.state.start,1,'failed initialization is not blindly replayed');
const vehicleSource=fs.readFileSync(path.join(root,'scripts/类定义/org/flashNight/arki/scene/Cf6VehicleService.as'),'utf8');
const context={current:()=>true,Cf6VehicleActorAdapter:{current:()=>true},
    PauseManager:{isPaused:()=>false},_root:{场景转换中:false},
    readInput:()=>{throw Error('live input polled');}};
vm.createContext(context);
const tickVehicle=vm.runInContext('(function(s){'+extract('tick',vehicleSource,'public static function ')+'})',context);
const vehicle={closed:false,status:'playing',world:{__stageIntroExecutionHeld:true,__combatAdmitted:false},
    actorAdapter:{hero:{hp:10}},age:7,rules:{phase:'playing',frame:17}};
for(let i=0;i<300;i++)assert.equal(tickVehicle(vehicle),'playing');
assert.equal(vehicle.age,7);assert.equal(vehicle.rules.frame,17);
vehicle.world.__stageIntroExecutionHeld=false;
for(let i=0;i<60;i++)assert.equal(tickVehicle(vehicle),'playing','vehicle playing remains held while __combatAdmitted===false');
assert.equal(vehicle.age,7);assert.equal(vehicle.rules.frame,17);
vehicle.world.__combatAdmitted=true;
assert.throws(()=>tickVehicle(vehicle),/live input polled/,'input polling resumes only after __combatAdmitted===true');
let domainCalls=0,finishCalls=0;
const control={isActive:true,isFinished:false,isFailed:false,stageMode:'warlord',
    gameworld:{__stageIntroExecutionHeld:true,__combatAdmitted:false},trace:()=>finishCalls++,
    org:{flashNight:{arki:{scene:{LeeAssaultService:{
        interceptClear:()=>{domainCalls++;return true;},canAdvance:()=>{domainCalls++;return false;}
    }}}}}};
vm.createContext(control);
const controls=['clearStage','nextStage','finishStage'].map(name=>vm.runInContext('(function(){'+extract(name)+'})',control));
for(const run of controls)run();
assert.equal(domainCalls,0);assert.equal(finishCalls,0);assert.equal(control.isFinished,false);
control.gameworld.__stageIntroExecutionHeld=false;
controls[0]();controls[2]();
assert.equal(domainCalls,0,'clearStage rejected while __combatAdmitted===false');
assert.equal(finishCalls,0,'finishStage rejected while __combatAdmitted===false');
control.gameworld.__combatAdmitted=true;
for(const run of controls)run();
assert.equal(domainCalls,2);assert.equal(finishCalls,1,'grant restores the existing clear, advance and finish authorities');

// CF6 combatAdmission matrix (curtainReleased && narrativeDone && roomReady && !__stageIntroExecutionHeld)
function createAdmissionFixture() {
    const state={ready:true,held:false,start:0,waves:0,failures:0,clockTicks:0,savePath:'slot_a',
        bookRun:{bookId:'cf6-sting',routeId:'historical',slot:'slot_a',seed:17,startedAt:100,outcome:'active'}};
    const owner={};
    const world={
        __stageReturnWorldIdentity:owner,
        __stageIntroExecutionHeld:false,
        dispatcher:{publish(name){
            assert.equal(name,'Start');
            state.start++;
            if(state.onStart)state.onStart();
        }}
    };
    const ctx={
        _global:{ASSetPropFlags(){}},
        _root:{gameworld:world,savePath:'slot_a',_saveExt:{bookRun:state.bookRun}},
        StageReturnFlow:{worldIdentity:w=>w&&w.__stageReturnWorldIdentity},
        isActive:true,isFinished:false,isFailed:false,
        gameworld:world,currentStage:0,combatAdmission:null,
        currentStageInfo:{waveInfo:[{}],basicInfo:{Cf6MapId:'A01',Cf6ChapterIndex:3}},
        spawner:{init(){state.waves++;}},
        org:{flashNight:{
            gesh:{object:{PersistedSnapshot:{clone:o=>JSON.parse(JSON.stringify(o))}}},
            arki:{scene:{
                StageReturnFlow:{worldIdentity:w=>w&&w.__stageReturnWorldIdentity},
                BookRunRules:{sameCf6Run:(a,b)=>Boolean(a&&b&&a.bookId==='cf6-sting'&&b.bookId==='cf6-sting'&&a.routeId===b.routeId&&b.outcome==='active'&&a.slot===b.slot&&a.seed===b.seed&&a.startedAt===b.startedAt)},
                PlayerSceneLifecycle:{isReady:g=>Boolean(g&&g===state.gate&&state.ready&&ctx._root.gameworld===world&&ctx.gameworld===world&&ctx.currentStage===g.stage)},
                StageIntroService:{deferStart:g=>{assert.strictEqual(g,state.gate);return state.held;},noteStart:()=>{}},
                BookRunClock:{tick(){state.clockTicks++;}}
            }}
        }},
        onPlayerInitializationFailed(g,err){state.failures++;state.ready=false;}
    };
    vm.createContext(ctx);
    const self=vm.runInContext('this',ctx);
    const methods=['beginCombatAdmission','isCombatAdmissionCurrent','canAdmitCombat','matchesCombatAdmission',
        'retryCombatAdmissionGate','revokeCombatAdmission','noteCurtainReleased','noteNarrativeDone','noteRoomReady',
        'noteCombatAdmissionFailed','currentBookChapterIndex','onPlayerReady'];
    for(const m of methods) {
        const prefix=['matchesCombatAdmission','retryCombatAdmissionGate','revokeCombatAdmission'].includes(m)?'private function ':'public function ';
        ctx[m]=vm.runInContext('(function('+extractParams(m,source,prefix)+'){'+extract(m,source,prefix)+'})',ctx).bind(self);
    }
    state.gate={manager:self,world:owner,stage:0,published:true};
    return {state,ctx:self,world,owner};
}
function extractParams(name,input=source,prefix='public function ') {
    const start=input.indexOf(prefix+name+'(');
    assert(start>=0,'missing '+name);
    const open=input.indexOf('(',start)+1;
    const close=input.indexOf(')',open);
    return input.slice(open,close).replace(/:[\p{L}\p{N}_$.]+/gu,'');
}

// 1. Comic + dialogue + arrival: tryGrant clears __stageIntroExecutionHeld, roomReady admits combat
{
    const f=createAdmissionFixture();
    f.state.held=true;
    f.world.__stageIntroExecutionHeld=true;
    const rec=f.ctx.beginCombatAdmission(f.world,3,'A01');
    assert.equal(f.world.__combatAdmitted,false);
    assert.equal(f.ctx.currentBookChapterIndex(f.world,f.owner),3,'startAt > 0 preserves Cf6ChapterIndex=3');
    f.ctx.onPlayerReady(f.state.gate);
    assert.strictEqual(rec.playerGate,f.state.gate,'playerGate recorded before StageIntroService.deferStart');
    assert.equal(f.state.start,0);assert.equal(f.state.waves,0);
    assert.equal(f.ctx.noteCurtainReleased(f.world,f.owner),true);
    assert.equal(f.ctx.noteNarrativeDone(f.world,f.owner,3),true);
    f.state.held=false;f.world.__stageIntroExecutionHeld=false;
    f.ctx.onPlayerReady(f.state.gate);
    assert.equal(f.world.__combatAdmitted,false,'still false before roomReady');
    assert.equal(f.state.start,0);assert.equal(f.state.waves,0);
    assert.equal(f.ctx.noteRoomReady(f.world,f.owner,'A01'),true);
    assert.equal(f.world.__combatAdmitted,true,'admitted once roomReady arrives');
    assert.equal(f.state.start,1);assert.equal(f.state.waves,1);assert.equal(f.state.clockTicks,1);
    // Duplicate signals remain idempotent
    f.ctx.noteCurtainReleased(f.world,f.owner);
    f.ctx.noteNarrativeDone(f.world,f.owner,3);
    f.ctx.noteRoomReady(f.world,f.owner,'A01');
    f.ctx.onPlayerReady(f.state.gate);
    assert.equal(f.state.start,1);assert.equal(f.state.waves,1);
}

// 2. Non-comic + dialogue: roomReady before narrativeDone waits for narrativeDone
{
    const f=createAdmissionFixture();
    f.ctx.beginCombatAdmission(f.world,2,'A02');
    f.ctx.onPlayerReady(f.state.gate);
    f.ctx.noteCurtainReleased(f.world,f.owner);
    f.ctx.noteRoomReady(f.world,f.owner,'A02');
    assert.equal(f.world.__combatAdmitted,false,'roomReady alone cannot admit before narrativeDone');
    assert.equal(f.state.start,0);assert.equal(f.state.waves,0);
    f.ctx.noteNarrativeDone(f.world,f.owner,2);
    assert.equal(f.world.__combatAdmitted,true);
    assert.equal(f.state.start,1);assert.equal(f.state.waves,1);
}

// 3. Start callback replacing world aborts spawner.init, marks failed=true and revokes __combatAdmitted
{
    const f=createAdmissionFixture();
    const rec=f.ctx.beginCombatAdmission(f.world,0,'TUTORIAL');
    f.state.onStart=()=>{f.ctx._root.gameworld={__stageReturnWorldIdentity:{}};};
    f.ctx.noteCurtainReleased(f.world,f.owner);
    f.ctx.noteNarrativeDone(f.world,f.owner,0);
    f.ctx.noteRoomReady(f.world,f.owner,'TUTORIAL');
    f.ctx.onPlayerReady(f.state.gate);
    assert.equal(f.state.start,1);
    assert.equal(f.state.waves,0,'Start world replacement aborts spawner.init');
    assert.equal(f.world.__combatAdmitted,false,'__combatAdmitted revoked on Start world replacement');
    assert.equal(rec.failed,true,'admission permanently marked failed after Start world replacement');
    f.ctx._root.gameworld=f.world;
    f.ctx.noteRoomReady(f.world,f.owner,'TUTORIAL');
    f.ctx.onPlayerReady(f.state.gate);
    assert.equal(f.state.waves,0,'restored world cannot re-admit or initialize waves after failed Start');
    assert.equal(f.world.__combatAdmitted,false);
}

// 4. Mechanism load failure marks combatAdmission failed and prevents admission
{
    const f=createAdmissionFixture();
    f.ctx.beginCombatAdmission(f.world,1,'A01');
    f.ctx.onPlayerReady(f.state.gate);
    f.ctx.noteCurtainReleased(f.world,f.owner);
    f.ctx.noteNarrativeDone(f.world,f.owner,1);
    f.ctx.noteCombatAdmissionFailed(f.world,f.owner);
    assert.equal(f.ctx.noteRoomReady(f.world,f.owner,'A01'),false);
    assert.equal(f.world.__combatAdmitted,false);
    assert.equal(f.state.start,0);assert.equal(f.state.waves,0);
}
// A same-path replacement retains its MovieClip handle while changing the plain
// world owner. The old Start stack cannot revoke a newer record after reentry.
{
    const f=createAdmissionFixture();
    const old=f.ctx.beginCombatAdmission(f.world,0,'A01');
    let current,before;
    f.state.onStart=()=> {
        f.state.onStart=null;
        f.world.__stageReturnWorldIdentity={};f.ctx.currentStage=1;
        current=f.ctx.beginCombatAdmission(f.world,1,'A02');
        f.state.gate={manager:f.ctx,world:f.world.__stageReturnWorldIdentity,stage:1,published:true};
        f.ctx.noteCurtainReleased(f.world,current.owner);
        f.ctx.noteNarrativeDone(f.world,current.owner,1);
        f.ctx.noteRoomReady(f.world,current.owner,'A02');
        f.ctx.onPlayerReady(f.state.gate);before=f.world.__combatAdmitted;
    };
    f.ctx.noteCurtainReleased(f.world,f.owner);
    f.ctx.noteNarrativeDone(f.world,f.owner,0);
    f.ctx.noteRoomReady(f.world,f.owner,'A01');
    f.ctx.onPlayerReady(f.state.gate);
    assert.equal(before,true);assert.equal(f.world.__combatAdmitted,true);
    assert.equal(old.failed,true);assert.equal(current.failed,false);
    assert.equal(f.state.waves,1);assert.equal(f.state.gate.wavesStarted,true);
}
console.log('Stage intro admission: pending/resume, CF6 combatAdmission matrix, Start reentry, same-path owner replacement, failure recovery, direct stage controls and vehicle simulation permission passed (source functions, not AVM1).');
