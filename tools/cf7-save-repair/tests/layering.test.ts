import { describe, it, expect } from 'vitest';
import { classifyField } from '../src/layering.js';

describe('classifyField', () => {
  it('L0: 角色名 $[0][0]', () => {
    const r = classifyField(['0', '0']);
    expect(r.layer).toBe('L0');
    expect(r.fallbackWhenDictMiss).toBe('manual');
  });

  it('L0: lastSaved', () => {
    expect(classifyField(['lastSaved']).layer).toBe('L0');
  });

  it('L1: 装备栏.{slot}.name', () => {
    const r = classifyField(['inventory', '装备栏', '上装装备', 'name']);
    expect(r.layer).toBe('L1');
    expect(r.kind).toBe('item');
    expect(r.fallbackWhenDictMiss).toBe('preserve');
  });

  it('L1: 装备栏.{slot}.value.mods.0', () => {
    const r = classifyField(['inventory', '装备栏', '上装装备', 'value', 'mods', 0]);
    expect(r.layer).toBe('L1');
    expect(r.kind).toBe('mod');
  });

  it('L2: tasks_finished[key]', () => {
    const r = classifyField(['tasks', 'tasks_finished', 'someTask']);
    expect(r.layer).toBe('L2');
    expect(r.kind).toBe('questId');
    expect(r.fallbackWhenDictMiss).toBe('drop');
  });

  it('L2: 击杀统计.byType[key]', () => {
    const r = classifyField(['others', '击杀统计', 'byType', '某敌人']);
    expect(r.layer).toBe('L2');
    expect(r.kind).toBe('enemy');
  });

  it('L2: [5][N][0] 技能名', () => {
    const r = classifyField(['5', 3, '0']);
    expect(r.layer).toBe('L2');
    expect(r.kind).toBe('skill');
  });

  it('L2: [1][N] 发型', () => {
    const r = classifyField(['1', 5]);
    expect(r.layer).toBe('L2');
    expect(r.kind).toBe('hairstyle');
  });

  it('L2: collection.材料[key]', () => {
    const r = classifyField(['collection', '材料', '某材料']);
    expect(r.layer).toBe('L2');
    expect(r.kind).toBe('item');
  });

  it('L3: 物品来源缓存.discoveredEnemies[N]', () => {
    const r = classifyField(['others', '物品来源缓存', 'discoveredEnemies', 0]);
    expect(r.layer).toBe('L3');
  });

  it('L3: 设置.*', () => {
    const r = classifyField(['others', '设置', '某键']);
    expect(r.layer).toBe('L3');
  });

  it('未知字段 → L3 默认丢弃', () => {
    const r = classifyField(['未知字段']);
    expect(r.layer).toBe('L3');
  });
});
