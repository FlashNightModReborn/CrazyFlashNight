# 蛮斧刽子手 R2 原生装配与 CF7 战斗接入

**文档角色**：蛮斧刽子手（开发名“蛮蛮”）素材、数值和私有 AI 的维护入口。最后核对代码基线：commit `4cacdc76c1` 加本轮狼跳与接地阴影改动；历史验证结果见 [接入记录](../../docs/CF6蛮蛮-R2-接入与实战复核-2026-10-15.md)。

## 单位与源归属

- 兵种 `463`，linkage `敌人-CF6蛮蛮`，正式显示名“蛮斧刽子手”。单位注册归 `data/units/units.json`，敌人属性显示名归 `data/enemy_properties/CF6重制敌人.xml`；两处由 `balance.py` 的 `DISPLAY_NAME` 同步。开发名继续用于内部 linkage、源文件和实验参数。
- 用户指定阶段 `7`、档次 `9`。其余八项标识以及身高、速度、躲闪、重量、韧性和抗性从“不死兽人”起步。面板由现役 `monsters.ts` 正算，整数结果与输入归 [balance-inputs.json](balance-inputs.json)，运行数据归 `data/enemy_properties/CF6重制敌人.xml`。
- CF6 重制属性按系列集中，装配源仍按角色独立。`balance.py --write` 只替换本单位节点，不重写整张共享表；历史实验仍保留合表前的路径与哈希。
- 认可源稿为 `flashswf/arts/new/Codex素材源稿/CF6蛮蛮-R2/`；`archive-origin.json` 绑定交付 ZIP 和选取成员。原稿只读，不回写原 ZIP，也不修改不死兽人源库。
- 唯一原生编辑源为 `flashswf/arts/new/Codex蛮蛮素材/`。首次从源稿装配后，人工美术编辑继续在此 XFL 进行。重新导入会检查全工程、元件集合及文件身份，发现人工修改就拒绝覆盖。`--force` 会放弃这项保护，不能用于绕过未知改动。
- 发布为 `flashswf/arts/new/Codex蛮蛮素材.swf`，通过 `things-new` 第 4 帧的独立导入锚点接入共享库。新增兵种本身不改变关卡刷怪表。

## 装配与战斗合同

CF6 蛮蛮与 CF7 不死兽人的行走骨架可逐帧对应，差别包含统一平移。装配直接复用兽人的 CF7 动作和注册点，将十二个身体／斧头分件替换成 R2 原生矢量，并移除兽人独有的旧护裆片。SVG 渐变和裁切保留为 Flash 矢量及遮罩，不导入位图。

| 动作 | CF7 接线 |
|---|---|
| 普通斧击 | 34 帧；第 15 帧三个近战判定；第 34 帧回到正常状态 |
| 前踏重击 | 仅保留不死兽人实际使用的 `a0`，33 帧；第 5～13 帧前踏，第 15 帧三个近战判定，第 33 帧结束 |
| 专用狼跳（动作修订，待人验） | 48 帧；1～18 蓄势，19～30 翻身跃进，31 单次落地重劈，32～48 收招；不使用玩家纸娃娃或刀属性公式 |
| 受击 | 两个原有分支，第 15／37 帧结束 |
| 击倒／倒地 | 击倒转倒地；第 14／18 帧走 CF7 死亡检查，第 22 帧起身回调 |
| 血腥死 | R2 原稿的单分支、88 帧死亡动画，保留 31 件血肉矢量；末帧调用 CF7 死亡检测 |

每个命中框沿用 CF7 `近战子弹` 正式结算出口：单次基础威力为单位空手攻击力，纵深判定 30，击倒率 1。三处空间判定不等于对单个目标必然造成三次命中。配表中继承的攻击倍率、段数和霸体系数属于数值建模输入，不会直接改写时间轴伤害。

2026-10-15 增量试测加入每次有效命中 `0.25%` 击溃，普通斧击与前踏重击都显式传入 `血量上限击溃`。比例唯一真源为 `ManmanAI.as` 的 `manmanTuning.crumblePercent`，帧脚本只转发；MISS、盾强门槛、满血值削减与配对伤害继续由原有伤害链处理。三个独立判定各自结算，不新增按整斧去重，也不改变普通伤害、刚体、前摇和收招。额外击溃没有计入原八项整数面板公式，不能把原面板核对当作新增机制的全量强度标定。

未启用兽人时间轴里隐藏的枪击分支。死亡动画使用蛮蛮自己的 R2 源，不沿用兽人旧皮肤死亡画面，也不人为添加另外两种碎尸。CF6 的旧辅助喷血件没有移植，死亡主体血肉与断头轨迹完整保留。

CF6 死亡骨架已烘入 `0.761993408203125` 的比例，生前动作使用 CF7 骨架。`align_death_to_cf7()` 从原稿站立外层矩阵取逆比例，并用两边首帧的骨盆注册点对齐，统一应用于整个死亡动画，包括血肉和斧头；不得只拉伸尸体分件。原稿时间轴保持只读。

每次攻击有独立 token。仅当前存活、未暂停、仍处于该动作且 token 一致的实例可以发出伤害；受击换状态或致死会取消旧攻击，避免离开动作后补发。原两招的刚体只在动作第 8～17 帧持有，结束或取消时恢复进入该窗口前的状态；狼跳窗口见下文。

## 私有 AI

[ManmanAI.as](ManmanAI.as) 作为根元件帧脚本装入，不引入第二份引擎 class。通用 AI 继续管理仇恨，私有控制器同步关闭其自动近身攻击距离，负责纵深对齐、转向、普通斧击、前踏重击与专用狼跳的选择。

参数唯一真源为 `manmanTuning`。当前策略保留换目标反应和各招冷却，按各自有效区间出手；没有合适攻击时继续追击。暂停、浮空、倒地、硬直或玩家手动控制时不主动选招。起手与收招期间保留可反击窗口，动作自身的收招之后不再叠加额外等待。

2026-10-22 专用狼跳首版保持阶段、档次、攻防、生命、韧性及原两招面板不变。横距大于 200 且不超过 440、纵深差不超过 72、冷却就绪时可选择狼跳；其余情况继续沿原策略追击。蓄势开始时冻结目标坐标和朝向，横向位移最多 360，纵深最多修正 60，并在目标前约 70 停下；起跳后不跟踪、转向或补偿被墙挡住的距离。移动经正式敌人碰撞出口以不超过 4 的步长推进，空中演出高度 90 同步实际单位坐标与碰撞箱，取消时只回收本动作仍持有的高度。

狼跳冷却为起手起算 180 个未暂停帧；刚体仅在 19～31 帧持有，蓄势和收招可反击，没有无敌。落地只有一个连续空间判定，基础威力为本单位空手攻击力、纵深 36、击倒率 1，显式继承现有 0.25% 击溃；不继承玩家狼跳的沿途多段攻击。动作使用自身已认可身体／巨斧骨架，空中收腿翻身与落地姿态由 [wolf_leap.py](wolf_leap.py) 确定性装配；修改 `wolfWindup/wolfFlight/wolfImpactFrame` 时必须同步生成器时序并重跑真实时间轴测试。

落地与取消恢复时，Z 与 `_y` 同步归一到 twip 地面坐标，避免 `sin(PI)` 和分段纵移的浮点尾差残留为 0.05 高度。仅隔离实验单位发送 `[MANMAN_WOLF]` 的 `begin/impact/recovered` 观察消息，便于核对真实游戏是否走完新动作；普通单位不发送。这些消息只表示实际动作阶段，不代替伤害结果、玩家体验或发布资格。

首版曾将普通斧击的抬斧片段拉长，再旋转整个身体，缺少玩家狼跳的独立屈膝、压身、空中收腿展体与再举兵器过程；机械专项通过不能证明动作衔接合格。当前修订读取 `things0` 的 `战技容器-狼跳` 身体层，只提取 27 个姿态的关节矩阵，按蛮斧 17 个身体／巨斧实例的关节和握持点转换；参考 XML 纳入生成输入身份。1～18 帧映射参考 1～12 帧，19～30 帧映射参考 12～22 帧，31 帧起映射落地姿态，首尾衔接自身站姿。插值分离旋转与缩放，避免翻身时四肢压扁；地面阶段按脚底对齐，空中去除参考动画内置的整体抬升，由单位控制器提供实际高度。玩家的纸娃娃引用、前置攻击、刀光、武器公式和全程刚体均不导入。落地判定从声明时即透明，避免首帧加载回调前露出辅助框。

狼跳底层独立复用原站姿的 `Symbol 2` 矢量影子，保持原尺寸与单位局部偏移。每次位置更新后将当前 Z 地面点转换到动作局部坐标，兼容左右朝向和单位身高缩放；影子随实际横移与纵深修正贴地，不随身体抬升或翻转。显示遵循 `_root.是否阴影`，结束或中断时随动作实例回收。

刚体受击仍可能保留移动钝感硬直标记；它不应单独吞掉落地命中。狼跳与原斧击一样，以 hp、暂停、动作状态和 token 判断伤害资格，真实被击／击倒换状态或死亡仍使旧攻击作废；本招不修改全局受击、韧性或击退规则。

`蛮蛮AI模式="baseline"` 仅在 `_arenaCalibrationUnit=true` 的隔离实验单位上允许，使用通用近身攻击与前方几何感应。普通游戏强制使用 `enhanced`。两种实验模式共用同一素材、数值、判定和刚体窗口，只用于比较决策差异；baseline 不是原版不死兽人的完整复刻。

`蛮蛮击溃模式="off"` 也只在隔离实验单位上生效；普通单位保持配置的击溃比例。它与 AI 模式独立，击溃对照双方都使用 `enhanced`，避免把 AI 改善混入击溃收益。

## 维护与验证

Python 需要现有 `lxml`；捕获解码另需 `Pillow`。数值正算使用仓库已有 balance-tool 的 `tsx`。不通过脚本安装外部依赖。

```powershell
chcp.com 65001 > $null

# 原稿/配方修改后，受保护地重新装配；已有人工原生修改时先处理差异
python -X utf8 -B tools/cf6-manman-assets/build.py --import-approved
python -X utf8 -B tools/cf6-manman-assets/build.py --check

# 数值输入改变时正算并核对；不修改公式本身
python -X utf8 -B tools/cf6-manman-assets/balance.py --write
python -X utf8 -B tools/cf6-manman-assets/balance.py

# XFL 治理与全仓来源登记
python -X utf8 -B scripts/tools/xfl/audit.py 'flashswf/arts/new/Codex蛮蛮素材'
python -X utf8 -B tools/linkage_scanner/scan_linkage.py --xml-only

# 原生资源和共享库分别由真实 CS6 发布
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target 'flashswf/arts/new/Codex蛮蛮素材/Codex蛮蛮素材.xfl' -PublishOnly -VerifySwf 'flashswf/arts/new/Codex蛮蛮素材.swf' -TimeoutSeconds 180
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target 'flashswf/arts/things-new.fla' -PublishOnly -VerifySwf 'flashswf/arts/things-new.swf' -TimeoutSeconds 180

# 编译后校验实际导出/导入、零位图、class 权威、BOM、数据与原生身份
python -X utf8 -B tools/cf6-manman-assets/verify.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-manman-asset-tests.ps1

# 固定比例捕获站立、死亡首帧、并排切换对照、命中姿态与死亡后段
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-manman-asset-tests.ps1 -Capture
python -X utf8 -B tools/cf6-manman-assets/decode-native-capture.py scripts/flashlog.txt tmp/manman-native-capture-new

# 真实时间轴连续捕获左右各 48 帧；解码为两张 8×6、每格 300×320 的图集
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-manman-asset-tests.ps1 -MotionCapture
python -X utf8 -B tools/cf6-manman-assets/decode-native-capture.py scripts/flashlog.txt tmp/manman-native-motion-new
```

专项 TestLoader 加载实际编译的 SWF，覆盖左右朝向共 42 个动作组合，含关闭击溃时的斧击／狼跳、固定落点、纵深上限和小幅修正的精确落地、碰撞阻挡、暂停、前摇／空中受击和致死取消、刚体期间移动硬直不吞攻击、刚体／高度回收、单次落地判定及不可移动的收招窗口；另检查私有选招、手动控制和普通单位不能关闭击溃。普通模式包含 458 项断言；连续捕获模式另检查左右各 48 帧完整、首帧判定隐藏及图集原生像素。阴影专项覆盖四阶段贴地、身高缩放、双向显示开关及收招回收。初始化与伤害出口使用内存替身，不能代证正式战斗结算；本轮证据在 `tmp/manman-wolf-20261022/`，动作修订与旧首版分目录保留。击溃／护盾／MISS 等真实伤害合同另跑 `scripts/run-combat-hp-impact-tests.ps1`，真实对战由隔离 Worker 补验，机器验证不代替玩家平衡体验。

动作修订前的首版另有 AI 诊断回归 98 项通过，其四场真实远程／纵深错位换边对战均自然终局，四次新招均观察到第 31 帧命中和第 48 帧收招；落地高度均为 0，其中两次在刚体带移动硬直时仍正常发出攻击。资源身份、测试种子、真实存档保护和 owned 清理均通过。场景使用原生 AI 和不等强单位，只证明专项接入，不作为玩家平衡认证；旧首版实战不能代证动作修订后素材的实战验收；60 的修正上限及小幅纵移的精确落地由上述原生动作专项覆盖。首版汇总 `tmp/manman-wolf-20261022/summary.json` 保留其 SWF、原始行与历史失败／超时。

补影前的动作修订素材通过真实 CS6 连续捕获模式 431 项断言、0 失败，Compiler 0/0，左右各 48 帧完整；另有两场远程单位换边对战自然终局，均观察到第 31 帧命中、第 48 帧收招及零残留落地高度。实际资源身份、存档保护、测试种子与 owned 清理通过；该轮汇总 `tmp/manman-wolf-20261022/motion-revision-summary.json` 绑定对应素材和回放，玩家参考图只解析源姿态，不执行其装备脚本或滤镜。接地阴影补全后的素材另通过 470 项连续捕获检查、0 失败，Compiler 0/0，原始证据与双向整招图集保存在 `tmp/manman-wolf-20261022/shadow-fix/`。旧素材实战与新素材阴影专项分层陈述，素材提交不代表正式 runtime 部署。

死亡尺寸回归在同一父坐标系比较站立和死亡首帧的宽高、脚底与水平位置，左右朝向都要求差值小于 `0.25px`。像素捕获必须带上动作实例的父层矩阵、固定像素比例和基准点，禁止逐姿态自动适配画布；自动适配图只能说明形状，不能证明动作切换时的尺寸连续性。

## 隔离实战

[arena-plan.js](arena-plan.js) 接受一个 JSON 配置，必须显式给出新 `experimentId`、`mode`、绝对 `candidateRoot` 和只读测试 `seedPath`；可选 `levels` 为 1～99 的一至三个不同等级。候选必须先经正常开发构建入口取得身份。复用同一实验 ID 会拒绝覆盖历史结果。

有并行编译时用显式 `projectRoot` 指向本任务独占的 Git 资源副本，并在其 `tmp/runtime-candidates/v2/<leaf>` 下保存同身份候选；复制后重新核验 Core、build identity 和 payload closure。计划自动将主工作区和资源副本的 saves 都加入保护。`verify.py --runtime-root <owned-checkout>` 可对该实际运行快照执行原有 class 权威检查，但要求蛮蛮 SWF 与编辑工作区逐字节相同，不借另一版素材通过。副本归档前必须保留其原始战斗结果及清理记录。

- `pilot`：30 级同属性 AI 换边对照，以及与不死兽人的换边比较。
- `ai`：指定等级的同属性 AI 换边对照，每边一场，默认观察上限 180 秒；`mirrorTimeoutFrames` 可显式设为 1800～8100 帧，最长 270 秒。默认等级为 30／60／99。
- `integration`：指定等级与不死兽人换边比较，另有 30 级两对两纵深错位场。
- `crumble`：指定等级分别运行双方关闭击溃、仅候选开启击溃的换边场，双方固定使用 `enhanced`；另运行 30 级蛮蛮加不死兽人的两对两换边场。首轮配置为 `levels:[60]`，共 6 场；必须与这批同 AI 对照比较，不借旧 AI 对照的时长宣称击溃收益。

```powershell
node tools/cf6-manman-assets/arena-plan.js <explicit-config.json>
node tools/arena-calibration/run-worker-experiment.js --plan <returned-experiment-plan.json>
```

这是有界开发复核，不是 Gate F 全量强度认证。对战不死兽人包含阶段／档次差异；仅同蛮蛮、同等级、双方 `startMaxHp` 一致的换边场用于讨论 AI。胜率样本较小，不报告统计显著性。

Worker 运行期间冻结数据和 SWF；使用独立测试克隆及真实存档保护快照，结束后检查 owned 清理、资源身份和保护快照。超时保留为超时，不当作胜利或通过。机器战斗、原生截图、人类对战手感与正式 runtime 部署分别陈述。
