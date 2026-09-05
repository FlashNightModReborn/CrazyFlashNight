import { runAiActionPhase, runAiPlanning } from '../ai/heuristic.js';
import { requireFaction } from '../core/factions.js';
import { createGame } from '../core/state.js';
import { CARD_IDS } from '../data/cards.js';
import { AI_POLICY_VERSION, TUNING_VERSION } from '../data/config.js';
import { makeReplay } from '../replay/replay.js';
function deployedCount(state, factionId) {
    return Object.values(state.pieces).filter((piece) => piece.factionId === factionId).length;
}
function canRebuild(state, factionId) {
    const faction = requireFaction(state, factionId);
    const queueExists = Object.values(faction.productionQueues).some((slots) => slots?.some((slot) => slot.orders.length > 0));
    const productionNodeExists = Object.values(state.map.nodes).some((node) => {
        return node.ownerFactionId === factionId && node.productionSlots > 0 && node.activeFromRound !== null && node.activeFromRound <= state.strategicRound;
    });
    return queueExists || productionNodeExists;
}
export function runSingleSimulation(seed, difficulty = 'normal', preset = 'standard', compactLogs = false) {
    let state = createGame({ seed, difficulty, preset });
    let invalidCommands = 0;
    let guard = 0;
    const wipedWithRebuildPotential = Object.fromEntries(state.turnOrder.map((factionId) => [factionId, false]));
    const rebuilds = Object.fromEntries(state.turnOrder.map((factionId) => [factionId, 0]));
    const telemetry = {
        battleCount: 0,
        battleRounds: 0,
        battleRoundLimits: 0,
        suppressions: 0,
        sniperVolleyDamage: 0,
        totalDamage: 0,
    };
    let observedBattleCount = 0;
    const collectTelemetry = () => {
        const newBattles = state.battles.slice(observedBattleCount);
        for (const battle of newBattles) {
            telemetry.battleCount += 1;
            telemetry.battleRounds += battle.result.battleRounds;
            if (battle.result.reason === 'battle_round_limit')
                telemetry.battleRoundLimits += 1;
            for (const event of battle.result.eventLog) {
                if (event.type === 'suppression')
                    telemetry.suppressions += 1;
                if (event.damage) {
                    telemetry.totalDamage += event.damage;
                    if (event.phase === 'opening_volley')
                        telemetry.sniperVolleyDamage += event.damage;
                }
            }
        }
        if (compactLogs) {
            state.battles = [];
            state.eventLog = [];
            state.commandHistory = [];
            state.casualtyLedger = state.casualtyLedger.filter((entry) => !entry.settled);
            observedBattleCount = 0;
        }
        else {
            observedBattleCount = state.battles.length;
        }
    };
    while (!state.result && guard < 5_000) {
        guard += 1;
        for (const factionId of state.turnOrder) {
            const count = deployedCount(state, factionId);
            if (count === 0 && canRebuild(state, factionId))
                wipedWithRebuildPotential[factionId] = true;
            if (count > 0 && wipedWithRebuildPotential[factionId]) {
                rebuilds[factionId] = (rebuilds[factionId] ?? 0) + 1;
                wipedWithRebuildPotential[factionId] = false;
            }
        }
        if (state.phase === 'FIRST_FACTION_ACTION' || state.phase === 'SECOND_FACTION_ACTION') {
            const active = state.activeFactionId;
            if (!active) {
                invalidCommands += 1;
                break;
            }
            const result = runAiActionPhase(state, active);
            state = result.state;
            invalidCommands += result.invalidGenerated;
            collectTelemetry();
            continue;
        }
        if (state.phase === 'SETTLEMENT_PLANNING') {
            const pendingFactionId = state.turnOrder.find((factionId) => !requireFaction(state, factionId).planningCommitted);
            if (pendingFactionId) {
                const result = runAiPlanning(state, pendingFactionId);
                state = result.state;
                invalidCommands += result.invalidGenerated;
                collectTelemetry();
                continue;
            }
        }
    }
    collectTelemetry();
    const commandGuardHit = !state.result;
    if (commandGuardHit)
        state.diagnostics.maxCommandsGuardHit = true;
    return { state, invalidCommands, commandGuardHit, rebuilds, telemetry };
}
export function runBatchSimulation(gameCount = 32) {
    const seeds = Array.from({ length: gameCount }, (_, index) => `warlord-batch-${String(index + 1).padStart(3, '0')}`);
    const results = seeds.map((seed, index) => runSingleSimulation(seed, 'normal', 'standard', index !== 0));
    const states = results.map((result) => result.state);
    const completed = states.filter((state) => state.result !== null);
    const winners = { draw: 0 };
    const terminalReasons = { elimination: 0, round_limit: 0, incomplete: 0 };
    for (const state of states) {
        if (!state.result) {
            terminalReasons.incomplete = (terminalReasons.incomplete ?? 0) + 1;
            continue;
        }
        winners[state.result.winner] = (winners[state.result.winner] ?? 0) + 1;
        terminalReasons[state.result.reason] = (terminalReasons[state.result.reason] ?? 0) + 1;
    }
    const cardStats = Object.fromEntries(CARD_IDS.map((cardId) => {
        let produced = 0;
        let lost = 0;
        let levels = 0;
        let promotions = 0;
        let samples = 0;
        for (const state of states) {
            for (const factionId of state.turnOrder) {
                const card = requireFaction(state, factionId).cards[cardId];
                if (!card)
                    continue;
                samples += 1;
                produced += card.producedCount;
                lost += card.lostCount;
                levels += card.level;
                promotions += card.purchasedPromotions.length;
            }
        }
        return [String(cardId), {
                produced,
                lost,
                finalAverageLevel: samples > 0 ? levels / samples : 0,
                promotionsPurchased: promotions,
            }];
    }));
    const suppressions = results.reduce((sum, result) => sum + result.telemetry.suppressions, 0);
    const sniperVolleyDamage = results.reduce((sum, result) => sum + result.telemetry.sniperVolleyDamage, 0);
    const totalDamage = results.reduce((sum, result) => sum + result.telemetry.totalDamage, 0);
    const battleRounds = results.reduce((sum, result) => sum + result.telemetry.battleRounds, 0);
    const battleCount = results.reduce((sum, result) => sum + result.telemetry.battleCount, 0);
    const battleRoundLimits = results.reduce((sum, result) => sum + result.telemetry.battleRoundLimits, 0);
    const invalidStateCount = results.reduce((sum, result) => sum + result.invalidCommands, 0)
        + states.filter((state) => Object.values(state.factions).some((faction) => (!Number.isFinite(faction.gold)
            || !Number.isFinite(faction.populationUsed)
            || faction.populationUsed < 0
            || faction.populationReserved < 0))).length;
    const rebuilds = Object.create(null);
    for (const result of results) {
        for (const [factionId, count] of Object.entries(result.rebuilds)) {
            rebuilds[factionId] = (rebuilds[factionId] ?? 0) + count;
        }
    }
    const denominator = Math.max(1, completed.length);
    const firstFactionId = states[0]?.turnOrder[0] ?? 'red';
    const secondFactionId = states[0]?.turnOrder[1] ?? 'blue';
    const firstRate = (winners[firstFactionId] ?? 0) / denominator;
    const secondRate = (winners[secondFactionId] ?? 0) / denominator;
    const summary = {
        schemaVersion: 1,
        rulesVersion: states[0]?.rulesVersion ?? 'wargame-demo-v0.1.1',
        configDigest: states[0]?.configDigest ?? '',
        tuningVersion: TUNING_VERSION,
        aiPolicyVersion: AI_POLICY_VERSION,
        generatedAt: new Date().toISOString(),
        gameCount,
        completedGames: completed.length,
        terminalReasons,
        winners,
        // Demo 1 compatibility fields; values mean initial first/second faction.
        mirrorWinRate: { red: firstRate, blue: secondRate, draw: (winners.draw ?? 0) / denominator },
        firstSecondBias: {
            initialFirstFaction: firstFactionId,
            initialFirstWinRate: firstRate,
            initialSecondWinRate: secondRate,
            delta: firstRate - secondRate,
        },
        averageStrategicRound: completed.length > 0
            ? completed.reduce((sum, state) => sum + state.strategicRound, 0) / completed.length
            : 0,
        cards: cardStats,
        controlEffects: { suppressions, sniperVolleyDamage, totalDamage },
        battles: {
            total: battleCount,
            averageBattleRounds: battleCount > 0 ? battleRounds / battleCount : 0,
            roundLimitCount: battleRoundLimits,
            roundLimitRate: battleCount > 0 ? battleRoundLimits / battleCount : 0,
        },
        rebuildsAfterFieldWipe: rebuilds,
        invalidStateCount,
        commandGuardHitCount: results.filter((result) => result.commandGuardHit).length,
        seeds,
    };
    return {
        summary,
        sampleReplay: makeReplay(states[0] ?? createGame()),
        finalStates: states,
    };
}
//# sourceMappingURL=run.js.map