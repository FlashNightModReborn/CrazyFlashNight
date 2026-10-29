/** 旧帧 AI 的可选技能决策；无效辅助量只退回普通攻击，不阻断人物出生或操控。 */
class org.flashNight.arki.unit.UnitAI.behavior.LegacyUnarmedSkillChance {
    public static function limit(chance:Number,weight:Number):Number {
        if (typeof weight != "number" || !isFinite(weight) || weight < 0) return 0;
        return Math.min(chance,100-(Math.sqrt(weight)+5)*2);
    }
}
