import org.flashNight.sara.util.*;

class org.flashNight.arki.spatial.move.Mover {
    
    // --------------------
    // 静态方向向量（2D）—仅包含 dx, dy
    private static var directions2D:Object = {
        上:  { dx: 0, dy: -1 },
        下:  { dx: 0, dy:  1 },
        左:  { dx: -1, dy: 0 },
        右:  { dx: 1, dy: 0 }
    };

    // 静态方向向量（2.5D）—包含 dx, dy, dz（跳跃时 dz 有效）
    // 注意：这里保存的是基础值，调用时根据 isJump 参数决定是否采用 dz
    private static var directions25D:Object = {
        上:  { dx: 0, dy: -1, dz: -1 },
        下:  { dx: 0, dy:  1, dz:  1 },
        左:  { dx: -1, dy: 0, dz: 0 },
        右:  { dx: 1, dy: 0, dz: 0 }
    };

    // --------------------
    // 静态临时变量，复用以减少对象创建（2D 部分）
    private static var globalPoint:Vector = new Vector(0, 0);

    /**
     * 纯 2D 移动（无高度变化）
     * 根据方向与速度计算出速度向量后，调用 moveWithVector 处理移动
     * @param entity    要移动的 MovieClip 对象
     * @param direction 移动方向（"上", "下", "左", "右"）
     * @param speed     移动速度
     */
    public static function move2D(entity:MovieClip, direction:String, speed:Number):Void {
        // 先根据方向获取 dx, dy
        var dir:Object = directions2D[direction];
        if (!dir) return;
        var vx = dir.dx * speed;
        var vy = dir.dy * speed;

        // 计算碰撞检测用的全局坐标
        globalPoint.setTo(entity._x, entity.Z轴坐标);
        _root.gameworld.localToGlobal(globalPoint);

        var targetX = globalPoint.x + vx;
        var targetY = globalPoint.y + vy;

        // 碰撞检测
        if (!_root.gameworld.地图.hitTest(targetX, targetY, true)) {
            
            if (direction == "上" || direction == "下") {
                // 垂直移动只改 Z轴坐标
                entity.Z轴坐标 += vy;
                entity._y = entity.Z轴坐标;
                entity.swapDepths(entity._y);
            } else {
                // 水平移动只改 _x
                entity._x += vx;
            }
        }
    }


    /**
     * 2.5D 移动（带高度变化）
     * 根据方向与速度计算出 2.5D 速度向量后，调用 moveWithVertex 处理移动
     * @param entity    要移动的 MovieClip 对象，需含 Z轴坐标属性
     * @param direction 移动方向（"上", "下", "左", "右"）
     * @param speed     移动速度
     * @param isJump    是否处于跳跃/高度变化状态，true 表示需要更新高度
     */
    public static function move25D(entity:MovieClip, direction:String, speed:Number, isJump:Boolean):Void {
        var dir:Object = directions25D[direction];
        if (!dir) return;
        
        // 计算跳跃时的 dz 分量，非跳跃状态下 dz 为 0
        var dz:Number = (isJump ? dir.dz : 0);
        
        // 使用局部坐标转换为全局坐标（用于碰撞检测）
        globalPoint.setTo(entity._x, entity.Z轴坐标);
        _root.gameworld.localToGlobal(globalPoint);
        
        // 根据方向计算目标全局坐标
        var targetX:Number = globalPoint.x + dir.dx * speed;
        var targetY:Number = globalPoint.y + dir.dy * speed;
        
        // 碰撞检测
        if (!_root.gameworld.地图.hitTest(targetX, targetY, true)) {
            // 如果是垂直方向移动（上或下），走跳跃/高度变化逻辑
            if (direction == "上" || direction == "下") {
                // 更新垂直轴：旧代码中只操作 Z轴坐标，再同步 _y
                entity.Z轴坐标 += dir.dy * speed;
                entity._y = entity.Z轴坐标;
                // 跳跃状态下，更新起始Y（用于后续跳跃计算）
                if (isJump) {
                    entity.起始Y += dz * speed;
                }
                // 调整显示层次
                entity.swapDepths(entity._y);
            } else {
                // 如果是水平移动（左或右），只更新 _x 坐标
                entity._x += dir.dx * speed;
            }
        }
    }

}
