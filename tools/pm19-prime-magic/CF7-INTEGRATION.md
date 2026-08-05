# PM19 × CF7 集成说明（项目侧文档）

> 本文件是 CF7 工程对 `tools/pm19-prime-magic/` 的**归属与消费契约**记录。
> 数学定义、复现命令、审计报告的 canonical 文档是本目录自带的 [README.md](README.md)（交付方原文）。`SHA256SUMS` 只覆盖入仓交付文件，不包含该清单自身、项目侧本文件以及可重建的 `runtime/dist` / `runtime/node_modules`。

## 来源与完整性

- 2026-08-05 自 `prime-magic-19-delivery.zip`（外部交付）迁入，**排除 `runtime/dist` 与 `runtime/node_modules`**（均可由已入仓 TypeScript 真源和 lockfile 重建）。
- 参考用可视化交付 `prime-magic-visual-demo.zip` 未入仓，评估期解包副本在 `tmp/prime-magic-eval/prime-magic-visual-demo/`（tmp 不入仓，随时可弃）。
- 迁入及 2026-08-05 审阅收尾已在本机复验（Windows / Python 3.13.7 / Node 24）：
  - `sha256sum -c SHA256SUMS`：131 项全 OK；`.gitattributes` 固定文本为 LF，Windows checkout 可复现
  - Python 离线链：`python -m unittest discover -s python/tests`（12 passed）+ `python python/verify_manifest.py seeds/manifest.json --source fixtures/prime_semimagic_19.json`（`valid: true`，8 seeds，source SHA 已核对）
  - TS 运行时：`npm run test:all` 15/15 通过（显式测试文件列表，Windows / POSIX 同入口）；其中百万次轨道变换无错误

## 数学契约（下游消费只需记住这些）

- 8 张 19 阶完整质数幻方 seed：361 个互异质数，19 行 + 19 列 + 双对角线和均严格等于 `190000361`。
- 单 seed 轨道精确 `743,178,240` 个状态；8 seed 中心值两两不同 → 8 条轨道可证明不相交，合计 `5,945,425,920` 个合法棋盘。
- **离线验真、在线只置换**：运行时只做已证明保持幻性的坐标变换（中心化子置换 + 轴反转 + 转置），不判质数、不搜索、不重试。任何下游不得让运行时重新承担验证职责。
- 种子二进制加载时已带 SHA-256 核对（`binary-seed.js` 用 Web Crypto），加载失败即拒绝，不会静默用坏数据。

## 消费方式（vendoring 边界）

运行时消费者（当前：`launcher/web/modules/bg-gl/`，启动引导界面电子战背景层）**不跨目录引用**本目录——`bootstrap.local` 虚拟主机只映射 `launcher/web/`。规则：

1. 真源在本目录；下游持有的是**构建后字节级副本**（由 `runtime/src/*.ts` 生成的 `runtime/dist/src/*.js` → 下游 `pm19/`，`runtime/web/assets/` → 下游资产目录）。生成目录不入仓，也不进入 `SHA256SUMS`。
2. 升级路径：本目录更新 → `cd runtime && npm ci && npm run build && npm run test:all` → 从本次新鲜生成的 dist 复制 JS，并复制 assets 到下游 → 下游目检。
3. 下游的视觉层（渲染器配色、相位叙事、事件绑定）是消费者私有代码，**不回填本目录**；本目录只保存可复现的数学资产与通用运行时。

## 复现入口

- 重新生成/验真 seed、全部审计命令：见 [README.md](README.md)「一键复核」。
- 性能与渲染路线决策：见 [runtime/PERFORMANCE.md](runtime/PERFORMANCE.md)（渲染路线对比表、Worker/WASM 不引入的依据、目标机补测清单）。
- 数学证明：见 [reports/MATHEMATICAL_PROOFS.md](reports/MATHEMATICAL_PROOFS.md)。

## 相关文档

- 启动引导界面 PM19 背景层的设计与施工记录：[启动引导-PM19质数幻方背景-设计与施工-2026-08-05.md](../../docs/启动引导-PM19质数幻方背景-设计与施工-2026-08-05.md)；Launcher 侧集成说明见 `launcher/README.md`「PM19 质数幻方背景层」节。
