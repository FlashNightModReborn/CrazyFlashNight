import { describe, it, expect } from 'vitest';
import { findCandidates } from '../src/matcher.js';

describe('findCandidates', () => {
  it('单候选字典命中 → confidence 1.0, source dict_unique', () => {
    const r = findCandidates('黑铁会�叔', ['黑铁会大叔', '黑铁会小弟']);
    expect(r).toHaveLength(1);
    expect(r[0]!.value).toBe('黑铁会大叔');
    expect(r[0]!.source).toBe('dict_unique');
    expect(r[0]!.confidence).toBe(1.0);
  });

  it('多候选 → confidence 1/N', () => {
    const r = findCandidates('黑铁会�叔', ['黑铁会大叔', '黑铁会二叔']);
    expect(r).toHaveLength(2);
    expect(r[0]!.source).toBe('dict');
    expect(r[0]!.confidence).toBeCloseTo(0.5, 5);
  });

  it('自参考池命中优先 → source self_ref', () => {
    const r = findCandidates('黑铁会�叔', ['黑铁会大叔'], ['黑铁会大叔']);
    expect(r[0]!.source).toBe('self_ref');
    expect(r[0]!.confidence).toBe(1.0);
    // 字典里同名的不重复出现
    expect(r).toHaveLength(1);
  });

  it('累积扩张：broken 长度可远大于候选（subsequence anchor 匹配）', () => {
    // 模拟多次 saveAll 让 1 个 CJK 字符膨胀成 N 个 fffd
    const r = findCandidates('黑铁�����������会大叔', ['敌人-黑铁会大叔', '敌人-黑铁会叔'], []);
    // anchors=[黑,铁,会,大,叔] 都按序包含
    expect(r.find((c) => c.value === '敌人-黑铁会大叔')).toBeDefined();
  });

  it('多个 fffd 也能匹配', () => {
    const r = findCandidates('黑��叔', ['黑铁会叔', '黑铁我叔']);
    expect(r).toHaveLength(2);
  });

  it('全部 fffd → 0 anchor 不匹配', () => {
    const r = findCandidates('���', ['ABC', 'XYZ']);
    expect(r).toHaveLength(0);
  });

  it('subsequence 匹配：anchors 必须按序', () => {
    // anchors=[A,C], 候选 "ABC" 命中, "CBA" 不（C 在 A 前）
    const r = findCandidates('A�C', ['ABC', 'CBA']);
    expect(r).toHaveLength(1);
    expect(r[0]!.value).toBe('ABC');
  });

  it('ASCII 锚点过滤掉不匹配', () => {
    // broken="A�C", 候选 "AYC" 命中, "BYC" 因 A 不匹配过滤掉
    const r = findCandidates('A�C', ['AYC', 'BYC']);
    expect(r).toHaveLength(1);
    expect(r[0]!.value).toBe('AYC');
  });
});
