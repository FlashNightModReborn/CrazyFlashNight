/**
 * StateFlags - 子弹实例状态标志位定义
 *
 * 设计理念：
 * 与 flags（类型标志位）分离，专门存储实例层面的布尔属性。
 * • flags：纯类型位，由子弹种类字符串推导，可缓存
 * • stateFlags：实例状态位，由XML配置/属性初始化烧录，一次性写入
 *
 * 位分配：
 * • bit 0: STATE_NO_STUN           - 不硬直
 * • bit 1: STATE_REVERSE_KNOCKBACK - 水平击退反向
 * • bit 2: STATE_FRIENDLY_FIRE     - 友军伤害
 * • bit 3: STATE_LONG_RANGE        - 远距离不消失
 * • bit 4: STATE_GRENADE_XML       - XML配置的手雷标记
 * • bit 5-30: 保留扩展
 *
 * 使用示例：
 * • 检测：(bullet.stateFlags & STATE_NO_STUN) != 0
 * • 设置：bullet.stateFlags |= STATE_NO_STUN
 * • 清除：bullet.stateFlags &= ~STATE_NO_STUN
 *
 * 性能优势：
 * • 5个布尔属性压缩为1个Number，节省约40 bytes/bullet
 * • 位运算检测比布尔属性访问更快
 * • 副作用隔离：XML配置污染不影响类型缓存系统
 */

var STATE_NO_STUN:Number           = 1 << 0;  // 不硬直标志位 - 位值: 1 (第0位)
var STATE_REVERSE_KNOCKBACK:Number = 1 << 1;  // 水平击退反向 - 位值: 2 (第1位)
var STATE_FRIENDLY_FIRE:Number     = 1 << 2;  // 友军伤害标志 - 位值: 4 (第2位)
var STATE_LONG_RANGE:Number        = 1 << 3;  // 远距离不消失 - 位值: 8 (第3位)
var STATE_GRENADE_XML:Number       = 1 << 4;  // XML手雷配置 - 位值: 16 (第4位)
