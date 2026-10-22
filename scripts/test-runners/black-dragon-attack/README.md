# 黑龙普攻状态同步回归（Issue #154）

本目录验证一阶段骑马黑龙从站立发起普通攻击后，实际动画能否返回站立。生产修复只有 `things5/LIBRARY/Symbol 654.xml` 的攻击入口；公共同状态跳过规则保持原样。

## 快速检查

在仓库根运行 `node tools/test-black-dragon-attack.js`。它直接读取生产状态切换、动画收尾与 AI 攻击源码，执行 12 项参考模型检查。旧入口对照通过恢复那一条直接跳帧语句得到；这不是 AVM1 或时间轴证据。

`powershell -File scripts/run-black-dragon-attack-tests.ps1 -LegacyBaseline -PrepareOnly` 仅生成本轮隔离宿主、生产函数源片段和哈希清单，不写 `scripts/TestLoader.as`，不启动编译或播放器，可在等待 CS6 交接时执行。

## 真实 Flash 顺序

取得明确的 CS6/TestLoader 交接后串行执行：

```powershell
powershell -File scripts/run-black-dragon-attack-tests.ps1 -LegacyBaseline
powershell -File scripts/compile_test.ps1 -Target flashswf/arts/things5/things5.xfl -PublishOnly -VerifySwf flashswf/arts/things5.swf
powershell -File scripts/run-black-dragon-attack-tests.ps1
```

原版对照读取 `tmp/issue154-black-dragon/original/things5.swf`，只接受 SHA-256 `2091034D4278DE1C5435531F71F01C245BE4798D605E19B78B314E308D5AC8A9`。它来自修复前提交 `412d95cd6775fda91b8168c5d384a0447264890e` 的同路径资源。保留原件，不能用新发布产物替换；另一个 checkout 缺少该文件时从固定提交按二进制导出并复核哈希。

wrapper 复用现有 `ShootReloadNativeHost` 的最小宿主结构，在 `tmp/issue154-black-dragon/host/` 生成自己的 XFL，显式导入 `加载mc库-黑铁会`。宿主绑定实际 things5 中的黑龙、AI 和 54 帧普攻，不把并列加载 SWF 当作共享库导入。

`状态改变` 和 `动画完毕` 两个函数由 wrapper 从生产 `.as` 原文提取进带 BOM 的临时 template，不维护第二份实现。实际初始化、目标及弹体出口使用内存夹具，不进入存档、库存、掉落或交易。

用例覆盖站立左右、行走、跑动、攻击中移除目标、站立连续两次攻击，以及外部切到受击状态后的收尾。原版断言站立入口在两轮结束后仍循环，行走/跑动和受击状态改变可恢复；修复版断言八次攻击均在原生动作结束时返回站立。受击用例只调用状态入口，不声称覆盖真实削韧结算。

## 证据与边界

focused runner 负责唯一 runId、Compiler `0/0`、新鲜 trace、32K 零重试、函数尺寸、mutex 与 scratch 哈希恢复。原版复现和修复验证分别保留日志、源、宿主 SWF、库资源哈希；失败尝试不覆盖。跳帧调用栈内仍能短暂枚举即将卸载的 AI，卸载检查放在下一个真实帧。

测试完成后停止本轮播放器，并通过第二次控制回执确认没有遗留播放器；保留其他 CS6 文档，不退出编辑器。执行和恢复合同见 [CS6 自动化编译](../../FlashCS6自动化编译.md) 与 [focused runner 合同](../../../agentsDoc/testing-details.md#flash-recovery)。

本轮调查、原始失败和实际通过身份见 [Issue154 报告](../../../docs/reports/Issue154-黑龙普攻循环修复与回归-2026-10-22.md)。原生隔离回归不代替完整关卡、玩家视觉、正式 runtime 发布或标准入口验收。
