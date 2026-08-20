using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class PreparationNavigationTests
    {
        [Fact]
        public void FrozenTuple_HasExactIdentityLabelOrderAndCommand()
        {
            PreparationRoute[] routes =
                PreparationNavigationCatalog.FrozenRoutes.ToArray();

            Assert.Equal(
                new[]
                {
                    "equipment",
                    "battlebox",
                    "tuning",
                    "skills",
                    "materials",
                    "intelligence"
                },
                routes.Select(x => x.Identity).ToArray());
            Assert.Equal(
                new[]
                {
                    "装备",
                    "战备箱",
                    "装备调制",
                    "技能",
                    "材料",
                    "情报"
                },
                routes.Select(x => x.Label).ToArray());
            Assert.Equal(
                new[]
                {
                    "EQUIP_UI",
                    "WAREHOUSE",
                    "EQUIPMENT_TUNING",
                    "SKILLS",
                    "MATERIALS",
                    "INTELLIGENCE"
                },
                routes.Select(x => x.CommandKey).ToArray());
        }

        [Fact]
        public void RolloutOff_PreservesProductionSevenRouteGameRow()
        {
            string[] expected =
            {
                "TEAM",
                "TABLET",
                "WAREHOUSE",
                "INTELLIGENCE",
                "MATERIALS",
                "SKILLS",
                "SHOP"
            };

            Assert.Equal(
                expected,
                NotchWidget.ToolbarRoutesForTest());
        }

        [Fact]
        public void RolloutOn_NativeHasFourRows()
        {
            NotchToolbarRow[] native =
                NotchWidget.ToolbarRowsForTest(
                    true,
                    true,
                    14);

            Assert.Equal(
                new[] { "游戏", "整备", "辅助", "系统" },
                native.Select(x => x.Label).ToArray());
            Assert.Equal(
                new[] { "TEAM", "TABLET", "SHOP" },
                native[0].Actions
                    .Select(x => x.CommandKey)
                    .ToArray());
            Assert.Equal(
                PreparationNavigationCatalog.FrozenRoutes
                    .Select(x => x.CommandKey)
                    .ToArray(),
                native[1].Actions
                    .Select(x => x.CommandKey)
                    .ToArray());
        }

        [Fact]
        public void ProgressionProjection_KeepsMembersVisibleAndExplainsDisabledState()
        {
            PreparationAvailability[] locked =
                PreparationNavigationCatalog.Project(
                    true,
                    13);
            PreparationAvailability battlebox =
                locked.Single(
                    x => x.Route.Identity == "battlebox");
            PreparationAvailability tuning =
                locked.Single(
                    x => x.Route.Identity == "tuning");

            Assert.All(locked, x => Assert.True(x.Visible));
            Assert.False(battlebox.Enabled);
            Assert.Equal(
                "完成基地整备后开放",
                battlebox.Reason);
            Assert.False(tuning.Enabled);
            Assert.Equal(
                "完成基地整备后开放",
                tuning.Reason);

            PreparationAvailability[] unlocked =
                PreparationNavigationCatalog.Project(
                    true,
                    14);
            Assert.All(
                new[] { "battlebox", "tuning" },
                identity =>
                {
                    PreparationAvailability item =
                        unlocked.Single(
                            x => x.Route.Identity == identity);
                    Assert.True(item.Visible);
                    Assert.True(item.Enabled);
                    Assert.Equal("", item.Reason);
                });
        }

        [Fact]
        public void RolloutOn_ProgressionProjectionKeepsMembersVisibleWithReasons()
        {
            NotchToolbarRow native =
                NotchWidget.ToolbarRowsForTest(
                    true,
                    true,
                    13)[1];

            Assert.All(
                native.Actions,
                x => Assert.True(x.Visible));
            NotchToolbarAction battlebox =
                native.Actions.Single(
                    x => x.CommandKey == "WAREHOUSE");
            Assert.False(battlebox.Enabled);
            Assert.Equal(
                "完成基地整备后开放",
                battlebox.Reason);
        }

        [Fact]
        public void ToolbarHeight_IsDerivedFromProjectedVisibleRowCount()
        {
            int nativeOld =
                NotchWidget.ExpandedToolbarHeightForTest(
                    false,
                    1f);
            int nativePreparation =
                NotchWidget.ExpandedToolbarHeightForTest(
                    true,
                    1f);

            Assert.Equal(82, nativeOld);
            Assert.Equal(108, nativePreparation);
            Assert.Equal(26, nativePreparation - nativeOld);
        }

        [Fact]
        public void NativeExpandedBounds_UseFourRowsAndDoNotCollapseLockedMember()
        {
            using (Control anchor = new Control())
            {
                anchor.Size = new Size(1024, 576);
                NotchWidget widget = new NotchWidget(
                    anchor,
                    new FpsRingBuffer(300),
                    "",
                    null,
                    null,
                    null,
                    null,
                    new AudioHudState(),
                    true);
                widget.ForceGameReadyForTest(true);
                widget.ForceCurrenciesForTest(2241561, 1351758);
                widget.ForceQuestProgressForTest(13);

                Size locked =
                    widget.SizeForProgressForTest(1f);
                widget.ForceQuestProgressForTest(14);
                Size unlocked =
                    widget.SizeForProgressForTest(1f);

                Assert.Equal(140, locked.Height);
                Assert.Equal(locked, unlocked);
                Rectangle viewport =
                    new Rectangle(0, 0, 1024, 576);
                Rectangle actions =
                    RightHudLayout.TopToolsRectFromViewport(
                        viewport,
                        1f);
                int notchRight =
                    (viewport.Width + locked.Width) / 2;
                Assert.True(
                    actions.Left - notchRight
                    >= RightHudLayout.NotchRightGapBase);
            }
        }
    }
}
