/** U4 健身入口：打开完整 Web 工作台，并安装 AS2 权威训练与完成结算命令。 */
class org.flashNight.arki.ui.GymPreviewPanelService {
    public static function install():Void {
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        org.flashNight.arki.ui.GymTrainingPanelService.install();
        _root.gameCommands["openGymPreview"] = function(stationId:String):Boolean {
            return org.flashNight.arki.ui.GymPreviewPanelService.openPanel(stationId);
        };
        // 隔离克隆槽的 agent_control 入口只打开木人桩面板，付费项目仍由玩家在 Web 中选择。
        _root.gameCommands["openGymForAgent"] = function():Boolean {
            return org.flashNight.arki.ui.GymPreviewPanelService.openPanel("dummy");
        };
    }

    public static function openPanel(stationId:String):Boolean {
        if (stationId != "dummy" && stationId != "dumbbell" && stationId != "squat") return false;
        if (_root.server == undefined || typeof _root.server.sendSocketMessage != "function") return false;
        var preview:Object = org.flashNight.arki.ui.GymTrainingPanelService.prepareOpen(stationId);
        if (preview == null || preview.error != undefined) return false;
        var json:LiteJSON = new LiteJSON();
        var snapshotJson:String = json.stringifySafe(preview);
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "gym", "world_gym", [], [
                {name:"stationId", value:preview.stationId},
                {name:"snapshotJson", value:snapshotJson}
            ]
        );
        if (_root.server.sendSocketMessage(payload) === false) {
            org.flashNight.arki.ui.GymTrainingPanelService.retireOpen(preview.openToken);
            return false;
        }
        return true;
    }
}
