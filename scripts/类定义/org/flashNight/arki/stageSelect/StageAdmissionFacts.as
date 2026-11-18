import org.flashNight.arki.task.TaskUtil;
import org.flashNight.arki.scene.StageRunSession;

/** Facts requested by the host for this operation only. Unknown values are JSON null. */
class org.flashNight.arki.stageSelect.StageAdmissionFacts {
    public static function ready():Boolean {
        var hero = _root.gameworld[_root.控制目标];
        return hero != null && typeof _root.控制目标 == "string"
            && hero._parent === _root.gameworld && hero._name === _root.控制目标
            && _root.savePath != null && String(_root.savePath) != "" && _root.存档系统 != null
            && _root._taskReloadBusy !== true && typeof _root.isChallengeMode == "function"
            && !_root.存档系统.hasRewardCommitPending() && StageRunSession.hasSettledAdmissionFacts();
    }

    private static function count(value) {
        return typeof value == "number" && value >= 0 && value <= 9007199254740991
            && value == Math.floor(value) ? value : null;
    }

    private static function validMode(value):Boolean {
        return value === "简单" || value === "冒险" || value === "修罗" || value === "地狱";
    }

    private static function clearModes(name:String):Array {
        var store:Object = _root._saveExt.stageHistory;
        if (store == null || store.version !== 1) return null;
        var source = store.stages["stage:" + name].difficulties;
        if (!(source instanceof Array) || source.length > 4) return null;
        var seen:Object = {};
        for (var i:Number = 0; i < source.length; i++) {
            if (!validMode(source[i]) || seen[source[i]] === true) return null;
            seen[source[i]] = true;
        }
        return source.slice();
    }

    private static function objective(data:Object):String {
        var goals = data.finish_requirements;
        if (!(goals instanceof Array) || goals.length != 1 || typeof goals[0] != "string") return null;
        var stage:String = goals[0].split("#")[0];
        return _root._saveExt.stageAdmissionPending["stage:"+stage] == null ? goals[0] : null;
    }

    private static function credibleRemaining(entry:Object, expected:String):Boolean {
        if (entry.admissionStageObjectivesUnknown === true) return false;
        var stages = entry.requirements.stages;
        if (!(stages instanceof Array) || stages.length > 1 || expected == null) return false;
        if (stages.length == 0) return true;
        var parts:Array = expected.split("#");
        return parts.length == 2 && stages[0].name === parts[0] && stages[0].difficulty === parts[1];
    }

    private static function sampleTask(id:String, fields:Array):Object {
        var result:Object = {};
        var data:Object = TaskUtil.getRawTaskData(id);
        var index:Number = -1;
        var todo = _root.tasks_to_do;
        var valid:Boolean = todo instanceof Array && data != null;
        var i:Number;
        var checkedObjective:Boolean = false;
        for (i = 0; i < fields.length; i++) if (fields[i] == "objective") checkedObjective = true;
        if (valid) for (i = 0; i < todo.length; i++) {
            if (todo[i] == null || todo[i].id == null) { valid = false; break; }
            if (String(todo[i].id) == id) {
                if (index >= 0) { valid = false; break; }
                index = i;
            }
        }
        for (i = 0; i < fields.length; i++) {
            var field:String = String(fields[i]);
            var value = null;
            if (data != null) {
                if (field == "objective") value = objective(data);
                else if (field == "finished" && typeof _root.tasks_finished == "object" && _root.tasks_finished != null) {
                    if (id != "54" || _root._saveExt.stageAdmissionUnknownFinished54 !== true)
                        value = _root.tasks_finished[id] === undefined ? 0 : count(_root.tasks_finished[id]);
                } else if (field == "active" && valid) value = index >= 0;
                else if (field == "available" && valid && typeof _root.taskAvailable == "function")
                    value = _root.taskAvailable(id) === true;
                else if (field == "deliverable" && valid && typeof _root.taskCompleteCheck == "function") {
                    if (index < 0) value = false;
                    else if (todo[index].requirements.stages instanceof Array
                            && (!checkedObjective || credibleRemaining(todo[index], objective(data))))
                        value = _root.taskCompleteCheck(index) === true;
                }
            }
            result[field] = value;
        }
        return result;
    }

    public static function capture(scope:Object):Object {
        if (!ready() || !(scope.chains instanceof Array) || !(scope.clears instanceof Array)
                || scope.tasks == null) return null;
        var facts:Object = {chains:{}, tasks:{}, clears:{}};
        var i:Number;
        for (i = 0; i < scope.chains.length; i++) {
            var key:String = scope.chains[i];
            facts.chains[key] = count(key == "主线" ? _root.主线任务进度 : _root.task_chains_progress[key]);
        }
        if (scope.assets instanceof Array) {
            facts.assets = {money:count(_root.金钱), kpoints:count(_root.虚拟币), level:count(_root.等级)};
        }
        for (var id:String in scope.tasks) facts.tasks[id] = sampleTask(id, scope.tasks[id]);
        for (i = 0; i < scope.clears.length; i++) facts.clears[scope.clears[i]] = clearModes(scope.clears[i]);
        return {facts:facts, challenge:_root.isChallengeMode() === true, force:_root.Web选关强制解锁 === true};
    }
}
