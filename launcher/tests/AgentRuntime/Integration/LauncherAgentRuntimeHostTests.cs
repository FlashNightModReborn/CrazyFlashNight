using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.Guardian;
using CF7Launcher.Tests.AgentRuntime.Observation;
using CF7Launcher.Tests.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    [Collection(
        AgentRuntimeHostIdentityCollection.CollectionName)]
    public sealed class LauncherAgentRuntimeHostTests
    {
        private static readonly AgentFrameCodec Codec =
            new AgentFrameCodec(1);

        [Fact]
        public void CapabilityAdvertisementRequiresProductionProviders()
        {
            string[] withoutActivator =
                LauncherAgentRuntimeHost
                    .BuildSessionCapabilities(
                        qualified: true,
                        hairEnabled: true,
                        structuredEnabled: true,
                        activationEnabled: false);

            Assert.DoesNotContain(
                AgentCapabilitiesV1.SetValue,
                withoutActivator);
            Assert.DoesNotContain(
                AgentCapabilitiesV1.PerformSecondaryAction,
                withoutActivator);
            Assert.DoesNotContain(
                AgentCapabilitiesV1.TraceExport,
                withoutActivator);
            Assert.DoesNotContain(
                AgentCapabilitiesV1.ActivateWindow,
                withoutActivator);
            Assert.Contains(
                AgentCapabilitiesV1.SessionShutdown,
                withoutActivator);

            string[] withActivator =
                LauncherAgentRuntimeHost
                    .BuildSessionCapabilities(
                        qualified: true,
                        hairEnabled: true,
                        structuredEnabled: true,
                        activationEnabled: true);
            Assert.Contains(
                AgentCapabilitiesV1.ActivateWindow,
                withActivator);
            Assert.DoesNotContain(
                AgentCapabilitiesV1.SetValue,
                withActivator);
            Assert.DoesNotContain(
                AgentCapabilitiesV1.PerformSecondaryAction,
                withActivator);
            Assert.DoesNotContain(
                AgentCapabilitiesV1.TraceExport,
                withActivator);

            string[] enrollment =
                LauncherAgentRuntimeHost
                    .EnrollmentCapabilities(
                        withActivator.Concat(
                            new[]
                            {
                                AgentCapabilitiesV1.TraceExport
                            }));
            Assert.Contains(
                "observe:"
                + ObservationDataScopesV1.PlayerState,
                enrollment);
            Assert.Contains(
                AgentCapabilitiesV1.TraceExport,
                enrollment);
            Assert.Contains(
                "observation.export",
                enrollment);
            Assert.Contains(
                "observe:"
                + ObservationDataScopesV1.DataExport,
                enrollment);
        }

        [Fact]
        public void ActivationAdvertisementRecognizesOnlyFlashProvider()
        {
            LauncherAgentRuntimeTargetIds targets =
                LauncherAgentRuntimeTargetIds.Create();
            var webOnly =
                new Dictionary<
                    string,
                    Func<
                        LauncherAgentExactTargetBinding,
                        bool>>(StringComparer.Ordinal)
                {
                    [targets.WebOverlay] = _ => true
                };
            var flash =
                new Dictionary<
                    string,
                    Func<
                        LauncherAgentExactTargetBinding,
                        bool>>(StringComparer.Ordinal)
                {
                    [targets.Flash] = _ => true
                };

            Assert.False(
                LauncherAgentRuntimeHost
                    .HasProductionActivationProvider(
                        webOnly,
                        targets));
            Assert.True(
                LauncherAgentRuntimeHost
                    .HasProductionActivationProvider(
                        flash,
                        targets));
        }

        [Fact]
        public async Task
            ProductionPanelInstanceRegistersAndRoundTrips()
        {
            using var fixture = new HostFixture();
            await using LauncherAgentRuntimeHost host =
                fixture.CreateHost();
            var pumps = new Queue<Action>();
            using var panelHost =
                new PanelHostController(
                    pumps.Enqueue,
                    fire => fire());

            Assert.True(
                panelHost.TryOpenPanel(
                    "help",
                    null,
                    null,
                    null));
            Action open = Assert.Single(pumps);
            pumps.Clear();
            open();
            string panelInstanceId =
                panelHost.ActivePanelInstanceId;

            Assert.Matches(
                "^panel_[0-9a-f]{16}_[0-9a-f]{16}$",
                panelInstanceId);
            Assert.True(
                host.SetActivePanel(
                    "help",
                    panelInstanceId));
            Assert.Equal(
                "help",
                host.SnapshotForTests.ActivePanelName);
            Assert.Equal(
                panelInstanceId,
                host.SnapshotForTests.ActivePanelInstanceId);
            Assert.Equal(
                host.Targets.WebOverlay,
                host.SnapshotForTests.ActivePanelTargetId);
            Assert.Equal(
                panelInstanceId,
                host.SnapshotForTests.PanelInstanceIdForTarget(
                    host.Targets.WebOverlay));
        }

        [Fact]
        public async Task
            LifecycleReferenceIssuesGrantAgainstActualSessionAndAllowedTarget()
        {
            using var fixture = new HostFixture();
            await using LauncherAgentRuntimeHost host =
                fixture.CreateHost();

            Assert.Equal(
                RuntimeMode.UnqualifiedDev,
                host.SnapshotForTests
                    .RuntimeQualification.RuntimeMode);
            Assert.Equal(2, host.SnapshotForTests.Surfaces.Count);
            Assert.All(
                host.SnapshotForTests.Surfaces,
                surface => Assert.Empty(surface.InputModes));

            string credentialPath =
                host.ShowDeveloperEnrollmentDialog();
            Assert.True(File.Exists(credentialPath));
            Assert.NotNull(fixture.Presenter.Request);
            Assert.Equal(
                new[]
                {
                    SurfaceKind.Launcher,
                    SurfaceKind.WebOverlay
                },
                fixture.Presenter.Request.Targets
                    .Select(target => target.Kind)
                    .ToArray());
            Assert.Contains(
                AgentCapabilitiesV1
                    .ObservationGrantManage,
                fixture.Presenter.Request.Capabilities);
            Assert.Contains(
                "observe:"
                + ObservationDataScopesV1
                    .WindowMetadata,
                fixture.Presenter.Request.Capabilities);
            Assert.Contains(
                "observe:"
                + ObservationDataScopesV1.Pixels,
                fixture.Presenter.Request.Capabilities);
            Assert.DoesNotContain(
                "observe:"
                + ObservationDataScopesV1.Accessibility,
                fixture.Presenter.Request.Capabilities);
            Assert.DoesNotContain(
                "observe:"
                + ObservationDataScopesV1.Focus,
                fixture.Presenter.Request.Capabilities);
            Assert.DoesNotContain(
                "observe:"
                + ObservationDataScopesV1.Selection,
                fixture.Presenter.Request.Capabilities);
            Assert.DoesNotContain(
                "observe:"
                + ObservationDataScopesV1.LorePublic,
                fixture.Presenter.Request.Capabilities);
            Assert.DoesNotContain(
                "observe:"
                + ObservationDataScopesV1
                    .RetentionPersist,
                fixture.Presenter.Request.Capabilities);
            Assert.DoesNotContain(
                "observe:"
                + ObservationDataScopesV1.PlayerState,
                fixture.Presenter.Request.Capabilities);
            Assert.DoesNotContain(
                "observation.persist",
                fixture.Presenter.Request.Capabilities);
            Assert.DoesNotContain(
                AgentCapabilitiesV1.Click,
                fixture.Presenter.Request.Capabilities);

            using JsonDocument credential =
                JsonDocument.Parse(
                    File.ReadAllBytes(credentialPath));
            string proof = credential.RootElement
                .GetProperty("credentialProof")
                .GetString();
            using JsonDocument rendezvous =
                JsonDocument.Parse(
                    File.ReadAllBytes(
                        host.RendezvousPath));
            string ticket = rendezvous.RootElement
                .GetProperty("connectionTicket")
                .GetString();

            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                host.GatewayForTests.RunConnectionAsync(
                    Id("connection"),
                    pair.Server,
                    CancellationToken.None);
            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                new
                {
                    protocolVersion =
                        AgentProtocolV1.Version,
                    clientInstanceId =
                        HostFixture.ClientInstanceId,
                    clientKind = "jsonl_cli",
                    requestedCapabilities = new[]
                    {
                        AgentCapabilitiesV1
                            .SessionStatus,
                        AgentCapabilitiesV1
                            .ObservationGrantManage
                    },
                    nonce = Id("nonce"),
                    connectionToken = ticket,
                    credentialProof = proof
                });
            JsonElement welcome =
                await ReadJsonAsync(pair.Client);
            string lifecycleRef = welcome
                .GetProperty("result")
                .GetProperty("minimalSessionRef")
                .GetProperty("lifecycleRef")
                .GetString();
            Assert.False(
                string.IsNullOrWhiteSpace(lifecycleRef));

            await WriteRequestAsync(
                pair.Client,
                "grant",
                AgentMethodsV1.ObservationGrantIssue,
                new
                {
                    lifecycleRef,
                    targetKinds = new[]
                    {
                        "launcher",
                        "web_overlay"
                    },
                    dataScopes = new[]
                    {
                        ObservationDataScopesV1
                            .WindowMetadata
                    },
                    requestedTtlMs = 300_000,
                    allowEphemeralKeyframes = false,
                    allowPersistence = false,
                    allowExport = false
                });
            JsonElement response =
                await ReadJsonAsync(pair.Client);
            Assert.False(
                response.TryGetProperty("error", out _),
                response.GetRawText());
            JsonElement grant =
                response.GetProperty("result");
            Assert.Equal(
                host.SessionId,
                grant.GetProperty("sessionScope")
                    .GetProperty("sessionId")
                    .GetString());
            Assert.Equal(
                1UL,
                grant.GetProperty("sessionScope")
                    .GetProperty("lifecycleGeneration")
                    .GetUInt64());
            Assert.Equal(
                host.Targets.Launcher,
                Assert.Single(
                    grant.GetProperty("targetScope")
                        .EnumerateArray())
                    .GetString());

            pair.Client.Dispose();
            _ = await run.WaitAsync(
                TimeSpan.FromSeconds(5));
        }

        [Fact]
        public async Task WindowStatePixelsUsesCaptureProvider()
        {
            using var fixture = new HostFixture();
            await using LauncherAgentRuntimeHost host =
                fixture.CreateHost();
            string credentialPath =
                host.ShowDeveloperEnrollmentDialog();
            string proof = ReadStringProperty(
                credentialPath,
                "credentialProof");
            string ticket = ReadStringProperty(
                host.RendezvousPath,
                "connectionTicket");

            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                host.GatewayForTests.RunConnectionAsync(
                    Id("connection-pixels"),
                    pair.Server,
                    CancellationToken.None);
            await WriteRequestAsync(
                pair.Client,
                "hello-pixels",
                AgentMethodsV1.RuntimeHello,
                new
                {
                    protocolVersion =
                        AgentProtocolV1.Version,
                    clientInstanceId =
                        HostFixture.ClientInstanceId,
                    clientKind = "jsonl_cli",
                    requestedCapabilities = new[]
                    {
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        AgentCapabilitiesV1
                            .GetWindowState
                    },
                    nonce = Id("nonce-pixels"),
                    connectionToken = ticket,
                    credentialProof = proof
                });
            JsonElement welcome =
                await ReadJsonAsync(pair.Client);
            string lifecycleRef = welcome
                .GetProperty("result")
                .GetProperty("minimalSessionRef")
                .GetProperty("lifecycleRef")
                .GetString();

            await WriteRequestAsync(
                pair.Client,
                "grant-pixels",
                AgentMethodsV1.ObservationGrantIssue,
                new
                {
                    lifecycleRef,
                    targetKinds = new[] { "launcher" },
                    dataScopes = new[]
                    {
                        ObservationDataScopesV1.Pixels
                    },
                    requestedTtlMs = 300_000,
                    allowEphemeralKeyframes = false,
                    allowPersistence = false,
                    allowExport = false
                });
            JsonElement grantResponse =
                await ReadJsonAsync(pair.Client);
            string grantId = grantResponse
                .GetProperty("result")
                .GetProperty("observationGrantId")
                .GetString();

            await WriteRequestAsync(
                pair.Client,
                "window-state-pixels",
                AgentCapabilitiesV1.GetWindowState,
                new
                {
                    sessionId = host.SessionId,
                    observationGrantId = grantId,
                    dataScope =
                        ObservationDataScopesV1.Pixels,
                    targetId = host.Targets.Launcher
                });
            JsonElement state =
                await ReadJsonAsync(pair.Client);

            Assert.False(
                state.TryGetProperty("error", out _),
                state.GetRawText());
            Assert.Equal(
                host.Targets.Launcher,
                state.GetProperty("result")
                    .GetProperty("targetId")
                    .GetString());
            Assert.Equal(
                1,
                state.GetProperty("result")
                    .GetProperty("frames")
                    .GetArrayLength());
            Assert.Equal(1, fixture.FrameSources.CaptureCalls);

            pair.Client.Dispose();
            _ = await run.WaitAsync(
                TimeSpan.FromSeconds(5));
        }

        [Fact]
        public async Task WindowStateMetadataReturnsActualStateAndGenerations()
        {
            using var fixture = new HostFixture();
            await using LauncherAgentRuntimeHost host =
                fixture.CreateHost();
            string credentialPath =
                host.ShowDeveloperEnrollmentDialog();
            string proof = ReadStringProperty(
                credentialPath,
                "credentialProof");
            string ticket = ReadStringProperty(
                host.RendezvousPath,
                "connectionTicket");

            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                host.GatewayForTests.RunConnectionAsync(
                    Id("connection-state-meta"),
                    pair.Server,
                    CancellationToken.None);
            await WriteRequestAsync(
                pair.Client,
                "hello-state-meta",
                AgentMethodsV1.RuntimeHello,
                new
                {
                    protocolVersion =
                        AgentProtocolV1.Version,
                    clientInstanceId =
                        HostFixture.ClientInstanceId,
                    clientKind = "jsonl_cli",
                    requestedCapabilities = new[]
                    {
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        AgentCapabilitiesV1
                            .GetWindowState
                    },
                    nonce = Id("nonce-state-meta"),
                    connectionToken = ticket,
                    credentialProof = proof
                });
            JsonElement welcome =
                await ReadJsonAsync(pair.Client);
            string lifecycleRef = welcome
                .GetProperty("result")
                .GetProperty("minimalSessionRef")
                .GetProperty("lifecycleRef")
                .GetString();

            await WriteRequestAsync(
                pair.Client,
                "grant-state-meta",
                AgentMethodsV1.ObservationGrantIssue,
                new
                {
                    lifecycleRef,
                    targetKinds = new[] { "launcher" },
                    dataScopes = new[]
                    {
                        ObservationDataScopesV1
                            .WindowMetadata
                    },
                    requestedTtlMs = 300_000,
                    allowEphemeralKeyframes = false,
                    allowPersistence = false,
                    allowExport = false
                });
            JsonElement grantResponse =
                await ReadJsonAsync(pair.Client);
            string grantId = grantResponse
                .GetProperty("result")
                .GetProperty("observationGrantId")
                .GetString();

            await WriteRequestAsync(
                pair.Client,
                "window-state-meta",
                AgentCapabilitiesV1.GetWindowState,
                new
                {
                    sessionId = host.SessionId,
                    observationGrantId = grantId,
                    dataScope =
                        ObservationDataScopesV1
                            .WindowMetadata,
                    targetId = host.Targets.Launcher
                });
            JsonElement response =
                await ReadJsonAsync(pair.Client);

            Assert.False(
                response.TryGetProperty("error", out _),
                response.GetRawText());
            JsonElement state =
                response.GetProperty("result");
            Assert.Equal(
                host.Targets.Launcher,
                state.GetProperty("targetId")
                    .GetString());
            Assert.True(
                state.GetProperty("visible")
                    .GetBoolean());
            Assert.False(
                state.GetProperty("minimized")
                    .GetBoolean());
            Assert.Equal(
                "none",
                state.GetProperty(
                        "blockingModalKind")
                    .GetString());
            Assert.True(
                state.GetProperty("surfaceEpoch")
                    .GetUInt64() > 0);
            Assert.True(
                state.GetProperty(
                        "coordinateSpaceVersion")
                    .GetUInt64() > 0);
            Assert.True(
                state.GetProperty("focusEpoch")
                    .GetUInt64() > 0);
            Assert.True(
                state.GetProperty("modalEpoch")
                    .GetUInt64() > 0);
            Assert.False(
                state.TryGetProperty(
                    "surface",
                    out _));
            Assert.Equal(0, fixture.FrameSources.CaptureCalls);

            pair.Client.Dispose();
            _ = await run.WaitAsync(
                TimeSpan.FromSeconds(5));
        }

        [Fact]
        public async Task ExternalSystemDialogLeavesHumanReauthorizationLatched()
        {
            using var fixture = new HostFixture();
            await using LauncherAgentRuntimeHost host =
                fixture.CreateHost();

            using (host.EnterHumanOnlySecuritySurface())
            {
                SessionSnapshot blocked =
                    host.SnapshotForTests;
                Assert.Equal(
                    BlockingModalKind
                        .HumanOnlySecurity,
                    blocked.BlockingModalKind);
                Assert.True(
                    blocked
                        .HumanReauthorizationRequired);
            }

            SessionSnapshot cleared =
                host.SnapshotForTests;
            Assert.Equal(
                BlockingModalKind.None,
                cleared.BlockingModalKind);
            Assert.True(
                cleared.HumanReauthorizationRequired);
        }

        [Fact]
        public async Task SessionAttachDetachTracksConnectionBinding()
        {
            using var fixture = new HostFixture();
            await using LauncherAgentRuntimeHost host =
                fixture.CreateHost();
            string credentialPath =
                host.ShowDeveloperEnrollmentDialog();
            string proof = ReadStringProperty(
                credentialPath,
                "credentialProof");
            string ticket = ReadStringProperty(
                host.RendezvousPath,
                "connectionTicket");

            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                host.GatewayForTests.RunConnectionAsync(
                    Id("connection-binding"),
                    pair.Server,
                    CancellationToken.None);
            await WriteRequestAsync(
                pair.Client,
                "hello-binding",
                AgentMethodsV1.RuntimeHello,
                new
                {
                    protocolVersion =
                        AgentProtocolV1.Version,
                    clientInstanceId =
                        HostFixture.ClientInstanceId,
                    clientKind = "jsonl_cli",
                    requestedCapabilities = new[]
                    {
                        AgentCapabilitiesV1.SessionAttach,
                        AgentCapabilitiesV1.SessionDetach,
                        AgentCapabilitiesV1
                            .ObservationGrantManage
                    },
                    nonce = Id("nonce-binding"),
                    connectionToken = ticket,
                    credentialProof = proof
                });
            JsonElement welcome =
                await ReadJsonAsync(pair.Client);
            Assert.False(
                welcome.TryGetProperty("error", out _),
                welcome.GetRawText());
            string lifecycleRef = welcome
                .GetProperty("result")
                .GetProperty("minimalSessionRef")
                .GetProperty("lifecycleRef")
                .GetString();
            var binding = new
            {
                sessionId = host.SessionId,
                lifecycleGeneration = 1
            };

            await WriteRequestAsync(
                pair.Client,
                "detach-before-attach",
                AgentCapabilitiesV1.SessionDetach,
                binding);
            JsonElement unattached =
                await ReadJsonAsync(pair.Client);
            Assert.Equal(
                "session_mismatch",
                unattached.GetProperty("error")
                    .GetProperty("data")
                    .GetProperty("reasonCode")
                    .GetString());

            await WriteRequestAsync(
                pair.Client,
                "attach",
                AgentCapabilitiesV1.SessionAttach,
                binding);
            JsonElement attached =
                await ReadJsonAsync(pair.Client);
            Assert.True(
                attached.GetProperty("result")
                    .GetProperty("attached")
                    .GetBoolean());

            await WriteRequestAsync(
                pair.Client,
                "attach-idempotent",
                AgentCapabilitiesV1.SessionAttach,
                binding);
            JsonElement reattached =
                await ReadJsonAsync(pair.Client);
            Assert.True(
                reattached.GetProperty("result")
                    .GetProperty("attached")
                    .GetBoolean());

            await WriteRequestAsync(
                pair.Client,
                "detach",
                AgentCapabilitiesV1.SessionDetach,
                binding);
            JsonElement detached =
                await ReadJsonAsync(pair.Client);
            Assert.False(
                detached.GetProperty("result")
                    .GetProperty("attached")
                    .GetBoolean());

            await WriteRequestAsync(
                pair.Client,
                "detach-idempotent-rejected",
                AgentCapabilitiesV1.SessionDetach,
                binding);
            JsonElement alreadyDetached =
                await ReadJsonAsync(pair.Client);
            Assert.Equal(
                "session_mismatch",
                alreadyDetached.GetProperty("error")
                    .GetProperty("data")
                    .GetProperty("reasonCode")
                    .GetString());

            var grantRequest = new
            {
                lifecycleRef,
                targetKinds = new[] { "launcher" },
                dataScopes = new[]
                {
                    ObservationDataScopesV1
                        .WindowMetadata
                },
                requestedTtlMs = 60_000,
                allowEphemeralKeyframes = false,
                allowPersistence = false,
                allowExport = false
            };
            await WriteRequestAsync(
                pair.Client,
                "grant-while-detached",
                AgentMethodsV1.ObservationGrantIssue,
                grantRequest);
            JsonElement grantWhileDetached =
                await ReadJsonAsync(pair.Client);
            Assert.Equal(
                "session_mismatch",
                grantWhileDetached.GetProperty("error")
                    .GetProperty("data")
                    .GetProperty("reasonCode")
                    .GetString());

            await WriteRequestAsync(
                pair.Client,
                "reattach-after-detach",
                AgentCapabilitiesV1.SessionAttach,
                binding);
            JsonElement attachedAgain =
                await ReadJsonAsync(pair.Client);
            Assert.True(
                attachedAgain.GetProperty("result")
                    .GetProperty("attached")
                    .GetBoolean());
            await WriteRequestAsync(
                pair.Client,
                "grant-after-reattach",
                AgentMethodsV1.ObservationGrantIssue,
                grantRequest);
            JsonElement grantAfterReattach =
                await ReadJsonAsync(pair.Client);
            Assert.False(
                grantAfterReattach.TryGetProperty(
                    "error",
                    out _),
                grantAfterReattach.GetRawText());

            pair.Client.Dispose();
            _ = await run.WaitAsync(
                TimeSpan.FromSeconds(5));
        }

        [Fact]
        public async Task
            StopAdmissionAndDisposeAreIdempotentAndFailClosed()
        {
            using var fixture = new HostFixture();
            LauncherAgentRuntimeHost host =
                fixture.CreateHost();
            string rendezvousPath = host.RendezvousPath;
            Assert.True(File.Exists(rendezvousPath));

            host.StopAdmission();
            host.StopAdmission();

            Assert.False(File.Exists(rendezvousPath));
            Assert.False(host.RefreshSurfaces());
            Assert.False(host.AdvanceWebDocument());
            Assert.Null(
                host.ShowDeveloperEnrollmentDialog());

            await host.DisposeAsync();
            await host.DisposeAsync();

            Assert.True(host.IsDisposedForTests);
            Assert.False(File.Exists(rendezvousPath));
        }

        [Fact]
        public async Task
            RotationClosesOldConnectionAndNewCredentialReconnects()
        {
            using var fixture = new HostFixture();
            await using LauncherAgentRuntimeHost host =
                fixture.CreateHost();
            string credentialPath =
                host.ShowDeveloperEnrollmentDialog();
            string firstProof =
                ReadStringProperty(
                    credentialPath,
                    "credentialProof");
            string firstTicket =
                ReadStringProperty(
                    host.RendezvousPath,
                    "connectionTicket");

            using DuplexPair first = DuplexPair.Create();
            Task<AgentConnectionTermination> firstRun =
                host.GatewayForTests.RunConnectionAsync(
                    Id("connection-first"),
                    first.Server,
                    CancellationToken.None);
            await WriteRequestAsync(
                first.Client,
                "hello-first",
                AgentMethodsV1.RuntimeHello,
                DeveloperHello(
                    firstTicket,
                    firstProof));
            JsonElement firstWelcome =
                await ReadJsonAsync(first.Client);
            Assert.False(
                firstWelcome.TryGetProperty(
                    "error",
                    out _));

            string rotatedPath =
                host.ShowDeveloperEnrollmentDialog();
            string secondProof =
                ReadStringProperty(
                    rotatedPath,
                    "credentialProof");
            Assert.NotEqual(
                firstProof,
                secondProof);
            AgentConnectionTermination rotated =
                await firstRun.WaitAsync(
                    TimeSpan.FromSeconds(5));
            Assert.Equal(
                AgentConnectionTerminationKind.Cancelled,
                rotated.Kind);
            Assert.Equal(
                "developer_enrollment_rotated",
                rotated.ReasonCode);

            string secondTicket =
                ReadStringProperty(
                    host.RendezvousPath,
                    "connectionTicket");
            using DuplexPair second = DuplexPair.Create();
            Task<AgentConnectionTermination> secondRun =
                host.GatewayForTests.RunConnectionAsync(
                    Id("connection-second"),
                    second.Server,
                    CancellationToken.None);
            await WriteRequestAsync(
                second.Client,
                "hello-second",
                AgentMethodsV1.RuntimeHello,
                DeveloperHello(
                    secondTicket,
                    secondProof));
            JsonElement secondWelcome =
                await ReadJsonAsync(second.Client);
            Assert.False(
                secondWelcome.TryGetProperty(
                    "error",
                    out _));

            Assert.True(
                host.RevokeDeveloperEnrollment(
                    HostFixture.ClientInstanceId));
            Assert.False(
                File.Exists(rotatedPath));
            AgentConnectionTermination revoked =
                await secondRun.WaitAsync(
                    TimeSpan.FromSeconds(5));
            Assert.Equal(
                AgentConnectionTerminationKind.Cancelled,
                revoked.Kind);
            Assert.Equal(
                "developer_enrollment_revoked",
                revoked.ReasonCode);
        }

        private static object DeveloperHello(
            string ticket,
            string proof)
        {
            return new
            {
                protocolVersion =
                    AgentProtocolV1.Version,
                clientInstanceId =
                    HostFixture.ClientInstanceId,
                clientKind = "jsonl_cli",
                requestedCapabilities = new[]
                {
                    AgentCapabilitiesV1
                        .SessionStatus
                },
                nonce = Id("nonce"),
                connectionToken = ticket,
                credentialProof = proof
            };
        }

        private static string ReadStringProperty(
            string path,
            string propertyName)
        {
            using JsonDocument document =
                JsonDocument.Parse(
                    File.ReadAllBytes(path));
            return document.RootElement
                .GetProperty(propertyName)
                .GetString();
        }

        private static async Task WriteRequestAsync(
            Stream stream,
            string id,
            string method,
            object parameters)
        {
            byte[] payload =
                JsonSerializer.SerializeToUtf8Bytes(
                    new
                    {
                        jsonrpc = "2.0",
                        id,
                        method,
                        @params = parameters
                    },
                    AgentProtocolV1.JsonOptions);
            await Codec.WriteAsync(
                stream,
                new AgentFrame(
                    1,
                    AgentFrameKind.JsonRpc,
                    0,
                    payload),
                CancellationToken.None);
            await stream.FlushAsync();
        }

        private static async Task<JsonElement> ReadJsonAsync(
            Stream stream)
        {
            AgentFrame frame = await Codec.ReadAsync(
                    stream,
                    CancellationToken.None)
                .WaitAsync(TimeSpan.FromSeconds(5));
            Assert.NotNull(frame);
            Assert.Equal(
                AgentFrameKind.JsonRpc,
                frame.Kind);
            using JsonDocument document =
                JsonDocument.Parse(frame.Payload);
            return document.RootElement.Clone();
        }

        private static string Id(string prefix)
        {
            return (prefix
                + "_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
                .Substring(0, 32);
        }

        private sealed class HostFixture : IDisposable
        {
            private const long LauncherWindow = 1001;
            private const long WebWindow = 1002;

            public const string ClientInstanceId =
                "client_runtime_host_AAAAAA";

            private readonly string _root = Path.Combine(
                Path.GetTempPath(),
                "cf7-runtime-host-tests",
                Guid.NewGuid().ToString("N"));
            private readonly SessionRegistryHostOwner _owner;
            private readonly SessionSurfaceRegistry _registry;
            private readonly FakeSurfaceProbe _probe =
                new FakeSurfaceProbe();

            public HostFixture()
            {
                Directory.CreateDirectory(ProjectRoot);
                _owner =
                    SessionRegistryHostOwner
                        .CaptureCurrentLauncher();
                _registry = new SessionSurfaceRegistry(
                    _owner,
                    new RecordingSessionSurfaceHostValidator());
                _probe.Windows.Add(
                    LauncherWindow,
                    Window(_owner.LauncherProcess.ProcessId));
                _probe.Windows.Add(
                    WebWindow,
                    Window(_owner.LauncherProcess.ProcessId));
                _probe.Focus =
                    new WindowsSessionFocusSnapshot(
                        LauncherWindow,
                        LauncherWindow);
            }

            public RecordingEnrollmentPresenter Presenter
            {
                get;
            } = new RecordingEnrollmentPresenter();

            public RecordingFrameSourceFactory FrameSources
            {
                get;
            } = new RecordingFrameSourceFactory();

            private string ProjectRoot =>
                Path.Combine(_root, "project");

            private string LocalRoot =>
                Path.Combine(_root, "local");

            public LauncherAgentRuntimeHost CreateHost()
            {
                return LauncherAgentRuntimeHost.CreateProduction(
                    new LauncherAgentRuntimeHostOptions
                    {
                        ProjectRoot = ProjectRoot,
                        LocalAppDataOverride = LocalRoot,
                        DeveloperEnrollmentPresenter =
                            Presenter,
                        SurfaceRefreshInterval =
                            TimeSpan.FromMinutes(1),
                        SurfaceSource = targets =>
                            new[]
                            {
                                new WindowsSessionSurfaceSpec(
                                    targets.Launcher,
                                    SurfaceKind.Launcher,
                                    AgentTargetSafetyKind
                                        .RuntimeOwned,
                                    SessionSurfaceOwnerRelation
                                        .LauncherTopLevel,
                                    _owner.LauncherProcess,
                                    LauncherWindow,
                                    null,
                                    0,
                                    new[]
                                    {
                                        ObservationMode
                                            .WindowGraphicsCapture
                                    },
                                    new[]
                                    {
                                        InputMode
                                            .SendInputGuarded
                                    },
                                    0),
                                new WindowsSessionSurfaceSpec(
                                    targets.WebOverlay,
                                    SurfaceKind.WebOverlay,
                                    AgentTargetSafetyKind
                                        .RuntimeOwned,
                                    SessionSurfaceOwnerRelation
                                        .LauncherOwned,
                                    _owner.LauncherProcess,
                                    WebWindow,
                                    targets.Launcher,
                                    LauncherWindow,
                                    new[]
                                    {
                                        ObservationMode
                                            .WindowGraphicsCapture
                                    },
                                    new[]
                                    {
                                        InputMode
                                            .SendInputGuarded
                                    },
                                    10)
                            }
                    },
                    new LauncherAgentRuntimeHostServices
                    {
                        Registry = _registry,
                        RegistryOwner = _owner,
                        SurfaceProbe = _probe,
                        FrameSources = FrameSources,
                        FileProtection =
                            new NoOpProtection()
                    });
            }

            public void Dispose()
            {
                if (Directory.Exists(_root))
                    Directory.Delete(_root, true);
            }

            private static WindowsSessionWindowSnapshot
                Window(int processId)
            {
                var rect =
                    new SessionPhysicalRect(
                        10,
                        20,
                        800,
                        600);
                return new WindowsSessionWindowSnapshot(
                    processId,
                    rect,
                    rect,
                    rect,
                    96,
                    true,
                    false);
            }
        }

        private sealed class RecordingEnrollmentPresenter
            : ILauncherAgentDeveloperEnrollmentPresenter
        {
            public LauncherAgentDeveloperEnrollmentPresentationRequest
                Request { get; private set; }

            public LauncherAgentDeveloperEnrollmentSelection
                Present(
                    LauncherAgentDeveloperEnrollmentPresentationRequest
                        request)
            {
                Request = request;
                string launcherTarget = request.Targets
                    .Single(target =>
                        target.Kind
                            == SurfaceKind.Launcher)
                    .TargetId;
                return new
                    LauncherAgentDeveloperEnrollmentSelection(
                        HostFixture.ClientInstanceId,
                        new[]
                        {
                            AgentCapabilitiesV1
                                .SessionStatus,
                            AgentCapabilitiesV1
                                .ObservationGrantManage,
                            AgentCapabilitiesV1
                                .GetWindowState,
                            AgentCapabilitiesV1
                                .SessionAttach,
                            AgentCapabilitiesV1
                                .SessionDetach,
                            "observe:"
                                + ObservationDataScopesV1
                                    .WindowMetadata,
                            "observe:"
                                + ObservationDataScopesV1
                                    .Pixels
                        },
                        new[] { launcherTarget },
                        TimeSpan.FromHours(1));
            }
        }

        private sealed class FakeSurfaceProbe
            : IWindowsSessionSurfaceProbe
        {
            public Dictionary<
                long,
                WindowsSessionWindowSnapshot> Windows { get; } =
                    new Dictionary<
                        long,
                        WindowsSessionWindowSnapshot>();

            public WindowsSessionFocusSnapshot Focus { get; set; }

            public bool IsInteractiveDesktopAvailable()
            {
                return true;
            }

            public bool TryProbeKnownWindow(
                long knownWindowHandle,
                out WindowsSessionWindowSnapshot snapshot)
            {
                return Windows.TryGetValue(
                    knownWindowHandle,
                    out snapshot);
            }

            public bool TryProbeFocus(
                out WindowsSessionFocusSnapshot snapshot)
            {
                snapshot = Focus;
                return snapshot != null;
            }

            public bool IsSameOrChildWindow(
                long knownAncestorWindowHandle,
                long candidateWindowHandle)
            {
                return knownAncestorWindowHandle
                    == candidateWindowHandle;
            }
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

        private sealed class DuplexPair : IDisposable
        {
            private readonly AnonymousPipeServerStream
                _clientToServerReader;
            private readonly AnonymousPipeClientStream
                _clientToServerWriter;
            private readonly AnonymousPipeServerStream
                _serverToClientWriter;
            private readonly AnonymousPipeClientStream
                _serverToClientReader;

            private DuplexPair(
                AnonymousPipeServerStream clientToServerReader,
                AnonymousPipeClientStream clientToServerWriter,
                AnonymousPipeServerStream serverToClientWriter,
                AnonymousPipeClientStream serverToClientReader)
            {
                _clientToServerReader =
                    clientToServerReader;
                _clientToServerWriter =
                    clientToServerWriter;
                _serverToClientWriter =
                    serverToClientWriter;
                _serverToClientReader =
                    serverToClientReader;
                Server = new SplitDuplexStream(
                    _clientToServerReader,
                    _serverToClientWriter);
                Client = new SplitDuplexStream(
                    _serverToClientReader,
                    _clientToServerWriter);
            }

            public Stream Server { get; }
            public Stream Client { get; }

            public static DuplexPair Create()
            {
                var clientToServerReader =
                    new AnonymousPipeServerStream(
                        PipeDirection.In,
                        HandleInheritability.None);
                var clientToServerWriter =
                    new AnonymousPipeClientStream(
                        PipeDirection.Out,
                        clientToServerReader
                            .GetClientHandleAsString());
                var serverToClientWriter =
                    new AnonymousPipeServerStream(
                        PipeDirection.Out,
                        HandleInheritability.None);
                var serverToClientReader =
                    new AnonymousPipeClientStream(
                        PipeDirection.In,
                        serverToClientWriter
                            .GetClientHandleAsString());
                return new DuplexPair(
                    clientToServerReader,
                    clientToServerWriter,
                    serverToClientWriter,
                    serverToClientReader);
            }

            public void Dispose()
            {
                Client.Dispose();
                Server.Dispose();
            }
        }

        private sealed class SplitDuplexStream : Stream
        {
            private readonly Stream _read;
            private readonly Stream _write;
            private int _disposed;

            public SplitDuplexStream(
                Stream read,
                Stream write)
            {
                _read = read;
                _write = write;
            }

            public override bool CanRead => true;
            public override bool CanSeek => false;
            public override bool CanWrite => true;
            public override long Length =>
                throw new NotSupportedException();

            public override long Position
            {
                get => throw new NotSupportedException();
                set => throw new NotSupportedException();
            }

            public override void Flush()
            {
                _write.Flush();
            }

            public override Task FlushAsync(
                CancellationToken cancellationToken)
            {
                return _write.FlushAsync(
                    cancellationToken);
            }

            public override int Read(
                byte[] buffer,
                int offset,
                int count)
            {
                return _read.Read(
                    buffer,
                    offset,
                    count);
            }

            public override ValueTask<int> ReadAsync(
                Memory<byte> buffer,
                CancellationToken cancellationToken = default)
            {
                return _read.ReadAsync(
                    buffer,
                    cancellationToken);
            }

            public override void Write(
                byte[] buffer,
                int offset,
                int count)
            {
                _write.Write(buffer, offset, count);
            }

            public override ValueTask WriteAsync(
                ReadOnlyMemory<byte> buffer,
                CancellationToken cancellationToken = default)
            {
                return _write.WriteAsync(
                    buffer,
                    cancellationToken);
            }

            public override long Seek(
                long offset,
                SeekOrigin origin)
            {
                throw new NotSupportedException();
            }

            public override void SetLength(long value)
            {
                throw new NotSupportedException();
            }

            protected override void Dispose(bool disposing)
            {
                if (disposing
                    && Interlocked.Exchange(
                        ref _disposed,
                        1) == 0)
                {
                    _write.Dispose();
                    _read.Dispose();
                }
                base.Dispose(disposing);
            }
        }
    }
}
