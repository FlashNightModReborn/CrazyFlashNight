import org.flashNight.neur.Controller.*;
import org.flashNight.gesh.xml.LoadXml.*;

class org.flashNight.neur.Controller.PIDController {
    // ===== 私有变量定义 =====
    private var kp:Number; // 比例增益 (Proportional Gain)，控制误差的比例放大系数
    private var ki:Number; // 积分增益 (Integral Gain)，控制误差累计的影响
    private var kd:Number; // 微分增益 (Derivative Gain)，控制误差变化率的影响
    private var errorPrev:Number; // 上一次误差值，用于计算微分项
    private var integral:Number; // 积分项累积值，用于反积分控制
    private var integralMax:Number; // 积分项的最大限幅，防止积分饱和
    private var derivativeFilter:Number; // 微分项滤波系数，用于平滑微分项，防止高频噪声影响
    private var derivativePrev:Number; // 上一次微分项计算值，用于平滑微分输出

    // ===== 最近一次 update() 的 P/I/D 分量（用于日志/系统辨识） =====
    private var _lastP:Number; // 比例项输出: kp * error
    private var _lastI:Number; // 积分项输出: ki * integral
    private var _lastD:Number; // 微分项输出: kd * derivativePrev

    // ===== 构造函数 =====
    /**
     * 构造函数 - 初始化 PID 控制器参数和状态
     * @param kp:Number 比例增益系数
     * @param ki:Number 积分增益系数
     * @param kd:Number 微分增益系数
     * @param integralMax:Number 积分项最大限幅值，防止积分过大
     * @param derivativeFilter:Number 微分项滤波器系数，范围 (0.0 ~ 1.0)
     */
    public function PIDController(kp:Number, ki:Number, kd:Number, integralMax:Number, derivativeFilter:Number) {
        // 设置比例、积分、微分增益
        this.kp = kp;
        this.ki = ki;
        this.kd = kd;

        // 初始化控制器状态
        this.errorPrev = 0; // 上次误差初始值为 0
        this.integral = 0; // 积分项初始值为 0

        // 设置积分限幅和微分滤波器系数
        this.integralMax = (integralMax != undefined) ? integralMax : 1000; // 默认积分限幅为 1000
        this.derivativeFilter = (derivativeFilter != undefined) ? derivativeFilter : 0.1; // 默认滤波器系数为 0.1

        this.derivativePrev = 0; // 上次微分项初始值为 0

        // P/I/D 分量初始化
        this._lastP = 0;
        this._lastI = 0;
        this._lastD = 0;
    }

    // ===== 公共方法 =====

    /**
     * 获取当前积分项的值
     * @return Number 当前积分项的累积值
     */
    public function getIntegral():Number {
        return this.integral;
    }

    /**
     * 重置 PID 控制器的状态
     * 清除误差、积分和微分项的历史状态，适合控制器重新开始计算
     */
    public function reset():Void {
        this.errorPrev = 0;
        this.integral = 0;
        this.derivativePrev = 0;
        this._lastP = 0;
        this._lastI = 0;
        this._lastD = 0;
    }

    // ===== 核心控制逻辑 =====
    /**
     * 更新 PID 控制器的状态并计算输出值
     * @param setPoint:Number 目标值 (期望值)
     * @param actualValue:Number 实际值 (测量值)
     * @param deltaTime:Number 时间步长，必须大于 0。
     *        单位由调用方决定。性能调度系统传入帧数（30~120），
     *        这会使积分项快速饱和（±integralMax）并缩小微分项增益。
     *        详见 IntervalSampler.getPIDDeltaTimeFrames() 注释。
     * @return Number 控制输出值
     */
    public function update(setPoint:Number, actualValue:Number, deltaTime:Number):Number {
        // 确保 deltaTime 合法，防止除零错误
        if (deltaTime <= 0) return 0;

        // ===== 缓存变量以提升访问速度 =====
        var kp:Number = this.kp; // 比例增益
        var ki:Number = this.ki; // 积分增益
        var kd:Number = this.kd; // 微分增益
        var integralMax:Number = this.integralMax; // 积分限幅
        var derivativeFilter:Number = this.derivativeFilter; // 微分滤波系数

        // ===== 计算误差 =====
        var error:Number = setPoint - actualValue; // 误差 = 目标值 - 实际值

        // ===== 计算积分项并限幅 =====
        var integral:Number = this.integral + error * deltaTime; // 积分累计
        if (integral > integralMax) { // 限幅：防止积分过大
            integral = integralMax;
        } else if (integral < -integralMax) { // 限幅：防止积分过小
            integral = -integralMax;
        }
        this.integral = integral; // 更新积分项状态

        // ===== 计算微分项并滤波 =====
        var errorDiff:Number = (error - this.errorPrev) / deltaTime; // 误差变化率
        this.derivativePrev = this.derivativePrev * (1 - derivativeFilter) + errorDiff * derivativeFilter; // 应用滤波器平滑微分项

        // 更新前一次误差状态
        this.errorPrev = error;

        // ===== 计算 PID 输出并缓存分量 =====
        this._lastP = kp * error;
        this._lastI = ki * integral;
        this._lastD = kd * this.derivativePrev;
        return this._lastP + this._lastI + this._lastD;
    }

    // ===== 参数设置与获取 =====
    /**
     * 设置和获取比例增益
     */
    public function setKp(value:Number):Void { this.kp = value; }
    public function getKp():Number { return this.kp; }

    /**
     * 设置和获取积分增益
     */
    public function setKi(value:Number):Void { this.ki = value; }
    public function getKi():Number { return this.ki; }

    /**
     * 设置和获取微分增益
     */
    public function setKd(value:Number):Void { this.kd = value; }
    public function getKd():Number { return this.kd; }

    /**
     * 设置和获取积分限幅
     */
    public function setIntegralMax(value:Number):Void { this.integralMax = value; }
    public function getIntegralMax():Number { return this.integralMax; }

    /**
     * 设置和获取微分滤波系数
     */
    public function setDerivativeFilter(value:Number):Void { this.derivativeFilter = value; }
    public function getDerivativeFilter():Number { return this.derivativeFilter; }

    // ===== P/I/D 分量访问器（系统辨识/日志用） =====
    /**
     * 获取最近一次 update() 的各分量输出值。
     * 用途：日志系统记录 EVT_PID_DETAIL，供离线系统辨识和参数优化。
     * 注意：reset() 后返回 0，update() 前无意义。
     */
    public function getLastP():Number { return this._lastP; }
    public function getLastI():Number { return this._lastI; }
    public function getLastD():Number { return this._lastD; }

    // ===== 调试与状态输出 =====
    /**
     * 输出当前 PID 控制器的状态信息
     * @return String 表示当前控制器状态的字符串
     */
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
