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
| `data/arena/` | 竞技场标准/隐藏卡与标准佣兵装备掉落 XML 真源、势力元数据 JSON 真源与关卡派生 roster |
| `config/` | 系统配置 |

大多数采用 **list.xml 主从模式**：

```
data/items/list.xml          → 引用 54 个物品分类文件 + item_sets.xml 套装中心表
data/enemy_properties/list.xml → 引用 14 个敌人定义文件
data/dialogues/list.xml       → 引用 16 个对话文件
data/environment/             → scene_environment.xml、stage_environment.xml、color_engine_preset.xml
data/stages/                  → 按地点组织的关卡数据
data/dictionaries/            → 材料/情报字典
data/intelligence/            → 按情报名称存放的 legacy txt 正文
data/intelligence_h5/         → 按情报名称存放的 H5 JSON 组件树正文
data/shops/list.xml           → 引用 data/shops/npcs/*.json（每个 NPC 一个文件）
data/arena/arena_config.xml   → 标准/隐藏挑战卡运行时真源
data/arena/arena_drop_rules.xml → 标准佣兵装备掉落、概率与玩家可见来源分类真源
data/arena/arena_factions.json → 势力 benchLevel/scale/enabled/units 手作真源
data/arena/meta_teams.json    → 从 data/stages/** 派生的 roster/merc 生成物
data/arena/arena_calibrated_rosters.json → 已完成人机门的精确怪物组合到标准卡档位目录
```

### GameStage 跨 SubStage 计时池

`data/stages/**/*.xml` 可在一个 `GameStage` 内声明会话级 `TimePools`，并由任意 `SubStage` 直接引用零到多个池。未声明 `TimePools` 的旧关卡保持原行为；计时状态不写存档或 `tasks_to_do`，离开、失败、完成、重开或返回基地时清空。

```xml
<GameStage>
    <TimePools>
        <TimePool>
            <Id>route_a</Id>
            <DurationSeconds>600</DurationSeconds>
            <DisplayName>章节 A</DisplayName>
            <TimeoutResult>FailStage</TimeoutResult>
        </TimePool>
    </TimePools>
    <SubStage id="0">
        <TimePoolRef>route_a</TimePoolRef>
        <!-- 其余关卡数据 -->
    </SubStage>
</GameStage>
```

- `Id` 必须匹配 `[a-z][a-z0-9_-]{0,31}`；每个 `GameStage` 最多 16 个池，每个 `SubStage` 最多同时引用 4 个池，定义必须至少被引用一次，引用必须已定义且同图不得重复。
- `DurationSeconds` 是 `1..3600` 的整数；`DisplayName` 为 1..32 字符，禁止首尾空白、控制符和 `|`；v1 的 `TimeoutResult` 只允许 `FailStage`。计时域禁止 `CaseSwitch`，避免运行时条件投影造成池身份漂移。
- 相邻或不相邻子图引用同一池都会延续剩余时间；未引用的中间图暂停该池。一个子图引用 A+B 时两池独立扣时、独立展示，任一到期即按 `FailStage` 裁决。
- 只在有效战斗帧按 30 FPS 扣时；暂停、对话和转场不计入。同帧先执行 `WaveSpawner.tick()`，已完成关卡时通关优先于到期。
- AS2 `StageTimePoolController` 是时间与失败裁决权威；Launcher 的 `T` 快车道只显示 keyed HUD。静态门为 `powershell -File tools/validate-stage-time-pools.ps1`，行为门为 `powershell -File scripts/run-stage-time-pool-tests.ps1`。
- 首批配置：`残垣断壁`前两图共享 600 秒、遇到键盘后停止；`核电站`四图共享 600 秒；`挑战战斗天才`单图 300 秒。

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

### 竞技场 P5 权威配置

- `arena_config.xml` 是标准卡与隐藏警报卡的运行时真源。`Cards/Card` 的 `id/index/countMin/countMax/levelMin/levelMax/exprTemplate` 和 `HiddenChallenges/HiddenChallenge` 的 offset、人数、mixed 要求与经济倍率由 C# `ArenaAuthorityCatalog` 启动期严格解析；损坏、重复 ID、倒置范围或模板与数字字段不一致会让竞技场 fail-closed，不回退 Web 硬编码。
- `arena_factions.json` 是势力卡手作元数据真源，schemaVersion 固定为 1；每个 faction 必须命中 meta roster，`benchLevel` 只能为正整数或 null，`scale` 只能为 `small|large|coalition`，`enabled` 为布尔，`units` 为 null 或不重复的 `兵种N` 白名单。`launcher/web/modules/arena-factions.js` 由 `tools/derive-arena-factions.js` 生成，禁止手改。
- `meta_teams.json` 与 `launcher/web/modules/arena-meta-rosters.js` 由 `tools/derive-arena-meta-teams.js` 从 `data/stages/**` 同步派生；`--check` 会 exact 比较 tracked 字节。release prepare 会先重建 meta/faction 投影，再重建 custom presets、unit catalog 和 parameter presets；任何 stale 输出必须非零失败。
- `arena_calibrated_rosters.json` 只承载通过机器完成门、低 timeout/error、side-swap 复核及明确人类锚点的**精确组合**，不把单元格边推断成势力常数，也不写 `benchLevel`。`active=false` 时必须为空且不影响旧抽取；`active=true` 时每条 roster 必须绑定标准 `tierId`、组合成员/参数顺序、来源单元格、样本与 timeout/error 审计、side-swap 状态、生产物理 profile 和 `catalogHash`。非人单位还必须形成 `requiredKnownEnemies` 闭包，未知图鉴不会投影给玩家。
- 正式启用只能由 `build-production-recommendation.js` 生成 `baseSha256 + replacementSha256 + dry-run diff + implementationClosure + rollback` 的 exact bundle，再由人类批准精确 `bundleHash` 后调用 `apply-production-recommendation.js`。apply 对 base/revision/消费者闭包做 CAS，启用后运行 Host/Web/文档门，任一失败恢复原始字节；禁止手抄组合、跳过验证或直接修改 Web 生成物。
- 运行时 snapshot 的 `arenaAuthority.sourceDigest` 覆盖上述 XML、meta-team JSON、faction JSON、calibrated-roster JSON 与 `data/units/units.json` 的原始字节；Host 还会以 unit ID + spritename 精确验证每个目录成员及 humanoid 分类。标准怪物卡命中标定目录时，Web 展示 snapshot 中的 canonical 组合并只回传 session `cardId/cardIndex/calibratedRosterId`；Host 按同一 session 与 tier 反查原始 roster，拒绝未知单位、伪造 ID、跨档位 ID 或同时夹带的 client roster。未命中时保留既有 roster 抽取路径；C# 继续重建经济、表达式与爬升池，AS2 在写入前独立复算。完整协议与验证入口见 [Launcher README](../launcher/README.md) 和 [testing-guide](testing-guide.md)。

### 竞技场标准佣兵装备掉落

`data/arena/arena_drop_rules.xml` 是 `_root.加载敌方人物` 标准佣兵分支的装备掉落与玩家可见来源分类真源；它不属于 `arena_config.xml` 的卡片、赛程与经济权威。`ArenaDropRulesLoader` 在启动 S9 严格解析后写入 `_root.竞技场掉落规则`，缺文件、未知字段、重复 ID、非法概率、槽位覆盖不完整或来源投影不完整都会终止启动，不回退代码内默认值。

- `Profile/Rule` 的物理顺序就是裁决顺序；命中 `stopOnMatch=true` 后停止后续规则。触发器与装备名单均按物品名称 exact 匹配，不做前缀、后缀或品类模糊扩张。
- `Drop` 表达逐件独立概率；`SlotLottery` 先按 `Choice.weight` 选槽位，再在该槽位的 `EligibleItem` 中按当前穿戴名称判定是否掉落。现役角斗规则冻结头/上装/下装/手/脚各权重 1、空结果权重 2，并保持武器 25%、被选中防具 100% 的旧语义。
- 仅 `standard_merc` 使用该目录。roster、自定义 PvE、mixed 与爬升模式继续显式清空掉落，不得因目录存在而获得标准佣兵奖励。
- 加载成功时，`ItemObtainIndex` 把每个可达装备投影为静态 `dropType="arena"` 来源记录，并保留规则级 `carrierScope`。共享 `TooltipComposer` 只显示两类稳定入口：`carrier` →“竞技场：携带该装备的佣兵”，`specific_carrier` →“竞技场：携带该装备的特定佣兵”。
- 物品 tooltip 不显示佣兵名单、项链条件或掉率；`arenaId/ruleId/triggers/chanceModel/conditionalChancePercent` 等结构化字段继续保留，供竞技场界面以后解释“特定佣兵”和概率明细，避免两处维护自由文本。

修改该文件、解析器、场景消费或来源提示时，固定运行 `node tools/validate-arena-drop-rules.js`、`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-arena-drop-rule-tests.ps1 -TimeoutSeconds 240` 与 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-boot-sequencer-tests.ps1 -TimeoutSeconds 240`；发布注入层时再运行 `scripts/compile_test.ps1 -Target publish -VerifySwf scripts/asLoader.swf`。Launcher release policy 同时把 XML 列为 required asset 并执行同一 validator，打包范围由 `tools/cf7-packer/pack.config.yaml` 的 `data/**` 覆盖。

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
| `ItemDataLoader` | `data/items/list.xml` | 并行加载 54 个物品分类文件与 `item_sets.xml`；合并数组附带中心套装元数据 |
| `ArenaDropRulesLoader` | `data/arena/arena_drop_rules.xml` | 严格加载标准佣兵装备掉落规则，并为 `ItemObtainIndex` 提供静态竞技场来源投影 |
| `EnemyPropertiesLoader` | `data/enemy_properties/list.xml` | 敌人属性（14 文件合并，按名称索引） |
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

### 实际命中终结 `<actualTerminal>`

`data/items/bullets_cases.xml` 的 `<attribute><actualTerminal>true</actualTerminal>` 是极少数“完成实际命中分类后立即终结目标”的声明式能力。`AttributeLoader` 会在 MovieClip 创建前把它投影为子弹的 `实际命中强制击杀`，因此普通显示子弹、透明弹和无 MovieClip 的 settlement bullet 使用同一权威；素材时间轴不得再重复声明该能力或用通用 `击中时触发函数` 模拟。

该能力仍执行暴击、通用分类、闪避/格挡与联弹分段判定，因此会消费这些分类器原本使用的随机数；这是从旧“伤害计算前无条件置零”迁移到 actual-only 合同的显式兼容边界。全段 MISS 只生成伤害数字；无敌、`man.无敌标签` 与 NPC 仍返回 `DamageResult.NULL`，均不得终结。至少一段真实命中才置目标 HP 为 0，并在护盾、纳米毒性、吸血、击溃、斩杀及普通扣血前结束。结果保留 actual 身份与空数字列表，使既有 `hit → kill/death → enemyKilled` 和命中后特效继续成立。

### 射线子弹 `<rayConfig>`

`data/items/bullets_cases.xml` 的 `<attribute><rayConfig>` 会由 `TeslaRayConfig.fromXML()` 解析，并自动把子弹标记为射线类型。`rayMode` 现支持 `single | chain | pierce | fork | flame`；`flame` 是连续喷火模式：每帧重扫沿线目标，以第 `pierceLimit` 个有效目标作为阻挡长度，`flameGrowSpeed/flameRetractSpeed` 控制当前长度追随目标长度，`flameTickInterval` 控制伤害脉冲帧间隔，`flameLifetime` 控制单发喷火束存活帧数。喷火常用的段数/预算字段：`flamePulseCount`（单发伤害脉冲段数）、`flameHotPulseStart/flameHotPulseCount`（热属性段窗口）、`flameHotDamageType/flameHotMagicType`（热段临时覆盖伤害属性）、`flameTotalHitBudget`（单发总伤害结算预算，0 为不限）、`flameMaxHitsPerTarget`（同一目标单发内最多吃几段，0 为不限）。`flameUseWeaponVelocity=true` 时，喷火束会按发射武器 `<velocity>` 缩放 `flameGrowSpeed/flameRetractSpeed`；`flameVelocityBase` 是基准速度，`flameVelocityMinScale/flameVelocityMaxScale` 是钳制范围，用于避免低速配置让火束完全爬不出去或高速配置退化为瞬时射线。`flameReuseMaxOriginDist` 控制同喷口连续火束视觉复用允许的起点偏移半径（默认 32px），只影响显示对象复用与淡出刷新，不改变命中扫描或伤害结算。

喷火视觉风格使用 `vfxStyle=flame_stream` / `vfxPreset=flame_stream`，常用字段包括 `rayLength`、`rayWidthFactor`、`damageFalloff`、`thickness`、`waveAmp`、`waveLen`、`waveSpeed`、`tongueCount`、`tipBloomScale`、`smokeColor`、`visualDuration`、`fadeOutDuration`。`rayWidthFactor>0` 时运行时走带宽射线碰撞，半宽由 `Z轴攻击范围 * rayWidthFactor * 0.5` 计算；视觉宽度仍由 `thickness/waveAmp` 等字段独立控制。

### 消耗品药效 `<effects>` 与持续效果域

`data/items/消耗品_药剂*.xml` 的 `<effects>` 按物理顺序执行。现有基础类型为 `heal / regen / state / purify / buff / playEffect / message / grantItem / global`；九龙批次新增四个封闭类型：

- `buffDomain domain="meal|enhancer"`：必须位于持续效果之前；移除同域旧药剂登记的 Buff，再登记本次 `buff`、`regen` 和专用 Buff 的真实返回 ID。`meal` 与 `enhancer` 各保留一个槽且可以并存，即时医疗效果不占槽。
- `resistanceBuff value duration buffId`：对 `魔法抗性.电/热/冷/波/蚀/毒/冲` 七个叶子路径施加同值增益；不得把 `魔法抗性` 对象交给普通数值 Buff。
- `toughnessBuff value duration buffId`：`value` 使用装备 XML 的 `toughness` 点数口径；运行时添加 `基础韧性系数 × value / 100`，不得对已含装备值的最终韧性系数再次乘算。
- `restoreToughness`：同时清零 `remainingImpactForce` 与 `impactDecayBaseForce` 并刷新派生显示；不改 `lastHitTime`，不撤销已进入的控制状态。

域注册表只保存 `BuffManager.addBuff()` 返回的外部 ID，不能保存 MetaBuff 内部 ID。完整参数、顺序与 Tooltip 约束见 [`data/items/消耗品_药剂.md`](../data/items/消耗品_药剂.md)。上述三个新战斗数值路径在 Flash 旅程通过前必须保持 `runtime-test-pending`。

### 礼包 `<rewardPack>` 与物品使用

`data/items/消耗品_礼包.xml` 是现役礼包目录；礼包必须声明 `type=消耗品`、`use=礼包`，并只在 `<data><rewardPack>` 描述领取内容，不再携带手雷投掷字段。`<mode>` 只允许三种值：`fixed` 逐项生成，`chooseOne` 按正整数 `<weight>` 选择一项，`independent` 按每项正整数 `chanceNumerator/chanceDenominator` 独立检定。每个 `<entry>` 必须有目录中真实存在的 `itemName`，并满足 `1 <= quantityMin <= quantityMax`；缺失物品直接删除，不得静默换成近似名称或货币。

礼包只能从角色构筑的背包总览显式“打开”。运行时先完成随机结果与 64 occurrence 待领取容量预检，再以同一事务消耗一个来源礼包、追加不可变领取批次、记录 `operationId` 回执并刷盘；未知写结果只按同一 `operationId` 查询，不重放打开。礼包产出若仍是礼包，只作为普通待领取物品交付，不递归自动打开。旧在线奖励按钮与 5 分钟任务已封存；圣诞树恢复旧系统“每次 Flash 运行可领五档”的会话语义，改用 `_root.帧计时器` 的本次运行帧时间，在 10–20、20–40、40–60、60–120 与 `>=120` 分钟五个窗口中分别幂等投送在线补给包Ⅰ–Ⅴ，并继续要求主线进度 `>28`。成功投送并强制存盘后，圣诞树必须用 strict `panel_request {panel:"loot",source:"reward_inbox",initData:<authority>}` 请求现役领取页；面板拒绝不回滚批次，玩家仍可从角色构筑的“待领取”入口继续。持久 `supplyKeys` 只保留当前进程 token 的最多五个窗口键，存盘切换不丢本会话幂等性，新运行首次成功投送时才以事务替换旧会话索引；token 的毫秒时间必须先拆为 AVM1 int32 安全段再编码，禁止直接对时间戳调用 `Number.toString(36)` 而把所有现代日期饱和成同一键。`#supplytime:<minutes>` 只调整该在线补给域的会话偏移，不改全局帧数、冷却或调度，也不清除本会话已经领取的档位。`node tools/validate-reward-packs.js` 固定校验 mode/字段形状、数量与概率边界、物品目录闭包、在线补给帧时间/五窗口/幂等探针闭包及旧手雷定义已迁空。

### 平衡记录 `<balance>`

`<balance>` 不是战斗数据源，也不得形成第二份人工数值。武器只记录 XML `<data>` 中没有的公式输入与最小展示门，不复制 `level/weight/defence/hp/mp/damage/power/interval`；药剂则允许同步器写入派生输出和 `marketPrice` 对账副本，但禁止手工修改。AS2 战斗逻辑不消费它；展示层只允许从严格验证的武器 profile 生成最小 `balanceSummary`，不能让 Web 自行读取审计原文或推断状态。

**枪械 / 武器**：尚未上线的契约统一为严格 `formulaFamily=weapon + schemaVersion=1`，不兼容此前平铺/v2 或 runtime SHA 开发草案。item 根 `<balance>` 只保留容器身份、数字 `workbookVersion` 和 `<profiles>`；完整 SHA 只在工具注册表、规则表与外部审计台账保存一次。`data/data_*` 每个静态形态都要有独立完整 profile，保存八个公式输入、`status/displayEligible/inputDigest/auditRef`，缺 profile 禁止回退基础形态。条款、证据、预算和可选短备注存入不由 ItemDataLoader 加载的 `tools/cf7-balance-tool/records/weapon-balance-audit.xml`，runtime profile 必须由台账机械同步并逐字段对账。完整 schema、digest 和施工流程以 `tools/cf7-balance-tool/docs/agent-balance-record-design.md` 为准，取值判据及条款 ID 以 `tools/cf7-balance-tool/docs/weapon-balance-rulebook.md` 为准。公式最高权威仍是 `0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx`。

**药剂 / 食品**：使用 `formulaFamily=potion + schemaVersion=1 + formulaVersion=2` 的提案记录。人工真源是 `records/potion-balance-plan.xml`；工具必须从实际 `<effects>` 重建输入，生成 `records/potion-balance-audit.xml` 和 item 根最小 `<balance>`，并对来源等级上限、全量覆盖、工作簿快照、input/source digest 做反向检查。当前工作簿尚未正式登记 v2，所有记录必须保留 `authorityStatus=workbook-registration-pending`，不得提升为确认值。公式、产品域、数值表和退出条件见 [`potion-balance-rulebook.md`](../tools/cf7-balance-tool/docs/potion-balance-rulebook.md)。

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

### 装备插件基础选档与确定性覆盖

`<stats><baseSwitch path="data.*">` 在 tier/强化结算后、任何插件尚未应用时读取宿主基础数据，只应用第一个命中的命名 `<value>`，无命名 `<value>` 为 default。它用于石英磨刀石这类“按改质前伤害类型补偿”的配额，其他插件的 `override` 不得反向影响其选档。`softOverride`、`override`、`lockOverride` 构成三层浅覆盖：前者覆盖宿主原值但让位于普通覆盖，后者在普通覆盖与 `merge` 后最终重申锁定值；因此低优先级暴击基线和高优先级物理锁定均不依赖插件槽遍历顺序。完整运算顺序、Tooltip 语义与 XML 示例见 `data/items/equipment_mods/README.md`。

近战切手技的运行时可配置面是武器 `data.switchstrike` 数值对象，现役字段为 `weightCoefficient` 与 `impactMultiplier`。插件通过 `merge` 写入，`SwitchStrikeCore` 以封闭形态表解释；XFL 时间轴只传定位器与形态名，禁止在 XML/XFL 重复公式或配置任意函数名。

`useSwitch` / `skillSwitch` 的无前缀 `name` 继续匹配宿主 `use` 与 `weapontype` 的联合集合。需要消除同名歧义时可写 `use:值` 或 `weapontype:值`：例如 `weapontype:手枪` 只命中精确子类，不会命中仅因 `use=手枪` 而共用装备槽的冲锋手枪和大威力手枪。`grantsUse` 同时进入无前缀集合与 `use:` 限定集合。Tooltip 必须隐藏内部限定符，显示为“装备类型：…”或“武器子类：…”。`stats.useSwitch.use` 分支除数值运算符外还可声明 `provideTags` 与 `requireTags`：前者仅在分支命中时提供结构，后者仅在分支命中时并入根层安装前置，并必须同时用于候选过滤、安装检查、缺失标签提示与拆卸依赖判定。

### 声明式子弹命中行为 `<hitBehavior>`

武器运行时数据可包含 `<hitBehavior>` 对象；插件通过 `<stats><merge><hitBehavior>...</hitBehavior></merge></stats>` 写入。`ShootInitCore.generateBulletProps` 将该对象透传到子弹，`BulletQueueProcessor.settleHit` 仅在实际伤害结算成功且至少一个分段真实命中时按封闭 `type` 分发；联弹分段模型中 `scatterMissCount >= actualScatterUsed` 的全 MISS/直感结果不得挂载行为。该字段表达游戏行为，不得与既有视觉命中特效字段混用，也不得存任意 AS2 函数名或可执行字符串。

当前正式类型为 `grayGooPrimer`（读取端仍接受旧名 `toughnessVulnerabilityPrimer`）。字段为：`stackGroup`、`profileId`、`decayDelay`（停火后开始衰减的帧数）、`decayInterval`（逐格衰减间隔）、`maxStacks`、`hitStacks`、`breakStacks`、`milestoneInterval`、`damagePerStack`（小数倍率）、`crumblePerMilestone`（击溃的原始百分比数值）、`executeAtMax`（斩杀的原始百分比数值）与 `sameSourceOnly`。同一 `stackGroup` 内按 `(sourceUID, profileId)` 保存候选，最终易伤只取完整候选的 MAX，不跨 profile 拼接字段。命中在伤害管线前预测是否跨过节点，临时配给击溃/斩杀并重选 `DamageManager`；`DamageResult.hasActualHit()` 在击溃、斩杀和后置叠层三处统一排除普通 MISS 与联弹全段 MISS/直感，只有至少一段真实命中才兑现节点并实际增加层数。

灰蛊裂隙弹使用 18 格、6/12/18 三个节点、每格 1% 全队易伤；冲锋枪/大威力手枪/普通手枪每次有效命中分别增加 1/2/3 格，真实破韧追加一次本 profile 等价命中。基础档仅由冲锋枪完整使用，参数为 `decayDelay=90/decayInterval=10/crumblePerMilestone=1/executeAtMax=8`；大威力手枪分支显式锁定为 `90/10/0.1/5`，防止继承冲锋枪的自建自吃补偿；普通手枪是 `150/15/0.3/8`。节点分别在衰减到 0/6/12 格时重新武装。`ToughnessBroken` 只表示非刚体真实破韧；刚体越阈仅清槽、不发布。层数变化发布 `GrayGooStacksChanged(target, stacks, maxStacks, profileId)`，并同步写入 `target.grayGooStackCount/grayGooMaxStacks`。`useSwitch.merge.hitBehavior` 是深度 merge；追猎射击的六个发射点也必须从两把手枪属性透传该对象。

### 装备插件格展示词典

`data/items/equipment_mods/*.xml` 的插件定义是档级、用途与定位的业务元数据单源。每个 `list.xml/<items>` 子文件根层必须显式声明 `<modGrade>low|medium|high|special</modGrade>` 与 `<catalogScope>armor|firearm|blade|fist|universal|underbarrel</catalogScope>`；文件名前缀只服务人类导航，运行时禁止据此推断。`catalogScope` 只用于 Web 目录分组，精确安装权限仍由每个 `<mod>` 的 `use/weapontype/excludeWeapontype` 与 `EquipmentUtil` 决定。

`data/items/equipment_mods/ui_presentation.xml` 是上述 ID 的受控标签/色号词典，以及插件格角色→符号、`tag`→默认角色的展示词典；它不得重新分配单个插件的档级或目录用途。`EquipModListLoader` 并行加载词典与子文件，向 `EquipmentUtil.modDict` 投影 `modGrade/catalogScope/uiGradeLabel/uiGradeColor/uiScopeLabel/uiRole/uiRoleLabel/uiSymbol`。角色符号采用 `形状-solid|outline` 受控 token；单个插件仅在 `tag` 默认角色不准确时声明 `<uiRole>` 覆盖，禁止填写任意 Unicode/HTML 符号。`EquipmentTuningService.modCandidates[]` 暴露档级/用途/定位/受控符号供候选树和紧凑瓦片展示，未知符号由 Web 白名单回退；`InventoryPanelService` 对松散插件材料附加 `modMeta`，但 `availabilityCode` 仍是安装可用性的唯一权威。

`data/items/收集品_材料_插件.xml` 与 `收集品_材料.xml` 只维护库存、经济、图标和说明，不复制档级/用途/定位。构建门 `node tools/validate-equipment-mod-ui.js` 固定校验 105 个 mod、四档、六种 scope、全部现役 `tag`/角色/符号，并要求每个 mod 名称在 `data/items/list.xml` 引用的物品文件中恰好出现一次；其中插件材料文件的 101 个条目必须全部映射到 mod。特殊档原图错色视为美术流程问题，不参与运行时取色或兼容逻辑。

### 材料档案 authored catalog 与 legacy 字典

`data/dictionaries/material_catalog.xml` 是全量材料档案顺序、base type、受控直接用途、旧 UI 可见性与编辑摘要的 authored SOT。根节点 schemaVersion 固定为 `1`，并直接包含重复的 `<DirectPurpose>` 与 `<Material>`；加载方必须把 XMLParser 可能产生的 scalar/Array 两种形状统一归一为数组。

- `<DirectPurpose>` exact 子键为 `id/label/order/consumerEvidence`。当前受控 registry 包含 `system:equipment_tuning / 装备改装 / 0 / EquipmentTuningService` 与 `system:infrastructure_upgrade / 基建升级 / 1 / InfrastructureUpgradeUI`。未知 ID、重复 ID/order、非连续物理顺序或 consumer evidence 漂移均失败关闭。
- `<Material>` exact 子键以 `Name/typeId/legacyVisible` 开头；`typeId` 只允许 `equipment_mod|food|general`。只有 `legacyVisible=true` 才必须带 `legacyInformation`，反之必须省略；`authoredDirectPurposeId` 可重复且必须命中同文件 registry。字段缺失必须保持省略，禁止序列化为字符串 `undefined`。
- `<Material>` 物理位置就是 `archiveOrder`，不在 authored XML 重复保存第二个 order 字段。初始迁移严格保持旧字典 58 项原序，再追加 `data/items/list.xml` 中尚未出现的 166 项材料载入序；当前闭包为 `224/224`、连续 `0..223`。新增、删除或重排都必须先显式修改 catalog，不能由 Web、对象枚举或本地化名称自动决定。
- `equipment_mod` 当前精确等于 `data/items/equipment_mods/list.xml` 的 105 个 mod identity；食材来自 `消耗品_材料_食材.xml` 的 45 项，其余 74 项为 `general`。105 项装备改装用途由 runtime mod metadata 机器派生，不在 catalog 重复 authored；只有 `强化石 / 二阶复合防御组件 / 三阶复合防御组件 / 四阶复合防御组件 / 墨冰战术涂料 / 狱火战术涂料` 六个经现役 consumer 证明的非 mod-metadata 例外 authored 同一个 `system:equipment_tuning`，且不得因此伪造 mod facets 或 `equipment_mod` type。
- `system:infrastructure_upgrade` 的材料集合只以 `data/infrastructure/infrastructure.xml` 中各级 `<Material><Name>` 为真源；当前为 67 个需求 occurrence、21 个 unique material identity。catalog 中这 21 项的 `authoredDirectPurposeId` 只是由 generator exact-check 约束的分类投影：集合必须与 XML 去重结果完全相等，所有 identity 必须命中材料 exact-set；连同装备改装六例外，当前 authored direct-purpose refs 总数为 27、registry 总数为 2。`flashswf/UI/平板电脑界面/LIBRARY/基建内容整体.xml` 只作为 `InfrastructureUpgradeUI` consumer evidence。sidecar 当前 schema 为 `cf7.material-dictionary-generated.v2`、producer 为 `material-catalog-producer.v2`；其顶层 `infrastructure` exact 为 `{path,consumerEvidencePath,materialOccurrenceCount,materialCount}`，并把两个输入的 digest 纳入闭包。
- 含该 direct purpose 的 v2 `materialDetail` 条件增加 `infrastructureUses[]`；其他材料及历史不含该 registry 的 v2 response 必须省略此键。项目 exact 为 `{infrastructureName,projectOrder,currentLevel,maximumLevel,levels}`，等级 exact 为 `{levelIndex,targetLevel,required,owned,missing,status}`，其中 `status` 只允许 `completed|current|future`。配置与物理顺序在 catalog snapshot 时从已就绪的 `_root.基建系统.nameList/dict` 冻结，缺失或不闭合时局部失败关闭；`levelIndex/targetLevel=levelIndex+1` 只认 `Level[]` 数组位置，不信任历史 XML `id`。详情读取 live `infrastructure[name]`，只投影已有自有键的已发现项目；未发现项目不得泄露名称。`owned` 沿用材料 snapshot，完成级 `missing=0`，当前/后续级为 `max(required-owned,0)`。Web 用这些数据替换重复的泛化“基建升级”行，显示逐项目、逐等级需求与缺口；仍为纯只读信息，不提供“前往基建”。
- 配方 category 的 authored order 仍只来自 `data/crafting/list.xml` 的物理 `<list>` 顺序，catalog 不复制第二真源。生成 sidecar 会绑定并列出该顺序，运行时 loader 必须在 keyed merge 前保存它。

`material_dictionary.xml` 现在是只投影 `legacyVisible=true` 的 `{Name,Information}` generated compatibility artifact；当前 58 条摘要、顺序和历史末尾无换行字节保持不变。`material_dictionary.generated.json` 是 manifest-last 审计 sidecar，绑定 generator 版本/哈希、全部逻辑输入、source digest、catalog/type/purpose/category 计数与 legacy 输出 SHA-256。

```powershell
# 只有维护者明确接受 generated diff 时才写；依次原子替换 dictionary、sidecar。
python tools/derive-material-catalog.py derive

# 发布、CI 与日常验证只执行纯读 exact-byte 检查，stale 时非零失败。
python tools/derive-material-catalog.py --check
python tools/test-material-catalog.py
powershell -ExecutionPolicy Bypass -File tools/test-material-catalog-release-policy.ps1
```

producer 对材料 exact-set、重复/未知 identity、未知 type/purpose、缺 legacy summary、legacy 58 前缀/摘要字节、mod/食材分类、六例外、基建 `67 occurrence / 21 unique` exact membership、category order、双次确定性与 tracked stale 输出全部 fail closed；focused test 另把初迁移的 `58+166` 具体顺序钉死，并证明后续非 legacy 条目的显式 authored 重排会按 catalog 物理序保留而不被 manifest/名称悄悄重排。任何接受的重排都必须同时审阅 catalog diff、更新迁移 ratchet 并显式 `derive`。producer 不解析自由文本生成用途，也不把动态来源回写摘要；发布流程不得先运行 `derive` 来掩盖 stale authored/generated diff。

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

#### 近战长枪联弹约束

`<use>长枪</use>` 且 `weapontype=近战|压制近战` 的武器，每个有效 `data*` 配置在继承基础 `<data>` 后，只要 `split>1`，有效 `bullet` 必须精确为 `近战联弹`。`data_fire*` / `data_ice*` 等变体缺失 `split` 或 `bullet` 时按基础配置继承后再判定。

该约束保证子弹工厂只创建一个联弹结算对象，避免 `近战子弹 + split=N` 被展开成 N 个独立对象、逐对象初始化并结算淬毒。它只把同一目标的一次多段命中从逐段满额毒收敛为一份满额毒，不改变 `近战联弹` 现有 `FLAG_NORMAL` 所对应的 100% 单次毒系数。静态门：`node tools/validate-melee-longgun-chain.js`。

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

### 怪物头像 Pilot 审计 schema（非生产）

`tmp/portrait-pilot/*/source-choice-data.json` 使用 `cf7.enemy-portrait-source-choice-candidates.v1`。每行键为 `portraitRef::source`，每个 duplicate/conflict 来源使用由 `portraitRef + swf + symbolName + orphan` 派生的稳定 `sourceCandidateKey`；来源候选仍是同一身份的替代真源，不是 `variantKey`。可定位候选绑定 `rootCharacterId / renderCharacterId / renderStrategy`、FFDec XML/GIF 与代表帧 artifact；无 symbolName orphan 固定 `renderable=false / unrenderableReason=orphan_without_symbol_name`。

人类导出 `cf7.enemy-portrait-source-choice-decisions.v1`：每行 exact `{status,sourceCandidateKey,notes,updatedAt}`。`selected` 必须绑定一个 `renderable=true` 候选；`manual_maintenance` 必须令 `sourceCandidateKey=null` 且备注非空。验证回执为 `cf7.enemy-portrait-source-choice-receipt.v1`，不写生产资产，选中项后续仍投影为 `portraitRef + default`。

已由人类确认的换皮复用使用 `cf7.portrait-pilot-identity-alias-receipt.v1`。回执必须同时绑定来源身份的人审决定、目标身份已验证的 framing-guidance 与无模型高分辨率 render，记录稳定 `sourceReviewKey / targetReviewKey`、复用原因、目标 frame/crop、显式排除项和 controller/artifact 摘要；来源与目标不能相同，目标必须已有冻结的人类选择。该回执只证明后续 consumer 可把来源 `portraitRef` 显式指向目标身份，固定 `productionReady=false / productionWrites=false`，不得直接修改 XML、生产 manifest 或把未列入复用关系的来源异常一并吞掉。

`tmp/portrait-pilot/*/representative-closure.json` 使用 `cf7.enemy-portrait-representative-closure.v1`，只汇总冻结的人审回执、高分辨率人工框选直渲染和异常队列摘要。`representative_visuals_resolved_source_choices_pending` 要求代表集 12/12 eligible 有可追溯视觉结果，同时 3 个 source blocker 继续不可签名；该状态不授权全量 campaign、consumer resolver 或 promotion。

`tmp/portrait-pilot/*/portrait-inventory.json` 使用 `cf7.enemy-portrait-campaign-inventory.v1`。先逐 consumer 应用敌人可选 `portraitRef` / 战宠可选 `PortraitRef`，默认分别取 enemyId / `Identifier`，排除战宠占位 Identifier `默认`，再按最终 `portraitRef` 合并 `enemyIds / petIds / petIdentifiers`。每个 identity 记录 `variantKeys`、原始 `sourceClassification`、`sourceResolution=unique|human_selected|manual_maintenance|source_choice_required|missing`、全部来源和唯一 `selectedSource`；duplicate/conflict 的 `human_selected` 必须绑定冻结的 source-choice receipt，仍不生成产品 variant。`inventoryDigest` 覆盖完整 inventory，`sourceDigest` 覆盖 consumer XML、资产映射、选源决定/回执、代表集 closure 和 controller 源码。

全量有界 shard 继续使用 `cf7.enemy-portrait-feature-refinement-candidates.v2 / P3_FEATURE_REFINEMENT`，并增加 `sourceEnvelope.mode=bounded_full_campaign_shard` 与 `campaign`。`campaign` 固定记录 inventory digest、确定性选择策略、shard/source-group 大小、已选 identity、排除集合、`resolutionAnomalies` 和预期 A/B job 数；review key 仍为 `portraitRef::default`。可运行行必须精确命中 linkage 根首帧唯一命名 `man`，`linkage_root_fallback` 在 campaign 中非法。`unclassified` 只表示由视觉模型从像素推理人形头部或非人身份特征，不允许按文件名或几何中心猜测。当前 profile 的高分辨率合同为最小 1024 真源裁切、最多 4096 保留母版、最大 16384 中间全帧；它不授权生产写入。

没有 ExportAssets linkage、但能从 FLA/XFL 装载时间轴与 SWF `PlaceObject` 的帧号及 twip 平移精确对应到怪物根时，使用 `cf7.portrait-pilot-xfl-embedded-source-closure.v1`。该闭包必须继续定位根首帧唯一实例名 `man` 并直接渲染它，记录 XFL/SWF 双映射和 receipt；外层怪物根、血条/等级层和 root fallback 均禁止。若素材只存在内部零件命名空间、没有可实例化敌人根，则不得把零件或相似单位头像冒充来源。

campaign profile 的几何合同还必须满足可实现性不等式：对每个 framing mode，`minimumRenderedFeatureLongAxisOccupancy` 与 `minimumRenderedFeatureShortAxisOccupancy` 均不得大于 `1 - 2 × mustIncludeSafeMargin`。原因是 `mustIncludeBox` 必须包含 `featureBox`，而 crop 又在 must-include 外保留该安全边距；超过这个上限时任何模型坐标都无法通过。该矛盾必须在 `prepare-shard/check-shard` 阶段拒绝，不能消耗模型重试后再发现；失败 profile 与 attempt 只作工程负例，不进入人类偏好 atlas。

人审反馈校准的当前累计版本为 `cf7.portrait-pilot-human-feedback-calibration.v9`，并保留 v2–v8 控制器闭包供历史报告复验。它绑定原 `review-data`、完整 decisions、human-review receipt、已验证 framing-guidance、确定性重渲染、方向修正与 supersession 证据，并保留原始备注、真实框选几何和扩容估算。当前闭包为 203 条当前人类偏好（86 pass / 116 adjustment / 1 source）和 112 条按 `reviewKey` 确定性去重的几何框选；内部主体 17 项最终为 11 pass / 6 guided adjustment，`敌人-dude` 的旧 C06 `wrong_subject` 只保留为负例，后续 C03 pass 是唯一当前决定。`adaptiveScaling.humanReviewPageLimit` 继续为 `null`；最近 35 个同类首轮身份为 27 pass / 8 revision，在 `expectedRevisionBudget=6` 下下一批建议 26 项、预计复议 `5.942857`，不能继续沿用上一轮 96 项估计。身份规模调整不自动提高进程并发：selection-only 当前基线 Luna Max / Fast6，精确 localization 为 Luna Max / Fast3，两者单进程 600 秒；并发 8 未授权。

累计偏好图当前使用 `cf7.portrait-pilot-human-preference-atlas.v9`：在 v8 完整图后追加 17 项最终人类接受面板，闭合 203 条当前标签、112 条框选几何和 C06→C03 supersession 负例。v8 的 compact retrieval 只覆盖 186 条旧状态，v9 manifest 已移除 `modelAtlas / modelAtlasRetrieval`，禁止继续发送该过期紧凑图；下一次模型施工前必须从 v9 完整 atlas 重新确定性派生 compact retrieval，并再次证明 patch 严格减少、当前候选与历史偏好分开发送以及父 atlas/controller/artifact 哈希闭合。

最终来源排除使用 `cf7.portrait-pilot-source-exclusion-closure.v1`，只允许把 inventory 的真实 missing 集合与运行时可实例化证据逐项对账。当前 221 个 consumer identity 中 219 个有来源；`敌人-Serpent` 只有 enemy property 与 save-repair allowlist，`units.json`、`asset_source_map.xml`、FLA/SWF ExportAssets 均无可实例化敌人根，FLA 中 `Serpent/*` 仅是 ArmsArius 使用的内部肢体零件；`敌人-不知火舞` 有“不考虑实装”注释且命名素材只位于 `flashswf/unused`。两项均固定为“实现前排除、未来实装后重新做来源与人审”，不得复用 ArmsArius 或 unused FLA 冒充成品。该闭包只把 `actionableMissingSourceCount` 降为 0，仍固定 `productionReady=false / productionWrites=false`。

缺失命名 `man` 的来源救援使用 `cf7.enemy-portrait-internal-subject-rescue-candidates.v1`。每个 `reviewKey=portraitRef::variantKey` 必须绑定怪物 linkage 根、精确 SWF/XML、内部 `DefineSprite` 的 sprite/frame、分层复杂度、显示路径与预览 artifact；复杂度固定为 `candidate_recall_prior_only`，已知 UI 路径硬排除，根 MovieClip fallback、提前矢量导出和生产写入均为 false。Luna A/B 输出 `cf7.enemy-portrait-internal-subject-rescue-selection.v1`：逐行闭合 `select|none`、候选白名单、`subjectLikeness`、连贯单位、UI/特效/武器否定标记、1–5 个可见身份特征、置信度与理由；模型报告 `cf7.enemy-portrait-internal-subject-rescue-model-report.v1` 必须保留不同 PID/role prompt、进程退出与 artifact，并固定 `automaticPromotion=false`。人审输入为 `cf7.enemy-portrait-internal-subject-rescue-review-data.v1`，不得应用模型预选；最终 `cf7.enemy-portrait-internal-subject-human-decisions.v1` 要求每个身份显式选择白名单 candidateId 或 `none + null`，同时绑定 source/manifest/model/review digest。该人工决定只冻结内部主体 sprite/frame，仍不授权 SVG、头像构图或 production promotion。

若更晚人工复确认需要替换同一 canonical 内部主体决定，旧批次不得假装仍指向当前文件。必须保留字节完全一致的旧决定归档，并用 `cf7.enemy-portrait-internal-subject-reconfirmation-receipt.v1` 同时绑定 `decisionsBefore`、新 canonical、归档副本、旧/新 candidateId 和未变更行数；后续反馈闭包只允许对该精确路径做哈希等价 supersession。当前 `敌人-dude` 为 C06（仅下肢）→ C03（完整紫色人形）的实证；旧 C06 继续作为 negative evidence，但只有 r194 C03 pass 可进入 production。

缺失 `man` 的后续来源解析按“外围根帧只作身份参考 → 内部 MovieClip 分层召回和视觉对应 → MovieClip 全失败后才检查根帧实际放置的 Graphic”执行。复杂度只能提高召回率；多模态判定至少要确认候选与参考主体对应、构成连贯可识别单位并排除 UI/武器/特效。Graphic 不得通过全库裸 Shape 相似度猜测，必须绑定根帧 `DOMSymbolInstance/PlaceObject` 路径、帧号与矩阵，并以编译 Shape/连通主体证据复核后送真人验收。定位适配器允许在人工决定之后拒绝“近乎纯色且近满填充的实心矩形”这一客观非主体类型，但不得据此自动采用 Luna 候选；必须用单项复核器保留其余决定并要求真人重新点击。

锁帧定位的方向输出使用 `cf7.portrait-pilot-feature-selection-orientation.v2`。它在原 `featureLabel / framingMode / featureBox / mustIncludeBox` 之外逐行闭合 `orientationAction=keep|flip_x`、`orientationReason` 与 `orientationConfidence`；当前 canonical 方向为主体朝右。坐标始终属于未翻转的锁定候选，`flip_x` 只能由版本化 renderer 在 crop 后、512/80/48/32/WebP 派生前执行。方向渲染仍使用 `cf7.portrait-pilot-render-report.v4`，但必须增加 `renderer.orientationPolicy`、逐行方向字段、`orientationSummary`，并同时绑定基础 renderer、版本化 wrapper 和模型报告 artifact；A/B 可各自决定方向，分歧不得静默合并。A/B 方向一致也不等于方向正确：若人类证明源图已朝 canonical 方向而两路仍共同 `flip_x`，后续反馈必须记录为 `model_flip_false_positive`。ArmsArius `e19-c01/f1` 是当前实证，r129 的二次镜像只恢复原方向，不能反推源图本来朝左。

`wrong_pose` 人工重选帧数据使用 `cf7.enemy-portrait-frame-reselection-candidates.v1`，决定与回执分别使用 `cf7.enemy-portrait-frame-reselection-decisions.v1` / `cf7.enemy-portrait-frame-reselection-receipt.v1`。数据必须精确绑定父 candidate/model/render/review/decisions/human receipt、所有 PNG/SVG 候选和 reviewer 闭包；父轮所选 candidateId 进入 `rejectedCandidateIds` 并在 UI/verifier 双重禁选。`selected` 决定绑定 candidate PNG hash、SVG hash 与 frame；`expand_search` 必须清空候选并写备注。若扩帧后由人类指定 `动作标签 → 库元件 → man`，`prepare_action_frame_reselection.py` 必须先验证扩帧回执，再把 FLA 标签层的动作帧与人物层同帧 `DOMSymbolInstance[name=man]` 对齐，并以 SWF XML 的 `FrameLabelTag + named placement + DefineSprite` 独立复核角色 ID 和帧数；数据新增绑定 FLA/SWF/XML、FFDec 版本/命令、动作路径及全部旧候选，旧候选整组否决时须全部进入 `rejectedCandidateIds`。禁止只信 FLA 库名、退回首帧 `man`/linkage root，或复用旧几何。回执只接受人工帧选择，固定 `modelGeometryDiscarded=true / localizationRerunRequired=true / productionWrites=false`，不能把新帧与旧 featureBox 拼接。

维护者给出“动作状态 + 精确内部库元件 + 内部帧”时，可由 `prepare_exact_action_frame_directive_v1.py` 处理没有实例名 `man` 的内部时间轴，但这不是一般性放宽。controller 必须从 linkage root 同时验证 XFL 动作标签起帧、该帧的唯一目标库元件、库元件到 SWF `DefineSprite` 的映射、SWF `FrameLabelTag` 起帧、XFL/SWF 内部总帧数一致和目标帧范围，并绑定 exact PNG/SVG 与全部旧候选；任一映射不唯一即 fail-closed。后续 `prepare_frame_reselection_localization_directive_v2.py` 仍输出标准 P3 manifest/localization view，只在 `intentPolicy.orientationDirective` 记录 `source=verified_human_exact_action_frame_directive`、`action=keep|flip_x`、`applyAfterOriginalSpaceCrop=true`。人类方向不得被 Luna A/B 共识覆盖；`cf7.portrait-pilot-human-orientation-conformance.v1` 必须绑定 manifest/model/render 与 controller，证明 proposal、independent-review 和 renderer 均服从该动作，固定 `productionWrites=false`。

真人选帧后的定位适配仍复用标准 P3 candidate manifest、`cf7.portrait-pilot-localization-views.v1`、方向模型报告与 render report，不引入可绕过验证的新 schema。`prepare_frame_reselection_localization_v1.py` 的输出必须逐项绑定已验证重选回执、所选 candidate PNG/SVG、精确 SWF 帧、控制器和累计 `humanPreferenceCalibration`；唯一 review row 必须与 receipt 的 `reviewKey/candidateId/frame` 一致，并写明 `oldModelGeometryConsumed=false`。定位 view 只从所选高分辨率帧生成，旧 proposal/independent-review 的 `featureBox/mustIncludeBox` 不得进入新 manifest、prompt 或 renderer。

人类明确“当前帧可用，问题仅是黑底需转透明”时，不得伪造 `wrong_pose` 换帧；独立后处理使用 `cf7.enemy-portrait-black-matte-candidates.v1`，决定与回执分别为 `cf7.enemy-portrait-black-matte-decisions.v1` / `cf7.enemy-portrait-black-matte-receipt.v1`。数据必须绑定父 candidate/model/render/review/decisions/human receipt、proposal/independent-review 的原始 4096px supersample、源 SVG、版本化 controller/reviewer 和每个输出 hash。当前 v1 公式固定为 `v=max(R,G,B)/255; m=v^gamma; A'=A*m; RGB'=RGB/m (m>0)`，只能使用记录的 gamma 候选，在 4096px 层处理后以 LANCZOS 派生 512/80/48/32；逐候选必须记录黑底预乘 RGB 的 mean/max absolute error，最大值不得超过 `2/255`。人类 `selected` 决定同时绑定 candidateDigest、4096px 与 512px hash；`refine` 必须清空候选并填写调参备注。该支路固定 `currentFrameRetained=true / noModelCall=true / productionWrites=false`，人审通过也不等于 production promotion。

人工先框选再改朝向使用 `cf7.portrait-pilot-guided-orientation-render-report.v1`。它必须同时绑定原 human-review receipt、framing-guidance receipt 和 `cf7.portrait-pilot-human-framing-render-report.v1`，只允许对冻结框选的高分辨率 supersample 执行明确人工备注授权的 `flip_x_after_human_crop`；重新派生 512/80/48/32/WebP，并以最终 master 对人工框选 master 的水平镜像做预乘 RGBA MAE。方向变换不得退回模型初框，不重复计算一条人类 adjustment，也不授权生产写入。

视觉校准派生 shard 不改变候选身份或模型 schema，而是在 `sourceEnvelope.humanPreferenceCalibration` 增加人类偏好图谱。历史 `cf7.portrait-pilot-human-preference-atlas.v1..v7` 依次绑定动态多轮 receipt、guided orientation、supersession 与分阶段并发；当前 v8 再追加最新五条 pass。`coverage.statusCounts`、`passAnchorCount / guidedCorrectionCount / orientationOnlyCorrectionCount / guidedOrientationCount / anomalyCount` 必须逐键闭合；更晚的人类决定构成当前状态，被取代的错误决定只能作为单独的负例证据可视化，不能继续计入当前标签。guided orientation 只替换同一 guided correction 的最终图，不能把同一 adjustment 重复计数；`source / wrong_pose / wrong_subject / variant_mismatch` 也不能丢弃。atlas 区域不是候选，不得提供当前行 candidateId 或坐标，也不构成模型训练声明。

当完整 atlas 的纵长视觉输入造成明显超时或注意力稀释时，可由版本化 compact controller 派生 `cf7.portrait-pilot-model-atlas-retrieval.v1..v3`。它不得删除或改写完整 atlas 闭包：全部原始 receipt/render/controller artifact、当前累计标签统计、supersession 证据和 source digest 继续保留；新增 `modelAtlas` 只作为单次模型调用的确定性检索视图。当前 v3 规则固定为“全部 pass 锚点 + 最新已解析人审状态的 adjustment + 全部 anomaly + superseded negative evidence + 全量标签聚合统计”，并要求 `latestResolvedStateIncluded=true`。`modelAtlasRetrieval` 必须绑定父 manifest、最新回执、完整/紧凑 atlas 尺寸与 32×32 patch 计数，证明 patch 严格减少、示例不是当前候选、完整 atlas 不随每个模型请求重复发送、`productionWrites=false`。r118-v2 绑定 144 标签，将 20,709 个 patch 减为 6,313，并确定性选择 45 个 review key。运行时附件 1 必须是脱离历史合成图的当前四行候选，附件 2 才是该检索视图；不得把一个角色切成头/身多个无上下文碎片来规避视觉输入限制。

两阶段 campaign 的逐行锁帧使用 `cf7.portrait-pilot-selection-lock.v1`。它必须同时绑定候选 manifest、完整 A/B model report、controller 与每个锁定候选 artifact；确定性规则顺序固定为“非 `none` 风险标记更少 → confidence 更高 → proposal 稳定并列规则”。锁帧只接受 candidateId，不接受第一阶段的 feature/must-include 几何，也不得读取当前留出集真人目标坐标。第二阶段观察窗使用 `cf7.portrait-pilot-localization-views.v1`：逐行绑定 selection lock、源 review-data、所选 `sourceHighResolution`、候选 hash、真实像素裁切和最多 2048px 的 `0.1` 归一化网格图；`normalizedCoordinatesMatchCandidate=true`、`humanTargetGeometryExcluded=true` 与 `productionWrites=false` 缺一不可。localization 模型只能沿用锁定 candidateId，最终仍需独立 A/B、确定性高分辨率 render 与真人 reviewer。

若完整第二阶段运行失败，但每个 role/batch 的 attempt-1 最终消息均已 transport-complete、schema-valid、锁定 candidate 闭合，且拒绝原因只有最终 feature occupancy，可用 first-answer recovery 生成 `cf7.portrait-pilot-feature-model-report.v1` 的受限人审输入。控制器必须按最早首答确定性取证，禁止按结果挑选；保留 `strictFeatureOccupancyAccepted=false`，逐项列出 occupancy violation，并区分 `fullProcessExitAndOrphanEvidenceAvailable` 与已绑定的部分进程证据。该报告只能供版本化 human-review renderer 生成真人候选；不得冒充严格模型运行成功、不得自动接受艺术结果，也不得改变全局 profile。r121 的实证为 12/12 首答、24/24 锁帧、23/24 方向一致，7 个 role-row / 5 个 identity 只因 occupancy 进入人审，且 3/12 缺完整进程退出证据。

标准高分辨率渲染触发 MAE 失败后，隔离诊断使用当前 `cf7.portrait-pilot-feature-fidelity-diagnostic.v2`，历史 v1 只保留复验。诊断必须覆盖当前 shard 的全部 proposal/independent-review 路径，绑定 manifest、model report、基础 renderer、alpha policy、任何 occupancy human-review recovery 与版本化诊断 controller，逐行保留真实 MAE、半透明占比、实体核心 IoU、重心距离和是否满足表示差条件；状态固定为 `diagnostic_only / productionReady=false`。诊断只负责定位差异，不能自行放宽全局 MAE，也不能替代后续 render report 或人审。

若超限不是二值 GIF alpha 表示差，只允许额外生成 `cf7.portrait-pilot-near-threshold-rasterization-evidence.v1`。它必须精确绑定 `reviewKey + candidateId + frame + roles`，全局 MAE 仍为 8，单行只允许不超过 8.25，并同时满足 alpha MAE≤2、alpha bbox 坐标差≤1px、alpha≥128 核心 IoU≥0.98、归一化核心重心差≤0.002、双向 1px edge recall≥0.99；所有阈值和真实值写入 report。该证据只证明矢量/栅格形状对应并允许送真人评价，不证明像素门全局通过或艺术接受。r124 只绑定独狼 `e22-c01/frame 1` 的 A/B 两路。

高分辨率报告仍使用 `cf7.portrait-pilot-render-report.v4`。默认每行必须通过绑定候选回缩后的预乘 RGBA MAE；若 FFDec GIF 的二值 alpha 无法表示精确选帧 PNG 的源半透明，报告可增加 `fidelityComparison.representationException`；若使用上述近阈值证据，则必须在 `fidelitySummary.exceptionPolicy/exceptionRows` 逐项复制精确 binding、阈值和实测形状指标。first-answer occupancy 人审恢复必须另写 `occupancyRecoverySummary`，只允许模型报告中已列明的 role-row，其他行仍走严格 occupancy。精确帧像素量超过 Pillow 默认阈值时不得设为无限；当前适配器把轴向上限钳到 `maximumSourceFrameDimension≤16384`，另以 `maximumSourceFramePixels=min(maximumSourceFrameDimension², 240,000,000)` 约束面积；`renderer` 记录 `maximumSourceFrameDimension`、`maximumSourceFramePixels` 与 `pillowDecompressionBombLimit`，基础 renderer 调用期间还会临时包住共享 `Image.open`，在 `.convert()` / `.load()` 前按图像头尺寸拒绝超限帧，并在 `finally` 恢复 opener 与 Pillow 阈值。所有例外都只证明候选对应并允许打开真人页，不是艺术通过、全局阈值放宽或 production promotion；r125 的 48 行中 41 行严格 occupancy、7 行精确人审 occupancy 恢复，46 行主 MAE、2 行独狼近阈值对应。

### 共享头像资产（通用 promotion 包 / Team 与 Arena 消费者）

敌人 consumer 的默认 `portraitRef` 是 `data/enemy_properties` 中敌人节点本身的稳定名称；只有多个 consumer 明确共享同一身份时，才用可选 `<portraitRef>` 覆盖。战宠同理以 `Identifier` 为默认值、可选 `PortraitRef` 覆盖。因而“15 个 XML 文件没有重复写 `<portraitRef>` 子节点”不是缺失；inventory 必须按这套默认/覆盖规则派生并把最终 `portraitRef + variantKey` 写入证据。

`launcher/web/assets/enemy-portraits/manifest.json` 当前使用 `cf7.enemy-portrait-manifest.v1`，主键为 `entries[portraitRef].variants[variantKey]`。只有 `variant.status=human_accepted` 可暴露 `subject.svg / subject.pngFallback`；`pending_human_review`、`excluded_unimplemented` 与 `identity_alias` 都不得指向未签名的新主体。`aliases` 只接受已验证的 identity-alias receipt，并必须防止环；别名 entry 只登记目标，resolver 从清单顶层别名表跳转到目标的 `human_accepted` variant，调用方显式 variant 优先于 alias 的 `variantKey`。每个现代 variant 绑定透明裁切 SVG、精确人审 512px PNG、原图回退与决定/render/vector 来源；文件名按内容哈希生成，清单 `manifestDigest` 闭包全部条目和来源。`subject.preferredFormat=svg|png` 是首选格式顺序的唯一显式权威；promotion/checker 必须从 SVG 字节重算 `embeddedRasterCount/isRasterHeavy` 并拒绝字段漂移。纯矢量保持 SVG-first；任何含嵌入栅格的包装 SVG 一律 PNG-first，`isRasterHeavy` 只记录其体积/数量风险而不另行决定顺序，不能用“扩展名是 SVG”冒充矢量收益。

当前冻结通用包由 `promote-enemy-portraits-v1.py` 的 subjects-first / manifest-last 全量入口与 `promote-arena-portrait-supplement-v1.py` 的基础摘要绑定增量入口共同验证；manifest 单文件替换是唯一运行时权威切换，不宣称整目录或多文件事务原子。随仓 immutable evidence 由 353 条显式 artifact path、211 条 digest-bound selected-master 派生记录和一个逐 blob 校验的 25 项 raw sidecar 组成；显式与派生合计 564 条（560 条 `tmp/portrait-pilot` 生产证据 + 4 条 tracked controller provenance），supplement 又把基础 manifest/receipt 的原始字节压缩内嵌到 closure，避免 clean checkout 依赖 ignored tmp。`test-evidence-only-full-build-v1.py` 必须在 base exact-fileset 清理、pack/materialized cache 清空并改用 base-cleaned basis root 后仍完成 supplement，且进程内 promotion build/check 路径 564/564 全消费、不触达 live tmp；它显式跳过四个历史 verifier 子进程，因为父进程 audit hook 不会继承，后者由真实 normal supplement promotion 与 standalone checks 独立覆盖。subjects fileset 只允许 runtime 引用与 runtime manifest 的 17 条显式 preserved evidence（12 条 orientation-only + 5 条 SVG reconstruction basis；后 5 条与最终 runtime SVG 重叠）；evidence pack 的 `preservedSubjects` 只含前 12 条。最终 442 个唯一 runtime 引用与 preserved 的 exact union 为 454，disk/tracked 也为 454，extra/missing 均为 0，未声明 stale/orphan 会被清理或拒绝。设置 `CF7_PORTRAIT_EVIDENCE_ONLY=1` 后执行两级 `check` 必须在没有 tmp provenance 的情况下通过。manifest digest `EFDBD928…06E5`、receipt digest `17FC0D9B…0EDF`、supplement closure digest `C70B03A8…8AD3`、base manifest digest `EED4D8DC…01D0`：226 identity / 227 variant / 221 个全 variant 已接受 identity / 222 个 `human_accepted` variant / 2 个 `pending_human_review` / 1 个 `excluded_unimplemented` / 2 个回执别名。两个 pending 精确为 `敌人-Serpent`、`敌人-黑无常索命`；内部主体 17 项已全部进入现代 SVG/PNG 路径。新增 Arena 五项保留逐项人审与方向来源，`敌人-锡蒙利范围光环发生器` 只以签名 alias 指向 `敌人-锡蒙利::default`，不得复制或伪造主体。它完整保留原 98 identity / 99 variant 的 Team 子集，其中 98 个 variant 已接受、`不知火舞` 仍明确未实装。每个现代 variant 的 `provenance.orientationAction=keep|flip_x` 必须与 `subject.svg.flipX`、SVG 内部变换标记及 `subject.pngFallback` 的真实像素朝向一致；不得只翻 SVG 或 PNG 其中一路。FFDec 源若含自闭合空 `<filter/>`，promotion 必须剥离对应引用并在 `subject.svg.compatibilityTransforms` 与 provenance 中登记，否则 Chromium 会把有效 `<use>` 画成透明；resolver 还会在 SVG onload 后做小尺寸透明像素检查，全空时顺序降级到 PNG。

promotion 的基础方向解析区分 `direct_model_orientation`、`explicit_correction_orientation`、`explicit_human_post_crop_flip`、`selected_model_orientation_inherited_after_human_crop` 与 `legacy_orientation_unassessed`。普通 `cf7.portrait-pilot-human-framing-render-report.v1` 只冻结未翻转源空间中的人工 crop，本身没有 `orientationAction`；若该 adjustment 选中了 proposal / independent-review，就必须继承所选模型行的方向并在人工 crop 之后执行，不能把“人类重新框选”误解为 `keep`。显式 guided-orientation 继续优先于继承值。全量方向复核闭合后，最终生产 provenance 只允许 `production_visual_audit_model_verified_keep` 与 `explicit_production_orientation_human_audit`，并在 `orientationAudit` 中保留源生产动作和相对变换。`cf7.portrait-orientation-propagation-audit.v1` 必须逐项验证 action、SVG 与 512px PNG 三者闭合；基础 r210 digest `0D6B0C7F…22C3` 覆盖当时 217/217，三类 mismatch 均为 0，`legacyVisualAuditRequired=0`；r220 digest `1A10ECD4…DC2A` 是后续 222 项历史快照。当前 r221 绑定最终 production manifest 与当前 promotion controllers，digest `DDC843A4…0576` 覆盖 222/222：178 个模型闭合保持、39 个真人方向裁决、4 个尾批真人 pass 与家用机器人 1 项显式 `flip_x`，三类 mismatch 与 legacy 仍全部为 0。新增项不伪装成 r210 已审对象，r210/r220 均不得继续冒充 current。

生产包方向全量视觉复核使用 `cf7.production-portrait-orientation-visual-audit-manifest.v1` 与 `cf7.production-portrait-orientation-visual-model-report.v1`。输入只能是最终 production 512px PNG，canonical 目标为主体视觉轴朝 viewer-right；武器、特效和留白不得覆盖可见解剖朝向。控制器把 217 项分成最多 8 项的 28 组，以 Luna Max / Fast6 执行 A/B 两套独立盲审并保留 56 个完整进程回执。只有 A/B 都建议 `keep` 且最低 confidence 至少 `0.75` 才可记为 `model_verified_keep`；双 flip、方向分歧、ambiguous 或低置信度都必须进入真人页，模型报告固定禁止生产写入。当前 report digest `CB6EF3AE…68F4`：178 项模型一致保持、11 项 A/B 一致建议镜像、28 项分歧/含混/低置信度。

方向真人页使用 `cf7.portrait-orientation-human-review-data.v1`，只包含上述 39 个风险项，并把完全相同的 production PNG 同时展示为“保持当前”和 CSS 水平镜像的 512px / 80px 对照；不得预选。导出 `cf7.portrait-orientation-human-decisions.v1` 必须精确绑定 `batchId/sourceDigest/modelReportDigest/reviewDigest`，包含 39 个唯一 `reviewKey` 的 `keep|flip_x`、逐项时间及 `complete=true`。r204 review digest `D4555C91…1FA0` 已由回执 `15828B45…243` 闭合为 34 keep / 5 relative `flip_x`；相对镜像精确作用于 `ArmsArius`、`忍者BOSS`、`忍者兵`、`汽车炸弹`、`重盾骑士` 的当前生产像素，不能解释成覆盖底层绝对动作。promotion 必须保留旧审计的 434 个素材绑定 / 432 个唯一文件；r202 控制器或 live manifest 已演进时，只能显式提供 artifact-supersession receipt `12D8EF1F…865D` 使用字节相同的冻结副本，禁止静默跳过历史哈希门。

消费者使用 `portraitRef + portraitVariant`；无显式 variant 时取 alias `variantKey` 或 `defaultVariant`。武装 JK 必须同时提供 `orange / white`，Host/AS2 稳定 `portraitVariant` 优先于旧 snapshot 的本地化 `schemeStatus` 兼容桥。`portrait-resolver.js` 对外以 `EnemyPortraits` 为消费者无关入口，并保留 `PortraitResolver` 同实例兼容别名；当前生产真源为 `cf7.enemy-portrait-manifest.v1`，同时只读兼容历史 `cf7.team-enemy-portrait-manifest.v1`。schema 切换只能由 promotion/controller 完成，消费者不得就地改写 manifest。加载链先按 `subject.preferredFormat` 排 SVG/PNG，再尝试另一主体格式、调用方旧图和一次性 `pet_locked.png`；旧 manifest 缺首选字段时，仅对 `SVG≥2MiB 且至少为 PNG 8 倍`的主体采用 PNG-first。manifest transport 每次调用至多一个 in-flight；失败清 Promise 并按 250/500/1000/2000/4000ms 封顶退避，冷却内 fail-soft，不把一次瞬时失败永久缓存为 null。dev harness 只可通过 `CF7_PORTRAIT_ROOT / CF7_PORTRAIT_LEGACY_ROOT / CF7_PORTRAIT_LOCKED_URL` 投影文档根，异步结果必须用 DOM request token 拒绝过期回写。边框、氛围底色、地面光晕与 theme 属于 `entity-portrait-art` Web presentation，不写入透明主体或 provenance manifest；`team-portrait-art` 仅是 Team 兼容 class。

佣兵不伪装成怪物 `portraitRef`。`merc-portrait-renderer.js` 对外暴露 `MercPortraits`，只消费只读外观投影 `id/gender/height/face/hair/equips` 与 `assets/dressup/manifest.json`，固定从战斗 rig 的 `空手站立` 生成胸像快照；旧 Host 缺字段时按 AS2 兼容规则归一为女、女性默认脸型、空发型和空装备，显式男值仍保持男。快照 key 使用规范化 face/hair、去强化后缀并映射槽位的 equipment 与渲染参数；LRU 默认同时受 96 条和估算 12MiB 双上限约束。同 key 的并发请求共享一个 job、每个 mount 持有独立活订阅；最后订阅者释放即取消排队或活动 renderer，任一异步 tick 异常都必须销毁 renderer、释放并发槽并 settle。`clear` 先作废 DOM token/订阅再显示回退，迟到结果不得复活旧卡；加载或渲染失败显示领域无关剪影，不得生成或回写佣兵战斗权威。

Arena 定制赛目录以 `units.json.spritename` 作为消费身份，按 exact case-sensitive identity 去重；标准、堕落、爬升卡片及右侧对手明细中的怪物同样按 roster `type/spritename` 进入 `EnemyPortraits`，佣兵进入 `MercPortraits`。定制目录中的 `主角-*` 不是怪物 manifest 债务：派生目录 v2 从各单位 `data.gender/face/hairstyle` 与 11 个装备字段生成只读 `portrait.kind=dressup` 投影，目录和已选阵容行均按单位 ID 进入 `MercPortraits`。当前 450 条单位记录形成 217 个唯一消费身份，其中 3 个主角模板全部可走纸娃娃，余下 214 个怪物身份全部命中通用包，因此合计 217/217 ready、0 显式回退；通用包另核对 222 个已接受 variant 的 444 个 SVG/PNG 绑定（442 个唯一文件）。旧 `敌人-lady` 已统一为具有人审资产的 exact identity `敌人-Lady`，不再计作素材缺口；`敌人-锡蒙利范围光环发生器` 通过签名 alias 解析到 `敌人-锡蒙利::default`。隐藏警报卡不得挂载或预取对手头像，避免从 DOM/网络泄露身份；完整密度固定为每排 2 张识别卡，并在卡内按实际阵容顺序展示最多 4 个单位小头像，超出部分用 `+N` 表意；紧凑密度为每排 3 张速览卡，仅显示同一头像组首项。密度切换只改变可见投影，不得重新抽取阵容或发起 Host preview；两态都保留对手数、等级与经济语义。该 `217/217` 只证明当前目录与资产路由闭包；目录增长必须同步审计基线，素材增长必须继续绑定真人接受与 manifest provenance。

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

`RosterType` 只决定战队名册与商店筛选类型，不会让宠物自动进入领养目录。需要由玩家领养获得的宠物，还必须被 `/Pets/PetStore/Category/List` 至少引用一次；否则定义虽能进入 `pet_lib`，但未拥有的玩家在 Web 战队界面没有获得入口。类型筛选后若请求的原始分类索引不可用，Host 必须回退到该类型第一个非空分类，并通过 `selectedCategoryIndex` 告知 Web；不得假定任一类型都从索引 `0` 开始。真实目录关键宠物应以仓库数据回归同时锁定“定义存在、商店可达、默认分类回退后可投影”。

#### `宠物信息[i][5].托管长枪` 运行态存档扩展

T800（`petId=66`）的玩家供枪不写回 `pets.xml`，而作为单只战宠的持久属性保存：

```text
{
  version: 1,
  item: <BaseItem.toObject() 的完整深克隆>
}
```

- `item` 是交付时权威，包含弹耗、强化、插件、tier 与 `lastUpdate`；出战单位只能使用它的再克隆副本。
- 取回不合并战斗期 `item.value` 变化；返还的始终是交付快照，因此 AI 免费换弹不能成为玩家免费补弹通道。
- 未知 `version`、缺 `item` 或无法重建 `BaseItem` 时必须 fail-closed：禁止新交付覆盖，禁止取回和删除该宠物。
- Web `petSnapshot.promotions` 不得序列化该对象；对外只提供 `managedLongGun` 的白名单安全投影。
- `managedLongGun.candidates` 可以投影背包中的全部 `use=长枪`，但每行必须携带 Host/AS2 计算后的 `eligible/lockReason`。Web 默认“兼容”过滤不可交付项，显式“背包”只负责展示完整集合与原因，不得把不可交付行改成可提交。
- 当前托管/预设武器的完整注释必须从冻结权威或默认物品实例重建；候选注释必须重新复证 `{containerId,slot,expectedLease}` 且只接受背包 `use=长枪`。Web 不得根据快照摘要自行拼装备属性，也不得以名称回查替代 exact lease。

1. 确认数据类型对应的目录
2. 参照该类型现有文件的 XML 结构
3. 使用 UTF-8 编码，添加中文注释说明用途
4. 参阅 `agentsDoc/game-design.md` 确认数值平衡参考

