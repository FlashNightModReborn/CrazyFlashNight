import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.arki.item.ItemUtil;

import org.flashNight.aven.Coordinator.EventCoordinator;
import org.flashNight.naki.DataStructures.Dictionary;
/*
 * IconFactory，物品图标工厂
*/

class org.flashNight.arki.item.itemIcon.IconFactory{

    public static var inventoryContainerDict:Object; // 记录场上所有数据结构为ArrayInventory的物品栏UI和对应的物品图标

    public function IconFactory() {
        // 
    }

    // 通过行列数据创建若干个
    public static function createIconLayout(proto:MovieClip, func:Function, info:Object):Array{
        var iconname = info.iconname ? iconname : "物品图标";
        var startindex = info.startindex > 0 ? info.startindex : 0;
        var startdepth = info.startdepth > 0 ? info.startdepth : 0;
        var row = info.row > 0 ? info.row : 5;
        var col = info.col > 0 ? info.col : 10;
        var padding = info.padding > 0 ? info.padding : 28;

        var container = proto._parent;
        var x = proto._x;
        var y = proto._y;
        var endindex = row * col + startindex;
        var count = 0;
        var iconList = new Array(row * col);

        for (var i = startindex; i < endindex; i++){
            var iconMC = container.attachMovie("物品图标", iconname + i, startdepth + i);
            iconMC._x = x;
            iconMC._y = y;
            x += padding;
            count++;
            if (count >= col){
                count = 0;
                x = proto._x;
                y += padding;
            }
            iconList[i] = iconMC;
            iconMC.itemIcon = func(iconMC, i);
        }

        // 在对应的原型卸载时清除所有图标
        EventCoordinator.addUnloadCallback(proto, function(){
            for(var i=0; i<iconList.length; i++){
                iconList[i].removeMovieClip();
                iconList[i] = null;
            }
        });
        // 接受自定义的额外的卸载回调
        if(typeof info.unloadCallback == "function") EventCoordinator.addUnloadCallback(proto, info.unloadCallback);
        
        return iconList;
    }

    public static function createInventoryLayout(inventory, proto:MovieClip, info:Object):Array{
        if(inventory == null || proto == null) return null;

        var containerUID = Dictionary.getStaticUID(proto._parent);
        if(inventoryContainerDict == null) inventoryContainerDict = {};

        if(inventoryContainerDict[containerUID] != null){
            if(inventoryContainerDict[containerUID].container === proto._parent){
                // 若检查到图标已经存在则改为刷新图标
                resetInventoryLayout(containerUID, inventory, info.startindex);
                return inventoryContainerDict[containerUID].list;
            }else{
                return null;
            }
        }

        var dispatcher = new LifecycleEventDispatcher(proto);
        inventory.setDispatcher(dispatcher);

        var func = function(iconMC,i){
            return new InventoryIcon(iconMC, inventory, i);
        }
        var iconList = createIconLayout(proto, func, info);
        inventoryContainerDict[containerUID] = {
            proto: proto,
            container: proto._parent,
            inventory: inventory,
            list: iconList
        };
        
        // 原型卸载时额外清除容器记录
        EventCoordinator.addUnloadCallback(proto, function(){
            delete inventoryContainerDict[containerUID];
        });

        return iconList;
    }

    public static function resetInventoryLayout(uid:Number, inventory, startindex:Number):Void{
        if(inventory !== inventoryContainerDict[uid].inventory){
            // 若inventory更改，则销毁原事件分发器并创建新的分发器
            inventoryContainerDict[uid].inventory.getDispatcher().destroy();
            inventoryContainerDict[uid].inventory = inventory;
            var dispatcher = new LifecycleEventDispatcher(inventoryContainerDict[uid].proto);
            inventory.setDispatcher(dispatcher);
        }

        var list = inventoryContainerDict[uid].list;
        for(var i=0; i<list.length; i++){
            list[i].itemIcon.reset(inventory, startindex + i);
        }
    }


}
