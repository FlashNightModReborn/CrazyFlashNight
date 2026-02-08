// ============================================================================
// 目标缓存管理器（重构版 - 外观模式API层）
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 作为系统的公共 API 外观（Facade Pattern）
// 2. 为游戏逻辑提供简单、易用的静态方法
// 3. 将内部复杂的协作流程隐藏起来
// 4. 保持完全的向后兼容性
// 
// 重构改进：
// - 移除了所有内部实现细节，专注于API提供
// - 所有功能委托给 TargetCacheProvider 和 SortedUnitCache
// - 大幅简化了代码，提高了可维护性
// - 保持了所有原有的公共接口不变
// 
// 设计原则：
// - 外观模式：隐藏内部复杂性，提供简单接口
// - 向后兼容：所有原有API调用方式保持不变
// - 委托模式：将具体实现委托给专门的组件
// - 职责分离：只负责API路由，不处理具体逻辑
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheProvider;
import org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * 缓存提供者实例引用
     * 所有缓存相关操作都委托给这个提供者
     */
    private static var _provider:Object = TargetCacheProvider;
    
    /**
     * 初始化标志
     * 确保系统只初始化一次
     */
    private static var _initialized:Boolean = initialize();
    
    /**
     * 静态复用对象，减少GC压力
     * 用于空结果的返回
     */
    private static var _emptyResult:Object = { data: [], startIndex: 0 };

    // ========================================================================
    // 初始化方法
    // ========================================================================
    
    /**
     * 初始化目标缓存管理器
     * 现在只是确保底层组件已正确初始化
     * @return {Boolean} 初始化是否成功
     */
    public static function initialize():Boolean {
        // 委托给提供者进行初始化
        return _provider.initialize();
    }

    // ========================================================================
    // 基础查询方法（保持向后兼容）
    // ========================================================================
    
    /**
     * 获取缓存的目标单位列表
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
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.data : [];
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
    // 范围查询方法（索引定位）- 保持向后兼容
    // ========================================================================
    
    /**
     * 从指定位置开始获取满足条件的目标列表
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @param {AABBCollider} query - 查询碰撞盒
     * @return {Object} 包含data数组、startIndex的结果对象
     */
    public static function getCachedTargetsFromIndex(
        target:Object,
        updateInterval:Number,
        requestType:String,
        query:AABBCollider
    ):Object {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        if (!cache) return _emptyResult;
        
        return cache.getTargetsFromIndex(query);
    }

    /**
     * 基于“单调扫描”的起点查询（双指针预备）。
     * - 内部自动按帧号调用 beginMonotonicSweep，然后执行前向扫描。
     * - 适用于同一帧中子弹按X从左到右处理的场景，常数更小。
     * @param {Object} target            目标单位（用于定位所属阵营缓存）
     * @param {Number} updateInterval    缓存更新间隔（帧）
     * @param {String} requestType       请求类型："敌人"/"友军"/"全体"
     * @param {AABBCollider} query       查询AABB（使用 left 作为判定边界）
     * @return {Object} { data:Array, startIndex:Number }
     */
    public static function getCachedTargetsFromIndexMonotonic(
        target:Object,
        updateInterval:Number,
        requestType:String,
        query:AABBCollider
    ):Object {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        if (!cache) return _emptyResult;

        var currentFrame:Number = _root.帧计时器.当前帧数;
        cache.beginMonotonicSweep(currentFrame);
        return cache.getTargetsFromIndexMonotonic(query);
    }

    /** 单调扫描版：从指定索引开始的“敌人”列表查询 */
    public static function getCachedEnemyFromIndexMonotonic(t:Object, i:Number, aabb:AABBCollider):Object {
        return getCachedTargetsFromIndexMonotonic(t, i, "敌人", aabb);
    }

    /** 单调扫描版：从指定索引开始的“友军”列表查询 */
    public static function getCachedAllyFromIndexMonotonic(t:Object, i:Number, aabb:AABBCollider):Object {
        return getCachedTargetsFromIndexMonotonic(t, i, "友军", aabb);
    }

    /** 单调扫描版：从指定索引开始的“全部”列表查询 */
    public static function getCachedAllFromIndexMonotonic(t:Object, i:Number, aabb:AABBCollider):Object {
        return getCachedTargetsFromIndexMonotonic(t, i, "全体", aabb);
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
    // 最近单位查询方法
    // ========================================================================
    
    /**
     * 查找与目标单位最近的单位
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @return {Object} 最近单位对象，若不存在返回null
     */
    public static function findNearestTarget(
        target:Object,
        updateInterval:Number,
        requestType:String
    ):Object {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.findNearest(target) : null;
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
    // 最远单位查询方法
    // ========================================================================

    /**
     * 查找与目标单位最远的单位
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @return {Object} 最远单位对象，若不存在返回null
     */
    public static function findFarthestTarget(
        target:Object,
        updateInterval:Number,
        requestType:String
    ):Object {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.findFarthest(target) : null;
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
    // 区域搜索方法
    // ========================================================================

    /**
     * 查找指定X轴范围内的所有单位
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @param {Number} leftRange - 左侧搜索范围
     * @param {Number} rightRange - 右侧搜索范围
     * @return {Array} 范围内的单位数组
     */
    public static function findTargetsInRange(
        target:Object,
        updateInterval:Number,
        requestType:String,
        leftRange:Number,
        rightRange:Number
    ):Array {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.findInRange(target, leftRange, rightRange, true) : [];
    }

    /**
     * 查找指定半径范围内的所有单位
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @param {Number} radius - 搜索半径
     * @return {Array} 范围内的单位数组
     */
    public static function findTargetsInRadius(
        target:Object,
        updateInterval:Number,
        requestType:String,
        radius:Number
    ):Array {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.findInRadius(target, radius, true) : [];
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
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.findNearestInRange(target, maxDistance) : null;
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
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.findFarthestInRange(target, maxDistance) : null;
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
    // 单位计数API
    // ========================================================================
    
    /**
     * 获取指定类型的单位总数
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @return {Number} 单位总数
     */
    public static function getTargetCount(
        target:Object,
        updateInterval:Number,
        requestType:String
    ):Number {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.getCount() : 0;
    }

    /**
     * 获取敌人单位总数
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Number} 敌人总数
     */
    public static function getEnemyCount(t:Object, interval:Number):Number {
        return getTargetCount(t, interval, "敌人");
    }

    /**
     * 获取友军单位总数
     * @param {Object} t - 目标单位  
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Number} 友军总数
     */
    public static function getAllyCount(t:Object, interval:Number):Number {
        return getTargetCount(t, interval, "友军");
    }

    /**
     * 获取全体单位总数
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @return {Number} 全体总数
     */
    public static function getAllCount(t:Object, interval:Number):Number {
        return getTargetCount(t, interval, "全体");
    }

    /**
     * 获取指定X轴范围内的单位数量
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数) 
     * @param {String} requestType - 请求类型
     * @param {Number} leftRange - 左侧搜索范围
     * @param {Number} rightRange - 右侧搜索范围
     * @param {Boolean} excludeSelf - 是否排除自身
     * @return {Number} 范围内的单位数量
     */
    public static function getTargetCountInRange(
        target:Object,
        updateInterval:Number,
        requestType:String,
        leftRange:Number,
        rightRange:Number,
        excludeSelf:Boolean
    ):Number {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.getCountInRange(target, leftRange, rightRange, excludeSelf) : 0;
    }

    /**
     * 获取指定半径内的单位数量
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @param {Number} radius - 搜索半径
     * @param {Boolean} excludeSelf - 是否排除自身
     * @return {Number} 半径内的单位数量
     */
    public static function getTargetCountInRadius(
        target:Object,
        updateInterval:Number,
        requestType:String,
        radius:Number,
        excludeSelf:Boolean
    ):Number {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.getCountInRadius(target, radius, excludeSelf) : 0;
    }

    // ========================================================================
    // 便捷计数方法（各类型专用）
    // ========================================================================
    
    /**
     * 获取指定范围内的敌人数量
     */
    public static function getEnemyCountInRange(
        t:Object, interval:Number, leftRange:Number, rightRange:Number, excludeSelf:Boolean
    ):Number {
        return getTargetCountInRange(t, interval, "敌人", leftRange, rightRange, excludeSelf);
    }

    /**
     * 获取指定范围内的友军数量
     */
    public static function getAllyCountInRange(
        t:Object, interval:Number, leftRange:Number, rightRange:Number, excludeSelf:Boolean
    ):Number {
        return getTargetCountInRange(t, interval, "友军", leftRange, rightRange, excludeSelf);
    }

    /**
     * 获取指定范围内的全体数量
     */
    public static function getAllCountInRange(
        t:Object, interval:Number, leftRange:Number, rightRange:Number, excludeSelf:Boolean
    ):Number {
        return getTargetCountInRange(t, interval, "全体", leftRange, rightRange, excludeSelf);
    }

    /**
     * 获取指定半径内的敌人数量
     */
    public static function getEnemyCountInRadius(
        t:Object, interval:Number, radius:Number, excludeSelf:Boolean
    ):Number {
        return getTargetCountInRadius(t, interval, "敌人", radius, excludeSelf);
    }

    /**
     * 获取指定半径内的友军数量
     */
    public static function getAllyCountInRadius(
        t:Object, interval:Number, radius:Number, excludeSelf:Boolean
    ):Number {
        return getTargetCountInRadius(t, interval, "友军", radius, excludeSelf);
    }

    /**
     * 获取指定半径内的全体数量
     */
    public static function getAllCountInRadius(
        t:Object, interval:Number, radius:Number, excludeSelf:Boolean
    ):Number {
        return getTargetCountInRadius(t, interval, "全体", radius, excludeSelf);
    }

    // ========================================================================
    // 缓存获取方法（直接访问缓存对象）
    // ========================================================================
    
    /**
     * 获取缓存对象（直接访问SortedUnitCache实例）
     * 允许外部直接使用缓存对象的完整功能
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @return {SortedUnitCache} 缓存对象实例
     */
    public static function acquireCache(requestType:String, target:Object, updateInterval:Number):SortedUnitCache {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache;
    }
    
    /**
     * 获取敌人缓存对象
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @return {SortedUnitCache} 敌人缓存对象实例
     */
    public static function acquireEnemyCache(target:Object, updateInterval:Number):SortedUnitCache {
        return acquireCache("敌人", target, updateInterval);
    }
    
    /**
     * 获取友军缓存对象
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @return {SortedUnitCache} 友军缓存对象实例
     */
    public static function acquireAllyCache(target:Object, updateInterval:Number):SortedUnitCache {
        return acquireCache("友军", target, updateInterval);
    }
    
    /**
     * 获取全体缓存对象
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @return {SortedUnitCache} 全体缓存对象实例
     */
    public static function acquireAllCache(target:Object, updateInterval:Number):SortedUnitCache {
        return acquireCache("全体", target, updateInterval);
    }
    
    // ========================================================================
    // 条件计数方法
    // ========================================================================
    
    /**
     * 获取满足血量条件的单位数量
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @param {String} hpCondition - 血量条件
     * @param {Boolean} excludeSelf - 是否排除自身
     * @return {Number} 满足条件的单位数量
     */
    public static function getTargetCountByHP(
        target:Object,
        updateInterval:Number,
        requestType:String,
        hpCondition:String,
        excludeSelf:Boolean
    ):Number {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.getCountByHP(hpCondition, excludeSelf ? target : null) : 0;
    }

    /**
     * 获取满足血量条件的敌人数量
     */
    public static function getEnemyCountByHP(
        t:Object, interval:Number, hpCondition:String, excludeSelf:Boolean
    ):Number {
        return getTargetCountByHP(t, interval, "敌人", hpCondition, excludeSelf);
    }

    /**
     * 获取满足血量条件的友军数量
     */
    public static function getAllyCountByHP(
        t:Object, interval:Number, hpCondition:String, excludeSelf:Boolean
    ):Number {
        return getTargetCountByHP(t, interval, "友军", hpCondition, excludeSelf);
    }

    // ========================================================================
    // 距离分布统计方法
    // ========================================================================
    
    /**
     * 获取距离分布统计
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @param {Array} distanceRanges - 距离区间数组
     * @param {Boolean} excludeSelf - 是否排除自身
     * @return {Object} 距离分布统计对象
     */
    public static function getDistanceDistribution(
        target:Object,
        updateInterval:Number,
        requestType:String,
        distanceRanges:Array,
        excludeSelf:Boolean
    ):Object {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.getDistanceDistribution(target, distanceRanges, excludeSelf) : {
            totalCount: 0,
            distribution: [],
            minDistance: -1,
            maxDistance: -1
        };
    }

    /**
     * 获取敌人距离分布统计
     */
    public static function getEnemyDistanceDistribution(
        t:Object, interval:Number, distanceRanges:Array, excludeSelf:Boolean
    ):Object {
        return getDistanceDistribution(t, interval, "敌人", distanceRanges, excludeSelf);
    }

    /**
     * 获取友军距离分布统计
     */
    public static function getAllyDistanceDistribution(
        t:Object, interval:Number, distanceRanges:Array, excludeSelf:Boolean
    ):Object {
        return getDistanceDistribution(t, interval, "友军", distanceRanges, excludeSelf);
    }

    // ========================================================================
    // 杂项工具方法
    // ========================================================================

    /**
     * 查找主角
     * @return {MovieClip} 主角的引用，若不存在返回null
     */
    public static function findHero():MovieClip { 
        return _root.gameworld[_root.控制目标] || null; 
    }

    // ========================================================================
    // 系统管理方法（委托给TargetCacheProvider）
    // ========================================================================
    
    /**
     * 添加单位时更新版本号
     * @param {Object} unit - 新增的单位对象
     */
    public static function addUnit(unit:Object):Void {
        _provider.addUnit(unit);
    }
    
    /**
     * 移除单位时更新版本号
     * @param {Object} unit - 被移除的单位对象
     */
    public static function removeUnit(unit:Object):Void {
        _provider.removeUnit(unit);
    }

    /**
     * 批量添加单位
     * @param {Array} units - 要添加的单位数组
     */
    public static function addUnits(units:Array):Void {
        _provider.addUnits(units);
    }

    /**
     * 批量移除单位
     * @param {Array} units - 要移除的单位数组
     */
    public static function removeUnits(units:Array):Void {
        _provider.removeUnits(units);
    }

    /**
     * 清理缓存
     * @param {String} requestType - 要清理的请求类型（可选）
     */
    public static function clearCache(requestType:String):Void {
        _provider.clearCache(requestType);
    }

    /**
     * 清理所有缓存（向后兼容别名）
     * 旧代码中常用 TargetCacheManager.clear() 进行重置。
     */
    public static function clear():Void {
        clearCache(null);
    }

    /**
     * 强制刷新所有缓存
     */
    public static function invalidateAllCaches():Void {
        _provider.invalidateAllCaches();
    }

    /**
     * 强制刷新指定类型的缓存
     * @param {String} requestType - 要刷新的请求类型
     */
    public static function invalidateCache(requestType:String):Void {
        _provider.invalidateCache(requestType);
    }

    // ========================================================================
    // 调试和监控方法
    // ========================================================================
    
    /**
     * 获取系统统计信息
     * @return {Object} 详细的统计信息
     */
    public static function getSystemStats():Object {
        return _provider.getStats();
    }

    /**
     * 获取系统配置
     * @return {Object} 当前配置信息
     */
    public static function getSystemConfig():Object {
        return _provider.getConfig();
    }

    /**
     * 设置系统配置
     * @param {Object} config - 配置对象
     */
    public static function setSystemConfig(config:Object):Void {
        _provider.setConfig(config);
    }

    /**
     * 生成详细的状态报告
     * @return {String} 格式化的状态报告
     */
    public static function getDetailedStatusReport():String {
        return _provider.getDetailedStatusReport();
    }

    /**
     * 执行系统健康检查
     * @return {Object} 健康检查结果
     */
    public static function performHealthCheck():Object {
        return _provider.performHealthCheck();
    }

    /**
     * 获取优化建议
     * @return {Array} 优化建议数组
     */
    public static function getOptimizationRecommendations():Array {
        return _provider.getOptimizationRecommendations();
    }

    // ========================================================================
    // 过滤器查询方法（新增核心功能）
    // ========================================================================

    /**
     * 查找满足过滤条件的最近单位
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @param {Function} filter - 过滤函数，接收 (unit, target, absDx) 三个参数
     * @param {Number} searchLimit - 最大搜索步数（可选，默认30）
     * @param {Number} distanceThreshold - 距离阈值（可选，默认自适应）
     * @return {Object} 满足条件的最近单位，不存在返回null
     */
    public static function findNearestTargetWithFilter(
        target:Object,
        updateInterval:Number,
        requestType:String,
        filter:Function,
        searchLimit:Number,
        distanceThreshold:Number
    ):Object {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        return cache ? cache.findNearestWithFilter(target, filter, searchLimit, distanceThreshold) : null;
    }

    /**
     * 查找满足过滤条件的最近敌人
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Function} filter - 过滤函数
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @param {Number} distanceThreshold - 距离阈值（可选）
     * @return {Object} 满足条件的最近敌人，不存在返回null
     */
    public static function findNearestEnemyWithFilter(
        t:Object, interval:Number, filter:Function, searchLimit:Number, distanceThreshold:Number
    ):Object {
        return findNearestTargetWithFilter(t, interval, "敌人", filter, searchLimit, distanceThreshold);
    }

    /**
     * 查找满足过滤条件的最近友军
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Function} filter - 过滤函数
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @param {Number} distanceThreshold - 距离阈值（可选）
     * @return {Object} 满足条件的最近友军，不存在返回null
     */
    public static function findNearestAllyWithFilter(
        t:Object, interval:Number, filter:Function, searchLimit:Number, distanceThreshold:Number
    ):Object {
        return findNearestTargetWithFilter(t, interval, "友军", filter, searchLimit, distanceThreshold);
    }

    /**
     * 查找满足过滤条件的最近全体单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Function} filter - 过滤函数
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @param {Number} distanceThreshold - 距离阈值（可选）
     * @return {Object} 满足条件的最近全体单位，不存在返回null
     */
    public static function findNearestAllWithFilter(
        t:Object, interval:Number, filter:Function, searchLimit:Number, distanceThreshold:Number
    ):Object {
        return findNearestTargetWithFilter(t, interval, "全体", filter, searchLimit, distanceThreshold);
    }

    // ========================================================================
    // 预定义过滤器方法（游戏逻辑专用）
    // ========================================================================

    /**
     * 查找最近的构成威胁的敌人（威胁值 >= 阈值）
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} threatThreshold - 威胁阈值
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的威胁敌人，不存在返回null
     */
    public static function findNearestThreateningEnemy(t:Object, interval:Number, threatThreshold:Number, searchLimit:Number):Object {
        var threatFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return u.threat != undefined && u.threat >= threatThreshold;
        };
        // _root.发布消息(t._name, "findNearestThreateningEnemy");
        return findNearestEnemyWithFilter(t, interval, threatFilter, searchLimit, undefined);
    }

    /**
     * 查找最近的低血量敌人（血量 < 50%）
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的低血量敌人，不存在返回null
     */
    public static function findNearestLowHPEnemy(t:Object, interval:Number, searchLimit:Number):Object {
        var lowHPFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return (u.hp / u.maxhp) < 0.5;
        };
        return findNearestEnemyWithFilter(t, interval, lowHPFilter, searchLimit, undefined);
    }

    /**
     * 查找最近的受伤友军（血量 < 100%）
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的受伤友军，不存在返回null
     */
    public static function findNearestInjuredAlly(t:Object, interval:Number, searchLimit:Number):Object {
        var injuredFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return u.hp < u.maxhp;
        };
        return findNearestAllyWithFilter(t, interval, injuredFilter, searchLimit, undefined);
    }

    /**
     * 查找最近的特定类型单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型("敌人"、"友军"或"全体")
     * @param {String} unitType - 单位类型标识
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的指定类型单位，不存在返回null
     */
    public static function findNearestUnitByType(
        t:Object, interval:Number, requestType:String, unitType:String, searchLimit:Number
    ):Object {
        var typeFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return u.unitType == unitType || u._name.indexOf(unitType) != -1;
        };
        return findNearestTargetWithFilter(t, interval, requestType, typeFilter, searchLimit, undefined);
    }

    /**
     * 查找最近的强化单位（有特定buff）
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {String} buffName - buff名称
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的强化敌人，不存在返回null
     */
    public static function findNearestBuffedEnemy(t:Object, interval:Number, buffName:String, searchLimit:Number):Object {
        var buffFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return u.buffs && u.buffs[buffName] != undefined;
        };
        return findNearestEnemyWithFilter(t, interval, buffFilter, searchLimit, undefined);
    }

    /**
     * 查找指定范围内满足过滤条件的最近单位
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @param {Function} filter - 过滤函数
     * @param {Number} maxDistance - 最大搜索距离
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 满足条件的最近单位，不存在返回null
     */
    public static function findNearestTargetWithFilterInRange(
        target:Object,
        updateInterval:Number,
        requestType:String,
        filter:Function,
        maxDistance:Number,
        searchLimit:Number
    ):Object {
        var distanceFilter:Function = function(u:Object, t:Object, distance:Number):Boolean {
            return distance <= maxDistance && filter(u, t, distance);
        };
        return findNearestTargetWithFilter(target, updateInterval, requestType, distanceFilter, searchLimit, maxDistance);
    }

    // ========================================================================
    // 带回退降级的过滤器查询方法（新增核心功能）
    // ========================================================================

    /**
     * 查找满足过滤条件的最近单位，如果没有满足的则回退到基础查询
     * @param {Object} target - 目标单位
     * @param {Number} updateInterval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型
     * @param {Function} filter - 过滤函数，接收 (unit, target, absDx) 三个参数
     * @param {Number} searchLimit - 最大搜索步数（可选，默认30）
     * @param {Number} distanceThreshold - 距离阈值（可选，默认自适应）
     * @return {Object} 满足条件的最近单位，如果过滤器查询失败则返回基础查询结果
     */
    public static function findNearestTargetWithFallback(
        target:Object,
        updateInterval:Number,
        requestType:String,
        filter:Function,
        searchLimit:Number,
        distanceThreshold:Number
    ):Object {
        var cache:SortedUnitCache = _provider.getCache(requestType, target, updateInterval);
        if (!cache) return null;
        
        // 首先尝试过滤器查询
        var filteredResult:Object = cache.findNearestWithFilter(target, filter, searchLimit, distanceThreshold);
        
        // 如果过滤器查询找到了结果，直接返回
        if (filteredResult != null) {
            return filteredResult;
        }
        
        // 如果过滤器查询没有找到结果，回退到基础查询
        return cache.findNearest(target);
    }

    /**
     * 查找满足过滤条件的最近敌人，如果没有满足的则回退到基础查询
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Function} filter - 过滤函数
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @param {Number} distanceThreshold - 距离阈值（可选）
     * @return {Object} 满足条件的最近敌人，如果过滤器查询失败则返回最近敌人
     */
    public static function findNearestEnemyWithFallback(
        t:Object, interval:Number, filter:Function, searchLimit:Number, distanceThreshold:Number
    ):Object {
        return findNearestTargetWithFallback(t, interval, "敌人", filter, searchLimit, distanceThreshold);
    }

    /**
     * 查找满足过滤条件的最近友军，如果没有满足的则回退到基础查询
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Function} filter - 过滤函数
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @param {Number} distanceThreshold - 距离阈值（可选）
     * @return {Object} 满足条件的最近友军，如果过滤器查询失败则返回最近友军
     */
    public static function findNearestAllyWithFallback(
        t:Object, interval:Number, filter:Function, searchLimit:Number, distanceThreshold:Number
    ):Object {
        return findNearestTargetWithFallback(t, interval, "友军", filter, searchLimit, distanceThreshold);
    }

    /**
     * 查找满足过滤条件的最近全体单位，如果没有满足的则回退到基础查询
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Function} filter - 过滤函数
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @param {Number} distanceThreshold - 距离阈值（可选）
     * @return {Object} 满足条件的最近全体单位，如果过滤器查询失败则返回最近单位
     */
    public static function findNearestAllWithFallback(
        t:Object, interval:Number, filter:Function, searchLimit:Number, distanceThreshold:Number
    ):Object {
        return findNearestTargetWithFallback(t, interval, "全体", filter, searchLimit, distanceThreshold);
    }

    // ========================================================================
    // 预定义过滤器回退方法（游戏逻辑专用）
    // ========================================================================


    /**
     * 查找最近的构成威胁的敌人（威胁值 >= 阈值），如果没有则回退到最近敌人
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} threatThreshold - 威胁阈值
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的威胁敌人，如果没有则返回最近敌人
     */
    public static function findNearestThreateningEnemyWithFallback(t:Object, interval:Number, threatThreshold:Number, searchLimit:Number):Object {
        var threatFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return u.threat != undefined && u.threat >= threatThreshold;
        };
        return findNearestEnemyWithFallback(t, interval, threatFilter, searchLimit, undefined);
    }

    /**
     * 查找最近的低血量敌人，如果没有则回退到最近敌人
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的低血量敌人，如果没有则返回最近敌人
     */
    public static function findNearestLowHPEnemyWithFallback(t:Object, interval:Number, searchLimit:Number):Object {
        var lowHPFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return (u.hp / u.maxhp) < 0.5;
        };
        return findNearestEnemyWithFallback(t, interval, lowHPFilter, searchLimit, undefined);
    }

    /**
     * 查找最近的受伤友军，如果没有则回退到最近友军
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的受伤友军，如果没有则返回最近友军
     */
    public static function findNearestInjuredAllyWithFallback(t:Object, interval:Number, searchLimit:Number):Object {
        var injuredFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return u.hp < u.maxhp;
        };
        return findNearestAllyWithFallback(t, interval, injuredFilter, searchLimit, undefined);
    }

    /**
     * 查找最近的特定类型单位，如果没有则回退到最近单位
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {String} requestType - 请求类型("敌人"、"友军"或"全体")
     * @param {String} unitType - 单位类型标识
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的指定类型单位，如果没有则返回最近单位
     */
    public static function findNearestUnitByTypeWithFallback(
        t:Object, interval:Number, requestType:String, unitType:String, searchLimit:Number
    ):Object {
        var typeFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return u.unitType == unitType || u._name.indexOf(unitType) != -1;
        };
        return findNearestTargetWithFallback(t, interval, requestType, typeFilter, searchLimit, undefined);
    }

    /**
     * 查找最近的强化单位，如果没有则回退到最近敌人
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {String} buffName - buff名称
     * @param {Number} searchLimit - 最大搜索步数（可选）
     * @return {Object} 最近的强化敌人，如果没有则返回最近敌人
     */
    public static function findNearestBuffedEnemyWithFallback(t:Object, interval:Number, buffName:String, searchLimit:Number):Object {
        var buffFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
            return u.buffs && u.buffs[buffName] != undefined;
        };
        return findNearestEnemyWithFallback(t, interval, buffFilter, searchLimit, undefined);
    }

    // ========================================================================
    // 智能敌人搜索方法（AI专用）
    // ========================================================================
    
    /**
     * 智能查找有效的敌人目标（友军AI专用）
     * 1. 优先使用原有逻辑查找威胁敌人
     * 2. 找不到时降级查找任何有效敌人（排除地图元件）
     * @param {Object} t - 目标单位
     * @param {Number} interval - 更新间隔(帧数)
     * @param {Number} preferredThreat - 首选威胁阈值
     * @return {Object} 有效的敌人目标，不存在返回null
     */
    public static function findValidEnemyForAI(t:Object, interval:Number, preferredThreat:Number):Object {
        // 第一步：使用原有逻辑查找威胁敌人（不做额外过滤）
        var target:Object = findNearestThreateningEnemy(t, interval, preferredThreat);
        
        // 第二步：找不到时使用兜底策略，过滤地图元件
        if (!target) {
            // 过滤地图元件的过滤器
            var validTargetFilter:Function = function(u:Object, target:Object, distance:Number):Boolean {
                // 排除带element属性的地图元件
                return !u.element;
            };
            // _root.发布消息(t._name, "findValidEnemyForAI: Fallback to valid enemy search");
            target = findNearestEnemyWithFilter(t, interval, validTargetFilter, undefined, undefined);
        }
        
        return target;
    }
    
    // ========================================================================
    // 【重构兼容】更新缓存方法（保持向后兼容）
    // ========================================================================
    
    /**
     * 强制更新目标缓存（保持向后兼容）
     * 现在委托给 TargetCacheProvider 处理
     * @param {Object} target - 目标单位
     * @param {String} requestType - 请求类型
     * @param {String} targetStatus - 目标状态
     */
    public static function updateTargetCache(
        target:Object,
        requestType:String,
        targetStatus:String
    ):Void {
        // 使用新的系统强制刷新对应的缓存
        invalidateCache(requestType);
        // 立即获取一次缓存以触发更新
        _provider.getCache(requestType, target, 0);
    }
}
