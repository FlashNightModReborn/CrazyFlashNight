/**
 * 技能存档与 12 槽快捷栏的唯一领域 facade。
 *
 * 读取永不修档；所有写先同步 legacy 漂移并校验 revision，再原地提交。
 * 重复技能行、非法等级和 80 行后的非空数据都按契约 fail-closed。
 */
class org.flashNight.arki.skill.SkillLoadoutService {
    public static var SKILL_ROW_COUNT:Number = 80;
    public static var QUICK_SLOT_COUNT:Number = 12;

    private static var _revision:Number = 0;
    private static var _signature:String = null;
    private static var _lastScan:Object = null;
    private static var _testRoot:Object = null;
    private static var _testRejectNextCommit:Boolean = false;
    private static var _testRejectedState:Object = null;
    private static var _rendererDiagnostics:Array = [];

    public static function root():Object {
        return _testRoot == null ? _root : _testRoot;
    }

    public static function isReady():Boolean {
        var r:Object = root();
        return r != null
            && r.技能表对象 != null
            && r.主角技能表 instanceof Array
            && r.存档系统 != null
            && typeof r.动态更新技能冷却领域 == "function"
            && isFiniteNumber(r.等级)
            && isFiniteNumber(r.技能点数);
    }

    public static function synchronize():Object {
        if (!isReady()) return {success:false, v:1, error:"service_not_ready", revision:_revision};
        var scan:Object = scanState();
        if (_signature == null) {
            _signature = scan.signature;
        } else if (_signature != scan.signature) {
            _revision++;
            _signature = scan.signature;
        }
        _lastScan = scan;
        return {success:true, v:1, revision:_revision, scan:scan};
    }

    public static function getRevision():Number {
        var sync:Object = synchronize();
        return sync.success ? sync.revision : _revision;
    }

    public static function inspectSkill(skillKey:String):Object {
        var sync:Object = synchronize();
        if (!sync.success) return sync;
        return inspectFromScan(sync.scan, skillKey);
    }

    public static function findLearnTargetIndex():Number {
        var sync:Object = synchronize();
        if (!sync.success || sync.scan.tailData) return -1;
        var table:Array = root().主角技能表;
        for (var i:Number = 0; i < SKILL_ROW_COUNT; i++) {
            if (i >= table.length || !table.hasOwnProperty(String(i))) return i;
            if (isEmptyRow(table[i])) return i;
        }
        return -1;
    }

    public static function buildSnapshot(view:String, trainer:Object):Object {
        var sync:Object = synchronize();
        if (!sync.success) return sync;
        var r:Object = root();
        var scan:Object = sync.scan;
        var learned:Array = [];
        for (var i:Number = 0; i < SKILL_ROW_COUNT; i++) {
            var info:Object = scan.rows[i];
            if (info == null || info.skillKey == null || scan.firstIndex[skillMapKey(info.skillKey)] != i) continue;
            learned.push(projectLearned(info, scan));
        }
        var loadout:Array = [];
        for (var slot:Number = 1; slot <= QUICK_SLOT_COUNT; slot++) loadout.push(projectLoadoutWire(descriptorFromScan(slot, scan)));
        var diagnostics:Array = scan.diagnostics.concat();
        for (var rd:Number = 0; rd < _rendererDiagnostics.length; rd++) addDiagnostic(diagnostics, _rendererDiagnostics[rd]);
        var trainerWire:Object = null;
        if (trainer != null) {
            trainerWire = {session:trainer.session, entries:trainer.entries};
            if (trainer.diagnostics instanceof Array) {
                for (var td:Number = 0; td < trainer.diagnostics.length; td++) addDiagnostic(diagnostics, trainer.diagnostics[td]);
            }
        }
        return {
            success:true,
            v:1,
            revision:_revision,
            view:view == "trainer" ? "trainer" : "manage",
            player:{level:clampWhole(r.等级, 0, 9999), skillPoints:clampWhole(r.技能点数, 0, 2147483647), easyMode:isEasyMode()},
            learned:learned,
            loadout:loadout,
            trainer:trainerWire,
            diagnostics:diagnostics
        };
    }

    public static function getSlotDescriptor(slot:Number):Object {
        if (!validSlot(slot)) return {slot:slot, equipped:false, skillKey:null, stateHealth:"invalid", writeBlocked:true};
        var sync:Object = synchronize();
        if (!sync.success) return {slot:slot, equipped:false, skillKey:null, stateHealth:"not_ready", writeBlocked:true};
        return descriptorFromScan(slot, sync.scan);
    }

    public static function isReleaseAllowed(skillKey:String):Boolean {
        var sync:Object = synchronize();
        if (!sync.success) return false;
        var state:Object = inspectFromScan(sync.scan, skillKey);
        return state.success && state.learned && state.stateHealth == "ok" && !state.writeBlocked
            && state.metadata != null && state.metadata.Equippable === true && !isPurePassive(state.metadata);
    }

    public static function equip(skillKey:String, slot:Number, expectedRevision:Number):Object {
        var gate:Object = writeGate(expectedRevision);
        if (!gate.success) return gate;
        if (!validSlot(slot) || !safeSkillKey(skillKey)) return fail("invalid_payload");
        var scan:Object = gate.scan;
        if (scan.tailData) return fail("corrupt_skill_state");
        var state:Object = inspectFromScan(scan, skillKey);
        if (!state.success || !state.learned || state.stateHealth != "ok") return fail("corrupt_skill_state");
        if (state.metadata.Equippable !== true || isPurePassive(state.metadata)) return fail("not_equippable");

        var current:String = normalizeSlotName(root()["快捷技能栏" + slot]);
        if (current == skillKey) return writeNoop("manage", null);
        if (current != null) {
            var occupant:Object = inspectSlotOccupant(scan, current);
            if (!occupant.learned || occupant.metadata == null || occupant.stateHealth != "ok"
                || occupant.metadata.Equippable !== true || isPurePassive(occupant.metadata)) return fail("corrupt_skill_state");
        }
        if (!isEasyMode()) {
            for (var i:Number = 1; i <= QUICK_SLOT_COUNT; i++) {
                if (i != slot && normalizeSlotName(root()["快捷技能栏" + i]) == skillKey) return fail("already_equipped");
            }
        }

        var before:Object = captureTransactionState();
        root()["快捷技能栏" + slot] = skillKey;
        return finishMutation([skillKey, current], before);
    }

    public static function unequip(slot:Number, expectedRevision:Number):Object {
        var gate:Object = writeGate(expectedRevision);
        if (!gate.success) return gate;
        if (!validSlot(slot)) return fail("invalid_payload");
        if (gate.scan.tailData) return fail("corrupt_skill_state");
        var current:String = normalizeSlotName(root()["快捷技能栏" + slot]);
        if (current == null) return writeNoop("manage", null);
        var occupant:Object = inspectSlotOccupant(gate.scan, current);
        if (occupant.learned && occupant.stateHealth != "ok") return fail("corrupt_skill_state");

        var before:Object = captureTransactionState();
        root()["快捷技能栏" + slot] = "";
        return finishMutation([current], before);
    }

    /**
     * 在两个物理快捷槽之间原子移动或交换。
     *
     * 目标为空时移动并清空源槽；目标已占用时交换。不能用两次
     * equip/unequip 拼接，否则普通模式的 already_equipped 门和中途断线
     * 都可能留下半完成状态。
     */
    public static function moveSlot(sourceSlot:Number, targetSlot:Number, expectedRevision:Number):Object {
        var gate:Object = writeGate(expectedRevision);
        if (!gate.success) return gate;
        if (!validSlot(sourceSlot) || !validSlot(targetSlot)) return fail("invalid_payload");
        if (gate.scan.tailData) return fail("corrupt_skill_state");
        if (sourceSlot == targetSlot) return writeNoop("manage", null);

        var sourceKey:String = normalizeSlotName(root()["快捷技能栏" + sourceSlot]);
        if (sourceKey == null) return fail("slot_empty");
        var source:Object = inspectSlotOccupant(gate.scan, sourceKey);
        if (!source.learned || source.metadata == null || source.stateHealth != "ok"
            || source.metadata.Equippable !== true || isPurePassive(source.metadata)) return fail("corrupt_skill_state");

        var targetKey:String = normalizeSlotName(root()["快捷技能栏" + targetSlot]);
        if (targetKey == sourceKey) return writeNoop("manage", null);
        if (targetKey != null) {
            var target:Object = inspectSlotOccupant(gate.scan, targetKey);
            if (!target.learned || target.metadata == null || target.stateHealth != "ok"
                || target.metadata.Equippable !== true || isPurePassive(target.metadata)) return fail("corrupt_skill_state");
        }

        var before:Object = captureTransactionState();
        root()["快捷技能栏" + sourceSlot] = targetKey == null ? "" : targetKey;
        root()["快捷技能栏" + targetSlot] = sourceKey;
        return finishMutation([sourceKey, targetKey], before);
    }

    public static function setPassive(skillKey:String, enabled:Boolean, expectedRevision:Number):Object {
        var gate:Object = writeGate(expectedRevision);
        if (!gate.success) return gate;
        if (!safeSkillKey(skillKey) || typeof enabled != "boolean") return fail("invalid_payload");
        if (gate.scan.tailData) return fail("corrupt_skill_state");
        var state:Object = inspectFromScan(gate.scan, skillKey);
        if (!state.success || !state.learned || state.stateHealth != "ok") return fail("corrupt_skill_state");
        if (!isPurePassive(state.metadata) || !isPassive(state.metadata)) return fail("not_passive");
        var parsed:Object = parseLegacyBoolean(state.row[4]);
        if (!parsed.known) return fail("corrupt_skill_state");
        if (parsed.value == enabled) return writeNoop("manage", null);

        var before:Object = captureTransactionState();
        state.row[4] = enabled;
        if (String(state.row[3]) != String(state.metadata.Type)) state.row[3] = state.metadata.Type;
        return finishMutation([skillKey], before);
    }

    public static function reorder(skillKey:String, targetIndex:Number, expectedRevision:Number):Object {
        var gate:Object = writeGate(expectedRevision);
        if (!gate.success) return gate;
        if (!safeSkillKey(skillKey) || !wholeInRange(targetIndex, 0, SKILL_ROW_COUNT - 1)) return fail("invalid_payload");
        if (gate.scan.tailData) return fail("corrupt_skill_state");
        var state:Object = inspectFromScan(gate.scan, skillKey);
        if (!state.success || !state.learned || state.stateHealth != "ok") return fail("corrupt_skill_state");
        if (state.index == targetIndex) return writeNoop("manage", null);
        if (targetIndex >= root().主角技能表.length || !root().主角技能表.hasOwnProperty(String(targetIndex))) return fail("corrupt_skill_state");
        var target:Object = gate.scan.rows[targetIndex];
        if (target == null || target.stateHealth != "ok") return fail("corrupt_skill_state");
        if (target.skillKey == null && !isEmptyRow(target.row)) return fail("corrupt_skill_state");
        if (target.skillKey != null && gate.scan.duplicateKeys[skillMapKey(target.skillKey)] === true) return fail("corrupt_skill_state");
        if (target.skillKey != null && equippedSlots(target.skillKey).length > 0) return fail("equipped_skill_locked");
        if (!isEasyMode() && equippedSlots(skillKey).length > 0) return fail("equipped_skill_locked");

        var before:Object = captureTransactionState();
        var table:Array = root().主角技能表;
        var oldSource = table[state.index];
        var oldTarget = table[targetIndex];
        table[state.index] = oldTarget;
        table[targetIndex] = oldSource;
        return finishMutation([skillKey, target.skillKey], before);
    }

    public static function commitLearn(skillKey:String, desiredLevel:Number, cost:Number, expectedRevision:Number):Object {
        var gate:Object = writeGate(expectedRevision);
        if (!gate.success) return gate;
        if (!safeSkillKey(skillKey) || !wholeInRange(desiredLevel, 1, 100) || !wholeInRange(cost, 0, 2147483647)) return fail("invalid_payload");
        if (gate.scan.tailData) return fail("corrupt_skill_state");
        var state:Object = inspectFromScan(gate.scan, skillKey);
        if (state.success && state.stateHealth != "ok") return fail("corrupt_skill_state");
        var metadata:Object = root().技能表对象[skillKey];
        if (metadata == null) return fail("unknown_skill");
        if (!validLearnMetadata(metadata)) return fail("corrupt_skill_state");
        var maxLevel:Number = metadataMaxLevel(metadata);
        if (desiredLevel > maxLevel) return fail("invalid_level");
        var currentLevel:Number = state.learned ? state.level : 0;
        if (currentLevel == 0 && desiredLevel != 1) return fail("initial_level_must_be_one");
        if (currentLevel > 0 && desiredLevel <= currentLevel) return fail("invalid_level");
        var expectedCost:Number;
        if (currentLevel == 0) {
            expectedCost = Number(metadata.UnlockSP);
        } else {
            var delta:Number = desiredLevel - currentLevel;
            if (Number(metadata.UpgradeSP) > Math.floor(2147483647 / delta)) return fail("invalid_level");
            expectedCost = delta * Number(metadata.UpgradeSP);
        }
        if (cost != expectedCost) return fail("stale_state");
        if (safeWhole(root().技能点数, -1) < cost) return fail("insufficient_sp");

        var table:Array = root().主角技能表;
        var targetIndex:Number = state.learned ? state.index : findLearnTargetIndex();
        if (targetIndex < 0) return fail("skill_table_full");
        var before:Object = captureTransactionState();
        if (!state.learned) {
                var purePassive:Boolean = isPurePassive(metadata);
                table[targetIndex] = [skillKey, 1, purePassive, metadata.Type, purePassive];
        } else {
            table[targetIndex][1] = desiredLevel;
            if (String(table[targetIndex][3]) != String(metadata.Type)) table[targetIndex][3] = metadata.Type;
        }
        root().技能点数 = safeWhole(root().技能点数, 0) - cost;
        return finishMutation([skillKey], before);
    }

    private static function writeGate(expectedRevision:Number):Object {
        var sync:Object = synchronize();
        if (!sync.success) return sync;
        if (!wholeInRange(expectedRevision, 0, 2147483647)) return fail("invalid_payload");
        if (expectedRevision != _revision) return fail("stale_state");
        return {success:true, scan:sync.scan, revision:_revision};
    }

    private static function finishMutation(affectedKeys:Array, before:Object):Object {
        deriveFlagsForKeys(affectedKeys);
        if (!rebuildDomainState()) {
            restoreTransactionState(before);
            return fail("commit_failed");
        }
        var newScan:Object = scanState();
        _signature = newScan.signature;
        _lastScan = newScan;
        _revision++;
        markDirty();
        var snapshot:Object = buildSnapshot("manage", null);
        return {success:true, v:1, changed:true, revision:_revision, snapshot:snapshot};
    }

    private static function writeNoop(view:String, trainer:Object):Object {
        return {success:true, v:1, changed:false, revision:_revision, snapshot:buildSnapshot(view, trainer)};
    }

    private static function scanState():Object {
        var r:Object = root();
        var table:Array = r.主角技能表;
        var rows:Array = [];
        var physicalRows:Object = {};
        var firstIndex:Object = {};
        var duplicateKeys:Object = {};
        var diagnostics:Array = [];
        var parts:Array = ["len", table.length];
        var i:Number;
        for (i = 0; i < SKILL_ROW_COUNT; i++) {
            if (i >= table.length || !table.hasOwnProperty(String(i))) {
                rows[i] = null;
                parts.push("h", i);
                continue;
            }
            var row = table[i];
            if (!(row instanceof Array) || row.length < 5) {
                rows[i] = {index:i, row:row, skillKey:null, stateHealth:"invalid", writeBlocked:true};
                addDiagnostic(diagnostics, {code:"invalid_skill_row", index:i});
                parts.push("bad", i, typeToken(row));
                continue;
            }
            var rawName = row[0];
            var key:String = normalizeRowName(rawName);
            var metadata:Object = key == null ? null : r.技能表对象[key];
            var health:String = "ok";
            if (key != null && !safeSkillKey(key)) {
                health = "invalid";
                addDiagnostic(diagnostics, {code:"invalid_skill_row", index:i});
            }
            if (key != null && metadata == null) {
                health = "invalid";
                addDiagnostic(diagnostics, {code:"unknown_skill", skillKey:wireKey(String(key), "无效技能行-" + i, 64)});
            } else if (key != null && !validLearnMetadata(metadata)) {
                health = "invalid";
                addDiagnostic(diagnostics, {code:"metadata_mismatch", skillKey:wireKey(String(key), "无效技能行-" + i, 64)});
            }
            var level:Number = Number(row[1]);
            if (key != null && (!wholeInRange(level, 1, metadata == null ? 100 : metadataMaxLevel(metadata)))) {
                health = "invalid";
                addDiagnostic(diagnostics, {code:"invalid_skill_row", index:i, skillKey:wireKey(String(key), "无效技能行-" + i, 64)});
            }
            var pure:Boolean = metadata != null && isPurePassive(metadata);
            var equippedFlag:Object = pure ? {known:true, value:false} : parseLegacyBoolean(row[2]);
            var enabledFlag:Object = parseLegacyBoolean(row[4]);
            if (key != null && (!equippedFlag.known || !enabledFlag.known)) {
                health = "invalid";
                addDiagnostic(diagnostics, {code:"invalid_boolean", index:i, skillKey:wireKey(String(key), "无效技能行-" + i, 64)});
            }
            if (key != null && metadata != null && String(row[3]) != String(metadata.Type)) {
                addDiagnostic(diagnostics, {code:"metadata_mismatch", skillKey:wireKey(String(key), "无效技能行-" + i, 64)});
            }
            var info:Object = {index:i, row:row, skillKey:key, metadata:metadata, level:level,
                enabled:enabledFlag.value, stateHealth:health, writeBlocked:health != "ok"};
            rows[i] = info;
            if (key != null) {
                var mapKey:String = skillMapKey(key);
                if (physicalRows[mapKey] == undefined) physicalRows[mapKey] = [];
                physicalRows[mapKey].push(i);
                if (firstIndex[mapKey] == undefined) firstIndex[mapKey] = i;
            }
            parts.push("r", i, valueToken(rawName), valueToken(row[1]), pure ? "passive-shadow" : valueToken(row[2]), valueToken(row[4]), typeToken(row[3]));
        }
        for (var k:String in physicalRows) {
            if (physicalRows[k].length > 1) {
                duplicateKeys[k] = true;
                var indices:Array = physicalRows[k];
                var duplicateSkillKey:String = rows[indices[0]].skillKey;
                for (var di:Number = 0; di < indices.length; di++) {
                    rows[indices[di]].stateHealth = "duplicate";
                    rows[indices[di]].writeBlocked = true;
                }
                addDiagnostic(diagnostics, {code:"duplicate_skill_rows", skillKey:wireKey(duplicateSkillKey, "无效重复技能-" + firstIndex[k], 64), rowCount:physicalRows[k].length});
            }
        }
        var tailData:Boolean = false;
        for (i = SKILL_ROW_COUNT; i < table.length; i++) {
            if (table.hasOwnProperty(String(i)) && !isEmptyRow(table[i])) {
                tailData = true;
                parts.push("tail", i, valueToken(table[i]));
            }
        }
        if (tailData) addDiagnostic(diagnostics, {code:"tail_data"});
        for (i = 1; i <= QUICK_SLOT_COUNT; i++) parts.push("s", i, valueToken(r["快捷技能栏" + i]));
        return {rows:rows, physicalRows:physicalRows, firstIndex:firstIndex, duplicateKeys:duplicateKeys,
            diagnostics:diagnostics, tailData:tailData, signature:parts.join("|")};
    }

    private static function inspectFromScan(scan:Object, skillKey:String):Object {
        if (!safeSkillKey(skillKey)) return {success:false, learned:false, stateHealth:"invalid", writeBlocked:true};
        var indices:Array = scan.physicalRows[skillMapKey(skillKey)];
        if (indices == undefined || indices.length == 0) return {success:true, learned:false, skillKey:skillKey,
            metadata:root().技能表对象[skillKey], stateHealth:"ok", writeBlocked:false, level:0};
        var info:Object = scan.rows[indices[0]];
        return {success:true, learned:true, skillKey:skillKey, index:info.index, row:info.row,
            metadata:info.metadata, level:info.level, enabled:info.enabled,
            stateHealth:info.stateHealth, writeBlocked:info.writeBlocked};
    }

    private static function inspectSlotOccupant(scan:Object, skillKey:String):Object {
        for (var i:Number = 0; i < SKILL_ROW_COUNT; i++) {
            var info:Object = scan.rows[i];
            if (info != null && info.skillKey == skillKey) {
                return {success:true, learned:true, skillKey:skillKey, index:info.index, row:info.row,
                    metadata:info.metadata, level:info.level, enabled:info.enabled,
                    stateHealth:info.stateHealth, writeBlocked:info.writeBlocked};
            }
        }
        return {success:true, learned:false, skillKey:skillKey, metadata:root().技能表对象[skillKey],
            stateHealth:"unknown", writeBlocked:false, level:0};
    }

    private static function projectLearned(info:Object, scan:Object):Object {
        var m:Object = info.metadata;
        var slots:Array = isPurePassive(m) ? [] : equippedSlots(info.skillKey);
        var typeName:String = m == null ? String(info.row[3]) : String(m.Type);
        if (typeName == "" || typeName == "undefined" || typeName == "null") typeName = "未知";
        var projectedKey:String = wireKey(info.skillKey, "无效技能行-" + info.index, 64);
        return {
            skillKey:projectedKey, orderIndex:info.index, level:clampWhole(info.level, 0, 9999),
            maxLevel:metadataMaxLevel(m), type:sanitizePlain(typeName, 64, "未知"),
            passive:m != null && isPassive(m), equippable:m != null && m.Equippable === true,
            enabled:parseLegacyBoolean(info.row[4]).value, equippedSlots:slots,
            unlockLevel:boundedMetadataInteger(m, "UnlockLevel", 9999), unlockSP:boundedMetadataInteger(m, "UnlockSP", 2147483647),
            upgradeSP:boundedMetadataInteger(m, "UpgradeSP", 2147483647), mp:boundedMetadataNumber(m, "MP", 1000000),
            cooldownMs:boundedMetadataInteger(m, "CD", 86400000), iconKey:projectedKey,
            description:sanitizeLayout(m == null ? "" : String(m.Description), 4096),
            stateHealth:info.stateHealth, writeBlocked:info.writeBlocked
        };
    }

    private static function descriptorFromScan(slot:Number, scan:Object):Object {
        var r:Object = root();
        var key:String = normalizeSlotName(r["快捷技能栏" + slot]);
        var base:Object = {slot:slot, equipped:key != null, skillKey:key,
            keyLabel:keyLabel(slot), stateHealth:"ok", writeBlocked:false};
        if (key == null) return base;
        var state:Object = inspectSlotOccupant(scan, key);
        if (!state.learned) {
            base.level = null; base.iconKey = null; base.mp = null; base.cooldownMs = null;
            base.equipped = false; base.stateHealth = "unknown"; return base;
        }
        if (state.metadata == null || state.stateHealth != "ok") {
            base.level = clampWhole(state.level, 0, 9999);
            base.iconKey = wireKey(key, "无效技能槽-" + slot, 128);
            base.mp = state.metadata == null ? null : boundedMetadataNumber(state.metadata, "MP", 1000000);
            base.cooldownMs = state.metadata == null ? null : boundedMetadataInteger(state.metadata, "CD", 86400000);
            base.equipped = false; base.stateHealth = state.stateHealth == "duplicate" ? "duplicate" : "invalid";
            base.writeBlocked = true; return base;
        }
        if (state.metadata.Equippable !== true || isPurePassive(state.metadata)) {
            base.level = state.level; base.iconKey = wireKey(key, "无效技能槽-" + slot, 128);
            base.mp = null; base.cooldownMs = null; base.equipped = false;
            base.stateHealth = "invalid"; base.writeBlocked = false; return base;
        }
        base.level = state.level; base.iconKey = clip(key, 128);
        base.mp = boundedMetadataNumber(state.metadata, "MP", 1000000); base.cooldownMs = boundedMetadataInteger(state.metadata, "CD", 86400000);
        return base;
    }

    private static function projectLoadoutWire(descriptor:Object):Object {
        var projectedKey:String = descriptor.skillKey == null ? null : wireKey(descriptor.skillKey, "无效技能槽-" + descriptor.slot, 64);
        var wire:Object = {slot:descriptor.slot, skillKey:projectedKey, keyLabel:sanitizePlain(String(descriptor.keyLabel), 32, ""),
            stateHealth:descriptor.stateHealth, writeBlocked:descriptor.writeBlocked};
        if (descriptor.skillKey != null) {
            wire.level = descriptor.level == undefined || descriptor.level == null ? null : clampWhole(descriptor.level, 0, 9999);
            wire.iconKey = descriptor.iconKey == undefined || descriptor.iconKey == null ? null : projectedKey;
        }
        return wire;
    }

    private static function deriveFlagsForKeys(affectedKeys:Array):Void {
        var scan:Object = scanState();
        var seen:Object = {};
        for (var i:Number = 0; i < affectedKeys.length; i++) {
            var key:String = affectedKeys[i];
            var mapKey:String = skillMapKey(key);
            if (!safeSkillKey(key) || seen[mapKey] === true) continue;
            seen[mapKey] = true;
            var info:Object = inspectFromScan(scan, key);
            if (!info.success || !info.learned || info.metadata == null || info.stateHealth != "ok") continue;
            var slots:Array = equippedSlots(key);
            if (!isPurePassive(info.metadata)) {
                info.row[2] = slots.length > 0;
                info.row[4] = slots.length > 0;
            }
            if (String(info.row[3]) != String(info.metadata.Type)) info.row[3] = info.metadata.Type;
        }
    }

    private static function captureTransactionState():Object {
        var r:Object = root();
        var table:Array = r.主角技能表;
        var rows:Array = [];
        for (var i:Number = 0; i < SKILL_ROW_COUNT; i++) {
            if (i >= table.length || !table.hasOwnProperty(String(i))) { rows[i] = {exists:false}; continue; }
            var ref = table[i];
            var rowState:Object = {exists:true, ref:ref};
            if (ref instanceof Array) {
                var values:Array = [];
                var present:Array = [];
                for (var j:Number = 0; j < ref.length; j++) {
                    present[j] = ref.hasOwnProperty(String(j));
                    if (present[j]) values[j] = ref[j];
                }
                rowState.length = ref.length;
                rowState.values = values;
                rowState.present = present;
            }
            rows[i] = rowState;
        }
        var slots:Array = [];
        for (i = 1; i <= QUICK_SLOT_COUNT; i++) {
            var slotKey:String = "快捷技能栏" + i;
            slots[i] = {exists:r.hasOwnProperty(slotKey), value:r[slotKey]};
        }
        var dirtyExists:Boolean = r.存档系统 != null && r.存档系统.hasOwnProperty("dirtyMark");
        var originalValues:Object = captureOriginalValues(r);
        var dynamicMetadata:Array = captureDynamicMetadata(r);
        return {table:table, tableLength:table.length, rows:rows, slots:slots,
            skillPointsExists:r.hasOwnProperty("技能点数"), skillPoints:r.技能点数,
            passiveExists:r.hasOwnProperty("主角被动技能"), passiveCache:r.主角被动技能,
            dirtyExists:dirtyExists, dirty:r.存档系统 == null ? undefined : r.存档系统.dirtyMark,
            originalValues:originalValues, dynamicMetadata:dynamicMetadata,
            signature:_signature, lastScan:_lastScan, revision:_revision};
    }

    private static function restoreTransactionState(before:Object):Void {
        var r:Object = root();
        var table:Array = before.table;
        for (var i:Number = 0; i < SKILL_ROW_COUNT; i++) delete table[i];
        table.length = before.tableLength;
        for (i = 0; i < SKILL_ROW_COUNT; i++) {
            var rowState:Object = before.rows[i];
            if (rowState == null || !rowState.exists) continue;
            var ref = rowState.ref;
            if (ref instanceof Array && rowState.values != undefined) {
                ref.length = 0;
                ref.length = rowState.length;
                for (var j:Number = 0; j < rowState.length; j++) if (rowState.present[j]) ref[j] = rowState.values[j];
            }
            table[i] = ref;
        }
        for (i = 1; i <= QUICK_SLOT_COUNT; i++) {
            var slotKey:String = "快捷技能栏" + i;
            delete r[slotKey];
            if (before.slots[i].exists) r[slotKey] = before.slots[i].value;
        }
        if (before.skillPointsExists) r.技能点数 = before.skillPoints; else delete r.技能点数;
        if (before.passiveExists) r.主角被动技能 = before.passiveCache; else delete r.主角被动技能;
        if (r.存档系统 != null) {
            if (before.dirtyExists) r.存档系统.dirtyMark = before.dirty; else delete r.存档系统.dirtyMark;
        }
        restoreOriginalValues(r, before.originalValues);
        restoreDynamicMetadata(before.dynamicMetadata);
        _signature = before.signature;
        _lastScan = before.lastScan;
        _revision = before.revision;
    }

    private static function captureOriginalValues(r:Object):Object {
        if (!r.hasOwnProperty("_技能原始数值")) return {exists:false};
        var ref = r._技能原始数值;
        var entries:Array = [];
        if (ref != null && typeof ref == "object") {
            for (var key:String in ref) {
                if (ref.hasOwnProperty != undefined && !ref.hasOwnProperty(key)) continue;
                var value = ref[key];
                var child:Object = null;
                if (value != null && typeof value == "object") {
                    child = {ref:value, entries:[]};
                    for (var childKey:String in value) {
                        if (value.hasOwnProperty != undefined && !value.hasOwnProperty(childKey)) continue;
                        child.entries.push({key:childKey, value:value[childKey]});
                    }
                }
                entries.push({key:key, value:value, child:child});
            }
        }
        return {exists:true, ref:ref, entries:entries};
    }

    private static function restoreOriginalValues(r:Object, state:Object):Void {
        delete r._技能原始数值;
        if (state == null || !state.exists) return;
        r._技能原始数值 = state.ref;
        var ref = state.ref;
        if (ref == null || typeof ref != "object") return;
        clearOwnProperties(ref);
        for (var i:Number = 0; i < state.entries.length; i++) {
            var entry:Object = state.entries[i];
            ref[entry.key] = entry.value;
            if (entry.child != null) {
                var child = entry.child.ref;
                clearOwnProperties(child);
                for (var j:Number = 0; j < entry.child.entries.length; j++) {
                    var childEntry:Object = entry.child.entries[j];
                    child[childEntry.key] = childEntry.value;
                }
            }
        }
    }

    private static function clearOwnProperties(value:Object):Void {
        var keys:Array = [];
        for (var key:String in value) if (value.hasOwnProperty == undefined || value.hasOwnProperty(key)) keys.push(key);
        for (var i:Number = 0; i < keys.length; i++) delete value[keys[i]];
    }

    private static function captureDynamicMetadata(r:Object):Array {
        var keys:Array = ["闪现", "一瞬千击", "移动射击"];
        var states:Array = [];
        for (var i:Number = 0; i < keys.length; i++) {
            var metadata:Object = r.技能表对象 == null ? null : r.技能表对象[keys[i]];
            states.push({metadata:metadata,
                cdExists:metadata != null && metadata.hasOwnProperty("CD"), cd:metadata == null ? undefined : metadata.CD,
                mpExists:metadata != null && metadata.hasOwnProperty("MP"), mp:metadata == null ? undefined : metadata.MP});
        }
        return states;
    }

    private static function restoreDynamicMetadata(states:Array):Void {
        if (states == null) return;
        for (var i:Number = 0; i < states.length; i++) {
            var state:Object = states[i];
            var metadata:Object = state.metadata;
            if (metadata == null) continue;
            if (state.cdExists) metadata.CD = state.cd; else delete metadata.CD;
            if (state.mpExists) metadata.MP = state.mp; else delete metadata.MP;
        }
    }

    private static function rebuildDomainState():Boolean {
        var r:Object = root();
        var cache:Object = {};
        var seen:Object = {};
        var table:Array = r.主角技能表;
        for (var i:Number = 0; i < Math.min(SKILL_ROW_COUNT, table.length); i++) {
            if (!table.hasOwnProperty(String(i)) || !(table[i] instanceof Array)) continue;
            var key:String = normalizeRowName(table[i][0]);
            if (key == null || seen[skillMapKey(key)] === true) continue;
            seen[skillMapKey(key)] = true;
            var m:Object = r.技能表对象[key];
            var level:Number = Number(table[i][1]);
            var enabled:Object = parseLegacyBoolean(table[i][4]);
            if (m != null && isPassive(m) && wholeInRange(level, 1, metadataMaxLevel(m)) && enabled.known) {
                cache[key] = {技能名:key, 等级:level, 启用:enabled.value};
            }
        }
        r.主角被动技能 = cache;
        return recalculateDynamicCooldownDomain();
    }

    /**
     * 确定性 CD/MP 领域重算：先完整预检与计算，后一次性写入，不调用外部 Function。
     * 生产路径只用 Boolean 显式失败；不使用 try/catch。
     */
    public static function recalculateDynamicCooldownDomain():Boolean {
        var r:Object = root();
        if (r == null || r.技能表对象 == null) return false;
        var originals = r._技能原始数值;
        if (originals != null && typeof originals != "object") return false;

        var burstLevel:Number = 0;
        var burst:Object = r.主角被动技能 == null ? null : r.主角被动技能["内力爆发"];
        if (burst != null && burst.启用 === true) {
            burstLevel = Number(burst.等级);
            if (!wholeInRange(burstLevel, 0, 10)) return false;
        }

        var moveLevel:Number = 0;
        var moveEnabled:Boolean = false;
        var move:Object = r.主角被动技能 == null ? null : r.主角被动技能["移动射击"];
        if (move != null && move.启用 === true) {
            moveLevel = Number(move.等级);
            if (!wholeInRange(moveLevel, 0, 10)) return false;
            moveEnabled = true;
        }

        var flashPlan:Object = buildCooldownPlan(r, originals, "闪现", burstLevel, "burst");
        var strikePlan:Object = buildCooldownPlan(r, originals, "一瞬千击", burstLevel, "burst");
        var movePlan:Object = buildCooldownPlan(r, originals, "移动射击", moveEnabled ? moveLevel : 0, "move");
        if (!flashPlan.success || !strikePlan.success || !movePlan.success) return false;

        if (originals == null) { originals = {}; r._技能原始数值 = originals; }
        applyCooldownPlan(originals, flashPlan);
        // 故障注入点故意位于主写/cache 重建与第一个 CD/MP 投影之后。
        if (rejectCommitForTest()) return false;
        applyCooldownPlan(originals, strikePlan);
        applyCooldownPlan(originals, movePlan);
        return true;
    }

    private static function buildCooldownPlan(r:Object, originals:Object, skillKey:String, effectLevel:Number, mode:String):Object {
        var metadata:Object = r.技能表对象[skillKey];
        if (metadata == null) return {success:true, present:false};
        if (!domainNumber(metadata.CD, 86400000, true) || !domainNumber(metadata.MP, 1000000, false)) return {success:false};

        var originalExists:Boolean = false;
        if (originals != null) {
            originalExists = originals.hasOwnProperty == undefined
                ? originals[skillKey] != undefined : originals.hasOwnProperty(skillKey);
        }
        var original:Object = originalExists ? originals[skillKey] : null;
        if (originalExists && (original == null || typeof original != "object")) return {success:false};
        var baseCD:Number = originalExists ? Number(original.CD) : Number(metadata.CD);
        var baseMP:Number = originalExists ? Number(original.MP) : Number(metadata.MP);
        if (originalExists && (!domainNumber(baseCD, 86400000, true)
            || !domainNumber(baseMP, 1000000, false))) return {success:false};

        var nextCD:Number = Number(metadata.CD);
        var nextMP:Number = Number(metadata.MP);
        var createOriginal:Boolean = false;
        var writeCD:Boolean = false;
        var writeMP:Boolean = false;
        if (mode == "burst") {
            if (effectLevel > 0) {
                createOriginal = !originalExists;
                writeCD = writeMP = true;
                var reduction:Number = (effectLevel / 10) * 0.5;
                nextCD = Math.round(baseCD * (1 - reduction));
                nextMP = baseMP + 2 * effectLevel;
            } else if (originalExists) {
                writeCD = writeMP = true;
                nextCD = baseCD;
                nextMP = baseMP;
            }
        } else if (mode == "move") {
            // 保留旧语义：元数据存在即记录原值；仅移动射击自身启用且满级时将 CD 设为 1s。
            createOriginal = !originalExists;
            if (effectLevel >= 10) {
                writeCD = true;
                nextCD = 1000;
            }
        } else {
            return {success:false};
        }
        if ((writeCD && !domainNumber(nextCD, 86400000, true)) || (writeMP && !domainNumber(nextMP, 1000000, false))) return {success:false};
        return {success:true, present:true, skillKey:skillKey, metadata:metadata, createOriginal:createOriginal,
            baseCD:baseCD, baseMP:baseMP, writeCD:writeCD, writeMP:writeMP, nextCD:nextCD, nextMP:nextMP};
    }

    private static function applyCooldownPlan(originals:Object, plan:Object):Void {
        if (!plan.present) return;
        if (plan.createOriginal) originals[plan.skillKey] = {CD:plan.baseCD, MP:plan.baseMP};
        if (plan.writeCD) plan.metadata.CD = plan.nextCD;
        if (plan.writeMP) plan.metadata.MP = plan.nextMP;
    }

    private static function domainNumber(value, max:Number, integer:Boolean):Boolean {
        var n:Number = Number(value);
        return !isNaN(n) && isFinite(n) && n >= 0 && n <= max && (!integer || Math.floor(n) == n);
    }

    public static function runOptionalRenderers():Void {
        var r:Object = root();
        _rendererDiagnostics = [];
        runRenderer(r, "技能系统投影Hero", "hero");
        runRenderer(r, "技能系统投影快捷栏", "quick_slot");
        runRenderer(r, "技能系统投影旧列表", "legacy_list");
    }

    /**
     * 把领域快捷栏状态投影到观察期旧 HUD。
     *
     * 旧槽位的图标壳只在进入“默认图标”帧时 attachMovie。只更新
     * 已装备名/数量会留下上一枚图标，所以替换时必须先回空帧再进图标帧。
     * 这里只重建显示对象，不修改 root 槽位、技能行或手动冷却。
     */
    public static function projectQuickSlotRenderer(playerInterface:Object):Object {
        var quickInterface:Object = playerInterface == null ? null : playerInterface.快捷技能界面;
        if (quickInterface == null) return {success:true, v:1, rendered:false, renderedSlots:0};
        var sync:Object = synchronize();
        if (!sync.success) return sync;

        var renderedSlots:Number = 0;
        for (var slot:Number = 1; slot <= QUICK_SLOT_COUNT; slot++) {
            var slotClip:Object = quickInterface["快捷技能栏" + slot];
            if (slotClip == null) continue;
            if (typeof slotClip.gotoAndStop != "function") {
                return {success:false, v:1, error:"invalid_quick_slot_renderer", slot:slot};
            }

            var descriptor:Object = descriptorFromScan(slot, sync.scan);
            slotClip.装备槽类别 = "快捷技能栏" + slot;
            slotClip.对应装备 = "快捷技能栏" + slot;
            if (!descriptor.equipped) {
                slotClip.是否装备 = 0;
                slotClip.已装备名 = "";
                slotClip.对应数组号 = -1;
                slotClip.数量 = 0;
                slotClip.冷却时间 = 0;
                slotClip.消耗mp = 0;
                slotClip.图标 = "";
                slotClip.gotoAndStop("空");
                renderedSlots++;
                continue;
            }

            var occupant:Object = inspectSlotOccupant(sync.scan, descriptor.skillKey);
            slotClip.是否装备 = 1;
            slotClip.已装备名 = descriptor.skillKey;
            slotClip.对应数组号 = occupant.index;
            slotClip.数量 = descriptor.level;
            slotClip.冷却时间 = descriptor.cooldownMs;
            slotClip.消耗mp = descriptor.mp;
            slotClip.图标 = "图标-" + descriptor.skillKey;
            slotClip.gotoAndStop("空");
            slotClip.gotoAndStop("默认图标");
            renderedSlots++;
        }
        return {success:true, v:1, rendered:renderedSlots > 0, renderedSlots:renderedSlots};
    }

    private static function runRenderer(r:Object, functionName:String, label:String):Void {
        // 缺函数或 false 是 HUD / hero / 旧界面未就绪的正常 skip，不是领域失败。
        if (typeof r[functionName] != "function") return;
        var result = r[functionName]();
        if (result != null && typeof result == "object" && result.success === false) {
            recordRendererFailure(label + ":" + sanitizePlain(String(result.error), 128, "failed"));
        }
    }

    private static function recordRendererFailure(message:String):Void {
        addDiagnostic(_rendererDiagnostics, {code:"renderer_failed", message:sanitizeLayout(message, 512)});
        logDiagnostic("renderer_failed", message);
    }

    private static function markDirty():Void {
        var r:Object = root();
        if (r.存档系统 != null) {
            r.存档系统.dirtyMark = true;
            if (typeof r.存档系统.markDirty == "function") r.存档系统.markDirty();
        }
    }

    private static function equippedSlots(skillKey:String):Array {
        var result:Array = [];
        var r:Object = root();
        for (var i:Number = 1; i <= QUICK_SLOT_COUNT; i++) if (normalizeSlotName(r["快捷技能栏" + i]) == skillKey) result.push(i);
        return result;
    }

    private static function isEasyMode():Boolean {
        var r:Object = root();
        if (typeof r.isEasyMode == "function") return r.isEasyMode() === true;
        return r.难度模式 == "简单" || r.难度等级 == 0;
    }

    private static function keyLabel(slot:Number):String {
        var r:Object = root();
        var code = r["快捷技能栏键" + slot];
        if (typeof r.keyshow == "function" && isFiniteNumber(code)) return clip(String(r.keyshow(Number(code))), 32);
        return code == undefined ? "" : clip(String(code), 32);
    }

    private static function isPurePassive(metadata:Object):Boolean {
        return metadata != null && (String(metadata.Type) == "被动" || metadata.Equippable === false);
    }

    private static function isPassive(metadata:Object):Boolean {
        if (metadata == null) return false;
        return metadata.Passive === true || String(metadata.Type).indexOf("被动") >= 0;
    }

    private static function metadataMaxLevel(metadata:Object):Number {
        var n:Number = metadataNumber(metadata, "MaxLevel");
        return wholeInRange(n, 1, 100) ? n : 1;
    }

    private static function validLearnMetadata(metadata:Object):Boolean {
        return metadata != null
            && wholeInRange(Number(metadata.MaxLevel), 1, 100)
            && wholeInRange(Number(metadata.UnlockLevel), 0, 9999)
            && wholeInRange(Number(metadata.UnlockSP), 0, 2147483647)
            && wholeInRange(Number(metadata.UpgradeSP), 0, 2147483647)
            && typeof metadata.Type == "string" && String(metadata.Type).length > 0 && String(metadata.Type).length <= 64
            && isSafePlain(String(metadata.Type)) && typeof metadata.Passive == "boolean" && typeof metadata.Equippable == "boolean"
            && isFiniteNumber(metadata.MP) && Number(metadata.MP) >= 0 && Number(metadata.MP) <= 1000000
            && wholeInRange(Number(metadata.CD), 0, 86400000);
    }

    private static function metadataNumber(metadata:Object, key:String):Number {
        if (metadata == null) return 0;
        var n:Number = Number(metadata[key]);
        return isNaN(n) || !isFinite(n) ? 0 : n;
    }

    private static function boundedMetadataNumber(metadata:Object, key:String, max:Number):Number {
        var n:Number = metadataNumber(metadata, key);
        if (n < 0) return 0;
        return n > max ? max : n;
    }
    private static function boundedMetadataInteger(metadata:Object, key:String, max:Number):Number {
        return Math.floor(boundedMetadataNumber(metadata, key, max));
    }

    private static function parseLegacyBoolean(value):Object {
        if (typeof value == "boolean") return {known:true, value:value};
        if (typeof value == "number" && (value === 0 || value === 1)) return {known:true, value:value === 1};
        if (typeof value == "string") {
            var s:String = String(value).toLowerCase();
            if (s == "true" || s == "1") return {known:true, value:true};
            if (s == "false" || s == "0") return {known:true, value:false};
        }
        return {known:false, value:false};
    }

    private static function isEmptyRow(row):Boolean {
        if (row == null) return true;
        if (!(row instanceof Array)) return false;
        return normalizeRowName(row[0]) == null && (row[1] == undefined || Number(row[1]) == 0);
    }

    private static function normalizeRowName(raw):String {
        if (raw == null || typeof raw != "string") return null;
        var s:String = String(raw);
        return s == "" ? null : s;
    }

    private static function normalizeSlotName(raw):String {
        if (raw == null) return null;
        var s:String = String(raw);
        return s == "" || s == "空" || s == "null" || s == "undefined" ? null : s;
    }

    private static function safeSkillKey(value):Boolean {
        if (typeof value != "string") return false;
        var s:String = String(value);
        return s.length > 0 && s.length <= 64 && isSafePlain(s) && !isBoundaryWhitespace(s.charCodeAt(0))
            && !isBoundaryWhitespace(s.charCodeAt(s.length - 1));
    }
    private static function skillMapKey(value):String { return "$" + String(value); }

    private static function validSlot(slot:Number):Boolean { return wholeInRange(slot, 1, QUICK_SLOT_COUNT); }
    private static function wholeInRange(value:Number, min:Number, max:Number):Boolean {
        return isFiniteNumber(value) && Math.floor(Number(value)) == Number(value) && Number(value) >= min && Number(value) <= max;
    }
    private static function isFiniteNumber(value):Boolean {
        var n:Number = Number(value);
        return !isNaN(n) && isFinite(n);
    }
    private static function safeWhole(value, fallback:Number):Number {
        var n:Number = Number(value);
        return isNaN(n) || !isFinite(n) ? fallback : Math.floor(n);
    }
    private static function clampWhole(value, min:Number, max:Number):Number {
        var n:Number = safeWhole(value, min);
        if (n < min) return min;
        return n > max ? max : n;
    }
    private static function clip(value:String, max:Number):String { return value.length <= max ? value : value.substr(0, max); }
    private static function wireKey(value:String, fallback:String, max:Number):String {
        if (value != null && value.length > 0 && value.length <= max && isSafePlain(value)
            && !isBoundaryWhitespace(value.charCodeAt(0)) && !isBoundaryWhitespace(value.charCodeAt(value.length - 1))) return value;
        return clip(fallback, max);
    }
    private static function sanitizePlain(value:String, max:Number, fallback:String):String {
        var out:String = "";
        for (var i:Number = 0; i < value.length && out.length < max; i++) {
            var c:Number = value.charCodeAt(i);
            if (c >= 32 && !(c >= 127 && c <= 159)) out += value.charAt(i);
        }
        return out.length == 0 ? fallback : out;
    }
    private static function sanitizeLayout(value:String, max:Number):String {
        var out:String = "";
        for (var i:Number = 0; i < value.length && out.length < max; i++) {
            var c:Number = value.charCodeAt(i);
            if ((c >= 32 && !(c >= 127 && c <= 159)) || c == 9 || c == 10 || c == 13) out += value.charAt(i);
        }
        return out;
    }
    private static function isSafePlain(value:String):Boolean {
        for (var i:Number = 0; i < value.length; i++) {
            var c:Number = value.charCodeAt(i);
            if (c < 32 || (c >= 127 && c <= 159)) return false;
        }
        return true;
    }
    private static function isBoundaryWhitespace(code:Number):Boolean {
        return code <= 32 || code == 160 || code == 5760 || (code >= 8192 && code <= 8202)
            || code == 8232 || code == 8233 || code == 8239 || code == 8287 || code == 12288;
    }
    private static function typeToken(value):String { return typeof value + ":" + valueToken(value); }
    private static function valueToken(value):String {
        if (value == null) return "null";
        var s:String = String(value);
        return typeof value + ":" + s.length + ":" + s;
    }
    private static function addDiagnostic(target:Array, item:Object):Void { if (target.length < 32) target.push(item); }
    private static function logDiagnostic(code:String, detail:String):Void {
        var r:Object = root();
        if (typeof r.发布调试消息 == "function") r.发布调试消息("[SkillLoadoutService] " + code + ":" + detail);
    }
    private static function fail(errorCode:String):Object { return {success:false, v:1, error:errorCode, revision:_revision}; }

    private static function rejectCommitForTest():Boolean {
        if (!_testRejectNextCommit) return false;
        _testRejectNextCommit = false;
        var r:Object = root();
        var firstRow = r.主角技能表 instanceof Array ? r.主角技能表[0] : null;
        var flash:Object = r.技能表对象 == null ? null : r.技能表对象["闪现"];
        _testRejectedState = {
            slot9:r["快捷技能栏9"],
            firstSkill:firstRow instanceof Array ? firstRow[0] : null,
            firstEquipped:firstRow instanceof Array ? firstRow[2] : null,
            skillPoints:r.技能点数,
            flashCD:flash == null ? null : flash.CD,
            flashMP:flash == null ? null : flash.MP
        };
        return true;
    }

    public static function testOnlyUseRoot(value:Object):Void { _testRoot = value; _signature = null; _lastScan = null; _revision = 0; _testRejectNextCommit = false; _testRejectedState = null; _rendererDiagnostics = []; }
    public static function testOnlyRejectNextCommit():Void { _testRejectNextCommit = true; }
    public static function testOnlyRejectedState():Object { return _testRejectedState; }
    public static function testOnlyReset():Void { _testRoot = null; _signature = null; _lastScan = null; _revision = 0; _testRejectNextCommit = false; _testRejectedState = null; _rendererDiagnostics = []; }
}
