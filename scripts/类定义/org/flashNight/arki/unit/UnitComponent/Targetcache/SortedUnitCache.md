// 执行所有测试
org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCacheTest.runAll();


================================================================================
🚀 SortedUnitCache 完整测试套件启动
================================================================================

🔧 初始化测试数据...
📦 创建了 50 个测试单位

📋 执行基础功能测试...
✅ 空构造函数-数据长度 PASS (expected=0, actual=0)
✅ 空构造函数-isEmpty PASS
✅ 完整构造函数-数据长度 PASS (expected=5, actual=5)
✅ 完整构造函数-帧数 PASS (expected=999, actual=999)
✅ 空参数构造函数-数据长度 PASS (expected=0, actual=0)
✅ 空参数构造函数-帧数 PASS (expected=0, actual=0)
✅ getCount正确 PASS (expected=50, actual=50)
✅ 非空缓存isEmpty为false PASS
✅ 空缓存isEmpty为true PASS
✅ getUnitAt(0)返回对象 PASS (object is not null)
✅ getUnitAt(0)名称正确 PASS (expected="unit_0", actual="unit_0")
✅ getUnitAt(49)返回对象 PASS (object is not null)
✅ getUnitAt越界返回null PASS (object is null)
✅ getUnitAt负索引返回null PASS (object is null)
✅ findUnitByName找到单位 PASS (object is not null)
✅ findUnitByName名称匹配 PASS (expected="unit_5", actual="unit_5")
✅ findUnitByName找不到返回null PASS (object is null)
✅ toString返回字符串 PASS (object is not null)
✅ toString包含单位数量 PASS
✅ toString包含帧数 PASS

🔍 执行查询算法测试...
✅ getTargetsFromIndex返回结果 PASS (object is not null)
✅ 结果包含data PASS (object is not null)
✅ 结果包含startIndex PASS
✅ startIndex为有效数值 PASS
✅ 极小查询值startIndex为0 PASS (expected=0, actual=0)
✅ 极大查询值startIndex为数组长度 PASS (expected=50, actual=50)
✅ 空缓存startIndex为0 PASS (expected=0, actual=0)
✅ findNearest找到最近单位 PASS (object is not null)
✅ 最近单位不是目标自身 PASS
✅ 外部单位findNearest PASS (object is not null)
✅ 空缓存findNearest返回null PASS (object is null)
✅ 单元素缓存findNearest PASS (object is not null)
✅ 单元素缓存findFarthest(外部目标) PASS (object is not null)
✅ 单元素缓存findFarthest(自身目标) PASS (object is null)
✅ findFarthest找到最远单位 PASS (object is not null)
✅ 最远单位不是目标自身 PASS
✅ 首个单位findFarthest PASS (object is not null)
✅ 末尾单位findFarthest PASS (object is not null)
✅ 外部单位findFarthest PASS (object is not null)
✅ 空缓存findFarthest返回null PASS (object is null)
✅ 单元素缓存findFarthest(外部目标) PASS (object is not null)

📏 执行范围查询测试...
✅ findInRange返回数组 PASS (object is not null)
✅ 范围查询结果为数组 PASS
✅ 范围查询不包含目标自身 PASS
✅ 范围查询不包含目标自身 PASS
✅ 范围查询不包含目标自身 PASS
✅ 范围查询不包含目标自身 PASS
✅ 不排除自身结果更多 PASS
✅ 极小范围结果较少 PASS
✅ 极大范围包含大部分单位 PASS
✅ 空缓存范围查询长度为0 PASS (expected=0, actual=0)
✅ findInRadius返回数组 PASS (object is not null)
✅ findInRadius与findInRange结果一致 PASS (expected=9, actual=9)
✅ 大范围findNearestInRange PASS (object is not null)
✅ 零范围findNearestInRange返回null PASS (object is null)
✅ 大范围findFarthestInRange PASS (object is not null)
✅ 零范围findFarthestInRange返回null PASS (object is null)
✅ 范围计数为非负数 PASS
✅ 包含自身计数更大 PASS
✅ 计数与查询结果长度一致 PASS (expected=4, actual=4)
✅ 零范围计数为0 PASS (expected=0, actual=0)
✅ 半径计数与范围计数一致 PASS (expected=9, actual=9)

🎯 执行条件查询测试...
✅ critical血量计数 PASS
✅ low血量计数 PASS
✅ medium血量计数 PASS
✅ high血量计数 PASS
✅ healthy血量计数 PASS
✅ injured血量计数 PASS
✅ 无效条件返回0 PASS (expected=0, actual=0)
✅ 排除目标后计数减少 PASS
✅ findByHP返回数组 PASS (object is not null)
✅ critical单位数组长度正确 PASS
✅ critical单位血量正确 PASS
✅ low单位血量正确 PASS
✅ low单位血量正确 PASS
✅ medium单位血量正确 PASS
✅ 排除目标功能正常 PASS
✅ 距离分布返回对象 PASS (object is not null)
✅ 包含totalCount PASS
✅ 包含distribution数组 PASS
✅ 包含beyondCount PASS
✅ 包含minDistance PASS
✅ 包含maxDistance PASS
✅ totalCount为正数 PASS
✅ distribution为数组 PASS
✅ distribution长度正确 PASS (expected=3, actual=3)
✅ 默认距离区间分布 PASS (object is not null)
✅ 默认区间长度 PASS (expected=4, actual=4)
✅ 空缓存totalCount为0 PASS (expected=0, actual=0)
✅ 空缓存minDistance为-1 PASS (expected=-1, actual=-1)

🔍 执行边界条件测试...
✅ 空缓存数量 PASS (expected=0, actual=0)
✅ 空缓存isEmpty PASS
✅ 空缓存getUnitAt PASS (object is null)
✅ 空缓存findUnitByName PASS (object is null)
✅ 空缓存findNearest PASS (object is null)
✅ 空缓存findFarthest PASS (object is null)
✅ 空缓存范围查询长度 PASS (expected=0, actual=0)
✅ 空缓存范围计数 PASS (expected=0, actual=0)
✅ 单元素缓存数量 PASS (expected=1, actual=1)
✅ 单元素缓存非空 PASS
✅ 单元素缓存findUnitByName PASS (object is not null)
✅ 单元素缓存findNearest PASS (object is not null)
✅ 单元素缓存findFarthest(外部目标) PASS (object is not null)
✅ 单元素缓存findFarthest(自身目标) PASS (object is null)
✅ 重复位置findNearest PASS (object is not null)
✅ 重复位置范围计数 PASS
✅ 极值单位findNearest PASS (object is not null)
✅ 极值单位findFarthest PASS (object is not null)
✅ 极值血量计数 PASS

⚡ 执行性能基准测试...
📊 getTargetsFromIndex性能: 500次调用耗时 4ms
✅ getTargetsFromIndex性能达标 PASS
📊 findNearest性能: 500次调用耗时 2ms
✅ findNearest性能达标 PASS
📊 findFarthest性能: 500次调用耗时 2ms
✅ findFarthest性能达标 PASS
📊 findInRange性能: 500次调用耗时 7ms
✅ findInRange性能达标 PASS
📊 getCountInRange性能: 500次调用耗时 4ms
✅ getCountInRange性能达标 PASS
📊 getCountByHP性能: 500次调用耗时 23ms
✅ getCountByHP性能达标 PASS
📊 缓存优化测试: 100次相似查询耗时 1ms
✅ 缓存优化有效 PASS

💾 执行数据完整性测试...
✅ resetQueryCache执行成功 PASS
✅ updateData后数量正确 PASS (expected=10, actual=10)
✅ updateData后帧数正确 PASS (expected=2000, actual=2000)
✅ validateData返回对象 PASS (object is not null)
✅ 包含isValid属性 PASS
✅ 包含errors数组 PASS
✅ 包含warnings数组 PASS
✅ 正常数据验证通过 PASS
✅ 正常数据无错误 PASS (expected=0, actual=0)
✅ 损坏数据验证失败 PASS
✅ 损坏数据有错误 PASS
✅ getStatus返回对象 PASS (object is not null)
✅ 状态包含unitCount PASS
✅ 状态包含lastUpdatedFrame PASS
✅ 状态包含queryCache PASS
✅ 状态包含memoryUsage PASS
✅ 状态unitCount正确 PASS (expected=50, actual=50)
✅ getStatusReport返回字符串 PASS (object is not null)
✅ 报告包含单位信息 PASS
✅ 报告包含帧信息 PASS
✅ 报告包含验证信息 PASS

💪 执行压力测试...
✅ 大数据集findNearest PASS (object is not null)
✅ 大数据集findFarthest PASS (object is not null)
✅ 大数据集findInRange PASS (object is not null)
✅ 大数据集getCountInRange PASS
✅ 大数据集处理时间合理 PASS
💾 大数据集测试: 1000个单位，查询耗时 0ms
✅ 快速查询压力测试通过 PASS
⚡ 快速查询测试: 200次混合查询耗时 4ms
✅ 内存压力测试通过 PASS
🧠 内存使用测试: 20次缓存创建/销毁耗时 84ms
✅ 极端场景处理 PASS
🔥 极端场景测试: 3/3 通过

🧮 执行算法优化验证...
✅ 二分查找优化有效 PASS
🔍 二分查找测试: 100次查询耗时 2ms
🌡️ 缓存优化: 冷查询=0ms, 热查询平均=0ms
✅ 缓存优化效果(计时器下限) PASS
✅ 小数组线性扫描优化 PASS
📏 线性扫描测试: 100次小数组查询耗时 1ms

🔍 执行带过滤器的最近单位查询测试...
✅ 基础过滤查询返回结果 PASS (object is not null)
✅ 结果满足过滤条件 PASS
✅ 结果不是目标自身 PASS
✅ 快速路径返回结果 PASS (object is not null)
✅ 快速路径与findNearest结果一致 PASS (expected="unit_24", actual="unit_24")
✅ 过滤器恒为false时返回null PASS (object is null)
✅ searchLimit 性能回归守卫 PASS (expected=10, actual=10)
✅ 目标在缓存中查询返回结果 PASS (object is not null)
✅ 结果满足过滤条件 PASS
✅ 结果不是目标自身 PASS
✅ 外部目标左侧查询返回结果 PASS (object is not null)
✅ 返回左侧满足条件的单位 PASS (expected="unit_8", actual="unit_8")
✅ 外部目标右侧查询返回结果 PASS (object is not null)
✅ 返回右侧满足条件的单位 PASS (expected="unit_10", actual="unit_10")
✅ 等距情况返回结果 PASS (object is not null)
✅ 等距情况优先选择左侧 PASS (expected="unit_L", actual="unit_L")
✅ 大距离阈值能找到远处单位 PASS (object is not null)
✅ searchLimit限制时返回null PASS (object is null)
✅ 严格遵循searchLimit PASS (expected=15, actual=15)
✅ 空缓存返回null PASS (object is null)
✅ null过滤器返回null PASS (object is null)
✅ 零searchLimit返回null PASS (object is null)
✅ 负searchLimit返回null PASS (object is null)
✅ 单元素缓存满足条件 PASS (object is not null)
✅ 单元素缓存不满足条件 PASS (object is null)

================================================================================
📊 测试结果汇总
================================================================================
总测试数: 173
通过: 173 ✅
失败: 0 ❌
成功率: 100%
总耗时: 618ms

⚡ 性能基准报告:
  getTargetsFromIndex: 0.008ms/次 (500次测试)
  findNearest: 0.004ms/次 (500次测试)
  findFarthest: 0.004ms/次 (500次测试)
  findInRange: 0.014ms/次 (500次测试)
  getCountInRange: 0.008ms/次 (500次测试)
  getCountByHP: 0.046ms/次 (500次测试)

🎯 缓存当前状态:
=== SortedUnitCache Status ===
Units: 50
Last Updated: Frame 1000
Query Cache: Left=254, Index=12
Validation: PASSED


🎉 所有测试通过！SortedUnitCache 组件质量优秀！
================================================================================
