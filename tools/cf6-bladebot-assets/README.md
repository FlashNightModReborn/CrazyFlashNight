# CF6 大刀机器人 R2 装配

大刀机器人使用独立原生库 `Codex大刀机器人素材`，兵种 **465**，链接 `敌人-CF6大刀机器人`。阶段 **8**、档次 **9** 按制作组指定配置，定位为纯近战小 Boss；属性归入共用 `data/enemy_properties/CF6重制敌人.xml`。常规重启后可在斗兽场搜索“大刀机器人”。

## 真源与加载

- 原交接包：`05-source.zip`，SHA-256 `a689834247d252b500d0ecfdbd6ed75f1744b0e0a4f7f5ddd234eae40db7cb72`。原包保留不变。
- 冻结输入：[`CF6大刀机器人-R2`](../../flashswf/arts/new/Codex素材源稿/CF6大刀机器人-R2/archive-origin.json)，保存 38 个输入及逐文件摘要；包内脚本和旧混淆 AS2 不执行。
- 唯一编辑源：[`Codex大刀机器人素材.xfl`](../../flashswf/arts/new/Codex大刀机器人素材/Codex大刀机器人素材.xfl) 及同目录完整工程；由 CS6 发布旁边的同名 SWF。
- 共享入口：`things-new.fla` 第 4 帧挂载自身 RSL 锚点，`things-new.swf` 的实际 ImportAssets 指向独立库。仅索引登记不视为加载完成。
- 注册与数值：[`balance.py`](balance.py) 只改本单位，使用工作簿对应的 [`computeMonsterRow`](../cf7-balance-tool/packages/core/src/formulas/monsters.ts)；[`balance-inputs.json`](balance-inputs.json) 保存其余设计输入与整数面板。台账只将用户明确给定的阶段、档次登记为固定声明。

速度、攻速、倍率、段数和霸体系数遵守[怪物标识规则](../cf7-balance-tool/docs/monster-flag-rulebook.md)，不作为自由调参项。前摇均值 18.5 帧、后摇均值 15 帧，按 0.2 后摇权重落在攻速 3 档；重劈两段、横扫前后各三段，单方向有效段数均值 2.5。受击恢复为 8/7 帧，击飞与倒地都接入物理委托，因此霸体标识为短击退可击飞 2 档，加韧性 100 对应的 0.5；攻击过程的临时抗打断不把该标识改成“不可击飞”。数值校准只调整成长和攻防分配等自由量，阶段 8、档次 9 固定。

## 动作和战斗边界

| 动作 | 来源与接线 |
|---|---|
| 站立、行走 | 原 901 / 902 时间轴；行走兼作跑步外观 |
| 重劈 | 原 910，37 帧；第 20/22 帧各一次 2.4 倍物理近战判定，构建器核对两帧刀身姿势一致；第 9–18 帧沿真实移动接口压进，每次至多 8 像素，接近目标 185 像素时停止 |
| 左右横扫 | 原 912，49 帧；第 19/22/25/28/31/34 帧各一次 1 倍判定，前后各三次 |
| 受击 | 原 913 的 a0/a1 分支，分别在第 8/19 帧回到 CF7 正常状态 |
| 击飞、倒地、被投 | 原包没有完整对应动作；使用原受击姿势衔接 CF7 浮空、落地和恢复生命周期 |
| 死亡 | 原 924 的完整 58 帧，保留 916–923 八组机械碎片；结束调用 CF7 死亡结算一次 |

原 906“攻1”含远距离光束，按纯近战要求不接入可执行动作。重劈刀光 909 保留；不新增远射或弹幕。

近战区域沿用原 CF6 判定的横向跨度，并转换为 CF7 的纵向受击体积：重劈高 180 像素，横扫高 200 像素，下沿接世界 Z。它是游戏近战区域，不是刀刃逐像素碰撞。显式传入当前 `攻击点.area`，速度为零，通过正式 `子弹区域shoot传递` 结算；无百分比伤害、击溃或旁路扣血。自身命中率输入为 30，仍进入正式闪避结算。

私有控制只负责本单位的近战选择和压进。通用 AI 继续提供仇恨目标；私有控制同步攻击距离缓存，先对齐纵深，再选择重劈或横扫。重劈第 1–30 帧、横扫第 1–40 帧持有临时刚体和抗击退，正常承受伤害；收招末段、中断或死亡后恢复原值。该范围包含原稿刀势保持阶段，不修改动画帧数或增加出手。目标高度按既有近战合同计算为 `Z轴坐标 - _y + 有效正浮空高度`，兼容只移动受击区域的原生腾空动作。高度超过 80、但不超过 150 像素时，仅在 190 像素内选择横扫；更高目标不出手。横扫冷却 75 帧。动作 token 与当前 `man` 双重绑定，旧剪辑、暂停、硬直和死亡不能继续发出命中或位移。

受击使用“火花”；死亡调用共用“火花”和“小烟雾”表现一次。已核对两者依赖中的脚本只有选帧和自身移除，不发伤害、不移动世界。首次候选用过的“小火焰爆炸”含世界坐标和子弹威力脚本，已在正式交付素材中移除。

## 矢量、尺寸与影子

`vector.py` 在现有渐变转换器上补充两项本角色需要的语法：刀孔的两个半圆弧转为四段三次曲线，死亡材质图集的本地 `use` 引用转为可复用 Graphic。其他弧、外部引用和嵌套引用均拒绝。八组碎片共用一份矢量图集，保留原剪裁、材质矩阵与透明孔洞；角色本体与碎片没有位图填充。

各动作保留原注册矩阵，外层统一减去站姿脚底的 `44.03251647949219` 像素偏移。原死亡首姿另有 0.85 像素下移，按相同分件对齐消除。固定取景检查站立和死亡首姿同高、同横向位置、同接地点，不以自动缩放图掩盖尺寸差异。

独立 `bladebotShadow` 覆盖站立、两种攻击、受击、击飞、倒地、被投和死亡，消失态退出。影子以世界 Z 接地，处理镜像、旋转和缩放，动态跟随阴影开关；不写入历史 `unit.shadow` 或 `gameworld.shadow`。

## 生成与验证

所有命令从仓库根执行，PowerShell 先 `chcp.com 65001`。

```powershell
python -X utf8 -B tools/cf6-bladebot-assets/balance.py --write
python -X utf8 -B tools/cf6-bladebot-assets/build.py --import-approved
python -X utf8 -B tools/cf6-bladebot-assets/build.py --check
python -X utf8 -B tools/cf6-bladebot-assets/test_vector.py

powershell -File scripts/compile_test.ps1 `
  -Target 'flashswf/arts/new/Codex大刀机器人素材/Codex大刀机器人素材.xfl' `
  -PublishOnly -VerifySwf 'flashswf/arts/new/Codex大刀机器人素材.swf' -TimeoutSeconds 180

# 新增或改变共享锚点时才编译共享库。
powershell -File scripts/compile_test.ps1 -Target 'flashswf/arts/things-new.fla' `
  -PublishOnly -VerifySwf 'flashswf/arts/things-new.swf' -TimeoutSeconds 180

powershell -File scripts/run-cf6-bladebot-asset-tests.ps1
powershell -File scripts/run-cf6-bladebot-asset-tests.ps1 -Capture
python -X utf8 -B tools/cf6-bladebot-assets/decode-native-capture.py <本轮trace> <新的图片目录>
powershell -File scripts/compile_test.ps1 -StopTestPlayers -TimeoutSeconds 60

python -X utf8 -B tools/linkage_scanner/scan_linkage.py --xml-only
node tools/derive-arena-unit-catalog.js
node tools/derive-arena-unit-catalog.js --check
python -X utf8 -B tools/cf6-bladebot-assets/verify.py --runtime-root <本轮冻结资源目录>
```

生成器使用完整工程身份保护，不提供强制覆盖开关。测试 `.as` 保持 UTF-8 BOM；只发布独立资源和受影响共享库，不因此重编主文件或 asLoader。

专项真实 Flash 测试覆盖 22 组动作过程和 14 状态 × 2 方向的身体、影子检查，包括真实近战区域、精确出手次数、伤害参数、镜像、有限压进、刚体恢复、动作中断、致死取消、浮空委托和死亡结算。伤害入口与初始化在该专项中是内存夹具，不能代签实际对战强度。

本轮最终普通专项与整单位截图专项均为 **300 passed / 0 failed**，Compiler `0/0`、32K retry `0`。截图专项使用的实际素材 SHA-256 为 `d4dc955f19e7ad41e2da1018a8ab5f4af6469a762a2793c4a2e3ad4a6a9195c8`；[截图记录](evidence/20261016/logs/native-capture-review.json)保存八张图片的摘要与检查范围。已逐张查看站姿、死亡首姿、重劈、前后横扫、碎裂前后及浮空镜像姿态；这仍是 Agent 视觉复核，未代替制作组的动画手感验收。

最终库为 48,150 字节，71 个 Shape、19 个 Sprite、0 位图。XFL 的 110 个元件、771 处引用审核无断链；隔离资源目录的[生产类归属全量检查](evidence/20261016/logs/native-class-closure-r8.json)覆盖 699 个 SWF，`closureChecked=true`、错误 0。

## 对战目标与证据口径

目标为同等级下稳定击败兵种 347“黑铁会改造人”（当前显示名“诺亚试验体α”），并能对兵种 286“方舟爪豪”造成有意义的威胁。只调整本角色，不修改两位对手。

[`arena-plan.js`](arena-plan.js) 生成封存的试跑或复验计划，要求明确资源目录、候选运行时和只读种子。每个等级、对手都交换红蓝，重复数限于 1–3；至少 360 像素出生距离，分片预算和全局存档保护沿现有 Worker 合同。`mode=pilot|confirm`、`levels`、`repeat`、`spawnDistance` 与可选 `performance` 均记入计划。

首轮后台测试发生世界画面捕获故障，尚未生成参战单位；`bridge_lost`、主动取消及前置检查失败均保留，不能作为胜负或性能样本。早期参数探索也单独保存，不混入最终配置的胜率。素材专项与实际对战分别记录，不能从阶段、档次或夹具通过数推定胜率。

后台捕获不可用时，本轮使用现有 `run-unattended.js` 普通窗口入口。包装脚本 [`run-foreground.ps1`](run-foreground.ps1) 只接受独立候选目录和专用测试槽，复用本机已安装依赖，保留原准入检查、零自动重试与结束关机；临时显示活动请求在退出时释放，不修改电源方案。脚本本身不操控窗口，实际画面持续推进仍由运行回执判定。本机另记录了窗口出现后约 50 秒的 Shift 单键与状态刷新，以及较长批次中的少量同类检查；未发送移动或攻击指令。窗口操作与前台条件必须保留，不能把这组对战称为后台性能证明。

```powershell
node tools/cf6-bladebot-assets/foreground-evidence.js before <显式配置.json> <新的before.json>
powershell -File tools/cf6-bladebot-assets/run-foreground.ps1 `
  -ResourceRoot <隔离资源目录> -CandidateRoot <该目录内的明确候选> `
  -Manifest <冻结case-manifest.json> -Slot <新cf7_agent_测试槽> -SeedSlot <只读种子副本槽>
node tools/cf6-bladebot-assets/foreground-evidence.js after <同一before.json> <本轮run-report.json>
```

[`foreground-evidence.js`](foreground-evidence.js) 复用现有资源与存档快照算法，核对结果身份、自然结束、实际运行时、资源前后一致、玩家存档保护和进程退出。它保留普通 Launcher 更新本测试副本 `.launcher-version-marker.json` 的原始差异，单独说明该启动元数据，不把全目录差异改写成零；扫描闭包仍遵从底层 `completeResourceClosure` 口径。

## 本轮固定配置实测

[逐场结果与运行身份](evidence/20261016/combat-summary.json)绑定同一份素材、AI 和数据；[完整文件校验清单](evidence/20261016/summary.json)保存原始回执、失败记录、源文件身份及无损压缩映射。下表来自四个全部自然结束、保护检查通过的独立批次，共 18 场。双方始终同等级，出生距离 650，交换红蓝位置；仅本单位被调参。

| 对照 | 等级 | 机器人胜场 / 场数 | 结算观察 |
|---|---:|---:|---|
| 黑铁会改造人（显示名：诺亚试验体α） | 30 | 4 / 4 | 机器人余血 22.8%–31.6% |
| 黑铁会改造人 | 60 | 4 / 4 | 机器人余血 24.7%–38.7% |
| 黑铁会改造人 | 99 | 4 / 4 | 机器人余血 10.0%–22.5% |
| 方舟爪豪 | 30 | 0 / 2 | 对方净损失生命 15.2%–15.3% |
| 方舟爪豪 | 60 | 0 / 2 | 对方净损失生命 16.7%–17.8% |
| 方舟爪豪 | 99 | 0 / 2 | 对方净损失生命 19.0%–21.2% |

30/60 级黑铁会和全部方舟对战使用 3600 帧窗口；99 级黑铁会使用 5400 帧窗口（30 FPS 下分别为标称 120/180 秒）。最初同配置的一批为四场胜利、两场 99 级在 3600 帧时双方仍存活；该批整体单列，原超时没有改写成胜利，也没有只挑其中四场放入表中。随后四场独立的 99 级长窗口对战均自然获胜，实测约 126–144 秒。相同配置的全部运行总数是 **24 场：22 场自然结束、2 场超时**，机器汇总同时保留两种统计口径。

完整复验支持“在本轮同级样本内稳定击败黑铁会改造人”的定位；对方舟爪豪能造成约 15%–21% 的净生命损失，六场均未获胜。净损失由结算剩余生命计算，不是逐击累计伤害统计；有限 1v1 样本不证明任意种子、群战或玩家实战的通用胜率。

四个完整批次的已记录资源前后一致，玩家存档保护通过，测试 Host/Flash 已退出；测试副本自身启动版本标记的变化保留在原始差异中。最终 [站姿](evidence/20261016/images/stand.png)、[死亡首姿](evidence/20261016/images/death-start.png)、[浮空影子](evidence/20261016/images/airborne-shadow.png)及其余五张原生截图均可复核。

上述运行证据采集时尚未提交推送；后续源码提交不改变这些证据的范围。本轮未进行正式 runtime 发布，最终外观、打击感与标准入口体验仍需人类验收。
