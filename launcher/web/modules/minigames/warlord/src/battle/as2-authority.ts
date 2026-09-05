import type {
  BattleAuthorityAudit,
  BattleCasualty,
  BattleEvent,
  BattlePieceResult,
  BattleRecord,
  BattleUnitSnapshot,
} from './types.js';
import { createBattleIdentity } from './identity.js';
import { addGameEvent } from '../core/events.js';
import { requireNode } from '../core/access.js';
import { canonicalJson, sha256Canonical } from '../core/canonical.js';
import { commanderForPiece, handleCommanderCasualtyInPlace } from '../core/commanders.js';
import {
  auditEncounterState,
  frozenStateHasAnyEncounterFields,
} from '../core/encounter.js';
import { requireFaction, spendFactionActionPointsInPlace } from '../core/factions.js';
import { bounty, getRuntimeStats } from '../core/math.js';
import {
  auditOrganizationState,
  createOrganizationRuntimeState,
  registerOrganizationMemberInPlace,
} from '../core/organization.js';
import { movePiecesInPlace, removePieceInPlace } from '../core/pieces.js';
import { piecesAtNode } from '../core/selectors.js';
import type {
  Difficulty,
  FactionId,
  GameState,
  MoveOrAttackCommand,
  PresetId,
} from '../core/types.js';
import { validateCommand } from '../core/validator.js';
import { getCardDefinition } from '../data/cards.js';
import type { MapThemeId } from '../scene/map-theme.js';

export const AS2_BATTLE_REQUEST_SCHEMA = 'warlord.as2-battle-request.v1' as const;
export const AS2_BATTLE_RECEIPT_SCHEMA = 'warlord.as2-battle-receipt.v2' as const;
export const AS2_RESUME_SCHEMA = 'warlord.as2-resume.v1' as const;
export const AS2_BATTLE_HANDOFF_EVENT_LOG_LIMIT = 32;
export const AS2_BATTLE_REQUEST_SOFT_LIMIT_BYTES = 384 * 1024;

const OPAQUE_ID = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;

export interface As2BattleClientContext {
  seed: string;
  preset: PresetId;
  difficulty: Difficulty;
  mapTheme: MapThemeId;
  forceWebglFailure: boolean;
  aiSeenTransitions: string[];
}

export interface As2BattleRequest {
  schema: typeof AS2_BATTLE_REQUEST_SCHEMA;
  sessionId: string;
  requestId: string;
  state: GameState;
  command: MoveOrAttackCommand;
  clientContext: As2BattleClientContext;
}

export interface As2BattleEnvelope {
  type: 'panel';
  panel: 'warlord';
  cmd: 'battle_start';
  panelInstanceId: string;
  callId: string;
  inputDigest: string;
  request: As2BattleRequest;
}

export interface As2ResumeEnvelope {
  schema: typeof AS2_RESUME_SCHEMA;
  request: As2BattleRequest;
  state: GameState;
  command: MoveOrAttackCommand;
  inputDigest: string;
  receipt: unknown;
  clientContext: As2BattleClientContext;
  handoffError?: string;
}

export interface ApplyAs2ResumeResult {
  ok: boolean;
  state: GameState | null;
  battleRecord?: BattleRecord;
  error?: string;
  resultUnknown: boolean;
}

interface NormalizedUnitReceiptBase {
  pieceId: string;
  factionId: FactionId;
  projectionKind: 'pet_projection' | 'player_avatar';
  frozenCardLevel: number;
  startMaxHp: number;
  remainHp: number;
  hpPermille: number;
  alive: boolean;
}

interface NormalizedPetUnitReceipt extends NormalizedUnitReceiptBase {
  projectionKind: 'pet_projection';
  petId: number;
  identifier: string;
  level: number;
  strategicPromotions: string[];
}

interface NormalizedPlayerAvatarUnitReceipt extends NormalizedUnitReceiptBase {
  projectionKind: 'player_avatar';
  commanderId: string;
  characterId: string;
  runtimeLevel: number;
}

type NormalizedUnitReceipt = NormalizedPetUnitReceipt | NormalizedPlayerAvatarUnitReceipt;

const PET_UNIT_RECEIPT_KEYS = [
  'alive', 'factionId', 'hpPermille', 'identifier', 'level', 'petId', 'pieceId',
  'projectionKind', 'remainHp', 'resolvedType', 'startMaxHp', 'strategicPromotions',
] as const;
const PLAYER_AVATAR_UNIT_RECEIPT_KEYS = [
  'alive', 'characterId', 'commanderId', 'factionId', 'hpPermille', 'pieceId',
  'projectionKind', 'remainHp', 'runtimeLevel', 'startMaxHp',
] as const;
const ECONOMY_OBSERVATION_KEYS = [
  'attacker', 'catalogAuthority', 'catalogCurrencyUnit', 'catalogPriceBasis',
  'currentAs2SessionPriceSampled', 'defender', 'mode', 'schema', 'settlementPolicy',
  'strategicCurrencyUnit', 'strategicValueBasis', 'writesPlayerState',
] as const;
const ECONOMY_SIDE_KEYS = [
  'catalogBaseExposureGold', 'catalogBaseExposureK', 'catalogBaseLostGold',
  'catalogBaseLostK', 'strategicExposureGold', 'strategicLostGold', 'units',
] as const;
const PET_ECONOMY_UNIT_KEYS = [
  'basePrice', 'catalogEligible', 'catalogName', 'hpPermille', 'identifier',
  'increasePrice', 'kPrice', 'lost', 'petId', 'pieceId', 'projectionKind',
  'rosterType', 'strategicGoldValue', 'strategicPromotions',
] as const;
const PLAYER_AVATAR_ECONOMY_UNIT_KEYS = [
  'catalogEligible', 'characterId', 'commanderId', 'hpPermille', 'lost', 'pieceId',
  'projectionKind', 'strategicGoldValue',
] as const;

export { canonicalJson, sha256Canonical } from '../core/canonical.js';

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function hasExactKeys(value: unknown, expected: readonly string[]): value is Record<string, unknown> {
  if (!isObject(value)) return false;
  const actual = Object.keys(value).sort();
  const canonical = [...expected].sort();
  return actual.length === canonical.length
    && actual.every((key, index) => key === canonical[index]);
}

function clone<T>(value: T): T {
  return structuredClone(value);
}

function projectStateForAs2BattleHandoff(value: GameState): GameState {
  const state = clone(value);
  state.battles = [];
  state.commandHistory = [];
  state.eventLog = state.eventLog.slice(-AS2_BATTLE_HANDOFF_EVENT_LOG_LIMIT);
  state.casualtyLedger = state.casualtyLedger.filter((entry) => !entry.settled);
  return state;
}

function jsonUtf8ByteLength(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function assertFrozenEncounterState(state: GameState, label: string): void {
  const raw = state as unknown as Record<string, unknown>;
  if (raw.encounter === undefined) {
    if (frozenStateHasAnyEncounterFields(state)) {
      throw new Error(`${label}：encounter_sidecar_missing_with_node_fields。`);
    }
    // A wholly absent sidecar is the frozen legacy contract. Preserve it byte-for-byte
    // so the Host can apply its explicit far/650 compatibility branch.
    return;
  }
  const encounterIssues = auditEncounterState(state);
  if (encounterIssues.length > 0) {
    throw new Error(`${label}：${encounterIssues[0]!.code}。`);
  }
}

function normalizedFrozenState(value: GameState): GameState {
  const state = clone(value);
  const raw = state as unknown as Record<string, unknown>;
  if (raw.organization === undefined) {
    state.organization = createOrganizationRuntimeState();
    const pieces = Object.values(state.pieces)
      .filter((piece) => piece.hp > 0)
      .sort((left, right) => left.pieceId.localeCompare(right.pieceId));
    for (const piece of pieces) registerOrganizationMemberInPlace(state, piece);
  } else if (!isObject(raw.organization)) {
    throw new Error('冻结战略态的 organization sidecar 非法。');
  }
  const issues = auditOrganizationState(state);
  if (issues.length > 0) {
    throw new Error(`冻结战略态的 organization sidecar 不一致：${issues[0]!.code}。`);
  }
  assertFrozenEncounterState(state, '冻结战略态的 encounter sidecar 不一致');
  return state;
}

function assertOpaque(value: string, label: string): void {
  if (!OPAQUE_ID.test(value)) throw new Error(`${label} 不是合法的不透明标识。`);
}

export function createAs2AuthoritySessionId(): string {
  const random = new Uint32Array(2);
  if (globalThis.crypto?.getRandomValues) globalThis.crypto.getRandomValues(random);
  else {
    random[0] = Math.floor(Math.random() * 0x1_0000_0000);
    random[1] = Math.floor(Math.random() * 0x1_0000_0000);
  }
  return `warlord.${Date.now().toString(36)}.${random[0]!.toString(36)}${random[1]!.toString(36)}`;
}

export async function buildAs2BattleEnvelope(input: {
  panelInstanceId: string;
  callId: string;
  sessionId: string;
  requestId: string;
  state: GameState;
  command: MoveOrAttackCommand;
  clientContext: As2BattleClientContext;
}): Promise<As2BattleEnvelope> {
  assertOpaque(input.panelInstanceId, 'panelInstanceId');
  assertOpaque(input.callId, 'callId');
  assertOpaque(input.sessionId, 'sessionId');
  assertOpaque(input.requestId, 'requestId');
  const validation = validateCommand(input.state, input.command);
  if (!validation.ok || validation.isBattle !== true) {
    throw new Error(validation.error ?? '只有真实交战命令可以交给 AS2。');
  }
  assertFrozenEncounterState(input.state, '接敌距离冻结输入不一致');
  const request: As2BattleRequest = {
    schema: AS2_BATTLE_REQUEST_SCHEMA,
    sessionId: input.sessionId,
    requestId: input.requestId,
    state: projectStateForAs2BattleHandoff(input.state),
    command: clone(input.command),
    clientContext: clone(input.clientContext),
  };
  const requestBytes = jsonUtf8ByteLength(request);
  if (requestBytes > AS2_BATTLE_REQUEST_SOFT_LIMIT_BYTES) {
    throw new Error(
      `AS2 战斗请求为 ${requestBytes} 字节，超过 Web 侧 ${AS2_BATTLE_REQUEST_SOFT_LIMIT_BYTES} 字节软上限。`,
    );
  }
  return {
    type: 'panel',
    panel: 'warlord',
    cmd: 'battle_start',
    panelInstanceId: input.panelInstanceId,
    callId: input.callId,
    inputDigest: await sha256Canonical(request),
    request,
  };
}

function isGameState(value: unknown): value is GameState {
  if (!isObject(value) || value.schemaVersion !== 1) return false;
  return isObject(value.map) && isObject(value.factions) && isObject(value.pieces)
    && Array.isArray(value.battles) && Array.isArray(value.commandHistory);
}

function isMoveCommand(value: unknown): value is MoveOrAttackCommand {
  if (!isObject(value) || value.type !== 'MOVE_OR_ATTACK') return false;
  return typeof value.factionId === 'string'
    && OPAQUE_ID.test(value.factionId)
    && Array.isArray(value.pieceIds)
    && value.pieceIds.every((pieceId) => typeof pieceId === 'string')
    && typeof value.originNodeId === 'string'
    && typeof value.targetNodeId === 'string';
}

function readResume(value: unknown): As2ResumeEnvelope | null {
  if (!isObject(value) || value.schema !== AS2_RESUME_SCHEMA) return null;
  if (!isObject(value.request) || value.request.schema !== AS2_BATTLE_REQUEST_SCHEMA) return null;
  if (!isGameState(value.state) || !isMoveCommand(value.command)) return null;
  const request = value.request;
  if (!isGameState(request.state) || !isMoveCommand(request.command) || !isObject(request.clientContext)) return null;
  if (typeof request.sessionId !== 'string' || typeof request.requestId !== 'string') return null;
  if (typeof value.inputDigest !== 'string') return null;
  return value as unknown as As2ResumeEnvelope;
}

export function frozenStateFromAs2Resume(value: unknown): GameState | null {
  const resume = readResume(value);
  return resume ? clone(resume.state) : null;
}

export function sessionIdFromAs2Resume(value: unknown): string | null {
  const resume = readResume(value);
  return resume && OPAQUE_ID.test(resume.request.sessionId) ? resume.request.sessionId : null;
}

function battleSnapshot(
  state: GameState,
  pieceId: string,
  encounterUnit: NormalizedUnitReceipt,
): BattleUnitSnapshot {
  const piece = state.pieces[pieceId];
  if (!piece) throw new Error(`冻结战略态缺少棋子 ${pieceId}。`);
  if (encounterUnit.pieceId !== pieceId
    || encounterUnit.factionId !== piece.factionId) {
    throw new Error(`冻结战略态与动作战斗身份不一致：${pieceId}。`);
  }
  const definition = getCardDefinition(piece.cardId);
  const cardState = requireFaction(state, piece.factionId).cards[piece.cardId];
  if (!cardState) throw new Error(`冻结战略态缺少 ${piece.factionId}/${piece.cardId} 的兵种状态。`);
  const stats = getRuntimeStats(piece.cardId, cardState);
  return {
    pieceId,
    factionId: piece.factionId,
    cardId: piece.cardId,
    encounterProjectionKind: encounterUnit.projectionKind,
    displayName: encounterUnit.projectionKind === 'player_avatar'
      ? '我方主角'
      : definition.displayName,
    behaviorId: definition.behaviorId,
    tags: [...definition.tags],
    formationRank: definition.formationRank,
    hp: piece.hp,
    maxHp: piece.maxHp,
    attack: stats.attack,
    defense: stats.defense,
    speed: stats.speed,
    frozenCardLevel: cardState.level,
  };
}

function normalizeUnits(
  raw: unknown,
  expectedIds: string[],
  expectedFactionId: FactionId,
  state: GameState,
  label: string,
): NormalizedUnitReceipt[] {
  if (!Array.isArray(raw) || raw.length !== expectedIds.length) {
    throw new Error(`${label}单位回执数量与冻结战略态不一致。`);
  }
  const byId = new Map<string, NormalizedUnitReceipt>();
  for (const candidate of raw) {
    if (!isObject(candidate)) throw new Error(`${label}单位回执格式非法。`);
    const pieceId = candidate.pieceId;
    const hpPermille = candidate.hpPermille;
    if (typeof pieceId !== 'string' || byId.has(pieceId)
      || typeof hpPermille !== 'number' || !Number.isInteger(hpPermille)
      || hpPermille < 0 || hpPermille > 1000
      || candidate.factionId !== expectedFactionId
      || typeof candidate.alive !== 'boolean') {
      throw new Error(`${label}单位回执字段非法或重复。`);
    }
    const piece = state.pieces[pieceId];
    if (!piece || piece.factionId !== expectedFactionId) {
      throw new Error(`${label}单位的棋子身份发生变化：${pieceId}。`);
    }
    const definition = getCardDefinition(piece.cardId);
    const cardState = requireFaction(state, piece.factionId).cards[piece.cardId];
    if (!cardState) throw new Error(`${label}单位缺少兵种状态：${pieceId}。`);
    const startMaxHp = candidate.startMaxHp;
    const remainHp = candidate.remainHp;
    if (typeof startMaxHp !== 'number' || !Number.isFinite(startMaxHp) || startMaxHp <= 0
      || typeof remainHp !== 'number' || !Number.isFinite(remainHp)
      || remainHp < 0 || remainHp > startMaxHp
      || candidate.alive !== (remainHp > 0)
      || candidate.alive !== (hpPermille > 0)) {
      throw new Error(`${label}单位的生命观测不一致：${pieceId}。`);
    }
    const expectedPermille = remainHp > 0
      ? Math.min(1000, Math.max(1, Math.round(remainHp * 1000 / startMaxHp))) : 0;
    if (hpPermille !== expectedPermille) {
      throw new Error(`${label}单位的生命比例不一致：${pieceId}。`);
    }

    if (candidate.projectionKind === 'pet_projection') {
      if (!hasExactKeys(candidate, PET_UNIT_RECEIPT_KEYS)
        || typeof candidate.petId !== 'number' || !Number.isInteger(candidate.petId)
        || piece.cardId !== candidate.petId
        || typeof candidate.identifier !== 'string'
        || candidate.identifier !== definition.identifier
        || candidate.resolvedType !== definition.identifier
        || typeof candidate.level !== 'number' || !Number.isInteger(candidate.level)
        || candidate.level !== cardState.level
        || !Array.isArray(candidate.strategicPromotions)
        || candidate.strategicPromotions.some((name) => typeof name !== 'string')
        || canonicalJson(candidate.strategicPromotions) !== canonicalJson(cardState.purchasedPromotions)) {
        throw new Error(`${label}单位的战宠目录身份发生变化：${pieceId}。`);
      }
      byId.set(pieceId, {
        pieceId,
        factionId: expectedFactionId,
        projectionKind: 'pet_projection',
        petId: candidate.petId,
        identifier: candidate.identifier,
        level: cardState.level,
        frozenCardLevel: cardState.level,
        strategicPromotions: [...candidate.strategicPromotions],
        startMaxHp,
        remainHp,
        hpPermille,
        alive: candidate.alive,
      });
      continue;
    }

    if (candidate.projectionKind === 'player_avatar') {
      const commander = commanderForPiece(state, pieceId);
      if (!hasExactKeys(candidate, PLAYER_AVATAR_UNIT_RECEIPT_KEYS)
        || !commander || commander.role !== 'player_avatar' || commander.status !== 'fielded'
        || commander.factionId !== expectedFactionId || commander.cardId !== piece.cardId
        || candidate.commanderId !== commander.commanderId
        || candidate.characterId !== commander.characterId
        || typeof candidate.runtimeLevel !== 'number' || !Number.isInteger(candidate.runtimeLevel)
        || candidate.runtimeLevel < 1 || candidate.runtimeLevel > 9999) {
        throw new Error(`${label}单位的玩家主角身份发生变化：${pieceId}。`);
      }
      byId.set(pieceId, {
        pieceId,
        factionId: expectedFactionId,
        projectionKind: 'player_avatar',
        commanderId: commander.commanderId,
        characterId: commander.characterId,
        runtimeLevel: candidate.runtimeLevel,
        frozenCardLevel: cardState.level,
        startMaxHp,
        remainHp,
        hpPermille,
        alive: candidate.alive,
      });
      continue;
    }
    throw new Error(`${label}单位投影类型非法：${pieceId}。`);
  }
  return expectedIds.map((pieceId) => {
    const result = byId.get(pieceId);
    if (!result) throw new Error(`${label}单位回执缺少 ${pieceId}。`);
    return result;
  });
}

function validateEconomyObservation(
  value: unknown,
  attackerUnits: NormalizedUnitReceipt[],
  defenderUnits: NormalizedUnitReceipt[],
  state: GameState,
): Record<string, unknown> {
  if (!hasExactKeys(value, ECONOMY_OBSERVATION_KEYS)
    || value.schema !== 'warlord.pet-economy-observation.v1'
    || value.mode !== 'observe_only'
    || value.writesPlayerState !== false
    || value.settlementPolicy !== 'none'
    || value.catalogAuthority !== 'data/merc/pets.xml'
    || value.catalogPriceBasis !== 'xml_base_price'
    || value.currentAs2SessionPriceSampled !== false
    || value.strategicValueBasis !== 'piece.productionGoldValue'
    || value.catalogCurrencyUnit !== 'player_gold'
    || value.strategicCurrencyUnit !== 'warlord_gold') {
    throw new Error('战宠经济观测契约缺失或试图声明玩家写入。');
  }
  const nonNegativeInteger = (candidate: unknown, label: string): number => {
    if (typeof candidate !== 'number' || !Number.isSafeInteger(candidate) || candidate < 0) {
      throw new Error(`${label}不是非负安全整数。`);
    }
    return candidate;
  };
  const verifySide = (side: unknown, expected: NormalizedUnitReceipt[], label: string): void => {
    if (!hasExactKeys(side, ECONOMY_SIDE_KEYS)
      || !Array.isArray(side.units) || side.units.length !== expected.length) {
      throw new Error(`${label}战宠经济观测数量不一致。`);
    }
    const expectedById = new Map(expected.map((unit) => [unit.pieceId, unit]));
    let catalogBaseExposureGold = 0;
    let catalogBaseLostGold = 0;
    let catalogBaseExposureK = 0;
    let catalogBaseLostK = 0;
    let strategicExposureGold = 0;
    let strategicLostGold = 0;
    for (const unit of side.units) {
      if (!isObject(unit) || typeof unit.pieceId !== 'string') {
        throw new Error(`${label}战宠经济观测格式非法。`);
      }
      const source = expectedById.get(unit.pieceId);
      const piece = state.pieces[unit.pieceId];
      if (!source || !piece || unit.projectionKind !== source.projectionKind
        || unit.hpPermille !== source.hpPermille || unit.lost !== !source.alive) {
        throw new Error(`${label}战宠经济观测与战斗回执不一致。`);
      }
      const strategicGoldValue = nonNegativeInteger(unit.strategicGoldValue, `${label}战旗价值`);
      if (strategicGoldValue !== piece.productionGoldValue) {
        throw new Error(`${label}战旗价值与冻结棋子不一致。`);
      }
      strategicExposureGold += strategicGoldValue;
      if (unit.lost) {
        strategicLostGold += strategicGoldValue;
      }
      if (source.projectionKind === 'player_avatar') {
        if (!hasExactKeys(unit, PLAYER_AVATAR_ECONOMY_UNIT_KEYS)
          || unit.catalogEligible !== false
          || unit.commanderId !== source.commanderId
          || unit.characterId !== source.characterId) {
          throw new Error(`${label}玩家主角经济观测身份不一致。`);
        }
      } else {
        if (!hasExactKeys(unit, PET_ECONOMY_UNIT_KEYS)
          || unit.catalogEligible !== true
          || unit.petId !== source.petId || unit.identifier !== source.identifier
          || typeof unit.catalogName !== 'string' || typeof unit.rosterType !== 'string'
          || canonicalJson(unit.strategicPromotions) !== canonicalJson(source.strategicPromotions)) {
          throw new Error(`${label}战宠经济观测目录身份不一致。`);
        }
        const basePrice = nonNegativeInteger(unit.basePrice, `${label}战宠基础价`);
        const kPrice = nonNegativeInteger(unit.kPrice, `${label}战宠K价`);
        nonNegativeInteger(unit.increasePrice, `${label}战宠涨价步长`);
        catalogBaseExposureGold += basePrice;
        catalogBaseExposureK += kPrice;
        if (unit.lost) {
          catalogBaseLostGold += basePrice;
          catalogBaseLostK += kPrice;
        }
      }
      expectedById.delete(unit.pieceId);
    }
    if (expectedById.size !== 0) throw new Error(`${label}战宠经济观测缺少单位。`);
    const expectedAggregates: Record<string, number> = {
      catalogBaseExposureGold,
      catalogBaseLostGold,
      catalogBaseExposureK,
      catalogBaseLostK,
      strategicExposureGold,
      strategicLostGold,
    };
    for (const [field, aggregate] of Object.entries(expectedAggregates)) {
      if (nonNegativeInteger(side[field], `${label}${field}`) !== aggregate) {
        throw new Error(`${label}战宠经济观测汇总不一致：${field}。`);
      }
    }
  };
  verifySide(value.attacker, attackerUnits, '进攻方');
  verifySide(value.defender, defenderUnits, '防守方');
  return clone(value);
}

function buildAuthorityEvents(
  battleId: string,
  winner: 'attacker' | 'defender',
  reason: 'wiped' | 'mutual_wipe' | 'battle_round_limit',
  casualties: BattleCasualty[],
  frames: number,
): BattleEvent[] {
  let ordinal = 0;
  const events: BattleEvent[] = casualties.map((casualty) => {
    ordinal += 1;
    return {
      eventId: `${battleId}:as2-e${ordinal}`,
      battleId,
      battleRound: 1,
      phase: 'system',
      type: 'death',
      targetPieceId: casualty.pieceId,
      targetFactionId: casualty.factionId,
      hpAfter: 0,
      message: `${casualty.pieceId} 在 AS2 实战中阵亡。`,
    };
  });
  ordinal += 1;
  events.push({
    eventId: `${battleId}:as2-e${ordinal}`,
    battleId,
    battleRound: 1,
    phase: 'system',
    type: 'battle_end',
    message: reason === 'battle_round_limit'
      ? `AS2 实战达到 ${frames} 帧上限，守方守住。`
      : reason === 'mutual_wipe'
        ? 'AS2 实战双方全灭，节点保持原所有者。'
        : `${winner === 'attacker' ? '进攻方' : '守方'}在 AS2 实战中歼灭对手。`,
  });
  return events;
}

function applyAcceptedReceipt(
  request: As2BattleRequest,
  receipt: Record<string, unknown>,
  frozenState: GameState,
): { state: GameState; record: BattleRecord } {
  const state = clone(frozenState);
  const command = clone(request.command);
  const validation = validateCommand(state, command);
  if (!validation.ok || validation.isBattle !== true) {
    throw new Error(validation.error ?? '恢复时战略命令已不再是合法交战。');
  }
  const attackerIds = [...(validation.actualPieceIds ?? command.pieceIds)];
  const defenderFactionId = validation.defenderFactionId;
  if (!defenderFactionId || !OPAQUE_ID.test(defenderFactionId)) {
    throw new Error('恢复时无法从冻结战略态确定唯一防守阵营。');
  }
  requireFaction(state, defenderFactionId);
  const defenderIds = piecesAtNode(state, command.targetNodeId, defenderFactionId)
    .map((piece) => piece.pieceId);
  if (defenderIds.length === 0) throw new Error('恢复时冻结战略态缺少防守单位。');
  const attackerUnits = normalizeUnits(
    receipt.attackerUnits,
    attackerIds,
    command.factionId,
    state,
    '进攻方',
  );
  const defenderUnits = normalizeUnits(
    receipt.defenderUnits,
    defenderIds,
    defenderFactionId,
    state,
    '防守方',
  );
  const playerControlledSides = [
    ...attackerUnits.filter((unit) => unit.projectionKind === 'player_avatar').map(() => 'blue'),
    ...defenderUnits.filter((unit) => unit.projectionKind === 'player_avatar').map(() => 'red'),
  ];
  const expectedPlayerControlledSide = playerControlledSides.length === 0
    ? 'none' : playerControlledSides.length === 1 ? playerControlledSides[0] : null;
  if (expectedPlayerControlledSide === null
    || receipt.playerControlledSide !== expectedPlayerControlledSide) {
    throw new Error('AS2 玩家控制侧与冻结指挥官身份不一致。');
  }
  const attackersDead = attackerUnits.every((unit) => !unit.alive);
  const defendersDead = defenderUnits.every((unit) => !unit.alive);
  if (!hasExactKeys(receipt.sideMap, ['blue', 'red'])
    || receipt.sideMap.blue !== 'attacker'
    || receipt.sideMap.red !== 'defender') {
    throw new Error('AS2 物理阵营映射与冻结进攻方向不一致。');
  }
  let winner: 'attacker' | 'defender';
  let reason: 'wiped' | 'mutual_wipe' | 'battle_round_limit';
  if (receipt.as2Status === 'timeout') {
    if (receipt.as2Winner !== 'timeout') {
      throw new Error('AS2 超时事实与原始 winner 不一致。');
    }
    winner = 'defender';
    reason = 'battle_round_limit';
  } else if (receipt.as2Status === 'finished') {
    if (attackersDead && defendersDead) {
      if (receipt.as2Winner !== 'draw') {
        throw new Error('AS2 双方全灭事实与原始 winner 不一致。');
      }
      winner = 'defender';
      reason = 'mutual_wipe';
    } else if (defendersDead && !attackersDead) {
      if (receipt.as2Winner !== 'blue') {
        throw new Error('AS2 守方全灭事实与原始 winner 不一致。');
      }
      winner = 'attacker';
      reason = 'wiped';
    } else if (attackersDead && !defendersDead) {
      if (receipt.as2Winner !== 'red') {
        throw new Error('AS2 进攻方全灭事实与原始 winner 不一致。');
      }
      winner = 'defender';
      reason = 'wiped';
    } else {
      throw new Error('AS2 finished 事实没有形成可提交的歼灭结果。');
    }
  } else {
    throw new Error('AS2 原始战斗状态非法。');
  }
  const frames = receipt.frames;
  const durationMs = receipt.durationMs;
  if (typeof frames !== 'number' || !Number.isInteger(frames) || frames < 0
    || typeof durationMs !== 'number' || !Number.isFinite(durationMs) || durationMs < 0) {
    throw new Error('AS2 时间观测字段非法。');
  }
  const economyObservation = validateEconomyObservation(
    receipt.economyObservation,
    attackerUnits,
    defenderUnits,
    state,
  );

  state.commandSequence += 1;
  state.commandHistory.push({ sequence: state.commandSequence, command: clone(command) });
  const faction = requireFaction(state, command.factionId);
  const commandLoad = validation.commandLoad ?? attackerIds.length;
  spendFactionActionPointsInPlace(faction, commandLoad);
  state.battleOrdinal += 1;
  const { battleId, seed } = createBattleIdentity({
    gameSeed: state.gameSeed,
    strategicRound: state.strategicRound,
    battleOrdinal: state.battleOrdinal,
    attackerIds,
    defenderIds,
  });
  const allUnits = [...attackerUnits, ...defenderUnits];
  const unitById = new Map(allUnits.map((unit) => [unit.pieceId, unit]));
  const attackerSnapshots = attackerIds.map((pieceId) => {
    const unit = unitById.get(pieceId);
    if (!unit) throw new Error(`AS2 回执缺少冻结棋子 ${pieceId}。`);
    return battleSnapshot(state, pieceId, unit);
  });
  const defenderSnapshots = defenderIds.map((pieceId) => {
    const unit = unitById.get(pieceId);
    if (!unit) throw new Error(`AS2 回执缺少冻结棋子 ${pieceId}。`);
    return battleSnapshot(state, pieceId, unit);
  });
  const pieceResults: BattlePieceResult[] = [...attackerIds, ...defenderIds]
    .map((pieceId) => {
      const piece = state.pieces[pieceId];
      const unit = unitById.get(pieceId);
      if (!piece || !unit) throw new Error(`AS2 回执缺少冻结棋子 ${pieceId}。`);
      const hpAfter = unit.alive
        ? Math.max(1, Math.round(piece.maxHp * unit.hpPermille / 1000)) : 0;
      return {
        pieceId,
        factionId: piece.factionId,
        cardId: piece.cardId,
        hpAfter,
        dead: !unit.alive,
        damageDealt: 0,
        attacksMade: 0,
        suppressionsApplied: 0,
        frozenCardLevel: unit.frozenCardLevel,
      };
    })
    .sort((a, b) => a.pieceId.localeCompare(b.pieceId));
  const casualties: BattleCasualty[] = pieceResults
    .filter((result) => result.dead)
    .map((result) => ({
      pieceId: result.pieceId,
      factionId: result.factionId,
      killerFactionId: result.factionId === command.factionId ? defenderFactionId : command.factionId,
      cardId: result.cardId,
      frozenCardLevel: result.frozenCardLevel,
    }));
  const authority: BattleAuthorityAudit = {
    authority: 'as2',
    requestSchema: AS2_BATTLE_REQUEST_SCHEMA,
    receiptSchema: AS2_BATTLE_RECEIPT_SCHEMA,
    sessionId: request.sessionId,
    requestId: request.requestId,
    inputDigest: String(receipt.inputDigest),
    frames,
    durationMs,
    economyObservation,
  };
  const record: BattleRecord = {
    battleId,
    seed,
    strategicRound: state.strategicRound,
    commandSequence: state.commandSequence,
    nodeId: command.targetNodeId,
    attackerOriginNodeId: command.originNodeId,
    attackerPieceIds: attackerIds,
    defenderPieceIds: defenderIds,
    attackerSnapshots: clone(attackerSnapshots),
    defenderSnapshots: clone(defenderSnapshots),
    authority,
    result: {
      winner,
      reason,
      battleRounds: 1,
      pieceResults,
      casualties,
      eventLog: buildAuthorityEvents(battleId, winner, reason, casualties, frames),
      finalRngState: 0,
    },
  };
  state.battles.push(record);

  for (const result of pieceResults) {
    const piece = state.pieces[result.pieceId];
    if (piece) piece.hp = result.hpAfter;
  }
  for (const pieceId of [...attackerIds, ...defenderIds]) {
    const piece = state.pieces[pieceId];
    if (piece) piece.battlesThisRound += 1;
  }
  for (const casualty of casualties) {
    const value = bounty(casualty.cardId, casualty.frozenCardLevel);
    state.casualtyLedger.push({
      casualtyId: `${battleId}:${casualty.pieceId}`,
      strategicRound: state.strategicRound,
      battleId,
      deadPieceId: casualty.pieceId,
      deadFactionId: casualty.factionId,
      killerFactionId: casualty.killerFactionId,
      cardId: casualty.cardId,
      frozenCardLevel: casualty.frozenCardLevel,
      bounty: value,
      killerXp: value,
      loserXp: value * 3,
      settled: false,
    });
    addGameEvent(state, {
      type: 'piece_died',
      factionId: casualty.factionId,
      pieceId: casualty.pieceId,
      cardId: casualty.cardId,
      message: `${casualty.pieceId}在 AS2 实战中阵亡；击杀方待结算 ${value} XP，损失方待结算 ${value * 3} XP。`,
      data: { battleId, killerFactionId: casualty.killerFactionId, authority: 'as2' },
    });
    handleCommanderCasualtyInPlace(state, casualty.pieceId);
    removePieceInPlace(state, casualty.pieceId);
  }
  if (winner === 'attacker') {
    movePiecesInPlace(
      state,
      attackerIds.filter((pieceId) => state.pieces[pieceId] !== undefined),
      command.targetNodeId,
    );
  } else if (reason !== 'mutual_wipe') {
    for (const pieceId of attackerIds) {
      const piece = state.pieces[pieceId];
      if (piece && !piece.failedAssaultLocks.includes(command.targetNodeId)) {
        piece.failedAssaultLocks.push(command.targetNodeId);
      }
    }
  }
  addGameEvent(state, {
    type: 'battle_resolved',
    factionId: command.factionId,
    nodeId: command.targetNodeId,
    message: `${requireNode(state, command.targetNodeId).displayName} AS2 实战结束：${winner === 'attacker' ? '进攻方胜利' : '守方守住'}。`,
    data: {
      battleId,
      reason,
      authority: 'as2',
      frames,
      attackerPieceIds: attackerIds,
      defenderPieceIds: defenderIds,
    },
  });
  return { state, record };
}

export async function applyAs2BattleResume(value: unknown): Promise<ApplyAs2ResumeResult> {
  const resume = readResume(value);
  if (!resume) {
    return { ok: false, state: null, error: 'AS2 恢复信封格式非法。', resultUnknown: true };
  }
  let frozenState: GameState | null = null;
  try {
    assertOpaque(resume.request.sessionId, 'sessionId');
    assertOpaque(resume.request.requestId, 'requestId');
    const digest = await sha256Canonical(resume.request);
    if (digest !== resume.inputDigest
      || canonicalJson(resume.request.state) !== canonicalJson(resume.state)
      || canonicalJson(resume.request.command) !== canonicalJson(resume.command)
      || canonicalJson(resume.request.clientContext) !== canonicalJson(resume.clientContext)) {
      throw new Error('AS2 恢复内容与冻结请求摘要不一致。');
    }
    frozenState = normalizedFrozenState(resume.state);
    if (!isObject(resume.receipt)
      || resume.receipt.schema !== AS2_BATTLE_RECEIPT_SCHEMA
      || resume.receipt.sessionId !== resume.request.sessionId
      || resume.receipt.requestId !== resume.request.requestId
      || resume.receipt.inputDigest !== digest) {
      throw new Error('AS2 战斗回执不属于当前冻结请求。');
    }
    if (resume.receipt.status !== 'accepted') {
      const knownNotStarted = resume.receipt.status === 'not_started';
      return {
        ok: false,
        state: frozenState,
        error: typeof resume.receipt.message === 'string'
          ? resume.receipt.message
          : knownNotStarted
            ? 'AS2 战斗未发出，冻结战略态已恢复，可重新下令。'
            : 'AS2 战斗结果未知，战略态已冻结。',
        resultUnknown: !knownNotStarted,
      };
    }
    if (resume.receipt.petProjectionProfile !== 'catalog_identifier+strategic_progression_v1'
      || resume.receipt.playerPetSnapshotUsed !== false
      || resume.receipt.participantProjectionProfile !== 'discriminated_player_avatar+catalog_pet_v1'
      || resume.receipt.playerAvatarProjectionProfile !== 'trusted_demo2_commander_v1'
      || resume.receipt.playerPersistentSnapshotUsed !== false) {
      throw new Error('AS2 参战者投影契约缺失或引用了玩家持久快照。');
    }
    const applied = applyAcceptedReceipt(resume.request, resume.receipt, frozenState);
    return {
      ok: true,
      state: applied.state,
      battleRecord: applied.record,
      resultUnknown: false,
    };
  } catch (error) {
    return {
      ok: false,
      state: frozenState,
      error: error instanceof Error ? error.message : String(error),
      resultUnknown: true,
    };
  }
}
