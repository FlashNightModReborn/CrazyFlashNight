class org.flashNight.neur.Controller.PIDController {
    // 私有变量定义
    private var kp:Number; // 比例增益
    private var ki:Number; // 积分增益
    private var kd:Number; // 微分增益
    private var errorPrev:Number; // 上一次的误差
    private var integral:Number; // 误差积分
    private var integralMax:Number; // 积分限幅
    private var derivativeFilter:Number; // 微分项滤波器系数
    private var derivativePrev:Number; // 上次的微分项

    // 构造函数
    public function PIDController(kp:Number, ki:Number, kd:Number, integralMax:Number, derivativeFilter:Number) {
        // 使用明确的 this 指定对象变量
        this.kp = kp;
        this.ki = ki;
        this.kd = kd;
        this.errorPrev = 0;
        this.integral = 0;

        // 设置默认值，确保参数有效性
        this.integralMax = (integralMax != undefined) ? integralMax : 1000;
        this.derivativeFilter = (derivativeFilter != undefined) ? derivativeFilter : 0.1;
        this.derivativePrev = 0;
    }

    // 获取积分项当前值
    public function getIntegral():Number {
        return this.integral;
    }

    // 重置控制器状态
    public function reset():Void {
        this.errorPrev = 0;
        this.integral = 0;
        this.derivativePrev = 0;
    }

    // 更新 PID 控制器并返回控制输出
    public function update(setPoint:Number, actualValue:Number, deltaTime:Number):Number {
        // 确保 deltaTime 合法
        if (deltaTime <= 0) {
            return 0;
        }

        // 计算误差
        var error:Number = setPoint - actualValue;

        // 更新积分项并进行限幅
        this.integral += error * deltaTime;
        this.integral = this.limitIntegral(this.integral); // 使用单独函数处理积分限幅

        // 平滑微分项
        var derivative:Number = this.filterDerivative(error, deltaTime);

        // 计算 PID 输出
        var output:Number = 
            this.kp * error + 
            this.ki * this.integral + 
            this.kd * derivative;

        // 更新前一次误差
        this.errorPrev = error;

        return output;
    }

    // 辅助函数：限制积分值范围
    private function limitIntegral(value:Number):Number {
        if (value > this.integralMax) return this.integralMax;
        if (value < -this.integralMax) return -this.integralMax;
        return value;
    }

    // 辅助函数：计算平滑微分项
    private function filterDerivative(error:Number, deltaTime:Number):Number {
        var errorDiff:Number = (error - this.errorPrev) / deltaTime;
        this.derivativePrev = this.derivativePrev * (1 - this.derivativeFilter) + errorDiff * this.derivativeFilter;
        return this.derivativePrev;
    }

    // 设置和获取 PID 参数
    public function setKp(value:Number):Void {
        this.kp = value;
    }

    public function setKi(value:Number):Void {
        this.ki = value;
    }

    public function setKd(value:Number):Void {
        this.kd = value;
    }

    public function getKp():Number {
        return this.kp;
    }

    public function getKi():Number {
        return this.ki;
    }

    public function getKd():Number {
        return this.kd;
    }

    // 增加获取积分限幅和微分滤波系数的函数
    public function setIntegralMax(value:Number):Void {
        this.integralMax = value;
    }

    public function getIntegralMax():Number {
        return this.integralMax;
    }

    public function setDerivativeFilter(value:Number):Void {
        this.derivativeFilter = value;
    }

    public function getDerivativeFilter():Number {
        return this.derivativeFilter;
    }

    // 输出字符串表示 PID 控制器状态
    public function toString():String {
        return "PIDController {" +
            " kp: " + this.kp +
            ", ki: " + this.ki +
            ", kd: " + this.kd +
            ", integral: " + this.integral +
            ", integralMax: " + this.integralMax +
            ", derivativeFilter: " + this.derivativeFilter +
            ", errorPrev: " + this.errorPrev +
            ", derivativePrev: " + this.derivativePrev +
            " }";
    }
}
