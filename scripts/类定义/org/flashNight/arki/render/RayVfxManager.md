org.flashNight.arki.render.RayVfxManagerTest.runAllTests()


=== RAY VFX MANAGER TEST SUITE ===
===== RayVfxManagerTest 开始 =====
--- cfgNum ---
[PASS] cfgNum 正常读取
[PASS] cfgNum 读取 0 不回退
[PASS] cfgNum 读取负数
[PASS] cfgNum 字段不存在
[PASS] cfgNum null config
  [INFO] cfgNum({}, 'missing', 55) = 55
--- cfgArr ---
[PASS] cfgArr 正常读取返回原数组引用
[PASS] cfgArr 空数组不回退
[PASS] cfgArr 字段不存在
[PASS] cfgArr null config
--- cfgIntensity ---
[PASS] cfgIntensity 正常值
[PASS] cfgIntensity 零值不回退
[PASS] cfgIntensity null meta
[PASS] cfgIntensity 字段不存在
--- chainDelay ---
[PASS] chain hitIndex=0 不延迟
[PASS] chain hitIndex=1 延迟=2
[PASS] chain hitIndex=3 延迟=6
--- forkDelay ---
[PASS] fork hitIndex=0 延迟 1 帧
[PASS] fork hitIndex=5 延迟 1 帧
--- disableDelay ---
[PASS] chainDelay=0 chain 不延迟
[PASS] chainDelay=0 fork 不延迟
[PASS] pierce 不延迟
--- delay edge cases ---
[PASS] null meta 不延迟
[PASS] null config 不延迟
[PASS] main 不延迟
[PASS] 负 chainDelay 不延迟
--- pt pool ---
[PASS] pt.x 赋值正确
[PASS] pt.y 赋值正确
[PASS] pt.t 赋值正确
[PASS] pt 池复用同一对象引用
[PASS] pt 复用后 x 更新
[PASS] pt 复用后 y 更新
--- arr pool ---
[PASS] poolArr 返回非 null
[PASS] poolArr 返回空数组
[PASS] push 后长度正确
[PASS] poolArr 池复用同一数组引用
[PASS] poolArr 复用后长度清零
--- pd pool ---
[PASS] pd.path 引用正确
[PASS] pd.isMain 正确
[PASS] pd.isFork 正确
[PASS] pd 池复用同一对象引用
[PASS] pd 复用后 path 更新
--- pool multiple allocations ---
[PASS] 连续 pt 分配返回不同对象
[PASS] 第一个 pt 保持独立
[PASS] 第二个 pt 保持独立
[PASS] 连续 poolArr 分配返回不同数组
--- straightPath ---
[PASS] straightPath 生成 2 个点
[PASS] 起点 x
[PASS] 起点 y
[PASS] 起点 t=0
[PASS] 终点 x
[PASS] 终点 y
[PASS] 终点 t=1
--- generateSinePath ---
[PASS] generateSinePath 至少 12 个点, 实际=97
[PASS] sinePath 起点 x
[PASS] sinePath 起点 y
[PASS] sinePath 起点 t=0
[PASS] sinePath 终点 x
[PASS] sinePath 终点 y
[PASS] sinePath 终点 t=1
[PASS] sinePath t 值严格单调递增
[PASS] sinePath x 沿射线方向单调
[PASS] sinePath 中间点有 Y 偏移
--- generateSinePath noise ---
[PASS] clean 起点 x
[PASS] noisy 起点 x
  [INFO] midClean.y=9.46653372881942 midNoisy.y=9.46653372881942
--- generateSinePath short ray ---
[PASS] 短射线至少 2 个点
[PASS] 短射线起点 x
[PASS] 短射线终点 x
--- lifecycle ---
[PASS] 初始活跃数=0
[PASS] 初始延迟数=0
[PASS] spawn 后活跃数=1
[PASS] 过期后活跃数=0
--- multiple arcs ---
[PASS] 3 条射线活跃
[PASS] 全部过期后活跃数=0
--- fade alpha ---
[PASS] visual phase 活跃
[PASS] fade phase 仍活跃
[PASS] fade 结束后销毁
--- LOD ---
[PASS] 初始 LOD=0
[PASS] 4 条 spectrum LOD>=1, cost=10
[PASS] 10 条 spectrum LOD=2, cost=25
[PASS] reset 后 LOD=0
--- delayed queue ---
[PASS] 延迟段不立即活跃
[PASS] 延迟队列有 1 条
[PASS] 5 帧后仍在延迟
[PASS] 延迟队列仍有 1 条
[PASS] 6 帧后转为活跃
[PASS] 延迟队列清空
--- fork delayed queue ---
[PASS] fork 延迟不立即活跃
[PASS] fork 1 帧后活跃
--- reset ---
[PASS] reset 前有活跃或延迟
[PASS] reset 后活跃数=0
[PASS] reset 后延迟数=0
[PASS] reset 后 LOD=0
[PASS] reset 后 renderCost=0
--- initWithContainer ---
[PASS] initWithContainer 后活跃数=0
[PASS] initWithContainer 后 spawn 正常
[PASS] 重复 initWithContainer 清理旧状态
--- drawPath edge cases ---
[PASS] drawPath 空路径不崩溃
[PASS] drawPath 单点不崩溃
[PASS] drawPath 2 点正常
--- drawCircle edge cases ---
[PASS] drawCircle 零半径不崩溃
[PASS] drawCircle 负半径不崩溃
[PASS] drawCircle 零 alpha 不崩溃
[PASS] drawCircle 正常绘制不崩溃
--- bench generateSinePath ---
  generateSinePath x100 = 133ms (1.33ms/call)
--- bench pool ops ---
  pt x100000 = 388ms
===== RayVfxManagerTest 结束: run=103, pass=103, fail=0 =====
=== RAY VFX MANAGER TEST SUITE END ===
[compile] done
