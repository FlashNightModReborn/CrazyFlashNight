# 项目技术架构总览

> 闪客快打7佣兵帝国 MOD 的整体技术架构与模块间关系。

---

## 1. 架构概览

```
┌─────────────────────────────────┐
│     Flash Player (AS2 客户端)     │
│  ┌─────────┐  ┌──────────────┐  │
│  │ 主 SWF   │  │ 子 SWF/小游戏│  │
│  │(游戏逻辑)│←→│  (hana包)    │  │
│  └────┬─────┘  └──────────────┘  │
│       │ XMLSocket                 │
└───────┼───────────────────────────┘
        │
┌───────┼───────────────────────────┐
│  Node.js 本地服务器               │
│  ┌────┴─────┐  ┌──────────────┐  │
│  │XMLSocket │  │  HTTP/REST   │  │
│  │ 服务     │  │   服务       │  │
│  └──────────┘  └──────────────┘  │
│  ┌──────────────────────────────┐│
│  │ 任务处理器(eval/regex/音频等)  ││
│  └──────────────────────────────┘│
└───────────────────────────────────┘
```

---

## 2. 模块通信流程

### 子 SWF 加载与通信

子 SWF 不作为独立沙箱运行，而是以 **资源注入** 方式集成到主文件中（本质上被视为一种资源文件）：

1. **链接导出**：子 SWF 内的影片剪辑通过 AS 链接（Linkage）导出为可实例化的符号
2. **加载注入**：主 FLA 工程中可显式设置外部 SWF 作为共享库导入（Runtime Shared Library），也可通过 `loadMovie` / `attachMovie` 在运行时加载；两种方式均将子 SWF 库中的链接符号注入到主文件的运行时环境
3. **主文件范围运行**：实例化的影片剪辑在主文件的作用域内运行，可直接访问 `_root`、全局变量和主文件的类库，无跨 SWF 沙箱隔离

> 这意味着子 SWF 与主文件之间不存在显式的消息协议，而是共享同一运行时上下文，直接通过属性和方法调用通信。

### AS2 ↔ Node.js 通信
- 协议：XMLSocket（TCP 长连接）+ HTTP（辅助通道）
- 端口：通过 HTTP `GET /getSocketPort` 获取
- 消息格式：JSON over XMLSocket（`\0` 终止符分帧）
- 详细文档：`tools/Local Server/server.md`
- 客户端入口：`org.flashNight.neur.Server.ServerManager`（单例）
- 初始化脚本：`scripts/通信/通信_fs_本地服务器.as`

#### 连接建立流程

```
1. 端口发现：从 _root.闪客之夜 提取候选端口列表
2. HTTP 探测：POST /testConnection → status=success
3. 获取 Socket 端口：GET /getSocketPort → socketPort=9999
4. XMLSocket 连接：连接 localhost:{socketPort}
5. 断线重连：最多 5 次，间隔 300 帧（≈10s）
```

#### 消息协议

**客户端 → 服务器**（XMLSocket，JSON + `\0`）：
```json
{ "task": "eval|regex|computation|audio", "payload": ..., "extra": ... }
```

**服务器 → 客户端**：
```json
{ "success": true, "result": ... }
{ "success": false, "error": "错误信息" }
```

| 任务类型 | 处理器 | 用途 |
|---------|--------|------|
| `eval` | `controllers/evalTask.js` | VM2 沙箱执行 JavaScript 表达式 |
| `regex` | `controllers/regexTask.js` | 正则匹配（AS2 正则能力有限，委托服务端） |
| `computation` | `controllers/computationTask.js` | 数值计算任务 |
| `audio` | `controllers/audioTask.js` | 音频控制（play/pause/stop/setVolume） |

**HTTP 辅助通道**（调试日志批量上报）：
```
POST /logBatch  →  frame={帧号}&messages={msg1|msg2|msg3}
```
每帧最多发送一次，消息以 `|` 分隔，由 `ServerManager.sendMessageBuffer()` 管理缓冲区。

### XML 数据加载

#### 基础设施

| 组件 | 位置 | 职责 |
|------|------|------|
| `XMLLoader` | `org.flashNight.gesh.xml.XMLLoader` | 底层异步加载（封装 `XML.load()`，`ignoreWhite = true`） |
| `XMLParser` | `org.flashNight.gesh.xml.XMLParser` | 解析 XMLNode → AS2 Object，自动类型转换（字符串→数值/布尔）、同名节点自动合并为数组、HTML 实体解码 |
| `BaseXMLLoader` | `org.flashNight.gesh.xml.LoadXml.BaseXMLLoader` | 抽象基类，提供单例模式 + 数据缓存 + 加载状态管理 + PathManager 路径解析 |
| `PathManager` | `org.flashNight.gesh.path.PathManager` | 环境检测（browser/Steam）→ 自动解析相对路径为绝对 file:// URL |

#### XMLParser 隐式行为

解析器有两个影响消费侧代码的隐式行为，使用时必须了解：

**1. 同名节点自动合并为数组**

同一父节点下出现多个同名子节点时，自动合并为数组；仅出现一次时保持单值。这意味着**同一字段的类型取决于 XML 中恰好出现了几次**：

```xml
<!-- 解析结果：items = "苹果"（String） -->
<root><items>苹果</items></root>

<!-- 解析结果：items = ["苹果", "香蕉"]（Array） -->
<root><items>苹果</items><items>香蕉</items></root>
```

- **优点**：XML 编写简洁，单元素无需包裹冗余标签，数据文件可读性好
- **缺点**：类型不确定——消费侧必须防御性归一化
- **对策**：语义上「一定是列表」的字段，消费侧必须归一化（见下方代码）

```actionscript
// 方式一：使用 XMLParser 内建方法
var list:Array = XMLParser.configureDataAsArray(parsed.items);

// 方式二：手动归一化
if (!(data.items instanceof Array)) { data.items = [data.items]; }
```

**2. 递归解析所有子节点为嵌套对象 + 自动类型转换**

所有子节点递归解析为嵌套 Object，叶节点值自动做类型转换（`"100"` → `100`，`"true"` → `true`）。

- **优点**：零配置，XML 结构直接映射为对象树，新增数据类型无需改解析代码，大幅简化数据装配
- **缺点**：无 Schema 校验（结构错误静默产出错误对象）；自动类型转换可能误判（如编号 `"007"` 变为 `7`，纯数字字符串被转为 Number）
- **对策**：对必须保持字符串的字段，在 XML 中使用非纯数字格式，或在消费侧显式 `String()` 转回

#### 数据目录结构

`data/` 下约 387 个 XML 文件，大多数采用 **list.xml 主从模式**：

```
data/items/list.xml          → 引用 52 个分类文件（武器_刀_*.xml、防具_*.xml、消耗品_*.xml …）
data/enemy_properties/list.xml → 引用 11 个敌人定义文件
data/dialogues/list.xml       → 引用 16 个对话文件
data/environment/             → scene_environment.xml、weather_system.xml 等
data/stages/                  → 按地点组织的关卡数据
data/dictionaries/            → 材料/情报字典
data/config/                  → 运行时配置
```

#### 加载流程（以 ItemDataLoader 为例）

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

#### 专用加载器（均继承 BaseXMLLoader，单例模式）

| 加载器 | 数据路径 | 说明 |
|--------|---------|------|
| `ItemDataLoader` | `data/items/list.xml` | 全部物品（52 个分类文件合并为数组） |
| `EnemyPropertiesLoader` | `data/enemy_properties/list.xml` | 敌人属性（11 文件合并，按名称索引） |
| `NpcDialogueLoader` | `data/dialogues/list.xml` | NPC 对话数据 |
| `EquipmentConfigLoader` | `data/equipment/equipment_config.xml` | 装备配置 |
| `EquipModListLoader` | `data/items/equipment_mods/list.xml` | 装备改造列表 |
| `BulletsCasesLoader` | `data/items/bullets_cases.xml` | 弹药数据 |
| `MissileConfigLoader` | `data/items/missileConfigs.xml` | 投射物配置 |
| `HeroTitlesLoader` | `data/hero/hero_titles.xml` | 称号数据 |
| `MaterialDictionaryLoader` | `data/dictionaries/material_dictionary.xml` | 材料字典 |
| `InformationDictionaryLoader` | `data/dictionaries/information_dictionary.xml` | 情报字典 |
| `InfrastructureLoader` | `data/infrastructure/infrastructure.xml` | 基建定义 |
| `SceneEnvironmentLoader` | `data/environment/scene_environment.xml` | 场景环境 |
| `WeatherSystemConfigLoader` | `data/environment/weather_system.xml` | 天气系统 |
| `BGMListLoader` | `data/render/bgm_list.xml` | BGM 列表 |
| `TrailStylesLoader` | `data/render/trail_styles.xml` | 拖尾样式 |
| `InputCommandListXMLLoader` | `data/inputCommand/list.xml` | 操作指令定义 |
| `StageXMLLoader` | `data/stages/*/stage.xml` | 关卡数据（使用 `parseStageXMLNode`，支持 CaseSwitch 条件值） |

#### 使用模式

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

## 3. 代码组织层次

<!-- TODO: 补充各层之间的依赖关系图 -->

| 层次 | 位置 | 职责 |
|------|------|------|
| 帧脚本层 | `scripts/展现/`、`scripts/引擎/`、`scripts/逻辑/`、`scripts/通信/` | 运行在时间轴上的脚本，直接操作舞台 |
| 类库层 | `scripts/类定义/org/flashNight/` | 七大包：核心逻辑与工具的面向对象实现 |
| FLA 资源层 | `flashswf/` | Flash 可视化资源与元件，需 Flash CS6 编辑 |
| 数据层 | `data/`、`config/` | XML 配置与游戏数据，可直接修改 |
| 服务端 | `tools/Local Server/` | Node.js 服务，为 AS2 客户端提供扩展能力 |

---

## 4. 关键技术决策记录

<!-- TODO: 在自优化环节中记录重要的架构决策及其原因 -->

> 此节在自优化环节中逐步填充。
