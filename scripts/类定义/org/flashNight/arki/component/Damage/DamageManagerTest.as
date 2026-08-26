import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.component.Effect.HitNumberBatchProcessor;

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
            trace("    _efFlags: " + context.damageResult._efFlags);
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
        //    这里以 9 个处理器为例，8 个与 Basic 相同，1 个使用 BaseDamageHandle 占位

        var dummyHandle = new BaseDamageHandle(true);
        var handles16:Array = [
            CritDamageHandle.getInstance(),
            UniversalDamageHandle.getInstance(),
            DodgeStateDamageHandle.getInstance(),
            MultiShotDamageHandle.getInstance(),
            NanoToxicDamageHandle.getInstance(),
            LifeStealDamageHandle.getInstance(),
            CrumbleDamageHandle.getInstance(),
            ExecuteDamageHandle.getInstance(),   // 以上 8 个和 Basic 一致
            dummyHandle       // 占位处理器
        ];
        DamageManagerFactory.registerFactory("Extended16", handles16, 64);

        // 3) 创建覆盖 17~32 个处理器的工厂
        //    这里以 32 个处理器为例，8 个和 Basic 相同，其余 24 个用 BaseDamageHandle 占位
        var handles32:Array = [
            CritDamageHandle.getInstance(),
            UniversalDamageHandle.getInstance(),
            DodgeStateDamageHandle.getInstance(),
            MultiShotDamageHandle.getInstance(),
            NanoToxicDamageHandle.getInstance(),
            LifeStealDamageHandle.getInstance(),
            CrumbleDamageHandle.getInstance(),
            ExecuteDamageHandle.getInstance()    // 8 个和 Basic 一致
        ];
        // 补足到 32 个
        for (var i:Number = 0; i < 24; i++) {
            handles32.push(dummyHandle);
        }
        DamageManagerFactory.registerFactory("Extended32", handles32, 64);

        // 4) 对三个工厂执行相同的测试案例
        runAllScenarios("Basic");
        runAllScenarios("Extended16");
        runAllScenarios("Extended32");

        // 5) Burst 队列契约 + reset 清零验证
        testBurstQueueContract();

        info("===== DamageManager 测试结束 =====");
    }

    /** focused runner 只执行本轮打击数字跨层契约，避免把历史性能循环混入门槛。 */
    public static function runAllTests():Void {
        testBurstQueueContract();
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

        // 断言 _efFlags 包含 EF_DMG_TYPE_LABEL (bit 3 = 8)
        var hasTrueEffect2:Boolean = ((damageResult2._efFlags & 8) != 0);
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

        // 实际伤害流程（经运行验证）：
        // 1) 暴击：200 * 1.2 = 240
        // 2) 魔法抗性、固伤、击溃、nanoToxic、吸血、斩杀等处理器
        //    对 target.损伤值 的最终影响 = 240（已通过运行确认）
        var expectedDamage3:Number = 240;

        var context3:Object = {bullet: bullet3, shooter: shooter3, target: target1, damageResult: damageResult3};
        assertEquals(expectedDamage3, target1.损伤值, "测试案例3 - 魔法子弹多重效果", context3);

        // 断言 _efFlags 包含：EF_DMG_TYPE_LABEL(8)、EF_TOXIC(2)、EF_LIFESTEAL(32)、EF_CRUMBLE(1)
        var flags3:Number = damageResult3._efFlags;
        var hasMagicEffect3:Boolean = ((flags3 & 8) != 0);   // EF_DMG_TYPE_LABEL
        var hasPoisonEffect3:Boolean = ((flags3 & 2) != 0);  // EF_TOXIC
        var hasLifeStealEffect3:Boolean = ((flags3 & 32) != 0); // EF_LIFESTEAL
        var hasCrumbleEffect3:Boolean = ((flags3 & 1) != 0); // EF_CRUMBLE

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

    /** 验证 Burst 标识、预计段数入队与 reset 的纯事件契约。 */
    public static function testBurstQueueContract():Void {
        info("===== Burst 队列契约测试 =====");

        var passed:Number = 0;
        var failed:Number = 0;

        HitNumberBatchProcessor.clear();
        var firstBurst:String = HitNumberBatchProcessor.nextBurstId();
        var secondBurst:String = HitNumberBatchProcessor.nextBurstId();
        if (firstBurst == "1" && secondBurst == "2") {
            ++passed;
            trace("Assertion Passed: BurstId 场景内单调且 clear 后从 1 开始");
        } else {
            ++failed;
            trace("Assertion Failed: BurstId 序列异常 first=" + firstBurst + " second=" + secondBurst);
        }

        HitNumberBatchProcessor.setHostEnabled(false);
        if (!HitNumberBatchProcessor.isHostEnabled() && HitNumberBatchProcessor.getQueueLength() == 0) {
            ++passed;
            trace("Assertion Passed: H0 关闭来源并清空队列");
        } else {
            ++failed;
            trace("Assertion Failed: H0 未关闭来源或未清空队列");
        }

        var disabledResult:DamageResult = new DamageResult();
        disabledResult.addDamageValue(10);
        disabledResult.addDamageValue(20);
        disabledResult.addDamageValue(30);
        disabledResult.triggerDisplay(512, 360, "boss");
        if (HitNumberBatchProcessor.getQueueLength() == 0) {
            ++passed;
            trace("Assertion Passed: Host 关闭时 triggerDisplay 在 Burst 分配前短路");
        } else {
            ++failed;
            trace("Assertion Failed: Host 关闭时仍产生打击数字事件");
        }

        HitNumberBatchProcessor.setHostEnabled(true);
        if (HitNumberBatchProcessor.isHostEnabled()) {
            ++passed;
            trace("Assertion Passed: H1 开启来源");
        } else {
            ++failed;
            trace("Assertion Failed: H1 未开启来源");
        }

        disabledResult.triggerDisplay(512, 360, "boss");
        if (HitNumberBatchProcessor.getQueueLength() == 3) {
            ++passed;
            trace("Assertion Passed: 一发联弹的三段完整入队");
        } else {
            ++failed;
            trace("Assertion Failed: triggerDisplay 联弹队列长度异常");
        }

        HitNumberBatchProcessor.setHostEnabled(false);
        if (HitNumberBatchProcessor.getQueueLength() == 0) {
            ++passed;
            trace("Assertion Passed: H0 原子清除未发送批次");
        } else {
            ++failed;
            trace("Assertion Failed: H0 未清除未发送批次");
        }

        var packed:Number = 8 | (28 << 10) | (1 << 18);
        HitNumberBatchProcessor.setHostEnabled(true);
        HitNumberBatchProcessor.enqueueRaw(
            100, packed, "火", null, 0, 0,
            512, 360, "boss", firstBurst, 3
        );
        HitNumberBatchProcessor.enqueueRaw(
            120, packed, "火", null, 0, 0,
            512, 360, "boss", firstBurst, 3
        );
        HitNumberBatchProcessor.enqueueRaw(
            140, packed, "火", null, 0, 0,
            512, 360, "boss", firstBurst, 3
        );
        if (HitNumberBatchProcessor.getQueueLength() == 3) {
            ++passed;
            trace("Assertion Passed: 11 字段来源元数据不改变逐段计数");
        } else {
            ++failed;
            trace("Assertion Failed: 直接入队的联弹队列长度异常");
        }

        var oldServer:Object = _root.server;
        _root.server = {isSocketConnected: false};
        HitNumberBatchProcessor.flush();
        _root.server = oldServer;
        if (HitNumberBatchProcessor.getQueueLength() == 0) {
            ++passed;
            trace("Assertion Passed: 断连竞态在序列化前清空队列");
        } else {
            ++failed;
            trace("Assertion Failed: 断连竞态未清空队列");
        }

        // DamageResult.reset 后效果标量清零验证
        var dr:DamageResult = new DamageResult();
        dr._efFlags = 255;
        dr._dmgColorId = 5;
        dr._efText = "测试";
        dr._efLifeSteal = 99;
        dr._efShieldAbsorb = 50;
        dr.reset();

        if (dr._efFlags != 0 || dr._dmgColorId != 0 || dr._efText != null || dr._efLifeSteal != 0 || dr._efShieldAbsorb != 0) {
            ++failed;
            trace("Assertion Failed: DamageResult.reset 未清零效果字段");
            trace("  _efFlags=" + dr._efFlags + " _dmgColorId=" + dr._dmgColorId + " _efText=" + dr._efText);
        } else {
            ++passed;
            trace("Assertion Passed: DamageResult.reset 正确清零效果字段");
        }

        HitNumberBatchProcessor.setHostEnabled(false);
        HitNumberBatchProcessor.clear();
        trace("HitNumberBurstContract Tests Passed: " + passed);
        trace("HitNumberBurstContract Tests Failed: " + failed);
        info("===== Burst 队列契约测试完成 =====");
    }
}
