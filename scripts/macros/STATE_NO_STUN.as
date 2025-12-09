/**
 * STATE_NO_STUN - 不硬直状态标志位
 *
 * 位掩码值：1 << 0 = 1 (二进制: 00000001)
 * 位置：stateFlags 第0位（最低位）
 *
 * 功能用途：
 * • 标识子弹命中时不触发攻击者硬直效果
 * • 允许连续快速攻击，不受硬直间隔限制
 * • 通常用于特殊技能或装备的子弹
 *
 * 数据来源：
 * • 从 Obj.不硬直 布尔属性烧录
 * • 在 BulletInitializer.setFlagDependentDefaults 中写入
 *
 * 使用示例：
 * • 检测：(bullet.stateFlags & STATE_NO_STUN) != 0
 * • 设置：bullet.stateFlags |= STATE_NO_STUN
 * • 清除：bullet.stateFlags &= ~STATE_NO_STUN
 *
 * 应用场景：
 * • BasePostHitFinalizer.processHardening 硬直判定
 * • BulletQueueProcessor 命中循环中的 shouldStun 计算
 */
var STATE_NO_STUN:Number = 1 << 0;  // 不硬直标志位 - 位值: 1 (第0位)
