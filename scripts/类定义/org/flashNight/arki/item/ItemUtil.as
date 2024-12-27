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
    //检测背包是否有足够空位获得物品
    public static function require(items):Object{
        //
        return null;
    }
    //获得物品
    public static function acquire(items):Boolean{
        //
        return true;
    }

    //检测是否持有对应物品
    public static function contain(items):Object{
        var list = {背包:{},材料:{}};
        var capacity = _root.物品栏.背包.capacity;
        for(var i=0; i<capacity; i++){
            // var item = 
        }
        for(var key in _root.收集栏.材料){
        }
        return null;
    }
    //提交物品
    public static function submit(items):Boolean{
        var list = ItemUtil.contain(items);
        if(list == null) return false;
        return true;
    }
}
