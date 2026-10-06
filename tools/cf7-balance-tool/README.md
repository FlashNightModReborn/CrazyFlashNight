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
| [docs/monster-flag-rulebook.md](./docs/monster-flag-rulebook.md) | **当前规则** - 怪物面板公式、`<标识>` 反推可辨识性与阶段反查 | 数值/关卡相关必读 |
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
| 怪物(敌人属性) | 13 | enemy_properties/，面板公式正反算、`<标识>` 普查与写回，魔神.xml 除外 |
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
| 怪物 GUI 编辑 | - | `<标识>` 只有 CLI，Electron 侧未接 |

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

# 怪物标识普查（CLI 走 tsx，需要先构建 workspace dist）
npx tsc -b packages/core packages/xml-io packages/cli
npm run monster-census                              # 清点 + 四元联立反推，人工权威按 git HEAD 判
npm run monster-census -- --free-tier               # 一次性把 档次系数 放回搜索：只越过 humanTierFactors 点名的行，HEAD 已提交标识照旧钉住（estimatedTierTemplates 点名的两行两种模式都进搜索）
#   ⚠ 盘上现在的 档次 是放开档次解出来又写回的值，所以 census 与 monster-flags-csv 要用同一条模式跑；用默认模式重跑会把 11 行点名档次钉回旧值去解其余三项，表上误差整段虚高（见 rulebook §4）
npm run monster-solve -- 敌人-体育老师 --known 速度系数=2.5,档次系数=12   # 单行反推，没钉住的自由量都解
npm run monster-flags-apply -- reports/monster-flag-census.json   # dry-run，加 --write 才落盘
npm run monster-flags-csv                           # 出四张查验表：全量表 / 超范围表 / 偏差大表 / 人工表（前三张按盘上现值重生成，会盖掉全量表上没读回的手工改动）
npm run monster-flags-table-apply                   # 读回全量表上人工改过的系数，加 --write 才落盘 —— 重生成表之前必须先跑这一步

# 攻击结构实测：翻 XFL/.fla 量 攻速系数/攻击倍率/段数系数 的观测值，并从击倒/倒地/被击三段的状态层判 霸体系数，
# 连同机械可定的 阶段/速度系数 一起存候选 JSON
npm run monster-attack                                            # 全量，写 reports/monster-attack-census.{json,md}
npm run monster-attack-show -- 敌人-特警僵尸                        # 逐招明细（状态/标签/帧/子弹跨度/命中/段数/前摇/后摇/近战颗数/函数发弹/倍率与疑点）+ 霸体判据（击飞证据、被击每发击退帧数）
npm run monster-flags-apply -- --from reports/monster-attack-proposal.json   # 只补缺项，已标注的字段不覆盖
npm run monster-attack -- --overwrite                             # 口径变更后重标：观测值与已标注不同的也进候选，配 --only 圈行
# 模板被注册表记在 <conflict>/<duplicate>（有源没定源）时，定源写在 data/monster-census.json 的 attackSourceOverrides，
# 不手填 data/items/asset_source_map.xml（scan_linkage.py 的 DO-NOT-EDIT 生成物，图标/换装烘焙管线也读它）
# 口径旋钮同在 monster-census.json：attackTempoBands（攻速档位）、attackSegmentWindowFrames（段数的子弹跨度窗口）、
# attackTempoTailFactor（后摇分量倍率，同时放宽档位门槛）、attackStateWords/nonAttackStateWords（状态硬门词表）、
# meleeSegmentRules（近战子弹有效颗数：联弹折 霰弹值 分量 + 无区域散弹按拨折颗数，mode 取 cap/hitbox/off）；
# 联弹方向口径（制作组 2026-10-06 定，此前写反）：linkageHorizontalWords（现 横向）无条件折、
# linkageVerticalWords（现 纵向）一律不折、其余联弹（含 近战联弹）要传了 子弹属性.区域定位area 才折；
# 方向词在认到 linkageWords（现 联弹）之后才看，所以 横向机枪联弹／纵向机枪联弹 按前缀自动归入，不必逐个列名
# 80×170 那层只对 kindWords 命中的近战类生效，联弹不在 kindWords 里（非近战联弹射出多少算多少，制作组 2026-10-06 定）
# pierceSegmentRules（穿刺子弹段数放大）：穿刺 ×pierceFactor（现 2）、次级穿刺 ×secondaryPierceFactor（现 1.5），逐颗乘在自己的 霰弹值 上；
# 判定必须先认 secondaryPierceWords 再认 pierceWords —— 「次级穿刺子弹」含「穿刺」，顺序反了会被当 2 倍（运行期 BulletTypesetter 就是这么误收的，量段数不跟它）
# armorRules（霸体系数五档）：可击飞 = 击倒 与 倒地 两段各自都有**生效**的击飞代码（统一函数 airborneCallWords 或内联写法 inlineAirborneWords，去空白后匹配）**且**该段确实摆了元件；
# 元件名（airborneInstanceWords）与被注释掉的代码都不算证据（匹配前先剔行注释与块注释），只摆了名字叫击飞的元件是美术摆放、判不可击飞；airborneInstanceWords 现在只用来把 concerns 的原因写准
# 击退长短看 被击 段每发受创动画到 动画完毕 的帧数，比 longKnockbackFrames（现定 9，判「大于」）；多发改读法用 knockbackReading（any/all/mean）
# 整数档之上还带韧性小数位：读面板 韧性系数（census 的 tenacityField），高于 20 时每 20 点加 0.1、上限 0.5（Excel H34），
# 常量在 core 的 superArmorDecimalFromTenacity、由 proposeAttackFlags 在取档后合成 —— 这是观测通道唯一读面板的一处，改标准改代码不改 armorRules
# 逐行查验与改数都在 data/monster-flag-table.csv（UTF-8 BOM + CRLF，Excel 直接开）：一行一怪，十项系数各一列，
# 空着表示「这格不改」；改完跑 npm run monster-flags-table-apply 写回 data/enemy_properties/*.xml。
# 表列按表头名定位，主线进度/档次描述/超出范围/误差值 都是派生列、读回时忽略；全量表的 数据文件 列已于 2026-10-06 删掉（该值仍参与排序，只是不再占列；超范围表仍带这一列）
# 全量表行序 = 阶段升序 → 同阶段内 档次系数 升序 → 同数据文件聚片 → 模板名（缺阶段/缺档次的排最后；制作组 2026-10-06 第二次改口改的就是这张表）
# 档次描述的门槛只取各档下限（8~9 按 8 起算），落在两档之间按就近档写「低级精英+／高级精英-」，四舍五入进档
# 同批另出两张只读投影：monster-flag-out-of-range.csv（系数超出参考区间，档次越界的行整块置顶，块内与其后都按 超出倍数 降序 → 阶段 → 模板名）与 monster-flag-high-error.csv（复算面板对不上，
# 含制作组点名档次的全部行）。缺 <阶段> 又反查不到的行不单独成表，看全量表里那格空着；判定「无需标识」的模板登在
# monster-census.json 的 noFlagTemplates，制作组点名的档次登在 humanTierFactors，两处都不进反推的自由量
# HEAD 里那颗 档次系数 被制作组认定只是当初预估的行登在 estimatedTierTemplates：只摘 档次系数 放回搜索并重算写回，同一行其余已提交标识（含 阶段）照旧钉住（现量 敌人-双喷少女、敌人-特警僵尸）
# monster-flag-human.csv（人工表）只记 git HEAD 里已完整打标的行（除 速度系数 外十项齐全；速度系数 来自移动速度定义档、不算人工输入）：
# 印的是 HEAD 那份原文，不是盘上现值 ∪ 工具候选。这批行的标识不是工具识别出来的，所以从前三张表里整块移出（制作组 2026-10-07 口径），
# 只读不改；现量 27 行 = 本次一个自由量都没有的 27 行，与全量表的 143 行不重叠。留 数据文件 与 标识行 两列方便跳回 XML 原文
# 档次的搜索网格不受参考区间约束（core 的 tierFitCandidates：0.1~0.9 每 0.1、1~10 每 0.5、11 起每 1，解顶到上界按块加长到 200）；
# 参考区间只用来登记越界，越界值照常写盘并报警，不夹紧
# 全量表把 阶段 填 0 = 这只怪整行排除（面板待重做/临时下线）：0 会写进 <标识>，但该行不反推、不产候选、不进任何一张查验表与统计，
#   只保留从 SWF 实测到的 攻速/倍率/段数/霸体；table-apply 遇 阶段=0 只写 阶段 这一格，其余九格即使填了也跳过

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
