// 执行完整测试套件
org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheProviderTest.runAll();


================================================================================
🚀 TargetCacheProvider 完整测试套件启动
================================================================================

🔧 初始化测试环境...
📦 创建了 30 个测试单位
🌍 构建了模拟环境和帧计时器

📋 执行基础功能测试...
✅ initialize返回成功 PASS
✅ 初始缓存数量为0 PASS (expected=0, actual=0)
✅ getStats返回对象 PASS (object is not null)
✅ 初始请求数为0 PASS (expected=0, actual=0)
✅ 初始命中数为0 PASS (expected=0, actual=0)
✅ 初始未命中数为0 PASS (expected=0, actual=0)
✅ getCache返回缓存实例 PASS (object is not null)
✅ 返回正确类型 PASS (correct instance type)
✅ 缓存数量递增 PASS (expected=1, actual=1)
✅ 相同请求返回相同实例 PASS
✅ 总请求数为2 PASS (expected=2, actual=2)
✅ 缓存命中数为1 PASS (expected=1, actual=1)
✅ 缓存未命中数为1 PASS (expected=1, actual=1)
✅ 敌人请求后缓存数量 PASS (expected=1, actual=1)
✅ 不同阵营请求后缓存数量 PASS (expected=2, actual=2)
✅ 全体请求后缓存数量 PASS (expected=3, actual=3)
✅ 全体请求命中后缓存数量不变 PASS (expected=3, actual=3)

🔍 执行核心缓存获取测试...
✅ 新缓存创建成功 PASS (object is not null)
✅ 缓存包含数据 PASS
✅ 缓存创建统计正确 PASS (expected=1, actual=1)
✅ 缓存未命中统计正确 PASS (expected=1, actual=1)
✅ 首次请求未命中 PASS (expected=1, actual=1)
✅ 首次请求无命中 PASS (expected=0, actual=0)
✅ 第二次请求命中 PASS (expected=1, actual=1)
✅ 返回相同实例 PASS
✅ 命中率计算正确 PASS
✅ 过期后帧数更新 PASS
✅ 过期触发更新统计 PASS (expected=1, actual=1)
✅ 不同请求类型缓存数量 PASS (expected=5, actual=5)

♻️ 执行缓存生命周期测试...
✅ 失效后帧数为0 PASS (expected=0, actual=0)
✅ 失效后重新更新 PASS
✅ 特定类型失效有效 PASS
✅ 清理前有多个缓存 PASS
✅ 部分清理后数量减少 PASS
✅ 全部清理后数量为0 PASS (expected=0, actual=0)
✅ 版本控制前缓存数量 PASS (expected=1, actual=1)
✅ 版本号递增 PASS
✅ 批量操作后版本继续递增 PASS

🧹 执行自动清理机制测试...
❌ 自动清理被触发 FAIL (condition is false)
✅ 缓存数量被控制 PASS
✅ 过期缓存被清理 PASS
✅ LRU清理控制缓存数量 PASS
❌ 禁用时不执行自动清理 FAIL (expected=0, actual=2, diff=2)
❌ 禁用时缓存数量不受限 FAIL (expected=5, actual=2, diff=3)

⚙️ 执行配置管理测试...
✅ maxCacheCount设置正确 PASS (expected=25, actual=25)
✅ autoCleanThreshold设置正确 PASS (expected=20, actual=20)
✅ maxCacheAge设置正确 PASS (expected=500, actual=500)
✅ autoCleanEnabled设置正确 PASS
✅ 无效配置被拒绝 PASS
✅ 无效配置被拒绝 PASS
✅ 无效配置被拒绝 PASS
✅ null配置不影响现有配置 PASS (object is not null)
✅ getConfig返回对象 PASS (object is not null)
✅ 包含maxCacheCount PASS
✅ 包含autoCleanThreshold PASS
✅ 包含maxCacheAge PASS
✅ 包含autoCleanEnabled PASS
✅ 返回配置副本 PASS

📊 执行统计信息测试...
✅ 总请求数正确 PASS (expected=3, actual=3)
✅ 缓存命中数正确 PASS (expected=1, actual=1)
✅ 缓存未命中数正确 PASS (expected=2, actual=2)
✅ 缓存创建数正确 PASS (expected=1, actual=1)
✅ 缓存更新数正确 PASS (expected=1, actual=1)
✅ 命中率计算正确 PASS
✅ getCachePoolDetails返回对象 PASS (object is not null)
✅ 包含caches详情 PASS
✅ 包含totalUnits PASS
✅ 包含avgUnitsPerCache PASS
✅ 当前缓存数量正确 PASS (expected=2, actual=2)
✅ 总单位数大于等于0 PASS
✅ 平均单位数合理 PASS
✅ 命中数统计准确 PASS (expected=1, actual=1)
✅ 未命中数统计准确 PASS (expected=2, actual=2)
✅ 总请求数统计准确 PASS (expected=3, actual=3)

🏥 执行健康检查和诊断测试...
✅ performHealthCheck返回对象 PASS (object is not null)
✅ 健康检查包含healthy属性 PASS
✅ 健康检查包含warnings数组 PASS
✅ 健康检查包含errors数组 PASS
✅ 健康检查包含recommendations数组 PASS
✅ 正常情况下健康 PASS
✅ 低命中率产生警告 PASS
❌ 低命中率有建议 FAIL (condition is false)
❌ 超过最大数量产生错误 FAIL (condition is false)
❌ 有错误时健康状态为false FAIL (condition is false)
✅ getOptimizationRecommendations返回数组 PASS
✅ 有足够统计数据时有建议 PASS
✅ getDetailedStatusReport返回字符串 PASS (object is not null)
✅ 报告不为空 PASS
✅ 报告包含性能统计 PASS
✅ 报告包含缓存状态 PASS
✅ 报告包含配置信息 PASS
✅ 报告包含缓存详情 PASS

⚡ 执行性能基准测试...
📊 缓存获取性能: 100次调用耗时 1ms
✅ 缓存获取性能达标 PASS
📊 缓存创建性能: 50次创建耗时 1ms
✅ 缓存创建性能合理 PASS
📊 大量操作测试: 50次操作耗时 1ms
✅ 大量操作性能合理 PASS
📊 内存使用测试: 10次循环耗时 2ms
✅ 内存使用测试合理 PASS

🔗 执行集成测试...
✅ 集成获取SortedUnitCache PASS (object is not null)
✅ SortedUnitCache功能正常 PASS
✅ 可以获取单位 PASS (object is not null)
✅ 按名称查找正常 PASS
✅ 版本号正确更新 PASS
✅ 移除后版本号继续更新 PASS
✅ 端到端流程-初始缓存 PASS (object is not null)
✅ 端到端流程-缓存命中 PASS
❌ 端到端流程-缓存更新 FAIL (condition is false)
✅ 端到端流程-请求统计 PASS (expected=3, actual=3)
✅ 端到端流程-命中统计 PASS (expected=1, actual=1)
✅ 端到端流程-创建统计 PASS (expected=1, actual=1)
✅ 端到端流程-更新统计 PASS (expected=1, actual=1)

🔍 执行边界条件测试...
✅ 空世界返回缓存 PASS (object is not null)
✅ 空世界缓存无单位 PASS (expected=0, actual=0)
✅ 负数间隔处理 PASS (object is not null)
✅ 极限场景-第一个缓存 PASS (expected=1, actual=1)
❌ 极限场景-缓存数量受限 FAIL (condition is false)
✅ 零间隔缓存 PASS (object is not null)

💾 执行内存管理和优化测试...
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 防止内存泄漏 PASS (expected=0, actual=0)
✅ 高效使用达到高命中率 PASS
✅ 缓存效率合理 PASS
❌ 低效使用产生优化建议 FAIL (condition is false)
✅ 健康检查发现问题 PASS

================================================================================
📊 测试结果汇总
================================================================================
总测试数: 125
通过: 116 ✅
失败: 9 ❌
成功率: 93%
总耗时: 22ms

⚡ 性能基准报告:
  cacheRetrieval: 0.01ms/次 (100次测试)
  cacheCreation: 0.02ms/次 (50次测试)
  massiveOperations: 0.02ms/次 (50次测试)
  memoryUsage: 0.2ms/次 (10次测试)

🎯 TargetCacheProvider当前状态:
=== TargetCacheProvider Status Report ===

Performance Stats:
  Total Requests: 30
  Cache Hit Rate: 0%
  Cache Hits: 0
  Cache Misses: 30
  Cache Creates: 1
  Cache Updates: 29
  Auto Cleans: 1

Cache Status:
  Active Caches: 0/1
  Total Units Cached: 0
  Avg Units/Cache: 0
  Oldest Cache: 0 frames
  Newest Cache: 0 frames

Configuration:
  Max Cache Count: 1
  Auto Clean Threshold: 1
  Max Cache Age: 1000 frames
  Auto Clean Enabled: true

Cache Details:


⚠️ 发现 9 个问题，请检查实现！
================================================================================
