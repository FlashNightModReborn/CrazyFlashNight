// ============================================================================
// 目标缓存更新器（重构版 - 集成AdaptiveThresholdOptimizer）
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 收集、排序并写入 cacheEntry
// 2. 自动生成 nameIndex，支持 O(1) 索引定位
// 3. 新增 rightValues/leftValues 数组，优化坐标值访问性能
// 4. 维持 enemy / ally / all 三大版本号 + 复合键缓存
// 5. 【重构改进】使用 AdaptiveThresholdOptimizer 处理阈值逻辑
// 
// 重构改进：
// - 将自适应阈值逻辑委托给 AdaptiveThresholdOptimizer
// - 简化了类的职责，专注于缓存数据的构建
// - 保持了所有原有的性能优化
// - 为下一步向SortedUnitCache迁移做准备
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizer;
import org.flashNight.naki.Sort.TimSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * 缓存池对象
     * 存储不同类型的临时目标列表和版本号
     * 结构: {cacheKey: {tempList: Array, tempVersion: Number}}
     * - cacheKey: 缓存键，格式为 "敌人_true"、"友军_false" 或 "全体"
     * - tempList: 临时单位列表，用于减少重复收集
     * - tempVersion: 版本号，用于判断是否需要重新收集
     */
    private static var _cachePool:Object = {};
    
    /**
     * 敌人阵营版本号
     * 当敌人单位发生增删时递增，用于缓存失效判断
     */
    private static var _enemyVersion:Number = 0;
    
    /**
     * 友军阵营版本号
     * 当友军单位发生增删时递增，用于缓存失效判断
     */
    private static var _allyVersion:Number = 0;

    /**
     * 缓存有效性阈值访问器
     * 现在委托给 AdaptiveThresholdOptimizer 管理
     * 保持向后兼容性
     */
    public static function get _THRESHOLD():Number {
        return AdaptiveThresholdOptimizer.getThreshold();
    }

    /**
     * 请求类型常量定义
     * 使用常量避免字符串硬编码，提高代码可维护性
     */
    private static var _ENEMY_TYPE:String = "敌人"; // 敌人类型标识
    private static var _ALLY_TYPE:String  = "友军"; // 友军类型标识
    private static var _ALL_TYPE:String   = "全体"; // 全体类型标识

    // ========================================================================
    // 核心更新方法（重构版 - 使用AdaptiveThresholdOptimizer）
    // ========================================================================
    
    /**
     * 更新缓存的核心方法（重构版）
     * 根据请求类型和目标阵营收集、排序单位，并更新缓存项
     * 【重构改进】：使用 AdaptiveThresholdOptimizer 处理阈值逻辑
     * 
     * 处理流程：
     * 1. 确定需要收集的阵营类型
     * 2. 生成缓存键并获取或创建缓存数据
     * 3. 检查版本号决定是否需要重新收集
     * 4. 对收集的单位进行插入排序
     * 5. 【重构】委托给 AdaptiveThresholdOptimizer 分析并更新阈值
     * 6. 构建最终缓存数据（包含 nameIndex 和 rightValues）
     * 
     * @param {Object} gameWorld - 游戏世界对象，包含所有单位
     * @param {Number} currentFrame - 当前帧数，用于更新时间戳
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {Boolean} targetIsEnemy - 目标（请求者）是否为敌人
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

        // _root.发布消息(TargetCacheUpdater.getDetailedStatusReport());

        // (1) 判定需收集的阵营
        var effectiveFaction:Boolean;
        if (!isAllRequest) {
            // 敌人请求: 收集与请求者相反阵营的单位
            // 友军请求: 收集与请求者相同阵营的单位
            effectiveFaction = isEnemyRequest ? !targetIsEnemy : targetIsEnemy;
        }

        // (2) 生成复合键以对应临时列表
        var cacheKey:String = isAllRequest
            ? _ALL_TYPE
            : requestType + "_" + effectiveFaction.toString();

        // 获取或创建缓存类型数据
        if (!_cachePool[cacheKey]) {
            // 把新创建缓存的初始 tempVersion 设置为小于任何可能的版本号（比如 -1），保证第一次总能进入收集。
            _cachePool[cacheKey] = { tempList: [], tempVersion: -1 };
        }
        var cacheTypeData:Object = _cachePool[cacheKey];

        // (3) 版本号判定
        var currentVersion:Number = isAllRequest
            ? _enemyVersion + _allyVersion
            : (effectiveFaction ? _enemyVersion : _allyVersion);

        // 检查是否需要更新临时列表
        if (cacheTypeData.tempVersion < currentVersion) {
            // 重新收集有效单位
            cacheTypeData.tempList.length = 0;

            // 根据请求类型收集单位
            if (isAllRequest) {
                _collectAllValidUnits(gameWorld, cacheTypeData.tempList);
            } else {
                _collectValidUnits(
                    gameWorld,
                    targetIsEnemy,
                    isEnemyRequest,
                    cacheTypeData.tempList
                );
            }
            // 更新临时列表版本号
            cacheTypeData.tempVersion = currentVersion;
        }

        // (4) 插入排序（按 left 升序）
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

        // ========================================================================
        // ===== 核心优化：单循环完成所有数据提取 =====
        // ========================================================================
        var leftValues:Array = [];      // left 坐标值数组
        var rightValues:Array = [];     // right 坐标值数组  
        var newNameIndex:Object = {};   // 名称到索引的映射
        
        // 单次遍历，一次性完成所有数据提取
        // 性能优势：最大化数据局部性，最小化循环开销
        for (var k:Number = 0; k < len; k++) {
            var unit:Object = list[k];
            var collider:Object = unit.aabbCollider;
            
            // 一次访问单位对象，完成所有数据提取
            leftValues[k] = collider.left;          // 用于自适应阈值分析
            rightValues[k] = collider.right;        // 用于查询性能优化
            newNameIndex[unit._name] = k;           // 用于O(1)名称索引
        }

        // ========================================================================
        // ===== 【重构改进】使用 AdaptiveThresholdOptimizer 更新阈值 =====
        // ========================================================================
        AdaptiveThresholdOptimizer.updateThreshold(leftValues);

        // (6) 直接更新缓存项
        // 所有数据已在上面的单循环中准备完毕
        cacheEntry.data              = list;           // 单位数组引用
        cacheEntry.nameIndex         = newNameIndex;   // 名称索引映射
        cacheEntry.rightValues       = rightValues;    // right 值数组
        cacheEntry.leftValues        = leftValues;     // left 值数组
        cacheEntry.lastUpdatedFrame  = currentFrame;   // 更新时间戳
    }

    // ========================================================================
    // 【重构改进】AdaptiveThresholdOptimizer 委托方法
    // ========================================================================
    
    /**
     * 手动调整自适应参数
     * 现在委托给 AdaptiveThresholdOptimizer
     * 保持向后兼容性
     * 
     * @param {Number} alpha - EMA平滑系数 (0.1-0.5)
     * @param {Number} densityFactor - 密度倍数因子 (1.0-5.0)
     * @param {Number} minThreshold - 最小阈值限制
     * @param {Number} maxThreshold - 最大阈值限制
     */
    public static function setAdaptiveParams(
        alpha:Number,
        densityFactor:Number,
        minThreshold:Number,
        maxThreshold:Number
    ):Void {
        AdaptiveThresholdOptimizer.setParams(alpha, densityFactor, minThreshold, maxThreshold);
    }

    /**
     * 应用阈值优化预设
     * 新增方法，利用 AdaptiveThresholdOptimizer 的预设功能
     * 
     * @param {String} presetName - 预设名称 ("dense", "sparse", "dynamic", "stable", "default")
     * @return {Boolean} 应用是否成功
     */
    public static function applyThresholdPreset(presetName:String):Boolean {
        return AdaptiveThresholdOptimizer.applyPreset(presetName);
    }

    /**
     * 获取当前阈值
     * 委托给 AdaptiveThresholdOptimizer
     * 
     * @return {Number} 当前阈值
     */
    public static function getCurrentThreshold():Number {
        return AdaptiveThresholdOptimizer.getThreshold();
    }

    /**
     * 获取阈值优化器状态
     * 新增方法，用于调试和监控
     * 
     * @return {Object} 优化器状态信息
     */
    public static function getThresholdStatus():Object {
        return AdaptiveThresholdOptimizer.getStatus();
    }

    // ========================================================================
    // 全局版本控制
    // ========================================================================
    
    /**
     * 添加单位时更新版本号
     * 根据单位阵营递增对应的版本号，触发相关缓存失效
     * 
     * @param {Object} unit - 新增的单位对象
     */
    public static function addUnit(unit:Object):Void {
        if (unit.是否为敌人) {
            _enemyVersion++;  // 敌人阵营版本号递增
        } else {
            _allyVersion++;   // 友军阵营版本号递增
        }
    }
    
    /**
     * 移除单位时更新版本号
     * 根据单位阵营递增对应的版本号，触发相关缓存失效
     * 
     * @param {Object} unit - 被移除的单位对象
     */
    public static function removeUnit(unit:Object):Void {
        if (unit.是否为敌人) {
            _enemyVersion++;  // 敌人阵营版本号递增
        } else {
            _allyVersion++;   // 友军阵营版本号递增
        }
    }

    /**
     * 批量添加单位
     * 新增方法，优化批量操作的性能
     * 
     * @param {Array} units - 要添加的单位数组
     */
    public static function addUnits(units:Array):Void {
        var enemyCount:Number = 0;
        var allyCount:Number = 0;
        
        for (var i:Number = 0; i < units.length; i++) {
            if (units[i].是否为敌人) {
                enemyCount++;
            } else {
                allyCount++;
            }
        }
        
        if (enemyCount > 0) _enemyVersion += enemyCount;
        if (allyCount > 0) _allyVersion += allyCount;
    }

    /**
     * 批量移除单位
     * 新增方法，优化批量操作的性能
     * 
     * @param {Array} units - 要移除的单位数组
     */
    public static function removeUnits(units:Array):Void {
        var enemyCount:Number = 0;
        var allyCount:Number = 0;
        
        for (var i:Number = 0; i < units.length; i++) {
            if (units[i].是否为敌人) {
                enemyCount++;
            } else {
                allyCount++;
            }
        }
        
        if (enemyCount > 0) _enemyVersion += enemyCount;
        if (allyCount > 0) _allyVersion += allyCount;
    }

    /**
     * 获取版本号信息
     * 新增方法，用于调试和监控
     * 
     * @return {Object} 包含所有版本号的对象
     */
    public static function getVersionInfo():Object {
        return {
            enemyVersion: _enemyVersion,
            allyVersion: _allyVersion,
            totalVersion: _enemyVersion + _allyVersion
        };
    }

    /**
     * 重置所有版本号
     * 新增方法，用于调试或重新初始化
     */
    public static function resetVersions():Void {
        _enemyVersion = 0;
        _allyVersion = 0;
        // 清空缓存池
        for (var key:String in _cachePool) {
            delete _cachePool[key];
        }
        _cachePool = {};
    }


    // ========================================================================
    // 内部收集方法
    // ========================================================================
    
    /**
     * 收集有效单位（敌人或友军）
     * 根据请求类型和请求者阵营筛选符合条件的单位
     * 
     * 筛选逻辑：
     * - 敌人请求：收集与请求者阵营相反的单位
     * - 友军请求：收集与请求者阵营相同的单位
     * 
     * @param {Object} gameWorld - 游戏世界对象，包含所有单位
     * @param {Boolean} requesterIsEnemy - 请求者是否为敌人
     * @param {Boolean} isEnemyRequest - 是否请求敌人数据
     * @param {Array} targetList - 存储符合条件的单位（输出参数）
     */
    private static function _collectValidUnits(
        gameWorld:Object,
        requesterIsEnemy:Boolean,
        isEnemyRequest:Boolean,
        targetList:Array
    ):Void {
        var key:String, u:Object, uIsEnemy:Boolean;
        
        if (isEnemyRequest) {
            // 敌人请求：收集与请求者阵营相反的单位
            for (key in gameWorld) {
                u = gameWorld[key];
                if (u.hp <= 0) continue; // 跳过已死亡单位
                
                uIsEnemy = u.是否为敌人;
                // 检查是否为相反阵营
                if (requesterIsEnemy != uIsEnemy) {
                    // 更新碰撞器并添加到目标列表
                    // 使用链式赋值优化代码
                    u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
                }
            }
        } else {
            // 友军请求：收集与请求者阵营相同的单位
            for (key in gameWorld) {
                u = gameWorld[key];
                if (u.hp <= 0) continue; // 跳过已死亡单位
                
                uIsEnemy = u.是否为敌人;
                // 检查是否为相同阵营
                if (requesterIsEnemy == uIsEnemy) {
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
     */
    private static function _collectAllValidUnits(
        gameWorld:Object,
        targetList:Array
    ):Void {
        var key:String, u:Object;
        
        // 遍历游戏世界中的所有单位
        for (key in gameWorld) {
            u = gameWorld[key];
            if (u.hp <= 0) continue; // 跳过已死亡单位
            
            // 更新碰撞器并添加到目标列表
            u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
        }
    }

    // ========================================================================
    // 【重构辅助】缓存池管理方法
    // ========================================================================
    
    /**
     * 获取缓存池统计信息
     * 新增方法，用于性能分析和调试
     * 
     * @return {Object} 缓存池统计信息
     */
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

    /**
     * 清理指定类型的缓存池
     * 新增方法，用于内存管理
     * 
     * @param {String} requestType - 要清理的请求类型（可选，不传则清理所有）
     */
    public static function clearCachePool(requestType:String):Void {
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

    // ========================================================================
    // 调试和监控方法
    // ========================================================================
    
    /**
     * 生成详细的状态报告
     * 新增方法，整合所有组件的状态信息
     * 
     * @return {String} 格式化的状态报告
     */
    public static function getDetailedStatusReport():String {
        var versionInfo:Object = getVersionInfo();
        var poolStats:Object = getCachePoolStats();
        var thresholdStatus:Object = getThresholdStatus();
        
        var report:String = "=== TargetCacheUpdater Status Report ===\n\n";
        
        // 版本信息
        report += "Version Numbers:\n";
        report += "  Enemy Version: " + versionInfo.enemyVersion + "\n";
        report += "  Ally Version: " + versionInfo.allyVersion + "\n";
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
        
        return report;
    }

    /**
     * 执行自检和性能测试
     * 新增方法，用于验证系统健康状态
     * 
     * @return {Object} 自检结果
     */
    public static function performSelfCheck():Object {
        var result:Object = {
            passed: true,
            errors: [],
            warnings: [],
            performance: {}
        };
        
        // 检查AdaptiveThresholdOptimizer是否可用
        try {
            var threshold:Number = AdaptiveThresholdOptimizer.getThreshold();
            if (isNaN(threshold) || threshold <= 0) {
                result.errors.push("Invalid threshold value: " + threshold);
                result.passed = false;
            }
        } catch (e:Error) {
            result.errors.push("AdaptiveThresholdOptimizer not accessible: " + e.message);
            result.passed = false;
        }
        
        // 检查缓存池完整性
        var poolStats:Object = getCachePoolStats();
        if (poolStats.totalPools > 10) {
            result.warnings.push("Large number of cache pools (" + poolStats.totalPools + "), consider cleanup");
        }
        
        // 检查版本号一致性
        var versionInfo:Object = getVersionInfo();
        if (versionInfo.enemyVersion < 0 || versionInfo.allyVersion < 0) {
            result.errors.push("Negative version numbers detected");
            result.passed = false;
        }
        
        result.performance.cachePoolCount = poolStats.totalPools;
        result.performance.totalCachedUnits = poolStats.memoryUsage;
        result.performance.currentThreshold = threshold;
        
        return result;
    }
}