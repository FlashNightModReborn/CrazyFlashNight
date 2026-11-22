import org.flashNight.arki.unit.UnitAI.Custom.ArmorBreakZombieController;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

class org.flashNight.arki.unit.UnitAI.Custom.ArmorBreakZombieControllerTest {
    private static var passed:Number;
    private static var failed:Number;

    private static function check(value:Boolean, label:String):Void {
        if (value) passed++;
        else {
            failed++;
            trace("[FAIL] ArmorBreakZombieControllerTest " + label);
        }
    }

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        var oldWorld:MovieClip = _root.gameworld;
        var oldEffect:Function = _root.效果;
        var world:MovieClip = _root.createEmptyMovieClip("__armorBreakTestWorld", _root.getNextHighestDepth());
        _root.gameworld = world;
        TargetCacheManager.initialize();
        var effects:Array = [];
        _root.效果 = function(kind:String, x:Number, y:Number, scale:Number, force:Boolean):Void {
            effects.push({kind: kind, x: x, y: y, scale: scale, force: force});
        };
        var target:MovieClip = world.createEmptyMovieClip("armored", world.getNextHighestDepth());
        target.兵种 = ArmorBreakZombieController.KIND;
        target.是否为敌人 = true;
        target.单位编号 = 71;
        target.名字 = "兽化改造僵尸";
        target.hp = 0;
        target.hp满血值 = 2000;
        target._x = 123;
        target._y = 45;
        target._xscale = -100;
        target.Z轴坐标 = 45;
        target.gotoAndStop = function(label:String):Void {
            this.__testFrameLabel = label;
        };

        check(ArmorBreakZombieController.tryIntercept(target) && target.__armorBreakState.active === true,
            "lethal hit enters armor break");
        check(effects.length == 1 && effects[0].kind == "兽化碎裂烟雾" && effects[0].force === true,
            "armor break forces one smoke effect");
        check(effects.length == 1 && effects[0].x == 123 && effects[0].y == 45 && effects[0].scale == -100,
            "smoke keeps world position and direction");
        check(target.状态 == "装甲破裂" && target.__testFrameLabel == "装甲破裂" && target.hp == 1,
            "smoke does not replace existing armor break presentation");
        check(ArmorBreakZombieController.tryIntercept(target) && effects.length == 1,
            "repeated lethal notification does not replay smoke");

        var other:MovieClip = world.createEmptyMovieClip("other", world.getNextHighestDepth());
        other.兵种 = "敌人-普通改造僵尸";
        other.是否为敌人 = true;
        other.hp = 0;
        check(!ArmorBreakZombieController.tryIntercept(other) && effects.length == 1,
            "other enemy kinds do not emit armor break smoke");

        trace("=== ArmorBreakZombieControllerTest result: passed=" + passed + " failed=" + failed + " ===");
        world.removeMovieClip();
        _root.gameworld = oldWorld;
        _root.效果 = oldEffect;
    }
}
