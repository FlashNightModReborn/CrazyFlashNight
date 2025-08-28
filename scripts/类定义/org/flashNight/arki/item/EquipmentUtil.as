import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.*;
// import org.flashNight.arki.item.itemCollection.*;

/*
 * EquipmentUtil 静态类，存储各种装备数值的计算方法
 */

class org.flashNight.arki.item.EquipmentUtil{

    // 强化比例数值表
    // 原公式为 delta = 1 + 0.01 * (level - 1) * (level + 4)
    public static var levelStatList:Array = [
        1,
        1,    // Lv1
        1.06, // Lv2
        1.14, // Lv3
        1.24, // Lv4
        1.36, // Lv5
        1.5,  // Lv6
        1.66, // Lv7
        1.84, // Lv8
        2.04, // Lv9
        2.26, // Lv10
        2.5,  // Lv11
        2.76, // Lv12
        3.04  // Lv13
    ];

    public static var tierDict:Object = {
        二阶: "data_2",
        三阶: "data_3",
        四阶: "data_4",
        墨冰: "data_ice",
        狱火: "data_fire"
    };

    public static function calculateData(item:BaseItem, itemData:Object):Void{
        var data:Object = itemData.data;
        // 获取对应的多阶数据
        if(item.value.tier){
            var tierKey = tierDict[item.value.tier];
            var tierData = itemData[tierKey];
            if(tierKey && tierData){
                for(var key in tierData){
                   data[key] = tierData[key];
                }
                itemData[tierKey] = null;
            }
        }
        // 计算强化数值
        var level = item.value.level;
        if(level > 1){
            if(level > 13) level = 13;
            var levelMultiplier = levelStatList[level];

            // var adder = {};
            var multiplier = {
                power: levelMultiplier,
                defence: levelMultiplier,
                damage: levelMultiplier,
                force: levelMultiplier,
                punch:levelMultiplier,
                knifepower: levelMultiplier,
                gunpower: levelMultiplier,
                hp: levelMultiplier,
                mp: levelMultiplier
            };
            multiplyProperty(data, multiplier);
            // addProperty(data, adder, 0);
        }
    }


    /**
    * 输入2个存放装备属性的Object对象，将后者每个属性的值增加到前者。
    * 如果键在两个Object中都存在，则值相加；
    * 如果键只在后一个Object中存在，则取该Object的值 + 初始值。
    *
    * @param prop 要被修改的属性对象。
    * @param addProp 用于相加的属性对象。
    * @param initValue prop 不存在对应属性时的初始值。
    */
    public static function addProperty(prop:Object, addProp:Object, initValue:Number):Void {
        for (var key:String in addProp) {
            if (prop[key]) {
                prop[key] += addProp[key];
            }else{
                prop[key] = initValue + addProp[key];
            }
        }
    }

    /**
    * 输入2个存放装备属性的Object对象，将后者每个属性的值对前者相乘，并去尾取整。
    * 如果键在两个Object中都存在，则值相乘，然后通过位运算去除小数位；
    * 如果键只在后一个Object中存在，不作处理。
    *
    * @param prop 要被修改的属性对象。
    * @param multiProp 用于相乘的属性对象。
    */
    public static function multiplyProperty(prop:Object, multiProp:Object):Void {
        for (var key:String in multiProp) {
            var val = prop[key];
            if (val) {
                prop[key] = (val * multiProp[key]) >> 0;
            }
        }
    }
}