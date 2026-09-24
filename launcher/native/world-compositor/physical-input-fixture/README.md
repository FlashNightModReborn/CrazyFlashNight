# C1 前置：物理输入来源只读观察

这是独立 WinForms 诊断进程，不是 C1-I 或游戏候选。人工入口不加载 Flash、Web、NativeHUD 或玩家数据，不注入输入、不吞输入、不设 capture、不恢复焦点、不授予业务输入。唯一显式机器对照参数 `--injected-control` 会在本进程窗口为前台时注入两对 Ctrl（虚拟键与扫描码）；人工 runner 不传该参数，identity 会记录 false。

独立消息线程注册 WH_MOUSE_LL、WH_KEYBOARD_LL 及 mouse/keyboard 的 RIDEV_INPUTSINK。hook 只写有界内存记录，磁盘记录由 UI timer 消费。只保留鼠标按钮和 Ctrl/Shift/Alt 的边沿；不记录普通键、文字、剪贴板或输入内容。记录来源标志、系统时间、QPC、短期设备句柄及前台 HWND，方便核对同一次刺激；数据有界溢出显式记录，不能当无丢失证明。

快照仅在**本进程窗口为前台**、当前输入 desktop 与线程 desktop 名称一致、打开 input desktop 取得所需权限、Raw Input 登记仍指向该线程窗口、非交换鼠标配置时尝试。两次完整状态快照与观测前缀必须一致，相关输入队列不能有待处理消息。外部窗口的边沿仍观察，但外部前台时不采纳 GetAsyncKeyState 的零值。模型一旦进入 Unknown，不靠一次 Up 或反复零值自动宣称恢复；此诊断尚未实现完整恢复协议。

这些条件只是需审定的采样资格，**不是 OS hook 连续性证书，也没有提供可用于生产 grant 的证明**。仅安装成功、Raw Input 注册存在、零记录丢弃、双快照一致都不能单独证明 S4 通过。`PhysicalInputLedger` 是被本工具实际调用的纯状态机；6 项模型测试不认证其 Windows 适配器。

构建使用仓库 exact SDK，输出到单独 candidate/bin；候选清单固定 EXE/DLL/deps/runtimeconfig 哈希。`run.ps1` 只校验并运行候选，不偷偷重编，保存到候选目录的独立 evidence 子目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/physical-input-fixture/run.ps1 -CandidateRoot tmp/r9-physical-input-candidate-20260923-v2
```

人类只需在观察窗口内按住左键，Alt-Tab 切出后释放，再返回；随后普通点击左右键，短按 Ctrl/Shift/Alt，最后用关闭按钮退出。不要输入文本、改系统设置或进入游戏。机器读取 `identity.json`、`observations.jsonl`、`summary.json`，人类不需要判读计数。

自动 CUA 对照证明：本机注入鼠标也产生了 Raw Input 记录，LL 注入位为 true。**不能把 Raw Input 出现直接等同于物理硬件，LL 未标记 injected 也不单独认证硬件来源。** 初轮未采 generic VK_CONTROL/VK_SHIFT，补采后又增加所有 LL 键盘回调的无内容计数；后续在没有其他窗口测试并行时复测，CUA 与探针直接调用 Win32 SendInput（虚拟键、扫描码）仍只有 Raw 修饰键记录、键盘回调 0。此异常未归因，S4 保持未通过；原记录与预期断言失败保留，不称通用修饰键覆盖已通过。

只有明确由人操作的样本能补本轮自动注入无法给出的来源对照；它用于区分注入路径与真实操作时的观测行为，不代签 S4、C1、IME 或整个游戏。关闭窗口输出 summary；自动测试可向 exact 本轮 evidence 创建 `stop.request` 请求该进程正常退出，不按名称清理其他应用。

## 人工回执后的版本

上述是 v2 冻结入口的状态。`20260923-221226-416` 已取得人工样本，原 DLL/日志保留；不需重复采样。当前源码增加 Raw 修饰键 shadow、严格左右/设备 held 跟踪，并区分快照竞争与真正源失效。`--injected-control` 还显式触发一次 pending 标志故障控制（记录 forcedPending 与 actualDrained），检查后续恢复；人工 runner 不启用。

复数入口：`python analyze.py CANDIDATE_ROOT RUN_DIRECTORY OUTPUT_JSON`。工具校验实际候选身份、展开 Raw 鼠标复合 flags、规范化修饰键并匹配时间/键/方向多重集；历史 rejected 仍是 rejected。人工原件的受控归档、24 项 focused tests 及新诊断变体的实际运行范围见 [R9 报告 §5](../../../../docs/reports/统一输入-R9前置修补与物理来源采样-2026-09-23.md#5-人工采样回执与后续修补)。Raw shadow 不认证全部输入或 OS 连续性，也不发 grant。
