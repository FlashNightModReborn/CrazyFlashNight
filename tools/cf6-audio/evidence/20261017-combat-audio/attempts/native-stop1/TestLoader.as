#include "test-runners/cf6-playtest/PlaytestFixture.as"
_root.敌人函数={};
#include "test-runners/cf6-knockback-scope/EnemyKnockbackFixture.as"
import org.flashNight.arki.unit.Action.Melee.*;
_root.elderCapture = false;
_root.cf6ElderAssetComplete = function():Void {
    trace("FocusedTestRunId cf6-elder Complete: f65436bab42647c6ab4154dafb945ce4");
};
trace("FocusedTestRunId cf6-elder Start: f65436bab42647c6ab4154dafb945ce4");
org.flashNight.arki.unit.Action.Melee.Cf6ElderAssetTest.runAllTests();
