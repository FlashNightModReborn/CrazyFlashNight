# 黑市匿名影子版与独立目录开发测试

**状态**：`SHADOW_MINIGAME_V1 / PRIVACY_HARDENING_PROMOTED / ANONYMOUS_PRODUCT_FIXTURE / EXACT_ORACLE_NODE_ONLY / NOT_PRODUCTION_STATEFUL / NOT_E2E_VERIFIED`

2026-08-23 的匿名产品夹具、Node-only exact oracle 隔离与双币种账本修复已随 release source `0b7d5ec1880bfdbbcf252070d219c47af1811dac` 和 promotion `19f57d0fe6383f0ec9cae4d73646cf8197bd6ee5` 进入正式 runtime；post-promotion audit run `32613483455` 已确认 `state=promoted / deploymentChanged=true`。
这只证明隐私加固字节已部署，不表示黑市生产经济、存档、掉落、NPC 入口、真实目录鉴定信号、物理 WebView2 或业务 E2E 已实现。普通安全表面继续是明确的匿名 shadow 降级。

普通 Launcher `BLACKMARKET_TEST` 现在只运行匿名合成状态机：三舱、购买、TP/K、提取/回售、覆泥安全表面和放大检视仍可操作，但 Web 不再请求或持有全量物品目录，不在购买前或购买后处理真实物品名、ID、资源 URI、精确回售价或真实类别。公开 `category/subclass/counterPrice` 使用与真实目录不相交的匿名分类和独立合成价格，不能再拿全目录价格反查候选。

全目录机械盘点、确定性配对 oracle、纸娃娃和武器素材验证已移到 Web 静态根外的 `tools/fixtures/blackmarket/`，只由 Node QA 读取。普通 lazy closure 与浏览器 harness 都不加载 exact oracle、catalog、`equipment-preview.js`、`EquipmentInspector`、dressup 或 portrait 依赖；产品 core/panel 不存在 marker、字符串 capability、exact session factory、Lab UI 或 catalog 注入钩子。历史 catalog URL 与旧 exact-core URL 在 Web 根均无文件可读。

## 边界

| 能力 | 当前实现 | 结论 |
| --- | --- | --- |
| 普通产品数据 | 每页 3 组、6 件匿名合成货物；分类固定为 `anonymous / 匿名影子货舱`，价格从独立夹具生成 | 不读取 `black-market-shadow-catalog.v1.json`，不能声称全目录玩法或真实平衡 |
| 安全表面 | 不透明 `visualHandle` 只解析到固定身份无关 `data:` SVG；纹理 seed 与真实目录不存在映射 | DOM、ARIA、遥测和请求不含真实物品 URI；抽象形状不构成 exact 视觉验收 |
| 交易 | 会话内 TP/K 影子余额、幂等 receipt、提取/回售；历史显式记录 `deltaTp`、`deltaK`、`deltaV=deltaTp+50×deltaK` | `productionWrites=false`；退出即丢弃；揭晓名称和数值仍是匿名合成夹具 |
| exact 开发测试 | `tools/fixtures/blackmarket/exact-oracle-core.js` 与同目录 catalog 可验证全目录生成和私有视觉 source；Web 内 `visual/equipment-preview.js` 只被 Node 测试读取 | 只属于离线 Node QA；产品 panel 无法通过 initData、global marker、历史 URL 或 Web 自开升级到该能力 |
| 放大检视 | 卡片与检视窗共享固定 `512×768` 匿名覆泥母版，可拖拽、缩放、整体旋转和切换 A/B | 不调用读取真实标题/原图的 `EquipmentInspector.open()` |
| 存档 | 无 localStorage、无文件写入 | AS2 page object、flush、reconcile 均未实现 |

## 结构

- `core/index.js`：普通产品唯一 core。只生成匿名货物、私有 CSPRNG 句柄/表面 seed 与影子交易状态；浏览器导出仅 `createShadowSession` 等匿名 API。
- `blackmarket-panel.js`：普通 `Panels.register("blackmarket")` UI；固定 `1024×576` 并由 `PanelScale` 整体缩放，只消费 `product + surface + audit` 匿名端口。
- `visual/item-surface.js`：Alpha/SDF、自动锚点、正交旋转和休眠纳米污泥算法；普通产品只以固定安全 SVG 为输入。
- `visual/inspection-focus.js`：只消费匿名覆泥母版的 bounds/外扩半径，计算检视相机。
- `../../../../../tools/fixtures/blackmarket/exact-oracle-core.js`：Web 静态根外的 Node-only 全目录开发 oracle。
- `visual/equipment-preview.js`：仅供独立开发测试验证纸娃娃/武器 source，不在普通 lazy closure 中。
- `dev/qa-suite.js`：Node 逻辑门同时验证离线 exact oracle 和匿名产品契约，但明确选择不同 core。
- `dev/harness.html`：只含普通产品 UI/browser QA；不加载 exact 目录、oracle 或装备预览，并直接负测两个历史 Web URL 不可读。
- `../../../../../tools/fixtures/blackmarket/black-market-shadow-catalog.v1.json`：Web 静态根外的 Node-only 派生目录，不是 authored eligibility 真源。

## 入口

Launcher 内从“其他 → 测试 → 黑市鉴定测试”打开。Host 仍只发送：

```json
{"mode":"dev","source":"runtime","shadowOnly":true,"debug":true}
```

面板拒绝非 `dev + shadowOnly`。`debug:true` 不创建调试 API；`seed`、旧 bootstrap marker 或旧 `allowExactIdentityLab` 字符串即使由同页代码伪造，也不会改变匿名产品 core 或面板能力。`blackmarket` 仍没有普通游戏命令、NPC opener 或正式 domain contract。

浏览器夹具：

```text
launcher/web/modules/minigames/blackmarket/dev/harness.html?qa=1
```

## 验证

```powershell
chcp.com 65001 | Out-Null
node tools/derive-black-market-shadow-catalog.js --check
node launcher/tools/run-minigame-qa.js --game blackmarket
node tools/test-blackmarket-equipment-preview.js
node launcher/tools/validate-minigame-final-state.js
node tools/test-panel-contracts.js
```

当前 Node 逻辑门为 22/22：其中 `bm22` 锁定产品 core 拒绝 exact catalog，并证明所有公开 `category/subclass/counterPrice` 三元组在真实目录中命中 0 项；`bm20` 锁定 K 提取/回售双币种账本；`bm21` 用只存在于 CommonJS 的私有熵注入 seam 证明调用方 seed 不能重放产品状态。装备/检视专项当前为 44/44，并锁定旧 marker 预置后浏览器产品 core 仍无 exact API、普通 lazy closure 不含 exact/dressup 依赖、Web 根没有 exact catalog/oracle 文件，且两个历史 HTTP 路径均返回 404。

浏览器 harness 现有 7 个场景：匿名三舱、DOM/新请求与历史 URL 负例、购买回售、旧 marker/capability 失效、固定布局、匿名放大检视和 PanelScale。浏览器用例已编写不等于已执行；本轮没有物理 WebView2 结果，仍保持 `NOT_RUN`，Node 门不代替像素观感、正式 runtime 或业务 E2E。

## 下一阶段

进入正式接入必须新增 AS2 权威 page draft/page object、存档、Host 私有且不可逆的视觉字节端口、authored eligibility、正式 panel contract、NPC 入口和真实失败恢复。不得把 dev exact core、全目录 JSON、影子余额或匿名合成报价直接翻转为生产实现。
