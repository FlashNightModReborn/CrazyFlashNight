using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class HairdresserTaskDomainAdapterTests : IDisposable
    {
        private readonly string _temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            "cf7-hair-adapter-tests",
            Guid.NewGuid().ToString("N"));

        [Fact]
        public async Task InspectAndCommit_UseOnlyHairdresserBridgeAndCAS()
        {
            using var bridge = new FakeHairdresserBridge("光头");
            Fixture fixture = CreateFixture(bridge);

            HairAdapterInspectResult inspected =
                await fixture.Adapter.InspectAsync(
                    fixture.Binding,
                    CancellationToken.None);
            Assert.True(inspected.Success);
            Assert.Equal("光头", inspected.Snapshot.CurrentHair);
            Assert.Equal(
                new[]
                {
                    "hairdresserSnapshot"
                },
                bridge.Actions);

            HairAuthoritativeSnapshot before = inspected.Snapshot;
            var command = new HairDomainCommitCommand(
                "hairtx_ABCDEFGHIJKLMNOPQRSTUVWX",
                fixture.Binding,
                "发型-男式-平头",
                before.CurrentHair,
                before.Revision,
                before.Generation,
                HairAppearanceHashing.ComputeSnapshotHash(before),
                false);
            HairAdapterCommitResult committed =
                await fixture.Adapter.CommitAsync(
                    command,
                    CancellationToken.None);

            Assert.Equal(HairAdapterCommitStatus.Applied, committed.Status);
            Assert.Equal(
                "发型-男式-平头",
                committed.Snapshot.CurrentHair);
            Assert.Equal(
                before.Revision + 1,
                committed.Snapshot.Revision);
            Assert.Equal(
                new[]
                {
                    "hairdresserSnapshot",
                    "hairdresserCommit",
                    "hairdresserSnapshot"
                },
                bridge.Actions);
            Assert.Equal(
                "光头",
                bridge.LastCommitExpectedCurrentHair);
        }

        [Fact]
        public async Task StaleAs2Cas_IsDefinitiveAndNextInspectAdvancesRevision()
        {
            using var bridge = new FakeHairdresserBridge("光头");
            Fixture fixture = CreateFixture(bridge);
            HairAuthoritativeSnapshot before =
                (await fixture.Adapter.InspectAsync(
                    fixture.Binding,
                    CancellationToken.None)).Snapshot;
            bridge.HumanChange("发型-女式-短发");

            HairAdapterCommitResult rejected =
                await fixture.Adapter.CommitAsync(
                    Command(
                        fixture.Binding,
                        before,
                        "发型-男式-平头"),
                    CancellationToken.None);
            Assert.Equal(
                HairAdapterCommitStatus.Rejected,
                rejected.Status);
            Assert.Equal(
                HairAppearanceReasonCodes.StaleState,
                rejected.ReasonCode);

            HairAuthoritativeSnapshot observed =
                (await fixture.Adapter.InspectAsync(
                    fixture.Binding,
                    CancellationToken.None)).Snapshot;
            Assert.Equal(
                "发型-女式-短发",
                observed.CurrentHair);
            Assert.Equal(before.Revision + 1, observed.Revision);
        }

        [Fact]
        public async Task AppliedThenAckLoss_IsUnknownAndNeverReplayed()
        {
            using var bridge = new FakeHairdresserBridge(
                "光头",
                timeoutMs: 40);
            Fixture fixture = CreateFixture(bridge);
            HairAuthoritativeSnapshot before =
                (await fixture.Adapter.InspectAsync(
                    fixture.Binding,
                    CancellationToken.None)).Snapshot;
            bridge.DropNextCommitAcknowledgement = true;

            HairAdapterCommitResult unknown =
                await fixture.Adapter.CommitAsync(
                    Command(
                        fixture.Binding,
                        before,
                        "发型-男式-平头"),
                    CancellationToken.None);
            Assert.Equal(
                HairAdapterCommitStatus.Unknown,
                unknown.Status);
            Assert.Equal(
                1,
                bridge.Actions.Count(
                    value => value == "hairdresserCommit"));

            HairAdapterInspectResult reconciled =
                await fixture.Adapter.InspectAsync(
                    fixture.Binding,
                    CancellationToken.None);
            Assert.True(reconciled.Success);
            Assert.Equal(
                "发型-男式-平头",
                reconciled.Snapshot.CurrentHair);
            Assert.Equal(before.Revision + 1,
                reconciled.Snapshot.Revision);
            Assert.Equal(
                1,
                bridge.Actions.Count(
                    value => value == "hairdresserCommit"));
        }

        [Fact]
        public async Task CrossSaveAndStaleRevisionRejectBeforeFlashWrite()
        {
            using var bridge = new FakeHairdresserBridge("光头");
            Fixture fixture = CreateFixture(bridge);
            HairAuthoritativeSnapshot before =
                (await fixture.Adapter.InspectAsync(
                    fixture.Binding,
                    CancellationToken.None)).Snapshot;
            int actionCount = bridge.Actions.Count;

            HairSaveBinding other = new HairSaveBinding(
                "session_other_ABCDEFGHIJKLMNOP",
                fixture.Binding.LifecycleGeneration,
                fixture.Binding.AttemptId,
                fixture.Binding.AttemptGeneration,
                fixture.Binding.SlotId,
                fixture.Binding.SaveSignature);
            HairAdapterCommitResult crossSave =
                await fixture.Adapter.CommitAsync(
                    Command(
                        other,
                        before,
                        "发型-男式-平头"),
                    CancellationToken.None);
            Assert.Equal(
                HairAdapterCommitStatus.Rejected,
                crossSave.Status);
            Assert.Equal(
                HairAppearanceReasonCodes.CrossSave,
                crossSave.ReasonCode);

            var stale = new HairDomainCommitCommand(
                "hairtx_ABCDEFGHIJKLMNOPQRSTUVWX",
                fixture.Binding,
                "发型-男式-平头",
                before.CurrentHair,
                before.Revision + 1,
                before.Generation,
                HairAppearanceHashing.ComputeSnapshotHash(before),
                false);
            HairAdapterCommitResult staleRevision =
                await fixture.Adapter.CommitAsync(
                    stale,
                    CancellationToken.None);
            Assert.Equal(
                HairAppearanceReasonCodes.StaleRevision,
                staleRevision.ReasonCode);
            Assert.Equal(actionCount, bridge.Actions.Count);
        }

        public void Dispose()
        {
            if (!Directory.Exists(_temporaryRoot))
                return;
            string full = Path.GetFullPath(_temporaryRoot);
            string expected = Path.GetFullPath(
                Path.Combine(
                    Path.GetTempPath(),
                    "cf7-hair-adapter-tests"));
            if (full.StartsWith(
                expected + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase))
            {
                Directory.Delete(full, true);
            }
        }

        private Fixture CreateFixture(FakeHairdresserBridge bridge)
        {
            HairSaveBinding binding = CreateBinding();
            var authority = new PersistentHairDomainAuthority(
                @"C:\Games\CrazyFlashNight",
                _temporaryRoot,
                new NoOpProtection());
            authority.Bind(binding, 5);
            return new Fixture(
                binding,
                new HairdresserTaskDomainAdapter(
                    bridge.Task,
                    authority));
        }

        private static HairDomainCommitCommand Command(
            HairSaveBinding binding,
            HairAuthoritativeSnapshot before,
            string afterHair)
        {
            return new HairDomainCommitCommand(
                "hairtx_ABCDEFGHIJKLMNOPQRSTUVWX",
                binding,
                afterHair,
                before.CurrentHair,
                before.Revision,
                before.Generation,
                HairAppearanceHashing.ComputeSnapshotHash(before),
                false);
        }

        private static HairSaveBinding CreateBinding()
        {
            return new HairSaveBinding(
                "session_ABCDEFGHIJKLMNOPQRSTUVWX",
                4,
                "attempt_ABCDEFGHIJKLMNOPQRSTUVWX",
                2,
                "slot1",
                new string('b', 64));
        }

        private sealed class Fixture
        {
            public Fixture(
                HairSaveBinding binding,
                HairdresserTaskDomainAdapter adapter)
            {
                Binding = binding;
                Adapter = adapter;
            }

            public HairSaveBinding Binding { get; }
            public HairdresserTaskDomainAdapter Adapter { get; }
        }

        private sealed class NoOpProtection
            : IAgentRendezvousFileProtection
        {
            public void ProtectDirectory(string path)
            {
            }

            public void ProtectFile(string path)
            {
            }
        }

        private sealed class FakeHairdresserBridge : IDisposable
        {
            private readonly object _gate = new object();
            private string _currentHair;

            public FakeHairdresserBridge(
                string currentHair,
                int timeoutMs = 1000)
            {
                _currentHair = currentHair;
                Task = new HairdresserTask(
                    () => true,
                    HandleSend,
                    timeoutMs);
            }

            public HairdresserTask Task { get; }
            public List<string> Actions { get; } =
                new List<string>();
            public bool DropNextCommitAcknowledgement { get; set; }
            public string LastCommitExpectedCurrentHair { get; private set; }

            public void HumanChange(string hair)
            {
                lock (_gate)
                {
                    _currentHair = hair;
                }
            }

            public void Dispose()
            {
                Task.Dispose();
            }

            private bool HandleSend(string payload)
            {
                JObject request = JObject.Parse(
                    payload.TrimEnd('\0'));
                string action = request.Value<string>("action");
                Actions.Add(action);
                int callId = request.Value<int>("callId");

                if (action == "hairdresserSnapshot")
                {
                    Task.HandleFlashResponse(
                        SnapshotResponse(callId),
                        null);
                    return true;
                }
                if (action != "hairdresserCommit")
                    return false;

                string requested =
                    request.Value<string>("hairIdentifier");
                string expected =
                    request.Value<string>("expectedCurrentHair");
                LastCommitExpectedCurrentHair = expected;
                JObject response;
                lock (_gate)
                {
                    if (!string.Equals(
                        expected,
                        _currentHair,
                        StringComparison.Ordinal))
                    {
                        response = new JObject
                        {
                            ["task"] = "hairdresser_response",
                            ["callId"] = callId,
                            ["success"] = false,
                            ["v"] = 1,
                            ["error"] = "stale_state",
                            ["currentHair"] = _currentHair
                        };
                    }
                    else
                    {
                        _currentHair = requested;
                        response = new JObject
                        {
                            ["task"] = "hairdresser_response",
                            ["callId"] = callId,
                            ["success"] = true,
                            ["v"] = 1,
                            ["operation"] = "commit",
                            ["currentHair"] = _currentHair
                        };
                    }
                }

                if (DropNextCommitAcknowledgement)
                {
                    DropNextCommitAcknowledgement = false;
                    return true;
                }
                Task.HandleFlashResponse(response, null);
                return true;
            }

            private JObject SnapshotResponse(int callId)
            {
                string current;
                lock (_gate)
                {
                    current = _currentHair;
                }
                return new JObject
                {
                    ["task"] = "hairdresser_response",
                    ["callId"] = callId,
                    ["success"] = true,
                    ["v"] = 1,
                    ["gender"] = "男",
                    ["face"] = "默认脸",
                    ["currentHair"] = current,
                    ["catalog"] = new JArray
                    {
                        new JObject
                        {
                            ["identifier"] = "光头",
                            ["name"] = "光头"
                        },
                        new JObject
                        {
                            ["identifier"] =
                                "发型-男式-平头",
                            ["name"] = "男式平头"
                        },
                        new JObject
                        {
                            ["identifier"] =
                                "发型-女式-短发",
                            ["name"] = "女式短发"
                        }
                    }
                };
            }
        }
    }
}
