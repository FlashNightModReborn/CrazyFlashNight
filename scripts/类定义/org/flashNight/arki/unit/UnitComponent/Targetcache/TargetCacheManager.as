// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheManager.as
import org.flashNight.naki.Sort.InsertionSort;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager {
    // 静态缓存结构
    private static var _targetCaches:Object;
    private static var _initialized:Boolean = false;

    // 模块化配置 (类常量)
    private static var _STATUS_KEYS:Array = ["undefined", "true", "false"];
    private static var _CACHE_TEMPLATE:Object = {
        data: [],
        lastUpdatedFrame: 0,
        dataVersion: ""
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
        
        var cache:Object = _getCacheEntry(targetStatus, requestType);
        var frame:Number = _root.帧计时器.当前帧数;
        
        if (_needUpdate(cache, frame, updateInterval)) {
            TargetCacheUpdater.updateCache(
                _root.gameworld,      // 游戏世界对象
                frame,               // 当前帧数
                requestType,         // 请求类型
                targetStatus == "true", // 请求者是否为敌人
                cache                // 要更新的缓存条目
            );
        }
    }

    // 新增辅助方法
    private static function _getCacheEntry(targetStatus:String, requestType:String):Object {
        if (!_targetCaches[targetStatus]) _targetCaches[targetStatus] = {};
        var stateCache:Object = _targetCaches[targetStatus];
        return stateCache[requestType] || (stateCache[requestType] = _createCacheEntry());
    }

    private static function _needUpdate(cache:Object, currentFrame:Number, interval:Number):Boolean {
        return isNaN(cache.lastUpdatedFrame) || 
              (currentFrame - cache.lastUpdatedFrame) > interval;
    }
    
    // 新增获取缓存目标方法
    public static function getCachedTargets(target:Object, updateInterval:Number, requestType:String):Array {
        if (!_initialized) initialize();
        
        var targetStatus:String = target.是否为敌人.toString();
        var cacheEntry:Object = _getCacheEntry(targetStatus, requestType);
        
        if (_needForceUpdate(cacheEntry, updateInterval)) {
            TargetCacheUpdater.updateCache(
                _root.gameworld,
                _root.帧计时器.当前帧数,
                requestType,
                targetStatus == "true",
                cacheEntry
            );
        }
        return cacheEntry.data;
    }

    private static function _needForceUpdate(cache:Object, interval:Number):Boolean {
        var frameDiff:Number = _root.帧计时器.当前帧数 - cache.lastUpdatedFrame;
        return isNaN(cache.lastUpdatedFrame) || frameDiff > interval;
    }

    public static function getCachedEnemy(target:Object, updateInterval:Number):Array {
        return getCachedTargets(target, updateInterval, "敌人");
    }

    public static function getCachedAlly(target:Object, updateInterval:Number):Array {
        return getCachedTargets(target, updateInterval, "友军");
    }
}
