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
✅ 失效后缓存被清空 PASS (expected=0, actual=0)
✅ 失效后重新创建缓存 PASS (object is not null)
✅ 失效后重新更新 PASS
✅ 特定类型失效有效 PASS
✅ 清理前有多个缓存 PASS
✅ 部分清理后数量减少 PASS
✅ 全部清理后数量为0 PASS (expected=0, actual=0)
✅ 版本控制前缓存数量 PASS (expected=1, actual=1)
✅ 版本号递增 PASS
✅ 批量操作后版本继续递增 PASS

🧹 执行缓存容量 & LRU淘汰测试（Object Map 版）...
✅ LRU淘汰控制缓存数量<=5 PASS
✅ 分布详情接口可用 PASS (object is not null)
✅ 容量设置正确 PASS (expected=5, actual=5)
✅ 缓存项总数<=容量 PASS
✅ 填满时缓存数=3 PASS (expected=3, actual=3)
✅ 淘汰后缓存数<=3 PASS
✅ 分布接口返回对象 PASS (object is not null)
✅ totalItems>0 PASS
✅ 缓存项目不超过容量 PASS
✅ 强制刷新阈值生效 PASS
✅ 强制刷新统计递增 PASS
✅ 首次超阈值触发强制刷新 PASS
✅ 强制刷新后帧数更新 PASS
✅ 阈值内不应触发强制刷新 PASS (expected=0, actual=0)
✅ 再次超阈值应触发强制刷新 PASS
✅ 版本检查后缓存可用 PASS (object is not null)
✅ 版本检查可以禁用 PASS

⚙️ 执行配置管理测试...
✅ maxCacheCapacity设置正确 PASS (expected=80, actual=80)
✅ forceRefreshThreshold设置正确 PASS (expected=300, actual=300)
✅ versionCheckEnabled设置正确 PASS
✅ detailedStatsEnabled设置正确 PASS
✅ 无效maxCacheCapacity被拒绝 PASS
✅ 无效forceRefreshThreshold被拒绝 PASS
✅ null配置不影响现有配置 PASS (object is not null)
✅ 部分配置更新成功 PASS
✅ getConfig返回对象 PASS (object is not null)
✅ 包含maxCacheCapacity PASS
✅ 包含forceRefreshThreshold PASS
✅ 包含versionCheckEnabled PASS
✅ 包含detailedStatsEnabled PASS
✅ 返回配置副本 PASS
✅ reinitialize执行成功 PASS
✅ 重新初始化后容量更新 PASS (expected=150, actual=150)
✅ 重新初始化后缓存清空 PASS (expected=0, actual=0)
✅ 无参数重新初始化保持容量 PASS (expected=150, actual=150)

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
✅ 缓存健康检查通过 PASS
✅ 正常情况下无错误 PASS
✅ 低命中率产生警告 PASS
✅ 低命中率有建议 PASS
✅ 频繁版本变化可能产生警告 PASS
✅ getOptimizationRecommendations返回数组 PASS
✅ 有足够统计数据时有建议 PASS
✅ 小容量配置可能产生建议 PASS
✅ 大容量配置可能产生建议 PASS
✅ getDetailedStatusReport返回字符串 PASS (object is not null)
✅ 报告不为空 PASS
✅ 报告包含性能统计 PASS
✅ 报告包含缓存池状态 PASS
✅ 报告包含配置信息 PASS
✅ 报告包含数据一致性 PASS
✅ getCacheDistribution返回对象 PASS (object is not null)
✅ 包含容量信息 PASS
✅ 包含总缓存项目 PASS
✅ 总缓存项目计算正确 PASS (expected=2, actual=2)
✅ 缓存项目不超过容量 PASS

⚡ 执行性能基准测试...
📊 缓存获取性能: 100次调用耗时 3ms
✅ 缓存获取性能达标 PASS
📊 缓存创建性能: 50次创建耗时 4ms
✅ 缓存创建性能合理 PASS
📊 大量操作测试: 50次操作耗时 5ms
✅ 大量操作性能合理 PASS
📊 内存使用测试: 10次循环耗时 14ms
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
✅ 端到端流程-缓存更新 PASS
✅ 端到端流程-请求统计 PASS (expected=3, actual=3)
✅ 端到端流程-命中统计 PASS (expected=1, actual=1)
✅ 端到端流程-创建统计 PASS (expected=1, actual=1)
✅ 端到端流程-更新统计 PASS (expected=1, actual=1)

🔍 执行边界条件测试...
✅ 空世界返回缓存 PASS (object is not null)
✅ 空世界缓存无单位 PASS (expected=0, actual=0)
✅ null目标处理不崩溃 PASS
✅ 空请求类型处理不崩溃 PASS
✅ 负数间隔处理 PASS (object is not null)
✅ 极大间隔处理 PASS (object is not null)
✅ 极限场景-第一个缓存 PASS (expected=1, actual=1)
✅ 极限场景-LRU控制缓存数量 PASS
✅ 零间隔缓存 PASS (object is not null)
✅ 极大容量配置不崩溃 PASS
✅ 容量0被正确处理 PASS
✅ 极端强制刷新阈值生效 PASS
✅ 频繁版本变化后缓存仍可用 PASS (object is not null)
✅ 缺少帧计时器时优雅处理 PASS
✅ 缺少游戏世界时优雅处理 PASS
✅ 无效_root时优雅处理 PASS
✅ 负容量重新初始化处理 PASS
✅ 异常情况下健康检查仍可用 PASS (object is not null)

💾 执行内存管理和优化测试...
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 清理后缓存为空 PASS (expected=0, actual=0)
✅ 防止内存泄漏 PASS (expected=0, actual=0)
✅ 高效使用达到高命中率 PASS
✅ 缓存效率合理 PASS
✅ 低效使用产生优化建议 PASS
✅ 健康检查发现问题 PASS

================================================================================
📊 测试结果汇总
================================================================================
总测试数: 161
通过: 161 ✅
失败: 0 ❌
成功率: 100%
总耗时: 90ms

⚡ 性能基准报告:
  cacheRetrieval: 0.03ms/次 (100次测试)
  cacheCreation: 0.08ms/次 (50次测试)
  massiveOperations: 0.1ms/次 (50次测试)
  memoryUsage: 1.4ms/次 (10次测试)

🎯 TargetCacheProvider 当前状态:
=== TargetCacheProvider 状态报告 ===

性能统计:
  总请求次数: 30
  缓存命中率: 0%
  缓存命中: 0
  缓存未命中: 30
  缓存创建: 1
  缓存更新: 29
  平均访问时间: 0.07ms
  最大访问时间: 1ms

缓存池状态:
  活跃缓存数: 0
  总缓存单位: 0
  平均单位/缓存: 0
  最老缓存年龄: 0 帧
  最新缓存年龄: 0 帧

阵营分布:

缓存分布:
  容量上限: 10
  冷缓存(访问<2): 0 项
  热缓存(访问>=2): 0 项
  总缓存项目: 0
  冷热比例: 0% : 0%

数据一致性:
  版本不匹配: 0
  强制刷新: 0

配置信息:
  缓存容量: 10
  强制刷新阈值: 10000 帧
  版本检查启用: true
  详细统计启用: true

FactionManager集成:
  状态: 已集成
  注册阵营数: 3
  阵营列表: PLAYER, ENEMY, HOSTILE_NEUTRAL

缓存详情:


🎉 所有测试通过！TargetCacheProvider 组件质量优秀！
================================================================================
