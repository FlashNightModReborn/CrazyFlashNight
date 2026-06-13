import { describe, it, expect } from 'vitest';
import {
  editJvmIni,
  tightenSidebar,
  machineInfoSafe,
  windowSwfGlobs,
  pathsFromWindowSwf,
} from '../src/an/index.js';

describe('AnEnv pure transforms', () => {
  describe('editJvmIni', () => {
    it('sets -Xmx and halves -Xms, reporting the previous value', () => {
      const res = editJvmIni('-Xmx512m\n-Xms256m\n-Dsun.java2d=true\n', 1024);
      expect(res.changed).toBe(true);
      expect(res.previousXmxMb).toBe(512);
      expect(res.newXmxMb).toBe(1024);
      expect(res.newXmsMb).toBe(512);
      expect(res.content).toContain('-Xmx1024m');
      expect(res.content).toContain('-Xms512m');
      expect(res.content).toContain('-Dsun.java2d=true');
    });

    it('appends -Xms when absent', () => {
      const res = editJvmIni('-Xmx512m\n', 800);
      expect(res.content).toContain('-Xms400m');
      expect(res.changed).toBe(true);
    });

    it('reports no change when already at target', () => {
      const res = editJvmIni('-Xmx1024m\n-Xms512m\n', 1024);
      expect(res.changed).toBe(false);
    });

    it('rejects non-positive / non-integer heap sizes', () => {
      expect(() => editJvmIni('-Xmx1m\n', 0)).toThrow();
      expect(() => editJvmIni('-Xmx1m\n', 1.5)).toThrow();
    });
  });

  describe('tightenSidebar', () => {
    const dict =
      '"$$$/PI_MAX_WIDTH=300"\n' +
      '"$$$/PI_MIN_WIDTH=100"\n' +
      '"$$$/PI/Text/Character/Autokern/tooltip=自动调整字距"=自动调整字距\n' +
      '"$$$/other=keep"\n';

    it('drops width lines and shortens auto-kern labels', () => {
      const res = tightenSidebar(dict);
      expect(res.changed).toBe(true);
      expect(res.removedWidthLines).toBe(2);
      expect(res.replacedLabels).toBe(1);
      expect(res.content).not.toContain('PI_MAX_WIDTH');
      expect(res.content).toContain('=自动'); // shortened
      expect(res.content).toContain('"$$$/other=keep"');
    });

    it('is idempotent once tightened', () => {
      const once = tightenSidebar(dict).content;
      const twice = tightenSidebar(once);
      expect(twice.changed).toBe(false);
    });
  });

  describe('machineInfoSafe', () => {
    it('produces a diagnostic with NO machine id / MAC', () => {
      const info = machineInfoSafe({
        platform: 'win32',
        osRelease: '10.0.26100',
        nodeVersion: 'v20.12.2',
        resolvedWindowSwf: ['C:/x/WindowSWF'],
        cepExtensionsDirs: [],
        sharedObjectsBase: null,
      });
      expect(info.containsMachineId).toBe(false);
      const blob = JSON.stringify(info).toLowerCase();
      expect(blob).not.toMatch(/\bmac\b/);
      expect(blob).not.toMatch(/([0-9a-f]{2}[:-]){5}[0-9a-f]{2}/); // no MAC address pattern
      expect(blob).not.toContain('active_code');
      expect(blob).not.toContain('consum_code');
    });
  });

  describe('path resolvers', () => {
    it('windowSwfGlobs builds Windows patterns', () => {
      const globs = windowSwfGlobs({
        platform: 'win32',
        localAppData: 'C:\\Users\\me\\AppData\\Local',
        programFiles: 'C:\\Program Files',
      });
      expect(globs.length).toBeGreaterThan(0);
      expect(globs.some((g) => g.includes('Animate') && g.includes('WindowSWF'))).toBe(true);
    });

    it('pathsFromWindowSwf derives sibling config paths', () => {
      const p = pathsFromWindowSwf('C:/AN/Configuration/WindowSWF');
      expect(p.commandsDir.replace(/\\/g, '/')).toBe('C:/AN/Configuration/Commands');
      expect(p.jvmIniPath.replace(/\\/g, '/')).toBe('C:/AN/Configuration/ActionScript 3.0/jvm.ini');
    });
  });
});
