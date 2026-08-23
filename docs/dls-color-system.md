# CF7:ME · DLS / θ-域 视觉色谱谱系

> **文档性质**：世界观-视觉接口文档。把 Web Panel 的配色锚定到 DLS、θ-域、信号与派系设定的共享框架，防止“青/蓝/绿”随意漂移。
> **最后核对世界观基线**：`docs/worldbuilding` v2.15.4（2026-06-29），核心依据 [01-总纲](worldbuilding/01-总纲.md)、[05-DLS-原体同源假说](worldbuilding/05-DLS-原体同源假说.md)、[09-药剂产业链与DLS融合](worldbuilding/09-药剂产业链与DLS融合.md)、[10-可观测量与能量框架](worldbuilding/10-可观测量与能量框架.md)。

---

## 1. 设计目标

1. **物理锚定**：颜色不是“好看就行”，而是 DLS 物质状态或 θ-域效应的可视化。
2. **统一技能与调制**：技能被重新解释为“人体通过信息素/改造/修炼对 DLS / 强化石科技的直接延伸”，因此技能面板与装备调制共享晶体青主色，只在结构与交互密度上区分。
3. **商业色谱降级为功能色**：K 点商城的主强调色已收敛到 DLS 晶体青；价格、余额等交易功能仍可用琥珀/金作为辅助识别色。
4. **给 CSS 变量当 canonical 来源**：任何涉及 DLS、θ-域、技能、调制的面板颜色，优先从这里取值，而不是在 `panels.css` 中新增硬编码色值。

---

## 2. 与既有世界观的接口

| 世界观事实 | 来源 | 视觉映射 |
|---|---|---|
| DLS 是非地球常规物质，高对称晶格 | 01 公设一 / 05 三 | 晶体青 `#3dd5ff` 为 DLS 原生代表色 |
| DLS 切割保留本征频谱但降低 Q | 10 DLS 切割 | 深色/低饱和青用于“激活但未共振”状态 |
| 技能 = 人体对 DLS / 强化石科技的神经-信息素整合 | 09 / 10 | 技能面板也使用晶体青，暗示其与调制同源 |
| θ-域信息拓扑分支（模因） | 01 规则4-5 | 紫罗兰用于模因/信息类 UI（预留） |
| 信号 = θ-域耦合在电磁频谱的投影 | 03/06 | 低饱和青灰用于信号/诊断文本；电蓝仅用于信息/控制平面提示 |
| 能量释放（SSB 局部有序化抽热/放热） | 10 宏观能量框架 | 琥珀/金用于高能释放、锻造、强化成功 |
| 失控纳米机器人 / 逆向地球化 | 09 四驱动 | 病态锈红/暗黄仅用于异常/腐蚀状态（预留） |

---

## 3. DLS 物质光谱（Material Spectrum）

用于所有与 DLS 材料直接交互的界面：装备调制、技能、强化石、星座武器、DLS 道具、插件档级。

| 状态 | 色名 | Hex / RGBA | 使用场景 |
|---|---|---|---|
| **DLS 原生晶体** | `dls-crystal` | `#3dd5ff` | 装备调制、技能主强调色、激活态、按钮填充 |
| **DLS 亮晶体** | `dls-crystal-bright` | `#8be0f1` | hover、高亮数值、选中标识 |
| **DLS 深晶体** | `dls-crystal-deep` | `#1e90b3` | 边框、次级描边、hover 加深 |
| **DLS 暗淡晶体** | `dls-crystal-dim` | `#0f4a5c` | 禁用/未激活 DLS 组件边框 |
| **DLS 柔和晕** | `dls-crystal-soft` | `rgba(61,213,255,.12)` | 背景晕染、选中底色 |
| **DLS 半透明晕** | `dls-crystal-faint` | `rgba(61,213,255,.45)` | 次级光晕、进度条未完成段 |
| **DLS 共振光晕** | `dls-glow` | `rgba(61,213,255,.18)` | 阴影、光晕、内发光 |
| **DLS 高能相（热力学偏向）** | `dls-energetic` | `#f1b83b` | 强化成功、能量释放、高 Q 谐振提示 |
| **DLS 信息拓扑偏向** | `dls-memetic` | `#9d5cff` | 模因相关 DLS 装备/插件（预留） |

> CSS token 前缀建议：`--dls-crystal*`、`--dls-glow`、`--dls-energetic`。
> 当前 `panels.css` 已收敛 `--tuning-dls*` 等局部变量到 `--dls-*` 族。

---

## 4. θ-域表达光谱（Field Expression Spectrum）

用于信号设备、WP-FQ 干扰器、符线/心网、信息/帮助提示等界面；**技能面板不再使用此谱系**。

| 分支 | 色名 | Hex / RGBA | 使用场景 |
|---|---|---|---|
| **信息 / 控制平面** | `theta-kinetic` | `#5e8cff` | 帮助、提示、可点击说明、诊断高亮 |
| **信息高亮** | `theta-kinetic-bright` | `#8bb1ff` | hover、信息类高亮数值 |
| **信息柔和** | `theta-kinetic-soft` | `rgba(94,140,255,.12)` | 信息背景晕染 |
| **信息拓扑 · 模因** | `theta-memetic` | `#9d5cff` | 模因武器、抗性、信息类技能（预留） |
| **信号 / 控制平面** | `theta-signal` | `#4a90a4` | 诊断文本、信号强度、sub-ELF 0.77Hz 可视化 |
| **退相干 / 噪声** | `theta-incoherent` | `#6e7a80` | 环境噪声、不可施放提示 |

> **关键决策**：技能面板曾迁移到 `theta-kinetic #5e8cff`（电蓝），但实际表现与 DLS 青相比辨识度不足且显得冷硬。基于“技能是 DLS / 强化石科技延伸”的叙事设定，技能面板重新收敛到 `dls-crystal #3dd5ff`。

---

## 5. 商业 / 派系 / 档案色谱（非 DLS）

这些颜色与 DLS 无关，作为面板身份识别保留。

| 系统 | 色名 | Hex | 叙事理由 |
|---|---|---|---|
| **K 点商城** | `dls-crystal` | `#3dd5ff` | DLS / 强化石科技支撑的交易终端；与技能、调制共享主色 |
| **NPC 商店** | `commerce-coin` | `#e5a64d` | 金币/以物易物 |
| **合成工作台** | `forge-ember` | `#f1b83b` | 锻造/化学/材料转化，偏热力学 |
| **库存 / 战备箱 / 仓库** | `archive-paper` | `#e5e5e5` | 档案、纸质、 tactile |
| **情报面板** | `archive-gold` | `#d8b656` | 联合大学/档案馆的旧纸与烫金 |

---

## 6. UI 语义色（跨面板统一）

无论皮肤如何，以下语义必须在所有面板保持一致，禁止每个皮肤自己发明“成功绿”。

| 语义 | 推荐色 | 使用场景 |
|---|---|---|
| `success` | `#78bc73` | 可合成、可提交、已同步、容量充足 |
| `warning` | `#e5a64d` | 忙碌、待确认、容量紧张、旧 token |
| `danger` | `#df665b` | 丢弃、卸下、破坏性操作、余额不足 |
| `info` | `#5e8cff` | 帮助、提示、可点击说明 |
| `disabled` | `#646e75` | 不可用按钮、只读文本 |

> 当前 `crafting` 使用 `#78bc73` 表示可合成，`equipment-tuning` 使用 `#d08b80` 表示卸下，`kshop` 使用 `#c8ff4c` 作为普通交互。建议把 `success/warning/danger/info` 抽成 `--wb-semantic-*`，在皮肤层只覆盖暗部色板，不覆盖语义色。

### 6.1 Launcher 黑铁终端族（`--launcher-*` / `--term-*`）

启动外壳（bootstrap/welcome）与复用终端语言的面板（settings 等）共享一套独立于 DLS 面板映射的黑铁色板，真源在 `css/workbench/tokens.css`：

| 角色 | token | 基值 |
|---|---|---|
| 锈红（品牌 / 危险 / 区块身份） | `--launcher-rust` 族 | `#b83a2e` |
| 骨金（标题与主文案） | `--launcher-bone` | `#c8b28a` |
| 尘灰（次要文案） | `--launcher-dust` | `#6a6258` |
| 背景 | `--launcher-bg-0/1` | `#05070a` / `#0c0e12` |
| 正文 | `--launcher-copy` | `#d4d8dc` |

终端族派生 token（2026-08-23 新增，全部 color-mix 自既有色板，不引入新色相）：

- 表面层级：`--term-surface-veil`（薄纱覆盖）、`--term-surface-inset`（控件/凹槽底）、`--term-surface-card`（卡片渐变）——收敛各页面一次性硬编码的近黑底。
- 墨色阶梯：`--term-ink-hi/md/lo/faint`——收敛一次性硬编码的灰阶字面量。
- 控件度量：`--term-control-h`（统一控件高度）。

共享组件层 `css/terminal.css`（bootstrap.html 与 overlay.html 均直接 link）：品牌铭牌 `.term-brand-seal`、kicker `.term-kicker`、标题分隔线 `.term-heading-rule`、语义状态点 `.term-status-dot[data-state]`、四角 L 角标 `.corner-brackets` 与单角 `.term-corner-tick`、扫描线 `.term-scanlines`、切角按钮族 `.term-btn`、终端卡片 `.term-card`。组件只组合 token、不定义色值；页面通过组件上的 `--term-*` 旋钮变量调度量。

---

## 7. 面板 → 强调色映射（canonical）

| 面板 | 主强调色 token | 当前 CSS 值 | 备注 |
|---|---|---|---|
| `workbench` / 库存 | `--wb-accent` | `#e5e5e5` | 档案白， tactile serif |
| `character-build` / `profile` | `--wb-text`（档案白系）+ `--wb-accent` → `--dls-crystal` | `#dff4f8` + `#3dd5ff` | 主角装备/档案混合皮肤：档案白承载信息，晶体青只强化诊断、焦点与已选状态 |
| `kshop` | `--wb-accent` → `--dls-crystal` | `#3dd5ff` | 与技能、调制统一为 DLS 晶体青；保留价格/结算中的琥珀作为功能色 |
| `npcshop` | `--wb-accent` | `#e5a64d` | 商业金 |
| `crafting` | `--wb-accent` | `#f1b83b` | 锻造琥珀；可与 `dls-energetic` 对齐 |
| `skills` | `--wb-accent` → `--dls-crystal` | `#3dd5ff` | 与调制统一为 DLS 晶体青 |
| `equipment-tuning` | `--wb-accent` → `--dls-crystal` | `#3dd5ff` | 保持，收敛变量名 |
| `intelligence` | `--wb-accent` | `#d8b656` | 档案金 |

### 7.1 主角构筑 / 档案混合皮肤

`character-build` 与 `profile` 是同一套 protagonist-facing 装备共振接口，不复用 K 点商城的商业语气。常态名称、原始属性、说明和档案层级使用档案白/中性灰；DLS 晶体青用于诊断仪表、键盘焦点、选择源和临时预览边界，不能把整页普通信息都染成青色。

在该 profile 内，当前轻装读数使用 `success`、重装读数使用 `danger`，标准负载保持档案白中性色；`warning` 仍保留给容量临界、待处理等通用语义。旧 PlayerInfo 的绿—黄—红负重色带是有出处的数据可视化例外，只能通过 character profile 的三个局部 `--character-weight-band-*` token 消费，不能反向改变普通控件状态。候选装备、预测数值和普通物品筛选不得借用这些颜色暗示尚未发生的结果。筛选器继续使用 inventory 的中性灰状态，即使外层处于 `data-workbench-skin="character"`，也不改成 DLS 青色分类导航。

Character Build 的顶部候选操作、完整/紧凑实体格、个人信息 3×3 分组、八抗性图标和单 Canvas 放大预览都继续服从这套混合皮肤；结构优化不引入新的 DLS 色值。抗性 inline SVG 使用 `currentColor` 并只作装饰，文字/原值才是信息权威；武器威力的 `log10` 压缩只是几何表达，不对应新的 DLS 能量色谱。纸娃娃放大预览沿用同一 stage/Canvas 与既有 token，不另造“预览专用”颜色系统。

---

## 8. 给 CSS 的迁移建议

1. **新增变量族**（在 `panels.css` 最前或独立 `dls-tokens.css`）：
   ```css
   :root {
     --dls-crystal: #3dd5ff;
     --dls-crystal-bright: #8be0f1;
     --dls-crystal-deep: #1e90b3;
     --dls-crystal-dim: #0f4a5c;
     --dls-crystal-soft: rgba(61,213,255,.12);
     --dls-crystal-faint: rgba(61,213,255,.45);
     --dls-glow: rgba(61,213,255,.18);
     --dls-energetic: #f1b83b;
     --dls-memetic: #9d5cff;

     --theta-kinetic: #5e8cff;
     --theta-kinetic-bright: #8bb1ff;
     --theta-kinetic-soft: rgba(94,140,255,.12);
     --theta-memetic: #9d5cff;
     --theta-signal: #4a90a4;
   }
   ```
2. **装备调制**：把 `--tuning-dls` 改为 `--dls-crystal` 的 alias；`--tuning-dls-deep` → `--dls-crystal-deep`；`--tuning-dls-dim` → `--dls-crystal-dim`。
   新增局部语义 token（仅在 `.equipment-tuning-view` 内生效，避免向全局扩散）：
   ```css
   --tuning-active-border: var(--dls-crystal);
   --tuning-active-bg: rgba(61,213,255,.08);
   --tuning-active-glow: 0 0 8px rgba(61,213,255,.12);
   --tuning-active-inset: inset 0 0 0 1px var(--dls-crystal-deep);
   --tuning-tier-gold: #d6bc43;
   --tuning-danger: #df8178;
   --tuning-convert-arrow: #5cd7ee;
   --tuning-delta: #d4bd85;
   --tuning-fast: #e1b75c;
   ```
   这些 token 用于统一 tab 激活态、level mark 选中态、卡片选中态、卸下危险色、交换箭头、数值差分与快速模式按钮。
3. **技能面板**：把 `--skill-energy` 改为 `--dls-crystal`，并在 `.skills-panel` 内将 `--theta-kinetic*` 覆写为 `--dls-crystal*` 的 alias，使现有 `var(--theta-kinetic*)` 规则自动渲染为晶体青。
4. **商城**：把 `--wb-accent` 改为 `--dls-crystal`；价格、余额等商业功能色可保留琥珀 `#ffd367` / `#ffc447` 作为辅助识别。
5. **语义色**：新增 `--wb-semantic-success` 等，并让 `crafting` 的可合成侧条、`tuning` 的危险卸下、`kshop` 的最终结算统一使用。

---

## 9. 迭代与收敛

本文件从实际验证中经历了两轮收敛：

- 最初把技能强调色从 `#4ec9f0` 迁移到 `#5e8cff`，但在实机中发现电蓝显得冷硬且与 DLS 青区分度不足。
- 随后根据“技能是人体对 DLS / 强化石科技的延伸”这一叙事，将技能重新收敛到 DLS 晶体青 `#3dd5ff`；商城也统一至此主色，仅保留价格/余额等商业功能色用琥珀辅助识别。
- 为后续任何涉及 DLS、θ-域、技能、调制的面板提供唯一取色来源，减少 `panels.css` 中新增硬编码色的情况。

---

## 10. 版本

- **v1.4 · 2026-07-27** 确认 Character Build 顶部操作、候选 density、属性抗性图标与单 Canvas 放大预览仍使用 protagonist 档案白 + DLS 晶体青混合皮肤；结构变化不引入新色值，抗性 SVG 统一 `currentColor`。
- **v1.3 · 2026-07-26** 增加主角 `character-build/profile` 的档案白 + DLS 晶体青混合皮肤；冻结权威负重语义色边界，并规定普通物品筛选保持 inventory 中性。
- **v1.2 · 2026-07-18** 装备调制界面新增 `--tuning-active-*` 选中态原子与 `--tuning-tier-gold / --tuning-danger / --tuning-convert-arrow / --tuning-delta / --tuning-fast` 局部语义 token，统一 active/selected 视觉语言。
- **v1.1 · 2026-07-17** 技能面板收敛到 `dls-crystal #3dd5ff`；新增 `--dls-crystal-bright` / `--dls-crystal-soft` / `--dls-crystal-faint`；`theta-kinetic` 谱系改为仅用于信息/控制平面，不再用于技能。
- **v1.0 · 2026-07-17** 初始版本：建立 DLS 物质光谱、θ-域表达光谱、商业/档案色谱、语义色与面板映射。
