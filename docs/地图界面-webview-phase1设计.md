# 地图界面 WebView 迁移 Phase 1 设计

**文档角色**：地图界面迁移 Phase 1 设计与执行文档。  
**最后核对代码基线**：commit `9f8f0c225`（2026-04-20）。

## 1. 本阶段目标

Phase 1 只解决两件事：

- 让地图可以作为独立 WebView `panel` 被打开、关闭、联调
- 建立一条专用的地图桥接协议，证明后续 manifest 驱动和全图迁移有宿主边界可依附

本阶段不解决：

- 全图 1:1 布局复刻
- 完整 manifest
- 视觉升级
- 完整 preview / 可视化构建器

换句话说，Phase 1 的目标不是“把地图做完”，而是“把地图迁移的运行时底座立住”。

## 2. 现有实现基础

当前工程已经具备可复用的 panel / bridge 基础，不需要为地图另起一套宿主机制。

### 2.1 已有面板容器

- `overlay.html` 已有全屏 `#panel-container / #panel-backdrop / #panel-content`
- `panels.js` 已负责通用 `open / close / force_close / ESC / 遮罩关闭`
- 当前面板以 `Panels.register(id, { create, onOpen, onRequestClose })` 方式挂载

这意味着地图完全可以先按“全屏独占 panel”接入，不需要额外发明第二套容器。

### 2.2 已有 Host 生命周期

`WebOverlayForm.cs` 已有：

- `_activePanel` 单活动面板状态
- `panel_cmd` 下发
- Web → Host 的 `type:"panel"` 消息收口
- socket 断开时的 `force_close`

这对地图是合适的，因为地图天然是独占式全屏界面，不需要和其他 panel 并存。

### 2.3 已有桥接样式

商城已经跑通了一套可复用模式：

1. Host 通过 `panel_cmd open` 打开 panel
2. Web panel 在 `onOpen` 后通过 `Bridge.send({ type:"panel", cmd, callId })` 发请求
3. Host 侧任务对象把 web `callId` 转成 Flash `callId`
4. Flash 回包
5. Host 再转写为 `type:"panel_resp"` 发回 Web

地图优先复用这条模式，而不是自造一条不兼容的消息流。

### 2.4 当前地图打开路径

当前 `TASK_MAP` 已切到 Web 地图正式入口：

- `WebOverlayForm.cs` 在 `TASK_MAP` 按钮上直接打开 `panel:"map"`
- 打开参数固定为 `{"source":"task_map","dev":false}`
- 旧 `openTaskMap` 仍保留在 AS2 侧，作为未清理的旧链路，不再承担 launcher 默认入口

开发期临时 `MAP_TEST` 入口已完成使命并移除：

- 当前 Launcher 侧只保留 `TASK_MAP` 这一条正式打开路径
- 地图调试入口统一转到 browser harness / preview / CLI 复核，而不是长期保留运行时子菜单按钮

也就是说，Phase 1 已经完成“Web 地图面板立起来 + `TASK_MAP` 默认切换”，当前剩余的是后续维护与清理工作。

## 3. Phase 1 的核心决策

### 3.1 面板 ID

地图 panel 使用固定 id：

- `map`

原因：

- 短、清晰，和现有 `kshop`、`help` 风格一致
- 后续 `panel_cmd` / `panel_resp` / CSS / 日志都更直观

### 3.2 生命周期所有权

Phase 1 的职责划分固定为：

| 层 | 所有权 |
|------|------|
| Host | 面板开关、activePanel、断线强制关闭 |
| Web panel | 渲染、交互、向 Host 发请求 |
| Flash / AS2 | 地图运行时状态、跳图命令执行 |

不做的事情：

- 不让 Web 直接决定场景跳转结果
- 不让 Flash 直接控制 Web 面板 DOM
- 不把关闭逻辑散到多处

### 3.3 首轮输入策略

Phase 1 直接复用现有 panel 的全屏 hitRect 策略。

原因：

- `panels.js` 当前对活动 panel 直接上报整个 `panel-container`
- 地图本身也是全屏独占 UI
- 首轮没必要先优化复杂点击穿透

细粒度命中优化和局部透传留到后续阶段。

### 3.4 暂停策略

Phase 1 默认不引入商城那种“显式暂停 / 恢复”机制，除非联调证明地图必须暂停。

原因：

- 旧 `openTaskMap` 路径本身不是通过单独 pause 协议打开
- 先保持最小行为改变，减少不必要的状态耦合

如果后续发现地图打开时必须冻结部分输入或逻辑，再补 `mapPanelOpen / mapPanelClose` 的运行态钩子。

### 3.5 回退策略

Phase 1 不建设长期正式回退。

只保留开发期临时切换口，目的仅有两个：

- 联调时快速逃生
- 宿主或桥接未就绪时暂时回到旧路径

切换口应是显式开发开关，而不是长期双轨默认逻辑。

## 4. 协议设计

Phase 1 继续沿用已有的三层消息语义：

- Host → Web：`panel_cmd`
- Web → Host：`type:"panel"`
- Host → Web 回包：`panel_resp`

不新增第二套 message bus。

### 4.1 Host → Web

### 打开地图

```json
{
  "type": "panel_cmd",
  "cmd": "open",
  "panel": "map",
  "initData": {
    "source": "task_map",
    "dev": false
  }
}
```

说明：

- `source` 用于日志和后续扩展
- `initData` 首轮不承载地图全量状态

### 关闭地图

```json
{
  "type": "panel_cmd",
  "cmd": "close",
  "panel": "map"
}
```

### 断线强制关闭

```json
{
  "type": "panel_cmd",
  "cmd": "force_close",
  "reason": "disconnected"
}
```

### 4.2 Web → Host

### 请求关闭

```json
{
  "type": "panel",
  "panel": "map",
  "cmd": "close"
}
```

说明：

- `ESC`、遮罩、关闭按钮统一走这条
- Host 收到后负责清掉 `_activePanel`

### 请求快照

```json
{
  "type": "panel",
  "panel": "map",
  "cmd": "snapshot",
  "callId": "ms1"
}
```

用途：

- Web panel 打开后请求当前地图运行态
- 只拉取动态状态，不混入完整静态布局

### 请求跳转

```json
{
  "type": "panel",
  "panel": "map",
  "cmd": "navigate",
  "callId": "mn3",
  "targetId": "base_floor_1",
  "targetType": "scene"
}
```

用途：

- 点击热点或楼层按钮后请求 Flash 执行真正跳转
- 跳转权仍在 AS2

### 开发期刷新

```json
{
  "type": "panel",
  "panel": "map",
  "cmd": "refresh",
  "callId": "mr2"
}
```

说明：

- 这不是长期业务命令
- 仅用于联调阶段快速重新拉 snapshot

### 4.3 Host → Web 回包

统一继续走 `panel_resp`：

```json
{
  "type": "panel_resp",
  "panel": "map",
  "cmd": "snapshot",
  "callId": "ms1",
  "success": true,
  "snapshot": {
    "version": 1,
    "sceneId": "school",
    "floorId": "roof",
    "flags": {},
    "hotspots": [],
    "markers": [],
    "tips": []
  }
}
```

跳转响应：

```json
{
  "type": "panel_resp",
  "panel": "map",
  "cmd": "navigate",
  "callId": "mn3",
  "success": true,
  "closePanel": true
}
```

失败响应：

```json
{
  "type": "panel_resp",
  "panel": "map",
  "cmd": "navigate",
  "callId": "mn3",
  "success": false,
  "error": "invalid_target"
}
```

### 4.4 Host ↔ Flash

推荐新增一套地图专用命令，风格对齐商城：

- `mapPanelSnapshot`
- `mapPanelNavigate`
- `mapPanelClose`

如联调发现需要打开期初始化，再补：

- `mapPanelOpen`

Flash 回包任务名建议：

- `map_response`

原因：

- 语义清楚
- 可照搬 `ShopTask` 的 callId 映射模式
- 避免把地图业务硬塞进通用 `UiData`

## 5. 静态布局与动态状态的拆分

Phase 1 必须明确区分：

- 静态布局：Web 侧控制
- 动态状态：Flash 侧控制

### 5.1 静态布局

先放在 Web 侧的 stub 数据或早期 manifest 中：

- 背景图
- 楼层按钮列表
- 热点矩形或点击区域
- 默认点位位置
- 基础视觉层级

这些数据不应在 Phase 1 通过 AS2 每次实时下发。

### 5.2 动态状态

通过 `snapshot` 下发：

- 默认打开页
- 哪些热点可用
- 哪些点位需要显示
- 哪些任务闪光需要点亮
- 哪些目标当前不可达

这样可以避免：

- 把 Web panel 做成 Flash DOM 的镜像
- 把 AS2 变成布局引擎

## 6. Phase 1 文件落点

### 6.1 Host / C#

优先改动：

- `launcher/src/Guardian/WebOverlayForm.cs`
- `launcher/src/Tasks/MapTask.cs` 或等价新任务类

职责：

- 为 `TASK_MAP` 提供统一的 `map` panel 打开逻辑
- 处理 Web 发来的 `close / snapshot / navigate / refresh`
- 做 web `callId` 与 flash `callId` 的转发
- 将 Flash 的 `map_response` 改写为 `panel_resp`

说明：

- 不建议把所有地图桥接逻辑继续堆到 `WebOverlayForm.cs`
- 更推荐仿照商城单独抽一个 `MapTask`

### 6.2 Web

优先改动：

- `launcher/web/modules/map-panel.js`
- `launcher/web/modules/map-panel-data.js`
- `launcher/web/modules/map/dev/harness.html`
- `launcher/web/modules/map/dev/qa-suite.js`
- `launcher/web/overlay.html`
- `launcher/web/css/panels.css` 或新地图样式文件

职责：

- 注册 `Panels.register('map', ...)`
- 提供最小头部、关闭按钮、调试信息和热点承载区
- `onOpen` 时发 `snapshot`
- 响应 `panel_resp`
- 点击热点时发 `navigate`

### 6.3 Flash / AS2

优先改动：

- `scripts/展现/UI交互/UI交互_lsy_UI管理.as`
- 新增地图 WebView 适配脚本，建议独立文件而不是继续混在 UI 管理入口里

推荐新增能力：

- `gameCommands["mapPanelSnapshot"]`
- `gameCommands["mapPanelNavigate"]`
- `gameCommands["mapPanelClose"]`

职责：

- 提供当前地图状态
- 执行目标跳转
- 在需要时做关闭后的状态收口

## 7. 执行步骤

建议的具体顺序如下：

1. 新增 `map` panel 模块，先只做空壳和关闭链路
2. 开发期可先加临时联调入口，不直接替换 `TASK_MAP`
3. 接入 `snapshot` 请求与 `panel_resp` 回包
4. 在 Web 侧用真实底图和少量热点验证渲染链
5. 接入 `navigate`
6. 扩到多页面静态底图与跨页热点集合
7. 完成二轮验证后切换 `TASK_MAP`

这个顺序的核心是：先打通链路，再补业务。

## 8. 验收清单

Phase 1 完成时，至少应满足：

- `TASK_MAP` 能打开 Web 地图面板
- `map` panel 能通过按钮、ESC、遮罩关闭
- 地图 panel 打开后能请求并收到一次 `snapshot`
- 点击至少一个测试热点能触发 `navigate`
- Host 断线时地图 panel 会被 `force_close`
- 不依赖最终 manifest 也可以完成端到端联调

当前实现额外约束：

- `snapshot.version = 2`
- `snapshot` 会返回 `defaultPageId`
- `snapshot` 现额外返回 `unlocks` 与 `hotspotStates`，用于多页面锁定态和锁定原因驱动
- `snapshot.dynamicAvatarState.roommateGender` 用于学校页 `室友头像` 的动态图覆盖
- 页内层级按钮改为由 Web 静态数据中的 `filters[].buttonRect` 覆盖到旧地图烘焙按钮位置，避免被大面积热点遮挡
- `enabledHotspotIds` 覆盖多页面热点，而不是只覆盖 `基地一层`
- `TASK_MAP` 已切换到 Web 路径；临时 `MAP_TEST` 别名已清理
- `launcher/web/modules/map-panel-data.js` 现同时暴露 `MapManifest` 与 `MapPanelData` helper，作为当前运行时 manifest 入口
- 最小 browser harness 已落地：`launcher/web/modules/map/dev/harness.html`
- 当前 harness 固定覆盖 `top chrome hit-test`、`右侧层级按钮遮挡`、`学校室友头像动态切换`、`1366x768` 紧凑视口可达性、locked group 的锁定提示与锁定原因
- 最小 preview 已可模拟 `locked groups`，观察 `flashHints / hotspotStates / display.when`

## 9. 延后事项

以下内容明确不进入 Phase 1：

- 全图热点与楼层一次性迁完
- 复杂任务闪光与 NPC 动画
- 细粒度点击穿透
- 完整 preview / 校准器
- 可视化构建器
- 大范围视觉升级

## 10. 默认结论

- 地图桥接不走 `UiData` 扁平键值协议
- 地图沿用现有 `panel / panel_resp` 风格，而不是发明新壳
- 静态布局与动态状态必须拆开
- `MapTask` 独立成类比把逻辑继续堆进 `WebOverlayForm.cs` 更稳
- Phase 1 只要求“壳与协议成立”，不要求“地图已迁完”
