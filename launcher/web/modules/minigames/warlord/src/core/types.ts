import type { BattleRecord } from '../battle/types.js';

export type FactionId = 'red' | 'blue';
export type NodeId =
  | 'R-HQ'
  | 'R-Supply'
  | 'R-Economy'
  | 'North-Choke'
  | 'Center-Command'
  | 'South-Depot'
  | 'B-Economy'
  | 'B-Supply'
  | 'B-HQ';

export type CardId = 12 | 13 | 14 | 15 | 82 | 83 | 84 | 85;
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

export type NodeKind = 'hq' | 'supply' | 'economy' | 'choke' | 'command' | 'depot';

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
  gold: number;
  xpPool: number;
  populationUsed: number;
  populationReserved: number;
  populationCap: number;
  scenarioPopulationBonus: number;
  actionPoints: number;
  apGeneratedThisRound: number;
  apSpentThisRound: number;
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
    | 'action_ended'
    | 'planning_committed'
    | 'game_over';
  factionId?: FactionId;
  nodeId?: NodeId;
  pieceId?: string;
  cardId?: CardId;
  amount?: number;
  message: string;
  data?: Record<string, unknown>;
}

export interface GameResult {
  winner: FactionId | 'draw';
  reason: 'elimination' | 'round_limit';
  decidedAtRound: number;
  score?: Record<FactionId, [number, number, number, number]>;
}

export interface RecordedCommand {
  sequence: number;
  command: GameCommand;
}

export interface GameState {
  schemaVersion: 1;
  rulesVersion: string;
  configDigest: string;
  gameSeed: string;
  difficulty: Difficulty;
  preset: PresetId;
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

export type GameCommand =
  | MoveOrAttackCommand
  | EndActionCommand
  | AllocateXpCommand
  | PurchasePromotionCommand
  | EnqueueProductionCommand
  | CancelProductionCommand
  | CommitPlanningCommand;

export interface CommandResult {
  ok: boolean;
  state: GameState;
  error?: string;
  battleId?: string;
}
