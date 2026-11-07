# 漫画开场试点：开场执行准入与呈现交接

> 历史试点记录：当前全部漫画开场的接入、验收和回滚以[统一迁移记录](scene-intro-migration.md)为准。下文“仅首图”等限定描述本轮试点当时的范围。

本轮仅接入 `repair-campus` 第一个子关卡的 `chapter0 / prologue`，沿用原漫画、原剧情对话和波次配置。AS2 决定剧情完成及战斗执行，Host 决定窗口和输入交接，Web 负责绘制与播放。其他书本、CF6 和没有 intro 描述的关卡继续原路径。

## 准入与成功路径

`BookRunRules` 在首图写入纯数据 `BasicInformation.Intro`。`StageManager` 在关卡事件、实例和环境初始化前调用 `StageIntroService.declare`。只有当前书本、活动 run、slot、普通 world identity 和 Host 能力均匹配时才接入；不取得全局 PauseManager lease。书本竞速计时同时消费开场执行标记，漫画租约释放后的失败等待也不计时；执行放行时记录新的计时边界。

加载、相机、通信和必需时间轴继续推进。玩家初始化完成时保存待执行的 Start；本图的波次、AI、弹体命中及直接伤害入口同时检查世界执行标记。标记不参与旧世界对象枚举。本试点没有 authored 敌人，不能据此宣称其他地图的自带时间轴敌人均已治理。

Host 先确认当前目标世界已有新捕获帧且旧幕仍不透明，再发送 exact `intro_covered`。AS2 退休原加载尾部，发布 `phase=intro` 并独立发起原章节，避免等待被自己延后的 Start。原 Start 回调识别已发起的章节，不重复打开。

漫画静态首帧绘制后发送原 `prepared` 业务请求。Host 等业务确认及 exact 新面板实例可承担呈现，以实际原生窗口可见性核对端点（WebOverlay 的托管 Visible 不能代表 SWP_SHOWWINDOW），先把漫画端点置于旧幕之上，再撤旧保护并投递成功响应。漫画取得前台后，开场资格认可当前绑定的 exact 原生面板及其子窗口，不泛化到同进程其他窗口；文档失效会撤销播放准入，但该 exact 原生窗口在关闭前仍可把前台交给恢复黑幕。播放、键盘推进和整页阅读均等待此响应；迟到、重复及已关闭实例的响应不能恢复旧播放。

正常继续或跳过交给原 BookComic / BookRun owner，随后沿用原对话及其 `followingEvent`。原漫画关闭先补上不透明保护，原 pause 释放、关闭事务和焦点收尾仍由现有 owner 完成。Host 等 exact native close、当前世界新帧及前台资格，发送 `intro_surface`。AS2 只有同时具备剧情完成和呈现恢复两个事实，才清除执行标记，兑现待执行 Start 一次，再按原配置初始化波次。

## 身份和失败

| 边界 | 凭证 / 约束 |
|---|---|
| AS2 执行域 | world 普通对象身份、run 引用、slot；旧 MovieClip 路径不能复用 |
| 过场投影 | v3；requestId / revision / targetScene / introId；v1 只在揭幕前升级 |
| 时间轴退休 | `intro_covered`；不伪装成普通 `revealed` |
| 漫画打开 | openData v2 增加 introId；业务 prepared / finish RPC 保持 v1 |
| 播放激活 | 当前面板 instance、当前 document、原 callId 和 presentationId；失效即拒绝 |
| 恢复 / 操作 | `intro_surface` / `intro_retry` / `intro_return` 使用当前 exact 投影 revision |

图片失败、关闭、中断、超时、transport 断开或 document 更替均不能替试点生成剧情成功。失败保留执行屏障和不透明保护，提供「重试漫画」「返回书架」。重试沿用当前章节责任，创建新的漫画实例；返回委托既有返回基地入口，保留持久写及 unknown 约束。失败关闭仍完成原关闭收尾，不把它冒充为游戏恢复。

保护 Web 文档重建时重新投递当前 v3 投影；在新文档的 covered 事实到达前保留原生黑底。Alt+Tab / 最小化期间不抢回前台，不发送游戏恢复许可。以上协议事实不等于物理屏幕逐帧验收，后者须绑定实际候选单独记录。

## 验证入口

```powershell
powershell -NoProfile -File scripts/run-stage-intro-tests.ps1 -AutoStopReadOnlyPlayer -TimeoutSeconds 900
node tools/test-stage-intro-admission.js
node tools/test-stage-intro-browser.js
node tools/test-book-comic-player.js
node tools/test-book-comic-browser.js
node tools/test-scene-transition.js
node tools/test-scene-transition-stage-entry.js
node tools/test-external-scene-entry.js
node tools/test-bookshelf-runtime.js
node tools/stage-intro-live-e2e/test-save-protection.js
powershell -NoProfile -File tools/run-focus-sol-recheck.ps1 -Phase integration -Canonical
```

原生 aggregate 钉值为 StageIntro 22、SceneTransition 119、BookComic 48，必须同时有本轮 Compiler 0/0、唯一 runId 行为闭环、SWF 刷新和函数体门。`-OwnedReadOnlyHost` 另要求两项既有计划任务都直接执行同一 CS6；旧 cmd 文件关联任务不满足资格时不绕过检查。新 suite 已在只读清理封闭名单内，不涉及真实 SharedObject 或存档写入。

真实旅程使用 `tools/stage-intro-live-e2e/run-candidate.js` 的专用克隆，通过原书架 UI 选择此书。必须在交互式控制台运行；自动化调用分配 PTY，封闭标准输入在准备克隆前拒绝。工具固定克隆槽、核验候选身份及 fresh asLoader 摘要，只开放只读观察和正常关闭。允许原生产流程新建的 exact 附属 bookrun 槽；所有原有 JSON/SOL 的内容及集合必须保持。不得以控制台直接完成剧情或写战斗状态充当验收。

验收应记录漫画前没有 Start / 波次，漫画继续或跳过后原对话完成、surface_ready、execution_granted、Start、波次依次发生，重复回执不重开。另查慢解码、页面失效及重试、Alt+Tab、不透明接力和返回。浏览器夹具、Host 模型、真实窗口合成夹具与实际 Flash 旅程分别记账，感官或人工未完成项保留待验。

## 本轮实机验收（2026-11-07）

基线为 main `4169fa5808dcef5d8b3a0af23fab9e3d0b904ab1`，改动留在主线工作区。最终本地候选为 `intro-prologue-1107g`；Core SHA256 为 `797E2BFC461C31B44D987FA9E0ABE994987DC04063328FF4F9125737362961AA`，本轮 CS6 发布的 asLoader SHA256 为 `46DCA8E4DC09C13E9C18E18514CFD4748AC5FAAA7916E0078E3A94682A4A7D63`。

最终原生 aggregate 为 22 + 119 + 48 = 189 项通过，Compiler 0/0，fresh runId 为 `a8f8592f95a74d89a9a7a0f42545f0ac`。Host canonical 为 8,281 项通过、31 项跳过、零失败；另有 71 项真实 HWND / WebView / 合成窗口检查通过。这些夹具与实际游戏旅程分别记录。

实机从正常书架 UI 进入此书首图：漫画自动获得播放许可；正常 Alt+Tab 后保留开场屏障；页面重载后自动呈现原生失败黑幕；点击原「重试漫画」按钮后，新实例自动恢复播放。选择原「跳过」入口后，原生 Andy 对话仍保持执行屏障。完成对话后，`narrative_complete / execution_granted / start_published / waves_initialized` 各出现一次，首波出现并发生实际伤害。随后经失败返回恢复原角色，记录有效战斗时间 36.294 秒、零 SP、零通关和零最佳纪录。开场从声明到放行约 2 分 39 秒，未计入战斗成绩。

本轮使用专用克隆档，正常关闭候选及交互式验收进程后，312 个运行前既有 JSON / SOL 工件集合及内容保持一致，种子与克隆恢复、锁与恢复记录清理均核验通过。仅保留生产流程新建的 exact 本轮 `bookrun_c84eed88e6facff619d262e2.sol` 作为隔离测试工件。

实机发现并修复了托管 Visible 与原生显示状态不一致、以及漫画取得前台后被旧遮幕资格排除的两个交接阻点。前台单元回归使用受控的只读窗口观测；真实焦点交接由上述候选实机旅程验证。此前受输入资格变化影响的检查和失败尝试已保留记录，最终全套重跑通过。

本轮覆盖漫画开场交接、首波战斗及失败返回；首图胜利、七图通关、物理显示器逐帧零闪帧、人工音频混音与主观手感未验收。本轮未提交、推送或正式部署。验收 JSON、原生截帧、编译凭证、测试结果及 exact 源码反向补丁随本轮交付包保存。

## 回滚

优先回退新会话能力：在候选启动进程的环境中设置 `CF7_STAGE_INTRO_HANDOFF=0`，再使用本地开发入口启动。Host 对新 covered 不宣布 intro 能力；AS2 完整沿用旧书本开场路径。这个开关不改变正在进行的 v3 会话，不能用于中途清除保护。

活跃开场先使用其原重试 / 安全返回入口，等待原会话退休并正常退出本轮候选。若持久写结果未知，先按原权威对账，不能用关窗或开关解除锁。

源码回滚使用本轮交付包中的 exact 反向补丁，先 `git apply --reverse --check`；任一文件已漂移即停止，按文件核对他人后续修改。禁止 `reset --hard` 或覆盖整个工作树。本轮新编译的 asLoader 另用「编译前最新 main」备份恢复，先核对两端 SHA256；初始审计基线的旧 SWF 不能覆盖后来已提交的刺弹炮修改。

`effects.v1.json` 是上游资源源文件变化后的生成器同步，单独记录，不混入开场能力反向补丁。回滚后重跑相关 AS2 / Host / Web 门及选定旅程。本地候选、源码和正式 runtime 分别管理；本任务未授权正式发布。
