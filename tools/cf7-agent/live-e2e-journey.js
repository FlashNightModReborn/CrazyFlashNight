'use strict';

const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { findRepoRoot } = require('./harness-orchestrator');
const { snapshotPlayerSaves, verifyPlayerSavesUnchanged } = require('./player-save-guard');

class McpStdioClient {
  constructor(projectRoot) {
    this.projectRoot = projectRoot;
    this.proc = null;
    this.buf = '';
    this.nextId = 1;
    this.pending = new Map();
  }

  start() {
    const mcpPath = path.join(this.projectRoot, 'tools', 'cf7-agent', 'harness-mcp.js');
    this.proc = spawn(process.execPath, [mcpPath], {
      cwd: this.projectRoot,
      stdio: ['pipe', 'pipe', 'inherit']
    });
    this.proc.stdout.setEncoding('utf8');
    this.proc.stdout.on('data', (chunk) => {
      this.buf += chunk;
      for (;;) {
        const nl = this.buf.indexOf('\n');
        if (nl < 0) break;
        const line = this.buf.slice(0, nl).trim();
        this.buf = this.buf.slice(nl + 1);
        if (!line) continue;
        try {
          const msg = JSON.parse(line);
          if (msg && msg.id !== undefined && this.pending.has(msg.id)) {
            const p = this.pending.get(msg.id);
            this.pending.delete(msg.id);
            clearTimeout(p.timer);
            p.resolve(msg);
          }
        } catch (_) {}
      }
    });
  }

  request(method, params, timeoutMs = 60000) {
    const id = this.nextId++;
    const line = JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n';
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`MCP request "${method}" timed out after ${timeoutMs}ms`));
        }
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.proc.stdin.write(line, 'utf8');
    });
  }

  async callTool(name, args = {}, timeoutMs = 60000) {
    const resp = await this.request('tools/call', { name, arguments: args }, timeoutMs);
    if (resp.error) {
      throw new Error(`MCP protocol error on ${name}: ${JSON.stringify(resp.error)}`);
    }
    const text = resp.result && resp.result.content && resp.result.content[0] && resp.result.content[0].text;
    const parsed = text ? JSON.parse(text) : {};
    return { isError: !!resp.result.isError, data: parsed };
  }

  async stop() {
    if (!this.proc) return;
    try { this.proc.stdin.end(); } catch (_) {}
    await new Promise((r) => {
      const t = setTimeout(r, 4000);
      this.proc.once('exit', () => { clearTimeout(t); r(); });
    });
  }
}

async function run() {
  const argv = process.argv.slice(2);
  let runtimeMode = 'isolated_candidate';
  for (let i = 0; i < argv.length - 1; i++) {
    if (argv[i] === '--mode') runtimeMode = argv[i + 1];
  }

  const root = findRepoRoot(__dirname);
  const baseline = snapshotPlayerSaves(root);
  console.log(`[E2E] Player save baseline captured: ${baseline.fileCount} protected files`);

  const client = new McpStdioClient(root);
  client.start();
  const slot = 'cf7_agent_harness_e2e_v1';

  try {
    const init = await client.request('initialize', { protocolVersion: '2025-03-26' });
    assert.equal(init.result.serverInfo.name, 'cf7_harness');

    const tools = await client.request('tools/list', {});
    assert.ok(tools.result.tools.length >= 16);

    const listRes = await client.callTool('cf7_save_list', {});
    assert.ok(listRes.data.slots.length > 0, 'Expected at least one save template in saves/');
    const preferred = listRes.data.slots.find((s) => s.slot === 'cf7_agent_equipment_b_seed_1115')
      || listRes.data.slots.find((s) => !s.corrupt && s.roleName)
      || listRes.data.slots[0];
    console.log(`[E2E] Cloning template slot: ${preferred.slot} -> ${slot}`);

    const cloneRes = await client.callTool('cf7_save_clone', {
      fromSlot: preferred.slot,
      toSlot: slot,
      patches: {
        roleName: '线束E2E特工',
        gold: 888888,
        kpoints: 66666
      }
    });
    assert.equal(cloneRes.isError, false);
    assert.equal(cloneRes.data.summary.gold, 888888);

    console.log(`[E2E] Starting game session under mode=${runtimeMode}...`);
    const started = await client.callTool('cf7_session_start', {
      slot,
      runtimeMode
    }, 90000);
    assert.equal(started.isError, false, `session_start failed: ${JSON.stringify(started.data)}`);
    assert.equal(started.data.ok, true);
    assert.ok(started.data.corePid > 0);
    console.log(`[E2E] Session started! corePid=${started.data.corePid} runtimeMode=${started.data.runtimeMode} buildIdentity=${started.data.runtimeIdentity && started.data.runtimeIdentity.buildIdentity}`);

    // 1. World snapshot & virtual movement input
    const w1 = await client.callTool('cf7_world_snapshot', { includePlayer: true });
    assert.equal(w1.isError, false);
    assert.equal(w1.data.data.worldPresent, true);
    assert.equal(w1.data.data.hero.present, true);
    assert.equal(w1.data.data.money, 888888);
    assert.equal(w1.data.data.kpoint, 66666);
    const startX = w1.data.data.hero.x;
    console.log(`[E2E] Initial hero pos=(${startX}, ${w1.data.data.hero.z}) scene=${w1.data.data.scene.stageName || w1.data.data.scene.stageFlag}`);

    const statusBefore = await client.callTool('cf7_session_status', {});
    console.log(`[E2E] Desktop/LockScreen state: ${JSON.stringify(statusBefore.data.desktop)}`);
    const navSeq = statusBefore.data.eventSeq || 0;
    const targetDx = startX > 500 ? -100 : 100;
    const moveRes = await client.callTool('cf7_world_act', {
      act: 'move_to',
      dx: targetDx,
      dz: 0,
      run: true,
      timeoutFrames: 90
    });
    assert.equal(moveRes.data.ok, true);
    await client.callTool('cf7_wait_for', { sinceSeq: navSeq, regex: '^nav_(completed|timeout)', timeoutMs: 6000 });
    const w2 = await client.callTool('cf7_world_snapshot', {});
    const endX = w2.data.data.hero.x;
    console.log(`[E2E] Moved hero X: ${startX} -> ${endX} (delta=${endX - startX})`);
    assert.ok(Math.abs(endX - startX) >= 20, `Expected hero X to move by >=20px, got ${startX} -> ${endX}`);

    await client.callTool('cf7_world_act', { act: 'tap_key', key: 'jump', durationFrames: 3 });
    await client.callTool('cf7_world_act', { act: 'release_all' });

    // 2. Multi-surface panel sweep: Help (CompositionHelpSurface), Modifier (ModifierOverlay), Settings (WebOverlayForm)
    console.log('[E2E] Sweeping multi-surface panels (help -> modifier -> settings)...');
    const helpOpen = await client.callTool('cf7_panel_open', { panel: 'help' });
    assert.equal(helpOpen.data.success, true, `help open failed: ${JSON.stringify(helpOpen.data)}`);
    const helpDom = await client.callTool('cf7_web_snapshot', {});
    assert.equal(helpDom.data.success, true);
    assert.equal(helpDom.data.surfaceKind, 'composition_help');
    assert.ok(helpDom.data.elementCount > 0, 'Expected interactive DOM in CompositionHelpSurface');
    const helpClose = await client.callTool('cf7_panel_close', {});
    assert.equal(helpClose.data.success, true);

    const modOpen = await client.callTool('cf7_panel_open', { panel: 'modifier' });
    assert.equal(modOpen.data.success, true, `modifier open failed: ${JSON.stringify(modOpen.data)}`);
    const modClose = await client.callTool('cf7_panel_close', {});
    assert.equal(modClose.data.success, true);

    const setOpen = await client.callTool('cf7_panel_open', { panel: 'settings' });
    assert.equal(setOpen.data.success, true);
    const setDom = await client.callTool('cf7_web_snapshot', {});
    assert.equal(setDom.data.success, true);
    assert.ok(setDom.data.elementCount > 0);
    const setClose = await client.callTool('cf7_panel_close', {});
    assert.equal(setClose.data.success, true);

    // 3. Equipment Tuning (WebOverlayForm workbench?view=tuning) closed loop
    console.log('[E2E] Opening Equipment Tuning workbench...');
    const wbOpen = await client.callTool('cf7_panel_open', { panel: 'workbench', view: 'tuning', timeoutMs: 12000 });
    assert.equal(wbOpen.data.success, true, `workbench open failed: ${JSON.stringify(wbOpen.data)}`);
    const wbDom = await client.callTool('cf7_web_snapshot', { maxElements: 200 });
    assert.equal(wbDom.data.success, true);
    assert.equal(wbDom.data.surfaceKind, 'web_overlay');
    assert.ok(wbDom.data.elementCount > 0, 'Expected interactive DOM in Equipment Tuning workbench');
    console.log(`[E2E] Workbench headings: ${JSON.stringify(wbDom.data.headings.slice(0, 5))} elements=${wbDom.data.elementCount}`);

    // Click first non-close interactive equipment/tab item if available to verify web_act
    const candidateBtn = wbDom.data.elements.find((e) =>
      !e.disabled && e.text && !/关闭|返回|Close/i.test(e.text) && (e.tag === 'button' || e.role === 'button' || e.role === 'tab' || e.classes)
    );
    if (candidateBtn) {
      const actRes = await client.callTool('cf7_web_act', { action: 'click', ref: candidateBtn.ref });
      assert.equal(actRes.data.success, true);
    }

    const shot = await client.callTool('cf7_web_screenshot', {
      outputPath: 'tmp/agent-harness/e2e-workbench.png'
    });
    assert.equal(shot.data.success, true);
    assert.ok(shot.data.byteLength > 2000);
    const wbClose = await client.callTool('cf7_panel_close', {});
    assert.equal(wbClose.data.success, true);

    // 4. Restart & persistence readback verification
    console.log('[E2E] Testing save-and-exit + session restart persistence readback...');
    const restartRes = await client.callTool('cf7_session_restart', {
      slot,
      runtimeMode
    }, 100000);
    assert.equal(restartRes.data.ok, true, `restart failed: ${JSON.stringify(restartRes.data)}`);
    assert.equal(restartRes.data.saveAndExit.exitedCleanly, true);
    assert.equal(restartRes.data.started.ok, true);

    const wAfter = await client.callTool('cf7_world_snapshot', {});
    assert.equal(wAfter.data.data.hero.present, true);
    assert.equal(wAfter.data.data.money, 888888);
    assert.equal(wAfter.data.data.kpoint, 66666);

    const inspected = await client.callTool('cf7_save_inspect', { slot });
    assert.equal(inspected.data.summary.gold, 888888);
    assert.equal(inspected.data.summary.kpoints, 66666);

    // 5. Clean save-and-exit + delete temp slot + assert 0 byte change on player saves
    const finalExit = await client.callTool('cf7_session_save_and_exit', {});
    assert.equal(finalExit.data.ok, true, `final save_and_exit failed: ${JSON.stringify(finalExit.data)}`);
    assert.equal(finalExit.data.exitedCleanly, true);
    if (finalExit.data.playerSaveIntegrity) {
      assert.equal(finalExit.data.playerSaveIntegrity.ok, true, JSON.stringify(finalExit.data.playerSaveIntegrity.violations));
    }

    await client.callTool('cf7_save_delete', { slot });
    if (fs.existsSync(path.join(root, 'tmp', 'agent-harness', 'e2e-workbench.png'))) {
      fs.unlinkSync(path.join(root, 'tmp', 'agent-harness', 'e2e-workbench.png'));
    }

    const integrity = verifyPlayerSavesUnchanged(baseline);
    assert.equal(integrity.ok, true, `Player save tampering detected: ${JSON.stringify(integrity.violations)}`);
    console.log(`[E2E] ALL PASSED! Checked ${integrity.checkedFiles} protected player save files: 0 violations.`);
  } finally {
    try { await client.callTool('cf7_save_delete', { slot }); } catch (_) {}
    await client.stop();
  }
}

run().catch((err) => {
  console.error('[E2E] FAILED:', err);
  process.exit(1);
});
