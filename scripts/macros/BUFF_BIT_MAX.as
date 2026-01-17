/**
 * BUFF_BIT_MAX - 最小保底类型位标志
 *
 * 位掩码值: 1 << 7 = 128 (二进制: 0010000000)
 * 位置: 第7位
 *
 * 功能用途:
 * - 标识最小保底类型的 Buff 修改
 * - 确保结果不低于指定值: result = Math.max(result, value)
 * - 所有MAX值中取最大值作为下限
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_MAX) != 0
 * - 设置: typeMask |= BUFF_BIT_MAX
 */
var BUFF_BIT_MAX:Number = 1 << 7;
