import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.itemCollection.*;
/*
 * ItemSortUtil 静态类，专用于排序整理物品栏
 * 
 */

class org.flashNight.arki.item.ItemSortUtil{

    /**
     * 封装后的排序方法
     * @param inventory 要排序的物品栏
     * @param methodName 排序方法名称（可选，默认为"default"）
     * @param callback 完成后的回调（可选）
     */
    public static function sortInventory(
        inventory:ArrayInventory, 
        methodName:String, 
        callback:Function
    ):Void {
        // 参数验证和默认值处理

        var sortMethods:Object = new Object;

        sortMethods["default"] = function (a:Object, b:Object):Number
        {
            return 0;
        };

        _root.发布消息("开始排序");
        
        if (methodName == null || !sortMethods[methodName]) {
            methodName = "default";
        }
        
        // 获取对应的排序函数
        var sortFunc:Function = sortMethods[methodName];
        
        // 执行排序
        inventory.rebuildOrder(sortFunc);
        
        // 自动刷新界面
        if (_root.物品栏 && _root.物品栏.背包 == inventory) {
            _root.物品UI函数.删除背包图标();
		    _root.物品UI函数.创建背包图标();
        }
        
        // 执行回调
        if (typeof callback === "function") {
            callback(inventory);
        }
    }

}

//org.flashNight.arki.item.ItemUtil.acquire()