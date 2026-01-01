org.flashNight.arki.component.Shield.AdaptiveShieldTestSuite.runAllTests();



========================================
    AdaptiveShield 测试套件 v1.0
========================================

【1. 构造函数测试】
✓ 默认值测试通过
✓ 自定义值测试通过
✓ 初始模式测试通过
构造函数 所有测试通过！
【2. 单盾模式测试】
✓ 单盾伤害吸收测试通过
✓ 单盾强度限制测试通过
✓ 单盾充能测试通过
✓ 单盾衰减测试通过
✓ 单盾持续时间测试通过
单盾模式 所有测试通过！
【3. 工厂方法测试】
✓ createTemporary测试通过
✓ createRechargeable测试通过
✓ createDecaying测试通过
✓ createResistant测试通过
工厂方法 所有测试通过！
【4. 模式升级测试】
✓ 添加护盾触发升级测试通过
✓ 状态保持测试通过
✓ 多层护盾测试通过
✓ 延迟状态精确迁移测试通过
模式升级 所有测试通过！
【5. 栈模式测试】
✓ 栈模式伤害吸收测试通过
✓ 栈模式强度限制测试通过
✓ 多护盾分配测试通过
✓ 排序测试通过
栈模式 所有测试通过！
【6. 模式降级测试】
✓ 降级迟滞测试通过
✓ 状态恢复测试通过
✓ 所有护盾耗尽测试通过
✓ 嵌套ShieldStack不降级测试通过
✓ 降级延迟状态回填测试通过
模式降级 所有测试通过！
【7. 联弹机制测试】
✓ 单盾联弹测试通过
✓ 栈模式联弹测试通过
联弹机制 所有测试通过！
【8. 抵抗绕过测试】
✓ 单盾无抵抗测试通过
✓ 单盾抵抗测试通过
✓ 栈模式任意层抵抗测试通过
抵抗绕过 所有测试通过！
【9. 回调测试】
✓ onHit回调测试通过
✓ onBreak回调测试通过
✓ onExpire回调测试通过
✓ setCallbacks测试通过
✓ 内部护盾回调保留测试通过（委托模式）
✓ 扁平化模式测试通过（无内部回调时自动扁平化）
✓ preserveReference参数测试通过（强制委托模式）
回调 所有测试通过！
【10. 边界条件测试】
✓ 添加null护盾测试通过
✓ 添加未激活护盾测试通过
✓ 零伤害测试通过
✓ clear测试通过
✓ 容量为0不重复触发onBreak测试通过
✓ consumeCapacity容量为0不重复触发onBreak测试通过
✓ setCapacity钳位测试通过
✓ setMaxCapacity同步容量测试通过
边界条件 所有测试通过！
【11. 空壳模式测试】
✓ 无参构造空壳模式测试通过
✓ createDormant工厂方法测试通过
✓ 空壳模式伤害穿透测试通过
✓ 空壳模式属性测试通过
✓ 空壳升级到单盾模式测试通过
✓ 空壳升级到栈模式(嵌套栈)测试通过
✓ 耗尽降级回空壳模式测试通过
✓ 完整生命周期测试通过
✓ clear后持久存在测试通过
空壳模式 所有测试通过！
【12. 一致性对比测试】
✓ 单盾一致性测试通过
✓ 栈一致性测试通过
一致性对比 所有测试通过！
【13. 立场抗性测试】
✓ 空壳模式删除立场抗性测试通过
✓ 单盾模式写入立场抗性测试通过
✓ 栈模式写入立场抗性测试通过
✓ 模式切换立场抗性同步测试通过
✓ 强度变化立场抗性同步测试通过
✓ removeShield立场抗性同步测试通过
✓ removeShieldById立场抗性同步测试通过
✓ remove清空到0层切回空壳模式测试通过
✓ clear立场抗性同步测试通过
✓ 绑定owner触发立场抗性同步测试通过
✓ 无owner安全无操作测试通过
✓ 无魔法抗性表安全无操作测试通过
✓ refreshStanceResistance强制刷新测试通过
✓ 缓存避免重复写入测试通过
立场抗性 所有测试通过！
【14. 单盾模式ID稳定性测试】
✓ 扁平化removeShieldById测试通过
✓ 委托模式removeShieldById测试通过
✓ 扁平化getShieldById测试通过
✓ 跨模式ID稳定性测试通过
✓ 扁平化getShieldById状态同步测试通过
✓ 扁平化getShieldById元数据同步测试通过
✓ 升级maxCapacity顺序测试通过
单盾模式ID稳定性 所有测试通过！
【15. 回调重入修改结构测试】
✓ onEjected中addShield测试通过
✓ onEjected中removeShield测试通过
✓ onEjected中clear测试通过
✓ onAllDepleted中addShield测试通过
✓ 栈模式连续弹出链测试通过（弹出: 初始盾1→初始盾2→补充盾1→补充盾2）
✓ 回调中缓存一致性测试通过
✓ 子盾回调通知测试通过（break=true, expire=false）
回调重入修改结构 所有测试通过！
【16. 跨模式回调一致性契约测试】
✓ onHitCallback一致性测试通过
✓ onBreakCallback一致性测试通过
✓ 回调参数shield测试通过
✓ 扁平化自动检测机制测试通过
✓ 栈模式内部回调测试通过（触发次数=1）
跨模式回调一致性契约 所有测试通过！
【17. bypass与抵抗层边界测试】
✓ 抗真伤盾耗尽后bypass测试通过
✓ 抗真伤盾被遮挡时bypass测试通过
✓ 混合栈bypass测试通过
✓ 所有抗真伤盾耗尽测试通过
✓ resistantCount准确性测试通过
bypass与抵抗层边界 所有测试通过！
【18. setter不变量测试】
✓ setCapacity(NaN)测试通过（结果=100）
✓ setCapacity负数钳位测试通过
✓ setMaxCapacity(0)测试通过
✓ setStrength(NaN)测试通过
✓ setRechargeRate(NaN)测试通过
✓ 极大值处理测试通过
✓ 连续setter调用测试通过
setter不变量 所有测试通过！
【19. 集成级战斗模拟测试】
✓ 高频伤害测试通过（吸收1010/5850）
✓ 交替update/damage测试通过（cap=0）
✓ 多源伤害测试通过（cap=0）
✓ 快速模式切换测试通过（切换10次）
✓ 长时间运行测试通过（18000帧/28ms）
✓ 状态一致性测试通过
集成级战斗模拟 所有测试通过！
【20. IShield 接口契约测试】
✓ getId唯一性测试通过（含ShieldStack）
✓ Owner传播测试通过
✓ 栈模式Owner传播测试通过
✓ 模式切换后ID稳定性测试通过
✓ ShieldStack按ID查询/移除支持所有IShield实现
IShield 接口契约 所有测试通过！
【21. ShieldSnapshot 测试】
✓ 弹出快照元数据测试通过（含ID语义验证）
✓ 快照Owner保留测试通过
✓ ShieldSnapshot IShield接口测试通过（含isEmpty语义）
✓ fromFlattenedContainer工厂方法测试通过
ShieldSnapshot 所有测试通过！
【22. 性能测试】
单盾模式 vs Shield: AdaptiveShield 23ms, Shield 32ms (比率:0.72x)
扁平化 vs 委托: 扁平化 26ms, 委托 53ms (委托/扁平化:2.04x)
栈模式 vs ShieldStack: AdaptiveShield 115ms, ShieldStack 116ms (比率:0.99x)
模式切换(升级+降级): 1000次 501ms, 平均0.5ms/次

========================================
测试完成！总耗时: 928ms
========================================

