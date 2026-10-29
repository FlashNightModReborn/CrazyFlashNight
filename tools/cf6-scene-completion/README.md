# CF6 场景机关、人物通行与车辆规则

本目录承接[章节设计基线](../../docs/闪客快打6肉鸽-首版设计与施工拆分-2026-10-21.md)的机关演出与车战后续。
2026-10-23 已接收额外门、电梯和车辆源资产，并按追加授权修复摆件比例、前后层与原作机关触发。
共享 CS6 由根队列串行调度；独立资源编译和真实 AVM1 测试分别保留当轮源码、SWF、Compiler 与行为证据。
可打击油桶及靠近破碎的活体培养皿另接真实伤害、出生及原遭遇配额，不能由静态缩放代签。

施工基线 `cc5cd91d5ae96fac4532401188dc077151d8de7d`。生产接线由
[`scene-assembly.py`](../cf6-prototype/scene-assembly.py) 与 `Cf6MapMechanism` / `Cf6TraversalService` 持有。
现役终局按[章节装配](../cf6-prototype/README.md)合并为A20同房间两阶段。2026-10-24的章内难度源已重排普通必清波次，培养皿、运输车及精英奖励仍各守原配额。A07完整车战已接入本轮源码，原生资源和服务的唯一入口为[车辆工具链](../cf6-vehicle/README.md)；本目录继续拥有`Cf6VehicleRules`编辑源。

## 生产接线与恢复边界

`Cf6TraversalService` 与 `Cf6MapMechanism` 已接现役人物的 `状态改变(攻击模式+行走/站立)`，
不复制原作人体/武器。章节生成器给 `mechanism.traversal.arrive/depart` 最终世界脚点，离场同时给
`gate{x,z,radius}` 与失败恢复用标准出口 `exit{x,z}`。清场只锁存权威；门口到达后才接管，完成后
由真实 `clearStage` 加 exact 一次性票据请求 `StageManager.requestCf6DoorAdvance`，沿原内存转场记录
与淡出权威自动离场。成功保留最终门内姿态直到被遮罩覆盖的原场景拆除，不回填门前闪现。
明确拒绝才归还标准手动出口；未知结果不重放，不清既有持久化锁。1729 第 122 帧归还人物，门继续至174。

人物输入用独立暂停 claim，控制块回调用普通对象 token 与函数 CAS 管理。普通死亡暂停本房间机关并归还人物控制，保留已有波次和资源；仅同世界、同人物出生身份的实际复活能恢复。未完成的登离场从既有冻结轨迹重新开始，已完成轨迹不重播；真正换人、换世界、关卡失败或返回才清理。`PauseManager.isPausedExcept`只豁免确切存活claim，其他同名owner、手动暂停和奖励持久写pending仍冻结演出，不借复活解除持久写锁。

整备入口由 `Cf6ActorRefreshPolicy` 做只读准入：SceneReady 的到达准备、尚未释放人物的入场、已接管人物的离场，以及电梯的受控站姿期间，暂缓打开角色构筑或装备调制并提示等待。`InventoryPanelService` 的生产 opener 与 `CharacterBuildService.canOpenPanel/open` 都执行检查；拒绝发生在新会话建立和装备重建之前，不创建暂停 claim、写存档或消费 generation；若已有会话处于保存结果未知状态，只返回拒绝并保留原会话，不退休恢复 owner 或重放保存。人物在原定释放帧恢复控制后，即使门动画尚有尾段也可正常整备；战斗及尚未触发的出口不受限制。换装会重新按人物脚点排列层级，不能在门演出持有固定排序深度时执行，也不能通过放宽演出的外部接管检查来兼容。专项入口为 [`run-cf6-actor-refresh-tests.ps1`](../../scripts/run-cf6-actor-refresh-tests.ps1)，包含真实 AVM1 深度冲突反例及拒绝、释放、换世界和电梯边界；它不代签完整 A05 实机过关。

电梯准备、移动结束及开门等待期间接管人物站姿，登离梯路径才显示行走；正常战斗阶段的移动能力保持。真实清场提示先锁存，等待人物可见且入场完成后只显示一次统一的“OK LET'S GO”，与最后的标准`clearStage`提示去重。

现役`SceneReady`资源就绪屏障同步准备入场显隐与方向token，覆盖`beginRoom`在其之前或之后的顺序。资源加载等待期间不露出默认出生点，首个有效轨迹样本就位后才恢复原可见性；原本隐藏、外部mask及被替换owner不强行显露。朝向按冻结轨迹的主运动轴确定，竖向轨迹保持接管时方向，不再逐帧把鞋锚摆动当转身。离场明确受理后另登记现役`PlayerSceneLifecycle`意图，登记失败保留未知状态，不重放淡出。

原作 1720/1750 的触发是实际击杀达标且门区与人物 area 相交；1714 仅随真实出生事件播放木门；
1729 是场景到达演出；1587 是电梯清场监视器。这些事实不授予普通静物交互。A10/A13 连续登离梯
属于 CF7 补齐，使用既有平台锚点与轴道前景；未取得原作门叶的地方不虚构新门叶。

focused 生命周期、标准交接、生产机制、真实资产和装备外观各有独立 runner，预期断言以各 runner 为准。
持枪通行只固定上身原生“空闲”，由实际独立腿时间轴继续行走；不遍历完整枪械上身数字帧，以免执行射击和装填帧脚本。
出口提示在待战阶段半透明可见，真实清场后亮起，离场演出中隐藏；不再依赖正式Clear后才出现的旧箭头。
静态/Node 结果不代签真实 AVM1、完整章节与人眼验收。人物遮罩使用独立位图代理：
仅在 `Cf6ActorMaskState` 记录的受控主角出生时已知无外部 root mask 合同时，用 `BitmapData.draw(actor)`
画独立代理；不写人物 `setMask` 或父链，未知 root mask 不冒称可保真恢复。只有原活动帧临时隐藏本人；
未知或外部 root mask 被明确拒绝；既有内部面具仍随真实外观一起绘制。复杂变换、装备外观和游戏可见性需分层验证。

补充资源1430出口门、1862木门和1832摄像头分别由真实离场、真实出生事件与环境循环驱动。
`SceneReady` 到 `beginRoom` 之间的出生事实只缓存同一 World/StageManager/局次的有界事件，避免首批出生早于机关订阅；
不枚举现有敌人补造出生，不重放刷怪或修改击杀配额。原作门轨迹按固定门槛深度夹在 Back/Front 之间，
人物脚点在画面内移动时不穿出两层排序；取消只归还仍属于本服务的姿态、深度和输入槽位。

`Cf6InteractivePropService` 消费 [`interactive-assembly.py`](../cf6-prototype/interactive-assembly.py)
生成的 `mechanism.interactiveProps`。原作14个可爆桶分布于A04/A08/A11/A12/A18/A20；
10个活体培养皿仅在A15/A17各5个。它们是独立world实例，不在背景图内；不删除66对静态1901/1906舱体或9个装饰桶。
油桶作为中立地图元件接受现有伤害结算，保留 `element` 排除敌人击杀配额；第7帧只发一次现役普通爆炸，
采用物理威力100、Z范围80和击倒0.5。发射者为友方机关，玩家不列为敌方目标；不直接遍历扣血或产生奖励。

桶的原注册点、物理 `groundY` 与显示 `sortY` 分开，视觉保持原生大小。原作脚部命中区域与命中效果的−90px投影
不能直接当作现代屏幕碰撞框；本章仅对桶合并静止首帧外框、原脚部区域及其投影带，作为射击兼容包络，
不把爆炸碎片范围或可见画稿放大。该包络与实际M4A1枪口、过高及错Z拒绝分别验证。

培养皿使用原矩形区域接触与第24帧出生节点。A15把已有五只的计数波次拆成五个精确 `Cf6PodReady` 事件；
A17仍由原有限Boss支援控制器持有预占、并发上限和取消，只增加逐皿就绪门。等级、兵种460原型复用与总数保持原预算。
同一事件只尝试一次，实际出生及完整初始化后才结束；未知结果不重放。普通清场后桶仍可活动，培养皿不再请求出生。

A17等待支援名额时保持完整舱内画面，控制器领取名额后才显示短交接姿态；真实单位完整初始化后结束。Boss死亡取消已启动的舱体画稿，未触发的舱体保留；晚到加载或出生回调不能重新激活取消项。运输车在本房间清场后保持最后开门画面，真实离场、失败或世界身份更替才卸载。

## 清场提示、乘梯站姿与场景 Wings

清场提示由 `Cf6ExitGuideService.showClearCue` 在真实清场请求锁存、入场完成且人物已可见后调用现役“小过关提示动画”；
其普通对象回执绑定 World owner、StageManager 和 stage，最终 `clearStage` 只跳过同一回执的重复投射。
提示不提前发布 Clear、不开放出口；投射异常也不按帧盲重放。待战箭头与真实门口接管规则保持不变。

电梯关闭和清场后的减速／停稳阶段由 `holdElevatorActor` 切换人物真实 `攻击模式+站立` 根姿态，
并以独立 token 与回调 CAS 暂时接管输入。它不在旧行走腿帧上调用 `stop()`；原生腿的 enterFrame 因而不能重新播放旧走路姿态。
正常释放只归还仍属本服务的输入槽，不回填旧行走或死亡姿态；登梯、离梯仍由原通行轨迹走路，移动战斗阶段保留自由输入。
同路径重建、外国回调替换、死亡与登梯归属分别由 mechanism focused 覆盖；真实长枪／手枪／双枪腿部停步另由 traversal-native runner 验证。

`build_scenic_wings.py` 从现役 Wings R3 的 15 帧站姿导出独立纯矢量源，递归移除脚本、声音与 linkage，
保留当前 190cm 身体标定。第五轮核对原作1777的粉发/粉衣后，独立 `scenic-wings-palette.json` 对33份身体分件作显式色表适配；皮肤、武器、渐变透明度、动作和注册点保持，蓝色敌方Wings源不改。色表、原作身份和全部分件共同进入manifest及实际消费者闭包，真实AVM1两侧像素验证粉色主体。A06/A08 的位置和朝向来自冻结原 SWF 的 world1778/depth186 与 world1841/depth158；
原 sprite1777 及依赖 sprite1772 均无帧或子实例脚本，外层实例只排序，不能据此新增可受伤目标、AI、血量或保护任务。
A06 头顶保留原触发器1455的“Andy！救我！”直到真实清场请求；A08只补赛车旁人物，不扩写对话。

```powershell
python -X utf8 -B tools/cf6-scene-completion/build_scenic_wings.py
python -X utf8 -B tools/cf6-scene-completion/build_scenic_wings.py --check
python scripts/tools/xfl/audit.py flashswf/backgrounds/cf6/preparation/CF6_ScenicWings
# 由已获授权的根编译队列串行执行：
powershell -File scripts/compile_test.ps1 -Target flashswf/backgrounds/cf6/preparation/CF6_ScenicWings/CF6_ScenicWings.xfl -PublishOnly -VerifySwf flashswf/backgrounds/cf6/preparation/CF6_ScenicWings.swf
```

14个可爆桶均以原作世界脚点保持落地；本体原生尺寸不变，只反算注册点：
`displayY=(nativeY+localFloorY)*mapScale-localFloorY`。当前三个桶型的局部底边为44.5，
因此相对旧中心缩放放置下移31.4467世界像素。`groundY/sortY`使用修正后的真实脚点，原相对命中包络及十个培养皿出生点保持不变。
源码、装配检查、CS6编译、原生行为与实际游戏视觉分别留证，不能互相代签。

## 已准备的可消费内容

- `source-evidence/original.json`：固定原 SWF 的 19 个时间轴、逐图摆放与 216 条原脚本记录；
  对应脚本文本按内容摘要保存为不可执行的 `.as.txt`。捕获原件不执行旧 AS，也不复制它的存档/奖励副作用。
- `completion-plan.json`：A03 离场、A04 到达/离场、A05 到达/离场五条轨迹；两段电梯的接线规格；
  A07 三段遭遇、双枪时钟、Boss 原帧点、尾段和 40,000 金币唯一迁回安排。它不是生产章节配置。
- `traversal-art-manifest.json`：三种门的完整前景、后景与人物遮罩，共九个独立 XFL 源工程，
  位于 `flashswf/backgrounds/cf6/preparation/`。保留 174/174/40 帧源时间轴与矩阵，人物改由现役外观承担。
  大门没有人物遮罩，其 Mask 工程为空的源时间轴占位，消费者不得加载它或把空遮罩套在人物上。
- `vehicle-art-manifest.json`：装甲车车体、车轮、A08 R5 玩家赛车、道路的可编辑源与原生矢量片段，
  附原纹理字节及 CS6 导入配方。道路的两处磨损沿用已存在的 A08 有界噪声转换；此处仍需实机比较。
  车体字体从同族字体文件显式迁移，冻结实际字节和 DejaVu 许可证，不冒称与旧预览逐像素相同。
- `Cf6TraversalRules.as.txt`、`Cf6ElevatorRules.as.txt`、`Cf6VehicleRules.as.txt`：规则真源，通过 `install_rules.py` 复制既有
  BOM 文件后生成同名 AS2 类。只处理轨迹、有限状态和事件去重；不直接移动人物、扣血、发奖或跳地图。
- `Cf6SceneCompletionTest.as.txt`、生命周期与离场 fixture：通过 `run-native-tests.ps1` 在真实 CS6/AVM1 中执行。
  每次变更后以新鲜 Compiler 与同 runId 的完整行为区段判定，保留失败原件。
- `auxiliary-art-manifest.json`：额外三类原生门/摄像头的源与纹理闭包；消费者只使用已注册的独立 SWF。
- [`interactive-art-manifest.json`](interactive-art-manifest.json)：三种16帧油桶与25帧活体培养皿的完整原生源，
  73帧包含原空终帧；生成、真实纹理导入和原注册点合同见[交互美术](interactive-art/README.md)。
- [`transport-art-manifest.json`](transport-art-manifest.json)：1868运输车的完整29帧、原触发区域及A09/A14/A18精确摆放。
  `build_transport_art.py --assemble --check` 核验原生源与唯一TransportTextureSeed；生产服务在第29帧锁存，
  等同一第二波监听器就绪后发布一次 `Cf6TransportReady`。原WaveSpawnWheel持有5/7/5敌人数量；异常发布保留未知结果，不自动重放。

## 原作事实与改编边界

A03 的门 1720 原有 174 帧，旧装配只取前 50 帧门叶；A04 还摆放了未接线的另一扇 1720 离场门。
1729 到达演出在第 122 帧恢复人物，门继续运动至 174 帧。原遮罩覆盖 1720 的第 136–174 帧、
1729 的第 1–39 帧，覆盖整个人物；已拆出可供现役角色使用的遮罩源。

轨迹脚点取原鞋形 1021 的变换后外框，是几何推导的参考轨迹；不是 CF7 角色真实脚底、碰撞或姿态验收。
后续适配必须保留当前装备外观、按现役地图原点与倍率换算一次，并校准脚底和门框比例。
原图中的人体分件/旧枪不会复制到新门工程中。

A10/A13 原轴道有 37 帧循环，原清关监视器 1587 在 59 帧段末交给切镜。原始切场本身不能证明
已经存在连续的登梯/离梯人物轨迹；计划里的连贯登梯、停靠和离梯属于 CF7 演出补齐，明确作为改编。
保持原遭遇与清关权威，不用倒计时伪造战斗完成。

A07 原公路以 30 次最终死亡切入 Boss；生成器的 200/15/200 是剩余死亡预算，不能写成固定打 415 人。
双枪每门 150ms，Boss 攻击循环 120 帧、第 19 帧投掷，121–208 帧死亡后进入尾段。
尾段含两名撞车党、五名撞车盾兵、两个路障，最终碰撞触发 S5。所有数值仅是原作参考，
不代表当前 CF7 难度已经标定。玩家/车辆伤害归属仍由实际角色适配器承接，不凭空增加独立车辆生命条。

## 离线复现与检查

普通 Python 可执行事实/计划/规则同步与静态校验。原生矢量生成使用现有 CF6 Python 环境中的
Pillow、NumPy、fontTools、Matplotlib 等依赖，不安装新包。PowerShell 先运行 `chcp.com 65001`。

```powershell
python -X utf8 -B tools/cf6-scene-completion/build_plan.py --check
python -X utf8 -B tools/cf6-scene-completion/install_rules.py --check
python -X utf8 -B tools/cf6-scene-completion/verify.py --compiled
node tools/cf6-scene-completion/test-rules-reference.js
# 用现有 CF6 Python 解释器；这两项只重建/核验源，不调用 CS6。
python -X utf8 -B tools/cf6-scene-completion/build_traversal_art.py --check
python -X utf8 -B tools/cf6-scene-completion/prepare_vehicle_art.py --check
python -X utf8 -B tools/cf6-scene-completion/build_interactive_art.py --assemble --check
python -X utf8 -B tools/cf6-scene-completion/build_transport_art.py --assemble --check
```

真实交互资产用 `scripts/run-cf6-interactive-assets-tests.ps1`；业务、实际伤害与枪口碰撞用
`tools/cf6-scene-completion/run-interactive-tests.ps1`，A17真实控制器边界并入 `scripts/run-cf6-prototype-tests.ps1`。
枪口碰撞夹具验证既有BQP主循环查询和结算；完整游戏中的发射、飞行、爆炸与关卡体验仍由候选现场验证。
`tools/cf6-field-combat/run-tests.ps1` 另以实际角色RSL、WaveSpawner、初始化器、子弹队列和元老碎片链验证异步交接；
`scripts/run-cf6-transport-tests.ps1` 使用真实车辆SWF与事件轮，生成接收器仅为容量受控夹具，不能写成实际敌人全初始化通过。
电梯黑背景调查使用 `scripts/run-cf6-elevator-composite-tests.ps1` 的真实烘焙与双片井壁复合；
地板修复使用 `scripts/run-cf6-native-surface-tests.ps1` 的旧/新SWF像素对照，各自与完整游戏画面分开判定。
交互宿主生成在 `scripts/tmp-cf6-interactive-host`，沿标准 TestLoader 的目录布局解析生产 `../macros`；
发布配置明确将测试 SWF 输出到仓库根，以保留真实资源 URL。不要将宿主移到根目录后仅改 classpath：
真实 CS6 已复现宏缺失，绝对 classpath 也不能修复该布局。模板替换必须唯一命中，已有不同字节的宿主拒绝覆盖。

去掉生成器的 `--check` 才写本目录持有的派生文件；已存在产物与旧 manifest 不符会拒绝覆盖。
首次事实捕获使用 `extract_source.py --swf <原件.swf> --scripts <已有FFDec目录>`，
可追加 `--check` 对原件重新复核；原件完整 SHA-256 固定在提取器中。消费者不依赖原机 tmp 路径。

原生导入配方包含本轮工作树的绝对路径，换工作树后必须从同一输入重新生成；不能直接运行旧配方。
门时间轴内部库采用 `CF6Src/<SHA256前24位>` 短名，manifest保留完整SHA，截断碰撞直接拒绝。
文件名、库内部名、Include及实例引用由同一生成名称驱动；旧长名只在原manifest所有权和字节校验成立时精确退出。
`build_traversal_art.py --check` 同时拒绝旧命名空间残留，安全回归见 `test_traversal_art.py`。
路径验收同时使用仓库现有[路径预算门](../path-budget/README.md)的CI根模型和实际检出根；不增加例外或放宽政策。
九份门XFL已是源工程；本目录旧四类车辆XML片段保留为来源材料，完整A07已在车辆工具链中完成真实CS6纹理导入、工程装配与资源发布。禁止伪造`bin`缓存或手写SWF，旧片段不作为另一个运行编辑源。

## 真实验证与后续施工

1. 核对共享 CS6 的明确交接与精确工程路由，沿既有 scratch/mutex 协议串行运行；marker 不代签编译或行为。
2. 运行 `run-native-tests.ps1`、`scripts/run-cf6-prototype-tests.ps1`，以及独立门资产、原生出生/遮罩、真实装备外观 runner。
   每份回执绑定当轮输入，失败区段不得用上一轮成功替换。
3. 合并回固定主目录后重新编译合并源码的 asLoader，再从[开发候选入口](../../automation/README.md#3-日常启动)
   核对实际路径、identity 与 closure。隔离工作树产物不能覆盖已验收效果/音频的 asLoader。
4. A10/A13 补平台/门锚点与登离梯路径，保持真实击杀清关。完成 A09→A10→A11、A12→A13→A14
   两条正常链和中断链；规则 suite 不能代签这些实际场景。
5. A07现役装配含滚动层、玩家车轮/双枪/死亡、装甲车209帧及专用碰撞敌人，接入既有音频/伤害权威；车辆工具链负责真实资源及行为验证。
   `Cf6VehicleRules` 的 hit/death/trigger 接口只接受实际消费者确认的事件；它不应被 UI 任意调用。
6. 章节已接为S4→A07→S5→A08，40,000唯一配额移回A07、A08不再重复；后续故事索引随之更新。旧局次兼容和实际入账仍按生产合同及对应专项验收，不从源码配额推断存档已写入。
7. 独立 CS6 编译与行为、隔离候选全流程、视觉/驾驶手感各自留证。当前未获提交、推送或正式 runtime 发布授权。

独立源编译、规则行为、真实外观、候选场景与完整游玩是分别成立的结论。
完整车辆动画/玩法、逐图观感及完整章节验收不得由本目录的局部通过替代。
