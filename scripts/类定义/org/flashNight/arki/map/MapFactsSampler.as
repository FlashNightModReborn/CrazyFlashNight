/**
 * 只采集地图需要的 AS2 事实，不求值地图条件，不发布完整背包或玩家存档。
 */
class org.flashNight.arki.map.MapFactsSampler {
    public static function scene():Object {
        // 保留原对象字段的建立顺序，既有 facts JSON 签名不因改写而漂移。
        var result:Object = {stageFlag:"", frameLabel:"", entrance:"", mapFrame:"", inCombat:false};
        writeScene(_root, result);
        return result;
    }
    /** 归一化规则与事实快照共用；同步观察可复用自己的普通 Object scratch。 */
    public static function writeScene(source:Object, result:Object):Void {
        result.stageFlag = String(source.关卡标志 || "");
        result.frameLabel = String(source._currentlabel || "");
        result.entrance = String(source.场景进入位置名 || "");
        result.mapFrame = String(source.关卡地图帧值 || "");
        result.inCombat = source.当前为战斗地图 == true;
    }
    public static function capture(bootstrap:Object, interests:Array):Object {
        var hero:Object = _root.gameworld[_root.控制目标];
        var ready:Boolean = hero != undefined && typeof _root.控制目标 == "string"
            && hero._parent === _root.gameworld && hero._name === _root.控制目标
            && _root.tasks_to_do instanceof Array && _root.tasks_finished != undefined
            && _root.task_chains_progress != undefined;
        var chains:Object = {};
        var finished:Object = {};
        var active:Array = [];
        var deliverable:Array = [];
        var available:Object = {};
        var known:Object = {};
        var i:Number;
        var id:String;
        var value:Number;
        for (i = 0; i < bootstrap.chains.length; i++) {
            var chain:String = String(bootstrap.chains[i]);
            value = Number(_root.task_chains_progress[chain]);
            chains[chain] = isNaN(value) || value < 0 ? 0 : value;
        }
        for (i = 0; i < bootstrap.taskIds.length; i++) {
            id = String(bootstrap.taskIds[i]); known["$" + id] = true;
            value = Number(_root.tasks_finished[id]);
            if (!isNaN(value) && value > 0) finished[id] = value;
        }
        if (ready) {
            for (i = 0; i < _root.tasks_to_do.length; i++) {
                id = String(_root.tasks_to_do[i].id);
                if (known["$" + id] !== true) continue;
                active.push(id);
                if (_root.taskCompleteCheck(i) === true) deliverable.push(id);
            }
        }
        var required:Array = [];
        for (i = 0; i < bootstrap.availableTaskIds.length; i++) required.push(String(bootstrap.availableTaskIds[i]));
        for (i = 0; i < interests.length; i++) required.push(String(interests[i]));
        if (ready) for (i = 0; i < required.length; i++) {
            id = required[i];
            if (known["$" + id] === true && available[id] == undefined) available[id] = _root.taskAvailable(id) === true;
        }
        var infrastructure:Object = _root.基建系统.infrastructure;
        var infrastructureFacts:Object = {};
        for (i = 0; i < bootstrap.infrastructureKeys.length; i++) {
            var infrastructureKey:String = String(bootstrap.infrastructureKeys[i]);
            value = Number(infrastructure[infrastructureKey]);
            if (infrastructure != undefined) infrastructureFacts[infrastructureKey] = isNaN(value) || value < 0 ? 0 : value;
        }
        var gender:String = String(_root.性别 || "");
        if (gender != "男" && gender != "女" && gender != "male" && gender != "female") gender = "";
        var facts:Object = {chains:chains, finished:finished, activeOrder:active, deliverableIds:deliverable,
            available:available,
            infrastructure:infrastructureFacts, flags:{},
            scene:scene(), navigation:{reason:String(org.flashNight.arki.scene.StageRunSession.getSceneExitBlockReason() || "")}};
        facts["dynamic"] = {roommateGender:gender};
        return {ready:ready, facts:facts};
    }
}
