
import org.flashNight.arki.component.Damage.*;
// 运行 DamageManager 测试
DamageManagerTest.runTests();



[INFO] ===== DamageManager 测试开始 =====
[INFO] ----- 开始测试工厂: Basic -----
[INFO] 测试案例1 - 普通伤害 + 1.5倍暴击
Assertion Passed: 测试案例1 - 普通伤害 + 1.5倍暴击
[INFO] 测试案例2 - 真伤子弹伤害计算
Assertion Passed: 测试案例2 - 真伤子弹伤害计算
Assertion Passed: 测试案例2 - 真伤特效检查
[INFO] 测试案例3 - 魔法子弹多重效果
Assertion Passed: 测试案例3 - 魔法子弹多重效果
Assertion Passed: 测试案例3 - 魔法特效检查
[INFO] 性能测试（Basic 工厂）：执行 10000 次伤害结算
性能测试（Basic）：执行 10000 次伤害结算，总耗时 226 毫秒，平均每次 0.0226 毫秒。
[INFO] ----- 工厂 Basic 测试完成 -----

[INFO] ----- 开始测试工厂: Extended16 -----
[INFO] 测试案例1 - 普通伤害 + 1.5倍暴击
Assertion Passed: 测试案例1 - 普通伤害 + 1.5倍暴击
[INFO] 测试案例2 - 真伤子弹伤害计算
Assertion Passed: 测试案例2 - 真伤子弹伤害计算
Assertion Passed: 测试案例2 - 真伤特效检查
[INFO] 测试案例3 - 魔法子弹多重效果
Assertion Passed: 测试案例3 - 魔法子弹多重效果
Assertion Passed: 测试案例3 - 魔法特效检查
[INFO] 性能测试（Extended16 工厂）：执行 10000 次伤害结算
性能测试（Extended16）：执行 10000 次伤害结算，总耗时 245 毫秒，平均每次 0.0245 毫秒。
[INFO] ----- 工厂 Extended16 测试完成 -----

[INFO] ----- 开始测试工厂: Extended32 -----
[INFO] 测试案例1 - 普通伤害 + 1.5倍暴击
Assertion Passed: 测试案例1 - 普通伤害 + 1.5倍暴击
[INFO] 测试案例2 - 真伤子弹伤害计算
Assertion Passed: 测试案例2 - 真伤子弹伤害计算
Assertion Passed: 测试案例2 - 真伤特效检查
[INFO] 测试案例3 - 魔法子弹多重效果
Assertion Passed: 测试案例3 - 魔法子弹多重效果
Assertion Passed: 测试案例3 - 魔法特效检查
[INFO] 性能测试（Extended32 工厂）：执行 10000 次伤害结算
性能测试（Extended32）：执行 10000 次伤害结算，总耗时 819 毫秒，平均每次 0.0819 毫秒。
[INFO] ----- 工厂 Extended32 测试完成 -----

[INFO] ===== buildHtml 渲染顺序测试 =====
Assertion Passed: 用例A - 效果顺序正确 (火→毒→汲→溃)
Assertion Passed: 用例B - 效果顺序正确 (毒→斩→🛡)
Assertion Passed: 用例C - MISS 路径正确
Assertion Passed: 用例D - 负伤害 MISS 路径正确
Assertion Passed: 用例E - 破击标签包含 emoji 和文本
Assertion Passed: 用例F - reset 正确清零所有新字段
[INFO] ===== buildHtml 渲染顺序测试完成 =====
[INFO] ===== DamageManager 测试结束 =====
