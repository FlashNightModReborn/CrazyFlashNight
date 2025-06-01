// import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.neur.Server.ServerManager;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/*
 * ItemUtil 静态类，存储物品数据与物品工具函数
 * 
 */

class org.flashNight.arki.item.ItemUtil{
    
    public static var itemDataDict:Object;
    public static var itemDataArray:Array;
    public static var itemNamesByID:Object;
    public static var maxID:Number;
    public static var informationMaxValueDict:Object;


    /*
     * 获取物品数据
     */
    public static function getItemData(index){
        if (index.__proto__ == String.prototype) return ObjectUtil.clone(ItemUtil.itemDataDict[index]);
        if (index.__proto__ == Number.prototype) return ObjectUtil.clone(ItemUtil.itemDataDict[itemNamesByID[index]]);
    }

    /*
     * 获取物品数据（返回原始数据，不进行拷贝）
     * as2不支持protected，原则上只能在高性能需求时谨慎使用
     */
    public static function getRawItemData(index){
        if (index.__proto__ == String.prototype) return ItemUtil.itemDataDict[index];
        if (index.__proto__ == Number.prototype) return ItemUtil.itemDataDict[itemNamesByID[index]];
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
        return result;
    }

    //将物品移入装备栏
    public static function moveItemToEquipment(icon,equipmentIcon,index):Boolean{
        if(index != equipmentIcon.index) return false;
        var itemData = icon.itemData;
        if (itemData.level > _root.等级)
        {
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
            if (use == "颈部装备"){
                var 控制对象 = TargetCacheManager.findHero();
                控制对象.称号 = itemData.equipped.title;
                _root.玩家称号 = 控制对象.称号;
            }
        }
        // _root[index] = name;
        _root.播放音效(音效);
        _root.发布消息("成功装备[" + use + "][" + itemData.displayname + "]");
        _root.刷新人物装扮(_root.控制目标);
        return true;
    }

    //将物品移入药剂栏
    public static function moveItemToDrug(icon,drugIcon):Boolean{
        if(!drugIcon.isCoolDown()) return false;
        var result = ItemUtil.moveItemToInventory(icon,drugIcon);
        return result;
    }


    /*
     * 物品获得与提交
     * 基础方法共4个：require, acquire, contain, submit
     */

    //根据原版物品数据生成itemRequirement
    public static function getRequirement(itemArray:Array):Array{
        var newArray = new Array(itemArray.length);
        for(var i = 0; i<itemArray.length; i++){
            newArray[i] = {name:itemArray[i][0], value:itemArray[i][1]};
        }
        return newArray;
    }

    //根据任务文件内的物品字符串生成itemRequirement
    public static function getRequirementFromTask(itemArray:Array):Array{
        var newArray = new Array(itemArray.length);
        for(var i = 0; i < itemArray.length; i++){
            var arr = itemArray[i].split("#");
            newArray[i] = {name:arr[0], value:Number(arr[1])};
        }
        return newArray;
    }

    /*
     * require 函数检索背包是否有足够空位装下物品。
     * 输入值为一个物品数组
     * 返回带有背包，材料，情报，金币，K点，经验值，技能点7个键的Object。其中背包，材料，情报三项内记录要进行操作的物品栏位和对应物品
     * 若背包空间不足，返回null
     */
    public static function require(itemArray:Array):Object {
        var list = {金币:0, K点:0, 经验值:0, 技能点:0, 背包:{}, 药剂栏:{}, 材料:{}, 情报:{}};
        var mergables:Object = {}; // 用来累计可合并物品的需求：键为物品名，值为总需求数量
        var nonMergeableList:Array = []; // 不可合并物品（如武器、防具）—必须占用新格子

        // 遍历要求数组，区分材料、情报、可合并与不可合并物品
        for(var i = 0; i < itemArray.length; i++){
            var name:String = itemArray[i].name;
            var value:Number = itemArray[i].value;
            if(name == "金币" || name == "K点" || name == "经验值" || name == "技能点"){
                list[name] = value;
                continue;
            }
            var itemData:Object = ItemUtil.getItemData(name);
            if(itemData.use == "材料"){
                list.材料[name] = value;
            } else if(itemData.use == "情报"){
                list.情报[name] = value;
            } else if(itemData.type != "武器" && itemData.type != "防具"){
                // 可合并物品
                if(mergables[name] != undefined){
                    mergables[name] += value;
                } else {
                    mergables[name] = value;
                }
            } else {
                // 不可合并物品直接加入列表
                nonMergeableList.push(itemArray[i]);
            }
        }

        // 得到药剂栏对象
        var 药剂栏:Object = _root.物品栏.药剂栏;
        var drugindexArr:Array = 药剂栏.getIndexes();
        var drugArr:Array = 药剂栏.getItemArray();
        // 这里默认能装进药剂栏的物品均可合并，检查药剂栏中是否已存在相同物品
        for(var i = 0; i < drugindexArr.length; i++){
            var drugItem:Object = drugArr[i];
            if(mergables[drugItem.name] != undefined && !isNaN(drugItem.value)){
                // 记录：将原有合并堆增加新需求
                list.药剂栏[drugindexArr[i]] = { name: drugItem.name, value: mergables[drugItem.name] };
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
            if(mergables[bagItem.name] != undefined && !isNaN(bagItem.value)){
                // 记录：将原有合并堆增加新需求
                list.背包[indexArr[i]] = { name: bagItem.name, value: mergables[bagItem.name] };
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

        // ServerManager.getInstance().sendServerMessage(ObjectUtil.toString(list));
        return list;
    }




    /* 
     * acquire 函数处理获得物品事件。
     * 输入值为一个物品数组，经过require函数处理后，在对应的位置添加对应的物品。
     * 若成功获得所有物品，返回true
     * 若背包空间不足，返回false
     */
    public static function acquire(itemArray:Array):Boolean {
        var list = ItemUtil.require(itemArray);
        if(list == null) return false;

        //获取
        if(list.金币 > 0) _root.金钱 += list.金币;
        if(list.K点 > 0) _root.虚拟币 += list.K点;
        if(list.经验值 > 0) {
            _root.经验值 += list.经验值;
            _root.主角是否升级(_root.等级,_root.经验值);
        }
        if(list.技能点 > 0) _root.技能点数 += list.技能点;

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
                // 新物品添加时间戳
                var newDrugItem = {
                    name: req.name,
                    value: req.value,
                    lastUpdate: new Date().getTime() // 新增时间戳
                };
                药剂栏.add(drugIndex, newDrugItem);
            } else {
                // 已有物品更新数量和时间戳
                药剂栏.addValue(drugIndex, req.value);
                var existingDrug = 药剂栏.getItem(drugIndex);
                existingDrug.lastUpdate = new Date().getTime(); // 更新时间戳
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
                var indexFound:Number = 背包.findByName(req.name);
                if(indexFound != -1) {
                    背包.addValue(String(indexFound), req.value);
                    背包.addValue(indexFound, req.value);
                    var existingItem = 背包.getItem(indexFound);
                    existingItem.lastUpdate = new Date().getTime(); // 更新时间戳
                } else {
                    // 没有则添加新项，用 -1 表示新建堆
                    背包.addValue(indexFound, req.value);
                    var existingItem = 背包.getItem(indexFound);
                    existingItem.lastUpdate = new Date().getTime(); // 更新时间戳
                }
            } else {
                // 对于已有项，直接增加数量
                var bagIndex:Number = Number(key);

                if(背包.isEmpty(bagIndex)){
                    // 如果该格子为空，添加新物品
                    var itemData = ItemUtil.getItemData(req.name);
                    var newItem = {name: req.name};
                    //检测是否为武器或防具，是则改写value的结构
                    if(itemData.type == "武器" || itemData.type == "防具") {
                        newItem.value = {level: req.value};
                    } else {
                        newItem.value = req.value;
                    }
                    newItem.lastUpdate = new Date().getTime(); // 新增时间戳
                    背包.add(bagIndex, newItem);
                } else {
                    // 已有物品更新数量和时间戳
                    背包.addValue(bagIndex, req.value);
                    var existingItem = 背包.getItem(bagIndex);
                    existingItem.lastUpdate = new Date().getTime(); // 更新时间戳
                }
            }
        }

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
            var itemData = ItemUtil.getItemData(name);
            if(itemData.use == "材料"){
                if(材料.getValue(name) < value) return null;
                list.材料[name] = value;
            }else if(itemData.use == "情报"){
                if(情报.getValue(name) < value) return null;
                list.情报[name] = value;
            }else{
                var indexArr = 背包.getIndexes();
                for(var arri:Number = 0; arri < indexArr.length; arri++){
                    var index = indexArr[arri];
                    var bagItem = 背包.getItem(index);
                    if(name != bagItem.name) continue;
                    if((itemData.type == "武器" || itemData.type == "防具") && bagItem.value.level >= value){
                        list.背包[index] = value;
                        value = 0;
                        break;
                    }
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
                if(value > 0) return null;
            }
        }
        return list;
    }
    
    /* 
     * submit 函数处理提交物品事件。
     * 输入值为一个物品数组，经过contain函数处理后，在背包和材料栏对应的位置移除对应数量的物品。情报栏的物品不会被submit函数移除
     * 若成功移除所有物品，返回true
     * 若背包和材料栏没有足够物品，返回false
     */
    public static function submit(itemArray:Array):Boolean{
        var list = ItemUtil.contain(itemArray);
        if(list == null) return false;
        //材料
        var 材料 = _root.收集品栏.材料;
        for(var name in list.材料){
            var value = list.材料[name];
            材料.addValue(name,-value);
        }
        //情报不需要提交
        // var 情报 = _root.收集品栏.情报;
        // for(var name in list.情报){
        //     var value = list.情报[name];
        //     情报.addValue(name,-value);
        // }
        //背包
        var 背包 = _root.物品栏.背包;
        for(var i in list.背包){
            var item = 背包.getItem(i);
            if(isNaN(item.value)) 背包.remove(i);
            else 背包.addValue(i, -list.背包[i]);
        }
        //药剂栏
        var 药剂栏 = _root.物品栏.药剂栏;
        for(var i in list.药剂栏){
            var item = 药剂栏.getItem(i);
            if(isNaN(item.value)) 药剂栏.remove(i);
            else 药剂栏.addValue(i, -list.药剂栏[i]);
        }
        return true;
    }

    //检索是否能放入单个物品
    public static function singleRequire(__name:String,__value:Number):Object{
        return ItemUtil.require([{name:__name,value:__value}]);
    }
    //获得单个物品
    public static function singleAcquire(__name:String,__value:Number):Boolean{
        return ItemUtil.acquire([{name:__name,value:__value}]);
    }
    //检索是否持有单个物品
    public static function singleContain(__name:String,__value:Number):Object{
        return ItemUtil.contain([{name:__name,value:__value}]);
    }
    //提交单个物品
    public static function singleSubmit(__name:String,__value:Number):Boolean{
        return ItemUtil.submit([{name:__name,value:__value}]);
    }

    
    
    //查找物品总数
    public static function getTotal(__name:String):Number{
        var itemData = ItemUtil.getItemData(__name);
        if(itemData.use == "材料") return _root.收集品栏.材料.getValue(__name);
        if(itemData.use == "情报") return _root.收集品栏.情报.getValue(__name);
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