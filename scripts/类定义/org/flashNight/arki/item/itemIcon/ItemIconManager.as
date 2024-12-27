/*
 * 物品图标UI管理器
*/

class org.flashNight.arki.item.itemIcon.ItemIconManager{
    
    private var instance:ItemIconManager;

    public function ItemIconManager() {
        if (instance != null) {
            trace("ItemIconManager 已经实例化。");
            return;
        }
    }

    public function getInstance():ItemIconManager {
        if (instance == null) {
            instance = new ItemIconManager();
        }
        return instance;
    }

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
        var result = ItemIconManager.moveItemToInventory(icon,equipmentIcon);
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
        _root[index] = name;//
        _root.播放音效(sound);
        _root.发布消息("成功装备[" + use + "][" + itemData.displayname + "]");
        _root.刷新人物装扮(_root.控制目标);
        return true;
    }

    public static function moveItemToDrug(icon,drugIcon):Boolean{
        if(!drugIcon.isCoolDown()) return false;
        var result = ItemIconManager.moveItemToInventory(icon,drugIcon);
        return result;
    }
}
