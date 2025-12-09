/**
 * STATE_LONG_RANGE - 远距离不消失状态标志位
 *
 * 位掩码值：1 << 3 = 8 (二进制: 00001000) 
 * 位置：stateFlags 第3位
 *
 * 功能用途：
 * • 标识子弹在超出射程后不自动销毁
 * • 用于手雷、爆炸类子弹，确保到达目标位置
 * • 子弹生命周期管理的关键标志
 *
 * 数据来源（多源合并）：
 * • Obj.远距离不消失 布尔属性（外部预设）
 * • (flags & (FLAG_GRENADE | FLAG_EXPLOSIVE)) != 0（类型推断）
 * • (stateFlags & STATE_GRENADE_XML) != 0（XML配置）
 * • 在 BulletInitializer.setFlagDependentDefaults 中合并写入
 *
 * 使用示例：
 * • 检测：(bullet.stateFlags & STATE_LONG_RANGE) != 0
 * • 设置：bullet.stateFlags |= STATE_LONG_RANGE
 * • 清除：bullet.stateFlags &= ~STATE_LONG_RANGE
 *
 * 应用场景：
 * • NormalBulletLifecycle.shouldDestroy 射程检测
 */
var STATE_LONG_RANGE:Number = 1 << 3;  // 远距离不消失 - 位值: 8 (第3位)
