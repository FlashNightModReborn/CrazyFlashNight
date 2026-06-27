# 武器平衡留档与复现设计（agent 友好）

> 把"依赖人类自觉的 Excel 数值平衡"升级为**进 git、可复现、可审计、agent 可独立操作**的闭环。
> 状态：设计 + 追月连弩试点（2026-06-26）。落地路线见 §8。

---

## 0. TL;DR

- **病根**：重算一把武器平衡所需的 6~7 个输入系数（双枪/穿刺/伤害类型/霰弹/弹夹价格/加权层数/种类）**只活在不进 git 的 Excel 里**，游戏 XML 只存输出（power/price）。→ 谁都无法从数据复现/审计一把武器是怎么平衡的。
- **方案**：在武器 XML 加结构化 `<balance>` 记录，**只装 XML 里没有的那几个系数**，使其成为**进 git 的平衡单一真值**，取代 Excel。
- **闭环**：`<balance>` 系数 + `<data>` 数值 → 工具 `calc weapons` 重算 → 校验门断言 `averageDPS≈balanceDPS`（或实际 power≈推荐）→ 不符即红。
- **落点**：重算在 **工具/校验门**（权威），DPS 展示在 **web tooltip**；**AS2 不动**（已有 `WeaponDpsEstimator` 服务 AI 选武器，是另一套"持续 DPS"）。

---

## 1. 背景与诊断

- **平衡模型成熟且已代码化**：Excel（16+ 互锁列，带 level 分段 + sigmoid 防钻空）→ `tools/cf7-balance-tool` 的 TS 内核（`baseline-extracted.json` 为权威真值，标定 <0.1%，6 大品类 25 输出列全过）。
- **工具 ~90% 就绪**：16 个 CLI 命令全 JSON；XML 读写**无损**（位置 patch 解析，保 BOM/属性序/缩进，89/89 round-trip）。
- **根因 = 平衡输入不在数据里**（下表）。
- **执行缺口**：① `npm install` 没跑过 → CLI 调不动；② `calc` 需要的系数 XML 没有 → calc↔XML 断层；③ `data/items/weapon_weighting_workflow.md` 是**简化/陈旧公式**，勿用，以工具为准。

### 输入字段来源（枪械，权威见 `packages/core/src/formulas/weapons.ts`）

| 输入 | TS 字段 | 来源 | 取值 |
|------|---------|------|------|
| 限制等级 | level | **XML `<data><level>`** | — |
| 子弹威力 | bulletPower | **XML `<data><power>`** | — |
| 射击间隔 | shootInterval | **XML `<data><interval>`** | ms |
| 弹容量 | magSize | **XML `<data><capacity>`** | — |
| 重量 | weight | **XML `<data><weight>`** | — |
| 冲击力 | impact | **XML `<data><impact>`** | — |
| **双枪系数** | dualWieldFactor | **`<balance>`（XML 没有）** | 长枪1 / 短枪2 |
| **穿刺系数** | pierceFactor | **`<balance>`** | 非穿1 / 普通穿2 / 喷火·次级穿1.5 |
| **伤害类型系数** | damageTypeFactor | **`<balance>`** | 物理1 / 魔法2 / 真伤3 |
| **霰弹值** | shotgunValue | **`<balance>`** | 霰弹填散射数；爆炸类4；默认1 |
| **弹夹价格** | magPrice | **`<balance>`** | 经济输入（补满一夹弹药的成本） |
| **额外加权层数** | extraWeightLayers | **`<balance>`** | −1~4（档位） |
| **种类系数** | categoryFactor | **`<balance>`（可选）** | 定价乘数，默认1 |

> basePower：长枪 `power*1.5+30`，短枪 `power+20`（由 dualWieldFactor 区分）。
> 价格：`金价 = level×3900×1.6^层数×种类系数×1.6^(伤害类型−1) / 双枪系数`；K点 `level×120×1.5^层数×…`。

---

## 2. 平衡记录 schema（结构化 `<balance>`）

放在 `<item>` 内、与 `<data>` 同级。**只装 `<data>` 里没有的输入**，绝不重复 power/interval/capacity/level/weight/impact。

```xml
<data> … 现有数值，不动 … </data>
<balance>
  <dualWield>1</dualWield>        <!-- 双枪系数：长枪1 / 短枪2 -->
  <pierce>1</pierce>             <!-- 穿刺系数：非穿1 / 普通穿2 / 喷火·次级1.5 -->
  <damageType>1</damageType>    <!-- 伤害类型系数：物理1 / 魔法2 / 真伤3 -->
  <shotgun>1</shotgun>          <!-- 霰弹值：散射数；爆炸类4；默认1 -->
  <magPrice>0</magPrice>        <!-- 弹夹价格（经济输入） -->
  <weightLayers>0</weightLayers> <!-- 额外加权层数 −1~4（档位） -->
  <category>1</category>        <!-- 种类系数，默认1，可省 -->
  <formula>1</formula>          <!-- 公式版本号，便于将来迁移 -->
</balance>
```

- **结构化子节点**（非 JSON 串）：git diff 友好、无需 XML 转义、工具的无损 patch I/O 原生支持、人/agent 都好读。
- 复用并扩展了原 `weightlevel`（死字段，无运行时读取）的意图，但纳入完整 `<balance>` 块。
- 运行时安全：游戏 AS2 不解析 `<balance>`（透传字段），不影响战斗。

---

## 3. 系数决策表（把"人脑判断"文档化 → agent 可复现）

agent/人按此表从武器的客观属性推出系数，**不再凭记忆**：

| 系数 | 判定依据 | 规则 |
|------|----------|------|
| `dualWield` | `<use>` | 长枪→1；手枪/手枪2→2 |
| `pierce` | 子弹是否穿透 / 武器定位 | 普通不穿→1；明确穿透弹→2；喷火、次级穿刺、链式→1.5 |
| `damageType` | `<data><damagetype>`/`<magictype>` 与元素 | 物理/无→1；魔法（含元素）→2；真伤/无视防御→3 |
| `shotgun` | `<data><split>` 与机制 | 单发→1；霰弹→散射弹数；爆炸/AOE→4 |
| `magPrice` | 弹药稀缺度（设计选择） | 普通弹低、稀有弹高；**游戏设计师定**，记录留痕即可复核 |
| `weightLayers` | 获取方式/稀有度档位 | 练习/低标→−1~0；商店/掉落→0；K点/合成→1；稀有/高价→2；史诗→3；活动/开发者→4。**可由现价反验**：`金价≈level×3900×1.6^层数` |
| `category` | 特殊定价乘数 | 默认1，特殊品类才改 |

> 这张表是 agent 填法的核心契约——把原本只在作者脑中的判断变成可查、可审、可复现的规则。

---

## 4. 公式契约与"两种 DPS"

- **权威 = `tools/cf7-balance-tool`**（TS，已标定 <0.1%）。`weapon_weighting_workflow.md` 是旧简化版，**勿用**（本设计落地后应纠正/废弃该文档）。
- 平衡逻辑：`balanceDPS` = 该 level+系数+档位下的**目标** DPS；`averageDPS` = 当前 power 算出的**实际** DPS。**调 power 使 average≈balance** 即平衡达标。
- **两种 DPS 不要混**：
  - **平衡/加权 DPS**（Excel/工具指标，需系数+重公式）→ 服务**作者/平衡核对**，算在工具。
  - **持续 DPS**（`scripts/类定义/org/flashNight/arki/unit/UnitAI/combat/WeaponDpsEstimator.as`，需角色上下文）→ 服务**AI 选武器**，已存在，不动。
  - 字符串"反求"主要服务前者；重公式放工具/web，**不进 AS2**。

---

## 5. agent 填一把武器的工作流（headless，可复现）

```
前置（一次）：cd tools/cf7-balance-tool && npm install
```

1. 读武器客观属性（`<use>/<damagetype>/<split>/bullet/level/price` 等）。
2. 按 §3 决策表推出 6~7 个系数（含由现价反验 weightLayers）。
3. 写 `<balance>` 记录（§2）到该 `<item>`。
4. 组装 WeaponInput（英文键）= `<data>` 数值 + `<balance>` 系数，跑：
   ```
   node packages/cli/src/index.ts calc weapons --input weapon-input.json
   ```
   读 `output.averageDPS / balanceDPS / weightedDPS / recommendedGoldPrice`。
5. 调 `<data><power>` 使 `averageDPS≈balanceDPS`（或直接采纳推荐），用工具无损写回：
   ```
   node packages/cli/src/index.ts xml set --file <xml> --path <…/power> --value <n> --in-place
   ```
   多字段用 `project batch-set --input payload.json --output-dir …`。
6. 跑校验门（§6）确认闭环。

> calc 入参是**英文键**（直传 `computeWeaponRow`）；calibrate/query 才做中文列名映射。

---

## 6. 校验门设计（治本，仿 `validate-equip-fn-coverage.js`）

**已实现** CLI `balance-check` 命令（`npm run balance-check`）：

1. 扫描 `data/items/武器_*.xml` 中带 `<balance>` 的 `<item>`。
2. 组装 WeaponInput（`<data>` 数值 + `<balance>` 系数）→ 调 `@cf7-balance-tool/core` 的 `computeWeaponRow`。
3. 断言（两种模式）：
   - **模式 A（forward，新武器/严格）**：实际 `power` 算出的 `averageDPS` 与 `balanceDPS` 在容差带内（如 ±15%）。
   - **模式 B（band，旧武器/宽松）**：`averageDPS` 落在 `balanceDPS` 的 [0.5×, 1.3×]（对齐工具 `validate` 的现有阈值）。
4. 越界 → 打印 `武器名 / 实际DPS / 目标DPS / 偏离%` 并 `exit 1`。
5. 接入：独立命令 + 可挂 `validate-doc-governance.js` 或 CI；本质是"提交即验平衡"。

效果：平衡从"不可审计的 trust me"变成"机器可复现核对"；agent/手填错当场红。

---

## 7. 反求 / 显示落点

- **算**：工具 / 校验门（权威，提交时）。
- **显示**：web tooltip（`launcher/web/modules/tooltip.js`/`kshop.js`）读 `<balance>`+`<data>` 算并展示 DPS/档位——浏览器原生 JSON、不动 AS2 运行时。
- **AS2**：不动。其 `WeaponDpsEstimator` 是给 AI 的"持续 DPS"，与本"平衡 DPS"职责不同，无需重复。

---

## 8. 落地路线 + 前置

| 阶段 | 动作 | 状态 |
|------|------|------|
| 前置 | `npm install`（解 #1 阻塞）；可选 payload-gen helper（按武器名生成 batch payload） | 待做 |
| 试点 | 追月连弩：写 `<balance>` → calc → 核对（见本轮试点记录） | 进行中 |
| 校验门 | `tools/validate-weapon-balance.js`（§6） | 待做 |
| 回填 | 逐类给现有武器补 `<balance>`（优先有 lifecycle/争议的），可用 import-excel + baseline 反查历史系数 | 待做 |
| 显示 | web tooltip DPS（§7） | 待做 |
| 文档治理 | 纠正/废弃 `weapon_weighting_workflow.md`；AGENTS.md/data-schemas.md 加 `<balance>` schema 指针 | 待做 |

- **向后兼容**：无 `<balance>` 的武器 → 校验门跳过（或走模式 B 的纯 stat band 估算）；运行时不受影响（透传字段）。
- **单一真值**：`<balance>` 进 git 后，Excel 退化为一次性 legacy import（`import-excel` 仍可用于历史系数反查回填）。

---

## 9. 防 hack：依据驱动 + 系数交叉校验（2026-06-26 精化）

**风险**：平衡公式多输入，若"固定目标 DPS、放任系数浮动"，可用**等效依据**凑出想要的 power（谎报 pierce=2 撑高伤害预算、或抬 weightLayers 拔档位）。

**双重防线**：
1. **系数必须有客观依据**：每个非平凡系数在 `<rationale>` 写明绑定的**可验证武器属性**（pierce=2 ⟺ 子弹真穿透；weightLayers=3 ⟺ 获取/稀有度真到该档），不是自由旋钮。人/agent 据此读懂"为什么是这个值"。
2. **校验门交叉校验系数↔客观数据**（不止重算 DPS）：
   - `dualWield` ↔ `<use>`（长枪1/手枪2）
   - `damageType` ↔ `<data><damagetype>`/`<magictype>`
   - `weightLayers` ↔ `<price>`（应满足 `price≈level×3900×1.6^层数`，本设计已实证追月连弩 WL=2）
   - `pierce` ↔ 子弹穿透配置（bullets_cases）
   不符即红 → **结构上堵死"等效依据 hack"**。

**schema 补充**：`<balance>` 加 `<rationale>`（自由文本，承载依据）；可选 `<class>`（如 `压制机枪`）便于规则化。
**「存全部参数？」结论**：存**系数 + 目标档位 + rationale**，**不复制** `<data>` 的 power/interval/cap（复制 = 第二处漂移面）；需要"一处看全"时由**工具写 `<derived>` 快照**（balanceDPS/推荐power，工具/校验门生成，绝不手维护）。

**压制机枪类（capacity>150）**：DPS 公式下换弹项被摊薄、cycleDamage 巨大但 averageDPS 归一；其价值在**持续压制**而非单体，故 weightLayers/系数取舍必须在 `<rationale>` 说明（如"压制定位，单体 DPS 让位于持续火力"），并建议打 `<class>压制机枪</class>` 以便后续按类给默认系数。

## 10. 求解器（auto-solve，替代人肉试错）

原版"凑平衡"= 人肉试错、不可自动化。但公式是 `inputs→DPS` 的纯函数，**求解 = 逆问题**：

- **单未知（power）求目标 DPS = 单调 1D 问题**，二分/牛顿稳解（已原型验证）。覆盖 ~90% 场景。
- **通用形态**：固定 N−1 个输入，解 1 个自由量（通常 power）对目标（`averageDPS=balanceDPS` 自洽，或指定 DPS）。多未知欠定 → 需多目标或多固定，文档约定"固定到只剩一个自由量"。
- **追月连弩 demo（2026-06-26）**：固定 level50/interval200/cap7/系数/WL，二分解得 **power≈3400** 使 `averageDPS≈balanceDPS≈25510`；跨档位敏感度 WL1/2/3 → power 3380/3399/3415、金价 312k/499k/799k。对照旧约束(cap50/interval150) 只需 power≈1238——**约束变化对单发威力的影响一目了然**。
- **已实现并折进 CLI（2026-06-26）**：core `solveWeaponPower`（`packages/core/src/formulas/weapon-solve.ts`）+ CLI 子命令 `solve weapons` / `balance-check`：
  - `npm run solve -- weapons --input <fixed.json> [--target <dps>]` — 固定其余、二分解 power 命中目标（默认 balanceDPS）。
  - `npm run balance-check` — 扫全部带 `<balance>` 武器，重算 + DPS 带 + dualWield↔use + price↔公式 交叉校验，失败 exit 1。
  - 追月连弩实证：cap7/interval200 解得 **power=3399**（averageDPS=balanceDPS=25510）；balance-check `ok`。
- **构建已修（2026-06-26）**：`tsc -b core+xml-io+cli` 现 exit 0。两个根因——① 陈旧 `.tsbuildinfo` 让 `tsc -b` 误判"已构建"而跳过 emit（dist 缺失 → 跨包 `@cf7-balance-tool/*` TS2307 级联 + implicit-any），`tsc -b --force` 重建即出 dist；② `fast-xml-parser` 被 xml-io 使用却**从未在任何 package.json 声明**（原始 `npm install` 因此漏装），已补进 `xml-io`/`cli` deps。注：web/electron GUI 构建另需完整 `npm install`（electron/react/vite），不在 CLI 范围。
- **规模化后**：积累各武器 `<rationale>` → 提炼每类默认系数规则 → 参数化规范 / 自动建议系数（**先有数据再形式化**，勿过早固化）。

## 11. 相关文件
- 公式内核：`tools/cf7-balance-tool/packages/core/src/formulas/weapons.ts`、`economy.ts`
- CLI：`tools/cf7-balance-tool/packages/cli/src/index.ts`（calc/xml set/batch-set/calibrate/query）
- 权威真值：`tools/cf7-balance-tool/baseline/baseline-extracted.json`
- 标定：`packages/core/tests/formulas/*.calibration.test.ts`
- 运行时持续 DPS（勿混）：`scripts/类定义/org/flashNight/arki/unit/UnitAI/combat/WeaponDpsEstimator.as`
- 陈旧勿用：`data/items/weapon_weighting_workflow.md`
