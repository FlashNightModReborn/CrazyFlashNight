import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.neur.Controller.SimpleKalmanFilter1D;

/**
 * ZoomController.as - 缩放控制组件（卡尔曼滤波平滑版 + 对称 Logistic 拟合版）
 *
 * 负责：
 *  1. 计算基于目标与最远敌人距离的动态缩放
 *  2. 根据敌人数量动态调整缩放限制（使用对称 Logistic 曲线平滑拟合）
 *  3. 使用卡尔曼滤波器实现平滑缩放过渡
 *  4. 处理缩放补偿逻辑（保持 scrollObj 在屏幕上位置恒定）
 *  5. 管理并更新缩放状态
 *
 * 升级特性：
 *  - 卡尔曼滤波：双重滤波确保平滑过渡，防止突变
 *    * 敌人数量滤波：减少检测噪声导致的缩放限制跳跃
 *    * 缩放值滤波：确保最终缩放值的平滑过渡
 *  - 对称 Logistic 曲线：替代阶梯式 if-else，提供连续平滑的缩放过渡
 *    * 自动参数拟合：根据设定的关键点自动计算曲线参数
 *    * 数学连续性：消除缩放跳跃，提供自然的视觉体验
 *  - 性能优化：滤波计算与数据更新同步，避免每帧计算开销
 *  - 敌人数量感知：根据当前敌人数量动态调整缩放上限
 *  - 配置化：所有魔数抽取为静态属性，便于调整和测试
 *
 * 敌人数量缩放策略（Logistic 曲线拟合）：
 *  - 敌人数量 > 8：  缩放限制趋近 1.0 (不放大)
 *  - 敌人数量 5-8：  缩放限制平滑过渡 1.0-1.2
 *  - 敌人数量 3-5：  缩放限制平滑过渡 1.0-1.5  
 *  - 敌人数量 < 3：  缩放限制趋近 2.0 (最大放大)
 *  - 所有过渡均为连续平滑，无跳跃点
 *
 * 数学原理：
 *  - Logistic 函数：f(x) = ymin + (ymax-ymin) / (1 + e^(k*(x-x0)))
 *  - 参数自动拟合：通过约束点 (n1,z1) 和 (n2,z2) 反推 k 和 x0
 *  - 斜率计算：k = ln((1-g2)/g2 / (1-g1)/g1) / (n2-n1)
 *  - 中心点计算：x0 = n1 - ln((1-g1)/g1) / k
 *  - 其中 g1 = (z1-ymin)/(ymax-ymin), g2 = (z2-ymin)/(ymax-ymin)
 *
 * 卡尔曼滤波参数说明：
 *  - 敌人数量滤波：轻度滤波，快速响应但减少噪声
 *  - 缩放值滤波：中度滤波，确保视觉平滑但保持响应性
 *  - 性能策略：滤波计算仅在数据更新时执行，非更新帧使用缓存结果
 *    避免AS2环境下每帧滤波的性能开销
 *
 * 使用示例：
 *   // 调整敌人数量阈值和对应缩放限制
 *   ZoomController.setEnemyCountThresholds(10, 6, 2);
 *   ZoomController.setZoomLimitsByEnemyCount(1.0, 1.3, 1.7, 2.5);
 *   
 *   // 调整卡尔曼滤波参数
 *   ZoomController.setKalmanParams(0.1, 0.5, 0.01, 0.1);
 *   
 *   // 重置滤波器（场景切换时）
 *   ZoomController.resetFilters();
 *   
 *   // 强制更新敌人检测（敌人大量变化时）
 *   ZoomController.forceUpdateEnemy();
 */
class org.flashNight.arki.camera.ZoomController {
    
    // ============ 距离和缩放计算参数 ============
    
    /** 距离归一化除数（用于将像素距离转换为标准化单位） */
    public static var DISTANCE_NORMALIZER:Number = 100;
    
    /** 参考距离（用于计算对数缩放系数的基准距离） */
    public static var REFERENCE_DISTANCE:Number = 800;
    
    /** 参考距离下期望的缩放倍数（用于校准缩放曲线） */
    public static var REFERENCE_ZOOM_MULTIPLIER:Number = 0.89;
    
    /** 缩放计算基数（对数缩放公式中的基础系数） */
    public static var ZOOM_BASE:Number = 2;
    
    /** 对数缩放系数（根据参考参数自动计算，控制距离-缩放的响应曲线） */
    public static var LOG_SCALE_FACTOR:Number = _calculateLogScaleFactor();
    
    /** 最小缩放倍数（防止缩放过小导致目标不可见） */
    public static var MIN_ZOOM_MULTIPLIER:Number = 1;
    
    /** 基础最大缩放倍数（作为缩放上限的后备值） */
    public static var BASE_MAX_ZOOM_MULTIPLIER:Number = 2.0;
    
    /** 缩放变化阈值（低于此值不应用缩放变化，避免微小抖动） */
    public static var SCALE_CHANGE_THRESHOLD:Number = 0.005;
    
    /** 查找最远敌人的时间帧数限制（防止搜索过久影响性能） */
    public static var ENEMY_SEARCH_LIMIT:Number = 5;
    
    /** 默认距离值（当找不到敌人时使用，表示"很远"） */
    public static var DEFAULT_DISTANCE:Number = 99999;
    
    /** 性能优化：每多少次调用更新一次最远敌人和敌人数量（降低计算频率） */
    public static var UPDATE_FREQUENCY:Number = 60;

    // ============ 卡尔曼滤波参数 ============
    
    /** 敌人数量滤波器 - 过程噪声 Q（系统内在变化的不确定性） */
    public static var ENEMY_COUNT_PROCESS_NOISE:Number = 0.1;
    
    /** 敌人数量滤波器 - 测量噪声 R（敌人检测的观测不确定性） */
    public static var ENEMY_COUNT_MEASUREMENT_NOISE:Number = 0.5;
    
    /** 缩放值滤波器 - 过程噪声 Q（缩放系统内在变化的不确定性） */
    public static var ZOOM_SCALE_PROCESS_NOISE:Number = 0.01;
    
    /** 缩放值滤波器 - 测量噪声 R（缩放计算的观测不确定性） */
    public static var ZOOM_SCALE_MEASUREMENT_NOISE:Number = 0.1;

    // ============ 敌人数量阈值配置（Logistic 拟合约束点） ============
    
    /** 敌人数量阈值1：超过此数量时使用最低缩放（Logistic 曲线右端约束） */
    public static var ENEMY_COUNT_HIGH_THRESHOLD:Number = 8;
    
    /** 敌人数量阈值2：中等敌人数量的下限（Logistic 曲线中段约束点1） */
    public static var ENEMY_COUNT_MID_THRESHOLD:Number = 5;
    
    /** 敌人数量阈值3：少量敌人数量的下限（Logistic 曲线中段约束点2） */
    public static var ENEMY_COUNT_LOW_THRESHOLD:Number = 3;
    
    /** 敌人数量很多时的最大缩放倍数 (>8个敌人，Logistic 曲线下渐近线) */
    public static var MAX_ZOOM_HIGH_ENEMY:Number = 1.0;
    
    /** 敌人数量中等时的最大缩放倍数 (5-8个敌人，约束点1的目标值) */
    public static var MAX_ZOOM_MID_ENEMY:Number = 1.2;
    
    /** 敌人数量较少时的最大缩放倍数 (3-5个敌人，约束点2的目标值) */
    public static var MAX_ZOOM_LOW_ENEMY:Number = 1.5;
    
    /** 敌人数量很少时的最大缩放倍数 (<3个敌人，Logistic 曲线上渐近线) */
    public static var MAX_ZOOM_VERY_LOW_ENEMY:Number = 2.0;

    // ============ 对称 Logistic 拟合参数（自动计算） ============
    
    /** Logistic 曲线斜率参数（控制过渡的陡峭程度，根据约束点自动计算） */
    public static var LOGI_SLOPE:Number = _calculateLogiSlope();
    
    /** Logistic 曲线中心点参数（曲线拐点位置，根据约束点自动计算） */
    public static var LOGI_PIVOT:Number = _calculateLogiPivot();

    // ============ 内部状态（静态属性） ============
    
    /** 当前缩放值（相对于 1.0 的倍数） */
    private static var lastScale:Number;
    
    /** 调用计数器（用于控制更新频率） */
    private static var updateCounter:Number = 0;
    
    /** 缓存的最远敌人信息（避免每帧重新搜索） */
    private static var cachedFarthestEnemy:Object;
    
    /** 缓存的原始敌人数量（避免每帧重新计算） */
    private static var cachedRawEnemyCount:Number = 0;
    
    /** 当前动态最大缩放倍数（由 Logistic 曲线计算得出） */
    private static var currentMaxZoomMultiplier:Number = BASE_MAX_ZOOM_MULTIPLIER;
    
    /** 最后一次查找敌人时的目标位置（用于判断是否需要强制更新） */
    private static var lastTargetPos:Object = { x: 0, y: 0 };
    
    /** 敌人数量卡尔曼滤波器实例 */
    private static var enemyCountFilter:SimpleKalmanFilter1D;
    
    /** 缩放值卡尔曼滤波器实例 */
    private static var zoomScaleFilter:SimpleKalmanFilter1D;
    
    /** 滤波器是否已初始化标志 */
    private static var filtersInitialized:Boolean = false;

    // ============ 核心公共方法 ============

    /**
     * 根据 scrollObj 与最远敌人的距离以及敌人数量，计算 targetZoomScale，并做卡尔曼滤波平滑，
     * 如果缩放发生显著变化（阈值可配置），则：
     *   1) 记录缩放前后 scrollObj 在屏幕上的坐标
     *   2) 更新 gameWorld 与 bgLayer 的 _xscale/_yscale
     *   3) 计算并返回 worldOffset，用于后续坐标补偿
     *
     * 核心流程：
     *   1. 性能优化检查：判断是否需要重新计算敌人数据
     *   2. 敌人检测：查找最远敌人和敌人总数
     *   3. 距离计算：计算目标到最远敌人的距离
     *   4. 缩放计算：基于距离计算目标缩放值
     *   5. 卡尔曼滤波：对敌人数量和缩放值进行平滑滤波
     *   6. Logistic 拟合：根据滤波后的敌人数量计算最大缩放限制
     *   7. 缓动应用：轻度缓动最终缩放值
     *   8. 坐标补偿：如果缩放改变，计算并返回位置补偿量
     *
     * @param scrollObj   要跟踪的目标 MovieClip（通常是玩家角色）
     * @param gameWorld   全局世界 MovieClip（会直接修改其 _xscale/_yscale）
     * @param bgLayer     "天空盒"根节点 MovieClip（会直接修改其 _xscale/_yscale）
     * @param easeFactor  缓动系数（越大越平滑，但与卡尔曼滤波配合使用时可以设置较小值）
     * @param zoomScale   缩放基数（通常为相机的基础缩放值）
     * @return Object     { newScale:Number, offsetX:Number, offsetY:Number, enemyCount:Number, filteredEnemyCount:Number, maxZoom:Number }
     *                    newScale：本次最终缩放（相对于 1.0 的倍数）
     *                    offsetX/offsetY：应用于 world 坐标的补偿量（像素）
     *                    enemyCount：原始敌人数量（未滤波）
     *                    filteredEnemyCount：卡尔曼滤波后的敌人数量
     *                    maxZoom：当前最大缩放限制（由 Logistic 曲线计算）
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
        var shouldUpdate:Boolean = updateCounter >= UPDATE_FREQUENCY || 
                                  !cachedFarthestEnemy || 
                                  _hasTargetMovedSignificantly(scrollObj);
        
        var filteredEnemyCount:Number;
        var filteredZoomScale:Number;
        
        if (shouldUpdate) {
            // 2) 更新敌人数据：查找最远敌人和敌人总数
            cachedFarthestEnemy = TargetCacheManager.findFarthestEnemy(scrollObj, ENEMY_SEARCH_LIMIT);
            cachedRawEnemyCount = TargetCacheManager.getEnemyCount(scrollObj, ENEMY_SEARCH_LIMIT);
            
            // 3) 计算距离和目标缩放
            var distance:Number = _calculateDistance(scrollObj, cachedFarthestEnemy);
            var targetZoom:Number = _calculateTargetZoomScale(distance, zoomScale);

            // 4) 卡尔曼滤波：仅在数据更新时进行计算
            enemyCountFilter.predict();
            filteredEnemyCount = enemyCountFilter.update(cachedRawEnemyCount);
            
            zoomScaleFilter.predict();
            filteredZoomScale = zoomScaleFilter.update(targetZoom);

            // 5) 使用 Logistic 曲线计算动态最大缩放限制
            currentMaxZoomMultiplier = _calculateMaxZoomByEnemyCount(filteredEnemyCount);
            
            // 6) 重置计数器和位置缓存
            updateCounter = 0;
            lastTargetPos.x = scrollObj._x;
            lastTargetPos.y = scrollObj._y;
        } else {
            // 7) 非更新帧：直接使用缓存的滤波结果，避免重复计算
            filteredEnemyCount = enemyCountFilter.getEstimate();
            filteredZoomScale = zoomScaleFilter.getEstimate();
        }

        // 8) 初始化 lastScale
        if (lastScale == undefined) {
            lastScale = filteredZoomScale;
        }
        
        var oldScale:Number = lastScale;
        
        // 9) 轻度缓动（因为已有卡尔曼滤波，缓动可以更激进）
        var newScale:Number = oldScale + (filteredZoomScale - oldScale) / Math.max(1, easeFactor * 0.5);
        
        // 10) 判断是否需要真正更新缩放
        if (Math.abs(newScale - oldScale) > SCALE_CHANGE_THRESHOLD) {
            // 10.1) 记录缩放前 scrollObj 在屏幕上的坐标
            var prePt:Object = { x: 0, y: 0 };
            scrollObj.localToGlobal(prePt);
            
            // 10.2) 应用缩放到 gameWorld 与 bgLayer
            var pct:Number = newScale * 100;
            gameWorld._xscale = gameWorld._yscale = pct;
            bgLayer._xscale = bgLayer._yscale = pct;
            
            // 10.3) 记录缩放后 scrollObj 在屏幕上的坐标
            var postPt:Object = { x: 0, y: 0 };
            scrollObj.localToGlobal(postPt);
            
            // 10.4) 计算 worldOffset（保持 scrollObj 在屏幕上的视觉位置不变）
            var offX:Number = prePt.x - postPt.x;
            var offY:Number = prePt.y - postPt.y;
            
            // 10.5) 更新 lastScale
            lastScale = newScale;
            
            return { 
                newScale: newScale, 
                offsetX: offX, 
                offsetY: offY,
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

    // ============ 状态管理方法 ============

    /**
     * 重置所有缓存状态和滤波器（在场景切换等时机调用）
     * 清理所有内部状态，确保新场景从干净状态开始
     */
    public static function resetState():Void {
        lastScale = undefined;
        updateCounter = 0;
        cachedFarthestEnemy = null;
        cachedRawEnemyCount = 0;
        currentMaxZoomMultiplier = BASE_MAX_ZOOM_MULTIPLIER;
        lastTargetPos = { x: 0, y: 0 };
        resetFilters();
    }

    /**
     * 重置卡尔曼滤波器（保持其他状态不变）
     * 适用于需要重新校准滤波器但保持配置的场景
     */
    public static function resetFilters():Void {
        filtersInitialized = false;
        enemyCountFilter = null;
        zoomScaleFilter = null;
    }

    /**
     * 强制更新最远敌人和敌人数量（在敌人大量变化时可手动调用）
     * 跳过性能优化的更新频率限制，立即重新检测敌人
     */
    public static function forceUpdateEnemy():Void {
        updateCounter = UPDATE_FREQUENCY;
    }

    // ============ 配置管理方法 ============

    /**
     * 设置敌人数量阈值，并自动重新计算 Logistic 曲线参数
     * 这些阈值用作 Logistic 曲线的约束点，影响缩放过渡的形状
     * 
     * @param highT  高阈值（敌人很多时的分界点，通常 >8）
     * @param midT   中阈值（中等敌人数量，通常 5-8）
     * @param lowT   低阈值（少量敌人数量，通常 3-5）
     */
    public static function setEnemyCountThresholds(highT:Number, midT:Number, lowT:Number):Void {
        ENEMY_COUNT_HIGH_THRESHOLD = highT;
        ENEMY_COUNT_MID_THRESHOLD = midT;
        ENEMY_COUNT_LOW_THRESHOLD = lowT;
        _recalculateLogisticParams();
    }

    /**
     * 设置不同敌人数量下的缩放上限，并自动重新计算 Logistic 曲线参数
     * 这些值决定了 Logistic 曲线的渐近线和约束点目标值
     * 
     * @param highZ     敌人很多时的最大缩放（通常 1.0，不放大）
     * @param midZ      敌人中等时的最大缩放（通常 1.2）
     * @param lowZ      敌人较少时的最大缩放（通常 1.5）
     * @param veryLowZ  敌人很少时的最大缩放（通常 2.0，最大放大）
     */
    public static function setZoomLimitsByEnemyCount(highZ:Number, midZ:Number, lowZ:Number, veryLowZ:Number):Void {
        MAX_ZOOM_HIGH_ENEMY = highZ;
        MAX_ZOOM_MID_ENEMY = midZ;
        MAX_ZOOM_LOW_ENEMY = lowZ;
        MAX_ZOOM_VERY_LOW_ENEMY = veryLowZ;
        _recalculateLogisticParams();
    }

    /**
     * 设置卡尔曼滤波参数，用于调节平滑程度和响应速度
     * 
     * @param eQ  敌人数量滤波器过程噪声（越大越信任新观测，响应越快）
     * @param eR  敌人数量滤波器测量噪声（越大越不信任观测，平滑越强）
     * @param zQ  缩放值滤波器过程噪声
     * @param zR  缩放值滤波器测量噪声
     */
    public static function setKalmanParams(eQ:Number, eR:Number, zQ:Number, zR:Number):Void {
        ENEMY_COUNT_PROCESS_NOISE = eQ;
        ENEMY_COUNT_MEASUREMENT_NOISE = eR;
        ZOOM_SCALE_PROCESS_NOISE = zQ;
        ZOOM_SCALE_MEASUREMENT_NOISE = zR;
        
        // 如果滤波器已初始化，更新其参数
        if (filtersInitialized) {
            enemyCountFilter.setProcessNoise(eQ);
            enemyCountFilter.setMeasurementNoise(eR);
            zoomScaleFilter.setProcessNoise(zQ);
            zoomScaleFilter.setMeasurementNoise(zR);
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

    /**
     * 获取 Logistic 曲线参数（用于调试和验证）
     */
    public static function getLogisticParams():Object {
        return {
            slope: LOGI_SLOPE,
            pivot: LOGI_PIVOT,
            enemyThresholds: [ENEMY_COUNT_LOW_THRESHOLD, ENEMY_COUNT_MID_THRESHOLD, ENEMY_COUNT_HIGH_THRESHOLD],
            zoomLimits: [MAX_ZOOM_VERY_LOW_ENEMY, MAX_ZOOM_LOW_ENEMY, MAX_ZOOM_MID_ENEMY, MAX_ZOOM_HIGH_ENEMY]
        };
    }

    /**
     * 测试 Logistic 曲线在指定敌人数量下的缩放值（用于调试）
     */
    public static function testLogisticCurve(enemyCount:Number):Number {
        return _calculateMaxZoomByEnemyCount(enemyCount);
    }

    // ============ 私有辅助方法 ============

    /**
     * 计算目标与最远敌人的曼哈顿距离
     * 使用曼哈顿距离而非欧几里得距离，减少开方运算的性能开销
     * 
     * @param s  目标对象（scrollObj）
     * @param e  敌人对象（可能为 null）
     * @return   曼哈顿距离，如果敌人不存在则返回默认大距离
     */
    private static function _calculateDistance(s:MovieClip, e:Object):Number {
        if (!e) return DEFAULT_DISTANCE;
        return Math.abs(s._x - e._x) + Math.abs(s._y - e._y);
    }

    /**
     * 基于距离计算目标缩放值
     * 使用对数缩放公式，距离越远缩放越小，提供自然的视野调节
     * 同时受当前最大缩放限制约束（由敌人数量 Logistic 曲线决定）
     * 
     * @param d  到最远敌人的距离
     * @param z  基础缩放值
     * @return   计算得出的目标缩放值
     */
    private static function _calculateTargetZoomScale(d:Number, z:Number):Number {
        // 归一化距离，避免对数运算的异常值
        var nd:Number = Math.max(1, d / DISTANCE_NORMALIZER);
        
        // 对数缩放计算
        var ls:Number = Math.log(nd) / Math.log(10);
        
        // 应用缩放公式并限制在合理范围内
        var mu:Number = Math.min(currentMaxZoomMultiplier,
            Math.max(MIN_ZOOM_MULTIPLIER, ZOOM_BASE - ls * LOG_SCALE_FACTOR));
        
        return z * mu;
    }

    /**
     * 判断目标是否移动了足够距离（需要重新查找敌人）
     * 避免目标小幅移动时频繁重新搜索敌人，优化性能
     * 
     * @param s  目标对象
     * @return   是否需要重新搜索敌人
     */
    private static function _hasTargetMovedSignificantly(s:MovieClip):Boolean {
        var dx:Number = Math.abs(s._x - lastTargetPos.x);
        var dy:Number = Math.abs(s._y - lastTargetPos.y);
        return (dx + dy) > DISTANCE_NORMALIZER;
    }

    /**
     * 初始化卡尔曼滤波器（如果尚未初始化）
     * 创建两个独立的滤波器实例，分别处理敌人数量和缩放值
     */
    private static function _initializeFiltersIfNeeded():Void {
        if (!filtersInitialized) {
            // 初始化敌人数量滤波器（初始估计为 0 个敌人）
            enemyCountFilter = new SimpleKalmanFilter1D(0, ENEMY_COUNT_PROCESS_NOISE, ENEMY_COUNT_MEASUREMENT_NOISE);
            
            // 初始化缩放值滤波器（初始估计为 1.0 倍缩放）
            zoomScaleFilter = new SimpleKalmanFilter1D(1.0, ZOOM_SCALE_PROCESS_NOISE, ZOOM_SCALE_MEASUREMENT_NOISE);
            
            filtersInitialized = true;
        }
    }

    // ============ Logistic 曲线计算方法 ============

    /**
     * 使用对称 Logistic 曲线计算基于敌人数量的最大缩放倍数
     * 
     * 数学公式：f(n) = ymin + (ymax - ymin) / (1 + e^(k*(n - x0)))
     * 其中：
     *   - n：敌人数量
     *   - ymin：最小缩放值 (MAX_ZOOM_HIGH_ENEMY)
     *   - ymax：最大缩放值 (MAX_ZOOM_VERY_LOW_ENEMY)
     *   - k：斜率参数 (LOGI_SLOPE)
     *   - x0：中心点参数 (LOGI_PIVOT)
     * 
     * 特性：
     *   - 敌人数量少时缩放大，敌人数量多时缩放小
     *   - 连续平滑过渡，无跳跃点
     *   - 参数自动拟合，确保通过设定的约束点
     * 
     * @param n  滤波后的敌人数量
     * @return   计算得出的最大缩放倍数
     */
    private static function _calculateMaxZoomByEnemyCount(n:Number):Number {
        // 对称 Logistic 曲线公式
        return MAX_ZOOM_HIGH_ENEMY +
               (MAX_ZOOM_VERY_LOW_ENEMY - MAX_ZOOM_HIGH_ENEMY) /
               (1 + Math.exp(LOGI_SLOPE * (n - LOGI_PIVOT)));
    }

    /**
     * 计算 Logistic 曲线的斜率参数
     * 
     * 数学推导：
     * 设约束点 (n1, z1) 和 (n2, z2)，其中：
     *   - n1 = ENEMY_COUNT_LOW_THRESHOLD, z1 = MAX_ZOOM_LOW_ENEMY
     *   - n2 = ENEMY_COUNT_MID_THRESHOLD, z2 = MAX_ZOOM_MID_ENEMY
     * 
     * 归一化变量：g1 = (z1-ymin)/(ymax-ymin), g2 = (z2-ymin)/(ymax-ymin)
     * 指数项：exp1 = (1-g1)/g1, exp2 = (1-g2)/g2
     * 斜率：k = ln(exp2/exp1) / (n2-n1)
     * 
     * @return  Logistic 曲线斜率参数
     */
    private static function _calculateLogiSlope():Number {
        var n1:Number = ENEMY_COUNT_LOW_THRESHOLD;
        var n2:Number = ENEMY_COUNT_MID_THRESHOLD;
        var m:Number = MAX_ZOOM_HIGH_ENEMY;
        var L:Number = MAX_ZOOM_VERY_LOW_ENEMY;
        var z1:Number = MAX_ZOOM_LOW_ENEMY;
        var z2:Number = MAX_ZOOM_MID_ENEMY;
        
        // 归一化到 [0,1] 区间
        var A:Number = L - m;
        var g1:Number = (z1 - m) / A;
        var g2:Number = (z2 - m) / A;
        
        // 计算指数项
        var exp1:Number = (1 - g1) / g1;
        var exp2:Number = (1 - g2) / g2;
        
        // 防止除零错误
        if (n2 - n1 == 0) return 1;
        
        // 计算斜率
        return Math.log(exp2 / exp1) / (n2 - n1);
    }

    /**
     * 计算 Logistic 曲线的中心点参数
     * 
     * 数学推导：
     * 从约束条件 f(n1) = z1 反推中心点：
     * z1 = m + A / (1 + e^(k*(n1-x0)))
     * 解得：x0 = n1 - ln((1-g1)/g1) / k
     * 
     * @return  Logistic 曲线中心点参数
     */
    private static function _calculateLogiPivot():Number {
        var n1:Number = ENEMY_COUNT_LOW_THRESHOLD;
        var m:Number = MAX_ZOOM_HIGH_ENEMY;
        var L:Number = MAX_ZOOM_VERY_LOW_ENEMY;
        var z1:Number = MAX_ZOOM_LOW_ENEMY;
        
        // 归一化
        var A:Number = L - m;
        var g1:Number = (z1 - m) / A;
        
        // 计算指数项
        var exp1:Number = (1 - g1) / g1;
        
        // 获取当前斜率
        var k:Number = LOGI_SLOPE;
        if (k == 0) return n1;
        
        // 计算中心点
        return n1 - Math.log(exp1) / k;
    }

    /**
     * 重新计算 Logistic 曲线参数
     * 当敌人数量阈值或缩放限制改变时调用，确保曲线参数与新配置匹配
     */
    private static function _recalculateLogisticParams():Void {
        LOGI_SLOPE = _calculateLogiSlope();
        LOGI_PIVOT = _calculateLogiPivot();
    }

    /**
     * 根据参考距离和期望缩放倍数计算对数缩放系数
     * 确保在参考距离处获得期望的缩放倍数，校准整个缩放曲线
     * 
     * @return  对数缩放系数
     */
    private static function _calculateLogScaleFactor():Number {
        var nd:Number = Math.max(1, REFERENCE_DISTANCE / DISTANCE_NORMALIZER);
        var ls:Number = Math.log(nd) / Math.log(10);
        
        // 防止除零
        if (Math.abs(ls) < 0.001) return 1;
        
        return (ZOOM_BASE - REFERENCE_ZOOM_MULTIPLIER) / ls;
    }
}