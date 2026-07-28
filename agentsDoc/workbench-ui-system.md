# 双栏工作台 UI 系统约束

**文档角色**：双栏工作台范围的布局、交互、美学与前端工程 canonical doc。跨 AS2 / Host 的协议与权威闭环仍以 [as2-web-panel-migration.md](as2-web-panel-migration.md) 为准，验证入口以 [testing-guide.md](testing-guide.md) 为准。
**最后核对代码基线**：commit `c4faf14460238c7ea3e85983f31dee8be1b79afa`（2026-07-28）；角色构筑 ↔ Skills 双向导航与原生 workbench nonce 已由 promotion commit `45b9748baa68786a52557239d5bd7c52869970f7` 正式发布并达到 `standard_entry_verified`。

本文适用于 `kshop`、`npcshop`、`crafting`、独立 `workbench`、角色构筑、嵌入式装备调制和 `skills` 中采用双栏工作台语言的视图。它约束玩家态 UI，不把 dev harness、诊断面板或协议调试页误当成生产视觉标准。

## 1. 不变量与职责边界

- 工作台逻辑画布固定为 `1024×576`，生产入口使用 `.panel-scale-shell + PanelScale.attach()` 等比铺满全 anchor；禁止在各面板复制缩放算法。
- Web 只呈现权威状态、收集 UI intent；价格、余额、材料、槽位、lease、token、可提交性和写入结果由 Host / AS2 领域链裁决。
- 共享层负责壳、可访问性、生命周期、视觉状态和机械交互；领域层负责 ViewModel、能力、文案、authority envelope 与 reconcile 规则。
- 完整/紧凑、skin、动画偏好都只能改变呈现，不得改变业务能力、payload、权限或安全边界。
- 玩家常态界面不显示 `callId`、lease、epoch、token、wire、协议状态等技术词；异常诊断可在明确的复制入口中提供脱敏信息。

## 2. 布局系统

### 2.1 布局 profile

面板选择语义 profile，不继续用面板名堆叠比例魔法数：

| profile | 用途 | 基本结构 |
|---------|------|----------|
| `catalog-decision` | KShop、NPC、合成、教师研习、调制预览 | 左侧浏览约 60%，窄 FlowRail，右侧权威决策约 40% |
| `archive-reference` | 材料档案等只读索引 | 左侧约 44% 稳定目录，右侧约 56% 详情；两栏分别滚动，选择按稳定 key 原位更新 |
| `transfer-pair` | 背包—战备箱、背包—仓库 | 两个可操作容器近似对称；容量差异只能做受控 token 覆盖 |
| `library-action-strip` | 技能管理 | 全宽库 + 固定 Hotbar；密度只作用技能库 |
| `library-decision` | 技能教师、调制候选 | 目录/候选 + 固定信息量的预览提交区 |
| `character-build` | 角色构筑 | 左右固定 `55:45`；左侧内层为弹性单 Canvas + 按内容收缩并贴右的 11 装备槽/4 药剂槽，不能把槽区右侧空白保留成无效列宽；右侧候选/调制决策区不得窄于 `360px`；55% 是 1024 下仍保持三列完整候选和八列紧凑图标的左倾上限；详细属性以全 body SecondaryPage 与编辑态互斥 |

`character-build` 的最低画布为 1024×576；“当前装备/候选预览”只改变同一个 Canvas 的合成输入，不生成第二个并排 Canvas。Character Build 每次从当前权威纸娃娃状态重新测量 `空手/长枪/手枪/手枪2/双枪/兵器` 六种 battle pose，合并一个带留白的结构骨架 envelope：`身体/脸型/发型/面具/屁股/大腿/小腿/脚` 参与取景，横向变化最大的手臂、手与武器只绘制、不参与缩小人物。相同身体投影下，切槽、武器候选、嵌入/放大迁移和 resize 使用同一几何结果；装备或外观权威变化必须重新测量，禁止复用只按 `panelInstanceId + gender` 建立的陈旧缓存。嵌入态允许姿态末端受控裁切，完整武器/动作查看由放大页的平移和缩放承担。该能力是 renderer 的 opt-in 输入；未传 envelope 的对话、佣兵与独立 dressup 页面仍保持逐次内容自适应。需要更大构图时，`character-build-doll-preview.js` 只把现有 `.character-build-doll-stage` 与 exact Canvas 临时迁入全 body SecondaryPage；不得复制 renderer、Canvas 或 current/preview state。打开时底层 body/header inert，Esc 后按原顺序放回 stage 并恢复 opener。放大页复用 `workbench-inspection-viewport.js` 的瞬态相机：滚轮或 `+/-` 缩放、主键拖拽或方向键平移、“全貌”/`Home` 复位；transform 只作用 exact Canvas，不作用 stage、候选覆盖层或 renderer 输入。关闭必须清零缩放/位移；嵌入态停用相机且不得吞掉 pointer、wheel 或键盘输入。该 profile 必须覆盖满 11+4、空/blocked、长中文、未知性别/缺素材、stats SecondaryPage 与完整键盘路径。stats 在最低画布下不得靠缩小中文字号硬塞：标题/footer 固定，正文使用单一、可聚焦的纵向滚动区，保留可见滚动提示、滚轮与键盘滚动，并在关闭后把焦点还给入口。任何新 profile 都必须先进入本文，说明适用角色、最小画布和验证样本；禁止只在单个 feature CSS 中创造隐式结构。

### 2.2 纵向节奏

生产工作台通常按“`48px` 顶栏 → PaneChrome / 筛选 → 可滚内容 → 决策 footer”排列。Character Build 是受控例外：左侧“外观与配置 / 当前构筑”的 PaneChrome 以标题复制区承载当前浏览摘要，摘要位于“当前构筑”右侧、放大预览入口左侧；固定 11+4 槽与“护具/武装/药剂”分组不再重复显示 `15 / 15`、`· 6/5/4` 等可从结构直接得出的计数。未选候选时保留语义 overlay 节点但整层隐藏，选中后才显示一行“预览 · 名称”。routine 浏览/读取/恢复提示不得再占用 pane 底部空间，底部只为 blocked/write/reconcile/error 等必须持续可读的异常信息让位。右侧候选动作直接并入“背包候选 / 候选对比”同一 PaneChrome 标题行；删除无领域决策价值的通用“详情”和任何钉住动作，装备上下文最多显示“装备 / 调制 / 卸下”三项，药剂提交短标签改为“装入”。完整动作语义保留在 `aria-label`；“装备/装入”是唯一主 CTA。1024×576 下动作组必须单行、不换行、不横向溢出；删除独立动作行以扩大候选区，候选可滚区底部也不再复制 action rail 或长快捷键说明。常态状态、指标和 action group 不应因为文字变化推动标题或关闭按钮。二级页从顶栏下沿覆盖整个 workbench body，不在底层双栏上叠半透明可点击内容。

PaneChrome 承担标题、面包屑、meta 和筛选工具；业务内容不得再造第二套局部顶栏。FlowRail 是关系提示，不是常亮主 CTA：待命时低能量，只有拖拽接收、权威 pending 或预览更新时提升亮度。

### 2.3 溢出与空态

- 横向滚动只允许领域明确需要的连续轨道；目录、卡片网格、面包屑和顶栏 action group 不得产生嵌套横向滚动。
- 玩家可见的纵向溢出面必须使用当前 skin 的共享窄轨、轨道与滑块 token，并显式移除 Chromium/Edge 的系统箭头按钮；目录、购物车、历史记录和二级结算不得在有内容时才突然回退为白色原生滚动条。视觉门至少包含一个真实 `scrollHeight > clientHeight` 的溢出 fixture，不能只在空列表上检查选择器存在。
- 可滚区域必须有明确的“窗口身份”：容器/目录、筛选路径、分页 offset/limit 与面板 session 相同，才属于同一窗口。纯选择变化必须按稳定 key 原位更新，不得清空并重建列表；数量、权威 preview、写后 snapshot/reconcile 或图标就绪状态须复用引用未变化的 key、仅重建新权威对象，并恢复 `scrollTop/scrollLeft`。原焦点 key 仍存在时须恢复到同一实体/子控件；排序或重排改变实体位置时，焦点实体必须保持在可视窗口内。筛选、分页、会话或自动回退到另一实体属于窗口语义变化，必须显式归顶或滚到新实体。
- 分类/筛选路径、分页窗口、工作台 operation、绑定实体或面板 session 改变时属于新窗口，必须显式从顶部开始。不得把“所有 render 都保留”或“所有 render 都归零”作为默认策略；owned 权威视图至少用 container + offset + limit + filterKey/filterSpec 判定窗口身份，领域自绘结算/详情列表遵循同一规则。
- full 模式必须能读到主名称和关键状态；空间不足时减少列数，不得把 full 退化成“略大的 compact”。
- 空态分为 `empty`、`filtered-empty`、`unavailable`、`error`；每种都提供下一步动作或原因，不用装饰填满空白。

### 2.4 角色属性 SecondaryPage

`launcher/web/modules/character-build/character-build-stats-view.js` 是角色属性页的只读 leaf presenter，专责格式化标量、绘制权威负重带、组内相对条和完整属性投影；它不持有 session、Bridge、候选选择或装备写入时序。现役 browser fixture 为 `launcher/web/modules/character-build/dev/stats-fixture.js`，固定 `CharacterBuildStatsSnapshot v1` 的 **9 组、47 行 exact shape**；fixture 只用于验证顺序、格式与降级，不是第二份游戏数值真源。

负重带的位置、分界与速度读数只消费 AS2 已投影的 `weightRatio`、`lightMediumThreshold`、`mediumHeavyThreshold`、`heavyThreshold` 与 `movementSpeed`。Web 不重算负重或速度公式，不把候选装备代入预测，也不复制 `UnitUtil` 等 AS2 公式。当前轻装读数使用 `success`、重装读数使用 `danger`，标准负载保持中性；`warning` 不表示正常状态。相对条只在整组均为有限非负值且不全为零时出现：武器威力先做 `log10(value+1)` 视觉压缩、再按同组最大变换值归一，并标注“对数相对量级”；抗性使用原值线性组内归一，并标注“当前组相对量级”。出现负数、缺值或全零时省略对应图表并保留原始明细。`log10` 不能进入 authority、AS2 公式、候选预测或 DPS。每一行继续显示带单位的原始权威值，禁止把条长解释为跨组战力或用图形替代原值。

完整 9 组 47 行采用 3×3 分组网格；抗性首屏摘要为 4×2，完整明细中的抗性组为 2×4。八种抗性可使用 inline SVG 帮助扫读，但图标必须 `aria-hidden`、使用 `currentColor`，中文字段名与原始权威值始终存在，禁止仅靠图形或颜色识别。

stats 页只允许一个可聚焦的纵向滚动区：header 与 footer 固定，打开时焦点直接进入该滚动区，滚动提示跟随 start/middle/end，支持滚轮、PageUp/PageDown，并在退出时恢复 opener；所有玩家可见 stats 正文不得小于 11px。`groups` 为空时显示 `unavailable`，不得填默认值；`weightRatio` 缺失/`null` 或负重阈值畸形时只撤掉负重带，47 行原始明细仍照常投影；相对组缺失、含缺值/负值或全为零时只省略对应图表，抗性明细图标与文字仍保留。现役资产与验证入口为：

| 路径 / 命令 | 职责 |
|-------------|------|
| `launcher/web/modules/character-build/character-build-stats-view.js` | stats 只读 presenter 与渐进降级 |
| `launcher/web/css/workbench/character-build-stats.css` | 档案白信息层、DLS 诊断/焦点、单滚动区和负重仪表 |
| `launcher/web/modules/character-build/dev/stats-fixture.js` | 9 组 47 行 exact browser fixture |
| `node tools/run-character-build-harness.js` | 独立三视口结构、exact rows、畸形阈值降级、滚动/焦点/reduced-motion |
| `node tools/run-character-build-workbench-harness.js` | 生产 controller + storage facade + fake Host 的三视口 stats/权威闭环 |
| `node tools/audit-workbench-ui.js --strict-warnings` | 新 CSS/JS 的颜色、字号、动效、模块阈值与依赖治理 |

## 3. 密度与实体格

共享尺寸基线：完整 owned 卡高度 `68px`；紧凑 owned 实体格 `48px`、图标 `40px`、间距 `4px`。KShop / NPC 目录 compact 使用固定 `54px` 图标瓦片，不把自适应列宽分摊到每张卡；目录 full 的可读列宽不得低于 `128px`。最低画布下仍须满足领域容量目标，例如战备箱 40 格、调制候选 25 格的无滚动可达性。独立战备箱是受控容量例外：紧凑态固定 `6×7`（末行留空）容纳 40 槽，卡片仍不得低于 `48px`，图标框/图像为 `38/34px`；这样为正文批量命令栏让出纵向空间，不得退回压缩卡高的 `5×8`。

所有向玩家提供完整/紧凑切换的生产视图，首次进入统一以 `compact` 为初始值；只有 `localStorage` 中已经存在该视图的显式 `full|compact` 偏好时才覆盖初始值。storage、Character Build 候选和 embedded tuning 共用 `panelId=workbench` 与同一 `cf7.itemgrid.mode.workbench`，不能因子路由切换生成第二份偏好。密度只影响呈现，不改变筛选结果、选择、拖拽/点击能力、批量操作、payload 或权威上限。

`full` 显示名称、核心 meta、价格/数量/状态与必要动作；`compact` 以图标和角标为主，隐藏语义正文后必须通过键盘可达的共享 tooltip 或可见的当前浏览摘要提供同等信息，不为此恢复通用“详情”动作。Hotbar、权威预览、材料核算和提交区不随目录密度压缩。

材料档案使用独立 `panelId=crafting-materials`：默认 compact 为 7 列、52px 图标格并以角标保留非零持有量，full 为 2 列、至少 58px 的名称/持有量/来源/用途行。密度切换必须同步键盘网格列数，保留稳定材料 key、选择、焦点和左右栏滚动；不能只改 CSS 后仍按两列解释方向键。

Character Build 的 density 只作用右侧候选网格：full 沿用 68px owned card，compact 沿用 48px 格、40px 图标、4px 间距；左侧纸娃娃与固定 11+4 槽、PaneChrome 内联候选操作组和调制提交区均不压缩。compact 隐藏的中性 preview badge 不得承载独占业务信息，选中、blocked、数量等仍由角标、ARIA、当前浏览摘要或共享 tooltip 表达。同一个持久化 density toggle DOM 在 storage chrome 与 Character Build 候选 PaneChrome 之间迁移；切换不发送业务消息，也不创建第二份偏好。full → compact → full 必须保持候选稳定顺序、选择和焦点。

商城 compact 的加购动作采用 `24×24px` 透明 hitbox 包围 `16×16px` glyph；默认只保留低能量深色角标，hover / focus-visible 才点亮。按钮不得重新铺满实体格，也不得以缩小命中区换取视觉留白。空槽与有内容的 compact 卡共享同一固定宽度，禁止按内容收缩。

实体格抽象采用可组合 primitive，而不是万能卡片：

- `EntityTile`：icon、body、name、meta、badge、action、state slots；
- 领域 presenter：把商品、owned slot、技能、配件候选投影到 slots；
- capability adapter：声明 select、transfer、inspect、discard、buy 等意图；
- tooltip adapter：提供 pointer 与由键盘导航取得的 focus 共用内容和生命周期。

现役 tooltip 交互只分三种原型，不扩成领域可配置工作流：KShop、NPC、Crafting、Skills、Equipment Tuning、Inventory Workbench 与 Loot 的实体/动作卡统一走 `bindAsync` 被动说明；非聚焦材料行等只读节点只消费其中的 pointer 分支；购物车点击检视等明确要求持续展示的详情独立走 `showAnchored`。实体格内 nested button 仍属于外层实体说明，但鼠标/笔点击子按钮形成的 focus 不升级为 keyboard owner。selection、busy、drag 只决定当前 owner 是否 eligible，不成为新的核心状态维度；验证锁定输入来源转换与 owner 交接旅程，不把领域状态做笛卡尔积。

### 3.1 武器加权徽标

武器标定摘要是购买引导层，不是普通描述字段：Web 只接受恰含 `{state:"confirmed",weightLayers:Number,formula:1,level:Number}` 的严格四字段摘要，其中 `weightLayers/level` 必须为真实有限 number；缺字段、多字段、公式版本不符、黄/红审计或任一畸形摘要都 fail-closed。通过后实体格图标左下显示加权徽标：完整目录为 `LvN ◆±N`，紧凑目录与 owned 格为 `◆±N`，零层必须显示 `◆0`；隐藏时完全不占位。该徽标优先于稀有度等装饰信息，但不能覆盖锁定、不可购买、数量与主动作等业务状态。

`◆N` 的玩家语义固定为“同等级标准枪械之上的额外加权层”，不是全局战力、品质或价格。正/零/负同时用符号、数字和 ARIA 文案表达，颜色不能成为唯一编码。Tooltip 只增加一行“同级加权”摘要；WBR 条款号、SHA/digest、evidence 路径和内部 note 永不进入常态 UI。未来条款解释只能先映射为受控玩家短标签，最多三项；DPS 只有在全量标定和显示口径另行冻结后才能启用。

## 4. 排版、颜色与层级

### 4.1 排版下限

| 角色 | 最小字号 |
|------|----------|
| 中文正文、条件、错误原因 | `10px` |
| 主标签、卡片名称、按钮 | `11–12px` |
| 英文/数字辅助、紧凑角标 | `9px`；只承载短信息 |
| 标题 | Pane `15–17px`，工作台 `20px` 左右 |

`6–8px` 中文不属于可接受的信息层；不能用 tooltip 掩盖常态正文不可读。Consolas/等宽字体用于数字、短状态和仪表，不承载长中文说明。

### 4.2 颜色与 skin

颜色真源见 [dls-color-system.md](../docs/dls-color-system.md)。新代码只使用 `--dls-*`、`--theta-*`、`--wb-semantic-*` 与 skin 覆盖的 `--wb-accent-*`，禁止新增一次性 DLS/技能/调制硬编码色值。

共享组件消费角色 token，例如 surface、line、text、muted、accent、focus、success、warning、danger、disabled；skin 只能覆盖 token，不能重写组件结构、命中区或状态优先级。领域差异优先来自构图与信息节奏，而不是不断增加新主色：商城强调“青色系统 + 琥珀经济”，合成强调“琥珀浏览 + 青色权威”，库存保持档案/实体感，技能和调制用不同构图区分同属 DLS 的青色家族。

边框不能全部等权。推荐层级为：surface 明度/间距建立主分组，柔线分隔内部，accent 只标识 focus、selected、pending 或主决策。

## 5. 状态语言与权威阶段

### 5.1 规范状态

组件交互状态固定为：`default → hover → focus-visible → selected/source → accept|reject → pending → success|warning|error`，另有互斥的 `disabled`、`locked`。颜色之外至少再用轮廓、图标、文案或形态表达重要状态。

工作台运行状态固定为 `idle/loading/ready/pending/success/warning/error`。routine ready 可折叠为稳定小状态点；warning/error 必须使用可读玩家文案和恢复动作，不能只改变颜色。

### 5.2 权威交互阶段

写操作遵循：

1. `browse/select`：本地意图，零写入；
2. `preview/pending`：请求权威核算，旧结果明确标记且不可提交；
3. `commit`：单一主 CTA，绑定当前 token/revision；
4. `reconcile`：未知结果只读对账，不自动重放写入。

Selection 不能伪装成写入成功。每个决策面只保留一个主 CTA；余额、成本、阻断原因和提交后的剩余量在同一区域呈现。Web 的 disabled 只是 UX，领域服务仍须复核全部安全条件。

背包—战备箱与背包—仓库的普通点击在批量模式下只暂存选择：再次点击同一格取消，玩家显式点击“执行转移”后才按选择顺序逐项调用现有 lease-bound `autoTransfer(mergeThenEmpty)`，全程严格单飞；任一 stale、timeout、断线或未知写结果立即停止剩余队列并进入既有对账，绝不重放不确定写入。`Ctrl+单击` 保留为单件立即转移，不进入批量暂存。批量入口、模式、计数、退出与唯一提交按钮属于双栏下方的正文命令栏，不得塞回全局顶栏或覆盖任一物品格；空闲态保持低高度，进入模式后扩展为可读操作栏。最低画布必须分别验证暂存 `0/1/5/50` 件时栏体位于 body 内、零横纵溢出、零子控件重叠。批量模式和密度都不得改变 AS2 落位策略、目标容器可访问容量或 slot lease 复核。

数量控件同时接收领域提供的合法意图上限 `A` 与当前可直接提交上限 `E`。数字框、range 与键盘可达完整 `1..A`，`E` 只作为“可用”预设按钮和轨道标记，不能把超出余额/容量但仍合法的预览意图裁掉；最终提交继续由权威 preview 阻断。`A≤200` 使用线性轨道，`A>200` 使用对数位置映射，但 ARIA、方向键与回调始终表达真实数量：方向键 `±1`、Shift+方向键 `±5`、Home/End 到边界、PageUp/PageDown 跳实际数量级节点。数字草稿只接受范围内整数；空值、小数、负数或越界值保留在本地并显示关联错误，不触发 preview。草稿存在时第一次 Esc 只撤销字段编辑，第二次 Esc 才交给二级页；preview 临时锁定后必须复用行和控件节点，恢复原字段焦点与列表滚动。

KShop 只保留一处精确数量编辑入口：目录的单击或 `+` 每次加购 1 件，购物车只显示 `×N`、小计和整行移除，`QuantityControl` 只出现在“核对并结账”的 SecondaryPage。目录数量弹层、购物车 `− / +` 与第二套数字框均属重复入口，禁止恢复；可选拖拽仍只产生加购意图。

## 6. 命中区、键盘与焦点

- 图标控件透明命中区至少 `24×24px`；紧凑实体格和可点击卡至少 `44px`；主 CTA 高度至少 `40px`。
- 可视 glyph 可以小于命中区。紧凑商城加购、调制单拆等角落动作统一采用“小 glyph + 大 hitbox”，不能用放大按钮遮挡物品图主体。
- pointer 点击/拖拽必须有 Enter/Space 或明确快捷键等价；hover 才出现的信息必须由 `focus-visible` 同样触发。
- 所有可操作实体必须有包含名称与当前动作的 `aria-label`；仅写“加入”“查看”不合格。
- focus ring 必须可见、与 skin 协调且不能只依赖浏览器默认蓝框；禁止全局 `outline:none` 后不给替代。

模态框与二级页必须：设置可关联标题、把焦点移入、trap Tab/Shift+Tab、使背景 inert/不可聚焦、Esc 按域规则关闭、关闭后归还 opener。二级页不是普通 DOM `display` 切换；它与 modal 共用焦点栈和底层禁用语义。Character Build 的域内 Esc 顺序固定为：纸娃娃放大预览 → 调制检视 modal → 内联“调制说明” → 未提交候选 → tuning/stats/storage → 面板关闭；一次只消费最上层。特别是检视 modal 的 Esc 只能关闭 modal 并把焦点还给调制装备图标；“调制说明”的 Esc 只收起说明并回到入口，下一次 Esc 才能退出 tuning。说明保持打开时必须随当前 operation 或键盘/指针 focus 更新，不提供 pin、`aria-pressed` 或持久化主题。

双栏工作台把帮助能力视为标配，而不是每个领域临时造按钮：只要存在拖拽替代路径、批量暂存、快捷键、二级结算或会随模式变化的隐含状态，就必须在关闭按钮前挂载唯一 `HelpAction`。入口固定使用共享 `?` 样式，打开共享 modal，零业务消息、零持久化打开态，并继承 inert、Esc 和 opener focus restore。帮助正文仍由领域负责：KShop 说明单击加购与结算页数量；战备箱说明精确放置、拖拽、`Ctrl+单击`、批量存取/取消/执行；材料档案说明密度、筛选、来源/用途与键盘浏览。storage/tuning/build 等同壳模式切换只更新同一入口内容和可用态，不得并存多个领域帮助按钮。

## 7. 动效语言

| 类别 | 时长 | 用途 |
|------|------|------|
| `micro` | `90–120ms` | hover、focus、press |
| `standard` | `140–180ms` | 选择、状态切换 |
| `structural` | `180–220ms` | 二级页、决策区切换 |
| `reject` | 约 `250ms`，最多两次 | 明确拒绝反馈 |
| `busy/ambient` | `900–1800ms` | 权威等待或唯一环境核心 |

动效只表达选择源、目标接受/拒绝、权威等待和提交结果。默认只变 `opacity/transform/color/border-color`，禁止 `transition:all`、循环装饰普通可用控件或通过宽高动画推动布局。

`prefers-reduced-motion: reduce` 在工作台根统一关闭 pulse、shake、travel 和非必要 transform，持续状态改用静态 outline/图标/文案。任何新增 keyframes 必须在同一变更中提供 reduced-motion 结果，并由 atlas 的 reduced 场景验证 computed style。

## 8. 生命周期与资源所有权

共享视图生命周期为 `mount → activate → deactivate → unmount → destroy`。`destroy` 必须幂等；进入 destroy 后必须先封闭 mount/activate/destroy 重入，再释放 session、host 与 lifetime，不能让销毁回调复活半个实例。重复 open/close/rebind 后 listener、timer、RAF、ResizeObserver、tooltip 和 pending callback 数量不得增长。

每个面板实例持有唯一 session/epoch。异步回调在应用前验证 panel instance、session epoch、operation kind 与 intent revision；旧实例回包只能被丢弃。批量 snapshot 必须验证请求容器 exact-set、唯一性和 window 参数后再原子应用。

资源清理由 `DisposableStack` 或等价共享 primitive 登记；禁止让业务模块以散落的 `removeEventListener/clearTimeout/disconnect` 猜测清理。共享 primitive 不拥有领域 lease/token，领域 coordinator 不持有 DOM。

当前实现边界固定为：

- `panel-runtime.js`：全局唯一 `PanelResponseRouter` Bridge response listener，`PanelRequestMux` 负责 generation、latest-wins、timeout 与 send failure；领域模块不得再安装直接 response listener；
- `workbench-lifecycle.js`：`DisposableStack` 与 `PanelLifecycle`，失败挂载/激活必须回滚；
- `workbench-focus.js`：栈式 `FocusScope`，统一初始焦点、Tab 环、Esc、opener restore 与祖先 `hidden/inert/aria-hidden` 排除；多层 scope 对底层 suppression 采用引用计数，乱序关闭也必须精确还原；
- `workbench-primitives.js`：EntityTile、ItemCard、InteractionBroker、PointerDragController 等中性 UI/交互 primitive；
- `workbench-components.js`：SecondaryPage、ChoiceGroup、CommitBar、HelpAction、OwnedInventoryPane、QuantityControl；所有 open/close/destroy 回调都必须容忍重入和异常，并保持 DOM、focus stack 与业务 active 状态一致。HelpAction 只拥有标准顶栏入口、更新和 listener/DOM 清理，并把领域文案交给 shell modal；并列 SecondaryPage 按打开顺序形成模态栈，只允许顶层页进入可访问树；关闭顶层恢复下层，关闭被覆盖下层不得在后续 unwind 中复活，焦点须沿 opener 链跳过已关闭页。QuantityControl 只同步数字输入、range、步进/预设按钮、`A/E` 标记及其生命周期；领域必须分别提供合法上限与当前可直接提交上限，并按 `number/range/increment/maximum` 原因解释意图，组件本身不计算价格、容量或可提交性。
- `workbench-inspection-viewport.js`：共享瞬态 inspection camera，只拥有 Canvas presentation transform、wheel/键盘/拖拽与控制按钮；不创建 renderer/Canvas，不持有领域 selection、authority 或持久偏好，deactivate/close 必须复位且 inactive 时不得消费输入。

合成页的“整理背包”是当前 `crafting` 实例内的纯 Web 子路由，不是 Host panel 切换。进入整理态时 Host active owner、exact `panelInstanceId` 与 pause lease 始终仍属 `crafting`，不得另发 `panel=workbench` open、转移 owner 或制造第二条 Host authority。只有玩家点击显式“返回合成”才恢复合成 DOM 与其本地浏览意图；普通关闭、Host close、lazy 依赖加载失败或 workbench mount 失败都直接关闭 exact `crafting` owner，不隐式返回或复活合成页。独立 workbench 则是另一条生产入口，必须由 Host 分配有效 `panelInstanceId` 后才能挂载；禁止复用合成子路由的实例缺省路径来接受无实例 standalone open。

`Panels` 的生产挂载必须 fail-closed：初始/懒注册缺失、`create()` 抛错或返回非 `Element`、append 失败、`onOpen/onRebind` 返回 `false` 或抛错，都清掉半挂载 DOM/active 状态，并向 Host 对 incoming initData 的 exact `panelInstanceId` 最多发送一次 close；不能误关旧 owner，也不能留下可被迟到 callback 复活的 pending intent。same-active 新 rebind 先退休旧 required-assets/lazy pending，再以新 initData 为唯一意图；lazy loader 同步抛错、返回非 thenable 或异步拒绝均走同一失败关闭。普通 close 先归零 visual/owner，再隔离 `onClose` 异常；force-close 额外隔离 `onForceClose`，`Bridge.send` 异常同样不得破坏清理。create/append/rebind 失败后的节点、active owner、pending open、focus 与领域状态都必须归零，且由 `test-panel-runtime.js` 覆盖精确 owner 与“恰好一次”语义。

共享异步 tooltip 的核心状态固定为一个 pointer owner 和一个 keyboard owner，pointer 展示优先。共享层以 document capture 的 `pointerdown` / `keydown` 判定输入模态；focus 只有由键盘导航取得时才登记 keyboard owner，鼠标/笔点击造成的 DOM focus 必须撤权。pointer 离开后最多恢复仍连接、仍匹配真实 `document.activeElement` 且未被 suppression 的当前 keyboard owner；不保存 owner 历史栈，也不接受领域 `restoreOn…`、`focusMode` 等恢复策略开关。无 owner 的 `hide()` 是确定性 dismiss，显式点击详情继续独立使用 `showAnchored`，不得混入这两个被动说明 owner。

每个 panel/view 实例必须持有一个 tooltip scope；关闭、rebind 或整树替换时由 scope/disposable 一次性销毁域内 binding，`clearElement/releaseTree` 必须在节点脱离 DOM 前执行。恢复前还要复核 scope 活性、节点 `isConnected` 与真实 `document.activeElement`，不能依赖浏览器一定派发 `pointerleave/focusout`。迟到回包不得复活 detached owner，`debugState` 的 detached binding 在稳定关闭后必须为 0。

tooltip 的内容视觉可以继续复用 AS2 `TooltipComposer` 的 intro/desc 双栏，但几何契约归 Web 浮层系统：被动注释固定 `pointer-events:none`，初始位置在存在可行候选时不得覆盖当前鼠标热点或触发元素；按 left/right/top/bottom 做视口碰撞选择并保留至少 `10px` anchor gap，最后夹紧 `8px` viewport inset。并排双栏超出视口时转为纵向，不能以“复刻 AS2 舞台坐标”为理由允许注释压住鼠标。anchored 内容从占位更新为富内容、字体或图片迟到时，必须以 transform 后的物理尺寸重新测量并再次执行同一契约。

## 9. 组件边界

推荐共享边界：

| primitive | 共享职责 | 不应承担 |
|-----------|----------|----------|
| `DualPaneShell` | 画布、header、profile、slot、FlowRail | 领域请求与 ViewModel |
| `WorkbenchDialog/SecondaryPage` | focus stack、inert、Esc、opener restore | 交易/学习/调制规则 |
| `HeaderToolbar/ChoiceGroup` | action group、pressed 状态、窄宽退化 | 持久化偏好和 wire |
| `HelpAction` | 唯一标准 `?` 入口、领域 spec 更新、modal 转交与确定性销毁 | 领域教程文案、业务请求与持久状态 |
| `EntityTile/ItemGrid` | 几何、密度、状态 slots、键盘入口 | 物品 taxonomy 与价格 |
| `OwnedInventoryPane` | pager/filter/sort/grid/selection 机械能力 | transfer/sell/discard 权限裁决 |
| `AuthorityPreview/CommitBar` | 核算布局、阻断原因、单 CTA | token 校验和 commit |
| `QuantityControl` | 严格整数输入、线性/对数 range、真实数量键盘步进、`− / + / +5 / 可用`、`A/E` 标记、焦点与 listener 生命周期 | 价格、容量、两类上限来源和 commit 权威 |
| `WorkbenchInspectionViewport` | Canvas-only 瞬态缩放/平移、全貌复位、输入与控制按钮 | renderer、领域预览状态、持久相机 |
| `PanelRequestMux/Router` | callId、timeout、session 分发 | 各领域 envelope validator 与 reconcile 策略 |
| `DisposableStack` | 幂等清理 | 业务状态 |

共享层只抽“相同原因而变化”的部分。仅 DOM 相似、但 authority 或失败恢复不同的代码不得为了减少行数合并。

物理拆分遵循“facade 只编排、presenter 只投影、runtime 才持有领域时序”：KShop 的 cart/catalog/owned/tooltip、Inventory Workbench 的 config/header/quick-transfer/owned-view/storage controller、NPC 的 secondary pages、Skills 的 library/loadout/trainer/interactions/render/diagnostics、Equipment Tuning 的 model/render，以及 Character Build 的 session/view/controller/mutation/action-view/tuning/slot-transition/pose/template/stats-view/doll-preview 均为显式依赖模块。`character-build-template.js` 只返回静态壳 markup，不持有行为或 authority；`character-build-slot-transition.js` 只处理 embedded tuning 活跃时的可调制 source rebind、不可调制 exact detach 与迟到回调 fence，不持有 writer、DOM 或通用路由；`character-build-doll-preview.js` 只编排 exact stage 的 SecondaryPage 迁移、底层 inert、Esc/opener restore，并把瞬态相机机械能力委托给 `workbench-inspection-viewport.js`；它不创建 Canvas/renderer，也不持有 Bridge/session/候选。各模块不得自行拥有第二个 Bridge response listener、跨面板 session 或不属于本模块的 authority token；懒加载表必须先加载共享 runtime/生命周期/焦点/primitive/component/inspection viewport，再加载 feature module，最后加载 facade。

Character Build 的“技能”入口是离开当前工作台的跨面板动作，不是第三种域内 view。前端只能在本地 finalize 成功后，用当前 exact `panelInstanceId` 发送 `reason:"navigate_skills"` 的严格 workbench close；不得自行挂载 Skills、模拟 Native HUD、建立通用返回栈，或把 Character 的 session/revision/选择状态带入 Skills。按钮触发后沿用正常关闭/blocked 反馈，页面实际切换必须等待 Host visual-retire、AS2 acknowledged detach 与 coordinator settled；失败时由 Host 执行至多一次 Character 回滚并给出结果提示，Web 不造“看似已跳转”的乐观状态。最终业务入口与刘海屏“技能”一致，只接受 `source=nativehud, view=manage`，initData 不含 `trainerSession` 或 `canReturnTrainer=true`，不创建、恢复或继承教师 capability，玩家只能配置自身已学技能与快捷栏。

只有 Character 来源且已绑定 exact Skills instance 的 manage 页可显示“← 返回构筑”；`canReturnCharacterBuild` 只是 Host 投影的展示位，不是 Web capability。点击该按钮发送 strict `reason:"navigate_character_build"`，Host 再复验当前实例与 Skill idle/cleanup 状态；右上 `×`、物理 Esc 和 native backdrop 始终普通关闭到游戏。由于 Host 当前把物理 Esc 与 native backdrop 合并为同一 `panel_esc`，不得在前端文案或状态机里声称二者行为不同。帮助/确认模态与展开搜索先消费 Esc，返回按钮在写入、对账或清理未定局时显示 disabled，而不是吞点击。跨面板返回会销毁原 Skills DOM，焦点恢复不得保存旧元素引用；新 Character Build 只消费 Host 给出的 presentation focus key，并在首屏稳定后聚焦“技能配置”。前向自动回滚也使用同一焦点落点，反向打开失败则停在游戏并明确提示从“装备”重试。跨层完整契约见 [迁移护栏 §2.5](as2-web-panel-migration.md#25-角色构筑会话默认入口与双向导航屏障2026-07-28-工作树)。

## 10. CSS 级联与文件治理

当前 `css/panels.css` 是纯 `@import` facade；历史样式按原顺序保存在 `panels/foundation-top.css`、`panels/foundation-rest.css`、`panels/features.css`，工作台样式物理拆为 `workbench/{tokens,core,inventory,skins,entities,crafting,equipment-inspector,skills,equipment-tuning,components,character-build,character-build-stats,states,motion}.css`。`tools/lib/read-css-bundle.js` 以与浏览器相同的顺序递归解析，拒绝循环、越根和丢失的外部 import；静态审计必须扫描聚合结果而不是只扫 facade。`launcher/build.ps1` 必须调用 `tools/check-workbench-css-bundle.js`，因此 transitive import 与本地 `url()` 闭包也是 candidate build 的 fail-fast 门；checker 与 reader 本身属于 runtime build recipe 身份输入。

新共享规则已使用 `workbench.components → workbench.states → workbench.motion` named layers；历史 feature/skin 仍暂时保持 unlayered，以避免物理拆分同时重排既有级联。下一阶段的目标层序仍为 `tokens → reset/base → shell → components → states → feature → skin → utilities`，但只有在跨面板截图与 computed style 对照稳定后才迁移旧规则。组件 selector 不得依赖面板祖先超过一层；skin 通过 token 或明确 `data-workbench-skin` 覆盖。`!important` 只允许暂存于迁移兼容层，并登记退出条件。

`inventory-workbench` 根暂时保留历史类名 `.kshop-workbench`，因为现役 `skins.css` 仍以它作为共享工作台 skin selector 命名空间；实际面板身份由 `data-workbench-skin=inventory|character|shop` 与领域 controller 决定，该类不表示商城路由或商城 authority。只有另开 CSS selector migration、完成 atlas 与各领域 harness 的 computed-style 对照后才允许改名，不在角色构筑视觉收敛轮为语义洁癖扩大级联变更。

新 selector、字号、transition、animation 和颜色必须通过静态治理门。当前历史债务先作为 warning 登记；warning 数只允许下降，达到约定预算后再升级为 error，禁止无说明增加。

## 11. Visual atlas 与验证矩阵

参数化 atlas 位于 [tools/visual/workbench-atlas.html](../tools/visual/workbench-atlas.html)，覆盖以下完整笛卡尔积：

- 视口：`1024×576`、`1366×768`、`1920×1080`；
- 密度：`full`、`compact`；
- 键盘焦点：默认、`focus-visible`；
- 动效偏好：默认、`prefers-reduced-motion: reduce`；
- 页面层级：主双栏、secondary page。

即 `3×2×2×2×2 = 48` 个场景。自动 runner：

```powershell
node tools/run-workbench-visual-atlas.js
node tools/run-workbench-visual-atlas.js --shot-dir=tmp/workbench-visual-atlas
node tools/audit-workbench-ui.js --strict-warnings
node tools/check-workbench-css-bundle.js
node tools/test-workbench-inspection-viewport.js
node tools/run-item-grid-visual-matrix.js --shot=tmp/item-grid-visual-matrix.png
```

runner 的 error 表示几何、溢出、焦点、命中区、二级页覆盖或结构契约失败；warning 表示 reduced-motion 仍有动画等已登记债务。`--strict-warnings` 用于债务清零后的 ratchet，不应在未治理基线上制造假红。

| 改动面 | 必跑 |
|--------|------|
| 共享 shell/entity/state/motion/CSS token/inspection viewport | static audit + 48 场景 atlas + inspection viewport Node gate + item-grid matrix |
| KShop / NPC / Crafting / Inventory / Skills / Tuning feature | 上述共享门 + 对应 feature harness |
| focus/modal/secondary page | atlas focus/secondary 场景 + 键盘人工走查 |
| reduced-motion/keyframes | atlas reduced 场景 + computed animation/transition 断言 |
| Host / AS2 authority | 本文门之外叠加 migration 闭环、xUnit、Flash fresh trace 与真机手测 |

截图用于人眼比较，不单独构成像素级通过证据；字体、Edge/WebView2 版本和资源闭包稳定前不启用脆弱的全图像素 golden。atlas 证明共享合同，不能替代各领域真实数据、滚动极值、中文长文案和游戏内动效验收。

共享稳定基线为 atlas `48/48`、物品格矩阵 `17/17` 与静态审计 `0 error / 0 warning`。角色构筑另有 workbench、领域控制器和 dressup combination 三条 browser runner；它们必须覆盖三个视口、`55:45` 且右栏不少于 `360px`、1024 下左内层 Canvas 至少 `300px`、槽区按内容收缩到约 `204px` 并贴右、三组槽位末格与左 pane 右缘对齐、四药剂同排且内层零横溢出、左 PaneChrome 的“当前构筑 + 浏览摘要”在左且放大入口在右、无总槽位/分组重复计数、空候选 overlay 隐藏、routine 底部提示折叠、候选 action group 最多三项（装备/调制/卸下，药剂为装入）且无通用详情/pin、完整 `aria-label`、1024 单行无溢出、无独立动作行和底部重复 rail、单一 density toggle DOM、候选 full/compact 往返零业务流量、stats 3×3 与抗性 4×2/2×4、power `data-scale=log10` / resistance linear、八 SVG `aria-hidden`、负值/缺值/全零降级、同一 Canvas/renderer identity、六种 battle pose 的当前状态结构骨架 fit envelope、放大页 Canvas-only wheel/`+/-`/drag/arrows/full-view reset、关闭复位、嵌入态不吞输入、inert/focus/Esc、11+4 槽位、无 pin 且随 operation/focus 更新的“调制说明”、检视 modal/内联说明逐层 Esc 与权威写后刷新。纯几何 envelope 回归另由 `node tools/test-dressup-stable-fit.js` 固定，未传 envelope 的 renderer 默认路径也必须覆盖。case 总数随契约增加而变化，本文不冻结最终数字；验收只引用同一源码树的完整 runner 输出。Browser harness 仍须按受影响领域分别执行，不能用 atlas 数量替代。

## 12. 例外与变更流程

偏离本文必须在变更中说明：业务原因、受影响 profile/primitive、最低视口、键盘与 reduced-motion 结果、退出或长期保留条件，并更新 atlas/harness 样本。一次性施工记录可以放在 `docs/`，但稳定规则只回写本文；其他入口文档只保留摘要和链接。

## 13. 本轮审视结论与后续优先级

| 维度 | 已治理并进入 ratchet | 后续只在触发条件满足时继续 |
|------|----------------------|----------------------------|
| 排版与密度 | 48px header 节奏、profile 化双栏、full 最小可读列、KShop/NPC 54px compact 目录、Owned 48px compact 格、空槽等宽、二级页全 body 覆盖 | 新增第五种布局 profile 时先补 atlas；不以单 feature 魔法数扩张 |
| 视觉层级 | 常态技术指标退出玩家层、边框降权、明确标题/正文/meta/角标字号下限、统一 empty/filtered/error 表达、FlowRail 默认低能量且只在 accept/pending/reject 提升 | 真资源极亮/极暗图标、超长本地化文案仍需按真实数据专项抽检 |
| 动效 | micro/standard/structural/reject/busy/ambient token、禁止 `transition:all`、根级 reduced-motion 关闭非必要动画 | 只有出现新的状态语义才新增 keyframes；装饰性 ambient 不作为普通控件默认态 |
| 可访问性 | EntityTile 键盘激活与完整动作命名、统一 focus-visible、FocusScope 的 trap/inert/Esc/opener restore、嵌套与重入异常回归 | 游戏内 WebView2 的完整键盘走查和系统缩放/输入法组合仍是人工门 |
| 前端架构 | 单 Bridge response router、generation-aware mux、DisposableStack/PanelLifecycle、共享 primitive/component、领域 presenter/model 拆分、lazy/build 资产闭包审计 | 不把领域 authority/reconcile 合并到视觉组件；只有出现第二个相同变化原因才继续抽象 |
| 文件治理 | `panels.css` 保持纯 `@import` facade；工作台 CSS 分域；逐模块阈值由 `tools/audit-workbench-ui.js` 单源维护，覆盖 Character Build 的 session/view/controller/mutation/action-view/tuning/pose/stats-view、storage controller 与 workbench facade | 不在本文复制易漂移的当前行数；不提高阈值、不压行伪造余量。父 facade 触线优先抽 header/close 协调，view 触线只按真实 reducer/filter 变化原因抽 model；历史 `panels/features.css` 与旧 unlayered cascade 继续分阶段迁移，不与大规模视觉改版同轮重排 |
| 视觉验证 | 48 场景 atlas、17 项物品格矩阵、各工作台领域 browser harness（含滚动窗口保持/重置探针）、严格零 warning 静态门 | 字体/Edge/WebView2/资源闭包稳定前不启用全图像素 golden；自动 Edge 证据不替代游戏内动效与真实存档验收 |

因此当前值得“现在完成”的债务是响应 listener、多实例生命周期、焦点栈、实体格密度、重复 presenter、超大 facade、CSS 物理边界和可执行验证门；这些已治理。旧样式全面 named-layer 化、像素 golden 与更细粒度 feature CSS 拆分属于下一阶段工程，不是以继续缩短文件为目的立即施工。
