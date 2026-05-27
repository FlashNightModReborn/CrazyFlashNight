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

    window.MercData = {
        SLOTS: SLOTS,
        SLOT_NAMES: SLOT_NAMES,
        HIRE_PER_PAGE: HIRE_PER_PAGE
    };
})();
