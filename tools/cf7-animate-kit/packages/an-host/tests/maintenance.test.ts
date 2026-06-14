import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  installPluginSwf,
  deletePluginSwf,
  clearCacheDir,
  applyJvmMemory,
  expandPattern,
} from '../src/index.js';

let tmp = '';

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ankit-'));
});
afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function mkdirp(...segments: string[]): string {
  const dir = path.join(tmp, ...segments);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}
function writeFile(file: string, content: string): string {
  fs.writeFileSync(file, content);
  return file;
}

describe('an-host maintenance (tmpdir, never touches a real Animate install)', () => {
  it('installPluginSwf: dry-run plans, apply copies, overwrite backs up', () => {
    const windowSwf = mkdirp('Configuration', 'WindowSWF');
    const src = writeFile(path.join(tmp, 'myplugin.swf'), 'AAA');

    const plan = installPluginSwf(src, [windowSwf], { apply: false });
    expect(plan.applied).toBe(false);
    expect(fs.existsSync(path.join(windowSwf, 'myplugin.swf'))).toBe(false);
    expect(plan.changes[0]?.action).toBe('create');

    const done = installPluginSwf(src, [windowSwf], { apply: true });
    expect(done.applied).toBe(true);
    expect(fs.readFileSync(path.join(windowSwf, 'myplugin.swf'), 'utf8')).toBe('AAA');

    writeFile(src, 'BBB');
    const over = installPluginSwf(src, [windowSwf], { apply: true, backupSuffix: '.bak-test' });
    expect(over.changes[0]?.action).toBe('overwrite');
    expect(over.changes[0]?.backup).toBeTruthy();
    expect(fs.existsSync(path.join(windowSwf, 'myplugin.swf.bak-test'))).toBe(true);
    expect(fs.readFileSync(path.join(windowSwf, 'myplugin.swf'), 'utf8')).toBe('BBB');
  });

  it('applyJvmMemory: dry-run leaves file, apply edits + backs up', () => {
    const cfg = mkdirp('Configuration', 'ActionScript 3.0');
    const jvm = writeFile(path.join(cfg, 'jvm.ini'), '-Xmx512m\n-Xms256m\n');

    const dry = applyJvmMemory(jvm, 1024, { apply: false });
    expect(dry.applied).toBe(false);
    expect(fs.readFileSync(jvm, 'utf8')).toContain('-Xmx512m');

    const done = applyJvmMemory(jvm, 1024, { apply: true, backupSuffix: '.bak-test' });
    expect(done.applied).toBe(true);
    expect(done.previousXmxMb).toBe(512);
    const after = fs.readFileSync(jvm, 'utf8');
    expect(after).toContain('-Xmx1024m');
    expect(after).toContain('-Xms512m');
    expect(fs.existsSync(`${jvm}.bak-test`)).toBe(true);
  });

  it('clearCacheDir: clears contents on apply, plans on dry-run', () => {
    const cache = mkdirp('Configuration', 'tmp');
    writeFile(path.join(cache, 'a.bin'), 'x');
    writeFile(path.join(cache, 'b.bin'), 'y');

    const dry = clearCacheDir(cache, { apply: false });
    expect(dry.changes.length).toBe(2);
    expect(fs.existsSync(path.join(cache, 'a.bin'))).toBe(true);

    clearCacheDir(cache, { apply: true });
    expect(fs.readdirSync(cache).length).toBe(0);
  });

  it('deletePluginSwf: wildcard delete with backup, leaves non-matches', () => {
    const windowSwf = mkdirp('Configuration', 'WindowSWF');
    writeFile(path.join(windowSwf, 'plug_v1.swf'), '1');
    writeFile(path.join(windowSwf, 'keep.swf'), 'k');

    const res = deletePluginSwf('plug_*.swf', [windowSwf], { apply: true, backupSuffix: '.bak-test' });
    expect(res.changes.length).toBe(1);
    expect(fs.existsSync(path.join(windowSwf, 'plug_v1.swf'))).toBe(false);
    expect(fs.existsSync(path.join(windowSwf, 'keep.swf'))).toBe(true);
  });

  it('expandPattern: resolves single-* glob segments to existing dirs', () => {
    mkdirp('Adobe', 'Animate 2024', 'zh_CN', 'Configuration', 'WindowSWF');
    const pattern = path.join(tmp, 'Adobe', 'Animate*', '*', 'Configuration', 'WindowSWF');
    const found = expandPattern(pattern);
    expect(found.length).toBe(1);
    expect(found[0]?.endsWith(path.join('Configuration', 'WindowSWF'))).toBe(true);
  });
});
