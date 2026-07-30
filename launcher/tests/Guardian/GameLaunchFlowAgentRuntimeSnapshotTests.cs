using System;
using System.Diagnostics;
using System.Reflection;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class GameLaunchFlowAgentRuntimeSnapshotTests
    {
        [Fact]
        public void SaveSignatureCanonicalizesNestedObjectOrder()
        {
            SolResolveResult first =
                SolResolveResult.NewSnapshot(
                    JObject.Parse(
                        "{\"z\":1,\"nested\":{\"b\":2,\"a\":1},\"array\":[{\"y\":2,\"x\":1},3]}"),
                    "sol");
            SolResolveResult reordered =
                SolResolveResult.NewSnapshot(
                    JObject.Parse(
                        "{\"array\":[{\"x\":1,\"y\":2},3],\"nested\":{\"a\":1,\"b\":2},\"z\":1}"),
                    "sol");

            Assert.Equal(
                GameLaunchFlow
                    .ComputeAgentRuntimeSaveSignature(
                        "slot-a",
                        first),
                GameLaunchFlow
                    .ComputeAgentRuntimeSaveSignature(
                        "slot-a",
                        reordered));
        }

        [Fact]
        public void SaveSignatureBindsSlotDecisionSourceAndSnapshot()
        {
            SolResolveResult baseline =
                SolResolveResult.NewSnapshot(
                    JObject.Parse("{\"value\":1}"),
                    "sol");
            string signature =
                GameLaunchFlow
                    .ComputeAgentRuntimeSaveSignature(
                        "slot-a",
                        baseline);

            Assert.NotEqual(
                signature,
                GameLaunchFlow
                    .ComputeAgentRuntimeSaveSignature(
                        "slot-b",
                        baseline));
            Assert.NotEqual(
                signature,
                GameLaunchFlow
                    .ComputeAgentRuntimeSaveSignature(
                        "slot-a",
                        SolResolveResult.NewSnapshot(
                            JObject.Parse("{\"value\":1}"),
                            "json_shadow")));
            Assert.NotEqual(
                signature,
                GameLaunchFlow
                    .ComputeAgentRuntimeSaveSignature(
                        "slot-a",
                        SolResolveResult.NewRepairable(
                            JObject.Parse("{\"value\":1}"),
                            "sol",
                            new JObject())));
            Assert.NotEqual(
                signature,
                GameLaunchFlow
                    .ComputeAgentRuntimeSaveSignature(
                        "slot-a",
                        SolResolveResult.NewSnapshot(
                            JObject.Parse("{\"value\":2}"),
                            "sol")));
        }

        [Fact]
        public void SnapshotKeepsExactProcessReferenceAndOneLockState()
        {
            using Harness harness = new Harness();
            using Process process =
                Process.GetCurrentProcess();
            SetPrivateField(
                harness.Flow,
                "_state",
                GameLaunchFlow.State.Ready);
            SetPrivateField(
                harness.Flow,
                "_currentAttemptId",
                "attempt.agent.snapshot.1");
            SetPrivateField(
                harness.Flow,
                "_pendingSlot",
                "slot-a");
            SetPrivateField(
                harness.Flow,
                "_currentFlashProcess",
                process);
            SetPrivateField(
                harness.Flow,
                "_agentRuntimeSaveSignature",
                new string('A', 64));

            GameLaunchFlow.AgentRuntimeLaunchSnapshot snapshot =
                harness.Flow
                    .CaptureAgentRuntimeLaunchSnapshot();

            Assert.Equal(
                GameLaunchFlow.State.Ready,
                snapshot.LaunchState);
            Assert.Equal(
                "attempt.agent.snapshot.1",
                snapshot.AttemptId);
            Assert.Equal("slot-a", snapshot.Slot);
            Assert.Same(process, snapshot.FlashProcess);
            Assert.Equal(
                new string('A', 64),
                snapshot.SaveSignature);
        }

        [Fact]
        public void IdleResetClearsAgentRuntimeAttemptSnapshot()
        {
            using Harness harness = new Harness();
            using Process process =
                Process.GetCurrentProcess();
            SetPrivateField(
                harness.Flow,
                "_currentAttemptId",
                "attempt.agent.stale.1");
            SetPrivateField(
                harness.Flow,
                "_pendingSlot",
                "slot-stale");
            SetPrivateField(
                harness.Flow,
                "_currentFlashProcess",
                process);
            SetPrivateField(
                harness.Flow,
                "_resolvedSave",
                SolResolveResult.NewEmpty());
            SetPrivateField(
                harness.Flow,
                "_agentRuntimeSaveSignature",
                new string('B', 64));

            harness.Flow.Reset(
                null,
                "agent_runtime_snapshot_test");
            GameLaunchFlow.AgentRuntimeLaunchSnapshot snapshot =
                harness.Flow
                    .CaptureAgentRuntimeLaunchSnapshot();

            Assert.Equal(
                GameLaunchFlow.State.Idle,
                snapshot.LaunchState);
            Assert.Null(snapshot.AttemptId);
            Assert.Null(snapshot.Slot);
            Assert.Null(snapshot.FlashProcess);
            Assert.Null(snapshot.SaveSignature);
        }

        private static void SetPrivateField<T>(
            GameLaunchFlow flow,
            string name,
            T value)
        {
            FieldInfo field =
                typeof(GameLaunchFlow).GetField(
                    name,
                    BindingFlags.Instance
                    | BindingFlags.NonPublic);
            Assert.NotNull(field);
            field.SetValue(flow, value);
        }

        private sealed class Harness : IDisposable
        {
            public Harness()
            {
                Router = new MessageRouter();
                Server = new XmlSocketServer(
                    Router,
                    AllowLoopbackXmlSocketPeerAuthority.Instance);
                ProcessManager =
                    new ProcessManager(
                        "unused-flash.exe",
                        "unused.swf");
                Flow = new GameLaunchFlow(
                    Server,
                    Router,
                    ProcessManager,
                    new WindowManager(),
                    null,
                    null,
                    null,
                    null,
                    null);
            }

            public MessageRouter Router { get; }
            public XmlSocketServer Server { get; }
            public ProcessManager ProcessManager { get; }
            public GameLaunchFlow Flow { get; }

            public void Dispose()
            {
                ProcessManager.Dispose();
                Server.Dispose();
            }
        }
    }
}
