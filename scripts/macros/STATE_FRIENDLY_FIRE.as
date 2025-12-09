/**
 * STATE_FRIENDLY_FIRE - 友军伤害状态标志位
 *
 * 位掩码值：1 << 2 = 4 (二进制: 00000100)
 * 位置：stateFlags 第2位
 *
 * 功能用途：
 * • 标识子弹可以命中友方单位
 * • 影响目标筛选：使用全体目标池而非敌方目标池
 * • 用于AOE技能、陷阱、环境伤害等
 *
 * 数据来源：
 * • 从 Obj.友军伤害 布尔属性烧录
 * • 在 BulletInitializer.setFlagDependentDefaults 中写入
 *
 * 使用示例：
 * • 检测：(bullet.stateFlags & STATE_FRIENDLY_FIRE) != 0
 * • 设置：bullet.stateFlags |= STATE_FRIENDLY_FIRE
 * • 清除：bullet.stateFlags &= ~STATE_FRIENDLY_FIRE
 *
 * 应用场景：
 * • BulletQueueProcessor.add 队列键选择
 * • TargetRetriever.getPotentialTargets 目标池选择
 */
var STATE_FRIENDLY_FIRE:Number = 1 << 2;  // 友军伤害标志 - 位值: 4 (第2位)
