# cf7-animate-kit

干净、纯离线、入库的 Adobe Animate 生产力工具（CF7 项目专用）。

三能力域：
1. **AN 维护** — 装/删插件、清缓存、改 `jvm.ini` 内存、收侧边、开目录、机器诊断（独立运行，Animate 关闭时用）。
2. **`.sol` / AMF0 编解码** — 通用 Flash SharedObject 读写库，可被 `cf7-save-repair` 复用。
3. **创作提速面板** — Animate 内 CEP web 面板 + JSFL，自动化素材师重复劳动。

> ⚠️ **清室边界**：本工具**不含**任何联网、远程授权校验、MAC 算号、DRM `.sol` 伪造、改 hosts。
> 设计与边界详见 [CF7-AnimateKit-DevSpec-v1.md](CF7-AnimateKit-DevSpec-v1.md) 与 [docs/clean-room-boundary.md](docs/clean-room-boundary.md)。

## 包结构（monorepo / npm workspaces）

| 包 | 作用 | 运行时 |
|---|---|---|
| `packages/core` | 纯 TS 逻辑（零 I/O）：`AmfCodec` / `AnEnv` / `AuthoringModel` | 库 |
| `packages/an-host` | 唯一碰真实机器：fs / 注册表（只读）/ child_process | Node |
| `packages/cli` | headless 命令：`sol` / `an` / `art`（Agent/CI） | Node + tsx |
| `packages/web` | Electron + React cockpit（维护 + SOL 检视/编辑） | Electron（Animate 关闭时） |
| `packages/cep-panel` | Animate 内 CEP 面板（创作提速 UI） | CEP（Animate 内） |
| `packages/jsfl-host` | JSFL 宿主脚本（唯一碰 FLA DOM） | Animate JSFL VM |

## 快速开始

### GUI（推荐，一键）

首次运行自动安装依赖、按需构建、下载 Electron，无需手动操作（与 `cf7-packer` 同款体验）。

| 平台 | 启动方式 |
|------|---------|
| Windows | 双击 `launch.bat` |
| macOS / Linux | `chmod +x launch.sh && ./launch.sh` |

启动的是 **维护 + SOL 检视/编辑 cockpit**（Animate 关闭时用）。
Animate 内的 **CEP 创作面板**走自己的安装脚本：`packages/cep-panel/install/enable-debug.bat` + `install-dev.bat`（见 [docs/operation-manual.md](docs/operation-manual.md) §5）。

### CLI（Agent / CI）

```bash
cd tools/cf7-animate-kit
npm install
npm test                       # vitest（.sol 编解码字节级 + Rust 金标 JSON + 维护 + XFL + JSFL runner）
npm run typecheck              # tsc -b
npm run sol -- read <file.sol> --json
npm run an  -- doctor
npm run art -- lint <DOMDocument.xml>
npm run art -- run probe --exe "<Animate.exe>"   # 无人值守驱动 JSFL（见操作手册 §3.5）
```

## 文档

| 文档 | 内容 |
|---|---|
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | **开发/交接总览（先读这个）**：架构 · 开发循环 · CEP 踩坑手册 · 怎么加函数 · 故障速查 |
| [packages/jsfl-host/README.md](packages/jsfl-host/README.md) | 全部 ~33 个 cf7ak 函数的 args/返回/置信度参考 |
| [docs/operation-manual.md](docs/operation-manual.md) | 日常用法（CLI · web cockpit · CEP 面板安装与使用） |
| [CF7-AnimateKit-DevSpec-v1.md](CF7-AnimateKit-DevSpec-v1.md) | 设计动机 · 来源审计 · 施工状态(§0.5) · 路线图 |
| [docs/clean-room-boundary.md](docs/clean-room-boundary.md) | 清室红线 + review checklist |
| [docs/source-audit.md](docs/source-audit.md) | 醉尘仙破解包黑盒审计 |

## 状态（2026-06-13）

已在**真机 Animate 2024 验证可用**:CEP 面板 6 标签 / ~33 JSFL 函数(导出·库治理·帧·滤镜·预设·位图·诊断),wave1~3 逐个真机实测过。`core` `.sol`/AMF0 编解码字节级+Rust 金标双 oracle 全绿;`web` cockpit 已真机跑通。**纯离线、零 DRM**。延后:醉尘仙的运镜/表情/走路(对 CF7 无用)。详见 DevSpec §0.5 与 DEVELOPMENT.md。
