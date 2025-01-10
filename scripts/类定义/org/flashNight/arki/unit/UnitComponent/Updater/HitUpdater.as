import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater {
    
    public static function getUpdater():Function
    {
        return function():Void {
            ImpactHandler.refreshImpactForce(this);
            var bar:MovieClip = this.新版人物文字信息.头顶血槽;
            bar._visible = true;
            bar.gotoAndPlay(2);
        };
    }
}
