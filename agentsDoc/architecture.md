# 项目技术架构总览

> **字体 Gate E（2026-08-21）**：根 `fonts/fonts.xml` 是 C#/Web runtime authority，表达 14 asset、28 个语义 role、9 个 `accepted` preset 与 `permanent/on-demand` residency。`fontctl generate` 产出 XML-hash 绑定的 `launcher/web/generated/font-catalog.{json,css,js}` 和 FontPack 兼容 manifest。
> `RuntimeFontCatalog` 在 WebView2/Native HUD 构造前加载投影，按 face-major（每个 face 内 `temporary/custom → temporary/cache → permanent/runtime`）解析；成功项按 asset 复用同一已验证 byte snapshot，并通过 exact-set `WebResourceRequested` + 内容 ETag 提供字体，未命中不缓存。Web CSS/Canvas/动态 SVG/Tooltip 与 Native HUD/Combo/HitNumber/mono/symbol 均走 role。
> JetBrains Mono 和 Source Han Serif CN Regular 为常驻，其余按需；旧 `%LOCALAPPDATA%/CF7FlashNight/fonts/` 可能仍有惰性文件，但导入和 Web 字体副本已退役，运行时、CLI 与 harness 均忽略。打包层收 permanent、排除 temporary，并显式收入三项 generated Web 投影。Flash/AS2/FLA/XFL 和 legacy 作者字体不在该图内。机器 Gate 与维护者人工观感已通过；正式部署状态以 runtime consensus 和标准入口证据为准。
> FontPack 与 fontctl 对 requested URL 和每跳 redirect 重复执行默认 HTTPS 端口与 exact host 校验；当前仅允许
> `github.com`、`release-assets.githubusercontent.com`、`raw.githubusercontent.com`、`cdn.jsdelivr.net`，
> 不允许通配 `githubusercontent.com` 子域。

**文档角色**：系统拓扑 canonical doc。  
**最后核对代码基线**：commit `416c4441947d40bc27ae3854178e87e2c5cf1ac9`（2026-08-23，战宠生命周期、事务与跨栈面板加固 release source；deployment `df060eac491c7251b261a3f5626960a8ea18911a`）。

当前正式 runtime 的身份、发布状态和专项验收只读 [runtime release consensus](../config/build/runtime-release-consensus.json)、[runtime manifest](../runtime/cf7-runtime-manifest.tsv)、[runtime build reproducibility](../docs/runtime-build-reproducibility.md)与[测试矩阵](testing-guide.md)。本架构文档不复制发布收据或历史测试数字；Audio H2 继续作为独立专项，不由通用 promotion 代签。

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
│ 启动链路、TaskRegistry、Agent Runtime/Wings、UI 宿主   │
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

外部 developer adapters / trusted Core unattended runner
                │ CF7A v1 当前用户本地命名管道
                ▼
┌──────────────────────────────────────────────────────┐
│ Guardian Launcher Host                               │
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
  - Audio Platform v2 的 `AudioCoordinator` 单 owner、资格化/ready barrier、Notch / Toast / Web overlay 宿主
  - standard normal 的 CF7 Agent Runtime/Wings composition；显式 legacy HTTP 与 `--bus-only` 不创建该控制面
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
- `warlord` 军阀战术演习已作为 `1024×576` Three ESM 测试 Panel 接入 lazy registry、全锚 Web 布局、Host 生命周期与 exact close；当前 `productionWrites=false`。Phase C 源码候选采用 `Web 冻结 exact 战略请求 → WarlordBattleTask 复验 → 精确关闭并释放 pause → ArenaCalibrationTask/AS2 专用场景 → 绑定 digest 的 receipt → 重开同一战略态并单次应用`。八张卡的 `cardId` 即正式战宠 `petId`，产品身份由 `petId + Identifier` 联合裁决；等级与合法体质升阶前缀投影到隔离宠物属性副本，不读取或写入玩家战宠。`warlord.pet-economy-observation.v1` 只分开记录宠物目录基础价与战旗战略造价，不结算玩家金币/K 点。确定未投递返回 `not_started` 并允许重试；可能已投递的异常进入 `unknown` 并冻结。JS resolver 只留显式 fixture，产品 AS2 不可用时 fail closed。AS2 终态恢复是 Host 内部能力，不加入 AS2/Web 可达的通用 panel allowlist：`WarlordBattleTask` 只能调用 `LauncherCommandRouter.TryOpenWarlordResumePanel`，由后者复验只读权威、digest、session/request、冻结 state/command 和 client context，再经统一 `PanelHost` 打开；`RequestOpenPanel("warlord", ...)` 必须保持 unsupported。首次真实候选旅程已完成 AS2 战斗并取得无错误战果，但旧恢复实现误走通用路由而无法回到战旗，因此 E2E 已重新打开；修复源码门通过，仍待替代候选的人类复验，不得写成业务已验收或已部署。
- 这条链与 AS2 游戏核心并存，但职责不同：它是运行态 UI 层，不是替代游戏主逻辑的重写

### E. Native & Build 链

- `launcher/scripts/` 中的 TypeScript 编译为 V8 运行时代码
- `launcher/native/sol_parser/` 通过 Rust 生成 `sol_parser.dll`
- `launcher/native/` 的 Audio Platform v2 以多个 C/C++ TU 构建，并把静态 libvorbis/libopus 与 bridge 链接成单一 `miniaudio.dll`；构建输入与 decoder 依赖由 tracked manifest/lock 固定
- Windows runtime 发布已分成正交控制面：prepare 只派生 tracked 资产；policy 只读审计并签发绑定 Git tree 的 receipt；纯 producer 只消费 artifact source + producer recipe + toolchain lock，在隔离输出中生成 payload/manifest，不让政策变化进入 build identity
- release train 把最终 Git tree + policy hash 冻结为无自由命令字段的 request/Git bundle；bundle 内构建源码仍会执行，因此共享 queue 是 ACL 收紧的信任边界。本地 worker 清除外部 Git index/worktree/object 上下文，用 lease/heartbeat/mutex 在 MAX_PATH 预算内的短隔离 clone 构建，失败诊断受限归档，candidate 按 build identity + payload closure 进入 CAS。payload closure 排除 manifest，避免元数据变化伪装成二进制失衡
- v2 生产证明有两个信任根：注册本地机器以 CurrentUser 不可导出 X509 key 签名；GitHub hosted Windows 以固定 repo/workflow/source-ref 的 OIDC/Sigstore keyless provenance 证明。promotion 同时要求不同 signer identity 与不同 faultDomain，推荐 local + GitHub 双域
- promotion 是正式部署唯一写入口：验证 immutable request、production receipt、候选字节与 quorum 后事务替换 bootstrap/runtime/consensus，失败回滚；CI 对所有分支先验 byte closure，开发分支部署不变时允许 `source-ahead`。一次性 hash-bound `migration-bootstrap` 已完成 cloud workflow/公钥 registry 引导，当前正式部署为 v2；保护分支只接受完整 v2 strict 状态并永久禁止降级 v1
- 身份 schema、队列/CAS、enrollment、cloud proof、promotion 与 CI 状态机见 [runtime-build-reproducibility.md](../docs/runtime-build-reproducibility.md)
- PowerShell 承担 Windows 环境下的启动、编译 smoke、CLI 和诊断自动化
- 这里的 Node / Rust 都属于**受控边界件**，不是独立应用栈；它们存在的理由是为现有运行时服务

## 3. 通信与边界

### Flash ↔ Launcher

- 主通道：XMLSocket（快车道前缀 + JSON 路由）。standard normal 在 accepted loopback tuple 上解析 owner，并只接受 GameLaunchFlow 当前 exact Flash PID/start-time/path；校验先于旧连接替换、generation/ready 与 dispatch。显式 legacy/`--bus-only` 才使用 loopback compatibility authority。
- 辅助通道：HTTP。standard normal 只保留 Flash 窄 probe/log/crossdomain，privileged legacy 路由为 `DenyAll`；只有显式 `--legacy-http-automation` / `--bus-only` 签发进程生命周期 credential，同时不创建 Agent Runtime/rendezvous/Wings。
- 注册中心：`launcher/src/Bus/TaskRegistry.cs`
- loot feed（左下玩家物资双向流动/击杀播报）：AS2 领域服务在真实资产与领域状态提交后，将 gain/loss 写入 `PlayerAssetTransaction` detached receipt；独立 UI/关卡/素材 XFL 没有稳定类路径，只允许调用 asLoader 注入的六个 `_root` 玩家物资门面，不直接链接 `PlayerAssetTransaction/ItemUtil`。根时间轴只做 authority item key → tier/display/icon 投影，经 `{"task":"loot","payload":{v:1,direction,kind,itemKey,name,count,source,operationId,...}}` fire-and-forget 到严格 `LootFeedTask` → NativeHud `LootFeedWidget`。事务基座不是 mutation engine：预检、写入、dirty、领域回滚仍归各服务，消费者异常不得反向回滚资产；位置移动、经验/SP 与状态池明确不算所有权变化。完整边界、source 与渠道矩阵见[玩家物资事务与双向播报 ADR](../docs/玩家物资事务与双向播报-ADR-2026-08-22.md)。地图战利品箱 `loot_response` 仍是另一域；native 单渲染端，无 Web fallback。击杀继续由 `enemyKilled`/killStats 同链经旧 façade 发 neutral legacy event，`eliteLevel` 仍只承载 `UnitUtil.getEliteLevel` 的 `0/1/2`。
- loot feed 调度/渲染：Host v1 要求显式 direction/source/itemKey/operationId 与 safe 正整数，以 operation/effect 身份 exact 去重并拒绝冲突 replay。`LootFeedModel` 是五个稳定可见槽 + recoverable pending queue；视觉合并键含 `direction/kind/itemKey/tier/派生调度策略/eliteLevel` 并要求展示名/图标一致，`operationId/reason/mergeScope/raw source` 保留在 Host 幂等与审计层、不进入卡片模型；跨 raw source 只有在 retention/urgency/priority/hold 完全一致且都非 `unknown` 时才合并。任务/通关/箱/Boss 保真，精英/拾取 exact-aggregate，普通击杀只压身份溢出，`reload` 为 immediate exact-aggregate。`LootFeedWidget` 使用 26px 直角卡与 96–220px/8px 内容宽度；gain 一件省略 `×1`，loss 一件仍以珊瑚红 `−1` 明示。pending 不计时，高级替换复用 victim slot；事件 burst 单飞 drain，计数视觉 8Hz、方向感知几何桶、签名 32ms 采样并受 overlay 33ms 上限约束，静态 hold 零 repaint。
- loot 图标缓存与纸娃娃回包：`LootIconCatalog` 以有界 `BitmapLruCache` 作为 64px 位图唯一所有者，帧集只在一次查询/绘制周期内组合，不能跨淘汰保留位图引用；整组动画超过预算时回退静态首帧。纸娃娃缺图由 Host 发 `{type:"dollBake",key,requestId,tuple}`，Web 通过 allowlisted `doll_bake_result` 回 `{key,requestId,pngBase64|error}`；Host 仅接受当前 key 的 exact 在飞 requestId，并在 completing 状态保持同键单飞，foreign/duplicate/timeout 后迟到回包不能写盘或清除新请求。Web 快照显式使用 `pixelRatio:1`、`animate:false`，因此 API 的 256 尺寸不受 WebView DPI 放大；只有完整解码且 exact 256×256 的 PNG 才可原子落到 `launcher/data/doll-portraits/<hex>.png`，拒绝时记录 key/requestId/reason。历史缓存首次复用也须通过同一验证，旧尺寸/损坏文件进入重烘焙且读取端拒绝消费，成功后 `PortraitReady` 驱动占位卡重探。常驻 UI 路线只保留 NativeHud（legacy Web 常驻 HUD 与 GDI+ 伴随层已拆除），loot feed 无 fallback。
- 集成测试入口：`--bus-only`
- 鼠标手型迁移边界：AS2 `_root.鼠标` 是纯脚本兼容代理，只保留状态接口与物品拖拽容器；几何命中统一走 `_root._xmouse/_ymouse` 点命中和 `interactionMouseDown` / `interactionMouseUp` 事件，不再把 `_root.鼠标` 作为 `hitTest` 目标；`cursor_control` 只传低频状态。真实 cursor 视觉坐标由 Launcher 低级鼠标 hook / 坐标泵采样，视觉只由 C# `CursorOverlayForm` 原生 layered window 接管并按 monitor DPI 缩放；Web DOM 只通过 `cursorFeedback` 回传 hover/press 状态变化，不承担 cursor 视觉 fallback；AS2 仅在物品拖拽期间同步图标容器位置，不恢复旧鼠标视觉。
- **规划态入口（尚未实现）**：单位/子弹 `WorldFrame`、CSharp native world overlay、四帧 `SenseFrame`、逐碰撞帧 `ThreatFrame` 与固定 `n→n+1` 普通 AABB 碰撞迁移，统一见 [单位数据镜像、CSharp 原生绘制与碰撞判定 · 长期迁移路线 ADR](../docs/单位数据镜像-CSharp原生绘制与碰撞判定-长期迁移路线-ADR-2026-08-09.md)。该路线状态为 `PROPOSED / ROUTE_FROZEN / NOT_IMPLEMENTED / P0_EVIDENCE_PENDING`；`ROUTE_FROZEN` 只表示提案冻结供评审，尚非 `ROUTE_ACCEPTED / P0_AUTHORIZED`。最后核对相关源码 commit `fff104b0f29d7c5def80f2ba0b5cc2682124f500`。当前不存在该 ADR 所述 raw lane、worker、World Overlay 或 gameplay authority，现役通信事实仍以上述 XMLSocket/TaskRegistry 说明为准。

### Audio Platform v2 current source

- **authority / ABI**：`AudioEngine` 只是进程级兼容 facade；所有 native mutation 经 `AudioCoordinator` 单 owner 队列串行化，raw P/Invoke 只存在于 `AudioNativeV2` adapter。`audio_bridge_v2.h` 暴露 versioned fixed-width ABI、capability snapshot 与 runtime snapshot，不跨边界泄漏 C/miniaudio 平台类型。
- **backend / codec / failure**：production backend 固定为 `WASAPI → DirectSound → WinMM`，禁止 Null；三者均失败时发布 `audio_unavailable` 并进入 no-output 降级，**不把 Launcher/游戏进程判 fatal**。engine 建立后 BGM/SFX group 必须分别显式 `started`，任一 start 失败都使初始化失败。native runtime contract 必须播放非静音 fixture，并同时观察 `started`、`playing=true`、推进的 cursor 与非零 peak/RMS meter，专门拒绝“source playing 但 group 未启动”的静音图；内部图信号仍不能代签 endpoint 可听。decoder 能力为 miniaudio built-in WAV/MP3/FLAC、静态 libvorbis/libopus，以及 Windows Media Foundation AAC/M4A/MP4/ADTS；WMA deferred，不在当前能力声明内。多个 C/C++ TU 与静态 codec 最终只产出一个 `miniaudio.dll`，没有松散 codec side-car。
- **qualification / ready**：`.wav/.mp3/.flac/.ogg/.m4a/.mp4/.aac/.adts/.opus` 仅作 discovery hint；`MusicCatalog` 必须执行 container/codec content sniff、extension mismatch 检查、production 间隔 1000ms 的两次 size+mtime 稳定观测与 bounded runtime probe。catalog 只投影 exact availability/reason；native/SFX 初始化后仍须等待 catalog qualification，再向同一连接发送 full catalog，最后才允许 `audio_ready`。A5 shipped-audio source inventory 为 `827 = 795 tracked + 32 ignored_source`，manifest `843455` B / SHA-256 `60CA5E3E6B42842965FBD5A2A8313827D0C2E7AB0CAE4E16D9E8E3B0986B6A9C`；其中 11 个 content-sniff 为 AAC 的资产已由 `.wav` 重命名为 `.m4a`。qualification dependency 为 `568` entries / closure `78F24B46977C3D370FFAA41D657B184B8617D21C9DAB02EE115F6B90724A9764` / manifest `142054` B / SHA-256 `F38A7E83AFF8070D7B82E97BF905471C8CBF4D3C56C858199E8CDA25CCD5ACF1`；这些不等于已部署或物理可听。
- **wire / recovery**：BGM 与生命周期使用 strict `wireRevision=2`，分别绑定 lowercase UUID `audioSessionId`、uint64 decimal `audioReadyGeneration` 与 `deviceGeneration`；transport `connectionGeneration` 不进 wire。WASAPI default-device/inactive-default callback 只发原子 rerouted signal，禁止 callback/audio write thread stop/reinit/start；native/managed owner 执行 single-flight recovery。首次 Initialize 的 `device_unavailable|device_lost` 计 attempt 1，attempt 2–5 沿用同一 ready epoch；default-device notification、普通 BGM `device_lost` 与 hot catalog refresh 进入 active episode，recovery replay `not_ready` 沿用已消耗预算。最多 5 次 initialize，按 `200/400/800/1600 ms` 退避；qualification completion 总先 strict inspect，query exception/null-invalid ABI/tuple drift/其他 non-ready terminal，只有 exact valid tuple 的 `Recovering` 或 `Ready + deviceGeneration drift` 继续。replay 在 `Recovering` 内执行，成功后才唯一发布 `Ready` 并恢复 latest successfully committed BGM intent；失败无 transient Ready。SFX pre-ready/recovery/stale 全部 drop + counter，禁止排队、补播或 replay。A6 `sleep_resume` 允许同一 case 内出现多个顺序 recovery episode，但零 episode 不通过；recovery marker 是 endpoint transition boundary，首个 `Recovering` 可已暴露新 endpoint digest。每个 episode 必须保持同 session、`audioReadyGeneration` 相对当前 `Ready` baseline 精确 `+1`，episode 内 `deviceGeneration` 不回退；retry 可迁移 endpoint，closing `Ready` 的 physical tuple 必须等于最后一个 `Recovering`、`deviceGeneration` 相对该 baseline 前进，并成为下一 episode baseline。journal 的 hash-bound `workingStateElapsed100ns` 由 `api-ms-win-core-realtime-l1-1-1.dll!QueryUnbiasedInterruptTimePrecise` 以 Host origin 生成，100ns 单位、允许相等、禁止回退、排除 sleep/hibernate 且无 fallback；`monotonicTicks` 仍严格排序。仅对 `sleep_resume` 的恢复时长，UTC 只作审计且允许墙钟回拨；seek、crossfade 与格式 case 既有的 UTC window 语义保持不变。R4 的具体 15 秒目标、30 秒硬上限与最终同 generation 双 snapshot PCM 规则见下节。
- **qualification-only surfaces**：A6 只在 exact `isolated_candidate` Core 显式携带 32 位 lowercase-hex runId 时建立两条 CurrentUserOnly named pipe；formal/standard/unattended/legacy 入口携带该 flag 必须 fail-closed，无 flag 不创建。observer 的 OS pipe name 不变；qualification request/response、candidate-journal carrier 与 live-observation schema 为 v2，stimulus protocol/response 保持 v1。observer 只以顺序 marker 划定 14 case、在 coordinator owner 队列取只读 snapshot 并返回 hash-chained journal；separate stimulus pipe 对每条命令在同一 ready generation 内串行执行幂等 rearm，再把 strict grammar 命令投递到生产 `AS2 → XMLSocket → AudioTask → AudioCoordinator/native` 链，generation 漂移即 fail-closed。`sent=true` 仍仅为 socket delivery proof，不是 AS2 ingress、native started 或可听证明。有限 SFX 两 case 要求最后 pre-dispatch SFX `peakAbs <64`、至少一份 post-anchor snapshot 同时 frame 推进且 `peakAbs >=64`、final 总 frame 推进，允许 terminal silence。stale case 另以 hash-bound `recovery_sfx_armed{result:armed,sent:false}` 锁定 `arm < first Recovering < old-generation batch < first Ready after that Recovering < post`，只允许 `staleGenerationDrops` 按 batch 增加，其余 counter 与 played 不变。前 10 case 可由 operator 自动编排；`dense_overlap_throttle` 必须把同一个 full-filename ID 在单个 S2 batch 中重复 6 次，静态绑定 per-entry voice cap `4`，并要求 `1 <= played <= 4`、`throttled >= 1`、`played + throttled = 6` 且其他 outcome counter 零增长；6 个 unique ID 不覆盖该 per-entry 语义。Opus 后在 case 外 mute BGM、dense overlap 后 restore，后 4 个设备/路由/睡眠/recovery case 与 10 项听感必须由人类完成。
- **capture / evidence boundary**：loopback capture 必须先由 capture process 在 `IAudioClient.Start` 后写 `ReadySignalPath`，再允许 stimulus；runtime tuple/`f32` 与 endpoint WAV `pcm_s16le` 分别绑定。observer/stimulus pipe 使用无空白 compact canonical UTF-8 JSON；capture configuration 是递归 key-sort、two-space indent、terminal LF、UTF-8 no-BOM 的 tracked artifact，operator 必须用独立 comparator 校验，禁止拿 pipe wire canonical bytes 代验 artifact。`prepare` 只接受全新 runId，先独占创建 run root 与空 `captures/`；run root 已存在（无论 captures 缺失、为空或非空）一律 fail-closed 且不得触碰旧 run。toolchain writer 用 pinned runtime environment gate 生成 canonical Node/MSVC/.NET/PowerShell/cmd/vcvars 描述，隔离 runner 只接收 hash-bound absolute `CF7_NODE_EXE`，不继承 PATH；materializer 的 SFX `linkageId` 必须与 production catalog 一样使用包含 `.wav` 的 full basename，逐项重读并核对 source bytes/hash，再按 MPEG Layer III frame 严格解析到物理 EOF，锁定 version/sample rate/frame/sample/duration；只接纳 `sourceDurationMs >= 3000`，并按 duration、sourceBytes 降序与 linkageId 升序绑定三项自动 SFX case 共用的 `qualifiedLongSfx`。dense restore 后须等待该绑定的 floor duration 加 250ms 排空，mix 初始 SFX meter 必须 quiet；随后以同一 playing request、codec/container/decoder、非空 length 与合法 cursor 边界锁定 loop source，允许 cursor wrap 或整圈后相等，BGM/SFX 两路各以非静音 meter frame delta 证明贡献。assembler 只生成 9 组配置/输入和 `HUMAN_REQUIRED` drafts，固定 `promotionAuthorized=false`，不生成 E1、H2 或 pass。crossfade 自动证据保留所有 raw snapshot 的非静音与 frame 不回退约束，允许短 cached read；首尾 source 必须替换、总 frame 必须前进、至少 3 个 distinct frame sample，含 leading/trailing duplicate 的连续 no-progress wall-clock 窗口均须 `<=500ms`。它不要求每次读取都推进，也不证明 dual-slot gain envelope。

**R4 recovery evidence boundary**：`sleep_resume` 的 pre snapshot 只绑定原始 qualified endpoint，不参与恢复后 frame 差。每个 episode 以 `workingStateElapsed100ns` 计算：`<=15s` 为 target hit，`>15s && <=30s` 为结构化 target miss 且仍 bounded，`>30s` 失败。最后两个显式 qualification snapshots 必须都对齐末 closing `Ready` 的 session/generation/device/physical tuple；第二份必须在同一 BGM 或 SFX meter 上同时满足 frame 前进与 `peakAbsPcm16>=64`。
- **qualification run-root ownership**：`run-automated --capture-output-root` 必须逐路径等于 `<projectRoot>/tmp/audio-v2-qualification/<runId>/captures`，真实目录及从它到 project root 的每层 ancestry 都不得是 symlink/junction/reparse；lane 开始时必须为空。operator 不创建或清理该目录，并在每次 production capture 前重验 exact real path/ancestry；后续重验不再要求为空，以允许本 run 已产生的 capture pair 留在目录中。当前 `qualifiedLongSfx` 为 hash-bound `04_and_df1-22.wav`，`60882` B、146 个 MP3 frame、`168192` samples、`44100` Hz、floor duration `3813ms`（约 `3.813877s`）、SHA-256 `D06403877D9328656F5EA4B92D168274DAEBC2F8ABE43D24697C2DB286AB3C42`；minimum duration 为 `3000ms`，因此 dense→mix drain 为 `3813+250=4063ms`。
- **S10/S11 历史失败/重入边界**：历史五次 failed attempt 之后，S6 又有两次 operationally invalid/aborted run，以及 run `82a440cc…9870` 在前十 case/三份 TWS 非静音诊断 capture 后，于 Realtek→TWS default-device switch 触发 `miniaudio.dll` `0xc0000005` 崩溃；S9 `b2370…a108` 又因旧有限 SFX/UTC/stale-counter evidence contract fail-close。S10 source `82d2fe1d92aab9fb86677f37a3c3ebe2211fb4ff` / tree `0aa6ad2b0b1a564bb31f8b63e497633f21b7f398` 已完成双 clean repro，isolated candidate 本身 GO：identity `E28139CDC0AB7CCB34B0B19D9CDD88E3B85D65EB265010A4302578CCC849E671`、closure `FE874BA9CAC43B4ED944A1B5606DFDD03176C02A89F510338CEC251B2C768793`、runtime manifest SHA-256 `A59BE52C567DA5C20A12F069F02CB7D0EB1BFF96AC369D91E5142C2208CECA10`。但 run `b0672e56…59a03` 的 production/player 在一次休眠后以两个 bounded episode 完成 TWS→Realtek→TWS 恢复并回到原 pre digest时，S10 frozen observer 把每个 episode 的 endpoint digest 错误约束为全程不变；A6 因而在 case 13 证据实现误判处 diagnostic invalidated，case 14、E1、H2 均不存在，整个 run/capture 不得复用且仍 `NOT_DEPLOYED`。至此十个 runId/capture 均不可复用。S11 已形成并完成 fresh unattended non-device Source matrix：observer/runner/materializer/operator/assembler/updater `26/29/8/12/5/5`、contract `673`、Launcher `3547 passed + 3 opt-in skipped / 3550`、audio-focused `240`、native ABI `57` 与 support/backend 门、MF `78`、AS2 `-SkipCompile` `185`、Jukebox Edge `30`、shipped `12`、发布控制面 `108/65/109/16/13/48`；dependency 为 `568` entries / closure `F1DAB211BDFCB77B344FC05DF86B7E977C97E92FBD8E1DF75CA73155343F7A15`，文档治理与 diff check 通过。该时点未运行真实 endpoint enumeration/runtime playback contract，故 physical Source 未闭合，严格为 **H2 blocked / NOT_DEPLOYED**；这只描述 S11 历史 H2 合规路径。2026-08-15 owner-emergency 列车虽已 `promoted`，仍未满足 H2，也不改变这些失败证据；完整事故证据与台账见 [Audio Platform v2 ADR](../docs/原生音频平台-v2-格式能力桥接契约与可观测性-ADR-2026-08-09.md)。

### 外部 Agent / Wings ↔ CF7 Agent Runtime

- F8 implementation source `53caabc90941826ddacf626f536b0f473adbf049` 冻结合同实现，正式 release source `6f3d50a52413c747b05b74be88d6ee46650f4597` 只在 standard normal 组合运行时。developer JSONL/MCP 客户端通过受当前用户 ACL 保护的 rendezvous 和 CF7A 命名管道接入；无人值守安全身份是已选定并验证完整 manifest/payload closure 的 exact `Core.exe --agent-unattended-runner`，Node/PowerShell 只可包装该固定入口，不能提供 principal 或替代 Core provenance。
- `PipeOptions.CurrentUserOnly` 只保证当前用户边界；Host 仍从 OS peer token 独立验证 PID/start time、SID、Windows session 与 elevation，Hello 自报值不参与信任。F8 是首个 promoted v1 consumer；任何 wire-breaking 都必须新增 revision/version，并原子迁移 schema/registry/server/JSONL/MCP，不允许在既有 v1 内静默替换或部分 rollout。
- session/surface 信任使用 exact process incarnation：可执行路径 + PID + process start time + HWND/owner relation，拒绝标题、EXE 名、PID 单项或重用 HWND。Web `activePanel` 精确为 `{name,instanceId,targetId}`；NavigationStarting 立即推进 document generation，使旧 node/observation 失效。
- F8 production surface contract 将嵌入式 Flash 固定为 metadata-only：`observationModes=[]`、`inputModes=[]`，任何 pixel capture 精确失败为 `unsupported_for_surface`。production MCP tool list 与 session capabilities 都不列出或授予 `window.activate`，Host 的 activator map 为空；WGC 只允许 Launcher、WebOverlay、NativeHud，不能从 schema 中仍存在的类型推导实际 capability。
- `business_modal` 仍是 wire 闭集 selector，但 production 解析结果固定为空。Launcher-owned 中性同意卡内部登记为 `BusinessModal + HumanOnlySecuritySurface`，不进入 discover/capture/input；foreign modal 或第二个 security surface 出现即 fail closed。
- `trace.export` 只对显式 enrolled developer 的 `DeveloperInteractive` 会话开放，并要求 `trace.export + observation.export`、exact `consentPurpose` capability，以及同 principal/session 的 `data.export + allowExport + consent receipt` grant。输出是 Runtime-owned、最多 8 MiB、先以 owner staging marker 原子取得共同 process-incarnation pending marker、再把临时文件同目录原子改名的 JSONL；可控失败只清理本调用 owned files，删除受阻时保留 marker，由后续调用在 owner 已确定死亡或同进程 transaction 已退出后重试，owner 无法确认则跳过。无 marker 的 legacy `.tmp` 仅在取得独占打开后清理，无 marker 的 `.jsonl` 永不推断删除。marker 删除是发布线性化点；此前 crash 可回收，此后 response-loss 可能留下调用方未知但已发布的 artifact，单文件 move 不等于 filesystem/audit 跨资源事务。wire 只返回 artifact ID/name 与 scoped chain 元数据，不返回任意路径。
- Wings 自由文本永远零执行。F7 曾验证的 `window.activate` 管线仅作历史实现证据，F8 production 不暴露该能力。F8 `panel.open` 只接受 production allowlist 上的 immutable structured intent，selector 与 lease scope 必须解析为 exact 一个当前 `RuntimeOwned` Launcher target；lease 为 one-shot，dispatch 前后继续绑定该 singleton，成功只由 broker dispatch receipt 证明，不能由自由文本、panel 前缀或原生输入包取得 authority。所有 panel producer 的 `instanceId` 均由 CSPRNG 生成、熵至少 144 bit，前缀只作诊断而无授权语义。
- Hair 保持 `expectedCurrentHair` CAS、focused runner、commit 零 replay、close/reopen instance 隔离和同领域 restore。已确认 commit 的 raw restore token 只在 terminal receipt 一次性交付；unknown receipt 不携 token，只有同 transaction 实例、同 connection/principal/session/lifecycle/target 且 preview/store 均仍精确时，reconcile 证明 committed 后才可从 lifecycle-local escrow 消费一次。同 Core session/lifecycle 内的 transaction service restart 只从对应 durable service/store 重建状态并继续 reconcile，不能恢复或重建旧实例的 raw token；新 service/transaction 实例必须 fail closed。Core 重启还会改变 lifecycle 并拒绝旧事务。restore 前产品先 reconcile 持久记录为 `Committed`，无法确认时保留 commit receipt、绝不重放 commit。
- `LeaseDescriptor.purpose` 必填，`renewAfter` 可选；shutdown descriptor 必须省略 `renewAfter`。`session.shutdown` 只允许 `DeveloperInteractive` / `UnattendedTest`；请求的 exact target scope 必须恰含当前一个 `RuntimeOwned` Launcher target，这是该 scope 的 cardinality，不推导整个 session 全局只有一个 Launcher surface。专用 lease 的唯一 capability/operation 为 `session.shutdown`、TTL≤30 秒、one action、no renew。`PlayerAssist` 只有语法有效、已认证且通过全部先行授权门、实际到达 issuance policy 的 acquire 才返回 `consent_required`；畸形、越权或直接 action 可更早失败。
- lease live table 只保留 active 或尚在执行/交付的记录；terminal tombstone 按 FIFO 最多 256 条，已 committed shutdown session 的独立 latch 最多 64 条，容量溢出后转为全局 fail-closed，任何 eviction 都不能重新开放写入。renew/release 失败后的资源 cleanup 只允许 exact active owner，attacker、已 consumed 或仍 pending 的 lease 都不能借失败路径清理他人资源。
- 同 session execution reservation 只归成功 consume 的 action owner，并从 consume 保持到 JSON 与可选 binary 等全部 CF7A response frames 完成 `WriteAsync` commit 或显式 abort；失败 consume 从未拥有 reservation，不能释放、abort 或覆盖其他 owner。abort callback 返回 false 或抛异常时 reservation 保持并标记 continuity lost；完整 frames 已写出后 commit callback 返回 false 或抛异常时字节不可回滚，只能标记 continuity lost，且不能保证 SafeExit continue。action 的唯一绝对 deadline 在完整 request frame 收到时开始，覆盖 parse、admission、scheduler、performer、response writer lock 与全部 response-frame `WriteAsync`，任何阶段不得重置。
- SafeExit 只先 arm。Gateway 在首个成功 response 字节前顺序执行两道 claim：先 claim exact audit response identity，再 claim shutdown lease write ownership 与 human-input sequence fence；在 delivery ownership 建立前，external input 会撤销所有 active / execution-pending / delivery-pending / queued 且尚未取得交付写所有权的工作。第二道失败时必须保持零成功字节并同步 abort；一旦写所有权在首字节前成功 claim，随后 human override 不得回滚它，terminal 收束只归 response-completion state machine。
- `action_response_written` / `action_response_unknown` 是 reserved audit facts，generic append 必须拒绝；只有绑定 exact pending terminal identity 的专用 claim/complete 路径可以追加。DeliveryUnknown 必须投影 `EvidenceKind.ReconciliationRequired`。Action ledger 对已收束结果 replay 原样返回 retained `ContractReceipt`（包括 Unknown），不得再次 dispatch 或二次合成。全部 required frames 完成 `WriteAsync` 只代表 server-side delivery disposition，不是 peer acknowledgement；正常追加唯一 `action_response_written`，写失败追加 exact `action_response_unknown`。后置 Flush、post-write audit append 或 commit callback 失败都不回滚已写字节；audit append 失败只允许 continuity lost、pending removal 与 `truncated` segment，后续 dispose 不得再合成 Unknown。
- trusted Core runner 在每次完整 surface refresh（含周期 refresh）重试 credential publication；Host 以 single-flight 锁串行 publication，并在 teardown 先停止 admission/周期 refresh、再越过 publication barrier 后才 dispose 依赖。credential acquisition 使用 Core 内部按 exact ordinal slot 固定的单调上限：四个历史槽 30 秒，仅 A5 真实标题/固定进档栅栏为 60 秒，调用方不可配置；它独立于 bootstrap request/session 最长 10 分钟寿命。退出观察固定 `allowValidatedFlashKeyframeFallback=false`，只信 exact target 的 `SourceLayer.Launcher` frame；shutdown lease 与 receipt 必须逐字段严格匹配。可信退出只对 exact canonical transient 做有限重试：capture 的 `capture_unavailable / retryable=true / reconcileKind=none` 与 shutdown lease acquire 的 `input_not_quiescent / retryable=true / reconcileKind=none`；不重新 grant，不改变 scope/参数，`session.shutdown` action 永不重试。JSONL/MCP stdout 始终 protocol-only，不输出 credential、secret 或完成证据。只有 adapter exit code 0、strict shutdown receipt、同一 exact owned child exit code 0 且未发生 forced recovery 时，runner 才向 stderr 输出一行不超过 16 KiB 的非秘密证据，字段限于 schema、runtime mode、process path、Core SHA-256、build identity、payload closure、guardian PID 与 terminal receipt。
- A5 在 credential 原子可见前由 exact-owned Host 对同一 pipe/process/lifecycle/runtime qualification 换发新的 30 秒随机 rendezvous ticket；旧票即使已过期也从不被认可。换票或后续 credential 写入失败都保持无凭据，历史槽的 rendezvous 发布时序不变。
- F7 C1 的自动门与 `candidate_built / NOT_DEPLOYED`、F8 implementation candidate 的 `e2e_verified / NOT_DEPLOYED` 继续作为历史基线。F8 formal runtime 随后由 Agent Runtime MCP 自身完成可见 Launcher、NativeHud 与 WebOverlay 的 WGC/内存哈希、structured `panel.open` 和可信退出，未使用 Codex Computer Use、browser/Chrome、legacy privileged HTTP 或任何 `input.*`，也未持久化 pixel buffer 或写 PNG；同一 identity 经 promotion 后的正式入口窄纵切严格达到 `standard_entry_verified`。证据仍只来自单显示器，未取得 Flash pixels、未运行“13/13”扩展矩阵，也未验证 Hair/Wings 完整产品或业务写，不能外推这些未覆盖能力。

### Save Snapshot / File-Custody Boundary

- Launcher 的 shadow 文件保管与启动快照候选固定落在 `<projectRoot>/saves/`；哪个根启动 launcher，就只读取和维护哪个根的文件
- legacy SOL 定位只在当前运行根对应的 SharedObject 子树内进行，探测顺序为 `.swf` → `.exe` → 当前根 root-scoped fallback
- `reset` / `rebuild` / legacy SOL 删除都只影响当前运行根，不承担跨根合并或恢复职责

### Launcher Host ↔ WebView2

- Bootstrap 阶段：`chrome.webview.postMessage({cmd, ...})`
- 运行态：Bridge / Panel / UiData / Notch / overlay 消息桥
- 整备 rollout 与 opener 边界：`PreparationNavigationV1` 的代码默认和随仓配置均为 `true`；缺 key 使用代码默认，显式 `false` 或非法值会成套恢复旧 Native/legacy HUD、Build header 与 `returnFocusAction:"skills"` 的 presentation。该 gate 只切换导航呈现，不参与 route authorization，也不恢复任何已退役 AS2 全屏 UI。Equipment Tuning、Character、Materials、Intelligence 与 Skills 的 opener 仍分别受 exact source/instance/generation、Host nonce/admission、AS2 echo、revision/lease 和 lifecycle fence 约束；业务旅程的当前覆盖只读 [测试矩阵](testing-guide.md)，不能从通用 runtime 状态外推。
- Panel domain 路由：通用 `close` 始终最优先；其余携 `domain` 的请求先做领域分流。`domain=inventory` 独占 `InventoryTask → inventory_response → panel_resp(domain/cmd/callId)`，覆盖 range snapshot、move/merge/swap/discard、autoTransfer 与 `sortAndMerge`，并以容器写版本维护跨只读请求稳定的 OCC slot lease；`domain=npcshop` 只拥有目录、价格、材料/情报与交易计划，不再嵌套背包 snapshot；`domain=crafting` 由 `CraftingTask → crafting_response` 独占，Web preview 只传分类/配方索引/`craftCount`，commit 只传一次性 token，Flash 重算最终写入；`domain=hairdresser` 由 `HairdresserTask → hairdresser_response` 独占，只允许 snapshot 与 commit，77 行权威目录保持源顺序和重复项，Web 只做脸型/发型本地预览，AS2 重新校验免费目录后写 root/live actor 并置 dirty mark；未知写只由后发 fresh snapshot 判定 applied / not-applied，绝不重放；`world_hairdresser` NPC 已冻结为 Web-only，命令缺失或发送失败 fail-closed，不保留 legacy Flash renderer/fallback；`domain=skills` 由 `SkillTask → skill_response` 独占，严格使用带 `panelInstanceId` 的七键 envelope，active/candidate/return 实例门、write epoch 与 reconcile watermark 隔离迟到响应，关闭时由 Host 把 scoped cleanup 收敛为 `skillPanelClose`。Skill 的 `switch_manage/switch_trainer` 是独立 panel-control：只接受当前相应 view 实例和嵌套 `{v,focusSkillKey}`；trainer session 在往返 manage 期间只存 Host，manage Web 仅见 `canReturnTrainer`，不进入 AS2 业务路由。金币商店由 Web 组合 inventory 背包与 NPC collections；合成面板切入 workbench 时只共享 UI 意图，不共享 token 或写 authority；Host `HairdresserTask` 组合既有 `PanelPendingCallTracker`，Web `HairdresserRuntime` 组合现役 `PanelRuntime.PanelRequestMux`，不新建 pending/timer/mux、价格/token 或通用外观状态机；技能展示可复用共享密度、树导航/面包屑、pointer drag 和 AS2 HTML 白名单注释 primitive，但技能浏览、教师学习、快捷槽和被动开关不进入 inventory/equipment domain。这五个专属域都不得回落 legacy 全局 cmd/MapTask catch-all。无 domain 请求继续走既有 panel/cmd 路由。
- 材料商店往返是 domain mux 外的两条窄 flat transition command：Crafting Web 只发送 exact `open_npc_shop` hint，NPCShop Web 只发送 exact `return_crafting_materials` intent；两者都不能自开 Host-owned panel。`MaterialShopNavigationCoordinator` 独占 deadline、settlement witness 与三 Task lease，`MaterialShopAccessTask` 只承接 Host→AS2 fid/response correlation；AS2 以 current material snapshot、exact source occurrence 与 live NPC catalog 重新授权。成功 transition 只由 `PreparedPanelReplace/TryReplacePanelExact` 提交 admission、source retire 与 capability transfer；pre-commit failure 保留 source，post-commit mount/lazy failure exact close target且不回滚。Web 的 shopId/index/name、价格与 portrait 都只是 presentation hint，preferred navigation 与购买选择分离，购买继续进入 NPC/Inventory authority。
- 全屏显示层的 Web-only 边界：仓库/战备箱、装备/角色构筑、NPC 商店、合成和技能教师只允许正式 AS2 opener → `panel_request` → Host 白名单 → Web/领域服务；发送、准入或挂载失败必须可见且 fail-closed。Host 不再读取 `CF7_WEB_INVENTORY_WORKBENCH`，不再派发旧 `warehouse/openEquipUI`，AS2 也不 attach/跳帧回退旧 renderer。主 XFL 的 Include、递归时间轴放置与发布 SWF ImportAssets/linkage/PlaceObject 闭包不得再到达旧物品、改装、商店、仓库、教师或资源箱 UI；常驻快捷技能/药剂 HUD 的轻量图标与冷却投影仍属 Flash HUD 责任，不构成全屏 UI fallback。结构门见 `tools/audit-main-legacy-ui-reachability.js`，迁移护栏见 [as2-web-panel-migration.md](as2-web-panel-migration.md)。
- Team/Pet owner：`team` 与其嵌套 `pets` 共用 Host 当前 active `panelInstanceId`。所有 Pet 请求（含
  `equip_weapon` / `withdraw_weapon`）必须精确匹配 active Team owner；inactive、foreign、旧 replacement
  均在 Host 拒绝，owner 替换清退旧 pending，迟到响应不能跨实例采用。
- Exact close：Team 与 blackmarket 只发送携实例的 close intent，并等待 Host exact close acknowledgment；
  Bridge 投递成功不等于 Host 接受。Host 只 retire exact active name/instance，迟到 A 不得关闭 replacement B。
  旧 `panel:"pets"` close 信封 fail-closed；blackmarket 的 `dev + shadowOnly` 与匿名、无生产写语义不受影响。
- Settings ambiguity：非 preview 写的 timeout、DeliveryUnknown 或 malformed success 都建立 reconcile latch。
  latch 跨 close/rebind/pending cleanup 保留，只由锁存后发出的有效成功 Flash snapshot 清除，早期迟到 snapshot 不得解锁；期间写入 fail-closed，
  Web 不自动重放，也不把未知结果展示为确定未执行。cancel 半恢复继续保留首次基线并等待权威对账。
- Minigame：统一 `minigame_session` envelope。`blackmarket` 首版是 `dev + shadowOnly` 的全目录算法测试渠道：目录与影子余额只存在于 Web 开发会话，Host 只负责打开/关闭和脱敏日志，不拥有黑市经济。装备通过私有视觉 port 复用现役 `EquipmentInspector`：非颈部防具按 `fieldsByGender` 生成 fit/draw 字段，只渲染装备实际占用的局部肢体组件；武器解析完整单件或复合 dressup 商品图；两者再由 `MercPortraits` 有界队列生成透明快照。同组防具先协商双方共有的 authored 性别分支，无共同分支则整组封存；没有完整 dressup 的装备只允许影子态保 Alpha 锐化图标回退。统一 `item-surface` 管线按 Alpha/不透明背景分割 → 正交旋转 → 可选 RGB 保边锐化 → 精确 SDF → 自动骨架锚点 → 实际 Alpha 覆盖预算 → 休眠军用纳米机器人污泥生成；宏观 fBm 泥团、Worley 蜂群接缝、静态结节与冷金属微粒只改变材质，不改变遮挡预算。面板与主 SWF 共用 `1024×576` 逻辑画布，只允许 `PanelScale` 随宿主整体等比缩放，不按物理 viewport 重排。卡片与独立放大检视共享固定 `512×768` 覆泥母版；`inspection-focus` 只消费旋转后的 `objectBounds` 与污泥外扩半径，为共享 `WorkbenchInspectionViewport` 计算 fit/聚焦 zoom 和视线中心偏移，切侧、旋转与重开均重算。平移/缩放/90° 整体旋转不重跑污泥、不暴露真实标题且不改变购买选择。切组和生成失败期间只显示不含身份的封存层，原始解码图始终隐藏；当前可见六件优先交给独立 `OffscreenCanvas` worker，不支持时只允许单件主线程计算并保留 backend/置信度诊断。正式接入仍须新增 AS2 page draft/page object 权威与版本化 panel domain，不能从 minigame 注册或视觉 worker 推导为业务上线。
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
