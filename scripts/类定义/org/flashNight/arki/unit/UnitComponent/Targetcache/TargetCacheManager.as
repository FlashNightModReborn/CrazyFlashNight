// ============================================================================
// 目标缓存管理器（增强重构版）
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 缓存管理：管理敌人/友军/全体三大类目标缓存，支持按帧自动更新
// 2. 基础查询：获取指定类型的所有单位列表（已按X轴排序）
// 3. 范围查询：从指定索引开始获取单位，支持二分查找优化
// 4. 邻近查询：O(1)查找最近/最远单位，利用有序性和nameIndex
// 5. 区域搜索：查找指定范围内的所有单位或最近/最远单位
// 
// 性能优化：
// - 利用nameIndex实现O(1)索引查找
// - 二分查找定位范围起始位置
// - 有序数组特性实现最远单位O(1)查询
// - 静态对象复用减少GC压力
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * 目标缓存集合
     * 结构: {状态键:{敌人/友军/全体:cacheEntry}}
     * 状态键包括: "undefined", "true", "false", "all"
     */
    private static var _targetCaches:Object;
    
    /**
     * 初始化标志，确保只初始化一次
     */
    private static var _initialized:Boolean = initialize();
    
    /**
     * 缓存状态键数组
     * - "true"      : 敌人状态
     * - "false"     : 友军状态
     * - "all"       : 全体状态
     * - "undefined" : 未定义状态
     */
    private static var _STATUS_KEYS:Array = ["undefined", "true", "false", "all"];

    /**
     * 缓存项模板
     * 定义了缓存项的基本结构
     */
    private static var _CACHE_TEMPLATE:Object = {
        data:        [],   // 已按 left 升序排序的单位数组
        nameIndex:   {},   // 名称到索引的映射: {_name: index}，用于O(1)时间查找单位位置
        lastUpdatedFrame: 0 // 缓存最后更新的帧数
    };
    
    /**
     * 静态复用对象，减少GC压力
     */
    private static var _emptyResult:Object = { data: [], startIndex: 0 };
    private static var _resultCache:Object = { data: null, startIndex: 0 };

    // ========================================================================
    // 初始化方法
    // ========================================================================
    
    /**
     * 初始化目标缓存管理器
     * 为每个状态键创建敌人、友军和全体的缓存结构
     * @return {Boolean} 初始化是否成功
     */
    public static function initialize():Boolean {
        _targetCaches = {};
        // 遍历所有状态键，初始化缓存结构
        for (var i:Number = 0; i < _STATUS_KEYS.length; i++) {
            var key:String = _STATUS_KEYS[i];
            _targetCaches[key] = {
                敌人 : _createCacheEntry(), // 敌人缓存
                友军 : _createCacheEntry(), // 友军缓存
                全体 : _createCacheEntry()  // 全体缓存
            };
        }
        return true;
    }

    /**
     * 创建一个新的缓存项
     * 包含独立的数据数组、名称索引和时间戳
     * @return {Object} 新的缓存项对象
     */
    private static function _createCacheEntry():Object {
        return {
            data: _CACHE_TEMPLATE.data.concat(), // 创建新数组，避免引用污染
            nameIndex: {},                       // 创建新的名称索引映射
            lastUpdatedFrame: _CACHE_TEMPLATE.lastUpdatedFrame // 初始更新时间
        };
    }

    // ========================================================================
    // 缓存更新方法
    // ========================================================================
    
    /**
     * 强制更新目标缓存
     * 不检查更新间隔，直接更新缓存数据
     * @param {Object} target - 目标单位
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {String} targetStatus - 目标状态: "true"(敌人)、"false"(友军)或"all"(全体)
     */
    public static function updateTargetCache(
        target:Object,
        requestType:String,
        targetStatus:String
    ):Void {
        var frame:Number = _root.帧计时器.当前帧数; // 获取当前帧数

        // 获取或创建缓存项
        if (!_targetCaches[targetStatus]) _targetCaches[targetStatus] = {};
        var stateCache:Object = _targetCaches[targetStatus];
        var cache:Object = stateCache[requestType];
        if (!cache) cache = stateCache[requestType] = _createCacheEntry();

        // 调用更新器进行缓存更新
        TargetCacheUpdater.updateCache(
            _root.gameworld,
            frame,
            requestType,
            targetStatus == "true", // true表示敌人，false表示友军
            cache
        );
    }

    // ========================================================================
    // 基础查询方法
    // ========================================================================
    
    /**
     * 获取缓存的目标单位列表
     * 根据更新间隔检查是否需要刷新缓存
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @return {Array} 目标单位数组(已按x轴排序)
     */
    public static function getCachedTargets(
        target:Object,
        updateInterval:Number,
        requestType:String
    ):Array {
        // 确定目标状态
        var targetStatus:String = (requestType == "全体")
            ? "all"
            : target.是否为敌人.toString();
        var currentFrame:Number = _root.帧计时器.当前帧数; // 获取当前帧数

        // 获取或创建缓存项
        if (!_targetCaches[targetStatus]) _targetCaches[targetStatus] = {};
        var stateCache:Object = _targetCaches[targetStatus];
        var cacheEntry:Object = stateCache[requestType];
        if (!cacheEntry) cacheEntry = stateCache[requestType] = _createCacheEntry();

        // 检查是否需要更新缓存
        if ((currentFrame - cacheEntry.lastUpdatedFrame) >= updateInterval) {
            updateTargetCache(target, requestType, targetStatus);
        }

        return cacheEntry.data; // 返回缓存数据
    }

    /**
     * 获取缓存的敌人单位列表
     * @param {Object} t - 目标单位
     * @param {Number} i - 更新间隔(帧数)
     * @return {Array} 敌人单位数组
     */
    public static function getCachedEnemy(t:Object, i:Number):Array { 
        return getCachedTargets(t, i, "敌人"); 
    }
    
    /**
     * 获取缓存的友军单位列表
     * @param {Object} t - 目标单位
     * @param {Number} i - 更新间隔(帧数)
     * @return {Array} 友军单位数组
     */
    public static function getCachedAlly(t:Object, i:Number):Array { 
        return getCachedTargets(t, i, "友军"); 
    }
    
    /**
     * 获取缓存的全体单位列表
     * @param {Object} t - 目标单位
     * @param {Number} i - 更新间隔(帧数)
     * @return {Array} 全体单位数组
     */
    public static function getCachedAll(t:Object, i:Number):Array { 
        return getCachedTargets(t, i, "全体"); 
    }

    // ========================================================================
    // 范围查询方法（索引定位）
    // ========================================================================
    
    // =========================================================================
    // 缓存相关的静态变量
    // =========================================================================

    /**
     * 上一次查询的左边界值
     * 用于判断本次查询是否可以利用缓存进行增量扫描
     * 初始值设为负无穷，确保第一次查询不会误判为缓存命中
     */
    private static var _lastQueryLeft:Number = -Infinity;

    /**
     * 上一次查询结果的索引位置
     * 表示上次找到的第一个满足 aabbCollider.right >= queryLeft 的元素索引
     * 配合 _lastQueryLeft 使用，作为增量扫描的起始位置
     */
    private static var _lastIndex:Number = 0;

    /**
     * 缓存有效性阈值（单位：像素）
     * 当本次查询的 queryLeft 与上次相差在此阈值内时，认为可以使用缓存
     * 该值可根据实际场景动态调整，建议范围：30-200
     * - 较小值：更精确，但缓存命中率低
     * - 较大值：缓存命中率高，但可能增加扫描距离
     */
    private static var _THRESHOLD:Number = 100;

    /**
     * 性能统计对象
     * 包含详细的查询统计信息，用于分析和优化算法性能
     * 
     * @property totalQueries      总查询次数
     * @property smallArrays       小数组优化次数（<=8个元素）
     * @property cacheHits         缓存命中次数（使用增量线性扫描）
     * @property cacheMisses       缓存未命中次数（退化到其他查找方式）
     * @property firstElementHits  首元素命中次数
     * @property lastElementHits   尾元素命中次数
     * @property binarySearches    二分查找次数
     * @property avgScanDistance   平均线性扫描距离
     * @property maxScanDistance   最大线性扫描距离
     */
    private static var _stats:Object = {
        totalQueries: 0,
        smallArrays: 0,
        cacheHits: 0,
        cacheMisses: 0,
        firstElementHits: 0,
        lastElementHits: 0,
        binarySearches: 0,
        avgScanDistance: 0,
        maxScanDistance: 0
    };

    /**
     * 从指定位置开始获取满足条件的目标列表
     * 
     * 该方法在一个按 aabbCollider.right 升序排列的数组中，查找第一个
     * 满足 aabbCollider.right >= query.left 条件的元素索引。
     * 
     * 性能优化策略：
     * 1. 小数组（<=8个元素）：直接线性扫描，避免二分查找开销
     * 2. 缓存命中：当查询位置变化很小时，从上次位置开始线性扫描
     * 3. 边界快速检查：检查首尾元素，快速处理极端情况
     * 4. 二分查找：其他情况使用标准二分查找
     * 
     * @param target         当前查询发起者（如玩家单位）
     * @param updateInterval 缓存更新间隔（帧数），控制缓存刷新频率
     * @param requestType    目标类型："敌人"、"友军"或"全体"
     * @param query          查询碰撞盒，使用其 left 属性作为查询边界
     * 
     * @return {Object} 返回结果缓存对象，包含：
     *         - data: {Array} 完整的目标列表（引用原数组，未复制）
     *         - startIndex: {Number} 第一个满足条件的元素索引
     *                      如果为 n（数组长度），表示没有满足条件的元素
     * 
     * @example
     * var result = getCachedTargetsFromIndex(player, 5, "敌人", queryBox);
     * var targets = result.data;
     * for (var i = result.startIndex; i < targets.length; i++) {
     *     processTarget(targets[i]);
     * }
     */
    public static function getCachedTargetsFromIndex(
        target:Object,
        updateInterval:Number,
        requestType:String,
        query:AABBCollider
    ):Object {
        // 获取已缓存的目标列表（已按 aabbCollider.right 升序排列）
        var list:Array = getCachedTargets(target, updateInterval, requestType);
        var n:Number = list.length;
        
        // 增加总查询计数
        // _stats.totalQueries++;
        
        // 空数组快速返回
        if (n == 0) {
            return _emptyResult;
        }
        
        // 提取查询参数
        var queryLeft:Number = query.left;
        var resultCache:Object = _resultCache;  // 使用预分配的结果对象，避免频繁创建
        
        // =====================================================================
        // 策略1：小数组优化（<=8个元素）
        // 对于小数组，线性扫描比二分查找更快，因为：
        // - 避免了二分查找的逻辑开销
        // - CPU缓存友好，连续访问效率高
        // - 减少了分支预测失败的可能
        // =====================================================================
        if (n <= 8) {
            // _stats.smallArrays++;
            var i:Number = 0;
            do {
                if (list[i].aabbCollider.right >= queryLeft) {
                    // 找到第一个满足条件的元素
                    resultCache.data = list;
                    resultCache.startIndex = i;
                    // 更新缓存，为下次查询做准备
                    _lastQueryLeft = queryLeft;
                    _lastIndex = i;
                    return resultCache;
                }
            } while (++i < n);
            
            // 所有元素都不满足条件
            resultCache.data = list;
            resultCache.startIndex = n;
            _lastQueryLeft = queryLeft;
            _lastIndex = n;
            return resultCache;
        }
        
        // =====================================================================
        // 策略2：缓存优化 - 增量线性扫描
        // 当查询位置变化很小时，从上次结果附近开始扫描
        // 这在子弹密集的游戏中特别有效，因为查询位置通常是连续变化的
        // =====================================================================
        
        // 检查缓存是否有效
        var cacheValid:Boolean = (!isNaN(_lastQueryLeft) &&  // 有上次查询记录
                                _lastIndex >= 0 &&           // 索引在有效范围内
                                _lastIndex < n);              // 索引未越界
        
        if (cacheValid) {
            // 计算查询位置的变化量
            var deltaQuery:Number = Math.abs(queryLeft - _lastQueryLeft);
            
            // 只有变化量在阈值内才使用缓存
            if (deltaQuery <= _THRESHOLD) {
                // _stats.cacheHits++;  // 记录缓存命中
                
                // 获取缓存位置的右边界值
                var cachedRight:Number = list[_lastIndex].aabbCollider.right;
                var scanDistance:Number = 0;  // 记录扫描距离，用于性能分析
                
                // -------------------------------------------------------------
                // 情况A：查询位置右移（queryLeft > 上次位置）
                // 需要向后扫描，找到新的起始位置
                // -------------------------------------------------------------
                if (cachedRight < queryLeft) {
                    var idxForward:Number = _lastIndex;
                    
                    // 向后扫描，跳过所有不满足条件的元素
                    while (idxForward < n && list[idxForward].aabbCollider.right < queryLeft) {
                        idxForward++;
                        scanDistance++;
                    }
                    
                    // 确保找到的是第一个满足条件的元素
                    // 可能存在多个元素的 right 值相同的情况
                    if (idxForward > 0 && idxForward < n) {
                        while (idxForward > 0 && list[idxForward - 1].aabbCollider.right >= queryLeft) {
                            idxForward--;
                            scanDistance++;
                        }
                    }
                    
                    // 返回结果并更新缓存
                    resultCache.data = list;
                    resultCache.startIndex = idxForward;
                    _lastQueryLeft = queryLeft;
                    _lastIndex = idxForward;
                    return resultCache;
                    
                // -------------------------------------------------------------
                // 情况B：查询位置左移或不变（queryLeft <= 上次位置）
                // 需要向前扫描，找到新的起始位置
                // -------------------------------------------------------------
                } else {
                    var idxBackward:Number = _lastIndex;
                    
                    // 向前扫描，找到第一个满足条件的元素
                    while (idxBackward > 0 && list[idxBackward - 1].aabbCollider.right >= queryLeft) {
                        idxBackward--;
                        scanDistance++;
                    }
                    
                    // 返回结果并更新缓存
                    resultCache.data = list;
                    resultCache.startIndex = idxBackward;
                    _lastQueryLeft = queryLeft;
                    _lastIndex = idxBackward;
                    return resultCache;
                }
            } else {
                // 查询位置变化过大，缓存失效
                // _stats.cacheMisses++;
            }
        } else {
            // 缓存完全无效（首次查询或数组大小变化）
            // _stats.cacheMisses++;
        }
        
        // =====================================================================
        // 策略3：边界元素快速检查
        // 在进行完整二分查找前，先检查首尾元素
        // 可以快速处理一些特殊情况，避免不必要的二分查找
        // =====================================================================
        
        // 检查第一个元素
        var firstUnit:Object = list[0];
        if (firstUnit.aabbCollider.right >= queryLeft) {
            // _stats.firstElementHits++;
            resultCache.data = list;
            resultCache.startIndex = 0;
            _lastQueryLeft = queryLeft;
            _lastIndex = 0;
            return resultCache;
        }
        
        // 检查最后一个元素
        var lastUnit:Object = list[n - 1];
        if (lastUnit.aabbCollider.right < queryLeft) {
            // _stats.lastElementHits++;
            resultCache.data = list;
            resultCache.startIndex = n;  // 所有元素都不满足
            _lastQueryLeft = queryLeft;
            _lastIndex = n;
            return resultCache;
        }
        
        // =====================================================================
        // 策略4：标准二分查找
        // 当缓存失效且不是边界情况时，使用二分查找
        // 在 [1, n-1] 区间内查找（因为已经检查过首尾元素）
        // =====================================================================
        // _stats.binarySearches++;
        var l:Number = 1;
        var r:Number = n - 1;
        
        do {
            var m:Number = (l + r) >> 1;  // 位运算实现除2，更快
            var unitRight:Number = list[m].aabbCollider.right;
            
            if (unitRight >= queryLeft) {
                // 检查是否是第一个满足条件的元素
                if (list[m - 1].aabbCollider.right < queryLeft) {
                    // 找到目标！
                    resultCache.data = list;
                    resultCache.startIndex = m;
                    _lastQueryLeft = queryLeft;
                    _lastIndex = m;
                    return resultCache;
                }
                // 继续在左半部分查找
                r = m - 1;
            } else {
                // 在右半部分查找
                l = m + 1;
            }
        } while (l <= r);
        
        // 理论上不会执行到这里，但为了代码健壮性仍然处理
        resultCache.data = list;
        resultCache.startIndex = l;
        _lastQueryLeft = queryLeft;
        _lastIndex = l;
        return resultCache;
    }

    /**
     * 更新线性扫描距离的统计信息
     * 
     * 用于分析缓存命中时的扫描效率，帮助调整阈值参数
     * 
     * @param distance 本次线性扫描的距离（扫描的元素个数）
     * @private
     */
    private static function _updateScanStats(distance:Number):Void {
        // 更新最大扫描距离
        if (distance > _stats.maxScanDistance) {
            _stats.maxScanDistance = distance;
        }
        
        // 计算平均扫描距离（增量平均）
        var totalScans:Number = _stats.cacheHits;
        _stats.avgScanDistance = (_stats.avgScanDistance * (totalScans - 1) + distance) / totalScans;
    }

    /**
     * 更新性能统计的调试输出
     * 
     * 将关键性能指标输出到游戏界面，便于实时监控和优化
     * 输出内容包括：缓存命中率、二分查找率、平均/最大扫描距离
     * 
     * @private
     */
    private static function _updateDebugOutput():Void {
        // 计算有效查询次数（排除小数组）
        var effectiveQueries:Number = _stats.totalQueries - _stats.smallArrays;
        if (effectiveQueries <= 0) return;
        
        // 计算各项指标的百分比
        var cacheHitRate:Number = (_stats.cacheHits / effectiveQueries) * 100;
        var binarySearchRate:Number = (_stats.binarySearches / effectiveQueries) * 100;
        
        // 构建并输出统计信息
        _root.发布消息(
            "缓存命中率: " + cacheHitRate + "% | " +
            "二分查找率: " + binarySearchRate + "% | " +
            "平均扫描距离: " + _stats.avgScanDistance + " | " +
            "最大扫描距离: " + _stats.maxScanDistance
        );
    }

    /**
     * 重置所有性能统计数据
     * 
     * 在场景切换、关卡重新开始或需要重新评估性能时调用
     * 清空所有统计计数器，开始新的统计周期
     * 
     * @example
     * // 在新关卡开始时重置统计
     * TargetQueryCache.resetStats();
     */
    public static function resetStats():Void {
        _stats.totalQueries = 0;
        _stats.smallArrays = 0;
        _stats.cacheHits = 0;
        _stats.cacheMisses = 0;
        _stats.firstElementHits = 0;
        _stats.lastElementHits = 0;
        _stats.binarySearches = 0;
        _stats.avgScanDistance = 0;
        _stats.maxScanDistance = 0;
    }

    /**
     * 获取从指定索引开始的敌人单位
     * @param {Object} t - 目标单位
     * @param {Number} i - 更新间隔(帧数)
     * @param {AABBCollider} aabb - 查询用的AABB碰撞器
     * @return {Object} 包含data数组、startIndex的结果对象
     */
    public static function getCachedEnemyFromIndex(t:Object, i:Number, aabb:AABBCollider):Object {
        return getCachedTargetsFromIndex(t, i, "敌人", aabb);
    }

    /**
     * 获取从指定索引开始的友军单位
     * @param {Object} t - 目标单位
     * @param {Number} i - 更新间隔(帧数)
     * @param {AABBCollider} aabb - 查询用的AABB碰撞器
     * @return {Object} 包含data数组、startIndex的结果对象
     */
    public static function getCachedAllyFromIndex(t:Object, i:Number, aabb:AABBCollider):Object {
        return getCachedTargetsFromIndex(t, i, "友军", aabb);
    }

    /**
     * 获取从指定索引开始的全体单位
     * @param {Object} t - 目标单位
     * @param {Number} i - 更新间隔(帧数)
     * @param {AABBCollider} aabb - 查询用的AABB碰撞器
     * @return {Object} 包含data数组、startIndex的结果对象
     */
    public static function getCachedAllFromIndex(t:Object, i:Number, aabb:AABBCollider):Object {
        return getCachedTargetsFromIndex(t, i, "全体", aabb);
    }

    // ========================================================================
    // 最近单位查询
    // ========================================================================
    
    /**
     * 按X轴快速查找与目标单位最近的单位
     * 利用nameIndex实现O(1)邻居查找，或在目标不在列表时进行全表扫描
     * @param {Object} target - 当前单位
     * @param {Number} updateInterval - 缓存失效帧间隔
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @return {Object} 最近单位对象，若不存在返回null
     */
    public static function findNearestTarget(
        target:Object,
        updateInterval:Number,
        requestType:String
    ):Object {
        // 确定目标状态
        var targetStatus:String = (requestType == "全体")
            ? "all"
            : target.是否为敌人.toString();

        // 获取缓存项并确保最新
        if (!_targetCaches[targetStatus]) _targetCaches[targetStatus] = {};
        var stateCache:Object = _targetCaches[targetStatus];
        var cacheEntry:Object = stateCache[requestType];
        if (!cacheEntry) cacheEntry = stateCache[requestType] = _createCacheEntry();

        // 检查是否需要更新缓存
        var currentFrame:Number = _root.帧计时器.当前帧数;
        if ((currentFrame - cacheEntry.lastUpdatedFrame) >= updateInterval) {
            updateTargetCache(target, requestType, targetStatus);
        }

        // --- 快速定位自身索引 ---
        var idx:Number = cacheEntry.nameIndex[target._name];
        if (idx == undefined) {
            // 如果自身不在列表中，则进行全表扫描查找最近单位
            var list:Array = cacheEntry.data;
            var minDist:Number = Number.MAX_VALUE;
            var nearest:Object = null;
            var lx:Number = target.aabbCollider.left; // 目标X坐标
            
            // 遍历所有单位，找到最近的
            for (var i:Number = 0; i < list.length; i++) {
                if (list[i] == target) continue; // 跳过自身
                var d:Number = Math.abs(list[i].aabbCollider.left - lx); // 计算X轴距离
                if (d < minDist) { 
                    minDist = d; // 更新最小距离
                    nearest = list[i]; // 更新最近单位
                }
            }
            return nearest;
        }

        // --- 当目标在列表中时，只需检查左右相邻两个元素 ---
        // 获取左侧单位（如果存在）
        var leftObj:Object = (idx > 0) ? cacheEntry.data[idx - 1] : null;
        // 获取右侧单位（如果存在）
        var rightObj:Object = (idx < cacheEntry.data.length - 1) ? cacheEntry.data[idx + 1] : null;

        // 计算左右单位与目标的距离
        var lx:Number = target.aabbCollider.left; // 目标X坐标
        var dl:Number = (leftObj) ? Math.abs(leftObj.aabbCollider.left - lx) : Number.MAX_VALUE;
        var dr:Number = (rightObj) ? Math.abs(rightObj.aabbCollider.left - lx) : Number.MAX_VALUE;

        // 如果左右都没有单位，返回null
        if (dl == Number.MAX_VALUE && dr == Number.MAX_VALUE) return null;
        
        // 返回距离较近的单位
        return (dl <= dr) ? leftObj : rightObj;
    }

    /**
     * 查找X轴上最近的敌人单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最近的敌人单位，若不存在返回null
     */
    public static function findNearestEnemy(t:Object, interval:Number):Object { 
        return findNearestTarget(t, interval, "敌人"); 
    }

    /**
     * 查找X轴上最近的友军单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最近的友军单位，若不存在返回null
     */
    public static function findNearestAlly(t:Object, interval:Number):Object { 
        return findNearestTarget(t, interval, "友军"); 
    }

    /**
     * 查找X轴上最近的全体单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最近的全体单位，若不存在返回null
     */
    public static function findNearestAll(t:Object, interval:Number):Object { 
        return findNearestTarget(t, interval, "全体"); 
    }

    // ========================================================================
    // 最远单位查询
    // ========================================================================

    /**
     * 按X轴快速查找与目标单位最远的单位
     * 利用排序数组特性：最远单位必定是首元素或尾元素，实现O(1)查询
     * @param {Object} target - 当前单位
     * @param {Number} updateInterval - 缓存失效帧间隔
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @return {Object} 最远单位对象，若不存在返回null
     */
    public static function findFarthestTarget(
        target:Object,
        updateInterval:Number,
        requestType:String
    ):Object {
        // 确定目标状态
        var targetStatus:String = (requestType == "全体")
            ? "all"
            : target.是否为敌人.toString();

        // 获取缓存项并确保最新
        if (!_targetCaches[targetStatus]) _targetCaches[targetStatus] = {};
        var stateCache:Object = _targetCaches[targetStatus];
        var cacheEntry:Object = stateCache[requestType];
        if (!cacheEntry) cacheEntry = stateCache[requestType] = _createCacheEntry();

        // 检查是否需要更新缓存
        var currentFrame:Number = _root.帧计时器.当前帧数;
        if ((currentFrame - cacheEntry.lastUpdatedFrame) >= updateInterval) {
            updateTargetCache(target, requestType, targetStatus);
        }

        var list:Array = cacheEntry.data;
        if (list.length <= 1) {
            return list[0] || null;
        }
         // 列表为空或只有一个单位

        // --- 快速定位自身索引 ---
        var idx:Number = cacheEntry.nameIndex[target._name];
        var lx:Number = target.aabbCollider.left; // 目标X坐标
        
        if (idx == undefined) {
            // 如果自身不在列表中，则进行全表扫描查找最远单位
            var maxDist:Number = -1;
            var farthest:Object = null;
            
            for (var i:Number = 0; i < list.length; i++) {
                if (list[i] == target) continue; // 跳过自身
                var d:Number = Math.abs(list[i].aabbCollider.left - lx);
                if (d > maxDist) { 
                    maxDist = d;
                    farthest = list[i];
                }
            }
            return farthest;
        }

        // --- O(1)核心算法：最远单位必定是首元素或尾元素 ---
        var firstObj:Object = list[0];
        var lastObj:Object = list[list.length - 1];
        
        // 特殊情况：如果自己就是首元素，最远的是尾元素
        if (idx == 0) return (list.length > 1) ? lastObj : null;
        
        // 特殊情况：如果自己就是尾元素，最远的是首元素  
        if (idx == list.length - 1) return firstObj;
        
        // 一般情况：自己在中间，比较到首尾的距离
        var d1:Number = Math.abs(firstObj.aabbCollider.left - lx);
        var d2:Number = Math.abs(lastObj.aabbCollider.left - lx);
        
        return (d1 >= d2) ? firstObj : lastObj;
    }

    /**
     * 查找X轴上最远的敌人单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最远的敌人单位，若不存在返回null
     */
    public static function findFarthestEnemy(t:Object, interval:Number):Object { 
        return findFarthestTarget(t, interval, "敌人"); 
    }

    /**
     * 查找X轴上最远的友军单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最远的友军单位，若不存在返回null
     */
    public static function findFarthestAlly(t:Object, interval:Number):Object { 
        return findFarthestTarget(t, interval, "友军"); 
    }

    /**
     * 查找X轴上最远的全体单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最远的全体单位，若不存在返回null
     */
    public static function findFarthestAll(t:Object, interval:Number):Object { 
        return findFarthestTarget(t, interval, "全体"); 
    }

    // ========================================================================
    // 区域搜索方法（新增）
    // ========================================================================

    /**
     * 查找指定X轴范围内的所有单位
     * 利用有序数组特性，使用二分查找定位起始和结束位置
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {Number} leftRange - 左侧搜索范围（相对于目标的距离）
     * @param {Number} rightRange - 右侧搜索范围（相对于目标的距离）
     * @return {Array} 范围内的单位数组
     */
    public static function findTargetsInRange(
        target:Object,
        updateInterval:Number,
        requestType:String,
        leftRange:Number,
        rightRange:Number
    ):Array {
        var list:Array = getCachedTargets(target, updateInterval, requestType);
        var len:Number = list.length;
        if (len == 0) return [];

        var targetX:Number = target.aabbCollider.left;
        var leftBound:Number = targetX - leftRange;
        var rightBound:Number = targetX + rightRange;

        // === 左边界二分查找 (>= leftBound) ===
        var startIdx:Number;
        if (list[0].aabbCollider.left >= leftBound) {
            startIdx = 0;
        } else if (list[len - 1].aabbCollider.left < leftBound) {
            return [];
        } else {
            var l:Number = 0;
            var r:Number = len - 1;
            while (l < r) {
                var m:Number = (l + r) >> 1;
                var v:Number = list[m].aabbCollider.left;
                if (v < leftBound) l = m + 1;
                else r = m;
            }
            startIdx = l;
        }

        // === 右边界二分查找 (> rightBound) ===
        var endIdx:Number;
        if (list[len - 1].aabbCollider.left <= rightBound) {
            endIdx = len;
        } else {
            var l2:Number = startIdx; // 优化：从 startIdx 开始
            var r2:Number = len - 1;
            while (l2 < r2) {
                var m2:Number = (l2 + r2) >> 1;
                var v2:Number = list[m2].aabbCollider.left;
                if (v2 <= rightBound) l2 = m2 + 1;
                else r2 = m2;
            }
            endIdx = l2;
        }

        // === 构建结果数组 ===
        var result:Array = [];
        for (var i:Number = startIdx; i < endIdx; i++) {
            var unit:Object = list[i];
            if (unit != target) result.push(unit);
        }

        return result;
    }

    /**
     * 查找指定半径范围内的所有单位
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {Number} radius - 搜索半径
     * @return {Array} 范围内的单位数组
     */
    public static function findTargetsInRadius(
        target:Object,
        updateInterval:Number,
        requestType:String,
        radius:Number
    ):Array {
        return findTargetsInRange(target, updateInterval, requestType, radius, radius);
    }

    /**
     * 查找指定X轴范围内的敌人单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} leftRange - 左侧搜索范围
     * @param {Number} rightRange - 右侧搜索范围
     * @return {Array} 范围内的敌人数组
     */
    public static function findEnemiesInRange(
        t:Object, interval:Number, leftRange:Number, rightRange:Number
    ):Array {
        return findTargetsInRange(t, interval, "敌人", leftRange, rightRange);
    }

    /**
     * 查找指定X轴范围内的友军单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} leftRange - 左侧搜索范围
     * @param {Number} rightRange - 右侧搜索范围
     * @return {Array} 范围内的友军数组
     */
    public static function findAlliesInRange(
        t:Object, interval:Number, leftRange:Number, rightRange:Number
    ):Array {
        return findTargetsInRange(t, interval, "友军", leftRange, rightRange);
    }

    /**
     * 查找指定X轴范围内的全体单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} leftRange - 左侧搜索范围
     * @param {Number} rightRange - 右侧搜索范围
     * @return {Array} 范围内的全体单位数组
     */
    public static function findAllInRange(
        t:Object, interval:Number, leftRange:Number, rightRange:Number
    ):Array {
        return findTargetsInRange(t, interval, "全体", leftRange, rightRange);
    }

    /**
     * 查找指定半径内的敌人单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} radius - 搜索半径
     * @return {Array} 半径内的敌人数组
     */
    public static function findEnemiesInRadius(t:Object, interval:Number, radius:Number):Array {
        return findTargetsInRadius(t, interval, "敌人", radius);
    }

    /**
     * 查找指定半径内的友军单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} radius - 搜索半径
     * @return {Array} 半径内的友军数组
     */
    public static function findAlliesInRadius(t:Object, interval:Number, radius:Number):Array {
        return findTargetsInRadius(t, interval, "友军", radius);
    }

    /**
     * 查找指定半径内的全体单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} radius - 搜索半径
     * @return {Array} 半径内的全体单位数组
     */
    public static function findAllInRadius(t:Object, interval:Number, radius:Number):Array {
        return findTargetsInRadius(t, interval, "全体", radius);
    }

    // ========================================================================
    // 范围限制查询方法
    // ========================================================================

    /**
     * 查找指定范围内的最近单位
     * 结合范围查询和最近单位查找，适用于有距离限制的场景
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔
     * @param {String} requestType - 请求类型
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最近的单位，超出范围返回null
     */
    public static function findNearestTargetInRange(
        target:Object,
        updateInterval:Number,
        requestType:String,
        maxDistance:Number
    ):Object {
        var nearest:Object = findNearestTarget(target, updateInterval, requestType);
        if (!nearest) return null;
        
        var distance:Number = Math.abs(nearest.aabbCollider.left - target.aabbCollider.left);
        return (distance <= maxDistance) ? nearest : null;
    }

    /**
     * 查找指定范围内的最近敌人
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最近的敌人，超出范围返回null
     */
    public static function findNearestEnemyInRange(
        t:Object, interval:Number, maxDistance:Number
    ):Object {
        return findNearestTargetInRange(t, interval, "敌人", maxDistance);
    }

    /**
     * 查找指定范围内的最近友军
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最近的友军，超出范围返回null
     */
    public static function findNearestAllyInRange(
        t:Object, interval:Number, maxDistance:Number
    ):Object {
        return findNearestTargetInRange(t, interval, "友军", maxDistance);
    }

    /**
     * 查找指定范围内的最近全体单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最近的全体单位，超出范围返回null
     */
    public static function findNearestAllInRange(
        t:Object, interval:Number, maxDistance:Number
    ):Object {
        return findNearestTargetInRange(t, interval, "全体", maxDistance);
    }

    /**
     * 查找指定范围内的最远单位
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔
     * @param {String} requestType - 请求类型
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最远的单位，超出范围返回null
     */
    public static function findFarthestTargetInRange(
        target:Object,
        updateInterval:Number,
        requestType:String,
        maxDistance:Number
    ):Object {
        var farthest:Object = findFarthestTarget(target, updateInterval, requestType);
        if (!farthest) return null;
        
        var distance:Number = Math.abs(farthest.aabbCollider.left - target.aabbCollider.left);
        return (distance <= maxDistance) ? farthest : null;
    }

    /**
     * 查找指定范围内的最远敌人
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最远的敌人，超出范围返回null
     */
    public static function findFarthestEnemyInRange(
        t:Object, interval:Number, maxDistance:Number
    ):Object {
        return findFarthestTargetInRange(t, interval, "敌人", maxDistance);
    }

    /**
     * 查找指定范围内的最远友军
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最远的友军，超出范围返回null
     */
    public static function findFarthestAllyInRange(
        t:Object, interval:Number, maxDistance:Number
    ):Object {
        return findFarthestTargetInRange(t, interval, "友军", maxDistance);
    }

    /**
     * 查找指定范围内的最远全体单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最远的全体单位，超出范围返回null
     */
    public static function findFarthestAllInRange(
        t:Object, interval:Number, maxDistance:Number
    ):Object {
        return findFarthestTargetInRange(t, interval, "全体", maxDistance);
    }

    // ========================================================================
    // 其他方法
    // ========================================================================

    /**
     * 查找主角
     * @return {MovieClip} 主角的引用，若不存在返回null
     */
    public static function findHero():MovieClip { 
        return _root.gameworld[_root.控制目标] || null; 
    }
}