// 执行所有测试
org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizerTest.runAll();

================================================================================
🚀 AdaptiveThresholdOptimizer 完整测试套件启动
================================================================================

📋 执行核心功能测试...
✅ 初始阈值在合理范围 PASS (value=100 in range [30, 300])
✅ 初始化参数完整性 PASS
✅ Alpha自动修正 PASS
✅ DensityFactor自动修正 PASS
✅ MinThreshold自动修正 PASS
✅ MaxThreshold自动修正 PASS
✅ 均匀分布阈值更新 PASS
✅ 聚集分布阈值更新 PASS
✅ 稀疏分布阈值更新 PASS
✅ 极小数据边界限制 PASS (value=30 in range [30, 300])
✅ 极大数据边界限制 PASS (value=300 in range [30, 300])
✅ getThreshold返回有效值 PASS
✅ getAvgDensity返回有效值 PASS
✅ getParams返回对象 PASS (object is not null)
✅ params包含必要属性 PASS

🔍 执行边界条件测试...
✅ 空数组保持阈值不变 PASS (expected=222.432, actual=222.432)
✅ 单元素数组保持阈值不变 PASS (expected=222.432, actual=222.432)
✅ 空数组推荐阈值 PASS (expected=222.432, actual=222.432)
✅ 单元素推荐阈值 PASS (expected=222.432, actual=222.432)
✅ 重复值保持阈值不变 PASS (expected=222.432, actual=222.432)
✅ 部分重复值正常处理 PASS
✅ 极大值结果在边界内 PASS (value=300 in range [30, 300])
✅ 负值处理 PASS
✅ NaN参数自动修正 PASS

⚙️ 执行参数配置测试...
✅ 有效参数设置成功 PASS
✅ Alpha设置正确 PASS (expected=0.5, actual=0.5)
✅ DensityFactor设置正确 PASS (expected=2.5, actual=2.5)
✅ MinThreshold设置正确 PASS (expected=20, actual=20)
✅ MaxThreshold设置正确 PASS (expected=200, actual=200)
✅ 无效参数被正确拒绝或修正 PASS
✅ Alpha单独设置 PASS
✅ Alpha值正确 PASS (expected=0.3, actual=0.3)
✅ DensityFactor单独设置 PASS
✅ DensityFactor值正确 PASS (expected=4, actual=4)
✅ MinThreshold单独设置 PASS
✅ MinThreshold值正确 PASS (expected=25, actual=25)
✅ MaxThreshold单独设置 PASS
✅ MaxThreshold值正确 PASS (expected=350, actual=350)
✅ 无效参数名被拒绝 PASS
✅ 预设[dense]应用成功 PASS
✅ 预设[dense]参数有效 PASS
✅ 预设[sparse]应用成功 PASS
✅ 预设[sparse]参数有效 PASS
✅ 预设[dynamic]应用成功 PASS
✅ 预设[dynamic]参数有效 PASS
✅ 预设[stable]应用成功 PASS
✅ 预设[stable]参数有效 PASS
✅ 预设[default]应用成功 PASS
✅ 预设[default]参数有效 PASS
✅ 无效预设被拒绝 PASS
✅ 边界测试0参数有效 PASS
✅ 边界测试1参数有效 PASS
✅ 边界测试2参数有效 PASS

💾 执行状态管理测试...
✅ 重置后Alpha PASS (expected=0.2, actual=0.2)
✅ 重置后DensityFactor PASS (expected=3, actual=3)
✅ 重置后MinThreshold PASS (expected=30, actual=30)
✅ 重置后MaxThreshold PASS (expected=300, actual=300)
✅ 重置后阈值 PASS (expected=100, actual=100)
✅ 重置后平均密度 PASS (expected=100, actual=100)
✅ 自定义平均密度设置 PASS (expected=250, actual=250)
✅ 默认平均密度重置 PASS (expected=100, actual=100)
✅ 无效值重置为默认 PASS (expected=100, actual=100)
✅ 状态对象非空 PASS (object is not null)
✅ 状态包含currentThreshold PASS
✅ 状态包含avgDensity PASS
✅ 状态包含params PASS
✅ 状态包含version PASS
✅ 状态值有效 PASS
✅ 状态报告非空 PASS (object is not null)
✅ 报告包含阈值信息 PASS
✅ 报告包含密度信息 PASS
✅ 报告包含Alpha信息 PASS
✅ 报告包含边界信息 PASS

🔧 执行工具方法测试...
✅ 推荐阈值确定性 PASS (expected=150, actual=150)
✅ 均匀分布推荐阈值 PASS
✅ 稀疏分布推荐阈值 PASS
✅ 分析结果非空 PASS (object is not null)
✅ 包含currentThreshold PASS
✅ 包含recommendedThreshold PASS
✅ 包含difference PASS
✅ 包含differencePercent PASS
✅ 包含suggestion PASS
✅ 包含efficiency PASS
✅ 差异百分比非负 PASS
✅ 当前阈值正数 PASS
✅ 推荐阈值正数 PASS
✅ 建议字符串有效 PASS
✅ 效率评估有效 PASS

⚡ 执行性能基准测试...
📊 updateThreshold性能: 1000次调用耗时 47ms (平均 0.047ms/次)
✅ updateThreshold性能达标 PASS
📊 calculateRecommendedThreshold性能: 2000次调用耗时 48ms (平均 0.024ms/次)
✅ calculateRecommended性能达标 PASS
📊 参数操作性能: 5000次操作耗时 142ms (平均 0.028ms/次)
✅ 参数操作性能达标 PASS
📊 analyzeDistribution性能: 1000次调用耗时 36ms (平均 0.036ms/次)
✅ analyzeDistribution性能达标 PASS

🎯 执行效果评估测试...
✅ 阈值适应密集/稀疏分布 PASS
📈 适应性测试: 密集分布阈值=243, 稀疏分布阈值=300
📋 预设[dense]效果评估: 差异=84%, 效率=Poor
✅ 预设[dense]差异在可接受范围 PASS
✅ 预设[dense]产生有效阈值 PASS
📋 预设[sparse]效果评估: 差异=0%, 效率=Excellent
✅ 预设[sparse]差异在可接受范围 PASS
✅ 预设[sparse]产生有效阈值 PASS
📋 预设[dynamic]效果评估: 差异=17%, 效率=Good
✅ 预设[dynamic]差异在可接受范围 PASS
✅ 预设[dynamic]产生有效阈值 PASS
✅ 边界约束有效 PASS (value=50 in range [10, 50])
🔒 边界约束测试: 极端数据下阈值=50 (边界[10,50])
✅ 阈值趋向收敛 PASS
📉 收敛性测试: 早期变化=19, 后期变化=4

💪 执行压力测试...
✅ 大数据集处理成功 PASS
✅ 大数据集处理时间合理 PASS
💾 大数据集测试: 500个元素处理耗时 1ms
✅ 快速更新压力测试通过 PASS
⚡ 快速更新测试: 100次更新耗时 8ms
✅ 极端情况处理 PASS
🔥 极端情况测试: 5/5 通过
✅ 内存压力测试通过 PASS
🧠 内存使用测试: 50次大数组操作耗时 23ms

================================================================================
📊 测试结果汇总
================================================================================
总测试数: 106
通过: 106 ✅
失败: 0 ❌
成功率: 100%
总耗时: 310ms

⚡ 性能基准报告:
  updateThreshold: 0.047ms/次 (1000次测试)
  calculateRecommendedThreshold: 0.024ms/次 (2000次测试)
  parameterOperations: 0.028ms/次 (5000次测试)
  analyzeDistribution: 0.036ms/次 (1000次测试)

🎯 优化器当前状态:
AdaptiveThresholdOptimizer Status:
  Current Threshold: 30px
  Avg Density: 5px
  Alpha: 0.2
  Density Factor: 3
  Bounds: [30, 300]

🎉 所有测试通过！AdaptiveThresholdOptimizer 组件质量优秀！
================================================================================
