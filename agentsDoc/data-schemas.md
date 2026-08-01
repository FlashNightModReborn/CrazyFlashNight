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
| `data/shops/` | NPC 金币商店清单、逐 NPC 商品目录与开发者分组 |
| `config/` | 系统配置 |

大多数采用 **list.xml 主从模式**：

```
data/items/list.xml          → 引用 52 个物品分类文件 + item_sets.xml 套装中心表
data/enemy_properties/list.xml → 引用 11 个敌人定义文件
data/dialogues/list.xml       → 引用 16 个对话文件
data/environment/             → scene_environment.xml、stage_environment.xml、color_engine_preset.xml
data/stages/                  → 按地点组织的关卡数据
data/dictionaries/            → 材料/情报字典
data/intelligence/            → 按情报名称存放的 legacy txt 正文
data/intelligence_h5/         → 按情报名称存放的 H5 JSON 组件树正文
data/shops/list.xml           → 引用 data/shops/npcs/*.json（每个 NPC 一个文件）
```

### 关卡敌人屏外尸体保留参数

`data/stages/**/*.xml` 的 `SubStage/Wave/SubWave/EnemyGroup/Enemy/Parameters` 支持实例级参数 `保留屏外尸体:true`。该参数由 `ObjectUtil.cloneParameters()` 解析为严格布尔值，并随当前敌人实例的初始化对象传入；不要在 `DeathEffectRenderer` 中硬编码兵种 ID、名称或素材名。

```xml
<Enemy>
    <Type>兵种67</Type>
    <Quantity>1</Quantity>
    <Parameters>称号:火凤堂赤旌,保留屏外尸体:true</Parameters>
</Enemy>
```

- 省略或写 `false`：保持默认策略，尸体中心处于屏外时跳过 `BitmapData.draw()`。
- 写 `true`：只在死亡贴图事务内绕过离屏拒绝，并在单位已被常规可见性剔除时临时设为可见；同步绘制结束后立即恢复原隐藏状态。
- 该参数不关闭单位存活期的屏外剔除，不覆盖 `DeathEffectRenderer.isEnabled` 总开关，也不改变死亡音效、变身阈值或伤害结算。
- 只应用于少量需要死亡结果可追溯的重要实例；不要给成群杂兵批量标记，避免同帧多次矢量 `draw()` 形成尖峰。

当前代表验收点是 `黑铁会总部/黑铁会总堂.xml` 第二图首波的火凤。修改渲染器或该参数后，运行 `tools/test-offscreen-corpse-retention.ps1`；需要 Flash 行为证据时再运行 `scripts/run-offscreen-corpse-retention-tests.ps1`。

### 关卡地图资源箱声明

`data/stages/**/*.xml` 中六类地图箱（保险柜、生存箱、装备箱、资源箱、纸箱、隐藏资源点）的 `row/col` 是行为契约，不是宽松展示参数：

- `row > 0 && col > 0` 表达 Web 战利品意图；当前能力上限为 `col <= 8 && row * col <= 64`，超界或非整数 fail-closed。
- 只有精确 `row == 0 && col == 0` 表达直接地面掉落。负数、单边为零、正负混合、只缺一维或显式坏值都是配置错误，禁止静默降级为直投。
- 掉落规则的 `最小数量/最大数量` 必须同时省略或同时给出。两者同时省略时按明确默认 `1/1`；只缺一端、不可解析、非正、非整数、倒置或超出安全跨度均 fail-closed。该契约由 Web 物化、精确 `0×0` 直投和攻击破碎共用同一个运行时校验器，静态审计覆盖全部六类箱声明。
- 攻击破碎是独立玩法语义：在尚未建立 Web authority 时直接地面掉落；已 reservation/active/suspended/pending 的箱必须先由统一 break guard 截住，不能重复发奖。

改动关卡箱声明后运行 `tools/test-audit-stage-chests.ps1`；改箱体 XFL/回调时再追加 `tools/test-map-loot-wiring.ps1` 与对应独立 XFL 发布验证。完整权威、状态机与人工代表场见 [地图资源箱实施与验收基线](../docs/地图资源箱-Web战利品工作台与开锁流程-前期调研-2026-07-17.md)。

### NPC 商店 `npc-shop.v2`

`data/shops/list.xml` 中每个 `<shops>` 指向一个独立 NPC JSON。运行时加载器把 v2 文档归一化回 `_root.shops[shopId] = catalog`，因此旧 NPC 对目录对象的引用与 `catalogIndex` 协议身份不变；展示配置进入 `_root.shopLayouts[shopId]`。

```json
{
  "schema": "npc-shop.v2",
  "shopId": "冷兵器商人",
  "title": "冷兵器商人",
  "catalog": { "0": "爪刀", "38": { "name": "旧世残篇", "requiredInfo": "符线溯源笔记", "purchaseLimit": 20 } }
}
```

- `catalog` 键必须是稳定的非负整数索引；值只能是物品名字符串或 `{name,requiredInfo,purchaseLimit}`。`purchaseLimit` 可省略，存在时必须为 `1..999999` 整数；它是策划显式设置的单笔设计配额，而不是统一默认限额。未配置时，装备以背包技术容量为上限，堆叠物品使用 `999999` 技术护栏，情报再与当前剩余持有容量取最小值。预览与提交必须复用同一动态上限；不得先按请求量扣款、再依赖收集栏 clamp 截断入账。
- `sections` 可省略；省略时 Web 从物品现有字段构建互斥分类树：一级 `type=武器/防具/消耗品/收集品`，二级使用 `use`，武器三级以刀的 `actiontype` 或枪械的 `weapontype` 细分。未知值进入“其他”，不会隐藏商品；AS2 snapshot 只透传这些现有展示字段，不改变物品 XML 权威。
- `sections` 存在时完整替代自动分类，必须覆盖目录内全部索引，`all` 为 Web 隐式保留分组。当前生产目录不启用人工分组；配置规则与示例见 [`data/shops/README.md`](../data/shops/README.md)。
- 空目录合法，用于显式停用但仍需保留身份的 NPC。
- 套装元数据单一权威为 `data/items/item_sets.xml`，由 `data/items/list.xml/<itemSets>` 声明入口。中心表每个 `<set>` 必须含唯一的 `<id>ascii_snake</id>`、唯一中文 `<name>` 与唯一整数 `<order>`；`order` 控制所有 Web / 库存投影的套装分组顺序。
- 物品根节点只可选声明 `<setId>ascii_snake</setId>` 表达成员归属，不得重复写 `setName/setOrder`。运行时只信显式 `setId`，不得用名称、描述、`dressup` 或配方猜测归属；同槽变体也必须逐物品人工决定是否标注。当前经人工复核的高置信度基线为 66 套 / 327 件，升级版、同槽变体与缺槽套仅在人工确认后纳入；NPC 版及归属不确定成员仍不得自动纳入。
- `ItemDataLoader` 并行加载物品分类文件与中心套装表；`ItemUtil.loadItemData()` 在构建 `_root.物品套装索引` 前按 `setId` 注入 `setName/setOrder`，因此 AS2 → Host → Web 的既有逐物品协议保持不变。Web 共享筛选模型把“套装”作为与“类别”并列的分支。库存类界面使用 `{branch:"set",setId:"..."}` 请求 AS2 对完整权威容器筛选，省略 `setId` 表示全部显式标注物品，不能用当前 Web 页做汇总。
- **效果扩展**：`item_sets.xml` 以可选 `<effects>/<effect_N>` 承载声明式属性表项、routine 门控和必需组件 manifest；成员的 init/tier/bullet 等完整配置留在物品 `<lifecycle>/<attr_N>`，只用 `setGate/effectId/componentId` 引用中心效果，不复制参数树。没有 `effects` 的套装继续只作展示分组。一期 `SetEffectController` 已消费 `member_components` routine 与 `resistance_entry`：gated init 在 commit 内登记可回滚资源，`finalize` 统一排序 context/子周期并最后写入 `魔法抗性`。该字段存在会开启对应定向特攻破击，属于负向暴露而非普通 Buff；仅开放 `add`，字段缺失时使用 `baseIfMissing`，写入层不钳制。剑圣固定 `baseIfMissing=10/value=75`，无其他来源时最终为 85。字段闭集、事务接线与验收以 [套装系统设计](../docs/套装系统-设计与剑圣一期验收-2026-07-14.md) 为真源。
- 改动后运行 `node tools/validate-item-sets.js` 与 `node tools/validate-npc-shops.js`；前者校验每个物品 `setId` 命中中心表、中心 ID/名称/排序唯一、仅装备可入套、每套至少两个成员且中心表无零成员套装，后者校验商品映射与自动分类 fallback。`launcher/build.ps1` Step 1h3 同样 fail-fast 执行两项门禁。

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
| `ItemDataLoader` | `data/items/list.xml` | 并行加载 52 个物品分类文件与 `item_sets.xml`；合并数组附带中心套装元数据 |
| `EnemyPropertiesLoader` | `data/enemy_properties/list.xml` | 敌人属性（11 文件合并，按名称索引） |
| `NpcDialogueLoader` | `data/dialogues/list.xml` | NPC 对话数据 |
| `BulletsCasesLoader` | `data/items/bullets_cases.xml` | 弹药数据；联弹支持「模板×单元体」双层配置（`<chainTemplate>` + `<chainUnit>`，加载期由 `ChainBulletConfigResolver` 派生合并，显式条目优先） |
| `MissileConfigLoader` | `data/items/missileConfigs.xml` | 投射物配置 |
| `StageInfoLoader` | `data/stages/list.xml`（级联子目录） | 关卡元信息 |
| `SceneEnvironmentLoader` | `data/environment/scene_environment.xml` | 场景环境 |
| `InputCommandRuntimeConfigLoader` | `data/config/InputCommandRuntimeConfig.xml` | 指令 DFA 运行时参数 |
| `MapAvatarVisibilityLoader` | `data/map/map_panel.xml` | WebView 地图面板的 `avatar_visibility` 门控规则（瘦身后 map_panel.xml 仅剩此段；缺失=空表=默认全可见，仅影响头像门控，不阻塞）。**groups/hotspots 已迁出本文件**，真相源 = launcher/web/modules/map-panel-data.js，build.ps1 Step 1c 派生为 `data/map/map_catalog.json`，AS2 经 `DataQueryService("map_catalog")` → `MapPanelCatalog.applyFromCatalogJson` 启动期拉取（导航权威，失败硬报错不降级）。`task_npcs/aliases` 同样迁出，走 `DataQueryTask("task_npc_registry")`（NPC→hotspot 映射，**同时驱动**：① 地图任务红点 ② 任务面板「前往交付」按钮可达态 `finishNavigable` 与 `navigateFinish` 跳转执行路径。失败/未就绪 = 静默降级：红点不亮 + 面板「前往交付」按钮禁用 + `navigateFinish` 回 `not_navigable`，均不阻塞游戏进入与正常交付）|
| `InformationDictionaryLoader` | `data/dictionaries/information_dictionary.xml` | 情报条目元数据；Launcher Web 情报面板由 C# `IntelligenceTask` 读取同一 XML，并按字典白名单读取 `data/intelligence_h5/<itemName>.json` |

> 完整列表见 `org/flashNight/gesh/xml/LoadXml/`。另有 `BaseStageXMLLoader`（按路径加载单个关卡 XML）和 `StageXMLLoader`（非单例，支持 CaseSwitch 条件值解析）。

### 关卡进度门控与一次性拾取

`data/stages/**.xml` 的地图元件 `Instances.Instance.Parameters` 与直接拾取物 `Pickups.Pickup.Parameters` 共用 `ProgressValidator` 门控。所有已配置条件按 AND 合取：

- `最小主线进度` / `最大主线进度`：既有主线闭区间门控。
- `任务链名称` + `最小任务链进度` / `最大任务链进度`：读取 `_root.task_chains_progress[任务链名称]`；配置任一任务链区间但漏写链名时失败关闭。
- `要求进行中任务ID`：仅当 `_root.tasks_to_do` 中存在该任务 ID 时通过；用于区分首次剧情行动与任务完成后的副本复盘。
- `一次性领取ID`：仅用于可拾取物。成功进入背包后写入 `_root._saveExt.一次性领取[ID]` 并标记存档为脏；生成前若已领取则不再创建。背包满、未实际拾取或仅进入关卡不会消耗领取资格。`_saveExt` 由 `SaveManager` 透传，无需扩展存档主体或 `save_repair_dict.json`。

首次剧情遗物推荐同时使用任务门控和一次性领取：前者控制时间线与复盘显示，后者阻止玩家在任务交付前退出重进重复领取。

```xml
<Pickups>
    <Pickup>
        <Name>Type56R</Name>
        <Value>1</Value>
        <x>1200</x>
        <y>500</y>
        <Parameters>
            <任务链名称>铁枪会</任务链名称>
            <最小任务链进度>1</最小任务链进度>
            <最大任务链进度>1</最大任务链进度>
            <要求进行中任务ID>70002</要求进行中任务ID>
            <一次性领取ID>iron_spear_70002_veteran_type56r</一次性领取ID>
        </Parameters>
    </Pickup>
</Pickups>
```

### 射线子弹 `<rayConfig>`

`data/items/bullets_cases.xml` 的 `<attribute><rayConfig>` 会由 `TeslaRayConfig.fromXML()` 解析，并自动把子弹标记为射线类型。`rayMode` 现支持 `single | chain | pierce | fork | flame`；`flame` 是连续喷火模式：每帧重扫沿线目标，以第 `pierceLimit` 个有效目标作为阻挡长度，`flameGrowSpeed/flameRetractSpeed` 控制当前长度追随目标长度，`flameTickInterval` 控制伤害脉冲帧间隔，`flameLifetime` 控制单发喷火束存活帧数。喷火常用的段数/预算字段：`flamePulseCount`（单发伤害脉冲段数）、`flameHotPulseStart/flameHotPulseCount`（热属性段窗口）、`flameHotDamageType/flameHotMagicType`（热段临时覆盖伤害属性）、`flameTotalHitBudget`（单发总伤害结算预算，0 为不限）、`flameMaxHitsPerTarget`（同一目标单发内最多吃几段，0 为不限）。`flameUseWeaponVelocity=true` 时，喷火束会按发射武器 `<velocity>` 缩放 `flameGrowSpeed/flameRetractSpeed`；`flameVelocityBase` 是基准速度，`flameVelocityMinScale/flameVelocityMaxScale` 是钳制范围，用于避免低速配置让火束完全爬不出去或高速配置退化为瞬时射线。`flameReuseMaxOriginDist` 控制同喷口连续火束视觉复用允许的起点偏移半径（默认 32px），只影响显示对象复用与淡出刷新，不改变命中扫描或伤害结算。

喷火视觉风格使用 `vfxStyle=flame_stream` / `vfxPreset=flame_stream`，常用字段包括 `rayLength`、`rayWidthFactor`、`damageFalloff`、`thickness`、`waveAmp`、`waveLen`、`waveSpeed`、`tongueCount`、`tipBloomScale`、`smokeColor`、`visualDuration`、`fadeOutDuration`。`rayWidthFactor>0` 时运行时走带宽射线碰撞，半宽由 `Z轴攻击范围 * rayWidthFactor * 0.5` 计算；视觉宽度仍由 `thickness/waveAmp` 等字段独立控制。

### 装备平衡记录 `<balance>`

`<balance>` 的原则是**只记录 XML `<data>` 中没有的公式输入与最小展示门**，不要复制 `level/weight/defence/hp/mp/damage/power/interval` 等现有数值。AS2 战斗逻辑不消费它；展示层只允许从严格验证的武器 profile 生成最小 `balanceSummary`，不能让 Web 自行读取审计原文或推断状态。

**枪械 / 武器**：尚未上线的契约统一为严格 `formulaFamily=weapon + schemaVersion=1`，不兼容此前平铺/v2 或 runtime SHA 开发草案。item 根 `<balance>` 只保留容器身份、数字 `workbookVersion` 和 `<profiles>`；完整 SHA 只在工具注册表、规则表与外部审计台账保存一次。`data/data_*` 每个静态形态都要有独立完整 profile，保存八个公式输入、`status/displayEligible/inputDigest/auditRef`，缺 profile 禁止回退基础形态。条款、证据、预算和可选短备注存入不由 ItemDataLoader 加载的 `tools/cf7-balance-tool/records/weapon-balance-audit.xml`，runtime profile 必须由台账机械同步并逐字段对账。完整 schema、digest 和施工流程以 `tools/cf7-balance-tool/docs/agent-balance-record-design.md` 为准，取值判据及条款 ID 以 `tools/cf7-balance-tool/docs/weapon-balance-rulebook.md` 为准。公式最高权威仍是 `0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx`。

**防具**：属于另一公式族，不因武器 v1 的不兼容决定而迁移。不要沿用枪械字段；防具平衡表的核心额外输入是 `extraWeightLayers`，`armorType` 仅在不能从装备位/用途稳定推断时填写，合法值为 `standard | glove | necklace`。

```xml
<balance>
  <armorType>standard</armorType>        <!-- 可选：常规/攻击手套/项链映射 -->
  <extraWeightLayers>1</extraWeightLayers>
  <formula>1</formula>
  <rationale>WL=1：合成装备，配方见 data/crafting/...</rationale>
</balance>
```

### 装备插件条件战技

`data/items/equipment_mods/*.xml` 的插件支持根层 `<skillSwitch>`（与 `<skill>`、`<stats>` 同级），用于按宿主装备 `use` / `weapontype` 切换主动战技。命中分支时优先使用分支技能，未命名 `<use>` 是 default 分支，仅在无命名分支命中时使用；多个分支同时匹配时按 XML 顺序取第一个。根层 `<skill>` 仍可作为兼容回退，但有条件战技映射时建议把默认技能也写进 `skillSwitch` 的 default 分支，避免 tooltip 表达成多个可同时装载的战技。`skillSwitch` 只决定技能，不应用属性，条件数值仍走 `<stats><useSwitch>...</useSwitch></stats>`。完整写法与示例见 `data/items/equipment_mods/README.md`。

`useSwitch` / `skillSwitch` 的无前缀 `name` 继续匹配宿主 `use` 与 `weapontype` 的联合集合。需要消除同名歧义时可写 `use:值` 或 `weapontype:值`：例如 `weapontype:手枪` 只命中精确子类，不会命中仅因 `use=手枪` 而共用装备槽的冲锋手枪和大威力手枪。`grantsUse` 同时进入无前缀集合与 `use:` 限定集合。Tooltip 必须隐藏内部限定符，显示为“装备类型：…”或“武器子类：…”。`stats.useSwitch.use` 分支除数值运算符外还可声明 `provideTags` 与 `requireTags`：前者仅在分支命中时提供结构，后者仅在分支命中时并入根层安装前置，并必须同时用于候选过滤、安装检查、缺失标签提示与拆卸依赖判定。

### 声明式子弹命中行为 `<hitBehavior>`

武器运行时数据可包含 `<hitBehavior>` 对象；插件通过 `<stats><merge><hitBehavior>...</hitBehavior></merge></stats>` 写入。`ShootInitCore.generateBulletProps` 将该对象透传到子弹，`BulletQueueProcessor.settleHit` 仅在实际伤害结算成功且至少一个分段真实命中时按封闭 `type` 分发；联弹分段模型中 `scatterMissCount >= actualScatterUsed` 的全 MISS/直感结果不得挂载行为。该字段表达游戏行为，不得与既有视觉命中特效字段混用，也不得存任意 AS2 函数名或可执行字符串。

当前正式类型为 `grayGooPrimer`（读取端仍接受旧名 `toughnessVulnerabilityPrimer`）。字段为：`stackGroup`、`profileId`、`decayDelay`（停火后开始衰减的帧数）、`decayInterval`（逐格衰减间隔）、`maxStacks`、`hitStacks`、`breakStacks`、`milestoneInterval`、`damagePerStack`（小数倍率）、`crumblePerMilestone`（击溃的原始百分比数值）、`executeAtMax`（斩杀的原始百分比数值）与 `sameSourceOnly`。同一 `stackGroup` 内按 `(sourceUID, profileId)` 保存候选，最终易伤只取完整候选的 MAX，不跨 profile 拼接字段。命中在伤害管线前预测是否跨过节点，临时配给击溃/斩杀并重选 `DamageManager`；`DamageResult.hasActualHit()` 在击溃、斩杀和后置叠层三处统一排除普通 MISS 与联弹全段 MISS/直感，只有至少一段真实命中才兑现节点并实际增加层数。

灰蛊裂隙弹使用 18 格、6/12/18 三个节点、每格 1% 全队易伤；冲锋枪/大威力手枪/普通手枪每次有效命中分别增加 1/2/3 格，真实破韧追加一次本 profile 等价命中。基础档仅由冲锋枪完整使用，参数为 `decayDelay=90/decayInterval=10/crumblePerMilestone=1/executeAtMax=8`；大威力手枪分支显式锁定为 `90/10/0.1/5`，防止继承冲锋枪的自建自吃补偿；普通手枪是 `150/15/0.3/8`。节点分别在衰减到 0/6/12 格时重新武装。`ToughnessBroken` 只表示非刚体真实破韧；刚体越阈仅清槽、不发布。层数变化发布 `GrayGooStacksChanged(target, stacks, maxStacks, profileId)`，并同步写入 `target.grayGooStackCount/grayGooMaxStacks`。`useSwitch.merge.hitBehavior` 是深度 merge；追猎射击的六个发射点也必须从两把手枪属性透传该对象。

### 装备插件格展示词典

`data/items/equipment_mods/*.xml` 的插件定义是档级、用途与定位的业务元数据单源。每个 `list.xml/<items>` 子文件根层必须显式声明 `<modGrade>low|medium|high|special</modGrade>` 与 `<catalogScope>armor|firearm|blade|fist|universal|underbarrel</catalogScope>`；文件名前缀只服务人类导航，运行时禁止据此推断。`catalogScope` 只用于 Web 目录分组，精确安装权限仍由每个 `<mod>` 的 `use/weapontype/excludeWeapontype` 与 `EquipmentUtil` 决定。

`data/items/equipment_mods/ui_presentation.xml` 是上述 ID 的受控标签/色号词典，以及插件格角色→符号、`tag`→默认角色的展示词典；它不得重新分配单个插件的档级或目录用途。`EquipModListLoader` 并行加载词典与子文件，向 `EquipmentUtil.modDict` 投影 `modGrade/catalogScope/uiGradeLabel/uiGradeColor/uiScopeLabel/uiRole/uiRoleLabel/uiSymbol`。角色符号采用 `形状-solid|outline` 受控 token；单个插件仅在 `tag` 默认角色不准确时声明 `<uiRole>` 覆盖，禁止填写任意 Unicode/HTML 符号。`EquipmentTuningService.modCandidates[]` 暴露档级/用途/定位/受控符号供候选树和紧凑瓦片展示，未知符号由 Web 白名单回退；`InventoryPanelService` 对松散插件材料附加 `modMeta`，但 `availabilityCode` 仍是安装可用性的唯一权威。

`data/items/收集品_材料_插件.xml` 与 `收集品_材料.xml` 只维护库存、经济、图标和说明，不复制档级/用途/定位。构建门 `node tools/validate-equipment-mod-ui.js` 固定校验 105 个 mod、四档、六种 scope、全部现役 `tag`/角色/符号，并要求每个 mod 名称在 `data/items/list.xml` 引用的物品文件中恰好出现一次；其中插件材料文件的 101 个条目必须全部映射到 mod。特殊档原图错色视为美术流程问题，不参与运行时取色或兼容逻辑。

### 长枪副武器 `<subweapon>`

长枪下挂 / 内置副武器使用根层 `<subweapon>`，与普通 `<skill>` 共享长枪特殊槽，不能并存。`EquipmentCalculator` 会把配件根层 `subweapon` 写入宿主 `itemData.subweapon`；`DressupInitializer` 装载长枪时读取 `subweapon` 并交给 `LongGunSubWeaponCore`，不会装入普通主动战技。

最小字段：`name`、`cd`、`power`、`capacity`、`reserveName`、`bullet`、`consumeMode`、`consumeTiming`。常用字段：`sound`、`split`、`diffusion`、`velocity`、`range`、`impact`、`damageType`、`magicType`、`powerMultiplier`、`initialLoaded`、`manualReloadAnimation`、`manualReloadBurden`、`clipCostPerLoad`、`fireCost`、`mp`、`hp`。

当前迁移语义：`consumeMode=onLoadGroup + consumeTiming=onReloadCommit` 表示 1 份 `reserveName` 支持一组 `capacity` 发；首仓由 `initialLoaded` 表达预装；R 联动补装与 F 快装都在换弹提交帧扣组弹药。逐发消耗武器使用 `consumeMode=onFire + consumeTiming=onFire + fireCost`。

### 联弹双层配置与补弹参数（2026-06-12 起）

联弹子弹名格式为 `"{模板前缀}-{单元体}"`（如 `横向联弹-普通子弹`），其弹壳/属性配置在 `bullets_cases.xml` 按全名查表。组合配置由两层声明在加载期派生（`ChainBulletConfigResolver`，挂在 `InfoLoader` 聚合之后、回调分发之前）：

- **模板层** `<chainTemplate>`：`prefix`（联弹前缀）+ 可选 `shell`（`xOffset`/`yOffset`/`simulationMethod` + `casingMap` 的 `entry: material→casing` 矩阵，弹壳按**武器机匣**决定：机枪系→重机枪弹壳族、手枪系→手枪弹壳族，横/纵散布方向不影响弹壳）+ 可选 `attributeOverride`（**仅替换单元体已声明的键**，如横向系霰弹式发射 pierceLimit 特判 2）。
- **单元体层**：在单元体自身 `<bullet>` 条目内声明 `<chainUnit><material>能量|加强|普通|无壳</material></chainUnit>`；材质未命中模板 casingMap（如 `无壳`）则该组合不派生弹壳。
- **合并契约**：显式 `"模板-单元体"` 条目始终优先，派生仅补缺（shellData/attributeData 按各自键独立判断）；movement 配置不可派生，必须显式（如 `横向拖尾追踪联弹-普通无壳子弹`）。
- **审计**：物品+配件数据就绪后，递归扫描全部 `bullet` 键（覆盖 `data`/`data_ice`/`data_fire` 等变体、lifecycle、skill、配件 stats/skill），未声明模板/单元体或弹壳未解析发服务器告警。**边界**：AS2 代码内嵌子弹名不在审计范围（新增时人工核对）；配件词缀经 `PropertyOperators.mergeString` 前缀保留拼接动态合成组合——后缀必须是已声明单元体，任意已声明模板组合即被全量派生覆盖。
- **武器补弹参数** `<fillrate>`（武器 `<data>` 内，可选；2026-06-12 起普及化为默认行为）：**缺省/`auto` = 默认**——纵向联弹按本次实际射击间隔（含枪械师点按/连按修正、配件改装后的运行时射速）生成整数分数 `分子=霰弹值-1`、`分母=ceil(间隔毫秒/每帧毫秒)`，通过 Bresenham 累加器在调度器有效间隔的第 `分母` 个更新 tick 补完；同 tick 内与下一发调度的先后顺序不作保证。高射速（有效间隔 1 tick，如 XM214）一帧补完；低射速（如磁稳贯穿弹改装后 interval 300ms+）率<1 隔帧补弹，2,3,2,… 的不均匀帧分布是预期行为。**正数 = 显式每帧补弹率**：允许小数，执行时向上定点化为 `ceil(fillrate×4096)/4096`，最小有效正数为 `1/4096`；低于该精度的配置仍按 `1/4096` 执行。技能等不经 WeaponFireCore 的直调路径无间隔戳 → 回退每帧 1 发旧行为。

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
         同 avatarId 多条 rule = AND；rule 内部 chain/min（配对）+ requireInfra（"A|B" = OR）三类 AND。 -->
    <rule avatarId="…（必须命中 launcher staticAvatars/dynamicAvatars id）"
          npc="…（AS2 字典 key；建议命中 task_npcs/npc.name）"
          chain="主线|引导|支线|挑战|废城|彩蛋|异形|大学|后勤|预览|铁枪会"
          min="<非负整数>"
          requireInfra="自行车|摩托车|越野车"/>
  </avatar_visibility>
</map_panel>
```

**硬约束**：
- `avatar_visibility` 由 `MapPanelCatalog.applyAvatarVisibilityFromXml`（经 `MapAvatarVisibilityLoader`）解析；整段缺失 = 空表 = 全部默认可见（合法，不报错）；解析/校验失败 → trace + reset avatar 表 + 返回 false。
  - rule 必须有 avatarId + npc；chain/min 必须配对出现（要么都有要么都没）
  - chain ∈ `VALID_CHAIN_NAMES`（task_chain canonical，与 `SaveManager.REPAIR_DICT_TASK_CHAINS` 同步）
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
    {
      "name": "…（canonical NPC 全名，跟 staticAvatars.label 一致；允许同名多 placement）",
      "hotspot": "…（必须在 map_catalog hotspots 里）",
      "placement": "…（默认 name@hotspot；同名 NPC 的稳定 placement 键）",
      "avatarId": "…（launcher staticAvatars/dynamicAvatars slot id）"
    }
  ],
  "aliases": [
    { "name": "…（任务字符串非正式拼写）", "canonical": "…（必须命中 task_npcs.name）" }
  ]
}
```

派生时校验：同一 `name+hotspot` placement 不重复、`placement` 不重复、大小写折叠只允许同一原名、hotspot 命中 Catalog.HOTSPOT_PAGES、alias.canonical 命中 task_npcs。AS2 端校验等价。失败 → AS2 静默降级（任务红点列表为空），错误走 `_root.服务器.发布服务器消息` 留痕。

任务数据新增 placement 字段：`get_npc_hotspot` / `finish_npc_hotspot` 可选；当 `get_npc` 或 `finish_npc` 在 registry 中有多个地图 placement（例如同一个 `武器大师` 分别位于 `gym` 与 `first_defense`）时，必须填写对应 hotspot。`tools/derive-task-catalog.js` 会在 build Step 1e 校验该字段命中 registry；运行时 `NPCTaskCheck`、任务红点、HUD 交付、任务面板 `finishNavigable/navigateFinish` 都按 `NPC 名 + hotspot` 解析。旧任务未填写 hotspot 时保持 name-only 兼容。

### task-catalog.json schema（派生产物，禁手改；WS6 事件日志/任务树）

`launcher/web/modules/tasks/task-catalog.json` 由 `tools/derive-task-catalog.js` 从 **`data/task/*.json` + `data/task/text/*.json`**（游戏权威任务源，AS2 也读它）派生，build.ps1 **Step 1e** 自动跑。与 map_catalog 方向相反：map 是 web JS→AS2 JSON，task 是**游戏 JSON→web JSON**，web 拿同源只读投影（无 AS2/web 双源漂移）。**消费方 = web 任务面板「事件日志」tab 直读**（非 AS2，非 DataQueryService；web `fetch('modules/tasks/task-catalog.json')`）。

形状：`{ version, taskCount, tasks:{ "<id>":{ id, chain:[name,seq|null], type, title, description, npcName, stageReq, itemReqs, rewards, req:[前置id...], hasGetConv, hasFinishConv } }, chains:{ name:[id...按seq升序] }, chainsUnsequenced:{ name:[id...] } }`。`req`=get_requirements（前置任务 id），供图表视图画前置依赖连线 + 算拓扑深度（约 +3KB；多数任务 0-1 个前置）。

**不含**：对话文本本体（留 AS2，catalog 仅持 `hasGetConv/hasFinishConv` 布尔；点「接取/完成对话」时 `replayDialogue` 按需回传【单任务】对话文本行 `lines:[{speaker,sub,text}]`，web 内联展开纯文本、不关面板）、`finish_remote`（写路径权威字段留 AS2）、`conditions`（cur 是运行态读数须 AS2 现算，detail 回 `conditions:[{label,cur,target}]`；catalog 不带）。

**任务接取优先级 `priority`（可选）**：默认 `0`。同一 NPC 在同一时刻存在多个可接任务时，运行时按 `priority` 降序选择；优先级相同则保持 `data/task/list.xml` 合并后的加载顺序。该字段只影响 NPC 点击接取顺序，不改变 `get_requirements`、任务链进度或 Web catalog 拓扑。

**场景调度板字段（可选，运行时权威）**：`dispatch_board` 为字符串或字符串数组，声明任务归属的调度板 ID；`dispatch_order` 为板内升序权重，缺省 `9999`；`dispatch_kind` 为表现分类，当前正式使用值为 `story`；`dispatch_replayable:true` 允许任务完成后以“已结案·复盘案例”继续留在板上。复盘进入关卡不重新 AddTask，因此不会重复触发任务奖励和完成对白，关卡内常规收益仍按关卡自身规则处理。这些字段由 AS2 `TaskPanelService` 直接读取，不进入派生 `task-catalog.json`。调度板 snapshot 只暴露已接取、当前可接取或已完成且可复盘的归属任务；进入关卡时必须再次校验任务仍归属该板，并满足“任务进行中”或“已完成且可复盘”之一及首个关卡完成需求有效。`contract` / `mode` 等长期玩法分类仅保留设计空间，未实现前不得只靠改数据启用。

**任务对白分层字段 `mission_briefing`（可选）**：用于关卡入口反复播放的战前简报，与一次性 `get_conversation` 和结果型 `finish_conversation` 隔离。内容只能描述目标、路线、限制、撤离规则和已公开威胁，不应包含关卡中才揭示的伤亡、背叛、首领或结局。调度板任务不会回退读取 `get_conversation`，缺字段时显示“暂无任务简报”；既有委托副本为兼容旧数据，暂时按 `mission_briefing` 优先、`get_conversation` 回退。`tools/derive-task-catalog.js` 对 `$` 引用执行同等文本闭包校验，但不把对白本体写入 catalog。

**任务 `conditions` 字段（可选，2026-06-11 判定层共享）**：`[{type, params, target, label, sinceAccept?}]`——与成就共享 `ObjectiveEvaluator.rawOf` 的 9 类指标（枚举单源 `tools/lib/objective-types.js`，两 derive 共用）；`label` 必填（面板直显）；`sinceAccept:true` 仅限单调类型（killTotal/economyCount），AddTask 拍基线进 `requirements.condBase` 走窗口语义；derive-task-catalog build gate 全量校验（economyCount 白名单单源 / taskFinished 闭包+禁自引用 / 布尔型 taskFinished·itemOwned 的 `target` 必须=1（rawOf 返 0/1，>1 永不可达）/ itemOwned `count`≥1（count=0 时 containTaskItems 恒真=错误达成）/ chainProgress 引用须为**有序号链**且 `target`≤链最大 seq（无序号链永不写 `task_chains_progress`）/ **条件死锁=单调 AND-OR 不动点**——按运行时真实语义建模（`taskAvailable` 接取门控只查 `get_requirements`，链序号不约束完成顺序）：任务可完成 ⇔ get_requirements 全可完成 ∧ taskFinished 引用可完成 ∧ 每个 chainProgress 存在**任一** seq≥target 候选可完成（析取，环检测表达不了 OR）；基线集与带条件集之差 = 条件死锁，逐任务报阻塞条件；只证无结构性死锁不证可完成。回归矩阵：`node tools/test-derive-task-conditions.js`（23 合成用例）。与老字段（关卡/交物/持有/特殊）合取判定，缺省零成本。**运行态回包**：`taskDetail` 实时回 `conditions:[{label,cur,target}]` + 权威 `satisfied`（web 详情缓存只固化静态字段，conditions/satisfied/finishNavigable 在缓存命中时后台复查就地修补，防旧进度/按钮态永久陈旧）。设计：docs/任务成就-判定层共享-设计-2026-06-11.md。

`replayDialogue` 防剧透硬门控（服务端权威，AS2 `TaskPanelService.handleReplayDialogue`，不依赖前端隐藏按钮）：接取对话仅 active(`tasks_to_do`)/finished(`tasks_finished>0`) 才回，完成对话仅 finished 才回，否则回 `error:"locked"`（绝不吐对话本体）。web 渲染对话行经 `PanelTooltip.convertAS2Html` 真·标签+属性白名单清洗（DOM 重建，丢弃未知标签/事件属性，防 `$PC`→存档角色名等玩家可控输入造成 XSS）。图表视图同口径只画已接取节点、未接取详情遮罩（防剧透）。

派生时校验（失败 → build exit 1）：**闭包性**——任务的 `title/description/get_conversation/finish_conversation` 若值以 `$` 开头，该键必须存在于合并 `task_texts`（防 `$KEY` 缺失运行期显示原始键，亦为审计 Phase1 description 下沉前置门控）；dup-id 守卫；chain 序号无重复；多 placement 地图 NPC 必须用 `get_npc_hotspot` / `finish_npc_hotspot` 显式命中 registry。干跑校验：`node tools/derive-task-catalog.js --check`。
**进度叠加**（哪些已完成/进行中）不在本目录——走只读命令 `taskTreeState` 实时读 `_root.task_chains_progress`/`tasks_finished`/`tasks_to_do`（存档态可变，绝不缓存进目录）。详见 [task 系统 AS2 内存驻留审计](../docs/web-task-panel-WS6-事件日志任务树-设计-2026-06-09.md)。

### launcher/web 端 NPC 头像坐标 schema (Stage C 以后 hotspot-relative)

`launcher/web/modules/map-avatar-source-data.js`（手工维护 IIFE）每个 entry 不再带绝对坐标 `center/rect`，而是相对所属 hotspot 的 runtime rect 左上角偏移：

```jsonc
{
  "symbolName": "<XFL 头像 MovieClip 名>",
  "assetUrl": "assets/map/avatars/<symbolName>.webp",
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

### data/merc/pets.xml 战队分类

每个 `/Pets/Pet` 必须在 `Identifier` 后声明 `<RosterType>`，合法值为 `partner | pet | mechanical`。该字段是战队界面伙伴 / 战宠 / 机械分类的运行时权威；三类仍共享宠物池、槽位、出战配额和存档结构。

敌人属性中的 `魔法抗性/机械` 与 `魔法抗性/人类` 仅用于审计推导，优先级为机械、人类、其他归战宠。人工校对允许显式分类与推导不同。构建门禁 `tools/audit-pet-roster-types.ps1` 严格跟随 `data/enemy_properties/list.xml`：缺失或非法字段、损坏引用为错误；显式分类差异与 Identifier 未匹配为警告。

`PetCatalogLoader` 将 `rosterType` 投影到 `pet_lib` 和 `adopt_list`。类型化 `adopt_list` 请求可带 `rosterType` 与原始 `categoryIndex`，回包分类形状为 `{index,name,count}` 并带 `selectedCategoryIndex`；未传 `rosterType` 时保留旧兼容形状。

1. 确认数据类型对应的目录
2. 参照该类型现有文件的 XML 结构
3. 使用 UTF-8 编码，添加中文注释说明用途
4. 参阅 `agentsDoc/game-design.md` 确认数值平衡参考

