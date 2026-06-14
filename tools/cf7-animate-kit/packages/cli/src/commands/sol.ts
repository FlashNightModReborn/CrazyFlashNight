import fs from 'node:fs';
import path from 'node:path';
import {
  readSol,
  writeSol,
  solToJson,
  jsonToBody,
  SOL,
  type Json,
  type SolFile,
} from '@cf7-animate-kit/core';
import { parseArgs, printJson, printLine, fail } from '../lib/args.js';

const USAGE = `cf7-animate-kit sol <subcommand>

  read <file.sol> [--ast]        Print the JSON projection (default) or the lossless AST (--ast).
  info <file.sol>                Print name / AMF version / element count / top-level keys.
  diff <a.sol> <b.sol>           Structural diff of two saves' JSON projections.
  from-json <data.json> <out.sol> --name <soname>
                                 Build a .sol from a plain JSON data object (AS2 array semantics).

All reads are non-destructive. 'from-json' writes a fresh file (no in-place edit).`;

export function runSol(argv: string[]): void {
  const sub = argv[0];
  const rest = argv.slice(1);
  switch (sub) {
    case 'read':
      return solRead(rest);
    case 'info':
      return solInfo(rest);
    case 'diff':
      return solDiff(rest);
    case 'from-json':
      return solFromJson(rest);
    case undefined:
    case 'help':
    case '--help':
      return printLine(USAGE);
    default:
      fail(`unknown 'sol' subcommand: ${sub}. Run 'sol help'.`);
  }
}

function solRead(argv: string[]): void {
  const { _, flags } = parseArgs(argv);
  const file = _[0];
  if (!file) fail('usage: sol read <file.sol> [--ast]');
  const sol = readSol(fs.readFileSync(file));
  printJson(flags['ast'] ? sol : solToJson(sol));
}

function solInfo(argv: string[]): void {
  const { _ } = parseArgs(argv);
  const file = _[0];
  if (!file) fail('usage: sol info <file.sol>');
  const buf = fs.readFileSync(file);
  const sol = readSol(buf);
  printJson({
    file: path.resolve(file),
    bytes: buf.length,
    name: sol.name,
    amfVersion: sol.amfVersion,
    elementCount: sol.body.length,
    topLevelKeys: sol.body.map((e) => e.name),
  });
}

function solDiff(argv: string[]): void {
  const { _ } = parseArgs(argv);
  const a = _[0];
  const b = _[1];
  if (!a || !b) fail('usage: sol diff <a.sol> <b.sol>');
  const ja = solToJson(readSol(fs.readFileSync(a)));
  const jb = solToJson(readSol(fs.readFileSync(b)));
  const changes: Array<{ path: string; a: Json | undefined; b: Json | undefined }> = [];
  deepDiff('', ja, jb, changes);
  printJson({ a, b, changeCount: changes.length, changes });
}

function solFromJson(argv: string[]): void {
  const { _, flags } = parseArgs(argv);
  const dataFile = _[0];
  const outFile = _[1];
  const name = typeof flags['name'] === 'string' ? flags['name'] : undefined;
  if (!dataFile || !outFile) fail('usage: sol from-json <data.json> <out.sol> --name <soname>');
  if (!name) fail("'from-json' requires --name <soname> (the SharedObject name)");
  const data = JSON.parse(fs.readFileSync(dataFile, 'utf8')) as { [k: string]: Json };
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    fail('data.json must be a JSON object at the top level');
  }
  const sol: SolFile = {
    signature: SOL.SIGNATURE,
    headerPad: SOL.HEADER_PAD,
    name,
    amfVersion: 0,
    body: jsonToBody(data),
  };
  fs.writeFileSync(outFile, writeSol(sol));
  printLine(`wrote ${path.resolve(outFile)} (SharedObject "${name}", ${sol.body.length} keys)`);
}

function deepDiff(
  prefix: string,
  a: Json | undefined,
  b: Json | undefined,
  out: Array<{ path: string; a: Json | undefined; b: Json | undefined }>,
): void {
  if (a === b) return;
  const bothObjects =
    a !== null &&
    b !== null &&
    typeof a === 'object' &&
    typeof b === 'object' &&
    Array.isArray(a) === Array.isArray(b);
  if (!bothObjects) {
    if (JSON.stringify(a) !== JSON.stringify(b)) out.push({ path: prefix || '(root)', a, b });
    return;
  }
  const keys = new Set<string>([...Object.keys(a as object), ...Object.keys(b as object)]);
  for (const k of keys) {
    const av = (a as Record<string, Json>)[k];
    const bv = (b as Record<string, Json>)[k];
    deepDiff(prefix ? `${prefix}.${k}` : k, av, bv, out);
  }
}
