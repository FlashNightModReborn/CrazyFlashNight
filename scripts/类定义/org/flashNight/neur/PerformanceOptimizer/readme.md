# Flash 性能桥

当前职责、协议与验证入口见 [Flash 性能采样与执行桥](PerformanceOptimizer.md)。C# 拥有性能调度；AS2 保留实测采样和明确目标执行。

本目录没有 PID、Kalman、前馈 hold 或断连后备调度。测试使用 `scripts/run-render-schedule-tests.ps1`，不依赖本机 TestLoader scratch 的既有内容。
