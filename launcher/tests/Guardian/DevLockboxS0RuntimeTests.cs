using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class DevLockboxS0RuntimeTests
    {
        private sealed class FakePanel : IDevLockboxS0PanelPort
        {
            public bool IsAvailableValue = true;
            public bool IsIdleValue = true;
            public string InitDataJson;
            public string ReservedInstance;
            public Func<bool> ExecutionGate;
            public Action<PanelHostController.TrackedOpenOutcome> OpenCompleted;
            public Action<bool> CloseCompleted;
            public int CloseAttempts;
            public bool OpenAccepted = true;
            public bool CloseAccepted = true;
            public bool CompleteCloseSynchronously;
            public bool SynchronousCloseResult = true;

            public bool IsAvailable { get { return IsAvailableValue; } }
            public bool IsIdleForTrackedOpen { get { return IsIdleValue; } }

            public bool TryOpenTracked(string initDataJson, string panelInstanceId,
                Func<bool> executionGate,
                Action<PanelHostController.TrackedOpenOutcome> completed)
            {
                InitDataJson = initDataJson;
                ReservedInstance = panelInstanceId;
                ExecutionGate = executionGate;
                OpenCompleted = completed;
                return OpenAccepted;
            }

            public bool TryCloseExact(string panelInstanceId, Action<bool> completed)
            {
                Assert.Equal(ReservedInstance, panelInstanceId);
                CloseAttempts += 1;
                CloseCompleted = completed;
                if (CompleteCloseSynchronously && completed != null)
                    completed(SynchronousCloseResult);
                return CloseAccepted;
            }
        }

        private sealed class Harness : IDisposable
        {
            public readonly FakePanel Panel = new FakePanel();
            public readonly List<JObject> Web = new List<JObject>();
            public readonly List<JObject> Socket = new List<JObject>();
            public readonly List<int> SocketGenerations = new List<int>();
            public readonly List<int> ReleaseGenerations = new List<int>();
            public DevLockboxS0Runtime.GameProcessIdentity Process =
                new DevLockboxS0Runtime.GameProcessIdentity(731, 987654321);
            public Func<DevLockboxS0Runtime.GameProcessIdentity?> ProcessProvider;
            public Func<int, bool> AcquireAction = _ => true;
            public bool Released;
            public Func<int, bool> ReleaseAction;
            public Func<JObject, bool> WebDelivery = _ => true;
            public Func<JObject, bool> SocketDelivery = _ => true;
            public readonly DevLockboxS0Runtime Runtime;
            private int _capabilitySequence;
            private int _flowSequence;
            private int _requestSequence;
            private int _panelSequence;

            public Harness(IDevLockboxS0PanelPort panel = null,
                int closeAckRetryMilliseconds = 2500,
                int bindTimeoutMilliseconds = 2500,
                int bindingAckTimeoutMilliseconds = 2500,
                Func<string> capabilityFactory = null)
            {
                ReleaseAction = delegate(int generation)
                {
                    ReleaseGenerations.Add(generation);
                    Released = true;
                    return true;
                };
                ProcessProvider = () => Process;
                Runtime = new DevLockboxS0Runtime(panel ?? Panel,
                    () => true,
                    () => "1",
                    () => ProcessProvider(),
                    delegate(string json, int generation)
                    {
                        JObject message = JObject.Parse(json);
                        lock (Socket)
                        {
                            Socket.Add(message);
                            SocketGenerations.Add(generation);
                        }
                        return SocketDelivery(message);
                    },
                    delegate(string json)
                    {
                        JObject message = JObject.Parse(json);
                        lock (Web) Web.Add(message);
                        return WebDelivery(message);
                    },
                    generation => AcquireAction(generation),
                    generation => ReleaseAction(generation),
                    initialDocumentEpoch: 11,
                    capabilityFactory: capabilityFactory ?? (() => ++_capabilitySequence == 1
                        ? "capability.host.generated.once"
                        : _capabilitySequence == 2
                            ? "capability.host.reconnect.two"
                            : "capability.host.generated." + _capabilitySequence),
                    flowHandleFactory: () => "flow.host." + ++_flowSequence,
                    requestTokenFactory: () => "request.host." + ++_requestSequence,
                    panelInstanceIdFactory: () => "panel.lockbox.host." + ++_panelSequence,
                    closeAckRetryMilliseconds: closeAckRetryMilliseconds,
                    bindTimeoutMilliseconds: bindTimeoutMilliseconds,
                    bindingAckTimeoutMilliseconds: bindingAckTimeoutMilliseconds);
            }

            public JObject ArmAndAcknowledge()
            {
                Runtime.OnSocketReady(7);
                JObject arm = Web[^1];
                Assert.Equal(DevLockboxS0Runtime.WebControlType, (string)arm["type"]);
                Assert.Equal("arm", (string)arm["cmd"]);
                JObject armed = (JObject)arm.DeepClone();
                armed["cmd"] = "armed";
                Assert.True(Runtime.TryHandleWebMessage(armed));
                Assert.Equal("devLockboxS0Bootstrap", (string)Socket[^1]["action"]);
                Assert.False((bool)Socket[^1]["resumeActive"]);

                AcknowledgeLastBootstrap(7);
                return (JObject)arm["payload"];
            }

            public void AcknowledgeLastBootstrap(int generation)
            {
                JObject command = Socket[^1];
                Assert.Equal("devLockboxS0Bootstrap", (string)command["action"]);
                JObject ackPayload = new JObject
                {
                    ["action"] = "bootstrap_ack",
                    ["protocolVersion"] = command["protocolVersion"].DeepClone(),
                    ["capability"] = command["capability"].DeepClone(),
                    ["connectionGeneration"] = command["connectionGeneration"].DeepClone(),
                    ["gameProcessId"] = command["gameProcessId"].DeepClone(),
                    ["documentEpoch"] = command["documentEpoch"].DeepClone(),
                    ["resumeActive"] = command["resumeActive"].DeepClone(),
                    ["source"] = command["source"].DeepClone(),
                    ["fixture"] = command["fixture"].DeepClone()
                };
                string ignored;
                Assert.True(Runtime.TryHandleSocketJson(new JObject
                {
                    ["task"] = DevLockboxS0Runtime.SocketTask,
                    ["payload"] = ackPayload
                }.ToString(), generation, out ignored));
                Assert.Null(ignored);
            }

            public JObject Begin(JObject armPayload, bool addExtra = false, int generation = 7)
            {
                JObject payload = new JObject
                {
                    ["action"] = "begin",
                    ["protocolVersion"] = 1,
                    ["capability"] = armPayload["capability"].DeepClone(),
                    ["sessionId"] = "chest-s0.session.1",
                    ["pauseAcquired"] = true,
                    ["source"] = "as2-chest-s0",
                    ["fixture"] = "insurance-safe-s0-v1"
                };
                if (addExtra) payload["forged"] = true;
                JObject request = new JObject
                {
                    ["task"] = DevLockboxS0Runtime.SocketTask,
                    ["callId"] = 41,
                    ["payload"] = payload
                };
                string response;
                Assert.True(Runtime.TryHandleSocketJson(request.ToString(), generation, out response));
                return JObject.Parse(response);
            }

            public int CountWeb(string command)
            {
                lock (Web) return Web.FindAll(message =>
                    (string)message["cmd"] == command).Count;
            }

            public int CountSocketAction(string action)
            {
                lock (Socket) return Socket.FindAll(message =>
                    (string)message["action"] == action).Count;
            }

            public void Dispose() { Runtime.Dispose(); }
        }

        [Fact]
        public void HappyPath_UsesSocketCapabilityTrackedPanelAuthorityAndExactClose()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            JObject begin = h.Begin(arm);
            Assert.True((bool)begin["success"]);
            Assert.True((bool)begin["accepted"]);
            Assert.Equal("flow.host.1", (string)begin["flowHandle"]);
            Assert.Equal("panel.lockbox.host.1", (string)begin["panelInstanceId"]);

            JObject init = JObject.Parse(h.Panel.InitDataJson);
            Assert.Equal(9, init.Count);
            Assert.Equal("capability.host.generated.once", (string)init["capability"]);
            Assert.Equal("flow.host.1", (string)init["flowHandle"]);
            Assert.Equal("panel.lockbox.host.1", (string)init["panelInstanceId"]);
            Assert.Null(init["requestToken"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);

            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));
            Assert.True(h.Runtime.HoldsGlobalPause);

            JObject result = WebIdentity();
            result["flowCallId"] = 1;
            result["result"] = "cancel";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", result)));
            Assert.Equal("devLockboxS0ApplyResult", (string)h.Socket[^1]["action"]);

            JObject authority = AuthorityBase("result_ack");
            authority["flowCallId"] = 1;
            authority["result"] = "cancel";
            authority["applied"] = true;
            authority["observedCallWatermark"] = 1;
            authority["authorityTerminal"] = true;
            authority["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = authority
            }.ToString(), 7, out ignored));
            Assert.Contains(h.Web, m => (string)m["cmd"] == "result_ack");
            Assert.Contains(h.Web, m => (string)m["cmd"] == "close_request");

            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void MalformedBegin_DoesNotConsumeCapability_ButValidBeginConsumesItOnce()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            JObject malformed = h.Begin(arm, addExtra: true);
            Assert.False((bool)malformed["success"]);
            Assert.Equal("schema_mismatch", (string)malformed["error"]);

            JObject valid = h.Begin(arm);
            Assert.True((bool)valid["success"]);
            JObject replay = h.Begin(arm);
            Assert.False((bool)replay["success"]);
            Assert.Equal("capability_rejected", (string)replay["error"]);
        }

        [Fact]
        public void MalformedDedicatedJson_IsConsumedBeforeGenericRawLogging()
        {
            using Harness h = new Harness();
            string response;
            Assert.True(h.Runtime.TryHandleSocketJson(
                "{\"task\":\"dev_lockbox_s0\",\"payload\":{\"capability\":\"secret",
                7, out response));
            Assert.Null(response);
        }

        [Fact]
        public void ProcessChangeBeforeQueueExecution_FailsClosedAndForwardsKnownOpenFailure()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            h.Process = new DevLockboxS0Runtime.GameProcessIdentity(999, 987654322);
            Assert.False(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.PreExecutionRejected);
            Assert.Equal("devLockboxS0OpenFailed", (string)h.Socket[^1]["action"]);
            Assert.Equal("pre_execution_rejected", (string)h.Socket[^1]["reason"]);
            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.False(h.Runtime.TryReleaseGenericPause());
        }

        [Fact]
        public void ProcessChangeAfterExecutionGate_ExpiresAndClosesTrackedOpen()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());

            h.Process = new DevLockboxS0Runtime.GameProcessIdentity(999, 987654322);
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);

            Assert.Equal(1, h.Panel.CloseAttempts);
            Assert.Contains(h.Web, message => (string)message["cmd"] == "authority_terminal"
                && (string)message["payload"]["terminal"] == "EXPIRED");
            Assert.Contains(h.Web, message => (string)message["cmd"] == "close_request");
            Assert.True(h.Runtime.HoldsGlobalPause);

            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void SynchronousNativeCloseCompletion_ReentersRuntimeWithoutOuterLockInversion()
        {
            using Harness h = new Harness();
            h.Panel.CompleteCloseSynchronously = true;
            h.ReleaseAction = delegate(int generation)
            {
                h.ReleaseGenerations.Add(generation);
                bool reentered = Task.Run(delegate
                {
                    h.Runtime.OnWebDocumentContentLoading(999);
                }).Wait(1000);
                h.Released = reentered;
                return reentered;
            };

            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject terminal = AuthorityBase("authority_terminal");
            terminal["flowCallId"] = 1;
            terminal["observedCallWatermark"] = 0;
            terminal["terminal"] = "EXPIRED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = terminal
            }.ToString(), 7, out ignored));

            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void ActiveReconnectProcessMismatch_ExpiresOldFlowWithoutResumeBootstrap()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));
            int bootstrapCount = h.CountSocketAction("devLockboxS0Bootstrap");

            h.Process = new DevLockboxS0Runtime.GameProcessIdentity(999, 987654322);
            h.Runtime.OnSocketReady(8);

            Assert.Equal(bootstrapCount, h.CountSocketAction("devLockboxS0Bootstrap"));
            Assert.Equal(1, h.Panel.CloseAttempts);
            Assert.Contains(h.Web, message => (string)message["cmd"] == "authority_terminal"
                && (string)message["payload"]["terminal"] == "EXPIRED");
            Assert.Contains(h.Web, message => (string)message["cmd"] == "close_request");
            Assert.True(h.Runtime.HoldsGlobalPause);

            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Equal(999, (int)h.Web[^1]["payload"]["gameProcessId"]);
        }

        [Fact]
        public void ProcessReplacementBeforeNonPostedCompletion_UsesTrackedNoDomProof()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.CloseAccepted = false;

            h.Process = new DevLockboxS0Runtime.GameProcessIdentity(999, 987654322);
            h.Runtime.OnSocketReady(8);
            Assert.False(h.Released);
            Assert.Equal(1, h.Panel.CloseAttempts);

            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.PostNotDelivered);
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void DisconnectBetweenExecutionGateAndOpenCompletionRetriesExactCloseAfterLeaseSettles()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.CloseAccepted = false;

            h.Runtime.OnSocketDisconnected(7);
            Assert.Equal(1, h.Panel.CloseAttempts);
            h.Panel.CloseAccepted = true;
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);

            Assert.Equal(2, h.Panel.CloseAttempts);
            Assert.NotNull(h.Panel.CloseCompleted);
            Assert.True(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public async Task GenericUnpauseWrite_IsLinearizedBeforeTrackedBegin()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            using ManualResetEventSlim unpauseWriteEntered = new ManualResetEventSlim(false);
            using ManualResetEventSlim allowUnpauseWrite = new ManualResetEventSlim(false);
            h.SocketDelivery = message =>
            {
                if ((string)message["action"] == "webPanelUnpause")
                {
                    unpauseWriteEntered.Set();
                    allowUnpauseWrite.Wait(1500);
                }
                return true;
            };

            Task<bool> generic = Task.Run(() => h.Runtime.TryReleaseGenericPause());
            Assert.True(unpauseWriteEntered.Wait(1500));
            Task<JObject> begin = Task.Run(() => h.Begin(arm));
            await Task.WhenAny(begin, Task.Delay(100));
            Assert.False(begin.IsCompleted);

            allowUnpauseWrite.Set();
            Assert.True(await generic);
            JObject beginResult = await begin;
            Assert.True((bool)beginResult["success"]);
            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.False(h.Runtime.TryReleaseGenericPause());
        }

        [Fact]
        public void PendingGenericUnpause_MustSucceedBeforeFreshArm()
        {
            using Harness h = new Harness();
            Assert.False(h.Runtime.TryReleaseGenericPause());
            h.SocketDelivery = message => (string)message["action"] != "webPanelUnpause";

            h.Runtime.OnSocketReady(7);
            Assert.Equal(0, h.CountWeb("arm"));
            Assert.Equal(1, h.CountSocketAction("webPanelUnpause"));

            h.Runtime.OnPanelHostOrchestrationSettled();
            Assert.Equal(0, h.CountWeb("arm"));
            Assert.Equal(2, h.CountSocketAction("webPanelUnpause"));

            h.SocketDelivery = _ => true;
            h.Runtime.OnPanelHostOrchestrationSettled();
            Assert.Equal(3, h.CountSocketAction("webPanelUnpause"));
            Assert.Equal(1, h.CountWeb("arm"));
        }

        [Fact]
        public void PendingGenericUnpause_WithReadyBindingRetriesWithoutReplacingCapability()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            h.SocketDelivery = message => (string)message["action"] != "webPanelUnpause";

            Assert.False(h.Runtime.TryReleaseGenericPause());
            Assert.Equal(1, h.CountSocketAction("webPanelUnpause"));
            Assert.Equal(1, h.CountWeb("arm"));

            h.Runtime.OnPanelHostOrchestrationSettled();
            Assert.Equal(2, h.CountSocketAction("webPanelUnpause"));
            Assert.Equal(1, h.CountWeb("arm"));
            Assert.False((bool)h.Begin(arm)["success"]);

            h.SocketDelivery = _ => true;
            h.Runtime.OnPanelHostOrchestrationSettled();
            Assert.Equal(3, h.CountSocketAction("webPanelUnpause"));
            Assert.Equal(1, h.CountWeb("arm"));
            Assert.True((bool)h.Begin(arm)["success"]);
        }

        [Fact]
        public void WireLoadingRejectionSchedulesFreshCapabilityRetry()
        {
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 20);
            h.Runtime.OnSocketReady(7);
            JObject firstArm;
            lock (h.Web) firstArm = h.Web.Last(message => (string)message["cmd"] == "arm");
            JObject rejected = (JObject)firstArm["payload"].DeepClone();
            rejected["code"] = "wire_loading";

            Assert.True(h.Runtime.TryHandleWebMessage(WebControl("rejected", rejected)));
            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("arm") >= 2, 1000));
            JObject retryArm;
            lock (h.Web) retryArm = h.Web.Last(message => (string)message["cmd"] == "arm");
            Assert.NotEqual((string)firstArm["payload"]["capability"],
                (string)retryArm["payload"]["capability"]);
            Assert.Equal(7, (int)retryArm["payload"]["connectionGeneration"]);
        }

        [Fact]
        public async Task BootstrapAckCommit_RechecksProcessAfterInitialValidation()
        {
            using Harness h = new Harness();
            DevLockboxS0Runtime.GameProcessIdentity originalProcess = h.Process;
            h.Runtime.OnSocketReady(7);
            JObject arm = h.Web[^1];
            JObject armed = (JObject)arm.DeepClone();
            armed["cmd"] = "armed";
            Assert.True(h.Runtime.TryHandleWebMessage(armed));
            JObject command = h.Socket[^1];
            JObject ackPayload = new JObject
            {
                ["action"] = "bootstrap_ack",
                ["protocolVersion"] = command["protocolVersion"].DeepClone(),
                ["capability"] = command["capability"].DeepClone(),
                ["connectionGeneration"] = command["connectionGeneration"].DeepClone(),
                ["gameProcessId"] = command["gameProcessId"].DeepClone(),
                ["documentEpoch"] = command["documentEpoch"].DeepClone(),
                ["resumeActive"] = command["resumeActive"].DeepClone(),
                ["source"] = command["source"].DeepClone(),
                ["fixture"] = command["fixture"].DeepClone()
            };
            JObject envelope = new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = ackPayload
            };
            using ManualResetEventSlim commitProcessCheck = new ManualResetEventSlim(false);
            using ManualResetEventSlim allowCommitCheck = new ManualResetEventSlim(false);
            int ackThreadId = 0;
            int processChecks = 0;
            h.ProcessProvider = delegate
            {
                if (Thread.CurrentThread.ManagedThreadId == Volatile.Read(ref ackThreadId)
                    && Interlocked.Increment(ref processChecks) == 2)
                {
                    commitProcessCheck.Set();
                    allowCommitCheck.Wait(1500);
                }
                return h.Process;
            };

            Task<bool> staleAck = Task.Run(() =>
            {
                Volatile.Write(ref ackThreadId, Thread.CurrentThread.ManagedThreadId);
                string response;
                bool handled = h.Runtime.TryHandleSocketJson(envelope.ToString(), 7, out response);
                Assert.Null(response);
                return handled;
            });
            Assert.True(commitProcessCheck.Wait(1500));
            h.Process = new DevLockboxS0Runtime.GameProcessIdentity(999, 987654322);
            allowCommitCheck.Set();
            Assert.True(await staleAck);

            h.Process = originalProcess;
            Assert.False((bool)h.Begin((JObject)arm["payload"])["success"]);
            h.AcknowledgeLastBootstrap(7);
            Assert.True((bool)h.Begin((JObject)arm["payload"])["success"]);
        }

        [Fact]
        public void StaleSocketReadyCannotRollBackGenerationOrCancelFreshBindingTimeout()
        {
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 40);
            h.Runtime.OnSocketReady(9);
            Assert.Equal(1, h.CountWeb("arm"));
            JObject firstArm;
            lock (h.Web) firstArm = h.Web.Last(message => (string)message["cmd"] == "arm");
            Assert.Equal(9, (int)firstArm["payload"]["connectionGeneration"]);

            h.Runtime.OnSocketReady(8);
            Assert.Equal(1, h.CountWeb("arm"));
            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("arm") >= 2, 1000));

            JObject retryArm;
            lock (h.Web) retryArm = h.Web.Last(message => (string)message["cmd"] == "arm");
            Assert.Equal(9, (int)retryArm["payload"]["connectionGeneration"]);
            Assert.NotEqual((string)firstArm["payload"]["capability"],
                (string)retryArm["payload"]["capability"]);
        }

        [Fact]
        public void DisconnectObservedBeforeReadyPermanentlyRejectsThatGeneration()
        {
            using Harness h = new Harness();
            h.Runtime.OnSocketDisconnected(7);
            h.Runtime.OnSocketReady(7);
            Assert.Equal(0, h.CountWeb("arm"));

            h.Runtime.OnSocketReady(8);
            Assert.Equal(1, h.CountWeb("arm"));
            Assert.Equal(8, (int)h.Web[^1]["payload"]["connectionGeneration"]);
        }

        [Fact]
        public void HigherDisconnectWithoutReadyInvalidatesOlderLiveBindingAndActivePanel()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            h.Runtime.OnSocketDisconnected(8);
            Assert.Equal(1, h.Panel.CloseAttempts);
            int bootstraps = h.CountSocketAction("devLockboxS0Bootstrap");
            h.Runtime.OnSocketReady(8);
            Assert.Equal(bootstraps, h.CountSocketAction("devLockboxS0Bootstrap"));

            h.Runtime.OnSocketReady(9);
            Assert.Equal(bootstraps + 1, h.CountSocketAction("devLockboxS0Bootstrap"));
            Assert.True((bool)h.Socket[^1]["resumeActive"]);
            Assert.Equal(9, (int)h.Socket[^1]["connectionGeneration"]);
        }

        [Fact]
        public async Task SupersededArmConstructionCannotCancelNewGenerationRetryOrPostStaleArm()
        {
            using ManualResetEventSlim oldCapabilityEntered = new ManualResetEventSlim(false);
            using ManualResetEventSlim releaseOldCapability = new ManualResetEventSlim(false);
            int capabilityCalls = 0;
            Func<string> capabilityFactory = delegate
            {
                int call = Interlocked.Increment(ref capabilityCalls);
                if (call == 1)
                {
                    oldCapabilityEntered.Set();
                    releaseOldCapability.Wait(5000);
                }
                return "capability.generation.race." + call;
            };
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 500,
                capabilityFactory: capabilityFactory);
            int armPosts = 0;
            h.WebDelivery = message => (string)message["cmd"] != "arm"
                || Interlocked.Increment(ref armPosts) > 1;

            Task oldReady = Task.Factory.StartNew(() => h.Runtime.OnSocketReady(8),
                CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            bool entered = oldCapabilityEntered.Wait(5000);
            if (!entered) releaseOldCapability.Set();
            Assert.True(entered);

            h.Runtime.OnSocketReady(9);
            Assert.Equal(1, h.CountWeb("arm"));
            releaseOldCapability.Set();
            await oldReady;

            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("arm") >= 2, 5000));
            JObject[] arms;
            lock (h.Web) arms = h.Web.Where(message => (string)message["cmd"] == "arm").ToArray();
            Assert.All(arms, arm => Assert.Equal(9,
                (int)arm["payload"]["connectionGeneration"]));
        }

        [Fact]
        public async Task DisposeDuringArmConstructionPreventsAnyLaterWebDispatch()
        {
            using ManualResetEventSlim capabilityEntered = new ManualResetEventSlim(false);
            using ManualResetEventSlim releaseCapability = new ManualResetEventSlim(false);
            using Harness h = new Harness(capabilityFactory: delegate
            {
                capabilityEntered.Set();
                releaseCapability.Wait(5000);
                return "capability.dispose.race";
            });

            Task ready = Task.Factory.StartNew(() => h.Runtime.OnSocketReady(7),
                CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            bool entered = capabilityEntered.Wait(5000);
            if (!entered) releaseCapability.Set();
            Assert.True(entered);

            h.Runtime.Dispose();
            releaseCapability.Set();
            await ready;
            Assert.Equal(0, h.CountWeb("arm"));
        }

        [Fact]
        public void PauseAcquireDeliveryFailure_RevokesBeforeEnqueueAndNeverReportsOpenSuccess()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            int acquireGeneration = 0;
            h.AcquireAction = generation =>
            {
                acquireGeneration = generation;
                return false;
            };

            JObject rejected = h.Begin(arm);
            Assert.False((bool)rejected["success"]);
            Assert.Equal("panel_enqueue_failed", (string)rejected["error"]);
            Assert.Equal(7, acquireGeneration);
            Assert.Null(h.Panel.ExecutionGate);
            Assert.Equal("devLockboxS0OpenFailed", (string)h.Socket[^1]["action"]);
            Assert.Equal("pre_execution_rejected", (string)h.Socket[^1]["reason"]);
            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.False(h.Released);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = revoked
            }.ToString(), 7, out ignored));
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Theory]
        [InlineData(PanelHostController.TrackedOpenOutcome.PostNotDelivered, false)]
        [InlineData(PanelHostController.TrackedOpenOutcome.PostAcceptedThenFailed, true)]
        public void TrackedOpenFailure_PhaseDeterminesWhetherExactDomProofIsRequired(
            PanelHostController.TrackedOpenOutcome outcome, bool requiresDomProof)
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(outcome);
            Assert.Equal("devLockboxS0OpenFailed", (string)h.Socket[^1]["action"]);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = revoked
            }.ToString(), 7, out ignored));
            Assert.Equal(!requiresDomProof, h.Released);

            if (requiresDomProof)
            {
                Assert.Contains(h.Web, message => (string)message["cmd"] == "close_request");
                Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
                Assert.True(h.Released);
            }
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void ResultPendingDisconnect_RecordsFirstExactCloseAndReleasesAfterNewGenerationQuery()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject result = WebIdentity();
            result["flowCallId"] = 1;
            result["result"] = "cancel";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", result)));
            Assert.Equal("devLockboxS0ApplyResult", (string)h.Socket[^1]["action"]);
            Assert.Equal(7, h.SocketGenerations[^1]);

            h.Runtime.OnSocketDisconnected(7);
            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.False(h.Released);
            JObject teardown = (JObject)arm.DeepClone();
            teardown["reason"] = "force_close";
            Assert.True(h.Runtime.TryHandleWebMessage(WebControl("teardown_ack", teardown)));
            Assert.False(h.Released);
            int webMessageCountBeforeReconnect = h.Web.Count;

            h.Runtime.OnSocketReady(8);
            JObject reconnectBootstrap = h.Socket[^1];
            Assert.Equal("devLockboxS0Bootstrap", (string)reconnectBootstrap["action"]);
            Assert.Equal(8, (int)reconnectBootstrap["connectionGeneration"]);
            Assert.Equal("capability.host.reconnect.two", (string)reconnectBootstrap["capability"]);
            Assert.True((bool)reconnectBootstrap["resumeActive"]);
            Assert.Equal(8, h.SocketGenerations[^1]);
            Assert.Equal(webMessageCountBeforeReconnect, h.Web.Count);
            h.AcknowledgeLastBootstrap(8);
            Assert.Equal("devLockboxS0QueryResult", (string)h.Socket[^1]["action"]);
            Assert.Equal(8, h.SocketGenerations[^1]);

            JObject queryReply = AuthorityBase("result_query_reply");
            queryReply["flowCallId"] = 1;
            queryReply["observedCallWatermark"] = 1;
            queryReply["disposition"] = "cancel";
            queryReply["authorityTerminal"] = true;
            queryReply["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = queryReply
            }.ToString(), 8, out ignored));
            Assert.Contains(h.Web, m => (string)m["cmd"] == "reconcile_reply");
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.True(h.Runtime.TryReleaseGenericPause());
        }

        [Fact]
        public void AuthorityExpiredBeforeResult_AcceptsZeroWatermarkAndClosesExactly()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            }.ToString(), 7, out ignored));
            Assert.Contains(h.Web, m => (string)m["cmd"] == "authority_terminal");
            Assert.Contains(h.Web, m => (string)m["cmd"] == "close_request");

            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void LostWebCloseAck_IsQueriedUntilExactAckArrives()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 20);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            }.ToString(), 7, out ignored));
            int messagesBeforeRetry = h.Web.Count;
            JObject closeQuery = null;
            Assert.True(SpinWait.SpinUntil(delegate
            {
                lock (h.Web)
                {
                    for (int index = messagesBeforeRetry; index < h.Web.Count; index += 1)
                    {
                        if ((string)h.Web[index]["cmd"] != "close_query") continue;
                        closeQuery = h.Web[index];
                        return true;
                    }
                }
                return false;
            }, 1000));
            Assert.NotNull(closeQuery);
            Assert.Equal(WebIdentity(), closeQuery["payload"]);

            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void RuntimeRejection_CannotClearConsumedBinding_AndNeedsWebAndNativeCloseProofs()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);

            JObject staleArmRejection = (JObject)arm.DeepClone();
            staleArmRejection["code"] = "wire_not_dormant";
            Assert.True(h.Runtime.TryHandleWebMessage(
                WebControl("rejected", staleArmRejection)));

            JObject runtimeRejection = (JObject)arm.DeepClone();
            runtimeRejection["code"] = "dom_bind_not_committed";
            Assert.True(h.Runtime.TryHandleWebMessage(
                WebControl("runtime_rejected", runtimeRejection)));
            Assert.Equal("devLockboxS0OpenFailed", (string)h.Socket[^1]["action"]);
            Assert.Equal("web_bind_rejected", (string)h.Socket[^1]["reason"]);

            JObject teardown = (JObject)arm.DeepClone();
            teardown["reason"] = "runtime_rejected";
            Assert.True(h.Runtime.TryHandleWebMessage(WebControl("teardown_ack", teardown)));
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.False(h.Released);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = revoked
            }.ToString(), 7, out ignored));
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void ActiveNavigation_PreResultRevokesWithoutWriteAndReleasesAfterNativeClose()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            h.Runtime.OnWebDocumentNavigationStarting(1001);
            h.Runtime.OnWebDocumentContentLoading(1001);
            h.Runtime.OnWebDocumentNavigationCompleted(1001, true);
            Assert.Equal(12, h.Runtime.DocumentEpoch);
            Assert.Equal("devLockboxS0OpenFailed", (string)h.Socket[^1]["action"]);
            Assert.Equal("web_bind_rejected", (string)h.Socket[^1]["reason"]);
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.False(h.Released);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = revoked
            }.ToString(), 7, out ignored));
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Contains(h.Web, message => (string)message["cmd"] == "arm"
                && (long)message["payload"]["documentEpoch"] == 12);
        }

        [Fact]
        public void ActiveNavigation_PostResultQueriesCausallyAndNeverResendsTheWrite()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject result = WebIdentity();
            result["flowCallId"] = 1;
            result["result"] = "cancel";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", result)));
            Assert.Single(h.Socket.FindAll(message =>
                (string)message["action"] == "devLockboxS0ApplyResult"));

            h.Runtime.OnWebDocumentNavigationStarting(1002);
            h.Runtime.OnWebDocumentContentLoading(1002);
            h.Runtime.OnWebDocumentNavigationCompleted(1002, true);
            Assert.Equal("devLockboxS0QueryResult", (string)h.Socket[^1]["action"]);
            Assert.Equal(1, (int)h.Socket[^1]["unknownFlowCallId"]);
            Assert.Single(h.Socket.FindAll(message =>
                (string)message["action"] == "devLockboxS0ApplyResult"));
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);

            JObject reply = AuthorityBase("result_query_reply");
            reply["flowCallId"] = 1;
            reply["observedCallWatermark"] = 1;
            reply["disposition"] = "cancel";
            reply["authorityTerminal"] = true;
            reply["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = reply
            }.ToString(), 7, out ignored));
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void FailedMismatchedAndSameDocumentNavigation_NeverProveOldDomTeardown()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));
            Assert.False(h.Runtime.CanRebuildWebDocument);

            h.Runtime.OnWebDocumentNavigationStarting(2001);
            h.Runtime.OnWebDocumentNavigationCompleted(9999, true);
            Assert.Equal(11, h.Runtime.DocumentEpoch);
            Assert.True(h.Runtime.HoldsGlobalPause);
            h.Runtime.OnWebDocumentNavigationCompleted(2001, false);
            Assert.Equal(11, h.Runtime.DocumentEpoch);
            Assert.True(h.Runtime.HoldsGlobalPause);

            h.Runtime.OnWebDocumentNavigationStarting(2002);
            h.Runtime.OnWebDocumentNavigationCompleted(2002, true);
            Assert.Equal(11, h.Runtime.DocumentEpoch);
            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.Null(h.Panel.CloseCompleted);
            Assert.DoesNotContain(h.Socket, message =>
                (string)message["action"] == "devLockboxS0OpenFailed");
        }

        [Fact]
        public void NavigationPending_InvalidatesUnusedCapabilityAndRearmsFreshAfterCompletion()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();

            h.Runtime.OnWebDocumentNavigationStarting(3001);
            JObject rejected = h.Begin(arm);
            Assert.False((bool)rejected["success"]);
            Assert.Equal("web_navigation_pending", (string)rejected["error"]);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Null(h.Panel.ExecutionGate);

            h.Runtime.OnWebDocumentContentLoading(3001);
            h.Runtime.OnWebDocumentNavigationCompleted(3001, true);
            Assert.Equal(12, h.Runtime.DocumentEpoch);
            Assert.Equal(2, h.CountWeb("arm"));
            JObject freshArm = (JObject)h.Web[^1]["payload"];
            Assert.NotEqual((string)arm["capability"], (string)freshArm["capability"]);
            Assert.Equal(12, (long)freshArm["documentEpoch"]);

            JObject replay = h.Begin(arm);
            Assert.False((bool)replay["success"]);
            Assert.Equal("capability_rejected", (string)replay["error"]);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void ResumeActiveCapability_CannotBeConsumedByBeginAndStillAcceptsAuthority()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            h.Runtime.OnSocketDisconnected(7);
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            h.Runtime.OnSocketReady(8);
            JObject reconnect = h.Socket[^1];
            Assert.Equal("devLockboxS0Bootstrap", (string)reconnect["action"]);
            Assert.True((bool)reconnect["resumeActive"]);
            h.AcknowledgeLastBootstrap(8);

            JObject rejected = h.Begin(reconnect, false, 8);
            Assert.False((bool)rejected["success"]);
            Assert.Equal("capability_rejected", (string)rejected["error"]);
            Assert.True(h.Runtime.HoldsGlobalPause);

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            }.ToString(), 8, out ignored));
            Assert.Contains(h.Web, message => (string)message["cmd"] == "authority_terminal");
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void BindQueryDeliveryLoss_ReconcileTickRetriesUntilExactBoundReply()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 20,
                bindTimeoutMilliseconds: 20);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);

            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("bind_query") >= 2, 1000));
            JObject bound = WebIdentity();
            bound["binding"] = "bound";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind_query_result", bound)));

            JObject result = WebIdentity();
            result["flowCallId"] = 1;
            result["result"] = "cancel";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", result)));
            Assert.Equal(1, h.CountSocketAction("devLockboxS0ApplyResult"));
        }

        [Fact]
        public void LateOriginalBindAckAfterTimeout_CannotStopExactQueryReconcile()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 20,
                bindTimeoutMilliseconds: 20);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("bind_query") >= 2, 1000));
            int queriesBeforeLateAck = h.CountWeb("bind_query");

            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));
            Assert.True(SpinWait.SpinUntil(
                () => h.CountWeb("bind_query") > queriesBeforeLateAck, 1000));

            JObject prematureResult = WebIdentity();
            prematureResult["flowCallId"] = 1;
            prematureResult["result"] = "cancel";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", prematureResult)));
            Assert.Equal(0, h.CountSocketAction("devLockboxS0ApplyResult"));

            JObject bound = WebIdentity();
            bound["binding"] = "bound";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind_query_result", bound)));
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", prematureResult)));
            Assert.Equal(1, h.CountSocketAction("devLockboxS0ApplyResult"));
        }

        [Fact]
        public void ResultWriteDeliveryUnknown_HostQueriesWithoutDependingOnWebQueryDelivery()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 20);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));
            h.SocketDelivery = message =>
                (string)message["action"] != "devLockboxS0ApplyResult";

            JObject result = WebIdentity();
            result["flowCallId"] = 1;
            result["result"] = "cancel";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", result)));
            Assert.Equal(1, h.CountSocketAction("devLockboxS0ApplyResult"));
            Assert.True(h.CountSocketAction("devLockboxS0QueryResult") >= 1);

            JObject reply = AuthorityBase("result_query_reply");
            reply["flowCallId"] = 1;
            reply["observedCallWatermark"] = 1;
            reply["disposition"] = "cancel";
            reply["authorityTerminal"] = true;
            reply["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = reply
            }.ToString(), 7, out ignored));
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            h.Panel.CloseCompleted(true);
            Assert.True(h.Released);
        }

        [Fact]
        public void LostTerminalProjection_IsReplayedBeforeExactCloseQuery()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 20);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));
            int terminalDeliveries = 0;
            h.WebDelivery = message =>
            {
                if ((string)message["cmd"] != "authority_terminal") return true;
                terminalDeliveries += 1;
                return terminalDeliveries > 1;
            };

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            }.ToString(), 7, out ignored));
            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("authority_terminal") >= 2
                && h.CountWeb("close_query") >= 1, 1000));
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            h.Panel.CloseCompleted(true);
            Assert.True(h.Released);
        }

        [Theory]
        [InlineData("COMPLETED_NO_REWARD")]
        [InlineData("EXPIRED")]
        public void ResultAppliedTerminalPoll_PreservesTerminalKindWithoutReplayingTheWrite(
            string terminalState)
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 20);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject result = WebIdentity();
            result["flowCallId"] = 1;
            result["result"] = "success";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", result)));
            JObject ack = AuthorityBase("result_ack");
            ack["flowCallId"] = 1;
            ack["result"] = "success";
            ack["applied"] = true;
            ack["observedCallWatermark"] = 1;
            ack["authorityTerminal"] = false;
            ack["authorityState"] = "OPENING_ANIMATION";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = ack
            }.ToString(), 7, out ignored));
            Assert.True(SpinWait.SpinUntil(() =>
                h.CountSocketAction("devLockboxS0QueryResult") >= 1, 1000));
            Assert.Equal(1, h.CountSocketAction("devLockboxS0ApplyResult"));

            JObject terminal = AuthorityBase("result_query_reply");
            terminal["flowCallId"] = 1;
            terminal["observedCallWatermark"] = 1;
            terminal["disposition"] = "success";
            terminal["authorityTerminal"] = true;
            terminal["authorityState"] = terminalState;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = terminal
            }.ToString(), 7, out ignored));
            Assert.Equal(1, h.CountSocketAction("devLockboxS0ApplyResult"));
            JObject projection = h.Web.Last(message =>
                (string)message["cmd"] == "authority_terminal");
            Assert.Equal(terminalState, (string)projection["payload"]["terminal"]);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            h.Panel.CloseCompleted(true);
            Assert.True(h.Released);
        }

        [Fact]
        public void SuccessAuthorityStateMapping_RejectsRevokedAckAndTerminalPoll()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject result = WebIdentity();
            result["flowCallId"] = 1;
            result["result"] = "success";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", result)));

            JObject invalidAck = AuthorityBase("result_ack");
            invalidAck["flowCallId"] = 1;
            invalidAck["result"] = "success";
            invalidAck["applied"] = true;
            invalidAck["observedCallWatermark"] = 1;
            invalidAck["authorityTerminal"] = true;
            invalidAck["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = invalidAck
            }.ToString(), 7, out ignored));
            Assert.Equal(0, h.CountWeb("result_ack"));

            JObject opening = (JObject)invalidAck.DeepClone();
            opening["authorityTerminal"] = false;
            opening["authorityState"] = "OPENING_ANIMATION";
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = opening
            }.ToString(), 7, out ignored));
            Assert.Equal(1, h.CountWeb("result_ack"));

            JObject invalidPoll = AuthorityBase("result_query_reply");
            invalidPoll["flowCallId"] = 1;
            invalidPoll["observedCallWatermark"] = 1;
            invalidPoll["disposition"] = "success";
            invalidPoll["authorityTerminal"] = true;
            invalidPoll["authorityState"] = "REVOKED";
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = invalidPoll
            }.ToString(), 7, out ignored));
            Assert.Equal(0, h.CountWeb("authority_terminal"));
            Assert.True(h.Runtime.HoldsGlobalPause);

            using Harness reconcile = new Harness();
            JObject reconcileArm = reconcile.ArmAndAcknowledge();
            Assert.True((bool)reconcile.Begin(reconcileArm)["success"]);
            Assert.True(reconcile.Panel.ExecutionGate());
            reconcile.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(reconcile.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));
            reconcile.SocketDelivery = message =>
                (string)message["action"] != "devLockboxS0ApplyResult";
            JObject cancel = WebIdentity();
            cancel["flowCallId"] = 1;
            cancel["result"] = "cancel";
            Assert.True(reconcile.Runtime.TryHandleWebMessage(WebBusiness("result", cancel)));

            foreach (string disposition in new[] { "cancel", "failure", "not_applied" })
            {
                JObject malformed = AuthorityBase("result_query_reply");
                malformed["flowCallId"] = 1;
                malformed["observedCallWatermark"] = 1;
                malformed["disposition"] = disposition;
                malformed["authorityTerminal"] = true;
                malformed["authorityState"] = "EXPIRED";
                Assert.True(reconcile.Runtime.TryHandleSocketJson(new JObject
                {
                    ["task"] = DevLockboxS0Runtime.SocketTask,
                    ["payload"] = malformed
                }.ToString(), 7, out ignored));
            }
            Assert.Equal(0, reconcile.CountWeb("reconcile_reply"));
            Assert.True(reconcile.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void NativeExactClose_FirstFailureIsRetriedByReconcileTick()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 20);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            }.ToString(), 7, out ignored));
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.Equal(1, h.Panel.CloseAttempts);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.Equal(1, h.Panel.CloseAttempts);
            h.Panel.CloseCompleted(false);
            Assert.True(SpinWait.SpinUntil(() => h.Panel.CloseAttempts >= 2, 1000));
            h.Panel.CloseCompleted(true);
            Assert.True(h.Released);
        }

        [Fact]
        public async Task AuthorityActionInFlight_BlocksReleaseAndFreshIdentitySubstitution()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            string ignored;
            JObject envelope = new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            };
            Assert.True(h.Runtime.TryHandleSocketJson(envelope.ToString(), 7, out ignored));
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.Equal(1, h.Panel.CloseAttempts);

            using ManualResetEventSlim authorityProcessCheck = new ManualResetEventSlim(false);
            using ManualResetEventSlim allowAuthority = new ManualResetEventSlim(false);
            int authorityThreadId = 0;
            h.ProcessProvider = delegate
            {
                if (Thread.CurrentThread.ManagedThreadId == Volatile.Read(ref authorityThreadId))
                {
                    authorityProcessCheck.Set();
                    allowAuthority.Wait(1500);
                }
                return h.Process;
            };
            Task<bool> duplicate = Task.Run(() =>
            {
                Volatile.Write(ref authorityThreadId, Thread.CurrentThread.ManagedThreadId);
                string response;
                return h.Runtime.TryHandleSocketJson(envelope.ToString(), 7, out response);
            });
            Assert.True(authorityProcessCheck.Wait(1500));

            h.Panel.CloseCompleted(true);
            Assert.False(h.Released);
            Assert.True(h.Runtime.HoldsGlobalPause);

            allowAuthority.Set();
            Assert.True(await duplicate);
            Assert.True(SpinWait.SpinUntil(() => h.Released && !h.Runtime.HoldsGlobalPause, 1500));
            Assert.Equal(2, h.CountWeb("arm"));
        }

        [Fact]
        public void MalformedAuthorityBinding_DoesNotLeakInFlightOrBlockValidTerminalRelease()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject resultAck = AuthorityBase("result_ack");
            resultAck["flowCallId"] = 1;
            resultAck["result"] = "success";
            resultAck["applied"] = true;
            resultAck["observedCallWatermark"] = 1;
            resultAck["authorityTerminal"] = false;
            resultAck["authorityState"] = "OPENING_ANIMATION";

            JObject queryReply = AuthorityBase("result_query_reply");
            queryReply["flowCallId"] = 1;
            queryReply["observedCallWatermark"] = 1;
            queryReply["disposition"] = "success";
            queryReply["authorityTerminal"] = false;
            queryReply["authorityState"] = "OPENING_ANIMATION";

            JObject revocationAck = AuthorityBase("revocation_ack");
            revocationAck["observedCallWatermark"] = 1;
            revocationAck["authorityState"] = "REVOKED";

            JObject terminalBase = AuthorityBase("authority_terminal");
            terminalBase["flowCallId"] = 1;
            terminalBase["observedCallWatermark"] = 0;
            terminalBase["terminal"] = "EXPIRED";

            List<JObject> malformedPayloads = new List<JObject>
            {
                MutatedAuthority(terminalBase, "protocolVersion", new JValue("bad")),
                MutatedAuthority(terminalBase, "documentEpoch", new JValue(ulong.MaxValue)),
                MutatedAuthority(resultAck, "flowCallId", new JValue("1")),
                MutatedAuthority(resultAck, "observedCallWatermark", new JValue(true)),
                MutatedAuthority(resultAck, "applied", new JValue("true")),
                MutatedAuthority(resultAck, "authorityTerminal", new JValue(1)),
                MutatedAuthority(queryReply, "flowCallId", new JArray()),
                MutatedAuthority(queryReply, "observedCallWatermark", new JValue("1")),
                MutatedAuthority(queryReply, "authorityTerminal", new JValue("false")),
                MutatedAuthority(revocationAck, "observedCallWatermark", new JValue("1")),
                MutatedAuthority(terminalBase, "flowCallId", new JValue("1")),
                MutatedAuthority(terminalBase, "observedCallWatermark", new JValue(false))
            };
            string ignored = null;
            foreach (JObject malformed in malformedPayloads)
            {
                Exception failure = Record.Exception(() =>
                    Assert.True(h.Runtime.TryHandleSocketJson(new JObject
                    {
                        ["task"] = DevLockboxS0Runtime.SocketTask,
                        ["payload"] = malformed
                    }.ToString(), 7, out ignored)));
                Assert.Null(failure);
                Assert.True(h.Runtime.HoldsGlobalPause);
            }
            Assert.True(h.Runtime.HoldsGlobalPause);

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            }.ToString(), 7, out ignored));
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.Equal(1, h.Panel.CloseAttempts);
            h.Panel.CloseCompleted(true);

            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Equal(2, h.CountWeb("arm"));
        }

        [Fact]
        public void LateTrackedOpenCompletion_CannotPolluteFreshArmOrSendOldFailure()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Action<PanelHostController.TrackedOpenOutcome> oldCompletion = h.Panel.OpenCompleted;

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            }.ToString(), 7, out ignored));
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            h.Runtime.OnPanelHostClosed("lockbox", "panel.lockbox.host.1");
            Assert.True(h.Released);
            Assert.Equal(2, h.CountWeb("arm"));
            int failuresBefore = h.CountSocketAction("devLockboxS0OpenFailed");

            oldCompletion(PanelHostController.TrackedOpenOutcome.PreExecutionRejected);
            Assert.Equal(failuresBefore, h.CountSocketAction("devLockboxS0OpenFailed"));
            Assert.Equal(2, h.CountWeb("arm"));
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void PauseReleaseFailure_RetainsTerminalFlowAndRetriesBeforeFreshArm()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));
            int releaseAttempts = 0;
            h.ReleaseAction = delegate(int generation)
            {
                h.ReleaseGenerations.Add(generation);
                releaseAttempts += 1;
                if (releaseAttempts == 1) return false;
                h.Released = true;
                return true;
            };

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            }.ToString(), 7, out ignored));
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            int armCountBeforeRelease = h.CountWeb("arm");
            h.Panel.CloseCompleted(true);
            h.Runtime.OnPanelHostClosed("lockbox", "panel.lockbox.host.1");

            Assert.Equal(1, releaseAttempts);
            Assert.False(h.Released);
            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.Equal(armCountBeforeRelease, h.CountWeb("arm"));
            Assert.True(SpinWait.SpinUntil(() => h.Released
                && !h.Runtime.HoldsGlobalPause
                && h.CountWeb("arm") == armCountBeforeRelease + 1, 1500));
            Assert.True(releaseAttempts >= 2);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Equal(armCountBeforeRelease + 1, h.CountWeb("arm"));
        }

        [Fact]
        public void InFlightReconcile_CannotEmitOldIdentityAfterFreshArm()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 20);
            using ManualResetEventSlim retryEntered = new ManualResetEventSlim(false);
            using ManualResetEventSlim allowRetry = new ManualResetEventSlim(false);
            int terminalDeliveries = 0;
            h.WebDelivery = message =>
            {
                if ((string)message["cmd"] == "authority_terminal"
                    && Interlocked.Increment(ref terminalDeliveries) == 2)
                {
                    retryEntered.Set();
                    allowRetry.Wait(1500);
                }
                return true;
            };

            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject expired = AuthorityBase("authority_terminal");
            expired["flowCallId"] = 1;
            expired["observedCallWatermark"] = 0;
            expired["terminal"] = "EXPIRED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = expired
            }.ToString(), 7, out ignored));
            Assert.True(retryEntered.Wait(1500));

            int armCountBeforeRelease = h.CountWeb("arm");
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.Equal(armCountBeforeRelease, h.CountWeb("arm"));

            allowRetry.Set();
            Assert.True(SpinWait.SpinUntil(() => !h.Runtime.HoldsGlobalPause
                && h.CountWeb("arm") == armCountBeforeRelease + 1, 1500));
            lock (h.Web)
            {
                Assert.Equal("arm", (string)h.Web[^1]["cmd"]);
            }
        }

        [Fact]
        public void ArmedPanelBusyBegin_RearmsFreshCapabilityOnlyAfterPanelHostReturnsIdle()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            h.Panel.IsIdleValue = false;
            int webCount = h.Web.Count;
            JObject rejected = h.Begin(arm);
            Assert.False((bool)rejected["success"]);
            Assert.Equal("panel_orchestration_busy", (string)rejected["error"]);
            Assert.Equal(webCount, h.Web.Count);

            h.Panel.IsIdleValue = true;
            h.Runtime.OnPanelHostClosed("inventory", "ordinary-panel-1");
            JObject freshArm = h.Web[^1];
            Assert.Equal("arm", (string)freshArm["cmd"]);
            Assert.Equal("capability.host.reconnect.two",
                (string)freshArm["payload"]["capability"]);
            Assert.NotEqual((string)arm["capability"],
                (string)freshArm["payload"]["capability"]);
            Assert.Equal(11, (long)freshArm["payload"]["documentEpoch"]);
        }

        [Fact]
        public void PanelQueueSettled_RetriesFreshArmAfterFastFailureRelease()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            h.Panel.IsIdleValue = false;
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.PreExecutionRejected);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = revoked
            }.ToString(), 7, out ignored));
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Equal(1, h.CountWeb("arm"));

            h.Panel.IsIdleValue = true;
            h.Runtime.OnPanelHostOrchestrationSettled();
            Assert.Equal(2, h.CountWeb("arm"));
            h.Runtime.OnPanelHostOrchestrationSettled();
            Assert.Equal(2, h.CountWeb("arm"));
            Assert.Equal("capability.host.reconnect.two",
                (string)h.Web[^1]["payload"]["capability"]);
        }

        [Fact]
        public void WebArmAcceptedButUnobserved_TimesOutToFreshCapability()
        {
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 100);
            h.Runtime.OnSocketReady(7);
            JObject first = (JObject)h.Web[^1]["payload"];

            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("arm") >= 2, 1000));
            JObject second = (JObject)h.Web[^1]["payload"];
            Assert.NotEqual((string)first["capability"], (string)second["capability"]);
            Assert.Equal(0, h.CountSocketAction("devLockboxS0Bootstrap"));
        }

        [Fact]
        public void BootstrapAckLost_TimesOutAndRecoversThroughFreshArmAndCapability()
        {
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 100);
            h.Runtime.OnSocketReady(7);
            JObject firstArm = h.Web[^1];
            JObject firstArmed = (JObject)firstArm.DeepClone();
            firstArmed["cmd"] = "armed";
            Assert.True(h.Runtime.TryHandleWebMessage(firstArmed));
            Assert.Equal(1, h.CountSocketAction("devLockboxS0Bootstrap"));

            // System.Threading.Timer callbacks are ThreadPool-scheduled.  The production timeout
            // remains 100 ms; this wider assertion window only tolerates full-suite worker
            // scheduling pressure before observing the already-due recovery callback.
            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("arm") >= 2, 5000));
            JObject freshArm = h.Web[^1];
            Assert.NotEqual((string)firstArm["payload"]["capability"],
                (string)freshArm["payload"]["capability"]);
            JObject freshArmed = (JObject)freshArm.DeepClone();
            freshArmed["cmd"] = "armed";
            Assert.True(h.Runtime.TryHandleWebMessage(freshArmed));
            Assert.Equal(2, h.CountSocketAction("devLockboxS0Bootstrap"));
            h.AcknowledgeLastBootstrap(7);

            JObject began = h.Begin((JObject)freshArm["payload"]);
            Assert.True((bool)began["success"]);
        }

        [Fact]
        public async Task OldBootstrapFailureCannotDisposeFreshBindingAckTimer()
        {
            // Use a dedicated worker and a wider deadline: this test deliberately blocks the
            // socket callback, so sharing a saturated xUnit thread pool with the 100 ms
            // production-timer model can let the arm expire before the race is established.
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 500);
            h.Runtime.OnSocketReady(7);
            JObject oldArmed = (JObject)h.Web[^1].DeepClone();
            oldArmed["cmd"] = "armed";
            using ManualResetEventSlim oldSendEntered = new ManualResetEventSlim(false);
            using ManualResetEventSlim finishOldSend = new ManualResetEventSlim(false);
            h.SocketDelivery = delegate(JObject message)
            {
                if ((string)message["action"] == "devLockboxS0Bootstrap"
                    && (int)message["connectionGeneration"] == 7)
                {
                    oldSendEntered.Set();
                    finishOldSend.Wait(5000);
                    return false;
                }
                return true;
            };

            Task<bool> oldAck = Task.Factory.StartNew(
                () => h.Runtime.TryHandleWebMessage(oldArmed),
                CancellationToken.None,
                TaskCreationOptions.LongRunning,
                TaskScheduler.Default);
            Assert.True(oldSendEntered.Wait(5000));
            h.Runtime.OnSocketReady(8);
            Assert.Equal(2, h.CountWeb("arm"));
            JObject freshPending = h.Web[^1];

            finishOldSend.Set();
            Assert.True(await oldAck);
            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("arm") >= 3, 5000));
            JObject recovered = h.Web[^1];
            Assert.NotEqual((string)freshPending["payload"]["capability"],
                (string)recovered["payload"]["capability"]);
            Assert.Equal(8, (int)recovered["payload"]["connectionGeneration"]);
        }

        [Fact]
        public void SameGenerationBootstrapSendFailureRetriesWithFreshCapability()
        {
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 75);
            int bootstrapAttempts = 0;
            h.SocketDelivery = delegate(JObject message)
            {
                if ((string)message["action"] != "devLockboxS0Bootstrap") return true;
                return Interlocked.Increment(ref bootstrapAttempts) > 1;
            };
            h.Runtime.OnSocketReady(7);
            JObject firstArm = h.Web[^1];
            JObject firstArmed = (JObject)firstArm.DeepClone();
            firstArmed["cmd"] = "armed";
            Assert.True(h.Runtime.TryHandleWebMessage(firstArmed));

            Assert.True(SpinWait.SpinUntil(() => h.CountWeb("arm") >= 2, 1500));
            JObject secondArm = h.Web[^1];
            Assert.NotEqual((string)firstArm["payload"]["capability"],
                (string)secondArm["payload"]["capability"]);
            JObject secondArmed = (JObject)secondArm.DeepClone();
            secondArmed["cmd"] = "armed";
            Assert.True(h.Runtime.TryHandleWebMessage(secondArmed));
            Assert.Equal(2, h.CountSocketAction("devLockboxS0Bootstrap"));
            Assert.Equal(2, bootstrapAttempts);
        }

        [Fact]
        public void ActiveReconnectBootstrapSendFailureRetriesSameGenerationWithFreshCapability()
        {
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 75);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            int resumeAttempts = 0;
            h.SocketDelivery = delegate(JObject message)
            {
                if ((string)message["action"] != "devLockboxS0Bootstrap"
                    || !(bool)message["resumeActive"]) return true;
                return Interlocked.Increment(ref resumeAttempts) > 1;
            };
            h.Runtime.OnSocketDisconnected(7);
            h.Runtime.OnSocketReady(8);

            Assert.True(SpinWait.SpinUntil(delegate
            {
                lock (h.Socket)
                    return h.Socket.Count(message =>
                        (string)message["action"] == "devLockboxS0Bootstrap"
                        && (bool)message["resumeActive"]) >= 2;
            }, 1500));
            JObject[] resumeBootstraps;
            lock (h.Socket)
                resumeBootstraps = h.Socket.Where(message =>
                    (string)message["action"] == "devLockboxS0Bootstrap"
                    && (bool)message["resumeActive"]).ToArray();
            Assert.Equal(2, resumeBootstraps.Length);
            Assert.Equal(2, resumeAttempts);
            Assert.All(resumeBootstraps, message =>
                Assert.Equal(8, (int)message["connectionGeneration"]));
            Assert.NotEqual((string)resumeBootstraps[0]["capability"],
                (string)resumeBootstraps[1]["capability"]);
            h.AcknowledgeLastBootstrap(8);
            Assert.True(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void FailedNavigationPreservesActiveReconnectBootstrapAckTimeout()
        {
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 75);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            h.Runtime.OnSocketDisconnected(7);
            h.Runtime.OnSocketReady(8);
            JObject firstResume;
            lock (h.Socket) firstResume = h.Socket.Last(message =>
                (string)message["action"] == "devLockboxS0Bootstrap"
                && (bool)message["resumeActive"]);
            h.Runtime.OnWebDocumentNavigationStarting(8001);
            h.Runtime.OnWebDocumentNavigationCompleted(8001, false);

            Assert.True(SpinWait.SpinUntil(delegate
            {
                lock (h.Socket)
                    return h.Socket.Count(message =>
                        (string)message["action"] == "devLockboxS0Bootstrap"
                        && (bool)message["resumeActive"]) >= 2;
            }, 1500));
            JObject secondResume;
            lock (h.Socket) secondResume = h.Socket.Last(message =>
                (string)message["action"] == "devLockboxS0Bootstrap"
                && (bool)message["resumeActive"]);
            Assert.NotEqual((string)firstResume["capability"],
                (string)secondResume["capability"]);
            Assert.Equal(8, (int)secondResume["connectionGeneration"]);
        }

        [Fact]
        public void DisposeCancelsPendingBindingAckWithoutLateWebOrSocketOutput()
        {
            Harness h = new Harness(bindingAckTimeoutMilliseconds: 50);
            try
            {
                h.Runtime.OnSocketReady(7);
                Assert.Equal(1, h.CountWeb("arm"));
                h.Runtime.Dispose();
                Thread.Sleep(150);
                Assert.Equal(1, h.CountWeb("arm"));
                Assert.Equal(0, h.CountSocketAction("devLockboxS0Bootstrap"));
            }
            finally
            {
                h.Dispose();
            }
        }

        [Fact]
        public async Task DisposeCannotOvertakeInFlightBeginDispatchAndQueuedGateFailsClosed()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            using ManualResetEventSlim acquireEntered = new ManualResetEventSlim(false);
            using ManualResetEventSlim allowAcquire = new ManualResetEventSlim(false);
            h.AcquireAction = delegate
            {
                acquireEntered.Set();
                allowAcquire.Wait(5000);
                return true;
            };

            Task<JObject> begin = Task.Factory.StartNew(() => h.Begin(arm),
                CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            bool entered = acquireEntered.Wait(5000);
            if (!entered) allowAcquire.Set();
            Assert.True(entered);
            Task dispose = Task.Factory.StartNew(() => h.Runtime.Dispose(),
                CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            bool disposeBlockedAtDispatch = await Task.WhenAny(dispose, Task.Delay(150)) != dispose;
            allowAcquire.Set();
            JObject response = await begin;
            await dispose;

            Assert.True(disposeBlockedAtDispatch);
            Assert.False((bool)response["success"]);
            Assert.Null(h.Panel.ExecutionGate);
        }

        [Fact]
        public void ResultQueryFromPanelBound_EntersNoWriteReconcileWithoutApplyingOrReplayingResult()
        {
            using Harness h = new Harness();
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject query = WebIdentity();
            query["unknownFlowCallId"] = 1;
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result_query", query)));
            Assert.Equal(0, h.CountSocketAction("devLockboxS0ApplyResult"));
            Assert.Equal(1, h.CountSocketAction("devLockboxS0QueryResult"));
            Assert.True(h.Runtime.HoldsGlobalPause);

            JObject noWrite = AuthorityBase("result_query_reply");
            noWrite["flowCallId"] = 1;
            noWrite["observedCallWatermark"] = 1;
            noWrite["disposition"] = "not_applied";
            noWrite["authorityTerminal"] = true;
            noWrite["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = noWrite
            }.ToString(), 7, out ignored));
            Assert.Equal(0, h.CountSocketAction("devLockboxS0ApplyResult"));
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("close_ack", WebIdentity())));
            Assert.NotNull(h.Panel.CloseCompleted);
            h.Panel.CloseCompleted(true);
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
        }

        [Fact]
        public void PauseRelease_UsesOnlyRuntimeAdoptedGenerationAcrossReplacementGap()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            h.AcquireAction = _ => false;
            h.ReleaseAction = delegate(int generation)
            {
                h.ReleaseGenerations.Add(generation);
                if (generation != 8) return false;
                h.Released = true;
                return true;
            };
            Assert.False((bool)h.Begin(arm)["success"]);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = revoked
            }.ToString(), 7, out ignored));
            Assert.False(h.Released);
            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.Equal(new[] { 7 }, h.ReleaseGenerations);

            h.Runtime.OnSocketReady(8);
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Equal(new[] { 7, 8 }, h.ReleaseGenerations);
            Assert.Equal(2, h.CountWeb("arm"));
            Assert.Equal(8, (int)h.Web[^1]["payload"]["connectionGeneration"]);
        }

        [Fact]
        public void PauseRelease_RetriesGenerationAdoptedInsideOldGenerationCallback()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            h.AcquireAction = _ => false;
            h.ReleaseAction = delegate(int generation)
            {
                h.ReleaseGenerations.Add(generation);
                if (generation == 7)
                {
                    // Reproduce the narrow ordering where socket adoption publishes its ready
                    // edge before the old exact-generation send has returned false.
                    h.Runtime.OnSocketReady(8);
                    return false;
                }
                if (generation != 8) return false;
                h.Released = true;
                return true;
            };
            Assert.False((bool)h.Begin(arm)["success"]);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = revoked
            }.ToString(), 7, out ignored));

            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Equal(new[] { 7, 8 }, h.ReleaseGenerations);
            Assert.Equal(2, h.CountWeb("arm"));
            Assert.Equal(8, (int)h.Web[^1]["payload"]["connectionGeneration"]);
        }

        [Fact]
        public async Task PauseRelease_AllowsConcurrentGenerationAdoptionBeforeFinalProof()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            h.AcquireAction = _ => false;
            using ManualResetEventSlim oldReleaseEntered = new ManualResetEventSlim(false);
            using ManualResetEventSlim allowOldRelease = new ManualResetEventSlim(false);
            h.ReleaseAction = delegate(int generation)
            {
                h.ReleaseGenerations.Add(generation);
                if (generation == 7)
                {
                    oldReleaseEntered.Set();
                    allowOldRelease.Wait(5000);
                    return true;
                }
                if (generation != 8) return false;
                h.Released = true;
                return true;
            };
            Assert.False((bool)h.Begin(arm)["success"]);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            Task authority = Task.Factory.StartNew(delegate
            {
                string ignored;
                Assert.True(h.Runtime.TryHandleSocketJson(new JObject
                {
                    ["task"] = DevLockboxS0Runtime.SocketTask,
                    ["payload"] = revoked
                }.ToString(), 7, out ignored));
            }, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            bool entered = oldReleaseEntered.Wait(5000);
            if (!entered) allowOldRelease.Set();
            Assert.True(entered);

            Task ready = Task.Factory.StartNew(() => h.Runtime.OnSocketReady(8),
                CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            bool readyPublishedBeforeOldReturn = await Task.WhenAny(ready, Task.Delay(1000)) == ready;
            allowOldRelease.Set();
            await Task.WhenAll(authority, ready);

            Assert.True(readyPublishedBeforeOldReturn);
            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Equal(new[] { 7, 8 }, h.ReleaseGenerations);
            Assert.Equal(8, (int)h.Web[^1]["payload"]["connectionGeneration"]);
        }

        [Fact]
        public void SuccessfulOldReleaseRetriesAdoptedGenerationBeforeFreshArm()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            h.AcquireAction = _ => false;
            h.ReleaseAction = delegate(int generation)
            {
                h.ReleaseGenerations.Add(generation);
                if (generation == 7) h.Runtime.OnSocketReady(8);
                h.Released = true;
                return true;
            };
            Assert.False((bool)h.Begin(arm)["success"]);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = revoked
            }.ToString(), 7, out ignored));

            Assert.True(h.Released);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Equal(new[] { 7, 8 }, h.ReleaseGenerations);
            Assert.Equal(1, h.CountSocketAction("devLockboxS0Bootstrap"));
            Assert.Equal(2, h.CountWeb("arm"));
            Assert.Equal(8, (int)h.Web[^1]["payload"]["connectionGeneration"]);
        }

        [Fact]
        public void SuccessfulOldReleaseCannotResetWhenAdoptedGenerationReleaseFails()
        {
            using Harness h = new Harness(closeAckRetryMilliseconds: 500);
            JObject arm = h.ArmAndAcknowledge();
            h.AcquireAction = _ => false;
            h.ReleaseAction = delegate(int generation)
            {
                h.ReleaseGenerations.Add(generation);
                if (generation == 7)
                {
                    h.Runtime.OnSocketReady(8);
                    return true;
                }
                return false;
            };
            Assert.False((bool)h.Begin(arm)["success"]);

            JObject revoked = AuthorityBase("revocation_ack");
            revoked["observedCallWatermark"] = 1;
            revoked["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = revoked
            }.ToString(), 7, out ignored));

            Assert.Equal(new[] { 7, 8 }, h.ReleaseGenerations);
            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.False(h.Released);
            Assert.Equal(1, h.CountWeb("arm"));
            Assert.Equal(1, h.CountSocketAction("devLockboxS0Bootstrap"));
        }

        [Fact]
        public async Task SupersededActiveReconnectCannotCancelFreshIdleArmRetry()
        {
            using ManualResetEventSlim resumeCapabilityEntered = new ManualResetEventSlim(false);
            using ManualResetEventSlim releaseResumeCapability = new ManualResetEventSlim(false);
            int capabilityCalls = 0;
            Func<string> capabilityFactory = delegate
            {
                int call = Interlocked.Increment(ref capabilityCalls);
                if (call == 2)
                {
                    resumeCapabilityEntered.Set();
                    releaseResumeCapability.Wait(5000);
                }
                return "capability.resume.owner." + call;
            };
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 500,
                capabilityFactory: capabilityFactory);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject result = WebIdentity();
            result["flowCallId"] = 1;
            result["result"] = "cancel";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", result)));
            JObject authority = AuthorityBase("result_ack");
            authority["flowCallId"] = 1;
            authority["result"] = "cancel";
            authority["applied"] = true;
            authority["observedCallWatermark"] = 1;
            authority["authorityTerminal"] = true;
            authority["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = authority
            }.ToString(), 7, out ignored));
            Assert.True(h.Runtime.TryHandleWebMessage(
                WebBusiness("close_ack", WebIdentity())));
            Assert.NotNull(h.Panel.CloseCompleted);

            h.Runtime.OnSocketDisconnected(7);
            Task reconnect = Task.Factory.StartNew(() => h.Runtime.OnSocketReady(8),
                CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            bool entered = resumeCapabilityEntered.Wait(5000);
            if (!entered) releaseResumeCapability.Set();
            Assert.True(entered);

            int armCountBeforeRelease = h.CountWeb("arm");
            int postReleaseArmAttempts = 0;
            h.WebDelivery = message => (string)message["cmd"] != "arm"
                || Interlocked.Increment(ref postReleaseArmAttempts) > 1;
            h.Panel.CloseCompleted(true);
            Assert.False(h.Runtime.HoldsGlobalPause);
            Assert.Equal(armCountBeforeRelease + 1, h.CountWeb("arm"));

            releaseResumeCapability.Set();
            await reconnect;
            Assert.True(SpinWait.SpinUntil(
                () => h.CountWeb("arm") >= armCountBeforeRelease + 2, 5000));
            JObject[] freshArms;
            lock (h.Web) freshArms = h.Web
                .Where(message => (string)message["cmd"] == "arm")
                .Skip(armCountBeforeRelease).ToArray();
            Assert.All(freshArms, fresh => Assert.Equal(8,
                (int)fresh["payload"]["connectionGeneration"]));
        }

        [Fact]
        public async Task ReleaseFailureRestoresResumeEdgeConsumedDuringReleaseWindow()
        {
            using Harness h = new Harness(bindingAckTimeoutMilliseconds: 250);
            JObject arm = h.ArmAndAcknowledge();
            Assert.True((bool)h.Begin(arm)["success"]);
            Assert.True(h.Panel.ExecutionGate());
            h.Panel.OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("bind", WebIdentity())));

            JObject result = WebIdentity();
            result["flowCallId"] = 1;
            result["result"] = "cancel";
            Assert.True(h.Runtime.TryHandleWebMessage(WebBusiness("result", result)));
            JObject authority = AuthorityBase("result_ack");
            authority["flowCallId"] = 1;
            authority["result"] = "cancel";
            authority["applied"] = true;
            authority["observedCallWatermark"] = 1;
            authority["authorityTerminal"] = true;
            authority["authorityState"] = "REVOKED";
            string ignored;
            Assert.True(h.Runtime.TryHandleSocketJson(new JObject
            {
                ["task"] = DevLockboxS0Runtime.SocketTask,
                ["payload"] = authority
            }.ToString(), 7, out ignored));
            Assert.True(h.Runtime.TryHandleWebMessage(
                WebBusiness("close_ack", WebIdentity())));
            Assert.NotNull(h.Panel.CloseCompleted);

            h.Runtime.OnSocketDisconnected(7);
            h.Runtime.OnSocketReady(8);
            int resumeBootstrapCount = h.CountSocketAction("devLockboxS0Bootstrap");
            Assert.True(resumeBootstrapCount >= 2);

            using ManualResetEventSlim releaseEntered = new ManualResetEventSlim(false);
            using ManualResetEventSlim finishRelease = new ManualResetEventSlim(false);
            h.ReleaseAction = delegate(int generation)
            {
                h.ReleaseGenerations.Add(generation);
                releaseEntered.Set();
                finishRelease.Wait(5000);
                return false;
            };
            Task nativeClose = Task.Factory.StartNew(() => h.Panel.CloseCompleted(true),
                CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            Assert.True(releaseEntered.Wait(5000));
            Assert.False(SpinWait.SpinUntil(
                () => h.CountSocketAction("devLockboxS0Bootstrap") > resumeBootstrapCount, 1000));
            finishRelease.Set();
            await nativeClose;

            Assert.True(h.Runtime.HoldsGlobalPause);
            Assert.True(SpinWait.SpinUntil(
                () => h.CountSocketAction("devLockboxS0Bootstrap") > resumeBootstrapCount, 5000));
            JObject freshResume;
            lock (h.Socket) freshResume = h.Socket.Last(message =>
                (string)message["action"] == "devLockboxS0Bootstrap");
            Assert.True((bool)freshResume["resumeActive"]);
            Assert.Equal(8, (int)freshResume["connectionGeneration"]);
        }

        [Fact]
        public void MinigameTelemetryBoundary_AcceptsOnlyExactFourFieldAllowList()
        {
            JObject payload = new JObject
            {
                ["game"] = "lockbox",
                ["kind"] = "s0_telemetry",
                ["data"] = new JObject
                {
                    ["eventCategory"] = "result",
                    ["resultCategory"] = "success",
                    ["durationBucket"] = "1_5s",
                    ["errorCategory"] = "none"
                }
            };
            JObject normalized;
            Assert.True(DevLockboxS0Runtime.TryNormalizeMinigameTelemetry(payload,
                out normalized));
            Assert.Equal(4, normalized.Count);
            Assert.Equal("result", (string)normalized["eventCategory"]);

            JObject raw = (JObject)payload.DeepClone();
            ((JObject)raw["data"])["sessionId"] = "must-not-log";
            Assert.False(DevLockboxS0Runtime.TryNormalizeMinigameTelemetry(raw,
                out normalized));
            Assert.Null(normalized);
            JObject invalid = (JObject)payload.DeepClone();
            ((JObject)invalid["data"])["durationBucket"] = "1234ms";
            Assert.False(DevLockboxS0Runtime.TryNormalizeMinigameTelemetry(invalid,
                out normalized));
            Assert.Null(normalized);
        }

        [Fact]
        public void S0MinigameLogging_RedactsEnvelopeAndNeverSerializesRawSecrets()
        {
            const string secret = "raw-session-secret-must-never-reach-log";
            JObject valid = new JObject
            {
                ["game"] = "lockbox",
                ["kind"] = "s0_telemetry",
                ["data"] = new JObject
                {
                    ["eventCategory"] = "result",
                    ["resultCategory"] = "success",
                    ["durationBucket"] = "1_5s",
                    ["errorCategory"] = "none"
                }
            };
            JObject malformed = (JObject)valid.DeepClone();
            ((JObject)malformed["data"])["sessionId"] = secret;
            JObject missingGame = (JObject)malformed.DeepClone();
            missingGame.Remove("game");

            List<string> logs = new List<string>();
            foreach (JObject payload in new[] { valid, malformed, missingGame })
            {
                JObject envelope = new JObject
                {
                    ["cmd"] = "minigame_session",
                    ["payload"] = payload,
                    ["diagnostic"] = secret
                };
                logs.Add(WebOverlayForm.FormatPanelEnvelopeLog("minigame_session",
                    envelope.ToString(Newtonsoft.Json.Formatting.None)));
                Assert.True(WebOverlayForm.TryLogS0MinigameSession(payload, true, logs.Add));
            }

            string combined = string.Join("\n", logs);
            Assert.DoesNotContain(secret, combined, StringComparison.Ordinal);
            Assert.Equal(3, logs.Count(delegate(string line)
            {
                return line == "[Panel] HandlePanelMessage: cmd=minigame_session payload=redacted";
            }));
            Assert.Single(logs, delegate(string line)
            {
                return line == "[LockboxS0] {\"eventCategory\":\"result\","
                    + "\"resultCategory\":\"success\",\"durationBucket\":\"1_5s\","
                    + "\"errorCategory\":\"none\"}";
            });
            Assert.Equal(2, logs.Count(delegate(string line)
            {
                return line == "[DevLockboxS0] event=telemetry_dropped"
                    + " code=non_allowlisted_minigame_session";
            }));

            List<string> lateLogs = new List<string>();
            Assert.True(WebOverlayForm.TryLogS0MinigameSession(valid, false, lateLogs.Add));
            Assert.True(WebOverlayForm.TryLogS0MinigameSession(malformed, false, lateLogs.Add));
            Assert.False(WebOverlayForm.TryLogS0MinigameSession(missingGame, false, lateLogs.Add));
            Assert.DoesNotContain(secret, string.Join("\n", lateLogs), StringComparison.Ordinal);
            Assert.Equal(2, lateLogs.Count);
        }

        [Fact]
        public void MissingPanelHost_NeverArmsAndDedicatedTaskIsNotRegisteredInGenericRouter()
        {
            using Harness h = new Harness(new DevLockboxS0PanelHostPort(null));
            h.Runtime.OnSocketReady(7);
            Assert.Empty(h.Web);
            Assert.Empty(h.Socket);

            MessageRouter router = new MessageRouter();
            string generic = router.ProcessMessage(@"{""task"":""dev_lockbox_s0"",""callId"":1,""payload"":{}}", null);
            JObject rejected = JObject.Parse(generic);
            Assert.False((bool)rejected["success"]);
            Assert.Equal("Unknown task type", (string)rejected["error"]);
        }

        private static JObject WebBusiness(string command, JObject payload)
        {
            return new JObject
            {
                ["type"] = DevLockboxS0Runtime.WebBusinessType,
                ["cmd"] = command,
                ["payload"] = payload
            };
        }

        private static JObject WebControl(string command, JObject payload)
        {
            return new JObject
            {
                ["type"] = DevLockboxS0Runtime.WebControlType,
                ["cmd"] = command,
                ["payload"] = payload
            };
        }

        private static JObject WebIdentity()
        {
            return new JObject
            {
                ["flowHandle"] = "flow.host.1",
                ["panelInstanceId"] = "panel.lockbox.host.1",
                ["documentEpoch"] = 11,
                ["source"] = "as2-chest-s0",
                ["fixture"] = "insurance-safe-s0-v1"
            };
        }

        private static JObject AuthorityBase(string action)
        {
            return new JObject
            {
                ["action"] = action,
                ["protocolVersion"] = 1,
                ["sessionId"] = "chest-s0.session.1",
                ["flowHandle"] = "flow.host.1",
                ["panelInstanceId"] = "panel.lockbox.host.1",
                ["documentEpoch"] = 11,
                ["source"] = "as2-chest-s0",
                ["fixture"] = "insurance-safe-s0-v1"
            };
        }

        private static JObject MutatedAuthority(JObject source, string key, JToken value)
        {
            JObject clone = (JObject)source.DeepClone();
            clone[key] = value;
            return clone;
        }
    }
}
