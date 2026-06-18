# AS2 UI 到 Web Panel 迁移护栏

**文档角色**：AS2 UI 迁移到 Launcher Web Panel 的专题 canonical doc。
**最后核对代码基线**：commit `b852c0eba1`（2026-06-17）。

本文用于所有“旧 Flash / AS2 UI 迁移到 Launcher WebView2 panel”的任务。它不是普通前端开发指南，而是跨 AS2、C# 总线、Web panel、Flash CS6 编译链的稳定性护栏。凡迁移旧 UI、替换运行态入口、扩展 panel 协议、把 dev harness 推向生产，都必须先读本文。

## 1. 迁移分级

| 分级 | 判断标准 | 不允许声称 |
|------|----------|------------|
| 静态原型 | 只有 `launcher/web/modules/*/dev/` harness、mock 数据、美术资源 | 不得说“已接入运行态” |
| Web panel 原型 | 有正式 JS module 与 `Panels.register`，但未接 AS2 / C# 写操作 | 不得说“功能完成” |
| 协议接入 | Web cmd、C# Task、AS2 handler、response task 全链存在 | 不得跳过验证直接合并 |
| 生产可用 | 完成构建、xUnit / harness、Flash fresh trace 或人工复核、游戏内端到端手测 | 才能说“迁移完成” |

`modules/*/dev` 默认只是原型。进入生产前必须有正式模块、panel 注册、协议接入、验证入口和文档同步。

## 2. 迁移闭环表

每个功能命令必须维护一张闭环表。没有闭环表，不允许说协议完成。

| Web cmd | C# action | AS2 handler | AS2 response task | C# panel_resp | JS handler | 写状态 |
|---------|-----------|-------------|-------------------|---------------|------------|--------|
| `snapshot` | `xxxSnapshot` | `handleSnapshot` | `xxx_response` | `panel_resp panel=xxx cmd=snapshot` | `Bridge.on('panel_resp')` | 读 |
| `save` | `xxxSave` | `handleSave` | `xxx_response` | `panel_resp panel=xxx cmd=save` | 对应 callback | 写 |

检查点：

- Web `cmd` 必须进入 `WebOverlayForm.HandlePanelMessage` 的 case 列表。
- C# Task 的 action 字符串必须与 AS2 `gameCommand` 分发一致。
- AS2 `task` 回包名必须与 `TaskRegistry` 注册名一致。
- C# 回包必须恢复 Web 原始 `callId`，不能把 Flash 内部 `fid` 泄漏给 JS。
- JS callback 必须在成功、失败、关闭时清理 pending / busy 状态。

战宠与佣兵迁移暴露过两类典型断链：Web cmd 没进 `HandlePanelMessage` 导致静默丢弃；AS2 委托其他 service 后回包 task 名不匹配导致 tooltip / 写操作永远收不到响应。新增 panel 时优先防这两类问题。

## 3. C# 接入清单

新增生产 panel 的 C# 最小接入面：

- `launcher/src/Tasks/*Task.cs`：实现双层 `callId` 桥接、timeout、`ClearPending()`、`Dispose()`。
- `launcher/src/Program.cs`：创建 Task，注入 `WebOverlayForm`，传入 `TaskRegistry.RegisterAll`。
- `launcher/src/Bus/TaskRegistry.cs`：注册 AS2 response task，例如 `xxx_response`。
- `launcher/src/Guardian/WebOverlayForm.cs`：
  - Task 字段（如 `_petTask`）与 `SetXTask()` 注入方法。
  - `HandlePanelMessage` 覆盖所有 Web cmd。
  - `OnSocketDisconnected()` 里补一行 `if (_xTask != null) _xTask.ClearPending();`，与既有各 Task 的清理逐项对齐（断线时清 pending，防止旧回包错配新会话）。
  - `ResolvePanelCloseGameCommand()` 明确 close 是否通知 Flash。
- `launcher/CRAZYFLASHER7MercenaryEmpire.csproj`：当前 SDK-style 会自动包含 `.cs`，但迁移时仍要确认构建清单没有旧式残留假设。
- `launcher/tests/Tasks/*TaskTests.cs`：至少覆盖断连错误、cmd→action、Flash 回包重写、unsupported cmd。

禁止只新增 JS 和 AS2 service 而漏 C# 分发层。C# build 通过也不代表协议能到达 AS2，必须有 Task 级测试或游戏内验证。

## 4. AS2 接入清单

AS2 侧修改必须遵守：

- 新增 / 重建 `.as` 必须 UTF-8 with BOM；优先复制现有 `.as` 改名保留 BOM。
- 新增 boot 期 `.as` 入口：asLoader.xml 已塌成单帧 `#include _collapsed_frame.as`（见 [docs/asLoader-README.md](../docs/asLoader-README.md)）→ 不再直接改时间轴；同步入口加进对应 staged 帧 manifest 后 `node tools/assemble-collapsed-frame.js` regen，异步入口归 BootSequencer；被引用的 class 自动嵌入无需手动 include。
- response task 名必须唯一，并与 C# `TaskRegistry` 一致。
- 修改 AS2 后必须说明 `scripts/asLoader.swf` 是否已重编。
- 没有 fresh trace、Output Panel 副本或 IDE 复核时，不能说“Flash 编译通过”。
- 写存档、金钱、K点、背包、伙伴、宠物、任务状态后，必须对齐当前 save dirty / autosave 机制，不能只改内存对象。

AS2 smoke 的成功边界按 [testing-guide.md](testing-guide.md) 与 [FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md)。`publish_done.marker` 只能证明 JSFL 触发结束，不能单独作为成功依据。

## 5. Web Panel 接入清单

生产 Web panel 至少满足：

- 正式模块位于 `launcher/web/modules/`，不是只在 `dev/`。
- `Panels.register(id, ...)` 或懒注册表 `panels-lazy-registry.js` 已接入。
- `onOpen` 初始化 session、pending、busy、runtime snapshot。
- `onClose` 清理 pending、busy、timer、tooltip、hover、DOM 订阅。
- close 按钮、ESC、backdrop click 必须最终触发同一套本地 close 清理，再通知 C#。
- 任何 async callback 返回时要校验 session，避免旧面板回包污染新会话。
- 用户可输入文本进入 `innerHTML` 前必须 escape；优先用 `textContent`。
- runtime 文本必须考虑 1024×576、1366×768、1920×1080 视口，按钮文本不能溢出。

使用资源时，必须有 fallback：图标、头像、背景 missing 时不能让 panel 空白或 JS 抛异常。共享图标体系要主动加载 manifest，例如佣兵装备图标需要先 `Icons.load()`；普通物品图标若只需要 URL 用 `Icons.resolve()` 首帧静态显示，列表/格子里的可动画图标用 `Icons.html()` / `applyIconToImage()` 交给共享模块播放，只有 manifest 显式声明 `playback` / `animated` 的图标才会按时间线切帧。

迁移 Flash MovieClip 素材时，manifest 不能只记录“静图 / 多帧图”二分。必须保留时间线语义：父 sprite 首帧纯 `stop();` 时父级停在第一帧；若第一帧内有自播放子 MovieClip，子层仍应独立播放，不能把整件素材误折叠为普通静图，也不能按子层周期最小公倍数预合成全量大序列。图标素材先用 `tools/bake-icons-offline.py --animation-structure-audit-only --ffdec-timeout-seconds 120` 审 `animationStructureCandidates` / `animationStructureParentStopNested` / `animationStructureUnsupported` / `spriteGraphErrors[].error=swf_xml_timeout`；`--ffdec-timeout-seconds` 作用于每个 FFDec 子进程，PNG/SVG/XML2SWF 超时按对应 export error 的 `exitCode=124` 审。生产推广用 `--animation-candidates-only --animation-candidate-report tmp/icon-animation-structure-audit.json` 复用结构审计候选，并可配 `--animated-candidate-max-source-frames` 在 PNG 导出前跳过超长周期候选；每轮仍应按 `--name` 分批审首帧 oracle 与体积，批量推进走 `tools/promote-icon-animation-candidates.py` 汇总 `animated|visual-static|budget-static|unsupported-static|timeout`。父级纯 `stop();` 的图标应写 `playback=static-first-frame` 并移除 `f2` 运行时引用，不能让 FFDec 导出的后续变形帧变成循环动画。图标素材若父首帧、stripped base 全透明且只有一个自播放子 MovieClip，可写成 `playback=nested-animation` 的全画布 `frames[]/timelineFrames[]`，第 1 帧复用原父级首帧以守住既有偏移；若父第 1 帧直接挂一个或多个可动子层且层深度不与静态 base 交错，写 `nestedAnimation.strategy=direct-layered-icon-canvas`，运行时用 `Icons.html()` 生成 base+layers wrapper 并按层独立播放。direct-layered 图标导出时应烘焙 PlaceObject 上可支持的滤镜，并用父首帧 oracle 做小范围自动 `offset` 校准；layer frame 可按透明包围盒裁剪，使用 `cropX/cropY/cropWidth/cropHeight/canvasWidth/canvasHeight` 在 Web 侧放回原 256 画布位置；`filters` / `offset` / crop 字段都是导出审计与还原元数据，不是手工 offset 表，也不要求 Web 运行时实现 Flash 滤镜。复杂嵌套只进 `nestedIconCanvasUnsupported` / `nestedIconLayeredUnsupported`。图标动图进生产目录前可用 `--max-animated-icon-bytes` 设置单图标体积门槛；超预算条目必须记录 `animatedIconBudgetSkipped` 并回退静态首帧；多帧候选若视觉上只有同一 `uri + crop`，必须记录 `animatedVisualStaticDowngraded` 并回退静态首帧，避免无意义运行时 tick。纸娃娃素材以 `nestedAnimation.autoPlayingDescendants`、`playback=static-parent-nested-animation|nested-animation`、重复帧 `duplicateOfFrame` 作为当前契约；能直接分层的 child MovieClip 进一步写 `nestedAnimation.layers[]`，包含 stripped base 之外的子层帧、矩阵与 `drawOrder`。连续重复显示帧应保留为播放时长而不是重复实体帧：`frames[]` 可作为完整逻辑帧/审计明细，运行时优先读取 `timelineFrames[]` 与 `durationFrames`。图标与纸娃娃运行时都必须通过 `web/modules/asset-timeline.js` 解释这些字段；`icons.js` / `dressup-doll-renderer.js` 只保留各自的 DOM、URL、Canvas、matrix/origin 逻辑，不能再分叉实现播放时间线。导出端的 digest 去重、`duplicateOfFrame` 与连续 hold 压缩同样必须走 `tools/asset_timeline_export.py`；图标可按 `uri` 合并，layered 图标判断是否动起来必须把 `cropX/cropY/cropWidth/cropHeight/canvasWidth/canvasHeight` 纳入 identity，纸娃娃必须把尺寸和注册点纳入 identity key。`python tools/test-nested-animation-stop-semantics.py` 是父级首帧 `stop();` 只冻结父时间线、第一帧内未停止子 MovieClip 仍播放的固定回归。

## 6. Close 与旧 Flash UI 副作用

默认规则：Web panel close 不应触发旧 Flash UI 重排。尤其不要在 close、hire success、save success 这类回调里调用旧 UI 的：

- `gotoAndStop`
- `attachMovie`
- `排列*图标`
- 大量 MovieClip rebuild
- 旧 SWF 面板 refresh 函数

这类调用可能干扰 PanelHost 的 backdrop 移除、HUD resume、InputShield 清理和焦点恢复。确实需要 Flash cleanup 时，必须写清：

- 为什么纯 Web cleanup 不够。
- 发送哪个 `*PanelClose` gameCommand。
- AS2 handler 是否 no-op 或只清理状态。
- 验证项：关闭后再次打开、鼠标可点击、键盘焦点恢复、Flash 前台恢复。

经验规则：像 `kshop` 这类会暂停 / 恢复 Flash 状态的面板可以有 open/close gameCommand；像 `arena`、`team` 这类纯 Web 展示 / 操作面板，close 默认不通知 Flash。`team` 内宠物子视图尤其不能在 close 时调用 `petPanelClose`，该旧命令会重建 Flash 战宠图标。

## 7. 数据权威与转录

禁止裸手工转录以下数据：

- 金币、K点、倍率、消耗公式。
- 存档字段路径。
- XML / AS2 表里的宠物、佣兵、任务、关卡、物品定义。
- unlock 条件、主线进度门槛、等级门槛。

如果必须迁移到 JS / JSON，必须同轮给出：

1. 源文件路径与字段名。
2. 生成脚本、审计脚本或逐项对照记录。
3. 差异处理规则：哪些是故意改写，哪些必须与源一致。
4. 运行时 fallback：源数据缺失时显示什么，是否禁用写操作。

静态 JS 数据只能作为展示缓存或分类辅助；写操作必须由 AS2 权威路径重新校验价格、权限、槽位和状态。Web 端禁用按钮只是 UX，不是安全校验。

## 8. 验证门槛

迁移任务最小验证按改动面叠加：

| 改动面 | 必跑 |
|--------|------|
| C# Task / router / PanelHost | `launcher/build.ps1` + `launcher/tests/run_tests.ps1` |
| Web module / CSS / harness | 对应 browser harness 或静态 QA；没有入口时先补入口 |
| AS2 service / include / gameCommand | `scripts/compile_test.ps1` fresh trace，或说明 IDE 人工复核状态 |
| 写存档 / 金钱 / K点 / 背包 / 伙伴 / 宠物 | 游戏内端到端手测 + 回读存档状态 |
| 文档入口、协议、验证入口变化 | `node tools/validate-doc-governance.js` |

结束汇报必须区分：

- 已跑 C# build。
- 已跑 xUnit。
- 已跑 Web harness / Node QA。
- 已拿到 Flash fresh trace。
- 已做游戏内端到端手测。
- 未验证项与风险。

不要用“跑通了”“应该没问题”替代具体证据。

## 9. 文档同步

触发以下任一变化时，同轮更新文档：

- 新 panel id、目录、入口、懒注册依赖。
- Web cmd / C# action / AS2 response task 变化。
- close 语义变化。
- dev harness 升级为生产 panel，或生产 panel 降级 / 废弃。
- 新增验证入口或改变必跑命令。
- 数据 source of truth 改变。

更新位置：

- `launcher/README.md`：目录树、Panel System 摘要、运行态边界。
- `agentsDoc/testing-guide.md`：验证矩阵入口。
- 本文：迁移规则变化。
- 具体施工记录 / 设计文档：一次性过程、取舍、踩坑复盘。

入口文档只写摘要和链接，不复制本文清单。

## 10. Agent 收尾格式

迁移任务结束时，用固定格式报告：

```text
迁移级别：静态原型 / Web panel 原型 / 协议接入 / 生产可用
协议闭环：列出已覆盖 cmd，说明 Web→C#→AS2→C#→Web 是否完整
写状态：列出会改存档/金钱/K点/背包/伙伴/宠物/任务的路径
验证：build / xUnit / harness / Flash fresh trace / 游戏内手测
未验证：明确列出
文档：已更新的 canonical doc 与巡检结果
```

如果缺 Flash fresh trace 或游戏内手测，必须显式说“未做”，不能用 C# build 或 Web harness 替代。
