/**
 * StateFlags - 子弹实例状态标志位 (整包引入)
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
 * • bit 5: STATE_HIT_MAP           - 击中地图（运行期状态）
 * • bit 6-30: 保留扩展
 *
 * 使用方式：
 * • 整包引入：#include "StateFlags.as" (注入全部6个常量)
 * • 按需引入：#include "STATE_NO_STUN.as" (只注入需要的常量)
 *
 * 推荐：按需引入，避免无谓的变量声明开销
 *
 * 使用示例：
 * • 检测：(bullet.stateFlags & STATE_NO_STUN) != 0
 * • 设置：bullet.stateFlags |= STATE_NO_STUN
 * • 清除：bullet.stateFlags &= ~STATE_NO_STUN
 *
 * 性能优势：
 * • 6个布尔属性压缩为1个Number，节省约48 bytes/bullet
 * • 位运算检测比布尔属性访问更快
 * • 副作用隔离：XML配置污染不影响类型缓存系统
 */

// 整包引入：将6个状态位常量全部注入当前作用域
#include "STATE_NO_STUN.as"
#include "STATE_REVERSE_KNOCKBACK.as"
#include "STATE_FRIENDLY_FIRE.as"
#include "STATE_LONG_RANGE.as"
#include "STATE_GRENADE_XML.as"
#include "STATE_HIT_MAP.as"
