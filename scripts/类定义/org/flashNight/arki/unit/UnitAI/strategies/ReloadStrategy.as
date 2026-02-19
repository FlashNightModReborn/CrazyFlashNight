import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;
import org.flashNight.arki.unit.UnitAI.WeaponEvaluator;

/**
 * ReloadStrategy — 换弹候选源
 *
 * 从 ActionArbiter._collectReload 提取。
 * 职责：在远程姿态 + 弹药不足时注入 Reload 候选。
 *
 * 技能换弹（翻滚换弹等）：
 *   当单位拥有 功能=="换弹" 的技能且可用时，作为 skill 类型候选注入。
 *   高经验单位强烈偏好技能换弹（评分加成），低经验单位退化为普通换弹。
 *   技能换弹走 _scoreCandidates 评分管线，额外获得弹药紧迫度加成。
 */
class org.flashNight.arki.unit.UnitAI.strategies.ReloadStrategy {

    private var p:Object;
    private var _weaponEval:WeaponEvaluator;

    public function ReloadStrategy(personality:Object, weaponEval:WeaponEvaluator) {
        this.p = personality;
        this._weaponEval = weaponEval;
    }

    public function getName():String { return "Reload"; }

    public function collect(ctx:AIContext, data:UnitAIData, out:Array, trace:DecisionTrace):Void {
        // 非远程姿态不换弹
        if (ctx.repositionDir <= 0) { trace.reject("Reload", DecisionTrace.REASON_STANCE); return; }
        // 已在换弹
        if (ctx.isAnimLocked) { trace.reject("Reload", DecisionTrace.REASON_ANIMLOCK); return; }

        var ratio:Number = ctx.ammoRatio;
        if (isNaN(ratio)) ratio = _weaponEval.getAmmoRatio(ctx.self, ctx.attackMode);

        // ── 提前换弹（战术换弹）──
        // 目标：避免“打到一半才没子弹→被迫硬换弹→发呆/被贴脸”的极端情况。
        // 原则：只在 chase 且安全时触发；engage 仍维持 <0.5 的紧急换弹。
        var tactical:Boolean = false;
        var tacticalThreshold:Number = 0.75; // 默认：余弹 <75% 才考虑提前换弹（避免打几枪就换）
        if (ctx.attackMode == "长枪") tacticalThreshold = 0.7;
        else if (ctx.attackMode == "双枪") tacticalThreshold = 0.8;

        if (ratio >= 0.5) {
            // engage 不做提前换弹，避免近身/交战中打断输出
            if (ctx.context != "chase") {
                trace.reject("Reload", DecisionTrace.REASON_AMMO);
                return;
            }
            if (ratio >= tacticalThreshold) {
                trace.reject("Reload", DecisionTrace.REASON_AMMO);
                return;
            }

            // 安全门控：不在受火/包围/子弹逼近下提前换弹
            if (ctx.underFire || ctx.retreatUrgency >= 0.3
                || (ctx.bulletThreat > 0 && ctx.bulletETA < 12)
                || ctx.nearbyCount > 0 || ctx.encirclement > 0.2
                || ctx.self.射击中) {
                trace.reject("Reload", DecisionTrace.REASON_THREAT);
                return;
            }

            // 安全距离：比保持距离更远时才换弹（避免贴身换弹）
            var safeRatio:Number = (ctx.xdistance > 0) ? (ctx.xDist / ctx.xdistance) : 1;
            if (safeRatio <= 1.25) {
                trace.reject("Reload", DecisionTrace.REASON_RANGE);
                return;
            }
            tactical = true;
        }

        // 评分：弹药越少越高 + 距离系数（提前换弹用更温和的紧迫度）
        var urgency:Number = (1 - ratio);
        var safeDist:Number = (ctx.xdistance > 0) ? (ctx.xDist / ctx.xdistance) : 1;
        var distBonus:Number = (safeDist > 1) ? 0.3 : -0.2;
        var score:Number = 0.3 + urgency * 0.5 + distBonus;

        if (tactical) {
            // 将 [0.5, tacticalThreshold) 映射到 [1, 0] 的紧迫度区间（越接近0.5越想换弹）
            var denom:Number = (tacticalThreshold - 0.5);
            var tactUrg:Number = denom > 0 ? ((tacticalThreshold - ratio) / denom) : 0;
            if (tactUrg < 0) tactUrg = 0;
            if (tactUrg > 1) tactUrg = 1;

            // 提前换弹不应压过关键技能：给较低基础分，但在极安全距离时略抬升
            var tacDistBonus:Number = (safeDist > 1.8) ? 0.35 : 0.2;
            score = 0.15 + tactUrg * 0.35 + tacDistBonus;
        }

        // ── 技能换弹 + 普通换弹：双候选竞争设计 ──
        //
        // 意图：技能换弹(type:"skill", score:0) 和 普通换弹(type:"reload", score:preset)
        //       同时注入候选池，通过 Boltzmann 竞争选出一个赢家。
        //       技能换弹 score=0 走 ScoringPipeline 评分管线（AmmoReloadMod 给予加成），
        //       普通换弹 score=preset 跳过管线（ScoringPipeline 对 type:"reload" 直通）。
        //
        // 效果：高经验 AI 的 AmmoReloadMod 加成足以让技能换弹评分超过普通换弹 →
        //       优先使用带闪避/增益的换弹方式；
        //       低经验 AI 加成不足 → 退化为普通换弹。
        //
        // 注意：两者是互斥竞争关系（Boltzmann 只选一个），不会双重执行。
        //       如果改为 if/else 互斥注入，低经验 AI 将无法触发普通换弹兜底。
        var sk:Object = _findReloadSkill(ctx);
        if (sk != null) {
            out.push({
                name: sk.技能名, type: "skill", priority: 1,
                skill: sk, commitFrames: p.skillCommitFrames, score: 0
            });
        }

        out.push({
            name: "Reload", type: "reload", priority: 2,
            commitFrames: p.reloadCommitFrames, score: score
        });
    }

    /**
     * _findReloadSkill — 查找可用的技能换弹（功能=="换弹"）
     *
     * 条件：已学 + CD 就绪 + 距离匹配
     * 返回第一个匹配的技能对象，无匹配返回 null
     */
    private function _findReloadSkill(ctx:AIContext):Object {
        var skills:Array = ctx.self.已学技能表;
        if (skills == null) return null;

        var nowMs:Number = ctx.nowMs;
        var xDist:Number = ctx.xDist;

        for (var i:Number = 0; i < skills.length; i++) {
            var sk:Object = skills[i];
            if (sk.功能 != "换弹") continue;
            if (xDist < sk.距离min || xDist > sk.距离max) continue;
            if (!isNaN(sk.上次使用时间) && (nowMs - sk.上次使用时间 <= sk.冷却 * 1000)) continue;
            return sk;
        }
        return null;
    }
}
