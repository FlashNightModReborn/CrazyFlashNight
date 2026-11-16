# Tooltip 离线 AS2 oracle

这里保留 Issue #262 起点 `db6d3d248b80b80651987c99557c4e83b56f9301` 的旧内容实现，供独立 AVM1 真值采集。`as2/` 的 69 个文件与起点逐字节一致，`baseline.json` 记录来源 commit、原路径与 SHA-256。

**本目录不是候选运行时的 classpath。不要把旧 Builder、Document parser、renderer 或整套测试拷回候选生产类树、加入 asLoader manifest、挂到正式 Flash 入口。** 唯一允许同时运行旧内容实现和新输入 producer 的地方是单独的、可丢弃的 baseline oracle worktree。

## 当前验证状态

- 云端已执行 capture 工具的源码注入与 trace 协议单测；使用伪造协议行测试拒绝不完整、重复、失败与计数不一致的采集。
- Windows 已用真实 CS6 单独验证离线 JSON helper 的 45 个用例，以及采集暂停确认、恢复后的继续执行。完整采集仍必须独立通过计数和 parity 门，微型工具验证不代签全量语料。
- 工具单测不会把 synthetic expected 输出保存成 oracle，也不构成 AS2/TS 内容等价证据。
- `launcher/tooltip-engine/parity.cjs` 没有独立 corpus 时返回 `oracle-unavailable`、exit 2；这个缺口不能用 TS 自产期望补齐。

## 新配对捕获做什么

`capture/prepare-baseline.cjs` 只准备一个**干净且 HEAD 精确等于起点 commit**的独立 worktree：

1. 核验旧 Tooltip 归档对应的全部源文件哈希。
2. 将候选的 `TooltipInputProjection.as`、本目录的 `TooltipPairedCapture.as` 和离线传输 helper `TooltipCaptureJson.as` 装入该临时基线工程；不复制候选 InventoryPanelService 或候选 Builder。
3. 在基线原 `TooltipCorpusDump.emitCorpusRecord` 追加采集 hook；仍由原加载器、实际 BaseItem、合法 tier 和配件资格／依赖搜索产生实例。
4. 在原 TestLoader 模板引入基线的实际 UI frame 源，供旧 `_root.Web物品注释HTML` 生成 COMMON 预览。模板仍保持原 focused-run ID 约束。

每条 inventory 记录同步执行：候选 input 投影 → **基线旧** `InventoryPanelService.buildTooltipProjection` → 再次独立投影。两次冻结输入不一致则记录 `source_drift`，整次转换失败。旧 helper 提供 `expectedDocument`、`expectedIntroHTML`、`expectedDescHTML`；纯文本 details 使用基线 `StringUtils.htmlToPlainTextFast`。TS 不参与 expected 生成。

`expectedDetails` 按原出口比较：inventory/details 消费者使用原完整内联简介和描述，遵守 `ChoiceRewardService.snapshot` 的奖励详情规则；Web 记录来自旧 Web 兼容 HTML 的纯文字，其中可能重复列出药剂 Buff。比对器分别检查这两种原始出口，不用 Web 的兼容排版反向定义奖励详情。所有已采集字段继续保留并逐项比较。

离线 JSON helper 按转义片段汇合字符串，避免逐字符反复复制长 HTML；它不生成内容期望。每轮 AVM1 采集开始时必须先通过 45 个用例与基线 `LiteJSON.stringifySafe` 的逐字比较，包含所有 C0 控制字符、缺失值、非有限数和数组空洞。`TC_SERIALIZER_MISMATCH` 或 `TC_INPUT_ERROR` 均不能作为成功语料。独立微型验证入口为 `capture/run-json-tests.ps1 -BaselineRoot <已 prepare 的隔离基线>`，不能指向候选或正式工程；它使用同一事务化 focused runner，并保留 Compiler、SWF 和唯一 runId 的真实证据。Node 另有 47 个序列化用例，它们不代签 AVM1。

基础物品还配对旧 COMMON Web 入口；装备 tier／mods 变体配对 inventory 入口。开始时另采两条受限 HTML body 和 12 条技能边界 fixture，覆盖装备／启用标志、null、缺失字段、NaN／正负 Infinity、数字字符串、数组空洞、数字键和标记文本。技能表仅在同步采样期间替换，finally 恢复原引用。它们是**输入为 fixture、实际 expected 在 AVM1 执行**的边界证据，不应称为真实装备、存档或实战样本。

另有 20 条 `configured:` 记录：M4A1、KRISS、沙漠军装背心、远古诛神剑和巨兽各以强化 2/5/10/13 级通过真正 `BaseItem.create/getData` 构造。它们验证当前 authored 配置的计算结果与旧显示规则，没有复制计算公式，也不是读取真实玩家槽位；任一配置或等级不能构造时整轮失败。

### Windows 执行入口

下面命令须在已允许占用的 Windows 构建机执行。`C:\work\CrazyFlashNight-tooltip` 为候选 checkout，`C:\work\CrazyFlashNight-tooltip-oracle` 为新建基线 checkout，按实际路径替换。

```powershell
# 在候选 checkout 中创建独立 baseline，保留候选工作树。
$candidate = 'C:\work\CrazyFlashNight-tooltip'
$oracle = 'C:\work\CrazyFlashNight-tooltip-oracle'
$baseline = 'db6d3d248b80b80651987c99557c4e83b56f9301'
git -C $candidate config extensions.worktreeConfig true
git -C $candidate worktree add --detach --no-checkout $oracle $baseline
git -C $oracle config --worktree core.autocrlf false
git -C $oracle config --worktree core.eol lf
git -C $oracle read-tree -mu HEAD

# 只写临时 baseline 源码，不启动 CS6/Flash，不修改发布 SWF。
node "$candidate\tools\tooltip-oracle\capture\prepare-baseline.cjs" --baseline $oracle

# 使用 baseline 自己的事务化 TestLoader runner，fresh compile；不要 -SkipCompile。
Set-Location $oracle
.\scripts\run-tooltip-corpus-audit.ps1 -IncludeContext `
    -OutputRelativePath 'tmp/tooltip-paired-capture/paired.trace' -TimeoutSeconds 3600

# 转换器必须看到唯一完整、零错误的 TC_INPUT_BEGIN/TC_INPUT_END。
node "$candidate\tools\tooltip-oracle\capture\trace-to-oracle.cjs" `
    "$oracle\tmp\tooltip-paired-capture\paired.trace" `
    --output "$oracle\tmp\tooltip-paired-capture\paired-oracle.json"

# 实际 bundle 对独立 AVM1 expected 做逐字段比较。
Set-Location $candidate
node launcher/tooltip-engine/build.cjs
node launcher/tooltip-engine/parity.cjs `
    "$oracle\tmp\tooltip-paired-capture\paired-oracle.json" --current $baseline
```

请先完成该 baseline 工程原有的 CS6 路径、字体、Flash Player debug log、素材与数据配置；工具不会安装这些环境，也不会执行生产 Launcher 发布。prepare 命令拒绝候选目录、主 checkout、错 HEAD、脏工作树、缺失文件或源哈希漂移。基线旧文件的 SHA 绑定原始 Git 字节，须在首次 checkout 前关闭这个临时工作树的换行转换；不要把换行差异改写进 manifest 来放过检查。需要重新采集时使用新临时 worktree；不要用强制清理覆盖其他工作。

prepare 生成 `tmp/tooltip-paired-capture/setup.json`，含候选 producer SHA-256、原内容来源 commit、catalogContentVersion 与实际注入文件哈希。采集器在 AVM1 `begin()` 时写 UTC `capturedAt`，不是由转换器编造时间。原 focused runner 使用自己的编译互斥／scratch transaction／fresh-output 验证；配对错误可能不影响原 HTML dump 的成功计数，因此**还必须运行 trace 转换器并查看其退出码**。

全量导出会累积大量 IDE Output 内容。不要在导出运行时直接清空 Output：Windows 实测曾出现内部 footer 为 5691、原始文件只有 5690 条的拒收语料。离线 `TooltipCaptureControl` 在导出帧边界确认暂停，`capture/drain-output.ps1` 才能在原文件计数与暂停计数完全一致后，通过现有 CS6 控制入口清空本轮独占宿主的 Output，再以同一 nonce 恢复。原始 flashlog 前缀和每次控制回执均保留；任何计数或身份漂移均停止，不补造记录。暂停控制只加载准备目录里的本地 XML，不修改内容规则、装备或 expected。

可先在隔离基线执行 `capture/run-control-tests.ps1 -BaselineRoot <baseline>`，检查新鲜 `CAPTURE_CONTROL_PROBE|passed` 与 Compiler `0/0`。全量 runner 启动后，从本轮 scratch marker、实际唯一 Flash 进程和 `TC_INPUT_BEGIN` 获取身份，在另一个终端运行：

```powershell
& "$candidate\tools\tooltip-oracle\capture\drain-output.ps1" `
  -BaselineRoot $oracle -ParentPid <本轮原runner进程> -FlashPid <本轮冷宿主进程> `
  -RunId <本轮runId> -ScratchToken <本轮scratch-token>
```

该入口拒绝错误 HEAD、准备源码漂移、错误 scratch、非本轮冷宿主、占用中的编译器或不完整暂停回执。nonce 或控制超时后须按仓库恢复合同检查迟到回执，不能盲重放或删除 marker。清理控制安装的独占宿主 marker，仍须等原 runner 结束、保存完整证据并确认已退出；它不代表测试通过。

### 现场真实实例与边界补采

全量 corpus 默认覆盖真实配置构造的装备、tier 与合法配件路径；它没有玩家存档、发现进度或完整战斗 MovieClip。完成基线真实运行态初始化后，可以在**同一离线工程**中使用：

```actionscript
// begin 的三个版本参数取 setup.json；runId 使用这次独立采集唯一值。
org.flashNight.gesh.tooltip.test.TooltipPairedCapture.begin(
    "manual-save-001", "<sourceCommit>", "<projectionSha256>", "<catalogContentVersion>");
org.flashNight.gesh.tooltip.test.TooltipPairedCapture.captureInventory(
    "owned:backpack:0", _root.物品栏.背包.getItem(0));
org.flashNight.gesh.tooltip.test.TooltipPairedCapture.captureWeb("preview:medkit", "战场医疗包");
org.flashNight.gesh.tooltip.test.TooltipPairedCapture.captureLoadoutSkill("skill:0", 0);
org.flashNight.gesh.tooltip.test.TooltipPairedCapture.captureSkillFixture(
    "number-boundary",
    {Name:"数值边界", Type:"主动", Equippable:true, CD:0/0, MP:1/0, Description:"fixture"},
    ["oracle-number-boundary", 3, true, 0, false]);
org.flashNight.gesh.tooltip.test.TooltipPairedCapture.finish();
```

`captureSkillFixture` 仅在其同步调用期间替换测试技能表，`finally` 恢复原引用；生成 ID 带 `fixture:` 前缀。它用于观察 AVM1 的 NaN/Infinity/缺失字段等转换，不是玩家状态或 authored 配置样本。若日志包含多次完整运行，用 `--run-id manual-save-001` 选择；任何行出现在对应 begin/end 之外、重复 ID、错误标记或 footer 数量不符都会被拒绝。

应补采的真实上下文：强化等级、真实换装／配件后的 calculated 差异，灰蛊／灰蛊蚀刻，电力与 `__modName` 灯光归属，配置刀口数及实际 linkage 探测，存档中的不同已发现来源集合，技能装备／启用状态，HUD 药剂快捷键／数量，以及请求期间状态变化。完整 NativeHud HUD 专用 mode 的现场配对、最终 NativeHud/Web UI 与异步生命周期验收仍是单独项目，本工具没有把它们标为通过。

### 配对格式与 provenance

```json
{
  "schema": "cf7.tooltip-content-oracle.v1",
  "provenance": {
    "kind": "avm1-capture",
    "sourceCommit": "40-character-baseline-commit",
    "capturedAt": "runtime UTC ISO timestamp",
    "inputProjectionSha256": "copied candidate producer hash",
    "catalogContentVersion": "catalog version used for the comparison",
    "runId": "one runtime capture identity",
    "traceSha256": "complete trace hash"
  },
  "records": [{
    "id": "unique case identity",
    "input": {"version": 1, "kind": "item"},
    "expectedDocument": {"version": 1},
    "expectedIntroHTML": "optional independent AVM1 output",
    "expectedDescHTML": "optional independent AVM1 output",
    "expectedDetails": "optional independent AVM1 output"
  }]
}
```

示例中的字段内容是占位说明，不能交给 parity 充当真值。转换器只重新封装实际 trace 中的字段，附 trace 哈希；它不补全文档、不重算期望，也不会覆盖已有输出文件。

`--current` 用于核对**旧内容权威的来源 commit**，不是把候选 engine commit 冒充旧 AS2 的来源。这个流程绑定 Issue #262 起点配置和领域代码；若后续主线的装备／配件／领域数据已变化，必须重新审计并更新基线采集工程和 catalog。修改参数强行让 provenance 相等不能证明新版本等价。匹配结果仅覆盖所提供记录，不能推导未捕获场景。

## 旧 HTML／几何 dump 与新配对 corpus 的区别

`as2/.../test/TooltipCorpusDump.as`、`TooltipGroundTruthDump.as` 以及 `runners/` 原脚本／模板为 byte-exact 历史资产。`TC_ITEM` 保存旧 HTML 和布局统计，`GT_*` 保存 Flash 文本／几何读数；它们没有完整的同实例 TooltipInput + expectedDocument 配对，不能直接包装成新 schema 后宣称 Builder 差分通过。

归档 runner 内的相对路径以原 `scripts/` 为基准，**不能直接从本目录运行**。本流程使用干净 baseline checkout 自带的原 runner，并只在该临时工程增添配对 hook。候选生产 `scripts/run-tooltip-corpus-audit.ps1` 已显式退役，避免意外把旧 classpath 重挂到新生产入口。

可在任意平台执行的工具自检：

```sh
node tools/tooltip-oracle/capture/capture-tools.test.cjs
node tools/test-tooltip-input-projection.js
```

这些命令只验证源码注入、协议与 producer mock。实际 CS6 编译、AVM1 行为、已发现集合、资源探测和 Windows 生产 ClearScript 装载仍须分别记录结果。
