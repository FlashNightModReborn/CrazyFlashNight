/**
 * AdaptiveKalmanFilter1D - 自适应一维卡尔曼滤波器
 * 用于动态调整过程噪声和测量噪声以优化滤波效果。
 */
class org.flashNight.neur.Optimizer.AdaptiveKalmanFilter1D {

    private var kalmanFilter:org.flashNight.neur.Controller.SimpleKalmanFilter1D;
    private var initialQ:Number;
    private var initialR:Number;
    private var alpha:Number;          // EWMA衰减因子
    private var residualMean:Number;   // 残差指数加权移动平均
    private var residualVariance:Number; // 残差方差估计
    private var isInitialized:Boolean; // 初始化标志

    /**
     * 构造函数
     * 
     * @param initialEstimate 初始状态估计
     * @param initialQ 初始过程噪声协方差
     * @param initialR 初始测量噪声协方差
     * @param alpha 衰减因子 (0.9~0.999)，值越大历史数据权重越高
     */
    public function AdaptiveKalmanFilter1D(
        initialEstimate:Number, 
        initialQ:Number, 
        initialR:Number, 
        alpha:Number
    ) {
        // 参数校验
        if (alpha <= 0 || alpha >= 1) {
            throw new Error("衰减因子必须介于0和1之间");
        }

        // 初始化卡尔曼滤波器
        kalmanFilter = new org.flashNight.neur.Controller.SimpleKalmanFilter1D(
            initialEstimate, 
            initialQ, 
            initialR
        );
        
        // 保存初始参数
        this.initialQ = initialQ;
        this.initialR = initialR;
        this.alpha = alpha;
        
        // 初始化统计量
        residualMean = 0;
        residualVariance = 0;
        isInitialized = false;
    }

    /**
     * 执行预测-更新周期并自适应调整参数
     * 
     * @param measuredValue 当前测量值
     * @return 优化后的状态估计值
     */
    public function update(measuredValue:Number):Number {
        // 预测阶段
        kalmanFilter.predict();
        
        // 记录预测后的先验估计
        var priorEstimate:Number = kalmanFilter.getEstimate();
        
        // 执行标准更新
        var filteredValue:Number = kalmanFilter.update(measuredValue);
        
        // 计算本次残差 (测量值 - 先验估计)
        var residual:Number = measuredValue - priorEstimate;
        
        // 更新EWMA统计量
        updateResidualStats(residual);
        
        // 参数自整定逻辑
        adaptParameters();
        
        return filteredValue;
    }

    /**
     * 更新残差统计量（使用指数加权移动平均法）
     */
    private function updateResidualStats(residual:Number):Void {
        if (!isInitialized) {
            // 首次初始化
            residualMean = residual;
            residualVariance = 0;
            isInitialized = true;
        } else {
            // 更新均值估计
            var newMean:Number = alpha * residualMean + (1 - alpha) * residual;
            
            // 更新方差估计（采用Welford算法变体）
            var delta:Number = residual - residualMean;
            residualMean = newMean;
            residualVariance = alpha * residualVariance + (1 - alpha) * (delta * delta);
        }
    }

    /**
     * 参数自适应调整核心逻辑
     */
    private function adaptParameters():Void {
        // 获取当前理论残差方差: HPH^T + R = P + R
        var theoreticalVar:Number = kalmanFilter.getErrorCov() + kalmanFilter.getMeasurementNoise();
        
        // 获取实际估计的残差方差
        var actualVar:Number = residualVariance;
        
        // 方差有效性检查
        if (actualVar <= 0 || theoreticalVar <= 0) return;
        
        // 计算方差比例因子
        var ratio:Number = actualVar / theoreticalVar;
        
        // 动态调整策略（带约束的比例调整）
        var sqrtRatio:Number = Math.sqrt(ratio);
        
        // 调整Q（过程噪声）
        var newQ:Number = kalmanFilter.getProcessNoise() * sqrtRatio;
        newQ = Math.max(0.001, Math.min(newQ, 100 * initialQ)); // 约束在0.001~100倍初始Q
        
        // 调整R（测量噪声）
        var newR:Number = kalmanFilter.getMeasurementNoise() * sqrtRatio; 
        newR = Math.max(0.001, Math.min(newR, 100 * initialR)); // 约束在0.001~100倍初始R
        
        // 应用新参数
        kalmanFilter.setProcessNoise(newQ);
        kalmanFilter.setMeasurementNoise(newR);
    }

    /**
     * 重置滤波器状态（保留初始Q/R配置）
     */
    public function reset():Void {
        kalmanFilter.reset(kalmanFilter.getEstimate(), 1);
        residualMean = 0;
        residualVariance = 0;
        isInitialized = false;
    }

    // 以下为访问器方法
    public function getEstimate():Number {
        return kalmanFilter.getEstimate();
    }
    
    public function getCurrentQ():Number {
        return kalmanFilter.getProcessNoise();
    }
    
    public function getCurrentR():Number {
        return kalmanFilter.getMeasurementNoise();
    }
}
