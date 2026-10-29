'use strict';
// Executes the production refresh path with explicit authority and pause ports.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {createSource}=require('./source');
const source=createSource(process.argv[2]||path.resolve(__dirname,'../..'));
const file='scripts/类定义/org/flashNight/arki/unit/PlayerStatRefreshCoordinator.as';
const results=[];
function fixture() {
    const actor={__playerStatBody:{},hp:80,mp:0,enableShoot:true};
    const state={readable:false,blocked:false,computes:0,acquired:0,released:0,claims:new Set(['other-panel'])};
    const globals={actor,body:actor.__playerStatBody,world:{},context:{},ready:true,
      appliedBody:actor.__playerStatBody,checkpoint:null,lastFailure:null,transition:null,
      batchDepth:0,flushing:false,revision:0,projectedRevision:0,requested:[0,0,0],completed:[0,0,0],
      _root:{服务器:{}},spawnFailedHook:undefined,growthReadReason:()=>state.readable?'':'gym_save_pending'};
    const adapter={
      canConsume:()=>state.readable,canProject:()=>true,isCurrent:()=>true,
      block() {if(!state.blocked) {state.claims.add('coordinator');state.acquired++;state.shootBefore=actor.enableShoot;}
        state.blocked=true;actor.enableShoot=false;},
      unblock() {if(!state.blocked)return;state.blocked=false;actor.enableShoot=state.shootBefore;
        state.claims.delete('coordinator');state.released++;if(state.onRelease)state.onRelease();},
      compute() {state.computes++;return {};},captureResources:()=>({}),commit(){},settleResources(){},derive(){},verify:()=>true
    };
    globals.adapter=adapter;
    const api=source.methods(file,['flushProjection','result','capture','dirtyMask','current','accept','fail'],globals);
    globals.PlayerStatRefreshCoordinator={};
    return {state,globals,api,actor};
}
function wait(f) {assert.equal(f.api.flushProjection('skill_snapshot').status,'pending');assert(f.state.blocked);}
function check(name,fn) {try{fn();results.push({name,passed:true});}catch(error){results.push({name,passed:false,error:error.message});}}
check('clean_success_releases_only_own_claim_without_resource_writes',()=>{
  const f=fixture();wait(f);f.actor.hp=71;f.state.readable=true;
  assert.equal(f.api.flushProjection('gym_save_confirmed').status,'unchanged');
  assert.equal(f.state.blocked,false);assert.equal(f.actor.enableShoot,true);
  assert.deepEqual([...f.state.claims],['other-panel']);assert.equal(f.state.released,1);
  assert.equal(f.state.computes,0);assert.deepEqual([f.actor.hp,f.actor.mp],[71,0]);
});
check('release_callback_reentry_is_guarded_and_new_dirty_is_projected',()=>{
  const f=fixture();wait(f);f.state.readable=true;
  f.state.onRelease=()=>{assert.equal(f.api.flushProjection('release_subscriber').reason,'reentrant');f.globals.requested[0]++;f.globals.revision++;};
  assert.equal(f.api.flushProjection('save_confirmed').status,'applied');
  assert.equal(f.state.computes,1);assert.equal(f.api.dirtyMask(),0);
});
check('authority_reclosed_during_release_reacquires_own_claim',()=>{
  const f=fixture();wait(f);f.state.readable=true;f.state.onRelease=()=>{f.state.readable=false;};
  assert.equal(f.api.flushProjection('save_confirmed').status,'pending');
  assert.equal(f.state.blocked,true);assert.equal(f.actor.enableShoot,false);
  assert.equal(f.state.acquired,2);assert.equal(f.state.released,1);
});
check('old_clean_callback_cannot_block_new_context',()=>{
  const f=fixture();wait(f);f.state.readable=true;
  f.state.onRelease=()=>{f.globals.context={};f.state.claims.add('new-context');};
  assert.equal(f.api.flushProjection('save_confirmed').reason,'stale_context');
  assert.equal(f.state.blocked,false);assert(f.state.claims.has('new-context'));
});
check('preexisting_disabled_shooting_is_not_enabled',()=>{
  const f=fixture();f.actor.enableShoot=false;wait(f);f.state.readable=true;
  assert.equal(f.api.flushProjection('save_confirmed').status,'unchanged');
  assert.equal(f.actor.enableShoot,false);assert.equal(f.state.blocked,false);
});
check('release_exception_does_not_grant_a_clean_receipt',()=>{
  const f=fixture();wait(f);f.state.readable=true;f.state.onRelease=()=>{throw new Error('release_failure');};
  assert.equal(f.api.flushProjection('save_confirmed').status,'failed');
  assert.equal(f.state.blocked,true);
});
const report={evidenceTier:'node-source-extraction',passed:results.filter(x=>x.passed).length,
  failed:results.filter(x=>!x.passed).length,results,sourceEvidence:source.evidence};
if(process.argv[3])fs.writeFileSync(process.argv[3],JSON.stringify(report,null,2));
console.log(JSON.stringify({evidenceTier:report.evidenceTier,passed:report.passed,failed:report.failed}));
if(report.failed)process.exitCode=1;
