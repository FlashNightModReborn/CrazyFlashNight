using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class WebOverlayFormPanelCloseTests
    {
        [Fact]
        public void FormatPanelEnvelopeLog_MinigameSessionRedactsWholePayload()
        {
            const string secret = "one-time-capability";
            string json = "{\"cmd\":\"minigame_session\",\"payload\":{\"game\":\"lockbox\",\"capability\":\""
                + secret + "\"}}";

            string line = WebOverlayForm.FormatPanelEnvelopeLog("minigame_session", json);

            Assert.Equal("[Panel] HandlePanelMessage: cmd=minigame_session payload=redacted", line);
            Assert.DoesNotContain(secret, line);
        }

        [Fact]
        public void FormatPanelEnvelopeLog_NonMinigameKeepsDiagnosticEnvelope()
        {
            const string json = "{\"cmd\":\"ready\"}";

            Assert.Equal("[Panel] HandlePanelMessage: " + json,
                WebOverlayForm.FormatPanelEnvelopeLog("ready", json));
        }

        [Fact]
        public void ResolvePanelCloseGameCommand_StageSelect_NotifiesFlashClose()
        {
            Assert.Equal("stageSelectPanelClose", WebOverlayForm.ResolvePanelCloseGameCommand("stage-select"));
        }

        [Fact]
        public void ResolvePanelCloseGameCommand_KnownPanels_KeepExistingCloseActions()
        {
            Assert.Equal("shopPanelClose", WebOverlayForm.ResolvePanelCloseGameCommand("kshop"));
            Assert.Equal("mapPanelClose", WebOverlayForm.ResolvePanelCloseGameCommand("map"));
            Assert.Equal("taskPanelClose", WebOverlayForm.ResolvePanelCloseGameCommand("tasks"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("help"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("intelligence"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("mercs"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("pets"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("team"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("arena"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("hairdresser"));
        }

        [Fact]
        public void HairdresserDomain_RoutesExplicitlyWhileCloseKeepsPriority()
        {
            Assert.Equal(
                WebOverlayForm.PanelDomainRoute.Hairdresser,
                WebOverlayForm.ResolvePanelDomainRoute("snapshot", "hairdresser"));
            Assert.Equal(
                WebOverlayForm.PanelDomainRoute.Close,
                WebOverlayForm.ResolvePanelDomainRoute("close", "hairdresser"));
        }

        [Fact]
        public void ItemUseDomain_RoutesExplicitlyWhileCloseKeepsPriority()
        {
            Assert.Equal(
                WebOverlayForm.PanelDomainRoute.ItemUse,
                WebOverlayForm.ResolvePanelDomainRoute("open", "item_use"));
            Assert.Equal(
                WebOverlayForm.PanelDomainRoute.Close,
                WebOverlayForm.ResolvePanelDomainRoute(
                    "close", "item_use"));
        }

        [Fact]
        public void WorkbenchClose_AllowsOnlyFrozenRewardInboxNavigationReason()
        {
            JObject exact = JObject.Parse(
                "{\"type\":\"panel\",\"panel\":\"workbench\","
                + "\"cmd\":\"close\",\"panelInstanceId\":\"workbench.1\","
                + "\"reason\":\"navigate_reward_inbox\"}");
            Assert.True(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                exact, "workbench", "workbench.1"));

            exact["reason"] = "navigate_item_use";
            Assert.False(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                exact, "workbench", "workbench.1"));
        }

        [Fact]
        public void RewardInboxHandoffRecordsAuthoritativeVisualRetireBeforeDetachRecovery()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string close = Slice(
                source,
                "case \"close\":",
                "case \"bulkQuery\":");
            int retire = close.IndexOf(
                "TryRetireCharacterBuildHostVisual(",
                StringComparison.Ordinal);
            int markClosed = close.IndexOf(
                "_itemUseTask.OnWorkbenchPanelClosed(",
                retire,
                StringComparison.Ordinal);
            int commitEffects = close.IndexOf(
                "CommitAcceptedPanelCloseEffects(",
                markClosed,
                StringComparison.Ordinal);

            Assert.True(retire >= 0);
            Assert.True(markClosed > retire);
            Assert.True(commitEffects > markClosed);
        }

        [Fact]
        public void RewardInboxTerminalClosePreservesWebSurfaceUntilExactReplacement()
        {
            string panel = File.ReadAllText(FindRepositoryFile(
                "launcher", "web", "modules", "loot", "loot-panel.js"));
            string finish = Slice(
                panel,
                "function finishVisualClose(reason)",
                "function onRebind(");
            Assert.Contains(
                "_init.sourceKind==='reward_inbox'",
                finish);
            Assert.Contains(
                "reason==='terminal'||reason==='suspended'",
                finish);
            Assert.Contains(
                "if (!preserveForRewardReturn) Panels.close();",
                finish);

            string host = File.ReadAllText(FindWebOverlaySource());
            string close = Slice(
                host,
                "private void HandleLootVisualClose(JObject parsed)",
                "private bool HasExactActivePanelOwnerBinding(");
            int pending = close.IndexOf(
                ".IsRewardInboxReplacementPendingExact(",
                StringComparison.Ordinal);
            int retry = close.IndexOf(
                ".RetryAuthorityVisualCloseExact(",
                StringComparison.Ordinal);
            Assert.True(pending >= 0 && retry > pending);
            Assert.Contains(
                "replacement=pending",
                close);
        }

        [Fact]
        public void LootRecovery_AddsSourceKindOnlyForRewardInbox()
        {
            var request = new LootPanelCoordinator.OpenRequest
            {
                ChestSessionId = "reward.chest.1",
                LootContainerId = "reward.container.1",
                ContainerEpoch = 2,
                OpenAttemptSeq = 3,
                DisplayName = "待领取物品",
                Capacity = 64,
                Columns = 8,
                SourceKind = LootPanelCoordinator.RewardInboxSource
            };
            var binding = new LootPanelCoordinator.Binding(
                request, "panel.loot.reward.1");

            JObject reward = JObject.Parse(
                WebOverlayForm.BuildLootPanelRecoveryCommand(
                    binding,
                    "web_open_failed",
                    "recovery.nonce.1"));
            Assert.Equal(
                "reward_inbox", reward.Value<string>("sourceKind"));

            request.SourceKind = LootPanelCoordinator.MapChestSource;
            binding = new LootPanelCoordinator.Binding(
                request, "panel.loot.map.1");
            JObject map = JObject.Parse(
                WebOverlayForm.BuildLootPanelRecoveryCommand(
                    binding,
                    "web_open_failed",
                    "recovery.nonce.2"));
            Assert.Null(map["sourceKind"]);
        }

        [Fact]
        public void ShouldReturnBaseOnPanelClose_OnlyArenaReturnBaseFlagTriggers()
        {
            Assert.True(WebOverlayForm.ShouldReturnBaseOnPanelClose(
                "arena",
                JObject.Parse("{\"returnBase\":true}")));

            Assert.False(WebOverlayForm.ShouldReturnBaseOnPanelClose(
                "arena",
                JObject.Parse("{}")));
            Assert.False(WebOverlayForm.ShouldReturnBaseOnPanelClose(
                "arena",
                JObject.Parse("{\"returnBase\":false}")));
            Assert.False(WebOverlayForm.ShouldReturnBaseOnPanelClose(
                "stage-select",
                JObject.Parse("{\"returnBase\":true}")));
            Assert.False(WebOverlayForm.ShouldReturnBaseOnPanelClose("arena", null));
        }

        [Fact]
        public void ForeignCloseCannotTearDownActivePanelOrDetachedCharacterBuildBarrier()
        {
            JObject foreign = JObject.Parse(
                "{\"type\":\"panel\",\"panel\":\"kshop\",\"cmd\":\"close\"}");
            JObject exactLoot = JObject.Parse(
                "{\"type\":\"panel\",\"panel\":\"loot\",\"cmd\":\"close\"}");
            JObject exactWorkbench = JObject.Parse(
                "{\"type\":\"panel\",\"panel\":\"workbench\",\"cmd\":\"close\"}");
            JObject exactMap = JObject.Parse(
                "{\"type\":\"panel\",\"panel\":\"map\",\"cmd\":\"close\"}");

            Assert.True(WebOverlayForm.ShouldRejectForeignPanelClose(
                foreign, "loot", false));
            Assert.False(WebOverlayForm.ShouldRejectForeignPanelClose(
                exactLoot, "loot", false));
            Assert.False(WebOverlayForm.ShouldRejectForeignPanelClose(
                foreign, "kshop", false));
            Assert.True(WebOverlayForm.ShouldRejectForeignPanelClose(
                foreign, "workbench", true));
            Assert.False(WebOverlayForm.ShouldRejectForeignPanelClose(
                exactWorkbench, "workbench", true));
            Assert.True(WebOverlayForm.ShouldRejectForeignPanelClose(
                foreign, null, true));
            Assert.True(WebOverlayForm.ShouldRejectForeignPanelClose(
                exactMap, "map", true));
            // A finalized/releasable old build binding is not a detached recovery barrier.
            Assert.False(WebOverlayForm.ShouldRejectForeignPanelClose(
                exactMap, "map", false));
            Assert.False(WebOverlayForm.ShouldRejectForeignPanelClose(
                foreign, null, false));
        }

        [Fact]
        public void ForeignCloseGuardRunsBeforePauseReleaseAndVisualClose()
        {
            string source = File.ReadAllText(
                FindWebOverlaySource());
            string handler = Slice(
                source,
                "private void HandlePanelMessage(string json)",
                "private void RespondPanelDomainError(");
            int guard = handler.IndexOf(
                "ShouldRejectForeignPanelClose(",
                StringComparison.Ordinal);
            Assert.True(guard >= 0);
            string[] acceptedCloseSideEffects =
            {
                "SealPanelRequestOwner(",
                "CommitAcceptedPanelCloseEffects(",
                "_panelHost.ClosePanel();",
                ".TryClosePanelExact(",
                ".TryRetirePanelVisualExact("
            };
            foreach (string marker in acceptedCloseSideEffects)
            {
                int sideEffect = handler.IndexOf(
                    marker,
                    StringComparison.Ordinal);
                Assert.True(
                    sideEffect > guard,
                    marker + " must remain after the foreign-close guard");
            }
        }

        [Fact]
        public void CraftingCloseDefersBehindMaterialReplaceBeforeOwnerRetirement()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string handler = Slice(
                source,
                "private void HandlePanelMessage(string json)",
                "private void RespondPanelDomainError(");
            int defer = handler.IndexOf(
                ".TryHandlePreCommitCraftingSourceClose(",
                StringComparison.Ordinal);
            int exactClose = handler.IndexOf(
                "_panelHost.TryClosePanelExact(",
                defer,
                StringComparison.Ordinal);
            int seal = handler.IndexOf(
                "SealPanelRequestOwner(",
                defer,
                StringComparison.Ordinal);

            Assert.True(defer >= 0);
            Assert.True(exactClose > defer);
            Assert.True(seal > exactClose);
        }

        [Fact]
        public void PanelCloseRestoresFlashFocusAfterOverlaySettlement()
        {
            string panelHost = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "PanelHostController.cs"));
            string close = Slice(
                panelHost,
                "private void DoClose()",
                "public void Dispose()");
            int webClose = close.IndexOf(
                "_web.TryPostToWeb(closePayload)",
                StringComparison.Ordinal);
            int suspend = close.IndexOf(
                "_web.SuspendAfterPanel(closingName)",
                StringComparison.Ordinal);
            int shield = close.IndexOf(
                "_shield.ExitTelemetryMode()",
                StringComparison.Ordinal);
            int hud = close.IndexOf(
                "_hud.Resume()",
                StringComparison.Ordinal);
            int escape = close.IndexOf(
                "_escSource.SetPanelEscapeEnabled(false)",
                StringComparison.Ordinal);
            int cursor = close.IndexOf(
                "_web.UpdateCursorFromScreenPoint",
                StringComparison.Ordinal);
            int closed = close.IndexOf(
                "PostPanelClosed(closingName, closingInstance)",
                StringComparison.Ordinal);
            int settledRestore = close.IndexOf(
                "_web.RestoreFlashInputFocusAfterPanelClose(closingName)",
                StringComparison.Ordinal);

            Assert.True(webClose >= 0);
            Assert.True(suspend > webClose);
            Assert.True(shield > suspend);
            Assert.True(hud > shield);
            Assert.True(escape > hud);
            Assert.True(cursor > escape);
            Assert.True(closed > cursor);
            Assert.True(settledRestore > closed);

            string overlay = File.ReadAllText(FindWebOverlaySource());
            string restore = Slice(
                overlay,
                "internal bool RestoreFlashInputFocusAfterPanelClose(",
                "private void ScheduleNativeHudIdleSuspend(");
            Assert.Contains("_disposed || _panelMode", restore);
            Assert.Contains("!_panelTakeForeground", restore);
            Assert.Contains("panel_close:settled:", restore);
            Assert.Contains("TryRestoreFlashInputFocusAfterPanelCloseCore(", restore);
        }

        [Fact]
        public void PanelCloseFocusRestore_SessionSnapshotAllowsIdleAndSettledRestore()
        {
            int calls = 0;
            var reasons = new List<string>();
            Func<string, bool> restore = delegate(string reason)
            {
                calls++;
                reasons.Add(reason);
                return true;
            };

            Assert.True(WebOverlayForm.TryInvokePanelCloseFocusRestore(
                disposed: false,
                panelMode: false,
                takeForeground: true,
                sessionForeground: true,
                restorer: restore,
                reason: "panel_close:idle:map"));
            int consumedGeneration = 0;
            Assert.True(WebOverlayForm.TryConsumePanelSettledFocusRestore(
                panelGeneration: 7,
                closeGeneration: 7,
                closeEligible: true,
                currentSessionForeground: true,
                consumedGeneration: ref consumedGeneration));
            Assert.True(WebOverlayForm.TryInvokePanelCloseFocusRestore(
                disposed: false,
                panelMode: false,
                takeForeground: true,
                sessionForeground: true,
                restorer: restore,
                reason: "panel_close:settled:map"));
            Assert.False(WebOverlayForm.TryConsumePanelSettledFocusRestore(
                7, 7, true, true, ref consumedGeneration));

            Assert.Equal(2, calls);
            Assert.Equal(new[]
            {
                "panel_close:idle:map",
                "panel_close:settled:map"
            }, reasons);
        }

        [Fact]
        public void PanelCloseFocusRestore_ExternalSnapshotBlocksBothAttempts()
        {
            int calls = 0;
            Func<string, bool> restore = delegate(string reason)
            {
                calls++;
                return true;
            };

            Assert.False(WebOverlayForm.TryInvokePanelCloseFocusRestore(
                false, false, true, false, restore,
                "panel_close:idle:map"));
            int consumedGeneration = 0;
            Assert.False(WebOverlayForm.TryConsumePanelSettledFocusRestore(
                7, 7, false, false, ref consumedGeneration));
            Assert.False(WebOverlayForm.TryConsumePanelSettledFocusRestore(
                7, 7, false, true, ref consumedGeneration));
            Assert.Equal(0, calls);
        }

        [Fact]
        public void PanelCloseFocusRestore_SessionThenExternalSkipsAndConsumesSettled()
        {
            int consumedGeneration = 0;
            Assert.False(WebOverlayForm.TryConsumePanelSettledFocusRestore(
                11, 11, true, false, ref consumedGeneration));
            Assert.Equal(11, consumedGeneration);
            Assert.False(WebOverlayForm.TryConsumePanelSettledFocusRestore(
                11, 11, true, true, ref consumedGeneration));
        }

        [Fact]
        public void PanelCloseFocusRestore_CoreRechecksLiveForegroundBeforeRestorer()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string core = Slice(
                source,
                "private bool TryRestoreFlashInputFocusAfterPanelCloseCore(",
                "private PanelCloseFocusTraceContext CapturePanelCloseFocusEligibility(");
            int liveQuery = core.IndexOf(
                "TryCapturePanelCloseForeground(",
                StringComparison.Ordinal);
            int externalGuard = core.IndexOf(
                "if (!currentSessionForeground)",
                StringComparison.Ordinal);
            int restore = core.IndexOf(
                "TryInvokePanelCloseFocusRestore(",
                StringComparison.Ordinal);

            Assert.True(liveQuery >= 0);
            Assert.True(externalGuard > liveQuery);
            Assert.True(restore > externalGuard);
            Assert.Contains("currentSessionForeground,", core);
            Assert.Contains("currentForeground.IsSessionOwned", core);
        }

        [Fact]
        public void PanelCloseCapturesForegroundBeforePanelModeAndHideMutation()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string close = Slice(
                source,
                "private void DoForceIdleSequence(string closingPanelName)",
                "private static void LogIdleStepDuration(");

            int capture = close.IndexOf(
                "CapturePanelCloseFocusEligibility(panelTag)",
                StringComparison.Ordinal);
            int clearMode = close.IndexOf(
                "_panelMode = false",
                StringComparison.Ordinal);
            int hideSequence = close.IndexOf(
                "DoFullIdleSuspend(closingPanelName, trace)",
                StringComparison.Ordinal);

            Assert.True(capture >= 0);
            Assert.True(clearMode > capture);
            Assert.True(hideSequence > clearMode);
        }

        [Fact]
        public void PanelCloseFocusTelemetry_PairsCloseHideAndRestoreStagesByGeneration()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string capture = Slice(
                source,
                "private PanelCloseFocusTraceContext CapturePanelCloseFocusEligibility(",
                "public void ForceIdleState(");
            Assert.Contains("new PanelCloseFocusTraceContext(", capture);
            Assert.Contains("Stopwatch.GetTimestamp()", capture);
            Assert.Contains("RegisterPanelCloseFocusTraceForSettled(trace)", capture);
            Assert.Contains("\"close_start\"", capture);

            string idle = Slice(
                source,
                "private void DoFullIdleSuspend(",
                "private void SuspendWebTimers()");
            Assert.Contains("PanelCloseFocusTraceContext trace", idle);
            int hideBefore = idle.IndexOf("\"hide_before\"", StringComparison.Ordinal);
            int hide = idle.IndexOf("ShowWindow(this.Handle, SW_HIDE)", StringComparison.Ordinal);
            int hideAfter = idle.IndexOf("\"hide_after\"", StringComparison.Ordinal);
            Assert.True(hideBefore >= 0);
            Assert.True(hide > hideBefore);
            Assert.True(hideAfter > hide);
            Assert.Contains("ClassifyPanelCloseHandoffTransition(", idle);

            string restore = Slice(
                source,
                "private bool TryRestoreFlashInputFocusAfterPanelCloseCore(",
                "private PanelCloseFocusTraceContext CapturePanelCloseFocusEligibility(");
            int restoreBefore = restore.IndexOf("\"restore_before\"", StringComparison.Ordinal);
            int invoke = restore.IndexOf("TryInvokePanelCloseFocusRestore(", StringComparison.Ordinal);
            int restoreResult = restore.IndexOf(
                "\"restore_result\"",
                invoke,
                StringComparison.Ordinal);
            Assert.True(restoreBefore >= 0);
            Assert.True(invoke > restoreBefore);
            Assert.True(restoreResult > invoke);

            string trace = Slice(
                source,
                "private void LogPanelCloseFocusTrace(",
                "private void LogPanelCloseFocusTraceFailure(");
            Assert.Contains("[PanelFocusHandoff] generation=", trace);
            Assert.Contains("trace.Generation", trace);
            Assert.Contains("trace.PanelTag", trace);
            Assert.Contains("ElapsedMs(trace.StartedAt)", trace);
            Assert.Contains("elapsed=", trace);
            Assert.Contains("foreground=", trace);
            Assert.Contains("kind=", trace);
            Assert.DoesNotContain("_panelCloseFocusTraceGeneration", source);
            Assert.DoesNotContain("_panelCloseFocusTracePanelTag", source);
            Assert.DoesNotContain("_panelCloseFocusTraceStartedAt", source);

            string close = Slice(
                source,
                "private void DoForceIdleSequence(string closingPanelName)",
                "private static void LogIdleStepDuration(");
            Assert.Contains("PanelCloseFocusTraceContext trace", close);
            Assert.Contains("DoFullIdleSuspend(closingPanelName, trace)", close);

            string settled = Slice(
                source,
                "internal bool RestoreFlashInputFocusAfterPanelClose(",
                "private bool TryRestoreFlashInputFocusAfterPanelCloseCore(");
            Assert.Contains("ResolvePanelCloseFocusTraceForStage(", settled);
            Assert.Contains("result=stale_stage_rejected", source);
        }

        [Fact]
        public void PanelCloseFocusTraceContext_RejectsInterleavedGenerationAndPanel()
        {
            var first = new WebOverlayForm.PanelCloseFocusTraceContext(
                7, "map", 101);
            var replacement = new WebOverlayForm.PanelCloseFocusTraceContext(
                8, "tasks", 202);
            var samePanelReplacement =
                new WebOverlayForm.PanelCloseFocusTraceContext(
                    8, "map", 303);

            Assert.True(first.IsValid);
            Assert.True(first.Matches(7, "map"));
            Assert.False(first.Matches(8, "map"));
            Assert.False(first.Matches(7, "tasks"));
            Assert.True(replacement.Matches(8, "tasks"));
            Assert.False(replacement.Matches(7, "map"));
            Assert.True(samePanelReplacement.Matches(8, "map"));
            Assert.False(samePanelReplacement.Matches(7, "map"));
            Assert.False(default(WebOverlayForm.PanelCloseFocusTraceContext)
                .IsValid);

            int matchCount;
            WebOverlayForm.PanelCloseFocusTraceContext unique =
                WebOverlayForm.SelectUniquePanelCloseFocusTrace(
                    new[] { first, replacement },
                    "map",
                    out matchCount);
            Assert.Equal(1, matchCount);
            Assert.True(unique.Matches(7, "map"));

            WebOverlayForm.PanelCloseFocusTraceContext ambiguous =
                WebOverlayForm.SelectUniquePanelCloseFocusTrace(
                    new[] { first, samePanelReplacement },
                    "map",
                    out matchCount);
            Assert.Equal(2, matchCount);
            Assert.False(ambiguous.IsValid);
        }

        [Fact]
        public void PanelHostClosePayloadRetiresOnlyTheExactWebOwner()
        {
            JObject payload = JObject.Parse(
                PanelHostController.BuildPanelClosePayload(
                    "crafting",
                    "panel.crafting.exact"));

            Assert.Equal("panel_cmd", payload.Value<string>("type"));
            Assert.Equal("close", payload.Value<string>("cmd"));
            Assert.Equal("crafting", payload.Value<string>("panel"));
            Assert.Equal(
                "panel.crafting.exact",
                payload.Value<string>("panelInstanceId"));
            Assert.Equal(4, payload.Count);
            Assert.Null(
                PanelHostController.BuildPanelClosePayload(
                    "crafting",
                    null));
        }

        [Fact]
        public void NpcShopUserAndSystemCloseContractsRemainStrictAndRoutable()
        {
            const string instance = "panel.npcshop.material";
            foreach (string reason in new[]
            {
                "button", "escape", "backdrop", "toggle"
            })
            {
                var outer = new JObject
                {
                    ["type"] = "panel",
                    ["panel"] = "npcshop",
                    ["cmd"] = "close",
                    ["panelInstanceId"] = instance,
                    ["reason"] = reason
                };
                Assert.True(MaterialShopNavigationCoordinator
                    .IsValidNpcShopOuterCloseEnvelope(outer));
                Assert.True(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                    outer, "npcshop", instance));
            }

            var systemFailure = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "npcshop",
                ["cmd"] = "close",
                ["panelInstanceId"] = instance
            };
            Assert.True(MaterialShopNavigationCoordinator
                .IsValidNpcShopSystemFailureCloseEnvelope(systemFailure));
            Assert.True(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                systemFailure, "npcshop", instance));
            systemFailure["extra"] = true;
            Assert.False(MaterialShopNavigationCoordinator
                .IsValidNpcShopSystemFailureCloseEnvelope(systemFailure));
        }

        [Fact]
        public void BlackMarketClose_IsExactAndCannotRetireReplacement()
        {
            const string activeInstance = "panel.blackmarket.replacement";
            var exact = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "blackmarket",
                ["cmd"] = "close",
                ["panelInstanceId"] = activeInstance
            };
            Assert.True(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "blackmarket", "blackmarket", activeInstance));
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "blackmarket", "blackmarket", "panel.blackmarket.old"));
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "blackmarket", "help", activeInstance));
            exact["extra"] = true;
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "blackmarket", "blackmarket", activeInstance));

            string panel = File.ReadAllText(FindRepositoryFile(
                "launcher", "web", "modules", "minigames", "blackmarket",
                "blackmarket-panel.js"));
            Assert.Contains("panelInstanceId: panelInstanceId", panel);
            Assert.DoesNotContain(
                "Bridge.send({ type: \"panel\", cmd: \"close\", panel: \"blackmarket\" });",
                panel);
            Assert.DoesNotContain("Panels.close()", Slice(
                panel, "function closePanel()", "function cleanup()"));
            Assert.Contains("_closeTimer = setTimeout", panel);
            Assert.Contains("Launcher 尚未确认关闭，可再次尝试。", panel);
            Assert.Contains("_openGeneration !== generation", panel);
            Assert.Contains("clearCloseTimer();", Slice(
                panel, "function cleanup()", "function notifyHost("));
        }

        [Fact]
        public void WarlordClose_IsExactAndCannotRetireReplacement()
        {
            const string activeInstance = "panel.warlord.replacement";
            var exact = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "warlord",
                ["cmd"] = "close",
                ["panelInstanceId"] = activeInstance
            };
            Assert.True(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "warlord", "warlord", activeInstance));
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "warlord", "warlord", "panel.warlord.old"));
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "warlord", "help", activeInstance));
            exact["extra"] = true;
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "warlord", "warlord", activeInstance));

            string panel = File.ReadAllText(FindRepositoryFile(
                "launcher", "web", "modules", "minigames", "warlord",
                "warlord-panel.js"));
            string close = Slice(
                panel, "function onRequestClose(reason)", "function onClose()");
            Assert.Contains("panelInstanceId: panelInstanceId", close);
            Assert.DoesNotContain("Panels.close()", close);
            Assert.Contains("closeTimer = setTimeout", close);
            Assert.Contains("Launcher 尚未确认关闭，可再次尝试。", close);
            Assert.Contains("generation !== localGeneration", close);
            Assert.Contains("clearCloseTimer();", Slice(
                panel, "function onClose()", "function notifyHost("));
        }

        [Fact]
        public void WarlordResume_UsesDedicatedHostCapabilityInsteadOfGenericPanelRequest()
        {
            string source = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Guardian", "WebOverlayForm.cs"));
            string wiring = Slice(
                source,
                "public void SetWarlordBattleTask(WarlordBattleTask task)",
                "public void SetPetTask(PetTask task)");

            Assert.Contains(
                "router.TryOpenWarlordResumePanel(initData);",
                wiring);
            Assert.DoesNotContain("RequestOpenPanel(", wiring);
            Assert.Contains(
                "event=warlord_resume_dispatch_failed reason=ui_invoke",
                wiring);
        }

        [Fact]
        public void TeamClose_IsExactAndCannotRetireReplacement()
        {
            const string activeInstance = "panel.team.replacement";
            var exact = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "team",
                ["cmd"] = "close",
                ["panelInstanceId"] = activeInstance
            };
            Assert.True(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "team", "team", activeInstance));
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "team", "team", "panel.team.old"));
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "team", "pets", activeInstance));
            exact["extra"] = true;
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                exact, "team", "team", activeInstance));

            string panel = File.ReadAllText(FindRepositoryFile(
                "launcher", "web", "modules", "team", "team-panel.js"));
            string close = Slice(
                panel, "function requestClose()", "function onClose()");
            Assert.Contains("panelInstanceId: _panelInstanceId", close);
            Assert.DoesNotContain("Panels.close()", close);
            Assert.Contains("_closeTimer = setTimeout", close);
            Assert.Contains("Launcher 尚未确认关闭，可再次尝试。", close);
            Assert.Contains("_panelInstanceId !== instance", close);
            Assert.Contains("clearCloseTimer();", Slice(
                panel, "function onClose()", "function closeAckTimeoutMs()"));

            string lifecycle = File.ReadAllText(FindRepositoryFile(
                "launcher", "web", "modules", "panels.js"));
            Assert.Contains("id === 'blackmarket' || id === 'team'", lifecycle);
        }

        [Fact]
        public void LegacyPetsClose_IsRejectedBeforeGenericCloseAndCannotRetireTeamReplacement()
        {
            var legacy = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "pets",
                ["cmd"] = "close",
                ["panelInstanceId"] = "panel.team.old"
            };
            Assert.True(WebOverlayForm.ShouldRejectLegacyPetsClose(legacy));
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                legacy, "team", "team", "panel.team.replacement"));

            legacy["panelInstanceId"] = "panel.team.replacement";
            Assert.True(WebOverlayForm.ShouldRejectLegacyPetsClose(legacy));
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                legacy, "team", "team", "panel.team.replacement"));

            string source = File.ReadAllText(FindWebOverlaySource());
            string handler = Slice(
                source,
                "private void HandlePanelMessage(string json)",
                "private void RespondPanelDomainError(");
            int rejection = handler.IndexOf(
                "ShouldRejectLegacyPetsClose(parsed)",
                StringComparison.Ordinal);
            int genericClose = handler.IndexOf(
                "_panelHost.ClosePanel();",
                StringComparison.Ordinal);
            Assert.True(rejection >= 0);
            Assert.True(genericClose > rejection);
        }

        [Fact]
        public void LegacyMercsClose_IsRejectedBeforeGenericCloseAndWebChildCannotCloseLocally()
        {
            var legacy = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "mercs",
                ["cmd"] = "close",
                ["panelInstanceId"] = "panel.team.old"
            };
            Assert.True(WebOverlayForm.ShouldRejectLegacyMercsClose(legacy));
            Assert.False(WebOverlayForm.IsValidExactPanelCloseEnvelope(
                legacy, "team", "team", "panel.team.replacement"));

            string hostSource = File.ReadAllText(FindWebOverlaySource());
            string handler = Slice(
                hostSource,
                "private void HandlePanelMessage(string json)",
                "private void RespondPanelDomainError(");
            int rejection = handler.IndexOf(
                "ShouldRejectLegacyMercsClose(parsed)",
                StringComparison.Ordinal);
            int genericClose = handler.IndexOf(
                "_panelHost.ClosePanel();",
                StringComparison.Ordinal);
            Assert.True(rejection >= 0);
            Assert.True(genericClose > rejection);

            string mercPanel = File.ReadAllText(FindRepositoryFile(
                "launcher", "web", "modules", "merc-panel.js"));
            string close = Slice(
                mercPanel, "function requestClose()", "function teardownView(");
            Assert.DoesNotContain("Panels.close()", close);
            Assert.DoesNotContain("Bridge.send", close);

            string tooltip = Slice(
                mercPanel,
                "function requestEquipTooltip(",
                "function ensureDressupManifest(");
            Assert.Contains("sendPanelMsg('equip_tooltip'", tooltip);
            Assert.DoesNotContain("Bridge.send", tooltip);
        }

        [Fact]
        public void WorkbenchMountFailureEmitterMatchesExactHostCloseContract()
        {
            string panelsSource = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "web", "modules", "panels.js"));
            string closeEnvelope = Slice(
                panelsSource,
                "function panelCloseMessage(",
                "function hostOwnsPanelMount(");
            Assert.Contains(
                "closeMessage.reason = reason || 'lazy_cancel';",
                closeEnvelope);
            Assert.Contains(
                "closeMessage.panelInstanceId = readPanelInstanceId(initData);",
                closeEnvelope);
            string mountFailure = Slice(
                panelsSource,
                "function sendMountFailureClose(",
                "function applyRegistrationDecorators(");
            Assert.Contains(
                "sendExactCloseNotification(",
                mountFailure);
            Assert.Contains(
                "id, initData, reason || 'mount_failed'",
                mountFailure);

            JObject emitted = JObject.Parse(
                "{\"type\":\"panel\",\"cmd\":\"close\","
                + "\"panel\":\"workbench\",\"reason\":\"mount_failed\","
                + "\"panelInstanceId\":\"panel.workbench.mount\"}");
            Assert.True(
                WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                    emitted,
                    "workbench",
                    "panel.workbench.mount"));
            emitted["extra"] = true;
            Assert.False(
                WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                    emitted,
                    "workbench",
                    "panel.workbench.mount"));
        }

        [Fact]
        public void DisconnectWithholdsCharacterRecoveryUntilHostVisualIdleProof()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string disconnect = Slice(
                source,
                "public void OnSocketDisconnected(int closedGeneration)",
                "public void OnSocketReconnected(int readyGeneration)");
            int drain = disconnect.IndexOf(
                "BeginSocketDetachBarrier(",
                StringComparison.Ordinal);
            int visual = disconnect.IndexOf(
                "BuildPanelForceClosePayload(",
                StringComparison.Ordinal);
            int panelHostClose = disconnect.IndexOf(
                "TryRetireCharacterBuildHostVisual(",
                StringComparison.Ordinal);
            Assert.True(drain >= 0);
            Assert.True(visual > drain);
            Assert.True(panelHostClose > drain);
            Assert.DoesNotContain(
                "_panelHost.PanelClosed +=",
                disconnect);
            Assert.Contains(
                "ContinueDetachRecoveryAfterVisualRetired(",
                disconnect);
            Assert.DoesNotContain(
                "_characterBuildTask.HandleDisconnect(",
                disconnect);
        }

        [Fact]
        public void ReconnectKeepsPauseWhileCharacterBuildBarrierIsUnresolved()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string reconnect = Slice(
                source,
                "public void OnSocketReconnected(int readyGeneration)",
                "#endregion");
            int recovery = reconnect.IndexOf(
                "_characterBuildTask.OnSocketReconnected(",
                StringComparison.Ordinal);
            int release = reconnect.IndexOf(
                "TryReleaseGenericWebPanelPause();",
                StringComparison.Ordinal);
            Assert.True(recovery >= 0);
            Assert.True(release > recovery);
            Assert.Contains(
                "!characterRecoveryPending",
                reconnect);
        }

        [Fact]
        public void WebNavigationRecoveryDispatchesOnlyAfterExactVisualRetireCompletion()
        {
            string source = File.ReadAllText(
                FindWebOverlaySource());
            string navigation = Slice(
                source,
                "_webView.CoreWebView2.NavigationStarting += delegate",
                "_webView.CoreWebView2.ContentLoading += delegate");
            Assert.Contains(
                "BeginCharacterBuildWebNavigationRecovery();",
                navigation);

            string helper = Slice(
                source,
                "private void BeginCharacterBuildWebNavigationRecovery()",
                "public void OnSocketDisconnected(int closedGeneration)");
            int recover = helper.IndexOf(
                "task.BeginWebViewDetachBarrier()",
                StringComparison.Ordinal);
            int close = helper.IndexOf(
                "TryRetireCharacterBuildHostVisual(",
                StringComparison.Ordinal);
            Assert.True(recover >= 0);
            Assert.True(close > recover);
            string retire = Slice(
                source,
                "private bool TryRetireCharacterBuildHostVisual(",
                "private void BeginCharacterBuildWebNavigationRecovery()");
            Assert.Contains(
                "VisualRetireOutcome",
                retire);
            Assert.Contains(
                ".ContinueDetachRecoveryAfterVisualRetired(",
                retire);
            Assert.Contains(
                "bool trackedVisual = _panelHost != null",
                helper);
            Assert.DoesNotContain(
                "ActivePanelName == \"workbench\"",
                helper);
            Assert.DoesNotContain(
                "task.BeginWebViewDetach(readyGeneration)",
                helper);
            Assert.DoesNotContain(
                "TryReleaseGenericWebPanelPause",
                helper);
        }

        [Fact]
        public void FinalizedBuildMustRetireBeforeSameNameStorageOrMapCanOpen()
        {
            var webPosts = new List<string>();
            var gameCommands = new List<string>();
            var flash = new List<string>();
            var router = new LauncherCommandRouter(
                null, null, null, null, null,
                delegate(string json) { webPosts.Add(json); });
            router.SetGameCommandSenderForTests(delegate(string payload)
            {
                gameCommands.Add(payload);
                return true;
            });
            var pumps = new Queue<Action>();
            using (var host =
                new PanelHostController(
                    delegate(Action pump) { pumps.Enqueue(pump); },
                    delegate(Action fire) { fire(); }))
            {
                router.SetPanelHost(host);

            using (var task = new CharacterBuildTask(delegate(string payload)
            {
                flash.Add(payload.TrimEnd('\0'));
                return true;
            }))
            {
                router.SetCharacterBuildTask(task);
                router.RequestOpenPanel(
                    "workbench",
                    "agent_control",
                    null, null, null, null, null,
                    "{\"profile\":\"battlebox\",\"view\":\"build\"}");
                while (pumps.Count > 0) pumps.Dequeue()();
                Assert.Equal("workbench", host.ActivePanelName);
                string buildInstance =
                    host.ActivePanelInstanceId;
                Assert.True(task.BindPanelInstance(buildInstance));

                Assert.True(task.TryBeginHostAccepted(
                    buildInstance,
                    null,
                    "navigation.stale.snapshot",
                    "snapshot",
                    null,
                    out int snapshotCallId,
                    out string snapshotError),
                    snapshotError);
                Assert.True(task.TryCompleteSuccess(
                    snapshotCallId,
                    buildInstance,
                    9,
                    "navigation.stale.snapshot",
                    "snapshot",
                    0,
                    3,
                    3,
                    5,
                    false,
                    true,
                    null,
                    null,
                    out string snapshotCompletionError),
                    snapshotCompletionError);

                Assert.True(task.TryBeginHostAccepted(
                    buildInstance,
                    9,
                    "navigation.stale.finalize",
                    "finalize",
                    null,
                    out int finalizeCallId,
                    out string finalizeError),
                    finalizeError);
                Assert.True(task.TryCompleteSuccess(
                    finalizeCallId,
                    buildInstance,
                    9,
                    "navigation.stale.finalize",
                    "finalize",
                    1,
                    3,
                    3,
                    5,
                    false,
                    false,
                    true,
                    true,
                    out string finalizeCompletionError),
                    finalizeCompletionError);
                Assert.True(task.CanRebind);

                int commandsBeforeTransition =
                    gameCommands.Count;

                // Same-name storage is a fresh Host instance. It must not replace A while A still
                // owns the captured Character pause authority.
                router.RequestOpenPanel(
                    "workbench",
                    "nativehud",
                    null, null, null, null, null,
                    "{\"profile\":\"battlebox\",\"view\":\"storage\"}");
                while (pumps.Count > 0) pumps.Dequeue()();
                Assert.True(task.IsBoundTo(buildInstance));
                Assert.True(task.RequiresDetachRecovery);
                // Host 视觉已被精确退休：面板不再持有任何活跃实例。
                Assert.Null(host.ActivePanelName);
                Assert.Null(host.ActivePanelInstanceId);

                int postsBeforeMap = webPosts.Count;
                router.RequestOpenPanel(
                    "map", "navigation_stale", null);
                while (pumps.Count > 0) pumps.Dequeue()();
                Assert.Equal(postsBeforeMap, webPosts.Count);
                Assert.Null(host.ActivePanelName);
                Assert.Null(host.ActivePanelInstanceId);
                Assert.Equal(
                    commandsBeforeTransition,
                    gameCommands.Count);

                JObject recovery =
                    JObject.Parse(flash[flash.Count - 1]);
                Assert.Equal(
                    "characterBuildRecoverDetach",
                    recovery.Value<string>("action"));
                task.HandleFlashResponse(
                    new JObject
                    {
                        ["task"] = "loadout_response",
                        ["callId"] =
                            recovery.Value<int>("callId"),
                        ["v"] = 1,
                        ["success"] = true,
                        ["command"] = "recoverDetach",
                        ["requestCallId"] =
                            recovery.Value<string>(
                                "requestCallId"),
                        ["panelInstanceId"] =
                            recovery.Value<string>(
                                "panelInstanceId"),
                        ["writeEpoch"] =
                            recovery.Value<int>(
                                "writeEpoch"),
                        ["active"] = false,
                        ["sessionGeneration"] = 9,
                        ["loadoutRevision"] = 3,
                        ["liveRevision"] = 3,
                        ["liveRefreshDirty"] = false,
                        ["drugRevision"] = 5,
                        ["recoveryState"] = "settled",
                        ["closed"] = true,
                        ["pauseReleased"] = true,
                        ["persistence"] =
                            new JObject
                            {
                                ["success"] = true,
                                ["changed"] = true
                            }
                    },
                    null);

                Assert.False(task.HasBoundPanel);
                Assert.False(task.RequiresDetachRecovery);
                Assert.Equal(
                    commandsBeforeTransition,
                    gameCommands.Count);

                router.RequestOpenPanel(
                    "map", "navigation_stale", null);
                while (pumps.Count > 0) pumps.Dequeue()();
                Assert.Equal("map",
                    host.ActivePanelName);
                Assert.NotEqual(buildInstance,
                    host.ActivePanelInstanceId);
            }
            }
        }

        [Theory]
        [InlineData("loadout_response")]
        [InlineData("inventory_response")]
        [InlineData("equipment_tuning_response")]
        [InlineData("loot_response")]
        [InlineData("panel_request")]
        [InlineData("agent_control")]
        [InlineData("agent_runtime_status")]
        [InlineData("cursor_control")]
        public void WebTaskIngressRejectsSocketOriginResponseRoutes(
            string taskName)
        {
            Assert.False(
                WebOverlayForm.IsWebTaskRouterIngressAllowed(
                    taskName));
            Assert.True(
                WebOverlayForm.IsWebTaskRouterIngressAllowed(
                    "font_pack"));
            Assert.True(
                WebOverlayForm.IsWebTaskRouterIngressAllowed(
                    "loot_request"));
            // 纸娃娃烘焙回传（doll-bake.js → DollBakeTask）属通用 Web task
            Assert.True(
                WebOverlayForm.IsWebTaskRouterIngressAllowed(
                    "doll_bake_result"));
        }

        [Fact]
        public void WebTaskResponseGuardRunsBeforeMessageRouter()
        {
            string source = File.ReadAllText(
                FindWebOverlaySource());
            string handler = Slice(
                source,
                "private void HandleWebTaskMessage(JObject parsed, string json)",
                "private void PostTaskResultToWeb(");
            int guard = handler.IndexOf(
                "IsWebTaskRouterIngressAllowed(taskName)",
                StringComparison.Ordinal);
            int route = handler.IndexOf(
                "_taskRouter.ProcessMessage(",
                StringComparison.Ordinal);
            Assert.True(guard >= 0);
            Assert.True(route > guard);
        }

        [Fact]
        public void CharacterBuildCloseUsesAcknowledgedHostOnlyRecoveryBeforeBindingConsumption()
        {
            string source = File.ReadAllText(
                FindWebOverlaySource());
            string close = Slice(
                source,
                "case \"close\":",
                "case \"bulkQuery\":");
            int recover = close.IndexOf(
                ".BeginNormalCloseBarrier(",
                StringComparison.Ordinal);
            int directConsume = close.IndexOf(
                ".TryClosePanelInstance(activeInstance)",
                StringComparison.Ordinal);
            Assert.True(recover >= 0);
            Assert.Equal(-1, directConsume);
            Assert.Contains(
                "deferInventoryOwnerCloseCommit",
                close);
            Assert.Contains(
                "CommitAcceptedPanelCloseEffects(",
                close);

            string closeEffects = Slice(
                source,
                "private void CommitAcceptedPanelCloseEffects(",
                "public bool ReleaseLootPanelPause()");
            Assert.Contains(
                "if (!pauseReleaseHandled)",
                closeEffects);

            string visualRetire = Slice(
                source,
                "private bool TryRetireCharacterBuildHostVisual(",
                "internal static bool ShouldRetireInventoryOwnerOnWebNavigation(");
            Assert.Contains(
                "if (retired != null) retired();",
                visualRetire);

            string recoverySource = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "CharacterBuildTask.DetachRecovery.cs"));
            string helper = Slice(
                recoverySource,
                "internal bool BeginNormalCloseBarrier(",
                "internal bool OnSocketReconnected(int readyGeneration)");
            Assert.Contains(
                "RequireDetachRecovery(",
                helper);
            Assert.Contains(
                "ContinueDetachRecoveryAfterVisualRetired(",
                close);
        }

        [Fact]
        public void CharacterBuildSkillsNavigationArmsBeforeCloseBarrierAndCompletesFromSettledCallback()
        {
            string overlay = File.ReadAllText(
                FindWebOverlaySource());
            string close = Slice(
                overlay,
                "case \"close\":",
                "case \"bulkQuery\":");
            int exactReason = close.IndexOf(
                ".TryParseCharacterBuildPreparationCloseReason(",
                StringComparison.Ordinal);
            int arm = close.IndexOf(
                ".TryArmCharacterBuildPreparationNavigation(",
                exactReason,
                StringComparison.Ordinal);
            int closeBarrier = close.IndexOf(
                ".BeginNormalCloseBarrier(",
                arm,
                StringComparison.Ordinal);
            int visualRetire = close.IndexOf(
                "TryRetireCharacterBuildHostVisual(",
                closeBarrier,
                StringComparison.Ordinal);
            Assert.True(exactReason >= 0);
            Assert.True(arm > exactReason);
            Assert.True(closeBarrier > arm);
            Assert.True(visualRetire > closeBarrier);
            Assert.Contains(
                ".CancelCharacterBuildPreparationNavigation(",
                close);
            Assert.Contains(
                "dismissReturnStack || navigatePreparation",
                close);
            Assert.Contains(
                "bool navigationArmed =",
                close);
            Assert.Contains(
                "RestoreCharacterBuildAfterPreparationArmFailure(",
                close);
            string preparationArmFailure = Slice(
                close,
                "if (!navigationArmed)",
                "if (tuningBound");
            Assert.DoesNotContain(
                "continuing ordinary close",
                preparationArmFailure);

            string program = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Program.cs"));
            string settled = Slice(
                program,
                "characterBuildTask.SetCoordinatorSettled(delegate",
                "MapTask mapTask");
            int complete = settled.IndexOf(
                ".TryCompleteCharacterBuildPreparationNavigation()",
                StringComparison.Ordinal);
            int deferredOpen = settled.IndexOf(
                "panelHost.FlushDeferredBarrierOpen();",
                StringComparison.Ordinal);
            Assert.True(complete >= 0);
            Assert.True(deferredOpen > complete);
            Assert.Contains(
                "if (!preparationNavigationConsumed)",
                settled);

            string router = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "LauncherCommandRouter.cs"));
            string completion = Slice(
                router,
                "internal bool TryCompleteCharacterBuildPreparationNavigation()",
                "internal bool TryCompleteCharacterBuildSkillsNavigation()");
            int bindingFence = completion.IndexOf(
                "task.HasBoundPanel",
                StringComparison.Ordinal);
            int visualFence = completion.IndexOf(
                "visual_not_idle",
                StringComparison.Ordinal);
            int discardDeferred = completion.IndexOf(
                ".DiscardDeferredBarrierOpen()",
                StringComparison.Ordinal);
            int preflight = completion.IndexOf(
                "TrySendSkillPanelOpenCommandIfCurrent(",
                StringComparison.Ordinal);
            Assert.True(bindingFence >= 0);
            Assert.True(visualFence > bindingFence);
            Assert.True(discardDeferred > visualFence);
            Assert.True(preflight > discardDeferred);
            Assert.DoesNotContain(
                "OpenPanel(\"skills\"",
                completion);
            Assert.Contains(
                "ClearCharacterBuildPreparationNavigationLocked();",
                completion);
            Assert.Contains(
                "TryBeginSkillOpenWait(",
                completion);

            string navigation = Slice(
                overlay,
                "_webView.CoreWebView2.NavigationStarting += delegate",
                "_webView.CoreWebView2.ContentLoading += delegate");
            Assert.Contains(
                ".CancelAllPanelNavigationIntents(",
                navigation);
        }

        [Theory]
        [InlineData("navigate_skills")]
        [InlineData("navigate_materials")]
        [InlineData("navigate_intelligence")]
        public void CharacterBuildPreparationCloseReasonsAreExactAndClosed(
            string reason)
        {
            JObject envelope =
                JObject.Parse(
                    "{\"type\":\"panel\",\"panel\":\"workbench\","
                    + "\"cmd\":\"close\",\"panelInstanceId\":\"workbench.exact\","
                    + "\"reason\":\"placeholder\"}");
            envelope["reason"] = reason;
            Assert.True(
                WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                    envelope,
                    "workbench",
                    "workbench.exact"));

            envelope["reason"] = reason + "_other";
            Assert.False(
                WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                    envelope,
                    "workbench",
                    "workbench.exact"));
            envelope["reason"] = reason;
            envelope["target"] = "skills";
            Assert.False(
                WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                    envelope,
                    "workbench",
                    "workbench.exact"));
        }

        [Theory]
        [InlineData("crafting")]
        [InlineData("intelligence")]
        public void PreparationChildReturnCloseRequiresExactFiveKeyInstanceAndReason(
            string panel)
        {
            JObject envelope =
                JObject.Parse(
                    "{\"type\":\"panel\",\"panel\":\"placeholder\","
                    + "\"cmd\":\"close\",\"panelInstanceId\":\"child.exact\","
                    + "\"reason\":\"navigate_character_build\"}");
            envelope["panel"] =
                panel;
            Assert.True(
                WebOverlayForm
                    .IsValidPreparationChildReturnCloseEnvelope(
                        envelope,
                        panel,
                        "child.exact"));

            Assert.False(
                WebOverlayForm
                    .IsValidPreparationChildReturnCloseEnvelope(
                        envelope,
                        panel,
                        "child.replacement"));
            Assert.False(
                WebOverlayForm
                    .IsValidPreparationChildReturnCloseEnvelope(
                        envelope,
                        panel == "crafting"
                            ? "intelligence"
                            : "crafting",
                        "child.exact"));
            envelope["reason"] =
                "navigate_character_build_other";
            Assert.False(
                WebOverlayForm
                    .IsValidPreparationChildReturnCloseEnvelope(
                        envelope,
                        panel,
                        "child.exact"));
            envelope["reason"] =
                "navigate_character_build";
            envelope.Remove(
                "panelInstanceId");
            Assert.False(
                WebOverlayForm
                    .IsValidPreparationChildReturnCloseEnvelope(
                        envelope,
                        panel,
                        "child.exact"));
            envelope["panelInstanceId"] =
                "child.exact";
            envelope["extra"] =
                true;
            Assert.False(
                WebOverlayForm
                    .IsValidPreparationChildReturnCloseEnvelope(
                        envelope,
                        panel,
                        "child.exact"));
        }

        [Theory]
        [InlineData("crafting")]
        [InlineData("intelligence")]
        public void PreparationChildOrdinaryCloseCannotMasqueradeAsReturn(
            string panel)
        {
            JObject ordinary =
                JObject.Parse(
                    "{\"type\":\"panel\",\"panel\":\"placeholder\","
                    + "\"cmd\":\"close\"}");
            ordinary["panel"] =
                panel;
            Assert.False(
                WebOverlayForm
                    .IsValidPreparationChildReturnCloseEnvelope(
                        ordinary,
                        panel,
                        "child.exact"));
        }

        [Theory]
        [InlineData(false, "skills")]
        [InlineData(true, "preparation-menu")]
        public void PreparationArmFailureRecoveryReopensOnlyTheSameBuildInstance(
            bool preparationNavigationV1,
            string expectedReturnFocusAction)
        {
            string payload =
                WebOverlayForm
                    .BuildCharacterBuildPreparationRecoveryPayload(
                        "panel.workbench.exact",
                        preparationNavigationV1);
            JObject parsed =
                JObject.Parse(payload);
            Assert.Equal(
                "open",
                parsed.Value<string>("cmd"));
            Assert.Equal(
                "workbench",
                parsed.Value<string>("panel"));
            Assert.Equal(
                "panel.workbench.exact",
                parsed.Value<string>("panelInstanceId"));
            JObject initData =
                (JObject)parsed["initData"];
            Assert.Equal(
                "panel.workbench.exact",
                initData.Value<string>("panelInstanceId"));
            Assert.Equal(
                "battlebox",
                initData.Value<string>("profile"));
            Assert.Equal(
                "build",
                initData.Value<string>("view"));
            Assert.Equal(
                expectedReturnFocusAction,
                initData.Value<string>("returnFocusAction"));
            Assert.Equal(
                preparationNavigationV1
                    ? true
                    : (bool?)null,
                initData.Value<bool?>(
                    "preparationNavigationV1"));
            Assert.Null(
                WebOverlayForm
                    .BuildCharacterBuildPreparationRecoveryPayload(
                        null));
        }

        [Fact]
        public void DisabledPreparationTargetsReturnBeforeAnyCloseOrOpenMutation()
        {
            string overlay =
                File.ReadAllText(
                    FindWebOverlaySource());
            string close =
                Slice(
                    overlay,
                    "case \"close\":",
                    "case \"bulkQuery\":");
            string disabledGate =
                Slice(
                    close,
                    "if (navigatePreparation",
                    "bool tuningBound =");
            Assert.Contains(
                ".IsCharacterBuildPreparationTargetEnabled(",
                disabledGate);
            Assert.Contains(
                "reason=target_disabled",
                disabledGate);
            Assert.Contains(
                "return;",
                disabledGate);
            Assert.DoesNotContain(
                "BeginNormalCloseBarrier",
                disabledGate);
            Assert.DoesNotContain(
                "TryClosePanel",
                disabledGate);
            Assert.DoesNotContain(
                "BuildCharacterBuildPreparationRecoveryPayload",
                disabledGate);
        }

        [Fact]
        public void SkillsCharacterBuildReturnUsesExactCapabilityAndTwoSettledGates()
        {
            string overlay = File.ReadAllText(
                FindWebOverlaySource());
            string close = Slice(
                overlay,
                "case \"close\":",
                "case \"bulkQuery\":");
            int reason = close.IndexOf(
                "\"navigate_character_build\"",
                StringComparison.Ordinal);
            int arm = close.IndexOf(
                ".TryArmSkillsCharacterBuildNavigation(",
                reason,
                StringComparison.Ordinal);
            int coordinatorClose = close.IndexOf(
                ".HandleAuthoritativePanelClosed(",
                arm,
                StringComparison.Ordinal);
            int exactVisualRetire = close.IndexOf(
                ".TryRetirePanelVisualExact(",
                coordinatorClose,
                StringComparison.Ordinal);
            int complete = close.IndexOf(
                ".TryCompleteSkillsCharacterBuildNavigation()",
                exactVisualRetire,
                StringComparison.Ordinal);
            Assert.True(reason >= 0);
            Assert.True(arm > reason);
            Assert.True(coordinatorClose > arm);
            Assert.True(exactVisualRetire > coordinatorClose);
            Assert.True(complete > exactVisualRetire);
            Assert.Contains(
                ".CancelSkillsCharacterBuildNavigation(",
                close);
            Assert.Contains(
                "VisualAlreadyAbsent",
                close);

            string router = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "LauncherCommandRouter.cs"));
            string completion = Slice(
                router,
                "internal bool TryCompleteSkillsCharacterBuildNavigation()",
                "private void OnSkillsCharacterBuildNavigationTimeout(");
            Assert.Contains(
                "_skillTask.IsClosedAndSettled",
                completion);
            Assert.Contains(
                "_panelHost.IsIdleForTrackedOpen",
                completion);
            Assert.Contains(
                "\"skills_return\"",
                completion);
            Assert.Contains(
                "TrySendNativeEquipmentBuildPreflightIfCurrent(",
                completion);
            Assert.DoesNotContain(
                "OpenPanel(\"workbench\"",
                completion);

            string program = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Program.cs"));
            string skillSettled = Slice(
                program,
                "skillTask.SetCoordinatorSettled(delegate",
                "equipmentTuningTask.SetCoordinatorSettled(delegate");
            Assert.Contains(
                ".TryCompleteSkillsCharacterBuildNavigation()",
                skillSettled);
            Assert.Contains(
                "PendingSkillsCharacterBuildNavigationInstance",
                skillSettled);
        }

        [Fact]
        public void PreparationChildReturnRetiresExactVisualBeforeNativeBuildPreflight()
        {
            string overlay =
                File.ReadAllText(
                    FindWebOverlaySource());
            string close =
                Slice(
                    overlay,
                    "case \"close\":",
                    "case \"bulkQuery\":");
            int exactEnvelope =
                close.IndexOf(
                    "IsValidPreparationChildReturnCloseEnvelope(",
                    StringComparison.Ordinal);
            int arm =
                close.IndexOf(
                    ".TryArmPreparationChildCharacterBuildNavigation(",
                    exactEnvelope,
                    StringComparison.Ordinal);
            int retire =
                close.IndexOf(
                    ".TryRetirePanelVisualExact(",
                    close.IndexOf(
                        "else if (navigatePreparationChild)",
                        arm,
                        StringComparison.Ordinal),
                    StringComparison.Ordinal);
            int complete =
                close.IndexOf(
                    ".TryCompletePreparationChildCharacterBuildNavigation(",
                    retire,
                    StringComparison.Ordinal);
            Assert.True(
                exactEnvelope >= 0);
            Assert.True(
                arm > exactEnvelope);
            Assert.True(
                retire > arm);
            Assert.True(
                complete > retire);
            Assert.Contains(
                "exactPreparationChildPanel",
                close);
            Assert.Contains(
                "exactPreparationChildInstance",
                close);

            string router =
                File.ReadAllText(
                    FindRepositoryFile(
                        "launcher",
                        "src",
                        "Guardian",
                        "LauncherCommandRouter.cs"));
            string completion =
                Slice(
                    router,
                    "internal bool TryCompletePreparationChildCharacterBuildNavigation(",
                    "OnPreparationChildCharacterBuildNavigationTimeout(");
            Assert.Contains(
                "TryBeginNativeEquipmentBuildOpenWait(",
                completion);
            Assert.Contains(
                "TrySendNativeEquipmentBuildPreflightIfCurrent(",
                completion);
            Assert.DoesNotContain(
                "OpenPanel(",
                completion);
        }

        [Fact]
        public void ForeignVisibleWorkbenchRetiresBeforeOldCharacterAuthorityRecovery()
        {
            string source = File.ReadAllText(
                FindWebOverlaySource());
            string close = Slice(
                source,
                "case \"close\":",
                "case \"bulkQuery\":");
            int anyBinding = close.IndexOf(
                "bool anyLoadoutBinding = _characterBuildTask != null",
                StringComparison.Ordinal);
            int captureVisible = close.IndexOf(
                "exactWorkbenchInstance = activeInstance;",
                StringComparison.Ordinal);
            int armOldAuthority = close.IndexOf(
                ".BeginNormalCloseBarrier(",
                StringComparison.Ordinal);
            int closeVisible = close.IndexOf(
                "TryRetireCharacterBuildHostVisual(",
                StringComparison.Ordinal);
            Assert.True(anyBinding >= 0);
            Assert.True(captureVisible > anyBinding);
            Assert.True(armOldAuthority > captureVisible);
            Assert.True(closeVisible > armOldAuthority);
            Assert.Contains(
                "string closeInstance =",
                close);
            Assert.Contains(
                "exactWorkbenchInstance",
                close);
        }

        [Fact]
        public void CharacterRecoveryUsesHostIdleOutcomeInsteadOfBestEffortCloseEvent()
        {
            string source = File.ReadAllText(
                FindWebOverlaySource());
            string retire = Slice(
                source,
                "private bool TryRetireCharacterBuildHostVisual(",
                "private void BeginCharacterBuildWebNavigationRecovery()");
            int hostPrimitive = retire.IndexOf(
                "_panelHost.TryRetirePanelVisualExact(",
                StringComparison.Ordinal);
            int idleOutcome = retire.IndexOf(
                ".VisualAlreadyAbsent",
                hostPrimitive,
                StringComparison.Ordinal);
            int continueRecovery = retire.IndexOf(
                ".ContinueDetachRecoveryAfterVisualRetired(",
                idleOutcome,
                StringComparison.Ordinal);
            int unavailable = retire.IndexOf(
                "Host visual retire unavailable",
                continueRecovery,
                StringComparison.Ordinal);
            Assert.True(hostPrimitive >= 0);
            Assert.True(idleOutcome > hostPrimitive);
            Assert.True(continueRecovery > idleOutcome);
            Assert.True(unavailable > continueRecovery);
            Assert.DoesNotContain(
                "_panelHost.PanelClosed +=",
                retire);

            string router = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "LauncherCommandRouter.cs"));
            string handoff = Slice(
                router,
                "private bool BeginCharacterBuildSwitchHandoff(",
                "private void SendKey(Keys k)");
            Assert.Contains(
                "_panelHost.TryRetirePanelVisualExact(",
                handoff);
            Assert.Contains(
                "VisualRetireOutcome",
                handoff);
            Assert.DoesNotContain(
                "_panelHost.TryClosePanelExact(",
                handoff);
        }

        private static string Slice(
            string source,
            string startMarker,
            string endMarker)
        {
            int start = source.IndexOf(
                startMarker, StringComparison.Ordinal);
            Assert.True(start >= 0);
            int end = source.IndexOf(
                endMarker, start, StringComparison.Ordinal);
            Assert.True(end > start);
            return source.Substring(start, end - start);
        }

        private static string FindWebOverlaySource()
        {
            return FindRepositoryFile(
                "launcher", "src", "Guardian",
                "WebOverlayForm.cs");
        }

        private static string FindRepositoryFile(
            params string[] relativeParts)
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string repositoryPath = current.FullName;
                foreach (string part in relativeParts)
                    repositoryPath = Path.Combine(
                        repositoryPath, part);
                if (File.Exists(repositoryPath)) return repositoryPath;
                current = current.Parent;
            }
            throw new FileNotFoundException(
                "Unable to locate repository file: "
                + string.Join("/", relativeParts));
        }
    }
}
