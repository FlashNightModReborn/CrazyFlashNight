import org.flashNight.arki.unit.Action.Skill.EmergencyInjectionService;
import org.flashNight.arki.unit.Action.Skill.EmergencyInjector;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DrugInventory;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.unit.Action.Skill.EmergencyInjectionServiceTest {
    private static var total:Number;
    private static var passed:Number;
    private static var failed:Number;
    private static var scheduled:Array;
    private static var fixtures:Array;

    private static function check(value:Boolean, label:String):Void {
        total++;
        if (value) passed++; else { failed++; trace("[FAIL] EmergencyInjection " + label); }
    }
    private static function reset():Void {
        ManualCooldownService.resetForTests();
        PlayerAssetTransaction.resetForTests();
        scheduled = [];
        ManualCooldownService.setSchedulerForTests(function(callback:Function):Void { scheduled.push(callback); });
        DrugInputService.resetSession();
    }
    private static function ready():Void {
        var guard:Number = 0;
        while (scheduled.length > 0 && guard++ < 1000) { var callback = scheduled.shift(); callback(); }
    }
    private static function fixture(heal:Number, count:Number, slot:Number):Object {
        reset();
        var unit:MovieClip = _root.createEmptyMovieClip("emergencyFixture" + fixtures.length, _root.getNextHighestDepth());
        unit.version = 1; unit.hp = unit.hp满血值 = 1000; unit.mp = 9999;
        unit.防御力 = 1; unit.无敌 = false; unit.NPC = false;
        unit.shield = {absorbDamage:function(amount:Number):Number { return amount; },
            getStrength:function():Number { return 0; }, getCapacity:function():Number { return 0; }};
        var inventory:ArrayInventory = new ArrayInventory({}, 8);
        inventory.add(slot, new BaseItem("大HP药剂", count, 0));
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(unit);
        inventory.setDispatcher(dispatcher);
        var chest:Object = {name:"统合61式胸甲", value:{level:1, tier:"", mods:[]}};
        var equipment:Object = {chest:chest, getItem:function(key:String):Object {
            return key == "上装装备" ? this.chest : null;
        }};
        var root:Object = {当前玩家总数:1, 控制目标:"hero", 暂停:false, gameworld:{hero:unit},
            物品栏:{药剂栏:inventory, 装备栏:equipment}, _saveExt:{drugLoadout:{version:2}},
            存档系统:{dirtyMark:false}, 吃药冷却时间:100, heal:heal, effectCalls:0};
        root.getItemData = function(name:String):Object { return {name:name, type:"消耗品", use:"药剂"}; };
        root.使用药剂 = function(name:String):Void {
            this.effectCalls++;
            var target:Object = this.gameworld[this.控制目标];
            target.hp = Math.min(target.hp满血值, target.hp + this.heal);
        };
        root.发布消息 = function(message:String):Void {};
        var owner:Object = {broken:true};
        owner.emergencyInjectionEligible = function():Boolean { return this.broken; };
        var f:Object = {unit:unit, root:root, owner:owner, inventory:inventory,
            equipment:equipment, chest:chest, slot:slot};
        fixtures.push(f);
        EmergencyInjectionService.refresh(unit, owner, root);
        return f;
    }
    private static function authorize(f:Object):Object {
        return EmergencyInjectionService.authorize(f.root, f.unit, f.slot, "大HP药剂", true);
    }
    private static function remaining(f:Object):Number {
        var item:Object = f.inventory.getItem(String(f.slot));
        return item == null ? 0 : item.value;
    }
    private static function bullet(amount:Number, handles:Array):Object {
        var normal:Object = {handleBulletDamage:function(b:Object, shooter:Object, target:Object,
                                                       manager:Object, result:DamageResult):Void {
            target.损伤值 = b.testDamage;
            result.actualScatterUsed = b.testScatter == undefined ? 1 : b.testScatter;
        }};
        return {testDamage:amount, testScatter:1, damageManager:new DamageManager(handles == null ? [normal] : handles),
            伤害类型:"物理", 子弹威力:1, 固伤:0, 百分比伤害:0, flags:0, hitBehavior:{type:"titaniumFireControl"}};
    }
    private static function hit(f:Object, b:Object):Void {
        DamageCalculator.calculateDamage(b, {伤害加成:0}, f.unit, 1, "");
    }

    private static function testAuthorizationAndInactiveBank():Void {
        var f:Object = fixture(600, 3, 4);
        check(!EmergencyInjectionService.read(f.root).enabled && f.unit.__emergencyInjector == undefined, "default off has no HP accessor");
        var result:Object = authorize(f);
        check(result.success && result.emergencyInjection.physicalSlot == 4 && f.root.存档系统.dirtyMark, "authorization binds exact physical slot and marks save dirty");
        check(f.unit.__emergencyInjector != undefined, "authorized five-piece provider installs local accessor");
        f.unit.hp = 300;
        check(f.unit.hp == 900 && remaining(f) == 2 && f.root.effectCalls == 1, "inactive bank injects real healing once before returning from HP write");
        check(DrugInputService.getActiveBank() == 0 && !ManualCooldownService.isReady(ManualCooldownService.drugKey(0)), "inactive bank keeps bank and occupies paired lane");
        check(ManualCooldownService.isReady(ManualCooldownService.drugSwitchKey()), "automatic use does not consume bank switch cooldown");
        check(DrugInputService.updateSlot(f.unit, 0, true, true, f.inventory, f.root, null) == null, "paired manual lane cannot spend another dose in same cooldown");
        f.unit.hp = 200;
        check(f.unit.hp == 200 && remaining(f) == 2, "same-frame next damage is not free recovery");
        var before:Number = f.root.effectCalls;
        var snap:Object = EmergencyInjectionService.snapshot(f.root);
        check(snap.enabled && f.root.effectCalls == before && remaining(f) == 2, "read-only projection neither injects nor consumes");
    }

    private static function testCrisisAndEligibility():Void {
        var f:Object = fixture(100, 3, 0); authorize(f);
        f.unit.hp = 300;
        check(f.unit.hp == 400 && remaining(f) == 2, "small medicine below reset remains same crisis");
        ready(); f.unit.hp = 250;
        check(f.unit.hp == 250 && remaining(f) == 2, "cooldown recovery plus another low write cannot repeat used crisis");
        f.unit.hp = 700; f.unit.hp = 500;
        check(f.unit.hp == 600 && remaining(f) == 1, "70 percent resets and exact 50 percent triggers next crisis");
        f = fixture(600, 2, 0); authorize(f); f.owner.broken = false;
        f.unit.hp = 450;
        check(f.unit.hp == 450 && remaining(f) == 2, "online own shield protects intentional low HP");
        f.owner.broken = true; f.unit.hp = 400;
        check(f.unit.hp == 1000 && remaining(f) == 1, "already-low HP can gain first full eligibility after shield breaks");
        check(f.unit.mp == 9999 && f.root.effectCalls == 1, "high MP is not an emergency rejection");
        f = fixture(600, 2, 0); authorize(f); f.root.暂停 = true; f.unit.hp = 450;
        check(f.unit.hp == 450 && remaining(f) == 2, "pause blocks consumption");
        f.root.暂停 = false; ready();
        check(remaining(f) == 2, "unpause and cooldown do not queue automatic use");
        f.unit.hp = 400;
        check(f.unit.hp == 1000 && remaining(f) == 1, "new legal descending event after pause can trigger");
        f = fixture(600, 2, 0); authorize(f); f.unit.hp = 0;
        check(f.unit.hp == 0 && remaining(f) == 2, "direct lethal assignment is never revived");
        f.unit.hp = 1000; f.unit.hp = 500;
        check(f.unit.hp == 1000 && remaining(f) == 1, "revived healthy actor rearms normally");
        f = fixture(600, 2, 0); authorize(f); f.unit.__playerStatInitializing = true; f.unit.hp = 300;
        check(f.unit.hp == 300 && remaining(f) == 2, "stat reconstruction cannot consume medicine");
    }

    private static function testInvalidationAndLifecycle():Void {
        var f:Object = fixture(600, 2, 0); authorize(f);
        f.inventory.remove("0"); f.inventory.add("0", new BaseItem("另一种药剂", 2));
        check(!EmergencyInjectionService.read(f.root).enabled, "actual inventory replacement immediately revokes item authorization");
        f.inventory.remove("0"); f.inventory.add("0", new BaseItem("大HP药剂", 2));
        EmergencyInjectionService.refresh(f.unit, f.owner, f.root);
        check(f.unit.__emergencyInjector == undefined && !EmergencyInjectionService.read(f.root).enabled, "A-B-A replacement cannot silently authorize original item again");
        check(authorize(f).success, "explicit reauthorization restores access");
        f.unit.hp = 300;
        check(f.unit.hp == 900 && remaining(f) == 1, "reauthorized slot works through same consumption path");
        f = fixture(100, 1, 0); authorize(f); f.unit.hp = 300;
        check(remaining(f) == 0 && EmergencyInjectionService.read(f.root).enabled, "last dose preserves item authorization");
        check(f.root._saveExt.drugLoadout.version == 3 && f.root._saveExt.drugLoadout.slots[0].itemKey == "大HP药剂", "last automatic dose commits existing original-slot affinity");
        f.inventory.add("0", new BaseItem("大HP药剂", 1)); ready();
        f.unit.hp = 200;
        check(remaining(f) == 1, "same-name refill does not reset low-HP crisis");
        var old:EmergencyInjector = f.unit.__emergencyInjector;
        EmergencyInjectionService.release(f.unit, f.owner);
        check(f.unit.__emergencyInjector == undefined && f.unit.hp == 200, "unequip restores plain numeric HP with exact current value");
        var owner:Object = {broken:true, emergencyInjectionEligible:function():Boolean { return this.broken; }};
        EmergencyInjectionService.refresh(f.unit, owner, f.root); f.unit.hp = 150;
        check(remaining(f) == 1 && f.unit.hp == 150, "changing set provider cannot reset same crisis");
        f.unit.version = 2;
        EmergencyInjectionService.refresh(f.unit, owner, f.root); f.unit.hp = 100;
        check(remaining(f) == 1 && f.unit.hp == 100, "same-world actor reinitialization cannot reset used crisis");
        f.unit.hp = 1000; f.unit.hp = 400;
        check(remaining(f) == 0 && f.unit.hp == 500, "shared provider retains recovery-based rearm");
        EmergencyInjectionService.authorize(f.root, f.unit, -1, "", false);
        check(f.unit.__emergencyInjector == undefined && !EmergencyInjectionService.snapshot(f.root).enabled, "explicit disable removes accessor immediately");
        f = fixture(600, 2, 0);
        check(!EmergencyInjectionService.authorize(f.root, f.unit, 0, "错误药剂", true).success, "stale item name is rejected before authorization write");
        check(!f.root.存档系统.dirtyMark && !EmergencyInjectionService.read(f.root).enabled, "rejected authorization does not dirty save or enable use");
        f.chest.value.emergencyInjection = {version:2, enabled:true, physicalSlot:0, itemKey:"大HP药剂"};
        EmergencyInjectionService.refresh(f.unit, f.owner, f.root);
        check(f.unit.__emergencyInjector == undefined && EmergencyInjectionService.snapshot(f.root).status == "unsupported_config", "future config fails closed without overwrite");
    }

    private static function testPerChestInstanceOwnershipAndSwap():Void {
        var f:Object = fixture(100, 2, 0);
        f.inventory.add("4", new BaseItem("再生药剂", 2));
        f.equipment.chest = {name:"普通防弹背心", value:{level:1, tier:"", mods:[]}};
        EmergencyInjectionService.refresh(f.unit, f.owner, f.root);
        var rejected:Object = EmergencyInjectionService.authorize(f.root, f.unit, 0, "大HP药剂", true);
        check(!rejected.success && rejected.error == "incompatible_item"
                && !EmergencyInjectionService.read(f.root).enabled
                && EmergencyInjectionService.snapshot(f.root).status == "disabled",
            "non-61 chest cannot be authorized for emergency injection");

        var chestA:Object = f.chest;
        var chestB:Object = {name:"钛合金61式胸甲", value:{level:1, tier:"", mods:[]}};
        f.equipment.chest = chestA;
        EmergencyInjectionService.refresh(f.unit, f.owner, f.root);
        authorize(f);
        f.equipment.chest = chestB;
        EmergencyInjectionService.refresh(f.unit, f.owner, f.root);
        check(!EmergencyInjectionService.read(f.root).enabled
                && f.unit.__emergencyInjector == undefined
                && chestA.value.emergencyInjection.enabled
                && chestA.value.emergencyInjection.physicalSlot == 0,
            "swapping to unbound 61 chest disposes injector while preserving previous chest slot");

        var resB:Object = EmergencyInjectionService.authorize(f.root, f.unit, 4, "再生药剂", true);
        check(resB.success && chestB.value.emergencyInjection.physicalSlot == 4
                && chestA.value.emergencyInjection.physicalSlot == 0,
            "second 61 chest holds independent emergency slot");

        f.unit.hp = 300;
        var slot4After:Number = f.inventory.getItem("4").value;
        var slot0Before:Number = f.inventory.getItem("0").value;
        f.equipment.chest = chestA;
        EmergencyInjectionService.refresh(f.unit, f.owner, f.root);
        ready();
        f.unit.hp = 200;
        var noDoubleConsume:Boolean = f.inventory.getItem("0").value == slot0Before;
        f.unit.hp = 700;
        f.unit.hp = 500;
        check(slot4After == 1 && noDoubleConsume
                && f.inventory.getItem("0").value == 1
                && f.inventory.getItem("4").value == 1,
            "swapping back switches active slot without resetting shared crisis memory");

        f.inventory.remove("4");
        f.inventory.add("4", new BaseItem("止血药", 2));
        var backpackSnap:Object = EmergencyInjectionService.snapshotItem(chestB, f.root);
        check(backpackSnap.status == "item_changed" && chestB.value.emergencyInjection.enabled,
            "unequipped chest reports item_changed read-only without mutating until worn");
        f.root.存档系统.dirtyMark = false;
        f.equipment.chest = chestB;
        EmergencyInjectionService.refresh(f.unit, f.owner, f.root);
        check(!EmergencyInjectionService.read(f.root).enabled
                && !chestB.value.emergencyInjection.enabled
                && f.unit.__emergencyInjector == undefined
                && f.root.存档系统.dirtyMark,
            "re-equipping a backpack chest whose drug changed immediately revokes stale authorization");
    }

    private static function testSynchronousDamageBoundary():Void {
        var f:Object = fixture(600, 3, 0); authorize(f);
        hit(f, bullet(700, null));
        check(f.unit.hp == 900 && remaining(f) == 2, "real DamageCalculator returns only after first-hit emergency healing");
        hit(f, bullet(700, null));
        check(f.unit.hp == 200 && remaining(f) == 2 && f.root.effectCalls == 1, "two independent synchronous hits exceed Hmax and survive by exactly one paid dose");
        f = fixture(600, 3, 0); authorize(f); var b:Object = bullet(1400, null); b.testScatter = 4; hit(f, b);
        check(f.unit.hp == 0 && remaining(f) == 3, "one aggregated lethal scatter hit has no internal injection point");
        f = fixture(600, 3, 0); authorize(f); b = bullet(0, [ActualTerminalDamageHandle.getInstance()]); b.实际命中强制击杀 = true; hit(f, b);
        check(f.unit.hp == 0 && remaining(f) == 3, "actual terminal handler preserves explicit final death");
        f = fixture(600, 3, 0); authorize(f);
        var intermediate:Object = {handleBulletDamage:function(b:Object, s:Object, target:Object, m:Object, result:DamageResult):Void {
            target.hp = 400; target.损伤值 = 1400;
        }};
        hit(f, bullet(1400, [intermediate]));
        check(f.unit.hp == 0 && remaining(f) == 3 && f.root.effectCalls == 0, "intermediate low-HP write cannot eat before final lethal commit");
        f = fixture(600, 3, 0); authorize(f);
        var fault:Object = {handleBulletDamage:function(b:Object, s:Object, target:Object, m:Object, result:DamageResult):Void {
            target.hp = 400; throw "original_damage_failure";
        }};
        var observed:String = "";
        try { hit(f, bullet(0, [fault])); } catch (error) { observed = String(error); }
        check(observed == "original_damage_failure" && f.unit.hp == 400 && remaining(f) == 3, "failed damage preserves original exception and does not inject on partial state");
        check(f.unit.__emergencyInjector.damageDepth == 0, "failed damage releases only its exact synchronous boundary");
    }

    private static function testFailuresDoNotInterruptDamage():Void {
        var f:Object = fixture(600, 3, 0); authorize(f);
        f.owner.emergencyInjectionEligible = function():Boolean { throw "provider_failure"; return false; };
        f.unit.hp = 400;
        check(f.unit.hp == 400 && remaining(f) == 3 && f.unit.__emergencyInjector.lastError == "provider_failure", "eligibility exception does not interrupt committed HP write");
        f = fixture(600, 3, 0); authorize(f);
        f.root.使用药剂 = function(name:String):Void { throw "effect_failure"; };
        f.unit.hp = 400;
        check(f.unit.hp == 400 && remaining(f) == 3 && PlayerAssetTransaction.current() == null, "effect failure unwinds asset transaction without losing original damage");
        ready(); f.unit.hp = 300;
        check(f.unit.hp == 300 && remaining(f) == 3, "uncertain attempt is not blindly replayed while low");
        f = fixture(600, 3, 0); authorize(f); delete f.root.存档系统;
        f.unit.hp = 400;
        check(f.unit.hp == 400 && remaining(f) == 3 && PlayerAssetTransaction.current() == null, "missing save owner rejects before medication effects");
        f = fixture(600, 3, 0); authorize(f); f.root.当前玩家总数 = 2; f.unit.hp = 400;
        check(f.unit.hp == 400 && remaining(f) == 3, "multiplayer state disables automatic player medication");
        f = fixture(600, 3, 0); authorize(f);
        var savedRestriction:Object = _root.限制系统;
        var savedData = _root.getItemData;
        try {
            _root.限制系统 = {entries:{DisableDrug:true}};
            _root.getItemData = function(name:String):Object { return {use:"药剂"}; };
            f.unit.hp = 400;
            check(f.unit.hp == 400 && remaining(f) == 3
                    && ManualCooldownService.isReady(ManualCooldownService.drugKey(0)),
                "stage prohibition rejects automatic use before HP effect cooldown and inventory writes");
            check(!f.unit.__emergencyInjectionMemory.used, "prohibited medicine has not consumed a crisis opportunity");
            _root.限制系统 = {entries:{}};
            f.unit.hp = 300;
            check(f.unit.hp == 900 && remaining(f) == 2,
                "first eligible descending event after prohibition clears may use the same crisis");
        } finally { _root.限制系统 = savedRestriction; _root.getItemData = savedData; }
    }

    private static function testMaximumChangesCannotRearm():Void {
        var f:Object = fixture(100, 3, 0); authorize(f); f.unit.hp = 300;
        f.unit.__playerStatInitializing = true; f.unit.hp满血值 = 500; f.unit.version = 2;
        EmergencyInjectionService.refresh(f.unit, f.owner, f.root);
        f.unit.__playerStatInitializing = false;
        ready(); f.unit.hp = 200;
        check(f.unit.hp == 200 && remaining(f) == 2,
            "lower maximum HP and actor reinitialization cannot turn a used crisis into healthy recovery");
        f.unit.hp = 350; f.unit.hp = 250;
        check(f.unit.hp == 350 && remaining(f) == 1,
            "real healing to the new 70 percent maximum may rearm normally");
        f = fixture(100, 3, 0); authorize(f); f.unit.hp = 300;
        EmergencyInjectionService.release(f.unit, f.owner); f.unit.hp满血值 = 500;
        EmergencyInjectionService.refresh(f.unit, f.owner, f.root); ready(); f.unit.hp = 200;
        check(f.unit.hp == 200 && remaining(f) == 2,
            "unequip and re-equip with a lower HP maximum cannot grant a free crisis opportunity");
    }

    private static function testProductionInventoryObservation():Void {
        var savedData = _root.getItemData;
        _root.getItemData = function(name:String):Object { return {use:"药剂"}; };
        try {
            var f:Object = fixture(100, 2, 4);
            var inventory:DrugInventory = new DrugInventory({}, 8);
            inventory.add(4, new BaseItem("大HP药剂", 2, 0));
            f.inventory = inventory; f.root.物品栏.药剂栏 = inventory;
            authorize(f);
            check(inventory.getDispatcher() == null && f.unit.__emergencyInjector != undefined,
                "production DrugInventory authorization requires no optional HUD dispatcher");
            inventory.transactionWrite(4, new BaseItem("另一种药剂", 2, 0));
            inventory.publishTransactionChange(4, "replaced");
            inventory.transactionWrite(4, new BaseItem("大HP药剂", 2, 0));
            inventory.publishTransactionChange(4, "replaced");
            check(!EmergencyInjectionService.read(f.root).enabled,
                "actual committed A-B-A transactions synchronously revoke authorization in one frame");
            authorize(f); f.unit.hp = 300;
            check(f.unit.hp == 400 && remaining(f) == 1,
                "real container reauthorization enables one exact inactive-slot dose");
            inventory.remove(4); inventory.add(4, new BaseItem("大HP药剂", 2, 0));
            ready(); f.unit.hp = 200;
            check(EmergencyInjectionService.read(f.root).enabled && remaining(f) == 2 && f.unit.hp == 200,
                "real same-name refill retains authorization without rearming the used crisis");
            EmergencyInjectionService.authorize(f.root, f.unit, -1, "", false);
            var owner:Object = {};
            check(inventory.bindSlotChangeObserver(function():Void {}, owner),
                "disable releases only the emergency observer ownership");
            inventory.unbindSlotChangeObserver(owner);
        } finally { _root.getItemData = savedData; }
    }

    private static function testWorldLifecycle():Void {
        var f:Object = fixture(100, 3, 0); authorize(f); f.unit.hp = 300;
        EmergencyInjectionService.release(f.unit, f.owner);
        var next:MovieClip = _root.createEmptyMovieClip("emergencyWorldReplacement", _root.getNextHighestDepth());
        next.version = 2; next.hp满血值 = 1000; next.hp = 400;
        fixtures.push({unit:next, inventory:f.inventory});
        f.root.gameworld = {hero:next};
        EmergencyInjectionService.refresh(next, f.owner, f.root); ready(); next.hp = 300;
        check(next.hp == 300 && remaining(f) == 2 && next.__emergencyInjectionMemory.used,
            "new world and replacement actor preserve the already-used crisis");
        next.hp = 700; next.hp = 500;
        check(next.hp == 600 && remaining(f) == 1,
            "new scene still rearms only after actual healthy recovery");
        EmergencyInjectionService.release(next, f.owner);
        EmergencyInjectionService.resetSession(f.root);
        EmergencyInjectionService.refresh(next, f.owner, f.root); ready(); next.hp = 400;
        check(next.hp == 500 && remaining(f) == 0,
            "explicit owned save-session boundary creates fresh crisis memory");
    }

    private static function testMedicationReentry():Void {
        var f:Object = fixture(600, 3, 0); authorize(f);
        f.root.fixture = f;
        f.root.使用药剂 = function(name:String):Void {
            var current:Object = this.fixture;
            this.nestedUse = DrugInputService.tryConsumePhysicalSlot(current.unit, 0,
                current.inventory, this, name);
            current.unit.hp = Math.min(current.unit.hp + 600, current.unit.hp满血值);
        };
        f.unit.hp = 400;
        check(f.root.nestedUse == null && f.unit.hp == 1000 && remaining(f) == 2,
            "same lane rejects reentry before medicine effect starts its cooldown");
        f = fixture(600, 3, 0); authorize(f); f.root.fixture = f;
        f.root.使用药剂 = function(name:String):Void { this.fixture.unit.hp = 400; };
        DrugInputService.tryConsumePhysicalSlot(f.unit, 0, f.inventory, f.root, "大HP药剂");
        check(remaining(f) == 2 && f.unit.hp == 400
                && f.unit.__emergencyInjectionMemory.attempts == 0,
            "manual medicine HP effect cannot recursively trigger automatic medicine");
        ready(); f.unit.hp = 300;
        check(remaining(f) == 1 && f.unit.hp == 400
                && f.unit.__emergencyInjectionMemory.attempts == 1,
            "later independent damage remains eligible after medication effect returns");
    }

    private static function benchmark():Void {
        var f:Object = fixture(600, 3, 0), sum:Number = 0, start:Number, plain:Array = [], accessor:Array = [];
        var repeats:Number = 5, count:Number = 100000, allBound:Boolean = true;
        for (var r:Number = 0; r < repeats; r++) {
            EmergencyInjectionService.release(f.unit, f.owner);
            start = getTimer();
            for (var i:Number = 0; i < count; i++) { f.unit.hp = 900 + (i & 1); sum += f.unit.hp; }
            plain.push(getTimer() - start);
            if (r == 0) authorize(f);
            EmergencyInjectionService.refresh(f.unit, f.owner, f.root);
            if (f.unit.__emergencyInjector == undefined) allBound = false;
            start = getTimer();
            for (i = 0; i < count; i++) { f.unit.hp = 900 + (i & 1); sum += f.unit.hp; }
            accessor.push(getTimer() - start);
        }
        trace("EmergencyInjectionBenchmark count=" + count + " plainMs=" + plain.join(",")
            + " accessorMs=" + accessor.join(",") + " checksum=" + sum);
        check(allBound, "every native accessor benchmark sample actually installs the accessor");
        check(sum == 900500000 && remaining(f) == 3, "native accessor benchmark preserves HP and never consumes above crisis line");
    }

    public static function runAllTests():Void {
        total = passed = failed = 0; fixtures = [];
        try {
            testAuthorizationAndInactiveBank(); testCrisisAndEligibility(); testInvalidationAndLifecycle();
            testPerChestInstanceOwnershipAndSwap();
            testSynchronousDamageBoundary(); testFailuresDoNotInterruptDamage();
            testMaximumChangesCannotRearm(); testProductionInventoryObservation(); testWorldLifecycle(); testMedicationReentry(); benchmark();
        } catch (error) { failed++; total++; trace("[FAIL] EmergencyInjection suite exception: " + error); }
        for (var i:Number = 0; i < fixtures.length; i++) {
            var f:Object = fixtures[i];
            if (f.unit.__emergencyInjector) f.unit.__emergencyInjector.dispose();
            f.inventory.setDispatcher(null); f.unit.removeMovieClip();
        }
        ManualCooldownService.resetForTests(); PlayerAssetTransaction.resetForTests();
        trace("EmergencyInjectionServiceTest Tests Passed: " + passed);
        trace("EmergencyInjectionServiceTest Tests Failed: " + failed);
    }
}
