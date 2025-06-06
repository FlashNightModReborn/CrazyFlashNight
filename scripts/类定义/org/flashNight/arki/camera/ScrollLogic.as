/**
 * ScrollLogic.as - 滚动逻辑组件
 *
 * 负责：
 *  1. 根据目标位置与中心点的偏移，计算 easing 后的 dx/dy
 *  2. 判断是否需要滚动：当绝对偏移大于阈值才计算
 *  3. 返回滚动后的最终坐标增量
 */
class org.flashNight.arki.camera.ScrollLogic {
    /**
     * 计算单轴方向上、带缓动的滚动增量
     *
     * @param delta        目标中心与 scrollObj 投影后的差值
     * @param easeFactor   缓动系数（越大越平滑）
     * @return Number      返回本帧应该移动的增量（可能是 delta/self.factor，也可能直接是 delta）
     */
    public static function computeAxisOffset(delta:Number, easeFactor:Number):Number {
        var absDelta:Number = Math.abs(delta);
        if (absDelta > 1) {
            return delta / easeFactor;
        }
        return delta;
    }

    /**
     * 给定 scrollObj 在屏幕的位置 pts.x/pts.y，与设定中心位置 centerX/centerY，
     * 以及 offsetTolerance，判断 X/Y 方向是否需要滚动，并分别计算 dx/dy。
     *
     * @param screenX             scrollObj 在屏幕上的 X
     * @param screenY             scrollObj 在屏幕上的 Y
     * @param centerX             水平滚动中心 X
     * @param centerY             垂直滚动中心 Y
     * @param offsetTolerance     滚动容差
     * @param easeFactor          缓动系数
     * @return Object             { needMoveX:Boolean, needMoveY:Boolean, dx:Number, dy:Number }
     */
    public static function computeScrollOffsets(
        screenX:Number,
        screenY:Number,
        centerX:Number,
        centerY:Number,
        offsetTolerance:Number,
        easeFactor:Number
    ):Object {
        var deltaX:Number = centerX - screenX;
        var deltaY:Number = centerY - screenY;
        var adx:Number = Math.abs(deltaX);
        var ady:Number = Math.abs(deltaY);

        var needMoveX:Boolean = (adx > offsetTolerance);
        var needMoveY:Boolean = (ady > offsetTolerance);
        var dx:Number = 0;
        var dy:Number = 0;

        if (needMoveX) {
            dx = ScrollLogic.computeAxisOffset(deltaX, easeFactor);
        }
        if (needMoveY) {
            dy = ScrollLogic.computeAxisOffset(deltaY, easeFactor);
        }

        return {
            needMoveX: needMoveX,
            needMoveY: needMoveY,
            dx: dx,
            dy: dy
        };
    }
}
