import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * ZoomController.as - 缩放控制组件
 *
 * 负责：
 *  1. 计算基于目标与最远敌人距离的动态缩放
 *  2. 处理缩放补偿逻辑（保持 scrollObj 在屏幕上位置恒定）
 *  3. 管理并更新 gameWorld.lastScale 状态
 */
class org.flashNight.arki.camera.ZoomController {
    /**
     * 根据 scrollObj 与最远敌人的距离，计算 targetZoomScale，并做缓动，
     * 如果缩放发生显著变化（阈值 0.005），则：
     *   1) 记录缩放前后 scrollObj 在屏幕上的坐标
     *   2) 更新 gameWorld 与 bgLayer 的 _xscale/_yscale
     *   3) 计算并返回 worldOffset，用于后续坐标补偿
     *
     * @param scrollObj   要跟踪的目标 MovieClip
     * @param gameWorld   全局世界 MovieClip（会直接修改其 _xscale/_yscale 与 lastScale）
     * @param bgLayer     “天空盒”根节点 MovieClip（会直接修改其 _xscale/_yscale）
     * @param easeFactor  缓动系数（越大越平滑）
     * @return Object     { newScale:Number, offsetX:Number, offsetY:Number }
     *                    newScale：本次最终缩放（相对于 1.0 的倍数）
     *                    offsetX/offsetY：应用于 world 坐标的补偿量（像素）
     */
    public static function updateScale(
        scrollObj:MovieClip,
        gameWorld:MovieClip,
        bgLayer:MovieClip,
        easeFactor:Number
    ):Object {
        // 1) 找到最远的敌人
        var farthestEnemy:Object = TargetCacheManager.findFarthestEnemy(scrollObj, 5);
        var distance:Number = (Math.abs(scrollObj._x - farthestEnemy._x)
                              + Math.abs(scrollObj._y - farthestEnemy._y)) || 99999;
        var normalizedDistance:Number = Math.max(1, distance / 100);
        var logScale:Number = Math.log(normalizedDistance) / Math.log(10);

        // 2) 计算 targetZoomScale：当 distance = 800 时，logScale≈1 => 2 - 1*1.11 = 0.89，取最大 1
        var targetZoomScale:Number = Math.min(1.5, Math.max(1, 2 - logScale * 1.11));

        // 3) 初始化 lastScale
        if (!gameWorld.lastScale) {
            gameWorld.lastScale = targetZoomScale;
        }

        var oldScale:Number = gameWorld.lastScale;
        // 4) 缓动计算 newScale
        var newScale:Number = oldScale + (targetZoomScale - oldScale) / easeFactor;

        // 5) 判断是否需要真正更新
        var scaleChanged:Boolean = Math.abs(newScale - oldScale) > 0.005;
        if (scaleChanged) {
            // 5.1) 记录缩放前 scrollObj 在屏幕上的坐标
            var preScalePt:Object = { x:0, y:0 };
            scrollObj.localToGlobal(preScalePt);

            // 5.2) 应用缩放到 gameWorld 与 bgLayer
            var newScalePercent:Number = newScale * 100;
            gameWorld._xscale = gameWorld._yscale = newScalePercent;
            bgLayer._xscale   = bgLayer._yscale   = newScalePercent;

            // 5.3) 记录缩放后 scrollObj 在屏幕上的坐标
            var postScalePt:Object = { x:0, y:0 };
            scrollObj.localToGlobal(postScalePt);

            // 5.4) 计算 worldOffset
            var worldOffsetX:Number = preScalePt.x - postScalePt.x;
            var worldOffsetY:Number = preScalePt.y - postScalePt.y;

            // 5.5) 更新 lastScale
            gameWorld.lastScale = newScale;

            return { newScale: newScale, offsetX: worldOffsetX, offsetY: worldOffsetY };
        }

        // 如果没变化，则返回旧值并且 offset 为 0
        return { newScale: oldScale, offsetX: 0, offsetY: 0 };
    }
}
