# cf7-save-repair

CF7:ME 一次性救火脚本：扫描并修复因 launcher XmlSocket UTF-8 跨 chunk 切割 bug
（已修，见 C1a）残留在 `saves/{slot}.json` 中的 `U+FFFD` 替换字符。

与 launcher 同源消费 `launcher/data/save_repair_dict.json`（由 `tools/cf7-save-repair-dict-build` 生成）。

## 使用

```bash
cd tools/cf7-save-repair
npm install                 # 首次

# dry-run（默认）：扫描 + 输出 markdown 报告，不改文件
npm run scan -- <save.json> --project-root <project-root>

# 真改文件：备份原档 + 修复 + bump lastSaved（INV-1）
npm run scan -- <save.json> --project-root <project-root> --apply

# JSON 输出（程序消费）
npm run scan -- <save.json> --project-root <project-root> --json
```

`<project-root>` 必填，用于反推 `launcher/data/save_repair_dict.json` 路径。
推荐填仓库根：
`C:/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight`。

## 字段层级

按 plan `prancy-weaving-treasure.md` 同步：

| 层 | 路径 | 修复策略 |
|---|---|---|
| L0 | `$[0][0]` 角色名 / `$.lastSaved` | 阻塞 → manual_required |
| L1 | `inventory.{背包,装备栏,...}.*.name` / `.value.mods[*]` | 字典命中即修，未命中保留占位 `[损坏 待修复]` |
| L2 | 任务 / 击杀统计 / 技能名 / 发型 / 收藏 | 字典命中即修，未命中静默丢弃 |
| L3 | 物品来源缓存 / 设置 | 静默丢弃，下次玩自动重建 |

## --apply 流程

1. 备份原档 → `<save_dir>/.repair-backups/<slot>/<ts>.broken.json`（INV-4）
2. 内存扫描 + 修复（自参考池 + dict 对齐 + 分层降级）
3. **bump `lastSaved` 到当前时间**（INV-1，让 SolResolver 选 shadow，下次 saveAll 自动洗 SOL）
4. 原子写回 `saves/{slot}.json`（`.tmp` → unlink → rename）
5. audit log → `<save_dir>/.repair-backups/<slot>/<ts>.repair.log`（含修复 plan）

## INV-1 提醒

修过的 `saves/{slot}.json` 必须在玩家下次进游戏前**先经过 launcher 决议**：
- 修复后 `lastSaved` 已 bump → SolResolver 比时间戳选 shadow（修过的 JSON）
- AS2 用干净数据 loadFromMydata → 进入游戏后任意 saveAll → flush 干净 mydata 到 SOL → SOL 永久清洁

绕过 launcher 直接打游戏可能让旧 SOL 反向覆盖修复结果。

## 已知局限

- L1 多候选时降级为 manual_required，需用 archive-editor 手动确认（C2/C3 实施）
- L0 角色名修复必须人工
- 工具不感知 .sol 二进制；`.sol` 由 launcher AS2 saveAll 自动覆盖（INV-1 链）

## 测试

```bash
npm test
```

5 个 vitest suite，覆盖 layering / matcher / scan / repair / dict-loader 集成。
