# 自有线程 Hook 路径诊断

用于区分本机 DLL 装载、导出解析、`SetWindowsHookExW` 注册失败。只创建一个自己的隐藏子进程消息队列；对其 exact TID 依次尝试同 SHA 的正式路径、候选路径、全新短路径副本、正式路径，然后立即解除 hook，正常投递 `WM_QUIT` 并核对进程退出。

不创建全局 hook，不操作 Flash、真实窗口或存档，不清理他人 hook。短路径副本和全部结果保留；任何成功只属于自有线程注册，不代表候选游戏启动或实际输入已通过。

用仓库锁定的 SDK 构建本目录项目，运行参数为两个 `FlashInputBridge.dll` 绝对路径和新的证据目录。两个输入必须 SHA 相同，进程必须为 x64。报告区分 LoadLibraryEx、InputHook 解析和 Hook 注册的独立结果与 Win32 错误；`status=observed` 不意味着所有路径成功。
