// File: org/flashNight/arki/component/Damage/DamageManagerTest.as

import org.flashNight.arki.component.Damage.*;

/**
 * DamageManager 测试类
 * 
 * 通过使用 DamageManagerFactory.Basic 工厂实例，测试 DamageManager 的功能是否符合预期。
 */
class org.flashNight.arki.component.Damage.DamageManagerTest {

    /**
     * 断言方法
     * @param condition 布尔条件
     * @param message   断言失败时的错误信息
     */
    public static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("Assertion Failed: " + message);
        } else {
            trace("Assertion Passed: " + message);
        }
    }
    
    /**
     * 运行所有测试
     */
    public static function runTests():Void {
        trace("===== DamageManager 测试开始 =====");
        
        // 初始化工厂（已经在 DamageManagerFactory.Basic 中初始化）
        var factory:DamageManagerFactory = DamageManagerFactory.Basic;
        
        // 定义样例子弹
        var bullet1:Object = {
            破坏力: 100,
            暴击: 1.5, // 暴击倍率
            伤害类型: "普通",
            子弹敌我属性值: true,
            魔法伤害属性: null,
            联弹检测: true,
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
        
        var bullet2:Object = {
            破坏力: 150,
            暴击: 0, // 无暴击
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
        
        var bullet3:Object = {
            破坏力: 200,
            暴击: 2, // 高暴击
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
        
        // 定义射手
        var shooter:Object = {
            hp: 500,
            hp满血值: 500,
            淬毒: 20
        };
        
        // 定义目标
        var target:Object = {
            hp: 300,
            hp满血值: 300,
            防御力: 50,
            魔法抗性: { 火: 20, 基础: 10 },
            等级: 5,
            无敌: false,
            man: { 无敌标签: false },
            NPC: false,
            受击反制: function(damage:Number, bullet:Object):Number { return damage; },
            毒返: 0.1,
            毒返函数: function(poisonAmount:Number, poisonReturnAmount:Number):Void {
                // 毒返逻辑
            }
        };
        
        // 创建 DamageResult 实例
        var damageResult:DamageResult = new DamageResult();
        
        // 测试案例 1：普通子弹带暴击
        damageResult.reset();
        var manager1:DamageManager = factory.getDamageManager(bullet1);
        manager1.execute(bullet1, shooter, target, damageResult);
        var expectedDamage1:Number = Math.floor((bullet1.破坏力 * 1.5) * (100 - target.防御力) / 100);
        assert(target.损伤值 == expectedDamage1, "测试案例 1 - 普通子弹带暴击伤害计算");
        assert(damageResult.damageEffects.indexOf("暴") != -1, "测试案例 1 - 暴击效果添加");
        
        // 重置目标 HP
        target.hp = 300;
        target.hp满血值 = 300;
        
        // 测试案例 2：真伤子弹无暴击
        damageResult.reset();
        var manager2:DamageManager = factory.getDamageManager(bullet2);
        manager2.execute(bullet2, shooter, target, damageResult);
        var expectedDamage2:Number = bullet2.破坏力;
        assert(target.损伤值 == expectedDamage2, "测试案例 2 - 真伤子弹无暴击伤害计算");
        assert(damageResult.damageEffects.indexOf("真") != -1, "测试案例 2 - 真伤效果添加");
        
        // 重置目标 HP
        target.hp = 300;
        target.hp满血值 = 300;
        
        // 测试案例 3：魔法子弹带多重效果
        damageResult.reset();
        var manager3:DamageManager = factory.getDamageManager(bullet3);
        manager3.execute(bullet3, shooter, target, damageResult);
        var enemyMagicResist:Number = target.魔法抗性["火"];
        var expectedMagicDamage:Number = Math.floor(bullet3.破坏力 * (100 - enemyMagicResist) / 100);
        var expectedTotalDamage3:Number = expectedMagicDamage + bullet3.nanoToxic + bullet3.吸血 + bullet3.击溃;
        assert(target.损伤值 == expectedTotalDamage3, "测试案例 3 - 魔法子弹多重效果伤害计算");
        assert(damageResult.damageEffects.indexOf("真") == -1 && damageResult.damageEffects.indexOf("魔") == -1, "测试案例 3 - 魔法效果添加");
        
        // 性能测试
        var iterations:Number = 10000;
        var startTime:Number = getTimer();
        
        for (var i:Number = 0; i < iterations; i++) {
            var tempBullet:Object = {
                破坏力: 100 + (i % 50),
                暴击: (i % 10 == 0) ? 1.5 : 0,
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
                魔法抗性: { 火: 20, 基础: 10 },
                等级: 5,
                无敌: false,
                man: { 无敌标签: false },
                NPC: false,
                受击反制: function(damage:Number, bullet:Object):Number { return damage; },
                毒返: 0.1,
                毒返函数: function(poisonAmount:Number, poisonReturnAmount:Number):Void {
                    // 毒返逻辑
                }
            };
            
            var tempDamageResult:DamageResult = new DamageResult();
            manager1.execute(tempBullet, shooter, tempTarget, tempDamageResult);
        }
        
        var endTime:Number = getTimer();
        var totalTime:Number = endTime - startTime;
        var averageTime:Number = totalTime / iterations;
        trace("性能测试：执行 " + iterations + " 次伤害结算，总耗时 " + totalTime + " 毫秒，平均每次 " + averageTime + " 毫秒。");
        
        trace("===== DamageManager 测试结束 =====");
    }
}
