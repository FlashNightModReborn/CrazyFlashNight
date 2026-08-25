export const NODE_CONFIGS = {
    'R-HQ': {
        nodeId: 'R-HQ', displayName: '红方总部', kind: 'hq', capacity: 5, attackWidth: 3,
        defenseWidth: 5, strategicValue: 5, goldIncome: 5, population: 5, apBonus: 0,
        productionSlots: 2, defenseBonus: 0, x: 90, y: 210,
    },
    'R-Supply': {
        nodeId: 'R-Supply', displayName: '红方补给', kind: 'supply', capacity: 4, attackWidth: 3,
        defenseWidth: 4, strategicValue: 3, goldIncome: 0, population: 6, apBonus: 0,
        productionSlots: 2, defenseBonus: 0, x: 250, y: 110,
    },
    'R-Economy': {
        nodeId: 'R-Economy', displayName: '红方经济', kind: 'economy', capacity: 3, attackWidth: 3,
        defenseWidth: 3, strategicValue: 2, goldIncome: 8, population: 0, apBonus: 0,
        productionSlots: 0, defenseBonus: 0, x: 250, y: 310,
    },
    'North-Choke': {
        nodeId: 'North-Choke', displayName: '北部关隘', kind: 'choke', capacity: 4, attackWidth: 2,
        defenseWidth: 4, strategicValue: 1, goldIncome: 0, population: 0, apBonus: 0,
        productionSlots: 0, defenseBonus: 0.2, x: 470, y: 70,
    },
    'Center-Command': {
        nodeId: 'Center-Command', displayName: '中央指挥', kind: 'command', capacity: 4, attackWidth: 4,
        defenseWidth: 4, strategicValue: 3, goldIncome: 0, population: 0, apBonus: 2,
        productionSlots: 0, defenseBonus: 0, x: 470, y: 210,
    },
    'South-Depot': {
        nodeId: 'South-Depot', displayName: '南部军需', kind: 'depot', capacity: 3, attackWidth: 3,
        defenseWidth: 3, strategicValue: 2, goldIncome: 6, population: 0, apBonus: 0,
        productionSlots: 0, defenseBonus: 0, x: 470, y: 350,
    },
    'B-Economy': {
        nodeId: 'B-Economy', displayName: '蓝方经济', kind: 'economy', capacity: 3, attackWidth: 3,
        defenseWidth: 3, strategicValue: 2, goldIncome: 8, population: 0, apBonus: 0,
        productionSlots: 0, defenseBonus: 0, x: 690, y: 310,
    },
    'B-Supply': {
        nodeId: 'B-Supply', displayName: '蓝方补给', kind: 'supply', capacity: 4, attackWidth: 3,
        defenseWidth: 4, strategicValue: 3, goldIncome: 0, population: 6, apBonus: 0,
        productionSlots: 2, defenseBonus: 0, x: 690, y: 110,
    },
    'B-HQ': {
        nodeId: 'B-HQ', displayName: '蓝方总部', kind: 'hq', capacity: 5, attackWidth: 3,
        defenseWidth: 5, strategicValue: 5, goldIncome: 5, population: 5, apBonus: 0,
        productionSlots: 2, defenseBonus: 0, x: 850, y: 210,
    },
};
export const MAP_EDGES = [
    { a: 'R-HQ', b: 'R-Supply' },
    { a: 'R-HQ', b: 'R-Economy' },
    { a: 'R-Supply', b: 'North-Choke' },
    { a: 'R-Supply', b: 'Center-Command' },
    { a: 'R-Economy', b: 'Center-Command' },
    { a: 'R-Economy', b: 'South-Depot' },
    { a: 'North-Choke', b: 'B-Supply' },
    { a: 'Center-Command', b: 'B-Supply' },
    { a: 'Center-Command', b: 'B-Economy' },
    { a: 'South-Depot', b: 'B-Economy' },
    { a: 'B-Supply', b: 'B-HQ' },
    { a: 'B-Economy', b: 'B-HQ' },
];
export function adjacentNodeIds(nodeId) {
    return MAP_EDGES.flatMap((edge) => {
        if (edge.a === nodeId)
            return [edge.b];
        if (edge.b === nodeId)
            return [edge.a];
        return [];
    }).sort();
}
//# sourceMappingURL=map.js.map