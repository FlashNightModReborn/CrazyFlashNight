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

        // 更新血槽长度
        hpBar.血槽条._width = target.hp / target.hp满血值 * bloodBarLength;
        // 更新韧性条的位置
        hpBar.韧性条._x = bloodBarX - target.remainingImpactForce / target.韧性上限 * bloodBarLength;
        // 在霸体状态下改变韧性条底部颜色
        hpBar.刚体遮罩._visible = !!(target.刚体 || target.man.刚体标签);
    }
}
