import org.flashNight.arki.skill.SkillLoadoutServiceTest;
import org.flashNight.arki.skill.SkillPanelServiceTest;

/** Skill 面板与配装的稳定聚合；玩家手动输入链由独立 tracked runner 承接。 */
class org.flashNight.arki.skill.SkillMigrationTestSuite {
    public static function runAllTests():Void {
        trace("=== SkillMigrationTestSuite START ===");
        SkillLoadoutServiceTest.runAllTests();
        SkillPanelServiceTest.runAllTests();
        trace("=== SkillMigrationTestSuite END ===");
    }
}
