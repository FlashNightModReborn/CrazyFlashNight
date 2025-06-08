// ============================================================================
// 目标缓存提供者（TargetCacheProvider）- 基于ARC算法的智能缓存管理器
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 使用自适应替换缓存（ARC）算法管理 SortedUnitCache 实例
// 2. 提供高效的缓存获取统一入口，自动适应不同访问模式
// 3. 协调 TargetCacheUpdater 和 SortedUnitCache 之间的交互
// 4. 智能缓存替换策略，无需手动配置失效时间
// 
// 设计原则：
// - 智能缓存：基于ARC算法的自适应缓存替换策略
// - 高性能：O(1)缓存访问复杂度，优化热点数据访问
// - 自适应：根据访问模式自动调整冷热数据比例
// - 向后兼容：保持原有API接口，升级对外透明
// 
// ARC算法优势：
// - 结合LRU和LFU算法优点，适应多种访问模式
// - 自动平衡最近性和频率，提高缓存命中率
// - 动态调整参数p，无需人工干预
// - 幽灵缓存机制，记住被淘汰项的访问模式
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater;
import org.flashNight.naki.Cache.ARCCache;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheProvider {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * ARC缓存实例 - 核心缓存管理器
     * 使用自适应替换缓存算法，智能管理缓存生命周期
     * 容量设置考虑游戏场景的复杂度和内存限制
     */
    private static var _arcCache:ARCCache;
    
    /**
     * 缓存注册表 - 用于跟踪活跃缓存项的详细信息
     * 结构: {cacheKey: cacheValue对象}
     * 与ARC缓存同步维护，用于提供详细统计信息
     */
    private static var _cacheRegistry:Object;
    
    /**
     * TargetCacheUpdater 实例引用
     * 用于创建和更新缓存数据
     */
    private static var _updater:Object = TargetCacheUpdater;
    
    /**
     * 缓存配置参数
     * 针对ARC算法特点优化的配置
     */
    private static var _cacheConfig:Object = {
        // ARC缓存容量（建议根据游戏复杂度设置，典型值：50-200）
        arcCacheCapacity: 100,
        
        // 强制刷新阈值（帧数）- 防止数据过度陈旧
        forceRefreshThreshold: 600,
        
        // 是否启用版本号检查（额外的数据一致性保障）
        versionCheckEnabled: true,
        
        // 是否启用详细统计（性能分析模式）
        detailedStatsEnabled: false
    };
    
    /**
     * 增强版缓存统计信息
     * 包含ARC算法特有的统计指标
     */
    private static var _stats:Object = {
        // 基础统计
        totalRequests: 0,           // 总请求次数
        cacheHits: 0,               // 缓存命中次数
        cacheMisses: 0,             // 缓存未命中次数
        cacheCreations: 0,          // 缓存创建次数
        cacheUpdates: 0,            // 缓存更新次数
        
        // ARC特有统计
        arcGhostHits: 0,            // ARC幽灵缓存命中次数
        arcAdaptations: 0,          // ARC参数自适应调整次数
        
        // 性能统计
        avgAccessTime: 0,           // 平均访问时间（毫秒）
        maxAccessTime: 0,           // 最大访问时间（毫秒）
        totalAccessTime: 0,         // 总访问时间（毫秒）
        
        // 数据一致性统计
        versionMismatches: 0,       // 版本号不匹配次数
        forceRefreshCount: 0        // 强制刷新次数
    };

    /**
     * 缓存值结构定义
     * 封装SortedUnitCache及其元数据
     */
    private static var _cacheValueSchema:Object = {
        // cache: SortedUnitCache实例
        // createdFrame: 创建帧数
        // lastAccessFrame: 最后访问帧数
        // accessCount: 访问次数
        // dataVersion: 数据版本号
        // requestType: 请求类型
        // isEnemyTarget: 是否敌人目标
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
     * 创建ARC缓存实例并设置默认配置
     * @return {Boolean} 初始化是否成功
     */
    public static function initialize():Boolean {
        try {
            // 创建ARC缓存实例
            _arcCache = new ARCCache(_cacheConfig.arcCacheCapacity);
            
            // 初始化缓存注册表
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
     * 用于运行时重置或配置更改后的重新初始化
     * @param {Number} newCapacity - 新的缓存容量（可选）
     * @return {Boolean} 重新初始化是否成功
     */
    public static function reinitialize(newCapacity:Number):Boolean {
        if (newCapacity != undefined && newCapacity > 0) {
            _cacheConfig.arcCacheCapacity = newCapacity;
        }
        
        return initialize();
    }

    // ========================================================================
    // 核心缓存提供方法
    // ========================================================================
    
    /**
     * 获取指定类型的缓存（核心方法 - ARC增强版）
     * 
     * 利用ARC算法的自适应特性，提供智能缓存管理：
     * 1. 自动适应不同的访问模式（序列、随机、循环等）
     * 2. 动态平衡最近性和频率，提高命中率
     * 3. 基于访问模式自动调整缓存策略
     * 4. 提供O(1)访问复杂度和高性能
     * 
     * @param {String} requestType - 请求类型: "敌人", "友军", "全体"
     * @param {Object} target - 目标单位（用于确定阵营状态）
     * @param {Number} updateInterval - 缓存更新间隔（帧数，用于兼容性检查）
     * @return {SortedUnitCache} 有效的缓存实例，失败时返回null
     */
    public static function getCache(
        requestType:String,
        target:Object,
        updateInterval:Number
    ):SortedUnitCache {
        var startTime:Number = getTimer(); // 性能统计开始
        _stats.totalRequests++;

        try {
            // 定期同步缓存注册表（每100次请求同步一次以平衡性能）
            if (_stats.totalRequests % 100 == 0) {
                syncCacheRegistry();
            }

            // 1. 生成缓存键（与原版兼容）
            var cacheKey:String = generateCacheKey(requestType, target);

            // 2. 获取当前帧数和版本信息
            var currentFrame:Number = _root.帧计时器.当前帧数;
            var currentVersion:Number = _cacheConfig.versionCheckEnabled ? 
                _updater.getCurrentVersion() : 0;

            // 3. 从ARC缓存中获取缓存值对象
            var cacheValue:Object = _arcCache.get(cacheKey);
            
            if (cacheValue != null) {
                // 4. 缓存命中 - 执行数据有效性检查
                var isValid:Boolean = validateCacheValue(cacheValue, currentFrame, currentVersion, updateInterval);
                
                if (isValid) {
                    // 5. 缓存有效 - 更新访问统计并返回
                    updateAccessStats(cacheValue, currentFrame);
                    _stats.cacheHits++;
                    
                    recordAccessTime(startTime);
                    return cacheValue.cache;
                } else {
                    // 6. 缓存失效 - 更新现有缓存
                    _stats.cacheMisses++;
                    updateExistingCacheValue(cacheValue, requestType, target, currentFrame, currentVersion);
                    _stats.cacheUpdates++;
                    
                    recordAccessTime(startTime);
                    return cacheValue.cache;
                }
            } else {
                // 7. 缓存未命中 - 创建新缓存
                _stats.cacheMisses++;
                
                var newCacheValue:Object = createNewCacheValue(requestType, target, currentFrame, currentVersion);
                
                // 8. 将新缓存值放入ARC缓存和注册表
                _arcCache.put(cacheKey, newCacheValue);
                _cacheRegistry[cacheKey] = newCacheValue;
                _stats.cacheCreations++;
                
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
     * 生成缓存键
     * 保持与原版完全兼容的键生成逻辑
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
     * 验证缓存值的有效性
     * 多层验证机制确保数据一致性
     * 
     * @param {Object} cacheValue - 缓存值对象
     * @param {Number} currentFrame - 当前帧数
     * @param {Number} currentVersion - 当前版本号
     * @param {Number} updateInterval - 更新间隔
     * @return {Boolean} 缓存是否有效
     * @private
     */
    private static function validateCacheValue(
        cacheValue:Object,
        currentFrame:Number,
        currentVersion:Number,
        updateInterval:Number
    ):Boolean {
        // 检查1: 帧间隔验证（兼容原版逻辑）
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
        
        // 检查3: 版本号一致性（如果启用）
        if (_cacheConfig.versionCheckEnabled && cacheValue.dataVersion != currentVersion) {
            _stats.versionMismatches++;
            return false;
        }
        
        return true;
    }

    /**
     * 更新访问统计信息
     * 记录缓存值的访问模式
     * 
     * @param {Object} cacheValue - 缓存值对象
     * @param {Number} currentFrame - 当前帧数
     * @private
     */
    private static function updateAccessStats(cacheValue:Object, currentFrame:Number):Void {
        cacheValue.lastAccessFrame = currentFrame;
        cacheValue.accessCount++;
    }

    /**
     * 创建新的缓存值对象
     * 构建包含SortedUnitCache和元数据的完整缓存值
     * 
     * @param {String} requestType - 请求类型
     * @param {Object} target - 目标单位
     * @param {Number} currentFrame - 当前帧数
     * @param {Number} currentVersion - 当前版本号
     * @return {Object} 新创建的缓存值对象
     * @private
     */
    private static function createNewCacheValue(
        requestType:String,
        target:Object,
        currentFrame:Number,
        currentVersion:Number
    ):Object {
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
        
        // 构建完整的缓存值对象
        var cacheValue:Object = {
            cache: cache,
            createdFrame: currentFrame,
            lastAccessFrame: currentFrame,
            accessCount: 1,
            dataVersion: currentVersion,
            requestType: requestType,
            isEnemyTarget: target.是否为敌人
        };
        
        return cacheValue;
    }

    /**
     * 更新现有缓存值对象
     * 刷新缓存数据而不改变ARC缓存中的位置
     * 
     * @param {Object} cacheValue - 要更新的缓存值对象
     * @param {String} requestType - 请求类型
     * @param {Object} target - 目标单位
     * @param {Number} currentFrame - 当前帧数
     * @param {Number} currentVersion - 当前版本号
     * @private
     */
    private static function updateExistingCacheValue(
        cacheValue:Object,
        requestType:String,
        target:Object,
        currentFrame:Number,
        currentVersion:Number
    ):Void {
        var tempCacheEntry:Object = {
            data: [],
            nameIndex: {},
            rightValues: [],
            leftValues: [],
            lastUpdatedFrame: 0
        };
        
        _updater.updateCache(
            _root.gameworld,
            currentFrame,
            requestType,
            target.是否为敌人,
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

        // 更新元数据
        cacheValue.cache.lastUpdatedFrame = currentFrame;
        cacheValue.lastAccessFrame = currentFrame;
        cacheValue.accessCount++;
        cacheValue.dataVersion = currentVersion;
    }

    /**
     * 记录访问时间统计
     * 性能监控和优化分析
     * 
     * @param {Number} startTime - 开始时间
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
    // 缓存生命周期管理（ARC增强版）
    // ========================================================================
    
    /**
     * 清理注册表中被ARC淘汰的缓存项
     * 保持注册表与ARC缓存同步
     * @private
     */
    private static function syncCacheRegistry():Void {
        if (!_arcCache || !_cacheRegistry) return;
        
        // 获取ARC缓存中当前活跃的键
        var activeKeys:Object = {};
        var t1Keys:Array = _arcCache.getT1();
        var t2Keys:Array = _arcCache.getT2();
        
        // 标记活跃键
        for (var i:Number = 0; i < t1Keys.length; i++) {
            // ARC缓存的键带有下划线前缀，需要转换为原始键
            var originalKey:String = convertARCKeyToOriginal(t1Keys[i]);
            if (originalKey) activeKeys[originalKey] = true;
        }
        for (var j:Number = 0; j < t2Keys.length; j++) {
            var originalKey2:String = convertARCKeyToOriginal(t2Keys[j]);
            if (originalKey2) activeKeys[originalKey2] = true;
        }
        
        // 清理注册表中不再活跃的项目
        for (var regKey:String in _cacheRegistry) {
            if (!activeKeys[regKey]) {
                delete _cacheRegistry[regKey];
            }
        }
    }
    
    /**
     * 将ARC缓存键转换为原始缓存键
     * ARC缓存内部使用带下划线前缀的键，需要转换回原始格式
     * @param {String} arcKey - ARC缓存键（如"_敌人_true"）
     * @return {String} 原始缓存键（如"敌人_true"）
     * @private
     */
    private static function convertARCKeyToOriginal(arcKey:String):String {
        if (arcKey && arcKey.charAt(0) == "_") {
            return arcKey.substring(1);
        }
        return arcKey;
    }

    /**
     * 智能缓存清理
     * 利用ARC算法的自适应特性进行智能清理
     * @param {String} requestType - 要清理的请求类型（可选）
     */
    public static function clearCache(requestType:String):Void {
        TargetCacheUpdater.resetVersions(); // 清理更新器缓存
        if (requestType) {
            // 清理特定类型的缓存 - 需要遍历注册表
            clearCacheByType(requestType);
        } else {
            // 清理所有缓存 - 重新初始化ARC缓存和注册表
            _arcCache = new ARCCache(_cacheConfig.arcCacheCapacity);
            _cacheRegistry = {};
        }
    }

    /**
     * 按类型清理缓存的辅助方法
     * @param {String} requestType - 请求类型
     * @private
     */
    private static function clearCacheByType(requestType:String):Void {
        var keysToRemove:Array = [];
        
        for (var key:String in _cacheRegistry) {
            if (key.indexOf(requestType) == 0) {
                keysToRemove.push(key);
            }
        }
        
        for (var i:Number = 0; i < keysToRemove.length; i++) {
            var keyToRemove:String = keysToRemove[i];
            delete _cacheRegistry[keyToRemove];
            
            // 【修复后的集成】调用 ARCCache 的 remove 方法
            if (_arcCache != null && typeof _arcCache.remove == "function") {
                // 注意：ARCCache的remove方法需要原始key，而不是带"_"前缀的uid
                // TargetCacheProvider的cacheKey就是原始key
                _arcCache.remove(keyToRemove);
            }
        }
        
        // syncCacheRegistry() 变得有些多余，因为已经手动清理了
        // 不过保留也无妨，可以作为一种安全保障
        syncCacheRegistry();
    }

    /**
     * 强制刷新所有缓存
     * 标记所有缓存为需要更新状态
     */
    public static function invalidateAllCaches():Void {
        // ARC缓存的invalidate策略：重新初始化
        // 这比遍历所有项目更高效
        _arcCache = new ARCCache(_cacheConfig.arcCacheCapacity);
        _cacheRegistry = {};
    }

    /**
     * 强制刷新指定类型的缓存
     * @param {String} requestType - 要刷新的请求类型
     */
    public static function invalidateCache(requestType:String):Void {
        TargetCacheUpdater.resetVersions(); // 清理更新器缓存
        clearCacheByType(requestType);
    }

    // ========================================================================
    // 版本号管理（委托给TargetCacheUpdater）
    // ========================================================================
    
    /**
     * 添加单位时更新版本号
     * 触发全局缓存失效以保证数据一致性
     * @param {Object} unit - 新增的单位对象
     */
    public static function addUnit(unit:Object):Void {
        _updater.addUnit(unit);
        
        // ARC缓存策略：重大数据变更时完全失效缓存
        // 这确保了数据一致性，而ARC算法会快速重建热点数据
        invalidateAllCaches();
    }
    
    /**
     * 移除单位时更新版本号
     * 触发全局缓存失效以保证数据一致性
     * @param {Object} unit - 被移除的单位对象
     */
    public static function removeUnit(unit:Object):Void {
        _updater.removeUnit(unit);
        invalidateAllCaches();
    }

    /**
     * 批量添加单位
     * 优化版本：批量操作后统一失效缓存
     * @param {Array} units - 要添加的单位数组
     */
    public static function addUnits(units:Array):Void {
        _updater.addUnits(units);
        invalidateAllCaches();
    }

    /**
     * 批量移除单位
     * 优化版本：批量操作后统一失效缓存
     * @param {Array} units - 要移除的单位数组
     */
    public static function removeUnits(units:Array):Void {
        _updater.removeUnits(units);
        invalidateAllCaches();
    }

    // ========================================================================
    // 配置管理方法（ARC增强版）
    // ========================================================================
    
    /**
     * 设置缓存配置
     * 支持ARC特有的配置参数
     * @param {Object} config - 配置对象
     */
    public static function setConfig(config:Object):Void {
        if (!config) return;
        
        var needReinit:Boolean = false;
        
        // ARC缓存容量设置
        if (config.arcCacheCapacity != undefined && config.arcCacheCapacity > 0) {
            if (config.arcCacheCapacity != _cacheConfig.arcCacheCapacity) {
                _cacheConfig.arcCacheCapacity = config.arcCacheCapacity;
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
     * @return {Object} 配置对象的副本
     */
    public static function getConfig():Object {
        return {
            arcCacheCapacity: _cacheConfig.arcCacheCapacity,
            forceRefreshThreshold: _cacheConfig.forceRefreshThreshold,
            versionCheckEnabled: _cacheConfig.versionCheckEnabled,
            detailedStatsEnabled: _cacheConfig.detailedStatsEnabled
        };
    }

    // ========================================================================
    // 统计和监控方法（ARC增强版）
    // ========================================================================
    
    /**
     * 获取缓存数量
     * 利用ARC缓存的内部统计
     * @return {Number} 当前缓存实例数量
     */
    public static function getCacheCount():Number {
        // 注意：需要根据ARCCache实现添加size()方法
        // 或者维护内部计数器
        return _arcCache ? (_arcCache.getT1().length + _arcCache.getT2().length) : 0;
    }

    /**
     * 获取增强版统计信息
     * 包含ARC算法特有的统计指标
     * @return {Object} 详细的统计信息
     */
    public static function getStats():Object {
        var hitRate:Number = (_stats.totalRequests > 0) 
            ? (_stats.cacheHits / _stats.totalRequests) * 100 
            : 0;
        
        var result:Object = {
            // 基础统计
            totalRequests: _stats.totalRequests,
            cacheHits: _stats.cacheHits,
            cacheMisses: _stats.cacheMisses,
            hitRate: hitRate,
            cacheCreations: _stats.cacheCreations,
            cacheUpdates: _stats.cacheUpdates,
            
            // ARC特有统计
            arcGhostHits: _stats.arcGhostHits,
            arcAdaptations: _stats.arcAdaptations,
            
            // 缓存状态
            currentCacheCount: getCacheCount(),
            
            // 数据一致性统计
            versionMismatches: _stats.versionMismatches,
            forceRefreshCount: _stats.forceRefreshCount
        };
        
        // 性能统计（如果启用详细统计）
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
        _stats.arcGhostHits = 0;
        _stats.arcAdaptations = 0;
        _stats.avgAccessTime = 0;
        _stats.maxAccessTime = 0;
        _stats.totalAccessTime = 0;
        _stats.versionMismatches = 0;
        _stats.forceRefreshCount = 0;
    }

    /**
     * 获取缓存池详细信息
     * 基于ARC缓存和注册表提供与原版兼容的详细统计信息
     * @return {Object} 缓存池的详细状态
     */
    public static function getCachePoolDetails():Object {
        // 确保注册表与ARC缓存同步
        syncCacheRegistry();
        
        var details:Object = {
            caches: {},
            totalUnits: 0,
            avgUnitsPerCache: 0,
            oldestCacheAge: 0,
            newestCacheAge: Number.MAX_VALUE
        };
        
        var currentFrame:Number = _root.帧计时器.当前帧数;
        var cacheCount:Number = 0;
        
        // 遍历缓存注册表获取详细信息
        for (var key:String in _cacheRegistry) {
            var cacheValue:Object = _cacheRegistry[key];
            if (!cacheValue || !cacheValue.cache) continue;
            
            var cache:SortedUnitCache = cacheValue.cache;
            var age:Number = currentFrame - cache.lastUpdatedFrame;
            
            // 构建与原版兼容的缓存详情
            details.caches[key] = {
                unitCount: cache.getCount(),
                lastUpdated: cache.lastUpdatedFrame,
                age: age,
                // ARC增强信息
                createdFrame: cacheValue.createdFrame,
                lastAccessFrame: cacheValue.lastAccessFrame,
                accessCount: cacheValue.accessCount,
                dataVersion: cacheValue.dataVersion,
                requestType: cacheValue.requestType,
                isEnemyTarget: cacheValue.isEnemyTarget
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
        
        // 添加ARC特有的详细信息
        var arcDetails:Object = getARCCacheDetails();
        if (arcDetails) {
            details.arcInfo = {
                T1_size: arcDetails.T1_size,
                T2_size: arcDetails.T2_size,
                B1_size: arcDetails.B1_size,
                B2_size: arcDetails.B2_size,
                total_cached_items: arcDetails.total_cached_items,
                cold_hot_ratio: arcDetails.T1_size + ":" + arcDetails.T2_size,
                cache_efficiency: cacheCount > 0 ? Math.round((details.totalUnits / cacheCount) * 100) / 100 : 0
            };
        }
        
        return details;
    }

    /**
     * 获取ARC缓存详细信息
     * 提供ARC算法的内部状态视图
     * @return {Object} ARC缓存的详细状态
     */
    public static function getARCCacheDetails():Object {
        if (!_arcCache) return null;
        
        return {
            capacity: _cacheConfig.arcCacheCapacity,
            T1_queue: _arcCache.getT1(),
            T2_queue: _arcCache.getT2(),
            B1_queue: _arcCache.getB1(),
            B2_queue: _arcCache.getB2(),
            T1_size: _arcCache.getT1().length,
            T2_size: _arcCache.getT2().length,
            B1_size: _arcCache.getB1().length,
            B2_size: _arcCache.getB2().length,
            total_cached_items: _arcCache.getT1().length + _arcCache.getT2().length
        };
    }

    // ========================================================================
    // 调试和诊断方法（ARC增强版）
    // ========================================================================
    
    /**
     * 生成详细的状态报告
     * 包含ARC算法特有的诊断信息
     * @return {String} 格式化的状态报告
     */
    public static function getDetailedStatusReport():String {
        var stats:Object = getStats();
        var config:Object = getConfig();
        var details:Object = getCachePoolDetails();
        var arcDetails:Object = getARCCacheDetails();
        
        var report:String = "=== TargetCacheProvider ARC增强版状态报告 ===\n\n";
        
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
        
        // 缓存池状态（使用getCachePoolDetails的结果）
        report += "缓存池状态:\n";
        report += "  活跃缓存数: " + stats.currentCacheCount + "\n";
        report += "  总缓存单位: " + details.totalUnits + "\n";
        report += "  平均单位/缓存: " + Math.round(details.avgUnitsPerCache * 100) / 100 + "\n";
        report += "  最老缓存年龄: " + details.oldestCacheAge + " 帧\n";
        report += "  最新缓存年龄: " + details.newestCacheAge + " 帧\n\n";
        
        // ARC算法状态
        if (arcDetails) {
            report += "ARC算法状态:\n";
            report += "  缓存容量: " + arcDetails.capacity + "\n";
            report += "  T1队列(冷数据): " + arcDetails.T1_size + " 项\n";
            report += "  T2队列(热数据): " + arcDetails.T2_size + " 项\n";
            report += "  B1队列(冷幽灵): " + arcDetails.B1_size + " 项\n";
            report += "  B2队列(热幽灵): " + arcDetails.B2_size + " 项\n";
            report += "  总缓存项目: " + arcDetails.total_cached_items + "\n";
            report += "  冷热比例: " + Math.round((arcDetails.T1_size / Math.max(1, arcDetails.total_cached_items)) * 100) + "% : " + 
                     Math.round((arcDetails.T2_size / Math.max(1, arcDetails.total_cached_items)) * 100) + "%\n\n";
        }
        
        // 数据一致性统计
        report += "数据一致性:\n";
        report += "  版本不匹配: " + stats.versionMismatches + "\n";
        report += "  强制刷新: " + stats.forceRefreshCount + "\n\n";
        
        // 配置信息
        report += "配置信息:\n";
        report += "  ARC缓存容量: " + config.arcCacheCapacity + "\n";
        report += "  强制刷新阈值: " + config.forceRefreshThreshold + " 帧\n";
        report += "  版本检查启用: " + config.versionCheckEnabled + "\n";
        report += "  详细统计启用: " + config.detailedStatsEnabled + "\n\n";
        
        // 缓存详情（来自getCachePoolDetails）
        report += "缓存详情:\n";
        for (var key:String in details.caches) {
            var cacheInfo:Object = details.caches[key];
            report += "  " + key + ": " + cacheInfo.unitCount + " 单位 (年龄: " + cacheInfo.age + " 帧, 访问: " + cacheInfo.accessCount + " 次)\n";
        }
        
        return report;
    }

    /**
     * 执行健康检查
     * 针对ARC缓存的专门诊断
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
        var arcDetails:Object = getARCCacheDetails();
        
        // 检查ARC缓存可用性
        if (!_arcCache) {
            result.errors.push("ARC缓存实例不存在");
            result.healthy = false;
            return result;
        }
        
        // 检查缓存命中率 (降低了触发阈值)
        if (stats.totalRequests > 20) { // <--- 已修复：将阈值从 100 改为 20
            if (stats.hitRate < 30) {
                result.warnings.push("缓存命中率较低: " + Math.round(stats.hitRate) + "%");
                result.recommendations.push("考虑增加updateInterval或检查访问模式");
            } else if (stats.hitRate > 95) {
                result.recommendations.push("缓存命中率很高，考虑优化更新策略以提高响应性");
            }
        }
        
        // 检查ARC队列平衡性
        if (arcDetails && arcDetails.total_cached_items > 0) {
            var t1Ratio:Number = arcDetails.T1_size / arcDetails.total_cached_items;
            if (t1Ratio > 0.9) {
                result.warnings.push("T1队列占比过高(" + Math.round(t1Ratio * 100) + "%)，可能存在缓存冷启动问题");
            } else if (t1Ratio < 0.1) {
                result.warnings.push("T2队列占比过高(" + Math.round((1-t1Ratio) * 100) + "%)，可能缺乏新数据探索");
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
        } catch (e:Error) {
            result.errors.push("访问TargetCacheUpdater时出错: " + e.message);
            result.healthy = false;
        }
        
        return result;
    }

    /**
     * 优化建议生成器
     * 基于ARC算法特性和当前统计数据提供优化建议
     * @return {Array} 优化建议数组
     */
    public static function getOptimizationRecommendations():Array {
        var recommendations:Array = [];
        var stats:Object = getStats();
        var config:Object = getConfig();
        var arcDetails:Object = getARCCacheDetails();
        
        // 基于命中率的建议
        if (stats.totalRequests > 50) {
            if (stats.hitRate < 40) {
                recommendations.push("命中率较低 - ARC算法需要更多时间学习访问模式，或考虑增加缓存容量");
            } else if (stats.hitRate > 90) {
                recommendations.push("命中率很高 - 可以考虑减少强制刷新阈值以提高数据新鲜度");
            }
        }
        
        // 基于ARC队列分析的建议
        if (arcDetails && arcDetails.total_cached_items > 0) {
            var t1Ratio:Number = arcDetails.T1_size / arcDetails.total_cached_items;
            
            if (t1Ratio > 0.8) {
                recommendations.push("冷数据占比过高 - 系统可能处于探索阶段，这是正常的学习过程");
            } else if (t1Ratio < 0.2) {
                recommendations.push("热数据占比过高 - 访问模式可能过于集中，考虑增加缓存容量");
            }
            
            if (arcDetails.B1_size + arcDetails.B2_size > arcDetails.capacity) {
                recommendations.push("幽灵队列过大 - ARC算法正在积极学习，这有助于提高未来命中率");
            }
        }
        
        // 基于性能的建议
        if (_cacheConfig.detailedStatsEnabled && stats.avgAccessTime > 5) {
            recommendations.push("平均访问时间较高 - 考虑关闭详细统计以提高性能");
        }
        
        // 基于配置的建议
        if (config.arcCacheCapacity < 50) {
            recommendations.push("缓存容量较小 - 考虑增加ARC缓存容量以提高算法效果");
        } else if (config.arcCacheCapacity > 500) {
            recommendations.push("缓存容量很大 - 确保有足够内存，并监控内存使用情况");
        }
        
        return recommendations;
    }
}