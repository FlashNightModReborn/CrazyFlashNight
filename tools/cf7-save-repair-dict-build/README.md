# cf7-save-repair-dict-build

存档修复字典生成器。

## 用途

为存档损坏（U+FFFD 乱码）修复流程提供**单源权威字典**。该字典被两端共同消费：

- launcher C# 端：`launcher/src/Save/RepairDictionary.cs` 启动加载 `launcher/data/save_repair_dict.json`
- 修复脚本 TS 端：`tools/cf7-save-repair/src/dict-loader.ts` 直读同一份 JSON

字典内容来自 4 类源头：

| 字段 | 源 | 提取方式 |
|---|---|---|
| `items` | `data/items/**.xml` | `<item><name>` |
| `mods` | `data/items/equipment_mods/*.xml` | `<mod><name>` |
| `enemies` | `data/enemy_properties/*.xml` | top-level element name (e.g. `<敌人-黑铁会大叔>`) |
| `hairstyles` | `data/items/hairstyle.xml` | `<Hair><Identifier>` |
| `skills` | `scripts/.../SaveManager.as` | `REPAIR_DICT_SKILLS:Array = [...]` 字面量 |
| `taskChains` | `scripts/.../SaveManager.as` | `REPAIR_DICT_TASK_CHAINS:Array = [...]` |
| `stages` | `scripts/.../SaveManager.as` | `REPAIR_DICT_STAGES:Array = [...]` |

## 使用

```bash
# 安装
npm install

# 测试
npm test

# 生成 dict（写到 ../../launcher/data/save_repair_dict.json）
npm run build

# 验证 dict 是否与源头一致（CI gate 用）
npm run verify   # 通过返回 0；不一致返回 1 + 打印 diff
```

## 何时需要重新生成

修改了以下任一处，必须 `npm run build`：

- `data/items/**/*.xml` 新增/删除/改名 `<item>` 或 `<mod>`
- `data/enemy_properties/*.xml` 新增/删除敌人元素（top-level tag）
- `data/items/hairstyle.xml` 新增/删除发型条目
- `scripts/类定义/org/flashNight/neur/Server/SaveManager.as` 修改 `REPAIR_DICT_*` 静态常量

## CI Gate

`npm run verify` 的 exit code：
- `0`：当前 `save_repair_dict.json` 与源头一致
- `1`：源头有变化但 dict 未同步 regenerate

建议在以下位置接入：
- **Git pre-commit hook**：检测 `data/**/*.xml` 或 `SaveManager.as` 改动后跑 `npm --prefix tools/cf7-save-repair-dict-build run verify`
- **PR check**（如有 GitHub Actions）：在 launcher build 之前跑 verify；失败即阻止合入

## 单元测试结构

- `tests/xml-parsers.test.ts`：4 类 XML 解析的独立单测
- `tests/as2-constants.test.ts`：AS2 字面量提取（多行/内联/注释/单引号/异常）
- `tests/build.test.ts`：端到端 — 用合成迷你项目跑 build/verify

## 设计决策

- **不写 schema 校验工具**：generated JSON 本身就是契约；如何使用由消费方负责。
- **AS2 常量**而非 `<skill>` XML：技能名/任务链名在 AS2 代码里就是字符串字面量，没有独立 XML。继续在 SaveManager 维护一份显式数组，CI gate 守同源。
- **U+FFFD 过滤**：解析时主动跳过含 `�` 的字段，防止已坏数据被当成"权威"反向污染 dict。
- **排序**：所有数组按 `localeCompare(zh)` 稳定排序，便于 PR diff review。
