import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;

/**
 * 基础属性初始化组件 - 负责初始化地图元件的基础属性
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.BasicAttributeInitializer {
    
    // 默认属性常量
    private static var DEFAULT_HIT_POINT:Number = 10;
    private static var DEFAULT_HP:Number = 9999999;
    private static var DEFAULT_DEFENSE:Number = 99999;
    private static var DEFAULT_DODGE_RATE:Number = 100;
    private static var DEFAULT_HIT_EFFECT:String = "火花";
    private static var DEFAULT_AI_TYPE:String = "None";
    
    /**
     * 初始化目标的基础属性
     * @param target 要初始化的目标MovieClip
     */
    public static function initialize(target:MovieClip):Void {
        // 设置敌人标识
        target.是否为敌人 = null;
        
        // 初始化生命值
        BasicAttributeInitializer.initializeHitPoints(target);
        
        // 设置战斗属性
        BasicAttributeInitializer.initializeCombatAttributes(target);
        
        // 设置位置和AI属性
        BasicAttributeInitializer.initializePositionAndAI(target);
        
        // 设置显示状态
        BasicAttributeInitializer.initializeDisplayState(target);
    }
    
    /**
     * 初始化生命值相关属性
     * @param target 要初始化的目标MovieClip
     */
    private static function initializeHitPoints(target:MovieClip):Void {
        if (isNaN(target.hitPoint)) {
            target.hitPoint = target.hitPointMax = DEFAULT_HIT_POINT;
        } else {
            target.hitPointMax = target.hitPoint;
        }
    }
    
    /**
     * 初始化战斗属性
     * @param target 要初始化的目标MovieClip
     */
    private static function initializeCombatAttributes(target:MovieClip):Void {
        target.hp = DEFAULT_HP;
        target.防御力 = DEFAULT_DEFENSE;
        target.躲闪率 = DEFAULT_DODGE_RATE;
        target.击中效果 = target.击中效果 || DEFAULT_HIT_EFFECT;
    }
    
    /**
     * 初始化位置和AI属性
     * @param target 要初始化的目标MovieClip
     */
    private static function initializePositionAndAI(target:MovieClip):Void {
        target.Z轴坐标 = target._y;
        target.unitAIType = DEFAULT_AI_TYPE;
    }
    
    /**
     * 初始化显示状态
     * @param target 要初始化的目标MovieClip
     */
    private static function initializeDisplayState(target:MovieClip):Void {
        target.gotoAndStop("正常");
        if (target.element) {
            target.element.stop();
        }
    }
    
    /**
     * 重置目标的战斗属性为默认值
     * @param target 要重置的目标MovieClip
     */
    public static function resetCombatAttributes(target:MovieClip):Void {
        target.hp = DEFAULT_HP;
        target.防御力 = DEFAULT_DEFENSE;
        target.躲闪率 = DEFAULT_DODGE_RATE;
    }
}