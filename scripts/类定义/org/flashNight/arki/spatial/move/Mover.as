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

    /**
     * 增强版碰撞处理：加权方向混合 + 中点回归
     * @param entity 实体对象
     * @param attemptedGlobal 尝试移动的目标全局坐标（碰撞点）
     * @param originalDirection 原始移动方向（用于权重计算）
     */
    public static function enhancedCollisionResponse(entity:MovieClip, attemptedGlobal:Vector, originalDirection:String):Void {
        // 阶段1：基础边界限制
        var clamped:Vector = forceClampToBoundary(attemptedGlobal);
        
        // 阶段2：方向感知的加权挤出
        if (isStillColliding(clamped)) {
            clamped = directionalWeightedEjection(entity, attemptedGlobal, originalDirection);
        }

        // 阶段3：最终安全位置更新
        applySafePosition(entity, clamped);
    }

    //-------------------------
    // 私有工具方法
    //-------------------------

    /** 强制限制到环境边界 */
    private static function forceClampToBoundary(globalPt:Vector):Vector {
        return new Vector(
            Math.max(_root.Xmin, Math.min(globalPt.x, _root.Xmax)),
            Math.max(_root.Ymin, Math.min(globalPt.y, _root.Ymax))
        );
    }

    /** 检测坐标是否仍与地图碰撞 */
    private static function isStillColliding(globalPt:Vector):Boolean {
        return _root.gameworld.地图.hitTest(globalPt.x, globalPt.y, true);
    }

    /** 应用最终安全位置 */
    private static function applySafePosition(entity:MovieClip, globalPt:Vector):Void {
        var localPos:Vector = _root.gameworld.globalToLocal(globalPt);
        entity._x = localPos.x;
        entity.Z轴坐标 = localPos.y;
        entity._y = entity.Z轴坐标;
        entity.swapDepths(entity._y);
    }

    /** 方向加权挤出算法 */
    private static function directionalWeightedEjection(entity:MovieClip, attemptedGlobal:Vector, dir:String):Vector {
        // 获取原始方向向量
        var baseDir:Object = directions2D[dir] || {dx:0, dy:0};
        
        // 计算各边界距离（归一化）
        var distToEdges:Object = {
            left: attemptedGlobal.x - _root.Xmin,
            right: _root.Xmax - attemptedGlobal.x,
            top: attemptedGlobal.y - _root.Ymin,
            bottom: _root.Ymax - attemptedGlobal.y
        };

        // 方向权重计算（基于移动方向）
        var weights:Object = calculateDirectionWeights(dir, distToEdges);

        // 生成候选挤出方向
        var candidates:Array = [];
        
        // 水平挤出候选
        if (weights.horizontal > 0.1) {
            candidates.push({
                x: (baseDir.dx > 0) ? _root.Xmax : _root.Xmin,
                y: attemptedGlobal.y,
                weight: weights.horizontal
            });
        }

        // 垂直挤出候选
        if (weights.vertical > 0.1) {
            candidates.push({
                x: attemptedGlobal.x,
                y: (baseDir.dy > 0) ? _root.Ymax : _root.Ymin,
                weight: weights.vertical
            });
        }

        // 对角线挤出候选
        if (weights.diagonal > 0.1) {
            candidates.push({
                x: (baseDir.dx > 0) ? _root.Xmax : _root.Xmin,
                y: (baseDir.dy > 0) ? _root.Ymax : _root.Ymin,
                weight: weights.diagonal * 0.8 // 降低对角线优先级
            });
        }

        // 中点回归候选
        candidates.push({
            x: (_root.Xmin + _root.Xmax)/2,
            y: (_root.Ymin + _root.Ymax)/2,
            weight: 0.5 // 中等权重
        });

        // 按权重排序并检测可行解
        candidates.sortOn("weight", Array.NUMERIC | Array.DESCENDING);
        for (var i:Number=0; i<candidates.length; i++) {
            var testPt:Vector = forceClampToBoundary(new Vector(candidates[i].x, candidates[i].y));
            if (!isStillColliding(testPt)) return testPt;
        }

        // 全部失败则返回最近边界
        return findNearestEdgeFallback(attemptedGlobal);
    }

    /** 计算方向权重 */
    private static function calculateDirectionWeights(dir:String, dists:Object):Object {
        var weights:Object = {horizontal:0, vertical:0, diagonal:0};
        
        // 基于移动方向的基础权重
        switch(dir) {
            case "左":
            case "右":
                weights.horizontal = 1.0;
                weights.vertical = 0.3;
                break;
            case "上":
            case "下":
                weights.vertical = 1.0;
                weights.horizontal = 0.3;
                break;
            default:
                weights.horizontal = weights.vertical = 0.5;
        }

        // 基于边界距离的动态调整
        var totalX:Number = dists.left + dists.right;
        var totalY:Number = dists.top + dists.bottom;
        weights.horizontal *= (dists.left / totalX) || 0;
        weights.vertical *= (dists.top / totalY) || 0;

        // 对角线权重（当两个方向都接近边界时激活）
        weights.diagonal = Math.min(
            Math.pow(1 - (dists.left / _root.Xmax), 2),
            Math.pow(1 - (dists.top / _root.Ymax), 2)
        );

        return weights;
    }

    /** 最终回退：寻找最近边 */
    private static function findNearestEdgeFallback(globalPt:Vector):Vector {
        var minDist:Number = Infinity;
        var closest:Vector = globalPt.clone();

        // 检查四个边界
        var edges:Array = [
            {x: _root.Xmin, y: globalPt.y}, // left
            {x: _root.Xmax, y: globalPt.y}, // right
            {x: globalPt.x, y: _root.Ymin}, // top
            {x: globalPt.x, y: _root.Ymax}  // bottom
        ];

        for (var i:Number=0; i<edges.length; i++) {
            var dist:Number = globalPt.distance(edges[i]);
            if (dist < minDist && !isStillColliding(edges[i])) {
                minDist = dist;
                closest = edges[i];
            }
        }

        return closest;
    }

}
