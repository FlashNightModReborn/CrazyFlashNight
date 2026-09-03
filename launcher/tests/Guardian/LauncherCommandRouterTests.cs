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
    /// Router 单测。panel 打开统一经 PanelHostController（用 pump/closedEventDispatcher
    /// 测试构造器驱动，不创建原生窗口）；PostToWeb fallback 路径已随 useNativeHud=false 分支拆除。
    /// </summary>
    public class LauncherCommandRouterTests
    {
        private class Capture
        {
            public List<Keys> SentKeys = new List<Keys>();
            public List<string> Posts = new List<string>();
            public int Fullscreen, Log, Exit;
        }

        /// <summary>
        /// PanelHostController 测试线束：同步 pump（打开/关闭调用即完成），
        /// 保持旧 fallback 测试的同步断言语义。
        /// </summary>
        private sealed class HostHarness : IDisposable
        {
            public readonly PanelHostController Host;

            public HostHarness(LauncherCommandRouter router)
            {
                Host = new PanelHostController(
                    delegate(Action pump) { pump(); },
                    delegate(Action fire) { fire(); });
                router.SetPanelHost(Host);
            }

            /// <summary>精确关闭当前面板（等价旧 ClearFallbackPanelInstance 的测试语义）。</summary>
            public void CloseCurrent()
            {
                string name = Host.ActivePanelName;
                string instance = Host.ActivePanelInstanceId;
                if (name == null || instance == null) return;
                Assert.True(
                    Host.TryClosePanelExact(name, instance, null));
            }

            /// <summary>最后一次 Host 打开的完整 open payload（initData 已含 enricher 结果）。</summary>
            public JObject LastOpenPayload
            {
                get
                {
                    string raw = Host.LastOpenPayloadForTest;
                    Assert.False(string.IsNullOrEmpty(raw));
                    return JObject.Parse(raw);
                }
            }

            /// <summary>生产接线镜像（Program.cs）：skills initData 由 SkillTask 富化。</summary>
            public void WireSkillsEnricher(SkillTask task)
            {
                Host.SetInitDataEnricher(
                    delegate(string panelName, string initDataJson, string panelInstanceId)
                    {
                        return panelName == "skills"
                            ? task.EnrichPanelInitData(initDataJson, panelInstanceId)
                            : initDataJson;
                    });
            }

            public void Dispose() { Host.Dispose(); }
        }

        private static LauncherCommandRouter MakeRouter(
            Capture c,
            bool preparationNavigationV1 = false,
            Action<string> postObserved = null)
        {
            LauncherCommandRouter router =
                new LauncherCommandRouter(
                socketServer: null,
                onSendKey: k => c.SentKeys.Add(k),
                onToggleFullscreen: () => c.Fullscreen++,
                onToggleLog: () => c.Log++,
                onForceExit: () => c.Exit++,
                postToWeb: s =>
                {
                    c.Posts.Add(s);
                    if (postObserved != null) postObserved(s);
                },
                preparationNavigationV1:
                    preparationNavigationV1);
            return router;
        }

        private static JObject BuildWarlordResumeInitDataForRouterTest()
        {
            JObject state = new JObject
            {
                ["schemaVersion"] = 1,
                ["phase"] = "SECOND_FACTION_ACTION"
            };
            JObject command = new JObject
            {
                ["type"] = "MOVE_OR_ATTACK",
                ["factionId"] = "blue",
                ["pieceIds"] = new JArray("b-12-7"),
                ["originNodeId"] = "Center-Command",
                ["targetNodeId"] = "R-Supply"
            };
            JObject clientContext = new JObject
            {
                ["seed"] = "warlord-router-test",
                ["preset"] = "standard",
                ["difficulty"] = "normal",
                ["mapTheme"] = "desert",
                ["forceWebglFailure"] = false,
                ["aiSeenTransitions"] = new JArray("b-12-7:B-HQ->B-Economy")
            };
            JObject request = new JObject
            {
                ["schema"] = "warlord.as2-battle-request.v1",
                ["sessionId"] = "warlord.router.session.1",
                ["requestId"] = "warlord.router.request.1",
                ["state"] = state.DeepClone(),
                ["command"] = command.DeepClone(),
                ["clientContext"] = clientContext.DeepClone()
            };
            string digest = WarlordBattleTask.Sha256OfToken(request);
            JObject receipt = new JObject
            {
                ["schema"] = "warlord.as2-battle-receipt.v1",
                ["status"] = "accepted",
                ["sessionId"] = "warlord.router.session.1",
                ["requestId"] = "warlord.router.request.1",
                ["inputDigest"] = digest
            };
            JObject resume = new JObject
            {
                ["schema"] = "warlord.as2-resume.v1",
                ["request"] = request,
                ["state"] = state,
                ["command"] = command,
                ["inputDigest"] = digest,
                ["receipt"] = receipt,
                ["clientContext"] = clientContext.DeepClone()
            };
            JObject initData = (JObject)clientContext.DeepClone();
            initData["mode"] = "phase-c-as2";
            initData["source"] = "as2_battle_resume";
            initData["productionWrites"] = false;
            initData["battleAuthority"] = "as2";
            initData["as2BattleSession"] = true;
            initData["resume"] = resume;
            return initData;
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
        public void HELP_OpenPanel_OpensThroughHost()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.Dispatch("HELP");
            Assert.True(harnessR.Host.IsPanelOpen);
            Assert.Equal("help", harnessR.Host.ActivePanelName);
        }

        [Theory]
        [InlineData("help")]
        [InlineData("map")]
        [InlineData("tasks")]
        [InlineData("team")]
        [InlineData("jukebox")]
        [InlineData("settings")]
        public void AgentPanelOpen_UsesNarrowWhitelist(
            string panelName)
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);

            Assert.True(
                router.TryOpenAgentPanel(panelName));

            Assert.Equal(
                panelName,
                harness.Host.ActivePanelName);
            Assert.Matches(
                "^panel_[A-Za-z0-9_-]{24}$",
                harness.Host.ActivePanelInstanceId);
        }

        [Fact]
        public void AgentPanelOpen_SettingsCameraPreview_MapsToExactSettingsView()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using var harness = new HostHarness(router);

            Assert.True(
                router.TryOpenAgentPanel("settings_camera_preview"));

            Assert.Equal("settings", harness.Host.ActivePanelName);
            JObject initData = harness.LastOpenPayload["initData"] as JObject;
            Assert.NotNull(initData);
            Assert.Equal(
                "agent_runtime_settings",
                initData.Value<string>("source"));
            Assert.False(initData.Value<bool>("dev"));
            Assert.Equal(
                "camera_preview",
                initData.Value<string>("initialView"));
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("HELP")]
        [InlineData("settings-camera-preview")]
        [InlineData("skills")]
        [InlineData("workbench")]
        [InlineData("../help")]
        public void AgentPanelOpen_RejectsOutsideWhitelist(
            string panelName)
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);

            Assert.False(
                router.TryOpenAgentPanel(panelName));
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void AgentPanelOpen_MaterialsUsesAuthoritativeMaterialRoute()
        {
            Capture c = new Capture();
            LauncherCommandRouter router = MakeRouter(c);
            var commands = new List<string>();
            router.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(value);
                    return true;
                });

            Assert.True(router.TryOpenAgentPanel("materials"));

            JObject command = JObject.Parse(
                Assert.Single(commands).TrimEnd('\0'));
            Assert.Equal("cmd", (string)command["task"]);
            Assert.Equal("openMaterialUI", (string)command["action"]);
            Assert.Equal(
                command.Value<string>("openRequestId"),
                router.PendingMaterialOpenRequestId);
            Assert.Equal(
                "nativehud_materials",
                router.PendingMaterialOpenOrigin);
        }

        [Fact]
        public void AgentPanelOpen_MaterialsReturnsFalseWhenAuthoritySendFails()
        {
            Capture c = new Capture();
            LauncherCommandRouter router = MakeRouter(c);
            router.SetGameCommandSenderForTests(_ => false);

            Assert.False(router.TryOpenAgentPanel("materials"));
            Assert.Null(router.PendingMaterialOpenRequestId);
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void AgentPanelOpen_MaterialsAcceptsOnlyExactSynchronousAdmission(
            bool senderThrows)
        {
            Capture c = new Capture();
            LauncherCommandRouter router = MakeRouter(c);
            bool echoed = false;
            router.SetGameCommandSenderForTests(
                payload =>
                {
                    JObject command = JObject.Parse(
                        payload.TrimEnd('\0'));
                    if (!echoed
                        && command.Value<string>("action")
                            == "openMaterialUI")
                    {
                        echoed = true;
                        RequestNativeMaterials(
                            router,
                            "crafting",
                            "nativehud_materials",
                            "{\"view\":\"materials\"}",
                            command.Value<string>("openRequestId"));
                    }
                    if (senderThrows)
                        throw new InvalidOperationException(
                            "late sender failure");
                    return false;
                });

            Assert.True(router.TryOpenAgentPanel("materials"));
            Assert.Null(router.PendingMaterialOpenRequestId);
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void AgentPanelOpen_MaterialsDoesNotTreatCancellationAsDispatch(
            bool senderThrows)
        {
            Capture c = new Capture();
            LauncherCommandRouter router = MakeRouter(c);
            router.SetGameCommandSenderForTests(
                _ =>
                {
                    Assert.True(router.CancelPendingMaterialOpenIntent(
                        "concurrent_cancel"));
                    if (senderThrows)
                        throw new InvalidOperationException(
                            "cancelled sender failure");
                    return false;
                });

            Assert.False(router.TryOpenAgentPanel("materials"));
            Assert.Null(router.PendingMaterialOpenRequestId);
        }

        [Theory]
        [InlineData("help")]
        [InlineData("materials")]
        public void AgentPanelOpen_PreservesUnifiedAdmissionGate(
            string panelName)
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            router.SetPanelAdmissionGate(
                () => false);

            Assert.False(
                router.TryOpenAgentPanel(panelName));
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void HostPanelChangedPublishesAfterOpenAndClose()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            var changed =
                new List<(string Name, string Instance)>();
            harness.Host.PanelChanged += (name, instance) =>
                changed.Add((name, instance));

            Assert.True(
                router.TryOpenAgentPanel("help"));
            string instance =
                harness.Host.ActivePanelInstanceId;
            harness.CloseCurrent();

            Assert.Collection(
                changed,
                opened =>
                {
                    Assert.Equal("help", opened.Name);
                    Assert.Equal(
                        instance,
                        opened.Instance);
                },
                retired =>
                {
                    Assert.Null(retired.Name);
                    Assert.Null(retired.Instance);
                });
        }

        [Fact]
        public void HostPanelInstancesUseFreshCspRngOpaqueIds()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);

            Assert.True(
                router.TryOpenAgentPanel("help"));
            string first =
                harness.Host.ActivePanelInstanceId;
            harness.CloseCurrent();
            Assert.True(
                router.TryOpenAgentPanel("map"));
            string second =
                harness.Host.ActivePanelInstanceId;

            Assert.Matches(
                "^panel_[A-Za-z0-9_-]{24}$",
                first);
            Assert.Matches(
                "^panel_[A-Za-z0-9_-]{24}$",
                second);
            Assert.NotEqual(first, second);
        }

        [Fact]
        public void HostPanelChangedFailureDoesNotBreakOpen()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            int healthySubscriberCalls = 0;
            harness.Host.PanelChanged += delegate
            {
                throw new InvalidOperationException(
                    "subscriber failure");
            };
            harness.Host.PanelChanged += delegate
            {
                healthySubscriberCalls++;
            };

            Assert.True(
                router.TryOpenAgentPanel("help"));
            Assert.Equal(
                "help",
                harness.Host.ActivePanelName);
            Assert.Equal(
                1,
                healthySubscriberCalls);
        }

        [Fact]
        public void WAREHOUSE_WebOnlyRoute_UsesBattleboxStorageWithoutLegacyCommand()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(value);
                    return true;
                });
            r.Dispatch("WAREHOUSE");
            Assert.True(harnessR.Host.IsPanelOpen);
            JObject open = harnessR.LastOpenPayload;
            Assert.Equal("workbench", (string)open["panel"]);
            Assert.Equal("battlebox", (string)open["initData"]["profile"]);
            Assert.Equal("storage", (string)open["initData"]["view"]);
            Assert.Equal("nativehud", (string)open["initData"]["source"]);
            Assert.DoesNotContain(
                commands,
                payload => payload.Contains(
                    "\"action\":\"warehouse\""));
        }

        [Fact]
        public void WAREHOUSE_DefaultRoute_DoesNotEmitTuningCapabilitySwitch()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);

            r.Dispatch("WAREHOUSE");

            Assert.DoesNotContain("tuningAvailable", harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None));
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
            string openRequestId =
                command.Value<string>(
                    "openRequestId");
            Assert.StartsWith(
                "material.open.",
                openRequestId);
            Assert.Equal(
                openRequestId,
                r.PendingMaterialOpenRequestId);
            Assert.Equal(
                "nativehud_materials",
                r.PendingMaterialOpenOrigin);
            Assert.Empty(c.Posts);
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
            Assert.Null(
                r.PendingMaterialOpenRequestId);
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
            Assert.Null(
                r.PendingMaterialOpenRequestId);
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
            using var harnessR = new HostHarness(r);
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
                harnessR.Host.ActivePanelName);
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
        public void MATERIALS_ExactEchoConsumesOnceAndBuildsFixedInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            var commands =
                new List<JObject>();
            router.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(
                        ParseWire(value));
                    return true;
                });
            router.Dispatch(
                "MATERIALS");
            string openRequestId =
                Assert.Single(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "openMaterialUI")
                .Value<string>(
                    "openRequestId");

            RequestNativeMaterials(
                router,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                openRequestId);

            Assert.Null(
                router.PendingMaterialOpenRequestId);
            Assert.Equal(
                "crafting",
                harness.Host.ActivePanelName);
            JObject opened = harness.LastOpenPayload;
            JObject initData =
                Assert.IsType<JObject>(
                    opened["initData"]);
            Assert.Equal(
                "runtime",
                initData.Value<string>("mode"));
            Assert.Equal(
                "materials",
                initData.Value<string>("view"));
            Assert.Equal(
                "nativehud_materials",
                initData.Value<string>("source"));
            Assert.False(
                initData.Value<bool>("debug"));
            Assert.Null(
                initData["openRequestId"]);

            string openedInstance =
                harness.Host.ActivePanelInstanceId;
            RequestNativeMaterials(
                router,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                openRequestId);
            // 已消费的 nonce 不再打开：仍是同一实例
            Assert.Equal(
                openedInstance,
                harness.Host.ActivePanelInstanceId);
        }

        [Fact]
        public void MATERIALS_MissingNonceWhilePendingRejectsWithoutConsumingThenExactEchoOpens()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            string command =
                null;
            router.SetGameCommandSenderForTests(
                value =>
                {
                    JObject parsed =
                        ParseWire(value);
                    if (parsed.Value<string>("action")
                        == "openMaterialUI")
                    {
                        command =
                            value;
                    }
                    return true;
                });
            router.Dispatch(
                "MATERIALS");
            string openRequestId =
                ParseWire(command)
                    .Value<string>(
                        "openRequestId");

            RequestNativeMaterials(
                router,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                null);

            Assert.Equal(
                openRequestId,
                router.PendingMaterialOpenRequestId);
            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.Contains(
                c.Posts,
                value => value.Contains(
                    "正在打开材料"));

            RequestNativeMaterials(
                router,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                openRequestId);
            Assert.Null(
                router.PendingMaterialOpenRequestId);
            Assert.Equal(
                "crafting",
                harness.Host.ActivePanelName);
        }

        [Fact]
        public void MATERIALS_MissingNonceWhileCharacterBuildIntentIsArmedPreservesExactBuild()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            using (var task =
                new CharacterBuildTask(
                    _ => true))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    _ => true);
                string instance =
                    OpenHostBuild(router, harness);
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
                Assert.True(
                    router
                        .TryArmCharacterBuildPreparationNavigation(
                            instance,
                            LauncherCommandRouter
                                .CharacterBuildPreparationTarget
                                .Materials));

                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    null);

                Assert.Equal(
                    instance,
                    router
                        .PendingCharacterBuildPreparationNavigationInstance);
                Assert.Equal(
                    "materials",
                    router
                        .PendingCharacterBuildPreparationTarget);
                Assert.Equal(
                    "workbench",
                    harness.Host.ActivePanelName);
                Assert.Equal(
                    instance,
                    harness.Host.ActivePanelInstanceId);
                Assert.Contains(
                    capture.Posts,
                    value => value.Contains(
                        "正在打开材料"));
                Assert.True(
                    router
                        .CancelCharacterBuildPreparationNavigation(
                            instance,
                            LauncherCommandRouter
                                .CharacterBuildPreparationTarget
                                .Materials,
                            "test_cleanup"));
            }
        }

        [Fact]
        public void MATERIALS_CompetingPanelCancelsWaitAndLateEchoCannotReplaceWinner()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            string command =
                null;
            router.SetGameCommandSenderForTests(
                value =>
                {
                    JObject parsed =
                        ParseWire(value);
                    if (parsed.Value<string>("action")
                        == "openMaterialUI")
                    {
                        command =
                            value;
                    }
                    return true;
                });
            router.Dispatch(
                "MATERIALS");
            string openRequestId =
                ParseWire(command)
                    .Value<string>(
                        "openRequestId");

            router.RequestOpenPanel(
                "map",
                "competing_test",
                null);
            Assert.Null(
                router.PendingMaterialOpenRequestId);
            Assert.Equal(
                "map",
                harness.Host.ActivePanelName);
            RequestNativeMaterials(
                router,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                openRequestId);

            Assert.Equal(
                "map",
                harness.Host.ActivePanelName);
            Assert.Empty(capture.Posts);
        }

        [Theory]
        [InlineData(
            "crafting",
            "nativehud_materials",
            "{\"view\":\"materials\"}",
            "material.open.wrong")]
        [InlineData(
            "crafting",
            "nativehud_material",
            "{\"view\":\"materials\"}",
            null)]
        [InlineData(
            "crafting",
            "nativehud_materials",
            "{\"view\":\"material\"}",
            null)]
        [InlineData(
            "crafting",
            "nativehud_materials",
            "{\"view\":\"materials\",\"extra\":true}",
            null)]
        [InlineData(
            "skills",
            "nativehud_materials",
            "{\"view\":\"materials\"}",
            null)]
        public void MATERIALS_NearTupleOrNonceCancelsTargetAndLateExactEchoOpensZero(
            string panel,
            string source,
            string initData,
            string replacementNonce)
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            string command =
                null;
            router.SetGameCommandSenderForTests(
                value =>
                {
                    JObject parsed =
                        ParseWire(value);
                    if (parsed.Value<string>("action")
                        == "openMaterialUI")
                    {
                        command =
                            value;
                    }
                    return true;
                });
            router.Dispatch(
                "MATERIALS");
            string openRequestId =
                ParseWire(command)
                    .Value<string>(
                        "openRequestId");

            RequestNativeMaterials(
                router,
                panel,
                source,
                initData,
                replacementNonce
                    ?? openRequestId);
            RequestNativeMaterials(
                router,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                openRequestId);

            Assert.Null(
                router.PendingMaterialOpenRequestId);
            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.DoesNotContain(
                c.Posts,
                value => value.Contains(
                    "\"cmd\":\"open\""));
            Assert.Single(
                c.Posts,
                value => value.Contains(
                    "\"type\":\"toast\""));
        }

        [Fact]
        public void MATERIALS_TimeoutAndCancelAllFenceLateEchoes()
        {
            Capture timeoutCapture =
                new Capture();
            LauncherCommandRouter timeoutRouter =
                MakeRouter(
                    timeoutCapture);
            using var harnessTimeoutRouter = new HostHarness(timeoutRouter);
            timeoutRouter.MaterialPanelOpenTimeoutMs =
                25;
            string timeoutCommand =
                null;
            timeoutRouter.SetGameCommandSenderForTests(
                value =>
                {
                    JObject parsed =
                        ParseWire(value);
                    if (parsed.Value<string>("action")
                        == "openMaterialUI")
                    {
                        timeoutCommand =
                            value;
                    }
                    return true;
                });
            timeoutRouter.Dispatch(
                "MATERIALS");
            string timedOutId =
                ParseWire(timeoutCommand)
                    .Value<string>(
                        "openRequestId");
            Assert.True(
                System.Threading.SpinWait.SpinUntil(
                    () =>
                        timeoutRouter
                            .PendingMaterialOpenRequestId
                        == null,
                    2000));
            RequestNativeMaterials(
                timeoutRouter,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                timedOutId);
            Assert.Null(
                harnessTimeoutRouter.Host.ActivePanelName);
            Assert.Contains(
                timeoutCapture.Posts,
                value => value.Contains(
                    "材料服务未就绪"));

            Capture cancelCapture =
                new Capture();
            LauncherCommandRouter cancelRouter =
                MakeRouter(
                    cancelCapture);
   using var harnessCancelRouter = new HostHarness(cancelRouter);
            cancelRouter.MaterialPanelOpenTimeoutMs =
                25;
            string cancelCommand =
                null;
            cancelRouter.SetGameCommandSenderForTests(
                value =>
                {
                    JObject parsed =
                        ParseWire(value);
                    if (parsed.Value<string>("action")
                        == "openMaterialUI")
                    {
                        cancelCommand =
                            value;
                    }
                    return true;
                });
            cancelRouter.Dispatch(
                "MATERIALS");
            string cancelledId =
                ParseWire(cancelCommand)
                    .Value<string>(
                        "openRequestId");
            cancelRouter.CancelAllPanelNavigationIntents(
                "test_cancel");
            System.Threading.Thread.Sleep(
                80);
            RequestNativeMaterials(
                cancelRouter,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                cancelledId);
            Assert.Null(
                harnessCancelRouter.Host.ActivePanelName);
            Assert.Empty(
                cancelCapture.Posts);
        }

        [Fact]
        public void MATERIALS_AdmissionRevocationConsumesWaitWithoutPauseOrOpen()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            bool admitted =
                true;
            var commands =
                new List<JObject>();
            router.SetPanelAdmissionGate(
                () => admitted);
            router.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(
                        ParseWire(value));
                    return true;
                });
            router.Dispatch(
                "MATERIALS");
            string openRequestId =
                Assert.Single(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "openMaterialUI")
                .Value<string>(
                    "openRequestId");

            admitted =
                false;
            RequestNativeMaterials(
                router,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                openRequestId);

            Assert.Null(
                router.PendingMaterialOpenRequestId);
            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.DoesNotContain(
                commands,
                command =>
                    command.Value<string>("action")
                        == "webPanelPause");
            Assert.Contains(
                c.Posts,
                value => value.Contains(
                    "\"type\":\"toast\""));
        }

        [Fact]
        public void MATERIALS_TrackedReservationCycleInvalidatesCapturedHostAdmission()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            var pumps =
                new Queue<Action>();
            var commands =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                router.SetPanelHost(
                    host);
                router.SetGameCommandSenderForTests(
                    value =>
                    {
                        commands.Add(
                            ParseWire(value));
                        return true;
                    });
                router.Dispatch(
                    "MATERIALS");
                string openRequestId =
                    Assert.Single(
                        commands,
                        command =>
                            command.Value<string>("action")
                                == "openMaterialUI")
                    .Value<string>(
                        "openRequestId");
                Assert.True(
                    host.TryOpenTrackedPanel(
                        "loot",
                        "{}",
                        "panel.loot.material-race",
                        delegate { return false; },
                        null));
                Action pump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                pump();
                Assert.True(
                    host.IsIdleForTrackedOpen);

                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    openRequestId);

                Assert.Null(
                    router.PendingMaterialOpenRequestId);
                Assert.False(
                    host.IsPanelOpen);
                Assert.Empty(
                    pumps);
                Assert.DoesNotContain(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "webPanelPause");
                Assert.Contains(
                    c.Posts,
                    value => value.Contains(
                        "\"type\":\"toast\""));
            }
        }

        [Fact]
        public void ShutdownAdmissionGateRejectsNewBuildMaterialAndWebPanelIngress()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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
                harnessR.Host.ActivePanelName);
        }

        [Fact]
        public void EQUIP_UI_WebOnlyRouteSendsFixedBuildPreflightWithoutLegacyFallback()
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
            Assert.DoesNotContain(
                commands,
                payload => payload.Contains(
                    "\"action\":\"openEquipUI\""));
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    Assert.Single(commands));
            Assert.Equal(6, command.Count);
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
        }

        [Fact]
        public void EQUIP_UI_SendTrueWaitsForExactPanelRequestAndTimesOut()
        {
            Capture c = new Capture();
            using (var postObserved =
                new System.Threading.ManualResetEventSlim(false))
            {
                LauncherCommandRouter r = MakeRouter(
                    c,
                    false,
                    delegate { postObserved.Set(); });
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
                Assert.True(postObserved.Wait(5000));
                Assert.Single(c.Posts);
                Assert.Contains(
                    "装备服务未就绪",
                    c.Posts[0]);
                Assert.DoesNotContain(
                    "\"cmd\":\"open\"",
                    c.Posts[0]);
            }
        }

        [Fact]
        public void EQUIP_UI_ExactAckCancelsTimeoutAndOpensOnce()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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

            JObject opened = harnessR.LastOpenPayload;
            Assert.Equal(
                "workbench",
                (string)opened["panel"]);
            Assert.Equal(
                "build",
                (string)opened["initData"]["view"]);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void EQUIP_UI_SynchronousAckDuringSendCannotLeaveStaleTimeout()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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

            JObject opened = harnessR.LastOpenPayload;
            Assert.Equal(
                "workbench",
                (string)opened["panel"]);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void EQUIP_UI_SynchronousAckFollowedBySendFalseDoesNotReportFailure()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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

            JObject opened = harnessR.LastOpenPayload;
            Assert.Equal(
                "workbench",
                opened.Value<string>("panel"));
            Assert.Empty(c.Posts);
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
            using (var postObserved = new System.Threading.ManualResetEventSlim(false))
            {
                LauncherCommandRouter r = MakeRouter(
                    c,
                    false,
                    delegate { postObserved.Set(); });
                r.NativeEquipmentBuildOpenTimeoutMs = 250;
                var commands = new List<string>();
                r.SetGameCommandSenderForTests(
                    payload =>
                    {
                        commands.Add(payload);
                        return true;
                    });

                r.Dispatch("EQUIP_UI");
                Assert.True(
                    postObserved.Wait(5000));
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
            }
        }

        [Fact]
        public void EQUIP_UI_CompetingPanelRejectsPendingNativeBuildAck()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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

            Assert.Equal(
                "map",
                harnessR.Host.ActivePanelName);
            Assert.Empty(c.Posts);
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
            using var harnessR = new HostHarness(r);
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

            Assert.Equal(
                "map",
                harnessR.Host.ActivePanelName);
            Assert.Empty(c.Posts);

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
            Assert.Empty(c.Posts);
            Assert.Equal(
                "map",
                harnessR.Host.ActivePanelName);
        }

        [Fact]
        public void EQUIP_UI_NearMatchDoesNotConsumePendingExactAck()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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

            JObject opened = harnessR.LastOpenPayload;
            Assert.Equal(
                "workbench",
                (string)opened["panel"]);
        }

        [Fact]
        public void SkillsIntentSupersedesOlderNativeBuildPreflight()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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
            JObject opened = harnessR.LastOpenPayload;
            Assert.Equal(
                "skills",
                opened.Value<string>("panel"));
        }

        [Fact]
        public void NativeBuildIntentSupersedesOlderSkillsPreflight()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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
            JObject opened = harnessR.LastOpenPayload;
            Assert.Equal(
                "workbench",
                opened.Value<string>("panel"));
        }

        [Fact]
        public void NativeStorageRequestCancelsOlderNativeBuildPreflight()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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
                harnessR.Host.ActivePanelInstanceId;
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

            Assert.Equal(
                storageInstance,
                harnessR.Host.ActivePanelInstanceId);
            Assert.Equal(
                "storage",
                harnessR.LastOpenPayload[
                    "initData"].Value<string>("view"));
        }

        [Fact]
        public void CraftingRequest_WhitelistsCategoryAndBuildsRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("crafting", "world_crafting_entry", null, null, null, null, null,
                "{\"category\":\"武器合成\",\"ignored\":\"x\"}");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"crafting\"", open);
            Assert.Contains("\"category\":\"武器合成\"", open);
            Assert.DoesNotContain("ignored", open);
        }

        [Fact]
        public void CraftingRequest_RejectsUnknownCategory()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("crafting", "world_crafting_entry", null, null, null, null, null,
                "{\"category\":\"未知分类\"}");
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void CraftingMaterialsLegacyRequest_BuildsFixedReadOnlyMaterialInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("crafting", "nativehud_materials", null, null, null, null, null,
                "{\"view\":\"materials\"}");

            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"crafting\"", open);
            Assert.Contains("\"view\":\"materials\"", open);
            Assert.Contains("\"source\":\"nativehud_materials\"", open);
            Assert.DoesNotContain("\"category\"", open);
        }

        [Fact]
        public void CraftingMaterialsRequest_RejectsExtraFields()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel(
                "crafting",
                "nativehud_materials",
                null,
                null,
                null,
                null,
                null,
                "{\"view\":\"materials\",\"category\":\"未知分类\",\"ignored\":\"x\"}");

            Assert.Empty(c.Posts);
        }

        [Fact]
        public void HairdresserRequest_UsesExactRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);

            r.RequestOpenPanel(
                "hairdresser",
                "world_hairdresser",
                "ignored-page",
                "ignored-frame",
                "ignored-return-frame",
                "ignored-return-panel",
                "{\"ignored\":true}",
                "{\"ignored\":true}");

            JObject open = harnessR.LastOpenPayload;
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
            Assert.Equal("hairdresser", harnessR.Host.ActivePanelName);
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
        }

        [Fact]
        public void GOBANG_TEST_OpenPanel_IncludesInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.Dispatch("GOBANG_TEST");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"gobang\"", open);
            Assert.Contains("\"initData\"", open);
            Assert.Contains("\"ruleset\":\"casual\"", open);
        }

        [Fact]
        public void BLACKMARKET_TEST_OpenPanel_IsDevShadowOnly()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.Dispatch("BLACKMARKET_TEST");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"blackmarket\"", open);
            Assert.Contains("\"mode\":\"dev\"", open);
            Assert.Contains("\"source\":\"runtime\"", open);
            Assert.Contains("\"shadowOnly\":true", open);
            Assert.DoesNotContain("\"seed\"", open);
            Assert.DoesNotContain("allowExactIdentityLab", open);
        }

        [Fact]
        public void WARLORD_TEST_OpenPanel_IsDeterministicAndReadOnly()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.Dispatch("WARLORD_TEST");
            JObject open = harnessR.LastOpenPayload;
            Assert.Equal("warlord", (string)open["panel"]);
            JObject initData = open["initData"] as JObject;
            Assert.NotNull(initData);
            Assert.Equal("phase-c-as2", (string)initData["mode"]);
            Assert.Equal("runtime", (string)initData["source"]);
            Assert.Equal("warlord-demo-seed-001", (string)initData["seed"]);
            Assert.Equal("standard", (string)initData["preset"]);
            Assert.Equal("normal", (string)initData["difficulty"]);
            Assert.Equal("desert", (string)initData["mapTheme"]);
            Assert.Equal("as2", (string)initData["battleAuthority"]);
            Assert.False((bool)initData["productionWrites"]);
        }

        [Fact]
        public void WarlordResume_DedicatedCapabilityReopensValidatedHostEnvelope()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            JObject resume = BuildWarlordResumeInitDataForRouterTest();

            Assert.True(r.TryOpenWarlordResumePanel(resume));

            Assert.Equal("warlord", harnessR.Host.ActivePanelName);
            JObject open = harnessR.LastOpenPayload;
            JObject initData = open["initData"] as JObject;
            Assert.NotNull(initData);
            Assert.Equal("as2_battle_resume", (string)initData["source"]);
            Assert.True((bool)initData["as2BattleSession"]);
            Assert.Equal("accepted", (string)initData["resume"]["receipt"]["status"]);
            Assert.Equal(
                (string)resume["resume"]["inputDigest"],
                (string)initData["resume"]["inputDigest"]);
        }

        [Fact]
        public void WarlordResume_GenericPanelRequestRemainsUnsupported()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            JObject resume = BuildWarlordResumeInitDataForRouterTest();

            r.RequestOpenPanel(
                "warlord",
                "as2_battle_resume",
                null,
                null,
                null,
                null,
                null,
                resume.ToString(Newtonsoft.Json.Formatting.None));

            Assert.False(harnessR.Host.IsPanelOpen);
        }

        [Fact]
        public void WarlordResume_DedicatedCapabilityRejectsAuthorityDrift()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);

            JObject wrongSource = BuildWarlordResumeInitDataForRouterTest();
            wrongSource["source"] = "as2_request";
            Assert.False(r.TryOpenWarlordResumePanel(wrongSource));

            JObject extraRoot = BuildWarlordResumeInitDataForRouterTest();
            extraRoot["debug"] = true;
            Assert.False(r.TryOpenWarlordResumePanel(extraRoot));

            JObject mismatchedDigest = BuildWarlordResumeInitDataForRouterTest();
            mismatchedDigest["resume"]["receipt"]["inputDigest"] =
                "sha256:" + new string('0', 64);
            Assert.False(r.TryOpenWarlordResumePanel(mismatchedDigest));

            Assert.False(harnessR.Host.IsPanelOpen);
        }

        [Fact]
        public void INTELLIGENCE_TEST_OpenPanel_IncludesFixtureInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.Dispatch("INTELLIGENCE_TEST");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"intelligence\"", open);
            Assert.Contains("\"itemName\":\"资料\"", open);
            Assert.Contains("\"value\":99", open);
            Assert.Contains("\"decryptLevel\":10", open);
        }

        [Fact]
        public void INTELLIGENCE_OpenPanelFallback_UsesRuntimeProdInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.Dispatch("INTELLIGENCE");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"intelligence\"", open);
            Assert.Contains("\"mode\":\"prod\"", open);
            Assert.Contains("\"source\":\"runtime\"", open);
            Assert.Contains("\"debug\":false", open);
            Assert.Equal("intelligence", harnessR.Host.ActivePanelName);
        }

        [Fact]
        public void NewTaskUi_WhenFlashUnavailable_PostsUnavailableToast()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("NEW_TASK_UI");

            Assert.Single(c.Posts);
            Assert.Contains("任务面板暂时不可用", c.Posts[0]);
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
        }

        [Fact]
        public void RequestOpenPanel_Map_RoutesToOpenMapPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("map", "as2_request", "page-1");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"map\"", open);
            Assert.Contains("\"page\":\"page-1\"", open);
            Assert.Contains("\"source\":\"as2_request\"", open);
        }

        [Fact]
        public void RequestOpenPanel_StageSelect_RoutesRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("stage-select", "as2_base_gate", null, "基地门口");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"stage-select\"", open);
            Assert.Contains("\"mode\":\"runtime\"", open);
            Assert.Contains("\"fixture\":\"mixed\"", open);
            Assert.Contains("\"frameLabel\":\"基地门口\"", open);
            Assert.Contains("\"returnFrameLabel\":\"基地门口\"", open);
            Assert.Contains("\"source\":\"as2_base_gate\"", open);
            Assert.Contains("\"debug\":false", open);
        }

        [Fact]
        public void RequestOpenPanel_StageSelect_CarriesExplicitReturnFrame()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("stage-select", "as2_legacy_stage_gate", null, "黑铁会总部", "基地车库");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"frameLabel\":\"黑铁会总部\"", open);
            Assert.Contains("\"returnFrameLabel\":\"基地车库\"", open);
        }

        [Fact]
        public void RequestOpenPanel_Tasks_RoutesToOpenTasksPanelWithInitData()
        {
            // 副本任务（委托任务）入口回归：NPC openWebDungeon 发 panel_request panel="tasks"，
            // 必须开 tasks 面板并透传 initData {view,taskId}。曾因 RequestOpenPanel 无 tasks 分支
            // 静默丢弃（"[Router] RequestOpenPanel unsupported panel=tasks"），NPC 点击无反应。
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("tasks", "npc_dungeon", null, null, null, null, null, "{\"view\":\"dungeon\",\"taskId\":20052}");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"tasks\"", open);
            Assert.Contains("\"view\":\"dungeon\"", open);
            Assert.Contains("\"taskId\":20052", open);
            Assert.Contains("\"source\":\"npc_dungeon\"", open);
        }

        [Fact]
        public void RequestOpenPanel_Team_RoutesToOpenTeamPanelWithInitData()
        {
            // 世界内雇佣入口：NPC openWebHire 发 panel_request panel="team"，必须开 team 面板并
            // 透传 initData {view:"hire",kind,npcId,initialTab}。无 team 分支会静默丢弃（unsupported panel）。
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("team", "npc_hire", null, null, null, null, null, "{\"view\":\"hire\",\"kind\":\"merc\",\"npcId\":\"敌人123\",\"initialTab\":\"mercenary\"}");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"team\"", open);
            Assert.Contains("\"view\":\"hire\"", open);
            Assert.Contains("\"kind\":\"merc\"", open);
            Assert.Contains("\"source\":\"npc_hire\"", open);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchWarehouse_UsesStrictWarehouseProfile()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("workbench", "dormitory", null, null, null, null, null,
                "{\"profile\":\"warehouse\",\"rightContainer\":\"任意容器\"}");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"workbench\"", open);
            Assert.Contains("\"profile\":\"warehouse\"", open);
            Assert.Contains("\"view\":\"storage\"", open);
            Assert.DoesNotContain("tuningAvailable", open);
            Assert.Contains("\"source\":\"dormitory\"", open);
            Assert.DoesNotContain("rightContainer", open);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchUnknownProfile_IsRejected()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("workbench", "dormitory", null, null, null, null, null,
                "{\"profile\":\"仓库\"}");
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchTuning_AllowsNormalEquipmentSource()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("workbench", "nativehud_equipment", null, null, null, null, null,
                "{\"profile\":\"battlebox\",\"view\":\"tuning\",\"ignored\":true}");

            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"view\":\"tuning\"", open);
            Assert.DoesNotContain("tuningAvailable", open);
            Assert.Contains("\"source\":\"nativehud_equipment\"", open);
            Assert.DoesNotContain("ignored", open);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchTuning_AgentControlUsesSameNormalRoute()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("workbench", "agent_control", null, null, null, null, null,
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}");

            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"view\":\"tuning\"", open);
            Assert.DoesNotContain("tuningAvailable", open);
            Assert.Contains("\"source\":\"agent_control\"", open);
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void RequestOpenPanel_WorkbenchBuild_ProjectsStrictPreparationPresentationGate(
            bool preparationNavigationV1)
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(
                    capture,
                    preparationNavigationV1);
            using var harness = new HostHarness(router);

            router.RequestOpenPanel(
                "workbench",
                "agent_control",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}");

            JObject opened =
                harness.LastOpenPayload;
            JObject initData =
                Assert.IsType<JObject>(
                    opened["initData"]);
            Assert.Equal(
                "build",
                initData.Value<string>(
                    "view"));
            if (preparationNavigationV1)
            {
                JToken gate =
                    initData[
                        "preparationNavigationV1"];
                Assert.NotNull(gate);
                Assert.Equal(
                    JTokenType.Boolean,
                    gate.Type);
                Assert.True(
                    gate.Value<bool>());
            }
            else
            {
                Assert.Null(
                    initData[
                        "preparationNavigationV1"]);
            }
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchNonBuildNeverProjectsPreparationPresentationGate()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(
                    capture,
                    true);
            using var harness = new HostHarness(router);

            router.RequestOpenPanel(
                "workbench",
                "agent_control",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}");

            JObject opened =
                harness.LastOpenPayload;
            JObject initData =
                Assert.IsType<JObject>(
                    opened["initData"]);
            Assert.Equal(
                "tuning",
                initData.Value<string>(
                    "view"));
            Assert.Null(
                initData[
                    "preparationNavigationV1"]);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchBuild_AllowsOnlyFixedProductionSources()
        {
            Capture accepted = new Capture();
            LauncherCommandRouter router = MakeRouter(accepted);
            using var harness = new HostHarness(router);
            router.RequestOpenPanel(
                "workbench",
                "agent_control",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}");
            JObject opened = harness.LastOpenPayload;
            Assert.Equal("workbench", (string)opened["panel"]);
            Assert.Equal("battlebox", (string)opened["initData"]["profile"]);
            Assert.Equal("build", (string)opened["initData"]["view"]);
            Assert.Equal("agent_control", (string)opened["initData"]["source"]);

            Capture nativeHud = new Capture();
            LauncherCommandRouter nativeRouter =
                MakeRouter(nativeHud);
            using var harnessNative = new HostHarness(nativeRouter);
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
                harnessNative.LastOpenPayload;
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
            using var harness = new HostHarness(router);
            using (var task =
                new CharacterBuildTask(_ => true))
            {
                string instance =
                    OpenHostBuild(router, harness);
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
                    "{\"type\":\"panel_esc\",\"reason\":\"toggle\"}",
                    Assert.Single(capture.Posts));
                Assert.Empty(commands);
                Assert.Equal(
                    instance,
                    harness.Host.ActivePanelInstanceId);
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
            using var harness = new HostHarness(router);
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
                harness.Host.ActivePanelInstanceId;
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
                    harness.Host.ActivePanelInstanceId);
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
            using var harness = new HostHarness(router);
            using (var task =
                new CharacterBuildTask(_ => true))
            {
                string instance =
                    OpenHostBuild(router, harness);
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
                    "{\"type\":\"panel_esc\",\"reason\":\"toggle\"}",
                    Assert.Single(capture.Posts));
                Assert.Empty(commands);
                Assert.Equal(
                    1,
                    task.PendingCount);
                Assert.True(
                    task.IsBoundTo(instance));
                Assert.Equal(
                    instance,
                    harness.Host.ActivePanelInstanceId);
            }
        }

        [Fact]
        public void EQUIP_UI_ExactBuildUnknownWriteStaysBehindWebCloseGate()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            bool taskSend = true;
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        return taskSend;
                    }))
            {
                string instance =
                    OpenHostBuild(router, harness);
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
                    "{\"type\":\"panel_esc\",\"reason\":\"toggle\"}",
                    Assert.Single(capture.Posts));
                Assert.Empty(commands);
                Assert.Equal(
                    "needs_reconcile",
                    task.WriteState);
                Assert.True(
                    task.IsBoundTo(instance));
                Assert.Equal(
                    instance,
                    harness.Host.ActivePanelInstanceId);
            }
        }

        [Fact]
        public void FallbackPanelSwitchWaitsForCharacterBuildFinalizeProof()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using var harness = new HostHarness(router);
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
                string instance = harness.Host.ActivePanelInstanceId;
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
                Assert.Empty(capture.Posts);
                Assert.Equal(instance, harness.Host.ActivePanelInstanceId);

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
                Assert.Empty(capture.Posts);
                Assert.True(task.HasBoundPanel);
                Assert.True(task.RequiresDetachRecovery);
                Assert.Null(harness.Host.ActivePanelName);
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
                Assert.Empty(capture.Posts);

                router.RequestOpenPanel(
                    "map", "switch_test", null);
                Assert.Equal("map", harness.Host.ActivePanelName);
            }
        }

        [Fact]
        public void CharacterBuildDetachRecoveryFencesEveryPanelBeforePauseReuse()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using var harness = new HostHarness(router);
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
                    harness.Host.ActivePanelInstanceId;
                Assert.True(task.BindPanelInstance(instance));
                Assert.True(task.BeginWebViewDetach(0));
                Assert.True(task.RequiresDetachRecovery);

                router.RequestOpenPanel(
                    "map", "switch_test", null);

                Assert.Empty(capture.Posts);
                Assert.Equal(
                    instance,
                    harness.Host.ActivePanelInstanceId);
            }
        }

        [Theory]
        [InlineData(false, "skills")]
        [InlineData(true, "preparation-menu")]
        public void CharacterBuildSkillsNavigation_WaitsForExactRecoveryThenPreflightsOnce(
            bool preparationNavigationV1,
            string expectedReturnFocusAction)
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(
                    capture,
                    preparationNavigationV1);
            using var harness = new HostHarness(router);
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
                harness.WireSkillsEnricher(skillTask);
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

                string instance = OpenHostBuild(router, harness);
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
                harness.CloseCurrent();
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
                Assert.Null(harness.Host.ActivePanelName);
                Assert.Single(gameCommands);
                Assert.Empty(capture.Posts);

                RequestWorldSkillTrainer(
                    router,
                    "trainer.race");
                RequestNativeSkillManage(
                    router,
                    "skill.open.foreign");
                Assert.Null(
                    harness.Host.ActivePanelName);
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
                    harness.Host.ActivePanelName);
                JObject open = harness.LastOpenPayload;
                Assert.Equal(
                    "skills",
                    open.Value<string>("panel"));
                Assert.True(
                    (bool)open["initData"][
                        "canReturnCharacterBuild"]);

                string skillsInstance =
                    harness.Host.ActivePanelInstanceId;
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
                harness.CloseCurrent();
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
                    harness.LastOpenPayload;
                Assert.Equal(
                    "skills_return",
                    returnedBuild["initData"]
                        .Value<string>(
                            "navigationOrigin"));
                Assert.Equal(
                    expectedReturnFocusAction,
                    returnedBuild["initData"]
                        .Value<string>(
                            "returnFocusAction"));
                Assert.Equal(
                    preparationNavigationV1
                        ? true
                        : (bool?)null,
                    returnedBuild["initData"]
                        .Value<bool?>(
                            "preparationNavigationV1"));
            }
        }

        [Fact]
        public void RewardInboxReturn_UsesFreshNativeBuildPreflightExactlyOnce()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using var harness = new HostHarness(router);
            var gameCommands = new List<JObject>();
            router.SetGameCommandSenderForTests(
                delegate(string payload)
                {
                    gameCommands.Add(ParseWire(payload));
                    return true;
                });

            Assert.True(
                router.TryOpenCharacterBuildAfterRewardInbox());
            Assert.False(
                router.TryOpenCharacterBuildAfterRewardInbox());
            JObject firstPreflight = Assert.Single(gameCommands);
            Assert.Equal(6, firstPreflight.Count);
            Assert.Equal("cmd", firstPreflight.Value<string>("task"));
            Assert.Equal(
                "openInventoryWorkbench",
                firstPreflight.Value<string>("action"));
            Assert.Equal(
                "battlebox",
                firstPreflight.Value<string>("profile"));
            Assert.Equal("build", firstPreflight.Value<string>("view"));
            Assert.Equal(
                "nativehud_equipment",
                firstPreflight.Value<string>("source"));
            string firstRequestId =
                firstPreflight.Value<string>("openRequestId");
            Assert.False(string.IsNullOrEmpty(firstRequestId));

            router.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                firstRequestId);
            Assert.Equal("workbench", harness.Host.ActivePanelName);
            string firstInstance = harness.Host.ActivePanelInstanceId;
            Assert.False(string.IsNullOrEmpty(firstInstance));
            JObject firstOpen = harness.LastOpenPayload;
            Assert.Null(firstOpen["initData"]["navigationOrigin"]);

            harness.CloseCurrent();
            Assert.True(harness.Host.IsIdleForTrackedOpen);
            Assert.True(
                router.TryOpenCharacterBuildAfterRewardInbox());
            JObject[] buildPreflights = gameCommands
                .Where(command =>
                    command.Value<string>("action")
                        == "openInventoryWorkbench")
                .ToArray();
            Assert.Equal(2, buildPreflights.Length);
            string secondRequestId =
                buildPreflights[1].Value<string>("openRequestId");
            Assert.NotEqual(firstRequestId, secondRequestId);
            router.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                secondRequestId);
            Assert.Equal("workbench", harness.Host.ActivePanelName);
            Assert.NotEqual(
                firstInstance,
                harness.Host.ActivePanelInstanceId);
        }

        [Fact]
        public void RewardInboxReturn_ReplacesTrackedLootWithoutPauseOrVisualGap()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using var harness = new HostHarness(router);
            int pauseReleases = 0;
            using var coordinator = new LootPanelCoordinator(
                new LootPanelHostPort(harness.Host),
                delegate
                {
                    pauseReleases++;
                    return true;
                },
                delegate { return "panel.loot.reward"; });
            router.SetLootPanelCoordinator(coordinator);
            coordinator.SetRewardInboxReturnHandler(
                delegate(LootPanelCoordinator.Binding binding)
                {
                    return router
                        .TryOpenCharacterBuildAfterRewardInbox(
                            binding);
                });
            var gameCommands = new List<JObject>();
            router.SetGameCommandSenderForTests(
                delegate(string payload)
                {
                    gameCommands.Add(ParseWire(payload));
                    return true;
                });

            string rejection;
            Assert.True(coordinator.TryOpenRewardInbox(
                new JObject
                {
                    ["sourceKind"] = "reward_inbox",
                    ["chestSessionId"] = "reward.chest.router",
                    ["lootContainerId"] = "reward.container.router",
                    ["containerEpoch"] = 3,
                    ["openAttemptSeq"] = 4,
                    ["displayName"] = "待领取物品",
                    ["authorityRevision"] = 6,
                    ["state"] = "LOOT_ACTIVE",
                    ["remainingCount"] = 2,
                    ["capacity"] = 8,
                    ["columns"] = 8,
                    ["recoverableRootOperationId"] = "",
                    ["recoverableRootStatus"] = "not_started",
                    ["recoveryRequired"] = false,
                    ["recoveryOnly"] = false
                },
                out rejection));
            Assert.Equal("loot", harness.Host.ActivePanelName);
            Assert.True(harness.Host.HasTrackedPanelLease);
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact(
                "panel.loot.reward",
                "reward.chest.router",
                "reward.container.router",
                3,
                out binding));

            Assert.True(
                coordinator.CloseAfterAuthoritySuspended(binding));
            Assert.Equal("loot", harness.Host.ActivePanelName);
            Assert.True(
                coordinator.IsRewardInboxReplacementPendingExact(
                    binding.PanelInstanceId));
            JObject preflight = Assert.Single(gameCommands);
            string requestId =
                preflight.Value<string>("openRequestId");
            Assert.False(string.IsNullOrEmpty(requestId));
            string replacementPayload = null;
            harness.Host.SetExactReplacePosterForTests(
                delegate(string payload)
                {
                    replacementPayload = payload;
                    return true;
                });

            router.RequestOpenPanel(
                "workbench",
                "nativehud_equipment",
                null,
                null,
                null,
                null,
                null,
                "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                requestId);

            Assert.Equal("workbench", harness.Host.ActivePanelName);
            Assert.NotEqual(
                binding.PanelInstanceId,
                harness.Host.ActivePanelInstanceId);
            Assert.False(harness.Host.HasTrackedPanelLease);
            Assert.Equal(
                LootPanelCoordinator.BindingState.Idle,
                coordinator.State);
            Assert.Null(coordinator.ActiveBinding);
            Assert.Equal(0, pauseReleases);
            Assert.Equal(
                "reward_inbox_return",
                JObject.Parse(replacementPayload)["initData"]
                    .Value<string>("navigationOrigin"));
        }

        [Fact]
        public void RewardInboxReturn_RejectsCompetingPanelOrClosedAdmission()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using var harness = new HostHarness(router);
            var gameCommands = new List<string>();
            router.SetGameCommandSenderForTests(
                delegate(string payload)
                {
                    gameCommands.Add(payload);
                    return true;
                });

            Assert.True(harness.Host.TryOpenPanel(
                "settings", "{}", null, null));
            Assert.False(
                router.TryOpenCharacterBuildAfterRewardInbox());
            Assert.Empty(gameCommands);

            harness.CloseCurrent();
            router.SetPanelAdmissionGate(delegate { return false; });
            Assert.False(
                router.TryOpenCharacterBuildAfterRewardInbox());
            Assert.Empty(gameCommands);
        }

        [Theory]
        [InlineData("navigate_skills", "skills", true)]
        [InlineData("navigate_materials", "materials", true)]
        [InlineData("navigate_intelligence", "intelligence", true)]
        public void CharacterBuildPreparationReasonParserIsClosedAndB6TargetsAreEnabled(
            string reason,
            string expectedTarget,
            bool enabled)
        {
            Assert.True(
                LauncherCommandRouter
                    .TryParseCharacterBuildPreparationCloseReason(
                        reason,
                        out LauncherCommandRouter
                            .CharacterBuildPreparationTarget
                            target));
            Assert.Equal(
                expectedTarget,
                target.ToString().ToLowerInvariant());
            Assert.Equal(
                enabled,
                LauncherCommandRouter
                    .IsCharacterBuildPreparationTargetEnabled(
                        target));
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("navigate_skill")]
        [InlineData("navigate_skills_other")]
        [InlineData("NAVIGATE_SKILLS")]
        public void CharacterBuildPreparationReasonParserRejectsNearMatches(
            string reason)
        {
            Assert.False(
                LauncherCommandRouter
                    .TryParseCharacterBuildPreparationCloseReason(
                        reason,
                        out LauncherCommandRouter
                            .CharacterBuildPreparationTarget
                            ignored));
        }

        [Theory]
        [InlineData("skills")]
        [InlineData("preparation-menu")]
        public void CharacterBuildReturnFocusParserAcceptsOnlyMigrationValues(
            string value)
        {
            Assert.True(
                LauncherCommandRouter
                    .TryNormalizeCharacterBuildReturnFocusAction(
                        value,
                        out string normalized));
            Assert.Equal(
                value,
                normalized);
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("Skills")]
        [InlineData("#skills")]
        [InlineData("[data-header-action=skills]")]
        [InlineData("preparation-menu other")]
        public void CharacterBuildReturnFocusParserRejectsSelectorsAndNearMatches(
            string value)
        {
            Assert.False(
                LauncherCommandRouter
                    .TryNormalizeCharacterBuildReturnFocusAction(
                        value,
                        out string normalized));
            Assert.Null(normalized);
        }

        [Fact]
        public void UnknownCharacterBuildPreparationTargetNeverArmsOrClosesTheBuild()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            var gameCommands =
                new List<string>();
            using (var task =
                new CharacterBuildTask(
                    _ => true))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(
                            payload);
                        return true;
                    });
                string instance =
                    OpenHostBuild(router, harness);
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
                gameCommands.Clear();

                Assert.False(
                    router
                        .TryArmCharacterBuildPreparationNavigation(
                            instance,
                            (LauncherCommandRouter
                                .CharacterBuildPreparationTarget)999));

                Assert.Null(
                    router
                        .PendingCharacterBuildPreparationNavigationInstance);
                Assert.Null(
                    router
                        .PendingCharacterBuildPreparationTarget);
                Assert.True(
                    task.IsBoundTo(
                        instance));
                Assert.Equal(
                    "workbench",
                    harness.Host.ActivePanelName);
                Assert.Equal(
                    instance,
                    harness.Host.ActivePanelInstanceId);
                Assert.Empty(
                    gameCommands);
                Assert.Empty(
                    capture.Posts);
            }
        }

        [Fact]
        public void CharacterBuildPreparationArmTimeoutPreservesAnUnclosedExactBuild()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            var gameCommands =
                new System.Collections.Concurrent
                    .ConcurrentQueue<JObject>();
            using (var task =
                new CharacterBuildTask(
                    _ => true))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Enqueue(
                            ParseWire(payload));
                        return true;
                    });
                router.CharacterBuildPreparationNavigationTimeoutMs =
                    60;
                string instance =
                    OpenHostBuild(router, harness);
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
                    router
                        .TryArmCharacterBuildPreparationNavigation(
                            instance,
                            LauncherCommandRouter
                                .CharacterBuildPreparationTarget
                                .Skills));
                Assert.Equal(
                    "arm_to_settled",
                    router
                        .PendingCharacterBuildPreparationPhase);
                Assert.True(
                    System.Threading.SpinWait.SpinUntil(
                        delegate
                        {
                            return router
                                .PendingCharacterBuildPreparationNavigationInstance
                                == null;
                        },
                        2000));

                Assert.True(
                    task.IsBoundTo(
                        instance));
                Assert.False(
                    task.RequiresDetachRecovery);
                Assert.Equal(
                    "workbench",
                    harness.Host.ActivePanelName);
                Assert.Equal(
                    instance,
                    harness.Host.ActivePanelInstanceId);
                Assert.Empty(
                    gameCommands);
                JObject toast =
                    JObject.Parse(
                        Assert.Single(
                            capture.Posts));
                Assert.Equal(
                    "toast",
                    toast.Value<string>("type"));
                Assert.False(
                    router
                        .TryCompleteCharacterBuildPreparationNavigation());
            }
        }

        [Fact]
        public void CharacterBuildPreparationArmTimeoutAfterCloseRollsBackOnceOnlyAfterSettled()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            var flash =
                new List<string>();
            var gameCommands =
                new System.Collections.Concurrent
                    .ConcurrentQueue<JObject>();
            int completionCount =
                0;
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Enqueue(
                            ParseWire(payload));
                        return true;
                    });
                router.CharacterBuildPreparationNavigationTimeoutMs =
                    60;
                router.NativeEquipmentBuildOpenTimeoutMs =
                    1000;
                task.SetCoordinatorSettled(
                    delegate
                    {
                        if (router
                            .TryCompleteCharacterBuildPreparationNavigation())
                        {
                            completionCount++;
                        }
                    });
                string instance =
                    OpenHostBuild(router, harness);
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
                    router
                        .TryArmCharacterBuildPreparationNavigation(
                            instance,
                            LauncherCommandRouter
                                .CharacterBuildPreparationTarget
                                .Skills));
                Assert.True(
                    task.BeginNormalCloseBarrier(
                        instance));
                harness.CloseCurrent();
                Assert.True(
                    task.ContinueDetachRecoveryAfterVisualRetired(
                        0));
                Assert.True(
                    System.Threading.SpinWait.SpinUntil(
                        delegate
                        {
                            return router
                                .PendingCharacterBuildPreparationPhase
                                == "rollback_after_settle";
                        },
                        2000));
                Assert.Empty(
                    gameCommands);
                Assert.Equal(
                    0,
                    completionCount);

                JObject recovery =
                    JObject.Parse(
                        flash[flash.Count - 1]);
                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.Equal(
                    1,
                    completionCount);
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
                Assert.Null(
                    router
                        .PendingCharacterBuildPreparationNavigationInstance);
                Assert.False(
                    router
                        .TryCompleteCharacterBuildPreparationNavigation());
                Assert.Single(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.True(
                    router
                        .CancelPendingNativeEquipmentBuildOpenIntent(
                            "test_cleanup"));
            }
        }

        [Fact]
        public void CharacterBuildPreparationSettledAtomicallySwapsToIndependentSkillOpenTimer()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            var flash =
                new List<string>();
            var gameCommands =
                new System.Collections.Concurrent
                    .ConcurrentQueue<JObject>();
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Enqueue(
                            ParseWire(payload));
                        return true;
                    });
                router.CharacterBuildPreparationNavigationTimeoutMs =
                    300;
                router.SkillOpenTimeoutMs =
                    40;
                router.NativeEquipmentBuildOpenTimeoutMs =
                    1000;
                task.SetCoordinatorSettled(
                    delegate
                    {
                        router
                            .TryCompleteCharacterBuildPreparationNavigation();
                    });
                string instance =
                    OpenHostBuild(router, harness);
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
                    router
                        .TryArmCharacterBuildPreparationNavigation(
                            instance,
                            LauncherCommandRouter
                                .CharacterBuildPreparationTarget
                                .Skills));
                Assert.True(
                    task.BeginNormalCloseBarrier(
                        instance));
                harness.CloseCurrent();
                Assert.True(
                    task.ContinueDetachRecoveryAfterVisualRetired(
                        0));
                JObject recovery =
                    JObject.Parse(
                        flash[flash.Count - 1]);
                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.Null(
                    router
                        .PendingCharacterBuildPreparationNavigationInstance);
                Assert.Single(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "skillPanelOpen");
                Assert.True(
                    System.Threading.SpinWait.SpinUntil(
                        delegate
                        {
                            return gameCommands.Count(
                                command =>
                                    command.Value<string>("action")
                                        == "openInventoryWorkbench")
                                == 1;
                        },
                        2000));
                System.Threading.Thread.Sleep(
                    320);
                Assert.Single(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "skillPanelOpen");
                Assert.Single(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.False(
                    router
                        .TryCompleteCharacterBuildPreparationNavigation());
                Assert.True(
                    router
                        .CancelPendingNativeEquipmentBuildOpenIntent(
                            "test_cleanup"));
            }
        }

        [Fact]
        public void CharacterBuildMaterialsNavigation_ExactEchoOpensCraftingWithoutRollback()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            var flash =
                new List<string>();
            var commands =
                new List<JObject>();
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(
                            ParseWire(payload));
                        return true;
                    });
                string openRequestId =
                    BeginCharacterBuildMaterialHandoff(
                        router,
                        harness.Host,
                        null,
                        task,
                        capture,
                        flash,
                        commands);

                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    openRequestId);

                Assert.Null(
                    router.PendingMaterialOpenRequestId);
                Assert.Equal(
                    "crafting",
                    harness.Host.ActivePanelName);
                Assert.DoesNotContain(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                JObject opened =
                    harness.LastOpenPayload;
                Assert.Equal(
                    "materials",
                    opened["initData"]
                        .Value<string>(
                            "view"));
                Assert.True(
                    opened["initData"]
                        .Value<bool>(
                            "canReturnCharacterBuild"));
                Assert.Equal(
                    "character_build",
                    opened["initData"]
                        .Value<string>(
                            "navigationOrigin"));
                Assert.Equal(
                    "crafting",
                    router
                        .PendingPreparationChildReturnPanelName);
                Assert.Equal(
                    harness.Host.ActivePanelInstanceId,
                    router
                        .PendingPreparationChildReturnInstance);
            }
        }

        [Fact]
        public void CharacterBuildMaterialsNavigation_DroppedQueuedForwardCannotAuthorizeLaterOrdinaryOpen()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var flash =
                new List<string>();
            var commands =
                new List<JObject>();
            var enrichedInitData =
                new List<JObject>();
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
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
                router.SetPanelHost(
                    host);
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(
                            ParseWire(payload));
                        return true;
                    });
                string openRequestId =
                    BeginCharacterBuildMaterialHandoff(
                        router,
                        host,
                        pumps,
                        task,
                        capture,
                        flash,
                        commands);
                host.SetInitDataEnricher(
                    delegate(
                        string panelName,
                        string initDataJson,
                        string panelInstanceId)
                    {
                        enrichedInitData.Add(
                            JObject.Parse(
                                initDataJson));
                        return initDataJson;
                    });
                host.SetOpenGate(
                    delegate
                    {
                        return false;
                    });

                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    openRequestId);
                Assert.Equal(
                    "crafting",
                    router
                        .PendingPreparationChildReturnPanelName);
                Assert.Null(
                    router
                        .PendingPreparationChildReturnInstance);
                Assert.Single(
                    pumps);
                Action droppedForwardPump =
                    pumps.Dequeue();
                droppedForwardPump();
                Assert.Empty(
                    pumps);
                Assert.Null(
                    host.ActivePanelName);

                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    null);

                Assert.Null(
                    router
                        .PendingPreparationChildReturnPanelName);
                Assert.Null(
                    router
                        .PendingPreparationChildReturnInstance);
                Action deferredOrdinaryPump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                deferredOrdinaryPump();
                Assert.Empty(
                    enrichedInitData);
                host.SetOpenGate(
                    delegate
                    {
                        return true;
                    });
                host.FlushDeferredBarrierOpen();
                Action ordinaryPump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                ordinaryPump();
                Assert.Single(
                    enrichedInitData);
                Assert.All(
                    enrichedInitData,
                    initData =>
                    {
                        Assert.Null(
                            initData[
                                "canReturnCharacterBuild"]);
                        Assert.Null(
                            initData[
                                "navigationOrigin"]);
                    });
            }
        }

        [Fact]
        public void CharacterBuildMaterialsReturn_ConsumesExactChildOnceAndUsesFreshNativeBuildPreflight()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(
                    capture,
                    preparationNavigationV1: true);
            using var harness = new HostHarness(router);
            var flash =
                new List<string>();
            var commands =
                new List<JObject>();
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(
                            ParseWire(payload));
                        return true;
                    });
                string materialRequestId =
                    BeginCharacterBuildMaterialHandoff(
                        router,
                        harness.Host,
                        null,
                        task,
                        capture,
                        flash,
                        commands);
                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    materialRequestId);

                string childInstance =
                    harness.Host.ActivePanelInstanceId;
                Assert.False(
                    string.IsNullOrEmpty(
                        childInstance));
                Assert.True(
                    router
                        .TryArmPreparationChildCharacterBuildNavigation(
                            "crafting",
                            childInstance));
                Assert.False(
                    router
                        .TryArmPreparationChildCharacterBuildNavigation(
                            "crafting",
                            childInstance));
                Assert.False(
                    router
                        .TryArmPreparationChildCharacterBuildNavigation(
                            "crafting",
                            "fallback.stale"));
                Assert.DoesNotContain(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");

                capture.Posts.Clear();
                harness.CloseCurrent();
                Assert.True(
                    router
                        .TryCompletePreparationChildCharacterBuildNavigation(
                            "crafting",
                            childInstance));
                Assert.False(
                    router
                        .TryCompletePreparationChildCharacterBuildNavigation(
                            "crafting",
                            childInstance));

                JObject preflight =
                    Assert.Single(
                        commands,
                        command =>
                            command.Value<string>("action")
                                == "openInventoryWorkbench");
                string buildRequestId =
                    preflight.Value<string>(
                        "openRequestId");
                Assert.False(
                    string.IsNullOrEmpty(
                        buildRequestId));
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
                    harness.LastOpenPayload;
                Assert.Equal(
                    "workbench",
                    returnedBuild.Value<string>(
                        "panel"));
                Assert.NotEqual(
                    childInstance,
                    returnedBuild.Value<string>(
                        "panelInstanceId"));
                Assert.Equal(
                    "materials_return",
                    returnedBuild["initData"]
                        .Value<string>(
                            "navigationOrigin"));
                Assert.Equal(
                    "preparation-menu",
                    returnedBuild["initData"]
                        .Value<string>(
                            "returnFocusAction"));
                Assert.Equal(
                    "build",
                    returnedBuild["initData"]
                        .Value<string>(
                            "view"));
            }
        }

        [Fact]
        public void MaterialShopCharacterCapsule_CommitPermitSurvivesLifecycleCancelAndRebindsExactReturn()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using var harness = new HostHarness(router);
            var flash = new List<string>();
            var commands = new List<JObject>();
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
                        commands.Add(ParseWire(payload));
                        return true;
                    });
                string requestId = BeginCharacterBuildMaterialHandoff(
                    router,
                    harness.Host,
                    null,
                    task,
                    capture,
                    flash,
                    commands);
                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    requestId);
                string sourceCrafting = harness.Host.ActivePanelInstanceId;
                const string npcInstance = "panel.npcshop.material";
                const string returnCrafting = "panel.crafting.material.return";

                Assert.True(router.TryPrepareMaterialShopCharacterForward(
                    sourceCrafting,
                    npcInstance,
                    out LauncherCommandRouter.MaterialShopCharacterCapsule capsule));
                Assert.NotNull(capsule);
                Assert.True(router.TrySealMaterialShopCharacterForwardCommit(
                    capsule,
                    sourceCrafting,
                    npcInstance));
                router.AbortMaterialShopCharacterForwardNoFail(
                    capsule,
                    sourceCrafting,
                    npcInstance);
                Assert.Equal(
                    LauncherCommandRouter.MaterialShopCharacterCapsulePhase.PreparedForward,
                    capsule.Phase);
                Assert.True(router.IsMaterialShopCharacterForwardCurrent(
                    capsule,
                    sourceCrafting,
                    npcInstance));

                Assert.True(router.TrySealMaterialShopCharacterForwardCommit(
                    capsule,
                    sourceCrafting,
                    npcInstance));
                router.CancelAllPanelNavigationIntents("commit_permit_race");
                Assert.Equal(
                    LauncherCommandRouter.MaterialShopCharacterCapsulePhase.ForwardCommitting,
                    capsule.Phase);
                router.CommitMaterialShopCharacterForwardNoFail(capsule);
                Assert.Equal(
                    LauncherCommandRouter.MaterialShopCharacterCapsulePhase.SuspendedInShop,
                    capsule.Phase);

                Assert.True(router.TryPrepareMaterialShopCharacterReverse(
                    capsule,
                    npcInstance,
                    returnCrafting));
                Assert.True(router.TrySealMaterialShopCharacterReverseCommit(
                    capsule,
                    npcInstance,
                    returnCrafting));
                router.AbortMaterialShopCharacterReverseNoFail(
                    capsule,
                    npcInstance,
                    returnCrafting);
                Assert.Equal(
                    LauncherCommandRouter.MaterialShopCharacterCapsulePhase.SuspendedInShop,
                    capsule.Phase);

                Assert.True(router.TryPrepareMaterialShopCharacterReverse(
                    capsule,
                    npcInstance,
                    returnCrafting));
                Assert.True(router.TrySealMaterialShopCharacterReverseCommit(
                    capsule,
                    npcInstance,
                    returnCrafting));
                router.CancelAllPanelNavigationIntents("reverse_commit_permit_race");
                Assert.Equal(
                    LauncherCommandRouter.MaterialShopCharacterCapsulePhase.ReverseCommitting,
                    capsule.Phase);
                router.CommitMaterialShopCharacterReverseNoFail(
                    capsule,
                    returnCrafting);

                Assert.Equal(
                    LauncherCommandRouter.MaterialShopCharacterCapsulePhase.ReturnedToMaterials,
                    capsule.Phase);
                Assert.Equal("crafting", router.PendingPreparationChildReturnPanelName);
                Assert.Equal(returnCrafting, router.PendingPreparationChildReturnInstance);
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void PreparationChildReturnCapability_OrdinaryCloseAndReturningTimeoutBothRevoke(
            bool returningTimeout)
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            var flash =
                new List<string>();
            var commands =
                new List<JObject>();
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(
                            ParseWire(payload));
                        return true;
                    });
                string materialRequestId =
                    BeginCharacterBuildMaterialHandoff(
                        router,
                        harness.Host,
                        null,
                        task,
                        capture,
                        flash,
                        commands);
                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    materialRequestId);
                string childInstance =
                    harness.Host.ActivePanelInstanceId;
                Assert.False(
                    string.IsNullOrEmpty(
                        childInstance));

                if (returningTimeout)
                {
                    router
                        .PreparationChildCharacterBuildNavigationTimeoutMs =
                        20;
                    Assert.True(
                        router
                            .TryArmPreparationChildCharacterBuildNavigation(
                                "crafting",
                                childInstance));
                    Assert.True(
                        System.Threading.SpinWait.SpinUntil(
                            delegate
                            {
                                return router
                                    .PendingPreparationChildReturnPanelName
                                    == null;
                            },
                            2000));
                    Assert.DoesNotContain(
                        commands,
                        command =>
                            command.Value<string>("action")
                                == "openInventoryWorkbench");
                }
                else
                {
                    Assert.True(
                        router
                            .CancelPreparationChildCharacterBuildNavigation(
                                "crafting",
                                childInstance,
                                "ordinary_close"));
                }

                Assert.Null(
                    router
                        .PendingPreparationChildReturnPanelName);
                Assert.Null(
                    router
                        .PendingPreparationChildReturnInstance);
                Assert.False(
                    router
                        .TryArmPreparationChildCharacterBuildNavigation(
                            "crafting",
                            childInstance));
            }
        }

        [Fact]
        public void PreparationChildReturnCapability_IsAbsentFromOrdinaryHudOrigins()
        {
            Capture materials =
                new Capture();
            LauncherCommandRouter materialRouter =
                MakeRouter(materials);
            using var harnessMaterial = new HostHarness(materialRouter);
            RequestNativeMaterials(
                materialRouter,
                "crafting",
                "nativehud_materials",
                "{\"view\":\"materials\"}",
                null);
            JObject materialOpen =
                harnessMaterial.LastOpenPayload;
            string materialInstance =
                materialOpen.Value<string>(
                    "panelInstanceId");
            Assert.Null(
                materialOpen["initData"][
                    "canReturnCharacterBuild"]);
            Assert.Null(
                materialOpen["initData"][
                    "navigationOrigin"]);
            Assert.False(
                materialRouter
                    .TryArmPreparationChildCharacterBuildNavigation(
                        "crafting",
                        materialInstance));

            Capture intelligence =
                new Capture();
            LauncherCommandRouter intelligenceRouter =
                MakeRouter(intelligence);
            using var harnessIntelligence = new HostHarness(intelligenceRouter);
            intelligenceRouter.Dispatch(
                "INTELLIGENCE");
            JObject intelligenceOpen =
                harnessIntelligence.LastOpenPayload;
            string intelligenceInstance =
                intelligenceOpen.Value<string>(
                    "panelInstanceId");
            Assert.Null(
                intelligenceOpen["initData"][
                    "canReturnCharacterBuild"]);
            Assert.Null(
                intelligenceOpen["initData"][
                    "navigationOrigin"]);
            Assert.False(
                intelligenceRouter
                    .TryArmPreparationChildCharacterBuildNavigation(
                        "intelligence",
                        intelligenceInstance));
        }

        [Fact]
        public void CharacterBuildMaterialsNavigation_WrongNonceRollsBackAtMostOnce()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            var flash =
                new List<string>();
            var commands =
                new List<JObject>();
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Add(
                            ParseWire(payload));
                        return true;
                    });
                string openRequestId =
                    BeginCharacterBuildMaterialHandoff(
                        router,
                        harness.Host,
                        null,
                        task,
                        capture,
                        flash,
                        commands);

                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    "material.open.wrong");
                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    openRequestId);
                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    "material.open.second-wrong");

                Assert.Null(
                    router.PendingMaterialOpenRequestId);
                Assert.Null(
                    harness.Host.ActivePanelName);
                Assert.Single(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "openMaterialUI");
                Assert.Single(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.DoesNotContain(
                    capture.Posts,
                    value => value.Contains(
                        "\"cmd\":\"open\""));
                Assert.True(
                    router
                        .CancelPendingNativeEquipmentBuildOpenIntent(
                            "test_cleanup"));
            }
        }

        [Fact]
        public void CharacterBuildMaterialsNavigation_TargetTimeoutRollsBackAndLateEchoOpensZero()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            router.CharacterBuildPreparationNavigationTimeoutMs =
                400;
            router.MaterialPanelOpenTimeoutMs =
                25;
            var flash =
                new List<string>();
            var commands =
                new System.Collections.Concurrent
                    .ConcurrentQueue<JObject>();
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        commands.Enqueue(
                            ParseWire(payload));
                        return true;
                    });
                string openRequestId =
                    BeginCharacterBuildMaterialHandoff(
                        router,
                        harness.Host,
                        null,
                        task,
                        capture,
                        flash,
                        commands);

                Assert.True(
                    System.Threading.SpinWait.SpinUntil(
                        delegate
                        {
                            return commands.Count(
                                command =>
                                    command.Value<string>("action")
                                        == "openInventoryWorkbench")
                                == 1;
                        },
                        2000));
                RequestNativeMaterials(
                    router,
                    "crafting",
                    "nativehud_materials",
                    "{\"view\":\"materials\"}",
                    openRequestId);
                System.Threading.Thread.Sleep(
                    450);

                Assert.Null(
                    harness.Host.ActivePanelName);
                Assert.Single(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "openMaterialUI");
                Assert.Single(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.DoesNotContain(
                    capture.Posts,
                    value => value.Contains(
                        "\"cmd\":\"open\""));
                Assert.True(
                    router
                        .CancelPendingNativeEquipmentBuildOpenIntent(
                            "test_cleanup"));
            }
        }

        [Fact]
        public void IntelligenceProductionInitDataIsClosedAndFixed()
        {
            JObject initData =
                LauncherCommandRouter
                    .BuildIntelligenceProductionInitData();

            Assert.Equal(
                new[] { "debug", "mode", "source" },
                initData.Properties()
                    .Select(property => property.Name)
                    .OrderBy(name => name)
                    .ToArray());
            Assert.Equal(
                "prod",
                initData.Value<string>("mode"));
            Assert.Equal(
                "runtime",
                initData.Value<string>("source"));
            Assert.False(
                initData.Value<bool>("debug"));
        }

        [Fact]
        public void CharacterBuildIntelligenceNavigation_ExactSettledAdmissionOpensOnceWithoutTargetWait()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var flash =
                new List<string>();
            var gameCommands =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetPanelHost(host);
                router.SetCharacterBuildTask(task);
                router.CharacterBuildPreparationNavigationTimeoutMs =
                    40;
                router.SkillOpenTimeoutMs =
                    40;
                router.MaterialPanelOpenTimeoutMs =
                    40;
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(
                            ParseWire(payload));
                        return true;
                    });
                int settledCallbacks =
                    0;
                bool? completionConsumed =
                    null;
                task.SetCoordinatorSettled(
                    delegate
                    {
                        settledCallbacks++;
                        completionConsumed =
                            router
                                .TryCompleteCharacterBuildPreparationNavigation();
                    });
                JObject recovery =
                    PrepareHostCharacterBuildIntelligenceHandoff(
                        router,
                        host,
                        task,
                        pumps,
                        flash,
                        delegate
                        {
                            gameCommands.Clear();
                        });

                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.True(
                    completionConsumed);
                Assert.Equal(
                    1,
                    settledCallbacks);
                Assert.Null(
                    router
                        .PendingCharacterBuildPreparationNavigationInstance);
                Assert.Null(
                    router.PendingMaterialOpenRequestId);
                Assert.DoesNotContain(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "skillPanelOpen"
                        || command.Value<string>("action")
                            == "openMaterialUI"
                        || command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.DoesNotContain(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "webPanelPause");
                Assert.Single(
                    pumps);
                Assert.False(
                    router
                        .TryCompleteCharacterBuildPreparationNavigation());
                Assert.Single(
                    pumps);

                System.Threading.Thread.Sleep(
                    120);
                Assert.Empty(
                    capture.Posts);
                Assert.Single(
                    pumps);
                Action intelligencePump =
                    pumps.Dequeue();
                intelligencePump();
                Assert.Equal(
                    "intelligence",
                    host.ActivePanelName);
                Assert.False(
                    string.IsNullOrEmpty(
                        host.ActivePanelInstanceId));
                Assert.Equal(
                    "intelligence",
                    router
                        .PendingPreparationChildReturnPanelName);
                Assert.Equal(
                    host.ActivePanelInstanceId,
                    router
                        .PendingPreparationChildReturnInstance);
            }
        }

        [Fact]
        public void CharacterBuildIntelligenceNavigation_DroppedQueuedForwardCannotAuthorizeLaterOrdinaryOpen()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var flash =
                new List<string>();
            var gameCommands =
                new List<JObject>();
            var enrichedInitData =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetPanelHost(
                    host);
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(
                            ParseWire(payload));
                        return true;
                    });
                task.SetCoordinatorSettled(
                    delegate
                    {
                        Assert.True(
                            router
                                .TryCompleteCharacterBuildPreparationNavigation());
                    });
                JObject recovery =
                    PrepareHostCharacterBuildIntelligenceHandoff(
                        router,
                        host,
                        task,
                        pumps,
                        flash,
                        delegate
                        {
                            gameCommands.Clear();
                        });
                host.SetInitDataEnricher(
                    delegate(
                        string panelName,
                        string initDataJson,
                        string panelInstanceId)
                    {
                        enrichedInitData.Add(
                            JObject.Parse(
                                initDataJson));
                        return initDataJson;
                    });
                host.SetOpenGate(
                    delegate
                    {
                        return false;
                    });

                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);
                Assert.Equal(
                    "intelligence",
                    router
                        .PendingPreparationChildReturnPanelName);
                Assert.Null(
                    router
                        .PendingPreparationChildReturnInstance);
                Assert.Single(
                    pumps);
                Action droppedForwardPump =
                    pumps.Dequeue();
                droppedForwardPump();
                Assert.Empty(
                    pumps);
                Assert.Null(
                    host.ActivePanelName);

                router.Dispatch(
                    "INTELLIGENCE");

                Assert.Null(
                    router
                        .PendingPreparationChildReturnPanelName);
                Assert.Null(
                    router
                        .PendingPreparationChildReturnInstance);
                Action deferredOrdinaryPump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                deferredOrdinaryPump();
                Assert.Empty(
                    enrichedInitData);
                host.SetOpenGate(
                    delegate
                    {
                        return true;
                    });
                host.FlushDeferredBarrierOpen();
                Action ordinaryPump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                ordinaryPump();
                Assert.Single(
                    enrichedInitData);
                Assert.All(
                    enrichedInitData,
                    initData =>
                    {
                        Assert.Null(
                            initData[
                                "canReturnCharacterBuild"]);
                        Assert.Null(
                            initData[
                                "navigationOrigin"]);
                    });
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void CharacterBuildIntelligenceReturn_RequiresExactVisualIdleAndRejectsCompetingLifecycle(
            bool openCompetingPanel)
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(
                    capture,
                    preparationNavigationV1: true);
            var pumps =
                new Queue<Action>();
            var flash =
                new List<string>();
            var gameCommands =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetPanelHost(
                    host);
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Add(
                            ParseWire(payload));
                        return true;
                    });
                task.SetCoordinatorSettled(
                    delegate
                    {
                        router
                            .TryCompleteCharacterBuildPreparationNavigation();
                    });
                JObject recovery =
                    PrepareHostCharacterBuildIntelligenceHandoff(
                        router,
                        host,
                        task,
                        pumps,
                        flash,
                        delegate
                        {
                            gameCommands.Clear();
                        });
                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);
                Action intelligencePump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                intelligencePump();
                string childInstance =
                    host.ActivePanelInstanceId;
                Assert.Equal(
                    "intelligence",
                    host.ActivePanelName);
                Assert.Equal(
                    childInstance,
                    router
                        .PendingPreparationChildReturnInstance);

                Assert.False(
                    router
                        .TryArmPreparationChildCharacterBuildNavigation(
                            "crafting",
                            childInstance));
                Assert.False(
                    router
                        .TryArmPreparationChildCharacterBuildNavigation(
                            "intelligence",
                            "panel.stale"));
                Assert.True(
                    router
                        .TryArmPreparationChildCharacterBuildNavigation(
                            "intelligence",
                            childInstance));
                Assert.False(
                    router
                        .TryArmPreparationChildCharacterBuildNavigation(
                            "intelligence",
                            childInstance));

                gameCommands.Clear();
                bool? completion =
                    null;
                PanelHostController.VisualRetireOutcome?
                    retireOutcome =
                        null;
                Assert.True(
                    host.TryRetirePanelVisualExact(
                        "intelligence",
                        childInstance,
                        delegate(
                            PanelHostController
                                .VisualRetireOutcome
                                outcome)
                        {
                            retireOutcome =
                                outcome;
                            if (!openCompetingPanel)
                            {
                                completion =
                                    router
                                        .TryCompletePreparationChildCharacterBuildNavigation(
                                            "intelligence",
                                            childInstance);
                            }
                        }));
                Assert.DoesNotContain(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Action retirePump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                retirePump();
                Assert.True(
                    retireOutcome
                        == PanelHostController
                            .VisualRetireOutcome
                            .RetiredExact
                    || retireOutcome
                        == PanelHostController
                            .VisualRetireOutcome
                            .VisualAlreadyAbsent);
                Assert.True(
                    host.IsIdleForTrackedOpen);

                if (openCompetingPanel)
                {
                    Assert.True(
                        host.TryOpenPanel(
                            "map",
                            null,
                            null,
                            null));
                    Action mapPump =
                        Assert.Single(
                            pumps);
                    pumps.Clear();
                    mapPump();
                    Assert.Equal(
                        "map",
                        host.ActivePanelName);
                    Assert.False(
                        router
                            .TryCompletePreparationChildCharacterBuildNavigation(
                                "intelligence",
                                childInstance));
                    Assert.Null(
                        router
                            .PendingPreparationChildReturnInstance);
                    Assert.DoesNotContain(
                        gameCommands,
                        command =>
                            command.Value<string>("action")
                                == "openInventoryWorkbench");
                    return;
                }

                Assert.True(
                    completion);
                JObject buildPreflight =
                    Assert.Single(
                        gameCommands,
                        command =>
                            command.Value<string>("action")
                                == "openInventoryWorkbench");
                router.RequestOpenPanel(
                    "workbench",
                    "nativehud_equipment",
                    null,
                    null,
                    null,
                    null,
                    null,
                    "{\"profile\":\"battlebox\",\"view\":\"build\"}",
                    buildPreflight.Value<string>(
                        "openRequestId"));
                Action buildPump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                buildPump();
                Assert.Equal(
                    "workbench",
                    host.ActivePanelName);
                Assert.NotEqual(
                    childInstance,
                    host.ActivePanelInstanceId);
                Assert.False(
                    router
                        .TryCompletePreparationChildCharacterBuildNavigation(
                            "intelligence",
                            childInstance));
            }
        }

        [Fact]
        public void CharacterBuildIntelligenceNavigation_StaleHostAdmissionRollsBackAtMostOnce()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var flash =
                new List<string>();
            var gameCommands =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
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
                task.SetCoordinatorSettled(
                    delegate
                    {
                        Assert.True(
                            router
                                .TryCompleteCharacterBuildPreparationNavigation());
                    });
                JObject recovery =
                    PrepareHostCharacterBuildIntelligenceHandoff(
                        router,
                        host,
                        task,
                        pumps,
                        flash,
                        delegate
                        {
                            gameCommands.Clear();
                        });
                bool invalidated =
                    false;
                router.SetPanelAdmissionGate(
                    delegate
                    {
                        if (!invalidated)
                        {
                            invalidated =
                                true;
                            Assert.True(
                                host.TryAcquireIdleFence(
                                    "intelligence.admission.race"));
                            Assert.True(
                                host.ReleaseIdleFenceExact(
                                    "intelligence.admission.race"));
                        }
                        return true;
                    });

                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.True(
                    invalidated);
                Assert.Empty(
                    pumps);
                Assert.Null(
                    host.ActivePanelName);
                Assert.Single(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.DoesNotContain(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "skillPanelOpen"
                        || command.Value<string>("action")
                            == "openMaterialUI");
                Assert.False(
                    router
                        .TryCompleteCharacterBuildPreparationNavigation());
                Assert.Single(
                    gameCommands,
                    command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench");
                Assert.True(
                    router
                        .CancelPendingNativeEquipmentBuildOpenIntent(
                            "test_cleanup"));
            }
        }

        [Fact]
        public void CharacterBuildIntelligenceNavigation_RollbackFailureStaysInGameWithActionableToast()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var flash =
                new List<string>();
            var gameCommands =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
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
                task.SetCoordinatorSettled(
                    delegate
                    {
                        Assert.True(
                            router
                                .TryCompleteCharacterBuildPreparationNavigation());
                    });
                JObject recovery =
                    PrepareHostCharacterBuildIntelligenceHandoff(
                        router,
                        host,
                        task,
                        pumps,
                        flash,
                        delegate
                        {
                            gameCommands.Clear();
                        });
                Assert.True(
                    host.TryAcquireIdleFence(
                        "intelligence.rollback.blocked"));

                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.Empty(
                    pumps);
                Assert.Empty(
                    gameCommands);
                Assert.Null(
                    host.ActivePanelName);
                JObject toast =
                    JObject.Parse(
                        Assert.Single(
                            capture.Posts));
                Assert.Equal(
                    "toast",
                    toast.Value<string>("type"));
                Assert.Contains(
                    "情报面板未打开",
                    toast.Value<string>("text"));
                Assert.Contains(
                    "装备入口",
                    toast.Value<string>("text"));
                Assert.False(
                    router
                        .TryCompleteCharacterBuildPreparationNavigation());
                Assert.Single(
                    capture.Posts);
                Assert.True(
                    host.ReleaseIdleFenceExact(
                        "intelligence.rollback.blocked"));
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void CharacterBuildIntelligenceNavigation_AcceptedOpenSurvivesPauseSocketFalseOrThrow(
            bool throwOnPauseFailure)
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var flash =
                new List<string>();
            bool failPause =
                false;
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
                        return true;
                    }))
            {
                router.SetPanelHost(host);
                router.SetCharacterBuildTask(task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        JObject command =
                            ParseWire(payload);
                        if (failPause
                            && command.Value<string>("action")
                                == "webPanelPause")
                        {
                            if (throwOnPauseFailure)
                            {
                                throw new InvalidOperationException(
                                    "socket closed");
                            }
                            return false;
                        }
                        return true;
                    });
                bool? completionConsumed =
                    null;
                task.SetCoordinatorSettled(
                    delegate
                    {
                        completionConsumed =
                            router
                                .TryCompleteCharacterBuildPreparationNavigation();
                    });
                JObject recovery =
                    PrepareHostCharacterBuildIntelligenceHandoff(
                        router,
                        host,
                        task,
                        pumps,
                        flash,
                        delegate
                        {
                        });
                failPause =
                    true;

                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.True(
                    completionConsumed);
                Assert.Single(
                    pumps);
                Assert.Empty(
                    capture.Posts);
                pumps.Dequeue()();
                Assert.Equal(
                    "intelligence",
                    host.ActivePanelName);
                Assert.False(
                    router
                        .CancelPendingNativeEquipmentBuildOpenIntent(
                            "probe"));
            }
        }

        [Fact]
        public void CharacterBuildIntelligenceNavigation_LifecycleCancellationFencesLateSettled()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var flash =
                new List<string>();
            var gameCommands =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
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
                bool? completionConsumed =
                    null;
                task.SetCoordinatorSettled(
                    delegate
                    {
                        completionConsumed =
                            router
                                .TryCompleteCharacterBuildPreparationNavigation();
                    });
                JObject recovery =
                    PrepareHostCharacterBuildIntelligenceHandoff(
                        router,
                        host,
                        task,
                        pumps,
                        flash,
                        delegate
                        {
                            gameCommands.Clear();
                        });
                router.CancelAllPanelNavigationIntents(
                    "shutdown");

                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.False(
                    completionConsumed);
                Assert.Empty(
                    pumps);
                Assert.Empty(
                    gameCommands);
                Assert.Empty(
                    capture.Posts);
                Assert.Null(
                    host.ActivePanelName);
            }
        }

        [Fact]
        public void CharacterBuildIntelligenceNavigation_LifecycleAdvanceDuringAdmissionSuppressesRollback()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            var pumps =
                new Queue<Action>();
            var flash =
                new List<string>();
            var gameCommands =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            using (var task =
                new CharacterBuildTask(
                    delegate(string payload)
                    {
                        flash.Add(
                            payload.TrimEnd('\0'));
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
                bool? completionConsumed =
                    null;
                task.SetCoordinatorSettled(
                    delegate
                    {
                        completionConsumed =
                            router
                                .TryCompleteCharacterBuildPreparationNavigation();
                    });
                JObject recovery =
                    PrepareHostCharacterBuildIntelligenceHandoff(
                        router,
                        host,
                        task,
                        pumps,
                        flash,
                        delegate
                        {
                            gameCommands.Clear();
                        });
                bool lifecycleAdvanced =
                    false;
                router.SetPanelAdmissionGate(
                    delegate
                    {
                        lifecycleAdvanced =
                            true;
                        router.CancelAllPanelNavigationIntents(
                            "shutdown_during_admission");
                        return false;
                    });

                task.HandleFlashResponse(
                    CharacterBuildRecoveryAck(
                        recovery,
                        9),
                    null);

                Assert.True(
                    lifecycleAdvanced);
                Assert.True(
                    completionConsumed);
                Assert.Empty(
                    pumps);
                Assert.Empty(
                    gameCommands);
                Assert.Empty(
                    capture.Posts);
                Assert.Null(
                    host.ActivePanelName);
                Assert.False(
                    router
                        .CancelPendingNativeEquipmentBuildOpenIntent(
                            "probe"));
            }
        }

        [Fact]
        public void CancelAllDisposesCharacterBuildPreparationArmTimerAndFencesLateTimeout()
        {
            Capture capture =
                new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
            var gameCommands =
                new System.Collections.Concurrent
                    .ConcurrentQueue<JObject>();
            using (var task =
                new CharacterBuildTask(
                    _ => true))
            {
                router.SetCharacterBuildTask(
                    task);
                router.SetGameCommandSenderForTests(
                    delegate(string payload)
                    {
                        gameCommands.Enqueue(
                            ParseWire(payload));
                        return true;
                    });
                router.CharacterBuildPreparationNavigationTimeoutMs =
                    60;
                string instance =
                    OpenHostBuild(router, harness);
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
                    router
                        .TryArmCharacterBuildPreparationNavigation(
                            instance,
                            LauncherCommandRouter
                                .CharacterBuildPreparationTarget
                                .Skills));
                router.CancelAllPanelNavigationIntents(
                    "test_lifecycle");
                System.Threading.Thread.Sleep(
                    150);

                Assert.Null(
                    router
                        .PendingCharacterBuildPreparationNavigationInstance);
                Assert.Null(
                    router
                        .PendingCharacterBuildPreparationPhase);
                Assert.True(
                    task.IsBoundTo(
                        instance));
                Assert.Equal(
                    "workbench",
                    harness.Host.ActivePanelName);
                Assert.Empty(
                    gameCommands);
                Assert.Empty(
                    capture.Posts);
            }
        }

        [Fact]
        public void CharacterBuildSkillsNavigation_CancelsOnlyTheExactArmedInstance()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using var harness = new HostHarness(router);
            using (var task = new CharacterBuildTask(_ => true))
            {
                router.SetCharacterBuildTask(task);
                string instance = OpenHostBuild(router, harness);
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
            using var harness = new HostHarness(router);
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

                string instance = OpenHostBuild(router, harness);
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
                    harness.Host.ActivePanelName);
            }
        }

        [Fact]
        public void CharacterBuildSkillsNavigation_CancelledAtAtomicConsumeDoesNotClaimNavigation()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router = MakeRouter(capture);
            using var harness = new HostHarness(router);
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

                string instance = OpenHostBuild(router, harness);
                Assert.True(task.BindPanelInstance(instance));
                PrimeCharacterBuild(task, instance, 9);
                FinalizeCharacterBuild(task, instance, 9);
                gameCommands.Clear();

                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.True(
                    task.BeginNormalCloseBarrier(instance));
                harness.CloseCurrent();
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
                    harness.Host.ActivePanelName);
            }
        }

        [Fact]
        public void CharacterBuildSkillsNavigation_PreflightAdmissionFailureReportsOnce()
        {
            Capture capture = new Capture();
            LauncherCommandRouter router =
                MakeRouter(capture);
            using var harness = new HostHarness(router);
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
                    OpenHostBuild(router, harness);
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
                harness.CloseCurrent();
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
            using var harness = new HostHarness(router);
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
                    OpenHostBuild(router, harness);
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
                harness.CloseCurrent();
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
                    harness.LastOpenPayload;
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
            using var harness = new HostHarness(router);
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
                    OpenHostBuild(router, harness);
                Assert.True(
                    task.BindPanelInstance(instance));
                PrimeCharacterBuild(task, instance, 9);
                FinalizeCharacterBuild(task, instance, 9);
                Assert.True(
                    router.TryArmCharacterBuildSkillsNavigation(
                        instance));
                Assert.True(
                    task.BeginNormalCloseBarrier(instance));
                harness.CloseCurrent();
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
        }

        [Fact]
        public void RequestOpenPanel_SkillsTrainer_RebuildsStrictRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            r.RequestOpenPanel("skills", "world_skill_trainer", null, null, null, null, null,
                "{\"view\":\"trainer\",\"trainerSession\":\"trainer.session.7\"}");
            string open = harnessR.LastOpenPayload.ToString(Newtonsoft.Json.Formatting.None);
            Assert.Contains("\"panel\":\"skills\"", open);
            Assert.Contains("\"source\":\"world_skill_trainer\"", open);
            Assert.Contains("\"view\":\"trainer\"", open);
            Assert.Contains("\"trainerSession\":\"trainer.session.7\"", open);
            Assert.DoesNotContain("\"openRequestId\"", open);
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
        }

        [Fact]
        public void SkillsReturnCapability_IsAbsentFromNotchAndTrainerOrigins()
        {
            Capture notch = new Capture();
            LauncherCommandRouter notchRouter =
                MakeRouter(notch);
            using var harnessNotchRouter = new HostHarness(notchRouter);
            using (var notchTask = new SkillTask(
                () => true,
                _ => true))
            {
                notchRouter.SetSkillTask(
                    notchTask);
                string notchInstance =
                    OpenNativeSkillManage(notchRouter, harnessNotchRouter);
                Assert.False(
                    notchRouter
                        .TryArmSkillsCharacterBuildNavigation(
                            notchInstance));
            }

            Capture trainer = new Capture();
            LauncherCommandRouter trainerRouter =
                MakeRouter(trainer);
            using (var harnessTrainerRouter = new HostHarness(trainerRouter))
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
                    harnessTrainerRouter
                        .Host.ActivePanelInstanceId;
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
            using var harnessR = new HostHarness(r);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(value => { commands.Add(value); return true; });
            r.SkillOpenTimeoutMs = 20;

            r.Dispatch("SKILLS");

            Assert.Single(commands);
            Assert.Contains("skillPanelOpen", commands[0]);
            Assert.Empty(c.Posts);
            Assert.True(System.Threading.SpinWait.SpinUntil(() => c.Posts.Count == 1, 2000));
            Assert.Contains("技能服务未就绪", c.Posts[0]);
            Assert.DoesNotContain("\"cmd\":\"open\"", c.Posts[0]);

            RequestNativeSkillManage(
                r,
                ReadSkillOpenRequestId(
                    commands[0]));

            Assert.Single(c.Posts);
            Assert.Null(
                harnessR.Host.ActivePanelName);
        }

        [Fact]
        public void SkillsButton_LegacyNonceLessManageIsRejectedWithoutConsumingExactPreflight()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            string openRequestId =
                BeginNativeSkillOpen(r);

            RequestNativeSkillManage(
                r,
                null);

            Assert.Empty(c.Posts);
            Assert.Null(
                harnessR.Host.ActivePanelName);

            RequestNativeSkillManage(
                r,
                openRequestId);

            Assert.Empty(c.Posts);
            Assert.Equal(
                "skills",
                harnessR.Host.ActivePanelName);
        }

        [Fact]
        public void SkillsButton_ReadyPanelRequestOpensOnceAndCancelsTimeoutToast()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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

            Assert.Equal("skills", harnessR.Host.ActivePanelName);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void SkillsButton_AcceptedManageRejectsLateTrainerAndCleansItsSession()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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
                harnessR.WireSkillsEnricher(task);
                RequestNativeSkillManage(
                    r,
                    BeginNativeSkillOpen(r));
                string manageInstance =
                    harnessR.Host.ActivePanelInstanceId;
                Assert.False(
                    string.IsNullOrEmpty(manageInstance));
                Assert.Empty(c.Posts);
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

                Assert.Empty(c.Posts);
                Assert.Equal(
                    manageInstance,
                    harnessR.Host.ActivePanelInstanceId);
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
            using var harnessR = new HostHarness(r);
            string openRequestId =
                BeginNativeSkillOpen(r);

            r.RequestOpenPanel(
                "map",
                "competing_test",
                null);
            Assert.Equal(
                "map",
                harnessR.Host.ActivePanelName);
            Assert.Empty(c.Posts);

            RequestNativeSkillManage(
                r,
                openRequestId);

            Assert.Empty(c.Posts);
            Assert.Equal(
                "map",
                harnessR.Host.ActivePanelName);
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
            using var harnessR = new HostHarness(r);
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
                harnessR.Host.ActivePanelName);
        }

        [Fact]
        public void SkillsButton_SynchronousPanelRequestDuringSendCannotInstallStaleTimeout()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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

            Assert.Equal("skills", harnessR.Host.ActivePanelName);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void SkillsButton_SynchronousAckFollowedBySendFalseDoesNotReportFailure()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
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

            JObject opened = harnessR.LastOpenPayload;
            Assert.Equal(
                "skills",
                opened.Value<string>("panel"));
            Assert.Empty(c.Posts);
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
            using var harnessR = new HostHarness(r);
            RequestWorldSkillTrainer(
                r,
                "trainer.a");
            string firstInstance = harnessR.Host.ActivePanelInstanceId;
            var first = harnessR.LastOpenPayload;
            RequestWorldSkillTrainer(
                r,
                "trainer.b");
            Assert.Equal(firstInstance, harnessR.Host.ActivePanelInstanceId);
            Assert.Equal("trainer.a", (string)first["initData"]["trainerSession"]);
        }

        [Fact]
        public void SkillsTrainerManageRoundTrip_PreservesFocusButKeepsCapabilityInsideHost()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                harnessR.WireSkillsEnricher(task);
                RequestWorldSkillTrainer(
                    r,
                    "trainer.switch");
                string trainerInstance = harnessR.Host.ActivePanelInstanceId;
                task.BindPanelInstance(trainerInstance);

                Assert.True(r.RebindSkillsToManage(trainerInstance, "闪现"));
                JObject manage = harnessR.LastOpenPayload;
                Assert.Equal("manage", (string)manage["initData"]["view"]);
                Assert.Equal("闪现", (string)manage["initData"]["focusSkillKey"]);
                Assert.True((bool)manage["initData"]["canReturnTrainer"]);
                Assert.Null(manage["initData"]["trainerSession"]);
                Assert.NotEqual(trainerInstance, (string)manage["panelInstanceId"]);
                Assert.Empty(sent); // 返回凭据只暂存在 Host；切换本身不提前清理。
                Assert.False(r.RebindSkillsToManage(trainerInstance, "闪现"));

                string manageInstance = (string)manage["panelInstanceId"];
                Assert.Equal(manageInstance, harnessR.Host.ActivePanelInstanceId);
                task.BindPanelInstance(manageInstance);
                Assert.True(r.RebindSkillsToTrainer(manageInstance, "闪现"));
                JObject trainer = harnessR.LastOpenPayload;
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
            using var harnessR = new HostHarness(r);
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
                r.SetSkillTask(task);
                harnessR.WireSkillsEnricher(task);
                task.SetCoordinatorSettled(delegate { harnessR.Host.FlushDeferredRebind("skills"); });
                OpenNativeSkillManage(r, harnessR);
                Assert.Empty(c.Posts);
                string oldInstance = harnessR.Host.ActivePanelInstanceId;
                task.BindPanelInstance(oldInstance);
                task.HandleFlashResponse(SkillCleanupAck((int)sent[0]["callId"], 12), null);

                JObject write = SkillRequest("equip", "fallback.write");
                write["panelInstanceId"] = oldInstance;
                task.HandleWebRequest("equip", write);
                int writeFid = (int)sent[sent.Count - 1]["callId"];
                RequestWorldSkillTrainer(
                    r,
                    "trainer.new");
                Assert.Empty(c.Posts);
                Assert.Equal(oldInstance, harnessR.Host.ActivePanelInstanceId);

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
                Assert.Empty(c.Posts);
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

                Assert.Empty(c.Posts);
                Assert.Equal(
                    oldInstance,
                    harnessR.Host.ActivePanelInstanceId);
                Assert.Equal(oldInstance, (string)web[web.Count - 1]["panelInstanceId"]);
            }
        }

        [Fact]
        public void FallbackDisconnectClear_AllowsRealRecoveryOpenWhileTaskNeedsReconcile()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                // 生产接线镜像：skills initData 由 Host enricher 应用（Program.cs 同款）
                harnessR.Host.SetInitDataEnricher(
                    delegate(string panelName, string initDataJson, string panelInstanceId)
                    {
                        return panelName == "skills"
                            ? task.EnrichPanelInitData(initDataJson, panelInstanceId)
                            : initDataJson;
                    });
                OpenNativeSkillManage(r, harnessR);
                string oldInstance = harnessR.Host.ActivePanelInstanceId;
                task.BindPanelInstance(oldInstance);
                JObject write = SkillRequest("equip", "fallback.disconnect.write");
                write["panelInstanceId"] = oldInstance;
                task.HandleWebRequest("equip", write);
                RequestNativeSkillManage(
                    r,
                    BeginNativeSkillOpen(r));
                Assert.Empty(c.Posts);

                task.ClearPending();
                harnessR.CloseCurrent();
                RequestNativeSkillManage(
                    r,
                    BeginNativeSkillOpen(r));

                JObject recovery = harnessR.LastOpenPayload;
                Assert.NotEqual(oldInstance, (string)recovery["panelInstanceId"]);
                Assert.Equal("needs_reconcile", (string)recovery["initData"]["writeState"]);
                Assert.Equal("fallback.disconnect.write", (string)recovery["initData"]["reconcileAfterCallId"]);
            }
        }

        [Fact]
        public void TrainerSwitchToOtherPanel_ClosesScopedCapabilityBeforeFirstBusinessRequest()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            using var harnessR = new HostHarness(r);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                harnessR.WireSkillsEnricher(task);
                // 生产接线镜像：Host 关闭观察器把 skills 关闭转发给 SkillTask（Program.cs 同款）
                harnessR.Host.SetPanelCloseObserver(
                    delegate(string panelName, string panelInstanceId)
                    {
                        if (panelName == "skills")
                            task.HandleAuthoritativePanelClosed(panelInstanceId);
                    });
                RequestWorldSkillTrainer(
                    r,
                    "trainer.first");
                Assert.Equal("skills", harnessR.Host.ActivePanelName);

                r.RequestOpenPanel("map", "switch_test", null);

                Assert.Equal("map", harnessR.Host.ActivePanelName);
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
            using (var harnessR = new HostHarness(r))
            {
                r.SetSkillTask(task);
                task.RequestTrainerCleanup(null);
                Assert.Single(sent);
                Assert.Null(sent[0]["trainerSession"]);

                RequestWorldSkillTrainer(
                    r,
                    "trainer.candidate.C");
                JObject opened = harnessR.LastOpenPayload;
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

        [Fact]
        public void EQUIPMENT_TUNING_SendsFrozenPreflightAndExactAckOpensStandalone()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            var commands =
                new List<string>();
            router.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(value);
                    return true;
                });

            router.Dispatch(
                "EQUIPMENT_TUNING");

            JObject preflight =
                ParseWire(
                    Assert.Single(commands));
            Assert.Equal(
                "cmd",
                preflight.Value<string>("task"));
            Assert.Equal(
                "openInventoryWorkbench",
                preflight.Value<string>("action"));
            Assert.Equal(
                "battlebox",
                preflight.Value<string>("profile"));
            Assert.Equal(
                "tuning",
                preflight.Value<string>("view"));
            Assert.Equal(
                "nativehud_equipment_tuning",
                preflight.Value<string>("source"));
            Assert.Equal(
                6,
                preflight.Count);
            string openRequestId =
                preflight.Value<string>(
                    "openRequestId");
            Assert.StartsWith(
                "tuning.open.",
                openRequestId);
            Assert.Empty(c.Posts);

            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            JObject open =
                harness.LastOpenPayload;
            Assert.Equal(
                "panel_cmd",
                open.Value<string>("type"));
            Assert.Equal(
                "workbench",
                open.Value<string>("panel"));
            Assert.Equal(
                "battlebox",
                open["initData"]
                    .Value<string>("profile"));
            Assert.Equal(
                "tuning",
                open["initData"]
                    .Value<string>("view"));
            Assert.Equal(
                "nativehud_equipment_tuning",
                open["initData"]
                    .Value<string>("source"));
            Assert.Null(
                open["initData"]["returnTo"]);
            Assert.Equal(
                "workbench",
                harness.Host.ActivePanelName);
            Assert.False(
                string.IsNullOrEmpty(
                    harness.Host.ActivePanelInstanceId));
            Assert.Single(commands);

            using (var tuningTask =
                new EquipmentTuningTask(
                    () => true,
                    delegate { return true; }))
            {
                router.SetEquipmentTuningTask(
                    tuningTask);
                Assert.True(
                    tuningTask.BindPanelInstance(
                        harness.Host.ActivePanelInstanceId));
                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);
                Assert.DoesNotContain(
                    c.Posts,
                    value => value.Contains(
                        "\"type\":\"toast\""));
                Assert.Equal(
                    "workbench",
                    harness.Host.ActivePanelName);
            }
        }

        [Fact]
        public void EQUIPMENT_TUNING_DuplicateEchoWithoutBoundTaskStillReportsExpired()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            string command =
                null;
            router.SetGameCommandSenderForTests(
                value =>
                {
                    command = value;
                    return true;
                });

            router.Dispatch(
                "EQUIPMENT_TUNING");
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    command);
            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            Assert.Equal(
                "workbench",
                harness.Host.ActivePanelName);

            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            Assert.Single(
                c.Posts,
                value => value.Contains(
                    "装备调制请求已处理或过期"));
        }

        [Fact]
        public void EQUIPMENT_TUNING_PanelHostDuplicateEchoAfterPumpAndExactBindingIsSilent()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
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
            using (var tuningTask =
                new EquipmentTuningTask(
                    () => true,
                    delegate(string payload)
                    {
                        return true;
                    }))
            {
                router.SetPanelHost(
                    host);
                router.SetEquipmentTuningTask(
                    tuningTask);
                router.SetGameCommandSenderForTests(
                    value =>
                    {
                        commands.Add(value);
                        return true;
                    });

                router.Dispatch(
                    "EQUIPMENT_TUNING");
                string openRequestId =
                    ReadWorkbenchOpenRequestId(
                        Assert.Single(commands));
                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);
                Action pump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                pump();
                Assert.Equal(
                    "workbench",
                    host.ActivePanelName);
                Assert.True(
                    tuningTask.BindPanelInstance(
                        host.ActivePanelInstanceId));
                Assert.Empty(
                    c.Posts);

                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);

                Assert.Empty(
                    c.Posts);
                Assert.Empty(
                    pumps);
                Assert.Equal(
                    host.ActivePanelInstanceId,
                    tuningTask.PanelInstanceId);
            }
        }

        [Fact]
        public void EQUIPMENT_TUNING_FallbackCloseMakesDuplicateEchoReportExpired()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            string command =
                null;
            using (var tuningTask =
                new EquipmentTuningTask(
                    () => true,
                    delegate(string payload)
                    {
                        return true;
                    }))
            {
                router.SetEquipmentTuningTask(
                    tuningTask);
                router.SetGameCommandSenderForTests(
                    value =>
                    {
                        command = value;
                        return true;
                    });
                router.Dispatch(
                    "EQUIPMENT_TUNING");
                string openRequestId =
                    ReadWorkbenchOpenRequestId(
                        command);
                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);
                string closedInstance =
                    harness.Host.ActivePanelInstanceId;
                Assert.True(
                    tuningTask.BindPanelInstance(
                        closedInstance));
                c.Posts.Clear();

                harness.CloseCurrent();
                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);

                Assert.Null(
                    harness.Host.ActivePanelName);
                Assert.Equal(
                    closedInstance,
                    tuningTask.PanelInstanceId);
                Assert.Contains(
                    "装备调制请求已处理或过期",
                    Assert.Single(
                        c.Posts));
            }
        }

        [Fact]
        public void EQUIPMENT_TUNING_WrongTaskBindingMakesDuplicateEchoReportExpired()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            string command =
                null;
            using (var tuningTask =
                new EquipmentTuningTask(
                    () => true,
                    delegate(string payload)
                    {
                        return true;
                    }))
            {
                router.SetEquipmentTuningTask(
                    tuningTask);
                router.SetGameCommandSenderForTests(
                    value =>
                    {
                        command = value;
                        return true;
                    });
                router.Dispatch(
                    "EQUIPMENT_TUNING");
                string openRequestId =
                    ReadWorkbenchOpenRequestId(
                        command);
                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);
                string activeInstance =
                    harness.Host.ActivePanelInstanceId;
                Assert.True(
                    tuningTask.BindPanelInstance(
                        "workbench.tuning.wrong"));
                c.Posts.Clear();

                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);

                Assert.Equal(
                    activeInstance,
                    harness.Host.ActivePanelInstanceId);
                Assert.NotEqual(
                    activeInstance,
                    tuningTask.PanelInstanceId);
                Assert.Contains(
                    "装备调制请求已处理或过期",
                    Assert.Single(
                        c.Posts));
            }
        }

        [Fact]
        public void EQUIPMENT_TUNING_LifecycleCleanupClearsProofWhileExactBindingRemains()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            string command =
                null;
            using (var tuningTask =
                new EquipmentTuningTask(
                    () => true,
                    delegate(string payload)
                    {
                        return true;
                    }))
            {
                router.SetEquipmentTuningTask(
                    tuningTask);
                router.SetGameCommandSenderForTests(
                    value =>
                    {
                        command = value;
                        return true;
                    });
                router.Dispatch(
                    "EQUIPMENT_TUNING");
                string openRequestId =
                    ReadWorkbenchOpenRequestId(
                        command);
                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);
                string activeInstance =
                    harness.Host.ActivePanelInstanceId;
                Assert.True(
                    tuningTask.BindPanelInstance(
                        activeInstance));
                c.Posts.Clear();

                router.CancelAllPanelNavigationIntents(
                    "test_cleanup");
                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);

                Assert.Equal(
                    activeInstance,
                    harness.Host.ActivePanelInstanceId);
                Assert.Equal(
                    activeInstance,
                    tuningTask.PanelInstanceId);
                Assert.Contains(
                    "装备调制请求已处理或过期",
                    Assert.Single(
                        c.Posts));
            }
        }

        [Theory]
        [InlineData(
            "nativehud_equipment_tuning",
            "{\"profile\":\"battlebox\",\"view\":\"storage\"}")]
        [InlineData(
            "nativehud_equipment_tuning_extra",
            "{\"profile\":\"battlebox\",\"view\":\"tuning\"}")]
        [InlineData(
            "nativehud_equipment_tuning",
            "{\"profile\":\"battlebox\",\"view\":\"tuning\",\"extra\":true}")]
        [InlineData(
            "nativehud_equipment_tuning",
            "{\"profile\":\"warehouse\",\"view\":\"tuning\"}")]
        public void EQUIPMENT_TUNING_NearMatchClearsIntentAndLateExactAckCannotOpen(
            string source,
            string initData)
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            var commands =
                new List<string>();
            router.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(value);
                    return true;
                });
            router.Dispatch(
                "EQUIPMENT_TUNING");
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    Assert.Single(commands));

            RequestNativeEquipmentTuning(
                router,
                source,
                initData,
                openRequestId);
            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.DoesNotContain(
                c.Posts,
                value => value.Contains(
                    "\"cmd\":\"open\""));
            Assert.All(
                c.Posts,
                value => Assert.Contains(
                    "\"type\":\"toast\"",
                    value));
            Assert.Single(commands);
        }

        [Theory]
        [InlineData(
            "nativehud_equipment_tuning_extra")]
        [InlineData(
            "nativehud")]
        public void EQUIPMENT_TUNING_UncorrelatedWorkbenchWithoutNonceClearsIntentAndOpensZero(
            string source)
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            var commands =
                new List<string>();
            router.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(value);
                    return true;
                });
            router.Dispatch(
                "EQUIPMENT_TUNING");
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    Assert.Single(commands));

            RequestNativeEquipmentTuning(
                router,
                source,
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                null);
            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.DoesNotContain(
                c.Posts,
                value => value.Contains(
                    "\"cmd\":\"open\""));
            Assert.All(
                c.Posts,
                value => Assert.Contains(
                    "\"type\":\"toast\"",
                    value));
            Assert.Contains(
                c.Posts,
                value => value.Contains(
                    "当前操作发生冲突，请重试"));
            Assert.Single(commands);
        }

        [Fact]
        public void EQUIPMENT_TUNING_NonceCarriedByWrongPanelClearsIntentAndOpensZero()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            string command =
                null;
            router.SetGameCommandSenderForTests(
                value =>
                {
                    command = value;
                    return true;
                });
            router.Dispatch(
                "EQUIPMENT_TUNING");
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    command);

            router.RequestOpenPanel(
                "skills",
                "nativehud_equipment_tuning",
                null,
                null,
                null,
                null,
                null,
                null,
                openRequestId);
            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.DoesNotContain(
                c.Posts,
                value => value.Contains(
                    "\"cmd\":\"open\""));
            Assert.Equal(
                2,
                c.Posts.Count);
        }

        [Fact]
        public void EQUIPMENT_TUNING_QueuedHostOpenStalesAdmissionBeforeEcho()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            var pumps =
                new Queue<Action>();
            var commands =
                new List<JObject>();
            using (var host =
                new PanelHostController(
                    pumps.Enqueue,
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                router.SetPanelHost(
                    host);
                router.SetGameCommandSenderForTests(
                    value =>
                    {
                        commands.Add(
                            ParseWire(value));
                        return true;
                    });
                router.Dispatch(
                    "EQUIPMENT_TUNING");
                string openRequestId =
                    commands.Single(command =>
                        command.Value<string>("action")
                            == "openInventoryWorkbench")
                    .Value<string>(
                        "openRequestId");
                Assert.True(
                    host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));

                RequestNativeEquipmentTuning(
                    router,
                    "nativehud_equipment_tuning",
                    "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                    openRequestId);

                Assert.DoesNotContain(
                    commands,
                    command =>
                        command.Value<string>("action")
                            == "webPanelPause");
                Action pump =
                    Assert.Single(
                        pumps);
                pumps.Clear();
                pump();
                Assert.Equal(
                    "map",
                    host.ActivePanelName);
                Assert.Empty(
                    pumps);
            }
        }

        [Fact]
        public void EQUIPMENT_TUNING_ExactTupleWithoutNonceClearsIntentAndOpensZero()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            string command =
                null;
            router.SetGameCommandSenderForTests(
                value =>
                {
                    command = value;
                    return true;
                });
            router.Dispatch(
                "EQUIPMENT_TUNING");
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    command);

            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                null);
            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.DoesNotContain(
                c.Posts,
                value => value.Contains(
                    "\"cmd\":\"open\""));
            Assert.Equal(
                2,
                c.Posts.Count);
            Assert.Contains(
                c.Posts,
                value => value.Contains(
                    "装备调制请求已处理或过期"));
        }

        [Fact]
        public void EQUIPMENT_TUNING_WrongNonceClearsIntentAndDuplicateEchoOpensZero()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            string command =
                null;
            router.SetGameCommandSenderForTests(
                value =>
                {
                    command = value;
                    return true;
                });
            router.Dispatch(
                "EQUIPMENT_TUNING");
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    command);

            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                "tuning.open.wrong");
            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.DoesNotContain(
                c.Posts,
                value => value.Contains(
                    "\"cmd\":\"open\""));
            Assert.Equal(
                2,
                c.Posts.Count);
        }

        [Fact]
        public void EQUIPMENT_TUNING_TimeoutClearsIntentAndLateEchoOpensZero()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            router.NativeEquipmentTuningOpenTimeoutMs =
                30;
            string command =
                null;
            router.SetGameCommandSenderForTests(
                value =>
                {
                    command = value;
                    return true;
                });
            router.Dispatch(
                "EQUIPMENT_TUNING");
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    command);

            Assert.True(
                System.Threading.SpinWait.SpinUntil(
                    () => c.Posts.Count > 0,
                    2000));
            Assert.Contains(
                "装备调制服务未就绪",
                c.Posts[0]);
            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.DoesNotContain(
                c.Posts,
                value => value.Contains(
                    "\"cmd\":\"open\""));
        }

        [Fact]
        public void EQUIPMENT_TUNING_ActivePanelAndRepeatedUserIntentNeverToggleClose()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            router.RequestOpenPanel(
                "tasks",
                "test",
                null);
            c.Posts.Clear();
            var commands =
                new List<string>();
            router.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(value);
                    return true;
                });

            router.Dispatch(
                "EQUIPMENT_TUNING");

            Assert.Empty(commands);
            Assert.Equal(
                "tasks",
                harness.Host.ActivePanelName);
            Assert.Single(c.Posts);
            Assert.Contains(
                "请先关闭当前面板",
                c.Posts[0]);
            Assert.DoesNotContain(
                "panel_esc",
                c.Posts[0]);
        }

        [Fact]
        public void EQUIPMENT_TUNING_DuplicateClickIsRejectedWithoutReplacingArmedNonce()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            var commands =
                new List<string>();
            router.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(value);
                    return true;
                });

            router.Dispatch(
                "EQUIPMENT_TUNING");
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    Assert.Single(commands));
            router.Dispatch(
                "EQUIPMENT_TUNING");

            Assert.Single(commands);
            Assert.Contains(
                c.Posts,
                value => value.Contains(
                    "\"type\":\"toast\""));
            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);
            Assert.Equal(
                "workbench",
                harness.Host.ActivePanelName);
        }

        [Fact]
        public void EQUIPMENT_TUNING_AdmissionRevocationClearsIntentWithoutPauseOrOpen()
        {
            Capture c = new Capture();
            LauncherCommandRouter router =
                MakeRouter(c);
            using var harness = new HostHarness(router);
            bool admitted =
                true;
            var commands =
                new List<string>();
            router.SetPanelAdmissionGate(
                () => admitted);
            router.SetGameCommandSenderForTests(
                value =>
                {
                    commands.Add(value);
                    return true;
                });
            router.Dispatch(
                "EQUIPMENT_TUNING");
            string openRequestId =
                ReadWorkbenchOpenRequestId(
                    Assert.Single(commands));

            admitted = false;
            RequestNativeEquipmentTuning(
                router,
                "nativehud_equipment_tuning",
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}",
                openRequestId);

            Assert.Null(
                harness.Host.ActivePanelName);
            Assert.Single(commands);
            Assert.DoesNotContain(
                commands,
                value => value.Contains(
                    "webPanelPause"));
            Assert.Contains(
                c.Posts,
                value => value.Contains(
                    "\"type\":\"toast\""));
        }

        private static string OpenHostBuild(
            LauncherCommandRouter router,
            HostHarness harness)
        {
            return OpenHostBuild(router, harness.Host, null);
        }

        private static string OpenHostBuild(
            LauncherCommandRouter router,
            PanelHostController host,
            Queue<Action> pumps)
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
            DrainPumps(pumps);
            string instance =
                host.ActivePanelInstanceId;
            Assert.False(
                string.IsNullOrEmpty(instance));
            Assert.Equal(
                "workbench",
                host.ActivePanelName);
            return instance;
        }

        private static void DrainPumps(Queue<Action> pumps)
        {
            if (pumps == null) return;
            while (pumps.Count > 0) pumps.Dequeue()();
        }

        private static void CloseHostCurrent(
            PanelHostController host,
            Queue<Action> pumps)
        {
            string name = host.ActivePanelName;
            string instance = host.ActivePanelInstanceId;
            if (name == null || instance == null) return;
            Assert.True(host.TryClosePanelExact(name, instance, null));
            DrainPumps(pumps);
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

        private static JObject
            PrepareHostCharacterBuildIntelligenceHandoff(
                LauncherCommandRouter router,
                PanelHostController host,
                CharacterBuildTask task,
                Queue<Action> pumps,
                List<string> flash,
                Action clearGameCommands)
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
            Action openPump =
                Assert.Single(
                    pumps);
            pumps.Clear();
            openPump();
            string instance =
                host.ActivePanelInstanceId;
            Assert.False(
                string.IsNullOrEmpty(
                    instance));
            Assert.Equal(
                "workbench",
                host.ActivePanelName);
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
            clearGameCommands();

            Assert.True(
                router
                    .TryArmCharacterBuildPreparationNavigation(
                        instance,
                        LauncherCommandRouter
                            .CharacterBuildPreparationTarget
                            .Intelligence));
            Assert.True(
                task.BeginNormalCloseBarrier(
                    instance));
            Assert.True(
                host.TryClosePanelExact(
                    "workbench",
                    instance,
                    null));
            Action closePump =
                Assert.Single(
                    pumps);
            pumps.Clear();
            closePump();
            Assert.True(
                host.IsIdleForTrackedOpen);
            Assert.True(
                task.ContinueDetachRecoveryAfterVisualRetired(
                    0));
            return JObject.Parse(
                flash[flash.Count - 1]);
        }

        private static string BeginCharacterBuildMaterialHandoff(
            LauncherCommandRouter router,
            PanelHostController host,
            Queue<Action> pumps,
            CharacterBuildTask task,
            Capture capture,
            List<string> flash,
            List<JObject> commands)
        {
            return BeginCharacterBuildMaterialHandoff(
                router,
                host,
                pumps,
                task,
                capture,
                flash,
                delegate { commands.Clear(); },
                delegate { return commands.ToArray(); });
        }

        private static string BeginCharacterBuildMaterialHandoff(
            LauncherCommandRouter router,
            PanelHostController host,
            Queue<Action> pumps,
            CharacterBuildTask task,
            Capture capture,
            List<string> flash,
            System.Collections.Concurrent
                .ConcurrentQueue<JObject> commands)
        {
            return BeginCharacterBuildMaterialHandoff(
                router,
                host,
                pumps,
                task,
                capture,
                flash,
                delegate { commands.Clear(); },
                delegate { return commands.ToArray(); });
        }

        private static string BeginCharacterBuildMaterialHandoff(
            LauncherCommandRouter router,
            PanelHostController host,
            Queue<Action> pumps,
            CharacterBuildTask task,
            Capture capture,
            List<string> flash,
            Action clearCommands,
            Func<IEnumerable<JObject>> readCommands)
        {
            task.SetCoordinatorSettled(
                delegate
                {
                    Assert.True(
                        router
                            .TryCompleteCharacterBuildPreparationNavigation());
                });
            string instance =
                OpenHostBuild(router, host, pumps);
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
            clearCommands();

            Assert.True(
                router
                    .TryArmCharacterBuildPreparationNavigation(
                        instance,
                        LauncherCommandRouter
                            .CharacterBuildPreparationTarget
                            .Materials));
            Assert.True(
                task.BeginNormalCloseBarrier(
                    instance));
            CloseHostCurrent(host, pumps);
            Assert.True(
                task.ContinueDetachRecoveryAfterVisualRetired(
                    0));
            JObject recovery =
                JObject.Parse(
                    flash[flash.Count - 1]);
            task.HandleFlashResponse(
                CharacterBuildRecoveryAck(
                    recovery,
                    9),
                null);

            Assert.Null(
                router
                    .PendingCharacterBuildPreparationNavigationInstance);
            Assert.Equal(
                "character_build",
                router.PendingMaterialOpenOrigin);
            JObject command =
                Assert.Single(
                    readCommands(),
                    value =>
                        value.Value<string>("action")
                            == "openMaterialUI");
            string openRequestId =
                command.Value<string>(
                    "openRequestId");
            Assert.Equal(
                openRequestId,
                router.PendingMaterialOpenRequestId);
            return openRequestId;
        }

        private static void RequestNativeMaterials(
            LauncherCommandRouter router,
            string panel,
            string source,
            string initData,
            string openRequestId)
        {
            router.RequestOpenPanel(
                panel,
                source,
                null,
                null,
                null,
                null,
                null,
                initData,
                openRequestId);
        }

        private static void RequestNativeEquipmentTuning(
            LauncherCommandRouter router,
            string source,
            string initData,
            string openRequestId)
        {
            router.RequestOpenPanel(
                "workbench",
                source,
                null,
                null,
                null,
                null,
                null,
                initData,
                openRequestId);
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
            LauncherCommandRouter router,
            HostHarness harness)
        {
            RequestNativeSkillManage(
                router,
                BeginNativeSkillOpen(router));
            string instance =
                harness.Host.ActivePanelInstanceId;
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
