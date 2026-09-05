import { getCardDefinition, isCommanderCard } from '../data/cards.js';
import { PROMOTIONS } from '../data/config.js';
import { DEMO_1_ORGANIZATION } from '../data/organization.js';
import { isFactionDefeated, relationBetween, requireFaction } from './factions.js';
import { commandElementFormationProfileIds, commandElementMetrics, commandElementsAtNode, nodeDeploymentSize, prefixMembersWithinDeployment, selectedCommandElements, selectionOrganizationMetrics, } from './organization.js';
import { nodeIsAdjacent, nodeOccupyingFactions, isNodeActive, isNodeStable } from './selectors.js';
function fail(reasonCode, error, reasonParams = {}) {
    return { ok: false, reasonCode, reasonParams, error };
}
function validateMove(state, command) {
    if (state.phase !== 'FIRST_FACTION_ACTION' && state.phase !== 'SECOND_FACTION_ACTION') {
        return fail('action_phase_required', '当前不是行动阶段。');
    }
    if (state.activeFactionId !== command.factionId)
        return fail('active_faction_mismatch', '当前不是该阵营的行动时机。');
    const originNode = state.map.nodes[command.originNodeId];
    const targetNode = state.map.nodes[command.targetNodeId];
    if (!originNode || !targetNode) {
        return fail('node_unknown', '地图节点不存在。', {
            originNodeId: command.originNodeId,
            targetNodeId: command.targetNodeId,
        });
    }
    if (command.originNodeId === command.targetNodeId)
        return fail('origin_equals_target', '起点与目标节点不能相同。');
    const viaNode = command.viaNodeId ? state.map.nodes[command.viaNodeId] : null;
    if (command.viaNodeId) {
        if (!viaNode || command.viaNodeId === command.originNodeId || command.viaNodeId === command.targetNodeId) {
            return fail('allied_transit_invalid', '盟军过境路径无效。');
        }
        if (!nodeIsAdjacent(state, command.originNodeId, command.viaNodeId)
            || !nodeIsAdjacent(state, command.viaNodeId, command.targetNodeId)) {
            return fail('target_not_adjacent', '盟军过境的两段路径必须分别相邻。');
        }
        const viaOccupiers = nodeOccupyingFactions(state, command.viaNodeId);
        if (viaOccupiers.length !== 1
            || viaOccupiers[0] === command.factionId
            || relationBetween(state, command.factionId, viaOccupiers[0] ?? command.factionId) !== 'allied') {
            return fail('allied_transit_invalid', '中间据点必须由盟军单独驻守。');
        }
    }
    else if (!nodeIsAdjacent(state, command.originNodeId, command.targetNodeId)) {
        return fail('target_not_adjacent', '目标节点与起点不相邻。');
    }
    if (command.pieceIds.length === 0)
        return fail('selection_empty', '至少选择一枚棋子。');
    if (new Set(command.pieceIds).size !== command.pieceIds.length)
        return fail('selection_duplicate', '棋子列表包含重复项。');
    for (const pieceId of command.pieceIds) {
        const piece = state.pieces[pieceId];
        if (!piece || piece.hp <= 0)
            return fail('piece_unavailable', `棋子 ${pieceId} 不存在或已阵亡。`);
        if (piece.factionId !== command.factionId)
            return fail('piece_wrong_faction', `棋子 ${pieceId} 不属于当前阵营。`);
        if (piece.nodeId !== command.originNodeId)
            return fail('piece_wrong_origin', `棋子 ${pieceId} 不在起点节点。`);
    }
    const selectedElements = selectedCommandElements(state, command.pieceIds);
    if (!selectedElements.complete || selectedElements.elements.length === 0) {
        return fail('command_element_partial_selection', '任务编组必须作为完整指挥单位行动；请先拆分。');
    }
    const requestedMetrics = selectionOrganizationMetrics(state, command.pieceIds);
    const occupiers = nodeOccupyingFactions(state, command.targetNodeId);
    const foreign = occupiers.filter((factionId) => factionId !== command.factionId);
    const allies = occupiers.filter((factionId) => factionId === command.factionId);
    if (foreign.length > 0 && allies.length > 0)
        return fail('mixed_garrison_state', '节点存在混合阵营驻军，状态非法。');
    if (foreign.length > 1)
        return fail('hostile_garrison_ambiguous', '目标据点存在多个战略阵营，无法进入二方交战。');
    const targetFactionId = foreign[0];
    const targetRelation = targetFactionId
        ? relationBetween(state, command.factionId, targetFactionId)
        : null;
    if (targetRelation === 'allied')
        return fail('allied_destination_forbidden', '可以经过盟军据点，但不能在盟军驻地结束行动。');
    if (targetRelation === 'neutral')
        return fail('neutral_attack_forbidden', '中立阵营尚未进入敌对关系，不能发起攻击。');
    const isBattle = targetRelation === 'hostile';
    if (command.viaNodeId && (isBattle || targetFactionId !== undefined)) {
        return fail('allied_transit_invalid', '盟军过境只能结束在己方或无驻军据点。');
    }
    if (isBattle) {
        const node = targetNode;
        const attackerFormationIds = commandElementFormationProfileIds(selectedElements.elements);
        if (attackerFormationIds.length !== 1) {
            return fail('formation_mix_unsupported', '进攻方参战指挥单位必须采用同一阵型。', {
                side: 'attacker',
                nodeId: command.originNodeId,
                formationProfileIds: attackerFormationIds.join(','),
            });
        }
        const defenderElements = commandElementsAtNode(state, command.targetNodeId, targetFactionId);
        const defenderFormationIds = commandElementFormationProfileIds(defenderElements);
        if (defenderFormationIds.length !== 1) {
            return fail('formation_mix_unsupported', '目标守军指挥单位必须采用同一阵型。', {
                side: 'defender',
                nodeId: command.targetNodeId,
                formationProfileIds: defenderFormationIds.join(','),
            });
        }
        if (requestedMetrics.deploymentSize > node.attackWidth) {
            return fail('attack_width_exceeded', `进攻宽度为 ${node.attackWidth}，当前投入规模 ${requestedMetrics.deploymentSize}。`, { maximum: node.attackWidth, selected: requestedMetrics.deploymentSize });
        }
        for (const pieceId of command.pieceIds) {
            const piece = state.pieces[pieceId];
            if (piece?.failedAssaultLocks.includes(command.targetNodeId)) {
                return fail('assault_reentry_locked', `${pieceId} 本战略回合已进攻该节点失败，不能立即重入。`);
            }
        }
        const requiredAp = requestedMetrics.commandLoad;
        const faction = requireFaction(state, command.factionId);
        if (faction.actionPoints < requiredAp) {
            return fail('action_points_insufficient', `公共 AP 不足，需要 ${requiredAp}。`, { required: requiredAp, available: faction.actionPoints });
        }
        return {
            ok: true,
            actualPieceIds: [...command.pieceIds],
            isBattle: true,
            commandLoad: requiredAp,
            deploymentSize: requestedMetrics.deploymentSize,
            encounterCost: requestedMetrics.encounterCost,
            defenderFactionId: targetFactionId,
        };
    }
    const node = targetNode;
    const available = Math.max(0, node.capacity - nodeDeploymentSize(state, command.targetNodeId));
    const actualPieceIds = prefixMembersWithinDeployment(state, command.pieceIds, available);
    if (actualPieceIds.length === 0)
        return fail('garrison_capacity_full', `${node.displayName}已达到驻军容量。`, { nodeName: node.displayName, maximum: node.capacity });
    const actualMetrics = selectionOrganizationMetrics(state, actualPieceIds);
    const requiredAp = actualMetrics.commandLoad * (command.viaNodeId ? 2 : 1);
    const faction = requireFaction(state, command.factionId);
    if (faction.actionPoints < requiredAp) {
        return fail('action_points_insufficient', `公共 AP 不足，需要 ${requiredAp}。`, { required: requiredAp, available: faction.actionPoints });
    }
    return {
        ok: true,
        actualPieceIds,
        isBattle: false,
        commandLoad: requiredAp,
        deploymentSize: actualMetrics.deploymentSize,
        encounterCost: actualMetrics.encounterCost,
    };
}
function validateReorganizationAuthority(state, command) {
    if (state.phase !== 'FIRST_FACTION_ACTION' && state.phase !== 'SECOND_FACTION_ACTION') {
        return fail('action_phase_required', '当前不是行动阶段。');
    }
    if (state.activeFactionId !== command.factionId) {
        return fail('active_faction_mismatch', '当前不是该阵营的行动时机。');
    }
    if (!state.map.nodes[command.nodeId]) {
        return fail('node_unknown', '地图节点不存在。', { nodeId: command.nodeId });
    }
    return null;
}
function validateMergeTaskGroup(state, command) {
    const authority = validateReorganizationAuthority(state, command);
    if (authority)
        return authority;
    if (command.commandElementIds.length < 2
        || new Set(command.commandElementIds).size !== command.commandElementIds.length) {
        return fail('reorganization_selection_invalid', '至少选择两个互不重复的指挥单位。');
    }
    const elements = command.commandElementIds.map((elementId) => (state.organization.commandElements[elementId]));
    if (elements.some((element) => !element)) {
        return fail('reorganization_selection_invalid', '所选指挥单位已经失效。');
    }
    const present = elements.filter((element) => element !== undefined);
    if (present.some((element) => element.factionId !== command.factionId)) {
        return fail('reorganization_selection_invalid', '不能合并其他阵营的指挥单位。');
    }
    if (present.some((element) => element.nodeId !== command.nodeId)) {
        return fail('reorganization_wrong_node', '只能合并同一据点内的指挥单位。');
    }
    const template = DEMO_1_ORGANIZATION.taskGroupTemplates.find((entry) => (entry.id === command.taskGroupTemplateId));
    if (!template)
        return fail('task_group_template_mismatch', '当前组合没有可用的编制模板。');
    const memberCount = present.reduce((sum, element) => sum + element.memberIds.length, 0);
    if (memberCount < template.minimumMembers || memberCount > template.maximumMembers) {
        return fail('task_group_template_mismatch', '所选成员数量不符合编制模板。', {
            minimum: template.minimumMembers,
            maximum: template.maximumMembers,
            selected: memberCount,
        });
    }
    if (!template.formationProfileRefs.some((profileId) => profileId === command.formationProfileId)) {
        return fail('formation_unknown', '所选阵型不适用于该任务编组。');
    }
    return { ok: true };
}
function validateSplitTaskGroup(state, command) {
    const authority = validateReorganizationAuthority(state, command);
    if (authority)
        return authority;
    const element = state.organization.commandElements[command.commandElementId];
    if (!element || element.kind !== 'task_group') {
        return fail('reorganization_selection_invalid', '所选对象不是可拆分的任务编组。');
    }
    if (element.factionId !== command.factionId) {
        return fail('reorganization_selection_invalid', '不能拆分其他阵营的任务编组。');
    }
    if (element.nodeId !== command.nodeId) {
        return fail('reorganization_wrong_node', '只能在任务编组当前所在据点拆分。');
    }
    if (command.memberIds.length === 0 || new Set(command.memberIds).size !== command.memberIds.length) {
        return fail('reorganization_selection_invalid', '至少选择一个互不重复的成员。');
    }
    if (command.memberIds.some((memberId) => !element.memberIds.includes(memberId))) {
        return fail('reorganization_selection_invalid', '所选成员不属于该任务编组。');
    }
    return { ok: true };
}
function validateSetFormation(state, command) {
    const authority = validateReorganizationAuthority(state, command);
    if (authority)
        return authority;
    const element = state.organization.commandElements[command.commandElementId];
    if (!element || element.factionId !== command.factionId) {
        return fail('reorganization_selection_invalid', '所选指挥单位已经失效。');
    }
    if (element.nodeId !== command.nodeId) {
        return fail('reorganization_wrong_node', '只能调整当前据点内的阵型。');
    }
    const profile = DEMO_1_ORGANIZATION.formationProfiles.find((entry) => (entry.id === command.formationProfileId));
    if (!profile)
        return fail('formation_unknown', '所选阵型不存在。');
    if (element.taskGroupTemplateId) {
        const template = DEMO_1_ORGANIZATION.taskGroupTemplates.find((entry) => (entry.id === element.taskGroupTemplateId));
        if (!template?.formationProfileRefs.some((profileId) => profileId === command.formationProfileId)) {
            return fail('formation_unknown', '所选阵型不适用于该任务编组。');
        }
    }
    if (element.formationProfileId === command.formationProfileId) {
        return fail('reorganization_selection_invalid', '该部队已经采用所选阵型，无需重复调整。', {
            commandElementId: command.commandElementId,
            formationProfileId: command.formationProfileId,
        });
    }
    return { ok: true };
}
export function validateCommand(state, command) {
    if (state.phase === 'GAME_OVER')
        return fail('game_over', '对局已经结束。');
    if (!state.factions[command.factionId])
        return fail('faction_unknown', '命令引用了未知阵营。');
    if (isFactionDefeated(state, command.factionId))
        return fail('faction_defeated', '该阵营已经退出战局。');
    switch (command.type) {
        case 'MOVE_OR_ATTACK':
            return validateMove(state, command);
        case 'MERGE_TASK_GROUP':
            return validateMergeTaskGroup(state, command);
        case 'SPLIT_TASK_GROUP':
            return validateSplitTaskGroup(state, command);
        case 'SET_FORMATION':
            return validateSetFormation(state, command);
        case 'END_ACTION':
            if (state.phase !== 'FIRST_FACTION_ACTION' && state.phase !== 'SECOND_FACTION_ACTION')
                return fail('action_phase_required', '当前不是行动阶段。');
            if (state.activeFactionId !== command.factionId)
                return fail('active_faction_mismatch', '当前不是该阵营的行动时机。');
            return { ok: true };
        case 'ALLOCATE_XP': {
            if (state.phase !== 'SETTLEMENT_PLANNING')
                return fail('planning_phase_required', '当前不是结算规划阶段。');
            const faction = requireFaction(state, command.factionId);
            if (faction.planningCommitted)
                return fail('planning_already_committed', '该阵营已经提交规划。');
            if (!Number.isInteger(command.amount) || command.amount <= 0)
                return fail('xp_amount_invalid', '经验分配量必须是正整数。');
            if (command.amount > faction.xpPool)
                return fail('xp_insufficient', '待分配经验不足。', { required: command.amount, available: faction.xpPool });
            if (!faction.cards[command.cardId])
                return fail('card_unknown', '未知卡牌。');
            return { ok: true };
        }
        case 'PURCHASE_PROMOTION': {
            if (state.phase !== 'SETTLEMENT_PLANNING')
                return fail('planning_phase_required', '当前不是结算规划阶段。');
            const faction = requireFaction(state, command.factionId);
            if (faction.planningCommitted)
                return fail('planning_already_committed', '该阵营已经提交规划。');
            const cardState = faction.cards[command.cardId];
            const definition = getCardDefinition(command.cardId);
            if (cardState.promotedThisSettlement)
                return fail('promotion_already_purchased_this_round', '每张卡每个战略结算最多升阶一次。');
            const expected = definition.allowedPromotions[cardState.purchasedPromotions.length];
            if (!expected)
                return fail('promotion_complete', '该卡牌没有后续可购买升阶。');
            if (expected !== command.promotionId)
                return fail('promotion_sequence_required', `必须按序购买 ${expected}。`, { promotionName: expected });
            const promotion = PROMOTIONS[command.promotionId];
            if (cardState.level < promotion.level)
                return fail('card_level_insufficient', `需要卡牌达到 Lv.${promotion.level}。`, { requiredLevel: promotion.level });
            if (faction.gold < promotion.cost)
                return fail('military_funds_insufficient', `金币不足，需要 ${promotion.cost}G。`, { required: promotion.cost, available: faction.gold });
            return { ok: true };
        }
        case 'ENQUEUE_PRODUCTION': {
            if (state.phase !== 'SETTLEMENT_PLANNING')
                return fail('planning_phase_required', '当前不是结算规划阶段。');
            const faction = requireFaction(state, command.factionId);
            if (faction.planningCommitted)
                return fail('planning_already_committed', '该阵营已经提交规划。');
            const node = state.map.nodes[command.nodeId];
            if (!node || node.productionSlots <= 0)
                return fail('production_node_invalid', '目标节点不是生产节点。');
            if (!isNodeActive(state, command.nodeId) || !isNodeStable(state, command.nodeId, command.factionId)) {
                return fail('production_node_unavailable', '只有稳定、激活的己方生产节点可以接收订单。');
            }
            const slot = faction.productionQueues[command.nodeId]?.find((candidate) => candidate.slotId === command.slotId);
            if (!slot)
                return fail('production_slot_missing', '生产槽不存在。');
            const definition = getCardDefinition(command.cardId);
            if (isCommanderCard(command.cardId)) {
                return fail('commander_state_invalid', '唯一指挥官只能通过指挥所重建，不能作为普通兵种排产。');
            }
            const cardState = faction.cards[command.cardId];
            if (cardState.level < definition.deploymentLevel)
                return fail('card_level_insufficient', `卡牌需要 Lv.${definition.deploymentLevel} 才能生产。`, { requiredLevel: definition.deploymentLevel });
            if (faction.gold < definition.productionCost)
                return fail('military_funds_insufficient', `金币不足，需要 ${definition.productionCost}G。`, { required: definition.productionCost, available: faction.gold });
            if (faction.populationUsed + faction.populationReserved + definition.populationCost > faction.populationCap) {
                return fail('population_capacity_insufficient', '人口容量不足（含预留人口）。', { required: definition.populationCost });
            }
            return { ok: true };
        }
        case 'CANCEL_PRODUCTION': {
            if (state.phase !== 'SETTLEMENT_PLANNING')
                return fail('planning_phase_required', '当前不是结算规划阶段。');
            const faction = requireFaction(state, command.factionId);
            if (faction.planningCommitted)
                return fail('planning_already_committed', '该阵营已经提交规划。');
            const slot = faction.productionQueues[command.nodeId]?.find((candidate) => candidate.slotId === command.slotId);
            if (!slot)
                return fail('production_slot_missing', '生产槽不存在。');
            const order = slot.orders.find((candidate) => candidate.orderId === command.orderId);
            if (!order)
                return fail('production_order_missing', '生产订单不存在或已离开该槽。');
            if (order.factionId !== command.factionId || order.nodeId !== command.nodeId || order.slotId !== command.slotId) {
                return fail('production_order_mismatch', '生产订单归属与目标槽不一致。');
            }
            const definition = getCardDefinition(order.cardId);
            if (order.status !== 'building' || order.remainingRounds !== definition.buildRounds) {
                return fail('production_order_locked', '订单已经获得生产进度，不能撤销。');
            }
            if (faction.populationReserved < order.populationCost)
                return fail('production_reservation_invalid', '生产预留人口状态异常，不能撤销。');
            return { ok: true };
        }
        case 'COMMIT_PLANNING': {
            if (state.phase !== 'SETTLEMENT_PLANNING')
                return fail('planning_phase_required', '当前不是结算规划阶段。');
            if (requireFaction(state, command.factionId).planningCommitted)
                return fail('planning_already_committed', '该阵营已经提交规划。');
            return { ok: true };
        }
        case 'ENQUEUE_COMMANDER_PRODUCTION': {
            if (state.phase !== 'SETTLEMENT_PLANNING')
                return fail('planning_phase_required', '当前不是结算规划阶段。');
            const commander = state.commanders[command.commanderId];
            if (!commander || commander.factionId !== command.factionId || commander.role !== 'boss_unique') {
                return fail('commander_unknown', '未找到该阵营的唯一指挥官。');
            }
            if (commander.status !== 'available')
                return fail('commander_state_invalid', '该指挥官已经在场或正在生产。');
            const faction = requireFaction(state, command.factionId);
            if (faction.gold < commander.productionGoldCost) {
                return fail('military_funds_insufficient', '军费不足，无法重新生产指挥官。', {
                    required: commander.productionGoldCost,
                    available: faction.gold,
                });
            }
            if (!isNodeStable(state, faction.commandPostNodeId, command.factionId)) {
                return fail('command_post_required', '只有己方安全指挥所可以重新生产指挥官。');
            }
            return { ok: true };
        }
        case 'REDEPLOY_PLAYER_AVATAR': {
            if (state.phase !== 'SETTLEMENT_PLANNING')
                return fail('planning_phase_required', '当前不是结算规划阶段。');
            const commander = state.commanders[command.commanderId];
            if (!commander || commander.factionId !== command.factionId || commander.role !== 'player_avatar') {
                return fail('commander_unknown', '未找到玩家指挥官。');
            }
            if (commander.status !== 'rear')
                return fail('commander_state_invalid', '玩家指挥官当前不在后方待部署。');
            const faction = requireFaction(state, command.factionId);
            if (command.nodeId !== faction.commandPostNodeId
                || !isNodeStable(state, command.nodeId, command.factionId)) {
                return fail('command_post_required', '玩家指挥官只能从己方安全指挥所重新部署。');
            }
            return { ok: true };
        }
    }
}
export function firstProductionSlotId(state, factionId, nodeId) {
    return state.factions[factionId]?.productionQueues[nodeId]?.[0]?.slotId ?? null;
}
//# sourceMappingURL=validator.js.map