/**
 * FLAG_EXPLOSIVE - 爆炸子弹类型标志位
 * 
 * 位掩码值：1 << 5 = 32 (二进制: 00100000)
 * 位置：第5位
 * 
 * 功能用途：
 * • 标识爆炸类型子弹，如火箭弹、爆炸箭、炸弹等
 * • 远距离不消失：爆炸子弹在远距离仍保持活跃，确保爆炸效果触发
 * • 范围伤害：爆炸类型通常具有区域伤害效果，影响多个目标
 * • 普通分类排斥：爆炸子弹与穿刺类型互斥，不归类为普通类型
 * • 特殊效果：爆炸通常伴随视觉特效和音效，增强游戏体验
 * • 组合检测：常与FLAG_GRENADE组合，支持手雷爆炸复合类型
 * 
 * 使用示例：
 * • 检测：(bullet.flags & FLAG_EXPLOSIVE) != 0
 * • 设置：bullet.flags |= FLAG_EXPLOSIVE
 * • 清除：bullet.flags &= ~FLAG_EXPLOSIVE
 * 
 * 应用场景：
 * • 子弹初始化的远距离不消失属性设置
 * • 组合掩码检测：(flags & (FLAG_GRENADE | FLAG_EXPLOSIVE))
 * • 普通子弹分类的排除条件：!isPierce && !isExplosive
 * • 爆炸系统和范围伤害的触发标识
 */
var FLAG_EXPLOSIVE:Number    = 1 << 5;  // 爆炸标志位 - 位值: 32 (第5位)