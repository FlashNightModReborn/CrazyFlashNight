// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheManager.as
import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager {
    // 静态缓存结构
    private static var _targetCaches:Object;
    private static var _initialized:Boolean = false;

    // 模块化配置 (类常量)
    private static var _STATUS_KEYS:Array = ["undefined", "true", "false"];
    private static var _CACHE_TEMPLATE:Object = {
        data: [],
        lastUpdatedFrame: 0
    };

    // 初始化缓存结构
    public static function initialize():Void {
        _targetCaches = {};
        
        // 使用配置驱动初始化
        for (var i:Number = 0; i < _STATUS_KEYS.length; i++) {
            var key:String = _STATUS_KEYS[i];
            _targetCaches[key] = {
                // 深拷贝模板避免引用污染
                敌人: _createCacheEntry(),
                友军: _createCacheEntry()
            };
        }
        _initialized = true;
    }

    // 独立缓存项创建方法
    private static function _createCacheEntry():Object {
        return {
            data: _CACHE_TEMPLATE.data.concat(), // 新建数组
            nameIndex: {},
            lastUpdatedFrame: _CACHE_TEMPLATE.lastUpdatedFrame
        };
    }

    public static function updateTargetCache(target:Object, updateInterval:Number, requestType:String, targetStatus:String):Void {
        if (!_initialized) initialize();
        
        var SORT_KEY:String = "right";
        updateInterval = isNaN(updateInterval) ? 1 : updateInterval;
        
        if (!_targetCaches[targetStatus]) _targetCaches[targetStatus] = {};
        var stateCache:Object = _targetCaches[targetStatus];
        if (!stateCache[requestType]) stateCache[requestType] = { data: [], nameIndex: {}, lastUpdatedFrame: 0 };
        
        var cache:Object = stateCache[requestType];
        var frame:Number = _root.帧计时器.当前帧数;
        var isEnemyRequest:Boolean = (requestType == "敌人");
        var gameWorld:Object = _root.gameworld;
        var targetIsEnemy:Boolean = target.是否为敌人;
        
        // 收集符合条件的存活目标
        var tempList:Array = [];
        for (var unitKey:String in gameWorld) {
            var unit:Object = gameWorld[unitKey];
            if (unit.hp <= 0) continue;
            
            // 敌我判断
            var enemyStatus:Boolean = unit.是否为敌人;
            var needProcess:Boolean = isEnemyRequest ? 
                (targetIsEnemy != enemyStatus) : 
                (targetIsEnemy == enemyStatus);
            if (!needProcess) continue;
            
            // 更新碰撞体
            unit.aabbCollider.updateFromUnitArea(unit);
            tempList.push(unit);
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
        cache.data = newData;
        cache.nameIndex = newNameIndex;
        cache.lastUpdatedFrame = frame;
    }

    public static function getCachedTargets(target:Object, updateInterval:Number, requestType:String):Array {
        if (!_initialized) initialize();
        
        var targetStatus = target.是否为敌人.toString();
        var cachedTargets = _targetCaches[targetStatus][requestType];

        if (isNaN(cachedTargets.lastUpdatedFrame) || _root.帧计时器.当前帧数 - cachedTargets.lastUpdatedFrame > updateInterval) {
            updateTargetCache(target, updateInterval, requestType, targetStatus);
        }

        return cachedTargets.data;
    }

    public static function getCachedEnemy(target:Object, updateInterval:Number):Array {
        return getCachedTargets(target, updateInterval, "敌人");
    }

    public static function getCachedAlly(target:Object, updateInterval:Number):Array {
        return getCachedTargets(target, updateInterval, "友军");
    }
}
