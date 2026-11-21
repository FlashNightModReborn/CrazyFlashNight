// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/UseSwitchStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace UseSwitchStatsBuilder {
        export function buildBaseSwitchDetailed(ctx: Context, result?: any[], stats?: any): void {
            if (!stats || !stats.baseSwitch || !stats.baseSwitch.valueCases)
                return;
            var valueCases: any[] = stats.baseSwitch.valueCases;
            if (as2Equal(valueCases.length, 0))
                return;
            var path: string = stats.baseSwitch.path || "data.damagetype";
            var pathLabel: string = (as2Equal(path, "data.damagetype")) ? "基础伤害类型" : path;
            result.push("<font color='" + TooltipConstants.COL_HL + "'>按基础属性分档</font><BR>");
            for (var i: number = 0; as2Less(i, valueCases.length); i++) {
                var valueCase: any = valueCases[i];
                if (!valueCase)
                    continue;
                var label: string = (valueCase._isDefault || !valueCase.name)
                    ? "其他情况"
                    : pathLabel + "为" + valueCase.name;
                result.push("<font color='" + TooltipConstants.COL_INFO + "'>[" + label + "]</font><BR>");
                buildStatBlock(ctx, result, valueCase, "  ");
            }
        }
        export function buildDetailed(ctx: Context, result?: any[], stats?: any): void {
            if (!stats || !stats.useSwitch || !stats.useSwitch.useCases) {
                return;
            }
            var useCases: any = stats.useSwitch.useCases;
            if (as2Equal(useCases.length, 0)) {
                return;
            }
            result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_USE_SWITCH_EFFECT + "</font><BR>");
            for (var ucIdx: any = 0; as2Less(ucIdx, useCases.length); ucIdx++) {
                var useCase: any = useCases[ucIdx];
                if (useCase._isDefault || !useCase.name) {
                    result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TIP_DEFAULT_BRANCH + "：</font><BR>");
                }
                else {
                    result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TIP_FOR + " " + getUseCaseDisplayName(ctx, useCase.name) + "：</font><BR>");
                }
                if (useCase.provideTagDict) {
                    var condTags: any[] = [];
                    for (var pTag of as2Keys(useCase.provideTagDict)) {
                        if (isInternalKey(pTag))
                            continue;
                        condTags.push(pTag);
                    }
                    if (as2Greater(condTags.length, 0)) {
                        result.push("  <font color='" + TooltipConstants.COL_COND_PROVIDE + "'>" + TooltipConstants.LBL_COND_PROVIDE_TAGS + "：</font>", condTags.join(", "), "<BR>");
                    }
                }
                if (useCase.requireTagDict) {
                    var requiredTags: any[] = [];
                    for (var rTag of as2Keys(useCase.requireTagDict)) {
                        if (isInternalKey(rTag))
                            continue;
                        requiredTags.push(rTag);
                    }
                    if (as2Greater(requiredTags.length, 0)) {
                        result.push("  <font color='" + TooltipConstants.COL_INSTALL_COND + "'>" + TooltipConstants.LBL_COND_REQUIRE_TAGS + "：</font>", requiredTags.join(", "), "<BR>");
                    }
                }
                buildStatBlock(ctx, result, useCase, "  ");
            }
        }
        export function buildStatBlock(ctx: Context, result?: any[], statsObj?: any, indent?: string): void {
            if (!statsObj)
                return;
            if (statsObj.percentage) {
                var sortedList: any = TooltipTextBuilder.getSortedAttrList(ctx, statsObj.percentage);
                for (var i: any = 0; as2Less(i, sortedList.length); i++) {
                    var key: any = sortedList[i];
                    if (as2Equal(key, "impact"))
                        continue;
                    result.push(indent);
                    TooltipFormatter.statLine(result, "multiply", key, statsObj.percentage[key], null);
                }
                if (as2NotEqual(statsObj.percentage.impact, undefined)) {
                    var pctImpact: number = as2Number(statsObj.percentage.impact);
                    if (!as2IsNaN(pctImpact) && as2NotEqual(pctImpact, 0) && as2Greater(pctImpact, -1)) {
                        var changePct: number = Math.round(-pctImpact / (1 + pctImpact) * 100);
                        var pctSign: string = as2GreaterEqual(changePct, 0) ? " + " : " - ";
                        if (as2Less(changePct, 0))
                            changePct = -changePct;
                        result.push(indent, TooltipConstants.LBL_IMPACT, pctSign, changePct, "%<BR>");
                    }
                }
            }
            if (statsObj.multiplier) {
                var sortedList: any = TooltipTextBuilder.getSortedAttrList(ctx, statsObj.multiplier);
                for (var i: any = 0; as2Less(i, sortedList.length); i++) {
                    var key: any = sortedList[i];
                    var mValue: any = statsObj.multiplier[key];
                    var label: any = TooltipConstants.PROPERTY_DICT[key];
                    if (!label)
                        label = key;
                    if (as2Equal(key, "impact")) {
                        var rawFactor: number = 1 + mValue;
                        if (as2Less(rawFactor, 0.01))
                            rawFactor = 0.01;
                        var dispFactor: number = Math.round((1 / rawFactor) * 100) / 100;
                        result.push(indent, "<FONT COLOR='" + TooltipConstants.COL_MULTIPLIER + "'>", label, " ×", dispFactor, "</FONT> <FONT COLOR='" + TooltipConstants.COL_MULTIPLIER_HINT + "'>" + TooltipConstants.TAG_MULTIPLIER_ZONE + "</FONT><BR>");
                        continue;
                    }
                    var factorValue: any = Math.round((1 + mValue) * 100) / 100;
                    var displayText: string = "×" + factorValue;
                    result.push(indent, "<FONT COLOR='" + TooltipConstants.COL_MULTIPLIER + "'>", label, " ", displayText, "</FONT> <FONT COLOR='" + TooltipConstants.COL_MULTIPLIER_HINT + "'>" + TooltipConstants.TAG_MULTIPLIER_ZONE + "</FONT><BR>");
                }
            }
            if (statsObj.curve) {
                var sortedList: any = TooltipTextBuilder.getSortedAttrList(ctx, statsObj.curve);
                for (var i: any = 0; as2Less(i, sortedList.length); i++) {
                    var key: any = sortedList[i];
                    appendCurveLine(ctx, result, indent, key, statsObj.curve[key]);
                }
            }
            if (statsObj.flat) {
                var sortedList: any = TooltipTextBuilder.getSortedAttrList(ctx, statsObj.flat);
                for (var i: any = 0; as2Less(i, sortedList.length); i++) {
                    var key: any = sortedList[i];
                    if (as2Equal(key, "slay"))
                        continue;
                    if (as2Equal(key, "impact"))
                        continue;
                    result.push(indent);
                    TooltipFormatter.statLine(result, "add", key, statsObj.flat[key], null);
                }
                if (statsObj.flat.slay) {
                    result.push(indent);
                    SlayEffectBuilder.buildFlat(ctx, result, statsObj.flat.slay);
                }
                if (as2NotEqual(statsObj.flat.impact, undefined)) {
                    var flatImpact: number = as2Number(statsObj.flat.impact);
                    if (!as2IsNaN(flatImpact) && as2NotEqual(flatImpact, 0)) {
                        var isBuff: boolean = (as2Less(flatImpact, 0));
                        var flatLabel: string = isBuff ? "冲击力增强" : "冲击力削弱";
                        var flatColor: string = isBuff ? TooltipConstants.COL_HL : TooltipConstants.COL_ROUT;
                        var flatAbs: number = isBuff ? -flatImpact : flatImpact;
                        var flatRawSign: string = isBuff ? " -" : " +";
                        result.push(indent, "<FONT COLOR='", flatColor, "'>", flatLabel, "</FONT> (原始", flatRawSign, flatAbs, ")<BR>");
                    }
                }
            }
            if (statsObj.override) {
                var sortedList: any = TooltipTextBuilder.getSortedAttrList(ctx, statsObj.override);
                for (var i: any = 0; as2Less(i, sortedList.length); i++) {
                    var key: any = sortedList[i];
                    if (as2Equal(key, "damagetype") || as2Equal(key, "magictype") || as2Equal(key, "criticalhit") || as2Equal(key, "silence") || as2Equal(key, "slay") || as2Equal(key, "actiontype") || as2Equal(key, "singleshoot") || as2Equal(key, "reloadType") || as2Equal(key, "impact") || as2Equal(key, "bullet") || as2Equal(key, "bulletrename") || as2Equal(key, "split") || as2Equal(key, "hitBehavior"))
                        continue;
                    result.push(indent);
                    TooltipFormatter.statLine(result, "override", key, statsObj.override[key], null);
                }
                if (statsObj.override.slay) {
                    result.push(indent);
                    SlayEffectBuilder.buildOverride(ctx, result, statsObj.override.slay);
                }
                if (statsObj.override.actiontype) {
                    result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>" + TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipConstants.LBL_ACTION_TYPE, " → ", statsObj.override.actiontype, "<BR>");
                }
            }
            if (statsObj.merge) {
                var sortedList: any = TooltipTextBuilder.getSortedAttrList(ctx, statsObj.merge);
                for (var i: any = 0; as2Less(i, sortedList.length); i++) {
                    var key: any = sortedList[i];
                    if (as2Equal(key, "magicdefence") || as2Equal(key, "skillmultipliers") || as2Equal(key, "hitBehavior") || as2Equal(key, "switchstrike") || as2Equal(key, "overload"))
                        continue;
                    result.push(indent);
                    TooltipFormatter.statLine(result, "merge", key, statsObj.merge[key], null);
                }
            }
            if (statsObj.cap) {
                var sortedList: any = TooltipTextBuilder.getSortedAttrList(ctx, statsObj.cap);
                for (var i: any = 0; as2Less(i, sortedList.length); i++) {
                    var key: any = sortedList[i];
                    var capValue: any = statsObj.cap[key];
                    var label: any = TooltipConstants.PROPERTY_DICT[key];
                    if (!label)
                        label = key;
                    if (as2Greater(capValue, 0)) {
                        result.push(indent, "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " " + TooltipConstants.TIP_CAP_UPPER + ": +", capValue, "</FONT><BR>");
                    }
                    else if (as2Less(capValue, 0)) {
                        result.push(indent, "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " " + TooltipConstants.TIP_CAP_LOWER + ": ", capValue, "</FONT><BR>");
                    }
                }
            }
            if (statsObj.override) {
                if (statsObj.override.criticalhit) {
                    result.push(indent, TooltipTextBuilder.quickBuildCriticalHit(ctx, statsObj.override.criticalhit));
                }
                if (statsObj.override.magicdefence) {
                    result.push(indent, TooltipTextBuilder.quickBuildMagicDefence(ctx, statsObj.override.magicdefence, TooltipConstants.TXT_OVERRIDE));
                }
                if (statsObj.override.skillmultipliers) {
                    result.push(indent, TooltipTextBuilder.quickBuildSkillMultipliers(ctx, statsObj.override.skillmultipliers, TooltipConstants.TXT_OVERRIDE));
                }
                if (statsObj.override.silence) {
                    result.push(indent);
                    SilenceEffectBuilder.build(ctx, result, null, null, statsObj.override, null);
                }
                if (as2NotEqual(statsObj.override.singleshoot, undefined)) {
                    var singleshootVal: boolean = (as2Equal(statsObj.override.singleshoot, true) || as2Equal(statsObj.override.singleshoot, "true"));
                    var fireModeDesc: string = singleshootVal ? TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipConstants.TIP_FIRE_MODE_AUTO;
                    result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>" + TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipConstants.LBL_FIRE_MODE, " → ", fireModeDesc, "<BR>");
                }
                if (as2NotEqual(statsObj.override.reloadType, undefined)) {
                    var reloadTypeVal: string = statsObj.override.reloadType;
                    var reloadTypeDesc: string = (as2Equal(reloadTypeVal, "tube")) ? TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipConstants.TIP_RELOAD_TYPE_MAG;
                    result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>" + TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipConstants.LBL_RELOAD_TYPE, " → ", reloadTypeDesc, "<BR>");
                }
                if (as2NotEqual(statsObj.override.impact, undefined)) {
                    var impactRaw: number = as2Number(statsObj.override.impact);
                    if (!as2IsNaN(impactRaw) && as2Greater(impactRaw, 0)) {
                        result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>" + TooltipConstants.TAG_OVERRIDE + " </FONT>");
                        result.push(TooltipConstants.LBL_IMPACT, " → ", Math.floor(500 / impactRaw), "<BR>");
                    }
                }
                if (statsObj.override.ammoConversion === "slug") {
                    result.push(indent, TooltipConstants.LBL_BULLET_TYPE, " → 独头弹<BR>",
                        indent, "独头基础威力 = 单丸基础威力 × 原弹丸数 ÷ 4<BR>",
                        indent, TooltipConstants.LBL_PELLET_COUNT, " → 1<BR>",
                        indent, "基础弹速至少为 80，再计入弹速配件<BR>");
                }
                if (statsObj.override.bullet || statsObj.override.bulletrename) {
                    var bulletDisplay: string = statsObj.override.bulletrename
                        ? statsObj.override.bulletrename
                        : statsObj.override.bullet;
                    result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>" + TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipConstants.LBL_BULLET_TYPE, " → ", bulletDisplay, "<BR>");
                }
                if (as2NotEqual(statsObj.override.split, undefined)) {
                    result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>" + TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipConstants.LBL_PELLET_COUNT, " → ", statsObj.override.split, "<BR>");
                }
                if (statsObj.override.hitBehavior) {
                    appendHitBehavior(ctx, result, indent, statsObj.override.hitBehavior);
                }
            }
            if (statsObj.merge) {
                WeaponAmmoInfoBuilder.appendMerge(ctx, result, statsObj.merge.overload, indent);
                if (statsObj.merge.magicdefence) {
                    result.push(indent, TooltipTextBuilder.quickBuildMagicDefence(ctx, statsObj.merge.magicdefence, TooltipConstants.TXT_MERGE));
                }
                if (statsObj.merge.skillmultipliers) {
                    result.push(indent, TooltipTextBuilder.quickBuildSkillMultipliers(ctx, statsObj.merge.skillmultipliers, TooltipConstants.TXT_MERGE));
                }
                if (statsObj.merge.hitBehavior) {
                    appendHitBehavior(ctx, result, indent, statsObj.merge.hitBehavior);
                }
                if (statsObj.merge.switchstrike) {
                    appendSwitchStrike(ctx, result, indent, statsObj.merge.switchstrike);
                }
            }
            if (statsObj.override && statsObj.override.damagetype) {
                result.push(indent);
                TooltipTextBuilder.quickBuildDamageType(ctx, result, statsObj.override);
            }
            if (statsObj.softOverride) {
                result.push(indent, "<FONT COLOR='", TooltipConstants.COL_INFO, "'>【可覆盖设定】</FONT><BR>");
                buildStatBlock(ctx, result, { override: statsObj.softOverride }, indent + "  ");
            }
            if (statsObj.lockOverride) {
                result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>【最终锁定】</FONT><BR>");
                buildStatBlock(ctx, result, { override: statsObj.lockOverride }, indent + "  ");
            }
        }
        function appendSwitchStrike(ctx: Context, result?: any[], indent?: string, config?: any): void {
            if (!config)
                return;
            if (as2NotEqual(config.weightCoefficient, undefined)) {
                result.push(indent, "切手技重量系数 → ", config.weightCoefficient, "<BR>");
            }
            if (as2NotEqual(config.impactMultiplier, undefined)) {
                result.push(indent, "切手技冲击力 ×", config.impactMultiplier, "<BR>");
            }
        }
        export function getUseCaseDisplayName(ctx: Context, rawName?: string): string {
            if (!rawName)
                return "";
            var rawParts: any[] = rawName.split(",");
            var displayParts: any[] = [];
            for (var i: number = 0; as2Less(i, rawParts.length); i++) {
                var token: string = trimSimple(ctx, String(rawParts[i]));
                if (as2Equal(token.indexOf("weapontype:"), 0)) {
                    displayParts.push(TooltipConstants.LBL_SCOPE_WEAPON_TYPE + "：" + token.substring(11));
                }
                else if (as2Equal(token.indexOf("use:"), 0)) {
                    displayParts.push(TooltipConstants.LBL_SCOPE_USE + "：" + token.substring(4));
                }
                else if (as2Greater(token.length, 0)) {
                    displayParts.push(token);
                }
            }
            return displayParts.join("/");
        }
        export function buildHitBehaviorSummary(ctx: Context, behavior?: any): string {
            if (!behavior)
                return "";
            if (isGrayGooEtchBehavior(ctx, behavior))
                return buildGrayGooEtchSummary(ctx, behavior);
            if (isGrayGooBehavior(ctx, behavior))
                return buildGrayGooSummary(ctx, behavior);
            var parts: any[] = [];
            if (as2NotEqual(behavior.duration, undefined)) {
                parts.push(TooltipConstants.LBL_MARK_DURATION + formatFramesAsSeconds(ctx, behavior.duration));
            }
            if (as2NotEqual(behavior.damagePerStack, undefined)) {
                parts.push(TooltipConstants.LBL_DAMAGE_PER_STACK + "+" + formatPercent(ctx, behavior.damagePerStack));
            }
            if (as2NotEqual(behavior.maxDuration, undefined)) {
                parts.push(TooltipConstants.LBL_MAX_DURATION + formatFramesAsSeconds(ctx, behavior.maxDuration));
            }
            if (as2NotEqual(behavior.maxStacks, undefined)) {
                parts.push(TooltipConstants.LBL_MAX_STACKS + behavior.maxStacks + "层");
            }
            if (as2NotEqual(behavior.breakExtend, undefined)) {
                parts.push(TooltipConstants.LBL_BREAK_EXTEND + "+" + formatFramesAsSeconds(ctx, behavior.breakExtend));
            }
            if (as2NotEqual(behavior.decayDelay, undefined)) {
                parts.push(TooltipConstants.LBL_DECAY_DELAY + formatFramesAsSeconds(ctx, behavior.decayDelay));
            }
            if (as2NotEqual(behavior.decayInterval, undefined)) {
                parts.push(TooltipConstants.LBL_DECAY_INTERVAL + formatFramesAsSeconds(ctx, behavior.decayInterval));
            }
            if (as2NotEqual(behavior.hitStacks, undefined)) {
                parts.push(TooltipConstants.LBL_HIT_STACKS + behavior.hitStacks + "格");
            }
            if (as2NotEqual(behavior.breakStacks, undefined)) {
                parts.push(TooltipConstants.LBL_BREAK_STACKS + behavior.breakStacks + "格");
            }
            if (as2NotEqual(behavior.milestoneInterval, undefined)) {
                parts.push("每" + behavior.milestoneInterval + "格" + TooltipConstants.LBL_MILESTONE_INTERVAL);
            }
            if (as2NotEqual(behavior.crumblePerMilestone, undefined)) {
                parts.push(TooltipConstants.LBL_CRUMBLE_PER_MILESTONE + formatRawPercent(ctx, behavior.crumblePerMilestone));
            }
            if (as2NotEqual(behavior.executeAtMax, undefined)) {
                parts.push(TooltipConstants.LBL_EXECUTE_AT_MAX + formatRawPercent(ctx, behavior.executeAtMax));
            }
            return parts.join("，");
        }
        function appendHitBehavior(ctx: Context, result?: any[], indent?: string, behavior?: any): void {
            if (!behavior)
                return;
            if (isGrayGooEtchBehavior(ctx, behavior)) {
                appendGrayGooEtchBehavior(ctx, result, indent, behavior);
                return;
            }
            if (isGrayGooBehavior(ctx, behavior)) {
                appendGrayGooBehavior(ctx, result, indent, behavior);
                return;
            }
            result.push(indent, "<FONT COLOR='", TooltipConstants.COL_USE_SWITCH, "'>", TooltipConstants.LBL_HIT_BEHAVIOR, "</FONT><BR>");
            if (as2NotEqual(behavior.duration, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_MARK_DURATION, " ", formatFramesAsSeconds(ctx, behavior.duration), "<BR>");
            }
            if (as2NotEqual(behavior.breakExtend, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_BREAK_EXTEND, " +", formatFramesAsSeconds(ctx, behavior.breakExtend), "<BR>");
            }
            if (as2NotEqual(behavior.maxDuration, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_MAX_DURATION, " ", formatFramesAsSeconds(ctx, behavior.maxDuration), "<BR>");
            }
            if (as2NotEqual(behavior.maxStacks, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_MAX_STACKS, " ", behavior.maxStacks, "层<BR>");
            }
            if (as2NotEqual(behavior.damagePerStack, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_DAMAGE_PER_STACK, " +", formatPercent(ctx, behavior.damagePerStack), "<BR>");
            }
            if (as2NotEqual(behavior.decayDelay, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_DECAY_DELAY, " ", formatFramesAsSeconds(ctx, behavior.decayDelay), "<BR>");
            }
            if (as2NotEqual(behavior.decayInterval, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_DECAY_INTERVAL, " ", formatFramesAsSeconds(ctx, behavior.decayInterval), "<BR>");
            }
            if (as2NotEqual(behavior.hitStacks, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_HIT_STACKS, " ", behavior.hitStacks, "格<BR>");
            }
            if (as2NotEqual(behavior.breakStacks, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_BREAK_STACKS, " ", behavior.breakStacks, "格<BR>");
            }
            if (as2NotEqual(behavior.milestoneInterval, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_MILESTONE_INTERVAL, " 每", behavior.milestoneInterval, "格<BR>");
            }
            if (as2NotEqual(behavior.crumblePerMilestone, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_CRUMBLE_PER_MILESTONE, " ", formatRawPercent(ctx, behavior.crumblePerMilestone), "<BR>");
            }
            if (as2NotEqual(behavior.executeAtMax, undefined)) {
                result.push(indent, "  ", TooltipConstants.LBL_EXECUTE_AT_MAX, " ", formatRawPercent(ctx, behavior.executeAtMax), "<BR>");
            }
            if (as2Equal(behavior.sameSourceOnly, true) || as2Equal(behavior.sameSourceOnly, "true")) {
                result.push(indent, "  ", TooltipConstants.TIP_SAME_SOURCE_ONLY, "<BR>");
            }
        }
        function isGrayGooEtchBehavior(ctx: Context, behavior?: any): boolean {
            return as2Equal(String(behavior.type), "grayGooEtch") || as2NotEqual(behavior.delayFrames, undefined) || as2NotEqual(behavior.detonationCrumble, undefined);
        }
        function buildGrayGooEtchSummary(ctx: Context, behavior?: any): string {
            var parts: any[] = [];
            if (as2NotEqual(behavior.delayFrames, undefined)) {
                parts.push("延迟" + formatFramesAsSeconds(ctx, behavior.delayFrames) + "引爆贴身满伤");
            }
            if (as2NotEqual(behavior.detonationCrumble, undefined) && as2Greater(as2Number(behavior.detonationCrumble), 0)) {
                parts.push("引爆击溃" + formatRawPercent(ctx, behavior.detonationCrumble));
            }
            return parts.join("；");
        }
        function appendGrayGooEtchBehavior(ctx: Context, result?: any[], indent?: string, behavior?: any): void {
            var summary: string = buildGrayGooEtchSummary(ctx, behavior);
            if (as2Greater(indent.length, 0)) {
                if (as2Greater(summary.length, 0))
                    result.push(indent, "  ", summary, "<BR>");
                return;
            }
            result.push(indent, "<FONT COLOR='", TooltipConstants.COL_USE_SWITCH, "'>", TooltipConstants.LBL_GRAY_GOO_BEHAVIOR, "</FONT><BR>");
            if (as2Greater(summary.length, 0))
                result.push(indent, "  ", summary, "<BR>");
            result.push(indent, "  蚀刻未引爆期间不叠加不刷新；目标提前阵亡不触发<BR>");
        }
        function isGrayGooBehavior(ctx: Context, behavior?: any): boolean {
            return as2Equal(String(behavior.type), "grayGooPrimer") || as2NotEqual(behavior.hitStacks, undefined) || as2NotEqual(behavior.crumblePerMilestone, undefined) || as2NotEqual(behavior.executeAtMax, undefined);
        }
        function buildGrayGooSummary(ctx: Context, behavior?: any): string {
            var isBranchProfile: boolean = (as2NotEqual(behavior.profileId, undefined) && as2NotEqual(String(behavior.profileId), "base"));
            var parts: any[] = [];
            if (as2NotEqual(behavior.hitStacks, undefined) && as2Equal(behavior.breakStacks, behavior.hitStacks)) {
                parts.push("命中/破韧+" + behavior.hitStacks + "格");
            }
            else {
                if (as2NotEqual(behavior.hitStacks, undefined))
                    parts.push("命中+" + behavior.hitStacks + "格");
                if (as2NotEqual(behavior.breakStacks, undefined))
                    parts.push("破韧+" + behavior.breakStacks + "格");
            }
            if (!isBranchProfile && as2NotEqual(behavior.maxStacks, undefined))
                parts.push("上限" + behavior.maxStacks + "格");
            if (!isBranchProfile && as2NotEqual(behavior.damagePerStack, undefined)) {
                parts.push("每格易伤+" + formatPercent(ctx, behavior.damagePerStack));
            }
            if (as2NotEqual(behavior.crumblePerMilestone, undefined)) {
                var milestone: string = (!isBranchProfile && as2NotEqual(behavior.milestoneInterval, undefined))
                    ? "每" + behavior.milestoneInterval + "格" : "节点";
                parts.push(milestone + "击溃" + formatRawPercent(ctx, behavior.crumblePerMilestone));
            }
            if (as2NotEqual(behavior.executeAtMax, undefined)) {
                parts.push("满层斩杀" + formatRawPercent(ctx, behavior.executeAtMax));
            }
            if (as2NotEqual(behavior.decayDelay, undefined)) {
                parts.push("停火" + formatFramesAsSeconds(ctx, behavior.decayDelay) + "后衰减");
            }
            return parts.join("；");
        }
        function appendGrayGooBehavior(ctx: Context, result?: any[], indent?: string, behavior?: any): void {
            var isBranchProfile: boolean = (as2NotEqual(behavior.profileId, undefined) && as2NotEqual(String(behavior.profileId), "base")) || as2Greater(indent.length, 0);
            var isBase: boolean = (as2NotEqual(behavior.type, undefined)) && !isBranchProfile;
            if (!isBase) {
                var summary: string = buildGrayGooSummary(ctx, behavior);
                if (as2Greater(summary.length, 0))
                    result.push(indent, "  ", summary, "<BR>");
                return;
            }
            result.push(indent, "<FONT COLOR='", TooltipConstants.COL_USE_SWITCH, "'>", TooltipConstants.LBL_GRAY_GOO_BEHAVIOR, "</FONT><BR>");
            var overview: any[] = [];
            if (as2NotEqual(behavior.maxStacks, undefined))
                overview.push(behavior.maxStacks + "格");
            if (as2NotEqual(behavior.damagePerStack, undefined)) {
                overview.push("每格易伤+" + formatPercent(ctx, behavior.damagePerStack));
            }
            if (as2Greater(overview.length, 0))
                result.push(indent, "  ", overview.join("，"), "<BR>");
            var trigger: any[] = [];
            if (as2NotEqual(behavior.hitStacks, undefined) && as2Equal(behavior.breakStacks, behavior.hitStacks)) {
                trigger.push("命中/破韧+" + behavior.hitStacks + "格");
            }
            else {
                if (as2NotEqual(behavior.hitStacks, undefined))
                    trigger.push("命中+" + behavior.hitStacks + "格");
                if (as2NotEqual(behavior.breakStacks, undefined))
                    trigger.push("破韧+" + behavior.breakStacks + "格");
            }
            if (as2NotEqual(behavior.crumblePerMilestone, undefined)) {
                var milestone: string = as2NotEqual(behavior.milestoneInterval, undefined) ? "每" + behavior.milestoneInterval + "格" : "节点";
                trigger.push(milestone + "击溃" + formatRawPercent(ctx, behavior.crumblePerMilestone));
            }
            if (as2Greater(trigger.length, 0))
                result.push(indent, "  ", trigger.join("；"), "<BR>");
            var sustain: any[] = [];
            if (as2NotEqual(behavior.executeAtMax, undefined)) {
                sustain.push("满层斩杀" + formatRawPercent(ctx, behavior.executeAtMax));
            }
            if (as2NotEqual(behavior.decayDelay, undefined)) {
                sustain.push("停火" + formatFramesAsSeconds(ctx, behavior.decayDelay) + "后衰减");
            }
            if (as2Greater(sustain.length, 0))
                result.push(indent, "  ", sustain.join("；"), "<BR>");
            if (as2Equal(behavior.milestoneInterval, 6) && as2Equal(behavior.maxStacks, 18)) {
                result.push(indent, "  首跨6/12/18格削上限并伤血（Ⅰ/Ⅱ/Ⅲ阶标记）；退至12/6/0格重装<BR>");
            }
        }
        function formatFramesAsSeconds(ctx: Context, frameValue?: any): string {
            var frames: number = as2Number(frameValue);
            if (as2IsNaN(frames))
                return String(frameValue);
            var seconds: number = Math.round(frames / 30 * 10) / 10;
            return seconds + TooltipConstants.SUF_SECOND;
        }
        function formatPercent(ctx: Context, value?: any): string {
            var numericValue: number = as2Number(value);
            if (as2IsNaN(numericValue))
                return String(value);
            return (Math.round(numericValue * 1000) / 10) + TooltipConstants.SUF_PERCENT;
        }
        function formatRawPercent(ctx: Context, value?: any): string {
            var numericValue: number = as2Number(value);
            if (as2IsNaN(numericValue))
                return String(value);
            return (Math.round(numericValue * 10) / 10) + TooltipConstants.SUF_PERCENT;
        }
        function trimSimple(ctx: Context, value?: string): string {
            while (as2Greater(value.length, 0) && as2Equal(value.charAt(0), " "))
                value = value.substring(1);
            while (as2Greater(value.length, 0) && as2Equal(value.charAt(value.length - 1), " "))
                value = value.substring(0, value.length - 1);
            return value;
        }
        function appendCurveLine(ctx: Context, result?: any[], indent?: string, key?: string, curveConfig?: any): void {
            var label: string = TooltipConstants.PROPERTY_DICT[key];
            if (!label)
                label = key;
            var curveType: string = "sqrtScale";
            var coefficient: number = 1;
            var minValue: number = 1;
            if (as2Equal(typeof curveConfig, "object") && as2NotEqual(curveConfig, null)) {
                if (as2NotEqual(curveConfig.type, undefined)) {
                    curveType = String(curveConfig.type);
                }
                if (as2NotEqual(curveConfig.coefficient, undefined)) {
                    coefficient = as2Number(curveConfig.coefficient);
                }
                else if (as2NotEqual(curveConfig.scale, undefined)) {
                    coefficient = as2Number(curveConfig.scale);
                }
                if (as2NotEqual(curveConfig.min, undefined)) {
                    minValue = as2Number(curveConfig.min);
                }
            }
            else {
                coefficient = as2Number(curveConfig);
            }
            if (as2IsNaN(coefficient) || as2LessEqual(coefficient, 0))
                coefficient = 1;
            if (as2IsNaN(minValue))
                minValue = 1;
            result.push(indent, "<FONT COLOR='", TooltipConstants.COL_CURVE, "'>", TooltipConstants.TAG_CURVE, " ", label, "：");
            if (as2Equal(curveType, "sqrtScale") || as2Equal(curveType, "sqrt")) {
                result.push(TooltipConstants.LBL_CURVE_COMPRESSION_LEVEL, " ", calculateCurveCompressionLevel(ctx, coefficient));
            }
            else if (as2Equal(curveType, "saturatingAdd")) {
                var amount: number = as2Number(curveConfig.amount);
                if (!as2IsNaN(amount) && as2IsFinite(amount) && as2GreaterEqual(amount, 0)) {
                    result.push("柔性增加，最多 +", amount);
                    if (as2Equal(key, "interval"))
                        result.push("毫秒");
                }
                else {
                    result.push("柔性增加");
                }
            }
            else {
                result.push(curveType);
            }
            result.push("</FONT><BR>");
        }
        function calculateCurveCompressionLevel(ctx: Context, coefficient?: number): number {
            var neutralCoefficient: number = 2;
            var referenceCoefficient: number = 1.414;
            var referenceLevel: number = 20;
            var level: number = Math.round((neutralCoefficient - coefficient) / (neutralCoefficient - referenceCoefficient) * referenceLevel);
            return as2Less(level, 0) ? 0 : level;
        }
        export function buildBulletSwitchDetailed(ctx: Context, result?: any[], stats?: any): void {
            if (!stats || !stats.bulletSwitch || !stats.bulletSwitch.bulletCases) {
                return;
            }
            var bulletCases: any[] = stats.bulletSwitch.bulletCases;
            if (as2Equal(bulletCases.length, 0)) {
                return;
            }
            result.push("<font color='" + TooltipConstants.COL_BULLET_SWITCH + "'>" + TooltipConstants.LBL_BULLET_SWITCH_EFFECT + "</font><BR>");
            for (var bcIdx: number = 0; as2Less(bcIdx, bulletCases.length); bcIdx++) {
                var bulletCase: any = bulletCases[bcIdx];
                if (bulletCase._isDefault || !bulletCase.name) {
                    result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TIP_DEFAULT_BRANCH + "：</font><BR>");
                }
                else {
                    var displayNames: any[] = [];
                    var names: any[] = bulletCase.name.split(",");
                    for (var ni: number = 0; as2Less(ni, names.length); ni++) {
                        var trimmed: string = names[ni];
                        while (as2Equal(trimmed.charAt(0), " "))
                            trimmed = trimmed.substr(1);
                        while (as2Equal(trimmed.charAt(trimmed.length - 1), " "))
                            trimmed = trimmed.substr(0, trimmed.length - 1);
                        var cnName: string = TooltipConstants.BULLET_TYPE_NAMES[trimmed];
                        displayNames.push(cnName ? cnName : trimmed);
                    }
                    result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TIP_BULLET_FOR + " " + displayNames.join("/") + " " + TooltipConstants.TIP_BULLET_SUFFIX + "：</font><BR>");
                }
                buildStatBlock(ctx, result, bulletCase, "  ");
            }
        }
    }
}
