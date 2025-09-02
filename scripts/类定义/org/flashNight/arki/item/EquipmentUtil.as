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
    public static var tierDataList:Array = ["data_2", "data_3", "data_4", "data_ice", "data_fire"];
    public static var defaultTierDataDict = {
        二阶: {
            level: 20,
            defence: 80,
            hp: 50,
            mp: 50,
            damage: 15
        },
        三阶: {
            level: 30,
            defence: 180,
            hp: 80,
            mp: 80,
            damage: 35
        },
        四阶: {
            level: 40,
            defence: 255,
            hp: 100,
            mp: 100,
            damage: 60
        }
    }

    public static var propertyOperators:Object = {
        add: addProperty,
        multiply: multiplyProperty,
        override: overrideProperty
    }

    public static var modDict:Object;
    public static var modUseLists:Object;


    public static function loadModData(modData:Array):Void{
        var dict = {};
        var useLists = {
            头部装备: [],
            上装装备: [],
            手部装备: [],
            下装装备: [],
            脚部装备: [],
            颈部装备: [], // 目前还没有给颈部装备使用的插件
            长枪: [],
            手枪: [],
            刀: []
        };

        for(var i=0; i<modData.length; i++){
            var mod = modData[i];
            var name = mod.name;
            //
            var useArr = mod.use.split(",");
            for(var useIndex=0; useIndex < useArr.length; useIndex++){
                var useKey = useArr[useIndex];
                if(useLists[useKey]){
                    useLists[useKey].push(name);
                }
            }
            //
            var percentage = mod.stats.percentage;
            for(var key in percentage){
                percentage[key] *= 0.01;
            }
            dict[name] = mod;
        }

        modDict = dict;
        modUseLists = useLists;
    }



    public static function calculateData(item:BaseItem, itemData:Object):Void{
        var data:Object = itemData.data;
        var value = item.value;
        var level = value.level;

        var operators:Object = propertyOperators; // 三种算子

        // 获取对应的多阶数据，若不存在则使用默认数据覆盖
        if(value.tier){
            var tierKey = tierDict[value.tier];
            if(tierKey){
                var tierData = itemData[tierKey];
                if(tierData){
                    operators.override(data, tierData);
                    itemData[tierKey] = null;
                }else{
                    tierData = defaultTierDataDict[value.tier];
                    if(tierData){
                        operators.override(data, tierData);
                    }
                }
            }
        }

        if(level < 2 && !value.mods) return; // 若没有强化和插件则提前返回

        var adder = {};
        var multiplier;
        var overrider = {};
        var skill;

        // 计算强化加成
        if(level > 1){
            if(level > 13) level = 13;
            var levelMultiplier = levelStatList[level];
            multiplier = {
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
        }else{
            multiplier = {};
        }

        // 计算插件加成
        for(var modName in value.mods){
            var modInfo = modDict[modName];
            if(modInfo){
                var override = modInfo.stats.override;
                var percentage = modInfo.stats.percentage;
                var flat = modInfo.stats.flat;
                // 应用对应的加成
                if(flat) operators.add(adder, flat, 0);
                if(percentage) operators.add(multiplier, percentage, 1);
                if(override) operators.override(overrider, override);
                // 查找战技
                if(!skill && modInfo.skill){
                    skill = modInfo.skill;
                }
            }
        }

        // 以百分比加成-固定加成-覆盖的顺序应用所有加成
        operators.multiply(data, multiplier);
        operators.add(data, adder, 0);
        operators.override(data, ObjectUtil.clone(overrider));

        // 替换战技
        if(skill){
            itemData.skill = ObjectUtil.clone(skill);
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
            var addVal = addProp[key];
            if(isNaN(addVal)) continue;
            if (prop[key]) {
                prop[key] += addVal;
            }else{
                prop[key] = initValue + addVal;
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
            var multiVal = multiProp[key];
            var val = prop[key];
            if (val && !isNaN(multiVal)) {
                prop[key] = (val * multiVal) >> 0;
            }
        }
    }

    /**
    * 输入2个存放装备属性的Object对象，将后者的每个属性覆盖前者。
    *
    * @param prop 要被修改的属性对象。
    * @param overProp 用于覆盖的属性对象。
    */
    public static function overrideProperty(prop:Object, overProp:Object):Void {
        if(!overProp) return;
        for (var key:String in overProp) {
            prop[key] = overProp[key];
        }
    }
}