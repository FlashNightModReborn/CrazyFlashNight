/**
 * HysteresisQuantizer - 非对称迟滞量化器（方向感知的施密特触发器）
 *
 * 职责：
 * - 将 PID 连续输出 u* 量化为离散档位 u ∈ [minLevel, maxLevel]
 * - 通过方向感知的连续确认机制抑制量化极限环抖振
 * - 降级（画质下降）快速响应，升级（画质恢复）谨慎延迟
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
 * 【非对称迟滞 (Asymmetric Hysteresis)】
 * ───────────────────────────────────────────────────────────
 *   降级（level↑，画质↓）：2 次连续确认即执行
 *     理由：FPS 下降时应迅速减负载，保护流畅度
 *
 *   升级（level↓，画质↑）：3 次连续确认才执行
 *     理由：FPS 恢复后谨慎恢复画质，避免刚升回就被打回
 *     实测依据：堕落城保卫战 ~30s 战斗周期中，击杀完毕→等待刷怪
 *     的间隔期 FPS 短暂回升触发升级，刷怪后立刻压力回升导致乒乓。
 *     延长一个采样周期可跨越刷怪间隔，有效抑制周期性乒乓。
 *
 *   方向记忆：仅记忆方向（升/降），不记忆具体候选等级
 *     理由：在性能断崖场景中（如 L0→L2→L3 快速恶化），
 *     记忆具体等级会导致候选从 2 变为 3 时重置确认计数，
 *     使系统在断崖中迟钝。仅记忆方向则允许确认计数持续累积，
 *     最终切换到当次的最新候选等级。
 *
 *   状态机：
 *   ┌──────────────────────────────────────────────────────────────────┐
 *   │  当前状态              输入条件                下一状态    动作  │
 *   ├──────────────────────────────────────────────────────────────────┤
 *   │  count=0               等级相同               count=0     无    │
 *   │  count=0               降级方向               count=1     无    │
 *   │  count=0               升级方向               count=1     无    │
 *   │  count>0,方向=降       降级方向               count++     检查  │
 *   │  count>0,方向=降       升级方向(反转)          count=1     重置  │
 *   │  count>0,方向=升       升级方向               count++     检查  │
 *   │  count>0,方向=升       降级方向(反转)          count=1     重置  │
 *   │  count>=阈值           —                      count=0     切换  │
 *   │  count>0               等级相同               count=0     无    │
 *   └──────────────────────────────────────────────────────────────────┘
 *
 *   降级阈值=2 时的时间跨度: 2个采样周期 = 2~8秒
 *   升级阈值=3 时的时间跨度: 3个采样周期 = 3~12秒
 *
 * 注意：
 * - 方向反转时确认计数从 1 开始（不是 0），因为反转本身就是一次有效检测
 * - 比较使用 !== （严格不等），避免类型强制转换导致的误判
 */
class org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer {

    /** 连续确认计数（0 = 无待确认） */
    private var _confirmCount:Number;
    /** 待确认的变化方向（1=降级/level↑, -1=升级/level↓, 0=无） */
    private var _pendingDirection:Number;
    /** 降级确认阈值（level↑，画质↓），默认 2 */
    private var _downgradeThreshold:Number;
    /** 升级确认阈值（level↓，画质↑），默认 3 */
    private var _upgradeThreshold:Number;

    private var _minLevel:Number;
    private var _maxLevel:Number;
    private var _result:Object; // 复用对象，避免每次 process() 分配

    /**
     * 构造函数
     * @param minLevel:Number 下限（允许的最高画质），通常由"性能等级上限"提供
     * @param maxLevel:Number 上限（最低画质），工作版本固定为3
     * @param downgradeThreshold:Number 降级确认次数（level↑，画质↓），默认2
     * @param upgradeThreshold:Number 升级确认次数（level↓，画质↑），默认3
     */
    public function HysteresisQuantizer(minLevel:Number, maxLevel:Number,
                                         downgradeThreshold:Number, upgradeThreshold:Number) {
        this._minLevel = (minLevel == undefined) ? 0 : minLevel;
        this._maxLevel = (maxLevel == undefined) ? 3 : maxLevel;
        this._downgradeThreshold = (downgradeThreshold == undefined) ? 2 : downgradeThreshold;
        this._upgradeThreshold = (upgradeThreshold == undefined) ? 3 : upgradeThreshold;
        this._confirmCount = 0;
        this._pendingDirection = 0;
        this._result = { levelChanged: false, newLevel: this._minLevel };
    }

    /**
     * 处理一次 PID 输出，返回是否需要执行切换以及目标档位。
     * @param pidOutput:Number PID 连续输出
     * @param currentLevel:Number 当前性能等级
     * @return Object { levelChanged:Boolean, newLevel:Number }
     *
     * 【注意】返回值为内部复用对象，调用方必须在下次 process() 前消费完毕，不可缓存引用。
     */
    public function process(pidOutput:Number, currentLevel:Number):Object {
        // P3: 位运算替代 Math.round/max/min（T2）
        // 【不变量】clamp((x+0.5)>>0, mn, mx) ≡ clamp(Math.round(x), mn, mx) 当 mn≥0：
        //   x+0.5≥0 时 trunc≡floor，(x+0.5)>>0 = Math.round(x)；
        //   x+0.5<0 时两者可能不同，但结果≤0，经 clamp 到 mn≥0 后一致。
        //   前提: minLevel≥0 由构造函数默认值 + 性能等级上限∈[0,3] 保证。
        var candidate:Number = (pidOutput + 0.5) >> 0;
        var mn:Number = this._minLevel;
        var mx:Number = this._maxLevel;
        candidate = (candidate < mn) ? mn : (candidate > mx) ? mx : candidate;

        if (candidate !== currentLevel) {
            // 判断变化方向：candidate > current → 降级(+1)，< current → 升级(-1)
            var direction:Number = (candidate > currentLevel) ? 1 : -1;

            if (this._confirmCount > 0 && direction === this._pendingDirection) {
                // 同方向连续确认，计数递增
                this._confirmCount++;
            } else {
                // 首次检测或方向反转，（重新）开始计数
                this._pendingDirection = direction;
                this._confirmCount = 1;
            }

            // 根据方向选择对应阈值
            var threshold:Number = (direction > 0) ? this._downgradeThreshold : this._upgradeThreshold;

            if (this._confirmCount >= threshold) {
                // 达到阈值，执行切换
                this._confirmCount = 0;
                this._pendingDirection = 0;
                this._result.levelChanged = true;
                this._result.newLevel = candidate;
                return this._result;
            }

            // 未达阈值，继续等待
            this._result.levelChanged = false;
            this._result.newLevel = currentLevel;
            return this._result;
        }

        // 候选 === 当前，重置确认状态
        this._confirmCount = 0;
        this._pendingDirection = 0;
        this._result.levelChanged = false;
        this._result.newLevel = currentLevel;
        return this._result;
    }

    /**
     * 清除确认状态（用于前馈控制/强制切档后，避免下一次评估误触发）
     */
    public function clearConfirmation():Void {
        this._confirmCount = 0;
        this._pendingDirection = 0;
    }

    /**
     * 是否有待确认的变更（向后兼容，等价于 confirmCount > 0）
     */
    public function isAwaitingConfirmation():Boolean {
        return this._confirmCount > 0;
    }

    /**
     * 设置确认状态（向后兼容/测试用）
     * true → 模拟一次降级方向的待确认（count=1, direction=+1）
     * false → 清除所有确认状态
     *
     * 注：需要精确控制方向和计数的测试场景请使用 setConfirmState()
     */
    public function setAwaitingConfirmation(value:Boolean):Void {
        if (value) {
            this._confirmCount = 1;
            this._pendingDirection = 1; // 默认降级方向
        } else {
            this._confirmCount = 0;
            this._pendingDirection = 0;
        }
    }

    /**
     * 精确设置确认状态（用于测试构造特定状态）
     * @param count:Number 确认计数
     * @param direction:Number 方向（1=降级, -1=升级, 0=无）
     */
    public function setConfirmState(count:Number, direction:Number):Void {
        this._confirmCount = count;
        this._pendingDirection = direction;
    }

    /**
     * 获取当前确认计数
     */
    public function getConfirmCount():Number {
        return this._confirmCount;
    }

    /**
     * 获取当前待确认方向（1=降级, -1=升级, 0=无）
     */
    public function getPendingDirection():Number {
        return this._pendingDirection;
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

    public function getDowngradeThreshold():Number {
        return this._downgradeThreshold;
    }

    public function getUpgradeThreshold():Number {
        return this._upgradeThreshold;
    }
}
