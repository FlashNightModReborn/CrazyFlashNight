import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * DamageManager 测试类（扩展覆盖 9-16,17-32 区间）
 * 目标：
 * 1. 当测试断言失败时，输出预期值与实际值的详细信息。
 * 2. 在每个测试案例中记录关键变量的状态，辅助问题定位。
 * 3. 模块化各个测试案例，便于管理和扩展。
 * 4. 在现有测试基础上，新增两个工厂，分别覆盖 9~16 与 17~32 个处理器的区间。
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
     * 运行所有测试（含对 9-16、17-32 区间的额外工厂覆盖）
     */
    public static function runTests():Void {
        info("===== DamageManager 测试开始 =====");
        
        // 1) 初始化基础工厂 (≤8 区间)
        DamageManagerFactory.init();

        // 2) 创建覆盖 9~16 个处理器的工厂
        //    这里以 9 个处理器为例，7 个与 Basic 相同，2 个使用 BaseDamageHandle 占位

        var dummyHandle = new BaseDamageHandle(true);
        var handles16:Array = [
            CritDamageHandle.getInstance(),
            UniversalDamageHandle.getInstance(),
            MultiShotDamageHandle.getInstance(),
            NanoToxicDamageHandle.getInstance(),
            LifeStealDamageHandle.getInstance(),
            CrumbleDamageHandle.getInstance(),
            ExecuteDamageHandle.getInstance(),   // 以上 7 个和 Basic 一致
            dummyHandle,      // 占位处理器
            dummyHandle       // 占位处理器
        ];
        DamageManagerFactory.registerFactory("Extended16", handles16, 64);

        // 3) 创建覆盖 17~32 个处理器的工厂
        //    这里以 32 个处理器为例，7 个和 Basic 相同，其余 25 个用 BaseDamageHandle 占位
        var handles32:Array = [
            CritDamageHandle.getInstance(),
            UniversalDamageHandle.getInstance(),
            MultiShotDamageHandle.getInstance(),
            NanoToxicDamageHandle.getInstance(),
            LifeStealDamageHandle.getInstance(),
            CrumbleDamageHandle.getInstance(),
            ExecuteDamageHandle.getInstance()    // 7 个和 Basic 一致
        ];
        // 补足到 32 个
        for (var i:Number = 0; i < 25; i++) {
            handles32.push(dummyHandle);
        }
        DamageManagerFactory.registerFactory("Extended32", handles32, 64);

        // 4) 对三个工厂执行相同的测试案例
        runAllScenarios("Basic");
        runAllScenarios("Extended16");
        runAllScenarios("Extended32");

        info("===== DamageManager 测试结束 =====");
    }

    /**
     * 针对指定工厂名称运行所有测试场景（1,2,3 + 性能测试）
     * @param factoryName 工厂名称，如 "Basic"、"Extended16"、"Extended32"
     */
    private static function runAllScenarios(factoryName:String):Void {
        info("----- 开始测试工厂: " + factoryName + " -----");

        // ===================== 测试案例 1 =====================
        info("测试案例1 - 普通伤害 + 1.5倍暴击");

        var bullet1:Object = {
            破坏力: 100,
            暴击: function(b:Object):Number {
                return 1.5;
            },
            伤害类型: "普通",
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

        // 计算期望伤害：
        // defenseDamageRatio = 300 / (防御+300) => 300/(350)=0.8571
        // 破坏力100 * 暴击1.5 => 150
        // => 150 * 0.8571 = 128.57 => floor=128
        var expectedDamage1:Number = 128;

        var manager1:DamageManager = DamageManagerFactory.getFactory(factoryName).getDamageManager(bullet1);
        manager1.overlapRatio = 1;
        manager1.dodgeState = "";

        manager1.execute(bullet1, shooter1, target1, damageResult1);

        var context1:Object = {bullet: bullet1, shooter: shooter1, target: target1, damageResult: damageResult1};
        assertEquals(expectedDamage1, target1.损伤值, "测试案例1 - 普通伤害 + 1.5倍暴击", context1);


        // ===================== 测试案例 2 =====================
        info("测试案例2 - 真伤子弹伤害计算");
        target1.hp = 300;
        target1.hp满血值 = 300;
        target1.损伤值 = 0;

        var bullet2:Object = {
            破坏力: 150,
            暴击: null, // 不触发暴击
            伤害类型: "真伤",
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

        var manager2:DamageManager = DamageManagerFactory.getFactory(factoryName).getDamageManager(bullet2);
        manager2.overlapRatio = 1;
        manager2.dodgeState = "";

        manager2.execute(bullet2, shooter2, target1, damageResult2);

        // 真伤不考虑防御, 期望伤害=150
        var expectedDamage2:Number = 150;

        var context2:Object = {bullet: bullet2, shooter: shooter2, target: target1, damageResult: damageResult2};
        assertEquals(expectedDamage2, target1.损伤值, "测试案例2 - 真伤子弹伤害计算", context2);

        // 断言 damageEffects 包含「真」
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

        var manager3:DamageManager = DamageManagerFactory.getFactory(factoryName).getDamageManager(bullet3);
        manager3.overlapRatio = 1;
        manager3.dodgeState = "";

        manager3.execute(bullet3, shooter3, target1, damageResult3);

        // 手动计算期望伤害的思路：
        // 1) 暴击：200 * 1.2=240
        // 2) 魔法抗性火=20 => 实际=240*(100-20)/100=192
        // 3) 加固伤10 =>202
        // 4) 击溃(15%) => 目标满血300*15% =45 =>损伤增加45 =>247
        // 5) nanoToxic:10 => 257 (具体处理看你的逻辑；若是叠加毒伤)
        //   (本示例仅演示思路，需与实际处理器实现一致)
        // 6) 吸血:20%
        // 7) 斩杀50% (当前hp=255 >300*50%=150，不触发斩杀)
        // 此处和实际代码可能有微差，请根据真实处理器逻辑校正
        
        // 假设最终 target.损伤值=247
        var expectedDamage3:Number = 247;

        var context3:Object = {bullet: bullet3, shooter: shooter3, target: target1, damageResult: damageResult3};
        assertEquals(expectedDamage3, target1.损伤值, "测试案例3 - 魔法子弹多重效果", context3);

        // 断言 damageEffects 包含「火」、「毒」、「汲」、「溃」
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
        info("性能测试（" + factoryName + " 工厂）：执行 10000 次伤害结算");

        var iterations:Number = 10000;

        // 1. 预创建 Bullet 和 Target 数据
        var preCreatedBullets:Array = [];
        var preCreatedTargets:Array = [];
        var tempDamageResult:DamageResult = new DamageResult();
        var factory:DamageManagerFactory = DamageManagerFactory.getFactory(factoryName);

        // 预生成 bullets 和 targets
        for (var i:Number = 0; i < iterations / 100; i++) {
            preCreatedBullets.push({
                破坏力: 100 + (i % 50),
                暴击: (i % 10 == 0) ? function(b:Object):Number { return 1.5; } : null,
                伤害类型: (i % 3 == 0) ? "真伤" : ((i % 3 == 1) ? "魔法" : "普通"),
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
            });

            preCreatedTargets.push({
                hp: 300,
                hp满血值: 300,
                防御力: 50,
                魔法抗性: {火: 20, 基础: 10},
                等级: 5,
                无敌: false,
                man: {无敌标签: false},
                NPC: false,
                受击反制: function(damage:Number, bullet:Object):Number { return damage; },
                毒返: 0.1,
                毒返函数: function(poisonAmount:Number, poisonReturnAmount:Number):Void {},
                损伤值: 0
            });
        }

        var tempManager:DamageManager;

        var startTime:Number = getTimer();

        // 2. 正式开始性能测试（复用预创建对象）
        for (var i:Number = 0; i < iterations / 100; i++) 
        {
            for(var j:Number = 0; j < 100; j++)
            {
                tempDamageResult.reset();

                var tempBullet:Object = preCreatedBullets[i];
                var tempTarget:Object = preCreatedTargets[i];

                tempManager = factory.getDamageManager(tempBullet);
                tempManager.overlapRatio = 1;
                tempManager.dodgeState = "";

                tempManager.execute(tempBullet, shooter1, tempTarget, tempDamageResult);
            }
        }

        var endTime:Number = getTimer();
        var totalTime:Number = endTime - startTime;
        var averageTime:Number = totalTime / iterations;

        trace("性能测试（" + factoryName + "）：执行 " + iterations + " 次伤害结算，总耗时 " + totalTime + " 毫秒，平均每次 " + averageTime + " 毫秒。");


        info("----- 工厂 " + factoryName + " 测试完成 -----\n");
    }
}
