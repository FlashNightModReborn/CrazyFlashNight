/** Pure equipment-tuning state, intent and catalog rules. */
(function(root, factory) {
    'use strict';
    var itemFilter = typeof module !== 'undefined' && module.exports
        ? require('./item-filter.js') : root && root.ItemFilter;
    var api = factory(itemFilter);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.EquipmentTuningModel = api;
})(typeof window !== 'undefined' ? window : globalThis, function(ItemFilter) {
    'use strict';

    function wireRef(slot) {
        return {containerId:'背包', slot:Number(slot.physicalSlot != null ? slot.physicalSlot : slot.slot),
            expectedLease:String(slot.slotLease != null ? slot.slotLease : slot.expectedLease)};
    }
    function sameRef(a, b) { return a && b && a.containerId === b.containerId && Number(a.slot) === Number(b.slot); }
    function refKey(ref) {
        return ref ? String(ref.containerId || '') + ':' + Number(ref.slot) + ':' + String(ref.expectedLease || '') : '';
    }

    function quickCommitEligible(preview, intent) {
        var materials = preview && preview.materials instanceof Array ? preview.materials : [];
        var removed = preview && preview.removedMods instanceof Array ? preview.removedMods : [];
        if (intent.operation === 'install_mod') {
            return removed.length === 0 && materials.length === 1
                && materialDeltaEquals(materials[0], intent.candidateName, -1);
        }
        if (intent.operation === 'replace_mod') {
            return removed.length === 1 && removed[0] === intent.replaceCandidateName
                && materials.length === 2
                && hasMaterialDelta(materials, intent.candidateName, -1)
                && hasMaterialDelta(materials, intent.replaceCandidateName, 1);
        }
        if (intent.operation === 'detach_mod') {
            return removed.length === 1 && removed[0] === intent.candidateName
                && materials.length === 1 && materialDeltaEquals(materials[0], intent.candidateName, 1);
        }
        return false;
    }

    function hasMaterialDelta(materials, itemName, delta) {
        for (var i = 0; i < materials.length; i++) {
            if (materialDeltaEquals(materials[i], itemName, delta)) return true;
        }
        return false;
    }

    function materialDeltaEquals(row, itemName, delta) {
        return !!row && String(row.itemName || '') === String(itemName || '')
            && Number(row.delta) === Number(delta);
    }
    function normalizeConversionCandidates(candidates, source, sourceItem) {
        var out = [], seen = {}, sourceUse = String(sourceItem && sourceItem.use || '');
        var sourceLevel = Number(sourceItem && sourceItem.enhancementLevel);
        for (var i = 0; i < candidates.length; i++) {
            var slot = candidates[i], item = slot && slot.item, ref = slot && wireRef(slot);
            if (!slot || !slot.occupied || !item || item.itemKind !== 'equipment' || !ref
                    || sameRef(source, ref) || String(item.use || '') !== sourceUse) continue;
            var targetLevel = Number(item.enhancementLevel);
            if (isFinite(sourceLevel) && isFinite(targetLevel) && sourceLevel === targetLevel) continue;
            var key = refKey(ref);
            if (seen[key]) continue;
            seen[key] = true; out.push(slot);
        }
        return out;
    }

    function previewIntentKey(operation, payload) {
        payload = payload || {};
        if (operation === 'enhance') return 'enhance|' + Math.floor(Number(payload.targetLevel || 0));
        if (operation === 'convert') {
            var target = payload.target || {};
            return 'convert|' + String(target.containerId || '') + '|' + Number(target.slot) + '|'
                + String(target.expectedLease || '');
        }
        return String(operation || '') + '|' + String(payload.candidateKey || '')
            + '|' + String(payload.replaceCandidateKey || '');
    }
    function isOperation(value) { return /^(enhance|convert|install_tier|install_mod|replace_mod|detach_mod|detach_all_mods)$/.test(value); }
    function isOperationGroup(value) { return /^(enhance|convert|install_tier|install_mod)$/.test(value); }
    function nextEnhancementLevel(snapshot) {
        var enhance = snapshot && snapshot.enhance || {};
        var current = Number(enhance.currentLevel || snapshot.equipment && snapshot.equipment.level || 0);
        var max = Math.min(enhancementAvailableMax(snapshot), enhancementHardMax(snapshot));
        return Math.min(max, current + 1);
    }
    function operationLabel(value) {
        var labels = {enhance:'强化预览',convert:'强化度转换',install_tier:'装备进阶',install_mod:'安装配件',
            replace_mod:'替换配件',detach_mod:'卸下配件',detach_all_mods:'卸下全部配件'};
        return labels[value] || '调制预览';
    }
    function errorMessage(error) {
        var labels = {invalid_payload:'请求字段无效。',stale_state:'装备或材料状态已变化，请重新选择。',
            material_missing:'材料不足。',insufficient_material:'材料不足。',target_invalid:'转换目标无效。',
            invalid_target:'转换目标无效。',same_slot:'不能选择同一件装备。',
            type_mismatch:'只能在相同类型装备之间转换。',different_use:'只能在相同类型装备之间转换。',
            level_cap:'已达到当前强化上限。',tier_locked:'进阶顺序尚未满足。',invalid_transition:'进阶顺序尚未满足。',
            mod_unavailable:'该配件当前不可安装。',mod_not_installed:'目标配件已不在装备上。',busy:'Flash 正在处理另一项调制。',
            invalid_equipment:'该物品不能调制。',invalid_mods:'装备的配件数据无效。',unknown_candidate:'候选项已失效，请刷新。',
            token_invalid:'调制预览已失效，请重新预览。',token_expired:'调制预览已过期，请重新预览。',
            view_session_expired:'调制会话已失效，请重新进入。',commit_failed:'调制提交失败，未写入存档。',
            timeout:'调制响应超时。',client_timeout:'调制响应超时。',disconnected:'连接已断开。',not_sent:'请求未送达 Flash。',
            malformed_response:'Flash 回包不完整。',reconcile_required:'上次提交结果需要重新对账。',
            inventory_projection_failed:'同类装备读取失败，请重试。',
            inventory_projection_unavailable:'当前无法读取同类装备。'};
        return labels[error] || '调制操作失败，请重试。';
    }

    function candidateForItem(candidates, itemName) {
        candidates = candidates || [];
        for (var i = 0; i < candidates.length; i++) {
            if (String(candidates[i] && candidates[i].itemName || '') === String(itemName || '')) {
                return candidates[i];
            }
        }
        return null;
    }
    function candidateForTier(candidates, tierName) {
        candidates = candidates || [];
        for (var i = 0; i < candidates.length; i++) {
            if (String(candidates[i] && candidates[i].tierName || '') === String(tierName || '')) {
                return candidates[i];
            }
        }
        return null;
    }
    function exactQuantity(value) {
        if (typeof InventoryUI !== 'undefined' && InventoryUI.exactQuantity) return InventoryUI.exactQuantity(value);
        return String(Math.max(0, Math.floor(Number(value) || 0))).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }
    function materialCount(materials, itemName) {
        if (materials instanceof Array) {
            for (var i = 0; i < materials.length; i++) {
                if (String(materials[i] && materials[i].itemName || '') === String(itemName || '')) {
                    return Math.max(0, Math.floor(Number(materials[i].count) || 0));
                }
            }
            return 0;
        }
        return Math.max(0, Math.floor(Number(materials && materials[itemName]) || 0));
    }
    function materialDeltaFor(materials, itemName) {
        materials = materials || [];
        for (var i = 0; i < materials.length; i++) {
            if (String(materials[i] && materials[i].itemName || '') === String(itemName || '')) {
                return materials[i];
            }
        }
        return null;
    }
    function enhancementAvailableMax(snapshot) {
        var enhance = snapshot && snapshot.enhance || {};
        var current = Number(enhance.currentLevel || snapshot && snapshot.equipment && snapshot.equipment.level || 0);
        return Number(enhance.availableMaxLevel != null ? enhance.availableMaxLevel
            : (enhance.maxLevel != null ? enhance.maxLevel : current));
    }
    function enhancementHardMax(snapshot) {
        var enhance = snapshot && snapshot.enhance || {};
        var equipment = snapshot && snapshot.equipment || {};
        var available = enhancementAvailableMax(snapshot);
        return Number(enhance.hardMaxLevel != null ? enhance.hardMaxLevel
            : (equipment.hardMaxLevel != null ? equipment.hardMaxLevel : available));
    }
    function candidateInstalled(candidates, candidateKey) {
        candidates = candidates || [];
        for (var i = 0; i < candidates.length; i++) {
            if (String(candidates[i] && candidates[i].candidateKey || '') === String(candidateKey || '')) {
                return candidates[i].installed === true;
            }
        }
        return false;
    }
    function compactQuantity(value) {
        if (typeof InventoryUI !== 'undefined' && InventoryUI.compactQuantity) return InventoryUI.compactQuantity(value);
        var quantity = Math.max(0, Math.floor(Number(value) || 0));
        if (quantity < 10000) return String(quantity);
        var unitValue = quantity >= 100000000 ? 100000000 : 10000;
        var scaled = quantity / unitValue;
        var compact = scaled < 10 ? Math.floor(scaled * 10) / 10 : Math.floor(scaled);
        return String(compact).replace(/\.0$/, '') + (unitValue === 100000000 ? '亿' : '万');
    }
    function modStatus(candidate) {
        if (candidate && candidate.available === true) return {id:'available', label:'可安装', order:0};
        var reason = String(candidate && candidate.reason || '');
        if (reason === 'material_missing' || reason === '材料不足') return {id:'material_missing', label:'材料不足', order:1};
        return {id:'blocked', label:'条件不符', order:2};
    }
    function normalizeModSymbol(value) {
        value = String(value || 'diamond-outline');
        return /^(triangle|square|circle|diamond|star)-(solid|outline)$/.test(value)
            ? value : 'diamond-outline';
    }
    function modSegment(candidate, field, labelField, fallbackId, fallbackLabel, order) {
        var id = String(candidate && candidate[field] || fallbackId);
        return {id:id, label:String(candidate && candidate[labelField] || fallbackLabel), order:Number(order) || 0};
    }
    function buildModFilterTree(candidates) {
        candidates = candidates || [];
        var gradeOrder = {low:0, medium:1, high:2, special:3, unknown:9};
        return ItemFilter.branchTree([
            {id:'grade', label:'档级', tree:ItemFilter.build(candidates, function(candidate) {
                var value = modSegment(candidate, 'grade', 'gradeLabel', 'unknown', '未知档级', gradeOrder[String(candidate.grade || 'unknown')]);
                return [value];
            })},
            {id:'scope', label:'用途', tree:ItemFilter.build(candidates, function(candidate) {
                return [modSegment(candidate, 'scope', 'scopeLabel', 'unknown', '未分类', 0)];
            })},
            {id:'role', label:'定位', tree:ItemFilter.build(candidates, function(candidate) {
                return [modSegment(candidate, 'role', 'roleLabel', 'utility', '结构与功能', 0)];
            })},
            {id:'status', label:'状态', tree:ItemFilter.build(candidates, function(candidate) { return [modStatus(candidate)]; })}
        ], candidates.length);
    }
    function modMatchesFilter(candidate, path) {
        path = path || [];
        if (path.length < 2) return true;
        var value = String(path[1]);
        if (path[0] === 'grade') return String(candidate.grade || 'unknown') === value;
        if (path[0] === 'scope') return String(candidate.scope || 'unknown') === value;
        if (path[0] === 'role') return String(candidate.role || 'utility') === value;
        if (path[0] === 'status') return modStatus(candidate).id === value;
        return true;
    }
    function commitLabel(preview) {
        preview = preview || {};
        if (preview.operation !== 'enhance') {
            var labels = {convert:'互换强化度', install_tier:'确认进阶', install_mod:'安装配件',
                replace_mod:'替换配件', detach_mod:'卸下配件', detach_all_mods:'卸下全部配件'};
            return labels[preview.operation] || '确认调制';
        }
        var after = preview.after && preview.after.source && preview.after.source.equipment;
        var target = after ? Number(after.level || 0) : 0;
        var cost = 0, materials = preview.materials || [];
        for (var i = 0; i < materials.length; i++) {
            if (String(materials[i].itemName || '') === '强化石') cost += Math.max(0, -Number(materials[i].delta || 0));
        }
        return '强化至 +' + target + (cost > 0 ? ' · ' + cost + ' 强化石' : '');
    }

    function equipmentDiff(left, right) {
        var parts = [];
        var levelBefore = Number(left.level || 0), levelAfter = Number(right.level || 0);
        if (levelBefore !== levelAfter) parts.push('+' + levelBefore + ' → +' + levelAfter);
        if (left.tier !== right.tier) parts.push((left.tier || '—') + ' → ' + (right.tier || '—'));
        var beforeMods = left.mods || [];
        var afterMods = right.mods || [];
        var removed = beforeMods.filter(function(m) { return afterMods.indexOf(m) < 0; });
        var added = afterMods.filter(function(m) { return beforeMods.indexOf(m) < 0; });
        if (removed.length) parts.push('卸下 ' + removed.join('、'));
        if (added.length) parts.push('安装 ' + added.join('、'));
        return parts.join(' · ');
    }

    return {
        wireRef:wireRef,
        sameRef:sameRef,
        refKey:refKey,
        quickCommitEligible:quickCommitEligible,
        hasMaterialDelta:hasMaterialDelta,
        materialDeltaEquals:materialDeltaEquals,
        normalizeConversionCandidates:normalizeConversionCandidates,
        previewIntentKey:previewIntentKey,
        isOperation:isOperation,
        isOperationGroup:isOperationGroup,
        nextEnhancementLevel:nextEnhancementLevel,
        operationLabel:operationLabel,
        errorMessage:errorMessage,
        candidateForItem:candidateForItem,
        candidateForTier:candidateForTier,
        exactQuantity:exactQuantity,
        materialCount:materialCount,
        materialDeltaFor:materialDeltaFor,
        enhancementAvailableMax:enhancementAvailableMax,
        enhancementHardMax:enhancementHardMax,
        candidateInstalled:candidateInstalled,
        compactQuantity:compactQuantity,
        modStatus:modStatus,
        normalizeModSymbol:normalizeModSymbol,
        buildModFilterTree:buildModFilterTree,
        modMatchesFilter:modMatchesFilter,
        commitLabel:commitLabel,
        equipmentDiff:equipmentDiff
    };
});

