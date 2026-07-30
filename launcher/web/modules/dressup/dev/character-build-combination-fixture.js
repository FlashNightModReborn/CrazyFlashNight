/**
 * B0 角色构筑纸娃娃组合样本。
 *
 * 这里只冻结可重复的真实物品名与槽位语义；投影字段始终从现役
 * assets/dressup/manifest.json 读取，避免把 bake 结果复制成第二份真相。
 */
var CharacterBuildDressupFixture = (function() {
    'use strict';

    var equipment = {
        head: '精致战术猪鼻式防毒面具',
        neck: 'A兵团精致项链',
        upper: 'A兵团精致战术背心',
        hands: 'A兵团精致战术手套',
        lower: 'A兵团精致战术裤',
        feet: 'A兵团精致战术皮鞋',
        longGun: 'HK416战术版',
        pistol: '极品UZI战术版',
        blade: '战术黑刀',
        grenade: '战术核弹手雷',
        femaleFallbackUpper: '米色高腰背心'
    };

    return {
        manifestUrl: 'assets/dressup/manifest.json',
        equipment: equipment,
        armorSlots: [
            {id:'head', label:'头部', item:equipment.head},
            {id:'neck', label:'颈部', item:equipment.neck},
            {id:'upper', label:'上装', item:equipment.upper},
            {id:'hands', label:'手部', item:equipment.hands},
            {id:'lower', label:'下装', item:equipment.lower},
            {id:'feet', label:'脚部', item:equipment.feet}
        ],
        appearanceByGender: {
            '男': {
                '脸型': '男变装-基本脸型',
                '发型': '发型-男式-黑韩式头'
            },
            '女': {
                '脸型': '女变装-基本脸型',
                '发型': '发型-女式-银色清爽直发'
            }
        },
        scenarios: {
            longGun: {
                id:'long-gun',
                label:'长枪站立',
                stateLabel:'长枪站立',
                attackMode:'长枪',
                targetSlot:'长枪'
            },
            dualPistol: {
                id:'dual-pistol',
                label:'双枪站立',
                stateLabel:'双枪站立',
                attackMode:'双枪',
                targetSlot:'手枪'
            },
            pistol: {
                id:'pistol',
                label:'手枪站立',
                stateLabel:'手枪站立',
                attackMode:'手枪',
                targetSlot:'手枪',
                clearSlots:['手枪2']
            },
            pistol2: {
                id:'pistol-2',
                label:'手枪2站立',
                stateLabel:'手枪2站立',
                attackMode:'手枪2',
                targetSlot:'手枪2',
                clearSlots:['手枪']
            },
            blade: {
                id:'blade',
                label:'兵器站立',
                stateLabel:'兵器站立',
                attackMode:'兵器',
                targetSlot:'刀'
            },
            empty: {
                id:'empty',
                label:'空手站立',
                stateLabel:'空手站立',
                attackMode:'空手',
                targetSlot:'头部装备',
                clearSlots:['长枪','手枪','手枪2','刀']
            },
            grenadeCombined: {
                id:'grenade-combined',
                label:'手雷站立',
                stateLabel:'手雷站立',
                attackMode:'手雷',
                targetSlot:'手雷'
            },
            femaleArmFallback: {
                id:'female-arm-fallback',
                label:'女性裸臂兜底',
                stateLabel:'空手站立',
                attackMode:'空手',
                targetSlot:'上装装备',
                clearSlots:['长枪','手枪','手枪2','刀'],
                equipmentOverrides:{upper:equipment.femaleFallbackUpper}
            },
            candidate: {
                id:'candidate-overlay',
                label:'候选长枪覆盖',
                stateLabel:'长枪站立',
                attackMode:'长枪',
                targetSlot:'长枪',
                candidateItem:'M4A1战术版'
            }
        }
    };
})();
