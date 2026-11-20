# #130 库存可选摘要隔离候选

基线 main：`23ec828cd04c783c86abb016c1f080eb814d41ba`。本次只交源码候选与 Linux 机器结果，Issue 保持 Open；未发布 runtime、未重编 SWF、未触碰玩家存档。

## 先有实现与调用证据

基线 `InventoryTask.TrySanitizeItem` 已在坏摘要时复制、删除摘要并递归复验，因此不从头写校验器。实际调用除库存 snapshots/discarded 外，还有 `CraftingTask` 的 prototype/receipt 与 `ItemUseTask.RewardStash` 的暂存行。没有发现这两个调用方专门依赖坏摘要容错的测试；原 InventoryTaskTests 有直接要求公共入口容错的测试，与 #130 的公共严格边界冲突，本次按授权调整。

实现把已有副本复验移到私有 `TrySanitizeInventoryResponseItem`，仅库存 snapshots/discarded 调用。公共入口遇坏摘要返回 false。展示标记由 Host 生成，AS2 若传入同名字段仍因未知键被拒绝。正常缺省摘要与有效摘要保持原语义。核心字段、确认投影、租约、窗口及版本沿用原校验；不增加 ledger、命令或解锁能力。

另有可证响应差异：原测试只断言旧/部分 snapshot 不清 Host 写门，没有断言回给 Web 的 success；基线仍回 success=true。现改为在尚处 needs_reconcile 时返回明确失败，避免 Web 把该读当 ready。完整 post-unknown 覆盖探针的既有解锁条件保持原样。

## 验证与边界

Linux 已执行（完整命令与合并结果见[总交接](issue-130-132-linux-handoff.md)）：

- `node tools/test-inventory-runtime.js`：92/92；新增 normalized marker、三类写成功/版本保留/重复、丢回包后失败探针与 fresh read 恢复，无写重放。
- `node tools/test-workbench-primitives.js`：13/13；问题徽标与 ARIA、正常无摘要、confirmed 隔离。
- `node tools/test-inventory-workbench-modules.js`：38/38，含两条生产丢弃展示路径。
- `node tools/test-kshop-presenters.js`：41/41。
- `node tools/test-workbench-components.js`：17/17。
- `node tools/test-panel-contracts.js`：70/70；以本轮 JSON 为完整测试真源。
- 三视口 Chromium 直接加载现有 KShop/NPC harness：每次 157/157、133/133；额外调用生产 `InventoryUI.renderOwnedSlot`，确认问题徽标文字、可见宽度和 ARIA，pageerror 为 0。该临时 Linux 驱动及报告随交接证据包保留，不替代原 Edge runner 的额外量测和原生验收。

新增/加强 Windows Host 用例：七种 mutation 摘要隔离、公共严格、坏核心/lease/confirm/version/伪造标记拒绝、确定业务拒绝、原回包丢失后的断线/迟到/重连/全容器探针、旧/部分坏摘要探针不能解锁。本容器无 dotnet/PowerShell，未编译或执行这些 xUnit 用例。Node 模型与浏览器不代签 Host/Flash/WebView2。

## Windows 最短合成验收

1. 在保留本机差异的隔离分支导入本候选，先核对基线与本轮三个主题提交，执行 `git diff --check`。
2. 用仓库 exact SDK `10.0.300`，运行 `dotnet test launcher/tests/Launcher.Tests.csproj --filter "FullyQualifiedName~InventoryTaskTests|FullyQualifiedName~CraftingTaskTests|FullyQualifiedName~ItemUseTask"`，然后 canonical `powershell -File launcher/tests/run_tests.ps1`。
3. 重跑上述 Node 门以及 `node tools/run-kshop-harness.js`、`node tools/run-npcshop-harness.js`。确认 warning 徽标/丢弃提示、Host idle 与 Web ready 一致；旧/部分 probe 都阻止 ready、无自动重放。

Host 或相关消费者回归未通过、Host/Web 锁不一致、任何新解锁资格或盲重放均为 no-go。Linux 结果只允许进入 Windows 合成验证；完整原生验证之前不建议合入生产。真实游戏/隔离资产旅程和正式 runtime 发布另行授权与记录，不能据此自动关单。
