# asLoader / TestLoader 维护性重构 · 架构路线 · 2026-07-24

**文档角色**：asLoader 与 TestLoader 联合维护性治理的 planning baseline / 架构决策记录。本文冻结后续施工方向、债务边界、阶段顺序和完成门；它不是当前构建入口或测试命令的 source of truth。

**最后核对代码基线**：commit `6a7010ec8fb0`（2026-07-24）。

**状态**：`PROPOSED`。方向已经收敛，但尚未改变生产装配、TestLoader runner 或编译入口；当前事实仍以 [asLoader 导览](asLoader-README.md) 和 [测试指南](../agentsDoc/testing-guide.md) 为准。

**前序设计**：[2026-06 单帧塌缩设计](asLoader重构-架构设计-2026-06-15.md) 解释单帧与 `BootSequencer` 的形成过程；[BootSequencer 构建标准](asLoader-BootSequencer-构建标准-2026-06-16.md) 继续拥有启动行为契约。本文不改写两者的历史结论。

---

## 0. 结论

后续不应推翻单帧塌缩，也不应把整个 asLoader 重写成一套新的模块框架。正确路线是：

1. **保留单帧产物与 `BootSequencer`**，把它们视为已经验证的发布形态。
2. **停止把 `frameNN` / `fNN_k` 当作长期语义边界**；它们只保留为排障和回退坐标。
3. **先治理 TestLoader 的 32 KiB 跳转与 64 KiB 函数风险**，使后续生产代码迁移有快速、可信的承接面。
4. **以热点为单位渐进 class 化**：typed class 持有业务逻辑，`_root` 只保留薄适配器和必要生命周期接线；不做全量大爆炸迁移。
5. **先把语义名直接写入现有生成器的唯一输入表**；暂不增加独立 manifest、测试 profile 格式或 runner 生成器。
6. **把编译速度作为每个切片都记录的结果维度**。先测量 class 引用闭包和 cold / warm 编译时间，再决定是否值得拆第二个生产 SWF；当前不预设拆分。

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
- 当前冷 ASO 遇到 32K 错误时会自动重试一次；它保住了旧工作流，却会掩盖测试代码结构已经越界的事实。
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

## 2. 2026-07-24 量化快照

以下数字是当前基线快照，不是永久常量；后续应由审计命令生成，而不是继续手工维护。

| 范围 | 当前事实 | 含义 |
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

当前最大的测试文件为 `AdaptiveShieldTestSuite`（约 187 KB）、`FSM_StateMachineTest`（约 175 KB）、`LootContainerServiceTest`（约 170 KB）、`QuickSelectTest`（约 168 KB）和 `TaskManagerTester`（约 147 KB）。文件大小只决定调查顺序；真正的门必须落在编译后的函数 `codeSize`、跳转错误和新鲜测试输出上。

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

- 32K：看实际分支溢出 / cold compile 重试，不用 32 KiB 文件大小冒充。
- 64K：看 SWF 中单个函数 / 方法的 `codeSize`，不把整个 `.as` 文件大小当硬门。
- 源文件 32 / 64 / 100 KiB 只用于排序、提醒和“不得继续恶化”的基线，不应阻止合理的多小函数文件。

“class 多”不自动等于“应拆 SWF”。只有冷 / 热编译数据证明一个稳定、单向依赖的叶子闭包是主要耗时，且原型量化了跨 SWF 身份、加载、缓存和发布成本，才另开 ADR。此前只治理无意引用与过宽 aggregate。

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
Flash CS6 cold compile + fresh trace / Output Panel evidence
```

template 负责“选择”，aggregate 负责“调用”，测试方法负责“断言”。三者不得重新合并成一个巨型 `runAllTests()` 分支体。

## 6. 最小施工路线

首轮只做三个能独立还债的切片。它们不依赖新框架，也不要求先建“一键审计器”。

### S1：先拆三个近墙生产函数

- 用现有 SWF `codeSize` 结果映射 56,646 / 55,844 / 53,291 B 三个函数的真实源 chunk；
- 每次只拆一个，拆分点服从业务阶段和副作用顺序；
- 保持现有 `--max 60000` 门，不为了追求小文件任意切片；
- 每次记录拆前 / 拆后大小、编译耗时和 boot 行为证据。

**完成门**：三个热点都获得可解释边界和明确余量；boot trace、class ownership、BOM、静态 frame-scope 门及 Flash CS6 新鲜证据仍通过。此切片不新增 manifest、class 或 adapter。

### S2：修活跃 TestLoader 反馈环

先用现有命令形成一张基线表，记录 cold / warm 编译时间、最大测试函数、32K retry 次数、最终错误数、suite 和证据类型；不要求先实现聚合命令。

首批按当前验证矩阵处理：

- Inventory / NPC Shop / Crafting；
- Equipment Tuning；
- Skill；
- LongGun / ManualCooldown / DrugInput；
- Map loot。

为缺入口的组合增加 tracked `TestLoader.as.template` 与领域 runner 脚本；拆分实际触发 32K / 64K 风险的测试方法和过宽 aggregate，不改断言语义。共享 fixture 只在两个以上 suite 已经重复且生命周期一致时提取。

BootSequencer / BootstrapHandshake 目前不在 testing-guide 的活跃矩阵中；未来若把它们变成正式入口，应在实现同轮更新 testing-guide。

**完成门**：上述活跃组合可从 tracked 入口复现，cold compile 不触发 32K retry，runner / aggregate 保持薄，新鲜行为证据与拆分前等价。

这一步不清理全部历史测试债。当前验证矩阵显式点名的 >100 KiB 候选至少包括 `LootContainerServiceTest` 和 `LongGunSubWeaponCoreTest`，但 aggregate 的完整调用闭包仍需在 S2 盘点；不能据此宣称 12 个大候选已被覆盖。其余项留在“不得增长 + 被修改时偿还”的队列，源文件大小仍只是调查代理。

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

- 同一机器 / CS6 会话下分别记录 asLoader、focused TestLoader 的 cold / warm 中位数；
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

1. 先冻结当前最大函数和大文件清单，禁止新增更坏项；
2. 活跃测试组合达到 cold compile 零 32K retry；
3. 新增 / 修改测试方法纳入编译后 `codeSize` 门；
4. 每完成一个历史 suite 拆分，就从临时基线中移除；
5. 自动重试在迁移期保留诊断信息，不能继续被当作健康成功路径。

这是一张基线表加现有门，不是新的 ratchet 系统。具体阈值以 S2 的编译后数据为准；生产当前沿用 60,000 B 软门，不得仅凭源文件字节数发明新的硬失败阈值。

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
- 当前近墙生产函数降到已约定安全余量，且不再增长；
- testing-guide 的活跃 TestLoader 组合 cold compile 不出现 32K retry；
- 常用组合可由 tracked 入口复现，runner 和 aggregate 不再承担巨型业务分支；
- 若执行 S4，三个样本的生产 class、必要 adapter 和对应测试均有正向维护性数据，迁移 adapter 的调用方数量持续下降；
- 高频维护路径的定位时间、编译时间或 mock 体积至少有一项获得可复测改善；
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

1. 用现有命令记录一张 cold / warm、`codeSize`、32K retry、suite 与证据类型的基线表，不先写 wrapper。
2. 将三个近墙生产函数映射回源文件，逐个完成 S1。
3. 为 testing-guide 活跃组合补齐 tracked template / 领域 runner，选择一个真实触发编译墙的组合做 S2 样板。
4. 把 live 语义映射直接写进生成器内唯一输入表，随后提取 S5 / S9 业务并清理无回退价值的历史 frame。
5. S1–S3 复盘后，再决定是否启动恰好 3 文件的 S4；默认答案可以是“不启动”。

第一轮不新增生产 SWF、不迁全目录、不建立独立 manifest / profile 系统、不删除仍有调用方的兼容 API，也不提前修改 testing-guide 的正式入口。
