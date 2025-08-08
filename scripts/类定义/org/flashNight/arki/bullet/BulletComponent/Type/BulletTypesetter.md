org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetterTest.main();

AS2兼容性Polyfill已加载

============================================================
开始执行 BulletTypesetter 和 BulletTypeUtil 完整测试套件
============================================================

=== 开始测试: 基础类型检测 ===
[PASS] 近战类型检测通过: 近战子弹
[PASS] BulletTypesetter近战类型检测通过: 近战子弹
[PASS] 近战类型检测通过: 近战联弹
[PASS] BulletTypesetter近战类型检测通过: 近战联弹
[PASS] 近战类型检测通过: 激光近战
[PASS] BulletTypesetter近战类型检测通过: 激光近战
[PASS] 联弹类型检测通过: 联弹子弹
[PASS] BulletTypesetter联弹类型检测通过: 联弹子弹
[PASS] 联弹类型检测通过: 近战联弹
[PASS] BulletTypesetter联弹类型检测通过: 近战联弹
[PASS] 联弹类型检测通过: 穿刺联弹
[PASS] BulletTypesetter联弹类型检测通过: 穿刺联弹
[PASS] 穿刺类型检测通过: 穿刺子弹
[PASS] BulletTypesetter穿刺类型检测通过: 穿刺子弹
[PASS] 穿刺类型检测通过: 穿刺联弹
[PASS] BulletTypesetter穿刺类型检测通过: 穿刺联弹
[PASS] 穿刺类型检测通过: 高速穿刺
[PASS] BulletTypesetter穿刺类型检测通过: 高速穿刺
[PASS] 透明类型检测通过: 近战子弹
[PASS] BulletTypesetter透明类型检测通过: 近战子弹
[PASS] 透明类型检测通过: 近战联弹
[PASS] BulletTypesetter透明类型检测通过: 近战联弹
[PASS] 透明类型检测通过: 透明子弹
[PASS] BulletTypesetter透明类型检测通过: 透明子弹
[PASS] 纵向类型检测通过: 纵向子弹
[PASS] BulletTypesetter纵向类型检测通过: 纵向子弹
[PASS] 纵向类型检测通过: 纵向爆炸
[PASS] BulletTypesetter纵向类型检测通过: 纵向爆炸
[PASS] 纵向类型检测通过: 纵向穿刺
[PASS] BulletTypesetter纵向类型检测通过: 纵向穿刺
[PASS] 爆炸类型检测通过: 爆炸子弹
[PASS] BulletTypesetter爆炸类型检测通过: 爆炸子弹
[PASS] 爆炸类型检测通过: 纵向爆炸
[PASS] BulletTypesetter爆炸类型检测通过: 纵向爆炸
[PASS] 手雷类型检测通过: 手雷子弹
[PASS] BulletTypesetter手雷类型检测通过: 手雷子弹
[PASS] 手雷类型检测通过: 智能手雷
[PASS] BulletTypesetter手雷类型检测通过: 智能手雷
[PASS] 手雷类型检测通过: 定时手雷
[PASS] BulletTypesetter手雷类型检测通过: 定时手雷
[PASS] 普通类型检测通过: 普通子弹
[PASS] BulletTypesetter普通类型检测通过: 普通子弹
[PASS] 普通类型检测通过: 近战子弹
[PASS] BulletTypesetter普通类型检测通过: 近战子弹
[PASS] 普通类型检测通过: 透明子弹
[PASS] BulletTypesetter普通类型检测通过: 透明子弹
=== 完成测试: 基础类型检测 ===


=== 开始测试: 标志位计算 ===
[PASS] 近战联弹正确包含近战标志
[PASS] 近战联弹正确包含联弹标志
[PASS] 近战联弹正确包含透明标志
[PASS] 近战联弹正确包含普通标志
[PASS] 穿刺爆炸正确包含穿刺标志
[PASS] 穿刺爆炸正确包含爆炸标志
[PASS] 穿刺爆炸正确不是普通子弹
[PASS] 纵向手雷正确包含纵向标志
[PASS] 纵向手雷正确包含手雷标志
=== 完成测试: 标志位计算 ===


=== 开始测试: 基础素材名提取 ===
[PASS] 联弹基础素材名应为AK47
[PASS] 非联弹基础素材名应为完整名称
[PASS] getBaseAsset应正确提取联弹基础素材名
[PASS] getBaseAsset对非联弹应返回完整名称
=== 完成测试: 基础素材名提取 ===


=== 开始测试: 外部手雷标志处理 ===
[PASS] 普通子弹本身正确不是手雷
[PASS] 外部FLAG_GRENADE正确被识别
[PASS] 处理后FLAG_GRENADE正确被清除
=== 完成测试: 外部手雷标志处理 ===


=== 开始测试: 缓存机制 ===
[PASS] 缓存前后标志位应该相同
[PASS] getFlags和setTypeFlags结果应该相同
=== 完成测试: 缓存机制 ===


=== 开始测试: 内存使用测试 ===
[PASS] 缓存一致性测试 0
[PASS] 缓存一致性测试 1
[PASS] 缓存一致性测试 2
[PASS] 缓存一致性测试 3
[PASS] 缓存一致性测试 4
[PASS] 缓存一致性测试 5
[PASS] 缓存一致性测试 6
[PASS] 缓存一致性测试 7
[PASS] 缓存一致性测试 8
[PASS] 缓存一致性测试 9
[PASS] 清空缓存后应该能重新计算
=== 完成测试: 内存使用测试 ===


=== 开始测试: 调试工具 ===
[PASS] 英文输出正确包含MELEE
[PASS] 英文输出正确包含CHAIN
[PASS] 英文输出正确包含PIERCE
[PASS] 中文输出正确包含近战
[PASS] 中文输出正确包含联弹
[PASS] 中文输出正确包含穿刺
[PASS] 空标志位英文输出正确为NONE
[PASS] 空标志位中文输出正确为无
[PASS] BulletTypesetter重定向结果与BulletTypeUtil一致
=== 完成测试: 调试工具 ===


=== 开始测试: 透明子弹类型管理 ===
[PASS] 近战子弹正确识别为透明
[PASS] 近战联弹正确识别为透明
[PASS] 透明子弹正确识别为透明
[PASS] 普通子弹正确识别为非透明
[PASS] 成功添加新的透明类型
[PASS] 新添加的类型正确识别为透明
[PASS] 重复添加正确返回false
[PASS] 透明类型数量正确增加1
[PASS] BulletTypesetter重定向功能正常
=== 完成测试: 透明子弹类型管理 ===


=== 开始测试: 边界条件测试 ===
[PASS] undefined输入应返回0
[PASS] null输入应返回0
[PASS] 空对象应返回0
[PASS] undefined子弹种类应返回0
[PASS] 空字符串子弹种类应返回undefined（性能优化设计）
[PASS] 极长字符串应该能正常处理
[PASS] 包含特殊字符的近战子弹应该被正确识别
[PASS] 包含特殊字符的联弹应该被正确识别
=== 完成测试: 边界条件测试 ===


=== 开始测试: 兼容性重定向测试 ===
[PASS] isVertical重定向测试: 近战子弹
[PASS] isMelee重定向测试: 近战子弹
[PASS] isChain重定向测试: 近战子弹
[PASS] isPierce重定向测试: 近战子弹
[PASS] isTransparency重定向测试: 近战子弹
[PASS] isGrenade重定向测试: 近战子弹
[PASS] isExplosive重定向测试: 近战子弹
[PASS] isNormal重定向测试: 近战子弹
[PASS] isVertical重定向测试: 联弹子弹
[PASS] isMelee重定向测试: 联弹子弹
[PASS] isChain重定向测试: 联弹子弹
[PASS] isPierce重定向测试: 联弹子弹
[PASS] isTransparency重定向测试: 联弹子弹
[PASS] isGrenade重定向测试: 联弹子弹
[PASS] isExplosive重定向测试: 联弹子弹
[PASS] isNormal重定向测试: 联弹子弹
[PASS] isVertical重定向测试: 穿刺爆炸
[PASS] isMelee重定向测试: 穿刺爆炸
[PASS] isChain重定向测试: 穿刺爆炸
[PASS] isPierce重定向测试: 穿刺爆炸
[PASS] isTransparency重定向测试: 穿刺爆炸
[PASS] isGrenade重定向测试: 穿刺爆炸
[PASS] isExplosive重定向测试: 穿刺爆炸
[PASS] isNormal重定向测试: 穿刺爆炸
[PASS] isVertical重定向测试: 纵向手雷
[PASS] isMelee重定向测试: 纵向手雷
[PASS] isChain重定向测试: 纵向手雷
[PASS] isPierce重定向测试: 纵向手雷
[PASS] isTransparency重定向测试: 纵向手雷
[PASS] isGrenade重定向测试: 纵向手雷
[PASS] isExplosive重定向测试: 纵向手雷
[PASS] isNormal重定向测试: 纵向手雷
[PASS] isVertical重定向测试: 普通子弹
[PASS] isMelee重定向测试: 普通子弹
[PASS] isChain重定向测试: 普通子弹
[PASS] isPierce重定向测试: 普通子弹
[PASS] isTransparency重定向测试: 普通子弹
[PASS] isGrenade重定向测试: 普通子弹
[PASS] isExplosive重定向测试: 普通子弹
[PASS] isNormal重定向测试: 普通子弹
=== 完成测试: 兼容性重定向测试 ===


============================================================
测试结果统计:
总计运行: 141 个测试
通过: 141 个
失败: 0 个
成功率: 100%
🎉 所有测试通过！
============================================================

============================================================
开始执行性能基准测试
============================================================

=== 开始测试: 性能基准测试 ===
性能基准测试结果 (10000 次迭代):
setTypeFlags: 63ms
类型检测: 197ms
缓存性能: 68ms
[PASS] setTypeFlags性能达标，10000次调用耗时63ms
[PASS] 类型检测性能达标，40000次调用耗时197ms
[PASS] 缓存性能达标，10000次调用耗时68ms
=== 完成测试: 性能基准测试 ===

性能测试完成
============================================================

完整测试套件执行完毕！
