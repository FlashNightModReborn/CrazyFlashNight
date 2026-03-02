# XML 数据体系

> 数据层规范：加载基础设施、XMLParser 行为约定、数据目录结构、专用加载器索引。

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
| `config/` | 系统配置 |

大多数采用 **list.xml 主从模式**：

```
data/items/list.xml          → 引用 50 个分类文件（武器_刀_*.xml、防具_*.xml、消耗品_*.xml …）
data/enemy_properties/list.xml → 引用 11 个敌人定义文件
data/dialogues/list.xml       → 引用 16 个对话文件
data/environment/             → scene_environment.xml、stage_environment.xml、color_engine_preset.xml
data/stages/                  → 按地点组织的关卡数据
data/dictionaries/            → 材料/情报字典
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

> 完整列表（22 个加载器）见 `org/flashNight/gesh/xml/LoadXml/` 源码目录。另有 `BaseStageXMLLoader`（按路径参数加载单个关卡 XML）和 `StageXMLLoader`（非单例工具类，支持 CaseSwitch 条件值解析）。

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

<!-- TODO: 逐步填充 stages/items/units/dialogues/environment 的 Schema 描述 -->
