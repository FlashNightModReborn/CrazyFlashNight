#include "test-runners/cf6-playtest/PlaytestFixture.as"
_root.headbotRenderCapture=true;
import org.flashNight.arki.unit.Action.Melee.*;
_root.headbotRenderSwf = "../flashswf/arts/new/Codex大头机器人素材.swf";
_root.headbotRenderTag = "after";
_root.cf6HeadbotRenderComplete = function():Void {
    trace("FocusedTestRunId cf6-headbot-render Complete: 7f40b80fc27d46c3aa691865c01c7bf8");
};
trace("FocusedTestRunId cf6-headbot-render Start: 7f40b80fc27d46c3aa691865c01c7bf8");
org.flashNight.arki.unit.Action.Melee.Cf6HeadbotRenderTest.runAllTests();
