# LoadoutPicker 抽离与佣兵换装二期 设计（2026-08-24）

**状态**：施工完成，自动门禁全绿，待人工验收（§7；验收通过前不提交）。本文档是 2026-08-24 三策略评估（抽离共享组件 / 蓝本复制 / 分阶段）的收口结论兼实施规格；抽离边界、ports 契约、协议扩建字段、分步门禁为施工契约，实现不得静默偏离，被迫偏离必须回写本文档（已回写于 §11）。

**决策记录（2026-08-24 拍板）**：① 抽离与佣兵接入同列车，不做蓝本复制过渡；② 跨槽拖放所需协议扩建排进二期；③ 抽离边界与第三消费者约定落在本文档。

## 0. 范围与出范围

二期范围：

- 从角色构筑（character-build）交互层抽离共享组件 **LoadoutPicker**（候选五态、兼容/背包 scope、requestKey 栅栏、拖拽接线、落点策略接口、槽位网格）；抽离施工当时以 character-build 行为零变化为门，本日测试反馈后的契约修订见 §11.4；
- 佣兵面板（merc-panel）装备调配区块重构：11 槽单列 → 槽位图标网格 + 常驻候选栏，接入 LoadoutPicker，支持拖拽换装（含跨槽）、双击提交、写后状态保持；
- 协议扩建：`mercLoadoutCandidates` 增加背包总览 scope 与逐候选跨槽可写白名单（对齐 `equipmentEligibility` 契约形状）；
- 顺手消除一期遗留滚动痛点（写后整列重建弹回顶部、快照刷新无条件关闭浏览器、候选浏览器确认即销毁）。

出范围：

- 佣兵会话 / 写通道 / 三态徽章语义 / 取回 / `canOperate`/`combatLocked` 门——保持 merc 私有，不进共享层；
- character-build 的 session / transport / contract / mutation / 三 revision / 药剂槽 / 调制——保持 cb 私有，不进共享层；
- 手雷槽（下标 16）维持只读，仍归未来手雷玩法列车；
- 出战佣兵现场重建（二期换装仍下次出战生成时生效）；
- 肉鸽 / 战术携行集消费者本身（见 §9，只留 ports 注记，不写推测性接口）。

## 1. 背景与一期痛点（代码层证据）

佣兵装备托管一期（`docs/佣兵装备托管-设计-2026-08-23.md`，commit `b994d87b05`）协议与数据层已收口；痛点全部在 Web 视图层：

- 培养页右栏为单列长滚动列（特质 → 技能 → 11 槽单列 → inline 候选浏览器宿主，`merc-panel.js:1756-1785`）；全文件无滚动锚定（无 `scrollIntoView`）；
- 写入成功后 `renderDetailPage()` 清空重建右栏（`merc-panel.js:1756`），scrollTop 归零；且开头无条件 `closeLoadoutBrowser()`（`merc-panel.js:1694`），快照刷新等无关事件亦销毁已开浏览器；
- 候选浏览器单槽 scope、确认即销毁（`merc-panel.js:2130`），10 个可写槽逐槽换装 = 10 次「滚到槽位 → 点交付 → 滚到底 → 选 → 确认 → 被弹回顶部」循环；
- 候选列表 `max-height:202px` 独立滚动区嵌在右栏滚动列内（`team.css:1931-1935`），双层卷屏。

角色构筑的交互形态（左复合 pane + 右侧常驻候选对比栏、选槽联动、单击预览、双击/拖拽提交）已被验证；其机制基元（`PointerDragController`/`InteractionBroker`/`RovingGridFocus`/ChoiceGroup/五态渲染、拖拽视觉 `core.css:343-346`）全部为领域无关共享层。

## 2. 策略决策：抽离而非蓝本复制

评估对比（证据：`character-build-candidate-pane.js` 隐式宿主原型契约 20+ 字段、`:205-207` 硬编码三 roving；cb 门禁 1095/1095 × 3 视口、~129 处 debugState 断言、~80 处 DOM 标记断言、`audit-workbench-ui.js:865-871` 行数预算）：

- 蓝本复制≈新增 700±200 行且交互层最终将存在三份（cb + merc + 肉鸽）；抽离一次付清，ports 对着 cb + merc 两个真实消费者设计，非真空投机。
- 第三消费者真实存在于路线图：肉鸽 / 战术携行集（`docs/AS2-Launcher持久状态权威与战术携行集-长期演进调研-2026-07-23.md` CombatLoadout，尚未收敛 ADR）。该文档同时明令「不再复制特性专用分布式事务」，与本文档「会话层不共享」的边界同向。
- 玩家惯性：原 AS2 UI 为拖放风格，拖放是二期硬需求。抽离后共享的恰是玩家可感知的交互层（拖拽手感、落点高亮、五态、回滚），三面板操作惯性天然一致。

**传导边界的诚实声明**：共享层只承载交互编排（浏览-选择-拖拽-五态-回滚）；会话、revision、写闸门、对账、协议契约永远各面板私有。未来「角色构筑优化自动反馈到佣兵」仅在交互层成立。

## 3. LoadoutPicker 边界设计

**原则**：picker 拥有「浏览-选择-拖拽-五态-回滚」的交互编排；不拥有协议、会话、revision、动词语义、纸娃娃。

### 3.1 目录草案（`launcher/web/modules/loadout-picker/`）

- `loadout-picker.js` — 组合根；`install(host, ports)` 显式装配（把 cb candidate-pane 的隐式原型契约形式化为成文 ports，这是抽离工作量的主体与 80% 回归风险集中点）。
- `loadout-picker-candidate-state.js` — 现 `CandidateState`（`character-build-candidate-state.js:61-88` 已是 options 注入、无协议依赖）近乎平移，类名/文案经 ports 注入且**默认值保留 `character-build-*` 前缀与原中文文案**。
- `loadout-picker-drop-policy.js` — 现 `drop-targets.js` 的 `resolve/decide/rejectCopy` 提为策略接口；kind 词表与药剂判别（`isDrugRow`，`drop-targets.js:33-37`）参数化为 port。
- `loadout-picker-candidate-drag.js` — PointerDragController/InteractionBroker 接线 + drop-hint；`workbench-drop-*/drag-ghost` 视觉沿用共享 `core.css`。
- `loadout-picker-slot-grid.js` — `_renderSlotGroup`（`character-build-loadout-presenter.js:122-179`）参数化：槽位定义、分组、角标 hook、tooltip placement。
- `css/workbench/loadout-picker.css` — 候选/slot/pane 三段（约 300-400 行）自 `character-build.css` 切分；类名前缀策略 = 保留原名作默认值。

### 3.2 Ports 契约（宿主注入）

- `slotDescriptors() → [{rovingKey, kind, id, label, writable, blocked?}]` — cb 来自 `character-build-template.js:10-22`；merc 来自 `merc-data.js:5-20` + `isWritableLoadoutSlot`（`merc-panel.js:1936-1939`）。
- `fetchCandidates(target, scope, requestKey, cb)` — 栅栏契约成文（迟到回包不复活）；cb 走 `Session.requestCandidates`，merc 走 `loadout_candidates`。
- `equip(slotKey, candidate)` / `remove(slotKey)` — 动词集注入：cb=装备/卸下/装入；merc=交付/替换/取回。
- `eligibilityProvider(candidate) → {slots:[...]}` — 跨槽可落白名单来源；cb=现有 `equipmentEligibility.slots`，merc=§6 协议扩建后的 `eligibleSlots`（未落地前降级为仅当前槽）。
- `interactionState()` 映射 — cb=会话态；merc=`canOperate` 门 + 写入 busy。
- `texts` — 五态文案 / 通知 / 动词文案。
- `preview(candidate)` — 纸娃娃联动 hook；merc 复制 `_renderPortrait` 思路（`character-build.js:297-323`）经 MercPortraits 临时换装。
- `renderOwnedSlot` / `iconHtml` / `bindTooltip` / density — 沿用现注入件。

### 3.3 抽离分步（每步独立可发布、独立过门）

1. candidate-state + drop-policy + candidate-drag（近域无关，先出）；
2. slot-grid + action-bar 动词注入；
3. candidate-pane 状态机形式化（隐式契约 → ports；回归风险最高，单独成步）；
4. merc 消费者接入（§5）。

**保绿纪律**：保留 `character-build-*` 类名与 `debugState` 键形状作默认值，cb harness 目标零断言改动；每步更新 3 个加载清单（harness ×2 + panels registry）、2 个 runner 静态资产门（`run-character-build-workbench-harness.js:660-714`）、`audit-workbench-ui.js` 模块清单（`:104-126`/`:1119-1125`）与行数预算（`:865-871`）。

## 4. 协议扩建（AS2 / Host）

目标交互「背包总览下拖一件装备到任意高亮兼容槽」依赖逐候选跨槽资格白名单；一期 `loadout_candidates` 按 slotKey 逐槽拉取、候选仅带单槽 `eligible/lockReason`（`merc-panel.js:2194-2201`），不够。

- `MercLoadoutService.buildCandidates(merc, slot)` 扩展为 `buildCandidates(merc, slot, scope)`：`scope:"slot"` 维持现状；`scope:"backpack"` 返回背包全部装备候选，逐物品对全部可写槽（6..15）跑 §2 policy，产出 `eligibleSlots:[6..15]`（数字槽号数组；空数组 = 全局不兼容，仍携带以支持背包视图置灰）。50 格 × 10 槽 = 500 次纯函数评估，AS2 单次调用开销可接受，focused 测试附性能冒烟。
- 契约形状对齐 cb `equipmentEligibility.slots`（`character-build-session-contract.js:109-131`），但用数字槽号，不引入中文槽名。
- 命令不变：仍走 exact `loadout_candidates`（请求增 `scope` 字段），**Host 允许表 / MercTask 映射零改动**；响应 schema 扩展向后兼容（旧 scope=slot 调用方不受影响）。
- revision / 锁存 / 错误码语义不变；候选响应仍带 `loadoutRevision`。

## 5. 佣兵面板接入设计

- **布局**：`renderEquipManage`（`merc-panel.js:1882-1932`）与装备区宿主（`:1771-1785`）重构为内两栏——左列槽位图标网格（护具组 6..11 + 武装组 12..15，3 列紧凑网格，槽 16 手雷只读随行尾），右列常驻候选栏（五态、兼容/背包 scope、独立滚动区，不再内嵌列表底部）。特质/技能区块不动，仍在装备区上方；候选栏与槽位网格同区同屏，消灭一期「滚到底找浏览器」。
- **交互**：点槽 → 候选栏联动（requestKey 栅栏 + 乐观切换回滚，沿用 cb 模式）；候选单击 = 纸娃娃预览联动（§3.2 preview port）；双击 / 主按钮 / 拖拽 = 提交。拖拽落点策略 = merc 版 drop-policy port：可写槽 6..15、无药剂分支、`eligibleSlots` 白名单裁决、custody 槽落点 = 替换语义。
- **保留 merc 方言**：三态徽章（`TeamShared.buildCustodyBadge`）、取回按钮、`canOperate`/`combatLocked` 灰牌、交付/替换/取回动词文案；手雷 16 无按钮。
- **滚动痛点根治项**（与组件选型无关的确定收益，必须同列车带走）：写入成功后改为局部刷新装备区（不再整列 `clearElement` 重建）；快照刷新不再无条件 `closeLoadoutBrowser()`——浏览器状态（打开槽位、scope、选中候选）随装备区局部重建恢复；scrollTop 保持。
- merc 侧适配层落 `launcher/web/modules/merc/` 新 leaf（组合、drop-policy、channel），`merc-panel.js` 减重；写路径 `onLoadoutWrite`/`_loadoutCandidatesSeq` 栅栏语义不变。

## 6. 测试矩阵

**AS2 focused**（`scripts/run-merc-loadout-tests.ps1` 增补）：scope=backpack 逐候选 `eligibleSlots` 与单槽 policy 逐点一致；空背包 / 全不兼容 / 混合锁定原因；旧 scope=slot 响应字段回归；500 次评估性能冒烟；`loadoutRevision` 随写递增不变量。回归 97/97 基线 + ManagedLongGun 126/126。
**Host**：允许表/映射零改动，MercTaskTests 全族不回归；Launcher 全量不回归。
**Web**：
- cb harness 1095/1095 × 3 视口全绿，目标零断言改动（保类名/debugState 纪律）；cb 独立 view harness（`character-build/dev/harness.html`）加载清单更新；
- team harness：钉 `.team-managed-gun-browser/candidate/count/commit` 与「确认交付」文案的 ~6 组断言（`team/dev/harness.html:1482-1535`）改写为 picker DOM；新增 merc 换装专项（合成 PointerEvent 拖拽交付/替换、跨槽落点高亮与拒绝文案、双击提交、五态、scope 回滚、写后浏览器状态保持与 scrollTop 保持、快照刷新不关浏览器）× 3 视口；T800/pet 专项不回归；
- `test-panel-runtime.js` 41/41、`audit-workbench-ui.js --strict-warnings`（含新行数预算）、`check-workbench-css-bundle.js`、`node --check` 全改动文件。
**文档**：本文档 + `战队面板-双栏工作台翻新-设计-2026-08-03.md` §3.2 布局描述更新 + testing-guide 增补新门 + `node tools/validate-doc-governance.js`。

## 7. 人工验收窗口（自动门不代签）

真实 Flash/存档验收：佣兵连续多槽换装全程无反复卷屏；拖拽交付/替换手感与 cb 一致（含跨槽高亮与拒绝反馈）；双击与按钮提交等价；取回回落预设；出战切换 / 快照刷新后浏览器状态保持；三视口观感；与 cb 面板并排对比操作惯性一致。

## 8. 抽离触发条件成文（防遗忘约定）

LoadoutPicker 演进约定：① 第三消费者（肉鸽 / 战术携行集）ADR 落地时以其真实需求扩展 ports，禁止预先设计推测性接口；② picker 每次改动同时背 cb 1095×3 + team ×3 两套门禁；③ 若未来某面板需要交互层分叉行为，先经 ports 注入表达，禁止 fork 回私有副本。

## 9. 第三消费者注记（肉鸽 / 战术携行集）

调研文档（2026-07-23）方向：CombatLoadout / 战术携行集（活动装备 + 武器运行态 + 8~12 类战斗补给 + 快捷物品 + 战斗技能）、RogueRun 独立可恢复状态、不退出 Launcher 热切换。其「战前构筑」场景的交互形态（槽位网格 + 候选 + 拖拽）与 LoadoutPicker 同构，预期 ports：`slotDescriptors`（携行集槽）、`fetchCandidates`（背包/携行集双源）、动词集（装入/取出）、`eligibilityProvider`（肉鸽规则允许的临时道具白名单）。**以上仅为注记，不构成接口承诺**；肉鸽列车开工时先补 ADR 再动 ports。

## 10. 风险与纪律

- **回归面**：cb 侧触动 10+ leaf + view/controller 接线 + CSS 切分；纪律 = 类名/debugState/脚本注册顺序保留，分步发布，任何一步 1095×3 变红即回退该步。
- **协议风险**：scope=backpack 的 500 次评估若实测超标，降级为 AS2 只算当前槽 + Web 侧按 use 映射推导 `eligibleSlots`（手枪/手枪2 共享规则已有先例），偏离必须回写本文档 §4。
- **行数预算**：`audit-workbench-ui.js:865-871` 预算随切分同步调整，禁止为躲预算堆叠新文件。
- **验收术语**：本列车收口仅声称 picker 抽离 + merc 换装 `e2e_verified`；不动 runtime，无 promotion 语义。

## 11. 施工证据与实现偏离回写（2026-08-24 收口）

### 11.1 门禁证据

- **AS2 focused**（`scripts/run-merc-loadout-tests.ps1 -TimeoutSeconds 360`）：基线 **97/97**（runId `09aa6bb78b474770b6c38baddb534b8e`）→ fresh **113/113**（runId `daa0d899f191459cb4744a516a4f66a5`），Compiler **0/0**、32K retry **0**；新增 3 测试函数 16 断言覆盖 backpack scope 全量候选、`eligibleSlots` 逐点等于逐槽 policy 并集、空数组不兼容仍携带、非法 scope `invalid_scope`、旧 slot scope 形状回归、revision 不变量、50 件 × 10 槽性能冒烟（实测 228ms）。回归 `run-managed-longgun-tests.ps1` → **126/126**（runId `cbe554425ef644df9810453a54a52244`）。
- **抽离门禁**：cb 独立 harness **218/218 × 3 视口**、生产集成 harness **1095/1095 × 3 视口**（附带 12/12 + 18/18），三步每步复跑均绿，**cb harness 零断言改动**；equipment-tuning harness pass；7× test-character-build-* 全绿；`test-panel-runtime.js` **41/41**；lazy-closure **28/28**；canonical-presentation **6/6**；`audit-workbench-ui.js --strict-warnings` default 与 `--release-tree` 均 **0/0**；`check-workbench-css-bundle.js` ok（26 imports）。
- **merc 接入门禁**：team harness **207/207×3 → 218/218×3**（改写 9 组旧断言 + 新增 11 组 merc 换装专项：拖拽交付/替换、跨槽 drop-hint 与拒绝、双击、五态、scope 回滚、写后 picker 状态与 scrollTop 保持、快照不关 picker、损坏占位零协议、预览 overlay、错误重试、栅栏迟到不复活）；T800/pet 全族零回归；cb 两套 harness 复跑不回归；ratchet **67/67**。
- **Launcher 全量**：**4057 pass + 3 explicit opt-in skip / 4060 total**（基线 4054+3/4060，差值 3 条为 Audio v2 qualification 在 CF7_NODE_EXE 就绪环境下由历史失败转通过，与本列车无关）。
- **asLoader 发布**：`scripts/compile_test.ps1 -Target publish -VerifySwf scripts/asLoader.swf -TimeoutSeconds 300`，编译 226s exit 0，SWF **1,137,982 bytes**（基线 1,137,755）、SHA-256 `737A12808037BF2A926B255BC33467044F7BE98C8302B7F410CF333EC81BF36E`，解压定点命中 `eligibleSlots`/`invalid_scope`/`buildEligibleSlots`/`MercLoadoutService`；预编译 BOM 门 225/225；publish-only flashlog 未刷新属预期。
- **预存在红（非本列车）**：`tools/test-inventory-workbench-modules.js`（npcshop `createOwnerChannels` 源码断言 :1205）在干净基线即红，各阶段同点失败，按纪律原样保留未修。

### 11.2 实现偏离（按施工契约回写）

**§4 协议扩建**：① 非法 scope 处置选定 fail-closed 返回 `invalid_scope`；② 成功响应顶层新增 `scope` 回声键（增量键，向后兼容）；③ backpack scope 下 slot 参数可缺省（缺省/不可写时不携带单槽字段而非报错），Web 侧背包总览请求发 `slotKey:''`。

**§3 抽离**：④ 实际产物为 7 leaf（较 §3.1 草案多 `loadout-picker-action-view.js` 与 `loadout-picker-candidate-pane.js`）——§3.2 动词集注入与 §8③「禁止 fork 回私有副本」要求操作栏共享，pane 独立成 leaf 使组合根保持 206 行薄装配；⑤ `slotDescriptors` 未做函数端口，cb 侧维持 template 数组经 `_renderSlotGroup` 参数注入，留待第三消费者以真实需求扩展（§8①）；⑥ CSS 切分已执行，`css/workbench/loadout-picker.css` 323 行（slot 网格/候选 pane/五态/操作栏自 `character-build.css` 切出），WB043/WB135 审计同步重指；⑦ `candidate-pane` 隐式契约形式化为显式 ports：必需 `syncFocusSummary(host,key)`、`texts`（34 条）、`classPrefix`、`candidateTitleSelector`，硬编码三 roving 改为 `_slotRovings` 注册数组。

**§5 merc 接入**：⑧ 动作条动态动词（确认交付/确认替换按槽位托管态切换、取回仅 custody 可用）经 merc 组合根实例方法包裹实现，未给共享 ActionView 加新 port——第三消费者需要动态动词时可提为 port；⑨ corrupt 槽点击拦截在 merc 视图 click 层前置（旧行为「只解释零协议」，`_onSlotSelect` 内双保险）；⑩ 写后选中候选不保留（lease 随 revision 失效，同 cb refetch 语义），保留的是选中槽/scope/候选列表；⑪ `tools/lib/workbench-ui-ratchet.js` 焦点环例外由硬编码两选择器泛化为 `(file, selector)` 白名单表（覆盖 cb + merc），states.css/audit WB135/测试三处同步——属抽离期遗留红的同列车收口；⑫ 共享 loadout-picker 各 leaf 在 merc 接入期零改动，cb 私有文件零改动。

### 11.3 滚动痛点根治落点（merc-panel.js）

写成功后 `handleLoadoutWriteResponse` 只局部刷新装备区，不再整列重建/关闭候选栏；`renderDetailPage` 重建右栏前摘出同佣兵 picker 根（保 tooltip/拖拽/焦点绑定），重建后原样挂回 + `setMerc` 恢复选中槽/scope + scrollTop 还原；快照刷新不再有无条件关闭动作，`closeLoadoutBrowser` 与 `data-loadout-open` 死标记全删。

### 11.4 测试反馈后的契约修订（2026-08-24）

测试员确认了两个此前自动门未冻结的交互缺口：角色构筑从背包拖拽成功后会自动切入兼容态；兼容态只允许投递到浏览锚点，导致同类双槽（例如手枪/手枪2、药剂槽）无法直接跨槽。根因不是写权限不足，而是共享 drop-policy 在读取候选白名单前先按 scope 钉死落点，且 character-build 写回把实际 drop target 误当成新的浏览选择；同时 AS2/Host 只在 backpack scope 强制携带跨槽资格。

修订后的稳定合同如下：

- scope 只控制候选集合；锚点只控制 `compatible` 筛选和主 CTA 目标；候选的 drop target 由 AS2 权威白名单独立裁决。
- character-build 装备候选在 `compatible/backpack` 都携 `equipmentEligibility`，并由 Host 在两种 scope 下逐行验证；merc 候选在 slot/backpack 都由 AS2 携 `eligibleSlots`。Web 先消费对应白名单再考虑 legacy fallback，MercTask 传输/写闸门维持原边界。
- 合法药剂候选可投递到四个药剂槽；具体目标槽的冷却仍由 Host/AS2 写前最终裁决，不把 Web 高亮升级为写权限。
- drop 写 exact 落点，但成功、确定失败和对账都保留写前 scope + 锚点。fresh 背包总览保持无锚点；兼容槽 A 拖到槽 B 后仍浏览 A。只有玩家显式点槽或切 scope 才改变浏览上下文。
- merc 写回若推进 `loadoutRevision`，候选 authority 恰好重拉一次；随后同 revision 的快照只刷新投影，不重复制造 loading，也不得让连续操作沿用旧 revision。

本修订新增 character-build 背包/兼容装备与药剂跨槽、写后浏览上下文保持，以及 merc 兼容态跨槽高亮/取消零写/实际交付/连续 revision 的三视口回归。旧 §11.1 数字是首轮抽离收口的历史证据，不覆盖本修订；本轮 fresh 结果以 testing guide 与当前测试输出为准。

本轮自动证据：Character production **370/370×3**、standalone **218/218**、session **36/36**、projection **8/8**；Team **222/222×3**；Host CharacterBuild 定向 **228/228**、Launcher 全量 **4085 pass + 3 explicit opt-in skip / 4088 total**；Merc AS2 **113/113**，Character focused 六套合计 **580/580**（CharacterBuildService **194/194**），Compiler 均 **0/0**、32K retry **0**；合并本日其余体验修复后的 asLoader 最终 publish 刷新为 **1,139,471 bytes**。`run-character-build-tests.ps1` 的独立 writer 静态前置仍因本基线既有 DrugInputService/ItemUtil 文本合同失配而在进入 compile 前报红，本轮未越界改动；上述 Character 动态证据由该脚本定义的同一 focused template/suite 直接执行取得，不能表述为 wrapper 全绿。
