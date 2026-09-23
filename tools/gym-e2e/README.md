# 健身训练隔离候选验收

`run-candidate.js` 只操作固定测试槽 `cf7_agent_gym`。来源槽按原始字节读取，训练只在克隆槽进行；运行前必须显式指定唯一隔离候选、来源槽、build identity 与 payload closure。它通过 `agent_control openGym` 调用正式 AS2 木人桩入口，再用候选页面的可见按钮和 CDP Input 触发操作；不能从 HTTP、脚本或 DOM 直接发送训练业务命令。

先执行 `node tools/gym-e2e/self-test.js` 和只读预检：

```powershell
node tools/gym-e2e/preflight.js --candidate-root '<候选绝对路径>' --seed-slot '<来源槽名>' --allow-read-only-live-seed --expected-build-identity '<64位SHA256>' --expected-payload-closure '<64位SHA256>'
```

只开关候选面板、不点击训练按钮：

```powershell
node tools/gym-e2e/run-candidate.js --candidate-root '<候选绝对路径>' --seed-slot '<来源槽名>' --allow-read-only-live-seed --expected-build-identity '<64位SHA256>' --expected-payload-closure '<64位SHA256>' --execute-isolated-candidate --observe-only
```

完整付费旅程需要另外显式授权测试槽写入的开关：

```powershell
node tools/gym-e2e/run-candidate.js --candidate-root '<候选绝对路径>' --seed-slot '<来源槽名>' --allow-read-only-live-seed --expected-build-identity '<64位SHA256>' --expected-payload-closure '<64位SHA256>' --execute-isolated-candidate --allow-clone-training-writes
```

完整旅程固定为：开始木人桩金币项目并在完成前切换，核验健身业务字段零变化；重新开始并完成金币永久空攻加成，核验金币、加成、经验、SOL；完成 K 点技能点项目，核验 K 点、技能点、SOL；关闭候选并以新 PID 重启，核验读回。被动观察器检查当前候选进程身份、CDP 端口归属、实际加载 Web 脚本摘要、可信页面点击及 AS2 完成回执。所有截图、哈希链 transcript 与报告写在 `tmp/workbench-live-e2e/gym/<run>/`。成功收尾会保留独立测试槽，并清理其克隆锁和恢复记录；不会回写来源槽。

任何中断若留下 `tmp/workbench-live-e2e/locks/cf7_agent_gym.clone.lock` 或 `manual-recovery/cf7_agent_gym.json`，不得直接删除或再跑。先确认无 Launcher/Flash 进程、读取 exact 恢复记录及锁摘要，然后按 `clone-save-guard.restoreAbandonedCloneFromRecovery` 的离线恢复合同，把目标还原到记录中的 `targetBefore` 并证明来源槽摘要不变。不要以旧备份覆盖来源槽。
