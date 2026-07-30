'use strict';

class StrictJsonError extends SyntaxError {
  constructor(message, offset) {
    super(`${message} at offset ${offset}`);
    this.name = 'StrictJsonError';
    this.offset = offset;
  }
}

function parseStrictJson(text, options = {}) {
  if (typeof text !== 'string') {
    throw new TypeError('JSON input must be a string');
  }
  const maximumDepth = options.maximumDepth ?? 64;
  let offset = 0;

  function fail(message) {
    throw new StrictJsonError(message, offset);
  }

  function whitespace() {
    while (
      offset < text.length
      && (
        text[offset] === ' '
        || text[offset] === '\t'
        || text[offset] === '\r'
        || text[offset] === '\n'
      )
    ) {
      offset += 1;
    }
  }

  function string() {
    const start = offset;
    offset += 1;
    let escaped = false;
    while (offset < text.length) {
      const code = text.charCodeAt(offset);
      if (!escaped && code === 0x22) {
        offset += 1;
        try {
          return JSON.parse(text.slice(start, offset));
        } catch {
          fail('Invalid JSON string');
        }
      }
      if (!escaped && code < 0x20) {
        fail('Unescaped control character');
      }
      if (!escaped && code === 0x5c) {
        escaped = true;
      } else {
        escaped = false;
      }
      offset += 1;
    }
    fail('Unterminated JSON string');
  }

  function number() {
    const match = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/
      .exec(text.slice(offset));
    if (!match) {
      fail('Invalid JSON number');
    }
    offset += match[0].length;
    const value = Number(match[0]);
    if (!Number.isFinite(value)) {
      fail('Non-finite JSON number');
    }
    return value;
  }

  function literal(token, value) {
    if (text.slice(offset, offset + token.length) !== token) {
      fail('Invalid JSON literal');
    }
    offset += token.length;
    return value;
  }

  function value(depth) {
    if (depth > maximumDepth) {
      fail('JSON nesting exceeds the configured limit');
    }
    whitespace();
    const character = text[offset];
    if (character === '"') return string();
    if (character === '{') return object(depth + 1);
    if (character === '[') return array(depth + 1);
    if (character === 't') return literal('true', true);
    if (character === 'f') return literal('false', false);
    if (character === 'n') return literal('null', null);
    if (character === '-' || (character >= '0' && character <= '9')) {
      return number();
    }
    fail('Expected a JSON value');
  }

  function object(depth) {
    const result = Object.create(null);
    const keys = new Set();
    offset += 1;
    whitespace();
    if (text[offset] === '}') {
      offset += 1;
      return result;
    }
    while (offset < text.length) {
      whitespace();
      if (text[offset] !== '"') {
        fail('Object property name must be a string');
      }
      const key = string();
      if (keys.has(key)) {
        fail(`Duplicate object property ${JSON.stringify(key)}`);
      }
      keys.add(key);
      whitespace();
      if (text[offset] !== ':') {
        fail('Expected a colon after object property');
      }
      offset += 1;
      result[key] = value(depth);
      whitespace();
      if (text[offset] === '}') {
        offset += 1;
        return result;
      }
      if (text[offset] !== ',') {
        fail('Expected a comma or closing brace');
      }
      offset += 1;
    }
    fail('Unterminated JSON object');
  }

  function array(depth) {
    const result = [];
    offset += 1;
    whitespace();
    if (text[offset] === ']') {
      offset += 1;
      return result;
    }
    while (offset < text.length) {
      result.push(value(depth));
      whitespace();
      if (text[offset] === ']') {
        offset += 1;
        return result;
      }
      if (text[offset] !== ',') {
        fail('Expected a comma or closing bracket');
      }
      offset += 1;
    }
    fail('Unterminated JSON array');
  }

  const result = value(0);
  whitespace();
  if (offset !== text.length) {
    fail('Trailing content after JSON value');
  }
  return result;
}

module.exports = {
  StrictJsonError,
  parseStrictJson,
};
