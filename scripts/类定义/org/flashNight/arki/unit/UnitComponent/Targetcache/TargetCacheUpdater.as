// ============================================================================
// 目标缓存更新器（集成FactionManager版本）
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 收集、排序并写入 cacheEntry
// 2. 自动生成 nameIndex，支持 O(1) 索引定位
// 3. 新增 rightValues/leftValues 数组，优化坐标值访问性能
// 4. 【重构改进】集成 FactionManager 进行阵营关系判断
// 5. 使用 AdaptiveThresholdOptimizer 处理阈值逻辑
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizer;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.naki.Sort.TimSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * 缓存池对象
     * 【重构】现在使用阵营ID作为缓存键的一部分
     * 结构: {cacheKey: {tempList: Array, tempVersion: Number}}
     * - cacheKey: 缓存键，格式为 "敌人_FACTION_ID" 或 "友军_FACTION_ID" 或 "全体"
     * - tempList: 临时单位列表，用于减少重复收集
     * - tempVersion: 版本号，用于判断是否需要重新收集
     */
    private static var _cachePool:Object = {};
    
    /**
     * 【重构】基于阵营的版本控制
     * 不再使用简单的敌人/友军二分法，而是为每个阵营维护独立的版本号
     * 结构: {factionId: versionNumber}
     */
    private static var _factionVersions:Object = {};

    /**
     * 缓存有效性阈值访问器
     * 委托给 AdaptiveThresholdOptimizer 管理
     */
    public static function get _THRESHOLD():Number {
        return AdaptiveThresholdOptimizer.getThreshold();
    }

    /**
     * 请求类型常量定义
     */
    private static var _ENEMY_TYPE:String = "敌人";
    private static var _ALLY_TYPE:String  = "友军";
    private static var _ALL_TYPE:String   = "全体";

    /**
     * 初始化标志
     */
    private static var _initialized:Boolean = initialize();

    // ========================================================================
    // 初始化方法
    // ========================================================================
    
    /**
     * 初始化方法
     * 【重构】为所有注册的阵营初始化版本号
     */
    public static function initialize():Boolean {

        FactionManager.initialize();
        var arr:Array = FactionManager.getAllFactions();
        // trace("initialize" + arr);
        // 确保 FactionManager 已初始化
        if (!FactionManager || !arr) {
            // trace("TargetCacheUpdater: FactionManager 未初始化");
            return false;
        }
        
        // 为所有阵营初始化版本号
        var allFactions:Array = FactionManager.getAllFactions();
        for (var i:Number = 0; i < allFactions.length; i++) {
            var factionId:String = allFactions[i];
            if (!_factionVersions[factionId]) {
                _factionVersions[factionId] = 0;
            }
        }
        
        return true;
    }

    // ========================================================================
    // 核心更新方法（集成FactionManager版本）
    // ========================================================================
    
    /**
     * 更新缓存的核心方法（集成FactionManager版本）
     * 
     * 【重构改进】：
     * 1. 使用 FactionManager 判断阵营关系
     * 2. 支持多阵营系统，不再局限于敌人/友军二分法
     * 3. 使用阵营ID而非布尔值构建缓存键
     * 
     * @param {Object} gameWorld - 游戏世界对象，包含所有单位
     * @param {Number} currentFrame - 当前帧数，用于更新时间戳
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {Boolean} targetIsEnemy - 目标（请求者）是否为敌人（向后兼容参数）
     * @param {Object} cacheEntry - 要更新的缓存项对象
     */
    public static function updateCache(
        gameWorld:Object,
        currentFrame:Number,
        requestType:String,
        targetIsEnemy:Boolean,
        cacheEntry:Object
    ):Void {
        // 判断请求类型
        var isAllRequest:Boolean   = (requestType == _ALL_TYPE);
        var isEnemyRequest:Boolean = (requestType == _ENEMY_TYPE);

        // 【重构】创建一个假的单位对象来获取请求者的阵营
        // 这是为了向后兼容，理想情况下应该直接传入单位对象或阵营ID
        var requesterUnit:Object = { 是否为敌人: targetIsEnemy };
        var requesterFaction:String = FactionManager.getFactionFromUnit(requesterUnit);

        // 生成缓存键
        var cacheKey:String = isAllRequest
            ? _ALL_TYPE
            : requestType + "_" + requesterFaction;

        // 获取或创建缓存类型数据
        if (!_cachePool[cacheKey]) {
            _cachePool[cacheKey] = { tempList: [], tempVersion: -1 };
        }
        var cacheTypeData:Object = _cachePool[cacheKey];

        // 【重构】计算版本号 - 基于阵营版本控制
        var currentVersion:Number = _calculateVersion(requestType, requesterFaction);

        // 检查是否需要更新临时列表
        if (cacheTypeData.tempVersion < currentVersion) {
            // 重新收集有效单位
            cacheTypeData.tempList.length = 0;

            // 根据请求类型收集单位
            if (isAllRequest) {
                _collectAllValidUnits(gameWorld, cacheTypeData.tempList);
            } else {
                // 【重构】使用新的基于FactionManager的收集方法
                _collectValidUnitsWithFactionManager(
                    gameWorld,
                    requesterFaction,
                    isEnemyRequest,
                    cacheTypeData.tempList
                );
            }
            // 更新临时列表版本号
            cacheTypeData.tempVersion = currentVersion;
        }

        // 插入排序（按 left 升序）
        var list:Array = cacheTypeData.tempList;
        var len:Number = list.length;
        if (len > 64) {
            TimSort.sort(list, function(a:Object, b:Object):Number {
                return a.aabbCollider.left - b.aabbCollider.left;
            });
        } else if (len > 1) {
            var i:Number = 1;
            do {
                var key:Object = list[i];
                var leftVal:Number = key.aabbCollider.left;
                var j:Number = i - 1;
                while (j >= 0 && list[j].aabbCollider.left > leftVal) {
                    list[j + 1] = list[j--];
                }
                list[j + 1] = key;
            } while (++i < len);
        }

        // 单循环完成所有数据提取
        var leftValues:Array = [];
        var rightValues:Array = [];
        var newNameIndex:Object = {};
        
        for (var k:Number = 0; k < len; k++) {
            var unit:Object = list[k];
            var collider:Object = unit.aabbCollider;
            
            leftValues[k] = collider.left;
            rightValues[k] = collider.right;
            newNameIndex[unit._name] = k;
        }

        // 使用 AdaptiveThresholdOptimizer 更新阈值
        AdaptiveThresholdOptimizer.updateThreshold(leftValues);

        // 更新缓存项
        cacheEntry.data              = list;
        cacheEntry.nameIndex         = newNameIndex;
        cacheEntry.rightValues       = rightValues;
        cacheEntry.leftValues        = leftValues;
        cacheEntry.lastUpdatedFrame  = currentFrame;
    }

    // ========================================================================
    // 【新增】基于阵营的版本号计算
    // ========================================================================
    
    /**
     * 计算当前版本号
     * 【重构】基于阵营系统计算版本号
     * 
     * @param {String} requestType - 请求类型
     * @param {String} requesterFaction - 请求者阵营
     * @return {Number} 计算得出的版本号
     * @private
     */
    private static function _calculateVersion(requestType:String, requesterFaction:String):Number {
        if (requestType == _ALL_TYPE) {
            // 全体请求：所有阵营版本号之和
            var totalVersion:Number = 0;
            for (var faction:String in _factionVersions) {
                totalVersion += _factionVersions[faction];
            }
            return totalVersion;
        } else if (requestType == _ENEMY_TYPE) {
            // 敌人请求：所有敌对阵营版本号之和
            var enemyFactions:Array = FactionManager.getEnemyFactions(requesterFaction);
            var enemyVersion:Number = 0;
            for (var i:Number = 0; i < enemyFactions.length; i++) {
                enemyVersion += _factionVersions[enemyFactions[i]] || 0;
            }
            return enemyVersion;
        } else {
            // 友军请求：所有友好阵营版本号之和
            var allyFactions:Array = FactionManager.getAllyFactions(requesterFaction);
            var allyVersion:Number = 0;
            for (var j:Number = 0; j < allyFactions.length; j++) {
                allyVersion += _factionVersions[allyFactions[j]] || 0;
            }
            return allyVersion;
        }
    }

    // ========================================================================
    // 【重构】基于FactionManager的单位收集方法
    // ========================================================================
    
    /**
     * 使用FactionManager收集有效单位
     * 【重构】替代原有的基于布尔值的收集逻辑
     * 
     * @param {Object} gameWorld - 游戏世界对象
     * @param {String} requesterFaction - 请求者的阵营ID
     * @param {Boolean} isEnemyRequest - 是否请求敌人数据
     * @param {Array} targetList - 存储符合条件的单位（输出参数）
     * @private
     */
    private static function _collectValidUnitsWithFactionManager(
        gameWorld:Object,
        requesterFaction:String,
        isEnemyRequest:Boolean,
        targetList:Array
    ):Void {
        var key:String, u:Object;
        
        for (key in gameWorld) {
            u = gameWorld[key];
            
            // 仅处理存活单位
            if (u.hp > 0) {
                // 获取单位的阵营
                var unitFaction:String = FactionManager.getFactionFromUnit(u);
                
                // 使用FactionManager判断关系
                var shouldInclude:Boolean = false;
                if (isEnemyRequest) {
                    // 敌人请求：检查是否为敌对关系
                    shouldInclude = FactionManager.areEnemies(requesterFaction, unitFaction);
                } else {
                    // 友军请求：检查是否为友好关系
                    shouldInclude = FactionManager.areAllies(requesterFaction, unitFaction);
                }
                /*
                _root.服务器.发布服务器消息(key + " : " + unitFaction + " , " + 
                FactionManager.areEnemies(requesterFaction, unitFaction) + " " +
                FactionManager.areAllies(requesterFaction, unitFaction) + " : " +
                shouldInclude)
                */
                
                if (shouldInclude) {
                    // 更新碰撞器并添加到目标列表
                    u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
                }
            }
        
        }
    }

    /**
     * 收集所有有效单位
     * 不区分阵营，收集所有存活的单位
     * 
     * @param {Object} gameWorld - 游戏世界对象，包含所有单位
     * @param {Array} targetList - 存储所有有效单位（输出参数）
     * @private
     */
    private static function _collectAllValidUnits(
        gameWorld:Object,
        targetList:Array
    ):Void {
        var key:String, u:Object;
        
        for (key in gameWorld) {
            u = gameWorld[key];
            if (u.hp > 0) {
                // 更新碰撞器并添加到目标列表
                u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
            }
        }
    }

    // ========================================================================
    // 【重构】基于阵营的版本控制
    // ========================================================================
    
    /**
     * 添加单位时更新版本号
     * 【重构】基于单位的阵营更新对应的版本号
     * 
     * @param {Object} unit - 新增的单位对象
     */
    public static function addUnit(unit:Object):Void {
        var faction:String = FactionManager.getFactionFromUnit(unit);
        if (!_factionVersions[faction]) {
            _factionVersions[faction] = 0;
        }
        _factionVersions[faction]++;
    }
    
    /**
     * 移除单位时更新版本号
     * 【重构】基于单位的阵营更新对应的版本号
     * 
     * @param {Object} unit - 被移除的单位对象
     */
    public static function removeUnit(unit:Object):Void {
        var faction:String = FactionManager.getFactionFromUnit(unit);
        if (!_factionVersions[faction]) {
            _factionVersions[faction] = 0;
        }
        _factionVersions[faction]++;
    }

    /**
     * 批量添加单位
     * 【重构】基于阵营批量更新版本号
     * 
     * @param {Array} units - 要添加的单位数组
     */
    public static function addUnits(units:Array):Void {
        var factionCounts:Object = {};
        
        // 统计各阵营的单位数量
        for (var i:Number = 0; i < units.length; i++) {
            var faction:String = FactionManager.getFactionFromUnit(units[i]);
            if (!factionCounts[faction]) {
                factionCounts[faction] = 0;
            }
            factionCounts[faction]++;
        }
        
        // 批量更新版本号
        for (var factionId:String in factionCounts) {
            if (!_factionVersions[factionId]) {
                _factionVersions[factionId] = 0;
            }
            _factionVersions[factionId] += factionCounts[factionId];
        }
    }

    /**
     * 批量移除单位
     * 【重构】基于阵营批量更新版本号
     * 
     * @param {Array} units - 要移除的单位数组
     */
    public static function removeUnits(units:Array):Void {
        var factionCounts:Object = {};
        
        // 统计各阵营的单位数量
        for (var i:Number = 0; i < units.length; i++) {
            var faction:String = FactionManager.getFactionFromUnit(units[i]);
            if (!factionCounts[faction]) {
                factionCounts[faction] = 0;
            }
            factionCounts[faction]++;
        }
        
        // 批量更新版本号
        for (var factionId:String in factionCounts) {
            if (!_factionVersions[factionId]) {
                _factionVersions[factionId] = 0;
            }
            _factionVersions[factionId] += factionCounts[factionId];
        }
    }

    /**
     * 获取版本号信息
     * 【重构】返回基于阵营的版本信息
     * 
     * @return {Object} 包含所有版本号的对象
     */
    public static function getVersionInfo():Object {
        var info:Object = {
            factionVersions: {},
            totalVersion: 0
        };
        
        for (var faction:String in _factionVersions) {
            info.factionVersions[faction] = _factionVersions[faction];
            info.totalVersion += _factionVersions[faction];
        }
        
        // 【向后兼容】提供旧版本号映射
        info.enemyVersion = _factionVersions[FactionManager.FACTION_ENEMY] || 0;
        info.allyVersion = _factionVersions[FactionManager.FACTION_PLAYER] || 0;
        
        return info;
    }

    /**
     * 重置所有版本号
     * 【重构】重置所有阵营的版本号
     */
    public static function resetVersions():Void {
        // 重置所有阵营版本号
        for (var faction:String in _factionVersions) {
            _factionVersions[faction] = 0;
        }
        
        // 清空缓存池
        for (var key:String in _cachePool) {
            delete _cachePool[key];
        }
        _cachePool = {};
    }

    /**
     * 获取当前版本号
     * 【新增】用于外部查询当前的全局版本号
     * 
     * @return {Number} 当前的全局版本号
     */
    public static function getCurrentVersion():Number {
        var totalVersion:Number = 0;
        for (var faction:String in _factionVersions) {
            totalVersion += _factionVersions[faction];
        }
        return totalVersion;
    }

    // ========================================================================
    // 以下方法保持不变，继承自原版本
    // ========================================================================
    
    public static function setAdaptiveParams(
        alpha:Number,
        densityFactor:Number,
        minThreshold:Number,
        maxThreshold:Number
    ):Void {
        AdaptiveThresholdOptimizer.setParams(alpha, densityFactor, minThreshold, maxThreshold);
    }

    public static function applyThresholdPreset(presetName:String):Boolean {
        return AdaptiveThresholdOptimizer.applyPreset(presetName);
    }

    public static function getCurrentThreshold():Number {
        return AdaptiveThresholdOptimizer.getThreshold();
    }

    public static function getThresholdStatus():Object {
        return AdaptiveThresholdOptimizer.getStatus();
    }

    public static function getCachePoolStats():Object {
        var stats:Object = {
            totalPools: 0,
            poolDetails: {},
            memoryUsage: 0
        };
        
        for (var key:String in _cachePool) {
            var pool:Object = _cachePool[key];
            stats.totalPools++;
            stats.poolDetails[key] = {
                listLength: pool.tempList.length,
                version: pool.tempVersion
            };
            stats.memoryUsage++;
        }
        
        return stats;
    }

    public static function clearCachePool(requestType:String):Void {
        if (requestType) {
            for (var key:String in _cachePool) {
                if (key.indexOf(requestType) == 0) {
                    delete _cachePool[key];
                }
            }
        } else {
            for (var key2:String in _cachePool) {
                delete _cachePool[key2];
            }
            _cachePool = {};
        }
    }

    public static function getDetailedStatusReport():String {
        var versionInfo:Object = getVersionInfo();
        var poolStats:Object = getCachePoolStats();
        var thresholdStatus:Object = getThresholdStatus();
        
        var report:String = "=== TargetCacheUpdater Status Report ===\n\n";
        
        // 版本信息（基于阵营）
        report += "Faction Version Numbers:\n";
        for (var faction:String in versionInfo.factionVersions) {
            report += "  " + faction + ": " + versionInfo.factionVersions[faction] + "\n";
        }
        report += "  Total Updates: " + versionInfo.totalVersion + "\n\n";
        
        // 缓存池信息
        report += "Cache Pool Stats:\n";
        report += "  Active Pools: " + poolStats.totalPools + "\n";
        report += "  Total Units Cached: " + poolStats.memoryUsage + "\n";
        for (var key:String in poolStats.poolDetails) {
            var detail:Object = poolStats.poolDetails[key];
            report += "  " + key + ": " + detail.listLength + " units (v" + detail.version + ")\n";
        }
        report += "\n";
        
        // 阈值优化器信息
        report += "Threshold Optimizer:\n";
        report += "  Current Threshold: " + Math.round(thresholdStatus.currentThreshold) + "px\n";
        report += "  Avg Density: " + Math.round(thresholdStatus.avgDensity) + "px\n";
        report += "  Optimizer Version: " + thresholdStatus.version + "\n";
        
        // FactionManager 状态
        report += "\nFactionManager Integration:\n";
        report += "  Status: Integrated\n";
        report += "  Registered Factions: " + FactionManager.getAllFactions().length + "\n";
        
        return report;
    }

    public static function performSelfCheck():Object {
        var result:Object = {
            passed: true,
            errors: [],
            warnings: [],
            performance: {}
        };
        
        // 检查FactionManager是否可用
        if (!FactionManager) {
            result.errors.push("FactionManager not available");
            result.passed = false;
        } else {
            try {
                var testFactions:Array = FactionManager.getAllFactions();
                if (!testFactions || testFactions.length == 0) {
                    result.warnings.push("No factions registered in FactionManager");
                }
            } catch (e:Error) {
                result.errors.push("FactionManager access error: " + e.message);
                result.passed = false;
            }
        }
        
        // 检查AdaptiveThresholdOptimizer是否可用
        try {
            var threshold:Number = AdaptiveThresholdOptimizer.getThreshold();
            if (isNaN(threshold) || threshold <= 0) {
                result.errors.push("Invalid threshold value: " + threshold);
                result.passed = false;
            }
        } catch (e2:Error) {
            result.errors.push("AdaptiveThresholdOptimizer not accessible: " + e2.message);
            result.passed = false;
        }
        
        // 检查缓存池完整性
        var poolStats:Object = getCachePoolStats();
        if (poolStats.totalPools > 10) {
            result.warnings.push("Large number of cache pools (" + poolStats.totalPools + "), consider cleanup");
        }
        
        // 检查版本号一致性
        var allPositive:Boolean = true;
        for (var faction:String in _factionVersions) {
            if (_factionVersions[faction] < 0) {
                result.errors.push("Negative version number for faction: " + faction);
                result.passed = false;
                allPositive = false;
            }
        }
        
        result.performance.cachePoolCount = poolStats.totalPools;
        result.performance.totalCachedUnits = poolStats.memoryUsage;
        result.performance.currentThreshold = threshold;
        result.performance.factionManagerIntegrated = true;
        
        return result;
    }
}