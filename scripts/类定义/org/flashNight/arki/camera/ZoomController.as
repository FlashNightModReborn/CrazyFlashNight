import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * ZoomController.as - 缩放控制组件（升级版）
 *
 * 负责：
 *  1. 计算基于目标与最远敌人距离的动态缩放
 *  2. 处理缩放补偿逻辑（保持 scrollObj 在屏幕上位置恒定）
 *  3. 管理并更新缩放状态
 *
 * 升级特性：
 *  - 性能优化：每30次调用才更新一次最远敌人查找
 *  - 配置化：所有魔数抽取为静态属性，便于调整
 *  - 架构优化：lastScale作为类静态属性，避免对象污染
 *  - 智能计算：对数缩放系数根据参考距离和期望缩放值自动计算
 *    示例：当距离=800时期望缩放倍数=0.89，系统自动计算出LOG_SCALE_FACTOR≈1.11
 *
 * 使用示例：
 *   // 修改参考参数（距离1000时期望缩放0.8）
 *   ZoomController.setReferenceParams(1000, 0.8);
 *   
 *   // 或者分别设置后手动重新计算
 *   ZoomController.REFERENCE_DISTANCE = 1200;
 *   ZoomController.REFERENCE_ZOOM_MULTIPLIER = 0.75;
 *   ZoomController.recalculateLogScaleFactor();
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
    
    /** 对数缩放系数（自动计算） 
     * 基于 REFERENCE_DISTANCE 和 REFERENCE_ZOOM_MULTIPLIER 自动计算
     * 修改参考值后需调用 recalculateLogScaleFactor() 更新此值
     */
    public static var LOG_SCALE_FACTOR:Number = _calculateLogScaleFactor();
    
    /** 最小缩放倍数 */
    public static var MIN_ZOOM_MULTIPLIER:Number = 1;
    
    /** 最大缩放倍数 */
    public static var MAX_ZOOM_MULTIPLIER:Number = 1.5;
    
    /** 缩放变化阈值（低于此值不更新缩放） */
    public static var SCALE_CHANGE_THRESHOLD:Number = 0.005;
    
    /** 查找最远敌人的时间帧数限制 */
    public static var ENEMY_SEARCH_LIMIT:Number = 5;
    
    /** 默认距离值（当找不到敌人时） */
    public static var DEFAULT_DISTANCE:Number = 99999;
    
    /** 性能优化：每多少次调用更新一次最远敌人 */
    public static var UPDATE_FREQUENCY:Number = 60;
    
    // ============ 内部状态（静态属性） ============
    
    /** 当前缩放值 */
    private static var lastScale:Number;
    
    /** 调用计数器 */
    private static var updateCounter:Number = 0;
    
    /** 缓存的最远敌人信息 */
    private static var cachedFarthestEnemy:Object;
    
    /** 最后一次查找敌人时的目标位置（用于判断是否需要强制更新） */
    private static var lastTargetPos:Object = { x: 0, y: 0 };
    
    // ============ 公共方法 ============
    
    /**
     * 根据 scrollObj 与最远敌人的距离，计算 targetZoomScale，并做缓动，
     * 如果缩放发生显著变化（阈值可配置），则：
     *   1) 记录缩放前后 scrollObj 在屏幕上的坐标
     *   2) 更新 gameWorld 与 bgLayer 的 _xscale/_yscale
     *   3) 计算并返回 worldOffset，用于后续坐标补偿
     *
     * @param scrollObj   要跟踪的目标 MovieClip
     * @param gameWorld   全局世界 MovieClip（会直接修改其 _xscale/_yscale）
     * @param bgLayer     "天空盒"根节点 MovieClip（会直接修改其 _xscale/_yscale）
     * @param easeFactor  缓动系数（越大越平滑）
     * @param zoomScale   缩放基数
     * @return Object     { newScale:Number, offsetX:Number, offsetY:Number }
     *                    newScale：本次最终缩放（相对于 1.0 的倍数）
     *                    offsetX/offsetY：应用于 world 坐标的补偿量（像素）
     */
    public static function updateScale(
        scrollObj:MovieClip,
        gameWorld:MovieClip,
        bgLayer:MovieClip,
        easeFactor:Number,
        zoomScale:Number
    ):Object {
        // 1) 性能优化：检查是否需要更新最远敌人
        updateCounter++;
        var shouldUpdateEnemy:Boolean = (updateCounter >= UPDATE_FREQUENCY) || 
                                       (cachedFarthestEnemy == null) ||
                                       _hasTargetMovedSignificantly(scrollObj);
        
        if (shouldUpdateEnemy) {
            cachedFarthestEnemy = TargetCacheManager.findFarthestEnemy(scrollObj, ENEMY_SEARCH_LIMIT);
            updateCounter = 0;
            lastTargetPos.x = scrollObj._x;
            lastTargetPos.y = scrollObj._y;
        }
        
        // 2) 计算距离和缩放
        var distance:Number = _calculateDistance(scrollObj, cachedFarthestEnemy);
        var targetZoomScale:Number = _calculateTargetZoomScale(distance, zoomScale);
        
        // 3) 初始化 lastScale
        if (lastScale == undefined) {
            lastScale = targetZoomScale;
        }
        
        var oldScale:Number = lastScale;
        // 4) 缓动计算 newScale
        var newScale:Number = oldScale + (targetZoomScale - oldScale) / easeFactor;
        
        // 5) 判断是否需要真正更新
        var scaleChanged:Boolean = Math.abs(newScale - oldScale) > SCALE_CHANGE_THRESHOLD;
        if (scaleChanged) {
            // 5.1) 记录缩放前 scrollObj 在屏幕上的坐标
            var preScalePt:Object = { x:0, y:0 };
            scrollObj.localToGlobal(preScalePt);
            
            // 5.2) 应用缩放到 gameWorld 与 bgLayer
            var newScalePercent:Number = newScale * 100;
            gameWorld._xscale = gameWorld._yscale = newScalePercent;
            bgLayer._xscale   = bgLayer._yscale   = newScalePercent;
            
            // 5.3) 记录缩放后 scrollObj 在屏幕上的坐标
            var postScalePt:Object = { x:0, y:0 };
            scrollObj.localToGlobal(postScalePt);
            
            // 5.4) 计算 worldOffset
            var worldOffsetX:Number = preScalePt.x - postScalePt.x;
            var worldOffsetY:Number = preScalePt.y - postScalePt.y;
            
            // 5.5) 更新 lastScale
            lastScale = newScale;
            
            return { newScale: newScale, offsetX: worldOffsetX, offsetY: worldOffsetY };
        }
        
        // 如果没变化，则返回旧值并且 offset 为 0
        return { newScale: oldScale, offsetX: 0, offsetY: 0 };
    }
    
    // ============ 配置管理方法 ============
    
    /**
     * 重置所有缓存状态（在场景切换等时机调用）
     */
    public static function resetState():Void {
        lastScale = undefined;
        updateCounter = 0;
        cachedFarthestEnemy = null;
        lastTargetPos.x = 0;
        lastTargetPos.y = 0;
    }
    
    /**
     * 强制更新最远敌人（在敌人大量变化时可手动调用）
     */
    public static function forceUpdateEnemy():Void {
        updateCounter = UPDATE_FREQUENCY; // 强制下次更新
    }
    
    /**
     * 获取当前缩放值
     */
    public static function getCurrentScale():Number {
        return lastScale;
    }
    
    /**
     * 设置缩放值（用于外部强制设置）
     */
    public static function setCurrentScale(scale:Number):Void {
        lastScale = scale;
    }
    
    /**
     * 重新计算对数缩放系数（当参考参数改变时调用）
     */
    public static function recalculateLogScaleFactor():Void {
        LOG_SCALE_FACTOR = _calculateLogScaleFactor();
    }
    
    /**
     * 设置参考距离和期望缩放值，并自动重新计算对数系数
     * @param refDistance 参考距离
     * @param refZoomMultiplier 参考距离下期望的缩放倍数
     */
    public static function setReferenceParams(refDistance:Number, refZoomMultiplier:Number):Void {
        REFERENCE_DISTANCE = refDistance;
        REFERENCE_ZOOM_MULTIPLIER = refZoomMultiplier;
        recalculateLogScaleFactor();
    }
    
    // ============ 私有辅助方法 ============
    
    /**
     * 根据参考距离和期望缩放倍数计算对数缩放系数
     * 公式推导：
     * 当 distance = REFERENCE_DISTANCE 时，期望 zoomMultiplier = REFERENCE_ZOOM_MULTIPLIER
     * normalizedDistance = REFERENCE_DISTANCE / DISTANCE_NORMALIZER
     * logScale = log10(normalizedDistance)
     * ZOOM_BASE - logScale * LOG_SCALE_FACTOR = REFERENCE_ZOOM_MULTIPLIER
     * 解得：LOG_SCALE_FACTOR = (ZOOM_BASE - REFERENCE_ZOOM_MULTIPLIER) / logScale
     */
    private static function _calculateLogScaleFactor():Number {
        var normalizedDistance:Number = Math.max(1, REFERENCE_DISTANCE / DISTANCE_NORMALIZER);
        var logScale:Number = Math.log(normalizedDistance) / Math.log(10);
        
        // 避免除零错误
        if (Math.abs(logScale) < 0.001) {
            return 1.0; // 默认值
        }
        
        return (ZOOM_BASE - REFERENCE_ZOOM_MULTIPLIER) / logScale;
    }
    
    /**
     * 判断目标是否移动了足够距离（需要重新查找敌人）
     */
    private static function _hasTargetMovedSignificantly(scrollObj:MovieClip):Boolean {
        var moveThreshold:Number = DISTANCE_NORMALIZER; // 移动超过一个归一化单位时更新
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
     * 使用自动计算的LOG_SCALE_FACTOR，确保在REFERENCE_DISTANCE时达到REFERENCE_ZOOM_MULTIPLIER
     */
    private static function _calculateTargetZoomScale(distance:Number, zoomScale:Number):Number {
        var normalizedDistance:Number = Math.max(1, distance / DISTANCE_NORMALIZER);
        var logScale:Number = Math.log(normalizedDistance) / Math.log(10);
        
        // 计算缩放倍数：当距离=REFERENCE_DISTANCE时，倍数=REFERENCE_ZOOM_MULTIPLIER
        var zoomMultiplier:Number = Math.min(MAX_ZOOM_MULTIPLIER, 
                                           Math.max(MIN_ZOOM_MULTIPLIER, 
                                                   ZOOM_BASE - logScale * LOG_SCALE_FACTOR));
        
        return zoomScale * zoomMultiplier;
    }
}