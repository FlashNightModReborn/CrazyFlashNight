import { PRODUCTION_CARD_IDS, getCardDefinition } from '../data/cards.js';
import { PROMOTIONS } from '../data/config.js';
import { requireNode } from '../core/access.js';
import { applyCommand } from '../core/engine.js';
import { enumerateLocalMoveOrAttackCommands } from '../core/command-enumerator.js';
import { relationBetween, requireFaction } from '../core/factions.js';
import { getRuntimeStats, needXp } from '../core/math.js';
import { commandElementMetrics, commandElementsAtNode, nodeDeploymentSize, } from '../core/organization.js';
import { adjacentNodeIds, piecesAtNode } from '../core/selectors.js';
import { validateCommand } from '../core/validator.js';
function unitPower(state, pieceId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        return 0;
    const stats = getRuntimeStats(piece.cardId, requireFaction(state, piece.factionId).cards[piece.cardId]);
    const definition = getCardDefinition(piece.cardId);
    const behaviorFactor = definition.behaviorId === 'sniper' ? 1.15 : definition.behaviorId === 'ammo' ? 1.05 : 1;
    return (piece.hp + stats.attack * 8 + stats.defense * 2) * behaviorFactor;
}
function elementPower(state, element) {
    return element.memberIds.reduce((sum, memberId) => sum + unitPower(state, memberId), 0);
}
function chooseCommandElements(state, elements, limits) {
    const ranked = [...elements].sort((left, right) => (elementPower(state, right) - elementPower(state, left)
        || left.elementId.localeCompare(right.elementId)));
    const selected = [];
    let commandLoad = 0;
    let deploymentSize = 0;
    let encounterCost = 0;
    let selectedElements = 0;
    for (const element of ranked) {
        if (selectedElements >= (limits.maximumElements ?? Number.POSITIVE_INFINITY))
            break;
        const metrics = commandElementMetrics(state, element);
        if (commandLoad + metrics.commandLoad > limits.commandLoad
            || deploymentSize + metrics.deploymentSize > limits.deploymentSize
            || encounterCost + metrics.encounterCost > limits.encounterCost) {
            continue;
        }
        selected.push(...element.memberIds);
        commandLoad += metrics.commandLoad;
        deploymentSize += metrics.deploymentSize;
        encounterCost += metrics.encounterCost;
        selectedElements += 1;
    }
    return selected;
}
function chooseUniformFormationCommandElements(state, elements, limits) {
    const buckets = new Map();
    for (const element of elements) {
        const bucket = buckets.get(element.formationProfileId) ?? [];
        bucket.push(element);
        buckets.set(element.formationProfileId, bucket);
    }
    const candidates = [...buckets.entries()].map(([formationProfileId, bucket]) => {
        const pieceIds = chooseCommandElements(state, bucket, limits);
        return {
            pieceIds,
            power: pieceIds.reduce((sum, pieceId) => sum + unitPower(state, pieceId), 0),
            key: `${formationProfileId}|${pieceIds.join(',')}`,
        };
    }).filter((candidate) => candidate.pieceIds.length > 0);
    candidates.sort((left, right) => right.power - left.power || left.key.localeCompare(right.key));
    return candidates[0]?.pieceIds ?? [];
}
function progressValue(state, factionId, nodeId) {
    const node = requireNode(state, nodeId);
    const hostilePosts = state.turnOrder
        .filter((otherFactionId) => otherFactionId !== factionId
        && relationBetween(state, factionId, otherFactionId) === 'hostile')
        .map((otherFactionId) => requireNode(state, requireFaction(state, otherFactionId).commandPostNodeId));
    if (hostilePosts.length === 0)
        return node.strategicValue * 10;
    const nearest = Math.min(...hostilePosts.map((target) => Math.hypot(target.x - node.x, target.y - node.y)));
    return -nearest + node.strategicValue * 4;
}
function generateMoveCandidates(state, factionId, seenTransitions) {
    const candidates = [];
    const enumeration = enumerateLocalMoveOrAttackCommands(state, factionId);
    if (enumeration.work.guardHit)
        state.diagnostics.maxCommandsGuardHit = true;
    for (const entry of enumeration.legalCommands) {
        const command = entry.command;
        const { originNodeId, targetNodeId } = command;
        if (!entry.validation.isBattle && command.pieceIds.some((pieceId) => (seenTransitions.has(`${pieceId}:${originNodeId}->${targetNodeId}`)
            || seenTransitions.has(`${pieceId}:${targetNodeId}->${originNodeId}`))))
            continue;
        const target = requireNode(state, targetNodeId);
        let score;
        if (entry.validation.isBattle) {
            const enemies = piecesAtNode(state, targetNodeId).filter((piece) => (piece.factionId !== factionId
                && relationBetween(state, factionId, piece.factionId) === 'hostile'));
            const attackerPower = command.pieceIds.reduce((sum, id) => sum + unitPower(state, id), 0);
            const defenderPower = enemies.reduce((sum, piece) => sum + unitPower(state, piece.pieceId), 0)
                * (1 + target.defenseBonus);
            const ratio = defenderPower > 0 ? attackerPower / defenderPower : 10;
            const productionThreat = target.productionSlots > 0 ? 45 : 0;
            score = 120 + target.strategicValue * 15 + productionThreat
                + Math.min(60, ratio * 25) - (ratio < 0.55 ? 100 : 0);
        }
        else {
            const ownershipScore = target.ownerFactionId === factionId ? 0 : target.ownerFactionId === null ? 55 : 75;
            const functionScore = target.goldIncome * 3 + target.population * 2
                + target.apBonus * 12 + target.strategicValue * 8;
            const advance = progressValue(state, factionId, targetNodeId)
                - progressValue(state, factionId, originNodeId);
            score = ownershipScore + functionScore + advance * 0.08;
        }
        candidates.push({
            score,
            command,
            key: `${targetNodeId}|${originNodeId}|${command.pieceIds.join(',')}`,
        });
    }
    return candidates.sort((a, b) => b.score - a.score || a.key.localeCompare(b.key));
}
export function generateNextAiAction(state, factionId, seenTransitions = new Set()) {
    if (state.activeFactionId !== factionId || requireFaction(state, factionId).actionPoints <= 0)
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
    const faction = requireFaction(state, factionId);
    const locked = PRODUCTION_CARD_IDS
        .filter((cardId) => faction.cards[cardId].level < getCardDefinition(cardId).deploymentLevel)
        .map((cardId) => ({
        cardId,
        needed: xpToReachLevel(cardId, faction.cards[cardId].level, faction.cards[cardId].xpIntoLevel, getCardDefinition(cardId).deploymentLevel),
    }))
        .sort((a, b) => a.needed - b.needed || a.cardId - b.cardId);
    if (locked[0])
        return locked[0].cardId;
    return [...PRODUCTION_CARD_IDS].sort((a, b) => (faction.cards[a].level - faction.cards[b].level || a - b))[0] ?? 14;
}
function roleCounts(state, factionId) {
    const counts = { assault: 0, sniper: 0, ammo: 0, heavy: 0 };
    for (const piece of Object.values(state.pieces)) {
        if (piece.factionId === factionId)
            counts[getCardDefinition(piece.cardId).behaviorId] = (counts[getCardDefinition(piece.cardId).behaviorId] ?? 0) + 1;
    }
    for (const slots of Object.values(requireFaction(state, factionId).productionQueues)) {
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
    const faction = requireFaction(state, factionId);
    const counts = roleCounts(state, factionId);
    const fitsPopulation = (cardId) => {
        const definition = getCardDefinition(cardId);
        return faction.populationUsed + faction.populationReserved + definition.populationCost <= faction.populationCap;
    };
    const unlocked = PRODUCTION_CARD_IDS.filter((cardId) => {
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
    if (state.phase !== 'SETTLEMENT_PLANNING' || requireFaction(state, factionId).planningCommitted)
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
    const xpPool = requireFaction(shadow, factionId).xpPool;
    const availableBossCommander = Object.values(shadow.commanders)
        .filter((commander) => (commander.factionId === factionId
        && commander.role === 'boss_unique'
        && commander.status === 'available'))
        .sort((left, right) => left.commanderId.localeCompare(right.commanderId))[0];
    if (availableBossCommander) {
        applyIfLegal({
            type: 'ENQUEUE_COMMANDER_PRODUCTION',
            factionId,
            commanderId: availableBossCommander.commanderId,
        });
    }
    if (xpPool > 0) {
        applyIfLegal({ type: 'ALLOCATE_XP', factionId, cardId: chooseXpCard(shadow, factionId), amount: xpPool });
    }
    for (const cardId of PRODUCTION_CARD_IDS) {
        const card = requireFaction(shadow, factionId).cards[cardId];
        const nextPromotion = getCardDefinition(cardId).allowedPromotions[card.purchasedPromotions.length];
        if (!nextPromotion)
            continue;
        const promo = PROMOTIONS[nextPromotion];
        if (card.level >= promo.level && requireFaction(shadow, factionId).gold >= promo.cost) {
            applyIfLegal({ type: 'PURCHASE_PROMOTION', factionId, cardId, promotionId: nextPromotion });
            break;
        }
    }
    const productionNodes = Object.keys(shadow.map.nodes)
        .filter((nodeId) => requireFaction(shadow, factionId).productionQueues[nodeId])
        .sort();
    for (const nodeId of productionNodes) {
        const slots = requireFaction(shadow, factionId).productionQueues[nodeId] ?? [];
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