# 双栏工作台 UI 系统约束

**文档角色**：双栏工作台范围的布局、交互、美学与前端工程 canonical doc。跨 AS2 / Host 的协议与权威闭环仍以 [as2-web-panel-migration.md](as2-web-panel-migration.md) 为准，验证入口以 [testing-guide.md](testing-guide.md) 为准。
**最后核对代码基线**：当前 HEAD 已 fast-forward 至 commit `c6ca84714d134310793defda893772aac2c0d5ea`（2026-07-30）；`c96f4c3d750561022b706c72a4d53050431e627d` 只保留为本轮起始审阅与 F0 债务锚点。并已复核当前 source-ahead 施工树中由专项自动门闭环的 A2b、A3、B1–B7、C1、C2、C3、E、定向视觉 F、G1–G5 与 Native 右侧条件槽；这些后续源码尚未形成 immutable release identity，也未部署。角色构筑 ↔ Skills 双向导航与原生 workbench nonce 已由 promotion commit `45b9748baa68786a52557239d5bd7c52869970f7` 正式发布并达到 `standard_entry_verified`。其余施工状态见 [双栏工作台交互真实性与视觉系统整治 ADR](../docs/双栏工作台-交互真实性与视觉系统整治-ADR-2026-07-29.md)，不得从源码默认已切换的 B7 或定向视觉 F 外推为游戏 E2E、promotion、标准入口验收、剩余旧 CSS / G6+ 或整体整治已经完成。

本文适用于 `kshop`、`npcshop`、`crafting`、独立 `workbench`、角色构筑、嵌入式装备调制和 `skills` 中采用双栏工作台语言的视图。它约束玩家态 UI，不把 dev harness、诊断面板或协议调试页误当成生产视觉标准。

本文未带状态标签的规范句只描述已经落地并由现役门保护的稳定规则；仍属前向目标的规则必须逐条标为“目标态（未实装；见 ADR 对应批次）”。实现与验证没有同轮闭合前，不得仅凭 ADR 接受状态把未来 API、参数或 fail-closed 门写成现役事实。

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
| `catalog-decision` | KShop 商城、NPC 商店、合成配方 | 左侧浏览约 60%，窄 FlowRail，右侧权威决策约 40% |
| `archive-reference` | 材料档案等只读索引 | 左侧约 44% 稳定目录，右侧约 56% 详情；两栏分别滚动，选择按稳定 key 原位更新 |
| `transfer-pair` | 背包—战备箱、背包—仓库 | 两个可操作容器近似对称；容量差异只能做受控 token 覆盖 |
| `library-action-strip` | 技能管理 | 全宽库 + 固定 Hotbar；密度只作用技能库 |
| `library-decision` | 技能教师、独立装备调制 | 目录/候选 + 固定信息量的预览提交区 |
| `character-build` | 角色构筑 | 左右固定 `55:45`；左侧内层为弹性单 Canvas + 按内容收缩并贴右的 11 装备槽/4 药剂槽，不能把槽区右侧空白保留成无效列宽；右侧候选/调制决策区不得窄于 `360px`；55% 是 1024 下仍保持三列完整候选和八列紧凑图标的左倾上限；详细属性以全 body SecondaryPage 与编辑态互斥 |

`character-build` 的最低画布为 1024×576；“当前装备/候选预览”只改变同一个 Canvas 的合成输入，不生成第二个并排 Canvas。Character Build 每次从当前权威纸娃娃状态重新测量 `空手/长枪/手枪/手枪2/双枪/兵器/手雷` 七种 battle pose，合并一个带留白的结构骨架 envelope：`身体/脸型/发型/面具/屁股/大腿/小腿/脚` 参与取景，横向变化最大的手臂、手与武器只绘制、不参与缩小人物。`手雷站立` 已由 battle rig 的真实 `手雷_装扮` holder 承载，不再是映射到空手姿态的兼容缺口。相同身体投影下，切槽、武器候选、嵌入/放大迁移和 resize 使用同一几何结果；装备或外观权威变化必须重新测量，禁止复用只按 `panelInstanceId + gender` 建立的陈旧缓存。嵌入态允许姿态末端受控裁切，完整武器/动作查看由放大页的平移和缩放承担。该能力是 renderer 的 opt-in 输入；未传 envelope 的对话、佣兵与独立 dressup 页面仍保持逐次内容自适应。需要更大构图时，`character-build-doll-preview.js` 只把现有 `.character-build-doll-stage` 与 exact Canvas 临时迁入全 body SecondaryPage；不得复制 renderer、Canvas 或 current/preview state。打开时底层 body/header inert，Esc 后按原顺序放回 stage 并恢复 opener。放大页复用 `workbench-inspection-viewport.js` 的瞬态相机：滚轮或 `+/-` 缩放、主键拖拽或方向键平移、“全貌”/`Home` 复位；transform 只作用 exact Canvas，不作用 stage、候选覆盖层或 renderer 输入。关闭必须清零缩放/位移；嵌入态停用相机且不得吞掉 pointer、wheel 或键盘输入。该 profile 必须覆盖满 11+4、空/blocked、长中文、未知性别/缺素材、stats SecondaryPage 与完整键盘路径。stats 在最低画布下不得靠缩小中文字号硬塞：标题/footer 固定，正文使用单一、可聚焦的纵向滚动区，保留可见滚动提示、滚轮与键盘滚动，并在关闭后把焦点还给入口。任何新 profile 都必须先进入本文，说明适用角色、最小画布和验证样本；禁止只在单个 feature CSS 中创造隐式结构。

当前只读 dressup manifest/report 基线固定为：items `1288`、skinKeys `2843`、covered/export `2702`、missing `141`、manual compatibility alias `9`、`auto_opposite_gender` alias `0`、battle states `7`、battle audit error `0`；missing 分类为 `opposite_gender_only=135`、`exact_xml_without_as_linkage=3`、`no_matching_source=3`，佣兵闭包为 resolved parts `3253`、当前性别 holder basic fallback parts `12`、failures `0`。自动异性 alias 必须持续为零；仅有异性素材的 key 保持 uncovered，并由当前性别 holder 的 basic fallback 承接，不能把异性身体部件伪装成精确覆盖。本文只同步已生成报告的数字，不以文档修改或测试运行重生成 manifest/report。

> **现役实现（ADR E 已完成）**：`workbench-profile.js` 只持有上述封闭枚举、共同 validator 与原子 setter，并以 frozen `validProfiles` 作为运行时、ratchet 与 profile 纯 Node 门共同消费的唯一合法列表；不得在工具或测试中复制枚举。`DualPaneShell` 构造器在创建 DOM 前校验 `profile`，并把合法值投影为 root 的 exact `data-profile`。缺失或非法值 fail fast；`setProfile(profile)` 先完成同一校验，再同步更新 Shell 内部值与 DOM attribute，失败时两者都不改变。

生产 `DualPaneShell` 必须显式选择上述封闭 profile，并把它投影为稳定 data attribute；壳级 `grid-template-columns/rows`、最小 pane 宽度和决策 footer 结构归 `workbench/profiles.css`，feature 只控制 pane 内部构图。density 只改变实体格呈现，不得隐式改变宏观双栏 split；确需不同 split 时必须定义受控 profile variant、说明领域理由并补真实 feature fixture，不能把它藏在 compact selector 中。

生产 consumer / view 映射固定如下，不按 DOM 长相或 feature 名临时猜测：

| consumer / view | profile |
|-----------------|---------|
| KShop `shop` | `catalog-decision` |
| KShop `inventory` | `transfer-pair` |
| NPC Shop（商品 + bag/material/intelligence owned view） | `catalog-decision` |
| Crafting `recipes` | `catalog-decision` |
| Crafting `materials` | `archive-reference` |
| Inventory Workbench `storage` | `transfer-pair` |
| Inventory Workbench standalone `tuning` | `library-decision` |
| Inventory Workbench `build` 与 stats SecondaryPage underlay | `character-build` |
| Loot | `transfer-pair` |
| Skills `manage` | `library-action-strip` |
| Skills `trainer` | `library-decision` |

KShop 与 Inventory Workbench 在同一 Shell 原位切 view 时，profile 也必须通过 Shell-owned 的封闭 `setProfile(profile)` 与 view attribute 在一次同步投影中更新；feature 不得直接写 `data-profile`。构造器与 setter 共用同一合法枚举校验，缺失或非法值 fail fast。Skills 与 Crafting 当前会在切 view 时重建 Shell，仍必须按目标 view 在新构造调用中选择对应 profile；不得把“会重建”当成省略 profile 或追加同值 setter 的理由。

profile 只定义**可用的壳级 track 和列宽**，不根据 `transfer-pair` 等身份臆测 root footer 一定存在。root footer 必须是 Shell root 的直接子节点并带稳定结构标记 `data-workbench-shell-footer`；只有该节点存在时才启用 footer row。Loot 的 CommitBar 使用该 root marker；Inventory Storage 的批量栏则必须是 `.workbench-body` 的直接子节点并带 `data-workbench-body-footer`，两者不得错误同构，也不为 footer presence 创造 profile variant。

### 2.2 纵向节奏

生产工作台通常按“`48px` 顶栏 → PaneChrome / 筛选 → 可滚内容 → 决策 footer”排列。Character Build 是受控例外：左侧“外观与配置 / 当前构筑”的 PaneChrome 以标题复制区承载当前浏览摘要，摘要位于“当前构筑”右侧、放大预览入口左侧；固定 11+4 槽与“护具/武装/药剂”分组不再重复显示 `15 / 15`、`· 6/5/4` 等可从结构直接得出的计数。未选候选时保留语义 overlay 节点但整层隐藏，选中后才显示一行“预览 · 名称”。routine 浏览/读取/恢复提示不得再占用 pane 底部空间，底部只为 blocked/write/reconcile/error 等必须持续可读的异常信息让位。右侧候选动作直接并入“背包候选 / 候选对比”同一 PaneChrome 标题行；删除无领域决策价值的通用“详情”和任何钉住动作，装备上下文最多显示“装备 / 调制 / 卸下”三项，药剂提交短标签改为“装入”。完整动作语义保留在 `aria-label`；“装备/装入”是唯一主 CTA。1024×576 下动作组必须单行、不换行、不横向溢出；删除独立动作行以扩大候选区，候选可滚区底部也不再复制 action rail 或长快捷键说明。常态状态、指标和 action group 不应因为文字变化推动标题或关闭按钮。二级页从顶栏下沿覆盖整个 workbench body，不在底层双栏上叠半透明可点击内容。

> **现役实现（ADR A3、G1–G5 已完成；G6+ 仍未完成）**：共享 `SecondaryPage` 取得 FocusScope 时，以引用计数抑制底层 header action，并在自己的可访问树中投影 exact Back / Help / 普通 Close；嵌套或异常卸载只释放本 owner 的 suppression。Loot、Skills 与 NPC secondary page 已接入该合同，底层已 inert 的 Help、模式、密度和 `×` 不再保留可点击外观。KShop settlement、NPC settlement 与 NPC help 的 shell-level 结构和进退场已由 shared selector 接管；生产 DualPane 的 button、EntityTile、input、select、range 与可聚焦 scroll region 也已由最终 computed gate 证明消费 focus role。G3 已收敛既定 workbench fragments 与现役 KShop consumer 的语义 motion；G4 又删除工作台 skin/Character Build 的 `.001s/.001ms` 伪关闭及 Loot/Equipment Inspector 的重复 local reduced block，把 shell 内关闭唯一交给 shared root，并以 exact workbench `data-panel` owner 覆盖壳外 Tooltip。G5 已删除历史 feature/skin 的焦点 outline 重置并退出 G2 unlayered bridge；`@layer workbench.states` 现在唯一提供 `2px solid var(--wb-focus)`、`2px` offset 的生产基线。`.character-build-slot` 是唯一显式排除项：外层不画环，inner card 使用 exact focus token，selected 继续独立使用 `--wb-role-selected`。`WB135` 同时拒绝 bridge 回流和未登记的 unlayered focus outline。Equipment Inspector、Character renderer 与 Tuning 图标的现役有界 `matchMedia` 分支均已用真实行为门证明静态终态，因此这些批次没有引入 helper、registry 或常驻 listener。其余 structural motion 绕过与 named-layer 扩围按 G6+ 单独收敛。若后续某页确需让外露 header action 保持可用，必须把该 action 排除出 inert underlay，并补真实行为门；不能通过 feature CSS 绕过 shared owner。

PaneChrome 承担标题、面包屑、meta 和筛选工具；业务内容不得再造第二套局部顶栏。FlowRail 是关系提示，不是常亮主 CTA：待命时低能量，只有拖拽接收、权威 pending 或预览更新时提升亮度。

层级筛选固定为上下两层：PaneChrome 的标题轨在上，标题与完整 breadcrumb 同行并允许所有祖先 crumb 返回；当前节点的同级/下级可选项使用下方独立 toolbar 轨，不得与 breadcrumb 或整理控件争抢残余宽度。宽度充足时下层选项保持同排；真实不足时允许自然换行，但不得生成横向滚动条。breadcrumb 只有自身真实宽度不足时才折叠中段为省略号，始终保留 root、当前 leaf 与完整无障碍路径。每个可激活 crumb 的 `title` 与 accessible name 都表达从 root 到该节点的完整路径；中段省略节点只作视觉提示、设 `aria-hidden="true"`，但其 `title` 必须列出被省略路径，root crumb 仍保留完整路径 `aria-label`。不得把 breadcrumb 与下层选项合并成一条滚动轨，也不得在有结构化 facets 时回退为原生 `select`。

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

Character Build 初始页的 11+4 稳定槽节点各自承载一个只读候选数 data/CSS slot。计数只消费 Host 已严格验证的可选 `candidateFacets`，不扫描名称、不发额外业务请求，也不把完整背包的 `filterItemCount` 当成候选总数；装备按 exact `use` 映射，`手枪2` 是唯一固定兼容映射并合并 `手枪2 + 手枪`，药剂槽读取 `药剂` leaf。权威 `0` 必须显示数字 `0`，旧 payload 省略或整组投影失效必须显示 `—` 并以“暂不可用”进入 ARIA，二者不得用“无角标”混淆。badge 只是既有 slot 的 leaf decoration：选择、roving key、DOM identity、焦点摘要和滚动仍由 Character Build View 持有；snapshot 或写后 refresh 只更新投影，不创建第二套组件生命周期。

Character Build 候选 rich tooltip 复用现役 inventory tooltip AS2 读入口与共享 `PanelTooltip`，不增加第二套物品说明 endpoint。Web 请求必须携 exact active workbench `panelInstanceId`、当前 `sessionGeneration`、背包 `slot/expectedLease` 及 `context.kind="character_build_candidate"`；只要 `payload.context` 属性存在，就必须走该严格分支，畸形、近似、primitive 或跨实例 context 不得回落到普通 storage tooltip。Host 只接受最近一次已验证候选回包的 source allowlist，blocked 候选仍可检视；snapshot、新 candidates 请求、写入、rebind 与 close 都使 completion fence 失效，迟到回包不得复活 rich 内容。严格 response shape 只应用于 Character 候选路径；没有 context 的普通 storage tooltip 保留既有 generic lease-only 行为。Web scope/cache identity 包含 candidate identity、session generation、slot 与 lease；pointer 和键盘 focus 共用 basic→rich 内容，invalidate/timeout 后不自动重放或重试。tooltip 只解释，不持有选择、装备或调制 authority。

Character Build 候选的第一次单击、Enter 或 Space 只固定本地预览；再次单击同一候选或在同一候选上按 Space 必须取消选择并清除预览，零业务写入。只有在同一已选候选上一次明确、非 auto-repeat 的 Enter 才等价触发唯一主 CTA，并继续服从 disabled、pending、lease、revision 与写入门；重复键、pointer 取消和 Space 都不得提交。

商城 compact 的加购动作采用 `24×24px` 透明 hitbox 包围 `16×16px` glyph；默认只保留低能量深色角标，hover / focus-visible 才点亮。按钮不得重新铺满实体格，也不得以缩小命中区换取视觉留白。空槽与有内容的 compact 卡共享同一固定宽度，禁止按内容收缩。

实体格抽象采用可组合 primitive，而不是万能卡片：

- `EntityTile`：icon、body、name、meta、badge、action、state slots；
- 领域 presenter：把商品、owned slot、技能、配件候选投影到 slots；
- capability adapter：声明 select、transfer、inspect、discard、buy 等意图；
- tooltip adapter：提供 pointer 与由键盘导航取得的 focus 共用内容和生命周期。

现役 tooltip 交互只分三种原型，不扩成领域可配置工作流：KShop、NPC、Crafting、Skills、Equipment Tuning、Inventory Workbench、Character Build 候选与 Loot 的实体/动作卡统一走 `bindAsync` 被动说明；非聚焦材料行等只读节点只消费其中的 pointer 分支；购物车点击检视等明确要求持续展示的详情独立走 `showAnchored`。实体格内 nested button 仍属于外层实体说明，但鼠标/笔点击子按钮形成的 focus 不升级为 keyboard owner。selection、busy、drag 只决定当前 owner 是否 eligible，不成为新的核心状态维度；验证锁定输入来源转换与 owner 交接旅程，不把领域状态做笛卡尔积。

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

> **现役实现（ADR A2a / A2b 已完成）**：Equipment Tuning 的 confirmation mode 玩家标签固定为“逐次确认 / 单件快捷”。“单件快捷”只跳过符合白名单的单件 install / replace / detach 的**人工确认动作**，仍必须先取得权威 preview、opaque token，并复核 source lease、revision、写入单飞与未知结果 reconcile；它不跳过任何 authority gate。批量、cascade 与“卸下全部”绝不自动提交，触发后直接进入现有 CommitBar 的一次显式确认，不再叠加第二个确认模态。独立与 Character Build 嵌入态消费同一 live mode 与偏好；`ChoiceGroup` 的 reject/throw 会回滚 pressed 投影，不能留下视觉成功假象。HelpAction 只解释，不解锁 mode 或配件操作。

Tuning 的 preview detail 与唯一非滚动 CommitBar 已分离；preview 更新复用稳定 DOM，并保留合法 draft、字段焦点与滚动位置。`inventory` / `loadout` exact authority source 以常驻可见标记和等价测试语义分型；当前 source 使用 `12×12px` source-port glyph 标识 exact 调制源，不再用粗重文字贴纸占据卡面，仍须通过 `aria-current` 与“当前调制装备 / 用于交换”的完整名称表达，颜色和 glyph 不能成为唯一语义。插件槽容量只消费当前权威 `snapshot.equipment.modSlotCapacity` 与同一 snapshot 的 `snapshot.equipment.mods`；inventory/loadout 物品格另行消费 presentation projection 的 `modSlots[]`，两者不得混写。capacity 仅接受 `0..64` 的有限整数且 installed 不大于 capacity；`64` 是防止异常快照制造无界 DOM 的展示安全上限，不是本地三槽业务规则。`0` 明示“无插件槽”，字段缺失不猜测，畸形或超限值明示“容量未知”。顶部当前装备区是持久快捷总览：进阶、已装插件与低噪声空插件槽均为同角色按钮，可从任意 tab 一步进入进阶、替换或安装候选，但空槽点击不得提前 preview/commit；配件页槽位区以同一 capacity 全量显示更大的详细操作面，已装槽可替换或专门卸下，空槽可聚焦并进入 `install_mod` 候选，不存在槽不渲染。空槽序号只表达容量位置，当前协议不携目标槽号，任一空槽都是等价安装入口，最终位置仍由 AS2 权威规则决定。真实剑圣腿甲固定证明 `1 个进阶槽 + 3 个插件槽`；`1/3 + 2` 个空插件槽用于可用容量演示，另保留 4+ synthetic capacity 只证明 Web 没有写死三槽。“卸下全部”等批量命令位于槽位 group 之外，不得伪装成额外槽。summary / operation 使用带 surface 与槽序号的唯一 focus key，详细槽重渲不得把焦点跳回顶部。`readPending / busy / reconcile / detaching / retry` 经 feature-local 单一锁投影同步覆盖 operation tabs、已安装 tier、强化 input/stepper/range/marks/cap、两处空槽与主 CTA；source/loadout 锁必须保存 owner/base/original `disabled` 与 `aria-disabled`，解除时只恢复自己持有的节点，drug、empty、blocked 和原生 disabled 状态不得被误解锁。number/range/mark/stepper/cap 发起强化 preview 时保持发起控件焦点；只有候选/交换 preview 才可把确认区带入可见范围并迁移 CommitBar 语义焦点。confirmation wrapper 使用有名称的 `role="group"`，busy/`aria-disabled` 下沉到真实控件族，不污染 generic section。阻断原因保持正文可读，只有 exact ready owner 可以提交。

现役交换目标 wire 必须是 exact `{sourceKind:"inventory",containerId:"背包",slot,expectedLease}` 四键；遗漏 `sourceKind` 或任一 near-shape 在 Host/AS2 前 fail closed。“卸下全部”现为与槽卡等高的方形按钮，在同一 rail 最右对齐，但语义和 DOM 均留在槽位 group 之外。单件插件 click 的即时回显只是一份 presentation intent：候选与对应已装/空槽以 `aria-busy` 和 `preview_pending → write_pending → committed_syncing | uncertain` 阶段说明正在处理，但不得提前改写权威 snapshot、槽内容、数量、lease 或 revision，也不得排队重放。preview 确定失败立即撤销该意图；未知 commit 保持对账语义，不显示伪成功。成功 commit 的 Host 已校验写后 tuning snapshot 可以先呈现，但同一 inventory external-write capability 必须一直持有到 fresh 背包刷新 settle；刷新后的 source ref 与该 snapshot 精确匹配时直接收敛并免去重复 tuning read，不匹配、畸形或刷新失败则进入现役 fresh snapshot / retry / reconcile。Inventory coordinator 的 owner-only 状态变化仍刷新 controls、source marker 与 pager，但引用未变化的背包/右栏 window 不重建 pane DOM。

Character Build 的已选择候选优先成为 tuning action target；只有未选候选时才回落到当前已穿戴装备。候选入口必须重建 exact `{sourceKind:"inventory",containerId:"背包",slot,expectedLease}`，blocked、非装备、强化等级无效、near-shaped 或同物理槽歧义一律禁用并解释。写后先收束已挂载 Inventory coordinator 的 external-write/cache，未挂载时不得激活 Storage；随后只刷新 entry 绑定的 exact Character target、采用新 lease、失效 tooltip cache 并重绑 tuning source。entry/session/panel/target/request generation 任一漂移都丢弃迟到结果，未知或 stale 写不重放。

候选返回优先匹配同 physical slot 与写后新 lease；实体消失时固定 next→previous，歧义或没有候选时留在当前槽并聚焦候选标题。先恢复保存的候选滚动，再以 `preventScroll` 聚焦；仅当目标越出候选 viewport 时按实际 PanelScale 做 nearest 校正，原位置可见时不得扰动滚动。该纵切复用现有 `EquipmentTuningView` 与 Character session，不新建 endpoint、通用 source bus、第二个 cache coordinator 或跨领域状态机。

数量控件同时接收领域提供的合法意图上限 `A` 与当前可直接提交上限 `E`。数字框、range 与键盘可达完整 `1..A`，`E` 只作为“可用”预设按钮和轨道标记，不能把超出余额/容量但仍合法的预览意图裁掉；最终提交继续由权威 preview 阻断。`A≤200` 使用线性轨道，`A>200` 使用对数位置映射，但 ARIA、方向键与回调始终表达真实数量：方向键 `±1`、Shift+方向键 `±5`、Home/End 到边界、PageUp/PageDown 跳实际数量级节点。数字草稿只接受范围内整数；空值、小数、负数或越界值保留在本地并显示关联错误，不触发 preview。草稿存在时第一次 Esc 只撤销字段编辑，第二次 Esc 才交给二级页；preview 临时锁定后必须复用行和控件节点，恢复原字段焦点与列表滚动。

KShop 只保留一处精确数量编辑入口：目录的单击或 `+` 每次加购 1 件，购物车只显示 `×N`、小计和整行移除，`QuantityControl` 只出现在“核对并结账”的 SecondaryPage。目录数量弹层、购物车 `− / +` 与第二套数字框均属重复入口，禁止恢复；可选拖拽仍只产生加购意图。

### 5.3 交互真实性与对象身份

> **实现状态**：G0 已接通 terminal semantic-hidden utility、`HelpAction` header identity 与 `InventoryWorkbenchHeaderProjection`；G1 已接通 KShop/NPC 三个 shell-level SecondaryPage 的 shared cascade、normal structural transition 与 reduced-motion 静态终态；G2 已接通生产 DualPane 的 focus role 最终 computed convergence 与 selected/focus 分离；G3 已把既定工作台 fragments 和 foundation 的现役 KShop consumer 收敛到语义 duration/easing/property 合同，并让 shared neutral busy/reject keyframes 与消费同域；G4 已删除工作台 `.001s/.001ms` 伪关闭、收敛 shell 内重复 local reduced block、精确接管壳外 Tooltip，并以真实 renderer/transition/animation 门验证 normal/reduced 终态；G5 已删除历史 unlayered outline 重置、退出 G2 bridge，并以 layered baseline、Character slot 唯一例外和 `WB135` 静态门封闭焦点级联；定向视觉 F 已关闭本轮识别出的正文/标签字号、Choice/Loot 整组 opacity 与三个真实滚动面的 scrollbar 缺口，并把 debt ceiling 同步下调；A1 已接通显式导航计划/提交/回滚；A2a/A2b 已完成 Tuning mode、固定 CTA、source 与锁投影；A3 已完成 shared SecondaryPage exact action/header suppression、Loot/Skills/NPC Help 收敛、Loot player-copy、KShop 键盘 inspection 与 NPC locked entity 可检视；A4 已固定 Crafting 决策结构；B3 已完成 Build / Storage / standalone Tuning 的 feature-local 有界导航、exact detach 和失败回滚；B4 已完成三目标封闭 post-close intent、两阶段 timeout、lifecycle fence 与返回焦点双值 parser；B5 已启用 Materials 的 Host-owned opaque requestId、AS2 exact echo、独立 wait/admission 与一次失败回滚；B6 已启用 Intelligence 的 Host 内建固定 production initData、同步 exact admission、零 target wait 与一次失败回滚；B7 已把同一临时 gate 原子接入两套 HUD、Build header、Host focus 与 Web 固定菜单，并把代码默认和随仓配置切为 on；C1 已完成候选分类计数的 AS2 权威投影、Host 严格验证与 Web 渐进呈现；C2 已完成候选 rich tooltip 的 exact context/source allowlist、completion fence 与 scoped pointer/focus 呈现；C3 已完成 exact inventory source、写后 lease/候选/cache 刷新、迟到 fence 与语义返回；E 已接通封闭 Shell profile、中央壳级 CSS 与真实领域 fixture。它们均有专项行为门，D 已完成本机 150% DPI 双宿主 production/development smoke；但 100% DPI/真实 pinch、剩余旧色值/skin/G6+、B7 游戏内/标准入口验收与部署仍未完成，不能外推为所有生产 feature 已满足。现役缺口以 §13 为准。

玩家可见 control 必须真实投影当前 view 和 capability：激活后产生与文案一致的可观察效果，或 visibly disabled 并在同一上下文给出可读原因；禁止可点外观配 silent no-op。`hidden` 不只检查 DOM attribute，还必须在最终 computed style、命中区和 Tab 序列上同时隐藏；feature/skin 的 `display` 规则不得把语义 hidden 重新显示。HelpAction、tooltip、hover、focus 或打开说明永远不能成为业务 capability 的隐藏前置。

祖先 `aria-disabled` 或 pane-level busy class 不能替代子 EntityTile、nested button、input、tab 与 range 的真实投影；同一领域局部状态必须向父容器和全部控制族输出一致的 `{inspectable, actionable, reason}`。handler 因 reconcile、detaching、refresh 或 returning 拒绝时，对应控件不得仍显示 enabled 文案和命中区。

`browseFocus`、玩家 `selection`、`authoritySource` 与 `actionTarget` 是四种不同身份。它们可以指向同一实体，但不得合并为模糊 `item`；inventory exact ref 与 loadout exact ref 始终分型。当前 authority source 必须持续可见并具有等价 ARIA 语义，source stale 时先撤销可提交性和旧高亮，再进入安全刷新/重选。

每个决策面唯一主 CTA、提交状态和阻断原因位于非滚动 decision footer；可滚层只承载差异、材料、返还、历史和长说明。内容增长不得把确认按钮推离首屏。`availability-blocked` 仍允许查看原因，原因维持正文对比度；`interaction-disabled/busy` 只禁止控件，禁止用整卡或整条 CommitBar 的统一低 opacity 同时淡化解释文本。EntityTile 的 `inspectable` 与 `actionable` 分离：blocked 实体可由 pointer/键盘查看原因，激活只解释原因且不得发送业务 intent。

异步目录至少区分 `unselected / loading / empty / error / ready`；`0 / unknown / loading / error` 的计数也不得合并。空态统一 `{kind, statement, nextStep}` 语义，不强制领域共用业务组件。视图返回目标来自显式 view/overlay stack，不能以某 controller 或 DOM 是否曾实例化推断；Esc 一次只消费最内层 draft/modal/说明/子视图，普通 `×` 与 native backdrop 始终执行 exact owner 的普通关闭。

### 5.4 Native 右侧条件槽

`RightContextSlotOwner` 是封闭的 `hidden | contextHint | actionableNotice | transactionDecision`。唯一优先级仲裁位于 `NativeHudOverlay`：每次只计算一个 `transactionDecision > actionableNotice > contextHint > hidden` 结果，再把同一 owner 投影给 `RightContextWidget` 与 `SafeExitPanelWidget`；两个 widget 不得各自推断优先级，旧 `_externalStatusSlotActive` 高度布尔合同已经移除。

只有 exact owner 可以绘制或命中条件槽：SafeExit transaction 出现时 RightContext 的 notice/hint 零绘制、零命中；notice 出现时 hint 零绘制、零命中；hint 只绘制说明而不产生 action hitbox；`hidden` 或缺少组合 owner 时条件槽的可见几何、像素与命中均为空。`CompositeBounds` 允许为 hover/repaint 保留透明 union，但该区域必须 click-through，不能冒充可见槽。装备入口说明固定为“打开角色构筑；其他整备功能在刘海或装备页”，不在这里复制整备导航。现役 Native top tools 没有独立键盘 focus owner；本轮由 pointer hover 与同源测试探针固定文案，不声称已经增加不存在的键盘焦点链。

## 6. 命中区、键盘与焦点

- 图标控件透明命中区至少 `24×24px`；紧凑实体格和可点击卡至少 `44px`；主 CTA 高度至少 `40px`。
- 可视 glyph 可以小于命中区。紧凑商城加购、调制单拆等角落动作统一采用“小 glyph + 大 hitbox”，不能用放大按钮遮挡物品图主体。
- pointer 点击/拖拽必须有 Enter/Space 或明确快捷键等价；hover 才出现的信息必须由 `focus-visible` 同样触发。
- 所有可操作实体必须有包含名称与当前动作的 `aria-label`；仅写“加入”“查看”不合格。
- focus ring 必须可见、与 skin 协调且不能只依赖浏览器默认蓝框；禁止全局 `outline:none` 后不给替代。
- Ctrl+滚轮缩放、默认浏览器右键菜单与玩家 accelerator 属于 WebView2/Host 根输入策略，不在 feature 重复拦截。`WebView2BrowserPolicy` 已由 `WebOverlayForm` 与 `BootstrapPanel` 在 EnsureCore 后、首次 Navigate 前共同消费：生产默认关闭用户 zoom/pinch、accelerator、DevTools、默认右键、自动填充与密码保存；显式 `webView2DeveloperMode` / `CF7_WEBVIEW2_DEV_MODE` 只恢复未被 Host 热键合同保留的 browser accelerator、DevTools 与默认右键，普通滚轮、inspection wheel、系统 DPI、PanelScale 与 Host 写入的 ZoomFactor 保持原路径。`KeyboardHook` / `HotkeyGuard` 仍保留 `Ctrl+W/R/P/O/F/Q`，所以开发态以 `F5` 作为浏览器 reload 正例；`Ctrl+R` 继续服从 Host 合同，不能作为“开发 accelerator 已恢复”的断言。`tools/audit-workbench-ui.js` 的责任边界仅为 Web/CSS/发布接线，不解析 C#；Host 行为由 `WebView2BrowserPolicyTests` 和真实双宿主 smoke 证明。自动策略矩阵和双宿主接线已覆盖；当前 exact candidate 已在本机 150% DPI 下完成 Bootstrap/Overlay 的 production/development 实机 smoke，100% DPI 与真实触控/触控板 pinch 仍缺物理设备证据，不得写成完整 D 批 E2E。

> **现役实现（ADR G2/G5 已完成）**：G2 先以过渡 bridge 验证所有生产 `DualPaneShell` 的 focus role，G5 随后删除历史 feature/skin 的 `outline:none/0` 并退出该 bridge。`states.css` 的 named `@layer workbench.states` baseline 现在是生产 focus ring 的唯一来源；button、EntityTile、input、select、range、`[data-scroll-region]` 与显式 tab stop 的 `:focus-visible` 最终 outline 消费 `--wb-focus`，选择态使用 `--wb-role-selected` 边框而不覆盖 focus outline。Character Build slot 是唯一受控 inner-card 例外：外层不重复画环，内层 outline 消费 exact focus token、选中边框消费 selected token，并有 selected+focus computed gate。KShop 全控制族、Loot skinless profile、Character slot/stats scroll 和受影响领域 harness 均为现役自动证据；`WB135` 拒绝旧 bridge 或未登记 unlayered focus outline 回流。Native top tools 仍没有独立键盘 focus owner，不能由 Web 焦点门外推。

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

> **现役实现（ADR G1 已完成）**：KShop settlement、NPC settlement 与 NPC help 三个 shell-level consumer 不再用 unlayered skin 声明接管 `position/inset/z-index/display`。它们由 `.workbench-secondary-page` 统一保持 `display:grid`、`z-index:55` 和 header 下沿结构盒，normal 模式以 structural token 完成约 `210ms` 的 opacity/transform 进退场；同一 task 内 mount 后立即 open 也必须先提交 inactive 几何。reduced-motion 必须直接得到 `transition-duration:0s`、无动画、无 transform 的可见或隐藏静态终态。`.npcshop-space-page` 是 settlement 内嵌 organizer，长期保留 host-local `inset:0 / z-index:4 / display:none|grid`，不得迁升为 shell page；Character Stats 与 Doll Preview 的 full-body geometry 也仍由各自 host 持有。

> **现役实现（ADR G2/G5 已完成）**：production focus role 的最终计算值已经收敛；选择态与焦点态同时存在时仍保持不同角色。G5 已删除历史 outline reset 并退出 G2 的受控 unlayered bridge；当前唯一生产基线位于 named `workbench.states`，精确例外与防回流门见 §10。

> **现役实现（ADR G3 已完成）**：`skills/entities/inventory/core/equipment-tuning/skins/character-build/components` 与 `foundation-rest.css` 中现役 KShop consumer 已按职责消费 micro/standard/reject/busy/ambient token；过渡与三类语义 animation 均消费现有 `--wb-ease-standard`，过渡属性限定在允许集合。领域无关的 `wb-pulse-busy`、`wb-reject-pulse` keyframes 由 shared motion 域持有，Skills reject 使用 `--wb-role-reject`，Equipment Tuning 的唯一 ambient core 保留在 feature 同域但改用 ambient token。normal/reduced computed fixture 同时证明 busy/reject 动画按 token 执行、reduced 下动画归零且状态图标、outline 与文案不消失。该批明确没有扫描或改写 lockbox/非工作台 `transition:all`，也没有新增 JS helper、全局 `!important` 或第二套 easing/token。

> **现役实现（ADR G4 已完成）**：工作台 `skins.css` 与 `character-build.css` 已删除 `.001s/.001ms` 伪关闭；Loot 与 Equipment Inspector 不再复制 shell root 已覆盖的 reduced 声明，Equipment Tuning 的本地 reduced block 只保留必要的静态 `opacity:.55` 补偿。shared root 是 `.workbench-shell` 内 pulse、shake、travel、transform 与 transition 的唯一关闭点；SecondaryPage 的 `visibility 0s linear` 延迟离场合同原样保留。`#panel-tooltip` 位于 shell 外，因此 shared motion 以 `#panel-container` 的 exact `kshop/workbench/npcshop/crafting/skills/loot` owner 关闭其 busy pulse；`tasks` 等非工作台 panel 的反例仍保持正常 pulse，禁止用全局 tooltip selector 扩大影响。Character renderer、Equipment Inspector 与 Tuning 图标现有的直接 `matchMedia` 分支均已由真实 normal/reduced fixture 证明能停掉 renderer、transition 或动画并保留静态结果；当前只有这三个有界 consumer，故不新增共享 helper、registry 或 preference listener。非工作台 `task_panel.css` 中的 `0.001s` 仍是明确的范围外存量，不得把 G4 写成全站清零。

> **目标态（未完整实装；见 ADR G6+）**：历史 outline shorthand 与 G2 bridge 已由 G5 退出；其他 feature 对 shared structural motion 的 unlayered 绕过和 named-layer 扩围仍须分批完成。只有未来出现多个需要共同生命周期管理的 JS 帧循环时，才评估提取窄 `prefersReducedMotion()` helper；不得为形式统一预建 registry/listener。SecondaryPage 和 state motion 是否统一继续以最终 computed style 与行为为准。

## 8. 生命周期与资源所有权

共享视图生命周期为 `mount → activate → deactivate → unmount → destroy`。`destroy` 必须幂等；进入 destroy 后必须先封闭 mount/activate/destroy 重入，再释放 session、host 与 lifetime，不能让销毁回调复活半个实例。重复 open/close/rebind 后 listener、timer、RAF、ResizeObserver、tooltip 和 pending callback 数量不得增长。

每个面板实例持有唯一 session/epoch。异步回调在应用前验证 panel instance、session epoch、operation kind 与 intent revision；旧实例回包只能被丢弃。批量 snapshot 必须验证请求容器 exact-set、唯一性和 window 参数后再原子应用。

独立 Workbench 的 `build ↔ storage/tuning` 导航事务还必须绑定单调 generation 与 `destroyed` fence。destroy 先推进 generation、终结 pending 并清空端口；之后到达的 `prepareStorageLeave/prepareBuildLeave` 回调不得激活 Build、挂载 Storage、提交 history、恢复焦点或改写替代实例。controller 在 pending 期间上报另一个合法 view 时，以其实际状态 supersede 旧事务：先清 pending/timeout、推进 generation，旧目标为 Build 时 suspend，再按现有封闭三视图 plan/commit 或 reset 路径收敛；不得提交新 view 却遗留旧 pending 门闩。所有既有异步协议仍未终结时，30 秒 watchdog 只做最后止损：discard 未决目标、恢复旧视图/焦点并解除导航门，迟到回调继续由 generation 拒绝；它不把 timeout 当作成功，也不授权任意路由。当前回归覆盖双向 destroy-late-callback、controller 分叉与 orphan timeout。长时间使用后重启恢复并不能单独证明内存泄漏或 WebView renderer 崩溃；本轮确定关闭的是这些可证导航竞态。tooltip/透明覆盖层仍只能作为待现场 hit-test 的候选，未取得 live ProcessFailed、heap、console 与遮挡证据前不得写成根因。

资源清理由 `DisposableStack` 或等价共享 primitive 登记；禁止让业务模块以散落的 `removeEventListener/clearTimeout/disconnect` 猜测清理。共享 primitive 不拥有领域 lease/token，领域 coordinator 不持有 DOM。

当前实现边界固定为：

- `panel-runtime.js`：全局唯一 `PanelResponseRouter` Bridge response listener，`PanelRequestMux` 负责 generation、latest-wins、timeout 与 send failure；领域模块不得再安装直接 response listener；
- `workbench-lifecycle.js`：`DisposableStack` 与 `PanelLifecycle`，失败挂载/激活必须回滚；
- `workbench-focus.js`：栈式 `FocusScope`，统一初始焦点、Tab 环、Esc、opener restore 与祖先 `hidden/inert/aria-hidden` 排除；多层 scope 对底层 suppression 采用引用计数，乱序关闭也必须精确还原；
- `workbench-primitives.js`：EntityTile、ItemCard、InteractionBroker、PointerDragController 等中性 UI/交互 primitive；
- `workbench-components.js`：SecondaryPage、ChoiceGroup、CommitBar、HelpAction、OwnedInventoryPane、QuantityControl；所有 open/close/destroy 回调都必须容忍重入和异常，并保持 DOM、focus stack 与业务 active 状态一致。HelpAction 只拥有标准顶栏入口、更新和 listener/DOM 清理，并把领域文案交给 shell modal；并列 SecondaryPage 按打开顺序形成模态栈，只允许顶层页进入可访问树；关闭顶层恢复下层，关闭被覆盖下层不得在后续 unwind 中复活，焦点须沿 opener 链跳过已关闭页。QuantityControl 只同步数字输入、range、步进/预设按钮、`A/E` 标记及其生命周期；领域必须分别提供合法上限与当前可直接提交上限，并按 `number/range/increment/maximum` 原因解释意图，组件本身不计算价格、容量或可提交性。
- `workbench-inspection-viewport.js`：共享瞬态 inspection camera，只拥有 Canvas presentation transform、wheel/键盘/拖拽与控制按钮；不创建 renderer/Canvas，不持有领域 selection、authority 或持久偏好，deactivate/close 必须复位且 inactive 时不得消费输入。
- `equipment-tuning-write-lifecycle.js`：只拥有插件即时意图、inventory write、refresh/retry 与 quick-commit 阶段；不拥有 renderer、候选 taxonomy、Host/AS2 authority 或第二套 snapshot 状态机。`equipment-tuning-view.js` 继续编排 session/read/detach，render 只消费阶段投影。

合成页的“整理背包”是当前 `crafting` 实例内的纯 Web 子路由，不是 Host panel 切换。进入整理态时 Host active owner、exact `panelInstanceId` 与 pause lease 始终仍属 `crafting`，不得另发 `panel=workbench` open、转移 owner 或制造第二条 Host authority。只有玩家点击显式“返回合成”才恢复合成 DOM 与其本地浏览意图；普通关闭、Host close、lazy 依赖加载失败或 workbench mount 失败都直接关闭 exact `crafting` owner，不隐式返回或复活合成页。独立 workbench 则是另一条生产入口，必须由 Host 分配有效 `panelInstanceId` 后才能挂载；禁止复用合成子路由的实例缺省路径来接受无实例 standalone open。

`Panels` 的生产挂载必须 fail-closed：初始/懒注册缺失、`create()` 抛错或返回非 `Element`、append 失败、`onOpen/onRebind` 返回 `false` 或抛错，都清掉半挂载 DOM/active 状态，并向 Host 对 incoming initData 的 exact `panelInstanceId` 最多发送一次 close；不能误关旧 owner，也不能留下可被迟到 callback 复活的 pending intent。same-active 新 rebind 先退休旧 required-assets/lazy pending，再以新 initData 为唯一意图；lazy loader 同步抛错、返回非 thenable 或异步拒绝均走同一失败关闭。普通 close 先归零 visual/owner，再隔离 `onClose` 异常；force-close 额外隔离 `onForceClose`，`Bridge.send` 异常同样不得破坏清理。create/append/rebind 失败后的节点、active owner、pending open、focus 与领域状态都必须归零，且由 `test-panel-runtime.js` 覆盖精确 owner 与“恰好一次”语义。

共享异步 tooltip 的核心状态固定为一个 pointer owner 和一个 keyboard owner，pointer 展示优先。共享层以 document capture 的 `pointerdown` / `keydown` 判定输入模态；focus 只有由键盘导航取得时才登记 keyboard owner，鼠标/笔点击造成的 DOM focus 必须撤权。pointer 离开后最多恢复仍连接、仍匹配真实 `document.activeElement` 且未被 suppression 的当前 keyboard owner；不保存 owner 历史栈，也不接受领域 `restoreOn…`、`focusMode` 等恢复策略开关。无 owner 的 `hide()` 是确定性 dismiss，显式点击详情继续独立使用 `showAnchored`，不得混入这两个被动说明 owner。

每个 panel/view 实例必须持有一个 tooltip scope；关闭、rebind 或整树替换时由 scope/disposable 一次性销毁域内 binding，`clearElement/releaseTree` 必须在节点脱离 DOM 前执行。恢复前还要复核 scope 活性、节点 `isConnected` 与真实 `document.activeElement`，不能依赖浏览器一定派发 `pointerleave/focusout`。迟到回包不得复活 detached owner，`debugState` 的 detached binding 在稳定关闭后必须为 0。

tooltip 的内容视觉可以继续复用 AS2 `TooltipComposer` 的 intro/desc 双栏，但几何契约归 Web 浮层系统：被动注释固定 `pointer-events:none`，初始位置在存在可行候选时不得覆盖当前鼠标热点或触发元素；按 left/right/top/bottom 做视口碰撞选择并保留至少 `10px` anchor gap，最后夹紧 `8px` viewport inset。并排双栏超出视口时转为纵向，不能以“复刻 AS2 舞台坐标”为理由允许注释压住鼠标。anchored 内容从占位更新为富内容、字体或图片迟到时，必须以 transform 后的物理尺寸重新测量并再次执行同一契约。

## 9. 组件边界

推荐共享边界：

> **实现状态**：`InventoryWorkbenchHeaderProjection` 已在 G0 落地，带封闭 `profile` 的 `DualPaneShell` 已在 E 批落地。本轮没有创建共享 scroll-surface utility；现役只在 `.inventory-owned-grid`、Loot 两个滚动面和 `.equipment-tuning-detail` 使用领域级 exact scrollbar CSS。只有未来出现多个同因变化、且可由真实 overflow/computed fixture 证明一致的消费者时，才评估抽取窄 utility。

`InventoryWorkbenchHeaderProjection` 输出的 `disabled + reason` 是“可解释阻断”，不是应由原生 `button.disabled` 吞掉的静默禁用：action 保持真实 pointer/keyboard 激活路径与 `aria-disabled="true"`，统一守卫先显示现有 `onBlocked` 原因并阻止原 handler；只有 disabled 且没有 reason 的内部不可用态才使用原生 `disabled`。阻断投影必须保留初始 accessible name（Close 以“关闭工作台”为前缀），Close 的 reason 还须明确“完成后才能关闭工作台”，并把生产音频 capture 先读到的 `data-audio-cue` 原子切为 `error`；恢复可用时同时还原原名/原 cue，清理 reason、临时 title/ARIA 与禁用属性。Character Build 的 stats / legacy skills / close / storage 共用这一 feature-local 机械，不建立全局 disabled-action abstraction；真实 Edge fixture 必须证明可见 stats/close 仍有命中区、DOM 激活只出现对应动作原因/error cue，且零 stats/navigation/close 穿透。

| primitive | 共享职责 | 不应承担 |
|-----------|----------|----------|
| `DualPaneShell` | 画布、header、profile、slot、FlowRail | 领域请求与 ViewModel |
| `WorkbenchDialog/SecondaryPage` | focus stack、inert、Esc、opener restore | 交易/学习/调制规则 |
| feature `HeaderProjection` / `ChoiceGroup` | 当前 view 的 action 可见/禁用/标签纯投影；ChoiceGroup 负责 pressed/disabled 机械 | action descriptor DSL、动态 toolbar registry、领域路由与 wire |
| `HelpAction` | 唯一标准 `?` 入口、领域 spec 更新、modal 转交与确定性销毁 | 领域教程文案、业务请求与持久状态 |
| `EntityTile/ItemGrid` | 几何、密度、状态 slots、键盘入口 | 物品 taxonomy 与价格 |
| `OwnedInventoryPane` | pager/filter/sort/grid/selection 机械能力 | transfer/sell/discard 权限裁决 |
| `AuthorityPreview` 模式 / `CommitBar` | browse → preview → commit → reconcile 阶段；固定阻断原因、状态和单 CTA | 通用领域 preview schema、token 校验和 commit |
| `QuantityControl` | 严格整数输入、线性/对数 range、真实数量键盘步进、`− / + / +5 / 可用`、`A/E` 标记、焦点与 listener 生命周期 | 价格、容量、两类上限来源和 commit 权威 |
| 领域级 exact scrollbar CSS | 在 `.inventory-owned-grid`、Loot 两个滚动面和 `.equipment-tuning-detail` 上提供 stable gutter、窄轨、track/thumb/hover/button/corner 与 focus 角色 | 全局 utility、`overflow/max-height`、滚动窗口身份、scroll/focus restore、JS/DOM wrapper |
| `WorkbenchInspectionViewport` | Canvas-only 瞬态缩放/平移、全貌复位、输入与控制按钮 | renderer、领域预览状态、持久相机 |
| `PanelRequestMux/Router` | callId、timeout、session 分发 | 各领域 envelope validator 与 reconcile 策略 |
| `DisposableStack` | 幂等清理 | 业务状态 |

共享层只抽“相同原因而变化”的部分。仅 DOM 相似、但 authority 或失败恢复不同的代码不得为了减少行数合并。

物理拆分遵循“facade 只编排、presenter 只投影、runtime 才持有领域时序”：KShop 的 cart/catalog/owned/tooltip、Inventory Workbench 的 config/header/quick-transfer/owned-view/storage controller、NPC 的 secondary pages、Skills 的 library/loadout/trainer/interactions/render/diagnostics、Equipment Tuning 的 model/render，以及 Character Build 的 session/view/controller/mutation/action-view/tuning-adapter/tuning/slot-transition/pose/template/stats-view/doll-preview 均为显式依赖模块。`character-build-template.js` 只返回静态壳 markup 与固定槽目录，不持有行为或 authority；`character-build-tuning-adapter.js` 只适配 loadout/inventory source、候选 entry/refresh/return fence 和既有 session/cache 端口，不拥有 Bridge listener 或 tuning writer；`character-build-slot-transition.js` 只处理 embedded tuning 活跃时的可调制 source rebind、不可调制 exact detach 与迟到回调 fence，不持有 writer、DOM 或通用路由；`character-build-doll-preview.js` 只编排 exact stage 的 SecondaryPage 迁移、底层 inert、Esc/opener restore，并把瞬态相机机械能力委托给 `workbench-inspection-viewport.js`；它不创建 Canvas/renderer，也不持有 Bridge/session/候选。各模块不得自行拥有第二个 Bridge response listener、跨面板 session 或不属于本模块的 authority token；懒加载表必须先加载共享 runtime/生命周期/焦点/primitive/component/inspection viewport，再加载 feature module，最后加载 facade。

Character Build 的“技能”入口是离开当前工作台的跨面板动作，不是第三种域内 view。前端只能在本地 finalize 成功后，用当前 exact `panelInstanceId` 发送 `reason:"navigate_skills"` 的严格 workbench close；不得自行挂载 Skills、模拟 Native HUD、建立通用返回栈，或把 Character 的 session/revision/选择状态带入 Skills。按钮触发后沿用正常关闭/blocked 反馈，页面实际切换必须等待 Host visual-retire、AS2 acknowledged detach 与 coordinator settled；失败时由 Host 执行至多一次 Character 回滚并给出结果提示，Web 不造“看似已跳转”的乐观状态。最终业务入口与刘海屏“技能”一致，只接受 `source=nativehud, view=manage`，initData 不含 `trainerSession` 或 `canReturnTrainer=true`，不创建、恢复或继承教师 capability，玩家只能配置自身已学技能与快捷栏。

B4 将这条跨 owner 交接收敛为固定 `Skills | Materials | Intelligence` enum 和小型 Host intent；结构只保存目标、exact Build instance、`armed | rollback_after_settle` phase、generation、lifecycle epoch 与当前 timer，不保存 handler、任意 panel/initData 或 destination registry。close reason parser 只认 `navigate_skills | navigate_materials | navigate_intelligence`；B4 当批仅 Skills enable，Materials/Intelligence 在任何 binding 消费、normal close 或目标 open 前明确拒绝。arm→coordinator-settled timeout 与 settled→Skills 的既有 opener timeout 各自独立；settled transition 在同一 lifecycle 锁内销毁前一阶段并进入后一 wait。pre-destructive 失败保持或恢复同一 exact Build DOM，退场后失败至多一次原生 Character rollback；competition、stale、timeout、navigation/热重载、socket、shutdown 和 lifecycle epoch 变化都会单次撤销，迟到 callback 不得重开或重复回滚。`returnFocusAction` 只解析 `skills | preparation-menu` 两个稳定 action key，拒绝近似值和 selector；B4–B6 当批 Host 只发送 `skills`，B7 已按同一 gate 把默认 on 输出切为 `preparation-menu`，显式 off 仍保留 `skills`。

B6 在该固定 enum 内启用 Intelligence，但不把它放入机械 `FixedPanelOpenWait`。exact coordinator settled 后，Host 在同一 lifecycle fence 内销毁 arm/timer、捕获 exact idle admission，并以内部构造的封闭 `{mode:"prod",source:"runtime",debug:false}` 同步打开 `intelligence`；该分支没有 AS2 nonce、没有 Skill/Material target timer，也不接受 Web 提供 panel/initData。admission/同步 open false 或 exception 在 destructive close 后至多启动一次 Character rollback；rollback 也失败时保持游戏态并提示从装备入口重试。competing intent/panel、epoch 前进、navigation/热重载、socket/shutdown、迟到或重复 settled 均零重开；Host 已接受的 open 不因后续 pause socket false/throw 被反转。

B5 只在这三个固定目标中启用 Materials。Native HUD direct 与 Character settled 都使用独立 material wait，并由 Host 生成 opaque `openRequestId`；AS2 `CraftingPanelService` 只对合法 token 原样回显，Host 只消费 exact `panel=crafting / source=nativehud_materials / initData={view:"materials"}` 封闭请求，再构造固定 runtime initData。missing nonce 仅在没有 armed material intent 且没有 target wait 时保持老 HUD ordinary open；pending 时拒绝但不消费 wait，携带 nonce 的 wrong/near-match 则终止当前目标。send-false/throw、target timeout、admission、competition、navigation/热重载、socket、shutdown、迟到与重复均有一次性 fence；Build 关闭后失败至多一次原生回滚。该实现仍是材料专用路径，不扩展为 registry、bus 或通用 return stack。

只有 Character 来源且已绑定 exact Skills instance 的 manage 页可显示“← 返回构筑”；`canReturnCharacterBuild` 只是 Host 投影的展示位，不是 Web capability。点击该按钮发送 strict `reason:"navigate_character_build"`，Host 再复验当前实例与 Skill idle/cleanup 状态；右上 `×`、物理 Esc 和 native backdrop 始终普通关闭到游戏。由于 Host 当前把物理 Esc 与 native backdrop 合并为同一 `panel_esc`，不得在前端文案或状态机里声称二者行为不同。帮助/确认模态与展开搜索先消费 Esc，返回按钮在写入、对账或清理未定局时显示 disabled，而不是吞点击。跨面板返回会销毁原 Skills DOM，焦点恢复不得保存旧元素引用；新 Character Build 只消费 Host 给出的封闭 presentation focus key：`PreparationNavigationV1` on 时首屏聚焦“整备”菜单触发器，显式 off 时才聚焦旧“技能配置”。前向自动回滚使用同一 gate 配对落点，反向打开失败则停在游戏并明确提示从“装备”入口重试。跨层完整契约见 [迁移护栏 §2.5](as2-web-panel-migration.md#25-角色构筑会话默认入口与双向导航屏障2026-07-28-工作树)。

> **当前 source-ahead 实现（ADR H1 已接通；未部署）**：只有 Character Build 发起并由 Host 绑定到 exact 子实例的 Materials / Intelligence 才可显示“← 返回装备”。`navigationOrigin:"character_build"` 与 `canReturnCharacterBuild:true` 都只是展示提示；真正的一次性 capability 只存在于 Host。Host-only 能力处于 `PendingInstanceBind` 时仍未授权任何同名实例；后续 ordinary crafting/intelligence same-name open 必须在 admission / initData enrichment 前原子撤销它，forward open 丢失、取消或迟到都不能授权后来普通打开的实例。Web 仅发送 exact 五键 envelope `{type:"panel",panel:"crafting"|"intelligence",cmd:"close",panelInstanceId,reason:"navigate_character_build"}`；Native HUD 直开、普通 `×` / Esc / backdrop、stale/rebound/foreign instance 均无返回能力并关闭到游戏。Intelligence 的返回动作只在 authoritative `state / bundle / snapshot / glossary_snapshot` 请求在途时禁用；tooltip 与后台 glossary catalog 不构成返回屏障，相关请求 settle 后恢复。Host 先完成当前子面板 visual 与领域 owner 的 exact retire，再走 fresh workbench nonce 打开新 Character session/snapshot，并按现役 gate 聚焦 `preparation-menu`；navigation/热重载、socket、shutdown、competition 或 lifecycle epoch 变化都撤销 one-shot。该实现没有建立通用 `returnTo`、跨 panel stack 或 destination registry；源码与自动门通过仍不等于 immutable candidate、游戏 E2E、promotion 或部署。

当前 source-ahead 工作树的最新 fresh 自动证据为 Host H1 定向历史门 `253/253`、Launcher 全量 `1902 pass + 3 explicit opt-in skip / 1905`、0 fail，Crafting 三视口 `119/119`、Intelligence `30/30`、Tuning 三视口各 `115/115`（model `61/61`、runtime `25/25`、confirmation `4/4`、interaction `7/7`、source marker `2/2`）、Character standalone 三视口各 `218/218`、workbench `867/867 + 12/12 + 18/18`、inventory modules `31/31`、dressup `222/222`、preparation leaf `10/10`、KShop `135/135`、item matrix `20/20`、ratchet `66/66`，default/release-tree strict UI audit 均 `0 error / 0 warning`。同一合并树的 Flash focused run 为 Tuning `a6f2a1abb3dd44189e9cd1ab4583490b`（`55/55 + 144/144`）、Character `a5d8512263894ded9540aedec991c643`（`539/539`）与 Item Panels `49b52f058b4046bdba5dcafffd6bb50f`（`28/28 + 46/46 + 144/144 + 36/36`），三轮均为 fresh trace/output/errors、Compiler `0/0`、32K retry `0`；publish-only `scripts/asLoader.swf` 为 1,065,911 bytes / SHA-256 `BAB9E46D140739F753262264DB326039432552783E87CC184DE8C423AD084CAB`，未编 main。数字只描述对应 runner 当次 source-ahead 树，不冻结长期 case 数，也不得外推为 candidate、游戏 E2E 或部署。

整备 IA 的 B1–B7 已完成源码原子切换。C# frozen tuple 固定为 `equipment / battlebox / tuning / skills / materials / intelligence`；`PreparationNavigationV1` 的代码默认和随仓配置均为 `true`，显式 `false`（以及配置项存在但不是合法 bool）才原子回退旧 Native/legacy HUD、Build `storage | stats | skills | help | close` 与 `returnFocusAction:"skills"`。on 时 Native/legacy 使用“游戏 / 整备”分组，Build exact-set 为 `preparation-menu | stats | help | close`；Host 只给 Build `initData` 投影严格布尔 `preparationNavigationV1:true`，off 时省略，非 Build 永不携带。Skills 返回、Skills/Materials/Intelligence 退场后失败回滚统一在 on 时投影 `returnFocusAction:"preparation-menu"`，off 时仍为 `skills`；该 focus key 只是无权限 presentation enum，不是 selector。

Web 只接受缺失或严格 boolean gate，错误类型与 gate/focus 不配对都拒绝 launch。on 菜单保持固定六项及 `current / local-view / post-close` destination kind；`preparationAvailability` 输入必须是 exact 六键，每项只含 `{visible,disabled,reason}`，输出才补 `current/destinationKind`。`questProgress <= 13` 时 battlebox/tuning 仍结构可见、disabled，并统一说明“完成基地整备后开放”；busy/reconcile 也保留全部项目与可读 reason，当前 equipment 项可聚焦、`aria-current`、disabled，激活零业务调用。菜单触发器的 click / Enter / Space 都执行 toggle，ArrowDown 总是打开并进入 roving menu；Tab/Shift+Tab 只关闭菜单，既不 `preventDefault`，也不人工移动焦点。菜单在 Stats、SecondaryPage/modal、view 切换、rebind、deactivate/destroy 时关闭并释放 document listener；reduced motion 保留静态结构。gate 只切 presentation，不修改 B2–B6 的 route authorization、nonce、admission 或 once rollback。

B7 与最终 header 真实性收口的 fresh 自动证据：菜单 leaf `10/10`、inventory modules `27/27`；production Character 三视口各 `277/277`、合计 `831/831`，另有 1024 hidden-body/生命周期 `12/12` 与三视口 normal/reduced 键盘/几何 `18/18`。新增真实 Edge 断言在 held-reconcile busy 窗口核对 stats/close hitbox、四个 action 的基线 accessible name、`error` cue、对应 reason toast（Close 含关闭语义）、恢复还原与零导航/统计/关闭穿透；激活采用真实浏览器内 DOM `.click()`，不冒充尚未直接注入的 trusted pointer/Enter/Space。Tuning 三视口 `96/96`、KShop `134/134`；Launcher focused `237/237`、全量 `1720/1720`。这些是 B7 当批历史快照，已由本节上方 H1–H6 合并树的 Tuning `115/115`、Character `867/867`、inventory modules `31/31`、KShop `135/135` 与 Launcher `1902 pass + 3 explicit opt-in skip / 1905` fresh rerun 取代，不得冒充当前整合树总数。本批没有修改 `.as` 或 Flash 资产，未编译/publish SWF，也未构建 candidate、执行游戏 E2E、promotion、部署或标准入口验收。

`EQUIPMENT_TUNING` 已是 B2 的 exact Host/AS2 opener：Host 只发送 `{profile:"battlebox",view:"tuning",source:"nativehud_equipment_tuning",openRequestId:<opaque>}`。AS2 回显 envelope 顶层必须恰好五键 `{task:"panel_request",panel:"workbench",source:"nativehud_equipment_tuning",initData:{profile:"battlebox",view:"tuning"},openRequestId}`，且 `initData` 恰好两键；任何携 exact source 或 `tuning.open.*` requestId 的请求都先按 tuning attempt 分类，缺键、多键、错层或近似 shape 一律 fail closed，禁止落入 ordinary workbench open。Host 继续绑定 generation、baseline panel/instance、admission、lifecycle 与一次消费，缺失、近似、迟到、重复、竞争中的请求全部 fail closed。成功后打开 standalone workbench tuning，不携带 `returnTo`；tuning 与 battlebox storage 在同一 Workbench instance 内本地切换，普通 Close/Esc 回游戏。legacy `legacy_equipment_tuning` 仍明确保留原生 renderer。当前默认 on 的 rollout 已把该固定命令投影到 Native/legacy 玩家 toolbar；显式 off 或非法配置才整体恢复旧 toolbar 并隐藏该入口，不能只关闭其中一层呈现。

B3 在同一 workbench instance 内增加了只接受 `build | storage | tuning` 的 feature-local `WorkbenchViewStack`。Build → Storage/standalone Tuning 在目标 ready 后才 commit，离开 embedded tuning 时先 exact detach；Storage → Tuning → 显式 Build 只做有界 ancestor unwind，不 finalize Character session、不释放 pause owner，也不重新开 Host panel。Esc 一次只消费当前 modal/info/tuning/storage 层；独立 HUD 打开的 storage/tuning 没有 Build ancestor，因此仍普通关闭到游戏。失败会恢复原 DOM、view stack 与 opener focus；controller 非预期回报只允许 reset 到三个封闭 view，不能扩为任意路由。B7 只把这些既有固定 handler 投影进生产菜单，没有扩大 view enum 或路由权限。

## 10. CSS 级联与文件治理

当前 `css/panels.css` 是纯 `@import` facade；历史样式按原顺序保存在 `panels/foundation-top.css`、`panels/foundation-rest.css`、`panels/features.css`，工作台样式物理拆为 `workbench/{tokens,core,profiles,inventory,skins,entities,crafting,equipment-inspector,skills,equipment-tuning,components,character-build,character-build-stats,states,motion,utilities}.css`。`profiles.css` 紧随 core 导入并独占壳级 profile tracks，`utilities.css` 保持最后一个 unlayered compatibility import。`tools/lib/read-css-bundle.js` 以与浏览器相同的顺序递归解析，拒绝循环、越根和丢失的外部 import；静态审计必须扫描聚合结果而不是只扫 facade。`launcher/build.ps1` 必须调用 `tools/check-workbench-css-bundle.js`，因此 transitive import 与本地 `url()` 闭包也是 candidate build 的 fail-fast 门；checker 与 reader 本身属于 runtime build recipe 身份输入。

新共享规则已使用 `workbench.components → workbench.states → workbench.motion` named layers；历史 feature/skin 仍暂时保持 unlayered，以避免物理拆分同时重排既有级联。下一阶段的目标层序仍为 `tokens → reset/base → shell → components → states → feature → skin → utilities`，但只有在跨面板截图与 computed style 对照稳定后才迁移旧规则。组件 selector 不得依赖面板祖先超过一层；skin 通过 token 或明确 `data-workbench-skin` 覆盖。语义 hidden 的迁移例外登记为 `WB-HIDDEN-001`：`utilities.css` 作为 `panels.css` 最后一个、且不进入 named layer 的 import，使用 `.workbench-shell [hidden] { display:none !important; }` 压过现役 unlayered feature/skin；静态门拒绝任何可见 `display:... !important` 反向覆盖。该例外只能在历史 feature/skin 完成分层并通过 computed display / hitbox / Tab 矩阵后退出；其他 `!important` 不得借此获得许可。

现役 feature/skin 的 unlayered 状态规则也意味着 named `workbench.states` 不能单独收敛所有终态。`states.css` 因此在 named baseline 之后保留两个窄的 terminal unlayered convergence：disabled `ChoiceGroup` 的 option，以及 blocked `CommitBar` 的主按钮/状态文案；它们只降低控件能量，不给父容器或阻断原因设置 opacity。规则位于 feature/skin 之后、使用封闭语义属性与足够 specificity，当前不需要 `!important`；若未来出现更高 specificity 冲突，必须先以真实 computed fixture 复现，再收窄 selector，确需 priority 时另行登记 ledger 理由和退出条件，禁止顺手把整组 opacity 或全局 disabled utility 加回来。Tuning 与 Loot 的活体 harness 分别证明原因/选中态、CTA/status opacity、对比度、尺寸和原生聚焦语义。

G5 已退出 G2 的 unlayered focus bridge：历史 feature/skin 的 `outline:none/0` 已删除，`states.css` 的 named baseline 现在是生产 focus ring 唯一来源，并由 `WB135` 拒绝 bridge 或其他未登记 unlayered focus outline 回流。无 skin 的 Loot、KShop 全控制族、Character slot/stats scroll 与 atlas 的 computed fixture 共同守门；`.character-build-slot` 只因 inner card 已消费 focus role 而保留 exact outer/inner 例外及 selected+focus 断言。

resolved `panels.css` 闭包中的全部现役 `!important` 由 `tools/workbench-important-ledger.json` 按文件登记上限、分类、原因与退出条件；未登记文件、计数增长、无理由条目或清理后不在同轮降低台账都会使 strict audit 失败。`WB-HIDDEN-001` 是迁移期间唯一新增的 semantic-hidden priority 例外；其他登记项只是待下降的历史兼容债务或 reduced-motion 跨 unlayered surface 的暂时语义例外，登记不等于认可继续扩张。

`inventory-workbench` 根暂时保留历史类名 `.kshop-workbench`，因为现役 `skins.css` 仍以它作为共享工作台 skin selector 命名空间；实际面板身份由 `data-workbench-skin=inventory|character|shop` 与领域 controller 决定，该类不表示商城路由或商城 authority。只有另开 CSS selector migration、完成 atlas 与各领域 harness 的 computed-style 对照后才允许改名，不在角色构筑视觉收敛轮为语义洁癖扩大级联变更。

新 selector、字号、transition、animation 和颜色必须通过静态治理门。F0 已把 commit `c96f4c3d750561022b706c72a4d53050431e627d` 冻结为不可改写的债务基线：触碰行必须清零，当前树的裸颜色、9px 玩家中文、裸 duration/easing 与 `transition:all` 总数不得高于基线。开发检查使用 Git baseline/touched-line 证据；生产 release policy 另外执行 history-independent 的 `--release-tree --strict-warnings`，只接收当前树低于 checked-in ceiling 的结果，并执行 ratchet 回归。当前 exact ceiling 为 raw color `2637`、`<9px` `0`、9px 玩家文字 `34`、raw duration `144`、raw easing `105`、`transitionAll` `16`；剩余 9px 只允许短数字、角标、符号和技术刻度。基线债务仍然存在，门通过不等价于所有旧色值或 skin 结构已经清零。

> **现役门（ADR E 已完成）**：`tools/workbench-ui-ratchet-baseline.json` 通过 `explicit-e-batch-handshake` 显式启用 profile gate。`WB128` 要求门握手完整；扫描器计入每个直接 `new ...DualPaneShell(...)`，只接受没有 spread/computed key/重复 `profile` 的封闭 options object literal，其中 profile 是合法字符串字面量，或所有结果叶子均为合法字符串字面量的条件表达式；非对象实参、shorthand、逻辑 fallback、arrow value、覆盖键与非法叶子都 fail closed。结构探针刻意只守可稳定证明的 literal 子语法：源码只有一个 `DualPaneShell` 声明，构造器顶层只有一个不可变 `const` 直接调用 `WorkbenchShellProfile.requireProfile(options.profile)`；验证前不得出现明确的 `this._root =`、构造器 `return` 或直接 `throw`，validated binding 不得被重赋值；随后只能有一次顶层直接 `this._root.setAttribute("data-profile", validated)` literal 写入。它不是通用 JavaScript CFG 或动态键/API 分类器；真实时序与次数由既有 Focus/Fake DOM 行为门证明：缺失/空 options 都以 `TypeError` 在零 DOM、零 attribute mutation 前失败，合法构造只对 exact root 写一次已验证值，非法 `setProfile` 零写、合法转换恰好一写。生产 consumer/count 清单与直接引用方式一并冻结，别名、解构、bracket/Reflect 间接引用默认失败；合法 profile 列表由运行时 `workbench-profile.js` 以 frozen `validProfiles` 单源导出，ratchet 与 profile 纯 Node 叶门直接消费，禁止维护副本。`WB129` 拒绝 feature 壳级 `grid-template-columns/rows` 覆盖以及无理由/无退出条件的例外。当前 ratchet 单测 `66/66`、Focus/Fake DOM `15/15`，strict 与 release-tree strict 都是 `0 error / 0 warning`：6 个生产构造调用缺失/非法/间接引用均为 0，feature 壳级覆盖与登记例外均为 0；WB040 的声明扫描同时覆盖 spaced `! important`、末声明省略分号及任意 `all:* !important` reset。只有 ledger 登记的 exact `display:none!important` 语义隐藏例外可存在，任何可见 display priority 必须失败，不能再用计数守恒替换复活 `[hidden]`。

现役 F 门已按“触碰模块清零、全局债务只降不升”执行：触碰行不得新增裸颜色、裸 duration/easing、8px 玩家文字或让 9px 中文承担正文/条件/错误。本轮已把长中文正文/条件/原因提升到至少 10px、主标签/名称/按钮提升到至少 11px，并只给 `.inventory-owned-grid`、Loot 双滚动面和 `.equipment-tuning-detail` 接入 exact 7px themed stable scrollbar；KShop categories 2px、NPC popover 6px 与 legacy 4px grid 保持各自已验证身份。生产 `DualPaneShell` 缺合法 profile 必须直接失败，feature 覆盖壳级 `grid-template-*` 默认失败，受控例外必须登记理由与退出条件。静态门继续与真实 overflow/computed fixture 成对验收，不能以 token 或 selector 存在冒充规范已经生效。

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

runner 的 error 表示几何、溢出、焦点、命中区、二级页覆盖或结构契约失败；warning 表示 reduced-motion 仍有动画等已登记债务。F0 之后 `--strict-warnings` 还会执行 touched-line / baseline ratchet；历史债务由冻结基线控制，不靠把既有债务重新打印成 warning 制造假红。

| 改动面 | 必跑 |
|--------|------|
| 共享 shell/entity/state/motion/CSS token/inspection viewport | static audit + 48 场景 atlas + inspection viewport Node gate + item-grid matrix |
| KShop / NPC / Crafting / Inventory / Skills / Tuning feature | 上述共享门 + 对应 feature harness |
| focus/modal/secondary page | atlas focus/secondary 场景 + 键盘人工走查 |
| reduced-motion/keyframes | atlas reduced 场景 + computed animation/transition 断言 |
| Host / AS2 authority | 本文门之外叠加 migration 闭环、xUnit、Flash fresh trace 与真机手测 |

截图用于人眼比较，不单独构成像素级通过证据；字体、Edge/WebView2 版本和资源闭包稳定前不启用脆弱的全图像素 golden。atlas 证明共享合同，不能替代各领域真实数据、滚动极值、中文长文案和游戏内动效验收。

现役 48 场景使用一套 synthetic shop/catalog DOM，三个 16:9 viewport 在固定 1024×576 逻辑画布下主要属于 scale/DPI 样本；它不能单独证明六种 profile、真实 header action budget、长材料下固定 CTA 或 blocked/selected/busy 联合状态。G2/G5 的 input/select/range/EntityTile/scroll 与 selected+focus 结论来自 KShop、Loot 和 Character 的真实 computed fixture，不能倒推为 atlas 单独覆盖了这些控制族。

> **现役证据（ADR E 已完成）**：六种生产 profile 都已有至少一个真实 feature DOM/fixture：KShop/NPC/Crafting recipes 覆盖 `catalog-decision`，Crafting materials 覆盖 `archive-reference`，KShop inventory/Storage/Loot 覆盖 `transfer-pair`，Skills manage 覆盖 `library-action-strip`，Skills trainer/standalone Tuning 覆盖 `library-decision`，Character Build/Stats underlay 覆盖 `character-build`。领域矩阵在真实 1024×576 最低逻辑画布上检查横向溢出、computed split、长中文/长列表、blocked/busy、固定 CTA 命中与键盘焦点；root CommitBar 与 body footer 也分别按 exact 结构标记验证。共享 atlas 继续保留，不与领域 harness 相互替代。

> **现役证据（ADR G2/G5 已完成）**：KShop production fixture 对 button、EntityTile、input、select、range 及 selected+focus 做最终 computed token 断言；Loot 以没有 `data-workbench-skin` 的真实 `transfer-pair` root 证明 named focus baseline 不依赖可选 skin；Character runner 分别验证 stats scroll 的 exact focus token，以及 slot inner-card focus token 与 selected border token 同时可辨。受影响的 NPC、Skills、Crafting、Tuning 领域 harness 和 atlas/matrix 同树通过，`WB135` 同时冻结无 bridge 回流。

共享验收至少要求同一源码树的 atlas、物品格矩阵与 `--strict-warnings` 静态审计全部通过；当前 fresh `48/48`、`20/20` 和 `0 error / 0 warning` 是对应门的完整成功结果，不是可从历史输出继承的永久状态。角色构筑另有 workbench、领域控制器和 dressup combination 三条 browser runner；它们必须覆盖三个视口、`55:45` 且右栏不少于 `360px`、1024 下左内层 Canvas 至少 `300px`、槽区按内容收缩到约 `204px` 并贴右、三组槽位末格与左 pane 右缘对齐、四药剂同排且内层零横溢出、左 PaneChrome 的“当前构筑 + 浏览摘要”在左且放大入口在右、无总槽位/分组重复计数、空候选 overlay 隐藏、routine 底部提示折叠、候选 action group 最多三项（装备/调制/卸下，药剂为装入）且无通用详情/pin、完整 `aria-label`、1024 单行无溢出、无独立动作行和底部重复 rail、单一 density toggle DOM、候选 full/compact 往返零业务流量、stats 3×3 与抗性 4×2/2×4、power `data-scale=log10` / resistance linear、八 SVG `aria-hidden`、负值/缺值/全零降级、同一 Canvas/renderer identity、`空手/长枪/手枪/手枪2/双枪/兵器/手雷` 七种 battle pose 的当前状态结构骨架 fit envelope，并证明 `手雷站立` 真实消费 `手雷_装扮` 而非空手兼容、放大页 Canvas-only wheel/`+/-`/drag/arrows/full-view reset、关闭复位、嵌入态不吞输入、inert/focus/Esc、11+4 槽位、无 pin 且随 operation/focus 更新的“调制说明”、检视 modal/内联说明逐层 Esc 与权威写后刷新。纯几何 envelope 回归另由 `node tools/test-dressup-stable-fit.js` 固定，未传 envelope 的 renderer 默认路径也必须覆盖。case 总数随契约增加而变化，本文不冻结最终数字；验收只引用同一源码树的完整 runner 输出。Browser harness 仍须按受影响领域分别执行，不能用 atlas 数量替代。

## 12. 例外与变更流程

偏离本文必须在变更中说明：业务原因、受影响 profile/primitive、最低视口、键盘与 reduced-motion 结果、退出或长期保留条件，并更新 atlas/harness 样本。一次性施工记录可以放在 `docs/`，但稳定规则只回写本文；其他入口文档只保留摘要和链接。

## 13. 本轮审视结论与后续优先级

2026-07-29 的复核表明，shared primitive 与生命周期基座已经成立，但布局、交互真实性、视觉 token 和 motion 在生产 feature 中尚未全部落地；“规范存在”不得写成“实现已治理”。

| 维度 | 已验证的现役基础 | 仍需按 ADR 闭环的真实缺口 |
|------|------------------|----------------------------|
| 布局与密度 | 1024×576 逻辑画布、48px header、owned 68/48/40 基线；六种封闭 profile 已由 Shell fail-fast 校验、`profiles.css` 与真实领域 fixture 接通，KShop/Inventory 原位 view 原子同步 profile，Skills/Crafting 重建时按目标 view 构造，compact 不再改变宏观 split | 后续新 consumer/profile 仍须先更新本 canonical 映射并补最低画布真实 fixture；不得把 E/G1–G5 或定向视觉 F 局部完成外推为剩余视觉债务已核销 |
| 交互真实性 | G0/A1 已冻结 semantic hidden、Help/HeaderProjection 与显式导航计划；A2a/A2b 已完成 Tuning 共用 mode、固定 CommitBar、source、稳定 preview DOM 与全控制族锁投影；A3 已完成 shared SecondaryPage、Help、player-copy、键盘 inspection/blocked inspection 收口；A4 已固定 Crafting 决策结构；C1/C2/C3 已分别完成候选 counts、rich tooltip 与 candidate tuning 的 authority 纵切；ADR H1 已在 source-ahead 树接通 Character 来源 Materials/Intelligence exact 返回 | 未纳入本批的领域极值仍须按各自 authority 纵切闭环；H1/C3 自动门不能外推为游戏 E2E、promotion 或部署 |
| 视觉层级 | semantic token、字号下限、Character Build/Stats 的角色色实践和 shared empty/state CSS 已存在；F0 建立 touched-line / baseline ratchet，本轮定向 F 已清零 `<9px`、把玩家正文/原因与主标签提升到角色下限、给三个真实溢出面接入 exact 7px scrollbar，并移除 Choice/Loot 的整组 blocked opacity；G5 已让 layered focus baseline 成为唯一生产来源并以 `WB135` 阻止 unlayered 回流 | 剩余 raw color 与 skin 结构债务继续按独立原子批收敛；不得把本轮定向完成外推为旧 CSS 全量清零，也不得为追求数字归零重写未触碰领域 |
| 动效 | micro/standard/structural/reject/busy/ambient token 已由 G1–G5 接通 shared structural、焦点层叠、语义 fragments/KShop consumer、shell root reduced shutdown 与 exact workbench Tooltip owner；工作台 `.001s/.001ms` 已清零，Tuning 静态补偿及 Character/Inspector/Tuning 的实际静态终态已有 normal/reduced 门，ratchet raw duration ceiling 已继续下调 | 其余 feature unlayered structural 绕过与 named-layer 扩围仍需按 G6+ 收敛；非工作台 `task_panel.css` 的 `0.001s` 和 lockbox 动效明确不在 G4 范围 |
| 可访问性 | EntityTile 激活、tooltip scope、FocusScope trap/inert/Esc/opener restore、shared SecondaryPage exact action、Tuning source/lock、KShop/NPC inspectability、QuantityControl 键盘合同与双宿主 WebView2 自动策略矩阵已具备；G2/G5 已以真实 fixture 覆盖 button/EntityTile/input/select/range/scroll 和 selected+focus 的 role-token focus ring；exact candidate 已在本机 150% DPI 下完成双宿主 production/development 实机输入 smoke | Native top-tool 独立键盘 focus 仍未建立；100% DPI 与真实触控/触控板 pinch 尚无物理设备证据，不能把 150% smoke 或 CDP 合成输入外推为完整 D 批 E2E |
| 整备与 Native HUD | B1 frozen tuple、off/on 两套 HUD geometry fixture、统一 progression reason、B2 exact `EQUIPMENT_TUNING` opener、B3 Build/Storage/Tuning 有界局部导航、B4 封闭三目标 post-close intent/两阶段 timeout/双值 focus parser、B5 Materials exact handoff、B6 Intelligence 同步 exact admission、B7 默认 on 的两套 HUD/Build menu/Host focus/Web fixed mapping 原子切换，以及单一 `RightContextSlotOwner` 已落地 | 仍需真实 Native/legacy HUD 与 WebView2 游戏旅程、显式 off 回退旅程、candidate/E2E/promotion/标准入口验收；通过源码自动门不等于已部署 |
| 前端架构 | 单 Bridge router、generation-aware mux、DisposableStack/PanelLifecycle、`InventoryWorkbenchHeaderProjection`、封闭 Shell profile、shared SecondaryPage 及 feature-local navigation/confirmation/interaction/crafting presenter 已落地 | 其余能力继续接通现有 primitive，不建立 action DSL、layout registry、StagedCommandBar 或引导引擎 |
| 视觉验证 | 共享 atlas、物品格矩阵、六种 profile 的真实领域 browser fixture、F0/E 静态 ratchet、G1–G5 computed 门，以及本轮 Tuning disabled ChoiceGroup、Loot blocked CommitBar、三类真实 scrollbar overflow/pseudo computed、Character preparation menu 的 42px 单列与 normal/reduced 键盘几何均已提供可执行证据；双宿主 150% DPI production/development smoke 已完成 | atlas 仍只是一套 synthetic DOM 的 scale/DPI 矩阵；它不替代后续剩余颜色/skin/G6+ 的逐段视觉债务核销、100% DPI/真实 pinch 或完整人工游戏旅程 |

本轮后续的 B7 真实游戏/标准入口验收、D 批剩余 100% DPI/真实 pinch，以及剩余颜色/skin 与 G6+ motion/cascade 原子批次，以 2026-07-29 ADR 为准。B7/C3 和本轮定向视觉 F 已闭合源码与自动门，但不能冒充游戏 E2E、promotion 或部署；D 的 exact candidate 只用于双宿主 150% 输入 smoke；E/G1–G5 的 Shell/profile、SecondaryPage、focus、语义 motion 与 reduced-motion 代码/fixture 也不能外推为旧 CSS 全量治理完成；全面 named-layer 化、像素 golden 与物理拆分仍不得与领域任务流重构混成一个大批次。
