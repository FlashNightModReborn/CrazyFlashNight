export const PLAYER_TEXT_SCHEMA_VERSION = 'warlord.player-text-catalog.v1';
export const PLAYER_TERMINOLOGY_VERSION = 'warlord.player-terminology.zh-cn.v1';
const ENCOUNTER_DISTANCE_TEXT = Object.freeze({
    near: Object.freeze({ compactLabel: '接敌：近', label: '接敌距离：近', impact: '很快接战，突击与持续供弹更容易发挥。' }),
    medium: Object.freeze({ compactLabel: '接敌：中', label: '接敌距离：中', impact: '双方都有准备时间。' }),
    far: Object.freeze({ compactLabel: '接敌：远', label: '接敌距离：远', impact: '狙击先手时间更长。' }),
});
function numberParam(params, key, fallback = 0) {
    const value = params[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}
function stringParam(params, key, fallback) {
    const value = params[key];
    return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}
const REASON_FORMATTERS = {
    game_over: () => ({ reason: '本局已经结束。', nextStep: '可查看结果，或重新开始一局。', helpAnchor: 'overview' }),
    action_phase_required: () => ({ reason: '现在不是部队行动阶段。', nextStep: '等待行动阶段，或先完成当前结算安排。', helpAnchor: 'turn' }),
    active_faction_mismatch: () => ({ reason: '现在还没轮到这支势力行动。', nextStep: '查看顶栏的当前行动方，等待我方回合。', helpAnchor: 'turn' }),
    node_unknown: () => ({ reason: '地图节点不存在或配置已经失效。', nextStep: '请退出本局并重新进入；若再次出现请报告该关卡。', helpAnchor: 'overview' }),
    origin_equals_target: () => ({ reason: '部队已经在这个据点。', nextStep: '请选择一个相邻目标据点。', helpAnchor: 'movement' }),
    target_not_adjacent: () => ({ reason: '目标与部队所在据点不相邻。', nextStep: '请选择高亮的相邻据点，或先分步移动。', helpAnchor: 'movement' }),
    allied_transit_invalid: () => ({ reason: '这条盟军过境路线不完整或中间据点不属于盟军。', nextStep: '选择一条“己方起点 → 盟军中转 → 己方或无主终点”的两段路线。', helpAnchor: 'movement' }),
    allied_destination_forbidden: () => ({ reason: '盟军据点只能过境，不能作为本次行动的终点。', nextStep: '继续选择盟军据点另一侧的己方或无主据点。', helpAnchor: 'movement' }),
    neutral_attack_forbidden: () => ({ reason: '目标是中立阵营，目前不能交战。', nextStep: '改选无主、己方或已明确敌对的据点。', helpAnchor: 'movement' }),
    hostile_garrison_ambiguous: () => ({ reason: '目标据点存在多个阵营，无法形成明确的二方交战。', nextStep: '等待该据点状态收敛，或选择其他目标。', helpAnchor: 'movement' }),
    selection_empty: () => ({ reason: '还没有选择我方部队。', nextStep: '先点击一支我方部队，再选择目标据点。', helpAnchor: 'movement' }),
    selection_duplicate: () => ({ reason: '选择中出现了重复部队。', nextStep: '取消当前临时编队后重新选择。', helpAnchor: 'movement' }),
    piece_unavailable: () => ({ reason: '所选部队已经无法行动。', nextStep: '刷新当前据点并重新选择可用部队。', helpAnchor: 'movement' }),
    piece_wrong_faction: () => ({ reason: '所选部队不归我方指挥。', nextStep: '请选择标有“我方”的部队。', helpAnchor: 'movement' }),
    piece_wrong_origin: () => ({ reason: '所选部队不在同一个起点据点。', nextStep: '只选择同一据点内的部队。', helpAnchor: 'movement' }),
    mixed_garrison_state: () => ({ reason: '这个据点的驻军状态尚未稳定。', nextStep: '请先查看其他据点，稍后再尝试。', helpAnchor: 'garrison-capacity' }),
    attack_width_exceeded: (params) => ({
        reason: `已投入 ${numberParam(params, 'selected')} 支部队，本次最多投入 ${numberParam(params, 'maximum')} 支。`,
        nextStep: '请减少参战部队后再次进攻。',
        helpAnchor: 'deployment-limit',
    }),
    assault_reentry_locked: () => ({ reason: '这支部队本回合已经在此进攻失败。', nextStep: '改选其他部队，或等待下一回合再进攻。', helpAnchor: 'movement' }),
    action_points_insufficient: (params) => ({
        reason: `行动点不足：需要 ${numberParam(params, 'required')} 点，当前有 ${numberParam(params, 'available')} 点。`,
        nextStep: '请减少行动部队，或结束本回合。',
        helpAnchor: 'action-points',
    }),
    garrison_capacity_full: (params) => ({
        reason: `${stringParam(params, 'nodeName', '目标据点')}已达到驻军上限 ${numberParam(params, 'maximum')}。`,
        nextStep: '请减少本次移动部队，或先调走目标据点的驻军。',
        helpAnchor: 'garrison-capacity',
    }),
    command_element_partial_selection: () => ({
        reason: '临时编队必须作为一支完整部队行动。',
        nextStep: '请先在当前据点拆出需要单独行动的成员。',
        helpAnchor: 'movement',
    }),
    reorganization_selection_invalid: () => ({
        reason: '当前选择不能完成这次编队调整。',
        nextStep: '合并时请选择至少两支同据点部队；拆分时请选择编队内成员。',
        helpAnchor: 'movement',
    }),
    reorganization_wrong_node: () => ({
        reason: '只能调整位于同一据点的我方部队。',
        nextStep: '请返回部队所在据点，再进行合并、拆分或阵型调整。',
        helpAnchor: 'movement',
    }),
    task_group_template_mismatch: (params) => ({
        reason: `当前选择不符合临时编队人数要求${numberParam(params, 'minimum') > 0 ? `，需要 ${numberParam(params, 'minimum')} 至 ${numberParam(params, 'maximum')} 支部队` : ''}。`,
        nextStep: '请减少或补充所选部队后重试。',
        helpAnchor: 'movement',
    }),
    formation_unknown: () => ({
        reason: '这个阵型不适用于当前部队。',
        nextStep: '请从当前编队显示的五种阵型中重新选择。',
        helpAnchor: 'deployment-limit',
    }),
    formation_mix_unsupported: (params) => ({
        reason: stringParam(params, 'side', 'attacker') === 'defender'
            ? '目标据点的守军采用了不同阵型，当前不能形成统一战斗队形。'
            : '所选参战部队采用了不同阵型，不能同时按两种队形进入战斗。',
        nextStep: stringParam(params, 'side', 'attacker') === 'defender'
            ? '请改选其他目标，或等守军统一阵型后再进攻。'
            : '请在当前据点把参战部队调整为同一阵型，再次进攻。',
        helpAnchor: 'deployment-limit',
    }),
    planning_phase_required: () => ({ reason: '现在还不能进行结算安排。', nextStep: '双方结束行动后，再进行升级和生产。', helpAnchor: 'turn' }),
    planning_already_committed: () => ({ reason: '本轮结算安排已经提交。', nextStep: '等待下一回合开始。', helpAnchor: 'turn' }),
    xp_amount_invalid: () => ({ reason: '经验分配数量无效。', nextStep: '请输入大于零的整数。', helpAnchor: 'advancement' }),
    xp_insufficient: (params) => ({
        reason: `可分配经验不足：需要 ${numberParam(params, 'required')}，当前有 ${numberParam(params, 'available')}。`,
        nextStep: '减少本次分配数量，或继续通过战斗获得经验。',
        helpAnchor: 'advancement',
    }),
    card_unknown: () => ({ reason: '这个兵种目前不可用。', nextStep: '请选择兵种栏中可见的其他兵种。', helpAnchor: 'advancement' }),
    promotion_already_purchased_this_round: () => ({ reason: '这个兵种本轮已经升阶。', nextStep: '下一轮结算时可以继续升阶。', helpAnchor: 'advancement' }),
    promotion_complete: () => ({ reason: '这个兵种已经完成全部升阶。', nextStep: '可以继续升级或安排生产。', helpAnchor: 'advancement' }),
    promotion_sequence_required: (params) => ({
        reason: `需要先完成“${stringParam(params, 'promotionName', '前一项升阶')}”。`,
        nextStep: '按显示顺序完成升阶。',
        helpAnchor: 'advancement',
    }),
    card_level_insufficient: (params) => ({
        reason: `兵种等级不足，需要达到 ${numberParam(params, 'requiredLevel')} 级。`,
        nextStep: '先分配战后经验提升等级。',
        helpAnchor: 'advancement',
    }),
    military_funds_insufficient: (params) => ({
        reason: `军费不足：需要 ${numberParam(params, 'required')}，当前有 ${numberParam(params, 'available')}。`,
        nextStep: '减少本轮开支，或占领并守住提供收入的据点。',
        helpAnchor: 'production',
    }),
    production_node_invalid: () => ({ reason: '这个据点不能生产部队。', nextStep: '请选择带有生产槽的我方据点。', helpAnchor: 'production' }),
    production_node_unavailable: () => ({ reason: '这个生产据点尚未稳定或未激活。', nextStep: '先确保补给路线和据点控制稳定。', helpAnchor: 'production' }),
    production_slot_missing: () => ({ reason: '所选生产槽已经不可用。', nextStep: '重新选择一个当前可见的生产槽。', helpAnchor: 'production' }),
    population_capacity_insufficient: () => ({ reason: '人口上限不足，包含已经预留的生产人口。', nextStep: '等待现有订单完成，或取消尚未开工的订单。', helpAnchor: 'production' }),
    production_order_missing: () => ({ reason: '这张生产订单已经不在所选槽位。', nextStep: '刷新生产队列后重新选择。', helpAnchor: 'production' }),
    production_order_mismatch: () => ({ reason: '生产订单与当前槽位不一致。', nextStep: '重新定位该订单所在的生产槽。', helpAnchor: 'production' }),
    production_order_locked: () => ({ reason: '订单已经开工，不能再撤销。', nextStep: '等待生产完成；下次可在开工前撤销。', helpAnchor: 'production' }),
    production_reservation_invalid: () => ({ reason: '生产预留状态尚未完成核对。', nextStep: '请保留当前订单并稍后重试。', helpAnchor: 'production' }),
    faction_unknown: () => ({ reason: '这支势力不在当前战局中。', nextStep: '重新进入关卡以刷新阵营配置。', helpAnchor: 'overview' }),
    faction_defeated: () => ({ reason: '这支势力已经退出战局。', nextStep: '查看仍在行动的阵营和当前胜负目标。', helpAnchor: 'overview' }),
    commander_unknown: () => ({ reason: '没有找到对应的指挥官。', nextStep: '查看当前阵营的指挥官状态后重试。', helpAnchor: 'overview' }),
    commander_state_invalid: () => ({ reason: '指挥官当前状态不允许这项操作。', nextStep: '等待撤离或生产完成，再重新部署。', helpAnchor: 'turn' }),
    command_post_required: () => ({ reason: '这项操作必须在己方安全指挥所完成。', nextStep: '先守住指挥所并清除争夺，再进行操作。', helpAnchor: 'production' }),
};
export const ALL_VALIDATION_REASON_CODES = Object.freeze(Object.keys(REASON_FORMATTERS));
export function playerTextForReason(reasonCode, params = {}) {
    const resolved = reasonCode
        ? REASON_FORMATTERS[reasonCode](params)
        : { reason: '当前操作暂时不可执行。', nextStep: '请返回上一步重新选择。', helpAnchor: 'overview' };
    return { ...resolved, assistiveText: `${resolved.reason} ${resolved.nextStep}` };
}
export function playerReasonSummary(reasonCode, params = {}) {
    return playerTextForReason(reasonCode, params).assistiveText;
}
export function playerEncounterDistanceText(distanceBand) {
    const copy = ENCOUNTER_DISTANCE_TEXT[distanceBand];
    return Object.freeze({ ...copy, assistiveText: `${copy.label} · ${copy.impact}` });
}
export function playerFactionName(factionId) {
    return factionId === 'red' ? '我方' : '敌方';
}
export function playerOwnerName(factionId) {
    return factionId === null ? '无主' : playerFactionName(factionId);
}
export function playerBehaviorName(behaviorId) {
    const labels = {
        assault: '突击',
        sniper: '远射',
        ammo: '装填',
        heavy: '重装',
    };
    return labels[behaviorId] ?? '通用';
}
export function playerPowerTierName(powerTier) {
    const playerLabel = powerTier
        .replace(/^T\d+\s*/, '')
        .replace('Boss', '首领')
        .replace(/[兵级]$/, '')
        .trim();
    return playerLabel || '标准兵种';
}
export function formatMilitaryFunds(value) {
    return `军费 ${value}`;
}
export function formatActionPoints(value) {
    return `行动点 ${value}`;
}
export function formatStrategicRound(value) {
    return `第 ${value} 回合`;
}
//# sourceMappingURL=player-text-catalog.js.map