import org.flashNight.sara.util.*;
import org.flashNight.arki.spatial.transform.*;

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
    private static var debug:Boolean = false;

    /**
     * 纯 2D 移动（无高度变化）
     * 根据方向与速度计算出速度向量后，调用 moveWithVector 处理移动
     * @param entity    要移动的 MovieClip 对象
     * @param direction 移动方向（"上", "下", "左", "右"）
     * @param speed     移动速度
     */
    public static function move2D(entity:MovieClip, direction:String, speed:Number):Void {
        if (debug) {
            resolveCollision(entity, globalPoint, speed, direction);
            return;
        }
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

            return;
        }

        resolveCollision(entity, globalPoint, speed, direction);
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
        if (debug) {
            resolveCollision(entity, globalPoint, speed, direction);
            return;
        }
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
                var dy:Number = dir.dy * speed;
                entity.Z轴坐标 += dy;
                entity._y += dy;
                // 跳跃状态下，更新起始Y（用于后续跳跃计算）
                if (isJump) {
                    entity.起始Y += dy;
                }
                // 调整显示层次
                entity.swapDepths(entity._y);
            } else {
                // 如果是水平移动（左或右），只更新 _x 坐标
                entity._x += dir.dx * speed;
            }
            return;
        }
        resolveCollision(entity, globalPoint, speed, direction);
    }

    /**
     * 基础的碰撞挤出逻辑 —— 根据实体离边界的距离自适应混合“中心回归向量”与“原移动方向向量”。
     * 当单位越靠近边界时，中心回归的权重越高；靠近中心时，原移动方向控制权重越高。
     * @param entity     被挤出的对象
     * @param globalPt   当前全局坐标（用于检测碰撞）
     * @param speed      当前移动速度
     * @param direction  原移动方向
     */
    private static function resolveCollision(entity:MovieClip,
                                            globalPt:Vector,
                                            speed:Number,
                                            direction:String
    ):Void {
        // 如果当前全局坐标点本身并不碰撞，则无需挤出
        if (!_root.gameworld.地图.hitTest(globalPt.x, globalPt.y, true)) {
            return;
        }

        var point:Vector = new Vector(entity._x, entity._y);
        
        // 1) 计算“中心回归向量”：从角色指向世界中心
        var center:Vector = SceneCoordinateManager.center;
        var centerVec:Vector = center.minusNew(point);
        centerVec.normalize();
        // 2) 计算“原移动方向向量”
        var dir2D:Object = directions2D[direction];  
        if (!dir2D) {
            // 若没取到，则默认一个向量 (0,0) 避免出错
            dir2D = { dx: 0, dy: 0 };
        }
        var moveVec:Vector = new Vector(dir2D.dx, dir2D.dy);

        // 3) 根据实体与中心的距离自适应计算混合比重 adaptiveRatio
        // 计算实体到中心点的距离
        var minDist:Number = point.distance(center)

        // 计算中心安全区半径
        var maxMin:Number = Math.min(_root.Xmax - _root.Xmin, _root.Ymax - _root.Ymin) / 2;

        // 计算插值系数
        var adaptiveRatio:Number = Math.max(0, Math.min(1, 1 - (maxMin / minDist)));
        // 4) 将“中心回归向量”和“原移动方向向量”按 adaptiveRatio 加权混合
        //_root.发布消息(moveVec + " " + centerVec + " adaptiveRatio: " + adaptiveRatio);
        var finalVec:Vector = moveVec.lerp(centerVec, adaptiveRatio);

        
        // 5) 归一化并乘以挤出步长（确保即使 speed 较小也能产生足够位移）
        finalVec.normalize();
        finalVec.mult(Math.max(speed, 5));
        
        // 6) 更新实体位置（这里假定 Z轴坐标与 _y 同步）
        entity._x += finalVec.x;
        entity.Z轴坐标 += finalVec.y;
        entity._y += finalVec.y;
        
        // 7) 调整显示层次，确保角色正确显示
        entity.swapDepths(entity._y);
    }

}
