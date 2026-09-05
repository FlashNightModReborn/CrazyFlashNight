using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Loot;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class RightContextWidgetTests
    {
        private class Capture
        {
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

        private static RightContextWidget MakeWidget(
            out Capture cap,
            LootIconCatalog itemIcons = null)
        {
            cap = new Capture();
            Capture local = cap;
            LauncherCommandRouter router = new LauncherCommandRouter(
                socketServer: null,
                onSendKey: k => { },
                onToggleFullscreen: () => { },
                onToggleLog: () => { },
                onForceExit: () => { },
                postToWeb: s => local.Posts.Add(s));
            Control anchor = new Control();
            RightContextWidget w = new RightContextWidget(
                anchor,
                router,
                MapHudDataCatalog.FromPayload(BuildPayload()),
                MapDisplayPreference.Compact,
                null,
                itemIcons);
            w.ForceGameReady(true);
            return w;
        }

        private static string FindIconsDir()
        {
            DirectoryInfo dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir != null)
            {
                string candidate = Path.Combine(
                    dir.FullName, "launcher", "web", "icons");
                if (File.Exists(Path.Combine(candidate, "manifest.json")))
                    return candidate;
                dir = dir.Parent;
            }
            throw new DirectoryNotFoundException(
                "launcher/web/icons not found above " + AppContext.BaseDirectory);
        }

        private static SafeExitPanelWidget MakeSafeExitWidget()
        {
            Capture cap = new Capture();
            LauncherCommandRouter router = new LauncherCommandRouter(
                socketServer: null,
                onSendKey: k => { },
                onToggleFullscreen: () => { },
                onToggleLog: () => { },
                onForceExit: () => { },
                postToWeb: s => cap.Posts.Add(s));
            SafeExitPanelWidget widget = new SafeExitPanelWidget(new Control(), router);
            widget.ForceGameReady(true);
            return widget;
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

        private static StageOutcomeState StageState(
            string outcome,
            string life,
            string settlement,
            bool reviveAllowed = false,
            long reviveCoins = 0,
            string reviveBlockedReason = "",
            bool canReturnBase = true,
            int remainingRewards = 0,
            int revision = 7)
        {
            JObject message = new JObject
            {
                ["task"] = "stage_outcome",
                ["payload"] = new JObject
                {
                    ["v"] = 1,
                    ["runId"] = "run.right-context.1",
                    ["revision"] = revision,
                    ["stageName"] = "摇滚公园",
                    ["difficulty"] = "地狱",
                    ["outcome"] = outcome,
                    ["life"] = life,
                    ["activeFrames"] = 1481,
                    ["reviveCoins"] = reviveCoins,
                    ["reviveAllowed"] = reviveAllowed,
                    ["reviveBlockedReason"] = reviveBlockedReason,
                    ["canReturnBase"] = canReturnBase,
                    ["settlement"] = settlement,
                    ["remainingRewards"] = remainingRewards
                }
            };
            StageOutcomeState state;
            string error;
            Assert.True(StageOutcomeState.TryParseMessage(
                message, out state, out error), error);
            return state;
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
        public void MapSection_DisplayPreferenceDoesNotOverwriteRuntimeMode()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.ForceMapMode("1");
            w.ForceMapHotspot("base_dorm");
            Assert.True(w.MapSectionVisibleForTest);
            Assert.Equal(RuntimeMapMode.Navigation, w.RuntimeMapModeForTest);

            w.ToggleMapDisplaySize();
            Assert.Equal(MapDisplayPreference.Expanded, w.MapDisplayPreferenceForTest);
            Assert.True(w.MapSectionVisibleForTest);

            w.ToggleMapDisplaySize();
            Assert.Equal(MapDisplayPreference.Compact, w.MapDisplayPreferenceForTest);
            Assert.True(w.MapSectionVisibleForTest);

            w.ToggleMapVisibility();
            Assert.Equal(MapDisplayPreference.Off, w.MapDisplayPreferenceForTest);
            Assert.True(w.IsMapCollapsed);
            Assert.False(w.MapSectionVisibleForTest);

            w.ToggleMapVisibility();
            Assert.Equal(MapDisplayPreference.Compact, w.MapDisplayPreferenceForTest);
            Assert.True(w.MapSectionVisibleForTest);
            Assert.True(w.Visible);
            Assert.Equal(RuntimeMapMode.Navigation, w.RuntimeMapModeForTest);
        }

        [Fact]
        public void CombatRuntimeMode_BlocksDeliveryRegardlessOfDisplayPreference()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.ForceDeliverState(true, "base_dorm", true, "3");
            w.SetMapDisplayPreference(MapDisplayPreference.Expanded);

            Assert.Equal(RuntimeMapMode.Combat, w.RuntimeMapModeForTest);
            Assert.Equal(MapDisplayPreference.Expanded, w.MapDisplayPreferenceForTest);
            Assert.Equal(EffectiveMapDisplayMode.Hidden, w.EffectiveMapDisplayModeForTest);
            Assert.False(w.CanDeliver());
        }

        [Fact]
        public void PersistentActionRow_UsesSixPrimaryRoutes()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            Assert.Equal("TASK_MAP", w.ResolveActionRoute(0));
            Assert.Equal("TASK_UI", w.ResolveActionRoute(1));
            Assert.Equal("EQUIP_UI", w.ResolveActionRoute(2));
            Assert.Equal("GAMESETTINGS", w.ResolveActionRoute(3));
            Assert.Equal("PAUSE", w.ResolveActionRoute(4));
            Assert.Equal("SAFEEXIT", w.ResolveActionRoute(5));
        }

        [Fact]
        public void MissingOwner_LeavesConditionalSlotWithoutVisualOrHitBox()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.ForceHoveredToolForTest(2);

            Assert.True(w.RequestsContextHint);
            Assert.Equal(RightContextSlotOwner.Hidden, w.SlotOwnerForTest);
            Assert.False(w.StatusSlotVisibleForTest);
            Assert.False(w.PaintsContextHintForTest);
            Assert.False(w.PaintsActionableNoticeForTest);
            Assert.False(w.SlotHitBoxActiveForTest);
        }

        [Fact]
        public void EquipmentHint_AddsRouteAndNeighborInformation()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);

            Assert.Equal(
                "打开角色构筑；其他整备功能在刘海或装备页",
                w.ResolveActionHint(2));
        }

        [Fact]
        public void NativeHudSlotOwner_SwitchesPriorityAndProjectsOneOwnerToBothWidgets()
        {
            Capture c;
            RightContextWidget right = MakeWidget(out c);
            SafeExitPanelWidget safeExit = MakeSafeExitWidget();

            right.ForceHoveredToolForTest(2);
            Assert.Equal(
                RightContextSlotOwner.ContextHint,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right, safeExit));
            Assert.Equal(RightContextSlotOwner.ContextHint, right.SlotOwnerForTest);
            Assert.Equal(RightContextSlotOwner.ContextHint, safeExit.SlotOwnerForTest);
            Assert.True(right.PaintsContextHintForTest);
            Assert.False(right.SlotHitBoxActiveForTest);
            Assert.False(safeExit.PaintsTransactionDecisionForTest);

            right.ForceDeliverState(true, "base_dorm", true, "1");
            Assert.Equal(
                RightContextSlotOwner.ActionableNotice,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right, safeExit));
            Assert.True(right.PaintsActionableNoticeForTest);
            Assert.False(right.PaintsContextHintForTest);
            Assert.True(right.SlotHitBoxActiveForTest);
            Assert.False(safeExit.SlotHitBoxActiveForTest);

            safeExit.Arm();
            Assert.Equal(
                RightContextSlotOwner.TransactionDecision,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right, safeExit));
            Assert.Equal(RightContextSlotOwner.TransactionDecision, right.SlotOwnerForTest);
            Assert.Equal(RightContextSlotOwner.TransactionDecision, safeExit.SlotOwnerForTest);
            Assert.False(right.PaintsActionableNoticeForTest);
            Assert.False(right.PaintsContextHintForTest);
            Assert.False(right.SlotHitBoxActiveForTest);
            Assert.True(safeExit.PaintsTransactionDecisionForTest);
            Assert.True(safeExit.SlotHitBoxActiveForTest);

            safeExit.OnUiDataChanged(
                Snapshot("sv:1"),
                new HashSet<string> { "sv" });
            safeExit.OnUiDataChanged(
                Snapshot("sv:2"),
                new HashSet<string> { "sv" });
            safeExit.InternalDownIndex = 0;
            Assert.Equal(
                SafeExitPanelWidget.ClickOutcome.Cancelled,
                safeExit.TryFireButtonClick(0));
            Assert.Equal(
                RightContextSlotOwner.ActionableNotice,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right, safeExit));

            right.ForceTaskDone(false);
            Assert.Equal(
                RightContextSlotOwner.ContextHint,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right, safeExit));

            right.ForceHoveredToolForTest(-1);
            Assert.Equal(
                RightContextSlotOwner.Hidden,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right, safeExit));
            Assert.False(right.StatusSlotVisibleForTest);
            Assert.False(right.PaintsContextHintForTest);
            Assert.False(right.PaintsActionableNoticeForTest);
            Assert.False(right.SlotHitBoxActiveForTest);
            Assert.False(safeExit.Visible);
            Assert.False(safeExit.SlotHitBoxActiveForTest);
        }

        [Fact]
        public void StageDecision_PreemptsSafeExitAndUsesOnlyItsPreciseActions()
        {
            Capture c;
            RightContextWidget right = MakeWidget(out c);
            SafeExitPanelWidget safeExit = MakeSafeExitWidget();
            var intents = new List<string>();
            right.IntentRequested += delegate(
                string intent, string runId, int revision)
            {
                intents.Add(intent + ":" + runId + ":" + revision);
            };
            right.SetReady();
            right.ApplyState(StageState(
                "victory", "dead", "none", true, 2));
            safeExit.Arm();

            Assert.True(right.RequestsStageDecision);
            Assert.Equal(
                RightContextSlotOwner.StageDecision,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                    right, safeExit));
            Assert.True(right.PaintsStageDecisionForTest);
            Assert.False(right.PaintsActionableNoticeForTest);
            Assert.False(safeExit.PaintsTransactionDecisionForTest);
            Assert.Equal(new[] { "复活", "回基地" },
                right.StageActionLabelsForTest);
            Assert.Equal("持有复活币 2", right.StageDecisionTextForTest);
            Assert.Equal("复活币", right.StageDecisionItemIconForTest);
            Assert.Equal("复活币", right.StageDecisionBalanceLabelForTest);
            Assert.Equal("2", right.StageDecisionBalanceMetaForTest);

            right.ClickStageActionForTest(0);
            Assert.Equal(
                new[] { "revive:run.right-context.1:7" },
                intents);
        }

        [Fact]
        public void Victory_HasPersistentReturnAndOnlyAddsAuthoritativeTaskRoute()
        {
            Capture c;
            RightContextWidget right = MakeWidget(out c);
            var intents = new List<string>();
            right.IntentRequested += delegate(
                string intent, string runId, int revision)
            {
                intents.Add(intent + ":" + runId + ":" + revision);
            };
            right.SetReady();

            right.ApplyState(StageState("victory", "alive", "none"));
            Assert.True(right.RequestsStageDecision);
            Assert.Equal(new[] { "回基地" },
                right.StageActionLabelsForTest);

            right.ClickStageActionForTest(0);
            Assert.True(right.RequestsStageDecision);
            Assert.Equal(new[] { "return_base:run.right-context.1:7" },
                intents);

            right.ForceDeliverState(
                true, "base_dorm", false, "2", returnNavigable: false);
            Assert.Equal(new[] { "回基地" },
                right.StageActionLabelsForTest);

            right.ForceDeliverState(
                true, "base_dorm", false, "2", returnNavigable: true);
            Assert.Equal(new[] { "前往交付", "回基地" },
                right.StageActionLabelsForTest);
            right.ClickStageActionForTest(0);
            Assert.Equal(
                new[]
                {
                    "return_base:run.right-context.1:7",
                    "return_deliverable:run.right-context.1:7"
                },
                intents);

            right.ApplyState(StageState(
                "failure", "alive", "none", revision:8));
            Assert.Equal(new[] { "回基地" },
                right.StageActionLabelsForTest);
        }

        [Fact]
        public void StageActionGesture_RequiresDownAndImmutableActionIdentity()
        {
            using (Form owner = new Form())
            {
                owner.StartPosition = FormStartPosition.Manual;
                owner.Bounds = new Rectangle(120, 80, 1024, 576);
                Panel anchor = new Panel();
                anchor.Bounds = new Rectangle(0, 0, 1024, 576);
                owner.Controls.Add(anchor);
                owner.CreateControl();
                anchor.CreateControl();

                Capture cap = new Capture();
                LauncherCommandRouter router = new LauncherCommandRouter(
                    socketServer: null,
                    onSendKey: k => { },
                    onToggleFullscreen: () => { },
                    onToggleLog: () => { },
                    onForceExit: () => { },
                    postToWeb: s => cap.Posts.Add(s));
                RightContextWidget right = new RightContextWidget(
                    anchor,
                    router,
                    MapHudDataCatalog.FromPayload(BuildPayload()),
                    MapDisplayPreference.Off);
                var intents = new List<string>();
                right.IntentRequested += delegate(
                    string intent, string runId, int revision)
                {
                    intents.Add(intent + ":" + runId + ":" + revision);
                };
                right.ForceGameReady(true);
                right.SetReady();
                right.ApplyState(StageState("victory", "alive", "none"));
                right.ForceDeliverState(
                    true, "base_dorm", false, "0", returnNavigable: true);
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                    right, null);

                Rectangle deliver = right.StageActionBoundsForTest(0);
                Point deliverCenter = new Point(
                    deliver.Left + deliver.Width / 2,
                    deliver.Top + deliver.Height / 2);
                MouseEventArgs deliverArgs = new MouseEventArgs(
                    MouseButtons.Left, 1,
                    deliverCenter.X, deliverCenter.Y, 0);

                right.OnMouseEvent(deliverArgs, MouseEventKind.Click);
                Assert.Empty(intents);

                right.OnMouseEvent(deliverArgs, MouseEventKind.Down);
                // Same list index is rebuilt from deliver to return without ApplyState.
                right.ForceDeliverState(
                    false, "", false, "0", returnNavigable: true);
                Rectangle current = right.StageActionBoundsForTest(0);
                Point currentCenter = new Point(
                    current.Left + current.Width / 2,
                    current.Top + current.Height / 2);
                MouseEventArgs currentArgs = new MouseEventArgs(
                    MouseButtons.Left, 1,
                    currentCenter.X, currentCenter.Y, 0);
                right.OnMouseEvent(currentArgs, MouseEventKind.Up);
                right.OnMouseEvent(currentArgs, MouseEventKind.Click);

                Assert.Empty(intents);

                right.OnMouseEvent(currentArgs, MouseEventKind.Down);
                right.OnMouseEvent(currentArgs, MouseEventKind.Up);
                right.OnMouseEvent(currentArgs, MouseEventKind.Click);
                Assert.Equal(
                    new[] { "return_base:run.right-context.1:7" },
                    intents);
            }
        }

        [Fact]
        public void StageActionGesture_RevisionRefreshCancelsPendingDown()
        {
            Capture cap;
            RightContextWidget right = MakeWidget(out cap);
            var intents = new List<string>();
            right.IntentRequested += delegate(
                string intent, string runId, int revision)
            {
                intents.Add(intent + ":" + runId + ":" + revision);
            };
            right.SetReady();
            right.ApplyState(StageState(
                "victory", "alive", "none", revision: 7));

            right.SetStageActionDownForTest(0);
            right.ApplyState(StageState(
                "victory", "alive", "none", revision: 8));
            right.ClickStageActionGestureForTest(0);

            Assert.Empty(intents);
        }

        [Fact]
        public void NoticeGesture_CommandAndPayloadCannotRetargetInSameSlot()
        {
            Capture cap;
            RightContextWidget right = MakeWidget(out cap);
            right.SetReady();
            right.ForceTaskDone(true);

            right.ForceDeliverState(
                true, "base_dorm", false, "0", returnNavigable: true);
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                right, null);
            right.SetNoticeDownForTest();
            Assert.True(right.ClickNoticeGestureForTest());

            right.ForceDeliverState(
                true, "base_dorm", false, "0", returnNavigable: true);
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                right, null);
            right.SetNoticeDownForTest();
            right.ForceDeliverState(
                true, "base_dorm", true, "0", returnNavigable: true);
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                right, null);
            Assert.False(right.ClickNoticeGestureForTest());

            right.ForceDeliverState(
                true, "base_dorm", true, "0", returnNavigable: true);
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                right, null);
            right.SetNoticeDownForTest();
            right.ForceDeliverState(
                true, "other_hotspot", true, "0", returnNavigable: true);
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                right, null);
            Assert.False(right.ClickNoticeGestureForTest());
        }

        [Fact]
        public void ZeroRewardPending_OffersReportInsteadOfPhantomRewardCount()
        {
            Capture cap;
            RightContextWidget right = MakeWidget(out cap);
            right.SetReady();
            right.ApplyState(StageState(
                "failure", "alive", "rewards_pending",
                canReturnBase: false, remainingRewards: 0));

            Assert.Equal("行动报告待查看", right.StageDecisionTextForTest);
            Assert.Equal(new[] { "查看报告" },
                right.StageActionLabelsForTest);
        }

        [Fact]
        public void ReviveBalance_MovesInventoryOutOfActionSemantics()
        {
            Capture c;
            RightContextWidget right = MakeWidget(out c);
            right.SetReady();
            right.ApplyState(StageState(
                "victory", "dead", "none", true, 20574));

            Assert.Equal(new[] { "复活", "回基地" },
                right.StageActionLabelsForTest);
            Assert.Equal("持有复活币 2.1万", right.StageDecisionTextForTest);
            Assert.Equal("复活币", right.StageDecisionItemIconForTest);
        }

        [Fact]
        public void ReviveActionLayout_ReallocatesWidthAndKeepsLegalCountsSingleLine()
        {
            using (Form owner = new Form())
            {
                owner.StartPosition = FormStartPosition.Manual;
                owner.Bounds = new Rectangle(120, 80, 1600, 900);
                Panel anchor = new Panel();
                anchor.Bounds = new Rectangle(0, 0, 1600, 900);
                owner.Controls.Add(anchor);
                owner.CreateControl();
                anchor.CreateControl();

                Capture cap = new Capture();
                LauncherCommandRouter router = new LauncherCommandRouter(
                    socketServer: null,
                    onSendKey: k => { },
                    onToggleFullscreen: () => { },
                    onToggleLog: () => { },
                    onForceExit: () => { },
                    postToWeb: s => cap.Posts.Add(s));
                using (LootIconCatalog itemIcons =
                    new LootIconCatalog(FindIconsDir()))
                using (RightContextWidget right = new RightContextWidget(
                    anchor,
                    router,
                    MapHudDataCatalog.FromPayload(BuildPayload()),
                    MapDisplayPreference.Off,
                    null,
                    itemIcons))
                {
                    right.ForceGameReady(true);
                    right.SetReady();
                    right.ApplyState(StageState(
                        "victory", "dead", "none", true, 20574));
                    NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                        right, null);

                    Rectangle revive = right.StageActionBoundsForTest(0);
                    Rectangle returnBase = right.StageActionBoundsForTest(1);
                    Assert.True(revive.Width > returnBase.Width);
                    Assert.True(revive.Right < returnBase.Left);
                    Assert.True(right.StageActionTextUsesSingleLineForTest);
                    Assert.True(right.StageActionLabelFitsForTest(0));
                    Assert.True(right.StageActionLabelFitsForTest(1));
                    Assert.True(right.StageDecisionBalanceIconResolvesForTest);
                    Assert.Equal("持有",
                        right.StageDecisionBalanceLabelForTest);
                    Assert.Equal("2.1万",
                        right.StageDecisionBalanceMetaForTest);
                    Assert.False(right.StageDecisionBalanceUsesCompactFontForTest);
                    Assert.True(right.StageDecisionBalanceFitsForTest);

                    right.ApplyState(StageState(
                        "victory", "dead", "none", true,
                        9007199254740991L));
                    Assert.Equal(
                        new[] { "复活", "回基地" },
                        right.StageActionLabelsForTest);
                    Assert.True(right.StageDecisionBalanceUsesCompactFontForTest);
                    Assert.True(right.StageActionLabelFitsForTest(0));
                    Assert.Equal(
                        "9007.2万亿",
                        right.StageDecisionBalanceMetaForTest);
                    Assert.True(right.StageDecisionBalanceFitsForTest);
                    Assert.Equal(revive, right.StageActionBoundsForTest(0));
                    Assert.Equal(returnBase, right.StageActionBoundsForTest(1));
                }

                using (RightContextWidget fallback = new RightContextWidget(
                    anchor,
                    router,
                    MapHudDataCatalog.FromPayload(BuildPayload()),
                    MapDisplayPreference.Off))
                {
                    fallback.ForceGameReady(true);
                    fallback.SetReady();
                    fallback.ApplyState(StageState(
                        "victory", "dead", "none", true, 20574));
                    NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                        fallback, null);

                    Assert.False(fallback.StageDecisionBalanceIconResolvesForTest);
                    Assert.Equal("复活币",
                        fallback.StageDecisionBalanceLabelForTest);
                    Assert.Equal("2.1万",
                        fallback.StageDecisionBalanceMetaForTest);
                    Assert.True(fallback.StageDecisionBalanceFitsForTest);
                }
            }
        }

        [Fact]
        public void RevivingAndBlockedRevive_StayInOneLineDecisionState()
        {
            Capture c;
            RightContextWidget right = MakeWidget(out c);
            right.SetReady();

            right.ApplyState(StageState(
                "victory", "dead", "none", false, 3,
                "resurrection_restricted"));
            Assert.Equal(new[] { "禁复活", "回基地" },
                right.StageActionLabelsForTest);
            Assert.Equal("你受了重伤", right.StageDecisionTextForTest);
            Assert.Null(right.StageDecisionItemIconForTest);
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                right, null);
            Assert.True(right.SlotHitBoxActiveForTest);

            right.ApplyState(StageState(
                "victory", "dead", "none", false, 0,
                "no_revive_coin"));
            Assert.Equal(new[] { "复活", "回基地" },
                right.StageActionLabelsForTest);
            Assert.Equal("持有复活币 0", right.StageDecisionTextForTest);
            Assert.Equal("复活币", right.StageDecisionItemIconForTest);
            Assert.Equal("复活币", right.StageDecisionBalanceLabelForTest);
            Assert.Equal("0", right.StageDecisionBalanceMetaForTest);
            Assert.False(right.StageActionEnabledForTest(0));

            right.ApplyState(StageState(
                "victory", "reviving", "none", false, 2));
            Assert.True(right.RequestsStageDecision);
            Assert.Empty(right.StageActionLabelsForTest);
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                right, null);
            Assert.False(right.SlotHitBoxActiveForTest);
        }

        [Fact]
        public void NativeHudAddWidget_RealBoundsSubscriptionReconcilesAndProjectsEveryOwner()
        {
            using (Form owner = new Form())
            {
                owner.ClientSize = new Size(1024, 576);
                Panel anchor = new Panel();
                anchor.Bounds = new Rectangle(0, 0, 1024, 576);
                owner.Controls.Add(anchor);
                owner.CreateControl();
                anchor.CreateControl();

                Capture cap = new Capture();
                LauncherCommandRouter router = new LauncherCommandRouter(
                    socketServer: null,
                    onSendKey: k => { },
                    onToggleFullscreen: () => { },
                    onToggleLog: () => { },
                    onForceExit: () => { },
                    postToWeb: s => cap.Posts.Add(s));
                RightContextWidget right = new RightContextWidget(
                    anchor,
                    router,
                    MapHudDataCatalog.FromPayload(BuildPayload()),
                    MapDisplayPreference.Compact);
                right.ForceGameReady(true);
                SafeExitPanelWidget safeExit = new SafeExitPanelWidget(anchor, router);
                safeExit.ForceGameReady(true);

                // 先产生 demand，再注册，证明 AddWidget 是“先订阅、再首次 reconcile”。
                right.OnLegacyUiData("task", new[] { "先发任务" });
                safeExit.Arm();

                using (NativeHudOverlay hud = new NativeHudOverlay(owner, anchor))
                {
                    hud.AddWidget(right);
                    Assert.Equal(
                        RightContextSlotOwner.ActionableNotice,
                        hud.RightContextSlotOwnerForTest);
                    Assert.True(right.PaintsActionableNoticeForTest);

                    hud.AddWidget(safeExit);
                    Assert.Equal(
                        RightContextSlotOwner.TransactionDecision,
                        hud.RightContextSlotOwnerForTest);
                    Assert.Equal(hud.RightContextSlotOwnerForTest, right.SlotOwnerForTest);
                    Assert.Equal(hud.RightContextSlotOwnerForTest, safeExit.SlotOwnerForTest);
                    Assert.False(right.PaintsActionableNoticeForTest);
                    Assert.False(right.PaintsContextHintForTest);
                    Assert.False(right.SlotHitBoxActiveForTest);
                    Assert.True(safeExit.SlotHitBoxActiveForTest);

                    // BoundsOrVisibilityChanged 的真实订阅把 transaction → notice 切回。
                    safeExit.OnUiDataChanged(
                        Snapshot("sv:1"),
                        new HashSet<string> { "sv" });
                    safeExit.OnUiDataChanged(
                        Snapshot("sv:2"),
                        new HashSet<string> { "sv" });
                    safeExit.InternalDownIndex = 0;
                    safeExit.TryFireButtonClick(0);
                    Assert.Equal(
                        RightContextSlotOwner.ActionableNotice,
                        hud.RightContextSlotOwnerForTest);
                    Assert.True(right.PaintsActionableNoticeForTest);
                    Assert.False(safeExit.Visible);

                    // notice 到期的真实 Bounds event 收敛到 hidden。
                    right.Tick(5001);
                    Assert.Equal(
                        RightContextSlotOwner.Hidden,
                        hud.RightContextSlotOwnerForTest);
                    Assert.False(right.StatusSlotVisibleForTest);

                    // 实际 mouse path 触发 hint demand，再由相同订阅投影为 contextHint。
                    FlashCoordinateMapper mapper =
                        new FlashCoordinateMapper(anchor, 1024f, 576f);
                    Rectangle tools = RightHudLayout.GetTopToolsRect(anchor, mapper);
                    Rectangle equipment =
                        RightHudLayout.ActionButtonRectFromTools(tools, 1f, 2);
                    right.OnMouseEvent(
                        new MouseEventArgs(
                            MouseButtons.None,
                            0,
                            equipment.Left + equipment.Width / 2,
                            equipment.Top + equipment.Height / 2,
                            0),
                        MouseEventKind.Move);
                    Assert.Equal(
                        RightContextSlotOwner.ContextHint,
                        hud.RightContextSlotOwnerForTest);
                    Assert.True(right.PaintsContextHintForTest);
                    Assert.False(right.SlotHitBoxActiveForTest);
                    Assert.False(safeExit.SlotHitBoxActiveForTest);

                    right.OnMouseEvent(
                        new MouseEventArgs(MouseButtons.None, 0, 0, 0, 0),
                        MouseEventKind.Leave);
                    Assert.Equal(
                        RightContextSlotOwner.Hidden,
                        hud.RightContextSlotOwnerForTest);
                    Assert.False(right.StatusSlotVisibleForTest);
                }
            }
        }

        [Fact]
        public void SlotProjection_PaintAndHitOwnershipAreMutuallyExclusive()
        {
            using (Form owner = new Form())
            {
                owner.ClientSize = new Size(1024, 576);
                Panel anchor = new Panel();
                anchor.Bounds = new Rectangle(0, 0, 1024, 576);
                owner.Controls.Add(anchor);
                owner.CreateControl();
                anchor.CreateControl();

                Capture cap = new Capture();
                LauncherCommandRouter router = new LauncherCommandRouter(
                    socketServer: null,
                    onSendKey: k => { },
                    onToggleFullscreen: () => { },
                    onToggleLog: () => { },
                    onForceExit: () => { },
                    postToWeb: s => cap.Posts.Add(s));
                RightContextWidget right = new RightContextWidget(
                    anchor,
                    router,
                    MapHudDataCatalog.FromPayload(BuildPayload()),
                    MapDisplayPreference.Off);
                right.ForceGameReady(true);
                right.ForceHoveredToolForTest(2);
                right.ForceDeliverState(true, "base_dorm", true, "1");
                SafeExitPanelWidget safeExit =
                    new SafeExitPanelWidget(anchor, router);
                safeExit.ForceGameReady(true);
                safeExit.Arm();

                FlashCoordinateMapper mapper =
                    new FlashCoordinateMapper(anchor, 1024f, 576f);
                Rectangle viewport =
                    RightHudLayout.GetViewportRect(anchor, mapper);
                float scale = RightHudLayout.ScaleForViewport(viewport);
                Rectangle context =
                    RightHudLayout.ContextPanelRectFromViewport(
                        viewport,
                        scale,
                        EffectiveMapDisplayMode.Hidden,
                        true);
                Rectangle slot =
                    RightHudLayout.StatusSlotRectFromContext(
                        context,
                        scale,
                        true);
                Point slotCenter =
                    new Point(slot.Left + slot.Width / 2, slot.Top + slot.Height / 2);

                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                    right,
                    safeExit);
                Assert.Equal(
                    RightContextSlotOwner.TransactionDecision,
                    right.SlotOwnerForTest);
                Assert.True(right.ScreenBounds.Contains(slotCenter)); // 仅为地图让位的共享布局占位
                Assert.Equal(slot, safeExit.ScreenBounds);
                Assert.False(right.TryHitTest(slotCenter));
                Assert.True(safeExit.TryHitTest(slotCenter));
                Assert.False(right.PaintsActionableNoticeForTest);
                Assert.False(right.PaintsContextHintForTest);
                Assert.True(SlotHasVisiblePixels(safeExit, slot));
                Assert.False(SlotHasVisiblePixels(right, slot));

                safeExit.OnUiDataChanged(
                    Snapshot("sv:1"),
                    new HashSet<string> { "sv" });
                safeExit.OnUiDataChanged(
                    Snapshot("sv:2"),
                    new HashSet<string> { "sv" });
                safeExit.InternalDownIndex = 0;
                safeExit.TryFireButtonClick(0);
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                    right,
                    safeExit);
                Assert.Equal(
                    RightContextSlotOwner.ActionableNotice,
                    right.SlotOwnerForTest);
                Assert.True(right.TryHitTest(slotCenter));
                Assert.False(safeExit.TryHitTest(slotCenter));
                Assert.True(right.PaintsActionableNoticeForTest);
                Assert.False(right.PaintsContextHintForTest);
                Assert.True(SlotHasVisiblePixels(right, slot));

                right.ForceTaskDone(false);
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                    right,
                    safeExit);
                Assert.Equal(
                    RightContextSlotOwner.ContextHint,
                    right.SlotOwnerForTest);
                Assert.False(right.TryHitTest(slotCenter));
                Assert.False(safeExit.TryHitTest(slotCenter));
                Assert.False(right.PaintsActionableNoticeForTest);
                Assert.True(right.PaintsContextHintForTest);
                Assert.True(SlotHasVisiblePixels(right, slot));

                right.ForceHoveredToolForTest(-1);
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(
                    right,
                    safeExit);
                Assert.Equal(
                    RightContextSlotOwner.Hidden,
                    right.SlotOwnerForTest);
                Assert.False(right.StatusSlotVisibleForTest);
                Rectangle tools =
                    RightHudLayout.TopToolsRectFromViewport(viewport, scale);
                Assert.Equal(tools.Bottom, right.ScreenBounds.Bottom);
                Assert.True(right.CompositeBounds.Bottom >= slot.Bottom); // 透明 hover/repaint reserve
                Assert.False(right.TryHitTest(slotCenter));
                Assert.False(safeExit.TryHitTest(slotCenter));
                Assert.False(SlotHasVisiblePixels(right, slot));
            }
        }

        [Fact]
        public void NativeSaveFeedback_PreservesBoundsRoutesAndManualExitAuthority()
        {
            using (var owner = new Form())
            using (var anchor = new Panel { Bounds = new Rectangle(0, 0, 1024, 576) })
            {
                owner.Controls.Add(anchor);
                _ = anchor.Handle;
                var router = new LauncherCommandRouter(null, k => { }, () => { },
                    () => { }, () => { }, s => { });
                var right = new RightContextWidget(anchor, router,
                    MapHudDataCatalog.FromPayload(BuildPayload()), MapDisplayPreference.Compact);
                var safeExit = new SafeExitPanelWidget(anchor, router);
                using (var hud = new NativeHudOverlay(owner, anchor))
                {
                    hud.AddWidget(right);
                    hud.AddWidget(safeExit);
                    _ = hud.Handle;
                    void Send(string raw)
                    {
                        hud.HandleUiData(new UiDataPacket(raw));
                        Application.DoEvents();
                    }
                    Send("s:1");
                    Rectangle visual = right.ScreenBounds, composite = right.CompositeBounds;
                    Assert.True(visual.Width > 0 && visual.Height > 0);
                    int boundsChanges = 0;
                    right.BoundsOrVisibilityChanged += delegate { boundsChanges++; };
                    Send("sv:1|sv:1|sv:2");
                    Assert.Contains("1 次", right.ResolveActionHint(5));
                    Send("sv:2"); // 最后值未变，仍须投递新的成功事件。
                    Assert.Contains("2 次", right.ResolveActionHint(5));
                    Assert.Equal(visual, right.ScreenBounds);
                    Assert.Equal(composite, right.CompositeBounds);
                    Assert.Equal(0, boundsChanges);
                    Assert.Equal("SAFEEXIT", right.ResolveActionRoute(5));
                    Assert.False(safeExit.IsArmed);
                    Assert.False(safeExit.TryAuthorizeExitConfirm());
                    Assert.True(right.WantsAnimationTick);
                    Send("sv:3");
                    Assert.Contains("保存未确认", right.ResolveActionHint(5));
                    Assert.False(right.WantsAnimationTick);
                    safeExit.Arm();
                    Send("sv:2");
                    Assert.False(safeExit.TryAuthorizeExitConfirm());
                    Send("sv:1|sv:2");
                    Assert.True(safeExit.TryAuthorizeExitConfirm());
                    Assert.False(safeExit.TryAuthorizeExitConfirm());
                    Send("s:0|s:1");
                    Assert.Equal("安全退出", right.ResolveActionHint(5));
                    Assert.False(right.WantsAnimationTick);
                }
            }
        }

        private static bool SlotHasVisiblePixels(
            INativeHudWidget widget,
            Rectangle slot)
        {
            Rectangle bounds = widget.ScreenBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0) return false;
            using (Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                graphics.Clear(Color.Transparent);
                widget.Paint(graphics, 1f, bounds.Location);
                Rectangle local = new Rectangle(
                    slot.X - bounds.X + 2,
                    slot.Y - bounds.Y + 2,
                    System.Math.Max(0, slot.Width - 4),
                    System.Math.Max(0, slot.Height - 4));
                Rectangle clipped = Rectangle.Intersect(
                    new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                    local);
                for (int y = clipped.Top; y < clipped.Bottom; y++)
                {
                    for (int x = clipped.Left; x < clipped.Right; x++)
                    {
                        if (bitmap.GetPixel(x, y).A != 0) return true;
                    }
                }
                return false;
            }
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
        public void UiData_FullChainUpdatesMapAndNotice()
        {
            Capture c;
            RightContextWidget w = MakeWidget(out c);
            w.OnUiDataChanged(
                Snapshot("s:1", "mm:1", "mh:base_dorm", "td:1", "tdh:base_dorm", "tdn:1", "tdr:1", "bgm:Final Sky", "pl:2"),
                new HashSet<string> { "s", "mm", "mh", "td", "tdh", "tdn", "tdr", "bgm", "pl" });

            Assert.True(w.MapSectionVisibleForTest);
            Assert.True(w.QuestNoticeVisibleForTest);
            Assert.True(w.IsReturnNavigable);
        }
    }
}
