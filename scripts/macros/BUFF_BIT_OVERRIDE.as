/**
 * BUFF_BIT_OVERRIDE - 覆盖类型位标志
 *
 * 位掩码值: 1 << 9 = 512 (二进制: 1000000000)
 * 位置: 第9位
 *
 * 功能用途:
 * - 标识覆盖类型的 Buff 修改
 * - 直接设置为指定值，忽略所有其他计算
 * - 最后添加的覆盖生效
 *
 * 使用示例:
 * - 检测: (typeMask & BUFF_BIT_OVERRIDE) != 0
 * - 设置: typeMask |= BUFF_BIT_OVERRIDE
 */
var BUFF_BIT_OVERRIDE:Number = 1 << 9;
