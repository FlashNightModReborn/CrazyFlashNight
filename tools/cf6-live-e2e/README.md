# CF6 两条路线的实机入口与隔离验收

默认 `--route historical` 的目标槽固定为 `cf7_agent_cf6_sting_20261021`；`--route type61` 固定使用独立的 `cf7_agent_cf6_type61_20261026`。路线枚举及目标槽只读 [route-config.js](route-config.js)。默认建议来源为已存在的 `cf7_agent_scene_ready_1014`；只允许其他明确的 `cf7_agent_*` 来源，不接收真实玩家槽、任意目标槽或 fresh 初始化。来源 JSON 原始字节复制，来源 JSON 与对应 SOL 前后摘要必须一致。

61路线在以下预检和运行命令中加 `--route type61`。工具通过真实 WebView 的路线下拉框及 CDP 鼠标/键盘事件选择61计划，要求可见命中与可信 `change` 事件，再核对虚拟游玩目标 `cf6-sting.type61`、原档凭据、书中档和返回战绩的同一路线。不会直接改 DOM 值或调用业务命令。选路身份进入资源闭包；61配置、生成器、配方及新增运行消费者同样绑定。

Host `agent_control openBookshelf` 只接收 exact slot/attempt，通过固定 `openBookshelfForAgent` 到 AS2 生产 `BookshelfPanelService.openPanel()`。它不接收书号、token、存档正文或业务 commit。AS2 入口补丁保留于 `bookshelf-opener.as.patch`；本轮已应用，不能重复应用。改 AS2 后必须由主控真实编译，再钉住新的 asLoader 摘要。

先在仓库根运行离线安全夹具：

```powershell
node tools/cf6-live-e2e/self-test.js
node tools/cf6-live-e2e/source-closure-test.js
node tools/cf6-live-e2e/manual-observation-test.js
```

候选准备沿现役 `automation/dev.ps1 -BuildOnly`，用 `automation/dev.ps1 -Status` 核对当前候选；源码或配置变化后不能复用旧身份结论。以下三个摘要必须对应主控已验证的同一轮候选和 Flash 编译产物。命令中的占位符不能原样执行。

```powershell
node tools/cf6-live-e2e/preflight.js `
  --candidate-root '<候选绝对路径>' `
  --seed-slot cf7_agent_scene_ready_1014 `
  --expected-build-identity '<64位摘要>' `
  --expected-payload-closure '<64位摘要>' `
  --expected-asloader-sha256 '<本轮scripts/asLoader.swf的64位摘要>'
```

该命令不启动游戏、不复制槽、不写存档。它检查无已有运行实例、候选完整身份、编译产物、已安装历史章节、来源资格、目标原始状态，以及没有未解决的克隆锁／恢复记录。

源码闭包使用 `source-closure.v2`：除生产逻辑与生成器输入，还收录已安装章节的背景、stage/mechanism 中的 `url`、`Background`、`assetUrl` 本地 SWF 引用、`Cf6MapMechanism` 的 A21 绑定、环境与技能配置，以及 shops/items/equipment_mods/enemy_properties 的目录和全部目录成员。每个 SWF 的实际 ImportAssets 继续递归解析；路径必须归属于仓库，不能有远程 URL、歧义、大小写别名、缺失文件或畸形 SWF。资源变更与逻辑变更都改变闭包摘要；预检不以“未安装”跳过任何资源。

炮塔还绑定原始 SWF、raw-tag 清单、位图/声音来源摘要，以及真实 `CF6_A01_Turret` XFL 目录中的描述文件、库和 native cache；未完成原生导入或发布时会拒绝进入试玩。漫画绑定 Host/AS2/Web 消费者、运行 manifest、完整性 audit、生成内容、原始素材和生成脚本；逐项核对摘要/体积、清单总数及内容实际引用，漏列图片或音频不会被静默跳过。临时 FFDec 帧导出和工具自测目录不属于运行消费者，不因递归扫工具目录而进入闭包。

CS6 原生创建的 `CF6_A01_Turret/MobileSettings.xml` 可以为空，但仍按普通文件读取并记录字节数与摘要；
该例外只适用于这一明确的附属文件，必要源文件、媒体与其他空文件继续拒绝。运行期间该文件变化同样使闭包校验失败。

本轮通行与摆件还绑定 TraversalRules/Service、PropDepthService、ActorMaskPresentation、PauseManager/DepthManager、scene-assembly 和比例/提取配方；生产 Cf6 scene 类的直接引用按有界集合继续追踪，覆盖后续出生遮罩消费者而不递归扫描整个源码仓。按实际章节 SWF 选择 traversal/auxiliary/interactive 清单资产，逐项校验声明输入 SHA 与原生输出 SHA/bytes，并沿 DOM Include、bitmap href/bin 检查漏项；未消费的辅助资产及 A07/vehicle 准备内容不展开。depth-props 清单完整绑定独立源闭包，比例 baseline pin、实际背景父XML和排除成员共同核验，缺失消费者或背景仍重复绘制均拒绝。清单自引用、重复 JSON key、路径逃逸/大小写别名、伪造摘要/体积不作为可恢复缺省值。

辅助与交互资产的真实纹理母版分别只准入 `CF6_AuxiliaryTextureSeed`、`CF6_InteractiveTextureSeed`，不可跨用：清单须精确绑定 seed XFL 路径，DOMDocument 和其引用的每个 bin cache 必须入输入摘要，额外只接纳 `SymDepend.cache`；不扩大为任意 preparation 目录。交互资产限定1736/1838/1976桶与1939培养舱，名称、源角色ID、16/25帧及原作SWF摘要一并核验；真实伤害与地图元件初始化的相关权威源也纳入身份。

运输资产单独限定 `CF6_Transport1868`、29帧及第29帧派发，唯一纹理母版为 `CF6_TransportTextureSeed`，片段仅接受 `transport-art` 对应资源；原作SWF、输入、原生文档、纹理与缓存逐项绑定。它不扩大为A07驾驶资源。人体比例的七个原生站姿XML、比例政策及实际使用的Andy对白表情WebP同样进入来源闭包。

场景 Wings 只有在章节实际引用 `preparation/CF6_ScenicWings.swf` 时才展开 `scenic-wings-manifest.json`。
该清单必须匹配受治理原作 SWF 的摘要、1777源角色、15帧及唯一 XFL/SWF 地址；输入集合严格等于生成器、比例政策、
A06/A08原几何、现役Wings单位根与发布入口，加站姿原生符号的有界递归依赖。输出SHA/bytes和DOM Include闭包共同核对，
独立XFL目录不接受漏列或多余文件、跨preparation声明、新脚本/linkage/位图；仅在运行类中出现验证用URL字面量不算实际消费。
因此未消费的Wings或旧vehicle准备包不会借这一规则扩张清单，原有门、交互物件、运输车等准入仍各自限定。

A07 只由当前章节引用的三个精确URL触发车辆闭包：`flashswf/arts/new/CF6Vehicle.swf`、`CF6_A07_BG.swf` 与 `CF6_A07_sky.swf`。
`cf6-vehicle-art.v1` 绑定原作显示节点与动作摘录、受治理R2/R5重绘、纹理清单、真实`texture-seed/texture-seed.xfl`及其DOM引用的每个LIBRARY/bin文件；
纹理绝对路径只接受当前仓库根，或由本工作树Git共同目录验证出的主检出根，且必须对应同名、按摘要命名的`source/textures`文件。后者仅解释原始制作路径；实际纹理始终从当前工作树读取并校验SHA/bytes，不读取清单指定的外部路径。这两个精确根随本轮闭包记录，其他目录仍拒绝。提取器、转换器、字体、模板、章节生成器及六个固定运行类
（Service/ActorAdapter/Combat/Timeline/Data/Rules）都入身份，不能依赖裸类名恰好被正则发现。
横向滚屏 `HorizontalScroller.as` 与 Host `MapTaskCatalog.cs` 显式纳入来源身份。原作1805第2帧仅为ActionEnd(00)，其摘要为e3b0c442…b855的空反编译稿是唯一允许为空的车辆脚本；必须同时匹配该原路径，其他空脚本仍拒绝。
`runtime-manifest.json` 另封闭绑定 prepare_runtime、原作节点、四个生产模板与 canonical Rules 模板，输出必须恰好为六个运行类且摘要、字节一致。
三套原生XFL按实际消费选择，逐项核对输入/输出摘要、大小、Include与媒体闭包及精确文件集合，RSL公开符号集合与原生符号数另验。
车辆表现根另精确包含原作 356 子弹、115 火花与391爆炸（public 名分别 CF6VehicleBullet/Spark/Explosion）。
`audio-manifest.json` 绑定原作、音频提取器和既有资产目录，输出只允许6个 CF6Vehicle 文件，并精确绑定11个既有 CF6 音频；
音效cue映射封闭，MP3摘要/长度和PCM的RIFF格式、实际样本数、样本摘要另验。原始PCM声明长度偏差按实际样本记录，不能补造静音或据此声称听感验收。
旧错误位置 `flashswf/arts/CF6Vehicle.swf` 存在于磁盘不会自动入闭包，任何实际章节或导入引用该位置均拒绝；唯一车辆RSL位置为 `flashswf/arts/new/CF6Vehicle.swf`。
这条准入不会接受任意preparation或旧vehicle准备包：旧包仅明确的bitmap1806/1808原输入经重绘清单接入，其余仍不展开。
最终车资源清单尚未生成或实际SWF缺失时会拒绝；离线fixture通过不代替真实资源生成、CS6编译或驾驶验证。

装备构建的 `CharacterBuildService`、目标HUD的 `FocusTargetHudService` / `PlayerHudService` 与直接Host目标条消费者
明确列入生产源码身份；这是候选源/产物变更检测，不将源码领先状态当作现役DLL已经部署。

章内难度配置 `difficulty.source.json` 与 `difficulty_plan.py` 同时进入章节装配输入和本闭包；物资候选源、实际章节、商店与奖励消费者共同绑定。刷怪配置变化会使旧旅程身份失效，静态预算不代替实际难度验收。

教程启用 `r7-bold` 时，额外绑定所选 SVG、原始 ZIP、转换器、原生纹理缓存、生成清单与当前 XFL 的完整引用。路径仅允许教程自己的原稿、生成目录和精确纹理导入配方；遗漏实际 Include、修改源或缓存、改选边线及扩张到其他目录均拒绝。原生遮罩裁切与游戏倍率仍由实际消费者验证，清单不替代像素或通行证据。

闭包只证明本次输入身份和运行期间是否变化。源码准备、真实 CS6 编译、候选运行和完整玩法验收仍分别记录；离线夹具通过不能证明炮塔或漫画已在游戏中执行。

只验证生产书架 opener、真实 WebView 和关闭路径：

```powershell
node tools/cf6-live-e2e/run-candidate.js `
  --candidate-root '<候选绝对路径>' `
  --seed-slot cf7_agent_scene_ready_1014 `
  --expected-build-identity '<64位摘要>' `
  --expected-payload-closure '<64位摘要>' `
  --expected-asloader-sha256 '<64位摘要>' `
  --execute-isolated-candidate --observe-only
```

验证入书、真实终态、生产自动返回和新进程读回：

```powershell
node tools/cf6-live-e2e/run-candidate.js `
  --candidate-root '<候选绝对路径>' `
  --seed-slot cf7_agent_scene_ready_1014 `
  --expected-build-identity '<64位摘要>' `
  --expected-payload-closure '<64位摘要>' `
  --expected-asloader-sha256 '<64位摘要>' `
  --execute-isolated-candidate --allow-clone-book-writes `
  --await-return-seconds 14400
```

runner 通过受认证的现役 legacy HTTP 生命周期入口启动候选，`fresh:false`、`rememberSlot:false`，只发送固定进档／书架打开与正常退出请求。书架的选书、选第六章和进入由实际 WebView 的可见、命中测试通过的按钮加 CDP Input 完成。被动观察器记录生产 Bridge/Host 回执，并核对实际加载的 Web 脚本摘要；它不制造业务响应。

进入后工具只观察。战斗、死亡、撤退或通关由正常游戏输入触发，工具不自动杀敌、设定血量、跳图或伪造终态。当前生产书架在收到合法终态快照后自动返回，runner 观察这一次原始返回请求，不再额外点击返回。报告只证明实际到达的终态和入书／返回链，不将一次撤退写成全章通关，也不证明物理输入体验。

返回的 exact `applied` 回执与稳定存档均通过资产／零 SP 核对后，截图和观察器卸载属于可选展示证据；真人已关书架导致 CDP 断开时，报告保留错误并继续受认证的正常退出、新 PID 读回与完整保护检查，不再额外点击关闭。上述返回证明之前的异常仍保留失败与未知写锁；此边界不会重发任何入书／返回动作，也不会把旧失败报告改成通过。离线回归：`node tools/cf6-live-e2e/verified-return-observation-test.js`。

## 正常键鼠操作与只读观察

当前 Flash agent runtime 没有声明原生输入或像素观察能力；`agent_control` 没有按键按下／释放接口。CDP Input 仅用于已经绑定身份的 WebView 可见按钮，不能据此声称可驱动嵌入的 Flash 战斗。实际游戏操作交给已有 Windows Computer Use 或真人正常键鼠，不新增 SendInput、PostMessage、控制台脚本或游戏状态注入。

1. 仅对 runner 已启动且 `report.json` 中 PID、候选路径和摘要对应的窗口操作。入书前后核对固定克隆槽和本轮附属槽登记；不要另开一个启动器。
2. 输入前从当前截图确认窗口位于前台、游戏画面可见，且没有暂停、对话、商店或其他面板遮挡。键位以当前游戏设置为准，不把默认键位当作已验证事实。
3. 使用短的按下／释放配对操作；每批操作后截图确认角色、地图、血量与面板变化。长按必须由支持明确释放的现有输入工具执行，并在结束或异常分支释放全部由本批按下的键。没有这种接口时只使用工具支持的完整单次按键操作。
4. 失焦、暂停、窗口消失、身份改变或结果不确定时先释放本批按键并停止后续输入，再重新观察。不要把状态接口的 `readyForRuntimeAutomation` 当作前台、未暂停或战斗就绪证明。
5. 死亡、撤退或通关后让生产流程自行结算／返回，由 runner 观察与读回。超时或未知写结果保留证据，不再进入、不重发返回、不改存档补终态。

`manual-observation.js` 供已有 runner 会话按需调用，不自行启动、退出、读取凭据、轮询或发送输入：

```javascript
const observation = await require('./manual-observation').snapshot({runtime, admission});
writer.append({kind:'cf6_manual_observation', observation});
```

这里的 `runtime` 和 `admission` 必须来自本轮 runner 已完成的候选启动与附属槽登记，不从旧报告拼装新权限。调用在现役认证会话上读取一次 `agent_control status`，前后核对候选身份、PID、端口、加载 attempt 与槽位；输出只保留有限状态。前台、暂停、地图、血量和持键状态均明确标记 `unknown`，必须由正常画面观察补充。该辅助模块未接入 runner 自动循环，使用它不产生战斗完成或物理输入证明。

初始书中存档必须匹配所选路线的角色、等级、累计经验、初始金币／SP、装备强化和固定技能清单。史实仍为60级/+11；61为35级/+1，并逐一核对12个快捷技能槽。返回要求原克隆角色资产不变、精确局次零奖励、所选路线记录成立，并由新 PID 正常加载克隆槽读回。截图、哈希链观察记录和报告位于 `tmp/workbench-live-e2e/cf6/<run>/`。

每轮将入书前、实际入书保存屏障、书中初始角色、返回和重启读回的测试槽 JSON 原字节分别保存，并在报告绑定文件名与 SHA；不会只保留入口摘要后丢失可复查正文。克隆准备、其他既有槽的摘要基线和失败后的摘要集合另存 `save-protection-*.json`。这些证据文件只记录测试现场，不写回存档、不触发业务重放，也不把失败改为通过。

`bookrun_<24位hex>` 不由 runner 命名。仅当实际生产页面请求及配对 Host 回执、原克隆槽的 active 凭据、书中存档的 origin/seed/bookId/routeId 全部一致，且该槽的 JSON/SOL 在启动前均不存在，才登记一个本轮附属槽。所有其他既有槽必须逐字节不变。生产可能在结算后清理该附属槽，登记允许它在本轮消失；不会放宽为排除全部 `bookrun_*`。

失败不会重发入书／返回，不自动删存档、删锁、还原或重新克隆。工具只尝试正常关闭 exact 候选，保留测试槽、所有附属产物、`report.json`、克隆锁和恢复记录。下次预检会拒绝未处理的状态。

恢复前先确认原 runner 和所有游戏进程已退出，保存失败产物，并核对 `CloneSaveGuard.inspectCloneLock({root,slot})` 与恢复记录的 exact 摘要。离线恢复使用现役 `restoreAbandonedCloneFromRecovery({root,appData,slot,expectedLockSha256,expectedRecoveryRecordSha256,expectedRecoveryStatus,assertNoRuntime})`，`assertNoRuntime` 必须调用现役 `GenericOpener.assertNoLauncherBeforeMutation`。该方法只能恢复目标克隆槽到记录中的 `targetBefore` 并验证来源未变；它不处理书架未知写，也不清理附属书中槽。未知业务结果先沿原操作对账，不能靠还原克隆重新发奖；失败证据及附属槽另行保留，不用旧备份覆盖来源。
