import { requireNode } from '../core/access.js';
import { relationBetween, requireFaction } from '../core/factions.js';
import { selectedCommandElements, selectionOrganizationMetrics, } from '../core/organization.js';
import { adjacentNodeIds, isNodeActive, isNodeStable, nodeOccupyingFactions, piecesAtNode } from '../core/selectors.js';
import { validateCommand } from '../core/validator.js';
import { getCardDefinition } from '../data/cards.js';
import { playerBehaviorName, playerFactionName, playerOwnerName } from './player-text-catalog.js';
export const PHASE_LABEL = {
    FIRST_FACTION_ACTION: '先手行动',
    SECOND_FACTION_ACTION: '后手行动',
    SETTLEMENT_PLANNING: '统一结算规划',
    GAME_OVER: '对局结束',
};
export function ownerLabel(owner, state) {
    if (!state || owner === null)
        return playerOwnerName(owner);
    const faction = requireFaction(state, owner);
    if (owner === state.playerFactionId)
        return `我方 · ${faction.displayName}`;
    const relation = relationBetween(state, state.playerFactionId, owner);
    const relationLabel = relation === 'allied' ? '盟军' : relation === 'neutral' ? '中立' : '敌方';
    return `${relationLabel} · ${faction.displayName}`;
}
/**
 * BattleRecord keeps cardId for strategic HP/economy settlement. Presentation
 * instead follows the independently frozen encounter identity so the player's
 * paper-doll avatar cannot be rendered as card 83 (精锐狙击兵).
 */
export function projectBattleUnitPresentation(snapshot) {
    if (snapshot.encounterProjectionKind === 'player_avatar') {
        return {
            displayName: '我方主角',
            roleLabel: '主角指挥官',
            portraitKind: 'player_avatar',
            portraitIdentifier: null,
        };
    }
    return {
        displayName: snapshot.displayName,
        roleLabel: playerBehaviorName(snapshot.behaviorId),
        portraitKind: 'catalog',
        portraitIdentifier: getCardDefinition(snapshot.cardId).identifier,
    };
}
export function factionLabel(faction, state) {
    if (!state)
        return playerFactionName(faction);
    return ownerLabel(faction, state);
}
// Preserve the original nine-node composition exactly while deriving the
// origin from authored map bounds. A larger authored coordinate field now
// becomes a larger world instead of being squeezed into the demo viewport.
const WORLD_UNITS_PER_MAP_X = 8.4 / 380;
const WORLD_UNITS_PER_MAP_Y = 3.4 / 140;
export function mapProjectionFrame(state) {
    const nodes = Object.values(state.map.nodes);
    if (nodes.length === 0) {
        return {
            centerX: 0,
            centerY: 0,
            worldUnitsPerMapX: WORLD_UNITS_PER_MAP_X,
            worldUnitsPerMapY: WORLD_UNITS_PER_MAP_Y,
        };
    }
    const xs = nodes.map((node) => node.x);
    const ys = nodes.map((node) => node.y);
    return {
        centerX: (Math.min(...xs) + Math.max(...xs)) / 2,
        centerY: (Math.min(...ys) + Math.max(...ys)) / 2,
        worldUnitsPerMapX: WORLD_UNITS_PER_MAP_X,
        worldUnitsPerMapY: WORLD_UNITS_PER_MAP_Y,
    };
}
export function projectNodes(state) {
    const frame = mapProjectionFrame(state);
    return Object.keys(state.map.nodes).map((nodeId) => {
        const node = requireNode(state, nodeId);
        const occupiers = nodeOccupyingFactions(state, nodeId);
        const factionCounts = Object.create(null);
        for (const factionId of state.turnOrder) {
            factionCounts[factionId] = piecesAtNode(state, nodeId, factionId).length;
        }
        const playerCount = factionCounts[state.playerFactionId] ?? 0;
        let alliedCount = 0;
        let neutralCount = 0;
        let hostileCount = 0;
        for (const factionId of state.turnOrder) {
            if (factionId === state.playerFactionId)
                continue;
            const count = factionCounts[factionId] ?? 0;
            const relation = relationBetween(state, state.playerFactionId, factionId);
            if (relation === 'allied')
                alliedCount += count;
            else if (relation === 'neutral')
                neutralCount += count;
            else
                hostileCount += count;
        }
        return {
            nodeId,
            displayName: node.displayName,
            kind: node.kind,
            ownerFactionId: node.ownerFactionId,
            ownerLabel: ownerLabel(node.ownerFactionId, state),
            active: isNodeActive(state, nodeId),
            stable: node.ownerFactionId ? isNodeStable(state, nodeId, node.ownerFactionId) : false,
            playerCount,
            alliedCount,
            neutralCount,
            hostileCount,
            factionCounts,
            redCount: playerCount,
            blueCount: hostileCount,
            contested: !!node.ownerFactionId && occupiers.some((faction) => faction !== node.ownerFactionId),
            encounterProfileRef: node.encounterProfileRef,
            distanceBand: node.distanceBand,
            spawnDistance: node.spawnDistance,
            x: (node.x - frame.centerX) * frame.worldUnitsPerMapX,
            z: (node.y - frame.centerY) * frame.worldUnitsPerMapY,
        };
    });
}
export function buildActionPreviews(state, selectedNodeId, selectedPieceIds) {
    const emptyMetrics = {
        commandLoad: 0,
        deploymentSize: 0,
        encounterCost: 0,
        apContribution: 0,
        memberCount: 0,
    };
    let requestedMetrics = emptyMetrics;
    if (selectedPieceIds.length > 0) {
        try {
            requestedMetrics = selectionOrganizationMetrics(state, selectedPieceIds);
        }
        catch {
            // Validator owns the typed rejection for a partial/invalid command element selection.
        }
    }
    const directTargets = adjacentNodeIds(state, selectedNodeId)
        .sort((left, right) => String(left).localeCompare(String(right)));
    const directTargetSet = new Set(directTargets);
    const paths = directTargets
        .map((targetNodeId) => ({ targetNodeId }));
    const seenTransitTargets = new Set();
    for (const viaNodeId of directTargets) {
        const occupiers = nodeOccupyingFactions(state, viaNodeId);
        if (occupiers.length !== 1
            || occupiers[0] === state.playerFactionId
            || relationBetween(state, state.playerFactionId, occupiers[0] ?? state.playerFactionId) !== 'allied')
            continue;
        for (const targetNodeId of adjacentNodeIds(state, viaNodeId)
            .sort((left, right) => String(left).localeCompare(String(right)))) {
            if (targetNodeId === selectedNodeId
                || directTargetSet.has(targetNodeId)
                || seenTransitTargets.has(targetNodeId))
                continue;
            seenTransitTargets.add(targetNodeId);
            paths.push({ targetNodeId, viaNodeId });
        }
    }
    return paths.map(({ targetNodeId, viaNodeId }) => {
        const targetNode = requireNode(state, targetNodeId);
        const command = {
            type: 'MOVE_OR_ATTACK',
            factionId: state.playerFactionId,
            pieceIds: [...selectedPieceIds],
            originNodeId: selectedNodeId,
            targetNodeId,
            ...(viaNodeId ? { viaNodeId } : {}),
        };
        const validation = validateCommand(state, command);
        const actualPieceIds = validation.actualPieceIds ?? [];
        let projectedMetrics = requestedMetrics;
        if (actualPieceIds.length > 0) {
            try {
                projectedMetrics = selectionOrganizationMetrics(state, actualPieceIds);
            }
            catch {
                // Keep the requested projection so invalid previews still expose useful totals.
            }
        }
        const commandLoad = validation.commandLoad ?? projectedMetrics.commandLoad;
        const deploymentSize = validation.deploymentSize ?? projectedMetrics.deploymentSize;
        const encounterCost = validation.encounterCost ?? projectedMetrics.encounterCost;
        return {
            targetNodeId,
            ...(viaNodeId ? { viaNodeId } : {}),
            targetName: targetNode.displayName,
            ok: validation.ok,
            reasonCode: validation.reasonCode ?? null,
            reasonParams: validation.reasonParams ?? {},
            actualPieceIds,
            actualCommandElementCount: selectedCommandElements(state, actualPieceIds).elements.length,
            commandLoad,
            deploymentSize,
            encounterCost,
            encounterProfileRef: targetNode.encounterProfileRef,
            distanceBand: targetNode.distanceBand,
            spawnDistance: targetNode.spawnDistance,
            apCost: commandLoad,
            isBattle: validation.isBattle === true,
        };
    });
}
export function nextPromotionFor(game, factionId, cardId) {
    const definition = getCardDefinition(cardId);
    return definition.allowedPromotions[requireFaction(game, factionId).cards[cardId].purchasedPromotions.length] ?? null;
}
function initialAttackRound(behaviorId) {
    return behaviorId === 'ammo' ? 2 : 1;
}
function attackInterval(behaviorId) {
    return behaviorId === 'sniper' || behaviorId === 'ammo' ? 2 : 1;
}
export function projectBattleVisual(record, eventCount) {
    const units = new Map();
    for (const snapshot of [...record.attackerSnapshots, ...record.defenderSnapshots]) {
        units.set(snapshot.pieceId, {
            snapshot,
            hp: snapshot.hp,
            dead: snapshot.hp <= 0,
            suppressionPending: false,
            reloading: snapshot.behaviorId === 'ammo',
            nextAttackRound: initialAttackRound(snapshot.behaviorId),
            lastStatus: snapshot.behaviorId === 'ammo' ? '装填待命' : '战斗待命',
        });
    }
    for (const event of record.result.eventLog.slice(0, Math.max(0, eventCount))) {
        const actor = event.actorPieceId ? units.get(event.actorPieceId) : undefined;
        const target = event.targetPieceId ? units.get(event.targetPieceId) : undefined;
        if (event.type === 'reload' && actor) {
            actor.reloading = true;
            actor.nextAttackRound = Math.max(actor.nextAttackRound, 2);
            actor.lastStatus = '装填中';
        }
        if (event.type === 'attack' && actor) {
            actor.reloading = false;
            actor.suppressionPending = false;
            actor.nextAttackRound = event.battleRound + attackInterval(actor.snapshot.behaviorId);
            actor.lastStatus = event.phase === 'opening_volley' ? '狙击先制' : `第 ${event.battleRound} 轮已攻击`;
        }
        if (event.type === 'miss' && actor)
            actor.lastStatus = `第 ${event.battleRound} 轮未命中`;
        if ((event.type === 'damage' || event.type === 'special') && target) {
            target.hp = typeof event.hpAfter === 'number' ? event.hpAfter : Math.max(0, target.hp - (event.damage ?? 0));
            target.lastStatus = event.type === 'special' ? '遭受特攻' : '遭受伤害';
        }
        if (event.type === 'suppression' && target) {
            target.suppressionPending = true;
            target.nextAttackRound += 1;
            target.lastStatus = `受压制至第 ${target.nextAttackRound} 轮`;
        }
        if (event.type === 'death' && target) {
            target.hp = 0;
            target.dead = true;
            target.suppressionPending = false;
            target.lastStatus = '阵亡';
        }
    }
    if (eventCount >= record.result.eventLog.length) {
        for (const result of record.result.pieceResults) {
            const unit = units.get(result.pieceId);
            if (!unit)
                continue;
            unit.hp = result.hpAfter;
            unit.dead = result.dead;
            if (result.dead)
                unit.lastStatus = '阵亡';
        }
    }
    return units;
}
export function stateProjectionDigest(state) {
    return JSON.stringify({
        round: state.strategicRound,
        phase: state.phase,
        active: state.activeFactionId,
        nodes: projectNodes(state),
        pieces: Object.values(state.pieces).map((piece) => ({
            id: piece.pieceId,
            faction: piece.factionId,
            card: piece.cardId,
            node: piece.nodeId,
            hp: piece.hp,
        })).sort((a, b) => a.id.localeCompare(b.id)),
        organization: Object.values(state.organization.commandElements).map((element) => ({
            id: element.elementId,
            kind: element.kind,
            faction: element.factionId,
            node: element.nodeId,
            members: [...element.memberIds].sort((left, right) => left.localeCompare(right)),
            formation: element.formationProfileId,
            template: element.taskGroupTemplateId,
        })).sort((left, right) => left.id.localeCompare(right.id)),
    });
}
//# sourceMappingURL=presenter.js.map