/**
 * BUFF_TYPE_TO_BIT - 类型字符串到位值的映射表
 *
 * 注意: 此文件创建 Object 对象，每次 #include 都会产生运行时分配。
 * 仅用于初始化、调试、配置解析等非热路径场景。
 *
 * 热路径请使用字面量常量，参见 BuffCalculator.as 中的 addModification 实现。
 *
 * 位值定义派生自 BuffCalculator.as（单一事实源）:
 * - add:           1  (1<<0)
 * - multiply:      2  (1<<1)
 * - percent:       4  (1<<2)
 * - add_positive:  8  (1<<3)
 * - add_negative:  16 (1<<4)
 * - mult_positive: 32 (1<<5)
 * - mult_negative: 64 (1<<6)
 * - max:           128 (1<<7)
 * - min:           256 (1<<8)
 * - override:      512 (1<<9)
 *
 * 使用方式（仅限非热路径）:
 * var bit:Number = BUFF_TYPE_TO_BIT[type];
 * if (bit != undefined) typeMask |= bit;
 */
var BUFF_TYPE_TO_BIT:Object = {
    add:           1,
    multiply:      2,
    percent:       4,
    add_positive:  8,
    add_negative:  16,
    mult_positive: 32,
    mult_negative: 64,
    max:           128,
    min:           256,
    override:      512
};
