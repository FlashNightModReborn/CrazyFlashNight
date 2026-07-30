'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const net = require('node:net');
const { Readable, Writable } = require('node:stream');
const test = require('node:test');
const { runCli } = require('../cli');
const {
  AgentClient,
  AgentRpcError,
} = require('../lib/client');
const {
  encodeBinaryPayload,
} = require('../lib/contract');
const {
  BINARY_CHUNK_KIND,
  FrameReader,
  decodeJsonPayload,
  encodeFrame,
  encodeJsonFrame,
} = require('../lib/framing');
const {
  McpAdapter,
} = require('../mcp');

test('shared client performs hello, RPC, and bound binary content read', async (t) => {
  const observedRequests = [];
  const content = Buffer.from('abc', 'utf8');
  const contentHash = crypto
    .createHash('sha256')
    .update(content)
    .digest('hex');
  const server = net.createServer((socket) => {
    const reader = new FrameReader();
    socket.on('data', (chunk) => {
      for (const frame of reader.push(chunk)) {
        const request = decodeJsonPayload(frame.payload, 'request');
        observedRequests.push(request);
        if (request.method === 'runtime.hello') {
          socket.write(encodeJsonFrame({
            jsonrpc: '2.0',
            id: request.id,
            result: {
              serverInstanceId: 'SSSSSSSSSSSSSSSSSSSSSS',
              protocolVersion: '1.0',
              securityPrincipalId: 'PPPPPPPPPPPPPPPPPPPPPP',
              minimalSessionRef: {
                projectRunning: false,
                qualificationState: 'unqualified',
              },
              grantedCapabilities:
                request.params.requestedCapabilities,
              limits: {
                maximumJsonFrameBytes: 1_048_576,
                maximumBinaryChunkBytes: 4_194_304,
                maximumBinaryObjectBytes: 16_777_216,
                maximumConcurrentRequests: 4,
                maximumQueueDepth: 16,
                maximumRequestsPerMinute: 120,
                maximumActionDeadlineMs: 30_000,
                maximumContentHandleTtlMs: 15_000,
                maximumTargetScopeItems: 32,
              },
              serverSequence: 1,
            },
          }));
        } else if (request.method === 'session.status') {
          socket.write(encodeJsonFrame({
            jsonrpc: '2.0',
            id: request.id,
            result: { running: true },
          }));
        } else if (request.method === 'content.read') {
          const metadata = {
            handle: request.params.handle,
            offset: request.params.offset,
            totalLength: content.length,
            final: true,
            contentHash,
          };
          socket.write(Buffer.concat([
            encodeJsonFrame({
              jsonrpc: '2.0',
              id: request.id,
              result: { accepted: true },
            }),
            encodeFrame(
              BINARY_CHUNK_KIND,
              encodeBinaryPayload(metadata, content),
            ),
          ]));
        }
      }
    });
  });
  await new Promise((resolve) => {
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  const client = await AgentClient.connect({
    rendezvous: {
      pipeId: 'AAAAAAAAAAAAAAAAAAAAAA',
      connectionTicket: 'TTTTTTTTTTTTTTTTTTTTTT',
    },
    requestedCapabilities: ['session.status', 'content.read'],
    clientKind: 'test_harness',
    clientInstanceId: 'IIIIIIIIIIIIIIIIIIIIII',
    credentialProof: 'X'.repeat(32),
    connectionFactory: () => new Promise((resolve, reject) => {
      const socket = net.createConnection(
        address.port,
        '127.0.0.1',
      );
      socket.once('connect', () => resolve(socket));
      socket.once('error', reject);
    }),
  });
  t.after(async () => {
    client.close();
    await new Promise((resolve) => server.close(resolve));
  });
  assert.equal(
    JSON.stringify(await client.call('session.status', {})),
    '{"running":true}',
  );
  const complete = await client.readContent(
    'HHHHHHHHHHHHHHHHHHHHHH',
  );
  assert.deepEqual(complete, content);
  assert.equal(
    observedRequests.every(
      (request) => typeof request.id === 'string',
    ),
    true,
  );
  assert.deepEqual(
    observedRequests.map((request) => request.method),
    ['runtime.hello', 'session.status', 'content.read'],
  );
});

test('shared client closes the pipe when Welcome validation fails', async (t) => {
  let acceptedSocket = null;
  let resolveSocketClosed;
  const socketClosed = new Promise((resolve) => {
    resolveSocketClosed = resolve;
  });
  const server = net.createServer((socket) => {
    acceptedSocket = socket;
    socket.once('close', resolveSocketClosed);
    const reader = new FrameReader();
    socket.on('data', (chunk) => {
      for (const frame of reader.push(chunk)) {
        const request = decodeJsonPayload(frame.payload, 'request');
        socket.write(encodeJsonFrame({
          jsonrpc: '2.0',
          id: request.id,
          result: {
            serverInstanceId: 'SSSSSSSSSSSSSSSSSSSSSS',
            protocolVersion: '1.0',
            securityPrincipalId: 'PPPPPPPPPPPPPPPPPPPPPP',
            minimalSessionRef: {
              projectRunning: false,
              qualificationState: 'unqualified',
            },
            grantedCapabilities: [
              'session.status',
              'input.click',
            ],
            limits: {
              maximumJsonFrameBytes: 1_048_576,
              maximumBinaryChunkBytes: 4_194_304,
              maximumBinaryObjectBytes: 16_777_216,
              maximumConcurrentRequests: 4,
              maximumQueueDepth: 16,
              maximumRequestsPerMinute: 120,
              maximumActionDeadlineMs: 30_000,
              maximumContentHandleTtlMs: 15_000,
              maximumTargetScopeItems: 32,
            },
            serverSequence: 1,
          },
        }));
      }
    });
  });
  await new Promise((resolve) => {
    server.listen(0, '127.0.0.1', resolve);
  });
  t.after(async () => {
    acceptedSocket?.destroy();
    await new Promise((resolve) => server.close(resolve));
  });
  const address = server.address();

  await assert.rejects(
    AgentClient.connect({
      rendezvous: {
        pipeId: 'AAAAAAAAAAAAAAAAAAAAAA',
        connectionTicket: 'TTTTTTTTTTTTTTTTTTTTTT',
      },
      requestedCapabilities: ['session.status'],
      clientKind: 'test_harness',
      clientInstanceId: 'IIIIIIIIIIIIIIIIIIIIII',
      credentialProof: 'X'.repeat(32),
      connectionFactory: () => new Promise((resolve, reject) => {
        const socket = net.createConnection(
          address.port,
          '127.0.0.1',
        );
        socket.once('connect', () => resolve(socket));
        socket.once('error', reject);
      }),
    }),
    (error) => error?.code === 'welcome_capabilities_invalid',
  );

  await socketClosed;
});

test('JSONL CLI preserves outer IDs and emits only protocol lines', async () => {
  const output = collector();
  const diagnostic = collector();
  const calls = [];
  const client = {
    async call(method, params) {
      calls.push({ method, params });
      if (calls.length === 2) {
        throw new AgentRpcError({
          code: -32029,
          message: 'Rate limited',
          data: {
            reasonCode: 'rate_limited',
            retryable: true,
            reconcileKind: 'none',
            serverSequence: 4,
          },
        });
      }
      return { ok: true };
    },
    close() {},
  };
  const input = Readable.from([
    '{"jsonrpc":"2.0","id":"outer-1",'
    + '"method":"session.status","params":{}}\n',
    '{"jsonrpc":"2.0","id":"outer-2",'
    + '"method":"session.status","params":{}}\n',
  ]);
  const exitCode = await runCli({
    input,
    output: output.stream,
    diagnostic: diagnostic.stream,
    client,
  });
  assert.equal(exitCode, 0);
  assert.equal(diagnostic.text(), '');
  const messages = output.text().trim().split('\n').map(JSON.parse);
  assert.equal(messages.length, 2);
  assert.equal(messages[0].id, 'outer-1');
  assert.deepEqual(messages[0].result, { ok: true });
  assert.equal(messages[1].id, 'outer-2');
  assert.equal(messages[1].error.data.serverSequence, 4);
  assert.deepEqual(
    calls.map((call) => call.method),
    ['session.status', 'session.status'],
  );
});

test('JSONL content.read returns one bounded base64 protocol result', async () => {
  const output = collector();
  const diagnostic = collector();
  const content = Buffer.from('bounded pixels', 'utf8');
  const contentHash = crypto
    .createHash('sha256')
    .update(content)
    .digest('hex');
  let closeCount = 0;
  const client = {
    async call() {
      throw new Error('content.read must use the binary-aware client path');
    },
    async readContentChunk(handle, offset, count) {
      assert.equal(handle, 'HHHHHHHHHHHHHHHHHHHHHH');
      assert.equal(offset, 0);
      assert.equal(count, 4096);
      return {
        result: {
          handle,
          offset,
          totalLength: content.length,
          returnedBytes: content.length,
          final: true,
          contentHash,
        },
        metadata: {
          handle,
          offset,
          totalLength: content.length,
          final: true,
          contentHash,
        },
        content,
      };
    },
    close() {
      closeCount++;
    },
  };
  const input = Readable.from([
    '{"jsonrpc":"2.0","id":"content-1",'
    + '"method":"content.read","params":{'
    + '"handle":"HHHHHHHHHHHHHHHHHHHHHH",'
    + '"offset":0,"count":4096}}\n',
  ]);

  const exitCode = await runCli({
    input,
    output: output.stream,
    diagnostic: diagnostic.stream,
    client,
  });

  assert.equal(exitCode, 0);
  assert.equal(diagnostic.text(), '');
  assert.equal(closeCount, 1);
  assert.equal(output.text().endsWith('\n'), true);
  assert.equal(output.text().trim().split('\n').length, 1);
  const response = JSON.parse(output.text());
  assert.equal(response.id, 'content-1');
  assert.deepEqual(response.result.result, {
    handle: 'HHHHHHHHHHHHHHHHHHHHHH',
    offset: 0,
    totalLength: content.length,
    returnedBytes: content.length,
    final: true,
    contentHash,
  });
  assert.deepEqual(response.result.metadata, {
    handle: 'HHHHHHHHHHHHHHHHHHHHHH',
    offset: 0,
    totalLength: content.length,
    final: true,
    contentHash,
  });
  assert.equal(
    response.result.contentBase64,
    content.toString('base64'),
  );
});

test('JSONL bootstraps lifecycleRef then first grant by target kind', async () => {
  const output = collector();
  const diagnostic = collector();
  const calls = [];
  const lifecycleRef = 'LLLLLLLLLLLLLLLLLLLLLL';
  const client = {
    async call(method, params) {
      calls.push({ method, params });
      if (method === 'session.status') {
        return {
          projectRunning: true,
          qualificationState: 'verified',
          lifecycleRef,
        };
      }
      return grantDescriptor();
    },
    close() {},
  };
  const input = Readable.from([
    '{"jsonrpc":"2.0","id":"status",'
    + '"method":"session.status","params":{}}\n',
    JSON.stringify({
      jsonrpc: '2.0',
      id: 'first-grant',
      method: 'observation.grant.issue',
      params: firstGrantParams(lifecycleRef),
    }) + '\n',
  ]);

  const exitCode = await runCli({
    input,
    output: output.stream,
    diagnostic: diagnostic.stream,
    client,
  });

  assert.equal(exitCode, 0);
  assert.equal(diagnostic.text(), '');
  const messages = output.text().trim().split('\n').map(JSON.parse);
  assert.equal(messages[0].result.lifecycleRef, lifecycleRef);
  assert.equal(
    messages[1].result.sessionScope.sessionId,
    'QQQQQQQQQQQQQQQQQQQQQQ',
  );
  assert.deepEqual(
    calls.map(({ method }) => method),
    ['session.status', 'observation.grant.issue'],
  );
  assert.deepEqual(
    calls[1].params.targetKinds,
    ['flash'],
  );
  assert.equal(
    Object.hasOwn(calls[1].params, 'sessionId'),
    false,
  );
  assert.equal(
    Object.hasOwn(calls[1].params, 'targetIds'),
    false,
  );
});

test('MCP accepts outer numeric IDs but maps only registered tools', async () => {
  const output = collector();
  const diagnostic = collector();
  const calls = [];
  let rejectHeld;
  let heldCallCompleted = false;
  let closeCount = 0;
  const held = new Promise((resolve, reject) => {
    rejectHeld = reject;
  });
  const client = {
    grantedCapabilities: new Set(['session.status']),
    async call(method, params) {
      calls.push({ method, params });
      if (params.hold) {
        await held;
        heldCallCompleted = true;
      }
      return { running: true };
    },
    close() {
      closeCount++;
      rejectHeld(new Error('client_closed'));
    },
  };
  const adapter = new McpAdapter(
    client,
    output.stream,
    diagnostic.stream,
  );
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 1,
    method: 'initialize',
    params: {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: {
        name: 'test',
        version: '1',
      },
    },
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    method: 'notifications/initialized',
    params: {},
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 'list',
    method: 'tools/list',
    params: {},
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 2,
    method: 'tools/call',
    params: {
      name: 'session.status',
      arguments: {},
    },
  }));

  const pending = adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 3,
    method: 'tools/call',
    params: {
      name: 'session.status',
      arguments: { hold: true },
    },
  }));
  await new Promise((resolve) => setImmediate(resolve));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    method: 'notifications/cancelled',
    params: {
      requestId: 3,
      reason: 'test cancellation',
    },
  }));
  await pending;

  const messages = output.text().trim().split('\n').map(JSON.parse);
  assert.equal(messages[0].id, 1);
  assert.equal(messages[0].result.protocolVersion, '2025-06-18');
  assert.equal(messages[1].id, 'list');
  assert.deepEqual(
    messages[1].result.tools.map((tool) => tool.name),
    ['session.status'],
  );
  assert.equal(
    messages[1].result.tools[0].inputSchema.additionalProperties,
    false,
  );
  assert.deepEqual(
    messages[1].result.tools[0].inputSchema.required,
    undefined,
  );
  assert.equal(
    messages[1].result.tools[0].inputSchema.maxProperties,
    0,
  );
  assert.equal(messages[2].id, 2);
  assert.equal(
    messages.some((message) => message.id === 3),
    false,
  );
  assert.deepEqual(
    calls.map((call) => call.method),
    ['session.status', 'session.status'],
  );
  assert.equal(closeCount, 1);
  assert.equal(heldCallCompleted, false);
  assert.equal(diagnostic.text(), '');
});

test('MCP bootstraps lifecycleRef then first grant by target kind', async () => {
  const output = collector();
  const diagnostic = collector();
  const calls = [];
  const lifecycleRef = 'LLLLLLLLLLLLLLLLLLLLLL';
  const client = {
    grantedCapabilities: new Set([
      'session.status',
      'observation.grant.manage',
    ]),
    async call(method, params) {
      calls.push({ method, params });
      return method === 'session.status'
        ? {
          projectRunning: true,
          qualificationState: 'verified',
          lifecycleRef,
        }
        : grantDescriptor();
    },
  };
  const adapter = new McpAdapter(
    client,
    output.stream,
    diagnostic.stream,
  );
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 1,
    method: 'initialize',
    params: {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: {
        name: 'bootstrap-test',
        version: '1',
      },
    },
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    method: 'notifications/initialized',
    params: {},
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 2,
    method: 'tools/call',
    params: {
      name: 'session.status',
      arguments: {},
    },
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 3,
    method: 'tools/call',
    params: {
      name: 'observation.grant.issue',
      arguments: firstGrantParams(lifecycleRef),
    },
  }));

  const messages = output.text().trim().split('\n').map(JSON.parse);
  const statusContent = JSON.parse(
    messages[1].result.content[0].text,
  );
  const grantContent = JSON.parse(
    messages[2].result.content[0].text,
  );
  assert.equal(statusContent.lifecycleRef, lifecycleRef);
  assert.equal(
    grantContent.sessionScope.sessionId,
    'QQQQQQQQQQQQQQQQQQQQQQ',
  );
  assert.deepEqual(
    calls.map(({ method }) => method),
    ['session.status', 'observation.grant.issue'],
  );
  assert.deepEqual(calls[1].params.targetKinds, ['flash']);
  assert.equal(
    Object.hasOwn(calls[1].params, 'sessionId'),
    false,
  );
  assert.equal(diagnostic.text(), '');
});

test('MCP enforces 2025-06-18 two-phase initialization without leaks', async () => {
  const output = collector();
  const diagnostic = collector();
  const client = {
    grantedCapabilities: new Set(['session.status']),
    async call() {
      throw new Error('C:\\secret\\internal-path');
    },
    close() {},
  };
  const adapter = new McpAdapter(
    client,
    output.stream,
    diagnostic.stream,
  );
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 'wrong-version',
    method: 'initialize',
    params: {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: {
        name: 'test',
        version: '1',
      },
    },
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 'initialize',
    method: 'initialize',
    params: {
      protocolVersion: '2025-06-18',
      capabilities: {
        vendorExtension: {},
      },
      clientInfo: {
        name: 'test',
        version: '1',
      },
    },
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 'before-notification',
    method: 'tools/list',
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    method: 'notifications/initialized',
    params: {},
  }));
  await adapter.receive(JSON.stringify({
    jsonrpc: '2.0',
    id: 'tool-call',
    method: 'tools/call',
    params: {
      name: 'session.status',
      arguments: {},
    },
  }));

  const messages = output.text().trim().split('\n').map(JSON.parse);
  assert.equal(messages[0].error.code, -32602);
  assert.equal(messages[1].result.protocolVersion, '2025-06-18');
  assert.equal(messages[2].error.code, -32002);
  assert.equal(messages[3].result.isError, true);
  assert.equal(
    output.text().includes('C:\\secret\\internal-path'),
    false,
  );
  assert.equal(diagnostic.text(), '');
});

function firstGrantParams(lifecycleRef) {
  return {
    lifecycleRef,
    targetKinds: ['flash'],
    dataScopes: ['window_metadata'],
    requestedTtlMs: 60_000,
    allowEphemeralKeyframes: false,
    allowPersistence: false,
    allowExport: false,
  };
}

function grantDescriptor() {
  return {
    observationGrantId: 'GGGGGGGGGGGGGGGGGGGGGG',
    securityPrincipalId: 'PPPPPPPPPPPPPPPPPPPPPP',
    sessionScope: {
      sessionId: 'QQQQQQQQQQQQQQQQQQQQQQ',
      lifecycleGeneration: 1,
      crossAttempt: false,
    },
    targetScope: [{
      targetId: 'TTTTTTTTTTTTTTTTTTTTTT',
    }],
    dataScopes: ['window_metadata'],
    allowsEphemeralKeyframes: false,
    allowsPersistence: false,
    allowsExport: false,
    issuedMonotonic: 1,
    expiresMonotonic: 60_001,
  };
}

function collector() {
  let content = '';
  return {
    stream: new Writable({
      write(chunk, encoding, callback) {
        content += chunk.toString('utf8');
        callback();
      },
    }),
    text() {
      return content;
    },
  };
}
