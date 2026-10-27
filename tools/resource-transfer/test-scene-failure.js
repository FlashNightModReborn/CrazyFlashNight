'use strict';
// Production-source boundary probes. Real AVM1 and socket entry are separate evidence.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {createSource}=require('../player-stat-refresh/source');
const source=createSource(path.resolve(__dirname,'../..'));
const file='scripts/类定义/org/flashNight/arki/scene/PlayerSceneLifecycle.as';
const results=[];
function check(name,fn){try{fn();results.push({name,passed:true});}catch(e){results.push({name,passed:false,error:e.stack});}}
function fixture(){
 const context={},generation={},world={identity:{}},run={outcome:'active',life:'alive'};
 const state={queued:0,handoffs:0,host:0,failPage:0,depth:2,recovered:0,events:0,starts:0};
 const gate={generation,world:world.identity,context,run,stage:0,slot:'test',setup:true,publishScene:true};
 const actor={__playerStatBody:{},hp:80,mp:0};const spawn={gate,identity:{},hero:true,name:'hero',resourcesReady:true};
 actor.__playerSceneSpawn=spawn;actor.__playerSceneActorIdentity=spawn.identity;
 world.hero=actor;world.__playerSceneGate=gate;gate.hero=spawn;gate.actorReady=false;
 gate.manager={gameworld:world,currentStage:0,isActive:true,
   onPlayerReady(){state.starts++;},onPlayerInitializationFailed(){state.handoffs++;}};
 const root={gameworld:world,控制目标:'hero',savePath:'test',淡出动画:{gotoAndStop(){state.failPage++;}},getNextHighestDepth:()=>1,
   createEmptyMovieClip(){state.queued++;state.tick={removeMovieClip(){state.removed=true;}};return state.tick;}};
 const bus={createDispatchRecoveryToken(){const before=state.depth;return ()=>{state.depth=before;state.recovered++;};},
   publish(){state.events++;state.depth++;if(state.event)state.event();state.depth--;}};
 const globals={_root:root,generation,context:()=>context,trace(){},
   StageRunSession:{getRunAuthority:()=>run},StageReturnFlow:{worldIdentity:w=>w.identity},
   org:{flashNight:{arki:{camera:{HorizontalScroller:{onPlayerBound(){}}}},neur:{Event:{EventBus:{getInstance:()=>bus,instance:bus}},
   Server:{CharacterCreationService:{onSceneInitializationFailed(){state.host++;return state.hostAccepted===true;}}}}}}};
 const api=source.methods(file,['identityCurrent','liveRun','isCurrent','owns','isReady','actorFailed','acceptSceneResult','failInitialization','dispatchFailure','publishReady'],globals);
 globals.PlayerSceneLifecycle=api;
 return {api,state,gate,actor,spawn,world,root,globals,context};
}
check('sync_failed_result_schedules_one_terminal_handoff',()=>{
 const f=fixture();f.api.acceptSceneResult({context:f.context,world:f.world.identity},{status:'failed',reason:'numeric'});
 assert.equal(f.gate.failed,true);assert.equal(f.state.handoffs,0);assert.equal(f.state.queued,1);
 f.api.failInitialization(f.gate,'again');assert.equal(f.state.queued,1);
 f.state.tick.onEnterFrame();f.api.dispatchFailure(f.gate,null);
 assert.equal(f.state.handoffs,1);assert.equal(f.state.removed,true);
 assert.deepEqual([f.actor.hp,f.actor.mp],[80,0]);
});
check('late_actor_failure_reports_only_original_body',()=>{
 const f=fixture();f.api.actorFailed(f.actor,{},'stale');assert.equal(f.state.queued,0);
 f.api.actorFailed(f.actor,f.actor.__playerStatBody,'late-tail');assert.equal(f.state.queued,1);
});
check('post_birth_equipment_failure_keeps_its_transaction_owner',()=>{
 const f=fixture();f.gate.actorReady=true;f.api.actorFailed(f.actor,f.actor.__playerStatBody,'equipment');
 assert.equal(f.state.queued,0);
});
for(const changed of ['world','context','slot'])check('stale_'+changed+'_cannot_abort_new_scene',()=>{
 const f=fixture();f.api.failInitialization(f.gate,'old');
 if(changed==='world')f.world.identity={};if(changed==='context')f.globals.context=()=>({});if(changed==='slot')f.root.savePath='other';
 f.state.tick.onEnterFrame();assert.equal(f.state.handoffs,0);assert.equal(f.state.host,0);
});
check('listener_throw_restores_outer_dispatch_and_never_replays',()=>{
 const f=fixture();f.gate.actorReady=true;f.state.event=()=>{assert.equal(f.gate.published,true);throw new Error('listener');};
 f.api.publishReady(f.gate);assert.equal(f.state.depth,2);assert.equal(f.state.recovered,1);
 assert.equal(f.gate.failed,true);assert.equal(f.state.starts,0);assert.equal(f.gate.published,true);
 f.api.publishReady(f.gate);assert.equal(f.state.events,1);
});
check('callback_reentry_publishes_only_once',()=>{
 const f=fixture();f.gate.actorReady=true;f.state.event=()=>f.api.publishReady(f.gate);f.api.publishReady(f.gate);
 assert.equal(f.state.events,1);assert.equal(f.state.starts,1);assert.equal(f.state.recovered,0);
});
check('accepted_frontdoor_failure_does_not_start_ingame_return',()=>{
 const f=fixture();f.state.hostAccepted=true;f.api.failInitialization(f.gate,'bad');f.state.tick.onEnterFrame();
 assert.equal(f.state.host,1);assert.equal(f.state.handoffs,0);
});
check('base_failure_uses_existing_load_failure_page',()=>{
 const f=fixture();f.gate.manager=null;f.api.failInitialization(f.gate,'bad');f.state.tick.onEnterFrame();
 assert.equal(f.state.failPage,1);
});
const service='scripts/类定义/org/flashNight/neur/Server/CharacterCreationService.as';
function serviceFixture(){
 const state={messages:[],delivered:true};
 const globals={_phase:'transitioning',_sceneNotified:false,_attemptId:'a',_slotKey:'s',_root:{_bootstrapAttemptId:'a',savePath:'s'},
   sendResponse:m=>{state.messages.push(m);return state.delivered;}};
 const fn=source.fn(service,'function onSceneInitializationFailed(',globals);
 return {fn,globals,state};
}
check('frontdoor_failure_receipt_is_exact_and_once',()=>{
 const f=serviceFixture();assert.equal(f.fn('numeric'),true);assert.equal(f.fn('again'),false);
 assert.equal(f.globals._phase,'scene_failed');assert.equal(f.state.messages.length,1);
 assert.equal(f.state.messages[0].attemptId,'a');assert.equal(f.state.messages[0].slotKey,'s');
 assert.equal(f.state.messages[0].task,'scene_initialization_failed');
});
for(const key of ['savePath','_bootstrapAttemptId'])check('frontdoor_rejects_stale_'+key,()=>{
 const f=serviceFixture();f.globals._root[key]='other';assert.equal(f.fn('bad'),false);assert.equal(f.state.messages.length,0);
});
check('transport_rejection_is_not_success_or_write_retry',()=>{
 const f=serviceFixture();f.state.delivered=false;assert.equal(f.fn('bad'),false);assert.equal(f.globals._phase,'transitioning');
 assert.equal(f.state.messages.length,1);
});
const report={evidenceTier:'node-source-extraction',passed:results.filter(x=>x.passed).length,failed:results.filter(x=>!x.passed).length,results,sourceEvidence:source.evidence};
if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({passed:report.passed,failed:report.failed}));
for(const r of results)if(!r.passed)console.error(r.name,r.error);
if(report.failed)process.exitCode=1;
