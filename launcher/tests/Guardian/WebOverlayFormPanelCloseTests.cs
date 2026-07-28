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
            int release = handler.IndexOf(
                "TryReleaseGenericWebPanelPause();",
                StringComparison.Ordinal);
            int visualClose = handler.IndexOf(
                "_panelHost.ClosePanel();",
                StringComparison.Ordinal);
            Assert.True(guard >= 0);
            Assert.True(release > guard);
            Assert.True(visualClose > guard);
        }

        [Fact]
        public void WorkbenchMountFailureEmitterMatchesExactHostCloseContract()
        {
            string panelsSource = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "web", "modules", "panels.js"));
            Assert.Contains(
                "reason:'mount_failed', panelInstanceId:readPanelInstanceId(initData)",
                panelsSource);

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
            int clearFallback = helper.IndexOf(
                "_commandRouter.ClearFallbackPanelInstance();",
                StringComparison.Ordinal);
            Assert.True(recover >= 0);
            Assert.True(close > recover);
            Assert.True(clearFallback > recover);
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
            Assert.Contains(
                "_commandRouter.ActiveFallbackPanelName",
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
                delegate(string json) { webPosts.Add(json); },
                null, null);
            router.SetFallbackVisualRetire(
                delegate { return true; });
            router.SetGameCommandSenderForTests(delegate(string payload)
            {
                gameCommands.Add(payload);
                return true;
            });

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
                string buildInstance =
                    router.ActiveFallbackPanelInstanceId;
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
                Assert.Null(
                    router.ActiveFallbackPanelInstanceId);
                Assert.Null(
                    router.ActiveFallbackPanelName);
                Assert.True(task.IsBoundTo(buildInstance));
                Assert.True(task.RequiresDetachRecovery);
                Assert.Equal(2, webPosts.Count);
                JObject visualRetire =
                    JObject.Parse(webPosts[1]);
                Assert.Equal("close",
                    visualRetire.Value<string>("cmd"));
                Assert.Equal(buildInstance,
                    visualRetire.Value<string>(
                        "panelInstanceId"));

                int postsBeforeMap = webPosts.Count;
                router.RequestOpenPanel(
                    "map", "navigation_stale", null);
                Assert.Equal(postsBeforeMap, webPosts.Count);
                Assert.Null(router.ActiveFallbackPanelName);
                Assert.Null(router.ActiveFallbackPanelInstanceId);
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
                Assert.Equal("map",
                    router.ActiveFallbackPanelName);
                Assert.NotEqual(buildInstance,
                    router.ActiveFallbackPanelInstanceId);
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
                "if (!characterBuildPauseReleaseHandled)",
                close);

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
                "\"navigate_skills\"",
                StringComparison.Ordinal);
            int arm = close.IndexOf(
                ".TryArmCharacterBuildSkillsNavigation(",
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
                ".CancelCharacterBuildSkillsNavigation(",
                close);
            Assert.Contains(
                "dismissReturnStack || navigateSkills",
                close);
            Assert.Contains(
                "bool navigationArmed =",
                close);
            Assert.Contains(
                "navigateSkills = false;",
                close);
            Assert.Contains(
                "continuing ordinary close",
                close);

            string program = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Program.cs"));
            string settled = Slice(
                program,
                "characterBuildTask.SetCoordinatorSettled(delegate",
                "MapTask mapTask");
            int complete = settled.IndexOf(
                ".TryCompleteCharacterBuildSkillsNavigation()",
                StringComparison.Ordinal);
            int deferredOpen = settled.IndexOf(
                "panelHost.FlushDeferredBarrierOpen();",
                StringComparison.Ordinal);
            Assert.True(complete >= 0);
            Assert.True(deferredOpen > complete);
            Assert.Contains(
                "if (!skillsNavigationConsumed)",
                settled);

            string router = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "LauncherCommandRouter.cs"));
            string completion = Slice(
                router,
                "internal bool TryCompleteCharacterBuildSkillsNavigation()",
                "private void ClearCharacterBuildSkillsNavigationLocked()");
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
                "TrySendSkillPanelOpenCommand(openRequestId)",
                StringComparison.Ordinal);
            Assert.True(bindingFence >= 0);
            Assert.True(visualFence > bindingFence);
            Assert.True(discardDeferred > visualFence);
            Assert.True(preflight > discardDeferred);
            Assert.DoesNotContain(
                "OpenPanel(\"skills\"",
                completion);

            string navigation = Slice(
                overlay,
                "_webView.CoreWebView2.NavigationStarting += delegate",
                "_webView.CoreWebView2.ContentLoading += delegate");
            Assert.Contains(
                ".CancelPendingSkillOpenIntent(",
                navigation);
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
