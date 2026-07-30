using System;
using System.IO;
using CF7Launcher.Guardian;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class ProgramPanelTaskShutdownTests
    {
        [Fact]
        public void TransactionPanelTrackers_AreDisposedOnEveryShutdownPath()
        {
            string source = File.ReadAllText(FindProgramSource());
            string early = Slice(
                source,
                "form.OnShutdownEarly = delegate",
                "// 写端口文件");
            string busOnly = Slice(
                source,
                "// === bus-only 模式：仅运行通信总线，不启动 Flash Player ===",
                "// === 正常模式：启动 Flash Player 并嵌入 ===");
            string normal = Slice(
                source,
                "Application.Run(ctx);",
                "StartupDiagnostics.Mark(\"guardian.shutdown_complete\");");

            AssertShutdownOrder(early);
            AssertShutdownOrder(busOnly);
            AssertShutdownOrder(normal);
            Assert.Equal(3, CountOccurrences(source, "npcShopTask.Dispose();"));
            Assert.Equal(3, CountOccurrences(source, "craftingTask.Dispose();"));
            Assert.Equal(3, CountOccurrences(source, "hairdresserTask.Dispose();"));
            Assert.Equal(3, CountOccurrences(source, "characterBuildTask.Dispose();"));
        }

        [Fact]
        public void HairdresserTrackedClose_ClearsPendingAtPanelHostObserver()
        {
            string source = File.ReadAllText(FindProgramSource());
            string observer = Slice(
                source,
                "panelHost.SetPanelCloseObserver(delegate",
                "skillTask.SetCoordinatorSettled");

            const string clear =
                "if (panelName == \"hairdresser\") hairdresserTask.ClearPending();";
            Assert.Contains(clear, observer);
            Assert.Equal(1, CountOccurrences(observer, "hairdresserTask.ClearPending();"));
        }

        [Fact]
        public void CharacterAuthorityGateAndPostCloseSafetyNetComposeBothCoordinators()
        {
            string source = File.ReadAllText(FindProgramSource());
            string authorityGate = Slice(
                source,
                "panelHost.SetOpenGate(delegate",
                "panelHost.SetRebindGate(delegate");
            Assert.Contains(
                "!characterBuildTask.HasBoundPanel",
                authorityGate);

            string gate = Slice(
                source,
                "panelHost.SetRebindGate(delegate",
                "panelHost.SetInitDataEnricher");
            Assert.Contains("equipmentTuningTask.HasBoundPanel", gate);
            Assert.Contains("!equipmentTuningTask.CanRebind", gate);
            Assert.DoesNotContain("characterBuildTask", gate);

            string observer = Slice(
                source,
                "panelHost.SetPanelCloseObserver(delegate",
                "skillTask.SetCoordinatorSettled");
            Assert.Contains(
                "panelHost.PanelClosed += delegate(",
                observer);
            Assert.Contains(
                ".BeginNormalCloseBarrier(",
                observer);
            Assert.Contains(
                ".ContinueDetachRecoveryAfterVisualRetired(",
                observer);
            Assert.DoesNotContain(
                "characterBuildTask.EnsureNormalClose(panelInstanceId);",
                observer);
            Assert.DoesNotContain(
                "characterBuildTask.TryClosePanelInstance(panelInstanceId);",
                observer);
        }

        [Fact]
        public void CharacterBuildReconnectUsesTypedSocketGeneration()
        {
            string source = File.ReadAllText(
                FindProgramSource());
            Assert.Contains(
                "socketServer.OnClientReadyForGeneration += webOverlay.OnSocketReconnected;",
                source);
            Assert.DoesNotContain(
                "socketServer.OnClientReady += webOverlay.OnSocketReconnected;",
                source);
        }

        [Fact]
        public void LootAdmissionIsFencedByAnyRetainedCharacterAuthority()
        {
            string source = File.ReadAllText(
                FindProgramSource());
            string setup = Slice(
                source,
                "CharacterBuildTask characterBuildTask =",
                "SkillTask skillTask =");
            Assert.Contains(
                "lootPanelCoordinator.SetExternalAdmissionGate(",
                setup);
            Assert.Contains(
                "!characterBuildTask.HasBoundPanel",
                setup);
        }

        [Fact]
        public void CharacterBuildAgentOpenerUsesOnlyFixedBattleboxPayload()
        {
            string source = File.ReadAllText(FindProgramSource());
            string opener = Slice(
                source,
                "agentControlTask.SetCharacterBuildOpenAction(delegate",
                "agentControlTask.SetActivePanelStatusProvider");
            Assert.Contains(
                "\\\"task\\\":\\\"cmd\\\",\\\"action\\\":\\\"openInventoryWorkbench\\\"",
                opener);
            Assert.Contains(
                "\\\"profile\\\":\\\"battlebox\\\",\\\"view\\\":\\\"build\\\","
                    + "\\\"source\\\":\\\"agent_control\\\"",
                opener);
            Assert.DoesNotContain("panelName", opener);
            Assert.DoesNotContain("initData", opener);
        }

        [Fact]
        public void EquipmentTuningAgentOpenerUsesFixedPayloadAndShutdownAdmission()
        {
            string source =
                File.ReadAllText(
                    FindProgramSource());
            string opener =
                Slice(
                    source,
                    "agentControlTask.SetEquipmentTuningOpenAction(delegate",
                    "agentControlTask.SetCharacterBuildOpenAction(delegate");
            Assert.Contains(
                "\\\"task\\\":\\\"cmd\\\",\\\"action\\\":\\\"openInventoryWorkbench\\\"",
                opener);
            Assert.Contains(
                "\\\"profile\\\":\\\"battlebox\\\",\\\"view\\\":\\\"tuning\\\","
                    + "\\\"source\\\":\\\"agent_control\\\"",
                opener);
            Assert.Contains(
                "!form.IsShutdownAdmissionClosed",
                opener);
            Assert.DoesNotContain(
                "panelName",
                opener);
            Assert.DoesNotContain(
                "initData",
                opener);
        }

        [Fact]
        public void CharacterBuildShutdownFenceIsWiredBeforeEarlyCleanup()
        {
            string source =
                File.ReadAllText(
                    FindProgramSource());
            string fence = Slice(
                source,
                "form.OnShutdownFence = delegate",
                "form.OnShutdownEarly = delegate");
            Assert.Contains(
                ".TryCompleteHostShutdownPersistence(",
                fence);
            Assert.Contains(
                "3000",
                fence);
            Assert.Contains(
                "角色配装尚未安全保存，已取消退出；请稍后重试，或按 Ctrl+Q 放弃未保存改动并强制退出",
                fence);
            Assert.DoesNotContain(
                "characterBuildTask.Dispose();",
                fence);
            Assert.Contains(
                "commandRouter.SetPanelAdmissionGate(",
                source);
            Assert.Contains(
                "characterBuildTask.SetAdmissionGate(",
                source);
            string opener = Slice(
                source,
                "agentControlTask.SetCharacterBuildOpenAction(delegate",
                "agentControlTask.SetActivePanelStatusProvider");
            Assert.Contains(
                "!form.IsShutdownAdmissionClosed",
                opener);
        }

        [Fact]
        public void GuardianRunsCancellableFenceBeforeShutdownLifecycleAndExitGuard()
        {
            string source =
                File.ReadAllText(
                    FindGuardianFormSource());
            string exit = Slice(
                source,
                "private bool DoExit()",
                "private void CleanupTrayIcon()");
            int fence =
                exit.IndexOf(
                    "TryPassShutdownFence()",
                    StringComparison.Ordinal);
            int lifecycle =
                exit.IndexOf(
                    "GuardianLifecycle.MarkShuttingDown();",
                    StringComparison.Ordinal);
            int guard =
                exit.IndexOf(
                    "Thread exitGuard",
                    StringComparison.Ordinal);
            int early =
                exit.IndexOf(
                    "OnShutdownEarly()",
                    StringComparison.Ordinal);
            Assert.True(
                fence >= 0
                && lifecycle > fence
                && guard > lifecycle
                && early > guard);
            Assert.Contains(
                "ref _exitStarted, 0",
                exit);
            Assert.Contains(
                "return false;",
                exit);
            Assert.Contains(
                "!DoExit();",
                source);
            Assert.Contains(
                "if (!skipShutdownFence",
                exit);
            string helper = Slice(
                source,
                "private bool TryPassShutdownFence()",
                "private bool DoExit()");
            Assert.Contains(
                "OnShutdownFence()",
                helper);
            Assert.Contains(
                "OnShutdownFence = null;",
                helper);

            string asyncClose = Slice(
                source,
                "private void OnFormClosing(object sender, FormClosingEventArgs e)",
                "private void TerminateCloseOnce(string reason)");
            int preResetFence =
                asyncClose.IndexOf(
                    "TryPassShutdownFence()",
                    StringComparison.Ordinal);
            int reset =
                asyncClose.IndexOf(
                    "_launchFlow.Reset(null, \"user_close\")",
                    StringComparison.Ordinal);
            Assert.True(
                preResetFence >= 0
                && reset > preResetFence,
                "async close must persist before initiating or joining launch Reset");
            int closeAdmission =
                asyncClose.IndexOf(
                    "_closeAlreadyInProgress = true;",
                    StringComparison.Ordinal);
            Assert.True(
                closeAdmission >= 0
                && closeAdmission < preResetFence,
                "async close must stop new panel/loadout admission before persistence proof");
            Assert.Contains(
                "_closeAlreadyInProgress = false;",
                asyncClose);
            Assert.Contains(
                "public bool IsShutdownAdmissionClosed",
                source);
        }

        [Fact]
        public void GuardianEmergencyExitAllowlistIsClosedAndUnknownValuesFailClosed()
        {
            Array values =
                Enum.GetValues(
                    typeof(
                        GuardianForm.EmergencyExitReason));
            Assert.Equal(
                4,
                values.Length);
            Assert.Equal(
                "ctrl_q",
                GuardianForm.EmergencyExitReasonCodeForTest(
                    GuardianForm.EmergencyExitReason.CtrlQ));
            Assert.Equal(
                "hard_exit_key_q",
                GuardianForm.EmergencyExitReasonCodeForTest(
                    GuardianForm.EmergencyExitReason.HardExitKeyQ));
            Assert.Equal(
                "flash_exited_ready",
                GuardianForm.EmergencyExitReasonCodeForTest(
                    GuardianForm.EmergencyExitReason.FlashExitedReady));
            Assert.Equal(
                "flash_zombie_watchdog",
                GuardianForm.EmergencyExitReasonCodeForTest(
                    GuardianForm.EmergencyExitReason.FlashZombieWatchdog));
            Assert.Null(
                GuardianForm.EmergencyExitReasonCodeForTest(
                    (GuardianForm.EmergencyExitReason)999));
        }

        [Fact]
        public void EmergencyExitIsLimitedToExplicitHardExitAndDeadFlashCallers()
        {
            string guardian =
                File.ReadAllText(
                    FindGuardianFormSource());
            Assert.Contains(
                "EmergencyExitReason.CtrlQ",
                Slice(
                    guardian,
                    "private void SetupHotkeys()",
                    "private bool IsReadyForHotkey()"));
            Assert.Contains(
                "EmergencyExitReason.CtrlQ",
                Slice(
                    guardian,
                    "protected override void WndProc(ref Message m)",
                    "private void OnSessionSwitch"));
            Assert.Contains(
                "case Keys.Q:",
                guardian);
            Assert.Contains(
                "EmergencyExitReason.HardExitKeyQ",
                Slice(
                    guardian,
                    "public void HandleButtonClick(Keys key)",
                    "public void SendKeyToFlash(Keys key)"));
            Assert.Contains(
                "_trayMenu.Items.Add(\"退出\", null, delegate { ForceExit(); });",
                guardian);
            Assert.Contains(
                "!DoExit();",
                guardian);

            string launchFlow =
                File.ReadAllText(
                    Path.Combine(
                        Path.GetDirectoryName(
                            FindGuardianFormSource()),
                        "GameLaunchFlow.cs"));
            Assert.Equal(
                1,
                CountOccurrences(
                    launchFlow,
                    "EmergencyExitReason.FlashExitedReady"));
            Assert.Equal(
                1,
                CountOccurrences(
                    launchFlow,
                    "EmergencyExitReason.FlashZombieWatchdog"));
            Assert.DoesNotContain(
                "_form.ForceExit();",
                launchFlow);

            string program =
                File.ReadAllText(
                    FindProgramSource());
            Assert.Equal(
                3,
                CountOccurrences(
                    program,
                    "EmergencyExitReason.HardExitKeyQ"));
            Assert.Contains(
                "httpServer.SetShutdownAction(delegate { form.ForceExit(); });",
                program);
            Assert.Contains(
                "agentControlTask.SetShutdownAction(delegate { form.ForceExit(); });",
                program);
            Assert.Contains(
                "new Action(form.ForceExit)",
                Slice(
                    program,
                    "LauncherCommandRouter commandRouter = new LauncherCommandRouter(",
                    "commandRouter.SetFallbackVisualRetire"));
            Assert.Contains(
                "config.PreparationNavigationV1",
                Slice(
                    program,
                    "LauncherCommandRouter commandRouter = new LauncherCommandRouter(",
                    "commandRouter.SetFallbackVisualRetire"));

            string launcherRouter =
                File.ReadAllText(
                    Path.Combine(
                        Path.GetDirectoryName(
                            FindGuardianFormSource()),
                        "LauncherCommandRouter.cs"));
            Assert.Contains(
                "case \"EXIT_CONFIRM\":",
                launcherRouter);
            Assert.Contains(
                "if (ConsumeSafeExitConfirmCapability())",
                launcherRouter);
            Assert.DoesNotContain(
                "case \"EXIT_CONFIRM\": ForceExit();",
                launcherRouter);
            Assert.DoesNotContain(
                "EmergencyExit(",
                launcherRouter);
            Assert.Contains(
                "commandRouter.OnSafeExitSendFailed =",
                program);
            Assert.Contains(
                "commandRouter.TryConsumeSafeExitConfirm =",
                program);
            Assert.Contains(
                "safeExitPanel.HandleUiData(pkt);",
                program);

            string guardianDirectory =
                Path.GetDirectoryName(
                    FindGuardianFormSource());
            AssertQHardExitPrecedesGenericRouter(
                File.ReadAllText(
                    Path.Combine(
                        guardianDirectory,
                        "NotchOverlay.cs")));
            AssertQHardExitPrecedesGenericRouter(
                File.ReadAllText(
                    Path.Combine(
                        guardianDirectory,
                        "Hud",
                        "NotchWidget.cs")));
        }

        private static void AssertQHardExitPrecedesGenericRouter(
            string source)
        {
            int q =
                source.IndexOf(
                    "else if (def.CommandKey == \"Q\")",
                    StringComparison.Ordinal);
            int generic =
                source.IndexOf(
                    "else if (!string.IsNullOrEmpty(def.CommandKey) && _router != null)",
                    q,
                    StringComparison.Ordinal);
            Assert.True(
                q >= 0 && generic > q,
                "Q 强退 must invoke its explicit emergency callback before generic key routing.");
        }

        private static void AssertShutdownOrder(string block)
        {
            const string npcShopDispose = "npcShopTask.Dispose();";
            const string craftingDispose = "craftingTask.Dispose();";
            const string hairdresserDispose = "hairdresserTask.Dispose();";
            const string characterBuildDispose =
                "characterBuildTask.Dispose();";
            int npcShopIndex = block.IndexOf(npcShopDispose, StringComparison.Ordinal);
            int craftingIndex = block.IndexOf(craftingDispose, StringComparison.Ordinal);
            int hairdresserIndex = block.IndexOf(hairdresserDispose, StringComparison.Ordinal);
            int characterBuildIndex =
                block.IndexOf(characterBuildDispose, StringComparison.Ordinal);

            Assert.True(npcShopIndex >= 0, "NpcShopTask must be disposed in this shutdown path.");
            Assert.True(craftingIndex >= 0, "CraftingTask must be disposed in this shutdown path.");
            Assert.True(hairdresserIndex >= 0, "HairdresserTask must be disposed in this shutdown path.");
            Assert.True(
                characterBuildIndex >= 0,
                "CharacterBuildTask must be disposed in this shutdown path.");
            Assert.True(
                npcShopIndex < craftingIndex && craftingIndex < hairdresserIndex,
                "Transaction panel tasks must keep their declared shutdown order.");
            Assert.Equal(1, CountOccurrences(block, npcShopDispose));
            Assert.Equal(1, CountOccurrences(block, craftingDispose));
            Assert.Equal(1, CountOccurrences(block, hairdresserDispose));
            Assert.Equal(1, CountOccurrences(block, characterBuildDispose));
        }

        private static string Slice(string source, string startMarker, string endMarker)
        {
            int start = source.IndexOf(startMarker, StringComparison.Ordinal);
            Assert.True(start >= 0, "Missing Program.cs start marker: " + startMarker);
            int end = source.IndexOf(endMarker, start, StringComparison.Ordinal);
            Assert.True(end > start, "Missing Program.cs end marker: " + endMarker);
            return source.Substring(start, end - start);
        }

        private static int CountOccurrences(string source, string value)
        {
            int count = 0;
            int offset = 0;
            while ((offset = source.IndexOf(value, offset, StringComparison.Ordinal)) >= 0)
            {
                count++;
                offset += value.Length;
            }
            return count;
        }

        private static string FindProgramSource()
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string fromRepository = Path.Combine(
                    current.FullName,
                    "launcher",
                    "src",
                    "Program.cs");
                if (File.Exists(fromRepository))
                    return fromRepository;

                string fromLauncher = Path.Combine(current.FullName, "src", "Program.cs");
                if (File.Exists(fromLauncher))
                    return fromLauncher;

                current = current.Parent;
            }

            throw new FileNotFoundException("Unable to locate launcher/src/Program.cs.");
        }

        private static string FindGuardianFormSource()
        {
            DirectoryInfo current =
                new DirectoryInfo(
                    AppContext.BaseDirectory);
            while (current != null)
            {
                string fromRepository =
                    Path.Combine(
                        current.FullName,
                        "launcher",
                        "src",
                        "Guardian",
                        "GuardianForm.cs");
                if (File.Exists(fromRepository))
                    return fromRepository;

                string fromLauncher =
                    Path.Combine(
                        current.FullName,
                        "src",
                        "Guardian",
                        "GuardianForm.cs");
                if (File.Exists(fromLauncher))
                    return fromLauncher;

                current = current.Parent;
            }

            throw new FileNotFoundException(
                "Unable to locate launcher/src/Guardian/GuardianForm.cs.");
        }
    }
}
