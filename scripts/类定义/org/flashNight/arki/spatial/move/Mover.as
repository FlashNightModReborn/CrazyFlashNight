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
    private static var tmpVelocity2D:Vector = new Vector(0, 0);
    
    // 静态临时变量，复用以减少对象创建（2.5D 部分）
    private static var tmpVelocity3D:Vertex3D = new Vertex3D(0, 0, 0);

    /**
     * 根据传入的 2D 速度向量移动实体
     * @param entity   要移动的 MovieClip 对象
     * @param velocity 速度向量（Vector 对象）
     */
    public static function moveWithVector(entity:MovieClip, velocity:Vector):Void {
        // 计算目标局部坐标
        var targetX:Number = entity._x + velocity.x;
        var targetY:Number = entity._y + velocity.y;
        
        // 使用 localToGlobal 转换为全局坐标（用于碰撞检测）
        var globalPoint:Object = { x: targetX, y: targetY };
        _root.gameworld.localToGlobal(globalPoint);
        
        // 如果全局坐标无碰撞，则更新实体的局部坐标
        if (!_root.gameworld.地图.hitTest(globalPoint.x, globalPoint.y, true)) {
            entity._x = targetX;
            entity._y = targetY;
        }
    }

    /**
     * 根据传入的 2.5D 速度向量移动实体
     * @param entity   要移动的 MovieClip 对象（需含 Z轴坐标属性）
     * @param velocity 速度向量（Vertex3D 对象）
     */
    public static function moveWithVertex(entity:MovieClip, velocity:Vertex3D):Void {
        // 计算目标局部坐标（x, y, z）
        var targetX:Number = entity._x + velocity.x;
        var targetY:Number = entity._y + velocity.y;
        var targetZ:Number = entity.Z轴坐标 + velocity.z;
        
        // 使用 localToGlobal 转换目标 (x, y) 坐标为全局坐标
        var globalPoint:Object = { x: targetX, y: targetY };
        _root.gameworld.localToGlobal(globalPoint);
        
        // 如果全局坐标无碰撞，则更新实体坐标、Z轴及显示层级
        if (!_root.gameworld.地图.hitTest(globalPoint.x, globalPoint.y, true)) {
            entity._x = targetX;
            entity._y = targetY;
            entity.Z轴坐标 = targetZ;
            entity.swapDepths(targetY);
        }
    }

    /**
     * 纯 2D 移动（无高度变化）
     * 根据方向与速度计算出速度向量后，调用 moveWithVector 处理移动
     * @param entity    要移动的 MovieClip 对象
     * @param direction 移动方向（"上", "下", "左", "右"）
     * @param speed     移动速度
     */
    public static function move2D(entity:MovieClip, direction:String, speed:Number):Void {
        var dir:Object = directions2D[direction];
        if (!dir) return;
        
        // 计算速度向量，并复用静态临时变量
        tmpVelocity2D.setTo(dir.dx * speed, dir.dy * speed);
        moveWithVector(entity, tmpVelocity2D);
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
        
        // 根据 isJump 决定是否使用 dz 分量
        var dz:Number = (isJump ? dir.dz : 0);
        // 计算 2.5D 速度向量，复用静态临时变量
        tmpVelocity3D.setTo(dir.dx * speed, dir.dy * speed, dz * speed);
        moveWithVertex(entity, tmpVelocity3D);
    }
}
