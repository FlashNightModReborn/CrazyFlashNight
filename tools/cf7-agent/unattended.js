#!/usr/bin/env node
'use strict';

const childProcess = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const ALLOWED_SLOTS = new Set([
  'cf7_agent_equipment_tuning',
  'cf7_agent_arena_calibration',
  'cf7_agent_character_build',
  'cf7_agent_loot_target_full_v1',
]);
const CANDIDATE_ID =
  /^c-[0-9a-f]{12}-[0-9a-f]{10}-[a-z0-9][a-z0-9-]{0,31}$/u;

class UnattendedArgumentError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'UnattendedArgumentError';
    this.code = code;
  }
}

function parseUnattendedArguments(argv) {
  let adapter;
  let slot;
  let candidateId;
  for (let index = 0; index < argv.length; index += 1) {
    const option = argv[index];
    if (option === '--adapter') {
      if (adapter !== undefined)
        failDuplicate(option);
      adapter = requiredValue(argv, ++index, option);
    } else if (option === '--slot') {
      if (slot !== undefined)
        failDuplicate(option);
      slot = requiredValue(argv, ++index, option);
    } else if (option === '--candidate-id') {
      if (candidateId !== undefined)
        failDuplicate(option);
      candidateId =
        requiredValue(argv, ++index, option);
    } else {
      throw new UnattendedArgumentError(
        'argument_invalid',
        `Unknown unattended option: ${option}`,
      );
    }
  }
  if (!['jsonl', 'mcp'].includes(adapter)) {
    throw new UnattendedArgumentError(
      'adapter_invalid',
      '--adapter must be exactly jsonl or mcp.',
    );
  }
  if (!ALLOWED_SLOTS.has(slot)) {
    throw new UnattendedArgumentError(
      'slot_invalid',
      '--slot must be one frozen unattended slot.',
    );
  }
  if (
    candidateId !== undefined
    && !CANDIDATE_ID.test(candidateId)
  ) {
    throw new UnattendedArgumentError(
      'candidate_invalid',
      '--candidate-id must be one immutable v2 candidate leaf.',
    );
  }
  return Object.freeze({
    adapter,
    slot,
    candidateId,
  });
}

function requiredValue(argv, index, option) {
  const value = argv[index];
  if (typeof value !== 'string' || value === '') {
    throw new UnattendedArgumentError(
      'argument_invalid',
      `${option} requires a value.`,
    );
  }
  return value;
}

function failDuplicate(option) {
  throw new UnattendedArgumentError(
    'argument_invalid',
    `${option} may be supplied only once.`,
  );
}

function main() {
  try {
    const parsed = parseUnattendedArguments(
      process.argv.slice(2),
    );
    const projectRoot = path.resolve(
      __dirname,
      '..',
      '..',
    );
    const startScript = path.join(
      projectRoot,
      'automation',
      'start.ps1',
    );
    const systemRoot = process.env.SystemRoot;
    if (
      process.platform !== 'win32'
      || typeof systemRoot !== 'string'
    ) {
      throw new Error(
        'The fixed Windows trusted Core wrapper is unavailable.',
      );
    }
    const powershell = path.join(
      systemRoot,
      'System32',
      'WindowsPowerShell',
      'v1.0',
      'powershell.exe',
    );
    if (
      !fs.statSync(startScript).isFile()
      || !fs.statSync(powershell).isFile()
    ) {
      throw new Error(
        'The fixed trusted Core wrapper path is unavailable.',
      );
    }
    const args = [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      startScript,
      '-UnattendedSlot',
      parsed.slot,
      '-UnattendedAdapter',
      parsed.adapter,
    ];
    if (parsed.candidateId !== undefined) {
      args.push(
        '-CandidateRoot',
        path.join(
          projectRoot,
          'tmp',
          'runtime-candidates',
          'v2',
          parsed.candidateId,
        ),
      );
    }
    const result = childProcess.spawnSync(
      powershell,
      args,
      {
        cwd: projectRoot,
        stdio: 'inherit',
        windowsHide: true,
        shell: false,
      },
    );
    if (result.error) throw result.error;
    process.exitCode = Number.isInteger(result.status)
      ? result.status
      : 1;
  } catch (error) {
    process.stderr.write(
      `cf7-agent-unattended: ${error.message}\n`,
    );
    process.exitCode = 1;
  }
}

if (require.main === module)
  main();

module.exports = {
  parseUnattendedArguments,
};
