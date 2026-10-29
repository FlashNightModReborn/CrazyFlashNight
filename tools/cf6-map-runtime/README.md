# CF6 地图装配与机关

本目录是 `cf6-sting / historical` 地图的确定性装配入口。归档美术与重建脚本归 [地图源管线](../cf6-map-source/)；本目录消费独立背景和独立部件，不消费场景预览。源码装配、真实 CS6 编译、实际消费者和通关验证分别留证，CS6 与游戏验证由主控串行执行。

2026-10-21 接入方向已按用户要求改为：**尽可能保留矢量、组与时间轴 → 原生 XFL → 运行时背景烘焙**。当前施工入口为 [native-vector](native-vector/README.md)。原稿内嵌的程序纹理保留原字节；不可直接表达的 SVG 功能逐项实现或报告局部退化，不因存在 `baked/` 或运行时最终使用位图而整层预栅格化。下面的 PNG 导入链和已有产物保留为早期候选与对照，未授予继续批量导入的意思；运行索引切向已验证矢量产物由主控统一完成。

## 当前状态（2026-10-21 回执核对）

- 20 张 canonical 背景 SWF（A01–A06、A08–A20、A22）及门/前景/电梯/天空/城市/A21 演出配套全部经真实 CS6 编译，Compiler 0/0；回执分布：A09–A17 共 13 目标 `tmp/cf6-roguelike-20261021/validation/canonical-native-batch-r1`，A18/A19/A20/A22 `canonical-pattern-batch-r1`，A02/A06 天空 `sky-canonical-r1`，更早 A01–A06/A08、门、前景、城市、A21 见 `canonical-vector-r1/r2/r3`。编译完成不等于全游戏 20 图已走通，整章路线尚未验收。
- 真实 TestLoader 612/612（`validation/prototype-viewport-r3`）；机关 suite 现为145项，另有地图显示专项30项（包含实际MovieClip、位图颜色/alpha和旧矩阵凭据拒绝），旧 79/105 数字仅为历史基线。
- 生产 asLoader Compiler 0/0（`validation/asloader-r4`）；生产 Web harness 14 场景 × 3 视口 42 次通过（`validation/web-flow-r5`）。
- 第一轮 live E2E 的快捷物品栏4失败原件保留，修复已通过908项角色/存档专项回归。第二轮隔离候选已实际进场、由用户试玩至A02并正常撤退，返回与独立进程重启读回通过，原角色资产一致、外带SP为0（`tmp/workbench-live-e2e/cf6/20261021T125243882Z-cf6/report.json`）。该轮使用适配前尺寸；本轮地图倍率修复尚未在新候选完整试玩。候选 `cf6-sting-20261021b` 隔离未部署，正式 runtime 未改。
- A14 培养舱小人独立实机对照仍存在缩小时描边变暗的视觉差异；诊断 01 编译失败原件保留、02 编译成功，canonical 未改。不能宣称全部画面已经人眼验收。

下列各节中的“缺资源”“待编译”“待主控运行”等早期描述保留为历史施工记录，与当前状态的矛盾以本节为准。

## 输入与坐标

字段说明见 [map-input.v1.json](map-input.v1.json)。实际输入为 `tools/cf6-map-source/generated/map-input.json`。原生世界坐标统一经过 `(p - nativeBounds.origin) * worldScale` 转换一次；PNG 的实际像素可以高于逻辑宽高，不能把高分辨率重复乘进坐标。

地图源真源仍是归档的 SVG、脚本、布局与来源文件。原生矢量转换器保留形状、元件、矩阵与时间轴；JSFL 仅为原稿已有的 PNG/JPEG 纹理建立 CS6 原生缓存。SWF 始终由真实 CS6 发布，没有外部工具生成或修改 SWF。背景随现役加载链烘焙，动态层独立加载并由本房间身份持有。

现役消费者为 `StageManager.initStage()`、`EnvironmentConfig.parseEnvironmentInfo()` 和 `关卡系统_lsy_add2map_加载背景.as`。环境键按 SWF 文件名查找；地图定义背景值包含 `cf6/` 相对目录。通用背景宽度大于 1300 时会被烘焙并卸载；本章矢量背景还会在子元件初始化后、且当前局与世界归属成立时主动请求烘焙。因此电梯滚动、门和演出不能放入背景 SWF。

`depth` 表示源图层内顺序，不是 CF7 绝对显示深度。电梯轴道放在 `deadbody` 的位图下方专属子层；前景与门放在 `gameworld.效果` 的专属子层，避开单位的 DepthManager 深度段。入口物件若需按角色脚底 Y 排序，必须另行添加明确的 `sortY` 支持，不能以固定前景层冒充已完成此类遮挡。

A02/A06 的固定天空与 A02 城市视差按 [sky-parallax.fragment.json](sky-parallax.fragment.json) 装配，坐标空间为 `root-stage`，不重复减地图原点。消费者只在现有 `_root.天空盒` 内创建有独立身份的子容器，并抵消父容器相机变换；不改共享后景层。A02天空源尺寸600×187、A06为800×187且原y=-20；这些是资源局部尺寸。现役显示按章节的地图倍率等比放大，并让固定天空至少覆盖当前Stage宽度。城市按地图倍率与当前世界镜头倍率同步，world平移仅加一次、横向仍半速。滤镜画质与实际窗口表现仍须实机核对。

当前 CF7 175cm 裸模站姿为 145.19 个角色局部像素，持枪姿势为 138.38px，见[既有人模标尺](../../docs/装备素材度量衡-175cm人模标尺-2026-09-05.md)。原 CF6 首帧 man1 身体部件 1013—1025（不含武器和碰撞标记）经放置矩阵后的外框高约 134.17px。原生资源与几何提取仍保留 `worldScale=1`。用户在本轮实机反馈后明确选择基础镜头1、调整地图倍率；最终章节装配按 [viewport-policy.json](../cf6-prototype/viewport-policy.json) 统一适配，角色本体保持现有尺寸。原生人模标尺只说明素材比例来源，不冒称最终房间比例已经人眼验收。

## 默认视口尺寸适配

最终装配入口 [viewport-assembly.py](../cf6-prototype/viewport-assembly.py) 消费未放大的原生输入：先恢复原作世界原点，再按默认1024×512可见区与原600×350视口计算统一128/75倍率。背景、碰撞、角色部署点、出口、掉落位置和机关坐标同步换算，角色本体与基础镜头不变。商店/金币布点在变换后沿现役角色净空生成。

相机边界采用原作load脚本明确的背景长/高，并限制在实际美术右/下缘内，不把装饰外框或行走边界当作镜头尺寸。A10/A13采用已核对的600×350升降窗口安全范围；这是本版裁剪适配，不冒称原作800×800跟随镜头。

原生背景SWF保持原字节；`Cf6MapPresentation` 在实际烘焙前施加绝对位置/倍率，并将实际矩阵绑定到烘焙凭据。动态层只缩放art，已换算的holder位置、clip和滚动距离不重复放大。

显示探针归 [build-viewport-probe.py](../cf6-prototype/build-viewport-probe.py)，只验证独立Flash显示列表，不写存档、不代替完整游戏。当前批跑存在待区分的加载/显示异常，A02另有一个角部透明采样点，不能将全21图列为画面通过。23:00熄屏后的施工以源码、装配和无界面检查为限，真实窗口与游戏复验留待亮屏。

## 原作几何与原型适配

[extract-geometry.py](extract-geometry.py) 只读取原 SWF 与已有反编译文本，硬校验交接包声明的原 SWF SHA-256；不执行 ActionScript。`generated/Axx-original-geometry.json` 绑定提取器、原文件、解码 load 文本的 SHA，保留世界边界、man1 初始放置矩阵、名为 `地图` 的碰撞子树。man1 原始时间轴位置不自动代表其脚本执行后的最终出生。

```powershell
python -X utf8 -B tools/cf6-map-runtime/extract-geometry.py --swf tmp/cf6-roguelike-20261021/kimi-content/extract/crazyflasher6-cn.swf --scripts tmp/cf6-soldier-20261016/knife-audit/deobfuscated-export/scripts --map A01 --output tools/cf6-map-runtime/generated/A01-original-geometry.json
python -X utf8 -B tools/cf6-map-runtime/derive-route-overrides.py
python -X utf8 -B tools/cf6-map-runtime/derive-route-overrides.py --check
python -X utf8 -B tools/cf6-map-runtime/audit-route-geometry.py
python -X utf8 -B tools/cf6-map-runtime/test-geometry.py
```

其他启用地图同样用其原 A 编号提取；A07、A21 不进入地图生成。`route-geometry-overrides.json` 是独立于 K3 美术源的运行几何适配输出。它将原碰撞实心区与行走孔洞分解成无孔凸多边形；不能把外轮廓和孔洞都直接当作阻挡多边形。

原曲线按最多 0.25px 控制点平坦误差离散；A11、A14、A15 的 0.05px 描边不进入填充碰撞。近似、源轮廓、原生变换与调整后坐标都保留在逐图 `geometryBasis` 中。离线检查对每图取 1000 个点验证分解前后填充一致，并以 5px 点网格检查出生到出口连通；它不证明实际角色碰撞半径或 AVM1 行走行为。

A03、A19/A20 的原始放置在原走区外，适配器显式选择最近合法点。A04/A05 使用原 sprite1729 首帧的 man1 定位脚本及其世界矩阵，证据摘要写入 `explicitOriginalArrival`。原 CF6 多图按死亡计数自动切换，当前原型改用 CF7 标准手动出口；这些适配入口/出口始终标 `prototypeDerived`，不宣称是原作门。A01 首批纵切还保留 [a01-runtime-overrides.json](a01-runtime-overrides.json) 与专用生成器，便于复核首次集成身份；全路线继续使用 route 覆盖。

## 早期位图候选构建和原生导入（保留对照）

仓库根目录，PowerShell 先 `chcp.com 65001`：

```powershell
python -X utf8 -B tools/cf6-map-runtime/build.py --input tools/cf6-map-source/generated/map-input.json --overrides tools/cf6-map-runtime/route-geometry-overrides.json
python -X utf8 -B tools/cf6-map-runtime/build.py --input tools/cf6-map-source/generated/map-input.json --overrides tools/cf6-map-runtime/route-geometry-overrides.json --check
python -X utf8 -B tools/cf6-map-runtime/test-build.py
```

`generated/CF6_*.jsfl` 每份只创建自己的新文档，导入独立 PNG，然后保存到 `flashswf/backgrounds/cf6/<名称>/<名称>.xfl`。成功或异常均在 finally 中只关闭自己创建的文档；异常另写 ERROR 回执，已存在的目标拒绝覆盖。它不发布、不启动播放器，也不保存或关闭其他文档。位图统一显式 lossless、禁用 imported JPEG data 并开启 smoothing，PNG 文件本身保持原字节。由主控在已持有的 CS6 会话执行对应导入脚本。需要重建已导入工程时先保留该工程与未保存修改，再由主控在新的隔离目标执行同配方；不要为了重跑而删除旧源或绕过编译事务。

原生导入结束后，设置准确发布路径并检查：

```powershell
python -X utf8 -B tools/cf6-map-runtime/finalize-native.py --map A01
python -X utf8 -B tools/cf6-map-runtime/finalize-native.py --map A01 --check
python -X utf8 -B tools/cf6-map-runtime/test-native-xfl.py
node tools/cf6-map-runtime/test-jsfl.js
python scripts/tools/xfl/audit.py flashswf/backgrounds/cf6/CF6_A01_BG
scripts/compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_A01_BG/CF6_A01_BG.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_A01_BG.swf'
```

CS6 对 uncompressed XFL 的发布名以工程目录的上一级解析，所以 `flashFileName` 使用裸 `<名称>.swf`；不能写 `../<名称>.swf`。`finalize-native.py` 先核验 PNG 与索引 SHA/字节数、media 引用、像素尺寸与非空 bin 缓存，再补齐发布设置与位图压缩属性；`--check` 不改源。输出记录每个缓存的 SHA，未解码缓存像素，不代替真实编译和画面验收。通用 XFL audit 仅索引 symbol 时可能把合法 DOMBitmapItem 引用报告为 broken，必须保留该输出并另用本工具验证 media 闭包，不能将原报错改称通过。JSFL 控制流测试只验证异常清理的参考模型，不代签 CS6 API。

其他地图与动态部件的精确 XFL、SWF 路径见生成的 `runtime-index.json`。该索引同时绑定每个输入 PNG 的 SHA-256 和字节数，动态目标通过 `sourcePng` 绑定对应输入。`environment.fragment.xml` 由主控合入 `data/environment/stage_environment.xml`，本工具不编辑共享环境注册表。

主控将索引的 `background`、`mechanism` 合入对应章节地图项，将 `spawn` 写入 `stage.BasicInformation.PlayerX / PlayerY`。`mechanism.layers` 的 URL 是完整仓库资源路径，已经进行坐标和尺寸转换；不得再次施加倍率。

## 独立教学关

教学入口固定为 `TUTORIAL`，使用独立 `cf6/CF6_Tutorial_BG.swf`。素材与唯一布局源见[教学室装配](../cf6-tutorial/README.md)；旧练习场占位及两只低级目标已退役，原件保留在该工具的 `archive/`。

```powershell
python -X utf8 -B tools/cf6-map-runtime/build-tutorial.py
python -X utf8 -B tools/cf6-map-runtime/build-tutorial.py --check
```

当前入口委托 `tools/cf6-tutorial/assemble.py`，产出独立 XFL、`environment.fragment.xml` 与 `tutorial-map.fragment.json`。章节装配直接消费这两个新片段，不再读取旧 `generated/tutorial-map.json`，也不把教学塞入20张主地图的 runtime-index。

教学室不安排敌人，初始枪与刀仅由角色模板发放；保留移动、切换武器、射击/换弹及补给说明，按键沿用当前设置。空波次按现役机关清关后开放右侧出口，A01 承担第一场战斗。两份补给沿正常拾取与满状态反馈，不人为扣血或强迫消费。

新资源已经真实 CS6 编译，且在隔离候选中实际进入；入口角色与源身份已核对。门口实际通行、射击、后续20图和完整返回读回分别验证，不由源码或静态连通检查代签。

## 机关职责

模板是 [Cf6MapMechanism.as.txt](Cf6MapMechanism.as.txt)，生成文件是 `scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as`。生成器先复制已有 BOM 文件，再以同一 BOM 写入模板内容。

```powershell
python -X utf8 -B tools/cf6-map-runtime/install-as2.py
python -X utf8 -B tools/cf6-map-runtime/install-as2.py --check
```

底座调用 `install()`，在加载幕退场后的章节入口调用 `beginRoom(world, identity, mapId, map.mechanism)`；`StageManager.clearStage()` 在写入通关结果前调用 `interceptClear(this, gameworld)`，返回 true 时等待。所有延迟操作持有普通对象世界身份、独立复制的局次标量身份和槽位，旧房间回调不得重新读取身份后冒充当前房间。

A08/A16 的空波可能在加载幕释放前完成。未绑定机关时，仅有效当前 CF6 史实局的真实清场调用可登记一次待交接请求，绑定 exact manager、world/普通身份对象、子关编号、槽位与局次标量；迟到的 `beginRoom` 核对后接管，仍需完成机关流程才能回调原 `clearStage()`。重复通知幂等，`teardown()` 清除未交接请求，交接后身份变化关闭出口并取消旧请求；不依据敌人数或刷怪器结束标志猜测补发。

| 地图 | 机关状态 | 完成后的责任 |
| --- | --- | --- |
| 普通出口 | 战斗 → ready | 回调原 `clearStage()` |
| 配置了门的地图 | 战斗 → 开门 24 帧 → ready | 回调原 `clearStage()` |
| A10 / A13 | 关门 24 帧 → 战斗中升降 → 到站 30 帧 → 开门 24 帧 | 回调原 `clearStage()`；升降不会以计时替代击杀 |
| A06 | 战斗 → 90 帧转场 → ready | 回调原 `clearStage()`；过渡配给只由内容配置的单一奖励源负责 |
| A20 | 战斗 → A21 显示演出 180 帧 → ready | 仍由标准出口进入 A22，不在演出中生成单位 |
| A22 | 标准终战 | 机器人仅由 A22 波次生成，标准终态完成结算 |

A10/A13 必须包含独立 `elevator-scroll` 图层、正数 `loopHeight` 和相对图层原点的 `clip:[x,y,width,height]`。滚动使用两份隔离 tile 和各自窗口遮罩，37 个位置循环；两图保留各自背景与前景布局。资源缺失、加载失败和超时明确关闭出口并释放本机制的暂停责任，让用户仍能撤退；不自动跳过或重复加载。

加载、关开门和演出持有自己的 PauseManager lease；升降战斗释放 lease。释放机制责任不撤销其他模块的暂停。普通游戏暂停停止战斗中的升降帧。机关不持有存档、补给、地图跳转或 Boss 生成权限。

## A21 显示工程

```powershell
python -X utf8 -B tools/cf6-map-runtime/build-transform.py
python -X utf8 -B tools/cf6-map-runtime/build-transform.py --check
python scripts/tools/xfl/audit.py flashswf/backgrounds/cf6/CF6_A21_Transform
scripts/compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_A21_Transform/CF6_A21_Transform.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_A21_Transform.swf'
```

A21 派生自现役 `Codex老头素材` 的 `Codex/老头/变身/角色演出` 前 93 帧，依赖清单见 `generated/a21-transform.manifest.json`。保留角色替换与分件矩阵，移除所有继承 ActionScript、声音控制和 linkage；外层只执行 `stop();actor.stop();`，由机关逐帧驱动。它是初步可玩版的角色变形演出与字幕，不宣称完整恢复原作 94–283 帧全屏演出。

A20 人形必须显式 `Parameters.老头变身=false`；A22 波次是机器人唯一生成者。不能同时启用单位自动变身和章节生成。

## 验证边界

离线测试验证输入角色、路径、禁用地图、坐标变换、缺失电梯层和确定性输出；不代签 Flash。

真实 TestLoader 入口为 `org.flashNight.arki.scene.Cf6MapMechanismTest.runAllTests()`。主控沿现役 focused runner 的 scratch 备份、mutex 和恢复协议接入；不要直接覆盖共享 `TestLoader.as`。该 suite 覆盖门/电梯帧边界、暂停、一次完成、同路径 MovieClip 换代、失败不放行及旧书籍旁路，另含空波次早清关保持身份与一次性交付用例；当前真实运行 142/142，合并原型 579/579（`tmp/cf6-roguelike-20261021/validation/prototype-combined-r6`，Compiler 0/0）。该通过数绑定该轮回执，不代签后续工作树或全路线验收。

实际消费者还要核验：背景注册与镜头、角色相对体量、碰撞与出生点、门叶遮挡、电梯窗口与升降方向、加载失败后撤退、A06 过渡配给只发一次、A20 老头不自行生成机器人、A21 无战斗副作用、A22 只出现一次机器人，以及死亡/撤退时旧演出不能延续。

## CF6转场后的地图装配遮挡

标准加载幕退场后，章节续接才启动CF6附加图层、摆件、运输车或赛车资源的异步加载。`Cf6MapPresentation`在有效CF6的SceneReady、标准幕仍在时先建立一个不透明的根级遮罩；`Cf6MapMechanism`在本房间静态背景、动态层与关联资源完成后跨两个watch帧撤下。遮罩不新增导航、奖励写、自动重试或固定等候秒数；只补足两段呈现之间的空档。

遮罩绑定普通世界身份和独立MovieClip所有权，出生事件监听到房间机制的交接保留同一遮罩。正常就绪、失败、死亡和场景拆除均按原房间身份清理，旧房间迟到清理不能移除新房间遮罩。视口改变时按Stage重绘；外部对话、菜单和既有恢复入口仍沿原流程。它隐藏加载过程，不宣称减少实际I/O耗时。生成模板、真实AVM1与像素覆盖门沿本页原入口；完整地图切换的观感需实机复验。
