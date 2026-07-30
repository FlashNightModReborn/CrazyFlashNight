using System;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Wings;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Wings
{
    public sealed class WingsStructuredActionIntentAndConsentTests
    {
        [Fact]
        public void IntentCanOnlyBeCreatedByNestedHostFactory()
        {
            ConstructorInfo[] constructors =
                typeof(WingsActionIntentV1).GetConstructors(
                    BindingFlags.Instance
                    | BindingFlags.Public
                    | BindingFlags.NonPublic);

            Assert.NotEmpty(constructors);
            Assert.All(
                constructors,
                constructor => Assert.True(
                    constructor.IsPrivate));
            Assert.All(
                typeof(WingsActionIntentV1).GetProperties(),
                property => Assert.Null(property.SetMethod));
            Assert.DoesNotContain(
                typeof(WingsActionIntentV1.HostFactory)
                    .GetMethods(),
                method => method.GetParameters().Any(
                    parameter =>
                        parameter.ParameterType
                            == typeof(WingsDraftOutput)
                        || parameter.ParameterType
                            == typeof(WingsCheckedOutput)));
        }

        [Fact]
        public void FactoryCanonicalizesAndFreezesExactHostBindings()
        {
            ManualAgentRuntimeClock clock = Clock();
            WingsActionIntentV1.HostFactory factory =
                ClickFactory(clock);
            WingsActionHostBindingSnapshot binding =
                Binding();

            Assert.True(factory.TryIssue(
                "wings.action.click.v1",
                binding,
                Json(
                    """
                    {
                        "y": 22,
                        "button": "primary",
                        "coordinateSpace": "observation_px",
                        "clickCount": 1,
                        "x": 11
                    }
                    """),
                out WingsActionIntentV1 first,
                out string reason));
            Assert.Null(reason);
            Assert.True(factory.TryIssue(
                "wings.action.click.v1",
                binding,
                Json(
                    """
                    {
                        "coordinateSpace": "observation_px",
                        "x": 11,
                        "y": 22,
                        "button": "primary",
                        "clickCount": 1
                    }
                    """),
                out WingsActionIntentV1 second,
                out reason));

            Assert.Null(reason);
            Assert.Equal(
                first.CanonicalArguments.GetRawText(),
                second.CanonicalArguments.GetRawText());
            Assert.Equal(
                first.ArgumentBoundsHash,
                second.ArgumentBoundsHash);
            Assert.NotEqual(first.IntentId, second.IntentId);
            Assert.NotEqual(first.ActionId, second.ActionId);
            Assert.NotEqual(
                first.IdempotencyKey,
                second.IdempotencyKey);
            Assert.Equal(
                WingsStructuredActionFixture.SessionId,
                first.SessionId);
            Assert.Equal(
                WingsStructuredActionFixture.SaveBindingId,
                first.SaveBindingId);
            Assert.Equal(
                WingsStructuredActionFixture.LoreViewId,
                first.LoreViewId);
            Assert.Equal(
                WingsStructuredActionFixture.ObservationId,
                first.ObservationId);
            Assert.Equal(
                AgentCapabilitiesV1.Click,
                first.Operation);
            Assert.Equal(64, first.ArgumentBoundsHash.Length);
            Assert.Equal(64, first.BindingHash.Length);
        }

        [Fact]
        public void IntentAndEnvelopeRoundTripEveryFrozenPrecondition()
        {
            ManualAgentRuntimeClock clock = Clock();
            var binding =
                new WingsActionHostBindingSnapshot(
                    WingsStructuredActionFixture.SessionId,
                    4,
                    WingsStructuredActionFixture.AttemptId,
                    5,
                    "save-slot-1",
                    WingsStructuredActionFixture.SaveBindingId,
                    new string('a', 64),
                    31,
                    WingsStructuredActionFixture.LoreViewId,
                    WingsStructuredActionFixture.TargetId,
                    9,
                    WingsStructuredActionFixture.PanelId,
                    12,
                    WingsStructuredActionFixture
                        .SemanticSnapshotId,
                    13,
                    WingsStructuredActionFixture.NodeId,
                    14,
                    15,
                    16,
                    WingsStructuredActionFixture
                        .ObservationGrantId,
                    WingsStructuredActionFixture.ObservationId,
                    null);
            WingsActionIntentV1.HostFactory factory =
                ClickFactory(clock);
            Assert.True(factory.TryIssue(
                "wings.action.click.v1",
                binding,
                Json(
                    """
                    {
                        "button": "primary",
                        "clickCount": 1
                    }
                    """),
                out WingsActionIntentV1 intent,
                out string reason),
                reason);

            ActionEnvelope action =
                WingsActionIntentV1.HostFactory
                    .ToActionEnvelope(
                        intent,
                        WingsStructuredActionFixture.LeaseId,
                        7_000);

            Assert.Equal(4UL, action.ExpectedLifecycleGeneration);
            Assert.Equal(
                WingsStructuredActionFixture.AttemptId,
                action.ExpectedAttemptId);
            Assert.Equal(5UL, action.ExpectedAttemptGeneration);
            Assert.Equal(
                WingsStructuredActionFixture.PanelId,
                action.ExpectedPanelInstanceId);
            Assert.Equal(12UL, action.ExpectedDocumentGeneration);
            Assert.Equal(
                WingsStructuredActionFixture.SemanticSnapshotId,
                action.SemanticSnapshotId);
            Assert.Equal(13UL, action.ExpectedSemanticGeneration);
            Assert.Equal(
                WingsStructuredActionFixture.NodeId,
                action.NodeId);
            Assert.Equal(14UL, action.ExpectedCoordinateSpaceVersion);
            Assert.Equal(15UL, action.ExpectedFocusEpoch);
            Assert.Equal(16UL, action.ExpectedModalEpoch);
            Assert.Equal(
                WingsStructuredActionFixture.ObservationGrantId,
                action.ObservationGrantId);
            Assert.Equal(
                WingsStructuredActionFixture.ObservationId,
                action.ObservationId);
            Assert.Equal(new string('a', 64), intent.SaveSignature);
            Assert.Equal(31, intent.SaveRevision);
            Assert.Equal(
                WingsStructuredActionFixture.SaveBindingId,
                intent.SaveBindingId);
            Assert.Equal(
                WingsStructuredActionFixture.LoreViewId,
                intent.LoreViewId);
            Assert.Equal(7_000, action.DeadlineMs);
        }

        [Fact]
        public void FactoryRejectsUnregisteredOrMalformedSelection()
        {
            ManualAgentRuntimeClock clock = Clock();
            WingsActionIntentV1.HostFactory factory =
                ClickFactory(clock);

            Assert.False(factory.TryIssue(
                "persona.free.text",
                Binding(),
                ClickArguments(),
                out WingsActionIntentV1 intent,
                out string reason));
            Assert.Null(intent);
            Assert.Equal(
                "wings_action_template_unregistered",
                reason);

            Assert.False(factory.TryIssue(
                "wings.action.click.v1",
                Binding(),
                Json(
                    """
                    {
                        "coordinateSpace": "screen_px",
                        "x": 11,
                        "y": 22,
                        "button": "primary",
                        "clickCount": 1
                    }
                    """),
                out intent,
                out reason));
            Assert.Null(intent);
            Assert.Equal("arguments_invalid", reason);
        }

        [Fact]
        public void HairIntentRejectsCrossTransactionArguments()
        {
            ManualAgentRuntimeClock clock = Clock();
            WingsHairActionBinding hair =
                WingsStructuredActionFixture.HairBinding();
            var catalog = new WingsActionTemplateCatalog(
                new[]
                {
                    new WingsActionTemplate(
                        "wings.action.hair.commit.v1",
                        AgentMethodsV1.HairCommit,
                        "Apply the exact reviewed hair preview.",
                        WingsActionLeaseKind.DomainTransaction,
                        30_000)
                });
            var factory =
                new WingsActionIntentV1.HostFactory(
                    clock,
                    catalog);

            Assert.False(factory.TryIssue(
                "wings.action.hair.commit.v1",
                Binding(hair),
                Json(
                    $$"""
                    {
                        "transactionId":
                            "{{WingsStructuredActionFixture.OtherId}}",
                        "previewHash": "{{hair.PreviewHash}}",
                        "consentToken": "trusted-token"
                    }
                    """),
                out WingsActionIntentV1 intent,
                out string reason));

            Assert.Null(intent);
            Assert.Equal(
                "wings_hair_binding_mismatch",
                reason);
        }

        [Fact]
        public async Task DefaultConsentDependenciesFailClosed()
        {
            ManualAgentRuntimeClock clock = Clock();
            WingsActionIntentV1 intent = IssueClick(clock);
            var broker = new WingsActionConsentBroker(
                clock,
                new AcceptingBindingAuthority(),
                new WingsActionConsentTrustDomain());

            WingsActionConsentResult result =
                await broker.RequestAsync(
                    Principal(),
                    intent,
                    CancellationToken.None);

            Assert.False(result.Authorized);
            Assert.Equal("consent_required", result.ReasonCode);
        }

        [Fact]
        public async Task HumanAllowRequiresCloseReauthAndTwoBindingChecks()
        {
            ManualAgentRuntimeClock clock = Clock();
            WingsActionIntentV1 intent = IssueClick(clock);
            PrincipalCredential principal = Principal();
            var bindings = new AcceptingBindingAuthority();
            var presenter = new AllowingPresenter();
            var reauthorization =
                new AcceptingReauthorizationAuthority();
            var broker = new WingsActionConsentBroker(
                clock,
                bindings,
                new WingsActionConsentTrustDomain(),
                presenter,
                reauthorization);

            WingsActionConsentResult result =
                await broker.RequestAsync(
                    principal,
                    intent,
                    CancellationToken.None);

            Assert.True(result.Authorized);
            Assert.Null(result.ReasonCode);
            Assert.Equal(2, bindings.CallCount);
            Assert.Equal(1, presenter.CallCount);
            Assert.Equal(1, reauthorization.CallCount);
            Assert.Equal(
                intent.BindingHash,
                presenter.Card.BindingHash);
            Assert.Equal(
                intent.ArgumentBoundsHash,
                presenter.Card.ArgumentBoundsHash);
            Assert.Equal(1, presenter.Card.MaximumActions);
            Assert.False(presenter.Card.AllowsPersistence);
            Assert.False(presenter.Card.AllowsExport);

            Assert.True(
                result.Authorization.TryConsume(
                    principal,
                    clock.MonotonicMilliseconds,
                    out string reason));
            Assert.Null(reason);
            Assert.False(
                result.Authorization.TryConsume(
                    principal,
                    clock.MonotonicMilliseconds,
                    out reason));
            Assert.Equal("consent_replayed", reason);
        }

        [Fact]
        public async Task PostConsentBindingDriftFailsClosedAndCannotReprompt()
        {
            ManualAgentRuntimeClock clock = Clock();
            WingsActionIntentV1 intent = IssueClick(clock);
            var bindings = new AcceptingBindingAuthority
            {
                FailOnCall = 2
            };
            var broker = new WingsActionConsentBroker(
                clock,
                bindings,
                new WingsActionConsentTrustDomain(),
                new AllowingPresenter(),
                new AcceptingReauthorizationAuthority());

            WingsActionConsentResult first =
                await broker.RequestAsync(
                    Principal(),
                    intent,
                    CancellationToken.None);
            WingsActionConsentResult replay =
                await broker.RequestAsync(
                    Principal(),
                    intent,
                    CancellationToken.None);

            Assert.False(first.Authorized);
            Assert.Equal(
                "wings_binding_changed",
                first.ReasonCode);
            Assert.False(replay.Authorized);
            Assert.Equal("consent_replayed", replay.ReasonCode);
        }

        [Fact]
        public async Task ConsentRejectsWrongSessionBeforePresentation()
        {
            ManualAgentRuntimeClock clock = Clock();
            WingsActionIntentV1 intent = IssueClick(clock);
            var presenter = new AllowingPresenter();
            var broker = new WingsActionConsentBroker(
                clock,
                new AcceptingBindingAuthority(),
                new WingsActionConsentTrustDomain(),
                presenter,
                new AcceptingReauthorizationAuthority());

            WingsActionConsentResult result =
                await broker.RequestAsync(
                    Principal(
                        selectedSessionId:
                            WingsStructuredActionFixture
                                .OtherId),
                    intent,
                    CancellationToken.None);

            Assert.False(result.Authorized);
            Assert.Equal(
                "session_scope_mismatch",
                result.ReasonCode);
            Assert.Equal(0, presenter.CallCount);
        }

        internal static ManualAgentRuntimeClock Clock()
        {
            var clock = new ManualAgentRuntimeClock();
            clock.Advance(TimeSpan.FromSeconds(1));
            return clock;
        }

        internal static PrincipalCredential Principal(
            string selectedSessionId =
                WingsStructuredActionFixture.SessionId,
            string[] capabilities = null)
        {
            return new PrincipalCredential(
                WingsStructuredActionFixture.CredentialId,
                WingsStructuredActionFixture.PrincipalId,
                WingsStructuredActionFixture.ClientId,
                AgentPrincipalKind.WingsPersona,
                AgentSessionMode.PlayerAssist,
                7,
                1,
                120_000,
                new DateTimeOffset(
                    2026,
                    7,
                    30,
                    0,
                    0,
                    0,
                    TimeSpan.Zero),
                capabilities
                    ?? new[]
                    {
                        AgentCapabilitiesV1.LeaseAcquire,
                        AgentCapabilitiesV1.LeaseRelease,
                        AgentCapabilitiesV1.Click,
                        AgentCapabilitiesV1
                            .AppearanceHairChange
                    },
                new[]
                {
                    WingsStructuredActionFixture.TargetId
                },
                WingsStructuredActionFixture.IssuerReceiptId,
                selectedSessionId,
                null,
                null,
                null);
        }

        internal static WingsActionHostBindingSnapshot Binding(
            WingsHairActionBinding hairBinding = null)
        {
            return new WingsActionHostBindingSnapshot(
                WingsStructuredActionFixture.SessionId,
                4,
                null,
                null,
                "save-slot-1",
                WingsStructuredActionFixture.SaveBindingId,
                new string('a', 64),
                31,
                WingsStructuredActionFixture.LoreViewId,
                WingsStructuredActionFixture.TargetId,
                9,
                WingsStructuredActionFixture.PanelId,
                12,
                null,
                null,
                null,
                14,
                15,
                16,
                WingsStructuredActionFixture.ObservationGrantId,
                WingsStructuredActionFixture.ObservationId,
                WingsStructuredActionFixture.FrameId,
                hairBinding);
        }

        internal static WingsActionIntentV1.HostFactory ClickFactory(
            IAgentRuntimeClock clock)
        {
            return new WingsActionIntentV1.HostFactory(
                clock,
                new WingsActionTemplateCatalog(
                    new[]
                    {
                        new WingsActionTemplate(
                            "wings.action.click.v1",
                            AgentCapabilitiesV1.Click,
                            "Click the exact reviewed point.",
                            WingsActionLeaseKind.GuiInput,
                            30_000)
                    }));
        }

        internal static WingsActionIntentV1 IssueClick(
            IAgentRuntimeClock clock)
        {
            WingsActionIntentV1.HostFactory factory =
                ClickFactory(clock);
            Assert.True(factory.TryIssue(
                "wings.action.click.v1",
                Binding(),
                ClickArguments(),
                out WingsActionIntentV1 intent,
                out string reason),
                reason);
            return intent;
        }

        internal static JsonElement ClickArguments()
        {
            return Json(
                """
                {
                    "coordinateSpace": "observation_px",
                    "x": 11,
                    "y": 22,
                    "button": "primary",
                    "clickCount": 1
                }
                """);
        }

        internal static JsonElement Json(string json)
        {
            using JsonDocument document =
                JsonDocument.Parse(json);
            return document.RootElement.Clone();
        }

        internal sealed class AcceptingBindingAuthority
            : IWingsActionBindingAuthority
        {
            public int CallCount { get; private set; }
            public int? FailOnCall { get; init; }

            public bool TryValidate(
                PrincipalCredential principal,
                WingsActionIntentV1 intent,
                out string reasonCode)
            {
                CallCount++;
                if (CallCount == FailOnCall)
                {
                    reasonCode = "wings_binding_changed";
                    return false;
                }
                reasonCode = null;
                return true;
            }
        }

        internal sealed class AllowingPresenter
            : IWingsActionConsentPresenter
        {
            public int CallCount { get; private set; }
            public TrustedWingsActionConsentCard Card
            {
                get;
                private set;
            }

            public Task<WingsActionHumanDecision> PresentAsync(
                TrustedWingsActionConsentCard card,
                CancellationToken cancellationToken)
            {
                CallCount++;
                Card = card;
                return Task.FromResult(
                    WingsActionHumanDecision.AllowAfterClose(
                        WingsStructuredActionFixture
                            .HumanInteractionReceiptId));
            }
        }

        internal sealed class AcceptingReauthorizationAuthority
            : IWingsActionReauthorizationAuthority
        {
            public int CallCount { get; private set; }

            public bool
                TryAcknowledgeAfterHumanSurfaceClosed(
                    PrincipalCredential principal,
                    WingsActionIntentV1 intent,
                    string humanInteractionReceiptId,
                    out string reauthorizationReceiptId,
                    out string reasonCode)
            {
                CallCount++;
                reauthorizationReceiptId =
                    WingsStructuredActionFixture
                        .ReauthorizationReceiptId;
                reasonCode = null;
                return true;
            }
        }
    }

    internal static class WingsStructuredActionFixture
    {
        public const string SessionId =
            "session_WingsStructured0001";
        public const string OtherId =
            "other_WingsStructured000001";
        public const string CredentialId =
            "credential_WingsStructured01";
        public const string PrincipalId =
            "principal_WingsStructured001";
        public const string ClientId =
            "client_WingsStructured000001";
        public const string TargetId =
            "target_WingsStructured000001";
        public const string PanelId =
            "panel_WingsStructured0000001";
        public const string AttemptId =
            "attempt_WingsStructured000001";
        public const string SemanticSnapshotId =
            "semantic_WingsStructured00001";
        public const string NodeId =
            "node_WingsStructured00000001";
        public const string SaveBindingId =
            "save_WingsStructured00000001";
        public const string LoreViewId =
            "lore_WingsStructured00000001";
        public const string ObservationGrantId =
            "grant_WingsStructured0000001";
        public const string ObservationId =
            "observation_WingsStructured01";
        public const string AfterObservationId =
            "observation_WingsStructured02";
        public const string FrameId =
            "frame_WingsStructured0000001";
        public const string IssuerReceiptId =
            "issuer_WingsStructured000001";
        public const string HumanInteractionReceiptId =
            "human_WingsStructured0000001";
        public const string ReauthorizationReceiptId =
            "reauth_WingsStructured000001";
        public const string LeaseId =
            "lease_WingsStructured0000001";
        public const string TransactionId =
            "transaction_WingsStructured01";

        public static WingsHairActionBinding HairBinding()
        {
            return new WingsHairActionBinding(
                TransactionId,
                new string('b', 64),
                "hair-revision-31",
                17,
                new string('c', 64),
                "short",
                "long",
                "hairdresser");
        }
    }
}
