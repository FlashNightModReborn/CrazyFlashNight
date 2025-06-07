// ============================================================================
// 有序单位缓存（SortedUnitCache）- 独立数据模型与查询执行器
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 封装一个已按X轴排序的单位列表及其优化数据结构
// 2. 提供高性能的查询方法：最近/最远/范围/计数等
// 3. 内置二分查找和增量扫描优化算法
// 4. 纯数据模型：不关心自身如何创建或更新，专注于查询执行
// 
// 设计原则：
// - 单一职责：只负责数据存储和查询执行
// - 高内聚：所有查询相关的逻辑都封装在这个类中
// - 无状态依赖：不依赖于全局状态或外部缓存管理器
// - 性能优化：充分利用预缓存数据和算法优化
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizer;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;

class org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache {

    // ========================================================================
    // 实例成员定义
    // ========================================================================
    
    /**
     * 已按 aabbCollider.left 升序排序的单位数组
     * 这是缓存的核心数据，所有查询都基于这个有序数组
     */
    public var data:Array;
    
    /**
     * 名称到索引的映射表
     * 结构: {单位._name: 数组索引}
     * 用于O(1)时间复杂度的单位定位
     */
    public var nameIndex:Object;
    
    /**
     * 预缓存的 aabbCollider.left 值数组
     * 与 data 数组一一对应，用于避免重复的属性链访问
     */
    public var leftValues:Array;
    
    /**
     * 预缓存的 aabbCollider.right 值数组
     * 与 data 数组一一对应，用于范围查询的性能优化
     */
    public var rightValues:Array;
    
    /**
     * 缓存最后更新的帧数
     * 用于缓存生命周期管理（由外部缓存管理器使用）
     */
    public var lastUpdatedFrame:Number;

    // ========================================================================
    // 查询状态缓存（用于增量扫描优化）
    // ========================================================================
    
    /**
     * 上一次查询的左边界值
     * 用于判断本次查询是否可以利用缓存进行增量扫描
     * 
     * 初始化为极小值，用于强制触发首次查询
     */
    private var _lastQueryLeft:Number = -9999999;
    
    /**
     * 上一次查询结果的索引位置
     * 配合 _lastQueryLeft 使用，作为增量扫描的起始位置
     */
    private var _lastIndex:Number = 0;

    // ========================================================================
    // 构造函数
    // ========================================================================
    
    /**
     * 构造函数
     * 创建一个新的有序单位缓存实例
     * 
     * @param {Array} sortedUnits - 已排序的单位数组（可选）
     * @param {Object} nameIndex - 名称索引映射（可选）
     * @param {Array} leftValues - left值数组（可选）
     * @param {Array} rightValues - right值数组（可选）
     * @param {Number} lastFrame - 最后更新帧数（可选）
     */
    public function SortedUnitCache(
        sortedUnits:Array,
        nameIndex:Object,
        leftValues:Array,
        rightValues:Array,
        lastFrame:Number
    ) {
        // 初始化数据结构
        this.data = sortedUnits || [];
        this.nameIndex = nameIndex || {};
        this.leftValues = leftValues || [];
        this.rightValues = rightValues || [];
        this.lastUpdatedFrame = lastFrame || 0;
        
        // 重置查询状态缓存
        resetQueryCache();
    }

    // ========================================================================
    // 基础信息方法
    // ========================================================================
    
    /**
     * 获取缓存中的单位总数
     * @return {Number} 单位总数
     */
    public function getCount():Number {
        return this.data.length;
    }
    
    /**
     * 检查缓存是否为空
     * @return {Boolean} 是否为空
     */
    public function isEmpty():Boolean {
        return this.data.length == 0;
    }
    
    /**
     * 获取指定索引的单位
     * @param {Number} index - 索引
     * @return {Object} 单位对象，越界则返回null
     */
    public function getUnitAt(index:Number):Object {
        if (index >= 0 && index < this.data.length) {
            return this.data[index];
        }
        return null;
    }
    
    /**
     * 根据名称查找单位
     * @param {String} unitName - 单位名称
     * @return {Object} 单位对象，不存在则返回null
     */
    public function findUnitByName(unitName:String):Object {
        var index:Number = this.nameIndex[unitName];
        if (index != undefined) {
            return this.data[index];
        }
        return null;
    }

    // ========================================================================
    // 范围查询核心方法（从TargetCacheManager迁移并优化）
    // ========================================================================
    
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
     * @param {AABBCollider} query - 查询碰撞盒，使用其 left 属性作为查询边界
     * @return {Object} 返回结果对象，包含：
     *         - data: {Array} 完整的目标列表（引用原数组，未复制）
     *         - startIndex: {Number} 第一个满足条件的元素索引
     */
    public function getTargetsFromIndex(query:AABBCollider):Object {
        var n:Number = this.data.length;
        
        // 静态复用对象，减少GC压力
        var result:Object = { data: this.data, startIndex: 0 };
        
        // 空数组快速返回
        if (n == 0) {
            result.startIndex = 0;
            return result;
        }
        
        var queryLeft:Number = query.left;
        
        // =====================================================================
        // 策略1：小数组优化（<=8个元素）
        // =====================================================================
        if (n <= 8) {
            var i:Number = 0;
            do {
                if (this.rightValues[i] >= queryLeft) {
                    result.startIndex = i;
                    _lastQueryLeft = queryLeft;
                    _lastIndex = i;
                    return result;
                }
            } while (++i < n);
            
            result.startIndex = n;
            _lastQueryLeft = queryLeft;
            _lastIndex = n;
            return result;
        }
        
        // =====================================================================
        // 策略2：缓存优化 - 增量线性扫描
        // =====================================================================
        var cacheValid:Boolean = (!isNaN(_lastQueryLeft) && 
                                _lastIndex >= 0 && 
                                _lastIndex < n);
        
        if (cacheValid) {
            var deltaQueryDiff:Number = queryLeft - _lastQueryLeft;
            var threshold:Number = AdaptiveThresholdOptimizer.getThreshold();
            
            if ((deltaQueryDiff < 0 ? -deltaQueryDiff : deltaQueryDiff) <= threshold) {
                var cachedRight:Number = this.rightValues[_lastIndex];
                
                if (cachedRight < queryLeft) {
                    // 向后扫描
                    var idxForward:Number = _lastIndex;
                    while (idxForward < n && this.rightValues[idxForward] < queryLeft) {
                        idxForward++;
                    }
                    if (idxForward > 0 && idxForward < n) {
                        while (idxForward > 0 && this.rightValues[idxForward - 1] >= queryLeft) {
                            idxForward--;
                        }
                    }
                    result.startIndex = idxForward;
                    _lastQueryLeft = queryLeft;
                    _lastIndex = idxForward;
                    return result;
                } else {
                    // 向前扫描
                    var idxBackward:Number = _lastIndex;
                    while (idxBackward > 0 && this.rightValues[idxBackward - 1] >= queryLeft) {
                        idxBackward--;
                    }
                    result.startIndex = idxBackward;
                    _lastQueryLeft = queryLeft;
                    _lastIndex = idxBackward;
                    return result;
                }
            }
        }
        
        // =====================================================================
        // 策略3：边界元素快速检查
        // =====================================================================
        if (this.rightValues[0] >= queryLeft) {
            result.startIndex = 0;
            _lastQueryLeft = queryLeft;
            _lastIndex = 0;
            return result;
        }
        
        if (this.rightValues[n - 1] < queryLeft) {
            result.startIndex = n;
            _lastQueryLeft = queryLeft;
            _lastIndex = n;
            return result;
        }
        
        // =====================================================================
        // 策略4：标准二分查找
        // =====================================================================
        var l:Number = 1;
        var r:Number = n - 1;
        
        do {
            var m:Number = (l + r) >> 1;
            var unitRight:Number = this.rightValues[m];
            
            if (unitRight >= queryLeft) {
                if (this.rightValues[m - 1] < queryLeft) {
                    result.startIndex = m;
                    _lastQueryLeft = queryLeft;
                    _lastIndex = m;
                    return result;
                }
                r = m - 1;
            } else {
                l = m + 1;
            }
        } while (l <= r);
        
        result.startIndex = l;
        _lastQueryLeft = queryLeft;
        _lastIndex = l;
        return result;
    }

    // ========================================================================
    // 最近单位查询方法
    // ========================================================================
    
    /**
     * 快速查找与目标单位最近的单位（深度优化版）
     * 
     * 利用有序数组的特性和nameIndex实现高性能查找：
     * - 如果目标在列表中：只需检查左右相邻的两个单位（O(1)）
     * - 如果目标不在列表中：进行全表扫描但使用预缓存坐标值优化
     * 
     * @param {Object} target - 目标单位
     * @return {Object} 最近的单位，不存在则返回null
     */
    public function findNearest(target:Object):Object {
        if (this.data.length == 0) return null;
        
        var targetX:Number = target.aabbCollider.left;
        var idx:Number = this.nameIndex[target._name];
        var listLength:Number = this.data.length;

        if (idx == undefined) {
            // 目标不在列表中，全表扫描
            var minDist:Number = Number.MAX_VALUE;
            var nearest:Object = null;
            
            for (var i:Number = 0; i < listLength; i++) {
                var unit:Object = this.data[i];
                if (unit == target) continue;
                
                var d:Number = this.leftValues[i] - targetX;
                var absD:Number = (d < 0 ? -d : d);
                if (absD < minDist) { 
                    minDist = absD;
                    nearest = unit;
                }
            }
            return nearest;
        }

        // 目标在列表中，只需检查相邻单位
        var leftObj:Object = (idx > 0) ? this.data[idx - 1] : null;
        var rightObj:Object = (idx < listLength - 1) ? this.data[idx + 1] : null;

        var diffL:Number = (leftObj) ? (this.leftValues[idx - 1] - targetX) : 0;
        var dl:Number = (leftObj) ? (diffL < 0 ? -diffL : diffL) : Number.MAX_VALUE;

        var diffR:Number = (rightObj) ? (this.leftValues[idx + 1] - targetX) : 0;
        var dr:Number = (rightObj) ? (diffR < 0 ? -diffR : diffR) : Number.MAX_VALUE;

        if (dl == Number.MAX_VALUE && dr == Number.MAX_VALUE) return null;
        
        return (dl <= dr) ? leftObj : rightObj;
    }

    // ========================================================================
    // 最远单位查询方法
    // ========================================================================
    
    /**
     * 快速查找与目标单位最远的单位（深度优化版）
     * 
     * 核心优化：利用排序数组的特性，最远单位必定是首元素或尾元素
     * 
     * @param {Object} target - 目标单位
     * @return {Object} 最远的单位，不存在则返回null
     */
    public function findFarthest(target:Object):Object {
        var listLength:Number = this.data.length;
        
        if (listLength <= 1) {
            // 单元素缓存：
            // 1) 没传参 (target==undefined) → null
            // 2) 传自身 (target == soleUnit) → null
            // 3) 其他 (外部目标) → 唯一单位
            if (target == undefined || target == this.data[0]) {
                return null;
            }
            return this.data[0];
        }

        var targetX:Number = target.aabbCollider.left;
        var idx:Number = this.nameIndex[target._name];
        
        if (idx == undefined) {
            // 目标不在列表中，全表扫描
            var maxDist:Number = -1;
            var farthest:Object = null;
            
            for (var i:Number = 0; i < listLength; i++) {
                var unit:Object = this.data[i];
                if (unit == target) continue;
                
                var d:Number = this.leftValues[i] - targetX;
                var absD:Number = (d < 0 ? -d : d);
                if (absD > maxDist) { 
                    maxDist = absD;
                    farthest = unit;
                }
            }
            return farthest;
        }

        // O(1)核心算法：最远单位必定是首元素或尾元素
        var firstObj:Object = this.data[0];
        var lastObj:Object = this.data[listLength - 1];
        
        if (idx == 0) return (listLength > 1) ? lastObj : null;
        if (idx == listLength - 1) return firstObj;
        
        var d1:Number = this.leftValues[0] - targetX;
        var d2:Number = this.leftValues[listLength - 1] - targetX;
        
        return ((d1 < 0 ? -d1 : d1) >= (d2 < 0 ? -d2 : d2)) ? firstObj : lastObj;
    }

    // ========================================================================
    // 范围查询方法
    // ========================================================================
    
    /**
     * 查找指定X轴范围内的所有单位（深度优化版）
     * 
     * @param {Object} target - 目标单位
     * @param {Number} leftRange - 左侧搜索范围（相对于目标的距离）
     * @param {Number} rightRange - 右侧搜索范围（相对于目标的距离）
     * @param {Boolean} excludeSelf - 是否排除目标自身
     * @return {Array} 范围内的单位数组
     */
    public function findInRange(
        target:Object,
        leftRange:Number,
        rightRange:Number,
        excludeSelf:Boolean
    ):Array {
        if (excludeSelf == undefined) excludeSelf = true;
        
        var len:Number = this.data.length;
        if (len == 0) return [];

        var targetX:Number = target.aabbCollider.left;
        var leftBound:Number = targetX - leftRange;
        var rightBound:Number = targetX + rightRange;

        // 左边界二分查找
        var startIdx:Number;
        if (this.leftValues[0] >= leftBound) {
            startIdx = 0;
        } else if (this.leftValues[len - 1] < leftBound) {
            return [];
        } else {
            var l:Number = 0;
            var r:Number = len - 1;
            while (l < r) {
                var m:Number = (l + r) >> 1;
                if (this.leftValues[m] < leftBound) l = m + 1;
                else r = m;
            }
            startIdx = l;
        }

        // 右边界二分查找
        var endIdx:Number;
        var r2:Number = len - 1;
        if (this.leftValues[r2] <= rightBound) {
            endIdx = len;
        } else {
            var l2:Number = startIdx;
            while (l2 < r2) {
                var m2:Number = (l2 + r2) >> 1;
                if (this.leftValues[m2] <= rightBound) l2 = m2 + 1;
                else r2 = m2;
            }
            endIdx = l2;
        }

        // 构建结果数组
        var result:Array = [];
        var resultIdx:Number = 0;
        
        for (var i:Number = startIdx; i < endIdx; i++) {
            var unit:Object = this.data[i];
            if (excludeSelf && unit == target) continue;
            result[resultIdx++] = unit;
        }

        return result;
    }

    /**
     * 查找指定半径范围内的所有单位
     * @param {Object} target - 目标单位
     * @param {Number} radius - 搜索半径
     * @param {Boolean} excludeSelf - 是否排除目标自身
     * @return {Array} 范围内的单位数组
     */
    public function findInRadius(target:Object, radius:Number, excludeSelf:Boolean):Array {
        return findInRange(target, radius, radius, excludeSelf);
    }

    // ========================================================================
    // 范围限制查询方法
    // ========================================================================
    
    /**
     * 查找指定范围内的最近单位
     * @param {Object} target - 目标单位
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最近的单位，超出范围返回null
     */
    public function findNearestInRange(target:Object, maxDistance:Number):Object {
        var nearest:Object = findNearest(target);
        if (!nearest) return null;
        
        var targetX:Number = target.aabbCollider.left;
        var distanceDiff:Number = nearest.aabbCollider.left - targetX;
        return ((distanceDiff < 0 ? -distanceDiff : distanceDiff) <= maxDistance) ? nearest : null;
    }

    /**
     * 查找指定范围内的最远单位
     * @param {Object} target - 目标单位
     * @param {Number} maxDistance - 最大搜索距离
     * @return {Object} 范围内最远的单位，超出范围返回null
     */
    public function findFarthestInRange(target:Object, maxDistance:Number):Object {
        var farthest:Object = findFarthest(target);
        if (!farthest) return null;
        
        var targetX:Number = target.aabbCollider.left;
        var diff:Number = farthest.aabbCollider.left - targetX;
        return (((diff < 0) ? -diff : diff) <= maxDistance) ? farthest : null;
    }

    // ========================================================================
    // 计数方法
    // ========================================================================
    
    /**
     * 获取指定X轴范围内的单位数量（高性能版）
     * 
     * @param {Object} target - 目标单位
     * @param {Number} leftRange - 左侧搜索范围
     * @param {Number} rightRange - 右侧搜索范围
     * @param {Boolean} excludeSelf - 是否排除自身
     * @return {Number} 范围内的单位数量
     */
    public function getCountInRange(
        target:Object,
        leftRange:Number,
        rightRange:Number,
        excludeSelf:Boolean
    ):Number {
        if (excludeSelf == undefined) excludeSelf = true;
        
        var len:Number = this.data.length;
        if (len == 0) return 0;

        var targetX:Number = target.aabbCollider.left;
        var leftBound:Number = targetX - leftRange;
        var rightBound:Number = targetX + rightRange;

        // 使用二分查找定位边界
        var startIdx:Number, endIdx:Number;
        
        // 左边界
        if (this.leftValues[0] >= leftBound) {
            startIdx = 0;
        } else if (this.leftValues[len - 1] < leftBound) {
            return 0;
        } else {
            var l:Number = 0;
            var r:Number = len - 1;
            while (l < r) {
                var m:Number = (l + r) >> 1;
                if (this.leftValues[m] < leftBound) l = m + 1;
                else r = m;
            }
            startIdx = l;
        }

        // 右边界
        var r2:Number = len - 1;
        if (this.leftValues[r2] <= rightBound) {
            endIdx = len;
        } else {
            var l2:Number = startIdx;
            while (l2 < r2) {
                var m2:Number = (l2 + r2) >> 1;
                if (this.leftValues[m2] <= rightBound) l2 = m2 + 1;
                else r2 = m2;
            }
            endIdx = l2;
        }

        var count:Number = endIdx - startIdx;

        // 排除自身
        if (excludeSelf && count > 0) {
            var selfIdx:Number = this.nameIndex[target._name];
            if (selfIdx != undefined && selfIdx >= startIdx && selfIdx < endIdx) {
                count--;
            }
        }

        return count;
    }

    /**
     * 获取指定半径内的单位数量
     * @param {Object} target - 目标单位
     * @param {Number} radius - 搜索半径
     * @param {Boolean} excludeSelf - 是否排除自身
     * @return {Number} 半径内的单位数量
     */
    public function getCountInRadius(target:Object, radius:Number, excludeSelf:Boolean):Number {
        return getCountInRange(target, radius, radius, excludeSelf);
    }

    // ========================================================================
    // 条件查询方法
    // ========================================================================
    
    /**
     * 获取满足血量条件的单位数量
     * 
     * @param {String} hpCondition - 血量条件: "low", "medium", "high", "critical", "injured", "healthy"
     * @param {Object} excludeTarget - 要排除的目标单位（可选）
     * @return {Number} 满足条件的单位数量
     */
    public function getCountByHP(hpCondition:String, excludeTarget:Object):Number {
        var len:Number = this.data.length;
        if (len == 0) return 0;

        var count:Number = 0;
        var i:Number = 0;
        var unit:Object, hpRatio:Number;

        switch (hpCondition) {
            case "low":
                for (i = 0; i < len; i++) {
                    unit = this.data[i];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if ((unit.hp / unit.maxhp) <= 0.3) count++;
                }
                break;
                
            case "medium":
                for (i = 0; i < len; i++) {
                    unit = this.data[i];
                    if (excludeTarget && unit == excludeTarget) continue;
                    hpRatio = unit.hp / unit.maxhp;
                    if (hpRatio > 0.3 && hpRatio <= 0.7) count++;
                }
                break;
                
            case "high":
                for (i = 0; i < len; i++) {
                    unit = this.data[i];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if ((unit.hp / unit.maxhp) > 0.7) count++;
                }
                break;
                
            case "critical":
                for (i = 0; i < len; i++) {
                    unit = this.data[i];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if ((unit.hp / unit.maxhp) <= 0.1) count++;
                }
                break;
                
            case "injured":
                for (i = 0; i < len; i++) {
                    unit = this.data[i];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if (unit.hp < unit.maxhp) count++;
                }
                break;
                
            case "healthy":
                for (i = 0; i < len; i++) {
                    unit = this.data[i];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if (unit.hp >= unit.maxhp) count++;
                }
                break;
                
            default:
                return 0;
        }

        return count;
    }

    /**
     * 查找满足血量条件的单位列表
     * @param {String} hpCondition - 血量条件
     * @param {Object} excludeTarget - 要排除的目标单位（可选）
     * @return {Array} 满足条件的单位数组
     */
    public function findByHP(hpCondition:String, excludeTarget:Object):Array {
        var len:Number = this.data.length;
        if (len == 0) return [];

        var result:Array = [];
        var resultIdx:Number = 0;
        var unit:Object, hpRatio:Number;

        switch (hpCondition) {
            case "low":
                for (var i:Number = 0; i < len; i++) {
                    unit = this.data[i];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if ((unit.hp / unit.maxhp) <= 0.3) result[resultIdx++] = unit;
                }
                break;
                
            case "medium":
                for (var i2:Number = 0; i2 < len; i2++) {
                    unit = this.data[i2];
                    if (excludeTarget && unit == excludeTarget) continue;
                    hpRatio = unit.hp / unit.maxhp;
                    if (hpRatio > 0.3 && hpRatio <= 0.7) result[resultIdx++] = unit;
                }
                break;
                
            case "high":
                for (var i3:Number = 0; i3 < len; i3++) {
                    unit = this.data[i3];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if ((unit.hp / unit.maxhp) > 0.7) result[resultIdx++] = unit;
                }
                break;
                
            case "critical":
                for (var i4:Number = 0; i4 < len; i4++) {
                    unit = this.data[i4];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if ((unit.hp / unit.maxhp) <= 0.1) result[resultIdx++] = unit;
                }
                break;
                
            case "injured":
                for (var i5:Number = 0; i5 < len; i5++) {
                    unit = this.data[i5];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if (unit.hp < unit.maxhp) result[resultIdx++] = unit;
                }
                break;
                
            case "healthy":
                for (var i6:Number = 0; i6 < len; i6++) {
                    unit = this.data[i6];
                    if (excludeTarget && unit == excludeTarget) continue;
                    if (unit.hp >= unit.maxhp) result[resultIdx++] = unit;
                }
                break;
        }

        return result;
    }

    // ========================================================================
    // 距离分布分析方法
    // ========================================================================
    
    /**
     * 获取距离分布统计
     * @param {Object} target - 目标单位
     * @param {Array} distanceRanges - 距离区间数组
     * @param {Boolean} excludeSelf - 是否排除自身
     * @return {Object} 距离分布统计对象
     */
    public function getDistanceDistribution(
        target:Object,
        distanceRanges:Array,
        excludeSelf:Boolean
    ):Object {
        if (excludeSelf == undefined) excludeSelf = true;
        if (!distanceRanges || distanceRanges.length == 0) {
            distanceRanges = [50, 100, 200, 300];
        }

        var len:Number = this.data.length;
        if (len == 0) {
            return {
                totalCount: 0,
                distribution: [],
                minDistance: -1,
                maxDistance: -1
            };
        }

        var targetX:Number = target.aabbCollider.left;
        var distribution:Array = [];
        var rangeCount:Number = distanceRanges.length;
        
        for (var r:Number = 0; r < rangeCount; r++) {
            distribution[r] = 0;
        }
        var beyondCount:Number = 0;
        
        var minDist:Number = Number.MAX_VALUE;
        var maxDist:Number = 0;
        var totalCount:Number = 0;

        for (var i:Number = 0; i < len; i++) {
            var unit:Object = this.data[i];
            if (excludeSelf && unit == target) continue;
            
            var distDiff:Number = this.leftValues[i] - targetX;
            var distance:Number = (distDiff < 0) ? -distDiff : distDiff;
            
            totalCount++;
            
            if (distance < minDist) minDist = distance;
            if (distance > maxDist) maxDist = distance;
            
            var assigned:Boolean = false;
            for (var j:Number = 0; j < rangeCount; j++) {
                if (distance <= distanceRanges[j]) {
                    distribution[j]++;
                    assigned = true;
                    break;
                }
            }
            
            if (!assigned) {
                beyondCount++;
            }
        }

        if (totalCount == 0) {
            minDist = -1;
        }

        return {
            totalCount: totalCount,
            distribution: distribution,
            beyondCount: beyondCount,
            minDistance: minDist,
            maxDistance: maxDist,
            distanceRanges: distanceRanges
        };
    }

    // ========================================================================
    // 缓存管理方法
    // ========================================================================
    
    /**
     * 重置查询状态缓存
     * 清除增量扫描的历史状态，用于数据更新后的状态重置
     */
    public function resetQueryCache():Void {
        _lastQueryLeft = -Infinity;
        _lastIndex = 0;
    }

    /**
     * 更新缓存数据
     * 用于外部更新缓存内容
     * 
     * @param {Array} newData - 新的排序数据
     * @param {Object} newNameIndex - 新的名称索引
     * @param {Array} newLeftValues - 新的left值数组
     * @param {Array} newRightValues - 新的right值数组
     * @param {Number} newFrame - 新的更新帧数
     */
    public function updateData(
        newData:Array,
        newNameIndex:Object,
        newLeftValues:Array,
        newRightValues:Array,
        newFrame:Number
    ):Void {
        this.data = newData || [];
        this.nameIndex = newNameIndex || {};
        this.leftValues = newLeftValues || [];
        this.rightValues = newRightValues || [];
        this.lastUpdatedFrame = newFrame || 0;
        
        // 重置查询缓存，因为数据已变化
        resetQueryCache();
    }

    /**
     * 验证缓存数据的完整性
     * 用于调试和质量保证
     * @return {Object} 验证结果
     */
    public function validateData():Object {
        var result:Object = {
            isValid: true,
            errors: [],
            warnings: []
        };

        var len:Number = this.data.length;
        
        // 检查数组长度一致性
        if (this.leftValues.length != len) {
            result.errors.push("leftValues length mismatch: " + this.leftValues.length + " vs " + len);
            result.isValid = false;
        }
        if (this.rightValues.length != len) {
            result.errors.push("rightValues length mismatch: " + this.rightValues.length + " vs " + len);
            result.isValid = false;
        }

        // 检查排序是否正确
        for (var i:Number = 1; i < len; i++) {
            if (this.leftValues[i] < this.leftValues[i - 1]) {
                result.errors.push("Sort order violation at index " + i);
                result.isValid = false;
                break;
            }
        }

        // 检查nameIndex的一致性
        var indexCount:Number = 0;
        for (var name:String in this.nameIndex) {
            indexCount++;
            var idx:Number = this.nameIndex[name];
            if (idx < 0 || idx >= len) {
                result.errors.push("Invalid nameIndex for " + name + ": " + idx);
                result.isValid = false;
            } else if (this.data[idx]._name != name) {
                result.errors.push("nameIndex mismatch for " + name);
                result.isValid = false;
            }
        }

        if (indexCount != len) {
            result.warnings.push("nameIndex count (" + indexCount + ") != data length (" + len + ")");
        }

        return result;
    }

    // ========================================================================
    // 调试和状态方法
    // ========================================================================
    
    /**
     * 获取缓存状态信息
     * @return {Object} 状态信息对象
     */
    public function getStatus():Object {
        return {
            unitCount: this.data.length,
            lastUpdatedFrame: this.lastUpdatedFrame,
            queryCache: {
                lastQueryLeft: _lastQueryLeft,
                lastIndex: _lastIndex
            },
            memoryUsage: {
                dataSize: this.data.length,
                nameIndexSize: 0, // 计算对象大小比较复杂，这里简化
                leftValuesSize: this.leftValues.length,
                rightValuesSize: this.rightValues.length
            }
        };
    }

    /**
     * 生成状态报告字符串
     * @return {String} 格式化的状态报告
     */
    public function getStatusReport():String {
        var status:Object = getStatus();
        var validation:Object = validateData();
        
        var report:String = "=== SortedUnitCache Status ===\n";
        report += "Units: " + status.unitCount + "\n";
        report += "Last Updated: Frame " + status.lastUpdatedFrame + "\n";
        report += "Query Cache: Left=" + status.queryCache.lastQueryLeft + ", Index=" + status.queryCache.lastIndex + "\n";
        report += "Validation: " + (validation.isValid ? "PASSED" : "FAILED") + "\n";
        
        if (validation.errors.length > 0) {
            report += "Errors: " + validation.errors.join(", ") + "\n";
        }
        if (validation.warnings.length > 0) {
            report += "Warnings: " + validation.warnings.join(", ") + "\n";
        }
        
        return report;
    }

    /**
     * 转换为简单的调试字符串
     * @return {String} 简化的状态描述
     */

    public function toString():String {
        return "[SortedUnitCache: " + this.data.length + " units, frame " + this.lastUpdatedFrame + "]";
    }
}