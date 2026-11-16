import org.flashNight.arki.unit.Action.Skill.EmergencyInjectionService;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.component.Damage.DamageCalculator;
import org.flashNight.arki.component.Damage.DamageResult;

/** 只挂到授权的当前玩家；HP原值、危机记忆与套装provider分别持有。 */
class org.flashNight.arki.unit.Action.Skill.EmergencyInjector {
    private var unit:Object;
    private var provider:Object;
    private var config:Object;
    private var root:Object;
    private var version;
    private var memory:Object;
    private var busy:Boolean;
    private var installed:Boolean;
    public var hp;
    public var damageDepth:Number;
    public var attempts:Number;
    public var doses:Number;
    public var observedDrops:Number;
    public var lastError:String;
    public var lastBefore:Number;
    public var lastAfter:Number;

    public function EmergencyInjector(target:Object, owner:Object, authorization:Object, environment:Object) {
        unit = target; provider = owner; config = authorization; root = environment;
        version = unit.version;
        memory = root.__emergencyInjectionMemory;
        if (!memory || memory.slot !== String(root.savePath)) {
            memory = {slot:String(root.savePath), used:false, lastHp:unit.hp, attempts:0, doses:0, observedDrops:0};
            root.__emergencyInjectionMemory = memory;
        }
        unit.__emergencyInjectionMemory = memory;
        busy = installed = false;
        damageDepth = 0;
        attempts = memory.attempts; doses = memory.doses; observedDrops = memory.observedDrops;
        lastError = "";
    }

    public function install():Boolean {
        if (unit.__emergencyInjector || typeof unit.addProperty != "function") return false;
        hp = unit.hp;
        unit.__emergencyInjector = this;
        if (!unit.addProperty("hp", function() { return this.__emergencyInjector.hp; },
                function(value):Void { this.__emergencyInjector.writeHp(value); })) {
            delete unit.__emergencyInjector;
            return false;
        }
        installed = true;
        resetIfRecovered(hp, hp);
        return true;
    }

    public function matches(owner:Object, authorization:Object, environment:Object):Boolean {
        return installed && provider === owner && config === authorization && root === environment
            && unit.version === version && unit.__emergencyInjector === this;
    }

    public function dispose():Void {
        if (!installed) return;
        installed = false;
        if (unit.__emergencyInjector !== this) return;
        var current = hp;
        delete unit.hp;
        unit.hp = current;
        delete unit.__emergencyInjector;
    }

    public function writeHp(value):Void {
        var before = hp;
        hp = value;
        if (!busy && damageDepth == 0) observe(before, value);
    }

    /** 只认实际HP回升；降低最大HP、换装或重建本身不构成治疗。 */
    private function resetIfRecovered(before, after):Void {
        if (unit.__playerStatInitializing === true
                || (unit.__playerSceneSpawn != undefined && unit.__playerSceneSpawn.resourcesReady !== true)
                || (unit.__resourceSpawn != undefined && unit.__resourceSpawn.resourcesReady !== true)) return;
        var maximum:Number = unit.hp满血值;
        if (typeof maximum != "number" || (maximum - maximum) != 0 || !(maximum > 0)
                || typeof before != "number" || typeof after != "number"
                || (before - before) != 0 || (after - after) != 0) return;
        var threshold:Number = maximum * EmergencyInjectionService.RESET_RATIO;
        // 也承认卸装/资源初始化期间完成、在下一次稳定观察前已存在的真实净回复。
        if ((before > memory.lastHp && before >= threshold)
                || (after > before && after >= threshold)) memory.used = false;
        memory.lastHp = after;
    }

    /** 药剂事务是低频冷边界，异常隔离不得改写原扣血或重放未知消费。 */
    private function observe(before, after):Void {
        if (memory.used) resetIfRecovered(before, after);
        if (busy || !installed || typeof before != "number" || typeof after != "number"
                || (before - before) != 0 || (after - after) != 0 || !(after > 0) || !(after < before)) return;
        observedDrops++;
        memory.observedDrops = observedDrops;
        var maximum:Number = unit.hp满血值;
        if (memory.used || typeof maximum != "number" || (maximum - maximum) != 0 || !(maximum > 0)
                || after > maximum * EmergencyInjectionService.TRIGGER_RATIO
                || DrugInputService.isApplyingDrugEffect()) return;
        if (unit.version !== version || unit.__emergencyInjector !== this
                || unit.__emergencyInjectionProvider !== provider || root.暂停
                || root.当前玩家总数 != 1 || root.gameworld[root.控制目标] !== unit
                || unit.__playerStatInitializing === true
                || (unit.__playerSceneSpawn != undefined && unit.__playerSceneSpawn.resourcesReady !== true)
                || (unit.__resourceSpawn != undefined && unit.__resourceSpawn.resourcesReady !== true)
                || EmergencyInjectionService.read(root) !== config || !config.enabled
                || config.__invalidated === true) return;
        busy = true;
        var attemptBefore = hp;
        try {
            if (provider.emergencyInjectionEligible() !== true) return;
            var inventory:Object = root.物品栏.药剂栏;
            var item:Object = inventory.getItem(String(config.physicalSlot));
            if (!item || item.name !== config.itemKey || !(item.value > 0)
                    || !ManualCooldownService.isReady(ManualCooldownService.drugKey(config.physicalSlot % 4))) return;
            memory.used = true;
            memory.lastHp = hp;
            attempts++; memory.attempts = attempts;
            lastBefore = hp;
            var result:Object = DrugInputService.tryConsumePhysicalSlot(unit, config.physicalSlot,
                inventory, root, config.itemKey);
            // 完整资格被领域预检拒绝时，危机机会尚未发生；只等下一次合法下降事件。
            if (result == null || result.effectAttempted !== true) memory.used = false;
            if (result.used) { doses++; memory.doses = doses; }
            lastAfter = hp;
        } catch (injectionError) {
            memory.used = true;
            memory.lastHp = attemptBefore;
            lastError = String(injectionError);
            trace("[EmergencyInjection] consumption failed: " + injectionError);
        } finally {
            busy = false;
            resetIfRecovered(attemptBefore, hp);
        }
    }

    /** Calculator回调递归一层；访问器只记录中间写，最终成功提交后才评估一次。 */
    public function settleDamage(bullet:Object, shooter:Object, target:Object,
                                 overlapRatio:Number, dodgeState:String):DamageResult {
        var before = hp;
        var completed:Boolean = false;
        damageDepth++;
        try {
            var result:DamageResult = DamageCalculator.calculateDamage(bullet, shooter, target, overlapRatio, dodgeState);
            completed = true;
            return result;
        } finally {
            damageDepth--;
            if (completed && damageDepth == 0) observe(before, hp);
        }
    }
}
