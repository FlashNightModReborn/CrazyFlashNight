#!/usr/bin/env node
"use strict";

const assert = require("assert");
const { closeInputEvidence } = require("./kshop-legacy-readback");

let passed = 0;

function test(name, body) {
  body();
  passed += 1;
  console.log("ok " + passed + " - " + name);
}

function closeRequest(sequence) {
  return { kind: "bridge_send", sequence, eventHash: "request-" + sequence };
}

function closeClick(sequence, overrides) {
  return Object.assign({
    kind: "dom_input",
    eventType: "click",
    sequence,
    eventHash: "click-" + sequence,
    isTrusted: true,
    button: 0,
    panelState: { panel: "kshop", hidden: false },
    target: {
      selector: "[data-header-action=\"close\"]",
      visible: true,
      enabled: true,
      hitTargetMatches: true,
    },
  }, overrides || {});
}

function panelEsc(sequence, request) {
  return {
    kind: "webview_message",
    sequence,
    prevHash: request.eventHash,
    eventHash: "esc-" + sequence,
    panelState: { panel: "", hidden: true },
    message: { type: "panel_esc" },
  };
}

test("accepts an exact trusted visible close-button click", () => {
  const request = closeRequest(20);
  const result = closeInputEvidence([closeClick(19), request], request, 10);
  assert.strictEqual(result.inputRoute, "trusted_dom_close_click");
  assert.strictEqual(result.physicalInputAttestation, true);
});

test("rejects a trusted click on another control", () => {
  const request = closeRequest(20);
  const click = closeClick(19);
  click.target.selector = "#kshop-checkout";
  assert.strictEqual(closeInputEvidence([click, request], request, 10), null);
});

test("rejects synthetic or non-hit close-button clicks", () => {
  const request = closeRequest(20);
  assert.strictEqual(closeInputEvidence([
    closeClick(18, { isTrusted: false }),
    closeClick(19, { target: Object.assign({}, closeClick(19).target,
      { hitTargetMatches: false }) }),
    request,
  ], request, 10), null);
});

test("accepts only the adjacent hidden host panel_esc close route", () => {
  const request = closeRequest(20);
  const result = closeInputEvidence([request, panelEsc(21, request)], request, 10);
  assert.strictEqual(result.inputRoute, "host_panel_esc");
  assert.strictEqual(result.browserIsTrusted, false);
  assert.strictEqual(result.physicalInputAttestation, false);
});

test("rejects a non-adjacent or unchained panel_esc", () => {
  const request = closeRequest(20);
  const delayed = panelEsc(22, request);
  const unchained = panelEsc(21, request);
  unchained.prevHash = "other";
  assert.strictEqual(closeInputEvidence([request, delayed], request, 10), null);
  assert.strictEqual(closeInputEvidence([request, unchained], request, 10), null);
});

test("rejects panel_esc while KShop is still visible", () => {
  const request = closeRequest(20);
  const event = panelEsc(21, request);
  event.panelState = { panel: "kshop", hidden: false };
  assert.strictEqual(closeInputEvidence([request, event], request, 10), null);
});

test("rejects input outside the exact post-open sequence window", () => {
  const request = closeRequest(20);
  assert.strictEqual(closeInputEvidence([closeClick(10), request], request, 10), null);
});

console.log("KShop legacy close evidence self-test: " + passed + "/7 passed");
