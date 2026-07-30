# 项目技术架构总览

**文档角色**：系统拓扑 canonical doc。  
**最后核对代码基线**：commit `9118eb5097ab073d26a9806138f9fabf28e3ca79`（2026-07-30）已由 immutable tag `runtime-build-v2/20260730-workbench-character-build-v1`、request `F5992FE5AFA3B74024CACEFCA1BACD311C1A3EE7C50CF3D08145A3E49BC211BC` 完成 v2 promotion；正式 runtime 绑定 identity `EB60E241929B5F88110C4EAE218DFD98569AE657F2B765179DBF644F0EEE0255`、closure `889FC7A800CFE738EAA99992CD6C5689AA65ECFEF3F406A617B3A1A344F4520B` 与 Core `9DE1C5249EA5827AB8CE7C19CAE0CAE8724809BE2BC7DE4F600AD2F7AB78F336`。标准入口 attempt `9539e5f3f6d44b7daf487d8985465972` 仅验证 production `EQUIPMENT_TUNING` opener → exact workbench instance → 同实例首个权威 snapshot → supported application shutdown；不外推为 Character、Materials、Intelligence、PlayerInfo、业务写、普通 panel close、人工视觉或持久化专项验收。

本项目当前应被理解为：**Flash 核心游戏 + Guardian Launcher Host + WebView2 UI + native / build tooling** 的本地多栈系统。

## 1. 总体分层

```
┌──────────────────────────────────────────────────────┐
│ Flash / AS2 Runtime                                 │
│ 主 SWF、子资源、帧脚本、org.flashNight.* 类库         │
└───────────────┬──────────────────────────────────────┘
                │ XMLSocket / HTTP / 本地文件 / 启动参数
┌───────────────▼──────────────────────────────────────┐
│ Guardian Launcher Host (C# / WinForms / net10.0-win) │
│ 启动链路、TaskRegistry、音频、overlay 宿主、存档决议   │
└───────────────┬──────────────────────────────────────┘
                │ WebView2 postMessage / bridge
┌───────────────▼──────────────────────────────────────┐
│ Launcher Web UI                                     │
│ bootstrap、overlay、Panels、minigames、dev harness   │
└───────────────┬──────────────────────────────────────┘
                │ build / native boundary
┌───────────────▼──────────────────────────────────────┐
│ Tooling & Native                                    │
│ TypeScript/V8、Rust sol_parser、PowerShell、CLI      │
└──────────────────────────────────────────────────────┘
```

## 2. 五条核心链路

### A. Flash / AS2 运行时链

- 游戏核心逻辑、帧脚本、资源链接和 `_root` 级业务入口仍在 `scripts/` 与 Flash 资产中
- 子资源与主 SWF 共享运行时上下文，不以现代沙箱或模块系统隔离
- `_root`、MovieClip、帧驱动 FSM、XML 数据加载仍是核心工程现实
- 这条链的验证与构建依赖 Flash / JSFL / IDE 协同，不属于可直接命令行编译的普通脚本项目
- **启动子系统（asLoader）**：承载 `org.flashNight.*` 类字节码 + boot 序列的 symbol，2026-06 已从 82 帧塌成**单帧 + `BootSequencer` 状态机**（反直觉，架构导览 + 待测见 [../docs/asLoader-README.md](../docs/asLoader-README.md)）
- **玩家手动输入与 Skill 权威**：`通信_fs_帧计时器.as` 每帧把武器技能、12 槽快捷技能与 4 槽药剂交给 `WeaponSkillInputService` / `QuickSkillInputService` / `DrugInputService`；`ManualCooldownService` 独占 `weapon:shared + quick:1..12 + drug:0..3` 共 17 条逻辑冷却并继续使用 CooldownWheel 调度，保持暂停期间推进与跨场景存活。快捷槽描述符与 equip/unequip/reorder 由 `SkillLoadoutService` 权威维护，`QuickSkillInputService` 不再依赖玩家信息 HUD MovieClip 取槽；学习、升级、纯被动与快照投影由 `SkillPanelService` 裁决，并通过独立 `skills` domain 连接 Web。玩家信息 XFL 的控制器只显示键位、`Symbol 1791` 只投影动画，二者缺失或时间轴重绑都不能成为输入或装备门控。旧第 5 药剂格仍是装饰残留，不进入权威容量；药剂管理继续属于独立物品/药剂主线。

### B. Flash CS6 编译与自动化 smoke 链

- 真实编译器仍是 Flash CS6 GUI
- 自动化 smoke 通过 `scripts/compile_test.ps1/.sh` → JSFL → `testMovie()` → `flashlog.txt` / `compile_output.txt` / `compiler_errors.txt`
- 这条链只提供 **smoke 级验证**，不能取代 IDE 人工复核，也不能把 `publish_done.marker` 当作最终成功依据
- 详细编译自动化细节由 `scripts/FlashCS6自动化编译.md` 负责

### C. Guardian Launcher Host 链

- `launcher/` 是当前运行时宿主，不再只是“附带工具”
- 关键职责：
  - 启动前 WebView2 预检与 BootstrapPanel
  - Flash Player SA 启动、预热、嵌入与 reveal
  - XMLSocket / HTTP 本地总线与 `TaskRegistry`
  - 音频系统、Notch / Toast / Web overlay 宿主
  - Native HUD 组合：`NativeHudOverlay` 是右侧条件槽的唯一 owner，按 `transactionDecision > actionableNotice > contextHint > hidden` 计算一次并把同一 `RightContextSlotOwner` 投影给 RightContext 与 SafeExit；透明 `CompositeBounds` 只负责合成范围，不拥有命中
  - 启动前存档决议与 Protocol 2
- 当前存档 authority 边界：
  - Launcher 拥有启动期 SOL / shadow 快照选择权、文件保管、修复与外部编辑入口；这不是运行期领域事务权威
  - 运行期玩家状态仍由 AS2 `_root.*` 业务对象裁决并组装 `mydata`，写入 SOL 后再把整份 shadow 推给 Launcher；`ArchiveTask` 当前没有领域 revision、CAS、幂等命令账本或多聚合事务
  - valid legacy SOL 在 Resolver 命中 `Snapshot(source=sol)` 时，会被同步 seed 到当前运行根的 `saves/{slot}.json`
  - Bootstrap `list/load/load_raw` 只对标准 10 槽做 legacy 预热；自定义 legacy 槽不自动继承
  - `resources/` 与 `CrazyFlashNight/` 是两套物理隔离运行根；启动快照决议、shadow 文件、legacy SOL 搜索和删除都不跨根
- `launcher/README.md` 是该子系统的 source of truth

### D. Launcher Web / Minigames / Overlay 链

- WebView2 前端已承担启动引导、运行态 overlay、Panel 系统和小游戏 UI
- 运行态 Overlay 由 `GameUiBehavior` 统一抑制文档浏览器式文本选取、原生拖影与菜单；输入/可编辑/显式 opt-in 区域保留浏览器原生编辑语义，避免各 panel 分叉实现。
- 小游戏当前采用统一壳层与宿主协议：
  - 共享结构类：`minigame-*`
  - 共享宿主上报：`minigame_session`
  - 浏览器 harness + Node QA + 静态验证三层回归
- 这条链与 AS2 游戏核心并存，但职责不同：它是运行态 UI 层，不是替代游戏主逻辑的重写

### E. Native & Build 链

- `launcher/scripts/` 中的 TypeScript 编译为 V8 运行时代码
- `launcher/native/sol_parser/` 通过 Rust 生成 `sol_parser.dll`
- Windows runtime 发布已分成正交控制面：prepare 只派生 tracked 资产；policy 只读审计并签发绑定 Git tree 的 receipt；纯 producer 只消费 artifact source + producer recipe + toolchain lock，在隔离输出中生成 payload/manifest，不让政策变化进入 build identity
- release train 把最终 Git tree + policy hash 冻结为无自由命令字段的 request/Git bundle；bundle 内构建源码仍会执行，因此共享 queue 是 ACL 收紧的信任边界。本地 worker 清除外部 Git index/worktree/object 上下文，用 lease/heartbeat/mutex 在 MAX_PATH 预算内的短隔离 clone 构建，失败诊断受限归档，candidate 按 build identity + payload closure 进入 CAS。payload closure 排除 manifest，避免元数据变化伪装成二进制失衡
- v2 生产证明有两个信任根：注册本地机器以 CurrentUser 不可导出 X509 key 签名；GitHub hosted Windows 以固定 repo/workflow/source-ref 的 OIDC/Sigstore keyless provenance 证明。promotion 同时要求不同 signer identity 与不同 faultDomain，推荐 local + GitHub 双域
- promotion 是正式部署唯一写入口：验证 immutable request、production receipt、候选字节与 quorum 后事务替换 bootstrap/runtime/consensus，失败回滚；CI 对所有分支先验 byte closure，开发分支部署不变时允许 `source-ahead`。一次性 hash-bound `migration-bootstrap` 已完成 cloud workflow/公钥 registry 引导，当前正式部署为 v2；保护分支只接受完整 v2 strict 状态并永久禁止降级 v1
- 身份 schema、队列/CAS、enrollment、cloud proof、promotion 与 CI 状态机见 [runtime-build-reproducibility.md](../docs/runtime-build-reproducibility.md)
- PowerShell 承担 Windows 环境下的启动、编译 smoke、CLI 和诊断自动化
- 这里的 Node / Rust 都属于**受控边界件**，不是独立应用栈；它们存在的理由是为现有运行时服务

## 3. 通信与边界

### Flash ↔ Launcher

- 主通道：XMLSocket（快车道前缀 + JSON 路由）
- 辅助通道：HTTP（端口发现、状态查询、日志与辅助接口）
- 注册中心：`launcher/src/Bus/TaskRegistry.cs`
- 集成测试入口：`--bus-only`
- 鼠标手型迁移边界：AS2 `_root.鼠标` 是纯脚本兼容代理，只保留状态接口与物品拖拽容器；几何命中统一走 `_root._xmouse/_ymouse` 点命中和 `interactionMouseDown` / `interactionMouseUp` 事件，不再把 `_root.鼠标` 作为 `hitTest` 目标；`cursor_control` 只传低频状态。真实 cursor 视觉坐标由 Launcher 低级鼠标 hook / 坐标泵采样，视觉只由 C# `CursorOverlayForm` 原生 layered window 接管并按 monitor DPI 缩放；Web DOM 只通过 `cursorFeedback` 回传 hover/press 状态变化，不承担 cursor 视觉 fallback；AS2 仅在物品拖拽期间同步图标容器位置，不恢复旧鼠标视觉。

### Save Snapshot / File-Custody Boundary

- Launcher 的 shadow 文件保管与启动快照候选固定落在 `<projectRoot>/saves/`；哪个根启动 launcher，就只读取和维护哪个根的文件
- legacy SOL 定位只在当前运行根对应的 SharedObject 子树内进行，探测顺序为 `.swf` → `.exe` → 当前根 root-scoped fallback
- `reset` / `rebuild` / legacy SOL 删除都只影响当前运行根，不承担跨根合并或恢复职责

### Launcher Host ↔ WebView2

- Bootstrap 阶段：`chrome.webview.postMessage({cmd, ...})`
- 运行态：Bridge / Panel / UiData / Notch / overlay 消息桥
- 整备 rollout 与 opener 边界：`PreparationNavigationV1` 是只切 presentation 的临时总 gate，代码默认与随仓配置现均为 `true`；显式 `false`（或配置项存在但值非法）会原子恢复旧 Native/legacy HUD、Build `storage | stats | skills | help | close` 与 `returnFocusAction:"skills"`。on 时两套 HUD 使用“游戏 / 整备”分组，Build 只显示 `preparation-menu | stats | help | close`；Host 只给 Build 注入严格布尔 `preparationNavigationV1:true`，并让 Skills return 与 Skills/Materials/Intelligence rollback 聚焦 `preparation-menu`，Web 只接受严格 optional bool 与固定六项映射。该 gate 不参与 route authorization：B2 的 `EQUIPMENT_TUNING` 继续只接受 exact `workbench / battlebox / tuning / nativehud_equipment_tuning` Host → AS2 → Host nonce admission；B3 的 `build | storage | tuning` 仍是同 instance 有界局部导航；B4 intent 仍只持固定目标、exact instance、phase/generation/lifecycle epoch/timer；B5 Materials 仍走 Host opaque `openRequestId` 与 AS2 exact echo；B6 Intelligence 仍只消费 Host 内建 `{mode:"prod",source:"runtime",debug:false}` 的同步 exact admission、零 AS2 nonce/target timer。B1–B7 实现字节已随 `9118eb5097…` 冻结源码及配对正式 runtime 部署，但本次 `standard_entry_verified` 只覆盖 Equipment Tuning production opener 与同实例首个权威 snapshot；没有执行 Character/B7/Materials/Intelligence 业务旅程、业务 preview/commit、普通 panel close、人工视觉或持久化验证。
- Panel domain 路由：通用 `close` 始终最优先；其余携 `domain` 的请求先做领域分流。`domain=inventory` 独占 `InventoryTask → inventory_response → panel_resp(domain/cmd/callId)`，覆盖 range snapshot、move/merge/swap/discard、autoTransfer 与 `sortAndMerge`，并以容器写版本维护跨只读请求稳定的 OCC slot lease；`domain=npcshop` 只拥有目录、价格、材料/情报与交易计划，不再嵌套背包 snapshot；`domain=crafting` 由 `CraftingTask → crafting_response` 独占，Web preview 只传分类/配方索引/`craftCount`，commit 只传一次性 token，Flash 重算最终写入；`domain=hairdresser` 由 `HairdresserTask → hairdresser_response` 独占，只允许 snapshot 与 commit，77 行权威目录保持源顺序和重复项，Web 只做脸型/发型本地预览，AS2 重新校验免费目录后写 root/live actor 并置 dirty mark；未知写只由后发 fresh snapshot 判定 applied / not-applied，绝不重放；`world_hairdresser` NPC 已冻结为 Web-only，命令缺失或发送失败 fail-closed，不保留 legacy Flash renderer/fallback；`domain=skills` 由 `SkillTask → skill_response` 独占，严格使用带 `panelInstanceId` 的七键 envelope，active/candidate/return 实例门、write epoch 与 reconcile watermark 隔离迟到响应，关闭时由 Host 把 scoped cleanup 收敛为 `skillPanelClose`。Skill 的 `switch_manage/switch_trainer` 是独立 panel-control：只接受当前相应 view 实例和嵌套 `{v,focusSkillKey}`；trainer session 在往返 manage 期间只存 Host，manage Web 仅见 `canReturnTrainer`，不进入 AS2 业务路由。金币商店由 Web 组合 inventory 背包与 NPC collections；合成面板切入 workbench 时只共享 UI 意图，不共享 token 或写 authority；Host `HairdresserTask` 组合既有 `PanelPendingCallTracker`，Web `HairdresserRuntime` 组合现役 `PanelRuntime.PanelRequestMux`，不新建 pending/timer/mux、价格/token 或通用外观状态机；技能展示可复用共享密度、树导航/面包屑、pointer drag 和 AS2 HTML 白名单注释 primitive，但技能浏览、教师学习、快捷槽和被动开关不进入 inventory/equipment domain。这五个专属域都不得回落 legacy 全局 cmd/MapTask catch-all。无 domain 请求继续走既有 panel/cmd 路由。
- Minigame：统一 `minigame_session` envelope
- WebView2 浏览器策略：`WebView2BrowserPolicy` 由 BootstrapPanel 与运行态 WebOverlayForm 在 `EnsureCoreWebView2Async` 后、首次导航前共同消费。生产默认关闭用户 zoom/pinch、browser accelerator、DevTools 与默认右键；只有显式、默认 false 的 `webView2DeveloperMode` / `CF7_WEBVIEW2_DEV_MODE` 恢复未被 Host 热键合同保留的 accelerator、DevTools 与默认右键，Host 的 DPI/PanelScale `ZoomFactor` 写入不受影响。`KeyboardHook` / `HotkeyGuard` 仍保留 `Ctrl+W/R/P/O/F/Q`，因此开发态浏览器 reload 正例是 `F5`，`Ctrl+R` 继续走 Host 合同。该诊断能力不从 Git dev repository、热重载或其他隐式模式推导。
- 性能诊断边界：运行态 Web overlay 可分别启用 `webOverlayDisableCssAnimations`、`webOverlayDisableVisualizers` 做 A/B；`webOverlayLowEffects` 是聚合保护开关，并额外降低 map panel 的全屏 scanline / radar / pulse、CSS filter/drop-shadow 与覆膜合成成本。`webView2DisableGpu` 同时作用于 BootstrapPanel 与运行态 WebOverlayForm，用于定位 WebView2 GPU 合成责任面，不作为默认运行方案。`nativeCursorOverlay=false` 只关闭 C# cursor layered window，恢复系统鼠标，用于隔离 cursor 迁移与 WebView2 overlay 满载。双显卡调度通过 `tools/set-launcher-gpu-preference.ps1` 管理 Windows 每应用高性能 GPU 偏好；运行态采样用 `tools/sample-launcher-gpu.ps1` 按 launcher / flash / bootstrap / web_overlay 分组读取 GPU engine；静态复杂度审计用 `tools/audit-web-overlay-complexity.js` 统计 overlay CSS / JS 中的合成与布局风险点。GPU 偏好只能影响系统调度意愿，不能保证无 MUX 笔记本的最终桌面合成绕过核显。
- WebView2 user-data 边界：BootstrapPanel 与运行态 WebOverlayForm 使用不同 user-data 目录，避免诊断参数改变 WebView2 browser process group 后互相破坏初始化。BootstrapPanel 在 reveal 后隐藏时请求 WebView2 suspend，避免启动页在游戏态继续占 GPU。

### 文档边界

- 本文只讲系统拓扑与链路分层
- 协议明细、构建细节、测试矩阵、治理规则分别由：
  - `launcher/README.md`
  - `agentsDoc/testing-guide.md`
  - `agentsDoc/documentation-governance.md`
  - `docs/tech-stack-rationalization.md`

## 4. 当前架构结论

- 当前工程是一个必须接受 Flash 物理约束、同时由多条宿主与工具链围绕的本地多栈系统
- 入口文档应只陈述这一现实；技术栈演进判断统一下沉到 `docs/tech-stack-rationalization.md`

后续治理重点应放在：

- 文档 truth source 明确化
- 子栈边界收敛
- 验证矩阵标准化
- 入口页与深文档职责分离
