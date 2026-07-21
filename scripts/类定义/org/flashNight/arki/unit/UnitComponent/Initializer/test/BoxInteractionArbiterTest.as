import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.BoxInteractionArbiter;

import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.InteractionHandler;

/** BoxInteractionArbiter A01-A12 + A03F 契约测试。 */
class org.flashNight.arki.unit.UnitComponent.Initializer.test.BoxInteractionArbiterTest {

    private static var assertionCount:Number = 0;
    private static var caseCount:Number = 0;

    public static function runAllTests():Void {
        assertionCount = 0;
        caseCount = 0;
        trace("=== BoxInteractionArbiter Test Suite (A01-A12 + A03F) ===");
        testA01AllowList();
        testA02RejectsUnknownPresets();
        testA03IdempotentRegistrationAndCleanup();
        testA03FRegistrationFailureNeverFallsBack();
        testA04NearestDistanceWins();
        testA05RegistrationOrderBreaksTie();
        testA06NonFiniteDistanceIsFarthest();
        testA07TwoGridBoxesHaveOneWinner();
        testA08GridAndDirectDropHaveOneWinner();
        testA09TwoDirectDropBoxesHaveOneWinner();
        testA10SceneInteractionHasPriority();
        testA11LegacyElementStillConsumes();
        testA12GroundPickupStillConsumes();
        trace("BoxInteractionArbiterTest: " + caseCount + "/13 cases, " +
            assertionCount + " assertions passed");
    }

    private static function testA01AllowList():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var presets:Array = ["保险柜", "生存箱", "装备箱", "资源箱", "纸箱", "隐藏资源点"];
        for (var i:Number = 0; i < presets.length; i++) {
            var target:Object = makeTarget(world, presets[i], i + 1, 0, 2, 4);
            assertTrue("A01", BoxInteractionArbiter.isBoxPreset(presets[i]),
                "allow-list should contain " + presets[i]);
            assertTrue("A01", BoxInteractionArbiter.register(target, world),
                "allowed preset should register: " + presets[i]);
            emit(world, hero, null);
            assertTrue("A01", target.dispatcher.pickUpCount == 1,
                "allowed preset should become a candidate: " + presets[i]);
            BoxInteractionArbiter.unregister(target);
        }
        disposeWorld(world);
        finishCase();
    }

    private static function testA02RejectsUnknownPresets():Void {
        var world:Object = makeWorld();
        var unknown:Object = makeTarget(world, "未知箱", 0, 0, 2, 4);
        var missing:Object = makeTarget(world, null, 0, 0, 2, 4);
        var projector:Object = makeTarget(world, "投影召唤器", 0, 0, 4, 8);
        assertTrue("A02", !BoxInteractionArbiter.register(unknown, world),
            "unknown preset must fail closed");
        assertTrue("A02", !BoxInteractionArbiter.register(missing, world),
            "missing preset must fail closed");
        assertTrue("A02", !BoxInteractionArbiter.register(projector, world),
            "row/col must not turn a projector into a box");
        assertTrue("A02", world.dispatcher.subscribeCount == 0,
            "invalid targets must not initialize a global listener");
        disposeWorld(world);
        finishCase();
    }

    private static function testA03IdempotentRegistrationAndCleanup():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var first:Object = makeTarget(world, "保险柜", 10, 0, 4, 8);
        var second:Object = makeTarget(world, "装备箱", -10, 0, 2, 4);
        assertTrue("A03", BoxInteractionArbiter.register(first, world), "first register");
        assertTrue("A03", BoxInteractionArbiter.register(first, world), "duplicate register");
        assertTrue("A03", BoxInteractionArbiter.register(second, world), "second register");
        assertTrue("A03", world.dispatcher.subscribeCount == 1,
            "one gameworld must have one arbiter listener");
        assertTrue("A03", BoxInteractionArbiter.__getKnownRecordCount(world) == 2,
            "two targets must create exactly two known records");

        BoxInteractionArbiter.unregister(first);
        BoxInteractionArbiter.register(first, world);
        emit(world, hero, null);
        assertTrue("A03", first.dispatcher.pickUpCount == 1 &&
            second.dispatcher.pickUpCount == 0,
            "re-register must reuse first order without duplicate records");
        assertTrue("A03", BoxInteractionArbiter.__getKnownRecordCount(world) == 2,
            "unregister and re-register must reuse the known record");

        BoxInteractionArbiter.forget(first);
        assertTrue("A03", BoxInteractionArbiter.__getKnownRecordCount(world) == 1,
            "target unload forget must release the destroyed target reference");
        var replacement:Object = makeTarget(world, "保险柜", 10, 0, 4, 8);
        BoxInteractionArbiter.register(replacement, world);
        assertTrue("A03", BoxInteractionArbiter.__getKnownRecordCount(world) == 2,
            "replacement target must not grow known records beyond live target count");
        emit(world, hero, null);
        assertTrue("A03", second.dispatcher.pickUpCount == 1 &&
            replacement.dispatcher.pickUpCount == 0,
            "replacement after unload must receive a later order than surviving targets");

        BoxInteractionArbiter.unregister(replacement);
        BoxInteractionArbiter.unregister(second);
        emit(world, hero, null);
        assertTrue("A03", first.dispatcher.pickUpCount == 1 &&
            second.dispatcher.pickUpCount == 1 && replacement.dispatcher.pickUpCount == 0,
            "target cleanup must leave zero submissions");

        BoxInteractionArbiter.cleanup(world);
        assertTrue("A03", world.dispatcher.unsubscribeCount == 1 &&
            world.dispatcher.handlers.length == 0,
            "scene cleanup must remove exactly the arbiter listener");
        finishCase();
    }

    /**
     * 中央监听注册失败时，明确箱型必须 fail closed；禁止回落到旧的逐 target
     * interactionKeyDown 监听，否则同一输入会再次触发多箱 fan-out。
     */
    private static function testA03FRegistrationFailureNeverFallsBack():Void {
        var oldWorld:Object = _root.gameworld;
        var worldDispatcher:Object = {subscribeCount: 0};
        worldDispatcher.subscribeGlobal = function(
                eventName:String, callback:Function, scope:Object):Boolean {
            this.subscribeCount++;
            return false;
        };
        worldDispatcher.unsubscribeGlobal = function():Boolean { return true; };
        var world:Object = {dispatcher: worldDispatcher};

        var localDispatcher:Object = {
            globalSubscribeCount: 0,
            localSubscribeCount: 0,
            pickUpCount: 0
        };
        localDispatcher.subscribeGlobal = function(
                eventName:String, callback:Function, scope:Object):Boolean {
            this.globalSubscribeCount++;
            return true;
        };
        localDispatcher.unsubscribeGlobal = function():Boolean { return true; };
        localDispatcher.subscribe = function(
                eventName:String, callback:Function, scope:Object):Boolean {
            this.localSubscribeCount++;
            return true;
        };
        localDispatcher.unsubscribe = function():Boolean { return true; };
        localDispatcher.unsubscribeAll = function():Void {};
        localDispatcher.publish = function(eventName:String, value:Object):Void {
            if (eventName == "pickUpBox") this.pickUpCount++;
        };

        var target:MovieClip = _root.createEmptyMovieClip(
            "__boxInteractionA03FTarget", _root.getNextHighestDepth());
        target.presetName = "保险柜";
        target.dispatcher = localDispatcher;

        try {
            _root.gameworld = world;
            InteractionHandler.initialize(target);
            assertTrue("A03F", worldDispatcher.subscribeCount == 1,
                "recognized box must attempt the central arbiter exactly once");
            assertTrue("A03F", localDispatcher.globalSubscribeCount == 0,
                "central registration failure must not install a per-target global listener");
            assertTrue("A03F", localDispatcher.localSubscribeCount == 0 &&
                    localDispatcher.pickUpCount == 0,
                "failed arbiter registration must install no local pickup wiring or pickup");
            assertTrue("A03F", target.__cf7InteractionHandlerInitialized !== true &&
                    target.__cf7InteractionHandlerDispatcher === undefined,
                "failed wiring must leave no initialized or dispatcher marker");
            assertTrue("A03F", BoxInteractionArbiter.__getKnownRecordCount(world) == 0,
                "failed central subscription must retain no target record");
        } finally {
            InteractionHandler.cleanup(target);
            BoxInteractionArbiter.cleanup(world);
            target.removeMovieClip();
            _root.gameworld = oldWorld;
        }
        finishCase();
    }

    private static function testA04NearestDistanceWins():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var nearBox:Object = makeTarget(world, "生存箱", 5, 0, 4, 4);
        var farBox:Object = makeTarget(world, "装备箱", 25, 0, 2, 4);
        BoxInteractionArbiter.register(farBox, world);
        BoxInteractionArbiter.register(nearBox, world);
        emit(world, hero, null);
        assertSingleWinner("A04", nearBox, farBox, "smaller squared distance must win");
        disposeWorld(world);
        finishCase();
    }

    private static function testA05RegistrationOrderBreaksTie():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var first:Object = makeTarget(world, "保险柜", 10, 0, 4, 8);
        var second:Object = makeTarget(world, "生存箱", -10, 0, 4, 4);
        BoxInteractionArbiter.register(first, world);
        BoxInteractionArbiter.register(second, world);
        // swap-and-pop 后重注册使遍历顺序变成 second,first，但 order 不变。
        BoxInteractionArbiter.unregister(first);
        BoxInteractionArbiter.register(first, world);
        emit(world, hero, null);
        assertSingleWinner("A05", first, second,
            "registrationOrder must break ties independently of enumeration order");
        disposeWorld(world);
        finishCase();
    }

    private static function testA06NonFiniteDistanceIsFarthest():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var invalid:Object = makeTarget(world, "保险柜", 0, 0, 4, 8);
        invalid._x = Number("not-a-number");
        var normal:Object = makeTarget(world, "生存箱", 20, 0, 4, 4);
        BoxInteractionArbiter.register(invalid, world);
        BoxInteractionArbiter.register(normal, world);
        emit(world, hero, null);
        assertSingleWinner("A06", normal, invalid,
            "finite distance must beat NaN without comparison drift");
        disposeWorld(world);
        finishCase();
    }

    private static function testA07TwoGridBoxesHaveOneWinner():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var first:Object = makeTarget(world, "保险柜", 5, 0, 4, 8);
        var second:Object = makeTarget(world, "装备箱", 10, 0, 2, 4);
        BoxInteractionArbiter.register(first, world);
        BoxInteractionArbiter.register(second, world);
        emit(world, hero, null);
        assertSingleWinner("A07", first, second, "one input must submit one grid box");
        BoxInteractionArbiter.unregister(first);
        emit(world, hero, null);
        assertTrue("A07", second.dispatcher.pickUpCount == 1,
            "unselected grid box must remain available for a later input");
        second._killed = true;
        emit(world, hero, null);
        assertTrue("A07", second.dispatcher.pickUpCount == 1,
            "ordinary killed targets remain rejected unless loot authority proves the exact suspended anchor");
        disposeWorld(world);
        finishCase();
    }

    private static function testA08GridAndDirectDropHaveOneWinner():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var direct:Object = makeTarget(world, "资源箱", 4, 0, 0, 0);
        var grid:Object = makeTarget(world, "保险柜", 12, 0, 4, 8);
        BoxInteractionArbiter.register(grid, world);
        BoxInteractionArbiter.register(direct, world);
        emit(world, hero, null);
        assertSingleWinner("A08", direct, grid,
            "selected direct-drop box alone must receive legacy pickUpBox");
        assertTrue("A08", direct.row == 0 && direct.col == 0,
            "arbiter must not rewrite direct-drop shape");
        disposeWorld(world);
        finishCase();
    }

    private static function testA09TwoDirectDropBoxesHaveOneWinner():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var first:Object = makeTarget(world, "纸箱", 3, 0, 0, 0);
        var second:Object = makeTarget(world, "隐藏资源点", 8, 0, 0, 0);
        BoxInteractionArbiter.register(first, world);
        BoxInteractionArbiter.register(second, world);
        emit(world, hero, null);
        assertSingleWinner("A09", first, second,
            "one input must submit only one direct-drop box");
        disposeWorld(world);
        finishCase();
    }

    private static function testA10SceneInteractionHasPriority():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var box:Object = makeTarget(world, "保险柜", 2, 0, 4, 8);
        BoxInteractionArbiter.register(box, world);
        emit(world, hero, {name: "scene-interaction"});
        assertTrue("A10", box.dispatcher.pickUpCount == 0,
            "SceneInteractionManager.currentMC must suppress all box submissions");
        disposeWorld(world);
        finishCase();
    }

    private static function testA11LegacyElementStillConsumes():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var first:Object = makeTarget(world, "生存箱", 2, 0, 4, 4);
        var second:Object = makeTarget(world, "装备箱", 5, 0, 2, 4);
        BoxInteractionArbiter.register(first, world);
        BoxInteractionArbiter.register(second, world);
        var legacy:Object = {count: 0};
        world.dispatcher.subscribeGlobal("interactionKeyDown", function():Void {
            legacy.count++;
        }, legacy);
        emit(world, hero, null);
        assertTrue("A11", legacy.count == 1, "non-box legacy consumer must still run");
        assertTrue("A11", first.dispatcher.pickUpCount + second.dispatcher.pickUpCount == 1,
            "legacy co-consumption must not cause a second box winner");
        disposeWorld(world);
        finishCase();
    }

    private static function testA12GroundPickupStillConsumes():Void {
        var world:Object = makeWorld();
        var hero:Object = makeHero();
        var first:Object = makeTarget(world, "纸箱", 2, 0, 0, 0);
        var second:Object = makeTarget(world, "资源箱", 5, 0, 0, 0);
        BoxInteractionArbiter.register(first, world);
        BoxInteractionArbiter.register(second, world);
        var pickup:Object = {count: 0};
        world.dispatcher.subscribeGlobal("interactionKeyDown", function():Void {
            pickup.count++;
        }, pickup);
        emit(world, hero, null);
        assertTrue("A12", pickup.count == 1, "ground pickup consumer must still run");
        assertTrue("A12", first.dispatcher.pickUpCount + second.dispatcher.pickUpCount == 1,
            "ground pickup co-consumption must not cause a second box winner");
        disposeWorld(world);
        finishCase();
    }

    private static function makeWorld():Object {
        return {dispatcher: makeGlobalDispatcher()};
    }

    private static function makeGlobalDispatcher():Object {
        var dispatcher:Object = {
            handlers: [],
            subscribeCount: 0,
            unsubscribeCount: 0
        };
        dispatcher.subscribeGlobal = function(
            eventName:String, callback:Function, scope:Object):Boolean {
            this.handlers.push({eventName: eventName, callback: callback, scope: scope});
            this.subscribeCount++;
            return true;
        };
        dispatcher.unsubscribeGlobal = function(
            eventName:String, callback:Function, scope:Object):Boolean {
            for (var i:Number = 0; i < this.handlers.length; i++) {
                var item:Object = this.handlers[i];
                if (item.eventName == eventName && item.callback === callback &&
                    item.scope === scope) {
                    this.handlers.splice(i, 1);
                    this.unsubscribeCount++;
                    return true;
                }
            }
            return false;
        };
        dispatcher.emit = function():Void {
            var snapshot:Array = this.handlers.slice(0);
            for (var i:Number = snapshot.length - 1; i >= 0; i--) {
                snapshot[i].callback.call(snapshot[i].scope);
            }
        };
        return dispatcher;
    }

    private static function makeHero():Object {
        var area:Object = {};
        area.hitTest = function(other:Object):Boolean { return true; };
        return {_x: 0, Z轴坐标: 0, area: area};
    }

    private static function makeTarget(
        world:Object, preset:String, x:Number, z:Number,
        row:Number, col:Number):Object {
        var localDispatcher:Object = {pickUpCount: 0, lastTarget: null};
        localDispatcher.publish = function(eventName:String, target:Object):Void {
            if (eventName == "pickUpBox") {
                this.pickUpCount++;
                this.lastTarget = target;
            }
        };
        return {
            _parent: world,
            _x: x,
            Z轴坐标: z,
            presetName: preset,
            row: row,
            col: col,
            area: {},
            interactionEnabled: true,
            pickupEnabled: true,
            _killed: false,
            dispatcher: localDispatcher
        };
    }

    private static function emit(
        world:Object, hero:Object, sceneCurrent:Object):Void {
        BoxInteractionArbiter.__setTestInteractionContext(hero, sceneCurrent);
        try {
            world.dispatcher.emit();
        } finally {
            BoxInteractionArbiter.__clearTestInteractionContext();
        }
    }

    private static function disposeWorld(world:Object):Void {
        BoxInteractionArbiter.__clearTestInteractionContext();
        BoxInteractionArbiter.cleanup(world);
    }

    private static function assertSingleWinner(
        id:String, winner:Object, loser:Object, message:String):Void {
        assertTrue(id, winner.dispatcher.pickUpCount == 1 &&
            loser.dispatcher.pickUpCount == 0 &&
            winner.dispatcher.lastTarget === winner, message);
    }

    private static function finishCase():Void {
        caseCount++;
    }

    private static function assertTrue(
        id:String, condition:Boolean, message:String):Void {
        assertionCount++;
        if (!condition) throw new Error(
            "BoxInteractionArbiterTest " + id + ": " + message);
    }
}
