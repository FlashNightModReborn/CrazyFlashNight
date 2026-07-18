# 双栏工作台 UI 系统约束

**文档角色**：双栏工作台范围的布局、交互、美学与前端工程 canonical doc。跨 AS2 / Host 的协议与权威闭环仍以 [as2-web-panel-migration.md](as2-web-panel-migration.md) 为准，验证入口以 [testing-guide.md](testing-guide.md) 为准。
**最后核对代码基线**：commit `711c469036ad6b1226833faf255499abb1ebf2ed`（2026-07-18）+ 当前工作台回归修复工作树。

本文适用于 `kshop`、`npcshop`、`crafting`、独立 `workbench`、嵌入式装备调制和 `skills` 中采用双栏工作台语言的视图。它约束玩家态 UI，不把 dev harness、诊断面板或协议调试页误当成生产视觉标准。

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
| `transfer-pair` | 背包—战备箱、背包—仓库 | 两个可操作容器近似对称；容量差异只能做受控 token 覆盖 |
| `library-action-strip` | 技能管理 | 全宽库 + 固定 Hotbar；密度只作用技能库 |
| `library-decision` | 技能教师、调制候选 | 目录/候选 + 固定信息量的预览提交区 |

任何新 profile 都必须先进入本文，说明适用角色、最小画布和验证样本；禁止只在单个 feature CSS 中创造隐式第五种结构。

### 2.2 纵向节奏

生产工作台按“`48px` 顶栏 → PaneChrome / 筛选 → 可滚内容 → 决策 footer”排列。常态状态、指标和 action group 不应因为文字变化推动标题或关闭按钮。二级页从顶栏下沿覆盖整个 workbench body，不在底层双栏上叠半透明可点击内容。

PaneChrome 承担标题、面包屑、meta 和筛选工具；业务内容不得再造第二套局部顶栏。FlowRail 是关系提示，不是常亮主 CTA：待命时低能量，只有拖拽接收、权威 pending 或预览更新时提升亮度。

### 2.3 溢出与空态

- 横向滚动只允许领域明确需要的连续轨道；目录、卡片网格、面包屑和顶栏 action group 不得产生嵌套横向滚动。
- full 模式必须能读到主名称和关键状态；空间不足时减少列数，不得把 full 退化成“略大的 compact”。
- 空态分为 `empty`、`filtered-empty`、`unavailable`、`error`；每种都提供下一步动作或原因，不用装饰填满空白。

## 3. 密度与实体格

共享尺寸基线：完整 owned 卡高度 `68px`；紧凑 owned 实体格 `48px`、图标 `40px`、间距 `4px`。KShop / NPC 目录 compact 使用固定 `54px` 图标瓦片，不把自适应列宽分摊到每张卡；目录 full 的可读列宽不得低于 `128px`。最低画布下仍须满足领域容量目标，例如战备箱 40 格、调制候选 25 格的无滚动可达性。

`full` 显示名称、核心 meta、价格/数量/状态与必要动作；`compact` 以图标和角标为主，隐藏语义正文后必须通过键盘可达的共享 tooltip 或可见详情提供同等信息。Hotbar、权威预览、材料核算和提交区不随目录密度压缩。

商城 compact 的加购动作采用 `24×24px` 透明 hitbox 包围 `16×16px` glyph；默认只保留低能量深色角标，hover / focus-visible 才点亮。按钮不得重新铺满实体格，也不得以缩小命中区换取视觉留白。空槽与有内容的 compact 卡共享同一固定宽度，禁止按内容收缩。

实体格抽象采用可组合 primitive，而不是万能卡片：

- `EntityTile`：icon、body、name、meta、badge、action、state slots；
- 领域 presenter：把商品、owned slot、技能、配件候选投影到 slots；
- capability adapter：声明 select、transfer、inspect、discard、buy 等意图；
- tooltip adapter：提供 pointer 与 focus 共用的内容和生命周期。

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

## 6. 命中区、键盘与焦点

- 图标控件透明命中区至少 `24×24px`；紧凑实体格和可点击卡至少 `44px`；主 CTA 高度至少 `40px`。
- 可视 glyph 可以小于命中区。紧凑商城加购、调制单拆等角落动作统一采用“小 glyph + 大 hitbox”，不能用放大按钮遮挡物品图主体。
- pointer 点击/拖拽必须有 Enter/Space 或明确快捷键等价；hover 才出现的信息必须由 `focus-visible` 同样触发。
- 所有可操作实体必须有包含名称与当前动作的 `aria-label`；仅写“加入”“查看”不合格。
- focus ring 必须可见、与 skin 协调且不能只依赖浏览器默认蓝框；禁止全局 `outline:none` 后不给替代。

模态框与二级页必须：设置可关联标题、把焦点移入、trap Tab/Shift+Tab、使背景 inert/不可聚焦、Esc 按域规则关闭、关闭后归还 opener。二级页不是普通 DOM `display` 切换；它与 modal 共用焦点栈和底层禁用语义。

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
- `workbench-components.js`：SecondaryPage、ChoiceGroup、CommitBar、OwnedInventoryPane；所有 open/close/destroy 回调都必须容忍重入和异常，并保持 DOM、focus stack 与业务 active 状态一致。并列 SecondaryPage 按打开顺序形成模态栈，只允许顶层页进入可访问树；关闭顶层恢复下层，关闭被覆盖下层不得在后续 unwind 中复活，焦点须沿 opener 链跳过已关闭页。

共享异步 tooltip 同时记录 pointer/focus 活性和 owner 顺序。临时 hover owner 离开或销毁后，应恢复仍聚焦的上一 owner；anchored 内容从占位更新为富内容、字体或图片迟到时，必须以 transform 后的物理尺寸重新测量并夹紧视口。

## 9. 组件边界

推荐共享边界：

| primitive | 共享职责 | 不应承担 |
|-----------|----------|----------|
| `DualPaneShell` | 画布、header、profile、slot、FlowRail | 领域请求与 ViewModel |
| `WorkbenchDialog/SecondaryPage` | focus stack、inert、Esc、opener restore | 交易/学习/调制规则 |
| `HeaderToolbar/ChoiceGroup` | action group、pressed 状态、窄宽退化 | 持久化偏好和 wire |
| `EntityTile/ItemGrid` | 几何、密度、状态 slots、键盘入口 | 物品 taxonomy 与价格 |
| `OwnedInventoryPane` | pager/filter/sort/grid/selection 机械能力 | transfer/sell/discard 权限裁决 |
| `AuthorityPreview/CommitBar` | 核算布局、阻断原因、单 CTA | token 校验和 commit |
| `PanelRequestMux/Router` | callId、timeout、session 分发 | 各领域 envelope validator 与 reconcile 策略 |
| `DisposableStack` | 幂等清理 | 业务状态 |

共享层只抽“相同原因而变化”的部分。仅 DOM 相似、但 authority 或失败恢复不同的代码不得为了减少行数合并。

物理拆分遵循“facade 只编排、presenter 只投影、runtime 才持有领域时序”：KShop 的 cart/catalog/owned/tooltip、Inventory Workbench 的 config/header/quick-transfer/owned-view、NPC 的 secondary pages、Skills 的 library/loadout/trainer/interactions/render/diagnostics、Equipment Tuning 的 model/render 均为显式依赖模块。它们不得自行拥有 Bridge listener、authority token 或跨面板 session；懒加载表必须先加载共享 runtime/生命周期/焦点/primitive/component，再加载 feature module，最后加载 facade。

## 10. CSS 级联与文件治理

当前 `css/panels.css` 是纯 `@import` facade；历史样式按原顺序保存在 `panels/foundation-top.css`、`panels/foundation-rest.css`、`panels/features.css`，工作台样式物理拆为 `workbench/{tokens,core,inventory,skins,entities,crafting,skills,equipment-tuning,components,states,motion}.css`。`tools/lib/read-css-bundle.js` 以与浏览器相同的顺序递归解析，拒绝循环、越根和丢失的外部 import；静态审计必须扫描聚合结果而不是只扫 facade。`launcher/build.ps1` 必须调用 `tools/check-workbench-css-bundle.js`，因此 transitive import 与本地 `url()` 闭包也是 candidate build 的 fail-fast 门；checker 与 reader 本身属于 runtime build recipe 身份输入。

新共享规则已使用 `workbench.components → workbench.states → workbench.motion` named layers；历史 feature/skin 仍暂时保持 unlayered，以避免物理拆分同时重排既有级联。下一阶段的目标层序仍为 `tokens → reset/base → shell → components → states → feature → skin → utilities`，但只有在跨面板截图与 computed style 对照稳定后才迁移旧规则。组件 selector 不得依赖面板祖先超过一层；skin 通过 token 或明确 `data-workbench-skin` 覆盖。`!important` 只允许暂存于迁移兼容层，并登记退出条件。

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
node tools/run-item-grid-visual-matrix.js --shot=tmp/item-grid-visual-matrix.png
```

runner 的 error 表示几何、溢出、焦点、命中区、二级页覆盖或结构契约失败；warning 表示 reduced-motion 仍有动画等已登记债务。`--strict-warnings` 用于债务清零后的 ratchet，不应在未治理基线上制造假红。

| 改动面 | 必跑 |
|--------|------|
| 共享 shell/entity/state/motion/CSS token | static audit + 48 场景 atlas + item-grid matrix |
| KShop / NPC / Crafting / Inventory / Skills / Tuning feature | 上述共享门 + 对应 feature harness |
| focus/modal/secondary page | atlas focus/secondary 场景 + 键盘人工走查 |
| reduced-motion/keyframes | atlas reduced 场景 + computed animation/transition 断言 |
| Host / AS2 authority | 本文门之外叠加 migration 闭环、xUnit、Flash fresh trace 与真机手测 |

截图用于人眼比较，不单独构成像素级通过证据；字体、Edge/WebView2 版本和资源闭包稳定前不启用脆弱的全图像素 golden。atlas 证明共享合同，不能替代各领域真实数据、滚动极值、中文长文案和游戏内动效验收。

当前自动基线为：atlas `48/48` 且 `0 error / 0 warning`；物品格矩阵 `14/14`；静态审计 `0 error / 0 warning`；共享 runtime/lifecycle/focus/focus-integration/primitives/components 与各拆分 presenter/model 的纯 Node 门全部通过。Browser harness 仍须按受影响领域分别执行，不能用 atlas 数量替代。

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
| 文件治理 | `panels.css` 收敛为 14 行 facade；工作台 CSS 分域；主 facade 均低于当前行数预算（KShop 840、Inventory 949、NPC 911、Skills 1168、Tuning 717、Workbench 951） | 历史 `panels/features.css` 与旧 unlayered cascade 继续分阶段迁移；不得与大规模视觉改版同轮重排 |
| 视觉验证 | 48 场景 atlas、14 项物品格矩阵、五个领域 browser harness、严格零 warning 静态门 | 字体/Edge/WebView2/资源闭包稳定前不启用全图像素 golden；自动 Edge 证据不替代游戏内动效与真实存档验收 |

因此当前值得“现在完成”的债务是响应 listener、多实例生命周期、焦点栈、实体格密度、重复 presenter、超大 facade、CSS 物理边界和可执行验证门；这些已治理。旧样式全面 named-layer 化、像素 golden 与更细粒度 feature CSS 拆分属于下一阶段工程，不是以继续缩短文件为目的立即施工。
