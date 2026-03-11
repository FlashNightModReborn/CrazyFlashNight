import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.ItemUtil;

/**
 * TestDataBootstrap - 同步数据注入
 *
 * 直接构造 config 和 item 数据对象，
 * 调用 EquipmentUtil.loadEquipmentConfig() + ItemUtil.loadItemData() 完成同步注入。
 */
class org.flashNight.gesh.tooltip.test.TestDataBootstrap {
    private static var _initialized:Boolean = false;

    public static function init():Void {
        if (_initialized) return;

        // 1. 注入 EquipmentConfig（对齐 data/equipment/equipment_config.xml 结构）
        // AS2 对象字面量不支持中文 key，需动态赋值
        var tierNameToKey:Object = {};
        tierNameToKey["二阶"] = "data_2";
        tierNameToKey["三阶"] = "data_3";
        var tierToMat:Object = {};
        tierToMat["data_2"] = "二阶复合防御组件";
        var defaultTier:Object = {};
        defaultTier["二阶"] = {level: 12, defence: 80};
        EquipmentUtil.loadEquipmentConfig({
            levelStatList: [1, 1, 1.06, 1.14, 1.24, 1.36, 1.5, 1.66, 1.84, 2.04, 2.26, 2.5, 2.76],
            decimalPropDict: {weight: 1, rout: 1, vampirism: 1},
            tierNameToKeyDict: tierNameToKey,
            tierToMaterialDict: tierToMat,
            defaultTierDataDict: defaultTier,
            tierDataList: ["data_2", "data_3"]
        });

        // 2. 注入物品数据（最小代表性集合，对齐仓库 XML 结构）
        var items:Array = [
            // 弹夹（GunStatsBuilder.build L38-39 需要 ItemUtil.getItemData(clipname)）
            {name: "手枪通用弹药", displayname: "手枪通用弹药",
             type: "消耗品", use: "弹夹", price: 50,
             data: {}},
            // 近战武器
            {name: "测试军刀", displayname: "测试军刀",
             type: "武器", use: "刀", actiontype: "斩击", price: 15200,
             description: "测试用近战武器",
             data: {level: 9, weight: 3, power: 100, force: 10, hp: 50, defence: 5,
                    bladeCount: 3, dressup: "刀-测试军刀"},
             data_2: {level: 12, power: 150, force: 15}},
            // 手枪
            {name: "测试手枪", displayname: "测试手枪",
             type: "武器", use: "手枪", price: 20000,
             description: "测试用手枪",
             data: {level: 10, weight: 2, clipname: "手枪通用弹药",
                    bullet: "普通", capacity: 12, interval: 200,
                    impact: 50, split: 1, singleshoot: false,
                    reloadType: "clip", power: 80}},
            // 手雷
            {name: "测试手雷", displayname: "测试手雷",
             type: "武器", use: "手雷", price: 500,
             data: {level: 1, weight: 1, power: 200}},
            // 防具
            {name: "测试护甲", displayname: "测试护甲",
             type: "防具", use: "防具", price: 8000,
             data: {level: 5, weight: 8, defence: 50, hp: 100}},
            // 药剂
            {name: "测试药水", displayname: "测试药水",
             type: "消耗品", use: "药剂", price: 100,
             data: {heal: {value: 50, target: "hp"}}},
            // 情报（maxvalue > 0 以通过 ItemUtil.isInformation 检查）
            {name: "测试情报", displayname: "测试情报",
             type: "收集品", use: "情报", price: 0, maxvalue: 1,
             description: "情报描述"}
        ];
        ItemUtil.loadItemData(items);
        _initialized = true;
    }

    public static function isReady():Boolean {
        return _initialized;
    }
}
