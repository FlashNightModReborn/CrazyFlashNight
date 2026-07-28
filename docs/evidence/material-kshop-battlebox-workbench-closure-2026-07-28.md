# 材料、商城与战备箱体验优化正式关闭证据

**状态**：`compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`

**日期**：2026-07-28（UTC+08）

**源码身份**：feature commit `7b21f679cb6bb82d108a3b8fe8cbd19af050a073`，release freeze commit `7d869c5eadf224953b2c61ec7a6ceee2ca03055f`，tree `6dcd424849964d5b174c559d350a9693b59e56f8`，lightweight immutable tag `runtime-build-v2/20260728-material-shop-storage-workbench-v1`。

**正式部署记录**：promotion commit `40675cae8264a5330904731b9dd8871a2263723a`。

本文冻结本轮材料入口、情报溢出、金币/K 点商城数量交互、战备箱双栏工作台，以及对应 Launcher runtime 发布与标准入口证据。平板电脑迁移、巴别塔文档与任何旧 UI fallback 均不在本轮范围。

## 1. 最终能力边界

- Native HUD 新增材料直达入口，直接进入 `crafting view=materials`；旧 material-only 页面与 fallback 不再保留。
- 材料档案延续双栏工作台：左侧目录、右侧详情，支持完整/紧凑切换且无既有偏好时默认紧凑；详情同时呈现持有量、怪物/关卡/商店来源，以及配方和装备用途。
- 情报继续使用每个情报自身的 `maxvalue`。敌人掉落先按原始数量掷骰，再按剩余容量分流；可接收部分正常生成，溢出部分按该情报 `price` 精确转换为金币，零价剧情情报不制造无价值拾取物。拾取、任务、成就与药剂奖励统一在实际写入前重新结算，避免同屏竞争后越界或“捡了但没增加”。
- 金币商城与 K 点商城共用严格整数数量控件；高上限使用分段线性/对数 range，并保留数字输入、键盘步进与滑条。K 点目录单击或 `+` 每次加购一件，拖拽仍可选；精确数量只在真实结算二级页调整，目录浮层和购物车不再保留重复数量编辑。
- K 点商城、材料档案和战备箱统一提供双栏工作台帮助入口。K 点购物车使用项目主题的窄滚动条，隐藏原生系统箭头与白色滚动槽。
- 战备箱无既有偏好时默认紧凑，空箱也保持正常可用网格；保留拖拽精细调整，并提供普通点击批量暂存、显式批量存入/取出，以及 `Ctrl+单击` 单件快速转移。批量栏在最低画布和 0/1/5/50 件数据下均不得溢出或重叠。

## 2. 自动门

- Launcher xUnit：`1583/1583`。
- KShop browser harness：三视口各 `111/111`；覆盖主题滚动条、帮助、默认紧凑、目录/购物车冗余数量控件退役、结算二级页、严格整数输入，以及上限 `999999` 的对数映射和 24px 命中目标。
- NPC Shop browser harness：`89/89`；Crafting browser harness：三视口各 `99/99`。
- 共享 workbench components：`12/12`；focus integration：`13/13`；inventory workbench modules：`15/15`。
- 情报静态政策扫描：59 个配置条目；fresh TestLoader 为 EquipmentInventory `28/28`、NPC `46/46`、Inventory `142/142`、Crafting `34/34`，Compiler Errors/Warnings `0/0`。
- production policy receipt：`22/22` passed。

Crafting harness 在与其他重型浏览器矩阵并行时曾出现 3 个动画计数时序失败；停止并发后立即以同一源码独立重跑，三个视口均为 `99/99`。最终通过结论采用这次无资源争抢的 fresh rerun。

## 3. Exact isolated candidate E2E

### 3.1 身份

- 本地 exact-byte candidate：`tmp/runtime-candidates/v2/c-3f7887adf904-08846e81b3-20260728t111053832z-cd70abc1`。
- 云端 candidate：`tmp/runtime-cloud-results/7d869c5eadf224953b2c61ec7a6ceee2ca03055f/run-30364763726/candidate`。
- 两者均通过 23-file `RuntimeBundleV2`，逐文件字节、build identity 与 payload closure 相同。
- build identity：`3F7887ADF9041DFEDA74EEA26040A3628919A725B04D322FCE667791425F7B44`。
- payload closure：`A9B142A417CF2AC45EA19845144569391FCDEE8DF4235F5279A1EC5F0F9022F2`。
- manifest SHA-256：`236462357B4E13B7F2E5EFE2C14F0433CBAA75EAACEDEAB7D81EA17183325513`。
- Core DLL SHA-256：`DADE2CC2206B9981FF390250BD0DF8FB5CC7393E8EF9FA378567B5FB9009CCA1`。
- 实际 candidate Core PID `21088`，进程路径精确位于上述本地 candidate；退出后进程已消失。

### 3.2 实际 GUI 与运行链

使用 Windows Computer Use 操作标题页、游戏内 Native HUD 与真实 WebView2：

1. 从 Native HUD 打开材料档案，确认 223 条目录默认紧凑、完整/紧凑切换和标准帮助入口存在；Andy 套装碎片详情同时显示持有量、来源与五项装备用途。
2. 打开战备箱，确认双栏默认紧凑、空位尺寸正常、帮助入口、批量存入/取出、`Ctrl+单击` 提示与两侧数据均可见，批量栏无溢出。
3. 打开 K 点商城，确认 227 件目录、真实 5 种/141 件购物车、单击加购、标准帮助和主题滚动条；购物车行只保留数量文本与移除，不出现第二套 `- / +` 数量编辑。

candidate attempt 为 `63b297110dcc4d59a1dbd7f4a9f3ac70`；`launchState=Ready`、`socketConnected=true`、`gameEnteredObserved=true`、同 attempt runtime load ack 与 `readyForRuntimeAutomation=true` 联合成立。真实日志随后出现：

```text
panel_request panel=crafting source=nativehud_materials initData view=materials
CraftingTask -> Flash: craftingMaterials
CraftingTask -> Flash: craftingMaterialDetail itemName=Andy套装碎片
PanelHost opened: workbench
ShopWV shopPanelOpen
ShopTask -> Flash: shopBulkQuery
```

## 4. v2 双故障域发布

- request：`9AC9E3C9A1BC5162F17881DDB37A6F23C8AAAA9830A808CAF4648EDE60753771`。
- artifact source：`F773F7A6F6BA565CABAC14587C2BF7EFCA41AD5F9FFF1F2B89C75E4250F7CAFC`。
- producer recipe：`DE5E1C0263A803CC416598BFDB074C20E5D22C594DF601EC231BC702793BFE7D`。
- toolchain lock：`7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD`。
- GitHub hosted run：`30364763726`，success；API tag、workflow `GITHUB_SHA` 与 run `headSha` 均绑定 source commit `7d869c5eadf224953b2c61ec7a6ceee2ca03055f`。
- GitHub OIDC/Sigstore builder identity：`1BDD1B0F419E0CA384E59986DBC1C9C9195A01CFEAF0838E116A8AD13B9BCEC3`，faultDomain `github-hosted-windows`。
- 本地 X509 keyId：`28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3`，faultDomain `physical-host-a`；私钥保持 CurrentUser 不可导出。
- production policy：`F8C5D87ADA848323D0C35FD6DC0AC895327BC7A382FFBE7997287C7AA646440B`；final receipt SHA-256 `E1604B933786DBA76C989A18AFC401AB7F1E925AE677FFCE27F3729C6B2A9A43`。
- promotion 时间：`2026-07-28T14:26:12.9287283Z`。
- promotion 只改写 `config/build/runtime-release-consensus.json`、`runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll` 与 `runtime/cf7-runtime-manifest.tsv`。
- 上一正式闭包保存在可恢复目录 `tmp/runtime-promotions/20260728T142549373Z-f02c3898feb74fecaa5646c50d4ddfe0/previous`。

promotion 后 `RuntimeBundleV2`、GitHub attestation replay、双 signer/双 faultDomain `RuntimeConsensus` 与根 bootstrap `--verify-only` 均为 exit `0`。

## 5. Formal standard entry

无参数执行根 `automation/start.ps1`，实际启动：

```text
Runtime Mode    : formal_runtime
Core Path       : runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe
Core SHA256     : DADE2CC2206B9981FF390250BD0DF8FB5CC7393E8EF9FA378567B5FB9009CCA1
Build Identity  : 3F7887ADF9041DFEDA74EEA26040A3628919A725B04D322FCE667791425F7B44
Payload Closure : A9B142A417CF2AC45EA19845144569391FCDEE8DF4235F5279A1EC5F0F9022F2
Deployment      : FORMAL_RUNTIME
```

- Guardian PID `19008`，最终由 `agent_control/shutdown` 正常退出。
- save slot `dev`，attempt `f6a0bf80251d46a0af8e2791d4e933f6`；`gameEnteredObserved=true`、runtime ack 同 attempt、`readyForRuntimeAutomation=true`，关闭面板后 `activePanel=null`。
- 正式 GUI 再次从 Native HUD 依次打开材料档案、战备箱和 K 点商城，确认同一默认紧凑双栏、帮助入口、来源/用途、批量交互、精简购物车与主题滚动条。
- 累积运行日志 `logs/launcher.log` 在关闭后为 979,229 bytes，SHA-256 `711EC1B80485E4D7B212083DA0C7ACB56E64E55C0F5B57611DABE5EDC50EB879`；其中 `22:31:18`、`22:31:41`、`22:32:21` 分别记录正式材料、战备箱和 K 点商城打开正链。

因此同一 immutable identity 已达到 `standard_entry_verified`。该结论由 candidate/正式进程身份、双生产者共识、运行态 attempt 回执、Host/AS2 日志和实际 GUI 共同组成，不由源码提交、测试计数或 consensus 任一项单独推出。
