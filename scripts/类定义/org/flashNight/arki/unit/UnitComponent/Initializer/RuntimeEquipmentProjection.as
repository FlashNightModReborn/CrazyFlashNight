/**
 * RuntimeEquipmentProjection - 权威装备投影与运行态槽位借用控制器。
 *
 * 装备栏/装扮加载得到的 11 槽是 canonical authority；装备生命周期可以在目标槽
 * 为空时申请一个有所有权的运行态 alias，但不得改写 canonical snapshot。角色构筑
 * 只比较 canonical snapshot，战斗代码在兼容期仍可读取被物化的 target[slot]。
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection {
    public static var STATUS_ALIGNED:String = "aligned";
    public static var STATUS_MISMATCH:String = "mismatch";
    public static var STATUS_INVALID:String = "invalid";

    private static var STATE_KEY:String = "__runtimeEquipmentProjectionV1";
    private static var STATE_VERSION:Number = 1;
    private static var _generationCounter:Number = 0;
    private static var SLOT_KEYS:Array = [
        "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
        "长枪", "手枪", "手枪2", "刀", "手雷"
    ];

    /**
     * 在 Dressup 完成 11 槽 canonical load 之后、任何装备 lifecycle 之前冻结输入。
     */
    public static function beginCanonical(target:Object):Object {
        if (target == null) return null;
        var refs:Array = [];
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            refs[i] = target[SLOT_KEYS[i]];
        }
        var signature:String = buildSemanticSignature(refs);
        var state:Object = {
            schemaVersion:STATE_VERSION,
            generation:++_generationCounter,
            phase:signature == null ? "invalid" : "building",
            unitVersion:target.version,
            refs:refs,
            semanticSignature:signature,
            intents:{},
            failure:signature == null ? "invalid_canonical_loadout" : ""
        };
        target[STATE_KEY] = state;
        return signature == null ? null : state;
    }

    /** lifecycle 全部安装后提交；未提交 intent 或未登记的裸槽改写都会使投影失效。 */
    public static function completeCanonical(target:Object):Boolean {
        var state:Object = readState(target);
        if (state == null || state.phase != "building") return false;
        if (!validateRuntimeState(target, state)) {
            state.phase = "invalid";
            if (state.failure == "") state.failure = "runtime_projection_invalid";
            return false;
        }
        state.phase = "complete";
        return true;
    }

    /**
     * 为 lifecycle owner 预留一个 canonical 空槽。调用方完成目标槽属性配置后必须
     * 立即 commitSlotAlias；未提交 reservation 会使 completeCanonical 失败。
     */
    public static function reserveEmptySlotAlias(ref:Object,
                                                 targetSlot:String):Object {
        if (ref == null || ref.自机 == null) return null;
        var target:Object = ref.自机;
        var state:Object = readState(target);
        if (state == null || state.phase != "building") return null;

        var sourceSlot:String = String(ref.装备类型 || "");
        var sourceIndex:Number = slotIndex(sourceSlot);
        var targetIndex:Number = slotIndex(String(targetSlot));
        if (sourceIndex < 0 || targetIndex < 0 || sourceIndex == targetIndex) return null;
        if (ref.版本号 !== state.unitVersion) return null;

        var sourceRef:Object = state.refs[sourceIndex];
        if (sourceRef == null || target[sourceSlot] !== sourceRef) return null;
        if (state.refs[targetIndex] != null || target[targetSlot] !== state.refs[targetIndex]) {
            return null;
        }
        if (ref.装备名称 != undefined
                && String(ref.装备名称) != String(sourceRef.name)) return null;

        var existing:Object = state.intents[targetSlot];
        if (existing != undefined) {
            if (existing.ownerRef === ref && existing.sourceSlot == sourceSlot) {
                return existing;
            }
            state.failure = "slot_alias_conflict:" + targetSlot;
            return null;
        }

        var intent:Object = {
            state:state,
            generation:state.generation,
            target:target,
            targetSlot:String(targetSlot),
            targetIndex:targetIndex,
            sourceSlot:sourceSlot,
            sourceIndex:sourceIndex,
            sourceRef:sourceRef,
            ownerRef:ref,
            ownerVersion:ref.版本号,
            committed:false
        };
        state.intents[targetSlot] = intent;
        return intent;
    }

    /** 将已配置的目标槽最终物化为 source exact ref。 */
    public static function commitSlotAlias(intent:Object):Boolean {
        if (!validIntent(intent)) return false;
        var state:Object = intent.state;
        var target:Object = intent.target;
        if (state.intents[intent.targetSlot] !== intent
                || target[intent.sourceSlot] !== intent.sourceRef
                || intent.ownerVersion !== target.version) return false;
        target[intent.targetSlot] = intent.sourceRef;
        intent.committed = true;
        return true;
    }

    /** reservation/commit 失败后的幂等回滚。只恢复仍由本 intent 持有的槽位。 */
    public static function cancelSlotAlias(intent:Object):Void {
        if (intent == null || intent.target == null || intent.state == null) return;
        var state:Object = intent.state;
        if (state.intents[intent.targetSlot] !== intent) return;
        if (!intent.committed || intent.target[intent.targetSlot] === intent.sourceRef) {
            intent.target[intent.targetSlot] = state.refs[intent.targetIndex];
        }
        delete state.intents[intent.targetSlot];
        intent.committed = false;
    }

    /** lifecycle teardown 的统一回收边界；stale cleanup 不覆盖后来写入的真实装备。 */
    public static function releaseAliases(target:Object):Void {
        var state:Object = readState(target);
        if (state == null) return;
        for (var targetSlot:String in state.intents) {
            var intent:Object = state.intents[targetSlot];
            if (intent != null && intent.committed
                    && target[targetSlot] === intent.sourceRef) {
                target[targetSlot] = state.refs[intent.targetIndex];
            }
            if (intent != null) intent.committed = false;
        }
        state.intents = {};
        state.phase = "released";
        delete target[STATE_KEY];
    }

    /** 当前装备 authority 相对最后一次完整 Dressup 投影的状态。 */
    public static function getStatus(target:Object, currentRefs:Array):String {
        var state:Object = readState(target);
        if (state == null || state.phase != "complete"
                || currentRefs == null || currentRefs.length != SLOT_KEYS.length) {
            return STATUS_INVALID;
        }
        var signature:String = buildSemanticSignature(currentRefs);
        if (signature == null) return STATUS_INVALID;
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            if (state.refs[i] !== currentRefs[i]) return STATUS_MISMATCH;
        }
        if (state.semanticSignature != signature) return STATUS_MISMATCH;
        return validateRuntimeState(target, state) ? STATUS_ALIGNED : STATUS_MISMATCH;
    }

    public static function getCanonicalRef(target:Object, slot:String) {
        var state:Object = readState(target);
        var index:Number = slotIndex(String(slot));
        if (state == null || index < 0) return undefined;
        return state.refs[index];
    }

    public static function hasActiveAlias(target:Object, targetSlot:String,
                                          sourceSlot:String):Boolean {
        var state:Object = readState(target);
        if (state == null) return false;
        var intent:Object = state.intents[targetSlot];
        return intent != null && intent.committed
            && intent.sourceSlot == sourceSlot
            && target[targetSlot] === intent.sourceRef;
    }

    public static function getSlotKeys():Array {
        return SLOT_KEYS.concat();
    }

    /**
     * 只覆盖需要重建派生装备数据的语义；弹药、换弹、当前战技、形态和 lastUpdate
     * 都不是 live projection identity。
     */
    public static function buildSemanticSignature(refs:Array):String {
        if (refs == null || refs.length != SLOT_KEYS.length) return null;
        var parts:Array = ["slots", SLOT_KEYS.length];
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            var key:String = String(SLOT_KEYS[i]);
            var item:Object = refs[i];
            parts.push("k", stringToken(key));
            if (item == null) {
                parts.push("empty");
                continue;
            }
            if (typeof item != "object" || typeof item.name != "string") return null;
            parts.push("item", valueToken(item.name));
            var value = item.value;
            if (typeof value == "number") {
                parts.push("stack");
            } else if (typeof value == "object" && value != null) {
                parts.push("equipment", valueToken(value.level), valueToken(value.tier),
                    modifierToken(value.mods));
            } else {
                return null;
            }
        }
        return parts.join("|");
    }

    private static function validIntent(intent:Object):Boolean {
        if (intent == null || intent.state == null || intent.target == null) return false;
        var state:Object = intent.state;
        return state.phase == "building" && state.generation == intent.generation
            && readState(intent.target) === state;
    }

    private static function validateRuntimeState(target:Object,
                                                 state:Object):Boolean {
        if (target == null || state == null || state.refs == null
                || state.refs.length != SLOT_KEYS.length
                || state.unitVersion !== target.version
                || state.failure != "") return false;
        for (var intentSlot:String in state.intents) {
            var pending:Object = state.intents[intentSlot];
            if (pending == null || !pending.committed
                    || pending.state !== state || pending.target !== target
                    || pending.generation != state.generation
                    || pending.ownerVersion !== state.unitVersion
                    || pending.sourceRef !== state.refs[pending.sourceIndex]) return false;
        }
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            var slot:String = String(SLOT_KEYS[i]);
            var expected = state.refs[i];
            var intent:Object = state.intents[slot];
            if (intent != undefined) expected = intent.sourceRef;
            if (target[slot] !== expected) return false;
        }
        return true;
    }

    private static function readState(target:Object):Object {
        if (target == null) return null;
        var state:Object = target[STATE_KEY];
        return state != null && state.schemaVersion == STATE_VERSION ? state : null;
    }

    private static function slotIndex(slot:String):Number {
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            if (String(SLOT_KEYS[i]) == slot) return i;
        }
        return -1;
    }

    private static function modifierToken(mods):String {
        var values:Array = [];
        var i:Number;
        if (mods instanceof Array) {
            values.push("array", mods.length);
            for (i = 0; i < mods.length; i++) values.push(valueToken(mods[i]));
            return values.join(",");
        }
        if (typeof mods == "object" && mods != null) {
            var keys:Array = [];
            for (var key:String in mods) keys.push(String(key));
            keys.sort();
            values.push("object", keys.length);
            for (i = 0; i < keys.length; i++) {
                var sortedKey:String = String(keys[i]);
                values.push(stringToken(sortedKey), valueToken(mods[sortedKey]));
            }
            return values.join(",");
        }
        return "other," + valueToken(mods);
    }

    private static function valueToken(value):String {
        if (value == undefined) return "u";
        if (value == null) return "z";
        var typeName:String = typeof value;
        if (typeName == "string") return "s" + stringToken(String(value));
        if (typeName == "number") {
            if (isNaN(value)) return "n:NaN";
            if (value == Number.POSITIVE_INFINITY) return "n:+Inf";
            if (value == Number.NEGATIVE_INFINITY) return "n:-Inf";
            return "n:" + String(value);
        }
        if (typeName == "boolean") return value ? "b:1" : "b:0";
        return typeName + ":" + stringToken(String(value));
    }

    private static function stringToken(value:String):String {
        return value.length + ":" + value;
    }
}
