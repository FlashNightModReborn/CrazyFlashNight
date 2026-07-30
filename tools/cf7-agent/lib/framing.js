'use strict';

const { TextDecoder } = require('node:util');
const {
  MAX_BINARY_FRAME_BYTES,
  MAX_JSON_FRAME_BYTES,
  PROTOCOL_MAJOR,
  validateRequest,
  validateResponse,
} = require('./contract');
const { parseStrictJson } = require('./strict-json');

const MAGIC = Buffer.from('CF7A', 'ascii');
const HEADER_BYTES = 12;
const JSON_RPC_KIND = 1;
const BINARY_CHUNK_KIND = 2;
const SUPPORTED_FLAGS = 0;
const strictUtf8 = new TextDecoder('utf-8', { fatal: true });

class FrameError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'FrameError';
    this.code = code;
  }
}

function maximumForKind(kind) {
  if (kind === JSON_RPC_KIND) return MAX_JSON_FRAME_BYTES;
  if (kind === BINARY_CHUNK_KIND) return MAX_BINARY_FRAME_BYTES;
  throw new FrameError('unsupported_kind', 'Unsupported CF7A frame kind');
}

function encodeFrame(kind, payload) {
  const body = Buffer.isBuffer(payload)
    ? payload
    : Buffer.from(payload);
  const maximum = maximumForKind(kind);
  if (body.length > maximum) {
    throw new FrameError(
      'payload_too_large',
      'CF7A frame payload exceeds its kind limit',
    );
  }
  const frame = Buffer.allocUnsafe(HEADER_BYTES + body.length);
  MAGIC.copy(frame, 0);
  frame[4] = PROTOCOL_MAJOR;
  frame[5] = kind;
  frame.writeUInt16LE(SUPPORTED_FLAGS, 6);
  frame.writeUInt32LE(body.length, 8);
  body.copy(frame, HEADER_BYTES);
  return frame;
}

function encodeJsonFrame(message) {
  const text = JSON.stringify(message);
  const payload = Buffer.from(text, 'utf8');
  if (payload.length === 0) {
    throw new FrameError('invalid_json', 'JSON payload cannot be empty');
  }
  return encodeFrame(JSON_RPC_KIND, payload);
}

function decodeJsonPayload(payload, direction = 'response') {
  let text;
  try {
    text = strictUtf8.decode(payload);
  } catch {
    throw new FrameError('invalid_utf8', 'JSON frame is not strict UTF-8');
  }
  let value;
  try {
    value = parseStrictJson(text, { maximumDepth: 64 });
  } catch (error) {
    throw new FrameError('invalid_json', error.message);
  }
  if (direction === 'request') {
    validateRequest(value);
  } else if (direction === 'response') {
    validateResponse(value);
  }
  return value;
}

class FrameReader {
  constructor() {
    this.buffer = Buffer.alloc(0);
    this.failed = false;
  }

  push(chunk) {
    if (this.failed) {
      throw new FrameError(
        'reader_failed',
        'A failed frame reader cannot resynchronize',
      );
    }
    try {
      const incoming = Buffer.from(chunk);
      this.buffer = this.buffer.length === 0
        ? incoming
        : Buffer.concat([this.buffer, incoming]);
      const frames = [];
      while (this.buffer.length >= HEADER_BYTES) {
        if (!this.buffer.subarray(0, 4).equals(MAGIC)) {
          throw new FrameError('invalid_magic', 'Invalid CF7A magic');
        }
        if (this.buffer[4] !== PROTOCOL_MAJOR) {
          throw new FrameError(
            'unsupported_protocol',
            'Unsupported CF7A protocol major',
          );
        }
        const kind = this.buffer[5];
        const maximum = maximumForKind(kind);
        if (this.buffer.readUInt16LE(6) !== SUPPORTED_FLAGS) {
          throw new FrameError(
            'unsupported_flags',
            'Unsupported CF7A flags',
          );
        }
        const length = this.buffer.readUInt32LE(8);
        if (length > maximum) {
          throw new FrameError(
            'payload_too_large',
            'Declared CF7A payload exceeds its kind limit',
          );
        }
        const frameLength = HEADER_BYTES + length;
        if (this.buffer.length < frameLength) break;
        frames.push({
          kind,
          flags: SUPPORTED_FLAGS,
          payload: Buffer.from(
            this.buffer.subarray(HEADER_BYTES, frameLength),
          ),
        });
        this.buffer = this.buffer.subarray(frameLength);
      }
      return frames;
    } catch (error) {
      this.failed = true;
      this.buffer = Buffer.alloc(0);
      throw error;
    }
  }

  end() {
    if (this.buffer.length !== 0) {
      this.failed = true;
      this.buffer = Buffer.alloc(0);
      throw new FrameError(
        'truncated_frame',
        'CF7A stream ended with a truncated frame',
      );
    }
  }
}

module.exports = {
  BINARY_CHUNK_KIND,
  FrameError,
  FrameReader,
  HEADER_BYTES,
  JSON_RPC_KIND,
  decodeJsonPayload,
  encodeFrame,
  encodeJsonFrame,
};
