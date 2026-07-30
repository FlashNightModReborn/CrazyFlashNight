using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Observation
{
    public sealed class ObservationCaptureBrokerTests
    {
        private const string SessionId =
            "session_AAAAAAAAAAAAAAAAAAAAAAAA";
        private const string PrimaryTarget =
            "target_flash_AAAAAAAAAAAAAAAAAAA";
        private const string ModalTarget =
            "target_modal_AAAAAAAAAAAAAAAAAAA";
        private const string AttemptId =
            "attempt_AAAAAAAAAAAAAAAAAAAAAAA";
        private const string PanelId =
            "panel_AAAAAAAAAAAAAAAAAAAAAAAAA";
        private const string ClientId = "developer-client";

        [Fact]
        public async Task MissingGrantDoesNotResolveSessionOrStartCapture()
        {
            using Setup setup = CreateSetup(includeModal: false);

            ObservationCaptureOutcome outcome =
                await setup.Broker.CaptureAsync(
                    Request(
                        setup,
                        observationGrantId:
                            "missing_AAAAAAAAAAAAAAAAAAAAAA"));

            Assert.False(outcome.Success);
            Assert.Equal(
                "observation_grant_not_found",
                outcome.ReasonCode);
            Assert.Equal(0, setup.Targets.CreatePlanCalls);
            Assert.Equal(0, setup.Frames.CreateCalls);
            Assert.Equal(0, setup.Frames.CaptureCalls);
        }

        [Theory]
        [InlineData("window_metadata")]
        [InlineData("accessibility")]
        [InlineData("player_state")]
        [InlineData("data.export")]
        public async Task NonPixelScopeNeverTouchesGrantSessionOrContent(
            string dataScope)
        {
            using Setup setup = CreateSetup(includeModal: false);

            ObservationCaptureOutcome outcome =
                await setup.Broker.CaptureAsync(
                    Request(
                        setup,
                        dataScope: dataScope));

            Assert.False(outcome.Success);
            Assert.Equal(
                "observation_scope_mismatch",
                outcome.ReasonCode);
            Assert.Null(outcome.Envelope);
            Assert.Equal(0, setup.Targets.CreatePlanCalls);
            Assert.Equal(0, setup.Frames.CreateCalls);
            Assert.Equal(0, setup.Frames.CaptureCalls);
            Assert.Empty(setup.Audit.Events);
        }

        [Fact]
        public async Task OwnedBusinessModalIsSeparateAuthorizedZOrderedFrame()
        {
            using Setup setup = CreateSetup(includeModal: true);

            ObservationCaptureOutcome outcome =
                await setup.Broker.CaptureAsync(Request(setup));

            Assert.True(outcome.Success, outcome.ReasonCode);
            Assert.Equal(BlockingModalKind.BusinessOwned,
                outcome.Envelope.BlockingModalKind);
            Assert.True(outcome.Envelope.Visible);
            Assert.False(outcome.Envelope.Minimized);
            Assert.True(outcome.Envelope.Active);
            Assert.Equal(
                new[] { PrimaryTarget, ModalTarget },
                outcome.Envelope.Frames
                    .Select(frame => frame.TargetId)
                    .ToArray());
            Assert.Equal(
                new[] { 10, 20 },
                outcome.Envelope.Frames
                    .Select(frame => frame.ZIndex)
                    .ToArray());
            Assert.All(
                outcome.Envelope.Frames,
                frame =>
                {
                    Assert.NotEmpty(frame.OpaqueContentHandle);
                    Assert.Equal(64, frame.ContentHash.Length);
                });
            Assert.Empty(
                AgentContractValidator.Validate(outcome.Envelope));
            Assert.Equal(2, setup.Frames.CreateCalls);
            Assert.Equal(2, setup.Frames.CaptureCalls);
        }

        [Fact]
        public async Task MissingModalTargetScopeRejectsBeforeAnyCapture()
        {
            using Setup setup = CreateSetup(
                includeModal: true,
                grantModal: false);

            ObservationCaptureOutcome outcome =
                await setup.Broker.CaptureAsync(Request(setup));

            Assert.False(outcome.Success);
            Assert.Equal("target_scope_denied", outcome.ReasonCode);
            Assert.Equal(1, setup.Targets.CreatePlanCalls);
            Assert.Equal(0, setup.Frames.CreateCalls);
            Assert.Equal(0, setup.Frames.CaptureCalls);
        }

        [Theory]
        [InlineData("human_only_security_surface")]
        [InlineData("foreign_modal")]
        [InlineData("unknown_modal")]
        [InlineData("target_minimized")]
        [InlineData("target_not_visible")]
        public async Task UnsafeOrUnavailableTargetReturnsNoPixelMetadata(
            string rejection)
        {
            using Setup setup = CreateSetup(includeModal: false);
            setup.Targets.CreateReason = rejection;

            ObservationCaptureOutcome outcome =
                await setup.Broker.CaptureAsync(Request(setup));

            Assert.False(outcome.Success);
            Assert.Equal(rejection, outcome.ReasonCode);
            Assert.Null(outcome.Envelope);
            Assert.Equal(0, setup.Frames.CreateCalls);
            Assert.DoesNotContain(
                setup.Audit.Events,
                entry => entry.Accepted);
        }

        [Theory]
        [InlineData("stale_lifecycle")]
        [InlineData("stale_attempt")]
        [InlineData("stale_surface")]
        [InlineData("stale_coordinate_space")]
        [InlineData("stale_document")]
        [InlineData("stale_panel_instance")]
        [InlineData("stale_focus")]
        [InlineData("stale_modal")]
        public async Task GenerationChangeAfterCaptureDiscardsPixels(
            string staleReason)
        {
            using Setup setup = CreateSetup(includeModal: false);
            byte[] captured = ColorPixels(4, 3);
            setup.Frames.Set(
                PrimaryTarget,
                _ =>
                {
                    setup.Targets.ValidateReason = staleReason;
                    return Task.FromResult(
                        WindowFrameCaptureResult.Captured(
                            captured,
                            4,
                            3,
                            ObservationMode.WindowGraphicsCapture));
                });

            ObservationCaptureOutcome outcome =
                await setup.Broker.CaptureAsync(Request(setup));

            Assert.False(outcome.Success);
            Assert.Equal(staleReason, outcome.ReasonCode);
            Assert.All(captured, value => Assert.Equal(0, value));
            Assert.DoesNotContain(
                setup.Audit.Events,
                entry => entry.EventType == "pixel_handle_open"
                    && entry.Accepted);
        }

        [Fact]
        public async Task BlackWgcUsesOnlyExplicitlyGrantedValidatedFallback()
        {
            using Setup setup = CreateSetup(
                includeModal: false,
                includeFlashFallbackMode: true);
            setup.Frames.Set(
                PrimaryTarget,
                _ => Task.FromResult(
                    RecordingFrameSourceFactory.BlackFrame()));

            ObservationCaptureOutcome noFallback =
                await setup.Broker.CaptureAsync(Request(setup));
            Assert.False(noFallback.Success);
            Assert.Equal(
                "capture_unavailable",
                noFallback.ReasonCode);
            Assert.Equal(0, setup.Fallback.Calls);

            ObservationCaptureOutcome allowed =
                await setup.Broker.CaptureAsync(
                    Request(setup, allowFallback: true));
            Assert.True(allowed.Success, allowed.ReasonCode);
            Assert.Equal(1, setup.Fallback.Calls);
            Assert.Single(allowed.Envelope.Frames);
        }

        [Fact]
        public async Task PerSourceBackpressureHasNoPendingQueue()
        {
            using Setup setup = CreateSetup(includeModal: false);
            var entered = new TaskCompletionSource<bool>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var release =
                new TaskCompletionSource<WindowFrameCaptureResult>(
                    TaskCreationOptions.RunContinuationsAsynchronously);
            setup.Frames.Set(
                PrimaryTarget,
                _ =>
                {
                    entered.TrySetResult(true);
                    return release.Task;
                });

            Task<ObservationCaptureOutcome> first =
                setup.Broker.CaptureAsync(Request(setup));
            await entered.Task;
            ObservationCaptureOutcome second =
                await setup.Broker.CaptureAsync(Request(setup));

            Assert.False(second.Success);
            Assert.Equal(
                "capture_backpressure",
                second.ReasonCode);
            Assert.Equal(1, setup.Frames.CaptureCalls);

            release.SetResult(
                RecordingFrameSourceFactory.ColorFrame());
            ObservationCaptureOutcome completed = await first;
            Assert.True(completed.Success, completed.ReasonCode);
            Assert.Equal(1, setup.Frames.CaptureCalls);
        }

        [Fact]
        public async Task CancellationDisposesOtherCompletedSurfacePixels()
        {
            using Setup setup = CreateSetup(includeModal: true);
            byte[] completedPixels = ColorPixels(4, 3);
            setup.Frames.Set(
                PrimaryTarget,
                _ => Task.FromResult(
                    WindowFrameCaptureResult.Captured(
                        completedPixels,
                        4,
                        3,
                        ObservationMode.WindowGraphicsCapture)));
            setup.Frames.Set(
                ModalTarget,
                _ => Task.FromCanceled<WindowFrameCaptureResult>(
                    new CancellationToken(canceled: true)));

            ObservationCaptureOutcome outcome =
                await setup.Broker.CaptureAsync(Request(setup));

            Assert.False(outcome.Success);
            Assert.Equal("capture_cancelled", outcome.ReasonCode);
            Assert.All(
                completedPixels,
                value => Assert.Equal(0, value));
            Assert.DoesNotContain(
                setup.Audit.Events,
                entry => entry.EventType == "pixel_handle_open");
        }

        [Fact]
        public async Task GrantRevocationDuringCaptureReturnsNoHandle()
        {
            using Setup setup = CreateSetup(includeModal: false);
            setup.Targets.OnValidate = () =>
                setup.Grants.Revoke(
                    setup.Grant.ObservationGrantId,
                    "human_override");

            ObservationCaptureOutcome outcome =
                await setup.Broker.CaptureAsync(Request(setup));

            Assert.False(outcome.Success);
            Assert.Equal("human_override", outcome.ReasonCode);
            Assert.Null(outcome.Envelope);
            Assert.DoesNotContain(
                setup.Audit.Events,
                entry => entry.EventType == "pixel_handle_open"
                    && entry.Accepted);
        }

        [Fact]
        public async Task OtherReaderDoesNotInvalidateButWriteConsumesOnce()
        {
            using Setup setup = CreateSetup(includeModal: false);
            ObservationCaptureOutcome first =
                await setup.Broker.CaptureAsync(Request(setup));
            ObservationCaptureOutcome second =
                await setup.Broker.CaptureAsync(Request(setup));
            Assert.True(first.Success);
            Assert.True(second.Success);

            ObservationUseRequest use = Use(
                setup,
                first.Envelope);
            Assert.True(setup.Broker.TryUseObservation(
                use,
                consumeForWrite: false,
                out _));
            Assert.True(setup.Broker.TryUseObservation(
                use,
                consumeForWrite: true,
                out _));
            Assert.False(setup.Broker.TryUseObservation(
                use,
                consumeForWrite: true,
                out string replayReason));
            Assert.Equal("observation_consumed", replayReason);

            Assert.True(setup.Broker.TryUseObservation(
                Use(setup, second.Envelope),
                consumeForWrite: false,
                out _));
        }

        [Fact]
        public async Task ObservationTtlFailsStaleWithoutBlindReuse()
        {
            using Setup setup = CreateSetup(includeModal: false);
            ObservationCaptureOutcome captured =
                await setup.Broker.CaptureAsync(Request(setup));
            setup.Clock.Advance(TimeSpan.FromMilliseconds(
                AgentProtocolV1.MaximumObservationTtlMs + 1));

            Assert.False(setup.Broker.TryUseObservation(
                Use(setup, captured.Envelope),
                consumeForWrite: false,
                out string reason));
            Assert.Equal("stale_observation_ttl", reason);
        }

        [Fact]
        public async Task ObservationExpiringDuringFinalValidationCannotBeUsed()
        {
            using Setup setup = CreateSetup(includeModal: false);
            ObservationCaptureOutcome captured =
                await setup.Broker.CaptureAsync(Request(setup));
            setup.Targets.OnValidate = () =>
                setup.Clock.Advance(
                    TimeSpan.FromMilliseconds(
                        AgentProtocolV1
                            .MaximumObservationTtlMs
                        + 1));

            Assert.False(setup.Broker.TryUseObservation(
                Use(setup, captured.Envelope),
                consumeForWrite: true,
                out string reason));
            Assert.Equal("stale_observation_ttl", reason);

            Assert.False(setup.Broker.TryUseObservation(
                Use(setup, captured.Envelope),
                consumeForWrite: false,
                out string replayReason));
            Assert.Equal(
                "observation_not_found",
                replayReason);
            PixelContentReadOutcome content =
                setup.Content.Read(
                new PixelContentReadRequest
                {
                    Handle = captured.Envelope.Frames[0]
                        .OpaqueContentHandle,
                    ClientInstanceId = ClientId,
                    SecurityPrincipalId =
                        setup.Credential
                            .SecurityPrincipalId,
                    SessionId = SessionId,
                    ObservationGrantId =
                        setup.Grant.ObservationGrantId,
                    ObservationId =
                        captured.Envelope.ObservationId,
                    Offset = 0,
                    MaximumBytes = 1
                });
            Assert.False(content.Success);
            Assert.Equal(
                "stale_observation_ttl",
                content.ReasonCode);
        }

        [Fact]
        public async Task AcknowledgeTerminallyReleasesObservationAndContent()
        {
            using Setup setup = CreateSetup(includeModal: false);
            ObservationCaptureOutcome captured =
                await setup.Broker.CaptureAsync(Request(setup));
            ObservationUseRequest use =
                Use(setup, captured.Envelope);

            Assert.True(
                setup.Broker.TryAcknowledgeObservation(
                    use,
                    out string acknowledgeReason));
            Assert.Null(acknowledgeReason);
            Assert.False(setup.Broker.TryUseObservation(
                use,
                consumeForWrite: false,
                out string useReason));
            Assert.Equal(
                "observation_not_found",
                useReason);

            PixelContentReadOutcome content =
                setup.Content.Read(
                    new PixelContentReadRequest
                    {
                        Handle = captured.Envelope.Frames[0]
                            .OpaqueContentHandle,
                        ClientInstanceId = ClientId,
                        SecurityPrincipalId =
                            setup.Credential
                                .SecurityPrincipalId,
                        SessionId = SessionId,
                        ObservationGrantId =
                            setup.Grant.ObservationGrantId,
                        ObservationId =
                            captured.Envelope.ObservationId,
                        Offset = 0,
                        MaximumBytes = 1
                    });
            Assert.False(content.Success);
            Assert.Equal(
                "observation_acknowledged",
                content.ReasonCode);
        }

        private static Setup CreateSetup(
            bool includeModal,
            bool grantModal = true,
            bool includeFlashFallbackMode = false)
        {
            var clock = new ManualObservationClock();
            var targets = new MutableObservationAuthority();
            targets.AddTarget(PrimaryTarget);
            if (includeModal)
                targets.AddTarget(ModalTarget);
            targets.Plan = Plan(
                includeModal,
                includeFlashFallbackMode);

            var credentialAuthority =
                new PrincipalCredentialAuthority(
                    clock,
                    new ObservationEnrollmentVerifier());
            PrincipalCredential credential =
                credentialAuthority.IssueDeveloper(
                    new DeveloperEnrollmentEvidence
                    {
                        ClientInstanceId = ClientId,
                        EnrollmentReceipt =
                            "developer-enrollment-receipt",
                        AllowedCapabilities =
                            new[] { "observe:pixels" },
                        AllowedTargets = new[] { "*" }
                    });
            var grantBroker = new ObservationGrantBroker(
                clock,
                credentialAuthority,
                targets);
            var targetScopes =
                new List<ObservationTargetScope>
                {
                    new ObservationTargetScope
                    {
                        TargetId = PrimaryTarget
                    }
                };
            if (includeModal && grantModal)
            {
                targetScopes.Add(
                    new ObservationTargetScope
                    {
                        TargetId = ModalTarget
                    });
            }
            ObservationGrant grant = grantBroker.Issue(
                new ObservationGrantRequest
                {
                    CredentialId = credential.CredentialId,
                    ClientInstanceId = ClientId,
                    SessionId = SessionId,
                    Targets = targetScopes,
                    DataScopes = new[] { "pixels" },
                    RequestedLifetime = TimeSpan.FromMinutes(5),
                    AllowEphemeralKeyframes = true
                });
            var audit = new RecordingPixelAuditSink();
            var content = new PixelContentHandleStore(
                clock,
                grantBroker,
                audit);
            var frames = new RecordingFrameSourceFactory();
            var fallback = new RecordingFlashFallback();
            var broker = new ObservationCaptureBroker(
                clock,
                grantBroker,
                targets,
                frames,
                fallback,
                content);
            return new Setup(
                clock,
                targets,
                credential,
                grant,
                grantBroker,
                audit,
                content,
                frames,
                fallback,
                broker);
        }

        private static ObservationCapturePlan Plan(
            bool includeModal,
            bool includeFlashFallbackMode)
        {
            var modes = new List<ObservationMode>
            {
                ObservationMode.WindowGraphicsCapture
            };
            if (includeFlashFallbackMode)
            {
                modes.Add(
                    ObservationMode.FlashSnapshotKeyframe);
            }
            ObservationSurfacePlan primary = Surface(
                PrimaryTarget,
                SurfaceKind.Flash,
                101,
                10,
                active: true,
                modalEpoch: includeModal ? 5UL : 4UL,
                modes: modes);
            var surfaces = new List<ObservationSurfacePlan>
            {
                primary
            };
            if (includeModal)
            {
                surfaces.Add(
                    Surface(
                        ModalTarget,
                        SurfaceKind.BusinessModal,
                        102,
                        20,
                        active: false,
                        modalEpoch: 5,
                        modes: new[]
                        {
                            ObservationMode.WindowGraphicsCapture
                        }));
            }
            return new ObservationCapturePlan(
                SessionId,
                1,
                AttemptId,
                1,
                PanelId,
                3,
                includeModal ? 5UL : 4UL,
                includeModal
                    ? BlockingModalKind.BusinessOwned
                    : BlockingModalKind.None,
                primary,
                surfaces);
        }

        private static ObservationSurfacePlan Surface(
            string targetId,
            SurfaceKind kind,
            long windowHandle,
            int zIndex,
            bool active,
            ulong modalEpoch,
            IEnumerable<ObservationMode> modes)
        {
            return new ObservationSurfacePlan(
                targetId,
                kind,
                windowHandle,
                101,
                new DateTimeOffset(
                    2026, 7, 30, 8, 0, 0, TimeSpan.Zero),
                Path.GetFullPath(
                    Path.Combine(
                        Path.GetTempPath(),
                        "cf7-observation-tests",
                        "owner.exe")),
                0,
                1,
                1,
                3,
                modalEpoch,
                null,
                null,
                Rect(100, 200, 400, 300),
                Rect(104, 230, 392, 266),
                Rect(110, 236, 380, 250),
                144,
                zIndex,
                visible: true,
                minimized: false,
                active: active,
                observationModes: modes);
        }

        private static PhysicalRect Rect(
            int x,
            int y,
            int width,
            int height)
        {
            return new PhysicalRect
            {
                X = x,
                Y = y,
                Width = width,
                Height = height
            };
        }

        private static ObservationCaptureRequest Request(
            Setup setup,
            string observationGrantId = null,
            bool allowFallback = false,
            string dataScope = "pixels")
        {
            return new ObservationCaptureRequest
            {
                ObservationGrantId =
                    observationGrantId
                    ?? setup.Grant.ObservationGrantId,
                ClientInstanceId = ClientId,
                SecurityPrincipalId =
                    setup.Credential.SecurityPrincipalId,
                SessionId = SessionId,
                TargetId = PrimaryTarget,
                DataScope = dataScope,
                AllowValidatedFlashKeyframeFallback =
                    allowFallback
            };
        }

        private static ObservationUseRequest Use(
            Setup setup,
            ObservationEnvelope envelope)
        {
            FrameEnvelope frame = envelope.Frames[0];
            return new ObservationUseRequest
            {
                ObservationId = envelope.ObservationId,
                ObservationGrantId =
                    envelope.ObservationGrantId,
                ClientInstanceId = ClientId,
                SecurityPrincipalId =
                    setup.Credential.SecurityPrincipalId,
                SessionId = SessionId,
                TargetId = frame.TargetId,
                FrameId = frame.FrameId,
                DataScope = "pixels"
            };
        }

        private static byte[] ColorPixels(int width, int height)
        {
            byte[] pixels = new byte[checked(width * height * 4)];
            for (int index = 0; index < pixels.Length; index += 4)
            {
                pixels[index] = 60;
                pixels[index + 1] = 100;
                pixels[index + 2] = 140;
                pixels[index + 3] = 255;
            }
            return pixels;
        }

        private sealed class Setup : IDisposable
        {
            public Setup(
                ManualObservationClock clock,
                MutableObservationAuthority targets,
                PrincipalCredential credential,
                ObservationGrant grant,
                ObservationGrantBroker grants,
                RecordingPixelAuditSink audit,
                PixelContentHandleStore content,
                RecordingFrameSourceFactory frames,
                RecordingFlashFallback fallback,
                ObservationCaptureBroker broker)
            {
                Clock = clock;
                Targets = targets;
                Credential = credential;
                Grant = grant;
                Grants = grants;
                Audit = audit;
                Content = content;
                Frames = frames;
                Fallback = fallback;
                Broker = broker;
            }

            public ManualObservationClock Clock { get; }
            public MutableObservationAuthority Targets { get; }
            public PrincipalCredential Credential { get; }
            public ObservationGrant Grant { get; }
            public ObservationGrantBroker Grants { get; }
            public RecordingPixelAuditSink Audit { get; }
            public PixelContentHandleStore Content { get; }
            public RecordingFrameSourceFactory Frames { get; }
            public RecordingFlashFallback Fallback { get; }
            public ObservationCaptureBroker Broker { get; }

            public void Dispose()
            {
                Broker.Dispose();
                Content.Dispose();
            }
        }
    }
}
