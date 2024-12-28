// import org.flashNight.arki.item.itemCollection.DictCollection;
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
     * 物品栏移动操作
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
        var sound = "9mmclip2.wav";
        var use = itemData.use;
        if(itemData.type == "防具"){
            sound = "ammopickup1.wav";
            if (use == "颈部装备"){
                var 控制对象 = _root.gameworld[_root.控制目标];
                控制对象.称号 = itemData.equipped.title;
                _root.玩家称号 = 控制对象.称号;
            }
        }else if (use == "长枪"){
            _root.长枪强化等级 = level;
            _root.长枪配置(_root.控制目标,name,level);
        }else if (use == "手枪"){
            if (index == "手枪2"){
                _root.手枪2强化等级 = level;
                _root.手枪2配置(_root.控制目标,name,level);
            }else{
                _root.手枪强化等级 = level;
                _root.手枪配置(_root.控制目标,name,level);
            }
        }else if (use == "手雷"){
            _root.手雷配置(_root.控制目标,name);
        }else if (use == "刀"){
            _root.刀强化等级 = level;
            _root.刀配置(_root.控制目标,name,level);
        }
        _root[index] = name;
        _root.播放音效(sound);
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
    */
    //根据原版物品数据生成itemRequirement
    public static function getRequirement(itemArray:Array):Array{
        var newArray = new Array(itemArray.length);
        for(var i = 0; i<itemArray.length; i++){
            newArray[i] = {name:itemArray[i].name, value:itemArray[i].value};
        }
        return newArray;
    }


    //检测背包是否有足够空位获得物品
    public static function require(itemArray:Array):Object{
        var 背包 = _root.物品栏.背包;
        var list = {金币:0,K点:0,经验值:0,技能点:0,背包:{},材料:{},情报:{}};
        var inventoryItems = {};
        //提取材料和情报
        for(var i = itemArray.length - 1; i > -1; i--){
            var name = itemArray[i].name;
            var value = itemArray[i].value;
            if(name == "金币" || name == "K点" || name == "经验值" || name == "技能点"){
                list[name] = value;
                continue;
            }
            var itemData = _root.getItemData(name);
            if(itemData.use == "材料"){
                list.材料[name] = value;
                itemArray.splice(i,1);
            }else if(itemData.use == "情报"){
                list.情报[name] = value;
                itemArray.splice(i,1);
            }else{
                inventoryItems[name] = i;
            }
        }
        //提取可堆叠物品
        for(var i = 0; i < 背包.capacity; i++){
            var bagItem = 背包.getItem(i);
            var index = inventoryItems[bagItem.name];
            if(index != null && !isNaN(bagItem.value)){
                list.背包[i] = itemArray[index];
                itemArray.splice(index,1);
            }
        }
        //若背包空间不足以容纳不可堆叠物品则返回null;
        var vacancyList = 背包.getVacancies();
        if(isNaN(vacancyList.length) || vacancyList.length < itemArray.length) return null;
        //为不可堆叠物品分配空间
        for(var i = 0; i < itemArray.length; i++){
            list.背包[vacancyList[i]] = itemArray[i];
        }
        //返回
        return list;
    }
    //获得物品
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

    //检测是否持有对应物品
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
                for(var index = 0; index < 背包.capacity; index++){
                    if(背包.isEmpty(index)) continue;
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
    //提交物品
    public static function submit(itemArray:Array):Boolean{
        var list = ItemUtil.contain(itemArray);
        if(list == null) return false;
        //材料
        var 材料 = _root.收集品栏.材料;
        for(var name in list.材料){
            var value = list.材料[name];
            材料.addValue(name,-value);
        }
        //情报
        var 情报 = _root.收集品栏.情报;
        for(var name in list.情报){
            var value = list.情报[name];
            情报.addValue(name,-value);
        }
        //背包
        var 背包 = _root.物品栏.背包;
        for(var i in list.背包){
            var item = 背包.getItem(i);
            if(isNaN(item.value)) 背包.remove(i);
            else 背包.addValue(i, -list.背包[i].value);
        }
        return true;
    }
}

//org.flashNight.arki.item.ItemUtil.acquire()