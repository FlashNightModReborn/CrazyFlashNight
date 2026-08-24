/**
 * Merc loadout drop-policy port （设计 §5）：可写槽 6..15（armor/weapon 两组）、
 * 无药剂分支、跨槽落点由 AS2 二期协议扩建的逐候选 `eligibleSlots` 数字槽号
 * 白名单裁决（`MercLoadoutService.buildCandidates` 两种 scope 均签发）；
 * custody 槽落点 = 替换语义（操作动词由提交侧按槽位托管态解析，策略只管落点）。
 *
 * 纯函数策略，由共享 loadout-picker-drop-policy 工厂参数化产出；DOM / 传输 /
 * 会话永远不进本层。拒绝文案为佣兵托管方言（交付/替换/取回口径）。
 */
(function(root, factory) {
    'use strict';
    var dropPolicy = typeof module !== 'undefined' && module.exports
        ? require('../loadout-picker/loadout-picker-drop-policy.js')
        : root && root.LoadoutPickerDropPolicy;
    var api = factory(dropPolicy);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.MercLoadoutDropPolicy = api;
        root.MercLoadoutDropPolicy = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(DropPolicyModule) {
    'use strict';
    if (!DropPolicyModule || typeof DropPolicyModule.create !== 'function') {
        throw new Error('merc-loadout-drop-policy.js requires LoadoutPickerDropPolicy');
    }

    var TEXTS = {
        write_locked:'正在处理托管写入，当前拖拽已取消。',
        target_blocked:'该槽位当前不可接收托管装备，现有装备保持不变。',
        item_blocked:'该装备当前不可交付（等级不足或全局不兼容），现有装备保持不变。',
        target_mismatch:'该装备与这个槽位不兼容；请拖到高亮的兼容槽位。'
    };

    /**
     * 逐候选跨槽白名单来源：两种 scope 均携带 `eligibleSlots:[6..15]`
     * （数字槽号数组；空数组 = 全局不兼容）。浏览 scope 不再决定拖拽落点。
     */
    function eligibilityOf(candidate) {
        var raw = candidate && candidate.raw;
        var slots = raw && raw.eligibleSlots;
        if (!Array.isArray(slots)) return null;
        var out = [];
        for (var i = 0; i < slots.length; i++) out.push(String(slots[i]));
        return { slots: out, blockedReason: '' };
    }

    function create(overrides) {
        overrides = overrides || {};
        return DropPolicyModule.create({
            equipmentKinds: ['armor', 'weapon'],
            drugKind: '__merc_none__',
            isDrugRow: function() { return false; },
            eligibilityProvider: typeof overrides.eligibilityProvider === 'function'
                ? overrides.eligibilityProvider : eligibilityOf,
            operationId: 'merc.loadout-deliver',
            texts: overrides.texts || TEXTS
        });
    }

    return { create: create, eligibilityOf: eligibilityOf, TEXTS: TEXTS };
});
