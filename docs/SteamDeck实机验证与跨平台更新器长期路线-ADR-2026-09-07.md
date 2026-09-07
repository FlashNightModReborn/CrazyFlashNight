# Steam Deck 实机验证与跨平台更新器长期路线

**文档角色**：SteamOS 安装探索的历史证据、当前阻塞与跨平台更新器长期方向；不是已交付安装器的使用说明。<br>
**最后核对代码基线**：commit `bcab5ac3dbcc32c3665dad1411f6158cd751b5b0`，用于归档时的仓库路由和职责核对；实测输入另由下文每日包哈希绑定，不以此 HEAD 冒充被执行产物。<br>
**状态**：长期方向已确认；公共更新器及平台适配层待实现。指定每日包已达到依赖安装、C# Host / Web 前门运行，Flash 连接仍超时，未完成游戏实机验收。<br>
**范围**：本轮落盘测试和讨论，不启动更新器施工，不设下一次每日包的时间承诺，不把 SteamOS 探索完成度加入通用 runtime promotion 门。

## 1. 目标与维护取舍

维护者希望以 Steam Deck 作为项目的长期实机基准之一，同时保留 Windows 开发机完成构建、资产生产与日常开发。掌机交互不适合反复安装和抄取日志，因此开发机上的 Agent 应通过 SSH 承担传输、安装、启动编排和证据回收。

现行每日包继续作为游戏更新输入。SteamOS 玩家占比较小，不因该平台额外把完整浏览器依赖塞进每个通用每日包。环境准备应首次完成并复用，游戏日更与依赖升级分开。

长期采用公共更新核心、Windows / SteamOS 平台适配层及版本化依赖清单。一个更新器支持多个游戏版本；每日包声明依赖，只有安装能力发生变化时才升级更新器本体。首轮先验证脚本 / CLI 核心，再按需要增加图形界面。

这项拆分集中管理平台安装差异，不能代替 Flash、Win32 窗口、输入、存档等运行态兼容修复。当前证据不足以要求整体重写 Guardian、替换 WebView2 或改变 AS2 / Flash 的资产权威。

## 2. 实测输入与部署方式

| 项目 | 本轮事实 |
|---|---|
| 输入 | `CF7_20260817.7z`，1,425,957,051 字节；配套 `安装更新.bat`、`7z.exe`、`7z.dll` |
| 压缩包 SHA-256 | `18ce3ffeecfca8759ad84961824886ce2f05ba2829882ce4dda14c1b73c7f951`，Windows / Deck 一致 |
| SteamOS | 3.8.16，build 20260716.1，x86_64 |
| Proton 10 | `1785139158 proton-10.0-4b` |
| Proton 11 | `1787334450 proton-11.0-2-x86_64` |
| 启动环境 | 两套均通过 Steam Linux Runtime sniper；测试时是桌面会话 |
| 已有工具 | OpenSSH、7-Zip、rsync、Flatpak Protontricks 1.12.1 |
| 原版游戏 | Steam AppID `2402310`，原版安装和原 Proton prefix 保留 |
| 测试隔离 | `/home/deck/cf7-test/20260817/`，运行文件在 `payload/`，两个 prefix 在 `compatdata/proton10` / `compatdata/proton11` |
| 安装语义 | 每日包解压后，使用原版底座填充缺失文件，已有每日包文件不被原版覆盖；与原版底座上覆盖更新的目标文件组合对齐 |
| 收尾 | 测试进程已停止，原游戏和原 `steamapps/compatdata/2402310` 未被本轮写入；隔离目录保留 |

以上是 2026-09-07 对 **2026-08-17 包**的历史测试，不是当前工作树或后续每日包的兼容性声明。掌机地址、SSH 私钥与个人连接配置不进入仓库，后续连接使用本机配置。

## 3. 已通过与未通过的边界

| 层次 | 证据 | 能陈述的结果 |
|---|---|---|
| 传输 / 解压 | 包哈希一致，7-Zip 正常解压 | 指定包成功送达并解包 |
| native bootstrap / runtime 文件 | 原生 `--verify-only` 通过；收尾重新校验 33/33 manifest 文件大小和 SHA-256 | 已检查部署文件完整性；不外推全部 Flash 资源引用均可读取 |
| .NET | 两个测试 prefix 的 Windows Desktop Runtime 10.0.8 安装器完成；Core 日志出现 `clr=.NET 10.0.8` | Windows 版 C# Core 确实在 Proton 中执行 |
| WebView2 | 官方离线安装器日志 `Installation complete, returning: 0`，游戏识别 152.0.4191.66 | 依赖安装及运行时发现成功 |
| Steam | `SteamAPI initialized`、`BIsSubscribedApp(2402310) = True` | 该隔离启动中所有权校验通过，没有绕过校验 |
| HTTP | 1192 端口启动；实际 POST `http://localhost:1192/testConnection` 返回 200 / `status=success` | 本地 HTTP 实际请求可用 |
| XMLSocket | 1924 端口 IPv4 / IPv6 loopback 监听 | 宿主服务启动，不代表 Flash 客户端已连接 |
| Web UI | WebView2 创建和导航完成，收到 JS `ready` / `list`，有真实前门截图 | 混合启动器前门已显示并执行脚本 |
| Flash 进程 / 窗口 | Flash Player 20 启动，窗口重设父窗口到隐藏宿主 | 进程及一部分 Win32 嵌入操作成功 |
| Flash 启动链 | 两个 Proton 版本重复出现约 10 秒的 `socket_connect_timeout` | 仍阻塞，未完成握手 / scene-ready / 关卡 |
| 玩家旅程 | 没有完整战斗、存读档、声音、手柄、睡眠恢复、Gaming Mode 旅程证据 | 不称 `e2e_verified` 或 `standard_entry_verified` |

首轮 `CF7-LAUNCH-WEBVIEW2-MISSING` 已通过依赖安装解决；旧 `startup-failure-latest.txt` 可能继续保存首轮内容。必须依据同次运行日志的时间及身份判断，不能用旧摘要覆盖后续成功的 WebView2 初始化。

Wine / Proton 包装命令退出 0、bootstrap 的 5 秒存活检查和窗口出现，都不足以单独证明业务启动成功。本轮是探索性远程诊断，不是经正式 Steam Gaming Mode 入口完成的产品验收。

## 4. 中文文件名线索与尚未完成的归因

### 已观察到的内容

直接 Flash 文件访问诊断使用显式 Windows SWF 路径。日志显示主 SWF 已被读取，随后访问 `flashswf/UI/加载背景.swf` 返回 `c0000034`。Linux 侧相同路径存在，大小 4,458,807 字节，UTF-8 文件名字节正常。

进一步检查 Wine 的目录枚举，目标名字本身是正确的 Unicode，但枚举结果包含乱码和控制字符。对比结果如下：

- `加载背景.swf` 的 UTF-8 字节为 `e5 8a a0 e8 bd bd e8 83 8c e6 99 af 2e 73 77 66`。
- 将各字节与 `0x7f` 做按位与，得到的字符序列与 Wine 日志中的乱码枚举吻合。
- [机器证据摘录](evidence/steamdeck-install-20260907.json) 保留原日志行、字节串及转换结果。JSON 对控制字符的转义用于无损记录，不是把项目中文命名改为转义字面量。

这支持“文件名编码转换错误”为优先调查方向。它不能证明 Linux 禁止中文，也没有证明是哪一层选错编码，更未证明该次资源访问失败就是完整宿主启动超时的唯一根因。

### 上轮对照的解释限制

Proton 10 / 11、补齐原版底座、继承桌面 `LANG=zh_CN.UTF-8`、短 `C:\cf7-test` 路径映射均未消除宿主超时。**仅继承 LANG 不足以排除编码方向**：SSH / Python / 容器仍可能携带不同的 `LC_CTYPE`、`LC_ALL`，且尚未验证 Wine 实际采用的 CODESET。上轮“语言重跑仍失败”只是一条对照事实。

Wine 上游 `init_unix_codepage()` 使用 `setlocale(LC_CTYPE, "")` 和 `nl_langinfo(CODESET)` 选择 Unix 文件名转换；这是调查依据，不等于当前 Proton 构建的根因已经确定。[上游实现](https://github.com/wine-mirror/wine/blob/master/dlls/ntdll/unix/env.c)

更早一次直接向 Windows Flash 传入 Unix SWF 参数的独立启动不用于归因；`mm.cfg` 配置后没有取得可用 AS2 trace，也不应声称已经取得 Flash 业务 trace。暂不批量改英文资源名、不修改 SWF、不放宽宿主校验。

### 下一轮最短可证伪步骤

1. 在实际 Proton 运行环境中记录 locale 可用性及 `LC_ALL` / `LC_CTYPE` / `LANG`，核对 Wine 文件访问路径使用的编码；不要只读取 SSH 外层或 Python 的默认编码。
2. 用同内容、英文名 / 中文名的最小文件对照，在同一个 Wine 环境中分别枚举和读取；覆盖 Unicode 文件 API，必要时再核传统 ANSI API 和 Flash 文件 URL 转换。
3. 候选修正后重读原名 `加载背景.swf`，再验证共享脚本库加载、Flash 连接、握手和 scene-ready，建立完整因果链。
4. 编码仍解释不了时，依次检查 Flash 本地信任 / Socket policy、路径及 URL 转换、localhost 解析和宿主对等进程检查；HTTP 200 不替代这些检查。
5. 能进入游戏后再执行新建测试存档、进入关卡、存读档 / 正常退出，以及 Gaming Mode 下的手柄、窗口、声音与睡眠恢复验证。

窗口消息循环、SetParent、输入钩子、Win32 进程身份和音频端点属于后续兼容风险；目前不把它们写成已确认的故障。失败重试使用有界诊断，退出后按本次独立 prefix 清理进程，不用全局 `pkill wine`。

## 5. 当前安装链职责与复用边界

现有 `安装更新.bat` 调用 7-Zip，再运行包内 `bootstrap.bat` / `install.ps1`。PowerShell 定位 Windows Steam 库并复制 `resources` / `_Data`，包含 Windows 版本检查。[当前安装脚本](../tools/cf7-packer/sfx/install.ps1)

每日包带有 Windows .NET Desktop Runtime 安装器，native bootstrap 负责缺失运行时检查；包内没有完整 WebView2 离线安装器。仅在 Linux 安装 .NET 10 不能满足当前 Windows WinForms Host，依赖须进入运行游戏的同一个 Proton prefix。

[install-unix.sh](../tools/cf7-packer/sfx/install-unix.sh) 当前主要定位 Steam 库和复制更新目录，不能据其存在声称 Proton、.NET 和 WebView2 已由 SteamOS 安装入口供给。[打包工具 README](../tools/cf7-packer/README.md) 中 Linux / macOS 启动能力指打包工具本身，不等于游戏在这些系统上已兼容。

复用 `cf7-packer` 的文件选择与派生资产约束；新更新器只消费已生成产物及其完整性信息，不能另造一套容易漂移的运行文件白名单。既有 runtime manifest / consensus 字节保持不变，不改哈希来迁就复制或压缩处理。正式 Launcher 发布继续遵循 [runtime-build-reproducibility.md](runtime-build-reproducibility.md)，更新器不获得构建或 promotion 权威。

## 6. 长期更新器职责划分

| 部分 | 责任 | 收敛约束 |
|---|---|---|
| 公共核心 | 包识别、版本兼容、完整性检查、安装计划、文件更新与失败恢复、用户数据保护、诊断汇总 | GUI / CLI / Agent 调同一核心；复用现有打包契约 |
| Windows 适配 | Steam 路径、运行时检查、Windows 依赖安装、启动入口 | 安装职责逐步归并，避免更新器与 bootstrap 各自维护不同版本规则 |
| SteamOS 适配 | Steam 库 / prefix、Proton 和 Steam Runtime 调用、真实编码 / 图形会话、依赖供给、启动及日志回收 | 默认用户目录操作，不为安装更新关闭系统只读保护 |
| 版本 / 依赖清单 | 游戏版本、适用底座、最低更新器能力、依赖版本策略、下载来源 / 大小 / 哈希 | 初期只定义所需信息，不提前冻结完整 schema 或新增发布状态机 |
| 图形入口 | 找游戏、导入每日包、显示进度 / 结果、启动与诊断 | 玩家不必操作 prefix、命令行或安装器参数 |
| CLI / SSH | Windows Agent 对同一核心进行无人值守调用 | 不维护一套仅 Agent 可用的复制 / 修复流程 |

更新器必须能在目标游戏依赖缺失时启动，不能为了安装 WebView2 而先要求更新器自己依赖 WebView2；具体技术选型待最小实现验证。一个更新器识别多个版本，不随每个每日包复制出一套平台 App。

安装包文件、prefix 中的依赖、玩家存档和机器配置分别管理。先明确每类配置的默认值 / 用户修改归属，不能把整棵 `config` 永久排除而漏掉游戏必要配置更新。更新中断可重试；删除只作用于已记录且退休的包文件，不能对含存档、缓存或 prefix 的根目录做无差别镜像删除。

prefix 升级也可能改变注册表或依赖状态，文件回滚不能冒充环境回滚。第一版先保留已知可用环境，依赖组合变更使用独立环境做测试；不为每个日更复制整个 prefix。

## 7. WebView2 版本策略与分发成本

**方向**：Windows 普通玩家优先继续 Evergreen；SteamOS / Deck 在完整游戏验证通过后，按兼容证据决定是否使用 Fixed Version。当前 152.0.4191.66 只证明前门可运行，不是完整游戏的已批准依赖基线。

- Evergreen 离线安装器提供离线安装，不等于固定运行时；安装后仍属于 Evergreen 的更新模式。
- Fixed Version 可显式指定运行时目录，更新由项目维护；不能因“当前能用”永久冻结安全更新。
- 如果 SteamOS 需要固定版本，运行时作为该平台按需下载的独立依赖组件，首次或版本变化时获取，校验后长期复用。
- 不把同一份浏览器依赖重复塞进所有 Windows / SteamOS 玩家每日包；游戏内容日更与依赖更新使用不同频率。
- 建议保留下载缓存和可选离线依赖包，兼顾网络失败与手工导入；增加的是需要该依赖者的首次下载和磁盘成本。
- 相同依赖是否能跨 prefix 复用需独立验证，不先假定复制目录可替代注册表安装。

测试中下载的 Evergreen x64 离线安装器约 246 MiB；这不是 Fixed Version 包的实测大小。Fixed Version 仍会带来额外体积、版本保管及更新测试成本，按需组件只减少重复分发，不能消除这些成本。[微软模式说明](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/evergreen-vs-fixed-version) / [分发与指定运行时目录](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)

### Apple Silicon macOS 的评估边界

当前交付物是 Windows x64 的 WinForms / WebView2 Host、Flash Player 和 Windows native DLL；安装 macOS ARM64 的 .NET 或改一个编译目标不足以原生运行整套游戏。保持当前产物时，需要 Windows API 兼容层及 x86-64 指令转换，或使用运行 Windows 的虚拟机；原生移植则涉及宿主 UI、窗口 / 输入、浏览器及 native 边界的实质工程。

CrossOver 是 Wine 路线的兼容层，不是安装完整 Windows 的虚拟机。它与 SteamOS / Proton 可共用包识别、依赖清单、环境管理和诊断设计，但不能互认兼容结果：Steam Deck 本身是 x86-64，Apple Silicon 是 ARM64，还存在指令转换、macOS 窗口 / 图形 / 音频后端及权限差异。具体转换方式随所选兼容层版本核对，不将 Rosetta 单独等同于 Windows EXE 运行环境。[CodeWeavers](https://www.codeweavers.com/crossover) / [Apple Rosetta 说明](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment)

macOS 仅保留未来平台适配扩展点，本轮没有 Mac 实机证据，不承诺 CrossOver、其他 Wine 发行版或 Windows 虚拟机可运行本项目。后续如启动评估，应在同一 Windows 产物身份下，从 .NET / WebView2 / Flash / native 依赖开始分层验证，不仅凭同属 Wine 就套用 Deck 配方。Apple 的 Game Porting Toolkit 提供未修改 Windows 游戏的评估环境，其定位也不等于本项目已经完成原生移植或玩家发行适配。[Apple 工具说明](https://developer.apple.com/games/game-porting-toolkit/)

## 8. 分阶段推进与停止扩张边界

| 阶段 | 最小可交付结果 | 当前情况 |
|---|---|---|
| 编码 / 启动定位 | 可复现的字符读取对照，修正后原名资源与完整 Flash 握手通过 | 待继续，已有字节模式线索 |
| 单机安装配方 | 原版底座 + 每日包 + 依赖供给 + 正确启动环境可重复；明确旧存档保护 | 依赖 / 前门部分已验证，游戏启动未通过 |
| 公共 CLI 核心 | 包计划 / 安装 / 依赖检查 / 诊断可共用，Windows Agent 可 SSH 调用 | 待实现 |
| 平台图形入口 | 玩家导入每日包即可更新；已满足依赖时不反复安装 | 待核心稳定后评估 |
| 基准机回归 | 固定场景、游戏版本、SteamOS / Proton / 依赖、显示 / 功耗设置可对照 | 待完整运行与范围明确后建立 |

不提前新增重型 UI 栈、常驻同步服务、全自动 watcher 或完整跨平台发行系统。支持 SteamOS 不自动要求迁移游戏主体；不把探索 pending 塞进通用发布门。本轮只归档文档和证据，后续工程按具体授权推进，不从路线记录推导立即施工或发布权限。

## 9. 证据保留与后续维护

持久的最小文本证据为 [steamdeck-install-20260907.json](evidence/steamdeck-install-20260907.json)，含包与原始证据 ZIP 哈希、依赖安装结果、33 文件验证、HTTP 请求、启动 / 超时日志及乱码对照。它是历史诊断摘录，不是新的机器发布收据。

较大的 ZIP、截图和原始 Wine 日志保留在本机 `tmp/steamdeck-install-20260907/` 与 Deck 测试根，未纳入 Git。这些位置不保证在其他机器可用；若本机证据清理，本文和 JSON 仍保留核心事实，但后续界面验收必须重新采集。临时 `run-probe.py` 带诊断超时，非稳定安装器或正常游玩入口，不把其绝对路径固化为公共测试命令。

后续关闭编码根因、取得关卡 / 存读档 / Gaming Mode 证据、确定依赖版本策略、实现公共核心或退役旧安装入口时，同轮更新本文和所属 canonical 文档。不要根据单一成功截图抬高整个平台的验收等级。

相关入口：[技术栈收敛](tech-stack-rationalization.md)、[验证矩阵](../agentsDoc/testing-guide.md)、[Launcher 职责](../launcher/README.md)、[cf7-packer](../tools/cf7-packer/README.md)。外部参考：[Valve 开发机部署](https://partner.steamgames.com/doc/steamhardware/loadgames)、[Protontricks](https://github.com/Matoking/protontricks)、[微软 WebView2 下载](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)。
