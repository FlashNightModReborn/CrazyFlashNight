class org.flashNight.neur.Controller.PIDController {
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
        this.kp = kp;
        this.ki = ki;
        this.kd = kd;
        this.errorPrev = 0;
        this.integral = 0;
        // 使用局部常量缓存，减少重复赋值和传递的开销
        this.integralMax = (integralMax != undefined) ? integralMax : 1000; // 设定积分限幅
        this.derivativeFilter = (derivativeFilter != undefined) ? derivativeFilter : 0.1; // 微分项滤波
        this.derivativePrev = 0;
    }

    public function getIntegral():Number {
        return integral;
    }

    public function reset():Void {
        this.errorPrev = 0;
        this.integral = 0;
        this.derivativePrev = 0;
    }

    // 更新 PID 控制器，并返回控制输出
    public function update(setPoint:Number, actualValue:Number, deltaTime:Number):Number {
        // 确保 deltaTime > 0，避免负值或者零的场景
        if (deltaTime <= 0) {
            return 0;
        }

        // 计算误差
        var error:Number = setPoint - actualValue;

        // 积分项更新，同时应用反积分饱和
        integral += error * deltaTime;
        // 替换 Math.max 和 Math.min 函数，利用逻辑运算符的短路特性进一步优化，减少条件判断次数
        // integral = (integral > integralMax && (integral = integralMax)) || (integral < -integralMax && (integral = -integralMax)) || integral;

        // 微分项平滑处理，提前计算 errorPrev 和 error 差值
        // var errorDiff:Number = (error - errorPrev) / deltaTime;
        // derivativePrev = derivativePrev * (1 - derivativeFilter) + errorDiff * derivativeFilter;
        
        // 计算 PID 输出，内联计算，减少临时变量和重复计算
        var output:Number = kp * error + ki * (integral = (integral > integralMax && (integral = integralMax)) || (integral < -integralMax && (integral = -integralMax)) || integral) + kd * (derivativePrev * (1 - derivativeFilter) + ((error - errorPrev) / deltaTime) * derivativeFilter);

        // 更新上一次误差
        errorPrev = error;

        return output;
    }

    // 设置和获取 PID 参数
    public function setKp(value:Number):Void {
        kp = value;
    }

    public function setKi(value:Number):Void {
        ki = value;
    }

    public function setKd(value:Number):Void {
        kd = value;
    }

    public function getKp():Number {
        return kp;
    }

    public function getKi():Number {
        return ki;
    }

    public function getKd():Number {
        return kd;
    }
}
