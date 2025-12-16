import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
import org.flashNight.arki.collision.CollisionLayerRenderer;

/**
 * 障碍物渲染组件 - 负责将地图元件的碰撞区域渲染到地图上
 * 绘制逻辑已委托给 CollisionLayerRenderer
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ObstacleRenderer {

    /**
     * 渲染目标的障碍物到地图
     * @param target 要渲染的目标MovieClip
     */
    public static function renderObstacle(target:MovieClip):Void {
        if (!ObstacleRenderer.canRenderObstacle(target)) {
            return;
        }

        var rect:Object = target.area.getRect(_root.gameworld);
        var collisionLayer:MovieClip = _root.collisionLayer;

        if (collisionLayer) {
            CollisionLayerRenderer.drawObstacle(collisionLayer, rect, true);
        }
    }

    /**
     * 检查目标是否可以渲染障碍物
     * @param target 要检查的目标MovieClip
     * @return Boolean 如果可以渲染返回true
     */
    public static function canRenderObstacle(target:MovieClip):Boolean {
        return target.obstacle && target.area && _root.gameworld;
    }

    /**
     * 获取障碍物的边界矩形
     * @param target 目标MovieClip
     * @param referenceClip 参考坐标系MovieClip，默认为gameworld
     * @return Object 包含xMin, yMin, xMax, yMax的矩形对象，如果无效则返回null
     */
    public static function getObstacleBounds(target:MovieClip, referenceClip:MovieClip):Object {
        if (!target || !target.area) {
            return null;
        }
        if (!referenceClip) {
            referenceClip = _root.gameworld;
        }
        return target.area.getRect(referenceClip);
    }

    /**
     * 批量渲染多个障碍物
     * @param targets 要渲染的目标数组
     */
    public static function renderMultipleObstacles(targets:Array):Void {
        if (!targets || targets.length == 0) return;
        for (var i:Number = 0; i < targets.length; i++) {
            ObstacleRenderer.renderObstacle(targets[i]);
        }
    }

    /**
     * 清除碰撞层上的所有障碍物
     * 注意：此方法会清除整个碰撞层，包括边界碰撞箱
     * @param gameworld 游戏世界MovieClip（参数保留用于向后兼容，实际未使用）
     */
    public static function clearAllObstacles(gameworld:MovieClip):Void {
        var collisionLayer:MovieClip = _root.collisionLayer;
        if (collisionLayer) {
            collisionLayer.clear();
            CollisionLayerRenderer.markDirty();
        }
    }
}