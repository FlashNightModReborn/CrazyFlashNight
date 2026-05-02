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
| `MapPanelLoader` | `data/map/map_panel.xml` | WebView 地图面板（启动失败时硬错、不做 fallback；Catalog + TaskNpcRegistry 的 canonical 白名单精确/超集校验在代码侧） |
| `InformationDictionaryLoader` | `data/dictionaries/information_dictionary.xml` | 情报条目元数据；Launcher Web 情报面板由 C# `IntelligenceTask` 读取同一 XML，并按字典白名单读取 `data/intelligence_h5/<itemName>.json` |

> 完整列表见 `org/flashNight/gesh/xml/LoadXml/`。另有 `BaseStageXMLLoader`（按路径加载单个关卡 XML）和 `StageXMLLoader`（非单例，支持 CaseSwitch 条件值解析）。

### 情报字典、legacy txt 与 H5 JSON

`data/dictionaries/information_dictionary.xml` 维护情报条目的名称、排序、分页解锁值、加密等级与替换/截断规则。legacy txt 位于 `data/intelligence/<Name>.txt`，使用 `@@@PageKey@@@` 分隔分页正文；H5 正文位于 `data/intelligence_h5/<Name>.json`，每个 JSON 必须包含 `schemaVersion:1`、`itemName`、`skin`、`pages[]`，且 `pages[].pageKey` 必须与字典中的 `Information PageKey` 完全一致。

Launcher Web 情报面板不开放 WebView2 对 `data/` 或项目根的 fetch 权限，而是由 C# `IntelligenceTask` 精确命中字典项后读取固定目录 JSON，并校验最终 full path 仍在 `data/intelligence_h5/` 下。正式 runtime 入口通过 AS2 `intelligenceState` 只回每条情报收集值、解密等级和玩家名，C# 合并本地 catalog 后返回 `state` 小包；Web 点击目录项时再请求 `snapshot(itemName)`，H5 snapshot 返回 `contentMode:"h5"`、`skin` 与 `pages[].blocks`，锁定页不下发 blocks。H5 JSON 只允许白名单组件树和 inline token，内容中不得包含任意 HTML、脚本或事件属性；组件完整语义、逐篇手工创作流程和 KimiCode 使用边界见 [情报 H5 组件创作交接](../docs/情报H5组件创作交接.md)。

H5 数据门禁：示范/迁移期可运行 `node tools/validate-intelligence-h5.js --allow-missing`，正式全量门禁使用 `node tools/validate-intelligence-h5.js --strict`。批量迁移给 KimiCode 的自包含 prompt 由 `node tools/generate-intelligence-h5-prompts.js --batch-size 10` 生成；该工具只产出 `tmp/intelligence-h5-prompts/`，实际施工范围限定在 `data/intelligence_h5/`。创作层表达增强可用 `node tools/enhance-intelligence-h5-expression.js` 重新应用当前人工固化的示范组合；`幻层残响` 当前刻意保持生成基线，避免额外组件稀释原文本高信息密度。

### map_panel.xml schema 摘要

```xml
<map_panel>
  <groups>
    <group id="base|warlord|rock|blackiron|fallen|defense|restricted|schoolOutside|schoolInside"
           page="base|faction|defense|school"
           label="…"
           lockedReason="…"/>   <!-- base 组无 lockedReason -->
  </groups>
  <hotspots>
    <hotspot id="…" group="…（必须在 groups 里声明）" frame="…（帧名）"/>
  </hotspots>
  <task_npcs>
    <npc name="…" hotspot="…（page 由 Catalog 派生）" x="…" y="…"/>
    <alias name="别名" canonical="…（必须命中某个 npc name）"/>
  </task_npcs>
</map_panel>
```

**硬约束**（`MapPanelCatalog.applyFromXml` + `MapTaskNpcRegistry.applyFromXml` 在加载时强制校验；任一失败 → trace + **先无条件 reset 所有表为安全零值、isLoaded 复位为 false** + 返回 false。同时 `MapPanelLoader.load` 对"结构上无效但非 null"的 XML 会调用 `clearCache()`，防止基类缓存污染后续 reload）：
- `groups` 的 id 集合 = `REQUIRED_GROUP_IDS`（9 个，精确相等）
- `hotspots` 的 id 集合 = `REQUIRED_HOTSPOT_IDS`（38 个，精确相等）
- `task_npcs/npc` 的 name 集合 ⊇ `REQUIRED_NPC_NAMES`（54 个，允许超集）
- 非 base 组必须显式声明 `lockedReason`（为空会让锁区提示静默消失，按硬失败处理）
- hotspot.group 必须命中 groups 里声明的 id；npc.hotspot 必须命中 hotspots
- alias.name 不得与真实 npc 重名、两 alias 不得重名、npc 名不得仅大小写不同
- 新增热点/分组属于**设计变更**，需同步修改 XML + 代码内 REQUIRED 列表 + launcher 侧 manifest

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

