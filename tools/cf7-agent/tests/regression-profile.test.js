"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {parseUnattendedArguments} = require("../unattended");
const Profile = require("../regression-profile");
const candidateId = "c-0123456789ab-0123456789-i152";

test("regression qualification is closed and supports verified formal or candidate at every entry", () => {
  const root = path.resolve(__dirname, "../../..");
  const ps = fs.readFileSync(path.join(root, "automation/start.ps1"), "utf8");
  const cs = fs.readFileSync(path.join(root, "launcher/src/AgentRuntime/TrustedRunner/TrustedRegressionSlots.cs"), "utf8");
  for (const slot of Profile.SLOTS) {
    assert(ps.includes("'" + slot + "'"));
    assert(cs.includes('"' + slot + '"'));
    assert.equal(parseUnattendedArguments(["--adapter", "jsonl", "--slot", slot, "--candidate-id", candidateId]).slot, slot);
    assert.equal(parseUnattendedArguments(["--adapter", "jsonl", "--slot", slot]).candidateId, undefined);
    for (const candidate of ["a5", "c-near", "../runtime", "A5"])
      assert.throws(() => parseUnattendedArguments(["--adapter", "jsonl", "--slot", slot, "--candidate-id", candidate]));
    assert.deepEqual(Profile.resolve({schema:Profile.SCHEMA,resourcesRoot:root,candidateId,slots:{targetSlot:slot}}), {slot,candidateId});
    assert.deepEqual(Profile.resolve({schema:Profile.SCHEMA,resourcesRoot:root,slots:{targetSlot:slot}}), {slot,candidateId:undefined});
  }
  for (const slot of ["crazyflasher7_saves", "cf7_agent_152_a28_near", "CF7_AGENT_152_A28", "cf7_agent_other"])
    assert.throws(() => Profile.resolve({schema:Profile.SCHEMA,resourcesRoot:root,candidateId,slots:{targetSlot:slot}}));
  assert.equal(Profile.resolve({schema:"legacy"}), null);
});

test("regression audit omits pixel content recursively without losing receipt metadata", () => {
  const {withoutPixels} = require("../regression-session");
  const response = {result:{contentBase64:"secret-pixels", metadata:{contentHash:"hash", totalLength:4}},
    frames:[{pixels:Buffer.from([1,2,3,4]), frameId:"frame"}]};
  assert.deepEqual(withoutPixels(response), {result:{metadata:{contentHash:"hash",totalLength:4}},
    frames:[{frameId:"frame"}]});
  assert.equal(response.result.contentBase64, "secret-pixels");
});

test("ephemeral PNG conversion preserves premultiplied BGRA colors and bounds", () => {
  const {captureToPng} = require("../regression-session");
  const zlib = require("node:zlib");
  const capture = {width:1,height:1,frame:{pixelFormat:"bgra8_premultiplied"},pixels:Buffer.from([0,32,64,128])};
  const png = captureToPng(capture);
  let offset=8, rgba;
  while(offset<png.length) {
    const length=png.readUInt32BE(offset), name=png.toString("ascii",offset+4,offset+8);
    if(name==="IDAT") rgba=zlib.inflateSync(png.subarray(offset+8,offset+8+length));
    offset+=length+12;
  }
  assert.deepEqual([...rgba], [0,128,64,0,128]);
  assert.throws(() => captureToPng({...capture, pixels:Buffer.alloc(3)}));
  assert.throws(() => captureToPng({...capture, width:4194305}));
});

test("only regression initialization includes candidate verification in its startup budget", async () => {
  const Controller = require("../../workbench-live-e2e/material-shop/trusted-runtime-controller");
  for (const regression of [false,true]) {
    let timeout;
    const preparation={resourcesRoot:path.resolve(__dirname,"../../.."),
      slots:{targetSlot:regression?Profile.SLOTS[0]:Controller.EXACT_SLOT},
      ...(regression?{schema:Profile.SCHEMA,candidateId}:{})};
    const runner={call:async(method,params,options)=>{
      assert.equal(method,"session.status"); timeout=options.timeoutMs;
      return {projectRunning:true,qualificationState:"verified",lifecycleRef:"lifecycle".padEnd(22,"x")};
    }};
    await new Controller.TrustedRuntimeController(preparation,runner).initialize();
    assert.equal(timeout,regression?180000:90000);
  }
});

test("regression work deadline blocks new input while preserving reads and supported shutdown", async () => {
  const {bindWorkBudget}=require("../regression-session");
  let tick=100, writes=0, finishes=0;
  const session={click:()=>++writes,pressKey:()=>++writes,typeText:()=>++writes,openPanel:()=>++writes,
    capture:()=>"fresh-read",finish:()=>++finishes};
  bindWorkBudget(session,()=>tick);
  assert.equal(session.click({}),1);
  tick+=8*60*1000;
  for(const name of ["click","pressKey","typeText","openPanel"])
    assert.throws(()=>session[name]({}),e=>e.code==="regression_checkpoint_due");
  assert.equal(writes,1);
  assert.equal(session.capture(),"fresh-read");
  assert.equal(session.finish(),1);
  assert.equal(finishes,1);
});

test("timed Launcher movement is regression-only and leaves legacy key arguments unchanged", async () => {
  const {TrustedRuntimeController}=require("../../workbench-live-e2e/material-shop/trusted-runtime-controller");
  const root=path.resolve(__dirname,"../../..");
  const prep={schema:Profile.SCHEMA,resourcesRoot:root,candidateId,slots:{targetSlot:Profile.SLOTS[0]}};
  const controller=new TrustedRuntimeController(prep,{});
  let sent;
  controller._withFreshActionCapture=async(kind,action)=> { assert.equal(kind,"launcher"); return action({}); };
  controller._perform=async(method,capture,lease,args)=> { sent=args; return {}; };
  await controller.pressKey({targetKind:"launcher",key:"s",durationMs:500});
  assert.deepEqual(sent,{key:"s",modifiers:[],repeat:1,durationMs:500});
  const artifact=JSON.parse(fs.readFileSync(path.join(root,"launcher/contracts/agent-runtime/v1/parameter-contracts.v1.json"),"utf8"));
  assert.deepEqual(artifact.actionArguments["input.press_key"].optional,["durationMs"]);
  const {validateRequest}=require("../lib/contract");
  const opaque=name=>name.padEnd(22,"x");
  const wire={jsonrpc:"2.0",id:"timed-direction-test",method:"input.press_key",params:{
    actionId:opaque("action"),idempotencyKey:opaque("key"),deadlineMs:5000,sessionId:opaque("session"),
    observationGrantId:opaque("grant"),leaseId:opaque("lease"),observationId:opaque("observation"),
    expectedLifecycleGeneration:1,targetId:opaque("target"),expectedSurfaceEpoch:1,
    expectedCoordinateSpaceVersion:1,expectedFocusEpoch:1,expectedModalEpoch:1,
    operation:"input.press_key",reason:"Timed movement contract",arguments:sent}};
  assert.doesNotThrow(()=>validateRequest(wire));
  for(const patch of [{durationMs:2001},{durationMs:0},{key:"f4"},{repeat:2},{modifiers:["ctrl"]}])
    assert.throws(()=>validateRequest({...wire,params:{...wire.params,arguments:{...sent,...patch}}}));
  for(const options of [{key:"f4",durationMs:50},{key:"s",durationMs:2001},{key:"s",durationMs:50,modifiers:["ctrl"]},{key:"s"}])
    await assert.rejects(controller.pressKey({targetKind:"launcher",...options}),e=>e.code==="trusted_runtime_key_invalid");
  const legacy=new TrustedRuntimeController({schema:"legacy"},{});
  await assert.rejects(legacy.pressKey({targetKind:"launcher",key:"s",durationMs:50}),e=>e.code==="trusted_runtime_input_kind_invalid");
});


test("Meridian structured opener is closed to non-regression clients and forwards only its panel name", async () => {
  const {TrustedRuntimeController}=require("../../workbench-live-e2e/material-shop/trusted-runtime-controller");
  const root=path.resolve(__dirname,"../../..");
  const prep={schema:Profile.SCHEMA,resourcesRoot:root,candidateId,slots:{targetSlot:Profile.SLOTS[0]}};
  const controller=new TrustedRuntimeController(prep,{});
  let sent, captured=0;
  controller._withFreshActionCapture=async(kind,action)=>{assert.equal(kind,"launcher");captured++;return action({});};
  controller._perform=async(method,capture,lease,args)=>{assert.equal(method,"panel.open");assert.equal(lease,"structured_action");sent=args;return {};};
  await controller.openPanel("meridians","Open current test role's production Meridian panel");
  assert.deepEqual(sent,{panel:"meridians"});
  assert.equal(captured,1);
  const ordinary=new TrustedRuntimeController({resourcesRoot:root,slots:{targetSlot:"cf7_agent_a5_material_shop_run"}},{});
  ordinary._withFreshActionCapture=async()=>{throw new Error("must reject before observation or dispatch");};
  await assert.rejects(ordinary.openPanel("meridians"),e=>e.code==="trusted_runtime_panel_invalid");
  for(const near of ["Meridians","meridians?debug=true","meridian","../meridians"])
    await assert.rejects(controller.openPanel(near),e=>e.code==="trusted_runtime_panel_invalid");
  const foreign=new TrustedRuntimeController({...prep,slots:{targetSlot:"crazyflasher7_saves"}},{});
  await assert.rejects(foreign.openPanel("meridians"),/closed test cohort/);
});
