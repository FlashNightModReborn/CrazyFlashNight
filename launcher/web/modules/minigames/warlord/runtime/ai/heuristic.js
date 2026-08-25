import { CARD_IDS, getCardDefinition } from '../data/cards.js';
import { PROMOTIONS } from '../data/config.js';
import { adjacentNodeIds } from '../data/map.js';
import { applyCommand } from '../core/engine.js';
import { getRuntimeStats, needXp } from '../core/math.js';
import { piecesAtNode } from '../core/selectors.js';
import { validateCommand } from '../core/validator.js';
function unitPower(state, pieceId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        return 0;
    const stats = getRuntimeStats(piece.cardId, state.factions[piece.factionId].cards[piece.cardId]);
    const definition = getCardDefinition(piece.cardId);
    const behaviorFactor = definition.behaviorId === 'sniper' ? 1.15 : definition.behaviorId === 'ammo' ? 1.05 : 1;
    return (piece.hp + stats.attack * 8 + stats.defense * 2) * behaviorFactor;
}
function chooseGroup(state, pieceIds, limit) {
    return [...pieceIds]
        .sort((a, b) => unitPower(state, b) - unitPower(state, a) || a.localeCompare(b))
        .slice(0, Math.max(0, limit));
}
function progressValue(state, factionId, nodeId) {
    const x = state.map.nodes[nodeId].x;
    return factionId === 'red' ? x : -x;
}
function generateMoveCandidates(state, factionId, seenTransitions) {
    const faction = state.factions[factionId];
    const candidates = [];
    for (const originNodeId of Object.keys(state.map.nodes).sort()) {
        const ownPieces = piecesAtNode(state, originNodeId, factionId).map((piece) => piece.pieceId);
        if (ownPieces.length === 0)
            continue;
        for (const targetNodeId of adjacentNodeIds(originNodeId)) {
            const enemies = piecesAtNode(state, targetNodeId).filter((piece) => piece.factionId !== factionId);
            const target = state.map.nodes[targetNodeId];
            if (enemies.length > 0) {
                const limit = Math.min(target.attackWidth, faction.actionPoints, ownPieces.length);
                if (limit <= 0)
                    continue;
                const selected = chooseGroup(state, ownPieces.filter((pieceId) => !state.pieces[pieceId]?.failedAssaultLocks.includes(targetNodeId)), limit);
                if (selected.length === 0)
                    continue;
                const attackerPower = selected.reduce((sum, id) => sum + unitPower(state, id), 0);
                const defenderPower = enemies.reduce((sum, piece) => sum + unitPower(state, piece.pieceId), 0)
                    * (1 + target.defenseBonus);
                const ratio = defenderPower > 0 ? attackerPower / defenderPower : 10;
                const productionThreat = target.productionSlots > 0 ? 45 : 0;
                const score = 120 + target.strategicValue * 15 + productionThreat + Math.min(60, ratio * 25) - (ratio < 0.55 ? 100 : 0);
                const command = {
                    type: 'MOVE_OR_ATTACK', factionId, pieceIds: selected, originNodeId, targetNodeId,
                };
                const validation = validateCommand(state, command);
                if (validation.ok)
                    candidates.push({ score, command, key: `${targetNodeId}|${originNodeId}|${selected.join(',')}` });
                continue;
            }
            const available = target.capacity - target.pieceIds.length;
            if (available <= 0 || faction.actionPoints <= 0)
                continue;
            const selected = chooseGroup(state, ownPieces, 1);
            const pieceId = selected[0];
            if (!pieceId)
                continue;
            const transitionKey = `${pieceId}:${originNodeId}->${targetNodeId}`;
            const reverseKey = `${pieceId}:${targetNodeId}->${originNodeId}`;
            if (seenTransitions.has(transitionKey) || seenTransitions.has(reverseKey))
                continue;
            const ownershipScore = target.ownerFactionId === factionId ? 0 : target.ownerFactionId === null ? 55 : 75;
            const functionScore = target.goldIncome * 3 + target.population * 2 + target.apBonus * 12 + target.strategicValue * 8;
            const advance = progressValue(state, factionId, targetNodeId) - progressValue(state, factionId, originNodeId);
            const score = ownershipScore + functionScore + advance * 0.08;
            const command = {
                type: 'MOVE_OR_ATTACK', factionId, pieceIds: [pieceId], originNodeId, targetNodeId,
            };
            const validation = validateCommand(state, command);
            if (validation.ok)
                candidates.push({ score, command, key: `${targetNodeId}|${originNodeId}|${pieceId}` });
        }
    }
    return candidates.sort((a, b) => b.score - a.score || a.key.localeCompare(b.key));
}
export function generateNextAiAction(state, factionId, seenTransitions = new Set()) {
    if (state.activeFactionId !== factionId || state.factions[factionId].actionPoints <= 0)
        return null;
    return generateMoveCandidates(state, factionId, seenTransitions)[0]?.command ?? null;
}
export function runAiActionPhase(state, factionId, maxCommands = 64) {
    let current = state;
    const commands = [];
    let invalidGenerated = 0;
    const seenTransitions = new Set();
    for (let i = 0; i < maxCommands; i += 1) {
        if (current.activeFactionId !== factionId || current.phase === 'GAME_OVER')
            break;
        const command = generateNextAiAction(current, factionId, seenTransitions);
        if (!command)
            break;
        const validation = validateCommand(current, command);
        if (!validation.ok) {
            invalidGenerated += 1;
            break;
        }
        const beforeLocations = Object.fromEntries(command.pieceIds.map((pieceId) => [pieceId, current.pieces[pieceId]?.nodeId]));
        const result = applyCommand(current, command);
        if (!result.ok) {
            invalidGenerated += 1;
            break;
        }
        commands.push(command);
        current = result.state;
        for (const pieceId of command.pieceIds) {
            const from = beforeLocations[pieceId];
            const to = current.pieces[pieceId]?.nodeId;
            if (from && to && from !== to)
                seenTransitions.add(`${pieceId}:${from}->${to}`);
        }
    }
    if (current.activeFactionId === factionId && current.phase !== 'GAME_OVER') {
        const end = { type: 'END_ACTION', factionId };
        const result = applyCommand(current, end);
        if (result.ok) {
            current = result.state;
            commands.push(end);
        }
        else {
            invalidGenerated += 1;
        }
    }
    return { state: current, commands, invalidGenerated };
}
function xpToReachLevel(cardId, currentLevel, xpIntoLevel, targetLevel) {
    let needed = -xpIntoLevel;
    for (let level = currentLevel; level < targetLevel; level += 1)
        needed += needXp(cardId, level);
    return Math.max(0, needed);
}
function chooseXpCard(state, factionId) {
    const faction = state.factions[factionId];
    const locked = CARD_IDS
        .filter((cardId) => faction.cards[cardId].level < getCardDefinition(cardId).deploymentLevel)
        .map((cardId) => ({
        cardId,
        needed: xpToReachLevel(cardId, faction.cards[cardId].level, faction.cards[cardId].xpIntoLevel, getCardDefinition(cardId).deploymentLevel),
    }))
        .sort((a, b) => a.needed - b.needed || a.cardId - b.cardId);
    if (locked[0])
        return locked[0].cardId;
    return [...CARD_IDS].sort((a, b) => (faction.cards[a].level - faction.cards[b].level || a - b))[0] ?? 14;
}
function roleCounts(state, factionId) {
    const counts = { assault: 0, sniper: 0, ammo: 0, heavy: 0 };
    for (const piece of Object.values(state.pieces)) {
        if (piece.factionId === factionId)
            counts[getCardDefinition(piece.cardId).behaviorId] = (counts[getCardDefinition(piece.cardId).behaviorId] ?? 0) + 1;
    }
    for (const slots of Object.values(state.factions[factionId].productionQueues)) {
        for (const slot of slots ?? []) {
            for (const order of slot.orders) {
                const behavior = getCardDefinition(order.cardId).behaviorId;
                counts[behavior] = (counts[behavior] ?? 0) + 1;
            }
        }
    }
    return counts;
}
function tierRank(cardId) {
    const tier = getCardDefinition(cardId).powerTier;
    return tier.startsWith('T3') ? 3 : tier.startsWith('T2') ? 2 : 1;
}
function chooseProductionCard(state, factionId) {
    const faction = state.factions[factionId];
    const counts = roleCounts(state, factionId);
    const fitsPopulation = (cardId) => {
        const definition = getCardDefinition(cardId);
        return faction.populationUsed + faction.populationReserved + definition.populationCost <= faction.populationCap;
    };
    const unlocked = CARD_IDS.filter((cardId) => {
        const definition = getCardDefinition(cardId);
        return faction.cards[cardId].level >= definition.deploymentLevel && fitsPopulation(cardId);
    });
    const affordable = unlocked.filter((cardId) => faction.gold >= getCardDefinition(cardId).productionCost);
    // First restore an actually missing battlefield function. Heavy only enters this
    // branch after its T2 card has been unlocked, so the standard opening still uses
    // the three T1 roles defined by the specification.
    const roleOrder = ['assault', 'sniper', 'ammo', 'heavy'];
    const missingRole = roleOrder.find((role) => ((counts[role] ?? 0) === 0
        && unlocked.some((cardId) => getCardDefinition(cardId).behaviorId === role)));
    if (missingRole) {
        const roleCard = affordable
            .filter((cardId) => getCardDefinition(cardId).behaviorId === missingRole)
            .sort((a, b) => tierRank(b) - tierRank(a)
            || getCardDefinition(a).productionCost - getCardDefinition(b).productionCost
            || a - b)[0];
        if (roleCard)
            return roleCard;
        // The role is unlocked but temporarily unaffordable. Do not consume the
        // earmarked budget on another redundant T1 order; deterministic saving is
        // required for T2/T3 cards to be reachable in a finite 24-round match.
        return null;
    }
    const affordableAdvanced = affordable.filter((cardId) => tierRank(cardId) >= 2);
    if (affordableAdvanced.length > 0) {
        return affordableAdvanced.sort((a, b) => {
            const definitionA = getCardDefinition(a);
            const definitionB = getCardDefinition(b);
            return tierRank(b) - tierRank(a)
                || (counts[definitionA.behaviorId] ?? 0) - (counts[definitionB.behaviorId] ?? 0)
                || definitionA.productionCost - definitionB.productionCost
                || a - b;
        })[0] ?? null;
    }
    // Once every core role exists and at least one advanced card is unlocked,
    // preserve gold until the cheapest advanced order becomes legal instead of
    // creating an endless stream of cheap T1 units.
    if (unlocked.some((cardId) => tierRank(cardId) >= 2))
        return null;
    const leastRepresentedCoreRole = [...roleOrder.slice(0, 3)]
        .sort((a, b) => (counts[a] ?? 0) - (counts[b] ?? 0) || a.localeCompare(b))[0];
    return affordable
        .filter((cardId) => getCardDefinition(cardId).behaviorId === leastRepresentedCoreRole)
        .sort((a, b) => getCardDefinition(a).productionCost - getCardDefinition(b).productionCost || a - b)[0]
        ?? affordable.sort((a, b) => getCardDefinition(a).productionCost - getCardDefinition(b).productionCost || a - b)[0]
        ?? null;
}
export function generateAiPlanningCommands(state, factionId) {
    if (state.phase !== 'SETTLEMENT_PLANNING' || state.factions[factionId].planningCommitted)
        return [];
    let shadow = state;
    const commands = [];
    const applyIfLegal = (command) => {
        if (!validateCommand(shadow, command).ok)
            return false;
        const result = applyCommand(shadow, command);
        if (!result.ok)
            return false;
        shadow = result.state;
        commands.push(command);
        return true;
    };
    const xpPool = shadow.factions[factionId].xpPool;
    if (xpPool > 0) {
        applyIfLegal({ type: 'ALLOCATE_XP', factionId, cardId: chooseXpCard(shadow, factionId), amount: xpPool });
    }
    for (const cardId of CARD_IDS) {
        const card = shadow.factions[factionId].cards[cardId];
        const nextPromotion = getCardDefinition(cardId).allowedPromotions[card.purchasedPromotions.length];
        if (!nextPromotion)
            continue;
        const promo = PROMOTIONS[nextPromotion];
        if (card.level >= promo.level && shadow.factions[factionId].gold >= promo.cost) {
            applyIfLegal({ type: 'PURCHASE_PROMOTION', factionId, cardId, promotionId: nextPromotion });
            break;
        }
    }
    const productionNodes = Object.keys(shadow.map.nodes)
        .filter((nodeId) => shadow.factions[factionId].productionQueues[nodeId])
        .sort();
    for (const nodeId of productionNodes) {
        const slots = shadow.factions[factionId].productionQueues[nodeId] ?? [];
        for (const slot of slots) {
            if (slot.orders.length > 0)
                continue;
            const cardId = chooseProductionCard(shadow, factionId);
            if (!cardId)
                continue;
            const command = { type: 'ENQUEUE_PRODUCTION', factionId, nodeId, slotId: slot.slotId, cardId };
            applyIfLegal(command);
        }
    }
    commands.push({ type: 'COMMIT_PLANNING', factionId });
    return commands;
}
export function runAiPlanning(state, factionId) {
    let current = state;
    const commands = generateAiPlanningCommands(state, factionId);
    let invalidGenerated = 0;
    const applied = [];
    for (const command of commands) {
        const validation = validateCommand(current, command);
        if (!validation.ok) {
            invalidGenerated += 1;
            continue;
        }
        const result = applyCommand(current, command);
        if (!result.ok) {
            invalidGenerated += 1;
            continue;
        }
        current = result.state;
        applied.push(command);
    }
    return { state: current, commands: applied, invalidGenerated };
}
//# sourceMappingURL=heuristic.js.map