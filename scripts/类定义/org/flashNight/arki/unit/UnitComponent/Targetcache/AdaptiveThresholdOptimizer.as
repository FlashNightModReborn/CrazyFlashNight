// ============================================================================
// 自适应阈值优化器
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 封装所有与自适应阈值计算相关的逻辑
// 2. 根据单位分布特征动态调整查询阈值
// 3. 使用指数移动平均（EMA）平滑阈值变化
// 4. 提供参数调整接口，支持不同游戏场景的优化
// 
// 设计原则：
// - 单一职责：只负责阈值计算和优化
// - 无状态依赖：不依赖于具体的缓存实现
// - 高内聚：所有阈值相关的逻辑都在这个类中
// - 低耦合：通过简单的接口与其他组件交互
// ============================================================================

class org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizer {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * 当前全局阈值（单位：像素）
     * 用于判断缓存查询的有效性
     * 当本次查询位置与上次查询位置的差值在此阈值内时，可以使用缓存进行增量扫描
     */
    public static var _threshold:Number = 100;

    /**
     * 自适应阈值算法参数
     * 这些参数控制着阈值计算的行为和边界
     */
    private static var _params:Object = {
        // EMA平滑系数 (0.1 = 慢速适应, 0.3 = 快速适应)
        // 较小的值会让阈值变化更平滑，较大的值会让阈值更快响应当前状况
        alpha: 0.2,
        
        // 密度倍数因子 (平均间距的倍数)
        // 这个值决定了阈值相对于单位平均间距的比例
        // 较大的值会产生更大的阈值，允许更多的缓存复用
        densityFactor: 3.0,
        
        // 阈值边界限制
        // 防止阈值过小（导致缓存命中率低）或过大（导致扫描效率低）
        minThreshold: 30,
        maxThreshold: 300,
        
        // 历史平均密度（初始值）
        // 用于EMA计算的基准值
        avgDensity: 100
    };

    /**
     * 初始化标志，确保静态初始化只执行一次
     */
    private static var _initialized:Boolean = initialize();

    // ========================================================================
    // 初始化方法
    // ========================================================================
    
    /**
     * 静态初始化方法
     * 设置默认参数并准备优化器
     * @return {Boolean} 初始化是否成功
     */
    public static function initialize():Boolean {
        // 确保参数对象的完整性
        validateParams();
        return true;
    }

    /**
     * 验证并修正参数的有效性
     * 确保所有参数都在合理范围内
     * @private
     */
    private static function validateParams():Void {
        // 验证alpha参数
        if (isNaN(_params.alpha) || _params.alpha <= 0 || _params.alpha > 1) {
            _params.alpha = 0.2;
        }
        
        // 验证密度因子
        if (isNaN(_params.densityFactor) || _params.densityFactor <= 0) {
            _params.densityFactor = 3.0;
        }
        
        // 验证阈值边界
        if (isNaN(_params.minThreshold) || _params.minThreshold <= 0) {
            _params.minThreshold = 30;
        }
        if (isNaN(_params.maxThreshold) || _params.maxThreshold <= _params.minThreshold) {
            _params.maxThreshold = Math.max(_params.minThreshold * 10, 300);
        }
        
        // 验证平均密度
        if (isNaN(_params.avgDensity) || _params.avgDensity <= 0) {
            _params.avgDensity = 100;
        }
        
        // 验证当前阈值
        if (isNaN(_threshold) || _threshold < _params.minThreshold || _threshold > _params.maxThreshold) {
            _threshold = (_params.minThreshold + _params.maxThreshold) / 2;
        }
    }

    // ========================================================================
    // 核心优化方法
    // ========================================================================
    
    /**
     * 根据单位分布特征更新自适应阈值
     * 
     * 算法说明：
     * 1. 计算相邻单位的平均间距（密度指标）
     * 2. 使用指数移动平均（EMA）更新历史平均密度
     * 3. 根据密度计算新阈值：阈值 = 平均密度 × 密度因子
     * 4. 应用边界限制确保阈值在合理范围内
     * 
     * EMA公式：新平均值 = α × 当前值 + (1-α) × 历史平均值
     * 其中α是平滑系数，控制新数据的影响权重
     * 
     * @param {Array} leftValues - 已按left坐标升序排序的数值数组
     * @return {Number} 更新后的阈值
     */
    public static function updateThreshold(leftValues:Array):Number {
        var len:Number = leftValues.length;
        
        // 需要至少2个单位才能计算相邻间距
        if (len < 2) {
            return _threshold; // 保持当前阈值不变
        }

        // ===== 计算当前分布密度 =====
        var totalSpacing:Number = 0;
        var spacingCount:Number = 0;

        // 计算所有相邻单位的间距
        for (var i:Number = 1; i < len; i++) {
            var spacing:Number = leftValues[i] - leftValues[i - 1];
            // 只统计有效间距（排除重叠单位）
            if (spacing > 0) {
                totalSpacing += spacing;
                spacingCount++;
            }
        }

        // 如果没有有效间距，保持当前阈值不变
        if (spacingCount == 0) {
            return _threshold;
        }

        // 计算平均间距
        var currentDensity:Number = totalSpacing / spacingCount;

        // ===== 使用EMA更新历史平均密度 =====
        _params.avgDensity = _params.alpha * currentDensity + 
                           (1 - _params.alpha) * _params.avgDensity;

        // ===== 计算新阈值 =====
        var newThreshold:Number = _params.avgDensity * _params.densityFactor;

        // ===== 应用边界限制 =====
        newThreshold = applyThresholdBounds(newThreshold);

        // ===== 更新全局阈值 =====
        _threshold = newThreshold;

        return _threshold;
    }

    /**
     * 应用阈值边界限制
     * 确保阈值在合理的范围内
     * 
     * @param {Number} value - 待限制的阈值
     * @return {Number} 限制后的阈值
     * @private
     */
    private static function applyThresholdBounds(value:Number):Number {
        if (value < _params.minThreshold) {
            return _params.minThreshold;
        } else if (value > _params.maxThreshold) {
            return _params.maxThreshold;
        }
        return value;
    }

    // ========================================================================
    // 访问器方法
    // ========================================================================
    
    /**
     * 获取当前阈值
     * @return {Number} 当前的自适应阈值
     */
    public static function getThreshold():Number {
        return _threshold;
    }

    /**
     * 获取当前平均密度
     * @return {Number} 历史平均密度值
     */
    public static function getAvgDensity():Number {
        return _params.avgDensity;
    }

    /**
     * 获取所有参数的副本
     * @return {Object} 参数对象的副本（防止外部修改）
     */
    public static function getParams():Object {
        return {
            alpha: _params.alpha,
            densityFactor: _params.densityFactor,
            minThreshold: _params.minThreshold,
            maxThreshold: _params.maxThreshold,
            avgDensity: _params.avgDensity
        };
    }

    // ========================================================================
    // 参数配置方法
    // ========================================================================
    
    /**
     * 手动设置自适应参数
     * 允许根据不同游戏场景微调算法行为
     * 
     * 使用场景：
     * - 密集作战场景：可以减小densityFactor，提高缓存命中率
     * - 稀疏场景：可以增大densityFactor，减少不必要的缓存更新
     * - 快速变化场景：可以增大alpha，让阈值快速响应
     * - 稳定场景：可以减小alpha，保持阈值稳定
     * 
     * @param {Number} alpha - EMA平滑系数 (0.05-0.5)，控制响应速度
     * @param {Number} densityFactor - 密度倍数因子 (1.0-5.0)，控制阈值大小
     * @param {Number} minThreshold - 最小阈值限制
     * @param {Number} maxThreshold - 最大阈值限制
     * @return {Boolean} 设置是否成功
     */
    public static function setParams(
        alpha:Number,
        densityFactor:Number,
        minThreshold:Number,
        maxThreshold:Number
    ):Boolean {
        var changed:Boolean = false;

        // 更新alpha参数
        if (!isNaN(alpha) && alpha > 0 && alpha <= 1) {
            _params.alpha = alpha;
            changed = true;
        }

        // 更新密度因子
        if (!isNaN(densityFactor) && densityFactor > 0) {
            _params.densityFactor = densityFactor;
            changed = true;
        }

        // 更新最小阈值
        if (!isNaN(minThreshold) && minThreshold > 0) {
            _params.minThreshold = minThreshold;
            changed = true;
        }

        // 更新最大阈值（必须大于最小阈值）
        if (!isNaN(maxThreshold) && maxThreshold > _params.minThreshold) {
            _params.maxThreshold = maxThreshold;
            changed = true;
        }

        // 如果参数发生变化，重新验证并调整当前阈值
        if (changed) {
            validateParams();
            _threshold = applyThresholdBounds(_threshold);
        }

        return changed;
    }

    /**
     * 设置单个参数
     * 提供更细粒度的参数控制
     * 
     * @param {String} paramName - 参数名称
     * @param {Number} value - 参数值
     * @return {Boolean} 设置是否成功
     */
    public static function setParam(paramName:String, value:Number):Boolean {
        switch (paramName) {
            case "alpha":
                return setParams(value, _params.densityFactor, _params.minThreshold, _params.maxThreshold);
                
            case "densityFactor":
                return setParams(_params.alpha, value, _params.minThreshold, _params.maxThreshold);
                
            case "minThreshold":
                return setParams(_params.alpha, _params.densityFactor, value, _params.maxThreshold);
                
            case "maxThreshold":
                return setParams(_params.alpha, _params.densityFactor, _params.minThreshold, value);
                
            default:
                return false;
        }
    }

    // ========================================================================
    // 预设配置方法
    // ========================================================================
    
    /**
     * 应用预设的参数配置
     * 为常见游戏场景提供优化的参数组合
     * 
     * @param {String} presetName - 预设名称
     * @return {Boolean} 应用是否成功
     */
    public static function applyPreset(presetName:String):Boolean {
        switch (presetName) {
            case "dense": // 密集场景：单位很多且分布紧密
                return setParams(0.4, 1.5, 10, 100);
                
            case "sparse": // 稀疏场景：单位较少且分布稀疏
                return setParams(0.2, 3.0, 30, 200);
                
            case "dynamic": // 动态场景：单位分布经常变化
                return setParams(0.5, 2.0, 20, 150);
                
            case "stable": // 稳定场景：单位分布相对固定
                return setParams(0.1, 3.5, 40, 300);
                
            case "default": // 默认场景：平衡的参数设置
                return setParams(0.2, 3.0, 30, 300);
                
            default:
                return false;
        }
    }

    // ========================================================================
    // 重置方法
    // ========================================================================
    
    /**
     * 重置所有参数到默认值
     * 用于故障恢复或重新初始化
     */
    public static function reset():Void {
        applyPreset("default");
        _params.avgDensity = 100;
        _threshold = 100;
    }

    /**
     * 重置历史平均密度
     * 用于场景切换时清除历史数据的影响
     * 
     * @param {Number} newAvgDensity - 新的基准密度值（可选）
     */
    public static function resetAvgDensity(newAvgDensity:Number):Void {
        if (!isNaN(newAvgDensity) && newAvgDensity > 0) {
            _params.avgDensity = newAvgDensity;
        } else {
            _params.avgDensity = 100;
        }
    }

    // ========================================================================
    // 调试和监控方法
    // ========================================================================
    
    /**
     * 获取优化器状态的详细信息
     * 用于调试和性能监控
     * 
     * @return {Object} 包含所有状态信息的对象
     */
    public static function getStatus():Object {
        return {
            currentThreshold: _threshold,
            avgDensity: _params.avgDensity,
            params: getParams(),
            version: "1.0.0"
        };
    }

    /**
     * 生成状态报告字符串
     * 便于日志输出和调试
     * 
     * @return {String} 格式化的状态报告
     */
    public static function getStatusReport():String {
        var status:Object = getStatus();
        return "AdaptiveThresholdOptimizer Status:\n" +
               "  Current Threshold: " + Math.round(status.currentThreshold) + "px\n" +
               "  Avg Density: " + Math.round(status.avgDensity) + "px\n" +
               "  Alpha: " + status.params.alpha + "\n" +
               "  Density Factor: " + status.params.densityFactor + "\n" +
               "  Bounds: [" + status.params.minThreshold + ", " + status.params.maxThreshold + "]";
    }

    // ========================================================================
    // 工具方法
    // ========================================================================
    
    /**
     * 计算给定单位分布的建议阈值
     * 不改变当前状态，仅用于分析和预测
     * 
     * @param {Array} leftValues - 单位的left坐标数组
     * @return {Number} 建议的阈值
     */
    public static function calculateRecommendedThreshold(leftValues:Array):Number {
        var len:Number = leftValues.length;
        if (len < 2) return _threshold;

        var totalSpacing:Number = 0;
        var spacingCount:Number = 0;

        for (var i:Number = 1; i < len; i++) {
            var spacing:Number = leftValues[i] - leftValues[i - 1];
            if (spacing > 0) {
                totalSpacing += spacing;
                spacingCount++;
            }
        }

        if (spacingCount == 0) return _threshold;

        var avgSpacing:Number = totalSpacing / spacingCount;
        var recommendedThreshold:Number = avgSpacing * _params.densityFactor;
        
        return applyThresholdBounds(recommendedThreshold);
    }

    /**
     * 检查当前参数配置是否适合给定的单位分布
     * 返回优化建议
     * 
     * @param {Array} leftValues - 单位的left坐标数组
     * @return {Object} 包含分析结果和建议的对象
     */
    public static function analyzeDistribution(leftValues:Array):Object {
        var recommended:Number = calculateRecommendedThreshold(leftValues);
        var current:Number = _threshold;
        var diff:Number = Math.abs(recommended - current);
        var diffPercent:Number = (diff / current) * 100;

        return {
            currentThreshold: current,
            recommendedThreshold: recommended,
            difference: diff,
            differencePercent: diffPercent,
            suggestion: (diffPercent > 20) ? "Consider adjusting parameters" : "Parameters are well-suited",
            efficiency: (diffPercent < 10) ? "Excellent" : (diffPercent < 25) ? "Good" : "Poor"
        };
    }
}