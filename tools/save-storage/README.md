# Flash 存盘环境与文件提交回归

本目录验证存盘环境护栏及新进程 SharedObject 读回，运行资料写入显式 evidence 目录，不使用玩家槽位。

1. 在 evidence 目录写 `request.json`，内容为 `{"phase":"ready"}`，以 Node 启动 `probe-server.js <evidenceRoot>`。服务仅监听本机 `127.0.0.1:47183`，只能使用 `cf7_env_probe_<16 hex>` 测试槽。
2. 执行 `scripts/run-save-storage-probe-tests.ps1`，取得本轮真实 CS6 Compiler `0/0`、新鲜 TestLoader SWF 和唯一 ready block。这只证明探针已编译/就绪。
3. 在 .NET 10 的 PowerShell 7 宿主执行 `run-flash-backend-probe.ps1 -CoreDirectory <含 Core 与依赖的目录> -EvidenceRoot <evidenceRoot>`。驱动加载该目录的实际 `ProcessManager`，分别写入与启动另一个 Flash 进程读回；报告绑定 Core、播放器、SWF、SOL 的 SHA-256 及不同 PID。
4. 默认对照使用本目录下的 SUBST 盘符别名，退出时只解除自己建立的映射。它与原目录处于同一卷，不是跨卷负例。`-ParentTempDirectory` 可指定事先准备并归属明确的测试目录/测试卷；该参数不创建或格式化卷，也不提权。

驱动保留自己的 SOL 证据副本后，仅清理本轮随机测试槽和恢复父测试进程环境。Node 服务由启动者按记录 PID 结束。新进程读回是 Flash 后端的组件证据，不替代生产 Launcher 的建角、保存、删档与退出链。

当前本机记录：正常护栏写入与新进程读回成功；SUBST 与无效 TEMP 路径对照均未复现已知真实跨卷故障，不能拿它们宣称跨卷负例通过。独立测试卷的创建需要本机额外权限，未创建、未格式化。已知现场 A/B 仍以 `docs/存档写盘失败-TEMP跨卷根因诊断与处置-2026-09-30.md` 为准。
