/**
 * BUFF_BIT_MULT_POSITIVE - 正向保守乘法类型位标志
 *
 * 位掩码值: 1 << 5 = 32 (二进制: 0000100000)
 * 位置: 第5位
 *
 * 功能用途:
 * - 标识正向保守乘法类型的 Buff 修改
 * - 独占型: 同类型只取最大值
 * - 用于防止同来源增益乘数膨胀
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_MULT_POSITIVE) != 0
 * - 设置: typeMask |= BUFF_BIT_MULT_POSITIVE
 */
var BUFF_BIT_MULT_POSITIVE:Number = 1 << 5;
