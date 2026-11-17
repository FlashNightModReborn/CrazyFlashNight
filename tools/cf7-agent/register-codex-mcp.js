'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { findRepoRoot } = require('./harness-orchestrator');

function toTomlLiteral(val) {
  return JSON.stringify(val);
}

function registerCodexMcp({
  configPath = path.join(os.homedir(), '.codex', 'config.toml'),
  projectRoot = findRepoRoot(__dirname),
  backupDir = path.join(findRepoRoot(__dirname), 'tmp', 'agent-harness')
} = {}) {
  if (!fs.existsSync(configPath)) {
    throw new Error(`Codex config not found: ${configPath}`);
  }
  const orig = fs.readFileSync(configPath, 'utf8');
  fs.mkdirSync(backupDir, { recursive: true });
  const backupPath = path.join(backupDir, `codex-config.backup.${Date.now()}.toml`);
  fs.writeFileSync(backupPath, orig, 'utf8');

  const mcpScript = path.join(projectRoot, 'tools', 'cf7-agent', 'harness-mcp.js');
  const nodeExe = process.execPath;

  const block = [
    '[mcp_servers.cf7_harness]',
    `command = ${toTomlLiteral(nodeExe)}`,
    `args = [${toTomlLiteral(mcpScript)}]`,
    'startup_timeout_sec = 30',
    'tool_timeout_sec = 120'
  ].join('\n');

  const sectionRegex = /^\[mcp_servers\.cf7_harness\][^\S\r\n]*\r?\n(?:(?!\[)[^\r\n]*\r?\n?)*/m;
  let updated;
  if (sectionRegex.test(orig)) {
    updated = orig.replace(sectionRegex, block + '\n');
  } else {
    const needsNewline = orig.length > 0 && !orig.endsWith('\n');
    updated = orig + (needsNewline ? '\n\n' : '\n') + block + '\n';
  }

  fs.writeFileSync(configPath, updated, 'utf8');
  return { ok: true, configPath, backupPath, mcpScript, nodeExe };
}

if (require.main === module) {
  const res = registerCodexMcp();
  console.log(JSON.stringify(res, null, 2));
}

module.exports = { registerCodexMcp };
