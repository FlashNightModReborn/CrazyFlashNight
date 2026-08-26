import { generateNextAiAction, runAiActionPhase, runAiPlanning } from '../ai/heuristic.js';
import type { BattleRecord } from '../battle/types.js';
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
import { needXp } from '../core/math.js';
import { createGame } from '../core/state.js';
import { piecesAtNode } from '../core/selectors.js';
import type {
  CardId,
  Difficulty,
  GameCommand,
  GameState,
  MoveOrAttackCommand,
  NodeId,
  PresetId,
  PromotionId,
} from '../core/types.js';
import { firstProductionSlotId, validateCommand } from '../core/validator.js';
import { CARD_IDS, getCardDefinition } from '../data/cards.js';
import { PROMOTIONS } from '../data/config.js';
import { mountPortraits } from '../assets/portrait-texture-source.js';
import {
  SandtableScene,
  type SandtableCameraSnapshot,
} from '../scene/sandtable-scene.js';
import {
  MAP_THEMES,
  normalizeMapTheme,
  type MapThemeId,
} from '../scene/map-theme.js';
import { DisposableBag, GenerationFence, isEditableKeyboardTarget } from './lifecycle.js';
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
  buildActionPreviews,
  factionLabel,
  nextPromotionFor,
  ownerLabel,
  PHASE_LABEL,
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

export interface WarlordInitData {
  mode?: string;
  source?: string;
  seed?: string;
  preset?: PresetId;
  difficulty?: Difficulty;
  panelInstanceId?: string;
  productionWrites?: boolean;
  forceWebglFailure?: boolean;
  mapTheme?: MapThemeId;
  battleAuthority?: 'fixture' | 'as2';
  bridgeSend?: (message: As2BattleEnvelope) => boolean;
  as2BattleSession?: boolean;
  aiSeenTransitions?: string[];
  resume?: As2ResumeEnvelope | Record<string, unknown> | null;
}

export interface WarlordSessionContract {
  rebind(initData?: WarlordInitData): void;
  requestClose(reason?: string): boolean;
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
  panelInstanceId: string;
  productionWrites: false;
  forceWebglFailure: boolean;
  mapTheme: MapThemeId;
  battleAuthority: 'fixture' | 'as2';
  bridgeSend: ((message: As2BattleEnvelope) => boolean) | null;
  as2BattleSession: boolean;
  aiSeenTransitions: string[];
  resume: WarlordInitData['resume'];
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
  return displayName.replace('红方', 'R·').replace('蓝方', 'B·').replace('中央', '中·');
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
  return {
    mode: typeof input?.mode === 'string' ? input.mode : 'phase-b',
    source,
    seed: typeof input?.seed === 'string' && input.seed.trim() ? input.seed.trim() : 'warlord-demo-seed-001',
    preset: preset === 'all-units' ? preset : 'standard',
    difficulty: difficulty === 'easy' || difficulty === 'hard' || difficulty === 'extreme' ? difficulty : 'normal',
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
  };
}

export class WarlordSession implements WarlordSessionContract {
  private init: NormalizedWarlordInit;
  private game: GameState;
  private selectedNodeId: NodeId;
  private selectedPieceIds: string[] = [];
  private productionNodeId: NodeId;
  private selectedSlotId: string;
  private productionControlMode: ProductionControlMode = 'auto';
  // notice 通过 setter 同步可见 toast 的序号；错误/阻断类用 setNotice(..., 'error') 区分色调
  private noticeText = '点击己方棋子或按住 Shift 框选，再点击高亮据点直接下令。';
  private noticeTone: 'info' | 'error' = 'info';
  private toastSerial = 0;
  private toastFadeTimer: number | null = null;
  private toastHideTimer: number | null = null;
  private armedTargetNodeId: NodeId | null = null;
  private attackArmTimer: number | null = null;
  // fixture 模式 AI 回合重放队列：公开 applyCommand 逐条投影中间态
  private aiReplay: { commands: GameCommand[]; index: number } | null = null;
  // 首次引导（仅会话内记忆，不落盘）：发过一轮命令 / 完成过一轮行动后不再提示
  private coachCommandIssued = false;
  private coachDone = false;
  private playback: BattlePlaybackState | null = null;
  private automationTimer: number | null = null;
  private portraitGeneration = new GenerationFence();
  private resources = new DisposableBag();
  private scene: SandtableScene | null = null;
  private cameraSnapshot = DEFAULT_CAMERA_SNAPSHOT;
  private cameraHudExpanded = false;
  private cameraHudTimer: number | null = null;
  private mapTheme: MapThemeId;
  private themeDraft: MapThemeId;
  private nodeNavigatorMode: NodeNavigatorMode = 'context';
  private nodePageIndex = 0;
  private sceneError: string | null = null;
  private configOpen = false;
  private disposed = false;
  private seedDraft: string;
  private presetDraft: PresetId;
  private difficultyDraft: Difficulty;
  private handoffPending = false;
  private authorityBlocked = false;
  private authoritySessionId: string;
  private pendingBattleCallId: string | null = null;
  private authorityAckTimer: number | null = null;
  private consumedResumeDigest: string | null = null;
  private aiSeenTransitions = new Set<string>();

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

  public constructor(private readonly root: HTMLElement, initData?: WarlordInitData) {
    this.init = normalizeInit(initData);
    this.authoritySessionId = sessionIdFromAs2Resume(this.init.resume)
      ?? createAs2AuthoritySessionId();
    this.aiSeenTransitions = new Set(this.init.aiSeenTransitions);
    this.mapTheme = this.init.mapTheme;
    this.themeDraft = this.mapTheme;
    const resumeState = this.init.battleAuthority === 'as2'
      ? frozenStateFromAs2Resume(this.init.resume) : null;
    this.game = resumeState
      ?? createGame({ seed: this.init.seed, preset: this.init.preset, difficulty: this.init.difficulty });
    this.handoffPending = this.init.battleAuthority === 'as2' && this.init.resume !== null;
    this.authorityBlocked = this.handoffPending && resumeState === null;
    this.selectedNodeId = this.game.preset === 'all-units' ? 'R-Supply' : 'R-HQ';
    this.productionNodeId = recommendProductionLane(this.game, 'red')?.nodeId ?? 'R-HQ';
    this.selectedSlotId = firstProductionSlotId(this.game, 'red', this.productionNodeId) ?? 'R-HQ:1';
    this.seedDraft = this.game.gameSeed;
    this.presetDraft = this.game.preset;
    this.difficultyDraft = this.game.difficulty;
    this.installShell();
    this.root.addEventListener('click', this.onClick);
    this.root.addEventListener('change', this.onChange);
    this.root.addEventListener('input', this.onInput);
    this.root.addEventListener('pointerdown', this.onCameraSurfaceActivity);
    this.root.addEventListener('wheel', this.onCameraSurfaceActivity, { passive: true });
    window.addEventListener('keydown', this.onKeyDown);
    this.resources.add(() => this.root.removeEventListener('click', this.onClick));
    this.resources.add(() => this.root.removeEventListener('change', this.onChange));
    this.resources.add(() => this.root.removeEventListener('input', this.onInput));
    this.resources.add(() => this.root.removeEventListener('pointerdown', this.onCameraSurfaceActivity));
    this.resources.add(() => this.root.removeEventListener('wheel', this.onCameraSurfaceActivity));
    this.resources.add(() => window.removeEventListener('keydown', this.onKeyDown));
    this.startScene();
    this.render();
    if (this.init.battleAuthority === 'as2' && this.init.resume) {
      void this.consumeAs2Resume(this.init.resume);
    }
  }

  private installShell(): void {
    this.root.innerHTML = `<div class="warlord-app" data-testid="warlord-app">
      <header class="warlord-command-bar">
        <div class="warlord-brand"><b>军阀战术演习</b><span data-region="theater">沙漠战区 · 确定性指挥终端</span></div>
        <div class="warlord-round" data-region="round"></div>
        <div class="warlord-factions" data-region="factions"></div>
        <button class="warlord-icon-button" data-action="toggle-config" aria-label="打开演习配置">配置</button>
        <button class="warlord-icon-button warlord-panel-close" data-action="request-close" aria-label="关闭军阀战术演习">×</button>
      </header>
      <main class="warlord-main">
        <aside class="warlord-force-rail" data-region="forces" aria-label="当前节点驻军"></aside>
        <section class="warlord-map-stage" aria-label="三维战术沙盘">
          <div class="warlord-scene-host" data-region="scene"></div>
          <div class="warlord-map-fallback" data-region="fallback" hidden></div>
          <div class="warlord-map-caption"><span>TACTICAL TABLE / 正交战术沙盘</span><span>拖拽平移 · Shift 框选 · 双击棋子编组</span></div>
          <div class="warlord-compass" aria-hidden="true"><i>N</i><span></span></div>
          <div class="warlord-camera-hud" data-region="camera" aria-label="沙盘相机控制"></div>
          <div class="warlord-toast" data-region="toast" hidden></div>
          <div class="warlord-authority-banner" data-region="authority" hidden></div>
          <div class="warlord-hover-chip" data-region="hover" hidden></div>
          <div class="warlord-coach-tip" data-region="coach" hidden></div>
          <div class="warlord-command-intent" data-region="command-intent" hidden></div>
          <nav class="warlord-node-strip" data-region="nodes" aria-label="节点上下文导航"></nav>
          <div class="warlord-planning-layer" data-region="planning"></div>
        </section>
        <aside class="warlord-action-rail" data-region="actions" aria-label="合法行动与事件"></aside>
      </main>
      <footer class="warlord-roster" data-region="cards" aria-label="八卡科技与生产"></footer>
      <div class="warlord-battle-layer" data-region="battle"></div>
      <div class="warlord-config-layer" data-region="config"></div>
      <div class="warlord-live" data-region="live" aria-live="polite"></div>
    </div>`;
  }

  private startScene(): void {
    const host = this.root.querySelector<HTMLElement>('[data-region="scene"]');
    if (!host) return;
    try {
      if (this.init.forceWebglFailure) throw new Error('测试开关强制关闭 WebGL');
      this.scene = new SandtableScene(host, {
        reducedMotion: window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true,
        mapTheme: this.mapTheme,
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
          this.notice = message;
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
    this.startScene();
  }

  private get playbackRecord(): BattleRecord | null {
    if (!this.playback) return null;
    return this.game.battles.find((record) => record.battleId === this.playback?.battleId) ?? null;
  }

  private clearAutomation(): void {
    if (this.automationTimer !== null) window.clearTimeout(this.automationTimer);
    this.automationTimer = null;
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
      this.cameraHudExpanded = false;
      this.renderCameraHud();
    }, CAMERA_HUD_REVEAL_MS);
  }

  private readonly onCameraSurfaceActivity = (event: Event): void => {
    if (isCameraSurfaceTarget(event.target)) this.revealCameraHud();
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

  private async beginAs2Battle(command: MoveOrAttackCommand): Promise<void> {
    const bridgeSend = this.init.bridgeSend;
    if (!bridgeSend) {
      this.handoffPending = false;
      this.setNotice('Launcher 战斗桥不可用；产品模式不会回退到 JS 模拟。', 'error');
      this.render();
      return;
    }
    const nonce = `${this.game.strategicRound}.${this.game.commandSequence + 1}.${this.game.battleOrdinal + 1}.${Date.now().toString(36)}`;
    const requestId = `battle.${nonce}`;
    const callId = `wb.${nonce}`;
    this.pendingBattleCallId = callId;
    this.handoffPending = true;
    this.authorityBlocked = false;
    this.notice = '正在冻结战略态并移交 AS2 真实战斗…';
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
      if (bridgeSend(envelope) !== true) {
        this.pendingBattleCallId = null;
        this.handoffPending = false;
        this.setNotice('Launcher 未接收 AS2 战斗请求；战略态未改变，也不会运行 JS 战斗。', 'error');
        this.render();
        return;
      }
      this.clearAuthorityAckTimer();
      this.authorityAckTimer = window.setTimeout(() => {
        this.authorityAckTimer = null;
        if (this.disposed || this.pendingBattleCallId !== callId) return;
        this.pendingBattleCallId = null;
        this.handoffPending = false;
        this.authorityBlocked = true;
        this.setNotice('Launcher 未及时确认交接；结果按未知处理，战略态已冻结。', 'error');
        this.render();
      }, 5000);
    } catch (error) {
      if (this.disposed || this.pendingBattleCallId !== callId) return;
      this.pendingBattleCallId = null;
      this.handoffPending = false;
      this.setNotice(error instanceof Error ? error.message : String(error), 'error');
      this.render();
    }
  }

  private async consumeAs2Resume(resume: WarlordInitData['resume']): Promise<void> {
    const digest = resume && typeof resume === 'object' && 'inputDigest' in resume
      && typeof resume.inputDigest === 'string' ? resume.inputDigest : '<invalid>';
    if (this.consumedResumeDigest === digest) return;
    this.consumedResumeDigest = digest;
    const result = await applyAs2BattleResume(resume);
    if (this.disposed || this.consumedResumeDigest !== digest) return;
    this.handoffPending = false;
    this.pendingBattleCallId = null;
    this.clearAuthorityAckTimer();
    if (!result.ok || !result.state || !result.battleRecord) {
      if (result.state) this.game = result.state;
      this.authorityBlocked = result.resultUnknown;
      this.setNotice(`${result.error ?? 'AS2 战斗回执无法验收。'}${result.resultUnknown ? ' 不能重试或继续战略结算。' : ''}`, 'error');
      this.render();
      return;
    }
    this.game = result.state;
    this.authorityBlocked = false;
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
    this.openBattle(result.battleRecord);
    this.notice = 'AS2 真实战斗回执已验收；战宠经济观测已记录为只读数据。';
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
      this.notice = 'Launcher 已接受冻结请求，正在切换至 AS2 真实战场…';
      this.renderLiveRegion();
      return true;
    }
    this.pendingBattleCallId = null;
    this.handoffPending = false;
    this.authorityBlocked = false;
    this.setNotice(typeof data.message === 'string'
      ? data.message : `AS2 战斗交接被拒绝：${String(data.error ?? 'unknown')}`, 'error');
    this.render();
    return true;
  }

  private scheduleAutomation(): void {
    this.clearAutomation();
    if (this.disposed || this.handoffPending || this.authorityBlocked) return;
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
          this.playback = null;
          this.render();
        }, AI_BATTLE_DWELL_MS);
      }
      return;
    }
    if (this.aiReplay) {
      // 每条 AI 命令间隔不小于棋子补间时长，逐条投影中间态
      this.automationTimer = window.setTimeout(() => this.stepAiReplay(), AI_REPLAY_INTERVAL_MS);
      return;
    }
    if (this.game.phase === 'GAME_OVER') return;
    if ((this.game.phase === 'FIRST_FACTION_ACTION' || this.game.phase === 'SECOND_FACTION_ACTION')
      && this.game.activeFactionId === 'blue') {
      if (this.init.battleAuthority === 'as2') {
        this.automationTimer = window.setTimeout(() => {
          if (this.disposed || this.handoffPending || this.authorityBlocked) return;
          const command = generateNextAiAction(this.game, 'blue', this.aiSeenTransitions);
          if (!command) {
            this.dispatch({ type: 'END_ACTION', factionId: 'blue' }, '蓝方 AI 结束行动。');
            return;
          }
          const validation = validateCommand(this.game, command);
          const isBattle = validation.ok && validation.isBattle === true;
          if (this.dispatch(command, isBattle ? '蓝方 AI 正在移交 AS2 实战。' : '蓝方 AI 完成一条机动命令。')
            && !isBattle) {
            this.rememberAppliedTransitions(command);
          }
        }, AI_AS2_INTERVAL_MS);
        return;
      }
      this.automationTimer = window.setTimeout(() => {
        if (this.disposed || this.aiReplay) return;
        this.beginAiReplay();
      }, 180);
      return;
    }
    if (this.game.phase === 'SETTLEMENT_PLANNING' && !this.game.factions.blue.planningCommitted) {
      this.automationTimer = window.setTimeout(() => {
        if (this.disposed) return;
        const ai = runAiPlanning(this.game, 'blue');
        this.game = ai.state;
        this.notice = `蓝方 AI 完成结算规划：${ai.commands.length} 条命令。`;
        this.render();
      }, 150);
    }
  }

  // fixture 模式：先在行动前状态上跑出整回合命令，再按节奏逐条重放到真实状态
  private beginAiReplay(): void {
    const run = runAiActionPhase(this.game, 'blue');
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
      ? '蓝方 AI 结束行动。'
      : isLast
        ? `蓝方 AI 完成行动：${replay.commands.length} 条合法命令。`
        : `蓝方 AI 行动 ${replay.index}/${replay.commands.length}。`;
    const succeeded = this.dispatch(command, label);
    // 防御：重放命令与实时状态不一致时放弃本次队列；下个渲染周期会按实时状态重建
    if (!succeeded) {
      this.aiReplay = null;
      return;
    }
    // AI 重放中的战斗以 4× 播完并排队依次呈现，不阻塞后续命令节奏
    if (this.playback && this.playback.speed !== 4) {
      this.playback = { ...this.playback, speed: 4 };
    }
    if (isLast) this.aiReplay = null;
  }

  private dispatch(command: GameCommand, successNotice?: string, deferSuccessRender = false): boolean {
    if (this.handoffPending || this.authorityBlocked) {
      this.setNotice(this.handoffPending
        ? 'AS2 战斗交接尚未完成。'
        : 'AS2 战斗结果未知，战略态已冻结。', 'error');
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
      this.setNotice(validation.error ?? '命令非法。', 'error');
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
      this.setNotice(result.error ?? '命令非法。', 'error');
      this.render();
      return false;
    }
    this.game = result.state;
    this.notice = successNotice ?? '命令已由确定性规则核心接受。';
    if (result.battleId) {
      const record = this.game.battles.find((candidate) => candidate.battleId === result.battleId);
      if (record) this.openBattle(record);
    }
    if (!deferSuccessRender) this.render();
    return true;
  }

  private openBattle(record: BattleRecord): void {
    this.playback = { battleId: record.battleId, index: 0, speed: 1, paused: false, showLog: false };
  }

  private inspectNode(nodeId: NodeId): void {
    if (!this.game.map.nodes[nodeId]) return;
    this.selectedNodeId = nodeId;
    this.selectedPieceIds = this.selectedPieceIds.filter((pieceId) => this.game.pieces[pieceId]?.nodeId === nodeId);
    const productionSlotId = firstProductionSlotId(this.game, 'red', nodeId);
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
    this.notice = `已查看${this.game.map.nodes[nodeId].displayName}。`;
    this.render();
  }

  // 门禁文案按真实原因分流：播放 / AS2 移交 / 结果未知 / 非红方行动阶段
  private selectionBlockReason(): string | null {
    if (this.playback) return '战斗播放期间不能建立编组或框选。';
    if (this.handoffPending) return '正在移交 AS2 战斗，请稍候。';
    if (this.authorityBlocked) return '战斗结果未知，战略态已冻结。';
    if (this.game.activeFactionId !== 'red'
      || (this.game.phase !== 'FIRST_FACTION_ACTION' && this.game.phase !== 'SECOND_FACTION_ACTION')) {
      return '只有红方行动阶段可以建立命令编组。';
    }
    return null;
  }

  private canSelectPieces(): boolean {
    return this.selectionBlockReason() === null;
  }

  private selectionOrigin(): NodeId | null {
    const first = this.selectedPieceIds
      .map((pieceId) => this.game.pieces[pieceId])
      .find((piece) => piece?.factionId === 'red' && piece.hp > 0);
    return first?.nodeId ?? null;
  }

  private reconcileSelection(): void {
    const existing = canonicalPieceIds(this.selectedPieceIds)
      .filter((pieceId) => this.game.pieces[pieceId]?.factionId === 'red' && this.game.pieces[pieceId]!.hp > 0);
    const origin = existing.length > 0 ? this.game.pieces[existing[0]!]!.nodeId : null;
    this.selectedPieceIds = origin
      ? existing.filter((pieceId) => this.game.pieces[pieceId]?.nodeId === origin)
      : [];
    // 编组被状态变化清空时，未确认的进攻武装一并解除
    if (!origin) this.disarmAttack();
    if (origin) this.inspectNode(origin);
  }

  private commandPreviews(): ActionPreview[] {
    // 战斗播放期间不做 3D 高亮与命令预览，点击降级为只读查看
    if (this.playback || this.handoffPending || this.authorityBlocked) return [];
    const origin = this.selectionOrigin();
    if (!origin || this.selectedPieceIds.length === 0) return [];
    return buildActionPreviews(this.game, origin, this.selectedPieceIds);
  }

  private selectPiece(pieceId: string, additive: boolean): void {
    const piece = this.game.pieces[pieceId];
    if (!piece) return;
    // 选择变化意味着进攻确认的目标上下文已改变
    this.disarmAttack();
    if (piece.factionId !== 'red') {
      if (this.selectedPieceIds.length > 0) {
        this.handleNodeIntent(piece.nodeId);
        return;
      }
      this.selectedPieceIds = [];
      this.inspectNode(piece.nodeId);
      this.notice = `${this.game.map.nodes[piece.nodeId].displayName}的敌方棋子仅供查看。`;
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
    const crossNode = additive && origin !== null && origin !== piece.nodeId;
    if (!additive || crossNode) {
      this.selectedPieceIds = [pieceId];
    } else if (this.selectedPieceIds.includes(pieceId)) {
      this.selectedPieceIds = this.selectedPieceIds.filter((id) => id !== pieceId);
    } else {
      this.selectedPieceIds = canonicalPieceIds([...this.selectedPieceIds, pieceId]);
    }
    this.inspectNode(piece.nodeId);
    this.notice = crossNode
      ? `编组不能跨据点；已改选${this.game.map.nodes[piece.nodeId].displayName}的 1 枚棋子。`
      : this.selectedPieceIds.length > 0
        ? `已编组 ${this.selectedPieceIds.length} 枚棋子；点击高亮据点直接下令。`
        : '已取消该棋子选择。';
    this.render();
  }

  private setPieceChecked(pieceId: string, checkedState: boolean): void {
    const piece = this.game.pieces[pieceId];
    if (!piece || piece.factionId !== 'red' || !this.canSelectPieces()) return;
    this.disarmAttack();
    if (!checkedState) {
      this.selectedPieceIds = this.selectedPieceIds.filter((id) => id !== pieceId);
    } else if (this.selectionOrigin() !== null && this.selectionOrigin() !== piece.nodeId) {
      this.selectedPieceIds = [pieceId];
    } else {
      this.selectedPieceIds = canonicalPieceIds([...this.selectedPieceIds, pieceId]);
    }
    this.inspectNode(piece.nodeId);
    this.notice = this.selectedPieceIds.length > 0
      ? `已编组 ${this.selectedPieceIds.length} 枚棋子；点击高亮据点直接下令。`
      : '当前编组已清空。';
    this.render();
  }

  private selectAllAtNode(nodeId: NodeId): void {
    this.disarmAttack();
    if (!this.canSelectPieces()) {
      this.selectNode(nodeId);
      return;
    }
    const pieceIds = canonicalPieceIds(piecesAtNode(this.game, nodeId, 'red').map((piece) => piece.pieceId));
    this.selectedPieceIds = pieceIds;
    this.inspectNode(nodeId);
    this.notice = pieceIds.length > 0
      ? `已编组${this.game.map.nodes[nodeId].displayName}全部 ${pieceIds.length} 枚己方棋子。`
      : `${this.game.map.nodes[nodeId].displayName}没有可选己方棋子。`;
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
    this.selectedPieceIds = selection.additive && origin === selection.nodeId
      ? canonicalPieceIds([...this.selectedPieceIds, ...selection.pieceIds])
      : canonicalPieceIds(selection.pieceIds);
    this.inspectNode(selection.nodeId);
    this.notice = `框选编组 ${this.selectedPieceIds.length} 枚${selection.ignoredCount > 0 ? `；另有 ${selection.ignoredCount} 枚因跨据点被忽略` : ''}。点击高亮据点直接下令。`;
    this.render();
  }

  private clearPieceSelection(notice: string): void {
    this.disarmAttack();
    if (this.selectedPieceIds.length === 0) return;
    this.selectedPieceIds = [];
    this.notice = notice;
    this.render();
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
      this.setNotice(`${this.game.map.nodes[nodeId].displayName}是当前编组起点；请选择高亮相邻据点。`, 'error');
      this.render();
      return;
    }
    const preview = this.commandPreviews().find((candidate) => candidate.targetNodeId === nodeId);
    if (!preview) {
      this.disarmAttack();
      this.setNotice(`${this.game.map.nodes[nodeId].displayName}与当前编组起点不相邻；按 Esc 取消编组后可改为查看。`, 'error');
      this.render();
      return;
    }
    if (!preview.ok) {
      this.disarmAttack();
      this.setNotice(`无法向${preview.targetName}下令：${preview.error ?? '命令非法。'}`, 'error');
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
    this.setNotice(`再次点击确认进攻${targetName}；3 秒内有效，点击他处或 Esc 解除。`, 'error');
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
    const requestedCount = this.selectedPieceIds.length;
    const command: GameCommand = {
      type: 'MOVE_OR_ATTACK',
      factionId: 'red',
      pieceIds: [...this.selectedPieceIds],
      originNodeId,
      targetNodeId: preview.targetNodeId,
    };
    if (!this.dispatch(command, undefined, true)) return;
    // 首次命令成功：引导从"下令"推进到"结束行动"
    this.coachCommandIssued = true;
    if (preview.isBattle && this.init.battleAuthority === 'as2') {
      this.selectedPieceIds = [];
      this.notice = '进攻命令已冻结；正在移交 AS2 真实战斗，战略态尚未结算。';
      this.render();
      return;
    }
    const followed = followCommandSelection(this.game, preview.actualPieceIds, preview.targetNodeId);
    this.selectedPieceIds = followed.pieceIds;
    this.inspectNode(followed.selectedNodeId);
    const appliedCopy = preview.actualPieceIds.length < requestedCount
      ? `仅 ${preview.actualPieceIds.length}/${requestedCount} 枚生效；`
      : `${preview.actualPieceIds.length}/${requestedCount} 枚生效；`;
    this.notice = followed.pieceIds.length > 0
      ? `${preview.isBattle ? '进攻' : '机动'}命令已接受，${appliedCopy}${followed.pieceIds.length} 枚幸存棋子保持选中。`
      : `${preview.isBattle ? '进攻' : '机动'}命令已接受，${appliedCopy}编组已无幸存棋子。`;
    this.render();
  }

  private startNewGame(): void {
    this.clearAutomation();
    this.clearAuthorityAckTimer();
    this.clearAttackArmTimer();
    this.aiReplay = null;
    this.armedTargetNodeId = null;
    this.handoffPending = false;
    this.authorityBlocked = false;
    this.pendingBattleCallId = null;
    this.consumedResumeDigest = null;
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
    this.game = createGame({ seed: this.seedDraft, preset: this.presetDraft, difficulty: this.difficultyDraft });
    this.selectedNodeId = this.game.preset === 'all-units' ? 'R-Supply' : 'R-HQ';
    this.selectedPieceIds = [];
    this.nodePageIndex = 0;
    this.productionControlMode = 'auto';
    this.productionNodeId = recommendProductionLane(this.game, 'red')?.nodeId ?? 'R-HQ';
    this.selectedSlotId = firstProductionSlotId(this.game, 'red', this.productionNodeId) ?? 'R-HQ:1';
    this.playback = null;
    this.configOpen = false;
    this.notice = `已按种子 ${this.game.gameSeed} 重开${this.game.preset === 'all-units' ? '全兵种演习' : '标准对局'}。`;
    this.render();
  }

  private readonly onInput = (event: Event): void => {
    const target = event.target as HTMLInputElement | null;
    if (target?.dataset.field === 'seed') this.seedDraft = target.value;
  };

  private readonly onChange = (event: Event): void => {
    const target = event.target as HTMLInputElement | HTMLSelectElement | null;
    if (!target) return;
    if (target.dataset.field === 'piece') {
      this.setPieceChecked(target.value, (target as HTMLInputElement).checked);
    }
    if (target.dataset.field === 'slot') {
      this.selectedSlotId = target.value;
      this.render();
    }
    if (target.dataset.field === 'production-node') {
      const nodeId = target.value as NodeId;
      if (!this.game.map.nodes[nodeId]) return;
      this.productionNodeId = nodeId;
      this.selectedSlotId = firstProductionSlotId(this.game, 'red', nodeId) ?? `${nodeId}:1`;
      this.notice = `正在查看${this.game.map.nodes[nodeId].displayName}生产队列。`;
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
    if (this.handoffPending) {
      this.setNotice('正在等待 Launcher 完成 AS2 战斗交接；当前窗口会由 Host 精确关闭。', 'error');
      this.renderLiveRegion();
      return;
    }
    if (this.authorityBlocked && action !== 'request-close') {
      this.setNotice('AS2 战斗结果未知，当前战略态只能关闭，不能继续结算。', 'error');
      this.renderLiveRegion();
      return;
    }
    if (action === 'select-node') this.handleNodeIntent(target.dataset.node as NodeId);
    if (action === 'select-all-at-node') this.selectAllAtNode(this.selectedNodeId);
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
      const orderExists = this.game.factions.red.productionQueues[nodeId]
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
      const order = this.game.factions.red.productionQueues[nodeId]
        ?.find((slot) => slot.slotId === slotId)
        ?.orders.find((candidate) => candidate.orderId === orderId);
      const orderName = order ? getCardDefinition(order.cardId).displayName : '该生产';
      const refund = order?.goldCost ?? 0;
      const released = order?.populationCost ?? 0;
      this.dispatch({
        type: 'CANCEL_PRODUCTION',
        factionId: 'red',
        nodeId,
        slotId,
        orderId,
      }, `${orderName}订单已撤销：返还 ${refund}G，释放 ${released} 预留人口。`);
    }
    if (action === 'inspect-auto-slot') {
      const recommendation = recommendProductionLane(this.game, 'red');
      if (!recommendation) return;
      this.productionNodeId = recommendation.nodeId;
      this.selectedSlotId = recommendation.slotId;
      this.render();
    }
    if (action === 'allocate-xp') {
      const cardId = Number(target.dataset.card) as CardId;
      this.dispatch({
        type: 'ALLOCATE_XP',
        factionId: 'red',
        cardId,
        amount: Math.min(1000, this.game.factions.red.xpPool),
      });
    }
    if (action === 'promotion') {
      this.dispatch({
        type: 'PURCHASE_PROMOTION',
        factionId: 'red',
        cardId: Number(target.dataset.card) as CardId,
        promotionId: target.dataset.promotion as PromotionId,
      });
    }
    if (action === 'production') {
      const cardId = Number(target.dataset.card) as CardId;
      const choice = resolveProductionChoice(
        this.game,
        'red',
        cardId,
        this.productionControlMode,
        this.productionNodeId,
        this.selectedSlotId,
      );
      if (!choice.nodeId || !choice.slotId) {
        this.setNotice(choice.error ?? '没有可用生产槽。', 'error');
        this.render();
        return;
      }
      this.productionNodeId = choice.nodeId;
      this.selectedSlotId = choice.slotId;
      this.dispatch({
        type: 'ENQUEUE_PRODUCTION',
        factionId: 'red',
        nodeId: choice.nodeId,
        slotId: choice.slotId,
        cardId,
      }, `${getCardDefinition(cardId).displayName}已加入${choice.nodeName} ${choice.slotNumber}号槽（${choice.mode === 'auto' ? '自动调度' : '精确槽位'}）。`);
    }
    if (action === 'commit-planning') this.dispatch({ type: 'COMMIT_PLANNING', factionId: 'red' });
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
      this.playback = null;
      this.render();
    }
  };

  private readonly onKeyDown = (event: KeyboardEvent): void => {
    if (this.disposed || !this.root.isConnected) return;
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
    if (event.key.toLowerCase() === 'e' && !this.playback && this.game.activeFactionId === 'red'
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
    if (this.dispatch({ type: 'END_ACTION', factionId: 'red' })) {
      // 玩家完成过一整轮行动后不再显示首次引导
      this.coachDone = true;
      this.renderCoach();
    }
  }

  public requestClose(reason = 'escape'): boolean {
    if (this.disposed || reason !== 'escape') return false;
    if (this.handoffPending) {
      this.setNotice('AS2 战斗正在交接；等待 Launcher 精确关闭当前窗口。', 'error');
      this.renderLiveRegion();
      return true;
    }
    if (this.configOpen) {
      this.configOpen = false;
      this.render();
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
        this.notice = '已跳到战斗结尾；再按 Esc 返回沙盘。';
      } else {
        this.playback = null;
        this.notice = '已关闭战斗播放，返回沙盘。';
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

  private render(): void {
    if (this.disposed) return;
    this.reconcileSelection();
    const app = this.root.querySelector<HTMLElement>('.warlord-app');
    if (app) {
      app.dataset.mapTheme = this.mapTheme;
      app.dataset.battleAuthority = this.init.battleAuthority;
      app.dataset.authorityState = this.authorityBlocked
        ? 'blocked' : this.handoffPending ? 'handoff' : 'ready';
    }
    this.renderCommandBar();
    this.renderForces();
    this.renderNodes();
    this.renderActions();
    this.renderCommandIntent();
    this.renderCards();
    this.renderPlanning();
    this.renderBattle();
    this.renderConfig();
    this.renderFallback();
    this.renderCameraHud();
    this.renderAuthorityBanner();
    this.renderCoach();
    this.renderLiveRegion();
    this.root.dataset.ready = 'true';
    this.root.dataset.phase = this.game.phase;
    this.root.dataset.selectedNode = this.selectedNodeId;
    this.root.dataset.selectedPieceCount = String(this.selectedPieceIds.length);
    this.scene?.update(this.game, this.selectedNodeId, this.selectedPieceIds, this.commandPreviews());
    const generation = this.portraitGeneration.next();
    void mountPortraits(this.root).then(() => {
      if (!this.portraitGeneration.isCurrent(generation)) return;
      this.root.dataset.portraitsReady = 'true';
    });
    this.scheduleAutomation();
  }

  private renderCommandBar(): void {
    const round = this.root.querySelector<HTMLElement>('[data-region="round"]');
    const factions = this.root.querySelector<HTMLElement>('[data-region="factions"]');
    const theater = this.root.querySelector<HTMLElement>('[data-region="theater"]');
    if (theater) theater.textContent = `${MAP_THEMES[this.mapTheme].theaterLabel} · 确定性指挥终端`;
    if (round) round.innerHTML = `<b>R${this.game.strategicRound}<small>/24</small></b><span>${PHASE_LABEL[this.game.phase]} · ${this.game.activeFactionId ? `${factionLabel(this.game.activeFactionId)}行动` : '统一处理'}</span>`;
    if (factions) factions.innerHTML = (['red', 'blue'] as const).map((factionId) => {
      const faction = this.game.factions[factionId];
      return `<section class="warlord-faction ${factionId}" data-testid="hud-${factionId}"><b>${factionId === 'red' ? 'R' : 'B'}</b><span><em>${faction.gold}G</em><em>${faction.populationUsed}+${faction.populationReserved}/${faction.populationCap}人</em><em>${faction.actionPoints}AP</em></span></section>`;
    }).join('');
  }

  private renderForces(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="forces"]');
    if (!region) return;
    const node = this.game.map.nodes[this.selectedNodeId];
    const pieces = piecesAtNode(this.game, this.selectedNodeId);
    const canSelect = this.canSelectPieces();
    const redCount = pieces.filter((piece) => piece.factionId === 'red').length;
    region.innerHTML = `<header><span>当前据点</span><b>${escapeHtml(node.displayName)}</b><small>${escapeHtml(ownerLabel(node.ownerFactionId))} · 容量 ${node.pieceIds.length}/${node.capacity}</small></header>
      <div class="warlord-force-toolbar"><button class="warlord-select-all" data-action="select-all-at-node" aria-label="全选本据点全部己方棋子" title="全选本据点全部己方棋子（等同双击棋子）"${disabled(redCount === 0)}>全选本据点</button></div>
      <div class="warlord-force-list">${pieces.length === 0 ? '<p class="warlord-empty">无人驻守</p>' : pieces.map((piece) => {
        const definition = getCardDefinition(piece.cardId);
        return `<label class="warlord-piece ${piece.factionId}${this.selectedPieceIds.includes(piece.pieceId) ? ' selected' : ''}" data-piece-id="${escapeHtml(piece.pieceId)}">
          <input type="checkbox" data-field="piece" value="${escapeHtml(piece.pieceId)}"${checked(this.selectedPieceIds.includes(piece.pieceId))}${disabled(!canSelect || piece.factionId !== 'red')}>
          <span class="warlord-mini-portrait" data-warlord-portrait="${escapeHtml(definition.identifier)}"><img alt=""></span>
          <span><b>${escapeHtml(definition.displayName)}</b><small>${escapeHtml(piece.pieceId)} · Lv.${this.game.factions[piece.factionId].cards[piece.cardId].level}</small><i${hpBarClass(piece.hp, piece.maxHp)}><em style="width:${hpPercent(piece.hp, piece.maxHp)}%"></em></i></span>
        </label>`;
      }).join('')}</div>
      <div class="warlord-node-facts"><span>攻宽 ${node.attackWidth}</span><span>防宽 ${node.defenseWidth}</span><span>${node.goldIncome}G</span><span>+${node.apBonus}AP</span></div>`;
  }

  private renderNodes(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="nodes"]');
    if (!region) return;
    const projections = projectNodes(this.game);
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
    region.dataset.totalNodes = String(window.totalCount);
    region.dataset.visibleNodes = String(window.nodeIds.length);
    region.dataset.page = String(window.pageIndex + 1);
    region.dataset.pages = String(window.pageCount);
    const scopeLabel = window.mode === 'context' ? '局部' : '全域';
    const scopeMeta = window.mode === 'context'
      ? `${window.nodeIds.length}/${window.totalCount}`
      : `${window.pageIndex + 1}/${window.pageCount}`;
    const cards = window.nodeIds
      .map((nodeId) => byId.get(nodeId))
      .filter((node) => node !== undefined)
      .map((node) => {
        const preview = previewById.get(node.nodeId);
        const partial = preview?.ok === true && preview.actualPieceIds.length < this.selectedPieceIds.length;
        const commandState = preview?.ok
          ? preview.isBattle ? 'attack' : partial ? 'partial' : 'move'
          : preview ? 'invalid' : 'none';
        const shortName = node.displayName.replace('红方', 'R·').replace('蓝方', 'B·');
        const status = `${node.ownerLabel}${node.stable ? '·稳' : ''}`;
        const commandCopy = !preview ? status
          : preview.ok
            ? `${preview.isBattle ? '进攻' : '机动'} ${preview.actualPieceIds.length}/${this.selectedPieceIds.length}`
            : '命令阻断';
        const accessibleLabel = `${node.displayName}，红方 ${node.redCount}，蓝方 ${node.blueCount}，${node.ownerLabel}${node.stable ? '，稳定' : ''}${preview ? `，${preview.ok ? commandCopy : preview.error}` : ''}`;
        const title = preview?.error ? `${accessibleLabel}；${preview.error}` : accessibleLabel;
        return `<button class="warlord-node-card owner-${node.ownerFactionId ?? 'neutral'}${node.nodeId === this.selectedNodeId ? ' selected' : ''}${node.contested ? ' contested' : ''}${preview ? ` command-${commandState}` : ''}" data-action="select-node" data-node="${node.nodeId}" data-command-state="${commandState}" data-command-actual="${preview?.actualPieceIds.length ?? 0}" data-command-requested="${this.selectedPieceIds.length}" data-testid="node-${node.nodeId}" aria-label="${escapeHtml(accessibleLabel)}" title="${escapeHtml(title)}" aria-pressed="${node.nodeId === this.selectedNodeId}"><b>${escapeHtml(shortName)}</b><span class="warlord-node-meta"><em>R${node.redCount}/B${node.blueCount}</em><i>${escapeHtml(commandCopy)}</i></span></button>`;
      }).join('');
    region.innerHTML = `<div class="warlord-node-index">
      <button data-action="toggle-node-scope" aria-label="切换局部与全域节点索引"><b>${scopeLabel}</b><span>${scopeMeta}</span></button>
      <div class="warlord-node-pager"${window.mode === 'context' ? ' hidden' : ''}>
        <button data-action="node-page-prev" aria-label="上一页节点"${disabled(!window.hasPrevious)}>‹</button>
        <button data-action="node-page-next" aria-label="下一页节点"${disabled(!window.hasNext)}>›</button>
      </div>
    </div><div class="warlord-node-window">${cards}</div>`;
  }

  private renderProductionConsole(planning: boolean): string {
    const nodes = projectProductionNodes(this.game, 'red');
    const inspected = nodes.find((node) => node.nodeId === this.productionNodeId) ?? nodes[0];
    const recommendation = recommendProductionLane(this.game, 'red');
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
        ? `<button class="warlord-production-cancel" data-action="cancel-production" data-node="${escapeHtml(lane.nodeId)}" data-slot="${escapeHtml(lane.slotId)}" data-order="${escapeHtml(lane.head.orderId)}" data-cancellable="true" aria-label="撤销${escapeHtml(lane.head.displayName)}订单，返还 ${lane.head.goldCost}G" title="尚未开工：全额返还 ${lane.head.goldCost}G，并释放 ${lane.head.populationCost} 预留人口">撤销</button>`
        : '';
      const tail = lane.tail.length > 0
        ? `<span class="warlord-lane-tail" aria-label="后续 ${escapeHtml(tailNames)}">${lane.tail.map((order) => order.cancellable
          ? `<button class="warlord-tail-order" data-action="cancel-production" data-node="${escapeHtml(lane.nodeId)}" data-slot="${escapeHtml(lane.slotId)}" data-order="${escapeHtml(order.orderId)}" data-cancellable="true" aria-label="撤销后续${escapeHtml(order.displayName)}订单，返还 ${order.goldCost}G" title="待开工，可全额撤销"><span class="warlord-tail-order-portrait" data-warlord-portrait="${escapeHtml(order.portraitRef)}"><img alt=""></span><span>${escapeHtml(order.displayName)}</span><i aria-hidden="true">×</i></button>`
          : `<span class="warlord-tail-order is-locked" title="${escapeHtml(order.cancelReason ?? '订单已锁定')}"><span class="warlord-tail-order-portrait" data-warlord-portrait="${escapeHtml(order.portraitRef)}"><img alt=""></span><span>${escapeHtml(order.displayName)}</span><i aria-hidden="true">•</i></span>`).join('')}</span>`
        : `<span class="warlord-lane-tail">${lane.queueLength > 0 ? '队首执行中 · 无后续订单' : '队列为空'}</span>`;
      return `<div class="warlord-production-lane state-${lane.state}${recommended ? ' is-recommended' : ''}${exactSelected ? ' is-exact' : ''}${lane.head?.cancellable ? ' has-cancellable-head' : ''}" data-state="${lane.state}" data-queue-length="${lane.queueLength}" data-recommended="${recommended}" role="listitem">
        <button class="warlord-production-lane-select" data-action="choose-production-slot" data-node="${escapeHtml(lane.nodeId)}" data-slot="${escapeHtml(lane.slotId)}" data-state="${lane.state}" aria-pressed="${exactSelected}" aria-label="切换为精确槽位：${escapeHtml(inspected.displayName)} ${lane.slotNumber}号槽" title="点击后切换为精确槽位：${escapeHtml(inspected.displayName)} ${lane.slotNumber}号槽">
          <span class="warlord-lane-index"><b>${String(lane.slotNumber).padStart(2, '0')}</b><i>${recommended ? 'AUTO' : exactSelected ? 'EXACT' : lane.stateLabel}</i></span>
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
      ? `<button class="warlord-production-undo" data-action="cancel-production" data-node="${escapeHtml(latestCancellable.nodeId)}" data-slot="${escapeHtml(latestCancellable.slotId)}" data-order="${escapeHtml(latestCancellable.orderId)}" data-cancellable="true" title="撤销${escapeHtml(latestCancellable.displayName)}，全额返还 ${latestCancellable.goldCost}G">撤销上一单</button>`
      : canInspectRecommendation ? '<button data-action="inspect-auto-slot">查看 AUTO</button>' : '';
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
        <span class="warlord-production-network-copy"><b>${escapeHtml(compactProductionNodeName(order.nodeDisplayName))}·${order.slotNumber}</b><small>${order.queuePosition === 0 ? `${order.progressPercent}%` : `Q${order.queuePosition + 1}`}</small></span>
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
        <button data-action="toggle-production-mode" class="mode-${this.productionControlMode}" aria-pressed="${!modeIsAuto}" title="${modeIsAuto ? '切换为精确据点与槽位' : '切换为全网自动调度'}"><b>${modeIsAuto ? 'AUTO' : 'EXACT'}</b><span>${modeIsAuto ? '自动调度' : '精确槽位'}</span></button>
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
    const eventFeed = `<section class="warlord-event-feed"><h3>战况流</h3>${events.map((entry) => `<p><time>R${entry.strategicRound}</time>${escapeHtml(entry.message)}</p>`).join('')}</section>`;
    const canEnd = this.game.activeFactionId === 'red'
      && (this.game.phase === 'FIRST_FACTION_ACTION' || this.game.phase === 'SECOND_FACTION_ACTION')
      && !this.playback;
    region.dataset.mode = planning ? 'production' : 'action';
    if (planning) {
      const orders = projectProductionNodes(this.game, 'red').reduce((total, node) => total + node.orderCount, 0);
      region.innerHTML = `<header><span>生产调度</span><b>${this.productionControlMode === 'auto' ? '全网自动' : '精确控制'} · ${orders}单</b></header>
        <div class="warlord-action-scroll" data-region="action-scroll" role="region" aria-label="生产调度与战况" tabindex="0">
          ${this.renderProductionConsole(true)}
          ${eventFeed}
        </div>`;
      return;
    }
    region.innerHTML = `<header><span>命令预览 · 点击即执行</span><b>已选 ${this.selectedPieceIds.length} 枚</b></header>
      <div class="warlord-action-scroll" data-region="action-scroll" role="region" aria-label="可选节点、生产监控与战况" tabindex="0">
        <div class="warlord-route-actions">${previews.map((preview) => {
          const partial = preview.ok && preview.actualPieceIds.length < this.selectedPieceIds.length;
          return `<button class="${preview.isBattle ? 'is-attack' : 'is-move'}${partial ? ' is-partial' : ''}" data-action="move" data-node="${preview.targetNodeId}"${disabled(!preview.ok || !!this.playback)} title="${escapeHtml(preview.error ?? '合法命令')}"><b>${preview.isBattle ? '进攻' : '机动'} · ${escapeHtml(preview.targetName)}</b><span>${preview.ok ? `${preview.apCost} AP · ${partial ? '仅 ' : ''}${preview.actualPieceIds.length}/${this.selectedPieceIds.length} 枚生效` : escapeHtml(preview.error)}</span></button>`;
        }).join('')}</div>
        ${this.renderProductionConsole(false)}
        ${eventFeed}
      </div>
      <div class="warlord-action-footer"><button class="warlord-end-action" data-action="end-action"${disabled(!canEnd)}>结束红方行动 <kbd>E</kbd></button></div>`;
  }

  private renderCommandIntent(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="command-intent"]');
    if (!region) return;
    const origin = this.selectionOrigin();
    if (!origin || this.selectedPieceIds.length === 0) {
      region.hidden = true;
      region.innerHTML = '';
      region.dataset.legalTargets = '0';
      return;
    }
    const previews = this.commandPreviews();
    const legalCount = previews.filter((preview) => preview.ok).length;
    const partialCount = previews.filter((preview) => preview.ok
      && preview.actualPieceIds.length < this.selectedPieceIds.length).length;
    region.hidden = false;
    region.dataset.legalTargets = String(legalCount);
    region.dataset.partialTargets = String(partialCount);
    region.dataset.armedTarget = this.armedTargetNodeId ?? '';
    region.classList.toggle('is-armed', this.armedTargetNodeId !== null);
    region.classList.toggle('is-coach', this.armedTargetNodeId === null
      && !this.coachDone && !this.coachCommandIssued);
    if (this.armedTargetNodeId !== null) {
      const armedName = this.game.map.nodes[this.armedTargetNodeId]?.displayName ?? this.armedTargetNodeId;
      region.innerHTML = `<b>确认进攻</b><span>再次点击 ${escapeHtml(armedName)} 执行不可撤销进攻</span><small>3 秒内有效 · Esc / 点击他处解除</small>`;
      return;
    }
    region.innerHTML = `<b>编组 ${this.selectedPieceIds.length}</b><span>${escapeHtml(this.game.map.nodes[origin].displayName)} · ${legalCount} 个合法目标${partialCount > 0 ? ` · ${partialCount} 个容量受限` : ''}</span><small>点击高亮据点下令 · Esc 取消</small>`;
  }

  private renderCards(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="cards"]');
    if (!region) return;
    const planningPhase = this.game.phase === 'SETTLEMENT_PLANNING';
    region.innerHTML = `<div class="warlord-roster-label"><b>兵种蓝图</b><span>结算升级 / 排产</span>${planningPhase ? '' : '<small class="warlord-roster-hint">统一结算阶段开放排产 / 升阶</small>'}</div><div class="warlord-card-track">${CARD_IDS.map((cardId) => {
      const definition = getCardDefinition(cardId);
      const card = this.game.factions.red.cards[cardId];
      const promotion = nextPromotionFor(this.game, 'red', cardId);
      const promotionRule = promotion ? PROMOTIONS[promotion] : null;
      const production = resolveProductionChoice(
        this.game,
        'red',
        cardId,
        this.productionControlMode,
        this.productionNodeId,
        this.selectedSlotId,
      );
      const xpDisabled = this.game.phase !== 'SETTLEMENT_PLANNING'
        || this.game.factions.red.planningCommitted || this.game.factions.red.xpPool <= 0 || card.level >= 50;
      const promotionValidation = promotion ? validateCommand(this.game, {
        type: 'PURCHASE_PROMOTION', factionId: 'red', cardId, promotionId: promotion,
      }) : { ok: false, error: '升阶完成' };
      return `<article class="warlord-card tier-${definition.powerTier.slice(1, 2)}" data-testid="card-${cardId}">
        <span class="warlord-card-portrait" data-warlord-portrait="${escapeHtml(definition.identifier)}"><img alt=""><i>${escapeHtml(definition.behaviorId)}</i></span>
        <span class="warlord-card-copy"><b title="${escapeHtml(definition.displayName)}">${escapeHtml(definition.displayName)}</b><small class="warlord-card-stats"><strong>Lv.${card.level}</strong><em>${escapeHtml(definition.powerTier.slice(0, 2))}</em><em>${definition.productionCost}G</em></small><small>XP ${card.level >= 50 ? 'MAX' : `${card.xpIntoLevel}/${needXp(cardId, card.level)}`}</small></span>
        <span class="warlord-card-actions"><button data-action="allocate-xp" data-card="${cardId}"${disabled(xpDisabled)}>+XP</button><button data-action="promotion" data-card="${cardId}" data-promotion="${escapeHtml(promotion ?? '')}" title="${escapeHtml(promotionRule ? `Lv.${promotionRule.level} / ${promotionRule.cost}G` : '完成')}"${disabled(!promotionValidation.ok)}>升阶</button><button class="warlord-card-production" data-action="production" data-card="${cardId}" title="${escapeHtml(production.ok ? `${production.mode === 'auto' ? '自动调度' : '精确槽位'} → ${production.nodeName} ${production.slotNumber}号槽 · ${production.reason} · ${definition.productionCost}G/${definition.buildRounds}R/${definition.populationCost}人` : production.error ?? '排产不可用')}"${disabled(!production.ok)}>排产</button></span>
      </article>`;
    }).join('')}</div>`;
  }

  private renderPlanning(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="planning"]');
    if (!region) return;
    if (this.game.phase === 'SETTLEMENT_PLANNING') {
      region.innerHTML = `<div><b>统一结算规划</b><span>恢复、占领与收入已完成；分配经验、升阶并排产。</span></div><button data-action="commit-planning"${disabled(this.game.factions.red.planningCommitted)}>${this.game.factions.red.planningCommitted ? '红方已提交' : '提交红方规划'}</button>`;
      region.hidden = false;
      return;
    }
    if (this.game.phase === 'GAME_OVER' && this.game.result) {
      const winner = this.game.result.winner === 'draw' ? '平局' : `${factionLabel(this.game.result.winner)}胜利`;
      region.innerHTML = `<div><b>${winner}</b><span>${this.game.result.reason === 'elimination' ? '再生产能力与部队全部消失' : '24 回合计分结算'}</span></div><button data-action="restart">同配置重开</button>`;
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
        return `<article class="${unit.snapshot.factionId}${unit.dead ? ' dead' : ''}${event?.actorPieceId === pieceId ? ' acting' : ''}${event?.targetPieceId === pieceId ? ' targeted' : ''}"><span class="warlord-battle-portrait" data-warlord-portrait="${escapeHtml(getCardDefinition(unit.snapshot.cardId).identifier)}"><img alt=""></span><span><b>${escapeHtml(unit.snapshot.displayName)}</b><small>${escapeHtml(pieceId)}</small><i${hpBarClass(unit.hp, unit.snapshot.maxHp)}><em style="width:${hpPercent(unit.hp, unit.snapshot.maxHp)}%"></em></i><small>HP ${unit.hp}/${unit.snapshot.maxHp} · ${escapeHtml(unit.lastStatus)}</small></span></article>`;
      }).join('')}</section>`;
    }).join('');
    region.hidden = false;
    region.innerHTML = `<div class="warlord-battle-dialog" role="dialog" aria-modal="true" aria-label="战斗播放">
      <header><span><b>${escapeHtml(this.game.map.nodes[record.nodeId as NodeId]?.displayName ?? record.nodeId)}</b><small>${escapeHtml(record.battleId)}</small></span><strong>${playback.index}/${record.result.eventLog.length}</strong></header>
      <div class="warlord-battle-formations">${formations}</div>
      <div class="warlord-battle-event"><b>${event ? `R${event.battleRound} · ${escapeHtml(event.type)}` : '解析结果已冻结'}</b><p>${escapeHtml(event?.message ?? '播放层只消费战斗日志，不回写规则。')}</p></div>
      <div class="warlord-battle-controls"><button data-action="battle-pause">${playback.paused ? '继续' : '暂停'}</button><button data-action="battle-speed">${playback.speed}×</button><button data-action="battle-skip">立即结算</button><button data-action="battle-log">${playback.showLog ? '收起日志' : '逐回合日志'}</button><button data-action="battle-close"${disabled(!finished)}>返回沙盘</button></div>
      ${playback.showLog ? `<div class="warlord-battle-log">${record.result.eventLog.map((entry) => `<p><span>R${entry.battleRound}</span>${escapeHtml(entry.message)}</p>`).join('')}</div>` : ''}
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
    region.innerHTML = `<div class="warlord-config-dialog" role="dialog" aria-modal="true" aria-label="演习配置"><header><b>重开演习</b><button data-action="close-config" aria-label="关闭">×</button></header><label>确定性种子<input data-field="seed" value="${escapeHtml(this.seedDraft)}"></label><label>预设<select data-field="preset"><option value="standard"${selected(this.presetDraft === 'standard')}>标准开局</option><option value="all-units"${selected(this.presetDraft === 'all-units')}>全战宠演习</option></select></label><label>地图外观<select data-field="map-theme"><option value="desert"${selected(this.themeDraft === 'desert')}>沙漠沙盘</option><option value="tundra"${selected(this.themeDraft === 'tundra')}>冻原迁移预览</option></select></label><label>AI 难度<select data-field="difficulty">${DIFFICULTIES.map(([value, label]) => `<option value="${value}"${selected(this.difficultyDraft === value)}>${label}</option>`).join('')}</select></label><p>产品模式把交战交给 AS2 隔离战宠副本；战宠价格只进入经济观测，不写玩家战宠、经验、货币或存档。开发 harness 仍使用 fixture 规则。</p><button data-action="new-game">按配置重开</button></div>`;
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
    region.innerHTML = `<div class="warlord-fallback-notice"><b>3D 沙盘不可用</b><span>${escapeHtml(this.sceneError)}</span><small>规则与完整操作仍可通过以下节点继续。</small></div><div class="warlord-fallback-grid">${projectNodes(this.game).map((node) => {
      const preview = previewById.get(node.nodeId);
      const commandState = preview?.ok ? preview.isBattle ? 'attack' : 'move' : preview ? 'invalid' : 'none';
      return `<button data-action="select-node" data-node="${node.nodeId}" data-command-state="${commandState}" class="owner-${node.ownerFactionId ?? 'neutral'}${node.nodeId === this.selectedNodeId ? ' selected' : ''}${preview ? ` command-${commandState}` : ''}" title="${escapeHtml(preview?.error ?? '')}"><b>${escapeHtml(node.displayName)}</b><span>${preview?.ok ? `${preview.isBattle ? '进攻' : '机动'} ${preview.actualPieceIds.length}/${this.selectedPieceIds.length}` : preview?.error ?? `${node.ownerLabel} · R${node.redCount}/B${node.blueCount}`}</span></button>`;
    }).join('')}</div>`;
  }

  private renderCameraHud(): void {
    const region = this.root.querySelector<HTMLElement>('[data-region="camera"]');
    if (!region) return;
    const detailLabel = this.cameraSnapshot.detailTier === 'overview'
      ? '战区总览'
      : this.cameraSnapshot.detailTier === 'tactical' ? '战术近距' : '作战视图';
    const unavailable = !this.scene;
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
    if (position) position.textContent = `X ${this.cameraSnapshot.centerX.toFixed(1)} · Z ${this.cameraSnapshot.centerZ.toFixed(1)} · ${this.cameraSnapshot.nodeCount || 9} 节点`;
    for (const button of region.querySelectorAll<HTMLButtonElement>('button')) button.disabled = unavailable;
    region.dataset.zoom = String(this.cameraSnapshot.zoomPercent);
    region.dataset.atFit = this.cameraSnapshot.atFit ? 'true' : 'false';
    region.dataset.detail = this.cameraSnapshot.detailTier;
    region.dataset.expanded = this.cameraHudExpanded ? 'true' : 'false';
    region.dataset.idleDelay = String(CAMERA_HUD_REVEAL_MS);
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
    if (this.authorityBlocked) {
      region.hidden = false;
      region.dataset.state = 'blocked';
      region.innerHTML = '<b>战斗结果未知</b><span>战略态已冻结，不能继续结算；请点击右上角 × 关闭本面板。</span>';
      return;
    }
    if (this.handoffPending) {
      region.hidden = false;
      region.dataset.state = 'handoff';
      region.innerHTML = '<i class="warlord-authority-spinner" aria-hidden="true"></i><b>正在移交 AS2 真实战斗</b><span>战略态已冻结，等待 Launcher 精确关闭本窗口…</span>';
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
    const redAction = this.game.activeFactionId === 'red'
      && (this.game.phase === 'FIRST_FACTION_ACTION' || this.game.phase === 'SECOND_FACTION_ACTION');
    let tip: string | null = null;
    if (!this.coachDone && redAction && !this.playback && !this.handoffPending && !this.authorityBlocked) {
      if (this.coachCommandIssued) tip = '③ 按 E 或点击"结束红方行动"收束本回合';
      else if (this.selectedPieceIds.length === 0) tip = '① 点击己方棋子建立编组';
    }
    if (!tip) {
      region.hidden = true;
      region.textContent = '';
      return;
    }
    region.hidden = false;
    region.textContent = tip;
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
        chip.innerHTML = `<b>${escapeHtml(node.displayName)}</b><span>${escapeHtml(ownerLabel(node.ownerFactionId))} · 红 ${piecesAtNode(this.game, info.nodeId, 'red').length} · 蓝 ${piecesAtNode(this.game, info.nodeId, 'blue').length} · 容量 ${node.pieceIds.length}/${node.capacity}</span>`;
      } else {
        const piece = this.game.pieces[info.pieceId];
        if (!piece) {
          chip.hidden = true;
          return;
        }
        chip.innerHTML = `<b>${escapeHtml(getCardDefinition(piece.cardId).displayName)}</b><span>${factionLabel(piece.factionId)} · HP ${piece.hp}/${piece.maxHp}</span>`;
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
    const changed = next.seed !== this.init.seed || next.preset !== this.init.preset
      || next.difficulty !== this.init.difficulty || sceneModeChanged || themeChanged
      || next.battleAuthority !== this.init.battleAuthority;
    this.init = next;
    if (next.battleAuthority === 'as2' && next.resume) {
      const frozen = frozenStateFromAs2Resume(next.resume);
      if (frozen) this.game = frozen;
      this.authoritySessionId = sessionIdFromAs2Resume(next.resume)
        ?? this.authoritySessionId;
      this.aiSeenTransitions = new Set(next.aiSeenTransitions);
      this.handoffPending = true;
      this.authorityBlocked = frozen === null;
      this.playback = null;
      this.render();
      void this.consumeAs2Resume(next.resume);
      return;
    }
    if (!changed) {
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
    this.clearAutomation();
    this.clearCameraHudTimer();
    this.clearAuthorityAckTimer();
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
