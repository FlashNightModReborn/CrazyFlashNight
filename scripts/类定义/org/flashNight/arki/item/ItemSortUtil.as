import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.item.*;

/**
 * ItemSortUtil 物品栏排序工具类
 *
 * 提供多种物品排序策略，支持链式条件排序。通过 sortInventory 方法对外提供统一入口。
 * 排序策略包括：类型、用途、价格、等级、ID、名称、价值、更新时间等。
 * 当主要排序条件相同时，按预定义条件链进行次级排序。
 */
class org.flashNight.arki.item.ItemSortUtil {

    /*------------------------- 公共方法 -------------------------*/

    /**
     * 对物品栏进行排序并执行回调
     *
     * @param inventory 需要排序的 ArrayInventory 实例
     * @param methodName 排序策略名称（默认为"byType"）
     * @param callback 排序完成后执行的回调函数
     */
    public static function sortInventory(inventory:ArrayInventory, methodName:String, callback:Function):Void {
        // 参数校验与默认策略处理
        methodName = validateMethodName(methodName);

        // 获取排序函数并执行排序
        inventory.rebuildOrder(getComparator(methodName));

        // 执行回调函数
        if (typeof callback === "function")
            callback(inventory);
    }

    /*------------------------- 比较器核心逻辑 --------------------*/

    /**
     * 创建链式条件比较器
     *
     * @param conditions 排序条件函数数组，按优先级排列
     * @return 组合后的比较器函数
     */
    private static function createChainedComparator(conditions:Array):Function {
        return function(a:Object, b:Object):Number {
            for (var i:Number = 0; i < conditions.length; i++) {
                var result:Number = conditions[i](a, b);
                if (result != 0)
                    return result;
            }
            return 0;
        };
    }

    /**
     * 基础属性比较器生成函数
     *
     * @param propName 要比较的物品属性名
     * @param nextComparator 下一级比较器（可选）
     * @return 组合后的比较器函数
     */
    private static function compareByProperty(propName:String, nextComparator:Function):Function {
        return function(a:Object, b:Object):Number {
            var aVal = a[propName] || 0;
            var bVal = b[propName] || 0;
            if (aVal > bVal)
                return 1;
            if (aVal < bVal)
                return -1;
            return nextComparator ? nextComparator(a, b) : 0;
        };
    }

    /**
     * 元数据比较器生成函数
     *
     * @param metaField 物品元数据字段名
     * @param nextComparator 下一级比较器（可选）
     * @return 组合后的比较器函数
     */
    private static function compareByMetadata(metaField:String, nextComparator:Function):Function {
        return function(a:Object, b:Object):Number {
            var aMeta = ItemUtil.itemDataDict[a.name][metaField];
            var bMeta = ItemUtil.itemDataDict[b.name][metaField];
            if (aMeta > bMeta)
                return 1;
            if (aMeta < bMeta)
                return -1;
            return nextComparator ? nextComparator(a, b) : 0;
        };
    }

    /*------------------------- 排序策略配置 ----------------------*/

    // 类型排序的链式条件（类型 -> 用途 -> 价格 -> 等级 -> ID）
    private static var TYPE_CONDITIONS:Array = [compareByMetadata("type", null),
        compareByMetadata("use", null),
        compareByMetadata("price", null),
        compareByMetadata("level", null),
        compareByMetadata("id", null)];

    // 各排序策略配置映射
    private static var COMPARATOR_CONFIG:Object = initConfig();

    private static function initConfig():Object {
        var config:Object = {byType: TYPE_CONDITIONS,
                byUse: [compareByMetadata("use", createChainedComparator(TYPE_CONDITIONS))],
                byPrice: [compareByMetadata("price", createChainedComparator(TYPE_CONDITIONS))],
                byLevel: [compareByMetadata("level", createChainedComparator(TYPE_CONDITIONS))],
                byID: [compareByMetadata("id", null)],
                byName: [compareByProperty("name", null)],
                byValue: [compareByProperty("value", null)],
                byTime: [compareByProperty("lastUpdate", null)]};

        return config;
    }

    /*------------------------- 策略选择器 ------------------------*/

    /**
     * 获取指定策略的比较器
     *
     * @param methodName 排序策略名称
     * @return 对应的比较器函数
     */
    private static function getComparator(methodName:String):Function {
        var conditions:Array = COMPARATOR_CONFIG[methodName];
        return createChainedComparator(conditions);
    }

    /**
     * 验证并返回有效的排序策略名称
     *
     * @param methodName 输入的策略名称
     * @return 有效的策略名称（默认返回"byType"）
     */
    private static function validateMethodName(methodName:String):String {
        var DEFAULT_METHOD:String = "byType";
        return (methodName && COMPARATOR_CONFIG.hasOwnProperty(methodName)) ? methodName : DEFAULT_METHOD;
    }
}
