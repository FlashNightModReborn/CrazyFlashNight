using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NotchWidgetAnimationTests
    {
        [Fact]
        public void ExpandAndCollapse_OnlyPublishBoundsAtEndpoints()
        {
            using (Control anchor = new Control())
            {
                NotchWidget widget = new NotchWidget(
                    anchor,
                    new FpsRingBuffer(300),
                    "",
                    null, null, null, null,
                    new AudioHudState());
                int boundsEvents = 0;
                int repaintEvents = 0;
                widget.BoundsOrVisibilityChanged += delegate { boundsEvents++; };
                widget.RepaintRequested += delegate { repaintEvents++; };

                widget.BeginExpandForTest();
                Assert.True(widget.HasCompositeReservationForTest);
                Assert.Equal(1, boundsEvents);

                widget.Tick(75);
                widget.Tick(75);
                Assert.Equal(1, boundsEvents);
                Assert.True(repaintEvents >= 2);

                widget.BeginCollapseForTest();
                widget.Tick(100);
                Assert.Equal(1, boundsEvents);
                Assert.True(widget.HasCompositeReservationForTest);

                widget.Tick(100);
                Assert.Equal(2, boundsEvents);
                Assert.False(widget.HasCompositeReservationForTest);
            }
        }

        [Fact]
        public void ExpandedLayout_StaysLeftOfRightActionsAtDesignViewport()
        {
            using (Control anchor = new Control())
            {
                anchor.Size = new Size(1024, 576);
                NotchWidget widget = new NotchWidget(
                    anchor,
                    new FpsRingBuffer(300),
                    "",
                    null, null, null, null,
                    new AudioHudState());
                widget.ForceGameReadyForTest(true);
                widget.ForceCurrenciesForTest(2241561, 1351758);

                Size expanded = widget.SizeForProgressForTest(1f);
                Rectangle viewport = new Rectangle(0, 0, 1024, 576);
                Rectangle actions = RightHudLayout.TopToolsRectFromViewport(viewport, 1f);
                int notchRight = (viewport.Width + expanded.Width) / 2;

                Assert.True(expanded.Width <= RightHudLayout.PreferredNotchMaxWidthBase);
                Assert.True(actions.Left - notchRight >= RightHudLayout.NotchRightGapBase);
            }
        }

        [Fact]
        public void OtherMenu_UsesThreeCompactGroupsAndClosesWithNotch()
        {
            using (Control anchor = new Control())
            {
                NotchWidget widget = new NotchWidget(
                    anchor,
                    new FpsRingBuffer(300),
                    "",
                    null, null, null, null,
                    new AudioHudState());
                widget.ForceGameReadyForTest(true);

                widget.OpenOtherMenuForTest(0);
                Assert.True(widget.IsOtherMenuOpenForTest);
                Assert.Equal(0, widget.OtherMenuGroupIndexForTest);
                Assert.Equal(5, widget.OtherMenuItemCountForTest);

                widget.OpenOtherMenuForTest(1);
                Assert.Equal(7, widget.OtherMenuItemCountForTest);
                widget.OpenOtherMenuForTest(2);
                Assert.Equal(4, widget.OtherMenuItemCountForTest);

                widget.BeginCollapseForTest();
                Assert.False(widget.IsOtherMenuOpenForTest);
                Assert.Equal(0, widget.OtherMenuGroupIndexForTest);
            }
        }


        [Fact]
        public void GameToolbar_ModernAndLegacyExposeSameSevenRoutesIncludingMaterialsAndSkills()
        {
            string[] modern = NotchWidget.ToolbarRoutesForTest();
            string[] legacy = NotchOverlay.ToolbarRoutesForTest();
            Assert.Equal(
                new[] { "TEAM", "TABLET", "WAREHOUSE", "INTELLIGENCE", "MATERIALS", "SKILLS", "SHOP" },
                modern);
            Assert.Equal(modern, legacy);
        }
    }
}
