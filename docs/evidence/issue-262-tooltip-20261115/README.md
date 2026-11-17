# Issue #262 云端回执

- 最终代码 commit：`3a2f434ceea4c0a07bad3a915bd314921f0f6863`。
- 性能原始测量对应 Gate C commit：`cb9a3e0a72b6508c60f1855ecfd55fc33735cdc0`；后续响应 schema／提示文案修补未改内容引擎、调度器、目录或基准函数，未冒称重跑性能。
- [metadata.json](metadata.json)：环境、代码边界与最终资源 hash。
- [checks.json](checks.json)：确切命令、原退出码与分类。`BASELINE_FAILURE` 和 `UNAVAILABLE` 不是 PASS。
- [source-closure.json](source-closure.json)：40→5 登记类的精确名单、净减 35、源扫描口径。
- [Host 汇总](../../reports/issue-262-tooltip-host-receipt.json)：34 项真实 C#／协议测试、生产 Task 链接范围、打包与性能。
- [Crafting 基线比较](crafting-contract-baseline-comparison.json)：起点与候选 24 个锚定函数无变化，既有 buildPlan 契约失败保留。
- `*.log` 保留命令原输出，包括负例日志、编译 warnings、浏览器环境失败与文档巡检既有债务提示。只按退出码和具体验证边界读结论，不能以日志中某一个 PASS 字样替代整体结果。

输入 JSONL 和两份约 3.54 MB 输出可按[复现步骤](../../reports/issue-262-tooltip-migration.md#8-最小复现命令)重新生成；目录/bundle/input/output SHA 已记录，不把合成输入输出登记为 AVM1 oracle。这里没有新鲜 Flash/CS6/Windows 运行、UI 截图或部署证据。
