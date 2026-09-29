import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitData;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitManager;
import org.flashNight.arki.render.BulletVisualProbe;
import org.flashNight.arki.render.ChainVisualBridge;
import org.flashNight.arki.render.FrameBroadcaster;

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

    // Observe actual F5 bytes after the production broadcaster consumes its slot.
    private static function wireEpoch():Number {
        BulletVisualProbe.flush();
        FrameBroadcaster.send();
        var message:String = _root.server.last;
        var start:Number = message.indexOf("\x05");
        check(start >= 0, "production broadcaster emits F5");
        return Number(message.substring(start + 1).split("|")[0]);
    }

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        var oldWorld:MovieClip = _root.gameworld;
        var oldTimer:Object = _root.帧计时器;
        var oldServer:Object = _root.server;
        _root.server = {
            isSocketConnected:true, fault:"", last:"",
            sendSocketMessage:function(message:String):Boolean { this.last = message; return true; },
            sendServerMessage:function(message:String):Void { this.fault += message + "\n"; }
        };
        var world:MovieClip = _root.createEmptyMovieClip("bulletVisualTestWorld", 76545);
        var zone:MovieClip = world.createEmptyMovieClip("子弹区域", 1);
        var holder:MovieClip = world.createEmptyMovieClip("normalBullets", 2);
        _root.gameworld = world;
        _root.帧计时器 = {当前帧数:123};

        // 配对错误：缺容量字段的能力载荷必须报告一次且通道保持关闭。
        BulletVisualProbe.configure({
            version:1, mode:"native",
            styles:[{ordinaryLinkage:"普通子弹", gunChainUnitLinkage:"单元体-普通子弹"}],
            gunChainPrefixes:["纵向联弹"]
        });
        check(_root.server.last === "Vbullet|caps_invalid",
            "invalid caps reports a bullet channel fault on the controlled fast lane");

        var caps:Object = {
            version:1, mode:"native", maxOrdinary:1024, maxTotal:16384,
            styles:[{ordinaryLinkage:"普通子弹", gunChainUnitLinkage:"单元体-普通子弹"}],
            gunChainPrefixes:["纵向联弹"]
        };
        BulletVisualProbe.configure(caps);
        var firstEpoch:Number = wireEpoch();
        var bullets:Array = [];
        for (var i:Number = 0; i < 1025; i++) {
            var bullet:MovieClip = holder.createEmptyMovieClip("b" + i, i + 1);
            bullet.子弹种类 = "普通子弹";
            bullet._x = i;
            bullet._alpha = 100;
            bullet._visible = true;
            bullets[i] = bullet;
            BulletVisualProbe.registerNormal(bullet);
        }
        BulletVisualProbe.flush();
        check(bullets[0]._alpha === 0 && bullets[1024]._alpha === 0
            && bullets[1024].__nativeVisualOwned === true,
            "over-limit normal bullet stays native-owned; host rejects the packet");
        BulletVisualProbe.disconnect();
        check(bullets[0]._alpha === 0 && bullets[0].__nativeVisualOwned === true
            && bullets[1024]._alpha === 0,
            "socket detach keeps hidden native ownership for resync");

        // 正常挂起语义：native -> shadow -> native 之间所有权与隐藏状态保留。
        BulletVisualProbe.configure(caps);
        var secondEpoch:Number = wireEpoch();
        check(secondEpoch > firstEpoch, "reconnected F5 belongs to a fresh epoch");
        caps.mode = "shadow";
        BulletVisualProbe.configure(caps);
        check(bullets[0]._alpha === 0 && bullets[0].__nativeVisualOwned === true,
            "presentation suspend keeps native ownership");
        FrameBroadcaster.send();
        check(_root.server.last.indexOf("\x05") < 0,
            "suspended presentation emits no F5 section");
        caps.mode = "native";
        BulletVisualProbe.configure(caps);
        check(wireEpoch() > secondEpoch, "presentation resume uses a newer epoch");
        BulletVisualProbe.disconnect();
        holder.removeMovieClip();

        // ChainVisualBridge 配对协议：霰弹峰值增长在总预算 15360 内有界再预留；
        // 耗尽保持原生所有权并致命报告一次，绝不回交 AS2 画法。
        ChainVisualBridge.resetScene();
        ChainVisualBridge.disconnect();
        ChainVisualBridge.configure({
            version:1, mode:"native", maxUnits:15360,
            styles:[{gunChainUnitLinkage:"单元体-普通子弹"}],
            gunChainPrefixes:["纵向联弹"]
        });
        var chainHost:Object = {_visible:true, _alpha:100, 子弹种类:"纵向联弹-普通子弹", 霰弹值:2};
        var chainGroup:ChainGroup = new ChainGroup(null, chainHost, null, null);
        chainGroup.isObject = true;
        check(ChainVisualBridge.reserveGroup(chainGroup) === true
            && chainGroup.nativeGroupOwned === true && chainGroup.nativeReserved === 2,
            "bridge reserves the group scatter peak");
        chainGroup.单元体列表[0] = new ChainUnitData();
        chainGroup.单元体列表[1] = new ChainUnitData();
        var extraUnit:ChainUnitData = new ChainUnitData();
        chainGroup.单元体列表[2] = extraUnit;
        ChainVisualBridge.addUnit(chainGroup, extraUnit);
        check(chainGroup.nativeGroupOwned === true && chainGroup.nativeReserved === 3
            && extraUnit.nativeLive === true,
            "growing scatter peak re-reserves within total budget");
        var hugeHost:Object = {_visible:true, _alpha:100, 子弹种类:"纵向联弹-普通子弹", 霰弹值:15360};
        var hugeGroup:ChainGroup = new ChainGroup(null, hugeHost, null, null);
        hugeGroup.isObject = true;
        check(ChainVisualBridge.reserveGroup(hugeGroup) === true
            && hugeGroup.nativeGroupOwned === true
            && _root.server.last === "Vchain|reserve_overflow",
            "reservation exhaustion stays native-owned and reports a fatal fault");
        ChainVisualBridge.resetScene();
        ChainVisualBridge.disconnect();
        world.removeMovieClip();
        _root.gameworld = oldWorld;
        _root.帧计时器 = oldTimer;
        _root.server = oldServer;
        trace("BulletVisualProbeTest Tests Passed: " + passed);
        trace("BulletVisualProbeTest Tests Failed: " + failed);
    }
}
