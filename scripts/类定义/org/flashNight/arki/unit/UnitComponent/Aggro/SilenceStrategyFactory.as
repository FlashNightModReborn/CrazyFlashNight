/**
 * 消音策略工厂
 * 负责创建和管理消音策略函数，用于判断攻击是否触发仇恨
 * @class SilenceStrategyFactory
 * @package org.flashNight.arki.unit.UnitComponent.Aggro
 */

import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

class org.flashNight.arki.unit.UnitComponent.Aggro.SilenceStrategyFactory {

    /**
     * 根据消音参数生成消音策略
     *
     * 重要约定：存在消音策略时，与友军伤害冲突，不检测敌我关系以优化性能
     *
     * @param {Object} v 消音参数
     *                   - 数字：表示距离阈值，超过此距离消音成功
     *                   - 百分比字符串（如"90%"）：表示消音成功概率
     *                   - null/undefined：返回null，表示无消音策略
     *
     * @returns {Function} 消音策略函数 Function(shooter:Object, target:Object, distance:Number):Boolean
     *                     返回true表示触发仇恨，false表示消音成功（不触发仇恨）
     */
    public static function create(v:Object):Function {
        if (v == null) return null;

        var s:String = String(v);
        // _root.发布消息("创建消音策略，参数：" + s);

        // 概率消音
        // 约定：消音策略参数为百分比字符串时表示概率消音
        var percentIndex:Number = s.indexOf("%");
        if (percentIndex > 0) {
            var p:Number = Number(s.substring(0, percentIndex));
            if (isNaN(p) || p < 0 || p > 100) return null;

            // 预处理概率值：将消音成功率转换为触发仇恨率
            // 例如：90%消音成功 = 10%触发仇恨
            var triggerProbability:Number = 100 - p;
            var rng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

            return function(shooter:Object, target:Object, d:Number):Boolean {
                // 优化：直接判断是否触发仇恨，无需取反
                // true表示触发仇恨，false表示消音成功
                return rng.successRate(triggerProbability);
            };
        }

        // 距离消音（远距离消音：超过指定距离不触发仇恨）
        // 约定：消音策略参数为数值时表示距离阈值
        var r:Number = Number(v);
        if (!isNaN(r) && r > 0) {
            // 缓存距离阈值，避免闭包内重复访问外部变量
            var threshold:Number = r;

            return function(shooter:Object, target:Object, d:Number):Boolean {
                // 优化：直接返回距离比较结果
                // 距离<=阈值时返回true（触发仇恨），>阈值时返回false（消音成功）
                return d <= threshold;
            };
        }

        return null;
    }

    /**
     * 便捷方法：将消音策略挂载到承载对象的指定键上
     *
     * @param {Object} carrier 承载对象，通常是单位对象
     * @param {String} key 属性键名，例如"手枪消音策略"、"长枪消音策略"
     * @param {Object} v 消音参数，同create方法的参数
     */
    public static function bind(carrier:Object, key:String, v:Object):Void {
        var strategy:Function = SilenceStrategyFactory.create(v);
        if (strategy != null) {
            carrier[key] = strategy;
        }
    }

    /**
     * 清除指定对象上的消音策略
     *
     * @param {Object} carrier 承载对象
     * @param {String} key 属性键名
     */
    public static function clear(carrier:Object, key:String):Void {
        if (carrier[key] != null) {
            delete carrier[key];
        }
    }

    /**
     * 批量清除对象上的所有武器消音策略
     * 用于单位死亡或切换装备时的清理
     *
     * @param {Object} carrier 承载对象
     */
    public static function clearAll(carrier:Object):Void {
        var weaponTypes:Array = ["手枪", "手枪2", "长枪", "兵器"];
        for (var i:Number = 0; i < weaponTypes.length; i++) {
            var key:String = weaponTypes[i] + "消音策略";
            if (carrier[key] != null) {
                delete carrier[key];
            }
        }
    }
}