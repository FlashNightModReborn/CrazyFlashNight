# 黑市匿名影子版与独立目录开发测试

**状态**：`SHADOW_MINIGAME_V1 / PRIVACY_HARDENING_PROMOTED / ANONYMOUS_PRODUCT_FIXTURE / EXACT_ORACLE_NODE_ONLY / O1_OBSERVATION_CANDIDATE_ONLY / NOT_PRODUCTION_STATEFUL / NOT_E2E_VERIFIED`

2026-08-23 的匿名产品夹具、Node-only exact oracle 隔离与双币种账本修复已随 release source `416c4441947d40bc27ae3854178e87e2c5cf1ac9` 和 deployment `df060eac491c7251b261a3f5626960a8ea18911a` 进入正式 runtime；post-promotion audit run `32644777181` 已确认 `state=promoted / deploymentChanged=true`。
这只证明隐私加固字节已部署，不表示黑市生产经济、存档、掉落、NPC 入口、真实目录鉴定信号、物理 WebView2 或业务 E2E 已实现。普通安全表面继续是明确的匿名 shadow 降级。

普通 Launcher `BLACKMARKET_TEST` 运行匿名合成交易状态机：三舱、购买、TP/K、提取/回售、覆泥表面和放大检视可操作。公开 `category/subclass/counterPrice` 使用匿名分类和独立合成价格。2026-08-26 的测试版产品决策已让客户端视觉池携带真实图标、名称和参考价；购买前快照仍不投影身份，但客户端清单不构成保密边界。完整 exact catalog/oracle 仍只供 Node 开发测试，正式经济和存档未接入。

全目录机械盘点、确定性配对 oracle、纸娃娃和武器素材验证已移到 Web 静态根外的 `tools/fixtures/blackmarket/`，只由 Node QA 读取。普通 lazy closure 与浏览器 harness 都不加载 exact oracle、catalog、`equipment-preview.js`、`EquipmentInspector`、dressup 或 portrait 依赖；产品 core/panel 不存在 marker、字符串 capability、exact session factory、Lab UI 或 catalog 注入钩子。历史 catalog URL 与旧 exact-core URL 在 Web 根均无文件可读。

## 边界

| 能力 | 当前实现 | 结论 |
| --- | --- | --- |
| 普通产品数据 | 每页 3 组、6 件匿名合成货物；分类固定为 `anonymous / 匿名影子货舱`，价格从独立夹具生成 | 不读取 `black-market-shadow-catalog.v1.json`，不能声称全目录玩法或真实平衡 |
| 覆泥表面 | 不透明 `visualHandle` 绑定到 `visual/visual-pool-manifest.js` 的真实图标及身份绑定条目；每页私有熵洗牌，同页六件零撞车；生成器 `--check` 复验冻结目录的视觉投影 | 像素允许被认出；购买前快照仍零身份字段。视觉清单包含名称和参考价，不声称客户端不可反查；正式接入仍需 Host 私有视觉字节端口 |
| 交易 | 会话内 TP/K 影子余额、幂等 receipt、提取/回售；历史显式记录 `deltaTp`、`deltaK`、`deltaV=deltaTp+50×deltaK` | `productionWrites=false`；退出即丢弃；成交结算数值仍是匿名合成夹具 |
| 注释释放（2026-08-26 产品决策） | 成交揭晓后释放真实物品身份与目录参考价（`realInfo`）；hover 预览走全局 PanelTooltip + buildItemRichHtml（与商店/情报同一套）：已揭晓给完整注释（描述/属性/获取方式由 **AS2 权威数据源**经 `blackmarketTooltip` 一跳提供，零派生副本、不随平衡调整漂移；Host/AS2 缺席时降级为基础卡），未揭晓只给同组分类注释；`productionEligibility` 为 `banned` 的条目扣下注释 | 购买前快照与 offer 投影仍零身份字段（bm24 锁定）；名称/价格只随"已成交易"释放，不构成预购答案钥匙 |
| exact 开发测试 | `tools/fixtures/blackmarket/exact-oracle-core.js` 与同目录 catalog 可验证全目录生成和私有视觉 source；Web 内 `visual/equipment-preview.js` 只被 Node 测试读取 | 只属于离线 Node QA；产品 panel 无法通过 initData、global marker、历史 URL 或 Web 自开升级到该能力 |
| 放大检视 | 卡片与检视窗共享固定 `512×768` 匿名覆泥母版，可拖拽、缩放、整体旋转和切换 A/B | 不调用读取真实标题/原图的 `EquipmentInspector.open()` |
| 存档 | 无 localStorage、无文件写入 | AS2 page object、flush、reconcile 均未实现 |

## 结构

- `core/index.js`：普通产品唯一 core。只生成匿名货物、私有 CSPRNG 句柄/表面 seed 与影子交易状态；表面端口把每页洗牌分配的池序号解析为视觉池清单中的真实物品图标（像素可见、名称/价格不可见），清单缺失时回退固定安全 SVG；浏览器导出仅 `createShadowSession` 等匿名 API。
- `blackmarket-panel.js`：普通 `Panels.register("blackmarket")` UI；固定 `1024×576` 并由 `PanelScale` 整体缩放，只消费 `product + surface + audit` 匿名端口。
- `visual/item-surface.js`：真实池图标的 Alpha/SDF、自动锚点、正交旋转和休眠纳米污泥算法；清单缺席时才用固定安全 SVG。
- `visual/inspection-focus.js`：只消费匿名覆泥母版的 bounds/外扩半径，计算检视相机。
- `../../../../../tools/fixtures/blackmarket/exact-oracle-core.js`：Web 静态根外的 Node-only 全目录开发 oracle。
- `visual/equipment-preview.js`：仅供独立开发测试验证纸娃娃/武器 source，不在普通 lazy closure 中。
- `visual/visual-pool-manifest.js`：`tools/bake-black-market-visual-pool.js` 生成的全目录渲染资格 + 身份绑定清单（u/f/fm/h/g/n/t/sc/p/s/at/e/k，零注释全文）；可选 `f` 仅指同 iconKey 的另一帧，`fm` 区分透明完整帧与背包图的 Alpha 策略。
- `launcher/web/assets/minigames/blackmarket/`：面板美术资产——`tank-interior.webp`（舱液背景，AI 精致化后人工验收）、`device-frame.webp`（合成台机体淡影，backdrop 用）。
- `dev/qa-suite.js`：Node 逻辑门同时验证离线 exact oracle 和匿名产品契约，但明确选择不同 core。
- `dev/harness.html`：只含普通产品 UI/browser QA；不加载 exact 目录、oracle 或装备预览，并直接负测两个历史 Web URL 不可读。
- `../../../../../tools/fixtures/blackmarket/black-market-shadow-catalog.v1.json`：Web 静态根外的 Node-only 派生目录，不是 authored eligibility 真源。

## 入口

Launcher 内从“其他 → 测试 → 黑市鉴定测试”打开。Host 仍只发送：

```json
{"mode":"dev","source":"runtime","shadowOnly":true,"debug":true}
```

面板拒绝非 `dev + shadowOnly`。`debug:true` 不创建调试 API；`seed`、旧 bootstrap marker 或旧 `allowExactIdentityLab` 字符串即使由同页代码伪造，也不会改变匿名产品 core 或面板能力。`blackmarket` 仍没有普通游戏命令、NPC opener 或正式 domain contract。

调试抽屉（header「调试」按钮）：只调整匿名影子会话的四个白名单数值参数
（tradePoints/kPoints/supplyCredits/decryptLevel，core `validateOptions` 强制），应用即以新参数
重开会话；目录、身份、视觉池不在可调范围（bm25/bm-ui11 锁定）。该抽屉不是历史 exact Lab，
不能从它提权到真实目录或生产写入。

close 仍属于 Host-owned panel lifecycle。Web 必须发送当前 `panelInstanceId`，并等待 Host 返回 exact
`panel_cmd close` 后才 retire；Bridge 投递成功不等于 Host 已接受。Host 只关闭当前 active
name/instance；确认在 3 秒内丢失时 Web 只解除 pending 以允许重试，不本地关闭，也不允许旧 timer
解锁 replacement。迟到实例 A 的 close 不能关闭 replacement B。该约束不改变 `dev + shadowOnly`、
匿名表面、影子余额或 `productionWrites=false`。

### O1 软锁观测（临时候选能力）

仅当进程环境 `CF7_BLACKMARKET_SOFTLOCK_OBSERVATION` **精确等于** `1` 时，Host 才在 initData 中下发 `softlockObservation:true`；heartbeat 的 Host 接收入口还会再次检查同一精确开关，`0`、`true`、空值或其他字符串都保持关闭。Web 在打开/重绑后立即发送一次 heartbeat，随后每 10 秒发送 `{panelInstanceId,documentGeneration,sequence,snapshotRevision,pending}`；close、force-close、rebind、pagehide 均清 timer。

Host 只接受当前 blackmarket exact instance、递增 sequence 与有界整数，按真实 Web 文档生命周期最多记录 64 条 `event=blackmarket_softlock_observation`。每个 heartbeat 至多维持一个 observation-only AS2 probe，用现有 socket generation 读取 `businessOwner/pauseOwner/sceneOwner/frameSequence`，并同时记录 Web pending、Host route outstanding 与 socket ready。探针没有业务写、timeout、retry、watchdog、自动关闭或修复能力；目前机器只能安全输出 `no_outstanding_operation` 或 `inconclusive`，主动复现时再按止血治理 ADR 结合现场日志裁决四种合法结论之一。该能力默认关闭、未进入正式 runtime，不能拿 heartbeat 存活或沉默单独推断卡顿 owner。

P2 演出钩子：面板通过 `minigame_session` 的 `kind="fx"` 上报机器演出时刻（`fx` 字段取值
`fx-poweron / fx-select / fx-reveal-profit / fx-reveal-loss / fx-error / fx-scan-open /
fx-scan-rotate / fx-drain`），供 Host 或未来音效系统消费；纯通知、无状态依赖，Host 缺席即 no-op。
所有演出 FX 均为 `pointer-events:none` 纯装饰层，不拦截输入、不改变任何逻辑时序。

浏览器夹具：

```text
launcher/web/modules/minigames/blackmarket/dev/harness.html?qa=1
```

## 验证

### 污泥 v3（2026-10-26 视觉验收，未部署）

购买前统一使用 `Core.HIDDEN_COLOR_MODE = monochrome`：材料、消耗品、装备、备用帧与安全表面均采用同一中性灰处理，保留明暗和纹理。放大、旋转和切侧仅变换已经去色的覆泥母版；解密等级只改变覆盖面积，不恢复饱和度。仅 `visualState === revealed` 的成交物恢复 `source` 原色；撤回、封签及其他未成交状态仍去色。半透明发光与抗锯齿边缘也统一去色，不再按主体掩膜跳过可见像素。原清单 `h` 保留为 `sourceMaskMode`，不再决定玩家看到的颜色，避免统一去色误改透明图分割。

颜色对照回归使用 `--comparison color --baseline <上一轮候选 item-surface.js>`，按全池四档比较物体/污泥/揭示掩膜逐字节一致、裸露处中性色、揭晓原色一致与已有灰色主体像素不变；浏览器另验证六件彩色材料的购买前卡面、放大/旋转/切侧及真实影子成交状态。这里只执行隔离测试，不代表部署或正式游戏存档验证。

`object-sdf-nanobot-sludge.v3` 在实际分辨率前景上建立八邻接图，为每个真实部件分配有限的测地揭示顺序。独立部件依次开启连续清洗前沿；细线和对角线不再因 128 格降采样而不可达。同一种子下四档揭示集合嵌套，覆盖预算固定为 `round(objectPixels * coverage)`。

外沿和滴落只添加到物体之外，最终仍必须连接到物体内部的污泥。`actualCoverage`、`coveredObjectPixels` 从最终污泥与物体掩膜的交集重新计数；`coverageInvariant`、`unreachableObjectPixels` 用于回归。`diagnostics:true` 可返回最终物体、揭示、污泥和预算掩膜，默认不返回这些大数组。材质、经济参数和四档目标覆盖率保持原值。

分割优先使用已有 Alpha，禁止以“占画面比例高”推断不透明背景。代理背包图通过不透明核心及局部抗锯齿边缘剔除软底影，保留独立部件；真正不透明的输入只在边框颜色一致时尝试保守背景洪泛。不确定输入保留并标记 `ambiguous`，不把剩余碎片报成高置信度轮廓。`sourceMaskMode` 独立于揭晓后的颜色模式，保持取景一致；原始裁切图仍是裁切图，算法不会恢复画面外的缺失内容。

全透明主图抛出 `empty-source`，渲染器仅尝试清单明确绑定的同物品备用帧一次；隐藏态使用中性色，揭晓态恢复原色。没有有效备用图时正常失败，不生成空白成功结果。不透明且无法可靠分割的主图也可尝试同物品透明帧，但原始渲染始终保留到备用帧被确认可用；备用帧仍不透明、解码/网络失败或超时均回到原图并标记原因。销毁或取消仍正常拒绝，不恢复过期画布。池内身份、顺序、价格、资格及原始主图路径维持冻结基线；生成器支持当前池已有的 PNG 导出，不因旧 catalog 路径后缀丢弃条目。

Worker 请求在启动和解码前登记；同键请求合并但每个视图独立交付元数据。启动、转移后崩溃、消息错误及超时转主线程队列恢复；销毁和画布被新请求取代均以 `AbortError` 收敛，迟到结果关闭位图并丢弃。默认请求超时 30 秒；主线程任务之间让出事件循环。表面缓存和揭示场缓存有界；失败的资源请求从缓存驱逐后可重试。

专项命令：

```powershell
node tools/test-blackmarket-surface.js
# 需在 NODE_PATH 中提供 @napi-rs/canvas 与 playwright；基线是冻结的旧 item-surface.js。
node tools/run-blackmarket-surface-regression.js --out <绝对输出目录> --baseline <旧源码路径> --workers 4
node tools/run-blackmarket-surface-browser.js --out <绝对输出目录> --chrome <Chrome路径>
```

全池工具验证所有独立 `u/h` 输入的四档最终像素预算、嵌套揭示、可达性、RGBA 重复一致性及干净揭晓图，另用两个种子验证前景图。浏览器工具使用真实 Worker、OffscreenCanvas 和产品 DOM；比较像素时统一位图转存和 CPU 读回路径，避免 GPU 读回切换的舍入差异。离线像素、浏览器执行、正式 WebView2 和人类视觉验收分别记录。

若只修改请求生命周期/备用图选择，可通过 `--reuse <上轮结果> --reuse-source <上轮源码> --reuse-pool <上轮池快照>` 进行增量复验。工具核对渲染核心字节、基线、完整参数、Node/Canvas 版本、主图路径/模式和图片哈希；选用备用帧的输入仍重新渲染。结果明确记录复用条数及新增渲染次数，不能把新增执行次数与完整覆盖范围混为一谈。

冻结基线的 `derive-black-market-shadow-catalog.js --check` 已有目录漂移（冻结 1625 条，2026-10-25 隔离评估时 XML 推导 1743 条）。本候选不重建它，以免改变本轮 1462 条测试池及经济数据；视觉生成器仍须独立 `--check` 通过。

```powershell
chcp.com 65001 | Out-Null
node tools/derive-black-market-shadow-catalog.js --check
node tools/bake-black-market-visual-pool.js --check
node launcher/tools/run-minigame-qa.js --game blackmarket
node tools/test-blackmarket-equipment-preview.js
node launcher/tools/validate-minigame-final-state.js
node tools/test-panel-contracts.js
```

当前 Node 逻辑门为 25/25：其中 `bm22` 锁定产品 core 拒绝 exact catalog，并证明所有公开 `category/subclass/counterPrice` 三元组在真实目录中命中 0 项；`bm20` 锁定 K 提取/回售双币种账本；`bm21` 用只存在于 CommonJS 的私有熵注入 seam 证明调用方 seed 不能重放产品状态；新增用例锁定 O1 默认关闭、精确启用、立即/10 秒 heartbeat 与 cleanup。装备/检视专项当前为 44/44，并锁定旧 marker 预置后浏览器产品 core 仍无 exact API、普通 lazy closure 不含 exact/dressup 依赖、Web 根没有 exact catalog/oracle 文件，且两个历史 HTTP 路径均返回 404。

浏览器 harness 现有 11 个场景，包含匿名三舱、DOM/新请求与历史 URL 负例、购买回售、旧 marker/capability 失效、固定布局、匿名放大检视、PanelScale、调试参数与 close acknowledgment 丢失后的同实例重试等。浏览器用例不等于物理 WebView2 已执行；Node 门不代替像素观感、正式 runtime 或业务 E2E。

## 下一阶段

进入正式接入必须新增 AS2 权威 page draft/page object、存档、Host 私有且不可逆的视觉字节端口、authored eligibility、正式 panel contract、NPC 入口和真实失败恢复。不得把 dev exact core、全目录 JSON、影子余额或匿名合成报价直接翻转为生产实现。
