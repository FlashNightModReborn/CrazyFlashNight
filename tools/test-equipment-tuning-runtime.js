#!/usr/bin/env node
'use strict';

const assert = require('assert');
const {RequestMux, isAmbiguous, safeToken} = require('../launcher/web/modules/equipment-tuning-runtime.js');

function source(lease) {
  return {sourceKind:'inventory',containerId:'背包',slot:1,expectedLease:lease||'lease.1'};
}
function equipment(level, mods, lastUpdate) {
  return {name:'测试手枪A',displayName:'测试手枪甲',icon:'测试手枪图标甲',type:'武器',use:'手枪',
    level:level||7,tier:'一阶',mods:mods||[],lastUpdate:lastUpdate==null?1000:lastUpdate,
    modSlotCapacity:3,maxLevel:13,hardMaxLevel:13};
}
function snapshot(lease, level, mods, lastUpdate) {
  const current=equipment(level,mods,lastUpdate),candidates=(mods||[]).map((name,index)=>({
    candidateKey:'mod.installed.'+index,itemName:name,displayName:'已安装配件 '+index,
    icon:'已安装配件图标 '+index,owned:0,installed:true,available:false,
    availabilityCode:-2,reason:'already_installed',replaceableFrom:[],grade:'common',scope:'firearm',role:'utility'
  }));
  return {gender:'男',source:source(lease),equipment:current,
    enhance:{currentLevel:current.level,maxLevel:13,availableMaxLevel:13,hardMaxLevel:13},
    tierCandidates:[],modCandidates:candidates,materials:[{
      itemName:'强化石',displayName:'高能强化晶体',icon:'强化晶体图标',count:100
    }],
    materialRevision:7,inventoryRevision:11};
}
function projection(lease, level, mods, lastUpdate) {
  return {source:{source:source(lease),equipment:equipment(level,mods,lastUpdate)}};
}
function modCandidate() {
  return {candidateKey:'mod.candidate.1',itemName:'测试插件A',displayName:'测试插件甲',icon:'测试插件图标甲',
    owned:5,installed:false,available:true,availabilityCode:1,reason:'',replaceableFrom:[],
    grade:'common',scope:'firearm',role:'utility'};
}
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function tuple(cmd, callId) {
  return {type:'panel_resp',domain:'equipment_tuning',cmd,callId,
    panelInstanceId:'panel.1',viewSessionId:'view.1',success:true};
}
function previewResponse(callId, token) {
  return Object.assign(tuple('preview',callId),{operation:'install_mod',tuningToken:token,
    before:projection('lease.1',7,[],1000),after:projection('lease.1',7,['测试插件A'],1000),
    materials:[{itemName:'测试插件A',displayName:'测试插件甲',icon:'测试插件图标甲',
      before:5,delta:-1,after:4}],removedMods:[],
    noOp:false,canCommit:true});
}
function tooltipResponse(callId, text, candidateKey) {
  return Object.assign(tuple('tooltip',callId),{candidateKey:candidateKey||'opaque.1',introHTML:'<b>候选</b>',
    descHTML:'候选说明',itemType:'收集品',itemUse:'材料',text:text||'候选显示名'});
}
function backpackSnapshot(lease, current) {
  return {slots:[{physicalSlot:1,occupied:true,slotLease:lease,item:{itemKind:'equipment',
    name:current.name,displayName:current.displayName,icon:current.icon},confirmProjection:{
    name:current.name,displayName:current.displayName}}]};
}
function commitResponse(callId) {
  const post=equipment(8,[],2000);
  const state=snapshot('lease.2',8,[],2000);state.materials[0].count=97;
  return Object.assign(tuple('commit',callId),{operation:'enhance',tuningToken:'token.commit',
    transactionId:'txn.1',before:projection('lease.1',7,[],1000),
    after:{source:{source:source('lease.2'),equipment:post}},
    materials:[{itemName:'强化石',displayName:'高能强化晶体',icon:'强化晶体图标',
      before:100,delta:-3,after:97}],removedMods:[],
    noOp:false,canCommit:false,snapshot:state,
    inventorySnapshots:[backpackSnapshot('lease.2',post)]});
}

const sent = [];
const timers = [];
const diagnostics = [];
const mux = new RequestMux({
  sessionNonce:'runtime-test', timeoutMs:100,
  diagnostic(event){ diagnostics.push(event); },
  send(message){ sent.push(message); return true; },
  setTimer(callback){ const timer={callback,cleared:false}; timers.push(timer); return timer; },
  clearTimer(timer){ timer.cleared=true; }
});

assert.strictEqual(mux.openSession('panel.1','view.1'),true);
let response = null;
const callId = mux.request('snapshot',{source:{containerId:'背包',slot:1,expectedLease:'lease.1'}},value=>{ response=value; });
assert.ok(/^tune\.runtime-test\.1\.1$/.test(callId));
assert.deepStrictEqual(Object.keys(sent[0]).sort(),['callId','cmd','domain','panel','panelInstanceId','payload','type'].sort());
assert.strictEqual(sent[0].payload.viewSessionId,'view.1');
assert.strictEqual(sent[0].payload.v,1);
assert.strictEqual(mux.handleResponse({type:'panel_resp',domain:'equipment_tuning',cmd:'snapshot',callId,
  panelInstanceId:'panel.old',viewSessionId:'view.1',success:true}),false);
assert.strictEqual(response,null);
assert.deepStrictEqual(diagnostics[0], {
  event:'response_tuple_mismatch', cmd:'snapshot', webCallId:callId,
  panelInstanceId:'panel.1', viewSessionId:'view.1',
  mismatchFields:['panelInstanceId']
});
assert.strictEqual(mux.debugState().pendingCount,1);
assert.deepStrictEqual(mux.debugState().pendingKinds,['snapshot']);
assert.strictEqual(mux.handleResponse({type:'panel_resp',domain:'equipment_tuning',cmd:'snapshot',callId,
  panelInstanceId:'panel.1',viewSessionId:'view.1',success:true,snapshot:{}}),false);
assert.strictEqual(response,null);
assert.deepStrictEqual(diagnostics[diagnostics.length-1].mismatchFields,['businessShape']);
assert.strictEqual(mux.debugState().pendingCount,1);
assert.strictEqual(mux.handleResponse(Object.assign(tuple('snapshot',callId),{
  snapshot:snapshot('lease.1',7,[],1000)})),true);
assert.strictEqual(response.success,true);
assert.strictEqual(mux.debugState().pendingCount,0);

let terminalError = null;
const terminalErrorCall = mux.request('preview',{operation:'install_mod'},value=>{ terminalError=value; });
assert.strictEqual(mux.handleResponse({type:'panel_resp',domain:'equipment_tuning',cmd:'preview',
  callId:terminalErrorCall,panelInstanceId:'panel.1',viewSessionId:'view.stale',
  success:false,error:'view_session_expired'}),false);
assert.strictEqual(terminalError,null);
assert.strictEqual(mux.debugState().pendingCount,1);
assert.deepStrictEqual(diagnostics[diagnostics.length-1].mismatchFields,['viewSessionId']);
assert.strictEqual(mux.handleResponse({type:'panel_resp',domain:'equipment_tuning',cmd:'preview',
  callId:terminalErrorCall,panelInstanceId:'panel.1',viewSessionId:'view.1',
  success:false,error:'view_session_expired'}),true);
assert.strictEqual(terminalError.error,'view_session_expired');
assert.strictEqual(mux.debugState().pendingCount,0);

[
  ['missing displayName', value=>{ delete value.snapshot.equipment.displayName; }],
  ['number displayName', value=>{ value.snapshot.equipment.displayName=73; }],
  ['wrong icon type', value=>{ value.snapshot.equipment.icon=7; }],
  ['object icon', value=>{ value.snapshot.equipment.icon={bad:true}; }],
  ['legacy display alias', value=>{ value.snapshot.equipment.displayname='legacy'; }],
  ['whitespace candidate display', value=>{ value.snapshot.modCandidates=[modCandidate()]; value.snapshot.modCandidates[0].displayName=' \t '; }],
  ['number candidate display', value=>{ value.snapshot.modCandidates=[modCandidate()]; value.snapshot.modCandidates[0].displayName=74; }],
  ['literal undefined candidate icon', value=>{ value.snapshot.modCandidates=[modCandidate()]; value.snapshot.modCandidates[0].icon=' UnDeFiNeD '; }],
  ['object candidate icon', value=>{ value.snapshot.modCandidates=[modCandidate()]; value.snapshot.modCandidates[0].icon={bad:true}; }],
  ['missing material displayName', value=>{ delete value.snapshot.materials[0].displayName; }],
  ['object material displayName', value=>{ value.snapshot.materials[0].displayName={bad:true}; }],
  ['wrong material icon type', value=>{ value.snapshot.materials[0].icon=7; }],
  ['object material icon', value=>{ value.snapshot.materials[0].icon={bad:true}; }],
  ['legacy material alias', value=>{ value.snapshot.materials[0].displayname='legacy'; }],
  ['whitespace material display', value=>{ value.snapshot.materials[0].displayName=' \t '; }],
  ['literal undefined material icon', value=>{ value.snapshot.materials[0].icon=' UnDeFiNeD '; }]
].forEach(([label,mutate],index)=>{
  let adopted=null;
  const malformedCall=mux.request('snapshot',{source:source('lease.1')},value=>{ adopted=value; });
  const malformed=Object.assign(tuple('snapshot',malformedCall),{snapshot:snapshot('lease.1',7,[],1000)});
  mutate(malformed);
  assert.strictEqual(mux.handleResponse(malformed),false,label);
  assert.strictEqual(adopted,null,label+' callback');
  assert.deepStrictEqual(diagnostics[diagnostics.length-1].mismatchFields,['businessShape']);
  assert.strictEqual(mux.handleResponse(Object.assign(tuple('snapshot',malformedCall),{
    snapshot:snapshot('lease.1',7,[],1000)})),true,label+' recovery');
  assert.strictEqual(adopted.success,true,label+' recovery callback');
});

let malformedPreviewAdopted=null;
const malformedPreviewCall=mux.request('preview',{operation:'install_mod'},value=>{ malformedPreviewAdopted=value; });
const malformedPreview=previewResponse(malformedPreviewCall,'token.malformed.preview');
delete malformedPreview.after.source.equipment.displayName;
malformedPreview.after.source.equipment.displayname='legacy';
assert.strictEqual(mux.handleResponse(malformedPreview),false);
assert.strictEqual(malformedPreviewAdopted,null);
assert.strictEqual(mux.handleResponse(previewResponse(
  malformedPreviewCall,'token.malformed.preview')),true);

let malformedMaterialPreviewAdopted=null;
const malformedMaterialPreviewCall=mux.request('preview',{operation:'install_mod'},
  value=>{ malformedMaterialPreviewAdopted=value; });
const malformedMaterialPreview=previewResponse(
  malformedMaterialPreviewCall,'token.malformed.material.preview');
malformedMaterialPreview.materials[0].icon=' UnDeFiNeD ';
assert.strictEqual(mux.handleResponse(malformedMaterialPreview),false);
assert.strictEqual(malformedMaterialPreviewAdopted,null);
assert.strictEqual(mux.handleResponse(previewResponse(
  malformedMaterialPreviewCall,'token.malformed.material.preview')),true);

let statsPreviewAdopted=null;
const statsPreviewCall=mux.request('preview',{operation:'install_mod'},value=>{ statsPreviewAdopted=value; });
const statsPreview=previewResponse(statsPreviewCall,'token.stats.preview');
const statsRows=[
  {key:'damage',label:'伤害加成',value:10},
  {key:'vampirism',label:'吸血',value:3}];
statsPreview.before.source.equipment.stats=statsRows.slice(0,1);
statsPreview.after.source.equipment.stats=statsRows;
assert.strictEqual(mux.handleResponse(statsPreview),true);
assert.deepStrictEqual(statsPreviewAdopted.after.source.equipment.stats,statsRows);

let malformedStatsPreviewAdopted=null;
const malformedStatsPreviewCall=mux.request('preview',{operation:'install_mod'},
  value=>{ malformedStatsPreviewAdopted=value; });
const malformedStatsPreview=previewResponse(
  malformedStatsPreviewCall,'token.malformed.stats.preview');
malformedStatsPreview.after.source.equipment.stats=[{key:'damage',label:'伤害加成',value:'10'}];
assert.strictEqual(mux.handleResponse(malformedStatsPreview),false);
assert.strictEqual(malformedStatsPreviewAdopted,null);
assert.strictEqual(mux.handleResponse(previewResponse(
  malformedStatsPreviewCall,'token.malformed.stats.preview')),true);

let statsTooltipAdopted=null;
const statsTooltipCall=mux.request('tooltip',{candidateKey:'opaque.stats'},value=>{ statsTooltipAdopted=value; });
const statsTooltip=tooltipResponse(statsTooltipCall,'带试算候选','opaque.stats');
statsTooltip.statsBefore=[{key:'damage',label:'伤害加成',value:10}];
statsTooltip.statsAfter=[{key:'damage',label:'伤害加成',value:12}];
assert.strictEqual(mux.handleResponse(statsTooltip),true);
assert.deepStrictEqual(statsTooltipAdopted.statsAfter,[{key:'damage',label:'伤害加成',value:12}]);

let unpairedTooltipAdopted=null;
const unpairedTooltipCall=mux.request('tooltip',{candidateKey:'opaque.unpaired'},value=>{ unpairedTooltipAdopted=value; });
const unpairedTooltip=tooltipResponse(unpairedTooltipCall,'单边试算','opaque.unpaired');
unpairedTooltip.statsBefore=[{key:'damage',label:'伤害加成',value:10}];
assert.strictEqual(mux.handleResponse(unpairedTooltip),false);
assert.strictEqual(unpairedTooltipAdopted,null);
assert.strictEqual(mux.handleResponse(tooltipResponse(
  unpairedTooltipCall,'无试算','opaque.unpaired')),true);

let malformedCommitAdopted=null;
const malformedCommitCall=mux.request('commit',{expectedTuningToken:'token.commit'},value=>{ malformedCommitAdopted=value; });
const malformedCommit=commitResponse(malformedCommitCall);
malformedCommit.snapshot.equipment.icon=' undefined ';
malformedCommit.inventorySnapshots[0].slots[0].item.icon=' undefined ';
assert.strictEqual(mux.handleResponse(malformedCommit),false);
assert.strictEqual(malformedCommitAdopted,null);
assert.strictEqual(mux.handleResponse(commitResponse(malformedCommitCall)),true);
assert.strictEqual(malformedCommitAdopted.success,true);

let forgedMaterialCommitAdopted=null;
const forgedMaterialCommitCall=mux.request('commit',{expectedTuningToken:'token.commit'},
  value=>{ forgedMaterialCommitAdopted=value; });
const forgedMaterialCommit=commitResponse(forgedMaterialCommitCall);
forgedMaterialCommit.materials[0].displayName='伪造材料展示名';
assert.strictEqual(mux.handleResponse(forgedMaterialCommit),false);
assert.strictEqual(forgedMaterialCommitAdopted,null);
assert.strictEqual(mux.handleResponse(commitResponse(forgedMaterialCommitCall)),true);

let malformedTooltipAdopted=null;
const malformedTooltipCall=mux.request('tooltip',{candidateKey:'opaque.sentinel'},value=>{ malformedTooltipAdopted=value; });
assert.strictEqual(mux.handleResponse(tooltipResponse(
  malformedTooltipCall,' undefined ','opaque.sentinel')),false);
assert.strictEqual(malformedTooltipAdopted,null);
assert.strictEqual(mux.handleResponse(tooltipResponse(
  malformedTooltipCall,'合法候选','opaque.sentinel')),true);

let tooltipResult = null;
let previewResult = null;
const tooltipCall = mux.request('tooltip',{candidateKey:'opaque.1'},value=>{ tooltipResult=value; });
const previewCall = mux.request('preview',{operation:'install_mod'},value=>{ previewResult=value; });
assert.deepStrictEqual(mux.debugState().pendingKinds,['tooltip','preview']);
assert.strictEqual(mux.handleResponse(tooltipResponse(tooltipCall,'rich','opaque.1')),true);
assert.strictEqual(previewResult,null);
assert.strictEqual(mux.handleResponse(previewResponse(previewCall,'token.normal')),true);
assert.strictEqual(previewResult.tuningToken,'token.normal');
assert.strictEqual(tooltipResult.text,'rich');
assert.strictEqual(mux.debugState().pendingCount,0);

tooltipResult = null;
previewResult = null;
const reverseTooltipCall = mux.request('tooltip',{candidateKey:'opaque.2'},value=>{ tooltipResult=value; });
const reversePreviewCall = mux.request('preview',{operation:'install_mod'},value=>{ previewResult=value; });
assert.strictEqual(mux.handleResponse(previewResponse(reversePreviewCall,'token.reverse')),true);
assert.strictEqual(previewResult.tuningToken,'token.reverse');
assert.strictEqual(tooltipResult,null);
assert.strictEqual(mux.handleResponse(tooltipResponse(reverseTooltipCall,'late-rich','opaque.2')),true);
assert.strictEqual(previewResult.tuningToken,'token.reverse');
assert.strictEqual(tooltipResult.text,'late-rich');
assert.strictEqual(mux.debugState().pendingCount,0);

let firstTooltip = null;
let secondTooltip = null;
const firstTooltipCall = mux.request('tooltip',{candidateKey:'opaque.3'},value=>{ firstTooltip=value; });
const secondTooltipCall = mux.request('tooltip',{candidateKey:'opaque.4'},value=>{ secondTooltip=value; });
assert.strictEqual(mux.handleResponse(tooltipResponse(secondTooltipCall,'second','opaque.4')),true);
assert.strictEqual(firstTooltip,null);
assert.strictEqual(secondTooltip.text,'second');
assert.strictEqual(mux.debugState().pendingCount,1);
assert.deepStrictEqual(mux.debugState().pendingKinds,['tooltip']);
assert.strictEqual(mux.handleResponse(tooltipResponse(firstTooltipCall,'first','opaque.3')),true);
assert.strictEqual(firstTooltip.text,'first');
assert.strictEqual(mux.debugState().pendingCount,0);

let late = false;
const oldCall = mux.request('preview',{operation:'enhance'},()=>{ late=true; });
assert.strictEqual(mux.openSession('panel.2','view.2'),true);
assert.strictEqual(mux.handleResponse({type:'panel_resp',domain:'equipment_tuning',cmd:'preview',callId:oldCall,
  panelInstanceId:'panel.1',viewSessionId:'view.1',success:true}),false);
assert.strictEqual(late,false);

let timeout = null;
const commit = mux.request('commit',{expectedTuningToken:'token.1'},value=>{ timeout=value; });
const timer = timers[timers.length-1];
timer.callback();
assert.strictEqual(timeout.callId,commit);
assert.strictEqual(timeout.requiresReconcile,true);
assert.strictEqual(isAmbiguous(timeout),true);
assert.strictEqual(isAmbiguous({success:false,error:'material_missing'}),false);
assert.strictEqual(isAmbiguous({success:false,error:'disconnected',requiresReconcile:false}),false);
assert.strictEqual(isAmbiguous({success:false,error:'disconnected',requiresReconcile:true}),true);
const reconcileRequired = {success:false,error:'reconcile_required',requiresReconcile:true,
  reconcileAfterCallId:'tune.host.previous.unknown.1'};
assert.strictEqual(isAmbiguous(reconcileRequired),true);
assert.strictEqual(safeToken(reconcileRequired.reconcileAfterCallId),'tune.host.previous.unknown.1');

let notSent = null;
const disconnectedMux = new RequestMux({sessionNonce:'not-sent',send(){ return false; }});
assert.strictEqual(disconnectedMux.openSession('panel.3','view.3'),true);
assert.ok(disconnectedMux.request('commit',{expectedTuningToken:'token.2'},value=>{ notSent=value; }));
assert.strictEqual(notSent.error,'not_sent');
assert.strictEqual(isAmbiguous(notSent),false);

let detached = null;
const detachCall = disconnectedMux.request('detach',{},value=>{ detached=value; });
assert.ok(detachCall);
assert.strictEqual(detached.cmd,'detach');
assert.strictEqual(detached.requiresReconcile,false);

assert.strictEqual(mux.request('unknown',{},()=>{}),null);
mux.closeSession();
assert.strictEqual(mux.debugState().pendingCount,0);
console.log('Equipment tuning runtime tests passed');
