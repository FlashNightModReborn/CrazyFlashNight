import { generateNextAiAction, runAiActionPhase, runAiPlanning } from '../ai/heuristic.js';
import type { BattleEvent, BattleRecord } from '../battle/types.js';
import {
  applyAs2BattleResume,
  buildAs2BattleEnvelope,
  createAs2AuthoritySessionId,
  frozenStateFromAs2Resume,
  sessionIdFromAs2Resume,
  type As2BattleEnvelope,
  type As2BattleClientContext,
  type As2ResumeEnvelope,
} from '../battle/as2-authority.js';
import { applyCommand } from '../core/engine.js';
import { requireNode } from '../core/access.js';
import { commanderForPiece } from '../core/commanders.js';
import { relationBetween, requireFaction } from '../core/factions.js';
import { needXp } from '../core/math.js';
import {
  commandElementForMember,
  commandElementMetrics,
  commandElementsAtNode,
  nodeDeploymentSize,
  selectionOrganizationMetrics,
} from '../core/organization.js';
import { createGame } from '../core/state.js';
import { canonicalJson } from '../core/canonical.js';
import { runtimeMapBundleForScenarioRef } from '../data/map.js';
import { adjacentNodeIds, nodeOccupyingFactions, piecesAtNode } from '../core/selectors.js';
import type {
  CardId,
  CommandElementState,
  Difficulty,
  GameEvent,
  GameCommand,
  GameState,
  FactionId,
  MoveOrAttackCommand,
  NodeId,
  PresetId,
  PromotionId,
  ValidationReasonCode,
} from '../core/types.js';
import { firstProductionSlotId, validateCommand } from '../core/validator.js';
import { PRODUCTION_CARD_IDS, getCardDefinition } from '../data/cards.js';
import { PROMOTIONS } from '../data/config.js';
import { DEMO_1_ORGANIZATION, formationProfile } from '../data/organization.js';
import { DEMO_2_SECTORS } from '../data/demo2.js';
import {
  mountPortraits,
  normalizePlayerAvatarPortrait,
  type PlayerAvatarPortrait,
} from '../assets/portrait-texture-source.js';
import {
  SandtableScene,
  type SandtableActionFollowCarry,
  type SandtableCameraSnapshot,
} from '../scene/sandtable-scene.js';
import {
  MAP_THEMES,
  normalizeMapTheme,
  type MapThemeId,
} from '../scene/map-theme.js';
import {
  StageOuterSessionAuthority,
  type StageTerminalSend,
} from '../stage/session-authority.js';
import type { StageOuterBindingV1 } from '../stage/outer-authority.js';
import { parseStageOuterBinding } from '../stage/outer-authority.js';
import {
  buildResumeAppliedReceipt,
  canEmitStageGameOver,
  type As2ResumeAppliedV1,
  type ResumeAppliedSend,
} from '../stage/resume-apply.js';
import type { ArenaFormationId, FormationSlotRole } from '../strategy/definitions.js';
import { DisposableBag, GenerationFence, isEditableKeyboardTarget } from './lifecycle.js';
import {
  buildLargeMapSectorIndex,
  deriveLargeMapAlerts,
  searchLargeMapNodes,
  type LargeMapNodeSignal,
  type LargeMapNodeSummary,
  type LargeMapSector,
} from './large-map-navigation.js';
import {
  buildNodeNavigatorWindow,
  nodePageIndexFor,
  type NodeNavigatorMode,
} from './node-navigator.js';
import {
  canonicalPieceIds,
  followCommandSelection,
} from './selection-policy.js';
import {
  closeHelpUi,
  createHelpUiState,
  helpProfileForScenario,
  isHelpAnchor,
  openHelpUi,
  type HelpAnchor,
  type HelpUiState,
} from './help-profile.js';
import {
  formatActionPoints,
  formatMilitaryFunds,
  formatStrategicRound,
  playerBehaviorName,
  playerEncounterDistanceText,
  playerOwnerName,
  playerPowerTierName,
  playerReasonSummary,
  playerTextForReason,
} from './player-text-catalog.js';
import {
  buildActionPreviews,
  factionLabel,
  nextPromotionFor,
  ownerLabel,
  PHASE_LABEL,
  projectBattleUnitPresentation,
  projectBattleVisual,
  projectNodes,
  type ActionPreview,
  type BattlePlaybackState,
} from './presenter.js';
import {
  flattenProductionOrders,
  projectProductionNodes,
  recommendProductionLane,
  resolveProductionChoice,
  type ProductionControlMode,
} from './production-presenter.js';
import { recoverDefinitiveAs2BattleFailure } from './as2-handoff-recovery.js';

export interface WarlordInitData {
  mode?: string;
  source?: string;
  seed?: string;
  preset?: PresetId;
  difficulty?: Difficulty;
  scenarioRef?: string;
  panelInstanceId?: string;
  productionWrites?: boolean;
  forceWebglFailure?: boolean;
  mapTheme?: MapThemeId;
  battleAuthority?: 'fixture' | 'as2';
  bridgeSend?: (message: As2BattleEnvelope) => boolean;
  as2BattleSession?: boolean;
  aiSeenTransitions?: string[];
  resume?: As2ResumeEnvelope | Record<string, unknown> | null;
  stageOuterBinding?: StageOuterBindingV1 | Record<string, unknown> | null;
  playerAvatarPortrait?: PlayerAvatarPortrait | Record<string, unknown> | null;
  stageTerminalSend?: StageTerminalSend;
  resumeAppliedSend?: ResumeAppliedSend;
}

export interface WarlordSessionContract {
  rebind(initData?: WarlordInitData): void;
  requestClose(reason?: string): boolean;
  prepareStageClose(): 'not_stage' | 'ready' | 'blocked';
  quiesceForPanelClose(): void;
  resumeAfterPanelCloseTimeout(): void;
  resize(): void;
  dispose(): void;
  getState(): GameState;
  handleHostResponse(response: unknown): boolean;
}

interface NormalizedWarlordInit {
  mode: string;
  source: string;
  seed: string;
  preset: PresetId;
  difficulty: Difficulty;
  scenarioRef: string;
  panelInstanceId: string;
  productionWrites: false;
  forceWebglFailure: boolean;
  mapTheme: MapThemeId;
  battleAuthority: 'fixture' | 'as2';
  bridgeSend: ((message: As2BattleEnvelope) => boolean) | null;
  as2BattleSession: boolean;
  aiSeenTransitions: string[];
  resume: WarlordInitData['resume'];
  stageOuterBinding: WarlordInitData['stageOuterBinding'];
  playerAvatarPortrait: PlayerAvatarPortrait | null;
  stageTerminalSend: StageTerminalSend | null;
  resumeAppliedSend: ResumeAppliedSend | null;
}

interface As2ResumeIdentity {
  readonly sessionId: string;
  readonly requestId: string;
  readonly inputDigest: string;
  readonly key: string;
}

interface As2ResumeCommitSlot {
  readonly identity: As2ResumeIdentity;
  readonly fingerprint: string;
  readonly stageContextIdentity: string;
  phase: 'applying' | 'committed';
  ackStatus: As2ResumeAppliedV1['status'] | null;
  ackSent: boolean;
}

const DIFFICULTIES: Array<[Difficulty, string]> = [
  ['easy', '简单'],
  ['normal', '普通'],
  ['hard', '困难'],
  ['extreme', '极难'],
];

const DEFAULT_CAMERA_SNAPSHOT: SandtableCameraSnapshot = {
  centerX: 0,
  centerZ: 0,
  zoomPercent: 100,
  atFit: true,
  detailTier: 'operational',
  nodeCount: 0,
};

const CAMERA_HUD_REVEAL_MS = 1400;
const MAX_NETWORK_ORDER_TILES = 6;
// 可见 toast：停留时长 + 淡出过渡（淡出曲线在 CSS 追加分区）
const TOAST_VISIBLE_MS = 2800;
const TOAST_FADE_MS = 320;
// 进攻二次确认的有效窗口；超时、Esc 或点击他处都会解除武装
const ATTACK_ARM_WINDOW_MS = 3000;
// AI 行动重放节奏：不小于棋子 420ms 移动补间，避免补间被下一条命令重启
const AI_REPLAY_INTERVAL_MS = 460;
const AI_AS2_INTERVAL_MS = 450;
// AI 重放中一场战斗播完后留给玩家看清结果的停留时间
const AI_BATTLE_DWELL_MS = 900;

const FORMATION_SLOT_LABEL: Record<FormationSlotRole, string> = {
  vanguard: '前卫',
  flank: '侧翼',
  fire_support: '火力',
  reserve: '预备',
};

function formationEffect(profileId: ArenaFormationId): string {
  const profile = formationProfile(profileId);
  return `阵位顺序：${profile.slotRoles.map((role) => FORMATION_SLOT_LABEL[role]).join('、')}`;
}

function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function checked(value: boolean): string {
  return value ? ' checked' : '';
}

function disabled(value: boolean): string {
  return value ? ' disabled' : '';
}

function ariaDisabled(value: boolean): string {
  return value ? ' aria-disabled="true"' : ' aria-disabled="false"';
}

function selected(value: boolean): string {
  return value ? ' selected' : '';
}

function hpPercent(hp: number, maxHp: number): number {
  return maxHp > 0 ? Math.max(0, Math.min(100, (hp / maxHp) * 100)) : 0;
}

// HP 条分色：低于 50% 警示、低于 25% 危急；颜色在 CSS 追加分区按 class 着色
function hpBarClass(hp: number, maxHp: number): string {
  const percent = hpPercent(hp, maxHp);
  return percent < 25 ? ' class="is-critical"' : percent < 50 ? ' class="is-low"' : '';
}

function compactProductionNodeName(displayName: string): string {
  return displayName.replace('红方', '我方·').replace('蓝方', '敌方·').replace('中央', '中部·');
}

function playerEventMessage(event: GameEvent, game: GameState): string {
  const faction = event.factionId ? factionLabel(event.factionId, game) : '双方';
  const nodeName = event.nodeId ? game.map.nodes[event.nodeId]?.displayName : null;
  const cardName = event.cardId ? getCardDefinition(event.cardId).displayName : null;
  switch (event.type) {
    case 'game_started': return '演习开始。';
    case 'round_started': return `${formatStrategicRound(event.strategicRound)}开始。`;
    case 'move': return `${faction}移动 ${event.amount ?? 0} 支部队${nodeName ? `至${nodeName}` : ''}。`;
    case 'battle_resolved': return `${nodeName ?? '目标据点'}战斗结束，兵力与控制状态已经更新。`;
    case 'piece_died': return `${faction}一支部队退出战斗。`;
    case 'node_captured': return `${nodeName ?? '目标据点'}的控制权已经改变。`;
    case 'recovery': return `${faction}完成部队恢复。`;
    case 'income': return `${faction}获得 ${event.amount ?? 0} 军费。`;
    case 'xp_settled': return `${faction}完成战后经验结算。`;
    case 'xp_allocated': return `已为${cardName ?? '所选兵种'}分配经验。`;
    case 'card_level_up': return `${cardName ?? '所选兵种'}的等级已经提升。`;
    case 'promotion_purchased': return `${cardName ?? '所选兵种'}完成升阶。`;
    case 'production_enqueued': return `${cardName ?? '所选兵种'}已加入生产队列。`;
    case 'production_cancelled': return `${cardName ?? '生产订单'}已撤销，军费和预留人口已经返还。`;
    case 'production_progressed': return `${cardName ?? '生产订单'}取得新的生产进度。`;
    case 'piece_deployed': return `${cardName ?? '新部队'}已部署。`;
    case 'task_group_merged': return `${nodeName ?? '当前据点'}已建立临时编队，共 ${event.amount ?? 0} 支部队。`;
    case 'task_group_split': return `${nodeName ?? '当前据点'}已拆出 ${event.amount ?? 0} 支独立部队。`;
    case 'formation_changed': return `${nodeName ?? '当前据点'}的部队已完成阵型调整。`;
    case 'faction_defeated': return `${faction}已经退出战局。`;
    case 'surrender_cleanup': return `${faction}完成投降清理，不产生战利品。`;
    case 'commander_downed': return `${faction}指挥官已经倒地或阵亡。`;
    case 'commander_evacuated': return `${faction}指挥官已经撤往后方。`;
    case 'commander_production_enqueued': return `${faction}开始重新生产指挥官。`;
    case 'commander_redeployed': return `${faction}指挥官已经重新部署。`;
    case 'action_ended': return `${faction}结束本回合行动。`;
    case 'planning_committed': return `${faction}提交结算安排。`;
    case 'game_over': return event.factionId ? `${faction}获胜。` : '本局以平局结束。';
  }
}

function battleUnitName(record: BattleRecord, pieceId: string | undefined): string {
  if (!pieceId) return '一支部队';
  return [...record.attackerSnapshots, ...record.defenderSnapshots]
    .find((unit) => unit.pieceId === pieceId)?.displayName ?? '一支部队';
}

function battleEventLabel(event: BattleEvent): string {
  const labels: Record<BattleEvent['type'], string> = {
    round_start: '交战开始',
    sniper_volley: '先制齐射',
    reload: '重新装填',
    attack: '发起攻击',
    miss: '攻击落空',
    damage: '造成伤害',
    special: '触发特攻',
    suppression: '压制生效',
    death: '部队阵亡',
    round_end: '本轮结束',
    battle_end: '战斗结束',
  };
  return labels[event.type];
}

function playerBattleEventMessage(record: BattleRecord, event: BattleEvent): string {
  const actor = battleUnitName(record, event.actorPieceId);
  const target = battleUnitName(record, event.targetPieceId);
  switch (event.type) {
    case 'round_start': return `第 ${event.battleRound} 轮交战开始。`;
    case 'sniper_volley': return '双方远射部队执行先制齐射。';
    case 'reload': return `${actor}正在重新装填。`;
    case 'attack': return `${actor}向${target}发起攻击。`;
    case 'miss': return `${actor}的攻击未命中。`;
    case 'damage': return `${target}受到 ${event.damage ?? 0} 点伤害。`;
    case 'special': return `${actor}对${target}触发特攻。`;
    case 'suppression': return `${target}受到压制，下一次攻击将推迟。`;
    case 'death': return `${target}退出战斗。`;
    case 'round_end': return `第 ${event.battleRound} 轮交战结束。`;
    case 'battle_end': return record.result.winner === 'attacker' ? '进攻方取得胜利。' : '防守方守住了据点。';
  }
}

function isCameraSurfaceTarget(target: EventTarget | null): boolean {
  return target instanceof Element && target.closest('.warlord-sandtable-canvas') !== null;
}

function isCameraNavigationKey(key: string): boolean {
  const normalized = key.toLowerCase();
  return normalized === '+' || normalized === '=' || normalized === '-' || normalized === '_'
    || normalized === '0' || normalized === 'home'
    || normalized === 'arrowleft' || normalized === 'arrowright'
    || normalized === 'arrowup' || normalized === 'arrowdown'
    || normalized === 'a' || normalized === 'd' || normalized === 'w' || normalized === 's';
}

function normalizeInit(input?: WarlordInitData): NormalizedWarlordInit {
  const difficulty = input?.difficulty;
  const preset = input?.preset;
  const source = typeof input?.source === 'string' ? input.source : 'dev-harness';
  const productAuthority = input?.battleAuthority === 'as2'
    || source === 'runtime' || source === 'as2_battle_resume';
  const parsedStageBinding = parseStageOuterBinding(input?.stageOuterBinding);
  const scenarioRef = parsedStageBinding.ok
    ? parsedStageBinding.value.scenarioRef
    : typeof input?.scenarioRef === 'string' && input.scenarioRef.trim()
      ? input.scenarioRef.trim()
      : 'warlord_tutorial_v1';
  return {
    mode: typeof input?.mode === 'string' ? input.mode : 'phase-b',
    source,
    seed: typeof input?.seed === 'string' && input.seed.trim() ? input.seed.trim() : 'warlord-demo-seed-001',
    preset: preset === 'all-units' ? preset : 'standard',
    difficulty: difficulty === 'easy' || difficulty === 'hard' || difficulty === 'extreme' ? difficulty : 'normal',
    scenarioRef,
    panelInstanceId: typeof input?.panelInstanceId === 'string' ? input.panelInstanceId : '',
    productionWrites: false,
    forceWebglFailure: input?.forceWebglFailure === true,
    mapTheme: normalizeMapTheme(input?.mapTheme),
    battleAuthority: productAuthority ? 'as2' : 'fixture',
    bridgeSend: typeof input?.bridgeSend === 'function' ? input.bridgeSend : null,
    as2BattleSession: input?.as2BattleSession === true,
    aiSeenTransitions: Array.isArray(input?.aiSeenTransitions)
      ? input.aiSeenTransitions.filter((entry): entry is string => typeof entry === 'string').slice(0, 256)
      : [],
    resume: input?.resume && typeof input.resume === 'object' ? input.resume : null,
    stageOuterBinding: input?.stageOuterBinding && typeof input.stageOuterBinding === 'object'
      ? input.stageOuterBinding : null,
    playerAvatarPortrait: productAuthority
      ? normalizePlayerAvatarPortrait(input?.playerAvatarPortrait) : null,
    stageTerminalSend: typeof input?.stageTerminalSend === 'function' ? input.stageTerminalSend : null,
    resumeAppliedSend: typeof input?.resumeAppliedSend === 'function'
      ? input.resumeAppliedSend : null,
  };
}

function as2ResumeIdentity(value: unknown): As2ResumeIdentity | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const resume = value as Record<string, unknown>;
  if (!resume.request || typeof resume.request !== 'object' || Array.isArray(resume.request)
    || typeof resume.inputDigest !== 'string') return null;
  const request = resume.request as Record<string, unknown>;
  if (typeof request.sessionId !== 'string' || typeof request.requestId !== 'string') return null;
  return Object.freeze({
    sessionId: request.sessionId,
    requestId: request.requestId,
    inputDigest: resume.inputDigest,
    key: `${request.sessionId}\u0000${request.requestId}\u0000${resume.inputDigest}`,
  });
}

export class WarlordSession implements WarlordSessionContract {
  private init: NormalizedWarlordInit;
  private game: GameState;
  private selectedNodeId: NodeId;
  private selectedPieceIds: string[] = [];
  private readonly splitMemberSelections = new Map<string, string[]>();
  private productionNodeId: NodeId;
  private selectedSlotId: string;
  private productionControlMode: ProductionControlMode = 'auto';
  // notice 通过 setter 同步可见 toast 的序号；错误/阻断类用 setNotice(..., 'error') 区分色调
  private noticeText = '点击己方部队或按住多选键框选，再点击高亮据点直接下令。';
  private noticeTone: 'info' | 'error' = 'info';
  private toastSerial = 0;
  private toastFadeTimer: number | null = null;
  private toastHideTimer: number | null = null;
  private armedTargetNodeId: NodeId | null = null;
  private attackArmTimer: number | null = null;
  // fixture 模式 AI 回合重放队列：公开 applyCommand 逐条投影中间态
  private aiReplay: { commands: GameCommand[]; index: number } | null = null;
  private aiCameraLease: {
    token: number;
    mode: 'dispatch' | 'movement' | 'holding' | 'battle' | 'returning';
    blocking: boolean;
    carry: SandtableActionFollowCarry | null;
  } | null = null;
  // 首次引导（仅会话内记忆，不落盘）：发过一轮命令 / 完成过一轮行动后不再提示
  private coachCommandIssued = false;
  private coachDone = false;
  private coachSkipped = false;
  private helpState: HelpUiState = createHelpUiState();
  private helpReturnFocus: HTMLElement | null = null;
  private helpFocusTarget: 'close' | 'section' | null = null;
  private playback: BattlePlaybackState | null = null;
  private automationTimer: number | null = null;
  private portraitGeneration = new GenerationFence();
  private stageCloseGeneration = new GenerationFence();
  private stageAutoCloseTimer: number | null = null;
  private resources = new DisposableBag();
  private scene: SandtableScene | null = null;
  private cameraSnapshot = DEFAULT_CAMERA_SNAPSHOT;
  private cameraHudExpanded = false;
  private cameraHudTimer: number | null = null;
  private mapTheme: MapThemeId;
  private themeDraft: MapThemeId;
  private nodeNavigatorMode: NodeNavigatorMode = 'context';
  private nodePageIndex = 0;
  private largeMapSectorId = 'all';
  private largeMapSearchQuery = '';
  private largeMapToolsExpanded = false;
  private rosterCollapsed = false;
  private sceneError: string | null = null;
  private configOpen = false;
  private disposed = false;
  private panelCloseQuiesced = false;
  private seedDraft: string;
  private presetDraft: PresetId;
  private difficultyDraft: Difficulty;
  private handoffPending = false;
  private authorityBlocked = false;
  private authorityReturnOnly = false;
  private authoritySessionId: string;
  private pendingBattleCallId: string | null = null;
  private pendingBattleCommand: MoveOrAttackCommand | null = null;
  private pendingBattleIdentity: string | null = null;
  private pendingBattlePrepared = false;
  private authorityAckTimer: number | null = null;
  private resumeCommitSlot: As2ResumeCommitSlot | null = null;
  private aiSeenTransitions = new Set<string>();
  private stageAuthority: StageOuterSessionAuthority;

  private get notice(): string {
    return this.noticeText;
  }

  private set notice(value: string) {
    this.setNotice(value);
  }

  private setNotice(value: string, tone: 'info' | 'error' = 'info'): void {
    this.noticeText = value;
    this.noticeTone = tone;
    this.toastSerial += 1;
  }

  private get playerId(): FactionId {
    return this.game.playerFactionId;
  }

  private playerFaction() {
    return requireFaction(this.game, this.playerId);
  }

  private activeAiFactionId(): FactionId | null {
    const factionId = this.game.activeFactionId;
    if (!factionId) return null;
    return requireFaction(this.game, factionId).controller === 'ai' ? factionId : null;
  }

  private pendingPlanningAiFactionId(): FactionId | null {
    return this.game.turnOrder.find((factionId) => {
      const faction = requireFaction(this.game, factionId);
      return faction.controller === 'ai' && faction.defeatedAtRound === null && !faction.planningCommitted;
    }) ?? null;
  }

  public constructor(private readonly root: HTMLElement, initData?: WarlordInitData) {
    this.init = normalizeInit(initData);
    this.stageCloseGeneration.next();
    this.stageAuthority = new StageOuterSessionAuthority({
      ...this.init,
      stageAutomaticCloseRequest: () => this.scheduleStageExactClose(),
    });
    this.authoritySessionId = sessionIdFromAs2Resume(this.init.resume)
      ?? createAs2AuthoritySessionId();
    this.aiSeenTransitions = new Set(this.init.aiSeenTransitions);
    this.mapTheme = this.init.mapTheme;
    this.themeDraft = this.mapTheme;
    const resumeState = this.init.battleAuthority === 'as2'
      ? frozenStateFromAs2Resume(this.init.resume) : null;
    this.game = resumeState
      ?? createGame({
        seed: this.init.seed,
        preset: this.init.preset,
        difficulty: this.init.difficulty,
        runtimeBundle: runtimeMapBundleForScenarioRef(this.init.scenarioRef),
      });
    this.handoffPending = this.init.battleAuthority === 'as2' && this.init.resume !== null;
    this.authorityBlocked = this.handoffPending && resumeState === null;
    const playerFaction = this.playerFaction();
    const preferredStart = this.game.preset === 'all-units'
      ? Object.keys(playerFaction.productionQueues)[1] as NodeId | undefined
      : playerFaction.commandPostNodeId;
    this.selectedNodeId = preferredStart ?? playerFaction.commandPostNodeId;
    this.productionNodeId = recommendProductionLane(this.game, this.playerId)?.nodeId
      ?? playerFaction.commandPostNodeId;
    this.selectedSlotId = firstProductionSlotId(this.game, this.playerId, this.productionNodeId)
      ?? `${this.productionNodeId}:1`;
    this.seedDraft = this.game.gameSeed;
    this.presetDraft = this.game.preset;
    this.difficultyDraft = this.game.difficulty;
    this.installShell();
    this.root.addEventListener('click', this.onClick);
    this.root.addEventListener('change', this.onChange);
    this.root.addEventListener('input', this.onInput);
    this.root.addEventListener('pointerdown', this.onCameraSurfaceActivity);
    this.root.addEventListener('wheel', this.onCameraSurfaceActivity, { passive: true });
    this.root.addEventListener('focusin', this.onCameraSurfaceActivity);
    this.root.addEventListener('focusout', this.onCameraSurfaceFocusOut);
    window.addEventListener('keydown', this.onKeyDown);
    this.resources.add(() => this.root.removeEventListener('click', this.onClick));
    this.resources.add(() => this.root.removeEventListener('change', this.onChange));
    this.resources.add(() => this.root.removeEventListener('input', this.onInput));
    this.resources.add(() => this.root.removeEventListener('pointerdown', this.onCameraSurfaceActivity));
    this.resources.add(() => this.root.removeEventListener('wheel', this.onCameraSurfaceActivity));
    this.resources.add(() => this.root.removeEventListener('focusin', this.onCameraSurfaceActivity));
    this.resources.add(() => this.root.removeEventListener('focusout', this.onCameraSurfaceFocusOut));
    this.resources.add(() => window.removeEventListener('keydown', this.onKeyDown));
    // AS2 的恢复结果会在同一次事件循环后打开阻塞式战斗结算。这里若先
    // 创建 Three/WebGL，再立即用结算层盖住，不仅做了无效工作，还会让
    // 每次“战斗 -> 恢复面板”都额外制造一个短命 GPU context。恢复完成前
    // 保持零场景；失败时或玩家关闭结算后，再由 render() 按需创建。
    if (!(this.init.battleAuthority === 'as2' && this.init.resume)) this.startScene();
    this.render();
    if (this.init.battleAuthority === 'as2' && this.init.resume) {
      void this.consumeAs2Resume(this.init.resume);
    }
  }

  private installShell(): void {
    const developerConfig = this.init.source === 'dev-harness'
      ? '<button class="warlord-icon-button" data-action="toggle-config" aria-label="打开开发设置">开发设置</button>'
      : '<span class="warlord-dev-spacer" aria-hidden="true"></span>';
    this.root.innerHTML = `<div class="warlord-app" data-testid="warlord-app">
      <header class="warlord-command-bar">
        <div class="warlord-brand"><b>军阀战术演习</b><span data-region="theater">沙漠战区 · 战术指挥台</span></div>
        <div class="warlord-round" data-region="round"></div>
        <div class="warlord-factions" data-region="factions"></div>
        <button class="warlord-icon-button warlord-help-button" data-action="open-help" data-help-anchor="overview" aria-label="打开玩法帮助">玩法帮助</button>
        ${developerConfig}
        <button class="warlord-icon-button warlord-panel-close" data-action="request-close" aria-label="关闭军阀战术演习">×</button>
      </header>
      <main class="warlord-main">
        <aside class="warlord-force-rail" data-region="forces" aria-label="当前节点驻军"></aside>
        <section class="warlord-map-stage" aria-label="战区沙盘">
          <div class="warlord-scene-host" data-region="scene"></div>
          <div class="warlord-map-fallback" data-region="fallback" hidden></div>
          <div class="warlord-map-caption"><span>战区沙盘</span><span>拖拽平移 · 按住多选键框选 · 双击部队临时编队</span></div>
          <div class="warlord-compass" aria-hidden="true"><i>北</i><span></span></div>
          <div class="warlord-camera-hud" data-region="camera" aria-label="沙盘相机控制"></div>
          <div class="warlord-toast" data-region="toast" hidden></div>
          <div class="warlord-authority-banner" data-region="authority" hidden></div>
          <div class="warlord-hover-chip" data-region="hover" hidden></div>
          <div class="warlord-coach-tip" data-region="coach" hidden></div>
          <div class="warlord-command-intent" data-region="command-intent" hidden></div>
          <aside id="warlord-large-map-tools" class="warlord-large-map-tools" data-region="large-map" aria-label="大地图战区筛选与告警" hidden></aside>
          <nav class="warlord-node-strip" data-region="nodes" aria-label="节点上下文导航"></nav>
          <div class="warlord-planning-layer" data-region="planning"></div>
        </section>
        <aside class="warlord-action-rail" data-region="actions" aria-label="合法行动与事件"></aside>
      </main>
      <footer class="warlord-roster" data-region="cards" aria-label="八卡科技与生产"></footer>
      <div class="warlord-battle-layer" data-region="battle"></div>
      <div class="warlord-config-layer" data-region="config"></div>
      <div class="warlord-help-layer" data-region="help"></div>
      <div class="warlord-live" data-region="live" aria-live="polite"></div>
    </div>`;
  }

  private startScene(): void {
    if (this.disposed || this.scene || this.playbackRecord || this.handoffPending
      || this.panelCloseQuiesced) return;
    const host = this.root.querySelector<HTMLElement>('[data-region="scene"]');
    if (!host) return;
    try {
      if (this.init.forceWebglFailure) throw new Error('测试开关强制关闭 WebGL');
      this.scene = new SandtableScene(host, {
        reducedMotion: window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true,
        mapTheme: this.mapTheme,
        playerAvatarPortrait: this.init.playerAvatarPortrait,
        onNodePicked: (nodeId) => this.handleNodeIntent(nodeId),
        onPiecePicked: (pieceId, additive) => this.selectPiece(pieceId, additive),
        onNodeDoublePicked: (nodeId) => this.selectAllAtNode(nodeId),
        onMarqueeSelected: (selection) => this.applyMarqueeSelection(selection),
        onEmptyPicked: () => this.clearPieceSelection('已取消当前编组；可继续浏览沙盘。'),
        onHoverInfo: (info, anchor) => this.renderHoverChip(info, anchor),
        onCameraChanged: (snapshot) => {
          this.cameraSnapshot = snapshot;
          this.renderCameraHud();
        },
        onError: (message) => {
          void message;
          this.setNotice('沙盘显示暂时不稳定；可继续使用界面中的据点列表操作。', 'error');
          this.renderLiveRegion();
        },
      });
    } catch (error) {
      this.sceneError = error instanceof Error ? error.message : String(error);
      this.scene = null;
    }
  }

  private restartScene(): void {
    this.scene?.dispose();
    this.scene = null;
    this.sceneError = null;
    this.cameraSnapshot = { ...DEFAULT_CAMERA_SNAPSHOT };
    if (!this.playbackRecord && !this.handoffPending && !this.panelCloseQuiesced) this.startScene();
  }

  /**
   * 战斗结算完全遮住沙盘时不保留 WebGL context。仅暂停 rAF 仍会留下
   * Chromium 合成层、纹理与 context；真实 AS2 战斗连续往返时会放大
   * 驱动压力。先断开字段再 dispose，避免清理回调重新触碰旧场景。
   */
  private releaseSceneForBattleBoundary(preserveAiFollow = false): void {
    const scene = this.scene;
    if (!scene) return;
    if (preserveAiFollow && this.aiCameraLease) {
      this.aiCameraLease.carry = scene.detachActionFollow(this.aiCameraLease.token);
    }
    this.scene = null;
    try {
      scene.dispose();
    } catch {
      // scene 字段已经断开，战斗/结算必须继续；dispose 自身保证先退役
      // context。留下可观测标记供 harness/现场日志定位第三方清理异常。
      this.root.dataset.sceneDisposeRecovered = 'true';
    }
  }

  private get playbackRecord(): BattleRecord | null {
    if (!this.playback) return null;
    return this.game.battles.find((record) => record.battleId === this.playback?.battleId) ?? null;
  }

  private clearAutomation(): void {
    if (this.automationTimer !== null) window.clearTimeout(this.automationTimer);
    this.automationTimer = null;
  }

  private clearStageAutoClose(): void {
    if (this.stageAutoCloseTimer !== null) window.clearTimeout(this.stageAutoCloseTimer);
    this.stageAutoCloseTimer = null;
  }

  private advanceStageCloseGeneration(): void {
    this.clearStageAutoClose();
    this.stageCloseGeneration.next();
  }

  private scheduleStageExactClose(): void {
    if (this.disposed || this.stageAutoCloseTimer !== null) return;
    const generation = this.stageCloseGeneration.current();
    this.stageAutoCloseTimer = window.setTimeout(() => {
      this.stageAutoCloseTimer = null;
      if (this.disposed
        || !this.stageCloseGeneration.isCurrent(generation)
        || this.stageAuthority.status !== 'terminal_sent') return;
      this.root.dispatchEvent(new CustomEvent('warlord:request-close', { bubbles: true }));
    }, 0);
  }

  private clearCameraHudTimer(): void {
    if (this.cameraHudTimer !== null) window.clearTimeout(this.cameraHudTimer);
    this.cameraHudTimer = null;
  }

  private revealCameraHud(): void {
    if (this.disposed) return;
    this.clearCameraHudTimer();
    this.cameraHudExpanded = true;
    this.renderCameraHud();
    this.cameraHudTimer = window.setTimeout(() => {
      this.cameraHudTimer = null;
      if (this.disposed) return;
      const region = this.root.querySelector<HTMLElement>('[data-region="camera"]');
      // 键盘焦点仍在相机控件内时保持完整信息；离开后由 focusout 收口。
      // 不能让固定闲置计时器在用户正操作按钮时把读数折叠掉。
      if (region?.contains(document.activeElement)) return;
      this.cameraHudExpanded = false;
      this.renderCameraHud();
    }, CAMERA_HUD_REVEAL_MS);
  }

  private readonly onCameraSurfaceActivity = (event: Event): void => {
    if (isCameraSurfaceTarget(event.target)) this.revealCameraHud();
  };

  private readonly onCameraSurfaceFocusOut = (event: FocusEvent): void => {
    if (!isCameraSurfaceTarget(event.target)) return;
    window.setTimeout(() => {
      if (this.disposed) return;
      const region = this.root.querySelector<HTMLElement>('[data-region="camera"]');
      if (region?.contains(document.activeElement)) return;
      this.clearCameraHudTimer();
      this.cameraHudExpanded = false;
      this.renderCameraHud();
    }, 0);
  };

  private clearAuthorityAckTimer(): void {
    if (this.authorityAckTimer !== null) window.clearTimeout(this.authorityAckTimer);
    this.authorityAckTimer = null;
  }

  private authorityClientContext(): As2BattleClientContext {
    return {
      seed: this.game.gameSeed,
      preset: this.game.preset,
      difficulty: this.game.difficulty,
      mapTheme: this.mapTheme,
      forceWebglFailure: this.init.forceWebglFailure,
      aiSeenTransitions: [...this.aiSeenTransitions].sort(),
    };
  }

  private rememberAppliedTransitions(command: MoveOrAttackCommand): void {
    for (const pieceId of command.pieceIds) {
      const piece = this.game.pieces[pieceId];
      if (piece?.nodeId === command.targetNodeId) {
        this.aiSeenTransitions.add(`${pieceId}:${command.originNodeId}->${command.targetNodeId}`);
      }
    }
  }

  private followAiAction(command: MoveOrAttackCommand): number | null {
    const token = this.scene?.followActionPath([
      command.originNodeId,
      ...(command.viaNodeId ? [command.viaNodeId] : []),
      command.targetNodeId,
    ]) ?? null;
    if (token !== null) {
      if (!this.aiCameraLease || this.aiCameraLease.token !== token) {
        this.aiCameraLease = { token, mode: 'dispatch', blocking: true, carry: null };
      } else {
        this.aiCameraLease.mode = 'dispatch';
        this.aiCameraLease.blocking = true;
      }
    }
    return token;
  }

  private cancelAiActionCamera(token: number, resumeAutomation = false): void {
    if (this.aiCameraLease?.token !== token) return;
    this.scene?.cancelActionFollow(token);
    this.aiCameraLease.carry = null;
    this.aiCameraLease = null;
    if (resumeAutomation && !this.disposed) this.scheduleAutomation();
  }

  private holdAiActionCameraForContinuation(token: number): void {
    const pending = this.aiCameraLease;
    if (!pending || pending.token !== token) return;
    pending.mode = 'movement';
    pending.blocking = true;
    const completion = this.scene?.holdActionFollowAfterMovement(token);
    void (completion ?? Promise.resolve(false)).then((settled) => {
      if (this.disposed || this.aiCameraLease?.token !== token) return;
      if (!settled) {
        this.aiCameraLease = null;
        this.scheduleAutomation(true);
        return;
      }
      this.aiCameraLease.mode = 'holding';
      this.aiCameraLease.blocking = false;
      this.scheduleAutomation(true);
    });
  }

  private returnAiActionCamera(token: number): void {
    const pending = this.aiCameraLease;
    if (!pending || pending.token !== token || pending.mode === 'returning') return;
    pending.mode = 'returning';
    pending.blocking = true;
    const completion = this.scene?.returnActionFollow(token);
    void (completion ?? Promise.resolve(false)).then(() => {
      if (this.disposed || this.aiCameraLease?.token !== token) return;
      this.aiCameraLease = null;
      this.scheduleAutomation(true);
    });
  }

  private closeBattlePlayback(): void {
    this.playback = null;
    const pending = this.aiCameraLease?.mode === 'battle' ? this.aiCameraLease : null;
    if (pending) pending.blocking = true;
    // render() 会先恢复唯一的新场景，再投影当前战略态。
    this.render();
    if (pending?.carry && this.scene) {
      const restoredToken = this.scene.restoreActionFollow(pending.carry);
      pending.carry = null;
      if (restoredToken !== null) pending.token = restoredToken;
    }
    if (pending) this.holdAiActionCameraForContinuation(pending.token);
  }

  private recoverFromDefinitiveAs2BattleFailure(
    command: MoveOrAttackCommand,
    playerNotice: string,
    aiNotice: string,
  ): void {
    this.clearAuthorityAckTimer();
    this.pendingBattleCallId = null;
    this.pendingBattleCommand = null;
    this.pendingBattleIdentity = null;
    this.pendingBattlePrepared = false;
    this.resumeCommitSlot = null;
    this.handoffPending = false;
    this.authorityBlocked = false;
    this.authorityReturnOnly = false;
    const recovery = recoverDefinitiveAs2BattleFailure(this.game, command);
    if (recovery.outcome === 'ai_action_ended') {
      this.game = recovery.state;
      this.aiSeenTransitions.clear();
      this.setNotice(aiNotice, 'error');
      this.render();
      return;
    }
    if (recovery.outcome === 'player_retry') {
      this.setNotice(playerNotice, 'error');
      this.render();
      return;
    }
    this.authorityBlocked = true;
    this.authorityReturnOnly = true;
    this.setNotice('敌方行动未能安全收束；为避免重复发起战斗，本局不能继续。请关闭面板后从任务提示选择“回基地”。', 'error');
    this.render();
  }

  private async beginAs2Battle(command: MoveOrAttackCommand): Promise<void> {
    const bridgeSend = this.init.bridgeSend;
    if (!bridgeSend) {
      this.recoverFromDefinitiveAs2BattleFailure(
        command,
        '战斗场景暂时无法打开；战略态未改变，请重新选择部队后再试。',
        '战斗场景暂时无法打开；本次进攻未写入战略态，敌方行动已结束，演习继续。',
      );
      return;
    }
    const nonce = `${this.game.strategicRound}.${this.game.commandSequence + 1}.${this.game.battleOrdinal + 1}.${Date.now().toString(36)}`;
    const requestId = `battle.${nonce}`;
    const callId = `wb.${nonce}`;
    this.pendingBattleCallId = callId;
    this.pendingBattleCommand = command;
    this.pendingBattleIdentity = null;
    this.pendingBattlePrepared = false;
    this.resumeCommitSlot = null;
    this.handoffPending = true;
    this.authorityBlocked = false;
    this.authorityReturnOnly = false;
    this.notice = '进攻命令已确认，正在进入战斗场景…';
    this.render();
    try {
      const envelope = await buildAs2BattleEnvelope({
        panelInstanceId: this.init.panelInstanceId,
        callId,
        sessionId: this.authoritySessionId,
        requestId,
        state: this.game,
        command,
        clientContext: this.authorityClientContext(),
      });
      if (this.disposed || this.pendingBattleCallId !== callId) return;
      const identity = as2ResumeIdentity({
        request: envelope.request,
        inputDigest: envelope.inputDigest,
      });
      if (!identity) throw new Error('生成的 AS2 战斗身份非法。');
      this.pendingBattleIdentity = identity.key;
      // 先安装等待提示，再交给可能同步回调的 Host。这样同步 ACK 可以真正
      // 取消计时器，不会在 bridgeSend 返回后又凭空创建一个过期计时器。
      this.clearAuthorityAckTimer();
      this.authorityAckTimer = window.setTimeout(() => {
        this.authorityAckTimer = null;
        if (this.disposed || this.pendingBattleCallId !== callId) return;
        // 这是等待提示，不是权威超时。迟到的 exact Host 响应仍必须能与
        // 原请求对应；只有明确 not_started 才能释放这份身份。
        this.setNotice('战斗场景仍在准备；已保留本次进攻身份，请勿重复下令。', 'info');
        this.render();
      }, 5000);
      const delivered = bridgeSend(envelope);
      if (this.disposed || this.pendingBattleCallId !== callId) return;
      // Host 可以在 bridgeSend 尚未返回时同步确认 prepared。该 exact 回包
      // 比 facade 的返回值更强；一旦接受，false 不得反向释放本次战斗身份。
      if (this.pendingBattlePrepared) return;
      if (delivered !== true) {
        this.recoverFromDefinitiveAs2BattleFailure(
          command,
          '战斗场景未能接收本次进攻；战略态未改变，请重新选择部队后再试。',
          '战斗场景未能接收本次进攻；本次进攻未写入战略态，敌方行动已结束，演习继续。',
        );
        return;
      }
    } catch {
      if (this.disposed || this.pendingBattleCallId !== callId) return;
      if (this.pendingBattlePrepared) return;
      this.recoverFromDefinitiveAs2BattleFailure(
        command,
        '战斗场景准备失败；战略态未改变，请重新选择部队后再试。',
        '战斗场景准备失败；本次进攻未写入战略态，敌方行动已结束，演习继续。',
      );
    }
  }

  private sendResumeApplied(
    resume: WarlordInitData['resume'],
    status: As2ResumeAppliedV1['status'],
  ): boolean {
    if (!this.stageAuthority.isStageMode) return true;
    const receipt = buildResumeAppliedReceipt(
      resume,
      this.init.stageOuterBinding,
      status,
    );
    if (!receipt || !this.init.resumeAppliedSend) return false;
    try {
      return this.init.resumeAppliedSend(receipt) === true;
    } catch {
      return false;
    }
  }

  private async consumeAs2Resume(resume: WarlordInitData['resume']): Promise<void> {
    const stageContextIdentity = this.stageAuthority.contextIdentity;
    const identity = as2ResumeIdentity(resume);
    let fingerprint: string;
    try {
      if (!identity) throw new Error('AS2 恢复身份不完整。');
      fingerprint = canonicalJson(resume);
    } catch {
      this.handoffPending = false;
      this.authorityBlocked = true;
      this.authorityReturnOnly = true;
      this.setNotice('战斗恢复身份无法校验；本局不能继续。请关闭面板后从任务提示选择“回基地”。', 'error');
      this.render();
      return;
    }

    const existing = this.resumeCommitSlot;
    if (existing) {
      if (existing.stageContextIdentity !== stageContextIdentity
        || existing.identity.key !== identity.key || existing.fingerprint !== fingerprint) {
        this.handoffPending = false;
        this.authorityBlocked = true;
        this.authorityReturnOnly = true;
        this.setNotice('收到与当前战斗身份冲突的恢复结果；为避免重复结算，本局不能继续。请返回基地。', 'error');
        this.render();
        return;
      }
      if (existing.phase === 'applying') return;
      if (existing.ackStatus !== null) {
        existing.ackSent = this.sendResumeApplied(resume, existing.ackStatus);
        if (!existing.ackSent) {
          this.authorityBlocked = true;
          this.authorityReturnOnly = false;
          this.setNotice('战斗结果已应用，但确认暂未送达；已保留原结果，等待 Host 以同一身份重试。', 'error');
          this.render();
        }
      }
      return;
    }
    if (this.pendingBattleIdentity !== null && this.pendingBattleIdentity !== identity.key) {
      this.handoffPending = false;
      this.authorityBlocked = true;
      this.authorityReturnOnly = true;
      this.setNotice('战斗恢复结果不属于当前进攻；为避免串局，本局不能继续。请返回基地。', 'error');
      this.render();
      return;
    }

    const slot: As2ResumeCommitSlot = {
      identity,
      fingerprint,
      stageContextIdentity,
      phase: 'applying',
      ackStatus: null,
      ackSent: false,
    };
    this.resumeCommitSlot = slot;
    const result = await applyAs2BattleResume(resume);
    if (this.disposed || this.resumeCommitSlot !== slot
      || this.stageAuthority.contextIdentity !== stageContextIdentity) return;
    this.handoffPending = false;
    this.pendingBattleCallId = null;
    this.pendingBattleCommand = null;
    this.pendingBattleIdentity = null;
    this.pendingBattlePrepared = false;
    this.clearAuthorityAckTimer();
    if (result.ok || !result.resultUnknown) this.authoritySessionId = identity.sessionId;
    if (!result.ok || !result.state || !result.battleRecord) {
      if (result.state) {
        this.game = result.state;
        slot.ackStatus = result.resultUnknown ? 'frozen' : 'applied';
      }
      slot.phase = 'committed';
      this.authorityBlocked = result.resultUnknown;
      this.authorityReturnOnly = result.resultUnknown;
      if (slot.ackStatus !== null) {
        slot.ackSent = this.sendResumeApplied(resume, slot.ackStatus);
      }
      if (slot.ackStatus !== null && !slot.ackSent) {
        this.authorityBlocked = true;
        this.authorityReturnOnly = false;
        this.setNotice(
          '战斗恢复状态已经读取，但 Host 尚未确认应用；当前战局保持冻结，请关闭面板后从任务提示恢复同一战局。',
          'error',
        );
        this.render();
        return;
      }
      this.setNotice(result.resultUnknown
        ? '战斗结果无法确认；本局不能继续。请关闭面板，再从任务提示选择“回基地”。'
        : '战斗结果无法载入；战略态未改变，请重新发起进攻。', 'error');
      this.render();
      return;
    }
    // 当前会话唯一的战略提交点。slot 在 await 前已登记，迟到或重复回执
    // 只能重发确认，不能再次进入这里。
    this.game = result.state;
    slot.phase = 'committed';
    slot.ackStatus = 'applied';
    slot.ackSent = this.sendResumeApplied(resume, 'applied');
    if (!slot.ackSent) {
      this.authorityBlocked = true;
      this.setNotice(
        '战斗结果已经载入，但 Host 尚未确认恢复完成；当前战局保持冻结，请关闭面板后从任务提示恢复同一战局。',
        'error',
      );
      this.render();
      return;
    }
    this.authorityBlocked = false;
    this.authorityReturnOnly = false;
    const command = resume && typeof resume === 'object' && 'command' in resume
      ? resume.command : null;
    const resumedCommand = command && typeof command === 'object'
      ? command as Partial<MoveOrAttackCommand> : null;
    if (resumedCommand?.type === 'MOVE_OR_ATTACK'
      && typeof resumedCommand.targetNodeId === 'string'
      && Array.isArray(resumedCommand.pieceIds)) {
      const move = resumedCommand as MoveOrAttackCommand;
      this.rememberAppliedTransitions(move);
      this.selectedNodeId = move.targetNodeId;
      this.selectedPieceIds = move.pieceIds
        .filter((pieceId) => this.game.pieces[pieceId]?.nodeId === move.targetNodeId);
    }
    // 玩家已经在 Flash 中看过并实际操作了这场战斗；恢复面板直接给出
    // 最终结算，避免再用 80/320ms 定时器把同一战斗自动回放一遍。
    this.openBattle(result.battleRecord, true);
    this.notice = '战斗结果已确认，战略地图已经更新。';
    this.render();
  }

  public handleHostResponse(response: unknown): boolean {
    if (!response || typeof response !== 'object') return false;
    const data = response as Record<string, unknown>;
    if (data.type !== 'panel_resp' || data.panel !== 'warlord'
      || data.cmd !== 'battle_start' || typeof data.callId !== 'string'
      || data.callId !== this.pendingBattleCallId) return false;
    this.clearAuthorityAckTimer();
    if (data.success === true || data.ok === true) {
      this.pendingBattlePrepared = true;
      this.notice = '进攻命令已接收，正在切换至战斗场景…';
      this.renderLiveRegion();
      return true;
    }
    const command = this.pendingBattleCommand;
    if (!command) {
      this.pendingBattleCallId = null;
      this.pendingBattlePrepared = false;
      this.handoffPending = false;
      this.authorityBlocked = true;
      this.authorityReturnOnly = true;
      this.setNotice('战斗入口响应无法对应原进攻命令；为避免重复发起，本局不能继续。请关闭面板后从任务提示选择“回基地”。', 'error');
      this.render();
      return true;
    }
    this.recoverFromDefinitiveAs2BattleFailure(
      command,
      '战斗场景拒绝了本次进攻；战略态未改变，请重新选择部队后再试。',
      '战斗场景拒绝了本次进攻；本次进攻未写入战略态，敌方行动已结束，演习继续。',
    );
    return true;
  }

  private scheduleAutomation(resumeAfterCamera = false): void {
    this.clearAutomation();
    if (this.disposed || this.panelCloseQuiesced || this.helpState.open
      || this.handoffPending || this.authorityBlocked
      || this.stageAuthority.blocksGameplay) return;
    if (this.aiCameraLease?.blocking) return;
    const record = this.playbackRecord;
    if (this.playback && record) {
      const total = record.result.eventLog.length;
      if (!this.playback.paused && this.playback.index < total) {
        const delay = this.playback.speed === 4 ? 80 : 320;
        this.automationTimer = window.setTimeout(() => {
          if (!this.playback || this.disposed) return;
          this.playback = { ...this.playback, index: this.playback.index + 1 };
          this.render();
        }, delay);
        return;
      }
      // AI 重放排队的战斗：播完后停留一拍再自动关闭，继续重放下一条命令
      if (this.playback.index >= total && this.aiReplay
        && this.aiReplay.index < this.aiReplay.commands.length) {
        this.automationTimer = window.setTimeout(() => {
          if (this.disposed || !this.playback) return;
          this.closeBattlePlayback();
        }, AI_BATTLE_DWELL_MS);
      }
      return;
    }
    if (this.aiReplay) {
      // 每条 AI 命令间隔不小于棋子补间时长，逐条投影中间态
      this.automationTimer = window.setTimeout(
        () => this.stepAiReplay(),
        resumeAfterCamera ? 0 : AI_REPLAY_INTERVAL_MS,
      );
      return;
    }
    const activeAiFactionId = this.activeAiFactionId();
    // 一个镜头段覆盖所有连续的非玩家行动。只要下一阵营仍由 AI
    // 驱动就继续持有；进入玩家阶段、结算规划或终局时才归位一次。
    if (this.aiCameraLease && activeAiFactionId === null) {
      this.returnAiActionCamera(this.aiCameraLease.token);
      return;
    }
    if (this.game.phase === 'GAME_OVER') return;
    if ((this.game.phase === 'FIRST_FACTION_ACTION' || this.game.phase === 'SECOND_FACTION_ACTION')
      && activeAiFactionId !== null) {
      if (this.init.battleAuthority === 'as2') {
        this.automationTimer = window.setTimeout(() => {
          if (this.disposed || this.handoffPending || this.authorityBlocked) return;
          const command = generateNextAiAction(this.game, activeAiFactionId, this.aiSeenTransitions);
          if (!command) {
            this.dispatch({ type: 'END_ACTION', factionId: activeAiFactionId }, `${requireFaction(this.game, activeAiFactionId).displayName}结束行动。`);
            return;
          }
          const validation = validateCommand(this.game, command);
          const isBattle = validation.ok && validation.isBattle === true;
          const cameraToken = validation.ok ? this.followAiAction(command) : null;
          const succeeded = this.dispatch(command, isBattle ? '敌方正在进入战斗。' : '敌方完成一次机动。');
          if (!succeeded) {
            if (cameraToken !== null) this.cancelAiActionCamera(cameraToken, true);
            return;
          }
          if (isBattle) {
            if (cameraToken !== null) this.cancelAiActionCamera(cameraToken, true);
            return;
          }
          this.rememberAppliedTransitions(command);
          if (cameraToken !== null) this.holdAiActionCameraForContinuation(cameraToken);
        }, resumeAfterCamera ? 0 : AI_AS2_INTERVAL_MS);
        return;
      }
      this.automationTimer = window.setTimeout(() => {
        if (this.disposed || this.aiReplay) return;
        this.beginAiReplay();
      }, 180);
      return;
    }
    const planningAiFactionId = this.pendingPlanningAiFactionId();
    if (this.game.phase === 'SETTLEMENT_PLANNING' && planningAiFactionId !== null) {
      this.automationTimer = window.setTimeout(() => {
        if (this.disposed) return;
        const ai = runAiPlanning(this.game, planningAiFactionId);
        this.game = ai.state;
        this.notice = `${requireFaction(this.game, planningAiFactionId).displayName}已经完成结算安排，共提交 ${ai.commands.length} 项。`;
        this.render();
      }, 150);
    }
  }

  // fixture 模式：先在行动前状态上跑出整回合命令，再按节奏逐条重放到真实状态
  private beginAiReplay(): void {
    const factionId = this.activeAiFactionId();
    if (!factionId) return;
    const run = runAiActionPhase(this.game, factionId);
    if (run.commands.length === 0) return;
    this.aiReplay = { commands: run.commands, index: 0 };
    this.scheduleAutomation();
  }

  private stepAiReplay(): void {
    const replay = this.aiReplay;
    if (!replay || this.disposed) return;
    const command = replay.commands[replay.index];
    if (!command) {
      this.aiReplay = null;
      this.render();
      return;
    }
    replay.index += 1;
    const isLast = replay.index >= replay.commands.length;
    const label = command.type === 'END_ACTION'
      ? '敌方结束行动。'
      : isLast
        ? `敌方完成行动，共执行 ${replay.commands.length} 项命令。`
        : `敌方正在行动（${replay.index}/${replay.commands.length}）。`;
    const validation = validateCommand(this.game, command);
    const cameraToken = validation.ok && command.type === 'MOVE_OR_ATTACK'
      ? this.followAiAction(command)
      : null;
    const succeeded = this.dispatch(command, label);
    // 防御：重放命令与实时状态不一致时放弃本次队列；下个渲染周期会按实时状态重建
    if (!succeeded) {
      this.aiReplay = null;
      if (cameraToken !== null) this.cancelAiActionCamera(cameraToken, true);
      return;
    }
    // AI 重放中的战斗以 4× 播完并排队依次呈现，不阻塞后续命令节奏
    if (this.playback && this.playback.speed !== 4) {
      this.playback = { ...this.playback, speed: 4 };
    }
    if (isLast) this.aiReplay = null;
    if (cameraToken !== null) {
      if (validation.ok && validation.isBattle === true && this.playback) {
        const pending = this.aiCameraLease;
        if (pending?.token === cameraToken) {
          pending.mode = 'battle';
          pending.blocking = false;
        }
        this.scheduleAutomation();
      } else {
        this.holdAiActionCameraForContinuation(cameraToken);
      }
    } else if (isLast) {
      this.scheduleAutomation(true);
    }
  }

  private dispatch(command: GameCommand, successNotice?: string, deferSuccessRender = false): boolean {
    if (this.handoffPending || this.authorityBlocked || this.stageAuthority.blocksGameplay) {
      this.setNotice(this.stageAuthority.status === 'blocked'
        ? '关卡身份校验失败；当前沙盘已锁定，不会按普通演习继续。'
        : this.stageAuthority.status === 'terminal_failed'
          ? '关卡结果尚未送达；当前沙盘保持打开且不能继续结算。'
          : this.stageAuthority.status === 'terminal_sent'
            ? '关卡结果已经提交，正在等待返回关卡。'
            : this.handoffPending
              ? '正在进入战斗场景，请稍候。'
              : '战斗结果暂时无法确认；为保护进度，当前对局已暂停。', 'error');
      this.render();
      return false;
    }
    if (this.playback) {
      this.setNotice('战斗播放期间不能提交战略命令。', 'error');
      this.render();
      return false;
    }
    const validation = validateCommand(this.game, command);
    if (!validation.ok) {
      this.setNotice(playerReasonSummary(validation.reasonCode, validation.reasonParams), 'error');
      this.render();
      return false;
    }
    if (this.init.battleAuthority === 'as2'
      && command.type === 'MOVE_OR_ATTACK'
      && validation.isBattle === true) {
      void this.beginAs2Battle(command);
      return true;
    }
    const result = applyCommand(this.game, command);
    if (!result.ok) {
      this.setNotice(playerReasonSummary(result.reasonCode, result.reasonParams), 'error');
      this.render();
      return false;
    }
    this.game = result.state;
    if (command.type === 'END_ACTION') this.aiSeenTransitions.clear();
    this.notice = successNotice ?? '命令已接受，战局已经更新。';
    if (result.battleId) {
      const record = this.game.battles.find((candidate) => candidate.battleId === result.battleId);
      if (record) this.openBattle(record);
    }
    if (!deferSuccessRender) this.render();
    return true;
  }

  private openBattle(record: BattleRecord, settled = false): void {
    // 阻塞式结算层期间维持零 WebGL context，杜绝隐藏沙盘参与合成。
    this.releaseSceneForBattleBoundary(this.aiCameraLease !== null);
    this.playback = {
      battleId: record.battleId,
      index: settled ? record.result.eventLog.length : 0,
      speed: 1,
      paused: settled,
      showLog: false,
    };
  }

  private inspectNode(nodeId: NodeId): void {
    if (!this.game.map.nodes[nodeId]) return;
    this.selectedNodeId = nodeId;
    this.selectedPieceIds = this.selectedPieceIds.filter((pieceId) => this.game.pieces[pieceId]?.nodeId === nodeId);
    const productionSlotId = firstProductionSlotId(this.game, this.playerId, nodeId);
    if (productionSlotId) {
      this.productionNodeId = nodeId;
      this.selectedSlotId = productionSlotId;
    }
    if (this.nodeNavigatorMode === 'all') {
      this.nodePageIndex = nodePageIndexFor(Object.keys(this.game.map.nodes) as NodeId[], nodeId);
    }
  }

  private selectNode(nodeId: NodeId): void {
    this.inspectNode(nodeId);
    this.notice = `已查看${requireNode(this.game, nodeId).displayName}。`;
    this.render();
  }

  // 门禁文案按真实原因分流：播放 / 战斗切换 / 结果未知 / 非我方行动阶段
  private selectionBlockReason(): string | null {
    if (this.playback) return '战斗播放期间不能建立编组或框选。';
    if (this.handoffPending) return '正在进入战斗场景，请稍候。';
    if (this.authorityBlocked) return '战斗结果未知，战略态已冻结。';
    if (this.stageAuthority.status === 'blocked') return '关卡身份无效，沙盘已锁定。';
    if (this.stageAuthority.status === 'terminal_failed') return '关卡结果尚未送达，沙盘已锁定。';
    if (this.stageAuthority.status === 'terminal_sent') return '关卡结果已经提交，正在返回关卡。';
    if (this.game.activeFactionId !== this.playerId
      || (this.game.phase !== 'FIRST_FACTION_ACTION' && this.game.phase !== 'SECOND_FACTION_ACTION')) {
      return '只有我方行动阶段可以建立命令编组。';
    }
    return null;
  }

  private canSelectPieces(): boolean {
    return this.selectionBlockReason() === null;
  }

  private commandElementsForSelection(memberIds: readonly string[] = this.selectedPieceIds): CommandElementState[] {
    const seen = new Set<string>();
    const elements: CommandElementState[] = [];
    for (const memberId of canonicalPieceIds(memberIds)) {
      const element = commandElementForMember(this.game, memberId);
      if (!element || seen.has(element.elementId)) continue;
      seen.add(element.elementId);
      elements.push(element);
    }
    return elements.sort((left, right) => left.elementId.localeCompare(right.elementId));
  }

  private completeMemberSelection(memberIds: readonly string[]): string[] {
    return canonicalPieceIds(this.commandElementsForSelection(memberIds)
      .flatMap((element) => element.memberIds));
  }

  private selectionOrigin(): NodeId | null {
    return this.commandElementsForSelection()
      .find((element) => element.factionId === this.playerId)?.nodeId ?? null;
  }

  private reconcileSelection(): void {
    const existing = canonicalPieceIds(this.selectedPieceIds)
      .filter((pieceId) => this.game.pieces[pieceId]?.factionId === this.playerId && this.game.pieces[pieceId]!.hp > 0);
    const elements = this.commandElementsForSelection(existing);
    const origin = elements[0]?.nodeId ?? null;
    this.selectedPieceIds = origin ? canonicalPieceIds(elements
      .filter((element) => element.factionId === this.playerId && element.nodeId === origin)
      .flatMap((element) => element.memberIds)) : [];
    for (const elementId of this.splitMemberSelections.keys()) {
      if (this.game.organization.commandElements[elementId]?.kind !== 'task_group') {
        this.splitMemberSelections.delete(elementId);
      }
    }
    // 编组被状态变化清空时，未确认的进攻武装一并解除
    if (!origin) this.disarmAttack();
    if (origin) this.inspectNode(origin);
  }

  private commandPreviews(): ActionPreview[] {
    // 战斗播放期间不做 3D 高亮与命令预览，点击降级为只读查看
    if (this.playback || this.handoffPending || this.authorityBlocked
      || this.stageAuthority.blocksGameplay) return [];
    const origin = this.selectionOrigin();
    if (!origin || this.selectedPieceIds.length === 0) return [];
    return buildActionPreviews(this.game, origin, this.selectedPieceIds);
  }

  private selectPiece(pieceId: string, additive: boolean): void {
    const piece = this.game.pieces[pieceId];
    const element = commandElementForMember(this.game, pieceId);
    if (!piece || !element) return;
    // 选择变化意味着进攻确认的目标上下文已改变
    this.disarmAttack();
    if (piece.factionId !== this.playerId) {
      if (this.selectedPieceIds.length > 0) {
        this.handleNodeIntent(piece.nodeId);
        return;
      }
      this.selectedPieceIds = [];
      this.inspectNode(piece.nodeId);
      this.notice = `${requireNode(this.game, piece.nodeId).displayName}的敌方棋子仅供查看。`;
      this.render();
      return;
    }
    const blockReason = this.selectionBlockReason();
    if (blockReason) {
      this.inspectNode(piece.nodeId);
      this.setNotice(blockReason, 'error');
      this.render();
      return;
    }

    const origin = this.selectionOrigin();
    const crossNode = additive && origin !== null && origin !== element.nodeId;
    const elementSelected = element.memberIds.every((memberId) => this.selectedPieceIds.includes(memberId));
    if (!additive || crossNode) {
      this.selectedPieceIds = [...element.memberIds];
    } else if (elementSelected) {
      const removed = new Set(element.memberIds);
      this.selectedPieceIds = this.selectedPieceIds.filter((id) => !removed.has(id));
    } else {
      this.selectedPieceIds = canonicalPieceIds([...this.selectedPieceIds, ...element.memberIds]);
    }
    this.inspectNode(element.nodeId);
    const selectedCount = this.commandElementsForSelection().length;
    this.notice = crossNode
      ? `部队选择不能跨据点；已改选${requireNode(this.game, element.nodeId).displayName}的 1 支部队。`
      : selectedCount > 0
        ? `已选 ${selectedCount} 支部队；点击高亮据点直接下令。`
        : '已取消该部队选择。';
    this.render();
  }

  private setPieceChecked(pieceId: string, checkedState: boolean): void {
    const piece = this.game.pieces[pieceId];
    const element = commandElementForMember(this.game, pieceId);
    if (!piece || !element || piece.factionId !== this.playerId || !this.canSelectPieces()) return;
    this.disarmAttack();
    if (!checkedState) {
      const removed = new Set(element.memberIds);
      this.selectedPieceIds = this.selectedPieceIds.filter((id) => !removed.has(id));
    } else if (this.selectionOrigin() !== null && this.selectionOrigin() !== element.nodeId) {
      this.selectedPieceIds = [...element.memberIds];
    } else {
      this.selectedPieceIds = canonicalPieceIds([...this.selectedPieceIds, ...element.memberIds]);
    }
    this.inspectNode(element.nodeId);
    const selectedCount = this.commandElementsForSelection().length;
    this.notice = selectedCount > 0
      ? `已选 ${selectedCount} 支部队；点击高亮据点直接下令。`
      : '当前部队选择已清空。';
    this.render();
  }

  private selectAllAtNode(nodeId: NodeId): void {
    this.disarmAttack();
    if (!this.canSelectPieces()) {
      this.selectNode(nodeId);
      return;
    }
    const elements = commandElementsAtNode(this.game, nodeId, this.playerId);
    const pieceIds = canonicalPieceIds(elements.flatMap((element) => element.memberIds));
    this.selectedPieceIds = pieceIds;
    this.inspectNode(nodeId);
    this.notice = pieceIds.length > 0
      ? `已选择${requireNode(this.game, nodeId).displayName}全部 ${elements.length} 支我方部队。`
      : `${requireNode(this.game, nodeId).displayName}没有可选己方棋子。`;
    this.render();
  }

  private applyMarqueeSelection(selection: {
    nodeId: NodeId | null;
    pieceIds: string[];
    ignoredCount: number;
    additive: boolean;
  }): void {
    this.disarmAttack();
    const marqueeBlockReason = this.selectionBlockReason();
    if (marqueeBlockReason) {
      this.setNotice(marqueeBlockReason, 'error');
      this.render();
      return;
    }
    if (!selection.nodeId || selection.pieceIds.length === 0) {
      if (!selection.additive) this.selectedPieceIds = [];
      this.notice = selection.additive ? '框选未命中己方棋子；原编组保持不变。' : '框选未命中己方棋子。';
      this.render();
      return;
    }
    const origin = this.selectionOrigin();
    const completeSelection = this.completeMemberSelection(selection.pieceIds);
    this.selectedPieceIds = selection.additive && origin === selection.nodeId
      ? canonicalPieceIds([...this.selectedPieceIds, ...completeSelection])
      : completeSelection;
    this.inspectNode(selection.nodeId);
    this.notice = `框选了 ${this.commandElementsForSelection().length} 支部队${selection.ignoredCount > 0 ? `；另有 ${selection.ignoredCount} 支因跨据点被忽略` : ''}。点击高亮据点直接下令。`;
    this.render();
  }

  private clearPieceSelection(notice: string): void {
    this.disarmAttack();
    if (this.selectedPieceIds.length === 0) return;
    this.selectedPieceIds = [];
    this.notice = notice;
    this.render();
  }

  private mergeSelectedTaskGroup(): void {
    this.disarmAttack();
    const elements = this.commandElementsForSelection();
    const template = DEMO_1_ORGANIZATION.taskGroupTemplates[0];
    const nodeId = this.selectionOrigin();
    if (!template || !nodeId) {
      this.setNotice('请先选择同一据点内至少两支我方部队。', 'error');
      this.render();
      return;
    }
    const formation = elements.find((element) => element.kind === 'task_group')?.formationProfileId
      ?? DEMO_1_ORGANIZATION.defaultFormationProfileRef as ArenaFormationId;
    const memberIds = canonicalPieceIds(elements.flatMap((element) => element.memberIds));
    const command: GameCommand = {
      type: 'MERGE_TASK_GROUP',
      factionId: this.playerId,
      nodeId,
      commandElementIds: elements.map((element) => element.elementId),
      taskGroupTemplateId: template.id,
      formationProfileId: formation,
    };
    if (!this.dispatch(command, undefined, true)) return;
    this.selectedPieceIds = memberIds.filter((memberId) => (this.game.pieces[memberId]?.hp ?? 0) > 0);
    this.notice = `已把 ${memberIds.length} 支成员部队合并为临时编队；重组不消耗行动点。`;
    this.render();
  }

  private setSplitMemberChecked(elementId: string, memberId: string, checkedState: boolean): void {
    const element = this.game.organization.commandElements[elementId];
    if (!element || element.kind !== 'task_group' || !element.memberIds.includes(memberId)) return;
    const selected = new Set(this.splitMemberSelections.get(elementId) ?? []);
    if (checkedState) selected.add(memberId);
    else selected.delete(memberId);
    this.splitMemberSelections.set(elementId, canonicalPieceIds(selected));
    this.render();
  }

  private splitTaskGroup(elementId: string): void {
    this.disarmAttack();
    const element = this.game.organization.commandElements[elementId];
    const memberIds = canonicalPieceIds(this.splitMemberSelections.get(elementId) ?? []);
    if (!element || element.kind !== 'task_group') {
      this.setNotice('这个临时编队已经失效，请重新选择。', 'error');
      this.render();
      return;
    }
    const allMemberIds = [...element.memberIds];
    const command: GameCommand = {
      type: 'SPLIT_TASK_GROUP',
      factionId: this.playerId,
      nodeId: element.nodeId,
      commandElementId: elementId,
      memberIds,
    };
    if (!this.dispatch(command, undefined, true)) return;
    this.splitMemberSelections.delete(elementId);
    this.selectedPieceIds = canonicalPieceIds(allMemberIds
      .filter((memberId) => (this.game.pieces[memberId]?.hp ?? 0) > 0));
    this.notice = `已从临时编队拆出 ${memberIds.length} 支部队；重组不消耗行动点。`;
    this.render();
  }

  private setCommandElementFormation(elementId: string, profileId: ArenaFormationId): void {
    const element = this.game.organization.commandElements[elementId];
    if (!element || element.formationProfileId === profileId) return;
    const profile = formationProfile(profileId);
    this.dispatch({
      type: 'SET_FORMATION',
      factionId: this.playerId,
      nodeId: element.nodeId,
      commandElementId: elementId,
      formationProfileId: profileId,
    }, `阵型已调整为${profile.displayName}；${formationEffect(profileId)}。`);
  }

  private handleNodeIntent(nodeId: NodeId): void {
    // 战斗播放期间节点点击降级为只读查看，不报"不相邻"等命令态文案
    if (this.playback) {
      this.selectNode(nodeId);
      return;
    }
    if (this.selectedPieceIds.length === 0) {
      this.selectNode(nodeId);
      return;
    }
    const originNodeId = this.selectionOrigin();
    if (!originNodeId) {
      this.selectedPieceIds = [];
      this.selectNode(nodeId);
      return;
    }
    if (nodeId === originNodeId) {
      this.setNotice(`${requireNode(this.game, nodeId).displayName}是当前编组起点；请选择高亮相邻据点。`, 'error');
      this.render();
      return;
    }
    const preview = this.commandPreviews().find((candidate) => candidate.targetNodeId === nodeId);
    if (!preview) {
      this.disarmAttack();
      this.setNotice(`${requireNode(this.game, nodeId).displayName}与当前编组起点不相邻；按退出键取消编组后可改为查看。`, 'error');
      this.render();
      return;
    }
    if (!preview.ok) {
      this.disarmAttack();
      this.setNotice(`无法向${preview.targetName}下令：${playerReasonSummary(preview.reasonCode ?? undefined, preview.reasonParams)}`, 'error');
      this.render();
      return;
    }
    // 进攻目标采用 arm-then-confirm：首次点击只武装，3 秒内二次点击同目标才执行
    if (preview.isBattle && this.armedTargetNodeId !== nodeId) {
      this.armAttack(nodeId, preview.targetName);
      return;
    }
    this.disarmAttack();
    this.executeSelectedCommand(originNodeId, preview);
  }

  private armAttack(nodeId: NodeId, targetName: string): void {
    this.clearAttackArmTimer();
    this.armedTargetNodeId = nodeId;
    this.setNotice(`再次点击确认进攻${targetName}；3 秒内有效，点击他处或退出键解除。`, 'error');
    this.attackArmTimer = window.setTimeout(() => {
      this.attackArmTimer = null;
      if (this.disposed || this.armedTargetNodeId !== nodeId) return;
      this.armedTargetNodeId = null;
      this.notice = `已解除对${targetName}的进攻确认。`;
      this.render();
    }, ATTACK_ARM_WINDOW_MS);
    this.render();
  }

  private disarmAttack(): void {
    if (this.armedTargetNodeId === null) return;
    this.armedTargetNodeId = null;
    this.clearAttackArmTimer();
  }

  private clearAttackArmTimer(): void {
    if (this.attackArmTimer !== null) window.clearTimeout(this.attackArmTimer);
    this.attackArmTimer = null;
  }

  private executeSelectedCommand(originNodeId: NodeId, preview: ActionPreview): void {
    const requestedCount = this.commandElementsForSelection().length;
    const command: GameCommand = {
      type: 'MOVE_OR_ATTACK',
      factionId: this.playerId,
      pieceIds: [...this.selectedPieceIds],
      originNodeId,
      targetNodeId: preview.targetNodeId,
      ...(preview.viaNodeId ? { viaNodeId: preview.viaNodeId } : {}),
    };
    if (!this.dispatch(command, undefined, true)) return;
    // 首次命令成功：引导从"下令"推进到"结束行动"
    this.coachCommandIssued = true;
    if (preview.isBattle && this.init.battleAuthority === 'as2') {
      this.selectedPieceIds = [];
      this.notice = '进攻命令已确认，正在进入战斗场景；战略地图会在战斗结束后更新。';
      this.render();
      return;
    }
    const followed = followCommandSelection(this.game, preview.actualPieceIds, preview.targetNodeId);
    this.selectedPieceIds = followed.pieceIds;
    this.inspectNode(followed.selectedNodeId);
    const appliedCount = preview.actualCommandElementCount;
    const followedCount = this.commandElementsForSelection(followed.pieceIds).length;
    const appliedCopy = appliedCount < requestedCount
      ? `仅 ${appliedCount}/${requestedCount} 支生效；`
      : `${appliedCount}/${requestedCount} 支生效；`;
    this.notice = followed.pieceIds.length > 0
      ? `${preview.isBattle ? '进攻' : '机动'}命令已接受，${appliedCopy}${followedCount} 支幸存部队保持选中。`
      : `${preview.isBattle ? '进攻' : '机动'}命令已接受，${appliedCopy}编组已无幸存部队。`;
    this.render();
  }

  private startNewGame(): void {
    if (this.stageAuthority.blocksGameplay) {
      this.setNotice(this.stageAuthority.status === 'blocked'
        ? '关卡身份校验失败；不能退回普通演习重新开始。'
        : '关卡终态已经形成；不能在当前关卡身份下重新开始。', 'error');
      this.renderLiveRegion();
      return;
    }
    this.clearAutomation();
    if (this.aiCameraLease) this.cancelAiActionCamera(this.aiCameraLease.token);
    this.clearAuthorityAckTimer();
    this.clearAttackArmTimer();
    this.aiReplay = null;
    this.armedTargetNodeId = null;
    this.handoffPending = false;
    this.authorityBlocked = false;
    this.authorityReturnOnly = false;
    this.pendingBattleCallId = null;
    this.pendingBattleCommand = null;
    this.pendingBattleIdentity = null;
    this.pendingBattlePrepared = false;
    this.resumeCommitSlot = null;
    this.aiSeenTransitions.clear();
    this.authoritySessionId = createAs2AuthoritySessionId();
    const themeChanged = this.themeDraft !== this.mapTheme;
    this.mapTheme = this.themeDraft;
    this.init = {
      ...this.init,
      seed: this.seedDraft,
      preset: this.presetDraft,
      difficulty: this.difficultyDraft,
      mapTheme: this.mapTheme,
    };
    if (themeChanged) this.restartScene();
    this.game = createGame({
      seed: this.seedDraft,
      preset: this.presetDraft,
      difficulty: this.difficultyDraft,
      runtimeBundle: runtimeMapBundleForScenarioRef(this.init.scenarioRef),
    });
    const playerFaction = this.playerFaction();
    this.selectedNodeId = this.game.preset === 'all-units'
      ? (Object.keys(playerFaction.productionQueues)[1] as NodeId | undefined) ?? playerFaction.commandPostNodeId
      : playerFaction.commandPostNodeId;
    this.selectedPieceIds = [];
    this.splitMemberSelections.clear();
    this.nodePageIndex = 0;
    this.largeMapSectorId = 'all';
    this.largeMapSearchQuery = '';
    this.largeMapToolsExpanded = false;
    this.productionControlMode = 'auto';
    this.productionNodeId = recommendProductionLane(this.game, this.playerId)?.nodeId
      ?? playerFaction.commandPostNodeId;
    this.selectedSlotId = firstProductionSlotId(this.game, this.playerId, this.productionNodeId)
      ?? `${this.productionNodeId}:1`;
    this.playback = null;
    this.configOpen = false;
    this.notice = `已重新开始${this.game.preset === 'all-units' ? '全兵种演习' : '标准对局'}。`;
    this.render();
  }

  private readonly onInput = (event: Event): void => {
    const target = event.target as HTMLInputElement | null;
    if (target?.dataset.field === 'seed') this.seedDraft = target.value;
    if (target?.dataset.field === 'large-map-search') this.largeMapSearchQuery = target.value;
  };

  private readonly onChange = (event: Event): void => {
    const target = event.target as HTMLInputElement | HTMLSelectElement | null;
    if (!target) return;
    if (target.dataset.field === 'piece') {
      this.setPieceChecked(target.value, (target as HTMLInputElement).checked);
    }
    if (target.dataset.field === 'task-group-member') {
      const elementId = target.dataset.element;
      if (elementId) this.setSplitMemberChecked(elementId, target.value, (target as HTMLInputElement).checked);
    }
    if (target.dataset.field === 'formation-profile') {
      const elementId = target.dataset.element;
      const profileId = target.value as ArenaFormationId;
      if (elementId && DEMO_1_ORGANIZATION.formationProfiles.some((profile) => profile.id === profileId)) {
        this.setCommandElementFormation(elementId, profileId);
      }
    }
    if (target.dataset.field === 'slot') {
      this.selectedSlotId = target.value;
      this.render();
    }
    if (target.dataset.field === 'production-node') {
      const nodeId = target.value as NodeId;
      if (!this.game.map.nodes[nodeId]) return;
      this.productionNodeId = nodeId;
      this.selectedSlotId = firstProductionSlotId(this.game, this.playerId, nodeId) ?? `${nodeId}:1`;
      this.notice = `正在查看${this.game.map.nodes[nodeId].displayName}生产队列。`;
      this.render();
    }
    if (target.dataset.field === 'large-map-sector' && this.game.scenarioId === 'warlord_demo_02_v1') {
      const sectors = this.largeMapSectors();
      const sector = sectors.find((candidate) => candidate.id === target.value);
      this.largeMapSectorId = sector?.id ?? 'all';
      this.nodeNavigatorMode = 'all';
      this.nodePageIndex = 0;
      const firstNodeId = sector?.nodeIds[0] as NodeId | undefined;
      if (firstNodeId) {
        this.selectedPieceIds = [];
        this.inspectNode(firstNodeId);
        this.scene?.focusNode(firstNodeId);
        this.notice = `已切换到${sector?.displayName ?? '全部战区'}。`;
      }
      this.render();
    }
    if (target.dataset.field === 'preset') this.presetDraft = target.value as PresetId;
    if (target.dataset.field === 'difficulty') this.difficultyDraft = target.value as Difficulty;
    if (target.dataset.field === 'map-theme') this.themeDraft = normalizeMapTheme(target.value);
  };

  private readonly onClick = (event: Event): void => {
    const target = (event.target as Element | null)?.closest<HTMLElement>('[data-action]');
    if (!target || target.hasAttribute('disabled')) return;
    const action = target.dataset.action;
    if (target.getAttribute('aria-disabled') === 'true') {
      const reasonText = target.dataset.reasonText;
      const reasonCode = target.dataset.reasonCode as ValidationReasonCode | undefined;
      this.setNotice(reasonText ?? playerTextForReason(reasonCode).assistiveText, 'error');
      this.renderLiveRegion();
      return;
    }
    if (action === 'open-help' || action === 'help-anchor') {
      const requested = target.dataset.helpAnchor;
      this.openHelp(isHelpAnchor(requested) ? requested : 'overview', target);
      return;
    }
    if (action === 'close-help') {
      this.closeHelp();
      return;
    }
    if (action === 'restart-coach') {
      this.coachDone = false;
      this.coachSkipped = false;
      this.coachCommandIssued = false;
      this.closeHelp();
      this.notice = '操作引导已重新打开；先选择一支我方部队。';
      this.renderCoach();
      this.renderLiveRegion();
      return;
    }
    if (action === 'skip-coach') {
      this.coachSkipped = true;
      this.renderCoach();
      this.notice = '操作引导已跳过，可随时从玩法帮助重新打开。';
      this.renderLiveRegion();
      return;
    }
    if (action === 'toggle-large-map-tools' && this.game.scenarioId === 'warlord_demo_02_v1') {
      this.largeMapToolsExpanded = !this.largeMapToolsExpanded;
      const app = this.root.querySelector<HTMLElement>('.warlord-app');
      if (app) app.dataset.largeMapToolsExpanded = String(this.largeMapToolsExpanded);
      this.renderLargeMapTools();
      this.renderNodes();
      queueMicrotask(() => {
        if (this.disposed) return;
        this.root.querySelector<HTMLElement>('[data-action="toggle-large-map-tools"]')
          ?.focus({ preventScroll: true });
      });
      return;
    }
    if (action === 'toggle-roster') {
      this.rosterCollapsed = !this.rosterCollapsed;
      const app = this.root.querySelector<HTMLElement>('.warlord-app');
      if (app) app.dataset.rosterCollapsed = String(this.rosterCollapsed);
      this.renderCards();
      queueMicrotask(() => {
        if (this.disposed) return;
        this.root.querySelector<HTMLElement>('[data-action="toggle-roster"]')
          ?.focus({ preventScroll: true });
      });
      return;
    }
    if (this.handoffPending) {
      this.setNotice('正在进入动作战斗；请等待当前沙盘自动切换。', 'error');
      this.renderLiveRegion();
      return;
    }
    if (this.stageAuthority.blocksGameplay && action !== 'request-close') {
      this.setNotice(this.stageAuthority.status === 'blocked'
        ? '关卡身份校验失败；当前沙盘已锁定，不会按普通演习继续。'
        : this.stageAuthority.status === 'terminal_failed'
          ? '关卡结果尚未送达；页面会保持打开，请勿重复操作。'
          : '关卡结果已经提交，正在等待返回关卡。', 'error');
      this.renderLiveRegion();
      return;
    }
    if (this.authorityBlocked && action !== 'request-close') {
      this.setNotice('战斗结果尚未确认，结算已经暂停；不会因此判负。', 'error');
      this.renderLiveRegion();
      return;
    }
    if (action === 'select-node') this.handleNodeIntent(target.dataset.node as NodeId);
    if (action === 'navigate-node' && target.dataset.node) {
      const nodeId = target.dataset.node as NodeId;
      this.navigateLargeMapNode(nodeId, `已定位${requireNode(this.game, nodeId).displayName}。`);
      return;
    }
    if (action === 'large-map-search' && this.game.scenarioId === 'warlord_demo_02_v1') {
      const sectors = this.largeMapSectors();
      const sectorIndex = buildLargeMapSectorIndex(sectors, Object.keys(this.game.map.nodes));
      const search = searchLargeMapNodes(
        this.largeMapNodeSummaries(sectorIndex.sectorByNodeId),
        sectors,
        this.largeMapSearchQuery,
        20,
      );
      const first = search.matches[0];
      if (!first) {
        this.setNotice('没有找到匹配的据点或战区；可尝试“中央”“弹药厂”或完整据点名。', 'error');
        this.renderLiveRegion();
        return;
      }
      this.largeMapSectorId = first.sectorId;
      this.nodeNavigatorMode = 'all';
      this.nodePageIndex = nodePageIndexFor(
        sectorIndex.nodeIdsBySectorId[first.sectorId] as readonly NodeId[] ?? [],
        first.nodeId as NodeId,
      );
      this.navigateLargeMapNode(
        first.nodeId as NodeId,
        search.totalMatches > 1
          ? `找到 ${search.totalMatches} 个匹配项，已定位第一个：${first.displayName}。`
          : `已定位${first.displayName}。`,
      );
      return;
    }
    if (action === 'select-all-at-node') this.selectAllAtNode(this.selectedNodeId);
    if (action === 'merge-task-group') this.mergeSelectedTaskGroup();
    if (action === 'split-task-group' && target.dataset.element) this.splitTaskGroup(target.dataset.element);
    if (action === 'toggle-node-scope') {
      this.nodeNavigatorMode = this.nodeNavigatorMode === 'context' ? 'all' : 'context';
      if (this.nodeNavigatorMode === 'all') {
        this.nodePageIndex = nodePageIndexFor(
          Object.keys(this.game.map.nodes) as NodeId[],
          this.selectedNodeId,
        );
      }
      this.renderNodes();
    }
    if (action === 'node-page-prev') {
      this.nodePageIndex = Math.max(0, this.nodePageIndex - 1);
      this.renderNodes();
    }
    if (action === 'node-page-next') {
      this.nodePageIndex += 1;
      this.renderNodes();
    }
    if (action === 'move') {
      this.handleNodeIntent(target.dataset.node as NodeId);
    }
    if (action === 'end-action') this.endRedAction();
    if (action?.startsWith('camera-')) this.revealCameraHud();
    if (action === 'camera-zoom-in') this.scene?.zoomBy(1.25);
    if (action === 'camera-zoom-out') this.scene?.zoomBy(0.8);
    if (action === 'camera-fit') this.scene?.fitToMap();
    if (action === 'camera-focus') this.scene?.focusNode(this.selectedNodeId);
    if (action === 'toggle-production-mode') {
      this.productionControlMode = this.productionControlMode === 'auto' ? 'exact' : 'auto';
      this.notice = this.productionControlMode === 'auto'
        ? '已启用自动调度：排产会选择全网负载最低的合法槽位。'
        : '已启用精确槽位：排产会严格使用当前查看的生产据点与槽位。';
      this.render();
    }
    if (action === 'choose-production-slot') {
      const nodeId = target.dataset.node as NodeId;
      const slotId = target.dataset.slot;
      if (!this.game.map.nodes[nodeId] || !slotId) return;
      this.productionNodeId = nodeId;
      this.selectedSlotId = slotId;
      this.productionControlMode = 'exact';
      this.notice = `已锁定${this.game.map.nodes[nodeId].displayName} ${slotId.split(':').at(-1)}号槽。`;
      this.render();
    }
    if (action === 'inspect-production-order') {
      const nodeId = target.dataset.node as NodeId;
      const slotId = target.dataset.slot;
      const orderId = target.dataset.order;
      if (!this.game.map.nodes[nodeId] || !slotId || !orderId) return;
      const orderExists = this.playerFaction().productionQueues[nodeId]
        ?.find((slot) => slot.slotId === slotId)
        ?.orders.some((order) => order.orderId === orderId);
      if (!orderExists) return;
      this.productionNodeId = nodeId;
      this.selectedSlotId = slotId;
      this.notice = `已定位${this.game.map.nodes[nodeId].displayName} ${slotId.split(':').at(-1)}号槽的在制订单；控制模式未改变。`;
      this.render();
    }
    if (action === 'cancel-production') {
      const nodeId = target.dataset.node as NodeId;
      const slotId = target.dataset.slot;
      const orderId = target.dataset.order;
      if (!this.game.map.nodes[nodeId] || !slotId || !orderId) return;
      const order = this.playerFaction().productionQueues[nodeId]
        ?.find((slot) => slot.slotId === slotId)
        ?.orders.find((candidate) => candidate.orderId === orderId);
      const orderName = order ? getCardDefinition(order.cardId).displayName : '该生产';
      const refund = order?.goldCost ?? 0;
      const released = order?.populationCost ?? 0;
      this.dispatch({
        type: 'CANCEL_PRODUCTION',
        factionId: this.playerId,
        nodeId,
        slotId,
        orderId,
      }, `${orderName}订单已撤销：返还军费 ${refund}，释放 ${released} 预留人口。`);
    }
    if (action === 'inspect-auto-slot') {
      const recommendation = recommendProductionLane(this.game, this.playerId);
      if (!recommendation) return;
      this.productionNodeId = recommendation.nodeId;
      this.selectedSlotId = recommendation.slotId;
      this.render();
    }
    if (action === 'allocate-xp') {
      const cardId = Number(target.dataset.card) as CardId;
      this.dispatch({
        type: 'ALLOCATE_XP',
        factionId: this.playerId,
        cardId,
        amount: Math.min(1000, this.playerFaction().xpPool),
      });
    }
    if (action === 'promotion') {
      this.dispatch({
        type: 'PURCHASE_PROMOTION',
        factionId: this.playerId,
        cardId: Number(target.dataset.card) as CardId,
        promotionId: target.dataset.promotion as PromotionId,
      });
    }
    if (action === 'production') {
      const cardId = Number(target.dataset.card) as CardId;
      const choice = resolveProductionChoice(
        this.game,
        this.playerId,
        cardId,
        this.productionControlMode,
        this.productionNodeId,
        this.selectedSlotId,
      );
      if (!choice.nodeId || !choice.slotId) {
        this.setNotice(playerReasonSummary(choice.reasonCode ?? undefined, choice.reasonParams), 'error');
        this.render();
        return;
      }
      this.productionNodeId = choice.nodeId;
      this.selectedSlotId = choice.slotId;
      this.dispatch({
        type: 'ENQUEUE_PRODUCTION',
        factionId: this.playerId,
        nodeId: choice.nodeId,
        slotId: choice.slotId,
        cardId,
      }, `${getCardDefinition(cardId).displayName}已加入${choice.nodeName} ${choice.slotNumber}号槽（${choice.mode === 'auto' ? '自动调度' : '精确槽位'}）。`);
    }
    if (action === 'redeploy-player-commander') {
      const commanderId = target.dataset.commander;
      if (!commanderId) return;
      this.dispatch({
        type: 'REDEPLOY_PLAYER_AVATAR',
        factionId: this.playerId,
        commanderId,
        nodeId: this.playerFaction().commandPostNodeId,
      }, '我方主角已从安全指挥所重新部署；下个战略回合开始贡献前线行动点。');
    }
    if (action === 'commit-planning') this.dispatch({ type: 'COMMIT_PLANNING', factionId: this.playerId });
    if (action === 'toggle-config') {
      this.configOpen = !this.configOpen;
      this.render();
    }
    if (action === 'request-close') {
      this.root.dispatchEvent(new CustomEvent('warlord:request-close', { bubbles: true }));
    }
    if (action === 'close-config') {
      this.configOpen = false;
      this.render();
    }
    if (action === 'new-game' || action === 'restart') this.startNewGame();
    if (action === 'battle-pause' && this.playback) {
      this.playback = { ...this.playback, paused: !this.playback.paused };
      this.render();
    }
    if (action === 'battle-speed' && this.playback) {
      this.playback = { ...this.playback, speed: this.playback.speed === 1 ? 4 : 1 };
      this.render();
    }
    if (action === 'battle-skip' && this.playbackRecord && this.playback) {
      this.playback = { ...this.playback, index: this.playbackRecord.result.eventLog.length, paused: true };
      this.render();
    }
    if (action === 'battle-log' && this.playback) {
      this.playback = { ...this.playback, showLog: !this.playback.showLog };
      this.render();
    }
    if (action === 'battle-close' && this.playbackRecord && this.playback
      && this.playback.index >= this.playbackRecord.result.eventLog.length) {
      this.closeBattlePlayback();
    }
  };

  private readonly onKeyDown = (event: KeyboardEvent): void => {
    if (this.disposed || !this.root.isConnected) return;
    if (this.trapHelpFocus(event)) return;
    if (isCameraSurfaceTarget(event.target) && isCameraNavigationKey(event.key)) this.revealCameraHud();
    if (event.key === 'Escape') {
      if (this.requestClose('escape')) event.preventDefault();
      return;
    }
    if (isEditableKeyboardTarget(event.target)) return;
    // 画布持焦时相机键由场景自己处理；这里只接管画布以外的全局入口，避免双触发
    if (isCameraNavigationKey(event.key) && !isCameraSurfaceTarget(event.target) && this.scene) {
      event.preventDefault();
      this.forwardCameraKey(event.key, event.shiftKey);
      this.revealCameraHud();
      return;
    }
    if (event.key === ' ' && this.playback) {
      event.preventDefault();
      this.playback = { ...this.playback, paused: !this.playback.paused };
      this.render();
      return;
    }
    if (event.key.toLowerCase() === 'e' && !this.playback && this.game.activeFactionId === this.playerId
      && (this.game.phase === 'FIRST_FACTION_ACTION' || this.game.phase === 'SECOND_FACTION_ACTION')) {
      event.preventDefault();
      this.endRedAction();
    }
  };

  // 与场景内键盘映射保持一致；平移步长随缩放百分比近似换算半高
  private forwardCameraKey(key: string, shiftKey: boolean): void {
    if (!this.scene) return;
    const normalized = key.toLowerCase();
    const zoom = Math.max(50, this.cameraSnapshot.zoomPercent || 100);
    const step = (36 / zoom) * (shiftKey ? 2.4 : 1);
    if (normalized === '+' || normalized === '=') this.scene.zoomBy(1.25);
    else if (normalized === '-' || normalized === '_') this.scene.zoomBy(0.8);
    else if (normalized === '0' || normalized === 'home') this.scene.fitToMap();
    else if (normalized === 'arrowleft' || normalized === 'a') this.scene.panBy(-step, 0);
    else if (normalized === 'arrowright' || normalized === 'd') this.scene.panBy(step, 0);
    else if (normalized === 'arrowup' || normalized === 'w') this.scene.panBy(0, -step);
    else if (normalized === 'arrowdown' || normalized === 's') this.scene.panBy(0, step);
  }

  private endRedAction(): void {
    if (this.dispatch({ type: 'END_ACTION', factionId: this.playerId })) {
      // 玩家完成过一整轮行动后不再显示首次引导
      this.coachDone = true;
      this.renderCoach();
    }
  }

  public requestClose(reason = 'escape'): boolean {
    if (this.disposed || reason !== 'escape') return false;
    if (this.helpState.open) {
      this.closeHelp();
      return true;
    }
    if (this.handoffPending) {
      this.setNotice('正在进入动作战斗；请等待当前沙盘自动切换。', 'error');
      this.renderLiveRegion();
      return true;
    }
    if (this.configOpen) {
      this.configOpen = false;
      this.render();
      return true;
    }
    if (this.largeMapToolsExpanded) {
      this.largeMapToolsExpanded = false;
      const app = this.root.querySelector<HTMLElement>('.warlord-app');
      if (app) app.dataset.largeMapToolsExpanded = 'false';
      this.renderLargeMapTools();
      this.renderNodes();
      queueMicrotask(() => {
        if (this.disposed) return;
        this.root.querySelector<HTMLElement>('[data-action="toggle-large-map-tools"]')
          ?.focus({ preventScroll: true });
      });
      return true;
    }
    if (this.armedTargetNodeId !== null) {
      const armedName = this.game.map.nodes[this.armedTargetNodeId]?.displayName ?? this.armedTargetNodeId;
      this.disarmAttack();
      this.notice = `已解除对${armedName}的进攻确认。`;
      this.render();
      return true;
    }
    // 战斗播放层：未播完先跳到结尾（等价"立即结算"），已播完则关闭播放窗（等价"返回沙盘"）
    if (this.playback && this.playbackRecord) {
      const total = this.playbackRecord.result.eventLog.length;
      if (this.playback.index < total) {
        this.playback = { ...this.playback, index: total, paused: true };
        this.notice = '已跳到战斗结尾；再按退出键返回沙盘。';
      } else {
        this.closeBattlePlayback();
        this.notice = '已关闭战斗播放，返回沙盘。';
        this.renderLiveRegion();
        return true;
      }
      this.render();
      return true;
    }
    if (this.selectedPieceIds.length > 0) {
      this.selectedPieceIds = [];
      this.notice = '已取消当前编组；节点点击恢复为查看。';
      this.render();
      return true;
    }
    return false;
  }

  public prepareStageClose(): 'not_stage' | 'ready' | 'blocked' {
    if (this.disposed) return 'blocked';
    const prepared = this.authorityBlocked && this.authorityReturnOnly
      ? this.stageAuthority.prepareActionResultUnknownClose()
      : this.stageAuthority.prepareUserClose();
    if (!prepared.handled) return 'not_stage';
    if (prepared.ready) {
      this.setNotice('关卡暂停状态已经提交，正在安全返回关卡。');
      this.renderLiveRegion();
      return 'ready';
    }
    this.setNotice(this.stageAuthority.status === 'blocked'
      ? '关卡身份无效，无法安全提交暂停状态；页面将保持打开。'
      : '关卡暂停状态尚未送达；页面将保持打开，不会直接返回基地。', 'error');
    this.renderAuthorityBanner();
    this.renderLiveRegion();
    return 'blocked';
  }

  /**
   * Host-owned close is acknowledged asynchronously.  Retire the only WebGL
   * owner before emitting that close intent so an overloaded/hidden WebView
   * cannot keep the sandtable context alive while the Host switches to idle.
   * Strategic state is untouched; a lost acknowledgement can rebuild exactly
   * one presentation scene in the same session.
   */
  public quiesceForPanelClose(): void {
    if (this.disposed || this.panelCloseQuiesced) return;
    this.panelCloseQuiesced = true;
    this.clearAutomation();
    this.releaseSceneForBattleBoundary(this.aiCameraLease !== null);
    if (this.aiCameraLease && !this.aiCameraLease.carry) this.aiCameraLease = null;
    this.root.dataset.sceneLifecycle = 'released_for_panel_close';
  }

  public resumeAfterPanelCloseTimeout(): void {
    if (this.disposed || !this.panelCloseQuiesced) return;
    this.panelCloseQuiesced = false;
    const pending = this.aiCameraLease;
    this.render();
    if (pending?.carry && this.scene) {
      const restoredToken = this.scene.restoreActionFollow(pending.carry);
      pending.carry = null;
      if (restoredToken !== null) {
        pending.token = restoredToken;
        this.holdAiActionCameraForContinuation(restoredToken);
      } else {
        this.aiCameraLease = null;
        this.scheduleAutomation(true);
      }
    }
  }

  private maybeEmitStageTerminal(): void {
    if (!this.stageAuthority.isStageMode) return;
    if (this.stageAuthority.status === 'blocked') {
      this.setNotice('关卡身份校验失败；当前沙盘已锁定，不会按普通演习继续。', 'error');
      return;
    }

    const emitted = canEmitStageGameOver(
      this.authorityBlocked,
      this.game.phase,
      this.game.result !== null,
    ) && this.game.result
      ? this.stageAuthority.emitGameOver(
        this.game.result.winner,
        this.playerId,
        this.game.result.winningVictoryGroupId,
        this.playerFaction().victoryGroupId,
      )
      : null;
    if (emitted === 'blocked' && this.stageAuthority.status === 'terminal_failed') {
      this.setNotice('关卡结果尚未送达；页面将保持打开，且不会把技术异常伪装成失败。', 'error');
    }
  }

  private render(): void {
    if (this.disposed) return;
    this.reconcileSelection();
    this.maybeEmitStageTerminal();
    if (this.disposed) return;
    const battleModalOpen = this.playbackRecord !== null;
    const sceneMustBeReleased = battleModalOpen || this.handoffPending || this.panelCloseQuiesced;
    // 防御性收口：从战斗请求冻结的同一次 render 起就释放沙盘，
    // 不等 Host 隐藏面板或结算遮罩出现。这样即使 exact-close 消息迟到，
    // Three rAF/context 也不会与 Flash Action 战场重叠。恢复失败解冻后
    // 再由下一分支按需建立唯一新场景。
    if (sceneMustBeReleased) this.releaseSceneForBattleBoundary();
    else if (!this.handoffPending && !this.scene && !this.sceneError) this.startScene();
    const app = this.root.querySelector<HTMLElement>('.warlord-app');
    if (app) {
      app.dataset.mapTheme = this.mapTheme;
      app.dataset.battleAuthority = this.init.battleAuthority;
      app.dataset.authorityState = this.authorityBlocked
        ? 'blocked' : this.handoffPending ? 'handoff' : 'ready';
      app.dataset.stageMode = this.stageAuthority.isStageMode ? 'stage-v1' : 'inactive';
      app.dataset.stageAuthority = this.stageAuthority.status;
      app.dataset.rosterCollapsed = String(this.rosterCollapsed);
      app.dataset.largeMapToolsExpanded = String(
        this.game.scenarioId === 'warlord_demo_02_v1' && this.largeMapToolsExpanded,
      );
      app.dataset.sceneLifecycle = this.panelCloseQuiesced
        ? 'released_for_panel_close'
        : battleModalOpen
        ? 'released_for_battle'
        : this.handoffPending
          ? this.pendingBattleCallId
            ? 'released_for_handoff'
            : 'deferred_for_resume'
          : this.scene
            ? 'active'
            : this.sceneError
              ? 'fallback'
              : 'absent';
    }
    this.renderCommandBar();
    this.renderForces();
    this.renderLargeMapTools();
    this.renderNodes();
    this.renderActions();
    this.renderCommandIntent();
    this.renderCards();
    this.renderPlanning();
    this.renderBattle();
    this.renderConfig();
    this.renderHelp();
    this.renderFallback();
    this.renderCameraHud();
    this.renderAuthorityBanner();
    this.renderCoach();
    this.renderLiveRegion();
    this.root.dataset.ready = 'true';
    this.root.dataset.phase = this.game.phase;
    this.root.dataset.selectedNode = this.selectedNodeId;
    this.root.dataset.selectedPieceCount = String(this.selectedPieceIds.length);
    const selectedElements = this.commandElementsForSelection();
    const selectedMetrics = this.selectedPieceIds.length > 0
      ? selectionOrganizationMetrics(this.game, this.selectedPieceIds)
      : { commandLoad: 0, deploymentSize: 0, encounterCost: 0, apContribution: 0, memberCount: 0 };
    this.root.dataset.selectedCommandElementCount = String(selectedElements.length);
    this.root.dataset.selectedMemberCount = String(this.selectedPieceIds.length);
    this.root.dataset.commandLoad = String(selectedMetrics.commandLoad);
    this.root.dataset.deploymentSize = String(selectedMetrics.deploymentSize);
    this.root.dataset.encounterCost = String(selectedMetrics.encounterCost);
    this.root.dataset.sceneLifecycle = app?.dataset.sceneLifecycle ?? 'absent';
    if (!battleModalOpen) {
      this.scene?.update(this.game, this.selectedNodeId, this.selectedPieceIds, this.commandPreviews());
    }
    const generation = this.portraitGeneration.next();
    void mountPortraits(this.root, this.init.playerAvatarPortrait).then(() => {
      if (!this.portraitGeneration.isCurrent(generation)) return;
      this.root.dataset.portraitsReady = 'true';
    });
    this.scheduleAutomation();
  }

  private renderCommandBar(): void {
    const round = this.root.querySelector<HTMLElement>('[data-region="round"]');
    const factions = this.root.querySelector<HTMLElement>('[data-region="factions"]');
    const theater = this.root.querySelector<HTMLElement>('[data-region="theater"]');
    if (theater) theater.textContent = `${MAP_THEMES[this.mapTheme].theaterLabel} · 战术指挥台`;
    const activeIndex = this.game.activeFactionId === null
      ? -1 : this.game.turnOrder.indexOf(this.game.activeFactionId);
    const phaseLabel = this.game.turnOrder.length > 2
      && (this.game.phase === 'FIRST_FACTION_ACTION' || this.game.phase === 'SECOND_FACTION_ACTION')
      ? `第 ${Math.max(1, activeIndex + 1)}/${this.game.turnOrder.length} 行动位`
      : PHASE_LABEL[this.game.phase];
    if (round) round.innerHTML = `<b>${escapeHtml(formatStrategicRound(this.game.strategicRound))}<small> / 共 24 回合</small></b><span>${phaseLabel} · ${this.game.activeFactionId ? `${factionLabel(this.game.activeFactionId, this.game)}行动` : '统一处理'}</span>`;
    if (factions) factions.innerHTML = this.game.turnOrder.map((factionId) => {
      const faction = requireFaction(this.game, factionId);
      const displayName = factionId === this.playerId ? '我方' : faction.displayName;
      const defeated = faction.defeatedAtRound === null ? '' : ' · 已败退';
      return `<section class="warlord-faction ${factionId}" data-testid="hud-${factionId}" data-action-points="${faction.actionPoints}" data-ap-spent="${faction.apSpentThisRound}" data-controller="${faction.controller}" data-victory-group="${escapeHtml(faction.victoryGroupId)}"><b>${escapeHtml(displayName)}</b><span><em>${escapeHtml(formatMilitaryFunds(faction.gold))}</em><em>人口 ${faction.populationUsed}+${faction.populationReserved}/${faction.populationCap}</em><em>${escapeHtml(formatActionPoints(faction.actionPoints))}${defeated}</em></span></section>`;
    }).join('');
  }

  private renderCommandElementCard(element: CommandElementState, canSelect: boolean): string {
    const representativeId = element.memberIds[0];
    const representative = representativeId ? this.game.pieces[representativeId] : undefined;
    if (!representative) return '';
    const metrics = commandElementMetrics(this.game, element);
    const selected = element.memberIds.every((memberId) => this.selectedPieceIds.includes(memberId));
    const definition = getCardDefinition(representative.cardId);
    const cardLevel = requireFaction(this.game, representative.factionId).cards[representative.cardId].level;
    const profile = formationProfile(element.formationProfileId);
    const commander = element.memberIds
      .map((memberId) => commanderForPiece(this.game, memberId))
      .find((candidate) => candidate !== null) ?? null;
    const commanderName = commander === null
      ? ''
      : commander.role === 'player_avatar'
        ? '我方主角'
        : getCardDefinition(commander.cardId).displayName;
    const elementName = element.kind === 'task_group'
      ? `临时编队 · ${element.memberIds.length} 支${commander ? ' · 含指挥官' : ''}`
      : commander
        ? `${commanderName} · 指挥官`
        : definition.displayName;
    const summary = element.kind === 'task_group'
      ? `${factionLabel(element.factionId, this.game)} · ${profile.displayName} · ${formationEffect(element.formationProfileId)}`
      : `${factionLabel(element.factionId, this.game)} · 等级 ${cardLevel} · 生命 ${representative.hp}/${representative.maxHp}`;
    const commanderAttributes = commander
      ? ` data-commander-id="${escapeHtml(commander.commanderId)}" data-commander-role="${commander.role}"`
      : '';
    const commanderBadge = commander
      ? `<small class="warlord-commander-badge">${escapeHtml(commander.role === 'player_avatar' ? '主角指挥官' : `${commanderName} · 军阀指挥官`)}</small>`
      : '';
    const portrait = commander?.role === 'player_avatar'
      ? this.init.playerAvatarPortrait !== null
        ? '<span class="warlord-mini-portrait warlord-player-avatar-portrait" data-warlord-player-avatar><img alt=""></span>'
        : '<span class="warlord-mini-portrait warlord-player-avatar-unavailable"><img alt=""></span>'
      : `<span class="warlord-mini-portrait" data-warlord-portrait="${escapeHtml(definition.identifier)}"><img alt=""></span>`;
    const card = `<label class="warlord-piece warlord-command-element ${element.factionId}${selected ? ' selected' : ''}${commander ? ' is-commander' : ''}" data-piece-id="${escapeHtml(representativeId)}" data-command-element-id="${escapeHtml(element.elementId)}" data-element-kind="${element.kind}" data-member-count="${element.memberIds.length}" data-command-load="${metrics.commandLoad}" data-deployment-size="${metrics.deploymentSize}" data-encounter-cost="${metrics.encounterCost}" data-formation-profile="${element.formationProfileId}"${commanderAttributes}>
      <input type="checkbox" data-field="piece" value="${escapeHtml(representativeId)}" aria-label="选择${escapeHtml(elementName)}，行动消耗 ${metrics.commandLoad}，规模 ${metrics.deploymentSize}，战斗负载 ${metrics.encounterCost}"${checked(selected)}${disabled(!canSelect || element.factionId !== this.playerId)}>
      ${portrait}
      <span><b>${escapeHtml(elementName)}</b>${commanderBadge}<small>${escapeHtml(summary)}</small><small class="warlord-element-metrics">行动消耗 ${metrics.commandLoad} · 规模 ${metrics.deploymentSize} · 战斗负载 ${metrics.encounterCost}</small>${element.kind === 'singleton' ? `<i${hpBarClass(representative.hp, representative.maxHp)}><em style="width:${hpPercent(representative.hp, representative.maxHp)}%"></em></i>` : ''}</span>
    </label>`;
    if (element.kind !== 'task_group' || element.factionId !== this.playerId) return card;

    const template = DEMO_1_ORGANIZATION.taskGroupTemplates.find((entry) => entry.id === element.taskGroupTemplateId);
    const allowedProfiles = DEMO_1_ORGANIZATION.formationProfiles.filter((candidate) => (
      !template || template.formationProfileRefs.includes(candidate.id)
    ));
    const splitMembers = new Set(this.splitMemberSelections.get(element.elementId) ?? []);
    const splitValidation = validateCommand(this.game, {
      type: 'SPLIT_TASK_GROUP',
      factionId: this.playerId,
      nodeId: element.nodeId,
      commandElementId: element.elementId,
      memberIds: canonicalPieceIds(splitMembers),
    });
    const splitReason = splitValidation.ok
      ? '' : playerReasonSummary(splitValidation.reasonCode, splitValidation.reasonParams);
    return `<article class="warlord-task-group" data-command-element-id="${escapeHtml(element.elementId)}" data-element-kind="task_group" data-member-count="${element.memberIds.length}" data-command-load="${metrics.commandLoad}" data-deployment-size="${metrics.deploymentSize}" data-encounter-cost="${metrics.encounterCost}" data-formation-profile="${element.formationProfileId}">
      ${card}
      <div class="warlord-task-group-controls">
        <fieldset class="warlord-formation-picker"><legend>阵型</legend><div>${allowedProfiles.map((candidate) => `<label><input type="radio" name="formation-${escapeHtml(element.elementId)}" data-field="formation-profile" data-element="${escapeHtml(element.elementId)}" value="${candidate.id}"${checked(candidate.id === element.formationProfileId)}${disabled(!canSelect)}><span>${escapeHtml(candidate.displayName)}</span></label>`).join('')}</div><p data-formation-effect>${escapeHtml(formationEffect(element.formationProfileId))}</p></fieldset>
        <fieldset class="warlord-task-group-members"><legend>拆出成员</legend>${element.memberIds.map((memberId) => {
          const member = this.game.pieces[memberId];
          if (!member) return '';
          const memberDefinition = getCardDefinition(member.cardId);
          return `<label data-task-group-member="${escapeHtml(memberId)}"><input type="checkbox" data-field="task-group-member" data-element="${escapeHtml(element.elementId)}" value="${escapeHtml(memberId)}"${checked(splitMembers.has(memberId))}${disabled(!canSelect)}><span>${escapeHtml(memberDefinition.displayName)} · 生命 ${member.hp}/${member.maxHp}</span></label>`;
        }).join('')}</fieldset>
        <button data-action="split-task-group" data-element="${escapeHtml(element.elementId)}"${ariaDisabled(!splitValidation.ok)} data-reason-code="${splitValidation.reasonCode ?? ''}" data-reason-text="${escapeHtml(splitReason)}" title="${escapeHtml(splitValidation.ok ? '把勾选成员拆为独立部队；不消耗行动点' : splitReason)}">拆出所选</button>
      </div>
    </article>`;
  }

  private renderForces(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="forces"]');
    if (!region) return;
    const node = requireNode(this.game, this.selectedNodeId);
    const pieces = piecesAtNode(this.game, this.selectedNodeId);
    const elements = commandElementsAtNode(this.game, this.selectedNodeId);
    const canSelect = this.canSelectPieces();
    const playerElements = elements.filter((element) => element.factionId === this.playerId);
    const selectedElements = this.commandElementsForSelection()
      .filter((element) => element.factionId === this.playerId && element.nodeId === this.selectedNodeId);
    const template = DEMO_1_ORGANIZATION.taskGroupTemplates[0];
    const mergeFormation = selectedElements.find((element) => element.kind === 'task_group')?.formationProfileId
      ?? DEMO_1_ORGANIZATION.defaultFormationProfileRef as ArenaFormationId;
    const mergeValidation = template ? validateCommand(this.game, {
      type: 'MERGE_TASK_GROUP',
      factionId: this.playerId,
      nodeId: this.selectedNodeId,
      commandElementIds: selectedElements.map((element) => element.elementId),
      taskGroupTemplateId: template.id,
      formationProfileId: mergeFormation,
    }) : null;
    const mergeReason = mergeValidation?.ok
      ? '' : playerReasonSummary(mergeValidation?.reasonCode, mergeValidation?.reasonParams);
    const encounterText = playerEncounterDistanceText(node.distanceBand);
    region.dataset.commandElementCount = String(elements.length);
    region.dataset.taskGroupCount = String(elements.filter((element) => element.kind === 'task_group').length);
    region.dataset.deploymentSize = String(nodeDeploymentSize(this.game, this.selectedNodeId));
    region.dataset.encounterProfileRef = node.encounterProfileRef;
    region.dataset.distanceBand = node.distanceBand;
    region.dataset.spawnDistance = String(node.spawnDistance);
    region.innerHTML = `<header><span>当前据点</span><b>${escapeHtml(node.displayName)}</b><small>${escapeHtml(ownerLabel(node.ownerFactionId, this.game))} · 驻军 ${nodeDeploymentSize(this.game, this.selectedNodeId)} / 上限 ${node.capacity} · <span role="note" data-encounter-distance="${node.distanceBand}" data-encounter-profile-ref="${node.encounterProfileRef}" data-spawn-distance="${node.spawnDistance}" aria-label="${escapeHtml(encounterText.assistiveText)}">${escapeHtml(encounterText.compactLabel)}</span></small></header>
      <div class="warlord-force-toolbar"><button class="warlord-select-all" data-action="select-all-at-node" aria-label="全选本据点全部己方部队" title="全选本据点全部己方部队（等同双击部队）"${disabled(playerElements.length === 0)}>全选本据点</button><button data-action="merge-task-group"${ariaDisabled(mergeValidation?.ok !== true)} data-reason-code="${mergeValidation?.reasonCode ?? ''}" data-reason-text="${escapeHtml(mergeReason)}" title="${escapeHtml(mergeValidation?.ok ? '合并为临时编队；不消耗行动点' : mergeReason)}">合并为临时编队</button></div>
      <div class="warlord-force-list">${pieces.length === 0 ? '<p class="warlord-empty">无人驻守</p>' : elements.map((element) => this.renderCommandElementCard(element, canSelect)).join('')}</div>
      <div class="warlord-node-facts"><span>本次最多投入 ${node.attackWidth}</span><span>防守上限 ${node.defenseWidth}</span><span>每轮军费 +${node.goldIncome}</span><span>行动点 +${node.apBonus}</span></div>`;
  }

  private largeMapSectors(): readonly LargeMapSector[] {
    return DEMO_2_SECTORS.map((sector) => ({
      id: sector.id,
      displayName: sector.displayName,
      nodeIds: sector.nodeRefs,
    }));
  }

  private largeMapNodeSummaries(
    sectorByNodeId: Readonly<Record<string, string>>,
  ): LargeMapNodeSummary[] {
    return Object.values(this.game.map.nodes).map((node) => ({
      nodeId: node.nodeId,
      displayName: node.displayName,
      kind: node.kind,
      sectorId: sectorByNodeId[node.nodeId] ?? '',
      ownerFactionId: node.ownerFactionId,
      searchTerms: [ownerLabel(node.ownerFactionId, this.game)],
    }));
  }

  private navigateLargeMapNode(nodeId: NodeId, notice: string): void {
    if (!this.game.map.nodes[nodeId]) return;
    this.selectedPieceIds = [];
    this.inspectNode(nodeId);
    this.scene?.focusNode(nodeId);
    this.notice = notice;
    this.render();
  }

  private renderLargeMapTools(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="large-map"]');
    if (!region) return;
    if (this.game.scenarioId !== 'warlord_demo_02_v1') {
      region.hidden = true;
      region.dataset.expanded = 'false';
      region.innerHTML = '';
      return;
    }

    const sectors = this.largeMapSectors();
    const nodeIds = Object.keys(this.game.map.nodes);
    const sectorIndex = buildLargeMapSectorIndex(sectors, nodeIds);
    const playerFaction = this.playerFaction();
    const signals: LargeMapNodeSignal[] = [];
    const commandPostNode = requireNode(this.game, playerFaction.commandPostNodeId);
    const commandPostThreatened = adjacentNodeIds(this.game, playerFaction.commandPostNodeId).some((nodeId) => (
      nodeOccupyingFactions(this.game, nodeId).some((factionId) => (
        relationBetween(this.game, this.playerId, factionId) === 'hostile'
      ))
    ));
    if (commandPostThreatened) {
      signals.push({
        nodeId: commandPostNode.nodeId,
        nodeDisplayName: commandPostNode.displayName,
        sectorId: sectorIndex.sectorByNodeId[commandPostNode.nodeId] ?? 'sector.player-home',
        commandPostThreatened: true,
      });
    }
    for (const [nodeId, slots] of Object.entries(playerFaction.productionQueues)) {
      if (!slots?.some((slot) => slot.orders.some((order) => order.status === 'waiting_deployment'))) continue;
      const node = this.game.map.nodes[nodeId];
      if (!node) continue;
      signals.push({
        nodeId,
        nodeDisplayName: node.displayName,
        sectorId: sectorIndex.sectorByNodeId[nodeId] ?? 'sector.player-home',
        productionBlockedReason: '有已完工部队等待驻军或人口空间',
      });
    }
    if (this.handoffPending) {
      const node = requireNode(this.game, this.selectedNodeId);
      signals.push({
        nodeId: node.nodeId,
        nodeDisplayName: node.displayName,
        sectorId: sectorIndex.sectorByNodeId[node.nodeId] ?? 'sector.central-industry',
        encounterPending: true,
      });
    }
    const activeFactionId = this.game.activeFactionId;
    if (activeFactionId) {
      const activePiece = Object.values(this.game.pieces)
        .filter((piece) => piece.factionId === activeFactionId)
        .sort((left, right) => left.pieceId.localeCompare(right.pieceId))[0];
      if (activePiece) {
        const node = requireNode(this.game, activePiece.nodeId);
        signals.push({
          nodeId: node.nodeId,
          nodeDisplayName: node.displayName,
          sectorId: sectorIndex.sectorByNodeId[node.nodeId] ?? 'sector.central-industry',
          currentAction: `${requireFaction(this.game, activeFactionId).displayName}正在行动`,
        });
      }
    }
    const alerts = deriveLargeMapAlerts(signals, 4);
    const commanderStatusLabel: Readonly<Record<string, string>> = {
      fielded: '在前线',
      downed: '已倒地',
      rear: '在后方',
      available: '可重建',
      queued: '重建中',
    };
    const commanderSummary = Object.values(this.game.commanders)
      .sort((left, right) => this.game.turnOrder.indexOf(left.factionId) - this.game.turnOrder.indexOf(right.factionId))
      .map((commander) => {
        const faction = requireFaction(this.game, commander.factionId);
        const name = commander.factionId === this.playerId
          ? '我方主角'
          : `${getCardDefinition(commander.cardId).displayName}（${faction.displayName}）`;
        return `<span data-commander-status="${commander.status}">${escapeHtml(name)}：${escapeHtml(commanderStatusLabel[commander.status] ?? commander.status)}</span>`;
      }).join('');
    const sectorOptions = [
      '<option value="all">全部战区</option>',
      ...sectors.map((sector) => `<option value="${escapeHtml(sector.id)}"${selected(this.largeMapSectorId === sector.id)}>${escapeHtml(sector.displayName)}</option>`),
    ].join('');
    const alertButtons = alerts.alerts.map((alert) => (
      `<button data-action="navigate-node" data-node="${escapeHtml(alert.nodeId)}" title="${escapeHtml(`${alert.detail} ${alert.nextStep}`)}"><b>${escapeHtml(alert.title)}</b><span>${escapeHtml(requireNode(this.game, alert.nodeId as NodeId).displayName)}</span></button>`
    )).join('');
    region.hidden = !this.largeMapToolsExpanded;
    region.dataset.expanded = String(this.largeMapToolsExpanded);
    region.dataset.totalNodes = String(nodeIds.length);
    region.dataset.totalAlerts = String(alerts.totalAlerts);
    region.innerHTML = `<div class="warlord-large-map-search"><label><span>战区</span><select data-field="large-map-sector">${sectorOptions}</select></label><label><span>查找</span><input data-field="large-map-search" value="${escapeHtml(this.largeMapSearchQuery)}" placeholder="据点或战区名称"></label><button data-action="large-map-search">定位</button></div><div class="warlord-large-map-alerts" aria-label="战区告警">${alertButtons || '<span>当前没有紧急告警</span>'}</div><div class="warlord-large-map-commanders" aria-label="指挥官状态">${commanderSummary}</div>`;
  }

  private renderNodes(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="nodes"]');
    if (!region) return;
    const allProjections = projectNodes(this.game);
    const sector = this.game.scenarioId === 'warlord_demo_02_v1' && this.largeMapSectorId !== 'all'
      ? this.largeMapSectors().find((candidate) => candidate.id === this.largeMapSectorId)
      : null;
    const allowedNodeIds = sector ? new Set(sector.nodeIds) : null;
    const projections = allowedNodeIds
      ? allProjections.filter((node) => allowedNodeIds.has(node.nodeId))
      : allProjections;
    const byId = new Map(projections.map((node) => [node.nodeId, node]));
    const previewById = new Map(this.commandPreviews().map((preview) => [preview.targetNodeId, preview]));
    const window = buildNodeNavigatorWindow({
      nodeIds: projections.map((node) => node.nodeId),
      edges: this.game.map.edges,
      selectedNodeId: this.selectedNodeId,
      mode: this.nodeNavigatorMode,
      requestedPage: this.nodePageIndex,
    });
    this.nodePageIndex = window.pageIndex;
    region.dataset.mode = window.mode;
    const isLargeMap = this.game.scenarioId === 'warlord_demo_02_v1';
    region.dataset.largeMap = String(isLargeMap);
    region.dataset.totalNodes = String(window.totalCount);
    region.dataset.visibleNodes = String(window.nodeIds.length);
    region.dataset.page = String(window.pageIndex + 1);
    region.dataset.pages = String(window.pageCount);
    const scopeLabel = window.mode === 'context' ? '局部' : '全域';
    const scopeMeta = window.mode === 'context'
      ? `${window.nodeIds.length}/${window.totalCount}`
      : `${window.pageIndex + 1}/${window.pageCount}`;
    const selectedElementCount = this.commandElementsForSelection().length;
    const cards = window.nodeIds
      .map((nodeId) => byId.get(nodeId))
      .filter((node) => node !== undefined)
      .map((node) => {
        const preview = previewById.get(node.nodeId);
        const partial = preview?.ok === true && preview.actualCommandElementCount < selectedElementCount;
        const commandState = preview?.ok
          ? preview.isBattle ? 'attack' : partial ? 'partial' : 'move'
          : preview ? 'invalid' : 'none';
        const shortName = compactProductionNodeName(node.displayName);
        const status = `${node.ownerLabel}${node.stable ? '·稳' : ''}`;
        const reasonText = preview && !preview.ok
          ? playerTextForReason(preview.reasonCode ?? undefined, preview.reasonParams)
          : null;
        const commandCopy = !preview ? status
          : preview.ok
            ? `${preview.isBattle ? '进攻' : '机动'} ${preview.actualCommandElementCount}/${selectedElementCount}`
            : '暂不可下令';
        const accessibleLabel = `${node.displayName}，我方 ${node.redCount}，敌方 ${node.blueCount}，${node.ownerLabel}${node.stable ? '，稳定' : ''}${preview ? `，${preview.ok ? commandCopy : reasonText?.assistiveText}` : ''}`;
        const reasonAttributes = reasonText
          ? `${ariaDisabled(true)} data-reason-code="${preview?.reasonCode ?? ''}" data-reason-text="${escapeHtml(reasonText.assistiveText)}"`
          : '';
        return `<button class="warlord-node-card owner-${node.ownerFactionId ?? 'neutral'}${node.nodeId === this.selectedNodeId ? ' selected' : ''}${node.contested ? ' contested' : ''}${preview ? ` command-${commandState}` : ''}" data-action="select-node" data-node="${node.nodeId}" data-command-state="${commandState}" data-command-actual="${preview?.actualCommandElementCount ?? 0}" data-command-requested="${selectedElementCount}" data-command-load="${preview?.commandLoad ?? 0}" data-deployment-size="${preview?.deploymentSize ?? 0}" data-encounter-cost="${preview?.encounterCost ?? 0}" data-testid="node-${node.nodeId}" aria-label="${escapeHtml(accessibleLabel)}" title="${escapeHtml(reasonText?.assistiveText ?? accessibleLabel)}" aria-pressed="${node.nodeId === this.selectedNodeId}"${reasonAttributes}><b>${escapeHtml(shortName)}</b><span class="warlord-node-meta"><em>我方 ${node.redCount} / 敌方 ${node.blueCount}</em><i>${escapeHtml(commandCopy)}</i></span></button>`;
      }).join('');
    const largeMapToggle = isLargeMap
      ? `<button class="warlord-large-map-toggle" data-action="toggle-large-map-tools" aria-controls="warlord-large-map-tools" aria-expanded="${this.largeMapToolsExpanded}" aria-label="${this.largeMapToolsExpanded ? '收起战区筛选与告警' : '展开战区筛选与告警'}" title="${this.largeMapToolsExpanded ? '收起战区筛选与告警' : '展开战区筛选与告警'}"><b>战区</b><span>${this.largeMapToolsExpanded ? '收起筛选' : '展开筛选'}</span></button>`
      : '';
    region.innerHTML = `<div class="warlord-node-index">
      <button data-action="toggle-node-scope" aria-label="切换局部与全域节点索引"><b>${scopeLabel}</b><span>${scopeMeta}</span></button>
      <div class="warlord-node-pager"${window.mode === 'context' ? ' hidden' : ''}>
        <button data-action="node-page-prev" aria-label="上一页节点"${disabled(!window.hasPrevious)}>‹</button>
        <button data-action="node-page-next" aria-label="下一页节点"${disabled(!window.hasNext)}>›</button>
      </div>
    </div>${largeMapToggle}<div class="warlord-node-window">${cards}</div>`;
  }

  private renderProductionConsole(planning: boolean): string {
    const nodes = projectProductionNodes(this.game, this.playerId);
    const inspected = nodes.find((node) => node.nodeId === this.productionNodeId) ?? nodes[0];
    const recommendation = recommendProductionLane(this.game, this.playerId);
    if (!inspected) {
      return '<section class="warlord-production-console is-empty"><b>生产网不可用</b><span>当前没有可检查的己方生产据点。</span></section>';
    }
    const modeIsAuto = this.productionControlMode === 'auto';
    const networkOrders = flattenProductionOrders(nodes);
    const orderCount = networkOrders.length;
    const latestCancellable = networkOrders
      .filter((order) => order.cancellable)
      .sort((a, b) => Number(a.orderId.slice(1)) - Number(b.orderId.slice(1)))
      .at(-1) ?? null;
    const nodeOptions = nodes.map((node) => `<option value="${escapeHtml(node.nodeId)}"${selected(node.nodeId === inspected.nodeId)}>${escapeHtml(node.displayName)} · ${node.orderCount}单 · 余${node.freeCapacity}/${node.capacity}</option>`).join('');
    const lanes = inspected.lanes.map((lane) => {
      const recommended = modeIsAuto
        && recommendation?.nodeId === lane.nodeId
        && recommendation.slotId === lane.slotId;
      const exactSelected = !modeIsAuto
        && this.productionNodeId === lane.nodeId
        && this.selectedSlotId === lane.slotId;
      const detail = lane.blockerLabels.length > 0
        ? lane.blockerLabels.join(' · ')
        : lane.head?.phaseLabel ?? '可立即开工';
      const headDetail = lane.head?.cancellable ? `${detail} · 可全额撤销` : detail;
      const tailNames = lane.tail.map((order) => order.displayName).join(' → ');
      const head = lane.head
        ? `<span class="warlord-queue-portrait" data-warlord-portrait="${escapeHtml(lane.head.portraitRef)}"><img alt=""></span><span class="warlord-production-order"><b>${escapeHtml(lane.head.displayName)}</b><small>${escapeHtml(headDetail)}</small></span>`
        : '<span class="warlord-queue-empty" aria-hidden="true">＋</span><span class="warlord-production-order"><b>等待订单</b><small>点击下方兵种开始排产</small></span>';
      const progress = lane.head?.progressPercent ?? 0;
      const headCancel = lane.head?.cancellable
        ? `<button class="warlord-production-cancel" data-action="cancel-production" data-node="${escapeHtml(lane.nodeId)}" data-slot="${escapeHtml(lane.slotId)}" data-order="${escapeHtml(lane.head.orderId)}" data-cancellable="true" aria-label="撤销${escapeHtml(lane.head.displayName)}订单，返还军费 ${lane.head.goldCost}" title="尚未开工：全额返还军费 ${lane.head.goldCost}，并释放 ${lane.head.populationCost} 预留人口">撤销</button>`
        : '';
      const tail = lane.tail.length > 0
        ? `<span class="warlord-lane-tail" aria-label="后续 ${escapeHtml(tailNames)}">${lane.tail.map((order) => order.cancellable
          ? `<button class="warlord-tail-order" data-action="cancel-production" data-node="${escapeHtml(lane.nodeId)}" data-slot="${escapeHtml(lane.slotId)}" data-order="${escapeHtml(order.orderId)}" data-cancellable="true" aria-label="撤销后续${escapeHtml(order.displayName)}订单，返还军费 ${order.goldCost}" title="待开工，可全额撤销"><span class="warlord-tail-order-portrait" data-warlord-portrait="${escapeHtml(order.portraitRef)}"><img alt=""></span><span>${escapeHtml(order.displayName)}</span><i aria-hidden="true">×</i></button>`
          : `<span class="warlord-tail-order is-locked" title="${escapeHtml(order.cancelReason ?? '订单已锁定')}"><span class="warlord-tail-order-portrait" data-warlord-portrait="${escapeHtml(order.portraitRef)}"><img alt=""></span><span>${escapeHtml(order.displayName)}</span><i aria-hidden="true">•</i></span>`).join('')}</span>`
        : `<span class="warlord-lane-tail">${lane.queueLength > 0 ? '队首执行中 · 无后续订单' : '队列为空'}</span>`;
      return `<div class="warlord-production-lane state-${lane.state}${recommended ? ' is-recommended' : ''}${exactSelected ? ' is-exact' : ''}${lane.head?.cancellable ? ' has-cancellable-head' : ''}" data-state="${lane.state}" data-queue-length="${lane.queueLength}" data-recommended="${recommended}" role="listitem">
        <button class="warlord-production-lane-select" data-action="choose-production-slot" data-node="${escapeHtml(lane.nodeId)}" data-slot="${escapeHtml(lane.slotId)}" data-state="${lane.state}" aria-pressed="${exactSelected}" aria-label="切换为精确槽位：${escapeHtml(inspected.displayName)} ${lane.slotNumber}号槽" title="点击后切换为精确槽位：${escapeHtml(inspected.displayName)} ${lane.slotNumber}号槽">
          <span class="warlord-lane-index"><b>${String(lane.slotNumber).padStart(2, '0')}</b><i>${recommended ? '系统推荐' : exactSelected ? '当前指定' : lane.stateLabel}</i></span>
          ${head}
          <span class="warlord-lane-progress" aria-label="${progress}%"><i style="width:${progress}%"></i></span>
        </button>
        ${headCancel}
        ${tail}
      </div>`;
    }).join('');
    const recommendationNode = recommendation
      ? nodes.find((node) => node.nodeId === recommendation.nodeId)
      : null;
    const recommendationLane = recommendationNode?.lanes.find((lane) => lane.slotId === recommendation?.slotId);
    const modeCopy = modeIsAuto
      ? recommendation && recommendationNode && recommendationLane
        ? `下次排产 → ${recommendationNode.displayName} ${recommendationLane.slotNumber}号槽 · ${recommendation.reason}`
        : '没有稳定、激活的生产槽可供自动调度。'
      : `下次排产固定进入 ${inspected.displayName} ${this.selectedSlotId.split(':').at(-1) ?? '?'}号槽。`;
    const canInspectRecommendation = modeIsAuto && recommendation
      && (recommendation.nodeId !== inspected.nodeId || recommendation.slotId !== this.selectedSlotId);
    const modeAction = latestCancellable
      ? `<button class="warlord-production-undo" data-action="cancel-production" data-node="${escapeHtml(latestCancellable.nodeId)}" data-slot="${escapeHtml(latestCancellable.slotId)}" data-order="${escapeHtml(latestCancellable.orderId)}" data-cancellable="true" title="撤销${escapeHtml(latestCancellable.displayName)}，全额返还军费 ${latestCancellable.goldCost}">撤销上一单</button>`
      : canInspectRecommendation ? '<button data-action="inspect-auto-slot">查看推荐槽位</button>' : '';
    const visibleOrderCount = networkOrders.length > MAX_NETWORK_ORDER_TILES
      ? MAX_NETWORK_ORDER_TILES - 1
      : MAX_NETWORK_ORDER_TILES;
    const visibleOrders = networkOrders.slice(0, visibleOrderCount);
    const overflowCount = Math.max(0, networkOrders.length - visibleOrders.length);
    const networkTiles = visibleOrders.map((order) => {
      const focused = order.nodeId === inspected.nodeId && order.slotId === this.selectedSlotId;
      const status = order.cancellable
        ? '可撤销'
        : order.laneState === 'waiting_deployment' ? '部署受阻' : order.cancelReason ?? '已锁定';
      const queueCopy = order.queuePosition === 0 ? order.phaseLabel : `队列第 ${order.queuePosition + 1} 位`;
      const tileClass = order.cancellable
        ? 'is-cancellable'
        : order.laneState === 'waiting_deployment' ? 'is-blocked' : 'is-locked';
      return `<button class="warlord-production-network-order ${tileClass}${focused ? ' is-focused' : ''}" data-action="inspect-production-order" data-node="${escapeHtml(order.nodeId)}" data-slot="${escapeHtml(order.slotId)}" data-order="${escapeHtml(order.orderId)}" data-progress="${order.progressPercent}" data-queue-position="${order.queuePosition}" role="listitem" aria-pressed="${focused}" aria-label="定位${escapeHtml(order.nodeDisplayName)} ${order.slotNumber}号槽，${escapeHtml(order.displayName)}，${escapeHtml(queueCopy)}，${escapeHtml(status)}" title="${escapeHtml(order.displayName)} · ${escapeHtml(order.nodeDisplayName)} ${order.slotNumber}号槽 · ${escapeHtml(queueCopy)} · ${escapeHtml(status)}">
        <span class="warlord-production-network-portrait" data-warlord-portrait="${escapeHtml(order.portraitRef)}"><img alt=""></span>
        <span class="warlord-production-network-copy"><b>${escapeHtml(compactProductionNodeName(order.nodeDisplayName))}·${order.slotNumber}</b><small>${order.queuePosition === 0 ? `${order.progressPercent}%` : `第 ${order.queuePosition + 1} 位`}</small></span>
        <i class="warlord-production-network-progress" aria-hidden="true"><em style="width:${order.progressPercent}%"></em></i>
        <mark aria-hidden="true">${order.cancellable ? '↶' : order.laneState === 'waiting_deployment' ? '!' : order.queuePosition > 0 ? order.queuePosition + 1 : ''}</mark>
      </button>`;
    }).join('');
    const network = `<div class="warlord-production-network" data-total-orders="${orderCount}" data-visible-orders="${visibleOrders.length}" data-overflow-orders="${overflowCount}">
      <span class="warlord-production-network-heading"><b>全网在制</b><small>${orderCount > 0 ? '点图标定位' : '暂无订单'}</small></span>
      <span class="warlord-production-network-orders" role="list" aria-label="全网在制订单头像">${networkTiles || '<i class="warlord-production-network-empty">所有生产槽均空闲</i>'}${overflowCount > 0 ? `<i class="warlord-production-network-overflow" title="其余 ${overflowCount} 单可从生产据点下拉框检查">+${overflowCount}</i>` : ''}</span>
    </div>`;
    return `<section class="warlord-production-console${planning ? ' is-planning' : ' is-monitoring'}" data-mode="${this.productionControlMode}" data-production-node="${escapeHtml(inspected.nodeId)}" data-recommended-node="${escapeHtml(recommendation?.nodeId ?? '')}" data-recommended-slot="${escapeHtml(recommendation?.slotId ?? '')}" data-order-count="${orderCount}">
      <div class="warlord-production-toolbar">
        <label><span>${modeIsAuto ? '查看生产据点' : '指定生产据点'}</span><select data-field="production-node" aria-label="生产据点">${nodeOptions}</select></label>
        <button data-action="toggle-production-mode" class="mode-${this.productionControlMode}" aria-pressed="${!modeIsAuto}" title="${modeIsAuto ? '切换为指定据点与槽位' : '切换为系统自动调度'}"><b>${modeIsAuto ? '自动' : '指定'}</b><span>${modeIsAuto ? '系统调度' : '指定槽位'}</span></button>
      </div>
      ${network}
      <div class="warlord-production-mode-note"><span>${escapeHtml(modeCopy)}</span>${modeAction}</div>
      <div class="warlord-production-lanes" role="list" aria-label="生产槽队列">${lanes || '<p>生产槽将在据点激活后建立。</p>'}</div>
    </section>`;
  }

  private renderActions(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="actions"]');
    if (!region) return;
    const commandPreviews = this.commandPreviews();
    const previews = commandPreviews.length > 0
      ? commandPreviews
      : buildActionPreviews(this.game, this.selectedNodeId, []);
    const planning = this.game.phase === 'SETTLEMENT_PLANNING';
    const events = this.game.eventLog.slice(-(planning ? 5 : 4)).reverse();
    const eventFeed = `<section class="warlord-event-feed"><h3>战况记录</h3>${events.map((entry) => `<p><time>${escapeHtml(formatStrategicRound(entry.strategicRound))}</time>${escapeHtml(playerEventMessage(entry, this.game))}</p>`).join('')}</section>`;
    const endValidation = validateCommand(this.game, { type: 'END_ACTION', factionId: this.playerId });
    const canEnd = endValidation.ok && !this.playback;
    const endReason = this.playback
      ? '战斗播放结束后才能结束行动。 请先完成或跳过战斗播放。'
      : endValidation.ok ? null : playerReasonSummary(endValidation.reasonCode, endValidation.reasonParams);
    region.dataset.mode = planning ? 'production' : 'action';
    if (planning) {
      const orders = projectProductionNodes(this.game, this.playerId).reduce((total, node) => total + node.orderCount, 0);
      region.innerHTML = `<header><span>生产调度</span><b>${this.productionControlMode === 'auto' ? '全网自动' : '精确控制'} · ${orders}单</b></header>
        <div class="warlord-action-scroll" data-region="action-scroll" role="region" aria-label="生产调度与战况" tabindex="0">
          ${this.renderProductionConsole(true)}
          ${eventFeed}
        </div>`;
      return;
    }
    const selectedElementCount = this.commandElementsForSelection().length;
    region.innerHTML = `<header><span>命令预览 · 点击即执行</span><b>已选 ${selectedElementCount} 支部队</b></header>
      <div class="warlord-action-scroll" data-region="action-scroll" role="region" aria-label="可选节点、生产监控与战况" tabindex="0">
        <div class="warlord-route-actions">${previews.map((preview) => {
          const partial = preview.ok && preview.actualCommandElementCount < selectedElementCount;
          const reason = !preview.ok
            ? playerTextForReason(preview.reasonCode ?? undefined, preview.reasonParams)
            : null;
          const blockedText = this.playback
            ? '战斗播放期间不能下达战略命令。 请先完成或跳过战斗播放。'
            : reason?.assistiveText ?? '';
          const blocked = !preview.ok || !!this.playback;
          const target = requireNode(this.game, preview.targetNodeId);
          const deploymentCopy = preview.isBattle
            ? `规模 ${preview.deploymentSize} / 最多 ${target.attackWidth}`
            : `规模 ${preview.deploymentSize}`;
          const metricCopy = `需要 ${preview.commandLoad} 行动点 · ${deploymentCopy} · 战斗负载 ${preview.encounterCost}`;
          const encounterText = playerEncounterDistanceText(preview.distanceBand);
          const title = `${blocked ? blockedText : metricCopy} ${encounterText.assistiveText}`.trim();
          return `<button class="${preview.isBattle ? 'is-attack' : 'is-move'}${partial ? ' is-partial' : ''}" data-action="move" data-node="${preview.targetNodeId}" data-command-load="${preview.commandLoad}" data-deployment-size="${preview.deploymentSize}" data-encounter-cost="${preview.encounterCost}" data-command-elements="${preview.actualCommandElementCount}" data-encounter-profile-ref="${preview.encounterProfileRef}" data-distance-band="${preview.distanceBand}" data-spawn-distance="${preview.spawnDistance}"${ariaDisabled(blocked)} data-reason-code="${preview.reasonCode ?? ''}" data-reason-text="${escapeHtml(blockedText)}" title="${escapeHtml(title)}"><b>${preview.isBattle ? '进攻' : '机动'} · ${escapeHtml(preview.targetName)}</b><span>${preview.ok ? `${escapeHtml(metricCopy)} · ${partial ? '仅 ' : ''}${preview.actualCommandElementCount}/${selectedElementCount} 支部队生效` : `${escapeHtml(metricCopy)} · ${escapeHtml(reason?.assistiveText)}`}</span><span data-encounter-distance="${preview.distanceBand}">${escapeHtml(encounterText.assistiveText)}</span></button>`;
        }).join('')}</div>
        ${this.renderProductionConsole(false)}
        ${eventFeed}
      </div>
      <div class="warlord-action-footer"><button class="warlord-end-action" data-action="end-action"${ariaDisabled(!canEnd)} data-reason-code="${endValidation.reasonCode ?? ''}" data-reason-text="${escapeHtml(endReason ?? '')}" title="${escapeHtml(endReason ?? '结束我方行动')}">结束我方行动</button></div>`;
  }

  private renderCommandIntent(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="command-intent"]');
    if (!region) return;
    const origin = this.selectionOrigin();
    if (!origin || this.selectedPieceIds.length === 0) {
      region.hidden = true;
      region.innerHTML = '';
      region.dataset.legalTargets = '0';
      region.dataset.commandElementCount = '0';
      region.dataset.commandLoad = '0';
      region.dataset.deploymentSize = '0';
      region.dataset.encounterCost = '0';
      return;
    }
    const previews = this.commandPreviews();
    const selectedElements = this.commandElementsForSelection();
    const legalCount = previews.filter((preview) => preview.ok).length;
    const partialCount = previews.filter((preview) => preview.ok
      && preview.actualCommandElementCount < selectedElements.length).length;
    const metrics = selectionOrganizationMetrics(this.game, this.selectedPieceIds);
    region.hidden = false;
    region.dataset.legalTargets = String(legalCount);
    region.dataset.partialTargets = String(partialCount);
    region.dataset.armedTarget = this.armedTargetNodeId ?? '';
    region.dataset.commandElementCount = String(selectedElements.length);
    region.dataset.commandLoad = String(metrics.commandLoad);
    region.dataset.deploymentSize = String(metrics.deploymentSize);
    region.dataset.encounterCost = String(metrics.encounterCost);
    region.classList.toggle('is-armed', this.armedTargetNodeId !== null);
    region.classList.toggle('is-coach', this.armedTargetNodeId === null
      && !this.coachDone && !this.coachCommandIssued);
    if (this.armedTargetNodeId !== null) {
      const armedName = this.game.map.nodes[this.armedTargetNodeId]?.displayName ?? this.armedTargetNodeId;
      region.innerHTML = `<b>确认进攻</b><span>再次点击 ${escapeHtml(armedName)} 执行不可撤销进攻</span><small>3 秒内有效 · 退出键或点击他处解除</small>`;
      return;
    }
    region.innerHTML = `<b>已选 ${selectedElements.length} 支</b><span>${escapeHtml(requireNode(this.game, origin).displayName)} · 行动消耗 ${metrics.commandLoad} · 规模 ${metrics.deploymentSize} · 战斗负载 ${metrics.encounterCost}</span><small>${legalCount} 个合法目标${partialCount > 0 ? ` · ${partialCount} 个容量受限` : ''} · 退出键取消</small>`;
  }

  private renderCards(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="cards"]');
    if (!region) return;
    const planningPhase = this.game.phase === 'SETTLEMENT_PLANNING';
    const playerFaction = this.playerFaction();
    region.dataset.collapsed = String(this.rosterCollapsed);
    region.setAttribute('aria-label', this.rosterCollapsed ? '兵种蓝图与生产（已收起）' : '兵种蓝图与生产');
    region.innerHTML = `<div class="warlord-roster-label"><button class="warlord-roster-toggle" data-action="toggle-roster" aria-controls="warlord-roster-cards" aria-expanded="${!this.rosterCollapsed}" aria-label="${this.rosterCollapsed ? '展开兵种蓝图与生产操作' : '收起兵种蓝图，让沙盘获得更多空间'}"><b>兵种蓝图</b><span aria-hidden="true">${this.rosterCollapsed ? '展开兵牌' : '收起兵牌'}</span></button><span>结算升级 / 排产</span>${planningPhase ? '' : '<small class="warlord-roster-hint">统一结算阶段开放排产 / 升阶</small>'}</div><div id="warlord-roster-cards" class="warlord-card-track"${this.rosterCollapsed ? ' hidden' : ''}>${PRODUCTION_CARD_IDS.map((cardId) => {
      const definition = getCardDefinition(cardId);
      const card = playerFaction.cards[cardId];
      const promotion = nextPromotionFor(this.game, this.playerId, cardId);
      const promotionRule = promotion ? PROMOTIONS[promotion] : null;
      const production = resolveProductionChoice(
        this.game,
        this.playerId,
        cardId,
        this.productionControlMode,
        this.productionNodeId,
        this.selectedSlotId,
      );
      const xpAmount = Math.min(1000, playerFaction.xpPool);
      const xpValidation = validateCommand(this.game, {
        type: 'ALLOCATE_XP', factionId: this.playerId, cardId, amount: xpAmount,
      });
      const xpBlocked = !xpValidation.ok || card.level >= 50;
      const xpReason = card.level >= 50
        ? '这个兵种已经达到最高等级。 可以继续升阶或安排生产。'
        : xpValidation.ok ? '' : playerReasonSummary(xpValidation.reasonCode, xpValidation.reasonParams);
      const promotionValidation = promotion ? validateCommand(this.game, {
        type: 'PURCHASE_PROMOTION', factionId: this.playerId, cardId, promotionId: promotion,
      }) : null;
      const promotionReason = promotionValidation?.ok
        ? ''
        : playerReasonSummary(promotionValidation?.reasonCode ?? 'promotion_complete', promotionValidation?.reasonParams);
      const productionReason = production.ok
        ? ''
        : playerReasonSummary(production.reasonCode ?? undefined, production.reasonParams);
      const productionTitle = production.ok
        ? `${production.mode === 'auto' ? '系统调度' : '指定槽位'}至${production.nodeName} ${production.slotNumber}号槽；${production.reason}；${formatMilitaryFunds(definition.productionCost)}；需要 ${definition.buildRounds} 回合；占用 ${definition.populationCost} 人口`
        : productionReason;
      return `<article class="warlord-card tier-${definition.powerTier.slice(1, 2)}" data-testid="card-${cardId}">
        <span class="warlord-card-portrait" data-warlord-portrait="${escapeHtml(definition.identifier)}"><img alt=""><i>${escapeHtml(playerBehaviorName(definition.behaviorId))}</i></span>
        <span class="warlord-card-copy"><b title="${escapeHtml(definition.displayName)}">${escapeHtml(definition.displayName)}</b><small class="warlord-card-stats"><strong>${card.level}级</strong><em>${escapeHtml(playerPowerTierName(definition.powerTier))}</em><em>军费${definition.productionCost}</em></small><small>经验 ${card.level >= 50 ? '已满级' : `${card.xpIntoLevel}/${needXp(cardId, card.level)}`}</small></span>
        <span class="warlord-card-actions"><button data-action="allocate-xp" data-card="${cardId}"${ariaDisabled(xpBlocked)} data-reason-code="${xpValidation.reasonCode ?? ''}" data-reason-text="${escapeHtml(xpReason)}" title="${escapeHtml(xpReason || '分配战后经验')}">分配经验</button><button data-action="promotion" data-card="${cardId}" data-promotion="${escapeHtml(promotion ?? '')}"${ariaDisabled(!promotionValidation?.ok)} data-reason-code="${promotionValidation?.reasonCode ?? (promotion ? '' : 'promotion_complete')}" data-reason-text="${escapeHtml(promotionReason)}" title="${escapeHtml(promotionValidation?.ok && promotionRule ? `需要等级 ${promotionRule.level}，消耗军费 ${promotionRule.cost}` : promotionReason)}">升阶</button><button class="warlord-card-production" data-action="production" data-card="${cardId}"${ariaDisabled(!production.ok)} data-reason-code="${production.reasonCode ?? ''}" data-reason-text="${escapeHtml(productionReason)}" title="${escapeHtml(productionTitle)}">排产</button></span>
      </article>`;
    }).join('')}</div>`;
  }

  private renderPlanning(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="planning"]');
    if (!region) return;
    if (this.game.phase === 'SETTLEMENT_PLANNING') {
      const commitValidation = validateCommand(this.game, { type: 'COMMIT_PLANNING', factionId: this.playerId });
      const commitReason = commitValidation.ok
        ? '' : playerReasonSummary(commitValidation.reasonCode, commitValidation.reasonParams);
      const playerCommander = Object.values(this.game.commanders).find((commander) => (
        commander.factionId === this.playerId && commander.role === 'player_avatar'
      ));
      const redeployCommand = playerCommander ? {
        type: 'REDEPLOY_PLAYER_AVATAR' as const,
        factionId: this.playerId,
        commanderId: playerCommander.commanderId,
        nodeId: this.playerFaction().commandPostNodeId,
      } : null;
      const redeployValidation = redeployCommand ? validateCommand(this.game, redeployCommand) : null;
      const redeployReason = redeployValidation?.ok
        ? '' : playerReasonSummary(redeployValidation?.reasonCode, redeployValidation?.reasonParams);
      const redeploy = playerCommander?.status === 'rear'
        ? `<button data-action="redeploy-player-commander" data-commander="${escapeHtml(playerCommander.commanderId)}"${ariaDisabled(redeployValidation?.ok !== true)} data-reason-code="${redeployValidation?.reasonCode ?? ''}" data-reason-text="${escapeHtml(redeployReason)}" title="${escapeHtml(redeployValidation?.ok ? '从我方安全指挥所重新出动' : redeployReason)}">主角重新出动</button>`
        : '';
      region.innerHTML = `<div><b>统一结算安排</b><span>恢复、占领与收入已完成；分配经验、升阶并排产。</span></div><span class="warlord-planning-actions">${redeploy}<button data-action="commit-planning"${ariaDisabled(!commitValidation.ok)} data-reason-code="${commitValidation.reasonCode ?? ''}" data-reason-text="${escapeHtml(commitReason)}" title="${escapeHtml(commitReason || '提交我方结算安排')}">${this.playerFaction().planningCommitted ? '我方已提交' : '提交我方安排'}</button></span>`;
      region.hidden = false;
      return;
    }
    if (this.game.phase === 'GAME_OVER' && this.game.result) {
      const winner = this.game.result.winner === 'draw' ? '平局' : `${factionLabel(this.game.result.winner, this.game)}胜利`;
      const resultReason = this.game.result.reason === 'elimination'
        ? '所有敌对胜利组均已退出战局'
        : this.game.result.reason === 'command_post_captured'
          ? '玩家指挥所失守，或最后一个敌对胜利组的指挥所被攻破'
          : '24 回合计分结算';
      const action = this.stageAuthority.isStageMode
        ? '<span>关卡结果已形成，正在返回外层关卡。</span>'
        : '<button data-action="restart">同配置重开</button>';
      region.innerHTML = `<div><b>${winner}</b><span>${resultReason}</span></div>${action}`;
      region.hidden = false;
      return;
    }
    region.hidden = true;
    region.innerHTML = '';
  }

  private renderBattle(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="battle"]');
    if (!region) return;
    const record = this.playbackRecord;
    if (!record || !this.playback) {
      region.innerHTML = '';
      region.hidden = true;
      return;
    }
    const playback = this.playback;
    const event = playback.index > 0 ? record.result.eventLog[Math.min(playback.index - 1, record.result.eventLog.length - 1)] : null;
    const visual = projectBattleVisual(record, playback.index);
    const finished = playback.index >= record.result.eventLog.length;
    const formations = (['attacker', 'defender'] as const).map((side) => {
      const ids = side === 'attacker' ? record.attackerPieceIds : record.defenderPieceIds;
      return `<section><h3>${side === 'attacker' ? '进攻编队' : '防守编队'}</h3>${ids.map((pieceId) => {
        const unit = visual.get(pieceId);
        if (!unit) return '';
        const presentation = projectBattleUnitPresentation(unit.snapshot);
        const portrait = presentation.portraitKind === 'player_avatar'
          ? this.init.playerAvatarPortrait !== null
            ? '<span class="warlord-battle-portrait warlord-player-avatar-portrait" data-warlord-player-avatar><img alt=""></span>'
            : '<span class="warlord-battle-portrait warlord-player-avatar-unavailable"><img alt=""></span>'
          : `<span class="warlord-battle-portrait" data-warlord-portrait="${escapeHtml(presentation.portraitIdentifier ?? '')}"><img alt=""></span>`;
        return `<article class="${unit.snapshot.factionId}${unit.dead ? ' dead' : ''}${event?.actorPieceId === pieceId ? ' acting' : ''}${event?.targetPieceId === pieceId ? ' targeted' : ''}">${portrait}<span><b>${escapeHtml(presentation.displayName)}</b><small>${escapeHtml(factionLabel(unit.snapshot.factionId, this.game))} · ${escapeHtml(presentation.roleLabel)}</small><i${hpBarClass(unit.hp, unit.snapshot.maxHp)}><em style="width:${hpPercent(unit.hp, unit.snapshot.maxHp)}%"></em></i><small>生命 ${unit.hp}/${unit.snapshot.maxHp} · ${escapeHtml(unit.lastStatus)}</small></span></article>`;
      }).join('')}</section>`;
    }).join('');
    region.hidden = false;
    region.innerHTML = `<div class="warlord-battle-dialog" role="dialog" aria-modal="true" aria-label="战斗播放">
      <header><span><b>${escapeHtml(this.game.map.nodes[record.nodeId as NodeId]?.displayName ?? '目标据点')}</b><small>${escapeHtml(formatStrategicRound(record.strategicRound))}的战斗</small></span><strong>${playback.index}/${record.result.eventLog.length}</strong></header>
      <div class="warlord-battle-formations">${formations}</div>
      <div class="warlord-battle-event"><b>${event ? `第 ${event.battleRound} 轮 · ${escapeHtml(battleEventLabel(event))}` : '战斗即将开始'}</b><p>${event ? escapeHtml(playerBattleEventMessage(record, event)) : '可以暂停、加速或立即查看结算结果。'}</p></div>
      <div class="warlord-battle-controls"><button data-action="battle-pause">${playback.paused ? '继续' : '暂停'}</button><button data-action="battle-speed">${playback.speed}×</button><button data-action="battle-skip">立即结算</button><button data-action="battle-log">${playback.showLog ? '收起日志' : '逐回合日志'}</button><button data-action="battle-close"${disabled(!finished)}>返回沙盘</button></div>
      ${playback.showLog ? `<div class="warlord-battle-log">${record.result.eventLog.map((entry) => `<p><span>第 ${entry.battleRound} 轮</span>${escapeHtml(playerBattleEventMessage(record, entry))}</p>`).join('')}</div>` : ''}
    </div>`;
  }

  private renderConfig(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="config"]');
    if (!region) return;
    if (!this.configOpen) {
      region.hidden = true;
      region.innerHTML = '';
      return;
    }
    region.hidden = false;
    region.innerHTML = `<div class="warlord-config-dialog" role="dialog" aria-modal="true" aria-label="开发设置"><header><b>开发设置</b><button data-action="close-config" aria-label="关闭开发设置">×</button></header><label>测试种子<input data-field="seed" value="${escapeHtml(this.seedDraft)}"></label><label>开局预设<select data-field="preset"><option value="standard"${selected(this.presetDraft === 'standard')}>标准开局</option><option value="all-units"${selected(this.presetDraft === 'all-units')}>全兵种演习</option></select></label><label>地图外观<select data-field="map-theme"><option value="desert"${selected(this.themeDraft === 'desert')}>沙漠沙盘</option><option value="tundra"${selected(this.themeDraft === 'tundra')}>冻原预览</option></select></label><label>电脑难度<select data-field="difficulty">${DIFFICULTIES.map(([value, label]) => `<option value="${value}"${selected(this.difficultyDraft === value)}>${label}</option>`).join('')}</select></label><p>本页只用于开发测试。正式游玩会使用关卡已经确定的设置。</p><button data-action="new-game">按设置重新开始</button></div>`;
  }

  private openHelp(anchor: HelpAnchor, trigger?: HTMLElement | null): void {
    this.clearAutomation();
    if (!this.helpState.open) {
      this.helpReturnFocus = trigger
        ?? (document.activeElement instanceof HTMLElement ? document.activeElement : null);
    }
    const wasOpen = this.helpState.open;
    this.helpState = openHelpUi(this.helpState, anchor);
    this.helpFocusTarget = wasOpen ? 'section' : 'close';
    this.renderHelp();
  }

  private closeHelp(): void {
    if (!this.helpState.open) return;
    this.helpState = closeHelpUi(this.helpState);
    this.helpFocusTarget = null;
    this.renderHelp();
    const returnFocus = this.helpReturnFocus;
    this.helpReturnFocus = null;
    this.scheduleAutomation();
    queueMicrotask(() => {
      if (!this.disposed && returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
    });
  }

  private renderHelp(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="help"]');
    if (!region) return;
    if (!this.helpState.open) {
      region.hidden = true;
      region.innerHTML = '';
      return;
    }
    const helpProfile = helpProfileForScenario(this.game.scenarioId);
    const active = helpProfile.sections.find((section) => section.anchor === this.helpState.anchor)
      ?? helpProfile.sections[0];
    if (!active) return;
    const quickGoal = this.game.scenarioId === 'warlord_demo_02_v1'
      ? '<span><b>目标</b><small>守住我方指挥所，消灭另外两个敌对胜利组</small></span><span><b>失败</b><small>我方指挥所被合法攻占</small></span>'
      : '<span><b>目标</b><small>让敌方失去部队和稳定生产能力</small></span><span><b>失败</b><small>我方失去部队和稳定生产能力</small></span>';
    region.hidden = false;
    region.innerHTML = `<div class="warlord-help-dialog" role="dialog" aria-modal="true" aria-labelledby="warlord-help-title" data-help-anchor="${active.anchor}">
      <header><span><b id="warlord-help-title">玩法帮助</b><small>关闭后会回到原来的沙盘状态</small></span><button data-action="close-help" aria-label="关闭玩法帮助">×</button></header>
      <div class="warlord-help-quick" aria-label="当前关卡要点">
        ${quickGoal}
        <span><b>回合</b><small>选择部队、下令、结束行动</small></span>
        <span><b>拒绝原因</b><small>按界面提示修改后重试</small></span>
      </div>
      <div class="warlord-help-body">
        <nav aria-label="玩法帮助目录">${helpProfile.sections.map((section) => `<button data-action="help-anchor" data-help-anchor="${section.anchor}" aria-current="${section.anchor === active.anchor ? 'page' : 'false'}">${escapeHtml(section.title)}</button>`).join('')}</nav>
        <article tabindex="-1" data-help-current data-help-section="${active.anchor}"><h2>${escapeHtml(active.title)}</h2><p>${escapeHtml(active.summary)}</p><ul>${active.details.map((detail) => `<li>${escapeHtml(detail)}</li>`).join('')}</ul>${active.anchor === 'turn' || active.anchor === 'overview' ? '<button data-action="restart-coach">重新打开操作引导</button>' : ''}</article>
      </div>
    </div>`;
    const focusTarget = this.helpFocusTarget;
    this.helpFocusTarget = null;
    if (focusTarget) {
      queueMicrotask(() => {
        if (this.disposed || !this.helpState.open) return;
        const target = focusTarget === 'close'
          ? region.querySelector<HTMLElement>('[data-action="close-help"]')
          : region.querySelector<HTMLElement>('[data-help-current]');
        target?.focus({ preventScroll: true });
      });
    }
  }

  private trapHelpFocus(event: KeyboardEvent): boolean {
    if (!this.helpState.open || event.key !== 'Tab') return false;
    const dialog = this.root.querySelector<HTMLElement>('.warlord-help-dialog');
    if (!dialog) return false;
    const focusable = Array.from(dialog.querySelectorAll<HTMLElement>('button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])'))
      .filter((element) => element.offsetParent !== null);
    if (focusable.length === 0) return false;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (!first || !last) return false;
    if (!(document.activeElement instanceof HTMLElement) || !focusable.includes(document.activeElement)) {
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
      return true;
    }
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
      return true;
    }
    if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
      return true;
    }
    return false;
  }

  private renderFallback(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="fallback"]');
    const scene = this.root.querySelector<HTMLElement>('[data-region="scene"]');
    if (!region || !scene) return;
    if (!this.sceneError) {
      region.hidden = true;
      scene.hidden = false;
      return;
    }
    scene.hidden = true;
    region.hidden = false;
    const previewById = new Map(this.commandPreviews().map((preview) => [preview.targetNodeId, preview]));
    region.innerHTML = `<div class="warlord-fallback-notice"><b>立体沙盘暂不可用</b><span>已切换到简化地图，当前战局和全部规则保持不变。</span><small>可继续选择部队、查看据点并下达命令。</small></div><div class="warlord-fallback-grid">${projectNodes(this.game).map((node) => {
      const preview = previewById.get(node.nodeId);
      const commandState = preview?.ok ? preview.isBattle ? 'attack' : 'move' : preview ? 'invalid' : 'none';
      const reason = preview && !preview.ok
        ? playerTextForReason(preview.reasonCode ?? undefined, preview.reasonParams)
        : null;
      return `<button data-action="select-node" data-node="${node.nodeId}" data-command-state="${commandState}" class="owner-${node.ownerFactionId ?? 'neutral'}${node.nodeId === this.selectedNodeId ? ' selected' : ''}${preview ? ` command-${commandState}` : ''}"${reason ? `${ariaDisabled(true)} data-reason-code="${preview?.reasonCode ?? ''}" data-reason-text="${escapeHtml(reason.assistiveText)}"` : ''} title="${escapeHtml(reason?.assistiveText ?? `${node.ownerLabel}，我方 ${node.redCount}，敌方 ${node.blueCount}`)}"><b>${escapeHtml(node.displayName)}</b><span>${preview?.ok ? `${preview.isBattle ? '进攻' : '机动'} ${preview.actualPieceIds.length}/${this.selectedPieceIds.length}` : reason?.assistiveText ?? `${node.ownerLabel} · 我方 ${node.redCount} / 敌方 ${node.blueCount}`}</span></button>`;
    }).join('')}</div>`;
  }

  private renderCameraHud(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="camera"]');
    if (!region) return;
    const detailLabel = this.cameraSnapshot.detailTier === 'overview'
      ? '战区总览'
      : this.cameraSnapshot.detailTier === 'tactical' ? '战术近距' : '作战视图';
    const cameraLocked = this.scene?.isActionCameraInputLocked() === true;
    const unavailable = !this.scene || cameraLocked;
    if (!region.querySelector('[data-camera-detail]')) {
      region.innerHTML = `<div class="warlord-camera-readout"><span data-camera-detail></span><b data-camera-zoom></b><small data-camera-position></small></div>
      <div class="warlord-camera-controls">
        <button data-action="camera-zoom-out" data-camera-role="detail" aria-label="缩小沙盘" title="缩小（-）">−</button>
        <button data-action="camera-fit" data-camera-role="primary" aria-label="全图适配" title="全图适配（0）">全图</button>
        <button data-action="camera-focus" data-camera-role="primary" aria-label="定位当前据点" title="定位当前据点">定位</button>
        <button data-action="camera-zoom-in" data-camera-role="detail" aria-label="放大沙盘" title="放大（+）">＋</button>
      </div>`;
    }
    const detail = region.querySelector<HTMLElement>('[data-camera-detail]');
    const zoom = region.querySelector<HTMLElement>('[data-camera-zoom]');
    const position = region.querySelector<HTMLElement>('[data-camera-position]');
    if (detail) detail.textContent = detailLabel;
    if (zoom) zoom.textContent = `${this.cameraSnapshot.zoomPercent}%`;
    if (position) position.textContent = `横向偏移 ${this.cameraSnapshot.centerX.toFixed(1)} · 纵向偏移 ${this.cameraSnapshot.centerZ.toFixed(1)} · ${this.cameraSnapshot.nodeCount || Object.keys(this.game.map.nodes).length} 个据点`;
    for (const button of region.querySelectorAll<HTMLButtonElement>('button')) button.disabled = unavailable;
    region.dataset.zoom = String(this.cameraSnapshot.zoomPercent);
    region.dataset.atFit = this.cameraSnapshot.atFit ? 'true' : 'false';
    region.dataset.detail = this.cameraSnapshot.detailTier;
    region.dataset.expanded = this.cameraHudExpanded ? 'true' : 'false';
    region.dataset.idleDelay = String(CAMERA_HUD_REVEAL_MS);
    region.dataset.inputLocked = cameraLocked ? 'true' : 'false';
    region.setAttribute('aria-disabled', cameraLocked ? 'true' : 'false');
  }

  private renderLiveRegion(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="live"]');
    if (region) region.textContent = this.notice;
    this.renderToast();
  }

  // 可见 toast：与 sr-only live 区域同源，只在 notice 变化（serial 前进）时重置淡出计时
  private renderToast(): void {
    const toast = this.root.querySelector<HTMLElement>('[data-region="toast"]');
    if (!toast) return;
    if (toast.dataset.serial === String(this.toastSerial)) return;
    toast.dataset.serial = String(this.toastSerial);
    this.clearToastTimers();
    toast.textContent = this.notice;
    toast.classList.toggle('is-error', this.noticeTone === 'error');
    toast.classList.remove('is-fading');
    toast.hidden = false;
    this.toastFadeTimer = window.setTimeout(() => {
      this.toastFadeTimer = null;
      if (this.disposed) return;
      toast.classList.add('is-fading');
      this.toastHideTimer = window.setTimeout(() => {
        this.toastHideTimer = null;
        toast.hidden = true;
        toast.classList.remove('is-fading');
      }, TOAST_FADE_MS);
    }, TOAST_VISIBLE_MS);
  }

  private clearToastTimers(): void {
    if (this.toastFadeTimer !== null) window.clearTimeout(this.toastFadeTimer);
    this.toastFadeTimer = null;
    if (this.toastHideTimer !== null) window.clearTimeout(this.toastHideTimer);
    this.toastHideTimer = null;
  }

  // handoff / blocked 的可见横幅：不拦截指针，关闭按钮与相机操作岛保持可点
  private renderAuthorityBanner(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="authority"]');
    if (!region) return;
    if (this.stageAuthority.status === 'blocked') {
      region.hidden = false;
      region.dataset.state = 'stage-blocked';
      region.innerHTML = '<b>关卡身份无效</b><span>无法确认本次关卡归属，沙盘已锁定且不会退回普通演习；请保留页面并联系维护者。</span>';
      return;
    }
    if (this.stageAuthority.status === 'terminal_failed') {
      region.hidden = false;
      region.dataset.state = 'stage-terminal-failed';
      region.innerHTML = '<b>关卡结果尚未送达</b><span>页面会保持打开，不会直接返回基地或重复提交。</span>';
      return;
    }
    if (this.stageAuthority.status === 'terminal_sent') {
      region.hidden = false;
      region.dataset.state = 'stage-terminal-sent';
      region.innerHTML = '<b>正在返回关卡</b><span>关卡结果已经提交，请等待外层关卡完成安全切换。</span>';
      return;
    }
    if (this.authorityBlocked) {
      region.hidden = false;
      region.dataset.state = 'blocked';
      region.innerHTML = this.authorityReturnOnly
        ? '<b>本次战斗结果无法确认</b><span>本局不能继续；请点击右上角 × 关闭面板，再从任务提示选择“回基地”。不会重复结算本次进攻。</span>'
        : '<b>当前战局已暂停</b><span>请点击右上角 × 关闭面板，再从任务提示恢复同一战略战局。</span>';
      return;
    }
    if (this.handoffPending) {
      region.hidden = false;
      region.dataset.state = 'handoff';
      region.innerHTML = '<i class="warlord-authority-spinner" aria-hidden="true"></i><b>正在进入战斗场景</b><span>进攻命令已经确认，战略地图会在战斗结束后更新。</span>';
      return;
    }
    region.hidden = true;
    region.innerHTML = '';
    delete region.dataset.state;
  }

  // 首次引导教练点：仅会话内记忆；① 建立编组 ③ 结束行动（② 由意图条脉冲承担）
  private renderCoach(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="coach"]');
    if (!region) return;
    const playerAction = this.game.activeFactionId === this.playerId
      && (this.game.phase === 'FIRST_FACTION_ACTION' || this.game.phase === 'SECOND_FACTION_ACTION');
    let tip: string | null = null;
    if (!this.coachDone && !this.coachSkipped && playerAction && !this.playback && !this.handoffPending
      && !this.authorityBlocked && !this.stageAuthority.blocksGameplay) {
      if (this.coachCommandIssued) tip = '③ 点击“结束我方行动”收束本回合';
      else if (this.selectedPieceIds.length === 0) tip = '① 点击己方棋子建立编组';
    }
    if (!tip) {
      region.hidden = true;
      region.innerHTML = '';
      return;
    }
    region.hidden = false;
    region.innerHTML = `<span>${escapeHtml(tip)}</span><button data-action="skip-coach" aria-label="跳过操作引导">跳过</button>`;
  }

  // 3D 悬停信息芯片：render 重建区域外单例，anchor 为 canvas 本地 CSS 像素
  private renderHoverChip(
    info: { kind: 'node'; nodeId: NodeId } | { kind: 'piece'; pieceId: string } | null,
    anchor: { x: number; y: number },
  ): void {
    const chip = this.root.querySelector<HTMLElement>('[data-region="hover"]');
    if (!chip) return;
    if (!info) {
      chip.hidden = true;
      chip.dataset.hoverKey = '';
      return;
    }
    const key = info.kind === 'node' ? `node:${info.nodeId}` : `piece:${info.pieceId}`;
    if (chip.dataset.hoverKey !== key) {
      chip.dataset.hoverKey = key;
      if (info.kind === 'node') {
        const node = this.game.map.nodes[info.nodeId];
        if (!node) {
          chip.hidden = true;
          return;
        }
        const elements = commandElementsAtNode(this.game, info.nodeId);
        const playerCount = elements.filter((element) => element.factionId === this.playerId).length;
        const otherCount = elements.length - playerCount;
        chip.innerHTML = `<b>${escapeHtml(node.displayName)}</b><span>${escapeHtml(ownerLabel(node.ownerFactionId, this.game))} · 我方 ${playerCount} · 其他 ${otherCount} · 驻军 ${nodeDeploymentSize(this.game, info.nodeId)} / 上限 ${node.capacity}</span>`;
      } else {
        const piece = this.game.pieces[info.pieceId];
        if (!piece) {
          chip.hidden = true;
          return;
        }
        const element = commandElementForMember(this.game, info.pieceId);
        if (element?.kind === 'task_group') {
          const metrics = commandElementMetrics(this.game, element);
          chip.innerHTML = `<b>临时编队 · ${element.memberIds.length} 支</b><span>${factionLabel(piece.factionId, this.game)} · ${escapeHtml(formationProfile(element.formationProfileId).displayName)} · 行动消耗 ${metrics.commandLoad} · 规模 ${metrics.deploymentSize} · 战斗负载 ${metrics.encounterCost}</span>`;
        } else {
          chip.innerHTML = `<b>${escapeHtml(getCardDefinition(piece.cardId).displayName)}</b><span>${factionLabel(piece.factionId, this.game)} · 生命 ${piece.hp}/${piece.maxHp}</span>`;
        }
      }
    }
    chip.hidden = false;
    const stage = this.root.querySelector<HTMLElement>('.warlord-map-stage');
    if (stage) {
      const maxX = Math.max(4, stage.clientWidth - chip.offsetWidth - 8);
      const maxY = Math.max(4, stage.clientHeight - chip.offsetHeight - 56);
      chip.style.left = `${Math.round(Math.max(4, Math.min(anchor.x + 14, maxX)))}px`;
      chip.style.top = `${Math.round(Math.max(4, Math.min(anchor.y + 16, maxY)))}px`;
    }
  }

  public rebind(initData?: WarlordInitData): void {
    if (this.disposed) return;
    const next = normalizeInit(initData);
    const themeChanged = next.mapTheme !== this.mapTheme;
    const sceneModeChanged = next.forceWebglFailure !== this.init.forceWebglFailure;
    this.advanceStageCloseGeneration();
    const stageRebind = this.stageAuthority.rebind({
      ...next,
      stageAutomaticCloseRequest: () => this.scheduleStageExactClose(),
    });
    const changed = next.seed !== this.init.seed || next.preset !== this.init.preset
      || next.difficulty !== this.init.difficulty || sceneModeChanged || themeChanged
      || next.scenarioRef !== this.init.scenarioRef
      || next.battleAuthority !== this.init.battleAuthority || stageRebind.contextChanged;
    this.init = next;
    if ((changed || next.resume) && this.aiCameraLease) {
      this.cancelAiActionCamera(this.aiCameraLease.token);
    }
    if (this.stageAuthority.blocksGameplay) {
      this.clearAutomation();
      this.render();
      return;
    }
    if (next.battleAuthority === 'as2' && next.resume) {
      const frozen = frozenStateFromAs2Resume(next.resume);
      this.aiSeenTransitions = new Set(next.aiSeenTransitions);
      this.handoffPending = true;
      this.authorityBlocked = frozen === null;
      this.authorityReturnOnly = false;
      this.playback = null;
      this.render();
      void this.consumeAs2Resume(next.resume);
      return;
    }
    if (!changed) {
      this.render();
      this.resize();
      return;
    }
    this.seedDraft = next.seed;
    this.presetDraft = next.preset;
    this.difficultyDraft = next.difficulty;
    this.themeDraft = next.mapTheme;
    this.mapTheme = next.mapTheme;
    if (sceneModeChanged || themeChanged) this.restartScene();
    this.startNewGame();
  }

  public resize(): void {
    this.scene?.resize();
  }

  public getState(): GameState {
    return this.game;
  }

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.panelCloseQuiesced = true;
    this.clearStageAutoClose();
    this.stageCloseGeneration.dispose();
    this.stageAuthority.dispose();
    this.clearAutomation();
    if (this.aiCameraLease) this.cancelAiActionCamera(this.aiCameraLease.token);
    this.clearCameraHudTimer();
    this.clearAuthorityAckTimer();
    this.pendingBattleCommand = null;
    this.pendingBattlePrepared = false;
    this.clearToastTimers();
    this.clearAttackArmTimer();
    this.aiReplay = null;
    this.portraitGeneration.dispose();
    this.resources.dispose();
    this.scene?.dispose();
    this.scene = null;
    this.root.removeAttribute('data-ready');
    this.root.removeAttribute('data-phase');
    this.root.removeAttribute('data-selected-node');
    this.root.removeAttribute('data-portraits-ready');
    this.root.innerHTML = '';
  }
}
