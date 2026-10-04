# 闪客快打系列书籍与合集原版接入

**状态：2026-10-05 已按双独立 builder 正式 promotion 并通过远端部署 Audit。** 本文负责章节目录、原版内容许可和隔离播放器；重制旅程、奖励及存档权威仍归[书架玩家上下文合同](bookshelf-player-context.md)。专项通过不证明正式 Steam 入口、完整战斗或玩家体验验收。

## 一册六章

作者目录在 [catalog.json](../data/books/catalog.json)，通过 [阅读导入器](../tools/import-bookshelf-library.py) 生成 Web 阅读目录与 manifest。系列阅读 ID 为 `crazy-flasher`，标题《闪客快打》，章节 `cf1` 至 `cf6`。第 1 章名为修理大学，其重制入口仍提交 `play / repair-campus`；AS2 的运行、奖励、存档身份没有改名。

| 章节 | 原版来源 | 重制入口 |
|---|---|---|
| 1 修理大学 | 已导入且校验完整性的原版 SWF，中文 | 既有修理大学七图历险 |
| 2–6 | 本机正版闪客快打合集的中、英文 projector 内部 SWF | 尚未制作，按钮不可提交 |

原版不创建 `bookrun_`、不写 CF7 SOL/JSON、不提交 CF7 奖励或 SP。第 1 章重制详情按领域规则显示首次通关或刷新个人纪录 45 SP、其他成功通关 5 SP、失败或离开无奖励，以及包含暂停、商店、过场的总计时。调试局的奖励禁用仍由领域规则裁决；界面文案不承担奖励权威。

## 内容许可和本地文件边界

[SteamCollectionAccess](../launcher/src/Config/SteamCollectionAccess.cs) 的来源选择复用 [SteamOwnershipCheck.IsDevRepository](../launcher/src/Config/SteamOwnershipCheck.cs) 的既有 Git 开发仓库判定，不新增 Web 开关，也不放宽该判定。开发仓库使用独立的本地内容读取器；普通发行环境使用共享的进程 Steam 客户端。成功初始化后不再重复初始化，不切换 CF7 的 AppID `2402310`、不写 `steam_appid.txt`，不加载或运行合集 EXE。

普通发行环境的合集 AppID 为 `1540150`。必须同时取得当前已登录用户、`BIsSubscribedApp` 的所有权、`BIsAppInstalled` 的安装状态和 `GetAppInstallDir` 的路径；目录存在、Steam 安装清单或旧 `SteamID.txt` 都不是所有权证明。无法读取 SDK、无法连接 Steam、未拥有、未安装分别返回可重试状态；这些失败不会回退到开发豁免。

按维护者要求，合法 Git 开发仓库沿用本体现有豁免，无需启动 Steam。[DevelopmentCollectionAccess](../launcher/src/Config/DevelopmentCollectionAccess.cs) 从同一游戏库的 `CrazyFlasherSeries` 目录、Steam 注册表安装位置和有大小、条目上限的 `libraryfolders.vdf` 定位本机已安装合集。文件位置仅用于开发资源发现，不作为所有权证明；不扫描任意磁盘，不读取旧身份文件。没有本机内容时返回 `development_content_missing`，界面明确提示安装合集。开发来源没有 Steam 用户、persona 或 DLC，所有 SWF 完整性检查仍执行。

[BookshelfOriginalContent](../launcher/src/Tasks/BookshelfOriginalContent.cs) 仅接受章节和语言，文件名在 Host 内形成固定集合 `exes/crazyflasher{2..6}-{cn|en}_secure.exe`。拒绝任意路径、未知组合、额外字段和越界 JSON 整数。路径组件不允许 reparse point；文件以只读、不共享写入或删除的方式打开。检查 projector 大小上限、`MZ`、末尾 `0xFA123456` 与 payload 长度，计算 SWF 范围，验证 FWS 版本、声明长度及已核对 SHA-256。当前支持 11 个 SWF 变体：CF1 中文和 CF2–6 中英文。Steam 更新导致字节变化时明确拒绝并提示等待兼容更新，不能静默加载未经核对的新文件。

商业 SWF 不导入、复制或打包进仓库；只有一次播放器租约的内存字节。资源请求仍核对来源模式、存储命名空间和安装位置；Steam 模式另核对当前账号、合集许可和安装状态。兼容资源 `SteamID.txt` 仅在 Steam 模式下于受控资源来源内临时合成，内容来自当前已认证的 Steam 用户与 persona；`myDLC` 按 DLC `2917650` 的真实 `BIsDlcInstalled` 值生成 0 或 1，采用 UTF-16LE BOM。开发模式不提供此资源，不伪造身份或 DLC。不会读取、修改或复用安装目录中的旧身份文件，不记录 Steam 用户身份到日志。

## 协议、隔离与生命周期

原版使用独立的 [bookshelf-original.v1 合同](../launcher/contracts/bookshelf-original.v1.json)。Web `panel=bookshelf`、`domain=bookshelf-original` 只允许 `prepare` 和 `release`，均为无 CF7 持久写的内容操作；既有 `bookshelf` 的 AS2 snapshot/commit/query 合同保持独立。

只有 `https://overlay.local/overlay.html`、当前 Host 书架实例，以及 AS2 已确认的 exact token / editing 快照可以准备内容；快照必须成功、允许上下文操作、没有运行中或待处理的旅程、没有未解决写入。关闭、断连、失败读取、开始 CF7 写操作和 dispose 撤销准入。旧实例或迟到的提取结果不能建立新租约；旧 release 只能释放自己对应的 session，不能关闭后来的播放器。

原版 iframe 由 [BookshelfOriginal](../launcher/web/modules/bookshelf-original.js) 控制，固定来源 `https://cf7-originals.local`，使用 `allow-scripts allow-same-origin` sandbox 以保留自身存储。该来源与 Overlay 不同；不授予 popup、下载、表单或顶层导航，没有 Frame Host 消息桥或原生对象。父子消息核对 exact window、origin、channel 和 session，只处理 playing/paused/error 与暂停/继续。泛用 Host 消息入口拒绝原版来源；原作不能提交 CF7 档案、奖励或其他 task。

[原生资源 handler](../launcher/src/Guardian/BookshelfOriginalWebResources.cs) 只公开当前文档、player.js、固定 Ruffle JS/WASM、当前 session 的 manifest/movie，以及身份兼容资源。无磁盘目录映射、无通用文件服务、无 source map 或 SWF 下载按钮。所有资源 `no-store`。CSP 拒绝外部网络、子 frame、object、form 和外部脚本；不能把 Ruffle 的 `allowNetworking` 当作网络封锁证明。原生 frame 导航额外限定当前播放器文档。

原生 filter 使用带 `CoreWebView2WebResourceRequestSourceKinds.Document` 的三参数重载，才能收到 iframe 的 script/fetch/WASM 子资源；两参数版本只能看到由父文档发起的 iframe 文档请求。依据 [Microsoft WebView2 frames 文档](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/frames)，该接线已纳入真实 WebView2 专项。

返回、改章、关面板、rebind 和重载都会销毁旧 iframe、计时器和事件监听，并释放旧内容租约。异步授权回来时若页面已离开，只释放租约，不挂载、不抢焦点。原版保留游戏自定义右键菜单；设备字体用 Ruffle `deviceFontRenderer=canvas`，避免动态中文缺字。比例仍使用 `showAll / forceScale / letterbox`，外部书架使用既有 1024×576 PanelScale。

## 原版存档

CF1 保留原有从头进入的行为。CF3–6 的 SharedObject 由原作自身读写；它们与 CF7 永久档和肉鸽临时档无关联。合集原版文档使用稳定的当前账号摘要 / 章节 / 语言路径；`data + swfFileName` 使用固定 `cfN-lang.swf`，临时 session URL 只供内容和兼容资源请求。

实际 Ruffle 存储键形如 `cf7-originals.local/player/<account-sha256>/cf4-cn/cf4-cn.swf/crazyflasher4_save`。session GUID 不进入键。中英文和 Steam 账号分别隔离。开发模式改用带独立版本前缀的规范仓库路径摘要，重启后保持稳定，不同开发仓库及 Steam 账号存档互不混用。不自动迁移原 Adobe projector 的 SOL，也不复制别的用户的原版存档。摘要仅用于命名空间，不作为许可证明。

## 验证入口与边界

- `python tools/import-bookshelf-library.py --check`：阅读派生目录与资产闭包。
- `node tools/test-bookshelf-runtime.js`：目录、六章身份、传输域与阅读资产。
- `node tools/test-bookshelf-original.js`：原版控制器准入回包、固定来源、迟到回包、重载和关闭清理。
- `node tools/run-bookshelf-flow-harness.js`：生产面板与模拟 Host/AS2 回执，章节选择、待制作状态、许可失败、对账和三视口布局；不证明 Steam 许可或真实玩家旅程。
- `DevelopmentCollectionAccessTests` / `BookshelfOriginalContentTests` / `BookshelfTaskTests`：复用 Git 豁免且不调用 Steam、普通安装仍校验、跨库发现、开发存档稳定及隔离、缺失内容提示，以及许可缺失不读文件、巨大整数、篡改字段、切账号、内容租约、边界范围与准入撤销。
- `node tools/probe-bookshelf-original-runtime.js --collection-root=<本机合集目录> --out=<临时输出>`：明确 opt-in 的只读本机资产探针，以隔离 Chromium profile 执行生产 wrapper / CSP。11 个变体加载，外部请求封锁，以及 CF4/CF5 原版 SharedObject flush、旋转 session 后稳定键和实际读取。不会建立 Steam/Host 准入结论，不启动原 EXE，不导出 SWF。
- `CF7_TEST_BOOKSHELF_WEBVIEW=1`、`CF7_TEST_BOOKSHELF_ROOT=<仓库>` 后运行 `BookshelfOriginalWebViewTests`；`CF7_TEST_BOOKSHELF_CHAPTER=5` 可验证本机合集中的第 5 章，默认第 1 章。使用隔离 WebView2 profile 和不激活的离屏窗口，准入由夹具提供，内容选择、读取与资源 handler 均走生产实现；默认全量跳过，不与依赖窗口顺序的测试并跑。

提交、正式发布、合集 Steam 入口的真实账号许可链、完整原版关卡体验、所有自定义右键命令、完整存档游戏进度与重启续玩、人类视觉和输入验收仍是不同工作。最终 Host 全量与合并后的候选构建由主控协调，不用这里的叶门替代。

## 2026-10-05 正式发布

本轮源码 `1318feadfe8b4634fed80b3805d257189a36b821` 经本地 X509 与 GitHub hosted OIDC 双故障域构建，identity / closure 全等，production policy 47/47、strict v2 和正式安装校验通过。部署提交 `29976fd57732f0721a88530446ae8f1e6b03b7fe` 的[远端 Audit](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/37221863217)成功；机器证据归[本轮发布回执](evidence/bookshelf-rations-originals-release-2026-10-05.json)。

标准无候选参数入口仅完成 formal runtime 身份、Core路径与通信就绪启动检查，随后正常关窗；真实CF7存档与SOL前后逐字节未改变。该启动smoke不代签完整七图、配给与SP存档重启、Steam账号许可链、原作通关输入或听感验收。
