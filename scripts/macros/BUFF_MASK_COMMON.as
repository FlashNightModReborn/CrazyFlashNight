/**
 * BUFF_MASK_COMMON - 常用组合掩码
 *
 * 包含: ADD, MULTIPLY, PERCENT 三种最常见类型的组合
 *
 * 值: 7 (二进制: 0000000111)
 *
 * 功能用途:
 * - 用于快速路径检测
 * - 当 typeMask == BUFF_MASK_COMMON 时，可以使用优化的计算路径
 */
var BUFF_MASK_COMMON:Number = 7; // BIT_ADD | BIT_MULTIPLY | BIT_PERCENT
