import org.flashNight.arki.hud.FocusTargetHudService;
import org.flashNight.arki.hud.PlayerHudService;
import org.flashNight.arki.scene.StageReturnFlow;

class org.flashNight.arki.hud.FocusTargetHudTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("FAIL FocusTargetHudTest: " + message); }
    }
    public static function runAllTests():Void {
        passed = failed = 0;
        var oldWorld:MovieClip = _root.gameworld;
        var api:Object = org.flashNight.arki.hud.FocusTargetHudService;
        var oldBinding:Object = api.binding;
        var oldCached:Object = api.cached;
        var hud:Object = org.flashNight.arki.hud.PlayerHudService;
        var oldEnabled:Boolean = hud.focusTargetEnabled;
        var oldForce:Boolean = hud.forceFull;
        var oldGroups:Object = hud.rawGroups;
        var world:MovieClip = _root.createEmptyMovieClip("__focusHudTestWorld", _root.getNextHighestDepth());
        _root.gameworld = world;
        try {
            api.binding = null; api.cached = null;
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
            _root.gameworld = world; StageReturnFlow.worldIdentity(world);
            check(FocusTargetHudService.snapshot() == null, "same-path world recreation clears captured world identity");
            check(FocusTargetHudService.bind(world, worldMark, unit, "marker", unitMark, "boss", "") == null, "late prior world cannot bind");
            hud.focusTargetEnabled = false;
            PlayerHudService.testOnlyConfigure({}); check(hud.focusTargetEnabled === false, "old Host stays unextended");
            PlayerHudService.testOnlyConfigure({focusTarget:1}); check(hud.focusTargetEnabled === false, "nonboolean opt-in rejected");
            PlayerHudService.testOnlyConfigure({focusTarget:true}); check(hud.focusTargetEnabled === true, "new Host opts in");
            hud.rawGroups = {};
            var groups:Object = {};
            check(hud.addGroup(groups,"focusTarget",first,true), "full includes target group");
            groups = {}; check(!hud.addGroup(groups,"focusTarget",first,false), "unchanged delta omitted");
            check(hud.addGroup(groups,"focusTarget",null,false) && groups.focusTarget === null, "explicit null replaces target");
            var codec:LiteJSON = new LiteJSON();
            trace("FOCUS_TARGET_HUD_WIRE " + codec.stringifySafe({focusTarget:first}));
        } catch (error) { check(false, "unexpected " + error); }
        world.removeMovieClip(); _root.gameworld = oldWorld;
        api.binding = oldBinding; api.cached = oldCached;
        hud.focusTargetEnabled = oldEnabled; hud.forceFull = oldForce; hud.rawGroups = oldGroups;
        trace("FocusTargetHudTest Tests Passed: " + passed);
        trace("FocusTargetHudTest Tests Failed: " + failed);
    }
}
