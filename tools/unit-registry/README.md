# 单位注册表与语义引用

此目录提供单位引用的离线校验和兼容回归。身份唯一真源为 [units.json](../../data/units/units.json)，字段职责归 [数据规范](../../agentsDoc/data-schemas.md#单位身份与可读引用)。

## 支持边界

- `key` 可写作 `cf6.特种兵.二阶段` 或 `堕落城.左轮`，不能由重名的 `name` 自动反查。
- 普通关卡 `Enemy.Type`、波次 `SubDialogue.Type` 与事件 `Event/Dialogue.Type` 单位引用在 AS2 加载边界解析；运行描述中的 Type 规范化为 `兵种N`，属性仍从原兵种库克隆。
- 元战队、单位参数预设、选关情报和数值工具读取同一注册表。随机分支的静态分析只枚举候选；选关情报仍不展示条件/秘密出场。
- `build-book-definition.py` 在原玩法校验前解析校园地图敌人池、校园增援池、CF6 波次和 Boss 增援/后继阶段引用；输出仍为原数字或 `兵种N`。`Parameters` 内任意业务字段不被递归改名。
- 竞技场权威数据、Host 命令、Web 保存阵容与赛程码保持原格式。本轮不把所有字符串字段升级成可接受语义键的接口。
- 现役 475 条单位已全部登记稳定 `key`，全部 198 个关卡 XML 的 8,097 处直接/分支引用已全部迁移为语义键；`--require-all` 同时强制校验全量单位均具备语义键且已扫描范围无遗留 `兵种N` 引用。

键限制为 96 个 BMP 字符以内，至少两个非空点分段。首字符必须是拉丁字母或 CJK 字符；其余允许拉丁字母、数字、CJK、下划线、短横线，后续分段另允许中点 `·`。拒绝空白、引号、路径字符及 `__proto__`、`prototype`、`constructor` 分段。精确大小写，不通过展示名称、linkage、修剪或大小写转换兜底。JSON/XML 均直接保存 UTF-8 中文。

## 维护入口

- Python：[unit_registry.py](../unit_registry.py)，`UnitRegistry`、`preserve_unit_key`、`normalize_book_units`。
- JavaScript/TypeScript：[unit-registry.js](../lib/unit-registry.js) 与对应类型声明。
- AS2：[UnitRegistry.as](../../scripts/类定义/org/flashNight/arki/unit/UnitRegistry.as)，由兵种 loader 初始化独立索引。旧类型的实际存在性由 `StageInfo` 对真实 `_root.兵种库` 复核。
- 共享正反例：[cases.json](cases.json)。涉及语法变化时三侧同步；Node/Python 测试不模拟 AVM1。

生成器调用 `preserve_unit_key(candidate, current_units, new_key=...)` 保留目标记录身份、去掉模板继承的 key，并要求新增记录有明确新键。现有已接入工具见 CF6 Wings、蛮蛮、大刀机器人、特种兵、保安和大头机器人配表脚本；其他新增/维护单位的工具按此合同接入，不推定未核对的历史导入脚本已经支持。

## 离线验证

从当前检出根执行，PowerShell 先 `chcp.com 65001`：

```powershell
node tools/unit-registry/test.js
python -B -X utf8 tools/unit-registry/test.py
python -B -X utf8 tools/unit-registry/validate.py --require-all
node tools/derive-arena-meta-teams.js --check
node tools/derive-arena-unit-param-presets.js --check
node tools/derive-arena-unit-catalog.js --check
python -B -X utf8 tools/derive-stage-select-intel.py --check
python -B -X utf8 tools/build-book-definition.py --check
```

`validate.py` 默认对比 Git `HEAD`，检查工作区不删除旧 ID、不改写已有 key、新增 ID 不占旧空缺且具有 key，并扫描各关卡 Enemy/对白的直接 Type、Type 内字面 Case 分支和上述书籍刷怪字段；不将任意历史私有 schema 视为已支持。比较一组已提交改动时传入 `--baseline-ref <实际基线>`，避免把改动后的 HEAD 当成迁移前基线。

数值反查消费者改动另运行 `tools/cf7-balance-tool` 的 `packages/xml-io/tests/monster-flags.test.ts` 与相应 TypeScript 检查。配表写回改动运行各脚本默认只读检查；不以 `--write` 掩盖无关面板漂移。生成输入变化按对应生成器再生并重跑 `--check`。

选关情报和 Host 权威摘要包含原始输入字节。独立检出的换行可能使原有摘要过期；先记录基线，再按本检出真源再生，并比较敌人/奖励内容是否变化。不要为通过检查改弱摘要规则，合并后在目标检出重跑生成器。

历史 `RandomType` 的竞技场投影仍只采用第一条数字类型，与原目录一致；本轮没有扩展或重新设计该备份格式，也不借身份迁移增删历史队伍。新语义引用仅识别直接 Type，`Parameters.Type` 不充当引用。

## 真实 Flash 验证

确认共享 CS6、编译任务与 scratch 已可使用之后，执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-unit-registry-tests.ps1 -TimeoutSeconds 240
```

该入口使用现有 focused runner 的 mutex、持久备份、nonce 和恢复协议，测试重复身份、旧/新键属性等价、模板克隆、内联/对白、失败重载、真实 LiteJSON、CaseSwitch 和混合波次。成功阈值只以 runner 与本轮实际输出为准；当前机器占用时不运行，不以读取旧 trace 代替。

源码装配需先执行 `node tools/assemble-collapsed-frame.js`、其 `--check` 与 BOM 检查；正式逻辑产物归 `-Target publish`。发布后再核生产消费者，保留 `compiled`、候选执行、游戏验收、正式发布的证据边界。源码完成不意味着本检出既有 SWF 已包含解析器。
