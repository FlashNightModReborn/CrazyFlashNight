import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Updater.*;
import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventInitializer {
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;

        dispatcher.subscribeSingle("hit", HitUpdater.getUpdater(), target);

        var wtfunc:Function = WeatherUpdater.getUpdater();
        dispatcher.subscribeSingleGlobal("WeatherTimeRateUpdated", wtfunc, target);
        wtfunc.call(target);
    }
}
