import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.scene.StageReturnFlow;

/** 只读资源预检与真实输入拒绝反馈。不得调用释放许可函数（旧战技中含扣物品）。 */
class org.flashNight.arki.skill.SkillResourceService {
    private static var serial:Number = 0;
    private static var lastSound:Number = -10000;

    public static function state(value:String, reason:String):Object {
        return {state:value, reason:reason};
    }
    public static function fixedCost(available:Number, minimum:Number, payment:Number, reason:String):Object {
        if (!isFinite(available) || !isFinite(minimum) || !isFinite(payment) || minimum < 0 || payment < 0)
            return state("unknown", "");
        if (available < minimum) return state("blocked", reason);
        return minimum > 0 && available - payment < minimum ? state("last", reason) : state("ready", "");
    }
    private static function combine(first:Object, second:Object):Object {
        if (first.state == "blocked") return first;
        if (second.state == "blocked") return second;
        if (first.state == "last") return first;
        if (second.state == "last") return second;
        return first.state == "unknown" || second.state == "unknown" ? state("unknown", "") : first;
    }
    /** Same contain authority as actual submit: backpack + all eight drug slots, plus explicit grenade fallback. */
    public static function itemState(name:String, grenadeFallback:Boolean, readItems:Object):Object {
        var key:String = name + (grenadeFallback ? ":grenade" : ":inventory");
        if (readItems != null && readItems[key] != undefined) return readItems[key];
        var result:Object = readItemState(name, grenadeFallback);
        if (readItems != null) readItems[key] = result;
        return result;
    }
    private static function readItemState(name:String, grenadeFallback:Boolean):Object {
        if (name == undefined || name == "") return state("unknown", "");
        var fallback:Number = 0;
        var grenade:Object = _root.物品栏.装备栏.getItem("手雷");
        if (grenadeFallback && grenade && grenade.name == name)
            fallback = isNaN(Number(grenade.value)) ? 1 : Math.max(0, Number(grenade.value));
        if (fallback >= 2 || ItemUtil.singleContain(name, Math.max(0, 2 - fallback)) != null)
            return state("ready", "");
        if (fallback >= 1 || ItemUtil.singleContain(name, 1) != null) return state("last", "item");
        return state("blocked", "item");
    }
    public static function quick(unit:Object, name:String, cost:Number, readItems:Object):Object {
        var result:Object = fixedCost(Number(unit.mp), cost, cost, "mp");
        if (name == "能量盾" && unit._name == _root.控制目标) result = combine(result, itemState("能量电池", false, readItems));
        return result;
    }
    public static function weapon(unit:Object, skill:Object, readItems:Object):Object {
        if (!skill || skill.isSubweaponControl === true) return state("unknown", "");
        // 猩红天秤等原子战技按缺口付款，零 MP 合法。不可套用配置中的固定消耗。
        if (skill.战技函数.原子释放 === true && skill.战技函数.固定资源消耗 !== true) return state("ready", "");
        var cost:Number = Number(skill.消耗mp);
        var minimum:Number = cost;
        var payment:Number = cost;
        if (skill.战技函数 === _root.主动战技函数.空手.贯空天盖战技 && skill.战技函数 != undefined) {
            var equipment:Object = _root.物品栏.装备栏;
            var names:Array = ["咒针", "伸手及月"];
            if (equipment.getNameString("头部装备") == "登上明星") names.push("登上明星");
            if (equipment.getNameString("上装装备") == "贯空天盖上衣") names.push("回归枢机之光");
            var selected:String = names[Number(equipment.getItem("手部装备").value.当前战技)];
            // 旧业务先扣基础费用，之后要求剩余 >= 300，再扣 200；保持原规则。
            if (selected == "回归枢机之光" && !(unit.回归枢机之光发射数 >= 5)) { minimum += 300; payment += 200; }
        }
        var result:Object = fixedCost(Number(unit.mp), minimum, payment, "mp");
        if (skill.战技函数 != undefined && skill.战技函数 === _root.主动战技函数.长枪.调用射击发射其他弹药)
            result = combine(result, itemState(unit.其他消耗物品, true, readItems));
        // 通过技能路由调用能量盾的战技沿用相同材料门槛。
        if (skill.名字 == "能量盾" && unit._name == _root.控制目标) result = combine(result, itemState("能量电池", false, readItems));
        return result;
    }
    public static function snapshot(unit:Object, loadout:Object):Object {
        var readItems:Object = {};
        var skills:Array = [];
        var drugs:Array = [];
        var i:Number;
        for (i = 0; i < 12; i++) {
            var slot:Object = loadout.skills[i];
            skills.push(slot.equipped === true && slot.writeBlocked !== true
                ? quick(unit, slot.skillKey, Number(slot.mp), readItems) : state("unknown", ""));
        }
        for (i = 0; i < 4; i++) {
            var drug:Object = loadout.drugs[i];
            drugs.push(drug.name == "" ? state("unknown", "") : fixedCost(Number(drug.count), 1, 1, "item"));
        }
        var notice:Object = unit.__skillResourceNotice;
        if (_root.暂停 || !(unit.hp > 0) || notice == null || getTimer() - notice.at > 600
                || notice.world !== StageReturnFlow.worldIdentity(_root.gameworld)) {
            // Retire display-only messages as well as hiding them: a coalesced pause packet
            // may arrive before the denial, so the receiver has not necessarily seen its serial.
            delete unit.__skillResourceNotice;
            notice = null;
        }
        var weaponHint:Object = weapon(unit, unit.主动战技[unit.攻击模式], readItems);
        return {skills:skills, drugs:drugs, weapon:weaponHint,
            switchBlocked:!DrugInputService.hasBankStock(_root, 1 - Number(loadout.bank)),
            feedback:notice == null ? null : {serial:notice.serial, kind:notice.kind, slot:notice.slot, reason:notice.reason}};
    }
    public static function begin(unit:Object, kind:String, slot:Number):Void {
        if (unit) unit.__skillResourceAttempt = {kind:kind, slot:slot, reason:""};
    }
    /** Only called at the real rejection branch; projections never publish or play sounds. */
    public static function reject(unit:Object, reason:String):Boolean {
        var attempt:Object = unit.__skillResourceAttempt;
        if (attempt != null) attempt.reason = reason;
        return false;
    }
    public static function finish(unit:Object):Void {
        var attempt:Object = unit.__skillResourceAttempt;
        delete unit.__skillResourceAttempt;
        if (attempt == null || attempt.reason == "" || unit._name != _root.控制目标 || _root.暂停 || !(unit.hp > 0)) return;
        var now:Number = getTimer();
        unit.__skillResourceNotice = {serial:++serial, at:now, world:StageReturnFlow.worldIdentity(_root.gameworld),
            kind:attempt.kind, slot:attempt.slot, reason:attempt.reason};
        // Empty-bank navigation only flashes its seal. Resource denials share one audio budget.
        if (attempt.reason != "empty" && now - lastSound >= 1000 && typeof _root.播放音效 == "function") {
            lastSound = now;
            _root.播放音效("message_ui.wav");
        }
    }
    public static function notify(unit:Object, kind:String, slot:Number, reason:String):Void {
        begin(unit, kind, slot); reject(unit, reason); finish(unit);
    }
    public static function describe(hint:Object):String {
        if (hint == null || hint.state == "ready" || hint.state == "unknown") return "";
        var resource:String = hint.reason == "mp" ? "MP" : "消耗品";
        return hint.state == "blocked" ? "<BR><FONT COLOR='#e87864'>" + resource + "不足，无法释放</FONT>"
            : "<BR><FONT COLOR='#e8a080'>当前" + resource + "仅够再释放一次</FONT>";
    }
}
