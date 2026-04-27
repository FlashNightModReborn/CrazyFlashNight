using System.Collections.Generic;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class RightContextWidgetTests
    {
        private class Capture
        {
            public int PauseToggleCount;
            public int ExpandCount;
            public List<string> Posts = new List<string>();
        }

        private static MapHudPayload BuildPayload()
        {
            MapHudPayload p = new MapHudPayload();
            p.ProtocolVersion = 1;
            p.Hotspots = new Dictionary<string, MapHudHotspotEntry>();

            MapHudHotspotEntry e1 = new MapHudHotspotEntry();
            e1.Meta = new MapHudMeta
            {
                PageId = "base",
                PageLabel = "基地",
                HotspotId = "base_dorm",
                Label = "宿舍",
                Group = ""
            };
            e1.Outline = new MapHudOutline
            {
                ViewportRect = new RectF { X = 0, Y = 0, W = 200, H = 100 },
                CurrentRect = new RectF { X = 60, Y = 30, W = 40, H = 30 },
                Blocks = new List<MapHudBlock>
                {
                    new MapHudBlock
                    {
                        HotspotId = "base_dorm",
                        Label = "宿舍",
                        SourceRect = new RectF { X = 50, Y = 20, W = 70, H = 45 }
                    }
                }
            };
            p.Hotspots["base_dorm"] = e1;
            return p;
        }

        private static RightContextWidget MakeWidget(out Capture cap)
        {
            cap = new Capture();
            Capture local = cap;
            LauncherCommandRouter router = new LauncherCommandRouter(
                socketServer: null,
                onSendKey: k => { },
                onToggleFullscreen: () => { },
                onToggleLog: () => { },
                onForceExit: () => { },
                postToWeb: s => local.Posts.Add(s),
                onPanelStateChanged: b => { },
                setActivePanel: name => { });
            Control anchor = new Control();
            RightContextWidget w = new RightContextWidget(
                anchor,
                router,
                MapHudDataCatalog.FromPayload(BuildPayload()),
                delegate { local.PauseToggleCount++; },
                delegate { local.ExpandCount++; });
            w.ForceGameReady(true);
            return w;
        }

        private static IReadOnlyDictionary<string, string> Snapshot(params string[] kvPieces)
        {
            Dictionary<string, string> dict = new Dictionary<string, string>();
            foreach (string p in kvPieces)
            {
                int colon = p.IndexOf(':');
                string k = colon > 0 ? p.Substring(0, colon) : p;
                dict[k] = p;
            }
            return dict;
        }

        [Fact]
        public void Ready_ShowsRightCluster()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            Assert.True(w.Visible);
        }

        [Theory]
        [InlineData("1", true)]
        [InlineData("2", true)]
        [InlineData("0", false)]
        [InlineData("3", false)]
        public void MapSection_VisibleOnlyForModeOneOrTwoWithKnownHotspot(string mode, bool expected)
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.ForceMapMode(mode);
            w.ForceMapHotspot("base_dorm");
            Assert.Equal(expected, w.MapSectionVisibleForTest);
        }

        [Fact]
        public void MapSection_CollapseHidesCardButKeepsWidgetVisible()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.ForceMapMode("1");
            w.ForceMapHotspot("base_dorm");
            Assert.True(w.MapSectionVisibleForTest);
            w.ToggleMapCollapsed();
            Assert.True(w.IsMapCollapsed);
            Assert.False(w.MapSectionVisibleForTest);
            Assert.True(w.Visible);
        }

        [Fact]
        public void QuestRowRoutes_MatchWebButtons()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            Assert.Equal("MAPHUD_TOGGLE", w.ResolveQuestRowRoute(0));
            Assert.Equal("EQUIP_UI", w.ResolveQuestRowRoute(1));
            Assert.Equal("TASK_UI", w.ResolveQuestRowRoute(2));
        }

        [Fact]
        public void TaskDone_FullyDeliverable_NoticeVisibleAndDeliverRoute()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.ForceDeliverState(true, "base_dorm", true, "1");
            Assert.True(w.QuestNoticeVisibleForTest);
            Assert.True(w.CanDeliver());
            Assert.Equal(RightContextWidget.ClickRoute.TaskDeliver, w.ResolveNoticeClickRoute());
            Assert.Equal("任务已达成 · 可交付", w.BuildTaskDoneText());
        }

        [Fact]
        public void TaskDone_InCombat_FallsBackToTaskUi()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.ForceDeliverState(true, "base_dorm", true, "3");
            Assert.False(w.CanDeliver());
            Assert.Equal(RightContextWidget.ClickRoute.TaskUi, w.ResolveNoticeClickRoute());
            Assert.Equal("任务已达成 · 战后交付", w.BuildTaskDoneText());
        }

        [Fact]
        public void LegacyTask_FlashesThenFallsBackToTaskDone()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.ForceDeliverState(true, "base_dorm", true, "1");
            w.OnLegacyUiData("task", new[] { "支线任务" });
            Assert.True(w.QuestNoticeVisibleForTest);
            Assert.True(w.HasActiveFlash);
            Assert.Equal("新任务: 支线任务", w.DisplayText);
            Assert.Equal(RightContextWidget.ClickRoute.TaskUi, w.ResolveNoticeClickRoute());
            w.AdvanceFlashMs(5001);
            Assert.False(w.HasActiveFlash);
            Assert.Equal("任务已达成 · 可交付", w.DisplayText);
            Assert.Equal(RightContextWidget.ClickRoute.TaskDeliver, w.ResolveNoticeClickRoute());
        }

        [Fact]
        public void BgmTitle_EnrollsAnimationTickAndPauseTogglesCallback()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            Assert.False(w.WantsAnimationTick);
            w.ForceBgmTitle("Track");
            w.ForceIsPlaying(true);
            Assert.True(w.WantsAnimationTick);
            w.SimulatePauseClick();
            Assert.True(w.IsPausedForTest);
            Assert.Equal(1, c.PauseToggleCount);
            Assert.False(w.WantsAnimationTick);
        }

        [Fact]
        public void ExpandClick_CallsExpandCallbackWithoutBgm()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.SimulateExpandClick();
            Assert.Equal(1, c.ExpandCount);
        }

        [Fact]
        public void UiData_FullChainUpdatesMapNoticeAndBgm()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.OnUiDataChanged(
                Snapshot("s:1", "mm:1", "mh:base_dorm", "td:1", "tdh:base_dorm", "tdn:1", "bgm:Final Sky", "pl:2"),
                new HashSet<string> { "s", "mm", "mh", "td", "tdh", "tdn", "bgm", "pl" });

            Assert.True(w.MapSectionVisibleForTest);
            Assert.True(w.QuestNoticeVisibleForTest);
            Assert.Equal("Final Sky", w.CurrentTitle);
            Assert.True(w.DisableVisualizersForTest);
        }
    }
}
