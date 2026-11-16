# Issue #262：Tooltip 异步服务与 AS2 内容闭包迁移

**文档角色**：本轮隔离施工的交付与证据边界；输入及消费者真源见[消费者矩阵](issue-262-tooltip-consumers.md)。

**2026-11-16 更新**：最新主线整合、真实 CS6 三模块、完整/定向 Host 覆盖、当前数据 AVM1 配对、实际 WebView2 检视器和正式列车状态见[整合发布记录](issue-262-tooltip-release-20261116.md)。本文第 9 节保留原云端交接时的验收缺口；未完成的全消费者物理体验和 GameInput 帧尾继续单列，不由候选或通用部署反推完成。

**起点**：`db6d3d248b80b80651987c99557c4e83b56f9301`。

**最后核对代码基线**：commit `3a2f434ceea4c0a07bad3a915bd314921f0f6863`（2026-11-15；云端源码候选）。

## 1. 结论与交付边界

已完成 Gate A–C 在 Linux 云端可实施的生产代码切流：AS2 冻结真实运行态，C# 独立常驻服务管理异步生命周期，TS 同步生成 Document 与兼容文字，原 NativeHud/Web 继续展示。生产类树不再保留旧 AS2 内容 Builder。三模块静态归属由 **1 / 338 / 464** 变为 **1 / 338 / 429**；原 40 个 Tooltip 登记类移除 36、保留 4、增加投影类 1，**净减 35**。

这是待 Windows 验收的源码候选。实际 Linux ClearScript、生产 C# 协议链、Node/Web 测试与交叉编译证据已经取得；新鲜 AVM1 内容真值、CS6 编译、Windows 桌面运行和玩家入口尚未取得。没有修改正式 SWF、部署 runtime、推送远端或覆盖其他工作树。

| 阶段 | 已完成 | 未据此宣称 |
|---|---|---|
| Gate A | 22 条现役调用链、领域依赖、最小输入、Flash 例外、69 文件旧源码哈希归档与配对采集工具 | 归档源码或采集工具单测已产生 AVM1 真值 |
| Gate B | 同步 TS 引擎、静态目录、AVM1 窄适配、既有固定内容预期回归；1,801 条 Node/ClearScript 相同输入对照 | 两个宿主执行同一规则就是 AS2 内容等价 |
| Gate C | 专用持久 V8 worker、生产路由/owner 接线、AS2 producer 切流、旧闭包裁撤、派生 manifest、打包完整性 | Linux 编译就是 Windows/CS6 或真实 UI 验收 |

## 2. 提交与复核方式

所有提交仅位于隔离分支 `work/issue-262-tooltip-20261115`，起点以上按功能拆分：

| 提交 | 内容 |
|---|---|
| `89c1c61f5a5ee285461ce0f6f039b1662a22f53e` | Gate A：消费者/契约、字节精确旧源码、配对 AVM1 采集工具 |
| `40d4ccfd4d642d1ba13dd2cedaa8e69889e16ece` | Gate B：纯 TS 引擎、静态目录、构建与源码回归 |
| `cb9a3e0a72b6508c60f1855ecfd55fc33735cdc0` | Gate C：C# 接线、AS2 裁撤、打包、生产 Task 协议测试 |
| `3a2f434ceea4c0a07bad3a915bd314921f0f6863` | 响应 exact schema 的收尾修复与真实 validator 回归 |
| 本文所在文档提交 | 最终日志、指标、未验证项与 Windows 验收清单；不改变运行逻辑 |

主线后续有变化时，应以上述完整起点做依赖对账；本轮未擅自合并其他施工。可复核 `git diff db6d3d248b80b80651987c99557c4e83b56f9301..HEAD`，详细命令/退出码见[checks.json](../evidence/issue-262-tooltip-20261115/checks.json)，代码与资源身份见[metadata.json](../evidence/issue-262-tooltip-20261115/metadata.json)。

## 3. 实现与权威边界

### 输入与内容引擎

`TooltipInput v1` 分为 `item / skill / body / hud`。展示身份仍在原请求信封：request/call ID、scene、owner、lease、revision、slot、panel/session 不交由 TS 裁决。静态目录由声明的 XML/JSON 清单生成，包含 **1,788 物品、107 配件、350 配方、85 技能、238 敌人显示名**。目录约 1.40 MB，bundle 304,982 B；启动加载一次，每次 hover 只传当前条目的窄投影。

AS2 保留真实 `BaseItem.getData()`、品阶基底选择、已安装配件的注册/条件匹配、有效技能、电力标签、药效与副武器 normalizer、当前已发现来源、技能资源状态。TS 直接消费结果；没有第二套装备结算、配件资格或掉落发现系统。实例投影失败不会偷偷替换成基础物品。

Flash 刀口数是明确保留的窄例外：有配置先读配置，否则沿用 linkage/显示列表探测、缓存与清理，只返回整数。没有开发 Flash 模拟器；离线素材烘焙尚未替换该探测。

`buildTooltip` / `buildProjection` 均为同步纯计算，无 I/O、时钟或 HostObject。Document v1、HTML 兼容出口与 Choice `details` 来自同一内容规则。已有 Document parser 资产与 C# sanitizer 继续复用。Choice 保留原“完整内联 intro + desc 转纯文本，截取 4096 UTF-16 units”的语义；Web 分段 HTML 不拿来反向构造 Choice 文本。

目录生成显式处理 XML 标量、重复节点、StringUtils 的有限实体表、物品 `cloneFast` 导致的字段顺序、列表顺序和重复命名。非有限数、数组空洞由严格单键 wire 标记保留；真正的 AVM1 数字键枚举、字符串化与复杂实例组合仍需独立真值确认。

### 调度与缓存

`TooltipService` 的专用后台线程负责创建、调用、销毁一个常驻 ClearScript 7.4.5 引擎。它不使用 GameInput 的 V8 或逐帧共享锁，不新增 GameInput 同步等待。每项输入校验、序列化和哈希为输入规模 O(n)；格式构建按读取的字段/效果/来源规模增长；队列节点淘汰、缓存查找与 LRU 更新为平均 O(1)。没有跨整个物品目录的逐 hover 搜索。

| 上界 | 生产默认值 |
|---|---:|
| 排队计算 | 64 |
| 在飞订阅者 | 128 |
| 结果缓存 | 256 条且估算存储 ≤16 MiB |
| 已完成 owner 的序号前沿 | 1024 |
| 原响应内 Tooltip 输入 | 1024 项 |
| 待增强原响应 | 32 包且合计 ≤16 Mi 个 UTF-16 字符 |
| 单输入 | 深度 24、8192 节点、序列化 ≤262144 字符 |

缓存键包含完整冻结输入及 scene/revision/lease；目录和 bundle 的 SHA 由服务实例固定，不能跨版本复用。同输入可合并，结果缓存存不可变 JSON，消费者各自解析。缓存命中也复核取消和 owner fence。缓存字节估算采用 UTF-16 字符存储加每条 512 B 的簿记预算，不冒充精确托管堆核算。

同 owner 最新请求淘汰旧订阅；普通 hover 与显式 Inspector 独立。取消不强行中断已运行的同步 V8，完成后再次判断是否仍有效。hide、压隐、切场景、断线、revision 回退和 panel binding 关闭覆盖请求退役；Native 最终完成边界保留受信 `pinned` profile。

15 个领域 resolver 读取既有 pending authority。`NoPending` 与合法但不需 hover owner 的回包分开：关闭/timeout 后才到的旧响应交原处理器丢弃，不计算整批旧内容。`stashChoices` 与 `stashTooltip` 使用不同 lane；批量逐项排队，避免 1024 项独占整个计算队列。

### 响应与失败

AS2 按原身份规则返回数据；Host 在原异步响应完成之前增强，无 Flash 阻塞、轮询、新回调状态机或逐项 RPC。增强后的 payload 仍须经过原领域 exact validator。内容失败只替换显示：非空不可用标题、正文或 details；不改 `success`、operationId、事务结论，不重放写操作。失败提示统一为“注释暂不可用。”；现有 Web 对成功业务响应的缓存仍可能保留该占位至面板或权威缓存失效，同 key 重新悬停不保证重试。本轮没有为此增加新的 wire 字段。

收尾复核发现并修复：缓存命中取消窗口、Choice 无输入时丢失 details-only 选择器、ItemUse 缺真实 owner、关闭后的迟到批次仍计算，以及调制台 Host、商城 Web 的旧 exact schema 未接受新增 Document；构筑 Web 在基线已存在的同类缺口也一并修复。具体测试范围和后续发现见[Host 回执](issue-262-tooltip-host-receipt.json)。

### 发版资源

Launcher 使用既有 project root 读取 bundle/catalog/manifest；启动核验目录及 runtime `data/**` 来源 SHA，玩家包无需开发 generator/AS2 源。prepare 和 policy 纳入生成及 `--check`，runtime-inputs 绑定新来源。

实际 packer 默认会 minify XML/JSON，曾使合法入包资源不再匹配来源 SHA。本轮为受完整性约束的 Tooltip 数据保留原字节；真实 copy/hash 回归覆盖 **123 个文件**。其他地图等数据继续沿原 minify 策略。完整 PowerShell 发布流水线未在 Linux 运行。

## 4. AS2 类闭包对账

| 模块 | 起点总类数 → 候选 | 起点 Tooltip → 候选 |
|---|---:|---:|
| resident | 1 → 1 | 0 → 0 |
| shared | 338 → 338 | 0 → 0 |
| boot | 464 → 429 | 40 → 5 |

| 原登记类保留项 | 必须保留的职责 |
|---|---|
| `NativeTooltipBridge` | requestId/sceneId、anchor/placement、坐标和 hide/teardown |
| `TooltipDataSelector` | 原 AS2 品阶基底选择，不搬动业务权威 |
| `ItemUseTypes` | 现役 EquipmentStatProjector 的领域词汇依赖 |
| `TooltipConstants` | 同一投影器仍使用的属性名、排序和六个标签；已从 30,373 B 收缩为 3,175 B |
| 新增 `TooltipInputProjection` | 真实运行态只读投影、wire 数值编码、窄刀口探测 |

以下 **36 个原登记类**退出生产闭包，前缀均为 `org.flashNight.gesh.tooltip`：

| 所属子目录 | 移除类 |
|---|---|
| 根（5） | `NativeTooltipDocument`、`SkillTooltipComposer`、`TooltipComposer`、`TooltipFormatter`、`TooltipTextBuilder` |
| `builder`（18） | `CommonStatsBuilder`、`CriticalBlockBuilder`、`DamageTypeBuilder`、`EquipmentLightingInfoBuilder`、`EquipmentStatsComposer`、`GrenadeStatsBuilder`、`GunStatsBuilder`、`MeleeStatsBuilder`、`ModStatBuilder`、`ModsBlockBuilder`、`ObtainMethodsBuilder`、`ResistanceBlockBuilder`、`SilenceEffectBuilder`、`SlayEffectBuilder`、`TagSwitchStatsBuilder`、`UpgradePathBuilder`、`UseSwitchStatsBuilder`、`WeaponAmmoInfoBuilder` |
| `builder/drug`（4） | `DrugTooltipComposer`、`DrugTooltipRegistry`、`DrugTooltipUtil`、`IDrugTooltipBuilder` |
| `builder/drug/builders`（9） | `BuffTooltipBuilder`、`GrantItemTooltipBuilder`、`HealTooltipBuilder`、`PurifyTooltipBuilder`、`RegenTooltipBuilder`、`ResistanceBuffTooltipBuilder`、`StateTooltipBuilder`、`ToughnessBuffTooltipBuilder`、`ToughnessRestoreTooltipBuilder` |

未登记的旧 Flash renderer/fallback、ArmorStatsBuilder 及纯内容测试同时退出生产目录，但不重复计入上述 36 类。仍有效的 Native bridge 与 Synthesis 测试移到各自领域；领域结算/属性断言留在 AS2，固定内容断言迁到 TS。focused runner 的旧 builder 路径和 Choice/Crafting 断言计数一并修正。

静态审计扫描 **2607 个 AS2 源/模板、235 个 PowerShell runner**，确认旧类无现役代码引用、每类有且仅有一个模块 owner、生产 Tooltip 目录恰为 5 个叶子、旧 oracle 不进入 classpath、必要 AS2 BOM 完整。69 个归档文件 SHA 逐项核验；其不可变历史空白由局部 `.gitattributes` 保留，不放宽新生产代码检查。

旧目录的 AS2 源字节 743,365 → 35,914，包含历史测试和未登记 renderer，**不能作为 SWF 字节、DoInitAction 动作或 CS6 内存收益**。本轮这些实编收益均未测量。完整类名、归属及口径见[source-closure.json](../evidence/issue-262-tooltip-20261115/source-closure.json)。

## 5. 消费端最终状态

完整 22 行矩阵包含 BaseItem 权威、同步用途、字段、lease/revision/owner 和切流位置，见[消费者矩阵](issue-262-tooltip-consumers.md)。这里汇总所有现役入口，状态均为“源码切流完成，未据此推断真实玩家入口验收”：

| 入口 | 最终内容路径 |
|---|---|
| Inventory、CharacterBuild | 真实槽位/装备输入 → 原 C# 响应 → Document/HTML |
| RewardInbox、LootContainer、结算 report、RewardStash | 原 exact 容器/记录身份 → 共用库存投影；嵌套节点增强 |
| EquipmentTuning | 静态候选输入 → Document/HTML；原 before/after stats 仍由 AS2 试算 |
| ChoiceReward | 原批量快照内 details-only 输入 → 原六字段行形状 |
| Merc、MercLoadout、Arena、Pet/ManagedLongGun | 原实际武器或合法预览实例 → 同一库存输入 helper |
| Crafting、Modifier、Task | 原允许的名称级预览 → 公共输入 |
| Shop、Intelligence、BlackMarket、NPC Shop | 原目录/会话授权；背包来源保留 exact 库存身份 |
| CharacterCreation | 同一 `richItemCatalog` 响应批量增强，Web 接收 Document |
| 场景物品、两种技能图标、通用正文 | 输入 + 原 Native request/scene/anchor/placement |
| PlayerHud | action/weapon/switch/resources/skill/drug 快照 → TS；资源资格仍由原服务决定 |

公共 `_root.Web物品注释HTML` 暂保留旧调用名，返回元数据、空内容占位和输入；所有现役调用者显式转发输入，没有同步等待其产出 HTML 的生产消费者。

## 6. 云端验证结果与未通过项

| 验证 | 结果与证据性质 |
|---|---|
| 目录转换/声明源 | 11/11；目录 `--check` 通过 |
| TS 编译/bundle | `--check` 逐字一致；37/37 Node 场景测试 |
| AS2 producer 投影 | 10/10，执行语法适配后的真实函数体 + 领域 stub；不是 AVM1 |
| 配对 capture 工具 | 14/14，源码注入和 trace 协议拒绝测试；未运行 Flash |
| Web Document / binding / consumers / CharacterBuild | 70 / 14 / 12 / 6 个检查通过；建角 Document 定向回归通过 |
| Linux Host | 34/34；直接链接生产 Native、Inventory、ItemUse、EquipmentTuning Task 及真实 validator |
| Web 严格响应链 | CharacterBuild Session 43/43、KShop Protocol/Presenter 41/41 |
| Node ↔ ClearScript | 1,801 条输入输出逐字相同；两份输出各 3,541,757 B |
| 完整 Service corpus | 1,801/1,801 经生产输入验证、V8、sanitizer、cache；末尾 256 条缓存 |
| 打包 | 实际拷贝后 123 文件 SHA 相同 |
| Windows target 交叉编译 | 54 warnings、0 errors，14.68 秒；仅 Linux 编译，未执行桌面进程 |
| AS2 静态闭包/asLoader 派生 | 通过；不等于 CS6/AVM1 编译 |
| BOM/差异/文档 | 39 个本轮改动 AS2 文件 BOM 完整；差异和文档治理最终回执见检查目录 |

**独立 AVM1 parity：未取得。** `node launcher/tooltip-engine/parity.cjs` 返回 `oracle-unavailable`，exit 2，compared=0。未找到可用于本基线的 paired corpus；现有 parser 固定断言与历史测试源码仅按其实际证据层使用。不能把本轮 synthetic inputs 存成 AS2 金样本。

**Web 几何：未执行成功。** 首次缺 Playwright 浏览器；改用已安装 `/usr/bin/chromium` 后，进程被环境的 `socket() ... Operation not permitted`/ptrace 限制中止，exit 2。未绕过限制，未产生可用截图。这一缺口不由纯 JS renderer 测试替代。

**Crafting 额外测试：两项分别记录。** 全 evidence fixture 因 sparse 树缺 `fonts/fonts.xml` 等正式资源而不能执行；窄 AS2 anchor 测试返回真实失败。对起点和候选全部 24 个锚点复核，都是 23 符合/1 失败，唯一 `buildPlan` 的期望 bodyTokenCount=1164、实际=1193；24 个函数源码片段和提取契约均与起点相同，没有新增漂移。未更新固定期望以掩盖既有失败，见[基线对照](../evidence/issue-262-tooltip-20261115/crafting-contract-baseline-comparison.json)。

主项目 warnings 未做同环境起点构建对照，不能统称“既有警告”。完整原始输出保留于[证据目录](../evidence/issue-262-tooltip-20261115/)。

## 7. 性能、内存与工程取舍

Linux x64，Node 24.22.1、.NET SDK 10.0.300、ClearScript 7.4.5。输入为当前目录 1,788 物品基底加明确合成实例/药剂/技能/HUD 等，共 1,801 条。最终数据均绑定同一目录及 bundle hash，顺序测量，未与其他重测试并发。性能样本绑定 Gate C 提交 `cb9a3e0a72b6508c60f1855ecfd55fc33735cdc0`；后续修复只涉及响应契约、失败提示与测试，内容引擎、目录、调度器和基准函数未改变，因此保留原始测量，不把它重标为新一轮性能运行。

| 指标 | 实测 |
|---|---:|
| Node VM/bundle + 目录初始化 | 5.768 + 31.958 = **37.726 ms** |
| Node 首次生成 | **2.544 ms** |
| Node 预热后 P50 / P95 / P99，5403 次 | **0.165 / 0.333 / 0.520 ms** |
| Node 100 项批次，20 批 P50 / P95 | **15.724 / 23.590 ms** |
| ClearScript 冷初始化 | **302.044 ms** |
| ClearScript 首轮 1801 项批次 | **398.179 ms** |
| ClearScript 10806 次 P50 / P95 / P99 | **0.081 / 0.263 / 0.536 ms** |
| Service 1000 次缓存命中 P50 / P95 / P99 | **0.022 / 0.051 / 0.153 ms** |
| 同 owner 1000 请求快切 | **995 取消，173 次实际计算，最大排队 1** |
| 快切末请求提交至完成 | **1.043 ms**，结束 queued/active 均 0 |

单次引擎指标包含输入 JSON 解析、内容生成与输出 JSON 序列化；没有 Flash 实例采样、IPC 或真实 UI 排版成本。Service 缓存数字包含其输入校验、序列化/哈希和调度入口。

缓存基准重复的是输入首条“金币”（简单静态物品），不能代表复杂装备输入的哈希/序列化成本。快切为无人工延时的合成 burst，不等于玩家真实鼠标轨迹；已进入 V8 的任务允许算完，因此取消数不等于被省去的计算数。Node 与 ClearScript 预热及轮数不同，不能直接当成运行时 A/B 排名；ClearScript 的六轮统计包含首轮。

Node 初始化后 GC heap 增量 **5,814,816 B**。ClearScript 单进程 working set 为 **31,989,760 → 158,883,840 → 157,630,464 B**；冷初始化约增 121 MiB，包含 CLR、ClearScript/V8、JIT 与文件读取。这不是已有 GameInput 进程中新加 isolate 的净成本，也不是纯 V8 retained heap。

据此采用独立引擎的取舍是：保持输入实时路径隔离，接受启动与常驻内存成本。源码没有新增 GameInput 锁等待；Windows 中真实进程增量和帧尾延迟仍须量测。没有给出无法证实的性能阈值，也没有用源类数推算编译内存收益。

原始指标：[Node](../evidence/issue-262-tooltip-20261115/tooltip-node-benchmark.json)、[ClearScript](../evidence/issue-262-tooltip-20261115/tooltip-clearscript-benchmark.json)、[跨宿主对照](../evidence/issue-262-tooltip-20261115/tooltip-runtime-parity.json)。

## 8. 最小复现命令

从候选仓库根执行；SDK 以 `global.json` 为准。依赖恢复需可访问项目所用 npm/NuGet 源。跨宿主与性能数据必须先生成输入文件，不能假定临时 JSONL 已存在。

```sh
npm ci --ignore-scripts --prefix launcher/scripts
python3 tools/build-tooltip-catalog.py --check
python3 tools/test-tooltip-catalog.py
node launcher/tooltip-engine/build.cjs --check
npm test --prefix launcher/tooltip-engine
node tools/test-tooltip-input-projection.js
node tools/tooltip-oracle/capture/capture-tools.test.cjs

dotnet restore launcher/tests/TooltipService.Host/TooltipService.Host.csproj --locked-mode
dotnet run --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --test .

node launcher/tooltip-engine/fixtures.cjs /tmp/cf7-tooltip/inputs.jsonl
node launcher/tooltip-engine/benchmark.cjs --evaluate /tmp/cf7-tooltip/inputs.jsonl > /tmp/cf7-tooltip/node-output.jsonl
dotnet run --no-build --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --evaluate . /tmp/cf7-tooltip/inputs.jsonl > /tmp/cf7-tooltip/v8-output.jsonl
cmp /tmp/cf7-tooltip/node-output.jsonl /tmp/cf7-tooltip/v8-output.jsonl
dotnet run --no-build --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --validate-service . /tmp/cf7-tooltip/inputs.jsonl

node --expose-gc launcher/tooltip-engine/benchmark.cjs /tmp/cf7-tooltip/inputs.jsonl
dotnet run --no-build --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --bench . /tmp/cf7-tooltip/inputs.jsonl

python3 tools/build-asloader-modules.py
python3 tools/build-asloader-modules.py --check
python3 tools/audit-tooltip-closure.py
node tools/validate-doc-governance.js
git diff db6d3d248b80b80651987c99557c4e83b56f9301..HEAD --check
```

各 Web 测试、packer 及交叉编译的确切命令、环境和原退出码另保留于 `checks.json` 与 Host README，不省略失败/不可用记录。

## 9. 下一步与阻断判断

**发布阻断项**：独立新鲜 AVM1 paired parity；真实动态实例/数值/枚举/资源探测；三模块 CS6 fresh build 和归属/字节；Windows 生产 ClearScript/线程/NativeHud/WebView2 真实链路；玩家正常入口全消费者、hide/close/lease/revision/切场景/断线/Inspector 回归。完整可执行步骤见[Windows 验收清单](issue-262-tooltip-windows-acceptance.md)。

**阻断减负收益结论**：同机冷 CS6 的编译时间、PeakVirtualSize、每模块与 Tooltip DoInitAction 字节、真实 SWF 文件字节。当前仅能确认源码注册闭包净减 35 类。

**不阻断本轮源码候选交接、但不得遗忘**：浏览器容器权限导致的几何缺口；完整 Crafting evidence fixture 的资源前置；既有 buildPlan anchor 漂移。后两项未修改本轮无关业务，后续如要依靠该 Crafting 验收器签署 live 结果，需要先修复其既有基线一致性。

发布前还须量测既有 Launcher 内增加 Tooltip 引擎的真实净内存、GameInput 帧尾与批量奖励延迟。刀口探测的离线烘焙属于可后续优化，不是维持第二套 AS2 内容引擎的理由。
