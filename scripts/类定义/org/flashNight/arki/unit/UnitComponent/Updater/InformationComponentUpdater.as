import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.unit.UnitComponent.Updater.InformationComponentUpdater {

    public static function update(target:MovieClip):Void {
        // 设置透明度和可见性
        var ic:MovieClip = target.新版人物文字信息;
        if (!(ic._visible = target.状态 == "登场" ? false : ic._alpha > 0)) return;

        var hpBar:MovieClip = ic.头顶血槽;
        var hpBarBottom:MovieClip = hpBar.血槽底;
        var bloodBarX:Number = hpBarBottom._x;
        var bloodBarLength:Number = hpBarBottom._width;

        target.hpUnchangedCounter++;

        // 计算实际血槽宽度
        var actualHpWidth:Number = target.hp / target.hp满血值 * bloodBarLength;
        hpBar.血槽条._width = actualHpWidth;

        // 核心动画逻辑 --------------------------------------------------------
        var currentCounter:Number = target.hpUnchangedCounter;
        var residualHpWidth:Number = target.residualHpWidth;

        // 情况1：血量增加时立即同步
        if (actualHpWidth > residualHpWidth) {
            residualHpWidth = actualHpWidth;
        }
        // 情况2：需要衰减且处于动画区间
        else if (residualHpWidth > actualHpWidth) {
            // 动画区间：16-39次更新（共24次）
            if (currentCounter >= 16 && currentCounter <= 39) {
                // 在动画起点记录初始状态
                if (currentCounter == 16) {
                    target._animStartResidual = residualHpWidth;
                    target._animStartActual = actualHpWidth;
                }
                
                // 计算二次缓出进度（t ∈ [0,1]）
                var t:Number = (currentCounter - 15) / 24; // 16→0.0417, 39→1.0
                var progress:Number = t * (2 - t); // 二次缓出公式：t*(2-t)

                // 计算动画插值
                residualHpWidth = target._animStartResidual - 
                    (target._animStartResidual - target._animStartActual) * progress;
                
                // 精度保护（避免浮点误差）
                if (residualHpWidth - actualHpWidth < 0.1) {
                    residualHpWidth = actualHpWidth;
                }
            }
            // 情况3：动画超时强制完成
            else if (currentCounter > 39) {
                residualHpWidth = actualHpWidth;
            }
        }

        // 更新状态
        target.residualHpWidth = residualHpWidth;
        hpBar.残余血槽条._width = residualHpWidth;

        // 更新韧性条的位置
        hpBar.韧性条._x = bloodBarX - target.remainingImpactForce / target.韧性上限 * bloodBarLength;
        // 在霸体状态下改变韧性条底部颜色
        hpBar.刚体遮罩._visible = !!(target.刚体 || target.man.刚体标签);
    }
}
