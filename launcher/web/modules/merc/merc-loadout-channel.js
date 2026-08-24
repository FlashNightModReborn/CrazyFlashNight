/**
 * Merc loadout channel port （设计 §5）：loadout_candidates 请求载荷、响应 →
 * picker 候选投影、托管写载荷的纯函数装配。会话/栅栏/传输锁（guardMutation、
 * _loadoutCandidatesSeq、beginOp/endOp、对账锁）全部留在 merc-panel.js；
 * 本层不持有任何可变状态，不发消息、不碰 DOM。
 *
 * 协议形状（AS2 MercLoadoutService.buildCandidates(merc, slot, scope)，二期 §4）：
 * - scope 'slot'（兼容 tab）：逐候选 eligible/lockReason/requirementLevel；
 * - scope 'backpack'（背包 tab）：逐候选 eligibleSlots[数字槽号 6..15]
 *   （空数组 = 全局不兼容仍携带，供置灰）；slot 参数在 backpack 下可缺省；
 * - 非法 scope 由 AS2 fail-closed（invalid_scope）；成功响应带 scope 回声键。
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.MercLoadoutChannel = api;
        root.MercLoadoutChannel = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function text(value, fallback) {
        return String(value == null || value === '' ? fallback || '' : value);
    }

    // picker rovingKey（'armor:6' / 'weapon:13' / 'backpack'）→ AS2 数字槽号字符串
    function slotIdFromKey(key) {
        var parts = String(key || '').split(':');
        if (parts.length < 2) return '';
        var id = String(parts[1]);
        return /^(\d+)$/.test(id) ? id : '';
    }

    function candidateKey(row) {
        var source = row && row.source || {};
        return text(source.containerId, '') + ':' + text(source.slot, '')
            + ':' + text(source.expectedLease, '');
    }

    // 锁定原因映射（等级门基准 = 佣兵自身等级，设计 §2；与一期文案逐字一致）
    function lockText(merc, row) {
        var reason = row && row.lockReason;
        if (reason === 'level_locked') {
            return '需求 Lv.' + (row.requirementLevel || '?')
                + '，超过佣兵等级 Lv.' + (merc ? merc.level : '?');
        }
        if (reason === 'item_incompatible') return '装备与槽位不匹配';
        if (reason) return '该装备当前不可交付';
        return '该装备与全部可写槽位不兼容或等级不足';
    }

    // 候选卡元信息（类型 / 需求等级 / 强化 / 插件；与一期 loadoutCandidateBits 同构）
    function bits(row) {
        var item = row && row.item || {};
        var out = [];
        if (item.weaponType) out.push(item.weaponType);
        else if (item.majorType) out.push(item.majorType);
        if (Number(row && row.requirementLevel) > 0) out.push('需求 Lv.' + Number(row.requirementLevel));
        if (Number(item.enhancementLevel) > 0) out.push('强化 +' + Number(item.enhancementLevel));
        if (Number(item.modSlotUsed) > 0) out.push('插件 ' + Number(item.modSlotUsed));
        return out;
    }

    /**
     * 响应 → picker 候选投影。slot scope：blocked = !eligible（单槽关系）；
     * backpack scope：eligibleSlots 空数组 = 全局不兼容（blocked 置灰携带）。
     * `source` 同时提升到候选顶层（lease-bound 背包格引用，写载荷直接消费）。
     */
    function projectCandidates(merc, data, scope) {
        var rows = data && Array.isArray(data.candidates) ? data.candidates : [];
        var overview = scope === 'backpack';
        var result = [];
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i] || {};
            var item = row.item || {};
            var source = row.source || {};
            var eligibleSlots = Array.isArray(row.eligibleSlots) ? row.eligibleSlots : null;
            var blocked = overview
                ? (eligibleSlots ? eligibleSlots.length === 0 : row.eligible === false)
                : row.eligible === false;
            var blockedReason = blocked ? lockText(merc, row) : '';
            var meta = bits(row);
            result.push({
                key: candidateKey(row),
                name: text(item.displayName || item.displayname || item.name, '未命名候选'),
                type: text(item.weaponType || item.majorType || item.use, '装备候选'),
                delta: overview ? '总览' : '预览',
                summary: blockedReason || meta.join(' · ') || '可预览',
                blockedReason: blockedReason,
                presentation: {
                    displayName: text(item.displayName || item.displayname || item.name, '未知装备'),
                    icon: item.icon || item.name || '',
                    enhancementLevel: Number(item.enhancementLevel) || 0,
                    itemKind: 'equipment',
                    metaLine: meta.join(' · ')
                },
                physicalSlot: Number(source.slot),
                badgeKind: 'preview',
                blocked: blocked,
                source: source,
                raw: row
            });
        }
        return result;
    }

    // loadout_candidates 请求载荷（panel='mercs'；slotKey 在 backpack scope 下为空串，
    // AS2 对 backpack 放宽 slot 校验、slot scope 下非法槽 fail-closed slot_locked）
    function requestPayload(merc, slotId, scope) {
        return {
            mercIndex: merc.slotIndex,
            mercId: merc.id || '',
            slotKey: text(slotId, ''),
            scope: scope === 'backpack' ? 'backpack' : 'slot'
        };
    }

    // 槽位托管态 → 写动词：custody = 替换语义，其余可写态 = 交付；损坏占位 fail-closed
    function operationForState(state) {
        if (state === 'custody') return 'replace';
        if (state === 'custody_corrupt') return '';
        return 'deliver';
    }

    function writeCommand(operation) {
        return operation === 'replace' ? 'loadout_replace'
            : operation === 'withdraw' ? 'loadout_withdraw' : 'loadout_deliver';
    }

    function writePayload(merc, slotId, operation, candidate, revision) {
        var payload = {
            mercIndex: merc.slotIndex,
            mercId: merc.id || '',
            slotKey: text(slotId, ''),
            expectedLoadoutRevision: Number(revision) || 0
        };
        if (operation !== 'withdraw') payload.source = candidate && candidate.source || null;
        return payload;
    }

    // 候选响应携带的权威 revision（拉取时刻），缺失时回落当前投影
    function revisionOf(data, merc) {
        var revision = Number(data && data.loadoutRevision);
        if (!isFinite(revision) || revision < 0) {
            revision = merc && merc.loadout ? Number(merc.loadout.loadoutRevision) || 0 : 0;
        }
        return revision;
    }

    return {
        slotIdFromKey: slotIdFromKey,
        candidateKey: candidateKey,
        lockText: lockText,
        bits: bits,
        projectCandidates: projectCandidates,
        requestPayload: requestPayload,
        operationForState: operationForState,
        writeCommand: writeCommand,
        writePayload: writePayload,
        revisionOf: revisionOf
    };
});
