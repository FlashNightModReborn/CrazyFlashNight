/**
 * BUFF_MASK_BOUNDS - 边界控制掩码
 *
 * 包含: MAX, MIN, OVERRIDE 三种边界控制类型
 *
 * 值: 896 (二进制: 1110000000)
 *
 * 功能用途:
 * - 用于检测是否存在边界控制修改
 * - 当 (typeMask & BUFF_MASK_BOUNDS) == 0 时，可以跳过边界检查
 */
var BUFF_MASK_BOUNDS:Number = 896; // BIT_MAX | BIT_MIN | BIT_OVERRIDE
