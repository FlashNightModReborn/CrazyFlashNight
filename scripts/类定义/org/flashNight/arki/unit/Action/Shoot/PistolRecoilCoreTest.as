import org.flashNight.arki.unit.Action.Shoot.ShootCore;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/** 真实 AVM1 + 时间轮回归；射击出口和库存是隔离桩，不操作玩家槽位。 */
class org.flashNight.arki.unit.Action.Shoot.PistolRecoilCoreTest {
    private static var passed:Number;
    private static var failed:Number;

    public static function runAllTests():Void {
        passed = failed = 0;
        var oldWorld:Object = _root.gameworld;
        var oldControl:String = _root.控制目标;
        var oldInventory:Object = _root.物品栏;
        _root.gameworld = {};
        _root.物品栏 = {背包: {getIndexes: function():Array { return []; }}};
        testInterleaved(false);
        testInterleaved(true);
        testAggregateAndFailure();
        testOrdinarySemiAuto();
        testAutomaticInterval();
        testCleanupAndLateCallback();
        testUnloadSamePath();
        EnhancedCooldownWheel.I().reset();
        _root.gameworld = oldWorld;
        _root.控制目标 = oldControl;
        _root.物品栏 = oldInventory;
        trace("--- PistolRecoilCoreTest: " + passed + "/" + (passed + failed) + " passed, " + failed + " failed ---");
    }

    private static function check(value:Boolean, message:String):Void {
        if (value) passed++;
        else { failed++; trace("[TEST_FAIL] PistolRecoilCoreTest: " + message); }
    }

    private static function ticks(count:Number):Void {
        while (count-- > 0) EnhancedCooldownWheel.I().tick();
    }

    private static function fixture(semi:Boolean, gunslinger:Boolean, interval:Number):MovieClip {
        var unit:MovieClip = _root.createEmptyMovieClip("__pistolRecoilProbe", _root.getNextHighestDepth());
        _root.gameworld[unit._name] = unit;
        _root.控制目标 = unit._name;
        unit.攻击模式 = "双枪";
        unit.主手射击中 = unit.副手射击中 = false;
        unit.动作A = unit.动作B = false;
        unit.mainFired = unit.offFired = 0;
        unit.手枪 = {name: "probe-main", value: {shot: 0}};
        unit.手枪2 = {name: "probe-off", value: {shot: 0}};
        unit.手枪弹匣容量 = unit.手枪2弹匣容量 = 100;
        unit.被动技能 = {枪械师: {启用: gunslinger, 等级: 10}};
        unit.dispatcher = {publish: function():Void {}};
        unit.手枪射击 = function():Boolean {
            this.mainFired++; this.手枪.value.shot++; return true;
        };
        unit.手枪2射击 = function():Boolean {
            this.offFired++; this.手枪2.value.shot++; return true;
        };
        var man:MovieClip = unit.createEmptyMovieClip("man", unit.getNextHighestDepth());
        man.gotoAndPlay = function(label:String):Void { this.lastLabel = label; };
        man.射击许可标签 = true;
        man.枪 = {枪: {装扮: {枪口位置: {}}}};
        man.枪2 = {枪: {装扮: {枪口位置: {}}}};
        var data:Object = {interval: interval, singleshoot: semi, clipname: "probe-magazine", split: 1,
            diffusion: 1, sound: "", muzzle: "", bullet: "probe-bullet", velocity: 30,
            bullethit: "", power: 100, bulletsize: 50, impact: 5, targethit: ""};
        ShootInitCore.initWeaponSystem(man, unit, {weaponType: "双枪", isDualGun: true,
            mainWeaponData: data, subWeaponData: data, extraParams: {}});
        return unit;
    }

    private static function dispose(unit:MovieClip):Void {
        ShootCore.cleanup(unit);
        removeMovieClip(unit);
        EnhancedCooldownWheel.I().reset();
    }

    private static function chain(unit:MovieClip, off:Boolean, interval:Number):Void {
        ShootCore._gunslingerDualGunContinuousShoot(unit, unit.man, off ? "手枪2" : "手枪", interval,
            off ? "副手持续射击" : "主手持续射击", off ? "副手射击中" : "主手射击中",
            off ? "动作B" : "动作A", off ? "keepshooting2" : "keepshooting",
            off ? "_gunslingerChain_keepshooting2" : "_gunslingerChain_keepshooting",
            off ? "_semiReleased_keepshooting2" : "_semiReleased_keepshooting");
    }

    private static function testInterleaved(reverse:Boolean):Void {
        var unit:MovieClip = fixture(true, true, 200);
        unit[reverse ? "动作A" : "动作B"] = true;
        unit.man[reverse ? "主手开始射击" : "副手开始射击"]();
        ticks(1);
        unit[reverse ? "动作B" : "动作A"] = true;
        unit.man[reverse ? "副手开始射击" : "主手开始射击"]();
        ticks(8);
        check(unit.mainFired == 2 && unit.offFired == 2, "both production bindings fire twice before release");
        unit.动作A = unit.动作B = false;
        ticks(60);
        check(!unit.主手射击中 && !unit.副手射击中, "neither hand remains shooting after staggered release");
        check(!unit.射击最大后摇中 && !ShootCore.isAnyShooting(unit), "release removes aggregate recoil and the movement-facing gate");
        unit.动作B = true; unit.man.副手开始射击();
        unit.动作B = false; unit.动作A = true; unit.man.主手开始射击();
        check(unit.mainFired == 3 && unit.offFired == 3, "J and K production bindings both accept a fresh press");
        dispose(unit);
    }

    private static function testAggregateAndFailure():Void {
        var unit:MovieClip = fixture(true, true, 200);
        unit.动作A = unit.动作B = true;
        chain(unit, false, 200); chain(unit, true, 600);
        unit.动作A = unit.动作B = false;
        ticks(6);
        check(!unit.主手射击中 && unit.副手射击中 && unit.射击最大后摇中,
            "ending main-hand recoil preserves the longer off-hand recoil");
        ticks(3);
        check(!ShootCore.isAnyShooting(unit) && !unit.射击最大后摇中, "last hand releases the aggregate state");
        unit.动作A = unit.动作B = true;
        chain(unit, false, 200); chain(unit, true, 600);
        unit.man.射击许可标签 = false;
        ShootCore.continuousShoot(unit, "手枪", 200, ShootCore.primaryParams);
        check(!unit.主手射击中 && unit.副手射击中 && unit.射击最大后摇中,
            "one denied lane cannot unlock the other lane");
        unit.man.射击许可标签 = true;
        unit.手枪射击 = function():Boolean { return false; };
        ShootCore.continuousShoot(unit, "手枪", 600, ShootCore.primaryParams);
        check(!unit._shootRecoil_keepshooting.active && unit._shootRecoil_keepshooting.taskLabel.结束射击后摇 == undefined,
            "failed legacy shot does not create a phantom recoil or delayed task");
        ShootCore.continuousShootAs(unit, {params: ShootCore.primaryParams, weaponType: "手枪",
            fireMethodName: "手枪射击", interval: 600, useGlobalRecoilTask: true, recoilPolicy: "aggregate"}, 600);
        check(!unit._shootRecoil_keepshooting.active && unit._shootRecoil_keepshooting.taskLabel.结束射击后摇 == undefined,
            "failed context shot does not create a phantom recoil or delayed task");
        unit.动作A = unit.动作B = false; ticks(8);
        check(!unit.射击最大后摇中, "failed shots cannot extend recoil beyond the surviving hand's completion");
        dispose(unit);
    }

    private static function testOrdinarySemiAuto():Void {
        var unit:MovieClip = fixture(true, false, 200);
        unit.动作A = unit.动作B = true;
        unit.man.主手开始射击(); unit.man.副手开始射击();
        ticks(7);
        unit.man.主手开始射击(); unit.man.副手开始射击();
        check(unit.mainFired == 1 && unit.offFired == 1, "ordinary semi-auto still requires release");
        check(!unit.射击最大后摇中, "ordinary semi-auto does not leave the aggregate recoil latched");
        unit.动作A = unit.动作B = false; ticks(2);
        unit.动作A = unit.动作B = true;
        unit.man.主手开始射击(); unit.man.副手开始射击();
        check(unit.mainFired == 2 && unit.offFired == 2, "ordinary semi-auto rearms each hand after release");
        dispose(unit);
    }

    private static function testAutomaticInterval():Void {
        var unit:MovieClip = fixture(false, false, 600);
        unit.动作A = true; unit.man.主手开始射击();
        ticks(10);
        check(unit.主手射击中 && !unit.射击最大后摇中, "automatic recoil cap preserves the longer fire-rate guard");
        unit.man.主手开始射击();
        check(unit.mainFired == 1, "recoil end cannot create an early automatic shot");
        ticks(9);
        check(unit.mainFired == 2, "automatic repeat still fires at its original interval");
        unit.动作A = false; ticks(20);
        check(!unit.主手射击中 && !unit.射击最大后摇中 && unit.keepshooting == undefined,
            "automatic release retires its repeating task");
        dispose(unit);
    }

    private static function testCleanupAndLateCallback():Void {
        var unit:MovieClip = fixture(true, true, 600);
        unit.动作A = unit.动作B = true;
        chain(unit, false, 600); chain(unit, true, 600);
        var staleLane:Object = unit._shootRecoil_keepshooting;
        ShootCore.cleanupLane(unit, ShootCore.primaryParams);
        check(!unit.主手射击中 && unit.副手射击中 && unit.射击最大后摇中,
            "lane cleanup preserves the other hand's recoil");
        check(staleLane.taskLabel.结束射击后摇 == undefined, "lane cleanup cancels its owner-bound task");
        chain(unit, false, 600);
        ShootCore._endSemiRecoil(unit, "主手射击中", staleLane);
        check(unit.主手射击中 && unit.射击最大后摇中, "late recoil cannot clear a replacement lane");
        ShootCore.cleanup(unit);
        check(!ShootCore.isAnyShooting(unit) && !unit.射击最大后摇中, "reload/equipment cleanup releases all lanes");
        check(unit._shootRecoil_keepshooting == undefined && unit._shootRecoil_keepshooting2 == undefined
            && unit._gunslingerChain_keepshooting == undefined && unit._gunslingerChain_keepshooting2 == undefined,
            "whole cleanup retires recoil owners and continuation tasks");
        unit.主手射击中 = true;
        ShootCore.scheduleRecoil(unit, "keepshooting", 600, "主手射击中");
        ticks(10);
        check(unit.主手射击中 && unit.射击最大后摇中, "cancelled old timers do not release a fresh recoil early");
        dispose(unit);
    }

    private static function testUnloadSamePath():Void {
        var unit:MovieClip = fixture(true, true, 600);
        unit.主手射击中 = true;
        ShootCore.scheduleRecoil(unit, "keepshooting", 150, "主手射击中");
        var oldUnit:MovieClip = unit;
        removeMovieClip(unit);
        unit = fixture(true, true, 600);
        check(oldUnit === unit, "fixture exercises actual AVM1 same-path reference rebinding");
        unit.主手射击中 = true;
        ShootCore.scheduleRecoil(unit, "keepshooting", 300, "主手射击中");
        ticks(5);
        check(unit.主手射击中 && unit.射击最大后摇中, "unloaded unit recoil cannot mutate a new unit at the same path");
        ticks(5);
        check(!unit.主手射击中 && !unit.射击最大后摇中, "replacement unit completes its own recoil");
        dispose(unit);
    }
}
