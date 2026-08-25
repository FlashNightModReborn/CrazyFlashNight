// Generated from the authoritative snapshot; do not edit by hand.
const snapshot = {
    "schemaVersion": 1,
    "snapshotVersion": "warlord-card-snapshot-v0.1",
    "rulesVersion": "wargame-demo-v0.1",
    "spec": {
        "path": "docs/军阀战术演习-Web-Demo-产品规格书-v0.1-draft.md",
        "sha256": "C07FA51F78852899901F6F38031663227F7067CD8E3B48CCDBF70F52417D3A18"
    },
    "snapshotExtractedAt": "2026-08-02",
    "runtimeContract": {
        "currency": "gold",
        "cardLevelMin": 1,
        "cardLevelMax": 50,
        "statInterpolationDenominator": 59,
        "difficultyStatMultiplier": 1,
        "auditOnlyFields": [
            "dodgeRate",
            "toughness",
            "magicResistance",
            "equipmentDefense",
            "weight"
        ]
    },
    "sourceFiles": [
        {
            "path": "data/merc/pets.xml",
            "sha256": "7B17B21FB1B97F56F86D9AC4D0FBEB60AF562CABD3971CFADFE6881AFB96B70A"
        },
        {
            "path": "data/units/units.json",
            "sha256": "08F64AC4730557CD5B6E090AF692540851A8BF4CF4865BFF79DC39C3824D88DE"
        },
        {
            "path": "data/enemy_properties/原版敌人 2011-2012.xml",
            "sha256": "B946C433C114C9FC1C4D884E7799FFCCE2D4AF7BC2F2017F8BD38DC72235F85A"
        },
        {
            "path": "data/enemy_properties/换皮敌人与战宠.xml",
            "sha256": "223B7C0F76D7C8A71342F59611E524469C66E36DAF47B97190262E88E2E06E0E"
        },
        {
            "path": "scripts/逻辑/单位函数/单位函数_aka_战宠进阶.as",
            "sha256": "33A7D921F3A8EF8F1083432906F89C88066F94A66FD5229E1BA79DC90E29189F"
        }
    ],
    "cards": [
        {
            "cardId": 12,
            "unitTypeId": 54,
            "identifier": "敌人-军阀狙击兵",
            "displayName": "狙击兵",
            "sourceCategory": "普通",
            "powerTier": "T1 基础兵",
            "tags": ["human"],
            "statRanges": {
                "hp": { "min": 1000, "max": 2000 },
                "unarmedAttack": { "min": 15, "max": 120 },
                "baseDefense": { "min": 100, "max": 300 },
                "speed": { "min": 18, "max": 30 }
            },
            "expRange": { "min": 46, "max": 400 },
            "auditOnlyStats": {
                "dodgeRate": { "min": 30, "max": 15 },
                "toughness": 0.6,
                "magicResistance": { "人类": 10, "统合": 10, "凡俗": 15 },
                "equipmentDefense": 0,
                "weight": 80
            },
            "allowedPromotions": ["基础训练", "强化药剂", "超级血清"],
            "productionCost": 8,
            "populationCost": 1,
            "buildRounds": 1,
            "deploymentLevel": 1,
            "behaviorId": "sniper",
            "formationRank": 3,
            "sourceRefs": [
                "data/enemy_properties/原版敌人 2011-2012.xml#敌人-军阀狙击兵",
                "data/units/units.json#id=54",
                "data/merc/pets.xml#id=12"
            ],
            "snapshotExtractedAt": "2026-08-02",
            "sourceAudit": {
                "sourceAllowedPromotions": ["基础训练", "强化药剂", "超级血清", "常驻淬毒"],
                "unitTemplate": { "level": 20, "height": 175 }
            }
        },
        {
            "cardId": 13,
            "unitTypeId": 57,
            "identifier": "敌人-军阀弹药兵",
            "displayName": "弹药兵",
            "sourceCategory": "普通",
            "powerTier": "T1 基础兵",
            "tags": ["human"],
            "statRanges": {
                "hp": { "min": 1000, "max": 2000 },
                "unarmedAttack": { "min": 15, "max": 120 },
                "baseDefense": { "min": 100, "max": 300 },
                "speed": { "min": 18, "max": 30 }
            },
            "expRange": { "min": 46, "max": 400 },
            "auditOnlyStats": {
                "dodgeRate": { "min": 30, "max": 15 },
                "toughness": 0.6,
                "magicResistance": { "人类": 20, "统合": 10, "凡俗": 10 },
                "equipmentDefense": 0,
                "weight": 100
            },
            "allowedPromotions": ["基础训练", "强化药剂", "超级血清"],
            "productionCost": 9,
            "populationCost": 1,
            "buildRounds": 1,
            "deploymentLevel": 1,
            "behaviorId": "ammo",
            "formationRank": 2,
            "sourceRefs": [
                "data/enemy_properties/原版敌人 2011-2012.xml#敌人-军阀弹药兵",
                "data/units/units.json#id=57",
                "data/merc/pets.xml#id=13"
            ],
            "snapshotExtractedAt": "2026-08-02",
            "sourceAudit": {
                "sourceAllowedPromotions": ["基础训练", "强化药剂", "超级血清", "常驻淬毒"],
                "unitTemplate": { "level": 20, "height": 175 }
            }
        },
        {
            "cardId": 14,
            "unitTypeId": 56,
            "identifier": "敌人-军阀突击兵",
            "displayName": "突击兵",
            "sourceCategory": "普通",
            "powerTier": "T1 基础兵",
            "tags": ["human"],
            "statRanges": {
                "hp": { "min": 1000, "max": 2000 },
                "unarmedAttack": { "min": 15, "max": 120 },
                "baseDefense": { "min": 100, "max": 300 },
                "speed": { "min": 18, "max": 30 }
            },
            "expRange": { "min": 46, "max": 400 },
            "auditOnlyStats": {
                "dodgeRate": { "min": 30, "max": 15 },
                "toughness": 0.8,
                "magicResistance": { "人类": 25, "统合": 15, "凡俗": 20 },
                "equipmentDefense": 0,
                "weight": 100
            },
            "allowedPromotions": ["基础训练", "强化药剂", "超级血清"],
            "productionCost": 8,
            "populationCost": 1,
            "buildRounds": 1,
            "deploymentLevel": 1,
            "behaviorId": "assault",
            "formationRank": 1,
            "sourceRefs": [
                "data/enemy_properties/原版敌人 2011-2012.xml#敌人-军阀突击兵",
                "data/units/units.json#id=56",
                "data/merc/pets.xml#id=14"
            ],
            "snapshotExtractedAt": "2026-08-02",
            "sourceAudit": {
                "sourceAllowedPromotions": ["基础训练", "强化药剂", "超级血清", "常驻淬毒"],
                "unitTemplate": { "level": 20, "height": 175 }
            }
        },
        {
            "cardId": 15,
            "unitTypeId": 55,
            "identifier": "敌人-军阀重装兵",
            "displayName": "重装兵",
            "sourceCategory": "普通",
            "powerTier": "T2 精锐级",
            "tags": ["human", "elite"],
            "statRanges": {
                "hp": { "min": 3000, "max": 6000 },
                "unarmedAttack": { "min": 60, "max": 400 },
                "baseDefense": { "min": 200, "max": 500 },
                "speed": { "min": 18, "max": 30 }
            },
            "expRange": { "min": 125, "max": 360 },
            "auditOnlyStats": {
                "dodgeRate": { "min": 20, "max": 10 },
                "toughness": 20,
                "magicResistance": { "人类": 40, "装甲": 25, "统合": 20, "精英": 20 },
                "equipmentDefense": 0,
                "weight": 200
            },
            "allowedPromotions": ["基础训练", "强化药剂", "超级血清"],
            "productionCost": 60,
            "populationCost": 2,
            "buildRounds": 2,
            "deploymentLevel": 10,
            "behaviorId": "heavy",
            "formationRank": 0,
            "sourceRefs": [
                "data/enemy_properties/原版敌人 2011-2012.xml#敌人-军阀重装兵",
                "data/units/units.json#id=55",
                "data/merc/pets.xml#id=15"
            ],
            "snapshotExtractedAt": "2026-08-02",
            "sourceAudit": {
                "sourceAllowedPromotions": ["基础训练", "强化药剂", "超级血清", "常驻淬毒"],
                "unitTemplate": { "level": 20, "height": 210 }
            }
        },
        {
            "cardId": 82,
            "unitTypeId": 264,
            "identifier": "敌人-军阀精英突击兵",
            "displayName": "精锐突击兵",
            "sourceCategory": "精锐",
            "powerTier": "T2 精锐级",
            "tags": ["human", "elite"],
            "statRanges": {
                "hp": { "min": 2800, "max": 5000 },
                "unarmedAttack": { "min": 280, "max": 550 },
                "baseDefense": { "min": 220, "max": 500 },
                "speed": { "min": 20, "max": 35 }
            },
            "expRange": { "min": 380, "max": 1300 },
            "auditOnlyStats": {
                "dodgeRate": { "min": 12, "max": 10 },
                "toughness": 7,
                "magicResistance": { "人类": 30, "统合": 20, "精英": 20 },
                "equipmentDefense": 0,
                "weight": 80
            },
            "allowedPromotions": ["强化药剂", "超级血清"],
            "productionCost": 60,
            "populationCost": 2,
            "buildRounds": 2,
            "deploymentLevel": 10,
            "behaviorId": "assault",
            "formationRank": 1,
            "sourceRefs": [
                "data/enemy_properties/换皮敌人与战宠.xml#敌人-军阀精英突击兵",
                "data/units/units.json#id=264",
                "data/merc/pets.xml#id=82"
            ],
            "snapshotExtractedAt": "2026-08-02",
            "sourceAudit": {
                "sourceAllowedPromotions": ["强化药剂", "超级血清", "常驻淬毒"],
                "unitTemplate": { "level": 30, "height": 175 }
            }
        },
        {
            "cardId": 83,
            "unitTypeId": 267,
            "identifier": "敌人-军阀精英狙击兵",
            "displayName": "精锐狙击兵",
            "sourceCategory": "精锐",
            "powerTier": "T2 精锐级",
            "tags": ["human", "elite"],
            "statRanges": {
                "hp": { "min": 2000, "max": 5000 },
                "unarmedAttack": { "min": 300, "max": 500 },
                "baseDefense": { "min": 120, "max": 360 },
                "speed": { "min": 16, "max": 30 }
            },
            "expRange": { "min": 380, "max": 1300 },
            "auditOnlyStats": {
                "dodgeRate": { "min": 30, "max": 15 },
                "toughness": 1,
                "magicResistance": { "人类": 15, "统合": 15, "精英": 15 },
                "equipmentDefense": 0,
                "weight": 80
            },
            "allowedPromotions": ["强化药剂", "超级血清"],
            "productionCost": 60,
            "populationCost": 2,
            "buildRounds": 2,
            "deploymentLevel": 10,
            "behaviorId": "sniper",
            "formationRank": 3,
            "sourceRefs": [
                "data/enemy_properties/换皮敌人与战宠.xml#敌人-军阀精英狙击兵",
                "data/units/units.json#id=267",
                "data/merc/pets.xml#id=83"
            ],
            "snapshotExtractedAt": "2026-08-02",
            "sourceAudit": {
                "sourceAllowedPromotions": ["强化药剂", "超级血清", "常驻淬毒"],
                "unitTemplate": { "level": 30, "height": 175 }
            }
        },
        {
            "cardId": 84,
            "unitTypeId": 266,
            "identifier": "敌人-军阀精英弹药兵",
            "displayName": "精锐弹药兵",
            "sourceCategory": "精锐",
            "powerTier": "T2 精锐级",
            "tags": ["human", "elite"],
            "statRanges": {
                "hp": { "min": 2500, "max": 5000 },
                "unarmedAttack": { "min": 50, "max": 250 },
                "baseDefense": { "min": 120, "max": 360 },
                "speed": { "min": 35, "max": 60 }
            },
            "expRange": { "min": 380, "max": 1300 },
            "auditOnlyStats": {
                "dodgeRate": { "min": 30, "max": 15 },
                "toughness": 1,
                "magicResistance": { "人类": 25, "统合": 15, "精英": 10 },
                "equipmentDefense": 0,
                "weight": 100
            },
            "allowedPromotions": ["强化药剂", "超级血清"],
            "productionCost": 60,
            "populationCost": 2,
            "buildRounds": 2,
            "deploymentLevel": 10,
            "behaviorId": "ammo",
            "formationRank": 2,
            "sourceRefs": [
                "data/enemy_properties/换皮敌人与战宠.xml#敌人-军阀精英弹药兵",
                "data/units/units.json#id=266",
                "data/merc/pets.xml#id=84"
            ],
            "snapshotExtractedAt": "2026-08-02",
            "sourceAudit": {
                "sourceAllowedPromotions": ["强化药剂", "超级血清", "常驻淬毒"],
                "unitTemplate": { "level": 30, "height": 175 }
            }
        },
        {
            "cardId": 85,
            "unitTypeId": 265,
            "identifier": "敌人-军阀精英重装兵",
            "displayName": "精锐重装兵",
            "sourceCategory": "精锐",
            "powerTier": "T3 Boss级",
            "tags": ["human", "elite", "boss"],
            "statRanges": {
                "hp": { "min": 7600, "max": 11000 },
                "unarmedAttack": { "min": 300, "max": 600 },
                "baseDefense": { "min": 620, "max": 950 },
                "speed": { "min": 12, "max": 18 }
            },
            "expRange": { "min": 950, "max": 2600 },
            "auditOnlyStats": {
                "dodgeRate": { "min": 10, "max": 8 },
                "toughness": 30,
                "magicResistance": { "人类": 50, "装甲": 35, "统合": 30, "精英": 30 },
                "equipmentDefense": 0,
                "weight": 200
            },
            "allowedPromotions": ["超级血清"],
            "productionCost": 180,
            "populationCost": 5,
            "buildRounds": 4,
            "deploymentLevel": 25,
            "behaviorId": "heavy",
            "formationRank": 0,
            "sourceRefs": [
                "data/enemy_properties/换皮敌人与战宠.xml#敌人-军阀精英重装兵",
                "data/units/units.json#id=265",
                "data/merc/pets.xml#id=85"
            ],
            "snapshotExtractedAt": "2026-08-02",
            "sourceAudit": {
                "sourceAllowedPromotions": ["超级血清", "凑数组的", "常驻淬毒"],
                "unitTemplate": { "level": 30, "height": 210 }
            }
        }
    ]
};
export default snapshot;
//# sourceMappingURL=warlord-cards.snapshot.js.map