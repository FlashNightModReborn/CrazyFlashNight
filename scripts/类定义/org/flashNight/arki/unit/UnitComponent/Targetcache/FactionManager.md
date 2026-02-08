org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManagerTest.runAll();

================================================================================
🚀 FactionManager 完整测试套件启动
================================================================================

📋 执行基础功能测试...
✅ getAllFactions返回数组 PASS (object is not null)
✅ 默认阵营数量正确 PASS
✅ getStatus返回对象 PASS (object is not null)
✅ 初始化标志正确 PASS
✅ 阵营数量统计正确 PASS (expected="3", actual="3")
✅ FACTION_PLAYER常量 PASS (object is not null)
✅ FACTION_ENEMY常量 PASS (object is not null)
✅ FACTION_HOSTILE_NEUTRAL常量 PASS (object is not null)
✅ 玩家阵营常量值 PASS (expected="PLAYER", actual="PLAYER")
✅ 敌人阵营常量值 PASS (expected="ENEMY", actual="ENEMY")
✅ 中立敌对常量值 PASS (expected="HOSTILE_NEUTRAL", actual="HOSTILE_NEUTRAL")
✅ RELATION_ALLY常量 PASS (object is not null)
✅ RELATION_ENEMY常量 PASS (object is not null)
✅ RELATION_NEUTRAL常量 PASS (object is not null)
✅ RELATION_SELF常量 PASS (object is not null)
✅ 盟友关系常量值 PASS (expected="ALLY", actual="ALLY")
✅ 敌对关系常量值 PASS (expected="ENEMY", actual="ENEMY")
✅ 中立关系常量值 PASS (expected="NEUTRAL", actual="NEUTRAL")
✅ 自身关系常量值 PASS (expected="SELF", actual="SELF")

📝 执行阵营注册测试...
✅ 新阵营注册成功 PASS
✅ 新阵营在列表中 PASS (array contains "TEST_FACTION")
FactionManager: 无效的阵营ID
✅ 空阵营ID注册失败 PASS
FactionManager: 无效的阵营ID
✅ null阵营ID注册失败 PASS
✅ 获取阵营元数据 PASS (object is not null)
✅ 元数据名称正确 PASS (expected="测试阵营", actual="测试阵营")
✅ 元数据描述正确 PASS (expected="用于测试的阵营", actual="用于测试的阵营")
✅ 不存在阵营返回空对象 PASS (object is not null)
✅ 玩家阵营元数据 PASS (object is not null)
✅ 玩家阵营legacy值 PASS (expected="false", actual="false")
✅ 敌人阵营元数据 PASS (object is not null)
✅ 敌人阵营legacy值 PASS (expected="true", actual="true")
✅ 中立敌对阵营元数据 PASS (object is not null)
✅ 中立敌对legacy值 PASS (expected="null", actual="null")

🤝 执行关系管理测试...
✅ 设置关系成功 PASS
✅ 关系设置正确 PASS (expected="ALLY", actual="ALLY")
FactionManager: 无效的阵营ID - INVALID_FACTION 或 PLAYER
✅ 无效阵营关系设置失败 PASS
FactionManager: 无效的关系状态 - INVALID_RELATION
✅ 无效关系状态设置失败 PASS
✅ 自身关系查询 PASS (expected="SELF", actual="SELF")
✅ 未定义关系默认中立 PASS (expected="NEUTRAL", actual="NEUTRAL")
✅ 矩阵验证结果 PASS (object is not null)
✅ 验证结果包含isValid PASS
✅ 验证结果包含errors PASS
✅ 验证结果包含warnings PASS

⚔️ 执行三阵营系统测试...
✅ 玩家vs玩家-盟友 PASS
✅ 玩家vs敌人-敌对 PASS
✅ 玩家vs中立敌对-敌对 PASS
✅ 敌人vs玩家-敌对 PASS
✅ 敌人vs敌人-盟友 PASS
✅ 敌人vs中立敌对-敌对 PASS
✅ 中立敌对vs玩家-敌对 PASS
✅ 中立敌对vs敌人-敌对 PASS
✅ 中立敌对vs中立敌对-盟友 PASS
✅ 玩家vs敌人-非盟友 PASS
✅ 玩家vs敌人-非中立 PASS
✅ 测试阵营vs玩家-中立 PASS
✅ 玩家的敌人包含敌人阵营 PASS (array contains "ENEMY")
✅ 玩家的敌人包含中立敌对 PASS (array contains "HOSTILE_NEUTRAL")
✅ 玩家的盟友包含自身 PASS (array contains "PLAYER")

🔄 执行适配器功能测试...
✅ 玩家单位阵营映射 PASS (expected="PLAYER", actual="PLAYER")
✅ 敌人单位阵营映射 PASS (expected="ENEMY", actual="ENEMY")
✅ 中立单位阵营映射 PASS (expected="HOSTILE_NEUTRAL", actual="HOSTILE_NEUTRAL")
✅ 未定义单位阵营映射 PASS (expected="HOSTILE_NEUTRAL", actual="HOSTILE_NEUTRAL")
✅ null单位阵营映射 PASS (expected="HOSTILE_NEUTRAL", actual="HOSTILE_NEUTRAL")
✅ 玩家阵营legacy值 PASS (expected="false", actual="false")
✅ 敌人阵营legacy值 PASS (expected="true", actual="true")
✅ 中立敌对legacy值 PASS (expected="null", actual="null")
✅ 玩家vs敌人-敌对 PASS
✅ 玩家vs中立-敌对 PASS
✅ 敌人vs中立-敌对 PASS
✅ 玩家vs玩家-盟友 PASS
✅ 敌人vs敌人-盟友 PASS
✅ 玩家vs敌人-非盟友 PASS
  测试 getFactionLegacyValue 方法...
✅ getFactionLegacyValue-玩家 PASS (expected="false", actual="false")
✅ getFactionLegacyValue-敌人 PASS (expected="true", actual="true")
✅ getFactionLegacyValue-中立敌对 PASS (expected="null", actual="null")
✅ getFactionLegacyValue-无效阵营 PASS (expected="null", actual="null")
✅ getFactionLegacyValue-null输入 PASS (expected="null", actual="null")
✅ getFactionLegacyValue-空字符串 PASS (expected="null", actual="null")
  测试 createFactionUnit 方法...
✅ createFactionUnit-玩家单位创建 PASS (object is not null)
✅ createFactionUnit-玩家单位名称 PASS (expected="test_PLAYER", actual="test_PLAYER")
✅ createFactionUnit-玩家单位是否为敌人 PASS (expected="false", actual="false")
✅ createFactionUnit-玩家单位阵营 PASS (expected="PLAYER", actual="PLAYER")
✅ createFactionUnit-敌人单位创建 PASS (object is not null)
✅ createFactionUnit-敌人单位名称 PASS (expected="queue_ENEMY", actual="queue_ENEMY")
✅ createFactionUnit-敌人单位是否为敌人 PASS (expected="true", actual="true")
✅ createFactionUnit-敌人单位阵营 PASS (expected="ENEMY", actual="ENEMY")
✅ createFactionUnit-中立单位创建 PASS (object is not null)
✅ createFactionUnit-中立单位名称前缀 PASS (expected="faction_unit_", actual="faction_unit_")
✅ createFactionUnit-中立单位是否为敌人 PASS (expected="null", actual="null")
✅ createFactionUnit-中立单位阵营 PASS (expected="HOSTILE_NEUTRAL", actual="HOSTILE_NEUTRAL")
✅ createFactionUnit-反向映射验证 PASS (expected="PLAYER", actual="PLAYER")
✅ createFactionUnit-单位关系查询 PASS
✅ createFactionUnit-单位盟友查询 PASS

🎯 执行缓存集成测试...
✅ 玩家查询敌人-包含敌人单位 PASS
✅ 玩家查询敌人-包含中立单位 PASS
✅ 玩家查询敌人-不包含玩家单位 PASS
✅ 玩家查询友军-包含玩家单位 PASS
✅ 玩家查询友军-不包含敌人单位 PASS
✅ 玩家查询友军-不包含中立单位 PASS
✅ 玩家单位缓存键后缀 PASS (expected="PLAYER", actual="PLAYER")
✅ 敌人单位缓存键后缀 PASS (expected="ENEMY", actual="ENEMY")
✅ 中立单位缓存键后缀 PASS (expected="HOSTILE_NEUTRAL", actual="HOSTILE_NEUTRAL")

🚀 执行高级功能测试...
✅ 批量关系设置成功数 PASS (expected="2", actual="2")
✅ 批量设置关系1 PASS (expected="ALLY", actual="ALLY")
✅ 批量设置关系2 PASS (expected="NEUTRAL", actual="NEUTRAL")
✅ 关系矩阵快照 PASS (object is not null)
✅ 矩阵加载成功 PASS
✅ 无效矩阵加载失败 PASS
✅ 关系报告生成 PASS (object is not null)
✅ 报告包含阵营信息 PASS
✅ 报告包含关系矩阵 PASS
✅ 状态信息获取 PASS (object is not null)
✅ 状态包含初始化标志 PASS
✅ 状态包含阵营数量 PASS

⚡ 执行性能基准测试...
📊 关系查询性能: 10000次查询耗时 45ms (平均 4.5μs/次)
✅ 关系查询性能达标 PASS
📊 适配器方法性能: 10000次调用耗时 28ms (平均 2.8μs/次)
✅ 适配器方法性能达标 PASS
📊 性能对比: 新方法=51ms, 传统方法=2ms, 开销=2550%
✅ 相对性能开销可接受 PASS

🔍 执行边界条件测试...
✅ 无效阵营关系查询 PASS
✅ 无效阵营关系默认中立 PASS (expected="NEUTRAL", actual="NEUTRAL")
✅ 无效阵营敌人列表为空 PASS
✅ null单位阵营映射 PASS (expected="HOSTILE_NEUTRAL", actual="HOSTILE_NEUTRAL")
✅ 单一阵营仍有敌人 PASS
✅ 自身关系为盟友 PASS
✅ 自身关系状态 PASS (expected="SELF", actual="SELF")
✅ 矩阵恢复成功 PASS
✅ 恢复后功能正常 PASS

⬅️ 执行向后兼容性测试...
✅ 单位0阵营映射 PASS (object is not null)
✅ 单位1阵营映射 PASS (object is not null)
✅ 单位2阵营映射 PASS (object is not null)
✅ 单位3阵营映射 PASS (object is not null)
✅ 单位4阵营映射 PASS (object is not null)
✅ 单位5阵营映射 PASS (object is not null)
✅ 新旧系统敌对判断一致 PASS (expected="true", actual="true")
✅ 玩家vs中立敌对-敌对 PASS
✅ 敌人vs中立敌对-敌对 PASS

🔗 执行 Ref 引用方法测试...
✅ getEnemyFactionsRef('PLAYER')非null PASS (object is not null)
✅ getEnemyFactionsRef('PLAYER')长度一致 PASS (expected="2", actual="2")
✅ getEnemyFactionsRef('PLAYER')元素一致 PASS
✅ getEnemyFactionsRef('ENEMY')非null PASS (object is not null)
✅ getEnemyFactionsRef('ENEMY')长度一致 PASS (expected="2", actual="2")
✅ getEnemyFactionsRef('ENEMY')元素一致 PASS
✅ getEnemyFactionsRef('HOSTILE_NEUTRAL')非null PASS (object is not null)
✅ getEnemyFactionsRef('HOSTILE_NEUTRAL')长度一致 PASS (expected="2", actual="2")
✅ getEnemyFactionsRef('HOSTILE_NEUTRAL')元素一致 PASS
✅ getAllyFactionsRef('PLAYER')非null PASS (object is not null)
✅ getAllyFactionsRef('PLAYER')长度一致 PASS (expected="1", actual="1")
✅ getAllyFactionsRef('PLAYER')元素一致 PASS
✅ getAllyFactionsRef('ENEMY')非null PASS (object is not null)
✅ getAllyFactionsRef('ENEMY')长度一致 PASS (expected="1", actual="1")
✅ getAllyFactionsRef('ENEMY')元素一致 PASS
✅ getAllyFactionsRef('HOSTILE_NEUTRAL')非null PASS (object is not null)
✅ getAllyFactionsRef('HOSTILE_NEUTRAL')长度一致 PASS (expected="1", actual="1")
✅ getAllyFactionsRef('HOSTILE_NEUTRAL')元素一致 PASS
✅ getEnemyFactionsRef无效阵营返回null PASS
✅ getAllyFactionsRef无效阵营返回null PASS
✅ getEnemyFactionsRef返回同一引用 PASS
✅ getAllyFactionsRef返回同一引用 PASS

================================================================================
📊 测试结果汇总
================================================================================
总测试数: 157
通过: 157 ✅
失败: 0 ❌
成功率: 100%
总耗时: 131ms

📌 新增方法测试覆盖:
  ✅ getFactionLegacyValue - 阵营到布尔值映射
  ✅ createFactionUnit - 假单位创建工具

⚡ 性能基准报告:
  relationshipQueries: 4.5μs/次 (10000次测试)
  adapterMethods: 2.8μs/次 (10000次测试)
  vsLegacyComparison: 开销 2550% (10000次对比)

🎯 FactionManager当前状态:
=== FactionManager 关系报告 ===

已注册阵营 (4 个):
  PLAYER: 玩家阵营
  ENEMY: 敌对阵营
  HOSTILE_NEUTRAL: 中立敌对
  TEST_FACTION: 测试阵营

关系矩阵:
From\To	PLAYER	ENEMY	HOSTILE_	TEST_FAC	
PLAYER	SELF		ENEM		ENEM		NEUT		
ENEMY	ENEM		SELF		ENEM		NEUT		
HOSTILE_	ENEM		ENEM		SELF		NEUT		
TEST_FAC	NEUT		ALLY		NEUT		SELF		

缓存状态: 有效

🎉 所有测试通过！FactionManager 组件质量优秀！
✅ 三阵营系统正常工作
✅ 向后兼容性完美
✅ 性能开销可接受
✅ 为未来扩展做好准备
================================================================================
