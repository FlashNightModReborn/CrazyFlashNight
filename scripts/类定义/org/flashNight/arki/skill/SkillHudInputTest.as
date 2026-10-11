import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.hud.PlayerHudService;

/** Live legacy mutation coverage; the original hudInputs builder remains the miss oracle. */
class org.flashNight.arki.skill.SkillHudInputTest {
    private static var api:Object;
    private static var legacyInputs:Array;
    private static var legacyDescriptors:Object;
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var checksum:Number = 0;
    private static var codec:LiteJSON;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] SkillHudInputTest: " + message); }
    }
    // Frozen getHudDescriptors control flow from 0c36a08a. The production cold-input
    // builder, authority scan and descriptor formatter retain their original bodies.
    private static function legacyRead():Object {
        var inputs:Array = api.hudInputs();
        if (inputs != null && legacyInputs != null && inputs.length == legacyInputs.length) {
            var same:Boolean = true;
            for (var index:Number = 0; index < inputs.length; index++) {
                if (inputs[index] !== legacyInputs[index]) { same = false; break; }
            }
            if (same) return legacyDescriptors;
        }
        var sync:Object = SkillLoadoutService.synchronize();
        var slots:Array = [];
        for (var slot:Number = 1; slot < 13; slot++) {
            slots.push(sync.success ? api.descriptorFromScan(slot, sync.scan) :
                {slot:slot, equipped:false, skillKey:null, keyLabel:api.keyLabel(slot), stateHealth:"unknown", writeBlocked:true});
        }
        legacyInputs = inputs;
        legacyDescriptors = {revision:api._revision, slots:slots};
        return legacyDescriptors;
    }
    private static function fixture(rowCount:Number, learned:Number):Object {
        var r:Object = {技能表对象:{}, 主角技能表:new Array(rowCount), 存档系统:{dirtyMark:false}, 等级:50, 技能点数:100, keyPrefix:"K", domainCalls:0};
        for (var i:Number = 0; i < rowCount; i++) {
            var name:String = "skill_" + i;
            r.技能表对象[name] = {MaxLevel:10, UnlockLevel:1, UnlockSP:20, UpgradeSP:5, Type:"武术", Passive:false, Equippable:true, MP:i + 1, CD:2000};
            r.主角技能表[i] = i < learned ? [name, 1, i < 12, "武术", true] : ["", 0, false, "", true];
        }
        for (i = 1; i < 13; i++) { r["快捷技能栏" + i] = i <= learned ? "skill_" + (i - 1) : ""; r["快捷技能栏键" + i] = 48 + i; }
        r.keyshow = function(code:Number):String { return this.keyPrefix + code; };
        r.动态更新技能冷却领域 = function():Boolean { this.domainCalls++; return true; };
        SkillLoadoutService.testOnlyUseRoot(r);
        legacyInputs = null; legacyDescriptors = null;
        return r;
    }
    private static function parity(label:String):Object {
        var actual:Object = SkillLoadoutService.getHudDescriptors();
        var expected:Object = legacyRead();
        check(PlayerHudService.testOnlySameProjection(actual, expected), label + " values");
        check(codec.stringifySafe(actual) == codec.stringifySafe(expected), label + " exact wire bytes/order");
        var r:Object = SkillLoadoutService.root();
        check(r.存档系统.dirtyMark !== true && r.domainCalls == 0, label + " read-only authority");
        return actual;
    }
    private static function testChanges():Void {
        var r:Object = fixture(80,12), i:Number, j:Number;
        var first:Object = parity("cold");
        parity("warm revision synchronization");
        var stable:Object = SkillLoadoutService.getHudDescriptors();
        check(stable === SkillLoadoutService.getHudDescriptors(), "unchanged descriptors retain identity");
        var before:String = codec.stringifySafe(first);
        r.主角技能表[0][1] = 2;
        check(parity("same-frame level edit").slots[0].level == 2, "level direct write appears immediately");
        check(codec.stringifySafe(first) == before, "earlier descriptors are never overwritten");
        var rowValues:Array = ["skill_1", 3, false, "被动", false];
        for (j = 0; j < 5; j++) {
            var saved = r.主角技能表[0][j]; r.主角技能表[0][j] = rowValues[j]; parity("row scalar " + j);
            r.主角技能表[0][j] = saved; parity("row scalar restore " + j);
        }
        var keys:Array = ["MaxLevel", "UnlockLevel", "UnlockSP", "UpgradeSP", "Type", "Passive", "Equippable", "MP", "CD"];
        var values:Array = [1, 60, 30, 9, "被动", true, false, 88, 8000];
        for (i = 0; i < keys.length; i++) {
            saved = r.技能表对象.skill_0[keys[i]]; r.技能表对象.skill_0[keys[i]] = values[i]; parity("metadata " + keys[i]);
            r.技能表对象.skill_0[keys[i]] = saved; parity("metadata restored " + keys[i]);
        }
        r.快捷技能栏12 = "skill_0"; parity("late slot reassignment");
        r.快捷技能栏键12 = 120; check(parity("last key binding").slots[11].keyLabel == "K120", "live key binding label");
        r.keyPrefix = "New"; check(parity("same keyshow new output").slots[0].keyLabel == "New49", "keyshow output stays live");
        r.等级 = 60; parity("player level"); r.技能点数 = 7; parity("skill points");
        var oldMeta:Object = r.技能表对象.skill_0;
        r.技能表对象.skill_0 = {MaxLevel:10, UnlockLevel:1, UnlockSP:20, UpgradeSP:5, Type:"武术", Passive:false, Equippable:true, MP:5, CD:2000};
        parity("metadata reference replaced"); r.技能表对象.skill_0 = oldMeta; parity("metadata restored");
        delete r.主角技能表[79]; parity("late hole");
        r.主角技能表[79] = ["skill_0", 1, false, "武术", true];
        check(parity("late duplicate").slots[0].writeBlocked, "row 79 still blocks duplicates");
        r.主角技能表[79] = ["", 0, false, "", true]; parity("duplicate removed");
        r.主角技能表[3].push("extra"); parity("row length grows"); r.主角技能表[3].pop(); parity("row length restored");
        r.主角技能表[80] = ["skill_0",1,false,"武术",true]; parity("corrupt tail fallback");
        r.主角技能表.length = 80; parity("tail removed");
        var table:Array = r.主角技能表; r.主角技能表 = table.slice(); parity("table replacement"); r.主角技能表 = table;
        var bad:Array = [null, undefined, Number.NaN, Number.POSITIVE_INFINITY, {}, function():Void {}, ["nested"]];
        for (i = 0; i < bad.length; i++) {
            saved = r.主角技能表[1][1]; r.主角技能表[1][1] = bad[i]; parity("non-scalar row input " + i);
            r.主角技能表[1][1] = saved; parity("row recovered " + i);
            saved = r.技能表对象.skill_1.MP; r.技能表对象.skill_1.MP = bad[i]; parity("non-scalar metadata input " + i);
            r.技能表对象.skill_1.MP = saved; parity("metadata recovered " + i);
        }
        var save:Object = r.存档系统; r.存档系统 = null;
        check(parity("readiness lost").slots[0].writeBlocked, "not-ready cannot reuse a ready snapshot");
        r.存档系统 = save; parity("readiness restored");
        r = fixture(0,0); parity("empty short table");
        r = fixture(1,1); parity("one row short table");
        r = fixture(80,1); delete r.主角技能表[0]; parity("missing learned own row");
    }
    private static function time(legacy:Boolean, count:Number, changing:Boolean):Number {
        var r:Object = SkillLoadoutService.root(), start:Number = getTimer();
        for (var i:Number = 0; i < count; i++) {
            if (changing) r.技能表对象.skill_0.MP = 10 + (i & 1);
            var value:Object = legacy ? legacyRead() : SkillLoadoutService.getHudDescriptors();
            checksum += value.slots.length;
        }
        return getTimer() - start;
    }
    private static function benchmark(rows:Number, learned:Number, changing:Boolean):Void {
        fixture(rows,learned);
        time(true, 4, changing); time(false, 4, changing);
        var original:Array = [], candidate:Array = [];
        var count:Number = changing ? 15 : 70;
        for (var round:Number = 0; round < 5; round++) {
            if ((round & 1) == 0) { original.push(time(true,count,changing)); candidate.push(time(false,count,changing)); }
            else { candidate.push(time(false,count,changing)); original.push(time(true,count,changing)); }
        }
        trace("[AS2_HOTPATH_BENCH] skill_hud_" + rows + "_" + learned + "_" + (changing ? "changing" : "unchanged") + "|iterations=" + count + "|baselineMs=" + original.join(",") + "|candidateMs=" + candidate.join(","));
    }
    public static function runAllTests():Void {
        passed = failed = checksum = 0; codec = new LiteJSON(); api = org.flashNight.arki.skill.SkillLoadoutService;
        try {
            testChanges();
            benchmark(0,0,false); benchmark(80,0,false); benchmark(80,12,false); benchmark(80,80,false); benchmark(80,12,true);
        } finally { SkillLoadoutService.testOnlyReset(); }
        trace("SkillHudInputTest Tests Passed: " + passed);
        trace("SkillHudInputTest Tests Failed: " + failed);
    }
}
