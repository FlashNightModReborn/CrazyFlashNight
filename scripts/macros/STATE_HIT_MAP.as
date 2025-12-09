/**
 * STATE_HIT_MAP - 击中地图状态标志位
 * 
 * 位掩码值：1 << 5 = 32 (二进制: 00100000)
 * 位置：stateFlags 第5位
 *
 * 功能用途：
 * • 标识子弹已与地图发生碰撞
 * • 控制子弹销毁时是否播放击中地图效果
 * • 纯运行期状态，初始值应为0
 *
 * 数据来源：
 * • 在生命周期检测中动态设置（NormalBulletLifecycle.shouldDestroy）
 * • 在队列处理中动态设置（BulletQueueProcessor/BulletCancelQueueProcessor）
 * • 不从XML配置烧录，不在 setFlagDependentDefaults 中初始化
 *
 * 使用示例：
 * • 检测：(bullet.stateFlags & STATE_HIT_MAP) != 0
 * • 设置：bullet.stateFlags |= STATE_HIT_MAP
 * • 清除：bullet.stateFlags &= ~STATE_HIT_MAP
 *
 * 应用场景：
 * • NormalBulletLifecycle.shouldDestroy 地图碰撞标记
 * • DestructionFinalizer 销毁时效果判定
 * • BulletQueueProcessor 僵尸子弹防御与收尾逻辑
 */
var STATE_HIT_MAP:Number = 1 << 5;  // 击中地图标志位 - 位值: 32 (第5位)
