'use strict';

const crypto = require('node:crypto');
const net = require('node:net');
const {
  MAX_BINARY_OBJECT_BYTES,
  MAX_BINARY_READ_COUNT,
  PROTOCOL_VERSION,
  capabilities,
  decodeBinaryPayload,
  exactObject,
  isObject,
  methods,
  opaqueId,
  safeInteger,
  validateMethodResult,
  validateRequest,
  validateResponse,
} = require('./contract');
const {
  BINARY_CHUNK_KIND,
  FrameReader,
  JSON_RPC_KIND,
  decodeJsonPayload,
  encodeJsonFrame,
} = require('./framing');
const { readRendezvous } = require('./rendezvous');

const PIPE_PREFIX = '\\\\.\\pipe\\CF7FlashNight.AgentRuntime.v1.';

class AgentRpcError extends Error {
  constructor(errorPayload) {
    super(errorPayload.message);
    this.name = 'AgentRpcError';
    this.code = errorPayload.code;
    this.data = errorPayload.data;
    this.errorPayload = errorPayload;
  }
}

class AgentClientError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'AgentClientError';
    this.code = code;
  }
}

function randomOpaqueId() {
  return crypto.randomBytes(32).toString('base64url');
}

function validateWelcome(
  welcome,
  requestedCapabilities,
) {
  exactObject(welcome, [
    'serverInstanceId',
    'protocolVersion',
    'securityPrincipalId',
    'minimalSessionRef',
    'grantedCapabilities',
    'limits',
    'serverSequence',
  ], '$.result');
  opaqueId(welcome.serverInstanceId, '$.result.serverInstanceId');
  opaqueId(
    welcome.securityPrincipalId,
    '$.result.securityPrincipalId',
  );
  if (welcome.protocolVersion !== PROTOCOL_VERSION) {
    throw new AgentClientError(
      'protocol_version_mismatch',
      'Welcome protocolVersion does not equal 1.0',
    );
  }
  exactObject(
    welcome.minimalSessionRef,
    welcome.minimalSessionRef.projectRunning
      ? ['projectRunning', 'qualificationState', 'lifecycleRef']
      : ['projectRunning', 'qualificationState'],
    '$.result.minimalSessionRef',
  );
  if (
    typeof welcome.minimalSessionRef.projectRunning !== 'boolean'
    || !['verified', 'unqualified'].includes(
      welcome.minimalSessionRef.qualificationState,
    )
  ) {
    throw new AgentClientError(
      'welcome_session_invalid',
      'Welcome minimal session reference is invalid',
    );
  }
  if (welcome.minimalSessionRef.projectRunning) {
    opaqueId(
      welcome.minimalSessionRef.lifecycleRef,
      '$.result.minimalSessionRef.lifecycleRef',
    );
  }
  if (!Array.isArray(welcome.grantedCapabilities)) {
    throw new AgentClientError(
      'welcome_capabilities_invalid',
      'Welcome grantedCapabilities must be an array',
    );
  }
  const requested = new Set(requestedCapabilities);
  const granted = new Set();
  for (const capability of welcome.grantedCapabilities) {
    if (
      typeof capability !== 'string'
      || !capabilities.has(capability)
      || !requested.has(capability)
      || granted.has(capability)
    ) {
      throw new AgentClientError(
        'welcome_capabilities_invalid',
        'Welcome granted an unknown, unrequested, or duplicate capability',
      );
    }
    granted.add(capability);
  }
  exactObject(welcome.limits, [
    'maximumJsonFrameBytes',
    'maximumBinaryChunkBytes',
    'maximumBinaryObjectBytes',
    'maximumConcurrentRequests',
    'maximumQueueDepth',
    'maximumRequestsPerMinute',
    'maximumActionDeadlineMs',
    'maximumContentHandleTtlMs',
    'maximumTargetScopeItems',
  ], '$.result.limits');
  const bounds = {
    maximumJsonFrameBytes: 1_048_576,
    maximumBinaryChunkBytes: 4_194_304,
    maximumBinaryObjectBytes: 16_777_216,
    maximumConcurrentRequests: 4,
    maximumQueueDepth: 16,
    maximumRequestsPerMinute: 120,
    maximumActionDeadlineMs: 30_000,
    maximumContentHandleTtlMs: 15_000,
    maximumTargetScopeItems: 32,
  };
  for (const [name, maximum] of Object.entries(bounds)) {
    safeInteger(
      welcome.limits[name],
      1,
      maximum,
      `$.result.limits.${name}`,
    );
  }
  safeInteger(
    welcome.serverSequence,
    1,
    Number.MAX_SAFE_INTEGER,
    '$.result.serverSequence',
  );
  return Object.freeze({
    ...welcome,
    grantedCapabilities: Object.freeze([...granted]),
  });
}

function defaultConnectionFactory(pipePath) {
  return new Promise((resolve, reject) => {
    const stream = net.createConnection(pipePath);
    const fail = (error) => {
      stream.destroy();
      reject(error);
    };
    stream.once('error', fail);
    stream.once('connect', () => {
      stream.removeListener('error', fail);
      resolve(stream);
    });
  });
}

class AgentClient {
  constructor(options) {
    this.options = { requestTimeoutMs: 30_000, ...options };
    this.stream = null;
    this.reader = new FrameReader();
    this.pending = new Map();
    this.binaryWaiters = new Map();
    this.nextId = 0;
    this.idPrefix = randomOpaqueId().slice(0, 16);
    this.grantedCapabilities = new Set();
    this.welcome = null;
    this.closed = false;
    this.writeChain = Promise.resolve();
  }

  static async connect(options) {
    normalizeClientIdentity(options);
    const requestedCapabilities = normalizeCapabilities(
      options.requestedCapabilities,
    );
    const rendezvous = options.rendezvous
      ?? (options.rendezvousReader ?? readRendezvous)({
        projectRoot: options.projectRoot,
        localAppData: options.localAppData,
        expectedLifecycleId: options.expectedLifecycleId,
        processProbe: options.processProbe,
        now: options.now,
      });
    const client = new AgentClient({
      ...options,
      requestedCapabilities,
      rendezvous,
    });
    try {
      await client.open();
      return client;
    } catch (error) {
      client.close();
      throw error;
    }
  }

  async open() {
    if (this.stream !== null) {
      throw new AgentClientError(
        'already_open',
        'Agent client has already been opened',
      );
    }
    const pipePath = PIPE_PREFIX + this.options.rendezvous.pipeId;
    const factory =
      this.options.connectionFactory ?? defaultConnectionFactory;
    this.stream = await factory(pipePath);
    this.stream.on('data', (chunk) => this.onData(chunk));
    this.stream.on('error', (error) => this.failConnection(error));
    this.stream.on('end', () => {
      try {
        this.reader.end();
        this.failConnection(
          new AgentClientError(
            'connection_closed',
            'Agent pipe closed',
          ),
        );
      } catch (error) {
        this.failConnection(error);
      }
    });
    this.stream.on('close', () => {
      if (!this.closed) {
        this.failConnection(
          new AgentClientError(
            'connection_closed',
            'Agent pipe closed',
          ),
        );
      }
    });

    const hello = {
      protocolVersion: PROTOCOL_VERSION,
      clientInstanceId: this.options.clientInstanceId,
      clientKind: this.options.clientKind,
      requestedCapabilities:
        this.options.requestedCapabilities,
      nonce: randomOpaqueId(),
      connectionToken:
        this.options.rendezvous.connectionTicket,
      credentialProof: this.options.credentialProof,
    };
    const welcome = await this.callInternal(
      'runtime.hello',
      hello,
    );
    this.welcome = validateWelcome(
      welcome,
      this.options.requestedCapabilities,
    );
    this.grantedCapabilities = new Set(
      this.welcome.grantedCapabilities,
    );
  }

  async call(method, params) {
    if (method === 'runtime.hello') {
      throw new AgentClientError(
        'hello_reserved',
        'runtime.hello is owned by the shared client',
      );
    }
    const definition = methods.get(method);
    if (!definition) {
      throw new AgentClientError(
        'rpc_method_not_found',
        'Method is not in the closed v1 registry',
      );
    }
    if (!this.grantedCapabilities.has(
      definition.requiredCapability,
    )) {
      throw new AgentClientError(
        'capability_not_granted',
        `Capability not granted: ${definition.requiredCapability}`,
      );
    }
    return this.callInternal(method, params);
  }

  async readContentChunk(handle, offset, count) {
    const params = { handle, offset, count };
    const key = `${handle}:${offset}`;
    if (this.binaryWaiters.has(key)) {
      throw new AgentClientError(
        'content_read_in_flight',
        'The same content range is already being read',
      );
    }
    let resolveBinary;
    let rejectBinary;
    const binary = new Promise((resolve, reject) => {
      resolveBinary = resolve;
      rejectBinary = reject;
    });
    const timeout = setTimeout(() => {
      const waiter = this.binaryWaiters.get(key);
      if (!waiter) return;
      this.binaryWaiters.delete(key);
      const error = new AgentClientError(
        'binary_chunk_timeout',
        'Timed out waiting for the content.read binary frame',
      );
      waiter.reject(error);
      this.failConnection(error);
    }, this.options.requestTimeoutMs);
    timeout.unref?.();
    this.binaryWaiters.set(key, {
      resolve: resolveBinary,
      reject: rejectBinary,
      count,
      timeout,
    });
    try {
      const result = await this.call('content.read', params);
      const chunk = await binary;
      return { result, ...chunk };
    } catch (error) {
      const waiter = this.binaryWaiters.get(key);
      if (waiter) {
        this.binaryWaiters.delete(key);
        clearTimeout(waiter.timeout);
        waiter.reject(error);
      }
      throw error;
    }
  }

  async readContent(handle, options = {}) {
    opaqueId(handle, '$.handle');
    const requestedCount = Math.min(
      options.count ?? MAX_BINARY_READ_COUNT,
      MAX_BINARY_READ_COUNT,
    );
    safeInteger(
      requestedCount,
      1,
      MAX_BINARY_READ_COUNT,
      '$.count',
    );
    const chunks = [];
    let offset = 0;
    let totalLength = null;
    let contentHash = null;
    while (true) {
      const chunk = await this.readContentChunk(
        handle,
        offset,
        requestedCount,
      );
      const { metadata, content } = chunk;
      if (
        metadata.handle !== handle
        || metadata.offset !== offset
        || content.length > requestedCount
      ) {
        throw new AgentClientError(
          'binary_binding_mismatch',
          'Binary chunk does not match its content.read request',
        );
      }
      if (totalLength === null) {
        totalLength = metadata.totalLength;
        contentHash = metadata.contentHash.toLowerCase();
      } else if (
        totalLength !== metadata.totalLength
        || contentHash !== metadata.contentHash.toLowerCase()
      ) {
        throw new AgentClientError(
          'binary_object_changed',
          'Binary object metadata changed between chunks',
        );
      }
      if (totalLength > MAX_BINARY_OBJECT_BYTES) {
        throw new AgentClientError(
          'binary_object_oversize',
          'Binary object exceeds 16 MiB',
        );
      }
      chunks.push(content);
      offset += content.length;
      if (metadata.final) break;
      if (content.length === 0) {
        throw new AgentClientError(
          'binary_no_progress',
          'Non-final binary read made no progress',
        );
      }
    }
    const complete = Buffer.concat(chunks, offset);
    const actualHash = crypto
      .createHash('sha256')
      .update(complete)
      .digest('hex');
    if (
      complete.length !== totalLength
      || actualHash !== contentHash
    ) {
      throw new AgentClientError(
        'content_hash_mismatch',
        'Assembled binary object failed length or SHA-256 validation',
      );
    }
    return complete;
  }

  async callInternal(method, params) {
    if (this.closed || !this.stream) {
      throw new AgentClientError(
        'connection_closed',
        'Agent client is not connected',
      );
    }
    const id = `${this.idPrefix}-${++this.nextId}`;
    const request = {
      jsonrpc: '2.0',
      id,
      method,
      params,
    };
    validateRequest(request);
    if (
      this.welcome
      && this.pending.size
        >= this.welcome.limits.maximumConcurrentRequests
    ) {
      throw new AgentClientError(
        'client_concurrency_limit',
        'Client concurrent request limit reached',
      );
    }
    const response = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        const error = new AgentClientError(
          'request_timeout',
          `Agent request timed out: ${method}`,
        );
        reject(error);
        this.failConnection(error);
      }, this.options.requestTimeoutMs);
      timeout.unref?.();
      this.pending.set(id, {
        method,
        resolve,
        reject,
        timeout,
      });
    });
    try {
      await this.write(encodeJsonFrame(request));
    } catch (error) {
      const pending = this.pending.get(id);
      if (pending) {
        clearTimeout(pending.timeout);
        this.pending.delete(id);
        pending.reject(error);
      }
    }
    return response;
  }

  write(buffer) {
    this.writeChain = this.writeChain.then(
      () => new Promise((resolve, reject) => {
        if (this.closed || !this.stream) {
          reject(
            new AgentClientError(
              'connection_closed',
              'Agent pipe is closed',
            ),
          );
          return;
        }
        this.stream.write(buffer, (error) => {
          if (error) reject(error);
          else resolve();
        });
      }),
    );
    return this.writeChain;
  }

  onData(chunk) {
    try {
      for (const frame of this.reader.push(chunk)) {
        if (frame.kind === JSON_RPC_KIND) {
          const response = decodeJsonPayload(
            frame.payload,
            'response',
          );
          validateResponse(response);
          const pending = this.pending.get(response.id);
          if (!pending) {
            throw new AgentClientError(
              'unexpected_response',
              `No request is pending for response ${response.id}`,
            );
          }
          if (Object.hasOwn(response, 'result')) {
            validateMethodResult(
              pending.method,
              response.result,
            );
          }
          clearTimeout(pending.timeout);
          this.pending.delete(response.id);
          if (Object.hasOwn(response, 'error')) {
            pending.reject(new AgentRpcError(response.error));
          } else {
            pending.resolve(response.result);
          }
        } else if (frame.kind === BINARY_CHUNK_KIND) {
          const decoded = decodeBinaryPayload(frame.payload);
          const key =
            `${decoded.metadata.handle}:${decoded.metadata.offset}`;
          const waiter = this.binaryWaiters.get(key);
          if (!waiter) {
            throw new AgentClientError(
              'unexpected_binary_chunk',
              'No content.read request is waiting for this binary chunk',
            );
          }
          if (decoded.content.length > waiter.count) {
            throw new AgentClientError(
              'binary_count_exceeded',
              'Binary chunk exceeds the requested count',
            );
          }
          this.binaryWaiters.delete(key);
          clearTimeout(waiter.timeout);
          waiter.resolve(decoded);
        }
      }
    } catch (error) {
      this.failConnection(error);
    }
  }

  failConnection(error) {
    if (this.closed) return;
    this.closed = true;
    this.stream?.destroy();
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timeout);
      pending.reject(error);
    }
    this.pending.clear();
    for (const waiter of this.binaryWaiters.values()) {
      clearTimeout(waiter.timeout);
      waiter.reject(error);
    }
    this.binaryWaiters.clear();
  }

  close() {
    if (this.closed) return;
    this.failConnection(
      new AgentClientError(
        'client_closed',
        'Agent client was closed',
      ),
    );
  }
}

function normalizeClientIdentity(options) {
  try {
    opaqueId(
      options.clientInstanceId,
      '$.clientInstanceId',
    );
  } catch {
    throw new AgentClientError(
      'client_instance_id_required',
      'An explicit opaque clientInstanceId is required',
    );
  }
  if (
    typeof options.credentialProof !== 'string'
    || options.credentialProof.length < 32
    || options.credentialProof.length > 4096
  ) {
    throw new AgentClientError(
      'credential_proof_required',
      'An explicit 32-4096 character credential proof is required',
    );
  }
}

function normalizeCapabilities(requested) {
  if (!Array.isArray(requested) || requested.length === 0) {
    throw new AgentClientError(
      'capabilities_required',
      'At least one explicit requested capability is required',
    );
  }
  const seen = new Set();
  for (const capability of requested) {
    if (
      typeof capability !== 'string'
      || !capabilities.has(capability)
      || seen.has(capability)
    ) {
      throw new AgentClientError(
        'capabilities_invalid',
        'Requested capabilities must be unique registered names',
      );
    }
    seen.add(capability);
  }
  return [...seen];
}

module.exports = {
  AgentClient,
  AgentClientError,
  AgentRpcError,
  PIPE_PREFIX,
  normalizeCapabilities,
  normalizeClientIdentity,
  randomOpaqueId,
  validateWelcome,
};
