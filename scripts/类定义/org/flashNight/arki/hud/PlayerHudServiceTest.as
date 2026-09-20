import org.flashNight.arki.hud.PlayerHudService;
import org.flashNight.arki.hud.PlayerHudBuffProjection;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.arki.item.DrugHudMutationService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.component.StatHandler.ImpactHandler;
class org.flashNight.arki.hud.PlayerHudServiceTest {
    private static var total:Number = 0;
    private static var passed:Number = 0;
    private static function check(ok:Boolean, message:String):Void {
        total++;
        if (ok) passed++; else trace("[FAIL] PlayerHudServiceTest: " + message);
    }
    public static function runAllTests():Void {
        total = passed = 0;
        testVitalsAndWire();
        testBuffOwnership();
        testDrugUnequip();
        testRealMovieClipGeneration();
        testAmmoOwnershipAndEncoding();
        testFrameEndCapture();
        testProjectionComparison();
        testPoiseProjection();
        ManualCooldownService.resetForTests();
        trace("--- PlayerHudServiceTest: " + passed + "/" + total + " passed, " + (total-passed) + " failed ---");
    }
    private static function testPoiseProjection():Void {
        var unit:Object = {hp:100, hp满血值:100, mp:50, mp满血值:100, 防御力:300,
            韧性系数:1, 躲闪率:1, remainingImpactForce:0, man:{}, 攻击模式:"空手", 主动战技:{}};
        ImpactHandler.refreshImpactDerived(unit);
        var view:Object = PlayerHudService.testOnlyPoise(unit);
        check(Math.abs(view.threshold - 0.2928932188) < 0.000001 && view.phase == "buffer", "stagger marker uses the nonlinear mapping, not fixed 50 percent");
        unit.remainingImpactForce = unit.impactStaggerBoundary;
        ImpactHandler.refreshImpactDerived(unit);
        check(PlayerHudService.testOnlyPoise(unit).phase == "buffer", "exact boundary retains the gameplay strict-greater comparison");
        unit.remainingImpactForce += 0.001;
        ImpactHandler.refreshImpactDerived(unit);
        check(PlayerHudService.testOnlyPoise(unit).phase == "stagger", "just past the real boundary is the stagger band despite rounded percent");
        unit.躲闪率 = 2; ImpactHandler.refreshImpactDerived(unit);
        check(PlayerHudService.testOnlyPoise(unit).threshold == 0.5, "attribute changes move the marker to 50 percent for this actor");
        unit.躲闪率 = 4; ImpactHandler.refreshImpactDerived(unit);
        check(Math.abs(PlayerHudService.testOnlyPoise(unit).threshold - 0.6464466094) < 0.000001, "another attribute value moves the marker again");
        unit.躲闪率 = 0.25; ImpactHandler.refreshImpactDerived(unit);
        view = PlayerHudService.testOnlyPoise(unit);
        check(!view.hasStaggerBand && view.threshold == 0, "boundary beyond knockdown capacity has no reachable stagger band");
        unit.remainingImpactForce = unit.韧性上限 + 1;
        check(PlayerHudService.testOnlyPoise(unit).phase == "break", "knockdown boundary has priority over stagger boundary");
        unit.刚体 = true;
        check(PlayerHudService.testOnlyPoise(unit).phase == "rigid", "rigid actor does not receive a misleading ordinary risk caption");
        unit.刚体 = false; unit.man.刚体标签 = true;
        check(PlayerHudService.testOnlyPoise(unit).phase == "rigid", "animation rigid tag is projected too");
        unit.浮空 = true;
        check(PlayerHudService.testOnlyPoise(unit).phase == "air", "airborne state leaves the ordinary ground bar");
        unit.浮空 = false; unit.倒地 = true;
        check(PlayerHudService.testOnlyPoise(unit).phase == "down", "down state leaves the ordinary ground bar");
        unit.倒地 = false; unit.man.刚体标签 = false; unit.remainingImpactForce = 60; unit.躲闪率 = 2;
        ImpactHandler.refreshImpactDerived(unit);
        var before:Number = unit.remainingImpactForce;
        check(PlayerHudService.testOnlyReadVitals(unit).poiseDetail == undefined, "old candidate field set is unchanged before opt-in");
        PlayerHudService.testOnlyConfigure({poiseDetails:true});
        view = PlayerHudService.testOnlyReadVitals(unit).poiseDetail;
        check(view.phase == "stagger" && unit.remainingImpactForce == before, "opt-in is a read-only atomic vitals projection");
        trace("[PLAYER_HUD_POISE_WIRE] " + PlayerHudService.testOnlyWire(unit));
        var server:Object = _root.server; _root.server = {isSocketConnected:false};
        PlayerHudService.tick(); _root.server = server;
        check(PlayerHudService.testOnlyReadVitals(unit).poiseDetail == undefined, "disconnect clears the prior receiver capability");
        unit.韧性上限 = 0;
        check(PlayerHudService.testOnlyPoise(unit).phase == "unavailable", "uninitialized capacity cannot be labelled safe");
    }
    private static function testVitalsAndWire():Void {
        var name = _root.角色名;
        _root.角色名 = "中文|冒号:引号\"换行\n" + String.fromCharCode(55357, 56832);
        var shield:AdaptiveShield = new AdaptiveShield(400, 100, 1, 10, "测试盾", "test");
        shield.consumeCapacity(400);
        var unit:Object = {hp:1400, hp满血值:1000, mp:700, mp满血值:600,
            nonlinearMappingResilience:0.25, shield:shield, 攻击模式:"空手", 主动战技:{}};
        var v:Object = PlayerHudService.testOnlyReadVitals(unit);
        check(v.hp[0] == 1400 && v.hp[1] == 1000, "raw overflow is not clamped");
        check(v.mp[0] == 700 && v.mp[1] == 600, "raw MP overflow remains available");
        check(v.shieldReady && v.shieldPresent && v.shield[0] == 0 && v.shield[1] == 400, "depleted rechargeable shield remains present");
        check(v.poise == 0.25, "existing nonlinear poise projection is authoritative");
        unit.shield = new AdaptiveShield();
        v = PlayerHudService.testOnlyReadVitals(unit);
        check(v.shieldReady && !v.shieldPresent, "dormant shell is not an equipped shield");
        unit.shield = null;
        v = PlayerHudService.testOnlyReadVitals(unit);
        check(!v.shieldReady && !v.shieldPresent, "not-ready shield differs from absent shield");
        unit.hp = -5;
        v = PlayerHudService.testOnlyReadVitals(unit);
        check(v.hp[0] == -5, "negative finite HP is preserved");
        check(v.level == 0 && v.sp == 0 && v.experience[0] == 0, "missing optional scalars are finite zero on the actual AVM1 wire");
        var wire:String = PlayerHudService.testOnlyWire(unit);
        var json:String = Base64.decode(wire);
        check(json.indexOf("\\n") >= 0 && json.indexOf("\\\"") >= 0, "free text is JSON escaped before base64");
        check(Base64.encode(json) == wire, "UTF8 and surrogate pair round-trip");
        trace("[PLAYER_HUD_WIRE] " + wire);
        _root.角色名 = name;
    }
    private static function testProjectionComparison():Void {
        var previous:Object = {name:"A|B:\"中文", numbers:[1, 0], slot:{key:"技能", empty:""}};
        var current:Object = {slot:{empty:"", key:"技能"}, numbers:[1, 0], name:"A|B:\"中文"};
        check(PlayerHudService.testOnlySameProjection(previous, current), "unchanged detached DTO ignores property insertion order");
        current.numbers[0] = "1";
        check(!PlayerHudService.testOnlySameProjection(previous, current), "numeric and display string changes remain distinct");
        current.numbers[0] = 1; current.numbers.push(0);
        check(!PlayerHudService.testOnlySameProjection(previous, current), "array membership changes publish");
        current.numbers.pop(); delete current.slot.empty;
        check(!PlayerHudService.testOnlySameProjection(previous, current), "removed display fields publish");
        current.slot.empty = ""; current.name = "A|B:\"中文变更";
        check(!PlayerHudService.testOnlySameProjection(previous, current), "escaped free text changes publish");
        check(!PlayerHudService.testOnlySameProjection([], {}), "empty arrays and objects remain distinct");
    }
    private static function timerBuff(id:String, totalTime:Number, remaining:Number):Object {
        var timer:Object = {totalTime:totalTime, remaining:remaining};
        timer.getTotal = function():Number { return this.totalTime; };
        timer.getRemaining = function():Number { return this.remaining; };
        var buff:Object = {__regId:id, timer:timer};
        buff.getPrimaryTimer = function():Object { return this.timer; };
        return buff;
    }
    private static function manager(rows:Array):Object {
        var dispatcher:Object = {subs:0, unsubs:0};
        dispatcher.isDestroyed = function():Boolean { return false; };
        dispatcher.subscribe = function():Void { this.subs++; };
        dispatcher.unsubscribe = function():Void { this.unsubs++; };
        var value:Object = {rows:rows, eventDispatcher:dispatcher};
        value.getAllMetaBuffs = function():Array { return this.rows; };
        return value;
    }
    private static function testBuffOwnership():Void {
        var a:Object = timerBuff("a", 100, 40);
        var b:Object = timerBuff("b", 200, 50);
        var first:Object = manager([a]);
        var projection:PlayerHudBuffProjection = new PlayerHudBuffProjection();
        projection.initialize(first);
        check(projection.snapshot().length == 1 && first.eventDispatcher.subs == 2, "initial Buff enumeration and exact subscriptions");
        projection.initialize(first);
        check(first.eventDispatcher.subs == 2, "same manager does not subscribe twice");
        projection.addIcon("b", b); projection.addIcon("b", b);
        var rows:Array = projection.snapshot();
        check(rows.length == 2 && rows[0].remaining == 40 && rows[1].remaining == 50, "stable order and duplicate add guard");
        projection.removeIcon("a");
        check(projection.snapshot().length == 1, "remove updates projected order");
        var replacement:Object = manager([a]);
        projection.initialize(replacement);
        check(first.eventDispatcher.unsubs == 2 && replacement.eventDispatcher.subs == 2, "manager replacement unsubscribes old ownership");
        check(projection.snapshot()[0].id != rows[0].id, "manager generation fences recycled Buff identifiers");
        projection.deinitialize();
        check(projection.snapshot().length == 0 && replacement.eventDispatcher.unsubs == 2, "teardown clears renderer without destroying Buffs");
    }
    private static function testDrugUnequip():Void {
        ManualCooldownService.resetForTests();
        ManualCooldownService.setSchedulerForTests(function(callback:Function):Void {});
        var save:Object = {dirtyMark:false};
        var item:Object = {name:"普通hp药剂", value:3};
        var source:Object = {items:[item,null,null,null,null,null,null,null], moves:0, save:save};
        source.getItem = function(slot:String):Object { return this.items[Number(slot)]; };
        source.move = function(bag:Object, slot:String, target:Number):Boolean {
            this.sawDirty = this.save.dirtyMark; this.moves++;
            bag.items[target] = this.items[Number(slot)]; this.items[Number(slot)] = null; return true;
        };
        var bag:Object = {vacancy:-1, items:[{name:"普通hp药剂",value:99},null]};
        bag.getFirstVacancy = function():Number { return this.vacancy; };
        var root:Object = {存档系统:save, 物品栏:{药剂栏:source, 背包:bag}, _saveExt:{}};
        root.getItemData = function(key:String):Object { return {use:"药剂"}; };
        check(DrugHudMutationService.unequip(root,0,item,3,true).error == "locked" && source.moves == 0, "locked icon does not write");
        check(DrugHudMutationService.unequip(root,0,{name:item.name,value:3},3,false).error == "stale_state", "same-name replacement is not the captured item");
        check(DrugHudMutationService.unequip(root,0,item,2,false).error == "stale_state", "changed count rejects delayed click");
        check(DrugHudMutationService.unequip(root,0,item,3,false).error == "bag_full" && !save.dirtyMark, "full bag stays rejected even when a same-name stack exists");
        bag.vacancy = 1;
        ManualCooldownService.start(ManualCooldownService.drugKey(0),1000);
        check(DrugHudMutationService.unequip(root,0,item,3,false).error == "cooldown", "shared lane cooldown protects unequip");
        ManualCooldownService.reset(ManualCooldownService.drugKey(0));
        var rejectingSave:Object = {};
        rejectingSave.addProperty("dirtyMark", function():Boolean { return false; }, function(value):Void {});
        root.存档系统 = rejectingSave;
        check(DrugHudMutationService.unequip(root,0,item,3,false).error == "not_ready" && source.moves == 0,
            "unacknowledged dirty mark rejects before moving an item");
        root.存档系统 = save;
        var result:Object = DrugHudMutationService.unequip(root,0,item,3,false);
        check(result.success && source.moves == 1 && source.sawDirty, "dirty is set before the sole collection write");
        check(bag.items[1] === item && bag.items[0].value == 99, "first vacancy policy does not merge stacks");
        check(root._saveExt.drugLoadout.version == 3 && root._saveExt.drugLoadout.slots[0].itemKey == "", "manual unequip clears old affinity");
    }
    private static function testAmmoOwnershipAndEncoding():Void {
        var world:MovieClip = _root.createEmptyMovieClip("gameworld", _root.getNextHighestDepth());
        var unit:MovieClip = world.createEmptyMovieClip("player", 1);
        unit.攻击模式 = "双枪"; unit.手枪 = {}; unit.手枪2 = {};
        unit.主动战技 = {};
        PlayerHudService.testOnlyAmmo(unit, 0, 17);
        PlayerHudService.testOnlyAmmo(unit, 1, 4);
        PlayerHudService.testOnlyAmmo(unit, 2, 8);
        PlayerHudService.testOnlyAmmo(unit, 3, "无限");
        check(PlayerHudService.testOnlyRawAmmo(0) === 17, "legacy numeric ammo readback remains numeric");
        var combat:Object = PlayerHudService.testOnlyCombat(unit);
        check(combat.ammo[0] === "17" && combat.ammo[3] === "无限", "wire converts detached display values only");
        unit.手枪2 = {};
        combat = PlayerHudService.testOnlyCombat(unit);
        check(combat.ammo[0] == "17" && combat.ammo[2] == "" && combat.ammo[3] == "", "secondary replacement clears only its pair");
        PlayerHudService.testOnlyAmmo(unit, 2, 3);
        combat = PlayerHudService.testOnlyCombat(unit);
        unit.攻击模式 = "unknown";
        var retained:Object = PlayerHudService.testOnlyCombat(unit);
        check(retained === combat && retained.ammo[2] == "3", "unknown mode retains the same actor's whole prior view");
        unit.攻击模式 = "长枪"; unit.长枪 = {};
        check(PlayerHudService.testOnlyCombat(unit).ammo[0] == "", "mode switch does not borrow a previous weapon's ammo");
        PlayerHudService.testOnlyAmmo(unit, 0, 44);
        unit.长枪 = {};
        check(PlayerHudService.testOnlyCombat(unit).ammo[0] == "", "same-mode primary replacement clears old ammo");
        unit.removeMovieClip(); unit = world.createEmptyMovieClip("player", 1); unit.攻击模式 = "unknown";
        check(PlayerHudService.testOnlyCombat(unit).mode == "", "new actor cannot inherit another actor's unknown-mode fallback");
        var oldKey = _root.武器技能键; var oldShow = _root.keyshow;
        _root.武器技能键 = 70; _root.keyshow = function(code:Number):String { return "key-" + code; };
        unit.攻击模式 = "空手";
        check(PlayerHudService.testOnlyCombat(unit).weapon.key == "key-70", "weapon label uses the same live key as behavior");
        _root.武器技能键 = oldKey; _root.keyshow = oldShow;
        world.removeMovieClip();
        var replacement:String = String.fromCharCode(65533);
        check(Base64.decode(Base64.encodeDisplay("A" + String.fromCharCode(55357) + "B")) == "A" + replacement + "B", "broken high surrogate cannot consume following text");
        check(Base64.decode(Base64.encodeDisplay(String.fromCharCode(56832))) == replacement, "isolated low surrogate becomes a display replacement");
        check(Base64.decode(Base64.encodeDisplay(String.fromCharCode(55357))) == replacement, "trailing high surrogate is valid UTF8 on wire");
        check(Base64.encodeDisplay(String.fromCharCode(55357,56832)) == "8J+YgA==", "valid astral character keeps its UTF8 known answer");
        check(Base64.encodeDisplay("中文") == Base64.encode("中文"), "valid existing Base64 output remains byte-identical");
        var strictThrows:Boolean = false;
        try { Base64.encode(String.fromCharCode(55357) + "B"); } catch (error) { strictThrows = true; }
        check(strictThrows, "strict Base64 callers keep their original rejection contract");
    }
    private static function testFrameEndCapture():Void {
        var priorServer = _root.server;
        var world:MovieClip = _root.createEmptyMovieClip("gameworld", _root.getNextHighestDepth());
        var sink:Object = {isSocketConnected:true, rows:[]};
        sink.sendSocketMessage = function(value:String):Void { this.rows.push(value); };
        _root.server = sink;
        FrameBroadcaster.setPlayerHudCapture(function():Void {
            FrameBroadcaster.setPlayerHudPayload("pi:frame-end");
        });
        FrameBroadcaster.setPlayerHudPayload("pi:early");
        FrameBroadcaster.send();
        check(sink.rows.length == 1 && sink.rows[0].indexOf("pi:frame-end") >= 0 && sink.rows[0].indexOf("pi:early") < 0,
            "frame-end capture replaces an earlier sample before the single frame send");
        check(!FrameBroadcaster.hasPlayerHudPending(), "frame consumes its bounded projection slot");
        sink.isSocketConnected = false;
        FrameBroadcaster.send();
        check(sink.rows.length == 1, "disconnected frame does not capture or send");
        FrameBroadcaster.setPlayerHudCapture(null);
        FrameBroadcaster.setPlayerHudPayload("pi:old-world");
        FrameBroadcaster.reset();
        check(!FrameBroadcaster.hasPlayerHudPending(), "scene reset drops the previous frame's projection");
        _root.server = priorServer; world.removeMovieClip();
    }
    private static function testRealMovieClipGeneration():Void {
        if (typeof _root.gameworld == "movieclip") { check(false, "test requires isolated TestLoader without player world"); return; }
        var world:MovieClip = _root.createEmptyMovieClip("gameworld", _root.getNextHighestDepth());
        var unit:MovieClip = world.createEmptyMovieClip("player", 1);
        var first:Number = PlayerHudService.testOnlyContext(unit);
        var oldReference:MovieClip = unit;
        unit.removeMovieClip();
        var replacement:MovieClip = world.createEmptyMovieClip("player", 1);
        var second:Number = PlayerHudService.testOnlyContext(replacement);
        check(second > first, "same-path actor replacement starts a new epoch");
        check(oldReference === replacement, "real AVM1 reference alias is exercised");
        world.removeMovieClip();
        world = _root.createEmptyMovieClip("gameworld", _root.getNextHighestDepth());
        replacement = world.createEmptyMovieClip("player", 1);
        check(PlayerHudService.testOnlyContext(replacement) > second, "same-path world replacement starts a new epoch");
        world.removeMovieClip();
    }
}
