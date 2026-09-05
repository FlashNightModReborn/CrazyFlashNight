import { RULES_VERSION } from './config.js';
import { DEMO_1_ENCOUNTER } from './encounter.js';
const MAP_CENTER = Object.freeze({ x: 600, y: 450 });
const HOME_SPECS = Object.freeze([
    { key: 'player', factionId: 'player', displayName: '西北远征军', baseX: 90, baseY: 80 },
    { key: 'pact-a', factionId: 'boss-pact-a', displayName: '东北盟约军', baseX: 1110, baseY: 80 },
    { key: 'independent', factionId: 'boss-independent', displayName: '东南独立军', baseX: 1110, baseY: 820 },
    { key: 'pact-b', factionId: 'boss-pact-b', displayName: '西南盟约军', baseX: 90, baseY: 820 },
]);
export const DEMO_2_COMMANDER_CARD_BY_FACTION = Object.freeze({
    player: 83,
    'boss-pact-a': 111,
    'boss-independent': 113,
    'boss-pact-b': 112,
});
const HOME_NODE_ROLES = Object.freeze([
    { ordinal: 1, suffix: '总部', kind: 'hq', progress: 0, lateral: 0 },
    { ordinal: 2, suffix: '补给总站', kind: 'supply', progress: 0.10, lateral: -30 },
    { ordinal: 3, suffix: '兵营', kind: 'barracks', progress: 0.10, lateral: 30 },
    { ordinal: 4, suffix: '农垦区', kind: 'economy', progress: 0.20, lateral: -45 },
    { ordinal: 5, suffix: '指挥所', kind: 'command', progress: 0.20, lateral: 0 },
    { ordinal: 6, suffix: '军需库', kind: 'depot', progress: 0.20, lateral: 45 },
    { ordinal: 7, suffix: '北翼驻地', kind: 'field', progress: 0.31, lateral: -40 },
    { ordinal: 8, suffix: '南翼驻地', kind: 'field', progress: 0.31, lateral: 40 },
    { ordinal: 9, suffix: '机修厂', kind: 'industry', progress: 0.41, lateral: -55 },
    { ordinal: 10, suffix: '通信站', kind: 'relay', progress: 0.41, lateral: 0 },
    { ordinal: 11, suffix: '弹药厂', kind: 'industry', progress: 0.41, lateral: 55 },
    { ordinal: 12, suffix: '左前沿', kind: 'frontier', progress: 0.51, lateral: -38 },
    { ordinal: 13, suffix: '右前沿', kind: 'frontier', progress: 0.51, lateral: 38 },
    { ordinal: 14, suffix: '战区枢纽', kind: 'logistics', progress: 0.54, lateral: 0 },
]);
const HOME_EDGE_PAIRS = Object.freeze([
    [1, 2], [1, 3],
    [2, 4], [2, 5], [3, 5], [3, 6],
    [4, 5], [5, 6],
    [4, 7], [5, 7], [5, 8], [6, 8],
    [7, 9], [7, 10], [8, 10], [8, 11],
    [9, 12], [10, 12], [10, 13], [11, 13],
    [12, 14], [13, 14],
]);
const CENTRAL_POSITIONS = Object.freeze([
    [536, 397],
    [600, 375],
    [664, 397],
    [690, 450],
    [664, 503],
    [600, 525],
    [536, 503],
    [510, 450],
]);
function twoDigit(value) {
    return String(value).padStart(2, '0');
}
function homeNodeId(key, ordinal) {
    return 'd2-' + key + '-' + twoDigit(ordinal);
}
function armNodeId(key, ordinal) {
    return 'd2-arm-' + key + '-' + twoDigit(ordinal);
}
function centralNodeId(ordinal) {
    return 'd2-central-' + twoDigit(ordinal);
}
function pointTowardCenter(spec, progress, lateral) {
    const deltaX = MAP_CENTER.x - spec.baseX;
    const deltaY = MAP_CENTER.y - spec.baseY;
    const length = Math.hypot(deltaX, deltaY);
    const perpendicularX = -deltaY / length;
    const perpendicularY = deltaX / length;
    return Object.freeze({
        x: Math.round(spec.baseX + deltaX * progress + perpendicularX * lateral),
        y: Math.round(spec.baseY + deltaY * progress + perpendicularY * lateral),
    });
}
function homeNodeAuthoring(role) {
    const isHeadquarters = role.ordinal === 1;
    const isNearBase = role.ordinal <= 3;
    return {
        id: '',
        kind: role.kind,
        garrisonCapacity: isHeadquarters ? 6 : role.kind === 'frontier' ? 5 : 4,
        attackWidth: isHeadquarters ? 4 : 3,
        defenseBonus: isHeadquarters ? 0.15 : role.kind === 'frontier' ? 0.08 : 0,
        nodeAPBonus: role.kind === 'command' ? 1 : 0,
        encounterProfileRef: isNearBase ? 'encounter.near' : 'encounter.medium',
    };
}
function homeNodeRule(spec, role) {
    const values = [
        [6, 5, 6, 2],
        [4, 2, 8, 2],
        [4, 1, 8, 3],
        [3, 8, 3, 1],
        [5, 2, 4, 1],
        [3, 5, 3, 1],
        [2, 2, 2, 0],
        [2, 2, 2, 0],
        [4, 7, 3, 2],
        [3, 3, 2, 1],
        [4, 7, 3, 2],
        [3, 2, 2, 0],
        [3, 2, 2, 0],
        [5, 4, 5, 2],
    ];
    const value = values[role.ordinal - 1];
    if (!value)
        throw new Error('Missing Demo 2 home-node economy values.');
    return {
        nodeRef: homeNodeId(spec.key, role.ordinal),
        displayName: spec.displayName + '·' + role.suffix,
        strategicValue: value[0],
        goldIncome: value[1],
        population: value[2],
        productionSlots: value[3],
    };
}
function edgeBuilder() {
    const edges = [];
    return {
        edges,
        add(a, b) {
            edges.push({ id: 'd2-edge-' + twoDigit(edges.length + 1), a, b });
        },
    };
}
export const DEMO_2_HOME_NODE_IDS = Object.freeze(Object.fromEntries(HOME_SPECS.map((spec) => [
    spec.key,
    Object.freeze(HOME_NODE_ROLES.map((role) => homeNodeId(spec.key, role.ordinal))),
])));
export const DEMO_2_ARM_NODE_IDS = Object.freeze(Object.fromEntries(HOME_SPECS.map((spec) => [
    spec.key,
    Object.freeze(Array.from({ length: 4 }, (_, index) => armNodeId(spec.key, index + 1))),
])));
export const DEMO_2_CENTRAL_NODE_IDS = Object.freeze(Array.from({ length: 8 }, (_, index) => centralNodeId(index + 1)));
const mapNodes = [];
const presentationNodes = [];
const nodeRules = [];
for (const spec of HOME_SPECS) {
    for (const role of HOME_NODE_ROLES) {
        const id = homeNodeId(spec.key, role.ordinal);
        mapNodes.push({ ...homeNodeAuthoring(role), id });
        const point = pointTowardCenter(spec, role.progress, role.lateral);
        presentationNodes.push({
            nodeRef: id,
            x: point.x,
            y: point.y,
            ...(role.ordinal === 1 ? { visualAnchor: spec.key } : {}),
        });
        nodeRules.push(homeNodeRule(spec, role));
    }
    for (let ordinal = 1; ordinal <= 4; ordinal += 1) {
        const id = armNodeId(spec.key, ordinal);
        const isInner = ordinal >= 3;
        const lateral = ordinal % 2 === 1 ? -30 : 30;
        const point = pointTowardCenter(spec, isInner ? 0.78 : 0.64, lateral);
        mapNodes.push({
            id,
            kind: isInner ? 'contested-industry' : 'contested-frontier',
            garrisonCapacity: isInner ? 5 : 4,
            attackWidth: isInner ? 4 : 3,
            defenseBonus: isInner ? 0.05 : 0.1,
            nodeAPBonus: isInner ? 1 : 0,
            encounterProfileRef: isInner ? 'encounter.far' : 'encounter.medium',
        });
        presentationNodes.push({ nodeRef: id, x: point.x, y: point.y });
        nodeRules.push({
            nodeRef: id,
            displayName: spec.displayName + '争夺臂·' + ordinal,
            strategicValue: isInner ? 5 : 3,
            goldIncome: isInner ? 6 : 2,
            population: isInner ? 3 : 1,
            productionSlots: isInner ? 1 : 0,
        });
    }
}
for (let ordinal = 1; ordinal <= 8; ordinal += 1) {
    const id = centralNodeId(ordinal);
    const point = CENTRAL_POSITIONS[ordinal - 1];
    if (!point)
        throw new Error('Missing Demo 2 central-ring position.');
    const isFar = ordinal % 2 === 1;
    mapNodes.push({
        id,
        kind: 'central-industry',
        garrisonCapacity: 6,
        attackWidth: 4,
        defenseBonus: 0.12,
        nodeAPBonus: ordinal % 4 === 0 ? 2 : 1,
        encounterProfileRef: isFar ? 'encounter.far' : 'encounter.medium',
    });
    presentationNodes.push({ nodeRef: id, x: point[0], y: point[1], visualAnchor: 'central-ring' });
    nodeRules.push({
        nodeRef: id,
        displayName: '中央工业环·' + ordinal,
        strategicValue: 8 + (ordinal % 2),
        goldIncome: 12,
        population: 6,
        productionSlots: ordinal % 2 === 0 ? 4 : 3,
    });
}
const edgeState = edgeBuilder();
for (const spec of HOME_SPECS) {
    for (const pair of HOME_EDGE_PAIRS) {
        edgeState.add(homeNodeId(spec.key, pair[0]), homeNodeId(spec.key, pair[1]));
    }
    edgeState.add(armNodeId(spec.key, 1), armNodeId(spec.key, 2));
    edgeState.add(armNodeId(spec.key, 1), armNodeId(spec.key, 3));
    edgeState.add(armNodeId(spec.key, 2), armNodeId(spec.key, 4));
    edgeState.add(armNodeId(spec.key, 3), armNodeId(spec.key, 4));
    edgeState.add(homeNodeId(spec.key, 12), armNodeId(spec.key, 1));
    edgeState.add(homeNodeId(spec.key, 13), armNodeId(spec.key, 2));
}
const armToCenter = Object.freeze({
    player: [8, 1],
    'pact-a': [2, 3],
    independent: [4, 5],
    'pact-b': [6, 7],
});
for (const spec of HOME_SPECS) {
    const centralOrdinals = armToCenter[spec.key];
    edgeState.add(armNodeId(spec.key, 3), centralNodeId(centralOrdinals[0]));
    edgeState.add(armNodeId(spec.key, 4), centralNodeId(centralOrdinals[1]));
}
for (let ordinal = 1; ordinal <= 8; ordinal += 1) {
    edgeState.add(centralNodeId(ordinal), centralNodeId(ordinal === 8 ? 1 : ordinal + 1));
}
for (let ordinal = 1; ordinal <= 4; ordinal += 1) {
    edgeState.add(centralNodeId(ordinal), centralNodeId(ordinal + 4));
}
edgeState.add(armNodeId('player', 3), armNodeId('pact-a', 4));
edgeState.add(armNodeId('pact-a', 3), armNodeId('independent', 4));
edgeState.add(armNodeId('independent', 3), armNodeId('pact-b', 4));
edgeState.add(armNodeId('pact-b', 3), armNodeId('player', 4));
export const DEMO_2_MAP_AUTHORING = {
    schemaVersion: 1,
    id: 'demo2-thick-x-80',
    rulesVersion: RULES_VERSION,
    encounterDefinitionRef: DEMO_1_ENCOUNTER.id,
    nodes: mapNodes,
    edges: edgeState.edges,
};
export const DEMO_2_MAP_PRESENTATION = {
    schemaVersion: 1,
    id: 'demo2-thick-x-80.desert',
    mapRef: DEMO_2_MAP_AUTHORING.id,
    themeRef: 'desert-large-map',
    nodes: presentationNodes,
};
export const DEMO_2_SECTORS = Object.freeze([
    ...HOME_SPECS.map((spec) => Object.freeze({
        id: ('sector.' + spec.key + '-home'),
        displayName: spec.displayName + '本土战区',
        role: 'home',
        nodeRefs: DEMO_2_HOME_NODE_IDS[spec.key],
    })),
    ...HOME_SPECS.map((spec) => Object.freeze({
        id: ('sector.' + spec.key + '-arm'),
        displayName: spec.displayName + '争夺臂',
        role: 'contested-arm',
        nodeRefs: DEMO_2_ARM_NODE_IDS[spec.key],
    })),
    Object.freeze({
        id: 'sector.central-industry',
        displayName: '中央高价值工业环',
        role: 'central-ring',
        nodeRefs: DEMO_2_CENTRAL_NODE_IDS,
    }),
]);
export const DEMO_2_SCENARIO_AUTHORING = {
    schemaVersion: 1,
    id: 'warlord_demo_02_v1',
    rulesVersion: RULES_VERSION,
    mapRef: DEMO_2_MAP_AUTHORING.id,
    mapPresentationRef: DEMO_2_MAP_PRESENTATION.id,
    playerFactionRef: 'player',
    turnOrder: ['player', 'boss-pact-a', 'boss-independent', 'boss-pact-b'],
    factions: [
        {
            id: 'player',
            displayName: '远征军',
            controller: 'player',
            headquartersNodeRef: homeNodeId('player', 1),
            supplyNodeRef: homeNodeId('player', 2),
        },
        {
            id: 'boss-pact-a',
            displayName: '东北盟约军阀',
            controller: 'ai',
            headquartersNodeRef: homeNodeId('pact-a', 1),
            supplyNodeRef: homeNodeId('pact-a', 2),
        },
        {
            id: 'boss-independent',
            displayName: '东南独立军阀',
            controller: 'ai',
            headquartersNodeRef: homeNodeId('independent', 1),
            supplyNodeRef: homeNodeId('independent', 2),
        },
        {
            id: 'boss-pact-b',
            displayName: '西南盟约军阀',
            controller: 'ai',
            headquartersNodeRef: homeNodeId('pact-b', 1),
            supplyNodeRef: homeNodeId('pact-b', 2),
        },
    ],
    nodeRules,
    initialState: {
        nodeControls: HOME_SPECS.flatMap((spec) => HOME_NODE_ROLES.map((role) => ({
            nodeRef: homeNodeId(spec.key, role.ordinal),
            factionRef: spec.factionId,
        }))),
        standardDeployments: HOME_SPECS.flatMap((spec) => [
            {
                nodeRef: homeNodeId(spec.key, 1),
                factionRef: spec.factionId,
                cardIds: [14, 14, 12, 13, DEMO_2_COMMANDER_CARD_BY_FACTION[spec.factionId] ?? 83],
            },
            { nodeRef: homeNodeId(spec.key, 2), factionRef: spec.factionId, cardIds: [14, 15, 82] },
        ]),
        allUnitsDeployments: HOME_SPECS.flatMap((spec) => [
            {
                nodeRef: homeNodeId(spec.key, 1),
                factionRef: spec.factionId,
                cardIds: [...new Set([
                        14, 15, 82, 83, 84, 85,
                        DEMO_2_COMMANDER_CARD_BY_FACTION[spec.factionId] ?? 83,
                    ])],
            },
            { nodeRef: homeNodeId(spec.key, 2), factionRef: spec.factionId, cardIds: [12, 13, 14, 15] },
            { nodeRef: homeNodeId(spec.key, 3), factionRef: spec.factionId, cardIds: [82, 83, 84, 85] },
        ]),
    },
};
/**
 * V1 scenario authoring carries faction identity and placement, but not diplomacy.
 * The shared runtime must supply the allied relation between these two factions.
 */
export const DEMO_2_ALLIED_PACT_FACTIONS = Object.freeze([
    'boss-pact-a',
    'boss-pact-b',
]);
//# sourceMappingURL=demo2.js.map