import org.flashNight.gesh.path.PathManager;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.NamedPoseCodec;

/** 按装备需求共享姿态JSON；最后一个租用者释放时撤销缓存及迟到回调。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.NamedPoseDataStore {
    private static var entries:Object = {};

    public static function acquire(path:String, ready:Function, failed:Function):Object {
        var entry:Object = entries[path];
        var start:Boolean = entry == undefined;
        if (start) {
            entry = {path:path, refs:0, alive:true, status:"loading", data:null, waiters:[]};
            entries[path] = entry;
        }
        var lease:Object = {entry:entry, active:true, ready:ready, failed:failed};
        entry.refs++;
        if (entry.status == "ready") ready(entry.data);
        else if (entry.status == "failed") failed(entry.error);
        else entry.waiters.push(lease);
        if (start) {
            // 复用现役路径和JSON解析器；租约层负责缓存，不带入读取包装的通信依赖。
            PathManager.initialize();
            var resolved:String = PathManager.resolvePath(path);
            if (resolved == null) complete(entry,null,"invalid resource path");
            else {
                entry.loader = new LoadVars();
                entry.loader.onData = function(raw:String):Void {
                    delete this.onData;
                    if (!entry.alive || NamedPoseDataStore.entries[entry.path] !== entry) return;
                    if (raw == null) { NamedPoseDataStore.complete(entry,null,"file read failed"); return; }
                    var parser:JSON = new JSON(false);
                    var parsed:Object = parser.parse(raw);
                    NamedPoseDataStore.complete(entry,parsed,parser.errors.length == 0 ? null : "invalid JSON");
                };
                if (!entry.loader.load(resolved)) complete(entry,null,"file load rejected");
            }
        }
        return lease;
    }

    private static function complete(entry:Object, data:Object, error:String):Void {
        if (!entry.alive || entries[entry.path] !== entry) return;
        if (error == null) data = NamedPoseCodec.unpack(data);
        if (error == null && !validate(data)) error = "invalid named-pose data";
        entry.data = error == null ? data : null;
        entry.error = error;
        entry.status = error == null ? "ready" : "failed";
        entry.loader = null;
        var waiters:Array = entry.waiters;
        entry.waiters = [];
        for (var i:Number = 0; i < waiters.length; i++) {
            var lease:Object = waiters[i];
            if (!lease.active || !entry.alive) continue;
            if (error == null) lease.ready(data);
            else lease.failed(error);
        }
    }

    public static function release(lease:Object):Void {
        if (!lease.active) return;
        lease.active = false;
        lease.ready = null; lease.failed = null;
        var entry:Object = lease.entry;
        lease.entry = null;
        for (var i:Number = entry.waiters.length - 1; i >= 0; i--) {
            if (entry.waiters[i] === lease) entry.waiters.splice(i,1);
        }
        if (--entry.refs == 0) {
            entry.alive = false; entry.data = null; entry.loader = null; entry.waiters = [];
            if (entries[entry.path] === entry) delete entries[entry.path];
        }
    }

    public static function inspect(path:String):Object {
        var entry:Object = entries[path];
        return entry == undefined ? {status:"absent", refs:0, cached:false}
            : {status:entry.status, refs:entry.refs, cached:entry.data != null};
    }

    /** 只接受完整直接索引表；消费时不重放前缀，也不推测缺失索引。 */
    public static function validate(data:Object):Boolean {
        if (data.schema != "named-pose.compact.v1" || !(data.parts instanceof Array)
                || !(data.targets instanceof Array) || data.targets.length == 0
                || !(data.matrices instanceof Array) || !(data.states instanceof Array)
                || !(data.poses instanceof Array) || data.poses.length == 0) return false;
        var i:Number;
        var seen:Object = {};
        for (i = 0; i < data.targets.length; i++) {
            var name:String = data.targets[i].name;
            if (typeof name != "string" || name.length == 0 || seen[name] === true) return false;
            seen[name] = true;
        }
        for (var id:String in data.clips) {
            var clip:Object = data.clips[id];
            if (!(clip.frames instanceof Array) || clip.frames.length == 0 || !(clip.milestones instanceof Array)) return false;
            for (i = 0; i < clip.frames.length; i++) {
                var pid:Number = clip.frames[i];
                if (!(pid >= 0 && pid < data.poses.length && pid == (pid | 0))) return false;
            }
            for (i = 0; i < clip.milestones.length; i++) {
                var index:Number = clip.milestones[i];
                if (!(index >= 0 && index < clip.frames.length && index == (index | 0))) return false;
            }
        }
        return true;
    }
}
