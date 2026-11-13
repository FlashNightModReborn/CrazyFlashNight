import org.flashNight.arki.hud.FocusTargetHudService;
import org.flashNight.arki.hud.PlayerHudService;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.StageEventHandler;
import org.flashNight.arki.scene.StageEvent;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

class org.flashNight.arki.hud.FocusTargetHudTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("FAIL FocusTargetHudTest: " + message); }
    }
    private static function checkSubstageBirths(world:MovieClip):Void {
        var spawner:Object = org.flashNight.arki.scene.WaveSpawner.getInstance();
        var oldSpawnWorld:MovieClip = spawner.gameworld;
        var oldWaves:Array = spawner.waveInfo;
        var oldSpawn:Function = _root.加载游戏世界人物;
        var map:MovieClip = world.createEmptyMovieClip("地图", world.getNextHighestDepth());
        try {
            spawner.gameworld = world;
            spawner.waveInfo = [[{SpawnIndex:-1, InstanceName:"waveHud", Parameters:{focusHudRole:"protect"}, x:5, y:10}]];
            _root.加载游戏世界人物 = function(id:String, name:String, depth:Number, params:Object):MovieClip {
                var actor:MovieClip = _root.gameworld.createEmptyMovieClip(name, depth);
                for (var key:String in params) actor[key] = params[key];
                actor.version = 1; actor.hp = 90; actor.hp满血值 = 100;
                return actor;
            };
            var oldScope:Object = FocusTargetHudService.activateScope(world, "scope-run", 0);
            spawner.spawn({兵种名:"hud-check"}, 0, 0, 1, 0);
            var event:StageEvent = new StageEvent({EventName:"Start", Enemy:[
                {spritename:"hud-check", InstanceName:"eventHud", x:10, y:15, Parameters:{focusHudRole:"boss"}},
                {spritename:"hud-check", InstanceName:"unmarkedHud", x:12, y:15}
            ]});
            event.execute();
            var waveActor:MovieClip = world.waveHud;
            var eventActor:MovieClip = world.eventHud;
            check(oldScope != null && waveActor.__stageFocusScope === oldScope && eventActor.__stageFocusScope === oldScope,
                "wave and event both carry the exact pre-attach scope");
            check(world.unmarkedHud._parent === world && world.unmarkedHud.__stageFocusScope === undefined,
                "unmarked event actor has no scope field");
            FocusTargetHudService.onUnitInitialized(waveActor);
            check(FocusTargetHudService.snapshotList(null, 8) == null, "not-ready stamped actor stays hidden");
            waveActor.__unitInitializedVersion = 1;
            FocusTargetHudService.onUnitInitialized(waveActor);
            var oldId:Number = FocusTargetHudService.snapshotList(null, 8)[0].id;
            check(oldId > 0 && FocusTargetHudService.activateScope(world, "scope-run", 0) === oldScope,
                "duplicate activation preserves the active row and identity");
            var oldLease:Object = FocusTargetHudService.bindInitialized(waveActor, "protect", "");
            var nextScope:Object = FocusTargetHudService.activateScope(world, "scope-run", 1);
            eventActor.__unitInitializedVersion = 1;
            FocusTargetHudService.onUnitInitialized(eventActor);
            waveActor.version = 2; waveActor.__unitInitializedVersion = 2;
            FocusTargetHudService.onUnitInitialized(waveActor);
            check(nextScope !== oldScope && nextScope.worldIdentity === oldScope.worldIdentity
                && oldScope.closed && FocusTargetHudService.snapshotList(null, 8) == null,
                "late ready and reinit from the previous substage cannot bind in the reused world");
            world.unmarkedHud.focusHudRole = "boss";
            world.unmarkedHud.__unitInitializedVersion = 1;
            FocusTargetHudService.onUnitInitialized(world.unmarkedHud);
            check(FocusTargetHudService.snapshotList(null, 8) == null, "tagged actor without pre-attach origin stays out");
            spawner.waveInfo[0][0].InstanceName = "nextHud";
            spawner.spawn({兵种名:"hud-check"}, 0, 0, 1, 0);
            world.nextHud.__unitInitializedVersion = 1;
            FocusTargetHudService.onUnitInitialized(world.nextHud);
            var nextId:Number = FocusTargetHudService.snapshotList(null, 8)[0].id;
            FocusTargetHudService.endEncounter(oldScope);
            check(!FocusTargetHudService.clear(oldLease) && nextId > oldId && FocusTargetHudService.snapshotList(null, 8)[0].id === nextId,
                "stale close and old lease leave the next substage target intact");
            FocusTargetHudService.endEncounter(nextScope);
            FocusTargetHudService.activateScope(world, "scope-run", 1);
            FocusTargetHudService.onUnitInitialized(world.nextHud);
            check(nextScope.closed && FocusTargetHudService.snapshotList(null, 8) == null,
                "duplicate activation cannot reopen the accepted terminal substage");
            var freshRun:Object = FocusTargetHudService.activateScope(world, "another-run", 1);
            check(freshRun !== nextScope && !freshRun.closed, "new run with the same world and ordinal receives a fresh scope");
        } finally {
            spawner.gameworld = oldSpawnWorld;
            spawner.waveInfo = oldWaves;
            _root.加载游戏世界人物 = oldSpawn;
            map.removeMovieClip();
        }
    }

    public static function runAllTests():Void {
        passed = failed = 0;
        var oldWorld:MovieClip = _root.gameworld;
        var oldControl:String = _root.控制目标;
        var oldTimer:Object = _root.帧计时器;
        var api:Object = org.flashNight.arki.hud.FocusTargetHudService;
        var oldBinding:Object = api.binding;
        var oldCached:Object = api.cached;
        var hud:Object = org.flashNight.arki.hud.PlayerHudService;
        var oldEnabled:Boolean = hud.focusTargetEnabled;
        var oldMultiEnabled:Boolean = hud.focusTargetsEnabled;
        var oldForce:Boolean = hud.forceFull;
        var oldGroups:Object = hud.rawGroups;
        var world:MovieClip = _root.createEmptyMovieClip("__focusHudTestWorld", _root.getNextHighestDepth());
        _root.gameworld = world;
        try {
            api.binding = null; api.cached = null; api.combatState = null; api.aggroState = null; api.cachedList = null;
            var worldMark:Object = StageReturnFlow.worldIdentity(world);
            var unit:MovieClip = world.createEmptyMovieClip("boss", 1);
            unit.marker = {}; unit.hp = 80; unit.hp满血值 = 100; unit.名字 = "Boss | 引号\"";
            var unitMark:Object = unit.marker;
            var lease:Object = FocusTargetHudService.bind(world, worldMark, unit, "marker", unitMark, "boss", "");
            check(lease != null, "bind live authoritative actor");
            var first:Object = FocusTargetHudService.snapshot();
            check(first.hp[0] === 80 && first.hp[1] === 100 && first.role == "boss", "raw authoritative health");
            check(first.name == unit.名字, "default name comes from unit");
            check(FocusTargetHudService.snapshot() === first, "unchanged snapshot reused");
            check(unit.hp === 80 && unit.hp满血值 === 100 && unit.marker === unitMark, "read does not mutate gameplay");
            unit.hp = 140;
            var next:Object = FocusTargetHudService.snapshot();
            check(next !== first && next.hp[0] === 140 && first.hp[0] === 80, "overflow raw and detached previous snapshot");
            unit.hp = -12;
            check(FocusTargetHudService.snapshot().hp[0] === -12, "death raw value is not rewritten");
            unit.hp = Number("invalid"); check(FocusTargetHudService.snapshot() == null, "NaN hidden");
            unit.hp = 1000000000000001; check(FocusTargetHudService.snapshot() == null, "out-of-wire-range HP hidden");
            unit.hp = 20; unit.hp满血值 = 0; check(FocusTargetHudService.snapshot() == null, "zero maximum hidden");
            unit.hp满血值 = 1 / 0; check(FocusTargetHudService.snapshot() == null, "infinite maximum hidden");
            unit.hp满血值 = 100; check(FocusTargetHudService.snapshot().hp[0] === 20, "finite facts recover same binding");
            check(FocusTargetHudService.bind(world, {}, unit, "marker", unitMark, "boss", "") == null, "foreign world rejected");
            check(FocusTargetHudService.bind(world, worldMark, unit, "marker", {}, "boss", "") == null, "foreign actor rejected");
            check(FocusTargetHudService.bind(world, worldMark, unit, "marker", unitMark, "fake", "") == null, "role allowlist");
            check(FocusTargetHudService.bind(world, worldMark, unit, "marker", unitMark, "boss", String.fromCharCode(55296)) == null, "unpaired surrogate rejected before wire");
            var longLabel:String = "";
            for (var i:Number = 0; i < 193; i++) longLabel += "长";
            check(FocusTargetHudService.bind(world, worldMark, unit, "marker", unitMark, "boss", longLabel) == null, "oversized label rejected before wire");
            check(FocusTargetHudService.snapshot() != null, "invalid bind leaves current binding intact");
            check(!FocusTargetHudService.clear({}), "foreign lease cannot clear");
            var protect:Object = FocusTargetHudService.bind(world, worldMark, unit, "marker", unitMark, "protect", "护送目标");
            check(protect != null && !FocusTargetHudService.clear(lease), "late prior lease cannot clear replacement");
            check(FocusTargetHudService.snapshot().role == "protect", "generic protection role uses real actor");
            check(FocusTargetHudService.clear(protect) && !FocusTargetHudService.clear(protect), "exact clear once");
            check(FocusTargetHudService.snapshot() == null, "clear emits no target");
            lease = FocusTargetHudService.bind(world, worldMark, unit, "marker", unitMark, "boss", "");
            var oldUnit:MovieClip = unit;
            unit.removeMovieClip();
            unit = world.createEmptyMovieClip("boss", 1);
            unit.marker = {}; unit.hp = 60; unit.hp满血值 = 100;
            check(FocusTargetHudService.snapshot() == null, "real same-path replacement cannot inherit binding");
            check(FocusTargetHudService.bind(world, worldMark, oldUnit, "marker", unitMark, "boss", "") == null, "late old MovieClip reference cannot bind new actor");
            lease = FocusTargetHudService.bind(world, worldMark, unit, "marker", unit.marker, "boss", "机器人");
            check(lease != null, "successor explicitly binds fresh marker");
            unit.removeMovieClip(); check(FocusTargetHudService.snapshot() == null, "removed actor clears");
            unit = world.createEmptyMovieClip("boss", 1); unit.marker = {}; unit.hp = 10; unit.hp满血值 = 20;
            lease = FocusTargetHudService.bind(world, worldMark, unit, "marker", unit.marker, "boss", "新世界测试");
            world.removeMovieClip();
            world = _root.createEmptyMovieClip("__focusHudTestWorld", _root.getNextHighestDepth());
            _root.gameworld = world; worldMark = StageReturnFlow.worldIdentity(world);
            check(FocusTargetHudService.snapshot() == null, "same-path world recreation clears captured world identity");
            check(FocusTargetHudService.bind(world, {}, unit, "marker", unitMark, "boss", "") == null, "late prior world cannot bind");

            // Multi-target, priority ordering (protect > boss > combat), combat sticky/TTL, and portraits
            _root.帧计时器 = {当前帧数: 100};
            var hero:MovieClip = world.createEmptyMovieClip("hero", 10);
            hero.是否为敌人 = false; hero.hp = 500; hero.hp满血值 = 500;
            _root.控制目标 = "hero";

            var b1:MovieClip = world.createEmptyMovieClip("boss1", 11);
            b1.marker = {}; b1.hp = 800; b1.hp满血值 = 1000; b1.名字 = "蛮斧刽子手"; b1.兵种 = "敌人-蛮斧刽子手"; b1.是否为敌人 = true;
            var p1:MovieClip = world.createEmptyMovieClip("vip1", 12);
            p1.marker = {}; p1.hp = 300; p1.hp满血值 = 400; p1.名字 = "幸存者车队"; p1.hasDressup = true;
            p1.脸型 = "男脸"; p1.发型 = "短发"; p1.性别 = "男"; p1.是否为敌人 = false;

            var bLease:Object = FocusTargetHudService.bind(world, worldMark, b1, "marker", b1.marker, "boss", "");
            var pLease:Object = FocusTargetHudService.bind(world, worldMark, p1, "marker", p1.marker, "protect", "");
            check(bLease != null && pLease != null, "coexisting boss and protect bindings accepted");

            var mobLow:MovieClip = world.createEmptyMovieClip("mobLow", 13);
            mobLow.hp = 90; mobLow.hp满血值 = 120; mobLow.名字 = "普通杂兵"; mobLow.是否为敌人 = true;
            var mobHigh:MovieClip = world.createEmptyMovieClip("mobHigh", 14);
            mobHigh.hp = 450; mobHigh.hp满血值 = 500; mobHigh.名字 = "精英重装兵"; mobHigh.兵种 = "重盾骑士"; mobHigh.是否为敌人 = true;

            FocusTargetHudService.recordPlayerHit(hero, mobHigh, null);
            _root.帧计时器.当前帧数 = 105;
            // Within sticky window (15 frames), hitting a lower-maxHP mob does not steal focus from mobHigh, but increments global combo
            FocusTargetHudService.recordPlayerHit(hero, mobLow, {actualScatterUsed: 6, scatterModelEnabled: true, scatterMissCount: 2});
            var list:Array = FocusTargetHudService.snapshotList(hero);
            check(list != null && list.length == 3, "multi-target list includes protect, boss, and combat");
            check(list[0].role == "protect" && list[1].role == "boss" && list[2].role == "combat", "priority order is protect > boss > combat");
            check(list[2].name == "精英重装兵" && list[2].icon == "敌人-重盾骑士", "sticky AOE keeps higher maxHP target and resolves portrait key");
            check(list[2].hits === 5 && list[0].hits == undefined && list[1].hits == undefined, "player combo accumulates scatter hits (1 + 4) onto active combat row");
            check(list[0].doll != null && list[0].doll.face == "男脸" && list[1].icon == "敌人-蛮斧刽子手", "dressup doll and fixed enemy portrait metadata projected");
            check(FocusTargetHudService.snapshotList(hero) === list, "unchanged snapshotList reuses Array reference");

            // Hitting an already-bound boss deduplicates instead of showing a second row for the same actor, and transfers combo to boss row
            _root.帧计时器.当前帧数 = 130;
            FocusTargetHudService.recordPlayerHit(hero, b1, null);
            var deduped:Array = FocusTargetHudService.snapshotList(hero);
            check(deduped.length == 2 && deduped[0].role == "protect" && deduped[1].role == "boss" && deduped[1].hits === 6, "bound boss hit is deduplicated and receives continued combo count");

            // Re-hit mobLow after combo TTL window (75 frames -> 130+80=210) resets combo to 1, then expire combat after 150 frames
            _root.帧计时器.当前帧数 = 210;
            FocusTargetHudService.recordPlayerHit(hero, mobLow, null);
            check(FocusTargetHudService.snapshotList(hero).length == 3 && FocusTargetHudService.snapshotList(hero)[2].name == "普通杂兵" && FocusTargetHudService.snapshotList(hero)[2].hits === 1, "combat target updates and combo resets after COMBO_TTL_FRAMES");
            _root.帧计时器.当前帧数 = 365;
            hero.攻击目标 = "mobHigh";
            var fallbackList:Array = FocusTargetHudService.snapshotList(hero);
            check(fallbackList.length == 3 && fallbackList[2].name == "精英重装兵" && fallbackList[2].hits == undefined, "expired hit target falls back to hero.攻击目标 with expired combo cleared");
            mobHigh.hp = 0;
            check(FocusTargetHudService.snapshotList(hero).length == 2, "dead combat target auto-hides immediately");
            FocusTargetHudService.clear(bLease);
            FocusTargetHudService.clear(pLease);
            check(FocusTargetHudService.snapshotList(hero) == null, "clearing remaining bindings with no active combat returns null");

            checkSubstageBirths(world);
            FocusTargetHudService.activateScope(world, "layout-fixture", 0);
            var residents:Array = [];
            for (var n:Number = 0; n < 8; n++) {
                var resident:MovieClip = world.createEmptyMovieClip("resident" + n, 20 + n);
                resident.version = n + 1; resident.__unitInitializedVersion = resident.version;
                resident.hp = 300; resident.hp满血值 = 300; resident.名字 = "目标" + n;
                resident.focusHudRole = n % 2 == 0 ? "protect" : "boss";
                FocusTargetHudService.stampSpawn(world, resident);
                FocusTargetHudService.onUnitInitialized(resident);
                residents.push(resident);
                if (n == 3) {
                    mobHigh.hp = 100; FocusTargetHudService.recordPlayerHit(hero, mobHigh, null);
                    var four:Array = FocusTargetHudService.snapshotList(hero, 8);
                    check(four.length == 5 && four[4].role == "combat" && four[4].name == "精英重装兵",
                        "four residents plus the currently hit enemy all enter the negotiated queue");
                    var firstId:Number = four[0].id;
                    mobHigh.hp = 0;
                    var noEnemy:Array = FocusTargetHudService.snapshotList(hero, 8);
                    check(noEnemy.length == 4 && noEnemy[0].id == firstId,
                        "expired combat row releases its cell without replacing a resident");
                    mobHigh.hp = 100;
                    FocusTargetHudService.recordPlayerHit(hero, mobHigh, null);
                }
                if (n == 4) {
                    var five:Array = FocusTargetHudService.snapshotList(hero, 8);
                    check(five.length == 6 && five[5].role == "combat",
                        "five residents plus the same combat enemy all enter the queue");
                }
            }
            var eight:Array = FocusTargetHudService.snapshotList(hero, 8);
            check(eight.length == 8 && eight[3].role == "protect" && eight[4].role == "boss" && eight[7].role == "boss",
                "eight residents sorted by role with no combat overflow");
            var legacy:Array = FocusTargetHudService.snapshotList(hero, 4);
            check(legacy.length == 4 && legacy[3].role == "protect" && eight.length == 8,
                "legacy four-row protocol and earlier immutable snapshot coexist");
            for (n = 3; n < 8; n++) residents[n].removeMovieClip();
            var reduced:Array = FocusTargetHudService.snapshotList(hero, 8);
            check(reduced.length == 4 && reduced[3].role == "combat" && reduced[0].compact == undefined,
                "queue shrinks to three residents and combat without a scene-wide layout latch");
            api.clearScene();
            var escortScope:Object = FocusTargetHudService.activateScope(world, "escort-fixture", 3);
            var horse:MovieClip = world.createEmptyMovieClip("黑龙", 41);
            horse.version = 1; horse.__unitInitializedVersion = 1; horse.hp = 80; horse.hp满血值 = 100;
            horse.focusHudRole = "protect"; horse.focusHudLabel = "黑龙"; horse.focusHudSuccessor = "敌人-铠甲勇士";
            FocusTargetHudService.stampSpawn(world, horse);
            FocusTargetHudService.onUnitInitialized(horse);
            var mounted:Array = FocusTargetHudService.snapshotList(null, 8);
            check(mounted.length == 1 && mounted[0].compact == undefined, "new encounter begins single-column");
            var foot:MovieClip = world.createEmptyMovieClip("黑龙敌人-铠甲勇士", 42);
            foot.version = 2; foot.__unitInitializedVersion = 2; foot.hp = 220; foot.hp满血值 = 300;
            foot.兵种 = "其他兵种"; FocusTargetHudService.onUnitInitialized(foot);
            check(FocusTargetHudService.snapshotList(null, 8)[0].id === mounted[0].id, "lookalike spawn cannot steal escort identity");
            foot.兵种 = "敌人-铠甲勇士"; FocusTargetHudService.onUnitInitialized(foot);
            var dismounted:Array = FocusTargetHudService.snapshotList(null, 8);
            check(dismounted.length == 1 && dismounted[0].id !== mounted[0].id && dismounted[0].name == "黑龙"
                && dismounted[0].hp[0] == 220 && dismounted[0].role == "protect", "dismount transfers lease to the actual foot actor");
            var stageEvents:StageEventHandler = StageEventHandler.getInstance();
            world.dispatcher = new LifecycleEventDispatcher(world);
            stageEvents.init(world);
            stageEvents.subscribeStageEvent(new StageEvent({EventName:"UnitDeath", Parameter:"黑龙敌人-铠甲勇士", StageProgress:"Fail"}));
            var outcome:Object = {count:0};
            world.dispatcher.subscribe("StageFailed", function() { this.count++; }, outcome);
            world.dispatcher.publish("UnitDeath", horse._name);
            check(outcome.count == 0 && FocusTargetHudService.snapshotList(null, 8)[0].id === dismounted[0].id,
                "mounted death leaves escort active");
            world.dispatcher.publish("UnitDeath", foot._name);
            world.dispatcher.publish("UnitDeath", foot._name);
            check(outcome.count == 1, "matching foot death fires the authored failure once");
            stageEvents.clear();
            FocusTargetHudService.endEncounter(escortScope);
            FocusTargetHudService.onUnitInitialized(horse);
            FocusTargetHudService.recordPlayerHit(hero, mobHigh, null);
            check(FocusTargetHudService.snapshot() == null && FocusTargetHudService.snapshotList(hero, 8) == null,
                "accepted stage end hides objectives and ignores late actor callbacks");
            api.clearScene();
            hud.focusTargetEnabled = false; hud.focusTargetsEnabled = false;
            PlayerHudService.testOnlyConfigure({}); check(hud.focusTargetEnabled === false && hud.focusTargetsEnabled === false, "old Host stays unextended");
            PlayerHudService.testOnlyConfigure({focusTarget:1, focusTargets:1}); check(hud.focusTargetEnabled === false && hud.focusTargetsEnabled === false, "nonboolean opt-in rejected");
            PlayerHudService.testOnlyConfigure({focusTarget:true, focusTargets:true}); check(hud.focusTargetEnabled === true && hud.focusTargetsEnabled === true, "new Host opts in");
            hud.rawGroups = {};
            var groups:Object = {};
            check(hud.addGroup(groups,"focusTarget",first,true), "full includes target group");
            groups = {}; check(!hud.addGroup(groups,"focusTarget",first,false), "unchanged delta omitted");
            check(hud.addGroup(groups,"focusTarget",null,false) && groups.focusTarget === null, "explicit null replaces target");
            var codec:LiteJSON = new LiteJSON();
            trace("FOCUS_TARGET_HUD_WIRE " + codec.stringifySafe({focusTarget:first}));
        } catch (error) { check(false, "unexpected " + error); }
        world.removeMovieClip(); _root.gameworld = oldWorld;
        _root.控制目标 = oldControl; _root.帧计时器 = oldTimer;
        api.binding = oldBinding; api.cached = oldCached; api.combatState = null; api.aggroState = null; api.cachedList = null;
        hud.focusTargetEnabled = oldEnabled; hud.focusTargetsEnabled = oldMultiEnabled; hud.forceFull = oldForce; hud.rawGroups = oldGroups;
        trace("FocusTargetHudTest Tests Passed: " + passed);
        trace("FocusTargetHudTest Tests Failed: " + failed);
    }
}
