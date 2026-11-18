/** 仅真实胜利写入；ext 随现有存档保存，不用发现记录推断通关。 */
class org.flashNight.arki.stageSelect.StageClearHistory {
    /** Task objectives change at the victory screen. A save or crash here must not
        turn that intermediate task state into evidence of a settled victory. */
    public static function pending(stageName:String, runId:String):Void {
        if (!stageName || !runId) return;
        if (_root._saveExt == null) _root._saveExt = {};
        if (_root._saveExt.stageAdmissionPending == null) _root._saveExt.stageAdmissionPending = {};
        _root._saveExt.stageAdmissionPending["stage:"+stageName] = runId;
        if (_root.存档系统 != null) _root.存档系统.dirtyMark = true;
    }

    /** Called inside the reward transaction. Its full-save commit or rollback covers both records. */
    public static function settle(stageName:String, difficulty:String):Void {
        record(stageName, difficulty);
        var pending:Object = _root._saveExt.stageAdmissionPending;
        if (pending != null) delete pending["stage:"+stageName];
    }

    public static function record(stageName:String, difficulty:String):Boolean {
        if (!stageName || stageName.length > 128 || !isDifficulty(difficulty)) return false;
        if (_root._saveExt == undefined) _root._saveExt = {};
        var ext:Object = _root._saveExt;
        var store:Object = ext.stageHistory;
        if (store == undefined) {
            store = {version:1, stages:{}};
            ext.stageHistory = store;
        }
        // 未认识的版本原样保留；通关本身不因可选历史损坏而失败。
        if (store.version !== 1 || typeof store.stages != "object" || store.stages == null) return false;
        var key:String = "stage:" + stageName;
        var entry:Object = store.stages[key];
        if (entry == undefined) {
            entry = {difficulties:[]};
            store.stages[key] = entry;
        }
        if (!(entry.difficulties instanceof Array)) return false;
        for (var i:Number = 0; i < entry.difficulties.length; i++) {
            if (entry.difficulties[i] === difficulty) return false;
        }
        if (entry.difficulties.length >= 4) return false;
        entry.difficulties.push(difficulty);
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
        return true;
    }

    public static function snapshot(stageName:String):Object {
        var result:Object = {cleared:false, difficulties:[]};
        var store:Object = _root._saveExt.stageHistory;
        if (store.version !== 1) return result;
        var entry:Object = store.stages["stage:" + stageName];
        if (!(entry.difficulties instanceof Array)) return result;
        var modes:Array = ["简单", "冒险", "修罗", "地狱"];
        for (var i:Number = 0; i < modes.length; i++) {
            for (var j:Number = 0; j < entry.difficulties.length; j++) {
                if (entry.difficulties[j] === modes[i]) {
                    result.difficulties.push(modes[i]);
                    break;
                }
            }
        }
        result.cleared = result.difficulties.length > 0;
        return result;
    }

    private static function isDifficulty(value:String):Boolean {
        return value == "简单" || value == "冒险" || value == "修罗" || value == "地狱";
    }
}
