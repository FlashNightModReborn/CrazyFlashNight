# 装备调制真实旅程验收

这里有三个相互独立的 gate。不得把“打开工作台”写成“preview 已通过”，也不得把“preview 已通过”或内存态 commit 写成“已持久化并可重启读回”。

## PG-TUNE-OPEN：生产 opener 与首个权威 snapshot

`run-unattended.js` 只打开生产装备调制工作台，并停在首个权威 snapshot；不会点击业务控件，不会发送 preview/commit，也不会尝试业务写入。

默认绑定工作区正式 `runtime/`：

```powershell
node tools/equipment-tuning/run-unattended.js `
  --seed-slot crazyflasher7_saves2 `
  --shutdown
```

验收未部署的本地 runtime candidate 时，必须精确传入 producer 返回的目录：

```powershell
node tools/equipment-tuning/run-unattended.js `
  --seed-slot crazyflasher7_saves2 `
  --candidate-root tmp/runtime-candidates/v2/c-<identity>-<builder>-<run> `
  --shutdown
```

runner 会把该路径透传给 `automation/start.ps1 -CandidateRoot`，并在操作存档和进入游戏前后绑定真实运行进程。现有 Host `/status` 不提供二进制身份，因此核验使用 `launcher_ports.json` 的 PID、操作系统返回的进程路径、Core DLL SHA-256、runtime manifest，以及 candidate metadata。期望与实际的进程路径、Core 哈希、build identity 或 payload closure 任一不符都会立即失败。

JSON/Markdown 报告固定记录 `runtimeMode`、`processPath`、`coreSha256`、`buildIdentity`、`payloadClosure` 和 `verified`；`runtimeMode` 只允许 `formal_runtime` 或 `isolated_candidate`。只有 `verified: true` 的报告才能证明本轮验收实际运行了所选二进制；它仍不代表 candidate 已正式 promotion。

任何 clone/SOL 变更前，runner 都会枚举 Launcher Core 进程：没有可认证 Legacy HTTP context 时必须为零进程；有 context 时也只允许该已认证 PID 唯一存在。“端口不可用”不能再被解释为“Launcher 不存在”。`saves/` 祖先、seed、旧 target 与新 target 都必须是 exact regular/non-reparse/realpath；target 以同目录独占临时文件写入并替换，Windows 文件身份使用 BigInt `dev/ino/size/mtimeNs` 复验。

`seedSha256`、`seededTargetSha256`/`targetSha256` 永久表示播种时事实，不会被启动写回覆盖。首个权威 snapshot 后，runner 至少取得两个相同完整 JSON 样本并以单调时钟稳定 1000ms，另写 `gateBaseline`。若 baseline 与播种 SHA 不同，只允许 `startup_normalization.v1` 的窄语义等价：移除根 `lastSaved`、统一空 `mods`，并只对四个明确的来源缓存数组排序；角色与等级必须不变。这个等价还必须由同一 attempt 的严格顺序 `start 水位 < handoff < title-frame < Archive <= snapshot` 解释，且 Archive 的 slot/path/UTF-16 char count 全匹配，否则失败。baseline 绑定 attempt、panel/view、snapshot call/source/stateRef/line、捕获后日志水位、语义 SHA、角色/等级，以及句柄读取所得 BigInt `dev/ino/mtimeNs`；闭合后再次复验完整 runtime identity 与唯一 Launcher 进程。旧版或半程 report 不能补签，必须重新运行 opener。`--report/--report-md` 自定义路径仅供 open-only 诊断；后续 live receipt Gate 只接受默认 canonical `tmp/equipment-tuning/unattended/<run>/run-report.json`。

上述本地证据用于拦截陈旧进程、竞态、路径替换和误绑定；报告 JSON 没有 Host 签名或 MAC，因此不是针对恶意同用户进程的密码学 attestation，不得把本门的通过外推为该威胁模型已关闭。

## PG-TUNE-PREVIEW：computer-use 真实点击后的精确 preview 闭环

先运行 opener，且不要传 `--shutdown`：

```powershell
node tools/equipment-tuning/run-unattended.js `
  --seed-slot crazyflasher7_saves2
```

拿到输出中的 `run-report.json` 后，启动独立 verifier：

```powershell
node tools/equipment-tuning/verify-journey.js `
  --open-report tmp/equipment-tuning/unattended/<run>/run-report.json `
  --timeout-ms 180000
```

开始点击前必须把确认方式切换为“逐次确认”，不得使用会在 preview 后自动提交的“单件快捷”。当 verifier 显示 `waiting_for_computer_use_preview` 后，使用 Launcher Agent Runtime computer-use；该入口不具备合格输入能力时，才回退 Codex computer-use。真实点击一个可用候选并等待权威 preview。verifier 本身只轮询 Host 日志，不控制 UI、不调用业务命令、不写存档。

verifier 从 opener 报告锁定并 fail-closed 核对：

- `runtimeIdentity.verified === true`，且模式只能是 `formal_runtime` 或 `isolated_candidate`；
- preview 前后都从当前进程重新核验 `processPath`、Core SHA-256、build identity、payload closure、PID 与 HTTP port，不能只信 opener 报告或端口连续；
- verifier 启动时先拒绝 snapshot 后已发生的 candidate/preview/commit/reconcile，再建立独立 `interactionLogWatermark`；所有签名事件必须严格晚于该水位，不能重放 opener 完成后、prompt 前的动作；
- `panelInstanceId`、`viewSessionId`、source、candidate、operation、intent 和 Web callId 为同一个精确 tuple；
- Web `candidate_hit → preview_issued → preview_adopted` 与 Host `equipment_tuning_preview_settled` 同轮闭合；
- Host outcome 为 `success`；最终 adopted 状态必须为 `pendingCount=0`、`tokenPresent=true`、`commitReady=true`。
- Web 诊断必须明确投影 `confirmationMode=safe`、`autoCommitPending=false`；最终 adopted 还必须是 `writeState=idle`、`needsReconcile=false`。
- preview 闭环后继续观察至少 1 秒；同一 panel/view 出现 Web commit、inventory refresh、reconcile 或 Host `equipment_tuning_commit_settled` 即失败，不能签发 preview-only 收据。

跨 session、candidate 或 callId 的响应、缺事件、旧水位前事件、日志截断/重置、任一运行身份字段漂移均失败。`--open-report` 在读取任何 JSON 前就被限制为 `tmp/equipment-tuning/unattended/<run>/run-report.json`；玩家档或任意目录文件不能被当作 report 读取。收据固定写入：

```text
tmp/equipment-tuning/journeys/<timestamp>-<pid>/journey-receipt.json
tmp/equipment-tuning/journeys/<timestamp>-<pid>/journey-receipt.md
```

`PG-TUNE-PREVIEW` 只证明真实 preview 闭环。它不证明 commit、背包刷新、reconcile、持久化或存档完整性；这些结论仍必须由独立的 clone-save commit receipt 承担。

## PG-TUNE-E2E：clone-only commit、archive 持久化与重启读回

先运行 opener，且不要传 `--shutdown`。目标必须是 opener 固定创建的 `cf7_agent_equipment_tuning` clone；E2E verifier 会拒绝其他 agent slot、任何 `crazyflasher7_saves*` 玩家档、发生过漂移的 clone，以及未绑定 exact runtime identity 的报告：

```powershell
node tools/equipment-tuning/verify-commit-journey.js `
  --open-report tmp/equipment-tuning/unattended/<run>/run-report.json
```

verifier 显示 `waiting_for_computer_use_safe_commit` 后，使用 Launcher Agent Runtime computer-use；该入口不具备合格输入能力时才回退 Codex computer-use。保持“逐次确认”，完成两个独立动作：点击一个可用候选并等待权威预览，再点击“提交”。不要使用“单件快捷”。

内存提交阶段必须按同一 panel/view/source/candidate/intent 串联：

- Web `candidate_hit → preview_issued → preview_adopted → commit_issued → commit_adopted → inventory_refresh_settled`；
- Host `equipment_tuning_preview_settled → equipment_tuning_commit_settled`，commit 必须具备同一 preview call/token reference、`transactionIdPresent=true`、`snapshotPresent=true` 与稳定 `stateRef`；
- `noOp=false`、新 lease 已刷新、`pendingCount=0`、最终 `writeState=idle`、`needsReconcile=false`；
- 同轮不得出现 `reconcile_issued/adopted`。这签的是“权威提交已明确成功，因此无需对账”，不是未知写入故障对账；后者必须由 A2 fault journey 单独验收。

verifier 在 commit 前后都通过运行进程重新读取并比较 `processPath`、Core SHA-256、build identity、payload closure、PID 与 HTTP port；不能只沿用 opener 报告或只看端口连续。显示 computer-use prompt 前会重放验证 strict marker chain 与 startup archive 行、拒绝 snapshot 后已有业务动作并建立新的交互水位；它从当前 clone 重算 `startup_normalization.v1` 语义 SHA、角色与等级，且等待候选/预览/提交的每次轮询都会用句柄绑定读取重新核对 SHA、字节数、BigInt 文件身份、mtime 与 `lastSaved`，Gate 期间任何漂移立即失败。

显示 `waiting_for_clone_archive_and_exit` 后，关闭调制面板；操作上应走游戏现役 SAFEEXIT，收到存盘成功后点击“退出游戏”。verifier 不发送保存或退出命令；机器 Gate 只接受严格晚于 commit 的 `[ArchiveTask] Shadow saved: cf7_agent_equipment_tuning`，其 Archive UTF-16 char count 必须等于句柄读取的最终 clone 文本长度，并要求 clone 文件 SHA-256、`lastSaved`、同一背包物品的 `lastUpdate` 和 `value` 全部真实变化，随后旧 Launcher PID 必须退出。进程退出后会从 canonical、non-reparse 的同一 `logs/launcher.log` 水位补采最终 archive 行，避免 HTTP 端口先关闭造成漏证。该证据证明 clone archive 持久化与进程退出，但没有绑定 SAFEEXIT arm / done / `EXIT_CONFIRM` session，因此收据固定写 `safeExitUiJourneyVerified=false`，不得外推为“SAFEEXIT UI 旅程已验收”。

随后 verifier 自动以同一 formal runtime 或 isolated candidate 启动全新 Launcher，不重新播种 clone；重启前必须枚举到零个 Launcher Core，不能用“没有可用端口”代替进程不存在。新身份建立、runtime ready 与最终 readback 关闭前都必须再次枚举并证明只有同一个新 PID；旧 PID 退出后若残留或另一个 Launcher 抢先出现，Gate 会拒绝启动/采用，而不是向未知会话发送 start。新进程复用 opener 的 start/open 流程并重新要求 fresh handoff、真实 title-frame receipt、无 reveal watchdog、唯一 agent save-entry。显示 `waiting_for_reload_source_selection` 时，如工作台未自动选择原物品，使用 computer-use 点击提示的同一背包物理槽。新 panel/view 的 `equipment_tuning_snapshot_confirmed` 必须在相同稳定背包坐标上读回与 commit 完全相同的 `stateRef`，最后再次复验完整 runtime identity，才写出 `e2e_verified`：

```text
tmp/equipment-tuning/commit-journeys/<timestamp>-<pid>/receipt.json
tmp/equipment-tuning/commit-journeys/<timestamp>-<pid>/receipt.md
```

verifier 自身不会点击 UI，不发送 preview/commit/reconcile/save 命令，只允许现役 `agent_control start/openEquipmentTuning` 控制入口；在读取 report 前即拒绝 canonical opener 目录之外的路径，并只读取 opener clone，不读取或写入任何玩家档。clone archive receipt、clone 实变、旧 PID 退出、fresh restart、同状态读回或任一次 identity 复验失败时都 fail-closed，不能用半程 JSON 作为 PASS。

## A2 Inventory 正常写后验收据

2026-08-02 的 A2 authority/data live journey 已完成，后验只读 verifier 用于在全局日志轮转前重新固化其联合证据：

```powershell
node tools/equipment-tuning/verify-inventory-mutation-journey.js
node tools/equipment-tuning/verify-inventory-mutation-journey.js --check
```

默认模式只读取冻结 opener report、`logs/launcher.log`、精确 seed/clone JSON、candidate metadata 与 runtime bytes，向 stdout 输出 `equipment-tuning.inventory-mutation-readonly-receipt.v1`；它不连接 CDP、不启动或停止 Launcher、不写存档。Gate 精确复算 isolated candidate 的 DLL/EXE 哈希、identity/closure、首进程 owner/Web callId/AS2 callId、唯一 `autoTransfer`、Archive、安全退出、同 clone SOL 的未重播种重启、fresh Inventory session/snapshots 与最终磁盘 delta。

Shadow 与 Inventory response 在 Host 日志中被截断，verifier 不解析或补造被截内容：初始坐标由 report 绑定的 seed SHA/语义归一化合同及 seed 文件独立复算，目的槽由 `mergeThenEmpty`、无 merge candidate、seed 首空槽和最终磁盘 delta 联合证明。输出固定声明 synthetic DOM transcript 未机器持久化、`isTrusted=false`、SAFEEXIT UI 未签、physical input/A4/A5 未签以及 `NOT_DEPLOYED`。`--check` 只在临时目录运行 2 个正例与 10 个关键负例，不访问工作区存档或运行时。

## 离线合同检查

```powershell
node tools/equipment-tuning/run-unattended.js --check
node tools/equipment-tuning/verify-journey.js --check
node tools/equipment-tuning/verify-commit-journey.js --check
node tools/equipment-tuning/verify-inventory-mutation-journey.js --check
node tools/equipment-tuning/run-checks.js
```

`verify-journey.js --check` 包含 3 组正例（含 384 字符 intent 边界与 verifier fresh interaction watermark）和 25 组负例：除 cross-session、cross-candidate、cross-callId、缺事件、旧事件外，还覆盖 prompt 前动作重放、fast/auto-commit、Web/Host commit、失败 outcome、错误终态、事件乱序、伪 Host 子串、过长 intent、低于 1 秒的静默窗、日志 reset/gap、Launcher PID/端口变化、runtime mode/process path/Core/build/closure 漂移，以及把玩家档路径冒充 opener report。

`verify-commit-journey.js --check` 是纯离线合同检查，不访问存档或运行时；当前包含 7 组正例和 71 组负例，覆盖 seed/gate baseline 分离、窄语义重算、稳定窗与样本数、BigInt 文件身份、snapshot/attempt/交互日志水位绑定、`start < handoff < title-frame < Archive <= snapshot`、startup archive 的新鲜度/path/chars、完整 runtime mode/process path/Core/build/closure identity 漂移、玩家档 report 路径预读拒绝、跨 panel/view/source/candidate/intent/call、token reference、no-op/失败/未知提交、reconcile 误签、刷新 lease、最终 archive char count、clone 文件与物品实变、旧 PID 退出、重启前残留 Core/重启中第二 Core拒绝，以及 reload source/stateRef/session 不匹配；另在正例内验证进程退出后的磁盘日志补采。`run-checks.js` 还会在专用临时目录覆盖 BigInt 文件身份、同目录替换、target/seed 文件 symlink 拒绝合同、reparse ancestor 拒绝、未认证/多 Launcher 拒绝和 verifier 等待期 clone 漂移；当前 OS 允许创建真实文件 symlink 时还会执行实物负例，完成后删除该临时目录。
