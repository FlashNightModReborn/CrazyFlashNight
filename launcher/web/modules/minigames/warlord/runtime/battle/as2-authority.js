import { addGameEvent } from '../core/events.js';
import { bounty, getRuntimeStats } from '../core/math.js';
import { movePieceInPlace, removePieceInPlace } from '../core/pieces.js';
import { piecesAtNode } from '../core/selectors.js';
import { validateCommand } from '../core/validator.js';
import { getCardDefinition } from '../data/cards.js';
export const AS2_BATTLE_REQUEST_SCHEMA = 'warlord.as2-battle-request.v1';
export const AS2_BATTLE_RECEIPT_SCHEMA = 'warlord.as2-battle-receipt.v1';
export const AS2_RESUME_SCHEMA = 'warlord.as2-resume.v1';
const OPAQUE_ID = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;
function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function clone(value) {
    return structuredClone(value);
}
function canonicalValue(value) {
    if (Array.isArray(value))
        return value.map(canonicalValue);
    if (isObject(value)) {
        return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]));
    }
    return value;
}
export function canonicalJson(value) {
    const json = JSON.stringify(canonicalValue(value));
    if (json === undefined)
        throw new Error('权威请求包含不可序列化值。');
    return json;
}
export async function sha256Canonical(value) {
    if (!globalThis.crypto?.subtle)
        throw new Error('当前 WebView 不支持 SHA-256 权威请求摘要。');
    const digest = await globalThis.crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonicalJson(value)));
    return `sha256:${[...new Uint8Array(digest)]
        .map((byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}
function assertOpaque(value, label) {
    if (!OPAQUE_ID.test(value))
        throw new Error(`${label} 不是合法的不透明标识。`);
}
export function createAs2AuthoritySessionId() {
    const random = new Uint32Array(2);
    if (globalThis.crypto?.getRandomValues)
        globalThis.crypto.getRandomValues(random);
    else {
        random[0] = Math.floor(Math.random() * 0x1_0000_0000);
        random[1] = Math.floor(Math.random() * 0x1_0000_0000);
    }
    return `warlord.${Date.now().toString(36)}.${random[0].toString(36)}${random[1].toString(36)}`;
}
export async function buildAs2BattleEnvelope(input) {
    assertOpaque(input.panelInstanceId, 'panelInstanceId');
    assertOpaque(input.callId, 'callId');
    assertOpaque(input.sessionId, 'sessionId');
    assertOpaque(input.requestId, 'requestId');
    const validation = validateCommand(input.state, input.command);
    if (!validation.ok || validation.isBattle !== true) {
        throw new Error(validation.error ?? '只有真实交战命令可以交给 AS2。');
    }
    const request = {
        schema: AS2_BATTLE_REQUEST_SCHEMA,
        sessionId: input.sessionId,
        requestId: input.requestId,
        state: clone(input.state),
        command: clone(input.command),
        clientContext: clone(input.clientContext),
    };
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
function isGameState(value) {
    if (!isObject(value) || value.schemaVersion !== 1)
        return false;
    return isObject(value.map) && isObject(value.factions) && isObject(value.pieces)
        && Array.isArray(value.battles) && Array.isArray(value.commandHistory);
}
function isMoveCommand(value) {
    if (!isObject(value) || value.type !== 'MOVE_OR_ATTACK')
        return false;
    return (value.factionId === 'red' || value.factionId === 'blue')
        && Array.isArray(value.pieceIds)
        && value.pieceIds.every((pieceId) => typeof pieceId === 'string')
        && typeof value.originNodeId === 'string'
        && typeof value.targetNodeId === 'string';
}
function readResume(value) {
    if (!isObject(value) || value.schema !== AS2_RESUME_SCHEMA)
        return null;
    if (!isObject(value.request) || value.request.schema !== AS2_BATTLE_REQUEST_SCHEMA)
        return null;
    if (!isGameState(value.state) || !isMoveCommand(value.command))
        return null;
    const request = value.request;
    if (!isGameState(request.state) || !isMoveCommand(request.command) || !isObject(request.clientContext))
        return null;
    if (typeof request.sessionId !== 'string' || typeof request.requestId !== 'string')
        return null;
    if (typeof value.inputDigest !== 'string')
        return null;
    return value;
}
export function frozenStateFromAs2Resume(value) {
    const resume = readResume(value);
    return resume ? clone(resume.state) : null;
}
export function sessionIdFromAs2Resume(value) {
    const resume = readResume(value);
    return resume && OPAQUE_ID.test(resume.request.sessionId) ? resume.request.sessionId : null;
}
function battleSnapshot(state, pieceId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        throw new Error(`冻结战略态缺少棋子 ${pieceId}。`);
    const definition = getCardDefinition(piece.cardId);
    const cardState = state.factions[piece.factionId].cards[piece.cardId];
    const stats = getRuntimeStats(piece.cardId, cardState);
    return {
        pieceId,
        factionId: piece.factionId,
        cardId: piece.cardId,
        displayName: definition.displayName,
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
function normalizeUnits(raw, expectedIds, expectedFactionId, state, label) {
    if (!Array.isArray(raw) || raw.length !== expectedIds.length) {
        throw new Error(`${label}单位回执数量与冻结战略态不一致。`);
    }
    const byId = new Map();
    for (const candidate of raw) {
        if (!isObject(candidate))
            throw new Error(`${label}单位回执格式非法。`);
        const pieceId = candidate.pieceId;
        const petId = candidate.petId;
        const hpPermille = candidate.hpPermille;
        if (typeof pieceId !== 'string' || byId.has(pieceId)
            || typeof petId !== 'number' || !Number.isInteger(petId)
            || typeof hpPermille !== 'number' || !Number.isInteger(hpPermille)
            || hpPermille < 0 || hpPermille > 1000
            || typeof candidate.identifier !== 'string'
            || typeof candidate.level !== 'number'
            || typeof candidate.alive !== 'boolean') {
            throw new Error(`${label}单位回执字段非法或重复。`);
        }
        const piece = state.pieces[pieceId];
        if (!piece || piece.factionId !== expectedFactionId || piece.cardId !== petId) {
            throw new Error(`${label}单位的棋子/战宠身份发生变化：${pieceId}。`);
        }
        const definition = getCardDefinition(piece.cardId);
        const cardState = state.factions[piece.factionId].cards[piece.cardId];
        const level = cardState.level;
        const strategicPromotions = candidate.strategicPromotions;
        if (candidate.identifier !== definition.identifier || candidate.level !== level
            || !Array.isArray(strategicPromotions)
            || strategicPromotions.some((name) => typeof name !== 'string')
            || canonicalJson(strategicPromotions) !== canonicalJson(cardState.purchasedPromotions)
            || candidate.alive !== (hpPermille > 0)) {
            throw new Error(`${label}单位的战宠目录或生命状态不一致：${pieceId}。`);
        }
        byId.set(pieceId, {
            pieceId,
            factionId: expectedFactionId,
            petId,
            identifier: candidate.identifier,
            level,
            strategicPromotions: [...strategicPromotions],
            hpPermille,
            alive: candidate.alive,
        });
    }
    return expectedIds.map((pieceId) => {
        const result = byId.get(pieceId);
        if (!result)
            throw new Error(`${label}单位回执缺少 ${pieceId}。`);
        return result;
    });
}
function validateEconomyObservation(value, attackerUnits, defenderUnits, state) {
    if (!isObject(value)
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
    const nonNegativeInteger = (candidate, label) => {
        if (typeof candidate !== 'number' || !Number.isSafeInteger(candidate) || candidate < 0) {
            throw new Error(`${label}不是非负安全整数。`);
        }
        return candidate;
    };
    const verifySide = (side, expected, label) => {
        if (!isObject(side) || !Array.isArray(side.units) || side.units.length !== expected.length) {
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
            if (!source || unit.petId !== source.petId || unit.hpPermille !== source.hpPermille
                || unit.identifier !== source.identifier
                || canonicalJson(unit.strategicPromotions) !== canonicalJson(source.strategicPromotions)
                || unit.lost !== !source.alive || !piece) {
                throw new Error(`${label}战宠经济观测与战斗回执不一致。`);
            }
            const strategicGoldValue = nonNegativeInteger(unit.strategicGoldValue, `${label}战旗价值`);
            const basePrice = nonNegativeInteger(unit.basePrice, `${label}战宠基础价`);
            const kPrice = nonNegativeInteger(unit.kPrice, `${label}战宠K价`);
            nonNegativeInteger(unit.increasePrice, `${label}战宠涨价步长`);
            if (strategicGoldValue !== piece.productionGoldValue) {
                throw new Error(`${label}战旗价值与冻结棋子不一致。`);
            }
            catalogBaseExposureGold += basePrice;
            catalogBaseExposureK += kPrice;
            strategicExposureGold += strategicGoldValue;
            if (unit.lost) {
                catalogBaseLostGold += basePrice;
                catalogBaseLostK += kPrice;
                strategicLostGold += strategicGoldValue;
            }
            expectedById.delete(unit.pieceId);
        }
        if (expectedById.size !== 0)
            throw new Error(`${label}战宠经济观测缺少单位。`);
        const expectedAggregates = {
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
function buildAuthorityEvents(battleId, winner, reason, casualties, frames) {
    let ordinal = 0;
    const events = casualties.map((casualty) => {
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
function applyAcceptedReceipt(request, receipt) {
    const state = clone(request.state);
    const command = clone(request.command);
    const validation = validateCommand(state, command);
    if (!validation.ok || validation.isBattle !== true) {
        throw new Error(validation.error ?? '恢复时战略命令已不再是合法交战。');
    }
    const attackerIds = [...(validation.actualPieceIds ?? command.pieceIds)];
    const defenderIds = piecesAtNode(state, command.targetNodeId)
        .filter((piece) => piece.factionId !== command.factionId)
        .map((piece) => piece.pieceId);
    const defenderFactionId = command.factionId === 'red' ? 'blue' : 'red';
    const attackerUnits = normalizeUnits(receipt.attackerUnits, attackerIds, command.factionId, state, '进攻方');
    const defenderUnits = normalizeUnits(receipt.defenderUnits, defenderIds, defenderFactionId, state, '防守方');
    const winner = receipt.winner;
    const reason = receipt.reason;
    if ((winner !== 'attacker' && winner !== 'defender')
        || (reason !== 'wiped' && reason !== 'mutual_wipe' && reason !== 'battle_round_limit')) {
        throw new Error('AS2 胜负或结束原因非法。');
    }
    const attackersDead = attackerUnits.every((unit) => !unit.alive);
    const defendersDead = defenderUnits.every((unit) => !unit.alive);
    if (reason === 'mutual_wipe' && (!attackersDead || !defendersDead)) {
        throw new Error('AS2 双方全灭回执与单位生命状态不一致。');
    }
    if (reason === 'wiped'
        && ((winner === 'attacker' && !defendersDead) || (winner === 'defender' && !attackersDead))) {
        throw new Error('AS2 歼灭胜负与单位生命状态不一致。');
    }
    if (reason === 'battle_round_limit' && winner !== 'defender') {
        throw new Error('AS2 超时必须按演习规则由守方守住。');
    }
    const frames = receipt.frames;
    const durationMs = receipt.durationMs;
    if (typeof frames !== 'number' || !Number.isInteger(frames) || frames < 0
        || typeof durationMs !== 'number' || !Number.isFinite(durationMs) || durationMs < 0) {
        throw new Error('AS2 时间观测字段非法。');
    }
    const economyObservation = validateEconomyObservation(receipt.economyObservation, attackerUnits, defenderUnits, state);
    state.commandSequence += 1;
    state.commandHistory.push({ sequence: state.commandSequence, command: clone(command) });
    const faction = state.factions[command.factionId];
    faction.actionPoints -= attackerIds.length;
    faction.apSpentThisRound += attackerIds.length;
    state.battleOrdinal += 1;
    const battleId = `b-r${state.strategicRound}-c${state.commandSequence}-o${state.battleOrdinal}`;
    const seed = `${state.gameSeed}|${state.strategicRound}|${state.commandSequence}|${state.battleOrdinal}`;
    const attackerSnapshots = attackerIds.map((pieceId) => battleSnapshot(state, pieceId));
    const defenderSnapshots = defenderIds.map((pieceId) => battleSnapshot(state, pieceId));
    const allUnits = [...attackerUnits, ...defenderUnits];
    const unitById = new Map(allUnits.map((unit) => [unit.pieceId, unit]));
    const pieceResults = [...attackerIds, ...defenderIds]
        .map((pieceId) => {
        const piece = state.pieces[pieceId];
        const unit = unitById.get(pieceId);
        if (!piece || !unit)
            throw new Error(`AS2 回执缺少冻结棋子 ${pieceId}。`);
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
            frozenCardLevel: unit.level,
        };
    })
        .sort((a, b) => a.pieceId.localeCompare(b.pieceId));
    const casualties = pieceResults
        .filter((result) => result.dead)
        .map((result) => ({
        pieceId: result.pieceId,
        factionId: result.factionId,
        killerFactionId: result.factionId === command.factionId ? defenderFactionId : command.factionId,
        cardId: result.cardId,
        frozenCardLevel: result.frozenCardLevel,
    }));
    const authority = {
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
    const record = {
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
        if (piece)
            piece.hp = result.hpAfter;
    }
    for (const pieceId of [...attackerIds, ...defenderIds]) {
        const piece = state.pieces[pieceId];
        if (piece)
            piece.battlesThisRound += 1;
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
        removePieceInPlace(state, casualty.pieceId);
    }
    if (winner === 'attacker') {
        for (const pieceId of attackerIds) {
            if (state.pieces[pieceId])
                movePieceInPlace(state, pieceId, command.targetNodeId);
        }
    }
    else if (reason !== 'mutual_wipe') {
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
        message: `${state.map.nodes[command.targetNodeId].displayName} AS2 实战结束：${winner === 'attacker' ? '进攻方胜利' : '守方守住'}。`,
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
export async function applyAs2BattleResume(value) {
    const resume = readResume(value);
    if (!resume) {
        return { ok: false, state: null, error: 'AS2 恢复信封格式非法。', resultUnknown: true };
    }
    const frozenState = clone(resume.state);
    try {
        assertOpaque(resume.request.sessionId, 'sessionId');
        assertOpaque(resume.request.requestId, 'requestId');
        const digest = await sha256Canonical(resume.request);
        if (digest !== resume.inputDigest
            || canonicalJson(resume.request.state) !== canonicalJson(resume.state)
            || canonicalJson(resume.request.command) !== canonicalJson(resume.command)) {
            throw new Error('AS2 恢复内容与冻结请求摘要不一致。');
        }
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
            || resume.receipt.playerPetSnapshotUsed !== false) {
            throw new Error('AS2 战宠投影契约缺失或引用了玩家战宠快照。');
        }
        const applied = applyAcceptedReceipt(resume.request, resume.receipt);
        return {
            ok: true,
            state: applied.state,
            battleRecord: applied.record,
            resultUnknown: false,
        };
    }
    catch (error) {
        return {
            ok: false,
            state: frozenState,
            error: error instanceof Error ? error.message : String(error),
            resultUnknown: true,
        };
    }
}
//# sourceMappingURL=as2-authority.js.map