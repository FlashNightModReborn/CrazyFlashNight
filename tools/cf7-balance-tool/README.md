# CF7 数值平衡工具

> 闪客快打7佣兵帝国 (CF7:ME) 数值平衡管理工具
> 直接读写游戏XML数据，内置从Excel翻译的平衡计算引擎
>
> 当前已初始化 **npm workspace** 骨架；实际可运行命令见 [docs/bootstrap-status.md](./docs/bootstrap-status.md)。

---

## 文档索引

| 文档 | 说明 | 优先级 |
|------|------|--------|
| [CF7-BalanceTool-DevSpec-v3.md](./CF7-BalanceTool-DevSpec-v3.md) | **主开发规格书** - 完整技术规格和实施计划 | 必读 |
| [CF7-BalanceTool-Investigation-Report.md](./CF7-BalanceTool-Investigation-Report.md) | **调研报告** - Q1-Q25结论和规格书修正 | 必读 |
| [CF7-BalanceTool-DocAudit-v1.md](./CF7-BalanceTool-DocAudit-v1.md) | **审计报告** - 文档准确性验证和修正建议 | 推荐 |
| [docs/field-reference.md](./docs/field-reference.md) | **字段参考** - 全部70个字段的详细说明 | 开发参考 |
| [docs/design-decisions.md](./docs/design-decisions.md) | **决策记录** - 关键设计决策(ADR) | 维护参考 |
| [docs/bootstrap-status.md](./docs/bootstrap-status.md) | **当前落地状态** - 已验证命令、首轮扫描结果、已知缺口 | 开发入口 |

---

## 项目定位

### 是什么

数值平衡管理工具，取代当前「Excel离线算 -> 手动抄回XML」的工作流。

```
旧工作流:
WPS Excel（离线计算器）──人工对照──> data/items/*.xml ──> AS2运行时

新工作流:
游戏XML数据 <──双向读写──> 平衡工具 <──公式引擎──> 计算内核
                                 |
                   CLI / Electron GUI / Agent 均可操作
```

### 核心约束

| # | 约束 | 说明 |
|---|------|------|
| C1 | 向前兼容 | XML是真正的数据源，Excel仅作legacy import |
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
| 数据源 | XML是主数据 | 消除不一致 |
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
| weapon_weighting_workflow.md | data/items/ | 武器加权工作流 |
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
