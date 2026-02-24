/**
 * FLAG_RAY - 射线子弹类型标志位
 *
 * 位掩码值：1 << 8 = 256 (二进制: 100000000)
 * 位置：第8位
 *
 * 功能用途：
 * • 标识射线类型子弹，如磁暴攻击、激光射线、闪电链等
 * • 单帧检测：射线子弹在发射瞬间完成全部碰撞检测，命中最近目标
 * • 碰撞检测：使用 RayCollider 进行射线-AABB相交检测
 * • 视觉独立：电弧/激光视觉效果独立于碰撞检测生命周期
 * • 配置驱动：通过 XML 的 <rayConfig> 节点配置射程、电弧外观等参数
 *
 * 使用示例：
 * • 检测：(bullet.flags & FLAG_RAY) != 0
 * • 设置：bullet.flags |= FLAG_RAY
 * • 清除：bullet.flags &= ~FLAG_RAY
 *
 * 应用场景：
 * • AttributeLoader 解析 <rayConfig> 时自动设置此标志
 * • BulletFactory 选择 TeslaRayLifecycle 生命周期
 * • BulletQueueProcessor 中的射线窄相碰撞分支
 * • RayVfxManager 射线视觉效果渲染（支持 Tesla/Prism/Spectrum/Wave 风格）
 */
var FLAG_RAY:Number = 1 << 8;  // 射线标志位 - 位值: 256 (第8位)
