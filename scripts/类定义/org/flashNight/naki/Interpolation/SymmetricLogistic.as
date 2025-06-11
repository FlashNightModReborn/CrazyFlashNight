/**
 * SymmetricLogistic.as - 对称Logistic曲线拟合算法（通用版）
 * 
 * 路径：org.flashNight.naki.Interpolation.SymmetricLogistic
 * 
 * 功能：
 *  1. 提供基于约束点的对称Logistic曲线自动拟合
 *  2. 支持任意数量的约束点（最少2个）
 *  3. 连续平滑的数值映射，消除阶梯式跳跃
 *  4. 高性能缓存机制，避免重复计算
 * 
 * 数学原理：
 *  Logistic函数：f(x) = ymin + (ymax-ymin) / (1 + e^(k*(x-x0)))
 *  - ymin/ymax：函数的渐近线（最小值/最大值）
 *  - k：斜率参数（控制过渡陡峭程度）
 *  - x0：中心点参数（曲线拐点位置）
 * 
 * 约束拟合：
 *  给定约束点 (x1,y1) 和 (x2,y2)，自动计算 k 和 x0：
 *  - g1 = (y1-ymin)/(ymax-ymin), g2 = (y2-ymin)/(ymax-ymin)
 *  - k = ln((1-g2)/g2 / (1-g1)/g1) / (x2-x1)
 *  - x0 = x1 - ln((1-g1)/g1) / k
 * 
 * 使用场景：
 *  - 游戏难度曲线调整（根据玩家等级/分数）
 *  - UI动画缓动函数（非线性过渡）
 *  - 数值平衡系统（属性随条件平滑变化）
 *  - 相机系统缩放控制（敌人数量 -> 缩放限制）
 *  - 音频系统音量控制（距离 -> 音量衰减）
 * 
 * 性能特性：
 *  - 参数计算缓存：相同配置重复使用，避免重复计算
 *  - 轻量级设计：无状态静态方法，内存开销最小
 *  - 数值稳定性：包含边界检查和除零保护
 */
class org.flashNight.naki.Interpolation.SymmetricLogistic {
    
    // ============ 数值计算常量 ============
    
    /** 浮点数比较精度阈值（防止除零和数值不稳定） */
    private static var EPSILON:Number = 1e-10;
    
    /** 默认斜率值（当计算失败时的后备值） */
    private static var DEFAULT_SLOPE:Number = 1.0;
    
    /** 指数函数裁剪阈值（防止溢出） */
    private static var EXP_CLAMP_MAX:Number = 700;
    private static var EXP_CLAMP_MIN:Number = -700;

    // ============ 参数缓存机制 ============
    
    /** 参数缓存表（避免重复计算相同配置的k和x0） */
    private static var paramCache:Object = {};
    
    /** 缓存键生成盐值（确保键的唯一性） */
    private static var CACHE_SALT:String = "logistic_";

    // ============ 核心公共接口 ============

    /**
     * 计算Logistic曲线在指定点的函数值
     * 
     * @param x       输入值（自变量）
     * @param yMin    函数最小值（下渐近线）
     * @param yMax    函数最大值（上渐近线）
     * @param slope   斜率参数k（控制过渡陡峭程度）
     * @param pivot   中心点参数x0（曲线拐点位置）
     * @return        计算得出的函数值 f(x)
     */
    public static function evaluate(
        x:Number, 
        yMin:Number, 
        yMax:Number, 
        slope:Number, 
        pivot:Number
    ):Number {
        // 计算指数项，并进行裁剪防止溢出
        var exponent:Number = slope * (x - pivot);
        exponent = Math.max(EXP_CLAMP_MIN, Math.min(EXP_CLAMP_MAX, exponent));
        
        // Logistic函数计算
        var expTerm:Number = Math.exp(exponent);
        return yMin + (yMax - yMin) / (1 + expTerm);
    }

    /**
     * 基于两个约束点自动拟合Logistic曲线参数
     * 
     * @param x1      约束点1的x坐标
     * @param y1      约束点1的y坐标
     * @param x2      约束点2的x坐标  
     * @param y2      约束点2的y坐标
     * @param yMin    函数最小值（下渐近线）
     * @param yMax    函数最大值（上渐近线）
     * @return Object { slope:Number, pivot:Number, isValid:Boolean }
     *                slope: 计算得出的斜率参数
     *                pivot: 计算得出的中心点参数
     *                isValid: 参数是否有效（false表示计算失败）
     */
    public static function fitFromTwoPoints(
        x1:Number, y1:Number,
        x2:Number, y2:Number, 
        yMin:Number, yMax:Number
    ):Object {
        // 生成缓存键
        var cacheKey:String = _generateCacheKey(x1, y1, x2, y2, yMin, yMax);
        
        // 检查缓存
        if (paramCache[cacheKey]) {
            return paramCache[cacheKey];
        }

        // 参数验证
        var validation:Object = _validateFitParams(x1, y1, x2, y2, yMin, yMax);
        if (!validation.isValid) {
            var result:Object = { 
                slope: DEFAULT_SLOPE, 
                pivot: (x1 + x2) / 2, 
                isValid: false,
                errorMsg: validation.errorMsg
            };
            paramCache[cacheKey] = result;
            return result;
        }

        // 计算归一化变量
        var range:Number = yMax - yMin;
        var g1:Number = (y1 - yMin) / range;
        var g2:Number = (y2 - yMin) / range;

        // 计算指数项
        var exp1:Number = (1 - g1) / g1;
        var exp2:Number = (1 - g2) / g2;

        // 计算斜率参数
        var slope:Number;
        var dx:Number = x2 - x1;
        if (Math.abs(dx) < EPSILON) {
            slope = DEFAULT_SLOPE;
        } else {
            slope = Math.log(exp2 / exp1) / dx;
        }

        // 计算中心点参数
        var pivot:Number;
        if (Math.abs(slope) < EPSILON) {
            pivot = (x1 + x2) / 2;
        } else {
            pivot = x1 - Math.log(exp1) / slope;
        }

        // 验证结果并缓存
        var finalResult:Object = { 
            slope: slope, 
            pivot: pivot, 
            isValid: _validateResult(slope, pivot),
            errorMsg: null
        };
        
        paramCache[cacheKey] = finalResult;
        return finalResult;
    }

    /**
     * 组合方法：拟合参数并立即计算函数值
     * 这是最常用的便捷接口
     * 
     * @param x       要计算的输入值
     * @param x1      约束点1的x坐标
     * @param y1      约束点1的y坐标
     * @param x2      约束点2的x坐标
     * @param y2      约束点2的y坐标
     * @param yMin    函数最小值
     * @param yMax    函数最大值
     * @return        计算得出的函数值
     */
    public static function fitAndEvaluate(
        x:Number,
        x1:Number, y1:Number,
        x2:Number, y2:Number,
        yMin:Number, yMax:Number
    ):Number {
        var params:Object = fitFromTwoPoints(x1, y1, x2, y2, yMin, yMax);
        
        if (!params.isValid) {
            // 拟合失败时使用线性插值作为后备
            return _linearFallback(x, x1, y1, x2, y2, yMin, yMax);
        }
        
        return evaluate(x, yMin, yMax, params.slope, params.pivot);
    }

    /**
     * 使用预计算参数直接计算函数值（高性能版本）
     * 适用于LogisticPresets等需要频繁调用的场景
     * 
     * @param x       输入值（自变量）
     * @param params  预计算的参数对象 {slope:Number, pivot:Number}
     * @param yMin    函数最小值（下渐近线）
     * @param yMax    函数最大值（上渐近线）
     * @return        计算得出的函数值 f(x)
     */
    public static function evaluateWithParams(
        x:Number,
        params:Object,
        yMin:Number,
        yMax:Number
    ):Number {
        // 直接使用预计算的参数，跳过拟合过程
        return evaluate(x, yMin, yMax, params.slope, params.pivot);
    }

    /**
     * 多点拟合版本：使用多个约束点进行最佳拟合
     * 目前实现选择中间两个最有代表性的点进行拟合
     * 
     * @param x               要计算的输入值
     * @param constraintPoints Array of {x:Number, y:Number}
     * @param yMin            函数最小值
     * @param yMax            函数最大值
     * @return                计算得出的函数值
     */
    public static function fitAndEvaluateMultiPoint(
        x:Number,
        constraintPoints:Array,
        yMin:Number,
        yMax:Number
    ):Number {
        if (constraintPoints.length < 2) {
            return (yMin + yMax) / 2; // 默认中值
        }
        
        if (constraintPoints.length == 2) {
            var p1:Object = constraintPoints[0];
            var p2:Object = constraintPoints[1];
            return fitAndEvaluate(x, p1.x, p1.y, p2.x, p2.y, yMin, yMax);
        }

        // 多点情况：选择最有代表性的两个点
        var selectedPoints:Array = _selectRepresentativePoints(constraintPoints);
        var sp1:Object = selectedPoints[0];
        var sp2:Object = selectedPoints[1];
        
        return fitAndEvaluate(x, sp1.x, sp1.y, sp2.x, sp2.y, yMin, yMax);
    }

    // ============ 缓存管理接口 ============

    /**
     * 清空参数缓存（在内存紧张或需要重新计算时调用）
     */
    public static function clearCache():Void {
        paramCache = {};
    }

    /**
     * 获取当前缓存大小（用于监控内存使用）
     */
    public static function getCacheSize():Number {
        var count:Number = 0;
        for (var key:String in paramCache) {
            count++;
        }
        return count;
    }

    /**
     * 预计算并缓存常用参数组合（用于性能优化）
     */
    public static function precomputeCommonParams():Void {
        // 游戏中常见的参数组合
        var commonConfigs:Array = [
            // 相机缩放：敌人数量3-8 -> 缩放1.5-1.2，范围1.0-2.0
            {x1: 3, y1: 1.5, x2: 8, y2: 1.2, yMin: 1.0, yMax: 2.0},
            // 难度曲线：等级1-100 -> 难度0.1-0.9，范围0.05-1.0  
            {x1: 1, y1: 0.1, x2: 100, y2: 0.9, yMin: 0.05, yMax: 1.0},
            // 音量衰减：距离100-1000 -> 音量0.8-0.2，范围0.0-1.0
            {x1: 100, y1: 0.8, x2: 1000, y2: 0.2, yMin: 0.0, yMax: 1.0}
        ];

        for (var i:Number = 0; i < commonConfigs.length; i++) {
            var config:Object = commonConfigs[i];
            fitFromTwoPoints(
                config.x1, config.y1, 
                config.x2, config.y2, 
                config.yMin, config.yMax
            );
        }
    }

    // ============ 私有辅助方法 ============

    /**
     * 生成缓存键
     */
    private static function _generateCacheKey(
        x1:Number, y1:Number, x2:Number, y2:Number, 
        yMin:Number, yMax:Number
    ):String {
        return CACHE_SALT + x1 + "_" + y1 + "_" + x2 + "_" + y2 + "_" + yMin + "_" + yMax;
    }

    /**
     * 验证拟合参数的有效性
     */
    private static function _validateFitParams(
        x1:Number, y1:Number, x2:Number, y2:Number,
        yMin:Number, yMax:Number
    ):Object {
        // 检查NaN
        if (isNaN(x1) || isNaN(y1) || isNaN(x2) || isNaN(y2) || isNaN(yMin) || isNaN(yMax)) {
            return { isValid: false, errorMsg: "Contains NaN values" };
        }

        // 检查范围有效性
        if (Math.abs(yMax - yMin) < EPSILON) {
            return { isValid: false, errorMsg: "yMax and yMin are too close" };
        }

        // 检查约束点是否在范围内
        if (y1 < yMin - EPSILON || y1 > yMax + EPSILON || 
            y2 < yMin - EPSILON || y2 > yMax + EPSILON) {
            return { isValid: false, errorMsg: "Constraint points outside range" };
        }

        return { isValid: true, errorMsg: null };
    }

    /**
     * 验证计算结果的有效性
     */
    private static function _validateResult(slope:Number, pivot:Number):Boolean {
        return !isNaN(slope) && !isNaN(pivot) && 
               Math.abs(slope) < 1000 && Math.abs(pivot) < 1000000;
    }

    /**
     * 线性插值后备方案（当Logistic拟合失败时使用）
     */
    private static function _linearFallback(
        x:Number, x1:Number, y1:Number, x2:Number, y2:Number,
        yMin:Number, yMax:Number
    ):Number {
        if (Math.abs(x2 - x1) < EPSILON) {
            return (y1 + y2) / 2;
        }
        
        var t:Number = (x - x1) / (x2 - x1);
        t = Math.max(0, Math.min(1, t)); // 约束到[0,1]
        var result:Number = y1 + t * (y2 - y1);
        
        // 确保结果在范围内
        return Math.max(yMin, Math.min(yMax, result));
    }

    /**
     * 从多个约束点中选择最有代表性的两个点
     */
    private static function _selectRepresentativePoints(points:Array):Array {
        // 按x坐标排序
        points.sort(_compareByX);
        
        // 选择x范围最大的两个点，确保拟合效果最好
        var first:Object = points[0];
        var last:Object = points[points.length - 1];
        
        return [first, last];
    }

    /**
     * 按x坐标比较函数（用于数组排序）
     */
    private static function _compareByX(a:Object, b:Object):Number {
        if (a.x < b.x) return -1;
        if (a.x > b.x) return 1;
        return 0;
    }
}