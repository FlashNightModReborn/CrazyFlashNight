import { isNodeActive, isNodeStable, nodeOccupyingFactions, piecesAtNode } from '../core/selectors.js';
import { validateCommand } from '../core/validator.js';
import { getCardDefinition } from '../data/cards.js';
import { adjacentNodeIds } from '../data/map.js';
export const PHASE_LABEL = {
    FIRST_FACTION_ACTION: '先手行动',
    SECOND_FACTION_ACTION: '后手行动',
    SETTLEMENT_PLANNING: '统一结算规划',
    GAME_OVER: '对局结束',
};
export function ownerLabel(owner) {
    return owner === 'red' ? 'R 红方' : owner === 'blue' ? 'B 蓝方' : 'N 中立';
}
export function factionLabel(faction) {
    return faction === 'red' ? '红方' : '蓝方';
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
        const node = state.map.nodes[nodeId];
        const occupiers = nodeOccupyingFactions(state, nodeId);
        return {
            nodeId,
            displayName: node.displayName,
            kind: node.kind,
            ownerFactionId: node.ownerFactionId,
            ownerLabel: ownerLabel(node.ownerFactionId),
            active: isNodeActive(state, nodeId),
            stable: node.ownerFactionId ? isNodeStable(state, nodeId, node.ownerFactionId) : false,
            redCount: piecesAtNode(state, nodeId, 'red').length,
            blueCount: piecesAtNode(state, nodeId, 'blue').length,
            contested: !!node.ownerFactionId && occupiers.some((faction) => faction !== node.ownerFactionId),
            x: (node.x - frame.centerX) * frame.worldUnitsPerMapX,
            z: (node.y - frame.centerY) * frame.worldUnitsPerMapY,
        };
    });
}
export function buildActionPreviews(state, selectedNodeId, selectedPieceIds) {
    return adjacentNodeIds(selectedNodeId).map((targetNodeId) => {
        const command = {
            type: 'MOVE_OR_ATTACK',
            factionId: 'red',
            pieceIds: [...selectedPieceIds],
            originNodeId: selectedNodeId,
            targetNodeId,
        };
        const validation = validateCommand(state, command);
        const actualPieceIds = validation.actualPieceIds ?? [];
        return {
            targetNodeId,
            targetName: state.map.nodes[targetNodeId].displayName,
            ok: validation.ok,
            error: validation.error ?? null,
            actualPieceIds,
            apCost: actualPieceIds.length || selectedPieceIds.length,
            isBattle: validation.isBattle === true,
        };
    });
}
export function nextPromotionFor(game, factionId, cardId) {
    const definition = getCardDefinition(cardId);
    return definition.allowedPromotions[game.factions[factionId].cards[cardId].purchasedPromotions.length] ?? null;
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
            actor.lastStatus = event.phase === 'opening_volley' ? '狙击先制' : `R${event.battleRound} 已攻击`;
        }
        if (event.type === 'miss' && actor)
            actor.lastStatus = `R${event.battleRound} 未命中`;
        if ((event.type === 'damage' || event.type === 'special') && target) {
            target.hp = typeof event.hpAfter === 'number' ? event.hpAfter : Math.max(0, target.hp - (event.damage ?? 0));
            target.lastStatus = event.type === 'special' ? '遭受特攻' : '遭受伤害';
        }
        if (event.type === 'suppression' && target) {
            target.suppressionPending = true;
            target.nextAttackRound += 1;
            target.lastStatus = `受压制至 R${target.nextAttackRound}`;
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
    });
}
//# sourceMappingURL=presenter.js.map