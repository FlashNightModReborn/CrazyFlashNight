/**
 * ActivationGlowWindow - 战技激活期 glow 三段 alpha 窗口
 *
 * 抽离斩马刀 / 烈焰斩马刀共有的"激活窗口期间 glow 三段透明度"逻辑：
 *   fadeIn → steady (100) → fadeOut → expire（写 ref.activation=false 并隐藏 glow）
 *
 * 字段 contract（调用方 init 时种好）：
 *   ref.activation             Boolean  当前是否处于激活窗口
 *   ref.activationStartFrame   Number   激活起始帧（来自 _root.帧计时器.当前帧数）
 *   ref.totalFrames            Number   激活总时长（帧）
 *   ref.fadeInFrames           Number   淡入帧数
 *   ref.fadeOutFrames          Number   淡出帧数
 *
 * 返回值：
 *   true  → 窗口仍激活，调用方继续主逻辑
 *   false → 未激活，调用方应早退（已确保 glow 被隐藏）
 *
 * 副作用：
 *   - 到期时把 ref.activation 置 false（一次性）
 *   - 写 glow._visible / glow._alpha（glow undefined 时跳过视觉写入）
 *
 * 设计选择：
 *   - glowMC 显式传入（不同武器路径名不同；斩马刀都是 saber.发光纹路 这级，但
 *     未来其它装备可能不同）
 *   - requireActivation 这种"是否启用激活窗口"开关不进工具，由调用方在外层短路
 *     （烈焰斩马刀 requireActivation=false 时常亮分支保留原 inline 写法）
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.ActivationGlowWindow {

    public static function tick(ref:Object, glow:MovieClip, now:Number):Boolean {
        var total:Number   = ref.totalFrames;
        var fadeIn:Number  = ref.fadeInFrames;
        var fadeOut:Number = ref.fadeOutFrames;

        // 到期检测
        if (ref.activation) {
            var elapsed:Number = now - ref.activationStartFrame;
            if (elapsed >= total) {
                ref.activation = false;
                if (glow != undefined) { glow._visible = false; glow._alpha = 0; }
            }
        }

        if (ref.activation) {
            if (glow != undefined) {
                if (!glow._visible) glow._visible = true;

                var e:Number = now - ref.activationStartFrame;
                var alphaVal:Number;

                if (e <= fadeIn && fadeIn > 0) {
                    alphaVal = (e / fadeIn) * 100;
                } else if (e >= total - fadeOut && fadeOut > 0) {
                    var fo:Number = (e - (total - fadeOut)) / fadeOut;
                    alphaVal = (1 - fo) * 100;
                } else {
                    alphaVal = 100;
                }

                glow._alpha = (alphaVal > 100) ? 100 : (alphaVal < 0) ? 0 : alphaVal;
            }
            return true;
        } else {
            if (glow != undefined && glow._visible) {
                glow._visible = false;
                glow._alpha = 0;
            }
            return false;
        }
    }
}
