const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

// Contract unit tests. Fake lifecycle objects below are NOT a real-page or C1 receipt.
const events = new Map(), handlers = new Map(), sent = [];
let phase = 'closed', closes = 0;
const context = vm.createContext({
  Bridge: {send:m => {sent.push(m);return true;}, on:(type,fn) => handlers.set(type,fn)},
  document: {body:{inert:true}, activeElement:{blur(){}}},
  Panels: {init(){}, open(){phase='editing';}, close(){phase='closed';closes++;}, isOpen(){return phase!=='closed';}},
  PlasticSurgeryPanel:{debugState:()=>({phase})},
  Promise, Number, Object, JSON,
});
context.window = context;
context.addEventListener = (type,fn) => events.set(type,fn);
for (const name of ['gate.js','scope.js']) vm.runInContext(fs.readFileSync(path.join(__dirname,name),'utf8'),context);
const gate = context.C1IslandGate, control = handlers.get('c1_control');
assert.equal(gate.sameRound({session:'s',coverage:'c',epoch:1,ticket:2,geometry:1},
  {geometry:1,ticket:2,epoch:1,coverage:'c',session:'s'}),true,'property order is not identity');
let blocked = 0;
events.get('click')({preventDefault(){blocked++;},stopImmediatePropagation(){blocked++;}});
assert.equal(blocked,2);
const round = {session:'s',coverage:'c',epoch:1,ticket:2,geometry:1};
control({op:'prepare',instance:'page.1',generation:1,round});
assert.equal(context.document.body.inert,true);
assert.equal(gate.granted,false);
assert.equal(context.Bridge.send({type:'panel',panel:'surgery',panelInstanceId:'page.old',cmd:'snapshot'}),false);
assert.equal(context.Bridge.send({type:'panel',panel:'other',panelInstanceId:'page.1',cmd:'snapshot'}),false);
assert.equal(context.Bridge.send({type:'panel',panel:'surgery',panelInstanceId:'page.1',cmd:'snapshot'}),true);
assert.equal(context.Bridge.send({type:'panel',panel:'surgery',panelInstanceId:'page.1',cmd:'close'}),false);
control({op:'grant',instance:'page.1',generation:1,round:{...round,ticket:1}});
assert.equal(gate.granted,false);
control({op:'grant',instance:'page.1',generation:1,round});
assert.equal(gate.granted,true);
assert.equal(context.Bridge.send({type:'panel',panel:'surgery',panelInstanceId:'page.1',cmd:'close'}),true);
assert.equal(sent.at(-1).inputGeneration,1);
assert.deepEqual(sent.at(-1).inputRound,round);
const before = closes;
control({op:'cancel',instance:'page.old',generation:1,round,retire:true});
assert.equal(closes,before);
control({op:'cancel',instance:'page.1',generation:1,round});
assert.equal(closes,before); assert.equal(phase,'editing'); assert.equal(gate.granted,false);
assert.equal(sent.at(-1).kind,'suspended');
control({op:'grant',instance:'page.1',generation:1,round});
assert.equal(gate.granted,false,'a cancelled prepared round cannot be granted again');
let lateCompositionBlocked=0;
events.get('compositionend')({preventDefault(){lateCompositionBlocked++;},stopImmediatePropagation(){lateCompositionBlocked++;}});
assert.equal(lateCompositionBlocked,2,'closed epoch rejects composition tail');
control({op:'cancel',instance:'page.1',generation:1,round,retire:true});
assert.equal(phase,'closed'); assert.equal(context.document.body.inert,true);
Promise.resolve().then(()=>{
  assert.equal(sent.at(-1).kind,'cancelled');
  assert.equal(sent.at(-1).gateClosed,true);
  const frames=[];
  context.setTimeout=()=>{throw new Error('Unexpected retry in ready editing page');};
  context.requestAnimationFrame=callback=>frames.push(callback);
  const nextRound={...round,epoch:2,ticket:3};
  control({op:'prepare',instance:'page.2',generation:2,round:nextRound});
  const readyBefore=sent.filter(m=>m.kind==='page_ready').length;
  frames.shift()();
  assert.equal(sent.filter(m=>m.kind==='page_ready').length,readyBefore,'DOM readiness alone cannot release the retained view');
  const beforeFreeze=sent.length;
  control({op:'freeze_view',instance:'page.2',generation:2,round:nextRound});
  assert.equal(phase,'editing','presentation hold must not close the panel before capture');
  assert.equal(gate.granted,false);
  assert.equal(sent.length,beforeFreeze,'a frozen image is not a cancellation ACK');
  frames.shift()();
  assert.equal(sent.filter(m=>m.kind==='page_ready').length,readyBefore,'late paint callback cannot reveal a revoked page');
  control({op:'cancel',instance:'page.2',generation:2,round:nextRound});
  frames.shift()();frames.shift()();
  assert.equal(sent.filter(m=>m.kind==='page_ready').length,readyBefore+1);
  assert.equal(gate.granted,false,'paint readiness is not input permission');
  console.log('C1 Web gate contract: closed input, exact instance/round, draft-preserving suspension and explicit retirement passed; unit layer only');
});
