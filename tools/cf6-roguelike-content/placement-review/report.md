# CF6 无车战20图 出生点源证据边界检查报告（K3 content r8，主控复核）

- 轮次：r8；日期 2026-10-21；执行线：K3 内容线（只读共享代码；未改 maps.fragment/generator/共享 chapter/AS2/资产/测试脚本；未执行 CS6/游戏；无网络、无凭据操作、未 commit/push）。
- 配套机读产物：`tools/cf6-roguelike-content/placement-review/report.json`（由 `source-boundary-check.py` 生成，同目录）。
- 前置报告：K3 maps r6 几何审计 `tmp/cf6-roguelike-20261021/kimi-maps/r6/result-r6.md` 与 `placement-audit-r6.json`（unknown 项的原始出处）。

## 输入身份（SHA256，report.json 同载）

| 输入 | SHA256（前16） |
| --- | --- |
| `data/stages/books/cf6-sting.json` | `d79e716efab238b0` |
| `data/stages/books/cf6-sting-source/maps.fragment.json` | `b47024d66ed716d8` |
| `data/environment/stage_environment.xml` | `983fa55e361a6d52` |
| `tools/cf6-map-runtime/generated/runtime-index.json` | `7aafd2377cdd6f1a` |

语义结论绑定的源码 hash（任一变化即需重核结论）：`WaveSpawner.as` `313f35a1`、`StageEvent.as` `7f2b4343`、`单位函数_lsy_敌人模板迁移.as` `c40304f7`、`CollisionLayerRenderer.as` `717e1427`、`SceneCollisionManager.as` `b5e72925`、`Mover.as` `08a3d298`、`CombatModule.as` `b6e0a3bf`、`UpdateEventComponent.as` `9aa274bb`（全值见 report.json `sourceEvidence`）。

## 证据边界

静态点/多边形几何 + 已核源码路径语义归类；**未运行 Flash/CS6/游戏**。墙环内（boundary_ring）只表示"单位一旦发起移动，`resolveCollision` 朝心挤出路径适用"；单位是否/何时移动（AI tick、待机/登场景门、XFL 时间轴 `行走()` 节律）与精确回界帧数**只能实机确定**。静止的界外单位没有任何逐帧代码修正其位置（无逐帧 clamp；`enforceScreenBounds`/`pushOutFromCollision` 不在普通敌人逐帧路径，`Mover.as:516-617` 及其调用方）。本轮未把 original facts 改成新坐标，未追加测试。

## 结论一：A17 Boss（兵种472，InstanceName=cf6Boss_A17，世界 963.55,305.9 vs walk Ymin=329.2）

**源码结论：出生位置原样保留；当单位向界内发起移动且命中墙环时，存在朝界内挤出的代码路径。它不保证单位实际发起移动、成功回界或可被命中，不能据此排除长期停在界外。**

已核源码路径（均按当前工作树，行号已逐条复核）：

1. **生成链**：`BookRunRules.as:119-136` 配置原样进关卡 → `WaveSpawner.startWave`→时间轮→`WaveSpawner.spawn`（`WaveSpawner.as:311-351`）→ `spawnEnemy`（`WaveSpawner.as:353-416`）→ `initObject._x = x; initObject._y = y;`（**as:412-413，无任何 clamp**）→ `_root.加载游戏世界人物` = `gameworld.attachMovie`（`关卡系统_lsy_场景转换.as:477-484`）。
2. **地面Z/深度**：`Z轴坐标 = this._y`（`单位函数_lsy_敌人模板迁移.as:723`），无地面吸附；`DepthManager.updateDepth` 只钳深度值、不改写位置。
3. **碰撞初始化**：`SceneCollisionManager` 只登记地图碰撞，不触碰单位位置；出生时刻无 depenetration（`Mover.pushOutFromCollision` 全仓仅 3 个调用方：主角过场景、镜之虎彻、主角/佣兵 AI 卡死脱困）。
4. **边界机制**：行走区被画成碰撞层上的实心墙环（外扩 300px，`CollisionLayerRenderer.drawBoundary` as:45-90；margin=300 由 `SceneCollisionManager.as:112` 显式传入）。Boss 出生点 y=305.9 ∈ [Ymin−300, Ymin) = [29.2, 329.2)，**嵌在上边界墙环内**（当前位置 hitTest=true）。
5. **AI 移动路径**：屏外剔除仅关渲染（`UpdateEventComponent.as:54-56`，`unitAI.update()` 不以可见性为门，as:105-106）；追击未入攻击距离且非 standby 时 `下行 = diff_z > 0`（`CombatModule.as:139-140`）。`Mover.move2D`（as:143-157）目标点撞墙则转 `resolveCollision`（as:384-426）：按 lerp（移动方向，指向场景中心）以 `max(speed,5)` 步长挤出。若追击方向朝界内，该路径可使位置向界内移动；实际方向、调用频率、动画门和最终位置仍需实机证据，不估算确定的回界帧数。

静态无法证明（保留 runtime-pending）：① XFL 时间轴 `行走()` 的真实逐帧节律；② 待机/登场动画是否门控移动（`待机` 属性赋值点不在 .as 源码侧）；③ 若 Boss 入攻击距离后站桩射击而永不移动，它将停在界外 23px 处，玩家能否命中该 z 差（23.3px）的目标无静态证据。原作同位（native 675.6,226.7，原作同样在行走带上沿之外），属原作既有放置而非装配漂移。

**最小修正建议：无（不改数据）。** 交主控实机确认项：Boss 战开局后是否被 AI 带入行走带；若实机证实站桩不出界且玩家不可命中，再议候选（如下压到世界 y≈330 或按原作语义保留并验证命中），原始值/候选值届时由主控定夺。

## 结论二：A06/A17 Boss 支援怪屏外原坐标（r6 unknown 项）

r6 报告出处：`tmp/cf6-roguelike-20261021/kimi-maps/r6/result-r6.md` "未知 26 项"第 2 条；机读明细在 `placement-audit-r6.json` 的 A06 `boss[0][5]` 与 A17 相关检查项（含 reverification 溯源）。

本轮沿现役源码的判断（当前 book 值）：

| 入口 | 世界坐标 | walkBounds | 越界量 | 结论 |
| --- | --- | --- | --- | --- |
| A06 boss[0][5] 兵种466 L41 | (8.45, 338.8) | X 53.45–1503.45 | 左 45px | boundary_ring |
| A17 boss[0][6] 兵种469 L56 | (291.95, 449.1) | X 337.95–1787.95 | 左 46px | boundary_ring |
| A17 boss[0][7] 兵种469 L56 | (1834.85, 495.5) | 同上 | 右 46.9px | boundary_ring |

- **SpawnIndex 与显式 x/y 的优先级已静态证明**：显式 x/y 绝对优先，原样采用不钳制；`SpawnIndex` 仅当 x 或 y 缺失（NaN）时才整点替换（`WaveSpawner.as:355-410`）。boss 支援与波次共用同一 `spawnEnemy` 出口（`StageEvent.as:184-199`）。三点 y 均在行走带内，仅 x 越界。
- **回界机制同结论一**：三点均在墙环内（<300px），可适用相同的条件式挤出路径；是否发起朝界内移动、成功入场及可被命中仍未知，不能升级为必然回界。
- **原始语义**：r6 已溯源三点与原作 id=1585 实例同位（屏外 45–47px 对称入场位），runtime-index 将 sprite1585 标为"语义未识别"。结合源码（界外照常 tick + 回推区），"屏外入场、走入场内"的原作意图与引擎行为相容；runtime-index 的"未识别"标注不变，最终确认仍属主控实机。
- **状态说明**：补充了与屏外入场相容的源码路径，实际入场结论仍为 unknown；暂保留原作入场位。若实机发现阻断，可评估去掉显式 x/y、使用已核出生线的候选，原始值为 (8.45,338.8)/(291.95,449.1)/(1834.85,495.5)。该调整会改变入场位置，不能直接声称与原作语义等价。

## 结论三：20 图入口只读摘要（当前 book hash d79e716e）

全部 174 个入口：inside_walk 129、boundary_ring 4（即上述 3 点+A17 Boss）、**beyond_ring 0、碰撞多边形内 0**、引擎出生线语义 39、引擎默认语义 1（A15 Wave[0][0] 兵种460 L50 无坐标无 SpawnIndex，走 `WaveSpawner.as:404-408` 默认 1/3 左 2/3 右，原作语义保留）。

| 图 | 玩家 | 波次敌 | 支援怪 | 商人 | 证据状态 |
| --- | --- | --- | --- | --- | --- |
| TUTORIAL | 1✓ | 2✓ | — | — | 几何通过（vanilla 图，r6 已核） |
| A01 | 1✓ | 6✓ | — | 1✓ | 几何通过 |
| A02 | 1✓ | 9✓ | — | — | 主控已修 r6 失败2点（现值 (871.95,380)/(1128.95,381)，本轮未重审） |
| A03 | 1✓ | 6✓ | — | — | 点几何通过；实际门与碰撞待核 |
| A04 | 1✓ | 6✓ | — | — | 同上 |
| A05 | 1✓ | 7✓ | — | — | 同上 |
| A06 | 1✓ | 1✓ | 15（1 环内界外+8 出生线+6 界内） | — | 支援屏外点有条件式回界路径，实机结果未知 |
| A08 | 1✓ | — | — | 1✓ | 几何通过 |
| A09 | 1✓ | 5✓ | — | — | 点几何通过；实际战斗待核 |
| A10 | 1✓ | 2✓ | — | — | 点几何通过；实际电梯行为待核 |
| A11 | 1✓ | 1✓ | — | 1✓ | 点几何通过；实际战斗待核 |
| A12 | 1✓ | 6✓ | — | — | 点几何通过；实际战斗待核 |
| A13 | 1✓ | 1✓ | — | — | 同上 |
| A14 | 1✓ | 3✓ | — | — | 同上 |
| A15 | 1✓ | 1（默认语义） | — | — | 同上 |
| A16 | 1✓ | — | — | 1✓ | 同上 |
| A17 | 1✓ | 1（Boss，环内界上23px） | 16（2 环内界外+9 出生线+5 界内） | — | 结论一/二，实机待核 |
| A18 | 1✓ | 8✓ | — | — | 主控已修 r6 失败2点（SpawnPoint[0] 现值 (885.0,232.05)），本轮未重审 |
| A19 | 1✓ | 6✓ | — | 1✓ | 点几何通过；实际战斗待核 |
| A20 | 1✓ | 1✓ | 14（10 出生线+4 界内） | — | 主控已修 boss[0][0]（现值 (263.0,201.05)），本轮未重审 |
| A22 | 1✓ | 1✓ | 16（12 出生线+4 界内） | — | 主控已修 boss[0][3]（现值 (263.0,201.05)），本轮未重审 |

"✓" = 当前输入下点几何在行走区内且不在碰撞多边形内（report.json 逐条可查）；r6 的几何证据（转换零漂移、连通性参考网格、商人锚点判定等）绑定其开始快照 `083be489…`，与本轮输入 hash 不同，引用时注意边界。r6 五项失败修复值已落入当前 book（上表），按本轮授权未重审其新几何。

## 阻断与移交

- **本轮未发现新的确定阻断问题**（无 beyond_ring、无墙内出生）；不提数据修正，original facts 保持原值。
- 移交主控实机确认清单（按优先级）：① A17 Boss 开局后是否被 AI 带入行走带、站桩时玩家可否命中；② A06/A17 三只屏外支援怪实际入场表现；③ 主控已修五点的新坐标实机复核（不属本轮范围）。
- 若 ① 证伪的最小修正：A17 Boss `y` 226.7→候选 ≈251.0（native；origin_y=−79.2，对应世界 ≈330.2，入界约 1px 余量）或保留原值改验证命中；原始值/候选值/理由如上，由主控确认技术结论后集成，本线不自行改业务数据。
