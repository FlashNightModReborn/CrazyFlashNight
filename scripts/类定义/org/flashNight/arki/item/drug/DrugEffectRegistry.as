import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.item.drug.effects.*;

/**
 * DrugEffectRegistry - 药剂效果词条注册表
 *
 * 管理所有可用的药剂效果词条类型，负责：
 * 1. 词条类型注册
 * 2. 根据类型获取词条实例
 * 3. 批量执行effects数组
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.DrugEffectRegistry {

    /** 词条类型 -> 词条实例 的映射表 */
    private static var _effects:Object;

    /** 是否已初始化 */
    private static var _initialized:Boolean = false;

    /**
     * 初始化注册表，注册所有内置词条
     */
    public static function initialize():Void {
        if (_initialized) return;

        _effects = {};

        // 注册内置词条
        register(new HealEffect());
        register(new RegenEffect());
        register(new StateEffect());
        register(new PurifyEffect());
        register(new BuffEffect());
        register(new GlobalEffect());
        register(new GrantItemEffect());
        register(new PlayEffectEffect());
        register(new MessageEffect());

        _initialized = true;
    }

    /**
     * 注册一个词条实例
     *
     * @param effect IDrugEffect 词条实例
     */
    public static function register(effect:IDrugEffect):Void {
        if (!effect) return;
        if (!_effects) _effects = {};

        var type:String = effect.getType();
        if (type && type.length > 0) {
            _effects[type] = effect;
        }
    }

    /**
     * 根据类型获取词条实例
     *
     * @param type String 词条类型
     * @return IDrugEffect 词条实例，不存在则返回null
     */
    public static function get(type:String):IDrugEffect {
        if (!_initialized) initialize();
        return _effects[type];
    }

    /**
     * 检查是否支持指定类型
     *
     * @param type String 词条类型
     * @return Boolean 是否已注册
     */
    public static function hasType(type:String):Boolean {
        if (!_initialized) initialize();
        return _effects[type] != null;
    }

    /**
     * 执行effects数组中的所有词条
     *
     * @param effects Array 词条配置数组（来自XML）
     * @param context DrugContext 执行上下文
     * @return Number 成功执行的词条数量
     */
    public static function executeAll(effects:Array, context:DrugContext):Number {
        if (!_initialized) initialize();
        if (!effects || effects.length == 0) return 0;
        if (!context || !context.isValid()) return 0;

        var successCount:Number = 0;

        for (var i:Number = 0; i < effects.length; i++) {
            var effectData:Object = effects[i];
            if (!effectData) continue;

            var type:String = effectData.type;
            if (!type) continue;

            var effect:IDrugEffect = _effects[type];
            if (!effect) {
                trace("[DrugEffectRegistry] 未知的词条类型: " + type);
                continue;
            }

            try {
                if (effect.execute(context, effectData)) {
                    successCount++;
                }
            } catch (e:Error) {
                trace("[DrugEffectRegistry] 执行词条失败: " + type + ", 错误: " + e.message);
            }
        }

        return successCount;
    }

    /**
     * 获取所有已注册的词条类型
     *
     * @return Array 类型字符串数组
     */
    public static function getRegisteredTypes():Array {
        if (!_initialized) initialize();

        var types:Array = [];
        for (var type:String in _effects) {
            types.push(type);
        }
        return types;
    }

    /**
     * 重置注册表（主要用于测试）
     */
    public static function reset():Void {
        _effects = {};
        _initialized = false;
    }
}
