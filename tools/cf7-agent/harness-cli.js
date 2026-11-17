'use strict';

const { createMcpServer } = require('./harness-mcp');
const { findRepoRoot } = require('./harness-orchestrator');

const CMD_TO_TOOL = {
  'save-list': 'cf7_save_list',
  'save-clone': 'cf7_save_clone',
  'save-inspect': 'cf7_save_inspect',
  'save-delete': 'cf7_save_delete',
  'start': 'cf7_session_start',
  'status': 'cf7_session_status',
  'save-and-exit': 'cf7_session_save_and_exit',
  'restart': 'cf7_session_restart',
  'panel-open': 'cf7_panel_open',
  'panel-close': 'cf7_panel_close',
  'web-snapshot': 'cf7_web_snapshot',
  'web-act': 'cf7_web_act',
  'web-screenshot': 'cf7_web_screenshot',
  'world-snapshot': 'cf7_world_snapshot',
  'world-act': 'cf7_world_act',
  'wait-for': 'cf7_wait_for',
  'logs': 'cf7_logs_query'
};

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv[0] === '--help' || argv[0] === '-h') {
    console.log('Usage: node tools/cf7-agent/harness-cli.js <command> [json-args]');
    console.log('Commands:', Object.keys(CMD_TO_TOOL).join(', '));
    process.exit(0);
  }
  const cmd = argv[0];
  const toolName = CMD_TO_TOOL[cmd] || cmd;
  const rawArgs = argv[1] ? JSON.parse(argv[1]) : {};
  const mcp = createMcpServer({ projectRoot: findRepoRoot(process.cwd()) });
  try {
    const res = await mcp.dispatchTool(toolName, rawArgs);
    console.log(JSON.stringify(res, null, 2));
    if (res && (res.ok === false || res.success === false) && res.error) {
      process.exitCode = 1;
    }
  } finally {
    await mcp.dispose();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
