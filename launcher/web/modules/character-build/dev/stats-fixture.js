/* Exact-shape CharacterBuildStatsSnapshot v1 fixture for browser harnesses. */
(function(root) {
    'use strict';
    function row(key, label, value, unit, displayHint) {
        return {key:key, label:label, value:value, unit:unit, displayHint:displayHint};
    }
    function group(key, label, rows) {
        return {key:key, label:label, rows:rows};
    }
    function create() {
        return {
            v:1,
            stateHealth:'ok',
            diagnostics:[],
            groups:[
                group('profile', '基础信息', [
                    row('height', '身高', 175, 'cm', 'integer'),
                    row('bodyWeight', '体重', 70, 'kg', 'integer'),
                    row('killCount', '杀敌数', 8794, '', 'integer'),
                    {key:'title', label:'称号', value:'血量很多', unit:'',
                        displayHint:'styled-text', spans:[{text:'血量很多', color:'#FFD700'}]},
                    row('level', '等级', 99, '', 'integer'),
                    row('experience', '经验值', 1211544487, '', 'integer')
                ]),
                group('encumbrance', '负重', [
                    row('equipmentWeight', '装备重量', 103, 'kg', 'number'),
                    row('lightMediumThreshold', '轻甲/中甲阈值', 71, 'kg', 'number'),
                    row('mediumHeavyThreshold', '中甲/重甲阈值', 142, 'kg', 'number'),
                    row('heavyThreshold', '最大负重', 284, 'kg', 'number'),
                    row('weightRatio', '负重比例', 0.36267605633802817, '', 'ratio-3'),
                    row('encumbranceState', '负重状态', 'normal', '', 'enum')
                ]),
                group('vitals', '生命与能量', [
                    row('maxHp', '最大HP', 3046105, '', 'integer'),
                    row('maxMp', '最大MP', 3722, '', 'integer'),
                    row('innerPower', '内力', 120, '', 'integer')
                ]),
                group('resistance', '魔法抗性', [
                    row('energyResistance', '能量抗性', 29, '', 'integer'),
                    row('heatResistance', '热抗性', 19, '', 'integer'),
                    row('corrosionResistance', '蚀抗性', 19, '', 'integer'),
                    row('poisonResistance', '毒抗性', 109, '', 'integer'),
                    row('coldResistance', '冷抗性', 19, '', 'integer'),
                    row('lightningResistance', '电抗性', 19, '', 'integer'),
                    row('waveResistance', '波抗性', 19, '', 'integer'),
                    row('impactResistance', '冲抗性', 60, '', 'integer')
                ]),
                group('defense', '防御', [
                    row('totalDefense', '综合防御力', 8264, '', 'integer'),
                    row('baseDefense', '基本防御', 664, '', 'integer'),
                    row('equipmentDefense', '装备防御', 7600, '', 'integer'),
                    row('equipmentDefenseBonus', '装备防御加成', 0, '', 'signed-integer'),
                    row('damageReduction', '减伤率', 96.4, '%', 'percent-1')
                ]),
                group('tenacity', '韧性', [
                    row('tenacityLimit', '韧性上限', 3756000, '', 'compact-number-1'),
                    row('staggerTenacity', '踉跄韧性', 1007200, '', 'compact-number-1'),
                    row('guardBreakAbility', '拆挡能力', 26, '', 'integer'),
                    row('stabilityAbility', '坚稳能力', 120, '', 'integer')
                ]),
                group('mobility', '命中与移动', [
                    row('accuracy', '命中力', 100, '', 'integer'),
                    row('evasionCost', '闪避负荷', 18, '', 'integer'),
                    row('lazyDodge', '懒闪避', 0, '%', 'percent-0'),
                    row('movementSpeed', '速度', 14.6, 'm/s', 'decimal-1')
                ]),
                group('offense', '伤害加成', [
                    row('damageBonus', '伤害加成', 1337, '', 'integer'),
                    row('unarmedBonus', '空手加成', 0, '', 'signed-integer'),
                    row('unarmedAttack', '空手攻击力', 244, '', 'integer'),
                    row('meleeBonus', '冷兵加成', 0, '', 'signed-number'),
                    row('firearmBonus', '枪械加成', 0, '', 'signed-number')
                ]),
                group('power', '武器威力', [
                    row('unarmedPower', '空手威力', 1581, '', 'integer'),
                    row('meleePower', '冷兵威力', 4374, '', 'integer'),
                    row('mainHandPower', '主手威力', 2029, '', 'integer'),
                    row('offHandPower', '副手威力', 2029, '', 'integer'),
                    row('riflePower', '长枪威力', 3473, '', 'integer'),
                    row('grenadePower', '手雷威力', 101337, '', 'integer')
                ])
            ]
        };
    }
    root.CharacterBuildStatsFixture = {create:create};
})(typeof window !== 'undefined' ? window : globalThis);
