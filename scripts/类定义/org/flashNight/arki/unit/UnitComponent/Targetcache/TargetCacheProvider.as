// ============================================================================
// 目标缓存提供者（集成FactionManager版本）
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 小工作集优化：使用 Object Map 管理 SortedUnitCache（典型工作集 <= 7 个键）
// 2. 提供高效的缓存获取统一入口，适配高频场景（如子弹队列 updateInterval=1）
// 3. 【重构改进】集成 FactionManager 支持多阵营系统
// 4. 失效由"版本号 + updateInterval"驱动，容量仅作为兜底
//
// 【注意：全体 vs 分阵营 缓存视图一致性】
// "全体" 缓存与 "敌人_X"/"友军_X" 缓存是独立的 cacheKey 条目，
// 各自拥有独立的 lastUpdatedFrame 和 updateInterval 生命周期。
// 因此，在同一帧内，若两类缓存的 updateInterval 不同，
// 它们的数据新鲜度可能不一致（"全体" 可能比 "分阵营" 更旧或更新）。
// 对于需要严格跨视图一致性的场景，调用方应确保使用相同的 updateInterval。
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheProvider {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * 缓存表 - 小工作集优化（通常 <= 7 个键）
     * 【重构】现在使用阵营ID作为缓存键的一部分
     * 结构: {cacheKey: cacheValue对象}
     */
    private static var _cacheRegistry:Object;
    
    /**
     * TargetCacheUpdater 实例引用
     */
    private static var _updater:Object = TargetCacheUpdater;
    
    /**
     * 缓存配置参数
     */
    private static var _cacheConfig:Object = {
        // 缓存表最大容量上限（兜底淘汰）
        maxCacheCapacity: 100,
        forceRefreshThreshold: 600,
        versionCheckEnabled: true,
        detailedStatsEnabled: false
    };
    
    /**
     * 增强版缓存统计信息
     */
    private static var _stats:Object = {
        totalRequests: 0,
        cacheHits: 0,
        cacheMisses: 0,
        cacheCreations: 0,
        cacheUpdates: 0,
        avgAccessTime: 0,
        maxAccessTime: 0,
        totalAccessTime: 0,
        versionMismatches: 0,
        forceRefreshCount: 0
    };

    /**
     * 【性能/内部】复用的临时缓存项（避免高频路径 new Object）
     * 注意：仅作为 updateCache 的 out-param 使用，禁止外部持有引用。
     */
    private static var _tempCacheEntry:Object = {};

    /**
     * 缓存值结构定义
     * 【重构】新增 targetFaction 字段
     */
    private static var _cacheValueSchema:Object = {
        // cache: SortedUnitCache实例
        // createdFrame: 创建帧数
        // lastAccessFrame: 最后访问帧数
        // accessCount: 访问次数
        // dataVersion: 数据版本号
        // requestType: 请求类型
        // targetFaction: 目标阵营ID（新增）
    };

    /**
     * 初始化标志
     */
    private static var _initialized:Boolean = initialize();

    // ========================================================================
    // 初始化和配置方法
    // ========================================================================
    
    /**
     * 静态初始化方法
     * 【重构】确保 FactionManager 已初始化
     */
    public static function initialize():Boolean {
        try {
            // 确保 FactionManager 已初始化
            if (!FactionManager || !FactionManager.getAllFactions) {
                trace("TargetCacheProvider: 等待 FactionManager 初始化");
                return false;
            }
            
            // 确保 TargetCacheUpdater 已初始化
            if (!_updater || !_updater.initialize) {
                trace("TargetCacheProvider: TargetCacheUpdater 不可用");
                return false;
            }
            
            // 初始化 TargetCacheUpdater
            _updater.initialize();
            
            // 初始化缓存表
            _cacheRegistry = {};
            
            // 重置统计信息
            resetStats();
            
            return true;
        } catch (error:Error) {
            trace("TargetCacheProvider初始化失败: " + error.message);
            return false;
        }
    }

    /**
     * 重新初始化缓存系统
     */
    public static function reinitialize(newCapacity:Number):Boolean {
        if (newCapacity != undefined && newCapacity > 0) {
            _cacheConfig.maxCacheCapacity = newCapacity;
        }
        
        return initialize();
    }

    // ========================================================================
    // 核心缓存提供方法（集成FactionManager版本）
    // ========================================================================
    
    /**
     * 获取指定类型的缓存（集成FactionManager版本）
     * 
     * 【重构改进】：
     * 1. 使用 FactionManager 获取目标阵营
     * 2. 基于阵营ID生成缓存键
     * 3. 支持多阵营系统
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
        var startTime:Number = _cacheConfig.detailedStatsEnabled ? getTimer() : 0;
        // 延迟初始化兜底：静态初始化失败时（加载顺序问题）允许首次访问触发初始化
        if (_cacheRegistry == undefined) {
            if (!initialize()) {
                recordAccessTime(startTime);
                return null;
            }
        }
        _stats.totalRequests++;

        try {
            // 定期同步缓存注册表
            if (_stats.totalRequests % 100 == 0) {
                syncCacheRegistry();
            }

            // 【重构】生成基于阵营的缓存键 + 精细化版本号（按 requestType + requesterFaction）
            var isAllRequest:Boolean = (requestType == TargetCacheUpdater.ALL_TYPE);
            var targetFaction:String = isAllRequest ? null : FactionManager.getFactionFromUnit(target);
            var cacheKey:String = TargetCacheUpdater.buildCacheKey(requestType, targetFaction);

            // 获取当前帧数和版本信息
            var currentFrame:Number = _root.帧计时器.当前帧数;
            var currentVersion:Number = 0;
            if (_cacheConfig.versionCheckEnabled) {
                // 旧实现：全局 getCurrentVersion() 会导致“无关阵营变化”触发误失效
                // 新实现：按请求类型 + 请求者阵营计算相关版本号
                currentVersion = isAllRequest ?
                    _updater.getCurrentVersion() :
                    _updater.getVersionForRequest(requestType, targetFaction);
            }

            // 从缓存表中获取缓存值对象
            var cacheValue:Object = _cacheRegistry[cacheKey];
            
            if (cacheValue != null) {
                // 缓存命中 - 执行数据有效性检查
                var isValid:Boolean = validateCacheValue(cacheValue, currentFrame, currentVersion, updateInterval);
                
                if (isValid) {
                    // 缓存有效 - 更新访问统计并返回
                    updateAccessStats(cacheValue, currentFrame);
                    _stats.cacheHits++;
                    
                    recordAccessTime(startTime);
                    return cacheValue.cache;
                } else {
                    // 缓存失效 - 更新现有缓存
                    _stats.cacheMisses++;
                    updateExistingCacheValue(cacheValue, requestType, target, currentFrame, currentVersion);
                    _stats.cacheUpdates++;
                    
                    recordAccessTime(startTime);
                    return cacheValue.cache;
                }
            } else {
                // 缓存未命中 - 创建新缓存
                _stats.cacheMisses++;
                
                var newCacheValue:Object = createNewCacheValue(requestType, target, currentFrame, currentVersion);
                
                // 放入缓存表
                _cacheRegistry[cacheKey] = newCacheValue;
                _stats.cacheCreations++;

                // 兜底容量控制（小工作集场景一般不会触发，但保持行为稳定）
                syncCacheRegistry();
                
                recordAccessTime(startTime);
                return newCacheValue.cache;
            }
            
        } catch (error:Error) {
            trace("缓存获取异常: " + error.message);
            recordAccessTime(startTime);
            return null;
        }
    }

    /**
     * 验证缓存值的有效性
     * @private
     */
    private static function validateCacheValue(
        cacheValue:Object,
        currentFrame:Number,
        currentVersion:Number,
        updateInterval:Number
    ):Boolean {
        // 检查1: 帧间隔验证
        var framesSinceUpdate:Number = currentFrame - cacheValue.cache.lastUpdatedFrame;
        if (framesSinceUpdate >= updateInterval) {
            return false;
        }
        
        // 检查2: 强制刷新阈值
        var framesSinceCreation:Number = currentFrame - cacheValue.createdFrame;
        if (framesSinceCreation > _cacheConfig.forceRefreshThreshold) {
            _stats.forceRefreshCount++;
            return false;
        }
        
        // 检查3: 版本号一致性
        if (_cacheConfig.versionCheckEnabled && cacheValue.dataVersion != currentVersion) {
            _stats.versionMismatches++;
            return false;
        }
        
        return true;
    }

    /**
     * 更新访问统计信息
     * @private
     */
    private static function updateAccessStats(cacheValue:Object, currentFrame:Number):Void {
        cacheValue.lastAccessFrame = currentFrame;
        cacheValue.accessCount++;
    }

    /**
     * 创建新的缓存值对象
     * 【重构】支持阵营系统
     * @private
     */
    private static function createNewCacheValue(
        requestType:String,
        target:Object,
        currentFrame:Number,
        currentVersion:Number
    ):Object {
        // 创建临时缓存项对象
        // 注意：TargetCacheUpdater.updateCache 会完整写入 data/nameIndex/leftValues/rightValues/lastUpdatedFrame，
        // 这里避免预先分配数组/对象造成无效GC。
        var tempCacheEntry:Object = _tempCacheEntry;
        
        // 使用 TargetCacheUpdater 填充数据
        _updater.updateCache(
            _root.gameworld,
            currentFrame,
            requestType,
            FactionManager.getFactionFromUnit(target),
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
        
        // 【重构】获取目标阵营
        var targetFaction:String = FactionManager.getFactionFromUnit(target);
        
        // 构建完整的缓存值对象
        // 使用 updateCache 输出的 post-reconcile 版本号，避免首次 reconcile 导致版本过时
        var cacheValue:Object = {
            cache: cache,
            createdFrame: currentFrame,
            lastAccessFrame: currentFrame,
            accessCount: 1,
            dataVersion: tempCacheEntry.dataVersion,
            requestType: requestType,
            targetFaction: targetFaction  // 【重构】存储阵营ID
        };
        
        return cacheValue;
    }

    /**
     * 更新现有缓存值对象
     * 【重构】支持阵营系统
     * @private
     */
    private static function updateExistingCacheValue(
        cacheValue:Object,
        requestType:String,
        target:Object,
        currentFrame:Number,
        currentVersion:Number
    ):Void {
        // TargetCacheUpdater.updateCache 会写入完整字段，避免预分配导致的无效GC。
        var tempCacheEntry:Object = _tempCacheEntry;
        
        _updater.updateCache(
            _root.gameworld,
            currentFrame,
            requestType,
            FactionManager.getFactionFromUnit(target),
            tempCacheEntry
        );
        
        // 更新SortedUnitCache实例的数据
        cacheValue.cache.updateData(
            tempCacheEntry.data,
            tempCacheEntry.nameIndex,
            tempCacheEntry.leftValues,
            tempCacheEntry.rightValues,
            tempCacheEntry.lastUpdatedFrame
        );

        // 更新元数据（lastUpdatedFrame 已由 updateData() 内部赋值，无需重复设置）
        cacheValue.createdFrame = currentFrame; // 重置创建帧，防止 forceRefreshThreshold 永久触发
        cacheValue.lastAccessFrame = currentFrame;
        cacheValue.accessCount++;
        cacheValue.dataVersion = tempCacheEntry.dataVersion; // 使用 post-reconcile 版本
        
        // 【重构】更新阵营信息
        cacheValue.targetFaction = FactionManager.getFactionFromUnit(target);
    }

    /**
     * 记录访问时间统计
     * @private
     */
    private static function recordAccessTime(startTime:Number):Void {
        if (!_cacheConfig.detailedStatsEnabled) return;
        
        var accessTime:Number = getTimer() - startTime;
        _stats.totalAccessTime += accessTime;
        
        if (accessTime > _stats.maxAccessTime) {
            _stats.maxAccessTime = accessTime;
        }
        
        _stats.avgAccessTime = _stats.totalAccessTime / _stats.totalRequests;
    }

    // ========================================================================
    // 缓存生命周期管理
    // ========================================================================
    
    /**
     * 同步/整理缓存表（容量兜底 + 清理无效项）
     * @private
     */
    private static function syncCacheRegistry():Void {
        if (_cacheRegistry == undefined) return;

        // 1) 清理无效项
        var liveCount:Number = 0;
        for (var key:String in _cacheRegistry) {
            var cv:Object = _cacheRegistry[key];
            if (!cv || !cv.cache) {
                delete _cacheRegistry[key];
            } else {
                liveCount++;
            }
        }

        // 2) 容量兜底：超出时淘汰“最久未访问”的条目
        var capacity:Number = _cacheConfig.maxCacheCapacity;
        if (capacity == undefined || capacity <= 0 || liveCount <= capacity) return;

        var candidates:Array = [];
        for (var k:String in _cacheRegistry) {
            var v:Object = _cacheRegistry[k];
            candidates.push({
                key: k,
                lastAccessFrame: v.lastAccessFrame,
                createdFrame: v.createdFrame
            });
        }

        // 小数组排序成本极低；按 lastAccessFrame 升序（最久未访问最先淘汰）
        candidates.sort(function(a:Object, b:Object):Number {
            var da:Number = a.lastAccessFrame - b.lastAccessFrame;
            if (da != 0) return da;
            return a.createdFrame - b.createdFrame;
        });

        var needRemove:Number = liveCount - capacity;
        for (var i:Number = 0; i < needRemove; i++) {
            delete _cacheRegistry[candidates[i].key];
        }
    }

    /**
     * 智能缓存清理
     * 【重构】支持基于阵营的清理
     */
    public static function clearCache(requestType:String):Void {
        if (requestType) {
            // 按类型清理：不重置全局版本号，只清除对应注册表条目
            clearCacheByType(requestType);
        } else {
            // 全量清理（如重启场景）：重置所有版本号 + 清空注册表
            TargetCacheUpdater.resetVersions();
            _cacheRegistry = {};
        }
    }

    /**
     * 按类型清理缓存
     * @private
     */
    private static function clearCacheByType(requestType:String):Void {
        if (_cacheRegistry == undefined) return;

        var keysToRemove:Array = [];
        
        for (var key:String in _cacheRegistry) {
            if (key.indexOf(requestType) == 0) {
                keysToRemove.push(key);
            }
        }
        
        for (var i:Number = 0; i < keysToRemove.length; i++) {
            var keyToRemove:String = keysToRemove[i];
            delete _cacheRegistry[keyToRemove];
        }
        
        syncCacheRegistry();
    }

    /**
     * 强制刷新所有缓存
     */
    public static function invalidateAllCaches():Void {
        _cacheRegistry = {};
    }

    /**
     * 强制刷新指定类型的缓存
     */
    public static function invalidateCache(requestType:String):Void {
        // 只清除对应类型的注册表条目，不重置全局版本号
        // 版本号属于数据变更追踪，不应被强制失效操作干扰
        clearCacheByType(requestType);
    }

    // ========================================================================
    // 版本号管理（委托给TargetCacheUpdater）
    // ========================================================================
    
    /**
     * 添加单位时更新版本号
     * 【重构】支持阵营系统
     */
    public static function addUnit(unit:Object):Void {
        _updater.addUnit(unit);
        // 不再调用 invalidateAllCaches()：版本号机制会精细化驱动对应阵营缓存失效
    }

    /**
     * 移除单位时更新版本号
     * 【重构】支持阵营系统
     */
    public static function removeUnit(unit:Object):Void {
        _updater.removeUnit(unit);
    }

    /**
     * 批量添加单位
     * 【重构】支持阵营系统
     */
    public static function addUnits(units:Array):Void {
        _updater.addUnits(units);
    }

    /**
     * 批量移除单位
     * 【重构】支持阵营系统
     */
    public static function removeUnits(units:Array):Void {
        _updater.removeUnits(units);
    }

    // ========================================================================
    // 配置管理方法
    // ========================================================================
    
    /**
     * 设置缓存配置
     */
    public static function setConfig(config:Object):Void {
        if (!config) return;
        
        var needReinit:Boolean = false;
        
        // 缓存容量上限
        if (config.maxCacheCapacity != undefined && config.maxCacheCapacity > 0) {
            if (config.maxCacheCapacity != _cacheConfig.maxCacheCapacity) {
                _cacheConfig.maxCacheCapacity = config.maxCacheCapacity;
                needReinit = true;
            }
        }
        
        // 强制刷新阈值
        if (config.forceRefreshThreshold != undefined && config.forceRefreshThreshold > 0) {
            _cacheConfig.forceRefreshThreshold = config.forceRefreshThreshold;
        }
        
        // 版本检查开关
        if (config.versionCheckEnabled != undefined) {
            _cacheConfig.versionCheckEnabled = config.versionCheckEnabled;
        }
        
        // 详细统计开关
        if (config.detailedStatsEnabled != undefined) {
            _cacheConfig.detailedStatsEnabled = config.detailedStatsEnabled;
        }
        
        // 如果容量变更，重新初始化缓存
        if (needReinit) {
            reinitialize();
        }
    }

    /**
     * 获取当前配置
     */
    public static function getConfig():Object {
        return {
            maxCacheCapacity: _cacheConfig.maxCacheCapacity,
            forceRefreshThreshold: _cacheConfig.forceRefreshThreshold,
            versionCheckEnabled: _cacheConfig.versionCheckEnabled,
            detailedStatsEnabled: _cacheConfig.detailedStatsEnabled
        };
    }

    // ========================================================================
    // 统计和监控方法
    // ========================================================================
    
    /**
     * 获取缓存数量
     */
    public static function getCacheCount():Number {
        if (_cacheRegistry == undefined) return 0;
        var count:Number = 0;
        for (var key:String in _cacheRegistry) {
            if (_cacheRegistry[key] && _cacheRegistry[key].cache) {
                count++;
            }
        }
        return count;
    }

    /**
     * 获取增强版统计信息
     */
    public static function getStats():Object {
        var hitRate:Number = (_stats.totalRequests > 0) 
            ? (_stats.cacheHits / _stats.totalRequests) * 100 
            : 0;
        
        var result:Object = {
            totalRequests: _stats.totalRequests,
            cacheHits: _stats.cacheHits,
            cacheMisses: _stats.cacheMisses,
            hitRate: hitRate,
            cacheCreations: _stats.cacheCreations,
            cacheUpdates: _stats.cacheUpdates,
            currentCacheCount: getCacheCount(),
            versionMismatches: _stats.versionMismatches,
            forceRefreshCount: _stats.forceRefreshCount
        };
        
        if (_cacheConfig.detailedStatsEnabled) {
            result.avgAccessTime = _stats.avgAccessTime;
            result.maxAccessTime = _stats.maxAccessTime;
            result.totalAccessTime = _stats.totalAccessTime;
        }
        
        return result;
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
        _stats.avgAccessTime = 0;
        _stats.maxAccessTime = 0;
        _stats.totalAccessTime = 0;
        _stats.versionMismatches = 0;
        _stats.forceRefreshCount = 0;
    }

    /**
     * 获取缓存池详细信息
     * 【重构】包含阵营信息
     */
    public static function getCachePoolDetails():Object {
        var details:Object = {
            caches: {},
            totalUnits: 0,
            avgUnitsPerCache: 0,
            oldestCacheAge: 0,
            newestCacheAge: Number.MAX_VALUE,
            factionDistribution: {}  // 【新增】阵营分布
        };

        if (_cacheRegistry == undefined) {
            return details;
        }

        syncCacheRegistry();
        
        var currentFrame:Number = _root.帧计时器.当前帧数;
        var cacheCount:Number = 0;
        
        // 遍历缓存注册表获取详细信息
        for (var key:String in _cacheRegistry) {
            var cacheValue:Object = _cacheRegistry[key];
            if (!cacheValue || !cacheValue.cache) continue;
            
            var cache:SortedUnitCache = cacheValue.cache;
            var age:Number = currentFrame - cache.lastUpdatedFrame;
            
            // 构建缓存详情
            details.caches[key] = {
                unitCount: cache.getCount(),
                lastUpdated: cache.lastUpdatedFrame,
                age: age,
                createdFrame: cacheValue.createdFrame,
                lastAccessFrame: cacheValue.lastAccessFrame,
                accessCount: cacheValue.accessCount,
                dataVersion: cacheValue.dataVersion,
                requestType: cacheValue.requestType,
                targetFaction: cacheValue.targetFaction  // 【新增】阵营信息
            };
            
            // 【新增】统计阵营分布
            var faction:String = cacheValue.targetFaction || "unknown";
            if (!details.factionDistribution[faction]) {
                details.factionDistribution[faction] = 0;
            }
            details.factionDistribution[faction]++;
            
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
        
        // 添加冷热分布信息
        var dist:Object = getCacheDistribution();
        if (dist) {
            details.distribution = {
                coldCount: dist.coldCount,
                hotCount: dist.hotCount,
                totalItems: dist.totalItems,
                capacity: dist.capacity,
                cache_efficiency: cacheCount > 0 ? Math.round((details.totalUnits / cacheCount) * 100) / 100 : 0
            };
        }

        return details;
    }

    /**
     * 获取缓存冷热分布信息
     * 基于访问次数的轻量划分：accessCount >= 2 为热缓存，否则为冷缓存
     */
    public static function getCacheDistribution():Object {
        var cold:Array = [];
        var hot:Array = [];

        if (_cacheRegistry != undefined) {
            for (var key:String in _cacheRegistry) {
                var cv:Object = _cacheRegistry[key];
                if (!cv || !cv.cache) continue;

                if (cv.accessCount >= 2) {
                    hot.push(key);
                } else {
                    cold.push(key);
                }
            }
        }

        return {
            capacity: _cacheConfig.maxCacheCapacity,
            coldKeys: cold,
            hotKeys: hot,
            coldCount: cold.length,
            hotCount: hot.length,
            totalItems: cold.length + hot.length
        };
    }

    // ========================================================================
    // 调试和诊断方法
    // ========================================================================
    
    /**
     * 生成详细的状态报告
     * 【重构】包含FactionManager集成状态
     */
    public static function getDetailedStatusReport():String {
        var stats:Object = getStats();
        var config:Object = getConfig();
        var details:Object = getCachePoolDetails();
        var dist:Object = getCacheDistribution();

        var report:String = "=== TargetCacheProvider 状态报告 ===\n\n";
        
        // 性能统计
        report += "性能统计:\n";
        report += "  总请求次数: " + stats.totalRequests + "\n";
        report += "  缓存命中率: " + Math.round(stats.hitRate * 100) / 100 + "%\n";
        report += "  缓存命中: " + stats.cacheHits + "\n";
        report += "  缓存未命中: " + stats.cacheMisses + "\n";
        report += "  缓存创建: " + stats.cacheCreations + "\n";
        report += "  缓存更新: " + stats.cacheUpdates + "\n";
        
        if (_cacheConfig.detailedStatsEnabled) {
            report += "  平均访问时间: " + Math.round(stats.avgAccessTime * 100) / 100 + "ms\n";
            report += "  最大访问时间: " + stats.maxAccessTime + "ms\n";
        }
        report += "\n";
        
        // 缓存池状态
        report += "缓存池状态:\n";
        report += "  活跃缓存数: " + stats.currentCacheCount + "\n";
        report += "  总缓存单位: " + details.totalUnits + "\n";
        report += "  平均单位/缓存: " + Math.round(details.avgUnitsPerCache * 100) / 100 + "\n";
        report += "  最老缓存年龄: " + details.oldestCacheAge + " 帧\n";
        report += "  最新缓存年龄: " + details.newestCacheAge + " 帧\n\n";
        
        // 【新增】阵营分布
        report += "阵营分布:\n";
        for (var faction:String in details.factionDistribution) {
            report += "  " + faction + ": " + details.factionDistribution[faction] + " 个缓存\n";
        }
        report += "\n";
        
        // 缓存冷热分布
        if (dist) {
            report += "缓存分布:\n";
            report += "  容量上限: " + dist.capacity + "\n";
            report += "  冷缓存(访问<2): " + dist.coldCount + " 项\n";
            report += "  热缓存(访问>=2): " + dist.hotCount + " 项\n";
            report += "  总缓存项目: " + dist.totalItems + "\n";
            report += "  冷热比例: " + Math.round((dist.coldCount / Math.max(1, dist.totalItems)) * 100) + "% : " +
                     Math.round((dist.hotCount / Math.max(1, dist.totalItems)) * 100) + "%\n\n";
        }
        
        // 数据一致性统计
        report += "数据一致性:\n";
        report += "  版本不匹配: " + stats.versionMismatches + "\n";
        report += "  强制刷新: " + stats.forceRefreshCount + "\n\n";
        
        // 配置信息
        report += "配置信息:\n";
        report += "  缓存容量: " + config.maxCacheCapacity + "\n";
        report += "  强制刷新阈值: " + config.forceRefreshThreshold + " 帧\n";
        report += "  版本检查启用: " + config.versionCheckEnabled + "\n";
        report += "  详细统计启用: " + config.detailedStatsEnabled + "\n\n";
        
        // FactionManager集成状态
        report += "FactionManager集成:\n";
        report += "  状态: " + (FactionManager ? "已集成" : "未集成") + "\n";
        if (FactionManager) {
            var factions:Array = FactionManager.getAllFactions();
            report += "  注册阵营数: " + factions.length + "\n";
            report += "  阵营列表: " + factions.join(", ") + "\n";
        }
        report += "\n";
        
        // 缓存详情
        report += "缓存详情:\n";
        for (var key:String in details.caches) {
            var cacheInfo:Object = details.caches[key];
            report += "  " + key + ": " + cacheInfo.unitCount + " 单位 (年龄: " + cacheInfo.age + 
                      " 帧, 访问: " + cacheInfo.accessCount + " 次, 阵营: " + cacheInfo.targetFaction + ")\n";
        }
        
        return report;
    }

    /**
     * 执行健康检查
     * 【重构】包含FactionManager检查
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
        var dist:Object = getCacheDistribution();

        // 检查缓存表可用性
        if (_cacheRegistry == undefined) {
            result.errors.push("缓存表未初始化");
            result.healthy = false;
            return result;
        }
        
        // 【新增】检查FactionManager可用性
        if (!FactionManager) {
            result.errors.push("FactionManager 未集成");
            result.healthy = false;
        } else {
            try {
                var testFactions:Array = FactionManager.getAllFactions();
                if (!testFactions || testFactions.length == 0) {
                    result.warnings.push("FactionManager 中没有注册的阵营");
                }
            } catch (e:Error) {
                result.errors.push("FactionManager 访问错误: " + e.message);
                result.healthy = false;
            }
        }
        
        // 检查缓存命中率
        if (stats.totalRequests > 20) {
            if (stats.hitRate < 30) {
                result.warnings.push("缓存命中率较低: " + Math.round(stats.hitRate) + "%");
                result.recommendations.push("考虑增加updateInterval或检查访问模式");
            } else if (stats.hitRate > 95) {
                result.recommendations.push("缓存命中率很高，考虑优化更新策略以提高响应性");
            }
        }
        
        // 检查缓存冷热平衡性
        if (dist && dist.totalItems > 0) {
            var coldRatio:Number = dist.coldCount / dist.totalItems;
            if (coldRatio > 0.9) {
                result.warnings.push("冷缓存占比过高(" + Math.round(coldRatio * 100) + "%)，大多数缓存仅被访问一次");
            }
        }
        
        // 检查强制刷新频率
        if (stats.forceRefreshCount > stats.totalRequests * 0.1) {
            result.warnings.push("强制刷新频率过高，考虑调整forceRefreshThreshold");
        }
        
        // 检查版本不匹配
        if (stats.versionMismatches > stats.totalRequests * 0.05) {
            result.warnings.push("版本不匹配频率过高，可能存在数据同步问题");
        }
        
        // 检查updater可用性
        try {
            if (!_updater || typeof _updater.updateCache != "function") {
                result.errors.push("TargetCacheUpdater不可用或无效");
                result.healthy = false;
            }
        } catch (e2:Error) {
            result.errors.push("访问TargetCacheUpdater时出错: " + e2.message);
            result.healthy = false;
        }
        
        return result;
    }

    /**
     * 优化建议生成器
     */
    public static function getOptimizationRecommendations():Array {
        var recommendations:Array = [];
        var stats:Object = getStats();
        var config:Object = getConfig();
        var dist:Object = getCacheDistribution();
        var poolDetails:Object = getCachePoolDetails();

        // 基于命中率的建议
        if (stats.totalRequests > 50) {
            if (stats.hitRate < 40) {
                recommendations.push("命中率较低 - 考虑增加缓存容量或检查访问模式是否过于分散");
            } else if (stats.hitRate > 90) {
                recommendations.push("命中率很高 - 可以考虑减少强制刷新阈值以提高数据新鲜度");
            }
        }

        // 基于冷热分布的建议
        if (dist && dist.totalItems > 0) {
            var coldRatio:Number = dist.coldCount / dist.totalItems;

            if (coldRatio > 0.8) {
                recommendations.push("冷缓存占比过高 - 大量缓存仅被访问一次，访问模式较分散");
            } else if (coldRatio < 0.2) {
                recommendations.push("热缓存占比过高 - 访问模式高度集中，考虑检查是否有冗余缓存键");
            }
        }
        
        // 【新增】基于阵营分布的建议
        if (poolDetails && poolDetails.factionDistribution) {
            var factionCount:Number = 0;
            for (var faction:String in poolDetails.factionDistribution) {
                factionCount++;
            }
            if (factionCount > 5) {
                recommendations.push("阵营数量较多 - 考虑增加缓存容量以适应多阵营系统");
            }
        }
        
        // 基于性能的建议
        if (_cacheConfig.detailedStatsEnabled && stats.avgAccessTime > 5) {
            recommendations.push("平均访问时间较高 - 考虑关闭详细统计以提高性能");
        }
        
        // 基于配置的建议
        if (config.maxCacheCapacity < 50) {
            recommendations.push("缓存容量较小 - 考虑增加缓存容量以容纳更多阵营组合");
        } else if (config.maxCacheCapacity > 500) {
            recommendations.push("缓存容量很大 - 确保有足够内存，并监控内存使用情况");
        }
        
        return recommendations;
    }
}
