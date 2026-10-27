'use strict';
// Production method extraction with explicit memory ports, not an AVM1/game proof.
const assert = require('node:assert/strict');
const path = require('node:path');
const {createSource} = require('./source');
const source = createSource(process.argv[2] ? path.resolve(process.argv[2]) : path.resolve(__dirname, '../..'));
const file = 'scripts/类定义/org/flashNight/arki/unit/PlayerStatRefreshCoordinator.as';
function fixture() {
    const actor = {__playerStatBody:{},__playerStatInitializing:true};
    const state = {calls:0,readable:true};
    const adapter = {
        compute:()=>({}),captureResources:()=>({hp:500,mp:0}),
        settleResources(){},derive(){},verify:()=>true,unblock(){},
        canConsume:()=>state.readable,canProject:()=>true,block(){},isCurrent:()=>true,
    };
    const globals = {
        actor,body:actor.__playerStatBody,world:{},context:{},ready:true,
        batchDepth:1,flushing:false,transition:null,checkpoint:null,lastFailure:null,
        revision:1,projectedRevision:1,requested:[0,0,0],completed:[0,0,0],appliedBody:actor.__playerStatBody,
        adapter,planCurrent:p=>p.actor===globals.actor && p.body===globals.body,
        scenePending:()=>false,modeComponentsReady:()=>true,canonicalCurrent:()=>true,
        growthReadReason:()=>state.readable?'':'authority_pending',
        spawnResourceHook:()=>{},spawnReadyHook:()=>{state.calls++;},
        failOuterInitialization:()=>assert.fail('unexpected initialization failure'),
        org:{flashNight:{arki:{unit:{UnitComponent:{Initializer:{DressupInitializer:{}}}}}}},
    };
    const names = ['finishFullPlan','flush','result','dirtyMask','capture','current','accept'];
    if (source.read(file).text.includes('function publishInitialReady(')) names.push('publishInitialReady','flushProjection');
    const api = source.methods(file,names,globals);
    globals.PlayerStatRefreshCoordinator=api;
    const c = {...api,adapter,flushing:false,notifyReady:()=>true};
    const plan = {actor,body:globals.body,coordinator:c,open:0,complete:false,
        tailCheckpoint:{snapshot:api.capture(),record:{},resources:{hpDone:true,mpDone:true},stage:'settled'}};
    actor.__playerStatInitPlan=plan;
    return {state,globals,api,c,plan};
}
const results=[];
function check(name, run) {run();results.push(name);}
check('batch completion delivers the initial notification once',()=>{
    const f=fixture();
    assert.equal(f.api.finishFullPlan(f.plan).status,'pending');
    assert.equal(f.state.calls,0);
    f.globals.batchDepth=0;
    assert.equal(f.c.flush('batch_closed').status,'unchanged');
    assert.equal(f.state.calls,1,'completed initialization must deliver after its pending flush settles');
    f.c.flush('another_read');f.api.finishFullPlan(f.plan);
    assert.equal(f.state.calls,1);
});
check('authority waiting does not lose the eventual initial notification',()=>{
    const f=fixture();f.globals.batchDepth=0;f.state.readable=false;
    assert.equal(f.api.finishFullPlan(f.plan).status,'pending');
    assert.equal(f.state.calls,0);
    f.state.readable=true;f.c.flush('authority_resolved');
    assert.equal(f.state.calls,1);
});
check('ordinary ready projection does not manufacture another spawn',()=>{
    const f=fixture();f.globals.batchDepth=0;f.api.finishFullPlan(f.plan);
    assert.equal(f.state.calls,1);
    f.globals.actor.hp=250;f.c.flush('after_damage');
    assert.equal(f.globals.actor.hp,250);assert.equal(f.state.calls,1);
});
check('a replaced actor cannot receive an old pending notification',()=>{
    const f=fixture();f.api.finishFullPlan(f.plan);
    f.globals.batchDepth=0;f.globals.body={};
    f.api.publishInitialReady(f.globals.actor);
    assert.equal(f.state.calls,0);
});
check('a callback failure retains the originating context snapshot',()=>{
    const f=fixture();f.globals.batchDepth=0;
    const originalContext=f.globals.context;
    let failedSnapshot;
    f.globals.fail=(snapshot)=>{failedSnapshot=snapshot;return {status:'failed'};};
    f.globals.spawnReadyHook=()=>{f.globals.context={};throw new Error('scene replaced');};
    assert.equal(f.api.finishFullPlan(f.plan).status,'failed');
    assert.equal(failedSnapshot.context,originalContext);
    assert.notEqual(failedSnapshot.context,f.globals.context);
});
console.log(JSON.stringify({evidenceTier:'node-source-extraction',passed:results.length,results,sourceEvidence:source.evidence}));
