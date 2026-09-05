import {
  applyStageOuterEvent,
  createStageOuterAuthorityState,
  parseStageOuterBinding,
  STAGE_OUTER_TERMINAL_SCHEMA,
  type StageOuterAuthorityState,
  type StageOuterBindingV1,
  type StageOuterTerminalKind,
  type StageOuterTerminalV1,
} from './outer-authority.js';

export const STAGE_MODE_SOURCE = 'game_stage' as const;
export const STAGE_MODE_VERSION = 'stage-v1' as const;
export const STAGE_PLAYER_FACTION = 'red' as const;

export type StageTerminalSend = (terminal: StageOuterTerminalV1) => boolean;

export interface StageOuterSessionInit {
  readonly source: string;
  readonly mode: string;
  readonly stageOuterBinding: unknown;
  readonly stageTerminalSend: StageTerminalSend | null;
  readonly stageAutomaticCloseRequest?: (() => void) | null;
}

export type StageOuterSessionStatus =
  | 'inactive'
  | 'blocked'
  | 'awaiting_terminal'
  | 'terminal_sent'
  | 'terminal_failed'
  | 'disposed';

export type StageTerminalEmitResult =
  | 'sent'
  | 'duplicate'
  | 'inactive'
  | 'blocked'
  | 'conflict'
  | 'stale';

export type StageClosePreparation =
  | { readonly handled: false; readonly ready: false }
  | { readonly handled: true; readonly ready: true }
  | { readonly handled: true; readonly ready: false };

function bindingKey(binding: StageOuterBindingV1): string {
  return [
    binding.runId,
    binding.subStageId,
    binding.scenarioRef,
    binding.callId,
    String(binding.revision),
  ].join('\u0000');
}

function sameBinding(left: StageOuterBindingV1 | null, right: StageOuterBindingV1): boolean {
  return left !== null && bindingKey(left) === bindingKey(right);
}

export class StageOuterSessionAuthority {
  private generation = 0;
  private disposed = false;
  private active = false;
  private blocked = false;
  private binding: StageOuterBindingV1 | null = null;
  private authorityState: StageOuterAuthorityState | null = null;
  private send: StageTerminalSend | null = null;
  private automaticCloseRequest: (() => void) | null = null;
  private automaticCloseRequested = false;
  private delivery: 'none' | 'attempted' | 'sent' | 'failed' = 'none';

  public constructor(init: StageOuterSessionInit) {
    this.rebind(init);
  }

  public rebind(init: StageOuterSessionInit): { readonly contextChanged: boolean } {
    const previousContext = this.contextIdentity;
    this.generation += 1;
    if (this.disposed) return Object.freeze({ contextChanged: false });
    this.automaticCloseRequest = init.stageAutomaticCloseRequest ?? null;
    this.automaticCloseRequested = false;

    const enabled = init.source === STAGE_MODE_SOURCE && init.mode === STAGE_MODE_VERSION;
    if (!enabled) {
      this.active = false;
      this.blocked = false;
      this.binding = null;
      this.authorityState = null;
      this.send = null;
      this.automaticCloseRequest = null;
      this.delivery = 'none';
      return Object.freeze({ contextChanged: previousContext !== this.contextIdentity });
    }

    this.active = true;
    const parsed = parseStageOuterBinding(init.stageOuterBinding);
    if (!parsed.ok || init.stageTerminalSend === null) {
      this.blocked = true;
      this.binding = null;
      this.authorityState = null;
      this.send = null;
      this.delivery = 'none';
      return Object.freeze({ contextChanged: previousContext !== this.contextIdentity });
    }

    this.blocked = false;
    this.send = init.stageTerminalSend;
    if (!sameBinding(this.binding, parsed.value)) {
      const created = createStageOuterAuthorityState(parsed.value);
      if (!created.ok) {
        this.blocked = true;
        this.binding = null;
        this.authorityState = null;
        this.send = null;
        this.delivery = 'none';
        return Object.freeze({ contextChanged: previousContext !== this.contextIdentity });
      }
      this.binding = parsed.value;
      this.authorityState = created.value;
      this.delivery = 'none';
    }
    return Object.freeze({ contextChanged: previousContext !== this.contextIdentity });
  }

  public get status(): StageOuterSessionStatus {
    if (this.disposed) return 'disposed';
    if (!this.active) return 'inactive';
    if (this.blocked || this.binding === null || this.authorityState === null || this.send === null) {
      return 'blocked';
    }
    if (this.authorityState.phase === 'awaiting_terminal') return 'awaiting_terminal';
    return this.delivery === 'sent' ? 'terminal_sent' : 'terminal_failed';
  }

  public get contextIdentity(): string {
    if (this.disposed) return 'disposed';
    if (!this.active) return 'inactive';
    if (this.blocked || this.binding === null) return 'blocked';
    return `stage:${bindingKey(this.binding)}`;
  }

  public get isStageMode(): boolean {
    return this.active;
  }

  public get blocksGameplay(): boolean {
    return this.status === 'blocked'
      || this.status === 'terminal_sent'
      || this.status === 'terminal_failed';
  }

  public get terminal(): StageOuterTerminalV1 | null {
    return this.authorityState?.phase === 'terminal' ? this.authorityState.terminal : null;
  }

  public emitTerminal(
    terminal: StageOuterTerminalKind,
    reasonCode: string,
  ): StageTerminalEmitResult {
    if (this.disposed) return 'stale';
    if (!this.active) return 'inactive';
    if (this.status === 'blocked'
      || this.binding === null
      || this.authorityState === null
      || this.send === null) return 'blocked';

    const envelope: StageOuterTerminalV1 = Object.freeze({
      schema: STAGE_OUTER_TERMINAL_SCHEMA,
      runId: this.binding.runId,
      subStageId: this.binding.subStageId,
      scenarioRef: this.binding.scenarioRef,
      callId: this.binding.callId,
      revision: this.binding.revision,
      terminal,
      reasonCode,
    });
    const applied = applyStageOuterEvent(this.authorityState, envelope);
    if (!applied.ok) {
      return applied.reasonCode === 'terminal_conflict' ? 'conflict'
        : applied.reasonCode === 'late_event' ? 'stale' : 'blocked';
    }
    if (applied.disposition === 'duplicate') {
      const localGeneration = this.generation;
      this.delivery = 'attempted';
      let delivered = false;
      try {
        delivered = this.send(applied.terminal) === true;
      } catch {
        delivered = false;
      }
      if (this.disposed || localGeneration !== this.generation) return 'stale';
      this.delivery = delivered ? 'sent' : 'failed';
      return delivered ? 'duplicate' : 'blocked';
    }
    if (applied.disposition !== 'accepted') return 'blocked';

    this.authorityState = applied.state;
    this.delivery = 'attempted';
    const localGeneration = this.generation;
    let delivered = false;
    try {
      delivered = this.send(envelope) === true;
    } catch {
      delivered = false;
    }
    if (this.disposed || localGeneration !== this.generation) return 'stale';
    this.delivery = delivered ? 'sent' : 'failed';
    return delivered ? 'sent' : 'blocked';
  }

  public emitGameOver(
    winner: string,
    playerFactionId: string = STAGE_PLAYER_FACTION,
    winningVictoryGroupId: string | null = null,
    playerVictoryGroupId: string | null = null,
  ): StageTerminalEmitResult {
    const playerWon = winningVictoryGroupId !== null && playerVictoryGroupId !== null
      ? winningVictoryGroupId === playerVictoryGroupId
      : winner === playerFactionId;
    const emitted = playerWon
      ? this.emitTerminal('CompleteSubStage', 'warlord.stage.player-victory')
      : this.emitTerminal('FailStage', 'warlord.stage.rule-terminal-failure');
    this.requestAutomaticClose(emitted);
    return emitted;
  }

  public emitTechnicalUnknown(): StageTerminalEmitResult {
    const emitted = this.emitTerminal('Unknown', 'warlord.stage.technical-unknown');
    this.requestAutomaticClose(emitted);
    return emitted;
  }

  private requestAutomaticClose(emitted: StageTerminalEmitResult): void {
    if ((emitted !== 'sent' && emitted !== 'duplicate')
      || this.automaticCloseRequested
      || this.automaticCloseRequest === null) return;
    this.automaticCloseRequested = true;
    this.automaticCloseRequest();
  }

  public prepareUserClose(): StageClosePreparation {
    if (!this.active) return Object.freeze({ handled: false, ready: false });
    if (this.status === 'blocked' || this.status === 'disposed') {
      return Object.freeze({ handled: true, ready: false });
    }
    if (this.authorityState?.phase === 'terminal') {
      return Object.freeze({ handled: true, ready: this.delivery === 'sent' });
    }
    const emitted = this.emitTerminal('Suspended', 'warlord.stage.user-close');
    return Object.freeze({
      handled: true,
      ready: emitted === 'sent' || emitted === 'duplicate',
    });
  }

  /**
   * Action 结果已经成为 Unknown 时，关闭只能把外层也冻结为不可重开终态。
   * 重发同一战略 checkpoint 无法凭空恢复缺失的战斗 receipt，只允许随后整关返回。
   */
  public prepareActionResultUnknownClose(): StageClosePreparation {
    if (!this.active) return Object.freeze({ handled: false, ready: false });
    if (this.status === 'blocked' || this.status === 'disposed') {
      return Object.freeze({ handled: true, ready: false });
    }
    if (this.authorityState?.phase === 'terminal') {
      const frozen = this.authorityState.terminal;
      const emitted = this.emitTerminal(frozen.terminal, frozen.reasonCode);
      return Object.freeze({
        handled: true,
        ready: emitted === 'sent' || emitted === 'duplicate',
      });
    }
    const emitted = this.emitTerminal(
      'Unknown',
      'warlord.stage.action-result-unknown',
    );
    return Object.freeze({
      handled: true,
      ready: emitted === 'sent' || emitted === 'duplicate',
    });
  }

  public dispose(): void {
    if (this.disposed) return;
    this.generation += 1;
    this.disposed = true;
    this.send = null;
    this.automaticCloseRequest = null;
  }
}
