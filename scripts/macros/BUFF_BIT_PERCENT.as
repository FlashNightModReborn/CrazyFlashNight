/**
 * BUFF_BIT_PERCENT - 百分比类型位标志
 *
 * 位掩码值: 1 << 2 = 4 (二进制: 0000000100)
 * 位置: 第2位
 *
 * 功能用途:
 * - 标识百分比类型的 Buff 修改
 * - 乘区相加: result *= (1 + Σpercent)
 * - 在乘法之后、加法之前应用
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_PERCENT) != 0
 * - 设置: typeMask |= BUFF_BIT_PERCENT
 */
var BUFF_BIT_PERCENT:Number = 1 << 2;
