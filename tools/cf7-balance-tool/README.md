# CF7 数值平衡工具

> 闪客快打7佣兵帝国 (CF7:ME) 数值平衡管理工具
> 直接读写游戏 XML 数据，内置对权威工作簿公式的派生实现；工具输出不得覆盖工作簿明确规则
>
> 当前已初始化 **npm workspace** 骨架；实际可运行命令见 [docs/bootstrap-status.md](./docs/bootstrap-status.md)。

---

## 文档索引

| 文档 | 说明 | 优先级 |
|------|------|--------|
| [docs/agent-balance-record-design.md](./docs/agent-balance-record-design.md) | **当前契约** - 武器 `<balance>` schema、权威边界、施工与验证 | 必读 |
| [docs/weapon-balance-rulebook.md](./docs/weapon-balance-rulebook.md) | **当前规则** - 武器平衡业务判据与稳定条款 ID | 必读 |
| [CF7-BalanceTool-DevSpec-v3.md](./CF7-BalanceTool-DevSpec-v3.md) | 历史开发规格；与当前契约冲突时不得采用 | 历史 |
| [CF7-BalanceTool-Investigation-Report.md](./CF7-BalanceTool-Investigation-Report.md) | 历史调研报告 | 历史 |
| [CF7-BalanceTool-DocAudit-v1.md](./CF7-BalanceTool-DocAudit-v1.md) | 历史文档审计 | 历史 |
| [docs/field-reference.md](./docs/field-reference.md) | **字段参考** - 全部70个字段的详细说明 | 开发参考 |
| [docs/design-decisions.md](./docs/design-decisions.md) | **决策记录** - 关键设计决策(ADR) | 维护参考 |
| [docs/bootstrap-status.md](./docs/bootstrap-status.md) | **当前落地状态** - 已验证命令、首轮扫描结果、已知缺口 | 开发入口 |

---

## 项目定位

### 是什么

数值平衡管理工具，把“权威工作簿规则 + 游戏 XML 数值 + 单件 `<balance>` 依据”接成可复算、可审计的工作流。工作簿仍是公式最高权威，工具负责翻译、批量操作和辅助验证。

```
权威工作簿 ──规则/公式──> 平衡契约与规则表 ──派生实现──> 平衡工具
                                  |                         |
                                  └──证据──> XML <balance> <──┘
                                                |
                                        XML <data> / AS2运行时
```

### 核心约束

| # | 约束 | 说明 |
|---|------|------|
| C1 | 真源分层 | XLSX 管公式；XML `<data>` 管运行数值；XML `<balance>` 管单件平衡输入与依据 |
| C2 | 人类友好 | Electron GUI表格编辑，即时校验 |
| C3 | Agent友好 | headless CLI，Agent可无GUI操作 |
| C4 | LLM预留 | JSON I/O，CLI已存在 |
| C5 | 可审计 | 变更changelog，git diff友好 |

---

## 数据源覆盖

### 公式引擎 + CRUD (完整支持)

| 品类 | 文件数 | 说明 |
|------|--------|------|
| 枪械 | 22 | 手枪+长枪，含22个weapontype分类 |
| 防具 | 4 | 0-19级/20-39级/40+级/颈部 |
| 近战(刀) | 15 | 15种刀类子类 |
| 药剂 | 1 | 59个公式，治疗效果计算 |
| 经济/合成 | - | 价格/合成成本/副本收益 |

### 仅 CRUD (暂无数值理论)

| 品类 | 文件数 | 说明 |
|------|--------|------|
| 插件 | 20 | equipment_mods/，有复杂数值建模 |
| bullets_cases | 1 | 子弹/射线配置 |
| 其他消耗品 | 5 | 弹夹/手雷/货币/食材/食品 |

### 延后支持 (P3)

| 品类 | 文件数 | 说明 |
|------|--------|------|
| 怪物属性 | 11 | enemy_properties/，完全不同的结构 |

### 不纳入

| 品类 | 原因 |
|------|------|
| 收集品 | 无数值字段 |
| hairstyle | 非数值平衡 |
| inputCommand | 搓招系统，无关 |
| intelligence | 剧情文本，无关 |

---

## 技术栈

| 层 | 选型 |
|----|------|
| 语言 | TypeScript (strict) |
| 运行时 | Node.js >=18, tsx |
| 测试 | Vitest |
| XML | fast-xml-parser |
| Excel | SheetJS (xlsx) |
| 前端 | Electron + React + Vite |
| Schema | Zod |

---

## 目录结构 (规划)

```
tools/cf7-balance-tool/
├── packages/
│   ├── core/              # 纯计算内核
│   │   ├── schema/        # Zod schema
│   │   ├── formulas/      # Excel翻译的公式
│   │   ├── engine/        # 计算引擎
│   │   └── rules/         # 平衡规则
│   ├── xml-io/            # XML读写层
│   ├── excel-io/          # Legacy导入
│   ├── cli/               # CLI入口
│   └── web/               # Electron + React
├── data/                  # 工具数据
├── baseline/              # Excel校准基准
│   ├── baseline-extracted.json
│   └── 武器-技能数值-价格-合成表.xlsx
└── docs/                  # 文档
    ├── field-reference.md
    └── design-decisions.md
```

---

## 实施计划

| 阶段 | 周期 | 目标 | 验收标准 |
|------|------|------|----------|
| P0 | Day 1 | 骨架+字段报告 | `npm test`通过 |
| P1 | Day 2-3 | XML读写层 | 所有XML round-trip无diff |
| P2 | Day 4-5 | 枪械公式+校准 | 校准通过率>95% |
| P3 | Day 6-8 | 其余公式 | 校准通过率>90% |
| P4 | Day 9-10 | CLI完善 | Agent可完整操作 |
| P5 | Day 11-14 | Electron GUI | 可编辑保存 |
| P6 | Day 15+ | 打磨+怪物 | 待定 |

---

## 快速开始 (当前骨架)

```bash
# 进入目录
cd tools/cf7-balance-tool

# 安装依赖
npm install

# 类型检查 + 测试
npm run typecheck
npm test

# 检查 v1 台账与 compact runtime profile 是否一致
npm run balance-sync -- --check

# 严格检查仓库内已有的 weapon balance v1 记录
npm run balance-check

# 生成字段扫描报告
npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json

# 启动 renderer shell
npm run dev:web

# 启动 Electron 主进程（需另开一个终端先跑 dev:web）
npm run dev:electron
```
---

## 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 权威分层 | XLSX 管公式，XML `<data>` 管运行值，工具侧 v1 台账管完整审计，item `<balance>` 只放派生运行时核 | 避免工具或旧记录循环证明自身，并减少加载/克隆成本 |
| 武器旧 schema | 不兼容；未上线草案统一迁移为严格 v1 | 旧平铺/v2 草案从未形成可用契约 |
| 变体 profile | `data/data_*` 独立完整记录，缺失禁止回退 | 基础形态不能证明进阶形态 |
| 玩家展示 | 仅投影通过门禁的等级/加权层最小摘要 | 提供购买引导且隔离内部审计信息 |
| 公式输出 | 只读参考值 | 不回写XML |
| 解析器 | 分层而非单一 | 结构差异大 |
| 插件计算 | 三阶段实现 | 复杂度递进 |
| 怪物支持 | P3延后 | 结构完全不同 |

详见 [docs/design-decisions.md](./docs/design-decisions.md)

---

## 相关资源

### 仓库内参考

| 文件 | 位置 | 用途 |
|------|------|------|
| 插件数值设计讨论.md | data/items/ | 插件算子说明 |
| 射线插件数值建模_2026-02.md | data/items/equipment_mods/ | 495行射线模型 |
| weapon_weighting_workflow.md | data/items/ | 旧简化武器加权流程，仅供历史追溯 |
| weapon_classification_log.md | data/items/ | weapontype标注日志 |
| DamageCalculator.as | scripts/.../Damage/ | 伤害计算源码 |
| DamageResistanceHandler.as | scripts/.../StatHandler/ | 减伤公式源码 |

### 外部依赖

- [fast-xml-parser](https://www.npmjs.com/package/fast-xml-parser) - XML处理
- [SheetJS](https://sheetjs.com/) - Excel处理
- [Zod](https://zod.dev/) - Schema验证

---

## 贡献与维护

### 待用户确认

1. **公式引擎输出范围**: 是否计算"推荐价格"？
2. **撤销/重做**: GUI是否需要完整支持？
3. **版本控制**: changelog如何与Git协作？

详见 [CF7-BalanceTool-DocAudit-v1.md](./CF7-BalanceTool-DocAudit-v1.md) §六

### 下一步行动

1. [ ] 确认4个待决策问题
2. [ ] 修正4处minor文档问题
3. [ ] 初始化monorepo骨架 (P0)
4. [ ] 实施字段扫描报告 (P0补充)

---

*项目状态: 文档就绪，待开发*
*最后更新: 2026-03-06*
