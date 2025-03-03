// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheManager.as
import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager {
    
    // 初始化缓存结构 (需由帧计时器初始化时调用)
    public static function initialize():Void {
        var temp = _root.帧计时器;

        temp.目标缓存 = {};
        temp.目标缓存["undefined"] = { 数据: [], 最后更新帧数: 0 };
        temp.目标缓存["true"] = { 数据: [], 最后更新帧数: 0 };
        temp.目标缓存["false"] = { 数据: [], 最后更新帧数: 0 };

    }

    public static function updateTargetCache(自机:Object, 更新间隔:Number, 请求类型:String, 自机状态键:String):Void {
        var SORT_KEY:String = "right";
        更新间隔 = isNaN(更新间隔) ? 1 : 更新间隔;
        
        if (!_root.帧计时器.目标缓存[自机状态键]) _root.帧计时器.目标缓存[自机状态键] = {};
        var 状态缓存:Object = _root.帧计时器.目标缓存[自机状态键];
        if (!状态缓存[请求类型]) 状态缓存[请求类型] = { 数据: [], nameIndex: {}, 最后更新帧数: 0 };
        
        var cache:Object = 状态缓存[请求类型];
        var 当前帧数:Number = _root.帧计时器.当前帧数;
        var isEnemyRequest:Boolean = (请求类型 == "敌人");
        var 游戏世界:Object = _root.gameworld;
        var 自机是敌人:Boolean = 自机.是否为敌人;
        
        // 收集符合条件的存活目标
        var tempList:Array = [];
        for (var 待选目标:String in 游戏世界) {
            var 目标:Object = 游戏世界[待选目标];
            if (目标.hp <= 0) continue;
            
            // 敌我判断
            var 目标敌我状态:Boolean = 目标.是否为敌人;
            var 需要处理:Boolean = isEnemyRequest ? 
                (自机是敌人 != 目标敌我状态) : 
                (自机是敌人 == 目标敌我状态);
            if (!需要处理) continue;
            
            // 更新碰撞体
            目标.aabbCollider.updateFromUnitArea(目标);
            tempList.push(目标);
        }
        
        // 按right升序排序
        InsertionSort.sort(tempList, function(a:Object, b:Object):Number {
            return a.aabbCollider.right - b.aabbCollider.right;
        });
        
        // 重建数据与索引
        var newData:Array = [];
        var newNameIndex:Object = {};
        for (var i:Number = 0; i < tempList.length; i++) {
            newData.push(tempList[i]);
            newNameIndex[tempList[i]._name] = i;
        }
        
        // 更新缓存
        cache.数据 = newData;
        cache.nameIndex = newNameIndex;
        cache.最后更新帧数 = 当前帧数;
    }

    public static function getCachedTargets(自机:Object, 更新间隔:Number, 请求类型:String):Array {
        var 自机状态键 = 自机.是否为敌人.toString();
        var 目标缓存对象 = _root.帧计时器.目标缓存[自机状态键][请求类型];

        if (isNaN(目标缓存对象.最后更新帧数) || _root.帧计时器.当前帧数 - 目标缓存对象.最后更新帧数 > 更新间隔) {
            TargetCacheManager.updateTargetCache(自机, 更新间隔, 请求类型, 自机状态键);
        }

        return 目标缓存对象.数据;
    }

    public static function getCachedEnemy(自机:Object, 更新间隔:Number):Array {
        var 自机状态键 = 自机.是否为敌人.toString();
        var 目标缓存对象 = _root.帧计时器.目标缓存[自机状态键]["敌人"];

        if (isNaN(目标缓存对象.最后更新帧数) || _root.帧计时器.当前帧数 - 目标缓存对象.最后更新帧数 > 更新间隔) {
            TargetCacheManager.updateTargetCache(自机, 更新间隔, "敌人", 自机状态键);
        }

        return 目标缓存对象.数据;
    }

    public static function getCachedAlly(自机:Object, 更新间隔:Number):Array {
        var 自机状态键 = 自机.是否为敌人.toString();
        var 目标缓存对象 = _root.帧计时器.目标缓存[自机状态键]["友军"];

        if (isNaN(目标缓存对象.最后更新帧数) || _root.帧计时器.当前帧数 - 目标缓存对象.最后更新帧数 > 更新间隔) {
            TargetCacheManager.updateTargetCache(自机, 更新间隔, "友军", 自机状态键);
        }

        return 目标缓存对象.数据;
    }
}
