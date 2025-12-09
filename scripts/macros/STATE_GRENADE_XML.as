/**
 * STATE_GRENADE_XML - XML配置手雷标记状态标志位
 *
 * 位掩码值：1 << 4 = 16 (二进制: 00010000)
 * 位置：stateFlags 第4位
 *
 * 功能用途：
 * • 记录子弹是否通过XML配置了FLAG_GRENADE属性
 * • 区分"类型推断的手雷"与"XML强制配置的手雷"
 * • 隔离XML副作用，保持flags类型缓存的纯净性
 *
 * 数据来源：
 * • 从 Obj.FLAG_GRENADE 布尔属性烧录（XML传入）
 * • 烧录后清除 Obj.FLAG_GRENADE，消除污染
 * • 在 BulletInitializer.setFlagDependentDefaults 中写入
 *
 * 使用示例：
 * • 检测：(bullet.stateFlags & STATE_GRENADE_XML) != 0
 * • 设置：bullet.stateFlags |= STATE_GRENADE_XML
 * • 清除：bullet.stateFlags &= ~STATE_GRENADE_XML
 *
 * 应用场景：
 * • BulletInitializer 中参与 STATE_LONG_RANGE 的计算
 * • 未来可用于区分手雷类型来源的场景
 */
var STATE_GRENADE_XML:Number = 1 << 4;  // XML手雷配置 - 位值: 16 (第4位)
