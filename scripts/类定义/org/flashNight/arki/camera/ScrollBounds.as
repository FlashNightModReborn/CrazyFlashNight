/**
 * ScrollBounds.as - 滚动边界计算组件
 *
 * 负责：
 *  1. 计算并维护 scroll 边界（给定背景尺寸与缩放后尺寸、舞台尺寸）
 *  2. 提供坐标约束（clamp）功能
 *  3. 判断当前是否需要滚动（即背景是否大于可视区域）
 */
class org.flashNight.arki.camera.ScrollBounds {
    /**
     * 计算缩放后背景的有效宽高，并返回边界值
     *
     * @param bgWidth        原始背景宽度（像素）
     * @param bgHeight       原始背景高度（像素）
     * @param newScale       当前缩放倍数（相对 1.0）
     * @param stageWidth     可视舞台宽度（像素）
     * @param stageHeight    可视舞台高度（像素，已扣除 UI）
     * @return Object        {
     *                        effBgW:Number,  // 缩放后背景宽度
     *                        effBgH:Number,  // 缩放后背景高度
     *                        minX:Number,    // X 方向最小滚动坐标 (stageWidth - effBgW)
     *                        maxX:Number,    // X 方向最大滚动坐标 (0)
     *                        minY:Number,    // Y 方向最小滚动坐标 (stageHeight - effBgH)
     *                        maxY:Number     // Y 方向最大滚动坐标 (0)
     *                      }
     */
    public static function calculateBounds(
        bgWidth:Number,
        bgHeight:Number,
        newScale:Number,
        stageWidth:Number,
        stageHeight:Number
    ):Object {
        var effBgW:Number = bgWidth  * newScale;
        var effBgH:Number = bgHeight * newScale;

        return {
            effBgW: effBgW,
            effBgH: effBgH,
            minX:   stageWidth - effBgW,
            maxX:   0,
            minY:   stageHeight - effBgH,
            maxY:   0
        };
    }

    /**
     * 判断当前背景是否真实需要滚动（即背景尺寸大于可视尺寸）
     *
     * @param effBgW        缩放后背景宽度
     * @param effBgH        缩放后背景高度
     * @param stageWidth    可视舞台宽度
     * @param stageHeight   可视舞台高度
     * @return Boolean      true 表示至少一维需要滚动
     */
    public static function needsScroll(
        effBgW:Number,
        effBgH:Number,
        stageWidth:Number,
        stageHeight:Number
    ):Boolean {
        return (stageWidth  < effBgW) || (stageHeight < effBgH);
    }

    /**
     * 将未约束的新世界坐标 newX/newY 按照边界 min/maxClamp 强制约束
     *
     * @param newX               计算得到的未约束 X
     * @param newY               计算得到的未约束 Y
     * @param bounds:Object      { minX, maxX, minY, maxY }
     * @param stageWidth         可视舞台宽度
     * @param stageHeight        可视舞台高度
     * @return Object            { clampedX:Number, clampedY:Number }
     */
    public static function clampPosition(
        newX:Number,
        newY:Number,
        bounds:Object,
        stageWidth:Number,
        stageHeight:Number
    ):Object {
        var clampedX:Number = newX;
        var clampedY:Number = newY;

        // X 方向：只在背景比舞台宽的时候才进行约束
        if (stageWidth < bounds.effBgW) {
            if (clampedX < bounds.minX) {
                clampedX = bounds.minX;
            } else if (clampedX > bounds.maxX) {
                clampedX = bounds.maxX;
            }
        } 
        // 【重要】移除 else 分支。如果背景不比舞台宽，clampedX 就等于传入的 newX。
        // 调用者会通过对比 newX 和 oldX 来决定是否应用。

        // Y 方向：只在背景比舞台高的时候才进行约束
        if (stageHeight < bounds.effBgH) {
            if (clampedY < bounds.minY) {
                clampedY = bounds.minY;
            } else if (clampedY > bounds.maxY) {
                clampedY = bounds.maxY;
            }
        }
        // 【重要】移除 else 分支。

        return { clampedX: clampedX, clampedY: clampedY };
    }
}
