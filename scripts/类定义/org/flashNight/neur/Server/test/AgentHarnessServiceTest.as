import org.flashNight.neur.Server.AgentHarnessService;

class org.flashNight.neur.Server.test.AgentHarnessServiceTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;

    private static function check(cond:Boolean, label:String):Void {
        if (cond) {
            _passed++;
        } else {
            _failed++;
            trace("FAIL AgentHarnessServiceTest: " + label);
        }
    }

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;

        var savedSlot = _root.savePath;
        var savedExt = _root._saveExt;
        var savedServer = _root.server;
        var savedCommands = _root.gameCommands;
        var savedTimer = _root.帧计时器;
        var savedHeroKeys = {
            left: _root.左键, right: _root.右键, interact: _root.互动键, wskill: _root.武器技能键
        };

        try {
            var sent:Array = [];
            _root.server = {
                sendSocketMessage: function(msg:String):Boolean {
                    sent.push(msg);
                    return true;
                }
            };
            _root.gameCommands = {};
            _root.帧计时器 = { 当前帧数: 100 };
            _root.左键 = 65;
            _root.右键 = 68;
            _root.互动键 = 69;
            _root.武器技能键 = 70;

            AgentHarnessService.install();
            check(!AgentHarnessService.isActive(), "inert before bind");
            check(typeof _root.gameCommands["agentHarnessCmd"] == "function", "agentHarnessCmd installed");

            // Refuse real player save slots
            _root.savePath = "crazyflasher7_saves";
            _root.gameCommands["agentHarnessCmd"]({
                sub: "bind", requestId: "r1", slot: "crazyflasher7_saves", sessionEpoch: "e1"
            });
            check(!AgentHarnessService.isActive(), "rejects player save slot");
            check(sent.length == 1 && sent[0].indexOf('"ok":false') >= 0, "player save bind emits failure");

            // Allow cf7_agent_* slot
            sent = [];
            _root.savePath = "cf7_agent_unit_test";
            _root.gameCommands["agentHarnessCmd"]({
                sub: "bind", requestId: "r2", slot: "cf7_agent_unit_test", sessionEpoch: "e2"
            });
            check(AgentHarnessService.isActive(), "binds cf7_agent_* slot");
            check(_root._agentHarnessActive === true, "sets _root._agentHarnessActive");
            check(sent.length == 1 && sent[0].indexOf('"ok":true') >= 0, "bind emits ok=true");

            // hold_mask expires after TTL
            _root.gameCommands["agentHarnessCmd"]({
                sub: "world_act", requestId: "r3", act: "hold_mask", mask: 2, durationFrames: 5
            });
            check(AgentHarnessService.sampleMask(null, 100) == 2, "mask active at frame 100");
            check(AgentHarnessService.sampleMask(null, 105) == 2, "mask active at frame 105");
            check(AgentHarnessService.sampleMask(null, 106) == 0, "mask auto-expires at frame 106");

            // virtual key works with bridge & expires
            _root.gameCommands["agentHarnessCmd"]({
                sub: "world_act", requestId: "r4", act: "tap_key", key: "互动键", durationFrames: 4
            });
            check(AgentHarnessService.isVirtualKeyDown(69) === true, "virtual interact key down at 100");
            check(_root._agentHarnessBridge.isKeyDown(69) === true, "bridge interact key down at 100");
            _root.帧计时器.当前帧数 = 104;
            check(AgentHarnessService.isVirtualKeyDown(69) === true, "virtual interact key down at 104");
            _root.帧计时器.当前帧数 = 105;
            check(AgentHarnessService.isVirtualKeyDown(69) === false, "virtual interact key auto-expires at 105");

            // bookrun_ owned by cf7_agent_ remains active, while bookrun_ owned by real player disarms
            _root.savePath = "bookrun_test_session";
            _root._saveExt = { bookRun: { originSlot: "cf7_agent_unit_test" } };
            check(AgentHarnessService.isActive() === true, "allows bookrun owned by cf7_agent_*");
            _root._saveExt = { bookRun: { originSlot: "crazyflasher7_saves" } };
            check(AgentHarnessService.isActive() === false, "disarms on bookrun owned by player save");

            // Re-bind for disconnect test; disarms immediately if _root.savePath switches to player slot
            _root._saveExt = undefined;
            _root.savePath = "cf7_agent_unit_test";
            _root.gameCommands["agentHarnessCmd"]({
                sub: "bind", requestId: "r5", slot: "cf7_agent_unit_test", sessionEpoch: "e2"
            });
            _root.savePath = "crazyflasher7_saves";
            check(AgentHarnessService.isActive() === false, "disarms on non-agent slot");
            check(AgentHarnessService.sampleMask(null, 105) === 0, "mask zero after disarm");

            AgentHarnessService.onTransportDisconnected();
            check(!AgentHarnessService.isActive(), "clean on disconnect");
        } finally {
            AgentHarnessService.onTransportDisconnected();
            _root.savePath = savedSlot;
            _root._saveExt = savedExt;
            _root.server = savedServer;
            _root.gameCommands = savedCommands;
            _root.帧计时器 = savedTimer;
            _root.左键 = savedHeroKeys.left;
            _root.右键 = savedHeroKeys.right;
            _root.互动键 = savedHeroKeys.interact;
            _root.武器技能键 = savedHeroKeys.wskill;
        }

        trace("AgentHarnessServiceTest Tests Passed: " + _passed);
        trace("AgentHarnessServiceTest Tests Failed: " + _failed);
        trace("--- AgentHarnessServiceTest: " + _passed + "/" + (_passed + _failed) + " passed, " + _failed + " failed ---");
    }
}
