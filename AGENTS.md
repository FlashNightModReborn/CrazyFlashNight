# AGENTS.md

**文档角色**：顶层路由与硬约束入口。**最后核对代码基线**：commit `2e5e32321506fa1fb2693f3928205f8c45b4235e`（2026-09-17）。

## 硬约束

**授权先于计划。** 仅执行用户已授权的范围；接班包、历史回执、lease 都不授予新权限。
保留他人修改与真实存档。不擅自 commit/push、发布、清理工作树、安装/消费外部服务或操作凭据。
已授权、可逆且边界清楚的工作继续推进；只因新权限、不可逆动作、产品取舍或必要的人类感官验收中断，
不为形式上的重新确认打断用户。详见 [人类注意力约束](agentsDoc/human-care.md)。

**证据不升级。** 源码成立、候选构建、实际运行、专项体验和正式部署是不同结论。
保留 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`
的术语边界；箭头不是可跳过证明的自动状态机。候选运行要绑定实际路径、identity 与 closure；
`build.ps1` 至多说明候选已构建。发布不证明某业务已在标准入口复验；旧回执不证明新工作树或现役 runtime。
[发布状态与证据](docs/runtime-build-reproducibility.md#evidence-states) 是说明入口，机器身份仍读对应 manifest/consensus。

**持久写与未知结果。** 改存档、库存、奖励、交易或退出链前，读取对应权威与恢复合同。
超时/畸形成功/DeliveryUnknown 不等于未执行，不得盲重放；不得用 UI 投影、关窗或换会话解除未知写锁。
不拿真实玩家槽位做试写，不以旧备份覆盖已有差异。
[持久化验证](agentsDoc/testing-guide.md#save)；[跨层权威](agentsDoc/as2-web-panel-migration.md#authority-core)。

**AS2 / Flash。** 写 AS2 前读 [反幻觉约束](agentsDoc/as2-anti-hallucination.md)。`.as` 保持 UTF-8 BOM，
新建优先复制现有文件再改名；不混入 AS3/JavaScript 假定。只用真实 Flash CS6 GUI 编译，不手工改 SWF。
目标按归属选择：逻辑注入 `-Target publish`；测试 `-Target test`；确属主 XFL 才 `-Target main`；
独立资源指定 `-Target <xfl> -PublishOnly -VerifySwf <对应.swf>`，不能让活动文档或 main 兜底。
marker 只结束等待，不证明编译成功；要求本轮新鲜 Compiler `0/0` 和目标对应证据。
publish 模式不出 trace 属正常；TestLoader 必须有本轮 suite 行为证据，Output Panel 副本不能称 trace。
编译锁、scratch 恢复、异常 marker 不得靠删除锁或备份绕过。
执行前读 [编译验证](agentsDoc/testing-guide.md#as2) 和 [CS6 操作](scripts/FlashCS6自动化编译.md)。

**正式 runtime 是独立授权路径。** 文档/数据/Flash/XFL/Web-only 改动不自动触发 runtime 发布；native source-ahead 也不等于必须部署。
只有部署闭包变更且获得发布授权才走 immutable request、受控源码 tag、local X509 与真实独立故障域 builder、
同 identity/closure 双 signer 共识、strict v2 policy receipt 和唯一 promotion writer。
禁止复制密钥/伪造独立 builder、v2 失败退回 v1、候选目录直拷正式 runtime 或绕过 tag/ruleset。
通用 supply-chain promotion 不借 Audio H1/H2/E3、截图/听感或 emergency-release 解锁；实际影响 DLL 的输入仍进入闭包。
操作从 [发布协议](docs/runtime-build-reproducibility.md#release-protocol) 开始。

**资产与工程边界。** XFL 改名/引用先用审核、rename_a_class、fix_includes 和 linkage 扫描工具；碰撞按专题要求由真人 CS6 处理。
坐标歪斜、编辑崩溃、无法保存 XFL 先查 [rigPropagationMatrix 故障](scripts/优化随笔/FLA-rigPropagationMatrix-溢出导致元件不可编辑.md)。
资源唯一编辑源与确定性装配见 [美术装配](agentsDoc/art-asset-assembly.md)；新增库资源走其 things-new 源链。
asLoader 可在获授权的可用节点交付；其他 SWF 按最终归档/上传边界交付，均不自动授予提交权限。

PowerShell 先 `chcp.com 65001`；文本直接用 UTF-8 中文，不无故改成 Unicode 转义。
仅改数据/配置 XML 通常重启，不据此重编 SWF；修改生成输入后先执行对应生成器及 `--check`。
不提交 node_modules、临时文件或无治理的大型派生物；运行资源例外必须有生成、manifest、完整性和体积审计。
提交说明用中文并给回归提示；获授权的合作者直推规则以 [贡献流程](docs/contribution-workflow.md) 为准，不额外强制 PR。
规范随相关施工同批修正，运行文档巡检；不把历史收据追加到本入口。

## 按任务读取

本仓是 AS2/Flash CS6 核心与 C# Host、WebView2、TypeScript/V8、Rust、PowerShell 共存工程。
**只读命中的路线和条件扩展；找到改动归属、权威入口、验证办法与失败恢复后停止扩读。**
已有明确源文件的局部修复直接进入其路线；跨界才升级，不按链接递归遍历全仓。

### AS2 逻辑、战斗与输入

先 [反幻觉约束](agentsDoc/as2-anti-hallucination.md) → [AS2 验证](agentsDoc/testing-guide.md#as2)。
热路径再读 [性能](agentsDoc/as2-performance.md)，初始化/跨 SWF 再读 [加载时序](agentsDoc/as2-load-timing.md)；
涉及游戏系统/代码约定才读对应 [系统](agentsDoc/game-systems.md) / [编码](agentsDoc/coding-standards.md) 章节。
进入持久写或 Host/Web 命令时追加跨层路线。

### 数据、数值与派生物

先 [数据格式与归属](agentsDoc/data-schemas.md#data-entry) → [数据验证](agentsDoc/testing-guide.md#data)。
数值/配方/成长调整追加 [游戏设计](agentsDoc/game-design.md) 对应规则与其工作簿来源；不把派生 XML 覆盖公式权威。
生成器/sidecar/闭包改动追加 [派生物验证](agentsDoc/testing-guide.md#derived)。

### Web 局部界面与跨层面板

已有面板的布局/样式/交互：先 [Panel 注册与脚本归属](launcher/README.md#panel-registry) → [Web 验证](agentsDoc/testing-guide.md#web)；
布局合同、焦点、CSS 治理、状态与动效归 [工作台对应合同](agentsDoc/workbench-ui-system.md#ui-core) 命中节（纯 CSS 修复也在其范围），不读整份迁移 backlog。
新增命令、改身份/数据权威/打开关闭/未知写恢复：先 [跨层核心](agentsDoc/as2-web-panel-migration.md#authority-core)
→ [跨层验证](agentsDoc/testing-guide.md#cross-layer)，再读该命令域；变更迁移范围时读取并在自然收口更新
[迁移剩余清单](docs/AS2-UI迁移剩余清单与难度评估-2026-09-12.md)，不把整份清单当每次 CSS 修复的前置。

### Host、启动、通信与自动化

先 [源码职责](launcher/README.md#source-map) / [自动化入口](automation/README.md)
→ [Host 验证](agentsDoc/testing-guide.md#host)。进程、通信或存档所有权不明确时再读
[架构职责链](agentsDoc/architecture.md#runtime-chains)。仅显式部署任务进入发布路线。

### 美术 / XFL / 图标 / 头像

先 [美术装配](agentsDoc/art-asset-assembly.md) → [美术验证](agentsDoc/testing-guide.md#art)。
仅实际编译时追加 CS6；仅头像生产/推广时追加其 campaign、真人回执和消费者闭包，不套给普通载具绘制。

### 存档、现场故障与专项资格

存档/奖励/退出先 [持久化验证](agentsDoc/testing-guide.md#save)；现场焦点/卡顿先
[诊断边界](agentsDoc/testing-guide.md#diagnostics)。不因本机不能复现而删除现场证据，也不让探针自动修复故障。
音频、NativeHUD、PlayerInfo B0、F8、长时斗兽或头像 campaign 只在命中该专项时读
[专项资格](agentsDoc/testing-guide.md#specialized)，其旧阈值不泛化成全项目流程。

### 文档、协作与接班

文档整顿先 [文档治理](agentsDoc/documentation-governance.md) → [文档验证](agentsDoc/testing-guide.md#docs)。
协作/任务拆分读 [Agent harness](agentsDoc/agent-harness.md) 和 [human-care](agentsDoc/human-care.md)；
自然收口时按 [经验沉淀](agentsDoc/self-optimization.md) 更新唯一真源，不建立额外日常打卡/回执制度。

## 文档地图

`AGENTS.md` 负责路由和短硬约束；`agentsDoc/` 保留专题当前合同；工具 README 负责准确命令；
`docs/` 保存 ADR、调查与历史证据。`testing-guide.md` 是选择矩阵，`testing-details.md` 是按需验证正文。
同一正文可以有多个任务入口；调用方写触发条件、目标章节和停止条件，不再要求无条件读回入口。
机器可给出的身份、注册表、枚举、产物计数不在此复制维护；规则冲突回到源码/机器真源与具体授权，显式报告范围。
