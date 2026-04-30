// dict-loader 集成测试：读真实 launcher/data/save_repair_dict.json。
// 确保工具与 launcher 数据契约同步。

import { describe, it, expect } from 'vitest';
import { join } from 'node:path';
import { loadDict, dictBucket } from '../src/dict-loader.js';

const PROJECT_ROOT = join(import.meta.dirname, '..', '..', '..');

describe('loadDict (集成)', () => {
  it('能从 launcher/data/save_repair_dict.json 加载', () => {
    const dict = loadDict(PROJECT_ROOT);
    expect(dict.schemaVersion).toBe(1);
    expect(dict.items.length).toBeGreaterThan(100);
    expect(dict.skills.length).toBeGreaterThan(10);
    expect(dict.enemies.length).toBeGreaterThan(50);
  });

  it('dictBucket 按 kind 路由', () => {
    const dict = loadDict(PROJECT_ROOT);
    expect(dictBucket(dict, 'item')).toBe(dict.items);
    expect(dictBucket(dict, 'skill')).toBe(dict.skills);
    expect(dictBucket(dict, 'enemy')).toBe(dict.enemies);
    expect(dictBucket(dict, 'free_text')).toEqual([]);
  });
});
