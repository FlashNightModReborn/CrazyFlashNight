"use strict";
const assert=require("node:assert/strict"),test=require("node:test"),fs=require("node:fs"),path=require("node:path");
const Profile=require("../regression-profile"),Input=require("../qualification-input");
const {parseUnattendedArguments}=require("../unattended");
const {TrustedRuntimeController}=require("../../workbench-live-e2e/material-shop/trusted-runtime-controller");
const root=path.resolve(__dirname,"../../.."),candidateId="c-0123456789ab-0123456789-i205";
test("qualification is closed, candidate-only and has no formal fallback",()=>{
 for(const slot of Profile.QUALIFICATION_SLOTS){
  const prep={schema:Profile.SCHEMA,resourcesRoot:root,candidateId,slots:{targetSlot:slot}};
  assert.equal(Profile.resolve(prep).slot,slot); assert(Profile.isQualification(prep));
  assert.throws(()=>Profile.resolve({...prep,candidateId:undefined}));
  assert.throws(()=>parseUnattendedArguments(["--adapter","jsonl","--slot",slot]));
  assert.equal(parseUnattendedArguments(["--adapter","jsonl","--slot",slot,"--candidate-id",candidateId]).slot,slot);
 }
 for(const slot of ["cf7_agent_i2051110_near","CF7_AGENT_I2051110","crazyflasher7_saves"])
  assert.throws(()=>Profile.resolve({schema:Profile.SCHEMA,resourcesRoot:root,candidateId,slots:{targetSlot:slot}}));
});
test("qualification gestures agree across native and client and exclude system shortcuts",()=>{
 const source=fs.readFileSync(path.join(root,"launcher/src/AgentRuntime/Contracts/GameQualificationInput.cs"),"utf8");
 const body=source.split("new[] {")[1].split("}, StringComparer.Ordinal")[0];
 const native=[...body.matchAll(/"([^"]+)"/g)].map(m=>m[1]);
 assert.deepEqual(native,Input.GESTURES);
 for(const key of Input.GESTURES)assert(Input.isGesture("q205:"+key));
 for(const key of ["q205:alt+f4","q205:ctrl+a","q205:escape","q205:d+j+k","q205:j+d","j"])
  assert(!Input.isGesture(key));
});
test("controller admits gestures only on qualification Launcher and keeps the duration bound",async()=>{
 for(const qualified of [false,true]){
  const prep={schema:Profile.SCHEMA,resourcesRoot:root,candidateId,
    slots:{targetSlot:qualified?Profile.QUALIFICATION_SLOTS[0]:Profile.SLOTS[0]}};
  const controller=new TrustedRuntimeController(prep,{});
  let sent=0;
  controller._withFreshActionCapture=async(kind,fn)=>{assert.equal(kind,"launcher");return fn({});};
  controller._perform=async(method,capture,lease,args)=>{sent++;return args;};
  const options={targetKind:"launcher",key:"q205:shift+d+j",durationMs:500};
  if(qualified)assert.equal((await controller.pressKey(options)).key,options.key);
  else await assert.rejects(controller.pressKey(options),e=>e.code==="trusted_runtime_key_invalid");
  const before=sent;
  for(const patch of [{durationMs:2001},{modifiers:["ctrl"]},{repeat:2},{key:"q205:alt+f4"},{key:"j"}])
   await assert.rejects(controller.pressKey({...options,...patch}),e=>e.code==="trusted_runtime_key_invalid");
  assert.equal(sent,before);
 }
});
