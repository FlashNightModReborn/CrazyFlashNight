namespace TooltipEngine {
    const emptyMap = Object.freeze(Object.create(null));
    const emptyArray: any[] = Object.freeze([]) as any;
    let activeCatalog: TooltipCatalog;

    function isMap(value: any): value is Data {
        return value !== null && typeof value === 'object' && !Array.isArray(value);
    }
    function validateCatalog(value: any): asserts value is TooltipCatalog {
        if (!isMap(value) || value.version !== 1 || typeof value.contentVersion !== 'string'
                || !value.contentVersion || value.contentVersion.length > 128) throw new InputError('invalid_catalog_version');
        for (const field of ['items', 'mods', 'recipes', 'recipesUsing', 'magicDamageTypes']) {
            if (!isMap(value[field])) throw new InputError('invalid_catalog_' + field);
        }
        if (!isMap(value.levelStatList) && !Array.isArray(value.levelStatList)) throw new InputError('invalid_catalog_levels');
    }
    /** Own-property validation is shared by direct Node callers and the ClearScript entry. */
    function validateTree(value: any, maxNodes: number, maxDepth: number): void {
        const stack: { value: any; depth: number; exit?: boolean }[] = [{ value, depth: 0 }];
        let nodes = 0;
        const seen = new Set<any>();
        while (stack.length) {
            const entry = stack.pop()!;
            if (entry.exit) { seen.delete(entry.value); continue; }
            if (++nodes > maxNodes || entry.depth > maxDepth) throw new InputError('input_too_large');
            const current = entry.value;
            if (typeof current === 'function' || typeof current === 'symbol' || typeof current === 'bigint') throw new InputError('invalid_input_value');
            if (typeof current === 'string' && current.length > 131072) throw new InputError('input_string_too_large');
            if (!current || typeof current !== 'object') continue;
            if (seen.has(current)) throw new InputError('cyclic_input');
            seen.add(current);
            stack.push({ value: current, depth: entry.depth, exit: true });
            for (const key of Object.keys(current)) {
                if (key === '__proto__' || key === 'prototype' || key === 'constructor') throw new InputError('invalid_input_key');
                stack.push({ value: current[key], depth: entry.depth + 1 });
            }
        }
    }
    function freezeTree(value: any): void {
        if (!value || typeof value !== 'object' || Object.isFrozen(value)) return;
        for (const key of Object.keys(value)) freezeTree(value[key]);
        Object.freeze(value);
    }
    /** The sole state is a validated, immutable static catalog, replaced atomically on init. */
    export function initCatalog(json: string): string {
        if (typeof json !== 'string' || json.length > 32 * 1024 * 1024) throw new InputError('invalid_catalog_json');
        const candidate = JSON.parse(json);
        validateCatalog(candidate);
        validateTree(candidate, 1000000, 48);
        freezeTree(candidate);
        activeCatalog = candidate;
        return candidate.contentVersion;
    }
    /** Restore only the restricted AS2 numeric transport markers, never executable values. */
    function decodeTransport(value: any): any {
        if (!value || typeof value !== 'object') return value;
        const keys = Object.keys(value);
        if (Object.prototype.hasOwnProperty.call(value, '__tooltipNumber')) {
            if (keys.length !== 1) throw new InputError('invalid_number_marker');
            if (value.__tooltipNumber === 'NaN') return NaN;
            if (value.__tooltipNumber === 'Infinity') return Infinity;
            if (value.__tooltipNumber === '-Infinity') return -Infinity;
            throw new InputError('invalid_number_marker');
        }
        if (Object.prototype.hasOwnProperty.call(value, '__tooltipUndefined')) {
            if (keys.length !== 1 || value.__tooltipUndefined !== true) throw new InputError('invalid_undefined_marker');
            return undefined;
        }
        const result: any = Array.isArray(value) ? new Array(value.length) : {};
        for (const key of keys) result[key] = decodeTransport(value[key]);
        return result;
    }
    function validateInput(input: TooltipInput): void {
        if (!isMap(input) || input.version !== 1) throw new InputError('invalid_input_version');
        validateTree(input, 8192, 24);
        if (!['item', 'skill', 'body', 'hud'].includes(input.kind)) throw new InputError('invalid_input_kind');
        if (input.presentation != null && !['native', 'inventory', 'web'].includes(input.presentation)) throw new InputError('invalid_presentation');
        if (input.output != null && input.output !== 'details') throw new InputError('invalid_output');
        if (input.kind !== 'item') return;
        if (typeof input.itemName !== 'string' || !input.itemName || input.itemName.length > 512) throw new InputError('invalid_item_name');
        const p = input.projection;
        if (!isMap(p)) throw new InputError('missing_projection');
        for (const field of ['isEquipment', 'isMaterial', 'isInformation']) {
            if (typeof (p as Data)[field] !== 'boolean') throw new InputError('missing_classification');
        }
        for (const field of ['tierOptions', 'drugEffects', 'obtainRecords']) {
            if (!Array.isArray((p as Data)[field])) throw new InputError('missing_' + field);
        }
        if (!isMap(p.mods)) throw new InputError('missing_mods');
        if (p.isMaterial && p.registeredModName !== null && typeof p.registeredModName !== 'string') throw new InputError('missing_registered_mod');
        for (const name of Object.keys(p.mods)) {
            const mod = p.mods[name];
            if (!isMap(mod) || typeof mod.present !== 'boolean' || !Array.isArray(mod.useCases)
                    || !Array.isArray(mod.bulletCases)) throw new InputError('invalid_mod_projection');
        }
        if (p.isEquipment && !isMap(p.baselineData)) throw new InputError('missing_baseline_data');
        if (p.calculated != null && !isMap(p.calculated)) throw new InputError('invalid_calculated_data');
    }
    function contextFor(input: TooltipInput, catalog: TooltipCatalog): Context {
        const decoded: TooltipInput = decodeTransport(input);
        const projected = decoded.projection || {
            isEquipment: false, isMaterial: false, isInformation: false,
            tierOptions: emptyArray, drugEffects: emptyArray, mods: emptyMap, obtainRecords: emptyArray
        };
        return { input: decoded, catalog, projection: projected };
    }
    function result(document: TooltipDocument, introHTML: string, descHTML: string, detailsHTML?: string): TooltipResult {
        return { document, introHTML, descHTML,
            details: plainText(detailsHTML === undefined ? introHTML + descHTML : detailsHTML).substr(0, 4096) };
    }
    function itemResult(ctx: Context): TooltipResult {
        const input = ctx.input;
        const item = lookupItem(ctx, input.itemName!);
        if (!item) throw new InputError('item_data_missing');
        // The legacy stats branch also accepts non-equipment items with data
        // (e.g. battlefield supplies). AS2 projects the same selector result.
        if (item.data && item.use !== ItemUseTypes.POTION && !isMap(ctx.projection.baselineData)) {
            throw new InputError('missing_baseline_data');
        }
        const calculated = ctx.projection.calculated;
        const base: Instance = calculated == null ? null : {
            name: input.itemName!, value: input.value == null ? { level: 1 } : input.value,
            getData: () => calculated
        };
        const value = input.value == null ? { level: 1 } : input.value;
        const iconData: Data = { ...calculated };
        if (ctx.projection.displayName !== undefined) iconData.displayname = ctx.projection.displayName;
        if (ctx.projection.iconName !== undefined) iconData.icon = ctx.projection.iconName;
        const fullDesc = TooltipComposer.generateItemDescriptionText(ctx, item, base);
        const fullIntro = TooltipComposer.generateIntroPanelContent(ctx, base, item, value);

        if (input.hud?.kind === 'drug') {
            let intro = fullIntro;
            const hud = input.hud;
            if (Math.floor(hud.count) === 1 && intro.indexOf('数量：') < 0) intro += '数量：1<BR>';
            const lane = hud.slot % 4;
            intro += '快捷栏：' + (hud.slot < 4 ? 'A' : 'B') + '组' + (lane + 1) + '号格';
            if (hud.key) intro += '（快捷键：' + hud.key + '）';
            intro += '<BR>';
            return result(NativeTooltipDocument.buildItem(input.itemName, item, iconData, intro, fullDesc), intro, fullDesc);
        }
        const subBlocks: any[] = [], docSubs: any[] = [];
        const desc = TooltipComposer.generateItemDescriptionTextEx(ctx, item, base, subBlocks, docSubs);
        const rail = TooltipComposer.getRailText(ctx, item, base);
        const magazine = TooltipComposer.getMagazineInfo(ctx, base, item, value);
        const upgrades = TooltipComposer.getUpgradePathInfo(ctx, item, base);
        const critSlay: any[] = [], buffs: any[] = [];
        // Web preview originally rebuilds equipment intro and potion buffs only.
        // Consumable grenades can have crit metadata; their Web intro stays inline.
        const splitEquipmentParts = input.presentation !== 'web' || ctx.projection.isEquipment;
        const intro = TooltipComposer.generateIntroPanelContent(ctx, base, item, value, {
            omitTypeLines: splitEquipmentParts && rail != null, omitActionType: splitEquipmentParts && rail != null,
            omitClipName: splitEquipmentParts && magazine != null, omitBulletType: splitEquipmentParts && magazine?.ammo != null,
            omitCritSlay: splitEquipmentParts, critSlay, omitBuff: input.presentation !== 'inventory', buff: buffs
        });
        if (buffs.length) { docSubs.unshift(buffs.join('')); subBlocks.unshift(buffs.join('')); }
        if (critSlay.length) { docSubs.unshift(critSlay.join('')); subBlocks.unshift(critSlay.join('')); }
        const document = NativeTooltipDocument.buildItem(input.itemName, item, iconData, intro, desc, docSubs,
            { rail: splitEquipmentParts ? rail : null, magazine: splitEquipmentParts ? magazine : null, upgrades });
        // ChoiceReward historically reads full intro + inline description. Web's
        // compatibility HTML reorders subpanels and may repeat crit/buff lines;
        // those delivery fragments must never redefine reward details.
        return result(document, fullIntro, input.presentation === 'web' ? desc + subBlocks.join('') : fullDesc,
            fullIntro + fullDesc);
    }
    export function resourceHintHtml(hint: any): string {
        if (!hint || hint.state === 'ready' || hint.state === 'unknown') return '';
        const resource = hint.reason === 'mp' ? 'MP' : '消耗品';
        return hint.state === 'blocked'
            ? "<BR><FONT COLOR='#e87864'>" + resource + '不足，无法释放</FONT>'
            : "<BR><FONT COLOR='#e8a080'>当前" + resource + '仅够再释放一次</FONT>';
    }
    function skillResult(input: TooltipInput): TooltipResult {
        if (!isMap(input.skillData) || typeof input.skillName !== 'string') throw new InputError('invalid_skill_input');
        const skill = input.skillData;
        const state = input.state || {};
        let intro = '<B>' + as2String(skill.Name) + '</B><BR>' + as2String(skill.Type);
        if (input.mode === 'learn') {
            intro += '<BR>最高等级：' + as2String(skill.MaxLevel);
            intro += '<BR>解锁需要技能点数：' + as2String(skill.UnlockSP);
            if (skill.MaxLevel > 1) intro += '<BR>升级需要技能点数：' + as2String(skill.UpgradeSP);
        } else {
            const label = skill.Equippable ? (state.equipped === true ? '已装备' : '未装备')
                : (state.enabled === true ? '已启用' : '未启用');
            const active = skill.Equippable ? state.equipped === true : state.enabled === true;
            intro += "   <FONT COLOR='" + (active ? TooltipConstants.COL_HP : '#FFDDDD') + "'>" + label + '</FONT>';
        }
        intro += '<BR>冷却秒数：' + Math.floor(as2Number(skill.CD) / 100) / 10;
        intro += '<BR>MP消耗：' + as2String(skill.MP);
        intro += input.mode === 'learn' ? '<BR>等级限制：' + as2String(skill.UnlockLevel) : '<BR>技能等级：' + as2String(state.level);
        intro += resourceHintHtml(input.resourceHint);
        const desc = skill.Description ? as2String(skill.Description) : '';
        return result(NativeTooltipDocument.buildSkill(input.skillName, intro, desc), intro, desc);
    }
    /** Synchronous deterministic content engine. It never reads a host object, clock, I/O or shared request state. */
    export function buildProjection(input: TooltipInput, catalog: TooltipCatalog): TooltipResult {
        validateCatalog(catalog);
        validateInput(input);
        const ctx = contextFor(input, catalog);
        input = ctx.input;
        switch (input.kind) {
            case 'item': return itemResult(ctx);
            case 'skill': return skillResult(input);
            case 'body': {
                if (input.html != null && typeof input.html !== 'string') throw new InputError('invalid_text_input');
                const html = input.html || '';
                return result(NativeTooltipDocument.buildBody(html, input.profile || 'simple'), '', html);
            }
            case 'hud': return buildHudResult(input);

        }
    }
    export function buildTooltip(input: TooltipInput, catalog: TooltipCatalog): TooltipDocument {
        return buildProjection(input, catalog).document;
    }
    function readInput(json: string): TooltipInput {
        if (!activeCatalog) throw new InputError('catalog_not_initialized');
        if (typeof json !== 'string' || json.length > 256 * 1024) throw new InputError('input_too_large');
        return JSON.parse(json);
    }
    export function buildJson(inputJson: string): string {
        return JSON.stringify(buildTooltip(readInput(inputJson), activeCatalog));
    }
    export function buildProjectionJson(inputJson: string): string {
        const input = readInput(inputJson);
        const built = buildProjection(input, activeCatalog);
        return JSON.stringify(input.output === 'details' ? { details: built.details } : built);
    }
    export function htmlToRuns(html: string): any[] { return NativeTooltipDocument.htmlToRuns(html); }
}
