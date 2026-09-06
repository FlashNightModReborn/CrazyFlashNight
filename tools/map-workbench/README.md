# 地图工作台：第一阶段

最后核对代码基线：commit `049eb27e3ed6c5ee264d38b29806ad219267e6d2`。维护者已确认第一阶段维护与预览可用，本地/云端共识及原子部署已完成；发布证据以[运行库记录](../../docs/runtime-build-reproducibility.md)为准，后续范围见[第二阶段内容创作设计](../../docs/地图内容创作工作台-第二阶段产品与CSharp权威收束-ADR-2026-09-06.md)。

游戏入口为 **其他 → 工具 → 地图工作台**。正式部署后使用正常游戏启动入口即可；后续开发验收双击根目录 `地图工作台测试启动.cmd`，使用当前源码身份的隔离候选。范围与发布节奏见[两阶段施工](../../docs/地图工作台与CSharp收束-两阶段施工-2026-09-06.md)。

## 操作

默认以 228px 属性栏 + 弹性大地图呈现；“专注画布”隐藏属性栏，Esc 返回。预览直接运行同一套生产 MapPanel：页签、右侧分层列表、地点标签、头像、场景层和自动取景不另写一份。设计态默认全部解锁、无任务标记，不执行场景/选关导航，不冒充实时游戏状态。

选择图块或头像后可拖动编辑边框，也可填写坐标/尺寸。滚轮或 +/- 缩放；中键或空格+拖动平移；“聚焦所选”放大选中对象，“玩家取景”恢复生产自动取景。相机只改变观察变换，既不改定义也不随倍率扩大 Canvas backing 分配。“编辑边框”关闭后仅呈现生产地图外观。“对比保存前”保留草稿。头像坐标相对地点，移动场景图时随地点移动。

场景图可改矩形，地点可改显示名，头像可改相对坐标和尺寸，页面可改标题与页签名。生产筛选列表使用共享布局，GUI 只开放筛选名称及纵向排序值（沿用 buttonRect.y）；历史矩形其余值不伪装成可自由拖动的生产按钮位置。NPC 身份、分组、目的帧、任务与解锁规则第一阶段只读。

“保存到项目”仅更新 `data/map/map_definition.json`；**重启同一正式版本或隔离候选后**完整地图与 NativeHud 使用新定义。草稿预览独立，不修改当前游戏目录或存档。“撤回所选修改”恢复原字节，配置后来改变时拒绝覆盖。结果未知时点击“重新读取 / 核对结果”。草稿支持 JSON 导入/导出，导入必须匹配配置摘要并通过同一 C# 校验。

## 内核与边界

`launcher/src/Data/MapDefinition.cs` 负责结构、允许字段、热点并集和 HUD 投影；`MapAuthoringStore.cs` 负责固定路径、摘要、进程间互斥、原子写和撤回。GUI/CLI 共用这些源码，CLI 不另写规则。操作与备份位于 `tmp/map-workbench/changes`，需要撤回或对账时不得清理。

Host 用 WebView2 的 document-created 脚本在 `https://overlay.local` 顶层页面注入 C# 校验后的启动快照；物理 `map-definition.js` 只检查该快照，不存数据副本。不能用 WebResourceRequested 拦截虚拟映射目录中的脚本。既有 Node 审计和浏览器静态服务器直接读同一 JSON，不参与生产写入。NativeHud 从 C# 生成内存投影；旧 HUD JSON 暂留作构建兼容和等价基线。AS2 的 `map_catalog / task_npc_registry` 仍走兼容派生，解锁、任务与导航第二阶段才切流。

XFL 校准矩形只作参考；场景保存会重算关联热点边界并记录手调，头像身份不随显示位置改变。`migrate-legacy.js` 是一次性机械提取器，不是日常工具。

旧 `tools/export-map-avatar-assets.py` 默认元数据输出会覆写 `map-avatar-source-data.js`，不得用该默认输出替代现在的薄适配器。素材导入与元数据候选合并属于第二阶段，本工作台第一阶段不调用该旧写入链。

`modules/map/authoring/preview.html` 是生产预览入口，不加载游戏 Bridge。父子消息受 exact Window、同源及打开轮次 session 限制；MapPanel 的 authoring API 仅在该隔离子文档开启，普通地图没有作者相机。DTO 与头像源均独立实例，关闭工作台即卸载子文档。旧正式运行时尚不支持地图定义注入：本阶段按开发者入口约定验收，不新增兼容副本或自动部署路径。

## CLI 与浏览器

需要仓库锁定的 .NET SDK，复用 Launcher 解析器；没有 Python/Java 依赖。

```powershell
powershell -File tools/map-workbench/run.ps1 -Command read
powershell -File tools/map-workbench/run.ps1 -Command serve
# 浏览器打开 http://127.0.0.1:18765/
```

构建后的 `MapWorkbench.dll api <项目根>` 从 stdin 读 JSON，stdout 返回一条 `{success,data|error}`。操作为 `read / preview / apply / query / undo`；preview 接收 `{expectedDigest,changes}`，apply 额外接收客户端生成的 32 位小写十六进制 `operationId`，query/undo 只接收该编号。changes 行为 `{pageId,kind,id,values}`，例如 `kind:"scene",values:{rect:{x:211.6,y:95.25,w:471.05,h:179.25}}`。只预览请调用 preview。

开发服务器仅在显式 serve 时监听回环并验证 API Origin/Host；按钮操作会调用同一 C# 内核真实写入项目。

## 验证

- 构建 CLI 后执行 `node tools/map-workbench/test-core.js`：隔离目录验证预览零写、身份保护、保存读回、幂等、漂移、撤回以及 40 个 NativeHud 地点与当前 Web 定义投影逐字段等价（不能把编辑前的旧 HUD JSON 当作编辑后的 golden）。
- serve 后执行 `node tools/map-workbench/test-browser.js`：实际 C# 后端的拖动、预览、对比、草稿导入导出、保存、精确撤回、重开对账与草稿保留、头像和关闭重开；对当前配置作可恢复的小改动，成功时恢复原字节。
- serve 后执行 `node tools/map-workbench/test-viewport.js`：1024×576 / 1600×900 / 2560×1440、DPR 1.5 的只读画布占比、专注模式和属性栏溢出检查。
- Host `MapWorkbenchTaskTests` 验证实例和字段边界；现役地图、Workbench 与文档门另行执行。
- Windows 上构建并运行 `webview-smoke/MapWebViewSmoke.csproj`，参数为项目根目录：以实际 WebView2、虚拟目录与生产 `overlay.html` 验证启动注入逐字段一致、4 页 / 40 地点、零脚本错误、来源隔离及作者子文档 UI / DTO 隔离。数字按 JS Number 精确比较，290 和 290.0 不因 JSON token 类型差异误报。测试不显示交互窗口，不进入玩家存档。

该加载方式遵循 [WebView2 虚拟主机不触发资源拦截的限制](https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/webresourcerequested)和 [document-created 注入时序](https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2.addscripttoexecuteondocumentcreatedasync)。

机器验证不能代签游戏入口、人类视觉或操作手感；最终候选身份与未验项目在施工计划记录。
