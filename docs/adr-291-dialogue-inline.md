# #291 对白以 inline 整本交付

2026-11-20。根据 [#291 裁决](https://github.com/FlashNightModReborn/CrazyFlashNight/issues/291#issuecomment-7027728594)，在 `5f142def0a` 核查最后调用者，在含 #294 立绘修复的 `48b9f2ce79` 上构建本地候选并完成自动化回归。

| 归属 | 现役契约 |
| --- | --- |
| C# 数据 | `XmlDataLoader → DataCache.GetNpcDialogues → DataQueryTask.QueryNpcDialogue` 先合入当前存档的 Agent replace/append，再按任务进度返回组。按 `list.xml` 复算为 14 个 XML、288,911 字节、108 个 NPC、421 组、823 行。 |
| Flash 选择与快照 | 覆盖层刷新先核对存档，`查询并绑定NPC默认对话` 按 NPC 丢弃迟到应答。场景 NPC 持有 `默认对话`，菜单原地洗牌并推进 `对话index`。XFL、佣兵、任务、关卡沿用各自的数组入口及 `组装单次对话`、`解析单次对话`、`SetDialogue`。 |
| 播放与终态 | AS2 冻结人物和立绘，发送 `kind:"inline"`，持有 requestId、epoch、followingEvent、暂停、奖励门禁与换图取消。Host 本地换句并重试 closing。旧 Core 使用 v1。v2 确定失败时由 `replaceWithSnapshot` 移交已冻结的行。 |

## 最后调用者与删改

- **AS2 全量加载。** 从 `通信_fs_lsy_XML数据解析.as` 移除 `_root.加载并配置NPC对话`、`读取NPC对话`、`读取并组装NPC对话`、全量表写入，以及 `NPC对话_*` 的状态、回调队列、待绑定列表、加载令牌、ensureLoaded、执行回调队列、unload、isLoaded、注册待绑定、补齐待绑定、countKeys。核查脚本、XFL、动态键与 954 个有效 SWF，仅 `asLoaderLogic.swf` 的 sprite 1 第 2 帧有 19 处旧标识指令引用，均为定义或链内读写、调用。重编后旧标识的指令引用为零。
- **AS2 加载类。** `org.flashNight.gesh.xml.LoadXml.NpcDialogueLoader` 的调用只见于 `ListLoaderTest` 和 `test_npc_loader.as`。删除该类、专用测试和通用套件中的旧断言。发行数据的可读性改由生产 `DataCache` 测试覆盖。
- **C# 接收。** `TaskRegistry` 将 `native_dialogue` 登记为 AS2→C#，握手公布 `snapshot/book`。核查本仓工具及 299 个本地发行标签，128 个尚无该服务，8 个只用 v1，163 个发 v2 inline。成功构造 source book 的仓内调用来自专项测试。删除 `CF7Launcher.Guardian.Dialogue.INativeDialogueSourceAssembler`、`NativeDialogueSourceAssembler`、生产注册、`NativeDialogueTask.TryAssembleSource` 及装配专项测试。合规的新请求只要指定 `source` 即返回 `rejected/malformed`，即使携带 `lines` 也不会替换会话或消耗序号。`status.rowCount` 仍供在途操作核对。
- **验证依赖。** CF6 当前闭包改为绑定实际播放类 `NativeDialogueBookSession.cs`。历史音频资格回放按冻结提交取 Git 对象，`784be9d200` 清单的 1,094 项路径、对象、长度与 SHA-256 全部吻合。

## 验收与已知失败

- 最终候选的 C# 对白、覆盖层和立绘测试 **343/343**。CS6 三模块均为 **0 错误、0 警告**。只有 `asLoaderLogic.swf` 的逻辑帧变化，另外两份只有 SWF 元数据标签变化，三份按编译工具的整组验证结果交付。
- 真实 Flash TestLoader 通过对白生命周期 **436** 项、菜单 **87** 项、佣兵 **31** 项和 **15** 项入口断言。入口夹具使用生产帧脚本、基地地下 1 层 XFL 原文及受控查询回包，覆盖多组轮播、非人形佣兵、存档热重绑、旧应答、换图、人物与立绘。维护者于 2026-11-20 确认本地候选验收通过。
- 通用 ListLoader 在 CS6 上原版 **22/24**，本版 **21/23**，少的一项为退役的旧 NPC 断言。两版失败项相同，均为配件展示字段和套装数量（断言 66，数据 71）。
- CF6 离线闭包 **99/99**。整章实际捕获在 Wings 素材摘要处失败。音频合同测试在 `sounds/zero.wav` 格式断言失败，默认校验器在历史 ADR 状态断言失败。三项均已在开工基线上复现，原始失败记录随候选提供。
