#!/usr/bin/env node
'use strict';

const readline = require('node:readline');
const { AgentClient, AgentRpcError } = require('./lib/client');
const { MAX_JSON_FRAME_BYTES, validateRequest } = require('./lib/contract');
const { parseAdapterOptions } = require('./lib/options');
const { parseStrictJson } = require('./lib/strict-json');

async function runCli(options) {
  const input = options.input ?? process.stdin;
  const output = options.output ?? process.stdout;
  const diagnostic = options.diagnostic ?? process.stderr;
  const client = options.client ?? await (
    options.createClient ?? AgentClient.connect
  )({
    ...options.clientOptions,
    clientKind: 'jsonl_cli',
  });
  const lines = readline.createInterface({
    input,
    crlfDelay: Infinity,
    terminal: false,
  });
  let hadInputError = false;
  try {
    for await (const line of lines) {
      if (line.trim() === '') continue;
      try {
        if (
          Buffer.byteLength(line, 'utf8')
          > MAX_JSON_FRAME_BYTES
        ) {
          throw new Error('JSONL request exceeds 1 MiB');
        }
        const request = parseStrictJson(line);
        validateRequest(request);
        if (request.method === 'runtime.hello') {
          throw new Error(
            'runtime.hello is reserved for the shared client',
          );
        }
        let result;
        if (request.method === 'content.read') {
          const chunk = await client.readContentChunk(
            request.params.handle,
            request.params.offset,
            request.params.count,
          );
          result = {
            result: chunk.result,
            metadata: chunk.metadata,
            contentBase64:
              chunk.content.toString('base64'),
          };
        } else {
          result = await client.call(
            request.method,
            request.params,
          );
        }
        writeMessage(output, {
          jsonrpc: '2.0',
          id: request.id,
          result,
        });
      } catch (error) {
        if (
          error instanceof AgentRpcError
          && typeof error.requestId !== 'undefined'
        ) {
          writeMessage(output, {
            jsonrpc: '2.0',
            id: error.requestId,
            error: error.errorPayload,
          });
        } else if (error instanceof AgentRpcError) {
          const requestId = tryReadRequestId(line);
          if (requestId !== null) {
            writeMessage(output, {
              jsonrpc: '2.0',
              id: requestId,
              error: error.errorPayload,
            });
          }
        } else {
          hadInputError = true;
          diagnostic.write(`cf7-agent-cli: ${error.message}\n`);
        }
      }
    }
  } finally {
    lines.close();
    if (!options.keepClientOpen) client.close();
  }
  return hadInputError ? 2 : 0;
}

function tryReadRequestId(line) {
  try {
    const request = parseStrictJson(line);
    return (
      typeof request.id === 'string'
      && request.id.length >= 1
      && request.id.length <= 128
    )
      ? request.id
      : null;
  } catch {
    return null;
  }
}

function writeMessage(output, message) {
  output.write(`${JSON.stringify(message)}\n`);
}

async function main() {
  try {
    const clientOptions = parseAdapterOptions(
      process.argv.slice(2),
    );
    const exitCode = await runCli({ clientOptions });
    process.exitCode = exitCode;
  } catch (error) {
    process.stderr.write(`cf7-agent-cli: ${error.message}\n`);
    process.exitCode = 1;
  }
}

if (require.main === module) {
  void main();
}

module.exports = {
  runCli,
  tryReadRequestId,
  writeMessage,
};
