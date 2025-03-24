import org.flashNight.arki.component.StatHandler.*;


class org.flashNight.arki.unit.UnitComponent.Updater.ImpactUpdater {
    public static function update(target:MovieClip):Void {
        // 计算剩余冲击力
        ImpactHandler.decayImpactForce(target);
    }
}
