# 射线速率与视觉通道回归

本夹具不启动游戏、不访问存档、不改 XML 或射速规则。读取现役 `data/items/bullets_cases.xml`，由 `TeslaRayConfig.fromXML` 解析磁暴基础/强化、光棱强化、热能强化、谐振强化和喷火配置；`pierceLimit` 与喷火脉冲、寿命、预算直接采用该文件，不为压测调低。

```powershell
chcp.com 65001
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-ray-rate-tests.ps1 -SkipCompile
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-ray-rate-tests.ps1 -TimeoutSeconds 1800
```

第二条使用真实 CS6 TestLoader。公共 focused runner 的 `AsyncBehaviorTimeoutSeconds` 默认仍为 30 秒；大型矩阵在本域明确使用 1800 秒（runner 默认 `TimeoutSeconds=1800`），且不超过 `TimeoutSeconds`。后台 Flash 回调可能受到节流，整轮墙钟时间已出现约17.5分钟；不能把该墙钟或函数计时换算成游戏 FPS。只延长本轮同 runId 的异步行为等待；Compiler 新鲜 `0/0`、失败 sentinel、唯一闭合块和 scratch 字节恢复要求不变。runner 打印本轮 XML SHA-256。

矩阵包含 single、pierce、chain、fork、combo、flame，各按每枪口 5/10/20/30 发每秒（30 Hz 逻辑时钟）执行；1 位射手×1 枪口和2位射手×2枪口，共48组。另有6组低 HP 目标的死亡/选靶变化场景。每组比较 `channelVersion=0/1`，合计54对。喷火复用在两边均保留，新通道协议还将喷火按真实枪口身份隔离；多枪口喷火对象数因此可能增加，不将旧的跨枪口误合并当成节省目标。普通场景120个发射 tick＋30个自然排空 tick，死亡场景60＋30；每次 Flash 回调最多推进8个逻辑 tick，并在20 ms 后让出，不把全部矩阵塞进一次脚本调用。

真实执行与替身边界：

- 真实：生产配置、`RayCollider`/`BandRayCollider`、细线碰撞器池、`BQP.preCheckRay`→`processRayBullets` 的选择与预算、`DodgeHandler`、`DamageCalculator`、默认伤害工厂的适用 handlers（包含暴击）、PinkNoise/LCG、空 `ShieldStack`、HP 扣减、自然退场、`RayVfxManager`/`RayVisualBridge`。`_raySettleProbe` 必须为 null。
- 真实视觉身份入口：自有 MovieClip 射手与枪口、普通 weapon 对象，调用 `captureShot` 和 `TeslaRayLifecycle.bindFrameHandler`；不直接伪造 source/key/serial。目标具有独立 version/name，BQP 生产代码记录拓扑。
- 替身：提供固定有序目标缓存，不测 TargetCache 的世界更新成本；以测试属性组装每发普通 Object，不经过武器动画、弹药、Factory 上游赋值和角色 AI。伤害类型、基础威力与暴击回调是明确的受控输入，不冒充某件完整武器构筑。事件 dispatcher 只计数并处理测试目标死亡标记，受击变色、EffectSystem、伤害数字显示出口不绘制。
- RNG：真实 PinkNoise 与 LCG 从相同可恢复状态起步，并计数其生产调用；`Math.random` 使用独立有种子的测试序列并计数。视觉 RNG 继续隔离。比较命中顺序、倍率、闪避结果、逐次 HP 损失、暴击序列、预算/退场、最终 HP、随机消费与最终引擎状态。

`[RAY_RATE_RESULT]` 后是 JSON：分别提供完整受测函数窗口、BQP 选择/结算、wire 序列化的 getTimer P50/P95/max/mean/sum；舍弃前15个逻辑 tick，日志输出放在计时窗口外。另报逻辑 active、native visual、Flash fallback 峰值、真实 `checkCollision` 调用数、缓存取得次数、伤害/事件/RNG次数、wire字节。`checkCollision` 数**不是候选访问总数**，chain 中心距离搜索也不由它计数。计时包含轻量观测包装，1 ms 分辨率会产生零样本；不是完整帧时间、GPU时间或实战FPS。

每个 RESULT 还包含完整已记录玩法值的 `gameplaySummary`：以固定顺序编码全部命中行、退场行、目标 HP、暴击序列、RNG消费/最终状态、缓存获取及事件计数，再计算两路32位滚动摘要。计时、碰撞调用次数、视觉和 wire 被明确排除。该摘要非密码学哈希，也不是 SWF、对象内存或二进制字节的等价证明；实际门仍逐项比较数组和数值。每对另输出 `[RAY_RATE_PAIR]`，包含九组玩法比较的通过数、已比较行数、摘要，以及独立的碰撞调用差值。

## 扫描预筛选对照

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-ray-rate-tests.ps1 -ScanCompare -SkipCompile
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-ray-rate-tests.ps1 -ScanCompare -TimeoutSeconds 900
```

`-ScanCompare` 使用独立的 `ScanCompare.TestLoader.as.template`，Domain 仍为 `ray-rate`，runner 精确要求 `pairs=4`。默认入口仍为原54对，驱动保持8 tick/20 ms让出。扫描对照两侧均固定 `channelVersion=1`，仅切换生产公开纯函数 `BulletQueueProcessor.rejectRayCandidateY(ray,target,zOffset,halfWidth)`：参考侧临时返回 false，让候选继续走原 `checkCollision`；优化侧恢复真实函数。两侧都使用当前代码的二分起点延后位置，因此不是旧/新 BQP 二进制总性能对照。

四组均为2位射手×2枪口：single 30发每秒（控制组）、chain 30、pierce 20、flame 20。每侧60个发射 tick＋30个排空 tick，配置、seed、布局及驱动一致；仍舍弃15 tick预热，仅该模式改为最多32 tick/100 ms一次让出。异步等待显式900秒。短矩阵输出统计与玩法摘要，不重复默认代表场景的完整wire日志。

命中顺序、伤害倍率、HP、暴击/RNG、预算、寿命和事件仍严格相等；`cacheAcquires` 也必须相等。只有 `collisionCalls` 允许减少，RESULT/PAIR 分别报告 before、after 和差值，不能以少做伤害结算换取通过。无论正常结束或异常结束都恢复生产 helper。尚未执行的对照不得写成扫描优化已通过。

有限代表场景（单枪口 Tesla single/chain 的10/30发每秒、straight pierce 30、flame 30，均含 off/on）在结算完毕后输出完整连续回放：

```text
[RAY_RATE_SCENE] <unique-key>
[RAY_RATE_WIRE] <生产 F7 payload>
```

每个代表场景保持150个连续 tick，保留实际配置、颜色、线宽、目标端点和照明字段，不压细光束或降低透明度。主控可用同一 native DLL 重放并另行观察GPU容量。其他场景只输出统计和断言，避免日志规模掩盖计时。

通过只证明这个隔离场景中视觉通道不改变所测玩法结果及对应函数成本。缓存/AI/动画/完整事件订阅、世界绘制和现场多武器拥塞仍需单独测量；不能据此直接声称“高射速已无性能上限”或批准删除插件射速门槛。
