import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.render.ChainVisualBridge;
import org.flashNight.arki.item.equipment.PropertyOperators;

/** 真实 CS6 focused：生产更新函数旧路径作 oracle；统计不含 GPU/完整实战。 */
class org.flashNight.arki.bullet.BulletComponent.Chain.ChainAggregateTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var seed:Number;
    private static var randomCalls:Number;
    private static var createdClips:Number;
    private static var clipId:Number;
    private static var prefixOverride:String;
    private static var suffixOverride:String;
    private static var fillOverride:Number;
    private static var scaleXOverride:Number;
    private static var scaleYOverride:Number;

    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] ChainAggregateTest: " + name); }
    }

    private static function randomOffset(span:Number):Number {
        seed = (seed * 1664525 + 1013904223) | 0;
        var unsigned:Number = seed < 0 ? seed + 4294967296 : seed;
        randomCalls++;
        return (unsigned / 4294967296 * 2 - 1) * span;
    }

    private static function acquireClip(type:String):MovieClip {
        createdClips++;
        var zone:MovieClip = _root.gameworld.子弹区域;
        return zone.createEmptyMovieClip("testUnit" + (++clipId), zone.getNextHighestDepth());
    }

    private static function releaseClip(clip:MovieClip):Void { clip.removeMovieClip(); }

    private static function capabilities(capacity:Number):Object {
        return {version:1, mode:"native", maxUnits:15360,
            styles:[{gunChainUnitLinkage:"单元体-普通子弹"}, {gunChainUnitLinkage:"单元体-加强普通子弹"},
                {gunChainUnitLinkage:null}, {gunChainUnitLinkage:null}, {gunChainUnitLinkage:null},
                {gunChainUnitLinkage:"单元体-穿刺子弹"}, {gunChainUnitLinkage:"单元体-次级穿刺子弹"},
                {gunChainUnitLinkage:"单元体-无壳穿刺子弹"}],
            gunChainPrefixes:["横向联弹", "横向机枪联弹", "横向手枪联弹",
                "纵向联弹", "纵向机枪联弹", "纵向手枪联弹"]};
    }

    private static function makeGroup(vertical:Boolean, nativeMode:Boolean, count:Number,
                                      spread:Number, speed:Number, rotation:Number):ChainGroup {
        var kind:String = prefixOverride == null ? (vertical ? "纵向联弹" : "横向联弹") : prefixOverride;
        var suffix:String = suffixOverride == null ? "普通子弹" : suffixOverride;
        var b:Object = {子弹种类:kind + "-" + suffix, baseAsset:kind,
            霰弹值:count, 子弹散射度:spread, xmov:speed, ymov:0,
            _x:0, _y:-100, _rotation:rotation, _xscale:100, _yscale:100,
            _alpha:100, _visible:true, Z轴坐标:0, 每帧补弹数:3.25};
        if (fillOverride > 0) b.每帧补弹数 = fillOverride;
        if (isFinite(scaleXOverride)) b._xscale = scaleXOverride;
        if (isFinite(scaleYOverride)) b._yscale = scaleYOverride;
        var update:Function = vertical ? _root.联弹系统.纵向联弹更新 : _root.联弹系统.横向联弹更新;
        var group:ChainGroup = new ChainGroup(null, b, update, _root.联弹系统.渲染组);
        group.isObject = true;
        group.盒x = vertical ? 7 : -5;
        group.盒y = -5;
        group.盒宽 = 10;
        group.盒高 = 10;
        group.盒固有半宽 = 12.5;
        group.盒固有半高 = 12.5;
        if (nativeMode) ChainVisualBridge.reserveGroup(group);
        var assemble:Function = vertical ? _root.联弹系统.纵向联弹组装 : _root.联弹系统.横向联弹组装;
        assemble(group);
        return group;
    }

    private static function compareGroup(oldGroup:ChainGroup, newGroup:ChainGroup, label:String):Void {
        check(oldGroup.盒x === newGroup.盒x && oldGroup.盒y === newGroup.盒y
            && oldGroup.盒宽 === newGroup.盒宽 && oldGroup.盒高 === newGroup.盒高,
            label + " exact collision rectangle");
        check(oldGroup.bullet.霰弹值 === newGroup.bullet.霰弹值
            && oldGroup.单元体列表.length === newGroup.单元体列表.length,
            label + " scatter and active units");
        check(oldGroup.bullet._x === newGroup.bullet._x && oldGroup.bullet._y === newGroup.bullet._y,
            label + " anchored parent position");
        check(oldGroup.ma === newGroup.ma && oldGroup.mb === newGroup.mb
            && oldGroup.mc2 === newGroup.mc2 && oldGroup.md === newGroup.md,
            label + " exact shared collision/render matrix");
    }

    private static function parityCase(vertical:Boolean, count:Number, spread:Number,
                                       speed:Number, rotation:Number, changeMotion:Boolean):Void {
        ChainVisualBridge.configure(capabilities(4096));
        seed = 19471;
        randomCalls = 0;
        var oldGroup:ChainGroup = makeGroup(vertical, false, count, spread, speed, rotation);
        var expectedSeed:Number = seed;
        var expectedCalls:Number = randomCalls;
        seed = 19471;
        randomCalls = 0;
        var beforeClips:Number = createdClips;
        var newGroup:ChainGroup = makeGroup(vertical, true, count, spread, speed, rotation);
        check(newGroup.nativeGroupOwned && createdClips == beforeClips,
            "native birth does not allocate hidden MC");
        check(seed === expectedSeed && randomCalls === expectedCalls, "birth RNG order");
        check(ChainVisualBridge.flush().indexOf("G,") > 0, "group and birth packet");
        for (var tick:Number = 0; tick < 48; tick++) {
            if (changeMotion && tick == 17) {
                oldGroup.bullet.xmov *= -0.8;
                newGroup.bullet.xmov *= -0.8;
                oldGroup.bullet._rotation += 37;
                newGroup.bullet._rotation += 37;
            }
            if (tick == 23) {
                oldGroup.bullet.霰弹值 -= 2;
                newGroup.bullet.霰弹值 -= 2;
            }
            oldGroup.bullet._x += oldGroup.bullet.xmov;
            newGroup.bullet._x += newGroup.bullet.xmov;
            if (!vertical && tick > 20) {
                oldGroup.bullet._y += 7;
                newGroup.bullet._y += 7;
            }
            seed = 1000 + tick;
            randomCalls = 0;
            var update:Function = oldGroup.update;
            update(oldGroup);
            expectedSeed = seed;
            expectedCalls = randomCalls;
            seed = 1000 + tick;
            randomCalls = 0;
            update(newGroup);
            check(seed === expectedSeed && randomCalls === expectedCalls, "tick " + tick + " RNG order");
            compareGroup(oldGroup, newGroup, (vertical ? "vertical " : "horizontal ") + tick);
            ChainVisualBridge.flush();
        }
        var equal:Boolean = true;
        for (var i:Number = 0; i < newGroup.单元体列表.length; i++) {
            var actual:ChainUnitData = newGroup.单元体列表[i];
            if (newGroup.aggregate) ChainUnitManager.materializeUnit(newGroup, actual);
            var expected:ChainUnitData = oldGroup.单元体列表[i];
            if (actual.x !== expected.x || actual.y !== expected.y || actual.rot !== expected.rot) equal = false;
        }
        check(equal, "final exact local coordinates and reverse removal order");
        ChainUnitManager.removeGroup(oldGroup);
        ChainUnitManager.removeGroup(newGroup);
        ChainVisualBridge.disconnect();
    }

    private static function repeatOracle():Void {
        seed = 90173;
        var allEqual:Boolean = true;
        for (var i:Number = 0; i < 1600; i++) {
            var x:Number = randomOffset(1) * Math.pow(2, (i % 65) - 32);
            var delta:Number = randomOffset(1) * Math.pow(2, (i % 47) - 23);
            var n:Number = i % 1000;
            var expected:Number = x;
            for (var j:Number = 0; j < n; j++) expected += delta;
            var actual:Number = ChainUnitManager.repeatAdd(x, delta, n);
            if (actual !== expected) {
                trace("[REPEAT_MISMATCH] " + i + " x=" + x + " d=" + delta + " n=" + n);
                allEqual = false;
                break;
            }
        }
        check(allEqual, "1600 randomized exact repeated-addition oracles");
        var values:Array = [0, 1, -1, 0.5, -0.5, 1024, -1024];
        var deltas:Array = [0, Math.pow(2, -52), Math.pow(2, -53), 3 * Math.pow(2, -53), 0.1, -0.1];
        allEqual = true;
        for (i = 0; i < values.length; i++) for (j = 0; j < deltas.length; j++) {
            expected = values[i];
            for (var k:Number = 0; k < 4096; k++) expected += deltas[j];
            if (ChainUnitManager.repeatAdd(values[i], deltas[j], 4096) !== expected) allEqual = false;
        }
        check(allEqual, "42 zero, binade, sign and half-ULP ties");
    }

    private static function pressureAndNativeOnly():Void {
        ChainVisualBridge.configure(capabilities(4096));
        seed = 618;
        var beforeClips:Number = createdClips;
        var group:ChainGroup = makeGroup(false, true, 4096, 10, 25, 0);
        group.衰竭计数器 = -10000000;
        group.bullet.Z轴坐标 = 1000000;
        ChainVisualBridge.flush();
        var beforeVisits:Number = group.aggregateVisits;
        var beforeAdds:Number = ChainUnitManager.aggregateAddOperations;
        var maxPayload:Number = 0;
        var started:Number = getTimer();
        for (var tick:Number = 0; tick < 120; tick++) {
            var update:Function = group.update;
            update(group);
            var payload:String = ChainVisualBridge.flush();
            if (length(payload) > maxPayload) maxPayload = length(payload);
        }
        var elapsed:Number = getTimer() - started;
        check(createdClips == beforeClips, "4096 units create zero hidden MovieClips");
        check(group.aggregateVisits - beforeVisits < 300,
            "120 stable horizontal ticks visit two bounds, not 491520 units");
        check(maxPayload < 512, "steady wire has one group, zero per-unit positions");
        trace("[CHAIN_COST] units=4096 ticks=120 boundVisits=" + (group.aggregateVisits - beforeVisits)
            + " scalarAdds=" + (ChainUnitManager.aggregateAddOperations - beforeAdds)
            + " maxSteadyChars=" + maxPayload + " elapsedMs=" + elapsed);
        // Reserve the remaining native budget with one growing vertical group.
        // Reaching the hard boundary must report failure without creating AS2 MCs.
        var filler:ChainGroup = makeGroup(true, true, 11264, 0, 10, 0);
        check(filler.nativeGroupOwned, "expanded native reservation admits 15360 units");
        var overflowBefore:Number = ChainVisualBridge.overflowGroups;
        var over:ChainGroup = makeGroup(false, true, 1, 0, 10, 0);
        check(ChainVisualBridge.overflowGroups == overflowBefore + 1,
            "expanded native reservation rejects the next unit explicitly");
        check(over.单元体列表[0].mc == null && createdClips == beforeClips,
            "capacity failure never constructs a Flash fallback unit");
        ChainVisualBridge.disconnect();
        check(group.单元体列表[0].mc == null && createdClips == beforeClips,
            "disconnect does not recreate retired Flash visuals");
        ChainUnitManager.removeGroup(group);
        ChainUnitManager.removeGroup(filler);
        ChainUnitManager.removeGroup(over);
    }

    private static function styleAndTransformMatrix():Void {
        var names:Array = ["横向联弹", "横向机枪联弹", "横向手枪联弹",
            "纵向联弹", "纵向机枪联弹", "纵向手枪联弹"];
        var styles:Array = ["普通子弹", "加强普通子弹", "穿刺子弹", "次级穿刺子弹", "无壳穿刺子弹"];
        for (var i:Number = 0; i < names.length; i++) {
            prefixOverride = names[i];
            for (var j:Number = 0; j < styles.length; j++) {
                suffixOverride = styles[j];
                // 首帧填满、高速、非等比负缩放、全镜像均走同一生产入口。
                fillOverride = j < 2 ? 128 : 0.25;
                scaleXOverride = j % 2 == 0 ? -150 : 75;
                scaleYOverride = j % 3 == 0 ? -60 : 125;
                parityCase(i > 2, 17, j == 0 ? 0 : 35, i % 2 == 0 ? 360 : -360,
                    j * 47, j == 4);
            }
        }
        prefixOverride = null;
        suffixOverride = null;
        fillOverride = NaN;
        scaleXOverride = NaN;
        scaleYOverride = NaN;
        trace("[CHAIN_MATRIX] prefixes=6 styles=5 combinations=30 ticksEach=48");
    }

    private static function naturalDecayPressure():Void {
        ChainVisualBridge.configure(capabilities(4096));
        seed = 49261;
        var oldGroup:ChainGroup = makeGroup(false, false, 4096, 8, 50, 0);
        seed = 49261;
        var group:ChainGroup = makeGroup(false, true, 4096, 8, 50, 0);
        oldGroup.bullet.Z轴坐标 = 1000000;
        group.bullet.Z轴坐标 = 1000000;
        ChainVisualBridge.flush();
        var beforeVisits:Number = group.aggregateVisits;
        var beforeAdds:Number = ChainUnitManager.aggregateAddOperations;
        var oldMs:Number = 0;
        var newMs:Number = 0;
        var removed:Number = 0;
        var oldUnits:Number = 4096;
        var noBirths:Boolean = true;
        for (var tick:Number = 0; tick < 40; tick++) {
            var update:Function = group.update;
            var started:Number = getTimer();
            update(oldGroup);
            oldMs += getTimer() - started;
            started = getTimer();
            update(group);
            var packet:String = ChainVisualBridge.flush();
            newMs += getTimer() - started;
            if (packet.indexOf(";B,") >= 0) noBirths = false;
            removed += oldUnits - group.单元体列表.length;
            oldUnits = group.单元体列表.length;
            compareGroup(oldGroup, group, "natural decay " + tick);
        }
        check(removed > 1000, "natural 4096 pressure exercises thousands of real removals");
        check(group.aggregateVisits - beforeVisits < 400,
            "real decay event path does not scan all remaining units");
        check(noBirths, "steady decay transmits deletions and group state only");
        trace("[CHAIN_DECAY_COST] units=4096 ticks=40 removed=" + removed
            + " boundVisits=" + (group.aggregateVisits - beforeVisits)
            + " scalarAdds=" + (ChainUnitManager.aggregateAddOperations - beforeAdds)
            + " legacyUpdateMs=" + oldMs + " nativeUpdateAndWireMs=" + newMs);
        ChainUnitManager.removeGroup(oldGroup);
        ChainUnitManager.removeGroup(group);
        ChainVisualBridge.disconnect();
    }

    private static function verticalFilledPressure():Void {
        ChainVisualBridge.configure(capabilities(4096));
        seed = 13498;
        fillOverride = 4096;
        var beforeClips:Number = createdClips;
        var group:ChainGroup = makeGroup(true, true, 2048, 12, 250, 0);
        var update:Function = group.update;
        ChainVisualBridge.flush();
        update(group);
        ChainVisualBridge.flush();
        check(group.count === 2048 && group.单元体列表.length === 2048,
            "high-rate vertical fill completes all 2048 units in one real production update");
        for (var warm:Number = 0; warm < 16; warm++) { update(group); ChainVisualBridge.flush(); }
        var beforeVisits:Number = group.aggregateVisits;
        var beforeAdds:Number = ChainUnitManager.aggregateAddOperations;
        var started:Number = getTimer();
        var maxPayload:Number = 0;
        for (var tick:Number = 0; tick < 120; tick++) {
            update(group);
            var packet:String = ChainVisualBridge.flush();
            if (length(packet) > maxPayload) maxPayload = length(packet);
        }
        var elapsed:Number = getTimer() - started;
        check(group.aggregateVisits - beforeVisits < 8192,
            "filled vertical steady state avoids 245760 per-unit visits");
        check(createdClips == beforeClips && maxPayload < 512,
            "filled vertical stream keeps zero MC and group-only state");
        trace("[CHAIN_VERTICAL_COST] units=2048 ticks=120 boundVisits=" + (group.aggregateVisits - beforeVisits)
            + " scalarAdds=" + (ChainUnitManager.aggregateAddOperations - beforeAdds)
            + " maxSteadyChars=" + maxPayload + " elapsedMs=" + elapsed);
        ChainUnitManager.removeGroup(group);
        ChainVisualBridge.disconnect();
        fillOverride = NaN;
    }

    /** 生产初始化顺序：能力先授予，registerGroup 懒建层/清场后仍必须发 F8。 */
    private static function productionSceneLifecycle():Void {
        var priorWorld:MovieClip = _root.gameworld;
        ChainUnitManager.resetAll();
        ChainVisualBridge.disconnect();
        ChainVisualBridge.configure(capabilities(15360));
        // 参数来自 武器_长枪_压制机枪.xml / 武器_长枪_霰弹枪.xml。
        var cases:Array = [
            {key:"xm214-secondary", prefix:"纵向机枪联弹", suffix:"次级穿刺子弹", style:6, count:5, speed:50, spread:7, mod:true},
            {key:"xm1014-secondary", prefix:"横向联弹", suffix:"次级穿刺子弹", style:6, count:8, speed:36, spread:15, mod:false},
            {key:"xm214-pierce", prefix:"纵向机枪联弹", suffix:"穿刺子弹", style:5, count:5, speed:50, spread:7, mod:true},
            {key:"m134-plain", prefix:"纵向机枪联弹", suffix:"普通子弹", style:0, count:5, speed:50, spread:7, mod:false}
        ];
        var beforeClips:Number = createdClips;
        for (var scene:Number = 0; scene < 2; scene++) {
            var world:MovieClip = _root.createEmptyMovieClip("chainSceneLifecycle" + scene, 76546 + scene);
            world.createEmptyMovieClip("子弹区域", 1);
            _root.gameworld = world;
            for (var i:Number = 0; i < cases.length; i++) {
                var c:Object = cases[i];
                var item:Object = {bullet:c.prefix + "-" + (c.mod ? "普通子弹" : c.suffix)};
                if (c.mod) PropertyOperators.merge(item, {bullet:c.suffix});
                check(item.bullet == c.prefix + "-" + c.suffix, c.key + " production plugin type merge");
                var b:Object = {子弹种类:item.bullet, baseAsset:c.prefix,
                    霰弹值:c.count, 子弹散射度:c.spread, xmov:c.speed, ymov:0,
                    _x:180, _y:110 + i * 100, _rotation:0, _xscale:100, _yscale:100,
                    _alpha:100, _visible:true, Z轴坐标:0, 每帧补弹数:3.25};
                _root.联弹系统.对象联弹初始化(b);
                var g:ChainGroup = b.chainGroup;
                check(g.nativeGroupOwned && g.nativeStyle == c.style && g.单元体列表.length > 0,
                    c.key + " production initializer owns the right style after scene " + scene);
                var packet:String = ChainVisualBridge.flush();
                check(packet != null && packet.indexOf(";G," + g.nativeGroupId + "," + c.style + ",") >= 0
                    && packet.indexOf(";B,") >= 0,
                    c.key + " production registration emits group and births after scene " + scene);
                trace("[CHAIN_SCENE_CASE] " + c.key + " scene=" + scene);
                trace("[CHAIN_SCENE_WIRE] " + packet);
                var update:Function = g.update;
                update(g);
                packet = ChainVisualBridge.flush();
                check(packet != null && packet.indexOf(";G," + g.nativeGroupId + ",") >= 0,
                    c.key + " next production update remains visible after scene " + scene);
                trace("[CHAIN_SCENE_WIRE] " + packet);
                ChainUnitManager.removeGroup(g);
            }
            ChainUnitManager.resetAll();
            var cleared:String = ChainVisualBridge.flush();
            check(cleared != null && cleared.indexOf(";") < 0,
                "scene retirement sends an empty new epoch without requiring new capabilities");
            world.removeMovieClip();
        }
        check(createdClips == beforeClips, "production scene transitions allocate no unit MovieClips");
        var caps:Object = capabilities(15360);caps.mode = "shadow";
        ChainVisualBridge.configure(caps);ChainUnitManager.resetAll();
        check(ChainVisualBridge.flush() == null, "scene reset cannot resume a suspended presentation");
        ChainVisualBridge.disconnect();ChainUnitManager.resetAll();
        check(ChainVisualBridge.flush() == null, "scene reset cannot resume a disconnected transport");
        ChainVisualBridge.configure(capabilities(15360));
        check(ChainVisualBridge.flush() != null, "explicit regrant can resume after scene and transport reset");
        ChainVisualBridge.disconnect();
        _root.gameworld = priorWorld;
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0; createdClips = 0; clipId = 0;
        prefixOverride = null; suffixOverride = null;
        fillOverride = NaN; scaleXOverride = NaN; scaleYOverride = NaN;
        var oldWorld:MovieClip = _root.gameworld;
        var oldTimer:Object = _root.帧计时器;
        var oldRandom:Function = _root.随机偏移;
        var manager:Object = ChainUnitManager;
        var oldAcquire:Function = manager.acquireUnit;
        var oldRelease:Function = manager.releaseUnit;
        var world:MovieClip = _root.createEmptyMovieClip("chainAggregateTestWorld", 76545);
        world.createEmptyMovieClip("子弹区域", 1);
        _root.gameworld = world;
        _root.帧计时器 = {当前帧数:1};
        _root.随机偏移 = randomOffset;
        manager.acquireUnit = acquireClip;
        manager.releaseUnit = releaseClip;
        repeatOracle();
        parityCase(false, 128, 20, 25, 0, false);
        parityCase(false, 31, 60, -18.5, 145, false);
        parityCase(false, 64, 16, 12, 0, true);
        parityCase(true, 31, 15, 25, 0, false);
        parityCase(true, 64, 35, -18.5, 145, false);
        parityCase(true, 31, 15, 25, 0, true);
        pressureAndNativeOnly();
        styleAndTransformMatrix();
        naturalDecayPressure();
        verticalFilledPressure();
        productionSceneLifecycle();
        ChainVisualBridge.disconnect();
        manager.acquireUnit = oldAcquire;
        manager.releaseUnit = oldRelease;
        _root.随机偏移 = oldRandom;
        _root.帧计时器 = oldTimer;
        _root.gameworld = oldWorld;
        world.removeMovieClip();
        trace("ChainAggregateTest Tests Passed: " + passed);
        trace("ChainAggregateTest Tests Failed: " + failed);
    }
}
