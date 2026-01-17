/**
 * BUFF_BIT_ADD_POSITIVE - 正向保守加法类型位标志
 *
 * 位掩码值: 1 << 3 = 8 (二进制: 0000001000)
 * 位置: 第3位
 *
 * 功能用途:
 * - 标识正向保守加法类型的 Buff 修改
 * - 独占型: 同类型只取最大值
 * - 用于防止同来源正向加法膨胀
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_ADD_POSITIVE) != 0
 * - 设置: typeMask |= BUFF_BIT_ADD_POSITIVE
 */
var BUFF_BIT_ADD_POSITIVE:Number = 1 << 3;
