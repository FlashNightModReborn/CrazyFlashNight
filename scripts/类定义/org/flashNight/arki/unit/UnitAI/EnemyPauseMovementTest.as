class org.flashNight.arki.unit.UnitAI.EnemyPauseMovementTest {
    private static var passed:Number;
    private static var failed:Number;

    private static function check(value:Boolean, label:String):Void {
        if (value) passed++;
        else {
            failed++;
            trace("[FAIL] EnemyPauseMovementTest " + label);
        }
    }

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        var oldPause:Boolean = _root.暂停;
        var oldWorld:MovieClip = _root.gameworld;
        var world:MovieClip = _root.createEmptyMovieClip("__enemyPauseWorld", _root.getNextHighestDepth());
        _root.gameworld = world;
        var unit:MovieClip = world.createEmptyMovieClip("unit", world.getNextHighestDepth());
        var man:MovieClip = unit.createEmptyMovieClip("man", 1);
        unit.攻击模式 = "空手";
        unit.状态 = "空手行走";
        unit._x = 100;
        unit._y = unit.Z轴坐标 = 200;
        unit.行走X速度 = 6;
        unit.行走Y速度 = 3;
        unit.跑X速度 = 12;
        unit.跑Y速度 = 6;
        unit.方向改变 = function(direction:String):Void { this.方向 = direction; };
        unit.移动 = function(direction:String, speed:Number):Void {
            if (direction == "右") this._x += speed;
            else if (direction == "左") this._x -= speed;
            else if (direction == "下") this._y = this.Z轴坐标 += speed;
            else if (direction == "上") this._y = this.Z轴坐标 -= speed;
        };
        unit.状态改变 = _root.敌人函数.状态改变;
        unit.行走 = _root.敌人函数.行走;
        var rootStops:Number = 0;
        var rootPlays:Number = 0;
        var manStops:Number = 0;
        var manPlays:Number = 0;
        unit.stop = function():Void { rootStops++; };
        unit.play = function():Void { rootPlays++; };
        man.stop = function():Void { manStops++; };
        man.play = function():Void { manPlays++; };

        unit.右行 = true;
        unit.行走();
        check(unit._x == 106 && unit.状态 == "空手行走", "ordinary walking consumes direction and moves");

        _root.暂停 = true;
        unit.行走();
        check(unit._x == 106 && !unit.右行 && !unit.左行 && !unit.上行 && !unit.下行,
            "pause blocks displacement and clears direction flags");
        check(rootStops == 1 && manStops == 1 && unit.状态 == "空手行走",
            "pause freezes the current walking timelines once");
        unit.行走();
        check(rootStops == 1 && manStops == 1 && unit._x == 106,
            "repeated paused frames do not retrigger stop or movement");

        _root.暂停 = false;
        unit.行走();
        check(rootPlays == 1 && manPlays == 1 && unit._x == 106,
            "resume plays only the frozen timelines");
        check(unit.状态 == "空手站立" && unit.__enemyPauseWalkState == undefined,
            "resume settles to standing after clearing movement input");

        _root.暂停 = true;
        unit.行走();
        check(rootStops == 1 && manStops == 1,
            "standing pause does not stop unrelated timelines");

        _root.暂停 = false;
        unit.右行 = true;
        unit.状态 = "空手跑";
        unit.行走();
        check(unit._x == 118 && unit.状态 == "空手跑", "ordinary running keeps its existing movement speed");
        _root.暂停 = true;
        unit.行走();
        check(rootStops == 2 && manStops == 2 && unit.状态 == "空手跑" && unit._x == 118,
            "running uses the same pause freeze contract");
        _root.暂停 = false;
        unit.行走();
        check(rootPlays == 2 && manPlays == 2 && unit.状态 == "空手站立",
            "running resumes its own frozen timelines");

        unit.右行 = true;
        unit.行走();
        _root.暂停 = true;
        unit.行走();
        unit.状态 = "击倒";
        _root.暂停 = false;
        unit.行走();
        check(rootPlays == 2 && manPlays == 2,
            "state changed during pause is not revived by stale playback");

        trace("=== EnemyPauseMovementTest result: passed=" + passed + " failed=" + failed + " ===");
        _root.暂停 = oldPause;
        _root.gameworld = oldWorld;
        world.removeMovieClip();
    }
}
