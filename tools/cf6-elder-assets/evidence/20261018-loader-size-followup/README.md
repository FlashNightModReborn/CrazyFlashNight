# C6 加载器大小门修复与补充验证

本包承接 `dabd11a89570125b6fe2125aa45b5ccaf2d60cd2` 的 CF6 校准提交，修复该提交触发的 AS2 CI 失败。父提交已有相同的通信函数体 60,668 B，超过现有 60,000 B 门槛；未提高或跳过门槛。原失败日志和父产物比较保留在本包。

`frame3.as` 沿 Agent 注册边界拆为 `f3_1 → f3_2`，仍在同一 S1 阶段同步执行。相对拆分前的同一主线源码，函数体按原顺序拼接相同，没有跨段顶层局部变量。CS6 本轮发布 `0 错误／0 警告`；两段 45,559 / 15,472 B，全产物最大 53,041 B，生产闭包 715 个 SWF、728 个类的归属检查通过。[改动及字节码范围](records/change-analysis.json)同时保留“近墙门不能单独排除 UI16 回绕”的边界。

727 个既有编译类动作与 C5 相同，ServerManager 随此前已合入主线的只读终端状态白名单更新；Agent 的既有终端兼容源码也编入本轮。战斗源码、AI、资源和数值保持 C5 校准版本。C6 为 `scripts/asLoader.swf`，SHA-256 `ff9290d7918bccda94cf7e0c98517b0f234c5a3236a104d433d1e77f45004b70`；实际执行 Host 仍为 R4 隔离候选，身份与全部绑定见[机器汇总](summary.json)。

- 新鲜 BootSequencer 91 项、BootstrapHandshake 12 项，共 103 项通过，零失败、零 32K 重试；原测试入口恢复，原编辑器保留。
- [大头 6 场](head/integration-summary.json)：30／60／99 级，双方各一次，6 胜，无超时。
- [老头 12 场](elder/integration-summary.json)：60／80／100 级、两个对手、双方各一次，0 胜、12 负，无超时，逐场恰好交接一次。
- [9 次实际启动](records/boot-proof/summary.json)各自绑定原始诊断档案哈希和当前宿主区间，启动事件顺序与既有 golden 相同。私有原件保留在本机，本包只含相应启动消息原文及来源位置。
- 存档保护、候选资源一致性、退出和显示观察均通过；最后一场结束后立即释放临时唤醒。

另保留 [原批次未通过的分片](elder-primary/coordinator/experiment-report.json)及[具体分析](records/failed100-assessment.json)：100 级兽王分片在对战请求的所有权探测处失败，未取得结果；保护与退出核验后，另用[新隔离会话](elder-retry/integration-summary.json)完成缺失两场。原批次的“不合格”状态未改写，也未放宽门禁或重用旧会话。探测进程未返回有效结果的底层原因仍未知，不以补跑通过声称该工具问题已修复。

这 18 场是 C6 加载器集成验证，不代替 [C5 完整 18＋36 场强度校准](../20261017-calibration/summary.json)。C5 的 4,773 个索引文件逐项校验未变；旧包中的当前目录检查需要其原 C5 输入，不能拿更新后的 C6 目录回填旧证据。没有执行正式 runtime 发布，也不代签标准入口、物理音频、玩家手感或弱机性能。

冻结检查：在仓库根运行 `python -X utf8 -B tools/cf6-elder-assets/evidence/20261018-loader-size-followup/verify-followup.py`；交付当时的 C6 工作树可追加 `--check-current`。实际编译源码保存在 [源码原件](records/actual-as2-source.zip)与[逐文件身份](records/inputs-before.json)，复现使用原件字节。大于 8,000,000 字节的采集项按 `lossless-mapping.json` 无损还原，全部文件按 `integrity.json` 核验。该包在提交前封存，commit／push 和远端 CI 结果以随后 Git 历史为准。
