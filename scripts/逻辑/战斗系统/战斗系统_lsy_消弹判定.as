import org.flashNight.arki.component.Effect.*;

/**
 * 消除子弹系统 - 高性能子弹碰撞检测与消除（矩形碰撞版）
 *
 * 变更要点：
 * • 使用 区域定位area.getRect(_root.gameworld) 获取轴对齐矩形
 * • 将子弹注册点转换到 gameworld 坐标系，判断 (x,y) 是否落入矩形
 */
_root.消除子弹 = function(obj)
{
    if (_root.暂停) {
        return;
    }

    // —— 提取与缓存参数 ——
    var 消弹敌我属性 = obj.消弹敌我属性;
    var 消弹方向   = obj.消弹方向;
    var shootZ     = obj.shootZ;
    var Z轴攻击范围 = obj.Z轴攻击范围;
    var 区域定位area = obj.区域定位area;

    // 计算一次消弹区域在 gameworld 坐标系下的包围矩形
    // AS2 的 getRect/getBounds 返回 {xMin, xMax, yMin, yMax}
    var 游戏世界:MovieClip = _root.gameworld;
    var 区域矩形:Object = 区域定位area.getRect(游戏世界);

    // —— 宏：近战标志（按位快速跳过不可消弹的近战子弹） ——
    #include "../macros/FLAG_MELEE.as"

    // —— 主循环 ——
    for (var bullet in 游戏世界.子弹区域)
    {
        var 子弹实例 = 游戏世界.子弹区域[bullet];
        var Z轴坐标差 = 子弹实例.Z轴坐标 - shootZ;

        // 早退：Z轴范围 / 近战 / 静止
        if (Math.abs(Z轴坐标差) > Z轴攻击范围 || (子弹实例.flags & FLAG_MELEE) || 子弹实例.xmov == 0) {
            continue;
        }

        // 方向过滤（可选）
        var 子弹方向 = (子弹实例.xmov > 0) ? "右" : "左";
        if (消弹方向 and 消弹方向 != 子弹方向) {
            continue;
        }

        // 只处理“敌对子弹”
        if (消弹敌我属性 != 子弹实例.是否为敌人)
        {
            // —— 将子弹注册点坐标转换到 gameworld 坐标系 ——
            // 1) 子弹本地(0,0) -> 全局
            // 2) 全局 -> gameworld 本地
            var pt:Object = {x:0, y:0};
            子弹实例.localToGlobal(pt);
            游戏世界.globalToLocal(pt);

            // —— 点 ∈ 矩形 判断（轴对齐）——
            var isHit:Boolean = (pt.x >= 区域矩形.xMin) && (pt.x <= 区域矩形.xMax)
                            && (pt.y >= 区域矩形.yMin) && (pt.y <= 区域矩形.yMax);

            if (isHit) {
                if (obj.反弹) {
                    子弹实例.是否为敌人 = !子弹实例.是否为敌人;
                    子弹实例.xmov *= -1;
                    子弹实例._xscale *= -1;
                } else {
                    子弹实例.击中地图 = true;
                    EffectSystem.Effect(子弹实例.击中地图效果, 子弹实例._x, 子弹实例._y);
                    子弹实例.gotoAndPlay("消失");

                    if (obj.强力) {
                        #include "../macros/FLAG_PIERCE.as"
                        if (子弹实例.flags & FLAG_PIERCE) {
                            子弹实例.removeMovieClip();
                        }
                    }
                }
            }
        }
    }
};

/**
 * 消弹属性初始化（保持不变，仅说明：区域定位area 将在消除过程中用 getRect(gameworld) 求矩形）
 */
_root.消弹属性初始化 = function(消弹区域:MovieClip){
    var 消弹属性 = {
        shootZ: 消弹区域._parent._parent.Z轴坐标,
        消弹敌我属性: 消弹区域._parent._parent.是否为敌人,
        消弹方向: null,
        Z轴攻击范围: 10,
        区域定位area: 消弹区域
    };
    return 消弹属性;
};
