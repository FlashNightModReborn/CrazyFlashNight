# XML 数据体系

---

## 1. 加载基础设施

| 组件 | 位置 | 职责 |
|------|------|------|
| `XMLLoader` | `org.flashNight.gesh.xml.XMLLoader` | 底层异步加载（封装 `XML.load()`，`ignoreWhite = true`） |
| `XMLParser` | `org.flashNight.gesh.xml.XMLParser` | XMLNode → AS2 Object，自动类型转换 + 同名节点合并 + HTML 实体解码 |
| `BaseXMLLoader` | `org.flashNight.gesh.xml.LoadXml.BaseXMLLoader` | 抽象基类：单例 + 数据缓存 + 加载状态 + PathManager 路径解析 |
| `PathManager` | `org.flashNight.gesh.path.PathManager` | 环境检测（browser/Steam）→ 解析相对路径为绝对 file:// URL |

---

## 2. XMLParser 隐式行为

### 同名节点自动合并为数组

多个同名子节点 → Array，仅一个 → 单值。**同一字段的类型取决于 XML 中出现几次**。

```xml
<root><items>苹果</items></root>                         <!-- items = "苹果"（String） -->
<root><items>苹果</items><items>香蕉</items></root>       <!-- items = ["苹果","香蕉"]（Array） -->
```

**对策**：语义上「一定是列表」的字段，消费侧必须归一化：

```actionscript
var list:Array = XMLParser.configureDataAsArray(parsed.items);
// 或：if (!(data.items instanceof Array)) { data.items = [data.items]; }
```

### 递归解析 + 自动类型转换

所有子节点递归解析为嵌套 Object，叶节点值自动转换：`"100"` → `100`，`"true"`/`"false"` → Boolean。

**陷阱**：
- 纯数字编号被转为 Number（`"007"` → `7`）→ 需保留字符串时显式 `String()` 转回
- Boolean vs Number 不一致 → 消费侧以 truthy/falsy 判断，不要用 `=== true` 或 `=== 1`

---

## 3. XML 编写规范

- 声明：`<?xml version="1.0" encoding="UTF-8"?>`
- 缩进：4 空格，属性值双引号，添加中文注释说明参数用途
- **注释保护**：代码处理 XML 时必须检查中文注释是否被保留（许多解析器/序列化器默认丢弃注释）

---

## 4. 数据目录结构

以下目录均为**运行时加载，重启生效**：

| 目录 | 用途 |
|------|------|
| `data/stages/` | 关卡定义 |
| `data/items/` | 物品配置 |
| `data/units/` | 单位数据 |
| `data/dialogues/` | 对话脚本 |
| `data/environment/` | 环境设置 |
| `data/config/` | 运行时配置 |
| `data/map/` | WebView 地图面板配置（`map_panel.xml` 单文件） |
| `data/intelligence/` | 情报详情 legacy txt 文本；保留为 AS2 旧界面和 H5 迁移来源 |
| `data/intelligence_h5/` | Launcher Web 情报面板 H5 JSON 组件树正文 |
| `config/` | 系统配置 |

大多数采用 **list.xml 主从模式**：

```
data/items/list.xml          → 引用 50 个分类文件（武器_刀_*.xml、防具_*.xml、消耗品_*.xml …）
data/enemy_properties/list.xml → 引用 11 个敌人定义文件
data/dialogues/list.xml       → 引用 16 个对话文件
data/environment/             → scene_environment.xml、stage_environment.xml、color_engine_preset.xml
data/stages/                  → 按地点组织的关卡数据
data/dictionaries/            → 材料/情报字典
data/intelligence/            → 按情报名称存放的 legacy txt 正文
data/intelligence_h5/         → 按情报名称存放的 H5 JSON 组件树正文
```

### 配置文件索引

**config/ 目录**：`PIDControllerConfig.xml`（PID 参数）、`WeatherSystemConfig.xml`（天气/昼夜/光照）

**根目录配置**：
- `./config.toml` — 运行时配置（Flash/SWF 路径等）。注意 `automation/config.toml` 是自动化脚本配置，二者用途不同
- `config.xml` — 游戏主配置
- `crossdomain.xml` — Flash 跨域策略

---

## 5. 加载流程（以 ItemDataLoader 为例）

```
PathManager.initialize()  →  检测运行环境
        ↓
ItemDataLoader.getInstance().load(onSuccess, onError)
        ↓
BaseXMLLoader 检查缓存 → 命中则直接回调
        ↓ 未命中
XMLLoader 异步加载 data/items/list.xml
        ↓
XMLParser.parseXMLNode() 解析 → { items: ["消耗品_货币.xml", "武器_刀_默认.xml", ...] }
        ↓
递归加载每个子文件 → 逐一解析 → 合并为单一数组
        ↓
回调返回合并数据 → 存入 _root.物品属性列表（按名称索引）/ _root.物品属性数组（顺序访问）
```

---

## 6. 专用加载器（均继承 BaseXMLLoader，单例模式）

**高频加载器**：

| 加载器 | 数据路径 | 说明 |
|--------|---------|------|
| `ItemDataLoader` | `data/items/list.xml` | 全部物品（50 个分类文件合并为数组） |
| `EnemyPropertiesLoader` | `data/enemy_properties/list.xml` | 敌人属性（11 文件合并，按名称索引） |
| `NpcDialogueLoader` | `data/dialogues/list.xml` | NPC 对话数据 |
| `BulletsCasesLoader` | `data/items/bullets_cases.xml` | 弹药数据 |
| `MissileConfigLoader` | `data/items/missileConfigs.xml` | 投射物配置 |
| `StageInfoLoader` | `data/stages/list.xml`（级联子目录） | 关卡元信息 |
| `SceneEnvironmentLoader` | `data/environment/scene_environment.xml` | 场景环境 |
| `InputCommandRuntimeConfigLoader` | `data/config/InputCommandRuntimeConfig.xml` | 指令 DFA 运行时参数 |
| `MapAvatarVisibilityLoader` | `data/map/map_panel.xml` | WebView 地图面板的 `avatar_visibility` 门控规则（瘦身后 map_panel.xml 仅剩此段；缺失=空表=默认全可见，仅影响头像门控，不阻塞）。**groups/hotspots 已迁出本文件**，真相源 = launcher/web/modules/map-panel-data.js，build.ps1 Step 1c 派生为 `data/map/map_catalog.json`，AS2 经 `DataQueryService("map_catalog")` → `MapPanelCatalog.applyFromCatalogJson` 启动期拉取（导航权威，失败硬报错不降级）。`task_npcs/aliases` 同样迁出，走 `DataQueryTask("task_npc_registry")`（NPC→hotspot 映射，**同时驱动**：① 地图任务红点 ② 任务面板「前往交付」按钮可达态 `finishNavigable` 与 `navigateFinish` 跳转执行路径。失败/未就绪 = 静默降级：红点不亮 + 面板「前往交付」按钮禁用 + `navigateFinish` 回 `not_navigable`，均不阻塞游戏进入与正常交付）|
| `InformationDictionaryLoader` | `data/dictionaries/information_dictionary.xml` | 情报条目元数据；Launcher Web 情报面板由 C# `IntelligenceTask` 读取同一 XML，并按字典白名单读取 `data/intelligence_h5/<itemName>.json` |

> 完整列表见 `org/flashNight/gesh/xml/LoadXml/`。另有 `BaseStageXMLLoader`（按路径加载单个关卡 XML）和 `StageXMLLoader`（非单例，支持 CaseSwitch 条件值解析）。

### 情报字典、legacy txt 与 H5 JSON

`data/dictionaries/information_dictionary.xml` 维护情报条目的名称、排序、分页解锁值、加密等级与替换/截断规则。legacy txt 位于 `data/intelligence/<Name>.txt`，使用 `@@@PageKey@@@` 分隔分页正文；H5 正文位于 `data/intelligence_h5/<Name>.json`，每个 JSON 必须包含 `schemaVersion:1`、`itemName`、`skin`、`pages[]`，且 `pages[].pageKey` 必须与字典中的 `Information PageKey` 完全一致。

Launcher Web 情报面板不开放 WebView2 对 `data/` 或项目根的 fetch 权限，而是由 C# `IntelligenceTask` 精确命中字典项后读取固定目录 JSON，并校验最终 full path 仍在 `data/intelligence_h5/` 下。正式 runtime 入口通过 AS2 `intelligenceState` 只回每条情报收集值、解密等级和玩家名，C# 合并本地 catalog 后返回 `state` 小包；Web 点击目录项时再请求 `snapshot(itemName)`，H5 snapshot 返回 `contentMode:"h5"`、`skin` 与 `pages[].blocks`，锁定页不下发 blocks。H5 JSON 只允许白名单组件树和 inline token，内容中不得包含任意 HTML、脚本或事件属性；组件完整语义、逐篇手工创作流程和 KimiCode 使用边界见 [情报 H5 组件创作交接](../docs/情报H5组件创作交接.md)。

H5 数据门禁：示范/迁移期可运行 `node tools/validate-intelligence-h5.js --allow-missing`，正式全量门禁使用 `node tools/validate-intelligence-h5.js --strict`。批量迁移给 KimiCode 的自包含 prompt 由 `node tools/generate-intelligence-h5-prompts.js --batch-size 10` 生成；该工具只产出 `tmp/intelligence-h5-prompts/`，实际施工范围限定在 `data/intelligence_h5/`。创作层表达增强可用 `node tools/enhance-intelligence-h5-expression.js` 重新应用当前人工固化的示范组合；`幻层残响` 当前刻意保持生成基线，避免额外组件稀释原文本高信息密度。

### map_panel.xml schema 摘要（拓扑收束后，2026-06：仅剩 avatar_visibility）

> groups/hotspots 已迁出本文件 → 见下方 `## map_catalog.json schema`。task_npcs/aliases 见 `## task_npc_registry.json schema`。

```xml
<map_panel>
  <avatar_visibility>
    <!-- 静态 NPC 头像的进度/基建门控声明。无对应 rule = 默认可见。
         同 npc 多条 rule = AND；rule 内部 chain/min（配对）+ requireInfra（"A|B" = OR）三类 AND。 -->
    <rule avatarId="…（必须命中 launcher staticAvatars/dynamicAvatars id）"
          npc="…（AS2 字典 key；建议命中 task_npcs/npc.name）"
          chain="主线|引导|支线|挑战|废城|彩蛋|异形|大学|后勤|预览"
          min="<非负整数>"
          requireInfra="自行车|摩托车|越野车"/>
  </avatar_visibility>
</map_panel>
```

**硬约束**：
- `avatar_visibility` 由 `MapPanelCatalog.applyAvatarVisibilityFromXml`（经 `MapAvatarVisibilityLoader`）解析；整段缺失 = 空表 = 全部默认可见（合法，不报错）；解析/校验失败 → trace + reset avatar 表 + 返回 false。
  - rule 必须有 avatarId + npc；chain/min 必须配对出现（要么都有要么都没）
  - chain ∈ `VALID_CHAIN_NAMES`（10 条 task_chain canonical，与 `SaveManager.REPAIR_DICT_TASK_CHAINS` 同步）
  - requireInfra="A|B" 切分后每项 ∈ `VALID_INFRA_NAMES`（自行车/摩托车/越野车）
  - 同一 avatarId 不可指向不同 npc；avatarId 必须命中 launcher staticAvatars/dynamicAvatars id 集
  - 外部 validator：`node tools/audit-map-avatar-visibility.js`
- **groups/hotspots 不再硬编码 REQUIRED 白名单**：集合正确性由 build.ps1 Step 1c 的 `tools/derive-map-catalog.js` 派生期 gate 保证；`MapPanelCatalog.applyFromCatalogJson` 运行期只做结构校验（id/group/frame 齐全、group 已声明、page 合法、非 base 组有 lockedReason、id 不重复）。
- **新增/改 hotspot 拓扑**：只需在 `launcher/web/modules/map-panel-data.js` 编辑，跑 build/derive 刷新 `map_catalog.json` 即可；**不再需要回写本 XML、不再需要改 AS2 REQUIRED 列表、不再需要重编译 SWF**（asLoader.xml boot 仍编译进 asLoader.swf，但拓扑数据本身是运行期 query）。
- **新增任务 NPC**：在 staticAvatars/dynamicAvatars 加 entry，build.ps1 Step 1b 自动派生 `task_npc_registry.json`。

### map_catalog.json schema（派生产物，禁手改）

`data/map/map_catalog.json` 由 `tools/derive-map-catalog.js` 从 launcher web manifest 派生，build.ps1 Step 1c 自动跑。AS2 端 `MapPanelCatalog.applyFromCatalogJson` 经 `DataQueryService.query("map_catalog", ...)` 启动期消费（C# 侧 `DataQueryTask("map_catalog")` → `DataCache.GetMapCatalog` → `XmlDataLoader.LoadMapCatalog`）。

```json
{
  "_generatedAt": "<ISO timestamp>",
  "_source": "launcher/web/modules/map-panel-data.js",
  "_note": "generated by tools/derive-map-catalog.js, do not hand-edit",
  "groups": [
    { "id": "base", "page": "base", "label": "基地" },
    { "id": "…", "page": "base|faction|defense|school", "label": "…", "lockedReason": "…（非 base 必填）" }
  ],
  "hotspots": [
    { "id": "…", "group": "…（必须在 groups 里声明）", "frame": "…（帧名 / sceneName）" }
  ]
}
```

派生时校验（失败 → build exit 1）：非 base 页 hotspot 必有 unlock group + base 页 hotspot 一律 group=base；group→page 反查唯一；hotspot/group id 全局唯一；frame 非空；group.page 合法。
**失败语义（与 task_npc_registry 不同）**：map_catalog 是导航权威 → C# 缺失/坏 JSON → `success:false`；AS2 boot（asLoader.xml）收到 false 必须明确报错（`_root.发布消息`）+ 地图面板不可用，**绝不静默降级**。

### task_npc_registry.json schema（派生产物，禁手改）

`data/map/task_npc_registry.json` 由 `tools/derive-task-npc-registry.js` 从 launcher web manifest 派生，build.ps1 Step 1b 自动跑。AS2 端 `MapTaskNpcRegistry.applyFromQuery` 通过 `DataQueryService.query("task_npc_registry", ...)` 启动期消费。

```json
{
  "_generatedAt": "<ISO timestamp>",
  "_source": "launcher/web/modules/map-panel-data.js",
  "_note": "generated by tools/derive-task-npc-registry.js, do not hand-edit",
  "task_npcs": [
    { "name": "…（canonical NPC 全名，跟 staticAvatars.label 一致）", "hotspot": "…（必须在 map_panel.xml hotspots 里）" }
  ],
  "aliases": [
    { "name": "…（任务字符串非正式拼写）", "canonical": "…（必须命中 task_npcs.name）" }
  ]
}
```

派生时校验：label 不重复（含大小写折叠）+ hotspot 命中 Catalog.HOTSPOT_PAGES + alias.canonical 命中 task_npcs。AS2 端校验等价。失败 → AS2 静默降级（任务红点列表为空），错误走 `_root.服务器.发布服务器消息` 留痕。

### launcher/web 端 NPC 头像坐标 schema (Stage C 以后 hotspot-relative)

`launcher/web/modules/map-avatar-source-data.js`（手工维护 IIFE）每个 entry 不再带绝对坐标 `center/rect`，而是相对所属 hotspot 的 runtime rect 左上角偏移：

```jsonc
{
  "symbolName": "<XFL 头像 MovieClip 名>",
  "assetUrl": "assets/map/avatars/<symbolName>.png",
  "hotspotId": "<launcher map-panel-data hotspot id>",
  "relX": <number>,            // 头像 rect 左上角 X 偏移
  "relY": <number>,            // 头像 rect 左上角 Y 偏移
  "size":     { "w": 44, "h": 44 },    // 渲染尺寸 (px); 室友 dynamic = 48
  "crop":     { "scaleX": 1.0, "scaleY": 1.0, "tx": -0.5, "ty": 0.5 },  // XFL 不可重算元数据, debug-only
  "assetSize": { "w": 44, "h": 44 }    // PNG 实际尺寸; 审计用
}
```

`launcher/web/modules/map-panel-data.js` 的 `dynamicAvatars` 也走同样的相对坐标 schema（室友独占该路径）：

```js
{ id: 'roommate', label: '室友', kind: 'roommateGender',
  hotspotId: 'school_dormitory', relX: 20.7, relY: 17.65, w: 48, h: 48 }
```

**渲染流程**：`resolveStaticAvatarRect` / `resolveDynamicAvatarRect` 通过 `MapPanelData.findHotspot(pageId, hotspotId)` 取 **runtime rect**（经 `applyXflLayoutOverrides` + `syncCompositeHotspotRects` 两道覆盖后的最终值），再加 `relX/relY` 得到屏幕坐标。调 hotspot rect 时 NPC 头像自动跟随，无需手动重算坐标。

**`MapManifest.markers[*].rect` 在 overlay 生产运行时为 `null`**：`map-avatar-source-data.js` 走 [panels-lazy-registry.js](../launcher/web/modules/panels-lazy-registry.js) 懒加载（map panel 首次打开时才注入），而 [map-panel-data.js](../launcher/web/modules/map-panel-data.js) 末尾 `var MapManifest = MapPanelData.exportManifest()` 在 boot 期立刻跑，此时 `MapAvatarSourceData === undefined`，`resolveStaticAvatarExportRect` / `resolveDynamicAvatarExportRect` 走 graceful-null 分支。**消费方约束**：不要直接读 `MapManifest.markers[k].rect`，rect 由 map-panel 渲染期 `resolveStaticAvatarRect` / `resolveDynamicAvatarRect` 动态派生；如确需 manifest 形式带 rect 的导出，走 Node 工具（`tools/export-map-manifest.js` 已预加载 source-data，输出包含正确 rect）。harness.html / preview.html 因为 `<script>` 标签把 source-data 显式放在 panel-data 之前，dev 工具读 MapManifest 也是带 rect 的。

**调位置**：
- 调一个 NPC 位置：只改 source-data.js（static）或 panel-data.js dynamicAvatars（动态）的 `relX/relY`
- 调一个 hotspot 位置：按 effective rect 来源改 `_pages.<page>.hotspots[].rect` / `_xflLayoutOverrides` / `_pages.<page>.sceneVisuals[].rect`（参考 `MapPanelData.findHotspot` 返回值跟哪个静态源数字最接近，那就是 effective 来源）

**跨边界 NPC**（理科教授 / 文科老师）：保留 `qa-suite.js` reviewOnly 白名单豁免；如需根治需要美术介入。

### 使用模式

```actionscript
// 异步加载
ItemDataLoader.getInstance().load(
    function(data:Object):Void {
        // data 为合并后的物品数组
    },
    function():Void { trace("加载失败"); }
);

// 已加载后直接获取缓存
if (loader.isLoaded()) {
    var data:Object = loader.getData();
}
```

---

## 7. 新增数据文件流程

1. 确认数据类型对应的目录
2. 参照该类型现有文件的 XML 结构
3. 使用 UTF-8 编码，添加中文注释说明用途
4. 参阅 `agentsDoc/game-design.md` 确认数值平衡参考

