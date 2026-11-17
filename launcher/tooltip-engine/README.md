# Tooltip 内容引擎

本目录是 Tooltip 文案、格式和 `TooltipDocument v1` 内容的生产 TypeScript 实现。主入口同步返回结果，不接触主机对象、文件、网络、时钟或游戏状态；Node 与 Launcher 的独立 ClearScript V8 使用同一份编译产物。

```ts
TooltipEngine.buildTooltip(input: TooltipInput, catalog: TooltipCatalog): TooltipDocument
TooltipEngine.buildProjection(input: TooltipInput, catalog: TooltipCatalog): {
  document: TooltipDocument;
  introHTML: string;
  descHTML: string;
  details: string;
}
```

`details` 保留原 ChoiceReward 的规则：完整内联简介 + 完整内联描述，经过原 `StringUtils.htmlToPlainTextFast` 的实体、换行与空白处理，再截取前 4,096 个 UTF-16 code units。它不使用 Web 为兼容出口重排的描述片段，以免重排文本或重复暴击/Buff。HTML 兼容出口和语义文档共享这里的内容规则。Inventory 继续保留内联 Buff；Native/Web 文档按原入口拆分 Buff、暴击斩杀、配件、战技等子面板。Web 的旧 `descHTML` 保留拆分主体与子块拼接顺序。

## 数据边界

`src/contracts.ts` 定义外部 DTO。静态配置内部保持动态属性袋，因为原始 XML 的装备、插件和效果结构并不统一；输入封装、分类、版本与受限传输标记在入口校验。

| 数据 | 生产来源 | TypeScript 职责 |
| --- | --- | --- |
| 名称、描述、图标、插件说明、配方与材料引用 | `data/tooltip/tooltip-catalog.json` | 查表与展示 |
| 装备最终属性、涂装、技能、生命周期 | AS2 真实 `BaseItem.getData()` 的字段白名单 | 直接展示，不复算 |
| 品阶覆盖后的基底属性 | AS2 `TooltipDataSelector.getEquipmentData()` | 展示基础值及差值；任何有 `data` 且不是药剂的物品均需要此投影 |
| 已安装插件的注册状态、已匹配 use/bullet 分支及有效技能 | 原 `ModRegistry` | 消费匹配结果，不重做资格或条件选择 |
| 独立插件的 registry key | `projection.registeredModName`，未注册为 `null` | catalog 中存在定义也不能重新发布被 AS2 拒绝的插件 |
| 电力标签、刀口数、纵向联弹标记 | 原 TagManager / Flash 资源探测 / BulletTypeUtil | 直接读取窄结果 |
| 药效、副武器 | 原 normalizer 的规范化结果 | 文案生成，不再规范化业务配置 |
| 可用升阶选项 | 原 TierSystem | 展示已投影的 available 状态 |
| 获取来源 | 当前存档发现集合的窄投影 | 保留顺序与名称；不能替换成全量静态掉落表 |
| 技能、HUD | 已授权当前快照 | 状态和资源提示文案，不判断施放资格 |

基底数据、最终实例数据是两个不同输入。`projection.displayName/iconName` 仅用于 Inventory 原本显式传入文档的身份，不能覆盖旧 `introHTML` 的基础标题。

生产物品输入的最小形状如下，具体可选字段见接口文件与 AS2 `TooltipInputProjection.as`：

```json
{
  "version": 1,
  "kind": "item",
  "itemName": "物品名",
  "value": {"level": 1},
  "presentation": "native",
  "projection": {
    "isEquipment": true,
    "isMaterial": false,
    "isInformation": false,
    "calculated": null,
    "baselineData": {},
    "registeredModName": null,
    "tierOptions": [],
    "drugEffects": [],
    "mods": {},
    "obtainRecords": []
  }
}
```

`presentation` 为 `native`、`inventory` 或 `web`。其他现役输入为 `kind: "skill"`、`kind: "body"`、`kind: "hud"`，不保留退役的 tier/enhancement 调用 API。

每个已安装插件投影必须包含 `present: boolean`、`useCases: []` 和 `bulletCases: []`。缺少匹配或注册投影会返回明确错误。`present: false` 保留原 Builder 的名称/图标行，但不显示不存在的插件效果。引擎不会构造 BaseItem、调用装备计算器或模拟 `_root`；内部 `Instance` 只封装已提供的只读 `calculated` 值。

### AVM1 语义适配

`src/avm1.ts` 集中实现这次内容规则需要的窄转换：空值与空白字符串的 `Number` 转换、NaN 非严格比较、反向枚举，以及字符实体中的 NUL 处理。原字段读取返回 `undefined` 的位置使用可选读取，避免 JS 空值解引用异常。Formatter 原有的六位小数吸附策略继续用于消除显示尾差。

JSON 本身不区分所有 AVM1 数值状态。AS2 producer 使用精确单键标记传递非有限数值和数组空洞：

```json
{"__tooltipNumber":"NaN"}
{"__tooltipNumber":"Infinity"}
{"__tooltipNumber":"-Infinity"}
{"__tooltipUndefined":true}
```

入口先验证整棵数据树，再解码这些标记。标记带额外键、未知枚举或错误类型会报错。对象缺失字段仍省略；数组空洞恢复为 `undefined`。这同样覆盖 `skillData`，不把特殊数值显示为 `[object Object]`。

输入限制为深度 24、8,192 个节点、单字符串 131,072 个 UTF-16 code units、JSON 入口 262,144 个 UTF-16 code units；禁止函数、循环和原型污染键。目录只在初始化时执行完整校验与冻结，不在每次 hover 重新解析。

**仍需新鲜 AVM1 真值确认的范围：** 实际 XML/clone/LiteJSON 多次枚举后的字段顺序（尤其数字键）、不同寄存器来源的 NaN 相等性、数字字符串化与边界算术、当前真实装备组合、最终 Flash/Host/Web 视觉。这里的适配和源码断言不构成这些项目的实机验收。

## Resident V8 ABI

编译后的脚本只要求标准 ES2020 JavaScript，公开以下入口；不注入 .NET HostObject：

```js
TooltipEngine.initCatalog(catalogJson);          // 返回 contentVersion；成功后原子替换冻结目录
TooltipEngine.buildJson(inputJson);             // JSON.stringify(document)
TooltipEngine.buildProjectionJson(inputJson);   // JSON.stringify({document,introHTML,descHTML,details})
```

`input.output === "details"` 时第三个入口只返回 `{details}`。C# 应在单次内容请求中选择一个入口，不重复调用两个构建入口。`body.profile` 控制正文布局；Inspector 的 pinned 身份由宿主完成边界校验后设置，物品输入中的任意 `profile` 不承担此职责。引擎没有请求级全局状态；唯一驻留数据为冻结目录。输入验证失败、构建失败或目录初始化失败不会修改下一次请求的上下文。

## 构建与回归

复用 `launcher/scripts/package-lock.json` 锁定的 TypeScript，不增加第二套依赖。

```sh
npm ci --prefix launcher/scripts --ignore-scripts --no-audit --no-fund
node launcher/tooltip-engine/build.cjs
node launcher/tooltip-engine/build.cjs --check
npm test --prefix launcher/tooltip-engine
python3 tools/build-tooltip-catalog.py --check
```

唯一生产产物是 `launcher/scripts/dist/tooltip-bundle.js`。`build.cjs --check` 在临时目录编译并逐字比较，防止提交的 bundle 与 TS 源码漂移。

现有测试分开记录以下证据：

1. 把既有 `tools/tooltip-parity-corpus.test.js` 的 Document 断言运行在新实现上。缺少历史 `samples.json` 时仍明确记录缺失，不把旧记录当成新鲜真值。
2. `engine.test.cjs` 覆盖纯函数不变性、实例数据、格式边界、受限实体、特殊命中、药效、子面板、投影拒绝与失败后的请求隔离。
3. `source-regressions.test.cjs` 迁移 baseline `db6d3d248b80b80651987c99557c4e83b56f9301` 中已有固定内容预期：EquipmentIntervalCurve、WeaponAmmoData、EquipmentEmissiveAsset、SheriffArsenal、LongGunSubWeaponCore、ArenaDropRuleCatalog、CraftingPanelService。原领域计算断言继续留在 AS2；这些测试不复制计算器。
4. 当前目录全物品 smoke 与运行时对照使用合成窄投影，仅证明输入覆盖及 Node/ClearScript 同规则执行；不会生成“预期 AS2 输出”。

## 独立 oracle 差分入口

```sh
node launcher/tooltip-engine/parity.cjs capture.json --current <完整40位源码commit>
```

文件结构：

```json
{
  "schema": "cf7.tooltip-content-oracle.v1",
  "provenance": {
    "kind": "avm1-capture",
    "sourceCommit": "完整40位源码commit",
    "capturedAt": "ISO-8601时间",
    "catalogContentVersion": "可选；提供时必须与目录一致"
  },
  "records": [
    {
      "id": "非空唯一记录编号",
      "input": {},
      "expectedDocument": {},
      "expectedIntroHTML": "可选",
      "expectedDescHTML": "可选",
      "expectedDetails": "可选"
    }
  ]
}
```

上例只描述字段，不能直接作为有效捕获。实际 `input` 与 `expectedDocument` 必须来自同一个真实 AS2 实例/预览状态：候选投影采样输入，独立旧 Builder 采样预期文档。不能先运行 TS 再把结果写成 oracle。可用 `--catalog <path>` 对照与捕获相同的目录。

缺少文件时退出码为 **2**，状态 `oracle-unavailable`；差异、损坏输入或指定源码版本不匹配为 **1**。只有 `kind: avm1-capture`、`--current` 完全匹配且记录通过时，才输出 `fresh-avm1-match`；未确认当前版本的成功比较标记为历史证据。比较保留数组和 run 顺序、颜色、字体、图标、profile、layoutType 等完整字段，只忽略 JSON 对象属性排列。

## 相同输入运行时比较与基准

```sh
node launcher/tooltip-engine/fixtures.cjs /tmp/tooltip-inputs.jsonl
node launcher/tooltip-engine/benchmark.cjs --evaluate /tmp/tooltip-inputs.jsonl > /tmp/tooltip-node-output.jsonl
node --expose-gc launcher/tooltip-engine/benchmark.cjs /tmp/tooltip-inputs.jsonl > /tmp/tooltip-node-benchmark.json

dotnet run --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --evaluate <repo-root> /tmp/tooltip-inputs.jsonl
dotnet run --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --bench <repo-root> /tmp/tooltip-inputs.jsonl
```

`fixtures.cjs` 构造当前全目录 baseline，再加明确的合成实例、药剂、技能与 HUD 输入。它不复制任何业务计算、匹配或发现规则，也不提供 expectedDocument。若需要衡量真实实例负载，应替换为捕获的输入 JSONL。

Node 基准报告 VM/bundle 装载、目录解析校验冻结、首条请求、预热后的 P50/P95/P99、25/100 项批次，以及 GC 后进程 heap/RSS 差值。逐项耗时包含输入 JSON 解析、内容构建和输出 JSON 序列化；不包含 C# 排队、缓存、IPC 或 AS2 采样。内存差值含 V8/JIT 开销，不能当成精确对象保留量。报告记录目录、bundle 与输入 hash，可复现当次测量，不设无依据的性能门槛。
