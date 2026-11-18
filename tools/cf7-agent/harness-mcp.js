'use strict';

const { HarnessOrchestrator, findRepoRoot } = require('./harness-orchestrator');
const { snapshotPlayerSaves, verifyPlayerSavesUnchanged } = require('./player-save-guard');
const { listSaves, cloneSave, inspectSave, deleteAgentSave } = require('./save-manager');

const TOOLS = [
  {
    name: 'cf7_save_list',
    description: 'List available player save templates (read-only) and isolated cf7_agent_* test saves.',
    inputSchema: {
      type: 'object',
      properties: {
        includeBookruns: { type: 'boolean', description: 'Include bookrun_* saves (default false).' }
      }
    }
  },
  {
    name: 'cf7_save_clone',
    description: 'Safely clone any save into a strictly isolated cf7_agent_* slot with optional patches (gold, kpoints, level, addItems). Never modifies real player saves.',
    inputSchema: {
      type: 'object',
      required: ['fromSlot', 'toSlot'],
      properties: {
        fromSlot: { type: 'string', description: 'Source slot name (e.g. cf7_23a03da3570a46b39b3ff59edcfb or cf7_agent_*).' },
        toSlot: { type: 'string', description: 'Destination slot name; MUST start with cf7_agent_.' },
        patches: {
          type: 'object',
          description: 'Optional fixture overrides: { roleName?, gold?, kpoints?, level?, skillPoints?, mainProgress?, addItems?: [{ name, value, container? }] }.'
        }
      }
    }
  },
  {
    name: 'cf7_save_inspect',
    description: 'Inspect structured contents of a save slot JSON shadow (gold, kpoints, level, inventory, equipment, tasks, settings).',
    inputSchema: {
      type: 'object',
      required: ['slot'],
      properties: {
        slot: { type: 'string' }
      }
    }
  },
  {
    name: 'cf7_save_delete',
    description: 'Delete an isolated cf7_agent_* save (JSON shadow, tombstone, and Flash SOL). Refuses any non-agent slot.',
    inputSchema: {
      type: 'object',
      required: ['slot'],
      properties: {
        slot: { type: 'string' }
      }
    }
  },
  {
    name: 'cf7_session_start',
    description: 'Start the game cleanly under `--agent-harness` (no focus steal, works under Windows lock screen Win+L) and enter a cf7_agent_* slot.',
    inputSchema: {
      type: 'object',
      properties: {
        slot: { type: 'string', description: 'Agent save slot to enter automatically (must match ^cf7_agent_*).' },
        runtimeMode: { type: 'string', enum: ['auto', 'isolated_candidate', 'formal_runtime'], description: 'Runtime binary mode (default auto).' },
        fresh: { type: 'boolean', description: 'Start fresh instead of loading snapshot.' },
        allowHeadlessFallback: { type: 'boolean', description: 'Allow deterministic lock-screen scene-fence fallback (default true).' },
        bootTimeoutMs: { type: 'number' },
        enterTimeoutMs: { type: 'number' }
      }
    }
  },
  {
    name: 'cf7_session_status',
    description: 'Return current harness status, PID, runtime identity, active panel, desktop lock state, and event/log watermarks.',
    inputSchema: { type: 'object', properties: {} }
  },
  {
    name: 'cf7_session_save_and_exit',
    description: 'Close open panels, durably flush AS2 save + confirm ArchiveTask shadow write, pass shutdown fence, and wait for clean exit.',
    inputSchema: {
      type: 'object',
      properties: {
        flushSave: { type: 'boolean', description: 'Flush AS2 save before exiting (default true).' },
        closePanelsFirst: { type: 'boolean', description: 'Close active panel before saving (default true).' },
        timeoutMs: { type: 'number' }
      }
    }
  },
  {
    name: 'cf7_session_restart',
    description: 'Save and cleanly exit the current session, then relaunch the exact same slot and runtimeMode for persistence readback verification.',
    inputSchema: {
      type: 'object',
      properties: {
        slot: { type: 'string' },
        runtimeMode: { type: 'string', enum: ['auto', 'isolated_candidate', 'formal_runtime'] }
      }
    }
  },
  {
    name: 'cf7_panel_open',
    description: 'Open any game Web panel or AS2-backed panel (workbench, kshop, skills, map, tasks, team, help, settings, npcshop, crafting, gym, bookshelf, sleep, modifier, etc.).',
    inputSchema: {
      type: 'object',
      required: ['panel'],
      properties: {
        panel: { type: 'string', description: 'Panel id (e.g. workbench, settings, help, skills, map, kshop, npcshop, crafting, modifier, sleep, gym).' },
        view: { type: 'string', description: 'Optional sub-view (e.g. tuning, build).' },
        profile: { type: 'string' },
        shopId: { type: 'string' },
        closeCurrentFirst: { type: 'boolean' },
        reopenIfOpen: { type: 'boolean' },
        timeoutMs: { type: 'number' }
      }
    }
  },
  {
    name: 'cf7_panel_close',
    description: 'Gracefully close the currently active Web or Modifier panel (with force fallback).',
    inputSchema: {
      type: 'object',
      properties: {
        force: { type: 'boolean' },
        timeoutMs: { type: 'number' }
      }
    }
  },
  {
    name: 'cf7_web_snapshot',
    description: 'Extract structured interactive DOM elements (refs e1..eN, text, disabled/selected, data-*, rect) from the active WebView2 panel without screenshots.',
    inputSchema: {
      type: 'object',
      properties: {
        rootSelector: { type: 'string' },
        maxElements: { type: 'number' }
      }
    }
  },
  {
    name: 'cf7_web_act',
    description: 'Act on an element in the active WebView2 panel by ref (e.g. "e3"), CSS selector, or visible text: click, double_click, right_click, fill, select, press_key, hover, scroll, eval_readonly.',
    inputSchema: {
      type: 'object',
      required: ['action'],
      properties: {
        action: { type: 'string', enum: ['click', 'double_click', 'right_click', 'fill', 'select', 'press_key', 'hover', 'scroll', 'eval', 'eval_readonly'] },
        ref: { type: 'string' },
        selector: { type: 'string' },
        text: { type: 'string' },
        value: { type: 'string' },
        label: { type: 'string' },
        key: { type: 'string' },
        deltaY: { type: 'number' },
        top: { type: 'number' },
        script: { type: 'string' }
      }
    }
  },
  {
    name: 'cf7_web_screenshot',
    description: 'Capture a PNG screenshot of the active WebView2 surface directly via CoreWebView2 (works in background / lock screen). Output path must be under tmp/.',
    inputSchema: {
      type: 'object',
      properties: {
        outputPath: { type: 'string' }
      }
    }
  },
  {
    name: 'cf7_world_snapshot',
    description: 'Read structured Flash world state: scene, frame, money, kpoint, hero pos/hp/mp/state, nearest units, pickups, doors, interactions, active dialogue.',
    inputSchema: {
      type: 'object',
      properties: {
        includePlayer: { type: 'boolean' },
        timeoutMs: { type: 'number' }
      }
    }
  },
  {
    name: 'cf7_world_act',
    description: 'Drive virtual Flash input / world navigation (works backgrounded and under Win+L): release_all, hold_mask, tap_mask, hold_keys, tap_key, move_to, pickup, interact, open_panel.',
    inputSchema: {
      type: 'object',
      required: ['act'],
      properties: {
        act: { type: 'string', enum: ['release_all', 'hold_mask', 'tap_mask', 'hold_keys', 'tap_key', 'tap_keys', 'move_to', 'pickup', 'interact', 'advance_dialogue', 'return_after_victory', 'open_panel'] },
        mask: { type: 'number' },
        key: { type: 'string' },
        keys: { type: 'array', items: { type: 'string' } },
        durationFrames: { type: 'number' },
        x: { type: 'number' },
        z: { type: 'number' },
        dx: { type: 'number' },
        dz: { type: 'number' },
        tolerance: { type: 'number' },
        run: { type: 'boolean' },
        maxFrames: { type: 'number' },
        timeoutFrames: { type: 'number' },
        target: { type: 'string' },
        panel: { type: 'string' }
      }
    }
  },
  {
    name: 'cf7_wait_for',
    description: 'Zero-polling await on host event watermark (panel_changed, panel_closed, launch_state, archive_shadow_saved, scene_transition, as2_*).',
    inputSchema: {
      type: 'object',
      properties: {
        sinceSeq: { type: 'number' },
        kind: { type: 'string' },
        panel: { type: 'string' },
        slot: { type: 'string' },
        state: { type: 'string' },
        contains: { type: 'string' },
        regex: { type: 'string' },
        timeoutMs: { type: 'number' }
      }
    }
  },
  {
    name: 'cf7_logs_query',
    description: 'Read structured Launcher/Flash log lines after a given logSeq watermark with substring/regex filter.',
    inputSchema: {
      type: 'object',
      properties: {
        sinceSeq: { type: 'number' },
        limit: { type: 'number' },
        contains: { type: 'string' },
        regex: { type: 'string' }
      }
    }
  }
];

function createMcpServer({ projectRoot, orchestrator } = {}) {
  const root = findRepoRoot(projectRoot || __dirname);
  const orch = orchestrator || new HarnessOrchestrator(root);
  let playerSaveBaseline = null;

  async function dispatchTool(name, args = {}) {
    switch (name) {
      case 'cf7_save_list':
        return listSaves({ projectRoot: root, includeBookruns: !!args.includeBookruns });
      case 'cf7_save_clone':
        if (!playerSaveBaseline) playerSaveBaseline = snapshotPlayerSaves(root);
        return cloneSave({ projectRoot: root, fromSlot: args.fromSlot, toSlot: args.toSlot, patches: args.patches });
      case 'cf7_save_inspect':
        return inspectSave({ projectRoot: root, slot: args.slot });
      case 'cf7_save_delete':
        return deleteAgentSave({ projectRoot: root, slot: args.slot });
      case 'cf7_session_start': {
        if (!playerSaveBaseline) playerSaveBaseline = snapshotPlayerSaves(root);
        return await orch.startSession(args);
      }
      case 'cf7_session_status':
        return await orch.status();
      case 'cf7_session_save_and_exit': {
        const res = await orch.saveAndExit(args);
        if (playerSaveBaseline) {
          res.playerSaveIntegrity = verifyPlayerSavesUnchanged(playerSaveBaseline);
        }
        return res;
      }
      case 'cf7_session_restart':
        return await orch.restart(args);
      case 'cf7_panel_open':
        return await orch.panelOpen(args);
      case 'cf7_panel_close':
        return await orch.panelClose(args);
      case 'cf7_web_snapshot':
        return await orch.webSnapshot(args);
      case 'cf7_web_act':
        return await orch.webAct(args);
      case 'cf7_web_screenshot':
        return await orch.webScreenshot(args);
      case 'cf7_world_snapshot':
        return await orch.worldSnapshot(args);
      case 'cf7_world_act':
        return await orch.worldAct(args);
      case 'cf7_wait_for':
        return await orch.waitFor(args);
      case 'cf7_logs_query':
        return await orch.logsQuery(args);
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  }

  async function handleJsonRpcMessage(msg) {
    if (!msg || typeof msg !== 'object') return null;
    const { id, method, params } = msg;
    const isNotification = id === undefined || id === null;

    if (method === 'initialize') {
      const requestedProto = params && typeof params.protocolVersion === 'string'
        ? params.protocolVersion
        : '2024-11-05';
      return {
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: requestedProto,
          capabilities: { tools: {} },
          serverInfo: { name: 'cf7_harness', version: '1.0.0' }
        }
      };
    }

    if (method === 'notifications/initialized' || method === 'notifications/cancelled') {
      return null;
    }

    if (method === 'ping') {
      return isNotification ? null : { jsonrpc: '2.0', id, result: {} };
    }

    if (method === 'tools/list') {
      return { jsonrpc: '2.0', id, result: { tools: TOOLS } };
    }

    if (method === 'tools/call') {
      const toolName = params && params.name;
      const toolArgs = (params && params.arguments) || {};
      try {
        const resultObj = await dispatchTool(toolName, toolArgs);
        const isErr = resultObj && (resultObj.ok === false || resultObj.success === false) && !!resultObj.error;
        return {
          jsonrpc: '2.0',
          id,
          result: {
            content: [{ type: 'text', text: JSON.stringify(resultObj) }],
            isError: isErr
          }
        };
      } catch (err) {
        return {
          jsonrpc: '2.0',
          id,
          result: {
            content: [{ type: 'text', text: JSON.stringify({ ok: false, error: 'tool_exception', message: err.message }) }],
            isError: true
          }
        };
      }
    }

    if (isNotification) return null;
    return {
      jsonrpc: '2.0',
      id,
      error: { code: -32601, message: `Method not found: ${method}` }
    };
  }

  async function dispose() {
    try { await orch.shutdownSession({ forceOnTimeout: true }); } catch (_) {}
  }

  return { TOOLS, dispatchTool, handleJsonRpcMessage, dispose, orchestrator: orch };
}

function startStdioServer(options = {}) {
  const input = options.input || process.stdin;
  const output = options.output || process.stdout;
  const server = createMcpServer(options);

  let buf = Buffer.alloc(0);
  let detectedFraming = null; // 'lsp' | 'newline'

  function writeMessage(obj) {
    if (!obj) return;
    const json = JSON.stringify(obj);
    if (detectedFraming === 'lsp') {
      const body = Buffer.from(json, 'utf8');
      const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, 'ascii');
      output.write(Buffer.concat([header, body]));
    } else {
      output.write(json + '\n', 'utf8');
    }
  }

  function drainMessages() {
    const messages = [];
    for (;;) {
      if (buf.length === 0) break;
      const headPreview = buf.slice(0, Math.min(buf.length, 32)).toString('ascii');
      if (detectedFraming === 'lsp' || /^Content-Length:\s*\d+/i.test(headPreview)) {
        detectedFraming = 'lsp';
        const headerEnd = buf.indexOf('\r\n\r\n');
        const altEnd = headerEnd >= 0 ? headerEnd : buf.indexOf('\n\n');
        const sepLen = headerEnd >= 0 ? 4 : 2;
        if (altEnd < 0) break;
        const headerStr = buf.slice(0, altEnd).toString('ascii');
        const m = /Content-Length:\s*(\d+)/i.exec(headerStr);
        if (!m) {
          buf = buf.slice(altEnd + sepLen);
          continue;
        }
        const len = parseInt(m[1], 10);
        const total = altEnd + sepLen + len;
        if (buf.length < total) break;
        const body = buf.slice(altEnd + sepLen, total).toString('utf8');
        buf = buf.slice(total);
        messages.push(JSON.parse(body));
      } else {
        const nl = buf.indexOf(0x0a);
        if (nl < 0) break;
        detectedFraming = detectedFraming || 'newline';
        const line = buf.slice(0, nl).toString('utf8').trim();
        buf = buf.slice(nl + 1);
        if (line) messages.push(JSON.parse(line));
      }
    }
    return messages;
  }

  let chain = Promise.resolve();
  input.on('data', (chunk) => {
    buf = Buffer.concat([buf, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, 'utf8')]);
    let msgs;
    try {
      msgs = drainMessages();
    } catch (_) {
      return;
    }
    for (const msg of msgs) {
      chain = chain.then(async () => {
        const resp = await server.handleJsonRpcMessage(msg);
        if (resp) writeMessage(resp);
      }).catch(() => {});
    }
  });

  const cleanup = async () => {
    await server.dispose();
  };
  input.on('end', () => { chain.finally(cleanup); });

  return { server, cleanup };
}

if (require.main === module) {
  const { cleanup } = startStdioServer();
  const exitCleanly = async () => {
    await cleanup();
    process.exit(0);
  };
  process.on('SIGINT', exitCleanly);
  process.on('SIGTERM', exitCleanly);
}

module.exports = {
  TOOLS,
  createMcpServer,
  startStdioServer
};
