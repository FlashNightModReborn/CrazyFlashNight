/** Real AVM1 call through the production challenge refusal handler; no persistence. */
class org.flashNight.arki.stageSelect.StageSelectChallengeEntryTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var replies:Array;
    private static var jumps:Number;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[TEST_FAIL] StageSelectChallengeEntry " + label); }
    }
    private static function receive(value:String):Void { replies.push(value); }
    private static function jump():Void { jumps++; }
    public static function runAllTests():Void {
        passed=0; failed=0; replies=[]; jumps=0;
        var old:Object={server:_root.server,commands:_root.gameCommands,challenge:_root.isChallengeMode,
            ext:_root._saveExt,fade:_root.淡出动画,world:_root.gameworld,frameValue:_root.关卡地图帧值};
        var frame:Number=Number(_root._currentframe);
        var world:Object={场景名:"基地场景-基地门口"};
        try {
            _root.server={sendSocketMessage:receive};
            _root.gameCommands={}; _root.isChallengeMode=function():Boolean { return true; };
            _root._saveExt=null; _root.gameworld=world;
            _root.淡出动画={淡出跳转帧:jump}; _root.关卡地图帧值="challenge.fixture.original";
            org.flashNight.arki.stageSelect.StageSelectPanelService.install();
            org.flashNight.arki.stageSelect.StageSelectPanelService.handleReturnFrame({callId:"challenge.fixture",returnFrameLabel:"地图-测试空间"});
            check(replies.length==1,"exactly one response");
            var codec:LiteJSON=new LiteJSON(); var reply:Object=codec.parse(replies[0]);
            check(reply.success===false && reply.error=="challenge_mode_restricted","production handler refuses challenge test-space");
            check(reply.callId=="challenge.fixture","response retains call identity");
            check(jumps==0,"refusal never starts navigation");
            check(_root.gameworld===world,"refusal preserves world");
            check(Number(_root._currentframe)===frame,"refusal preserves root frame");
            check(_root.关卡地图帧值=="challenge.fixture.original","refusal preserves return target");
        } finally {
            _root.server=old.server;_root.gameCommands=old.commands;_root.isChallengeMode=old.challenge;
            _root._saveExt=old.ext;_root.淡出动画=old.fade;_root.gameworld=old.world;_root.关卡地图帧值=old.frameValue;
        }
        trace("StageSelectChallengeEntryTest Tests Passed: "+passed);
        trace("StageSelectChallengeEntryTest Tests Failed: "+failed);
    }
}
