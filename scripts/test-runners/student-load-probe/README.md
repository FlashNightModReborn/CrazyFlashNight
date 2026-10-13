# 资源夹具阶段探针

`powershell -File scripts/run-student-load-probe-tests.ps1` 仅验证两个已发布库的加载/清理、DepthManager、各一个原生实例初始化与起始状态调用。逐阶段 trace 定位同步中止点；它不代替 70 实例完整时间轴、位图、视觉或战斗验收。

默认 `-OwnedReadOnlyHost`，要求没有已有 Flash；只使用可丢弃 TestLoader。它不读取真实玩家槽位、不写存档，异常/缺回执保持失败。进程、源原件、外来文档保护及恢复的唯一合同见 [CS6 自动停止](../../FlashCS6自动化编译.md#read-only-player-recovery)。不要为了类归属局部迭代重复运行该资源大闭包。
