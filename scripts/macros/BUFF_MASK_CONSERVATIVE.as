/**
 * BUFF_MASK_CONSERVATIVE - 保守语义掩码
 *
 * 包含: ADD_POSITIVE, ADD_NEGATIVE, MULT_POSITIVE, MULT_NEGATIVE
 *
 * 值: 120 (二进制: 0001111000)
 *
 * 功能用途:
 * - 用于检测是否存在保守语义修改
 * - 当 (typeMask & BUFF_MASK_CONSERVATIVE) == 0 时，可以跳过极值检查
 */
var BUFF_MASK_CONSERVATIVE:Number = 120; // 8 + 16 + 32 + 64
