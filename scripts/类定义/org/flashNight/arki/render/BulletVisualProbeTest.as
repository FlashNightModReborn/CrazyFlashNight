import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitData;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitManager;
import org.flashNight.arki.render.BulletVisualProbe;

class org.flashNight.arki.render.BulletVisualProbeTest {
    private static var passed:Number;
    private static var failed:Number;

    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else {
            failed++;
            trace("[TEST_FAIL] BulletVisualProbeTest: " + name);
        }
    }

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        var oldWorld:MovieClip = _root.gameworld;
        var oldTimer:Object = _root.帧计时器;
        var world:MovieClip = _root.createEmptyMovieClip("bulletVisualTestWorld", 76545);
        var zone:MovieClip = world.createEmptyMovieClip("子弹区域", 1);
        var holder:MovieClip = world.createEmptyMovieClip("normalBullets", 2);
        _root.gameworld = world;
        _root.帧计时器 = {当前帧数:123};

        var caps:Object = {
            version:1, mode:"native",
            styles:[{ordinaryLinkage:"普通子弹", gunChainUnitLinkage:"单元体-普通子弹"}],
            gunChainPrefixes:["纵向联弹"]
        };
        BulletVisualProbe.configure(caps);
        var bullets:Array = [];
        for (var i:Number = 0; i < 257; i++) {
            var bullet:MovieClip = holder.createEmptyMovieClip("b" + i, i + 1);
            bullet.子弹种类 = "普通子弹";
            bullet._x = i;
            bullet._alpha = 100;
            bullet._visible = true;
            bullets[i] = bullet;
            BulletVisualProbe.registerNormal(bullet);
        }
        BulletVisualProbe.flush();
        check(bullets[0]._alpha === 0 && bullets[255]._alpha === 0,
            "first 256 normal bullets are native-owned");
        check(bullets[256]._alpha === 100 && bullets[256].__nativeVisualOwned === false,
            "257th normal bullet remains visible in Flash");
        BulletVisualProbe.disconnect();
        check(bullets[0]._alpha === 100 && bullets[255]._alpha === 100,
            "socket detach restores currently owned normal bullets");
        check(bullets[256]._alpha === 100, "overflow bullet stays visible on detach");

        BulletVisualProbe.configure(caps);
        BulletVisualProbe.registerNormal(bullets[0]);
        BulletVisualProbe.flush();
        check(bullets[0]._alpha === 0, "native capability can own a fresh instance");
        caps.mode = "shadow";
        BulletVisualProbe.configure(caps);
        check(bullets[0]._alpha === 100 && bullets[0].__nativeVisualOwned === false,
            "capability revoke restores current normal bullet");
        holder.removeMovieClip();

        var host:Object = {_visible:true, _alpha:100, 子弹种类:"纵向联弹-普通子弹"};
        var group:ChainGroup = new ChainGroup(null, host, null, null);
        group.isObject = true;
        group.子弹种类 = "普通子弹";
        group.nativeVisualOwned = true;
        var unitA:ChainUnitData = new ChainUnitData();
        var unitB:ChainUnitData = new ChainUnitData();
        unitA.mc = zone.createEmptyMovieClip("chainUnitA", 3);
        unitB.mc = zone.createEmptyMovieClip("chainUnitB", 4);
        unitA.mc._x = 10;
        unitB.mc._x = 20;
        unitA.mc._visible = false;
        unitB.mc._visible = false;
        group.单元体列表[0] = unitA;
        group.单元体列表[1] = unitB;
        ChainUnitManager.registerGroup(group);
        var styles:Object = {};
        styles["单元体-普通子弹"] = 0;
        var prefixes:Object = {};
        prefixes["纵向联弹"] = true;
        var entries:Array = [];
        entries.length = 254;
        var result:Object = ChainUnitManager.appendVisualShadow(entries, styles, prefixes, 256, true);
        check(entries.length === 256 && result.count === 2 && result.overflow === 0,
            "two-unit group fits exactly at 256");
        check(group.nativeVisualOwned && !unitA.mc._visible && !unitB.mc._visible,
            "fitting group remains exclusively native-owned");
        ChainUnitManager.restoreNativeVisuals();
        check(!group.nativeVisualOwned && unitA.mc._visible && unitB.mc._visible,
            "group revoke restores both Flash units");

        group.nativeVisualOwned = true;
        unitA.mc._visible = false;
        unitB.mc._visible = false;
        entries.length = 255;
        result = ChainUnitManager.appendVisualShadow(entries, styles, prefixes, 256, true);
        check(entries.length === 255 && result.count === 0 && result.overflow === 2,
            "257 boundary returns the whole group");
        check(!group.nativeVisualOwned && unitA.mc._visible && unitB.mc._visible,
            "whole-group overflow leaves no hidden unit");
        ChainUnitManager.removeGroup(group);
        BulletVisualProbe.disconnect();
        world.removeMovieClip();
        _root.gameworld = oldWorld;
        _root.帧计时器 = oldTimer;
        trace("BulletVisualProbeTest Tests Passed: " + passed);
        trace("BulletVisualProbeTest Tests Failed: " + failed);
    }
}
