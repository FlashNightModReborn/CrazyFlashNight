# 地图界面目录说明

**文档角色**：地图界面资产邻近 README。  
**最后核对代码基线**：commit `9f8f0c225`（2026-04-20）。

## 1. 角色说明

本目录保存 `地图界面` 的 XFL 资产与相关导出真相源。

本 README 只负责回答三件事：

- 这个目录里有什么
- 地图迁移时这里扮演什么角色
- 修改地图相关内容时，哪些东西应该在这里改，哪些不应该

跨栈迁移的长期计划、阶段安排、验收口径统一看：

- [docs/地图界面-webview迁移路线图.md](../../../docs/地图界面-webview迁移路线图.md)

本文不是项目级路线图，不承担 Web panel、协议、Host / Bridge 的 canonical 职责。

## 2. 当前目录结构

| 路径 | 作用 |
|------|------|
| `地图界面.xfl` | XFL 工程入口标记 |
| `DOMDocument.xml` | 舞台与顶层时间轴定义 |
| `LIBRARY/` | 符号、元件、位图、时间轴 XML 真相源 |
| `bin/` | 导出或编译相关中间产物 |
| `META-INF/` | XFL 元信息 |
| `PublishSettings.xml` | 发布配置 |
| `MobileSettings.xml` | 移动端配置占位 |

## 3. 迁移中的定位

在地图迁移到 WebView `panel` 的过程中，本目录的定位是：

- 历史资产仓
- 布局真相源
- 导出参照源
- 行为对照源

它不是：

- Web 运行时资源目录
- Web panel 逻辑目录
- 最终 manifest 的唯一存放位置
- 长期的 UI 编辑器替代品

## 4. 真相源约定

迁移期间必须遵守以下真相源顺序：

1. `LIBRARY/*.xml` 与 `DOMDocument.xml` 是历史布局、实例、层级、帧态的真相源
2. FFDec 导出的位图是资源提取产物，不是布局真相源
3. 迁移完成后，Web 侧 `manifest` 才是新运行时真相源

换句话说：

- 要找位置、层级、实例名，先看 XFL / XML
- 要找位图内容或 linkage 对照，可以用 FFDec
- 不能只靠导出 PNG 去反推热点和状态结构

## 5. 修改落点规则

### 5.1 仍应在本目录处理的内容

- 盘点原始符号、位图、图层与实例命名
- 核对热点、点位、楼层、闪光提示在旧时间轴中的对应关系
- 为迁移建立资源映射和命名对照
- 在迁移前确认某个旧行为究竟由哪一层、哪一帧、哪个实例负责

### 5.2 不应继续沉到本目录的内容

- 新 Web panel 的渲染逻辑
- Web 侧交互状态机
- Host / Bridge 协议实现
- 未来 preview / harness 的前端代码
- 长期维护用的地图 manifest 业务逻辑

## 6. 迁移时的工作顺序

建议按以下顺序处理单个地图区域或单类元素：

1. 在 XFL / XML 中定位旧实例、图层和帧态
2. 导出需要的位图或符号参照
3. 把位置、层级、状态整理进 manifest
4. 在 Web panel 中复现交互与视觉
5. 用 preview / harness 或运行时面板校对
6. 确认新链路稳定后，再减少旧时间轴依赖

## 7. 与 FFDec 的关系

FFDec 在本迁移中的推荐用途是：

- 导出位图资源
- 辅助核对 linkage 或资源归属
- 补足 XFL 不方便快速查看的资源细节

FFDec 不应承担：

- 布局真相源
- 最终位置校准工具
- Web 侧热点结构设计器

## 8. 与 Manifest 的关系

后续 Web 地图应收敛到 manifest 驱动。

建议 manifest 至少表达：

- 背景层
- 楼层或场景节点
- 热点区域
- NPC / 任务点位
- 闪光提示
- 显示条件
- 目标跳转

本目录负责为 manifest 提供原始依据，但不建议把最终长期运行时 manifest 直接混放进 XFL 资产目录。

当前最小导出链：

- 运行时 manifest helper：`launcher/web/modules/map-panel-data.js`
- 预览 / 校准页：`launcher/web/modules/map/dev/preview.html`
- CLI 导出：`node tools/export-map-manifest.js --page base --output tmp/map-page-base.json --summary`

也就是说，XFL / FFDec 仍提供原始依据，但当前阶段的“受控 manifest 导出出口”已经固定在 Web 侧工具链，而不是临时复制 DOM 坐标。

## 9. 协作约定

- 对旧 Flash 地图行为有疑问时，先回本目录找真相源，再去改 Web 逻辑
- 新增资源映射或命名规则时，优先更新本文或相邻说明，而不是只留在聊天记录里
- 任何“为了快先手调坐标”的行为，都应在后续回写到 manifest 或对应数据文件
- 不手动编辑 SWF；以 XFL 和受控导出链为准

## 10. 后续补充方向

随着迁移推进，本文可以继续补充以下内容：

- 关键符号与新 manifest 字段的映射表
- 常见楼层或区域的资源命名规则
- 需要特殊处理的旧时间轴逻辑清单
- 从 XFL / FFDec 到 manifest 的导出约定

但这些补充应始终服务于“资产邻近说明”角色，不应把本文扩张成项目级迁移路线图。
