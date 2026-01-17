/**
 * BUFF_BIT_ADD_NEGATIVE - 负向保守加法类型位标志
 *
 * 位掩码值: 1 << 4 = 16 (二进制: 0000010000)
 * 位置: 第4位
 *
 * 功能用途:
 * - 标识负向保守加法类型的 Buff 修改
 * - 独占型: 同类型只取最小值
 * - 用于防止同来源负向debuff膨胀
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_ADD_NEGATIVE) != 0
 * - 设置: typeMask |= BUFF_BIT_ADD_NEGATIVE
 */
var BUFF_BIT_ADD_NEGATIVE:Number = 1 << 4;
