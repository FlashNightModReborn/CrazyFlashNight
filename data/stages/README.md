# 关卡 XML 编写指南

本文档面向关卡、数值与剧情策划，说明 `data/stages/` 中现役 XML 的目录关系、通用解析规则、主要节点、运行效果、风险边界与验证方法。

本文档只记录当前已经存在的能力，不引入新的 XML 语法，也不改变运行时行为。通用 XML 解析规则与跨数据系统约定以 [XML 数据体系](../../agentsDoc/data-schemas.md) 为准；本文件是关卡日常编写入口。武器、技能等数值平衡的落盘与复现另见 [balance 落盘与复现契约](../../tools/cf7-balance-tool/docs/agent-balance-record-design.md)。

策划不需要一次读完全文：先看第 1 节和下面的快速定位表，再跳到本次要改的节点。第 20 节命令由提交者、程序或自动化代理负责执行，不要求策划维护脚本。

## 1. 先看这几条

1. 调整现有关卡时，优先只改目标关卡 `.xml`；新增可选关卡时，才同步改同目录 `__list__.xml`。
2. 新关卡不要从空白文件开始写，应复制玩法最接近的现役关卡，再逐项替换。
3. 文件名、`__list__.xml` 中的 `<Name>`、任务或入口引用的关卡名通常必须完全一致，包括空格、中文标点和全半角字符。
4. XML 标签名、属性名和字符串值区分大小写；不要擅自翻译或改名。
5. `data/` 下 XML 是运行时数据，正常情况下保存后重启游戏生效；只改 XML 不需要发布 SWF，也不等同于 Flash 编译。
6. 不要在 `data/stages/` 下新增“示例.xml”“测试.xml”或备份副本。现有工具会递归扫描 `*.xml`，示例代码应只放在本 README 的代码块中。
7. `CallbackFunction`、事件 `Callback`、`CaseSwitch expression` 和不认识的 `Identifier` 都连接程序能力。策划可以修改已经确认的数值或分支内容，但新增函数名、表达式或素材标识前必须让程序复核。
8. 当前没有覆盖所有关卡语义的统一 schema 校验器。XML 能被解析，只能证明语法闭合，不能证明关卡一定能进入、刷怪、结算或返回。

### 日常修改风险分级

| 分级 | 常见内容 | 策划处理方式 |
|---|---|---|
| 日常可配 | 奖励名称/概率分母/数量上限，敌人 `Type`、`Quantity`、`Level`、难度上下限 | 按本文档修改并走对应检查 |
| 复制现例后改值 | 波次结束条件、出生点、场景元件、掉落箱、事件、触发器、计时池 | 复制同玩法现例，保留结构，只改明确字段 |
| 必须程序复核 | 新 `CaseSwitch` 表达式、新回调函数、新 `Identifier`、内联人形单位、历史 Rogue 字段 | 策划提供需求和取值，程序确认消费逻辑 |

### 常见需求快速定位

| 想改什么 | XML 位置 | 先看 |
|---|---|---|
| 选关名称、解锁、说明 | `目录/__list__.xml/StageInfo` | 第 4 节 |
| 通关奖励 | `GameStage/Rewards/Reward` | 第 6 节 |
| 跨子图总时限 | `GameStage/TimePools` + `SubStage/TimePoolRef` | 第 7 节 |
| 军阀战棋子关 | `SubStage[@driver='Warlord']` | 第 8 节 |
| 玩家出生点、背景、BGM | `SubStage/BasicInformation` | 第 8 节 |
| 箱子和地图元件 | `SubStage/Instances/Instance` | 第 9 节 |
| 敌人出生点 | `SubStage/SpawnPoint/Point` | 第 10 节 |
| 地面拾取物 | `SubStage/Pickups/Pickup` | 第 11 节 |
| 每波时间和结束条件 | `SubStage/Wave/SubWave/WaveInformation` | 第 12 节 |
| 敌人种类、数量、等级、难度 | `SubStage/Wave/SubWave/EnemyGroup/Enemy` | 第 13 节 |
| 剧情、提示、强制流程 | `SubStage/Event` | 第 15 节 |
| 进入区域触发剧情 | `SubStage/Trigger` + `EventName=TriggerPressed` | 第 16 节 |
| 随机/难度条件分支 | `CaseSwitch` | 第 17 节；必须程序复核 |

## 2. 文件结构与加载关系

`data/stages/` 不是“扫描到什么就加载什么”，而是两级索引加具体关卡文件：

```text
data/stages/list.xml
    └─ <stages>基地门口</stages>
         └─ data/stages/基地门口/__list__.xml
              └─ <StageInfo><Name>新手练习场</Name>...</StageInfo>
                   └─ data/stages/基地门口/新手练习场.xml
```

运行时 [StageInfoLoader](../../scripts/类定义/org/flashNight/gesh/xml/LoadXml/StageInfoLoader.as) 按以下规则工作：

1. 读取 `data/stages/list.xml` 中每个 `<stages>目录名</stages>`。
2. 加载 `data/stages/<目录名>/__list__.xml`。
3. 把每个 `StageInfo` 以 `Name` 为字典键。
4. 自动拼出 `data/stages/<目录名>/<Name>.xml` 作为战斗关卡 URL。

因此：

- 在现有目录中调整现有关卡，不需要改 `list.xml`。
- 在现有目录中新增普通战斗关卡，需要新增同名 `.xml`，并在该目录 `__list__.xml` 中新增 `StageInfo`。
- 新增一级目录时，才需要把目录名加入 `list.xml`，并创建该目录的 `__list__.xml`。
- `Name` 在全局应保持唯一。不同目录出现同名 `Name` 时会写入同一个字典键，后加载者可能覆盖前者。
- `list.xml` 中已有少量历史重复目录项，不要把它当作模板，也不要在无专项验证时顺手清理。

### 特殊文件和例外

| 文件或类型 | 作用 | 注意事项 |
|---|---|---|
| `list.xml` | 一级目录索引 | 不是具体关卡清单 |
| `<目录>/__list__.xml` | 玩家入口和关卡元信息 | 普通战斗关卡由 `Name` 自动拼出同名 XML |
| `<目录>/<关卡名>.xml` | `GameStage` 具体内容 | 刷怪、事件、奖励、场景元件都在这里 |
| `loading_data.xml` | 历史加载界面数据 | 不属于 `GameStage` 语法，不要拿它当关卡模板 |
| `特殊/教学关卡.xml` | 程序直接加载的特殊关卡 | 不依赖普通 `StageInfo` 一一索引，不是新增普通关卡的模板 |
| `Type=外交地图` | 进入已有地图帧/位置 | 可以只有 `StageInfo` 而没有同名 `GameStage` 文件 |

“索引中没有同名 XML”或“XML 没出现在索引中”不一定是错误；教学关、外交入口和程序直载属于例外。但新增普通战斗关卡时，不要自行创造新的例外。

## 3. XML 通用语法与隐式转换

### 3.1 基本格式

推荐使用：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<GameStage>
    ...
</GameStage>
```

- 文件保持 UTF-8。
- 使用 4 空格缩进。
- 一个文件只能有一个根节点。
- 开始标签和结束标签必须成对，嵌套不能交叉。
- 属性值必须加引号。
- `&`、`<`、`>` 等保留字符出现在正文时必须使用 XML 实体。
- 注释写成 `<!-- 说明 -->`。运行时会忽略注释，不要把生效数据只写在注释里。

### 3.2 自动类型转换

关卡 XML 通过 [XMLParser.parseStageXMLNode](../../scripts/类定义/org/flashNight/gesh/xml/XMLParser.as) 转换为 AS2 对象。叶节点和属性会自动转换：

| XML 文本 | 运行时值 |
|---|---|
| `100`、`-1`、`2.5` | Number |
| `true`、`True`、`TRUE` | Boolean `true` |
| `false`、`False`、`FALSE` | Boolean `false` |
| `007` | Number `7`，不会保留前导零 |
| 空节点 | 空字符串 |
| 其他文本 | String |

需要保留前导零、纯数字 ID 或文本 `true` 时，不能假定它仍是字符串；应先让程序确认消费侧是否显式转回字符串。

不要写 `null` 表示空值。它只是普通字符串 `"null"`。新配置中需要“没有这个字段”时，通常应直接省略节点。

### 3.3 同名节点：一个是单值，多个才是数组

```xml
<Parameter>0</Parameter>
```

会得到一个值；而：

```xml
<Parameter>0</Parameter>
<Parameter>1</Parameter>
```

会得到数组 `[0, 1]`。`SubStage`、`SubWave`、`Enemy`、`Event`、`Dialogue`、`Parameter`、`Reward` 等重复节点都遵守这条规则。

现役消费侧对主要列表做了单值转数组，但不是所有历史字段都有保护。不要为了“格式统一”随意把一个节点复制成两个，也不要把两个同名节点套进自创的复数容器。

### 3.4 属性和子节点都会进入对象

```xml
<SubStage id="0">
    <BasicInformation>...</BasicInformation>
</SubStage>
```

其中 `id="0"` 会成为该对象的 `id` 字段，并自动转成数字。属性名不能与同层需要的子节点名冲突。

### 3.5 顺序何时重要

- 多个 `SubStage` 的物理顺序就是过图顺序，不按 `id` 自动排序。
- 多个 `SubWave`、`Enemy`、`Dialogue`、`Reward` 的物理顺序会被保留。
- 数字 `SpawnIndex` 实际索引 `Point` 的物理顺序；建议让 `Point id` 与从 0 开始的物理序号保持一致。
- `CaseSwitch` 必须是其包装节点的第一个有效子节点，`default` 分支必须放最后。
- 多个完全相同触发条件的 `Event` 可能都会执行，且不要依赖它们的书写先后作为剧情顺序；需要顺序时使用已验证的对话/跟随事件结构。

## 4. `__list__.xml`：关卡入口元信息

普通战斗关卡的最小条目：

```xml
<Stages>
    <StageInfo>
        <Type>无限过图</Type>
        <Name>示例关卡名</Name>
        <FadeTransitionFrame>wuxianguotu_1</FadeTransitionFrame>
        <UnlockCondition>1</UnlockCondition>
        <Description>关卡说明</Description>
    </StageInfo>
</Stages>
```

### 常用字段

| 字段 | 功能 | 编写要求 |
|---|---|---|
| `Type` | 入口类型 | 当前日常值为 `无限过图` 或 `外交地图`；不要自创类型 |
| `Name` | 全局关卡键、显示名、普通战斗 XML 文件名 | 必须精确一致且全局唯一 |
| `FadeTransitionFrame` | 普通战斗/任务进入时的淡出跳转帧 | 普通关卡通常沿用现例 `wuxianguotu_1` |
| `UnlockCondition` | 主线进度解锁阈值 | 当前判定为玩家主线进度大于等于该值 |
| `Description` | 选关界面说明 | 玩家可见；需要换行时复制现有 `&amp;lt;BR&amp;gt;` 写法 |
| `MaterialDetail` | 选关界面的可得材料说明 | 玩家可见；只写真实可得内容 |
| `StartFrame` | 任务进关前设置的地图帧/返回上下文 | 只在同类任务入口中复制 |
| `Limitation` | 限制词条键 | 可重复；只能使用限制系统已有键，例如现存 `DisableCompanion` |
| `LimitLevel` | 关卡限制难度等级 | 沿用相邻条目的数值口径，不要自行解释成敌人等级 |

`Description` 和 `MaterialDetail` 经过索引加载器的 HTML 实体处理。XML 中不能直接把 `<BR>` 当普通文本写入，否则会被当成子标签；请复制现有实体写法。

### 替代解锁条件

`AltUnlockCondition` 表示主线阈值之外的任务链解锁路径。多个条件之间是 OR：

```xml
<UnlockCondition>28</UnlockCondition>
<AltUnlockCondition chain="大学" min="7"/>
```

含义是“主线进度达到 28，或任务链‘大学’进度达到 7”。`chain` 必须是现有任务链精确名称，`min` 是最低进度。新增这类条件时应同时核对任务链真源，不能只凭界面文案猜名称。

### 外交地图字段

```xml
<StageInfo>
    <Type>外交地图</Type>
    <Name>外交-示例地点</Name>
    <UnlockCondition>1</UnlockCondition>
    <Description> </Description>
    <RootFadeTransitionFrame>地图-示例地点</RootFadeTransitionFrame>
    <Address>出生地</Address>
</StageInfo>
```

| 字段 | 功能 |
|---|---|
| `RootFadeTransitionFrame` | 跳转到主时间轴上的地图帧标签 |
| `Address` | 进入该地图后的出生位置名；缺省路径通常按 `出生地` |

外交地图连接 Flash 时间轴和场景位置。新增帧标签或位置名不属于纯 XML 工作，必须由程序/Flash 维护者确认素材真实存在。

### 历史字段

`EndFrame` 在部分索引条目中存在，旧配置函数也会投影它，但当前主要任务进关路径并不以它作为统一的关卡结束权威。不要在新设计中依赖它来决定通关返回；需要改变返回目的地时，应由程序确认实际入口和退出链路。

## 5. `GameStage` 总体结构

一个常规战斗关卡可以包含：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<GameStage>
    <Rewards>
        <Reward>
            <Name>强化石</Name>
            <AcquisitionProbability>10</AcquisitionProbability>
            <QuantityMax>2</QuantityMax>
        </Reward>
    </Rewards>

    <SubStage id="0">
        <BasicInformation>
            <Background>flashswf/backgrounds/example_BG.swf</Background>
            <PlayerX>150</PlayerX>
            <PlayerY>450</PlayerY>
        </BasicInformation>

        <Wave>
            <SubWave id="0">
                <WaveInformation>
                    <Duration>0</Duration>
                    <FinishRequirement>0</FinishRequirement>
                </WaveInformation>
                <EnemyGroup>
                    <Enemy>
                        <Type>兵种2</Type>
                        <Interval>100</Interval>
                        <Quantity>3</Quantity>
                        <Level>5</Level>
                        <SpawnIndex>right</SpawnIndex>
                    </Enemy>
                </EnemyGroup>
            </SubWave>
        </Wave>
    </SubStage>
</GameStage>
```

`GameStage` 根下的现役主要节点是：

| 节点 | 数量 | 功能 |
|---|---:|---|
| `Rewards` | 0 或 1 | 整个关卡的通关奖励 |
| `TimePools` | 0 或 1 | 跨 `SubStage` 的会话计时池 |
| `SubStage` | 1 个或多个 | 按物理顺序进入的子图 |

历史文件还可能出现 `Unions`、`EnemyDrop`、`RogueWave` 等节点。它们不属于普通新关卡的稳定编写面，不要从备份或生存战文件中复制到新配置。

## 6. 通关奖励 `Rewards`

```xml
<Rewards>
    <Reward>
        <Name>强化石</Name>
        <AcquisitionProbability>10</AcquisitionProbability>
        <QuantityMax>2</QuantityMax>
    </Reward>
    <Reward>
        <Name>弹簧</Name>
        <AcquisitionProbability>1</AcquisitionProbability>
        <QuantityMax>1</QuantityMax>
    </Reward>
</Rewards>
```

| 字段 | 当前含义 |
|---|---|
| `Name` | 物品精确名称，必须命中物品数据 |
| `AcquisitionProbability` | 正整数概率分母，现役通关奖励逻辑是 `random(N) == 0`；`1` 必得，`2` 约二分之一，`10` 约十分之一 |
| `QuantityMax` | 传给通关奖励界面的正整数数量上限；缺省索引投影按 1 处理，但新配置应显式填写 |

特别注意：`AcquisitionProbability` 不是百分数。把“10%”写成 `10` 恰好得到约十分之一，但“50%”应写 `2`，不是 `50`。

三个字段都是必填。自 2026-08-27 关卡结算迁移起，缺 `AcquisitionProbability`（或值不是正整数）的 `Reward` 行在结算时整行丢弃，不再按历史旧语义视为必得；丢弃数会以“N 项奖励配置未进入本轮结算”披露在结算面板上。历史文件里的缺省行一旦被发现必须补齐，不能当作“必掉”沿用。

部分历史文件出现 `QuantityMin`，但当前主奖励数组只读取 `QuantityMax`，掉落来源投影也只把缺省下限视为 1。不要用 `QuantityMin` 设计新的数量区间。

同一物品可以出现多个 `Reward` occurrence，每项独立进入运行时数据和来源索引。除非设计明确需要多次独立抽取，否则不要重复写同名奖励。

## 7. 跨子图计时池 `TimePools`

`TimePools` 在 `GameStage` 根定义，`TimePoolRef` 直接写在需要计时的 `SubStage` 下：

```xml
<GameStage>
    <TimePools>
        <TimePool>
            <Id>escape_route</Id>
            <DurationSeconds>600</DurationSeconds>
            <DisplayName>撤离区域</DisplayName>
            <TimeoutResult>FailStage</TimeoutResult>
        </TimePool>
    </TimePools>

    <SubStage id="0">
        <TimePoolRef>escape_route</TimePoolRef>
        ...
    </SubStage>
    <SubStage id="1">
        <TimePoolRef>escape_route</TimePoolRef>
        ...
    </SubStage>
</GameStage>
```

现役约束：

- `Id` 匹配 `[a-z][a-z0-9_-]{0,31}`，同一 `GameStage` 内唯一。
- 每个 `GameStage` 最多 16 个池；每个 `SubStage` 最多引用 4 个池。
- `DurationSeconds` 是 1 到 3600 的整数。
- `DisplayName` 是 1 到 32 字符，不能有首尾空白、控制字符或 `|`。
- 当前 `TimeoutResult` 只允许 `FailStage`。
- 每个定义必须至少被引用一次；引用必须命中本文件定义，同一子图不能重复引用同一池。
- 相邻或不相邻子图引用同一池都会延续剩余时间；未引用的中间子图暂停该池。
- 暂停、对话和转场不扣时；离开、失败、完成、重开或返回基地会清空。
- `TimePools` 和 `TimePoolRef` 内禁止 `CaseSwitch`。

计时池完整契约和专用检查见 [XML 数据体系的 GameStage 计时池章节](../../agentsDoc/data-schemas.md#gamestage-跨-substage-计时池)。

## 8. `SubStage` 与 `BasicInformation`

缺省 `driver` 的 `SubStage` 表示一张实际 Action 战斗子图。运行时按 XML 物理顺序进入各子图；旧 Action 的 `id` 建议从 0 连续递增，仅用于保持可读性和兼容既有结构。

### Slice 1：单 Warlord SubStage

当前工作树允许一个窄的军阀战棋关卡：

```xml
<GameStage>
    <SubStage id="warlord_tutorial" driver="Warlord"
              scenarioRef="warlord_tutorial_v1" />
</GameStage>
```

- 整个 `GameStage` 必须恰好只有这一个 Warlord SubStage；Action/Warlord 混排、未知 driver 与多个 Warlord 当前全部拒绝。
- Warlord SubStage 只允许 `id`、`driver`、`scenarioRef` 三个属性，不写 `BasicInformation`、`Wave`、`TimePoolRef` 或其他 Action 字段；根也不写 `TimePools`。
- `id` 与 `scenarioRef` 是最多 160 字符的 opaque ASCII ID，合法字符为字母、数字、`.`、`_`、`~`、`-`，不得依赖显示名或 XML 物理序号。
- 当前唯一允许的 `scenarioRef` 是 `warlord_tutorial_v1`，仍运行旧红蓝九节点规则；不要据此新建第二个内容关卡。
- `not_started` 不自动重试；安全冻结后只能由 Native HUD 的显式动作带回当前 outer session revision 与 exact 六字段 binding。旧 `stage_outcome v1` 返回不能绕过这层栅栏。
- Warlord 返回基地若已冻结结算、但场景淡出未接受，仍保留同一 binding 供 fresh v2 动作重试；不得重新 roll 奖励或自动重开面板。
- 该语法已接入 AS2/Host/Web 源码，并通过 fresh TestLoader 行为、合并源码 `asLoader.swf` 发布与隔离 candidate build；当前为 `candidate_built / NOT_DEPLOYED`，在完成真实 GameStage 旅程前仍不是已上线作者面。

### `BasicInformation` 常用字段

```xml
<BasicInformation>
    <Background>flashswf/backgrounds/gk1_1_BG.swf</Background>
    <PlayerX>152</PlayerX>
    <PlayerY>461</PlayerY>
    <BGM>
        <Command>play</Command>
        <Title>Moan</Title>
        <Loop>true</Loop>
    </BGM>
</BasicInformation>
```

| 字段 | 功能 | 缺省/注意 |
|---|---|---|
| `Background` | 背景 SWF 路径 | 常规子图必填；资源路径必须真实存在 |
| `PlayerX` / `PlayerY` | 玩家出生坐标 | 任一缺失或不可解析时，两者一起回落到地图边界附近的默认位置 |
| `Environment` | 场景边界、尺寸、门和光照配置 | 复杂结构应复制相同背景/玩法现例 |
| `BGM` | 进图音乐控制 | `Command` 为 `play` 或 `stop`；播放时使用 `Title`、`Loop` |
| `Animation` | 进图或清图动画 | `Path` 为资源；`Pause=1` 暂停；`Load=1` 进图播放，`Load=0` 清图时播放 |
| `LoadingImage` | 历史加载图指定 | 现存使用很少，不作为新关卡常规字段 |
| `CallbackFunction` | 进图回调 | 动态函数边界，新增名称或参数必须程序复核 |
| `RogueMode` | 历史 Rogue 模式开关 | 只用于既有专项文件，不要扩散 |

`Environment` 的常见显式边界：

```xml
<Environment>
    <Xmax>1770</Xmax>
    <Xmin>50</Xmin>
    <Ymax>720</Ymax>
    <Ymin>250</Ymin>
    <Width>1770</Width>
    <Height>730</Height>
</Environment>
```

也有 `<Environment><Default>true</Default></Environment>` 走环境系统默认配置。`Door`、`MinIllumination`、`MaxIllumination` 等扩展字段依赖场景环境消费逻辑，按相同场景现例复制。

回调示例：

```xml
<CallbackFunction>
    <Name>已有回调名称</Name>
    <Parameter>6</Parameter>
    <Parameter>0</Parameter>
</CallbackFunction>
```

`Parameter` 按顺序传给函数。策划可以在程序给出的参数表内改值，不能通过 XML 自行猜测函数名或参数个数。

## 9. 场景元件 `Instances`

```xml
<Instances>
    <Instance id="0">
        <x>1400</x>
        <y>360</y>
        <Identifier>资源箱</Identifier>
        <Parameters>
            <掉落物>
                <名字>强化石</名字>
                <最小数量>3</最小数量>
                <最大数量>4</最大数量>
            </掉落物>
        </Parameters>
    </Instance>
</Instances>
```

| 字段 | 功能 |
|---|---|
| `x` / `y` | 场景元件坐标 |
| `Identifier` | 库中的元件/linkage 标识 |
| `url` | 某些元件使用的外部资源路径；通常与 `Identifier` 二选一 |
| `Parameters` | 传给该元件的结构化参数 |

`Identifier` 不是自由文本。即使 XML 能解析，资源库中不存在该标识时也无法得到正确元件。新增标识必须由程序/Flash 维护者确认。

### 地图箱

六类地图箱（保险柜、生存箱、装备箱、资源箱、纸箱、隐藏资源点）的掉落结构和 `row/col` 是严格行为契约：

- `row > 0` 且 `col > 0`：走 Web 战利品意图；`col <= 8` 且 `row * col <= 64`。
- 只有精确 `row == 0` 且 `col == 0` 表示直接地面掉落。
- 负数、只缺一维、单边为零或超限都属于配置错误。
- `最小数量` 和 `最大数量` 必须同时省略或同时填写；同时省略时为 1/1。
- 两者存在时必须是正整数，且最小值不大于最大值。

完整契约见 [XML 数据体系的关卡地图资源箱章节](../../agentsDoc/data-schemas.md#关卡地图资源箱声明)。代表文件见 [夺取材料.xml](副本任务/夺取材料.xml)。

### 场景元件进度门控

`Instance/Parameters` 支持：

- `最小主线进度` / `最大主线进度`；
- `任务链名称` 配合 `最小任务链进度` / `最大任务链进度`；
- `要求进行中任务ID`。

配置的条件按 AND 合取。任务链区间存在但缺少 `任务链名称` 时失败关闭。字段完整说明与一次性拾取契约见 [关卡进度门控与一次性拾取](../../agentsDoc/data-schemas.md#关卡进度门控与一次性拾取)。

## 10. 出生点 `SpawnPoint`

```xml
<SpawnPoint>
    <Point id="0">
        <x>1600</x>
        <y>450</y>
        <Identifier>出生点-钻头</Identifier>
        <QuantityMax>6</QuantityMax>
        <Offset>2</Offset>
        <NoCount>false</NoCount>
        <Hide>false</Hide>
        <BiasX>30</BiasX>
        <BiasY>20</BiasY>
        <Parameters>
            <方向>左</方向>
        </Parameters>
    </Point>
</SpawnPoint>
```

| 字段 | 功能 |
|---|---|
| `x` / `y` | 出生点坐标 |
| `Identifier` | 出生点场景元件 |
| `QuantityMax` | 该点允许同时在场的敌对单位上限；小于等于 0 表示不设该上限 |
| `Offset` | 从该点生成时的 Y 方向偏移 |
| `NoCount` | `true` 时，该点剩余敌人不计入波次结束判断 |
| `Hide` | `true` 时初始隐藏；第一次被波次使用时播放生成/开门，并可能附加生成延迟 |
| `BiasX` / `BiasY` | 两者都大于 0 时，在出生点周围随机偏移 |
| `Parameters` | 传给出生点元件的参数 |

`Enemy/SpawnIndex` 写数字时，索引的是 `Point` 的物理数组位置，不是查找 `id` 字符串。请让 `Point id="0"`、`id="1"`……与物理顺序保持一致。

`NoCount=true` 只改变波次计数，不会自动删除单位。错误使用可能造成关卡提前清图或场上仍有敌人时进入下一波。

## 11. 地图拾取物 `Pickups`

```xml
<Pickups>
    <Pickup>
        <Name>金钱</Name>
        <Value>10</Value>
        <x>700</x>
        <y>400</y>
    </Pickup>
</Pickups>
```

| 字段 | 功能 |
|---|---|
| `Name` | 拾取物类型/物品精确名称 |
| `Value` | 数量；非正数或不可解析时回落为 0 |
| `x` / `y` | 生成坐标 |
| `Parameters` | 结构化生成和进度门控参数 |
| `OnPickup` | 拾取成功后的既有回调配置 |

`Parameters` 可使用与场景元件相同的进度门控，并额外支持 `一次性领取ID`。一次性资格只有在物品真正进入背包后才消耗；背包满、只进关或未拾取不会消耗。

历史文件里可能在 `Pickups` 下直接写 `<金钱>`、`<砖>`、`<资料>`。当前 `StageInfo` 主路径只把 `Pickups/Pickup` 解析为可拾取物数组，新配置统一使用 `Pickup` 结构。

## 12. 波次 `Wave`、`SubWave` 和结束条件

```xml
<Wave>
    <SubWave id="0">
        <WaveInformation>
            <Duration>0</Duration>
            <FinishRequirement>0</FinishRequirement>
            <MapNoCount>false</MapNoCount>
        </WaveInformation>
        <EnemyGroup>
            ...
        </EnemyGroup>
    </SubWave>
</Wave>
```

### `WaveInformation`

| 字段 | 功能 |
|---|---|
| `Duration` | 波次倒计时秒数；缺失、不可解析或不大于 0 时按无倒计时波次 |
| `FinishRequirement` | 当计数敌人数小于等于此值时结束本波；缺失或不可解析时为 0 |
| `MapNoCount` | `true` 时忽略“地图全局”敌人计数，但仍统计未设 `NoCount` 的出生点 |

结束条件是：

- 当前计数敌人数 `<= FinishRequirement`；或
- `Duration > 0` 且倒计时归零。

因此：

- 常规歼灭波写 `Duration=0`、`FinishRequirement=0`。
- 定时坚持波可以写正数 `Duration`；是否允许提前因敌人数达标结束，要按设计设置 `FinishRequirement`。
- 负数 `FinishRequirement` 会让正常的“清空敌人”难以结束波次，通常只在定时或特殊流程中使用；不要无意复制。
- 很大的 `FinishRequirement` 会提前结束波次；`ForceFinishWave` 的内部实现也利用了这一点。

`Duration` 是每个 `SubWave` 自己的倒计时；它不会跨子图延续。跨 `SubStage` 的总时限应使用 `TimePools`。

## 13. 敌人 `Enemy`

推荐使用兵种库引用：

```xml
<Enemy>
    <Type>兵种67</Type>
    <Interval>100</Interval>
    <Delay>0</Delay>
    <Quantity>3</Quantity>
    <Level>20</Level>
    <SpawnIndex>right</SpawnIndex>
    <DifficultyMin>冒险</DifficultyMin>
    <DifficultyMax>地狱</DifficultyMax>
    <Parameters>称号:示例,不掉装备:true</Parameters>
</Enemy>
```

### 常用字段

| 字段 | 功能 | 缺省/注意 |
|---|---|---|
| `Type` | `_root.兵种库` 中的兵种 ID | 日常配置首选；必须真实存在 |
| `Interval` | 同组单位的刷出间隔 | 不可解析时为 100；单位和节奏按同类现例 |
| `Delay` | 本组开始刷出的附加延迟 | 不可解析时为 0 |
| `Quantity` | 本组总数量 | 不可解析时为 1；应填正整数 |
| `Level` | 单位等级 | 不可解析时为 1 |
| `SpawnIndex` | 数字出生点索引，或 `left/right/front/back/door` | 省略时走默认随机侧边；见下表 |
| `x` / `y` | 直接指定生成坐标 | 两者有效时优先于出生点坐标 |
| `DifficultyMin` | 最低生效难度 | 当前现役难度名包括 `简单/冒险/修罗/地狱` |
| `DifficultyMax` | 最高生效难度 | 上下限都是包含边界 |
| `Parameters` | 覆盖或补充该实例参数 | 支持文本和嵌套对象两种写法 |
| `InstanceName` | 固定实例名，并开启单位关卡事件发布 | 常与 `UnitSpawn/UnitDeath/UnitRemoved/UnitEmergency` 事件配合 |
| `IsHostile` | 覆盖单位敌我属性 | 新配置只写明确的 `true` 或 `false`，不要写字符串 `null` |

### `SpawnIndex`

| 值 | 生成位置 |
|---|---|
| `0`、`1`…… | `SpawnPoint/Point` 的物理数组位置 |
| `left` | 地图左侧 |
| `right` | 地图右侧 |
| `front` | 玩家前方区域，并默认令单位朝左 |
| `back` | 地图后段区域 |
| `door` | 出口门位置 |
| 省略或其他非数字值 | 默认在左右两侧随机 |

数字索引越界会把后续逻辑指向不存在的出生点，属于配置错误。使用数字索引时，先核对本 `SubStage` 的 `Point` 数量和物理顺序。

### 内联人形配置

如果 `Type` 不命中兵种库，运行时会尝试从 `spritename`、`Name`、`Gender`、`Height`、`PrimaryWeapon`、`SecondaryWeapon`、`MeleeWeapon`、`Grenade`、`FaceType`、`HairStyle`、`HeadEquipment`、`BodyArmor`、`LegArmor`、`HandGear`、`FootGear`、`NeckGear` 等字段组装单位。

这是历史兼容能力，不是推荐的日常写法。它绕过标准兵种条目的集中维护，新增内联人形必须由程序和角色/装备维护者共同复核。

`RandomType`、小写 `parameters` 等只出现在少量历史文件中，不要把大小写不同的旧字段当作 `Parameters` 的等价写法。

## 14. `Parameters` 的两种写法

### 14.1 文本键值对

```xml
<Parameters>称号:坛主,保留屏外尸体:true,方向:左</Parameters>
```

解析规则：

- 先按英文逗号 `,` 切成多项；
- 每项必须恰好按英文冒号 `:` 切成“键”和“值”；
- 数字转 Number，精确小写 `true`/`false` 转 Boolean；
- 不会去除首尾空格；
- 没有转义机制，键或值本身不能包含英文逗号或冒号。

因此应写 `方向:左`，不要写 `方向 : 左`；后者会把空格保留进键和值。

### 14.2 嵌套对象

```xml
<Parameters>
    <不掉钱>true</不掉钱>
    <不掉装备>true</不掉装备>
    <掉落物>
        <名字>强化石</名字>
        <最小数量>3</最小数量>
        <最大数量>4</最大数量>
    </掉落物>
</Parameters>
```

嵌套写法支持重复节点和复杂结构，适合箱体、进度门控、运动参数等。字段名仍由具体消费方决定，`Parameters` 不是“写什么都会生效”的万能字典。

常见参数类别：

| 场景 | 现役示例 |
|---|---|
| 敌人实例 | `称号`、`方向`、`登场动画`、`死亡动画`、`不掉钱`、`不掉装备` |
| 重要敌人死亡表现 | `保留屏外尸体:true` |
| 地图箱 | 重复 `掉落物`、`名字`、`最小数量`、`最大数量`、`row`、`col` |
| 场景元件/出生点 | `方向`、缩放、旋转、运动模式等元件专用参数 |
| 进度门控 | 主线、任务链、进行中任务 ID、一次性领取 ID |

`保留屏外尸体:true` 只应给少量需要保留死亡结果的重要实例；不要给成群杂兵批量设置。完整边界见 [关卡敌人屏外尸体保留参数](../../agentsDoc/data-schemas.md#关卡敌人屏外尸体保留参数)。

## 15. 关卡事件 `Event`

`Event` 订阅当前 `SubStage` 的运行时消息。事件参数匹配后执行一次并销毁：

```xml
<Event>
    <EventName>WaveFinished</EventName>
    <Parameter>0</Parameter>
    <Message>第一波完成！</Message>
</Event>
```

`EventName` 必须是实际会发布的事件名；`Parameter` 按位置逐项匹配发布参数。没有参数的 `Start` 事件应省略 `Parameter`。

当前关卡文件中可见的事件名包括：

| 事件名 | 常见参数与用途 |
|---|---|
| `Start` | 无参数，子图加载完成后触发 |
| `WaveStarted` | 0 开始的波次索引 |
| `WaveFinished` | 0 开始的波次索引 |
| `Pickup` | 拾取物相关参数；复制同类现例 |
| `TriggerPressed` | `Trigger id` |
| `UnitSpawn` | 固定 `InstanceName` |
| `UnitDeath` | 固定 `InstanceName` |
| `UnitRemoved` | 固定 `InstanceName` |
| `UnitEmergency` | 固定 `InstanceName` |
| `NextStage` | 特殊流程消息；不要与 `StageProgress=NextStage` 混淆 |

事件处理器会执行所有匹配项。对多个同名同参数事件，不要依赖 XML 上下顺序控制剧情先后。

### 事件可以执行的动作

一个 `Event` 可以同时声明多种动作：

| 节点 | 功能 | 结构/限制 |
|---|---|---|
| `Message` | 屏幕文字提示 | 纯文本 |
| `Guidance` | 加载已有引导界面 | 值必须是已有引导标识 |
| `StageProgress` | 改变关卡流程 | 只用 `Finish`、`Fail`、`NextStage`、`ForceFinishWave` |
| `Animation` | 播放外部动画 | `Path`；可选 `Pause=1` |
| `BGM` | 播放/停止关卡 BGM | `Command`、`Title`、`Loop` |
| `Dialogue` | 播放一条或多条对话 | 见下节 |
| `FollowingEvent` | 对话结束后发布后续事件 | 当前只应与对话一起使用 |
| `Enemy` | 立即生成单位 | 使用 `Enemy` 字段；可重复 |
| `Callback` | 调用已有关卡回调函数 | 动态函数边界，必须程序复核 |
| `Sound` | 调用已有音效名 | 代码支持重复 `Sound`，当前关卡语料缺少代表例，新增前复核 |
| `PerformanceControl` | 临时调节性能等级 | 性能专项字段，不作为普通剧情工具 |
| `Camera` / `Performance` | 历史预留 | 当前 `StageEvent` 标记为未实装，不要使用 |

动作执行大体顺序为：性能调控 → 动画 → BGM → 对话 → 生成单位 → 引导 → 提示 → 音效 → 关卡进度 → 回调。不要利用这条内部顺序拼出难以维护的隐式脚本；复杂流程应拆成已有事件链并让程序复核。

### 对话

```xml
<Event>
    <EventName>Start</EventName>
    <Dialogue id="0">
        <Name>诺艾尔</Name>
        <Title>女仆骑士（自称）</Title>
        <Char>诺艾尔</Char>
        <Text>应该就在前方。</Text>
    </Dialogue>
    <Dialogue id="1">
        <Name>$PC</Name>
        <Title>$PC_TITLE</Title>
        <Char>$PC_CHAR#严肃</Char>
        <Text>继续前进。</Text>
    </Dialogue>
</Event>
```

| 字段 | 功能 |
|---|---|
| `Name` | 显示名；`$PC` 等占位符按现有对话系统处理 |
| `Title` | 称号/身份 |
| `Char` | 角色立绘或表情键 |
| `Text` | 对话正文 |
| `ImageUrl` | 可选自定义图片 |

对话会暂停关卡。占位符、角色键和表情后缀必须复制对话系统已有写法。

### 跟随事件

```xml
<FollowingEvent>
    <EventName>NextStage</EventName>
</FollowingEvent>
```

当前跟随事件只在对话流程中附加。需要携带 `Parameter` 或串联多步剧情时，不要自行扩写，先让程序确认事件分发参数是否正确。

### 回调

```xml
<Callback>
    <Name>已有回调名称</Name>
    <Parameter>参数1</Parameter>
</Callback>
```

回调名会直接查 `_root.关卡回调函数`。不存在的函数或错误参数可能中断事件。策划日常维护不负责新增、重命名或迁移回调函数。

### 性能调控

`PerformanceControl` 当前支持：

- `Action=SetLevel` 配合 `Level`；
- `Action=Decrease` 配合 `Steps`；
- `Action=Increase` 配合 `Steps`；
- `Duration` 为保持秒数，缺失或非正时走程序默认；
- 可选 `Message` 显示提示。

它会影响整场运行性能，不应当只为剧情节奏随意使用。新增或调整必须由性能维护者复核。

## 16. 区域触发器 `Trigger`

`Trigger` 直接放在 `SubStage` 下：

```xml
<Trigger id="0">
    <Xmin>625</Xmin>
    <Xmax>900</Xmax>
    <Ymin>250</Ymin>
    <Ymax>720</Ymax>
</Trigger>

<Event>
    <EventName>TriggerPressed</EventName>
    <Parameter>0</Parameter>
    <Message>进入目标区域</Message>
</Event>
```

规则：

- 四个边界都可省略；省略的一侧不设限制。
- 玩家必须严格位于边界内部；等于 `Xmin/Xmax/Ymin/Ymax` 时不触发。
- 历史字段名写 `Y`，实际比较的是角色在地图纵深方向的坐标。
- 触发后发布一次 `TriggerPressed(id)`，然后该触发器从当前子图移除。
- `id` 会自动转型；`Event/Parameter` 应与它保持同一值。

触发器不是持续区域监听，也不会在离开后再次触发。

## 17. `CaseSwitch`：现存条件分支

`CaseSwitch` 保留了较强表达力，但当前实现会通过 `eval` 找函数并执行。因此它是高风险兼容语法，不属于策划可自由扩展的日常接口。

现役结构示例：

```xml
<Type>
    <CaseSwitch expression="_root.随机整数" params="0,3">
        <Case casevalue="0">兵种353</Case>
        <Case casevalue="1">兵种92</Case>
        <Case casevalue="2">兵种87</Case>
        <Case casevalue="3">兵种13</Case>
    </CaseSwitch>
</Type>
```

对象分支也可以返回一整组子节点：

```xml
<Instance id="1">
    <CaseSwitch expression="_root.难度是否达到" params="修罗">
        <Case casevalue="true">
            <x>1540</x>
            <y>370</y>
            <Identifier>装备箱</Identifier>
            <Parameters>...</Parameters>
        </Case>
        <Case casevalue="false">
            <x>1540</x>
            <y>530</y>
            <Identifier>资源箱</Identifier>
            <Parameters>...</Parameters>
        </Case>
    </CaseSwitch>
</Instance>
```

### 当前实际规则

- `CaseSwitch` 必须是包装节点的第一个有效子节点；不要在它前面放其他元素或注释。
- `expression` 当前会被 `eval`，然后作为函数调用。
- `params` 按英文逗号切分并自动转数字/布尔；没有引号、转义或嵌套参数语法。
- `casevalue` 同样自动转数字/布尔，与函数结果匹配。
- `<Case casevalue="default">` 是兜底，但解析器按物理顺序检查，所以 `default` 必须放最后，否则会遮住后续精确分支。
- 分支可以是一个文本值，也可以是一组对象子节点。
- 条件在关卡 XML 加载时求值，不会因为战斗中难度、任务或角色状态变化而自动重算。
- 表达式不存在时，当前实现可能把表达式字符串当返回值；表达式或被调函数抛异常时，整个关卡解析返回 `null`，不是只跳过坏分支。
- `params` 切分后恰好只有一个参数时，当前实现会先无参调用一次，再带参数调用一次；`params=""` 也落入这一分支。现存难度判断能够承受这一历史行为，但不要新增有副作用的单参数表达式或零参数表达式。

### 策划维护边界

- 可以在程序已确认的现存块中调整 `Case` 内的敌人、数量、坐标或掉落值。
- 需要新增同类分支时，由程序从 [郊区.xml](基地门口/郊区.xml) 的随机兵种模式或 [夺取材料.xml](副本任务/夺取材料.xml) 的难度模式提供并确认完整片段；策划只维护已约定的分支内容和取值。
- 不要自行填写新的 `expression` 函数路径。
- 不要把剧情文本、任意代码或运算式写进 `expression`。
- 不要把 `CaseSwitch` 放进 `TimePools` 或 `TimePoolRef`。

本轮只把现状和风险写清；`eval` 的安全替代、可视化编辑和统一规则注册仍冻结，尚未改变运行时。

## 18. 专项语法入口

以下能力已经有更窄的权威契约，本 README 只提供入口，避免同一规则在多处漂移：

| 能力 | 权威说明 | 代表关卡 |
|---|---|---|
| 跨子图计时池 | [GameStage 计时池](../../agentsDoc/data-schemas.md#gamestage-跨-substage-计时池) | [残垣断壁.xml](基地房顶/残垣断壁.xml)、[核电站.xml](地下2层/核电站.xml) |
| 地图资源箱 | [关卡地图资源箱声明](../../agentsDoc/data-schemas.md#关卡地图资源箱声明) | [夺取材料.xml](副本任务/夺取材料.xml) |
| 主线/任务链门控、一次性拾取 | [关卡进度门控与一次性拾取](../../agentsDoc/data-schemas.md#关卡进度门控与一次性拾取) | 按文档示例和现役任务关复制 |
| 屏外尸体保留 | [关卡敌人屏外尸体保留参数](../../agentsDoc/data-schemas.md#关卡敌人屏外尸体保留参数) | [黑铁会总堂.xml](黑铁会总部/黑铁会总堂.xml) |

## 19. 新增或修改关卡的推荐流程

### 19.1 调整数值

1. 找到入口 `__list__.xml` 和实际同名关卡 XML，确认改的是玩家真正进入的文件。
2. 在相同难度、相同玩法的相邻 `SubStage/SubWave` 中确认取值口径。
3. 只改目标字段，不顺手格式化整个大文件，不清理看似重复的历史节点。
4. 做 XML 语法检查和本次改动对应的专项检查。
5. 重启后从真实入口进入，至少覆盖改动难度、目标波次、结算和返回。

### 19.2 新增普通战斗关卡

1. 选择最接近的代表关卡复制并重命名。
2. 在同目录 `__list__.xml` 新增 `StageInfo`。
3. 保证 `Name` 与文件名完全相同，且不与其他目录重名。
4. 替换背景、出生坐标、兵种、奖励和玩家可见说明。
5. 删除不需要的回调、`CaseSwitch`、特殊参数和历史节点；不要保留“不知道做什么”的结构。
6. 检查所有资源路径、兵种 ID、物品名、出生点索引、事件参数和箱体数量区间。
7. 走静态检查和真实游戏入口回归。

### 19.3 新增外交入口或程序直载关卡

这会连接主时间轴帧、位置名、任务入口或代码路径，已超出纯 XML 日常维护。策划应提供地点、解锁条件、入口和返回需求，由程序/Flash 维护者确认接线后再落 XML。

## 20. 验证

### 20.1 XML 语法检查

检查单个文件：

```powershell
chcp.com 65001 | Out-Null
[xml](Get-Content -LiteralPath "data/stages/目录/关卡.xml" -Raw -Encoding UTF8) | Out-Null
```

检查整个目录的 XML 闭合性：

```powershell
chcp.com 65001 | Out-Null
$stageXmlFiles = Get-ChildItem -LiteralPath "data/stages" -Recurse -Filter "*.xml"
foreach ($stageXmlFile in $stageXmlFiles) {
    try {
        [xml](Get-Content -LiteralPath $stageXmlFile.FullName -Raw -Encoding UTF8) | Out-Null
    } catch {
        throw "XML 语法错误: $($stageXmlFile.FullName) :: $($_.Exception.Message)"
    }
}
```

这一步只证明 XML well-formed，不验证标签是否被运行时消费。

### 20.2 按改动类型追加专项检查

| 改动 | 至少运行 |
|---|---|
| `TimePools` / `TimePoolRef` | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/validate-stage-time-pools.ps1` |
| 地图箱声明 | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-audit-stage-chests.ps1` |
| 箱体素材/回调接线 | 在上项基础上追加 `tools/test-map-loot-wiring.ps1` 和对应独立 XFL 验证 |
| `保留屏外尸体` | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-offscreen-corpse-retention.ps1` |
| 关卡事件音效 | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-stage-event-sound.ps1` |
| 关卡敌方 roster 变化 | 运行 `node tools/derive-arena-meta-teams.js`，审查派生差异，再运行 `node tools/derive-arena-meta-teams.js --check` |
| 本 README 或其他治理文档变化 | `node tools/validate-doc-governance.js` |
| 任意文本改动 | `git diff --check` |

完整测试分层见 [测试指南](../../agentsDoc/testing-guide.md)。静态脚本通过不等于真实关卡业务验收。

### 20.3 真实游戏回归

按改动风险选择场景，但至少确认：

- 关卡能从玩家实际入口出现并进入；
- 正确难度下敌人种类、等级、数量和位置符合预期；
- 每一波能开始、能结束，不会提前清图或永久卡波；
- 事件/对话只触发一次，参数对应正确；
- 奖励界面显示并按概率分母、数量上限结算；
- 多子图能正确过图，计时池按预期延续/暂停/失败；
- 通关、失败、主动退出和返回目的地都正确。

纯 XML 修改通常只需重启加载，不需要为了“证明 XML 生效”去发布 `asLoader.swf`。只有同时修改 AS2、XFL 或 SWF 资源时，才按对应子栈的编译与发布规则另行验证。

## 21. 代表文件索引

| 想看什么 | 推荐文件 | 备注 |
|---|---|---|
| 基础多子图、拾取物、波次 | [新手练习场.xml](基地门口/新手练习场.xml) | 适合了解主结构，不代表所有现代专项契约 |
| 随机兵种 `CaseSwitch` | [郊区.xml](基地门口/郊区.xml) | 只复制已验证表达式 |
| 区域触发器 | [医院.xml](基地门口/医院.xml) | `TriggerPressed` 简单现例 |
| 计时池和单位事件 | [残垣断壁.xml](基地房顶/残垣断壁.xml) | 同时核对计时池专项文档 |
| 地图元件、箱体、难度分支 | [夺取材料.xml](副本任务/夺取材料.xml) | 结构复杂，不能整文件盲复制 |
| 性能调控事件 | [堕落城保卫战.xml](基地车库/堕落城保卫战.xml) | 只供性能维护者参考 |
| 屏外尸体保留参数 | [黑铁会总堂.xml](黑铁会总部/黑铁会总堂.xml) | 仅少量重要实例使用 |
| 教学、对话、跟随事件 | [教学关卡.xml](特殊/教学关卡.xml) | 程序直载特例，不是普通索引模板 |
| Rogue/历史根节点 | [生存战 备份.xml](副本任务/生存战%20备份.xml) | 仅用于考古，禁止作为新关卡模板 |

## 22. 常见故障

| 现象 | 优先检查 |
|---|---|
| 选关界面没有新关卡 | 是否加入正确 `__list__.xml`；一级目录是否在 `list.xml`；`Name` 是否重复；解锁条件是否满足 |
| 点击后找不到文件 | `Name` 与文件名是否逐字一致；是否放在索引所属目录；扩展名是否真为 `.xml` |
| 整关加载失败或空白 | XML 是否闭合；`CaseSwitch` 是否抛异常；函数/资源/兵种标识是否存在 |
| 改了但游戏仍是旧值 | `StageInfoLoader` 和关卡加载器有缓存；完全退出并重启后再测；确认实际入口 URL |
| 某难度不刷怪 | `DifficultyMin/Max`、`Quantity`、`Type`、`SpawnIndex` 和出生点容量 |
| 敌人生成位置不对 | `x/y` 是否覆盖出生点；`SpawnIndex` 是否越界；`Point` 物理顺序是否改变 |
| 波次提前结束 | `FinishRequirement` 是否过大；`NoCount` / `MapNoCount` 是否排除了应计数单位 |
| 波次永不结束 | 是否仍有被计数单位；`FinishRequirement` 是否为负；出生点计数和敌我属性是否异常 |
| 事件没有触发 | `EventName` 大小写；`Parameter` 数量、顺序和值；单位是否设置正确 `InstanceName` |
| 事件重复或顺序混乱 | 是否有多个同名同参数 `Event`；不要依赖书写顺序编排 |
| 区域触发器边缘不触发 | 边界为严格内部判定；检查角色纵深坐标和 `id/Parameter` |
| 奖励概率明显不对 | `AcquisitionProbability` 是分母，不是百分比；`1` 才是必得 |
| 计时池加载失败 | ID 格式、重复定义、未引用定义、未知引用、时长/名称限制、`CaseSwitch` 禁令 |
| XML 解析通过但功能无效 | 标签可能只是历史字段或拼写错误；对照本 README 的现役节点和实际消费源码 |

## 23. 维护边界

当关卡 XML 的节点名、字段语义、加载路径、测试入口或运行时默认值发生变化时，应在同一轮更新本文档。不要把某一张关卡的临时数值、当前文件数量或当前试点清单写成长期规则。

当前主要消费入口：

- [StageInfoLoader.as](../../scripts/类定义/org/flashNight/gesh/xml/LoadXml/StageInfoLoader.as)：一级/二级索引和 URL 拼接；
- [XMLParser.as](../../scripts/类定义/org/flashNight/gesh/xml/XMLParser.as)：自动类型、同名数组和 `CaseSwitch`；
- [StageInfo.as](../../scripts/类定义/org/flashNight/arki/scene/StageInfo.as)：`SubStage` 字段归一化与默认值；
- [StageManager.as](../../scripts/类定义/org/flashNight/arki/scene/StageManager.as)：场景、元件、出生点、拾取物、事件、触发器和计时池；
- [WaveSpawner.as](../../scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as)：波次、难度过滤、生成位置和结束计数；
- [StageEvent.as](../../scripts/类定义/org/flashNight/arki/scene/StageEvent.as)：事件动作；
- [通信_fs_lsy_XML数据解析.as](../../scripts/通信/通信_fs_lsy_XML数据解析.as)：具体关卡加载、奖励和 `StageManager` 初始化。
