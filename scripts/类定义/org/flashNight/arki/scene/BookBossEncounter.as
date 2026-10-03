import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageEvent;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/** 书中终战的有限增援。使用既有事件出怪，不计入必须清场的波次敌人数。 */
class org.flashNight.arki.scene.BookBossEncounter {
    private var world:MovieClip;
    private var owner:Object;
    private var plan:Object;
    private var clock:MovieClip;
    private var living:Object;
    private var issued:Object;
    private var queue:Array;
    private var groupIndex:Number;
    private var waitFrames:Number;
    private var stopped:Boolean;
    public static function start(world:MovieClip, plan:Object):Void {
        if (world == undefined || plan == null) return;
        new BookBossEncounter(world, plan);
    }
    private function BookBossEncounter(w:MovieClip, p:Object) {
        world = w; owner = StageReturnFlow.worldIdentity(w); plan = p;
        living = {}; issued = {}; queue = []; groupIndex = 0; waitFrames = 0; stopped = false;
        clock = w.createEmptyMovieClip("__bookBossEncounter", w.getNextHighestDepth());
        var self:BookBossEncounter = this;
        clock.onEnterFrame = function():Void { self.tick(); };
        world.dispatcher.subscribe("UnitDeath", onDeath, this);
        world.dispatcher.subscribe("UnitRemoved", onRemoved, this);
        world.dispatcher.subscribe("UnitSpawn", onSpawn, this);
    }
    private function current():Boolean {
        return !stopped && world === _root.gameworld && owner === StageReturnFlow.worldIdentity(_root.gameworld)
            && StageManager.instance.isActive && !StageManager.instance.isFinished && !StageManager.instance.isFailed;
    }
    private function tick():Void {
        if (!current()) { finishEncounter(false); return; }
        if (_root.暂停 === true) return;
        var hero:MovieClip = TargetCacheManager.findHero();
        if (!(hero.hp > 0)) return;
        var boss:MovieClip = world[plan.instanceName];
        if (boss == undefined || !(boss.hp满血值 > 0)) return;
        if (!(boss.hp > 0)) { finishEncounter(true); return; }
        while (groupIndex < plan.groups.length && boss.hp / boss.hp满血值 <= plan.groups[groupIndex].hpRatio) {
            var entries:Array = plan.groups[groupIndex++].enemies;
            for (var i:Number = 0; i < entries.length; i++) queue.push(entries[i]);
        }
        if (waitFrames > 0) { waitFrames--; return; }
        if (queue.length == 0) return;
        var count:Number = 0, ranged:Number = 0;
        for (var name:String in living) { count++; if (living[name].ranged) ranged++; }
        if (count >= plan.maxAlive) return;
        var index:Number = -1;
        for (i = 0; i < queue.length; i++) {
            if (!queue[i].ranged || ranged < plan.maxRanged) { index = i; break; }
        }
        if (index < 0) return;
        var enemy:Object = queue.splice(index, 1)[0];
        // 先占用位置，异步加载完成前也计入上限；不因一次空引用重复刷怪。
        living[enemy.InstanceName] = enemy;
        issued[enemy.InstanceName] = true;
        waitFrames = plan.intervalFrames;
        var event:StageEvent = new StageEvent({EventName:"BookCampusSupport", Enemy:[enemy]});
        event.execute();
    }
    private function onDeath(name:String):Void {
        if (!current()) return;
        if (name == plan.instanceName) { finishEncounter(true); return; }
        delete living[name];
    }
    private function onRemoved(name:String):Void {
        if (world !== _root.gameworld || owner !== StageReturnFlow.worldIdentity(_root.gameworld)) return;
        delete living[name];
    }
    private function onSpawn(name:String):Void {
        // Boss 死亡与异步演员加载可能交错；迟到的本场增援只退场，不再参与战斗。
        if (stopped && issued[name] === true && world === _root.gameworld
                && owner === StageReturnFlow.worldIdentity(_root.gameworld)) retire(world[name]);
    }
    private function retire(unit:MovieClip):Void {
        if (unit == undefined) return;
        unit.已加经验值 = true;
        unit.掉落物 = [];
        unit.removeMovieClip();
    }
    private function finishEncounter(victory:Boolean):Void {
        if (stopped) return;
        stopped = true; queue = [];
        delete clock.onEnterFrame;
        world.dispatcher.unsubscribe("UnitDeath", onDeath, this);
        world.dispatcher.unsubscribe("UnitRemoved", onRemoved, this);
        if (world !== _root.gameworld || owner !== StageReturnFlow.worldIdentity(_root.gameworld)) return;
        // 先关闭增援和波次调度。正常击杀的补给仍留在地面；退场不制造额外战利品或经验。
        if (victory) org.flashNight.arki.scene.WaveSpawner.instance.close();
        for (var name:String in living) {
            var unit:MovieClip = world[name];
            retire(unit);
        }
        living = {};
        if (victory) StageManager.instance.clearStage();
    }
}
