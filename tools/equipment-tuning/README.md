# 装备调制无人值守验收

`run-unattended.js` 只打开生产装备调制工作台，并停在首个权威 snapshot；不会点击业务控件或发送 preview/commit。

默认绑定工作区正式 `runtime/`：

```powershell
node tools/equipment-tuning/run-unattended.js --seed-slot crazyflasher7_saves2 --shutdown
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

离线自检：

```powershell
node tools/equipment-tuning/run-unattended.js --check
```
