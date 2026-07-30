#!/usr/bin/env node
'use strict';

const {
  PrelaunchError,
  launchFormalRuntime,
} = require('./lib/prelaunch');

async function runPrelaunchCli(options = {}) {
  const output = options.output ?? process.stdout;
  const diagnostic =
    options.diagnostic ?? process.stderr;
  try {
    const parsed = parsePrelaunchArguments(
      options.argv ?? process.argv.slice(2),
    );
    const receipt = await (
      options.launchAuthority
        ?? launchFormalRuntime
    )(parsed);
    output.write(`${JSON.stringify(receipt)}\n`);
    return 0;
  } catch (error) {
    const safe = error instanceof PrelaunchError
      ? `${error.code}: ${error.message}`
      : 'prelaunch_failed: The formal-runtime launch handoff failed.';
    diagnostic.write(`cf7-agent-prelaunch: ${safe}\n`);
    return 1;
  }
}

function parsePrelaunchArguments(argv) {
  let clientInstanceId;
  for (let index = 0; index < argv.length; index += 1) {
    const option = argv[index];
    if (option !== '--client-instance-id') {
      throw new PrelaunchError(
        'argument_invalid',
        'Only --client-instance-id is accepted.',
      );
    }
    if (clientInstanceId !== undefined) {
      throw new PrelaunchError(
        'argument_invalid',
        '--client-instance-id may be supplied only once.',
      );
    }
    clientInstanceId = argv[++index];
    if (
      typeof clientInstanceId !== 'string'
      || clientInstanceId === ''
    ) {
      throw new PrelaunchError(
        'client_instance_id_required',
        '--client-instance-id requires an explicit value.',
      );
    }
  }
  if (clientInstanceId === undefined) {
    throw new PrelaunchError(
      'client_instance_id_required',
      '--client-instance-id is required.',
    );
  }
  return { clientInstanceId };
}

async function main() {
  process.exitCode = await runPrelaunchCli();
}

if (require.main === module)
  void main();

module.exports = {
  parsePrelaunchArguments,
  runPrelaunchCli,
};
