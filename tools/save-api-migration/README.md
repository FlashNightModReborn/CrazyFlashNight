# save-api-migration — SaveManager API 分层 R1 调用点基线与回归门

R1 路线（裁决回执 `tmp/adjudication-savemanager-api-20260904/gptpro.txt` §3.1/§3.2）的 **Slice 0：基线冻结** 工具包。纯工具建设，不改任何生产代码。

| 文件 | 作用 |
|---|---|
| `callsites.v1.json` | 机器可读调用点 manifest：36 条物理记录 / 32 个逻辑调用点（17 strict + 15 debounce）+ 3 处悬空 `存档系统.markDirty()` + C6 关联子层 flush 基线 + 当前发布 SWF hash 基线 |
| `check-callsites.js` | 回归门扫描器：全库独立扫描，精确数量断言（`==` 非 `<=`），扫描命中与 manifest 一一对应，任何漂移非零退出 |

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
- **物理调用点**：源码中一处实际的旧入口调用文本。C1/C2/C3/C5 因主 XFL 与 `flashswf/UI` 同源双份各含 2 个物理点，故 32 逻辑点对应 36 物理点（scripts 11 strict + 2 debounce；XFL 10 strict + 13 debounce）。
- manifest 每条记录 = 一个物理点，`callsiteId` 指向逻辑点，`physicalId` 全局唯一。

### 旧入口 family（扫描口径）

| family | pattern | 范围 | 精确数 |
|---|---|---|---|
| `forceSave` | `_root.强制存盘(` | scripts 生产 + XFL XML | scripts 6 / XFL 10 |
| `directFlushNow` | `flushNow(` | scripts 生产，排除 `SaveManager.as`（定义宿主）与 `通信_lsy_原版存档系统.as`（shim 委托） | 5（B1-B5） |
| `autoSave` | `_root.自动存盘(` | scripts 生产 + XFL XML | scripts 2 / XFL 13 |
| `localSave` | `_root.本地存盘(` | scripts 生产 + XFL XML | 0 / 0（死委托） |
| `danglingMarkDirty` | `存档系统.markDirty(` | scripts 生产 | 3（悬空调用） |
| `saveShopCart` | `_root.保存购物车(` | XFL XML | 2（C6 关联，不纳入四层） |

- **扫描范围**：`scripts/**/*.as` 生产文件（排除 `test/` 目录、`*Test.as` / `*Tests.as`、gitignored 的 `TestLoader.as` scratch runner）+ `CRAZYFLASHER7MercenaryEmpire/**/*.xml`（含 DOMDocument.xml 与 LIBRARY）+ `flashswf/UI/**/*.xml`。
- **注释判定**：逐文件 `/* */` 块注释状态机 + 行内 `//`；XML 额外处理 `<!-- -->`。XFL 中 3 处已注释的 `//_root.自动存盘();`（宠物进阶页.xml:185、进阶方案详情页.xml:447/:841）据此不计入。
- **字符串字面量不排除**：当前目标命中区域无字符串内含 pattern 的形态；若未来引入会产生多计——这是安全方向的误报，报警后人工复核并更新本口径，不得静默放宽。

### paired 副本规则（duplicateGroup / pairRole）

- C1/C2/C3/C5 各是一个 `duplicateGroup`，含恰好 `live`（`flashswf/UI/...` → 对应独立 SWF）与 `mainCopy`（`CRAZYFLASHER7MercenaryEmpire/LIBRARY/...` → 主 SWF）两个物理点。运行时 loadMovie 加载的是 live 副本；主 XFL 副本仍随主 SWF 发布。
- parity 门（裁决 §5.5）：同组两条记录 `targetApi` / `reasonId` 必须一致、`expectedSwf` 必须不同；Slice 9 迁移时双份同改，改一漏一即语义分叉（裁决否决项 20）。
- C4（主 XFL 副本内无对应第二按钮）与 C6（商城主mc 无主 XFL 副本）无 pair，`pairRole: "sole"`。E 组全部无 pair。

### liveState 取信规则

| 取值 | 含义 | 取信依据 |
|---|---|---|
| `live` | 有直接运行证据的现役路径 | scripts 生产代码路径（A/B/D 组）；loadMovie 直接加载的 flashswf/UI 副本（C1-C5 live、E6/E9/E10）；callsites.md 明示"每次场景切换淡出都经过"（E1） |
| `unproven` | 无 dead 证据也无直接 live 证据 | 裁决 V1 一律按 live 处理（无条件 `requestSave`），Slice 8 reason probe 观测后再定级（E2/E4/E5/E7/E8/E13） |
| `suspect_legacy` | callsites.md / 裁决明示 legacy 嫌疑 | E3/E11/E12（裁决 §3.1 点名）、C6（旧原生商城，Slice 10 单独裁决）、C1/C2/C3/C5 主 XFL 副本（callsites.md §9 注 1"实例化情况未逐一证实"） |
| `dead` | 已证实无生产调用 | 本基线无调用点级 dead；`_root.本地存盘` 与 `_root.存盘商城已购买物品` 为入口级死委托，记入 manifest `legacyApiRegistry` |

- `suspect_legacy` 的删除条件（裁决 §3.1/Slice 8）：**静态不可达证据 + 运行覆盖证据**双证据齐全才允许删；"运行没打到一次"不足以证明 dead。E3/E11/E12 live 则无条件 `requestSave`。
- C6 的初始 `liveState` 取 `suspect_legacy`：WebView 商城已接管 `shop*` 命令，旧 UI 疑似不再实例化但**未证实**；若 live，保留"购物车 partial flush + full strict flush"双行为，R1 中不得偷删第一笔（裁决否决项 18/19）。
- 主 XFL paired 副本的 `suspect_legacy` **不影响 parity 门**：无论 liveState 结论如何，Slice 9 必须双份同改。

### reasonId 冻结性质

`reasonId` 是 Slice 0 冻结的**注册表提案**：裁决已给定字符串的按裁决（`safe_exit`、`asset_tx.commit`、`item_use.open_commit`、`stage.return_base`、`scene.changed_safety_net`、`character_creation.start_tutorial`、`settings.apply`/`settings.save`、`character_build.finalize`、`manual_save`、`shop.panel_close`、`shop.cart_edit`、`reward.<cutName>` 八 cut）；裁决只给定 API 未给定字符串的（A5 loot 三类、C1-C4、C6、E1-E13）为本 manifest 拟定的低基数值，Slice 1 建立 reason 注册表时以此为准，改动必须同轮更新本 manifest 并说明理由。C1/C2 两按钮同一语义，共用一个 reason（`reward_ui.task_panel_close`）以保持低基数。

### returnConsumed

调用者是否读取旧入口返回值。`true`：A2-A6、B2-B5（`=== true` 判定或经桥读取）；`false`：A1/B1（裸语句）、C1-C6（XFL 裸语句）、D/E 组（debounce 无返回消费）。Slice 4 迁移 A1 时注意：AS2 当前忽略 Boolean，Host 必须依赖本轮 `sv` 门控（裁决 §5.6）。

## 基线字段（baseline）

- `headCommit`：manifest 行号的代码基线。行号漂移（如合入新提交）后，更新受影响记录的 `line` 并在该字段写明新基线；callsites.md 封包基线（`776db2ae26`）与本基线的已知漂移已记录在 `lineNumberNote`。
- `swf`：Slice 0 封板时的发布 SWF SHA-256 快照：`scripts/asLoader.swf`（含函数数 10,924 / 最大函数体 54,560 B，由 `node tools/swf-function-sizes.js scripts/asLoader.swf --max 60000 --top 5` 取得）、主 SWF `CRAZYFLASHER7MercenaryEmpire.swf`、9 个相关 `flashswf/UI/*.swf`。
- 主 XFL 帧脚本基线**引用** `tmp/adjudication-savemanager-api-20260904/03-XFL帧脚本证据/xfl-callsite-extracts.md`（24 段 CDATA 逐字提取，来源为工作树 XML）；FFDec 对发布 SWF 的再提取基线属 Slice 8/9 发布门（裁决 §5.5 第 3 层），本包不含 SWF 反编译产物。

## 漂移处理流程

1. **行号漂移**（其他提交合入导致 `line` 失效）：scanner 报"无有效代码 / 不含 legacyApi / 未命中"→ 重新定位行号，更新对应记录 `line` 与 `baseline.headCommit`，并在最终提交信息中注明漂移原因。数量不变。
2. **新增 / 删除调用点**（scanner 报"扫描命中不在 manifest"或数量断言失败）：不得直接改 manifest 压平警报——先确认该改动已经过裁决分类（§3.1 语义归属），再更新 manifest、counts 与本 README，并在提交信息中写明分类依据。
3. **SWF 重发布**：用 `--verify-swf-hashes` 检出 hash 漂移后，将新 hash 写入 `baseline.swf`（asLoader 同时刷新 `functions` / `maxFunctionBytes`）。
4. **迁移施工**（Slice 2+ 改旧入口文本）：该切片提交必须同轮把受影响记录的 `legacyEntry` / `legacyApi` 改记为新 API 文本与 family（或移入已迁移区段），否则 scanner 会以"未命中 / 数量不足"拒绝——这正是本门的存在意义。
