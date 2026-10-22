# 70002 新人救援：关卡与原生美术施工入口

原施工批次在 `main` 完成；“不创建工作树、不提交、不推送、不部署 Host runtime”是该批次当时的授权边界。后续关卡、美术及验证说明已由提交 `b702dc0d1c` 进入主线，不再属于未提交草稿。

当前跟踪：[70001 流程验收 #50](https://github.com/FlashNightModReborn/CrazyFlashNight/issues/50)、[70002 剩余验收 #51](https://github.com/FlashNightModReborn/CrazyFlashNight/issues/51)。八段关卡与原生专项证据已落地；完整标准入口、实战平衡、退出重进与存档验收仍按下文范围执行，不把专项通过改写成整关验收。

## 当前范围

`data/stages/副本任务/新人救援.xml` 已替换原复制测试图，顺序为：防线出发 → 原郊区出口 → 卫生所救援 → 吉普调查/引爆/坚守 → 卫生所撤离后 → 郊区返程 → 防线接收 → 盗贼突袭。

- 前治安官直接使用现成兵种 458 独立两阶段 Boss，实例覆盖友军阵营；不使用换装人形兵替代，不修改全局 Boss 数值。
- 战犬暂用兵种 13 僵尸狗，只改本关显示名。新犬美术按找回的旧稿在云端并行转绘，不迁移全局 ID 13。
- 不放战场伤员背景人物是用户确认的设计选择。卫生所用联络对白表现室内幸存者，防线用空担架、医疗及卸货物资表现接收。
- 吉普三次玩家/友军实际命中后启动 45 个有效帧的引信；普通区域子弹入口提交一次 1800 威力、Z=392、Z 范围 160 的爆炸。爆炸原生元件由 55% 放大为 125%，直径约为此前 2.27 倍。车体在第 8 帧火球遮挡下切换焦黑残骸，掩体和地面碰撞同步变化；同一个特效实例继续播放至第 78 帧，再发布一次 `UnitDeath(战斗吉普)`。控制器使用同一有效帧时钟驱动特效与车体，暂停和对白同时冻结引信及演出。
- 调查前无敌；调查对白后生成带既有任务/一次性领取门控的 Type56R、一份突击步枪通用弹药和固定三枚手雷箱。成功入包与存档标记沿用既有拾取合同，控制器不直接写存档。
- 坚守使用原生 75 秒波次；撤离段 NoCount 配置在出生点，边界强制结束波次。最终战先完成无人机/犬首波，再给 10 秒整备和前治安官增援，最后处理盗贼主力。
- 引尸段参考第三集结点的多路基础僵尸持续补兵：六个出生点各限 8 只，合计同时在场容量 48。投放储备由 80 提至 745，其中 720 为 1/2/3/4/6/8 的持续基础流，间隔 450–550ms，少量高等级胖僵尸、军人及柜员僵尸延迟穿插。储备不代表 75 秒内保证全部出现或必须全部击杀；出生点满员时仍由原生生成器限流。
- 坚守结束和重返卫生所的对白明确说明清扫尾随追兵、边打边向右撤，不再说人走了就可以毫无阻碍地离开；返程仍使用到达边界即可脱离的规则。
- 首架观察机在初始化前传入真正的第三阵营 `null`；最终战无人机参与敌人清场，教学机实例固定掉落一个八门金锁镇暴弹。物资箱提供 SPAS12 一把和 12 号霰弹弹药四份。
- 观察机先从兵种表解析实际 linkage `敌人-盗贼小飞机`，不能把逻辑 ID `兵种456` 直接传给 attachMovie；创建失败走资源失败事件。
- 移除全部预置地面路线箭头和常驻悬浮说明。卫生所清场后、吉普调查前，先通过人物对白按世界内视角交代门口/掩体电台方位，再由 `<Message>` 横幅提示互动键；人物对白内不出现打破第四面墙的按键字样。操作消费后立即移除锚点，完成条件后才由原生 Clear 显示出口箭头。
- 地理方向与刷怪拓扑按实景严格对齐：前三段向左出发（玩家由右侧 `x=1640..1670` 入场，左门出），所有 `SpawnPoint` 均设在西侧来路与街心（`x <= 880`），去程路口无人机下方与卫生所货车/正门周边辅以预置驻守尸群，不在玩家背后的东侧来路刷怪；吉普段从右侧（`x=1660`）进入并原路从右门返回，六路 745 储备尸潮全部从吉普以西的深街（`x=75..560`）向右侧掩体涌来；四段返程（4/5/6）从左侧（`x=100`）进入并持续向右撤回防线，前方街心预置散落拦路僵尸，左侧尾随追兵出生点设置 `1400–2600ms` 延迟，避免开场 0 帧直接刷在玩家脚下；最终突袭段（Room 7）玩家与前治安官预备队、霰弹补给箱同处右侧防线沙袋内侧（`PlayerX=1220, PlayerY=530`），盗贼战犬、望风鸢与枪手全部从西侧破口与中路掩体（`x=85..520`）向东突入。
- 落地四份双页可收集情报（同时维护 `data/items/收集品_情报.xml`、`data/dictionaries/information_dictionary.xml`、`data/intelligence/*.txt` 与 `data/intelligence_h5/*.json`）：卫生所街口拾取《车队外勤散页》（学徒清点单 + 摩托老兵老陈炭笔绝笔）与《卫生所交接草单》（门内三组编组单 + 电台抄录与灰漆无人机目击批注）；吉普掩体旁拾取《吉普断后纪要》（吉普车长老周记录 `FC-09`/`M-14` 快拆件被盗与底舱引爆嘱托）；最终战第二波突袭无人机 `rescue_drone_assault` 固定掉落《盗贼踩点记号单》（黑市三组拆件账单、突袭口令与西南自治区旧式安保标准件“八门金锁”镇暴机芯销赃警告，严格区分前治安官所属军警宪政派残部与继承自治区工业遗产的铁枪会）。
- 盗贼主体使用兵种 44/45/48/49 的专用男性怪物元件（左轮、跳蚤、铁拳、杀手），移除兵种 27/28 换装人形。所有敌方波次显式 `IsHostile=true`，458 增援为 false，只有去程观察机实例为 null；不修改共享兵种默认阵营。
- 远程前治安官对白使用 `前治安官（无线电）`；现身接取/交付对白保留原立绘。无线电版由[共享后处理管线](../dialogue-portrait-source-review/README.md#程序化无线电派生)从原稿和配置生成，参考 boy/Blue 的人物轮廓光、冷色和扫描线，不添加矩形屏幕底板。
- 公社新人、防线哨兵和老兵通话记录的固定外观由 `source/dialogue-actors.json` 定义。新人为黑蓬头/浅灰背心，哨兵为平头/护肩夹克，老兵为络腮胡/绿色马甲；衣装使用现有 1–3 级物品。`stage.py` 将性别、脸型、发型及衣装写入每条对白，由 `StageInfo.parseSingleDialogue` 交给现有 `NativeDialogueAppearance` 冻结为自身肖像。它们是对白外观数据，不生成战斗人形单位，也不读取玩家装备填补空槽。
- 难度目标为明显高于同期主线、低于废城环线：普通部队以 22–24 级为主，推荐整备等级 20–25。路口与卫生所各两波，通过等级、数量和持续夹击提高压力。僵尸仅用主线第 13 步完成时已出现的 1–6、8、293；移除狂暴 7、狂躁 39、兽化 9/10、防暴 400、特战 401，避免提前展示后续怪物。75 秒坚守和尸潮密度保留，实际难度仍需实战校准。
- 任务交付奖励增加下挂镇暴装置，完成对白交代组件鉴定和铁枪会库存样品；复盘沿用既有不重复任务奖励的入口。

数值为本轮施工初值，尚需真实战斗和人类体验校准。无人机原生攻击直接复用兵种 456，接触、压制反制与友军 Boss 阶段行为须单独实战验收。

## 唯一编辑源与派生物

| 内容 | 权威 |
|---|---|
| 八段波次、对白、出生点、过图事件 | `stage.py`，生成正式关卡 XML |
| 公社新人、哨兵、记录中老兵的固定肖像外观 | `source/dialogue-actors.json`，随关卡 XML 派生；未登记的配角拒绝生成 |
| A/B/D 地面障碍候选 | `source/layouts.json`；已接入环境 Collision，游戏内路线/碰撞验收待完成 |
| 卫生所两状态 | `flashswf/backgrounds/70002/clinic/clinic.xfl` |
| 防线出发/接收两状态 | `flashswf/backgrounds/70002/staging/staging.xfl` |
| 吉普四状态与右侧战位 | `flashswf/backgrounds/70002/ambush/ambush.xfl` |
| 郊区返程 | `flashswf/backgrounds/70002/return/return.xfl` |
| 盗贼突袭 | `flashswf/backgrounds/70002/raid/raid.xfl` |
| 运行时状态、调查、引信、生命周期 | `NewcomerRescueController.as` |
| 无线电派生 | 原 `flashswf/portraits/前治安官.fla` + `flashswf/portraits/postprocess.json`；同名无线电 XFL 为生成物 |
| 本轮完整性及体积审计 | `publish-manifest.json` |

原始四个 ZIP 由 `archive-lock.json` 锁定；Downloads 原包保持原样。五份母版合计约 20.7 MB、512 个符号、43 份完整位图缓存。A/B 同源状态合并成场景，避免两份平行可编辑库。

原包缺失的 25 份缓存：24 份按原始 PNG/JPEG 的 SHA-256 匹配并复用 A/B 已有原生缓存，剩余 bitmap45.png 由真实 CS6 导入并保存 FLA 后取出缓存。没有用 PNG 改后缀或合成 `.dat`。`source/bitmap-cache-provenance.json` 记录原图、缓存哈希和 native twip bounds。背景水印使用的缺失 Arial Baltic 已改成本机 Arial，仅涉及 `CRAZYFLASHER.COM` 拉丁字样。

实机反馈暴露了源包的矢量装配错误：同一层的多个 DOMShape 各自使用从 1 开始的填充/描边编号，CS6 合并绘图时让后一个调色板覆盖前面的图形。真实 CS6 色块小样已复现该现象，并确认单独 DOMGroup 可隔离调色板。`repair_vectors.py` 在五份母版中修正 79 个文件、10719 个图形，保留坐标、路径、颜色和绘制顺序；`--check` 与主校验器拒绝此类回流。旧的非空/状态差异测试无法发现该问题，新增回归直接在真实 Flash BitmapData 中核对两状态的车身、摩托与门口加固层。

`build.py` 只生成 `tmp/newcomer-rescue/publish/` 下九个发布工程。七个背景进入 `flashswf/backgrounds/`，吉普和右侧战位分别进入 `flashswf/arts/70002_jeep.swf`、`70002_station.swf`，分别按地面深度 392/500 排序。母版四场景被装配成四个停止帧；运行时把状态容器及 78 帧爆炸转换为 MovieClip，去掉绘制遗枪，使用真实拾取物，清除不需要的全局导出 linkage。母版保留完整可编辑美术。

吉普与倒塌掩体的地面碰撞由当前场景状态持有；射击目标的身体区域单独初始化，避免把整辆车的视觉轮廓追加成永不移除的静态挡弹多边形。正常过图/重进时只清理本轮身份和实例。

## 生成与发布

仓库根目录执行：

```powershell
chcp.com 65001
python tools/newcomer-rescue-assets/stage.py
python tools/newcomer-rescue-assets/stage.py --check
python tools/newcomer-rescue-assets/repair_vectors.py --check
python tools/newcomer-rescue-assets/build.py
python tools/newcomer-rescue-assets/build.py --check
python tools/newcomer-rescue-assets/validate.py --require-published
node tools/derive-arena-meta-teams.js
node tools/derive-arena-meta-teams.js --check
node tools/derive-arena-factions.js --check
```

新副本首次导入才运行 `build.py --ingest C:/Users/iuo/Downloads`。已有母版时该命令拒绝覆盖。补缓存先运行 `repair_caches.py`；若唯一未匹配图仍缺失，再运行 `powershell -File tools/newcomer-rescue-assets/import_bitmap.ps1`，它只让 CS6 导入图片和保存自有临时 FLA，持同一仓库编译 mutex，不执行编译，不修改其他文档。缓存完整后无需重复导入。

实际发布必须逐一使用 `tmp/newcomer-rescue/publish-targets.json` 中的 exact XFL/SWF 配对，例如：

```powershell
powershell -File scripts/compile_test.ps1 -Target tmp/newcomer-rescue/publish/70002_jeep/70002_jeep.xfl -PublishOnly -VerifySwf flashswf/arts/70002_jeep.swf -TimeoutSeconds 180 -QuitFlashAfterPublish
powershell -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 720 -QuitFlashAfterPublish
powershell -File scripts/run-newcomer-rescue-tests.ps1 -TimeoutSeconds 300
```

发布只接受真实 CS6、当轮 Compiler `0/0` 和目标 SWF 刷新。批量大工程宜在已完成发布后退出自有 CS6，避免 32 位地址空间累积。超时后先按 `scripts/FlashCS6自动化编译.md` 复核迟到结果和所有权，不能删 marker 盲重放。

无线电立绘用 `build_radio_portrait.py` 从原前治安官 FLA 派生独立 XFL，再以 exact XFL/SWF 配对真实发布。Web 只定向导出该键到 `tmp/newcomer-rescue/radio-bake`，使用 `install_radio_portrait.py` 合并；它先核对全部既有图片摘要。不要对生产目录启动全量导出。商店只刷新其未消费的对话 manifest 摘要，39 个商店立绘和运行 manifest 保持原文件。

原生 host 导入实际生产战斗世界与无人机 SWF，在第一帧放置屏幕外依赖，确保无人机的 RSL 已装载后再创建实例。仅在第二帧声明依赖、同时让 host 停在第一帧，会令 attachMovie 得不到元件。真实 CS6 小样同时验证了 root、普通子容器和外部战斗世界中的实际创建。单位战斗初始化在夹具中隔离，不把原生实例/立绘可见性升级为 AI 或真实战斗验收。

## 证据边界

- 九份美术 SWF 已获本轮真实 CS6 `0/0` 与目标刷新证据；本次修复逐目标诊断保留在 `tmp/newcomer-rescue/compiler-palette-fix/`。
- `validate.py` 检查八段顺序、单位/事件引用、主线第 13 步可用的僵尸白名单、任务奖励、计时与 NoCount、母版所有符号/位图引用、43 份缓存及 twip 尺寸、九份 SWF 结构和体积，输出哈希闭包。它只给出 `source_validated`。
- `NewcomerRescueTest` 通过真实 CS6 Test Movie 加载正式 XML、九份地图/道具 SWF 和无线电 SWF，检查场景身份、互动与通行门、返程方向、专用敌对盗贼、原生地图元件初始化、hit/引信/状态/具名死亡、原生波次计时及立绘透明/蓝色像素。拾取请求和爆炸结算请求使用捕获夹具，不触及玩家存档；其通过不能声称物理战斗、任务交付或标准入口已验收。
- 配角肖像专项从真实 XML 解析三名配角的八句对白，检查身份与空装备槽不继承玩家、同角色跨事件保持一致、快照脱离原属性对象，以及切回玩家后的外观。trace 中的 `NewcomerRescueTest Portrait:` 行提供实际解析的外观、称号和正文；收集为 JSON 数组后，可传入 `powershell -File tools/run-native-dialogue-webview2-smoke.ps1 -OutputDirectory tmp/<全新目录> -AppearanceFixtures <该JSON路径>`，验证现有 Host/WebView2 的实际绘制、人物像素差异与切换缓存。输出只属于隐藏夹具，不代表游戏现场或正式部署。
- 当前配角肖像修正后的 XML 已通过原生专项：98 通过、0 失败、10/10 实际资源加载，唯一闭合 runId 为 `b1dd8850ba5741c688b568706426c430`，Compiler `0/0`、32K 重试 0。13 项新增检查覆盖配角自身外观、空槽、快照与切回玩家；既有爆炸、通行和尸潮检查继续通过。原始 trace、诊断、实际测试 SWF、外观定义与当轮 XML 保存在 `tmp/newcomer-rescue/native-authored-portraits-final/`。生产逻辑和美术 SWF 保持原产物，只重编了专项测试 host。
- 当前外观另通过 `tmp/newcomer-rescue/webview2-authored-20261020-v1/` 的隐藏 Host/WebView2 绘制：三人均为非空且不同的 768px 肖像，原生界面按 1024/1920 两档输出；切回玩家再返回新人时命中同一缓存、像素保持一致。此输入 JSON 与本轮 CS6 trace 实际输出的三个外观对象逐项相等。低阶军绿防弹衣存在未导出的手臂分件，故哨兵使用素材闭合的护肩夹克；验证器检查实际分件及图片文件，不只检查物品名已登记。
- 未完成的标准入口完整通关、实际爆炸伤害与友伤、无人机反制、友军 Boss 阶段、真实碰撞/遮挡、退出重进、结算存档及真人视觉验收保持为独立项。新犬美术仍可并行。
