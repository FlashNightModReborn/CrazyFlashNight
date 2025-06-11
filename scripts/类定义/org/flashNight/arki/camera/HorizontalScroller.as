import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.camera.ZoomController;
import org.flashNight.arki.camera.ScrollBounds;
import org.flashNight.arki.camera.ScrollLogic;
import org.flashNight.arki.camera.ParallaxBackground;

/**
 * HorizontalScroller.as - 重构后的主控制器（修正版）
 *
 * 负责：
 *  1. 协调 ZoomController / ScrollBounds / ScrollLogic / ParallaxBackground
 *  2. 对外提供 update(...) 接口，与原 _root.横版卷屏 保持兼容
 *  3. 修正：地平线高度在缩放时的计算错误
 */
class org.flashNight.arki.camera.HorizontalScroller {
    /**
     * 等价于原来 _root.横版卷屏 的实现逻辑，但将各块功能拆分到子组件里。
     *
     * @param scrollTarget  要跟踪的目标在 gameworld 中的名称
     * @param bgWidth       背景原始宽度（像素）
     * @param bgHeight      背景原始高度（像素）
     * @param easeFactor    缓动系数
     */
    public static function update(
        scrollTarget:String,
        bgWidth:Number,
        bgHeight:Number,
        easeFactor:Number
    ):Void {
        scrollTarget = _root.控制目标;
        bgWidth = _root.gameworld.背景长;
        bgHeight = _root.gameworld.背景高;
        easeFactor = 10;

        // —— 1) 先拿到 gameWorld 和 bgLayer（天空盒） ——
        var gameWorld:MovieClip = _root.gameworld;
        var bgLayer:MovieClip   = _root.天空盒;

        // —— 2) 如果目标不存在或未初始化，则直接 return ——
        var scrollObj:MovieClip = gameWorld[scrollTarget];
        if (!scrollObj || scrollObj._x == undefined) {
            return;
        }

        // —— 3) 先执行缩放逻辑（ZoomController），得到 newScale 与 worldOffset ——
        var zoomResult:Object = ZoomController.updateScale(scrollObj, gameWorld, bgLayer, easeFactor, 1);
        var newScale:Number   = zoomResult.newScale;
        var offsetX:Number    = zoomResult.offsetX;
        var offsetY:Number    = zoomResult.offsetY;

        // —— 4) 根据缩放后的背景尺寸与舞台尺寸，计算滚动边界（ScrollBounds） ——
        var stageWidth:Number  = Stage.width;
        var stageHeight:Number = Stage.height - 64; // 顶部 UI 占 64px
        var bounds:Object = ScrollBounds.calculateBounds(
            bgWidth, bgHeight, newScale, stageWidth, stageHeight
        );
        // bounds: { effBgW, effBgH, minX, maxX, minY, maxY }

        // —— 5) 如果缩放确实发生了（offsetX/offsetY 可能非零），马上将 world 坐标移动并做边界检查 ——
        //     注意：如果 offsetX/offsetY 为 0，则代表缩放未变化，可跳过
        if (offsetX !== 0 || offsetY !== 0) {
            // 5.1) 先尝试做坐标补偿（未约束）
            var tentativeX:Number = gameWorld._x + offsetX;
            var tentativeY:Number = gameWorld._y + offsetY;

            // 5.2) 用 ScrollBounds.clampPosition 约束
            var clamped:Object = ScrollBounds.clampPosition(
                tentativeX,
                tentativeY,
                bounds,
                stageWidth,
                stageHeight
            );

            // 5.3) 将约束后坐标设回 gameWorld 与 bgLayer
            gameWorld._x = clamped.clampedX;
            gameWorld._y = clamped.clampedY;

            // 【修正】地平线高度需要考虑缩放因子
            var scaledHorizonHeight:Number = bgLayer.地平线高度 * newScale;
            bgLayer._y = clamped.clampedY + scaledHorizonHeight;

            // 5.4) 缩放时，也立即刷新一次后景视差（ParallaxBackground）
            ParallaxBackground.refreshOnZoom(bgLayer, gameWorld._x);
        }

        // —— 6) 如果当前背景本身大小（缩放后） 小于等于舞台可视区域，则无需做滚动，直接 return ——
        if (!ScrollBounds.needsScroll(bounds.effBgW, bounds.effBgH, stageWidth, stageHeight)) {
            return;
        }

        // —— 7) 读取滚动容差与中心点常量 ——
        var frameTimer:Object = _root.帧计时器;
        var offsetTolerance:Number = frameTimer.offsetTolerance;

        var LEFT_SCROLL_CENTER:Number     = stageWidth  * 0.5 + 100;
        var RIGHT_SCROLL_CENTER:Number    = stageWidth  * 0.5 - 100;
        var VERTICAL_SCROLL_CENTER:Number = stageHeight - 100;

        // —— 8) 获取 scrollObj 在屏幕上的坐标 —— 
        var pt2:Object = { x:0, y:0 };
        scrollObj.localToGlobal(pt2);

        // —— 9) 根据朝向决定水平目标中心点 —— 
        var isRightDirection:Boolean = (scrollObj._xscale > 0);
        var targetX:Number = isRightDirection ? RIGHT_SCROLL_CENTER : LEFT_SCROLL_CENTER;

        // —— 10) 用 ScrollLogic 来计算 dx/dy —— 
        var scrollParams:Object = ScrollLogic.computeScrollOffsets(
            pt2.x,
            pt2.y,
            targetX,
            VERTICAL_SCROLL_CENTER,
            offsetTolerance,
            easeFactor
        );
        var needMoveX:Boolean = scrollParams.needMoveX;
        var needMoveY:Boolean = scrollParams.needMoveY;
        var dx:Number = scrollParams.dx;
        var dy:Number = scrollParams.dy;

        // 如果两者都不需要滚动，则直接 return
        if (!needMoveX && !needMoveY) {
            return;
        }

        // —— 11) 计算未约束的新世界坐标 —— 
        var oldX:Number = gameWorld._x;
        var oldY:Number = gameWorld._y;
        var newX:Number = oldX + dx;
        var newY:Number = oldY + dy;

        // —— 12) 用 ScrollBounds.clampPosition 对 newX/newY 进行约束 —— 
        var clampedFinal:Object = ScrollBounds.clampPosition(
            newX, newY, bounds, stageWidth, stageHeight
        );

        // —— 13) 最终写回 gameWorld 与 bgLayer —— 
        var onScrollX:Boolean = (clampedFinal.clampedX !== oldX);
        var onScrollY:Boolean = (clampedFinal.clampedY !== oldY);

        if (onScrollX) {
            gameWorld._x = clampedFinal.clampedX;
        }
        if (onScrollY) {
            gameWorld._y = clampedFinal.clampedY;
        }
        
        // 【修正】bgLayer 同步 Y - 地平线高度需要考虑缩放因子
        var scaledHorizonHeight:Number = bgLayer.地平线高度 * newScale;
        bgLayer._y = gameWorld._y + scaledHorizonHeight;

        // —— 14) 如果启用了后景视差，则在滚动时更新一次后景 —— 
        if (_root.启用后景) {
            var currentFrame:Number = frameTimer.当前帧数;
            ParallaxBackground.updateParallax(bgLayer, currentFrame, gameWorld._x);
        }
    }

    public static function onSceneChanged():Void {
        var bgLayer:MovieClip   = _root.天空盒;
        bgLayer._x = 0;
    }
}