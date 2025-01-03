// import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.neur.Server.ServerManager;
import org.flashNight.gesh.object.ObjectUtil;
/*
 * ItemUtil
 */

class org.flashNight.arki.item.ItemUtil{
    
    private var instance:ItemUtil;

    public function ItemUtil() {
        if (instance != null) {
            trace("ItemUtil 已经实例化。");
            return;
        }
    }

    //虽然暂时好像用不到单例
    public function getInstance():ItemUtil {
        if (instance == null) {
            instance = new ItemUtil();
        }
        return instance;
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
        var name = icon.name;
        var level = icon.value.level;
        var result = ItemUtil.moveItemToInventory(icon,equipmentIcon);
        if(!result) return false;
        //
        var 音效 = "9mmclip2.wav";
        var use = itemData.use;
        if(itemData.type == "防具"){
            音效 = "ammopickup1.wav";
            if (use == "颈部装备"){
                var 控制对象 = _root.gameworld[_root.控制目标];
                控制对象.称号 = itemData.equipped.title;
                _root.玩家称号 = 控制对象.称号;
            }
        }
        _root[index] = name;
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
            newArray[i] = {name:itemArray[i].name, value:itemArray[i].value};
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
    public static function require(itemArray:Array):Object{
        var list = {金币:0,K点:0,经验值:0,技能点:0,背包:{},材料:{},情报:{}};
        var mergables = {};//可堆叠物品
        var unmergableList = [];//不可堆叠物品
        //提取材料和情报
        for(var i = 0; i < itemArray.length; i++){
            var name = itemArray[i].name;
            var value = itemArray[i].value;
            if(name == "金币" || name == "K点" || name == "经验值" || name == "技能点"){
                list[name] = value;
                continue;
            }
            var itemData = _root.getItemData(name);
            if(itemData.use == "材料"){
                list.材料[name] = value;
            }else if(itemData.use == "情报"){
                list.情报[name] = value;
            }else if(itemData.type != "武器" && itemData.type != "防具"){
                mergables[name] = value;
            }else{
                unmergableList.push(itemArray[i]);
            }
        }
        //提取可堆叠物品
        var 背包 = _root.物品栏.背包;
        for(var i = 0; i < 背包.capacity; i++){
            var bagItem = 背包.getItem(i);
            if(!isNaN(mergables[bagItem.name]) && !isNaN(bagItem.value)){
                list.背包[i] = {name:bagItem.name, value:mergables[bagItem.name]};
                mergables[bagItem.name] = null;
            }
        }
        //未找到对应可堆叠物品则加入不可堆叠物品
        for(var key in mergables){
            if(!isNaN(mergables[key])) unmergableList.push({name:key, value:mergables[key]});
        }
        //若背包空间不足以容纳不可堆叠物品则返回null;
        var vacancyList = 背包.getVacancies(unmergableList.length);
        if(isNaN(vacancyList.length) || vacancyList.length < unmergableList.length) return null;
        //为不可堆叠物品分配空间
        for(var i = 0; i < unmergableList.length; i++){
            list.背包[vacancyList[i]] = unmergableList[i];
        }
        //返回
        ServerManager.getInstance().sendServerMessage(ObjectUtil.toString(list));
        return list;
    }

    /* 
     * acquire 函数处理获得物品事件。
     * 输入值为一个物品数组，经过require函数处理后，在对应的位置添加对应的物品。
     * 若成功获得所有物品，返回true
     * 若背包空间不足，返回false
     */
    public static function acquire(itemArray:Array):Boolean{
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
        //背包
        var 背包 = _root.物品栏.背包;
        for(var i in list.背包){
            if(背包.isEmpty(i)){
                var item = {name:list.背包[i].name};
                var itemData = _root.getItemData(item.name);
                if(itemData.type == "武器" || itemData.type == "防具"){
                    item.value = {level:list.背包[i].value};
                }else{
                    item.value = list.背包[i].value;
                }
                背包.add(i, item);
            }else{
                背包.addValue(i, list.背包[i].value);
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
        var list = {背包:{},材料:{},情报:{}};
        var 背包 = _root.物品栏.背包;
        var 材料 = _root.收集品栏.材料;
        var 情报 = _root.收集品栏.情报;
        var inventoryItems = {};
        //
        for(var i = 0; i < itemArray.length; i++){
            var name = itemArray[i].name;
            var value = itemArray[i].value;
            var itemData = _root.getItemData(name);
            if(itemData.use == "材料"){
                if(材料.getValue(name) < value) return null;
                list.材料[name] = value;
                // itemArray.splice(i,1);
            }else if(itemData.use == "情报"){
                if(情报.getValue(name) < value) return null;
                list.情报[name] = value;
                // itemArray.splice(i,1);
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
        var itemData = _root.getItemData(__name);
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