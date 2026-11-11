import org.flashNight.arki.unit.UnitComponent.Routing.*;
import org.flashNight.arki.spatial.move.Mover;
class org.flashNight.arki.unit.UnitComponent.Routing.MovementSkillDirectionTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] MovementSkillDirection " + label); }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        for (var face:Number = 0; face < 2; face++) {
            for (var mask:Number = 0; mask < 16; mask++) {
                var l:Boolean = (mask & 1) != 0;
                var r:Boolean = (mask & 2) != 0;
                var u:Boolean = (mask & 4) != 0;
                var d:Boolean = (mask & 8) != 0;
                var result:Object = MovementSkillDirection.resolve(face == 0 ? "左" : "右",l,r,u,d);
                var x:Number = l == r ? 0 : (l ? -1 : 1);
                var y:Number = u == d ? 0 : (u ? -1 : 1);
                var branch:String = y != 0 ? "side" : (x == (face == 0 ? -1 : 1) ? "forward" : "back");
                check(result.x == x && result.y == y && result.branch == branch,"two axis matrix " + face + "/" + mask);
            }
        }
        var oldStrict:Function = Mover.move2DStrict;
        var oldFast:Function = Mover.move2D;
        var spy:Function = function(target, dir, amount) {
            target.moves.push({direction:dir, distance:amount});
        };
        Mover.move2DStrict = spy; Mover.move2D = spy;
        var unit = {方向:"右", 左行:true,右行:false,上行:false,下行:false,
            技能名:"小跳",moves:[]};
        unit.移动 = function(dir, amount) { this.moves.push({direction:dir, distance:amount}); };
        var man = {_parent:unit,label:"back",gotoAndPlay:function(value){this.label=value;}};
        MovementSkillDirection.capture(unit,"小跳");
        unit.方向 = "左"; unit.左行 = false; unit.右行 = true;
        MovementSkillDirection.begin(man,"side","forward");
        check(man.label == "back", "back animation uses pre-turn facing");
        MovementSkillDirection.move(man,-22);
        check(unit.moves[0].direction == "右" && unit.moves[0].distance == -22,"late input cannot invert backstep");
        check(unit.__movementSkillIntent == undefined,"unit intent consumed once");
        unit.方向="右";unit.左行=true;unit.右行=false;unit.上行=true;
        MovementSkillDirection.capture(unit,"小跳");
        MovementSkillDirection.begin(man,"side","forward");
        check(man.label == "side","reverse diagonal survives startup");
        unit.左行=false;unit.右行=true;unit.上行=false;unit.下行=true;
        unit.moves=[];MovementSkillDirection.move(man,11);
        check(unit.moves.length == 2 && unit.moves[0].direction == "上"
            && unit.moves[1].direction == "左" && unit.moves[1].distance == 11,"diagonal keeps captured axes and distance");
        unit.技能名="战技小跳";unit.方向="左";unit.左行=false;unit.右行=true;unit.上行=false;unit.下行=false;
        MovementSkillDirection.capture(unit,"战技小跳");
        MovementSkillDirection.begin(man,"side","forward");
        unit.moves=[];MovementSkillDirection.move(man,-22);
        check(unit.moves[0].direction == "左" && unit.moves[0].distance == -22,"slide mirrors backstep");
        MovementSkillDirection.capture(unit,"拔刀术");
        check(unit.__movementSkillIntent == undefined,"blade keeps live-turn contract");
        check(!MovementSkillDirection.supports("瞬步斩"),"shunbu keeps live-turn contract");
        Mover.move2DStrict=oldStrict;Mover.move2D=oldFast;
        trace("MovementSkillDirectionTest: " + passed + " passed, " + failed + " failed");
    }
}
