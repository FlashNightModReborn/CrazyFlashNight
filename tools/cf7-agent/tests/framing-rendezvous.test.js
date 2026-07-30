'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const {
  FrameReader,
  JSON_RPC_KIND,
  decodeJsonPayload,
  encodeJsonFrame,
} = require('../lib/framing');
const {
  readRendezvous,
  utcTimestampToDotNetTicks,
  validateRendezvousDocument,
} = require('../lib/rendezvous');

test('CF7A reader handles fragmentation and multiple frames', () => {
  const message = {
    jsonrpc: '2.0',
    id: 'one',
    method: 'session.status',
    params: {},
  };
  const encoded = encodeJsonFrame(message);
  const reader = new FrameReader();
  assert.deepEqual(reader.push(encoded.subarray(0, 5)), []);
  assert.deepEqual(reader.push(encoded.subarray(5, 12)), []);
  const frames = reader.push(Buffer.concat([
    encoded.subarray(12),
    encoded,
  ]));
  assert.equal(frames.length, 2);
  assert.equal(frames[0].kind, JSON_RPC_KIND);
  assert.equal(
    JSON.stringify(
      decodeJsonPayload(frames[0].payload, 'request'),
    ),
    JSON.stringify(message),
  );
  reader.end();
});

test('CF7A framing failure is fatal and cannot resynchronize', () => {
  const reader = new FrameReader();
  const frame = encodeJsonFrame({
    jsonrpc: '2.0',
    id: 'one',
    method: 'session.status',
    params: {},
  });
  frame[6] = 1;
  assert.throws(() => reader.push(frame), /flags/u);
  assert.throws(() => reader.push(Buffer.alloc(0)), /cannot resynchronize/u);
});

test('rendezvous exact lifecycle, ticket, and PID/start identity validate', () => {
  const start = '2026-07-30T00:00:00.1234567Z';
  const now = Date.parse('2026-07-30T00:00:10Z');
  const document = {
    protocolMinMajor: 1,
    protocolMaxMajor: 1,
    pipeId: 'AAAAAAAAAAAAAAAAAAAAAA',
    launcherProcessId: 1234,
    launcherStartTimeUtc: start,
    lifecycleId: 'BBBBBBBBBBBBBBBBBBBBBB',
    runtimeQualificationState: 'unqualified_dev',
    ticketExpiresUtc: '2026-07-30T00:00:20Z',
    connectionTicket: 'CCCCCCCCCCCCCCCCCCCCCC',
  };
  assert.equal(
    utcTimestampToDotNetTicks('1970-01-01T00:00:00Z'),
    621355968000000000n,
  );
  assert.equal(
    validateRendezvousDocument(document, {
      now,
      expectedLifecycleId: document.lifecycleId,
    }),
    document,
  );

  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'cf7-agent-rendezvous-'),
  );
  const filePath = path.join(directory, 'rendezvous.json');
  try {
    fs.writeFileSync(filePath, JSON.stringify(document), 'utf8');
    const read = readRendezvous({
      path: filePath,
      now,
      expectedLifecycleId: document.lifecycleId,
      processProbe: (processId) => {
        assert.equal(processId, document.launcherProcessId);
        return utcTimestampToDotNetTicks(start);
      },
    });
    assert.equal(read.pipeId, document.pipeId);
    assert.equal(read.lifecycleId, document.lifecycleId);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('rendezvous rejects stale lifecycle and overlong ticket', () => {
  const document = {
    protocolMinMajor: 1,
    protocolMaxMajor: 1,
    pipeId: 'AAAAAAAAAAAAAAAAAAAAAA',
    launcherProcessId: 1,
    launcherStartTimeUtc: '2026-07-30T00:00:00Z',
    lifecycleId: 'BBBBBBBBBBBBBBBBBBBBBB',
    runtimeQualificationState: 'formal_runtime',
    ticketExpiresUtc: '2026-07-30T00:00:31Z',
    connectionTicket: 'CCCCCCCCCCCCCCCCCCCCCC',
  };
  assert.throws(
    () => validateRendezvousDocument(document, {
      now: Date.parse('2026-07-30T00:00:00Z'),
      expectedLifecycleId: 'DDDDDDDDDDDDDDDDDDDDDD',
    }),
    /30 second TTL|lifecycle/u,
  );
});
