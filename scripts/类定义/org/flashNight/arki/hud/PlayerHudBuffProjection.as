/** Headless owner of the existing detailed Buff bar order and primary timers. */
class org.flashNight.arki.hud.PlayerHudBuffProjection {
    private var manager:Object;
    private var entries:Array;
    private var generation:Number;
    public function PlayerHudBuffProjection() { entries = []; generation = 0; }
    public function initialize(value:Object):Void {
        if (value === manager) return;
        deinitialize();
        manager = value;
        generation++;
        if (manager == null) return;
        var initial:Array = manager.getAllMetaBuffs();
        for (var i:Number = 0; i < initial.length; i++) addIcon(String(initial[i].__regId), initial[i]);
        manager.eventDispatcher.subscribe("add", addIcon, this);
        manager.eventDispatcher.subscribe("remove", removeIcon, this);
    }
    public function deinitialize():Void {
        if (manager != null && manager.eventDispatcher != null && !manager.eventDispatcher.isDestroyed()) {
            manager.eventDispatcher.unsubscribe("add", addIcon, this);
            manager.eventDispatcher.unsubscribe("remove", removeIcon, this);
        }
        manager = null;
        entries.length = 0;
    }
    public function update():Void { }
    public function addIcon(id:String, buff:Object):Void {
        for (var i:Number = 0; i < entries.length; i++) if (entries[i].id == id) return;
        entries.push({id:id, buff:buff});
    }
    public function removeIcon(id:String):Void {
        for (var i:Number = 0; i < entries.length; i++) {
            if (entries[i].id == id) { entries.splice(i, 1); return; }
        }
    }
    public function snapshot():Array {
        var rows:Array = [];
        for (var i:Number = 0; i < entries.length; i++) {
            var entry:Object = entries[i];
            var timer:Object = entry.buff.getPrimaryTimer();
            var total:Number = timer == null ? 0 : Number(timer.getTotal());
            var remain:Number = timer == null ? 0 : Number(timer.getRemaining());
            if (!isFinite(total) || total < 0) total = 0;
            if (!isFinite(remain)) remain = 0;
            rows.push({id:generation + ":" + entry.id, timed:timer != null,
                total:total, remaining:Math.max(0, remain)});
        }
        return rows;
    }
}
