#include "test-runners/cf6-playtest/PlaytestFixture.as"
_root.elderRenderCapture=true;
import org.flashNight.arki.unit.Action.Melee.*;
_root.elderRenderSwf = "../flashswf/arts/new/Codex老头素材.swf";
_root.elderRenderTag = "after";
_root.cf6ElderRenderComplete = function():Void {
    trace("FocusedTestRunId cf6-elder-render Complete: 0296ee22dcfa45a3bd3a3fc1f6a59f84");
};
trace("FocusedTestRunId cf6-elder-render Start: 0296ee22dcfa45a3bd3a3fc1f6a59f84");
org.flashNight.arki.unit.Action.Melee.Cf6ElderRenderTest.runAllTests();
