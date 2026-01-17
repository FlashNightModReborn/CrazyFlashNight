/**
 * BUFF_BIT_MULT_NEGATIVE - 负向保守乘法类型位标志
 *
 * 位掩码值: 1 << 6 = 64 (二进制: 0001000000)
 * 位置: 第6位
 *
 * 功能用途:
 * - 标识负向保守乘法类型的 Buff 修改
 * - 独占型: 同类型只取最小值
 * - 用于防止同来源减益乘数膨胀
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_MULT_NEGATIVE) != 0
 * - 设置: typeMask |= BUFF_BIT_MULT_NEGATIVE
 */
var BUFF_BIT_MULT_NEGATIVE:Number = 1 << 6;
