import org.flashNight.arki.item.ItemUtil;

/** 弹药业务权威。shot 保持旧消费者的 C-总弹数合同；ammoState 只记录来源与付费拆包余额。
 * 普通弹容不含任何超装；配件 merge 只能提高 ghostLimit，不能授予结构资格。
 * 新余额随武器 value 持久化，reloadCount 仅保留枪械师的战术回收语义。
 */
class org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime {
    private static var rewardSession:String;
    private static var rewardBoundary:Number = 0;
    private static var endedRewardRun:String;

    private static function rewardScope():String {
        var runId:String = org.flashNight.arki.scene.StageRunSession.getCurrentRunId();
        if (runId != "" && runId != endedRewardRun) return "run:" + runId;
        if (rewardSession == undefined) rewardSession = String(new Date().getTime()) + ":" + String(getTimer());
        return "session:" + rewardSession + ":" + rewardBoundary;
    }

    /** 出击边界使背包/仓库中未装备武器的旧奖励也失效；下次装载时仅清奖励，不动付费弹。 */
    public static function endSortie():Void {
        endedRewardRun = org.flashNight.arki.scene.StageRunSession.getCurrentRunId();
        rewardBoundary++;
    }
    public static function count(value):Number {
        var n:Number = Number(value);
        return n > 0 && isFinite(n) ? Math.floor(n) : 0;
    }

    public static function capacity(unit:Object, slot:String):Number {
        return count(unit[slot + "弹匣容量"]);
    }

    public static function extras(state:Object):Number {
        return count(state.chamber) + count(state.ghost) + count(state.reward);
    }

    public static function normal(value:Object, cap:Number):Number {
        var shot:Number = Number(value.shot);
        if (isNaN(shot)) shot = 0;
        return Math.max(0, cap - shot - extras(value.ammoState));
    }

    public static function chamberLimit(unit:Object, slot:String):Number {
        return Math.min(2, count(unit[slot + "属性"].overload.chamber));
    }

    public static function ghostLimit(unit:Object, slot:String):Number {
        var config:Object = unit[slot + "属性"].overload;
        if (!(count(config.ghost) > 0) || !unit.被动技能.冲击连携.启用) return 0;
        return Math.min(2, Math.max(count(config.ghost), count(config.ghostLimit)));
    }

    public static function rewardLimit(unit:Object, slot:String):Number {
        return unit[slot + "属性"].overload.reward ? capacity(unit, slot) : 0;
    }

    public static function reserve(unit:Object, slot:String):Number {
        var value:Object = unit[slot].value;
        if (value.ammoState) return value.ammoState.reserveName == unit[slot + "属性"].clipname
            ? count(value.ammoState.reserve) : 0;
        return unit[slot + "属性"].reloadType == "tube" ? count(value.reloadCount) : 0;
    }

    /** 仅在初始化、真实提交或配置变化时调用；HUD 只读取，不在采样中修复业务状态。 */
    public static function ensure(unit:Object, slot:String, deferMissingSkills:Boolean):Object {
        var value:Object = unit[slot].value;
        var cap:Number = capacity(unit, slot);
        if (!value || !(cap > 0)) return null;
        var attrs:Object = unit[slot + "属性"];
        if (!value.ammoState && attrs.reloadType != "tube" && !(count(attrs.overload.chamber) > 0)
                && !(count(attrs.overload.ghost) > 0) && !attrs.overload.reward) {
            // 普通枪仍需初始化射击计数；新物品和旧存档都可能没有该字段。
            var plainShot:Number = Number(value.shot);
            if (!isFinite(plainShot) || plainShot < 0) value.shot = 0;
            return null;
        }
        var state:Object = value.ammoState;
        if (!state || state.v != 1) {
            var legacyShot:Number = Number(value.shot);
            if (isNaN(legacyShot)) legacyShot = 0;
            state = {v:1, capacity:cap, chamber:0, ghost:0, reward:0, paidNormal:0, paidChamber:0,
                reserve:attrs.reloadType == "tube" ? count(value.reloadCount) : 0,
                reserveName:String(attrs.clipname), rewardScope:rewardScope()};
            if (legacyShot < 0 && rewardLimit(unit, slot) > 0
                    && (_root.当前为战斗地图 === true || org.flashNight.arki.scene.StageRunSession.getCurrentRunId() != "")) {
                state.reward = Math.min(-legacyShot, rewardLimit(unit, slot));
            }
            value.ammoState = state;
            if (attrs.reloadType == "tube") value.reloadCount = 0;
            value.shot = Math.max(-state.reward, legacyShot);
        }
        if (count(state.reward) > 0 && state.rewardScope != rewardScope()) {
            value.shot += count(state.reward);
            state.reward = 0;
        }
        var oldCap:Number = count(state.capacity);
        if (!(oldCap > 0)) oldCap = cap;
        // 兼容尚未迁移的装备专用扣弹旁路：外部扣弹只能减少来源，不能被 ensure 补回来。
        var overTagged:Number = extras(state) - Math.max(0, oldCap - Number(value.shot));
        if (overTagged > 0) {
            var consumed:Number = Math.min(overTagged, count(state.ghost));
            state.ghost -= consumed; overTagged -= consumed;
            consumed = Math.min(overTagged, count(state.reward));
            state.reward -= consumed; overTagged -= consumed;
            state.chamber = Math.max(0, count(state.chamber) - overTagged);
        }
        state.paidChamber = Math.min(count(state.paidChamber), count(state.chamber));
        var currentName:String = String(attrs.clipname);
        if (state.reserveName != currentName && state.reserveName != "undefined") {
            if (!state.reserves) state.reserves = {};
            // 更换真实弹种时卸下旧装填：只退回已付费来源，不能把旧弹按新弹种结算。
            var paidLoaded:Number = Math.min(count(state.paidNormal), normal(value, oldCap))
                + count(state.paidChamber) + count(state.ghost);
            state.reserves[state.reserveName] = count(state.reserves[state.reserveName]) + count(state.reserve) + paidLoaded;
            value.shot = oldCap;
            state.chamber = state.ghost = state.reward = state.paidNormal = state.paidChamber = 0;
            state.reserve = count(state.reserves[currentName]);
            delete state.reserves[currentName];
            state.reserveName = currentName;
        }
        var loaded:Number = Math.min(oldCap, normal(value, oldCap));
        state.paidNormal = Math.min(count(state.paidNormal), loaded);
        // 免费初始弹/基地补给/奖励不能通过反复扩容、拆装变成付费余额。
        var refund:Number = Math.min(state.paidNormal, Math.max(0, loaded - cap));
        state.paidNormal -= refund;
        loaded = Math.min(loaded, cap);
        var limit:Number = chamberLimit(unit, slot);
        var chamberRefund:Number = Math.min(state.paidChamber, Math.max(0, count(state.chamber) - limit));
        refund += chamberRefund;
        state.paidChamber -= chamberRefund;
        state.chamber = Math.min(count(state.chamber), limit);
        limit = ghostLimit(unit, slot);
        if (deferMissingSkills && unit.被动技能 == undefined && count(attrs.overload.ghost) > 0)
            limit = Math.min(2, Math.max(count(attrs.overload.ghost), count(attrs.overload.ghostLimit)));
        refund += Math.max(0, count(state.ghost) - limit);
        state.ghost = Math.min(count(state.ghost), limit);
        state.reward = Math.min(count(state.reward), rewardLimit(unit, slot));
        state.reserve = count(state.reserve) + refund;
        state.capacity = cap;
        // 弹种转换不把旧付费弹药冒充新弹药。余额保留其原弹种，消费入口会拒绝不匹配。
        if (state.reserveName == undefined || state.reserveName == "undefined") state.reserveName = String(attrs.clipname);
        value.shot = cap - loaded - extras(state);
        return state;
    }

    public static function setNormal(value:Object, cap:Number, rounds:Number):Void {
        value.shot = cap - Math.min(cap, Math.max(0, rounds)) - extras(value.ammoState);
        if (value.ammoState) value.ammoState.paidNormal = Math.min(count(value.ammoState.paidNormal), normal(value, cap));
    }

    /** 提前换弹把一发已有普通弹移到留膛来源，弹药总量不变，不赠送子弹。 */
    public static function beginReload(unit:Object, slot:String):Void {
        var state:Object = ensure(unit, slot);
        if (!state) return;
        var value:Object = unit[slot].value;
        var move:Number = Math.min(normal(value, state.capacity), chamberLimit(unit, slot) - state.chamber);
        if (move > 0) {
            var paidMove:Number = Math.min(move, count(state.paidNormal));
            state.paidNormal -= paidMove;
            state.paidChamber += paidMove;
            state.chamber += move;
            markDirty(_root.控制目标 == unit._name);
        }
    }

    public static function canReload(unit:Object, slot:String, allowGhost:Boolean):Boolean {
        var state:Object = ensure(unit, slot);
        if (!state) return Number(unit[slot].value.shot) > 0;
        var ordinary:Number = normal(unit[slot].value, state.capacity);
        return ordinary < state.capacity
            || (ordinary > 0 && state.chamber < chamberLimit(unit, slot))
            || (allowGhost && state.ghost < ghostLimit(unit, slot));
    }

    public static function missing(unit:Object, slot:String, allowGhost:Boolean):Number {
        var state:Object = unit[slot].value.ammoState;
        if (!state) return 0;
        return Math.max(0, state.capacity - normal(unit[slot].value, state.capacity))
            + (allowGhost ? Math.max(0, ghostLimit(unit, slot) - state.ghost) : 0);
    }

    /** 一包只提供普通弹容份额，额外容量永不反哺每包预算；库存成功提交后才记余额。 */
    public static function spend(unit:Object, slot:String, rounds:Number, magazine:String, isHero:Boolean):Boolean {
        var state:Object = ensure(unit, slot);
        if (!state || !(rounds > 0)) return false;
        if (!isHero) return true;
        if (magazine != String(unit[slot + "属性"].clipname)) return false;
        if (state.reserve > 0 && state.reserveName != magazine) return false;
        var packs:Number = Math.max(0, Math.ceil((rounds - state.reserve) / state.capacity));
        if (packs > 0 && isHero && !ItemUtil.singleSubmit(magazine, packs,
                {source:"reload", reason:"ammo_packet", mergeScope:"operation"})) return false;
        if (packs > 0) state.reserveName = magazine;
        state.reserve += packs * state.capacity - rounds;
        markDirty(isHero);
        return true;
    }

    public static function fillRounds(unit:Object, slot:String, batch:Number, allowGhost:Boolean,
            magazine:String, isHero:Boolean):Number {
        var state:Object = ensure(unit, slot);
        if (!state) return 0;
        var amount:Number = Math.min(count(batch), missing(unit, slot, allowGhost));
        if (isHero && state.reserve > 0) amount = Math.min(amount, state.reserve);
        if (!(amount > 0) || !spend(unit, slot, amount, magazine, isHero)) return 0;
        var value:Object = unit[slot].value;
        var ordinary:Number = normal(value, state.capacity);
        var mainAmount:Number = Math.min(amount, state.capacity - ordinary);
        state.ghost += amount - mainAmount;
        setNormal(value, state.capacity, ordinary + mainAmount);
        if (isHero) state.paidNormal += mainAmount;
        markDirty(isHero);
        return amount;
    }

    /** 整匣路径同样消费拆包余额；tube 保留余弹，盒式换匣仍保留原有丢弃/枪械师回收规则。 */
    public static function fillMagazine(unit:Object, slot:String, magazine:String, isHero:Boolean):Boolean {
        var state:Object = ensure(unit, slot);
        if (!state) return false;
        var value:Object = unit[slot].value;
        if (!(normal(value, state.capacity) < state.capacity)) return true;
        var tube:Boolean = unit[slot + "属性"].reloadType == "tube";
        var ordinary:Number = normal(value, state.capacity);
        var amount:Number = tube ? state.capacity - ordinary : state.capacity;
        if (isHero) {
            var available:Number = state.reserve + state.capacity * count(ItemUtil.getTotal(magazine));
            amount = Math.min(amount, available);
            if (!(amount > 0) || (!tube && !(amount > ordinary))) return false;
        }
        var paidBefore:Number = count(state.paidNormal);
        if (amount > 0 && !spend(unit, slot, amount, magazine, isHero)) return false;
        setNormal(value, state.capacity, tube ? ordinary + amount : amount);
        if (isHero) state.paidNormal = tube ? Math.min(state.capacity, paidBefore + amount) : amount;
        markDirty(isHero);
        return true;
    }

    /** 真实发射一次：幽灵→奖励→留膛→普通。逐发惩罚必须在本调用之前快照。 */
    public static function consume(unit:Object, slot:String):Void {
        var value:Object = unit[slot].value;
        var state:Object = value.ammoState;
        if (state) {
            if (state.ghost > 0) state.ghost--;
            else if (state.reward > 0) state.reward--;
            else if (state.chamber > 0) {
                state.chamber--;
                state.paidChamber = Math.max(0, count(state.paidChamber) - 1);
            } else state.paidNormal = Math.max(0, count(state.paidNormal) - 1);
        }
        value.shot++;
        if (state) markDirty(_root.控制目标 == unit._name);
    }

    public static function addReward(unit:Object, slot:String, rounds:Number):Number {
        var state:Object = ensure(unit, slot);
        if (!state) return 0;
        var value:Object = unit[slot].value;
        var ordinary:Number = normal(value, state.capacity);
        var amount:Number = count(rounds);
        var mainAmount:Number = Math.min(amount, state.capacity - ordinary);
        var extraAmount:Number = Math.min(amount - mainAmount, rewardLimit(unit, slot) - state.reward);
        state.reward += extraAmount;
        state.rewardScope = rewardScope();
        setNormal(value, state.capacity, ordinary + mainAmount);
        if (mainAmount + extraAmount > 0) markDirty(_root.控制目标 == unit._name);
        return mainAmount + extraAmount;
    }

    public static function ghostMultiplier(unit:Object, slot:String):Number {
        var cap:Number = capacity(unit, slot);
        return cap > 0 ? 1 + Math.min(2, 2 * count(unit[slot].value.ammoState.ghost) / cap) : 1;
    }

    /** 免费补给只补普通仓；付费弹和拆包余额保留。结束出击才清奖励来源。 */
    public static function supplyValue(value:Object, clearReward:Boolean):Void {
        var state:Object = value.ammoState;
        if (!state || state.v != 1) {
            if (clearReward || !(Number(value.shot) < 0)) value.shot = 0;
            return;
        }
        if (clearReward) state.reward = 0;
        value.shot = -extras(state);
    }

    /** 背包/切场景没有活跃角色时，仅迁移旧 tube 付费额度，不依据缺失的技能状态收缩来源。 */
    public static function migrateItem(item:Object, attrs:Object):Void {
        var value:Object = item.value;
        if (!value || value.ammoState || attrs.reloadType != "tube") return;
        var cap:Number = count(attrs.capacity);
        if (!(cap > 0)) return;
        value.ammoState = {v:1, capacity:cap, chamber:0, ghost:0, reward:0, paidNormal:0, paidChamber:0,
            reserve:count(value.reloadCount), reserveName:String(attrs.clipname)};
        value.reloadCount = 0;
    }

    private static function markDirty(isHero:Boolean):Void {
        if (isHero && _root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
    }
}
