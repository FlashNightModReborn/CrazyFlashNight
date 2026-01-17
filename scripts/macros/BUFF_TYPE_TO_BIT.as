/**
 * BUFF_TYPE_TO_BIT - 类型字符串到位值的映射表
 *
 * 功能用途:
 * - 用于 addModification 时快速获取类型对应的位值
 * - 避免 switch-case 或 if-else 链
 *
 * 使用方式:
 * var bit:Number = BUFF_TYPE_TO_BIT[type];
 * if (bit != undefined) typeMask |= bit;
 */
var BUFF_TYPE_TO_BIT:Object = {
    add:           1,    // 1 << 0
    multiply:      2,    // 1 << 1
    percent:       4,    // 1 << 2
    add_positive:  8,    // 1 << 3
    add_negative:  16,   // 1 << 4
    mult_positive: 32,   // 1 << 5
    mult_negative: 64,   // 1 << 6
    max:           128,  // 1 << 7
    min:           256,  // 1 << 8
    override:      512   // 1 << 9
};
