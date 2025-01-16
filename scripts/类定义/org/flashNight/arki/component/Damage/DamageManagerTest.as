// File: org/flashNight/arki/component/Damage/DamageManagerTest.as

import org.flashNight.arki.component.Damage.*;

/**
 * DamageManager 测试类（优化版）
 * 目标：
 * 1. 当测试断言失败时，输出预期值与实际值的详细信息。
 * 2. 在每个测试案例中记录关键变量的状态，辅助问题定位。
 * 3. 模块化各个测试案例，便于管理和扩展。
 */
class org.flashNight.arki.component.Damage.DamageManagerTest {


    /**
     * 输出一条提示信息（可选的日志方法）
     */
    private static function info(msg:String):Void {
        trace("[INFO] " + msg);
    }

    /**
     * 断言两个值必须相等；否则打印详细对比信息
     * @param expected 期望值
     * @param actual   实际值
     * @param message  用于提示上下文信息
     * @param context  可选，传入 bullet/target 等调试对象
     */
    public static function assertEquals(expected:Object, actual:Object, message:String, context:Object):Void {
        if (expected != actual) {
            trace("Assertion Failed: " + message);
            trace("  Expected: " + expected);
            trace("  Actual  : " + actual);
            if (context != null) {
                logContext(context);
            }
        } else {
            trace("Assertion Passed: " + message);
        }
    }

    /**
     * 断言两个浮点值在给定误差范围内相等（可选）
     * @param expected 期望值
     * @param actual   实际值
     * @param delta    允许的误差范围
     * @param message  提示信息
     * @param context  额外调试用上下文对象
     */
    public static function assertFloatEquals(expected:Number, actual:Number, delta:Number, message:String, context:Object):Void {
        var diff:Number = Math.abs(expected - actual);
        if (diff > delta) {
            trace("Assertion Failed: " + message);
            trace("  Expected: " + expected + " ±" + delta);
            trace("  Actual  : " + actual);
            if (context != null) {
                logContext(context);
            }
        } else {
            trace("Assertion Passed: " + message);
        }
    }

    /**
     * 输出一些用于定位问题的关键信息
     * 你可以根据项目需求，灵活打印 bullet/shooter/target 的字段
     */
    private static function logContext(context:Object):Void {
        // 假设 context 中包含 bullet, shooter, target, damageResult
        if (context.bullet) {
            trace("  [Bullet Info]");
            trace("    破坏力: " + context.bullet.破坏力);
            trace("    暴击: " + (context.bullet.暴击 != null ? "Function" : "null"));
            trace("    伤害类型: " + context.bullet.伤害类型);
            trace("    霰弹值: " + context.bullet.霰弹值);
            trace("    固伤: " + context.bullet.固伤);
            trace("    nanoToxic: " + context.bullet.nanoToxic);
            trace("    击溃: " + context.bullet.击溃);
            trace("    斩杀: " + context.bullet.斩杀);
        }
        if (context.shooter) {
            trace("  [Shooter Info]");
            trace("    hp: " + context.shooter.hp);
            trace("    hp满血值: " + context.shooter.hp满血值);
            trace("    淬毒: " + context.shooter.淬毒);
        }
        if (context.target) {
            trace("  [Target Info]");
            trace("    hp: " + context.target.hp);
            trace("    hp满血值: " + context.target.hp满血值);
            trace("    防御力: " + context.target.防御力);
            trace("    损伤值: " + context.target.损伤值);
        }
        if (context.damageResult) {
            trace("  [DamageResult Info]");
            trace("    totalDamageList: " + context.damageResult.totalDamageList.join(", "));
            trace("    damageEffects: " + context.damageResult.damageEffects);
            trace("    finalScatterValue: " + context.damageResult.finalScatterValue);
            trace("    dodgeStatus: " + context.damageResult.dodgeStatus);
        }
    }

    /**
     * 防御力计算公式
     * @param defense 防御值
     * @return 防御减伤比
     */
    public static function defenseDamageRatio(defense:Number):Number {
        return 300 / (defense + 300);
    }

    /**
     * 运行所有测试
     */
    public static function runTests():Void {
        info("===== DamageManager 测试开始 =====");
        DamageManagerFactory.init();
        // ===================== 测试案例 1 =====================
        info("测试案例1 - 普通伤害 + 1.5倍暴击");
        var bullet1:Object = {
            破坏力: 100,
            暴击: function(b:Object):Number {
                return 1.5;
            },
            伤害类型: "普通",
            子弹敌我属性值: true,
            魔法伤害属性: null,
            联弹检测: false, // 霰弹值为1，联弹检测为false
            穿刺检测: false,
            nanoToxic: 0,
            吸血: 0,
            击溃: 0,
            斩杀: 0,
            固伤: 0,
            霰弹值: 1,
            最小霰弹值: 1,
            普通检测: true,
            近战检测: false
        };

        var shooter1:Object = {
            hp: 500,
            hp满血值: 500,
            淬毒: 20
        };

        var target1:Object = {
            hp: 300,
            hp满血值: 300,
            防御力: 50,
            魔法抗性: {火: 20, 基础: 10},
            等级: 5,
            无敌: false,
            man: {无敌标签: false},
            NPC: false,
            受击反制: function(damage:Number, bullet:Object):Number {
                return damage;
            },
            毒返: 0.1,
            毒返函数: function(poisonAmount:Number, poisonReturnAmount:Number):Void {
            }
        };

        var damageResult1:DamageResult = new DamageResult();
        damageResult1.reset();
        
        var manager1:DamageManager = DamageManagerFactory.Basic.getDamageManager(bullet1);
        manager1.overlapRatio = 1;
        manager1.dodgeState = "";

        manager1.execute(bullet1, shooter1, target1, damageResult1);

        // 计算期望伤害：破坏力 * 暴击 * defenseDamageRatio
        var expectedDamage1:Number = Math.floor(bullet1.破坏力 * bullet1.暴击(bullet1) * defenseDamageRatio(target1.防御力));
        // = Math.floor(100 * 1.5 * 300 / (50 + 300)) = Math.floor(150 * 300 / 350) = Math.floor(150 * 0.8571) = Math.floor(128.571) = 128

        var context1:Object = {bullet: bullet1, shooter: shooter1, target: target1, damageResult: damageResult1};
        assertEquals(expectedDamage1, target1.损伤值, "测试案例1 - 普通伤害 + 1.5倍暴击", context1);

        // 断言 damageEffects 包含「暴」字眼
        var hasCritEffect1:Boolean = (damageResult1.damageEffects.indexOf("暴") != -1);
        if (!hasCritEffect1) {
            trace("Assertion Failed: 测试案例1 - 暴击特效未添加");
            logContext(context1);
        } else {
            trace("Assertion Passed: 测试案例1 - 暴击特效检查");
        }


        // ===================== 测试案例 2 =====================
        info("测试案例2 - 真伤子弹伤害计算");
        target1.hp = 300;
        target1.hp满血值 = 300;
        target1.损伤值 = 0;

        var bullet2:Object = {
            破坏力: 150,
            暴击: null, // 不触发暴击
            伤害类型: "真伤",
            子弹敌我属性值: false,
            魔法伤害属性: null,
            联弹检测: false,
            穿刺检测: false,
            nanoToxic: 0,
            吸血: 0,
            击溃: 0,
            斩杀: 0,
            固伤: 0,
            霰弹值: 1,
            最小霰弹值: 1,
            普通检测: true,
            近战检测: false
        };

        var shooter2:Object = shooter1; // 使用相同 shooter

        var damageResult2:DamageResult = new DamageResult();
        damageResult2.reset();

        var manager2:DamageManager = DamageManagerFactory.Basic.getDamageManager(bullet2);
        manager2.overlapRatio = 1;
        manager2.dodgeState = "";

        manager2.execute(bullet2, shooter2, target1, damageResult2);

        var expectedDamage2:Number = Math.floor(bullet2.破坏力); // 真伤忽略防御
        // = 150

        var context2:Object = {bullet: bullet2, shooter: shooter2, target: target1, damageResult: damageResult2};
        assertEquals(expectedDamage2, target1.损伤值, "测试案例2 - 真伤子弹伤害计算", context2);

        // 断言 damageEffects 包含「真」字眼
        var hasTrueEffect2:Boolean = (damageResult2.damageEffects.indexOf("真") != -1);
        if (!hasTrueEffect2) {
            trace("Assertion Failed: 测试案例2 - 真伤特效未添加");
            logContext(context2);
        } else {
            trace("Assertion Passed: 测试案例2 - 真伤特效检查");
        }


        // ===================== 测试案例 3 =====================
        info("测试案例3 - 魔法子弹多重效果");
        target1.hp = 300;
        target1.hp满血值 = 300;
        target1.损伤值 = 0;

        var bullet3:Object = {
            破坏力: 200,
            暴击: function(b:Object):Number {
                return 1.2;
            }, // 可选的魔法暴击
            伤害类型: "魔法",
            子弹敌我属性值: true,
            魔法伤害属性: "火",
            联弹检测: false,
            穿刺检测: true,
            nanoToxic: 10,
            吸血: 20,
            击溃: 15,
           斩杀: 50,
            固伤: 10,
            霰弹值: 3,
            最小霰弹值: 1,
            普通检测: true,
            近战检测: true
        };

        var shooter3:Object = shooter1; // 使用相同 shooter

        var damageResult3:DamageResult = new DamageResult();
        damageResult3.reset();

        var manager3:DamageManager = DamageManagerFactory.Basic.getDamageManager(bullet3);
        manager3.overlapRatio = 1;
        manager3.dodgeState = "";

        manager3.execute(bullet3, shooter3, target1, damageResult3);

        // 计算期望伤害：
        // 1. 暴击：200 * 1.2 = 240
        // 2. 魔法伤害：240 * (300 / (50 + 300)) = 240 * 300/350 ≈ 205.714 ≈ 205
        // 3. 加固伤：10 => 215
        // 4. 击溃：15% of hp满血值 (300 * 15 / 100 = 45), target.hp满血值 -=45 =>255, target.损伤值 +=45 =>260
        // 5. nanoToxic:10 (添加 poison)
        // 6. 吸血:20 (20% of damage)
        // 7. 斩杀:50 (斩杀触发: target.hp=255 < 300*50/100=150? No, since 255 > 150)

        // 详细计算：
        // 1. CritDamageHandle: 200 * 1.2 =240, 添加 "暴" 特效
        // 2. MagicDamageHandle: 240 * (300 / 350) = 205.714 ≈205, 添加 "火" 特效
        // 3. 固伤: +10 =>215
        // 4. CrumbleDamageHandle: +45 =>260, 添加 "溃" 特效
        // 5. PoisonDamageHandle: +10 =>270, 添加 "毒" 特效
        // 6. LifeStealDamageHandle: 20% of damage= 20% of 270=54, but limited to shooter.hp满血值 *1.5 - shooter.hp = 500 *1.5 -500=750-500=250, shooter.hp +=54 =>554
        //    添加 "汲:54" 特效
        // 7. ExecuteDamageHandle:斩杀条件：target.hp=255 < 150? No, 不触发
        // 8. DamageResult.damageEffects: "暴" + "火" + "溃" + "毒" + "汲:54"

        // 最终 target.损伤值=270

        var expectedDamage3:Number = 270;

        var context3:Object = {bullet: bullet3, shooter: shooter3, target: target1, damageResult: damageResult3};
        assertEquals(expectedDamage3, target1.损伤值, "测试案例3 - 魔法子弹多重效果", context3);

        // 断言 damageEffects 包含「火」、「毒」、「汲」、「溃」字眼
        var hasMagicEffect3:Boolean = (damageResult3.damageEffects.indexOf("火") != -1);
        var hasPoisonEffect3:Boolean = (damageResult3.damageEffects.indexOf("毒") != -1);
        var hasLifeStealEffect3:Boolean = (damageResult3.damageEffects.indexOf("汲") != -1);
        var hasCrumbleEffect3:Boolean = (damageResult3.damageEffects.indexOf("溃") != -1);

        if (!hasMagicEffect3 || !hasPoisonEffect3 || !hasLifeStealEffect3 || !hasCrumbleEffect3) {
            trace("Assertion Failed: 测试案例3 - 魔法特效未完全添加");
            logContext(context3);
        } else {
            trace("Assertion Passed: 测试案例3 - 魔法特效检查");
        }

        // ===================== 性能测试（可选） =====================
        info("性能测试：执行 10000 次伤害结算");
        var iterations:Number = 10000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            var tempBullet:Object = {
                破坏力: 100 + (i % 50),
                暴击: (i % 10 == 0) ? function(b:Object):Number {
                    return 1.5;
                } : null,
                伤害类型: (i % 3 == 0) ? "真伤" : (i % 3 == 1 ? "魔法" : "普通"),
                子弹敌我属性值: (i % 2 == 0),
                魔法伤害属性: (i % 5 == 0) ? "火" : null,
                联弹检测: (i % 4 == 0),
                穿刺检测: (i % 6 == 0),
                nanoToxic: (i % 7 == 0) ? 10 : 0,
                吸血: (i % 8 == 0) ? 20 : 0,
                击溃: (i % 9 == 0) ? 15 : 0,
                斩杀: (i % 10 == 0) ? 50 : 0,
                固伤: 0,
                霰弹值: 1 + (i % 3),
                最小霰弹值: 1,
                普通检测: true,
                近战检测: false
            };

            var tempTarget:Object = {
                hp: 300,
                hp满血值: 300,
                防御力: 50,
                魔法抗性: {火: 20, 基础: 10},
                等级: 5,
                无敌: false,
                man: {无敌标签: false},
                NPC: false,
                受击反制: function(damage:Number, bullet:Object):Number {
                    return damage;
                },
                毒返: 0.1,
                毒返函数: function(poisonAmount:Number, poisonReturnAmount:Number):Void {
                }
            };

            var tempDamageResult:DamageResult = new DamageResult();
            tempDamageResult.reset();

            var tempManager:DamageManager = DamageManagerFactory.Basic.getDamageManager(tempBullet);
            tempManager.overlapRatio = 1;
            tempManager.dodgeState = "";

            tempManager.execute(tempBullet, shooter1, tempTarget, tempDamageResult);
        }

        var endTime:Number = getTimer();
        var totalTime:Number = endTime - startTime;
        var averageTime:Number = totalTime / iterations;

        trace("性能测试：执行 " + iterations + " 次伤害结算，总耗时 " + totalTime + " 毫秒，平均每次 " + averageTime + " 毫秒。");

        info("===== DamageManager 测试结束 =====");
    }
}
