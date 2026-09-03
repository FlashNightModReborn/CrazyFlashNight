# 黑市匿名影子版与独立目录开发测试

**状态**：`SHADOW_MINIGAME_V1 / PRIVACY_HARDENING_PROMOTED / ANONYMOUS_PRODUCT_FIXTURE / EXACT_ORACLE_NODE_ONLY / O1_OBSERVATION_CANDIDATE_ONLY / NOT_PRODUCTION_STATEFUL / NOT_E2E_VERIFIED`

2026-08-23 的匿名产品夹具、Node-only exact oracle 隔离与双币种账本修复已随 release source `416c4441947d40bc27ae3854178e87e2c5cf1ac9` 和 deployment `df060eac491c7251b261a3f5626960a8ea18911a` 进入正式 runtime；post-promotion audit run `32644777181` 已确认 `state=promoted / deploymentChanged=true`。
这只证明隐私加固字节已部署，不表示黑市生产经济、存档、掉落、NPC 入口、真实目录鉴定信号、物理 WebView2 或业务 E2E 已实现。普通安全表面继续是明确的匿名 shadow 降级。

普通 Launcher `BLACKMARKET_TEST` 现在只运行匿名合成状态机：三舱、购买、TP/K、提取/回售、覆泥安全表面和放大检视仍可操作，但 Web 不再请求或持有全量物品目录，不在购买前或购买后处理真实物品名、ID、资源 URI、精确回售价或真实类别。公开 `category/subclass/counterPrice` 使用与真实目录不相交的匿名分类和独立合成价格，不能再拿全目录价格反查候选。

全目录机械盘点、确定性配对 oracle、纸娃娃和武器素材验证已移到 Web 静态根外的 `tools/fixtures/blackmarket/`，只由 Node QA 读取。普通 lazy closure 与浏览器 harness 都不加载 exact oracle、catalog、`equipment-preview.js`、`EquipmentInspector`、dressup 或 portrait 依赖；产品 core/panel 不存在 marker、字符串 capability、exact session factory、Lab UI 或 catalog 注入钩子。历史 catalog URL 与旧 exact-core URL 在 Web 根均无文件可读。

## 边界

| 能力 | 当前实现 | 结论 |
| --- | --- | --- |
| 普通产品数据 | 每页 3 组、6 件匿名合成货物；分类固定为 `anonymous / 匿名影子货舱`，价格从独立夹具生成 | 不读取 `black-market-shadow-catalog.v1.json`，不能声称全目录玩法或真实平衡 |
| 安全表面 | 不透明 `visualHandle` 绑定到生成清单 `visual/visual-pool-manifest.js`（`tools/bake-black-market-visual-pool.js` 生成、`--check` 可复验）中全目录渲染资格条目（仅 `u`/`h` 渲染字段，零名称/价格/ID）；每页会话用私有熵洗牌分配，同页六件零撞车 | 设计意图：覆泥像素允许被认出（能猜、猜不准价），封死的是机器可读价格目录；bm21 逐字段反扫名称/ID 不出现在表面 URL，bm-ui2 继续封死目录 JSON 与 `data/`/XML 请求；正式接入由 Host 私有视觉字节端口替代 |
| 交易 | 会话内 TP/K 影子余额、幂等 receipt、提取/回售；历史显式记录 `deltaTp`、`deltaK`、`deltaV=deltaTp+50×deltaK` | `productionWrites=false`；退出即丢弃；成交结算数值仍是匿名合成夹具 |
| 注释释放（2026-08-26 产品决策） | 成交揭晓后释放真实物品身份与目录参考价（`realInfo`）；hover 预览走全局 PanelTooltip + buildItemRichHtml（与商店/情报同一套）：已揭晓给完整注释（描述/属性/获取方式由 **AS2 权威数据源**经 `blackmarketTooltip` 一跳提供，零派生副本、不随平衡调整漂移；Host/AS2 缺席时降级为基础卡），未揭晓只给同组分类注释；`productionEligibility` 为 `banned` 的条目扣下注释 | 购买前快照与 offer 投影仍零身份字段（bm24 锁定）；名称/价格只随"已成交易"释放，不构成预购答案钥匙 |
| exact 开发测试 | `tools/fixtures/blackmarket/exact-oracle-core.js` 与同目录 catalog 可验证全目录生成和私有视觉 source；Web 内 `visual/equipment-preview.js` 只被 Node 测试读取 | 只属于离线 Node QA；产品 panel 无法通过 initData、global marker、历史 URL 或 Web 自开升级到该能力 |
| 放大检视 | 卡片与检视窗共享固定 `512×768` 匿名覆泥母版，可拖拽、缩放、整体旋转和切换 A/B | 不调用读取真实标题/原图的 `EquipmentInspector.open()` |
| 存档 | 无 localStorage、无文件写入 | AS2 page object、flush、reconcile 均未实现 |

## 结构

- `core/index.js`：普通产品唯一 core。只生成匿名货物、私有 CSPRNG 句柄/表面 seed 与影子交易状态；表面端口把每页洗牌分配的池序号解析为视觉池清单中的真实物品图标（像素可见、名称/价格不可见），清单缺失时回退固定安全 SVG；浏览器导出仅 `createShadowSession` 等匿名 API。
- `blackmarket-panel.js`：普通 `Panels.register("blackmarket")` UI；固定 `1024×576` 并由 `PanelScale` 整体缩放，只消费 `product + surface + audit` 匿名端口。
- `visual/item-surface.js`：Alpha/SDF、自动锚点、正交旋转和休眠纳米污泥算法；普通产品只以固定安全 SVG 为输入。
- `visual/inspection-focus.js`：只消费匿名覆泥母版的 bounds/外扩半径，计算检视相机。
- `../../../../../tools/fixtures/blackmarket/exact-oracle-core.js`：Web 静态根外的 Node-only 全目录开发 oracle。
- `visual/equipment-preview.js`：仅供独立开发测试验证纸娃娃/武器 source，不在普通 lazy closure 中。
- `visual/visual-pool-manifest.js`：`tools/bake-black-market-visual-pool.js` 生成的全目录渲染资格 + 身份绑定清单（u/h/g/n/t/sc/p/s/at/e/k，零注释全文）。
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

浏览器 harness 现有 8 个场景：匿名三舱、DOM/新请求与历史 URL 负例、购买回售、旧 marker/capability 失效、固定布局、匿名放大检视、PanelScale，以及 close acknowledgment 丢失后保持打开并以同一 exact instance 重试。浏览器用例已编写不等于物理 WebView2 已执行；Node 门不代替像素观感、正式 runtime 或业务 E2E。

## 下一阶段

进入正式接入必须新增 AS2 权威 page draft/page object、存档、Host 私有且不可逆的视觉字节端口、authored eligibility、正式 panel contract、NPC 入口和真实失败恢复。不得把 dev exact core、全目录 JSON、影子余额或匿名合成报价直接翻转为生产实现。
