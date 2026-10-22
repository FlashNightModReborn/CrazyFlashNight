# CF6 史实章节装配

本目录把已审查的角色、遭遇、经济和地图输入装成 `data/stages/books/cf6-sting.json`，同时生成五档商店、商店登记块与地图环境登记块。它只更新本章拥有的块，保留其他关卡与商店内容。玩法范围及验收边界见[设计基线](../../docs/闪客快打6肉鸽-首版设计与施工拆分-2026-10-21.md)。

输入分工：

- `tools/cf6-actor-template/actor.fragment.json`：固定 60 级 Andy 初装与技能。
- `data/stages/books/cf6-sting-source/`：原坐标遭遇、六个随机枪节点、五个精英配额、五个自选池及技能候选。
- `tools/cf6-map-runtime/generated/`：20张主地图已转为游戏世界坐标的出生点、机关层、碰撞与环境。
- `tools/cf6-tutorial/`：教学室的独立地图和环境片段；章节及环境装配先教学、后20张主图，不混用旧练习场输入。
- `tools/cf6-map-runtime/sky-parallax.fragment.json`：A02/A06 根舞台（root-stage）天空与城市视差层声明（schema `cf6-sky-parallax-fragment.v1`），是这些层字段的唯一真源。装配按 `replaceLayerIds` 移除同 id 旧机制层后按声明顺序追加，拒绝重复 id/角色、未知地图、非 root-stage 坐标、非正尺寸与越界路径；层坐标不做地图原点或世界缩放转换。其 canonical 天空 SWF（`CF6_A02_sky.swf`、`CF6_A06_sky.swf`）已真实 CS6 编译（回执 `tmp/cf6-roguelike-20261021/validation/sky-canonical-r1/`，Compiler 0/0），strict 装配不再因天空资源缺失失败。
- [balance-input.json](balance-input.json)：本轮金币与累计商店选定输入；预算说明由 [economy-budget.py](economy-budget.py) 生成到 [README-budget.md](README-budget.md)。

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

## 当前证据与现场修复（2026-10-22）

20 张原生地图、A01 两门炮塔及 7 段漫画/43 页和片尾已装配；章节、角色和配给生成均需通过不带缺资源豁免的 `--check`。
用户确认基础镜头保持 1，地图当前按 `viewport-policy.json` / `viewport-assembly.py` 适配；
现场已指出家具等物件随背景放大后比例失调，逐图调整物件比例仍待施工和真人观感验收，不能以地图覆盖率代替。

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
本任务未执行 promotion。上游快进包含已跟踪的正式 Core、manifest 和 consensus 更新，与本任务构建独立候选分开记录于 `validation/upstream-merge-r1/formal-tracked-upstream-delta.json`。

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
