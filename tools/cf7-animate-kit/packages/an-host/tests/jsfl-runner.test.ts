import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runJsflJob } from '../src/jsfl-runner.js';

let jobDir = '';

beforeEach(() => {
  jobDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ankit-jsfl-'));
});
afterEach(() => {
  fs.rmSync(jobDir, { recursive: true, force: true });
});

/** Fake clock that advances only when sleep() is called, so the poll loop is instant + deterministic. */
function fakeTiming() {
  let now = 1_000_000;
  return {
    clock: () => now,
    sleep: async (ms: number) => {
      now += ms;
    },
  };
}

function writeResult(obj: unknown): void {
  fs.writeFileSync(path.join(jobDir, 'cf7ak-result.json'), JSON.stringify(obj), 'utf8');
  fs.writeFileSync(path.join(jobDir, 'cf7ak-done.marker'), 'ok', 'utf8');
}

describe('runJsflJob (headless JSFL chain, stub trigger — no real Animate)', () => {
  it('happy path: trigger writes a fresh result + marker → returns parsed data', async () => {
    const t = fakeTiming();
    const res = await runJsflJob({
      jobDir,
      fn: 'scanLinkage',
      args: { foo: 1 },
      trigger: { kind: 'inline', run: () => writeResult({ ok: true, data: { count: 3, items: [] } }) },
      ...t,
    });
    expect(res.ok).toBe(true);
    expect(res.data).toEqual({ count: 3, items: [] });
    // job file was written with the requested fn/args
    const job = JSON.parse(fs.readFileSync(path.join(jobDir, 'cf7ak-job.json'), 'utf8'));
    expect(job.fn).toBe('scanLinkage');
    expect(job.args).toEqual({ foo: 1 });
  });

  it('error marker → returns ok:false with the host error', async () => {
    const t = fakeTiming();
    const res = await runJsflJob({
      jobDir,
      fn: 'exportSelected',
      trigger: {
        kind: 'inline',
        run: () => fs.writeFileSync(path.join(jobDir, 'cf7ak-error.marker'), 'no document open', 'utf8'),
      },
      ...t,
    });
    expect(res.ok).toBe(false);
    expect(res.error).toBe('no document open');
  });

  it('no response → times out (does not hang)', async () => {
    const t = fakeTiming();
    const res = await runJsflJob({
      jobDir,
      fn: 'probe',
      timeoutSeconds: 5,
      trigger: { kind: 'inline', run: () => {} },
      ...t,
    });
    expect(res.ok).toBe(false);
    expect(res.timedOut).toBe(true);
  });

  it('stale leftover result is cleaned at start, not falsely returned', async () => {
    // Pre-seed a stale result + done marker from a "previous run".
    writeResult({ ok: true, data: { stale: true } });
    const t = fakeTiming();
    const res = await runJsflJob({
      jobDir,
      fn: 'probe',
      timeoutSeconds: 3,
      trigger: { kind: 'inline', run: () => {} }, // Animate "not running": writes nothing fresh
      ...t,
    });
    expect(res.timedOut).toBe(true); // stale data was NOT returned
  });
});
