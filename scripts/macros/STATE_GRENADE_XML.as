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
 * • 在 AttributeLoader.load() 中直接转换：FLAG_GRENADE → stateFlags |= STATE_GRENADE_XML
 * • 预置值通过 attributeInfo.stateFlags 传递，避免"污染"传播到 Obj
 * • 在 BulletInitializer.setFlagDependentDefaults 中与其他状态位合并
 *
 * 设计优势：
 * • 无需 delete Obj.FLAG_GRENADE，减少运行时开销
 * • 职责清晰：加载器负责格式转换，初始化器只做合并
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
