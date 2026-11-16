# Issue #262：主线整合、Windows 复验与正式发布

源码已对齐 `1b7a18b2ae6353399e2091db1359909df35cb7a4`；其相对已验业务基线 `650334df52b8d56b4c3b1caf9dabf8906e2409f8` 只更新现役旧底座的 DLL、manifest 与 consensus，三份 SWF 和业务源码未变，也不复用该底座签名票作为 Tooltip 发布证明。本轮源码/候选验收完成；正式发布状态和精确身份以[发布回执](../evidence/issue-262-tooltip-release-20261116/release.json)为准，不从候选结果推定已部署。

## 整合与真实 Flash

保留最新 Lady 资产、装备插件方案 B 的已清理快照、真实 mod 测试及新无人值守线束。材料字典、Tooltip catalog 和模块排除表由现役生成器重建。角色配装夹具直接注册的电脑芯片补调用正式 `ModRegistry.validateModHitBehavior`，继续要求巨兽需求由 30 降为 27；不改生产计算或放宽断言。

三方合并曾把上游两行修改带入只读 oracle 归档；已按原 manifest 所钉住的 `db6d3d248b...` Git blob 恢复，69 份归档原始哈希重新通过，未改 expected 或基线哈希。主线运行期的对应改动及独立采集仍保留，不能把归档复原外推为回退生产代码。

三份 SWF 均为本轮 CS6 新鲜发布，Compiler 0/0。实际类数从当前主线的 **1 / 340 / 466** 变为 **1 / 340 / 431**；boot **4,017,125 → 3,835,511** 字节，Tooltip DoInitAction **189,231 → 18,993** 字节。源码闭包、全部生产 SWF 类归属、继承次序及三个函数大小门通过。最新六组线束/原生交互/角色配装/警棍/弹药/真实 XML 数据回归均为 fresh 0/0、32K retry 0；背包、调制和灰蛊的未变领域也已有本轮新鲜通过记录。

## 内容与 Host

原完整 5,723 条内容配对保留其原始基线和超时历史；当前 catalog 变化另由真实 AVM1 补采 **180 条、零差异**，相同输入通过 Windows 正式 TooltipService，Node/ClearScript 一致。新增主线未改变该内容实现、计算器或 catalog 输入。bundle 为 307,048 字节，SHA-256 `C70BC251824A7BAAE8A8B31B6441BA761EB90386FADB4781F5368B8A66B20885`。

主线 92ecd9 上全量 Host **8,527 passed / 31 skipped / 0 failed**。随后仅派生数据更新的 650334 上全量有 112 项因输入计时变化取消；同一 Core/Test SHA 与 MVID、同一 source-inputs 下的 **128/128** 受控重验精确覆盖全部取消项，剩余失败为零。该结论为全量加定向覆盖，不称作 650334 单轮全绿；两条既有重复 theory key 单列，不以重试堆高通过数。

## 实际候选与边界

生产 Core `79151863DA64D8A4F855A5FA447F1AD152C12B8E174A558EE6FE0D11A8FD2799` 的隔离候选完成入场、移动、help/modifier/settings/调制台、多面板关闭、保存退出和重启读回。实际 WebView2 的 K 点商城固定检视器显示真实属性、三阶路线及获取来源，显式关闭、面板关闭和新 panel instance 重开均通过；本机 PNG 已检查。测试只在专用克隆档中执行，没有结账，临时加购后移除。288 份原有存档及相关文件逐一未变。

一轮可见采集工具和窗口辅助器超时，失败单独保留，不代签悬浮/物理输入或 NativeHud 全覆盖。后续固定检视器资格来自现役受控 WebView2 DOM/PNG 链；合成事件不算人类键鼠。GameInput 帧尾、全部消费者和完整战斗体验继续按专项验收，供应链与本轮限定旅程不扩大其结论。

同机两个新 Core 进程对同一专用来源档进行了基地/调制台各六次内存采样，未观察到本轮内存上升。完整数值和背景负载、缓存及单样本限制见[预发布机器回执](../evidence/issue-262-tooltip-release-20261116/preflight.json)，不据此宣称稳定或单因果性能收益。

## 发布与恢复

授权范围为提交推送、独立双构建、唯一 writer 推广、部署审计和标准入口复验。使用新的不可变 `runtime-build-v2/20261116-tooltip-content-v1`；不得沿用旧候选 policy 或其他功能的签名票。发布回执完成前维持 pending。最终运行库回退使用该轮 promotion 保留的 previous bundle；Flash/源码按已提交的三份 SWF 与原始 Git 历史恢复，不能混用运行库回退代替资源回退。本批继续为 DEV / UNSTABLE。
