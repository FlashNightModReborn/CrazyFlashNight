#!/usr/bin/env node
"use strict";

const assert = require("assert");
const {
  FORBIDDEN_WEB_AUTHORITY_FIELDS,
  arenaFlashCommands,
  closeRequestAfter,
  snapshotExchangeForOpen,
  trustedClickEvidence,
  validateAuthoritySnapshot,
  visibleStandardCards,
} = require("./arena-live-e2e");
const { TARGETS } = require("./arena/cdp-input-channel");
const { isSaveUniverseJsonName } = require("./kshop/generic-opener");

function authorityMessage(overrides) {
  const session = "0123456789abcdef0123456789abcdef";
  const cards = [];
  for (let index = 1; index <= 10; index += 1) {
    cards.push({
      id: session + ":arena-" + index,
      index,
      previewIndex: index - 1,
      mode: "standard",
      expr: "#0@10-12%3",
      deposit: index * 100,
      reward: index * 200,
      opponentCount: 3,
    });
  }
  cards.push({ id: session + ":arena-11", index: 11, previewIndex: 10,
    mode: "hidden", expr: "#0@20-24%4", deposit: 1100, reward: 2200 });
  cards.push({ id: session + ":arena-12", index: 12, previewIndex: 11,
    mode: "hidden", expr: "#0@24-28%4", deposit: 1200, reward: 2400 });
  const message = {
    success: true,
    snapshot: {
      money: 50000,
      playerLevel: 30,
      arenaAuthority: {
        schemaVersion: 1,
        source: "data/arena/arena_config.xml+meta_teams.json+arena_factions.json+arena_calibrated_rosters.json+data/units/units.json",
        sourceDigest: "A".repeat(64),
        cards,
      },
    },
  };
  return Object.assign(message, overrides || {});
}

function expectFailure(action, code) {
  assert.throws(action, (error) => error && error.code === code);
}

function run() {
  const authority = validateAuthoritySnapshot(authorityMessage());
  assert.strictEqual(authority.cardCount, 12);
  assert.strictEqual(authority.standardCards.length, 10);
  assert.strictEqual(authority.standardCards[0].id,
    "0123456789abcdef0123456789abcdef:arena-1");
  const visibleCards = authority.standardCards.concat([
    { id: "hidden-1", mode: "hidden" },
    { id: "hidden-2", mode: "hidden" },
  ]);
  assert.deepStrictEqual(visibleStandardCards(visibleCards).map((card) => card.id),
    authority.standardCards.map((card) => card.id));

  const stable = authorityMessage();
  stable.snapshot.arenaAuthority.cards[0].id = "arena-1";
  expectFailure(() => validateAuthoritySnapshot(stable), "arena_session_cards_invalid");
  const malformed = authorityMessage();
  malformed.snapshot.arenaAuthority.sourceDigest = "not-a-digest";
  expectFailure(() => validateAuthoritySnapshot(malformed), "arena_authority_snapshot_invalid");

  const geometry = { rect: { left: 10, top: 20, width: 100, height: 40 } };
  const writer = { events: [{
    sequence: 7,
    kind: "dom_input",
    eventType: "click",
    isTrusted: true,
    clientX: 60,
    clientY: 40,
    panelState: { panel: "arena", hidden: false },
    target: { selector: ".arena-card", text: "挑战", visible: true,
      enabled: true, hitTargetMatches: true },
    eventHash: "fixture-hash",
  }] };
  const click = trustedClickEvidence(writer, 0, geometry);
  assert.strictEqual(click.browserIsTrusted, true);
  assert.strictEqual(click.physicalInputAttestation, false);
  writer.events[0].isTrusted = false;
  expectFailure(() => trustedClickEvidence(writer, 0, geometry), "arena_trusted_click_missing");

  const commands = arenaFlashCommands({ records: [
    { lineNumber: 1, line: "noise" },
    { lineNumber: 2,
      line: "[ArenaTask] -> Flash: {\"task\":\"cmd\",\"action\":\"arenaEnter\",\"deposit\":100}" },
    { lineNumber: 3, line: "[ArenaTask] -> Flash: malformed" },
  ] });
  assert.strictEqual(commands.length, 1);
  assert.strictEqual(commands[0].command.action, "arenaEnter");
  assert.strictEqual(arenaFlashCommands({ lines: [commands[0].line] }).length, 0);
  assert(FORBIDDEN_WEB_AUTHORITY_FIELDS.includes("deposit"));
  assert(FORBIDDEN_WEB_AUTHORITY_FIELDS.includes("authoritySourceDigest"));
  assert.strictEqual(TARGETS.close, ".arena-panel .workbench-close-btn");

  const reordered = { events: [
    { sequence: 8, kind: "bridge_send", message: { type: "panel", panel: "arena",
      cmd: "snapshot", callId: "arena_snap_reordered" } },
    { sequence: 9, kind: "webview_message", message: { type: "panel_cmd", panel: "arena",
      cmd: "open", panelInstanceId: "panel_reordered" } },
    { sequence: 10, kind: "webview_message", message: { type: "panel_resp", panel: "arena",
      cmd: "snapshot", callId: "arena_snap_reordered", success: true } },
  ] };
  const exchange = snapshotExchangeForOpen(reordered, 7, 9);
  assert.deepStrictEqual([exchange.request.event.sequence, exchange.response.event.sequence], [8, 10]);
  assert.strictEqual(snapshotExchangeForOpen(reordered, 7, 10), null);

  const closeBeforeResponse = { events: [
    { sequence: 15, kind: "bridge_send", message: { type: "panel", panel: "arena",
      cmd: "enter", callId: "arena_enter_reordered" } },
    { sequence: 17, kind: "bridge_send", message: { type: "panel", panel: "arena",
      cmd: "close", dismissReturnStack: true } },
    { sequence: 18, kind: "webview_message", message: { type: "panel_resp", panel: "arena",
      cmd: "enter", callId: "arena_enter_reordered", success: true } },
  ] };
  assert.strictEqual(closeRequestAfter(closeBeforeResponse, 15).event.sequence, 17);
  assert.strictEqual(closeRequestAfter(closeBeforeResponse, 18), null);
  assert.strictEqual(isSaveUniverseJsonName(".launcher-version-marker.json",
    "cf7_agent_p5_arena_authority"), false);
  assert.strictEqual(isSaveUniverseJsonName("crazyflasher7_saves.json",
    "cf7_agent_p5_arena_authority"), true);
  assert.strictEqual(isSaveUniverseJsonName("cf7_agent_p5_arena_authority.json",
    "cf7_agent_p5_arena_authority"), false);

  console.log("Arena P5 live-E2E self-tests passed: 20/20");
}

run();
