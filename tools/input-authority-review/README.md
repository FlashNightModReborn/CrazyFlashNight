# R5 输入权威独立复验

本工具沿用原 G01–G60 与 RET-01–26。`criteria.json` 保留两份裁决输入的名称、SHA-256 和逐项断言。验收报告保留原始结果、运行边界与独立复核结论。原 R5 档案可作为历史输入，报告只写新的文件。

## 决定性局部复验

在仓库根目录执行。`$candidate` 指向已构建的绝对候选目录，`$runRoot` 指向本轮空闲证据目录。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/input-authority-review/run-domain.ps1 `
  -CandidateRoot $candidate -OutputDirectory (Join-Path $runRoot 'modifier-domain')

powershell -NoProfile -ExecutionPolicy Bypass -File tools/input-authority-review/run-native.ps1 `
  -CandidateRoot $candidate -OutputDirectory (Join-Path $runRoot 'native')
```

- `run-domain.ps1` 使用已核候选实际 Core DLL，在新建且从未切入的 Win32 桌面内直接给夹具 HWND 发消息。它校验正常、world-only 几何变化和本地位置变化。页签与关闭、带和不带 Move、两种组序分别取样。正控检查持 D/Shift 的 epoch 和位图。负控检查旧票停止和下一次新点击恢复。`receipt.json` 绑定候选和执行文件，`result.json` 保留每一次原始 oracle。退出 `2` 表示断言失败，退出 `1` 表示夹具或环境错误。此回放只覆盖 T1 和本地几何负控。
- `run-native.ps1` 复用 `launcher/native/world-compositor/build-dev.ps1 -Target selftest`。构建前后都核工作树与候选的 v2 身份，保留原 stdout、退出码与 SHA-256。可不占用桌面运行。改变 candidate 源码后用最终候选重新执行。
- Host focused 使用 `tools/run-focus-sol-recheck.ps1 -Phase integration -Filter '<本次完整过滤器>'`。过滤器包含所需测试类别和 `SolIndependentWindowsTraceTests`，用于保留实际加载的测试程序集与 Core 的 SHA/MVID。执行前冻结工作树。原路径回执包括 `command.json`、`source-inputs.json`、`build.log`、`recheck.trx`、`loaded-binaries.json` 和 `exit.json`。工具按 `UnitTestResult` 读取 skip，以同一最终源码的必测测试名取证。
- 转场夹具沿用 `tools/run-scene-transition-smoke.ps1 -OutputDirectory <新的仓库内 tmp 相对路径> -CandidateRoot <绝对候选>`。从可输入桌面串行执行。成功时 `state=fixture_executed`、`reportPixelsVerified=true`，其 `gameE2e=false` 保留。另用完整游戏验证场景先就绪/捕获先就绪、尾部关闭、真实地图 OpenIntent、P 与真实源内容。C0 品红标记、误捕和源停推使用各自 WGC 证据。仓库另有 `launcher/perf/flash-compositor/README.md` 的现役隔离夹具入口。

G19/G20 的隔离负控可在无桌面要求的阶段先准备。准备器只构建现有的管理夹具，逐字节绑定已核候选的 `FlashCompositorNative.dll`，再原样复制 G2 runner 和它的专用素材。预留可输入桌面与 GPU 时段后才运行证据目录中的 G2 脚本。

```powershell
$wgcEvidence = Join-Path $runRoot 'wgc-fixture'
powershell -NoProfile -ExecutionPolicy Bypass -File tools/input-authority-review/prepare-wgc-fixture.ps1 `
  -CandidateRoot $candidate -OutputDirectory $wgcEvidence
powershell -NoProfile -ExecutionPolicy Bypass -File tools/input-authority-review/run-wgc-fixture.ps1 `
  -Preparation (Join-Path $wgcEvidence 'preparation.json') -Adapter intel
```

将 `intel` 换成正在核验的适配器。G2 原始 `summary.json` 与各 case 文件中的 `s-chrome-only`、`stalled-under-cover`、`marker-leak` 和恢复/正常样本共同解释故意失败的退出码。冻结只作用于夹具自建源，Flash 片段也使用独立素材。正式游戏复验另记录 `world.bullet_source` 的解码帧、源与呈现采样、S/P/F 和实际拓扑。G2 的裸 WGC ROI 结果不包含游戏正常生产 UI 的全部遮挡条件。

准备脚本无窗口读取实际 Native ABI 与两种诊断结构大小。ABI 不符时终止准备，并保留原始导出信息。准备完成后，索引中的 `wgcFixturePreparation`、`wgcFixtureRun`、`wgcFixtureSummary` 指向同一候选夹具的准备、Default 执行和用例汇总。五个真实用例和四个命令参数负控各有原始回执。报告核实际加载的 managed 与 native SHA。

汇总时填写 `wgcFixturePreparation`、`wgcFixtureSummary` 和运行包装输出的 `wgcFixtureRun` 路径，机器核候选二进制、实机桌面和每项正负控。`liveGpuTrace` 指向同次实际游戏 FocusTrace，配合 `startupProcess` 自动输出生产源标签推进和独立的 P 提呈子证据。两者仍由 G19/G20 对照原条件复核。

协议长链使用原始 `live` 回执。支持延后发布的 Host 还应提交 `liveHostLauncherLog`，指向同次未节选的 launcher 日志。验收按同 PID、启动 attempt、S/P/F 和源 HWND 绑定发布、设为 Ready 及 reveal 边界。AS2 提前发送的 `bootstrap_ready` 可能仍在 Host 队列中。仍持有 F 焦点的启动记录及原始聚合失败一并保留。存在真实 Host Ready 后的原始焦点阳性时，运行期仍为失败。证据缺失或串入别的 attempt 时，运行期不签通过。

## 正常 HUD 入口

主控独占 Default 桌面。用同一隔离槽，从正常 HUD 扳手进入修改器，选择物品页、关闭、重开。至少记录一次静止旅程与一次持 D/Shift 旅程。使用 OS 命中的点击。需要自动控制时把注入事件标为 `os-sendinput`，实体输入用 `operator-physical`。同一份注入回执只能满足对应 T3 刺激，实体 G 项按原要求继续验收。

使用本候选的 rolling FocusTrace，保留 v2 原始日志。用 `trace.start` 的 `session`、PID、Core 路径与候选及实际启动回执对齐。每次 HUD、物品页、关闭和再次打开记录对应的 `mouseId`。`firstSeq` 到 `lastSeq` 围住这一组完整刺激与 AS2 `modifier.closed accepted=true`。HUD HWND 和从属接收窗由当次独立 Win32 观测填写。缺失日志或事件丢失时保留阻塞。保留第一个可复现失败，后续重复用独立目录。

入口索引至少含下列字段。路径相对于这份索引。示例值只展示格式。

```json
{
  "schema": "cf7-modifier-default-entry.v1",
  "runId": "entry-final-01",
  "trace": "FocusTrace.jsonl",
  "traceSession": "<trace.start session>",
  "observed": {
    "pid": 1234,
    "processPath": "<实际隔离 Core EXE 绝对路径>",
    "runtimeMode": "isolated_candidate",
    "buildIdentity": "<SHA-256>",
    "payloadClosure": "<SHA-256>",
    "coreSha256": "<SHA-256>"
  },
  "desktop": {"inputDesktop": "Default", "threadDesktop": "Default"},
  "slot": "cf7_agent_r5_entry_check",
  "attemptId": "<实际进档 attempt>",
  "stimulus": "os-sendinput",
  "windowCompleted": true,
  "cases": [
    {
      "id": "stationary-1",
      "firstSeq": 100,
      "lastSeq": 300,
      "hudReceivers": [123],
      "ownedReceivers": [],
      "hudOpenMouseIds": ["mouse.1.3", "mouse.1.6"],
      "pageMouseId": "mouse.1.4",
      "closeMouseId": "mouse.1.5",
      "holdDShift": false
    },
    {
      "id": "held-1",
      "firstSeq": 301,
      "lastSeq": 500,
      "hudReceivers": [123],
      "ownedReceivers": [],
      "hudOpenMouseIds": ["mouse.1.9", "mouse.1.12"],
      "pageMouseId": "mouse.1.10",
      "closeMouseId": "mouse.1.11",
      "holdDShift": true,
      "keyboard": {
        "beforeAdmittedD": true,
        "afterAdmittedD": true,
        "beforeAdmittedShift": true,
        "afterAdmittedShift": true,
        "epochBefore": 17,
        "epochAfter": 17
      }
    }
  ]
}
```

`M-ENTRY` 从 raw 序列关联 `mouse.down/up/route`、`modifier.press`、begin/commit、切页和关闭，核实际接收窗、token、generation 与关闭后不可见。未知 Up、未收到事件、明确拒票与 AS2 未收到关闭各有可区分的回执。焦点准入正常归属和已修改的代码都要保留实际数据。`rootOwner` 等 Windows 字段保留观测值，对有真实 `GW_OWNER` 但 `GA_ROOTOWNER` 返回自身的已知 Modifier 句柄，用同一次创建与实际接收窗做绑定。

同轮 1600×900 样例还可验证 `M-PRESENT-HUD`。在证据索引中配置 `hudCapture` 为含 `desktop.jsonl`、`entry-cycles.json`、`process.json` 和原 PNG 的真实运行目录。报告逐轮检验左下血条红青比例与右下技能组亮中性色。比较目标以客户区为准，只取原图里的组件矩形，并排除与修改器窗相交的区域。阈值取同轮开窗前和关窗后两个正例的较小值的 40%。持键组覆盖重开帧。可单独用 `python -B tools/input-authority-review/hud_pixels.py --run-root <原操作回执目录> --output <新 JSON>` 生成带图片路径、哈希、区域和比例的回执。

## 汇总 CLI

先把原生候选验证输出写入本轮证据目录。此处调用 verifier 的 `-Json` 工作树一致性路径，`-IntegrityOnly` 的结果也可用来证明候选包完整性。

```powershell
& tools/verify-runtime-bundle-v2.ps1 -ProjectRoot (Get-Location).Path -DeploymentRoot $candidate -Json |
  Set-Content -LiteralPath (Join-Path $runRoot 'candidate.json') -Encoding UTF8

python -B tools/input-authority-review/report.py --candidate-root $candidate `
  --evidence (Join-Path $runRoot 'index.json') --output (Join-Path $runRoot 'qualification.json') `
  --require M-DOMAIN --require M-CANCEL-LOCAL

python -B tools/input-authority-review/test_report.py
```

`index.json` 使用 `cf7-input-authority-evidence.v1`。`candidateVerification`、`live`、`startupProcess`、`domain`、`entry`、`native`、`smoke`、`smokeDesktop`、`asLoader`、`focus`、`legacyLatency`、`consumerClosure`、`historicalRetirement`、`independentReviews` 是可选原始文件路径。没有证据的项仍输出。`focusedRuns` 是原 runner 目录列表，`requiredFocusedTests` 是当前必测测试名或类名子串。非零 focused、必测 skip 和实际程序集证据分别判断。原 `run-r5-live-gate.js` 的 `r5-live-disabled.json` 可直接作为 `live`，它只覆盖对应 Agent probes，WGC/正常 OS 入口需各自原始回执。`startupProcess` 指向主控原 `process.json`，含同次实际鉴权读回的 `processPath`、`runtimeMode`、PID/身份及同目录的 `ready.json`。此入口只证明选定正式游戏进了隔离槽。`smokeDesktop` 是该次 smoke 启动环境的 `threadDesktop`、`inputDesktop` 记录。非输入桌面在前台准入处超时记为夹具原始失败和交互阶段未执行。

`focus` 使用 `cf7-input-authority-focus.v1`，填写 `observed` 实际候选身份、`probeStatus` 原 status 文件、`coveredCases`、`droppedRecords` 和带 `stage`、`case`、`querySucceeded`、`beforeFlashFocused`、`correctionAttempted` 的观测行。生命周期范围是 startup、text、transition、external_focus_loss、fault、exit。真运行期先计数再处置，启动纠正另记。缺任一生命周期或 hook 观测，零值只能作为样本计数保留。原混口径延迟文件经 `legacyLatency` 仅归档诊断样本，预算结论用同轨迹/时钟配对的新证据。

`passiveSession` 和 `focusAudit` 分别读正式游戏的查询样本与归档进程日志。两者按 PID、候选与 Guardian 根窗关联。`nativeEditors` 校验七类原生输入框的真实草稿、Enter、Esc 与 Tab 正反向记录。`globalPanelRoutes` 校验 Help 和 KShop 各自的实际输入、截图和关闭实例。`originalMapRoute` 读取具名地图角色位移。

对库存 `live` 回执，保留 `rawCaseChecks` 和原始全生命周期焦点裁决。业务焦点单独关联同次启动的 `bootstrap_ready` attempt、实测 S/P/F、两个线程的 Win32 样本和 ready 后原生计数。较晚焦点、直接查询阳性或运行计数阳性使业务项失败，无法确定阶段的样本继续阻断。原探针报告维持原字节。

如运行文件与松散资源分开发布，在 `materialManifest` 中绑定游戏使用的实际资源路径与 SHA，并将 `material-before.json`、`material-ready.json`、`material-exit.json` 放在 `startupProcess` 同目录。独立签署要给出这一组合材料 SHA。相同运行候选在不同资源组合下各有判定。`bountyLive`、`bountyObserverCompile`、`bountyProductionProof` 串起观察版 SWF 的确切原件、真实游戏中该次 primary 手势以及对应正式 SWF 静态身份。

### 普通输入延迟的可比诊断

先把实机角色置于同一无敌对单位、不会撞墙的走廊，使用同样的起点、双边可用的默认 D 键绑定、画质/分辨率和输入链诊断配置。记下实际 Guardian 前台 HWND、隔离槽和进档 attempt。在各自候选的真实 Default 桌面独占窗口用 8 次 120ms 的 D 脉冲测试。两轮之间重新布置同一个起点和观测条件。用 `--role baseline` 和 `--role candidate` 生成两份原始回执。

```powershell
node tools/input-authority-review/observe-latency.js --project-root $runProjectRoot `
  --candidate-root $runCandidate --slot $isolatedSlot --attempt-id $attemptId `
  --foreground $guardianHwnd --scene $frozenSceneLabel --role candidate `
  --samples 8 --output (Join-Path $runRoot 'ordinary-candidate.json')
```

执行器在发键前核 exact PID/前台和未按住的 A/D。先用一次 D 验证实际有移动空间。每次 D 的观察窗完成后用相同宽度的 A 回位，回位确认单独记录。两边保持相同轨迹，位置漂出准备区就停止。默认走现役已验证的 `#eval:hero._x` 单项读，只给实际位移的上下界。双边都选择 `--observer latched-movement` 时，预读现有 AS2 `inputFrameSeq`、keyboard epoch、键盘字和英雄 X。预读失败会在第一次输入前停止。报告用同进程单调钟上下界，保存每个请求的出入时刻与输入确认时刻，未观测到结果保留缺样。`ordinaryLatencyBaseline` 和 `ordinaryLatencyCandidate` 指向两份同口径回执，汇总逐样本计算上下界、配对差分与中位数区间。同期 `render_sample` 等日志只供关联观察，动作对应 P 像素缺样时保留空值。脉冲、高密度、原生采样分配、IPC、物理输入和源→P 仍按原 G51 验收，普通输入区间无预算结论。

`ordinaryLatencyPairPlan` 与 `ordinaryLatencyBaselineAnchor` 用于核固定种子、同起点、精确旧候选以及两次游戏进程、前台和清理的接续。种子原件仍应在两侧项目的隔离 QA 存档目录，起点与关停回执和每侧的 `ordinary.json` 一同归档。

正式矩阵的逐层裁决由独立验收者填 `cf7-input-authority-independent-reviews.v1`。顶层给 `reviewer`、`candidate` 的三份 SHA 和 `reviews`。每行给 `id`、`part`、`status`、`reason`、原始来源 `raw` 的 `path`、`sha256`、`locator`。G 项的 `part` 取原合同 T 层，T4/T5/T6 的 `stimulus` 分别为 `wgc`、`operator-physical`、`maintainer`。RET 的 `part` 是 `productionInbound`、`replacementBehavior`、`runtimeZeroOrNarrow`。工具会核验候选身份和引用的文件字节，原始失败仍优先。`--require` 让指定修复子项或 G 项的阻塞返回非零。从 `e2e_verified` 和各 `missingLevels`、`missingParts` 判断完整验收的缺口。
