import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { readSol, writeSol, parseSolToJson, solToJson, jsonToValue } from '../src/amf/index.js';

const here = path.dirname(url.fileURLToPath(import.meta.url));
const fxDir = path.join(here, 'fixtures', 'sol');

const FIXTURES = [
  'real_flash_v3',
  'amf0probe_types',
  'amf0probe_typed',
  'amf0probe_self',
  'amf0probe_nested',
  'amf0probe_root',
  'flwriter_probe',
] as const;

/** Normalize through JSON to collapse any NaN/Infinity to null and drop undefined. */
function norm(v: unknown): unknown {
  return JSON.parse(JSON.stringify(v));
}

describe('AMF0 / SOL codec', () => {
  for (const name of FIXTURES) {
    const solPath = path.join(fxDir, `${name}.sol`);
    const goldenPath = path.join(fxDir, `${name}.golden.json`);

    it(`${name}: byte-exact round-trip (read -> write === original)`, () => {
      const original = fs.readFileSync(solPath);
      const parsed = readSol(original);
      const rewritten = writeSol(parsed);
      expect(rewritten.equals(original)).toBe(true);
    });

    it(`${name}: JSON projection matches the Rust flash_lso golden`, () => {
      const bytes = fs.readFileSync(solPath);
      const golden = JSON.parse(fs.readFileSync(goldenPath, 'utf8'));
      expect(norm(parseSolToJson(bytes))).toEqual(golden);
    });
  }

  it('SolFile metadata: name + version of the real game save', () => {
    const sol = readSol(fs.readFileSync(path.join(fxDir, 'real_flash_v3.sol')));
    expect(sol.name).toBe('crazyflasher7_saves');
    expect(sol.amfVersion).toBe(0);
    expect(sol.signature).toBe(0x00bf);
  });

  it('jsonToValue: array -> ECMA array with length attribute (AS2 semantics)', () => {
    const v = jsonToValue([1, 2, 3]);
    expect(v).toEqual({
      kind: 'ecmaArray',
      lengthAttr: 3,
      entries: [
        { name: '0', value: { kind: 'number', value: 1 } },
        { name: '1', value: { kind: 'number', value: 2 } },
        { name: '2', value: { kind: 'number', value: 3 } },
      ],
    });
  });

  it('solToJson is stable across a parse/serialize/parse cycle', () => {
    const bytes = fs.readFileSync(path.join(fxDir, 'real_flash_v3.sol'));
    const sol = readSol(bytes);
    const again = readSol(writeSol(sol));
    expect(norm(solToJson(again))).toEqual(norm(solToJson(sol)));
  });
});
