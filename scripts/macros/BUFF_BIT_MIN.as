/**
 * BUFF_BIT_MIN - 最大封顶类型位标志
 *
 * 位掩码值: 1 << 8 = 256 (二进制: 0100000000)
 * 位置: 第8位
 *
 * 功能用途:
 * - 标识最大封顶类型的 Buff 修改
 * - 确保结果不超过指定值: result = Math.min(result, value)
 * - 所有MIN值中取最小值作为上限
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_MIN) != 0
 * - 设置: typeMask |= BUFF_BIT_MIN
 */
var BUFF_BIT_MIN:Number = 1 << 8;
