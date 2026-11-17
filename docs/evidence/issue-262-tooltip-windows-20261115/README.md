# Issue #262 本机证据索引

**文档角色**：Windows 实测回执摘要；完整原始日志保留在本轮隔离工作目录。

`results.json` 标明当前验证阶段。`as2-progress.json` 保存 21 组最新通过轮、原失败及未形成完整回执的尝试；最终三模块身份见 `candidate-modules-final.json`。

`host.json` 对应技能数组转换修正后的 bundle；`host-before-array.json` 和 `host-benchmark*.json` 是此前 bundle 的历史回执，基准不代表真实 Launcher 的净内存或 GameInput 开销。

`host-current-benchmark*.json` 绑定当前 bundle 的独立 Host 基准。`launcher-xunit.json` 保留整轮 8,569 项的真实计数，并核对需要资源窗口的五个失败类及 guard 源码均与原基线一致；没有修改 guard 或虚构输入锚点。

`native-policy.json` 是 release tree `d9885818…` 的 50/50 正式检查回执；`native-prepare-coverage.json` 绑定已验证的 27 项生成物。`native-open.json` 保存实际隔离候选的身份、运行路径和装备调制首份权威快照；`native-ui-observation.json` 与 `native-cleanup.json` 分别说明界面观察范围、测试进程退出和真实玩家存档保护。配件预览、全消费者实机覆盖与正式部署均未据此宣称完成。

`oracle-independent.json` 与 `oracle-parity.json` 绑定本轮完整 5,723 条独立 AVM1 记录、107/107 配件覆盖及零差异。`captured-windows-host.json` 说明同一份真实输入全部经过 Windows 正式服务，并逐行核对 Node／ClearScript 输出。

原始一小时脚本已超时，`oracle-canonical-timeout.json` 仍记失败。同一个 SWF 后续在独占观察守护下持续输出，严格转换及内容比对是单独结果，不能回填原脚本通过。身份连续性、退出与归档清理见 `oracle-observer.json` 和 `oracle-cleanup.json`。

`oracle-paused-diagnostic.json` 只是此前被重启中断采集的逐行诊断；恢复记录见 `oracle-reboot-recovery.json`。NativeHud/WebView2 全消费者、真实 GameInput 和物理专项仍未完整验收；单个层级的通过不代签其他层级或正式部署。
