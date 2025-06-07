// ============================================================================
// 目标缓存管理器（深度优化版 - 应用常数优化和数据局部性优化）
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 缓存管理：管理敌人/友军/全体三大类目标缓存，支持按帧自动更新
// 2. 基础查询：获取指定类型的所有单位列表（已按X轴排序）
// 3. 范围查询：从指定索引开始获取单位，支持二分查找优化
// 4. 邻近查询：O(1)查找最近/最远单位，利用有序性和nameIndex
// 5. 区域搜索：查找指定范围内的所有单位或最近/最远单位
// 
// 【新增优化策略】：
// - 借鉴TargetCacheUpdater的数据局部性思想，减少重复属性访问
// - 使用直接索引赋值替代Array.push()，减少函数调用开销
// - 在距离计算前缓存坐标值，避免重复的属性链查找
// - 优化循环结构，最大化代码执行效率
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
     * 
     * @property data              已按 left 升序排序的单位数组
     * @property nameIndex         名称到索引的映射: {_name: index}，用于O(1)时间查找单位位置
     * @property rightValues       预缓存的 aabbCollider.right 值数组（性能优化）
     * @property leftValues        预缓存的 aabbCollider.left 值数组（性能优化）
     * @property lastUpdatedFrame  缓存最后更新的帧数
     */
    private static var _CACHE_TEMPLATE:Object = {
        data:        [],   // 已按 left 升序排序的单位数组
        nameIndex:   {},   // 名称到索引的映射
        rightValues: [],   // right 坐标值数组（新增）
        leftValues:  [],   // left 坐标值数组（新增）
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
     * 包含独立的数据数组、名称索引、坐标值数组和时间戳
     * @return {Object} 新的缓存项对象
     */
    private static function _createCacheEntry():Object {
        return {
            data: _CACHE_TEMPLATE.data.concat(),         // 创建新数组，避免引用污染
            nameIndex: {},                               // 创建新的名称索引映射
            rightValues: _CACHE_TEMPLATE.rightValues.concat(), // 创建新的right值数组
            leftValues: _CACHE_TEMPLATE.leftValues.concat(),   // 创建新的left值数组
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
    // 范围查询方法（索引定位）- 核心优化部分
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
     * 从指定位置开始获取满足条件的目标列表（核心优化版）
     * 
     * 该方法在一个按 aabbCollider.right 升序排列的数组中，查找第一个
     * 满足 aabbCollider.right >= query.left 条件的元素索引。
     * 
     * 性能优化策略：
     * 1. 使用 rightValues 数组避免多层属性访问
     * 2. 小数组（<=8个元素）：直接线性扫描
     * 3. 缓存命中：当查询位置变化很小时，从上次位置开始线性扫描
     * 4. 边界快速检查：检查首尾元素，快速处理极端情况
     * 5. 二分查找：其他情况使用标准二分查找
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
     */
    public static function getCachedTargetsFromIndex(
        target:Object,
        updateInterval:Number,
        requestType:String,
        query:AABBCollider
    ):Object {
        // 确定目标状态
        var targetStatus:String = (requestType == "全体")
            ? "all"
            : target.是否为敌人.toString();
        
        // 获取缓存项
        if (!_targetCaches[targetStatus]) _targetCaches[targetStatus] = {};
        var stateCache:Object = _targetCaches[targetStatus];
        var cacheEntry:Object = stateCache[requestType];
        if (!cacheEntry) cacheEntry = stateCache[requestType] = _createCacheEntry();
        
        // 检查是否需要更新缓存
        var currentFrame:Number = _root.帧计时器.当前帧数;
        if ((currentFrame - cacheEntry.lastUpdatedFrame) >= updateInterval) {
            updateTargetCache(target, requestType, targetStatus);
        }
        
        // 获取数据数组和坐标值数组
        var list:Array = cacheEntry.data;
        var rightValues:Array = cacheEntry.rightValues;  // 使用预缓存的坐标值
        var n:Number = list.length;
        
        // 空数组快速返回
        if (n == 0) {
            return _emptyResult;
        }
        
        // 提取查询参数
        var queryLeft:Number = query.left;
        var resultCache:Object = _resultCache;  // 使用预分配的结果对象，避免频繁创建
        
        // =====================================================================
        // 策略1：小数组优化（<=8个元素）
        // 对于小数组，线性扫描比二分查找更快
        // =====================================================================
        if (n <= 8) {
            var i:Number = 0;
            do {
                if (rightValues[i] >= queryLeft) {  // 直接访问数组，更快
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
        // =====================================================================
        
        // 检查缓存是否有效
        var cacheValid:Boolean = (!isNaN(_lastQueryLeft) &&  // 有上次查询记录
                                _lastIndex >= 0 &&           // 索引在有效范围内
                                _lastIndex < n);              // 索引未越界
        
        if (cacheValid) {
            // 计算查询位置的变化量

            var deltaQueryDiff:Number = queryLeft - _lastQueryLeft;
            // 只有变化量在阈值内才使用缓存
            if ((deltaQueryDiff < 0 ? -deltaQueryDiff : deltaQueryDiff) <= TargetCacheUpdater._THRESHOLD) {
                
                // 获取缓存位置的右边界值
                var cachedRight:Number = rightValues[_lastIndex];  // 使用预缓存值
                
                // -------------------------------------------------------------
                // 情况A：查询位置右移（queryLeft > 上次位置）
                // 需要向后扫描，找到新的起始位置
                // -------------------------------------------------------------
                if (cachedRight < queryLeft) {
                    var idxForward:Number = _lastIndex;
                    
                    // 向后扫描，跳过所有不满足条件的元素
                    while (idxForward < n && rightValues[idxForward] < queryLeft) {
                        idxForward++;
                    }
                    
                    // 确保找到的是第一个满足条件的元素
                    // 可能存在多个元素的 right 值相同的情况
                    if (idxForward > 0 && idxForward < n) {
                        while (idxForward > 0 && rightValues[idxForward - 1] >= queryLeft) {
                            idxForward--;
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
                    while (idxBackward > 0 && rightValues[idxBackward - 1] >= queryLeft) {
                        idxBackward--;
                    }
                    
                    // 返回结果并更新缓存
                    resultCache.data = list;
                    resultCache.startIndex = idxBackward;
                    _lastQueryLeft = queryLeft;
                    _lastIndex = idxBackward;
                    return resultCache;
                }
            }
        }
        
        // =====================================================================
        // 策略3：边界元素快速检查
        // 在进行完整二分查找前，先检查首尾元素
        // =====================================================================
        
        // 检查第一个元素
        if (rightValues[0] >= queryLeft) {  // 使用预缓存值
            resultCache.data = list;
            resultCache.startIndex = 0;
            _lastQueryLeft = queryLeft;
            _lastIndex = 0;
            return resultCache;
        }
        
        // 检查最后一个元素
        if (rightValues[n - 1] < queryLeft) {  // 使用预缓存值
            resultCache.data = list;
            resultCache.startIndex = n;  // 所有元素都不满足
            _lastQueryLeft = queryLeft;
            _lastIndex = n;
            return resultCache;
        }
        
        // =====================================================================
        // 策略4：标准二分查找（使用预缓存坐标值）
        // 当缓存失效且不是边界情况时，使用二分查找
        // =====================================================================
        var l:Number = 1;
        var r:Number = n - 1;
        
        do {
            var m:Number = (l + r) >> 1;  // 位运算实现除2，更快
            var unitRight:Number = rightValues[m];  // 直接访问数组
            
            if (unitRight >= queryLeft) {
                // 检查是否是第一个满足条件的元素
                if (rightValues[m - 1] < queryLeft) {  // 直接访问数组
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
    // 最近单位查询（优化版）
    // ========================================================================
    
    /**
     * 按X轴快速查找与目标单位最近的单位（深度优化版）
     * 
     * 【优化要点】：
     * 1. 预缓存目标坐标，减少重复的属性链访问
     * 2. 利用nameIndex实现O(1)邻居查找，或在目标不在列表时进行全表扫描
     * 3. 使用预缓存的leftValues数组避免多层属性访问
     * 4. 在全表扫描中应用常数优化技巧
     * 
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

        // 获取数据和坐标值数组
        var list:Array = cacheEntry.data;
        var leftValues:Array = cacheEntry.leftValues;  // 使用预缓存的坐标值

        // 【优化点1】：预缓存目标坐标，减少重复属性访问
        var targetX:Number = target.aabbCollider.left;

        // --- 快速定位自身索引 ---
        var idx:Number = cacheEntry.nameIndex[target._name];
        var listLength:Number = list.length;

        if (idx == undefined) {
            // 如果自身不在列表中，则进行全表扫描查找最近单位
            var minDist:Number = Number.MAX_VALUE;
            var nearest:Object = null;
            
            // 【优化点2】：在循环中直接使用预缓存的坐标值
            
            for (var i:Number = 0; i < listLength; i++) {
                var unit:Object = list[i];
                if (unit == target) continue; // 跳过自身
                
                // 直接使用预缓存值计算距离，避免属性链访问
                var d:Number = leftValues[i] - targetX;
                var absD:Number = (d < 0 ? -d : d);
                if (absD < minDist) { 
                    minDist = absD; // 更新最小距离
                    nearest = unit; // 更新最近单位
                }
            }
            return nearest;
        }

        // --- 当目标在列表中时，只需检查左右相邻两个元素 ---
        // 获取左侧单位（如果存在）
        var leftObj:Object = (idx > 0) ? list[idx - 1] : null;
        // 获取右侧单位（如果存在）
        var rightObj:Object = (idx < listLength - 1) ? list[idx + 1] : null;

        // 【优化点3】：计算左右单位与目标的距离，使用预缓存坐标值和缓存的targetX
        var diffL:Number = (leftObj) ? (leftValues[idx - 1] - targetX) : 0;
        var dl:Number = (leftObj) ? (diffL < 0 ? -diffL : diffL) : Number.MAX_VALUE;

        var diffR:Number = (rightObj) ? (leftValues[idx + 1] - targetX) : 0;
        var dr:Number = (rightObj) ? (diffR < 0 ? -diffR : diffR) : Number.MAX_VALUE;

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
    // 最远单位查询（优化版）
    // ========================================================================

    /**
     * 按X轴快速查找与目标单位最远的单位（深度优化版）
     * 
     * 【优化要点】：
     * 1. 预缓存目标坐标，减少重复的属性链访问
     * 2. 利用排序数组特性：最远单位必定是首元素或尾元素，实现O(1)查询
     * 3. 使用预缓存的leftValues数组避免多层属性访问
     * 4. 优化全表扫描逻辑，减少不必要的计算
     * 
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
        var leftValues:Array = cacheEntry.leftValues;  // 使用预缓存的坐标值

        var listLength:Number = list.length;
        
        if (listLength <= 1) {
            return list[0] || null;  // 列表为空或只有一个单位
        }

        // 【优化点1】：预缓存目标坐标，减少重复属性访问
        var targetX:Number = target.aabbCollider.left;

        // --- 快速定位自身索引 ---
        var idx:Number = cacheEntry.nameIndex[target._name];
        
        if (idx == undefined) {
            // 如果自身不在列表中，则进行全表扫描查找最远单位
            var maxDist:Number = -1;
            var farthest:Object = null;
            
            // 【优化点2】：在循环中直接使用预缓存坐标值和缓存的targetX
            for (var i:Number = 0; i < listLength; i++) {
                var unit:Object = list[i];
                if (unit == target) continue; // 跳过自身
                
                // 使用预缓存值和缓存的targetX计算距离
                var d:Number = leftValues[i] - targetX;
                var absD:Number = (d < 0 ? -d : d);
                if (absD > maxDist) { 
                    maxDist = absD;
                    farthest = unit;
                }
            }
            return farthest;
        }

        // --- O(1)核心算法：最远单位必定是首元素或尾元素 ---
        var firstObj:Object = list[0];
        var lastObj:Object = list[listLength - 1];
        
        // 特殊情况：如果自己就是首元素，最远的是尾元素
        if (idx == 0) return (listLength > 1) ? lastObj : null;
        
        // 特殊情况：如果自己就是尾元素，最远的是首元素  
        if (idx == listLength - 1) return firstObj;
        
        // 【优化点3】：一般情况下比较到首尾的距离，使用预缓存值和缓存的targetX
        var d1:Number = leftValues[0] - targetX;
        var d2:Number = leftValues[listLength - 1] - targetX;
        
        return ((d1 < 0 ? -d1 : d1) >= (d2 < 0 ? -d2 : d2)) ? firstObj : lastObj;
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
    // 区域搜索方法（深度优化版）
    // ========================================================================

    /**
     * 查找指定X轴范围内的所有单位（深度优化版）
     * 
     * 【优化要点】：
     * 1. 预缓存目标坐标和边界值，减少重复计算
     * 2. 利用有序数组特性，使用二分查找定位起始和结束位置
     * 3. 使用预缓存的leftValues数组提高查询性能
     * 4. 【关键优化】使用直接索引赋值替代Array.push()，减少函数调用开销
     * 5. 优化循环结构和边界检查
     * 
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
        var leftValues:Array = cacheEntry.leftValues;  // 使用预缓存的坐标值
        var len:Number = list.length;
        if (len == 0) return [];

        // 【优化点1】：预缓存目标坐标和边界值，减少重复计算
        var targetX:Number = target.aabbCollider.left;
        var leftBound:Number = targetX - leftRange;
        var rightBound:Number = targetX + rightRange;

        // === 左边界二分查找 (>= leftBound) ===
        var startIdx:Number;
        if (leftValues[0] >= leftBound) {  // 使用预缓存值
            startIdx = 0;
        } else if (leftValues[len - 1] < leftBound) {  // 使用预缓存值
            return [];
        } else {
            var l:Number = 0;
            var r:Number = len - 1;
            while (l < r) {
                var m:Number = (l + r) >> 1;
                if (leftValues[m] < leftBound) l = m + 1;  // 使用预缓存值
                else r = m;
            }
            startIdx = l;
        }

        // === 右边界二分查找 (> rightBound) ===
        var endIdx:Number;
        var r2:Number = len - 1;
        if (leftValues[r2] <= rightBound) {  // 使用预缓存值
            endIdx = len;
        } else {
            var l2:Number = startIdx; // 优化：从 startIdx 开始
            
            while (l2 < r2) {
                var m2:Number = (l2 + r2) >> 1;
                if (leftValues[m2] <= rightBound) l2 = m2 + 1;  // 使用预缓存值
                else r2 = m2;
            }
            endIdx = l2;
        }

        // === 【关键优化】使用直接索引赋值构建结果数组 ===
        var result:Array = [];
        var resultIdx:Number = 0;  // 结果数组的当前索引
        
        // 【优化点2】：使用直接索引赋值代替push()，减少函数调用开销
        for (var i:Number = startIdx; i < endIdx; i++) {
            var unit:Object = list[i];
            if (unit != target) {
                result[resultIdx++] = unit;  // 直接索引赋值，避免push()的函数调用开销
            }
        }

        return result;
    }

    /**
     * 查找指定半径范围内的所有单位
     * 内部调用优化后的findTargetsInRange方法
     * 
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
    // 范围限制查询方法（优化版）
    // ========================================================================

    /**
     * 查找指定范围内的最近单位（深度优化版）
     * 
     * 【优化要点】：
     * 1. 预缓存目标坐标，减少重复的属性链访问
     * 2. 结合范围查询和最近单位查找，适用于有距离限制的场景
     * 3. 使用预缓存的数据结构提高性能
     * 4. 避免不必要的重复计算
     * 
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
        
        // 【优化点】：预缓存目标坐标，避免重复访问属性链
        var targetX:Number = target.aabbCollider.left;
        var distanceDiff:Number = nearest.aabbCollider.left - targetX;
        return ((distanceDiff < 0 ? -distanceDiff : distanceDiff) <= maxDistance) ? nearest : null;
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
     * 查找指定范围内的最远单位（深度优化版）
     * 
     * 【优化要点】：
     * 1. 预缓存目标坐标，减少重复的属性链访问
     * 2. 利用已优化的最远单位查找算法
     * 3. 避免重复的距离计算
     * 
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
        
        // 【优化点】：预缓存目标坐标，避免重复访问属性链
        var targetX:Number = target.aabbCollider.left;
        var diff:Number = farthest.aabbCollider.left - targetX;

        return (((diff < 0) ? -diff : diff) <= maxDistance) ? farthest : null;
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