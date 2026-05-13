/**
 * 文件：org/flashNight/arki/merc/ArenaPanelService.as
 * 说明：WebView 角斗场（DEATH MATCH）面板的 AS2 端桥。
 *
 * 同步管道（与 stage-select / map 同构）：
 *   Web → C# ArenaTask → Flash gameCommands:
 *     arenaSnapshot — 返回 money / reuseCount / reuseLimit / busy
 *     arenaEnter    — 接收 cardIndex/expr/deposit/reward，触发 ArenaController.requestOpponent
 *     arenaClose    — 仅记录关闭（无需清理状态，因为进场链未触发）
 *
 * 历史路径（Symbol 3394 选择界面 + DOMDocument frame 171）由 ArenaController
 * 全程承担，本服务只是把同样的 globals + 入口函数搬到 socket cmd 上。
 */
class org.flashNight.arki.merc.ArenaPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["arenaSnapshot"] = function(params) {
            org.flashNight.arki.merc.ArenaPanelService.handleSnapshot(params);
        };
        _root.gameCommands["arenaEnter"] = function(params) {
            org.flashNight.arki.merc.ArenaPanelService.handleEnter(params);
        };
        _root.gameCommands["arenaClose"] = function(params) {
            org.flashNight.arki.merc.ArenaPanelService.handleClose(params);
        };

        _inited = true;
    }

    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        sendResponse({
            task: "arena_response",
            callId: callId,
            success: true,
            snapshot: {
                money:       Number(_root.金钱) || 0,
                reuseCount:  Number(_root.当前佣兵重用数) || 0,
                reuseLimit:  Number(_root.竞技场佣兵重用基数) || 0,
                busy:        (_root.发布请求 == true) || (_root.决斗场进入中 == true)
            }
        });
    }

    public static function handleEnter(params:Object):Void {
        var callId = params.callId;

        var expr:String = String(params.expr || "");
        var deposit:Number = Number(params.deposit);
        var reward:Number = Number(params.reward);

        if (expr == "") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "invalid_expr" });
            return;
        }
        if (isNaN(deposit) || isNaN(reward) || deposit < 0 || reward < 0) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "invalid_amounts" });
            return;
        }
        if (_root.金钱 < deposit) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "insufficient_money" });
            return;
        }
        if (_root.发布请求 == true) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "busy" });
            return;
        }
        if (typeof _root.竞技场对手请求 != "function") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "arena_unavailable" });
            return;
        }
        if (typeof _root.载入关卡数据 != "function") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_loader_unavailable" });
            return;
        }
        if (_root.淡出动画 == undefined || _root.淡出动画.淡出跳转帧 == undefined) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_transition_unavailable" });
            return;
        }

        // 原始路径："DEATH MATCH角斗场" 的 StageInfo.FadeTransitionFrame = "角斗场选择挑战者",
        // 玩家先到那个帧、由该帧 stage-select 入口预先调过 _root.载入关卡数据 把
        // StageManager 初始化, 后续 enterArenaCommon → wuxianguotu_1 才能加载场景背景.
        // Web 面板直接跳关, 必须在此手动复现 stage 数据预载.
        var stageInfo:Object = _root.StageInfoDict ? _root.StageInfoDict["DEATH MATCH角斗场"] : undefined;
        if (stageInfo == undefined || stageInfo.url == undefined || String(stageInfo.url) == "") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_info_missing" });
            return;
        }

        _root.载入关卡数据(String(stageInfo.Type || "无限过图"), String(stageInfo.url));
        _root.关卡类型 = String(stageInfo.Type || "无限过图");
        _root.关卡路径 = String(stageInfo.url);

        _root.押金 = deposit;
        _root.角斗场奖金 = reward;
        _root.决斗场进入中 = true;

        sendResponse({
            task: "arena_response",
            callId: callId,
            success: true,
            closePanel: true,
            deposit: deposit,
            reward: reward,
            expr: expr
        });

        if (_root.soundEffectManager != undefined && _root.soundEffectManager.stopBGMForTransition != undefined) {
            _root.soundEffectManager.stopBGMForTransition();
        }
        _root.竞技场对手请求(expr);
    }

    public static function handleClose(params:Object):Void {
        // 仅当带 callId 时回包（Web 通过 ArenaTask 路径才会带）。
        // 无 callId 的情形（如未来 ResolvePanelCloseGameCommand 改 fire-and-forget）静默处理.
        if (params == undefined || params.callId == undefined) return;
        sendResponse({
            task: "arena_response",
            callId: params.callId,
            success: true
        });
    }

    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
    }
}
