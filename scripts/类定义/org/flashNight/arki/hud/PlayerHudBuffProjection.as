/** Headless owner of the existing detailed Buff bar order and primary timers. */
class org.flashNight.arki.hud.PlayerHudBuffProjection {
    private var manager:Object;
    private var entries:Array;
    private var generation:Number;
    private var snapshotRows:Array;
    public function PlayerHudBuffProjection() { entries = []; generation = 0; snapshotRows = []; }
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
        var dispatcher:Object = manager.eventDispatcher;
        if (dispatcher != null && !dispatcher.isDestroyed()) {
            dispatcher.unsubscribe("add", addIcon, this);
            dispatcher.unsubscribe("remove", removeIcon, this);
        }
        manager = null;
        entries.length = 0;
        snapshotRows = [];
    }
    public function update():Void { }
    public function addIcon(id:String, buff:Object):Void {
        for (var i:Number = 0; i < entries.length; i++) if (entries[i].id == id) return;
        entries.push({id:id, wireId:generation + ":" + id, buff:buff});
    }
    public function removeIcon(id:String):Void {
        for (var i:Number = 0; i < entries.length; i++) {
            if (entries[i].id == id) { entries.splice(i, 1); return; }
        }
    }
    public function snapshot():Array {
        var previous:Array = snapshotRows;
        var rows:Array = previous.length == entries.length ? null : [];
        for (var i:Number = 0; i < entries.length; i++) {
            var entry:Object = entries[i];
            var timer:Object = entry.buff.getPrimaryTimer();
            var total:Number = timer == null ? 0 : Number(timer.getTotal());
            var remain:Number = timer == null ? 0 : Number(timer.getRemaining());
            if (!isFinite(total) || total < 0) total = 0;
            if (!isFinite(remain)) remain = 0;
            remain = Math.max(0, remain);
            var timed:Boolean = timer != null;
            var row:Object = previous[i];
            if (row == null || row.id !== entry.wireId || row.timed !== timed || row.total !== total || row.remaining !== remain) {
                // Copy only after the first changed row. The old array and its rows
                // stay immutable for pending packets and forced resynchronization.
                if (rows == null) rows = previous.slice(0, i);
                row = {id:entry.wireId, timed:timed, total:total, remaining:remain};
            }
            if (rows != null) rows.push(row);
        }
        if (rows != null) snapshotRows = rows;
        return snapshotRows;
    }
}
