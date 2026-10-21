"use strict";
const test=require("node:test"), assert=require("node:assert/strict");
const {run,requireProductionDenial}=require("./qualification-isolation-segment");
const binding="13:21:49.152 event=authority_flash_call_bound domain=material_shop_access webCallIdRef=sha256_a flashCallId=1 panel=crafting panelInstanceIdRef=sha256_b cmd=open_procurement_shop action=craftingProcurementShopAuthorize";
const denied="13:21:49.281 [XmlSocket:JSON] task=material_shop_access_response cmd=other callId=1 success=false payload=redacted len=115";
test("denial evidence requires one fresh exact-domain binding and one matching explicit denial",()=>{
  assert.equal(requireProductionDenial(binding+"\r\n"+denied).flashCallId,"1");
  for(const log of [denied,binding,binding+"\n"+denied.replace("callId=1","callId=2"),
    binding+"\n"+denied+"\n"+denied,binding+"\n"+denied.replace("success=false","success=true"),
    binding.replace("cmd=open_procurement_shop","cmd=snapshot")+"\n"+denied])
    assert.throws(()=>requireProductionDenial(log));
});
test("the replay refuses other regression roles before any UI input",async()=>{
  let writes=0;
  const session={preparation:{schema:"cf7.regression-runtime.v1",resourcesRoot:__dirname,
    candidateId:"c-0123456789ab-0123456789-i152",slots:{targetSlot:"cf7_agent_152_c68"}},
    openPanel:async()=>writes++};
  await assert.rejects(run(session));assert.equal(writes,0);
});
