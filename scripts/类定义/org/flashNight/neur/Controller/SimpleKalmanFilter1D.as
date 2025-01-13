

/**
 * SimpleKalmanFilter1D - 一维卡尔曼滤波器
 * 用于实时帧率测量与噪音过滤。
 */
class org.flashNight.neur.Controller.SimpleKalmanFilter1D {

    private var estimate:Number; // 当前状态估计（帧率）
    private var errorCov:Number; // 估计误差协方差
    private var processNoise:Number; // 过程噪声协方差 Q
    private var measurementNoise:Number; // 测量噪声协方差 R

    /**
     * 构造函数，初始化一维卡尔曼滤波器。
     *
     * @param initialEstimate 初始状态估计
     * @param processNoise 过程噪声协方差 Q
     * @param measurementNoise 测量噪声协方差 R
     */
    public function SimpleKalmanFilter1D(initialEstimate:Number, processNoise:Number, measurementNoise:Number) {
        this.estimate = initialEstimate;
        this.errorCov = 1; // 初始估计误差协方差，通常设为1或较大值
        this.processNoise = processNoise;
        this.measurementNoise = measurementNoise;
    }

    /**
     * 预测步骤：预测下一个状态和协方差。
     *
     * @return 预测的状态估计
     */
    public function predict():Number {
        // 预测步骤
        var predictedEstimate:Number = this.estimate; // 无控制输入，估计值保持不变
        var predictedErrorCov:Number = this.errorCov + this.processNoise;

        // 更新内部状态
        this.estimate = predictedEstimate;
        this.errorCov = predictedErrorCov;

        return this.estimate;
    }

    /**
     * 更新步骤：根据测量值更新状态估计。
     *
     * @param measuredValue 测量值（当前帧率）
     * @return 更新后的状态估计
     */
    public function update(measuredValue:Number):Number {
        // 输入校验
        if (isNaN(measuredValue)) {
            throw new Error("更新错误：测量值不能为 NaN。");
        }

        // 计算卡尔曼增益
        var kalmanGain:Number = this.errorCov / (this.errorCov + this.measurementNoise);

        // 更新步骤
        this.estimate = this.estimate + kalmanGain * (measuredValue - this.estimate);
        this.errorCov = (1 - kalmanGain) * this.errorCov;

        return this.estimate;
    }

    /**
     * 获取当前状态估计。
     *
     * @return 当前状态估计
     */
    public function getEstimate():Number {
        return this.estimate;
    }

    /**
     * 获取当前误差协方差。
     *
     * @return 当前误差协方差
     */
    public function getErrorCov():Number {
        return this.errorCov;
    }

    /**
     * 获取过程噪声协方差 Q。
     *
     * @return 过程噪声协方差 Q
     */
    public function getProcessNoise():Number {
        return this.processNoise;
    }

    /**
     * 获取测量噪声协方差 R。
     *
     * @return 测量噪声协方差 R
     */
    public function getMeasurementNoise():Number {
        return this.measurementNoise;
    }

    /**
     * 重置滤波器。
     *
     * @param initialEstimate 新的初始状态估计
     * @param initialErrorCov 新的初始误差协方差
     */
    public function reset(initialEstimate:Number, initialErrorCov:Number):Void {
        if (isNaN(initialEstimate)) {
            throw new Error("重置错误：初始估计不能为 NaN。");
        }
        if (initialErrorCov < 0) {
            throw new Error("重置错误：初始误差协方差不能为负。");
        }
        this.estimate = initialEstimate;
        this.errorCov = initialErrorCov;
    }

    /**
     * 设置过程噪声协方差 Q。
     *
     * @param Q 新的过程噪声协方差
     */
    public function setProcessNoise(Q:Number):Void {
        if (Q < 0) {
            throw new Error("设置错误：过程噪声协方差 Q 不能为负。");
        }
        this.processNoise = Q;
    }

    /**
     * 设置测量噪声协方差 R。
     *
     * @param R 新的测量噪声协方差
     */
    public function setMeasurementNoise(R:Number):Void {
        if (R < 0) {
            throw new Error("设置错误：测量噪声协方差 R 不能为负。");
        }
        this.measurementNoise = R;
    }
}
