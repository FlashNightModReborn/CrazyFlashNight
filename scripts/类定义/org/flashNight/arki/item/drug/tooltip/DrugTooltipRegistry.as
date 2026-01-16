import org.flashNight.arki.item.drug.tooltip.IDrugTooltipBuilder;
import org.flashNight.arki.item.drug.tooltip.builders.*;

/**
 * DrugTooltipRegistry - 药剂 Tooltip 构建器注册表
 *
 * 管理所有词条类型的 Tooltip 构建器，按 type 分发。
 * 结构与 DrugEffectRegistry 对称。
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.tooltip.DrugTooltipRegistry {

    /** 词条类型 -> 构建器实例 的映射表 */
    private static var _builders:Object;

    /** 是否已初始化 */
    private static var _initialized:Boolean = false;

    /** 默认不显示的词条类型 */
    private static var _hiddenTypes:Object = {
        playEffect: true,
        message: true,
        global: true
    };

    /**
     * 初始化注册表，注册所有内置构建器
     */
    public static function initialize():Void {
        if (_initialized) return;

        _builders = {};

        // 注册内置构建器
        register(new HealTooltipBuilder());
        register(new RegenTooltipBuilder());
        register(new StateTooltipBuilder());
        register(new PurifyTooltipBuilder());
        register(new BuffTooltipBuilder());
        register(new GrantItemTooltipBuilder());
        // playEffect, message, global 默认不显示，不需要注册

        _initialized = true;
    }

    /**
     * 注册一个构建器实例
     *
     * @param builder IDrugTooltipBuilder 构建器实例
     */
    public static function register(builder:IDrugTooltipBuilder):Void {
        if (!builder) return;
        if (!_builders) _builders = {};

        var type:String = builder.getType();
        if (type && type.length > 0) {
            _builders[type] = builder;
        }
    }

    /**
     * 根据类型获取构建器实例
     *
     * @param type String 词条类型
     * @return IDrugTooltipBuilder 构建器实例，不存在则返回null
     */
    public static function get(type:String):IDrugTooltipBuilder {
        if (!_initialized) initialize();
        return _builders[type];
    }

    /**
     * 检查词条类型是否应该显示
     *
     * @param type String 词条类型
     * @param effectData Object 词条数据（可包含 tooltip="false" 覆盖）
     * @return Boolean 是否应该显示
     */
    public static function shouldDisplay(type:String, effectData:Object):Boolean {
        // 局部覆盖：tooltip="false" 强制不显示
        if (effectData.tooltip === false || effectData.tooltip === "false") {
            return false;
        }

        // 默认隐藏的类型
        if (_hiddenTypes[type]) {
            return false;
        }

        return true;
    }

    /**
     * 构建单个词条的 Tooltip
     *
     * @param effectData Object 词条配置数据
     * @return Array HTML 文本片段数组
     */
    public static function buildOne(effectData:Object):Array {
        if (!_initialized) initialize();
        if (!effectData) return [];

        var type:String = effectData.type;
        if (!type) return [];

        // 检查是否应该显示
        if (!shouldDisplay(type, effectData)) {
            return [];
        }

        var builder:IDrugTooltipBuilder = _builders[type];
        if (!builder) {
            // 未知类型，静默忽略
            return [];
        }

        return builder.build(effectData);
    }

    /**
     * 构建所有词条的 Tooltip
     *
     * @param effects Array 词条配置数组
     * @return Array HTML 文本片段数组
     */
    public static function buildAll(effects:Array):Array {
        if (!_initialized) initialize();
        if (!effects || effects.length == 0) return [];

        var result:Array = [];

        for (var i:Number = 0; i < effects.length; i++) {
            var effectData:Object = effects[i];
            var fragments:Array = buildOne(effectData);
            if (fragments && fragments.length > 0) {
                result = result.concat(fragments);
            }
        }

        return result;
    }

    /**
     * 重置注册表（主要用于测试）
     */
    public static function reset():Void {
        _builders = {};
        _initialized = false;
    }
}
