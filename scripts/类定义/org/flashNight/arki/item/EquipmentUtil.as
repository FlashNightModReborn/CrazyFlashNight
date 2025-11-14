import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.string.*;
import org.flashNight.arki.item.*;
// import org.flashNight.arki.item.itemCollection.*;

/*
 * EquipmentUtil 静态类，存储各种装备数值的计算方法
 */

class org.flashNight.arki.item.EquipmentUtil{

    // 调试模式开关（设置为true时输出调试日志）
    public static var DEBUG_MODE:Boolean = false;

    /**
    * 输出调试日志（仅在DEBUG_MODE为true时生效）
    * @param msg 要输出的调试信息
    */
    private static function debugLog(msg:String):Void {
        if(DEBUG_MODE) {
            _root.服务器.发布服务器消息("[EquipmentUtil] " + msg);
        }
    }

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

    /**
    * 获取最大等级值（基于levelStatList长度）
    * @return 最大等级值
    */
    public static function getMaxLevel():Number {
        return levelStatList.length - 1;
    }

    // 数值计算中需要保留小数点的属性字典，目前逻辑为在字典中的属性保留1位小数，否则去尾取整
    public static var decimalPropDict:Object = {
        weight: 1,
        rout: 1,
        vampirism: 1
    }

    // 进阶名称->进阶数据键字典
    public static var tierNameToKeyDict:Object = {
        二阶: "data_2",
        三阶: "data_3",
        四阶: "data_4",
        墨冰: "data_ice",
        狱火: "data_fire"
    };
    // 进阶数据键->进阶名称反向字典
    public static var tierKeyToNameDict:Object;

    // 进阶数据键->进阶材料字典
    public static var tierToMaterialDict:Object = {
        data_2: "二阶复合防御组件",
        data_3: "三阶复合防御组件",
        data_4: "四阶复合防御组件",
        data_ice: "墨冰战术涂料",
        data_fire: "狱火战术涂料"
    };
    // 进阶材料->进阶数据键反向字典
    public static var materialToTierDict:Object;

    // 进阶名称->进阶材料字典
    public static var tierNameToMaterialDict:Object;
    // 进阶材料->进阶名称反向字典
    public static var tierMaterialToNameDict:Object;

    public static var tierDataList:Array = ["data_2", "data_3", "data_4", "data_ice", "data_fire"];
    
    public static var defaultTierDataDict:Object = {
        二阶: {
            level: 12,
            defence: 80,
            hp: 50,
            mp: 50,
            damage: 15
        },
        三阶: {
            level: 25,
            defence: 180,
            hp: 80,
            mp: 80,
            damage: 35
        },
        四阶: {
            level: 35,
            defence: 255,
            hp: 100,
            mp: 100,
            damage: 60
        }
    }

    public static var propertyOperators:Object = {
        add: addProperty,
        multiply: multiplyProperty,
        override: overrideProperty,
        merge: mergeProperty,  // 新增：深度合并运算符
        applyCap: applyCapProperty
    }

    public static var modDict:Object;
    public static var modList:Array;
    public static var modUseLists:Object;


    /**
    * 初始化字典并加载配件数据
    *
    * @param modData 配件数据数组，每个元素包含：
    *   - name: 配件名称
    *   - use: 可用装备类型（逗号分隔）
    *   - weapontype: 武器类型限制（可选，逗号分隔）
    *   - grantsWeapontype: 授予的武器类型（可选，逗号分隔）
    *   - detachPolicy: 拆卸策略（默认"single"）
    *   - tag: 互斥标签（可选）
    *   - stats: 属性修改对象 {flat, percentage, override, merge, cap}
    *
    * 注意：此方法现在是幂等的，可以安全地多次调用
    */
    public static function loadModData(modData:Array):Void{
        // 初始化字典
        tierKeyToNameDict = {};
        tierNameToMaterialDict = {};
        tierMaterialToNameDict = {};
        for(var tierName:String in tierNameToKeyDict){
            var tierKey:String = tierNameToKeyDict[tierName];
            var mat:String = tierToMaterialDict[tierKey];
            tierKeyToNameDict[tierKey] = tierName;
            tierNameToMaterialDict[tierName] = mat;
            tierMaterialToNameDict[mat] = tierName;
        }
        materialToTierDict = {};
        for(var tierKey:String in tierToMaterialDict){
            materialToTierDict[tierToMaterialDict[tierKey]] = tierKey;
        }

        if(modData.length <= 0) return;

        //
        var dict:Object = {};
        var list:Array = [];
        var useLists:Object = {
            头部装备: [],
            上装装备: [],
            手部装备: [],
            下装装备: [],
            脚部装备: [],
            颈部装备: [], // 颈部装备可能不考虑允许插件
            长枪: [],
            手枪: [],
            刀: []
        };

        for(var i:Number = 0; i < modData.length; i++){
            var mod:Object = modData[i];
            var name:String = mod.name;
            //
            var useArr:Array = mod.use.split(",");
            for(var useIndex:Number = 0; useIndex < useArr.length; useIndex++){
                var useKey:String = useArr[useIndex];
                if(useLists[useKey]){
                    useLists[useKey].push(name);
                }
            }
            if(mod.weapontype){
                var typeArr:Array = mod.weapontype.split(",");
                if(typeArr.length > 0){
                    var wdict:Object = {};
                    for(var typeIndex:Number = 0; typeIndex < typeArr.length; typeIndex++){
                        wdict[typeArr[typeIndex]] = true;
                    }
                    mod.weapontypeDict = wdict;
                }
            }
            // 解析 grantsWeapontype 标签
            if(mod.grantsWeapontype){
                var grantsArr:Array = mod.grantsWeapontype.split(",");
                if(grantsArr.length > 0){
                    var grantDict:Object = {};
                    for(var grantIndex:Number = 0; grantIndex < grantsArr.length; grantIndex++){
                        grantDict[grantsArr[grantIndex]] = true;
                    }
                    mod.grantsWeapontypeDict = grantDict;
                }
            }
            // 解析 detachPolicy 标签，默认为 "single"
            if(mod.detachPolicy){
                mod.detachPolicy = mod.detachPolicy;
            }else{
                mod.detachPolicy = "single";
            }
            // 解析 tag 标签，用于实现同tag插件互斥
            if(mod.tag){
                mod.tagValue = mod.tag; // 存储tag值
            }
            // 调整百分比区的值为小数（防止重复处理）
            if(!mod._percentageNormalized){
                var percentage:Object = mod.stats ? mod.stats.percentage : null;
                if(percentage){
                    for(var key:String in percentage){
                        percentage[key] *= 0.01;
                    }
                    mod._percentageNormalized = true; // 标记已归一化，防止重复处理
                }
            }
            // 调整multiplier区的值为小数（独立乘区百分比）
            if(!mod._multiplierNormalized){
                var multiplier:Object = mod.stats ? mod.stats.multiplier : null;
                if(multiplier){
                    for(var key:String in multiplier){
                        multiplier[key] *= 0.01;
                    }
                    mod._multiplierNormalized = true; // 标记已归一化，防止重复处理
                }
            }

            // 处理useSwitch中的百分比归一化
            if(!mod._useSwitchNormalized && mod.stats && mod.stats.useSwitch){
                var useSwitch:Object = mod.stats.useSwitch;

                // 将useSwitch.use统一转换为数组
                var useCases:Array;
                if(useSwitch.use instanceof Array){
                    useCases = useSwitch.use;
                }else if(useSwitch.use){
                    useCases = [useSwitch.use];
                }else{
                    useCases = [];
                }

                // 对每个use分支进行归一化
                for(var ucIndex:Number = 0; ucIndex < useCases.length; ucIndex++){
                    var useCase:Object = useCases[ucIndex];

                    // 归一化percentage字段
                    if(useCase.percentage){
                        for(var pKey:String in useCase.percentage){
                            useCase.percentage[pKey] *= 0.01;
                        }
                    }

                    // 归一化multiplier字段
                    if(useCase.multiplier){
                        for(var mKey:String in useCase.multiplier){
                            useCase.multiplier[mKey] *= 0.01;
                        }
                    }
                }

                // 保存处理后的数组形式
                useSwitch.useCases = useCases;
                mod._useSwitchNormalized = true;
            }

            list.push(name);
            dict[name] = mod;
        }

        modDict = dict;
        modList = list;
        modUseLists = useLists;


        initializeModAvailabilityResults();
    }


    public static function getTierItem(tier:String):String{
        var tierData:String = tierNameToKeyDict[tier];
        return tierData ? tierToMaterialDict[tierData] : null;
    }



    /**
    * 查找所有可用的进阶材料
    *
    * @param item 装备物品对象
    * @return 可用的进阶材料名称数组
    */
    public static function getAvailableTierMaterials(item:BaseItem):Array{
        var rawItemData:Object = ItemUtil.getRawItemData(item.name);
        var list:Array = [];
        for(var i:Number = 0; i < tierDataList.length; i++){
            var tierKey:String = tierDataList[i];
            if(rawItemData[tierKey]) list.push(tierToMaterialDict[tierKey]);
        }
        if(list.length === 0){
            if(rawItemData.type === "防具" && rawItemData.use !== "颈部装备" && rawItemData.data.level < 10){
                return [tierToMaterialDict["data_2"],tierToMaterialDict["data_3"],tierToMaterialDict["data_4"]];
            }
        }
        return list;
    }

    /**
    * 查找进阶插件是否能合法装备
    *
    * @param item 装备物品对象
    * @param matName 进阶材料名称
    * @return true如果可以装备，false否则
    */
    public static function isTierMaterialAvailable(item:BaseItem, matName:String):Boolean{
        var rawItemData:Object = ItemUtil.getRawItemData(item.name);
        var tierKey:String = materialToTierDict[matName];
        if(rawItemData[tierKey]) return true;
        if(rawItemData.type === "防具" && rawItemData.use !== "颈部装备" && rawItemData.data.level < 10){
            if(tierKey === "data_2" || tierKey === "data_3" || tierKey === "data_4") return true;
        }
        return false;
    }


    /**
    * 查找所有可用的配件材料
    *
    * @param item 装备物品对象
    * @return 可用的配件名称数组
    */
    public static function getAvailableModMaterials(item:BaseItem):Array{
        var rawItemData:Object = ItemUtil.getRawItemData(item.name);
        var list:Array = [];
        var mods:Array = item.value.mods;

        // 收集所有已授予的武器类型（包括武器自身类型和配件授予的类型）
        var grantedTypes:Object = {};

        // 1. 武器自身的weapontype
        if(rawItemData.weapontype){
            grantedTypes[rawItemData.weapontype] = true;
        }

        // 2. 遍历已安装的配件，收集它们授予的武器类型
        for(var i:Number = 0; i < mods.length; i++){
            var installedMod:Object = modDict[mods[i]];
            if(installedMod && installedMod.grantsWeapontypeDict){
                for(var grantedType:String in installedMod.grantsWeapontypeDict){
                    grantedTypes[grantedType] = true;
                }
            }
        }

        // 3. 遍历候选配件列表，检查是否可用
        var useList:Array = modUseLists[rawItemData.use];
        if(!useList) return []; // 添加空值防护
        for(var i:Number = 0; i < useList.length; i++){
            var modName:String = useList[i];
            var modData:Object = modDict[modName];
            var weapontypeDict:Object = modData.weapontypeDict;

            if(!weapontypeDict){
                // 没有武器类型限制，直接允许
                list.push(modName);
            }else{
                // 检查是否有任何已授予的类型与配件要求的类型匹配
                var canUse:Boolean = false;
                for(var requiredType:String in weapontypeDict){
                    if(grantedTypes[requiredType]){
                        canUse = true;
                        break;
                    }
                }
                if(canUse){
                    list.push(modName);
                }
            }
        }
        return list;
    }

    /**
    * 查找配件插件是否能合法装备
    *
    * @param item 装备物品对象
    * @param itemData 原始物品数据
    * @param matName 配件名称
    * @return 状态码：1=可装备，0=配件不存在，-1=槽位已满，-2=已装备，
    *         -4=战技冲突，-8=tag冲突
    */
    public static function isModMaterialAvailable(item:BaseItem, itemData:Object, matName:String):Number{
        var mods:Array = item.value.mods;
        var modData:Object = modDict[matName];
        if(!modData) return 0;

        // 添加空值防护
        if(!itemData || !itemData.data) return 0;
        var modslot:Number = itemData.data.modslot;
        var len:Number = mods.length;
        if(len > 0 && len >= modslot) return -1; // 槽位已满
        for(var i:Number = 0; i < len; i++){
            if(mods[i] === matName) return -2; // 已装备同名配件
        }
        // 检查tag互斥：同tag的插件不能同时装备
        if(modData.tagValue){
            for(var j:Number = 0; j < len; j++){
                var installedModData:Object = modDict[mods[j]];
                if(installedModData && installedModData.tagValue){
                    if(installedModData.tagValue === modData.tagValue){
                        return -8; // 同tag插件已装备，不能装备多个相同tag的插件
                    }
                }
            }
        }
        //
        if(itemData.skill && modData.skill) return -4; // 已有战技
        return 1; // 允许装备
    }

    public static function initializeModAvailabilityResults():Void{
        modAvailabilityResults = {};
        modAvailabilityResults[1] = "可装备";
        modAvailabilityResults[0] = "配件数据不存在";
        modAvailabilityResults[-1] = "装备配件槽已满";
        modAvailabilityResults[-2] = "已装备";
        modAvailabilityResults[-4] = "配件无法覆盖装备原本的主动战技";
        modAvailabilityResults[-8] = "同位置插件已装备"; // tag冲突：一个装备不能同时装多个相同tag的插件
    }

    public static var modAvailabilityResults:Object;

    /**
    * 应用进阶数据覆盖
    * @private
    */
    private static function applyTierData(itemData:Object, value:Object):Void {
        if(!value.tier) return;

        var tierKey:String = tierNameToKeyDict[value.tier];
        if(!tierKey) return;

        var tierData:Object = itemData[tierKey];
        if(!tierData) {
            // 使用默认进阶数据
            tierData = defaultTierDataDict[value.tier];
        }

        if(!tierData) return;

        // 覆盖 data 内的属性
        propertyOperators.override(itemData.data, tierData);

        // 覆盖顶层属性（icon, displayname, description, skill）
        if(tierData.icon !== undefined) itemData.icon = tierData.icon;
        if(tierData.displayname !== undefined) itemData.displayname = tierData.displayname;
        if(tierData.description !== undefined) itemData.description = tierData.description;
        if(tierData.skill !== undefined) itemData.skill = ObjectUtil.clone(tierData.skill);

        // 清空已使用的进阶数据（无条件置空，保持原始行为）
        itemData[tierKey] = null;
    }

    /**
    * 构建基础强化倍率
    * @private
    */
    private static function buildBaseMultiplier(level:Number):Object {
        if(level <= 1) return {};

        var maxLevel:Number = getMaxLevel();
        if(level > maxLevel) level = maxLevel;

        var levelMultiplier:Number = levelStatList[level];
        return {
            power: levelMultiplier,
            defence: levelMultiplier,
            damage: levelMultiplier,
            force: levelMultiplier,
            punch: levelMultiplier,
            knifepower: levelMultiplier,
            gunpower: levelMultiplier,
            hp: levelMultiplier,
            mp: levelMultiplier
        };
    }

    /**
    * 累积配件的各种修改器
    * @param mods 配件名称数组
    * @param itemUse 装备的use属性（可能是逗号分隔的字符串）
    * @param itemWeaponType 装备的weapontype属性（武器子类）
    * @private
    */
    private static function accumulateModifiers(mods:Array, itemUse:String, itemWeaponType:String):Object {
        var adder:Object = {};
        var multiplier:Object = {};
        var overrider:Object = {};
        var merger:Object = {};
        var capper:Object = {};
        var multiplierZone:Object = {};  // 新增：独立乘区累积器
        var skill:Object = null;

        var operators:Object = propertyOperators;

        // 解析装备的use和weapontype列表（合并到一个列表中）
        var itemUseList:Array = [];

        // 添加use
        if(itemUse) {
            var tempUseList:Array = itemUse.split(",");
            for(var ui:Number = 0; ui < tempUseList.length; ui++) {
                var trimmedUse:String = StringUtils.trim(tempUseList[ui]);
                if(trimmedUse.length > 0) {
                    itemUseList.push(trimmedUse);
                }
            }
        }

        // 添加weapontype（武器子类也参与匹配）
        if(itemWeaponType) {
            var tempWeaponList:Array = itemWeaponType.split(",");
            for(var wi:Number = 0; wi < tempWeaponList.length; wi++) {
                var trimmedWeapon:String = StringUtils.trim(tempWeaponList[wi]);
                if(trimmedWeapon.length > 0) {
                    // 避免重复添加
                    var found:Boolean = false;
                    for(var ci:Number = 0; ci < itemUseList.length; ci++) {
                        if(itemUseList[ci] == trimmedWeapon) {
                            found = true;
                            break;
                        }
                    }
                    if(!found) {
                        itemUseList.push(trimmedWeapon);
                    }
                }
            }
        }

        // 内部helper函数：应用一个stats块
        var applyStats:Function = function(stats:Object):Void {
            if(!stats) return;

            var overrideStat:Object = stats.override;
            var percentageStat:Object = stats.percentage;
            var flatStat:Object = stats.flat;
            var mergeStat:Object = stats.merge;
            var capStat:Object = stats.cap;
            var multiplierStat:Object = stats.multiplier;

            // 应用对应的加成
            if(flatStat) operators.add(adder, flatStat, 0);
            if(percentageStat) operators.add(multiplier, percentageStat, 1);
            if(overrideStat) operators.override(overrider, overrideStat);
            if(mergeStat) operators.merge(merger, mergeStat);
            if(capStat) operators.add(capper, capStat, 0);

            // 独立乘区的乘法累积
            if(multiplierStat) {
                for(var key:String in multiplierStat) {
                    var p:Number = multiplierStat[key];  // 已归一化为小数
                    if(isNaN(p)) continue;

                    var factor:Number = 1 + p;  // 转换为倍率（支持负数削弱）

                    // 安全保护：防止倍率过低
                    if(factor < 0.01) factor = 0.01;

                    if(!multiplierZone[key]) {
                        multiplierZone[key] = factor;
                    } else {
                        multiplierZone[key] *= factor;  // 连乘
                    }
                }
            }
        };

        for(var i:Number = 0; i < mods.length; i++){
            var modInfo:Object = modDict[mods[i]];
            if(!modInfo) continue;

            // 仅在DEBUG模式下执行，避免生产环境的字符串拼接开销
            if(modInfo.stats.merge && DEBUG_MODE) {
                debugLog("发现插件 '" + mods[i] + "' 含有merge数据: " + ObjectUtil.toString(modInfo.stats.merge));
            }
            if(modInfo.stats.multiplier && DEBUG_MODE) {
                debugLog("发现插件 '" + mods[i] + "' 含有multiplier数据: " + ObjectUtil.toString(modInfo.stats.multiplier));
            }

            // 应用顶层stats
            applyStats(modInfo.stats);

            // 处理useSwitch条件分支
            if(modInfo.stats && modInfo.stats.useSwitch && modInfo.stats.useSwitch.useCases) {
                if(DEBUG_MODE) {
                    debugLog("检查插件 '" + mods[i] + "' 的useSwitch");
                    debugLog("  装备use='" + itemUse + "'，weapontype='" + itemWeaponType + "'");
                    debugLog("  合并后的itemUseList=" + itemUseList.join(",") + " (长度=" + itemUseList.length + ")");
                }

                if(itemUseList.length > 0) {
                    var useCases:Array = modInfo.stats.useSwitch.useCases;

                    if(DEBUG_MODE) {
                        debugLog("  找到 " + useCases.length + " 个useSwitch分支");
                    }

                    for(var ucIdx:Number = 0; ucIdx < useCases.length; ucIdx++) {
                        var useCase:Object = useCases[ucIdx];
                        if(!useCase.name) continue;

                        // 解析分支的use列表
                        var branchUseList:Array = [];
                        var tempBranchList:Array = useCase.name.split(",");
                        for(var bi:Number = 0; bi < tempBranchList.length; bi++) {
                            var trimmedBranch:String = StringUtils.trim(tempBranchList[bi]);
                            if(trimmedBranch.length > 0) {
                                branchUseList.push(trimmedBranch);
                            }
                        }

                        if(DEBUG_MODE) {
                            debugLog("  分支 " + ucIdx + " name='" + useCase.name + "'，branchUseList=" + branchUseList.join(","));
                        }

                        // 检查是否有交集（匹配）
                        var matched:Boolean = false;
                        for(var a:Number = 0; a < itemUseList.length && !matched; a++) {
                            for(var b:Number = 0; b < branchUseList.length && !matched; b++) {
                                if(DEBUG_MODE) {
                                    debugLog("    比较: '" + itemUseList[a] + "' vs '" + branchUseList[b] + "'");
                                }
                                if(itemUseList[a] == branchUseList[b]) {
                                    matched = true;
                                }
                            }
                        }

                        // 如果匹配，应用该分支的stats
                        if(matched) {
                            if(DEBUG_MODE) {
                                debugLog("  ✓ 分支匹配！应用useSwitch效果");
                                if(useCase.multiplier) {
                                    debugLog("    multiplier效果: " + ObjectUtil.toString(useCase.multiplier));
                                }
                            }
                            applyStats(useCase);
                        } else {
                            if(DEBUG_MODE) {
                                debugLog("  ✗ 分支不匹配");
                            }
                        }
                    }
                } else {
                    if(DEBUG_MODE) {
                        debugLog("  装备没有use属性，跳过useSwitch");
                    }
                }
            }

            // 查找战技
            if(!skill && modInfo.skill) skill = modInfo.skill;
        }

        if(DEBUG_MODE && multiplierZone.power) {
            debugLog("最终累积的独立乘区power倍率: " + multiplierZone.power);
        }

        return {
            adder: adder,
            multiplier: multiplier,
            overrider: overrider,
            merger: merger,
            capper: capper,
            multiplierZone: multiplierZone,  // 新增：返回独立乘区数据
            skill: skill
        };
    }

    /**
    * 按照固定顺序应用所有运算符
    * @private
    */
    private static function applyOperatorsInOrder(data:Object, baseMultiplier:Object, modifiers:Object):Void {
        var operators:Object = propertyOperators;

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 数值膨胀抑制方案：增量加法累积
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //
        // 核心思想：
        // 强化等级和配件的百分比加成应该以"增量形式"累加，而非乘法叠加，
        // 以保持线性增长，有效抑制数值膨胀。
        //
        // 公式：
        //   最终倍率 = 1 + (强化倍率 - 1) + 配件百分比总和
        //            = 1 + 强化增量 + 配件增量
        //
        // 示例（基础威力100）：
        //   强化 Lv13（倍率3.04，增量2.04）
        //   配件总计 +60%（三个+20%配件）
        //
        //   计算：100 × (1 + 2.04 + 0.60) = 100 × 3.64 = 364
        //
        // 对比其他方案：
        //   乘法叠加：100 × 3.04 × 1.60 = 486（膨胀过快）
        //   旧版bug： 100 × (3.04 + 1.60) = 464（错误计算）
        //
        // 这种方案的优势：
        //   1. 线性增长，数值可控
        //   2. 强化与配件平等，符合直觉
        //   3. 配件之间仍然是加法累积（符合XML文档设计意图）
        //   4. 有效抑制多配件叠加时的指数膨胀
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // 构建最终倍率：将强化倍率和配件倍率以"增量形式"合并
        var finalMultiplier:Object = {};

        // 将 baseMultiplier 的倍率转换为增量（减去1）
        for (var key:String in baseMultiplier) {
            var baseValue:Number = Number(baseMultiplier[key]);
            if (!isNaN(baseValue)) {
                finalMultiplier[key] = baseValue - 1; // 转换为增量
            }
        }

        // 将配件的百分比增量累加（modifiers.multiplier 中已经是 1+p 形式）
        if (modifiers.multiplier) {
            for (var modKey:String in modifiers.multiplier) {
                var modValue:Number = Number(modifiers.multiplier[modKey]);
                if (!isNaN(modValue)) {
                    var increment:Number = modValue - 1; // 提取增量部分
                    if (!isNaN(finalMultiplier[modKey])) {
                        finalMultiplier[modKey] += increment; // 累加增量
                    } else {
                        finalMultiplier[modKey] = increment; // 首次添加
                    }
                }
            }
        }

        // 将增量还原为倍率（加回1）
        for (var finalKey:String in finalMultiplier) {
            finalMultiplier[finalKey] = 1 + finalMultiplier[finalKey];
        }

        // 保存基础属性副本（用于cap计算）
        var baseData:Object = ObjectUtil.clone(data);

        // 按顺序应用运算符
        // 1. 应用合并后的最终倍率（percentage + 强化等级的加法合并乘区）
        operators.multiply(data, finalMultiplier);

        // 2. 应用独立乘区（multiplier的乘法增幅）
        if(modifiers.multiplierZone) {
            // Debug: 追踪multiplier执行
            if(DEBUG_MODE) {
                debugLog("Applying multiplier operator (独立乘区): " + ObjectUtil.toString(modifiers.multiplierZone));
            }
            operators.multiply(data, modifiers.multiplierZone);
        }

        // 3. 应用固定值加成
        operators.add(data, modifiers.adder, 0);

        // 4. 应用覆盖值
        operators.override(data, ObjectUtil.clone(modifiers.overrider));

        // Debug: 追踪merge执行
        if(modifiers.merger && DEBUG_MODE){
            debugLog("Applying merge operator: " + ObjectUtil.toString(modifiers.merger));
            if(data.magicdefence) {
                debugLog("Before merge - magicdefence: " + ObjectUtil.toString(data.magicdefence));
            }
        }

        // 5. 应用深度合并
        operators.merge(data, modifiers.merger);

        // Debug: 追踪merge结果
        if(modifiers.merger && DEBUG_MODE){
            if(data.magicdefence) {
                debugLog("After merge - magicdefence: " + ObjectUtil.toString(data.magicdefence));
            }
        }

        // 6. 应用上限限制
        operators.applyCap(data, modifiers.capper, baseData);
    }



    /**
    * 计算装备经过进阶、强化与配件之后的最终数值。
    *
    * 运算顺序：
    * 1. 进阶覆盖（tier override）
    * 2. 百分比加成（percentage multiply - 加法合并乘区）
    * 3. 独立乘区（multiplier multiply - 乘法增幅）
    * 4. 固定值加成（flat add）
    * 5. 覆盖值（override）
    * 6. 深度合并（merge）
    * 7. 上限过滤（cap）
    *
    * @param item 装备物品对象，包含value属性（level, tier, mods等）
    * @param itemData 原始物品数据，会被直接修改
    */
    public static function calculateData(item:BaseItem, itemData:Object):Void{
        var data:Object = itemData.data;
        var value:Object = item.value;
        var level:Number = value.level;

        // Step 1: 应用进阶数据
        applyTierData(itemData, value);

        // 若没有强化和插件则提前返回
        if(level < 2 && value.mods.length <= 0) return;

        // Step 2: 构建基础强化倍率
        var baseMultiplier:Object = buildBaseMultiplier(level);

        // Step 3: 累积配件修改器（传入装备的use和weapontype信息）
        var itemUse:String = itemData.use || "";
        var itemWeaponType:String = itemData.weapontype || "";
        var modifiers:Object = accumulateModifiers(value.mods, itemUse, itemWeaponType);

        // Step 4: 按顺序应用所有运算符
        applyOperatorsInOrder(data, baseMultiplier, modifiers);

        // Step 5: 替换战技
        if(modifiers.skill){
            itemData.skill = ObjectUtil.clone(modifiers.skill);
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
            var addVal:Number = addProp[key];
            if(isNaN(addVal)) continue;
            if (prop[key]) {
                prop[key] += addVal;
            }else{
                prop[key] = initValue + addVal;
            }
        }
    }

    /**
    * 输入2个存放装备属性的Object对象，将后者每个属性的值对前者相乘，并四舍五入，远离原点取整。
    * 不校验浮点数的精度，对于非常小的浮点数可能会有误差，但边界行为对装备数值来说可接受
    * 如果键在两个Object中都存在，则值相乘，然后通过位运算去除小数位；
    * 如果键只在后一个Object中存在，不作处理。
    *
    * @param prop 要被修改的属性对象。
    * @param multiProp 用于相乘的属性对象。
    */
    public static function multiplyProperty(prop:Object, multiProp:Object):Void {
        var dpd:Object = decimalPropDict; // 需要保留一位小数的键

        for (var key:String in multiProp) {
            var a:Number = prop[key];
            var b:Number = multiProp[key];
            var val:Number = a * b;

            // 保持原语义：val 为 0/NaN/undefined 时不写回
            if (!val) continue;

            // 一条路径搞定整数/一位小数
            var dec:Boolean = dpd[key];             // 是否保留一位小数
            var scale:Number = dec ? 10 : 1;        // 放大倍数
            var t:Number = val * scale;

            // 0.5 远离 0：正数 +0.5，负数 -0.5
            t += (t >= 0) ? 0.5 : -0.5;

            // 位运算转 int32，向0截断
            var n:Number = (t | 0);

            // 写回（小数则缩回）
            prop[key] = dec ? (n * 0.1) : n;

            // 如要消掉 -0，可解开下一行
            // if (prop[key] == 0) prop[key] = 0;
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

    /**
    * 应用属性上限过滤。对最终计算结果应用上限约束。
    * 正数cap表示属性的最大值（上限），负数cap表示属性的最小值（下限，绝对值）。
    *
    * @param prop 要被限制的属性对象。
    * @param capProp 上限配置对象。
    * @param baseProp 基础属性对象（用于计算变化量）。如果为null，则直接限制绝对值。
    */
    public static function applyCapProperty(prop:Object, capProp:Object, baseProp:Object):Void {
        if(!capProp) return;

        for (var key:String in capProp) {
            var capValue:Number = capProp[key];
            if(capValue == undefined || capValue == 0) continue;

            var currentVal:Number = prop[key];
            if(currentVal == undefined) continue;

            if (baseProp && baseProp[key] != undefined) {
                // 基于基础值计算变化量
                var baseVal:Number = baseProp[key];
                var change:Number = currentVal - baseVal;

                // 调试日志（需要时取消注释）
                // _root.服务器.发布服务器消息("[Cap调试] " + key + ": 基础=" + baseVal + ", 当前=" + currentVal + ", 变化=" + change + ", 上限=" + capValue);

                if (capValue > 0) {
                    // 正数cap = 增益上限（最多增加capValue）
                    if (change > capValue) {
                        // _root.服务器.发布服务器消息("[Cap生效] " + key + " 增益被限制: " + change + " -> " + capValue);
                        prop[key] = baseVal + capValue;
                    }
                } else if (capValue < 0) {
                    // 负数cap = 减益下限（最多减少|capValue|）
                    if (change < capValue) {
                        // _root.服务器.发布服务器消息("[Cap生效] " + key + " 减益被限制: " + change + " -> " + capValue);
                        prop[key] = baseVal + capValue;  // capValue本身是负数
                    }
                }
            } else {
                // 没有基础值，直接限制绝对值
                // _root.服务器.发布服务器消息("[Cap调试] " + key + ": 无基础值, 当前=" + currentVal + ", 上限=" + capValue);
                if (capValue > 0) {
                    // 正数cap = 最大值上限
                    if (currentVal > capValue) {
                        // _root.服务器.发布服务器消息("[Cap生效] " + key + " 绝对值被限制: " + currentVal + " -> " + capValue);
                        prop[key] = capValue;
                    }
                } else if (capValue < 0) {
                    // 负数cap = 最小值下限（绝对值）
                    var minValue:Number = -capValue;  // 转换为正数
                    if (currentVal < minValue) {
                        // _root.服务器.发布服务器消息("[Cap生效] " + key + " 绝对值下限被限制: " + currentVal + " -> " + minValue);
                        prop[key] = minValue;
                    }
                }
            }
        }
    }

    /**
    * 深度合并属性对象（智能合并）。
    * 递归处理嵌套对象，对于数字类型采用智能合并策略：
    * - 如果存在负数，取最小值（保留最不利的debuff）
    * - 如果都是正数，取最大值（保留最有利的buff）
    *
    * 使用场景：
    * - magicdefence等嵌套对象的部分更新
    * - skillmultipliers的多技能倍率合并
    *
    * @param prop 目标属性对象（会被修改）
    * @param mergeProp 要合并的属性对象
    */
    public static function mergeProperty(prop:Object, mergeProp:Object):Void {
        if(!mergeProp) return;

        for (var key:String in mergeProp) {
            var mergeVal = mergeProp[key];
            var propVal = prop[key];

            // 情况1：目标属性不存在，直接添加（深度克隆）
            if(propVal == undefined) {
                // _root.服务器.发布服务器消息("    [Merge] 添加新属性 '" + key + "' = " + mergeVal);
                prop[key] = ObjectUtil.clone(mergeVal);
                continue;
            }

            // 情况2：两个都是对象（且不是null），递归合并
            if(typeof mergeVal == "object" && mergeVal != null &&
               typeof propVal == "object" && propVal != null) {
                // _root.服务器.发布服务器消息("    [Merge] 递归合并对象属性 '" + key + "'");
                mergeProperty(propVal, mergeVal);
                continue;
            }

            // 情况3：都是数字，智能合并
            if(typeof mergeVal == "number" && typeof propVal == "number") {
                var oldVal:Number = propVal;
                // 有负数存在：取最小值（负数debuff优先）
                if(mergeVal < 0 || propVal < 0) {
                    prop[key] = Math.min(propVal, mergeVal);
                    // _root.服务器.发布服务器消息("    [Merge] 智能合并(负数) '" + key + "': " + oldVal + " + " + mergeVal + " -> " + prop[key]);
                } else {
                    // 都是正数：取最大值（正数buff优先）
                    prop[key] = Math.max(propVal, mergeVal);
                    // _root.服务器.发布服务器消息("    [Merge] 智能合并(正数) '" + key + "': " + oldVal + " + " + mergeVal + " -> " + prop[key]);
                }
                continue;
            }

            // 情况4：其他类型（字符串等），直接覆盖
            // _root.服务器.发布服务器消息("    [Merge] 覆盖属性 '" + key + "': " + propVal + " -> " + mergeVal);
            prop[key] = mergeVal;
        }
    }
}
