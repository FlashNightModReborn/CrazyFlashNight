"use strict";

const fs = require("fs");
const path = require("path");
const { connectExactTarget, evaluateByValue } = require("../kshop/cdp-client");
const { fail, sha256Bytes, sleep } = require("../kshop/common");

const OVERLAY_URL = "https://overlay.local/overlay.html";
const TARGETS = Object.freeze({
  firstCard: ".arena-card[data-index=\"0\"]",
  confirm: ".arena-detail-confirm",
  close: ".arena-panel .workbench-close-btn",
});

function strictToken(value, pattern, label) {
  value = String(value || "");
  if (!pattern.test(value)) fail("arena_input_token_invalid", "arena_input", label + " is invalid");
  return value;
}

async function openArenaInputChannel(options) {
  const binding = options.cdpBinding;
  const identity = options.runtimeIdentity;
  const writer = options.writer;
  if (!binding || !identity || binding.runtimePid !== identity.pid
      || !Number.isInteger(binding.port) || binding.exclusiveBeforeLaunch !== true) {
    fail("arena_input_binding_invalid", "arena_input",
      "arena candidate-page input is not bound to the authenticated candidate PID");
  }
  const connected = await connectExactTarget(binding.port, OVERLAY_URL,
    options.timeoutMs || 30000, options.pollMs || 250);
  const client = connected.client;
  await client.call("Runtime.enable", {}, 10000);
  await client.call("Page.enable", {}, 10000);
  const identityState = await evaluateByValue(client,
    "({url:String(location.href),origin:String(location.origin),readyState:String(document.readyState)})",
    "Arena input page identity");
  if (identityState.url !== OVERLAY_URL || identityState.origin !== new URL(OVERLAY_URL).origin) {
    client.close();
    fail("arena_input_page_invalid", "arena_input", "arena input attached to the wrong page");
  }
  writer.append({ kind: "arena_input_channel_bound", pageUrl: OVERLAY_URL,
    runtimePid: identity.pid, cdpPort: binding.port, candidatePageInput: true,
    physicalInputAttestation: false, pageIdentity: identityState });

  async function readState() {
    return evaluateByValue(client, `(function(){
      var container=document.getElementById('panel-container');
      var state=window.ArenaCore&&window.ArenaCore.state;
      var authority=state&&state._snapshot&&state._snapshot.arenaAuthority;
      var cards=state&&Array.isArray(state._activeCards)?state._activeCards.map(function(card){
        return {id:String(card&&card.id||''),index:Number(card&&card.index||0),
          previewIndex:Number(card&&card.previewIndex),mode:String(card&&card.mode||''),
          deposit:Number(card&&card.deposit),reward:Number(card&&card.reward),
          expr:String(card&&card.expr||''),opponentCount:Number(card&&card.opponentCount)};
      }):[];
      var preview=[];
      if(state&&state._previewCache){Object.keys(state._previewCache).forEach(function(key){
        var value=state._previewCache[key];if(Array.isArray(value)&&value.length)preview.push(Number(key));
      });}
      var button=document.querySelector('.arena-detail-confirm');
      return {url:String(location.href),panel:container?String(container.getAttribute('data-panel')||''):'',
        hidden:container?!!container.hidden||container.style.display==='none':true,
        session:Number(state&&state._session||0),selectedCardIdx:Number(state&&state._selectedCardIdx),
        cards:cards,previewReady:preview,
        previewPendingCount:state&&state._previewPending?Object.keys(state._previewPending).length:0,
        previewErrorCount:state&&state._previewError?Object.keys(state._previewError).length:0,
        snapshot:state&&state._snapshot?{money:Number(state._snapshot.money),
          playerLevel:Number(state._snapshot.playerLevel),sourceDigest:String(authority&&authority.sourceDigest||''),
          authorityCardCount:authority&&Array.isArray(authority.cards)?authority.cards.length:0}:null,
        confirm:{present:!!button,disabled:button?!!button.disabled:true,
          text:button?String(button.textContent||'').trim():''}};
    })()`, "Arena visible state");
  }

  async function click(targetName) {
    const selector = TARGETS[targetName];
    if (!selector) fail("arena_input_target_forbidden", "arena_input",
      "arena input target is outside the fixed allowlist", { targetName });
    const geometry = await evaluateByValue(client, `(function(selector){
      var container=document.getElementById('panel-container');
      var element=document.querySelector(selector);if(!element)return {ok:false,reason:'missing'};
      var rect=element.getBoundingClientRect();var x=rect.left+rect.width/2;var y=rect.top+rect.height/2;
      var hit=document.elementFromPoint(x,y);return {ok:!!(rect.width>0&&rect.height>0&&hit&&(hit===element||element.contains(hit))),
        panel:container?String(container.getAttribute('data-panel')||''):'',hidden:container?!!container.hidden:true,
        selector:selector,x:x,y:y,rect:{left:rect.left,top:rect.top,width:rect.width,height:rect.height},
        visible:!!(rect.width>0&&rect.height>0),enabled:!element.disabled,
        hitTargetMatches:!!(hit&&(hit===element||element.contains(hit)))};
    })(${JSON.stringify(selector)})`, "Arena " + targetName + " geometry");
    if (!geometry || geometry.ok !== true || geometry.panel !== "arena"
        || geometry.hidden === true || geometry.enabled !== true) {
      fail("arena_input_target_unavailable", "arena_input",
        "fixed arena input target is not visibly actionable", { targetName, geometry });
    }
    await client.call("Input.dispatchMouseEvent", {
      type: "mouseMoved", x: geometry.x, y: geometry.y, button: "none",
    }, 10000);
    await client.call("Input.dispatchMouseEvent", {
      type: "mousePressed", x: geometry.x, y: geometry.y, button: "left",
      buttons: 1, clickCount: 1,
    }, 10000);
    await client.call("Input.dispatchMouseEvent", {
      type: "mouseReleased", x: geometry.x, y: geometry.y, button: "left",
      buttons: 0, clickCount: 1,
    }, 10000);
    await sleep(100);
    writer.append({ kind: "arena_candidate_page_input", inputType: "trusted_click",
      targetName, selector, geometry, browserTrustedExpected: true,
      candidatePageInput: true, physicalInputAttestation: false });
    return geometry;
  }

  async function sendRetiredCardProbe(details) {
    const panelInstanceId = strictToken(details.panelInstanceId,
      /^panel_[A-Za-z0-9_-]{8,160}$/, "panelInstanceId");
    const retiredCardId = strictToken(details.retiredCardId,
      /^[a-f0-9]{32}:[^:\r\n]{1,128}$/, "retiredCardId");
    if (!Number.isInteger(details.cardIndex) || details.cardIndex < 0 || details.cardIndex > 1000) {
      fail("arena_input_card_index_invalid", "arena_input", "retired card index is invalid");
    }
    const callId = "arena_stale_probe_" + Date.now().toString(36);
    const payload = { type: "panel", panel: "arena", panelInstanceId,
      cmd: "preview", callId, cardId: retiredCardId, cardIndex: details.cardIndex };
    const result = await evaluateByValue(client, `(function(payload){
      var container=document.getElementById('panel-container');
      if(!container||container.hidden||String(container.getAttribute('data-panel')||'')!=='arena')
        return {sent:false,reason:'arena_not_visible'};
      if(typeof Bridge==='undefined'||!Bridge||typeof Bridge.send!=='function')
        return {sent:false,reason:'bridge_unavailable'};
      return {sent:Bridge.send(payload)===true,callId:String(payload.callId)};
    })(${JSON.stringify(payload)})`, "Arena retired card adversarial probe");
    if (!result || result.sent !== true || result.callId !== callId) {
      fail("arena_stale_probe_not_sent", "arena_stale_probe",
        "retired-card rejection probe did not enter the real WebView bridge", { result });
    }
    writer.append({ kind: "arena_retired_card_probe_issued", callId, panelInstanceId,
      retiredCardId, cardIndex: details.cardIndex, expectedError: "stale_authority",
      adversarialNonWritingProbe: true, directBusinessSuccessPath: false,
      candidatePageInput: false, physicalInputAttestation: false });
    return { callId, payload };
  }

  async function captureScreenshot(outputPath, label) {
    const exact = path.resolve(outputPath);
    const result = await client.call("Page.captureScreenshot", {
      format: "png", fromSurface: true, captureBeyondViewport: false,
    }, 30000);
    if (!result || typeof result.data !== "string") {
      fail("arena_screenshot_unavailable", "arena_visual", "CDP returned no PNG screenshot");
    }
    const bytes = Buffer.from(result.data, "base64");
    if (bytes.length < 1024 || bytes.length > 32 * 1024 * 1024
        || bytes[0] !== 0x89 || bytes[1] !== 0x50 || bytes[2] !== 0x4e || bytes[3] !== 0x47) {
      fail("arena_screenshot_invalid", "arena_visual", "CDP screenshot is not a bounded PNG");
    }
    fs.writeFileSync(exact, bytes, { flag: "wx" });
    const evidence = { kind: "arena_browser_screenshot", label: String(label || ""),
      path: exact, bytes: bytes.length, sha256: sha256Bytes(bytes),
      runtimePid: identity.pid, physicalInputAttestation: false };
    writer.append(evidence);
    return evidence;
  }

  let closed = false;
  return Object.freeze({
    readState,
    click,
    sendRetiredCardProbe,
    captureScreenshot,
    close() {
      if (closed) return;
      closed = true;
      client.close();
      writer.append({ kind: "arena_input_channel_detached", runtimePid: identity.pid });
    },
  });
}

module.exports = { OVERLAY_URL, TARGETS, openArenaInputChannel };
