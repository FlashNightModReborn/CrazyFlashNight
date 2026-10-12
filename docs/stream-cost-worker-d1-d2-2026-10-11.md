# 流式成本与 Worker D1/D2 隔离候选

**文档角色**：本轮协议、裁决、候选验证与发布入口。隔离施工起点为 `38f24d4bc9d6d7a63941425639409cd4a3643df2`；2026-10-12 用户试玩后明确授权「可行，那就走完整的发布列车」。

本轮采用首轮五项、Q1-R、Worker D1/D2。PC2、Q64、L2、D3、延迟 native draw 不在范围内。调研原始包绑定 `377408b59f94718138168b39678f4f13d33f3520`；六个离线模型已在 Windows 重放，其证明层仍为协议/成本模型。

## 当前发布列车（2026-10-12）

已将封存源码树 `890508f38af78e1d439176e4a261b23f69353532` 的 80 个施工文件整合到最新 main `d305afb9d159002311eca66f635b57824e087a9a`；逐路径核对无交叉修改，保留全部上游变更和真实存档。用户在普通 full 模式试玩隔离候选07后授权正式发布；日志确认该次 Ready 生命周期及 Flash code 0 退出，不补签逐项视听、弱机或完整业务验收。

本列车将为合并后的最终源码使用新标签 `runtime-build-v2/20261012-stream-cost-worker-v1` 和 immutable request，重新执行注册本地 X509／GitHub hosted OIDC 独立构建、当前 strict policy、唯一 writer 原子 promotion、部署提交及远端 Audit、无候选选择器的正式入口复验。目前状态为源码整合／验证中，尚未正式推广。施工包的旧 request、旧策略票与人工试玩身份不会替代新列车证明。

合并后的真实 CS6 首次 publish 发现上游 `通信_aka_Agent联动.as` 新函数使用 `lt`、`gt` 两个 AS2 保留字作变量，Compiler 报7错／0警告。按原业务语义仅重命名为 `tagStart`／`tagEnd`，保留 BOM 并重编；失败日志及无效1253字节 SWF 保留在本机发布目录，未部署。新 RAG 五键投影保持上游合同。

修正后的真实 CS6 publish 于 `2026-10-12T03:57:08Z` 取得 Compiler 0错／0警告，SWF 6,057,009字节、SHA-256 `299971B75B226B53BAB3514DBA9BDC05F191FCCEAC7AE23B08F75F0F58BD278F`。合并后的 canonical Host 全量7,089通过／27专项跳过，Node85和Worker projection48通过；22项派生资源与文档治理通过。发布前保护快照137个既有记录差异为0；原施工索引未知写锁和原索引字节均保留。

发布证据保存在 primary 的 `tmp/runtime-release/stream-cost-worker-20261012/`；施工原始证据和试玩存档继续保存在原 worktree。下节性能与测试数字属于已交付候选07，合并后的正式 runtime 单独记录实际身份和验证范围。

## 最终隔离候选交付（发布前历史）

本节更新于 2026-10-12T02:42:52.882Z；后面的具名时间段保留为历史证据。授权的首轮五项、Q1-R、Worker D1/D2 已完成实现、规定回退、回归、四组实际候选联调和单／双实例各六轮交替对照。交付只覆盖本机隔离候选；正式发布、提交和推送仍须另行授权。最终源码树以本机 candidate-policy-final-11.json 与 delivery-manifest.json 为准，只有 strict 回执 passed=true 才构成最终交付。

候选为 `tmp/runtime-candidates/v2/stream-d2-07`，两独立根选择同一字节闭包。identity `BAA09F477BECEE80A7B8591C23F2EA9ADC7215C668B0466CA319476AE3031088`，closure `09E033D761DFD2D3CCCC3CFD0A74D1171E29756446FFD6492176B40BE319C391`，Core `C386AA5F64212B2DEAC644E85E919C8349F25469E4599CE0BE8CA92889E6CF2A`，实际 publish 的 asLoader `10B5CEB06BF91BD123B4529011A49ADEDDF8036D090471B22BF7E65E17999ADE`。末次修复仅工具与文档，不改变这些运行输入；重新封存源码并校验，复用已验证运行字节，不冒充独立 builder 或部署。

Host 全量 7,089 通过、27 项专项跳过；Node 全量 85 与 Worker projection 48 通过；真实 CS6 Worker 220、旧 Worker 52、Q1 16、Chain 8,997、HUD 136、Ray 协议443、Audio185/增量差分59,929、光源35及拖尾96行对照通过。套件有重叠，不相加计数。Ray 54 对/11,833断言的九组权威与 RNG 记录等价仅属于受控实际 AVM1 范围。

`stream-entry-finished-20261012-07` 的 v1/full/D1/D2 四组均自然 finished（444/400/945/981源帧），真实安装、原始结果绑定、revealed、战斗、死亡及回收通过。普通默认入口07只证明实际启动、单例及一次关窗退出，没有在该入口复验完整玩家业务或人类视听体验。

### 六轮配对成本

两条件均为同一优化候选，比较投影策略 full/D2。固定manifest仍运行独立真实随机战斗并保留动态增援，不是相同战局的回放；六轮数据不泛化到全部装备和地图。M134 官方单位镜像初始每侧四人，保留实际动态增援，专用测试 manifest 等量加HP至1,000,000，固定3,600源帧；生产数值未改。实际应用 LOW 256×144/E2/CAS关闭，输出320×180；不是用请求上限180p替代实际栅格。单实例12场、双实例24场，共36场，均真实自然 combat timeout；这批零 finished 强度样本，不报告竞技场净吞吐倍率。

| 范围 | full采样CPU中位数 | D2采样CPU中位数 | 六对CPU下降中位数 | full/D2平均源FPS |
|---|---:|---:|---:|---:|
| 单实例 | 101.273秒 | 89.867秒 | 12.15% | 29.973/29.979 |
| 双实例，合计4个进程 | 254.930秒 | 215.797秒 | 10.77% | 29.744/29.754 |

双实例最短保守共同战斗窗口 102.896秒。窗口由真实Host回包时间减实际AS2时长估计，并再减10秒；存在跨时钟估计限制。

CPU仅采样Host＋Flash自有进程生命周期，包含观测到的启动/回收，排除WebView子进程；不是纯战斗或整机/功耗数据。full/D2窗口点观测保留原始前后台状态，不能证明连续相同可见性。各进程内存峰值相加不是同一时刻的整机峰值；完整墙钟与内存数据见原始分析，不能把被排除的失败与启动成本当作零。这里比较的是Worker D2在优化候选上的额外收益；首轮五项/Q1局部成本表单独保留，不与本表相加。

### 回退与安全边界

停止拖尾绘制会改变真实getRect/AABB（修正夹具94/96行不同），已恢复原绘图，回退后96/96一致；保留独立六枪F8停产与O(1) ledger。未纳入PC2、Q64、L2、D3或新的碰撞模型。

旧dual1首组因当前w02自己的44821...槽恢复副本被误计为其他槽变化而严格停止。保留 shadow确认失败、.previous-GUID及旧不合格回执；没有重放该写或该实验。工具仅将同目录、精确声明槽的previous/tmp-32hex记录为targetArtifacts，其他槽/root/未知后缀仍完整保护。临时Git fixture曾继承私有索引，失败只影响自有review-index08；隔离环境后strict09 47/47与原/私有索引前后SHA均通过。PowerShell空环境变量造成的一次启动门误拒绝发生在实验/请求分配前，修正为明确原索引路径后才启动新身份。

最终保护快照核对98个原有记录，差异和意外新增均为0；仅本轮明确分配的测试槽及其恢复工件可写。私有版本marker在普通入口测试中更新，未混作玩家存档。临时请求/自有Host和Flash回收、CS6原指针和静默状态见final-process-lease-cs6-02.json。

正式部署指纹按各根分别核对：施工/peer45文件保持5C012E27620A38CC01E060D34F124C8B7654C79DB7FDD051801B6A0917D55258；primary45文件独立只读观察为5CDC5CC5955160D29B0AD809326D80AF3353B46A7749E4A9FE6DD39FE4100A05，44个payload文件与施工基线相同，consensus JSON字段相同而格式字节不同，不能混用原始指纹。primary关键运行文件和原信任文件另与此前默认入口快照核对。原Git索引的未知写锁保留，最终只用自有private review index封存；HEAD、原索引及他人差异不被清理。

### 本机证据索引

唯一人类入口为本文件；机器证据位于 `tmp/stream-cost-worker/`：

- `delivery-manifest.json`、`delivery-source.patch`：最终身份、源码树、来源和可复验补丁；无commit/push。
- `candidate-policy-final-11.json`、`review-index-final-11-integrity.json`：最新源码树 strict及索引字节保护。
- `host-full-result-06.log`、`node-full-save-artifacts-08.log` 与 `progress.json` 中各真实CS6套件/局部成本日志。
- `stream-entry-finished-20261012-07-compact.json`；普通默认入口为 `tmp/normal-candidate-regression/normal-default-07/outcome.json`。
- `fixed120-final-performance.json`；single-1/2与dual-1/2-repair08各具名compact及其实际experiment报告、原始结果/资源/窗口观测。
- `final-safety-files.json`、`final-formal-deployment.json`、`final-process-lease-cs6-02.json`：存档/正式文件/请求和进程收尾。
- `dual-repair08-series-complete.json` 与每块30分钟有界显示lease的ready/连续通知/end：期间亮屏及同线程清理。

## 保持的权威

AS2 仍决定射击、运动、碰撞、伤害、库存、冷却、死亡回调与对象销毁。D1/D2 保留原来的世界捕获、相机、场景呈现/揭幕、场景灯和装备灯；装备灯资格对真实防御 Buff 的影响不变。所有字段和运行结果继续绑定原 Worker / session / assignment / attempt / manifest / case / run 身份。

游戏 RNG 固定为 `legacy-global-consume-v1`：保留火焰原有 `Math.random()` 消耗，以及散射、伤害、拖尾运动的随机路径。`visual-event-v1` 仅用于 v2 Worker 的独立显示事件；实际射线出生先领取编号，消费者和显示预算不决定编号。普通 Guardian 与 v1 Worker 保留已有视觉随机流。

## 首轮五项

| 项 | 实现边界 | 验证入口 |
|---|---|---|
| Audio SFX | 每批缓存下一序号/header，一遍验证 UTF-8，增量累计字节；只在 flush 编码一次 | `scripts/run-audio-sfx-incremental-tests.ps1`；冻结旧 AS2 实现并跑相同生命周期输入 |
| Player HUD | delta 缺失组复用已验证的 typed 对象；提供的组仍完整验证，最后原子提交 | `PlayerHudStateTests`；`StreamCostBenchmarksTests` |
| F 分段 | 顺序且唯一的段从原包一次扫描后切片；乱序/重复段保留旧解析决定 | `XmlSocketFrameVisualTests`；`StreamCostBenchmarksTests` |
| SceneLight | 仍每帧真实采样；八个标准化标量不变时复用上次编码行 | `scripts/run-scene-lighting-tests.ps1` |
| Ray Host | 无新 config 的合法增量帧复用现有只读查找；新 epoch/新 config 仍走独立验证 | `RayVisualTests`、`RayChannelFrameTaskTests` |

成本夹具记录 CPU/分配/字节，不能替代完整游戏 FPS 或吞吐证据。HUD full 包不获得 delta 缓存收益，Worker 无英雄、音量为零时也不重复计价已有静默路径。

## Q1-R

当前连接经过 `visual_wire_offer → visual_wire_select → visual_wire_commit` 才采用 Q1。Host 在发 commit 前安装 decoder；首次实际合法 Q1 数据被采纳后才退休该连接的 legacy F5。迟到连接、冲突选择、未知字段和重复 JSON key 不可改变当前选择。

wire 为 `Q1|offerId|epoch|snapshotSeq|sourceFrame|count|overflow|R;tag,x,y[,rotation][,scaleX][,scaleY][,alpha]`。`tag=style+16*mask`，mask 的四位分别表示 rotation/scaleX/scaleY/alpha；仅精确的 `0/100/100/100` 默认值省略，负缩放保留。snapshotSeq 独立于源帧，空快照不带分号；count 上限沿用普通弹 1024。只接受有限范围内原始浮点，`overflow=0`；Q64 和场景 l2 未启用。

旧 Host 或旧 SWF 没有这条协商时继续 legacy。断连退休格式选择，重新授予保留原所有权和存活对象。真实 MovieClip、broadcaster、镜像/默认值、空快照、未知量化 profile 的 R 选择由 `scripts/run-visual-wire-q1-tests.ps1` 验证。

## Worker 会话策略

`arena-worker.launch.v1` 继续完整投影，不能夹带新策略字段。`arena-worker.launch.v2` 额外要求以下六字段：

```json
{
  "presentationPolicy": "full",
  "projectionConsumers": {
    "playerHud": "none", "ordinaryBullet": "none", "ray": "none", "chain": "none",
    "combatDecoration": "none", "sceneLighting": "full", "equipmentLighting": "full"
  },
  "controlFrameFormat": "f-visual-v1",
  "visualSeedRevision": "visual-event-v1",
  "simulationRngConsumptionRevision": "legacy-global-consume-v1",
  "sessionVisualSeed": 104729
}
```

上例为 D2；D1 仅将 playerHud/combatDecoration 设为 none。完整对照将七个消费者全部设为 full。当前实现明确拒绝 presentation=none、关闭灯光、D3 的控制占位格式或新的游戏 RNG 消耗版本。只有已核验隔离候选的 Worker 装配能发送此协议，普通 Guardian 不装配协商器。

固定 `worker-projection.v1` 消息为 offer/prepared/commit/committed/rejected，均使用现有 NUL JSON task 路径和接收端实际 connectionGeneration。独立 contractId 为 32 位小写 hex。offer/commit 包含完整身份、sequence、策略、ownership、四个 catalogBindings；prepared 返回实际已采用能力的摘要与 clean，不照抄未安装的 offer。Host 同时核对自身没有旧原生投影存活。policyDigest 使用固定字段顺序 UTF-8 JSON SHA256；它用于诊断，不能替代字段和连接检查。

既有 v1 capability 的目录摘要为大写 hex。新协议在 Host 的 `BindCatalogs` 与 AS2 的已采用目录读取边界统一为小写 `sha256:` 表达，不改变 v1 capability 的格式或验证强度；真实启动暴露的大小写拒绝已加入 Host/实际 AS2 协商夹具。

Host 在 socket 就绪后最多等待 120 秒加载窗口；只有普通弹、射线和 CombatFx 三项实际 capability 均成功发送后才发 offer，并开始原有 10 秒协商期限。加载时间不消耗 AS2 的安装期限；加载窗口也不能无限延长。AS2 下一次真实、root 所属 EnterFrame 原子安装，返回完整应用策略及 `installClockKind=flashRootEnterFrame`、installEpoch/installTick。这个时钟只证明策略安装，不是战斗、冷却或世界就绪时钟。每连接至多一个 pending offer 和一个 committed 策略；prepared/commit 回执有界缓存，启动控制预算为 32 条/64 KiB；重复相同消息复用回执。未收到 committed 不准 startBatch，超时/违约按现有 transport poison 结束该 Worker，不猜测安装状态。

断连立即退休策略。变更 full/none 或单侧回滚必须结束 Worker 后新建会话；不承诺在活动进程中热恢复。候选实验组可声明六字段 `group.projection`；协调器会封存 v2 launch、新 session/专用槽、真实安装回执和结果绑定。原始结果附带 projectionConsumers、contractId、安装回执、readinessKind 和两项随机版本。完整结果缺少这些身份不能取得 v2 实验资格。

## 源头门与边界

HUD 门在 hero/sample 之前；命令、查询和必需控制回包保持原路。普通弹仍保存 alpha 并隐藏已接管样式的 MC，none 不建立 tracking。六枪式联弹仍采用原 nativeGroupOwned、aggregate、预留、单元 ID/live 语义；none 的活组表按 dense index 在 release 时 O(1) 回收，不建立 births/deaths，不依赖 flush 清理。

射线的命中、visited、预算、衰减、游标、寿命、随机消耗无条件推进；只有命中点显示数组、meta、拓扑和 Bridge record/config/queue 被门控。CombatFx 只关闭已审核的 shell/muzzle/不使用返回 MC 的 impact，未知或需要 MC 的效果继续原路。尸体只跳过位图绘制，保留死亡时间轴、掉落、deinit 和原 pending-death 等待。

F5/F7/F8 出现在已提交 none 连接时，Host 在内层解析之前以 `unexpected_projection_after_none` 结束 attempt。F6 仍保留 source clock 与 `l` 装备灯行；none 装饰的 s/m/i/a 行同样在 DTO 解析之前拒绝。场景 F9、装备防御、世界呈现和揭幕围栏保持 full。

拖尾保留原绘图，D2 的六枪 F8 停产与 dense ledger 独立保留。`scripts/run-worker-trail-geometry-tests.ps1` 的真实 MovieClip 对照发现：96 个采样中 94 个 AABB/getRect 边界随停止绘图变化，实际单元运动坐标相同。第二采样的 x 范围从 `123.7..155` 变为 `145..155`；旧碰撞器读取的是实际绘图区边界，不能把此绘图视为纯展示。首个探针用 Drawing API 建基础矩形，clear() 会连基础矩形清掉，因此该轮仅保留为夹具修正记录；改成与 timeline 图形一样可在 clear() 后保留的矩形后确认上述耦合。停画门已回退，要求新的完整 96 行对照一致。此次不另改碰撞模型，不将剩余拖尾成本计为已去除。

## 验证与候选交付

Host 使用 canonical `launcher/tests/run_tests.ps1`；Node 使用 `tools/arena-calibration/run-checks.js`。AS2 追加 Q1、Worker producer/ledger 和拖尾几何 focused，并回归既有 HUD、CombatFx、Ray、Chain、Worker 协议套件，最后以真实 CS6 `-Target publish` 构建 asLoader。测试端的 WorkerProjectionTestHost 是控制夹具，不构成实际 Host 或候选运行回执。

`scripts/run-ray-rate-tests.ps1 -WorkerProjectionCompare` 使用生产 XML、真实 collider/BQP/Dodge/DamageCalculator 和随机引擎，交替 AB/BA 比较 full/none；原 cache provider、武器/AI/输入仍是受控替代。其命中、HP、死亡、预算与 RNG 终态可以证明受控权威等价，不能代签完整战斗或净吞吐。

隔离候选由 canonical `launcher/build.ps1` 生成，绑定本轮 source identity/closure；实际启动和 Worker 实验继续保留运行身份、存档保护、source FPS、真实 revealed、CPU/内存、启停与失败耗时。候选构建/执行/专项证明分别报告。本轮不提交、不推送、不更新正式 runtime。

无人值守实验可由本轮独立 wrapper 临时持有 display/system execution request，退出时释放；不修改持久电源设置，不在产品里默认增加此请求。捕获停顿仍记录失败并保留实际新帧、呈现与揭幕状态，不能用亮屏请求或重复 Present 代替新鲜 capture 证据。

本机证据索引为工作树 `tmp/stream-cost-worker/progress.json` 和各具名日志/trace。以下为 2026-10-12 03:00 的阶段记录；实机战斗与单、双实例性能对照仍待连续亮屏环境，不能以此阶段记录宣布整轮完成。

### 隔离候选与已通过证据

候选为 `tmp/runtime-candidates/v2/stream-d2-05`，identity 为 `F6B90157880D5E25A1E7C21370900DDEE34EA7EDC0EAA79E6D293F981C73B992`，payload closure 为 `7417892F6240469BF6C23F25B8F19B39EFF9F82CD8BB7C60CE9247A49BF50738`，Core SHA-256 为 `0C6FCAEA227DB2F7F41D6B24E4E4456EB096E3000AC059C936F90476687C71D0`。严格 Index 策略 47/47 绑定源码 tree `68c823c14f9563160d0f9282a3c9e8622529c8cf`；本节后补说明不冒充该旧 tree 的内容。第二独立资源根 `stream-worker-peer/CrazyFlashNight` 持有同源码及逐文件相同候选；这是同一 payload 的实例隔离副本，不是独立 builder。

Host 完整回归 7,084 通过、27 项专项跳过、0 失败；Node 85 项通过。真实 CS6 的 Q1 16 项、Worker 215 项、联弹 8,997 项、HUD 136 项、Ray 协议 443 项、既有 Worker 协议 52 项均通过。音频协议 185 项、增量 SFX 差分 59,929 项、场景光源 35 项通过；Ray full/none 两轮均为 54 对、11,833 个断言，九组业务与 RNG 记录相同。上述套件有重叠，不将数量相加当作独立测试数。最终 asLoader 由真实 CS6 publish 取得本轮 Compiler 0/0，SHA-256 为 `F06ED7C727077C2A4C41AA7319266D95055456055E2A3F269EABCD76200D191A`。

普通候选默认入口复验 `tmp/normal-candidate-regression/normal-default-05-r2/outcome.json` 为 passed：实际 Host、Flash 与第二个单例检查进程均退出 0，只发起一次 CloseMainWindow，没有进入游戏或发出批次命令。首轮包装在已退出 Flash 的 WMI 残影上错误拒绝，保留失败；修正只用已持有进程句柄核对终态，未放行未绑定存活进程。由此取得有限的 `candidate_executed`，不取得竞技场 `e2e_verified` 或正式标准入口验收。普通启动新增/更新了私有根的版本 marker；85 个既存记录与真实玩家存档未改，正式文件及原信任文件摘要相同。

### 成本对照及边界

以下为同输入、交替 AB/BA 的局部 CPU/分配或 AS2 夹具计时，均不等于完整游戏 FPS、双实例吞吐或功耗：

| 路径 | 对照输入 | 基线 → 候选 |
|---|---|---|
| A1 SFX | 实际就绪 AVM1，720 批 × 64 事件 | 编码/生产合计 48,034 → 2,162 ms |
| H1 冷却增量 | 6,144 包、六对 AB/BA | 165,615,984 → 123,985,680 分配字节；574.626 → 363.984 ms |
| H1 完整快照 | 6,144 包，同样顺序 | 分配均为 643,152,528 字节；722.893 → 660.264 ms，短时计时有噪声 |
| T1 有序密集帧包 | 1,536 包、六对 AB/BA | 1,350,765,696 → 327,375,016 分配字节；501.728 → 222.311 ms |
| R1 无 config 增量 | 12 个已缓存 config、24,576 次 Apply | 14,942,224 → 0 分配字节；9.2319 → 4.0415 ms；没有活跃射线/GPU |
| Q1-R 普通弹默认变换 | 每包 512 条、1,536 包 | wire 12,176 → 5,013 字符；237.23 → 88.2475 ms；DTO 分配相同 |
| Q1-R 混合变换 | 每包 512 条，含镜像/旋转/缩放/alpha | wire 13,968 → 11,029 字符；227.4322 → 168.0361 ms |

Q1 首次对照发现 generic 字符范围搜索在 tiered JIT 预热前产生额外分配。候选 05 改为相同 ASCII 范围的有界逐字符检查；128 条小快照旧/新均为 5,652,480 字节/1,536 包，原 43,401,216 字节的失败前像保留。R1 基线由 `38f24d4` 两份完整 partial 源文件仅改类名冻结；Q1/R1 原始样本与真实 Core 哈希在 `tmp/stream-cost-worker/cost-probe/managed-cost-05.json`，HUD/帧包在 `stream-bench-quiet-final.log`。

### 实机阻塞与未完成项

两轮真实 Worker primer 均保留失败。v1 进入候选后只有首个通过裁剪/时间围栏的 WGC 源帧，调整源预算后没有新鲜源帧，场景不予真实 revealed，最终 `bridge_lost`；等待期间约 30 FPS 不计作战斗。v2 首轮的旧 capability 大写摘要拒绝与第二轮在加载期过早 offer 导致的安装超时均已修正并回归，但新候选尚未取得真实 v2 安装及完成战斗回执。

连续系统通知确认显示状态为 0，输入桌面为 Default、屏保未运行。临时 execution request 与 PowerRequest 均被系统接受但无法保持实际亮屏；一次自有隐藏 HWND 的唤醒短暂转为 1 后又变为 0，所有临时请求均已清除。实际根因仍不可仅凭这些通知定论。自有绘图窗口的连续诊断约每秒 4 个新帧，不能给真实 Flash 或 30 帧战斗代签。没有修改电源计划、注册表、锁屏或捕获/揭幕准入，没有继续重复唤醒。

`entry-plan-05.json` 的 v1/full/D1/D2 四组及 `perf-single-{1,2}-plan-05.json` / `perf-dual-{1,2}-plan-05.json` 各六轮 AB/BA 已准备，尚未消费。需当前 identity/closure 和连续亮屏条件成立，先取得入口真实回执，再执行性能组；1800 源帧的自然 combat timeout 可作成本/节拍样本，但不是 finished 强度样本，零 finished 样本不宣称吞吐倍率。所有失败、受控替代和人类验收缺口保留。本轮未提交、未推送、未正式推广。

## 2026-10-12 06:55 实机恢复及结果绑定修复

用户确认显示器曾手动关闭，06:42 只读查询实际恢复为 1。新连续通知 lease 覆盖四组 stream-entry-20261012-05 的启动到回收，全程保持 1，同一线程设置与清除临时请求，全部 owned Host/Flash 自然退出、存档和资源保护通过。v1 实际揭幕后运行 300 源帧并自然 combat timeout；full/D1/D2 均取得真实 root EnterFrame 安装回执，完成实际 300 帧战斗，但原始结果缺少策略绑定字段，严格 Node 验证全部拒绝，整轮不合格。失败与真实执行证据分别保留在 entry05-real-summary.json、entry05-actual-launcher.log 和原始 shard receipt，不能将安装成功升级为完整联调通过。

结果链修复在开战前由 AS2 捕获匹配 contract/generation 的实际安装及完整消费者回执，放入本轮不可变 context；异步转场或断连不得重读当前策略补身份。Host 在 dispatch 时一次捕获本轮预期，实际回包必须逐字段完全匹配；缺失、不同消费者、不同 contract 或 installTick 均按未知传输终态 poison，禁止同会话重放。Host 仅转存真实回包字段，保留既有 Node 资格门。新候选 06 需完成对应 Host/真实 CS6 回归、发布 asLoader、strict policy 后使用全新实验身份。首次新 AS2 夹具未先安装 ArenaCalibrationService，218 通过/2 失败保留为夹具修正记录；修正夹具初始化后另起本轮验证。

## 2026-10-12 07:25 严格原始结果 schema 收口

候选 06 已通过 strict 47/47；entry06 的 full/D1/D2 在真实安装和揭幕后运行，实际原始结果均包含完整匹配的安装回执。既有 result.v1 schema 没有声明这八个字段，additionalProperties=false 因而拒绝这些结果；v1 仍通过，整轮保留为不合格，不覆盖或重放。临时连续显示 lease 全程为 1，四组 owned 进程、存档和资源保护正常回收。

补齐 result schema 的八个有类型字段，任一出现必须整组出现并保留 Worker/run 身份；七个消费者、四个 catalog、完整安装回执及 root EnterFrame 时钟均严格声明，未知字段仍拒绝，D3/占位控制帧/关闭灯光仍拒绝。Node 定向回归同时经过通用 raw schema 和专用 installed-contract 检查，覆盖旧格式、新完整格式、缺字段及未知/错误嵌套字段。此工具源码属于声明的 source 输入，生成新隔离候选 07、fresh strict policy 和新实验；AS2/C# 源码未变，不重做已通过的 220/52 CS6 和 7089/27 Host。

## 2026-10-12 09:35 持续对照及自有恢复工件

候选 07 的四组 v1/full/D1/D2 均真实 finished、安装与原始结果绑定及死亡/回收通过；普通默认入口07启动/单例/退出通过。单实例六轮固定3600源帧、约120秒 AB/BA 已通过；采样 Host+Flash CPU 的配对下降中位数12.149%，两条件源帧节拍均约29.98FPS，此值不含WebView子进程且不构成整机/吞吐收益。双实例固定120试跑各两场3600源帧合格，保守共同窗口104.8/104.4秒，完整9912观测资源字节相同。peer六个生成文件仅CRLF/LF不同已确认语义等价后统一实际字节，保留旧不合格回执。正式六轮双实例仍待完成。

双实例第一块仅首组运行后严格停止。当前 w02 自有专用槽44821...的启动期 shadow 保存确认失败，保留 .json.previous-GUID 恢复副本；目标与恢复副本都等于只读种子3991A305...，没有玩家槽覆盖，不报告保存成功、不重放该写。保护快照将这份声明槽自身恢复工件误计成其他槽变化。工具只识别同目录精确目标 .json.previous-32hex/.json.tmp-32hex，单独记录 targetArtifacts 的路径/大小/SHA；其他槽、其他root、未知后缀继续完整保护。Node定向与全量85通过。该修复仅工具源码，C#/AS2与运行payload输入未改，复用既有Core/identity/closure并以新的 strict source-review tree验证，不重编相同SWF或宣称旧不合格实验新通过。

原Git索引有未知0字节写锁，未删除或修改；用自有临时review index复制原索引，明确核对原tree未改，并把授权工具/文档改动封存为可审阅tree。原索引与HEAD均保留，未commit/push/部署。

私有索引第一轮 strict 46/47：workbench ratchet 的临时 Git fixture 继承 GIT_INDEX_FILE，向自有 review index 加入 fixture.css，未写原索引；该失败回执保留。fixture 仅在自有临时仓库调用期间隔离 GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE/GIT_INDEX_FILE，并 finally 恢复调用者环境；原门、规则和运行代码不变。新 review index 从未变原索引复制，封存四个授权工具/文档差异，校验前后私有与原索引字节均须不变。
