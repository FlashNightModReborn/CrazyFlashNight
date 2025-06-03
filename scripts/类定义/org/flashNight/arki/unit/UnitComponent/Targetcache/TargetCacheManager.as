// ============================================================================
// 目标缓存管理器（升级版）
// ----------------------------------------------------------------------------
// 1. 管理敌人 / 友军 / 全体三大类缓存
// 2. 提供「最近单位」快速查询 API：
//    • findNearestTarget : 按 X 轴查最近单位（核心）
//    • findNearestEnemy  : 便捷封装（敌人）
//    • findNearestAlly   : 便捷封装（友军）
//    • findNearestAll    : 便捷封装（全体）
// 3. 依赖 TargetCacheUpdater 生成的 nameIndex，可 O(1) 拿到目标在
//    排序数组中的位置，仅需对左右相邻元素做常数级比较
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager {

    // ------------------------------------------------------------------
    // 静态成员
    // ------------------------------------------------------------------
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
     * "true" - 敌人状态
     * "false" - 友军状态
     * "all" - 全体状态
     * "undefined" - 未定义状态
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

    // ------------------------------------------------------------------
    // 初始化
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // 对外 · 更新接口 —— 直接强制更新
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // 对外 · 读取接口 —— 带自动按帧更新
    // ------------------------------------------------------------------
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

        // _root.服务器.发布服务器消息(ObjectUtil.toString(cacheEntry))
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

    // 范围查询方法 - 只查找起始索引，利用有序性提前退出

    // 静态复用对象，减少GC压力
    private static var _emptyResult:Object = { data: [], startIndex: 0 };
    private static var _resultCache:Object = { data: null, startIndex: 0 };
    
    /**
     * 获取从指定起始索引开始的缓存目标单位
     * 利用二分查找快速定位第一个可能碰撞的单位，后续利用isOrdered机制提前退出
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {AABBCollider} query - 查询用的AABB碰撞器
     * @return {Object} 包含data数组、startIndex的结果对象
     */
    public static function getCachedTargetsFromIndex(
        target:Object,
        updateInterval:Number,
        requestType:String,
        query:AABBCollider
    ):Object {
        var list:Array = getCachedTargets(target, updateInterval, requestType);
        var n:Number = list.length;
        
        if (n == 0) return _emptyResult;
        
        var queryLeft:Number = query.left;
        var resultCache:Object = _resultCache; // 局部化变量
        
        // 小数组线性查找优化
        if (n <= 8) {
            var i:Number = 0;
            do {
                if (list[i].aabbCollider.right >= queryLeft) {
                    resultCache.data = list;
                    resultCache.startIndex = i;
                    return resultCache;
                }
            } while (++i < n);
            
            resultCache.data = list;
            resultCache.startIndex = n;
            return resultCache;
        }
        
        // 先检查首元素，避免在二分查找中重复检查
        var firstUnit:Object = list[0];
        if (firstUnit.aabbCollider.right >= queryLeft) {
            resultCache.data = list;
            resultCache.startIndex = 0;
            return resultCache;
        }
        
        // 再检查尾元素
        var lastUnit:Object = list[n - 1];
        if (lastUnit.aabbCollider.right < queryLeft) {
            resultCache.data = list;
            resultCache.startIndex = n;
            return resultCache;
        }
        
        // 此时确保: list[0].right < queryLeft && list[n-1].right >= queryLeft
        // 在 [1, n-1] 范围内一定有解，使用 do-while
        var l:Number = 1;
        var r:Number = n - 1;
        
        do {
            var m:Number = (l + r) >> 1;
            var unitRight:Number = list[m].aabbCollider.right;
            
            if (unitRight >= queryLeft) {
                // l >= 1，所以 m >= 1，无需检查 m == 0
                if (list[m - 1].aabbCollider.right < queryLeft) {
                    resultCache.data = list;
                    resultCache.startIndex = m;
                    return resultCache;
                }
                r = m - 1;
            } else {
                l = m + 1;
            }
        } while (l <= r);
        
        // 理论上不会到达这里，但保持代码健壮性
        resultCache.data = list;
        resultCache.startIndex = l;
        return resultCache;
    }

    // 便捷封装方法
    /**
     * 获取从指定索引开始的敌人单位
     */
    public static function getCachedEnemyFromIndex(t:Object, i:Number, aabb:AABBCollider):Object {
        return getCachedTargetsFromIndex(t, i, "敌人", aabb);
    }

    /**
     * 获取从指定索引开始的友军单位
     */
    public static function getCachedAllyFromIndex(t:Object, i:Number, aabb:AABBCollider):Object {
        return getCachedTargetsFromIndex(t, i, "友军", aabb);
    }

    /**
     * 获取从指定索引开始的全体单位
     */
    public static function getCachedAllFromIndex(t:Object, i:Number, aabb:AABBCollider):Object {
        return getCachedTargetsFromIndex(t, i, "全体", aabb);
    }

    // ------------------------------------------------------------------
    // ★ 新增 · 最近单位查询 ★
    // ------------------------------------------------------------------
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
    public static function findNearestEnemy(
        t:Object, interval:Number
    ):Object { 
        return findNearestTarget(t, interval, "敌人"); 
    }

    /**
     * 查找X轴上最近的友军单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最近的友军单位，若不存在返回null
     */
    public static function findNearestAlly(
        t:Object, interval:Number
    ):Object { 
        return findNearestTarget(t, interval, "友军"); 
    }

    /**
     * 查找X轴上最近的全体单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最近的全体单位，若不存在返回null
     */
    public static function findNearestAll(
        t:Object, interval:Number
    ):Object { 
        return findNearestTarget(t, interval, "全体"); 
    }


    /**
     * 查找主角
     * @return {MovieClip} 主角的引用，若不存在返回null
     */
    public static function findHero():MovieClip { 
        return _root.gameworld[_root.控制目标] || null; 
    }


    // 在 TargetCacheManager 类中添加以下方法

    // ------------------------------------------------------------------
    //  最远单位查询 ★
    // ------------------------------------------------------------------

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
        if (list.length <= 1) return null; // 列表为空或只有一个单位

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
    public static function findFarthestEnemy(
        t:Object, interval:Number
    ):Object { 
        return findFarthestTarget(t, interval, "敌人"); 
    }

    /**
     * 查找X轴上最远的友军单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最远的友军单位，若不存在返回null
     */
    public static function findFarthestAlly(
        t:Object, interval:Number
    ):Object { 
        return findFarthestTarget(t, interval, "友军"); 
    }

    /**
     * 查找X轴上最远的全体单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Object} 最远的全体单位，若不存在返回null
     */
    public static function findFarthestAll(
        t:Object, interval:Number
    ):Object { 
        return findFarthestTarget(t, interval, "全体"); 
    }

    // ------------------------------------------------------------------
    // ★ 补充 · 范围查询优化方法 ★
    // ------------------------------------------------------------------

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
}