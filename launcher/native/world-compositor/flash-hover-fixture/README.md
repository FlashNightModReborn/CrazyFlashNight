# 真实 Flash 鼠标悬停与取消夹具

用现役 x64 Flash projector 运行只有两个 MovieClip 按钮的独立 AS2 SWF；不加载主游戏、存档或修改器。Host 原样编译生产 Controller、Surface、Mapper 和 Bridge，驱动真实 broker/DLL。AS2 通过仅绑定 loopback 的 32187 TCP 端口回传 rollOver、rollOut、press、release、releaseOutside、drag 与定频坐标样本。端口占用直接失败，不接管已有监听者。

AS2 唯一源为 `movie/HoverProbe.as`（UTF-8 BOM）和该目录 XFL。只允许真实 CS6 编译：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target launcher/native/world-compositor/flash-hover-fixture/movie/HoverProbe.xfl -PublishOnly -VerifySwf launcher/native/world-compositor/flash-hover-fixture/HoverProbe.swf -TimeoutSeconds 180
```

XFL 的默认发布位置是 **movie 的上一级**，不要把 marker 或错误目标路径当成功。要求新鲜 Compiler 0/0 和对应 SWF 更新；运行行为由本轮 AS2 TCP 回执证明，publish 模式无 trace 不构成失败。SWF 是本地可重建派生物，不手改字节，不加入正式 runtime payload。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/flash-hover-fixture/run.ps1 -NativeRoot tmp/r6-fixed-native
```

runner 使用 exact SDK，复制配套三原生模块至每轮唯一目录。显示 `SETUP_RAW_FLASH_READY` 后、创建合成 P **之前**，用 computer-use **仅在实验设置阶段**激活 `CF7 disposable Flash hover fixture` 并检查确实显示两个矩形，再在本轮 evidence 目录创建空 `continue.flag`。激活失败不创建 flag。前台必须是已知 Host 或其嵌入 Flash 的 exact HWND；不得放宽到任意同进程窗口。这不是业务成功回执，只是让已校准的夹具开始刺激。等待上限 120 秒；不在每次点击前用自动激活掩盖失败。测试期间勿与其他窗口测试并发。

刺激来自明确标注的 SendInput，不能称物理人工点击。移动也必须使用 SendInput；仅 SetCursorPos 在本机不能完整刺激低级 hook，不能据其陈旧坐标宣布通过。输出包括 `identity.json`、`host.log`、`as2.jsonl`、截图和 `summary.json`。截图有遮挡或未取得预期坐标时，必须标无效环境，不能当产品反例。`CF7_HOVER_BOUNDARIES_ONLY=1` 只用于明确标注的边界切片，不运行两档完整矩阵；默认不设置，不能以切片替代全量。

当前覆盖：67%/100% 悬停和连续移动、每档 10 次切目标单击、真正移出按钮与整个呈现窗口/重入、离开哨兵负坐标、拖出释放不得点击、持键切到独立进程不得提交或夺回前台、返回首击、移动/resize/最小化恢复。扩展测试的退出码必须保留失败；2026-09-23 R6 最终为 **33/34**，`fresh_click_after_focus_return` 暴露 AVM1 旧按下状态未确认取消。此前未含整个 P 离开的扩展为 30/31；原始 15 项悬停/单击切片修补前 8/15、修补后 15/15，不用切片通过抹除扩展失败。完整时间线和裁决边界见 [R6 报告](../../../../docs/reports/统一输入-R6悬停与取消边界-2026-09-23.md)。

只关闭本轮启动的 projector/外部样本进程；不按名称杀游戏。AS2 事件回执证明这个样本的语义，不自动证明修改器、NPC 或全部持久操作的真实旅程。

## R8：取消机制判定与协作域

`-Mode Raw` 是默认原生回调 oracle；`-Mode Direct` 使用真实原生 Flash 输入、不创建合成 P，桥只做 capture 观测。`-BoundariesOnly` 仅允许 Raw，明确作为边界切片。R8 新增 pressId、press/release/releaseOutside/drag/key/deferred 模拟提交计数，刺激 ID、LL 边缘记录及有界丢失计数。外部窗口在返回测试期间保持存在。前台十次采样仍不证明连续无抢焦。

capture 观测及**已被否决的**单机制试验以补丁保留在 [experiments](experiments/README.md)。它们没有合入生产桥。有效候选仍缺新 press，不继续枚举 Win32 消息。

`-Mode Cooperative` 是独立的鼠标左键 M 域研究夹具。编译两个独立目标（顺序执行，各自检查新鲜 Compiler 0/0）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target launcher/native/world-compositor/flash-hover-fixture/cooperative-child/CooperativeChild.xfl -PublishOnly -VerifySwf launcher/native/world-compositor/flash-hover-fixture/CooperativeChild.swf -TimeoutSeconds 180
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target launcher/native/world-compositor/flash-hover-fixture/cooperative/CooperativeProbe.xfl -PublishOnly -VerifySwf launcher/native/world-compositor/flash-hover-fixture/CooperativeProbe.swf -TimeoutSeconds 180
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/flash-hover-fixture/run.ps1 -NativeRoot tmp/r8-capture-baseline/native -Mode Cooperative
```

两个按钮分别来自主 SWF 和实际 `loadMovie` 子 SWF。REGISTER 带 protocol、contentBuild、coverageRevision、incarnation 和能力清单；Host 聚合两个 exact CANCELLED，再与物理 neutral 取交集，收到两个 READY 后才开放新的真实 LL 边沿。五个鼠标键在**业务关闭阶段**各做一次明确的 SendInput Down/Up 以校准实验账本；这不是正式产品可采用的启动交互。取消不清物理 held，也不靠 GetAsyncKeyState 零值放行。hook 只排有界队列，网络发包在 UI drain 中；排队边沿保留准入状态、epoch、QPC 和刺激 ID。

Host 只提供坐标和手势；AS2 负责命中、目标普通对象身份、悬停/拖动显示、Begin/End、延后模拟提交及独立取消。旧 onPress/onRelease/onReleaseOutside/键盘回调只能报告诊断，不能提交、排业务任务或驱动主要视觉。原生 raw 首击失败仍保留在 Raw oracle 中，M 的新 Begin 不能将它改判成功。

完整实验 token 为 session＋coverage＋ownerEpoch＋gesture＋button＋beginSeq＋目标 incarnation；CANCEL 同 ticket 可重复，错 session/epoch/ticket、陈旧序号、孤立 END 被拒绝。子 SWF 同名重载先关门，更新 coverage/incarnation 后重新注册；父域回执不代签子域。这个有限资产集合没有生产未注册子 SWF；不声称能自动发现或屏蔽任意第三方内容。

本轮 M 夹具 **26/26**，包含 raw 键盘旁路、延后取消、多键、旧 ACK、缺子域 ACK、持键返回、空白命中和同名重载。它只证明一次真实 projector 的注入鼠标实验，**不是真实 surgery、生产统一输入、IME/Tab、跨屏或人类验收**。游戏 Surface/Controller 的物理账本与 C1 仍未接入本实验。证据、边界和下一步见 [R8 报告](../../../../docs/reports/统一输入-R8取消机制判定与协作域-2026-09-23.md)。

回执复核补充：26 次断言只有 20 个不同名称；子对象仍由同一根协调器管理，缺子 ACK 是接收端丢弃负控，不是独立子程序拒绝清理。当前原型存在未修复的 S1–S4 静态缺口，尤其队列故障只关 Host 门且阻断取消发送，不能保证 AS2 已排队任务失效。**不要原样接入生产。** C1-I 路线与修补前置归[计划 §14](../../../../docs/统一合成与输入归属-分阶段施工计划-2026-09-22.md#14-r8-回执采纳c1-i-专用真实隔离入口)；本轮接受回执没有改变夹具运行行为。

## R9 后续施工

以上 R8 描述保留为历史状态。当前 Cooperative wire 为 v2，新增 geometry；Host 的数据队列故障不再封死取消控制；准备轮次遇 Down/Up 作废并等待 neutral 后重新准备；最终 grant 在观察前缀之后复验 exact ACK 集合。owner 移动/尺寸变化撤销 M，旧 geometry 按钮边沿拒绝。`TEST_READY_DELAY` 只在关闭状态供此 disposable 夹具延迟实际 AS2 回执，不进入生产协议。

当前有限切片 **35/35**，含 S1 队列实际溢出且 AS2 已有延后任务、S2 两个 READY 之间真实 LL Down、S3 LL Down 入队后窗口移动。显式 `-Mode Cooperative -S1NegativeControl` 会故意丢弃撤销路径，预期 `S1_remote_deferred_obligation_revoked` FAIL、随后关闭回执超时；它验证判定器，不能拿来做人验。正常 runner 显式清除此负控环境开关再运行，结束后恢复调用方环境。

本轮未完成 S4，也不覆盖完整 DPI/重绑/子域独立故障矩阵；仍不得原样接入真实游戏。原 raw 失败继续独立保留。[R9 报告](../../../../docs/reports/统一输入-R9前置修补与物理来源采样-2026-09-23.md)记录了更早的只读来源采样节点及精确候选入口。
