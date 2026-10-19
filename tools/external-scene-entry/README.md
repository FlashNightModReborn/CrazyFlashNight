# 外部地图入场回归

这是隔离开发候选的验证工具；工具本身不执行提交、推送或正式发布，不使用真实玩家槽。最后核对基线：`106e6a90714305910a0e9edac420de46254a5921` 加本轮差异。

## 证据边界

原现场 tr:18 长时间停留在 loading。捕获短暂陈旧后恢复推进；合成器 sceneReady 不能代签请求目标世界的 SceneReady。健康机器上的旧基线能够进入测试空间，GPU 退化和标签错位与事故的因果关系均未证明。本工具验证外部地图路由及兼容性，不把本机通过写成原事故已治愈。

源码夹具 `node tools/test-external-scene-entry.js` 和 `node tools/test-scene-transition-stage-entry.js` 不证明真实 MovieClip 生命周期。`scripts/run-scene-transition-tests.ps1` 保留当前镜头及加载停滞断言，并执行生产挑战拒绝 handler；`scripts/run-lee-trial-tests.ps1` 覆盖 Lee 接续与地图导航权威。实际 trace、Compiler 0/0、目标 SWF 和类归属仍须由真实 CS6 生成。

## 当前执行方式

先核对共享 CS6、Commands 和 TestLoader 所有权，按仓库编译合同在隔离工作树编译 focused、asLoader 和 main。封存每轮 Compiler、输出、trace、目标 SWF 及首次失败。编译只在源码/目标改变时重做。

最新主线的 A5 专用进档属于材料商店专项，其 resources 布局、适用性和同旅程权限不能借给地图测试。此前 9f548 基线的 A5 八段回归仅是该历史候选的证据。当前验证使用普通生产启动界面、immutable c-* 候选及精确的 `cf7_agent_equipment_tuning` 自有隔离槽。只从已封存的 agent 夹具逐字节克隆；不覆盖已有差异，不修改解锁权威，不操作真实玩家槽。

本机深路径下，默认 WebView2 缓存可能触及主线新增的 240 字符限制。使用生产者已有的 `WebView2CacheDirectory` 短本地路径参数；可从既有、哈希匹配的运行包分块无损还原锁定 CAB，仍须通过官方缓存/库存校验。不得放宽预算、使用链接或更改全局目录。生产者只构建候选，随后由 `automation/dev.ps1 -ReuseOnly -BuildOnly` 复核并选择，不更新正式 runtime。

Agent 在电脑操作运行时导入 `ui-session.js`，启动前建立日志水位并封存身份，再通过 `automation/start.ps1 -CandidateRoot <c-候选绝对路径>` 的正常界面进档。原生窗口操作使用 Computer Use 的 sky API；本轮已获用户明确授权，以 `cdp-input.js` 的真实浏览器鼠标事件点击隔离候选按钮。每次先核对 loopback listener、WebView 进程到精确 Guardian 的父链及本工作树 userdata，再读可见按钮几何和命中点，记录每个 Input 包的回执；没有硬件输入证明。`run.js` 仍是只读几何助手。不得 DOM `.click()`、调用业务/隐藏进入函数、伪造场景就绪或沿旧 A5 入口绕过新限制。输入失败或未知即停止依赖操作。

实际步骤为：首次进入测试空间 → 同帧前往军阀帐篷 → 同帧返回测试空间 → 返回基地 → 重入 → 返回基地 → 再次重入 → 返回基地。每个跳图操作先调用 `SceneUiSession.expect`，真实点击后再调用 `observe`。任何一段失败或结果不明即保留证据并停止依赖操作，不能靠重复点击、定时揭幕或强制关闭来解锁。

## 成功判据

每段要求新的请求、递增场景编号、同请求 cover/loading/reveal、真实目标世界的 SceneEntryReady 和 Host scene_transition_revealed。同帧段还要求 SceneEntryNavigation 的入口、目标及实际根帧一致；经过基地的跨帧重入不能代签它。两个标记只观察现有控制流，不赋予准入或强制揭幕。AS2 服务日志和协议独立批处理，不虚构跨通道到达顺序。

普通启动窗口在确认后退出，可能遗留旧 DevToolsActivePort；只读发现跳过不可连接端口，实际目标仍逐次核对进程归属。地图会记忆上次页签且异步同步权威数据，先观察当前可见页、分区和按钮再点击，不把旧 DOM 当新状态。零 Input 派发的可见性拒绝可在核清新状态后重新选择控件；任何已发送输入的未知结果都不得重放。

`oracle.js` 和 `self-test.js` 覆盖陈旧/异请求/缺失就绪、仅覆盖层关闭、仅正常退出、被替换转场及错误分支等反例。`log-tracker.js` 从启动水位读取，保留半行 UTF-8 和滚动前未读记录。完整关键行带源路径、文件身份和字节位置落盘，不做首尾截断。

每轮摘要绑定实际路径、Core EXE/DLL SHA-256、场景源码、build identity、payload closure、配套 SWF、专用槽和操作所用窗口。正常界面退出必须另由持有该精确 Guardian 的进程观察器取得 exitCode=0，且没有强制恢复；它属于 normal process exit，不得冒充 trusted-runner completion。全部八段通过、退出身份正确、源码/二进制稳定和非目标槽集合不变后，才记录 passed_normal_ui。

非目标槽逐字节保护。仅将精确 `.launcher-version-marker.json` 的 version=1 / writtenAt 两字段启动元数据单独校验和封存，不作泛化隐藏文件排除。现场事故复现、完整 Lee 实战以及真人观感和手感仍是各自独立边界。

本轮隔离候选的身份、配套编译、八段实际回执摘要及边界见[机器核验记录](../../docs/evidence/external-scene-entry-2026-10-19.json)。实机所用验证器另按其 SHA-256 封存；回归后收紧的跨段递增判据由离线反例及原始回执重新验证，不冒充一次新的实机运行。游戏源码和配套 SWF 在此期间未改变。

维护者确认本轮测试有效后，源码与该配套 SWF 可按已授予的提交推送权限一起交付。它们属于 Flash 内容；没有原生部署闭包变化时不借此重建或推广原生 runtime。隔离候选验收和后续主线交付仍分别记录。
