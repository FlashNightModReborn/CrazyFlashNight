/** Lee 原生角色试战的本地定义。配置未确认时不接纳临时角色，无内嵌玩法 fallback。 */
class org.flashNight.arki.scene.LeeTrialDefinition {
    private static var _data:Object;
    private static var _loading:Boolean = false;
    public static function get():Object { return _data; }
    public static function ready():Boolean { return _data != null; }
    public static function load():Void {
        if (_loading || ready()) return;
        _loading = true;
        var loader:org.flashNight.gesh.json.LoadJson.BaseJSONLoader = new org.flashNight.gesh.json.LoadJson.BaseJSONLoader(
            "data/stages/books/lee-trial.json", "LiteJSON");
        loader.load(function(data:Object):Void {
            org.flashNight.arki.scene.LeeTrialDefinition.accept(data);
        }, function(error:String):Void {
            org.flashNight.arki.scene.LeeTrialDefinition.loadFailed();
        });
    }
    public static function loadFailed():Void { _loading = false; }
    public static function accept(data:Object):Boolean {
        _loading = false;
        if (!valid(data)) return false;
        if (!ready()) _data = org.flashNight.gesh.object.PersistedSnapshot.clone(data);
        return true;
    }
    private static function integer(value, minimum:Number, maximum:Number):Boolean {
        return typeof value == "number" && !isNaN(value) && Math.floor(value) == value
            && !(value < minimum) && !(value > maximum);
    }
    public static function valid(data:Object):Boolean {
        if (data == null || data.schema !== "lee-trial.v1" || data.id !== "lee-trial"
                || typeof data.stageName != "string" || data.stageName.length == 0 || data.stageName.length > 64
                || data.actor.identifier !== "敌人-李小龙" || typeof data.actor.name != "string"
                || data.actor.name.length == 0 || data.actor.name.length > 32 || data.actor.gender !== "男"
                || !integer(data.actor.level, 1, 60) || !integer(data.actor.height, 50, 300)
                || !(data.stages instanceof Array) || data.stages.length == 0 || data.stages.length > 4) return false;
        var assault:Object = data.assault;
        if (assault != undefined && (assault.schema !== "lee-assault.v1"
                || !integer(assault.boltsPerRoom, 1, 60) || !integer(assault.damagePerBolt, 1, 1000)
                || !integer(assault.awakeningHits, 1, assault.boltsPerRoom * 3)
                || !integer(assault.reviveCoins, 1, 8) || !integer(assault.warningFrames, 1, 120)
                || !integer(assault.gapFrames, 1, 120) || !integer(assault.recoveryFrames, 30, 600)
                || !integer(assault.finalRecoveryFrames, 600, 18000)
                || !(assault.finalRecoveryFrames > assault.recoveryFrames)
                || !integer(assault.battleLight, 0, 7) || typeof assault.outageLight != "number"
                || isNaN(assault.outageLight) || assault.outageLight < 0 || assault.outageLight > assault.battleLight)) return false;
        if (assault != undefined && !validDialogues(assault.dialogues)) return false;
        var promotions:Object = data.actor.宠物属性;
        if (promotions != undefined) {
            if (typeof promotions != "object" || promotions instanceof Array) return false;
            for (var promotion:String in promotions) {
                if (promotion != "冲腿龙息" || promotions[promotion] !== true) return false;
            }
        }
        for (var s:Number = 0; s < data.stages.length; s++) {
            var stage:Object = data.stages[s];
            if (typeof stage.BasicInformation.Background != "string"
                    || stage.BasicInformation.Background.indexOf("flashswf/backgrounds/") != 0
                    || stage.BasicInformation.Background.indexOf("..") >= 0
                    || stage.BasicInformation.EndFrame !== "房间"
                    || ((stage.BasicInformation.PlayerX != undefined || stage.BasicInformation.PlayerY != undefined)
                        && (!integer(stage.BasicInformation.PlayerX, 0, 10000) || !integer(stage.BasicInformation.PlayerY, 0, 10000)))
                    || !(stage.Wave.SubWave instanceof Array) || stage.Wave.SubWave.length == 0
                    || stage.Wave.SubWave.length > 16
                    || !(stage.Instances.Instance instanceof Array) || stage.Instances.Instance.length != 0
                    || !(stage.Pickups.Pickup instanceof Array) || stage.Pickups.Pickup.length != 0) return false;
            for (var w:Number = 0; w < stage.Wave.SubWave.length; w++) {
                var enemies:Array = stage.Wave.SubWave[w].EnemyGroup.Enemy;
                if (!(enemies instanceof Array) || enemies.length == 0 || enemies.length > 8) return false;
                for (var i:Number = 0; i < enemies.length; i++) {
                    var enemy:Object = enemies[i];
                    if (typeof enemy.Type != "string" || enemy.Type.indexOf("兵种") != 0
                            || !integer(Number(enemy.Type.substr(2)), 1, 10000)
                            || enemy.Type !== "兵种" + Number(enemy.Type.substr(2))
                            || !integer(enemy.Level, 1, 60) || !integer(enemy.Quantity, 1, 12)
                            || enemy.Parameters.不掉钱 !== true || enemy.Parameters.不掉装备 !== true || enemy.Parameters.最小经验值 !== 0 || enemy.Parameters.最大经验值 !== 0
                            || !(enemy.Parameters.掉落物 instanceof Array) || enemy.Parameters.掉落物.length != 0) return false;
                }
            }
        }
        return true;
    }
    private static function validDialogues(beats:Object):Boolean {
        var ids:Array = [
            "lee-entry-0","lee-clear-0","lee-after-0","lee-after-0-dodged",
            "lee-after-0-revived","lee-entry-1","lee-entry-1-revived","lee-clear-1",
            "lee-clear-1-observe","lee-clear-1-revived","lee-awaken-early","lee-after-1",
            "lee-after-1-dodged","lee-after-1-revived","lee-entry-2-awakened","lee-entry-2",
            "lee-entry-2-revived","lee-clear-2-awakened","lee-clear-2","lee-clear-2-observe",
            "lee-clear-2-revived","lee-after-2-awakened","lee-awaken-late","lee-after-2",
            "lee-entry-3-early","lee-entry-3-late","lee-clear-3","lee-after-3"
        ];
        for (var i:Number = 0; i < ids.length; i++) {
            var rows:Array = beats[ids[i]];
            if (!(rows instanceof Array) || rows.length == 0 || rows.length > 6) return false;
            for (var j:Number = 0; j < rows.length; j++) {
                var row:Object = rows[j];
                if ((row.name !== "Lee" && row.name !== "黑龙") || row.char !== row.name || typeof row.text != "string"
                        || row.text.length == 0 || row.text.length > 500) return false;
            }
        }
        return true;
    }
    public static function stages():Array {
        if (!ready()) return [];
        var stages = org.flashNight.gesh.object.PersistedSnapshot.clone(_data.stages);
        // The trial opponent derives actor facts from the same definition as the player.
        // This is a local clone; never write changes back into the loaded configuration.
        for (var s:Number = 0; s < stages.length; s++) {
            var waves:Array = stages[s].Wave.SubWave;
            for (var w:Number = 0; w < waves.length; w++) {
                var enemies:Array = waves[w].EnemyGroup.Enemy;
                for (var i:Number = 0; i < enemies.length; i++) {
                    var enemy:Object = enemies[i];
                    if (enemy.InstanceName == "leeTrialOpponent" && enemy.Type == "兵种40") {
                        enemy.Level = _data.actor.level;
                        enemy.Parameters.身高 = _data.actor.height;
                        enemy.Parameters.宠物属性 = org.flashNight.gesh.object.PersistedSnapshot.clone(_data.actor.宠物属性 || {});
                    }
                }
            }
        }
        return stages;
    }
}
