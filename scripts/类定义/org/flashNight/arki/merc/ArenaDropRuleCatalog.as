/**
 * DEATH MATCH 标准佣兵掉落规则的严格解析与纯决策器。
 *
 * XML 只描述规则；本类负责把 XMLParser 的 singleton/array 形态归一化，
 * 同时从同一份 EligibleItem 生成 ItemObtainIndex 所需的静态来源记录。
 * resolveDrops() 不读 _root，便于 TestLoader 对概率分支做确定性验证。
 */
class org.flashNight.arki.merc.ArenaDropRuleCatalog {
    private static var MAX_PROFILES:Number = 8;
    private static var MAX_RULES:Number = 32;
    private static var MAX_ENTRIES:Number = 256;

    /** 将 XMLParser 输出严格归一化为运行时 catalog；任一非法字段都返回 null。 */
    public static function parse(raw:Object):Object {
        if (raw == null || typeof raw != "object"
                || !hasOnlyKeys(raw, {schemaVersion:true, Profile:true})
                || raw.schemaVersion !== 1) return null;

        var rawProfiles:Array = asArray(raw.Profile);
        if (rawProfiles.length < 1 || rawProfiles.length > MAX_PROFILES) return null;

        var result:Object = {
            schemaVersion:1,
            profiles:[],
            profilesById:{},
            sources:[]
        };
        var sourceKeys:Object = {};

        for (var p:Number = 0; p < rawProfiles.length; p++) {
            var rawProfile:Object = rawProfiles[p];
            if (rawProfile == null || typeof rawProfile != "object"
                    || !hasOnlyKeys(rawProfile,
                        {id:true, arenaId:true, arenaLabel:true,
                            modeLabel:true, Rule:true})
                    || !validText(rawProfile.id, 80)
                    || !validText(rawProfile.arenaId, 80)
                    || !validText(rawProfile.arenaLabel, 128)
                    || !validText(rawProfile.modeLabel, 128)
                    || result.profilesById[String(rawProfile.id)] != undefined) {
                return null;
            }

            var rawRules:Array = asArray(rawProfile.Rule);
            if (rawRules.length < 1 || rawRules.length > MAX_RULES) return null;

            var profile:Object = {
                id:String(rawProfile.id),
                arenaId:String(rawProfile.arenaId),
                arenaLabel:String(rawProfile.arenaLabel),
                modeLabel:String(rawProfile.modeLabel),
                rules:[]
            };
            var ruleIds:Object = {};

            for (var r:Number = 0; r < rawRules.length; r++) {
                var rule:Object = parseRule(rawRules[r], profile, result.sources,
                    sourceKeys, ruleIds);
                if (rule == null) return null;
                profile.rules.push(rule);
            }

            result.profiles.push(profile);
            result.profilesById[profile.id] = profile;
        }

        return result.sources.length > 0 ? result : null;
    }

    /**
     * 按 profile 对一个已初始化的人形单位生成旧掉落数组。
     * randomFn(totalWeight) 仅供测试注入；生产缺省使用 Math.random。
     */
    public static function resolveDrops(catalog:Object, profileId:String,
                                        unit:Object, randomFn:Function):Array {
        var drops:Array = [];
        if (catalog == null || unit == null || catalog.profilesById == null) {
            return drops;
        }
        var profile:Object = catalog.profilesById[profileId];
        if (profile == null || !(profile.rules instanceof Array)) return drops;

        for (var i:Number = 0; i < profile.rules.length; i++) {
            var rule:Object = profile.rules[i];
            if (!matchesAnyTrigger(rule.triggers, unit)) continue;

            var directDrops:Array = rule.directDrops;
            for (var d:Number = 0; d < directDrops.length; d++) {
                appendEligibleDrop(drops, unit, rule, directDrops[d]);
            }
            if (rule.slotLottery != null) {
                appendLotteryDrop(drops, unit, rule, rule.slotLottery, randomFn);
            }
            // 保留旧 if / else-if 的优先短路；匹配后即使装备不在白名单也必须停止。
            if (rule.stopOnMatch === true) break;
        }
        return drops;
    }

    private static function parseRule(rawRule:Object, profile:Object,
                                      sources:Array, sourceKeys:Object,
                                      ruleIds:Object):Object {
        if (rawRule == null || typeof rawRule != "object"
                || !hasOnlyKeys(rawRule,
                    {id:true, stopOnMatch:true, carrierScope:true,
                        Trigger:true, Drop:true,
                        SlotLottery:true, EligibleItem:true})
                || !validText(rawRule.id, 80)
                || typeof rawRule.stopOnMatch != "boolean"
                || !validCarrierScope(rawRule.carrierScope)
                || ruleIds[String(rawRule.id)] === true) return null;

        var rule:Object = {
            id:String(rawRule.id),
            stopOnMatch:rawRule.stopOnMatch,
            carrierScope:String(rawRule.carrierScope),
            triggers:[],
            directDrops:[],
            slotLottery:null,
            eligibleItems:[],
            eligibleBySlot:{}
        };
        ruleIds[rule.id] = true;

        var rawTriggers:Array = asArray(rawRule.Trigger);
        if (rawTriggers.length < 1 || rawTriggers.length > MAX_ENTRIES) return null;
        var triggerKeys:Object = {};
        for (var t:Number = 0; t < rawTriggers.length; t++) {
            var trigger:Object = rawTriggers[t];
            if (trigger == null || typeof trigger != "object"
                    || !hasOnlyKeys(trigger, {slot:true, item:true})
                    || !validSlot(trigger.slot) || !validText(trigger.item, 128)) {
                return null;
            }
            var triggerKey:String = String(trigger.slot) + "\n" + String(trigger.item);
            if (triggerKeys[triggerKey] === true) return null;
            triggerKeys[triggerKey] = true;
            rule.triggers.push({slot:String(trigger.slot), item:String(trigger.item)});
        }

        var actionBySlot:Object = {};
        var rawDrops:Array = asArray(rawRule.Drop);
        if (rawDrops.length > MAX_ENTRIES) return null;
        for (var d:Number = 0; d < rawDrops.length; d++) {
            var rawDrop:Object = rawDrops[d];
            if (rawDrop == null || typeof rawDrop != "object"
                    || !hasOnlyKeys(rawDrop, {slot:true, chancePercent:true})
                    || !validSlot(rawDrop.slot)
                    || !validPercent(rawDrop.chancePercent)
                    || actionBySlot[String(rawDrop.slot)] != undefined) return null;
            var direct:Object = {
                slot:String(rawDrop.slot),
                chancePercent:Number(rawDrop.chancePercent)
            };
            rule.directDrops.push(direct);
            actionBySlot[direct.slot] = {kind:"direct", action:direct};
        }

        var lotteries:Array = asArray(rawRule.SlotLottery);
        if (lotteries.length > 1) return null;
        if (lotteries.length == 1) {
            var rawLottery:Object = lotteries[0];
            if (rawLottery == null || typeof rawLottery != "object"
                    || !hasOnlyKeys(rawLottery,
                        {dropChancePercent:true, Choice:true})
                    || !validPercent(rawLottery.dropChancePercent)) return null;

            var rawChoices:Array = asArray(rawLottery.Choice);
            if (rawChoices.length < 1 || rawChoices.length > MAX_ENTRIES) return null;
            var lottery:Object = {
                dropChancePercent:Number(rawLottery.dropChancePercent),
                totalWeight:0,
                choices:[]
            };
            for (var c:Number = 0; c < rawChoices.length; c++) {
                var rawChoice:Object = rawChoices[c];
                if (rawChoice == null || typeof rawChoice != "object"
                        || !hasOnlyKeys(rawChoice, {slot:true, empty:true, weight:true})
                        || !validPositiveInteger(rawChoice.weight)) return null;
                var isEmpty:Boolean = rawChoice.empty === true;
                if (isEmpty) {
                    if (rawChoice.slot != undefined) return null;
                } else if (!validSlot(rawChoice.slot)
                        || actionBySlot[String(rawChoice.slot)] != undefined) {
                    return null;
                }
                var choice:Object = {
                    slot:isEmpty ? null : String(rawChoice.slot),
                    empty:isEmpty,
                    weight:Number(rawChoice.weight)
                };
                lottery.choices.push(choice);
                lottery.totalWeight += choice.weight;
                if (!isEmpty) {
                    actionBySlot[choice.slot] = {kind:"lottery", action:lottery,
                        choice:choice};
                }
            }
            if (!validPositiveInteger(lottery.totalWeight)) return null;
            rule.slotLottery = lottery;
        }

        if (rule.directDrops.length == 0 && rule.slotLottery == null) return null;

        var rawEligible:Array = asArray(rawRule.EligibleItem);
        if (rawEligible.length < 1 || rawEligible.length > MAX_ENTRIES) return null;
        var eligibleKeys:Object = {};
        var eligibleSlotCounts:Object = {};
        for (var e:Number = 0; e < rawEligible.length; e++) {
            var rawItem:Object = rawEligible[e];
            if (rawItem == null || typeof rawItem != "object"
                    || !hasOnlyKeys(rawItem, {name:true, slot:true})
                    || !validText(rawItem.name, 128) || !validSlot(rawItem.slot)) {
                return null;
            }
            var slot:String = String(rawItem.slot);
            var itemName:String = String(rawItem.name);
            var eligibleKey:String = slot + "\n" + itemName;
            var actionRef:Object = actionBySlot[slot];
            if (eligibleKeys[eligibleKey] === true || actionRef == null) return null;
            eligibleKeys[eligibleKey] = true;
            eligibleSlotCounts[slot] = Number(eligibleSlotCounts[slot] || 0) + 1;
            if (rule.eligibleBySlot[slot] == undefined) rule.eligibleBySlot[slot] = {};
            rule.eligibleBySlot[slot][itemName] = true;
            rule.eligibleItems.push({name:itemName, slot:slot});

            var chanceModel:String;
            var conditionalChance:Number;
            var selectionWeight = null;
            var totalWeight = null;
            var selectedDropChance = null;
            if (actionRef.kind == "direct") {
                chanceModel = "arena_equipped_drop";
                conditionalChance = Number(actionRef.action.chancePercent);
            } else {
                chanceModel = "arena_weighted_slot_then_drop";
                selectionWeight = Number(actionRef.choice.weight);
                totalWeight = Number(actionRef.action.totalWeight);
                selectedDropChance = Number(actionRef.action.dropChancePercent);
                conditionalChance = round6(selectionWeight / totalWeight
                    * selectedDropChance);
            }

            var sourceKey:String = profile.id + "\n" + rule.id + "\n"
                + slot + "\n" + itemName;
            if (sourceKeys[sourceKey] === true) return null;
            sourceKeys[sourceKey] = true;
            sources.push({
                itemName:itemName,
                arenaId:profile.arenaId,
                arenaLabel:profile.arenaLabel,
                profileId:profile.id,
                modeLabel:profile.modeLabel,
                ruleId:rule.id,
                carrierScope:rule.carrierScope,
                slot:slot,
                chanceModel:chanceModel,
                conditionalChancePercent:conditionalChance,
                selectionWeight:selectionWeight,
                totalWeight:totalWeight,
                selectedDropChancePercent:selectedDropChance
            });
        }

        // 每个可执行槽都必须由 EligibleItem 明确列举；禁止出现永远不可达的动作。
        for (var actionSlot:String in actionBySlot) {
            if (Number(eligibleSlotCounts[actionSlot] || 0) < 1) return null;
        }
        return rule;
    }

    private static function matchesAnyTrigger(triggers:Array, unit:Object):Boolean {
        for (var i:Number = 0; i < triggers.length; i++) {
            var trigger:Object = triggers[i];
            if (readExactEquippedName(unit, trigger.slot) === trigger.item) return true;
        }
        return false;
    }

    private static function appendEligibleDrop(output:Array, unit:Object,
                                               rule:Object, action:Object):Void {
        var itemName:String = readExactEquippedName(unit, action.slot);
        var eligible:Object = rule.eligibleBySlot[action.slot];
        if (eligible != null && eligible[itemName] === true) {
            output.push({名字:itemName, 概率:Number(action.chancePercent)});
        }
    }

    private static function appendLotteryDrop(output:Array, unit:Object,
                                              rule:Object, lottery:Object,
                                              randomFn:Function):Void {
        var total:Number = Number(lottery.totalWeight);
        var roll:Number = randomFn == null
            ? Math.floor(Math.random() * total)
            : Number(randomFn(total));
        if (isNaN(roll) || (roll - roll) != 0 || Math.floor(roll) != roll
                || roll < 0 || roll >= total) return;

        var cursor:Number = 0;
        for (var i:Number = 0; i < lottery.choices.length; i++) {
            var choice:Object = lottery.choices[i];
            cursor += Number(choice.weight);
            if (roll >= cursor) continue;
            if (choice.empty === true) return;
            appendEligibleDrop(output, unit, rule, {
                slot:choice.slot,
                chancePercent:lottery.dropChancePercent
            });
            return;
        }
    }

    private static function readExactEquippedName(unit:Object, slot:String):String {
        var value = unit[slot];
        return typeof value == "string" ? String(value) : "";
    }

    private static function asArray(value):Array {
        if (value instanceof Array) return value;
        if (value == undefined || value == null) return [];
        return [value];
    }

    private static function hasOnlyKeys(value:Object, allowed:Object):Boolean {
        if (value == null || typeof value != "object") return false;
        for (var key:String in value) {
            if (allowed[key] !== true) return false;
        }
        return true;
    }

    private static function validText(value, maxLength:Number):Boolean {
        return typeof value == "string" && value.length > 0
            && value.length <= maxLength && value != "undefined";
    }

    private static function validSlot(value):Boolean {
        if (typeof value != "string") return false;
        return value == "头部装备" || value == "上装装备"
            || value == "手部装备" || value == "下装装备"
            || value == "脚部装备" || value == "颈部装备"
            || value == "长枪" || value == "手枪"
            || value == "手枪2" || value == "刀";
    }

    private static function validCarrierScope(value):Boolean {
        return value == "carrier" || value == "specific_carrier";
    }

    private static function validPercent(value):Boolean {
        if (typeof value != "number") return false;
        var numberValue:Number = Number(value);
        return !isNaN(numberValue) && (numberValue - numberValue) == 0
            && numberValue >= 0 && numberValue <= 100;
    }

    private static function validPositiveInteger(value):Boolean {
        if (typeof value != "number") return false;
        var numberValue:Number = Number(value);
        return !isNaN(numberValue) && (numberValue - numberValue) == 0
            && numberValue > 0 && Math.floor(numberValue) == numberValue;
    }

    private static function round6(value:Number):Number {
        return Math.round(value * 1000000) / 1000000;
    }
}
