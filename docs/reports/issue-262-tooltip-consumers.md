# Issue #262：Tooltip 消费者、输入与 AS2 闭包审计

**文档角色**：本专项现役消费者、输入与响应形状清单。

**最后核对代码基线**：commit `3a2f434ceea4c0a07bad3a915bd314921f0f6863`。

## 基线与结论

- 审计起点：`db6d3d248b80b80651987c99557c4e83b56f9301`。
- 起点 `tools/asloader-modules.json`：resident 1 类、shared 338 类、boot 464 类；Tooltip 登记 40 类全部属于 boot。历史 42 类／210.8 KB 不用作本次净收益。
- 所有现役 Tooltip 内容消费者都可以沿已有 C# 响应生命周期增强；没有必须让 Flash 等待 V8 的同步业务依赖。
- 两处同步值有特殊处理：ChoiceReward 的 `details` 随原批量快照生成；建角 `richItemCatalog` 原本检查 HTML 非空，改为检查输入完整，在原建角响应中批量增强。二者都不增加逐项 RPC。
- 装备结算、配件资格、来源发现集合、技能资源裁决仍由现役 AS2 领域服务决定。TS 只格式化冻结数据。

本报告记录源码调查与候选改动，不代表真实 AVM1／CS6 已执行通过。旧实现完整归档于 `tools/tooltip-oracle/as2/org/flashNight/gesh/tooltip/`，`tools/tooltip-oracle/baseline.json` 绑定原始文件哈希。

## 现役消费者矩阵

下表“旧内容”记迁移前消费方式；“同步用途”指内容返回值是否影响领域事务。所有外层 `success`、版本、request/call ID、revision、session、lease 与业务结果均保留，`tooltipInput` 只替换原内容生产位置。Host 在现有消息处理器和原有验证器之间消费输入，再将 `document` 及仍被 Web 使用的 HTML 片段送入原链路。

| AS2 入口／调用链 | 数据权威与 BaseItem | 同步用途 | 旧内容 | 身份／失效边界 | 候选切流状态 |
|---|---|---|---|---|---|
| `InventoryPanelService.executeTooltip → buildTooltipProjection` | `ArrayInventory` exact 槽位；装备为真实实例，堆叠为数值 | 无内容业务依赖；helper 成败仍同步 | HTML + Document | 容器对象、mutationRevision、槽位对象、lease、堆叠数量／merge key | helper 冻结实例输入；C# 原库存响应增强 |
| `CharacterBuildService.executeTooltip` | 当前穿戴装备／药剂槽真实对象 | 投影成功后继续复核真实对象与两个 revision；该复核保留 | HTML + Document，exact shape | panelInstanceId、sessionGeneration、loadoutRevision、drugRevision、slotKey/drugSlot | payload 透传输入；Host 增强后沿原 exact validator |
| `RewardInboxService.executeTooltip → buildTooltip` | 奖励记录中的 exact 实例 | 无 | 嵌套 tooltip 的 HTML + Document | lootContainerId、记录 authorityRevision、slot lease、引用／版本／签名 | 共用库存 helper，原 `tooltip` 节点增强 |
| `LootContainerService.executeTooltip → buildTooltip` | 战利品容器 exact 实例 | 无 | 嵌套 HTML + Document | active identity、expectedAuthority、slot lease | 共用库存 helper；原容器响应增强 |
| `LootContainerService.executeReportTooltip` | 冻结结算流水引用，或当前材料白名单；名称级预览 | 无；读取不领取／不保存 | COMMON HTML + Document | 同一结算容器身份／authority，flow index 或材料白名单 | 保留引用校验；公共预览输入透传 |
| `RewardStashService.tooltip` | 持久化条目经 clone 后构造 detached BaseItem | 无 | 库存 helper 返回包 | storeId、entryId、entry revision；pending 时读取 before 快照 | 已完整转发 helper 对象，不需另设入口 |
| `EquipmentTuningService.executeTooltip` | 已签发 candidateKey 对应静态候选；before/after 仍由原试算器算 | HTML 不参与装配／提交；独立 stats 试算保留 | 分段 HTML + stat preview | view session、candidateKey；提交另作 exact 校验 | 候选输入 + 原 stat preview，同一响应增强 |
| `ChoiceRewardService.snapshot` | 冻结奖励选项；每项由原 detached BaseItem 构造 | 原 `details` 只供展示；不决定选项／领取 | `intro+desc` 转纯文本、最多 4096 字符 | 原奖励 store／offer 身份、快照 revision | 项目内 `output:'details'` 输入，Host 一次响应批量增强；投影 null／异常仍保留 details 选择器，失败只替换 details |
| `MercPanelService` 装备预览 | 佣兵配置构造的预览实例 | 无 | 库存 helper HTML + Document | 原请求 token、佣兵选择／装备索引 | 明确 DTO 透传输入 |
| `MercPanelService → MercLoadoutService.buildWeaponTooltip` | 佣兵实际当前长枪；原领域 helper 读装备 | 无 | 库存 helper HTML + Document | 原目标身份与武器槽校验 | 复用 helper；面板 DTO 透传输入 |
| `ArenaPanelService` 装备预览 | 竞技场目标配置构造的预览实例 | 无 | 库存 helper HTML + Document | 原 token／目标与装备索引 | 明确 DTO 透传输入 |
| `PetPanelService → ManagedLongGunService.buildWeaponTooltip` | 宠物／托管长枪领域数据 | 无 | 库存 helper HTML；原响应未附 doc | 原宠物目标／槽位校验与请求 token | 输入透传；Host 增加 Document，原任务为 raw passthrough |
| `CraftingPanelService.handleTooltip` | 当前配方页面允许的物品名称 | 无 | COMMON HTML + Document | 原视图与请求 token／名称校验 | 公共预览输入透传 |
| `ModifierPanelService.handleItemTooltip` | modifier 面板允许的物品名称 | 无 | COMMON HTML + Document | 原 session/token 与名称校验 | 公共预览输入透传 |
| `TaskPanelService.handleTooltip` | 任务物品名称；ItemUtil 元数据 | 无 | COMMON HTML + Document | 原任务请求 token／名字校验 | 公共预览输入透传 |
| `商城系统_WebView.as`：shop / intelligence / blackmarket Tooltip | 现役商店、情报、黑市展示目录中的名称 | 无；购买／刷新权限仍由独立业务入口决定 | COMMON HTML | 既有商店请求／目录身份 | 三个响应均透传输入 |
| `商店系统_兼容.as`：NPC Tooltip | 商店预览为名称；背包来源委托 exact 库存入口 | 无 | COMMON 或库存 HTML + Document | NPC 会话、原 token；背包 lease 仍在库存服务校验 | 原两种来源维持，响应透传输入 |
| `neur/Server/CharacterCreationService.richItemCatalog` | 建角允许装备目录；detached BaseItem | 原先 HTML 非空作为目录可用性检查，不是装备资格 | 批量 HTML；启动器目录 exact validator | 建角请求／启动流程会话；受限 outfit identifiers | 改检查 tooltipInput，Host 在 character_create_response 批量增强；Web 接收 Document |
| `_root.物品图标注释` | 既有传入 BaseItem 或名称级预览 | 返回值只控制显示 | `TooltipComposer → NativeTooltipDocument` | NativeInteraction requestId/sceneId、anchorRect/placement；hide/teardown | `forItem → NativeTooltipBridge.show(input)` |
| `_root.技能栏技能图标注释`、`_root.学习界面技能图标注释` | 当前主角技能数组／技能表 | 只显示 | SkillTooltipComposer + Document | NativeInteraction 身份／hide | 只投影技能表允许字段及当前状态 |
| `_root.注释` | 调用方已存在的短正文 | 只显示 | 通用 HTML→Document | NativeInteraction 身份／hide | `kind:'body'`，由唯一 TS Document parser 转换 |
| `PlayerHudService.showHover` | 实际动作配置、技能、武器战技、药剂、readVitals 快照 | 不参与战斗／技能执行；资源 hint 仍由 SkillResourceService 判定 | HUD 内联文案／HTML + Document | HUD owner/hoverRequest、sceneId、anchorRect；hide/切场景 | skill/item/hud 输入；文案迁 TS；保留原 hint/state |

公共名称级入口 `_root.Web物品注释HTML` 暂保留调用名，但返回内容只有元数据、空 HTML 占位和输入。所有现役调用者都显式转发输入，不存在继续依赖该函数同步产出 HTML 的生产消费者。通用正文入口不保留装备／药剂／HUD 文案规则；它仅接受调用方已经提供的正文。

### 重要的非 Tooltip 消费者

`EquipmentStatProjector` 仍引用 `ItemUseTypes` 和 `TooltipConstants` 的属性词汇、排序表及六个标签。该模块产生调制台 before/after 属性投影，属于本轮保留的现役领域投影。因此保留两个叶子类，不能为追求零残留把调制计算再实现到 TS。它们不保留 Tooltip 内容 Builder 或 HTML renderer。

## TooltipInput v1

输入仅为数据；请求／面板／容器身份仍留在原响应信封。`version` 固定为 `1`，生产 `kind` 仅有 `item | skill | body | hud`。没有 `tier`／`enhancement` 历史显示入口，也不保留第二套同步 fallback。

```ts
type ItemInput = {
  version: 1;
  kind: 'item';
  itemName: string;
  value: number | {
    level?: unknown; tier?: unknown; mods?: unknown[];
    count?: unknown; amount?: unknown; num?: unknown;
    stack?: unknown; quantity?: unknown;
  };
  presentation: 'native' | 'inventory' | 'web';
  output?: 'details';
  projection: {
    isEquipment: boolean; isMaterial: boolean; isInformation: boolean;
    calculated: null | {
      description?: unknown; displayname?: unknown; icon?: unknown;
      use?: unknown; weapontype?: unknown; actiontype?: unknown;
      data?: unknown; skill?: unknown; subweapon?: unknown; lifecycle?: unknown;
    };
    baselineData: unknown;
    mods: Record<string, {
      present: boolean;
      useCases: unknown[]; bulletCases: unknown[]; skill: unknown | null;
    }>;
    tierOptions: unknown[]; drugEffects: unknown[];
    subweapon: unknown | null;
    electric: boolean; isVerticalBullet: boolean;
    registeredModName: string | null;
    obtainRecords: unknown[];
    levelMultiplier?: unknown;
    bladeCount?: number;
    displayName?: string; iconName?: string;
  };
  hud?: {kind: 'drug'; count: number; slot: unknown; key: string};
};
```

“最小”指只传一个当前物品及现役格式规则真正读取的依赖；`data`、`lifecycle` 内保留该物品的现有语义树，避免在 AS2 复制每个特殊机制的字段清单。任意 BaseItem 方法、缓存、交易数据、整个 ItemUtil/mod/source 字典均不传输。

| 投影字段 | 保留的实际权威与选择规则 | TS 可以做什么 |
|---|---|---|
| `calculated` | 真实 `BaseItem.getData()` 结果；一次 forItem 内只调用一次；失败返回失败，不能悄悄改成基础预览 | 读取数据／格式化；不得重算强化、升阶、装备或配件效果 |
| `baselineData` | `TooltipDataSelector.getEquipmentData(itemData,value.tier)` 的实际基线；所有有 data 的非药剂物品均投影，包含战场医疗包等非装备 | 与真实计算值对照并显示；不自行推导 tier |
| `levelMultiplier` | 当前 `EquipmentUtil.levelStatList[level]` | 保留原强化显示口径 |
| `mods[name]` | 既有 ModRegistry `buildItemUseLookup`、`matchUseSwitchAll`、`matchBulletSwitchAll`、`resolveSkillForUse`，包含 grantsUseDict | 用已匹配分支输出说明；空数组明确无匹配；`present:false` 不得从静态目录复活效果 |
| `registeredModName` | 原 standalone mod 名称／displayname／trim 查询取得的实际注册记录 `name` | 按已注册 key 读静态说明；null 表示没有运行态注册资格 |
| `tierOptions` | `TierSystem.getAllTierOptionsByName`；所有非适用物品显式 `[]` | 排列并格式化已有方案，不实施升阶裁决 |
| `electric` | `TagManager.buildPresentTagsDict` 对当前 mods 与 calculated 的真实电力结果 | 显示灯光启用语义 |
| `subweapon` | `SubweaponDataUtil.normalizeSubweapon`；包含 standalone mod 的 subweapon | 格式化归一化结果 |
| `drugEffects` | `DrugEffectNormalizer.normalize(itemData.data)`；不适用显式 `[]` | 药效说明，不重算治疗／Buff 运行态 |
| `isVerticalBullet` | 原基线 bullet 经 `BulletTypeUtil.isVertical` | 保留枪械说明分支 |
| `obtainRecords` | `ItemObtainIndex.isIndexBuilt/getObtainRecords` 的**当前已发现集合**；冻结当前敌人 displayname；只传 kind、来源身份／类别与现役成本显示字段，省略概率与 exact variants | 按原排序／截断规则格式化；不得用全量来源表替代玩家发现进度 |
| `displayName/iconName` | 库存 helper 原 `buildItemProjection` 的标题／图标身份 | 仅 Document 最终身份；基础 introHTML 保持原口径 |
| `bladeCount` | 配置为正时直接读配置；否则极窄 Flash linkage 探测 | 只读数量，不模拟显示列表 |

wire 保留 AS2 数值差异：非有限数使用单键 `{__tooltipNumber:'NaN'|'Infinity'|'-Infinity'}`；数组空洞／undefined 使用 `{__tooltipUndefined:true}`；对象 undefined 属性省略，显式 null 保留。TS 在整个 TooltipInput 边界递归解码严格单键标记，以覆盖技能元数据和当前等级的非有限值；正文 HTML 字符串不会解释为标记。复制过滤函数、MovieClip、内部引用；`__modName` 是灯光生命周期所有者信息，必须例外保留。深度超过 16 时投影失败，不能无限追踪对象环。

技能输入包含 `mode:'loadout'|'learn'`、skillName 和允许的技能表字段：`Name,Type,MaxLevel,UnlockSP,UpgradeSP,CD,MP,UnlockLevel,Description,Equippable`。loadout 另带实际 `state:{level,equipped,enabled}`；HUD 可带 `resourceHint:{state,reason}`，由原 SkillResourceService 判定。

HUD 输入为 `kind:'hud',mode,data`：action 的 name/keyLabel/description；weapon 的 name/cooldown/mp/hp/sp/description/information/resourceHint；switch 的 bank/switchKey/otherBankHasStock；resources 的 hp/mp/shield/shieldReady/shieldPresent/poise/experience/sp。cooldown 保留原毫秒数。它们是原 HUD 快照的窄子集，无新增战斗读取路径。

`kind:'body'` 包含 `html` 和 `profile:'simple'|'dense'`。HTML 受限解析、清洗及 Document 布局语义仍由唯一现役 TS 内容引擎和既有 sanitizer 完成。

## 静态目录与动态数据的划分

`tools/build-tooltip-catalog.py` 根据现役 XML loader 的列表顺序构建 `data/tooltip/tooltip-catalog.json`，同时生成源文件与结果哈希 manifest。目录包含 items、mods、recipes/recipesUsing、显示用 magicDamageTypes，以及内容版本等字段；C# 启动加载并缓存。保留 authored 顺序，不用目录遍历次序代替 loader 次序，不执行运行态 CaseSwitch。目录转换是只读数据烘焙，不执行装备结算。

完整静态 catalog 不随 hover 发送。玩家发现过的 stage/enemy/quest 来源、实际配件资格与条件分支、升阶方案及真实实例计算结果始终由 AS2 投影；静态 catalog 不作为它们的运行态 fallback。每次请求仅传一个物品的语义闭包；奖励与建角将多个窄输入放在原有批量响应中。

## Flash 专属例外

刀口数保留在 `TooltipInputProjection` 中：先用基线 `bladeCount>0`，再尝试 dressup linkage，最后尝试 `刀-<icon>`。沿用 `_tooltipTempContainer`、最多四层、最多六个刀口和 linkage 缓存；临时 MovieClip 使用后清理。这里只输出一个整数，不生成文字。离线素材提取可以后续替换该探测，但本轮没有伪造资源解析结果，也没有扩大 Flash 模拟器范围。

## AS2 生产闭包裁撤清单

| 保留项 | 原因 |
|---|---|
| `NativeTooltipBridge` | requestId/sceneId、坐标与 anchorRect/placement、hide/teardown 交互生产者；发送 Input |
| `TooltipInputProjection`（新增） | 上述动态只读投影、数值 wire 编码与极窄刀口探测 |
| `TooltipDataSelector` | 现役升阶基线选择，禁止在 TS 重建业务权威 |
| `ItemUseTypes` | EquipmentStatProjector 现役词汇依赖 |
| `TooltipConstants`（收缩） | EquipmentStatProjector 现役排序／标签依赖 |

原 40 个已登记类中保留 4 个，移除 36 个，另新增 1 个，候选净减 35 个。裁撤包括 TooltipComposer、TooltipTextBuilder、TooltipFormatter、NativeTooltipDocument、SkillTooltipComposer、TooltipBridge、TooltipLayout 与全部内容 builder（含 drug composer/registry/interface/builders）。未登记旧测试也从生产 classpath 移出，留在隔离 oracle 目录。具体 manifest 派生检查、源字节对账及最终类名列表由本次闭包审计回执记录；这不是已编译 DoInitAction 或虚拟内存收益。

## 异步切流与失败语义

AS2 先执行原 exact 业务身份校验，再冻结输入并同步返回原响应。C# 在该响应的原回调生命周期内调用 TooltipService，不回调 Flash 补文案。原业务操作结果、领域版本与事务证据保持不变；内容失败只标记显示不可用，不能把已提交业务重放或抹掉。Native hover 同样提交 Input 与原身份，hide／场景退役能够先于计算完成；结果交付前仍检查 owner/request/scene 是否有效。

Host 目录版本和冻结动态输入共同参与内容缓存键，展示身份仍由原外层信封拥有。同名不同实例、数量、技能状态、已发现来源、runtime 配件资格不能合并为名称级缓存。普通 hover 与固定 Inspector 的生命周期分开处理，防止鼠标活动清除主动固定内容。独立 Logic V8 不进入 GameInput 的逐帧锁路径。

## 证据分层与新增真值计划

| 证据 | 本轮用途 | 不能证明的范围 |
|---|---|---|
| 原 AS2 源码 byte-exact 归档 + 哈希 | 可重现旧算法／离线 oracle 工程来源 | 未执行代码不等于新鲜 AVM1 输出 |
| `tools/tooltip-parity-corpus.js` 及已有 parser corpus | Document parser 已有受限 HTML、实体、布局等回归 | 不证明 Builder 内容、实例投影或最终 UI 全等 |
| TS engine 单测 | 静态规则、异常输入、数值标记、新机制、确定性 | 不能用 TS 自产期望声称 AS2 等价 |
| `tools/test-tooltip-input-projection.js` | 执行实际两份 AS2 producer 函数体的语法降级版本，领域 stub 验证窄数据、detach、真实 getData、原 matcher 调用、发现集合、mod 拒绝、native 身份 | JS 不是 AVM1；MovieClip stub 不是实际 linkage；目前 10 个用例通过 |
| 现役 AS2 focused tests | InventoryTooltipProjectionTest、InventoryPanelServiceTest、CharacterBuildServiceTest、EquipmentTuningServiceTest、NpcShopPanelServiceTest、LootContainerServiceTest、CraftingPanelServiceTest、ChoiceRewardServiceTest 已改为输入契约 | 云端未运行 TestLoader，需新鲜 CS6/AVM1 |
| C# 核心／Fake Socket 与 Web 回归 | 原响应增强、失败保留业务结果、身份／过期处理、展示 adapter | 不等于 Windows ClearScript 或玩家入口已验收 |

Windows 新鲜语料至少覆盖：真实强化／升阶／配件实例与基础物品差异；灰蛊、灰蛊蚀刻等最新命中机制；无效 runtime mod 与 catalog 同名条目；use/weapontype/grantsUse/bullet 分支；灯光 `__modName` 所有者与电力禁用；配置／资源探测刀口数；药剂归一化及 HUD 快捷键／数量；技能已学、装备、停用、资源不足；ItemObtainIndex 未就绪／不同发现进度／敌人显示名；null/undefined/非有限数／数组空洞与枚举顺序；CharacterBuild 读取期间 revision 漂移；批量奖励 details 和建角目录。

执行入口：现役 focused test 的 `runAllTests()`／原 TestLoader 流程；归档 TooltipGroundTruthDump／TooltipCorpusDump 仅在**隔离 oracle 编译 classpath**采集旧内容，不重新塞进生产 asLoader。候选三模块新鲜构建后，再跑玩家正常装备／药剂／技能、库存、调制、奖励、佣兵、宠物、竞技场、商店、任务、制作、建角悬停；观察旧请求迟到、hide 先行、切场景、换装／改配件、lease 失效、断线／Host 重启以及固定 Inspector。验收要对照实际 Document/HTML 与可观察 UI，并记录 AVM1 编译、DoInitAction、Logic SWF 字节、编译时间及 PeakVirtualSize。

## Host/Web 响应形状复核

覆盖 `TooltipResponseEnricher.ResponseTasks` 全部 **17 个响应域**，逐项核对现役 AS2 输入位置、Host 领域验证／净化和 Web 接收路径。下表的“可接受”是源码层面的形状结论；除表后列出的专项外，未把各域逐一经过真实 Flash 回包，也未执行 Windows 玩家入口。

`TooltipResponseEnricher.ApplyProjection` 在 `tooltipInput` 所在对象原位替换：普通模式只写 `document/introHTML/descHTML`，`output:'details'` 只写 `details`，两者均删除内部输入键。普通 Document 先经 `TooltipService.ValidateProjection → TooltipDocumentSanitizer`，宽透传领域也有这道共用净化。原 `success`、身份、revision、lease 和业务结果不因显示失败改变。

| 形状类别／响应域 | 实际字段位置与关键验证入口 | 复核结论 |
|---|---|---|
| 严格：Inventory | 根 `document`；`InventoryTask.TryNormalizeCharacterTooltipResponse` | 明确允许可选文档并 `ApplyTo`；Web candidate-tooltip 精确白名单也允许文档，owned view 透传。 |
| 严格：Shop／KShop | 根 `document`；`ShopTask.TrySanitizeTooltipSuccessLocked`；Web `KShopProtocol.sanitizeResponse` | Host 已允许并净化；本轮补 Web 的可选文档白名单与对象形状，仍保留 idx 和三身份的实际目录绑定。 |
| 严格：Crafting | 根 `document`；`CraftingTask.IsAuthoritativeTooltip/TrySanitizeResponse` | 可选文档经净化，原 `displayname → displayName` 转换保留；Web runtime 校验名称回显，rich renderer 传递文档。 |
| 严格：EquipmentTuning | 根 `document`；`EquipmentTuningTask.HasOnlyResponseKeys/SanitizeFlashResponse` | 本轮补 tooltip 成功分支白名单与共用净化；原候选、source、lease、stats 校验不变。Web runtime 不拒该增量键，renderRich 已透传。 |
| 严格：CharacterBuild／loadout | `payload.document`；`CharacterBuildTask.TryNormalizeTooltipProjection`；Web `validTooltip` | Host 原有可选文档与净化，外层只增加既有 `payload`；本轮补 Web 精确白名单，target／revision／HTML 门值仍成立。 |
| 严格：Loot／奖励收件箱 | `tooltip.document`；`LootTask.TrySanitizeTooltip` | 原根级 ResponseKeys 没有变化；嵌套六字段允许可选文档并净化。Web Loot mux 只精确检查外层，view 读取嵌套文档。 |
| 严格：ItemUse 暂存 | `data.tooltip.document`；`TrySanitizeStashResponse` | `data` 仍精确为 success＋tooltip；内部允许可选文档并净化。Web stash transport／source 原样保留 tooltip 属性。 |
| 严格：ItemUse 自选礼包 | `data.offers[].options[].items[].details`；`TrySanitizeChoiceSnapshot` | details-only 不增加 document／HTML，符合原六字段 item 行。AS2 无效输入也保留 `output:'details'`，失败占位不会破坏行形状。 |
| 严格：CharacterCreate 建角 | `appearanceCatalog.{upper,lower,footwear}.{male,female}[].document`；`GameLaunchFlow.IsStrictCharacterCreateAppearanceRows` | 行白名单允许可选文档，出现时严格净化；`appearanceRows` 显式保留，建角 rich renderer 透传。catalog／性别容器层级不变。 |
| 选择字段：NpcShop | 根 `document`；`NpcShopTask.TrySanitizeTooltip` | 先校验已有身份／HTML，再 CopyResponseKeys＋ApplyTo；Web identity validator 不拒文档，secondary-pages renderer 使用文档。 |
| 选择字段：Modifier | 根 `document`；`ModifierTask.ValidItemTooltip` | 明确接受可选对象；前置服务已净化。Web `normalizeItemTooltip` 保留文档，window rich renderer 使用。 |
| 宽透传：Merc | 根 `document`；`MercTask.HandleFlashResponse` | 实际 pending 完成后只改信封；装备／托管长枪 Web 缓存与 renderer 保留文档。 |
| 宽透传：Pet | 根 `document`；`PetTask.HandleFlashResponse` | weapon_tooltip 只改信封，Web 长枪 renderer 保留文档；pet_tooltip 进阶方案正文没有 TooltipInput，保持原响应。 |
| 宽透传：Arena | 根 `document`；`ArenaTask.HandleFlashResponse` | tooltip 不经过 snapshot 专用形状分支，保留文档；challenge browser 明确传递文档。 |
| 宽透传：Task | 根 `document`；`TaskTask.HandleFlashResponse` | 原 pending 身份完成后只改信封；task-panel 缓存／回调和 renderer 均保留文档。 |
| 宽透传：Intelligence | 根 `document`；`IntelligenceTask.ForwardPassThroughResponse` | tooltip 进入实际透传分支；intelligence-panel 将文档交给共享 renderer。 |
| 宽透传：BlackMarket | 根 `document`；`BlackMarketTask.ForwardPassThroughResponse` | 揭晓物品 tooltip 进入透传分支；Web `buildRevealTipHtml` 保留文档，观测专用响应未被改写。 |
| 当前无输入：Skill | `SkillTask.SanitizeFlashResponse` | allowlist 中有该域，但现役 skill_response 没有 TooltipInput；技能悬停走 Native 路径。不能把该项计为已执行的 Web 技能文档回包。 |

失败占位的 `introHTML="注释暂不可用"` 和 `descHTML="注释暂不可用。"` 均非空，文档包含合法 body/runs；因此满足建角“两字段非空”和 CharacterBuild“不能同时为空”的旧门值。details-only 使用同一非空短正文，满足 4096 字符限制。这里核查的是生成失败时的合法显示形状，不放松原业务失败响应的 exact-shape。

缺口归因以起始提交 `db6d3d248b80b80651987c99557c4e83b56f9301` 的实际 producer 为准：原 Tuning 和 KShop 成功响应均不含 document，本轮增强首次加入文档，分别触发旧 Host／Web 白名单拒绝，现已补齐。原 CharacterBuild AS2 已写 `payload.document`，Host 也已 `ApplyTo`，但 Web 固定八字段，因此这是既有接缝缺口，不能记成本轮新引入。

专项验证边界：

- `node tools/test-character-build-session.js`：**43/43**；执行现役 session／mux／validator，覆盖装备与药剂可选文档、错误类型、额外键、target 和 HTML 拒绝。回包为协议 fixture，不是 Flash 捕获。
- `node tools/test-kshop-presenters.js`：**41/41**；执行现役 `KShopProtocol.sanitizeResponse`，覆盖文档保留及 idx／三身份／额外键／失败形状仍被拒绝。修复前同一个有效回包仅新增 document 就返回 null，已实际复现。
- `launcher/tests/TooltipService.Host/EquipmentTuningIntegration.cs` 链接真实 Task、pending、snapshot／candidate／lease 验证和 V8，覆盖生成成功、内容失败、文档净化／剥除及未知外层键拒绝；fixture 只替换 Flash 传输与平台呈现，执行结果以该 Host 专项回执为准，不能推广为全部 17 域均已实测。
- 其余域本节仅记录源码复核。Windows CS6／AVM1 fresh paired oracle、实际 Socket→WebView2 消费和各玩家入口悬停仍待执行；本节不新增这些验收结论。
