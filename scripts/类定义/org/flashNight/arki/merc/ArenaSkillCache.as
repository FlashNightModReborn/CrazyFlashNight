/**
 * 斗兽标定的技能定义缓存。只在生成/命中时复制标量技能条目，
 * 不让单位可写的冷却和技能等级返回模板；普通游戏缓存不经此入口。
 */
class org.flashNight.arki.merc.ArenaSkillCache {
    public static function makeKey(unitName:String, level:Number, equipmentGroup:Number, technique:Number):String {
        return "arena-skill-v1|" + length(unitName) + ":" + unitName
            + "|l" + level + "|e" + equipmentGroup + "|t" + technique;
    }

    public static function copyForUnit(source:Array):Array {
        var result:Array = [];
        for (var i:Number = 0; i < source.length; i++) {
            var definition:Object = source[i];
            var runtimeSkill:Object = {};
            for (var key:String in definition) {
                if (definition.hasOwnProperty(key)) runtimeSkill[key] = definition[key];
            }
            runtimeSkill.上次使用时间 = NaN;
            result.push(runtimeSkill);
        }
        return result;
    }

    /** 入场一次采样；JSON 只用布尔与普通标量，不发送 NaN。 */
    public static function recordInitialState(unit:Object, table:Array, cacheKey:String, cacheHit:Boolean):Void {
        var signature:String = "";
        var cooldownsClear:Boolean = true;
        for (var i:Number = 0; i < table.length; i++) {
            var skill:Object = table[i];
            var skillName:String = String(skill.技能名);
            signature += length(skillName) + ":" + skillName + ":" + skill.技能等级
                + ":" + skill.冷却 + ":" + skill.消耗 + ":" + skill.点数 + ";";
            if (!isNaN(Number(skill.上次使用时间))) cooldownsClear = false;
        }
        unit._arenaCalibrationSkillState = {
            cacheKey: cacheKey,
            cacheHit: cacheHit,
            skillCount: table.length,
            cooldownsClear: cooldownsClear,
            definitionSignature: signature
        };
    }
}
