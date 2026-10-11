import org.flashNight.arki.bullet.BulletComponent.Loader.ShellLoader;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Skill.QuickSkillInputService;
import org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.hud.PlayerHudService;
import org.flashNight.arki.hud.PlayerHudBuffProjection;

/** 只覆盖普通字段读取的可删模式；存在性/反向判断/带副作用调用仍保留原门控。 */
class org.flashNight.gesh.object.Avm1GuardContractTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var sink:Number = 0;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("[FAIL] Avm1GuardContractTest: " + label); }
    }
    public static function runAllTests():Void {
        passed = failed = sink = 0;
        testScalarContracts();
        testShellLoader();
        testReloadPredicates();
        testOptionalViews();
        testHudGuards();
        benchmark(true);
        benchmark(false);
        ManualCooldownService.resetForTests();
        trace("Avm1GuardContractTest Tests Passed: " + passed);
        trace("Avm1GuardContractTest Tests Failed: " + failed);
    }
    private static function oldGuard(value:Object):Boolean {
        return value != null && value.child != null && value.child.detail != null && value.child.detail.enabled === true;
    }
    private static function newGuard(value:Object):Boolean { return value.child.detail.enabled === true; }
    private static function testScalarContracts():Void {
        var values:Array = [undefined, null, {}, false, 0, "", {child:null}, {child:{}},
            {child:{detail:null}}, {child:{detail:{}}}, {child:{detail:{enabled:false}}},
            {child:{detail:{enabled:true}}}, {child:{detail:{enabled:1}}}];
        for (var i:Number = 0; i < values.length; i++) {
            check(oldGuard(values[i]) === newGuard(values[i]), "ordinary positive leaf predicate " + i);
        }
        var missing:Object = null;
        check((missing != null && missing.disabled !== true) === false && (missing.disabled !== true) === true,
            "negative leaf predicate needs the existence guard and is excluded from rewriting");
        var primitive:Array = [undefined, null, 0, false, "", "null", "undefined", Number.NaN, Number.POSITIVE_INFINITY];
        for (i = 0; i < primitive.length; i++) {
            var value = primitive[i];
            check((value == undefined || value == null) === (value == null), "duplicate primitive nullish test " + i);
        }
    }
    private static function oldShell(data:Object):Object {
        var result:Object = {};
        var node:Object = data.shell;
        if (node != undefined && node.casing != undefined) result.弹壳 = node.casing;
        else return null;
        result.myX = node != undefined && node.xOffset != undefined ? Number(node.xOffset) : 0;
        result.myY = node != undefined && node.yOffset != undefined ? Number(node.yOffset) : 0;
        result.模拟方式 = node != undefined && node.simulationMethod != undefined ? node.simulationMethod : "标准";
        return result;
    }
    private static function sameNumber(a:Number, b:Number):Boolean { return a === b || (isNaN(a) && isNaN(b)); }
    private static function testShellLoader():Void {
        var loader:ShellLoader = new ShellLoader();
        var cases:Array = [undefined, null, {}, {shell:null}, {shell:{}}, {shell:{casing:null}},
            {shell:{casing:"壳"}}, {shell:{casing:"",xOffset:0,yOffset:0,simulationMethod:""}},
            {shell:{casing:"壳",xOffset:-3,yOffset:4,simulationMethod:"物理"}},
            {shell:{casing:"壳",xOffset:"2",yOffset:"bad"}}, {shell:{casing:"壳",xOffset:false,yOffset:null}}];
        for (var i:Number = 0; i < cases.length; i++) {
            var expected:Object = oldShell(cases[i]), actual:Object = loader.load(cases[i]);
            check(expected == null ? actual === null : actual.弹壳 === expected.弹壳
                && sameNumber(actual.myX, expected.myX) && sameNumber(actual.myY, expected.myY)
                && actual.模拟方式 === expected.模拟方式, "actual shell loader parity " + i);
        }
    }
    private static function testReloadPredicates():Void {
        var requests:Array = [undefined, null, {}, {kind:"manual"}, {kind:"linked"}, {kind:"other"},
            {weaponType:"长枪副武器"}, {kind:"manual",weaponType:"长枪副武器"}];
        for (var i:Number = 0; i < requests.length; i++) {
            var request:Object = requests[i], unit:Object = {subweaponReloadRequest:request};
            check(LongGunSubWeaponCore.isManualReloadRequest(unit) === (request != null && request.kind == "manual"), "manual request " + i);
            check(LongGunSubWeaponCore.isLinkedReloadRequest(unit) === (request != null && request.kind == "linked"), "linked request " + i);
            check(LongGunSubWeaponCore.isSubweaponReloadRequest(unit) === (request != null && request.weaponType == "长枪副武器"), "subweapon request " + i);
        }
        check(LongGunSubWeaponCore.isManualReloadRequest(null) === false, "missing actor still rejects manual request");
    }
    private static function testOptionalViews():Void {
        ManualCooldownService.resetForTests();
        var root:Object = {暂停:true, 当前玩家总数:1};
        var actor:Object = {hp:1,攻击模式:"空手",主动战技:{}};
        QuickSkillInputService.installRootBridge(root);
        WeaponSkillInputService.installRootBridge(root);
        DrugInputService.installRootBridge(root);
        check(root.快捷技能输入控制器.update(actor) === 0, "missing quick view does not release input");
        check(root.药剂输入控制器.update(actor) === 0, "missing drug view does not consume inventory");
        check(root.武器技能输入控制器.update(actor, false) == null, "missing weapon view keeps input untriggered");
        var weaponBar:Object = {}, quickBar:Object = {};
        root.玩家信息界面 = {玩家必要信息界面:{战技进度条:weaponBar},快捷技能界面:{进度条1:quickBar}};
        root.武器技能输入控制器.update(actor, false);
        root.快捷技能输入控制器.update(actor);
        check(weaponBar.__manualCooldownKey === ManualCooldownService.WEAPON_SKILL_KEY,
            "live weapon bridge retains its captured root and optional renderer receiver");
        check(quickBar.__manualCooldownKey === ManualCooldownService.quickSkillKey(1),
            "live quick bridge binds the original view when it becomes available");
        var view:Object = {控制器0:{mytext:{}},控制器4:{mytext:{}}};
        root.keyshow = function(code:Number):String { return "K" + code; };
        DrugInputService.syncView(view, 0, 65, root);
        DrugInputService.syncSwitchView(view, 66, root);
        check(view.控制器0.mytext.text === "K65" && view.控制器4.mytext.text === "K66", "present key renderer retains receiver and label");
        DrugInputService.syncView(view, 0, 67, null);
        DrugInputService.syncSwitchView(view, 68, undefined);
        check(view.控制器0.mytext.text === "K65" && view.控制器4.mytext.text === "K66", "absent root renderer does not overwrite labels");
        var quick:Object = QuickSkillInputService, loadout:Object = SkillLoadoutService;
        var original:Function = loadout.getSlotDescriptor;
        try {
            loadout.getSlotDescriptor = function(slot:Number):Object { return {stateHealth:"unknown",writeBlocked:true}; };
            check(quick.getSkillSlot(null, 1) === null, "absent fixture falls through to authoritative unavailable descriptor");
            var fixture:Object = {__skillInputFixture:true,快捷技能栏1:{name:"fixture"}};
            check(quick.getSkillSlot(fixture, 1) === fixture.快捷技能栏1, "positive fixture marker returns the original slot");
        } finally { loadout.getSlotDescriptor = original; }
    }
    private static function testHudGuards():Void {
        var before = _root.角色名;
        var unit:Object = {hp:1,hp满血值:1,mp:1,mp满血值:1,攻击模式:"空手",主动战技:{}};
        try {
            var names:Array = [undefined,null,0,false,"","中文"];
            for (var i:Number = 0; i < names.length; i++) {
                _root.角色名 = names[i];
                var expected:String = names[i] == undefined || names[i] == null ? "" : String(names[i]);
                check(PlayerHudService.testOnlyReadVitals(unit).name === expected, "HUD text nullish parity " + i);
            }
            check(PlayerHudService.testOnlyReadVitals(unit).shieldReady === false, "missing shield cannot advertise readiness");
            unit.shield = {getMaxCapacity:function():Number { return 10; },getCapacity:function():Number { return 5; }};
            check(PlayerHudService.testOnlyReadVitals(unit).shieldReady === true, "present shield method still advertises readiness");
            var projection:PlayerHudBuffProjection = new PlayerHudBuffProjection();
            projection.deinitialize();
            projection.initialize(null);
            check(projection.snapshot().length === 0, "empty Buff owner detaches without an event call");
        } finally { _root.角色名 = before; }
    }
    private static function measure(legacy:Boolean, value:Object, count:Number):Number {
        var start:Number = getTimer();
        for (var i:Number = 0; i < count; i++) if (legacy ? oldGuard(value) : newGuard(value)) sink++;
        return getTimer() - start;
    }
    private static function benchmark(present:Boolean):Void {
        var value:Object = present ? {child:{detail:{enabled:true}}} : null;
        measure(true, value, 100); measure(false, value, 100);
        var baseline:Array = [], candidate:Array = [];
        for (var round:Number = 0; round < 5; round++) {
            if ((round & 1) == 0) {
                baseline.push(measure(true,value,10000)); candidate.push(measure(false,value,10000));
            } else {
                candidate.push(measure(false,value,10000)); baseline.push(measure(true,value,10000));
            }
        }
        trace("[AS2_HOTPATH_BENCH] guard_depth3_" + (present ? "present" : "missing")
            + "|iterations=10000|baselineMs=" + baseline.join(",") + "|candidateMs=" + candidate.join(","));
    }
}
