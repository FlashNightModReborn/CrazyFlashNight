import org.flashNight.arki.unit.UnitUtil;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.unit.UnitComponent.Initializer.DisplayNameInitializer;

/** 理发与整形共用的原地外观刷新；不重建单位、dispatcher、Buff 或装备生命周期。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.LiveAppearanceUpdater {
    public static function isReady(actor:Object):Boolean {
        return actor != null && actor._parent === _root.gameworld
            && actor._name === _root.控制目标
            && actor.dressupRegistry != null
            && typeof _root.装备引用配置.刷新所有装扮 == "function";
    }

    public static function refresh(actor:Object):Boolean {
        if (!isReady(actor)) return false;
        var hp = actor.hp;
        var mp = actor.mp;
        var dispatcher = actor.dispatcher;
        var buffs = actor.buffManager;
        var version = actor.version;
        var scale:Number = UnitUtil.getHeightPercentage(Number(actor.身高));
        var mirrored:Boolean = Number(actor._xscale) < 0;
        actor.体重 = Number(actor.身高) - 105;
        actor.myxscale = scale;
        actor._xscale = mirrored ? -scale : scale;
        actor._yscale = scale;
        DressupInitializer.updateDressupKeys(MovieClip(actor));
        DisplayNameInitializer.refreshName(actor, true);
        _root.装备引用配置.刷新所有装扮(actor);
        if (typeof actor.aabbCollider.updateFromUnitArea == "function") {
            actor.aabbCollider.updateFromUnitArea(actor);
        }
        return isReady(actor) && actor.hp === hp && actor.mp === mp
            && actor.dispatcher === dispatcher && actor.buffManager === buffs && actor.version === version;
    }
}
