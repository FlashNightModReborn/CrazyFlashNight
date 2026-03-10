// File: org/flashNight/arki/component/Damage/DamageResult.as

import org.flashNight.arki.component.Effect.*;

/**
 * DamageResult 类用于存储和处理伤害计算结果。
 * 它包含了伤害值、伤害颜色、伤害大小、伤害效果等信息，并提供了触发伤害显示的功能。
 */
class org.flashNight.arki.component.Damage.DamageResult {

    /**
     * 存储所有伤害值的数组。
     * @type {Array}
     */
    public var totalDamageList:Array;

    /**
     * 伤害显示的字体大小。
     * @type {Number}
     */
    public var damageSize:Number;

    /**
     * 最终的散射值，用于计算伤害的散射效果。
     * @type {Number}
     */
    public var finalScatterValue:Number;

    /**
     * 闪避状态，用于显示是否成功闪避伤害。
     * @type {String}
     */
    public var dodgeStatus:String;

    /**
     * 实际使用的霰弹值。
     * @type {Number}
     */
    public var actualScatterUsed:Number;

    /**
     * 伤害显示的次数。
     * @type {Number}
     */
    public var displayCount:Number;

    /**
     * 联弹分段躲闪：DodgeStateDamageHandle 对联弹提前退出的标记。
     * - true：表示本次联弹命中将由 MultiShotDamageHandle 执行分段躲闪建模（方案B）。
     * - false：表示走旧的全局 dodgeState 流程。
     * @type {Boolean}
     */
    public var deferChainDodgeState:Boolean;

    /**
     * 联弹分段躲闪建模开关（方案B）。
     * 当为 true 且 actualScatterUsed > 1 时，calculateScatterDamage 会使用下方的分布信息生成伤害数字列表。
     * @type {Boolean}
     */
    public var scatterModelEnabled:Boolean;

    /**
     * 方案B：未触发躲闪系统（未躲闪）的段数。
     * @type {Number}
     */
    public var scatterNormalCount:Number;

    /**
     * 方案B：跳弹段数。
     * @type {Number}
     */
    public var scatterBounceCount:Number;

    /**
     * 方案B：过穿段数。
     * @type {Number}
     */
    public var scatterPenetrationCount:Number;

    /**
     * 方案B：MISS 段数（包含“躲闪/直感”等导致伤害为 0 的段）。
     * @type {Number}
     */
    public var scatterMissCount:Number;

    /**
     * 方案B：未躲闪单段伤害（基础值，最终显示会在 calculateScatterDamage 中按护盾/额外伤害统一缩放）。
     * @type {Number}
     */
    public var scatterNormalDamage:Number;

    /**
     * 方案B：跳弹单段伤害（基础值）。
     * @type {Number}
     */
    public var scatterBounceDamage:Number;

    /**
     * 方案B：过穿单段伤害（基础值）。
     * @type {Number}
     */
    public var scatterPenetrationDamage:Number;

    // ==================== 延迟 HTML 构建：结构化效果字段 ====================

    /**
     * 效果位掩码（opt-in 写入）。
     * bit 0 (1):   EF_CRUMBLE   — 溃
     * bit 1 (2):   EF_TOXIC     — 毒
     * bit 2 (4):   EF_EXECUTE   — 斩
     * bit 3 (8):   EF_DMG_TYPE_LABEL — 真/魔法属性标签
     * bit 4 (16):  EF_CRUSH_LABEL    — 破击属性标签
     * bit 5 (32):  EF_LIFESTEAL      — 吸血
     * bit 7 (128): isEnemy（用于 EF_EXECUTE 颜色选择）
     * bit 8 (256): EF_SHIELD         — 护盾吸收
     * @type {Number}
     */
    public var _efFlags:Number;

    /** 属性文本（真/魔法/破击共用），仅 EF_DMG_TYPE_LABEL 或 EF_CRUSH_LABEL 置位时有效 */
    public var _efText:String;

    /** 破击 emoji（✨ 或 ☠），仅 EF_CRUSH_LABEL 置位时有效 */
    public var _efEmoji:String;

    /** 每弹吸血量，仅 EF_LIFESTEAL 置位时有效 */
    public var _efLifeSteal:Number;

    /** 每弹盾吸收量，仅 EF_SHIELD 置位时有效 */
    public var _efShieldAbsorb:Number;

    /** 颜色枚举 ID（0-10，索引 HitNumberBatchProcessor.COLOR_TABLE），由 Handle 直写 */
    public var _dmgColorId:Number;

    /**
     * 静态实例，表示一个默认的伤害结果。
     * @type {DamageResult}
     */

    // 用于计算复用
    public static var IMPACT:DamageResult = new DamageResult();

    // 联弹/多段建模专用 IMPACT（避免在非联弹热路径上清洗额外字段）
    public static var IMPACT_CHAIN:DamageResult = new DamageResult();

    // 只用于传递无伤害的情况，注意不可更改
    public static var NULL:DamageResult = new DamageResult();

    /**
     * DamageResult 类的构造函数。
     * 初始化所有属性为默认值。
     */
    public function DamageResult() {
        this.reset();
    }

    /**
     * 重置所有属性为默认值。
     */
    public function reset():Void {
        this.totalDamageList = [];
        this.damageSize = 28;
        this.finalScatterValue = 0;
        this.dodgeStatus = "";
        this.actualScatterUsed = 1;
        this.displayCount = 1;

        // 联弹分段躲闪建模（方案B）相关字段重置
        this.deferChainDodgeState = false;
        this.scatterModelEnabled = false;
        this.scatterNormalCount = 0;
        this.scatterBounceCount = 0;
        this.scatterPenetrationCount = 0;
        this.scatterMissCount = 0;
        this.scatterNormalDamage = 0;
        this.scatterBounceDamage = 0;
        this.scatterPenetrationDamage = 0;

        // 延迟 HTML 构建字段重置
        this._efFlags = 0;
        this._dmgColorId = 0;
        this._efText = null;
        this._efEmoji = null;
        this._efLifeSteal = 0;
        this._efShieldAbsorb = 0;
    }

    /**
     * 获取可复用的 IMPACT 实例（用于计算复用，避免频繁创建对象）
     */
    public static function getIMPACT():DamageResult {
        var r:DamageResult = DamageResult.IMPACT;

        // 复用数组，避免频繁创建造成GC压力
        r.totalDamageList.length = 0;
        r.damageSize = 28;
        r.finalScatterValue = 0;
        r.dodgeStatus = "";
        r.actualScatterUsed = 1;
        r.displayCount = 1;

        // 延迟 HTML 构建：仅需重置位掩码和颜色 ID（槽值由 _efFlags 守护，无需重置）
        r._efFlags = 0;
        r._dmgColorId = 0;

        return r;
    }

    /**
     * 获取可复用的联弹 IMPACT 实例（用于联弹分段躲闪建模，避免污染普通 IMPACT）。
     */
    public static function getIMPACT_CHAIN():DamageResult {
        var r:DamageResult = DamageResult.IMPACT_CHAIN;

        // 复用数组，避免频繁创建造成GC压力
        r.totalDamageList.length = 0;
        r.damageSize = 28;
        r.finalScatterValue = 0;
        r.dodgeStatus = "";
        r.actualScatterUsed = 1;
        r.displayCount = 1;

        // 联弹分段躲闪建模相关标记（计数/单段伤害不必清零：仅在 scatterModelEnabled 为 true 时被消费）
        r.deferChainDodgeState = false;
        r.scatterModelEnabled = false;

        // 延迟 HTML 构建：仅需重置位掩码和颜色 ID
        r._efFlags = 0;
        r._dmgColorId = 0;

        return r;
    }

    /**
     * 添加一个伤害值到伤害列表中。
     * @param {Number} damage - 要添加的伤害值。
     */
    public function addDamageValue(damage:Number):Void {
        var list = this.totalDamageList;
        list[list.length] = damage;
    }

    /**
     * 兼容联弹处理逻辑，将伤害结果推入堆栈准备显示
     *
     * @param remainingDamage 待处理的伤害数值
     * @param damageSize 伤害数字大小
     * @return
     */
    public function calculateScatterDamage(remainingDamage:Number):Void {
        // 设置显示次数为实际使用的霰弹值
        this.displayCount = this.actualScatterUsed;

        var actualScatterUsed:Number = this.actualScatterUsed;

        // ==================== 方案B：联弹分段躲闪建模 ====================
        // MultiShotDamageHandle 会在联弹命中时写入分布信息；这里统一生成伤害数字列表，
        // 并将护盾吸收、毒/溃等额外伤害一起纳入最终显示（通过按比例缩放实现）。
        if (actualScatterUsed > 1 && this.scatterModelEnabled) {
            // 目标总伤害（与扣血一致）：按位运算取整，避免浮点误差
            var total:Number = remainingDamage | 0;
            if (total < 0) total = 0;

            var list:Array = this.totalDamageList;
            list.length = 0;

            // 读取并修正计数（保护：防止异常值导致越界）
            var missCount:Number = this.scatterMissCount | 0;
            var bounceCount:Number = this.scatterBounceCount | 0;
            var penCount:Number = this.scatterPenetrationCount | 0;
            var normalCount:Number = this.scatterNormalCount | 0;

            if (missCount < 0) missCount = 0;
            if (bounceCount < 0) bounceCount = 0;
            if (penCount < 0) penCount = 0;
            if (normalCount < 0) normalCount = 0;

            // 修正总和，优先补到 normal（模型来源可信，但仍做防御）
            var diff:Number = actualScatterUsed - (missCount + bounceCount + penCount + normalCount);
            if (diff != 0) {
                normalCount += diff;
                if (normalCount < 0) normalCount = 0;
            }

            // total<=0 的显示策略：
            // - 若模型判断为全MISS，则输出全MISS
            // - 否则输出全0（如护盾全吸收）
            var i:Number;
            if (total <= 0) {
                if (missCount >= actualScatterUsed) {
                    for (i = 0; i < actualScatterUsed; i++) {
                        list[list.length] = -1;
                    }
                } else {
                    for (i = 0; i < actualScatterUsed; i++) {
                        list[list.length] = 0;
                    }
                }
                return;
            }

            // 构造基础列表（不含护盾/额外伤害，之后统一缩放到 total）
            var baseNormal:Number = this.scatterNormalDamage | 0;
            var baseBounce:Number = this.scatterBounceDamage | 0;
            var basePen:Number = this.scatterPenetrationDamage | 0;
            if (baseNormal < 0) baseNormal = 0;
            if (baseBounce < 0) baseBounce = 0;
            if (basePen < 0) basePen = 0;

            // 轮转填充，使不同分支尽量交错（不引入额外随机）
            var idx:Number = 0;
            while (idx < actualScatterUsed) {
                if (bounceCount > 0) {
                    list[idx++] = baseBounce;
                    bounceCount--;
                    if (idx >= actualScatterUsed) break;
                }
                if (penCount > 0) {
                    list[idx++] = basePen;
                    penCount--;
                    if (idx >= actualScatterUsed) break;
                }
                if (normalCount > 0) {
                    list[idx++] = baseNormal;
                    normalCount--;
                    if (idx >= actualScatterUsed) break;
                }
                if (missCount > 0) {
                    list[idx++] = -1; // 负数用于触发 MISS 显示
                    missCount--;
                }

                // 防止在所有计数耗尽时进入死循环
                if (bounceCount <= 0 && penCount <= 0 && normalCount <= 0 && missCount <= 0) {
                    break;
                }
            }

            // 计算正值和（MISS 为负数，忽略）
            var sumPos:Number = 0;
            for (i = 0; i < actualScatterUsed; i++) {
                var v:Number = list[i];
                if (v > 0) sumPos += v;
            }

            // 若无正伤害但 total>0，回退到旧的随机拆分逻辑
            // 典型场景：全MISS但后续处理器追加了额外伤害（如击溃），此时分段建模已失去意义
            if (sumPos <= 0) {
                list.length = 0;
                for (i = 0; i < actualScatterUsed - 1; i++) {
                    var fluctuatedDamage:Number = (remainingDamage / (actualScatterUsed - i)) * (100 + _root.随机偏移(50 / actualScatterUsed)) / 100;
                    if (fluctuatedDamage != fluctuatedDamage) fluctuatedDamage = 0;
                    list[list.length] = fluctuatedDamage | 0;
                    remainingDamage -= fluctuatedDamage;
                }
                if (remainingDamage != remainingDamage) remainingDamage = 0;
                list[list.length] = remainingDamage | 0;
                return;
            }

            // 按比例缩放到 total：保留分支相对差异，同时与护盾/额外伤害对齐
            // 使用"累积取整"避免额外数组与最大余数扫描：O(n) 且无额外分配，适合热路径
            var unit:Number = total / sumPos;
            var acc:Number = 0;
            var accFloor:Number = 0;
            var lastPosIndex:Number = -1;

            for (i = 0; i < actualScatterUsed; i++) {
                v = list[i];
                if (v > 0) {
                    acc += v * unit;
                    var newFloor:Number = acc | 0;
                    list[i] = newFloor - accFloor;
                    accFloor = newFloor;
                    lastPosIndex = i;
                }
            }

            // ========== 形式化证明：leftover ≥ 0 恒成立 ==========
            //
            // 【前提条件】
            // - total ≥ 0（第263-264行保证：total = remainingDamage | 0; if (total < 0) total = 0）
            // - sumPos > 0（第350行 if (sumPos <= 0) 已提前 return）
            // - AS2 Number 为 IEEE 754 双精度浮点（53位尾数）
            // - x | 0 对于 |x| < 2³¹ 等价于 sign(x) * floor(|x|)，即向零截断
            //   本场景 acc ≥ 0，故 acc | 0 = floor(acc)
            //
            // 【定理】leftover = total - accFloor ≥ 0
            //
            // 【证明】
            // 设正值段的基础伤害为 v₁, v₂, ..., vₖ（均为正整数），sumPos = Σvᵢ。
            // 令 unit = total / sumPos，则理论累积值：
            //     acc_exact = Σvᵢ × unit = sumPos × (total / sumPos) = total
            //
            // 【浮点误差分析】
            // IEEE 754 双精度：机器精度 ε_mach = 2⁻⁵² ≈ 2.2×10⁻¹⁶
            // 单次乘法相对误差 ≤ ε_mach，单次加法相对误差 ≤ ε_mach
            // k 次累加的误差上界（Higham 误差分析）：|acc - acc_exact| ≤ k × acc_exact × ε_mach
            //
            // 【本项目数值范围】
            // - k ≤ 100（联弹段数实际上限，由霰弹值决定）
            // - total ≤ 10⁶（单次伤害合理上限）
            // - 绝对误差 ≤ 100 × 10⁶ × 2.2×10⁻¹⁶ ≈ 2.2×10⁻⁸ << 1
            //
            // 因此 |acc - total| < 1，即 total - 1 < acc < total + 1。
            // 由 accFloor = floor(acc)（见前提），且 acc < total + 1，
            // 得 accFloor ≤ total（因 accFloor, total 均为整数）。
            //
            // 因此 leftover = total - accFloor ≥ 0。                              ∎
            //
            // 【推论】leftover ∈ {0, 1}，无需处理 leftover < 0 的情况。
            // ============================================================
            var leftover:Number = total - accFloor;
            if (leftover > 0 && lastPosIndex >= 0) {
                list[lastPosIndex] = (list[lastPosIndex] | 0) + leftover;
            }

            return;
        }
        // ==================== 分段躲闪建模结束 ====================

        // 旧逻辑：随机拆分总伤害为多个散射伤害
        if (actualScatterUsed > 1) {
            for (var i:Number = 0; i < actualScatterUsed - 1; i++) {
                // 计算波动伤害（保留原随机逻辑）
                var fluctuatedDamage:Number = (remainingDamage / (actualScatterUsed - i)) * (100 + _root.随机偏移(50 / actualScatterUsed)) / 100;

                // 处理非法值并添加伤害
                if (fluctuatedDamage != fluctuatedDamage) fluctuatedDamage = 0;
                this.addDamageValue(fluctuatedDamage | 0);
                remainingDamage -= fluctuatedDamage;
            }
        }

        // 添加最后的剩余伤害
        if (remainingDamage != remainingDamage) remainingDamage = 0;
        this.addDamageValue(remainingDamage | 0);
    }

    /**
     * 触发伤害显示功能，将伤害值显示在指定的坐标位置。
     *
     * 伤害数字不会立即渲染，而是以标量快照形式加入批处理队列，
     * 在帧末由 HitNumberBatchProcessor.flush() 统一处理。
     * - 将节流决策从 O(N) 降至 O(1)
     * - 统一视野剔除，减少重复计算
     * - 更精确地控制同屏数字数量
     * - 先剔除后构建 HTML，被丢弃的项零 HTML 成本
     *
     * @param {Number} targetX - 伤害显示的X坐标。
     * @param {Number} targetY - 伤害显示的Y坐标。
     */
    public function triggerDisplay(targetX:Number, targetY:Number):Void {
        var list:Array = this.totalDamageList;
        var len:Number = list.length;

        if (len === 0) {
            return;
        }

        // 预打包标量快照
        var efFlags:Number = this._efFlags;
        var packed:Number = efFlags | (((this.dodgeStatus == "MISS") ? 1 : 0) << 9) | ((this.damageSize | 0) << 10) | (this._dmgColorId << 18);

        // 预取效果槽值（仅对应 flags 位为 1 时有意义）
        var efText:String = ((efFlags & 8) != 0 || (efFlags & 16) != 0) ? this._efText : null;
        var efEmoji:String = ((efFlags & 16) != 0) ? this._efEmoji : null;
        var lifeSteal:Number = ((efFlags & 32) != 0) ? this._efLifeSteal : 0;
        var shieldAbsorb:Number = ((efFlags & 256) != 0) ? this._efShieldAbsorb : 0;

        // 标量快照入队，延迟 HTML 构建到 flush 阶段
        var i:Number = 0;
        do {
            HitNumberBatchProcessor.enqueueRaw(
                list[i], packed,
                efText, efEmoji,
                lifeSteal, shieldAbsorb,
                targetX, targetY
            );
            i++;
        } while (i < len);
    }

    /**
     * 返回一个字符串，表示当前 DamageResult 对象的状态。
     * @return {String} 包含所有伤害相关信息的字符串。
     */
    public function toString():String {
        var result:String = "DamageResult {\n";
        result += "  totalDamageList: " + this.totalDamageList.toString() + ",\n";
        result += "  _dmgColorId: " + this._dmgColorId + ",\n";
        result += "  damageSize: " + this.damageSize + ",\n";
        result += "  _efFlags: " + this._efFlags + ",\n";
        result += "  finalScatterValue: " + this.finalScatterValue + ",\n";
        result += "  dodgeStatus: " + this.dodgeStatus + ",\n";
        result += "  actualScatterUsed: " + this.actualScatterUsed + ",\n";
        result += "  displayCount: " + this.displayCount + "\n";
        result += "}";
        return result;
    }
}
