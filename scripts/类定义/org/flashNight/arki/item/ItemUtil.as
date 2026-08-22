// import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.neur.Server.ServerManager;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

import org.flashNight.naki.Sort.QuickSort;

/*
 * ItemUtil 静态类，存储物品数据与物品工具函数
 *
 * ========================================
 * 待修复问题列表 (2025-01-17)
 * ========================================
 *
 * 【高优先级】
 * 1. ItemCollection.getValue() 类型混淆风险
 *    - 位置：ItemCollection.as:30-34
 *    - 问题：返回值可能是 Number（非装备）或 Object（装备），调用方无法区分
 *    - 风险：对返回值进行数值计算时可能产生 NaN
 *    - 建议：分拆为 getItemQuantity() 和 getEquipmentData() 两个方法
 *
 * 【中等优先级】
 * 2. ArrayInventory.getTotal() 隐含类型假设
 *    - 位置：ArrayInventory.as:179-188
 *    - 问题：使用 isNaN() 隐含区分装备/非装备，缺乏显式检查
 *    - 建议：添加 typeof item.value === 'number' 的显式类型检查
 *
 * 3. ItemSortUtil.isStackable() 空值检查不完整
 *    - 位置：ItemSortUtil.as:180-186
 *    - 问题：未检查 null/undefined，可能导致误判
 *    - 建议：添加 !== null && !== undefined 检查
 *
 * 4. 改造系统类型验证缺失
 *    - 位置：UI交互_无名氏_改造系统.as:42-50
 *    - 问题：假设改装清单物品 value 必为 Number，但缺乏验证
 *    - 建议：添加类型检查确保安全
 *
 * 【已完成】
 * ✓ BaseItem.create() 硬编码等级上限问题（已修复，使用EquipmentUtil.getMaxLevel()动态获取）
 * ✓ ItemIcon 满级框硬编码问题（已修复，使用EquipmentUtil.getMaxLevel()动态判断）
 * ✓ ItemUtil.contain() 装备强化等级判断bug（已修复，见444-515行）
 * ✓ Inventory.addValue() 添加使用约定文档（已添加详细注释）
 *
 * ========================================
 */

class org.flashNight.arki.item.ItemUtil{
    private static var MAX_SAFE_COLLECTION_QUANTITY:Number = 9007199254740991;
    
    public static var itemDataDict:Object;
    public static var balanceDataDict:Object; // balance 审计投影独立存放，避免常规物品克隆携带
    public static var itemDataArray:Array;
    public static var itemNamesByID:Object;
    public static var maxID:Number;

    public static var equipmentDict:Object; // 装备字典，快速判断物品是否为武器或防具
    public static var materialDict:Object; // 材料字典，快速判断物品是否为材料
    public static var informationMaxValueDict:Object; // 情报持有上限字典，可以顺便判断物品是否为情报
    public static var multiTierDict:Object; // 进阶字典，检查物品是否存进多阶属性
    public static var itemSetDict:Object; // 套装 ID → 权威展示信息与成员列表
    public static var itemSetByItem:Object; // 物品名 → 套装投影
    public static var itemSetConfigDict:Object; // 套装 ID → item_sets.xml 完整配置

    /**
     * 按 item_sets.xml 中心表补齐逐物品套装展示字段。
     * 保持旧 AS2 → Host → Web 投影协议不变。
     */
    public static function hydrateItemSetMetadata(combinedData):Void {
        var itemSetCatalog:Object = new Object();
        var itemSetConfigs:Object = new Object();
        var rawItemSetEntries = combinedData.itemSets;
        var itemSetEntries:Array = new Array();
        if (rawItemSetEntries instanceof Array) {
            itemSetEntries = rawItemSetEntries;
        } else if (rawItemSetEntries != undefined && rawItemSetEntries != null) {
            itemSetEntries.push(rawItemSetEntries);
        }
        for (var catalogIndex:Number = 0; catalogIndex < itemSetEntries.length; catalogIndex++) {
            var catalogEntry:Object = itemSetEntries[catalogIndex];
            var catalogId:String = catalogEntry.id == undefined ? "" : String(catalogEntry.id);
            if (catalogId == "") continue;
            var catalogOrder:Number = Number(catalogEntry.order);
            if (isNaN(catalogOrder)) catalogOrder = 0;
            itemSetCatalog[catalogId] = {
                id:catalogId,
                name:catalogEntry.name == undefined ? "" : String(catalogEntry.name),
                order:catalogOrder
            };
            itemSetConfigs[catalogId] = catalogEntry;
        }
        for (var itemIndex in combinedData) {
            if (itemIndex == "itemSets") continue;
            var itemData:Object = combinedData[itemIndex];
            var itemSetId:String = itemData.setId == undefined ? "" : String(itemData.setId);
            if (itemSetId == "") continue;
            var itemSetMeta:Object = itemSetCatalog[itemSetId];
            if (itemSetMeta != undefined) {
                itemData.setName = itemSetMeta.name;
                itemData.setOrder = itemSetMeta.order;
            } else if (itemSetEntries.length > 0) {
                trace("[ItemUtil] 未找到套装元数据: item=" + itemData.name + ", setId=" + itemSetId);
                delete itemData.setName;
                delete itemData.setOrder;
            }
        }
        itemSetConfigDict = itemSetConfigs;
        _root.物品套装配置索引 = itemSetConfigs;
    }


    /*
     * 加载物品数据
     */
    public static function loadItemData(combinedData):Void{
        var _itemDataDict = new Object();
        var _balanceDataDict = new Object();
        var _itemDataArray = new Array();
        var _itemNamesByID = new Object();
        var _maxID = 0;
        var _equipmentDict = new Object();
        var _materialDict = new Object();
        var _informationMaxValueDict = new Object();
        var _multiTierDict = {};
        var multiTierList = EquipmentUtil.tierDataList;
        for(var tierIndex = 0; tierIndex < multiTierList.length; tierIndex++){
            _multiTierDict[multiTierList[tierIndex]] = {};
        }

        // item_sets.xml 是套装展示元数据的单一权威；物品 XML 只声明 setId。
        // 测试夹具可继续直接携带 setName/setOrder，因此缺少目录时保持兼容。
        hydrateItemSetMetadata(combinedData);

        // 自动生成ID：完全忽略XML中的ID配置
        var autoIncrementID = 1;

        for(var i in combinedData){
            if (i == "itemSets") continue;
            var itemData = combinedData[i];
            var itemName = itemData.name;

            // balance 是严格校验后才能投影的审计元数据，不参与战斗物品克隆。
            // 只保留独立原始索引，不提供嵌入 itemData 的 fallback。
            if(itemData.balance !== undefined){
                _balanceDataDict[itemName] = itemData.balance;
                delete itemData.balance;
            }

            // 自动分配ID（忽略XML中的ID）
            itemData.id = autoIncrementID++;

            _itemDataDict[itemName] = itemData;
            _itemNamesByID[itemData.id] = itemName;
            _itemDataArray.push(itemData);
            if(itemData.id > _maxID) _maxID = itemData.id;
            if(itemData.type === "武器" || itemData.type === "防具") {
                _equipmentDict[itemName] = true;
                for(var tierIndex = 0; tierIndex < multiTierList.length; tierIndex++){
                    if(itemData[multiTierList[tierIndex]]){
                        _multiTierDict[multiTierList[tierIndex]][itemName] = true;
                    }
                }
                // 快速生成槽位数据
                if(itemData.data.modslot == null){
                    itemData.data.modslot = getDefaultModSlot(itemData);
                }
            }
            else if(itemData.use === "材料") _materialDict[itemName] = true;
            else if(itemData.use === "情报") _informationMaxValueDict[itemName] = itemData.maxvalue;
        }

        // 由于for...in遍历是反序的，需要反转数组以保持XML中的正序
        // 这样可以通过调整XML中物品的位置来直观控制显示顺序
        _itemDataArray.reverse();

        // 套装成员只从物品 XML 的显式 setId 派生；名称与排序已由中心表注入。
        // 按已恢复的 XML 顺序建索引，保证各界面对同槽变体的展示顺序一致。
        var _itemSetDict:Object = new Object();
        var _itemSetByItem:Object = new Object();
        for (var setIndex:Number = 0; setIndex < _itemDataArray.length; setIndex++) {
            var setItemData:Object = _itemDataArray[setIndex];
            var setId:String = setItemData.setId == undefined ? "" : String(setItemData.setId);
            var setName:String = setItemData.setName == undefined ? "" : String(setItemData.setName);
            if (setId == "" || setName == "") continue;
            var setGroup:Object = _itemSetDict[setId];
            if (setGroup == undefined) {
                var setOrder:Number = Number(setItemData.setOrder);
                if (isNaN(setOrder)) setOrder = 0;
                setGroup = {id:setId, name:setName, order:setOrder, items:[], itemsByUse:{}};
                _itemSetDict[setId] = setGroup;
            }
            setGroup.items.push(setItemData.name);
            var setUse:String = setItemData.use == undefined || String(setItemData.use) == "" ? "其他" : String(setItemData.use);
            if (setGroup.itemsByUse[setUse] == undefined) setGroup.itemsByUse[setUse] = [];
            setGroup.itemsByUse[setUse].push(setItemData.name);
            _itemSetByItem[setItemData.name] = {id:setGroup.id, name:setGroup.name, order:setGroup.order};
        }

        itemDataDict = _itemDataDict;
        balanceDataDict = _balanceDataDict;
        itemDataArray = _itemDataArray;
        itemNamesByID = _itemNamesByID;
        maxID = _maxID;
        equipmentDict = _equipmentDict;
        materialDict = _materialDict;
        informationMaxValueDict = _informationMaxValueDict;
        multiTierDict = _multiTierDict;
        itemSetDict = _itemSetDict;
        itemSetByItem = _itemSetByItem;
        _root.物品属性列表 = _itemDataDict;
        _root.物品属性数组 = _itemDataArray;
        _root.物品套装索引 = _itemSetDict;
        _root.id物品名对应表 = _itemNamesByID;
        _root.物品最大id = _maxID;
        _root.物品总数 = _itemDataDict.length;
    }



    /**
     * 获取物品数据（返回克隆副本）
     *
     * 【性能优化 2024-12-25】
     * 使用 cloneFast 替代 clone，因为物品数据满足以下条件：
     * - 无循环引用（纯数据结构，来自 XML 解析）
     * - 嵌套层级浅（最多2-3层）
     * - 主要是原始类型（Number, String）
     * - 原型链干净（无需 hasOwnProperty 检查）
     *
     * 预计性能提升：克隆耗时从 ~42ms 降至 ~15-20ms（24单位批次）
     */
    public static function getItemData(index):Object{
        if (index.__proto__ == String.prototype) return ObjectUtil.cloneFast(ItemUtil.itemDataDict[index]);
        if (index.__proto__ == Number.prototype) return ObjectUtil.cloneFast(ItemUtil.itemDataDict[itemNamesByID[index]]);
        return null;
    }

    /*
     * 获取物品数据（返回原始数据，不进行拷贝）
     * as2不支持protected，原则上只能在高性能需求时谨慎使用
     */
    public static function getRawItemData(index):Object{
        if (index.__proto__ == String.prototype) return ItemUtil.itemDataDict[index];
        if (index.__proto__ == Number.prototype) return ItemUtil.itemDataDict[itemNamesByID[index]];
        return null;
    }

    /**
     * 获取物品的原始 balance 容器。返回值只供严格校验与展示投影使用，
     * 不并入 getRawItemData/getItemData，也不应被游戏性能修改。
     */
    public static function getRawBalanceData(index):Object{
        if (index.__proto__ == String.prototype) return ItemUtil.balanceDataDict[index];
        if (index.__proto__ == Number.prototype) return ItemUtil.balanceDataDict[itemNamesByID[index]];
        return null;
    }

    /**
     * 返回物品的只读套装投影；未标注物品返回 null。
     */
    public static function getItemSet(name:String):Object{
        var projection:Object = itemSetByItem[name];
        return projection == undefined ? null : projection;
    }



    /*
     * 辅助函数，判断物品是否存在
     */
    public static function isItem(name:String):Boolean{
        return itemDataDict[name] != null;
    }

    /*
     * 三个辅助函数，判断物品是否为武器或防具 / 材料 / 情报
     */
    public static function isEquipment(name:String):Boolean{
        return equipmentDict[name] === true;
    }
    public static function isMaterial(name:String):Boolean{
        return materialDict[name] === true;
    }
    public static function isInformation(name:String):Boolean{
        return informationMaxValueDict[name] > 0;
    }
    /**
     * 返回某情报仍可安全写入的数量。交易与奖励预览必须以此为权威容量，不能依赖
     * InformationCollection 的末端 clamp，否则会出现按请求量扣款、按剩余量入账。
     */
    public static function getInformationRemaining(name:String):Number{
        var maximum:Number = Number(informationMaxValueDict[name]);
        if(isNaN(maximum) || maximum <= 0) return 0;
        var current:Number = 0;
        var collection:Object = _root.收集品栏 == undefined ? undefined : _root.收集品栏.情报;
        if(collection != undefined && typeof collection.getValue == "function") {
            current = Number(collection.getValue(name));
            if(isNaN(current) || current < 0) current = 0;
        }
        return Math.max(0, Math.floor(maximum - current));
    }

    /**
     * 以物品自身配置的 maxvalue 规划一次情报写入。超出部分按物品 price
     * 折算为金币；price 为 0 的剧情情报只截断，不制造无价值拾取物。
     */
    public static function planInformationAcquire(name:String, requested:Number):Object{
        requested = Number(requested);
        if(!isInformation(name) || isNaN(requested) || requested <= 0
                || requested != Math.floor(requested)) {
            return {valid:false, name:name, requested:requested,
                accepted:0, overflow:0, money:0, unitPrice:0, remaining:0};
        }
        var remaining:Number = getInformationRemaining(name);
        var accepted:Number = Math.min(requested, remaining);
        var overflow:Number = requested - accepted;
        var raw:Object = getRawItemData(name);
        var unitPrice:Number = raw == null ? 0 : Math.floor(Number(raw.price));
        if(isNaN(unitPrice) || unitPrice < 0) unitPrice = 0;
        return {
            valid:true,
            name:name,
            requested:requested,
            accepted:accepted,
            overflow:overflow,
            money:overflow * unitPrice,
            unitPrice:unitPrice,
            remaining:remaining,
            maximum:Number(informationMaxValueDict[name])
        };
    }

    /**
     * 奖励结算专用规划：同一批奖励中的重复情报共享剩余容量，全部超出量统一
     * 折算进金币项。该函数只读，不修改奖励数组或存档。
     */
    public static function planRewardAcquire(itemArray:Array):Object{
        if(!(itemArray instanceof Array)) return null;
        var items:Array = [];
        var conversions:Array = [];
        var reservedRemaining:Object = {};
        var moneyIndex:Number = -1;
        var overflowMoney:Number = 0;
        var hasOverflow:Boolean = false;

        for(var i:Number = 0; i < itemArray.length; i++){
            var source:Object = itemArray[i];
            if(source == null || source.name == undefined) return null;
            var name:String = String(source.name);
            var value:Number = Number(source.value);
            if(isInformation(name)){
                if(isNaN(value) || value <= 0 || value != Math.floor(value)) return null;
                var remaining:Number;
                if(reservedRemaining[name] == undefined) remaining = getInformationRemaining(name);
                else remaining = Number(reservedRemaining[name]);
                var accepted:Number = Math.min(value, remaining);
                var overflow:Number = value - accepted;
                reservedRemaining[name] = remaining - accepted;
                var raw:Object = getRawItemData(name);
                var unitPrice:Number = raw == null ? 0 : Math.floor(Number(raw.price));
                if(isNaN(unitPrice) || unitPrice < 0) unitPrice = 0;
                var convertedMoney:Number = overflow * unitPrice;
                overflowMoney += convertedMoney;
                if(overflow > 0) hasOverflow = true;
                conversions.push({
                    name:name,
                    requested:value,
                    accepted:accepted,
                    overflow:overflow,
                    money:convertedMoney,
                    unitPrice:unitPrice
                });
                if(accepted <= 0) continue;
                value = accepted;
            }

            if(name == "金币"){
                if(moneyIndex < 0){
                    moneyIndex = items.length;
                    items.push({name:"金币", value:value});
                }else{
                    items[moneyIndex].value += value;
                }
                continue;
            }

            var planned:Object = {name:name, value:value};
            if(source.tier != undefined) planned.tier = source.tier;
            if(source.isQuantity != undefined) planned.isQuantity = source.isQuantity;
            items.push(planned);
        }

        if(overflowMoney > 0){
            if(moneyIndex < 0) items.push({name:"金币", value:overflowMoney});
            else items[moneyIndex].value += overflowMoney;
        }
        return {
            success:false,
            items:items,
            conversions:conversions,
            overflowMoney:overflowMoney,
            hasOverflow:hasOverflow
        };
    }

    /**
     * 任务、成就与脚本奖励的原子入口。商城和合成仍使用 acquire() 的严格容量
     * 语义，避免先扣款再折算。
     */
    public static function acquireReward(itemArray:Array, context:Object):Object{
        var plan:Object = planRewardAcquire(itemArray);
        if(plan == null){
            return {success:false, error:"invalid_reward", items:[],
                conversions:[], overflowMoney:0, hasOverflow:false};
        }
        if(plan.items.length == 0){
            plan.success = true;
            return plan;
        }
        plan.success = acquire(plan.items, context);
        if(!plan.success) plan.error = "inventory_full";
        return plan;
    }
    /*
     * 辅助函数，判断装备物品是否存在进阶数据
     */
    public static function hasTier(name:String, tier:String):Boolean{
        return multiTierDict[tier][name] === true;
    }

    /*
     * 辅助函数，快速判断装备物品的配件槽数量
     * 1-11级：3槽
     * 12-29级：2槽
     * 30+级：1槽
     */
     public static function getDefaultModSlot(itemData:Object):Number{
        if(itemData.use === "颈部装备") return 0;
        var level = itemData.data.level;
        if(level < 12) return 3;
        if(level < 30) return 2;
        return 1;
     }



    /*
     * 玩家的物品移动操作
     */
    //将物品移入另一物品栏
    public static function moveItemToInventory(icon1,icon2):Boolean{
        if(!icon1.item || icon1 === icon2) return false;
        var targetItem = icon2.item;
        var result;
        if(!icon2.item){
            result = icon1.collection.move(icon2.collection,icon1.index,icon2.index);
        }else if (icon1.name == icon2.name && icon1.itemData.type == "消耗品"){
            result = icon1.collection.merge(icon2.collection,icon1.index,icon2.index);
        }else{
            result = icon1.collection.swap(icon2.collection,icon1.index,icon2.index);
        }
        _root.存档系统.dirtyMark = true;
        return result;
    }

    // 将物品移入装备栏
    public static function moveItemToEquipment(icon, equipmentIcon, index):Boolean{
        if(index != equipmentIcon.index) return false;
        var itemData = icon.item.getData();
        if (itemData.data.level > _root.等级){
            _root.发布消息("等级低于装备限制，无法装备！");
            return false;
        }
        var result = ItemUtil.moveItemToInventory(icon,equipmentIcon);
        if(!result) return false;
        //
        var 音效 = "9mmclip2.wav";
        var use = itemData.use;
        if(itemData.type == "防具"){
            音效 = "ammopickup1.wav";
            // if (use == "颈部装备"){
            //     var 控制对象 = TargetCacheManager.findHero();
            //     控制对象.称号 = itemData.data.title;
            //     _root.玩家称号 = 控制对象.称号;
            // }
        }
        _root.soundEffectManager.playSound(音效);
        _root.发布消息("成功装备[" + use + "][" + itemData.displayname + "]");
        _root.刷新人物装扮(_root.控制目标);
        _root.存档系统.dirtyMark = true;
        return true;
    }

    // 将物品移入药剂栏
    public static function moveItemToDrug(icon,drugIcon):Boolean{
        if(!drugIcon.isCoolDown()) return false;
        var result = ItemUtil.moveItemToInventory(icon,drugIcon);
        _root.存档系统.dirtyMark = true;
        return result;
    }


    /*
     * 物品获得与提交
     * 基础方法共4个：require, acquire, contain, submit
     */

    // 根据原版物品数据生成itemRequirement
    public static function getRequirement(itemArray:Array):Array{
        var newArray = new Array(itemArray.length);
        for(var i = 0; i<itemArray.length; i++){
            newArray[i] = {name:itemArray[i][0], value:itemArray[i][1]};
        }
        return newArray;
    }

    // 根据任务文件内的物品字符串生成itemRequirement
    // 支持 ## 语法表示数量需求（而非强化度需求）
    // 支持 #阶数 格式指定装备进阶（如：白色中山上装#1#二阶）
    public static function getRequirementFromTask(itemArray:Array):Array{
        var newArray = new Array(itemArray.length);
        for(var i = 0; i < itemArray.length; i++){
            var itemStr = itemArray[i];
            var isQuantity = false;  // 标记是否为数量需求
            var arr;

            // 检查是否使用 ## 语法（明确的数量需求）
            if(itemStr.indexOf("##") != -1){
                arr = itemStr.split("##");
                isQuantity = true;  // ## 表示数量需求
            } else {
                arr = itemStr.split("#");
                // 对于单个 #，保持原有逻辑（装备=强化度，非装备=数量）
            }

            var itemObj:Object = {
                name: arr[0],
                value: Number(arr[1]),
                isQuantity: isQuantity  // 新增标记字段
            };
            
            // 解析进阶信息（arr[2] 表示进阶，如"二阶"、"三阶"等）
            if(arr[2] != undefined && arr[2] != ""){
                itemObj.tier = arr[2];
            }
            
            newArray[i] = itemObj;
        }
        return newArray;
    }

    /*
     * require 函数检索背包是否有足够空位装下物品。
     * 输入值为一个物品数组
     * 返回带有背包、装备栏、药剂栏、材料、情报与货币/成长字段的 Object。
     * 装备栏当前只记录“获取同名手雷时补充已装备堆”的窄路由。
     * 若背包空间不足，返回null
     */
    public static function require(itemArray:Array):Object {
        var list = {金币:0, K点:0, 经验值:0, 技能点:0, 背包:{}, 装备栏:{}, 药剂栏:{}, 材料:{}, 情报:{}};
        var mergables:Object = {}; // 用来累计可合并物品的需求：键为物品名，值为总需求数量
        var nonMergeableList:Array = []; // 不可合并物品（如武器、防具）—必须占用新格子

        // 遍历要求数组，区分材料、情报、可合并与不可合并物品
        for(var i = 0; i < itemArray.length; i++){
            var name:String = itemArray[i].name;
            var value:Number = Number(itemArray[i].value);
            if(name == "金币" || name == "K点" || name == "经验值" || name == "技能点"){
                var scalarTotal:Number = Number(list[name]) + value;
                var scalarCurrent:Number;
                if(name == "金币") scalarCurrent = Number(_root.金钱);
                else if(name == "K点") scalarCurrent = Number(_root.虚拟币);
                else if(name == "经验值") scalarCurrent = Number(_root.经验值);
                else scalarCurrent = Number(_root.技能点数);
                if(isNaN(value) || !isFinite(value) || value <= 0
                        || Math.floor(value) != value
                        || isNaN(scalarTotal) || !isFinite(scalarTotal)
                        || Math.floor(scalarTotal) != scalarTotal
                        || scalarTotal > MAX_SAFE_COLLECTION_QUANTITY
                        || isNaN(scalarCurrent) || !isFinite(scalarCurrent)
                        || Math.floor(scalarCurrent) != scalarCurrent
                        || scalarCurrent + scalarTotal > MAX_SAFE_COLLECTION_QUANTITY) return null;
                // 同名标量奖励聚合，避免资产 last-wins、回执 merge-sum 的账实分叉。
                list[name] = scalarTotal;
                continue;
            }
            // 未知物品必须在任何写入前失败，不能由 BaseItem.create(null) 演化成
            // “实际未入包、调用方却收到成功与获得回执”。
            if(!isItem(name)) return null;
            if(isMaterial(name)){
                if(isNaN(value) || !isFinite(value) || value <= 0
                        || Math.floor(value) != value
                        || value > MAX_SAFE_COLLECTION_QUANTITY) return null;
                var materialTotal:Number = Number(list.材料[name] || 0) + value;
                var materialCurrent:Number = Number(_root.收集品栏.材料.getValue(name));
                if(isNaN(materialTotal) || !isFinite(materialTotal)
                        || Math.floor(materialTotal) != materialTotal
                        || materialTotal > MAX_SAFE_COLLECTION_QUANTITY
                        || isNaN(materialCurrent) || !isFinite(materialCurrent)
                        || materialCurrent < 0
                        || Math.floor(materialCurrent) != materialCurrent
                        || materialCurrent + materialTotal > MAX_SAFE_COLLECTION_QUANTITY) return null;
                list.材料[name] = materialTotal;
            } else if(isInformation(name)){
                var informationTotal:Number = Number(list.情报[name] || 0) + value;
                if(isNaN(informationTotal) || informationTotal <= 0
                        || informationTotal != Math.floor(informationTotal)
                        || informationTotal > getInformationRemaining(name)) return null;
                list.情报[name] = informationTotal;
            } else if(!isEquipment(name)){
                // 可合并物品
                var stackIncrement:Number = Number(value);
                var stackTotal:Number = Number(
                    mergables[name] == undefined ? 0 : mergables[name])
                    + stackIncrement;
                if(isNaN(stackIncrement) || !isFinite(stackIncrement)
                        || stackIncrement <= 0
                        || Math.floor(stackIncrement) != stackIncrement
                        || isNaN(stackTotal) || !isFinite(stackTotal)
                        || Math.floor(stackTotal) != stackTotal
                        || stackTotal > MAX_SAFE_COLLECTION_QUANTITY) return null;
                mergables[name] = stackTotal;
            } else {
                // 不可合并物品直接加入列表
                if(isNaN(value) || !isFinite(value) || value <= 0
                        || Math.floor(value) != value
                        || value > MAX_SAFE_COLLECTION_QUANTITY) return null;
                nonMergeableList.push(itemArray[i]);
            }
        }

        // 获取同名手雷时优先补充已装备堆；这一步先于药剂栏与背包，
        // 因而满包也不会阻断一个无需新格子的合法获取。
        var 装备栏:Object = _root.物品栏.装备栏;
        var equippedGrenade:Object = 装备栏 == undefined
            ? null : 装备栏.getItem("手雷");
        if(equippedGrenade != null
                && typeof equippedGrenade.name == "string"
                && mergables[equippedGrenade.name] != undefined){
            var grenadeIncrement:Number =
                Number(mergables[equippedGrenade.name]);
            var grenadeCurrent:Number = Number(equippedGrenade.value);
            var grenadeTotal:Number = grenadeCurrent + grenadeIncrement;
            if(isNaN(grenadeIncrement) || !isFinite(grenadeIncrement)
                    || grenadeIncrement <= 0
                    || Math.floor(grenadeIncrement) != grenadeIncrement
                    || isNaN(grenadeCurrent) || !isFinite(grenadeCurrent)
                    || grenadeCurrent <= 0
                    || Math.floor(grenadeCurrent) != grenadeCurrent
                    || isNaN(grenadeTotal) || !isFinite(grenadeTotal)
                    || Math.floor(grenadeTotal) != grenadeTotal
                    || grenadeTotal > MAX_SAFE_COLLECTION_QUANTITY){
                return null;
            }
            list.装备栏.手雷 = {
                name:String(equippedGrenade.name),
                value:grenadeIncrement
            };
            delete mergables[equippedGrenade.name];
        }

        // 得到药剂栏对象
        var 药剂栏:Object = _root.物品栏.药剂栏;
        var drugindexArr:Array = 药剂栏.getIndexes();
        var drugArr:Array = 药剂栏.getItemArray();
        // 这里默认能装进药剂栏的物品均可合并，检查药剂栏中是否已存在相同物品
        for(var i = 0; i < drugindexArr.length; i++){
            var drugItem:Object = drugArr[i];
            if(mergables[drugItem.name] != undefined){
                var drugCurrent:Number = Number(drugItem.value);
                var drugIncrement:Number = Number(mergables[drugItem.name]);
                var drugTotal:Number = drugCurrent + drugIncrement;
                if(isNaN(drugCurrent) || !isFinite(drugCurrent)
                        || drugCurrent <= 0
                        || Math.floor(drugCurrent) != drugCurrent
                        || isNaN(drugTotal) || !isFinite(drugTotal)
                        || Math.floor(drugTotal) != drugTotal
                        || drugTotal > MAX_SAFE_COLLECTION_QUANTITY) return null;
                // 记录：将原有合并堆增加新需求
                list.药剂栏[drugindexArr[i]] = {
                    name:drugItem.name,
                    value:drugIncrement
                };
                // 标记该物品已处理
                delete mergables[drugItem.name];
            }
        }
        
        // 得到背包对象
        var 背包:Object = _root.物品栏.背包;
        var indexArr:Array = 背包.getIndexes();
        var itemArr:Array = 背包.getItemArray();

        // 对于剩余的可合并物品，先检查背包中是否已存在相同物品
        for(var i = 0; i < itemArr.length; i++){
            var bagItem:Object = itemArr[i];
            if(mergables[bagItem.name] != undefined){
                var bagCurrent:Number = Number(bagItem.value);
                var bagIncrement:Number = Number(mergables[bagItem.name]);
                var bagTotal:Number = bagCurrent + bagIncrement;
                if(isNaN(bagCurrent) || !isFinite(bagCurrent)
                        || bagCurrent <= 0
                        || Math.floor(bagCurrent) != bagCurrent
                        || isNaN(bagTotal) || !isFinite(bagTotal)
                        || Math.floor(bagTotal) != bagTotal
                        || bagTotal > MAX_SAFE_COLLECTION_QUANTITY) return null;
                // 记录：将原有合并堆增加新需求
                list.背包[indexArr[i]] = {
                    name:bagItem.name,
                    value:bagIncrement
                };
                // 标记该物品已处理
                delete mergables[bagItem.name];
            }
        }

        // 对于剩余的可合并物品（在背包中尚无此类物品），加入不可合并列表
        for (var key:String in mergables) {
            nonMergeableList.push({ name: key, value: mergables[key] });
        }

        // 计算 mergeable items 的数量（不知道ds写这个干嘛）
        // var mergeableItemCount:Number = 0;
        // for (var key:String in mergables) {
        //     mergeableItemCount++;
        // }

        // 处理不可合并物品，要求必须有空位（依旧检查容量）
        var vacancyList:Array = 背包.getVacancies(nonMergeableList.length);
        if(isNaN(vacancyList.length) || vacancyList.length < nonMergeableList.length) return null;

        // 处理非合并物品的插入
        for(var i = 0; i < nonMergeableList.length; i++){
            list.背包[vacancyList[i]] = nonMergeableList[i];
        }

        // ServerManager.getInstance().sendServerMessage(ObjectUtil.stringify(list));
        return list;
    }




    /* 
     * acquire 函数处理获得物品事件。
     * 输入值为一个物品数组，经过require函数处理后，在对应的位置添加对应的物品。
     * 若成功获得所有物品，返回true
     * 若背包空间不足，返回false
     */
    public static function acquire(itemArray:Array, context:Object):Boolean {
        var list = ItemUtil.require(itemArray);
        if(list == null) return false;

        var acquireLastUpdate = new Date().getTime(); // 获取本次获得物品的时间戳

        // require 已锁定同名已装备手雷；任何异常都必须在货币、材料等写入前失败。
        var 装备栏:Object = _root.物品栏.装备栏;
        for(var equipmentKey:String in list.装备栏){
            var equipmentReq:Object = list.装备栏[equipmentKey];
            var equippedItem:Object = 装备栏.getItem(equipmentKey);
            if(equippedItem == null
                    || String(equippedItem.name) != String(equipmentReq.name)
                    || typeof equippedItem.value != "number") return false;
        }

        // 即使调用方没有显式领域事务，acquire 自身也要在首个资产写入前建立
        // 短事务，使升级强存盘延迟到同批货币/材料/背包全部写完之后。
        var assetTransaction:Object = PlayerAssetTransaction.current();
        var implicitAssetTransaction:Boolean = assetTransaction == null;
        if(implicitAssetTransaction) assetTransaction = PlayerAssetTransaction.begin(context);

        //获取
        if(list.金币 > 0) _root.金钱 += list.金币;
        if(list.K点 > 0) _root.虚拟币 += list.K点;
        if(list.经验值 > 0) {
            _root.经验值 += list.经验值;
            _root.主角是否升级(_root.等级,_root.经验值);
        }
        if(list.技能点 > 0) _root.技能点数 += list.技能点;

        // 已装备同名手雷的数量补充。保留原对象引用，并同步最后更新时间。
        for(var equipmentKey:String in list.装备栏){
            var equipmentReq:Object = list.装备栏[equipmentKey];
            装备栏.addValue(equipmentKey, Number(equipmentReq.value));
            装备栏.getItem(equipmentKey).update(acquireLastUpdate);
        }

        //材料
        var 材料 = _root.收集品栏.材料;
        for(var name in list.材料){
            var value = list.材料[name];
            if(材料.isEmpty(name)) 材料.add(name,value);
            else 材料.addValue(name,value);
        }

        //情报
        var 情报 = _root.收集品栏.情报;
        for(var name in list.情报){
            var value = list.情报[name];
            if(情报.isEmpty(name)) 情报.add(name,value);
            else 情报.addValue(name,value);
        }

        // 药剂栏
        var 药剂栏:Object = _root.物品栏.药剂栏; // DrugInventory 实例
        for(var key:String in list.药剂栏){
            var req:Object = list.药剂栏[key];
            var drugIndex:Number = Number(key);

            // 对于已有项，直接增加数量
            if(药剂栏.isEmpty(drugIndex)){
                // 格子为空的情况原则上不会触发
                var newDrugItem = BaseItem.create(req.name, req.value, acquireLastUpdate);
                药剂栏.add(drugIndex, newDrugItem);
            } else {
                // 已有物品更新数量和时间戳
                药剂栏.addValue(drugIndex, req.value);
                药剂栏.getItem(drugIndex).update(acquireLastUpdate); // 更新时间戳
            }
        }

        // 处理背包部分
        var 背包:Object = _root.物品栏.背包; // ArrayInventory 实例
        for(var key:String in list.背包){
            var req:Object = list.背包[key];
            // 如果 key 表示已有堆，则 key 是数字字符串；
            // 如果是新建 mergeable 物品，则 key 可设为 "-mergeable-" 开头
            if(key.indexOf("-mergeable-") == 0) {
                // 尝试查找是否已有同名物品
                var indexFoundStr:String = 背包.searchFirstKey(req.name);
                if(indexFoundStr != undefined) {
                    // 找到同名物品，合并到该位置
                    var indexFound:Number = Number(indexFoundStr);
                    背包.addValue(indexFound, req.value);
                    背包.getItem(indexFound).update(acquireLastUpdate); // 更新时间戳
                } else {
                    // 没有同名物品，创建新物品并添加到空格子
                    var newItem:BaseItem;
                    if(req.tier != undefined && ItemUtil.isEquipment(req.name)){
                        // 有进阶信息，使用 createFromString 保留 tier
                        var itemStr:String = req.name + "#" + req.value + "#" + req.tier;
                        newItem = BaseItem.createFromString(itemStr);
                        // createFromString 不会设置 lastUpdate，需要手动设置
                        if(newItem != null){
                            newItem.lastUpdate = acquireLastUpdate;
                        }
                    } else {
                        newItem = BaseItem.create(req.name, req.value, acquireLastUpdate);
                    }
                    背包.add(-1, newItem);
                }
            } else {
                // 对于已有项，直接增加数量
                var bagIndex:Number = Number(key);

                if(背包.isEmpty(bagIndex)){
                    // 如果该格子为空，添加新物品
                    var newItem:BaseItem;
                    if(req.tier != undefined && ItemUtil.isEquipment(req.name)){
                        // 有进阶信息，使用 createFromString 保留 tier
                        var itemStr:String = req.name + "#" + req.value + "#" + req.tier;
                        newItem = BaseItem.createFromString(itemStr);
                        // createFromString 不会设置 lastUpdate，需要手动设置
                        if(newItem != null){
                            newItem.lastUpdate = acquireLastUpdate;
                        }
                    } else {
                        newItem = BaseItem.create(req.name, req.value, acquireLastUpdate);
                    }
                    背包.add(bagIndex, newItem);
                } else {
                    // 已有物品更新数量和时间戳
                    背包.addValue(bagIndex, req.value);
                    背包.getItem(bagIndex).update(acquireLastUpdate); // 更新时间戳
                }
            }
        }

        // Plan A audit: acquire() 改 金币/K点/经验/技能点/材料/情报/装备栏/药剂栏/背包 全部 save-relevant
        // 字段，必须设 dirtyMark 让 SaveManager 知道需要落盘
        _root.存档系统.dirtyMark = true;
        // 可选消费者只看已完成写入后的 detached receipt；显式领域事务存在时先缓冲，
        // 由最外层 commit 决定是否发布，避免制作/交易回滚产生幽灵播报。
        PlayerAssetTransaction.recordItems("gain", itemArray, context);
        if(implicitAssetTransaction) PlayerAssetTransaction.commit(assetTransaction);
        return true;
    }


    /* 
     * cantain 函数检索玩家是否持有对应的物品。
     * 输入值为一个物品数组
     * 返回带有背包，材料，情报3个键的Object。记录玩家持有物品的位置和数量
     * 若对应栏位没有足够物品，返回null
     */
    public static function contain(itemArray:Array):Object{
        var list = {背包:{},材料:{},情报:{},药剂栏:{}};
        var 背包 = _root.物品栏.背包;
        var 材料 = _root.收集品栏.材料;
        var 情报 = _root.收集品栏.情报;
        var 药剂栏 = _root.物品栏.药剂栏;
        var inventoryItems = {};
        //
        for(var i = 0; i < itemArray.length; i++){
            var name = itemArray[i].name;
            var value = itemArray[i].value;
            var isQuantity = itemArray[i].isQuantity;  // 获取数量标记
            if(isMaterial(name)){
                if(材料.getValue(name) < value) return null;
                list.材料[name] = value;
            }else if(isInformation(name)){
                if(情报.getValue(name) < value) return null;
                list.情报[name] = value;
            }else{
                /*
                 * 背包和药剂栏物品检查
                 *
                 * 【Bug修复说明】
                 * 物品重构后，装备和非装备物品的 value 字段含义不同：
                 * - 装备物品：value 是 Object {level: 强化等级, ...}
                 * - 非装备物品：value 是 Number（数量）
                 *
                 * 在合成系统中，"K5项链#13" 会被解析为 {name: "K5项链", value: 13}
                 * 这里的 13 是数字，表示需要的强化等级。
                 *
                 * 【原Bug原因】
                 * 旧代码没有正确分离装备和非装备的判断逻辑，导致：
                 * 1. 当装备强化等级不足时（如+1 < +13）
                 * 2. 会跳过第一个if，执行到 value -= bagItem.value
                 * 3. 计算 13 - {level:1} 得到 NaN
                 * 4. 最后检查 if(value > 0)，但 NaN > 0 为 false
                 * 5. 函数不会返回null，导致检查错误通过！
                 *
                 * 【修复方案】
                 * 1. 对装备物品单独处理，强化等级不足时直接 continue
                 * 2. 避免执行 value -= bagItem.value 导致 NaN
                 * 3. 最终检查改为 if(isNaN(value) || value > 0) 防止 NaN 绕过检查
                 */
                var indexArr = 背包.getIndexes();
                for(var arri:Number = 0; arri < indexArr.length; arri++){
                    var index = indexArr[arri];
                    var bagItem = 背包.getItem(index);
                    if(name != bagItem.name) continue;

                    // 装备物品处理
                    if(isEquipment(name)){
                        // 如果明确标记为数量需求（使用##语法），则计算装备数量
                        if(isQuantity){
                            // 装备数量模式：累计装备个数
                            list.背包[index] = 1;  // 记录此格有1个装备
                            value -= 1;  // 需求数量减1
                            if(value <= 0){
                                value = 0;
                                break;
                            }
                            continue;
                        } else {
                            // 强化度模式（原有逻辑）：检查强化等级
                            if(bagItem.value.level >= value){
                                // 强化等级满足需求，记录此装备
                                list.背包[index] = value;
                                value = 0;
                                break;
                            }
                            // 强化等级不够，继续查找其他格子
                            // 关键：必须 continue，否则会执行后面的数量计算导致 NaN
                            continue;
                        }
                    }

                    // 非装备物品：检查数量（value 是 Number）
                    if(bagItem.value >= value){
                        list.背包[index] = value;
                        value = 0;
                        break;
                    }
                    list.背包[index] = bagItem.value;
                    value -= bagItem.value;
                }

                var drugindexArr:Array = 药剂栏.getIndexes();
                // var drugArr:Array = 药剂栏.getItemArray();
                for(var j = 0; j < drugindexArr.length; j++){
                    var index = drugindexArr[j];
                    // var drugItem:Object = drugArr[j];
                    var drugItem:Object = 药剂栏.getItem(index);
                    if(name != drugItem.name) continue;
                    if(drugItem.value >= value){
                        list.药剂栏[index] = value;
                        value = 0;
                        break;
                    }
                    list.药剂栏[index] = drugItem.value;
                    value -= drugItem.value;
                }

                // 检查是否还有剩余需求未满足
                // 关键：使用 isNaN 防止 NaN 导致的误判（NaN > 0 为 false）
                if(isNaN(value) || value > 0) return null;
            }
        }
        return list;
    }
    
    /*
     * submit 函数处理提交物品事件。
     * 输入值为一个物品数组，经过contain函数处理后，在背包和材料栏对应的位置移除对应数量的物品。情报栏的物品不会被submit函数移除
     * 若成功移除所有物品，返回true
     * 若背包和材料栏没有足够物品，返回false
     * 支持装备数量扣除（使用##语法时）
     */
    public static function submit(itemArray:Array, context:Object):Boolean{
        var list = ItemUtil.contain(itemArray);
        if(list == null) return false;
        var wrote:Boolean = false;
        var committedLosses:Array = [];
        //材料
        var 材料 = _root.收集品栏.材料;
        for(var name in list.材料){
            var value = list.材料[name];
            材料.addValue(name,-value);
            committedLosses.push({name:name, value:value, kind:"material"});
            wrote = true;
        }
        //情报不需要提交
        // var 情报 = _root.收集品栏.情报;
        // for(var name in list.情报){
        //     var value = list.情报[name];
        //     情报.addValue(name,-value);
        // }
        //背包
        var 背包 = _root.物品栏.背包;
        // 需要根据原始需求判断是否为数量模式
        var itemMap = {};  // 创建映射以获取原始需求信息
        for(var k = 0; k < itemArray.length; k++){
            itemMap[itemArray[k].name] = itemArray[k];
        }

        for(var i in list.背包){
            var item = 背包.getItem(i);
            var originalReq = itemMap[item.name];
            var removedName:String = String(item.name);
            var removedValue:Number = Number(list.背包[i]);
            var removedEquipment:Boolean = isEquipment(removedName);

            // 如果是装备且使用##语法（数量模式），或者是装备但list中记录的是1（数量模式的标记）
            if(isNaN(item.value) || (isEquipment(item.name) && list.背包[i] == 1 && originalReq && originalReq.isQuantity)){
                背包.remove(i);  // 移除整个装备
            } else {
                背包.addValue(i, -list.背包[i]);  // 减少数量
            }
            var lossEntry:Object = {
                name:removedName,
                value:removedEquipment ? 1 : removedValue
            };
            if (removedEquipment) {
                lossEntry.kind = "equip";
                lossEntry.isQuantity = true;
                if (item.value != null && item.value.tier != undefined) {
                    lossEntry.tier = item.value.tier;
                }
            }
            committedLosses.push(lossEntry);
            wrote = true;
        }
        //药剂栏
        var 药剂栏 = _root.物品栏.药剂栏;
        for(var i in list.药剂栏){
            var item = 药剂栏.getItem(i);
            var removedDrugName:String = String(item.name);
            var removedDrugValue:Number = Number(list.药剂栏[i]);
            if(isNaN(item.value)) 药剂栏.remove(i);
            else 药剂栏.addValue(i, -list.药剂栏[i]);
            committedLosses.push({name:removedDrugName, value:removedDrugValue});
            wrote = true;
        }
        if(wrote && _root.存档系统) _root.存档系统.dirtyMark = true;
        if(wrote) PlayerAssetTransaction.recordItems("loss", committedLosses, context);
        return true;
    }

    //检索是否能放入单个物品
    public static function singleRequire(__name:String,__value:Number):Object{
        return ItemUtil.require([{name:__name,value:__value}]);
    }
    //获得单个物品
    public static function singleAcquire(__name:String,__value:Number, context:Object):Boolean{
        return ItemUtil.acquire([{name:__name,value:__value}], context);
    }
    //检索是否持有单个物品
    public static function singleContain(__name:String,__value:Number):Object{
        return ItemUtil.contain([{name:__name,value:__value}]);
    }
    //提交单个物品
    public static function singleSubmit(__name:String,__value:Number, context:Object):Boolean{
        return ItemUtil.submit([{name:__name,value:__value}], context);
    }

    
    
    //查找物品总数
    public static function getTotal(__name:String):Number{
        if(isMaterial(__name)) return _root.收集品栏.材料.getValue(__name);
        if(isInformation(__name)) return _root.收集品栏.情报.getValue(__name);
        //遍历背包
        var 背包 = _root.物品栏.背包;
        var total = 0;
        var indexArr = 背包.getIndexes();
        for(var i:Number = 0; i < indexArr.length; i++){
            var index = indexArr[i];
            var bagItem = 背包.getItem(index);
            if(bagItem.name == __name){
                total += isNaN(bagItem.value) ? 1 : bagItem.value;
            }
        }
        return total;
    }
}

//org.flashNight.arki.item.ItemUtil.acquire()
