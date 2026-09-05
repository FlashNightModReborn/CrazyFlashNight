import { relationBetween } from './factions.js';
import { nodeOccupyingFactions } from './selectors.js';
import { validateCommand } from './validator.js';
export const DEFAULT_LOCAL_COMMAND_ENUMERATION_BUDGET = Object.freeze({
    maximumCommandElementsInspected: 256,
    maximumMapEdgesInspected: 512,
    maximumLocalEdgesVisited: 1024,
    maximumCandidates: 512,
    maximumValidations: 512,
});
function budgetValue(value, name) {
    if (!Number.isInteger(value) || value < 0) {
        throw new Error(name + ' must be a non-negative integer.');
    }
    return value;
}
function resolveBudget(overrides) {
    return Object.freeze({
        maximumCommandElementsInspected: budgetValue(overrides.maximumCommandElementsInspected
            ?? DEFAULT_LOCAL_COMMAND_ENUMERATION_BUDGET.maximumCommandElementsInspected, 'maximumCommandElementsInspected'),
        maximumMapEdgesInspected: budgetValue(overrides.maximumMapEdgesInspected
            ?? DEFAULT_LOCAL_COMMAND_ENUMERATION_BUDGET.maximumMapEdgesInspected, 'maximumMapEdgesInspected'),
        maximumLocalEdgesVisited: budgetValue(overrides.maximumLocalEdgesVisited
            ?? DEFAULT_LOCAL_COMMAND_ENUMERATION_BUDGET.maximumLocalEdgesVisited, 'maximumLocalEdgesVisited'),
        maximumCandidates: budgetValue(overrides.maximumCandidates ?? DEFAULT_LOCAL_COMMAND_ENUMERATION_BUDGET.maximumCandidates, 'maximumCandidates'),
        maximumValidations: budgetValue(overrides.maximumValidations ?? DEFAULT_LOCAL_COMMAND_ENUMERATION_BUDGET.maximumValidations, 'maximumValidations'),
    });
}
function freezeWork(values, guardReasons) {
    const reasons = Object.freeze([...guardReasons]);
    return Object.freeze({ ...values, guardHit: reasons.length > 0, guardReasons: reasons });
}
/**
 * Enumerates one complete CommandElement against only its adjacent map nodes,
 * plus the one additional edge allowed by the atomic allied-transit rule.
 * It intentionally avoids arbitrary member subsets and the node-by-node Cartesian
 * product that would make large-map AI work scale with every node on the board.
 */
export function enumerateLocalMoveOrAttackCommands(state, factionId, budgetOverrides = {}) {
    const budget = resolveBudget(budgetOverrides);
    const allElements = Object.values(state.organization.commandElements)
        .sort((left, right) => (String(left.nodeId).localeCompare(String(right.nodeId))
        || left.elementId.localeCompare(right.elementId)));
    const factionKnown = Object.hasOwn(state.factions, factionId);
    const guardReasons = [];
    const markGuard = (reason) => {
        if (!guardReasons.includes(reason))
            guardReasons.push(reason);
    };
    let commandElementsInspected = 0;
    const eligibleElements = [];
    for (const element of allElements) {
        if (commandElementsInspected >= budget.maximumCommandElementsInspected) {
            markGuard('maximumCommandElementsInspected');
            break;
        }
        commandElementsInspected += 1;
        if (element.factionId === factionId)
            eligibleElements.push(element);
    }
    const adjacency = new Map();
    let mapEdgesInspected = 0;
    for (const edge of state.map.edges) {
        if (mapEdgesInspected >= budget.maximumMapEdgesInspected) {
            markGuard('maximumMapEdgesInspected');
            break;
        }
        mapEdgesInspected += 1;
        const fromA = adjacency.get(edge.a) ?? new Set();
        const fromB = adjacency.get(edge.b) ?? new Set();
        fromA.add(edge.b);
        fromB.add(edge.a);
        adjacency.set(edge.a, fromA);
        adjacency.set(edge.b, fromB);
    }
    const legalCommands = [];
    const origins = new Set();
    let localEdgesVisited = 0;
    let candidatesBuilt = 0;
    let validations = 0;
    let rejected = 0;
    let validationErrors = 0;
    let stop = !factionKnown;
    for (const element of eligibleElements) {
        if (stop)
            break;
        origins.add(element.nodeId);
        const directTargets = [...(adjacency.get(element.nodeId) ?? [])]
            .sort((left, right) => String(left).localeCompare(String(right)));
        const directTargetSet = new Set(directTargets);
        const candidatePaths = directTargets
            .map((targetNodeId) => ({ targetNodeId }));
        const seenTransitTargets = new Set();
        for (const viaNodeId of directTargets) {
            const occupiers = nodeOccupyingFactions(state, viaNodeId);
            if (occupiers.length !== 1
                || occupiers[0] === factionId
                || relationBetween(state, factionId, occupiers[0] ?? factionId) !== 'allied')
                continue;
            const secondTargets = [...(adjacency.get(viaNodeId) ?? [])]
                .sort((left, right) => String(left).localeCompare(String(right)));
            for (const targetNodeId of secondTargets) {
                if (targetNodeId === element.nodeId
                    || directTargetSet.has(targetNodeId)
                    || seenTransitTargets.has(targetNodeId))
                    continue;
                seenTransitTargets.add(targetNodeId);
                candidatePaths.push({ targetNodeId, viaNodeId });
            }
        }
        for (const path of candidatePaths) {
            if (localEdgesVisited >= budget.maximumLocalEdgesVisited) {
                markGuard('maximumLocalEdgesVisited');
                stop = true;
                break;
            }
            localEdgesVisited += 1;
            if (candidatesBuilt >= budget.maximumCandidates) {
                markGuard('maximumCandidates');
                stop = true;
                break;
            }
            if (validations >= budget.maximumValidations) {
                markGuard('maximumValidations');
                stop = true;
                break;
            }
            const command = {
                type: 'MOVE_OR_ATTACK',
                factionId,
                pieceIds: [...element.memberIds].sort((left, right) => left.localeCompare(right)),
                originNodeId: element.nodeId,
                targetNodeId: path.targetNodeId,
                ...(path.viaNodeId ? { viaNodeId: path.viaNodeId } : {}),
            };
            candidatesBuilt += 1;
            validations += 1;
            try {
                const validation = validateCommand(state, command);
                if (!validation.ok) {
                    rejected += 1;
                    continue;
                }
                const frozenPieceIds = [...command.pieceIds];
                Object.freeze(frozenPieceIds);
                const frozenCommand = {
                    ...command,
                    pieceIds: frozenPieceIds,
                };
                Object.freeze(frozenCommand);
                legalCommands.push(Object.freeze({
                    commandElementId: element.elementId,
                    command: frozenCommand,
                    validation: Object.freeze({
                        actualPieceIds: Object.freeze([...(validation.actualPieceIds ?? command.pieceIds)]),
                        isBattle: validation.isBattle ?? false,
                        commandLoad: validation.commandLoad ?? 0,
                        deploymentSize: validation.deploymentSize ?? 0,
                        encounterCost: validation.encounterCost ?? 0,
                    }),
                }));
            }
            catch {
                validationErrors += 1;
            }
        }
    }
    const work = freezeWork({
        factionKnown,
        commandElementsAvailable: allElements.length,
        commandElementsInspected,
        eligibleCommandElements: eligibleElements.length,
        distinctOrigins: origins.size,
        mapEdgesAvailable: state.map.edges.length,
        mapEdgesInspected,
        localEdgesVisited,
        candidatesBuilt,
        validations,
        rejected,
        validationErrors,
    }, guardReasons);
    return Object.freeze({ legalCommands: Object.freeze(legalCommands), work });
}
//# sourceMappingURL=command-enumerator.js.map