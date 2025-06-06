/**
 * ParallaxBackground.as - 后景视差效果组件
 *
 * 负责：
 *  1. 管理并更新后景视差层的偏移（基于 worldX）
 *  2. 提供对后景速度列表的操作接口（若需要动态增删）
 *  3. 可选地在缩放时立即刷新一次后景位置
 */
class org.flashNight.arki.camera.ParallaxBackground {
    /**
     * 滚动时更新后景视差位置（只在需要时调用，每帧滚动时）
     *
     * @param bgLayer         “天空盒”根节点，需包含 “后景移动速度列表”（Array of { mc:MovieClip, speedrate:Number, delay:Number }）
     * @param currentFrame    当前帧编号（用于判断是否满足 delay）
     * @param worldX          gameWorld._x（全局世界 X 坐标，用于做视差计算）
     */
    public static function updateParallax(
        bgLayer:MovieClip,
        currentFrame:Number,
        worldX:Number
    ):Void {
        var bgList:Array = bgLayer.后景移动速度列表;
        var len:Number = bgList.length;
        for (var i:Number = 0; i < len; i++) {
            var info:Object = bgList[i];
            // 按 delay 来决定哪几帧更新
            if (currentFrame % info.delay === 0) {
                info.mc._x = worldX / info.speedrate;
            }
        }
    }

    /**
     * 在缩放时立即刷新后景位置（当 ZoomController detect 到 scaleChanged）
     *
     * @param bgLayer     “天空盒”根节点
     * @param worldX      gameWorld._x （此时已应用缩放后补偿）
     */
    public static function refreshOnZoom(
        bgLayer:MovieClip,
        worldX:Number
    ):Void {
        var bgList:Array = bgLayer.后景移动速度列表;
        var len:Number = bgList.length;
        for (var i:Number = 0; i < len; i++) {
            var info:Object = bgList[i];
            info.mc._x = worldX / info.speedrate;
        }
    }
}
