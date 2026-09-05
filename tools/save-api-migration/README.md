# save-api-migration — SaveManager API 分层 R1 调用点基线与回归门

R1 路线（[原始裁决存档](../../docs/裁决存档/SaveManager-API分层路线-2026-09-04.md) §3.1/§3.2）的调用点清单与验证工具。当前覆盖步骤 6–14 的源码迁移；发布范围按现役入口与编译闭包核定，不能由历史源码标签推导。最后核对代码基线：commit `4ae00a176265b7d00ea38364d545d29cbe601efa` 加本轮 R1 工作树。

| 文件 | 作用 |
|---|---|
| `callsites.v1.json` | 机器可读调用点 manifest：38 条物理记录 / 32 个逻辑调用点（17 strict + 15 debounce；D2/E6 分别于步骤 6/12 拆为 markDirty+requestSave 两物理点）+ 3 处已接通 canonical `存档系统.markDirty()` + C6 关联子层 flush 基线 + 当前发布 SWF hash 基线 |
| `check-callsites.js` | 回归门扫描器：全库独立扫描，精确数量断言（`==` 非 `<=`），扫描命中与 manifest 一一对应，任何漂移非零退出 |
| `test-callsites.js` | 迁移合同负例与生产 SceneChanged 顺序回归 |
| `check-published-scripts.py` | 按本地时间轴/linkage 可达图核对 FFDec 帧脚本，单列未引用和共享导入的源码副本 |

## 用法

```bash
node tools/save-api-migration/check-callsites.js
node tools/save-api-migration/check-callsites.js --json               # 机器可读汇总
node tools/save-api-migration/check-callsites.js --verify-swf-hashes  # 额外校验 baseline SWF SHA-256
```

- 默认每次必过的是**数量断言 + 一一对应 + paired parity**；SWF hash 是 Slice 0 快照证据（asLoader/UI SWF 会被其他切片正常重发布），只在发布前后对照时用 `--verify-swf-hashes` 显式校验，漂移后同步 manifest `baseline.swf`。
- 输出末尾的"逐调用点 targetApi / reasonId 汇总"供逐切片迁移时审阅。

## 口径

### 什么算一个调用点

- **逻辑调用点**：裁决 §3.1 分类的一个语义归属单位（A1-A6 / B1-B5 / C1-C6 / D1-D2 / E1-E13），共 17 strict（A/B/C 组）+ 15 debounce（D/E 组）= 32 个。
- **物理调用点**：源码中一处实际的存盘 API 调用文本。C1/C2/C3/C5 因主 XFL 与 `flashswf/UI` 同源双份各含 2 个物理点；D2/E6 在步骤 6/12 分别由一个逻辑点拆为 `markDirty` + `requestSave` 两个物理点，故 32 逻辑点当前对应 38 物理点（scripts 11 strict + 2 debounce + 1 canonical markDirty；XFL 10 strict + 13 debounce + 1 canonical markDirty）。
- manifest 每条记录 = 一个物理点，`callsiteId` 指向逻辑点，`physicalId` 全局唯一。

### 旧入口 family（扫描口径）

| family | pattern | 范围 | 精确数 |
|---|---|---|---|
| `forceSave` | `_root.强制存盘(` | scripts 生产 + XFL XML | **scripts 0 / XFL 0**（步骤 10/13–14 后归零） |
| `directFlushNow` | `flushNow(` | scripts 生产，排除 `SaveManager.as`（定义宿主）与 `通信_lsy_原版存档系统.as`（shim 委托） | **0**（步骤 11 后归零） |
| `autoSave` | `_root.自动存盘(` | scripts 生产 + XFL XML | scripts 0 / XFL 0 |
| `localSave` | `_root.本地存盘(` | scripts 生产 + XFL XML | 0 / 0（死委托） |
| `saveShopCart` | `_root.保存购物车(` | XFL XML | 2（C6 关联，不纳入四层） |

### 四层 API family（扫描口径，步骤 6 起）

| family | pattern | 范围 | 精确数 |
|---|---|---|---|
| `apiMarkDirty` | `存档系统.markDirty(` | scripts 生产 + XFL XML，排除两个定义宿主 | scripts 4 / XFL 1 |
| `apiRequestSave` | `requestSave(` | 同上 | scripts 2 / XFL 13 |
| `apiFlushDurableNow` | `flushDurableNow(` | 同上 | **scripts 8 / XFL 10**（含 A2/B1 与 C1–C6） |
| `apiFlushBeforeTransition` | `flushBeforeTransition(` | 同上 | scripts 3 / XFL 0 |

- 四层 family 同时匹配 shim 形态（`_root.存档系统.x(...)`）与类内直调形态（`sm.x(...)`）；`SaveManager.as`（定义宿主）与 `通信_lsy_原版存档系统.as`（shim 委托）经 `SAVE_API_DEF_HOSTS` 排除。
- `apiMarkDirty` 的 scripts 精确数 4 = `canonicalMarkDirty` 区段 3 处（Slice 1 已由 `installSaveApiShims()` 接通的 SkillLoadoutService:839 / StageRunSession:1345 / ProcurementPlanService:711）+ D2.markDirty（步骤 6）。
- 迁移状态（2026-09-04，**步骤 6→11 完成**）：D1/D2 迁 `requestSave`/`markDirty+requestSave`；B3/B4/B5、A4/A5/A3 迁 `flushDurableNow`；A1/A6/B2 迁 `flushBeforeTransition`；**步骤 10 A2 Reward（`flushSave(cutName)` wrapper 内核）与步骤 11 B1 SceneChanged 迁 `flushDurableNow`**。**scripts 侧旧入口（forceSave / directFlushNow / autoSave / localSave）至此全部归零**，legacy shim 继续保留；裁决 §7.2 的完整发布周期从正式发布起算，当前源码迁移完成不等于可以降级或删除 shim。wrapper 内部迁移（A4 `flushSave` / A5 `flushSaveVerified(reason)` / A3 `performStrongSave` / A2 `flushSave(cutName)`）只换内核目标，wrapper 形状与失败语义不变；受影响测试套件（LootContainerServiceTest / KShopCheckoutServiceTest / NpcShopPanelServiceTest / StageRunSessionTest）的 `_root.强制存盘` double 已按同函数镜像补挂 `_root.存档系统.flushDurableNow/flushBeforeTransition`，计数与失败注入零漂移。
- **A2 的领域计数不得退化**（裁决 Slice 6）：Reward 存盘次数门的两层计数——`__lootSaveCalls`（领域层 `_root.强制存盘` double 镜像到 `flushDurableNow` 后的调用数）与 `_rewardSaveImageCaptures`（物理层 save-image 成像数）——必须仍各等于 N+1，cut 序列精确相等；不得因内部不再调用 `_root.强制存盘` 就只测 SaveManager 物理桶。打桩点见 `LootContainerServiceTest.installRewardPersistedSaveHarness`（:4381 镜像行）。

- **扫描范围**：`scripts/**/*.as` 生产文件（排除 `test/` 目录、`*Test.as` / `*Tests.as`、gitignored 的 `TestLoader.as` scratch runner）+ `CRAZYFLASHER7MercenaryEmpire/**/*.xml`（含 DOMDocument.xml 与 LIBRARY）+ `flashswf/UI/**/*.xml`。
- **注释判定**：逐文件 `/* */` 块注释状态机 + 行内 `//`；XML 只扫描 `<script><![CDATA[...]]></script>` 内的代码，保留原始行号并排除 `<!-- -->`。XFL 中 3 处已注释的 `//_root.自动存盘();`（宠物进阶页.xml:185、进阶方案详情页.xml:447/:841）据此不计入。
- **字符串字面量不排除**：当前目标命中区域无字符串内含 pattern 的形态；若未来引入会产生多计——这是安全方向的误报，报警后人工复核并更新本口径，不得静默放宽。

### paired 副本规则（duplicateGroup / pairRole）

- C1/C2/C3/C5 各是一个 `duplicateGroup`，含恰好 `live`（`flashswf/UI/...` 独立资源源码）与 `mainCopy`（主 XFL 库源码）两个物理点。这两个值只标识历史副本位置：不保证主库副本被编译，也不保证独立 SWF 有现役 UI 入口。主库的 runtime shared import 不携带本地脚本；实际编译归属由 FFDec 门单列。
- parity 门（裁决 §5.5）：同组两条记录 `targetApi` / `reasonId` 必须一致，且 CDATA 实际 API/reason/dirty guard/裸语句必须与各自记录一致、`expectedSwf` 必须不同；Slice 9 迁移时双份同改，改一漏一即语义分叉（裁决否决项 20）。
- C4（主 XFL 副本内无对应第二按钮）与 C6（商城主mc 无主 XFL 副本）无 pair，`pairRole: "sole"`。E 组全部无 pair。

### liveState 取信规则

| 取值 | 含义 | 取信依据 |
|---|---|---|
| `live` | 已定位现役调用或实例入口 | scripts A/B/D；main 淡出 E1；医务室整形 E6；TABLET → toggleTablet 的 E7；main 仍导入的 C3/C4 兼容共享库。此字段不代签正式入口业务验收 |
| `unproven` | 尚无足以决定退役的业务证据 | E2/E4/E5 仍保留源码与无条件 request；编译未引用不自动授权删除 |
| `suspect_legacy` | 历史兼容源码或正式入口已被接管 | E3、E8–E13、C6、C1/C2/C5 两份源码及 C3.main；具体生产路由与本轮产物处置见 `baseline.swf.r1Reason/r1Disposition` |
| `dead` | 已证实无生产调用 | 本基线无调用点级 dead；`_root.本地存盘` 与 `_root.存盘商城已购买物品` 为入口级死委托，记入 manifest `legacyApiRegistry` |

- `suspect_legacy` 的删除条件（裁决 §3.1/Slice 8）：**静态不可达证据 + 运行覆盖证据**双证据齐全才允许删；"运行没打到一次"不足以证明 dead。E3/E11/E12 live 则无条件 `requestSave`。
- C6 仍保留 `suspect_legacy`：正式 SHOP 入口已指向 Web kshop，本轮不刷新旧 UI SWF；保留源码、shim 与“购物车 partial flush + full strict flush”双行为，不把路由复核扩张成删除兼容资产的许可。
- 主 XFL paired 副本的 `suspect_legacy` **不影响 parity 门**：无论 liveState 结论如何，Slice 9 必须双份同改。

### reasonId 冻结性质

`reasonId` 是 Slice 0 冻结的**注册表提案**：裁决已给定字符串的按裁决（`safe_exit`、`asset_tx.commit`、`item_use.open_commit`、`stage.return_base`、`scene.changed_safety_net`、`character_creation.start_tutorial`、`settings.apply`/`settings.save`、`character_build.finalize`、`manual_save`、`shop.panel_close`、`shop.cart_edit`、`reward.<cutName>` 八 cut）；裁决只给定 API 未给定字符串的（A5 loot 三类、C1-C4、C6、E1-E13）为本 manifest 拟定的低基数值，Slice 1 建立 reason 注册表时以此为准，改动必须同轮更新本 manifest 并说明理由。C1/C2 两按钮同一语义，共用一个 reason（`reward_ui.task_panel_close`）以保持低基数。

### returnConsumed

调用者是否读取旧入口返回值。`true`：A2-A6、B2-B5（`=== true` 判定或经桥读取）；`false`：A1/B1（裸语句）、C1-C6（XFL 裸语句）、D/E 组（debounce 无返回消费）。Slice 4 迁移 A1 时注意：AS2 当前忽略 Boolean，Host 必须依赖本轮 `sv` 门控（裁决 §5.6）。

## 基线字段（baseline）

- `headCommit`：manifest 行号的代码基线。行号漂移（如合入新提交）后，更新受影响记录的 `line` 并在该字段写明新基线；callsites.md 封包基线（`776db2ae26`）与本基线的已知漂移已记录在 `lineNumberNote`。
- `swf`：当前工作树的 SHA-256/体积快照，asLoader 同时记录函数数/最大函数体。`r1Disposition=published` 表示本轮保留的 5 个发布更新；`retained_previous_binary` 表示恢复接手时原字节的 6 个旧产物。它是本轮处置，不是永久构建白名单。
- XFL 帧脚本依据是 manifest 指向的版本化 CDATA；原始临时封包无需存在也能运行扫描。FFDec 导出可重建，保留在 `tmp/`；当前生产路由、编译闭包与人工旅程范围见 [R1 收尾记录](../../docs/R1存盘API迁移收尾-2026-09-05.md)。

## 漂移处理流程

1. **行号漂移**（其他提交合入导致 `line` 失效）：scanner 报"无有效代码 / 不含 legacyApi / 未命中"→ 重新定位行号，更新对应记录 `line` 与 `baseline.headCommit`，并在最终提交信息中注明漂移原因。数量不变。
2. **新增 / 删除调用点**（scanner 报"扫描命中不在 manifest"或数量断言失败）：不得直接改 manifest 压平警报——先确认该改动已经过裁决分类（§3.1 语义归属），再更新 manifest、counts 与本 README，并在提交信息中写明分类依据。
3. **SWF 重发布**：用 `--verify-swf-hashes` 检出 hash 漂移后，将新 hash 写入 `baseline.swf`（asLoader 同时刷新 `functions` / `maxFunctionBytes`）。
4. **迁移施工**（Slice 2+ 改旧入口文本）：该切片提交必须同轮把受影响记录的 `legacyEntry` / `legacyApi` 改记为新 API 文本与 family（或移入已迁移区段），否则 scanner 会以"未命中 / 数量不足"拒绝——这正是本门的存在意义。

## R1 步骤 10–14 收尾（2026-09-05）

- C1–C6 固定 `flushDurableNow`；普通奖励关窗与 `manual_save` 不在 transition allowlist。C1/C2 共用 `reward_ui.task_panel_close`，C3/C4 分别使用注册的 item close/claim-all reason，E13 使用 `ui.player_info_inventory_close`。
- E1/E9/E10 保留原 dirty guard；E6 canonical markDirty + request；其余 E 组保持无条件 request。E3/E11/E12 保留源码并在 `_root.__saveApiReasonProbeEnabled === true` 时输出 `[SaveApiReason] callsiteId|requestSave|reasonId`。`suspect_legacy` 不因迁移或未命中而改为 dead。
- C6 两处 `_root.保存购物车()` 与关闭时 partial→full 顺序保持；没有合并失败窗口。legacy API 委托仍兼容旧 SWF。
- `xflStrictPhysical=10` / `xflDebouncePhysical=13` 是分类数；新增 `xflForceSavePhysical=0` / `xflAutoSavePhysical=0` 单独表达旧入口扫描数，不能把两种计数混用。
- 运行 `node tools/save-api-migration/test-callsites.js`（17 项）：错误 API/reason、dirty 守卫、返回消费、CDATA 外伪命中、重复调用、注册表、C6、legacy probe 与生产 SceneChanged 回调顺序。随后运行 `check-callsites.js`（38 物理点 / 32 逻辑点）。
- 先沿正式入口与编译闭包选定实际需要刷新的目标，再经 CS6 publish 与 fresh Compiler `0/0`。对保留的新 SWF 运行 `python -X utf8 tools/save-api-migration/check-published-scripts.py <swf> <export-dir>`（导出必须来自该份实际 SWF）。该门按 XFL 时间轴引用及 linkage export 根求可达符号，精确核对实际生成的 API/reason 多重集合、C6 两处 partial 调用并拒绝旧入口。编译未引用或 `linkageImportForRS` 副本记录为 `sourceOnlyCallsites`，继续通过源码 parity。该工具不判断生产路由，也不要求为已由 Web 接管的旧 UI 人为恢复按钮再验收。
- 2026-09-05 批次实际试编 11 项后收窄为 5 项交付：asLoader、main、平板、基地特殊 UI、奖励物品。其余 6 项保留旧 SWF 与新源码，旧 shim 因此仍必要；不得把源码扫描旧入口为 0 外推为全部历史 SWF 无旧入口。
- `run-map-loot-tests.ps1` 保留原 675 项并增加真实 N=50 边界，现为 **676/676**；`run-character-build-tests.ps1` 中 SaveManager 增加 **18** 项，现为 **352/352**（七套合计 **824/824**），证明领域 wrapper 真委托后的 N+1 pack/doSaveAll/SOL flush 与 SceneChanged clean/pending 物理行为。PAT 的 open/openMany 分别检查首次写前的 canonical dirty，direct-authority 清单 **23**，原行为套件 **117/117**。
- 机器验证、SWF 发布与人工旅程分开记录；当前交付证据和人工剩余项见 [R1 收尾记录](../../docs/R1存盘API迁移收尾-2026-09-05.md)。
