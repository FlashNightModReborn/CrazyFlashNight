// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/ModStatBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace ModStatBuilder {
        export function build(ctx: Context, itemName?: string): any[] {
            return buildInternal(ctx, itemName, null);
        }
        export function buildWithRows(ctx: Context, itemName?: string): any {
            var ranges: any = {};
            var html: any[] = buildInternal(ctx, itemName, ranges);
            if (as2Equal(html.length, 0))
                return null;
            var rows: any[] = [];
            appendRowGroup(ctx, rows, "装配要求", html, ranges.infoStart, ranges.effectStart);
            appendRowGroup(ctx, rows, "属性与效果", html, ranges.effectStart, ranges.descriptionStart);
            appendRowGroup(ctx, rows, "附加说明", html, ranges.descriptionStart, html.length);
            return { kind: "modinfo", title: TooltipConstants.LBL_MOD_INFO,
                rows: rows, html: html.join("") };
        }
        function appendRowGroup(ctx: Context, rows?: any[], title?: string, html?: any[], start?: number, end?: number): void {
            if (as2GreaterEqual(start, end))
                return;
            rows.push({ name: title, depth: 0 });
            var text: string = "";
            for (var i: number = start; as2Less(i, end); i++)
                text += String(html[i]);
            var lines: any[] = text.split("<BR>");
            for (var j: number = 0; as2Less(j, lines.length); j++) {
                if (as2Equal(lines[j].length, 0))
                    continue;
                rows.push({ depth: 1, effect: lines[j] });
            }
        }
        function buildInternal(ctx: Context, itemName?: string, ranges?: any): any[] {
            var result: any = [];
            // The AS2 registry has already accepted/rejected and resolved this standalone mod.
            // A catalog row is descriptive data, never proof of publication/eligibility.
            const registeredName = ctx.projection.registeredModName;
            const modData: any = registeredName == null ? null : ctx.catalog.mods[registeredName];
            if (registeredName != null && !modData) throw new InputError('catalog_mod_missing');
            if (!modData)
                return result;
            result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_MOD_INFO + "</font><BR>");
            if (as2NotEqual(ranges, null))
                ranges.infoStart = result.length;
            result.push(TooltipConstants.LBL_MOD_USE_TYPE, "：", modData.use, "<BR>");
            if (modData.tagValue) {
                result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.LBL_MOD_SLOT + "：</font>", modData.tagValue, "<BR>");
            }
            if (modData.weapontype) {
                result.push(TooltipConstants.LBL_MOD_WEAPON_TYPE, "：", modData.weapontype, "<BR>");
            }
            if (modData.excludeWeapontype) {
                result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_MOD_EXCLUDE_WEAPON_TYPE + "：</font>", modData.excludeWeapontype, "<BR>");
            }
            if (modData.grantsUse) {
                result.push("<font color='" + TooltipConstants.COL_ENHANCE + "'>" + TooltipConstants.LBL_MOD_GRANTS_USE + "：</font>", modData.grantsUse, "<BR>");
            }
            if (modData.grantsWeapontype) {
                result.push("<font color='" + TooltipConstants.COL_ENHANCE + "'>" + TooltipConstants.LBL_MOD_GRANTS_WEAPON_TYPE + "：</font>", modData.grantsWeapontype, "<BR>");
            }
            if (modData.provideTagDict) {
                var provideTags: any = [];
                for (var pTag of as2Keys(modData.provideTagDict)) {
                    if (isInternalKey(pTag))
                        continue;
                    provideTags.push(pTag);
                }
                if (as2Greater(provideTags.length, 0)) {
                    result.push("<font color='" + TooltipConstants.COL_ENHANCE + "'>" + TooltipConstants.LBL_PROVIDE_TAGS + "：</font>", provideTags.join(", "), "<BR>");
                }
            }
            if (modData.requireTagDict) {
                var requireTags: any = [];
                for (var rTag of as2Keys(modData.requireTagDict)) {
                    if (isInternalKey(rTag))
                        continue;
                    requireTags.push(rTag);
                }
                if (as2Greater(requireTags.length, 0)) {
                    result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_REQUIRE_TAGS + "：</font>", requireTags.join(", "), "<BR>");
                }
            }
            if (modData.excludeBulletTypeDict) {
                var excludeNames: any[] = bulletTypeDictToNames(ctx, modData.excludeBulletTypeDict);
                if (as2Greater(excludeNames.length, 0)) {
                    result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_EXCLUDE_BULLET_TYPES + "：</font>", excludeNames.join(", "), "<BR>");
                }
            }
            if (modData.requireBulletTypeDict) {
                var requireNames: any[] = bulletTypeDictToNames(ctx, modData.requireBulletTypeDict);
                if (as2Greater(requireNames.length, 0)) {
                    result.push("<font color='" + TooltipConstants.COL_INSTALL_COND + "'>" + TooltipConstants.LBL_REQUIRE_BULLET_TYPES + "：</font>", requireNames.join(", "), "<BR>");
                }
            }
            const installConditions = modData.installCondList || displayConditionList(modData.installCondition);
            if (installConditions) {
                var condLines: any[] = buildInstallConditionText(ctx, installConditions);
                if (as2Greater(condLines.length, 0)) {
                    result.push("<font color='" + TooltipConstants.COL_INSTALL_COND + "'>" + TooltipConstants.LBL_INSTALL_CONDITION + "：</font><BR>");
                    for (var ci: number = 0; as2Less(ci, condLines.length); ci++) {
                        result.push("  " + condLines[ci] + "<BR>");
                    }
                }
            }
            if (as2NotEqual(ranges, null))
                ranges.effectStart = result.length;
            var stats: any = modData.stats;
            UseSwitchStatsBuilder.buildStatBlock(ctx, result, stats, "");
            UseSwitchStatsBuilder.buildBaseSwitchDetailed(ctx, result, stats);
            UseSwitchStatsBuilder.buildDetailed(ctx, result, stats);
            TagSwitchStatsBuilder.buildDetailed(ctx, result, stats);
            UseSwitchStatsBuilder.buildBulletSwitchDetailed(ctx, result, stats);
            if (modData.subweapon) {
                result = result.concat(TooltipTextBuilder.buildSubweaponInfo(ctx, modData.subweapon));
            }
            if (modData.skill && !modData.skillSwitch) {
                result = result.concat(TooltipTextBuilder.buildSkillInfo(ctx, modData.skill));
            }
            appendSkillSwitchInfo(ctx, result, modData);
            var lighting: any[] = EquipmentLightingInfoBuilder.build(ctx, modData, null, true);
            for (var li: number = 0; as2Less(li, lighting.length); li++)
                result.push(lighting[li]);
            if (as2NotEqual(ranges, null))
                ranges.descriptionStart = result.length;
            if (typeof modData.description === "string") {
                result.push(TooltipFormatter.normalizeDescription(modData.description), TooltipFormatter.br());
            }
            return result;
        }
        function bulletTypeDictToNames(ctx: Context, typeDict?: any): any[] {
            var names: any[] = [];
            var nameMap: any = TooltipConstants.BULLET_TYPE_NAMES;
            for (var key of as2Keys(typeDict)) {
                if (isInternalKey(key))
                    continue;
                var name: string = nameMap[key];
                names.push(name ? name : key);
            }
            return names;
        }
        function appendSkillSwitchInfo(ctx: Context, result?: any[], modData?: any): void {
            if (!modData || !modData.skillSwitch)
                return;
            var useCases: any[] = modData.skillSwitch.useCases;
            if (!useCases) {
                if (Array.isArray(modData.skillSwitch.use)) {
                    useCases = modData.skillSwitch.use;
                }
                else if (modData.skillSwitch.use) {
                    useCases = [modData.skillSwitch.use];
                }
            }
            if (!useCases || as2LessEqual(useCases.length, 0))
                return;
            var rows: any[] = [];
            var namedCount: number = 0;
            var hasDefault: boolean = false;
            for (var i: number = 0; as2Less(i, useCases.length); i++) {
                var useCase: any = useCases[i];
                if (!useCase)
                    continue;
                var skill: any = useCase.skill ? useCase.skill : useCase;
                if (!skill || !skill.skillname)
                    continue;
                var isDefault: boolean = (useCase._isDefault || !useCase.name);
                var useLabel: string = isDefault
                    ? TooltipConstants.TIP_DEFAULT_BRANCH
                    : UseSwitchStatsBuilder.getUseCaseDisplayName(ctx, useCase.name);
                if (isDefault) {
                    hasDefault = true;
                }
                else {
                    namedCount++;
                }
                rows.push({ label: useLabel, skill: skill, isDefault: isDefault });
            }
            if (modData.skill && !hasDefault) {
                rows.push({ label: TooltipConstants.TIP_DEFAULT_BRANCH, skill: modData.skill, isDefault: true });
            }
            if (as2LessEqual(rows.length, 0))
                return;
            if (as2Equal(rows.length, 1) && as2Equal(namedCount, 0)) {
                var singleInfo: any[] = TooltipTextBuilder.buildSkillInfo(ctx, rows[0].skill);
                for (var si: number = 0; as2Less(si, singleInfo.length); si++) {
                    result.push(singleInfo[si]);
                }
                return;
            }
            result.push("<font color='" + TooltipConstants.COL_HL + "'>", TooltipConstants.LBL_ACTIVE_SKILL, "</font>按装备类型切换<BR>");
            for (var ri: number = 0; as2Less(ri, rows.length); ri++) {
                appendSkillSwitchSkillLine(ctx, result, rows[ri].label, rows[ri].skill);
            }
        }
        function appendSkillSwitchSkillLine(ctx: Context, result?: any[], label?: string, skill?: any): void {
            var skillLabel: string = skill.skillname;
            result.push("  <font color='" + TooltipConstants.COL_USE_SWITCH + "'>[", label, "]</font> ", skillLabel);
            var summary: string = buildSkillSwitchSkillSummary(ctx, skill);
            if (as2Greater(summary.length, 0)) {
                result.push("：", summary);
            }
            result.push("<BR>");
        }
        function buildSkillSwitchSkillSummary(ctx: Context, skill?: any): string {
            if (!skill)
                return "";
            if (skill.information)
                return String(skill.information);
            var parts: any[] = [];
            if (hasSkillValue(ctx, skill.cd)) {
                parts.push(TooltipConstants.LBL_COOLDOWN + (as2Number(skill.cd) / 1000) + TooltipConstants.SUF_SECOND);
            }
            if (hasSkillValue(ctx, skill.hp) && as2NotEqual(as2Number(skill.hp), 0)) {
                parts.push(TooltipConstants.LBL_COST + skill.hp + TooltipConstants.SUF_HP);
            }
            if (hasSkillValue(ctx, skill.mp) && as2NotEqual(as2Number(skill.mp), 0)) {
                parts.push(TooltipConstants.LBL_COST + skill.mp + TooltipConstants.SUF_MP);
            }
            if (as2Greater(parts.length, 0))
                return parts.join("，") + "。";
            if (skill.description)
                return TooltipFormatter.normalizeDescription(skill.description);
            return "";
        }
        function hasSkillValue(ctx: Context, value?: any): boolean {
            return as2NotEqual(value, undefined) && as2NotEqual(value, null) && as2Greater(String(value).length, 0);
        }
        const pathNames = Object.freeze({
            actiontype: "动作类型", "data.damagetype": "伤害类型", "data.interval": "攻击间隔",
            "data.power": "威力", "data.defence": "防御", "data.weight": "重量", "data.hp": "生命值",
            "data.mp": "魔法值", "data.accuracy": "精准", "data.diffusion": "散布", "data.velocity": "弹速",
            "data.capacity": "弹匣容量", "data.damage": "伤害", "data.force": "力度", "data.punch": "冲击",
            "data.bullet": "子弹类型", "data.magictype": "魔法属性", "data.criticalhit": "暴击",
            "data.bulletsize": "纵向范围", "data.modslot": "插件槽", "data.split": "霰弹值"
        });
        const opSymbols = Object.freeze({
            is: " 为 ", isNot: " ≠ ", above: " > ", atLeast: " ≥ ", below: " &lt; ", atMost: " ≤ ",
            oneOf: " ∈ ", noneOf: " ∉ ", contains: " 包含 ", range: "", exists: " 存在", missing: " 不存在"
        });
        function getPathNameMap(ctx: Context): any { return pathNames; }
        function getOpSymbolMap(ctx: Context): any { return opSymbols; }
        // Catalogs retain authored XML nodes. Normalize their display shape only;
        // registration and installation eligibility remain the AS2 projection's authority.
        function displayConditionList(raw: any): any {
            if (!raw) return null;
            const conditions: any[] = [];
            const nodes = (value: any): any[] => value == null ? [] : Array.isArray(value) ? value : [value];
            for (const leaf of nodes(raw.cond)) {
                if (!leaf || !leaf.op) continue;
                const condition: any = {type:'cond',op:leaf.op,path:leaf.path || ''};
                if (leaf.op === 'range') {
                    condition.min = as2Number(leaf.min); condition.max = as2Number(leaf.max);
                } else if (leaf.op !== 'exists' && leaf.op !== 'missing') {
                    condition.value = leaf.value;
                }
                conditions.push(condition);
            }
            for (const group of nodes(raw.group)) {
                const nested = displayConditionList(group);
                if (nested) { nested.type = 'group'; conditions.push(nested); }
            }
            return conditions.length ? {mode:raw.mode || 'all',conditions} : null;
        }
        function buildInstallConditionText(ctx: Context, condList?: any): any[] {
            var lines: any[] = [];
            if (!condList || !condList.conditions)
                return lines;
            var pathNames: any = getPathNameMap(ctx);
            var opSymbols: any = getOpSymbolMap(ctx);
            var conditions: any[] = condList.conditions;
            for (var i: number = 0; as2Less(i, conditions.length); i++) {
                var cond: any = conditions[i];
                if (!cond)
                    continue;
                if (as2Equal(cond.type, "group")) {
                    var subLines: any[] = buildInstallConditionText(ctx, cond);
                    var modeLabel: string = (as2Equal(cond.mode, "any")) ? "任一满足" : "全部满足";
                    lines.push("<font color='" + TooltipConstants.COL_INSTALL_COND + "'>[" + modeLabel + "]</font>");
                    for (var s: number = 0; as2Less(s, subLines.length); s++) {
                        lines.push("  " + subLines[s]);
                    }
                    continue;
                }
                var line: string;
                if (as2Equal(cond.path, "data.interval")) {
                    var rateValue: number = Math.floor(10000 / as2Number(cond.value)) / 10;
                    line = "射速" + reverseIntervalOp(ctx, cond.op) + rateValue + TooltipConstants.SUF_FIRE_RATE;
                }
                else {
                    var pathLabel: string = pathNames[cond.path] || cond.path;
                    var opSymbol: string = opSymbols[cond.op] || " " + cond.op + " ";
                    if (as2Equal(cond.op, "exists") || as2Equal(cond.op, "missing")) {
                        line = pathLabel + opSymbol;
                    }
                    else if (as2Equal(cond.op, "range")) {
                        line = pathLabel + " ∈ [" + cond.min + ", " + cond.max + "]";
                    }
                    else if (as2Equal(cond.op, "oneOf") || as2Equal(cond.op, "noneOf")) {
                        line = pathLabel + opSymbol + "{" + cond.value + "}";
                    }
                    else {
                        line = pathLabel + opSymbol + mapCondValue(ctx, cond.path, cond.value);
                    }
                }
                lines.push(line);
            }
            return lines;
        }
        function reverseIntervalOp(ctx: Context, op?: string): string {
            if (as2Equal(op, "above"))
                return " &lt; ";
            if (as2Equal(op, "atLeast"))
                return " ≤ ";
            if (as2Equal(op, "below"))
                return " &gt; ";
            if (as2Equal(op, "atMost"))
                return " ≥ ";
            return " = ";
        }
        function mapCondValue(ctx: Context, path?: string, value?: string): string {
            if (as2Equal(path, "data.damagetype") && as2Equal(value, TooltipConstants.TXT_MAGIC)) {
                return "属性";
            }
            return value;
        }
    }
}
