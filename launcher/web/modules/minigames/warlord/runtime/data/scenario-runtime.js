import { DEMO_2_ALLIED_PACT_FACTIONS, DEMO_2_COMMANDER_CARD_BY_FACTION, } from './demo2.js';
import { createDefaultRelations, createDefaultVictoryGroups } from '../core/factions.js';
function factionIds(bundle) {
    return bundle.scenario.turnOrder.map((factionId) => factionId);
}
function displayNames(bundle) {
    return Object.fromEntries(bundle.scenario.factions.map((faction) => [faction.id, faction.displayName]));
}
function defaultRules(bundle) {
    const ids = factionIds(bundle);
    return {
        relations: createDefaultRelations(ids),
        victoryGroups: createDefaultVictoryGroups(ids, displayNames(bundle)),
        commanders: {},
    };
}
export function scenarioRuntimeRules(bundle) {
    const defaults = defaultRules(bundle);
    if (bundle.scenario.id !== 'warlord_demo_02_v1')
        return defaults;
    const [pactA, pactB] = DEMO_2_ALLIED_PACT_FACTIONS;
    defaults.relations[pactA][pactB] = 'allied';
    defaults.relations[pactB][pactA] = 'allied';
    delete defaults.victoryGroups[pactA];
    delete defaults.victoryGroups[pactB];
    defaults.victoryGroups['victory-group.pact'] = {
        victoryGroupId: 'victory-group.pact',
        displayName: '南北盟约',
        factionIds: [pactA, pactB],
    };
    const characterByFaction = {
        player: 'character.player-avatar',
        'boss-pact-a': 'character.itinerant',
        'boss-independent': 'character.surveyor',
        'boss-pact-b': 'character.gazer',
    };
    for (const definition of bundle.scenario.factions) {
        const factionId = definition.id;
        const cardId = DEMO_2_COMMANDER_CARD_BY_FACTION[factionId];
        const characterId = characterByFaction[factionId];
        if (cardId === undefined || characterId === undefined) {
            throw new Error(`Demo 2 commander profile is incomplete for ${factionId}.`);
        }
        const commanderId = `commander.${factionId}`;
        defaults.commanders[commanderId] = {
            commanderId,
            characterId,
            factionId,
            role: definition.controller === 'player' ? 'player_avatar' : 'boss_unique',
            cardId,
            status: 'fielded',
            pieceInstanceId: null,
            nodeId: definition.headquartersNodeRef,
            apContribution: 1,
            productionGoldCost: definition.controller === 'player' ? 0 : 180,
            productionRounds: definition.controller === 'player' ? 0 : 4,
            remainingProductionRounds: 0,
            readyFromRound: 1,
        };
    }
    return defaults;
}
//# sourceMappingURL=scenario-runtime.js.map