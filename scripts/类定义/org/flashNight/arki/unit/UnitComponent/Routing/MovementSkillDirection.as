import org.flashNight.arki.spatial.move.Mover;

/** 小跳/闪现/滑步共用一次起手选择。其他动作继续使用各自的逐帧转向。 */
class org.flashNight.arki.unit.UnitComponent.Routing.MovementSkillDirection {
    public static function supports(skillName:String):Boolean {
        return skillName == "小跳" || skillName == "闪现" || skillName == "战技小跳";
    }

    public static function resolve(facing:String, left:Boolean, right:Boolean,
            up:Boolean, down:Boolean):Object {
        var horizontal:Number = left == right ? 0 : (right ? 1 : -1);
        var vertical:Number = up == down ? 0 : (down ? 1 : -1);
        var forward:Number = facing == "左" ? -1 : 1;
        return {facing: facing == "左" ? "左" : "右", x: horizontal, y: vertical,
            branch: vertical != 0 ? "side" : (horizontal == forward ? "forward" : "back")};
    }

    public static function capture(unit:MovieClip, skillName:String):Void {
        delete unit.__movementSkillIntent;
        if (!supports(skillName)) return;
        var intent:Object = resolve(unit.方向, Boolean(unit.左行), Boolean(unit.右行),
            Boolean(unit.上行), Boolean(unit.下行));
        intent.skillName = skillName;
        unit.__movementSkillIntent = intent;
    }

    public static function begin(man:MovieClip, sideLabel:String, forwardLabel:String):Void {
        var unit:MovieClip = man._parent;
        var intent:Object = unit.__movementSkillIntent;
        if (intent == null || intent.skillName != unit.技能名) {
            capture(unit, unit.技能名);
            intent = unit.__movementSkillIntent;
        }
        if (intent == null) return;
        man.__movementSkillIntent = intent;
        delete unit.__movementSkillIntent;
        // 跳帧会卸载当前 load 事件；需要的数据均在跳转前安装。
        if (intent.branch == "side") man.gotoAndPlay(sideLabel);
        else if (intent.branch == "forward") man.gotoAndPlay(forwardLabel);
    }

    public static function move(man:MovieClip, distance:Number):Void {
        var intent:Object = man.__movementSkillIntent;
        if (intent == null || !isFinite(distance)) return;
        var unit:MovieClip = man._parent;
        var amount:Number = Math.abs(distance);
        var mover:Function = distance > 100 ? Mover.move2D : Mover.move2DStrict;
        if (intent.branch == "back") {
            mover(unit, intent.facing, -amount);
        } else if (intent.branch == "forward") {
            mover(unit, intent.facing, amount);
        } else {
            // 沿用纵向分支原来的两轴距离及碰撞入口，不做归一化或额外增速。
            unit.移动(intent.y < 0 ? "上" : "下", amount);
            if (intent.x != 0) mover(unit, intent.x < 0 ? "左" : "右", amount);
        }
    }
}
