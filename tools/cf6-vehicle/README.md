# CF6 A07 公路车辆段

此目录维护 A07 的原作证据、原生可编辑资源、固定车辆战斗适配和隔离验证。原稿 `crazyflasher6-cn.swf` 只读，SHA-256 固定为 `b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01`。本工具不写 SWF、不调用 Flash，也不提交、发布或修改真实存档。

## 当前权威与消费者

| 内容 | 当前入口 |
|---|---|
| 原帧、placement、矩阵、颜色变换、mask、标签 | `extract_source.py` → `source/original-nodes.json` |
| 原动作证据 | `source/actions.json` 及其内容寻址捕获；只作数据读取，绝不执行 |
| R2 天空／河岸、R5 双枪车身／独立前后轮 | `prepare_redraw.py` → `redraw-manifest.json` |
| 完整嵌套原生时间轴、无旧行为脚本 | `prepare_art.py` → `art-manifest.json` |
| 原声无损提取／已有 CF6 原声复用 | `prepare_audio.py` → `audio-manifest.json` |
| 源碰撞形状、初始／尾部放置、声音名 | `prepare_runtime.py` → `Cf6VehicleData.as` |
| AS2 生产源码 | 此目录四个 production `.as.txt`；`Cf6VehicleRules` 的唯一编辑源仍在 `tools/cf6-scene-completion` |
| 六个生产类的字节身份 | `runtime-manifest.json` |
| 章节片段／精确环境墙／stage 固定天空 | `chapter_fragment.py`；根章节生成器拥有最终合并、剧情与奖励 |
| things-new 共享库装配 | 根协调者拥有 `mount-shared-library.py`，本资源生成器不修改该工程 |

`Cf6VehicleService.begin(room,spec)` 返回会话或拒绝；`tick(session)` 返回 `loading / playing / dead / complete / failed / cancelled`；`dispose(session)` 只释放自己持有的对象和回调；`snapshot(session)` 只读。服务不调用切章、清场、奖励、存档或扣币 API。

普通主角死亡是 `dead`，不是 StageManager 的终局失败。车辆、敌人、投射物、Boss HP、计数、预算和 RNG 暂停保存；释放加载暂停及人物输入回调，只保留独立死亡展示 token。现役复活恢复同一个 hero 后重新取得当时的新回调，恢复同一战斗会话和 Boss HUD。不同 hero、世界、出生 mask 或控制目标不得被接管。装载／协议故障才返回 `failed`。实际关卡失败／返回由既有 `StageRunSession` 决定。

## 原作行为对照

| 原作证据 | 当前消费者及边界 |
|---|---|
| 1816 frame1 三个 1585，预算 200／15／200、各并发 1；1585 frame10 生产、24→2 | `Service.generators` 保留三路与 23 帧周期。预算不是 415 个必须击杀的敌人。 |
| 612 frame70→599 frame1，以及 frame77 的 611 load | 撞倒与射杀各产生一次原路敌终结计数；重复命中、障碍与逃逸不增加 30 计数。尸体离场不重复释放同一并发槽。 |
| 612 frame1/50/70/77 的 depth36 仍存在；599 位移、611 a2 位移 | 普通滚动 -20 持续；撞倒按撞击侧叠加 ±10，射杀 a2 叠加 ±5 并保持源左右翻转；三种死亡分支均可进入。 |
| 629 frame50 的 574 load | 盾受击仍选两个原分支；撞倒使用 628。初始／尾部 raider HP100、盾 HP300，与生产 raider HP10 区分。 |
| 1805 初始 stop 在 frame1、frame59 切阶段 | 生产适配从已存在的 frame1 开始，后续 58 次推进到 59；夹具另建实际 Flash 参考时间轴核对，不用纯计数模型代证。 |
| 1803 frame8 两个 359 枪口与全局 `汽车_子弹区域shoot` | 两枪各 150ms、威力20、速度20、±random(5) 度；保留原枪口与356显示／碰撞偏移，原355子轴14帧寿命和相对车辆800距离门。 |
| 356 area、源世界墙、移动 actor area | 源矩形上的相对运动扫掠判定；不读取玩家枪械数值，不把简单宽包围盒交叠当作斜线命中。 |
| 1813 frame1/19/120、HP5000 | Boss 是直属 world 的实际 MovieClip，固定 HP5000 是唯一 Boss 生命权威；追车、纵向跟随、推开车身、120帧循环与19帧投雷。新生就在 frame1。 |
| 1813 frame121..208、原位移 -10/+5 | 受控原死亡时间轴完成后进入尾段，不靠计时器跳过实际 Boss HP 判定。 |
| 361 frame31 的 360 与 `主角hp -= 30` | 源手雷范围只尝试一次命中；原30/200比例映射到现役 hero 最大HP，经过实际 BQP/DamageManager，保留现役无敌／复活权威。没有第二套车辆耐久。 |
| 1816 frame3 九个放置与移动1795 | 原2路敌／5盾／2障碍全部放置；仅实际尾部触发器碰撞产生 stable complete。根 typed writer 独占下一章导航。 |
| 115／391 的标签、终结帧与动态声音 | 火花、爆炸使用原矢量显示，独立受控时间轴与有界回收；不移植原脚本对 `world._y` 的直接累加，避免破坏相机所有权。 |

两项明确的 CF7 适配：世界边界使用原墙和车辆 footprint 钳制，代替旧脚本撞墙后的往返 ±20 推动；原路敌的直接 `金钱 += 100` 不执行。章节金钱只由根侧标准 Pickup／奖励合同交付。原 `_root.gotoAndStop("s5")`、旧失败提示和旧血条同样不移植，分别由根章节提交、现役 life／outcome 和 `FocusTargetHudService` 承担。

所有源动画帧只执行新生成的 `stop` 与标量元数据。服务统一推进，外部暂停、死亡和未知命中结果都不会悄悄继续运动、射击或重放。枪口实际视觉连贯、遮罩外观、完整玩家初始化、标准入口、相机手感和扬声器输出仍须各自的真实证据，不能由文件存在或像素非空升级。

## 资源与声音

资源 XFL 分别为 `flashswf/arts/new/CF6Vehicle/CF6Vehicle.xfl`、`flashswf/backgrounds/cf6/CF6_A07_BG/CF6_A07_BG.xfl`、`CF6_A07_sky/CF6_A07_sky.xfl`。CS6 对未压缩 XFL 的发布相对路径以工程目录父级为基准，配置使用 `CF6Vehicle.swf` 等文件名，不能添加 `../`。错误位置的旧发布只作失败证据，不搬动冒充消费者交付。

世界背景透明，运动路面由原1791轴绘制。天空属于独立 root-stage 层：`x=0,y=-110,width=800,height=253`，包含原1754矩阵与R2已审核延伸；不再乘地图 `1024/600`。相机焦点与世界变换由根 Map／HorizontalScroller 管理，车辆服务不写它们。

真实纹理 seed 位于 `texture-seed/DOMDocument.xml`，CS6 实际标记名为 `texture-seed.xfl`。最初导入请求文件名与实际 CS6 目录命名不同的失败回执已由根保留并核对；不得删除或盲重做 seed。所有 `bin` 都来自真实 CS6 导入。

车辆工具、独立资源和生成的`Cf6Vehicle*.as`沿用本章的Git原字节合同，避免跨机器检出时换行转换破坏manifest。纹理seed的Adobe XMP元数据含原生定长空白填充，仅该`META-INF/metadata.xml`豁免行尾空格检查；不修改原件来满足文本排版检查，其余源文件继续检查。

新声音是两个原 MP3 载荷和四份原 PCM 加 WAV 容器，没有合成、重采样或外部服务。三份原 PCM 的声明采样数多于载荷2–3帧，manifest同时保留声明值与实际值，不补零。11份已有 CF6 声音逐字节复用。Host 在启动时枚举 `sounds/export`，完整文件名是声音 ID；没有附加生成索引，完整重启才重新预载。所有调用经 `_root.播放音效`；车辆 RSL 不嵌入音轨。

## 重建与验证

以下准备命令只操作本 lane 的治理输入／输出。Flash GUI 导入、编译、测试运行和 things-new 装配由根协调者串行执行，遵守共享编译锁及 scratch 恢复合同。

```powershell
chcp.com 65001
python -X utf8 tools/cf6-vehicle/extract_source.py --check
python -X utf8 tools/cf6-vehicle/prepare_redraw.py --check
python -X utf8 tools/cf6-vehicle/prepare_audio.py --check
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-vehicle/prepare_art.py --assemble --check
python -X utf8 tools/cf6-vehicle/prepare_runtime.py --check
python -X utf8 tools/cf6-vehicle/prepare_tests.py --check
# 三个精确资源及 things-new 已新鲜发布后，再绑定真实SWF身份：
python -X utf8 tools/cf6-vehicle/prepare_tests.py --bind-native
tools/cf6-vehicle/run-tests.ps1
```

`--check` 不改输出；去掉它进行源重建。首次纹理准备先运行 `prepare_art.py` 并由根执行其 `import-textures.jsfl`，取得真实 seed 后才可 `--assemble`。重新提取原图形用 `extract_source.py --export`；可读动作提取使用 FFDec 的只读导出配置，不生成反混淆 SWF。

车辆库根帧必须保留十个公开符号的透明实例和 `stop()`。真实 CS6 隔离试验发现，仅有 AS 导出、根帧为空时，公开帧数和导出名仍然正确，但子符号会成为空占位；增加实际根引用后才生成完整图形依赖。不要将这十个透明实例作为“无用对象”删除。`--bind-native` 通过 `native_graph.py` 检查实际 shape/bitmap、十个公开帧数及各自可达 shape，拒绝空壳；此结构门不代替真实像素和生产消费者门。

原生车辆夹具实际加载发布 RSL、绘制原生像素、消费输入和动画帧，并调用实际 BQP／DamageManager、StageRunSession 和 RespawnEventComponent。hero 是带真实出生 mask 身份的 MovieClip 夹具，不能冒称已经覆盖完整玩家初始化。声音观察器证明调用，不证明输出端听音。生产 things-new 的实际导入链由根侧独立 consumer 夹具核验。通过数量、源与 SWF 哈希、失败和修复身份以本轮运行回执为准。

车辆输入夹具替换普通 `readInput()` 方法，给真实服务提供受控方向和开火意图；生产默认仍读取 `_root` 四向键与 A 键的 `Key.isDown`。准备工具核对默认映射源码，原生 trace 标记 `controlled_intent` 与 `source_fixture_only`。AVM1 原生 `Key.isDown` 不可用赋值模拟，故此夹具不声称物理键输入验收。坐标断言按 MovieClip 的一个世界 twip（1/20 像素）量化界限比较；150 秒墙钟与 2400 帧上限均只触发失败收尾，不产生通过。

2026-10-24已取得三份资源的新鲜Compiler 0/0、生产things-new导入链31项和车辆原生行为99项通过；后者含真实伤害、同人死亡复活、三种死亡分支与未知命中不重放。动画变体应用与推进分在相邻tick，避免读取旧帧元数据；测试人物使用现役空壳护盾初始化，未绕过生产伤害计算。失败原件保留在本轮诊断目录，当前通过版为`vehicle/native-r4`，共享消费者为`vehicle/shared-native-r1`。三个运行SWF合计5,951,032字节，六个新增声音70,400字节，均有源清单与摘要；标准入口、物理键及驾驶听感继续单列。
