import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.itemCollection.*;
/*
 * ItemSortUtil 静态类，专用于排序整理物品栏
 * 
 */

class org.flashNight.arki.item.ItemSortUtil{

    // 默认排序字段，不改变顺序
    private static var basic = null;

    
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
        
        if (methodName == null || !ItemSortUtil[methodName]) {
            methodName = "default";
        }

        //_root.发布消息("开始整理物品栏");

        // 获取对应的排序函数
        var sortFunc:Function = ItemSortUtil[methodName];
        
        // 执行排序
        inventory.rebuildOrder(sortFunc);
        
        // 执行回调
        if (typeof callback === "function") {
            callback(inventory);
        }
    }

}
