import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.neur.Controller.SimpleKalmanFilter1D;

/**
 * ZoomController.as - 缩放控制组件（卡尔曼滤波平滑版）
 *
 * 负责：
 *  1. 计算基于目标与最远敌人距离的动态缩放
 *  2. 根据敌人数量动态调整缩放限制
 *  3. 使用卡尔曼滤波器实现平滑缩放过渡
 *  4. 处理缩放补偿逻辑（保持 scrollObj 在屏幕上位置恒定）
 *  5. 管理并更新缩放状态
 *
 * 升级特性：
 *  - 卡尔曼滤波：双重滤波确保平滑过渡，防止突变
 *    * 敌人数量滤波：减少检测噪声导致的缩放限制跳跃
 *    * 缩放值滤波：确保最终缩放值的平滑过渡
 *  - 性能优化：滤波计算与数据更新同步，避免每帧计算开销
 *  - 敌人数量感知：根据当前敌人数量动态调整缩放上限
 *  - 配置化：所有魔数抽取为静态属性，便于调整
 *
 * 敌人数量缩放策略：
 *  - 敌人数量 > 8：  缩放限制 1.0 (不放大)
 *  - 敌人数量 5-8：  缩放限制 1.0-1.2
 *  - 敌人数量 3-5：  缩放限制 1.0-1.5  
 *  - 敌人数量 < 3：  缩放限制 1.0-2.0
 *
 * 卡尔曼滤波参数说明：
 *  - 敌人数量滤波：轻度滤波，快速响应但减少噪声
 *  - 缩放值滤波：中度滤波，确保视觉平滑但保持响应性
 *  - 性能策略：滤波计算仅在数据更新时执行，非更新帧使用缓存结果
 *    避免AS2环境下每帧滤波的性能开销
 *
 * 使用示例：
 *   // 调整卡尔曼滤波参数
 *   ZoomController.setKalmanParams(0.1, 0.5, 0.01, 0.1);
 *   
 *   // 重置滤波器（场景切换时）
 *   ZoomController.resetFilters();
 */
class org.flashNight.arki.camera.ZoomController {
    
    // ============ 配置参数（静态属性） ============
    
    /** 距离归一化除数 */
    public static var DISTANCE_NORMALIZER:Number = 100;
    
    /** 参考距离（用于计算对数缩放系数） */
    public static var REFERENCE_DISTANCE:Number = 800;
    
    /** 参考距离下期望的缩放倍数 */
    public static var REFERENCE_ZOOM_MULTIPLIER:Number = 0.89;
    
    /** 缩放计算基数 */
    public static var ZOOM_BASE:Number = 2;
    
    /** 对数缩放系数（自动计算） */
    public static var LOG_SCALE_FACTOR:Number = _calculateLogScaleFactor();
    
    /** 最小缩放倍数 */
    public static var MIN_ZOOM_MULTIPLIER:Number = 1;
    
    /** 基础最大缩放倍数（当敌人很少时） */
    public static var BASE_MAX_ZOOM_MULTIPLIER:Number = 2.0;
    
    /** 缩放变化阈值（低于此值不更新缩放） */
    public static var SCALE_CHANGE_THRESHOLD:Number = 0.005;
    
    /** 查找最远敌人的时间帧数限制 */
    public static var ENEMY_SEARCH_LIMIT:Number = 5;
    
    /** 默认距离值（当找不到敌人时） */
    public static var DEFAULT_DISTANCE:Number = 99999;
    
    /** 性能优化：每多少次调用更新一次最远敌人和敌人数量 */
    public static var UPDATE_FREQUENCY:Number = 60;
    
    // ============ 卡尔曼滤波参数 ============
    
    /** 敌人数量滤波器 - 过程噪声 Q（系统变化的不确定性） */
    public static var ENEMY_COUNT_PROCESS_NOISE:Number = 0.1;
    
    /** 敌人数量滤波器 - 测量噪声 R（观测的不确定性） */
    public static var ENEMY_COUNT_MEASUREMENT_NOISE:Number = 0.5;
    
    /** 缩放值滤波器 - 过程噪声 Q */
    public static var ZOOM_SCALE_PROCESS_NOISE:Number = 0.01;
    
    /** 缩放值滤波器 - 测量噪声 R */
    public static var ZOOM_SCALE_MEASUREMENT_NOISE:Number = 0.1;
    
    // ============ 敌人数量相关配置 ============
    
    /** 敌人数量阈值1：超过此数量时使用最低缩放 */
    public static var ENEMY_COUNT_HIGH_THRESHOLD:Number = 8;
    
    /** 敌人数量阈值2：中等敌人数量的下限 */
    public static var ENEMY_COUNT_MID_THRESHOLD:Number = 5;
    
    /** 敌人数量阈值3：少量敌人数量的下限 */
    public static var ENEMY_COUNT_LOW_THRESHOLD:Number = 3;
    
    /** 敌人数量很多时的最大缩放倍数 (>8个敌人) */
    public static var MAX_ZOOM_HIGH_ENEMY:Number = 1.0;
    
    /** 敌人数量中等时的最大缩放倍数 (5-8个敌人) */
    public static var MAX_ZOOM_MID_ENEMY:Number = 1.2;
    
    /** 敌人数量较少时的最大缩放倍数 (3-5个敌人) */
    public static var MAX_ZOOM_LOW_ENEMY:Number = 1.5;
    
    /** 敌人数量很少时的最大缩放倍数 (<3个敌人) */
    public static var MAX_ZOOM_VERY_LOW_ENEMY:Number = 2.0;
    
    // ============ 内部状态（静态属性） ============
    
    /** 当前缩放值 */
    private static var lastScale:Number;
    
    /** 调用计数器 */
    private static var updateCounter:Number = 0;
    
    /** 缓存的最远敌人信息 */
    private static var cachedFarthestEnemy:Object;
    
    /** 缓存的原始敌人数量 */
    private static var cachedRawEnemyCount:Number = 0;
    
    /** 当前动态最大缩放倍数 */
    private static var currentMaxZoomMultiplier:Number = BASE_MAX_ZOOM_MULTIPLIER;
    
    /** 最后一次查找敌人时的目标位置（用于判断是否需要强制更新） */
    private static var lastTargetPos:Object = { x: 0, y: 0 };
    
    // ============ 卡尔曼滤波器实例 ============
    
    /** 敌人数量卡尔曼滤波器 */
    private static var enemyCountFilter:SimpleKalmanFilter1D;
    
    /** 缩放值卡尔曼滤波器 */
    private static var zoomScaleFilter:SimpleKalmanFilter1D;
    
    /** 滤波器是否已初始化 */
    private static var filtersInitialized:Boolean = false;
    
    // ============ 公共方法 ============
    
    /**
     * 根据 scrollObj 与最远敌人的距离以及敌人数量，计算 targetZoomScale，并做卡尔曼滤波平滑，
     * 如果缩放发生显著变化（阈值可配置），则：
     *   1) 记录缩放前后 scrollObj 在屏幕上的坐标
     *   2) 更新 gameWorld 与 bgLayer 的 _xscale/_yscale
     *   3) 计算并返回 worldOffset，用于后续坐标补偿
     *
     * @param scrollObj   要跟踪的目标 MovieClip
     * @param gameWorld   全局世界 MovieClip（会直接修改其 _xscale/_yscale）
     * @param bgLayer     "天空盒"根节点 MovieClip（会直接修改其 _xscale/_yscale）
     * @param easeFactor  缓动系数（越大越平滑，但与卡尔曼滤波配合使用时可以设置较小值）
     * @param zoomScale   缩放基数
     * @return Object     { newScale:Number, offsetX:Number, offsetY:Number, enemyCount:Number, filteredEnemyCount:Number, maxZoom:Number }
     *                    newScale：本次最终缩放（相对于 1.0 的倍数）
     *                    offsetX/offsetY：应用于 world 坐标的补偿量（像素）
     *                    enemyCount：原始敌人数量
     *                    filteredEnemyCount：卡尔曼滤波后的敌人数量
     *                    maxZoom：当前最大缩放限制
     */
    public static function updateScale(
        scrollObj:MovieClip,
        gameWorld:MovieClip,
        bgLayer:MovieClip,
        easeFactor:Number,
        zoomScale:Number
    ):Object {
        // 0) 初始化卡尔曼滤波器
        _initializeFiltersIfNeeded();
        
        // 1) 性能优化：检查是否需要更新最远敌人和敌人数量
        updateCounter++;
        var shouldUpdate:Boolean = (updateCounter >= UPDATE_FREQUENCY) || 
                                  (cachedFarthestEnemy == null) ||
                                  _hasTargetMovedSignificantly(scrollObj);
        
        var filteredEnemyCount:Number;
        var filteredZoomScale:Number;
        
        if (shouldUpdate) {
            // 更新最远敌人
            cachedFarthestEnemy = TargetCacheManager.findFarthestEnemy(scrollObj, ENEMY_SEARCH_LIMIT);
            
            // 更新原始敌人数量
            cachedRawEnemyCount = TargetCacheManager.getEnemyCount(scrollObj, ENEMY_SEARCH_LIMIT);
            
            // 2) 计算距离和目标缩放
            var distance:Number = _calculateDistance(scrollObj, cachedFarthestEnemy);
            var targetZoomScale:Number = _calculateTargetZoomScale(distance, zoomScale);
            
            // 3) 性能优化：只在数据更新时进行卡尔曼滤波计算
            // 对敌人数量进行卡尔曼滤波
            enemyCountFilter.predict();
            filteredEnemyCount = enemyCountFilter.update(cachedRawEnemyCount);
            
            // 对缩放值进行卡尔曼滤波
            zoomScaleFilter.predict();
            filteredZoomScale = zoomScaleFilter.update(targetZoomScale);
            
            // 根据滤波后的敌人数量更新最大缩放限制
            currentMaxZoomMultiplier = _calculateMaxZoomByEnemyCount(filteredEnemyCount);
            
            updateCounter = 0;
            lastTargetPos.x = scrollObj._x;
            lastTargetPos.y = scrollObj._y;
        } else {
            // 4) 非更新帧：直接使用缓存的滤波结果，避免重复计算
            filteredEnemyCount = enemyCountFilter.getEstimate();
            filteredZoomScale = zoomScaleFilter.getEstimate();
        }
        
        // 5) 初始化 lastScale
        if (lastScale == undefined) {
            lastScale = filteredZoomScale;
        }
        
        var oldScale:Number = lastScale;
        
        // 6) 轻度缓动（因为已有卡尔曼滤波，缓动可以更激进）
        var newScale:Number = oldScale + (filteredZoomScale - oldScale) / Math.max(1, easeFactor * 0.5);
        
        // 7) 判断是否需要真正更新
        var scaleChanged:Boolean = Math.abs(newScale - oldScale) > SCALE_CHANGE_THRESHOLD;
        if (scaleChanged) {
            // 7.1) 记录缩放前 scrollObj 在屏幕上的坐标
            var preScalePt:Object = { x:0, y:0 };
            scrollObj.localToGlobal(preScalePt);
            
            // 7.2) 应用缩放到 gameWorld 与 bgLayer
            var newScalePercent:Number = newScale * 100;
            gameWorld._xscale = gameWorld._yscale = newScalePercent;
            bgLayer._xscale   = bgLayer._yscale   = newScalePercent;
            
            // 7.3) 记录缩放后 scrollObj 在屏幕上的坐标
            var postScalePt:Object = { x:0, y:0 };
            scrollObj.localToGlobal(postScalePt);
            
            // 7.4) 计算 worldOffset
            var worldOffsetX:Number = preScalePt.x - postScalePt.x;
            var worldOffsetY:Number = preScalePt.y - postScalePt.y;
            
            // 7.5) 更新 lastScale
            lastScale = newScale;
            
            return { 
                newScale: newScale, 
                offsetX: worldOffsetX, 
                offsetY: worldOffsetY,
                enemyCount: cachedRawEnemyCount,
                filteredEnemyCount: filteredEnemyCount,
                maxZoom: currentMaxZoomMultiplier
            };
        }
        
        // 如果没变化，则返回旧值并且 offset 为 0
        return { 
            newScale: oldScale, 
            offsetX: 0, 
            offsetY: 0,
            enemyCount: cachedRawEnemyCount,
            filteredEnemyCount: filteredEnemyCount,
            maxZoom: currentMaxZoomMultiplier
        };
    }
    
    // ============ 配置管理方法 ============
    
    /**
     * 重置所有缓存状态和滤波器（在场景切换等时机调用）
     */
    public static function resetState():Void {
        lastScale = undefined;
        updateCounter = 0;
        cachedFarthestEnemy = null;
        cachedRawEnemyCount = 0;
        currentMaxZoomMultiplier = BASE_MAX_ZOOM_MULTIPLIER;
        lastTargetPos.x = 0;
        lastTargetPos.y = 0;
        
        // 重置滤波器
        resetFilters();
    }
    
    /**
     * 重置卡尔曼滤波器（保持其他状态）
     */
    public static function resetFilters():Void {
        filtersInitialized = false;
        enemyCountFilter = null;
        zoomScaleFilter = null;
    }
    
    /**
     * 强制更新最远敌人和敌人数量（在敌人大量变化时可手动调用）
     */
    public static function forceUpdateEnemy():Void {
        updateCounter = UPDATE_FREQUENCY; // 强制下次更新
    }
    
    /**
     * 设置卡尔曼滤波参数
     * @param enemyCountQ 敌人数量滤波器过程噪声
     * @param enemyCountR 敌人数量滤波器测量噪声
     * @param zoomScaleQ 缩放值滤波器过程噪声
     * @param zoomScaleR 缩放值滤波器测量噪声
     */
    public static function setKalmanParams(enemyCountQ:Number, enemyCountR:Number, zoomScaleQ:Number, zoomScaleR:Number):Void {
        ENEMY_COUNT_PROCESS_NOISE = enemyCountQ;
        ENEMY_COUNT_MEASUREMENT_NOISE = enemyCountR;
        ZOOM_SCALE_PROCESS_NOISE = zoomScaleQ;
        ZOOM_SCALE_MEASUREMENT_NOISE = zoomScaleR;
        
        // 如果滤波器已初始化，更新其参数
        if (filtersInitialized) {
            enemyCountFilter.setProcessNoise(enemyCountQ);
            enemyCountFilter.setMeasurementNoise(enemyCountR);
            zoomScaleFilter.setProcessNoise(zoomScaleQ);
            zoomScaleFilter.setMeasurementNoise(zoomScaleR);
        }
    }
    
    /**
     * 获取当前缩放值
     */
    public static function getCurrentScale():Number {
        return lastScale;
    }
    
    /**
     * 获取当前原始敌人数量
     */
    public static function getCurrentEnemyCount():Number {
        return cachedRawEnemyCount;
    }
    
    /**
     * 获取当前滤波后的敌人数量
     */
    public static function getFilteredEnemyCount():Number {
        if (enemyCountFilter) {
            return enemyCountFilter.getEstimate();
        }
        return cachedRawEnemyCount;
    }
    
    /**
     * 获取当前滤波后的缩放值
     */
    public static function getFilteredZoomScale():Number {
        if (zoomScaleFilter) {
            return zoomScaleFilter.getEstimate();
        }
        return lastScale || 1.0;
    }
    
    /**
     * 获取当前最大缩放限制
     */
    public static function getCurrentMaxZoom():Number {
        return currentMaxZoomMultiplier;
    }
    
    /**
     * 设置缩放值（用于外部强制设置）
     */
    public static function setCurrentScale(scale:Number):Void {
        lastScale = scale;
        // 同时重置缩放滤波器到新值
        if (zoomScaleFilter) {
            zoomScaleFilter.reset(scale, 1.0);
        }
    }
    
    /**
     * 设置敌人数量阈值
     */
    public static function setEnemyCountThresholds(highThreshold:Number, midThreshold:Number, lowThreshold:Number):Void {
        ENEMY_COUNT_HIGH_THRESHOLD = highThreshold;
        ENEMY_COUNT_MID_THRESHOLD = midThreshold;
        ENEMY_COUNT_LOW_THRESHOLD = lowThreshold;
    }
    
    /**
     * 设置不同敌人数量下的缩放上限
     */
    public static function setZoomLimitsByEnemyCount(highEnemyZoom:Number, midEnemyZoom:Number, lowEnemyZoom:Number, veryLowEnemyZoom:Number):Void {
        MAX_ZOOM_HIGH_ENEMY = highEnemyZoom;
        MAX_ZOOM_MID_ENEMY = midEnemyZoom;
        MAX_ZOOM_LOW_ENEMY = lowEnemyZoom;
        MAX_ZOOM_VERY_LOW_ENEMY = veryLowEnemyZoom;
    }
    
    /**
     * 重新计算对数缩放系数（当参考参数改变时调用）
     */
    public static function recalculateLogScaleFactor():Void {
        LOG_SCALE_FACTOR = _calculateLogScaleFactor();
    }
    
    /**
     * 设置参考距离和期望缩放值，并自动重新计算对数系数
     */
    public static function setReferenceParams(refDistance:Number, refZoomMultiplier:Number):Void {
        REFERENCE_DISTANCE = refDistance;
        REFERENCE_ZOOM_MULTIPLIER = refZoomMultiplier;
        recalculateLogScaleFactor();
    }
    
    // ============ 私有辅助方法 ============
    
    /**
     * 初始化卡尔曼滤波器（如果尚未初始化）
     */
    private static function _initializeFiltersIfNeeded():Void {
        if (!filtersInitialized) {
            // 初始化敌人数量滤波器（初始估计为0个敌人）
            enemyCountFilter = new SimpleKalmanFilter1D(0, ENEMY_COUNT_PROCESS_NOISE, ENEMY_COUNT_MEASUREMENT_NOISE);
            
            // 初始化缩放值滤波器（初始估计为1.0倍缩放）
            zoomScaleFilter = new SimpleKalmanFilter1D(1.0, ZOOM_SCALE_PROCESS_NOISE, ZOOM_SCALE_MEASUREMENT_NOISE);
            
            filtersInitialized = true;
        }
    }
    
    /**
     * 根据敌人数量计算当前的最大缩放倍数
     * 使用滤波后的敌人数量，减少因检测噪声导致的缩放限制跳跃
     */
    private static function _calculateMaxZoomByEnemyCount(filteredEnemyCount:Number):Number {
        if (filteredEnemyCount > ENEMY_COUNT_HIGH_THRESHOLD) {
            return MAX_ZOOM_HIGH_ENEMY;
        } else if (filteredEnemyCount >= ENEMY_COUNT_MID_THRESHOLD) {
            return MAX_ZOOM_MID_ENEMY;
        } else if (filteredEnemyCount >= ENEMY_COUNT_LOW_THRESHOLD) {
            return MAX_ZOOM_LOW_ENEMY;
        } else {
            return MAX_ZOOM_VERY_LOW_ENEMY;
        }
    }
    
    /**
     * 根据参考距离和期望缩放倍数计算对数缩放系数
     */
    private static function _calculateLogScaleFactor():Number {
        var normalizedDistance:Number = Math.max(1, REFERENCE_DISTANCE / DISTANCE_NORMALIZER);
        var logScale:Number = Math.log(normalizedDistance) / Math.log(10);
        
        if (Math.abs(logScale) < 0.001) {
            return 1.0;
        }
        
        return (ZOOM_BASE - REFERENCE_ZOOM_MULTIPLIER) / logScale;
    }
    
    /**
     * 判断目标是否移动了足够距离（需要重新查找敌人）
     */
    private static function _hasTargetMovedSignificantly(scrollObj:MovieClip):Boolean {
        var moveThreshold:Number = DISTANCE_NORMALIZER;
        var deltaX:Number = Math.abs(scrollObj._x - lastTargetPos.x);
        var deltaY:Number = Math.abs(scrollObj._y - lastTargetPos.y);
        return (deltaX + deltaY) > moveThreshold;
    }
    
    /**
     * 计算目标与最远敌人的距离
     */
    private static function _calculateDistance(scrollObj:MovieClip, farthestEnemy:Object):Number {
        if (!farthestEnemy) {
            return DEFAULT_DISTANCE;
        }
        return Math.abs(scrollObj._x - farthestEnemy._x) + Math.abs(scrollObj._y - farthestEnemy._y);
    }
    
    /**
     * 基于距离计算目标缩放值
     * 使用当前动态最大缩放限制，根据敌人数量自动调整
     */
    private static function _calculateTargetZoomScale(distance:Number, zoomScale:Number):Number {
        var normalizedDistance:Number = Math.max(1, distance / DISTANCE_NORMALIZER);
        var logScale:Number = Math.log(normalizedDistance) / Math.log(10);
        
        var zoomMultiplier:Number = Math.min(currentMaxZoomMultiplier, 
                                           Math.max(MIN_ZOOM_MULTIPLIER, 
                                                   ZOOM_BASE - logScale * LOG_SCALE_FACTOR));
        
        return zoomScale * zoomMultiplier;
    }
}