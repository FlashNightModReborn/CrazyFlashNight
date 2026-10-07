import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  emptyMonsterFlagLedger,
  humanAuthorityOf,
  loadMonsterFlagLedger,
  recordToolWrites,
  saveMonsterFlagLedger,
} from "../src/monster-flag-ledger.js";
import type { MonsterFlagLedger } from "../src/monster-flag-ledger.js";

const COMMITTED = {
  "敌人-人工怪": { 阶段: 4, 档次系数: 8, 段数系数: 5 },
  "敌人-工具怪": { 阶段: 6, 档次系数: 24, 段数系数: 7.8 },
};

describe("标识来源台账", () => {
  it("工具自写的格即使提交进 HEAD 也不算人工权威", () => {
    const ledger = recordToolWrites(emptyMonsterFlagLedger(), [
      { spritename: "敌人-工具怪", flags: { 阶段: 6, 档次系数: 24, 段数系数: 7.8 } },
    ]);
    const authority = humanAuthorityOf(COMMITTED, ledger);
    expect(authority["敌人-工具怪"]).toBeUndefined();
    expect(authority["敌人-人工怪"]).toEqual({ 阶段: 4, 档次系数: 8, 段数系数: 5 });
  });

  it("HEAD 里的值与台账不同就是人工后来动过，那格回到人工权威", () => {
    const ledger = recordToolWrites(emptyMonsterFlagLedger(), [
      { spritename: "敌人-工具怪", flags: { 档次系数: 24 } },
    ]);
    const committed = { "敌人-工具怪": { 档次系数: 20 } };
    expect(humanAuthorityOf(committed, ledger)).toEqual({ "敌人-工具怪": { 档次系数: 20 } });
  });

  it("制作组点名的人工批次无条件算权威，没进 HEAD 也立刻生效", () => {
    const ledger: MonsterFlagLedger = { version: 1, writes: {}, claims: { "敌人-新打标怪": { 阶段: 9 } } };
    expect(humanAuthorityOf(COMMITTED, ledger)["敌人-新打标怪"]).toEqual({ 阶段: 9 });
  });

  it("工具落盘的格只进自写表：覆盖到点名那颗时把认领摘下去，写回不会把自己洗成永久人工权威", () => {
    const ledger: MonsterFlagLedger = { version: 1, writes: {}, claims: { "敌人-骨刺僵尸": { 阶段: 5 } } };
    expect(humanAuthorityOf({ "敌人-骨刺僵尸": { 阶段: 5 } }, ledger)).toEqual({ "敌人-骨刺僵尸": { 阶段: 5 } });

    const after = recordToolWrites(ledger, [{ spritename: "敌人-骨刺僵尸", flags: { 阶段: 6 } }]);
    expect(after.claims["敌人-骨刺僵尸"]).toBeUndefined();
    expect(after.writes["敌人-骨刺僵尸"]).toEqual({ 阶段: 6 });
    expect(humanAuthorityOf({ "敌人-骨刺僵尸": { 阶段: 6 } }, after)).toEqual({});
  });

  it("工具写同一模板的别的格不连坐，点名的那颗照旧算人工", () => {
    const ledger: MonsterFlagLedger = { version: 1, writes: {}, claims: { "敌人-骨刺僵尸": { 阶段: 5 } } };
    const after = recordToolWrites(ledger, [{ spritename: "敌人-骨刺僵尸", flags: { 档次系数: 9 } }]);
    expect(after.claims["敌人-骨刺僵尸"]).toEqual({ 阶段: 5 });
    expect(humanAuthorityOf({ "敌人-骨刺僵尸": { 阶段: 5, 档次系数: 9 } }, after)).toEqual({ "敌人-骨刺僵尸": { 阶段: 5 } });
  });

  it("台账落盘后按模板名与字段名排序读回，值一字不差", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "flag-ledger-"));
    const file = path.join(dir, "monster-flag-ledger.json");
    const ledger: MonsterFlagLedger = {
      ...recordToolWrites(emptyMonsterFlagLedger(), [
        { spritename: "敌人-骨刺僵尸", flags: { 阶段: 6, 档次系数: 24 } },
        { spritename: "敌人-盗贼小飞机", flags: { 阶段: 2 } },
      ]),
      claims: { "敌人-人工怪": { 段数系数: 5 } },
    };
    saveMonsterFlagLedger(file, ledger);
    const text = fs.readFileSync(file, "utf8");
    // 落盘按中文序重排：写入时 骨刺 在前、字段先写 阶段，读回来两处都要倒过来
    expect(text.indexOf("敌人-盗贼小飞机")).toBeLessThan(text.indexOf("敌人-骨刺僵尸"));
    expect(Object.keys(JSON.parse(text).writes["敌人-骨刺僵尸"])).toEqual(["档次系数", "阶段"]);
    expect(loadMonsterFlagLedger(file)).toEqual(ledger);
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("台账缺 writes 或 claims 时顶回去，不能当成空台账放过", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "flag-ledger-bad-"));
    const file = path.join(dir, "bad.json");
    fs.writeFileSync(file, '{"version":1,"writes":{}}', "utf8");
    expect(() => loadMonsterFlagLedger(file)).toThrow(/writes\/claims/);
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("没有台账文件时按空台账走，人工权威等于 HEAD 原文", () => {
    const missing = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "flag-ledger-none-")), "monster-flag-ledger.json");
    expect(loadMonsterFlagLedger(missing)).toEqual(emptyMonsterFlagLedger());
    expect(humanAuthorityOf(COMMITTED, loadMonsterFlagLedger(missing))).toEqual(COMMITTED);
  });
});
