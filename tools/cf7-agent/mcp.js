#!/usr/bin/env node
'use strict';

const readline = require('node:readline');
const { AgentClient, AgentRpcError } = require('./lib/client');
const {
  MAX_JSON_FRAME_BYTES,
  exactObject,
  isObject,
  methodInputSchema,
  methods,
  validateContentRead,
} = require('./lib/contract');
const { parseAdapterOptions } = require('./lib/options');
const { parseStrictJson } = require('./lib/strict-json');

const MCP_PROTOCOL_VERSION = '2025-06-18';

class McpAdapter {
  constructor(client, output, diagnostic) {
    this.client = client;
    this.output = output;
    this.diagnostic = diagnostic;
    this.initializeResponded = false;
    this.receivedInitializedNotification = false;
    this.active = new Map();
  }

  async receive(line) {
    let message;
    try {
      if (
        Buffer.byteLength(line, 'utf8')
        > MAX_JSON_FRAME_BYTES
      ) {
        throw new Error('MCP message exceeds 1 MiB');
      }
      message = parseStrictJson(line);
    } catch (error) {
      this.writeError(
        null,
        -32700,
        'Parse error',
      );
      return;
    }
    try {
      this.validateEnvelope(message);
      if (!Object.hasOwn(message, 'id')) {
        this.receiveNotification(message);
        return;
      }
      const key = outerIdKey(message.id);
      if (this.active.has(key)) {
        throw new McpRequestError(
          -32600,
          'A request with this ID is already active',
        );
      }
      const state = {
        cancelled: false,
        method: message.method,
        connectionClosed: false,
      };
      this.active.set(key, state);
      try {
        const result = await this.dispatchRequest(message);
        if (!state.cancelled) {
          this.write({
            jsonrpc: '2.0',
            id: message.id,
            result,
          });
        }
      } catch (error) {
        if (!state.cancelled) {
          if (error instanceof McpRequestError) {
            this.writeError(
              message.id,
              error.code,
              error.message,
              error.data,
            );
          } else {
            this.writeError(
              message.id,
              -32603,
              'Internal error',
            );
          }
        }
      } finally {
        this.active.delete(key);
      }
    } catch (error) {
      if (Object.hasOwn(message, 'id') && validOuterId(message.id)) {
        this.writeError(
          message.id,
          Number.isInteger(error.code)
            ? error.code
            : -32600,
          error.message,
          error.data,
        );
      } else {
        this.diagnostic.write(`cf7-agent-mcp: ${error.message}\n`);
      }
    }
  }

  validateEnvelope(message) {
    if (!isObject(message) || Array.isArray(message)) {
      throw new McpRequestError(-32600, 'Request must be one object');
    }
    const notification = !Object.hasOwn(message, 'id');
    exactObject(
      message,
      notification
        ? (
          Object.hasOwn(message, 'params')
            ? ['jsonrpc', 'method', 'params']
            : ['jsonrpc', 'method']
        )
        : (
          Object.hasOwn(message, 'params')
            ? ['jsonrpc', 'id', 'method', 'params']
            : ['jsonrpc', 'id', 'method']
        ),
      '$',
    );
    if (message.jsonrpc !== '2.0') {
      throw new McpRequestError(-32600, 'jsonrpc must equal 2.0');
    }
    if (typeof message.method !== 'string' || message.method === '') {
      throw new McpRequestError(-32600, 'method must be a string');
    }
    if (!notification && !validOuterId(message.id)) {
      throw new McpRequestError(
        -32600,
        'MCP ID must be a string or JSON safe integer',
      );
    }
    if (
      Object.hasOwn(message, 'params')
      && !isObject(message.params)
    ) {
      throw new McpRequestError(-32602, 'params must be an object');
    }
  }

  receiveNotification(message) {
    if (message.method === 'notifications/initialized') {
      if (
        !this.initializeResponded
        || this.receivedInitializedNotification
        ||
        Object.hasOwn(message, 'params')
        && Object.keys(message.params).length !== 0
      ) {
        throw new McpRequestError(
          -32602,
          'notifications/initialized params must be empty',
        );
      }
      this.receivedInitializedNotification = true;
      return;
    }
    if (message.method === 'notifications/cancelled') {
      if (!this.receivedInitializedNotification) {
        throw new McpRequestError(
          -32600,
          'Cancellation is unavailable before initialization',
        );
      }
      exactObject(
        message.params,
        Object.hasOwn(message.params ?? {}, 'reason')
          ? ['requestId', 'reason']
          : ['requestId'],
        '$.params',
      );
      if (!validOuterId(message.params.requestId)) {
        throw new McpRequestError(
          -32602,
          'Cancellation requestId is invalid',
        );
      }
      if (
        Object.hasOwn(message.params, 'reason')
        && (
          typeof message.params.reason !== 'string'
          || message.params.reason.length > 512
        )
      ) {
        throw new McpRequestError(
          -32602,
          'Cancellation reason must be a string',
        );
      }
      const active = this.active.get(
        outerIdKey(message.params.requestId),
      );
      if (active) {
        active.cancelled = true;
        if (
          active.method === 'tools/call'
          && !active.connectionClosed
        ) {
          active.connectionClosed = true;
          this.client.close();
        }
      }
      return;
    }
    throw new McpRequestError(
      -32601,
      'Only initialized and cancelled notifications are accepted',
    );
  }

  async dispatchRequest(message) {
    if (message.method === 'initialize') {
      if (this.initializeResponded) {
        throw new McpRequestError(
          -32600,
          'initialize may be called only once',
        );
      }
      const params = message.params;
      if (
        !isObject(params)
        || !sameKeys(
          params,
          ['protocolVersion', 'capabilities', 'clientInfo'],
        )
        || params.protocolVersion !== MCP_PROTOCOL_VERSION
        || !isObject(params.capabilities)
        || !isObject(params.clientInfo)
        || !validClientCapabilities(params.capabilities)
        || !validImplementation(params.clientInfo)
      ) {
        throw new McpRequestError(
          -32602,
          'initialize params are incomplete',
        );
      }
      this.initializeResponded = true;
      return {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: {
          tools: {
            listChanged: false,
          },
        },
        serverInfo: {
          name: 'cf7-agent-runtime',
          version: '1.0.0',
        },
        instructions:
          'Tools map directly to the closed CF7 Agent Runtime v1 method registry.',
      };
    }
    if (!this.receivedInitializedNotification) {
      throw new McpRequestError(
        -32002,
        'MCP adapter is not initialized',
      );
    }
    if (message.method === 'tools/list') {
      const params = message.params ?? {};
      if (Object.keys(params).length !== 0) {
        throw new McpRequestError(
          -32602,
          'This bounded tools/list has no pagination params',
        );
      }
      return {
        tools: this.toolDefinitions(),
      };
    }
    if (message.method === 'tools/call') {
      exactObject(
        message.params,
        ['name', 'arguments'],
        '$.params',
      );
      if (
        typeof message.params.name !== 'string'
        || !isObject(message.params.arguments)
      ) {
        throw new McpRequestError(
          -32602,
          'tools/call requires name and object arguments',
        );
      }
      return this.callTool(
        message.params.name,
        message.params.arguments,
      );
    }
    throw new McpRequestError(-32601, 'Method not found');
  }

  toolDefinitions() {
    const granted = this.client.grantedCapabilities;
    return [...methods.values()]
      .filter((definition) => (
        !definition.preAuthentication
        && granted.has(definition.requiredCapability)
      ))
      .map((definition) => ({
        name: definition.name,
        description:
          `CF7 Agent Runtime v1 method; requires ${definition.requiredCapability}.`,
        inputSchema: methodInputSchema(definition.name),
      }));
  }

  async callTool(name, args) {
    const definition = methods.get(name);
    if (
      !definition
      || definition.preAuthentication
      || !this.client.grantedCapabilities.has(
        definition.requiredCapability,
      )
    ) {
      throw new McpRequestError(-32602, 'Unknown or ungranted tool');
    }
    try {
      if (name === 'content.read') {
        validateContentRead(args);
        const chunk = await this.client.readContentChunk(
          args.handle,
          args.offset,
          args.count,
        );
        return toolText({
          result: chunk.result,
          metadata: chunk.metadata,
          contentBase64: chunk.content.toString('base64'),
        });
      }
      return toolText(await this.client.call(name, args));
    } catch (error) {
      const detail = error instanceof AgentRpcError
        ? {
          code: error.code,
          message: error.message,
          data: error.data,
        }
        : {
          code: error.code ?? 'client_error',
          message: 'Tool execution failed',
        };
      return {
        isError: true,
        content: [{
          type: 'text',
          text: JSON.stringify(detail),
        }],
      };
    }
  }

  writeError(id, code, message, data) {
    const error = { code, message };
    if (data !== undefined) error.data = data;
    this.write({
      jsonrpc: '2.0',
      id,
      error,
    });
  }

  write(message) {
    this.output.write(`${JSON.stringify(message)}\n`);
  }
}

class McpRequestError extends Error {
  constructor(code, message, data) {
    super(message);
    this.name = 'McpRequestError';
    this.code = code;
    this.data = data;
  }
}

function sameKeys(value, expected) {
  return Object.keys(value).sort().join('\u001f')
    === [...expected].sort().join('\u001f');
}

function validClientCapabilities(capabilities) {
  for (const [name, value] of Object.entries(capabilities)) {
    if (!isObject(value)) return false;
    if (name === 'roots') {
      if (
        !Object.keys(value).every((key) => key === 'listChanged')
        || (
          Object.hasOwn(value, 'listChanged')
          && typeof value.listChanged !== 'boolean'
        )
      ) {
        return false;
      }
    }
  }
  return true;
}

function validImplementation(clientInfo) {
  if (
    !sameKeys(clientInfo, ['name', 'version'])
    && !sameKeys(clientInfo, ['name', 'title', 'version'])
  ) {
    return false;
  }
  return boundedString(clientInfo.name, 128)
    && boundedString(clientInfo.version, 64)
    && (
      !Object.hasOwn(clientInfo, 'title')
      || boundedString(clientInfo.title, 128)
    );
}

function boundedString(value, maximumLength) {
  return typeof value === 'string'
    && value.trim() !== ''
    && value.length <= maximumLength;
}

function validOuterId(value) {
  return (
    (
      typeof value === 'string'
      && value.length >= 1
      && value.length <= 128
      && !/[\u0000-\u001f\u007f]/u.test(value)
    )
    || Number.isSafeInteger(value)
  );
}

function outerIdKey(value) {
  return `${typeof value === 'number' ? 'n' : 's'}:${value}`;
}

function toolText(value) {
  return {
    content: [{
      type: 'text',
      text: JSON.stringify(value),
    }],
  };
}

async function runMcp(options) {
  const input = options.input ?? process.stdin;
  const output = options.output ?? process.stdout;
  const diagnostic = options.diagnostic ?? process.stderr;
  const client = options.client ?? await (
    options.createClient ?? AgentClient.connect
  )({
    ...options.clientOptions,
    clientKind: 'mcp_stdio',
  });
  const adapter = new McpAdapter(client, output, diagnostic);
  const lines = readline.createInterface({
    input,
    crlfDelay: Infinity,
    terminal: false,
  });
  const activeReceives = new Set();
  try {
    for await (const line of lines) {
      if (line.trim() === '') continue;
      const receive = adapter.receive(line).finally(
        () => activeReceives.delete(receive),
      );
      activeReceives.add(receive);
    }
    await Promise.allSettled([...activeReceives]);
  } finally {
    lines.close();
    if (!options.keepClientOpen) client.close();
  }
}

async function main() {
  try {
    const clientOptions = parseAdapterOptions(
      process.argv.slice(2),
    );
    await runMcp({ clientOptions });
  } catch (error) {
    process.stderr.write(`cf7-agent-mcp: ${error.message}\n`);
    process.exitCode = 1;
  }
}

if (require.main === module) {
  void main();
}

module.exports = {
  MCP_PROTOCOL_VERSION,
  McpAdapter,
  McpRequestError,
  outerIdKey,
  runMcp,
  toolText,
  validOuterId,
};
