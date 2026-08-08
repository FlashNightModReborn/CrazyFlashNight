import org.flashNight.aven.test.*;

import org.flashNight.arki.merc.ArenaPanelService;
import org.flashNight.arki.stageSelect.StageSelectPanelService;

class org.flashNight.arki.merc.ArenaPanelAuthorityTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        checkQuote(makeQuote("standard", 40, 50, 4, 1, 40, 200000, 100000),
            "standard authority recomputes the level-40 economy boundary");
        checkQuote(makeQuote("hidden", 5, 10, 2, 1.5, 5, 15000, 7500),
            "hidden authority applies its bounded multiplier");
        checkQuote(makeQuote("fallen", 44, 59, 5, 1, 59, 236000, 94000),
            "fallen authority recomputes bench-level reward and deposit");
        checkQuote(makeQuote("escalation", 44, 59, 5, 1, 59, 147500, 148000),
            "escalation authority recomputes wave-base economy");
        checkQuote(makeQuote("custom_pve", 1, 1, 1, 1, 1, 0, 0),
            "custom PVE authority is fixed to zero economy");

        var numericString:Object = makeQuote("standard", 5, 10, 2, 1, 5, 10000, 5000);
        numericString.levelMin = "5";
        checkRejected(numericString, "numeric strings cannot cross the AS2 authority boundary");

        var wrongExpr:Object = makeQuote("standard", 5, 10, 2, 1, 5, 10000, 5000);
        wrongExpr.expr = "#0@5-10%3";
        checkRejected(wrongExpr, "forged expressions are rejected");

        var wrongReward:Object = makeQuote("fallen", 44, 59, 5, 1, 59, 236000, 94000);
        wrongReward.reward = 999999999;
        checkRejected(wrongReward, "forged rewards are rejected");

        var missingDigest:Object = makeQuote("standard", 5, 10, 2, 1, 5, 10000, 5000);
        delete missingDigest.authoritySourceDigest;
        checkRejected(missingDigest, "missing source digest fails closed");

        var fractionalCount:Object = makeQuote("standard", 5, 10, 2, 1, 5, 10000, 5000);
        fractionalCount.opponentCount = 2.5;
        checkRejected(fractionalCount, "fractional opponent counts fail closed");

        var wrongStandardMultiplier:Object = makeQuote("standard", 5, 10, 2, 1.5, 5, 15000, 7500);
        checkRejected(wrongStandardMultiplier, "standard cards cannot smuggle a hidden multiplier");

        checkAgentArenaOpenContract();

        trace("ArenaPanelAuthorityTest Tests Passed: " + passed);
        trace("ArenaPanelAuthorityTest Tests Failed: " + failed);
    }

    private static function makeQuote(mode:String, levelMin:Number, levelMax:Number,
        opponentCount:Number, multiplier:Number, benchLevel:Number,
        reward:Number, deposit:Number):Object {
        return {
            authorityId:"test-" + mode,
            authorityMode:mode,
            authoritySourceDigest:"0123456789ABCDEF",
            levelMin:levelMin,
            levelMax:levelMax,
            opponentCount:opponentCount,
            economyMultiplier:multiplier,
            benchLevel:benchLevel,
            expr:"#0@" + levelMin + "-" + levelMax + "%" + opponentCount,
            reward:reward,
            deposit:deposit
        };
    }

    private static function checkQuote(input:Object, label:String):Void {
        var result:Object = ArenaPanelService.buildAuthorityQuote(input);
        check(result != null && result.mode == input.authorityMode
            && result.expr == input.expr && result.reward == input.reward
            && result.deposit == input.deposit, label);
    }

    private static function checkRejected(input:Object, label:String):Void {
        check(ArenaPanelService.buildAuthorityQuote(input) == null, label);
    }

    private static function checkAgentArenaOpenContract():Void {
        var oldServer:Object = _root.server;
        var oldCommands:Object = _root.gameCommands;
        var oldScene:Object = _root.场景转换函数;
        var oldTimer:Object = _root.帧计时器;
        var oldCurrentFrame = _root.Web选关当前帧值;
        var oldReturnFrame = _root.Web选关返回帧值;
        var oldMapFrame = _root.关卡地图帧值;
        var sent:Array = [];

        _root.gameCommands = {};
        _root.场景转换函数 = { Web选关打开中:true, 上次切换帧数:0 };
        _root.帧计时器 = { 当前帧数:7788 };
        _root.Web选关当前帧值 = "基地门口";
        _root.Web选关返回帧值 = "基地门口";
        _root.关卡地图帧值 = "基地门口";
        _root.server = {
            sendSocketMessage:function(payload:String):Boolean {
                sent.push(payload);
                return true;
            }
        };

        StageSelectPanelService.install();
        var opened:Boolean = _root.gameCommands.openArenaForAgent({
            panel:"workbench",
            difficulty:"地狱",
            initData:{ deposit:1 }
        });
        var payload:Object = sent.length == 1 ? new LiteJSON().parse(String(sent[0])) : null;
        check(opened && sent.length == 1 && payload != null
            && payload.task == "panel_request" && payload.panel == "arena"
            && payload.source == "stage_select_arena_redirect"
            && payload.initData.difficulty == "冒险"
            && payload.returnTo == "stage-select"
            && _root.场景转换函数.Web选关打开中 == false
            && _root.场景转换函数.上次切换帧数 == 7788,
            "agent opener ignores input and reuses the production AS2 panel_request route");

        _root.server = undefined;
        check(StageSelectPanelService.handleOpenArenaForAgent({}) == false,
            "agent opener fails closed when the AS2 socket is unavailable");

        _root.server = oldServer;
        _root.gameCommands = oldCommands;
        _root.场景转换函数 = oldScene;
        _root.帧计时器 = oldTimer;
        _root.Web选关当前帧值 = oldCurrentFrame;
        _root.Web选关返回帧值 = oldReturnFrame;
        _root.关卡地图帧值 = oldMapFrame;
    }

    private static function check(value:Boolean, label:String):Void {
        if (value) {
            passed++;
            trace("[PASS] " + label);
        } else {
            failed++;
            trace("[FAIL] " + label);
        }
    }
}
