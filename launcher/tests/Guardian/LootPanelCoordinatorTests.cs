using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tests.Guardian
{
    public class LootPanelCoordinatorTests
    {
        private sealed class FakePanel : ILootPanelPort
        {
            public volatile bool Available = true;
            public volatile bool Idle = true;
            public volatile string ActiveName;
            public volatile string ActiveInstance;
            public string InitDataJson;
            public string ReservedInstance;
            public Func<bool> ExecutionGate;
            public Action<PanelHostController.TrackedOpenOutcome> OpenCompleted;
            public Action<bool> CloseCompleted;
            public int OpenCalls;
            private int _closeCalls;
            public bool QueueOpen = true;
            public volatile bool QueueClose = true;
            private readonly object _fenceSync = new object();
            private string _idleFenceToken;

            public int CloseCalls { get { return Volatile.Read(ref _closeCalls); } }

            public bool IsAvailable { get { return Available; } }
            public bool IsIdleForTrackedOpen
            {
                get { lock (_fenceSync) return Idle && _idleFenceToken == null; }
            }
            public string ActivePanelName { get { return ActiveName; } }
            public string ActivePanelInstanceId { get { return ActiveInstance; } }

            public bool TryAcquireIdleFence(string token)
            {
                lock (_fenceSync)
                {
                    if (!Idle || _idleFenceToken != null) return false;
                    _idleFenceToken = token;
                    return true;
                }
            }

            public bool ReleaseIdleFenceExact(string token)
            {
                lock (_fenceSync)
                {
                    if (_idleFenceToken != token) return false;
                    _idleFenceToken = null;
                    return true;
                }
            }

            public bool TryActivateOtherPanel(string panelName, string panelInstanceId)
            {
                lock (_fenceSync)
                {
                    if (_idleFenceToken != null) return false;
                    Idle = false;
                    ActiveName = panelName;
                    ActiveInstance = panelInstanceId;
                    return true;
                }
            }

            public bool TryOpenTracked(string initDataJson, string panelInstanceId,
                Func<bool> executionGate, Action<PanelHostController.TrackedOpenOutcome> completed)
            {
                OpenCalls++;
                InitDataJson = initDataJson;
                ReservedInstance = panelInstanceId;
                ExecutionGate = executionGate;
                OpenCompleted = completed;
                return QueueOpen;
            }

            public bool TryCloseExact(string panelInstanceId, Action<bool> completed)
            {
                Interlocked.Increment(ref _closeCalls);
                Assert.Equal(ReservedInstance, panelInstanceId);
                CloseCompleted = completed;
                return QueueClose;
            }

            public void CompleteOpenPosted()
            {
                Assert.True(ExecutionGate());
                ActiveName = "loot";
                ActiveInstance = ReservedInstance;
                OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            }
        }

        private static JObject Request(bool socketEnvelope = false, int openAttemptSeq = 1)
        {
            JObject request = new JObject
            {
                ["panel"] = "loot",
                ["source"] = "map_chest",
                ["initData"] = new JObject
                {
                    ["v"] = 1,
                    ["chestSessionId"] = "chest.session.1",
                    ["lootContainerId"] = "loot.container.1",
                    ["containerEpoch"] = 7,
                    ["openAttemptSeq"] = openAttemptSeq,
                    ["displayName"] = "装备箱",
                    ["capacity"] = 8,
                    ["columns"] = 4
                }
            };
            if (socketEnvelope) request.AddFirst(new JProperty("task", "panel_request"));
            return request;
        }

        private static LootPanelCoordinator Create(FakePanel panel, Func<bool> release = null,
            Func<LootPanelCoordinator.Binding, string, bool> recovery = null,
            int bindWatchdogMs = LootPanelCoordinator.DefaultBindWatchdogMs,
            int closeRetryDelayMs = LootPanelCoordinator.DefaultCloseRetryDelayMs,
            int closeRetryMaximumMs = LootPanelCoordinator.DefaultCloseRetryMaximumMs,
            int pauseReleaseRetryMs = LootPanelCoordinator.DefaultPauseReleaseRetryMs)
        {
            return new LootPanelCoordinator(panel, release,
                delegate { return "panel.loot.host.1"; }, recovery, bindWatchdogMs,
                closeRetryDelayMs, closeRetryMaximumMs, pauseReleaseRetryMs);
        }

        private static void WaitUntil(Func<bool> predicate, int timeoutMs = 1500)
        {
            Assert.True(SpinWait.SpinUntil(predicate, timeoutMs), "timed out waiting for state");
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void PanelRequest_StrictShape_QueuesTrackedOpenButDoesNotClaimBound(bool socketEnvelope)
        {
            var panel = new FakePanel();
            using var coordinator = Create(panel);

            JObject request = Request(socketEnvelope);
            Assert.Equal(8, ((JObject)request["initData"]).Count);
            JObject ack = JObject.Parse(coordinator.HandlePanelRequest(request));

            Assert.Equal(4, ack.Count);
            Assert.True((bool)ack["success"]);
            Assert.True((bool)ack["accepted"]);
            Assert.False((bool)ack["bound"]);
            Assert.Equal("loot", (string)ack["panel"]);
            Assert.Null(ack["error"]);
            Assert.Equal(LootPanelCoordinator.BindingState.OpenQueued, coordinator.State);
            Assert.Equal(1, panel.OpenCalls);
            JObject init = JObject.Parse(panel.InitDataJson);
            Assert.Equal(7, init.Count);
            Assert.Null(init["panelInstanceId"]);
            Assert.Null(init["openAttemptSeq"]);
            Assert.Equal("chest.session.1", (string)init["chestSessionId"]);
            Assert.Equal(1, coordinator.ActiveBinding.OpenAttemptSeq);
            JObject webOpen = JObject.Parse(PanelHostController.BuildPanelOpenPayload(
                "loot", panel.InitDataJson, "panel.loot.host.1"));
            JObject webInit = (JObject)webOpen["initData"];
            Assert.Equal(8, webInit.Count);
            Assert.Equal("panel.loot.host.1", webInit.Value<string>("panelInstanceId"));
            Assert.Null(webInit["openAttemptSeq"]);
        }

        [Fact]
        public void CharacterRecoveryGateRejectsLootBeforeQueueAndRechecksAtExecution()
        {
            var panel = new FakePanel();
            bool characterRecoveryClear = false;
            using var coordinator = Create(panel);
            coordinator.SetExternalAdmissionGate(
                delegate
                {
                    return characterRecoveryClear;
                });

            JObject rejected = JObject.Parse(
                coordinator.HandlePanelRequest(
                    Request()));
            Assert.False(
                rejected.Value<bool>("accepted"));
            Assert.Equal(
                "recovery_pending",
                rejected.Value<string>("error"));
            Assert.Equal(
                0,
                panel.OpenCalls);
            Assert.Equal(
                LootPanelCoordinator.BindingState.Idle,
                coordinator.State);

            characterRecoveryClear = true;
            JObject accepted = JObject.Parse(
                coordinator.HandlePanelRequest(
                    Request(openAttemptSeq: 2)));
            Assert.True(
                accepted.Value<bool>("accepted"));
            Assert.Equal(
                1,
                panel.OpenCalls);

            characterRecoveryClear = false;
            Assert.False(
                panel.ExecutionGate());
        }

        [Theory]
        [InlineData("source", "other")]
        [InlineData("panel", "workbench")]
        public void PanelRequest_WrongRoutingAnchor_IsRejected(string field, string value)
        {
            var panel = new FakePanel();
            using var coordinator = Create(panel);
            JObject request = Request();
            request[field] = value;

            JObject ack = JObject.Parse(coordinator.HandlePanelRequest(request));

            Assert.Equal(5, ack.Count);
            Assert.False((bool)ack["success"]);
            Assert.False((bool)ack["accepted"]);
            Assert.False((bool)ack["bound"]);
            Assert.Equal("loot", (string)ack["panel"]);
            Assert.Equal("invalid_request", (string)ack["error"]);
            Assert.Equal(0, panel.OpenCalls);
        }

        [Fact]
        public void PanelRequest_ExtraInitKey_IsRejected()
        {
            var panel = new FakePanel();
            using var coordinator = Create(panel);
            JObject request = Request();
            ((JObject)request["initData"])["reward"] = "forged";

            JObject ack = JObject.Parse(coordinator.HandlePanelRequest(request));

            Assert.False((bool)ack["accepted"]);
            Assert.Equal(0, panel.OpenCalls);
        }

        [Fact]
        public void PanelRequest_MissingOpenAttemptSeq_IsRejectedAsShapeDrift()
        {
            var panel = new FakePanel();
            using var coordinator = Create(panel);
            JObject request = Request();
            ((JObject)request["initData"]).Remove("openAttemptSeq");

            JObject ack = JObject.Parse(coordinator.HandlePanelRequest(request));

            Assert.False(ack.Value<bool>("accepted"));
            Assert.Equal("invalid_request", ack.Value<string>("error"));
            Assert.Equal(0, panel.OpenCalls);
        }

        [Fact]
        public void PanelRequest_OpenAttemptSeqMustBePositiveInt32()
        {
            JToken[] invalidValues =
            {
                new JValue(0),
                new JValue(-1),
                new JValue((long)int.MaxValue + 1L),
                JToken.Parse("999999999999999999999999999999999999999999"),
                new JValue(1.5),
                new JValue("1"),
                JValue.CreateNull()
            };
            foreach (JToken invalidValue in invalidValues)
            {
                var panel = new FakePanel();
                using var coordinator = Create(panel);
                JObject request = Request();
                request["initData"]["openAttemptSeq"] = invalidValue;

                JObject ack = JObject.Parse(coordinator.HandlePanelRequest(request));

                Assert.False(ack.Value<bool>("accepted"));
                Assert.Equal("invalid_request", ack.Value<string>("error"));
                Assert.Equal(0, panel.OpenCalls);
            }
        }

        [Fact]
        public void PanelRequest_GridCapabilityBoundaryMatchesAs2Contract()
        {
            LootPanelCoordinator.OpenRequest normalized;
            string error;

            JObject boundary = Request();
            boundary["initData"]["capacity"] = 64;
            boundary["initData"]["columns"] = 8;
            Assert.True(LootPanelCoordinator.TryNormalizePanelRequest(
                boundary, out normalized, out error));
            Assert.Equal(64, normalized.Capacity);
            Assert.Equal(8, normalized.Columns);

            JObject tooLarge = Request();
            tooLarge["initData"]["capacity"] = 65;
            Assert.False(LootPanelCoordinator.TryNormalizePanelRequest(
                tooLarge, out normalized, out error));

            JObject tooWide = Request();
            tooWide["initData"]["columns"] = 9;
            Assert.False(LootPanelCoordinator.TryNormalizePanelRequest(
                tooWide, out normalized, out error));
        }

        [Fact]
        public void TypedOpen_CannotBypassPositiveAttemptInvariant()
        {
            LootPanelCoordinator.OpenRequest normalized;
            string error;
            Assert.True(LootPanelCoordinator.TryNormalizePanelRequest(Request(),
                out normalized, out error));
            normalized.OpenAttemptSeq = 0;
            var panel = new FakePanel();
            using var coordinator = Create(panel);

            string rejection;
            Assert.False(coordinator.TryOpen(normalized, out rejection));

            Assert.Equal("invalid_request", rejection);
            Assert.Equal(0, panel.OpenCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
        }

        [Fact]
        public void WebBind_RequiresOpenPostedActivePanelAndAllExactIdentities()
        {
            var panel = new FakePanel();
            using var coordinator = Create(panel);
            coordinator.HandlePanelRequest(Request());
            LootPanelCoordinator.Binding ignored;

            Assert.False(coordinator.IsBoundVisualExact("panel.loot.host.1"));
            Assert.False(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out ignored));

            panel.CompleteOpenPosted();
            Assert.False(coordinator.IsBoundVisualExact("panel.loot.host.1"));
            Assert.False(coordinator.TryBindExact("panel.loot.host.1", "chest.session.stale",
                "loot.container.1", 7, out ignored));
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out ignored));
            Assert.Equal(LootPanelCoordinator.BindingState.Bound, coordinator.State);
            Assert.True(coordinator.IsBoundVisualExact("panel.loot.host.1"));
            Assert.False(coordinator.IsBoundVisualExact("panel.loot.stale"));
        }

        [Fact]
        public void AuthorityTerminal_QueuesOnlyExactTrackedClose_AndReleasesAfterPanelProof()
        {
            var panel = new FakePanel();
            int releases = 0;
            int detaches = 0;
            using var coordinator = Create(panel, delegate { releases++; return true; });
            coordinator.BindingDetached += delegate { detaches++; };
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Assert.True(coordinator.CloseAfterAuthorityTerminal(binding));
            Assert.Equal(LootPanelCoordinator.BindingState.TerminalCloseQueued, coordinator.State);
            Assert.Equal(1, panel.CloseCalls);
            Assert.Equal(0, releases);

            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.Equal(1, detaches);
            Assert.Equal(1, releases);
            Assert.True(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.host.1"));
            Assert.False(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.stale"));

            // A fresh accepted binding invalidates the previous idempotency proof even if a test
            // factory reuses the same opaque id; only the new flow may establish a terminal proof.
            Assert.True((bool)JObject.Parse(coordinator.HandlePanelRequest(Request()))["accepted"]);
            Assert.False(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.host.1"));
        }

        [Fact]
        public void AuthorityTerminalThenForceDetach_PreservesTerminalCloseAndSuppressesRecovery()
        {
            var panel = new FakePanel();
            int releases = 0;
            int recoveries = 0;
            using var coordinator = Create(panel,
                delegate { releases++; return true; },
                delegate { recoveries++; return true; });
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Assert.True(coordinator.CloseAfterAuthorityTerminal(binding));
            Assert.True(coordinator.ForceDetach("web_mount_failed"));

            Assert.Equal(LootPanelCoordinator.BindingState.TerminalCloseQueued,
                coordinator.State);
            Assert.Equal(1, panel.CloseCalls);
            Assert.Equal(0, recoveries);
            Assert.True(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.host.1"));
            Assert.False(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.stale"));

            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.Equal(1, releases);
            Assert.True(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.host.1"));
            Assert.False(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.stale"));
        }

        [Fact]
        public void AuthoritySuspended_QueuesExactClose_ReleasesPause_AndKeepsTypedProof()
        {
            var panel = new FakePanel();
            int releases = 0;
            using var coordinator = Create(panel, delegate { releases++; return true; });
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Assert.True(coordinator.CloseAfterAuthoritySuspended(binding));
            Assert.Equal(LootPanelCoordinator.BindingState.SuspendedCloseQueued,
                coordinator.State);
            Assert.Equal(1, panel.CloseCalls);
            Assert.True(coordinator.IsAuthoritySuspendedCloseKnownExact(
                "panel.loot.host.1"));
            Assert.False(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.host.1"));
            Assert.True(coordinator.IsAuthorityVisualCloseActiveExact(
                "panel.loot.host.1", "suspended"));
            Assert.False(coordinator.IsAuthorityVisualCloseActiveExact(
                "panel.loot.host.1", "terminal"));

            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.Equal(1, releases);
            Assert.True(coordinator.IsAuthorityVisualCloseKnownExact(
                "panel.loot.host.1", "suspended"));
            Assert.False(coordinator.IsAuthorityVisualCloseKnownExact(
                "panel.loot.host.1", "terminal"));

            Assert.True((bool)JObject.Parse(coordinator.HandlePanelRequest(Request()))["accepted"]);
            Assert.False(coordinator.IsAuthorityVisualCloseKnownExact(
                "panel.loot.host.1", "suspended"));
        }

        [Fact]
        public void AuthoritySuspendedThenForceDetach_PreservesSuspendAndSuppressesRecovery()
        {
            var panel = new FakePanel();
            int recoveries = 0;
            using var coordinator = Create(panel, null,
                delegate { recoveries++; return true; });
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Assert.True(coordinator.CloseAfterAuthoritySuspended(binding));
            Assert.True(coordinator.ForceDetach("web_mount_failed"));

            Assert.Equal(LootPanelCoordinator.BindingState.SuspendedCloseQueued,
                coordinator.State);
            Assert.Equal(0, recoveries);
            Assert.True(coordinator.IsAuthoritySuspendedCloseKnownExact(
                "panel.loot.host.1"));
        }

        [Fact]
        public void ForceDetachThenAuthoritySuspended_UpgradesWithoutChangingProofKind()
        {
            var panel = new FakePanel();
            int recoveries = 0;
            using var coordinator = Create(panel, null,
                delegate { recoveries++; return true; });
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Assert.True(coordinator.ForceDetach("web_mount_failed"));
            Assert.Equal(1, recoveries);
            Assert.True(coordinator.CloseAfterAuthoritySuspended(binding));

            Assert.Equal(LootPanelCoordinator.BindingState.SuspendedCloseQueued,
                coordinator.State);
            Assert.True(coordinator.IsAuthorityVisualCloseKnownExact(
                "panel.loot.host.1", "suspended"));
            Assert.False(coordinator.IsAuthorityVisualCloseKnownExact(
                "panel.loot.host.1", "terminal"));
            Assert.True(coordinator.ForceDetach("web_mount_failed"));
            Assert.Equal(1, recoveries);
        }

        [Fact]
        public void ForceDetachThenAuthorityTerminal_UpgradesAndKeepsTerminalProof()
        {
            var panel = new FakePanel();
            int recoveries = 0;
            using var coordinator = Create(panel, null,
                delegate { recoveries++; return true; });
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Assert.True(coordinator.ForceDetach("web_mount_failed"));
            Assert.Equal(LootPanelCoordinator.BindingState.ForceDetachQueued,
                coordinator.State);
            Assert.Equal(1, recoveries);
            Assert.False(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.host.1"));

            Assert.True(coordinator.CloseAfterAuthorityTerminal(binding));
            Assert.Equal(LootPanelCoordinator.BindingState.TerminalCloseQueued,
                coordinator.State);
            Assert.Equal(1, panel.CloseCalls);
            Assert.True(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.host.1"));
            Assert.False(coordinator.IsAuthorityTerminalCloseKnownExact(
                "panel.loot.stale"));

            // Once strict authority wins, a later visual detach cannot re-enter recovery.
            Assert.True(coordinator.ForceDetach("web_mount_failed"));
            Assert.Equal(LootPanelCoordinator.BindingState.TerminalCloseQueued,
                coordinator.State);
            Assert.Equal(1, recoveries);
        }

        [Fact]
        public void AuthorityTerminal_CloseQueueFailureStaysTerminalAndCanRetryExact()
        {
            var panel = new FakePanel { QueueClose = false };
            using var coordinator = Create(panel);
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Assert.False(coordinator.CloseAfterAuthorityTerminal(binding));
            Assert.Equal(LootPanelCoordinator.BindingState.TerminalCloseQueued,
                coordinator.State);
            panel.QueueClose = true;

            Assert.True(coordinator.RetryAuthorityTerminalCloseExact("panel.loot.host.1"));
            Assert.Equal(2, panel.CloseCalls);
            Assert.False(coordinator.RetryAuthorityTerminalCloseExact("panel.loot.stale"));
        }

        [Fact]
        public void ForceDetach_ClosesVisualBindingWithoutAuthorityCommand()
        {
            var panel = new FakePanel();
            int releases = 0;
            using var coordinator = Create(panel, delegate { releases++; return true; });
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Assert.True(coordinator.ForceDetach("web_navigation"));
            Assert.Equal(LootPanelCoordinator.BindingState.ForceDetachQueued, coordinator.State);
            Assert.Equal(1, panel.CloseCalls);
            Assert.Equal(0, releases);

            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Assert.Equal(1, releases);
            Assert.Null(coordinator.ActiveBinding);
        }

        [Fact]
        public void KnownPostFailure_ReleasesPauseAndReturnsIdle()
        {
            var panel = new FakePanel();
            int releases = 0;
            int recoveries = 0;
            using var coordinator = Create(panel, delegate { releases++; return true; },
                delegate(LootPanelCoordinator.Binding binding, string reason)
                {
                    Assert.Equal("panel.loot.host.1", binding.PanelInstanceId);
                    Assert.Equal("web_open_failed", reason);
                    recoveries++;
                    return true;
                });
            coordinator.HandlePanelRequest(Request());
            Assert.True(panel.ExecutionGate());

            panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.PostNotDelivered);

            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.Equal(1, releases);
            Assert.Equal(1, recoveries);
        }

        [Fact]
        public void AcceptedPreExecutionFailure_RecoversWithoutUnpause()
        {
            var panel = new FakePanel();
            int releases = 0;
            int recoveries = 0;
            using var coordinator = Create(panel, delegate { releases++; return true; },
                delegate(LootPanelCoordinator.Binding binding, string reason)
                {
                    Assert.Equal("chest.session.1", binding.ChestSessionId);
                    Assert.Equal("web_open_failed", reason);
                    recoveries++;
                    return true;
                });
            Assert.True(JObject.Parse(coordinator.HandlePanelRequest(Request()))
                .Value<bool>("accepted"));

            panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.PreExecutionRejected);

            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.Equal(0, releases);
            Assert.Equal(1, recoveries);
        }

        [Fact]
        public void BusyPanelAndSecondFlowFailClosed()
        {
            var panel = new FakePanel { Idle = false };
            using var coordinator = Create(panel);
            JObject first = JObject.Parse(coordinator.HandlePanelRequest(Request()));
            Assert.Equal("panel_busy", (string)first["error"]);

            panel.Idle = true;
            Assert.True((bool)JObject.Parse(coordinator.HandlePanelRequest(Request()))["accepted"]);
            JObject second = JObject.Parse(coordinator.HandlePanelRequest(Request()));
            Assert.False((bool)second["accepted"]);
        }

        [Fact]
        public void OpenQueuedBindWatchdog_RecoversExactObjectAndClearsWithoutUnpause()
        {
            var panel = new FakePanel();
            int releases = 0;
            int recoveries = 0;
            LootPanelCoordinator.Binding recovered = null;
            string recoveryReason = null;
            using var recoverySeen = new ManualResetEventSlim(false);
            using var coordinator = Create(panel,
                delegate { Interlocked.Increment(ref releases); return true; },
                delegate(LootPanelCoordinator.Binding binding, string reason)
                {
                    recovered = binding;
                    recoveryReason = reason;
                    Interlocked.Increment(ref recoveries);
                    recoverySeen.Set();
                    return true;
                }, bindWatchdogMs: 20, closeRetryDelayMs: 10,
                closeRetryMaximumMs: 20, pauseReleaseRetryMs: 10);

            Assert.True(JObject.Parse(coordinator.HandlePanelRequest(Request()))
                .Value<bool>("accepted"));
            Assert.True(recoverySeen.Wait(1500));
            WaitUntil(delegate { return coordinator.State == LootPanelCoordinator.BindingState.Idle; });

            Assert.Equal("web_mount_failed", recoveryReason);
            Assert.Equal("chest.session.1", recovered.ChestSessionId);
            Assert.Equal("loot.container.1", recovered.LootContainerId);
            Assert.Equal(7, recovered.ContainerEpoch);
            Assert.Equal(1, Volatile.Read(ref recoveries));
            Assert.Equal(0, Volatile.Read(ref releases));
            Assert.False(panel.ExecutionGate());

            panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.PreExecutionRejected);
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.Equal(1, Volatile.Read(ref recoveries));
        }

        [Fact]
        public void OpenPostedBindWatchdog_UsesExactCloseAndCancelsOnPanelClosed()
        {
            var panel = new FakePanel();
            int releases = 0;
            using var recoverySeen = new ManualResetEventSlim(false);
            using var coordinator = Create(panel,
                delegate { Interlocked.Increment(ref releases); return true; },
                delegate(LootPanelCoordinator.Binding binding, string reason)
                {
                    Assert.Equal("panel.loot.host.1", binding.PanelInstanceId);
                    Assert.Equal("web_mount_failed", reason);
                    recoverySeen.Set();
                    return true;
                }, bindWatchdogMs: 20, closeRetryDelayMs: 10,
                closeRetryMaximumMs: 20, pauseReleaseRetryMs: 10);
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();

            Assert.True(recoverySeen.Wait(1500));
            WaitUntil(delegate { return panel.CloseCalls >= 1; });
            Assert.Equal(LootPanelCoordinator.BindingState.ForceDetachQueued,
                coordinator.State);

            panel.ActiveName = null;
            panel.ActiveInstance = null;
            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.Equal(1, Volatile.Read(ref releases));
        }

        [Fact]
        public void ExactBind_CancelsBindWatchdog()
        {
            var panel = new FakePanel();
            int recoveries = 0;
            using var coordinator = Create(panel, null,
                delegate { Interlocked.Increment(ref recoveries); return true; },
                bindWatchdogMs: 20, closeRetryDelayMs: 10,
                closeRetryMaximumMs: 20, pauseReleaseRetryMs: 10);
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Thread.Sleep(80);

            Assert.Equal(LootPanelCoordinator.BindingState.Bound, coordinator.State);
            Assert.Equal(0, Volatile.Read(ref recoveries));
            Assert.Equal(0, panel.CloseCalls);
        }

        [Fact]
        public void Dispose_CancelsWatchdogsAndMakesCapturedGateStale()
        {
            var panel = new FakePanel();
            int recoveries = 0;
            var coordinator = Create(panel, null,
                delegate { Interlocked.Increment(ref recoveries); return true; },
                bindWatchdogMs: 20, closeRetryDelayMs: 10,
                closeRetryMaximumMs: 20, pauseReleaseRetryMs: 10);
            coordinator.HandlePanelRequest(Request());

            coordinator.Dispose();
            Thread.Sleep(80);

            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.Equal(0, Volatile.Read(ref recoveries));
            Assert.Equal(0, panel.CloseCalls);
            Assert.False(panel.ExecutionGate());
        }

        [Fact]
        public void TerminalClose_EnqueueAndCompletionFailuresRetryAutonomously()
        {
            var panel = new FakePanel { QueueClose = false };
            using var coordinator = Create(panel, null, null,
                bindWatchdogMs: 1000, closeRetryDelayMs: 15,
                closeRetryMaximumMs: 30, pauseReleaseRetryMs: 10);
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding binding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out binding));

            Assert.False(coordinator.CloseAfterAuthorityTerminal(binding));
            WaitUntil(delegate { return panel.CloseCalls >= 2; });
            panel.QueueClose = true;
            WaitUntil(delegate { return panel.CloseCalls >= 3; });
            Action<bool> failedCompletion = panel.CloseCompleted;
            Assert.NotNull(failedCompletion);
            failedCompletion(false);
            WaitUntil(delegate { return panel.CloseCalls >= 4; });

            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
        }

        [Fact]
        public void ForceDetach_CloseFailureRetriesUntilExactPanelProof()
        {
            var panel = new FakePanel { QueueClose = false };
            using var coordinator = Create(panel, null, null,
                bindWatchdogMs: 1000, closeRetryDelayMs: 15,
                closeRetryMaximumMs: 30, pauseReleaseRetryMs: 10);
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();

            Assert.True(coordinator.ForceDetach("socket_disconnected"));
            WaitUntil(delegate { return panel.CloseCalls >= 2; });
            Assert.Equal(LootPanelCoordinator.BindingState.ForceDetachQueued,
                coordinator.State);

            panel.ActiveName = null;
            panel.ActiveInstance = null;
            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
        }

        [Fact]
        public void PauseReleaseFailure_RetriesAndKeepsFlowOwnedUntilSuccess()
        {
            var panel = new FakePanel();
            int attempts = 0;
            int detaches = 0;
            using var coordinator = Create(panel,
                delegate { return Interlocked.Increment(ref attempts) >= 2; }, null,
                bindWatchdogMs: 1000, closeRetryDelayMs: 10,
                closeRetryMaximumMs: 20, pauseReleaseRetryMs: 10);
            coordinator.BindingDetached += delegate { Interlocked.Increment(ref detaches); };
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();

            panel.ActiveName = null;
            panel.ActiveInstance = null;
            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");

            Assert.Equal(LootPanelCoordinator.BindingState.PauseReleasePending,
                coordinator.State);
            Assert.NotNull(coordinator.ActiveBinding);
            WaitUntil(delegate { return coordinator.State == LootPanelCoordinator.BindingState.Idle; });
            Assert.True(Volatile.Read(ref attempts) >= 2);
            Assert.Equal(1, Volatile.Read(ref detaches));
        }

        [Fact]
        public void DetachedSettlement_WhenCoordinatorIdleNeverReleasesGlobalPause()
        {
            var panel = new FakePanel();
            int releases = 0;
            using var coordinator = Create(panel,
                delegate { Interlocked.Increment(ref releases); return true; }, null,
                bindWatchdogMs: 1000, pauseReleaseRetryMs: 1000);
            coordinator.HandlePanelRequest(Request());

            // The queued open never executed, so this binding never acquired the loot pause.
            Assert.True(coordinator.ForceDetach("socket_disconnected"));
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.False(coordinator.OnDetachedReconcileSettled());
            Assert.Equal(0, Volatile.Read(ref releases));

            Assert.True(panel.TryActivateOtherPanel("help", "panel.help.fresh"));
            Assert.False(coordinator.OnDetachedReconcileSettled());
            Assert.Equal(0, Volatile.Read(ref releases));
        }

        [Fact]
        public void DetachedSettlement_RetriesOnlyOwnedPauseBehindIdleFence()
        {
            var panel = new FakePanel();
            int releases = 0;
            bool allowRelease = false;
            bool otherPanelEntered = true;
            using var coordinator = Create(panel,
                delegate
                {
                    otherPanelEntered = panel.TryActivateOtherPanel(
                        "help", "panel.help.racing");
                    Interlocked.Increment(ref releases);
                    return allowRelease;
                }, null, bindWatchdogMs: 1000, pauseReleaseRetryMs: 1000);
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();
            panel.ActiveName = null;
            panel.ActiveInstance = null;
            panel.Idle = true;
            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Assert.Equal(LootPanelCoordinator.BindingState.PauseReleasePending,
                coordinator.State);
            Assert.False(otherPanelEntered);

            allowRelease = true;
            otherPanelEntered = true;
            Assert.True(coordinator.OnDetachedReconcileSettled());

            Assert.False(otherPanelEntered);
            Assert.Equal(2, Volatile.Read(ref releases));
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.True(panel.TryActivateOtherPanel("help", "panel.help.after"));
        }

        [Fact]
        public void OldPauseReleaseRetry_NeverUnpausesAnotherActivePanel()
        {
            var panel = new FakePanel();
            int releases = 0;
            using var coordinator = Create(panel,
                delegate { Interlocked.Increment(ref releases); return true; }, null,
                bindWatchdogMs: 1000, closeRetryDelayMs: 10,
                closeRetryMaximumMs: 20, pauseReleaseRetryMs: 10);
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();

            panel.ActiveName = "help";
            panel.ActiveInstance = "panel.help.2";
            panel.Idle = false;
            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Thread.Sleep(60);

            Assert.Equal(0, Volatile.Read(ref releases));
            Assert.Equal(LootPanelCoordinator.BindingState.PauseReleasePending,
                coordinator.State);

            panel.ActiveName = null;
            panel.ActiveInstance = null;
            panel.Idle = true;
            WaitUntil(delegate { return coordinator.State == LootPanelCoordinator.BindingState.Idle; });
            Assert.Equal(1, Volatile.Read(ref releases));
        }

        [Fact]
        public void PauseReleaseIdleFence_RejectsOpenInsideGateWriteWindow()
        {
            var panel = new FakePanel();
            int releases = 0;
            bool otherPanelEntered = true;
            using var coordinator = Create(panel,
                delegate
                {
                    otherPanelEntered = panel.TryActivateOtherPanel(
                        "help", "panel.help.racing");
                    Interlocked.Increment(ref releases);
                    return true;
                }, null, bindWatchdogMs: 1000, closeRetryDelayMs: 10,
                closeRetryMaximumMs: 20, pauseReleaseRetryMs: 10);
            coordinator.HandlePanelRequest(Request());
            panel.CompleteOpenPosted();

            panel.ActiveName = null;
            panel.ActiveInstance = null;
            panel.Idle = true;
            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");

            Assert.False(otherPanelEntered);
            Assert.Equal(1, Volatile.Read(ref releases));
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.True(panel.TryActivateOtherPanel("help", "panel.help.after"));
        }

        [Fact]
        public void FailedRecoverySend_IsClaimedOnceBeforeDisconnectReentrancy()
        {
            var panel = new FakePanel { QueueClose = false };
            int recoveries = 0;
            LootPanelCoordinator coordinator = null;
            coordinator = Create(panel, null,
                delegate
                {
                    Interlocked.Increment(ref recoveries);
                    Assert.True(coordinator.ForceDetach("socket_disconnected"));
                    return false;
                }, bindWatchdogMs: 1000, closeRetryDelayMs: 10,
                closeRetryMaximumMs: 20, pauseReleaseRetryMs: 10);
            using (coordinator)
            {
                coordinator.HandlePanelRequest(Request());
                panel.CompleteOpenPosted();

                Assert.True(coordinator.ForceDetach("web_mount_failed"));
                WaitUntil(delegate { return panel.CloseCalls >= 2; });
                Assert.True(coordinator.ForceDetach("web_mount_failed"));

                Assert.Equal(1, Volatile.Read(ref recoveries));
            }
        }

        [Fact]
        public async Task RecoveryInFlight_DefersOldFinalizeAndRejectsFreshOpenUntilDelegateReturns()
        {
            var panel = new FakePanel();
            using var recoveryEntered = new ManualResetEventSlim(false);
            using var releaseRecovery = new ManualResetEventSlim(false);
            int releases = 0;
            // The bind watchdog is orthogonal to this recovery-in-flight race. Keep it
            // outside the test's four-second assertion window so a saturated worker pool
            // cannot let the watchdog steal the manually triggered ForceDetach.
            using var coordinator = Create(panel,
                delegate { Interlocked.Increment(ref releases); return true; },
                delegate(LootPanelCoordinator.Binding binding, string reason)
                {
                    Assert.Equal(1, binding.OpenAttemptSeq);
                    Assert.Equal("web_mount_failed", reason);
                    recoveryEntered.Set();
                    Assert.True(releaseRecovery.Wait(2000));
                    return true;
                }, bindWatchdogMs: 30000);
            Assert.True(JObject.Parse(coordinator.HandlePanelRequest(
                Request(openAttemptSeq: 1))).Value<bool>("accepted"));
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding oldBinding = coordinator.ActiveBinding;

            Task forceDetach = Task.Run(delegate
            {
                Assert.True(coordinator.ForceDetach("web_mount_failed"));
            });
            Assert.True(recoveryEntered.Wait(2000));

            // The external delegate is blocked, yet coordinator APIs remain responsive because
            // it never runs under _sync.  Native close proof is remembered but cannot release the
            // old binding or admit a new same-triple attempt until that delegate returns.
            Assert.Equal(LootPanelCoordinator.BindingState.ForceDetachQueued,
                coordinator.State);
            panel.ActiveName = null;
            panel.ActiveInstance = null;
            coordinator.OnPanelHostClosed("loot", oldBinding.PanelInstanceId);
            Assert.Same(oldBinding, coordinator.ActiveBinding);
            JObject racingOpen = JObject.Parse(coordinator.HandlePanelRequest(
                Request(openAttemptSeq: 2)));
            Assert.False(racingOpen.Value<bool>("accepted"));
            Assert.Equal("flow_busy", racingOpen.Value<string>("error"));
            Assert.Equal(0, Volatile.Read(ref releases));

            releaseRecovery.Set();
            Assert.Same(forceDetach, await Task.WhenAny(forceDetach, Task.Delay(2000)));
            await forceDetach;
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);
            Assert.Null(coordinator.ActiveBinding);
            Assert.Equal(1, Volatile.Read(ref releases));

            JObject freshOpen = JObject.Parse(coordinator.HandlePanelRequest(
                Request(openAttemptSeq: 2)));
            Assert.True(freshOpen.Value<bool>("accepted"));
            Assert.Equal(2, coordinator.ActiveBinding.OpenAttemptSeq);
        }

        [Fact]
        public void RecoveryCommand_IsStrictExactEightKeyEnvelope()
        {
            var panel = new FakePanel();
            using var coordinator = Create(panel);
            coordinator.HandlePanelRequest(Request());
            LootPanelCoordinator.Binding binding = coordinator.ActiveBinding;

            JObject command = JObject.Parse(WebOverlayForm.BuildLootPanelRecoveryCommand(
                binding, "web_open_failed", "recovery.nonce.1"));

            Assert.Equal(new[] { "action", "chestSessionId", "containerEpoch",
                    "lootContainerId", "openAttemptSeq", "reason", "recoveryNonce", "task" },
                command.Properties().Select(p => p.Name).OrderBy(x => x).ToArray());
            Assert.Equal("cmd", command.Value<string>("task"));
            Assert.Equal("lootPanelRecovery", command.Value<string>("action"));
            Assert.Equal("chest.session.1", command.Value<string>("chestSessionId"));
            Assert.Equal("loot.container.1", command.Value<string>("lootContainerId"));
            Assert.Equal(7, command.Value<int>("containerEpoch"));
            Assert.Equal(1, command.Value<int>("openAttemptSeq"));
            Assert.Equal("recovery.nonce.1", command.Value<string>("recoveryNonce"));
            Assert.Equal("web_open_failed", command.Value<string>("reason"));
            Assert.Null(WebOverlayForm.BuildLootPanelRecoveryCommand(binding, "stale",
                "recovery.nonce.1"));
            Assert.Null(WebOverlayForm.BuildLootPanelRecoveryCommand(binding,
                "web_open_failed", "nonce with spaces"));
            Assert.NotNull(WebOverlayForm.BuildLootPanelRecoveryCommand(binding,
                "web_open_failed", "AZaz09._~-"));
            Assert.NotNull(WebOverlayForm.BuildLootPanelRecoveryCommand(binding,
                "web_open_failed", new string('n',
                    LootPanelCoordinator.MaximumOpaqueLength)));
            Assert.Null(WebOverlayForm.BuildLootPanelRecoveryCommand(binding,
                "web_open_failed", new string('n',
                    LootPanelCoordinator.MaximumOpaqueLength + 1)));
        }

        [Fact]
        public void StaleBindingRecoveryRetainsOldAttemptAndCannotAliasFreshSameTriple()
        {
            var panel = new FakePanel();
            using var coordinator = Create(panel, delegate { return true; });
            Assert.True(JObject.Parse(coordinator.HandlePanelRequest(
                Request(openAttemptSeq: 1))).Value<bool>("accepted"));
            panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding oldBinding;
            Assert.True(coordinator.TryBindExact("panel.loot.host.1", "chest.session.1",
                "loot.container.1", 7, out oldBinding));
            Assert.True(coordinator.CloseAfterAuthoritySuspended(oldBinding));
            coordinator.OnPanelHostClosed("loot", "panel.loot.host.1");
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, coordinator.State);

            Assert.True(JObject.Parse(coordinator.HandlePanelRequest(
                Request(openAttemptSeq: 2))).Value<bool>("accepted"));
            LootPanelCoordinator.Binding currentBinding = coordinator.ActiveBinding;
            Assert.NotSame(oldBinding, currentBinding);

            JObject staleRecovery = JObject.Parse(
                WebOverlayForm.BuildLootPanelRecoveryCommand(oldBinding, "web_open_failed",
                    "recovery.nonce.old"));
            JObject currentRecovery = JObject.Parse(
                WebOverlayForm.BuildLootPanelRecoveryCommand(currentBinding, "web_open_failed",
                    "recovery.nonce.current"));

            Assert.Equal("chest.session.1", staleRecovery.Value<string>("chestSessionId"));
            Assert.Equal(currentRecovery.Value<string>("chestSessionId"),
                staleRecovery.Value<string>("chestSessionId"));
            Assert.Equal(currentRecovery.Value<string>("lootContainerId"),
                staleRecovery.Value<string>("lootContainerId"));
            Assert.Equal(currentRecovery.Value<int>("containerEpoch"),
                staleRecovery.Value<int>("containerEpoch"));
            Assert.Equal(1, staleRecovery.Value<int>("openAttemptSeq"));
            Assert.Equal(2, currentRecovery.Value<int>("openAttemptSeq"));
            Assert.Equal("recovery.nonce.old", staleRecovery.Value<string>("recoveryNonce"));
            Assert.Equal("recovery.nonce.current",
                currentRecovery.Value<string>("recoveryNonce"));
        }
    }
}
