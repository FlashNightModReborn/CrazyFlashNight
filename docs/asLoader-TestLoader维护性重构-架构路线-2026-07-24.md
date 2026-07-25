# asLoader / TestLoader 维护性重构 · 架构路线 · 2026-07-24

**文档角色**：asLoader 与 TestLoader 联合维护性治理的 planning baseline / 架构决策记录。本文冻结后续施工方向、债务边界、阶段顺序和完成门；它不是当前构建入口或测试命令的 source of truth。

**施工基线**：commit `3d33fd238032e4ffc81cc91b41223b7ac67415f9`（2026-07-24）。

**状态**：`IMPLEMENTED`（2026-07-25）。S1–S3 已完成并通过新鲜 CS6、静态门与真机 trace；条件式 S4 经复盘明确不启动。本文 §13 记录本轮证据与未清债务；当前命令仍以 [asLoader 导览](asLoader-README.md) 和 [测试指南](../agentsDoc/testing-guide.md) 为准。

**前序设计**：[2026-06 单帧塌缩设计](asLoader重构-架构设计-2026-06-15.md) 解释单帧与 `BootSequencer` 的形成过程；[BootSequencer 构建标准](asLoader-BootSequencer-构建标准-2026-06-16.md) 继续拥有启动行为契约。本文不改写两者的历史结论。

---

## 0. 结论

后续不应推翻单帧塌缩，也不应把整个 asLoader 重写成一套新的模块框架。正确路线是：

1. **保留单帧产物与 `BootSequencer`**，把它们视为已经验证的发布形态。
2. **停止把 `frameNN` / `fNN_k` 当作长期语义边界**；它们只保留为排障和回退坐标。
3. **先治理 TestLoader 的 32 KiB 跳转与 64 KiB 函数风险**，使后续生产代码迁移有快速、可信的承接面。
4. **以热点为单位渐进 class 化**：typed class 持有业务逻辑，`_root` 只保留薄适配器和必要生命周期接线；不做全量大爆炸迁移。
5. **先把语义名直接写入现有生成器的唯一输入表**；暂不增加独立 manifest、测试 profile 格式或 runner 生成器。
6. **把编译速度作为每个切片都记录的结果维度**。先测量 class 引用闭包、首次诊断值和 warm 编译时间，再决定是否值得拆第二个生产 SWF；没有 ASO 重置协议前不声称可复现 cold，当前也不预设拆分。

这条路线优先清理已经存在的维护债，而不是追求“更现代”的 AS2 形态。

## 1. 问题边界

### 1.1 asLoader 的主要债务

- 单帧塌缩解决了时间轴散落，却没有建立稳定的**语义定位**；维护者仍需从 `frameNN`、chunk 名和生成器硬编码数组反推业务。
- `tools/assemble-collapsed-frame.js` 同时承担装配和部分启动业务编排，生成器边界过宽。
- 大函数仍接近 AVM1 `DefineFunction/DefineFunction2.codeSize` 的 UI16 上限；新增少量逻辑就可能撞墙。
- 大量 `_root`、`this`、时间轴闭包和动态赋值让代码难以隔离测试，也扩大改动影响面。
- live 输入、历史参考和生成物在同一心智空间内，容易改错文件或误判生效范围。
- 被引用 class 数量和依赖闭包持续增长，编译耗时明显，但目前没有稳定的分段测量支撑拆 SWF 决策。

### 1.2 TestLoader 的主要债务

- 多个测试套件本身已经成为“大脚本”，经常触发 AVM1 约 ±32 KiB 的相对跳转范围问题。
- 编译后的单个函数 / 方法也受 65,535 字节 `codeSize` 硬限制；源 `.as` 文件大于 64 KiB 不是硬错误本身，但通常是高风险代理指标。
- `scripts/TestLoader.as` 是被忽略的本机 scratch runner，测试选择不稳定，agent 很难从仓库直接复现“这轮究竟跑了什么”。
- 当前首次诊断样本若遇到 32K 错误会自动重试一次；它保住了旧工作流，却会掩盖测试代码结构已经越界的事实。没有可验证的 ASO 重置协议时，不把该样本称为 cold。
- 很多测试通过大 mock 环境复刻生产 `_root`，选择性复用生产逻辑的原始意图尚未形成可持续机制。

### 1.3 两者是同一笔维护债

若只重构 asLoader，TestLoader 仍因编译墙和 runner 漂移拖慢验证；若只拆 TestLoader，大量生产逻辑仍锁在 `_root` 与帧脚本中，只能继续维护高成本 mock。两条轨道必须相互咬合，但不应被揉成一个新框架：

```text
生产热点提取为可测 class / 薄适配器
              │
              ▼
TestLoader 直接测试生产 class 与适配器契约
              │
              ▼
稳定测试为下一批生产热点迁移提供保护
```

## 2. 2026-07-24 施工前量化快照

以下数字是 commit `3d33fd2380` 的施工前快照，不是当前工作树事实或永久常量；施工后数据见 §13，后续仍应由审计命令生成，而不是继续手工维护。

| 范围 | 施工前事实 | 含义 |
|---|---:|---|
| asLoader 时间轴 | 1 帧 | 单帧产物已经落地，不是本轮待解决问题 |
| 生成 import 头 | 82 个通配包 + 9 个具体类 | 解析面已经很宽，但通配 import 不等同于把整包 class 嵌入 |
| 生产 include 闭包 | 约 171 个现存 `.as`、1.85 MB、4.44 万行 | frame 数已经不能代表真实维护规模 |
| asLoader 嵌入 `org.flashNight.*` class | 599 | class 编译闭包仍在增长 |
| class ownership | main=0 / loader=599 / intersection=0 | 当前不存在主 SWF 与 asLoader 双嵌；必须继续守住 |
| asLoader 最大函数 | 56,646 / 55,844 / 53,291 B | 当前通过 `--max 60000`，但最大函数已超过 55 KiB，前两名均超过 54.5 KiB |
| 文本级 `_root` 命中 | 约 6,971 | 仅作耦合热区线索，不能机械等同为待迁移项 |
| 文本级 `this` 命中 | 约 3,485 | 同上 |
| `_root... = function` 命中 | 约 1,458 | 动态 API 面较大，适合做调用面审计，不适合一次性改写 |
| `scripts/**/*.as` 中文件名含 `Test`（含 as2lib 框架，排除 scratch `TestLoader.as`） | 253；其中 `org/flashNight` 226 | 这是候选盘点口径，不等同于 253 个独立 suite |
| 源文件 >32 KiB | 75 | 32K 跳转风险代理，不是编译后分支位移实测 |
| 源文件 >64 KiB | 34 | 64K 函数风险代理，不是 `.as` 文件硬限制 |
| 源文件 >100 KiB | 12 | 优先调查的超大套件 |
| tracked runner template | 3 | 与测试规模不匹配 |

当前最大的测试文件为 `AdaptiveShieldTestSuite`（约 187 KB）、`FSM_StateMachineTest`（约 175 KB）、`LootContainerServiceTest`（约 170 KB）、`QuickSelectTest`（约 168 KB）和 `TaskManagerTester`（约 147 KB）。文件大小只决定调查顺序。64K 风险必须由“canonical 源端单函数 / chunk 传递闭包度量 + 编译后近墙 `codeSize` + 新鲜行为证据”共同判断：`codeSize` 字段本身是 UI16，已经越过 65,535 B 的坏函数会回绕成小值，编译后扫描无法单独识别；源字节与字节码大小也不存在可证明的单调边界，因此源度量不单独作为 hard gate。32K 风险仍看真实跳转诊断与 retry。

## 3. 债务覆盖预期

本计划不会一次清零全部债务。按债务项而非代码行数做方向性估计，完整路线只承诺覆盖 asLoader 约四到五成、TestLoader 约五到六成；这不是验收指标。它优先降低最常发生、最妨碍 agent 工作流的成本：

| 已存在债务 | 本路线覆盖 | 完成后的剩余风险 |
|---|---|---|
| frame / chunk 难定位 | **高**：live 输入表获得语义名，生成器不再靠多组裸 frame 数组表达业务 | 历史提交仍会使用旧坐标 |
| 生成器混入业务逻辑 | **高**：业务判断回归 `BootSequencer` 或普通具名 boot 函数，生成器只排序 / 展开 / 校验 | AS2 编译器本身仍缺少模块系统 |
| asLoader 函数接近 64K | **中高**：先处理实测近墙函数并设防回归 | 未触及的低频脚本仍可能较大 |
| `_root` / 时间轴耦合 | **中**：按热点收缩为薄适配器 | 全量根对象 API 不在本轮清零 |
| TestLoader 32K / 64K 墙 | **高**：活跃测试组合先拆，随后建立编译后门禁 | 冷门历史套件按基线逐步偿还 |
| scratch runner 漂移 | **高**：常用选择落为 tracked template / aggregate | 临时排障仍允许 scratch runner |
| mock 与生产偏移 | **中高**：新迁移逻辑直接复用生产 class 和适配器契约 | 真实跨 SWF、存档和时序仍需真机 |
| class 数导致编译慢 | **未知，先量化**：减少无意引用，按闭包找候选 | 是否值得拆 SWF 必须由数据决定 |
| live / history / generated 混淆 | **高**：明确分层与只读生成物 | 物理迁移路径仍需兼容期 |

因此，第一阶段的成功标准不是“asLoader 已现代化”，而是：高频改动更容易定位、活跃测试不再频繁撞编译墙、下一批迁移可以在更小风险下进行。

## 4. 架构决策

### D1：保留已验证的发布形态

`scripts/asLoader/LIBRARY/asLoader.xml` 继续只 include 一个生成物，异步启动继续由 `BootSequencer` 驱动。单帧塌缩已经消除了 Flash 时间轴分散编辑面，本轮不重新引入多帧编排。

`f37_12` 之类的物理名字只用于二分、trace 对照和回退；新增文档、测试和所有权描述优先使用业务语义名。它不是需要长期维护的第二套模块 API。

### D2：先修 TestLoader，再渐进复用生产逻辑

TestLoader 选择性复用 asLoader 的长期意图是正确的：减少重复 mock 和实现偏移。但当前帧脚本普遍依赖 `_root`、时间轴 scope、加载顺序和副作用，直接 `#include frameNN.as` 会把生产启动环境整体拖入单测。

允许的复用顺序是：

1. 直接测试无时间轴依赖的生产 typed class；
2. 测试“薄 `_root` 适配器 → typed class”的契约；
3. 对仍无法提取的遗留脚本，只做最小兼容环境，不把它包装成通用运行时。

加载顺序编排、MovieClip scope 回调、必须捕获时间轴局部变量的 closure 和无法列清 `_root` 依赖的脚本不应为了 class 化而 class 化。它们可以继续保留普通函数形态。

如果测试载体自身随时撞 32K / 64K 墙，任何大规模生产重构都会放大反馈延迟。因此先处理活跃测试组合和真实近墙方法，再开启生产 class 试点。

### D3：测试选择只落 tracked 模板，不造 profile 系统

“focused / domain / full”只是测试组合的粒度术语，不对应新的配置格式。首轮沿用已经存在的模式：

- tracked `TestLoader.as.template` 声明 suite；
- 领域 PowerShell 脚本临时安装 / 恢复 scratch runner；
- 输出实际 suite、断言数与新鲜证据。

template 被复制后就是非 class 帧脚本，必须保留 UTF-8 BOM，并且不得使用具体类 import；只允许包通配 import，或直接用全限定类名调用。现有 template 在扩张前先按这条规则收口。

不新增 profile manifest、runner generator 或反射发现。只有多个领域脚本出现稳定重复后，才讨论提取公共 helper。

### D4：按压力迁移，并约束适配器寿命

满足以下至少两项的脚本才优先迁移：

- 高频修改或经常被 agent 定位；
- 编译后函数接近安全门；
- `_root` 动态 API 面大且 mock 代价高；
- 已有稳定 TestLoader 套件可承接；
- 业务边界清晰，能保持调用签名和时序。

一次迁移以一个业务切片为界，不以“清空一个目录”为目标。首个试点固定为装备域 3 个代表性脚本，不迁完整个装备体系。

旧调用方仍可调用 `_root.someApi(...)`，但 adapter 只负责：

- 参数和返回值的兼容转换；
- 从 `_root` 取得明确列出的依赖；
- 委托 typed class；
- 保留必要的 trace、时序和失败语义。

业务分支、状态机和大型循环不得继续堆回 adapter。无法列清依赖的脚本暂不迁移。

adapter 分两类：

- **边界 adapter**：跨时间轴 / 旧调用协议确实需要，允许长期保留，但必须只有一份业务实现；
- **迁移 adapter**：只为过渡存在，同批记录剩余调用方和删除条件；批次结束若调用方没有减少，则停止扩张或回退该迁移。

不为 adapter 另造框架、基类或注册表。

### D5：生成器内只保留一份 boot-source 语义表

首轮把 `STAGED`、`S7_LOADERS`、`S8_LOADERS` 等数组合并为 `tools/assemble-collapsed-frame.js` 内一份带注释的普通常量表，只表达：

- 稳定语义名；
- frame / 源文件；
- 启动阶段与执行形态；
- 确定性顺序。

一次性盘点的落点就是这张表，不再维护一份平行 Excel / Markdown 清单。只有出现第二个真实消费者后，才另开决策评估是否把表外置；TestLoader 首轮不消费它。`SPECIFIC_IMPORTS` 仍是独立的 CS6 解析兼容白名单，不混入 boot-source 表。

生成器只做读取、排序、展开、静态校验和生成。S5 / S9 一类启动业务移到 `BootSequencer` 或普通具名 boot 函数，不先发明 “installer” 抽象。生成结果保持可 diff、可重建，继续禁止手改。

### D6：以编译后事实设门，暂不拆第二个生产 SWF

- 32K：看实际分支溢出 / 首次诊断样本的自动重试，不用 32 KiB 文件大小冒充 cold compile 事实。
- 64K：保留 canonical 源端单函数 / chunk 的传递闭包度量用于定位和人工复核；SWF 中的 `codeSize` 负责硬拦尚未越墙的近墙项，但不能独立证明“没有溢出”，所以还必须有新鲜行为证据。不能仅凭源字节数发明硬失败阈值。
- 源文件 32 / 64 / 100 KiB 只用于排序和提醒，不应阻止合理的多小函数文件，也不建立 exact no-growth 例外表。

“class 多”不自动等于“应拆 SWF”。只有当前可复现的稳定 warm 编译数据（以及未来若出现可验证重置协议后的 cold 数据）证明一个稳定、单向依赖的叶子闭包是主要耗时，且原型量化了跨 SWF 身份、加载、缓存和发布成本，才另开 ADR。此前只治理无意引用与过宽 aggregate。

## 5. 目标结构

### 5.1 生产装配

```text
assemble-collapsed-frame.js 内唯一 boot-source 表
        │ semantic name / frame / phase / order
        ▼
现有生成器 ── 静态校验 / 展开 ──> _collapsed_frame.as
                                      │
                                      ▼
                     BootSequencer + 普通具名 boot 函数
                                      │
                         遗留函数或已验证的 typed class
                                      │
                          必要的边界 / 迁移 adapter
```

`_collapsed_frame.as` 仍是单一生产入口，但不再是维护者理解业务的首要地图。

### 5.2 测试选择

```text
tracked TestLoader.as.template + 领域 runner 脚本
                         │
                         ▼
               临时安装薄 scratch runner
                         │
                         ├─ production typed classes
                         ├─ adapter contract tests
                         └─ test aggregate
                         │
                         ▼
Flash CS6 首次诊断 + warm compile + fresh trace / Output Panel evidence
```

template 负责“选择”，可以直接调用少量 suite；只有一个稳定组合已被两个以上入口复用时，才由薄 aggregate 负责“调用”。测试方法负责“断言”，不得为了形式统一给每个 template 再造一层单函数 wrapper class，也不得重新合并成巨型 `runAllTests()` 分支体。

## 6. 最小施工路线

首轮只做三个能独立还债的切片。它们不依赖新框架，也不要求先建“一键审计器”。

### S1：先拆三个近墙生产函数

- 用现有 SWF `codeSize` 结果映射 56,646 / 55,844 / 53,291 B 三个函数的真实源 chunk；
- 每次只拆一个，拆分点服从业务阶段和副作用顺序；
- 同时记录 canonical 源端 chunk 闭包度量并保持 `--max 60000` 近墙硬门，不为了追求小文件任意切片；
- 每次记录拆前 / 拆后大小、编译耗时和 boot 行为证据。

**完成门**：三个热点都获得可解释边界和明确余量，且源端度量与编译后 `codeSize` 同时有记录；boot trace、class ownership、BOM、静态 frame-scope 门及 Flash CS6 新鲜证据仍通过。此切片不新增 manifest、class 或 adapter。

### S2：修活跃 TestLoader 反馈环

先用现有命令形成一张基线表，记录首次运行观察值、稳定 warm 编译时间、最大测试函数、32K retry 次数、最终错误数、suite 和证据类型；不要求先实现聚合命令。当前没有可重入的 ASO 冷态重置入口，因此不得把“切换目标后的第一次”包装成可复现 cold 中位数：

- 首次运行只作诊断样本，记录 CS6 进程 / 目标切换前置与是否发生 32K 自动重试；
- warm 基线先预热同一目标一次并丢弃该样本，再连续记录至少 3 次同目标 wall-clock，取中位数；
- 发生自动重试的样本单列，不混入单次编译性能中位数；
- 只有未来出现可验证的 ASO 重置协议，才新增 cold 中位数；本轮不为此发明 cache manager。

首批按当前验证矩阵处理：

- Inventory / NPC Shop / Crafting；
- Equipment Tuning；
- Skill；
- LongGun / ManualCooldown / DrugInput；
- Map loot。

为缺入口的组合增加 tracked `TestLoader.as.template` 与领域 runner 脚本；拆分实际触发 32K / 64K 风险的测试方法和过宽 aggregate，不改断言语义。共享 fixture 只在两个以上 suite 已经重复且生命周期一致时提取。

BootSequencer / BootstrapHandshake 目前不在 testing-guide 的活跃矩阵中；未来若把它们变成正式入口，应在实现同轮更新 testing-guide。

**完成门**：上述活跃组合可从 tracked 入口复现；本轮首次诊断样本和预热后至少 3 个连续 warm 样本均不触发 32K retry；runner / 必要 aggregate 保持薄，新鲜行为证据与拆分前等价。未来只有在可验证 ASO 重置协议落地后，才把 cold 中位数或 cold 零 retry 写成可复现完成门。

这一步不清理全部历史测试债。当前验证矩阵显式点名的 >100 KiB 候选至少包括 `LootContainerServiceTest` 和 `LongGunSubWeaponCoreTest`，但 aggregate 的完整调用闭包仍需在 S2 盘点；不能据此宣称 12 个大候选已被覆盖。其余项留在“被修改时优先偿还”的调查队列；不为源文件字节建立 exact no-growth ratchet。

### S3：收窄生成器与文件角色

- 盘点当前 live 输入，并把语义名、frame、阶段、执行形态和顺序直接写入生成器内唯一常量表；
- 把 S5 / S9 等业务编排移到 `BootSequencer` 或普通具名 boot 函数；
- 明确 live / history / generated 三种角色；
- 未被生成器读取、也没有当前回退契约的历史 frame 文件默认从工作树删除，由 Git 历史保留；确需保留者放入明确 history 区并写保留理由；
- 物理目录迁移只在 regen、回退和 Flash CS6 reopen 验证通过后进行。

删除历史 frame 只减少搜索和误改面，**不会**减少当前编译闭包；不能把它报告成编译提速。

**完成门**：生成物中的每个 live 输入都能反查生成器内唯一语义条目；生成器无业务条件分支；重复生成字节稳定；history 不参与生成；regen 后产物与唯一表一致，不再维护第二份手写清单。

### S4：条件式三文件 class 试点

只有 S1–S3 让测试反馈和定位成本稳定后，才从装备域选恰好 3 个高频、边界清晰、已有测试的脚本：

1. 冻结旧 `_root` API 与时序契约；
2. 提取业务逻辑到生产 class；
3. 只在必要处保留边界或迁移 adapter；
4. TestLoader 直接测 class，并测一层 adapter contract；
5. 记录 adapter 类型、剩余调用方、删除条件，以及编译闭包、函数大小、mock 体积和定位成本。

若三个样本没有稳定降低维护成本，停止 class 化路线并回退；不得因模板已经存在就迁完整目录。只有样本数据为正，才讨论玩家、库存或 Web bridge 的下一批固定热点。

### 6.1 编译速度的实际处理路径

编译速度不是第四套施工系统，而是每个切片都要记录的结果：

- 同一机器 / CS6 会话下记录 asLoader、focused TestLoader 的首次运行诊断值与 warm 中位数；warm 必须先预热、再取至少 3 次同目标样本，32K retry 单列；
- 优先移除经审计证实会扩大 class 闭包的无意 import、过宽 aggregate 和不必要静态引用；
- 用更小的 tracked 测试组合降低日常 TestLoader 编译面；
- 连续两个优化尝试若都没有超过测量噪声的稳定收益，就停止该方向；
- 生产 SWF 拆分仍须独立 ADR，不与 S4 class 试点绑售。

没有数据前不得声称目录整理、历史 frame 删除或 class 化“解决了编译速度”。

## 7. 依赖与变更粒度

```text
S1 生产近墙 ─────┐
S2 测试反馈环 ───┼──> S4 三文件试点（条件式）
S3 生成器卫生 ───┘
```

- S1、S2、S3 可并行取数，但代码变更分批验证，不把三类风险塞进同一批；
- S2 必须在 S4 前稳定，避免把迁移压力压到不健康测试载体；
- 每批只改变一种主要风险：函数切分、测试结构、生成角色或业务所有权；
- S4 不是必经里程碑；前三个切片已经能独立结束本轮施工。

## 8. 测试与门禁

### 8.1 测试粒度

- **focused**：一个 class / adapter 契约，默认开发反馈环。
- **domain**：同一领域的若干 suite，合并前门。
- **full**：跨域回归，定期或高风险变更使用。
- **real runtime**：跨 SWF、真实存档、socket、时间轴和生命周期，只能由真机 / 对应 XFL 验证覆盖。

TestLoader 不应伪装成 real runtime；减少 mock 偏移不等于取消真机门。

### 8.2 最小防回退基线

1. 先记录当前最大函数和大文件清单；被修改项重新测 canonical 源闭包与编译后 `codeSize`，只由既定近墙硬门阻断；
2. 活跃测试组合的本轮首次诊断样本与预热后至少 3 个连续 warm 样本均为零 32K retry；
3. 新增 / 修改测试方法同时记录源端单函数闭包度量，并纳入编译后 `codeSize` 近墙门；
4. 每完成一个历史 suite 拆分，就从临时基线中移除；
5. 自动重试在迁移期保留诊断信息，不能继续被当作健康成功路径。

这是一张基线表加现有门，不是通用 ratchet 系统。编译后 `codeSize >= 60,000 B` 作为近墙硬失败；canonical 源闭包 `>=70,000 B` 只在报告中突出为人工复核候选，不阻断生成，也不维护冻结例外。源字节既不能证明“必坏”也不能证明“安全”，把它设成 exact no-growth hard gate 会让注释 / 格式变化成为新的维护负担；UI16 回绕盲区由源度量、chunk 施工记录与新鲜行为证据共同覆盖。

### 8.3 每批生产迁移固定回归

- 生成器内唯一 boot-source 表 / 生成物确定性；
- function `codeSize`；
- class single ownership；
- BOM 与静态 frame-scope 门；
- 受影响 focused / domain 测试组合的新鲜行为证据；
- 涉及 boot 时做 trace 等价；
- 涉及真实跨 SWF、存档或生命周期时追加真机。

在入口真正实施前，命令和成功术语仍完全服从 [testing-guide.md](../agentsDoc/testing-guide.md)。

## 9. 防止重构制造新负担

以下均为本路线的明确非目标：

- 不引入 AS2 运行时模块加载器或通用 DI 容器；
- 不用反射 / 字符串扫描自动发现测试；
- 不为“统一”再造一套 package manager、脚本语言或生命周期框架；
- 不直接让 TestLoader include 原始 boot frame；
- 不把任一完整脚本集合或目录一次性 class 化；
- 不因 class 数增长就立即拆多个生产 SWF；
- 不强求每个小文件、每个测试 suite 使用相同抽象模板；
- 不删除仍有真实调用方的 `_root` 边界 API；迁移 adapter 则必须有调用方清单和删除条件；
- 首轮不产品化独立 semantic manifest、profile 格式、runner generator、installer 抽象、adapter 框架、ratchet 系统或一键审计 wrapper；
- 不把生成器和测试选择合成一个拥有业务行为的“万能 orchestrator”。

新增抽象至少应满足两个真实消费者或消除一个已量化的重复风险；否则优先使用普通函数、显式列表和现有工具。

## 10. 停止条件与完成判据

本路线不是无限重构项目。达到以下状态即可转入日常维护：

- live asLoader 输入 100% 映射到生成器内唯一 boot-source 语义表，history / generated 不再误导生效范围；
- 生成器只装配和校验，业务逻辑有明确 owner；
- 当前近墙生产函数降到已约定 `codeSize < 60,000 B` 余量；后续修改继续重测，而不是冻结源字节；
- testing-guide 的活跃 TestLoader 组合在本轮首次诊断样本与预热后至少 3 个连续 warm 样本中均不出现 32K retry；
- 常用组合可由 tracked 入口复现，runner 和 aggregate 不再承担巨型业务分支；
- 若执行 S4，三个样本的生产 class、必要 adapter 和对应测试均有正向维护性数据，迁移 adapter 的调用方数量持续下降；
- 高频维护路径的定位 / 复现步骤、编译时间或 mock 体积至少有一项获得可复测改善；
- 剩余历史大测试、`_root` 耦合和编译闭包已明确列为未清债务，不再伪装成“全面健康”。

不会作为完成条件的指标：

- `_root` 命中清零；
- 所有脚本变成 class；
- 所有测试放进单一 full runner；
- class 总数下降；
- 生产 SWF 数量增加。

## 11. 回退原则

- 每批只改一个业务切片；未执行 S4 时不新增 API 适配层；
- 语义名与旧 frame / chunk 坐标可从生成器内唯一 boot-source 表双向查找；
- 生成器变化与业务迁移分开提交 / 验证；
- runner / template 变化不得与断言语义变化混在同一批；
- 任一批若增加编译时间、mock 复杂度或故障定位成本且无抵消收益，回退该批，不以“架构已经投入”为继续理由。

## 12. 第一轮施工清单

1. 用现有命令按 §6.1 协议记录首次运行 / warm、源端闭包度量、`codeSize`、32K retry、suite 与证据类型的基线表，不先写 wrapper。
2. 将三个近墙生产函数映射回源文件，逐个完成 S1。
3. 为 testing-guide 活跃组合补齐 tracked template / 领域 runner，选择一个真实触发编译墙的组合做 S2 样板。
4. 把 live 语义映射直接写进生成器内唯一输入表，随后提取 S5 / S9 业务并清理无回退价值的历史 frame。
5. S1–S3 复盘后，再决定是否启动恰好 3 文件的 S4；默认答案可以是“不启动”。

第一轮不新增生产 SWF、不迁全目录、不建立独立 manifest / profile 系统、不删除仍有调用方的兼容 API；正式入口只有在实现和验证同轮才写入 testing-guide，不提前宣称可用。

## 13. 2026-07-25 施工完成记录

本节是对 §2 施工前快照和 §6 路线的闭环记录，不把一次施工包装成“全面健康”。本轮没有新增生产 SWF、AS2 模块系统、profile manifest、runner generator、adapter 框架或冷缓存管理器。

### 13.1 S1：近墙生产函数

三个匿名近墙函数的源 owner 定位为 `frame2` 引擎/路由、`frame39` 关卡系统和 `frame41` 物品栏 UI。拆分只改变具名 stage chunk 边界，不改变 include 顺序或运行 tick：

| 语义 owner | 施工后 chunk | 源闭包字节 | 新鲜 SWF `codeSize` |
|---|---|---:|---:|
| 引擎基础、成长/路由、攻击/子系统路由 | `f2_1 / f2_2 / f2_3` | 56,148 / 55,276 / 57,707 | 22,340 / 17,318 / 16,988 B |
| 关卡进入/场景建立、刷新/回调/限制 | `f39_1 / f39_2` | 62,684 / 41,687 | 31,822 / 24,022 B |
| 物品栏核心、强化与样品栏 | `f41_2 / f41_3` | 30,773 / 47,764 | 20,384 / 32,907 B |

施工前全局最大三个匿名函数为 `56,646 / 55,844 / 53,291 B`；2026-07-25 最终 publish 后全局最大三个为 `45,868 / 44,163 / 38,422 B`，`--max 60000` 通过。`frame41` 的强化/样品栏段是纯移动到单一新 include 文件，不存在双定义路径；`frame2/39/41` 的注释明确这些是人工语义边界，不伪装成 `stage-wrap-frame.js` 可重建的自动切点。

同一台机器和 CS6 会话的时间记录如下；“首次”只是诊断样本，不称为 cold：

| 样本 | 首次诊断 | 预热丢弃 | 三次 warm | warm 中位数 | 32K retry |
|---|---:|---:|---:|---:|---:|
| commit `3d33fd2380` | 63.233 s | 33.866 s | 32.988 / 32.941 / 33.006 s | 32.988 s | 0 |
| S1 拆分后 | 46.117 s | 32.967 s | 33.927 / 34.034 / 33.949 s | 33.949 s | 0 |

warm 中位数约慢 2.9%，处于本机编译噪声量级，因此**不声称编译提速**，也不据此拆第二个生产 SWF。S1 的确定收益是近墙余量、语义定位和较小故障面。

### 13.2 S2：活跃 TestLoader 反馈环

tracked template 从 3 个增至 6 个，五个活跃组合都有显式领域入口。结构相同的入口（含既有 scene-collision）最终收敛为单一窄 helper 加薄显式领域 wrapper；wrapper 继续列出 template、suite、FQN 和期望 summary，未引入 profile 或自动发现。Map loot 保留独立 runner，因为它还有 ServerManager 源隔离、materialization 和 teardown 审计，不强行塞入公共框架。

可复测的定位 / 复现指标已经改善：基线 clean checkout 对 item panels、equipment tuning、player manual input 三个组合均为 **0 个 tracked 领域入口**，只能先检查本机 ignored `TestLoader.as`、手改 runner、再编译，至少 3 步且无法从仓库反推出本轮 suite；施工后五个活跃组合为 **5/5 个单命令 tracked 入口**，每个入口同时固化 suite、断言 summary 和 evidence contract。该指标只声明选择与故障定位步骤从“检查 + 手改 + 编译”收敛为“一条领域命令”，不把它伪装成编译提速。

首个 item-panels 诊断曾以 `NpcShopPanelServiceTest 5/46` 暴露缺失的生产兼容 leaf；补入最小 `商店系统_兼容.as` 后才将首个**有效**诊断样本记入下表。所有诊断、预热丢弃和 warm 样本的 retry 均为 0：

| tracked 入口 | suite / 断言 | 首次有效诊断 | 预热丢弃 | 三次 warm | 中位数 | 最大 `codeSize` |
|---|---|---:|---:|---:|---:|---:|
| `run-item-panel-tests.ps1` | NPC 46 + Inventory 131 + Crafting 27 | ≈15.3 s | 18.040 s | 15.014 / 15.048 / 16.087 s | 15.048 s | 19,072 B |
| `run-equipment-tuning-tests.ps1` | Equipment 39 + Inventory 131 | 18.219 s | 15.306 s | 14.955 / 15.001 / 15.195 s | 15.001 s | 19,072 B |
| `run-skill-migration-tests.ps1` | Loadout 50 + Skill Panel 45 | 4.869 s | 4.990 s | 4.993 / 4.912 / 4.950 s | 4.950 s | 3,380 B |
| `run-player-manual-input-tests.ps1` | LongGun 472 + ManualCooldown 50 + DrugInput 19 | 13.984 s | 14.019 s | 13.047 / 13.077 / 13.067 s | 13.067 s | 19,072 B |
| `run-map-loot-tests.ps1` | Box 13 cases / 53 assertions + Loot 142 + Planner 9 | 13.557 s | 13.189 s | 13.051 / 13.168 / 13.070 s | 13.070 s | 19,072 B |

最终锁、marker 与 helper 代码冻结后，五个活跃入口各执行一次真实 CS6 回归，另有 scene-collision **21/21、4/4 cases**；全部得到单一、闭合且同 runId 的行为块、期望 summary 精确一次、compiler `0/0`、fresh trace/output/errors、fresh `TestLoader.swf` 和 `32K retry=0`。对应 runId 为 item `1c67a561ea6a472abc6518d2d949b68f`、equipment `197b1214d55d4dc4b784ec25b4ce7096`、skill `f9671c7d06ef44c89704b2c74e8aa592`、manual `2177d7450ae248c5a663a589a1311c70`、map `749738d9423a443a9cde07eeea4cb161`、scene `a0f2e36209d04b60a403df9d040158fe`；每轮结束都恢复同一个原始 `TestLoader.as` SHA-256 `2C393431E42C9EDF19FA185E8B0FDD3342CCB0F755CB688B9AD8DC11B7903A72`。最终入口只用同一仓库编译 mutex 覆盖“安装 scratch → 编译 → 消费证据 → 恢复”；原 runner 先复制到同卷 `scripts/.testloader-scratch-recovery/<token>.as` 并验 SHA-256，再在改写前落持久事务 marker。子 `compile_test.ps1` 只通过与 marker 的 repo/owner/lease/runner/backup 完全一致的随机 lease 复用父锁，普通编译见 scratch marker 一律拒绝；marker 只在 installed/original SHA-256 均验证后删除。Compiler Errors 必须由本轮新鲜导出并严格为 `0/0`，TestLoader 同时自动启用 SWF 刷新与 `codeSize < 60000` 门。`compile_action.jsfl` 只接受“唯一可解析汇总、零 warning、错误数与逐行含 32K 的诊断数完全相等”的保守格式；混合、多行上下文或不可解析诊断 fail closed，并保留首轮诊断。runner 把任何非零 retry 判为不健康失败。`compile_test.ps1` 在触发计划任务前先写 in-flight uncertain marker，terminal 只能 exact-match 清本轮 body；focused / map 在 child exit 0 后未见唯一 runId 终态也会 poison，非 terminal 保留 target/mode cfg 给迟到 JSFL 按原目标消费。必须先确认 Flash/计划任务/旧 player 停止，并按 marker 的 backup/hash 恢复 scratch 后再重试。

末轮入口审计又删除了无引用且可绕过上述事务的 `scripts/train_cycle.sh`、`scripts/test_publish.jsfl` 与 `scripts/test_trace.jsfl`；Gobang 只保留 `gobang_trainer_cycle.ps1`，普通编译只从 `compile_test.ps1` / `compile_test.sh` 进入。兼容旧计划任务的 `trigger_compile.ps1` 仍仅作为 `compile_test.ps1` 已识别的 legacy action 保留，现行 setup 会改为直开 loader。

Gobang / 协议两个长跑入口也复用了同一持久 scratch 事务，但没有被塞进 focused helper。Gobang 全量 fresh run（runId `a3813e87797643539b16b3d20de1d584`）得到 `Total=68 / Run=65 / Skipped=3`、Local `60/65`、Rapfi `58/65`、compiler `0/0`、retry `0`，按契约因 5 个本地失败而非零退出；`GobangTrainer.as` 与施工基线逐字节一致，故这不是 runner 回归，也不能写成全绿。定向正例 `mb_open_four_h`（runId `f1c0945522384b3c8962d62dddf23556`）为 `1/1` 且 exit 0，不存在过滤项（runId `88f4201913d74e7caa31164617eb5d34`）为 `Run=0` 且按预期 fail closed。协议 cycle（runId `38f167b2d06841c5b9ea75fa9b6dd37e`）从 AS2 源精确派生并验完 14 个 summary + 14 组 raw samples，failures `0`；`sweep -Runs 1` 同样完整 14 项且 failures `0`。两者的自启 bus 都绑定精确 Core PID，先 `/shutdown`、等待退出，只有超时才允许精确 PID kill；最终没有遗留端口文件、Core 进程、scratch、recovery 或 uncertain marker。

### 13.3 S3：生成器与 boot 所有权

- `tools/assemble-collapsed-frame.js` 只维护一张有序 `BOOT_SOURCES`：29 个 live source、6 个 stage，其中 13 个 `staged`、16 个 `loader-fire`；语义名、frame、phase、shape 和顺序不再分散在多组数组。
- 默认模式生成；`--check` 对 BOM、行尾和全部字节做 exact compare，未知参数拒绝。生成器同时校验表内唯一性、stage/shape、根目录 live frame exact-match、transitive include BOM、staged 定义/调用包络和 loader-fire 顶层 scope；canonical 源闭包只度量并报告，不参与成败判定。
- 帧顶 `_lockroot=false; stop();` 是生成物结构前导，必须早于任何 `_root` 读写；S0 的 `GlobalInitializer` 业务初始化、S5 task/guide、S9 crafting 归 `BootSequencer`，其中 `BootSequencer.start()` 不再重复写 `_lockroot`。S7 仍在同一 tick 严格执行 `syncLogic → 打印杂项文案 → misc loaders`。没有新增 state、等待门、service 或 installer。
- 删除不参与当前装配的 pre-collapse backup 与 `frame0/1/4/5/6/7/26/75/91`；Git 是唯一历史来源。删除只减少搜索/误改面，不声称缩小编译闭包。
- `BootSequencerTest 58/58`、`BootstrapHandshakeTest 12/12` 以临时 scratch runner（runId `4eb5d2ebd64d4dd3adc5681a9cf40611`）获得新鲜 CS6 trace、唯一 70 条 `PASS` 和 compiler `0/0`，随后 scratch SHA-256 完整恢复；S10 另直接断言 `_root.play() → host.removeMovieClip()` 的调用顺序。

最终执行 `regen → --check → --check` 均字节稳定；生成物由 `.gitattributes` 固定 LF，源闭包在剥 BOM、统一换行后度量，并同时计入 staged/loader-fire 自身源体。最大项为 `f3=149,298 B`；`f3`、`f36_2=121,117 B`、`f37_7=76,380 B` 高于 70,000 B 提示线，属于仍需关注的调查候选，不是 hard gate 例外。

2026-07-25 最终生产验证：

- `compile_test.ps1 -Target publish`：36 s，Compiler Errors 面板副本 `0 个错误, 0 个警告`，`scripts/asLoader.swf` 新鲜刷新为 1,034,400 B，SHA-256 `2B8A61DE2531852B399370EFD487AA081F656BCBBFE679FD1EA1889631026B8E`；
- `swf-function-sizes --max 60000`：9,493 个函数，最大 `45,868 B`；
- single ownership：main=0 / loader=599 / intersection=0；
- 正式标准入口经 immutable runtime identity / payload closure 核验后，以专用克隆槽 `cf7_agent_equipment_tuning` 启动；attempt `ba5c8503e3dc4e0ab569879f1dc83016` 获得 fresh handoff、真实 `bootstrap_reveal_ready`、同 attempt `s:1` 与 runtime ack，并到达只读装备 snapshot，未触发 reveal watchdog；报告为 `tmp/equipment-tuning/unattended/20260725T025939Z-cf7_agent_equipment_tuning/run-report.json`，正式 Core SHA-256 为 `15E22D10B450A8616766D25F709D761C20B5A773BA60314680060348B7970EC2`，build identity / payload closure 分别为 `3F6110809903BF28D08E90F92087A4333E5C604F0AC62994E945775690CD25C6` / `C16ED23C85DCF0C2B2A321158F2269BED9D45ACC32BACCD428ED51AD4D49E107`；
- `trace-diff` 修正旧 `f91` 无边界匹配（随机 attemptId 内嵌 `f91` 不再冒充 handoff）并扩充 selftest 后，当前 fresh 日志仍为 golden 10 事件 / new 10 事件 / LCS 10，顺序从 `S2_ENTER` 到 `HANDOFF_PLAY` 完全一致。

### 13.4 S4 决策：不启动

S1–S3 已直接解决本轮最高频的定位、近墙、runner 漂移和生成器双重事实源问题；现有数据没有证明再选 3 个装备脚本 class 化能带来超过新 adapter/API 生命周期成本的收益。按路线的条件式约束，本轮明确不启动 S4，不新增生产 class、adapter、基类或注册表。未来若出现三个满足 D4 压力条件且已有独立维护成本数据的候选，应另开切片重新决策，不能把本轮 template/helper 当成默认迁移许可。

### 13.5 异构对抗审查与剩余债务

本机 Kimi Code（`kimi-code/k3`，thinking，`--max-steps-per-turn 100`）已完成三次只读异构对抗审查；三轮都正常结束，未遇到 quota / overload。首轮明确反对新增 source-byte hard gate；后续命中了测试指南漂移、路线状态/证据缺口、非零 retry 被误当健康、多份 runner 重复、编译 timeout 未透传、abandoned mutex 覆盖旧 marker、stale scratch marker 泄漏自启 bus、迁移后旧注释和临时 prompt 卫生。本轮分别通过文档同步、retry=0 硬门、窄共享 helper、精确 timeout / PID teardown、append-preserving marker、失败路径 bus 回收、注释修复和临时文件清理收口。第三轮（session `04bf0f10-7c27-401d-9b5e-af1fae3e097a`）结论为 `PASS FOR FINAL VALIDATION`；其中“loader-fire include 正则无效”一项经独立复核判为误报，因为生成器先用 `stripStrings()` 把所有字符串字面量归一成 `""`，当前正则正是匹配归一化结果，故未为迎合审查而改坏它。结合首轮反对意见，70,000 B 源闭包门已降级为 canonical advisory 度量，不再维护 exact no-growth 例外。没有外扩 runner framework、cache manager、trace-session 协议或 S4 adapter 系统。

明确保留的未清债务：

- 没有可验证的 ASO 冷态重置协议，因此只有首次诊断值和 warm 中位数，没有“可复现 cold”结论；
- 三个高于源闭包提示线的候选、其余历史 >100 KiB 测试套件、广泛 `_root` / 时间轴耦合和 599-class 编译闭包仍需按修改触发逐步偿还；提示值只决定复核优先级；
- focused 入口覆盖的是 testing-guide 当前活跃组合，不代表全部 253 个 Test 候选或全部真实跨 SWF 生命周期；
- Gobang 当前全量仍有 `mid_complex_diagonal`、`mid_p3_should_not_rush`、`def_diag_two_two_block`、`mid_post_book_response`、`def_t_precursor_cross` 五个本地失败和 6 个 `RAPFI_DIFF`；本轮只把 runner、证据与恢复契约做成可重复且 fail-closed，没有借维护性重构修改 AI 或把红基线伪装成通过；
- timeout / 进程崩溃后 Flash/JSFL/player 可能迟到完成；编译触发前写入的 exact-owned `compile_state_uncertain.marker` 会阻断后续编译，terminal 只删除仍 exact-match 的本轮 in-flight body，非 terminal 保留 target/mode cfg 给迟到 JSFL。父 runner 崩溃则由 `testloader_scratch_inflight.marker` 与同卷 recovery sidecar 继续阻断普通编译。维护者仍须人工确认 Flash/计划任务/旧 player 静止并核对迟到 evidence；若是 scratch runner abandoned，还必须按 marker 的 `backup_path/original_sha256/had_runner` 恢复 `scripts/TestLoader.as` 后才能删闸与 sidecar。lease 不是鉴权，marker 提供可审计恢复材料但不自动猜测恢复；
- 编译速度没有稳定改善证据；不启动第二生产 SWF，也不把 history 删除或目录整理报告为性能收益。
