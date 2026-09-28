# 装备生命周期战技关系打标与照明施工衔接

**文档角色**：2026-09-28 隔离施工的审计快照与已对齐产品决策；当前字段合同归[装备函数 README](../../scripts/逻辑/装备函数/README.md#skill-interaction)，实时覆盖归[静态校验器](../../tools/lifecycle-skill-metadata/README.md)。
**核对基线**：纯打标批次基于 commit `5f6ea4135319cecfb0da433ae09ecf34504a07a7`，在独立 worktree `codex/lifecycle-skill-metadata` 完成。紧急列车结束后，已将该批修改复核并应用到 main 的 `6189814fb52aa691e8b81ec4fcb11ac47f48325c` 基线上；该批随后随装备照明合入主线并完成[正式发布](equipment-lighting-runtime-release-2026-09-28.md)。下文数量和“本批”均指当时的纯打标快照，后续运行接线见[照明施工记录](equipment-lighting-implementation-2026-09-28.md)。

## 本批范围与结果

按当时两份物品/插件注册表扫描 77 个 XML 文件中的 1654 个物品定义、106 个插件定义。在 111 个物品定义中发现 121 个生命周期绑定：119 个基础绑定、2 个进阶覆盖；当时插件定义没有 lifecycle。已逐绑定填写 `skillInteraction`，涉及 29 个 XML 文件。

| 分类 | 本批数量 |
|---|---:|
| `independent` | 97 |
| `fallback` | 1 |
| `bound` | 13 |
| `managed` | 10 |

这是该基线注册绑定的全量覆盖；未绑定的 helper 或尚在美术时间轴里的脚本没有被虚构成运行时绑定。今后接线或迁移时须按实际参数、调用链重新分类，缺标不会默认为独立。

6 个 SWE-2 Max 冻结证据分片完成全量初审，主控沿源码复核并纠正 8 处分类；另对 17 个边界绑定做独立复核。模型报告只作为审阅输入，不作为运行通过证明。初审的两处缺失调用链已补查：装备投影借槽不装载战技，G111 的充能状态确实被专用战技消费。

静态校验包含完整覆盖、合法枚举、重复/错层标记、直接 `attr.skill` 的结构约束，以及剥除新增标签行后的逐字节比较。后者覆盖两份注册表和全部注册 XML；本批没有改变原字段、注释、BOM 或 XML 换行。9 项检查器测试覆盖漏掉进阶绑定、注册插件漏标、根战技与独立动画分离、非法枚举和非 metadata 数据变化。

纯打标阶段没有修改 AS2/C#/native/XFL/SWF，也没有执行 CS6 编译、候选构建、发布、commit 或 push；当时 `TagManager` 与 loader 尚不消费此标签，安装行为没有改变。“分类完成”本身不等于战技兼容问题已在运行时修复。紧急列车后已复核新基线并继续接线，当前行为与验证见[照明施工记录](equipment-lighting-implementation-2026-09-28.md)。

## 需要保留的边界裁决

| 对象 | 本批裁决与源码依据 |
|---|---|
| 通用战技事件 | [统一释放入口](../../scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as) 1823–1827 行发布 `WeaponSkill(mode)`；单凭订阅它不能判定占槽。肩炮、两种斩马刀、光刀狮子、光刃摩羯、公社爆燃钻矛按独立绑定处理。钻矛仍有持续战技状态要求，替换组合的连发时长需实测。 |
| 指定技能协议 | [剑圣手甲](../../scripts/逻辑/装备函数/剑圣手甲.as) 145–165 行只认刀剑乱舞；[剑圣装甲鞋](../../scripts/逻辑/装备函数/剑圣装甲鞋.as) 103–131 行只增强一文字落雷。两者是 `bound`，不是泛化成所有套装组件占槽。 |
| 跨槽管理 | [剑圣腿甲](../../scripts/逻辑/装备函数/剑圣腿甲.as) 95–99 行装载空手战技，并由套装清理恢复旧槽。`managed` 不能简单映射到装备本身的穿戴槽。 |
| G111 | [充能 helper](../../scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/ChargeKeyAccumulator.as) 25–40 行生产 `chargeComplete`；[主动战技定义](../../scripts/逻辑/单位函数/单位函数_雾人_aka_fs_主动战技.as) 698–744 行以它控制突击者之怒的释放和弹数，修正为 `bound`。 |
| 死者之手 | [装备投影](../../scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/RuntimeEquipmentProjection.as) 62–119 行与[长枪配置](../../scripts/逻辑/单位函数/单位函数_fs_玩家装备配置.as) 1–10 行只借装备槽/配置属性，不装载主动战技，维持 `independent`。 |
| 固定动作与战技管理 | 毒液蜘蛛侠的固定手部发射、M134 PIG 的 NPC 自动抡枪记为 `bound`；它们没有改写共享战技槽。真猫妖头套初始化会重设 NPC 单位战技组，记为 `managed`，不能宣称它占了玩家空手槽。 |
| 根层约束 | 独立的刀光、激光、夜视或射击动画不会解除物品根层 skill/subweapon/skillLocked。龙破军霜的 `fallback` 也不解除原有锁。 |
| 当前准入代码 | [TagManager](../../scripts/类定义/org/flashNight/arki/item/equipment/TagManager.as) 222–246、516–546 行检查战技/副武器与锁；当前并没有把“存在任意 lifecycle”统一判为冲突。后续应解决真实耦合与插件生命周期合成，不应先假设有一个通用禁用开关可删除。 |

## 已对齐的照明方案

| 项目 | 当前决策 |
|---|---|
| A：长枪开关 | 以 `攻击模式 === "长枪"` 作为业务启用条件；在该模式下移动、换弹也保留灯光。装备引用、出光锚点、版本与卸载有效性仍由生命周期检查。 |
| B：单位与预算 | 人形 NPC 纳入试点验证，不因数量假设直接排除。常驻光源使用稳定身份和优先预算，开火脉冲使用余量，不能按瞬时亮度挤掉常驻灯。常驻灯自身超额时采用稳定取舍；数量与迟滞参数由实测决定。 |
| C：激光照明 | 先试可见光束加窄范围照明，首版不做遮挡/穿透判定。照明场会影响束内可见内容，并非已经实现“只照到某个敌人”；束宽、辉光、敌人可读性与亮度需要候选实测。 |
| D：内置与插件 | 同一逻辑光效去重，优先复用内置素材及准确锚点；明确配置的多个发射器可以保留。 |
| E：安装位置 | 保留现有导轨、插件位置和装备适配规则；是否与战技耦合只作为另一维检查。 |
| F：数值 | 战术手电首版提供照明，激光模组原有数值效果保持现状；不把视觉接线顺带变成数值平衡改动。 |
| G：生命周期标签 | 标到具体 attr 的战技关系，允许独立装饰/功能效果共存。标签只描述依赖和管理行为，不能直接转换成整件装备的互斥判定。 |

出光位置采用“有已配置手电口则走手电口，否则回落枪口”。回落后仍检查实例存在与坐标有效性，不能把素材缺口变成错误位置常亮。现有手电/激光素材纳入后续迁移，旧时间轴显隐转交外部生命周期，并建立唯一显示所有者、native 失效回退与卸载清理。素材外观可复用不等于现有 MovieClip 可直接当 native 纹理使用。

## 紧急列车后的施工顺序

1. 在紧急修复的新基线上复核并合入这批 metadata、校验器和合同。针对改变过的 lifecycle/skill 输入补审，不把本快照当新基线证据。
2. 补齐插件 lifecycle 的合成、稳定身份和换装/卸载清理，再接战技关系到具体准入与兼容处理。现有 `EquipmentCalculator` 没有通用 mod.lifecycle 合并；root 锁、目标战技槽、套装条件和固定动作应分别核对。
3. 先做一把已有手电素材的长枪纵向试点：AS2 持有业务开关/锚点/生命周期，Host/native 支持常驻定向光及预算优先级，保留可用回退。当前点光能力不能直接证明持续锥光可用。
4. 验证持枪、移动、换弹、转向、换武器、死亡、重建、暂停、场景切换与断连；加入人形 NPC、多灯和密集开火场景，确认常驻灯不会因枪火预算闪烁。
5. 基于实际候选调手电光效与激光束照明，再按已摸底素材分组迁移，最后接战术手电/激光插件。保持现有激光数值，处理内置与插件去重。

全量分类适合冻结输入后并行审阅，难度中等且已交付静态结果；运行准入与生命周期合成需要集中复核共享状态，难度中等偏高；原生持续光和实际视觉调校包含跨层与人验，不能由打标完成推断其工期或验收。独立 worktree 可以与 1–2 小时的紧急列车窗口错开，但列车结束时间不作为本批可跳过验证的条件。

## 全量绑定快照

以下 ID 只用于本次审计，不是新增运行时注册表。分类值的当前权威在链接的 XML，函数链接给出核对入口；基础与进阶覆盖分别列出。

| ID | 物品与绑定 | 标签 | 函数入口 | 裁决摘要 |
|---|---|---|---|---|
| B001 | [九命猫妖项链](../../data/items/防具_颈部装备.xml) · `root/attr_九命猫妖` | `independent` | [真九命猫妖初始化:169](../../scripts/逻辑/装备函数/九命猫妖.as) | 只写NPC被动技能与复活/退场参数,被动技能表不占主动战技槽,无注册/替换/恢复战技路径 |
| B002 | [将军衣服](../../data/items/防具_0-19级.xml) · `root/attr_0` | `independent` | [挂载披风初始化:1](../../scripts/逻辑/装备函数/外观类挂载.as)；[挂载披风周期:10](../../scripts/逻辑/装备函数/外观类挂载.as) | 纯披风视觉挂载与坐标跟随,可达链无任何主动战技/技能路由操作 |
| B003 | [红外夜视仪](../../data/items/防具_0-19级.xml) · `root/attr_0` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 只向天气系统注册夜视视觉对象,无主动战技/技能路由读写 |
| B004 | [目镜式简易夜视仪](../../data/items/防具_0-19级.xml) · `root/attr_0` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003夜视视觉注册,参数仅min/max/visual差异 |
| B005 | [锐刻幻影夜视仪](../../data/items/防具_0-19级.xml) · `root/attr_0` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B006 | [黑铁游侠围巾](../../data/items/防具_0-19级.xml) · `root/attr_0` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B007 | [觉醒者.L33T墨镜](../../data/items/防具_0-19级.xml) · `root/attr_0` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B008 | [3XF士兵头盔](../../data/items/防具_0-19级.xml) · `root/attr_0` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B009 | [般若影鬼半覆面](../../data/items/防具_20-39级.xml) · `root/attr_0` | `independent` | [剑圣头部装甲初始化:38](../../scripts/逻辑/装备函数/剑圣头部装甲.as)；[剑圣头部装甲周期:154](../../scripts/逻辑/装备函数/剑圣头部装甲.as) | 套装gated视觉+扫描debuff,全链不读写主动战技槽/技能路由 |
| B010 | [般若赤鬼半覆面](../../data/items/防具_20-39级.xml) · `root/attr_0` | `independent` | [剑圣头部装甲初始化:38](../../scripts/逻辑/装备函数/剑圣头部装甲.as)；[剑圣头部装甲周期:154](../../scripts/逻辑/装备函数/剑圣头部装甲.as) | 同B009同一对routine |
| B011 | [剑圣头部装甲](../../data/items/防具_20-39级.xml) · `root/attr_0` | `independent` | [剑圣头部装甲初始化:38](../../scripts/逻辑/装备函数/剑圣头部装甲.as)；[剑圣头部装甲周期:154](../../scripts/逻辑/装备函数/剑圣头部装甲.as) | 同B009同一对routine |
| B012 | [剑圣胸甲](../../data/items/防具_20-39级.xml) · `root/attr_0` | `independent` | [剑圣胸甲初始化:103](../../scripts/逻辑/装备函数/剑圣胸甲.as)；[剑圣胸甲周期:414](../../scripts/逻辑/装备函数/剑圣胸甲.as) | 任意成功战技事件驱动肩炮自身状态机；不限定战技名，不改写战技槽。 |
| B013 | [剑圣腿甲](../../data/items/防具_20-39级.xml) · `root/attr_0` | `managed` | [剑圣腿甲初始化:28](../../scripts/逻辑/装备函数/剑圣腿甲.as)；[剑圣腿甲周期:170](../../scripts/逻辑/装备函数/剑圣腿甲.as) | 进阶二阶+时直接向'空手'槽装载刀剑乱舞(非空槽才装的无条件替换)并注册teardown恢复,明确管理主动战技 |
| B014 | [剑圣手甲](../../data/items/防具_20-39级.xml) · `root/attr_0` | `bound` | [剑圣手甲初始化:34](../../scripts/逻辑/装备函数/剑圣手甲.as)；[剑圣手甲周期:340](../../scripts/逻辑/装备函数/剑圣手甲.as) | 进阶二阶+监听器只认特定战技刀剑乱舞;该战技被替换则爆发加成失效,本体不写战技槽 |
| B015 | [剑圣装甲鞋](../../data/items/防具_20-39级.xml) · `root/attr_0` | `bound` | [剑圣装甲鞋初始化:24](../../scripts/逻辑/装备函数/剑圣装甲鞋.as)；[剑圣装甲鞋周期:167](../../scripts/逻辑/装备函数/剑圣装甲鞋.as) | 仅在一文字落雷时改写该动作参数；专用兵器战技协议，未管理槽位。 |
| B016 | [黑铁大叔目镜头装](../../data/items/防具_20-39级.xml) · `root/attr_0` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B017 | [幻影胸甲](../../data/items/防具_20-39级.xml) · `root/attr_防具技能` | `independent` | [喷气背包初始化:5](../../scripts/逻辑/装备函数/喷气背包.as)；[喷气背包周期:32](../../scripts/逻辑/装备函数/喷气背包.as) | 纯视觉挂载+飞行键喷气，不触碰主动战技/选择索引/战技路由 |
| B018 | [幻影头部装甲](../../data/items/防具_20-39级.xml) · `root/attr_0` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B019 | [61式胸甲](../../data/items/防具_20-39级.xml) · `root/attr_防具技能` | `independent` | [喷气背包初始化:5](../../scripts/逻辑/装备函数/喷气背包.as)；[喷气背包周期:32](../../scripts/逻辑/装备函数/喷气背包.as) | 同喷气背包组：仅视觉与飞行机制，无战技槽交互 |
| B020 | [重甲上衣](../../data/items/防具_20-39级.xml) · `root/attr_防具技能` | `independent` | [喷气背包初始化:5](../../scripts/逻辑/装备函数/喷气背包.as)；[喷气背包周期:32](../../scripts/逻辑/装备函数/喷气背包.as) | 同B017 |
| B021 | [诺亚安保服头盔](../../data/items/防具_20-39级.xml) · `root/attr_0` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B022 | [毒液蜘蛛侠战服上装](../../data/items/防具_20-39级.xml) · `root/attr_防具技能` | `bound` | [蜘蛛侠蛛丝初始化:6](../../scripts/逻辑/装备函数/毒液蜘蛛侠.as)；[蜘蛛侠蛛丝周期:18](../../scripts/逻辑/装备函数/毒液蜘蛛侠.as) | 飞行键触发固定手部发射动作并提供专用弹药参数；不装载或选择共享战技槽。 |
| B023 | [毒液蜘蛛侠头套](../../data/items/防具_20-39级.xml) · `root/attr_夜视仪` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B024 | [钛合金61式装甲鞋](../../data/items/防具_40+级.xml) · `root/attr_0` | `independent` | [钛合金61组件初始化:5](../../scripts/逻辑/装备函数/钛合金套装.as)；[钛合金61组件周期:8](../../scripts/逻辑/装备函数/钛合金套装.as) | 套装静态组件，护盾伺服语义，不装/卸/选任何战技 |
| B025 | [钛合金61式腿甲](../../data/items/防具_40+级.xml) · `root/attr_0` | `independent` | [钛合金61组件初始化:5](../../scripts/逻辑/装备函数/钛合金套装.as)；[钛合金61组件周期:8](../../scripts/逻辑/装备函数/钛合金套装.as) | 弹药合成走MP换shot，契约明确改弹药不等于战技槽竞争 |
| B026 | [钛合金61式手甲](../../data/items/防具_40+级.xml) · `root/attr_0` | `independent` | [钛合金61组件初始化:5](../../scripts/逻辑/装备函数/钛合金套装.as)；[钛合金61组件周期:8](../../scripts/逻辑/装备函数/钛合金套装.as) | 静态组件，订阅通用processShot回蓝，不占战技槽 |
| B027 | [钛合金61式胸甲](../../data/items/防具_40+级.xml) · `root/attr_防具技能` | `independent` | [喷气背包初始化:5](../../scripts/逻辑/装备函数/喷气背包.as)；[喷气背包周期:32](../../scripts/逻辑/装备函数/喷气背包.as) | 同B017，attr_防具技能仅跑喷气背包视觉周期 |
| B028 | [钛合金61式胸甲](../../data/items/防具_40+级.xml) · `root/attr_0` | `independent` | [钛合金61组件初始化:5](../../scripts/逻辑/装备函数/钛合金套装.as)；[钛合金61组件周期:8](../../scripts/逻辑/装备函数/钛合金套装.as) | 护盾核心独立运行；血契API为可选战技调用方服务，不为本attr装载或选择战技。 |
| B029 | [钛合金61式头部装甲](../../data/items/防具_40+级.xml) · `root/attr_0` | `independent` | [钛合金61组件初始化:5](../../scripts/逻辑/装备函数/钛合金套装.as)；[钛合金61组件周期:8](../../scripts/逻辑/装备函数/钛合金套装.as) | 静态夜视注册，与战技系统零交集 |
| B030 | [芬里尔胸甲](../../data/items/防具_40+级.xml) · `root/attr_防具技能` | `independent` | [喷气背包初始化:5](../../scripts/逻辑/装备函数/喷气背包.as)；[喷气背包周期:32](../../scripts/逻辑/装备函数/喷气背包.as) | 同B017 |
| B031 | [Mark3手甲](../../data/items/防具_40+级.xml) · `root/attr_0` | `bound` | [Mark3手甲初始化:5](../../scripts/逻辑/装备函数/Mark3.as)；[Mark3手甲周期:22](../../scripts/逻辑/装备函数/Mark3.as) | routine产出掌炮专属战技参数（电池模式），共享切换键触发同一战技机制；替换掌炮则该开关失义 |
| B032 | [Mark3胸甲](../../data/items/防具_40+级.xml) · `root/attr_防具技能` | `independent` | [喷气背包初始化:5](../../scripts/逻辑/装备函数/喷气背包.as)；[喷气背包周期:32](../../scripts/逻辑/装备函数/喷气背包.as) | 同B017 |
| B033 | [贯空天盖手套](../../data/items/防具_40+级.xml) · `root/attr_切换战技` | `managed` | [贯空天盖手套初始化:5](../../scripts/逻辑/装备函数/贯空天盖手套.as)；[贯空天盖手套周期:14](../../scripts/逻辑/装备函数/贯空天盖手套.as) | 直接切换技能选择索引：条件为主角+空手攻击模式+变形键边沿，战技列表受头盔/上衣套装条件扩展 |
| B034 | [贯空天盖上衣](../../data/items/防具_40+级.xml) · `root/attr_披风` | `independent` | [挂载披风初始化:1](../../scripts/逻辑/装备函数/外观类挂载.as)；[挂载披风周期:10](../../scripts/逻辑/装备函数/外观类挂载.as) | 同B002纯视觉披风;根层item.skill(喷气背包/回归枢机之光)属item级,不归此视觉attr |
| B035 | [贯空天盖上衣](../../data/items/防具_40+级.xml) · `root/attr_防具技能` | `independent` | [喷气背包初始化:5](../../scripts/逻辑/装备函数/喷气背包.as)；[喷气背包周期:32](../../scripts/逻辑/装备函数/喷气背包.as) | 本attr仍是喷气背包；额外战技选项由B033手套routine读取上衣名驱动，不归此attr |
| B036 | [登上明星](../../data/items/防具_40+级.xml) · `root/attr_夜视仪` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003;根层item.skill(登上明星)不归此视觉attr |
| B037 | [猫妖头套](../../data/items/防具_40+级.xml) · `root/attr_夜视仪` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B038 | [真猫妖头套](../../data/items/防具_40+级.xml) · `root/attr_夜视仪` | `independent` | [红外夜视仪初始化:2](../../scripts/逻辑/装备函数/红外夜视仪.as)；[红外夜视仪周期:45](../../scripts/逻辑/装备函数/红外夜视仪.as) | 同B003 |
| B039 | [真猫妖头套](../../data/items/防具_40+级.xml) · `root/attr_九命猫妖` | `managed` | [九命猫妖初始化:5](../../scripts/逻辑/装备函数/九命猫妖.as)；[九命猫妖周期:214](../../scripts/逻辑/装备函数/九命猫妖.as) | 非玩家初始化接管单位战技组与AI；周期另调用复活动作，不应推断占用玩家空手战技槽。 |
| B040 | [主唱光剑](../../data/items/武器_刀_直剑.xml) · `root/attr_0` | `independent` | [主唱光剑初始化:1](../../scripts/逻辑/装备函数/主唱光剑.as)；[主唱光剑周期:157](../../scripts/逻辑/装备函数/主唱光剑.as) | 形态切换与子弹/召唤/治疗皆自身事件与弹药系统，状态表只读；未注册/替换/选择任何战技 |
| B041 | [主唱光剑](../../data/items/武器_刀_直剑.xml) · `root/attr_1` | `independent` | [通用特效刀口初始化:239](../../scripts/逻辑/装备函数/通用装备函数.as)；[通用特效刀口周期:251](../../scripts/逻辑/装备函数/通用装备函数.as) | 刀口特效由兵器攻击状态触发，不读写主动战技也不订阅WeaponSkill |
| B042 | [光剑天秤](../../data/items/武器_刀_直剑.xml) · `root/attr_0` | `bound` | [光剑天秤初始化:35](../../scripts/逻辑/装备函数/光剑天秤.as)；[光剑天秤周期:241](../../scripts/逻辑/装备函数/光剑天秤.as) | 战技事件驱动伤害/护盾/形态重置，依赖本体兵器战技协议，替换战技即断链 |
| B043 | [血色光剑天秤](../../data/items/武器_刀_直剑.xml) · `root/attr_0` | `independent` | [通用刀光初始化:187](../../scripts/逻辑/装备函数/通用装备函数.as)；[通用刀光周期:192](../../scripts/逻辑/装备函数/通用装备函数.as) | 纯刀光视觉，根层猩红天秤为item.skill不占此attr |
| B044 | [血色光剑天秤](../../data/items/武器_刀_直剑.xml) · `root/attr_1` | `independent` | [血色光剑初始化:79](../../scripts/逻辑/装备函数/血色光剑天秤.as)；[血色光剑周期:149](../../scripts/逻辑/装备函数/血色光剑天秤.as) | 攻击状态概率发射+扣血，无WeaponSkill订阅和主动战技读写 |
| B045 | [黑铁的剑](../../data/items/武器_刀_直剑.xml) · `root/attr_0` | `independent` | [黑铁的剑初始化:1](../../scripts/逻辑/装备函数/黑铁的剑.as)；[通用特效刀口周期:251](../../scripts/逻辑/装备函数/通用装备函数.as) | 根层黑铁剑意属item.skill不占此视觉attr，仅读兵器攻击状态 |
| B046 | [光玉的剑](../../data/items/武器_刀_直剑.xml) · `root/attr_0` | `independent` | [黑铁的剑初始化:1](../../scripts/逻辑/装备函数/黑铁的剑.as)；[通用特效刀口周期:251](../../scripts/逻辑/装备函数/通用装备函数.as) | 同B045，根skill不占此刀口视觉attr，无战技依赖 |
| B047 | [龙型环首唐刀](../../data/items/武器_刀_直剑.xml) · `root/attr_0` | `independent` | [镜之虎彻初始化:1](../../scripts/逻辑/装备函数/镜之虎彻.as)；[镜之虎彻周期:12](../../scripts/逻辑/装备函数/镜之虎彻.as) | 攻击触发镜闪冲刺，耗蓝属消耗非槽位竞争；根skill追踪五连为根层 |
| B048 | [冰魄神斩](../../data/items/武器_刀_长刀.xml) · `root/attr_0` | `independent` | [初期特效初始化:2](../../scripts/逻辑/装备函数/通用装备函数.as)；[初期特效周期:13](../../scripts/逻辑/装备函数/通用装备函数.as) | 攻击概率触发子弹，无skill装载/订阅 |
| B049 | [镜之虎彻](../../data/items/武器_刀_长刀.xml) · `root/attr_0` | `independent` | [镜之虎彻初始化:1](../../scripts/逻辑/装备函数/镜之虎彻.as)；[镜之虎彻周期:12](../../scripts/逻辑/装备函数/镜之虎彻.as) | 同B047，无战技读写与事件订阅 |
| B050 | [电感切割刃](../../data/items/武器_刀_刀剑.xml) · `root/attr_0` | `independent` | [电感切割刃初始化:1](../../scripts/逻辑/装备函数/电感切割刃.as)；[电感切割刃周期:28](../../scripts/逻辑/装备函数/电感切割刃.as) | 攻击充能放弹机制，无主动战技访问与订阅 |
| B051 | [激光剑](../../data/items/武器_刀_刀剑.xml) · `root/attr_0` | `independent` | [通用刀光初始化:187](../../scripts/逻辑/装备函数/通用装备函数.as)；[通用刀光周期:192](../../scripts/逻辑/装备函数/通用装备函数.as) | 纯刀光视觉，无战技交互 |
| B052 | [死者之手](../../data/items/武器_刀_刀剑.xml) · `root/attr_0` | `independent` | [死者之手初始化:9](../../scripts/逻辑/装备函数/死者之手.as)；[死者之手周期:89](../../scripts/逻辑/装备函数/死者之手.as) | 只借用空的长枪装备投影并生成枪械属性；借槽与配置函数不装载主动战技。 |
| B053 | [绝地武士佩剑](../../data/items/武器_刀_刀剑.xml) · `root/attr_0` | `independent` | [通用刀光初始化:187](../../scripts/逻辑/装备函数/通用装备函数.as)；[通用刀光周期:192](../../scripts/逻辑/装备函数/通用装备函数.as) | 纯刀光视觉 |
| B054 | [审判日夜闪](../../data/items/武器_刀_刀剑.xml) · `root/attr_0` | `independent` | [通用刀光初始化:187](../../scripts/逻辑/装备函数/通用装备函数.as)；[通用刀光周期:192](../../scripts/逻辑/装备函数/通用装备函数.as) | 纯刀光视觉 |
| B055 | [远古诛神剑](../../data/items/武器_刀_刀剑.xml) · `root/attr_0` | `managed` | [牙狼剑初始化:8](../../scripts/逻辑/装备函数/牙狼剑.as)；[牙狼剑周期:25](../../scripts/逻辑/装备函数/牙狼剑.as) | 变形键切换形态即主动装载/清空兵器战技，技能来自attr initParam.skill_0 |
| B056 | [龙破军霜](../../data/items/武器_刀_重斩.xml) · `root/attr_0` | `fallback` | [初期特效初始化:2](../../scripts/逻辑/装备函数/通用装备函数.as)；[初期特效周期:13](../../scripts/逻辑/装备函数/通用装备函数.as) | attr.skill凶斩走槽空才装载默认战技，routine不切换不依赖指定技能 |
| B057 | [十文字大剑](../../data/items/武器_刀_重斩.xml) · `root/attr_0` | `independent` | [通用特效刀口初始化:239](../../scripts/逻辑/装备函数/通用装备函数.as)；[通用特效刀口周期:251](../../scripts/逻辑/装备函数/通用装备函数.as) | 同B041，状态触发刀口特效，无战技交互 |
| B058 | [斩马刀](../../data/items/武器_刀_重斩.xml) · `root/attr_0` | `independent` | [斩马刀初始化:4](../../scripts/逻辑/装备函数/斩马刀.as)；[斩马刀周期:73](../../scripts/逻辑/装备函数/斩马刀.as) | 通用兵器战技事件开启增益窗口；不限定战技身份，既有伤害与耗蓝不构成槽位管理。 |
| B059 | [烈焰斩马刀](../../data/items/武器_刀_重斩.xml) · `root/attr_0` | `independent` | [烈焰斩马刀初始化:5](../../scripts/逻辑/装备函数/烈焰斩马刀.as)；[烈焰斩马刀周期:98](../../scripts/逻辑/装备函数/烈焰斩马刀.as) | 通用兵器战技事件开启可配置窗口；没有专用战技名称、参数或槽位管理。 |
| B060 | [炎魔斩new](../../data/items/武器_刀_重斩.xml) · `root/attr_0` | `managed` | [炎魔斩new初始化:5](../../scripts/逻辑/装备函数/炎魔斩new.as)；[炎魔斩new周期:206](../../scripts/逻辑/装备函数/炎魔斩new.as) | init与变形完成均主动装载/替换兵器战技，战技随形态路由 |
| B061 | [雷铁斩斧](../../data/items/武器_刀_重斩.xml) · `root/attr_0` | `independent` | [雷铁斩斧初始化:1](../../scripts/逻辑/装备函数/雷铁斩斧.as)；[雷铁斩斧周期:15](../../scripts/逻辑/装备函数/雷铁斩斧.as) | 变形只改动作类型，无装载战技/WeaponSkill订阅；根skill破坏殆尽为根层 |
| B062 | [光斧金牛](../../data/items/武器_刀_狂野.xml) · `root/attr_0` | `bound` | [光斧金牛初始化:1](../../scripts/逻辑/装备函数/光斧金牛.as)；[光斧金牛周期:9](../../scripts/逻辑/装备函数/光斧金牛.as) | 光效读取金牛之力改写的全局掉钱机率；专用效果协议，不管理战技槽。 |
| B063 | [光刀狮子](../../data/items/武器_刀_狂野.xml) · `root/attr_0` | `independent` | [光刀狮子初始化:1](../../scripts/逻辑/装备函数/光刀狮子.as)；[光刀狮子周期:14](../../scripts/逻辑/装备函数/光刀狮子.as) | 通用兵器战技事件设置刀光开关；不限定战技名称，也不读取专用战技参数。 |
| B064 | [光刃摩羯](../../data/items/武器_刀_短兵.xml) · `root/attr_0` | `independent` | [光刃摩羯初始化:1](../../scripts/逻辑/装备函数/光刃摩羯.as)；[光刃摩羯周期:14](../../scripts/逻辑/装备函数/光刃摩羯.as) | 通用兵器战技事件设置刀光时长；不限定战技身份或管理槽位。 |
| B065 | [键盘镰刀](../../data/items/武器_刀_镰刀.xml) · `root/attr_0` | `managed` | [键盘镰刀初始化:1](../../scripts/逻辑/装备函数/键盘镰刀.as)；[键盘镰刀周期:257](../../scripts/逻辑/装备函数/键盘镰刀.as) | 按镰刀/键盘形态与是否兵器跳动态装载、切换、清空兵器槽主动战技，含null清除路径；managed。 |
| B066 | [杀戮风暴](../../data/items/武器_刀_镰刀.xml) · `root/attr_0` | `independent` | [杀戮风暴初始化:4](../../scripts/逻辑/装备函数/杀戮风暴.as)；[杀戮风暴周期:40](../../scripts/逻辑/装备函数/杀戮风暴.as) | 只读通用兵器攻击状态驱动转刀动画；根层回旋裂地占用不归本视觉attr，independent。 |
| B067 | [公社爆燃钻矛](../../data/items/武器_刀_长枪.xml) · `root/attr_0` | `independent` | [公社爆燃钻矛初始化:4](../../scripts/逻辑/装备函数/公社爆燃钻矛.as)；[公社爆燃钻矛周期:68](../../scripts/逻辑/装备函数/公社爆燃钻矛.as) | 使用通用兵器战技事件和战技状态驱动燃料增益/连发，无指定战技协议；替换后的持续时间仍需组合验证。 |
| B068 | [烬灭裁决](../../data/items/武器_刀_长柄.xml) · `root/attr_0` | `managed` | [烬灭裁决初始化:38](../../scripts/逻辑/装备函数/烬灭裁决.as)；[烬灭裁决周期:60](../../scripts/逻辑/装备函数/烬灭裁决.as) | 初始化与变形回调均重写兵器槽主动战技且经战技路由播变形动画；managed。 |
| B069 | [烬灭裁决双刀](../../data/items/武器_刀_双刀.xml) · `root/attr_0` | `managed` | [烬灭裁决初始化:38](../../scripts/逻辑/装备函数/烬灭裁决.as)；[烬灭裁决周期:60](../../scripts/逻辑/装备函数/烬灭裁决.as) | 与B068同routine集合，双刀形态默认装载深冲利刺并可切回旋裂地；managed。 |
| B070 | [黑铁剑配鞘](../../data/items/武器_刀_疾影.xml) · `root/attr_0` | `independent` | [黑铁的剑初始化:1](../../scripts/逻辑/装备函数/黑铁的剑.as)；[通用特效刀口周期:251](../../scripts/逻辑/装备函数/通用装备函数.as) | 同B045，根skill不占此视觉attr |
| B071 | [P90](../../data/items/武器_手枪_冲锋枪.xml) · `root/attr_0` | `independent` | [P90初始化:1](../../scripts/逻辑/装备函数/P90.as)；[P90周期:13](../../scripts/逻辑/装备函数/P90.as) | 弹匣帧同步与视觉更新，无战技提供/依赖/管理；independent。 |
| B072 | [P90战术版](../../data/items/武器_手枪_冲锋枪.xml) · `root/attr_0` | `independent` | [P90初始化:1](../../scripts/逻辑/装备函数/P90.as)；[P90周期:13](../../scripts/逻辑/装备函数/P90.as) | 同P90，仅参数化弹速；independent。 |
| B073 | [Kel-Tec-P50](../../data/items/武器_手枪_冲锋枪.xml) · `root/attr_0` | `independent` | [P90初始化:1](../../scripts/逻辑/装备函数/P90.as)；[P90周期:13](../../scripts/逻辑/装备函数/P90.as) | 同P90；independent。 |
| B074 | [P90印花集](../../data/items/武器_手枪_冲锋枪.xml) · `root/attr_0` | `independent` | [P90初始化:1](../../scripts/逻辑/装备函数/P90.as)；[P90周期:13](../../scripts/逻辑/装备函数/P90.as) | 同P90；independent。 |
| B075 | [钛合金P90](../../data/items/武器_手枪_冲锋枪.xml) · `root/attr_0` | `independent` | [P90初始化:1](../../scripts/逻辑/装备函数/P90.as)；[P90周期:13](../../scripts/逻辑/装备函数/P90.as) | 同P90，extraMpPerShot属消耗不构成战技槽竞争；independent。 |
| B076 | [钛合金P90](../../data/items/武器_手枪_冲锋枪.xml) · `root/attr_1` | `independent` | [枪械激光初始化:8](../../scripts/逻辑/装备函数/枪械激光瞄准.as)；[枪械激光周期:41](../../scripts/逻辑/装备函数/枪械激光瞄准.as) | 纯光束视觉挂载与模式显隐，不触战技槽；independent。 |
| B077 | [XM556-OC-Overlord](../../data/items/武器_手枪_压制机枪.xml) · `root/attr_0` | `independent` | [XM556_OC_Overlord初始化:2](../../scripts/逻辑/装备函数/XM556-OC-Overlord.as)；[XM556_OC_Overlord周期:27](../../scripts/逻辑/装备函数/XM556-OC-Overlord.as) | 通用射击事件驱动射击/收拢帧动画；independent。 |
| B078 | [XM556-H-Stinger](../../data/items/武器_手枪_压制机枪.xml) · `root/attr_0` | `independent` | [XM556_H_Stinger初始化:4](../../scripts/逻辑/装备函数/XM556_H_Stinger.as)；[XM556_H_Stinger周期:25](../../scripts/逻辑/装备函数/XM556_H_Stinger.as) | 射击事件驱动转管视觉+暴击数值与激光显隐；independent。 |
| B079 | [AR57](../../data/items/武器_长枪_冲锋枪.xml) · `root/attr_0` | `independent` | [AR57初始化:1](../../scripts/逻辑/装备函数/AR57.as)；[AR57周期:12](../../scripts/逻辑/装备函数/AR57.as) | 弹匣帧同步视觉；independent。 |
| B080 | [XM556-Preview](../../data/items/武器_长枪_压制机枪.xml) · `root/attr_0` | `independent` | [XM556初始化:4](../../scripts/逻辑/装备函数/XM556_Microgun.as)；[XM556周期:43](../../scripts/逻辑/装备函数/XM556_Microgun.as) | 射击事件驱动转管动画；independent。 |
| B081 | [XM556-Microgun](../../data/items/武器_长枪_压制机枪.xml) · `root/attr_0` | `independent` | [XM556初始化:4](../../scripts/逻辑/装备函数/XM556_Microgun.as)；[XM556周期:43](../../scripts/逻辑/装备函数/XM556_Microgun.as) | 同XM556转管视觉；independent。 |
| B082 | [XM214-CageFrame](../../data/items/武器_长枪_压制机枪.xml) · `root/attr_0` | `independent` | [XM214初始化:4](../../scripts/逻辑/装备函数/XM214-CageFrame.as)；[XM214周期:75](../../scripts/逻辑/装备函数/XM214-CageFrame.as) | 射击事件改霰弹值/弹药与interval属弹药改写不构成战技槽竞争；independent。 |
| B083 | [M134](../../data/items/武器_长枪_压制机枪.xml) · `root/attr_0` | `independent` | [M134初始化:1](../../scripts/逻辑/装备函数/M134.as)；[M134周期:74](../../scripts/逻辑/装备函数/M134.as) | 通用射击事件驱动转管动画；根层旋转抡枪占用不归本视觉attr；independent。 |
| B084 | [M134暴力版](../../data/items/武器_长枪_压制机枪.xml) · `root/attr_0` | `independent` | [M134初始化:1](../../scripts/逻辑/装备函数/M134.as)；[M134周期:74](../../scripts/逻辑/装备函数/M134.as) | 同M134转管视觉；independent。 |
| B085 | [M134暴力版的PIG版](../../data/items/武器_长枪_压制机枪.xml) · `root/attr_0` | `bound` | [M134暴力版初始化:1](../../scripts/逻辑/装备函数/M134暴力版.as)；[M134暴力版周期:29](../../scripts/逻辑/装备函数/M134暴力版.as) | NPC近敌时调用固定抡枪动作；属于动作协议耦合，没有写入或替换长枪主动战技槽。 |
| B086 | [M134暴力版的PIG版](../../data/items/武器_长枪_压制机枪.xml) · `root/attr_1` | `independent` | [M134初始化:1](../../scripts/逻辑/装备函数/M134.as)；[M134周期:74](../../scripts/逻辑/装备函数/M134.as) | 同M134转管视觉，不占不触战技槽；independent。 |
| B087 | [等离子切割机](../../data/items/武器_长枪_压制近战.xml) · `root/attr_0` | `independent` | [等离子切割机初始化:5](../../scripts/逻辑/装备函数/等离子切割机.as)；[等离子切割机周期:113](../../scripts/逻辑/装备函数/等离子切割机.as) | 只读写通用射击/击杀事件与子弹属性，无战技装载或特定战技依赖。 |
| B088 | [GM6_LYNX](../../data/items/武器_长枪_反器材武器.xml) · `root/attr_0` | `independent` | [GM6_LYNX初始化:6](../../scripts/逻辑/装备函数/GM6_LYNX.as)；[GM6_LYNX周期:103](../../scripts/逻辑/装备函数/GM6_LYNX.as) | 动画状态机与弹药奖励，未触碰主动战技槽或指定战技。 |
| B089 | [战术巴雷特](../../data/items/武器_长枪_反器材武器.xml) · `root/attr_0` | `independent` | [通用拖影初始化:204](../../scripts/逻辑/装备函数/通用装备函数.as)；[通用拖影周期:214](../../scripts/逻辑/装备函数/通用装备函数.as) | 长枪攻击模式触发的视觉拖影，只读通用状态 |
| B090 | [RPG](../../data/items/武器_长枪_发射器.xml) · `root/attr_0` | `independent` | [RPG初始化:1](../../scripts/逻辑/装备函数/RPG.as)；[RPG周期:10](../../scripts/逻辑/装备函数/RPG.as) | 纯显隐视觉routine，无战技交互。 |
| B091 | [RPG7V2](../../data/items/武器_长枪_发射器.xml) · `root/attr_0` | `independent` | [RPG初始化:1](../../scripts/逻辑/装备函数/RPG.as)；[RPG周期:10](../../scripts/逻辑/装备函数/RPG.as) | 同RPG组，纯弹头显隐，无战技交互。 |
| B092 | [PF98A](../../data/items/武器_长枪_发射器.xml) · `root/attr_0` | `independent` | [PF98A初始化:3](../../scripts/逻辑/装备函数/PF98A.as)；[PF98A周期:8](../../scripts/逻辑/装备函数/PF98A.as) | 纯视觉，无战技读写。 |
| B093 | [RPG28](../../data/items/武器_长枪_发射器.xml) · `root/attr_0` | `independent` | [RPG28初始化:3](../../scripts/逻辑/装备函数/RPG28.as)；[RPG28周期:8](../../scripts/逻辑/装备函数/RPG28.as) | 纯视觉帧切换，无战技交互。 |
| B094 | [XM25](../../data/items/武器_长枪_发射器.xml) · `root/attr_0` | `independent` | [XM25初始化:4](../../scripts/逻辑/装备函数/XM25.as)；[XM25周期:49](../../scripts/逻辑/装备函数/XM25.as) | 激光锁定视觉；根层skill占用不归此attr，routine不读战技状态。 |
| B095 | [RShG4](../../data/items/武器_长枪_发射器.xml) · `root/attr_0` | `independent` | [RShG4初始化:3](../../scripts/逻辑/装备函数/RShG4.as)；[RShG4周期:8](../../scripts/逻辑/装备函数/RShG4.as) | 纯视觉，无战技交互。 |
| B096 | [RShG4Я](../../data/items/武器_长枪_发射器.xml) · `root/attr_0` | `independent` | [RShG4Я初始化:11](../../scripts/逻辑/装备函数/RShG4Я.as)；[RShG4Я周期:53](../../scripts/逻辑/装备函数/RShG4Я.as) | 只消费通用updateBullet事件驱动动画；根skill核战斗部属根层占用，routine未按特定战技分支。 |
| B097 | [FSC7](../../data/items/武器_长枪_发射器.xml) · `root/attr_0` | `independent` | [RPG初始化:1](../../scripts/逻辑/装备函数/RPG.as)；[RPG周期:10](../../scripts/逻辑/装备函数/RPG.as) | 同RPG组，纯弹头显隐，无战技交互。 |
| B098 | [追月连弩](../../data/items/武器_长枪_弓弩.xml) · `root/attr_0` | `independent` | [追月连弩初始化:40](../../scripts/逻辑/装备函数/追月连弩.as)；[追月连弩周期:66](../../scripts/逻辑/装备函数/追月连弩.as) | 纯弹药视觉档位，无战技交互。 |
| B099 | [G1111](../../data/items/武器_长枪_战斗步枪.xml) · `root/attr_0` | `bound` | [G1111初始化:5](../../scripts/逻辑/装备函数/G1111.as)；[G1111周期:191](../../scripts/逻辑/装备函数/G1111.as) | 射击回调按根战技铁枪之锋的许可/倍率协议改弹种与狙击结算，换战技破坏协作。 |
| B100 | [M249](../../data/items/武器_长枪_机枪.xml) · `root/attr_0` | `independent` | [M249初始化:1](../../scripts/逻辑/装备函数/M249.as)；[M249周期:15](../../scripts/逻辑/装备函数/M249.as) | 纯射击动画与显隐，无战技交互。 |
| B101 | [PKM机枪](../../data/items/武器_长枪_机枪.xml) · `root/attr_0` | `independent` | [M249初始化:1](../../scripts/逻辑/装备函数/M249.as)；[M249周期:15](../../scripts/逻辑/装备函数/M249.as) | 同M249组，纯动画，无战技交互。 |
| B102 | [NEGEV](../../data/items/武器_长枪_机枪.xml) · `root/attr_0` | `independent` | [NEGEV初始化:1](../../scripts/逻辑/装备函数/NEGEV.as)；[NEGEV周期:15](../../scripts/逻辑/装备函数/NEGEV.as) | 纯视觉，无战技交互。 |
| B103 | [QJZ171](../../data/items/武器_长枪_机枪.xml) · `root/attr_0` | `independent` | [长枪射击动画初始化:8](../../scripts/逻辑/装备函数/枪械射击动画.as)；[长枪射击动画周期:60](../../scripts/逻辑/装备函数/枪械射击动画.as) | 射击事件驱动的动画routine，不改弹药伤害也不读战技。 |
| B104 | [钛合金QJZ171](../../data/items/武器_长枪_机枪.xml) · `root/attr_0` | `independent` | [长枪射击动画初始化:8](../../scripts/逻辑/装备函数/枪械射击动画.as)；[长枪射击动画周期:60](../../scripts/逻辑/装备函数/枪械射击动画.as) | 同射击动画组纯视觉；根层subweapon占用不归此attr。 |
| B105 | [钛合金QJZ171](../../data/items/武器_长枪_机枪.xml) · `root/attr_1` | `independent` | [枪械激光初始化:8](../../scripts/逻辑/装备函数/枪械激光瞄准.as)；[枪械激光周期:41](../../scripts/逻辑/装备函数/枪械激光瞄准.as) | 光束alpha只读titanium61火控进度，合同明示读火控进度仍独立；independent。 |
| B106 | [PKM战术版](../../data/items/武器_长枪_机枪.xml) · `root/attr_0` | `independent` | [NEGEV初始化:1](../../scripts/逻辑/装备函数/NEGEV.as)；[NEGEV周期:15](../../scripts/逻辑/装备函数/NEGEV.as) | 同NEGEV组，纯视觉，无战技交互。 |
| B107 | [双面雷神](../../data/items/武器_长枪_特殊.xml) · `root/attr_0` | `independent` | [双面雷神初始化:5](../../scripts/逻辑/装备函数/双面雷神.as)；[双面雷神周期:70](../../scripts/逻辑/装备函数/双面雷神.as) | 变形键形态切换与子弹属性调整，无主动战技装载/依赖。 |
| B108 | [吉他喷火器](../../data/items/武器_长枪_特殊.xml) · `root/attr_0` | `managed` | [吉他喷火初始化:1](../../scripts/逻辑/装备函数/吉他喷火.as)；[吉他喷火周期:206](../../scripts/逻辑/装备函数/吉他喷火.as) | 刀枪复用条件下routine主动注册/切换兵器槽主动战技（凶斩），并依赖其执行态触发吉他震地。 |
| B109 | [铁枪](../../data/items/武器_长枪_特殊.xml) · `root/attr_0` | `independent` | [铁枪初始化:5](../../scripts/逻辑/装备函数/铁枪.as)；[铁枪周期:187](../../scripts/逻辑/装备函数/铁枪.as) | FSM动画与能量轮盘，无战技读写或依赖。 |
| B110 | [wa90变形款](../../data/items/武器_长枪_特殊.xml) · `root/attr_0` | `independent` | [wa90变形款初始化:12](../../scripts/逻辑/装备函数/wa90变形款.as)；[wa90变形款周期:37](../../scripts/逻辑/装备函数/wa90变形款.as) | 双形态弹药data切换+变形键，无主动战技交互。 |
| B111 | [G11](../../data/items/武器_长枪_突击步枪.xml) · `root/attr_0` | `independent` | [G11初始化:1](../../scripts/逻辑/装备函数/G11.as) | 纯射击动画；根层skill占用不归此attr。 |
| B112 | [G111](../../data/items/武器_长枪_突击步枪.xml) · `root/attr_0` | `bound` | [G111初始化:2](../../scripts/逻辑/装备函数/G111.as)；[G111周期:28](../../scripts/逻辑/装备函数/G111.as) | 充能routine生产chargeComplete；突击者之怒以它判定释放与弹数，属于同一专用机制。 |
| B113 | [僵尸割草机](../../data/items/武器_长枪_近战.xml) · `root/attr_0` | `independent` | [僵尸割草机初始化:1](../../scripts/逻辑/装备函数/僵尸割草机.as)；[僵尸割草机周期:28](../../scripts/逻辑/装备函数/僵尸割草机.as) | attr无skill配置，routine不装/不换/不读战技槽，仅消费通用射击事件 |
| B114 | [暴君收割机](../../data/items/武器_长枪_近战.xml) · `root/attr_0` | `independent` | [僵尸割草机初始化:1](../../scripts/逻辑/装备函数/僵尸割草机.as)；[僵尸割草机周期:28](../../scripts/逻辑/装备函数/僵尸割草机.as) | 同僵尸割草机可达链；rootSubweapon占用按合同不归此attr |
| B115 | [混凝土切割机](../../data/items/武器_长枪_近战.xml) · `data_fire_gold_stolen/attr_0` | `bound` | [混凝土切割机初始化:1](../../scripts/逻辑/装备函数/混凝土切割机.as)；[混凝土切割机周期:47](../../scripts/逻辑/装备函数/混凝土切割机.as) | 依赖指定战技'混凝土切割机超载打击'的许可/剩余时间协议；替换战技则超载分支失效 |
| B116 | [混凝土切割机](../../data/items/武器_长枪_近战.xml) · `root/attr_0` | `bound` | [混凝土切割机初始化:1](../../scripts/逻辑/装备函数/混凝土切割机.as)；[混凝土切割机周期:47](../../scripts/逻辑/装备函数/混凝土切割机.as) | 同B115可达链，进阶覆盖仅改magictype参数，战技协议耦合不变 |
| B117 | [MACSIII](../../data/items/武器_长枪_近战.xml) · `data_ice_gold_stolen/attr_0` | `bound` | [MACSIII初始化:18](../../scripts/逻辑/装备函数/MACSIII.as)；[MACSIII周期:158](../../scripts/逻辑/装备函数/MACSIII.as) | 依赖并参与MACSIII超载打击许可/剩余时间协议，不换战技槽；换战技破坏协作 |
| B118 | [MACSIII](../../data/items/武器_长枪_近战.xml) · `root/attr_0` | `bound` | [MACSIII初始化:18](../../scripts/逻辑/装备函数/MACSIII.as)；[MACSIII周期:158](../../scripts/逻辑/装备函数/MACSIII.as) | 同B117链路，进阶覆盖仅改idleDamageReductionLevel阈值 |
| B119 | [火药燃气液压打桩机](../../data/items/武器_长枪_近战.xml) · `root/attr_0` | `independent` | [火药燃气液压打桩机初始化:1](../../scripts/逻辑/装备函数/火药燃气液压打桩机.as)；[火药燃气液压打桩机周期:67](../../scripts/逻辑/装备函数/火药燃气液压打桩机.as) | 无skill配置，纯动画状态机消费通用射击事件 |
| B120 | [Six12-Matryoshka](../../data/items/武器_长枪_霰弹枪.xml) · `root/attr_0` | `independent` | [Six12_Matryoshka初始化:1](../../scripts/逻辑/装备函数/Six12_Matryoshka.as)；[Six12_Matryoshka周期:14](../../scripts/逻辑/装备函数/Six12_Matryoshka.as) | 无skill配置，不占不换不读战技 |
| B121 | [Jackhammer](../../data/items/武器_长枪_霰弹枪.xml) · `root/attr_0` | `managed` | [Jackhammer初始化:2](../../scripts/逻辑/装备函数/Jackhammer.as)；[Jackhammer周期:34](../../scripts/逻辑/装备函数/Jackhammer.as) | 可达路径按蓄力状态替换长枪槽主动战技，属战技切换管理 |
