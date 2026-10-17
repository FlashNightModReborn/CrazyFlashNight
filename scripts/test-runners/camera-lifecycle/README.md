# 相机生命周期修复与回归

P0 修复共享场景的低显示槽与 authored 定位器交换：卸载前归还原槽，同帧换层复用定位器，真正跳帧前退役精确的 idle 定位器。loot 未收敛时保持世界、镜头与显示槽；结构错误在销毁前拒绝，不作为 loot 自动重试。

P1 使用独立世界身份和镜头 scope，区分玩家跟随与显式虚拟镜头；旧 Ready、旧 focus handle 和旧释放不能干扰新场景。有限焦点在取目标与缩放前清理，保留零容差，snap 只消费一次。

P2 首次构图、全屏重构图使用相同公式；当前设置可刷新，整数呈现保留逻辑小数进度。揭幕要求当前世界身份与镜头 scope 已提交首帧。独立帧计时器只观察 driver，不代为更新镜头；诊断使用现有 focus 通道和独立限额。

## 快速检查

```powershell
node tools/test-camera-lifecycle-source.js
node tools/test-scene-transition-stage-entry.js
```

这两项是源码控制流夹具，不证明原生 MovieClip、画面、真实游戏入口或存档。

## 原生回归

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-camera-lifecycle-tests.ps1 -Suite camera
# 独立 worktree 使用已经配置 CS6 的主仓库编译服务，传绝对目录：
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-camera-lifecycle-tests.ps1 -Suite camera -CompilerProjectDirectory '<已配置编译环境的 resources 目录>'
```

入口只替换本工作树 `camera_run.as`，使用标准 `compile_test.ps1` 编译绝对 XFL，不改共享 TestLoader、编译配置或计划任务。每轮生成唯一 runId，要求新鲜 Compiler 0/0、目标 SWF、函数体上限与单 Start/Complete 原始 trace；证据保存在 `tmp/camera-lifecycle/<suite>/<runId>/`。行为不闭合仍保留不确定状态；按既有 CS6 恢复合同处理，不盲清 marker。

其他 suite：`scene-transition`、`stage-return`、`arena-worker-protocol`、`map-loot`、`lee-trial`、`warlord-action-encounter`、`bookshelf`。它们复用现有套件模板、内存夹具和专用回归 SOL，不使用真实玩家槽；书架与斗兽回归通过实际相机提交满足揭幕围栏。

CameraLifecycleHost 使用真实 authored enterFrame、原生 attach/swap/remove、十次同帧重载及前进/倒回。主工程定位器在 146、158、193、210 帧，之间有空帧；原生夹具 1→13 的空帧拓扑对应实际 146→158。相邻同元件关键帧可编译成 MoveObject，不能当作新建定位器的替代夹具。

像素检查同时覆盖正常上下半部与旧路径下半部遮挡；旧路径保留原生 `swapDepths(undefined)` 读回。它还实测同名 MovieClip 的旧引用重指，验证独立身份、焦点语义、缩放/取目标顺序、虚拟镜头优先级和首帧围栏。结果仍属原生夹具，不升级为游戏 E2E。

## 人工验收范围

验收候选须配套真实 CS6 编译的 asLoader。一次窗口检查：基地一层与屋顶反复换层并移动、打开修改器检查整面板与点击；切换全屏/窗口及缩放设置观察首帧与跟随；进入并返回一场既有战斗检查虚拟镜头与揭幕。通过后再按用户授权进入发布列车。
