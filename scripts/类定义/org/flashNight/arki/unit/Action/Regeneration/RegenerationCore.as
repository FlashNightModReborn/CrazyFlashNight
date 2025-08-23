// File: org/flashNight/arki/unit/Action/Regeneration/RegenerationCore.as
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * @class RegenerationCore
 * @description 恢复核心类
 * 
 * 该类采用策略模式实现了对不同恢复类型的统一处理，
 * 包括血量恢复、法力值恢复、弹药装填等各种恢复行为。
 * 减少了代码重复，提高了可维护性，同时保持了良好的性能表现。
 * 
 * 主要功能：
 * 1. 统一处理不同类型的恢复逻辑
 * 2. 支持固定值和百分比恢复
 * 3. 支持单体和范围恢复
 * 4. 处理恢复效果显示
 * 5. 提供恢复函数工厂方法，减少重复代码
 * 
 */
class org.flashNight.arki.unit.Action.Regeneration.RegenerationCore {
    
    // 恢复类型常量
    public static var HEALTH_REGEN:String = "health";
    public static var MANA_REGEN:String = "mana";
    public static var AMMO_REGEN:String = "ammo";
    
    // 恢复模式常量
    public static var FIXED_VALUE:String = "fixed";
    public static var PERCENTAGE:String = "percentage";
    
    // 预定义的恢复函数
    public static var MERCENARY_HEALTH_REGEN:Function = createRegenerationFunction(HEALTH_REGEN, FIXED_VALUE, "group");
    public static var MERCENARY_MANA_REGEN:Function = createRegenerationFunction(MANA_REGEN, FIXED_VALUE, "group");
    public static var MEDKIT_HEALING:Function = createRegenerationFunction(HEALTH_REGEN, PERCENTAGE, "single");
    
    /**
     * 创建恢复函数的工厂方法
     * 
     * 该方法是一个高阶函数，接受恢复类型、恢复模式和作用范围参数，
     * 返回一个预先绑定这些参数的恢复函数。
     * 
     * @param regenType 恢复类型（health/mana/ammo）
     * @param valueMode 数值模式（fixed/percentage）
     * @param scope 作用范围（single/group/range）
     * 
     * @return Function 返回一个恢复函数
     */
    public static function createRegenerationFunction(regenType:String, valueMode:String, scope:String):Function {
        return function(target, value:Number, config:Object):Boolean {
            return RegenerationCore.executeRegeneration(target, regenType, valueMode, scope, value, config);
        };
    }
    
    /**
     * 执行恢复的核心方法
     * 
     * 该方法是策略模式的主入口，根据传入的参数执行对应的恢复逻辑。
     * 
     * @param target 目标对象或目标名称
     * @param regenType 恢复类型
     * @param valueMode 数值模式
     * @param scope 作用范围
     * @param value 恢复数值
     * @param config 配置对象，包含范围、效果等参数
     * 
     * @return Boolean 恢复是否成功执行
     */
    public static function executeRegeneration(target, regenType:String, valueMode:String, scope:String, value:Number, config:Object):Boolean {
        if (isNaN(value) || value <= 0) return false;
        
        var regenConfig:Object = config || {};
        
        switch (scope) {
            case "single":
                return applySingleRegeneration(target, regenType, valueMode, value, regenConfig);
            case "group":
                return applyGroupRegeneration(target, regenType, valueMode, value, regenConfig);
            case "range":
                return applyRangeRegeneration(target, regenType, valueMode, value, regenConfig);
            default:
                return false;
        }
    }
    
    /**
     * 应用单体恢复
     * 
     * @param target 目标对象或目标名称
     * @param regenType 恢复类型
     * @param valueMode 数值模式
     * @param value 恢复数值
     * @param config 配置对象
     * 
     * @return Boolean 恢复是否成功
     */
    public static function applySingleRegeneration(target, regenType:String, valueMode:String, value:Number, config:Object):Boolean {
        var targetUnit:MovieClip;
        
        if (typeof target == "string") {
            if (_root.gameworld[target] == undefined) return false;
            targetUnit = _root.gameworld[target];
        } else {
            targetUnit = target;
        }
        
        if (!isValidTarget(targetUnit, regenType)) return false;
        
        var actualValue:Number = calculateRegenValue(targetUnit, regenType, valueMode, value, config);
        applyRegenerationToUnit(targetUnit, regenType, actualValue, config);
        
        return true;
    }
    
    /**
     * 应用群体恢复
     * 
     * @param caster 施法者或中心点
     * @param regenType 恢复类型
     * @param valueMode 数值模式
     * @param value 恢复数值
     * @param config 配置对象
     * 
     * @return Boolean 恢复是否成功
     */
    public static function applyGroupRegeneration(caster, regenType:String, valueMode:String, value:Number, config:Object):Boolean {
        var hero:MovieClip = TargetCacheManager.findHero();
        var allies:Array = TargetCacheManager.getCachedAlly(hero, config.maxTargets || 30);
        var successCount:Number = 0;
        
        for (var i:Number = 0; i < allies.length; ++i) {
            var target:MovieClip = allies[i];
            
            if (isValidTarget(target, regenType)) {
                var actualValue:Number = calculateRegenValue(target, regenType, valueMode, value, config);
                applyRegenerationToUnit(target, regenType, actualValue, config);
                successCount++;
            }
        }
        
        return successCount > 0;
    }
    
    /**
     * 应用范围恢复
     * 
     * @param caster 施法者
     * @param regenType 恢复类型
     * @param valueMode 数值模式
     * @param value 恢复数值
     * @param config 配置对象，必须包含rangeX和rangeY
     * 
     * @return Boolean 恢复是否成功
     */
    public static function applyRangeRegeneration(caster:MovieClip, regenType:String, valueMode:String, value:Number, config:Object):Boolean {
        if (!config.rangeX || !config.rangeY) return false;
        
        var allies:Array = TargetCacheManager.findAlliesInRange(caster, config.maxTargets || 30, config.rangeX);
        var successCount:Number = 0;
        
        for (var i:Number = 0; i < allies.length; ++i) {
            var target:MovieClip = allies[i];
            
            // 检查Y轴范围
            if (Math.abs(target._y - caster._y) < config.rangeY && isValidTarget(target, regenType)) {
                var actualValue:Number = calculateRegenValue(target, regenType, valueMode, value, config);
                applyRegenerationToUnit(target, regenType, actualValue, config);
                successCount++;
            }
        }
        
        return successCount > 0;
    }
    
    /**
     * 检查目标是否有效
     * 
     * @param target 目标单位
     * @param regenType 恢复类型
     * 
     * @return Boolean 目标是否有效
     */
    private static function isValidTarget(target:MovieClip, regenType:String):Boolean {
        if (!target || target.hp <= 0) return false;
        
        switch (regenType) {
            case HEALTH_REGEN:
                return target.hp < target.hp满血值;
            case MANA_REGEN:
                return target.mp != undefined && target.mp >= 0 && !isNaN(target.mp) && target.mp < target.mp满血值;
            case AMMO_REGEN:
                return true; // 弹药恢复需要具体的武器类型检查
            default:
                return false;
        }
    }
    
    /**
     * 计算实际恢复数值
     * 
     * @param target 目标单位
     * @param regenType 恢复类型
     * @param valueMode 数值模式
     * @param baseValue 基础数值
     * @param config 配置对象
     * 
     * @return Number 实际恢复数值
     */
    private static function calculateRegenValue(target:MovieClip, regenType:String, valueMode:String, baseValue:Number, config:Object):Number {
        var maxValue:Number;
        
        switch (regenType) {
            case HEALTH_REGEN:
                maxValue = target.hp满血值;
                break;
            case MANA_REGEN:
                maxValue = target.mp满血值;
                break;
            case AMMO_REGEN:
                // 弹药恢复需要根据具体武器类型确定最大值
                return baseValue;
            default:
                return baseValue;
        }
        
        if (valueMode == PERCENTAGE) {
            var regenValue:Number = maxValue * baseValue;
            
            // 应用恢复加成
            if (config.multiplier && !target.是否为敌人) {
                regenValue *= config.multiplier;
            }
            
            return regenValue;
        } else {
            var fixedValue:Number = baseValue;
            
            // 应用恢复加成
            if (config.multiplier && !target.是否为敌人) {
                fixedValue *= config.multiplier;
            }
            
            return fixedValue;
        }
    }
    
    /**
     * 对单位应用恢复效果
     * 
     * @param target 目标单位
     * @param regenType 恢复类型
     * @param value 恢复数值
     * @param config 配置对象
     * 
     * @return Void
     */
    private static function applyRegenerationToUnit(target:MovieClip, regenType:String, value:Number, config:Object):Void {
        var currentValue:Number;
        var maxValue:Number;
        var propertyName:String;
        
        switch (regenType) {
            case HEALTH_REGEN:
                currentValue = target.hp;
                maxValue = target.hp满血值;
                propertyName = "hp";
                break;
            case MANA_REGEN:
                currentValue = target.mp;
                maxValue = target.mp满血值;
                propertyName = "mp";
                break;
            case AMMO_REGEN:
                // 弹药恢复需要特殊处理
                applyAmmoRegeneration(target, value, config);
                return;
            default:
                return;
        }
        
        // 应用恢复
        if (currentValue + value > maxValue) {
            target[propertyName] = maxValue;
        } else {
            target[propertyName] = currentValue + value;
        }
        
        // 播放效果
        playRegenerationEffect(target, regenType, config);
    }
    
    /**
     * 应用弹药恢复
     * 
     * @param target 目标单位
     * @param value 恢复数值
     * @param config 配置对象，应包含weaponType
     * 
     * @return Void
     */
    private static function applyAmmoRegeneration(target:MovieClip, value:Number, config:Object):Void {
        if (!config.weaponType) return;
        
        var weaponType:String = config.weaponType;
        var currentShot:Number = target[weaponType].value.shot;
        var maxAmmo:Number = target[weaponType + "弹匣容量"];
        
        var newShot:Number = Math.max(0, currentShot - value);
        target[weaponType].value.shot = newShot;
        
        // 播放装弹效果
        playRegenerationEffect(target, AMMO_REGEN, config);
    }
    
    /**
     * 播放恢复效果
     * 
     * @param target 目标单位
     * @param regenType 恢复类型
     * @param config 配置对象
     * 
     * @return Void
     */
    private static function playRegenerationEffect(target:MovieClip, regenType:String, config:Object):Void {
        var effectName:String = config.effectName;
        
        if (!effectName) {
            switch (regenType) {
                case HEALTH_REGEN:
                    effectName = "药剂动画-2";
                    break;
                case MANA_REGEN:
                    effectName = "药剂动画-2";
                    break;
                case AMMO_REGEN:
                    effectName = "装弹效果";
                    break;
                default:
                    effectName = "药剂动画-2";
            }
        }
        
        _root.效果(effectName, target._x, target._y, config.effectScale || 100, config.effectStick || true);
    }
    
    // 便捷方法：佣兵集体加血
    public static function healMercenariesGroup(healValue:Number):Boolean {
        return executeRegeneration(null, HEALTH_REGEN, FIXED_VALUE, "group", healValue, {});
    }
    
    // 便捷方法：佣兵集体回蓝
    public static function restoreMercenariesMana(manaValue:Number):Boolean {
        return executeRegeneration(null, MANA_REGEN, FIXED_VALUE, "group", manaValue, {});
    }
    
    // 便捷方法：使用血包
    public static function useMedkit(targetName:String):Boolean {
        var target:MovieClip = _root.gameworld[targetName];
        if (!target) return false;
        
        var healPercent:Number = target.血包恢复比例 / 100;
        var config:Object = {
            multiplier: target.是否为敌人 ? 1 : 2
        };
        
        return executeRegeneration(target, HEALTH_REGEN, PERCENTAGE, "single", healPercent, config);
    }
    
    // 便捷方法：范围治疗
    public static function rangeHealing(caster:MovieClip, rangeX:Number, rangeY:Number, healValue:Number, isPercentage:Boolean, effectName:String):Boolean {
        var config:Object = {
            rangeX: rangeX,
            rangeY: rangeY,
            effectName: effectName
        };
        
        var valueMode:String = isPercentage ? PERCENTAGE : FIXED_VALUE;
        return executeRegeneration(caster, HEALTH_REGEN, valueMode, "range", healValue, config);
    }
}