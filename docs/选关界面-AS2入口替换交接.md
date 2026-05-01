# 选关界面 AS2 入口替换交接

**文档角色**：Stage Select Web Panel 从刘海屏测试入口推进到正式替换 Flash `关卡地图` 入口的施工交接。  
**当前状态**：Stage 2 Step 2 工程实现已落地；本文保留为正式入口替换的落地记录与后续验收清单。
**边界提醒**：本文只规划正式入口替换，不扩大到委托任务界面迁移，也不做 Stage 3 现代化视觉改造。

## 0. 本轮落地摘要

- AS2 已新增 `openWebStageSelect`、`stageSelectJumpFrame`、`stageSelectPanelClose` 命令；正式打开 payload 为 `panel_request` + `panel:"stage-select"` + `mode:"runtime"` + `frameLabel`
- C# `TaskRegistry` / `LauncherCommandRouter` / `WebOverlayForm` 已支持 `stage-select` panel request、`frameLabel` / `mode` 初始化、`jump_frame` 转发与 close 回调
- Web runtime 已隐藏 fixture/dev 控件；`localFrame` 先切 Web 页面再同步 AS2 frame，`return` / `return-garage` 只关闭 panel
- 场景门替换已覆盖 `基地门口`、`车库`、`地下 2 层`、`停机坪`、`地图-联合大学` 左右出口；旧 `切换场景("", "关卡地图", ...)` 保留为发送失败 fallback
- 战斗结束回流、角斗场返回、外交 / 委托任务 UI 不纳入本阶段

## 1. 已完成基线

当前 `stage-select` 已具备正式替换所需的前端壳和 live bridge：

- Web panel：`launcher/web/modules/stage-select-panel.js`
- Web manifest：`launcher/web/modules/stage-select-data.js`
- C# bridge：`launcher/src/Tasks/StageSelectTask.cs`
- AS2 service：`scripts/类定义/org/flashNight/arki/stageSelect/StageSelectPanelService.as`
- AS2 include：`scripts/逻辑系统分区/选关系统_WebView.as`
- XFL source：`flashswf/UI/选关界面/LIBRARY/选关界面UI/选关界面 1024&#042576.xml`

已验证能力：

- 刘海屏“其他 → 选关测试”可打开 `stage-select`
- `stageSelectSnapshot` 读取真实解锁状态、挑战模式、`StageInfoDict` 简介/限制词条、`tasks_to_do` 任务提示和推荐难度
- `stageSelectEnter` 可从 Web 难度按钮进入已解锁关卡
- 锁定关卡不会发 enter
- Web hover 卡片已处理 Flash HTML 标签和长文本
- Browser harness / launcher tests / Flash smoke 已能覆盖当前路径

## 2. Step 2 目标

正式替换含义：

- 玩家从基地门口、车库、地下 2 层、停机坪、联合大学等旧入口进入关卡地图时，默认打开 Web `stage-select`
- 不再把玩家带到 Flash 主时间轴 `关卡地图` 帧上显示 `关卡地图MC`
- Web 关闭时回到原场景，不触发进关、不留下 HUD / 鼠标 / PanelHost 半状态
- 进关仍走 `stageSelectEnter`，由 AS2 执行原 `选关界面进入关卡` 等价副作用
- 旧 Flash `关卡地图` 帧保留为回滚 fallback，不在本阶段删除

不做：

- 不迁移外交/委托任务界面
- 不接管所有非战斗副本任务 UI
- 不重做 2.5D / 天幕 / 场景现代化
- 不手动编辑 SWF

## 3. 入口现状盘点

旧入口大体有两类：场景门直接跳 `关卡地图`，以及旧 UI/战斗结算回到 `关卡地图`。

优先替换的场景门：

- `flashswf/levels/基地场景合集/LIBRARY/地图/基地门口.xml`：小门进入 `关卡地图`
- `flashswf/levels/基地场景合集/LIBRARY/地图/车库.xml`：车库入口进入 `关卡地图`
- `flashswf/levels/基地场景合集/LIBRARY/地图/溶洞.xml`：地下 2 层入口进入 `关卡地图`
- `flashswf/levels/基地场景合集/LIBRARY/地图/停机坪.xml`：基地房顶入口进入 `关卡地图`
- `flashswf/levels/地图-联合大学/LIBRARY/地图-联合大学.xml`：左右出口进入 `关卡地图`

需要单独判断的路径：

- `CRAZYFLASHER7MercenaryEmpire/LIBRARY/角斗场选择界面.xml`：返回按钮关闭决斗场后跳 `关卡地图`
- `scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as`：`_root.返回基地` 使用 `_root.关卡地图帧值` 回到基地/地图帧；这条不应直接替换成打开 panel，否则会破坏战斗结束回流
- `CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml`：主时间轴 `关卡地图` label 上挂载 `关卡地图MC`，这是旧 UI 最终承载点，保留作 fallback

## 4. 施工路径与当前实现

### 4.1 AS2 新增正式打开命令

在 `StageSelectPanelService.install()` 中新增命令：

```actionscript
_root.gameCommands["openWebStageSelect"] = function(params) {
    org.flashNight.arki.stageSelect.StageSelectPanelService.handleOpenWebStageSelect(params);
};
```

推荐 payload：

```json
{
  "task": "panel_request",
  "panel": "stage-select",
  "source": "as2_stage_map_door",
  "frameLabel": "_root.关卡地图帧值",
  "mode": "runtime"
}
```

AS2 侧要求：

- `frameLabel` 默认取 `String(_root.关卡地图帧值 || "基地门口")`
- `source` 由调用点传入，便于日志定位
- 如果 `_root.server` 或 `sendSocketMessage` 不可用，返回失败并允许调用点走旧 `切换场景("", "关卡地图", ...)`
- 字符串拼 JSON 时只拼固定字段和已清洗值；复杂扩展留给 C# / Web runtime snapshot

### 4.2 C# 支持 stage-select panel_request

`TaskRegistry` 的 `panel_request` 已从 `panel/source/pageId` 扩展到 `frameLabel/mode`。`LauncherCommandRouter.RequestOpenPanel` 当前显式支持 `map` 与 `stage-select`，其他 panel 仍记录 unsupported，不扩大任意 JSON 透传面。

当前实现：

- `TaskRegistry` 解析 `frameLabel`、`mode`
- `WebOverlayForm.RequestOpenPanel` 增加对应参数重载
- `LauncherCommandRouter.RequestOpenPanel` 支持 `panelName == "stage-select"`
- `OpenStageSelectPanel(source, frameLabel, mode)` 生成：

```json
{
  "mode": "runtime",
  "fixture": "mixed",
  "frameLabel": "基地门口",
  "debug": false,
  "source": "as2_stage_map_door"
}
```

注意：

- `fixture` 只作为 Bridge 失败 fallback；runtime 下 live snapshot 覆盖解锁/挑战/详情
- `frameLabel` 允许中文原名，不另起英文 ID
- 未知 `frameLabel` 由 Web fallback 到 manifest 首帧，但 C# 日志应记录 source 和 frameLabel

### 4.3 Web 正式模式行为

Web 已支持 runtime snapshot / enter，本轮补齐：

- `mode === "runtime"` 下隐藏 fixture 控件和 dev log，保留错误提示
- nav `return` / `return-garage` 在 runtime 下执行关闭 panel，而不是只 log
- `localFrame` 先做 Web 内页切换，再发送 `jump_frame`，由 C# / AS2 同步 `_root.关卡地图帧值`
- 非本阶段支持的外交/委托按钮保持不触发任务 UI；建议显示明确提示或保持静态
- close/backdrop/ESC 都只关闭 Web panel，不发送进关命令

如果采用“先拦截场景门，不进入 Flash `关卡地图` 帧”的策略，关闭 panel 后玩家自然停留原场景，Web 不需要再让 AS2 淡出返回。

### 4.4 替换 AS2 调用点

本轮实际替换顺序：

1. 新增 `openWebStageSelect` 与 `stageSelectJumpFrame` / `stageSelectPanelClose`
2. C# 支持 `panel_request stage-select`
3. 抽出 `_root.场景转换函数.打开Web选关` helper，统一复用门入口判定与 fallback
4. 替换 `基地门口.xml`
5. 扩展到 `车库.xml`、`溶洞.xml`、`停机坪.xml`
6. 扩展到 `地图-联合大学.xml` 左右出口
7. `角斗场选择界面.xml` 不纳入 Stage 2

每个调用点建议保留 fallback：

```actionscript
if (打开Web选关 != undefined) {
    打开Web选关("", "关卡地图", "", _root.左键, "as2_base_gate");
} else {
    切换场景("", "关卡地图", "", _root.左键);
}
```

实际门脚本里 `切换场景` 往往依赖方向键/门动画参数，替换时不要机械复制上面的参数；逐文件保持原方向键、门动画、出生点语义。

## 5. 风险与验收

主要风险：

- C# `panel_request` 只允许显式 panel；`stage-select` 已接入，未知 panel 仍应保持 unsupported
- 场景门脚本处于 `onClipEvent(enterFrame)`，错误调用可能导致重复打开 panel
- Web 关闭语义和旧 Flash 返回按钮不同，必须确认玩家仍在原场景且输入恢复
- 挑战模式只允许地狱难度，替换正式入口后仍要覆盖
- 外交/委托按钮仍留 Flash，不能误当普通关卡进入
- Flash compile smoke 只在有新鲜 trace / Output Panel 证据时才能宣称通过

最低验收：

```powershell
node tools/run-stage-select-harness.js --browser edge
node tools/export-stage-select-manifest.js --summary
node tools/audit-stage-select-layout.js --json
powershell -ExecutionPolicy Bypass -File launcher/build.ps1
powershell -ExecutionPolicy Bypass -File launcher/tests/run_tests.ps1
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1
node tools/validate-doc-governance.js
```

手测路径：

- 基地门口 → 选关 Web panel → 关闭 → 仍在基地门口，HUD/鼠标正常
- 基地门口 → 选关 Web panel → 新手练习场 / 简单 → 成功进关
- 车库 / 地下 2 层 / 停机坪 / 联合大学左右出口分别打开对应 `frameLabel`
- Web 页内跳转后关闭 / 重开，当前 frame 同步符合预期
- 锁定关卡不可进
- 挑战模式只显示/允许地狱
- 长文本 hover 不露 `<BR>` / `<FONT>`，锁定 hover 不丢红圈/文字

## 6. 回滚策略

- 不删除 `关卡地图MC`
- 不删除旧 `切换场景("", "关卡地图", ...)` fallback
- 若 WebView / C# / XMLSocket 不可用，AS2 调用点应回到旧 Flash 选关界面
- 若正式入口替换出现问题，可只撤回场景门调用点，保留 Stage 2 Step 1 测试入口继续调试

## 7. 给后续施工者的提示词

```text
Stage Select Stage 2 Step 2 已完成工程落地。
后续优先做 Flash CS6 smoke 与人工验收，不要把战斗结束回流或角斗场返回误改成 Web panel。
继续保留旧 Flash 关卡地图 fallback；不要迁移委托任务界面，不删除关卡地图MC。
改动协议或测试入口后继续跑 Edge harness、launcher build/tests、Flash compile smoke、doc governance。
```
