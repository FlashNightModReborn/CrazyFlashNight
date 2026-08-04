(function() {
    'use strict';

    // 装备槽位定义（mercData[6..16]）
    var SLOTS = [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];

    // 装备槽位中文名
    var SLOT_NAMES = {
        6:  '头部',
        7:  '上装',
        8:  '手部',
        9:  '下装',
        10: '脚部',
        11: '颈部',
        12: '长枪',
        13: '手枪',
        14: '手枪2',
        15: '刀',
        16: '手雷'
    };

    // 每页显示数量
    var HIRE_PER_PAGE = 10;

    // 纸娃娃槽位映射：装备槽号 → dressup rig 槽名（ merc-panel.js 原
    // DRESSUP_SLOT_BY_INDEX 副本迁入，保持槽位常量单源）
    var DRESSUP_SLOT_BY_INDEX = {
        6: 'head',
        7: 'body',
        8: 'hand',
        9: 'leg',
        10: 'foot',
        11: 'neck',
        12: 'primary',
        13: 'secondary1',
        14: 'secondary2',
        15: 'melee',
        16: 'grenade'
    };

    window.MercData = {
        SLOTS: SLOTS,
        SLOT_NAMES: SLOT_NAMES,
        HIRE_PER_PAGE: HIRE_PER_PAGE,
        DRESSUP_SLOT_BY_INDEX: DRESSUP_SLOT_BY_INDEX
    };
})();
