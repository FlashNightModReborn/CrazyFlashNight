"use strict";

// Replays the UI route already observed on this candidate. All inputs continue
// through the trusted controller's fresh WGC binding, lease and guarded input.
// This module owns neither credentials nor shutdown. A failed checkpoint throws
// without replaying inputs, resetting saves, or hiding a pending business result.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const Profile = require("../cf7-agent/regression-profile");
const CHECKPOINTS = Object.freeze({
  d69ArchiveList: "786831B7F8A3C11F034276188406523E5FA0ACA3E21C754A771E0BECCF1F95F0",
  c68ArchiveDetail: "DA01CA6C820A98A7FF2D6E27E984DA16748A8E8D8C2E328FB900B7725E7FD6C7",
  c68Arrived: "A62391DCBC2455427F7AF132131C75A310E7C2CE4EBAE54A3424B270589A08CD"
});
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

async function requireFrame(session, expected) {
  let capture;
  for (let attempt = 0; attempt < 8; attempt++) {
    capture = await session.capture("web_overlay");
    if (capture.width === 1600 && capture.height === 900 && capture.frame.contentHash === expected)
      return capture;
    await wait(500);
  }
  const error = new Error("Observed UI checkpoint changed; inspect the current frame before continuing");
  error.code = "observed_checkpoint_changed";
  error.capture = capture; // ephemeral pixels for caller inspection; never persisted here
  throw error;
}

async function run(session) {
  const profile = Profile.resolve(session.preparation);
  assert.equal(profile?.slot, "cf7_agent_152_d69", "Segment starts from the qualified D69 test role");
  await session.openPanel("bookshelf", "Issue152: same-process D69 to C68 isolation");
  await session.click({ x:637, y:138, reason:"Open the observed isolated archive list" });
  await requireFrame(session, CHECKPOINTS.d69ArchiveList);
  await session.click({ x:1323, y:678, reason:"Select C68 from the exact matched D69 role list" });
  await requireFrame(session, CHECKPOINTS.c68ArchiveDetail);
  await session.click({ x:493, y:358, reason:"Perform the exact matched D69-to-C68 role switch once" });
  await requireFrame(session, CHECKPOINTS.c68Arrived);
  await session.click({ x:1537, y:47, reason:"Close the verified C68 rebound bookshelf" });
  await session.openPanel("materials", "Read C68 source qualification after D69");
  await wait(2000);
  await session.click({ x:940, y:155, reason:"Open the observed military-cloth uses section" });
  for (const y of [811,811,811,847])
    await session.click({ x:1578, y, reason:"Page the observed frozen cloth-use list" });
  await session.click({ x:1480, y:356, reason:"Open the same goggle-scarf recipe in C68" });
  const log = path.join(session.preparation.resourcesRoot, "logs/launcher.log");
  const offset = fs.statSync(log).size;
  await session.click({ x:1521, y:383, reason:"Recheck the diplomat source after D69 eligibility" });
  const capture = await session.capture("web_overlay");
  const newLog = fs.readFileSync(log).subarray(offset).toString("utf8");
  const denial = requireProductionDenial(newLog);
  return { capture, qualificationDenied:true, flashCallId:denial.flashCallId,
    evidence:denial.response, checkpoints:CHECKPOINTS };
}

function requireProductionDenial(newLog) {
  const binding = [...newLog.matchAll(/event=authority_flash_call_bound domain=material_shop_access .*?flashCallId=(\d+) .*?cmd=open_procurement_shop/g)];
  assert.equal(binding.length, 1, "Requires one fresh production authorization binding");
  const responses = newLog.split(/\r?\n/).filter(line => new RegExp(
    "\\[XmlSocket:JSON\\] task=material_shop_access_response cmd=other callId=" + binding[0][1]
      + " success=(true|false) payload=redacted len=[0-9]+$").test(line));
  assert.equal(responses.length, 1, "Requires one response for the exact bound Flash call");
  assert(responses[0].includes("success=false "), "C68 must receive an explicit production denial");
  return {flashCallId:binding[0][1],response:responses[0]};
}

module.exports = { run, requireFrame, requireProductionDenial, CHECKPOINTS };
