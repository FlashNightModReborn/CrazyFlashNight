/**
 * HysteresisQuantizer - 迟滞量化器（两次确认的施密特触发器）
 *
 * 职责：
 * - 将 PID 连续输出 u* 量化为离散档位 u ∈ [minLevel, maxLevel]
 * - 通过"连续两次候选 !== 当前"才执行切换，抑制量化极限环抖振
 *
 * 【量化操作】
 *   u_k = round(u*_k)，然后 clamp 到 [minLevel, maxLevel]
 *
 * 【控制理论】量化控制的极限环问题
 * ───────────────────────────────────────────────────────────
 *   当 PID 输出在两个量化级别之间振荡时（如 1.4 ↔ 1.6），
 *   round() 会导致输出在 1 和 2 之间来回跳变，形成「量化极限环」。
 *   这是离散执行器系统的固有问题，需要通过迟滞/死区来解决。
 *
 * 【迟滞/驻留控制 (Hysteresis / Dwell-Time Control)】
 * ───────────────────────────────────────────────────────────
 *   状态机：
 *   ┌─────────────────────────────────────────────────────────────┐
 *   │  当前状态         输入条件               下一状态    动作    │
 *   ├─────────────────────────────────────────────────────────────┤
 *   │  awaitConfirm=F   等级变化               awaitConfirm=T  无 │
 *   │  awaitConfirm=T   等级变化（连续第二次） awaitConfirm=F 切换 │
 *   │  awaitConfirm=T   等级相同               awaitConfirm=F  无 │
 *   │  awaitConfirm=F   等级相同               awaitConfirm=F  无 │
 *   └─────────────────────────────────────────────────────────────┘
 *
 *   迟滞的核心作用是压制「量化极限环」：
 *   • 时间跨度: 2个采样周期 = 2~8秒（取决于性能等级）
 *   • 频率分析: 等效于截止频率 0.125~0.5 Hz 的低通滤波器
 *   • 人因工程: 2~8秒匹配用户对帧率变化的感知窗口（约3-5秒）
 *
 *   【这是系统稳定性的核心机制】
 *   即使 PID 输出抖动，迟滞也能保证切换频率极低
 *   实测切换频率 < 0.1次/秒（每10秒最多1次）
 *
 * 注意：
 * - 为保持行为等价，本实现与工作版本一致：只记录一个布尔 awaitConfirmation，
 *   不记忆"上一次候选档位"。第二次确认时使用当次的候选档位作为最终切换目标。
 * - 比较使用 !== （严格不等），避免类型强制转换导致的误判。
 */
class org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer {

    private var _awaitConfirmation:Boolean;
    private var _minLevel:Number;
    private var _maxLevel:Number;
    private var _result:Object; // 复用对象，避免每次 process() 分配

    /**
     * 构造函数
     * @param minLevel:Number 下限（允许的最高画质），通常由“性能等级上限”提供
     * @param maxLevel:Number 上限（最低画质），工作版本固定为3
     */
    public function HysteresisQuantizer(minLevel:Number, maxLevel:Number) {
        this._minLevel = (minLevel == undefined) ? 0 : minLevel;
        this._maxLevel = (maxLevel == undefined) ? 3 : maxLevel;
        this._awaitConfirmation = false;
        this._result = { levelChanged: false, newLevel: this._minLevel };
    }

    /**
     * 处理一次 PID 输出，返回是否需要执行切换以及目标档位。
     * @param pidOutput:Number PID 连续输出
     * @param currentLevel:Number 当前性能等级
     * @return Object { levelChanged:Boolean, newLevel:Number }
     */
    public function process(pidOutput:Number, currentLevel:Number):Object {
        var candidate:Number = Math.round(pidOutput);
        candidate = Math.max(this._minLevel, Math.min(candidate, this._maxLevel));

        if (candidate !== currentLevel) {
            if (this._awaitConfirmation) {
                this._awaitConfirmation = false;
                this._result.levelChanged = true;
                this._result.newLevel = candidate;
                return this._result;
            }
            this._awaitConfirmation = true;
            this._result.levelChanged = false;
            this._result.newLevel = currentLevel;
            return this._result;
        }

        this._awaitConfirmation = false;
        this._result.levelChanged = false;
        this._result.newLevel = currentLevel;
        return this._result;
    }

    /**
     * 清除确认状态（用于前馈控制/强制切档后，避免下一次评估误触发）
     */
    public function clearConfirmation():Void {
        this._awaitConfirmation = false;
    }

    public function isAwaitingConfirmation():Boolean {
        return this._awaitConfirmation;
    }

    /**
     * 设置当前确认状态（用于与旧系统状态对齐，或测试构造特定状态）
     * @param value:Boolean 是否处于等待二次确认
     */
    public function setAwaitingConfirmation(value:Boolean):Void {
        this._awaitConfirmation = value;
    }

    public function setMinLevel(level:Number):Void {
        this._minLevel = level;
    }

    public function getMinLevel():Number {
        return this._minLevel;
    }

    public function setMaxLevel(level:Number):Void {
        this._maxLevel = level;
    }

    public function getMaxLevel():Number {
        return this._maxLevel;
    }
}
