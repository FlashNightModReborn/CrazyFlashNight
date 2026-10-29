# 随机自选礼包

核对代码基线：commit `e959fb94cbb72d2e5c9a781c68b1f9b7eb4ba643` 加当前61路线工作树；本轮验证状态见[61施工记录](../../docs/闪客快打6肉鸽-61路线施工与验证-2026-10-26.md)。

`choice-rewards.json` 是基础候选内容和抽取规则的编辑源；章节附加源显式登记在 `tools/choice_reward_catalog.py` 的 `BOOK_SOURCES`，史实片段为 `data/stages/books/cf6-sting-source/choice-rewards.fragment.json`，61片段见下文。生成器按基础目录、章节目录顺序合并，拒绝身份冲突；不会改写基础目录。`tools/build-choice-rewards.py` 生成 AS2 目录、`data/items/消耗品_自选配给.xml` 和 `choice-rewards.generated.json`；最后一份是奖励包与档色静态门共用的合并投影，依靠生成器 `--check` 核对来源，运行时不另加载。生成物不能手改。

## 当前能力

61章节附加源为 `tools/cf6-type61/choice-rewards.fragment.json`，与史实片段一同显式登记在 `BOOK_SOURCES`，各自命名空间独立；编辑和生成顺序见[61内容入口](../../tools/cf6-type61/README.md)。61定向配给从 `type61.deliveryItems` 交付，A04原枪替换盒从 `a04ReplacementPacks` 交付，不叠加史实旧配给。

每次打开一个礼包，从各组按权重无放回抽取，共展示 2–4 套，玩家选 1 套；`chooseCount=1`、`rerolls=0`。礼包不能批量打开。同一存档最多保留 16 个待选礼包，达到上限拒绝开包且不扣物品。

修理大学前六图各投放一次：第一图功能技能，第二图完整构筑，第三图协同，第四图进阶构筑，第五图技能提升，第六图决战补给。两次大配给之外的四次小选择不重复发放大套装。第二图的免费候选保底一套 AK47＋蓝下挂＋对应弹药；第四图的下挂转向同样附 AK47。两池版本升至 4，旧冻结候选不变。

短枪构筑按双持配给：当前 UZI、M79 各两把，UZI 插件两份，对应枪械弹药各24份。作者以 `weaponCount:2` 指定，生成器拆为两个独立装备实例，不把数量误作强化等级；旧凭证兑换包同步生成双持内容。

技能卡直接授予指定等级，或提升到该等级，不增加 SP、不退还之前花费的 SP。纯被动按技能服务原规则启用，主动技能保留原快捷栏，由玩家自行装备。已达到或超过奖励等级的技能在抽取前排除；开包后状态变化只会使原候选不可领取，不重抽。纯装备候选已持有全部内容时也排除；消耗品补充仍可出现。

付费卡价格为 300、700、1100 K点，确认时才收费，每个礼包仍只选一张；免费选项一直保留。定价和授技只允许 book scope，不接受客户端指定价格或等级。局内 K 预算与掉落时机编辑书籍配置，见[构筑说明](../../docs/bookshelf-player-context.md#配给选择与枪械转向)。

## 配置字段

| 对象 | 字段与限制 |
| --- | --- |
| 顶层 | `schema=choice-rewards.v1`，`bundles` 为 1–128 套，`pools` 为 1–32 池 |
| bundle 公共字段 | `id`、`name`、`title`、`description`、`grade`；ID 稳定唯一，展示文案不作为领取身份。`grade` 为显式声明的封闭枚举 `low`/`medium`/`high`/`special`（低级/中等/高等/特殊）：初阶 `low`、进阶 `medium`、高阶（3级精进技能）`high`；`special` 金档是正交类目，只能显式声明、不可由价值派生。价值轴派生阈值待汇率口径裁决，落地前全部显式声明 |
| 武器构筑 bundle | `weapon`、`mods`、`consumables:[{name,count}]`；短枪须附 `weaponCount:2`，其他武器缺省1且只许1；插件按武器数量配齐，消耗品数量是整套总额。检查真实装备等级、插件用途/子类/前置/互斥/槽位容量以及主枪、下挂弹药 |
| 通用物资 bundle | 用 `items:[{itemName,quantity}]` 替代上述三个构筑字段，最多 16 项；可放药剂、防具、材料等目录中的实体物品，装备数量只能为 1，其他物品为 1–9999 |
| bundle 可选效果 | `skills:[{skillKey,level}]` 最多两项，名称和等级需在真实技能目录内；含技能时 `items` 可为空。`kCost` 为 0–1200 整数，缺省 0；二者仅允许 book scope |
| pool | `id`、正整数 `version`、`title`、唯一 `itemName`、`scope`、`maxItemLevel`、`chooseCount`、`rerolls`、`groups` |
| scope | 普通角色用 `{kind:"character"}`；书中局次用 `{kind:"book",bookId:"repair-campus"}`。61用 `{kind:"book",bookId:"cf6-sting",routeId:"type61"}`，要求书籍、路线和局次仍 active；CF6缺省路线只属于 `historical` |
| group | `id`、`draw`、`entries:[{bundleId,weight}]`；组内最多32项，权重为 1–10000 的整数，抽取量不能超过组内数量，各组不可重复引用同一 bundle |

不支持金币、SP、经验的伪物品直写；这类效果继续走现有成长/消耗品系统。候选产出中的礼包不会递归打开。

61的A04主枪卡在首次开包时优先避开已持有同名主枪，持有范围包括背包、装备、仓库、战备箱和奖励暂存。替代品只取自现有A04枪池，须未持有、当前等级可装备，且按61未强化基础标价25%的售卖规则计算，不低于原选项价值；优先取价值最接近者，同价候选等概率选择。同一箱保留其他未持有选项，替代品之间不重复。候选耗尽时保留原选项，有限枪械配额不缩水，也不额外发第二份枪。双枪、插件与混合物资包保持各自原规则；已经冻结的选项在重开、查询、重载或领取时不再替换。`checkpointAmmo:true`仅允许 `cf6.type61.*` 武器构筑且 `consumables` 为空，弹药由章内独立配额负责，不能用于其他目录绕过主副弹药校验。61插件箱至少须有一个现役装备可安装的候选，中级箱要求枪械宿主；无合法宿主时以 `no_eligible_choices` 明确取消，物品不消费。

书籍配置 `buildChoices` 保存两次大配给，`minorChoices` 保存四次小选择。两者只保存掉落时机、`poolId`、`choiceItem`、等级上限和旧凭证名。书籍生成器只将原有 `campus.initial.1–4` / `campus.advanced.1–4` 投影为旧凭证四选一配方；通用 `items` bundle 只走随机选择领取，不拓展旧凭证兑换能力。弹药包仍由 `data/stages/books/repair-campus.json` 的 `ammoBundle` 编辑。

## 存储与领取

史实CF6 使用独立书籍 scope 和 `chapter.economy.choices` 投放身份；接口见[经济输入合同](../../tools/cf6-prototype/economy-input-contract.json)。史实已满技能不得进入候选，首版卡片免费，且每次开包至少保留两个不受装备持有状态影响的补给候选；技能候选失效后可按现役规则从三张缩为两张。E1—E5 精英仍独占；普通随机与自选礼包允许共享候选，每个池内去重。CF6 每池从当前等级可用武器形态与补给/技能候选中抽三项，版本2；继续使用原目录容量且不增加每轮展示数。编辑源先生成自选目录和道具，再装配章节，最后运行书籍生成器；新增的静态门为 `python tools/test-cf6-economy.py`，真实 AVM1 计划验证为 `scripts/run-cf6-economy-tests.ps1`，其通过不替代真实开包、购物或完整路线体验。

1. 第一次打开：AS2 检查来源槽、租约、存档和局次，扣一个包并生成完整候选，在同一次 full save 保存 `_saveExt.rewardInbox.choiceOffers`。保存成功后才展示候选。配置中的权重、内容、种子或数量不接受 Web 提交。
2. 选择：Web 只提交 `storeId/expectedRevision/operationId/offerId/optionId`。AS2 校验冻结候选属于当前存档/局次，先校验冻结价格、K余额和技能可提升性，再将选中物资按现役接收规则优先放入背包或材料栏，装不下的条目加入暂存、授予指定技能、扣除K点并删除整个 offer；全部在同一次 full save 完成。技能领域保存前像，明确失败时与物品、K点一起回退；结果未知时普通技能改动也被锁定。
3. 未知结果：复用 ItemUse/RewardStash 的写锁和同 operation 查询；刷新列表、关闭窗口、重新打开均不能解锁或重抽。明确保存失败恢复全部前像。首次建立暂存库的空 storeId 写若重发会拒绝为 stale，恢复通过原 operation 的 query；已有库的 exact 重复写返回原回执。

领取提交确认后，Web 重新读取选择列表和同一暂存库摘要；两者都无待办且通道空闲时自动返回构筑。有其他选择、溢出物资、读失败或未知结果时保留处理入口。单纯打开或刷新空列表不触发自动返回。

Web 的“更新领取状态”只重读候选、K点余额及领取资格，不重新抽取；页面明确说明候选已固定、可在本局内稍后选择。读取期间显示进度并禁用重复读取与领取，手动读取成功且候选不变也明确反馈；失败显示“重试读取”且禁止凭旧数据领取。领取结果未知时，普通读取不覆盖待核对提示、不解锁写入，仍须通过“核对领取结果”处理原操作。

候选使用独立单调 offer ID，保存冻结的完整物品实例、技能等级和K点价格；后续配置调整不改已经抽出的候选。书中绑定临时槽、书籍 ID、seed 与 startedAt；CF6另绑定闭合枚举 `routeId`，旧候选缺该字段等价史实路线，不能由61领取。换普通存档、路线或开启另一局不可领取。此持久性保护不代表肉鸽支持中途续玩。

`RewardStashService` 建候选和明确失败恢复时会复制 `_saveExt`，包括 `bookRun`。CF6 的 Boss、机关、章节演出与待结算归属因此使用独立捕获的标量身份，经 `BookRunRules.sameCf6Run` 核对 `slot/bookId/routeId/seed/startedAt/planSeed` 和当前 active 状态；开始时间必须在真实赋值之后捕获。世界 identity、关卡索引与当前槽位的既有检查仍保留，不能只凭 `bookRun` 对象引用变化取消同局流程，也不能只凭同槽放行另一局。此身份检查不改变奖励写锁或 exact operation 查询。

CF6史实目录按明确年代白名单筛选地面、精英、配给和商店；统合后期与年代不明的进阶形态仅保留来源资料，当前不扩展配给tier持久交付协议。每轮仍抽三选一，原目录容量足够容纳本轮史实候选。

`grade` 已全链接线（2026-10-08 CS6 批次）：choice-rewards.json 显式声明 → `ChoiceRewardDefinition.as` 派生目录 → `ChoiceRewardService.open` 冻结进候选（目录非法值按 `invalid_reward_pack` 失败关闭）→ `snapshot` 投影（旧冻结候选无该键时读边省略）→ `ItemUseTask.RewardChoice.cs` 白名单（可选封闭枚举）→ Web 卡片/揭晓层按 `option.grade` 着色。`ChoiceRewardStore.normalize` 拒收非法冻结 grade（`invalid_choice_store`）。编辑源改动后跑 `build-choice-rewards.py`（及书籍生成器，若凭证选项受影响），AS2 源改动须走 CS6 `-Target publish` 并复核 `.as` BOM。

`choiceOffers.v=1`；旧档缺该字段合法，旧选项缺 `skills/kCost` 等价于物品卡且免费。未知版本或畸形非空数据拒绝写入；仅已知 AMF 空数组形状可修复，并报告 changed。未选物品不算玩家持有量，选定时才记 gain，领取到背包时不重复记收益。

## 修改与验证

```powershell
chcp.com 65001 > $null
python -X utf8 tools/build-choice-rewards.py
python -X utf8 tools/build-book-definition.py
python -X utf8 tools/derive-material-catalog.py derive
python -X utf8 tools/derive-material-catalog.py --check
python -X utf8 tools/build-choice-rewards.py --check
python -X utf8 tools/build-book-definition.py --check
python -X utf8 tools/test-choice-rewards.py
python -X utf8 tools/test-book-definition.py
node tools/validate-reward-packs.js
node tools/audit-grade-colors.js
node tools/test-character-build-item-use.js
node tools/run-choice-rewards-harness.js
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-choice-rewards-tests.ps1
```

协议变更另跑 Host 全量测试，持久写变更追加 reward-stash/save-storage 专项，书中掉落变更追加 bookshelf 专项。AS2 定义改变后用 CS6 `-Target publish` 编译并回读；重启对应开发候选再开新局。浏览器使用模拟权威，AS2 使用独立测试槽，均不代替完整游戏旅程或真实玩家体验。
