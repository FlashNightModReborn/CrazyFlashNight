# CF7-AnimateKit 开发规格 v1

> 项目专用、纯离线、干净入库的 Adobe Animate 生产力工具。
> 参考"醉尘仙 AN 插件"破解包**所用的技术**（CEP/JSFL 面板、`.sol`/AMF 读写、AN 维护工具），
> **剥离其全部越权部分**（联网、远程授权校验、MAC 算号、DRM `.sol` 伪造、改 hosts），
> 主目标：**给 CF7 动画素材师提速**。

| 字段 | 值 |
|---|---|
| 状态 | 草案 v1（待 owner 评审 → 进入 P0 脚手架） |
| 工具目录 | `tools/cf7-animate-kit/` |
| 命名约定 | 文件夹 `cf7-animate-kit`，规格 `CF7-AnimateKit-DevSpec-vN.md`（对齐 `cf7-balance-tool`） |
| 命名理由 | 不沿用 `醉尘仙/ZCX/ZCXGZS` 任何标识；"AnimateKit" = AN 维护 + .sol 编解码 + 创作提速三合一 |
| 协作语言 | 中文（技术名词保留英文） |
| 创建日期 | 2026-06-13 |

---

## 0. TL;DR（可行性结论）

**技术上完全可行，且与本仓库现有工具栈高度契合。** 卡点不在能不能做，而在守好清室边界。

- 三大能力域全部可落地：**①AN 维护**（独立 Electron，Animate 关闭时用）、**②`.sol`/AMF 读写**（纯 TS 库，可反哺 `cf7-save-repair`）、**③创作提速面板**（CEP web 面板 + JSFL，Animate 内运行）。
- 现代 web 落点已核实：Animate 内唯一的"现代 web"路径是 **CEP（Chromium + 可选 Node.js）+ JSFL 桥**；**UXP 暂不对 Animate 第三方开放**，不能依赖。CEP 在落日期但当下可用。
- 仓库已有可复用资产：Rust `flash_lso` 解析器（`amf0-help/sol_parser`、`launcher/native/sol_parser`）可作 `.sol` 编解码的**字节级测试 oracle**；`cf7-balance-tool` 是现成的 monorepo 模板。
- 边界：**算号/伪造激活 `.sol`/绕远程校验/改 hosts/复用反编译代码**一律不做。详见 §7。

---

## 0.5 施工状态（2026-06-13 落地）

P0–P5 **全部建成**，`tools/cf7-animate-kit/` 已入库。机器可验证部分全绿，GUI/Animate 部分待人工 smoke-test。

| 阶段 | 包 | 状态 | 验证 |
|---|---|---|---|
| P0 | `core/amf` + `cli sol` | ✅ | 38 测试含 7 fixture **字节级 round-trip** + **Rust flash_lso 金标 JSON** 双 oracle；真实 8KB 游戏存档通过 |
| P1 | `core/an` + `an-host` + `cli an` | ✅ | tmpdir 维护测试 + `an doctor` 在真机发现 Animate 2024 安装；`containsMachineId:false` 守护测试 |
| P3 | `core/authoring` + `cli art` | ✅ | XFL 解析/lint/查重测试 + 真实 1568 符号工程解析通过 |
| P3 | `jsfl-host` | 🟡 代码完成 | 纯 JSFL，**需 Animate 内 smoke-test**（见包 README） |
| P2 | `web`（Electron cockpit） | 🟡 构建通过 | typecheck 0 错 + `vite build`+`esbuild` 产出 main.cjs；**GUI 行为需人工 smoke-test** |
| P4 | `cep-panel`（CEP 面板） | 🟡 构建通过 | typecheck 0 错 + 产出自包含扩展 dist；**需 Animate 内 smoke-test** |
| P5 | 文档/打包 | ✅ | source-audit / clean-room-boundary / operation-manual / sign-zxp |

机器门：`npm run typecheck` 0 错、`npm test` **42/42** 绿、两个 GUI `npm run typecheck` + `npm run build` 通过。

**后续增量(2026-06-13 同日)**：
- **无人值守 JSFL runner**(对标仓库 CS6 编译链):`jsfl-host` 加 `runner-main.jsfl` + `npm run build`→自包含 `cf7ak-runner.jsfl`;
  `an-host/jsfl-runner.ts`(job 写→触发→轮询 marker+**新鲜产物校验**→读 JSON,**4 个 stub-trigger 单测**);`cli art run` / `art setup-task`。
  **意义**:能力③ 变 agent/CI 可驱动、可对真 CS6/Animate 验证;且 **CS6 装不了 CEP 面板,runner 即 CS6 原生提速路径**。
- **GUI 体验对齐 cf7-packer**:`web`+`cep-panel` renderer 加可拖拽分栏(ResizeHandle+useLayoutResize)、`useLocalStorage` 状态持久化、
  CSS 动效(无新重依赖)、**D3 v7 可视化**(web:SOL 结构 treemap;panel:linkage 覆盖图)、更厚的 SOL 树(类型徽章/搜索/展开)。
  IPC/bridge 契约未动;两包 typecheck+build 双绿。

**真机联调 + wave1~3(2026-06-13,已在真机 Animate 2024 验证)**:
- **CEP 面板已装进真机并跑通**(`%APPDATA%\Adobe\CEP\extensions\com.cf7.animatekit.panel` + PlayerDebugMode)。白屏根因=CEF 拒载外部 `type=module`(file:// 无 MIME)→ 用 `vite-plugin-singlefile` 内联修复;另 `node:path` vite alias→stub。验证手段=`.debug` 端口 8088 远程 DevTools + PowerShell `.NET ClientWebSocket` 连 CDP(`Runtime.evaluate`/`Page.captureScreenshot`)。
- **wave1**(导出 8 函数)/**wave2**(库·帧·滤镜 11)/**wave3**(预设·位图·诊断 7)共 26,加 7 个工具/发现函数(ping/probe/scanLinkage/applyLinkage/listFrameLabels/exportSelected/publish)= **33 个 dispatcher case**;全部真机实测过(只读用 live 档、破坏性用 `fl.createDocument()` scratch 废档不保存);面板 6 标签 / ~33 函数。**JSFL host 改动靠 `eval(FLfile.read(host))` 热加载免重启**。
- **owner 拍板:醉尘仙的 运镜/表情/走路 等"沙雕动画"功能对 CF7 无用,不做**。
- **完整开发/交接总览见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)**(架构 + 开发循环 + CEP 踩坑手册 + 怎么加函数 + 故障速查)。

**待人工 smoke-test（无法 headless 验证）**：① `web` Electron GUI 各按钮（装插件/jvm/缓存/侧边/SOL 编辑）在装 Animate 的 Win 机；
② `cep-panel` 在 Animate 内加载 + 四个标签页；③ `jsfl-host` 各函数（尤其 `SpriteSheetExporter` 签名因版本而异）。

**已知小项**：`cep-panel` 经 core barrel 间接引入 `anEnv`→`node:path`（被 Vite externalize），CEP 开 Node 下无害，
可后续用 core 子路径导出瘦身。**P5 面板纵深**（库内重复符号一键合并 UI、帧↔JSON 写回、配色批量应用 UI）属增强：
headless 侧（`art dup-scan`/`frame-extract`）已具备，**面板内的变更型 UI 故意延后**（风险高且无 Animate 不可验证，符合"先只读提取"纪律）。

---

## 1. 来源审计摘要（黑盒行为，仅作参考文档）

下载包 `自用限制插件` 的真实身份是商业付费 Animate 扩展 **"醉尘仙 AN 插件 v10.6"** 的**离线破解激活包**（源码经 `uncompyle6` 反编译；仓库 `tmp/zuichenxian-plugin-analysis/` 已有先前分析产物）。它本身不含创作功能，全部是绕授权的机器 + 一批正经维护小工具。

被绕过的四层 DRM 与对应破解手法（**仅作行为记录，本项目一律不复刻**）：

| 层 | 醉尘仙的机制 | 破解手法 | 本项目态度 |
|---|---|---|---|
| 机器绑定 | `active_code = MD5(MAC+"FUCKYOU").hex().upper()` 切 5 组 | 本机重算 | ⛔ 不做算号 |
| 用户码校验 | 12 位、4 条 mod-10 约束 | 反推约束伪造合法码 | ⛔ 不做 keygen |
| 状态存储 | Flash SharedObject `.sol`（AMF 二进制） | 手拼字节写入所有候选目录、删 `0000.sol` | ✅ 只保留**通用 .sol 编解码技术**，⛔ 不做 DRM 字段伪造 |
| 远程 kill-switch | 请求 `pispik.com/.../verify` 期望 `OK` | patch SWF 把 URL 改死端口 + hosts 屏蔽 | ⛔ 不做联网、不改 hosts、不 patch 任何 SWF |

可光明正大复刻的**正经维护功能**（破解包里 `Setup_source.py` 的 `function_1~6`）：装/更新/删插件 SWF、清 WindowSWF 缓存、改 `jvm.ini` 扩内存、收侧边、打开 WindowSWF/Commands 目录、复制机器信息（纯诊断、非算号种子）、SharedObject 诊断。

> 审计原始结论详见 `docs/source-audit.md`（P0 时补写）。本规格只把审计当作"哪些**合法按钮**存在"的黑盒说明，**不引用其任何一行实现**。

---

## 2. 目标 / 非目标

**目标**
- G1 一个干净、纯离线、可入库的项目专用 Animate 工具，分三能力域交付。
- G2 主价值：把素材师在 Animate 里的重复劳动（导出、linkage、查重、规范校验）自动化。
- G3 产出一个通用 `.sol`/AMF0 TS 编解码库，可被 `cf7-save-repair` 等本仓工具复用。
- G4 易维护：纯逻辑与宿主耦合分层隔离；为未来 UXP 迁移留低成本路径。
- G5 完全贴合现有工具栈与文档纪律（monorepo / strict TS / Vitest / DevSpec 文档）。

**非目标（硬边界，见 §7 清室排除）**
- N1 任何联网、远程校验、遥测。
- N2 任何 MAC 算号 / 用户码 keygen / 激活码体系。
- N3 伪造醉尘仙的 DRM `.sol`（带 `ZCXGZS` TCSO 头的 mac/recomm/active/consum 四字段 blob）。
- N4 改 hosts / DNS / 防火墙 / patch 第三方 SWF。
- N5 复用 `tmp/zuichenxian-plugin-analysis/` 下任何反编译代码、作者串、DoSWF 壳。

---

## 3. 现状盘点（仓库已有、必须复用或尊重）

**`.sol`/AMF 既有资产（能力②的 oracle）**
- `amf0-help/sol_parser/`：基于 Rust `flash_lso` crate 的解析器（已构建）。
- `launcher/native/sol_parser/`：launcher 侧 native 解析器；fixture `tests/fixtures/real_flash_v3.sol`。
- `amf0-help/probe_sols/*.sol`：探针样本（nested/root/self/typed/types/flwriter）。
- `tools/cf7-save-repair/`（单包 TS，`src/*.ts` + Vitest）：能力②的**直接消费方**（当前只处理 JSON 影子，未来可直接读写真 `.sol`）。
- 存档语义约束（见项目记忆"存档=SOL 权威+JSON 影子"）：**SOL 才是权威**，游戏运行时自动存档会 SOL→JSON 覆盖；**任何 `.sol` 写入必须 backup-before-write，且禁止在游戏运行时写**。

**素材/创作既有资产（能力③要尊重/吸收）**
- `flashswf/arts/new/`：60+ 源 FLA/XFL 工程（角色/NPC/武器/特效），素材师真实工作目录。
- `tools/jsfl/publish.jsfl`、`tools/removeParentChildRelationships.jsfl`：既有 JSFL，P3 收编进 `jsfl-host`。
- `tools/xfl_duplicate_detector/`：XFL 符号查重（语义/结构/文本），能力③"查重合并"的算法来源。
- `tools/色彩预设xml生成器/`、`高级色彩引擎.fla`、`渐变调色器.fla`：色彩预设 schema，能力③"配色批量应用"复用。
- `tools/碰撞箱生成工具/`：碰撞盒几何，可选能力。
- `export-map-avatar-assets.py` / `export-map-composite-assets.ps1` / `export_sfx.py` / `crop-nonsquare-avatars.ps1`：现有导出管线（FFDec CLI 驱动）。新面板**对齐其约定**，不取代其离线批处理。

**工具栈模板**
- `tools/cf7-balance-tool/`：npm workspaces monorepo，`packages/{core,xml-io,cli,web}`，Electron 35 / React 19 / Vite 6 / tsx / Vitest，`launch.bat` 运行时下 Electron。
- `tsconfig.base.json`（逐项照搬）：`target ES2022 / module NodeNext / strict / noUncheckedIndexedAccess / exactOptionalPropertyTypes / verbatimModuleSyntax / declaration+maps`。

**必须尊重的约定（不可破坏）**
- `linkageIdentifier` 唯一、`linkageExportForAS=true`，导出文件名 = linkageId。
- 库文件夹层级 = 符号路径；头像 44×44 ARGB（alpha-bbox 裁剪后）；音频 linkageId = 文件名。
- **XFL 优先**（不要压平成 FLA 二进制，工具假定 `DOMDocument.xml` + `LIBRARY/` 可解析）。
- `asLoader` 时间轴约 ~900 帧、帧标签分区（引擎/逻辑/展现…）**脆弱，off-by-one 会级联**——帧标签相关功能**默认只读提取**，写回须帧数不变量校验。

---

## 4. 能力域与素材师痛点（已基于仓库证据）

### 能力① AN 维护（独立运行，Animate 关闭时）
装/更新/删插件 SWF、清缓存、改 `jvm.ini` 内存、收侧边、打开 WindowSWF/Commands、复制机器诊断信息、SharedObject 诊断。**减去全部激活/联网**。

### 能力② `.sol` / AMF 读写（纯库 + GUI/CLI）
通用 Flash SharedObject 编解码（AMF0 envelope：TCSO 头 + 名称 + element list → 类型化 JSON 树）。GUI 树编辑 + CLI headless + 被 `cf7-save-repair` 直接 import。

### 能力③ 创作提速面板（Animate 内 CEP + JSFL）

| 痛点 | 证据 | 自动化 | 价值 |
|---|---|---|---|
| 选中库符号 → 批量导出 PNG/spritesheet + 元数据 | 现靠 `export-*.py/ps1` + FFDec，改 FLA 后手跑、手查 sprite ID | 面板一键 `SpriteSheetExporter`/`exportPNG`，自动算 size/anchor/帧数 | 高 |
| 批量设置/规范 `linkageIdentifier` | 导出依赖 linkage 唯一且 = 文件名，现逐符号手设 | 扫库列出缺失 linkage，按文件夹约定批量赋值、查重 | 高 |
| 重复符号检测与合并 | `xfl_duplicate_detector` 离线跑、手改 XML | 面板实时聚类 → 一键合并（并引用 + 删冗余）+ 日志 | 高 |
| 发布前规范校验（linter） | 现有 audit 脚本都是事后 | 实时检查 linkage 唯一/命名约定/帧数/缺档，发布前告警 | 高 |
| 帧标签 ↔ 动画数据 JSON 往返 | `asLoader.xml` 加载器，帧标签与数据 XML 手工同步 | 提取帧标签/关键帧元数据 → 生成动画 JSON（**默认只读**） | 高 |
| 配色/调色板批量应用 | `色彩预设xml生成器`/`高级色彩引擎` 手工逐个试 | 载入预设 → 批量应用 + 实时预览 + 导出变体 | 中 |
| 头像 PNG 归一化 44×44 | `crop-nonsquare-avatars.ps1` 手工逐文件 | 发布钩子或批处理：alpha-bbox 裁剪 + resize | 中 |
| 碰撞盒/源元数据生成 | `碰撞箱生成工具`、`export-map-avatar` 元数据手推 | 选符号 → 生成 collision XML / size/crop 元数据旁车文件 | 中 |

---

## 5. 架构

### 5.1 运行时切分（关键）
```
                       ┌─────────────────────────── Animate 进程内 ───────────────────────────┐
                       │  packages/cep-panel  (React + CSInterface)   ←evalScript(JSON str)→   │
                       │  packages/jsfl-host  (JSFL，跑在 Animate tool VM，唯一碰 FLA DOM)      │
                       └──────────────────────────────────────────────────────────────────────┘
   ┌──────────── 独立进程（Animate 关闭时）────────────┐
   │  packages/web   (Electron + React，维护 + .sol cockpit)                      │
   │  packages/cli   (tsx headless，Agent/CI)                                       │
   │  packages/an-host (唯一碰真实机器：fs/registry/child_process)                  │
   └───────────────────────────────────────────────────────────────────────────────┘
                       ▲
                       │  全员唯一依赖
              packages/core  (纯 TS，零 I/O：AmfCodec / AnEnv / AuthoringModel；Zod + Vitest)
```

### 5.2 包清单（对齐 `cf7-balance-tool` workspaces 风格）

| 包 | 职责 | 依赖 | 栈 |
|---|---|---|---|
| `packages/core` | **纯逻辑、零 I/O**。三子域：`AmfCodec`（AMF0 读写 + SharedObject envelope → 类型化 JSON）、`AnEnv`（Animate 安装布局/路径解析、`jvm.ini`/侧边栏 .dat 变换、机器诊断格式化——只产出 plan/diff 不落盘）、`AuthoringModel`（linkage 规则、命名约定、44×44、帧标签/动画/spritesheet 元数据、查重聚类）。全部 Zod 校验。 | `zod` only | strict TS，`tsc -b` |
| `packages/an-host` | **唯一允许碰真实机器**：Animate 发现（扫 Program Files + 只读 `CSXS.N` 注册表）、CEP 扩展目录定位、WindowSWF 拷贝/删除、`jvm.ini`/侧边栏读改写（**backup-before-write**）、打开目录、机器诊断采集。是 core plan 的执行器。 | `core` | Node fs/os/child_process |
| `packages/cli` | headless `tsx` 入口（Agent/CI）。`sol read\|write\|diff`、`an doctor\|paths\|jvm\|sidebar\|cache\|install\|delete`、`art lint\|linkage-scan\|dup-scan\|frame-extract`（直解 XFL `DOMDocument.xml`，无需 Animate）。**plan-first，`--apply` 才落盘**，支持 `--json`。 | `core`,`an-host` | tsx + `fast-xml-parser` |
| `packages/web` | 独立 **Electron + React** cockpit（Animate 关闭时用）。Tab A=AN 维护（IPC→an-host）；Tab B=SOL 检视/编辑（core AmfCodec，树视图 + 改值 + backup 存盘，兼作 `cf7-save-repair` JSON 影子 GUI）。renderer 纯 UI，main 持有 fs/an-host。 | `core`,`an-host` | Electron 35 + React 19 + Vite 6，`launch.bat` |
| `packages/cep-panel` | **Animate 内唯一的现代 web 面板**。薄 React UI（CSXS manifest，host=FLPR，PlayerDebugMode 免签安装）。编排创作任务，经 `CSInterface.evalScript` 与 jsfl-host JSON 往返；可选 `--enable-nodejs --mixed-context` 触达 repo fs 写 atlas JSON。 | `core`,`jsfl-host` | CEP 11/12 + React 19 + Vite（`base:'./'`） |
| `packages/jsfl-host` | manifest `<ScriptPath>` 装载、跑在 **Animate JSFL VM**（非 TS、非浏览器）。注册命名函数，单 JSON 串入、JSON 串出、守 `'EvalScript error.'`：`exportSelectedSymbols`/`scanLibraryLinkage`/`applyLinkage`/`listFrameLabels`/`applyColorPreset`/`publishDoc`。**所有 Animate-DOM 耦合集中于此**，是 core 决策的"哑执行器"。收编现有 `publish.jsfl`/`removeParentChildRelationships.jsfl`。 | 无（VM 内） | JSFL（`fl.*`/`Document`/`Library`/`SymbolItem`/`SpriteSheetExporter`/`FLfile`） |

### 5.3 单一接缝原则
`core` 是唯一接缝：每条 `.sol` 值变换、每条路径/`jvm.ini`/侧边栏规则、每条 lint/linkage/元数据规则**只写一次**，被 CLI / Electron / CEP 面板**同构消费**。修一处即全端生效，且 Agent 可在无 Animate / 无 Electron 下 headless 回归。

---

## 6. 关键技术决策（已核实，2024–2026 现状）

### 6.1 现代 web inside Animate = CEP，不是 UXP
- **CEP HTML5 面板**：真 Chromium + 可选 Node.js；通过 `CSInterface.evalScript` 桥到 **JSFL**（Animate 的宿主脚本是 JSFL，host appName=`FLPR`，不是 ExtendScript）。是当下唯一"现代 web + Animate 内"路径。
- **UXP**：**Animate 暂不开放第三方 UXP**（仅 PS/ID/Premiere）。不依赖；仅为未来留迁移路（§8）。
- **遗留 AS3/SWF WindowSWF 面板**（醉尘仙所用）：基于 EOL Flash 运行时，明确**弃用**，仅作参考。

### 6.2 免签 in-repo 开发安装（团队 dev 推荐路径）
- `PlayerDebugMode=1`：Windows 注册表 `HKCU\Software\Adobe\CSXS.12`（同时覆盖 `CSXS.11`/`CSXS.10` 以兼容旧 Animate）；mac `defaults write com.adobe.CSXS.12 PlayerDebugMode 1`。脚本化 `.reg`/`.bat` 一次性下发。
- `.debug` 文件（XML，扩展根目录）：`<Extension Id>` 须与 `CSXS/manifest.xml` 一致，`<Host Name="FLPR" Port="8088"/>`。
- 扩展目录（跨 CEP 版本不变）：Win 用户级 `%APPDATA%\Adobe\CEP\extensions`；mac `~/Library/Application Support/Adobe/CEP/extensions`。
- 把 `cep-panel/dist` **符号链接**进扩展目录（或构建时 `robocopy /MIR`，避免 junction 删除级联）。

### 6.3 热重载 dev loop
- manifest `MainPath` 指向 `dist/index.html`（3 行 dev 跳转 stub → `http://localhost:5173`），Vite `server.host=true`、`base:'./'`。
- `.debug` 的 Port 即 CEF 远程调试端口：浏览器开 `http://localhost:8088` 拿到完整 Chrome DevTools。
- 改 UI → Vite HMR 即时刷新；**仅**改 manifest 或 jsfl-host 才需重启 Animate。

### 6.4 evalScript ↔ JSFL 桥（约定）
- 单参数：面板侧把 argObj **双重 JSON 编码**传一个字符串；host 侧 `JSON.parse` 入、`JSON.stringify` 出（跨界只活字符串）。
- host 函数经 manifest `<ScriptPath>` 预装载，面板按名调用；失败时 evalScript 返回字面量 `'EvalScript error.'`，必须守。
- Node-in-panel：manifest `RequiredRuntime CSXS 5.0+` + `CEFCommandLine` 加 `--enable-nodejs --mixed-context`；Vite 构建把 node 内建标记 external，避免 require 破裂。

### 6.5 `.sol`/AMF0 编解码 + 测试 oracle
- `core/AmfCodec` 纯 TS clean-room 实现 AMF0 + SharedObject envelope，依据**公开 AMF0 规范**。
- **oracle**：对 `amf0-help/sol_parser`（Rust `flash_lso`）与 `launcher/native/sol_parser` 的输出做**字节级 roundtrip 交叉校验**，fixture 用 `real_flash_v3.sol` + `probe_sols/*.sol`。
- 安全闸：写盘必 backup；GUI 改值带 diff 预览；**禁止游戏运行时写 `.sol`**（SOL 权威 + 自动存档会覆盖）。

### 6.6 交付给非开发素材师
- **默认路径 A**：免签 folder-copy + `PlayerDebugMode`（一次性脚本下发），与 dev 同一产物，更新即 `git pull` + 构建重拷。
- 可选路径 B：自签 ZXP（`ZXPSignCmd -selfSignedCert` + `-tsa` 时间戳）做"一键安装"门面——但自签仍常需开 `PlayerDebugMode`，仅作 polish，不是唯一安装路。

---

## 7. 清室排除清单（硬边界 / Code review 闸门）

逐条对照破解包，**以下一律不实现、不引用、不链接**：

1. **零联网**：无 `URLRequest/fetch/socket`，无任何 verify/version 端点，无遥测。全程离线（唯一"下载"是 `launch.bat` 取 Electron，属构建基建非工具功能）。
2. **无远程授权/在线复检**：不复刻 COMPLETE-listener verify。
3. **无 MAC 算号 / keygen**：零 `MD5(MAC+'FUCKYOU')`、零 consum_code mod-10 校验、零 recomm_code 推导。"复制机器信息"是人类可读诊断（OS/Animate 版本/路径），**显式不含 MAC 衍生激活种子**（core 加测试断言其不含任何 MAC token）。
4. **无 DRM `.sol` 伪造**：`AmfCodec` 是**游戏自身存档 + 通用 `.sol`** 的标准编解码；**不**合成醉尘仙的 `ZCXGZS` TCSO 四字段激活 blob，无"离线生成 .sol/一键激活"。
5. **无 hosts/DNS/防火墙改写**：不写 `0.0.0.0 pispik.com`，不 `ipconfig /flushdns`，不提权屏蔽。（与游戏自身 FlashTrust/loopback 处理无关，那是另一既有议题，不在本工具范围。）
6. **无版权争议代码**：clean-room。**不**抽取/反编译/复用 `醉尘仙AN插件..swf`、`Setup.pyc`/`Setup_source.py`、DoSWF 解包例程、`ZCX_Sol_Generator`、任何反编译 `MainTimeline.as`；无作者串、无 DoSWF 壳、无反 dump 填充。`tmp/zuichenxian-plugin-analysis/` 仅作黑盒行为说明引用，不 import 其一字节。

**一句话边界**：保留**合法、离线、本地的 AN 维护工具**与**通用 `.sol` 编解码技术**；丢弃一切触及联网/身份/授权/DRM `.sol`/hosts 的行，全部从零依公开 Adobe + AMF0 规范重写。

---

## 8. 可维护性 + UXP 迁移

三条纪律：
1. **core 纯且单接缝**：每条变换/规则只写一次、Zod 校验、Vitest 对真 fixture 覆盖，三端同构消费；修复落一处，Agent 可 headless 回归。
2. **脆弱宿主面薄而隔离**：`jsfl-host` 收 100% Animate-DOM 耦合，`an-host` 收 100% OS/注册表/fs 耦合，二者皆为 core plan 的哑执行器；Animate 改 JSFL 签名只补 `jsfl-host`，core 测试不动。
3. **CEP 面板是薄编排壳**（UI + JSON-over-evalScript，无业务逻辑），其不可避免的 churn 低风险。

**UXP 迁移路**：CEP 落日、UXP 主要影响 JSFL 脚本模型。因 JSFL 逻辑已隔离在 `jsfl-host`（命名函数注册表：名入、JSON 串出）、core 宿主无关，UXP 迁移是**局部两包替换**——换掉 `cep-panel` 壳、把 `jsfl-host` 命名函数重定向到 UXP DOM/batchPlay；core + 独立 Electron/CLI/SOL 栈不动。从 P0 起作为设计注记跟踪，不到 Adobe 强制不建。

---

## 9. 路线图（每阶段可独立交付）

| 阶段 | 目标 | 交付物 |
|---|---|---|
| **P0** | 脚手架 + clean-room `.sol` 编解码（最高复用、零 Animate 依赖） | monorepo（workspaces、照搬 `tsconfig.base.json`、`project.json`→相对游戏数据、本 DevSpec + `docs/`）；`core/AmfCodec`（AMF0 读写 + envelope，Zod 树）；Vitest oracle：`real_flash_v3.sol` 字节级 roundtrip，对 Rust `flash_lso` 输出交叉校验；`cli sol read\|write\|diff`。**可交付：今天就能给 `cf7-save-repair` 用的 `.sol` 库 + CLI**。 |
| **P1** | AN 维护：纯逻辑 + headless apply（能力①，去激活/联网） | `core/AnEnv`（路径/CSXS.N/`jvm.ini`/侧边栏/机器诊断，纯，产 plan/diff）；`an-host` 执行器（backup-before-write、装/删 WindowSWF、清缓存、`jvm.ini`、侧边栏、开目录、机器诊断）；`cli an doctor\|paths\|jvm\|sidebar\|cache\|install\|delete`（plan-first，`--apply`）。**可交付：Agent/CI 全 headless 维护**。 |
| **P2** | 独立 Electron cockpit（能力①+②，人用 GUI，Animate 关闭时） | `packages/web`：Electron 35 + React 19 + Vite + `launch.bat`（npmmirror 下 Electron + esbuild main.cjs）；Tab A=AN 维护（IPC→an-host），Tab B=SOL 检视/编辑（core AmfCodec，树 + 改 + backup）。**可交付：双击 GUI 日常驱动**。 |
| **P3** | headless 创作切片 + JSFL host 收编（能力③地基，无面板可证） | `core/AuthoringModel`（linkage/命名/44×44/查重聚类/帧元数据 schema）；`cli art lint\|linkage-scan\|dup-scan\|frame-extract`（直解 XFL）；`packages/jsfl-host`（收编 `publish.jsfl`/`removeParentChildRelationships.jsfl` + 新命名函数，Commands 菜单手测）。**可交付：无 Animate 也能 lint/查重 XFL**。 |
| **P4** | CEP 面板 MVP（能力③，提速正餐） | `packages/cep-panel`：CSXS manifest（FLPR、CSXS.11/12）、免签 folder-copy + PlayerDebugMode 安装配方 + `.reg`/`.bat` 下发、Vite dev-server + redirect-stub + 远程 DevTools loop；React UI 经 evalScript 驱动 jsfl-host。MVP：选中符号批量 spritesheet/PNG 导出、linkage 扫描+批量赋值、发布前 linter。**可交付：替代手工逐符号导出/linkage 的真面板**。 |
| **P5** | 创作提速纵深 + 打包 polish | 面板：重复符号聚类复审+合并、帧标签↔动画 JSON 往返编辑器、配色预设应用；可选自签 ZXP 构建路；DocAudit + `operation-manual.md`。**可交付：三能力域完整 + 一键式安装选项 + 文档治理完成**。 |
| **P6**（延后/条件） | UXP 迁移就绪（团队 Animate 真离开 CEP 时才做） | 把 `jsfl-host` 命名函数注册表重定向到 UXP batchPlay/DOM；换 `cep-panel` 壳为 UXP 插件；core+an-host+web+cli 不动。 |

---

## 10. 风险登记

| 风险 | 缓解 |
|---|---|
| CEP 落日 → UXP | 面板薄、JSFL 逻辑隔离于 jsfl-host；P6 为局部两包替换，core/cli/web 不动；不过度投资 CEP-specific UI。 |
| Animate 2024+ 面板白屏 / PlayerDebugMode 回归 | 默认 folder-copy + PlayerDebugMode（覆盖 CSXS.10/11/12，脚本化）；文档写 run-as-admin 与白屏急救；ZXP 仅 polish；上批处理前在实际 Animate 构建 smoke-test。 |
| Apple Silicon/macOS 差异 | 独立 Electron/CLI/SOL 栈跨平台不受影响；仅面板 OS 敏感；团队以 Windows 为主（仓库即 Win），mac best-effort + doctor 闸。 |
| ZXP 签名摩擦 | folder-copy 为支持路径；ZXP 标注"可选、自签仍可能需 debug 标志"；`-tsa` 时间戳防签名过期。 |
| JSFL API 跨版本漂移（CS6 vs 2021+ vs 2024） | 所有 DOM 耦合关进 jsfl-host；P3 加能力探针 smoke-test 各命名函数，doctor 暴露不支持项；签名不臆断、对实装版本验证。 |
| AMF0 编解码正确性（存档损坏=数据丢失） | 对真 fixture + Rust 解析器字节级 oracle 测试；web/cli 永远 backup-before-write；GUI 改值带 diff 预览；游戏运行时禁写。 |
| asLoader/AS2 帧标签 off-by-one 级联 | 帧标签↔JSON 默认**只读提取**；写回 plan-first + 帧数不变量校验；不自动改 asLoader 时间轴。 |
| 清室污染（误用反编译代码） | DevSpec 硬排除清单；禁 import `tmp/zuichenxian-plugin-analysis`；无作者串；逐文件依公开规范重写；本边界设 code review 闸。 |
| DRM 邻近功能蠕变（"复制机器信息"漂向算号） | 机器信息为 core/AnEnv 固定人类可读格式化 + 测试断言不含 MAC token；API 全程无激活面。 |

---

## 11. 待决问题 / 下一步

**待 owner 拍板**
1. 工具名 `cf7-animate-kit` / `CF7-AnimateKit` 是否采用？（可改。）
2. 路线图起点：建议直接进 **P0**（`.sol` 编解码库即时可用、零 Animate 依赖、最高复用），还是先做 **能力③ 面板 MVP**（素材师感知最强）？两者解耦，可任选其一先行。
3. 能力③ MVP 功能优先级：默认取"批量导出 + linkage 批量赋值 + 发布前 linter"三项最高价值。是否调整？
4. `.sol` 编解码是否就直接立项替换 `cf7-save-repair` 的 JSON 影子读法（即让其改读真 SOL）？还是先做独立库、后续再切？

**下一步（owner 批准本规格后）**
- 进入 **P0**：建 `tools/cf7-animate-kit/` workspaces 骨架（照搬 balance-tool 配置）、写 `packages/core/AmfCodec` + Vitest oracle、`cli sol`，并补 `docs/source-audit.md`（黑盒审计存档）与 `docs/clean-room-boundary.md`（§7 提炼为 review checklist）。

---
*本规格为设计草案，未写任何实现代码；不引用、不复用破解包任何一行。*
