/**
 * FLAG_UNIT_BULLET - 可拦截单位子弹类型标志位
 *
 * 位掩码值：1 << 9 = 512 (二进制: 1000000000)
 * 位置：第9位
 *
 * 功能用途：
 * • 标识可被拦截的单位子弹（如重型炮弹、导弹等）
 * • 子弹同时具备单位属性，可被其他子弹命中并击毁
 * • 挂载到 gameworld 层（非子弹区域），满足 initializeUnit 的 _parent 校验
 * • 使用 element 自引用走地图元件分支，hitPoint 控制击毁次数
 *
 * 使用示例：
 * • 检测：(bullet.flags & FLAG_UNIT_BULLET) != 0
 * • 设置：bullet.flags |= FLAG_UNIT_BULLET
 * • 清除：bullet.flags &= ~FLAG_UNIT_BULLET
 *
 * 互斥性：
 * • 与 FLAG_TRANSPARENCY / FLAG_RAY 互斥（必须是实体 MovieClip）
 */
var FLAG_UNIT_BULLET:Number = 1 << 9;  // 单位子弹标志位 - 位值: 512 (第9位)
