# Issue #262：Windows / CS6 最终验收

**文档角色**：Windows/CS6 验收步骤与首轮本机记录；第 7 节保留原候选范围。对齐最新主线后的三模块、Host、实际检视器及正式列车状态见[2026-11-16 整合发布记录](issue-262-tooltip-release-20261116.md)，不沿用旧候选身份代签。

**最后核对代码基线**：导入 HEAD `f20f50f48072a95a45fd11b155e3fcf9bd2142e4` 加本轮未提交修改（2026-11-16）。原云端生产代码为 `3a2f434ceea4c0a07bad3a915bd314921f0f6863`。

**关联**：[交付报告](issue-262-tooltip-migration.md)、[完整消费者矩阵](issue-262-tooltip-consumers.md)、[离线 oracle 操作说明](../../tools/tooltip-oracle/README.md)。

本轮已获 Windows 构建机占用授权；下方保留复现步骤。publish 会重写隔离树的三件 SWF；focused runner 使用事务化 TestLoader 与新鲜 runId。正式目录保留，候选、编译基线和 oracle 分属隔离树。

## 1. 准备三棵树

`$candidate` 检出最终交付 commit。另两个目录必须新建；oracle 必须是干净的精确起点。

```powershell
$candidate = 'C:\work\tooltip-candidate\resources'
$baselineBuild = 'C:\work\tooltip-baseline-build\resources'
$oracle = 'C:\work\tooltip-oracle\resources'
$baseline = 'db6d3d248b80b80651987c99557c4e83b56f9301'
git -C $candidate config extensions.worktreeConfig true
foreach ($target in @($baselineBuild, $oracle)) {
  git -C $candidate worktree add --detach --no-checkout $target $baseline
  git -C $target config --worktree core.autocrlf false
  git -C $target config --worktree core.eol lf
  git -C $target read-tree -mu HEAD
}
```

按仓库现有指南配置 CS6、字体、Flash Player/debug log 与素材。保留每树 source commit、工作树差异和实际资源 hash；测试机器配置及冷/热 IDE 条件必须一致。

## 2. 独立 AS2 paired oracle

```powershell
node "$candidate\tools\tooltip-oracle\capture\prepare-baseline.cjs" --baseline $oracle
if ($LASTEXITCODE -ne 0) { throw 'Oracle prepare failed' }
Set-Location $oracle
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-tooltip-corpus-audit.ps1 `
  -IncludeContext -OutputRelativePath 'tmp/tooltip-paired-capture/paired.trace' -TimeoutSeconds 3600
if ($LASTEXITCODE -ne 0) { throw 'AVM1 capture failed' }
node "$candidate\tools\tooltip-oracle\capture\trace-to-oracle.cjs" `
  "$oracle\tmp\tooltip-paired-capture\paired.trace" `
  --output "$oracle\tmp\tooltip-paired-capture\paired-oracle.json"
if ($LASTEXITCODE -ne 0) { throw 'Paired trace conversion failed' }
Set-Location $candidate
npm ci --ignore-scripts --prefix launcher/scripts
node launcher/tooltip-engine/build.cjs --check
python -B -X utf8 tools/build-tooltip-catalog.py --check
node launcher/tooltip-engine/parity.cjs `
  "$oracle\tmp\tooltip-paired-capture\paired-oracle.json" --current $baseline
if ($LASTEXITCODE -ne 0) { throw 'Independent AVM1 parity failed' }
```

使用 **baseline 自己的**原 corpus runner，不是候选中已退役的同名脚本，也不是直接运行 archive 下的 runner。不得传 `-SkipCompile`。判据：唯一完整 `TC_INPUT_BEGIN/END`、非空记录、零 capture error、`fresh-avm1-match`、failureCount=0；`--current` 校验旧内容权威的完整 commit，候选投影器 hash 独立记录在 setup/provenance。

另补真实存档与战斗上下文：强化、升阶和实际配件；灰蛊/灰蛊蚀刻；use/weapontype/grantsUse/bullet 分支；灯光 `__modName`/电力；配置和 linkage 探测刀口；不同来源发现进度；技能启用/装备/资源不足；HUD 药剂数量和快捷键；null/undefined/NaN/Infinity/数组空洞/数字键枚举。配对时输入前后不稳定的记录应拒绝并重采，不能用 TS 输出覆盖 expected。

## 3. 三模块新鲜构建及成本对照

在 baseline-build 与 candidate 分别运行同一命令、记录同机冷宿主条件；不要在 oracle 树做此对照。

```powershell
Set-Location $candidate
$publishWall = [Diagnostics.Stopwatch]::StartNew()
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 `
  -Target publish -VerifySwf scripts/asLoader.swf -TimeoutSeconds 900
$publishExit = $LASTEXITCODE
$publishWall.Stop()
"Publish wall seconds: $($publishWall.Elapsed.TotalSeconds)"
if ($publishExit -ne 0) { throw 'Three-module publish failed' }
```

现役入口会依次构建 resident → shared → boot；对应 `scripts/asLoader.swf`、`scripts/asLoaderShared.swf`、`scripts/asLoaderLogic.swf`。生成一致性、fresh SWF、compiler diagnostics、类归属、继承顺序和 32K recovery 检查由该入口执行。

若使用 `-QuitFlashAfterPublish` 建立逐阶段冷启动对照，必须先确认 IDE 属于本轮且无其他未保存文档；该选项会退出 CS6，不作为默认附加参数。

保存 `tmp/asloader-builds/<本轮run>/receipt.json`、`inputs.json` 和 resident/shared/boot 的 `compile.log`、`compiler_errors.txt`、`compile_output.txt`。receipt 含三件 SWF 的路径、SHA、bytes 与整轮起止。`[OK] 编译完成` 是轮询粒度耗时；外层 Stopwatch 是整个 publish 流程耗时。`[CS6 VA 水位]` 的 PeakVirtual 来自 `Flash.exe.PeakVirtualMemorySize64`，是进程生命周期峰值，必须用同机冷进程比较，不能把历史峰值算成本轮成本。

## 4. 类归属、函数与 DoInitAction

```powershell
node tools/assemble-collapsed-frame.js --check
python -B -X utf8 tools/build-asloader-modules.py --check
python -B -X utf8 tools/audit-tooltip-closure.py --report tmp/tooltip-windows/source-closure.json
node tools/audit-as2-class-embedding.js --swf scripts/asLoader.swf --json
node tools/check-as2-inheritance-order.js --modules
node tools/swf-function-sizes.js scripts/asLoader.swf --max 60000 --top 15 --json
node tools/swf-function-sizes.js scripts/asLoaderShared.swf --max 60000 --top 15 --json
node tools/swf-function-sizes.js scripts/asLoaderLogic.swf --max 60000 --top 15 --json
# 完整候选资源及 packer 依赖齐全后，检查全部生产 SWF 集合：
node tools/audit-as2-class-embedding.js --policy production --json
```

不能用 report-only/child-only 替代最终门。候选 manifest 为 1/338/429；以实际 SWF 精确类集合为判据，检查旧 Builder 没有转嵌入其他 SWF。

在 baseline-build 和 candidate 各执行一次下列只读统计，分别保存 JSON：

```powershell
@'
const fs = require('node:fs');
const cp = require('node:child_process');
const {parseSwf} = require('./tools/swf-metadata');
const catalog = JSON.parse(fs.readFileSync('tools/asloader-modules.json', 'utf8'));
const modules = ['resident', 'shared', 'boot'].map(name => {
  const file = catalog[name].swf;
  const m = parseSwf(fs.readFileSync(file));
  const tooltip = m.classes.filter(c => c.fqn.startsWith('org.flashNight.gesh.tooltip.'));
  return {module:name, file, swfBytes:m.bytes, swfSha256:m.sha256,
    classCount:m.classes.length,
    classInitializerActionBytes:m.classes.reduce((n,c) => n+c.actionBytes,0),
    tooltipInitializerActionBytes:tooltip.reduce((n,c) => n+c.actionBytes,0),
    tooltipClasses:tooltip, classes:m.classes};
});
console.log(JSON.stringify({sourceCommit:cp.execFileSync('git',['rev-parse','HEAD']).toString().trim(), modules},null,2));
'@ | node -
```

`actionBytes` 为类 DoInitAction 动作 payload，不含两字节 SpriteID 和 tag header；与压缩 SWF 文件字节分别报告。类数、源码字节、动作字节、文件字节、编译时间、PeakVirtualSize 是不同指标。

## 5. focused AVM1 回归

统一形式如下，不加 `-SkipCompile`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-native-interaction-tests.ps1 -TimeoutSeconds 900
```

| 范围 | 实际 runner |
|---|---|
| Native 身份/anchor/实例输入 | `scripts/run-native-interaction-tests.ps1`；窄入口 `scripts/run-asloader-retirement-tests.ps1` |
| Inventory/Crafting/NPC/Synthesis | `scripts/run-item-panel-tests.ps1 -Suite All` |
| CharacterBuild、Tuning | `scripts/run-character-build-tests.ps1`、`scripts/run-equipment-tuning-tests.ps1` |
| Choice、Stash、Loot/report | `scripts/run-choice-rewards-tests.ps1`、`scripts/run-reward-stash-tests.ps1`、`scripts/run-map-loot-tests.ps1` |
| HUD | `scripts/run-player-hud-tests.ps1`、`scripts/run-player-hud-snapshot-tests.ps1`、`scripts/run-hud-loadout-resource-tests.ps1` |
| 技能、Task、Merc | `scripts/run-skill-resource-tests.ps1`、`scripts/run-task-panel-tests.ps1`、`scripts/run-merc-loadout-tests.ps1` |
| 原领域断言 | `scripts/run-equipment-interval-curve-tests.ps1`、`scripts/run-equipment-emissive-asset-tests.ps1`、`scripts/run-arena-drop-rule-tests.ps1`、`scripts/run-weapon-ammo-data-tests.ps1`、`scripts/run-weapon-ammo-tests.ps1`、`scripts/run-sheriff-baton-tests.ps1`、`scripts/run-player-manual-input-tests.ps1`、`scripts/run-gray-goo-tests.ps1` |

每项结束立刻保存新鲜 `scripts/flashlog.txt`、compiler 输出和测试 SWF 身份，后续 runner 会复用位置。Choice/Crafting 静态门已随新增断言改为 112/186；Native bridge/InventoryTooltipProjection 使用动态正计数。`run-equipment-lighting-tooltip-tests.ps1` 已变为 Node 内容检查，不算 AVM1 证据。

## 6. Windows Host、实际 UI 和玩家入口

1. 在 Windows 使用同一 7.4.5 ClearScript、实际打包资源运行独立 Host 测试，再按既有 Launcher candidate 构建规程生成候选。核 catalog 来源 SHA、源/bundle 版本、worker 初始化/销毁和 UI marshal；完整 PowerShell release prepare/policy 仍须实际执行。
2. 实际 NativeHud/WebView2 覆盖消费者矩阵全部入口，特别库存与构筑 exact slot、调制 before/after、奖励 details、暂存选择奖励、建角外观目录、宠物/佣兵、各商店和 HUD 技能/药剂。
3. 检查最终 Document/HTML 的标题/图标、排序/颜色/数值、灰蛊等特殊机制、Buff/暴击子面板、获取途径和升级路径；检查多栏几何、DPI、滚轮、锚点和遮挡。浏览器几何 runner 可在可用 Windows 浏览器环境运行，但不能替代实际 WebView2/NativeHud。
4. 生命周期覆盖快速切换、原请求期间装备或配件变化、lease/revision 失效、面板关闭/重开、hide 先于生成、切场景、迟到、断线/重连和 Host 重启。普通 hover 不得退役 pinned Inspector；过期请求不得复活，关闭批次不得继续累计未运行内容。
5. 在 Tooltip 读取/生成失败时，确认独立写操作只保留原来的提交结果，业务 ack 不丢失、不自动重放；Choice 失败仍保持 exact 行形状，调制/构筑 response 不被新增 Document 拒绝。
6. 量测已有 Launcher + GameInput 进程中新引擎的净 RSS/heap、冷启动、真实实例负载的 P95/P99、批量奖励尾延迟、cache key 序列化、GameInput 帧尾和锁等待。云端冷进程 RSS 不能代替这个净增量。

实际结果、失败和产物身份分别记录，不能将某一层证据升级为完整玩家验收。完整 Crafting live evidence 流程另有本基线既存 buildPlan anchor 不一致，需先单独核对其固定契约，不能更新 hash 代签业务等价。

## 7. 本机候选验证记录

机器与工具链、当前候选身份、逐项回执及失败原件索引见[本机证据](../evidence/issue-262-tooltip-windows-20261115/results.json)。本节随验证收口更新；缺少完成回执的项目保持待验。

| 范围 | 当前实际结果 |
|---|---|
| 原有开发环境 | Windows 11 / 32 GiB 级内存；用户目录原有 SDK 10.0.300，MSVC 19.44.35228.0、Rust 1.96.0、Windows SDK 10.0.22621.0 校验通过，无需先升级机器 |
| 终端与 CS6 设置 | 两种 PowerShell 已优先选择原有 SDK 并使用 UTF-8；CS6 已有 LAA，取消 WIN7RTM、保留 RUNASADMIN；备份保留 |
| 首轮三模块对照 | 基线与候选均 fresh Compiler 0/0；实际类数为 1/338/464 → 1/338/429，Tooltip 40 → 5；全生产 815 SWF 归属审计无错误，继承与三模块函数大小门通过 |
| 产物体积 | boot 3,987,878 → 3,806,261 字节；Tooltip DoInitAction 189,231 → 18,993 字节 |
| 单次冷宿主成本 | 整轮 383.48 → 350.08 秒，boot PeakVirtual 2295.7 → 2232.5 MiB；仅一次顺序对照，不外推稳定性能收益 |
| Windows 新引擎 | 内容测试 42/42、producer mock 11/11、实际 ClearScript Host 34/34；1,801 条合成窄投影通过生产 service，Node/ClearScript 换行归一后逐行一致；当前 bundle 307,048 字节，SHA-256 为 c70bc251… |
| fresh AVM1 focused | 21/21 组新鲜行为回归通过；最新通过轮均 Compiler 0/0、32K retry 0，原失败与恢复记录保留 |
| Launcher 全量 xUnit | 8,569 总数：8,410 通过、128 失败、31 跳过；128 项均为五个未改动物理 ResourceCaseGuard 类缺少 evidence root，不能写成全量通过 |
| 浏览器几何与实机观察 | Chromium 15/15，有实际截图；实际 WebView2 装备调制已同步并显示装备提示，覆盖范围有限，未代签全消费者／NativeHud 专项 |
| 原生候选 | C++、Rust、Core 与固定 WebView2 构建通过；build identity 为 C4C2A451…；production prepare 27 项、policy 50/50；实际候选首份调制快照通过，进程正常退出，三份真实存档哈希未变；未部署 |
| 独立旧 AS2 oracle | 完整 5,723 条严格转换及逐字段比对零差异，107/107 配件覆盖；同一输入全部通过 Windows 正式服务，Node／ClearScript 输出一致。原一小时 runner 超时仍为失败，后续同 SWF 连续采集独立验收，身份与来源见回执 |

本机实际验证修正了四个内容问题：AVM1 的缺失信息上限会令 `isInformation` 为 undefined，producer 现明确转换为 Boolean；药效分派使用现役 `restoreToughness`；独立配件的 authored 安装条件补齐展示投影；枪械射速避免 JavaScript 浮点尾数。配件资格与数值计算仍由 AS2 决定。

实际技能边界采样另发现数组的字符串转换差异：AVM1 保留空洞的 `undefined` 和显式 `null`，JavaScript 默认数组转换会省略。技能展示现使用窄转换；原始配对行逐字复制为测试 fixture，标题、正文与 Document 同时回归。该单行见证来自尚未闭合的采集，只作局部回归依据，不升级为完整 oracle。

`expectedDetails` 按真实出口检查：Web 为原兼容 HTML 的纯文字，inventory/details 为原 Choice 完整内联文字。独立采集字段全部保留，不用新引擎结果重写 expected。

验证入口另修正了两处问题：CharacterBuild 静态检查跟随实际 `BorrowedLongGunShot` 写入口，继续检查受控主角、扣除/移除、dirty 与资产记录；Choice 异常模拟补齐 CS6 要求的不可达返回语句。Map loot 首编译先后暴露两个 SI16 初始化跳转越界，调整 LootContainerServiceTest 与 StageRunSessionTest 的方法定义位置；145 个和 81 个方法逐字节一致，执行次序与断言不变。新鲜 Map loot 已取得 198/12/932 三套零失败、Box 53 条断言及 Compiler 0/0、32K retry 0。原失败和一次未消费指令的超时保留；超时宿主与临时恢复文件由维护者关闭/清理后重新核验。

HUD 测试改为检查现役输入 DTO 的版本、类型、名称及数量 41006；引擎另验证库存与 HUD 最终数量文字、快捷键，真实 HUD runner 也已通过。佣兵测试修复 CS6 不接受的带点字符串字面量键，性格 fixture 使用不同配置 ID，隐藏池断言按既有 README 与 Spawner 测试检查合并候选池及 hidden 索引；125/24/31/11 项、Compiler 0/0、32K retry 0。佣兵业务代码未改。弹药数据旧总数 44 经六份原 XML 独立核对为 49；数据与基线一致，逐项弹药断言及 9 把幽灵装填白名单保持，重新编译取得 149/149。原失败日志与修正依据分别保留。

采集工具的 JSON helper 已在真实 AVM1 对照基线 LiteJSON 通过 45 个用例，暂停/恢复微型测试通过。全量清理 Output 前新增帧边界暂停、原始计数复核与原始日志前缀检查；不完整日志仍须拒收。下一轮还包含 12 条显式技能边界 fixture 和 20 条真实 BaseItem 配置强化样本，不冒充真实存档或实战。

新增强化补采曾在物品加载前构造失败，该轮 14 条记录、21 个错误已拒收；补采改到原始语料完成后。另一轮冷启动未消费目标指令便退出，短时触发任务记录为 `0x41306`，没有目标 SWF；原因未确定，不据此声称内存耗尽。后续先由不限时编辑器任务独立启动，再取得两阶段零文档回执，绑定 PID/启动时间后调用原采集脚本。Windows PowerShell 5 的空备份文件名调用已改用真实 XML 备份。该轮已确认暂停，后续宿主检查请求没有被消费；尚未清理 Output，随后发生系统重启。

07:45 复核时，系统最后启动时间为 00:33，旧宿主与采集进程均已结束。已归档该轮安装的测试入口、scratch 记录、未消费控制请求及残留日志；测试入口按准确模板、runId 与 SHA 核对后经既有恢复函数恢复，原工程绑定已还原。该轮保持“中断／不完整”，没有补造 footer 或完整 oracle。主线此时已前进至 `e83fc73d…`，本轮隔离候选仍基于既定起点，未合入其他批次。

随后使用新隔离基线保留全部 Output，不进行中途清空。原 runner 在 09:26 达到 3,600 秒异步等待上限，留下失败及不确定状态记录，测试入口已按事务恢复。观察守护在编译成功后验证唯一宿主 PID／启动时间、准备源哈希、SWF SHA 和原始日志前缀，并持有全机编译互斥；同一个 SWF 继续输出至 09:44。没有重新运行或补造 expected，也没有修改原脚本的期限或失败结论。

后续独立结果：原始 begin／end 唯一且闭合、失败数为零、5,723 条记录与 footer 完全一致；其中 inventory 3,898、Web 1,791、技能边界 12、正文边界 2、五种真实配置各 2/5/10/13 级共 20 条，107 种配件全部覆盖。严格转换后的 corpus SHA-256 为 `f912530b21c3a67467dbb4c96a03564e4e6d532991a602ecbf5fa64521133c5a`，当前引擎逐字段 `fresh-avm1-match`、零差异。同一 5,723 条输入再经过 Windows 正式 TooltipService 的校验、V8 和输出清理；Node／ClearScript 逐行一致，回执绑定当前 `c70bc251…` bundle。该结果补齐独立内容比对，不代签原 runner 健康通过、真实玩家槽位、完整资源探测或 UI 旅程。

完整证据保存后，既有两阶段退出入口确认测试文档所有权并退出同一 CS6；核对进程消失、两任务空闲、测试入口恢复后，归档并清理精确超时标记，工程绑定恢复主线。原超时失败永久保留；未来重复采集需要给离线观察足够时间，不能仅删除标记重跑，或以不完整日志降低验收标准。

数组修正前 bundle 的独立 Windows Host 基准 P95/P99 为 0.3639/0.5580 ms，合成快切末尾 queued/active 均为零。该进程不包含真实 GameInput，回执明确 `gameInputMeasured=false`；其 RSS 不是已有 Launcher 的 Tooltip 净增量，运行时同机另有 CS6 构建负载。

当前 `c70bc251…` bundle 另有独立 Windows Host 新回执：1,801 个合成输入、10,806 次直调的 P95/P99 为 0.2614/0.4187 ms；1,000 次快切最后队列和活动订阅均为零、最后请求尾延迟 2.2329 ms。它仍在同机 CS6 工作时测得，不能据两次不同条件断言性能提升。fixture 移动新增的四个 CR 行尾已清理，归一后字节完全相同、方法 token 与断言不变；原编译行为回执和单独 EOL 证明均保留。

完整发布准备已验证 27 项生成物。首轮实际 production policy 的 50 项中，49 项通过，唯一失败为竞技场检查器仍读取已迁出的 `ObtainMethodsBuilder.as`。检查器已接到现役 TypeScript 展示层，同时检查 AS2 的已发现来源投影及 `dropType/carrierScope` 字段；XML、佣兵预设、物品闭包和原有禁止项均保留。定向检查、九项来源领域回归及完整 production policy 重跑均通过。正式 50/50 回执绑定 release tree `d9885818593494c609b73cf3409c9cab0f916836`；后续新增回执与本文属于文档差异，不能将该 receipt 写成另一个源码 tree 的验证。

实际运行使用同 build identity／payload closure 的隔离候选，并使用从真实存档只读复制的独立测试槽。标准无人值守 opener 到达 `PG-TUNE-OPEN`：权威快照、attempt／panel／view session、实际 PID、Core SHA 与运行路径均已绑定。界面可见背包 20/50、蓝晶手套 +13 和同步状态，装备提示包含强化、获取及升阶内容。指针点击被 WebView2 子窗口归属检查拦截；激活后的一次重试同样被拒，未绕过检查，未完成配件预览或提交。截图只作为本轮界面观察证据，不替代所有消费者、DPI 或生命周期验收。随后经身份复核的既有关闭入口退出候选，确认进程消失及三份原玩家存档 SHA-256 均未改变。
