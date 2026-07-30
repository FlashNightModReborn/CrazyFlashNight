using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.Tests.AgentRuntime.Domain;
using CF7Launcher.Tests.AgentRuntime.Security;
using CF7Launcher.Tests.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentHairConsentProtocolTests
    {
        [Fact]
        public void DirectMethodHasExactPrincipalFreeWireContract()
        {
            JsonElement valid = JsonSerializer.SerializeToElement(
                new
                {
                    observationGrantId = Id("grant"),
                    targetId = Id("target"),
                    sessionId = Id("session"),
                    lifecycleGeneration = 1,
                    transactionId = Id("transaction"),
                    previewHash = new string('a', 64)
                });

            Assert.Empty(
                AgentMethodParameterValidatorV1.Validate(
                    AgentMethodsV1.HairConsent,
                    valid));

            JsonElement injected = JsonSerializer.SerializeToElement(
                new
                {
                    observationGrantId = Id("grant"),
                    targetId = Id("target"),
                    sessionId = Id("session"),
                    lifecycleGeneration = 1,
                    transactionId = Id("transaction"),
                    previewHash = new string('a', 64),
                    securityPrincipalId = Id("principal")
                });
            Assert.Contains(
                AgentMethodParameterValidatorV1.Validate(
                    AgentMethodsV1.HairConsent,
                    injected),
                violation =>
                    violation.Code == "unknown_property"
                    && violation.Path
                        == "$.params.securityPrincipalId");
        }

        [Fact]
        public void PreviewStoreRejectsDifferentOriginalPrincipal()
        {
            using var setup = new ConsentSetup();
            var store = new AgentHairPreviewStore();
            AgentRuntimeDispatchContext owner = setup.Context;
            store.Store(
                owner,
                setup.TargetId,
                setup.Preview);
            var other = new AgentRuntimeDispatchContext(
                owner.ConnectionId,
                new PrincipalCredential(
                    Id("credential-other"),
                    Id("principal-other"),
                    Id("client-other"),
                    AgentPrincipalKind.DeveloperAgent,
                    AgentSessionMode.DeveloperInteractive,
                    1,
                    0,
                    60_000,
                    DateTimeOffset.UtcNow,
                    new[] {
                        AgentCapabilitiesV1.AppearanceHairChange
                    },
                    new[] { setup.TargetId },
                    "test",
                    null,
                    null,
                    null,
                    null));

            Assert.False(store.TryResolve(
                other,
                setup.Preview.TransactionId,
                setup.Preview.PreviewHash,
                out _,
                out _,
                out string reasonCode));
            Assert.Equal("principal_mismatch", reasonCode);
        }

        [Fact]
        public async Task HumanApprovalMintsExactSixtySecondOneShotToken()
        {
            using var setup = new ConsentSetup();
            var presenter = new RecordingPresenter(
                AgentHairConsentPresentationResult.Allow(
                    "neutral-ui-receipt"));
            AgentHairConsentIssuanceService service =
                setup.Service(presenter);

            AgentHairConsentIssuanceResult result =
                await service.RequestAsync(
                    setup.Request(),
                    CancellationToken.None);

            Assert.True(result.Success);
            Assert.NotNull(result.Descriptor);
            Assert.Equal(
                setup.Preview.TransactionId,
                result.Descriptor.TransactionId);
            Assert.Equal(
                setup.Preview.PreviewHash,
                result.Descriptor.PreviewHash);
            Assert.Equal(
                "neutral-ui-receipt",
                result.Descriptor.ConsentReceipt);
            Assert.Equal(60_000, result.Descriptor.ExpiresInMs);
            Assert.Same(
                setup.Principal,
                presenter.Request.Principal);
            Assert.Equal(
                setup.SessionId,
                presenter.Request.SessionId);
            Assert.Null(
                setup.ConsentBroker.TryConsume(
                    result.Descriptor.ConsentToken,
                    setup.Preview));
            Assert.Equal(
                HairAppearanceReasonCodes.ConsentReplayed,
                setup.ConsentBroker.TryConsume(
                    result.Descriptor.ConsentToken,
                    setup.Preview));
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public async Task RejectionOrAbsentHostNeverReturnsToken(
            bool hostAbsent)
        {
            using var setup = new ConsentSetup();
            IAgentHairConsentPresenter presenter = hostAbsent
                ? new FailClosedAgentHairConsentPresenter()
                : new RecordingPresenter(
                    AgentHairConsentPresentationResult.Reject());

            AgentHairConsentIssuanceResult result =
                await setup.Service(presenter).RequestAsync(
                    setup.Request(),
                    CancellationToken.None);

            Assert.False(result.Success);
            Assert.Null(result.Descriptor);
            Assert.Equal(
                hostAbsent
                    ? "human_intervention_required"
                    : "consent_required",
                result.ReasonCode);
        }

        [Fact]
        public async Task LifecycleChangeDuringPromptInvalidatesApproval()
        {
            using var setup = new ConsentSetup();
            var presenter = new RecordingPresenter(
                AgentHairConsentPresentationResult.Allow(
                    "stale-ui-receipt"),
                setup.ReplaceLifecycle);

            AgentHairConsentIssuanceResult result =
                await setup.Service(presenter).RequestAsync(
                    setup.Request(),
                    CancellationToken.None);

            Assert.False(result.Success);
            Assert.Null(result.Descriptor);
            Assert.Equal("session_not_found", result.ReasonCode);
        }

        [Fact]
        public async Task DisconnectCancellationAfterUiDecisionMintsNothing()
        {
            using var setup = new ConsentSetup();
            using var cancellation = new CancellationTokenSource();
            var presenter = new RecordingPresenter(
                AgentHairConsentPresentationResult.Allow(
                    "cancelled-ui-receipt"),
                cancellation.Cancel);

            await Assert.ThrowsAnyAsync<OperationCanceledException>(
                () => setup.Service(presenter).RequestAsync(
                    setup.Request(),
                    cancellation.Token));
        }

        private sealed class RecordingPresenter
            : IAgentHairConsentPresenter
        {
            private readonly AgentHairConsentPresentationResult
                _result;
            private readonly Action _onPresent;

            public RecordingPresenter(
                AgentHairConsentPresentationResult result,
                Action onPresent = null)
            {
                _result = result;
                _onPresent = onPresent;
            }

            public AgentHairConsentPresentationRequest Request
            {
                get;
                private set;
            }

            public Task<AgentHairConsentPresentationResult>
                PresentAsync(
                    AgentHairConsentPresentationRequest request,
                    CancellationToken cancellationToken)
            {
                Request = request;
                _onPresent?.Invoke();
                return Task.FromResult(_result);
            }
        }

        private sealed class ConsentSetup : IDisposable
        {
            private readonly SessionRegistryHostOwner _owner;
            private readonly SessionSurfaceHostController _controller;
            private readonly RuntimeQualificationRegistration
                _qualification;

            public ConsentSetup()
            {
                Clock = new ManualAgentRuntimeClock();
                var launcher = new SessionProcessIdentity(
                    107,
                    new DateTimeOffset(
                        2026,
                        7,
                        30,
                        1,
                        2,
                        3,
                        TimeSpan.Zero),
                    Path.GetFullPath("Launcher.Tests.exe"));
                _owner = new SessionRegistryHostOwner(launcher);
                Registry = new SessionSurfaceRegistry(
                    _owner,
                    new RecordingSessionSurfaceHostValidator());
                _qualification =
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode = RuntimeMode.FormalRuntime,
                        BuildIdentity = new string('a', 64),
                        PayloadClosure = new string('b', 64),
                        ActualProcessPath =
                            launcher.ExecutablePath
                    };
                _controller = new SessionSurfaceHostController(
                    Registry,
                    _owner,
                    _qualification,
                    new string('c', 64),
                    new[]
                    {
                        AgentCapabilitiesV1.AppearanceHairChange
                    });
                TargetId = Id("target");
                _controller.SynchronizeSurface(
                    new SessionSurfaceHostRegistration
                    {
                        TargetId = TargetId,
                        Kind = SurfaceKind.WebOverlay,
                        SafetyKind =
                            AgentTargetSafetyKind.RuntimeOwned,
                        OwnerRelation =
                            SessionSurfaceOwnerRelation
                                .RuntimeOverlay,
                        OwnerProcess = launcher,
                        WindowHandle = 1001,
                        BoundsPhysical =
                            new SessionPhysicalRect(
                                0,
                                0,
                                800,
                                600),
                        ClientRectPhysical =
                            new SessionPhysicalRect(
                                0,
                                0,
                                800,
                                600),
                        ContentRectPhysical =
                            new SessionPhysicalRect(
                                0,
                                0,
                                800,
                                600),
                        Dpi = 96,
                        Visible = true,
                        ObservationModes = new[]
                        {
                            ObservationMode
                                .WindowGraphicsCapture
                        },
                        InputModes = new[]
                        {
                            InputMode.DomainTransaction
                        }
                    });

                SessionId = _controller.SessionId;
                var credentials =
                    new PrincipalCredentialAuthority(
                        Clock,
                        new TestPrincipalEnrollmentVerifier());
                Principal = credentials.IssueDeveloper(
                    new DeveloperEnrollmentEvidence
                    {
                        ClientInstanceId = Id("client"),
                        EnrollmentReceipt =
                            "developer-enrollment",
                        AllowedCapabilities = new[]
                        {
                            AgentCapabilitiesV1
                                .AppearanceHairChange,
                            "observe:"
                                + ObservationDataScopesV1
                                    .PlayerState
                        },
                        AllowedTargets = new[] { TargetId }
                    });
                Grants = new ObservationGrantBroker(
                    Clock,
                    credentials,
                    Registry);
                Grant = Grants.Issue(
                    new ObservationGrantRequest
                    {
                        CredentialId =
                            Principal.CredentialId,
                        ClientInstanceId =
                            Principal.ClientInstanceId,
                        SessionId = SessionId,
                        Targets = new[]
                        {
                            new ObservationTargetScope
                            {
                                TargetId = TargetId
                            }
                        },
                        DataScopes = new[]
                        {
                            ObservationDataScopesV1
                                .PlayerState
                        },
                        RequestedLifetime =
                            TimeSpan.FromMinutes(5)
                    });
                Context = new AgentRuntimeDispatchContext(
                    Id("connection"),
                    Principal);
                ConsentBroker =
                    new HairAppearanceConsentBroker(Clock);
                Preview = CreatePreview();
                HairTransaction =
                    new HairAppearanceModifierTransaction(
                        new InMemoryHairdresserDomainAdapter(
                            Preview.Binding,
                            Preview.BeforeHair),
                        new InMemoryHairRestorePointStore(),
                        ConsentBroker,
                        Clock);
            }

            public ManualAgentRuntimeClock Clock { get; }
            public SessionSurfaceRegistry Registry { get; }
            public ObservationGrantBroker Grants { get; }
            public ObservationGrant Grant { get; }
            public PrincipalCredential Principal { get; }
            public AgentRuntimeDispatchContext Context { get; }
            public HairAppearanceConsentBroker ConsentBroker { get; }
            public HairAppearanceModifierTransaction HairTransaction
            {
                get;
            }
            public HairAppearancePreview Preview { get; }
            public string SessionId { get; }
            public string TargetId { get; }

            public AgentHairConsentIssuanceService Service(
                IAgentHairConsentPresenter presenter)
            {
                return new AgentHairConsentIssuanceService(
                    HairTransaction,
                    presenter,
                    Registry,
                    Grants,
                    new RegistryAgentHairDomainTargetAuthority(
                        Registry));
            }

            public AgentHairConsentPresentationRequest Request()
            {
                return new AgentHairConsentPresentationRequest(
                    Context.ConnectionId,
                    Principal,
                    Grant.ObservationGrantId,
                    SessionId,
                    1,
                    TargetId,
                    Preview);
            }

            public void ReplaceLifecycle()
            {
                _controller.ReplaceLifecycle(
                    _qualification,
                    "replacement_slot");
            }

            public void Dispose()
            {
            }

            private HairAppearancePreview CreatePreview()
            {
                var binding = new HairSaveBinding(
                    SessionId,
                    1,
                    Id("attempt"),
                    1,
                    "developer_slot",
                    new string('d', 64));
                string transactionId = Id("transaction");
                string snapshotHash = new string('e', 64);
                string previewHash =
                    HairAppearanceHashing.ComputePreviewHash(
                        transactionId,
                        binding,
                        "hair.before",
                        "hair.after",
                        7,
                        9,
                        snapshotHash);
                return new HairAppearancePreview(
                    transactionId,
                    binding,
                    "hair.before",
                    "hair.after",
                    7,
                    9,
                    snapshotHash,
                    previewHash,
                    Clock.UtcNow);
            }
        }

        private static string Id(string seed)
        {
            string value = seed.Replace("-", string.Empty);
            while (value.Length < 22)
                value += "A";
            return value.Substring(0, 22);
        }
    }
}
