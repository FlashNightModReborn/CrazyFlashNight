import { applyCommand } from '../core/engine.js';
import { createGame } from '../core/state.js';
import { runtimeMapBundleForScenarioRef } from '../data/map.js';
export function makeReplay(state) {
    const completeHistory = state.commandHistory.length === state.commandSequence
        && state.commandHistory.every((record, index) => record.sequence === index + 1);
    if (!completeHistory) {
        throw new Error('当前战局缺少从第 1 条开始的完整命令历史，不能导出完整录像。');
    }
    return {
        schemaVersion: 1,
        rulesVersion: state.rulesVersion,
        configDigest: state.configDigest,
        scenarioId: state.scenarioId,
        mapDefinitionId: state.mapDefinitionId,
        mapPresentationId: state.mapPresentationId,
        organizationConfigDigest: state.organization.configDigest,
        encounterConfigDigest: state.encounter.configDigest,
        gameSeed: state.gameSeed,
        difficulty: state.difficulty,
        preset: state.preset,
        commands: state.commandHistory.map((record) => structuredClone(record.command)),
        expected: {
            strategicRound: state.strategicRound,
            phase: state.phase,
            result: structuredClone(state.result),
        },
    };
}
export function exportReplay(state) {
    return JSON.stringify(makeReplay(state), null, 2);
}
export function parseReplay(json) {
    const parsed = JSON.parse(json);
    if (parsed.schemaVersion !== 1)
        throw new Error('不支持的录像 schemaVersion。');
    if (typeof parsed.gameSeed !== 'string' || !Array.isArray(parsed.commands))
        throw new Error('录像缺少种子或命令列表。');
    if (!parsed.rulesVersion || !parsed.configDigest || !parsed.difficulty || !parsed.preset)
        throw new Error('录像版本字段不完整。');
    if (typeof parsed.scenarioId !== 'string' || parsed.scenarioId.length === 0
        || typeof parsed.mapDefinitionId !== 'string' || parsed.mapDefinitionId.length === 0
        || typeof parsed.mapPresentationId !== 'string' || parsed.mapPresentationId.length === 0) {
        throw new Error('旧录像缺少关卡与地图身份，不能在多阵营规则下静默重放。');
    }
    if (typeof parsed.organizationConfigDigest !== 'string' || parsed.organizationConfigDigest.length === 0) {
        throw new Error('旧录像缺少编制配置摘要，不能在新编制规则下静默重放。');
    }
    if (typeof parsed.encounterConfigDigest !== 'string' || parsed.encounterConfigDigest.length === 0) {
        throw new Error('旧录像缺少接敌距离配置摘要，不能在新接敌距离规则下静默重放。');
    }
    return parsed;
}
export function replayGame(replay) {
    let state = createGame({
        seed: replay.gameSeed,
        difficulty: replay.difficulty,
        preset: replay.preset,
        runtimeBundle: runtimeMapBundleForScenarioRef(replay.scenarioId),
    });
    if (state.rulesVersion !== replay.rulesVersion)
        throw new Error(`录像规则版本不匹配：${replay.rulesVersion} != ${state.rulesVersion}`);
    if (state.configDigest !== replay.configDigest)
        throw new Error('录像配置摘要不匹配。');
    if (state.scenarioId !== replay.scenarioId
        || state.mapDefinitionId !== replay.mapDefinitionId
        || state.mapPresentationId !== replay.mapPresentationId) {
        throw new Error('录像关卡或地图身份不匹配。');
    }
    if (state.organization.configDigest !== replay.organizationConfigDigest) {
        throw new Error('录像编制配置摘要不匹配。');
    }
    if (state.encounter.configDigest !== replay.encounterConfigDigest) {
        throw new Error('录像接敌距离配置摘要不匹配。');
    }
    for (const [index, command] of replay.commands.entries()) {
        const result = applyCommand(state, command);
        if (!result.ok)
            throw new Error(`录像命令 ${index + 1} 非法：${result.error}`);
        state = result.state;
    }
    return state;
}
export function importAndReplay(json) {
    return replayGame(parseReplay(json));
}
export function deterministicStateView(state) {
    const clone = structuredClone(state);
    return clone;
}
//# sourceMappingURL=replay.js.map