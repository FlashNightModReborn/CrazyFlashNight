import org.flashNight.sara.util.*;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;

/**
 * org.flashNight.arki.spatial.move.Mover
 * 
 * 提供统一的移动工具方法：
 * - move2D：处理纯 2D 移动
 * - move25D：处理带高度变化的 2.5D 移动（例如跳跃、浮空等）
 *
 * 优化说明：
 * 1. 将方向向量提前定义为静态属性，避免每次调用时重复创建。
 * 2. 利用 SceneCoordinateManager.getOffset() 获取全局偏移量，减少局部与全局坐标转换的开销。
 * 3. 内部采用静态临时变量复用 Vector 和 Vertex3D 对象，减少垃圾对象产生。
 * 4. 新增 moveWithVector 与 moveWithVertex 两个通用方法，move2D 与 move25D 仅作为封装。
 */
class org.flashNight.arki.spatial.move.Mover {
    
    // --------------------
    // 静态方向向量（2D）—仅包含 dx, dy
    private static var directions2D:Object = {
        "上":  { dx: 0, dy: -1 },
        "下":  { dx: 0, dy:  1 },
        "左":  { dx: -1, dy: 0 },
        "右":  { dx: 1, dy: 0 }
    };

    // 静态方向向量（2.5D）—包含 dx, dy, dz（跳跃时 dz 有效）
    // 注意：这里保存的是基础值，调用时根据 isJump 参数决定是否采用 dz
    private static var directions25D:Object = {
        "上":  { dx: 0, dy: -1, dz: -1 },
        "下":  { dx: 0, dy:  1, dz:  1 },
        "左":  { dx: -1, dy: 0, dz: 0 },
        "右":  { dx: 1, dy: 0, dz: 0 }
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
        // 直接计算目标坐标
        var targetX:Number = entity._x + velocity.x;
        var targetY:Number = entity._y + velocity.y;

        // 利用全局偏移量（直接获取预先计算好的 offset）
        var offset:Vector = SceneCoordinateManager.getOffset();
        var globalX:Number = targetX + offset.x;
        var globalY:Number = targetY + offset.y;

        // 碰撞检测通过则更新实体坐标
        if (!_root.gameworld.地图.hitTest(globalX, globalY, true)) {
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
        // 直接计算目标坐标（x, y, z）
        var targetX:Number = entity._x + velocity.x;
        var targetY:Number = entity._y + velocity.y;
        var targetZ:Number = entity.Z轴坐标 + velocity.z;

        // 获取全局偏移量，仅用于 x, y 坐标的全局校正
        var offset:Vector = SceneCoordinateManager.getOffset();
        var globalX:Number = targetX + offset.x;
        var globalY:Number = targetY + offset.y;

        // 碰撞检测通过则更新坐标与深度
        if (!_root.gameworld.地图.hitTest(globalX, globalY, true)) {
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

        // 利用静态临时变量计算速度向量
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

        // 根据 isJump 决定是否采用 dz 分量
        var dz:Number = (isJump ? dir.dz : 0);
        // 利用静态临时变量计算 2.5D 速度向量
        tmpVelocity3D.setTo(dir.dx * speed, dir.dy * speed, dz * speed);
        moveWithVertex(entity, tmpVelocity3D);
    }
}
