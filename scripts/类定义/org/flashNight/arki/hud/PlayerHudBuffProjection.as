/** Headless owner of the existing detailed Buff bar order and primary timers. */
class org.flashNight.arki.hud.PlayerHudBuffProjection {
    private static var MAX_MODS_PER_BUFF:Number = 8;
    private static var MAX_MODS_PER_SNAPSHOT:Number = 64;
    private var manager:Object;
    private var entries:Array;
    private var generation:Number;
    private var snapshotRows:Array;
    private var metadataCost:Number = 0;
    private var detailsEnabled:Boolean = false;
    private var modsRemaining:Number = 0;
    public function PlayerHudBuffProjection() { entries = []; generation = 0; snapshotRows = []; }
    public function setDetailsEnabled(value:Boolean):Void {
        value = value === true;
        if (detailsEnabled === value) return;
        detailsEnabled = value;
        snapshotRows = [];
    }
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
        metadataCost = 0;
        snapshotRows = [];
    }
    public function update():Void { }
    public function addIcon(id:String, buff:Object):Void {
        // Cold binding enumerates MetaBuffs only. Apply the same rule to live
        // add events so internal numeric Pods cannot appear as anonymous cards.
        if (typeof buff.isPod == "function" && buff.isPod()) return;
        for (var i:Number = 0; i < entries.length; i++) if (entries[i].id == id) return;
        var info:Object = readInfo(buff);
        var presentation:Object = readPresentation(buff);
        var cost:Number = (info == null ? 0 : info.name.length + info.description.length + 64) +
            presentation.activeLabel.length + presentation.inactiveLabel.length;
        // Bound optional display metadata independently of the transport's 128 KiB ceiling.
        // Existing entries retain their metadata and slot identity under pressure.
        if (metadataCost + cost > 4096) {
            info = null;
            presentation.activeLabel = "";
            presentation.inactiveLabel = "";
            cost = 0;
        }
        metadataCost += cost;
        var group:Object = null;
        if (presentation.groupId.length > 0)
            group = {id:generation + ":" + presentation.groupId, primary:presentation.primary};
        entries.push({id:id, wireId:generation + ":" + id, buff:buff, info:info, cost:cost,
            group:group, activation:presentation.activation, mods:presentation.mods,
            activeLabel:presentation.activeLabel, inactiveLabel:presentation.inactiveLabel});
    }
    private function bounded(value, limit:Number):String {
        if (typeof value != "string") return "";
        var result:String = value.substr(0, limit);
        var last:Number = result.charCodeAt(result.length - 1);
        if (last > 55295 && last < 56320) result = result.substr(0, result.length - 1);
        return result;
    }
    private function readPresentation(buff:Object):Object {
        var source:Object = buff.hudPresentation;
        var activation:Object = source.activation;
        if (activation != null && (typeof activation.isActive != "function" ||
            typeof activation.getRemaining != "function" || typeof activation.getDuration != "function")) activation = null;
        return {groupId:bounded(source.groupId, 64), primary:source.primary === true,
            activation:activation, mods:source.mods === true,
            activeLabel:bounded(source.activeLabel, 16), inactiveLabel:bounded(source.inactiveLabel, 16)};
    }
    private function readInfo(buff:Object):Object {
        var source:Object = buff.hudInfo;
        var name:String = bounded(source.name, 32);
        var description:String = bounded(source.description, 96);
        var polarity:String = source.polarity;
        if (polarity != "benefit" && polarity != "harm") polarity = "neutral";
        var stacks:Number = Number(source.stacks);
        if (!isFinite(stacks) || stacks < 1 || stacks > 999 || stacks != Math.floor(stacks)) stacks = 0;
        if (name.length == 0 && typeof buff.getChildBuffCount == "function") {
            var properties:String = "";
            var count:Number = Math.min(4, buff.getChildBuffCount());
            for (var i:Number = 0; i < count; i++) {
                var child:Object = buff.getChildBuff(i);
                if (typeof child.getTargetProperty != "function") continue;
                var property:String = bounded(child.getTargetProperty(), 24);
                if (property == "damageTakenMultiplier") property = "受到的伤害";
                if (property == "行走X速度") property = "移动速度";
                if (property.length > 0) properties += (properties.length > 0 ? "、" : "") + property;
            }
            name = count == 1 && properties.length > 0 ? bounded(properties, 32) : "复合状态";
            description = properties.length > 0 ? bounded("影响属性：" + properties + "。强度以当前角色属性为准。", 96) : "由效果条件维持的状态。";
        }
        if (name.length == 0) return null;
        return {name:name, description:description, polarity:polarity, stacks:stacks};
    }
    public function removeIcon(id:String):Void {
        for (var i:Number = 0; i < entries.length; i++) {
            if (entries[i].id == id) { metadataCost -= entries[i].cost; entries.splice(i, 1); return; }
        }
    }
    private function readIncarnation(entry:Object):String {
        if (typeof entry.buff.getId != "function") return entry.wireId;
        var id:String = bounded(entry.buff.getId(), 48);
        return id.length > 0 ? id : entry.wireId;
    }
    private function readActivation(entry:Object):Object {
        var component:Object = entry.activation;
        if (component == null) return null;
        var active:Boolean = component.isActive() === true;
        var remain:Number = active ? Number(component.getRemaining()) : 0;
        var total:Number = Number(component.getDuration());
        if (!isFinite(remain) || remain < 0) remain = 0;
        if (!isFinite(total) || total < 0) total = 0;
        var result:Object = {active:active, remaining:remain, total:total};
        if (entry.activeLabel.length > 0) result.activeLabel = entry.activeLabel;
        if (entry.inactiveLabel.length > 0) result.inactiveLabel = entry.inactiveLabel;
        return result;
    }
    private function readMods(entry:Object):Array {
        if (!entry.mods || typeof entry.buff.getId != "function" ||
            typeof manager.getInjectedPodIds != "function" || typeof manager.getBuffById != "function") return null;
        var ids:Array = manager.getInjectedPodIds(entry.buff.getId());
        if (ids.length > MAX_MODS_PER_BUFF || ids.length > modsRemaining) return null;
        var result:Array = [];
        for (var i:Number = 0; i < ids.length; i++) {
            var pod:Object = manager.getBuffById(String(ids[i]));
            if (pod == null || typeof pod.getTargetProperty != "function" ||
                typeof pod.getCalculationType != "function" || typeof pod.getValue != "function") return null;
            if (typeof pod.isActive == "function" && !pod.isActive()) continue;
            var property:String = bounded(pod.getTargetProperty(), 32);
            var calc:String = bounded(pod.getCalculationType(), 24);
            var value:Number = Number(pod.getValue());
            if (property.length == 0 || calc.length == 0 || !isFinite(value)) return null;
            result.push({property:property, calc:calc, value:value});
        }
        modsRemaining -= result.length;
        return result;
    }
    private function sameDetail(previous, current):Boolean {
        if (previous === current) return true;
        if (previous == null || current == null) return previous == null && current == null;
        if (typeof previous != "object" || typeof current != "object") return false;
        if (previous instanceof Array || current instanceof Array) {
            if (!(previous instanceof Array) || !(current instanceof Array) || previous.length != current.length) return false;
            for (var i:Number = 0; i < current.length; i++) if (!sameDetail(previous[i], current[i])) return false;
            return true;
        }
        var count:Number = 0;
        var name:String;
        for (name in current) {
            if (!current.hasOwnProperty(name)) continue;
            if (!previous.hasOwnProperty(name) || !sameDetail(previous[name], current[name])) return false;
            count++;
        }
        for (name in previous) if (previous.hasOwnProperty(name)) count--;
        return count == 0;
    }
    public function snapshot():Array {
        var previous:Array = snapshotRows;
        var rows:Array = previous.length == entries.length ? null : [];
        modsRemaining = MAX_MODS_PER_SNAPSHOT;
        for (var i:Number = 0; i < entries.length; i++) {
            var entry:Object = entries[i];
            var timer:Object = entry.buff.getPrimaryTimer();
            var total:Number = timer == null ? 0 : Number(timer.getTotal());
            var remain:Number = timer == null ? 0 : Number(timer.getRemaining());
            if (!isFinite(total) || total < 0) total = 0;
            if (!isFinite(remain)) remain = 0;
            remain = Math.max(0, remain);
            var timed:Boolean = timer != null;
            var incarnation:String = "";
            var activation:Object = null;
            var mods:Array = null;
            if (detailsEnabled) {
                incarnation = readIncarnation(entry);
                activation = readActivation(entry);
                mods = readMods(entry);
            }
            var row:Object = previous[i];
            var detailsChanged:Boolean = detailsEnabled && row != null &&
                (row.incarnation !== incarnation || !sameDetail(row.group, entry.group) ||
                !sameDetail(row.activation, activation) || !sameDetail(row.mods, mods));
            if (row == null || row.id !== entry.wireId || row.timed !== timed ||
                row.total !== total || row.remaining !== remain || detailsChanged) {
                // Copy only after the first changed row. The old array and its rows
                // stay immutable for pending packets and forced resynchronization.
                if (rows == null) rows = previous.slice(0, i);
                row = {id:entry.wireId, timed:timed, total:total, remaining:remain};
                if (entry.info != null) row.info = entry.info;
                if (detailsEnabled) {
                    row.incarnation = incarnation;
                    if (entry.group != null) row.group = entry.group;
                    if (activation != null) row.activation = activation;
                    if (mods != null) row.mods = mods;
                }
            }
            if (rows != null) rows.push(row);
        }
        if (rows != null) snapshotRows = rows;
        return snapshotRows;
    }
}
