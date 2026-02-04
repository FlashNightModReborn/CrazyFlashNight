/**
 * HysteresisQuantizer - 迟滞量化器（两次确认的施密特触发器）
 *
 * 职责：
 * - 将 PID 连续输出 u* 量化为离散档位 u ∈ [minLevel, maxLevel]
 * - 通过"连续两次候选 !== 当前"才执行切换，抑制量化极限环抖振
 *
 * 注意：
 * - 为保持行为等价，本实现与工作版本一致：只记录一个布尔 awaitConfirmation，
 *   不记忆“上一次候选档位”。第二次确认时使用当次的候选档位作为最终切换目标。
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
