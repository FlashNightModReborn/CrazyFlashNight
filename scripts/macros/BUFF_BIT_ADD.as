/**
 * BUFF_BIT_ADD - 通用加算类型位标志
 *
 * 位掩码值: 1 << 0 = 1 (二进制: 0000000001)
 * 位置: 第0位
 *
 * 功能用途:
 * - 标识通用加算类型的 Buff 修改
 * - 累加所有值: result += Σvalue
 * - 适用于固定数值加成，如装备基础属性叠加
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_ADD) != 0
 * - 设置: typeMask |= BUFF_BIT_ADD
 */
var BUFF_BIT_ADD:Number = 1 << 0;
