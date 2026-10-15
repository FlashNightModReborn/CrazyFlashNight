# Antigravity 素材源稿

唯一编辑源为旁边 `Antigravity专用素材/Antigravity专用素材.xfl` 及其完整目录；Flash CS6 直接发布 `flashswf/arts/new/Antigravity专用素材.swf` 供运行时与自动化验证使用。原稿归档在本目录（XFL 目录之外），避免 CS6 另存 XFL 时清理目标目录，同时剔除回包中的冗余栅格预览图（PNG/GIF）与原始位图，仅保留权威矢量 SVG、时间轴与几何清单。装配和发布入口见 [美术资产装配](../../../../agentsDoc/art-asset-assembly.md)。

## 已归档资产

- **2026-10-15 [CF6 普通男僵尸 R5 来源归档](CF6普通男僵尸-R5/README.md)**（来自 `cf6-zombie-redraw-r5.zip`）：
  - 活体分件：`CF6普通男僵尸-R5/inputs/live/393..402.svg`（10 个原位注册的纯矢量分件，涵盖脚靴、小腿、大腿、髋部、上臂、张爪手、前臂、躯干、头部、垂指手）。
  - 碎尸分件与映射：`CF6普通男僵尸-R5/death-parts/409..475.svg`（67 个死亡图形）与 `death-mapping.json`、`inputs/death-reference/shape-manifest.json`。其中 48 个为纯矢量血肉/骨骼图形，19 个含合图裁切的碎块通过原生遮罩层 1:1 复用活体矢量分件（`401` 头部、`394` 小腿、`393` 脚靴），零位图、零重复绘制。
  - 时间轴：`inputs/live-timelines.json`（`403..408` 六段活体动作）与 `inputs/death-reference/death-timeline.json`（`476` 三分支血腥死 `a0`/`a1`/`a2`）。
  - 导出敌人模板：`敌人-CF6普通男僵尸`（库内路径 `Antigravity/CF6普通男僵尸/敌人-CF6普通男僵尸`）。

- **2026-10-15 [CF6 女僵尸 R2 来源归档](CF6女僵尸-R2/README.md)**（来自 `cf6-female-zombie-redraw-r2.zip`）：
  - 活体分件：`CF6女僵尸-R2/parts/1619..1628.svg` 与 `source/core-art.json`（10 个原位注册的纯矢量分件，含金棕束带破衣躯干、尖叫面部头部母版与黑色高跟长靴四肢）。
  - 碎尸分件与清单：`CF6女僵尸-R2/death-parts/1635..1692.svg`（58 个死亡图形）与 `reference/shape-manifest.json`。其中 55 个为原版纯矢量血肉/骨骼与描边，3 个含头部裁切的碎块（`1635`、`1637`、`1639`）通过原生遮罩层直接复用单一 `1627-头部母版` 元件，零位图、零重复绘制。
  - 时间轴：`reference/timelines.json`（`1629..1634` 六段活体动作、`1693` 三分支血腥死 `a0`/`a1`/`a2` 及 `1694` 根容器坐标）。
  - 导出敌人模板：`敌人-CF6女僵尸`（库内路径 `Antigravity/CF6女僵尸/敌人-CF6女僵尸`）。

## 确定性生成与校验

生成脚本位于 `tools/cf6-zombie-assets/build.py`：

- 重新从本目录归档源导入并生成原生 XFL：
  `python tools/cf6-zombie-assets/build.py --import-approved`
- 校验无位图、无断链引用与清单一致性：
  `python tools/cf6-zombie-assets/build.py`
