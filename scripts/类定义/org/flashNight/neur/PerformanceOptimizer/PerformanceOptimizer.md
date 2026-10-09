# Flash 性能采样与执行桥

C# `PerfDecisionEngine` / `RenderSchedule` 独占预设、预算、自动升降档和生效观察期。AS2 只测量实际 Flash 帧时间、执行完整表现目标并报告执行结果。断连保持最后有效状态，不运行本地后备调度。

## 运行闭包

- `IntervalSampler.as` 每帧累积实际时间，以 500 ms 窗口报告帧数、耗时、长帧数和最大帧耗时。
- `PerformanceScheduler.as` 管理观察 epoch、单调命令编号和执行确认。`ServerManager.as` 只从当前连接转交性能指令。
- `PerformanceActuator.as` 设置显式 Flash 画质，以及尚未迁入 native 的表现预算。它不读取旧画质预设上限，不改变 NPC 密度或镜头容差。
- `通信_fs_帧计时器.as` 初始化稳定的业务默认值：NPC 面积系数 300000、镜头死区容差 10；场景提示仍由 `StageEvent` 保留。

## Wire 与确认

命令沿用 `P{tier}|{softU100}|{quality}|{command}|{scene}`。只接收完整的五字段格式；旧二字段命令已退休。`quality` 允许 LOW、MEDIUM、HIGH、BEST，LOW 必须配 tier 1，其余配 tier 0。`softU100` 是 C# 档位指定的表现预算编码，不是 AS2 反馈控制量。

`scene` 是观察 epoch，场景切换或新连接时递增。每个 epoch 的命令编号为正整数；迟到命令被拒绝，同编号不能改变载荷。新连接允许命令编号重新从 1 开始。断连不改画质和表现预算；当前 XMLSocket 的对象身份守卫阻止旧连接回调进入桥。

只有执行器成功返回、实际 `_quality` 与目标一致后，才更新 `appliedCommand`。重发相同命令幂等；执行失败时不确认，允许重试同一个完整目标。执行窗口重置采样，避免把修改前后的帧时间混合为新目标收益。

采样沿用 v2 的 15 字段形状：

```text
fps|hour|tier|scene|v2|frames|ms|longFrames|maxMs|preset|quality|held|paused|seq|appliedCommand
```

`preset` 只保留格式兼容，不是 Host 策略权威；`held` 固定为 0。`quality` 与 `appliedCommand` 是 AS2 执行状态，仍不能证明 Host 尺寸交接已完成。

旧存档的 `性能等级上限` 保留原读写 schema，但性能桥不消费它。旧关卡 `PerformanceControl` 只展示 Message，Action/Level/Steps/Duration 不再调档。

## 验证入口

运行 [render-schedule focused runner](../../../../../run-render-schedule-tests.ps1)，取得当前 `RenderScheduleBridgeTest` 新鲜行为、Compiler 0/0 和零 32K 重试。断言数由 runner 维护。套件覆盖采样、断连不调档、重连/换场隔离、命令重复与迟到、执行失败不确认、四种画质、业务参数隔离及旧关卡提示。

随后用 `scripts/compile_test.ps1 -Target publish` 编译逻辑注入产物，部署前按 [Flash 验证合同](../../../../../../agentsDoc/testing-guide.md#as2) 核对单一类归属。真实尺寸交接、实际预设观感与实机性能必须由 Host 候选验证和人力验收补齐。
