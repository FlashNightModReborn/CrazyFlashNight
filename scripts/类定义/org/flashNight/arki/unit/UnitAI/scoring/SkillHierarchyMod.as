import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * SkillHierarchyMod — 上位技能抑制
 *
 * 来源：ActionArbiter._scoreCandidates L426-440
 * 同功能(解围霸体) + 更高点数 = 完全上位 → 经验系数惩罚低版本
 * 典型：觉醒霸体(150点) 是 霸体(10点) 的完全上位
 *
 * 优化：begin() 预扫 self.已学技能表，记录每个功能的最大点数（O(skills)）
 *       modify() 直接 O(1) 查 scratch（避免原来每候选遍历全技能表）
 */
class org.flashNight.arki.unit.UnitAI.scoring.SkillHierarchyMod extends ScoringModifier {

    public function getName():String { return "SkillHierarchy"; }

    public function begin(ctx, data, candidates:Array, scratch:Object):Void {
        // 预扫技能表：记录每个功能的最高点数
        var maxPts:Object = {};
        var self:MovieClip = data.self;
        var allSkills:Array = self.已学技能表;
        if (allSkills != null) {
            for (var i:Number = 0; i < allSkills.length; i++) {
                var sk:Object = allSkills[i];
                var func:String = sk.功能;
                var pts:Number = sk.点数;
                if (maxPts[func] == undefined || pts > maxPts[func]) {
                    maxPts[func] = pts;
                }
            }
        }
        scratch._maxPtsByFunc = maxPts;
    }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        if (c.type != "skill" || c.skill.功能 != "解围霸体") return 0;

        var myPts:Number = c.skill.点数;
        var maxPts:Number = scratch._maxPtsByFunc["解围霸体"];
        if (maxPts == undefined || myPts >= maxPts) return 0;

        // 高经验角色几乎不使用低版本；仅在上位技能 CD 中作为紧急突围选择
        return -(p.经验 || 0) * 1.5;
    }
}
