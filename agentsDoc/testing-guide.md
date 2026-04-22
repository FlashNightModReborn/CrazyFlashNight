# 测试约定与验证矩阵

**文档角色**：验证矩阵 canonical doc。  
**最后核对代码基线**：commit `9f8f0c225`（2026-04-20）。

按子栈选验证；不要用「编译一下」「跑一下 build」笼统覆盖跨栈任务。

## 0. 通用前缀

PowerShell 命令前先跑（避免 GBK 乱码）：

```powershell
chcp.com 65001 | Out-Null
```

下方所有 PowerShell 命令默认已执行该前缀,不再每条重复。

## 1. 任务 → 验证入口矩阵

| 任务类型 | 必跑 | 视改动追加 |
|----------|------|------------|
| AS2 class / 帧脚本 / Flash 资源联动 | `scripts/compile_test.ps1` 或 `bash scripts/compile_test.sh` | Flash IDE 复核、截图、专项 TestLoader 套件 |
| XML / 数据 / 游戏数值 | 受影响路径运行时 smoke | `compile_test`、游戏内人工验证 |
| 导弹运动 / 追踪参数离线调优 | `python tools/missile-tuning-sim/run_sim.py compare --configs ...` | `scan --objective loiter|pressure|hit` / `audit`、`compile_test`、游戏内人工验证 |
| Launcher C# / Host / Bus | `launcher/build.ps1` | `launcher/tests/run_tests.ps1`、`tools/cfn-cli`、`--bus-only` |
| Launcher Web / Minigame | `node launcher/tools/run-minigame-qa.js --game ...` | browser harness、`node launcher/tools/validate-minigame-final-state.js` |
| Launcher Web / Map Panel | `powershell -ExecutionPolicy Bypass -File launcher/build.ps1` + `node tools/audit-map-taskmarkers.js`（契约守门，必须 0 error / 0 warn） | browser harness `map-ui1`~`map-ui20` 全绿（`launcher/web/modules/map/dev/harness.html` → 面板"Run suite"）、`node tools/audit-map-layout.js` |
| 文档与治理 | `node tools/validate-doc-governance.js` | 交叉 grep / 链接检查 / 基线复核 |

## 2. AS2 / Flash 验证

**入口**：`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1` 或 `bash scripts/compile_test.sh`

**成功判据**（缺一不可视为成功）：

- 本次运行**新鲜生成**的 `scripts/flashlog.txt`
- 必要时核对 `scripts/compile_output.txt`
- `scripts/compiler_errors.txt` 为空或无新错误
- `publish_done.marker` **仅说明 JSFL 触发结束**,不能单独视为成功

**对外表述边界**：

- 可以说：`已完成 Flash CS6 自动化 smoke 验证` / `已触发编译并拿到新鲜 trace`
- **不要**在缺少新鲜 trace、编译器错误面板或 IDE 复核时说「已编译通过」

详见 [scripts/FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md)。

## 3. Launcher Host 验证

| 用途 | 命令 |
|------|------|
| 构建 | `powershell -File launcher/build.ps1` |
| xUnit | `powershell -File launcher/tests/run_tests.ps1` |
| 总线健康 | `bash tools/cfn-cli.sh status` |
| AS2 回环 | `bash tools/cfn-cli.sh console "help"` |
| 集成 (testMovie) | `CRAZYFLASHER7MercenaryEmpire.exe --bus-only` |

`--bus-only` 适用：Flash CS6 testMovie ↔ Launcher 通信链验证;AI / 模拟实验需外部 Flash 自连总线;排查启动链路 vs 总线本身。

## 4. Launcher Web / Minigame 验证

| 用途 | 命令 |
|------|------|
| Node QA(单局) | `node launcher/tools/run-minigame-qa.js --game lockbox` |
| Node QA(单局) | `node launcher/tools/run-minigame-qa.js --game pinalign` |
| Node QA(全套) | `node launcher/tools/run-minigame-qa.js --game all` |
| 静态校验 | `node launcher/tools/validate-minigame-final-state.js` |

**Browser harness**(直接打开)：`launcher/web/modules/minigames/lockbox/dev/harness.html` / `launcher/web/modules/minigames/pinalign/dev/harness.html` / `launcher/web/modules/map/dev/harness.html`。

**默认顺序**：纯逻辑 / 确定性问题先跑 Node QA；协议 / DOM / 布局 / 交互问题进 browser harness；目录 / 协议 / 旧入口回流问题再补静态校验。

`map` harness 固定覆盖：顶部分页与关闭按钮的 hit-test 可达性、右侧层级按钮遮挡、学校页 `室友头像` 动态切换、`1366x768` 紧凑视口滚动可达性、locked group 的锁定提示与锁定原因可达性、`base` assembled 热点框与 scene visual 联合包围框对齐（`map-ui11`）、静态头像运行时 rect 与 source metadata 对齐（`map-ui10`）、taskNpc 环锚点跟随动态头像中心（`map-ui12`）、连点热点去重 + busy 物理 disabled（`map-ui13`）、hotspot / 分页 / filter / close 的 `data-audio-cue` 语义路由 **且单次触发**（`map-ui14`，依赖 overlay 载入 `modules/audio.js` + `modules/overlay-audio-bindings.js`；harness 用 `BootstrapAudio` 计数器存根替身）、右侧 rail 脱离 stage frame + body 不溢出（`map-ui15`）、locked filter 点击不切状态且弹锁定原因 toast（`map-ui16`）、faction filter 切换驱动 `data-active-filter` 属性 + `is-retuning` 过渡 class（`map-ui17`）、defense restricted filter 触发 `.map-stage-anomaly.is-active` 且脉冲偏心到右上（`map-ui18`）、rail 手风琴仅展开 active 非 meta filter 子场景列表 + 点子项复用 `requestNavigate`（`map-ui19` / `map-ui20`）。

改 `map-panel.js` / `map-panel-data.js` / `panels.js` / `地图系统_WebView.as` 的 PR **必须**在合并前跑通以下 gate（缺一不得合并）：
1. `node tools/audit-map-taskmarkers.js` 输出 `0 warn, 0 error`
2. 在 `launcher/web/modules/map/dev/harness.html` 面板点 "Run suite" 全绿（`map-ui1`~`map-ui20`）
3. `node tools/audit-map-layout.js` 无几何漂移

地图 manifest 校准入口：`launcher/web/modules/map/dev/preview.html`；可视化构建入口：`launcher/web/modules/map/dev/builder.html`；fallback 期全量复核入口：`node tools/audit-map-layout.js [--page school] [--json]`。`preview` 负责看运行时同构的 assembled stage（`sceneVisuals` 拼接层 + backdrop）、布局、过滤、`buttonRect`、动态头像槽位、locked groups 条件、flash hint、XFL source rect、draft 校准与 override 导出；`builder` 在此基础上开启热点 / 过滤按钮拖拽缩放、bundle 粘贴导入和草稿持久化；两者都不替代 browser harness 的交互 gate。需要给人眼或外部视觉模型看图时，用 `python tools/render-map-audit-sheet.py --page base --page faction --page defense --page school` 生成热点/头像审计图，再按需调用 `powershell -ExecutionPolicy Bypass -File tools/kimi-map-review.ps1 ...` 做视觉复核。

URL 参数:`?qa=1` 自动断言 / `?case=` 单条 / `?scenario=` 脚本场景 / `?dump=1` 结构化输出。

若改动后的行为无法被现有 harness 或 QA 覆盖，同轮补测试入口，不把“靠人工记得点开”当作默认收尾。

静态校验拦截:旧平铺 Lockbox 入口、旧 `lockbox_session` / `pinalign_session`、旧共享结构 class 名。

## 5. 自动化与文档治理

| 用途 | 入口 |
|------|------|
| 启动 / 运行链 | [automation/README.md](../automation/README.md) |
| Flash 编译 smoke 细节 | [scripts/FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md) |
| 离线导弹调优 | `python tools/missile-tuning-sim/run_sim.py compare --configs ...` / `python tools/missile-tuning-sim/run_sim.py scan --objective loiter ...` |
| 文档治理巡检 | `node tools/validate-doc-governance.js` |

巡检脚本检查:必读文件存在、AGENTS.md 关键链接存在、回流模式未重新进入入口、关键文档基线标记存在、关键版本未回退。脚本是巡检器,不是 source of truth。

## 6. 收尾话术参考

- 文档改动:`已更新文档并运行文档治理巡检`
- Minigame:`已跑 Node QA / 静态校验;browser harness 未人工点开`
- Map Panel:`已跑 launcher/build.ps1 / browser harness;未做完整游戏内联调`
- Launcher:`已跑 build / xUnit;未做完整运行态手点`
- Flash:`已完成 Flash smoke;未在缺少新鲜 trace 或 IDE 复核时声称编译通过`

完整失败模式与重入约束看 [agent-harness.md](agent-harness.md)。
