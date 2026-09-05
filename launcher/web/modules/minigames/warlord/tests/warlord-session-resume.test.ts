import assert from 'node:assert/strict';
import test from 'node:test';
import type { WarlordInitData, WarlordSession } from '../src/app/warlord-session.js';
import {
  buildAs2BattleEnvelope,
  type As2BattleEnvelope,
  type As2ResumeEnvelope,
} from '../src/battle/as2-authority.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import type { GameState, MoveOrAttackCommand } from '../src/core/types.js';
import { getCardDefinition } from '../src/data/cards.js';
import {
  STAGE_OUTER_BINDING_SCHEMA,
  type StageOuterBindingV1,
  type StageOuterTerminalV1,
} from '../src/stage/outer-authority.js';
import { StageOuterSessionAuthority } from '../src/stage/session-authority.js';
import type { As2ResumeAppliedV1 } from '../src/stage/resume-apply.js';
import { clearAllPieces, makeState, setAction } from './helpers.js';

const BINDING: StageOuterBindingV1 = {
  schema: STAGE_OUTER_BINDING_SCHEMA,
  runId: 'run.resume.commit.1',
  subStageId: 'sub.resume.commit.1',
  scenarioRef: 'warlord_tutorial_v1',
  callId: 'call.resume.commit.1',
  revision: 1,
};

interface SessionCounters {
  render: number;
  playback: number;
  settledPlayback: number;
  transitions: number;
}

interface SessionHarness {
  readonly session: WarlordSession & Record<string, unknown>;
  readonly counters: SessionCounters;
}

type WarlordSessionConstructor = typeof import('../src/app/warlord-session.js').WarlordSession;

// The test compiler intentionally does not duplicate the audited Three.js
// vendor tree under .test-dist. Load the already-built runtime module whose
// relative vendor import resolves through the normal product layout.
const runtimeUrl = new URL('../../runtime/app/warlord-session.js', import.meta.url);
const runtime = await import(runtimeUrl.href) as { WarlordSession: WarlordSessionConstructor };
const WarlordSessionRuntime = runtime.WarlordSession;

function battleFixture(seed = 'session-resume-exact-once'): {
  state: GameState;
  command: MoveOrAttackCommand;
} {
  const state = makeState(seed);
  clearAllPieces(state);
  createPieceInPlace(state, 'red', 12, 'R-Supply', 1, { pieceId: 'pet-red-12' });
  createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'pet-blue-15' });
  setAction(state, 'red', 4);
  return {
    state,
    command: {
      type: 'MOVE_OR_ATTACK',
      factionId: 'red',
      pieceIds: ['pet-red-12'],
      originNodeId: 'R-Supply',
      targetNodeId: 'North-Choke',
    },
  };
}

async function envelopeFixture(seed?: string): Promise<As2BattleEnvelope> {
  const { state, command } = battleFixture(seed);
  return buildAs2BattleEnvelope({
    panelInstanceId: 'warlord.panel.resume-commit',
    callId: 'warlord.call.resume-commit',
    sessionId: 'warlord.session.resume-commit',
    requestId: 'warlord.request.resume-commit',
    state,
    command,
    clientContext: {
      seed: state.gameSeed,
      preset: state.preset,
      difficulty: state.difficulty,
      mapTheme: 'desert',
      forceWebglFailure: false,
      aiSeenTransitions: [],
    },
  });
}

function acceptedResume(envelope: As2BattleEnvelope): As2ResumeEnvelope {
  const attackerDefinition = getCardDefinition(12);
  const defenderDefinition = getCardDefinition(15);
  return {
    schema: 'warlord.as2-resume.v1',
    request: structuredClone(envelope.request),
    state: structuredClone(envelope.request.state),
    command: structuredClone(envelope.request.command),
    inputDigest: envelope.inputDigest,
    clientContext: structuredClone(envelope.request.clientContext),
    receipt: {
      schema: 'warlord.as2-battle-receipt.v2',
      status: 'accepted',
      sessionId: envelope.request.sessionId,
      requestId: envelope.request.requestId,
      inputDigest: envelope.inputDigest,
      petProjectionProfile: 'catalog_identifier+strategic_progression_v1',
      playerPetSnapshotUsed: false,
      participantProjectionProfile: 'discriminated_player_avatar+catalog_pet_v1',
      playerAvatarProjectionProfile: 'trusted_demo2_commander_v1',
      playerPersistentSnapshotUsed: false,
      playerControlledSide: 'none',
      as2Status: 'finished',
      as2Winner: 'blue',
      sideMap: { blue: 'attacker', red: 'defender' },
      frames: 180,
      durationMs: 6000,
      attackerUnits: [{
        pieceId: 'pet-red-12',
        factionId: 'red',
        projectionKind: 'pet_projection',
        petId: 12,
        identifier: attackerDefinition.identifier,
        level: 1,
        strategicPromotions: [],
        resolvedType: attackerDefinition.identifier,
        startMaxHp: 1000,
        remainHp: 625,
        hpPermille: 625,
        alive: true,
      }],
      defenderUnits: [{
        pieceId: 'pet-blue-15',
        factionId: 'blue',
        projectionKind: 'pet_projection',
        petId: 15,
        identifier: defenderDefinition.identifier,
        level: 1,
        strategicPromotions: [],
        resolvedType: defenderDefinition.identifier,
        startMaxHp: 1000,
        remainHp: 0,
        hpPermille: 0,
        alive: false,
      }],
      economyObservation: {
        schema: 'warlord.pet-economy-observation.v1',
        mode: 'observe_only',
        writesPlayerState: false,
        settlementPolicy: 'none',
        catalogAuthority: 'data/merc/pets.xml',
        catalogPriceBasis: 'xml_base_price',
        currentAs2SessionPriceSampled: false,
        strategicValueBasis: 'piece.productionGoldValue',
        catalogCurrencyUnit: 'player_gold',
        strategicCurrencyUnit: 'warlord_gold',
        attacker: {
          catalogBaseExposureGold: 8000,
          catalogBaseLostGold: 0,
          catalogBaseExposureK: 0,
          catalogBaseLostK: 0,
          strategicExposureGold: 8,
          strategicLostGold: 0,
          units: [{
            pieceId: 'pet-red-12',
            projectionKind: 'pet_projection',
            petId: 12,
            identifier: attackerDefinition.identifier,
            catalogName: attackerDefinition.displayName,
            rosterType: 'pet',
            catalogEligible: true,
            strategicPromotions: [],
            strategicGoldValue: 8,
            basePrice: 8000,
            kPrice: 0,
            increasePrice: 0,
            hpPermille: 625,
            lost: false,
          }],
        },
        defender: {
          catalogBaseExposureGold: 10000,
          catalogBaseLostGold: 10000,
          catalogBaseExposureK: 0,
          catalogBaseLostK: 0,
          strategicExposureGold: 60,
          strategicLostGold: 60,
          units: [{
            pieceId: 'pet-blue-15',
            projectionKind: 'pet_projection',
            petId: 15,
            identifier: defenderDefinition.identifier,
            catalogName: defenderDefinition.displayName,
            rosterType: 'pet',
            catalogEligible: true,
            strategicPromotions: [],
            strategicGoldValue: 60,
            basePrice: 10000,
            kPrice: 0,
            increasePrice: 0,
            hpPermille: 0,
            lost: true,
          }],
        },
      },
    },
  };
}

function stageInit(
  resume: As2ResumeEnvelope,
  binding: StageOuterBindingV1,
  resumeAppliedSend: (receipt: As2ResumeAppliedV1) => boolean,
): WarlordInitData {
  return {
    source: 'game_stage',
    mode: 'stage-v1',
    seed: resume.state.gameSeed,
    preset: resume.state.preset,
    difficulty: resume.state.difficulty,
    scenarioRef: binding.scenarioRef,
    panelInstanceId: 'warlord.panel.resume-commit',
    forceWebglFailure: false,
    mapTheme: 'desert',
    battleAuthority: 'as2',
    as2BattleSession: true,
    aiSeenTransitions: [],
    resume,
    stageOuterBinding: binding,
    playerAvatarPortrait: null,
    stageTerminalSend: (_terminal: StageOuterTerminalV1) => true,
    resumeAppliedSend,
  };
}

function bareSession(
  resume: As2ResumeEnvelope,
  binding: StageOuterBindingV1,
  resumeAppliedSend: (receipt: As2ResumeAppliedV1) => boolean,
): SessionHarness {
  // The production constructor owns Three/DOM resources. These tests exercise the
  // real resume/rebind methods while replacing only presentation side effects.
  const session = Object.create(WarlordSessionRuntime.prototype) as WarlordSession & Record<string, unknown>;
  const init = stageInit(resume, binding, resumeAppliedSend) as Record<string, unknown>;
  const counters: SessionCounters = {
    render: 0,
    playback: 0,
    settledPlayback: 0,
    transitions: 0,
  };
  Object.assign(session, {
    init,
    game: structuredClone(resume.state),
    selectedNodeId: 'R-Supply',
    selectedPieceIds: [],
    playback: null,
    disposed: false,
    mapTheme: 'desert',
    themeDraft: 'desert',
    seedDraft: resume.state.gameSeed,
    presetDraft: resume.state.preset,
    difficultyDraft: resume.state.difficulty,
    aiCameraLease: null,
    aiSeenTransitions: new Set<string>(),
    handoffPending: true,
    authorityBlocked: false,
    authorityReturnOnly: false,
    authoritySessionId: resume.request.sessionId,
    pendingBattleCallId: null,
    pendingBattleCommand: null,
    pendingBattleIdentity: null,
    authorityAckTimer: null,
    resumeCommitSlot: null,
    noticeText: '',
    noticeTone: 'info',
    toastSerial: 0,
    stageAuthority: new StageOuterSessionAuthority({
      ...init,
      stageOuterBinding: binding,
      stageTerminalSend: (_terminal: StageOuterTerminalV1) => true,
    } as never),
    render: () => { counters.render += 1; },
    renderLiveRegion: () => {},
    openBattle: (_record: unknown, settled: boolean) => {
      counters.playback += 1;
      if (settled) counters.settledPlayback += 1;
    },
    rememberAppliedTransitions: () => { counters.transitions += 1; },
    advanceStageCloseGeneration: () => {},
    clearAutomation: () => {},
  });
  return { session, counters };
}

async function consume(session: SessionHarness['session'], resume: As2ResumeEnvelope): Promise<void> {
  await (session as unknown as {
    consumeAs2Resume(value: As2ResumeEnvelope): Promise<void>;
  }).consumeAs2Resume(resume);
}

test('exact resume rebind re-acks without replacing the once-committed strategic state', async () => {
  const resume = acceptedResume(await envelopeFixture());
  const acknowledgements: As2ResumeAppliedV1[] = [];
  const harness = bareSession(resume, BINDING, (receipt) => {
    acknowledgements.push(structuredClone(receipt));
    return true;
  });

  await consume(harness.session, resume);
  const committedState = harness.session.getState();
  assert.equal(committedState.battles.length, 1);
  assert.equal(harness.counters.playback, 1);
  assert.equal(harness.counters.settledPlayback, 1);

  harness.session.rebind(stageInit(resume, BINDING, (receipt) => {
    acknowledgements.push(structuredClone(receipt));
    return true;
  }));

  assert.equal(harness.session.getState(), committedState);
  assert.equal(harness.session.getState().battles.length, 1);
  assert.equal(harness.counters.playback, 1);
  assert.equal(harness.counters.settledPlayback, 1);
  assert.equal(harness.counters.transitions, 1);
  assert.equal(acknowledgements.length, 2);
  assert.deepEqual(acknowledgements[1], acknowledgements[0]);
});

test('恢复结果结算释放隐藏沙盘，并直接停在可关闭的最终帧', async () => {
  const resume = acceptedResume(await envelopeFixture('session-resume-static-settlement'));
  const harness = bareSession(resume, BINDING, () => true);
  await consume(harness.session, resume);
  const state = harness.session.getState();
  const record = state.battles[0];
  assert.ok(record);

  let disposedScenes = 0;
  const session = Object.create(WarlordSessionRuntime.prototype) as WarlordSession & Record<string, unknown>;
  Object.assign(session, {
    game: state,
    playback: null,
    scene: { dispose: () => { disposedScenes += 1; } },
  });
  (session as unknown as {
    openBattle(value: typeof record, settled: boolean): void;
  }).openBattle(record, true);

  const playback = (session as unknown as { playback: {
    index: number;
    paused: boolean;
  } }).playback;
  assert.equal(disposedScenes, 1);
  assert.equal((session as unknown as { scene: unknown }).scene, null);
  assert.equal(playback.index, record.result.eventLog.length);
  assert.equal(playback.paused, true);
});

test('failed resume-applied delivery retries the exact acknowledgement without replaying commit', async () => {
  const resume = acceptedResume(await envelopeFixture('session-resume-ack-retry'));
  const acknowledgements: As2ResumeAppliedV1[] = [];
  let attempt = 0;
  const send = (receipt: As2ResumeAppliedV1): boolean => {
    attempt += 1;
    acknowledgements.push(structuredClone(receipt));
    return attempt > 1;
  };
  const harness = bareSession(resume, BINDING, send);

  await consume(harness.session, resume);
  const committedState = harness.session.getState();
  assert.equal((harness.session as unknown as { authorityBlocked: boolean }).authorityBlocked, true);

  harness.session.rebind(stageInit(resume, BINDING, send));

  assert.equal(attempt, 2);
  assert.deepEqual(acknowledgements[1], acknowledgements[0]);
  assert.equal(harness.session.getState(), committedState);
  assert.equal(harness.session.getState().battles.length, 1);
  assert.equal((harness.session as unknown as { authorityBlocked: boolean }).authorityBlocked, false);
});

test('same identity with a different proof fails closed without replacing committed state', async () => {
  const resume = acceptedResume(await envelopeFixture('session-resume-proof-conflict'));
  const acknowledgements: As2ResumeAppliedV1[] = [];
  const harness = bareSession(resume, BINDING, (receipt) => {
    acknowledgements.push(structuredClone(receipt));
    return true;
  });
  await consume(harness.session, resume);
  const committedState = harness.session.getState();
  const conflicting = structuredClone(resume);
  (conflicting.receipt as Record<string, unknown>).durationMs = 6001;

  harness.session.rebind(stageInit(conflicting, BINDING, (receipt) => {
    acknowledgements.push(structuredClone(receipt));
    return true;
  }));

  assert.equal(harness.session.getState(), committedState);
  assert.equal(harness.session.getState().battles.length, 1);
  assert.equal(harness.counters.playback, 1);
  assert.equal(acknowledgements.length, 1);
  assert.equal((harness.session as unknown as { authorityBlocked: boolean }).authorityBlocked, true);
  assert.equal((harness.session as unknown as { authorityReturnOnly: boolean }).authorityReturnOnly, true);
});

test('same proof under a different outer stage context fails closed', async () => {
  const resume = acceptedResume(await envelopeFixture('session-resume-stage-conflict'));
  const acknowledgements: As2ResumeAppliedV1[] = [];
  const harness = bareSession(resume, BINDING, (receipt) => {
    acknowledgements.push(structuredClone(receipt));
    return true;
  });
  await consume(harness.session, resume);
  const committedState = harness.session.getState();
  const nextBinding: StageOuterBindingV1 = {
    ...BINDING,
    callId: 'call.resume.commit.2',
    revision: 2,
  };

  harness.session.rebind(stageInit(resume, nextBinding, (receipt) => {
    acknowledgements.push(structuredClone(receipt));
    return true;
  }));

  assert.equal(harness.session.getState(), committedState);
  assert.equal(harness.session.getState().battles.length, 1);
  assert.equal(harness.counters.playback, 1);
  assert.equal(acknowledgements.length, 1);
  assert.equal((harness.session as unknown as { authorityBlocked: boolean }).authorityBlocked, true);
  assert.equal((harness.session as unknown as { authorityReturnOnly: boolean }).authorityReturnOnly, true);
});

function bareDispatchSession(
  bridgeSend: (envelope: As2BattleEnvelope) => boolean,
): { session: WarlordSession & Record<string, unknown>; command: MoveOrAttackCommand } {
  const { state, command } = battleFixture('session-sync-prepared');
  const session = Object.create(WarlordSessionRuntime.prototype) as WarlordSession & Record<string, unknown>;
  Object.assign(session, {
    init: {
      panelInstanceId: 'warlord.panel.sync-prepared',
      forceWebglFailure: false,
      bridgeSend,
    },
    game: state,
    disposed: false,
    mapTheme: 'desert',
    aiSeenTransitions: new Set<string>(),
    handoffPending: false,
    authorityBlocked: false,
    authorityReturnOnly: false,
    authoritySessionId: 'warlord.session.sync-prepared',
    pendingBattleCallId: null,
    pendingBattleCommand: null,
    pendingBattleIdentity: null,
    authorityAckTimer: null,
    resumeCommitSlot: null,
    noticeText: '',
    noticeTone: 'info',
    toastSerial: 0,
    render: () => {},
    renderLiveRegion: () => {},
  });
  return { session, command };
}

test('synchronous prepared callback wins over the bridge return and cancels the wait timer', async () => {
  const previousWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  let nextTimerId = 0;
  const liveTimers = new Map<number, () => void>();
  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      setTimeout(callback: () => void): number {
        nextTimerId += 1;
        liveTimers.set(nextTimerId, callback);
        return nextTimerId;
      },
      clearTimeout(timerId: number): void {
        liveTimers.delete(timerId);
      },
    },
  });
  try {
    let callbackAccepted = false;
    let harness: ReturnType<typeof bareDispatchSession>;
    harness = bareDispatchSession((envelope) => {
      callbackAccepted = harness.session.handleHostResponse({
        type: 'panel_resp',
        panel: 'warlord',
        cmd: 'battle_start',
        callId: envelope.callId,
        success: true,
        ok: true,
      });
      // A synchronous Host callback is stronger evidence than the facade's stale
      // boolean return; it must not be undone after the callback returns.
      return false;
    });

    await (harness.session as unknown as {
      beginAs2Battle(command: MoveOrAttackCommand): Promise<void>;
    }).beginAs2Battle(harness.command);

    assert.equal(callbackAccepted, true);
    assert.equal((harness.session as unknown as { handoffPending: boolean }).handoffPending, true);
    assert.equal((harness.session as unknown as { authorityBlocked: boolean }).authorityBlocked, false);
    assert.equal((harness.session as unknown as { authorityAckTimer: number | null }).authorityAckTimer, null);
    assert.equal(liveTimers.size, 0);
  } finally {
    if (previousWindow) Object.defineProperty(globalThis, 'window', previousWindow);
    else Reflect.deleteProperty(globalThis, 'window');
  }
});

function bareLifecycleSession(state: GameState): WarlordSession & Record<string, unknown> {
  const session = Object.create(WarlordSessionRuntime.prototype) as WarlordSession & Record<string, unknown>;
  Object.assign(session, {
    init: { battleAuthority: 'as2' },
    game: state,
    playback: null,
    disposed: false,
    aiSeenTransitions: new Set<string>([
      'old-piece:A->B',
      'old-piece:B->C',
    ]),
    handoffPending: false,
    authorityBlocked: false,
    authorityReturnOnly: false,
    pendingBattleCallId: null,
    pendingBattleCommand: null,
    pendingBattleIdentity: null,
    pendingBattlePrepared: false,
    authorityAckTimer: null,
    resumeCommitSlot: null,
    noticeText: '',
    noticeTone: 'info',
    toastSerial: 0,
    stageAuthority: { blocksGameplay: false, status: 'active' },
    render: () => {},
  });
  return session;
}

test('成功 END_ACTION 后清空跨行动 AI seen，失败命令不提前清空', () => {
  const state = makeState('session-ai-seen-end-action');
  setAction(state, 'red', 4);
  state.activeTurnIndex = state.turnOrder.indexOf('red');
  const session = bareLifecycleSession(state);
  const dispatch = (command: { type: 'END_ACTION'; factionId: string }): boolean => (
    session as unknown as {
      dispatch(value: { type: 'END_ACTION'; factionId: string }): boolean;
    }
  ).dispatch(command);

  assert.equal(dispatch({ type: 'END_ACTION', factionId: 'blue' }), false);
  assert.equal((session as unknown as { aiSeenTransitions: Set<string> }).aiSeenTransitions.size, 2);
  assert.equal(dispatch({ type: 'END_ACTION', factionId: 'red' }), true);
  assert.equal((session as unknown as { aiSeenTransitions: Set<string> }).aiSeenTransitions.size, 0);
});

test('AS2 known-not-started 收束 AI 行动后清空跨行动 AI seen', () => {
  const state = makeState('session-ai-seen-known-not-started');
  clearAllPieces(state);
  createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'seen-blue' });
  createPieceInPlace(state, 'red', 12, 'R-Supply', 1, { pieceId: 'seen-red' });
  setAction(state, 'blue', 4);
  state.activeTurnIndex = state.turnOrder.indexOf('blue');
  const session = bareLifecycleSession(state);
  const command: MoveOrAttackCommand = {
    type: 'MOVE_OR_ATTACK',
    factionId: 'blue',
    pieceIds: ['seen-blue'],
    originNodeId: 'North-Choke',
    targetNodeId: 'R-Supply',
  };

  (session as unknown as {
    recoverFromDefinitiveAs2BattleFailure(
      value: MoveOrAttackCommand,
      playerNotice: string,
      aiNotice: string,
    ): void;
  }).recoverFromDefinitiveAs2BattleFailure(command, '玩家提示', 'AI 提示');

  assert.equal((session as unknown as { aiSeenTransitions: Set<string> }).aiSeenTransitions.size, 0);
  assert.equal(session.getState().commandHistory.at(-1)?.command.type, 'END_ACTION');
  assert.equal(session.getState().phase, 'SETTLEMENT_PLANNING');
});
