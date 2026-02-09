
org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManagerTest.runAll();


================================================================================
⚔️  TargetCacheManager 外观层 - 终极战斗测试套件启动 ⚔️
================================================================================

🏗️ 初始化终极战场环境...
🎯 创建了 100 个测试单位
⚔️ 敌人数量: 50
🛡️ 友军数量: 50
🏰 战场环境构建完成

⚔️ 第一波：基础查询功能战斗测试...
✅ getCachedTargets-敌人返回数组 VICTORY (correct Array type)
✅ getCachedTargets-友军返回数组 VICTORY (correct Array type)
✅ getCachedTargets-全体返回数组 VICTORY (correct Array type)
✅ 敌人列表不为空 VICTORY
✅ 友军列表不为空 VICTORY
✅ 全体列表最大 VICTORY
✅ 第一个敌人确实是敌人 VICTORY
✅ 第一个友军确实是友军 VICTORY
✅ 简化敌人方法一致性 VICTORY (expected=50, actual=50)
✅ 简化友军方法一致性 VICTORY (expected=51, actual=51)
✅ 简化全体方法一致性 VICTORY (expected=101, actual=101)
✅ 缓存一致性-敌人 VICTORY (expected=50, actual=50)
✅ 缓存一致性-相同引用 VICTORY
✅ 缓存命中统计正确 VICTORY
✅ 更新间隔后重新获取缓存 VICTORY
✅ 更新后数据量保持 VICTORY (expected=50, actual=50)
  🧪 测试 acquireCache 缓存对象获取方法...
✅ acquireCache-敌人缓存对象不为空 VICTORY (object exists)
✅ acquireCache-友军缓存对象不为空 VICTORY (object exists)
✅ acquireCache-全体缓存对象不为空 VICTORY (object exists)
✅ 敌人缓存是SortedUnitCache实例 VICTORY (correct Object type)
✅ 敌人缓存有data属性 VICTORY
✅ 敌人缓存有getCount方法 VICTORY
✅ 敌人缓存有findNearest方法 VICTORY
✅ acquireEnemyCache返回缓存对象 VICTORY (object exists)
✅ acquireAllyCache返回缓存对象 VICTORY (object exists)
✅ acquireAllCache返回缓存对象 VICTORY (object exists)
✅ acquireEnemyCache返回相同引用 VICTORY
✅ acquireAllyCache返回相同引用 VICTORY
✅ acquireAllCache返回相同引用 VICTORY
✅ 缓存对象与Manager返回数据一致 VICTORY (expected=50, actual=50)
✅ 缓存对象与Manager返回相同数组引用 VICTORY
✅ 缓存对象findNearest与Manager一致 VICTORY
✅ 缓存对象计数与Manager一致 VICTORY (expected=50, actual=50)
✅ 缓存对象范围查询与Manager一致 VICTORY (expected=3, actual=3)
  ✅ acquireCache 方法测试全部通过

⚔️ 第二波：范围查询战斗测试...
✅ 敌人索引查询结果 VICTORY (object exists)
✅ 友军索引查询结果 VICTORY (object exists)
✅ 全体索引查询结果 VICTORY (object exists)
✅ 敌人索引查询包含data VICTORY
✅ 敌人索引查询包含startIndex VICTORY
✅ 敌人索引查询data是数组 VICTORY (correct Array type)
✅ 敌人索引查询startIndex是数字 VICTORY (correct Number type)
✅ 索引查询返回有效数据 VICTORY
✅ 小碰撞盒查询正常 VICTORY
✅ 大碰撞盒查询正常 VICTORY
✅ 大碰撞盒包含更多单位 VICTORY
✅ 范围查询一致性-数据长度 VICTORY (expected=51, actual=51)
✅ 范围查询一致性-开始索引 VICTORY (expected=24, actual=24)
✅ Monotonic equals baseline step=0 VICTORY (expected=24, actual=24)
✅ Monotonic equals baseline step=1 VICTORY (expected=25, actual=25)
✅ Monotonic non-decreasing step=1 VICTORY
✅ Monotonic equals baseline step=2 VICTORY (expected=26, actual=26)
✅ Monotonic non-decreasing step=2 VICTORY
✅ Monotonic equals baseline step=3 VICTORY (expected=27, actual=27)
✅ Monotonic non-decreasing step=3 VICTORY
✅ Monotonic equals baseline step=4 VICTORY (expected=27, actual=27)
✅ Monotonic non-decreasing step=4 VICTORY
✅ Monotonic equals baseline after new frame VICTORY (expected=21, actual=21)

⚔️ 第三波：距离查询战斗测试...
✅ 找到最近敌人 VICTORY (object exists)
✅ 找到最近友军 VICTORY (object exists)
✅ 找到最近全体单位 VICTORY (object exists)
✅ 最近敌人查找一致性 VICTORY
✅ 最近友军查找一致性 VICTORY
✅ 最近全体查找一致性 VICTORY
✅ 最近敌人确实是敌人 VICTORY
✅ 最近友军确实是友军 VICTORY
✅ 找到最远敌人 VICTORY (object exists)
✅ 找到最远友军 VICTORY (object exists)
✅ 最远敌人查找一致性 VICTORY
✅ 最远友军查找一致性 VICTORY
✅ 最远距离确实大于最近距离 VICTORY
✅ 单单位场景-找到单位 VICTORY (object exists)
enemy_0 vs enemy_0
✅ 单单位场景-最近和最远是同一个 VICTORY

⚔️ 第四波：区域搜索战斗测试...
✅ 范围敌人搜索返回数组 VICTORY (correct Array type)
✅ 范围友军搜索返回数组 VICTORY (correct Array type)
✅ 范围全体搜索返回数组 VICTORY (correct Array type)
✅ 简化范围敌人搜索一致 VICTORY (arrays match)
✅ 简化范围友军搜索一致 VICTORY (arrays match)
✅ 简化范围全体搜索一致 VICTORY (arrays match)
✅ 范围内敌人-0距离正确 VICTORY
✅ 范围内敌人-1距离正确 VICTORY
✅ 范围内敌人-2距离正确 VICTORY
✅ 范围内敌人-3距离正确 VICTORY
✅ 半径敌人搜索返回数组 VICTORY (correct Array type)
✅ 半径友军搜索返回数组 VICTORY (correct Array type)
✅ 简化半径敌人搜索一致 VICTORY (arrays match)
✅ 简化半径友军搜索一致 VICTORY (arrays match)
✅ 半径内敌人-0距离正确 VICTORY
✅ 半径内敌人-1距离正确 VICTORY
✅ 半径内敌人-2距离正确 VICTORY
✅ 半径内敌人-3距离正确 VICTORY
✅ 半径内敌人-4距离正确 VICTORY
✅ 半径内敌人-5距离正确 VICTORY
✅ 半径内敌人-6距离正确 VICTORY
✅ 限制范围最近敌人查找一致 VICTORY
✅ 限制范围内最近单位距离正确 VICTORY
✅ 区域搜索结果合理 VICTORY

⚔️ 第五波：计数API战斗测试...
✅ 敌人计数返回数字 VICTORY (correct Number type)
✅ 友军计数返回数字 VICTORY (correct Number type)
✅ 全体计数返回数字 VICTORY (correct Number type)
✅ 敌人数量合理 VICTORY
✅ 友军数量合理 VICTORY
✅ 全体数量最大 VICTORY
✅ 简化敌人计数一致 VICTORY (expected=50, actual=50)
✅ 简化友军计数一致 VICTORY (expected=51, actual=51)
✅ 简化全体计数一致 VICTORY (expected=101, actual=101)
✅ 计数与数组长度一致-敌人 VICTORY (expected=50, actual=50)
✅ 范围敌人计数返回数字 VICTORY (correct Number type)
✅ 范围友军计数返回数字 VICTORY (correct Number type)
✅ 范围敌人计数合理 VICTORY
✅ 范围友军计数合理 VICTORY
✅ 简化范围敌人计数一致 VICTORY (expected=3, actual=3)
✅ 简化范围友军计数一致 VICTORY (expected=4, actual=4)
✅ 范围计数与搜索结果一致 VICTORY (expected=3, actual=3)
✅ 半径敌人计数返回数字 VICTORY (correct Number type)
✅ 半径友军计数返回数字 VICTORY (correct Number type)
✅ 简化半径敌人计数一致 VICTORY (expected=5, actual=5)
✅ 简化半径友军计数一致 VICTORY (expected=6, actual=6)
✅ 半径计数与搜索结果一致 VICTORY (expected=5, actual=5)
✅ 排除自身计数逻辑正确 VICTORY

⚔️ 第六波：条件查询战斗测试...
✅ 低血量敌人计数返回数字 VICTORY (correct Number type)
✅ 中血量敌人计数返回数字 VICTORY (correct Number type)
✅ 高血量敌人计数返回数字 VICTORY (correct Number type)
✅ 血量条件计数合理 VICTORY
✅ 简化HP敌人计数一致 VICTORY (expected=0, actual=0)
✅ 简化HP友军计数返回数字 VICTORY (correct Number type)
✅ 敌人距离分布对象 VICTORY (object exists)
✅ 友军距离分布对象 VICTORY (object exists)
✅ 敌人分布包含totalCount VICTORY
✅ 敌人分布包含distribution VICTORY
✅ 敌人分布包含minDistance VICTORY
✅ 敌人分布包含maxDistance VICTORY
✅ 分布数组类型正确 VICTORY (correct Array type)
✅ 总数类型正确 VICTORY (correct Number type)
✅ 简化敌人分布总数一致 VICTORY (expected=50, actual=50)
✅ 简化友军分布总数一致 VICTORY (expected=51, actual=51)
✅ 血量分类覆盖合理 VICTORY
✅ 血量分类总和必须大于0 VICTORY
✅ 中英文HP条件结果一致(low/低血量) VICTORY (expected=0, actual=0)

⚔️ 第七波：系统管理战斗测试...
✅ 添加单位后数量增加 VICTORY
✅ 移除单位后数量恢复 VICTORY (expected=50, actual=50)
✅ 批量操作正常完成 VICTORY
✅ 部分清理后请求数增加 VICTORY
✅ 失效后可以重新创建缓存 VICTORY
✅ 特定失效操作正常完成 VICTORY
✅ 获取系统配置 VICTORY (object exists)
✅ 配置更新-容量 VICTORY (expected=75, actual=75)
✅ 配置更新-刷新阈值 VICTORY (expected=400, actual=400)
✅ 获取系统统计 VICTORY (object exists)
✅ 统计包含totalRequests VICTORY
✅ 统计包含cacheHits VICTORY
✅ 统计包含cacheMisses VICTORY
✅ 健康检查结果 VICTORY (object exists)
✅ 健康检查包含healthy VICTORY
✅ 健康检查包含warnings VICTORY
✅ 健康检查包含errors VICTORY
✅ 详细状态报告 VICTORY (object exists)
✅ 状态报告不为空 VICTORY
✅ 优化建议返回数组 VICTORY (correct Array type)

⚔️ 第八波：外观模式战斗验证...
✅ 简化API与复杂API结果一致 VICTORY
✅ 用户友好方法1-最近敌人 VICTORY (object exists)
✅ 用户友好方法2-敌人计数 VICTORY (correct Number type)
✅ findHero方法直观易用 VICTORY
✅ 委托统计-总请求数 VICTORY (expected=4, actual=4)
✅ 委托统计-缓存命中 VICTORY (expected=3, actual=3)
✅ 委托统计-缓存未命中 VICTORY (expected=1, actual=1)
✅ 委托配置-缓存容量 VICTORY (expected=100, actual=100)
✅ 委托配置-版本检查 VICTORY
✅ 接口一致性-敌人数组 VICTORY (correct Array type)
✅ 接口一致性-友军数组 VICTORY (correct Array type)
✅ 接口一致性-全体数组 VICTORY (correct Array type)
✅ 接口一致性-敌人计数 VICTORY (correct Number type)
✅ 接口一致性-友军计数 VICTORY (correct Number type)
✅ 接口一致性-全体计数 VICTORY (correct Number type)
✅ 向后兼容方法正常执行 VICTORY
✅ 短参数名兼容性-数组 VICTORY
✅ 短参数名兼容性-对象 VICTORY
✅ 短参数名兼容性-数字 VICTORY

⚔️ 第九波：性能基准战斗测试...
📊 基础查询性能: 1000次调用耗时 39ms
✅ 基础查询性能达标 VICTORY
📊 复杂查询性能: 1500次调用耗时 75ms
✅ 复杂查询性能合理 VICTORY
📊 外观层开销: Manager=385ms, Provider=381ms, 开销=1%
✅ 外观层开销合理 VICTORY
📊 大规模数据性能: 200次调用耗时 17ms
✅ 大规模数据性能合理 VICTORY

⚔️ 第十波：过滤器查询战斗测试...
✅ 基础过滤查询-无低血量敌人时返回null VICTORY (object is null)
✅ 简化过滤查询一致性 VICTORY
✅ 友军过滤查询-确实受伤 VICTORY
✅ 友军过滤查询-确实是友军 VICTORY
✅ 全体过滤查询-名称匹配 VICTORY
✅ 预定义过滤器-低血量敌人查询正常执行 VICTORY
✅ 预定义过滤器-受伤友军 VICTORY (object exists)
✅ 预定义过滤器-确实受伤 VICTORY
✅ 预定义过滤器-确实是友军 VICTORY
✅ 预定义过滤器-类型查询 VICTORY (object exists)
✅ 预定义过滤器-类型匹配 VICTORY
✅ 小范围过滤查询-距离确实很近 VICTORY
✅ 永不匹配过滤器返回null VICTORY (object is null)
✅ 永远匹配过滤器与直接查询一致 VICTORY
✅ null过滤器处理 VICTORY (object is null)
✅ 零searchLimit返回null VICTORY (object is null)
📊 过滤查询性能: 100次调用耗时 7ms
✅ 过滤查询性能合理 VICTORY
📊 复杂过滤查询性能: 50次调用耗时 2ms
✅ 复杂过滤查询性能合理 VICTORY
✅ 过滤查询与手动过滤一致性 VICTORY
✅ Manager与Cache过滤查询一致性 VICTORY

🔄 回退降级查询测试...
✅ 回退查询-过滤器成功时应返回结果 VICTORY (object exists)
✅ 回退查询-应与过滤器查询结果一致 VICTORY (expected=enemy_50, actual=enemy_50)
✅ 回退查询-过滤器失败时应回退到基础查询 VICTORY (object exists)
✅ 回退查询-应与基础查询结果一致 VICTORY (expected=enemy_50, actual=enemy_50)
✅ 通用敌人回退查询测试完成 VICTORY
✅ 通用友军回退查询测试完成 VICTORY
✅ 通用全体回退查询测试完成 VICTORY
✅ 低血量敌人回退查询应有结果 VICTORY (object exists)
✅ 回退到普通敌人查询 VICTORY (expected=enemy_50, actual=enemy_50)
✅ 受伤友军回退查询有合理结果 VICTORY
✅ 特定类型回退查询有合理结果 VICTORY
✅ 强化单位回退查询有合理结果 VICTORY
📊 回退查询性能 - 成功过滤: 0.05ms, 触发回退: 0.21ms
✅ 成功过滤性能合理 VICTORY
✅ 回退查询性能合理 VICTORY
✅ 边界情况测试完成 VICTORY

⚔️ 第十波：集成战斗测试...
✅ 工作流1-找到附近敌人 VICTORY
✅ 工作流2-选择最近目标 VICTORY (object exists)
✅ 工作流3-风险评估 VICTORY
✅ 工作流4-寻找支援 VICTORY
✅ 工作流5-战场概况 VICTORY (object exists)
✅ 工作流5-战场数据完整 VICTORY
✅ 完整工作流集成测试成功
✅ 跨组件集成-新单位被正确处理 VICTORY
✅ 跨组件集成-单位移除正确处理 VICTORY
📊 真实场景模拟: 10轮战斗耗时 4ms
✅ 真实场景性能合理 VICTORY
✅ 高压下系统统计正常 VICTORY (object exists)
✅ 高压下缓存命中率合理 VICTORY

⚔️ 终极波：大规模压力战斗测试...
✅ 大规模数据-总单位数正确 VICTORY
✅ 大规模数据-敌人计数合理 VICTORY
✅ 大规模数据-友军计数合理 VICTORY
✅ 大规模数据-处理时间合理 VICTORY
📊 大规模数据压力: 301个单位，处理耗时 23ms
📊 并发访问压力: 20次突发请求耗时 7ms
✅ 并发访问性能合理 VICTORY
✅ 高并发下系统健康 VICTORY
📊 内存压力测试: 20次循环耗时 40ms
✅ 内存压力测试完成 VICTORY
✅ 内存压力后系统恢复正常 VICTORY

⚔️ 最终波：边界条件战斗测试...
✅ 空世界-敌人数组长度 VICTORY (expected=0, actual=0)
✅ 空世界-友军数组长度 VICTORY (expected=0, actual=0)
✅ 空世界-最近敌人为null VICTORY (object is null)
✅ 空世界-敌人计数为0 VICTORY (expected=0, actual=0)
✅ null目标参数处理 VICTORY
✅ null类型参数处理 VICTORY
✅ 空字符串类型参数处理 VICTORY
✅ 零间隔处理 VICTORY (correct Array type)
✅ 负间隔处理 VICTORY (correct Array type)
✅ 极大间隔处理 VICTORY (correct Array type)
✅ 极值范围查询处理 VICTORY (correct Array type)
✅ 零半径查询处理 VICTORY (correct Array type)
✅ 极大半径查询处理 VICTORY (correct Array type)
✅ 缺失帧计时器错误恢复 VICTORY
✅ 无效世界对象错误恢复 VICTORY
✅ 错误后系统恢复正常 VICTORY

🧹 执行 clear() 别名 & rightMaxValues 集成测试...
✅ clear前缓存非空 VICTORY
✅ clear后缓存数量减少或归零 VICTORY
✅ getCachedEnemyFromIndex返回结果 VICTORY (object exists)
✅ 结果包含data VICTORY (object exists)

🔧 执行 Bug 修复回归测试...
✅ Provider返回null时仍有结果对象 VICTORY (object exists)
✅ _safeEmptyResult data长度为0 VICTORY (expected=0, actual=0)
✅ _safeEmptyResult startIndex为0 VICTORY (expected=0, actual=0)
✅ 污染后data长度为2 VICTORY
✅ 污染自愈后data长度为0 VICTORY (expected=0, actual=0)
✅ 污染自愈后startIndex为0 VICTORY (expected=0, actual=0)
✅ HP条件等价(低血量/low) VICTORY (expected=0, actual=0)
✅ HP条件等价(中血量/medium) VICTORY (expected=0, actual=0)
✅ HP条件等价(高血量/high) VICTORY (expected=0, actual=0)
✅ HP条件等价(濒死/critical) VICTORY (expected=0, actual=0)
✅ HP条件等价(受伤/injured) VICTORY (expected=0, actual=0)
✅ HP条件等价(满血/healthy) VICTORY (expected=0, actual=0)

================================================================================
🏆 TargetCacheManager 外观层战斗报告
================================================================================
⚔️ 总模拟数: 267
🏆 通过次数: 267 ✅
💥 失败次数: 0 ❌
🎯 胜通过: 100%
⏱️ 测试用时: 1068ms
📋 API覆盖数: 267 个方法

⚡ 测试报告:
  basicQueries: 0.039ms/次 (1000次测试)
  complexQueries: 0.05ms/次 (1500次测试)
  facadeOverhead: 开销 1% (10000次测试)
  largeScale: 0.085ms/次 (200次测试)
  filteredQuery: 0.07ms/次 (100次测试)
  complexFilteredQuery: 0.04ms/次 (50次测试)
  realWorldSimulation: 0.4ms/次 (10次测试)
  massiveDataStress: 301个单位，23ms
  concurrentAccess: 0.35ms/次 (20次突发)
  memoryStress: 2ms/次 (20次循环)

🎯 TargetCacheManager外观层当前状态:
=== TargetCacheProvider 状态报告 ===

性能统计:
  总请求次数: 23486
  缓存命中率: 99.75%
  缓存命中: 23427
  缓存未命中: 59
  缓存创建: 36
  缓存更新: 23


🎉🎊 完全通过！TargetCacheManager 外观层完美验收！ 🎊🎉
🏆 所有 267 项测试全部通过！
⚡ 性能表现优异，API设计完美！
🛡️ 外观模式实现卓越，用户体验极佳！
================================================================================
🏁 TargetCacheManager 终极测试完成！
================================================================================
