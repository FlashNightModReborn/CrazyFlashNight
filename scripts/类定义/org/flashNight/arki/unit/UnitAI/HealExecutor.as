import org.flashNight.arki.unit.UnitAI.UnitAIData;

/**
 * HealExecutor — 血包使用评估与执行
 *
 * 从 UtilityEvaluator 提取的治疗子服务。
 * 职责：evaluateHealNeed() — 评估并执行血包使用
 *
 * 副作用：直接修改 self.血包数量、调用 _root.佣兵使用血包
 * （item 轨独立于 body 轨，不经过候选/评分/Boltzmann 管线）
 */
class org.flashNight.arki.unit.UnitAI.HealExecutor {

    // ── 人格引用 ──
    private var p:Object;

    // ═══════ 构造 ═══════

    public function HealExecutor(personality:Object) {
        this.p = personality;
    }

    // ═══════ 血包评估 ═══════

    /**
     * evaluateHealNeed — 替换 HeroCombatBehavior.evaluateHeal
     *
     * healScore = (1 - hp/maxHP) × healEagerness × 2.0 + 紧急加成
     * healScore > 0.5 → 使用血包
     */
    public function evaluateHealNeed(data:UnitAIData):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 技能/战技播放期：血包动作会打断技能，按"仅技能可取消技能"规则延后
        if (self.状态 == "技能" || self.状态 == "战技") return;

        // 前置条件
        if (self.血包数量 <= 0) return;
        if (currentFrame - self.上次使用血包时间 <= self.血包使用间隔) return;

        var hpRatio:Number = self.hp / self.hp满血值;
        var eagerness:Number = p.healEagerness;
        if (isNaN(eagerness)) eagerness = 0.5;

        var healScore:Number = (1 - hpRatio) * eagerness * 2.0;

        // 紧急加成：血量 < 20%
        if (hpRatio < 0.2) healScore += 1.0;

        // 安全区自动回血
        if (_root.gameworld.允许通行 && self.hp满血值 > self.hp) {
            healScore += 0.6;
        }

        if (healScore > 0.5) {
            var hpBefore:Number = self.hp;
            self.血包数量--;
            _root.佣兵使用血包(self._name);
            self.上次使用血包时间 = currentFrame;
            _root.发布消息(self.名字 + "[" + hpBefore + "/" + self.hp满血值 + "] 紧急治疗后还剩[" + self.血包数量 + "]个治疗包");
        }
    }
}
