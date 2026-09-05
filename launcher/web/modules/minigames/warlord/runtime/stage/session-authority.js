import { applyStageOuterEvent, createStageOuterAuthorityState, parseStageOuterBinding, STAGE_OUTER_TERMINAL_SCHEMA, } from './outer-authority.js';
export const STAGE_MODE_SOURCE = 'game_stage';
export const STAGE_MODE_VERSION = 'stage-v1';
export const STAGE_PLAYER_FACTION = 'red';
function bindingKey(binding) {
    return [
        binding.runId,
        binding.subStageId,
        binding.scenarioRef,
        binding.callId,
        String(binding.revision),
    ].join('\u0000');
}
function sameBinding(left, right) {
    return left !== null && bindingKey(left) === bindingKey(right);
}
export class StageOuterSessionAuthority {
    generation = 0;
    disposed = false;
    active = false;
    blocked = false;
    binding = null;
    authorityState = null;
    send = null;
    automaticCloseRequest = null;
    automaticCloseRequested = false;
    delivery = 'none';
    constructor(init) {
        this.rebind(init);
    }
    rebind(init) {
        const previousContext = this.contextIdentity;
        this.generation += 1;
        if (this.disposed)
            return Object.freeze({ contextChanged: false });
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
    get status() {
        if (this.disposed)
            return 'disposed';
        if (!this.active)
            return 'inactive';
        if (this.blocked || this.binding === null || this.authorityState === null || this.send === null) {
            return 'blocked';
        }
        if (this.authorityState.phase === 'awaiting_terminal')
            return 'awaiting_terminal';
        return this.delivery === 'sent' ? 'terminal_sent' : 'terminal_failed';
    }
    get contextIdentity() {
        if (this.disposed)
            return 'disposed';
        if (!this.active)
            return 'inactive';
        if (this.blocked || this.binding === null)
            return 'blocked';
        return `stage:${bindingKey(this.binding)}`;
    }
    get isStageMode() {
        return this.active;
    }
    get blocksGameplay() {
        return this.status === 'blocked'
            || this.status === 'terminal_sent'
            || this.status === 'terminal_failed';
    }
    get terminal() {
        return this.authorityState?.phase === 'terminal' ? this.authorityState.terminal : null;
    }
    emitTerminal(terminal, reasonCode) {
        if (this.disposed)
            return 'stale';
        if (!this.active)
            return 'inactive';
        if (this.status === 'blocked'
            || this.binding === null
            || this.authorityState === null
            || this.send === null)
            return 'blocked';
        const envelope = Object.freeze({
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
            }
            catch {
                delivered = false;
            }
            if (this.disposed || localGeneration !== this.generation)
                return 'stale';
            this.delivery = delivered ? 'sent' : 'failed';
            return delivered ? 'duplicate' : 'blocked';
        }
        if (applied.disposition !== 'accepted')
            return 'blocked';
        this.authorityState = applied.state;
        this.delivery = 'attempted';
        const localGeneration = this.generation;
        let delivered = false;
        try {
            delivered = this.send(envelope) === true;
        }
        catch {
            delivered = false;
        }
        if (this.disposed || localGeneration !== this.generation)
            return 'stale';
        this.delivery = delivered ? 'sent' : 'failed';
        return delivered ? 'sent' : 'blocked';
    }
    emitGameOver(winner, playerFactionId = STAGE_PLAYER_FACTION, winningVictoryGroupId = null, playerVictoryGroupId = null) {
        const playerWon = winningVictoryGroupId !== null && playerVictoryGroupId !== null
            ? winningVictoryGroupId === playerVictoryGroupId
            : winner === playerFactionId;
        const emitted = playerWon
            ? this.emitTerminal('CompleteSubStage', 'warlord.stage.player-victory')
            : this.emitTerminal('FailStage', 'warlord.stage.rule-terminal-failure');
        this.requestAutomaticClose(emitted);
        return emitted;
    }
    emitTechnicalUnknown() {
        const emitted = this.emitTerminal('Unknown', 'warlord.stage.technical-unknown');
        this.requestAutomaticClose(emitted);
        return emitted;
    }
    requestAutomaticClose(emitted) {
        if ((emitted !== 'sent' && emitted !== 'duplicate')
            || this.automaticCloseRequested
            || this.automaticCloseRequest === null)
            return;
        this.automaticCloseRequested = true;
        this.automaticCloseRequest();
    }
    prepareUserClose() {
        if (!this.active)
            return Object.freeze({ handled: false, ready: false });
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
    prepareActionResultUnknownClose() {
        if (!this.active)
            return Object.freeze({ handled: false, ready: false });
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
        const emitted = this.emitTerminal('Unknown', 'warlord.stage.action-result-unknown');
        return Object.freeze({
            handled: true,
            ready: emitted === 'sent' || emitted === 'duplicate',
        });
    }
    dispose() {
        if (this.disposed)
            return;
        this.generation += 1;
        this.disposed = true;
        this.send = null;
        this.automaticCloseRequest = null;
    }
}
//# sourceMappingURL=session-authority.js.map