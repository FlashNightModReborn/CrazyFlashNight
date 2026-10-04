# 随机自选礼包

核对代码基线：commit `73366752444d9b3ca062ca5b3e23ceb04b5772ce` 加当前随机自选工作树。

`choice-rewards.json` 是候选内容和抽取规则的编辑源；`tools/build-choice-rewards.py` 生成 AS2 目录与 `data/items/消耗品_自选配给.xml`。生成物不能手改。

## 当前能力

每次打开一个礼包，从各组按权重无放回抽取，共展示 2–4 套，玩家选 1 套；`chooseCount=1`、`rerolls=0`。礼包不能批量打开。同一存档最多保留 16 个待选礼包，达到上限拒绝开包且不扣物品。

修理大学的第二、第四图末波分别掉初阶、进阶包。每池从战斗组抽两套，再从成长与生存组抽一套，最终三选一，组内等权。战斗组除原有四套武器方案外，加入拳套卡，进阶再加入四种下挂卡；成长与生存组保留原医疗、防具、复活币，并加入三类小加成项链与分阶段月系插件。复活币只在进阶池出现。两池版本为 3，已有冻结候选保持原内容。当前选品与经济取舍见[书中构筑说明](../../docs/bookshelf-player-context.md#配给选择与枪械转向)。

## 配置字段

| 对象 | 字段与限制 |
| --- | --- |
| 顶层 | `schema=choice-rewards.v1`，`bundles` 为 1–128 套，`pools` 为 1–32 池 |
| bundle 公共字段 | `id`、`name`、`title`、`description`；ID 稳定唯一，展示文案不作为领取身份 |
| 武器构筑 bundle | `weapon`、`mods`、`consumables:[{name,count}]`；检查真实装备等级、插件用途/子类/前置/互斥/槽位容量以及主枪、下挂弹药 |
| 通用物资 bundle | 用 `items:[{itemName,quantity}]` 替代上述三个构筑字段，最多 16 项；可放药剂、防具、材料等目录中的实体物品，装备数量只能为 1，其他物品为 1–9999 |
| pool | `id`、正整数 `version`、`title`、唯一 `itemName`、`scope`、`maxItemLevel`、`chooseCount`、`rerolls`、`groups` |
| scope | 普通角色用 `{kind:"character"}`；书中局次用 `{kind:"book",bookId:"repair-campus"}`，要求对应局次仍 active |
| group | `id`、`draw`、`entries:[{bundleId,weight}]`；权重为 1–10000 的整数，抽取量不能超过组内数量，各组不可重复引用同一 bundle |

不支持金币、SP、经验的伪物品直写；这类效果继续走现有成长/消耗品系统。候选产出中的礼包不会递归打开。

书籍配置 `buildChoices` 只保存掉落时机、`poolId`、`choiceItem`、等级上限和旧凭证名。书籍生成器只将池中的武器构筑 bundle 投影为旧凭证四选一配方；通用 `items` bundle 只走随机选择领取，不拓展旧凭证兑换能力。弹药包仍由 `data/stages/books/repair-campus.json` 的 `ammoBundle` 编辑。

## 存储与领取

1. 第一次打开：AS2 检查来源槽、租约、存档和局次，扣一个包并生成完整候选，在同一次 full save 保存 `_saveExt.rewardInbox.choiceOffers`。保存成功后才展示候选。配置中的权重、内容、种子或数量不接受 Web 提交。
2. 选择：Web 只提交 `storeId/expectedRevision/operationId/offerId/optionId`。AS2 校验冻结候选属于当前存档/局次，将选中物资加入现役暂存，同时删除整个 offer，两者在同一次 full save 完成。
3. 未知结果：复用 ItemUse/RewardStash 的写锁和同 operation 查询；刷新列表、关闭窗口、重新打开均不能解锁或重抽。明确保存失败恢复全部前像。首次建立暂存库的空 storeId 写若重发会拒绝为 stale，恢复通过原 operation 的 query；已有库的 exact 重复写返回原回执。

候选使用独立单调 offer ID，保存冻结的完整物品实例；后续配置调整不改已经抽出的候选。书中绑定临时槽、书籍 ID、seed 与 startedAt；换普通存档或开启另一局不可领取。此持久性保护不代表肉鸽支持中途续玩。

`choiceOffers.v=1`；旧档缺该字段合法。未知版本或畸形非空数据拒绝写入；仅已知 AMF 空数组形状可修复，并报告 changed。未选物品不算玩家持有量，选定时才记 gain，领取到背包时不重复记收益。

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
node tools/test-character-build-item-use.js
node tools/run-choice-rewards-harness.js
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-choice-rewards-tests.ps1
```

协议变更另跑 Host 全量测试，持久写变更追加 reward-stash/save-storage 专项，书中掉落变更追加 bookshelf 专项。AS2 定义改变后用 CS6 `-Target publish` 编译并回读；重启对应开发候选再开新局。浏览器使用模拟权威，AS2 使用独立测试槽，均不代替完整游戏旅程或真实玩家体验。
