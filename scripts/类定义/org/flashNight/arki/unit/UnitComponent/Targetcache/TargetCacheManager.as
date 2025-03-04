// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheManager.as

import org.flashNight.naki.Sort.InsertionSort;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

// 目标缓存管理器类
// 该类负责管理并更新游戏中的目标缓存，包括敌人和友军目标的缓存处理。
class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager {
    
    // 静态缓存结构，存储不同状态和请求类型的目标缓存
    private static var _targetCaches:Object;
    
    // 初始化标志，确保只初始化一次
    private static var _initialized:Boolean = initialize();

    // 模块化配置: 类常量，存储目标缓存的状态标识
    private static var _STATUS_KEYS:Array = ["undefined", "true", "false", "all"];
    
    // 缓存模板，包含了缓存的数据数组、最后更新时间和数据版本
    private static var _CACHE_TEMPLATE:Object = {
        data: [],  // 缓存数据（目标列表）
        lastUpdatedFrame: 0,  // 缓存的最后更新时间帧
        dataVersion: ""  // 缓存的数据版本标识
    };

    /**
     * 初始化目标缓存管理器。
     * 为每个状态键（undefined、true、false）创建一个缓存结构，存储敌人和友军的数据。
     * @return {Boolean} 返回初始化是否成功
     */
    public static function initialize():Boolean {
        _targetCaches = {};  // 初始化缓存对象
        
        // 使用状态键来驱动缓存初始化
        for (var i:Number = 0; i < _STATUS_KEYS.length; i++) {
            var key:String = _STATUS_KEYS[i];
            _targetCaches[key] = {
                // 深拷贝模板避免引用污染，初始化敌人和友军缓存项
                敌人: _createCacheEntry(),
                友军: _createCacheEntry(),
                全体: _createCacheEntry()
            };
        }
        return true;
    }

    /**
     * 创建一个新的缓存项。
     * 每个缓存项包含数据、名称索引和最后更新时间。
     * @return {Object} 返回新的缓存项对象
     */
    private static function _createCacheEntry():Object {
        return {
            data: _CACHE_TEMPLATE.data.concat(),  // 新建数组，避免与其他缓存数据共享引用
            nameIndex: {},  // 名称索引，可能用于快速查找目标
            lastUpdatedFrame: _CACHE_TEMPLATE.lastUpdatedFrame  // 初始化时设置为0
        };
    }

    /**
     * 更新目标缓存。
     * 通过指定的更新间隔检查缓存是否需要更新，如果需要，则调用更新缓存方法。
     * @param {Object} target - 目标对象
     * @param {Number} updateInterval - 更新间隔，单位为帧数
     * @param {String} requestType - 请求类型，例如“敌人”或“友军”
     * @param {String} targetStatus - 目标的状态（true/false，表示敌人或友军）
     */
    public static function updateTargetCache(target:Object, updateInterval:Number, requestType:String, targetStatus:String):Void {
        var frame:Number = _root.帧计时器.当前帧数;  // 获取当前帧数
        
        // 内联_getCacheEntry逻辑开始
        // 如果没有找到目标状态的缓存，初始化它
        if (!_targetCaches[targetStatus]) _targetCaches[targetStatus] = {};
        var stateCache:Object = _targetCaches[targetStatus];
        var cache:Object = stateCache[requestType];
        
        // 如果该请求类型的缓存不存在，则初始化
        if (!cache) cache = stateCache[requestType] = _createCacheEntry();
        // 内联_getCacheEntry逻辑结束

        // 内联_needUpdate逻辑开始
        // 如果缓存已经过时，且超过更新间隔，则执行缓存更新操作
        if ((frame - cache.lastUpdatedFrame) > updateInterval) {
            TargetCacheUpdater.updateCache(
                _root.gameworld,
                frame,
                requestType,
                targetStatus == "true",  // 如果目标是敌人，则为true
                cache
            );
        }
        // 内联_needUpdate逻辑结束
    }

    /**
     * 获取缓存的目标数据。
     * @param {Object} target - 目标对象
     * @param {Number} updateInterval - 更新间隔，单位为帧数
     * @param {String} requestType - 请求类型，例如“敌人”或“友军”
     * @return {Array} 返回目标数据列表
     */
    public static function getCachedTargets(target:Object, updateInterval:Number, requestType:String):Array { 
        // 全体请求使用all状态键
        var targetStatus:String = (requestType == "全体") ? "all" : target.是否为敌人.toString();  // 获取目标的状态（敌人或友军）
        var currentFrame:Number = _root.帧计时器.当前帧数;  // 获取当前帧数
        
        // 内联_getCacheEntry逻辑开始
        // 如果没有找到目标状态的缓存，初始化它
        if (!_targetCaches[targetStatus]) _targetCaches[targetStatus] = {};
        var stateCache:Object = _targetCaches[targetStatus];
        var cacheEntry:Object = stateCache[requestType];
        
        // 如果该请求类型的缓存项不存在，则初始化
        if (!cacheEntry) cacheEntry = stateCache[requestType] = _createCacheEntry();  // 初始化时设置lastUpdatedFrame=-Infinity
        // 内联_getCacheEntry逻辑结束

        // 内联_needForceUpdate并优化条件判断
        // 如果缓存已经过时，且超过更新间隔，则执行缓存更新操作
        if ((currentFrame - cacheEntry.lastUpdatedFrame) > updateInterval) {  // 依赖初始化时lastUpdatedFrame=-Infinity触发首次更新
            TargetCacheUpdater.updateCache(
                _root.gameworld,
                currentFrame,
                requestType,
                targetStatus == "true",  // 如果目标是敌人，则为true
                cacheEntry
            );
        }

        return cacheEntry.data;  // 返回目标缓存数据
    }

    /**
     * 获取缓存的敌人数据。
     * @param {Object} target - 目标对象
     * @param {Number} updateInterval - 更新间隔，单位为帧数
     * @return {Array} 返回敌人数据列表
     */
    public static function getCachedEnemy(target:Object, updateInterval:Number):Array {
        return getCachedTargets(target, updateInterval, "敌人");  // 获取敌人的缓存数据
    }

    /**
     * 获取缓存的友军数据。
     * @param {Object} target - 目标对象
     * @param {Number} updateInterval - 更新间隔，单位为帧数
     * @return {Array} 返回友军数据列表
     */
    public static function getCachedAlly(target:Object, updateInterval:Number):Array {
        return getCachedTargets(target, updateInterval, "友军");  // 获取友军的缓存数据
    }

    /**
     * 获取缓存的全体数据。
     * @param {Object} target - 目标对象
     * @param {Number} updateInterval - 更新间隔，单位为帧数
     * @return {Array} 返回全体数据列表
     */
    public static function getCachedAll(target:Object, updateInterval:Number):Array {
        return getCachedTargets(target, updateInterval, "全体");
    }
}
