# CF6 史实章节装配

本目录把已审查的角色、遭遇、经济和地图输入装成 `data/stages/books/cf6-sting.json`，同时生成五档商店、商店登记块与地图环境登记块。它只更新本章拥有的块，保留其他关卡与商店内容。玩法范围及验收边界见[设计基线](../../docs/闪客快打6肉鸽-首版设计与施工拆分-2026-10-21.md)。

五档商店商品变化后，还须执行 `python tools/refresh-shop-portrait-sources.py` 和 `python tools/test-shop-portrait-assets.py`，更新只消费 `shopId` 的来源摘要；该工具保持商店身份顺序、渲染来源、头像图片和运行时 manifest 不变。商店 JSON 按 `.gitattributes` 固定 LF，避免跨机检出破坏原始字节摘要；不以重新烘焙头像或修改旧验收记录替代此检查。

输入分工：

- `tools/cf6-actor-template/actor.fragment.json`：固定 60 级 Andy 初装与技能。
- `data/stages/books/cf6-sting-source/`：原坐标遭遇、六个随机枪节点、五个精英配额、五个自选池及技能候选。
- `tools/cf6-roguelike-content/difficulty.source.json` / `difficulty_plan.py`：章内必清波次、混编与有限同屏数量；原作事实校验后再适配，生成审计保存在源片段目录。两项输入纳入章节与实际消费源码闭包。
- `tools/cf6-map-runtime/generated/`：20张主地图已转为游戏世界坐标的出生点、机关层、碰撞与环境。
- `tools/cf6-tutorial/`：教学室的独立地图和环境片段；不混用旧练习场输入。
- `tools/cf6-vehicle/chapter_fragment.py`：A07专用车辆段、透明世界背景与固定天空。其资源经严格验证后插入A06与A08之间；终局仍合并在A20，当前源码路线为教学加20个主房间，原A22源保留。
- `tools/cf6-map-runtime/sky-parallax.fragment.json`：A02/A06 根舞台（root-stage）天空与城市视差层声明（schema `cf6-sky-parallax-fragment.v1`），是这些层字段的唯一真源。装配按 `replaceLayerIds` 移除同 id 旧机制层后按声明顺序追加，拒绝重复 id/角色、未知地图、非 root-stage 坐标、非正尺寸与越界路径；层坐标不做地图原点或世界缩放转换。其 canonical 天空 SWF（`CF6_A02_sky.swf`、`CF6_A06_sky.swf`）已真实 CS6 编译（回执 `tmp/cf6-roguelike-20261021/validation/sky-canonical-r1/`，Compiler 0/0），strict 装配不再因天空资源缺失失败。
- [balance-input.json](balance-input.json)：本轮金币与累计商店选定输入；预算说明由 [economy-budget.py](economy-budget.py) 生成到 [README-budget.md](README-budget.md)。
- [scene-assembly.py](scene-assembly.py) 绑定门轨迹、出生木门、摄像头、电梯补演出和可前后穿行的摆件；
  [interactive-assembly.py](interactive-assembly.py) 绑定14个原作可爆桶与10个活体培养皿，并迁移原有10只克隆兽的触发入口。
  [transport-assembly.py](transport-assembly.py) 将A09/A14/A18的原5/7/5个第二波敌人绑定到1868运输车开门事件。
  三者在世界坐标换算后执行；局部画稿比例与原注册点、排序脚点分开，原经济和总敌人配额不增加。
- [spawn-assembly.py](spawn-assembly.py) 在终局合并后核对普通增援的可见入口。运输车与十个培养皿保留专属预算；新难度编成优先绑定可见门，否则使用显式左右出生线，并核对24×12脚底包围盒与碰撞。普通多只队列采用400ms参数、同波队列错相200ms；现役时间轮实际首发约400ms、后续约500ms。同一出生点共享容量，不按敌人entry重复计算同屏上限；人数与混编以难度源为准，精英武器与奖励配额保持。
- [dialogue-portraits.json](dialogue-portraits.json) 为Andy台词指定现役 `Andy Law#表情`，装配核对表情目录与实际WebP身份。

`merge_elder_finale` 按同房间两阶段合同，将原A22护卫预算和补给并入A20的 `bossEncounter.nextPhase`，运行路线不再追加A22。原始遭遇片段保持归档事实。人形单位自身的原生变形链是唯一机器人生成者；控制器只接管同世界、同出生身份、已初始化的后继。最终机器人完成111帧死亡与碎片落定并实际移除后才允许清场，不以hp归零或死亡事件提前结算。A21独立字幕卡仅保留旧非合并配置兼容，现役终局不播放该卡。

`apply_exit_guides` 优先采用实际门口 `traversal.depart.gate`，普通出口从环境Door附近选择可站立点。提示服务不改变清场与转场权威。

原作A11的1617出口在左侧并通向A12，A14同类出口位于右侧并通向A15；`scene-assembly.py` 绑定原节点与几何后只修A11标准出口及随之生成的提示。A10/A13电梯本体仍为明确的CF7登离梯改编。

SAI GRY 幽灵的专属Flash图标与持枪linkage尚未发布；物品XML暂用已存在的CAR兼容外观，与此前Web替身一致。物品名、属性、价格及精英配额保持，真实枪架和图标双帧的验证入口见[物品外观夹具](../cf6-item-visuals/README.md)。这不代表SAI专属美术已补齐。

`build-chapter.py` 只对原坐标的敌人、固定拾取、出生点和实例减去原点一次，不再次转换地图线给出的玩家出生点或机关层。金币和商人最后在世界坐标添加；商人需有邻近的无碰撞落点和直线接近空间。静态几何不证明实际角色脚底、拥堵或寻路体验。

```powershell
python -X utf8 -B tools/cf6-prototype/economy-budget.py --check
python -X utf8 -B tools/cf6-prototype/test-sky-parallax.py
python -X utf8 -B tools/cf6-prototype/build-chapter.py
python -X utf8 -B tools/cf6-prototype/build-chapter.py --check
python -X utf8 -B tools/build-choice-rewards.py
python -X utf8 -B tools/build-choice-rewards.py --check
python -X utf8 -B tools/build-book-definition.py
python -X utf8 -B tools/build-book-definition.py --check
node tools/validate-npc-shops.js
```

当前 20 张 canonical 背景 SWF 已全部真实 CS6 编译，回执见[矢量装配当前状态](../cf6-map-runtime/native-vector/README.md)。此前未编齐阶段曾用 `build-chapter.py --allow-missing-swfs` 准备作者数据，并带同一开关执行 `--check`；该开关仍只用于缺资源作者态，不能生成编译成功、实机可玩或完整路线验收结论。可试玩候选必须通过不带此开关的装配和章节生成门，再启用书架入口。运行资源的唯一源与实际 CS6 编译见[矢量装配](../cf6-map-runtime/native-vector/README.md)，不创建空 SWF 绕过缺失检查。

天空/城市视差层遵守同一资源门。历史边界：canonical 天空 SWF 未编译前 strict 装配与 `--check` 曾必然报缺资源失败，作者态一律带 `--allow-missing-swfs`；该状态已由 sky-canonical-r1 编译解除。城市 SWF 的 viewBox 顶已归零，层 y 只加一次。定向夹具 `test-sky-parallax.py` 在内存中验证替换幂等、无二次坐标转换、其他层与经济保留及各类非法声明拒绝，不触碰共享产物。

商店目录累进，弹药覆盖本阶段已在售及免费武器候选的真实 `clipname`；价格来自现役物品目录。技能剔除史实角色已满级项并遵循解锁等级。精英武器由局次种子一次选定、以强化 1 装备并在最终死亡掉落同一把；初装 11 强化不复制到新枪。金币只生成非零原生拾取，未超当前 60 级的单堆修正阈值；名义额度不替代实际入账回执。

每次装配把输入摘要、商人落点、金币计划及尚未接入的表现项写入 `generated/assembly.json`。真实 AS2 回归使用 `scripts/run-cf6-prototype-tests.ps1`；真实进书、消费、通关或失败返回沿[隔离候选工具](../cf6-live-e2e/README.md)。所有专项与整章证据分别记录，失败原件保留；2026-10-22 已获阶段提交推送授权，正式 runtime 发布仍另行授权。

## 当前施工与历史验证（2026-10-24）

第五轮按原作首次登场限制兵种、两段电梯各一波12人预置战、粉色NPC Wings与目标血条避让已生成并通过功能专项，已随 `runtime-build-v2/20261024-cf6-hud-timeline-v4` 完成正式推广；普通入口已核对实际Core身份、正常关闭及90份存档和配置摘要不变。基础HUD资源资格仍有未通过记录，整章战斗与驾驶仍待测试员反馈，详见下方设计基线当前状态。

第四轮已接入A07、场景Wings、焦点目标血条、统一出口提示和电梯站姿，并修复换回原枪的装备应用收口及同图死亡复活后的机关恢复；史实物资扩池和必清波次已生成。第四轮真实Flash组合1,364项、车辆99项与最终asLoader编译通过；开发候选已实际完成入书、装备卸下回装与应用保存、正常撤退和新进程读回，原测试角色资产及85个旁路存档文件未变。完整路线和驾驶观感仍需实玩。分组身份和具体边界统一见[设计基线当前状态](../../docs/闪客快打6肉鸽-首版设计与施工拆分-2026-10-21.md#0-阶段交付与接续入口)。

第三轮历史回执：教学海报/灭火器、增援入口与错峰、电梯入场显隐和朝向、A11出口、SAI兼容持枪与图标、培养皿实际出生交接及运输车留场曾编入主目录asLoader；真实Flash专项1,401项及上游资源继承/角色属性回归1,288项通过，当轮教学背景与asLoader均有新鲜Compiler 0/0。该版本尚未接入A07，不作为第四轮二进制或完整路线证明。SAI专属美术与整章观感仍待补齐或实玩。

以下记录保留前一阶段问题的来源及验收边界。

20 张原生地图、A01 两门炮塔及 7 段漫画/43 页和片尾已装配；章节、角色和配给生成均需通过不带缺资源豁免的 `--check`。
用户确认基础镜头保持 1，地图当前按 `viewport-policy.json` / `viewport-assembly.py` 适配；
现场指出的家具随背景放大问题已由[局部摆件校准](../cf6-prop-layout/README.md)处理，
交互源与深度修复见[场景机关](../cf6-scene-completion/README.md)；逐图观感仍需候选现场核对，不能以地图覆盖率代替。

第三图残敌的明确源码缺陷位于 `WaveSpawnWheel.minHeapTick`：被并发上限拒绝的生成也扣减了任务数量。
修复只在 `spawn` 成功时扣减，保留每帧五次尝试预算。真实旧代码回归为 8/18，通过版为 18/18，
覆盖 A03 的“总量 5、同时最多 2、腾出位置后补齐”。这证明调度缺陷与修复，实际 A03 战斗仍需重走。

已按用户要求合并上游 `cfaff6a31f`，保留全部本轮未提交工作；#163 普通枪械缺失/非法弹耗初始化修复随之进入源码。
`scripts/run-cf6-field-repair-tests.ps1` 已取得 679/679 真实 AVM1（刷怪 18、炮塔 120、弹药/提示/真实 XML 541），
Compiler 0/0、retry 0；回执在 `tmp/cf6-roguelike-20261021/validation/field-repair-avm1-r3/`。
炮塔完整枪头和唯一显示实例另由真实 SWF 检查，详见[炮塔工具链](../cf6-tutorial-turrets/README.md)。
合并后五个 CF6 商店补入现役远程准入表的 `local` 模式，保留书中现场交易权威，定向 Host 回归 18/18。

合并后的 Host 全量结果为 7781 项：7630 通过、121 失败、30 跳过；其中商店覆盖缺口已定向修复，
其余 120 项均停在既有 Windows 资格夹具的 evidence-root 前置条件。未伪造窗口/输入资格，也不把这组治理前置失败写成游戏业务失败或全量通过。
漫画交接与检出字节规则收口后的隔离候选为 `tmp/runtime-candidates/v2/cf6-sting-20261022f`，精确身份见 `validation/candidate-build-r7/result.json`；
上述2026-10-22历史阶段未执行 promotion。上游快进包含已跟踪的正式 Core、manifest 和 consensus 更新，与当时本任务构建独立候选分开记录于 `validation/upstream-merge-r1/formal-tracked-upstream-delta.json`；2026-10-24第五轮的正式推广见本节当前状态。

此前旧尺寸候选有真实撤退与新进程读回证明。新尺寸第三轮已真实进入并触发 S1/S2/S3、撤退返回零 SP，
但真人关闭书架后 CDP 断开，使报告仍为 `failed_preserved`，没有重启读回证明；旧报告与原始存档证据未改。
精确返回已对账后，专用克隆通过现役恢复合同完成恢复，见 `validation/live-r3-recovery-r2/verified.json`。
观察器已修复为只在 exact 返回回执和资产核对之后容忍可选截图/卸载失败，正常退出、新进程读回和保护检查仍必需。
新修复版的 A01 命中/声音、A03 清场、完整 20 图路线及新进程返回读回尚待实机复验。

后续现场已到 A08 前过场，日志明确复现 S4 finish→旧面板 close 未完成→S5 被拒绝→重新 S4 的竞态。
Host 已增加同 slot/scene 的 S4→S5、S7→片尾单一后继交接，等待 exact close 成功和原暂停释放后走原打开路径；
生产接线及失败/断连/过期/迟到关闭的定向 58/58 通过，原 AS2/Web 协议保持不变。
当前运行的旧候选进程须正常退出后重开；修复后的真实漫画交接未据单测代签。
阶段收口与剩余工作以[唯一设计入口](../../docs/闪客快打6肉鸽-首版设计与施工拆分-2026-10-21.md#0-阶段交付与接续入口)为准。
