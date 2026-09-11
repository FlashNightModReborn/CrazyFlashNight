import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.task.TaskUtil;

/** 日常交付与胜利返回共用的只读候选；端点权限仍按调用场景分别取值。 */
class org.flashNight.arki.task.TaskDestinationOptions {
    public static function complete(id:String):Boolean {
        for (var i:Number = 0; i < _root.tasks_to_do.length; i++)
            if (String(_root.tasks_to_do[i].id) == id) return _root.taskCompleteCheck(i) === true;
        return false;
    }
    public static function build(origin:String, forReturn:Boolean):Object {
        var map:Object = MapDomainBridge.getProjection();
        var bootstrap:Object = MapDomainBridge.getBootstrap();
        var local:Array = [], other:Array = [], options:Object = {};
        for (var i:Number = 0; i < _root.tasks_to_do.length; i++) {
            var id:String = String(_root.tasks_to_do[i].id);
            if (_root.taskCompleteCheck(i) !== true) continue;
            var endpoint:Object = map.taskEndpoints[id].finish;
            if (forReturn ? endpoint.returnNavigable !== true : endpoint.navigable !== true) continue;
            var task:Object = TaskUtil.tasks[id];
            var location:String = String(endpoint.locationId);
            var label:String = String(bootstrap.locationLabels[location] || bootstrap.frames[location] || location);
            if (label.indexOf("地图-") == 0) label = label.substr(3);
            var key:String = "task." + id;
            var row:Object = {id:key, locationName:label, npcName:String(endpoint.npcName || task.finish_npc || ""),
                taskName:TaskUtil.getTaskText(task.title)};
            options["$" + key] = {kind:forReturn ? "stage_return" : "task_delivery", taskId:id,
                npcId:String(endpoint.npcId), placementId:String(endpoint.placementId), locationId:location};
            if (origin != "" && location == origin) local.push(row); else other.push(row);
        }
        var rows:Array = local.concat(other);
        return {rows:rows, options:options, signature:new LiteJSON().stringifySafe({rows:rows, options:options})};
    }
}
