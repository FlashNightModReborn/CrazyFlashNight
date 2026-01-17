/**
 * BUFF_BIT_MULTIPLY - 通用乘算类型位标志
 *
 * 位掩码值: 1 << 1 = 2 (二进制: 0000000010)
 * 位置: 第1位
 *
 * 功能用途:
 * - 标识通用乘算类型的 Buff 修改
 * - 乘区相加: result = base * (1 + Σ(multiplier - 1))
 * - 有效抑制指数膨胀，3个10%增益 = 30%而非33.1%
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_MULTIPLY) != 0
 * - 设置: typeMask |= BUFF_BIT_MULTIPLY
 */
var BUFF_BIT_MULTIPLY:Number = 1 << 1;
