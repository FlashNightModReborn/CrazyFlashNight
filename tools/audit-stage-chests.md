# 地图箱 XML 统计审计

`audit-stage-chests.ps1` 用 XML DOM 扫描 `data/stages/**/*.xml`，因此 XML 注释中的示例不会被当成关卡实例。它分别报告：

- `branchDeclarations`：有效 XML 中六种箱型的 `Identifier` 声明数；`CaseSwitch` 的各个条件分支分别计数。
- `instanceNodes`：包含这些声明的实际 `Instance` DOM 节点数。
- `logicalIdentities`：按“相对文件 + `SubStage id` + `Instance id`”折叠的逻辑身份数；节点缺少 `id` 时才使用同级序号。它与 `instanceNodes` 不是同一口径：当前“超市废墟”有两个互斥主线进度的 DOM 节点复用同一逻辑身份。
- `modes`：静态求值 `_root.难度是否达到("修罗")` 后，分别给出修罗 / 非修罗的网格箱与直投箱数量。
- `lootRollouts`：显式进入 Web 战利品链的网格箱。每条 rollout 必须同时具有唯一 ASCII `chestRolloutId`、`lootFlowProfile=web-loot-v1` 与当前唯一允许的 `unlockPolicy=skip`；direct 型、S0 marker 共存、重复 ID、缺失掉落、非法数量或规则数超容量都会失败关闭。

默认运行会同时校验当前基线（28 个分支声明、27 个 `Instance` DOM 节点、26 个逻辑身份；修罗 9/17，非修罗 8/18；一个显式 Web loot canary），漂移或任一 XML 解析失败均返回非零：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/audit-stage-chests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/audit-stage-chests.ps1 -Json
```

`-StageRoot <dir> -NoBaseline` 用于审计独立 fixture，而不套用生产基线。回归测试入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-audit-stage-chests.ps1
```
