import type { BattleRecord } from '../battle/types.js';
import type { ArenaFormationId, EncounterDistanceBand } from '../strategy/definitions.js';

/** Runtime faction identity is authored by the validated scenario. */
export type FactionId = string;
declare const runtimeNodeIdBrand: unique symbol;

/** Runtime node identity comes from a validated MapDefinition, never a fixed TypeScript union. */
export type NodeId = string & { readonly [runtimeNodeIdBrand]?: 'node' };

export type CardId = 12 | 13 | 14 | 15 | 82 | 83 | 84 | 85 | 111 | 112 | 113;
export type BehaviorId = 'assault' | 'sniper' | 'ammo' | 'heavy';
export type PowerTier = 'T1 基础兵' | 'T2 精锐级' | 'T3 Boss级';
export type PromotionId = '基础训练' | '强化药剂' | '超级血清';
export type Difficulty = 'easy' | 'normal' | 'hard' | 'extreme';
export type PresetId = 'standard' | 'all-units';

export type Phase =
  | 'FIRST_FACTION_ACTION'
  | 'SECOND_FACTION_ACTION'
  | 'SETTLEMENT_PLANNING'
  | 'GAME_OVER';

export interface RangeValue {
  min: number;
  max: number;
}

export interface AuditOnlyStats {
  dodgeRate: RangeValue | null;
  toughness: number | null;
  magicResistance: Record<string, number> | null;
  equipmentDefense: number | null;
  weight: number | null;
}

export interface CardDefinition {
  cardId: CardId;
  unitTypeId: number;
  identifier: string;
  displayName: string;
  sourceCategory: string;
  powerTier: PowerTier;
  tags: string[];
  statRanges: {
    hp: RangeValue;
    unarmedAttack: RangeValue;
    baseDefense: RangeValue;
    speed: RangeValue;
  };
  expRange: RangeValue;
  auditOnlyStats: AuditOnlyStats;
  allowedPromotions: PromotionId[];
  productionCost: number;
  populationCost: number;
  buildRounds: number;
  deploymentLevel: number;
  behaviorId: BehaviorId;
  formationRank: number;
  sourceRefs: string[];
  snapshotExtractedAt: string;
  sourceAudit: Record<string, unknown>;
}

/** Node semantics are authored by MapDefinition; renderers may style known values specially. */
export type NodeKind = string;

export interface NodeConfig {
  nodeId: NodeId;
  displayName: string;
  kind: NodeKind;
  capacity: number;
  attackWidth: number;
  defenseWidth: number;
  strategicValue: number;
  goldIncome: number;
  population: number;
  apBonus: number;
  productionSlots: number;
  defenseBonus: number;
  encounterProfileRef: string;
  distanceBand: EncounterDistanceBand;
  spawnDistance: number;
  sectorId?: string;
  x: number;
  y: number;
}

export interface NodeState extends NodeConfig {
  ownerFactionId: FactionId | null;
  activeFromRound: number | null;
  pieceIds: string[];
}

export interface Edge {
  a: NodeId;
  b: NodeId;
}

export interface CardState {
  level: number;
  xpIntoLevel: number;
  totalXpAllocated: number;
  purchasedPromotions: PromotionId[];
  promotedThisSettlement: boolean;
  producedCount: number;
  lostCount: number;
}

export type ProductionOrderStatus = 'building' | 'waiting_deployment';

export interface ProductionOrder {
  orderId: string;
  factionId: FactionId;
  nodeId: NodeId;
  slotId: string;
  cardId: CardId;
  remainingRounds: number;
  status: ProductionOrderStatus;
  populationCost: number;
  goldCost: number;
  enqueuedRound: number;
}

export interface ProductionSlot {
  slotId: string;
  nodeId: NodeId;
  orders: ProductionOrder[];
}

export interface FactionState {
  factionId: FactionId;
  displayName: string;
  controller: 'player' | 'ai';
  victoryGroupId: string;
  commandPostNodeId: NodeId;
  defeatedAtRound: number | null;
  defeatReason: 'command_post_captured' | 'surrendered' | 'eliminated' | null;
  gold: number;
  xpPool: number;
  populationUsed: number;
  populationReserved: number;
  populationCap: number;
  scenarioPopulationBonus: number;
  actionPoints: number;
  apGeneratedThisRound: number;
  apSpentThisRound: number;
  apLedger: {
    baseGenerated: number;
    fieldGenerated: number;
    baseRemaining: number;
    fieldRemaining: number;
    baseSpent: number;
    fieldSpent: number;
  };
  cards: Record<CardId, CardState>;
  productionQueues: Partial<Record<NodeId, ProductionSlot[]>>;
  planningCommitted: boolean;
}

export interface PieceState {
  pieceId: string;
  factionId: FactionId;
  cardId: CardId;
  nodeId: NodeId;
  hp: number;
  maxHp: number;
  commandReadyFromRound: number;
  failedAssaultLocks: NodeId[];
  createdRound: number;
  productionGoldValue: number;
  movesThisRound: number;
  battlesThisRound: number;
  maxDistanceInRound: number;
}

export type StrategicRelation = 'allied' | 'neutral' | 'hostile';

export interface VictoryGroupState {
  victoryGroupId: string;
  displayName: string;
  factionIds: FactionId[];
}

export type CommanderRole = 'boss_unique' | 'player_avatar';
export type CommanderStatus = 'fielded' | 'downed' | 'rear' | 'available' | 'queued';

export interface CommanderState {
  commanderId: string;
  characterId: string;
  factionId: FactionId;
  role: CommanderRole;
  cardId: CardId;
  status: CommanderStatus;
  pieceInstanceId: string | null;
  nodeId: NodeId | null;
  apContribution: number;
  productionGoldCost: number;
  productionRounds: number;
  remainingProductionRounds: number;
  readyFromRound: number;
}

export type CommandElementKind = 'singleton' | 'task_group';

export interface CommandElementState {
  elementId: string;
  kind: CommandElementKind;
  factionId: FactionId;
  nodeId: NodeId;
  memberIds: string[];
  formationProfileId: ArenaFormationId;
  taskGroupTemplateId: string | null;
  createdRound: number;
  reorganizedAtCommand: number;
}

export interface OrganizationRuntimeState {
  definitionId: string;
  rulesVersion: string;
  configDigest: string;
  nextCommandElementOrdinal: number;
  commandElements: Record<string, CommandElementState>;
  memberToElementId: Record<string, string>;
}

export interface EncounterRuntimeState {
  definitionId: string;
  rulesVersion: string;
  configDigest: string;
}

export interface CasualtyEntry {
  casualtyId: string;
  strategicRound: number;
  battleId: string;
  deadPieceId: string;
  deadFactionId: FactionId;
  killerFactionId: FactionId;
  cardId: CardId;
  frozenCardLevel: number;
  bounty: number;
  killerXp: number;
  loserXp: number;
  settled: boolean;
}

export type NodeCaptureCause = 'direct_end_turn' | 'encirclement_turn_start';

export interface GameEvent {
  eventId: string;
  strategicRound: number;
  commandSequence: number;
  type:
    | 'game_started'
    | 'round_started'
    | 'move'
    | 'battle_resolved'
    | 'piece_died'
    | 'node_captured'
    | 'recovery'
    | 'income'
    | 'xp_settled'
    | 'xp_allocated'
    | 'card_level_up'
    | 'promotion_purchased'
    | 'production_enqueued'
    | 'production_cancelled'
    | 'production_progressed'
    | 'piece_deployed'
    | 'task_group_merged'
    | 'task_group_split'
    | 'formation_changed'
    | 'faction_defeated'
    | 'surrender_cleanup'
    | 'commander_downed'
    | 'commander_evacuated'
    | 'commander_production_enqueued'
    | 'commander_redeployed'
    | 'action_ended'
    | 'planning_committed'
    | 'game_over';
  factionId?: FactionId;
  nodeId?: NodeId;
  pieceId?: string;
  cardId?: CardId;
  amount?: number;
  captureCause?: NodeCaptureCause;
  message: string;
  data?: Record<string, unknown>;
}

export interface GameResult {
  winner: FactionId | 'draw';
  winningVictoryGroupId: string | null;
  reason: 'elimination' | 'round_limit' | 'command_post_captured';
  reasonCode:
    | 'AllHostileVictoryGroupsEliminated'
    | 'VictoryGroupEliminated'
    | 'CommandPostCaptured'
    | 'RoundLimitScore';
  decidedAtRound: number;
  score?: Record<FactionId, [number, number, number, number]>;
  survivingFactionIds: FactionId[];
  capturedCommandPostNodeIds: NodeId[];
  commanderStates: Record<string, CommanderStatus>;
}

export interface RecordedCommand {
  sequence: number;
  command: GameCommand;
}

export interface GameState {
  schemaVersion: 1;
  rulesVersion: string;
  configDigest: string;
  scenarioId: string;
  mapDefinitionId: string;
  mapPresentationId: string;
  encounter: EncounterRuntimeState;
  gameSeed: string;
  difficulty: Difficulty;
  preset: PresetId;
  playerFactionId: FactionId;
  turnOrder: FactionId[];
  activeTurnIndex: number;
  scenarioBaseAp: number;
  relations: Record<FactionId, Record<FactionId, StrategicRelation>>;
  victoryGroups: Record<string, VictoryGroupState>;
  commanders: Record<string, CommanderState>;
  capturedCommandPostNodeIds: NodeId[];
  strategicRound: number;
  phase: Phase;
  initiativeFactionId: FactionId;
  activeFactionId: FactionId | null;
  commandSequence: number;
  battleOrdinal: number;
  nextPieceOrdinal: number;
  nextOrderOrdinal: number;
  nextEventOrdinal: number;
  map: {
    nodes: Record<NodeId, NodeState>;
    edges: Edge[];
  };
  factions: Record<FactionId, FactionState>;
  pieces: Record<string, PieceState>;
  organization: OrganizationRuntimeState;
  casualtyLedger: CasualtyEntry[];
  eventLog: GameEvent[];
  battles: BattleRecord[];
  commandHistory: RecordedCommand[];
  result: GameResult | null;
  diagnostics: {
    invalidCommandCount: number;
    maxCommandsGuardHit: boolean;
  };
}

export type MoveOrAttackCommand = {
  type: 'MOVE_OR_ATTACK';
  factionId: FactionId;
  pieceIds: string[];
  originNodeId: NodeId;
  targetNodeId: NodeId;
  /** Optional atomic allied transit: origin -> via allied node -> target. */
  viaNodeId?: NodeId;
};

export type EndActionCommand = {
  type: 'END_ACTION';
  factionId: FactionId;
};

export type AllocateXpCommand = {
  type: 'ALLOCATE_XP';
  factionId: FactionId;
  cardId: CardId;
  amount: number;
};

export type PurchasePromotionCommand = {
  type: 'PURCHASE_PROMOTION';
  factionId: FactionId;
  cardId: CardId;
  promotionId: PromotionId;
};

export type EnqueueProductionCommand = {
  type: 'ENQUEUE_PRODUCTION';
  factionId: FactionId;
  nodeId: NodeId;
  slotId: string;
  cardId: CardId;
};

export type CancelProductionCommand = {
  type: 'CANCEL_PRODUCTION';
  factionId: FactionId;
  nodeId: NodeId;
  slotId: string;
  orderId: string;
};

export type CommitPlanningCommand = {
  type: 'COMMIT_PLANNING';
  factionId: FactionId;
};

export type MergeTaskGroupCommand = {
  type: 'MERGE_TASK_GROUP';
  factionId: FactionId;
  nodeId: NodeId;
  commandElementIds: string[];
  taskGroupTemplateId: string;
  formationProfileId: ArenaFormationId;
};

export type SplitTaskGroupCommand = {
  type: 'SPLIT_TASK_GROUP';
  factionId: FactionId;
  nodeId: NodeId;
  commandElementId: string;
  memberIds: string[];
};

export type SetFormationCommand = {
  type: 'SET_FORMATION';
  factionId: FactionId;
  nodeId: NodeId;
  commandElementId: string;
  formationProfileId: ArenaFormationId;
};

export type EnqueueCommanderProductionCommand = {
  type: 'ENQUEUE_COMMANDER_PRODUCTION';
  factionId: FactionId;
  commanderId: string;
};

export type RedeployPlayerAvatarCommand = {
  type: 'REDEPLOY_PLAYER_AVATAR';
  factionId: FactionId;
  commanderId: string;
  nodeId: NodeId;
};

export type GameCommand =
  | MoveOrAttackCommand
  | EndActionCommand
  | AllocateXpCommand
  | PurchasePromotionCommand
  | EnqueueProductionCommand
  | CancelProductionCommand
  | CommitPlanningCommand
  | MergeTaskGroupCommand
  | SplitTaskGroupCommand
  | SetFormationCommand
  | EnqueueCommanderProductionCommand
  | RedeployPlayerAvatarCommand;

export type ValidationReasonCode =
  | 'game_over'
  | 'action_phase_required'
  | 'active_faction_mismatch'
  | 'node_unknown'
  | 'origin_equals_target'
  | 'target_not_adjacent'
  | 'allied_transit_invalid'
  | 'allied_destination_forbidden'
  | 'neutral_attack_forbidden'
  | 'hostile_garrison_ambiguous'
  | 'selection_empty'
  | 'selection_duplicate'
  | 'piece_unavailable'
  | 'piece_wrong_faction'
  | 'piece_wrong_origin'
  | 'mixed_garrison_state'
  | 'attack_width_exceeded'
  | 'assault_reentry_locked'
  | 'action_points_insufficient'
  | 'garrison_capacity_full'
  | 'command_element_partial_selection'
  | 'reorganization_selection_invalid'
  | 'reorganization_wrong_node'
  | 'task_group_template_mismatch'
  | 'formation_unknown'
  | 'formation_mix_unsupported'
  | 'planning_phase_required'
  | 'planning_already_committed'
  | 'xp_amount_invalid'
  | 'xp_insufficient'
  | 'card_unknown'
  | 'promotion_already_purchased_this_round'
  | 'promotion_complete'
  | 'promotion_sequence_required'
  | 'card_level_insufficient'
  | 'military_funds_insufficient'
  | 'production_node_invalid'
  | 'production_node_unavailable'
  | 'production_slot_missing'
  | 'population_capacity_insufficient'
  | 'production_order_missing'
  | 'production_order_mismatch'
  | 'production_order_locked'
  | 'production_reservation_invalid'
  | 'faction_unknown'
  | 'faction_defeated'
  | 'commander_unknown'
  | 'commander_state_invalid'
  | 'command_post_required';

export type ValidationReasonParams = Readonly<Record<string, string | number | boolean>>;

export interface CommandResult {
  ok: boolean;
  state: GameState;
  reasonCode?: ValidationReasonCode;
  reasonParams?: ValidationReasonParams;
  /** Technical compatibility text. Player-facing presenters must use reasonCode. */
  error?: string;
  battleId?: string;
}
