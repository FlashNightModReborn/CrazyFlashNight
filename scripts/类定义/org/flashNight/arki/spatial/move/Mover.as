import org.flashNight.sara.util.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Effect.*;

/*
 * Mover 类 - 2D 与 2.5D 移动逻辑处理
 * --------------------------------------------------
 * 本类用于处理游戏实体的移动逻辑，涵盖：
 *   - 纯2D移动（不涉及高度变化）：方法 move2D
 *   - 2.5D移动（包含高度变化，例如跳跃效果）：方法 move25D
 *
 * 在移动过程中，类内部实现了碰撞检测与碰撞挤出处理（resolveCollision），
 * 以确保实体在遇到障碍时能够自动调整位置、避免重叠。
 *
 * 内部关键变量说明：
 *   - directions2D: 存储纯2D移动基础方向向量（仅含水平与垂直分量），键为中文方向字符串。
 *   - directions25D: 存储2.5D移动基础方向向量（包含水平、垂直及高度变化 dz 分量），键为中文方向字符串。
 */
class org.flashNight.arki.spatial.move.Mover {

    // --------------------
    // 纯2D方向向量（仅水平和垂直分量）
    private static var directions2D:Object;

    /**
     * 初始化2D方向向量映射表
     *
     * 构造一个 Object 对象，将中文方向（"上"、"下"、"左"、"右"）映射到对应的 Vector 实例，
     * 每个 Vector 对象仅包含水平和垂直分量，用于纯2D移动时的方向控制。
     *
     * @return Object 方向字符串到 Vector 实例的映射表
     */
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
    // 2.5D方向向量（包含水平、垂直及高度变化的 dz 分量）
    private static var directions25D:Object;

    // 8向移动方向向量（用于可行走检测）
    private static var directions8:Object = initDirections8();

    /**
     * 初始化8向移动方向向量映射表
     *
     * 构造一个 Object 对象，将中文八个方向（"上"、"下"、"左"、"右"、
     * "左上"、"右上"、"左下"、"右下"）映射到对应的 Vector 实例。
     *
     * @return Object 方向字符串到 Vector 实例的映射表
     */
    private static function initDirections8():Object {
        var obj:Object = {};
        // 基础四方向
        obj["上"] = new Vector(0, -1);
        obj["下"] = new Vector(0, 1);
        obj["左"] = new Vector(-1, 0);
        obj["右"] = new Vector(1, 0);

        // 斜向四方向（向量需要归一化，以保证斜向移动速度一致）
        var diagonalFactor:Number = 1 / Math.sqrt(2); // 约等于 0.707
        obj["左上"] = new Vector(-diagonalFactor, -diagonalFactor);
        obj["右上"] = new Vector(diagonalFactor, -diagonalFactor);
        obj["左下"] = new Vector(-diagonalFactor, diagonalFactor);
        obj["右下"] = new Vector(diagonalFactor, diagonalFactor);
        
        return obj;
    };


    /**
     * 初始化2.5D方向向量映射表
     *
     * 构造一个 Object 对象，将中文方向（"上"、"下"、"左"、"右"）映射到对应的 Vertex3D 实例，
     * 每个 Vertex3D 对象包含水平、垂直及高度变化（dz）分量，用于2.5D移动时的方向控制。
     * 注意：基础 dz 分量在调用时可根据跳跃等状态调整使用。
     *
     * @return Object 方向字符串到 Vertex3D 实例的映射表
     */
    private static function initDirections25D():Object {
        var obj:Object = {};

        obj["上"] = new Vertex3D(0, -1, -1);
        obj["下"] = new Vertex3D(0, 1, 1);
        obj["左"] = new Vertex3D(-1, 0, 0);
        obj["右"] = new Vertex3D(1, 0, 0);
        return obj;
    };

    public static var initTag:Boolean = false;

    /**
     * 初始化 Mover 类
     *
     * 该方法初始化 2D 与 2.5D 的方向向量映射表，并设置初始化标志，
     * 为后续的移动处理提供必要的数据支持。
     */
    public static function init():Void {
        directions2D = initDirections2D();
        directions25D = initDirections25D();
        initTag = true;
    }

    /**
     * 纯2D移动处理
     *
     * 实现基于水平与垂直位移的2D移动逻辑，主要步骤包括：
     *   1. 根据给定的 direction 查找对应的2D向量；
     *   2. 计算水平与垂直位移 (vx, vy)；
     *   3. 将实体的局部坐标转换为全局坐标，便于执行碰撞检测；
     *   4. 根据全局坐标与位移量计算目标位置；
     *   5. 如果目标位置无碰撞，则直接更新实体位置：
     *         - 对于垂直移动（"上"、"下"）：同步更新 Z轴和 _y，并调整显示层次；
     *         - 对于水平移动（"左"、"右"）：仅更新 _x 坐标；
     *      否则，调用 resolveCollision 进行碰撞挤出处理。
     *
     * @param entity 需要移动的 MovieClip 对象（必须包含 _x、_y、Z轴坐标等属性）
     * @param direction 移动方向，支持 "上"、"下"、"左"、"右"
     * @param speed 移动速度，用于计算实际位移
     */
    public static function move2D(entity:MovieClip, direction:String, speed:Number):Void {
        var dir:Vector = Mover.directions2D[direction];
        if (!dir) return;

        // _root.服务器.发布服务器消息("move2D: " + entity.起始Y);
        var vx:Number = dir.x * speed;
        var vy:Number = dir.y * speed;

        // 执行碰撞检测：若目标位置无碰撞，则更新实体位置
        if (!_root.collisionLayer.hitTest(entity._x + vx, entity.Z轴坐标 + vy, true)) {
            if (vx === 0) {
                // 垂直移动：更新 Z轴 和 _y 坐标，并调整显示层次
                entity.swapDepths(entity._y = (entity.Z轴坐标 += vy));
            } else {
                // 水平移动：仅更新 _x 坐标
                entity._x += vx;
            }

            entity.aabbCollider.updateFromUnitArea(entity);
            return;
        }
        // 若检测到碰撞，则调用碰撞挤出处理
        resolveCollision(entity, entity._x, entity.Z轴坐标, speed, dir);
    }

    /**
     * 2.5D移动处理（包含高度变化）
     *
     * 实现带有高度变化的移动逻辑，例如跳跃动作。主要步骤包括：
     *   1. 根据 direction 查找对应的2.5D向量；
     *   2. 计算水平和垂直分量的位移 (dx, dy)；
     *   3. 将实体的局部坐标转换为全局坐标，便于进行碰撞检测；
     *   4. 根据全局坐标与位移计算目标位置；
     *   5. 如果目标位置无碰撞，则根据移动方向更新实体坐标：
     *         - 对于垂直移动（"上"、"下"）：更新 Z轴、同步 _y，同时处理跳跃时的起始 Y；
     *         - 对于水平移动（"左"、"右"）：仅更新 _x 坐标；
     *      否则，调用 resolveCollision 进行碰撞挤出处理。
     *
     * @param entity 需要移动的 MovieClip 对象（必须包含 _x、_y、Z轴坐标属性）
     * @param direction 移动方向，支持 "上"、"下"、"左"、"右"
     * @param speed 移动速度，用于计算实际位移
     */
    public static function move25D(entity:MovieClip, direction:String, speed:Number):Void {
        var dir:Vertex3D = Mover.directions25D[direction];
        if (!dir) return;
        
        // 计算水平与垂直位移
        var dx:Number = dir.x * speed;
        var dy:Number = dir.y * speed;
        // _root.服务器.发布服务器消息("move25D: " + entity.起始Y);

        // 执行碰撞检测：若目标位置无碰撞，则更新实体坐标
        if (!_root.collisionLayer.hitTest(entity._x + dx, entity.Z轴坐标 + dy, true)) {
            var dz:Number = dir.z * speed;
            // 若为垂直方向移动（"上" 或 "下"），则处理跳跃/高度变化逻辑
            if (dy | dz) {
                // 更新垂直轴坐标并调整显示层次（性能关键路径）
                entity.swapDepths(
                    // 使用逗号运算符合并多步操作，确保执行顺序和参数传递
                    (
                        // [步骤1] 更新实体的 Z轴坐标，并累加 dz 到起始Y
                        //  - 先计算 Z轴坐标: 自增 dy
                        //  - 逗号运算符返回 dz，因此起始Y += dz
                        entity.起始Y += (entity.Z轴坐标 += dy, dz), 

                        // [步骤2] 更新实体的 _y 坐标（垂直位置）
                        //  - 此处 dy 是垂直偏移量，_y 是显示对象的实际坐标
                        //  - 逗号运算符最终返回 entity._y 的新值，作为 swapDepths 参数
                        entity._y += dy
                    )
                );

                // _root.发布消息(entity.起始Y)

            } else {
                // 对于水平移动（"左" 或 "右"），仅更新 _x 坐标
                entity._x += dx;
            }

            entity.aabbCollider.updateFromUnitArea(entity);
            return;
        }
        // 若检测到碰撞，则调用碰撞挤出处理
        resolveCollision(entity, entity._x, entity.Z轴坐标, speed, dir);
    }

    /**
     * 纯2D移动处理（严格碰撞检测版）
     *
     * 此方法为 move2D 的严格检测版本，针对高速移动的隧穿问题，通过增量步进机制确保碰撞检测的准确性。
     * 主要特性：
     *   - 当移动距离超过50像素时，将移动分解为多个小步骤；
     *   - 每个步骤独立进行碰撞检测，确保不会跳过中间碰撞点；
     *   - 如发现碰撞，则立即停在最后一个无碰撞的位置。
     *
     * 适用场景：高速移动或对碰撞精度要求极高的情况。
     *
     * @param entity 需要移动的 MovieClip 对象（必须包含 _x、_y、Z轴坐标等属性）
     * @param direction 移动方向，支持 "上"、"下"、"左"、"右"
     * @param speed 移动速度，用于计算实际位移
     */
    public static function move2DStrict(entity:MovieClip, direction:String, speed:Number):Void {
        var dir:Vector = Mover.directions2D[direction];
        if (!dir) return;

        // _root.发布消息("move2DStrict")

        // 计算总位移
        var vx:Number = dir.x * speed;
        var vy:Number = dir.y * speed;
        var totalDistance:Number = Math.sqrt(vx * vx + vy * vy);
        
        // 判断是否需要分步检测
        var maxStepSize:Number = 50;
        if (totalDistance <= maxStepSize) {
            // 距离较小，使用标准移动方法
            move2D(entity, direction, speed);
            return;
        }
        
        // 计算需要分步的次数
        var stepCount:Number = Math.ceil(totalDistance / maxStepSize);
        var stepX:Number = vx / stepCount;
        var stepY:Number = vy / stepCount;
        
        var gameworld:MovieClip = _root.gameworld;
        
        // 保存实体的初始位置
        var prevX:Number = entity._x;
        var prevZ:Number = entity.Z轴坐标;
        var prevY:Number = entity._y;
        
        // 增量步进检测
        for (var i:Number = 1; i <= stepCount; i++) {
            // 计算本步的目标位置
            var targetX:Number = prevX + stepX * i;
            var targetZ:Number = prevZ + stepY * i;
            
            // 检测碰撞
            if (_root.collisionLayer.hitTest(targetX, targetZ, true)) {
                // 发现碰撞，回退到上一步位置
                break;
            }
            
            // 更新实体位置
            if (stepY !== 0) {
                // 垂直移动：更新 Z轴、_y 坐标以及显示层次
                entity.Z轴坐标 = targetZ;
                entity.swapDepths(entity._y = targetZ);
            } else {
                // 水平移动：仅更新 _x 坐标
                entity._x = targetX;
            }
            
            // 更新碰撞箱
            entity.aabbCollider.updateFromUnitArea(entity);
        }
    }

    /**
     * 2.5D移动处理（严格碰撞检测版）
     *
     * 此方法为 move25D 的严格检测版本，针对高速移动的隧穿问题，通过增量步进机制确保碰撞检测的准确性。
     * 主要特性：
     *   - 当移动距离超过50像素时，将移动分解为多个小步骤；
     *   - 每个步骤独立进行碰撞检测，同时处理高度变化（dz）的累积；
     *   - 如发现碰撞，则立即停在最后一个无碰撞的位置，同时保留已移动的高度变化。
     *
     * 适用场景：需要精确碰撞检测的跳跃、冲刺等快速移动场景。
     *
     * @param entity 需要移动的 MovieClip 对象（必须包含 _x、_y、Z轴坐标属性）
     * @param direction 移动方向，支持 "上"、"下"、"左"、"右"
     * @param speed 移动速度，用于计算实际位移
     */
    public static function move25DStrict(entity:MovieClip, direction:String, speed:Number):Void {
        var dir:Vertex3D = Mover.directions25D[direction];
        if (!dir) return;
        
        // 计算总位移
        var dx:Number = dir.x * speed;
        var dy:Number = dir.y * speed;
        var dz:Number = dir.z * speed;
        
        // 计算水平位移的总距离
        var totalDistance:Number = Math.sqrt(dx * dx + dy * dy);
        
        // 判断是否需要分步检测
        var maxStepSize:Number = 50;
        if (totalDistance <= maxStepSize) {
            // 距离较小，使用标准移动方法
            move25D(entity, direction, speed);
            return;
        }
        
        // 计算需要分步的次数
        var stepCount:Number = Math.ceil(totalDistance / maxStepSize);
        var stepX:Number = dx / stepCount;
        var stepY:Number = dy / stepCount;
        var stepZ:Number = dz / stepCount;
        
        var gameworld:MovieClip = _root.gameworld;
        
        // 保存实体的初始位置
        var prevX:Number = entity._x;
        var prevZ:Number = entity.Z轴坐标;
        var prevY:Number = entity._y;
        var prev起始Y:Number = entity.起始Y;
        
        // 增量步进检测
        for (var i:Number = 1; i <= stepCount; i++) {
            // 计算本步的目标位置
            var targetX:Number = prevX + stepX * i;
            var targetZ:Number = prevZ + stepY * i;
            
            // 检测碰撞
            if (_root.collisionLayer.hitTest(targetX, targetZ, true)) {
                // 发现碰撞，回退到上一步位置
                break;
            }
            
            // 更新实体位置
            if (stepY !== 0 || stepZ !== 0) {
                // 垂直移动（包含高度变化）：更新所有相关坐标
                entity.Z轴坐标 = targetZ;
                entity._y = targetZ;
                entity.起始Y = prev起始Y + stepZ * i;
                
                // 调整显示层次，使用与原方法相同的逻辑
                entity.swapDepths(entity._y);
            } else {
                // 水平移动：仅更新 _x 坐标
                entity._x = targetX;
            }
            
            // 更新碰撞箱
            entity.aabbCollider.updateFromUnitArea(entity);
        }
    }

    /**
     * 碰撞挤出处理
     *
     * 当检测到目标位置发生碰撞时，通过计算合适的挤出向量，
     * 将实体推送至非碰撞区域，解除重叠状态。具体流程如下：
     *   1. 检查当前全局坐标是否发生碰撞（若无碰撞则提前返回）；
     *   2. 计算中心回归向量：从实体当前位置指向场景中心，并进行归一化；
     *   3. 获取原始移动方向向量（仅取水平与垂直分量）；
     *   4. 根据实体与场景中心的距离，计算自适应混合比率 adaptiveRatio：
     *         - 实体越靠近场景中心，adaptiveRatio 越大；越靠近边界，则越小；
     *   5. 对原始移动向量和中心回归向量进行线性插值，获得最终的挤出向量；
     *   6. 对最终向量进行归一化，并乘以步长（取 speed 与 5 的较大值）；
     *   7. 更新实体的位置（同步更新 _x、Z轴坐标及 _y），并调用 swapDepths 调整显示层次。
     *
     * @param entity 需要进行碰撞挤出处理的 MovieClip 对象
     * @param x 实体当前全局 x 坐标
     * @param y 实体当前全局 y 坐标
     * @param speed 当前移动速度（用于计算最小挤出步长）
     * @param dir 原始移动方向向量（仅包含水平与垂直分量）
     */
    private static function resolveCollision(entity:MovieClip,
                                             x:Number,
                                             y:Number,
                                             speed:Number,
                                             dir:Vector
    ):Void {
        if (!_root.collisionLayer.hitTest(x, y, true)) {
            // 若当前坐标无碰撞，直接返回
            return;
        }


        // 获取实体当前局部坐标
        var point:Vector = new Vector(entity._x, entity._y);
        
        // 1. 计算指向场景中心的归一化向量（中心回归向量）
        var center:Vector = SceneCoordinateManager.center;
        var centerVec:Vector = center.minusNew(point);
        centerVec.normalize();
        
        // 2. 获取原始移动方向向量（仅保留水平与垂直分量）
        var dir2D:Vector = new Vector(dir.x, dir.y);

        // 3. 根据实体与中心的距离，计算自适应混合比率
        var adaptiveRatio:Number = Math.max(0, 
                                   Math.min(1, 1 - (SceneCoordinateManager.safeRadius / point.distance(center))));
        // 4. 对原始向量和中心回归向量进行线性插值，获得最终挤出向量
        var finalVec:Vector = dir2D.lerp(centerVec, adaptiveRatio);
        // _root.发布消息(dir2D + " " + adaptiveRatio + " " + finalVec)

        // 5. 对最终向量进行归一化，并乘以步长（speed 与 5 中较大值）
        finalVec.normalize();
        finalVec.mult(Math.max(speed, 5));
        
        // 6. 更新实体位置（同步更新 _x、Z轴坐标及 _y 与碰撞箱）
        entity._x += finalVec.x;
        entity.Z轴坐标 += finalVec.y;
        entity._y += finalVec.y;
        entity.aabbCollider.updateFromUnitArea(entity);

        // 7. 调整显示层次，确保实体正确显示
        entity.swapDepths(entity._y);
    }

    /**
     * 检测给定全局坐标点是否合法（即是否未与地图发生碰撞）
     * 
     * @param globalX 点的全局X坐标（相对于主场景）
     * @param globalY 点的全局Y坐标（相对于主场景）
     * @return Boolean 如果点未发生碰撞（合法）返回 true，否则返回 false
     */
    public static function isPointValid(globalX:Number, globalY:Number):Boolean {
        // 使用地图的 hitTest 方法检测碰撞，返回取反结果
        return !_root.collisionLayer.hitTest(globalX, globalY, true);
    }

    /**
     * 方向可行走检测（轻量版）
     *
     * 用于 AI 卡死脱困等热路径：仅探测指定方向的单个点，
     * 不分配 Object / 不遍历 8 向表。
     *
     * @param entity   需要检测的 MovieClip 对象
     * @param dirX     方向X分量：-1/0/1（左/无/右）
     * @param dirZ     方向Z分量：-1/0/1（上/无/下）
     * @param distance 探测距离（像素），默认 40
     * @return Boolean 该方向的目标点是否可行走（无碰撞）
     */
    public static function isDirectionWalkable(entity:MovieClip,
                                               dirX:Number, dirZ:Number,
                                               distance:Number):Boolean {
        if (distance == null || distance <= 0) distance = 40;
        // 注意：碰撞层以 X + Z轴坐标 为准（Z轴坐标缺失时回退 _y）
        var baseZ:Number = entity.Z轴坐标;
        if (isNaN(baseZ)) baseZ = entity._y;
        var tx:Number = entity._x + dirX * distance;
        var tz:Number = baseZ + dirZ * distance;
        return Mover.isPointValid(tx, tz);
    }

    /**
     * 检测影片剪辑的当前位置是否合法（其自身坐标点是否与地图碰撞）
     * 
     * @param mc 要检测的影片剪辑（将检测其注册点的位置）
     * @return Boolean 如果未碰撞返回 true，否则返回 false
     */
    public static function isMovieClipPositionValid(mc:MovieClip):Boolean {
        // 创建包含本地坐标 (0,0) 的点对象（即影片剪辑的注册点）
        var localPoint:Vector = new Vector(0,0);
        
        // 将本地坐标转换为全局坐标（考虑所有父级的位移/缩放/旋转）
        mc.localToGlobal(localPoint);
        
        return !_root.collisionLayer.hitTest(localPoint.x, localPoint.y, true);
    }

    /**
     * 检测给定的影片剪辑是否与地图碰撞
     *
     * @param clip MovieClip 作为碰撞箱
     * @return Boolean 如果碰撞箱与地图碰撞，返回 true；否则返回 false
     */
    public static function isMovieClipValid(clip:MovieClip):Boolean {
        return !clip.hitTest(_root.collisionLayer, true);
    }


    /**
     * 将实体从非法位置（与碰撞层相交）挤出到最近的合法位置。
     *
     * 采用“同心圆放射采样”的启发式：
     * - 先检测当前位置是否合法；若合法直接返回 true；
     * - 若不合法，以给定的半径步长向外扩展，在每一圈按照角度步长采样若干方向；
     * - 第一次命中的合法采样点即刻落位并返回 true；若搜索到最大半径仍未命中，返回 false；
     *
     * 注意：本方法会同步更新 `_x`、`Z`（与 `_y`）以及 `aabbCollider`，并调用 `swapDepths` 保证显示正确；
     * 若实体没有 `aabbCollider` 字段则忽略碰撞盒同步。
     *
     * @param entity 需要被挤出的 MovieClip（要求具有 `_x`、`_y`、`Z*` 坐标属性）
     * @param maxRadius 最大搜索半径（像素，默认 180）
     * @param radiusStep 半径步长（像素，默认 8）
     * @param angleStepDeg 角度步长（度，默认 30）
     * @return Boolean 是否成功找到合法位置
     */
    public static function pushOutFromCollision(entity:MovieClip,
                                                maxRadius:Number,
                                                radiusStep:Number,
                                                angleStepDeg:Number):Boolean {
        // 默认参数
        if (maxRadius == null || maxRadius <= 0) maxRadius = 180;
        if (radiusStep == null || radiusStep <= 0) radiusStep = 8;
        if (angleStepDeg == null || angleStepDeg <= 0) angleStepDeg = 30;

        // 读取当前全局坐标（以实体注点为准）
        var baseX:Number = entity._x;
        var baseY:Number = entity.Z轴坐标 != undefined ? entity.Z轴坐标 : entity._y;

        // 当前位置若已合法，直接返回
        if (Mover.isPointValid(baseX, baseY)) {
            return true;
        }

        // 先尝试四/八方向的近邻快速探测（半径=radiusStep）
        var quickDirs:Array = [
            {x: 1,  y: 0}, {x: -1, y: 0}, {x: 0,  y: 1}, {x: 0,  y: -1},
            {x: 1,  y: 1}, {x: 1,  y: -1}, {x: -1, y: 1}, {x: -1, y: -1}
        ];
        var i:Number;
        for (i = 0; i < quickDirs.length; i++) {
            var qx:Number = baseX + quickDirs[i].x * radiusStep;
            var qy:Number = baseY + quickDirs[i].y * radiusStep;
            if (Mover.isPointValid(qx, qy)) {
                entity._x = qx;
                entity.Z轴坐标 = qy;
                entity._y = qy;
                if (entity.aabbCollider && entity.aabbCollider.updateFromUnitArea) {
                    entity.aabbCollider.updateFromUnitArea(entity);
                }
                entity.swapDepths(entity._y);
                return true;
            }
        }

        // 同心圆放射搜索
        var r:Number;
        for (r = radiusStep; r <= maxRadius; r += radiusStep) {
            var ang:Number = 0;
            while (ang < 360) {
                var rad:Number = ang * Math.PI / 180;
                var tx:Number = baseX + Math.cos(rad) * r;
                var ty:Number = baseY + Math.sin(rad) * r;

                if (Mover.isPointValid(tx, ty)) {
                    entity._x = tx;
                    entity.Z轴坐标 = ty;
                    entity._y = ty;
                    if (entity.aabbCollider && entity.aabbCollider.updateFromUnitArea) {
                        entity.aabbCollider.updateFromUnitArea(entity);
                    }
                    entity.swapDepths(entity._y);
                    return true;
                }

                ang += angleStepDeg;
            }
        }

        // 未找到合法位置，最后尝试将其钳制到屏幕边界以避免极端越界
        Mover.enforceScreenBounds(entity);
        return false;
    }

    /**
     * 强制将实体限制在屏幕/关卡范围内
     *
     * @param entity 需要限制的 MovieClip 对象，要求其具有 _x、_y、Z轴坐标、aabbCollider、swapDepths 等属性
     */
    public static function enforceScreenBounds(entity:MovieClip):Void {
        // 从全局读取边界值，确保在关卡里定义了 Xmin/Xmax/Ymin/Ymax
        var minX:Number = (_root.Xmin != undefined) ? _root.Xmin : 0;
        var maxX:Number = (_root.Xmax != undefined) ? _root.Xmax : Stage.width;
        var minY:Number = (_root.Ymin != undefined) ? _root.Ymin : 0;
        var maxY:Number = (_root.Ymax != undefined) ? _root.Ymax : Stage.height;

        // 限制水平坐标
        if (entity._x < minX) {
            entity._x = minX;
        } else if (entity._x > maxX) {
            entity._x = maxX;
        }

        // 限制垂直/高度坐标：Z轴 和 _y 保持一致
        if (entity.Z轴坐标 < minY) {
            entity.Z轴坐标 = minY;
            entity._y         = minY;
        } else if (entity.Z轴坐标 > maxY) {
            entity.Z轴坐标 = maxY;
            entity._y         = maxY;
        }

        // _root.发布消息(entity._x, entity._y, _root.Xmin, _root.Xmax, _root.Ymin, _root.Ymax);

        // 更新碰撞箱并调整显示深度
        entity.aabbCollider.updateFromUnitArea(entity);
        entity.swapDepths(entity._y);
    }

    /**
     * 八方向可行走状态检测
     *
     * 对给定的实体（单位）进行八个方向的移动检测，返回一个包含所有方向
     * 及其可行性（true/false）的对象，便于快速查询。
     *
     * @param entity 需要检测的 MovieClip 对象
     * @return Object 一个以方向字符串为键，布尔值为值的对象。
     *                例如：{ "上": true, "右上": false, "右": true, ... }
     */
    public static function getWalkableDirections(entity:MovieClip):Object {
        // 创建一个空对象，用于存储所有方向的可行走状态
        var walkableStatus:Object = {};
        // 预设的检测速度/距离
        var speed:Number = 50;

        // 遍历所有八个方向
        for (var direction in Mover.directions8) {
            // 获取当前方向对应的向量
            var dir:Vector = Mover.directions8[direction];
            
            // 计算目标点的全局坐标
            var targetX:Number = entity._x + dir.x * speed;
            var targetY:Number = entity.Z轴坐标 + dir.y * speed;

            // _root.服务器.发布服务器消息(direction + ": " + targetX + "," + targetY);
            
            // 检测目标点是否合法，并将结果 (true/false) 直接存入对象
            walkableStatus[direction] = Mover.isPointValid(targetX, targetY);
        }

        // _root.服务器.发布服务器消息("getWalkableDirections " + ObjectUtil.toString(walkableStatus));
        
        // 返回包含所有方向可行性状态的对象
        return walkableStatus;
    }

    /**
     * 直线可达性检测 + 四向 L 备选路径（先横后纵，失败再试纵后横）
     * 检测从 startEntity 到指定点坐标是否可达
     * @param startEntity 起点 MovieClip（世界坐标）
     * @param endX        终点X坐标
     * @param endY        终点Y坐标
     * @param stepSize    采样步长（像素），默认 10
     * @param debugMode   是否绘制调试线与投放调试特效（默认 false）
     *
     * 调试规则（debugMode=true 时生效）：
     *  - 直线成功：绿色直线
     *  - 直线失败：
     *      · 任一 L 成功：绿色 L（成功的那条）
     *      · 全部失败：两条 L 都画红（HV 透明度 60，VH 透明度 100），失败点落"调试用失败定位"
     */
    public static function isReachableToPoint(startEntity:MovieClip, endX:Number, endY:Number, stepSize:Number, debugMode:Boolean):Boolean {
        if (stepSize == null || stepSize <= 0) stepSize = 10;
        var DEBUG:Boolean = (debugMode == true);

        // === 世界坐标（与特效/调试层一致，假定都在 _root.gameworld）===
        var sx:Number = startEntity._x;
        var sy:Number = startEntity._y;
        var ex:Number = endX;
        var ey:Number = endY;

        // === 调试绘制层（仅在 DEBUG 时创建/清理）===
        var getDebugLayer:Function = function():MovieClip {
            var world:MovieClip = _root.gameworld ? _root.gameworld : _root;
            if (!world.ReachabilityDebug) {
                world.createEmptyMovieClip("ReachabilityDebug", world.getNextHighestDepth());
            }
            world.ReachabilityDebug.clear();
            return world.ReachabilityDebug;
        };

        var drawLine:Function = function(layer:MovieClip, x1:Number, y1:Number, x2:Number, y2:Number, color:Number, thick:Number, alpha:Number):Void {
            layer.lineStyle(thick, color, alpha);
            layer.moveTo(x1, y1);
            layer.lineTo(x2, y2);
        };

        var drawL:Function = function(layer:MovieClip, ax:Number, ay:Number, mx:Number, my:Number, bx:Number, by:Number, color:Number, thick:Number, alpha:Number):Void {
            layer.lineStyle(thick, color, alpha);
            layer.moveTo(ax, ay);
            layer.lineTo(mx, my);
            layer.lineTo(bx, by);
        };

        // 线段采样碰撞检测（失败回调返回第一个失败点）
        var checkSegment:Function = function(x0:Number, y0:Number, x1:Number, y1:Number, step:Number, onFail:Function):Boolean {
            var dx:Number = x1 - x0;
            var dy:Number = y1 - y0;
            var dist:Number = Math.sqrt(dx*dx + dy*dy);
            if (dist <= step) {
                if (!Mover.isPointValid(x1, y1)) { if (onFail) onFail(x1, y1); return false; }
                return true;
            }
            var steps:Number = Math.ceil(dist / step);
            var stepx:Number = (dx / dist) * step;
            var stepy:Number = (dy / dist) * step;

            for (var i:Number = 1; i <= steps; i++) {
                var cx:Number = x0 + stepx * i;
                var cy:Number = y0 + stepy * i;
                if (!Mover.isPointValid(cx, cy)) {
                    if (onFail) onFail(cx, cy);
                    return false;
                }
            }
            return true;
        };

        // ===== 1) 直线尝试 =====
        var dx:Number = ex - sx;
        var dy:Number = ey - sy;
        var dist:Number = Math.sqrt(dx*dx + dy*dy);

        if (dist < stepSize) {
            if (DEBUG) {
                var dl0:MovieClip = getDebugLayer();
                drawLine(dl0, sx, sy, ex, ey, 0x00FF00, 1, 100);
            }
            return true;
        }

        var straightFailX:Number = NaN, straightFailY:Number = NaN;
        var straightOK:Boolean = checkSegment(sx, sy, ex, ey, stepSize, function(fx:Number, fy:Number) {
            straightFailX = fx; straightFailY = fy;
        });

        if (straightOK) {
            if (DEBUG) {
                var dl1:MovieClip = getDebugLayer();
                drawLine(dl1, sx, sy, ex, ey, 0x00FF00, 1, 100);
            }
            return true;
        }

        // ===== 2) L 方案 A：横->纵 (HV)，中点 (ex, sy) =====
        var midHX:Number = ex, midHY:Number = sy;
        var hvFailX:Number = NaN, hvFailY:Number = NaN;

        var hvSeg1:Boolean = checkSegment(sx, sy, midHX, midHY, stepSize, function(fx:Number, fy:Number){ hvFailX = fx; hvFailY = fy; });
        if (hvSeg1 && !Mover.isPointValid(midHX, midHY)) { hvSeg1 = false; hvFailX = midHX; hvFailY = midHY; }

        var hvSeg2:Boolean = false;
        if (hvSeg1) {
            hvSeg2 = checkSegment(midHX, midHY, ex, ey, stepSize, function(fx2:Number, fy2:Number){ hvFailX = fx2; hvFailY = fy2; });
        }
        var hvOK:Boolean = hvSeg1 && hvSeg2;

        if (hvOK) {
            if (DEBUG) {
                var dl2:MovieClip = getDebugLayer();
                drawL(dl2, sx, sy, midHX, midHY, ex, ey, 0x00FF00, 1, 100);
                EffectSystem.Effect("调试用定位", sx, sy,  60, true);
                EffectSystem.Effect("调试用定位", midHX, midHY, 60, true);
                EffectSystem.Effect("调试用定位", ex, ey,  60, true);
            }
            return true;
        }

        // ===== 3) L 方案 B：纵->横 (VH)，中点 (sx, ey) =====
        var midVX:Number = sx, midVY:Number = ey;
        var vhFailX:Number = NaN, vhFailY:Number = NaN;

        var vhSeg1:Boolean = checkSegment(sx, sy, midVX, midVY, stepSize, function(fx:Number, fy:Number){ vhFailX = fx; vhFailY = fy; });
        if (vhSeg1 && !Mover.isPointValid(midVX, midVY)) { vhSeg1 = false; vhFailX = midVX; vhFailY = midVY; }

        var vhSeg2:Boolean = false;
        if (vhSeg1) {
            vhSeg2 = checkSegment(midVX, midVY, ex, ey, stepSize, function(fx2:Number, fy2:Number){ vhFailX = fx2; vhFailY = fy2; });
        }
        var vhOK:Boolean = vhSeg1 && vhSeg2;

        if (vhOK) {
            if (DEBUG) {
                var dl3ok:MovieClip = getDebugLayer();
                drawL(dl3ok, sx, sy, midVX, midVY, ex, ey, 0x00FF00, 1, 100);
                EffectSystem.Effect("调试用定位", sx, sy,  60, true);
                EffectSystem.Effect("调试用定位", midVX, midVY, 60, true);
                EffectSystem.Effect("调试用定位", ex, ey,  60, true);
            }
            return true;
        }

        // ===== 4) 全部失败：两条 L 都标红，并在失败点落标记 =====
        if (DEBUG) {
            var dl3:MovieClip = getDebugLayer();
            // HV 用较低透明度，VH 用不透明，叠加更易看
            drawL(dl3, sx, sy, midHX, midHY, ex, ey, 0xFF0000, 1, 60);
            drawL(dl3, sx, sy, midVX, midVY, ex, ey, 0xFF0000, 1, 100);

            if (!isNaN(hvFailX)) EffectSystem.Effect("调试用失败定位", hvFailX, hvFailY, 100, true);
            if (!isNaN(vhFailX)) EffectSystem.Effect("调试用失败定位", vhFailX, vhFailY, 100, true);
            if (isNaN(hvFailX) && isNaN(vhFailX) && !isNaN(straightFailX)) {
                // 兜底：至少标记直线的失败点
                EffectSystem.Effect("调试用失败定位", straightFailX, straightFailY, 100, true);
            }
        }

        return false;
    }

    /**
     * 直线可达性检测 + 四向 L 备选路径（先横后纵，失败再试纵后横）
     * @param startEntity 起点 MovieClip（世界坐标）
     * @param endEntity   终点 MovieClip（世界坐标）
     * @param stepSize    采样步长（像素），默认 10
     * @param debugMode   是否绘制调试线与投放调试特效（默认 false）
     *
     * 调试规则（debugMode=true 时生效）：
     *  - 直线成功：绿色直线
     *  - 直线失败：
     *      · 任一 L 成功：绿色 L（成功的那条）
     *      · 全部失败：两条 L 都画红（HV 透明度 60，VH 透明度 100），失败点落"调试用失败定位"
     */
    public static function isReachable(startEntity:MovieClip, endEntity:MovieClip, stepSize:Number, debugMode:Boolean):Boolean {
        return isReachableToPoint(startEntity, endEntity._x, endEntity._y, stepSize, debugMode);
    }

}
