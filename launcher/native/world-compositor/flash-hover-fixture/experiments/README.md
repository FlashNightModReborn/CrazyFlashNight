# R8 capture 观测及已否决试验

此目录不是生产实现或可发布 native 补丁。`capture-observation.patch` 只增加目标 UI 线程的 capture API 进入/返回与取消前快照；其他线程仅计数。`capture-revoke-rejected.patch` 在观测版之上尝试一次虚拟 capture 对称撤销。有效运行仍缺返回第一击的 press，**不得合入生产或据此开放 C1**。

`capture-sources.json` 记录本轮生产输入、观测版、被否决试验的六文件字节摘要。补丁以 UTF-8/LF 表达文本差异；实验修改过的 CPP 在当轮构建时为 UTF-8 无 BOM / CRLF。复原时使用独立的 `tmp` 源目录，核对摘要，再通过现有 `CF7_WORLD_COMPOSITOR_SOURCE_DIR` / `CF7_NATIVE_OUTPUT_DIR` 构建；不要在生产源目录应用。未修改文件保持原字节；观测版只对 `InputBridge.cpp` / `InputBroker.cpp` 统一 CRLF，撤销试验只再次改变 `InputBridge.cpp`。

观测记录沿用隔离诊断 ring 的 56 字节布局，不更改生产 v4 ABI。stage 14/15 为 SetCapture 进入/返回，16/17 为 GetCapture，18/19 为 ReleaseCapture；sequence 为本次 capture call ID，epoch 保留输入 epoch，message 为线程 ID，point 两半保存参数/返回 HWND，focus 字段保存真实 capture，floor 位 0/1 为 mapped/virtual-held。试验增加位 2 为 revoking（broker 文本没有单独打印该位）；stage 20 为取消前快照与非目标线程调用计数，21/22 为合成 WM_CAPTURECHANGED 的前/后边界。**这些不是普通 pointer packet sequence，不可混入业务交付统计。**

试验只在确实持有虚拟 capture 时发送失捕获通知，撤销期间提供中性的鼠标查询视图。没有合成 MouseUp、重放点击、夺真实 capture 或循环抢焦。直接原生宿主中出现真实 CaptureChanged 是机制线索，不能证明补同名消息即可清掉 AVM1 私有按下状态。

运行对照、无效设置轮次与结果见 [R8 报告](../../../../../docs/reports/统一输入-R8取消机制判定与协作域-2026-09-23.md)。在已有反例下本分支停止；后续研究完整协作域，不继续枚举 native 消息和时序。
