// File: org/flashNight/arki/component/Shield/MyShield.as

import org.flashNight.arki.component.Shield.*;

/**
 * MyShield - 测试用 Shield 子类
 *
 * 用于验证 AdaptiveShield 的扁平化白名单：
 * - Shield 子类必须走委托模式，避免 override 逻辑被扁平化吞掉
 *
 * @class MyShield
 * @package org.flashNight.arki.component.Shield
 * @version 1.0
 */
class org.flashNight.arki.component.Shield.MyShield extends Shield {

    /** absorbDamage 被调用次数（用于测试断言） */
    public var absorbCalled:Number;

    /** update 被调用次数（用于测试断言） */
    public var updateCalled:Number;

    /**
     * 构造函数。
     *
     * @param maxCapacity 最大容量
     * @param strength 护盾强度
     * @param rechargeRate 充能速度
     * @param rechargeDelay 充能延迟
     * @param name 名称
     * @param type 类型
     */
    public function MyShield(
        maxCapacity:Number,
        strength:Number,
        rechargeRate:Number,
        rechargeDelay:Number,
        name:String,
        type:String
    ) {
        super(maxCapacity, strength, rechargeRate, rechargeDelay, name, type);
        this.absorbCalled = 0;
        this.updateCalled = 0;
    }

    public function absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        this.absorbCalled++;
        return super.absorbDamage(damage, bypassShield, hitCount);
    }

    public function update(deltaTime:Number):Boolean {
        this.updateCalled++;
        return super.update(deltaTime);
    }
}

