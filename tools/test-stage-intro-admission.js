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
const vehicle={closed:false,status:'playing',world:{__stageIntroExecutionHeld:true},
    actorAdapter:{hero:{hp:10}},age:7,rules:{phase:'playing',frame:17}};
for(let i=0;i<300;i++)assert.equal(tickVehicle(vehicle),'playing');
assert.equal(vehicle.age,7);assert.equal(vehicle.rules.frame,17);
vehicle.world.__stageIntroExecutionHeld=false;
assert.throws(()=>tickVehicle(vehicle),/live input polled/,'input polling resumes only after execution is granted');
let domainCalls=0,finishCalls=0;
const control={isActive:true,isFinished:false,isFailed:false,stageMode:'warlord',
    gameworld:{__stageIntroExecutionHeld:true},trace:()=>finishCalls++,
    org:{flashNight:{arki:{scene:{LeeAssaultService:{
        interceptClear:()=>{domainCalls++;return true;},canAdvance:()=>{domainCalls++;return false;}
    }}}}}};
vm.createContext(control);
const controls=['clearStage','nextStage','finishStage'].map(name=>vm.runInContext('(function(){'+extract(name)+'})',control));
for(const run of controls)run();
assert.equal(domainCalls,0);assert.equal(finishCalls,0);assert.equal(control.isFinished,false);
control.gameworld.__stageIntroExecutionHeld=false;
for(const run of controls)run();
assert.equal(domainCalls,2);assert.equal(finishCalls,1,'grant restores the existing clear, advance and finish authorities');
console.log('Stage intro admission: pending/resume, Start reentry, world retirement, failure recovery, direct stage controls and vehicle simulation permission passed (source functions, not AVM1).');
