'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { PassThrough } = require('stream');

const { isValidAgentSlot, snapshotPlayerSaves, verifyPlayerSavesUnchanged } = require('../player-save-guard');
const { listSaves, cloneSave, inspectSave, deleteAgentSave } = require('../save-manager');
const { HarnessOrchestrator } = require('../harness-orchestrator');
const { startStdioServer } = require('../harness-mcp');

function makeTempProject() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-ah-node-'));
  fs.writeFileSync(path.join(dir, 'crossdomain.xml'), '<cross-domain-policy/>', 'utf8');
  const savesDir = path.join(dir, 'saves');
  fs.mkdirSync(savesDir, { recursive: true });

  const sampleSave = {
    version: 2,
    lastSaved: '2026-11-16',
    '0': ['玩家一号', '男', 1000, 10, 500, 175, 5, '新人', 10000, 200],
    '1': ['脸1', '发1'],
    '3': 4,
    inventory: {
      '背包': {
        '0': { name: 'TTI Glock 19', value: { level: 1 }, lastUpdate: 1700000000000 }
      },
      '装备栏': {},
      '药剂栏': {},
      '仓库': {},
      '战备箱': {}
    }
  };
  fs.writeFileSync(path.join(savesDir, 'cf7_player_real.json'), JSON.stringify(sampleSave), 'utf8');
  return dir;
}

test('player-save-guard allows only cf7_agent_* slots and detects player save writes', () => {
  assert.equal(isValidAgentSlot('cf7_agent_verify_01'), true);
  assert.equal(isValidAgentSlot('slot_1'), false);
  assert.equal(isValidAgentSlot('crazyflasher7_saves'), false);
  assert.equal(isValidAgentSlot('cf7_player_real'), false);
  assert.equal(isValidAgentSlot('cf7_agent_../bad'), false);

  const root = makeTempProject();
  try {
    const baseline = snapshotPlayerSaves(root);
    assert.equal(verifyPlayerSavesUnchanged(baseline).ok, true);

    const cloneRes = cloneSave({
      projectRoot: root,
      fromSlot: 'cf7_player_real',
      toSlot: 'cf7_agent_test_clone',
      patches: {
        roleName: '自动化特工',
        gold: 999999,
        kpoints: 50000,
        level: 45,
        addItems: [{ name: '强化石', value: 20 }]
      }
    });
    assert.equal(cloneRes.ok, true);
    assert.equal(cloneRes.summary.gold, 999999);
    assert.equal(cloneRes.summary.kpoints, 50000);
    assert.equal(cloneRes.summary.level, 45);
    assert.equal(cloneRes.summary.roleName, '自动化特工');
    assert.equal(cloneRes.summary.inventoryCounts.backpack, 2);

    // Player save must be 100% untouched.
    assert.equal(verifyPlayerSavesUnchanged(baseline).ok, true);

    assert.throws(() => cloneSave({
      projectRoot: root,
      fromSlot: 'cf7_player_real',
      toSlot: 'cf7_player_overwrite'
    }), /Invalid agent toSlot/);

    assert.throws(() => deleteAgentSave({
      projectRoot: root,
      slot: 'cf7_player_real'
    }), /Invalid agent slot/);

    const listed = listSaves({ projectRoot: root });
    assert.equal(listed.slots.length, 2);

    const inspected = inspectSave({ projectRoot: root, slot: 'cf7_agent_test_clone' });
    assert.equal(inspected.backpack.length, 2);

    deleteAgentSave({ projectRoot: root, slot: 'cf7_agent_test_clone' });
    assert.equal(listSaves({ projectRoot: root }).slots.length, 1);

    // If player save is externally altered, guard must flag it.
    fs.writeFileSync(path.join(root, 'saves', 'cf7_player_real.json'), '{"tampered":true}', 'utf8');
    const bad = verifyPlayerSavesUnchanged(baseline);
    assert.equal(bad.ok, false);
    assert.equal(bad.violations[0].type, 'modified');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('harness-mcp handles newline-delimited and Content-Length MCP framing', async () => {
  const root = makeTempProject();
  try {
    // 1. Newline framing (standard Codex MCP stdio)
    {
      const input = new PassThrough();
      const output = new PassThrough();
      const chunks = [];
      output.on('data', (c) => chunks.push(c));

      const { server, cleanup } = startStdioServer({ projectRoot: root, input, output });
      input.write(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26' } }) + '\n');
      input.write(JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }) + '\n');
      input.write(JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'cf7_save_list', arguments: {} } }) + '\n');
      input.end();

      await new Promise((r) => setTimeout(r, 80));
      const lines = Buffer.concat(chunks).toString('utf8').trim().split('\n').map((l) => JSON.parse(l));
      assert.equal(lines.length, 3);
      assert.equal(lines[0].result.protocolVersion, '2025-03-26');
      assert.ok(lines[1].result.tools.some((t) => t.name === 'cf7_session_start'));
      const listRes = JSON.parse(lines[2].result.content[0].text);
      assert.equal(listRes.slots.length, 1);
      await cleanup();
      void server;
    }

    // 2. Content-Length LSP framing
    {
      const input = new PassThrough();
      const output = new PassThrough();
      const chunks = [];
      output.on('data', (c) => chunks.push(c));

      const { cleanup } = startStdioServer({ projectRoot: root, input, output });
      const msg = JSON.stringify({ jsonrpc: '2.0', id: 10, method: 'ping' });
      const pkt = `Content-Length: ${Buffer.byteLength(msg, 'utf8')}\r\n\r\n${msg}`;
      input.write(pkt);
      input.end();

      await new Promise((r) => setTimeout(r, 80));
      const raw = Buffer.concat(chunks).toString('utf8');
      assert.match(raw, /^Content-Length: \d+\r\n\r\n/);
      const body = JSON.parse(raw.split('\r\n\r\n')[1]);
      assert.equal(body.id, 10);
      await cleanup();
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('HarnessOrchestrator.worldAct normalizes relative move_to dx/dz and timeoutFrames', async () => {
  const orch = new HarnessOrchestrator();
  const calls = [];
  orch.activeSession = {
    client: {
      async request(method, params) {
        calls.push({ method, params });
        if (method === 'world.snapshot') {
          return { ok: true, result: { ok: true, data: { hero: { present: true, x: 400, z: 250 } } } };
        }
        return { ok: true, result: { ok: true, data: params } };
      }
    }
  };
  const res = await orch.worldAct({ act: 'move_to', dx: 80, dz: -10, timeoutFrames: 90, run: true });
  assert.equal(res.ok, true);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].method, 'world.snapshot');
  assert.equal(calls[1].method, 'world.act');
  assert.equal(calls[1].params.x, 480);
  assert.equal(calls[1].params.z, 240);
  assert.equal(calls[1].params.maxFrames, 90);
  assert.equal(calls[1].params.run, true);
});
