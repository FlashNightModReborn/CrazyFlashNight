'use strict';
const assert=require('assert/strict'),path=require('path');
const {verifyPilotSaveUniverse,verifyRuntimeSlot}=require('./run-candidate');
const {canonicalJson,sha256Text}=require('../workbench-live-e2e/kshop/common');
const slot='bookrun_0123456789abcdef01234567';
const entry=(name,sha='a')=>({kind:'json',locator:'root:saves/'+name+'.json',sha256:sha.repeat(64),bytes:10,regularFile:true,exactRealPath:true});
function universe(artifacts){
    const payload={schema:'workbench-live-e2e.kshop.save-universe.v1',root:path.resolve(__dirname,'../..'),appDataRoot:path.resolve(__dirname),excludedTargetSlot:'cf7_agent_intro_prologue_1107',artifacts:artifacts.slice().sort((a,b)=>a.locator.localeCompare(b.locator))};
    return {...payload,capturedAt:new Date().toISOString(),setSha256:sha256Text(canonicalJson(payload))};
}
const before=universe([entry('real')]);
assert.equal(verifyPilotSaveUniverse(before,universe([entry('real'),entry(slot)]),slot).artifactCount,1);
assert.throws(()=>verifyPilotSaveUniverse(before,universe([entry('real','b'),entry(slot)]),slot),/non-target/);
assert.throws(()=>verifyPilotSaveUniverse(before,universe([entry('real'),entry(slot),entry('foreign')]),slot),/non-target/);
assert.throws(()=>verifyPilotSaveUniverse(universe([entry('real'),entry(slot)]),universe([entry('real'),entry(slot)]),slot),/existed before/);
const corrupted=universe([entry('real'),entry(slot)]);corrupted.artifacts[0].bytes++;
assert.throws(()=>verifyPilotSaveUniverse(before,corrupted,slot),/digest changed/);
console.log('Pilot save protection: exact new affiliated slot allowed; existing slot, collateral writes/additions and tampered evidence rejected. No save files written.');
// A closed stdin previously left the candidate alive with an abandoned clone
// lease. Reject it before a run directory or clone can be created.
const fs=require('fs'),cp=require('child_process'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..'),runs=path.join(root,'tmp/workbench-live-e2e/stage-intro');
const beforeRuns=fs.existsSync(runs)?fs.readdirSync(runs).sort():[];
const loaderHash=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'scripts/asLoader.swf'))).digest('hex');
const child=cp.spawnSync(process.execPath,[path.join(__dirname,'run-candidate.js'),'--execute-isolated-candidate','--allow-clone-book-writes',
    '--candidate-root',root,'--expected-asloader-sha256',loaderHash,'--seed-slot','cf7_agent_fixture'],{stdio:['ignore','pipe','pipe'],encoding:'utf8'});
assert.equal(child.status,1);assert.match(child.stderr,/interactive console is required/);
assert.deepEqual(fs.existsSync(runs)?fs.readdirSync(runs).sort():[],beforeRuns);
console.log('Noninteractive startup rejected before run-directory or clone mutation.');
assert.equal(verifyRuntimeSlot({saveRuntime:{loaded:true,savePath:'cf7_agent_fixture'}},'cf7_agent_fixture',slot),'cf7_agent_fixture');
assert.equal(verifyRuntimeSlot({saveRuntime:{loaded:true,savePath:slot}},'cf7_agent_fixture',slot),slot);
assert.throws(()=>verifyRuntimeSlot({saveRuntime:{loaded:true,savePath:'crazyflasher7_saves0'}},'cf7_agent_fixture',slot),/outside the owned/);
assert.throws(()=>verifyRuntimeSlot({saveRuntime:{loaded:false,savePath:'cf7_agent_fixture'}},'cf7_agent_fixture',slot),/outside the owned/);
console.log('Runtime observation/shutdown refuses a foreign or unloaded save slot.');
const second='bookrun_abcdef0123456789abcdef01';
const twoSlots=[slot,second];
assert.equal(verifyPilotSaveUniverse(before,universe([entry('real'),entry(slot),entry(second)]),twoSlots).artifactCount,1);
assert.throws(()=>verifyPilotSaveUniverse(before,universe([entry('real'),entry(slot)]),[slot,slot]),/Malformed/);
assert.throws(()=>verifyPilotSaveUniverse(before,universe([entry('real'),entry(slot)]),[slot,'real']),/Malformed/);
assert.throws(()=>verifyPilotSaveUniverse(universe([entry('real'),entry(second)]),universe([entry('real'),entry(slot),entry(second)]),twoSlots),/existed before/);
assert.equal(verifyRuntimeSlot({saveRuntime:{loaded:true,savePath:second}},'cf7_agent_fixture',twoSlots),second);
assert.throws(()=>verifyRuntimeSlot({saveRuntime:{loaded:true,savePath:'bookrun_111111111111111111111111'}},'cf7_agent_fixture',twoSlots),/outside/);
const parse=require('./run-candidate').parse;
const baseArgs=['--execute-isolated-candidate','--allow-clone-book-writes','--candidate-root',root,'--expected-asloader-sha256',loaderHash,'--seed-slot','cf7_agent_fixture'];
assert.equal(parse([...baseArgs,'--book-target','cf6-sting.type61']).routeId,'type61');
assert.throws(()=>parse([...baseArgs,'--book-target','__proto__']),/reviewed/);
console.log('Bounded reentry inventory rejects duplicate, existing and foreign slots; route selection remains closed.');
