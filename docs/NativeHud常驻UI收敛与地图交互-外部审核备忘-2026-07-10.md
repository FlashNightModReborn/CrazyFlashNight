# NativeHud 常驻 UI 收敛与地图交互：外部审核备忘

**文档角色**：Launcher Native HUD 第二阶段的待审设计备忘 / ADR 草案，用于外部审核与跨会话恢复。本文记录当前实现事实、已形成的推荐方向、尚待裁决的问题、施工分期和验收门槛；**外审通过前不视为已生效设计，不替代 `launcher/README.md` 的当前实现真相**。

**最后核对代码基线**：commit `bb17305b65`（2026-07-09，代码树）；运行计数样本来自 `logs/perf-latest.jsonl`（2026-07-05），该样本之后 Native HUD 生产代码无变化。

**状态**：待外部审核，未开工。

---

## 0. 一页结论

本轮建议把右上角从“多栏常驻堆叠”收敛为：

1. **一行常驻操作**：`地图 / 装备 / 任务 | 系统设置 / 游戏暂停 / 安全退出`。
2. **一行条件状态**：仅在新任务、任务可交付或安全退出流程中出现；安全退出优先级最高。
3. **地图不再充当完整地图的前置步骤**：常驻地图按钮和小地图本体都应一击直达完整 Web 地图；小地图显示模式独立配置。
4. **刘海接管低频入口**：点歌机、修改器、帮助迁入刘海展开模式；BGM 波形以低透明度背景融入 FPS 线框。
5. **先修展开抖动，再重排 UI**：刘海动画期间固定宿主矩形，不再每帧重算 HWND bounds、重建 Bitmap 与完整提交 ULW。
6. **小地图按能力渐进上线**：当前以艺术预览和位置轮廓为主，可默认 `auto/关闭`；敌我位置与边界能力上线后，`compact` 才具备成为默认常驻态的理由。

目标草图：

```text
顶部中央：刘海
┌ FPS 折线 + 低透明度 BGM 包络 ┐
└ 展开：游戏功能区 / 点歌机·修改器·帮助 ┘

右上角常驻
┌ 地图 │ 装备 │ 任务 ┆ 设置 │ 暂停 │ 退出 ┐
└────── 条件任务提示 / 安全退出状态 ──────┘

地图预览（独立显示模式）
  compact / expanded 不推动上面两行；点击预览仍直接打开完整 Web 地图
```

---

## 1. 范围与非目标

### 1.1 本轮设计范围

- `NativeHudOverlay` 的几何更新与渲染提交策略
- `NotchWidget` 的展开布局、FPS/BGM 信息承载与入口分组
- `RightContextWidget` 的常驻入口、条件状态和点歌栏收敛
- `RightHudLayout` 的新几何模型
- `MapHudWidget` shared renderer 的显示模式与入口语义
- `SafeExitPanelWidget` 与任务提示的状态优先级
- 对应 xUnit、确定性 Native HUD harness、DPI 与真机截图验收

### 1.2 明确不在本轮实现

- 不实现敌我位置、视野、侦测或战场迷雾规则
- 不重做完整 Web 地图 Panel 的内容与导航协议
- 不改 Flash 主文件资产或 AS2 地图权威
- 不把本文与 `玩家信息界面 → C# NativeHud` 迁移 ADR 混为同一施工任务
- 不以“减少 HWND 数量”作为唯一性能目标；是否拆分 Native HUD surface 必须经 A/B 数据裁决

---

## 2. 当前实现事实

### 2.1 当前装配

`config.toml` 已默认 `useNativeHud=true`。`Program.cs` 注册：

- `RightContextWidget`
- `SafeExitPanelWidget`
- `ComboWidget`
- `ToastWidget`
- `NotchWidget`

所有 widget 由同一个 `NativeHudOverlay` 承载；运行态 Web HUD 对应区域被隐藏。

### 2.2 当前右侧布局

`RightHudLayout` 以 1024×576 设计坐标固定复刻旧 Web 常量：

| 区域 | 设计尺寸 |
|---|---:|
| 右侧 cluster 宽度 | 170px |
| 顶部工具栏 | 5 × 34px，高 32px |
| 小地图 | 高 86px |
| 地图/装备/任务行 | 高 32px |
| 条件通知行 | 高 32px |
| 点歌机标题栏 | 高 24px |

排除小地图后，右上角仍可能呈现四栏：顶部工具栏、地图/装备/任务行、条件通知行、点歌机标题栏。

小地图高度占设计视口约 14.9%；含地图的常态右侧 cluster 为 174px（约 30.2% 视口高），有通知时为 206px（约 35.8%）。全部尺寸按 Flash viewport 高度同比缩放，因此高分辨率下不会自然变得更紧凑。

### 2.3 当前路由语义

| 入口 | 当前命令 | 当前行为 |
|---|---|---|
| 系统设置 | `GAMESETTINGS` | `openSettings` |
| 修改器 | `SETTINGS` | `toggleSettings` |
| 游戏暂停 | `PAUSE` | `togglePause` |
| 帮助 | `HELP` | 打开 Web `help` Panel |
| 安全退出 | `SAFEEXIT` | Arm 原生确认状态后请求 AS2 存盘 |
| 地图行按钮 | `MAPHUD_TOGGLE` | 切换小地图折叠态 |
| 小地图卡片 | `TASK_MAP` | 打开完整 Web 地图 |
| 装备 | `EQUIP_UI` | 打开装备入口 |
| 任务 | `TASK_UI` | 打开 Web `tasks` Panel |
| 点歌机展开 | `JUKEBOX_EXPAND` | 打开 Web `jukebox` Panel |

必须保留的语义区别：

- 常驻 `PAUSE` 是**游戏暂停**。
- 当前点歌栏左侧 pause 是**仅暂停/恢复 BGM**。
- 二者不可合并为同一状态或同一命令。

### 2.4 已确认的展开抖动根因

`NotchWidget` 在 150ms 展开和 200ms 收起期间约每 16ms 改变一次 `ScreenBounds` 并发出 `BoundsOrVisibilityChanged`。`NativeHudOverlay` 收到后同步：

1. 计算全部可见 widget 的外接矩形 union；
2. 改变整个 Native HUD HWND 的位置和尺寸；
3. 尺寸变化时销毁并新建 composed Bitmap；
4. 重绘全部可见 widget；
5. 调 `UpdateLayeredWindow` 完整提交。

普通 repaint 有 33ms 合并门，但 bounds 路径直接进入 `RecomputeBounds()`，绕过 repaint coalescing。

当前单一 union 还会把居中刘海、右侧 cluster、左侧 Toast 之间的大块透明区域纳入同一位图；任何一个 widget 更新都会重绘其他静态 widget。窗口数量减少不等于合成像素面积或提交成本降低。

最近一份 65.27s 运行样本：

| 计数 | 数值 |
|---|---:|
| Native HUD commits | 566（约 8.67/s） |
| animation ticks | 1560 |
| repaint requests | 1066 |
| bounds changes | 43 |
| NotchWidget bounds changes | 21 |
| RightContextWidget ticks | 424 |
| RightContextWidget repaint requests | 104 |

这不是单纯调整 easing 或动画时长可以解决的问题。

### 2.5 当前验证覆盖

审阅时 `launcher/tests/run_tests.ps1` 为 658/658 通过。现有测试覆盖路由、协议解析、固定几何、地图数据安全和 widget 状态，但尚未硬约束：

- 单次展开/收起的 HWND 重定位次数
- composed Bitmap 重分配次数
- ULW commit 频率与耗时
- 多空间孤岛造成的透明 union 面积
- 展开过程的逐帧视觉稳定性
- 右侧 cluster 与最大展开刘海的碰撞

---

## 3. 推荐的信息架构

### 3.1 刘海：从单行扩宽改为受控的两组展开区

折叠态继续承载：

- 金币 / KP
- FPS 主数字与 FPS 折线
- 时钟及必要状态

建议把 BGM 左右声道峰值作为 FPS 线框内的**低透明度背景包络**：

- FPS 折线仍是前景主信息，不与音频使用同色同线型
- BGM 暂停时冻结并降透明度
- `disableVisualizers` 可关闭
- 音频刷新跟随刘海稳定刷新，默认不超过 4～10Hz，不因波形单独把 Native HUD 拉到 60Hz
- 峰值采样与播放状态下沉到共享 `AudioHudState`，避免 `RightContextWidget`、`NotchWidget`、Web Jukebox 多处各自维护权威

展开态迁入：

- 点歌机
- 修改器
- 帮助

刘海当前已包含战队、平板、战备箱、情报、商城等入口。加入三个入口后不应继续横向无限扩宽；推荐：

- 最大设计宽度约 420～440px
- 游戏功能与辅助功能分为两组或两行
- 具体宽度由右侧常驻栏的左边界动态给出安全上限
- 动画期间固定最大宿主 bounds，内容在内部做裁切/透明度/位移动画
- 完成展开或收起后才允许一次端点几何收敛

### 3.2 右侧：一行常驻入口

推荐顺序：

```text
地图 / 装备 / 任务 | 系统设置 / 游戏暂停 / 安全退出
```

约束：

- 不塞回现有 170px；推荐总宽 204～216px
- 单按钮视觉与命中宽度保持 34～36px
- 导航组与系统组之间有轻量分隔
- 地图、任务支持 badge / active 状态
- 暂停态使用明确的颜色与图标变化
- 安全退出保持最右、危险色 hover，但仍走存盘与二次确认
- 不再使用依赖 Emoji/font fallback 的临时字形作为最终图标；使用受控单色资源与 tooltip

### 3.3 条件第二行：统一状态槽

第二行仅在需要时出现，优先级固定为：

1. `SafeExit`：存盘中 / 取消 / 确认退出
2. 可交付任务
3. 新任务或普通任务通知
4. 无状态时隐藏

第一行位置永远不变。第二行状态变化不得推动或重排第一行。

`SafeExitPanelWidget` 是否合并进右侧状态槽是推荐项，但外审需确认：合并后可以消除当前独立浮层与任务提示/地图预览的空间竞争。

---

## 4. 地图职责与交互裁决

### 4.1 业界稳定分工

- **小地图**：扫一眼的态势感知，适合当前位置、地图边界、目标、友军、敌军等实时信息。
- **完整地图**：规划、导航、跳转、任务浏览与全局信息。
- 小地图不应成为打开完整地图前的强制中间层。

官方案例：

- Warframe：角落小地图持续显示目标、敌军和友军；`M` 直接打开全屏地图，长按地图键进入另一种可缩放地图模式。<https://support.warframe.com/hc/en-us/articles/38801911653517-Mission-Interface>
- Battlefield：小地图大小、背景透明度、旋转、观察距离及不同阵营/目标图标均可配置。<https://www.ea.com/able/resources/battlefield-6>
- Dragon Age: The Veilguard：允许单独隐藏小地图，同时保证世界/区域地图可用。<https://www.ea.com/games/dragon-age/dragon-age-the-veilguard/news/accessibility-spotlight>
- Xbox Accessibility Guideline 102：周边小地图元素需与背景保持足够对比，重要信息不能只靠颜色表达。<https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102>

### 4.2 推荐的 CF7 地图入口

主操作必须是：

- 常驻地图图标单击 → `TASK_MAP` → 直接打开完整 Web 地图
- 小地图本体单击 → `TASK_MAP` → 直接打开完整 Web 地图
- `M`（若接入）→ 直接打开完整 Web 地图

小地图显示模式独立于主操作：

- `off`：只保留地图图标
- `compact`：紧凑态势图
- `expanded`：较大 HUD 地图，但仍非完整 Web 地图
- `auto`：根据能力、场景或战斗状态决定 `off/compact`

`MAPHUD_TOGGLE` 应降为显示偏好或尺寸切换，不再占用“地图”主按钮的单击语义。

### 4.3 当前能力阶段

当前小地图主要承担：

- 地图轮廓和当前位置的美术表现
- 完整 Web 地图的视觉预告
- 为未来敌我位置、边界与目标层预留 renderer 和数据结构

当前阶段推荐默认 `auto`：没有战术数据时等价于 `off` 或只在用户固定后显示 `compact`。艺术展示可通过以下方式保留，但不能增加打开完整地图的点击层级：

- 地图按钮 hover-intent（约 350～500ms）显示只读预览；单击仍直接进完整地图
- 预览内允许“固定为 compact”
- 或完全省略 hover 预览，仅在设置中启用 compact

hover 预览是否进入首期施工属于待审项；它是锦上添花，不应阻塞右侧收敛。

### 4.4 未来战术小地图要求

敌我位置能力上线后，`compact` 才应考虑成为默认常驻态。最低契约：

- 玩家、友军、敌军采用颜色 + 形状双通道区分
- 不只依赖红/绿
- 越界单位钳制到边缘并显示方向，不静默消失
- 地图边界、缩放与世界坐标映射稳定
- 敌人仅显示游戏规则允许侦测到的目标，禁止 UI 泄露
- 地形美术降低明度，玩家/敌我/目标标记位于最高视觉层
- 支持大小、背景透明度和关闭选项
- 完整地图打开时以玩家当前位置或当前 hotspot 为初始焦点

---

## 5. 渲染架构建议

### 5.1 首先做的低风险修复

不改变 HWND 数量，先把刘海动画改为稳定宿主：

1. 展开开始时一次性申请动画所需最大矩形
2. 动画帧只改内部绘制参数，不发逐帧 `BoundsOrVisibilityChanged`
3. 收起动画沿用同一最大矩形
4. 动画结束后最多一次收敛到折叠矩形
5. bounds 与 repaint 分成两条可度量的调度路径

### 5.2 是否拆 surface：必须 A/B，不预裁决

候选 A：保留单一 `NativeHudOverlay`，增加稳定 bounds、per-widget 缓存和 dirty composite。

候选 B：按空间/更新域拆分：

- Center：Notch + Combo
- Right：常驻操作 + 条件状态 + 地图
- Toast：左侧瞬时通知

比较指标不是 HWND 数，而是：

- 实际 layered window 像素面积
- 每秒 ULW commit 次数
- 单次 commit p50/p95/p99
- 每次 commit 重绘的 widget 数
- DWM/GPU 与 UI 线程占用
- panel open/close、全屏和混合 DPI 的 z-order 稳定性

---

## 6. 分阶段施工建议

### Phase 0：确定性 harness 与基线

- 建 Native HUD 独立测试宿主或等价确定性入口
- 固定 1024×576、1600×900、1920×1080、4:3 letterbox 场景
- 固定刘海折叠/展开、任务通知、SafeExit、地图四模式、BGM 播放/暂停状态
- 记录 `SetWindowPos`、Bitmap resize、ULW commit、paint source、bounds source
- 生成截图或帧序列供外部审核

### Phase 1：刘海宿主稳定化

- 固定动画 bounds
- 加入 intent delay / click-pin 行为的最终裁决
- 限制最大宽度并改两组布局
- 不迁移新入口，先证明抖动消失

### Phase 2：音频状态与刘海入口迁移

- 提取 `AudioHudState`
- 把低透明度 BGM 包络接入 FPS 线框
- 把点歌机、修改器、帮助迁入刘海展开区
- 移除右侧点歌机标题栏常驻绘制

### Phase 3：右侧单行与条件状态槽

- 六入口单行化
- 任务通知进入条件第二行
- SafeExit 合并或重锚到条件状态区
- 保证第一行在全部状态下不移动

### Phase 4：地图入口与显示模式

- 地图主按钮切为 `TASK_MAP`
- 小地图本体保持 `TASK_MAP`
- `off/compact/expanded/auto` 模式与用户偏好
- 手动地图显示不推动常驻行和条件行
- 是否加入 hover-intent 预览按外审结论执行

### Phase 5：性能 A/B 与 surface 裁决

- 比较单 surface 稳定/缓存方案与多 surface 方案
- 选择总合成面积与提交成本更低、z-order 更稳定的一种
- 删除未采用的试验路径，不长期保留双实现

### Phase 6：文档与回归收口

- 更新 `launcher/README.md` Native HUD 当前组成、布局、路由与 parity gate
- 更新 `agentsDoc/testing-guide.md`（若新增验证入口或门槛）
- 补 `launcher/tests/run_tests.ps1`、真机截图、DPI 人工矩阵
- 运行 `node tools/validate-doc-governance.js`

建议每个 Phase 独立 commit；不要把抖动修复、视觉重排、地图新状态和 surface 拆分塞进同一提交。

---

## 7. 验收门槛

### 7.1 功能

- 地图按钮一次点击打开完整 Web 地图
- 小地图一次点击打开完整 Web 地图
- `MAPHUD_TOGGLE` 不再拦截主地图入口
- 游戏暂停与 BGM 暂停语义、状态、图标完全分离
- 任务通知、可交付、SafeExit 优先级稳定
- 装备、任务、系统设置、修改器、帮助、点歌机路由无回归
- panel 打开/关闭后 Native HUD 正确 Suspend/Resume

### 7.2 几何与交互

- 1024×576 下刘海最大展开不与右侧 204～216px 常驻行重叠
- 单按钮命中目标不小于 34×32 设计像素
- 第一行不因任务、SafeExit 或地图显示而移动
- 地图模式切换不改变第一行和条件行的锚点
- 所有纯图标入口具备 tooltip、hover、pressed、disabled/active 状态

### 7.3 平滑度与性能

- 单次刘海展开/收起期间 HWND placement 与 composed Bitmap resize 各不超过 2 次（端点级）
- 动画 repaint 受统一帧率门控，不因 bounds 路径绕过 coalescing
- 无 1px 往返跳动、hover enter/leave 自激或 z-order 闪烁
- 地图静态时不因 BGM 波形或 Toast 更新而重复执行昂贵地图重建
- idle WebView2 继续保持 `SW_HIDE` / suspend 基线
- 性能不得只以“感觉更顺”验收，必须保留计数与 p95 数据

### 7.4 DPI 与无障碍

- 单屏 100/125/150/175%
- 双屏混合 DPI 启动、跨屏、最大化、还原、全屏
- 敌我标记使用形状 + 颜色双通道
- 地图背景透明度和尺寸可配置
- `prefers-reduced-motion` 的 Web 语义在原生侧有等价的减弱动画策略或配置入口

---

## 8. 风险登记

| 风险 | 影响 | 对策 |
|---|---|---|
| 刘海加入三入口后横向碰撞右侧栏 | 顶部 UI 重叠 | 最大宽度 420～440；改两组/两行；宽度由右栏左边界约束 |
| 先重排视觉、后修宿主 | 新 UI 仍抖动 | Phase 1 先独立完成并验收 |
| 地图主按钮仍切 preview | 玩家多一步才能到完整地图 | 主按钮和小地图本体统一 `TASK_MAP` |
| 小地图当前只有美术却默认常驻 | 空间成本高于功能收益 | 当前默认 `auto/off`；战术能力上线后再评估 compact 默认 |
| 游戏暂停与 BGM 暂停混淆 | 状态和行为错误 | 两套 icon、tooltip、命令与状态模型完全分离 |
| SafeExit 与任务行争用 | 确认入口被覆盖或误触 | 条件状态槽固定优先级；SafeExit 最高 |
| 单一 union 继续跨屏大面积透明合成 | 重绘和 DWM 成本不降 | Phase 5 以像素面积和 commit 数据 A/B 裁决 surface |
| 敌我颜色依赖红绿 | 色觉障碍、复杂背景不可辨 | 形状、轮廓、颜色多通道；背景明度压低 |
| 战术小地图泄露未侦测敌人 | 玩法规则破坏 | UI 只消费经过游戏规则过滤的可见目标集合 |

---

## 9. 外部审核待裁决清单

- [ ] 接受“完整 Web 地图一击直达，小地图不作前置层”
- [ ] 接受右侧六入口顺序与 204～216px 总宽
- [ ] 接受点歌机、修改器、帮助迁入刘海展开区
- [ ] 接受刘海最大宽度 420～440px，并由单行改两组/两行
- [ ] 接受 BGM 包络作为 FPS 线框低透明度背景，而非第二条主折线
- [ ] 接受条件第二行优先级：SafeExit > 可交付任务 > 普通任务通知
- [ ] 裁决 SafeExit 是否完全合并进条件状态槽
- [ ] 裁决当前版本地图默认模式：推荐 `auto`（当前等价 off；未来战术能力可转 compact）
- [ ] 裁决首期是否加入 350～500ms hover-intent 艺术预览
- [ ] 接受 surface 拆分仅在 A/B 后裁决，不预先以 HWND 数量定方案
- [ ] 接受按 Phase 0～6 分提交施工，不做一次性大重写

外审若只批准部分项目，施工计划必须按批准范围重切，禁止默认把未勾选项视为授权。

---

## 10. 跨会话恢复入口

下一段会话开始时：

1. 先读本文状态与 §9 审核结论
2. 再读 `launcher/README.md` 的 Native HUD / parity gate 当前真相
3. 读 `agentsDoc/testing-guide.md` 的 Launcher Host 验证矩阵
4. 从外审批准的第一个 Phase 开始；默认从 Phase 0 harness/基线开始
5. 未获批准前不改 Native HUD 行为，不把本文推荐写成 launcher 当前事实

建议开场指令：

> 外审已完成。读取 `docs/NativeHud常驻UI收敛与地图交互-外部审核备忘-2026-07-10.md`，按已勾选裁决从第一个批准 Phase 开始施工；保持一阶段一提交，并按本文验收门槛验证。

---

## 11. 关联文件

- `launcher/README.md`：Launcher / Native HUD 当前 canonical truth
- `launcher/src/Program.cs`：Native HUD widget 注册与路由接线
- `launcher/src/Guardian/NativeHudOverlay.cs`：bounds union、render coalescing、ULW commit
- `launcher/src/Guardian/Hud/NotchWidget.cs`：刘海状态机、展开动画、FPS 折线
- `launcher/src/Guardian/Hud/RightContextWidget.cs`：右侧工具、地图、任务通知、点歌栏
- `launcher/src/Guardian/Hud/RightHudLayout.cs`：右侧固定布局常量
- `launcher/src/Guardian/Hud/MapHudWidget.cs`：小地图 shared renderer
- `launcher/src/Guardian/Hud/SafeExitPanelWidget.cs`：安全退出状态
- `launcher/src/Guardian/LauncherCommandRouter.cs`：所有入口命令语义
- `launcher/tests/Guardian/*Hud*Tests.cs`：现有 Native HUD 单测
- `logs/perf-latest.jsonl`：最近一次 Native HUD 计数样本

