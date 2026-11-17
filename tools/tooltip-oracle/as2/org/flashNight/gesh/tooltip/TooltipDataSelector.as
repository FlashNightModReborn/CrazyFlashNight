import org.flashNight.arki.item.*;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * TooltipDataSelector - 装备数据选择器
 *
 * 职责：
 * - 根据品阶（tier）选择并合并装备数据
 * - 提供纯函数接口，不修改原始数据
 *
 * 设计原则：
 * - 所有方法均为纯函数（Pure Function）
 * - 输入数据不会被修改，保证数据不可变性
 * - 返回新的合并对象，避免副作用
 */
class org.flashNight.gesh.tooltip.TooltipDataSelector {

    /**
     * 获取装备数据（纯函数）
     *
     * 根据品阶名称，将品阶特定数据合并到基础装备数据上。
     *
     * **重要：** 此函数不会修改输入的 item 对象，而是返回一个新的合并对象。
     *
     * @param item:Object 原始物品数据对象（不会被修改）
     * @param tier:String 品阶名称（如 "一阶"、"二阶" 等），可选
     * @return Object 合并后的新数据对象
     *
     * @example
     * ```actionscript
     * var item = {data: {power: 100}, elite: {power: 150}};
     * var result = TooltipDataSelector.getEquipmentData(item, "墨冰");
     * // result.power === 150
     * // item.data.power === 100 (原始数据未被修改)
     * ```
     *
     * @since 1.0
     * @pure 此函数为纯函数，不产生副作用
     */
    public static function getEquipmentData(item:Object, tier:String):Object {
        // 没有品阶时，返回基础数据的深拷贝
        if (tier == null || !item.data) {
            return ObjectUtil.clone(item.data);
        }

        // 查找品阶对应的键名
        var tierKey:String = EquipmentUtil.tierNameToKeyDict[tier];
        if (tierKey == null) {
            return ObjectUtil.clone(item.data);
        }

        // 获取品阶数据（优先使用物品自带的，否则使用默认品阶数据）
        var tierData:Object = item[tierKey];
        if (!tierData) {
            tierData = EquipmentUtil.defaultTierDataDict[tier];
        }

        // 没有品阶数据时，返回基础数据的深拷贝
        if (!tierData) {
            return ObjectUtil.clone(item.data);
        }

        // 创建基础数据的深拷贝（避免修改原始数据）
        var result:Object = ObjectUtil.clone(item.data);

        // 将品阶数据合并到结果中
        for (var key:String in tierData) {
            if (ObjectUtil.isInternalKey(key)) continue; // 跳过内部字段（如 __dictUID）
            result[key] = tierData[key];
        }

        return result;
    }
}