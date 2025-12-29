/**
 * STATE_LOCK_SHOOTER - 锁定发射者属性状态标志位
 *
 * 位掩码值：1 << 6 = 64 (二进制: 01000000)
 * 位置：stateFlags 第6位
 *
 * 功能用途：
 * • 阻断嵌套子弹的属性继承，锁定"发射瞬间"的属性快照
 * • 避免派生子弹（如炮弹/导弹爆炸）在切换模组/武器后被重新继承
 * • 保护伤害类型、魔法伤害属性、吸血、击溃、斩杀、暴击、毒/淬毒等字段
 *
 * 数据来源：
 * • 子弹 XML/脚本中设置 lockShooterAttributes = true
 * • 在 BulletInitializer.setFlagDependentDefaults 中烧录到 stateFlags
 *
 * 使用示例：
 * • 检测：(bullet.stateFlags & STATE_LOCK_SHOOTER) != 0
 * • 设置：bullet.stateFlags |= STATE_LOCK_SHOOTER
 * • 清除：bullet.stateFlags &= ~STATE_LOCK_SHOOTER
 *
 * 应用场景：
 * • BulletInitializer.inheritShooterAttributes 属性继承阻断
 * • BulletInitializer.initializeNanoToxicfunction 毒/淬毒继承阻断
 *
 * 典型使用者：
 * • 重型火箭弹、火箭弹、普通火箭弹、串联破甲火箭弹
 * • 核战斗部火箭弹、小型导弹、反坦克导弹
 * • 爆炎手里剑、榴弹、气锤地雷
 */
var STATE_LOCK_SHOOTER:Number = 1 << 6;  // 锁定发射者属性 - 位值: 64 (第6位)
