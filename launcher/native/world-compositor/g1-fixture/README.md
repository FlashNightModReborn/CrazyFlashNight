# G1 v4 输入会话夹具

本入口使用生产发送端、生产 Controller 续接、真实 broker/DLL 与 Windows 队列；目标是原生测试窗，**不是实际 Flash 游戏**。
桌面刺激须串行执行；每轮独立 run/evidence 目录保留，不按进程名杀其他 broker，不删除历史证据。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/build-dev.ps1 -Target selftest
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/g1-fixture/run.ps1 -Mode queue
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/g1-fixture/run.ps1 -Mode renew
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/g1-fixture/run.ps1 -Mode failure
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/g1-fixture/run.ps1 -Mode geometry
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/g1-fixture/run.ps1 -Mode maximize
```

- `queue`：端点失焦、owner Deactivate、未见 Down 撤销、队列满导致 CancelPostFailure；另测已交付 Down 后取消失败且无后续数据的持久清理。
- `renew`：受生产硬上限限制的小 cap，通过生产 Controller 连续三次完整关闭/重新 READY，检查 fresh Down/Up、输出 HWND 不变、并发安装拒绝、旧控制拒绝、保留的 PM_NOREMOVE MSG 副本不能重放；后台线程持续调用目标主模块 IAT。
- `failure`：目标主动加外层 WNDPROC 模拟恢复所有权冲突；关闭必须未确认、后继必须拒绝、目标进程保持存活。最后仅关闭本轮自建测试目标。
- `geometry`：生产 Controller、实际 WGC/D3D、67% 原生源；不泵 Host 消息时移动 owner，检查 P 可见性和屏幕远端像素。主动隐藏 P 并刷新 parent 的负控应露出未被 F 覆盖的底色。此处不是 Adobe Flash，也不是多屏/DPI 验收。
- `maximize`：在 geometry 基础上，切到 100% 源，构造 F 比 P 下移 1px 但仍在 S 内的反例；执行三轮真正的最大化/恢复，检查顶端像素、实际 crop、捕获代次变化及 P HWND/输入会话不变。必须检查截图中的遮挡，其他应用盖住采样点时不得把颜色失败归因于渲染；源码/真实 Flash/人类体验仍分别记录。

runner 为本轮子进程临时设置 `CF7_FOCUS_TRACE=1` 并恢复原值。broker 创建独立的 128 项诊断共享环，v4 输入映射大小与线协议不变；目标 UI 线程仅写原子字段，broker 取出后写 stdout。`TRACE` 的 QPC 是端点时间，日志行前缀是 broker 被读取的时间，不可用后者量端点延迟。覆盖时打印 `TRACE_GAP`，缺项不得补造。原窗口过程返回不是 AS2 on(release) 或业务 ACK。

新自测还检查诊断环覆盖/未提交项的拒绝，以及端点已准入 epoch 高水位。数据 selftest 走 Deliver；真实 WM_ENTERMENULOOP 等控制事件走真实 WindowProc，不把控制消息误送到数据解包器。

`renew` 的小 cap 是加速状态机实验，不冒充千万次物理点击或完整 Guardian 验收。
旧 v3 `--long-session` FAIL 保留在冻结补证包；v4 原生自测拒绝该旧参数，禁止把“拒绝到点输入”替换成连续可用的成功声明。
当前人力配合点见[施工计划](../../../../docs/统一合成与输入归属-分阶段施工计划-2026-09-22.md#11-续接记录当前唯一状态)。
