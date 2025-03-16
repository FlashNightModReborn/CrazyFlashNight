import org.flashNight.sara.util.*;
import org.flashNight.arki.spatial.transform.*;

/*
 * Mover 类
 * =========
 * 该类实现了2D和2.5D的移动逻辑，包括碰撞检测和碰撞挤出处理。
 *
 * 主要功能：
 *   1. move2D  - 实现纯2D移动（不考虑高度变化）
 *   2. move25D - 实现2.5D移动（带高度变化，如跳跃时）
 *   3. resolveCollision - 当移动发生碰撞时，通过计算挤出向量帮助实体摆脱障碍
 *
 * 内部结构说明：
 *   - directions2D: 存储纯2D移动的基础方向向量（仅包含水平和垂直分量）
 *   - directions25D: 存储2.5D移动的基础方向向量（包含水平、垂直及高度变化的dz分量）
 *   - globalPoint: 作为全局临时变量，用于减少重复创建 Vector 对象，主要在碰撞检测中使用
 *   - debug: 调试标志，开启后将直接调用碰撞挤出逻辑，而不进行正常移动
 */
class org.flashNight.arki.spatial.move.Mover {

    // --------------------
    // 2D方向向量（只包含水平和垂直分量）
    private static var directions2D:Object = initDirections2D();

    // 初始化2D方向向量映射表
    private static function initDirections2D():Object {
        var obj:Object = {};
        // "上": 向上移动，向量 (0, -1)
        obj["上"] = new Vector(0, -1);
        // "下": 向下移动，向量 (0, 1)
        obj["下"] = new Vector(0, 1);
        // "左": 向左移动，向量 (-1, 0)
        obj["左"] = new Vector(-1, 0);
        // "右": 向右移动，向量 (1, 0)
        obj["右"] = new Vector(1, 0);
        return obj;
    };

    // --------------------
    // 2.5D方向向量（包含水平、垂直和高度变化的dz分量）
    // 注意：此处保存的是基础值，在调用时根据是否跳跃决定是否使用dz分量
    private static var directions25D:Object = initDirections25D();

    // 初始化2.5D方向向量映射表
    private static function initDirections25D():Object {
        var obj:Object = {};
        // "上": 向上移动，基础向量 (0, -1, -1)
        obj["上"] = new Vertex3D(0, -1, -1);
        // "下": 向下移动，基础向量 (0, 1, 1)
        obj["下"] = new Vertex3D(0, 1, 1);
        // "左": 向左移动，基础向量 (-1, 0, 0)
        obj["左"] = new Vertex3D(-1, 0, 0);
        // "右": 向右移动，基础向量 (1, 0, 0)
        obj["右"] = new Vertex3D(1, 0, 0);
        return obj;
    };

    // --------------------
    // 全局临时变量，减少对象重复创建（用于2D部分）
    private static var globalPoint:Vector = new Vector(0, 0);
    // 调试标志，默认为 false；为 true 时，调用调试逻辑（直接使用碰撞挤出函数）
    private static var debug:Boolean = false;

    /*
     * 方法：move2D
     * --------------
     * 用途：实现纯2D移动（无高度变化）。
     *
     * 参数：
     *   entity    - 需要移动的 MovieClip 对象（包含 _x、_y、Z轴坐标等属性）
     *   direction - 移动方向（取值："上"、"下"、"左"、"右"）
     *   speed     - 移动速度，决定位移大小
     *
     * 移动逻辑：
     *   1. 根据 direction 查找对应的2D向量；
     *   2. 计算水平和垂直位移 (vx, vy)；
     *   3. 将实体的局部坐标转换为全局坐标，以便进行碰撞检测；
     *   4. 根据全局坐标和位移计算目标位置；
     *   5. 若目标位置无碰撞，执行移动：
     *         - 垂直移动（"上"、"下"）：更新 Z轴坐标，同时同步 _y 并调整显示层次；
     *         - 水平移动（"左"、"右"）：仅更新 _x 坐标；
     *      若发生碰撞，则调用 resolveCollision 进行挤出处理。
     */
    public static function move2D(entity:MovieClip, direction:String, speed:Number):Void {
        if (debug) {
            resolveCollision(entity, globalPoint, speed, direction);
            return;
        }
        var dir:Vector = directions2D[direction];
        if (!dir) return;
        var vx:Number = dir.x * speed;
        var vy:Number = dir.y * speed;

        // 计算实体的全局坐标
        globalPoint.setTo(entity._x, entity.Z轴坐标);
        _root.gameworld.localToGlobal(globalPoint);

        var targetX:Number = globalPoint.x + vx;
        var targetY:Number = globalPoint.y + vy;

        // 执行碰撞检测
        if (!_root.gameworld.地图.hitTest(targetX, targetY, true)) {
            if (direction == "上" || direction == "下") {
                // 垂直移动：更新Z轴和_y，并调整显示层次
                entity.Z轴坐标 += vy;
                entity._y = entity.Z轴坐标;
                entity.swapDepths(entity._y);
            } else {
                // 水平移动：仅更新_x坐标
                entity._x += vx;
            }
            return;
        }
        // 碰撞发生时调用挤出处理
        resolveCollision(entity, globalPoint, speed, direction);
    }

    /*
     * 方法：move25D
     * --------------
     * 用途：实现2.5D移动（包含高度变化）。
     *
     * 参数：
     *   entity    - 需要移动的 MovieClip 对象（必须包含 Z轴坐标属性）
     *   direction - 移动方向（取值："上"、"下"、"左"、"右"）
     *   speed     - 移动速度
     *   isJump    - 布尔值，指示是否处于跳跃状态；若为 true，则使用dz分量
     *
     * 移动逻辑：
     *   1. 根据 direction 查找对应的2.5D向量；
     *   2. 判断 isJump 决定是否使用dz分量（非跳跃状态下dz为0）；
     *   3. 将局部坐标转换为全局坐标，用于碰撞检测；
     *   4. 根据全局坐标和位移计算目标位置；
     *   5. 若目标位置无碰撞，执行移动：
     *         - 垂直移动（"上"、"下"）：更新Z轴和_y，且在跳跃时更新起始Y；
     *         - 水平移动（"左"、"右"）：仅更新 _x 坐标；
     *      若发生碰撞，则调用 resolveCollision 进行挤出处理。
     */
    public static function move25D(entity:MovieClip, direction:String, speed:Number, isJump:Boolean):Void {
        if (debug) {
            resolveCollision(entity, globalPoint, speed, direction);
            return;
        }
        var dir:Vertex3D = directions25D[direction];
        if (!dir) return;
        
        // 根据跳跃状态确定dz分量
        var dz:Number = (isJump ? dir.z : 0);
        
        // 计算全局坐标以供碰撞检测使用
        globalPoint.setTo(entity._x, entity.Z轴坐标);
        _root.gameworld.localToGlobal(globalPoint);
        
        var targetX:Number = globalPoint.x + dir.x * speed;
        var targetY:Number = globalPoint.y + dir.y * speed;
        
        // 检测目标位置是否发生碰撞
        if (!_root.gameworld.地图.hitTest(targetX, targetY, true)) {
            if (direction == "上" || direction == "下") {
                var dy:Number = dir.y * speed;
                entity.Z轴坐标 += dy;
                entity._y += dy;
                // 若处于跳跃状态，更新起始Y以便后续计算
                if (isJump) {
                    entity.起始Y += dy;
                }
                entity.swapDepths(entity._y);
            } else {
                entity._x += dir.x * speed;
            }
            return;
        }
        // 发生碰撞时，尝试通过碰撞挤出逻辑进行处理
        resolveCollision(entity, globalPoint, speed, direction);
    }

    /*
     * 方法：resolveCollision
     * -------------------------
     * 用途：当检测到目标位置发生碰撞时，通过计算挤出向量帮助实体“挤出”障碍区域，
     *       使其从碰撞状态中摆脱出来。
     *
     * 参数：
     *   entity    - 需要进行挤出处理的 MovieClip 对象
     *   globalPt  - 当前全局坐标，用于碰撞检测
     *   speed     - 当前移动速度，用于计算最小挤出步长
     *   direction - 原始移动方向（"上"、"下"、"左"、"右"）
     *
     * 挤出逻辑步骤：
     *   1. 若当前全局坐标没有碰撞，则直接返回；
     *   2. 计算中心回归向量：从实体当前位置指向场景中心，并归一化；
     *   3. 获取原始移动方向向量（若获取失败则使用零向量）；
     *   4. 根据实体与场景中心的距离计算自适应混合比率 adaptiveRatio：
     *         - 实体越靠近中心，adaptiveRatio 越大；越靠近边界，adaptiveRatio 越小；
     *   5. 对原始移动向量和中心回归向量进行线性插值，得到最终挤出向量；
     *   6. 对最终向量归一化，并乘以步长（步长取 speed 和 5 中较大值）；
     *   7. 更新实体的位置（假定 Z轴与 _y 同步），并调用 swapDepths 调整显示层次。
     */
    private static function resolveCollision(entity:MovieClip,
                                             globalPt:Vector,
                                             speed:Number,
                                             direction:String
    ):Void {
        if (!_root.gameworld.地图.hitTest(globalPt.x, globalPt.y, true)) {
            return;
        }

        // 获取实体当前局部坐标
        var point:Vector = new Vector(entity._x, entity._y);
        
        // 1. 计算中心回归向量（指向场景中心）
        var center:Vector = SceneCoordinateManager.center;
        var centerVec:Vector = center.minusNew(point);
        centerVec.normalize();
        
        // 2. 获取原始移动方向向量
        var dir2D:Vector = directions2D[direction];  
        if (!dir2D) {
            dir2D = new Vector(0, 0);
        }

        // 3. 计算自适应混合比率，根据实体与中心距离决定
        var adaptiveRatio:Number = Math.max(0, 
                                   Math.min(1, 1 - (SceneCoordinateManager.safeRadius / point.distance(center))));
        // 4. 进行线性插值混合，得到最终挤出向量
        var finalVec:Vector = dir2D.lerp(centerVec, adaptiveRatio);

        // 5. 对挤出向量归一化并乘以步长（取 speed 与 5 中较大值）
        finalVec.normalize();
        finalVec.mult(Math.max(speed, 5));
        
        // 6. 更新实体位置（更新 _x、Z轴坐标和 _y）
        entity._x += finalVec.x;
        entity.Z轴坐标 += finalVec.y;
        entity._y += finalVec.y;
        
        // 7. 调整显示层次，确保实体正确显示
        entity.swapDepths(entity._y);
    }
}
