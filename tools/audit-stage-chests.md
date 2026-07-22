# 地图箱 XML 统计审计

`audit-stage-chests.ps1` 用 XML DOM 扫描 `data/stages/**/*.xml`，因此 XML 注释中的示例不会被当成关卡实例。六类箱子的 grid/direct 分类直接从 `PresetManager.as` 的默认 `row/col` 推导，Web 上限直接读取 `LootContainerService.as` 的 `MAX_WEB_COLUMNS/MAX_WEB_CAPACITY`，不在工具内维护第二份箱型表或能力常量；真源缺失、重复、畸形或超出当前能力会使审计失败。它分别报告：

- `branchDeclarations`：有效 XML 中六种箱型的 `Identifier` 声明数；`CaseSwitch` 的各个条件分支分别计数。
- `instanceNodes`：包含这些声明的实际 `Instance` DOM 节点数。
- `logicalIdentities`：按“相对文件 + `SubStage id` + `Instance id`”折叠的逻辑身份数；节点缺少 `id` 时才使用同级序号。它与 `instanceNodes` 不是同一口径：当前“超市废墟”有两个互斥主线进度的 DOM 节点复用同一逻辑身份。
- `modes`：静态求值 `_root.难度是否达到("修罗")` 后，分别给出修罗 / 非修罗的网格箱与直投箱数量。
- `autoRoutedGridDeclarations`：所有网格箱声明。运行时按正整数 `row/col` 统一进入 Web 战利品链，不再由每箱 rollout marker 决定。
- `presetShapes` / `shape-override`：前者记录从运行时 preset 真源解析出的六箱 shape 与分类；关卡 `Parameters` 若自行覆盖 `row` / `col` 会使按 preset 的静态全量审计失真，因此当前直接报错。若未来确需逐实例 shape，必须先让审计合并 preset 默认值与 Parameters override，再放宽此门。
- `obsoleteLootRolloutMarkers`：已停用的 `chestRolloutId` / `lootFlowProfile` / `unlockPolicy`。任何生产声明仍含这些字段都会失败关闭，避免恢复双轨路由。
- 网格掉落会校验名字存在于 `data/items/list.xml` 权威目录、条件分支可静态求值、概率/总数合法，并要求原始掉落规则数不超过对应 preset 的 `row×col` 容量；否则运行时物化器必然拒绝，必须在静态阶段提前失败。`最小数量` 或 `最大数量` 任一缺省时按旧行为私有归一为 `1/1`，不要求地图 XML 填冗余默认值。

默认运行校验全部语义约束；声明、节点、逻辑身份、难度投影和摇滚公园注释数只作为报告，不构成隐藏的数量白名单。合法增删关卡箱无需同步工具内硬编码计数；解析失败、未建模条件、未知分类、无效掉落、容量越界、shape override 或旧 marker 才返回非零：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/audit-stage-chests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/audit-stage-chests.ps1 -Json
```

`-StageRoot <dir> -NoItemCatalog` 可用于只验证结构与分类的独立 fixture。回归测试入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-audit-stage-chests.ps1
```
