import type { RuntimeMapBundle } from './map.js';
import {
  DEMO_2_ALLIED_PACT_FACTIONS,
  DEMO_2_COMMANDER_CARD_BY_FACTION,
} from './demo2.js';
import { createDefaultRelations, createDefaultVictoryGroups } from '../core/factions.js';
import type {
  CardId,
  CommanderState,
  FactionId,
  NodeId,
  StrategicRelation,
  VictoryGroupState,
} from '../core/types.js';

export interface ScenarioRuntimeRules {
  readonly relations: Record<FactionId, Record<FactionId, StrategicRelation>>;
  readonly victoryGroups: Record<string, VictoryGroupState>;
  readonly commanders: Record<string, CommanderState>;
}

function factionIds(bundle: RuntimeMapBundle): FactionId[] {
  return bundle.scenario.turnOrder.map((factionId) => factionId as FactionId);
}

function displayNames(bundle: RuntimeMapBundle): Record<string, string> {
  return Object.fromEntries(bundle.scenario.factions.map((faction) => [faction.id, faction.displayName]));
}

function defaultRules(bundle: RuntimeMapBundle): ScenarioRuntimeRules {
  const ids = factionIds(bundle);
  return {
    relations: createDefaultRelations(ids),
    victoryGroups: createDefaultVictoryGroups(ids, displayNames(bundle)),
    commanders: {},
  };
}

export function scenarioRuntimeRules(bundle: RuntimeMapBundle): ScenarioRuntimeRules {
  const defaults = defaultRules(bundle);
  if (bundle.scenario.id !== 'warlord_demo_02_v1') return defaults;

  const [pactA, pactB] = DEMO_2_ALLIED_PACT_FACTIONS as readonly [FactionId, FactionId];
  defaults.relations[pactA]![pactB] = 'allied';
  defaults.relations[pactB]![pactA] = 'allied';

  delete defaults.victoryGroups[pactA];
  delete defaults.victoryGroups[pactB];
  defaults.victoryGroups['victory-group.pact'] = {
    victoryGroupId: 'victory-group.pact',
    displayName: '南北盟约',
    factionIds: [pactA, pactB],
  };

  const characterByFaction: Readonly<Record<string, string>> = {
    player: 'character.player-avatar',
    'boss-pact-a': 'character.itinerant',
    'boss-independent': 'character.surveyor',
    'boss-pact-b': 'character.gazer',
  };
  for (const definition of bundle.scenario.factions) {
    const factionId = definition.id as FactionId;
    const cardId = DEMO_2_COMMANDER_CARD_BY_FACTION[factionId] as CardId | undefined;
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
      nodeId: definition.headquartersNodeRef as NodeId,
      apContribution: 1,
      productionGoldCost: definition.controller === 'player' ? 0 : 180,
      productionRounds: definition.controller === 'player' ? 0 : 4,
      remainingProductionRounds: 0,
      readyFromRound: 1,
    };
  }
  return defaults;
}
