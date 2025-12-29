/**
 * SpeedDeriveInitializer - 速度派生初始化器
 *
 * 为所有单位统一设置速度属性的派生关系：
 *   - 行走Y速度 = 行走X速度 / 2
 *   - 跑X速度 = 行走X速度 × 奔跑速度倍率
 *   - 跑Y速度 = 行走Y速度 × 奔跑速度倍率
 *
 * 通过getter派生，修改行走X速度后其他速度自动跟随变化。
 * 这样buff系统只需修改行走X速度即可影响所有速度。
 *
 * 注意：
 *   - 跳横移速度/跳跃中移动速度是跳跃起跳时的状态缓存，不参与派生
 *   - 非主控单位的Y速度有上限限制（行走Y速度≤2.5，跑Y速度≤5）
 *   - 奔跑速度倍率：主角模板默认为2，敌人模板可自定义
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.SpeedDeriveInitializer {

    /**
     * 为目标单位设置速度派生getter
     * @param target 目标单位
     */
    public static function initialize(target:MovieClip):Void {
        // 必须已有行走X速度才能派生
        if (target.行走X速度 == undefined) return;

        // 获取奔跑速度倍率，主角模板默认为2，敌人模板可自定义
        var 奔跑倍率:Number = target.奔跑速度倍率;
        if (isNaN(奔跑倍率) || 奔跑倍率 <= 0) {
            奔跑倍率 = 2;
        }
        // 缓存倍率值供getter使用
        target._speedRunMultiplier = 奔跑倍率;

        // 判断是否为主控单位
        var isMainControl:Boolean = (target._name == _root.控制目标);

        // 清理可能存在的旧值（避免被缓存的普通属性覆盖getter）
        delete target.行走Y速度;
        delete target.跑X速度;
        delete target.跑Y速度;

        if (isMainControl) {
            // 主控单位：无速度上限限制
            setupMainControlGetters(target);
        } else {
            // 非主控单位：Y速度有上限限制
            setupNonMainControlGetters(target);
        }
    }

    /**
     * 主控单位的速度getter（无限制）
     */
    private static function setupMainControlGetters(target:MovieClip):Void {
        // 行走Y速度 = 行走X速度 / 2
        target.addProperty("行走Y速度",
            function():Number { return this.行走X速度 / 2; },
            null
        );

        // 跑X速度 = 行走X速度 × 奔跑速度倍率
        target.addProperty("跑X速度",
            function():Number { return this.行走X速度 * this._speedRunMultiplier; },
            null
        );

        // 跑Y速度 = 行走Y速度 × 奔跑速度倍率 = 行走X速度 / 2 × 奔跑速度倍率
        target.addProperty("跑Y速度",
            function():Number { return (this.行走X速度 / 2) * this._speedRunMultiplier; },
            null
        );
    }

    /**
     * 非主控单位的速度getter（Y速度有上限限制）
     * 行走Y速度上限2.5，跑Y速度上限5
     */
    private static function setupNonMainControlGetters(target:MovieClip):Void {
        // 行走Y速度 = min(行走X速度 / 2, 2.5)
        target.addProperty("行走Y速度",
            function():Number {
                return Math.min(this.行走X速度 / 2, 2.5);
            },
            null
        );

        // 跑X速度 = 行走X速度 × 奔跑速度倍率
        target.addProperty("跑X速度",
            function():Number {
                return this.行走X速度 * this._speedRunMultiplier;
            },
            null
        );

        // 跑Y速度 = min(行走Y速度 × 奔跑速度倍率, 5)
        // 注：这里直接用行走X速度计算避免嵌套getter调用
        target.addProperty("跑Y速度",
            function():Number {
                var baseY:Number = Math.min(this.行走X速度 / 2, 2.5);
                return Math.min(baseY * this._speedRunMultiplier, 5);
            },
            null
        );
    }
}
