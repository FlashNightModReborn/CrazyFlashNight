import org.flashNight.arki.component.StatHandler.*;


class org.flashNight.arki.unit.UnitComponent.Updater.ImpactUpdater {
    public static function update(target:MovieClip):Void {
        // 计算剩余冲击力
        ImpactHandler.decayImpactForce(target);
    }

    public static function updateHero(target:MovieClip):Void {
        // 计算剩余冲击力并且刷新ui
        ImpactHandler.decayImpactForce(target);
        _root.玩家信息界面.刷新韧性显示();
    }
}
