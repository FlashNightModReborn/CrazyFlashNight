/**
 * STATE_REVERSE_KNOCKBACK - 水平击退反向状态标志位
 *
 * 位掩码值：1 << 1 = 2 (二进制: 00000010)
 * 位置：stateFlags 第1位
 *
 * 功能用途：
 * • 反转子弹命中时的水平击退方向
 * • 使目标向子弹发射方向被击退（吸引效果）
 * • 用于特殊武器如钩爪、吸引类技能
 *
 * 数据来源：
 * • 从 Obj.水平击退反向 布尔属性烧录
 * • 在 BulletInitializer.setFlagDependentDefaults 中写入
 *
 * 使用示例：
 * • 检测：(bullet.stateFlags & STATE_REVERSE_KNOCKBACK) != 0
 * • 设置：bullet.stateFlags |= STATE_REVERSE_KNOCKBACK
 * • 清除：bullet.stateFlags &= ~STATE_REVERSE_KNOCKBACK
 *
 * 应用场景：
 * • HitUpdater.doHitUpdate 击退方向计算
 */
var STATE_REVERSE_KNOCKBACK:Number = 1 << 1;  // 水平击退反向 - 位值: 2 (第1位)
