# cf7-animate-kit 操作手册

纯离线、入库的 Adobe Animate 生产力工具。本手册覆盖三能力域的日常用法。
设计/边界见 [../CF7-AnimateKit-DevSpec-v1.md](../CF7-AnimateKit-DevSpec-v1.md) 与 [clean-room-boundary.md](clean-room-boundary.md)。

## 0. 一次性准备

```bash
cd tools/cf7-animate-kit
npm install                 # 轻量；Electron 二进制不在此下载（由 web/launch.bat 运行时下）
npm run typecheck           # tsc -b（core/an-host/cli）
npm test                    # vitest：.sol 编解码字节级+金标 / AnEnv / 维护 / XFL
```

## 1. 能力① AN 维护（CLI，独立运行，建议 Animate 关闭时）

全部 **plan-first**：不带 `--apply` 只打印计划，加 `--apply` 才落盘（覆盖前自动 `.bak-*` 备份）。

```bash
npm run an -- doctor                         # 发现 Animate 安装 + SharedObjects（机器诊断，无任何硬件 id）
npm run an -- paths                          # 各安装的 WindowSWF/Commands/jvm.ini/cache 路径
npm run an -- jvm 1024                        # 预览把 -Xmx 设为 1024m（-Xms 自动取一半）
npm run an -- jvm 1024 --apply               # 应用（备份原 jvm.ini）
npm run an -- cache                          # 预览清 WindowSWF tmp 缓存
npm run an -- cache --apply
npm run an -- install <plugin.swf> --apply   # 装插件 SWF 到所有 WindowSWF（覆盖前备份）
npm run an -- delete "myplugin*.swf" --apply # 通配删除（备份）
npm run an -- sidebar <fl_dictionary_*.dat> --apply   # 收侧边
npm run an -- open windowswf                 # 在资源管理器打开目录（commands 同理）
```

> ⚠️ 本域**不含**任何联网/算号/激活/改 hosts。`doctor` 的"机器信息"是纯诊断，无 MAC/卷序列号。

## 2. 能力② `.sol` / AMF0 编解码（CLI + 库）

```bash
npm run sol -- info <file.sol>               # 名称/AMF 版本/元素数/顶层键
npm run sol -- read <file.sol>               # JSON 投影（与 Rust flash_lso 金标一致）
npm run sol -- read <file.sol> --ast         # 无损 AST（用于精确编辑/写回）
npm run sol -- diff <a.sol> <b.sol>          # 两存档 JSON 投影的结构差异
npm run sol -- from-json <data.json> <out.sol> --name crazyflasher7_saves   # 从 JSON 造 .sol
```

作为库被本仓其它工具（如 `cf7-save-repair`）复用：

```ts
import { readSol, writeSol, parseSolToJson } from '@cf7-animate-kit/core';
const sol = readSol(buf);          // 无损 AST
const json = parseSolToJson(buf);  // = 游戏 C# 启动器消费的同款 JSON
const bytes = writeSol(sol);       // 字节级还原（已对真存档 + 6 个探针 fixture 验证）
```

> ⚠️ **SOL 是存档权威**，游戏运行时自动存档会 SOL→JSON 覆盖。写 `.sol` 前必备份、且**禁止游戏运行时写**。
> GUI（见 §4）的 SOL 编辑只改基本类型叶子并保留其余 AST 以保字节忠实，带 diff 预览 + 自动备份。

## 3. 能力③ 创作提速 — headless 切片（CLI，无需 Animate）

```bash
npm run art -- linkage-scan <DOMDocument.xml>     # 列出带 AS linkage 的符号/媒体
npm run art -- lint <DOMDocument.xml>             # linkage 校验（重复 id/导出无 id），有 error 退出码 2
npm run art -- dup-scan <xflDir>                  # LIBRARY 下精确结构重复符号聚类（忽略名/itemID）
npm run art -- frame-extract <DOMDocument.xml|symbol.xml>   # 提取命名帧标签
```

> 已对真实 `flashswf/arts/new/*`（如 1568 符号的工程）验证解析。

### 3.5 无人值守 JSFL runner（驱动真 CS6 / Animate，复用仓库编译链思路）

把 `jsfl-host` 变成 agent/CI 可驱动：写 job → 触发 Animate 跑 `cf7ak-runner.jsfl` → 轮询 marker + **校验新鲜产物** → 读回 JSON。
照搬 `scripts/compile_action.jsfl` + `compile_test.ps1` 的纪律（marker 不单独算成功、`-TimeoutSeconds` 适配慢机）。
**这也是 CS6 的原生提速路径**——CS6 装不了 CEP 面板，但能跑 JSFL。

```bash
# 0) 先生成自包含 runner（host + runner-main 合并）
npm run build -w @cf7-animate-kit/jsfl-host        # 产出 packages/jsfl-host/host/cf7ak-runner.jsfl

# 1a) 直启方式（最简；若该 exe 带 RUNASADMIN 可能弹 UAC）
npm run art -- run probe --exe "C:\Program Files\Adobe\Adobe Animate 2024\Animate.exe"
npm run art -- run scanLinkage --exe "<Animate.exe>" --timeout 60
npm run art -- run exportSelected --args '{"outDir":"C:/temp/out"}' --exe "<Animate.exe>"

# 1b) 计划任务方式（躲 UAC，对标 CompileTriggerTask）
npm run art -- setup-task --exe "<Animate.exe>"    # 生成 register-animatekit-task.ps1
#   以管理员跑一次该 .ps1（Register-ScheduledTask RunLevel=Highest）
npm run art -- run probe --task AnimateKitJsflTask
```

job/result 文件落在被发现 Animate 的 `Configuration/Commands/cf7ak/`（两侧约定同一路径，无需额外 cfg）。
返回 `{ok,data|error,timedOut}`；编排逻辑已用 stub trigger 做 tmpdir 单测（无需真 Animate）。
真机首次用前，仍按 `packages/jsfl-host/README.md` 核对 `SpriteSheetExporter` 等签名。

## 4. 能力①② GUI — Electron cockpit（`packages/web`，Animate 关闭时）

```bash
cd tools/cf7-animate-kit/packages/web
./launch.bat          # Windows：装依赖→建 core/an-host/web→下 Electron 到 %TEMP%→启动
```

- **Tab A 维护**：doctor 发现、装插件、jvm 内存、清缓存、收侧边、开目录（均 plan→Apply）。
- **Tab B SOL 检视/编辑**：打开 `.sol`→折叠树→改基本类型叶子→diff 预览→保存（自动备份）。

> 需在 Windows + 已装 Animate 的机器上人工 smoke-test（GUI 行为无法 headless 验证）。

## 5. 能力③ GUI — CEP 面板（`packages/cep-panel`，Animate 内）

**开发安装（免签）：**
```bash
cd tools/cf7-animate-kit/packages/cep-panel
install/enable-debug.bat        # 设 HKCU\Software\Adobe\CSXS.10/11/12 PlayerDebugMode=1（一次性）
npm run build                   # 产出自包含扩展 dist/（含 CSXS/manifest.xml + host/index.jsfl）
install/install-dev.bat         # 把 dist/ 符号链到 %APPDATA%\Adobe\CEP\extensions\com.cf7.animatekit.panel
# 重开 Animate → 窗口 → 扩展 → CF7 AnimateKit
```

> 面板**已在真机 Animate 2024 验证可用**。构建/安装/调试的完整踩坑手册见 [DEVELOPMENT.md](DEVELOPMENT.md) §5(白屏修复=singlefile 内联、node:path stub、ScriptPath 热加载、CDP/DevTools 验证、scratch 档安全测试)。

**面板功能**（经 `CSInterface.evalScript` 调 `jsfl-host`，6 标签）：
- **Doctor** 能力条 · **Linkage**(扫描+批量赋值) · **Export**(选中符号→spritesheet) · **Frame labels**
- **Advanced**：输出预览图/帧序列/批量符号导出/库图片/库音频/安全保存/打开存档
- **库/帧/滤镜**：批量改名·删除·文件夹·移动 / 加删帧·反向·转关键帧·清关键帧 / 发光·阴影·模糊·清滤镜
- **预设/位图/诊断**：预设存取应用(可复用任意操作) / 位图转矢量·压缩 / 崩溃诊断

全部函数 args/返回/置信度见 [packages/jsfl-host/README.md](../packages/jsfl-host/README.md)。

**热重载开发：** UI 改动 `npm run dev`(Vite :5173)+ 远程 DevTools 里 `localStorage.setItem('cf7ak-dev','1')` 后重载面板;**改 `host/index.jsfl` 用 `eval(FLfile.read(host))` 热加载免重启**(见 DEVELOPMENT.md §5.2)。

> ⚠️ `SpriteSheetExporter`/`BitmapItem` 等少数 JSFL 签名因 Animate 版本而异,新版本上批量用前先核对。

**打包发布给非开发素材师（可选）：** 见 `packages/cep-panel/scripts/sign-zxp.md`（自签 ZXP；自签仍常需开 PlayerDebugMode，仅作"一键安装"门面）。

## 6. 常见问题

- 面板白屏 / 不出现：确认 PlayerDebugMode 对该 Animate 的 CSXS.N 命名空间已设；试以管理员运行 Animate；查 `http://localhost:8088` DevTools 控制台。
- `EvalScript error.`：JSFL 抛错；用 `jsfl-host` README 的 Commands 手测法定位是哪个函数/签名。
- jvm/sidebar 改完没生效：确认改的是 `an doctor` 列出的那个 Configuration（多版本 Animate 各有一份）。
