# 非 weapon balance 离线物品投影候选

Refs [#131](https://github.com/FlashNightModReborn/CrazyFlashNight/issues/131)。核对基线为 main `23ec828cd04c783c86abb016c1f080eb814d41ba`。

四家族在下述源码和现役 SWF 的限定静态范围内没有已发现的游戏业务读者，最后保留点是 ItemUtil 的独立审计缓存。新增生成器只交付离线候选；生产 ItemDataLoader、作者 XML、台账和工作簿均不变。此结论不是 AVM1 执行或正式发布验收，Issue 必须保持 Open。

## 读者核对及边界

| 输入/路径 | 实际行为与处理 |
| --- | --- |
| `ItemDataLoader` → `ListLoader.concatField("item")` → BootSequencer → `ItemUtil.loadItemData` | 按 list 顺序连接 item；单节点归一化，套装中心表另挂 `itemSets`。ItemUtil 取出并删除 item-root balance 后才建立物品字典、自动 ID、默认 modslot 和普通 clone 输入。 |
| `ItemUtil.balanceDataDict` / `getRawBalanceData(name\|id)` | 是原树最后持有者；公共字典、数字 ID 路径也检查。正常库存、NPC 商店、K 店三条读取链只把它交给 `InventoryPanelService.buildBalanceSummary`。 |
| `buildBalanceSummary` | 要求原始 type 为武器，并严格要求 `formulaFamily="weapon"`；armor/melee/potion/explosives 均返回空摘要。保留 weapon 完整路径，未知家族或版本也保留。 |
| `CharacterBuildCf6LoadoutData` 的 `api[itemKeys[i]]` | 动态备份/恢复整个 balance 字典引用，供现有测试夹具复原；没有解释非 weapon 审计字段。不是删缓存的授权。 |
| `ChainBulletConfigResolver.auditWhenItemsReady` | 真实通用读者：会递归遍历 ItemDataLoader 原始树，只把名为 `bullet` 的字段当引用。现役四家族 balance 内没有该键。生成器遇到该键（含 XML 属性）保留对应整棵 balance。 |
| XFL/帧脚本 | 扫描 `scripts`、`flashswf`、主 `CRAZYFLASHER7MercenaryEmpire`、其他顶层文本源的 `.as/.xml`，未发现新的审计树读者。`eval`/动态字段的命中另核：物品缓存的公开别名/备份、数字访问和通用递归扫描如上；没有发现拼接 balance 字段名的生产访问。 |
| Host/Web/Tooltip | 检查 `launcher` 源码和工具编译器。它们消费四字段 balanceSummary，或同名的货币余额；不从四家族作者 balance 取业务值。 |
| 数值工具 | 四套 `*-balance-sync/check`、字段扫描/roundtrip、weapon 家族筛选会读作者输入或台账。它们继续使用原 `data/items`；离线候选不能替代作者源。 |

关键源码位于 [ItemUtil](../../scripts/类定义/org/flashNight/arki/item/ItemUtil.as)、[InventoryPanelService](../../scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as)、[ItemDataLoader](../../scripts/类定义/org/flashNight/gesh/xml/LoadXml/ItemDataLoader.as) 和 [ChainBulletConfigResolver](../../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Loader/ChainBulletConfigResolver.as)。

只读扫描 Git tracked 的 **1045** 个 `.swf`、**528,224,056** 个原始字节；1044 个可解包，逐个在解包字节中查找零终止的 balance/cache/accessor/summary/family 字符串。`flashswf/gk-1-s.swf` 是现存的 204-byte 非 SWF，无法按 SWF 扫描，保留这个漏查。没有改写它。

现役相关 literal 只命中 `scripts/asLoaderShared.swf`、`scripts/asLoaderLogic.swf`；另有 BaseSiege/历史工具宿主命中，不当作现役物品加载闭包。对两个现役模块用仓内 FFDec 21.1.1 导出全部 pcode（342/449 个脚本）并核对实际 Push/GetMember/CallMethod：ItemUtil 的提取、三条 summary 调用，以及 summary 的 weapon 门与源码一致。Dressup 的 `kind="balance"` 是武器形态伤害种类，不是 item balance。模块 SHA-256 分别为 `f0a997340bcbfb3ccc316a1a24313fa9e6ea037edd618f55261ee66f8fa21f13` / `74c8cb23c522180b2fa6a522159a4ea93632eec4d6c08355186897464a393eb5`。

该扫描不能证明任意动态生成属性名、外部未入库插件、未展开 FLA、将来新增消费者或真实执行时序；没有运行 Flash/AVM1，也没有测运行堆或 GC。生产切换仍需 Windows 的真实消费者核验。原 loader 缓存、balance 字典和旧引用均未删除。

复核源码及二进制导出的最短命令（仓库根；导出目录只作本机证据）：

```sh
rg -n 'getRawBalanceData|balanceDataDict|buildBalanceSummary' scripts flashswf CRAZYFLASHER7MercenaryEmpire launcher tools/cf7-balance-tool/packages
rg -n '\bbalance\b' scripts flashswf CRAZYFLASHER7MercenaryEmpire --glob '*.as' --glob '*.xml'
java -Djava.awt.headless=true -jar tools/ffdec/ffdec.jar -config parallelSpeedUp=0 -format script:pcode -export script tmp/issue131/shared-pcode scripts/asLoaderShared.swf
java -Djava.awt.headless=true -jar tools/ffdec/ffdec.jar -config parallelSpeedUp=0 -format script:pcode -export script tmp/issue131/logic-pcode scripts/asLoaderLogic.swf
```

## 投影合同和本轮字节结果

生成器从 `data/items/list.xml` 构造 ItemDataLoader 的输入闭包。只移除唯一 item-root balance、唯一已知 family 且 schemaVersion=1 的节点原文范围；其余 UTF-8/BOM/换行/注释和所有非 balance 字节保持。重复或残缺 balance、未知家族/版本、嵌套 balance 均保留。输出禁止落到生产目录，只允许专用仓外目录或仓内 `tmp` 子目录；`--check` 比较完整文件集合和字节，缺失/陈旧/额外文件均失败，额外文件不会被自动删除。

保留清单 **59** 个条目的顺序与全部 **1791** 条物品，逐条 manifest 使用文件、文件内 ordinal、同名 occurrence、merged ordinal；不按 name 去重。ItemUtil 的反序 Array 枚举/自动 ID 和重名覆盖只作源码模型记录，不称 AVM1 实测。发现 3 组重名（`TheGirl头-NPC`、`小F头部`、`三戈戟二型`），保留其全部 6 棵审计树，避免“只在 balance 存在时覆写字典”导致跨记录别名改变。`list.xml` 和 `item_sets.xml` 原字节保留；结构对照在套装注入、ID 和 modslot 默认化之前就要求除目标 balance 外完全相等，因此不复制/重写这些默认规则。

| 家族 | 原始节点 | 移除 | 保留 |
| --- | ---: | ---: | ---: |
| armor | 672 | 668 | 4（重名） |
| melee | 231 | 229 | 2（重名） |
| potion | 106 | 106 | 0 |
| explosives | 39 | 39 | 0 |
| weapon | 336 | 0 | 336 |
| 无 balance | 407 | 0 | 407 条物品 |

本轮实际生成目录：`tmp/issue-131-projection`。含 61 份 XML（59 个物品文件 + list + item_sets）和一份完整 manifest；输入/输出逐件 SHA-256、保留原因与完整身份对账均在 `projection-manifest.json`，不将大型派生物提交入库。

- XML：**2,906,461 → 1,977,813 bytes**，净省 **928,648 bytes**，移除 1042 节点。
- manifest：**590,893 bytes**。把 manifest 也计入离线产物后，总字节净省 **337,755 bytes**。
- 以上是文本/文件字节账，不是压缩包、运行驻留堆、加载时间或 GC 收益；与旧 Issue 的 920,911 不同，使用本轮真实输入重新计算。

复跑（工作目录 `tools/cf7-balance-tool`，输出目录可换为绝对路径）：

```sh
npm run nonweapon-runtime-projection -- --output ../../tmp/issue-131-projection
npm run nonweapon-runtime-projection -- --output ../../tmp/issue-131-projection --check
npm test -- packages/xml-io/tests/nonweapon-runtime-projection.test.ts
```

可显式传 `--repo-root <游戏仓绝对路径>`。manifest 的 `sourceRevision` 记录执行时 HEAD，逐件输入哈希绑定实际磁盘 XML；HEAD 变化后重新生成再 check，不拿旧 manifest 代签新工作树。

Linux 本轮 generate、check 及专属测试 **7/7** 通过，`tsc -b packages/cli --pretty false` 通过。测试含已知/未知家族、版本/重复/嵌套/通用 bullet 读者保留、BOM/CRLF/注释、单/多 item、重复清单、重名覆盖身份、item_sets 默认、输入漂移、完整集合与输出路径隔离。第一次测试暴露空 XML root 的工具解析差异，已修正并重跑通过；未放宽 XML 合法性。

父任务另跑原四家族检查：explosives **39/39** 通过；armor 因 `3XF特勤头盔` 未进入计划失败；melee 因计划中的 `光刀狮子` 找不到失败；potion 因台账及 `消耗品_药剂_九龙.xml` 摘要漂移失败。本轮未改这些作者输入或原检查器，也不运行 sync 覆盖它们。全量测试和完整基线红灯见[合并交接](issue-130-132-linux-handoff.md)。

## Windows 合成验收

1. 合成候选分支后在当前 HEAD 重新 generate + `--check`，跑工具 typecheck/test/roundtrip/原各家族检查，核对真实结果，不使用旧报告计数。
2. 在既有隔离测试资源副本中使用投影的 ItemDataLoader 清单闭包，保留其他游戏资源；记录实际目录和候选身份。使用隔离合成槽验证正常加载、套装、代表防具/刀/药/手雷与进阶、重名记录、物品身份及原 weapon 摘要。无需因数据投影重编 SWF。
3. Linux 结果只允许 **Go：离线候选复核**。**No-go：生产加载切换、删除审计缓存/旧树或关闭 #131**，直至 Windows 实际消费证据和独立生产裁决成立；不操作真实存档，也不触发 Runtime 发布。
