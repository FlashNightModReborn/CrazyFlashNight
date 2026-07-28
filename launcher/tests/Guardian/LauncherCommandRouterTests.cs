using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// Router 单测。Flag OFF 路径（_panelHost == null）触发 PostToWeb fallback；
    /// Flag ON 路径无法在单测里覆盖（PanelHostController 依赖 Form），通过集成测试 + 手测覆盖。
    /// </summary>
    public class LauncherCommandRouterTests
    {
        private class Capture
        {
            public List<Keys> SentKeys = new List<Keys>();
            public List<string> Posts = new List<string>();
            public List<string> ActivePanels = new List<string>();
            public List<bool> StateCallbacks = new List<bool>();
            public List<string> VisualRetires = new List<string>();
            public int Fullscreen, Log, Exit;
        }

        private static LauncherCommandRouter MakeRouter(Capture c)
        {
            LauncherCommandRouter router =
                new LauncherCommandRouter(
                socketServer: null,
                onSendKey: k => c.SentKeys.Add(k),
                onToggleFullscreen: () => c.Fullscreen++,
                onToggleLog: () => c.Log++,
                onForceExit: () => c.Exit++,
                postToWeb: s => c.Posts.Add(s),
                onPanelStateChanged: b => c.StateCallbacks.Add(b),
                setActivePanel: name => c.ActivePanels.Add(name));
            router.SetFallbackVisualRetire(delegate(string reason)
            {
                c.VisualRetires.Add(reason);
                return true;
            });
            return router;
        }

        [Fact]
        public void KeyDispatch_QWRPO_ForwardedAsKeys()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("Q");
            r.Dispatch("W");
            r.Dispatch("R");
            r.Dispatch("P");
            r.Dispatch("O");
            Assert.Equal(new[] { Keys.Q, Keys.W, Keys.R, Keys.P, Keys.O }, c.SentKeys);
        }

        [Fact]
        public void F_TogglesFullscreen_NotSentAsKey()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("F");
            Assert.Equal(1, c.Fullscreen);
            Assert.Empty(c.SentKeys);
        }

        [Fact]
        public void LOG_TogglesLog()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("LOG");
            Assert.Equal(1, c.Log);
        }

        [Fact]
        public void EXIT_ForceExits_ButExitConfirmRequiresCapability()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("EXIT");
            r.Dispatch("EXIT_CONFIRM");
            Assert.Equal(1, c.Exit);

            r.TryConsumeSafeExitConfirm =
                delegate { return false; };
            r.Dispatch("EXIT_CONFIRM");
            Assert.Equal(1, c.Exit);

            r.TryConsumeSafeExitConfirm =
                delegate { return true; };
            r.Dispatch("EXIT_CONFIRM");
            Assert.Equal(2, c.Exit);
        }

        [Fact]
        public void HELP_OpenPanelFallback_PostsPanelCmdOpen()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("HELP");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"help\"", c.Posts[0]);
            Assert.Contains("\"cmd\":\"open\"", c.Posts[0]);
            Assert.Equal(new[] { "help" }, c.ActivePanels);
            Assert.Equal(new[] { true }, c.StateCallbacks);
        }

        [Fact]
        public void WAREHOUSE_DefaultRoute_UsesBattleboxStorage()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("WAREHOUSE");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"workbench\"", c.Posts[0]);
            Assert.Contains("\"profile\":\"battlebox\"", c.Posts[0]);
            Assert.Contains("\"view\":\"storage\"", c.Posts[0]);
            Assert.Contains("\"source\":\"nativehud\"", c.Posts[0]);
            Assert.Equal(new[] { "workbench" }, c.ActivePanels);
            Assert.Equal(new[] { true }, c.StateCallbacks);
        }

        [Fact]
        public void WAREHOUSE_DefaultRoute_DoesNotEmitTuningCapabilitySwitch()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.Dispatch("WAREHOUSE");

            Assert.DoesNotContain("tuningAvailable", Assert.Single(c.Posts));
        }

        [Fact]
        public void MATERIALS_RoutesToWebMaterialAdmissionCommand()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(value);
                    return true;
                });

            r.Dispatch("MATERIALS");

            JObject command =
                JObject.Parse(
                    Assert.Single(commands)
                        .TrimEnd('\0'));
            Assert.Equal(
                "cmd",
                (string)command["task"]);
            Assert.Equal(
                "openMaterialUI",
                (string)command["action"]);
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void MATERIALS_SendFalseShowsUnavailableWithoutOpeningPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                delegate(string value)
                {
                    commands.Add(value);
                    return false;
                });

            r.Dispatch("MATERIALS");

            Assert.Single(commands);
            Assert.Contains(
                "材料面板暂时不可用",
                Assert.Single(c.Posts));
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void MATERIALS_SendThrowShowsUnavailableWithoutEscapingRouter()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            int attempts = 0;
            r.SetGameCommandSenderForTests(
                delegate
                {
                    attempts++;
                    throw new InvalidOperationException(
                        "material transport down");
                });

            r.Dispatch("MATERIALS");

            Assert.Equal(1, attempts);
            Assert.Contains(
                "材料面板暂时不可用",
                Assert.Single(c.Posts));
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void MATERIALS_CharacterBuildBindingRejectsBeforeFlashSend()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using (var task =
                new CharacterBuildTask(
                    delegate
                    {
                        throw new InvalidOperationException(
                            "material route must not use character transport");
                    }))
            {
                Assert.True(
                    task.TryBindPanelInstance(
                        "panel.workbench.material.bound"));
                r.SetCharacterBuildTask(task);
                int sends = 0;
                r.SetGameCommandSenderForTests(
                    delegate
                    {
                        sends++;
                        return true;
                    });

                r.Dispatch("MATERIALS");

                Assert.Equal(0, sends);
                Assert.Contains(
                    "请先完成当前装备面板操作",
                    Assert.Single(c.Posts));
                Assert.True(task.HasBoundPanel);
            }
        }

        [Fact]
        public void MATERIALS_CharacterBuildRecoveryRejectsBeforeFlashSend()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using (var task =
                new CharacterBuildTask(
                    delegate { return true; }))
            {
                Assert.True(
                    task.TryBindPanelInstance(
                        "panel.workbench.material.recovery"));
                Assert.True(
                    task.BeginWebViewDetachBarrier());
                Assert.True(
                    task.RequiresDetachRecovery);
                r.SetCharacterBuildTask(task);
                int sends = 0;
                r.SetGameCommandSenderForTests(
                    delegate
                    {
                        sends++;
                        return true;
                    });

                r.Dispatch("MATERIALS");

                Assert.Equal(0, sends);
                Assert.Contains(
                    "请先完成当前装备面板操作",
                    Assert.Single(c.Posts));
                Assert.True(
                    task.RequiresDetachRecovery);
            }
        }

        [Fact]
        public void MATERIALS_ActiveFallbackVisualRejectsBeforeFlashSend()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                delegate(string value)
                {
                    commands.Add(value);
                    return true;
                });
            r.Dispatch("HELP");
            Assert.Equal(
                "help",
                r.ActiveFallbackPanelName);
            c.Posts.Clear();
            commands.Clear();

            r.Dispatch("MATERIALS");

            Assert.Empty(commands);
            Assert.Contains(
                "请先关闭当前面板",
                Assert.Single(c.Posts));
        }

        [Fact]
        public void MATERIALS_ActivePanelHostVisualRejectsBeforeFlashSend()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var pumps = new Queue<Action>();
            using (var host =
                new PanelHostController(
                    delegate(Action pump)
                    {
                        pumps.Enqueue(pump);
                    },
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                r.SetPanelHost(host);
                Assert.True(
                    host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));
                Assert.Single(pumps);
                Action pump =
                    pumps.Dequeue();
                pump();
                Assert.True(host.IsPanelOpen);
                int sends = 0;
                r.SetGameCommandSenderForTests(
                    delegate
                    {
                        sends++;
                        return true;
                    });

                r.Dispatch("MATERIALS");

                Assert.Equal(0, sends);
                Assert.Contains(
                    "请先关闭当前面板",
                    Assert.Single(c.Posts));
                Assert.Equal(
                    "map",
                    host.ActivePanelName);
            }
        }

        [Fact]
        public void MATERIALS_QueuedPanelHostOpenRejectsBeforeFlashSend()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var pumps = new Queue<Action>();
            using (var host =
                new PanelHostController(
                    delegate(Action pump)
                    {
                        pumps.Enqueue(pump);
                    },
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                r.SetPanelHost(host);
                Assert.True(
                    host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));
                Assert.False(host.IsPanelOpen);
                Assert.False(host.IsIdleForTrackedOpen);
                Assert.Single(pumps);
                int sends = 0;
                r.SetGameCommandSenderForTests(
                    delegate
                    {
                        sends++;
                        return true;
                    });

                r.Dispatch("MATERIALS");

                Assert.Equal(0, sends);
                Assert.Contains(
                    "请先关闭当前面板",
                    Assert.Single(c.Posts));
                Assert.False(host.IsPanelOpen);
            }
        }

        [Fact]
        public void MATERIALS_ReservedTrackedOpenRejectsBeforeFlashSend()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var pumps = new Queue<Action>();
            using (var host =
                new PanelHostController(
                    delegate(Action pump)
                    {
                        pumps.Enqueue(pump);
                    },
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                r.SetPanelHost(host);
                Assert.True(
                    host.TryOpenTrackedPanel(
                        "loot",
                        "{}",
                        "panel.loot.material-race",
                        delegate { return true; },
                        null));
                Assert.False(host.IsPanelOpen);
                Assert.False(host.IsIdleForTrackedOpen);
                Assert.Single(pumps);
                int sends = 0;
                r.SetGameCommandSenderForTests(
                    delegate
                    {
                        sends++;
                        return true;
                    });

                r.Dispatch("MATERIALS");

                Assert.Equal(0, sends);
                Assert.Contains(
                    "请先关闭当前面板",
                    Assert.Single(c.Posts));
                Assert.False(host.IsPanelOpen);
            }
        }

        [Fact]
        public void ShutdownAdmissionGateRejectsNewBuildMaterialAndWebPanelIngress()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            int sends = 0;
            r.SetGameCommandSenderForTests(
                delegate
                {
                    sends++;
                    return true;
                });
            r.SetPanelAdmissionGate(
                delegate { return false; });

            r.Dispatch("EQUIP_UI");
            r.Dispatch("MATERIALS");
            r.RequestOpenPanel(
                "help",
                "shutdown_race",
                null);

            Assert.Equal(0, sends);
            Assert.Empty(c.Posts);
            Assert.Null(
                r.ActiveFallbackPanelName);
        }

        [Fact]
        public void WAREHOUSE_DisabledRoute_DoesNotOpenWebPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.WebInventoryWorkbenchEnabled = false;
            r.Dispatch("WAREHOUSE");
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Fact]
        public void EQUIP_UI_DefaultSendsFixedBuildPreflightWithoutOpeningPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(value => { commands.Add(value); return true; });
            r.Dispatch("EQUIP_UI");

            JObject command =
                JObject.Parse(
                    Assert.Single(commands)
                        .TrimEnd('\0'));
            Assert.Equal(
                "cmd",
                (string)command["task"]);
            Assert.Equal(
                "openInventoryWorkbench",
                (string)command["action"]);
            Assert.Equal(
                "battlebox",
                (string)command["profile"]);
            Assert.Equal(
                "build",
                (string)command["view"]);
            Assert.Equal(
                "nativehud_equipment",
                (string)command["source"]);
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    Assert.Single(commands));
            Assert.Equal(6, command.Count);
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                openRequestId);
        }

        [Fact]
        public void EQUIP_UI_PreflightFailureToastsWithoutLegacyOrPanelFallback()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(value => { commands.Add(value); return false; });
            r.Dispatch("EQUIP_UI");

            JObject command =
                JObject.Parse(
                    Assert.Single(commands)
                        .TrimEnd('\0'));
            Assert.Equal(
                "openInventoryWorkbench",
                (string)command["action"]);
            JObject toast =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "toast",
                (string)toast["type"]);
            Assert.Null(toast["panel"]);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Fact]
        public void EQUIP_UI_SendTrueWaitsForExactPanelRequestAndTimesOut()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.NativeEquipmentBuildOpenTimeoutMs = 500;
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                payload =>
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("EQUIP_UI");

            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.True(
                System.Threading.SpinWait.SpinUntil(
                    () => c.Posts.Count == 1,
                    2000));
            Assert.Contains(
                "装备服务未就绪",
                c.Posts[0]);
            Assert.DoesNotContain(
                "\"cmd\":\"open\"",
                c.Posts[0]);
        }

        [Fact]
        public void EQUIP_UI_ExactAckCancelsTimeoutAndOpensOnce()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            // Keep the injected test timeout comfortably above scheduler jitter so
            // an unrelated runner pause cannot race the immediate acknowledgement.
            r.NativeEquipmentBuildOpenTimeoutMs = 500;
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                payload =>
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                ReadWorkbenchOpenRequestId(
                    commands[0]));
            System.Threading.Thread.Sleep(650);

            JObject opened =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "workbench",
                (string)opened["panel"]);
            Assert.Equal(
                "build",
                (string)opened["initData"]["view"]);
        }

        [Fact]
        public void EQUIP_UI_SynchronousAckDuringSendCannotLeaveStaleTimeout()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.NativeEquipmentBuildOpenTimeoutMs = 500;
            r.SetGameCommandSenderForTests(
                delegate(string payload)
                {
                    JObject command =
                        ParseWire(payload);
                    if (command.Value<string>("action")
                        != "openInventoryWorkbench")
                    {
                        return true;
                    }
                    string openRequestId =
                        ReadWorkbenchOpenRequestId(
                            payload);
                    r.RequestOpenPanel(
                        "workbench",
                        "nativehud_equipment",
                        null,
                        null,
                        null,
                        null,
                        null,
                        "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                        openRequestId);
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            System.Threading.Thread.Sleep(650);

            JObject opened =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "workbench",
                (string)opened["panel"]);
        }

        [Fact]
        public void EQUIP_UI_SynchronousAckFollowedBySendFalseDoesNotReportFailure()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.NativeEquipmentBuildOpenTimeoutMs = 40;
            r.SetGameCommandSenderForTests(
                delegate(string payload)
                {
                    JObject command =
                        ParseWire(payload);
                    if (command.Value<string>("action")
                        == "openInventoryWorkbench")
                    {
                        r.RequestOpenPanel(
                            "workbench",
                            "nativehud_equipment",
                            null,
                            null,
                            null,
                            null,
                            null,
                            "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                            command.Value<string>(
                                "openRequestId"));
                        return false;
                    }
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            System.Threading.Thread.Sleep(100);

            JObject opened =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "workbench",
                opened.Value<string>("panel"));
            Assert.DoesNotContain(
                "toast",
                c.Posts[0]);
        }

        [Fact]
        public void EQUIP_UI_DuplicateWhilePendingSendsOnlyOnePreflight()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.NativeEquipmentBuildOpenTimeoutMs = 2000;
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                payload =>
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            r.Dispatch("EQUIP_UI");

            Assert.Single(commands);
            Assert.Empty(c.Posts);
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                ReadWorkbenchOpenRequestId(
                    commands[0]));
        }

        [Fact]
        public void EQUIP_UI_TimeoutRejectsLateNativeBuildAck()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.NativeEquipmentBuildOpenTimeoutMs = 100;
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                payload =>
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            Assert.True(
                System.Threading.SpinWait.SpinUntil(
                    () => c.Posts.Count == 1,
                    2000));
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                ReadWorkbenchOpenRequestId(
                    commands[0]));

            Assert.Single(c.Posts);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void EQUIP_UI_CompetingPanelRejectsPendingNativeBuildAck()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.NativeEquipmentBuildOpenTimeoutMs = 2000;
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                payload =>
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            r.RequestOpenPanel(
                "map",
                "competition",
                null);
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                ReadWorkbenchOpenRequestId(
                    commands[0]));

            JObject opened =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "map",
                (string)opened["panel"]);
            Assert.Equal(
                new[] { "map" },
                c.ActivePanels);
        }

        [Fact]
        public void EQUIP_UI_QueuedHostOpenInvalidatesIdleAdmissionBeforeItBecomesActive()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var pumps =
                new Queue<Action>();
            var commands =
                new List<string>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                r.SetPanelHost(host);
                r.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(payload);
                        return true;
                    });
                r.Dispatch("EQUIP_UI");
                string requestId =
                    ReadWorkbenchOpenRequestId(
                        Assert.Single(commands));
                Assert.True(
                    host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));

                r.RequestOpenPanel(
                    "workbench",
                    "nativehud_equipment",
                    null,
                    null,
                    null,
                    null,
                    null,
                    "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                    requestId);

                Action pump =
                    Assert.Single(pumps);
                pumps.Clear();
                pump();
                Assert.Equal(
                    "map",
                    host.ActivePanelName);
                Assert.Empty(pumps);
            }
        }

        [Fact]
        public void EQUIP_UI_FinalAdmissionRejectionDoesNotLeakWebPanelPause()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var pumps = new Queue<Action>();
            var commands = new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                r.SetPanelHost(host);
                r.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(ParseWire(payload));
                        return true;
                    });
                r.Dispatch("EQUIP_UI");
                string requestId =
                    commands.Single(command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench")
                    .Value<string>("openRequestId");

                bool invalidated = false;
                r.SetPanelAdmissionGate(
                    delegate
                    {
                        if (!invalidated)
                        {
                            invalidated = true;
                            Assert.True(
                                host.TryAcquireIdleFence(
                                    "admission.pause.race"));
                            Assert.True(
                                host.ReleaseIdleFenceExact(
                                    "admission.pause.race"));
                        }
                        return true;
                    });
                r.RequestOpenPanel(
                    "workbench",
                    "nativehud_equipment",
                    null,
                    null,
                    null,
                    null,
                    null,
                    "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                    requestId);

                Assert.True(invalidated);
                Assert.DoesNotContain(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "webPanelPause");
                Assert.False(host.IsPanelOpen);
                Assert.Empty(pumps);
            }
        }

        [Fact]
        public void EQUIP_UI_TimeoutWithAnotherActivePanelCancelsWithoutFalseToast()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.NativeEquipmentBuildOpenTimeoutMs = 500;
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                payload =>
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            r.RequestOpenPanel(
                "map",
                "competition",
                null);
            System.Threading.Thread.Sleep(650);

            JObject opened =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "map",
                (string)opened["panel"]);
            Assert.DoesNotContain(
                "装备服务未就绪",
                c.Posts[0]);

            // Timeout still consumes the pending admission, so a late native ack cannot
            // replace the panel that won the competition.
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                ReadWorkbenchOpenRequestId(
                    commands[0]));
            Assert.Single(c.Posts);
            Assert.Equal(
                new[] { "map" },
                c.ActivePanels);
        }

        [Fact]
        public void EQUIP_UI_NearMatchDoesNotConsumePendingExactAck()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.NativeEquipmentBuildOpenTimeoutMs = 2000;
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                payload =>
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            r.RequestOpenPanel(
                "WORKBENCH",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                ReadWorkbenchOpenRequestId(
                    Assert.Single(commands)));
            Assert.Empty(c.Posts);
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}");
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                "workbench.open.foreign");
            Assert.Empty(c.Posts);
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                ReadWorkbenchOpenRequestId(
                    Assert.Single(commands)));

            JObject opened =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "workbench",
                (string)opened["panel"]);
        }

        [Fact]
        public void SkillsIntentSupersedesOlderNativeBuildPreflight()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands =
                new List<string>();
            r.SetGameCommandSenderForTests(
                delegate(string payload)
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            r.Dispatch("SKILLS");
            JObject native =
                commands.Select(ParseWire).Single(
                    command =>
                        command.Value<string>("action")
                        == "openInventoryWorkbench");
            JObject skills =
                commands.Select(ParseWire).Single(
                    command =>
                        command.Value<string>("action")
                        == "skillPanelOpen");

            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                native.Value<string>("openRequestId"));
            Assert.Empty(c.Posts);

            RequestNativeSkillManage(
                r,
                skills.Value<string>("openRequestId"));
            JObject opened =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "skills",
                opened.Value<string>("panel"));
        }

        [Fact]
        public void NativeBuildIntentSupersedesOlderSkillsPreflight()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands =
                new List<string>();
            r.SetGameCommandSenderForTests(
                delegate(string payload)
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("SKILLS");
            r.Dispatch("EQUIP_UI");
            JObject skills =
                commands.Select(ParseWire).Single(
                    command =>
                        command.Value<string>("action")
                        == "skillPanelOpen");
            JObject native =
                commands.Select(ParseWire).Single(
                    command =>
                        command.Value<string>("action")
                        == "openInventoryWorkbench");

            RequestNativeSkillManage(
                r,
                skills.Value<string>("openRequestId"));
            Assert.Empty(c.Posts);

            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                native.Value<string>("openRequestId"));
            JObject opened =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "workbench",
                opened.Value<string>("panel"));
        }

        [Fact]
        public void NativeStorageRequestCancelsOlderNativeBuildPreflight()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands =
                new List<string>();
            r.SetGameCommandSenderForTests(
                delegate(string payload)
                {
                    commands.Add(payload);
                    return true;
                });

            r.Dispatch("EQUIP_UI");
            string staleRequestId =
                ReadWorkbenchOpenRequestId(
                    Assert.Single(commands));
            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"storage\"}");
            string storageInstance =
                r.ActiveFallbackPanelInstanceId;
            Assert.False(
                string.IsNullOrEmpty(storageInstance));

            r.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                staleRequestId);

            Assert.Single(c.Posts);
            Assert.Equal(
                storageInstance,
                r.ActiveFallbackPanelInstanceId);
            Assert.Equal(
                "storage",
                JObject.Parse(c.Posts[0])[
                    "initData"].Value<string>("view"));
        }

        [Fact]
        public void EQUIP_UI_ExplicitDisabledFlagUsesLegacyEquipmentFallback()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.WebInventoryWorkbenchEnabled =
                false;
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(value => { commands.Add(value); return true; });
            r.Dispatch("EQUIP_UI");

            JObject command =
                JObject.Parse(
                    Assert.Single(commands)
                        .TrimEnd('\0'));
            Assert.Equal(
                "openEquipUI",
                (string)command["action"]);
            Assert.Equal(2, command.Count);
            Assert.Empty(c.Posts);
        }

        [Theory]
        [InlineData("{\"profile\":\"battlebox\",\"view\":\"tuning\"}")]
        [InlineData("{\"profile\":\"battlebox\",\"view\":\"storage\"}")]
        [InlineData(null)]
        public void RequestOpenPanel_LegacyEquipmentTuningRedirectIsPaused(string extras)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel("workbench", "legacy_equipment_tuning", null, null, null, null, null, extras);

            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Fact]
        public void CraftingRequest_WhitelistsCategoryAndBuildsRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("crafting", "legacy_crafting_entry", null, null, null, null, null,
                "{\"category\":\"武器合成\",\"ignored\":\"x\"}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"crafting\"", c.Posts[0]);
            Assert.Contains("\"category\":\"武器合成\"", c.Posts[0]);
            Assert.DoesNotContain("ignored", c.Posts[0]);
            Assert.Equal(new[] { "crafting" }, c.ActivePanels);
        }

        [Fact]
        public void CraftingRequest_RejectsUnknownCategory()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("crafting", "legacy_crafting_entry", null, null, null, null, null,
                "{\"category\":\"未知分类\"}");
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void CraftingMaterialsRequest_BuildsReadOnlyMaterialInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel("crafting", "nativehud_materials", null, null, null, null, null,
                "{\"view\":\"materials\",\"category\":\"未知分类\",\"ignored\":\"x\"}");

            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"crafting\"", c.Posts[0]);
            Assert.Contains("\"view\":\"materials\"", c.Posts[0]);
            Assert.Contains("\"source\":\"nativehud_materials\"", c.Posts[0]);
            Assert.DoesNotContain("\"category\"", c.Posts[0]);
            Assert.DoesNotContain("ignored", c.Posts[0]);
            Assert.Equal(new[] { "crafting" }, c.ActivePanels);
        }

        [Fact]
        public void HairdresserRequest_UsesExactRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel(
                "hairdresser",
                "world_hairdresser",
                "ignored-page",
                "ignored-frame",
                "ignored-return-frame",
                "ignored-return-panel",
                "{\"ignored\":true}",
                "{\"ignored\":true}");

            JObject open = JObject.Parse(Assert.Single(c.Posts));
            Assert.Equal("hairdresser", (string)open["panel"]);
            JObject initData = Assert.IsType<JObject>(open["initData"]);
            Assert.Equal(4, initData.Count);
            Assert.Equal("runtime", (string)initData["mode"]);
            Assert.Equal("world_hairdresser", (string)initData["source"]);
            Assert.False((bool)initData["debug"]);
            Assert.Equal(
                (string)open["panelInstanceId"],
                (string)initData["panelInstanceId"]);
            Assert.Null(initData["ignored"]);
            Assert.Equal(new[] { "hairdresser" }, c.ActivePanels);
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("as2_request")]
        [InlineData("world_hairdresser ")]
        public void HairdresserRequest_RejectsNonExactSource(string source)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel(
                "hairdresser",
                source,
                null,
                null,
                null,
                null,
                null,
                null);

            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Fact]
        public void GOBANG_TEST_OpenPanelFallback_IncludesInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("GOBANG_TEST");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"gobang\"", c.Posts[0]);
            Assert.Contains("\"initData\"", c.Posts[0]);
            Assert.Contains("\"ruleset\":\"casual\"", c.Posts[0]);
        }

        [Fact]
        public void INTELLIGENCE_TEST_OpenPanelFallback_IncludesFixtureInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("INTELLIGENCE_TEST");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"intelligence\"", c.Posts[0]);
            Assert.Contains("\"itemName\":\"资料\"", c.Posts[0]);
            Assert.Contains("\"value\":99", c.Posts[0]);
            Assert.Contains("\"decryptLevel\":10", c.Posts[0]);
        }

        [Fact]
        public void INTELLIGENCE_OpenPanelFallback_UsesRuntimeProdInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("INTELLIGENCE");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"intelligence\"", c.Posts[0]);
            Assert.Contains("\"mode\":\"prod\"", c.Posts[0]);
            Assert.Contains("\"source\":\"runtime\"", c.Posts[0]);
            Assert.Contains("\"debug\":false", c.Posts[0]);
            Assert.Equal(new[] { "intelligence" }, c.ActivePanels);
            Assert.Equal(new[] { true }, c.StateCallbacks);
        }

        [Fact]
        public void NewTaskUi_WhenFlashUnavailable_PostsUnavailableToast()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("NEW_TASK_UI");

            Assert.Single(c.Posts);
            Assert.Contains("任务面板暂时不可用", c.Posts[0]);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Theory]
        [InlineData("TEAM")]
        [InlineData("PETS")]
        [InlineData("MERCS")]
        public void TeamEntries_WhenFlashUnavailable_PostUnavailableToast(string key)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.Dispatch(key);

            Assert.Single(c.Posts);
            Assert.Contains("战队面板暂时不可用", c.Posts[0]);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void RequestOpenPanel_Map_RoutesToOpenMapPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("map", "as2_request", "page-1");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"map\"", c.Posts[0]);
            Assert.Contains("\"page\":\"page-1\"", c.Posts[0]);
            Assert.Contains("\"source\":\"as2_request\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_StageSelect_RoutesRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("stage-select", "as2_base_gate", null, "基地门口");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"stage-select\"", c.Posts[0]);
            Assert.Contains("\"mode\":\"runtime\"", c.Posts[0]);
            Assert.Contains("\"fixture\":\"mixed\"", c.Posts[0]);
            Assert.Contains("\"frameLabel\":\"基地门口\"", c.Posts[0]);
            Assert.Contains("\"returnFrameLabel\":\"基地门口\"", c.Posts[0]);
            Assert.Contains("\"source\":\"as2_base_gate\"", c.Posts[0]);
            Assert.Contains("\"debug\":false", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_StageSelect_CarriesExplicitReturnFrame()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("stage-select", "as2_legacy_stage_gate", null, "黑铁会总部", "基地车库");
            Assert.Single(c.Posts);
            Assert.Contains("\"frameLabel\":\"黑铁会总部\"", c.Posts[0]);
            Assert.Contains("\"returnFrameLabel\":\"基地车库\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_Tasks_RoutesToOpenTasksPanelWithInitData()
        {
            // 副本任务（委托任务）入口回归：NPC openWebDungeon 发 panel_request panel="tasks"，
            // 必须开 tasks 面板并透传 initData {view,taskId}。曾因 RequestOpenPanel 无 tasks 分支
            // 静默丢弃（"[Router] RequestOpenPanel unsupported panel=tasks"），NPC 点击无反应。
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("tasks", "npc_dungeon", null, null, null, null, null, "{\"view\":\"dungeon\",\"taskId\":20052}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"tasks\"", c.Posts[0]);
            Assert.Contains("\"view\":\"dungeon\"", c.Posts[0]);
            Assert.Contains("\"taskId\":20052", c.Posts[0]);
            Assert.Contains("\"source\":\"npc_dungeon\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_Team_RoutesToOpenTeamPanelWithInitData()
        {
            // 世界内雇佣入口：NPC openWebHire 发 panel_request panel="team"，必须开 team 面板并
            // 透传 initData {view:"hire",kind,npcId,initialTab}。无 team 分支会静默丢弃（unsupported panel）。
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("team", "npc_hire", null, null, null, null, null, "{\"view\":\"hire\",\"kind\":\"merc\",\"npcId\":\"敌人123\",\"initialTab\":\"mercenary\"}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"team\"", c.Posts[0]);
            Assert.Contains("\"view\":\"hire\"", c.Posts[0]);
            Assert.Contains("\"kind\":\"merc\"", c.Posts[0]);
            Assert.Contains("\"source\":\"npc_hire\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchWarehouse_UsesStrictWarehouseProfile()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("workbench", "dormitory", null, null, null, null, null,
                "{\"profile\":\"warehouse\",\"rightContainer\":\"任意容器\"}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"workbench\"", c.Posts[0]);
            Assert.Contains("\"profile\":\"warehouse\"", c.Posts[0]);
            Assert.Contains("\"view\":\"storage\"", c.Posts[0]);
            Assert.DoesNotContain("tuningAvailable", c.Posts[0]);
            Assert.Contains("\"source\":\"dormitory\"", c.Posts[0]);
            Assert.DoesNotContain("rightContainer", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchUnknownProfile_IsRejected()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("workbench", "dormitory", null, null, null, null, null,
                "{\"profile\":\"仓库\"}");
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchTuning_AllowsNormalEquipmentSource()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("workbench", "nativehud_equipment", null, null, null, null, null,
                "{\"profile\":\"battlebox\",\"view\":\"tuning\",\"ignored\":true}");

            Assert.Single(c.Posts);
            Assert.Contains("\"view\":\"tuning\"", c.Posts[0]);
            Assert.DoesNotContain("tuningAvailable", c.Posts[0]);
            Assert.Contains("\"source\":\"nativehud_equipment\"", c.Posts[0]);
            Assert.DoesNotContain("ignored", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchTuning_AgentControlUsesSameNormalRoute()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("workbench", "agent_control", null, null, null, null, null,
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}");

            Assert.Single(c.Posts);
            Assert.Contains("\"view\":\"tuning\"", c.Posts[0]);
            Assert.DoesNotContain("tuningAvailable", c.Posts[0]);
            Assert.Contains("\"source\":\"agent_control\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchBuild_AllowsOnlyFixedProductionSources()
        {
            Capture accepted = new Capture();
            LauncherCommandRouter router = MakeRouter(accepted);
            router.RequestOpenPanel(
                "workbench",
                "agent_control",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}");
            JObject opened = JObject.Parse(Assert.Single(accepted.Posts));
            Assert.Equal("workbench", (string)opened["panel"]);
            Assert.Equal("battlebox", (string)opened["initData"]["profile"]);
            Assert.Equal("build", (string)opened["initData"]["view"]);
            Assert.Equal("agent_control", (string)opened["initData"]["source"]);

            Capture nativeHud = new Capture();
            LauncherCommandRouter nativeRouter =
                MakeRouter(nativeHud);
            var nativeCommands =
                new List<string>();
            nativeRouter.SetGameCommandSenderForTests(
                payload =>
                {
                    nativeCommands.Add(payload);
                    return true;
                });
            nativeRouter.Dispatch(
                "EQUIP_UI");
            nativeRouter.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                ReadWorkbenchOpenRequestId(
                    Assert.Single(
                        nativeCommands)));
            JObject nativeOpened =
                JObject.Parse(
                    Assert.Single(
                        nativeHud.Posts));
            Assert.Equal(
                "workbench",
                (string)nativeOpened["panel"]);
            Assert.Equal(
                "build",
                (string)nativeOpened[
                    "initData"]["view"]);
            Assert.Equal(
                "nativehud_equipment",
                (string)nativeOpened[
                    "initData"]["source"]);

            Capture foreign = new Capture();
            MakeRouter(foreign).RequestOpenPanel(
                "workbench",
                "as2_request",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}");
            Assert.Empty(foreign.Posts);

            Capture warehouse = new Capture();
            MakeRouter(warehouse).RequestOpenPanel(
                "workbench",
                "agent_control",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"warehouse\",\"view\":\"build\"}");
            Assert.Empty(warehouse.Posts);
        }

        [Fact]
        public void EQUIP_UI_ExactActiveBuildReclickPostsOnlyPanelEscape()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using (var task =
                new CharacterBuildTask(_ => true))
            {
                string instance =
                    OpenFallbackBuild(router);
                Assert.True(
                    task.TryBindPanelInstance(
                        instance));
                router.SetCharacterBuildTask(
                    task);
                capture.Posts.Clear();
                var commands =
                    new List<string>();
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(payload);
                        return true;
                    });

                router.Dispatch("EQUIP_UI");

                Assert.Equal(
                    "{\"type\":\"panel_esc\"}",
                    Assert.Single(capture.Posts));
                Assert.Empty(commands);
                Assert.Equal(
                    instance,
                    router.ActiveFallbackPanelInstanceId);
                Assert.True(
                    task.IsBoundTo(instance));
                Assert.Empty(
                    capture.VisualRetires);
            }
        }

        [Fact]
        public void EQUIP_UI_DisabledFlagUsesLegacyEvenWhenBuildIsActive()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using (var task =
                new CharacterBuildTask(_ => true))
            {
                string instance =
                    OpenFallbackBuild(router);
                Assert.True(
                    task.TryBindPanelInstance(
                        instance));
                router.SetCharacterBuildTask(
                    task);
                router.WebInventoryWorkbenchEnabled =
                    false;
                capture.Posts.Clear();
                var commands =
                    new List<string>();
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(payload);
                        return true;
                    });

                router.Dispatch("EQUIP_UI");

                JObject command =
                    JObject.Parse(
                        Assert.Single(commands)
                            .TrimEnd('\0'));
                Assert.Equal(
                    "openEquipUI",
                    (string)command["action"]);
                Assert.Empty(capture.Posts);
                Assert.Equal(
                    instance,
                    router.ActiveFallbackPanelInstanceId);
                Assert.True(
                    task.IsBoundTo(instance));
            }
        }

        [Fact]
        public void EQUIP_UI_SameNameStorageWithForeignBuildBindingDoesNotEscape()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            router.RequestOpenPanel(
                "workbench",
                "nativehud",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"storage\"}");
            string storageInstance =
                router.ActiveFallbackPanelInstanceId;
            using (var task =
                new CharacterBuildTask(_ => true))
            {
                Assert.True(
                    task.TryBindPanelInstance(
                        "panel.workbench.build.foreign"));
                router.SetCharacterBuildTask(
                    task);
                capture.Posts.Clear();
                var commands =
                    new List<string>();
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(payload);
                        return true;
                    });

                router.Dispatch("EQUIP_UI");

                JObject command =
                    JObject.Parse(
                        Assert.Single(commands)
                            .TrimEnd('\0'));
                Assert.Equal(
                    "openInventoryWorkbench",
                    (string)command["action"]);
                Assert.Equal(
                    "nativehud_equipment",
                    (string)command["source"]);
                Assert.Empty(capture.Posts);
                Assert.Equal(
                    storageInstance,
                    router.ActiveFallbackPanelInstanceId);
                Assert.True(
                    task.IsBoundTo(
                        "panel.workbench.build.foreign"));
            }
        }

        [Fact]
        public void EQUIP_UI_ExactBuildPendingSnapshotStaysBehindWebCloseGate()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using (var task =
                new CharacterBuildTask(_ => true))
            {
                string instance =
                    OpenFallbackBuild(router);
                Assert.True(
                    task.TryBindPanelInstance(
                        instance));
                router.SetCharacterBuildTask(
                    task);
                Assert.True(
                    task.TryBeginHostAccepted(
                        instance,
                        null,
                        "router.reclick.pending",
                        "snapshot",
                        null,
                        out int backendCallId,
                        out string beginError),
                    beginError);
                Assert.True(backendCallId > 0);
                capture.Posts.Clear();
                var commands =
                    new List<string>();
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(payload);
                        return true;
                    });

                router.Dispatch("EQUIP_UI");

                Assert.Equal(
                    "{\"type\":\"panel_esc\"}",
                    Assert.Single(capture.Posts));
                Assert.Empty(commands);
                Assert.Equal(
                    1,
                    task.PendingCount);
                Assert.True(
                    task.IsBoundTo(instance));
                Assert.Equal(
                    instance,
                    router.ActiveFallbackPanelInstanceId);
                Assert.Empty(
                    capture.VisualRetires);
            }
        }

        [Fact]
        public void EQUIP_UI_ExactBuildUnknownWriteStaysBehindWebCloseGate()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            bool taskSend = true;
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        return taskSend;
                    }))
            {
                string instance =
                    OpenFallbackBuild(router);
                Assert.True(
                    task.TryBindPanelInstance(
                        instance));
                PrimeCharacterBuild(
                    task,
                    instance,
                    9);
                taskSend = false;
                Assert.True(
                    task.TryBeginHostAccepted(
                        instance,
                        9,
                        "router.reclick.unknown",
                        "equipEquipment",
                        null,
                        out int backendCallId,
                        out string beginError),
                    beginError);
                Assert.True(backendCallId > 0);
                Assert.Equal(
                    "needs_reconcile",
                    task.WriteState);
                router.SetCharacterBuildTask(
                    task);
                capture.Posts.Clear();
                var commands =
                    new List<string>();
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(payload);
                        return true;
                    });

                router.Dispatch("EQUIP_UI");

                Assert.Equal(
                    "{\"type\":\"panel_esc\"}",
                    Assert.Single(capture.Posts));
                Assert.Empty(commands);
                Assert.Equal(
                    "needs_reconcile",
                    task.WriteState);
                Assert.True(
                    task.IsBoundTo(instance));
                Assert.Equal(
                    instance,
                    router.ActiveFallbackPanelInstanceId);
                Assert.Empty(
                    capture.VisualRetires);
            }
        }

        [Fact]
        public void FallbackPanelSwitchWaitsForCharacterBuildFinalizeProof()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            var flash = new List<string>();
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
                    null,
                    null,
                    null,
                    null,
                    null,
                    "{\"profile\":\"battlebox\",\"view\":\"build\"}");
                string instance = router.ActiveFallbackPanelInstanceId;
                Assert.True(task.BindPanelInstance(instance));
                Assert.True(task.TryBeginHostAccepted(
                    instance,
                    null,
                    "router.build.initial",
                    "snapshot",
                    null,
                    out int initialCallId,
                    out string initialError),
                    initialError);
                Assert.True(task.TryCompleteSuccess(
                    initialCallId,
                    instance,
                    9,
                    "router.build.initial",
                    "snapshot",
                    0,
                    3,
                    3,
                    5,
                    false,
                    true,
                    null,
                    null,
                    out string snapshotError),
                    snapshotError);

                router.RequestOpenPanel("map", "switch_test", null);
                Assert.Single(capture.Posts);
                Assert.Equal(instance, router.ActiveFallbackPanelInstanceId);

                Assert.True(task.TryBeginHostAccepted(
                    instance,
                    9,
                    "router.build.finalize",
                    "finalize",
                    null,
                    out int finalizeCallId,
                    out string finalizeError),
                    finalizeError);
                Assert.True(task.TryCompleteSuccess(
                    finalizeCallId,
                    instance,
                    9,
                    "router.build.finalize",
                    "finalize",
                    1,
                    3,
                    3,
                    5,
                    false,
                    false,
                    true,
                    true,
                    out string proofError),
                    proofError);

                router.RequestOpenPanel("map", "switch_test", null);
                Assert.Equal(2, capture.Posts.Count);
                Assert.Contains("\"cmd\":\"close\"", capture.Posts[1]);
                Assert.Contains("\"panel\":\"workbench\"", capture.Posts[1]);
                Assert.DoesNotContain("\"panel\":\"map\"", capture.Posts[1]);
                Assert.True(task.HasBoundPanel);
                Assert.True(task.RequiresDetachRecovery);
                Assert.Null(router.ActiveFallbackPanelName);
                Assert.Equal(
                    new[] { "character_build_switch" },
                    capture.VisualRetires);
                Assert.Equal(3, flash.Count);
                JObject recovery = JObject.Parse(flash[2]);
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
                // External panel requests are edge-triggered UI actions. The handoff request
                // closes authority A and is intentionally rejected; it is not replayed later.
                Assert.Equal(2, capture.Posts.Count);

                router.RequestOpenPanel(
                    "map", "switch_test", null);
                Assert.Equal(3, capture.Posts.Count);
                Assert.Contains(
                    "\"panel\":\"map\"",
                    capture.Posts[2]);
            }
        }

        [Fact]
        public void CharacterBuildDetachRecoveryFencesEveryPanelBeforePauseReuse()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using (var task = new CharacterBuildTask(_ => true))
            {
                router.SetCharacterBuildTask(task);
                router.RequestOpenPanel(
                    "workbench",
                    "agent_control",
                    null,
                    null,
                    null,
                    null,
                    null,
                    "{\"profile\":\"battlebox\",\"view\":\"build\"}");
                string instance =
                    router.ActiveFallbackPanelInstanceId;
                Assert.True(task.BindPanelInstance(instance));
                Assert.True(task.BeginWebViewDetach(0));
                Assert.True(task.RequiresDetachRecovery);

                router.RequestOpenPanel(
                    "map", "switch_test", null);

                Assert.Single(capture.Posts);
                Assert.Equal(
                    instance,
                    router.ActiveFallbackPanelInstanceId);
            }
        }

        [Fact]
        public void CharacterBuildSkillsNavigation_WaitsForExactRecoveryThenPreflightsOnce()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            var flash = new List<string>();
            var gameCommands = new List<string>();
            var skillFlash = new List<JObject>();
            using (var task = new CharacterBuildTask(
                delegate(string payload)
                {
                    flash.Add(payload.TrimEnd('\0'));
                    return true;
                }))
            using (var skillTask = new SkillTask(
                () => true,
                delegate(string payload)
                {
                    skillFlash.Add(
                        ParseWire(payload));
                    return true;
                }))
            {
                router.SetCharacterBuildTask(task);
                router.SetSkillTask(skillTask);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(payload);
                        return true;
                    });
                router.SkillOpenTimeoutMs = 500;
                int completedHandoffs = 0;
                task.SetCoordinatorSettled(delegate
                {
                    if (router
                        .TryCompleteCharacterBuildSkillsNavigation())
                    {
                        completedHandoffs++;
                    }
                });

                string instance = OpenFallbackBuild(router);
                Assert.True(task.BindPanelInstance(instance));
                PrimeCharacterBuild(task, instance, 9);
                FinalizeCharacterBuild(task, instance, 9);
                capture.Posts.Clear();
                gameCommands.Clear();

                Assert.False(
                    router.TryArmCharacterBuildSkillsNavigation(
                        "fallback.foreign"));
                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.False(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.Equal(
                    instance,
                    router
                        .PendingCharacterBuildSkillsNavigationInstance);
                Assert.Empty(gameCommands);

                Assert.True(
                    task.BeginNormalCloseBarrier(instance));
                router.ClearFallbackPanelInstance();
                Assert.True(
                    task.ContinueDetachRecoveryAfterVisualRetired(0));
                Assert.Empty(gameCommands);
                Assert.Equal(3, flash.Count);
                JObject recovery = JObject.Parse(
                    flash[flash.Count - 1]);
                Assert.Equal(
                    "characterBuildRecoverDetach",
                    recovery.Value<string>("action"));

                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(recovery, 9),
                    null);

                Assert.False(task.HasBoundPanel);
                Assert.False(task.RequiresDetachRecovery);
                Assert.Equal(1, completedHandoffs);
                Assert.Single(gameCommands);
                Assert.Contains(
                    "skillPanelOpen",
                    gameCommands[0]);
                Assert.Empty(capture.Posts);
                Assert.Null(
                    router
                        .PendingCharacterBuildSkillsNavigationInstance);
                Assert.False(
                    router
                        .TryCompleteCharacterBuildSkillsNavigation());
                Assert.Null(router.ActiveFallbackPanelName);
                Assert.Single(gameCommands);
                Assert.Empty(capture.Posts);

                RequestWorldSkillTrainer(
                    router,
                    "trainer.race");
                RequestNativeSkillManage(
                    router,
                    "skill.open.foreign");
                Assert.Null(
                    router.ActiveFallbackPanelName);
                Assert.Empty(capture.Posts);

                RequestNativeSkillManage(
                    router,
                    ReadSkillOpenRequestId(
                        gameCommands[0]));

                Assert.Null(
                    router
                        .PendingCharacterBuildSkillsNavigationInstance);
                Assert.Equal(
                    "skills",
                    router.ActiveFallbackPanelName);
                JObject open = JObject.Parse(
                    Assert.Single(capture.Posts));
                Assert.Equal(
                    "skills",
                    open.Value<string>("panel"));
                Assert.True(
                    (bool)open["initData"][
                        "canReturnCharacterBuild"]);

                string skillsInstance =
                    router.ActiveFallbackPanelInstanceId;
                Assert.True(
                    router.TryArmSkillsCharacterBuildNavigation(
                        skillsInstance));
                Assert.False(
                    router.TryArmSkillsCharacterBuildNavigation(
                        skillsInstance));
                Assert.True(
                    skillTask.HandleAuthoritativePanelClosed(
                        skillsInstance));
                Assert.False(
                    router.TryCompleteSkillsCharacterBuildNavigation());
                router.ClearFallbackPanelInstance();
                Assert.False(
                    router.TryCompleteSkillsCharacterBuildNavigation());

                JObject cleanup =
                    Assert.Single(
                        skillFlash);
                Assert.Equal(
                    "skillPanelClose",
                    cleanup.Value<string>(
                        "action"));
                skillTask.HandleFlashResponse(
                    new JObject
                    {
                        ["task"] = "skill_response",
                        ["callId"] =
                            cleanup.Value<int>(
                                "callId"),
                        ["success"] = true,
                        ["v"] = 1,
                        ["changed"] = false,
                        ["revision"] = 12
                    },
                    null);
                Assert.True(
                    router.TryCompleteSkillsCharacterBuildNavigation());
                Assert.Null(
                    router
                        .PendingSkillsCharacterBuildNavigationInstance);

                JObject buildPreflight =
                    gameCommands
                        .Select(ParseWire)
                        .Last(command =>
                            command.Value<string>(
                                "action")
                            == "openInventoryWorkbench");
                string buildRequestId =
                    buildPreflight.Value<string>(
                        "openRequestId");
                Assert.False(
                    string.IsNullOrEmpty(
                        buildRequestId));
                capture.Posts.Clear();
                router.RequestOpenPanel(
                    "workbench",
                    "nativehud_equipment",
                    null,
                    null,
                    null,
                    null,
                    null,
                    "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                    buildRequestId);
                JObject returnedBuild =
                    JObject.Parse(
                        Assert.Single(
                            capture.Posts));
                Assert.Equal(
                    "skills_return",
                    returnedBuild["initData"]
                        .Value<string>(
                            "navigationOrigin"));
                Assert.Equal(
                    "skills",
                    returnedBuild["initData"]
                        .Value<string>(
                            "returnFocusAction"));
            }
        }

        [Fact]
        public void CharacterBuildSkillsNavigation_CancelsOnlyTheExactArmedInstance()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using (var task = new CharacterBuildTask(_ => true))
            {
                router.SetCharacterBuildTask(task);
                string instance = OpenFallbackBuild(router);
                Assert.True(task.BindPanelInstance(instance));
                PrimeCharacterBuild(task, instance, 9);
                FinalizeCharacterBuild(task, instance, 9);

                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.False(
                    router.CancelCharacterBuildSkillsNavigation(
                        "fallback.foreign",
                        "foreign"));
                Assert.Equal(
                    instance,
                    router
                        .PendingCharacterBuildSkillsNavigationInstance);
                Assert.True(
                    router.CancelCharacterBuildSkillsNavigation(
                        instance,
                        "visual_retire_failed"));
                Assert.Null(
                    router
                        .PendingCharacterBuildSkillsNavigationInstance);
                Assert.False(
                    router.CancelCharacterBuildSkillsNavigation(
                        instance,
                        "duplicate"));
            }
        }

        [Fact]
        public void DuplicateSkillsReturnArmDoesNotRebindAnAlreadyClosedSkillTask()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var skillCommands =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var skillTask =
                new SkillTask(
                    () => true,
                    delegate(string payload)
                    {
                        skillCommands.Add(
                            ParseWire(payload));
                        return true;
                    }))
            {
                router.SetPanelHost(host);
                router.SetSkillTask(skillTask);
                Assert.True(
                    host.TryOpenPanel(
                        "skills",
                        "{}",
                        null,
                        null));
                Action pump =
                    Assert.Single(pumps);
                pumps.Clear();
                pump();
                string instance =
                    host.ActivePanelInstanceId;
                skillTask.EnrichPanelInitData(
                    "{\"view\":\"manage\",\"source\":\"nativehud\","
                    + "\"canReturnCharacterBuild\":true}",
                    instance);
                skillTask.BindPanelInstance(
                    instance);

                Assert.True(
                    router
                        .TryArmSkillsCharacterBuildNavigation(
                            instance));
                Assert.True(
                    skillTask
                        .HandleAuthoritativePanelClosed(
                            instance));
                Assert.False(
                    router
                        .TryArmSkillsCharacterBuildNavigation(
                            instance));

                JObject cleanup =
                    Assert.Single(
                        skillCommands);
                skillTask.HandleFlashResponse(
                    new JObject
                    {
                        ["task"] = "skill_response",
                        ["callId"] =
                            cleanup.Value<int>("callId"),
                        ["success"] = true,
                        ["v"] = 1,
                        ["changed"] = false,
                        ["revision"] = 12
                    },
                    null);
                Assert.True(
                    skillTask.IsClosedAndSettled);
                router.CancelAllPanelNavigationIntents(
                    "duplicate_after_close");
                Assert.False(
                    router
                        .TryArmSkillsCharacterBuildNavigation(
                            instance));
                Assert.True(
                    skillTask.IsClosedAndSettled);
            }
        }

        [Fact]
        public async System.Threading.Tasks.Task
            CancelAllIsLinearizationBarrierForSkillsReturnToNativePreflight()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var skillCommands =
                new List<JObject>();
            var gameCommands =
                new List<string>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var skillTask =
                new SkillTask(
                    () => true,
                    delegate(string payload)
                    {
                        skillCommands.Add(
                            ParseWire(payload));
                        return true;
                    }))
            using (var entered =
                new System.Threading.ManualResetEventSlim(
                    false))
            using (var release =
                new System.Threading.ManualResetEventSlim(
                    false))
            {
                router.SetPanelHost(host);
                router.SetSkillTask(skillTask);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(payload);
                        return true;
                    });
                Assert.True(
                    host.TryOpenPanel(
                        "skills",
                        "{}",
                        null,
                        null));
                Action pump =
                    Assert.Single(pumps);
                pumps.Clear();
                pump();
                string instance =
                    host.ActivePanelInstanceId;
                skillTask.EnrichPanelInitData(
                    "{\"view\":\"manage\",\"source\":\"nativehud\","
                    + "\"canReturnCharacterBuild\":true}",
                    instance);
                skillTask.BindPanelInstance(
                    instance);
                Assert.True(
                    router
                        .TryArmSkillsCharacterBuildNavigation(
                            instance));
                Assert.True(
                    skillTask
                        .HandleAuthoritativePanelClosed(
                            instance));
                JObject cleanup =
                    Assert.Single(
                        skillCommands);
                skillTask.HandleFlashResponse(
                    new JObject
                    {
                        ["task"] = "skill_response",
                        ["callId"] =
                            cleanup.Value<int>("callId"),
                        ["success"] = true,
                        ["v"] = 1,
                        ["changed"] = false,
                        ["revision"] = 12
                    },
                    null);
                Assert.True(
                    host.TryClosePanelExact(
                        "skills",
                        instance,
                        null));
                pump =
                    Assert.Single(pumps);
                pumps.Clear();
                pump();
                Assert.True(
                    skillTask.IsClosedAndSettled);
                Assert.True(
                    host.IsIdleForTrackedOpen);

                router
                    .SetBeforeSkillsCharacterBuildNavigationConsumeForTests(
                        delegate
                        {
                            entered.Set();
                            Assert.True(
                                release.Wait(
                                    TimeSpan.FromSeconds(
                                        2)));
                        });
                System.Threading.Tasks.Task<bool>
                    completion =
                        System.Threading.Tasks.Task.Run(
                            delegate
                            {
                                return router
                                    .TryCompleteSkillsCharacterBuildNavigation();
                            });
                Assert.True(
                    entered.Wait(
                        TimeSpan.FromSeconds(
                            2)));
                System.Threading.Tasks.Task cancellation =
                    System.Threading.Tasks.Task.Run(
                        delegate
                        {
                            router
                                .CancelAllPanelNavigationIntents(
                                    "race_test");
                        });
                release.Set();
                await System.Threading.Tasks.Task
                    .WhenAll(
                        completion,
                        cancellation)
                    .WaitAsync(
                        TimeSpan.FromSeconds(
                            3));

                Assert.True(
                    await completion);
                Assert.False(
                    router
                        .CancelPendingNativeEquipmentBuildOpenIntent(
                            "probe"));
                Assert.Null(
                    host.ActivePanelName);
                Assert.Empty(pumps);
            }
        }

        [Fact]
        public void CharacterBuildSkillsNavigation_VisualNotIdleCancelsWithoutConsumingDeferredOpen()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            var flash = new List<string>();
            var gameCommands = new List<string>();
            using (var task = new CharacterBuildTask(
                delegate(string payload)
                {
                    flash.Add(payload.TrimEnd('\0'));
                    return true;
                }))
            {
                router.SetCharacterBuildTask(task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(payload);
                        return true;
                    });
                bool? completionConsumed = null;
                task.SetCoordinatorSettled(delegate
                {
                    completionConsumed =
                        router
                            .TryCompleteCharacterBuildSkillsNavigation();
                });

                string instance = OpenFallbackBuild(router);
                Assert.True(task.BindPanelInstance(instance));
                PrimeCharacterBuild(task, instance, 9);
                FinalizeCharacterBuild(task, instance, 9);
                gameCommands.Clear();

                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.True(
                    task.BeginNormalCloseBarrier(instance));
                Assert.True(
                    task.ContinueDetachRecoveryAfterVisualRetired(0));
                JObject recovery = JObject.Parse(
                    flash[flash.Count - 1]);
                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(recovery, 9),
                    null);

                Assert.False(completionConsumed);
                Assert.Null(
                    router
                        .PendingCharacterBuildSkillsNavigationInstance);
                Assert.Empty(gameCommands);
                Assert.Equal(
                    "workbench",
                    router.ActiveFallbackPanelName);
            }
        }

        [Fact]
        public void CharacterBuildSkillsNavigation_CancelledAtAtomicConsumeDoesNotClaimNavigation()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            var flash = new List<string>();
            var gameCommands = new List<string>();
            using (var task = new CharacterBuildTask(
                delegate(string payload)
                {
                    flash.Add(payload.TrimEnd('\0'));
                    return true;
                }))
            {
                router.SetCharacterBuildTask(task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(payload);
                        return true;
                    });
                bool? completionConsumed = null;
                task.SetCoordinatorSettled(delegate
                {
                    completionConsumed =
                        router
                            .TryCompleteCharacterBuildSkillsNavigation();
                });

                string instance = OpenFallbackBuild(router);
                Assert.True(task.BindPanelInstance(instance));
                PrimeCharacterBuild(task, instance, 9);
                FinalizeCharacterBuild(task, instance, 9);
                gameCommands.Clear();

                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.True(
                    task.BeginNormalCloseBarrier(instance));
                router.ClearFallbackPanelInstance();
                Assert.True(
                    task.ContinueDetachRecoveryAfterVisualRetired(0));
                router.SetBeforeCharacterBuildSkillsNavigationConsumeForTests(
                    delegate
                    {
                        Assert.True(
                            router.CancelCharacterBuildSkillsNavigation(
                                instance,
                                "atomic_consume_race"));
                    });

                JObject recovery = JObject.Parse(
                    flash[flash.Count - 1]);
                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(recovery, 9),
                    null);

                Assert.False(completionConsumed);
                Assert.Null(
                    router
                        .PendingCharacterBuildSkillsNavigationInstance);
                Assert.Empty(gameCommands);
                Assert.Null(
                    router.ActiveFallbackPanelName);
            }
        }

        [Fact]
        public void CharacterBuildSkillsNavigation_PreflightAdmissionFailureReportsOnce()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var flash = new List<string>();
            var gameCommands = new List<JObject>();
            var pumps = new Queue<Action>();
            using (var task = new CharacterBuildTask(
                delegate(string payload)
                {
                    flash.Add(payload.TrimEnd('\0'));
                    return true;
                }))
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                router.SetCharacterBuildTask(task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(ParseWire(payload));
                        return true;
                    });
                bool? completionConsumed = null;
                task.SetCoordinatorSettled(delegate
                {
                    completionConsumed =
                        router
                            .TryCompleteCharacterBuildSkillsNavigation();
                });

                string instance =
                    OpenFallbackBuild(router);
                Assert.True(
                    task.BindPanelInstance(instance));
                PrimeCharacterBuild(task, instance, 9);
                FinalizeCharacterBuild(task, instance, 9);
                capture.Posts.Clear();
                gameCommands.Clear();
                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.True(
                    task.BeginNormalCloseBarrier(instance));
                router.ClearFallbackPanelInstance();
                Assert.True(
                    task.ContinueDetachRecoveryAfterVisualRetired(
                        0));

                router.SetPanelHost(host);
                Assert.True(
                    host.TryAcquireIdleFence(
                        "skill.preflight.baseline"));
                JObject recovery =
                    JObject.Parse(
                        flash[flash.Count - 1]);
                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.True(completionConsumed);
                Assert.Empty(gameCommands);
                JObject toast =
                    JObject.Parse(
                        Assert.Single(
                            capture.Posts));
                Assert.Equal(
                    "toast",
                    toast.Value<string>("type"));
                Assert.Contains(
                    "技能面板未打开",
                    toast.Value<string>("text"));
                Assert.True(
                    host.ReleaseIdleFenceExact(
                        "skill.preflight.baseline"));
            }
        }

        [Fact]
        public void CharacterBuildSkillsNavigation_ConsumedHostRejectionRollsBackOnce()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps = new Queue<Action>();
            var flash = new List<string>();
            var gameCommands = new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var task = new CharacterBuildTask(
                delegate(string payload)
                {
                    flash.Add(payload.TrimEnd('\0'));
                    return true;
                }))
            {
                router.SetPanelHost(host);
                router.SetCharacterBuildTask(task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(
                            ParseWire(payload));
                        return true;
                    });
                task.SetCoordinatorSettled(delegate
                {
                    router
                        .TryCompleteCharacterBuildSkillsNavigation();
                });
                router.RequestOpenPanel(
                    "workbench",
                    "agent_control",
                    null,
                    null,
                    null,
                    null,
                    null,
                    "{\"profile\":\"battlebox\",\"view\":\"build\"}");
                Action pump =
                    Assert.Single(pumps);
                pumps.Clear();
                pump();
                string instance =
                    host.ActivePanelInstanceId;
                Assert.True(
                    task.BindPanelInstance(
                        instance));
                PrimeCharacterBuild(
                    task,
                    instance,
                    9);
                FinalizeCharacterBuild(
                    task,
                    instance,
                    9);
                capture.Posts.Clear();
                gameCommands.Clear();

                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.True(
                    task.BeginNormalCloseBarrier(
                        instance));
                Assert.True(
                    task.ContinueDetachRecoveryAfterVisualRetired(
                        0));
                Assert.True(
                    host.TryClosePanelExact(
                        "workbench",
                        instance,
                        null));
                pump =
                    Assert.Single(pumps);
                pumps.Clear();
                pump();
                JObject recovery =
                    JObject.Parse(
                        flash[flash.Count - 1]);
                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                JObject skillPreflight =
                    Assert.Single(
                        gameCommands,
                        command =>
                            command.Value<string>("action")
                                == "skillPanelOpen");
                Assert.True(
                    host.TryAcquireIdleFence(
                        "skill.request.reject"));
                Assert.True(
                    host.ReleaseIdleFenceExact(
                        "skill.request.reject"));
                RequestNativeSkillManage(
                    router,
                    skillPreflight.Value<string>(
                        "openRequestId"));

                Assert.Single(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.Empty(
                    capture.Posts);
                Assert.False(
                    router.CancelPendingSkillOpenIntent(
                        "probe"));
                Assert.True(
                    router.CancelPendingNativeEquipmentBuildOpenIntent(
                        "test_cleanup"));
            }
        }

        [Fact]
        public void CharacterBuildSkillTimeoutCannotRollbackOverNewNotchIntent()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var flash = new List<string>();
            var gameCommands =
                new System.Collections.Concurrent
                    .ConcurrentQueue<JObject>();
            using (var task = new CharacterBuildTask(
                delegate(string payload)
                {
                    flash.Add(payload.TrimEnd('\0'));
                    return true;
                }))
            {
                router.SetCharacterBuildTask(task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Enqueue(
                            ParseWire(payload));
                        return true;
                    });
                task.SetCoordinatorSettled(delegate
                {
                    router
                        .TryCompleteCharacterBuildSkillsNavigation();
                });
                router.SkillOpenTimeoutMs =
                    30;

                string instance =
                    OpenFallbackBuild(router);
                Assert.True(
                    task.BindPanelInstance(instance));
                PrimeCharacterBuild(task, instance, 9);
                FinalizeCharacterBuild(task, instance, 9);
                capture.Posts.Clear();
                while (gameCommands.TryDequeue(
                    out JObject ignored))
                {
                }
                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.True(
                    task.BeginNormalCloseBarrier(instance));
                router.ClearFallbackPanelInstance();
                Assert.True(
                    task.ContinueDetachRecoveryAfterVisualRetired(
                        0));
                router.SetAfterSkillOpenTimeoutClearedForTests(
                    delegate
                    {
                        router
                            .SetAfterSkillOpenTimeoutClearedForTests(
                                null);
                        router.SkillOpenTimeoutMs =
                            1000;
                        router.Dispatch(
                            "SKILLS");
                    });
                JObject recovery =
                    JObject.Parse(
                        flash[flash.Count - 1]);
                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.True(
                    System.Threading.SpinWait.SpinUntil(
                        delegate
                        {
                            return gameCommands
                                .Count(command =>
                                    command.Value<string>("action")
                                        == "skillPanelOpen")
                                == 2;
                        },
                        2000));
                JObject latest =
                    gameCommands
                        .Where(command =>
                            command.Value<string>("action")
                                == "skillPanelOpen")
                        .Last();
                Assert.DoesNotContain(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.Empty(
                    capture.Posts);

                RequestNativeSkillManage(
                    router,
                    latest.Value<string>(
                        "openRequestId"));
                JObject opened =
                    JObject.Parse(
                        Assert.Single(
                            capture.Posts));
                Assert.Equal(
                    "skills",
                    opened.Value<string>("panel"));
            }
        }

        [Fact]
        public void DirectNativeIntentSupersedesOlderArmedForwardNavigation()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var flash = new List<string>();
            var gameCommands = new List<JObject>();
            using (var task = new CharacterBuildTask(
                delegate(string payload)
                {
                    flash.Add(payload.TrimEnd('\0'));
                    return true;
                }))
            {
                router.SetCharacterBuildTask(task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(ParseWire(payload));
                        return true;
                    });
                bool? completionConsumed = null;
                task.SetCoordinatorSettled(delegate
                {
                    completionConsumed =
                        router
                            .TryCompleteCharacterBuildSkillsNavigation();
                });

                string instance =
                    OpenFallbackBuild(router);
                Assert.True(
                    task.BindPanelInstance(instance));
                PrimeCharacterBuild(task, instance, 9);
                FinalizeCharacterBuild(task, instance, 9);
                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.True(
                    task.BeginNormalCloseBarrier(instance));
                router.ClearFallbackPanelInstance();
                Assert.True(
                    task.ContinueDetachRecoveryAfterVisualRetired(
                        0));

                router.Dispatch("EQUIP_UI");
                Assert.Null(
                    router
                        .PendingCharacterBuildSkillsNavigationInstance);
                JObject recovery =
                    JObject.Parse(
                        flash[flash.Count - 1]);
                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.False(completionConsumed);
                Assert.Single(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.DoesNotContain(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "skillPanelOpen");
                router.CancelPendingNativeEquipmentBuildOpenIntent(
                    "test_cleanup");
            }
        }

        [Fact]
        public void DirectSkillsIntentSupersedesOlderArmedReverseNavigation()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps = new Queue<Action>();
            var skillCommands = new List<JObject>();
            var gameCommands = new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var skillTask =
                new SkillTask(
                    () => true,
                    delegate(string payload)
                    {
                        skillCommands.Add(
                            ParseWire(payload));
                        return true;
                    }))
            {
                router.SetPanelHost(host);
                router.SetSkillTask(skillTask);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(
                            ParseWire(payload));
                        return true;
                    });
                Assert.True(
                    host.TryOpenPanel(
                        "skills",
                        "{}",
                        null,
                        null));
                Action pump =
                    Assert.Single(pumps);
                pumps.Clear();
                pump();
                string instance =
                    host.ActivePanelInstanceId;
                skillTask.EnrichPanelInitData(
                    "{\"view\":\"manage\",\"source\":\"nativehud\","
                    + "\"canReturnCharacterBuild\":true}",
                    instance);
                skillTask.BindPanelInstance(
                    instance);
                Assert.True(
                    router
                        .TryArmSkillsCharacterBuildNavigation(
                            instance));
                Assert.True(
                    skillTask
                        .HandleAuthoritativePanelClosed(
                            instance));
                JObject cleanup =
                    Assert.Single(
                        skillCommands);
                Assert.True(
                    host.TryClosePanelExact(
                        "skills",
                        instance,
                        null));
                pump =
                    Assert.Single(pumps);
                pumps.Clear();
                pump();

                router.Dispatch("SKILLS");
                Assert.Null(
                    router
                        .PendingSkillsCharacterBuildNavigationInstance);
                skillTask.HandleFlashResponse(
                    new JObject
                    {
                        ["task"] =
                            "skill_response",
                        ["callId"] =
                            cleanup.Value<int>("callId"),
                        ["success"] = true,
                        ["v"] = 1,
                        ["changed"] = false,
                        ["revision"] = 12
                    },
                    null);

                Assert.False(
                    router
                        .TryCompleteSkillsCharacterBuildNavigation());
                Assert.Single(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "skillPanelOpen");
                Assert.DoesNotContain(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                router.CancelPendingSkillOpenIntent(
                    "test_cleanup");
            }
        }

        [Theory]
        [InlineData("dormitory", "{\"profile\":\"warehouse\",\"view\":\"tuning\"}")]
        [InlineData("dormitory", "{\"profile\":\"warehouse\",\"view\":\"unknown\"}")]
        public void RequestOpenPanel_WorkbenchRejectsInvalidTuningProfileOrUnknownView(string source, string extras)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel("workbench", source, null, null, null, null, null, extras);

            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void RequestOpenPanel_Unknown_NoPost()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("nonexistent", "src", null);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void RequestOpenPanel_Loot_RejectsGenericRouterBypass()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel("loot", "map_chest", null, null, null, null, null,
                "{\"v\":1,\"chestSessionId\":\"chest.session.1\"," +
                "\"lootContainerId\":\"loot.container.1\",\"containerEpoch\":1," +
                "\"openAttemptSeq\":1,\"displayName\":\"装备箱\"," +
                "\"capacity\":8,\"columns\":4}");

            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Fact]
        public void RequestOpenPanel_SkillsTrainer_RebuildsStrictRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("skills", "world_skill_trainer", null, null, null, null, null,
                "{\"view\":\"trainer\",\"trainerSession\":\"trainer.session.7\"}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"skills\"", c.Posts[0]);
            Assert.Contains("\"source\":\"world_skill_trainer\"", c.Posts[0]);
            Assert.Contains("\"view\":\"trainer\"", c.Posts[0]);
            Assert.Contains("\"trainerSession\":\"trainer.session.7\"", c.Posts[0]);
            Assert.DoesNotContain("\"openRequestId\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_SkillsTrainerRejectsUntrustedOrManageSource()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel(
                "skills",
                "untrusted_source",
                null,
                null,
                null,
                null,
                null,
                "{\"view\":\"trainer\",\"trainerSession\":\"trainer.session.7\"}");
            r.RequestOpenPanel(
                "skills",
                "nativehud",
                null,
                null,
                null,
                null,
                null,
                "{\"view\":\"trainer\",\"trainerSession\":\"trainer.session.8\"}",
                "skill.open.foreign");
            r.RequestOpenPanel(
                "skills",
                "world_skill_trainer",
                null,
                null,
                null,
                null,
                null,
                "{\"view\":\"manage\"}");

            Assert.Empty(c.Posts);
        }

        [Fact]
        public void SkillsButton_WhenSocketPreflightFails_DoesNotOpenEmptyPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("SKILLS");
            Assert.Single(c.Posts);
            Assert.Contains("稍后重试", c.Posts[0]);
            Assert.DoesNotContain("旧物品界面", c.Posts[0]);
            Assert.DoesNotContain("\"cmd\":\"open\"", c.Posts[0]);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void SkillsReturnCapability_IsAbsentFromNotchAndTrainerOrigins()
        {
            Capture notch = new Capture();
            LauncherCommandRouter notchRouter =
                MakeRouter(notch);
            using (var notchTask = new SkillTask(
                () => true,
                _ => true))
            {
                notchRouter.SetSkillTask(
                    notchTask);
                string notchInstance =
                    OpenNativeSkillManage(
                        notchRouter);
                Assert.False(
                    notchRouter
                        .TryArmSkillsCharacterBuildNavigation(
                            notchInstance));
            }

            Capture trainer = new Capture();
            LauncherCommandRouter trainerRouter =
                MakeRouter(trainer);
            using (var trainerTask = new SkillTask(
                () => true,
                _ => true))
            {
                trainerRouter.SetSkillTask(
                    trainerTask);
                RequestWorldSkillTrainer(
                    trainerRouter,
                    "trainer.return.absent");
                string trainerInstance =
                    trainerRouter
                        .ActiveFallbackPanelInstanceId;
                Assert.False(
                    string.IsNullOrEmpty(
                        trainerInstance));
                Assert.False(
                    trainerRouter
                        .TryArmSkillsCharacterBuildNavigation(
                            trainerInstance));
            }
        }

        [Fact]
        public void SkillsButton_SendTrueWaitsForPanelRequestAndTimesOutWithoutOpening()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(value => { commands.Add(value); return true; });
            r.SkillOpenTimeoutMs = 20;

            r.Dispatch("SKILLS");

            Assert.Single(commands);
            Assert.Contains("skillPanelOpen", commands[0]);
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.True(System.Threading.SpinWait.SpinUntil(() => c.Posts.Count == 1, 2000));
            Assert.Contains("技能服务未就绪", c.Posts[0]);
            Assert.DoesNotContain("\"cmd\":\"open\"", c.Posts[0]);

            RequestNativeSkillManage(
                r,
                ReadSkillOpenRequestId(
                    commands[0]));

            Assert.Single(c.Posts);
            Assert.Null(
                r.ActiveFallbackPanelName);
        }

        [Fact]
        public void SkillsButton_LegacyNonceLessManageIsRejectedWithoutConsumingExactPreflight()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            string openRequestId =
                BeginNativeSkillOpen(r);

            RequestNativeSkillManage(
                r,
                null);

            Assert.Empty(c.Posts);
            Assert.Null(
                r.ActiveFallbackPanelName);

            RequestNativeSkillManage(
                r,
                openRequestId);

            Assert.Single(c.Posts);
            Assert.Contains(
                "\"panel\":\"skills\"",
                c.Posts[0]);
            Assert.Equal(
                "skills",
                r.ActiveFallbackPanelName);
        }

        [Fact]
        public void SkillsButton_ReadyPanelRequestOpensOnceAndCancelsTimeoutToast()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            string command =
                null;
            r.SetGameCommandSenderForTests(
                value =>
                {
                    command =
                        value;
                    return true;
                });
            r.SkillOpenTimeoutMs = 40;

            r.Dispatch("SKILLS");
            Assert.Empty(c.Posts);
            RequestNativeSkillManage(
                r,
                ReadSkillOpenRequestId(command));
            System.Threading.Thread.Sleep(100);

            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"skills\"", c.Posts[0]);
            Assert.DoesNotContain("技能服务未就绪", c.Posts[0]);
        }

        [Fact]
        public void SkillsButton_AcceptedManageRejectsLateTrainerAndCleansItsSession()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            using (var task = new SkillTask(
                () => true,
                value =>
                {
                    sent.Add(ParseWire(value));
                    return true;
                }))
            {
                r.SetSkillTask(task);
                RequestNativeSkillManage(
                    r,
                    BeginNativeSkillOpen(r));
                string manageInstance =
                    r.ActiveFallbackPanelInstanceId;
                Assert.False(
                    string.IsNullOrEmpty(manageInstance));
                Assert.Single(c.Posts);
                JObject initialCleanup =
                    Assert.Single(sent);
                Assert.Null(
                    initialCleanup["trainerSession"]);
                task.HandleFlashResponse(
                    SkillCleanupAck(
                        initialCleanup.Value<int>(
                            "callId"),
                        12),
                    null);
                sent.Clear();

                RequestWorldSkillTrainer(
                    r,
                    "trainer.late.after.manage");

                Assert.Single(c.Posts);
                Assert.Equal(
                    manageInstance,
                    r.ActiveFallbackPanelInstanceId);
                JObject cleanup =
                    Assert.Single(sent);
                Assert.Equal(
                    "skillPanelClose",
                    cleanup.Value<string>("action"));
                Assert.Equal(
                    "trainer.late.after.manage",
                    cleanup.Value<string>(
                        "trainerSession"));
            }
        }

        [Fact]
        public void SkillsButton_CompetingPanelCancelsExactResponse()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            string openRequestId =
                BeginNativeSkillOpen(r);

            r.RequestOpenPanel(
                "map",
                "competing_test",
                null);
            Assert.Equal(
                "map",
                r.ActiveFallbackPanelName);
            Assert.Single(c.Posts);

            RequestNativeSkillManage(
                r,
                openRequestId);

            Assert.Single(c.Posts);
            Assert.Equal(
                "map",
                r.ActiveFallbackPanelName);
        }

        [Fact]
        public void SkillsButton_TrackedReservationCycleInvalidatesIdleAdmission()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var pumps =
                new Queue<Action>();
            string skillCommand =
                null;
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                r.SetPanelHost(host);
                r.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        JObject command =
                            ParseWire(payload);
                        if (command.Value<string>("action")
                            == "skillPanelOpen")
                        {
                            skillCommand =
                                payload;
                        }
                        return true;
                    });
                r.Dispatch("SKILLS");
                Assert.False(
                    string.IsNullOrEmpty(
                        skillCommand));
                Assert.True(
                    host.TryOpenTrackedPanel(
                        "loot",
                        "{}",
                        "panel.loot.skill-race",
                        delegate { return false; },
                        null));
                Action pump =
                    Assert.Single(pumps);
                pumps.Clear();
                pump();
                Assert.True(
                    host.IsIdleForTrackedOpen);

                RequestNativeSkillManage(
                    r,
                    ReadSkillOpenRequestId(
                        skillCommand));

                Assert.False(
                    host.IsPanelOpen);
                Assert.Empty(pumps);
                Assert.Empty(c.Posts);
            }
        }

        [Fact]
        public void SkillsButton_WebNavigationCancellationRejectsLateResponse()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            string openRequestId =
                BeginNativeSkillOpen(r);

            Assert.True(
                r.CancelPendingSkillOpenIntent(
                    "web_navigation"));
            RequestNativeSkillManage(
                r,
                openRequestId);

            Assert.Empty(c.Posts);
            Assert.Null(
                r.ActiveFallbackPanelName);
        }

        [Fact]
        public void SkillsButton_SynchronousPanelRequestDuringSendCannotInstallStaleTimeout()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.SkillOpenTimeoutMs = 20;
            r.SetGameCommandSenderForTests(value =>
            {
                if (value.Contains("skillPanelOpen"))
                {
                    RequestNativeSkillManage(
                        r,
                        ReadSkillOpenRequestId(
                            value));
                }
                return true;
            });

            r.Dispatch("SKILLS");
            System.Threading.Thread.Sleep(80);

            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"skills\"", c.Posts[0]);
            Assert.DoesNotContain("技能服务未就绪", c.Posts[0]);
        }

        [Fact]
        public void SkillsButton_SynchronousAckFollowedBySendFalseDoesNotReportFailure()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.SkillOpenTimeoutMs = 40;
            r.SetGameCommandSenderForTests(
                delegate(string value)
                {
                    JObject command =
                        ParseWire(value);
                    if (command.Value<string>("action")
                        == "skillPanelOpen")
                    {
                        RequestNativeSkillManage(
                            r,
                            command.Value<string>(
                                "openRequestId"));
                        return false;
                    }
                    return true;
                });

            r.Dispatch("SKILLS");
            System.Threading.Thread.Sleep(100);

            JObject opened =
                JObject.Parse(
                    Assert.Single(c.Posts));
            Assert.Equal(
                "skills",
                opened.Value<string>("panel"));
            Assert.DoesNotContain(
                "toast",
                c.Posts[0]);
        }

        [Theory]
        [InlineData("{\"view\":\"trainer\"}")]
        [InlineData("{\"view\":\"manage\",\"trainerSession\":\"trainer.one\"}")]
        [InlineData("{\"view\":\"trainer\",\"trainerSession\":\"bad token\"}")]
        [InlineData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.one\",\"catalog\":[]}")]
        public void RequestOpenPanel_SkillsRejectsMalformedOrRawExtras(string extras)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("skills", "world", null, null, null, null, null, extras);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void RequestOpenPanel_SecondTrainerWhileSkillsActiveCannotReplaceFirstContext()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            RequestWorldSkillTrainer(
                r,
                "trainer.a");
            RequestWorldSkillTrainer(
                r,
                "trainer.b");
            Assert.Single(c.Posts);
            var first = Newtonsoft.Json.Linq.JObject.Parse(c.Posts[0]);
            Assert.Equal("trainer.a", (string)first["initData"]["trainerSession"]);
        }

        [Fact]
        public void SkillsTrainerManageRoundTrip_PreservesFocusButKeepsCapabilityInsideHost()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                RequestWorldSkillTrainer(
                    r,
                    "trainer.switch");
                string trainerInstance = r.ActiveFallbackPanelInstanceId;
                task.BindPanelInstance(trainerInstance);

                Assert.True(r.RebindSkillsToManage(trainerInstance, "闪现"));
                Assert.Equal(2, c.Posts.Count);
                JObject manage = JObject.Parse(c.Posts[1]);
                Assert.Equal("manage", (string)manage["initData"]["view"]);
                Assert.Equal("闪现", (string)manage["initData"]["focusSkillKey"]);
                Assert.True((bool)manage["initData"]["canReturnTrainer"]);
                Assert.Null(manage["initData"]["trainerSession"]);
                Assert.NotEqual(trainerInstance, (string)manage["panelInstanceId"]);
                Assert.Empty(sent); // 返回凭据只暂存在 Host；切换本身不提前清理。
                Assert.False(r.RebindSkillsToManage(trainerInstance, "闪现"));
                Assert.Equal(2, c.Posts.Count);

                string manageInstance = (string)manage["panelInstanceId"];
                task.BindPanelInstance(manageInstance);
                Assert.True(r.RebindSkillsToTrainer(manageInstance, "闪现"));
                Assert.Equal(3, c.Posts.Count);
                JObject trainer = JObject.Parse(c.Posts[2]);
                Assert.Equal("trainer", (string)trainer["initData"]["view"]);
                Assert.Equal("trainer.switch", (string)trainer["initData"]["trainerSession"]);
                Assert.Equal("闪现", (string)trainer["initData"]["focusSkillKey"]);
                Assert.False(r.RebindSkillsToTrainer(manageInstance, "闪现"));
            }
        }

        [Fact]
        public void FallbackSkillsLateTrainerCannotReplaceManageThroughUnknownWriteReconcile()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
                r.SetSkillTask(task);
                task.SetCoordinatorSettled(r.FlushDeferredFallbackSkillRebind);
                OpenNativeSkillManage(r);
                Assert.Single(c.Posts);
                string oldInstance = (string)JObject.Parse(c.Posts[0])["panelInstanceId"];
                task.BindPanelInstance(oldInstance);
                task.HandleFlashResponse(SkillCleanupAck((int)sent[0]["callId"], 12), null);

                JObject write = SkillRequest("equip", "fallback.write");
                write["panelInstanceId"] = oldInstance;
                task.HandleWebRequest("equip", write);
                int writeFid = (int)sent[sent.Count - 1]["callId"];
                RequestWorldSkillTrainer(
                    r,
                    "trainer.new");
                Assert.Single(c.Posts);
                Assert.Equal(oldInstance, r.ActiveFallbackPanelInstanceId);

                task.HandleFlashResponse(SkillError(writeFid, "future_error", 12), null);
                Assert.Equal("needs_reconcile", task.WriteState);
                JObject reconcile = SkillRequest("snapshot", "fallback.reconcile");
                reconcile["panelInstanceId"] = oldInstance;
                reconcile["payload"]["reconcileId"] = "fallback.probe";
                reconcile["payload"]["reconcileAfterCallId"] = "fallback.write";
                task.HandleWebRequest("snapshot", reconcile);
                int reconcileFid = (int)sent[sent.Count - 1]["callId"];
                JObject snapshot = SkillSnapshot(12);
                snapshot["task"] = "skill_response";
                snapshot["callId"] = reconcileFid;
                task.HandleFlashResponse(snapshot, null);
                Assert.Single(c.Posts);
                Assert.Equal(
                    "skillPanelClose",
                    sent[sent.Count - 1]
                        .Value<string>("action"));
                Assert.Equal(
                    "trainer.new",
                    sent[sent.Count - 1]
                        .Value<string>(
                            "trainerSession"));
                task.HandleFlashResponse(SkillCleanupAck((int)sent[sent.Count - 1]["callId"], 12), null);

                Assert.Single(c.Posts);
                Assert.Equal(
                    oldInstance,
                    r.ActiveFallbackPanelInstanceId);
                Assert.Equal(oldInstance, (string)web[web.Count - 1]["panelInstanceId"]);
            }
        }

        [Fact]
        public void FallbackDisconnectClear_AllowsRealRecoveryOpenWhileTaskNeedsReconcile()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                OpenNativeSkillManage(r);
                string oldInstance = r.ActiveFallbackPanelInstanceId;
                task.BindPanelInstance(oldInstance);
                JObject write = SkillRequest("equip", "fallback.disconnect.write");
                write["panelInstanceId"] = oldInstance;
                task.HandleWebRequest("equip", write);
                RequestNativeSkillManage(
                    r,
                    BeginNativeSkillOpen(r));
                Assert.Single(c.Posts);

                task.ClearPending();
                r.ClearFallbackPanelInstance();
                RequestNativeSkillManage(
                    r,
                    BeginNativeSkillOpen(r));

                Assert.Equal(2, c.Posts.Count);
                JObject recovery = JObject.Parse(c.Posts[1]);
                Assert.NotEqual(oldInstance, (string)recovery["panelInstanceId"]);
                Assert.Equal("needs_reconcile", (string)recovery["initData"]["writeState"]);
                Assert.Equal("fallback.disconnect.write", (string)recovery["initData"]["reconcileAfterCallId"]);
            }
        }

        [Fact]
        public void FallbackTrainerSwitchToOtherPanel_ClosesScopedCapabilityBeforeFirstBusinessRequest()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                RequestWorldSkillTrainer(
                    r,
                    "trainer.first");
                Assert.Single(c.Posts);

                r.RequestOpenPanel("map", "switch_test", null);

                Assert.Equal(2, c.Posts.Count);
                Assert.Single(sent);
                Assert.Equal("skillPanelClose", (string)sent[0]["action"]);
                Assert.Equal("trainer.first", (string)sent[0]["trainerSession"]);
            }
        }

        [Fact]
        public void ForceCleanupInFlight_TrainerRequestDowngradesToManageThenRunsScopedCleanup()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                task.RequestTrainerCleanup(null);
                Assert.Single(sent);
                Assert.Null(sent[0]["trainerSession"]);

                RequestWorldSkillTrainer(
                    r,
                    "trainer.candidate.C");
                Assert.Single(c.Posts);
                JObject opened = JObject.Parse(c.Posts[0]);
                Assert.Equal("manage", (string)opened["initData"]["view"]);

                task.HandleFlashResponse(SkillCleanupAck((int)sent[0]["callId"], 12), null);
                Assert.Equal(2, sent.Count);
                Assert.Equal("skillPanelClose", (string)sent[1]["action"]);
                Assert.Equal("trainer.candidate.C", (string)sent[1]["trainerSession"]);
                Assert.False(task.CanOpenTrainer);

                task.HandleFlashResponse(SkillCleanupAck((int)sent[1]["callId"], 12), null);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void EmptyKey_SilentlyIgnored()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("");
            r.Dispatch(null);
            Assert.Empty(c.SentKeys);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void UnknownKey_SilentlyIgnored()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("NONEXISTENT_KEY");
            Assert.Empty(c.SentKeys);
            Assert.Empty(c.Posts);
        }

        private static string OpenFallbackBuild(
            LauncherCommandRouter router)
        {
            router.RequestOpenPanel(
                "workbench",
                "agent_control",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}");
            string instance =
                router.ActiveFallbackPanelInstanceId;
            Assert.False(
                string.IsNullOrEmpty(instance));
            Assert.Equal(
                "workbench",
                router.ActiveFallbackPanelName);
            return instance;
        }

        private static string BeginNativeSkillOpen(
            LauncherCommandRouter router)
        {
            string command =
                null;
            router.SetGameCommandSenderForTests(
                delegate(string value)
                {
                    command =
                        value;
                    return true;
                });
            router.Dispatch("SKILLS");
            Assert.False(
                string.IsNullOrEmpty(command));
            return ReadSkillOpenRequestId(
                command);
        }

        private static string ReadSkillOpenRequestId(
            string command)
        {
            JObject parsed =
                ParseWire(command);
            Assert.Equal(
                "skillPanelOpen",
                parsed.Value<string>("action"));
            string requestId =
                parsed.Value<string>(
                    "openRequestId");
            Assert.False(
                string.IsNullOrEmpty(requestId));
            return requestId;
        }

        private static string ReadWorkbenchOpenRequestId(
            string command)
        {
            JObject parsed =
                ParseWire(command);
            Assert.Equal(
                "openInventoryWorkbench",
                parsed.Value<string>("action"));
            string requestId =
                parsed.Value<string>(
                    "openRequestId");
            Assert.False(
                string.IsNullOrEmpty(requestId));
            return requestId;
        }

        private static void RequestNativeSkillManage(
            LauncherCommandRouter router,
            string openRequestId)
        {
            router.RequestOpenPanel(
                "skills",
                "nativehud",
                null,
                null,
                null,
                null,
                null,
                "{\"view\":\"manage\"}",
                openRequestId);
        }

        private static string OpenNativeSkillManage(
            LauncherCommandRouter router)
        {
            RequestNativeSkillManage(
                router,
                BeginNativeSkillOpen(router));
            string instance =
                router.ActiveFallbackPanelInstanceId;
            Assert.False(
                string.IsNullOrEmpty(instance));
            return instance;
        }

        private static void RequestWorldSkillTrainer(
            LauncherCommandRouter router,
            string trainerSession)
        {
            router.RequestOpenPanel(
                "skills",
                "world_skill_trainer",
                null,
                null,
                null,
                null,
                null,
                "{\"view\":\"trainer\",\"trainerSession\":\""
                + trainerSession + "\"}");
        }

        private static void PrimeCharacterBuild(
            CharacterBuildTask task,
            string panelInstanceId,
            long generation)
        {
            Assert.True(
                task.TryBeginHostAccepted(
                    panelInstanceId,
                    null,
                    "router.build.prime",
                    "snapshot",
                    null,
                    out int backendCallId,
                    out string beginError),
                beginError);
            Assert.True(
                task.TryCompleteSuccess(
                    backendCallId,
                    panelInstanceId,
                    generation,
                    "router.build.prime",
                    "snapshot",
                    0,
                    3,
                    3,
                    5,
                    false,
                    true,
                    null,
                    null,
                    out string completionError),
                completionError);
        }

        private static void FinalizeCharacterBuild(
            CharacterBuildTask task,
            string panelInstanceId,
            long generation)
        {
            Assert.True(
                task.TryBeginHostAccepted(
                    panelInstanceId,
                    generation,
                    "router.build.finalize",
                    "finalize",
                    null,
                    out int backendCallId,
                    out string beginError),
                beginError);
            Assert.True(
                task.TryCompleteSuccess(
                    backendCallId,
                    panelInstanceId,
                    generation,
                    "router.build.finalize",
                    "finalize",
                    1,
                    3,
                    3,
                    5,
                    false,
                    false,
                    true,
                    true,
                    out string completionError),
                completionError);
        }

        private static JObject CharacterBuildRecoveryAck(
            JObject recovery,
            long generation)
        {
            return new JObject
            {
                ["task"] = "loadout_response",
                ["callId"] = recovery.Value<int>("callId"),
                ["v"] = 1,
                ["success"] = true,
                ["command"] = "recoverDetach",
                ["requestCallId"] =
                    recovery.Value<string>("requestCallId"),
                ["panelInstanceId"] =
                    recovery.Value<string>("panelInstanceId"),
                ["writeEpoch"] =
                    recovery.Value<int>("writeEpoch"),
                ["active"] = false,
                ["sessionGeneration"] = generation,
                ["loadoutRevision"] = 3,
                ["liveRevision"] = 3,
                ["liveRefreshDirty"] = false,
                ["drugRevision"] = 5,
                ["recoveryState"] = "settled",
                ["closed"] = true,
                ["pauseReleased"] = true,
                ["persistence"] = new JObject
                {
                    ["success"] = true,
                    ["changed"] = true
                }
            };
        }

        private static JObject SkillRequest(string cmd, string callId)
        {
            JObject payload = new JObject { ["v"] = 1 };
            if (cmd == "snapshot") payload["view"] = "manage";
            else if (cmd == "equip")
            {
                payload["skillKey"] = "闪现"; payload["slot"] = 4; payload["expectedRevision"] = 12;
            }
            return new JObject
            {
                ["type"] = "panel", ["panel"] = "skills", ["domain"] = "skills",
                ["cmd"] = cmd, ["callId"] = callId,
                ["panelInstanceId"] = "fallback.unbound", ["payload"] = payload
            };
        }

        private static JObject SkillError(int callId, string error, int revision)
        {
            return new JObject
            {
                ["task"] = "skill_response", ["callId"] = callId, ["success"] = false,
                ["v"] = 1, ["error"] = error, ["revision"] = revision
            };
        }

        private static JObject SkillCleanupAck(int callId, int revision)
        {
            return new JObject
            {
                ["task"] = "skill_response", ["callId"] = callId, ["success"] = true,
                ["v"] = 1, ["changed"] = false, ["revision"] = revision
            };
        }

        private static JObject SkillSnapshot(int revision)
        {
            var loadout = new JArray();
            for (int slot = 1; slot <= 12; slot++) loadout.Add(new JObject
            {
                ["slot"] = slot, ["skillKey"] = null, ["keyLabel"] = slot.ToString(),
                ["stateHealth"] = "ok", ["writeBlocked"] = false
            });
            return new JObject
            {
                ["success"] = true, ["v"] = 1, ["revision"] = revision, ["view"] = "manage",
                ["player"] = new JObject { ["level"] = 20, ["skillPoints"] = 10, ["easyMode"] = false },
                ["learned"] = new JArray(), ["loadout"] = loadout, ["trainer"] = null,
                ["diagnostics"] = new JArray()
            };
        }

        private static JObject ParseWire(string value) { return JObject.Parse(value.TrimEnd('\0')); }
    }
}
