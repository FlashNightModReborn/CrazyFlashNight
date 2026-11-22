import org.flashNight.arki.unit.UnitComponent.Routing.*;

class org.flashNight.arki.unit.UnitComponent.Routing.AirHandoffTest {
    private static var passed:Number;
    private static var failed:Number;

    private static function check(ok:Boolean, message:String):Void {
        if (ok) {
            passed++;
        } else {
            failed++;
            trace("[FAIL] AirHandoffTest " + message);
        }
    }

    private static function unit(mode:String):MovieClip {
        var depth:Number = _root.getNextHighestDepth();
        var u:MovieClip = _root.createEmptyMovieClip("airHandoff" + depth, depth);
        u.createEmptyMovieClip("man", 1);
        u.hp = 100;
        u.攻击模式 = mode;
        u.状态 = mode + "跳";
        u.Z轴坐标 = 0;
        u.起始Y = 0;
        u.起跳速度 = -12;
        u.垂直速度 = 0;
        u.跳横移速度 = u.跑X速度 = 8;
        u.动画完毕 = _root.主角函数.动画完毕;
        u.状态改变 = _root.主角函数.状态改变;
        u.启动跳跃浮空 = _root.主角函数.启动跳跃浮空;
        return u;
    }

    private static function earlyFinish(mode:String, held:Boolean):Void {
        var u:MovieClip = unit(mode);
        u._y = -40;
        u.右行 = held;
        u.启动跳跃浮空(u.man);
        var source:Object = u.__air.sources.jumpFloat;
        u.动画完毕();
        check(source != undefined && u.状态 == mode + "跳" && u.__air.sources.jumpFloat === source,
              mode + " early finish must keep jump and its source, held=" + held);
        for (var step:Number = 0; step < 20; step++) _root.空中控制器._tick(u);
        check(u._y == u.Z轴坐标 && !u.浮空 && !u.__air.running && u.状态 == mode + (held ? "跑" : "站立"),
              mode + " must land before running/standing, held=" + held + ", y=" + u._y + ", state=" + u.状态);
        u.removeMovieClip();
    }

    private static function sameMan():Void {
        var u:MovieClip = unit("空手");
        u.启动跳跃浮空(u.man);
        var first:Object = u.__air.sources.jumpFloat;
        var finalUnload:Function = u.man.onUnload;
        u.垂直速度 = -12;
        _root.空中控制器.启用跳跃浮空(u, u.man);
        var second:Object = u.__air.sources.jumpFloat;
        var y:Number = u._y;
        _root.空中控制器._tick(u);
        check(first != undefined && second !== first && second.man === u.man && u._y < y,
              "same man re-registers and continues ascending");
        finalUnload.call(u.man);
        check(u.__air.sources.jumpFloat == undefined && !u.__air.running,
              "the same man's final unload releases its latest registration");
        u.removeMovieClip();
    }

    private static function oldUnload():Void {
        var u:MovieClip = unit("空手");
        var oldMan:MovieClip = u.man;
        var nextMan:MovieClip = u.createEmptyMovieClip("nextMan", 2);
        oldMan.onUnload = function():Void {
            u.启动跳跃浮空(nextMan);
            u.刚体 = true;
        };
        u.启动跳跃浮空(oldMan);
        var oldHook:Function = oldMan.onUnload;
        oldHook.call(oldMan);
        var nextSource:Object = u.__air.sources.jumpFloat;
        check(nextSource != undefined && nextSource.man === nextMan && u.浮空 && u.刚体 && u.__air.running,
              "previous unload can install a successor without losing its source or flags");
        nextMan.onUnload();
        delete oldMan.onUnload;
        delete nextMan.onUnload;
        u.removeMovieClip();
    }

    private static function replaceOnLanding(kind:String):Void {
        var u:MovieClip = unit("空手");
        var air:Object = _root.空中控制器;
        u._y = -1;
        u.垂直速度 = 4;
        u.calls = 0;
        var register:Function = function():Void {
            u.calls++;
            u.垂直速度 = -12;
            if (kind == "fastFall") air.启用快速下落(u, u.man, 20, 30);
            if (kind == "knockback") air.启用被击飞浮空(u, u.man);
            if (kind == "jumpFloat") u.启动跳跃浮空(u.man);
            u.registered = u.__air.sources[kind];
        };
        // The substitute for play is deliberately synchronous. Only the
        // controller and registration are production code in that variant.
        if (kind == "fastFall") {
            u.man.play = register;
            air.启用快速下落(u, u.man, 20, 30);
        } else if (kind == "knockback") {
            u.man.受身反制 = true;
            u.动画完毕 = register;
            air.启用被击飞浮空(u, u.man);
        } else {
            u.动画完毕 = register;
            air.启用跳跃浮空(u, u.man);
        }
        check(u.calls == 1 && u.registered != undefined && u.__air.sources[kind] === u.registered,
              kind + " landing callback keeps the replacement source");
        check(u.__air.running && u.taskLabel["__air.step"] != undefined && u._y == 0 && u.垂直速度 == -12,
              kind + " replacement waits for the next scheduled step");
        air.清除源(u, kind);
        u.removeMovieClip();
    }

    public static function runAllTests():Void {
        passed = failed = 0;
        var oldGravity:Object = _root.重力加速度;
        _root.重力加速度 = 4;
        earlyFinish("兵器", true);
        earlyFinish("空手", false);
        sameMan();
        oldUnload();
        replaceOnLanding("jumpFloat");
        replaceOnLanding("fastFall");
        replaceOnLanding("knockback");
        _root.重力加速度 = oldGravity;
        trace("AirHandoffTest: " + passed + " passed, " + failed + " failed");
    }
}
