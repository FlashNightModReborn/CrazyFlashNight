import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;
import org.flashNight.arki.unit.UnitAI.UnitAIData;

/**
 * ScoringPipeline — 替代 ActionArbiter._scoreCandidates 的评分管线
 *
 * 三段式架构：
 *   1. begin()  — 每个修正器做一次性预计算（存入 scratch）
 *   2. 逐候选   — 基础维度评分 + 修正器管线叠加
 *   3. end()    — 后处理器跨候选二次遍历（反抖动、频率校正）
 *
 * 所有修正器返回纯增量（delta），管线只做加法叠加。
 * scratch 对象跨 tick 复用，零分配。
 */
class org.flashNight.arki.unit.UnitAI.scoring.ScoringPipeline {

    private var _scorer:UtilityEvaluator;
    private var _mods:Array;    // ScoringModifier[] — 逐候选修正器
    private var _posts:Array;   // ScoringModifier[] — 后处理器（仅 end 阶段）
    private var _scratch:Object;

    public function ScoringPipeline(scorer:UtilityEvaluator, mods:Array, posts:Array) {
        this._scorer = scorer;
        this._mods = mods;
        this._posts = posts;
        this._scratch = {};
    }

    /**
     * scoreAll — 对候选列表完成完整评分管线
     *
     * Continue / Reload / PreBuff 的分数已在收集时预设，跳过评分管线。
     * Skill / Attack 走完整维度评分 + 修正器管线 + 后处理。
     */
    public function scoreAll(
        candidates:Array,
        ctx,
        data:UnitAIData,
        self:MovieClip,
        p:Object,
        T:Number,
        trace
    ):Void {
        var scratch:Object = _scratch;
        scratch.T = T;

        var numMods:Number = _mods.length;
        var numPosts:Number = _posts.length;
        var len:Number = candidates.length;

        // ═══ begin phase ═══
        for (var bi:Number = 0; bi < numMods; bi++) {
            _mods[bi].begin(ctx, data, candidates, scratch);
        }
        for (var bpi:Number = 0; bpi < numPosts; bpi++) {
            _posts[bpi].begin(ctx, data, candidates, scratch);
        }

        // ═══ per-candidate scoring ═══
        var evalDepth:Number = p.evalDepth;
        var stance:Object = ctx.stance;

        // 角色技能基础加成（从 personality 读取，替代硬编码 name check）
        var skillBaseBonus:Number = p.skillBaseBonus;
        if (isNaN(skillBaseBonus)) skillBaseBonus = 0;

        // FULL trace: 收集维度分解 + 修正器贡献（仅调试级别有分配开销）
        var fullTrace:Boolean = trace.isFullTrace();

        for (var j:Number = 0; j < len; j++) {
            var c:Object = candidates[j];

            // 预设分数的候选跳过评分管线
            if (c.type == "continue" || c.type == "reload" || c.type == "preBuff") continue;

            var dimScores:Array = fullTrace ? [] : null;

            // ── 基础维度评分 + Stance dimMod ──
            var total:Number = 0;
            for (var d:Number = 0; d < evalDepth; d++) {
                var wKey:String = UtilityEvaluator.DIM_WEIGHTS[d];
                var w:Number = p[wKey];

                if (stance != null) {
                    var dm:Number = stance.dimMod[d];
                    if (!isNaN(dm)) w += dm;
                }

                var dimVal:Number = w * _scorer.scoreDimension(d, c, data, self);
                total += dimVal;
                if (fullTrace) dimScores.push(dimVal);
            }

            // 角色技能基础加成
            if (c.type == "skill" && skillBaseBonus > 0) {
                total += skillBaseBonus;
            }

            // ── 修正器管线 ──
            var modParts:Array = fullTrace ? [] : null;

            for (var m:Number = 0; m < numMods; m++) {
                var delta:Number = _mods[m].modify(c, ctx, p, scratch);
                total += delta;
                if (fullTrace && delta != 0) {
                    var sign:String = delta > 0 ? "+" : "";
                    modParts.push(_mods[m].getName() + "=" + sign
                        + String(Math.round(delta * 100) / 100));
                }
            }

            c.score = total;

            // 暂存诊断信息供 trace recording 使用
            if (fullTrace) {
                c._dimScores = dimScores;
                c._modStr = modParts.join(" ");
            }
        }

        // ═══ end phase (后处理器) ═══
        // FULL trace: 逐 post 快照差分，记录每个后处理器的贡献
        for (var ei:Number = 0; ei < numPosts; ei++) {
            if (fullTrace) {
                for (var snap:Number = 0; snap < len; snap++) {
                    candidates[snap]._beforePost = candidates[snap].score;
                }
            }

            _posts[ei].end(candidates, ctx, p, scratch);

            if (fullTrace) {
                var postName:String = _posts[ei].getName();
                for (var pd:Number = 0; pd < len; pd++) {
                    var postD:Number = candidates[pd].score - candidates[pd]._beforePost;
                    if (postD != 0) {
                        var ps:String = postD > 0 ? "+" : "";
                        var entry:String = postName + "=" + ps
                            + String(Math.round(postD * 100) / 100);
                        if (candidates[pd]._postStr == undefined) {
                            candidates[pd]._postStr = entry;
                        } else {
                            candidates[pd]._postStr += " " + entry;
                        }
                    }
                }
            }
        }

        // ═══ trace recording（所有候选，最终分数）═══
        for (var tr:Number = 0; tr < len; tr++) {
            var tc:Object = candidates[tr];
            trace.scored(tc, tc._dimScores, tc._modStr, tc._postStr);
        }
    }
}
