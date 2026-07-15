import org.flashNight.arki.skill.SkillLoadoutServiceTest;
import org.flashNight.arki.skill.SkillPanelServiceTest;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCoreTest;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownServiceTest;
import org.flashNight.arki.unit.Action.Skill.DrugInputServiceTest;

/** 可追踪的 Skill 主线聚合入口；TestLoader scratch 只调用这一行。 */
class org.flashNight.arki.skill.SkillMigrationTestSuite {
    public static function runAllTests():Void {
        trace("=== SkillMigrationTestSuite START ===");
        SkillLoadoutServiceTest.runAllTests();
        SkillPanelServiceTest.runAllTests();
        LongGunSubWeaponCoreTest.runAllTests();
        ManualCooldownServiceTest.runAllTests();
        DrugInputServiceTest.runAllTests();
        trace("=== SkillMigrationTestSuite END ===");
    }
}
