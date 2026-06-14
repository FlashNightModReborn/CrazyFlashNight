# cf7-animate-kit 开发 / 交接总览

> 后续回来开发(你或 Flash-Night)从这份开始读。看完这一篇 + [函数参考](../packages/jsfl-host/README.md) 就能上手。
> 设计动机/审计见 [CF7-AnimateKit-DevSpec-v1.md](../CF7-AnimateKit-DevSpec-v1.md);边界见 [clean-room-boundary.md](clean-room-boundary.md);日常用法见 [operation-manual.md](operation-manual.md)。

---

## 0. 一句话

干净、纯离线、入库的 Adobe Animate 生产力工具。参考(被破解的)商业插件"醉尘仙 AN 插件"的**功能**,但**剥离全部联网/算号/激活/改 hosts/DRM**,用现代 web(CEP+JSFL,非 AS3)从零重写。已在真机 Animate 2024 验证可用,面板 6 个标签页 / ~33 个 JSFL 函数。

**清室红线**:不抄破解包任何一行实现;`tmp/zuichenxian-plugin-analysis/` 只当黑盒行为说明。任何 PR 对照 [clean-room-boundary.md](clean-room-boundary.md)。

---

## 1. 仓库结构(monorepo / npm workspaces)

```
tools/cf7-animate-kit/
  package.json            workspaces 根;脚本 sol/an/art 走 tsx --conditions=development
  tsconfig.base.json      严格 TS(ES2022/NodeNext/exactOptionalPropertyTypes/noUncheckedIndexedAccess/verbatimModuleSyntax)
  launch.bat / launch.sh  一键启动 web cockpit(顶层入口)
  packages/
    core/        纯 TS,零 I/O,单一接缝。子域:amf(.sol/AMF0 编解码)/ an(Animate 路径+jvm/侧边栏变换)/ authoring(XFL 解析+lint)
    an-host/     唯一碰真实机器:fs/注册表(只读)/child_process;Animate 发现、维护执行、JSFL runner 编排
    cli/         headless 命令 sol / an / art(Agent/CI 友好)
    web/         Electron + React cockpit(Animate 关闭时用:AN 维护 + SOL 检视/编辑)
    cep-panel/   Animate 内 CEP 面板(创作提速 UI;唯一跑在 Animate 里的 web)
    jsfl-host/   JSFL 宿主脚本(唯一碰 FLA DOM);cf7ak() dispatcher + ~33 命名函数;build 合并成 cf7ak-runner.jsfl
  docs/          本目录(DEVELOPMENT/operation-manual/source-audit/clean-room-boundary)
```

依赖方向:`core` 被所有人依赖;`an-host`→core;`cli`→core+an-host;`web`→core+an-host;`cep-panel`→core(仅 authoring)+jsfl-host(构建期拷 host)。

---

## 2. 架构要点

- **单一接缝 = core**:每条纯逻辑(.sol 值变换、路径/jvm 规则、lint/查重)只写一次,CLI/Electron/面板同构消费。
- **运行时切分**:
  - **Animate 内**:`cep-panel`(React UI)+ `jsfl-host`(JSFL,碰文档 DOM)。面板经 `CSInterface.evalScript` 调 `cf7ak(fn, argJson)`。
  - **独立(Animate 关闭)**:`web`(Electron)+ `an-host`(碰 OS)+ `cli`。
- **桥契约**:面板 `bridge.ts` 的 `callHost(fn, argObj)` → 双重编码 argObj 为 JSON 字符串 → `evalScript("cf7ak('fn', <jsonstr>)")` → host `JSON.parse` 入、返回 JSON 字符串 `{ok,data}|{ok:false,error}`;失败时 evalScript 返回字面量 `'EvalScript error.'`,必须守。
- **现代 web 落点**:Animate 内只有 **CEP**(Chromium+Node)可用;**UXP 不对 Animate 第三方开放**,不依赖。

---

## 3. 环境 & 通用开发循环

```bash
cd tools/cf7-animate-kit
npm install                 # 轻量(Electron 二进制不在此下)
npm run typecheck           # tsc -b(core/an-host/cli)
npm test                    # vitest 全绿基线(.sol 字节级+Rust 金标 / AnEnv / 维护 / XFL / runner)
```

CLI(Agent/CI):`npm run sol -- read x.sol --json` · `npm run an -- doctor` · `npm run art -- lint dom.xml`。
`sol`/`an`/`art` 通过 `tsx --conditions=development` 直读 core 源码,无需先 build。

---

## 4. web cockpit(Electron)开发循环

```bash
# 一键(顶层):
launch.bat          # Windows;或 ./launch.sh(mac/Linux)
```
launch.bat:首次 `npm install`→build core+an-host+web→定位/下载 Electron→`start electron main.cjs`。

**踩坑(已修,别再犯)**:
- **`.bat` 必须 CRLF 换行**。Write/Edit 工具默认写 LF,cmd.exe 用 LF 会让 `goto :label` 失效→脚本中途闪退(无报错)。已加 `.gitattributes`(`*.bat/*.reg/*.ps1 eol=crlf`)锁死;**新建任何 .bat/.reg 后务必转 CRLF**。
- **Electron 下载卡死**:`launch.bat` 已加"复用 sibling cf7-packer 的同版本 Electron"(查 `../cf7-packer/node_modules/electron/dist/version`==35.7.5),命中就不重下 280MB。缓存在 `%TEMP%\cf7-electron-v35.7.5\`(两工具共享)。

仅 typecheck/build(不起 GUI):`npm run typecheck -w @cf7-animate-kit/web` / `npm run build -w @cf7-animate-kit/web`。

---

## 5. ⭐ CEP 面板开发循环 + 踩坑手册(最重要)

这是整个项目最难、最值得记的一段。面板能跑起来是踩平了下面所有坑换来的。

### 5.1 构建 + 安装(开发免签)

```bash
npm run build -w @cf7-animate-kit/jsfl-host   # 先生成 host/cf7ak-runner.jsfl(也会被 panel 拷)
npm run build -w @cf7-animate-kit/cep-panel   # vite(singlefile 内联)+ copy-assets(host/ + CSXS/ + .debug 进 dist)
# 安装到真机 Animate(免签):
#   1) PlayerDebugMode=1 写 HKCU\Software\Adobe\CSXS.10/11/12(Animate 2024=CSXS.12;10/11 兜底)
#   2) 把 dist/ 拷/软链到 %APPDATA%\Adobe\CEP\extensions\com.cf7.animatekit.panel
#   见 packages/cep-panel/install/enable-debug.* + install-dev.bat
# 重启 Animate → 窗口 → 扩展 → CF7 AnimateKit
```

### 5.2 五个致命坑(都已修,改动别回退)

1. **白屏 = CEF 拒载外部 `type="module"` 脚本**。Vite 默认产出 `<script type=module src=./assets/x.js>`,CEF 从 `file://` 加载 module 脚本会强制 MIME 校验,file:// 没 MIME → `Failed to load module script` → React 没挂载 → 白屏。
   **修法**:`vite-plugin-singlefile` 把 JS/CSS **内联进 index.html**(内联脚本不走网络、无 MIME 校验)。见 `cep-panel/vite.config.ts` 的 `viteSingleFile()`。**别改回外部 chunk**。
2. **`node:path` 裸 import 崩 CEF**。core 的 barrel `export * as anEnv` 把 `node:path` 拖进面板包(`sideEffects:false` 也 tree-shake 不掉)。面板根本不调 anEnv,但裸 `node:path` 在 CEF 里解析失败。
   **修法**:`cep-panel/vite.config.ts` 把 `node:path` alias 成 `src/lib/node-path-stub.ts`(死代码 stub)。
3. **dev 跳转探针刷红**:旧 index.html 用同步 XHR 探 `.cf7ak-dev` → file:// 404 噪声。已删,只留 localStorage 开关(`localStorage['cf7ak-dev']='1'` 才跳 Vite dev server)。
4. **ScriptPath 的 JSFL 改了不立即生效**。manifest `<ScriptPath>host/index.jsfl` 在**面板初始化时**载入 JSFL tool VM,改了 host 要重载面板/重启 Animate 才更新。
   **热加载技巧**(开发期免重启):在 JSFL tool VM 里 `eval(FLfile.read('<装好的 host index.jsfl 的 file:// uri>'))` —— 它会在共享 VM 里重定义全部函数(含 dispatcher cf7ak),**立即生效**。面板的 evalScript 和你 CDP 的 evalScript 是同一个 VM,所以热加载后面板也用上新函数。
5. **`.bat`/`.reg` 的 CRLF**(同 §4):install 脚本同样要 CRLF。

### 5.3 远程调试 + 无人值守验证(.debug 端口 8088)

`.debug` 文件给面板开了 CEF 远程调试端口 **8088**。两种用法:
- **人**:浏览器开 `http://localhost:8088` → 完整 Chrome DevTools(看 Console 报错最快定位白屏)。
- **Agent(本仓沉淀的关键手段)**:Node 20 没有全局 WebSocket、`ws` 包也没装,所以用 **PowerShell 的 .NET `System.Net.WebSockets.ClientWebSocket`** 连 CDP(`ws://localhost:8088/devtools/page/<id>`,先 `GET /json` 拿 id)。能:
  - `Runtime.evaluate`(`awaitPromise=true`)在面板里跑 JS、调 `window.__adobe_cep__.evalScript(...)` 测桥;
  - `Page.reload` / `Page.captureScreenshot`(无人值守截图);
  - `Log.entryAdded`/`Runtime.exceptionThrown` 抓加载期报错(白屏就是这么实锤的)。

  > PowerShell 5.1 收 WS 帧要用"单个 pending 接收 + Wait(timeout)"模式,别每轮新开 ReceiveAsync(会重叠抛异常);大消息(截图 base64)要累积到 `EndOfMessage`。本仓很多验证命令都是这套。

### 5.4 ⭐ 安全的真机测试法(绝不碰用户开着的 FLA)

- **只读函数**(listLibrary/crashDiagnostics/scan*):可直接在用户 live 档上经 CDP 调,安全。
- **破坏性函数**(改名/删除/加删帧/滤镜/trace/compression):**造废档测**——`var d=fl.createDocument(); /* addNewItem/importFile 造素材 */ cf7ak('...'); fl.closeDocument(d,false);`(不保存丢弃)。废档是当前活动文档,函数作用其上;关掉后用户的 FLA 复位。本仓 `c:/tmp/cf7ak-*-test.jsfl` 就是这种 scratch 测试脚本。

---

## 6. ⭐ 怎么加一个新 cf7ak 函数(每波都按这个套路)

1. **JSFL**:`packages/jsfl-host/host/index.jsfl` 加 `function cf7akXxx(args){ ... return cf7akOk({...})/cf7akErr(...) }`(ES3:只 var,无 const/let/arrow;先 `fl.getDocumentDOM()` 守空;per-item try/catch 不抛出),并在 `cf7ak()` dispatcher switch 加 `case 'xxx': return cf7akXxx(args);`。
2. `npm run build -w @cf7-animate-kit/jsfl-host` → 重生成 `host/cf7ak-runner.jsfl`(headless runner 用)。
3. **桥**:`packages/cep-panel/src/bridge.ts` 加 HostFnMap 条目 + arg/data 类型 + `host.xxx` wrapper(照现有 publish/listFrameLabels 抄)。
4. **面板 UI**:在某个 tab(或新建)加按钮/输入,调 `host.xxx(args)`,结果用 ResultChips/status 展示。破坏性操作加 confirm 门。
5. `npm run build -w @cf7-animate-kit/cep-panel`(singlefile)→ 重新部署 dist 到 extensions 目录。
6. **验证**:CDP 热加载 host(§5.2 技巧)→ `typeof cf7akXxx`==='function' → scratch 档或 live(只读)实测 → 截图。
7. 在 `packages/jsfl-host/README.md` 的对应表加一行(名/args/返回/confidence)。

> headless 路径:`npm run art -- run xxx --exe "<Animate.exe>"`(或 `--task`)。CS6 装不了 CEP 面板,runner 是 CS6 的原生提速路径。见 jsfl-host README「Headless runner」。

---

## 7. 现状(已建 / 已验证)

面板 6 标签 + ~33 JSFL 函数,全部在真机 Animate 2024 验证过(只读用 live、破坏性用 scratch):

| 标签 | 函数 | 醉尘仙对应 |
|---|---|---|
| Linkage | scanLinkage / applyLinkage | linkage 治理 |
| Export | exportSelected(spritesheet) | 批量导出 |
| Frame labels | listFrameLabels | 帧标签 |
| Advanced | exportStagePNG / exportFrameSequence / batchExportSymbols / exportLibraryBitmaps / exportLibrarySounds(实验) / safeSave / openDocument | 输出预览图/动态图(序列)/库图片/库音频/安全保存/打开存档/批量预览图/拆分到文件 |
| 库/帧/滤镜 | libBatchRename/libNewFolder/libMoveToFolder/libDeleteItems · framesInsert/Remove/Reverse/ConvertToKeyframes/ClearKeyframes · applyFilter/clearFilters | 批量改名/库清理/文件夹 · 批量加删帧/反向循环/转关键帧 · 一键发光阴影模糊 |
| 预设/位图/诊断 | presetSave/List/Apply/Delete · bitmapTrace/bitmapSetCompression · crashDiagnostics | 预设系统 · 位图转矢量/图片压缩 · 崩溃诊断 |

> 另有 3 个底层/工具函数不在标签表里:`ping`(健康检查)、`probe`(Doctor 条用,回 flVersion + 能力位)、`publish`(发布当前文档,`document.publish`)。**dispatcher 共 33 个 case**(7 工具/发现 + wave1 8 + wave2 11 + wave3 7),逐个见 [jsfl-host README](../packages/jsfl-host/README.md)。

非面板交付:`core` .sol/AMF0 编解码(字节级+Rust 金标双 oracle 测过,反哺 cf7-save-repair)、`an-host` AN 维护、`web` cockpit(已真机跑通+截图)、headless `art run` JSFL runner。

完整函数 args/返回/confidence:见 [packages/jsfl-host/README.md](../packages/jsfl-host/README.md)。

---

## 8. 路线 / 已延后(及原因)

- **已延后,且 owner 判定对 CF7 无用**:醉尘仙的 `一键运镜`(摄像机层+补间+缓动)、`一键表情/动作`(姿势库)、`走路/跑步循环`(动画模板)。设计量大、吃具体角色绑定结构、未必合 CF7 风格。**不做**(owner 2026-06-13 拍板)。
- **技术性延后(JSFL 难/不确定)**:真 GIF 合成(JSFL 无原生导出;已出 PNG 序列做前置)、导出到AE、音画同步、导出音轨、快捷键导入导出、SoundItem 音频再导出(`exportLibrarySounds` 多数版本不支持,逐项报告不崩)。
- **可维护性 / 未来 UXP**:JSFL 逻辑全在 `jsfl-host`(命名函数 + dispatcher),core 宿主无关。将来 Animate 开放 UXP,迁移≈换 `cep-panel` 壳 + 把命名函数重定向到 UXP API,core/cli/web/an-host 不动。

---

## 9. 故障速查

| 现象 | 多半是 | 处理 |
|---|---|---|
| CEP 面板白屏(标题在、内容空) | 外部 module 被 CEF MIME 拒载 / JS 抛错 | `http://localhost:8088` DevTools 看 Console;确认 vite singlefile 没被关 |
| `EvalScript error.`(桥返回) | JSFL 抛错 | 按 jsfl-host README 在 Commands 手测该函数;或 CDP 直接 `cf7ak('fn','args')` 看返回 |
| 改了 host 函数面板还报 unknown function | ScriptPath JSFL 未重载 | §5.2 热加载 `eval(FLfile.read(host))` 或重启 Animate |
| 双击 `.bat` 闪退、无报错 | LF 换行,cmd 要 CRLF | 转 CRLF(`.gitattributes` 已锁,新文件仍要转) |
| Electron 下载卡死 | 网络;残缺 zip | 已复用 sibling cf7-packer 的 Electron;或手动下到 `%TEMP%\cf7-electron-v35.7.5\dist` |
| 面板菜单里找不到 CF7 AnimateKit | PlayerDebugMode 没设 / Animate 没重启 / host 版本号不匹配 | 设 CSXS.10/11/12 PlayerDebugMode=1;查 manifest `<Host Name="FLPR" Version>` |

---

## 10. 清室边界(合入前必查)

禁:联网 / 远程校验 / MAC 算号 / DRM `.sol` 伪造 / 改 hosts / 复用 `tmp/zuichenxian-plugin-analysis` 反编译代码。
允许:本地离线维护、通用 `.sol` 编解码、XFL 解析、CEP+JSFL 文档自动化。守护测试见 `core/tests/an-env.test.ts`(断言无 MAC/激活码)。详 [clean-room-boundary.md](clean-room-boundary.md)。
