// ============================================================================
// 目标缓存提供者（TargetCacheProvider）- 缓存生命周期管理器
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 管理所有 SortedUnitCache 实例的生命周期和存储
// 2. 提供缓存获取的统一入口，处理缓存的创建、更新和失效
// 3. 协调 TargetCacheUpdater 和 SortedUnitCache 之间的交互
// 4. 维护版本号和缓存策略，优化内存使用
// 
// 设计原则：
// - 单一职责：专注于缓存实例的管理和提供
// - 工厂模式：为外部提供统一的缓存获取接口
// - 生命周期管理：处理缓存的创建、更新、失效和清理
// - 性能优化：智能的缓存策略和内存管理
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheProvider {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * 缓存池对象
     * 结构: {cacheKey: SortedUnitCache实例}
     * cacheKey格式: "请求类型_阵营状态" 或 "全体_all"
     * 例如: "敌人_false", "友军_true", "全体_all"
     */
    private static var _cachePool:Object = {};
    
    /**
     * TargetCacheUpdater 实例引用
     * 用于创建和更新缓存数据
     */
    private static var _updater:Object = TargetCacheUpdater;
    
    /**
     * 缓存策略配置
     */
    private static var _cacheConfig:Object = {
        // 最大缓存数量限制（防止内存泄漏）
        maxCacheCount: 20,
        
        // 自动清理阈值（当缓存数量超过此值时触发清理）
        autoCleanThreshold: 15,
        
        // 缓存存活时间（帧数），超过此时间的缓存将被标记为可清理
        maxCacheAge: 300,
        
        // 是否启用自动清理
        autoCleanEnabled: true
    };
    
    /**
     * 缓存统计信息
     */
    private static var _stats:Object = {
        totalRequests: 0,      // 总请求次数
        cacheHits: 0,          // 缓存命中次数
        cacheMisses: 0,        // 缓存未命中次数
        cacheCreations: 0,     // 缓存创建次数
        cacheUpdates: 0,       // 缓存更新次数
        autoCleanRuns: 0       // 自动清理运行次数
    };

    /**
     * 初始化标志
     */
    private static var _initialized:Boolean = initialize();

    // ========================================================================
    // 初始化方法
    // ========================================================================
    
    /**
     * 静态初始化方法
     * 设置默认配置并准备提供者
     * @return {Boolean} 初始化是否成功
     */
    public static function initialize():Boolean {
        // 确保缓存池为空对象
        _cachePool = {};
        
        // 重置统计信息
        resetStats();
        
        return true;
    }

    // ========================================================================
    // 核心缓存提供方法
    // ========================================================================
    
    /**
     * 获取指定类型的缓存（核心方法）
     * 
     * 这是外部获取缓存的唯一入口，负责：
     * 1. 生成缓存键
     * 2. 检查缓存是否存在且有效
     * 3. 如果缓存无效，创建新的缓存实例
     * 4. 返回有效的 SortedUnitCache 实例
     * 
     * @param {String} requestType - 请求类型: "敌人", "友军", "全体"
     * @param {Object} target - 目标单位（用于确定阵营状态）
     * @param {Number} updateInterval - 缓存更新间隔（帧数）
     * @return {SortedUnitCache} 有效的缓存实例，失败时返回null
     */
    public static function getCache(
        requestType:String,
        target:Object,
        updateInterval:Number
    ):SortedUnitCache {
        _stats.totalRequests++;
        
        // 1. 生成缓存键
        var cacheKey:String = generateCacheKey(requestType, target);
        
        // 2. 获取当前帧数
        var currentFrame:Number = _root.帧计时器.当前帧数;
        
        // 3. 检查缓存是否存在
        var cache:SortedUnitCache = _cachePool[cacheKey];
        
        if (cache) {
            // 4. 检查缓存是否需要更新
            var framesSinceUpdate:Number = currentFrame - cache.lastUpdatedFrame;
            
            if (framesSinceUpdate < updateInterval) {
                // 缓存仍然有效
                _stats.cacheHits++;
                return cache;
            } else {
                // 缓存过期，需要更新
                _stats.cacheMisses++;
                updateExistingCache(cache, requestType, target, currentFrame);
                _stats.cacheUpdates++;
                return cache;
            }
        } else {
            // 5. 缓存不存在，创建新缓存
            _stats.cacheMisses++;
            cache = createNewCache(requestType, target, currentFrame, cacheKey);
            _stats.cacheCreations++;
            
            // 6. 检查是否需要自动清理
            if (_cacheConfig.autoCleanEnabled) {
                checkAndPerformAutoClean(currentFrame);
            }
            
            return cache;
        }
    }

    /**
     * 生成缓存键
     * 根据请求类型和目标阵营生成唯一的缓存标识
     * 
     * @param {String} requestType - 请求类型
     * @param {Object} target - 目标单位
     * @return {String} 缓存键
     * @private
     */
    private static function generateCacheKey(requestType:String, target:Object):String {
        if (requestType == "全体") {
            return "全体_all";
        } else {
            var targetIsEnemy:Boolean = target.是否为敌人;
            return requestType + "_" + targetIsEnemy.toString();
        }
    }

    /**
     * 创建新的缓存实例
     * 使用 TargetCacheUpdater 构建数据，然后封装为 SortedUnitCache
     * 
     * @param {String} requestType - 请求类型
     * @param {Object} target - 目标单位
     * @param {Number} currentFrame - 当前帧数
     * @param {String} cacheKey - 缓存键
     * @return {SortedUnitCache} 新创建的缓存实例
     * @private
     */
    private static function createNewCache(
        requestType:String,
        target:Object,
        currentFrame:Number,
        cacheKey:String
    ):SortedUnitCache {
        // 创建临时缓存项对象（与原 TargetCacheUpdater 接口兼容）
        var tempCacheEntry:Object = {
            data: [],
            nameIndex: {},
            rightValues: [],
            leftValues: [],
            lastUpdatedFrame: 0
        };
        
        // 使用 TargetCacheUpdater 填充数据
        _updater.updateCache(
            _root.gameworld,
            currentFrame,
            requestType,
            target.是否为敌人,
            tempCacheEntry
        );
        
        // 创建 SortedUnitCache 实例
        var cache:SortedUnitCache = new SortedUnitCache(
            tempCacheEntry.data,
            tempCacheEntry.nameIndex,
            tempCacheEntry.leftValues,
            tempCacheEntry.rightValues,
            tempCacheEntry.lastUpdatedFrame
        );
        
        // 存储到缓存池
        _cachePool[cacheKey] = cache;
        
        return cache;
    }

    /**
     * 更新现有缓存实例
     * 重新填充缓存数据而不创建新的实例
     * 
     * @param {SortedUnitCache} cache - 要更新的缓存实例
     * @param {String} requestType - 请求类型
     * @param {Object} target - 目标单位
     * @param {Number} currentFrame - 当前帧数
     * @private
     */
    private static function updateExistingCache(
        cache:SortedUnitCache,
        requestType:String,
        target:Object,
        currentFrame:Number
    ):Void {
        // 创建临时缓存项对象
        var tempCacheEntry:Object = {
            data: [],
            nameIndex: {},
            rightValues: [],
            leftValues: [],
            lastUpdatedFrame: 0
        };
        
        // 使用 TargetCacheUpdater 重新生成数据
        _updater.updateCache(
            _root.gameworld,
            currentFrame,
            requestType,
            target.是否为敌人,
            tempCacheEntry
        );
        
        // 更新现有缓存实例的数据
        cache.updateData(
            tempCacheEntry.data,
            tempCacheEntry.nameIndex,
            tempCacheEntry.leftValues,
            tempCacheEntry.rightValues,
            tempCacheEntry.lastUpdatedFrame
        );
    }

    // ========================================================================
    // 缓存生命周期管理
    // ========================================================================
    
    /**
     * 检查并执行自动清理
     * 当缓存数量超过阈值时，清理旧的缓存实例
     * 
     * @param {Number} currentFrame - 当前帧数
     * @private
     */
    private static function checkAndPerformAutoClean(currentFrame:Number):Void {
        var cacheCount:Number = getCacheCount();
        
        if (cacheCount >= _cacheConfig.autoCleanThreshold) {
            performAutoClean(currentFrame);
            _stats.autoCleanRuns++;
        }
    }

    /**
     * 执行自动清理
     * 移除过期的缓存实例以释放内存
     * 
     * @param {Number} currentFrame - 当前帧数
     * @private
     */
    private static function performAutoClean(currentFrame:Number):Void {
        var keysToRemove:Array = [];
        
        // 收集需要清理的缓存键
        for (var key:String in _cachePool) {
            var cache:SortedUnitCache = _cachePool[key];
            var age:Number = currentFrame - cache.lastUpdatedFrame;
            
            if (age > _cacheConfig.maxCacheAge) {
                keysToRemove.push(key);
            }
        }
        
        // 如果按年龄清理后仍然超过最大数量，按LRU策略继续清理
        var currentCount:Number = getCacheCount();
        if (currentCount - keysToRemove.length > _cacheConfig.maxCacheCount) {
            var allCaches:Array = [];
            
            // 收集所有缓存及其信息
            for (var key2:String in _cachePool) {
                if (keysToRemove.indexOf(key2) == -1) { // 排除已标记删除的
                    allCaches.push({
                        key: key2,
                        cache: _cachePool[key2],
                        lastUpdate: _cachePool[key2].lastUpdatedFrame
                    });
                }
            }
            
            // 按最后更新时间排序（最旧的在前）
            allCaches.sort(function(a:Object, b:Object):Number {
                return a.lastUpdate - b.lastUpdate;
            });
            
            // 添加最旧的缓存到删除列表
            var needToRemove:Number = (currentCount - keysToRemove.length) - _cacheConfig.maxCacheCount;
            for (var i:Number = 0; i < needToRemove && i < allCaches.length; i++) {
                keysToRemove.push(allCaches[i].key);
            }
        }
        
        // 执行删除
        for (var j:Number = 0; j < keysToRemove.length; j++) {
            delete _cachePool[keysToRemove[j]];
        }
    }

    /**
     * 手动清理指定类型的缓存
     * @param {String} requestType - 要清理的请求类型（可选，不传则清理所有）
     */
    public static function clearCache(requestType:String):Void {
        if (requestType) {
            // 清理特定类型的缓存
            for (var key:String in _cachePool) {
                if (key.indexOf(requestType) == 0) {
                    delete _cachePool[key];
                }
            }
        } else {
            // 清理所有缓存
            for (var key2:String in _cachePool) {
                delete _cachePool[key2];
            }
            _cachePool = {};
        }
    }

    /**
     * 强制刷新所有缓存
     * 将所有缓存标记为过期，下次访问时将自动更新
     */
    public static function invalidateAllCaches():Void {
        for (var key:String in _cachePool) {
            var cache:SortedUnitCache = _cachePool[key];
            cache.lastUpdatedFrame = 0; // 设为0强制下次更新
        }
    }

    /**
     * 强制刷新指定类型的缓存
     * @param {String} requestType - 要刷新的请求类型
     */
    public static function invalidateCache(requestType:String):Void {
        for (var key:String in _cachePool) {
            if (key.indexOf(requestType) == 0) {
                var cache:SortedUnitCache = _cachePool[key];
                cache.lastUpdatedFrame = 0;
            }
        }
    }

    // ========================================================================
    // 版本号管理（委托给TargetCacheUpdater）
    // ========================================================================
    
    /**
     * 添加单位时更新版本号
     * 委托给 TargetCacheUpdater 处理
     * @param {Object} unit - 新增的单位对象
     */
    public static function addUnit(unit:Object):Void {
        _updater.addUnit(unit);
        // 可选：根据单位类型选择性失效缓存
        // invalidateRelatedCaches(unit);
    }
    
    /**
     * 移除单位时更新版本号
     * 委托给 TargetCacheUpdater 处理
     * @param {Object} unit - 被移除的单位对象
     */
    public static function removeUnit(unit:Object):Void {
        _updater.removeUnit(unit);
        // 可选：根据单位类型选择性失效缓存
        // invalidateRelatedCaches(unit);
    }

    /**
     * 批量添加单位
     * @param {Array} units - 要添加的单位数组
     */
    public static function addUnits(units:Array):Void {
        _updater.addUnits(units);
    }

    /**
     * 批量移除单位
     * @param {Array} units - 要移除的单位数组
     */
    public static function removeUnits(units:Array):Void {
        _updater.removeUnits(units);
    }

    /**
     * 根据单位变化选择性失效相关缓存
     * 优化版本号变化时的缓存失效策略
     * 
     * @param {Object} unit - 发生变化的单位
     * @private
     */
    private static function invalidateRelatedCaches(unit:Object):Void {
        var isEnemy:Boolean = unit.是否为敌人;
        
        // 失效与该单位相关的缓存
        if (isEnemy) {
            invalidateCache("敌人");
        } else {
            invalidateCache("友军");
        }
        invalidateCache("全体");
    }

    // ========================================================================
    // 配置管理方法
    // ========================================================================
    
    /**
     * 设置缓存配置
     * @param {Object} config - 配置对象
     */
    public static function setConfig(config:Object):Void {
        if (!config) return;
        
        if (config.maxCacheCount != undefined && config.maxCacheCount > 0) {
            _cacheConfig.maxCacheCount = config.maxCacheCount;
        }
        if (config.autoCleanThreshold != undefined && config.autoCleanThreshold > 0) {
            _cacheConfig.autoCleanThreshold = config.autoCleanThreshold;
        }
        if (config.maxCacheAge != undefined && config.maxCacheAge > 0) {
            _cacheConfig.maxCacheAge = config.maxCacheAge;
        }
        if (config.autoCleanEnabled != undefined) {
            _cacheConfig.autoCleanEnabled = config.autoCleanEnabled;
        }
    }

    /**
     * 获取当前配置
     * @return {Object} 配置对象的副本
     */
    public static function getConfig():Object {
        return {
            maxCacheCount: _cacheConfig.maxCacheCount,
            autoCleanThreshold: _cacheConfig.autoCleanThreshold,
            maxCacheAge: _cacheConfig.maxCacheAge,
            autoCleanEnabled: _cacheConfig.autoCleanEnabled
        };
    }

    // ========================================================================
    // 统计和监控方法
    // ========================================================================
    
    /**
     * 获取缓存数量
     * @return {Number} 当前缓存实例数量
     */
    public static function getCacheCount():Number {
        var count:Number = 0;
        for (var key:String in _cachePool) {
            count++;
        }
        return count;
    }

    /**
     * 获取统计信息
     * @return {Object} 详细的统计信息
     */
    public static function getStats():Object {
        var hitRate:Number = (_stats.totalRequests > 0) 
            ? (_stats.cacheHits / _stats.totalRequests) * 100 
            : 0;
            
        return {
            totalRequests: _stats.totalRequests,
            cacheHits: _stats.cacheHits,
            cacheMisses: _stats.cacheMisses,
            hitRate: hitRate,
            cacheCreations: _stats.cacheCreations,
            cacheUpdates: _stats.cacheUpdates,
            autoCleanRuns: _stats.autoCleanRuns,
            currentCacheCount: getCacheCount()
        };
    }

    /**
     * 重置统计信息
     */
    public static function resetStats():Void {
        _stats.totalRequests = 0;
        _stats.cacheHits = 0;
        _stats.cacheMisses = 0;
        _stats.cacheCreations = 0;
        _stats.cacheUpdates = 0;
        _stats.autoCleanRuns = 0;
    }

    /**
     * 获取缓存池详细信息
     * @return {Object} 缓存池的详细状态
     */
    public static function getCachePoolDetails():Object {
        var details:Object = {
            caches: {},
            totalUnits: 0,
            avgUnitsPerCache: 0,
            oldestCacheAge: 0,
            newestCacheAge: Number.MAX_VALUE
        };
        
        var currentFrame:Number = _root.帧计时器.当前帧数;
        var cacheCount:Number = 0;
        
        for (var key:String in _cachePool) {
            var cache:SortedUnitCache = _cachePool[key];
            var age:Number = currentFrame - cache.lastUpdatedFrame;
            
            details.caches[key] = {
                unitCount: cache.getCount(),
                lastUpdated: cache.lastUpdatedFrame,
                age: age
            };
            
            details.totalUnits += cache.getCount();
            cacheCount++;
            
            if (age > details.oldestCacheAge) {
                details.oldestCacheAge = age;
            }
            if (age < details.newestCacheAge) {
                details.newestCacheAge = age;
            }
        }
        
        if (cacheCount > 0) {
            details.avgUnitsPerCache = details.totalUnits / cacheCount;
        }
        
        if (details.newestCacheAge == Number.MAX_VALUE) {
            details.newestCacheAge = 0;
        }
        
        return details;
    }

    // ========================================================================
    // 调试和诊断方法
    // ========================================================================
    
    /**
     * 生成详细的状态报告
     * @return {String} 格式化的状态报告
     */
    public static function getDetailedStatusReport():String {
        var stats:Object = getStats();
        var config:Object = getConfig();
        var details:Object = getCachePoolDetails();
        
        var report:String = "=== TargetCacheProvider Status Report ===\n\n";
        
        // 基础统计
        report += "Performance Stats:\n";
        report += "  Total Requests: " + stats.totalRequests + "\n";
        report += "  Cache Hit Rate: " + Math.round(stats.hitRate * 100) / 100 + "%\n";
        report += "  Cache Hits: " + stats.cacheHits + "\n";
        report += "  Cache Misses: " + stats.cacheMisses + "\n";
        report += "  Cache Creates: " + stats.cacheCreations + "\n";
        report += "  Cache Updates: " + stats.cacheUpdates + "\n";
        report += "  Auto Cleans: " + stats.autoCleanRuns + "\n\n";
        
        // 缓存状态
        report += "Cache Status:\n";
        report += "  Active Caches: " + details.totalUnits + "/" + config.maxCacheCount + "\n";
        report += "  Total Units Cached: " + details.totalUnits + "\n";
        report += "  Avg Units/Cache: " + Math.round(details.avgUnitsPerCache * 100) / 100 + "\n";
        report += "  Oldest Cache: " + details.oldestCacheAge + " frames\n";
        report += "  Newest Cache: " + details.newestCacheAge + " frames\n\n";
        
        // 配置信息
        report += "Configuration:\n";
        report += "  Max Cache Count: " + config.maxCacheCount + "\n";
        report += "  Auto Clean Threshold: " + config.autoCleanThreshold + "\n";
        report += "  Max Cache Age: " + config.maxCacheAge + " frames\n";
        report += "  Auto Clean Enabled: " + config.autoCleanEnabled + "\n\n";
        
        // 缓存详情
        report += "Cache Details:\n";
        for (var key:String in details.caches) {
            var cache:Object = details.caches[key];
            report += "  " + key + ": " + cache.unitCount + " units (age: " + cache.age + ")\n";
        }
        
        return report;
    }

    /**
     * 执行健康检查
     * @return {Object} 健康检查结果
     */
    public static function performHealthCheck():Object {
        var result:Object = {
            healthy: true,
            warnings: [],
            errors: [],
            recommendations: []
        };
        
        var stats:Object = getStats();
        var config:Object = getConfig();
        var cacheCount:Number = getCacheCount();
        
        // 检查缓存命中率
        if (stats.totalRequests > 100 && stats.hitRate < 50) {
            result.warnings.push("Low cache hit rate: " + Math.round(stats.hitRate) + "%");
            result.recommendations.push("Consider increasing updateInterval or optimizing cache strategy");
        }
        
        // 检查缓存数量
        if (cacheCount >= config.maxCacheCount) {
            result.errors.push("Cache count at maximum: " + cacheCount);
            result.healthy = false;
            result.recommendations.push("Increase maxCacheCount or enable autoClean");
        } else if (cacheCount >= config.autoCleanThreshold) {
            result.warnings.push("Cache count near threshold: " + cacheCount);
        }
        
        // 检查自动清理效果
        if (config.autoCleanEnabled && stats.autoCleanRuns == 0 && cacheCount > 5) {
            result.warnings.push("Auto clean not running despite cache buildup");
            result.recommendations.push("Check autoCleanThreshold configuration");
        }
        
        // 检查updater可用性
        try {
            if (!_updater || typeof _updater.updateCache != "function") {
                result.errors.push("TargetCacheUpdater not available or invalid");
                result.healthy = false;
            }
        } catch (e:Error) {
            result.errors.push("Error accessing TargetCacheUpdater: " + e.message);
            result.healthy = false;
        }
        
        return result;
    }

    /**
     * 优化建议生成器
     * 基于当前统计数据提供性能优化建议
     * @return {Array} 优化建议数组
     */
    public static function getOptimizationRecommendations():Array {
        var recommendations:Array = [];
        var stats:Object = getStats();
        var config:Object = getConfig();
        var details:Object = getCachePoolDetails();
        
        // 基于命中率的建议
        if (stats.totalRequests > 50) {
            if (stats.hitRate < 30) {
                recommendations.push("Very low hit rate - consider increasing updateInterval values");
            } else if (stats.hitRate > 90) {
                recommendations.push("Very high hit rate - you might be able to reduce updateInterval for better responsiveness");
            }
        }
        
        // 基于缓存使用情况的建议
        if (details.avgUnitsPerCache < 5) {
            recommendations.push("Low average units per cache - consider scene-specific cache invalidation");
        }
        
        if (details.oldestCacheAge > config.maxCacheAge * 2) {
            recommendations.push("Some caches are very old - consider reducing maxCacheAge");
        }
        
        // 基于内存使用的建议
        if (getCacheCount() > 10 && details.totalUnits < 50) {
            recommendations.push("Many small caches - consider consolidating cache types");
        }
        
        return recommendations;
    }
}