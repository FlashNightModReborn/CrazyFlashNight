import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.component.StatHandler.ImpactHandler {
    // *******************************
    // 常量配置：便于外部调整相关参数
    // *******************************
    public static var IMPACT_COEFFICIENT:Number = 50;      // 冲击系数，控制冲击力的基础倍数
    public static var IMPACT_DECAY_TIME:Number = 5;        // 冲击残余时间（秒）
    public static var IMPACT_STAGGER_COEFFICIENT:Number = 2; // 控制硬直与冲击力衰减关联的系数
    public static var IMPACT_DECAY_FRAME:Number = IMPACT_DECAY_TIME * 30; // 衰减起始帧数（假设30FPS）
    public static var IMPACT_DECAY_DFRAME:Number = IMPACT_DECAY_FRAME * 2; // 衰减最大帧数（两倍衰减时间）

    /**
     * 韧性上限的唯一公式入口。
     * 防御按伤害链实际使用的完整数值参与计算，保证战斗、头顶条与个人信息面板一致。
     */
    public static function calculateImpactCap(target:Object):Number {
        if (!target) return 0;

        var toughness:Number = Number(target.韧性系数);
        var hp:Number = Number(target.hp);
        var defense:Number = Number(target.防御力);
        if (!isFinite(toughness) || toughness < 0) toughness = 0;
        if (!isFinite(hp) || hp <= 0) return 0;
        // DamageCalculator 在实际承伤前会把非正防御归一到 1；这里沿用同一边界，
        // 避免个人信息/头顶条在异常配置下先显示另一套韧性上限。
        if (!(defense > 0) || !isFinite(defense)) defense = 1;

        var damageRatio:Number = DamageResistanceHandler.defenseDamageRatio(defense);
        if (!(damageRatio > 0) || !isFinite(damageRatio)) return 0;

        var cap:Number = toughness * hp / damageRatio;
        return (cap > 0 && isFinite(cap)) ? cap : 0;
    }

    private static function calculateStaggerFromCap(target:Object, cap:Number):Number {
        if (!(cap > 0)) return 0;

        var dodgeRate:Number = Number(target.躲闪率);
        if (!(dodgeRate > 0) || !isFinite(dodgeRate)) {
            dodgeRate = DodgeHandler.DODGE_RATE_LIMIT;
        }
        return cap / IMPACT_STAGGER_COEFFICIENT / dodgeRate;
    }

    /** 由同一韧性上限与反向躲闪参数计算踉跄阈值。 */
    public static function calculateImpactStaggerBoundary(target:Object):Number {
        return calculateStaggerFromCap(target, calculateImpactCap(target));
    }

    /**
     * 从当前权威属性与冲击残量重建派生字段，不推进时间也不触发状态改变。
     * 换装降低上限时仅把显示夹到 0；下一次真实命中仍由 ImpactStateHandler 判定破韧。
     */
    public static function refreshImpactDerived(target:Object):Void {
        if (!target) return;

        var cap:Number = calculateImpactCap(target);
        var remaining:Number = Number(target.remainingImpactForce);
        if (!isFinite(remaining)) {
            remaining = remaining > 0 ? cap + 1 : 0;
        } else if (remaining < 0) {
            remaining = 0;
        }

        target.remainingImpactForce = remaining;
        target.韧性上限 = cap;
        target.impactStaggerBoundary = calculateStaggerFromCap(target, cap);

        if (cap > 0) {
            var loadRatio:Number = remaining / cap;
            if (loadRatio < 0) loadRatio = 0;
            else if (loadRatio > 1) loadRatio = 1;
            target.nonlinearMappingResilience = 1 - Math.sqrt(loadRatio);
        } else {
            target.nonlinearMappingResilience = 0;
        }
    }

    /**
     * 把当前冲击残量冻结为本次真实命中的衰减基线。
     */
    private static function captureImpactDecayBaseline(target:Object):Void {
        var remaining:Number = Number(target.remainingImpactForce);
        if (!isFinite(remaining) || remaining < 0) remaining = 0;
        target.remainingImpactForce = remaining;
        target.impactDecayBaseForce = remaining;
    }

    /** 结算真实冲击后同时开启新窗口，保证新增冲击不会沿用旧命中的时间锚点。 */
    private static function beginImpactDecayWindow(target:Object):Void {
        var currentFrame:Number = Number(_root.帧计时器.当前帧数);
        if (isFinite(currentFrame)) target.lastHitTime = currentFrame;
        captureImpactDecayBaseline(target);
    }

    /**
     * 从窗口基线计算当前帧的绝对投影，而不是继续乘上一次投影。
     * 这样四帧 updater 的同帧重复调用保持幂等，MISS 热路径无需参与衰减。
     */
    private static function applyImpactDecay(target:Object, intervalFrames:Number):Void {
        var remaining:Number = Number(target.remainingImpactForce);
        if (!isFinite(remaining) || remaining < 0) remaining = 0;
        if (!(remaining > 0)) {
            // 破韧/倒地只会把残量归零；同步清掉唯一基线，旧冲击不会复活。
            target.remainingImpactForce = 0;
            target.impactDecayBaseForce = 0;
            return;
        }

        var baseline:Number = Number(target.impactDecayBaseForce);
        if (!(baseline > 0) || !isFinite(baseline)) {
            // 首次接管旧单位；之后只有真实命中会建立新基线。
            baseline = remaining;
            target.impactDecayBaseForce = baseline;
        }

        var projected:Number = baseline;
        if (intervalFrames > IMPACT_DECAY_FRAME) {
            if (intervalFrames >= IMPACT_DECAY_DFRAME) {
                projected = 0;
            } else {
                // 保留既有平衡语义：150 帧前不衰减，随后按 (300-t)/300 线性投影至 0。
                projected = baseline * (IMPACT_DECAY_DFRAME - intervalFrames)
                    / IMPACT_DECAY_DFRAME;
            }
        }

        target.remainingImpactForce = projected;
    }

    /** 把旧命中窗口绝对投影到当前帧，并返回当前帧。 */
    private static function projectImpactDecayToCurrentFrame(target:Object):Number {
        var currentFrame:Number = Number(_root.帧计时器.当前帧数);
        var lastHitTime:Number = Number(target.lastHitTime);
        if (!isFinite(lastHitTime) || !isFinite(currentFrame) || lastHitTime > currentFrame) {
            if (isFinite(currentFrame)) target.lastHitTime = currentFrame;
            captureImpactDecayBaseline(target);
            return currentFrame;
        }

        applyImpactDecay(target, currentFrame - lastHitTime);
        return currentFrame;
    }

    /**
     * 结算冲击力
     * -----------------------------
     * 根据伤害值和击倒率计算冲击力，并累加到目标的剩余冲击力中。
     *
     * 计算公式：
     *   冲击力 = (伤害值 × 冲击系数) ÷ 击倒率
     *
     * 特殊情况：
     *   若击倒率为0或无效，则直接将目标的剩余冲击力设置为超出韧性上限的值，
     *   使其必定被击倒。
     *
     * @param damage Number 造成的伤害值，直接影响冲击力的基础值
     * @param knockRate Number 击倒率，目标受击稳定性（数值越高，越难击倒）
     * @param target Object 被命中的目标对象，需具备属性：
     *        - remainingImpactForce（当前剩余冲击力）
     *        - 韧性上限（目标的冲击韧性上限）
     */
    public static function settleImpactForce(damage:Number, knockRate:Number, target:Object):Void {
        // HitUpdater 不再做预刷新；真实命中在这里先投影旧窗口，再只派生一次。
        projectImpactDecayToCurrentFrame(target);
        var remaining:Number = Number(target.remainingImpactForce);
        if (!isFinite(remaining) || remaining < 0) remaining = 0;

        // 若击倒率为0或无效，直接设置冲击力超出韧性上限
        if (!(knockRate > 0) || !isFinite(knockRate)) {
            var cap:Number = calculateImpactCap(target);
            target.remainingImpactForce = cap + 1;
            beginImpactDecayWindow(target);
            refreshImpactDerived(target);
            return;
        }

        if (!(damage > 0) || !isFinite(damage)) {
            target.remainingImpactForce = remaining;
            beginImpactDecayWindow(target);
            refreshImpactDerived(target);
            return;
        }

        // 计算冲击力，并累加到目标的剩余冲击力中
        var impactForce:Number = damage * IMPACT_COEFFICIENT / knockRate;
        if (isFinite(impactForce)) {
            target.remainingImpactForce = remaining + impactForce;
        } else {
            var overflowCap:Number = calculateImpactCap(target);
            target.remainingImpactForce = overflowCap + 1;
        }
        beginImpactDecayWindow(target);
        refreshImpactDerived(target);
    }

    /**
     * 兼容旧测试/只读调用的冲击状态刷新；生产命中由 settleImpactForce 一次完成。
     * -----------------------------
     * 根据目标的受击时间以及属性，计算当前的韧性上限，同时在必要时对
     * 剩余冲击力进行衰减更新。
     *
     * 衰减规则：
     * 1. 获取当前游戏帧数（currentFrame），计算与上次受击的间隔帧数（intervalFrames）。
     * 2. 当间隔帧数大于衰减起始帧（IMPACT_DECAY_FRAME）时，
     *    - 若 intervalFrames >= IMPACT_DECAY_DFRAME，则直接将 remainingImpactForce = 0；
     *    - 否则从本次命中窗口的基线按线性衰减公式做绝对投影：
     *        projected = baseline × (IMPACT_DECAY_DFRAME - intervalFrames) / IMPACT_DECAY_DFRAME
     *      由于此时 intervalFrames < IMPACT_DECAY_DFRAME，因此系数必然在 (0,1) 区间，保证衰减结果大于 0。
     * 3. 真实命中才更新 lastHitTime，并冻结新的窗口基线。
     *
     * 同时，韧性上限的计算公式为：
     *    韧性上限 = 韧性系数 × 生命值 ÷ 防御伤害比率
     *
     * @param target Object 被命中的目标对象，需具备以下属性：
     *        - 韧性上限
     *        - remainingImpactForce
     *        - 韧性系数
     *        - lastHitTime（上次受击帧数）
     *        - hp（当前生命值）
     *        - 防御力
     */
    public static function refreshImpactForce(target:Object, actualHit:Boolean):Void {
        projectImpactDecayToCurrentFrame(target);

        // 使用当前 HP/防御/韧性重建派生上限。
        refreshImpactDerived(target);

        // 只有真实命中才开启新的冲击残留窗口。MISS 只允许把既有残量衰减到当前帧，
        // 不得靠连续擦碰无限延后衰减。
        if (actualHit !== false) {
            beginImpactDecayWindow(target);
        }
    }

    /**
     * 单独的冲击力衰减方法
     * -----------------------------
     * 此方法仅用于计算并更新目标的剩余冲击力衰减值，而不修改上次受击时间，
     * 便于外部按帧调用以实现逐帧衰减效果。
     *
     * 衰减规则同上：
     * 1. 计算当前帧与上次受击帧的间隔 intervalFrames。
     * 2. 若 intervalFrames > IMPACT_DECAY_FRAME：
     *    - 若 intervalFrames >= IMPACT_DECAY_DFRAME，则直接剩余冲击力归零；
     *    - 否则从窗口基线按照线性衰减公式绝对投影冲击力。
     *
     * @param target Object 需要衰减的目标对象，需具备属性：
     *        - remainingImpactForce
     *        - lastHitTime
     */
    public static function decayImpactForce(target:Object):Void {
        projectImpactDecayToCurrentFrame(target);
        // 先衰减再更新派生显示，避免头顶韧性条永远慢一帧。
        refreshImpactDerived(target);
    }
}
