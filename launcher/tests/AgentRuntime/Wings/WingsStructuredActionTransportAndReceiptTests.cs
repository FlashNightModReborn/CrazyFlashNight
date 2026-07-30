using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.AgentRuntime.Wings;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Wings
{
    public sealed class
        WingsStructuredActionTransportAndReceiptTests
    {
        [Fact]
        public async Task VirtualConnectionUsesValidatorCapabilityAndTwoRevocationGates()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            var resources = new RecordingResources();
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { released = true }));
            await using var connection =
                new WingsVirtualAuthenticatedConnection(
                    principal,
                    resources,
                    dispatcher,
                    clock);

            AgentRuntimeDispatchResult result =
                await connection.DispatchAsync(
                    AgentCapabilitiesV1.LeaseRelease,
                    JsonSerializer.SerializeToElement(
                        new LeaseReleaseParametersV1
                        {
                            LeaseId =
                                WingsStructuredActionFixture
                                    .LeaseId
                        },
                        AgentProtocolV1.JsonOptions),
                    CancellationToken.None);

            Assert.True(result.Success);
            Assert.Equal(1, resources.RegisterCount);
            Assert.True(resources.AuthorizationChecks >= 2);
            Assert.Equal(1, dispatcher.InvocationCount);
            Assert.Same(
                principal,
                dispatcher.LastContext.Principal);
            Assert.Equal(
                connection.ConnectionId,
                dispatcher.LastContext.ConnectionId);
        }

        [Fact]
        public async Task
            VirtualConnectionCompletesEachInProcessResponseOwnerBeforeReturning()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            int committed = 0;
            int aborted = 0;
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { released = true },
                        responseCompletion:
                            new AgentRuntimeResponseCompletion(
                                () => Interlocked.Increment(
                                    ref committed),
                                () => Interlocked.Increment(
                                    ref aborted))));
            await using var connection =
                new WingsVirtualAuthenticatedConnection(
                    principal,
                    new RecordingResources(),
                    dispatcher,
                    clock);
            JsonElement parameters =
                JsonSerializer.SerializeToElement(
                    new LeaseReleaseParametersV1
                    {
                        LeaseId =
                            WingsStructuredActionFixture
                                .LeaseId
                    },
                    AgentProtocolV1.JsonOptions);

            AgentRuntimeDispatchResult first =
                await connection.DispatchAsync(
                    AgentCapabilitiesV1.LeaseRelease,
                    parameters,
                    CancellationToken.None);
            AgentRuntimeDispatchResult second =
                await connection.DispatchAsync(
                    AgentCapabilitiesV1.LeaseRelease,
                    parameters,
                    CancellationToken.None);

            Assert.True(first.Success);
            Assert.True(second.Success);
            Assert.Equal(2, committed);
            Assert.Equal(0, aborted);
            Assert.Equal(2, dispatcher.InvocationCount);
        }

        [Fact]
        public async Task VirtualConnectionRejectsExtraParamsBeforeDispatcher()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            WingsActionIntentV1 intent =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            ActionEnvelope action =
                WingsActionIntentV1.HostFactory
                    .ToActionEnvelope(
                        intent,
                        WingsStructuredActionFixture.LeaseId,
                        10_000);
            string raw = JsonSerializer.Serialize(
                action,
                AgentProtocolV1.JsonOptions);
            JsonElement widened =
                WingsStructuredActionIntentAndConsentTests
                    .Json(
                        raw.Substring(0, raw.Length - 1)
                        + ",\"unexpected\":true}");
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { impossible = true }));
            await using var connection =
                new WingsVirtualAuthenticatedConnection(
                    WingsStructuredActionIntentAndConsentTests
                        .Principal(),
                    new RecordingResources(),
                    dispatcher,
                    clock);

            AgentRuntimeDispatchResult result =
                await connection.DispatchAsync(
                    AgentCapabilitiesV1.Click,
                    widened,
                    CancellationToken.None);

            Assert.False(result.Success);
            Assert.Equal("arguments_invalid", result.ReasonCode);
            Assert.Equal(0, dispatcher.InvocationCount);
        }

        [Fact]
        public async Task VirtualConnectionRejectsCapabilityAndRevocationBeforeDispatcher()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { impossible = true }));
            var resources = new RecordingResources();
            WingsActionIntentV1 intent =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            JsonElement clickParameters =
                JsonSerializer.SerializeToElement(
                    WingsActionIntentV1.HostFactory
                        .ToActionEnvelope(
                            intent,
                            WingsStructuredActionFixture
                                .LeaseId,
                            10_000),
                    AgentProtocolV1.JsonOptions);
            await using var connection =
                new WingsVirtualAuthenticatedConnection(
                    WingsStructuredActionIntentAndConsentTests
                        .Principal(
                            capabilities: new[]
                            {
                                AgentCapabilitiesV1
                                    .LeaseRelease
                            }),
                    resources,
                    dispatcher,
                    clock);

            AgentRuntimeDispatchResult denied =
                await connection.DispatchAsync(
                    AgentCapabilitiesV1.Click,
                    clickParameters,
                    CancellationToken.None);
            resources.Terminate("credential_revoked");
            AgentRuntimeDispatchResult revoked =
                await connection.DispatchAsync(
                    AgentCapabilitiesV1.LeaseRelease,
                    JsonSerializer.SerializeToElement(
                        new LeaseReleaseParametersV1
                        {
                            LeaseId =
                                WingsStructuredActionFixture
                                    .LeaseId
                        },
                        AgentProtocolV1.JsonOptions),
                    CancellationToken.None);

            Assert.Equal("capability_denied", denied.ReasonCode);
            Assert.Equal("credential_revoked", revoked.ReasonCode);
            Assert.Equal(0, dispatcher.InvocationCount);
        }

        [Fact]
        public async Task GenericVirtualDispatchCannotSelfAttestArgumentBounds()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            WingsActionIntentV1 intent =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Rejected(
                        context
                                .HostAttestedArgumentBoundsHash
                            == null
                                ? "argument_bounds_invalid"
                                : "internal_error"));
            await using var connection =
                new WingsVirtualAuthenticatedConnection(
                    principal,
                    new RecordingResources(),
                    dispatcher,
                    clock);

            AgentRuntimeDispatchResult result =
                await connection.DispatchAsync(
                    AgentCapabilitiesV1.LeaseAcquire,
                    JsonSerializer.SerializeToElement(
                        new LeaseAcquireParametersV1
                        {
                            SessionId = intent.SessionId,
                            Kind = "gui_input",
                            Capabilities = new()
                            {
                                AgentCapabilitiesV1.Click
                            },
                            TargetScope = new()
                            {
                                intent.TargetId
                            },
                            RequestedTtlMs = 10_000,
                            RequestedActionLimit = 1,
                            ConsentReceipt =
                                principal.IssuerReceipt,
                            ArgumentBoundsHash =
                                intent.ArgumentBoundsHash
                        },
                        AgentProtocolV1.JsonOptions),
                    CancellationToken.None);

            Assert.False(result.Success);
            Assert.Equal(
                "argument_bounds_invalid",
                result.ReasonCode);
            Assert.Null(
                dispatcher.LastContext
                    .HostAttestedArgumentBoundsHash);
        }

        [Fact]
        public async Task ExecutorUsesExactLeaseThenRegisteredActionAndProjectsReceipt()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            WingsActionIntentV1 intent =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            var bindings =
                new WingsStructuredActionIntentAndConsentTests
                    .AcceptingBindingAuthority();
            var consentTrustDomain =
                new WingsActionConsentTrustDomain();
            TrustedWingsActionAuthorization authorization =
                await AuthorizeAsync(
                    clock,
                    principal,
                    intent,
                    bindings,
                    consentTrustDomain);
            var dispatcher = new StructuredDispatcher(
                clock,
                principal,
                intent);
            await using var connection =
                new WingsVirtualAuthenticatedConnection(
                    principal,
                    new RecordingResources(),
                    dispatcher,
                    clock);
            var trustDomain =
                new WingsActionReceiptTrustDomain();
            var executor =
                new WingsStructuredActionExecutor(
                    clock,
                    bindings,
                    connection,
                    consentTrustDomain,
                    trustDomain);

            WingsStructuredActionExecutionResult result =
                await executor.ExecuteAsync(
                    authorization,
                    CancellationToken.None);

            Assert.True(result.HasTerminalReceipt);
            Assert.Null(result.ReasonCode);
            Assert.Equal(
                new[]
                {
                    AgentCapabilitiesV1.LeaseAcquire,
                    AgentCapabilitiesV1.Click
                },
                dispatcher.Methods);
            Assert.NotNull(dispatcher.Action);
            Assert.Equal(
                intent.ActionId,
                dispatcher.Action.ActionId);
            Assert.Equal(
                intent.ObservationGrantId,
                dispatcher.Action.ObservationGrantId);
            Assert.Equal(
                intent.ObservationId,
                dispatcher.Action.ObservationId);
            Assert.Equal(
                intent.TargetId,
                dispatcher.Action.TargetId);
            Assert.Equal(
                intent.CanonicalArguments.GetRawText(),
                dispatcher.Action.Arguments.GetRawText());

            var projector =
                new TrustedWingsActionReceiptAuthority(
                    trustDomain,
                    new WingsStructuredActionIntentAndConsentTests
                        .AcceptingBindingAuthority());
            Assert.True(projector.TryProject(
                principal,
                intent,
                result.BrokeredReceipt,
                out TrustedWingsActionProjection projection,
                out string reason),
                reason);
            Assert.Equal(
                ActionOutcome.InputDispatched,
                projection.Outcome);
            Assert.Equal(
                EvidenceKind.BrokerDispatch,
                projection.EvidenceKind);
        }

        [Fact]
        public async Task ExecutorRejectsLeaseWithoutExactArgumentBoundsAndReleasesIt()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            WingsActionIntentV1 intent =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            var bindings =
                new WingsStructuredActionIntentAndConsentTests
                    .AcceptingBindingAuthority();
            var consentTrustDomain =
                new WingsActionConsentTrustDomain();
            TrustedWingsActionAuthorization authorization =
                await AuthorizeAsync(
                    clock,
                    principal,
                    intent,
                    bindings,
                    consentTrustDomain);
            var dispatcher = new StructuredDispatcher(
                clock,
                principal,
                intent)
            {
                OmitArgumentBounds = true
            };
            await using var connection =
                new WingsVirtualAuthenticatedConnection(
                    principal,
                    new RecordingResources(),
                    dispatcher,
                    clock);
            var executor =
                new WingsStructuredActionExecutor(
                    clock,
                    bindings,
                    connection,
                    consentTrustDomain,
                    new WingsActionReceiptTrustDomain());

            WingsStructuredActionExecutionResult result =
                await executor.ExecuteAsync(
                    authorization,
                    CancellationToken.None);

            Assert.False(result.HasTerminalReceipt);
            Assert.Equal(
                "lease_scope_mismatch",
                result.ReasonCode);
            Assert.Equal(
                new[]
                {
                    AgentCapabilitiesV1.LeaseAcquire,
                    AgentCapabilitiesV1.LeaseRelease
                },
                dispatcher.Methods);
        }

        [Fact]
        public async Task ExecutorRejectsAuthorizationFromAnotherComposition()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            WingsActionIntentV1 intent =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            var bindings =
                new WingsStructuredActionIntentAndConsentTests
                    .AcceptingBindingAuthority();
            TrustedWingsActionAuthorization authorization =
                await AuthorizeAsync(
                    clock,
                    principal,
                    intent,
                    bindings,
                    new WingsActionConsentTrustDomain());
            var dispatcher = new StructuredDispatcher(
                clock,
                principal,
                intent);
            await using var connection =
                new WingsVirtualAuthenticatedConnection(
                    principal,
                    new RecordingResources(),
                    dispatcher,
                    clock);
            var executor =
                new WingsStructuredActionExecutor(
                    clock,
                    bindings,
                    connection,
                    new WingsActionConsentTrustDomain(),
                    new WingsActionReceiptTrustDomain());

            WingsStructuredActionExecutionResult result =
                await executor.ExecuteAsync(
                    authorization,
                    CancellationToken.None);

            Assert.False(result.HasTerminalReceipt);
            Assert.Equal("consent_invalid", result.ReasonCode);
            Assert.Empty(dispatcher.Methods);
        }

        [Fact]
        public void ProjectorAcceptsOnlyAuthenticatedTerminalFiveStateReceipt()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            WingsActionIntentV1 click =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            WingsActionIntentV1 hair = IssueHair(clock);
            var trustDomain =
                new WingsActionReceiptTrustDomain();
            var projector =
                new TrustedWingsActionReceiptAuthority(
                    trustDomain,
                    new WingsStructuredActionIntentAndConsentTests
                        .AcceptingBindingAuthority());

            foreach (ActionOutcome outcome in Enum
                .GetValues<ActionOutcome>())
            {
                WingsActionIntentV1 intent =
                    outcome == ActionOutcome.DomainCommitted
                        ? hair
                        : click;
                ActionReceipt receipt =
                    Receipt(intent, outcome);
                WingsBrokeredActionReceipt evidence =
                    trustDomain.Seal(
                        principal,
                        intent,
                        WingsStructuredActionFixture.LeaseId,
                        receipt);

                Assert.True(projector.TryProject(
                    principal,
                    intent,
                    evidence,
                    out TrustedWingsActionProjection projection,
                    out string reason),
                    outcome + ": " + reason);
                Assert.Equal(outcome, projection.Outcome);
                Assert.Equal(
                    outcome switch
                    {
                        ActionOutcome.Rejected =>
                            "rejected",
                        ActionOutcome.InputDispatched =>
                            "input_dispatched",
                        ActionOutcome.EffectObserved =>
                            "effect_observed",
                        ActionOutcome.DomainCommitted =>
                            "domain_committed",
                        ActionOutcome.Unknown =>
                            "unknown",
                        _ => throw new InvalidOperationException()
                    },
                    projection.OutcomeCode);
            }
        }

        [Fact]
        public void SessionOnlyResultAdapterValidatesHmacAndProjectsOnlyFiveStates()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            WingsActionIntentV1 click =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            WingsActionIntentV1 hair = IssueHair(clock);
            var trustDomain =
                new WingsActionReceiptTrustDomain();
            var projector =
                new TrustedWingsActionReceiptAuthority(
                    trustDomain,
                    new WingsStructuredActionIntentAndConsentTests
                        .AcceptingBindingAuthority());
            using var authority =
                new SessionOnlyTrustedWingsActionResultAuthority(
                    click.SessionId,
                    projector,
                    clock);

            foreach (ActionOutcome outcome in Enum
                .GetValues<ActionOutcome>())
            {
                WingsActionIntentV1 intent =
                    outcome == ActionOutcome.DomainCommitted
                        ? hair
                        : click;
                WingsBrokeredActionReceipt evidence =
                    trustDomain.Seal(
                        principal,
                        intent,
                        WingsStructuredActionFixture.LeaseId,
                        Receipt(intent, outcome));

                Assert.True(
                    authority.TryRecord(
                        principal,
                        intent,
                        evidence,
                        out string receiptId,
                        out string recordReason),
                    outcome + ": " + recordReason);
                Assert.True(
                    authority.TryResolve(
                        receiptId,
                        out TrustedActionResultFacts facts,
                        out string resolveReason),
                    outcome + ": " + resolveReason);
                Assert.Equal(intent.ActionId, facts.ActionId);
                Assert.Equal(intent.SessionId, facts.SessionId);
                Assert.Equal(
                    intent.SaveBindingId,
                    facts.SaveBindingId);
                Assert.Equal(
                    intent.LoreViewId,
                    facts.LoreViewId);
                Assert.Equal(outcome, facts.Outcome);
            }
            Assert.Equal(5, authority.CountForTest);

            WingsBrokeredActionReceipt foreignEvidence =
                new WingsActionReceiptTrustDomain().Seal(
                    principal,
                    click,
                    WingsStructuredActionFixture.LeaseId,
                    Receipt(
                        click,
                        ActionOutcome.InputDispatched));
            Assert.False(
                authority.TryRecord(
                    principal,
                    click,
                    foreignEvidence,
                    out _,
                    out string foreignReason));
            Assert.Equal(
                "wings_receipt_untrusted",
                foreignReason);

            authority.RevokeSession();
            Assert.Equal(0, authority.CountForTest);
            Assert.False(
                authority.TryResolve(
                    WingsStructuredActionFixture.OtherId,
                    out _,
                    out string unavailableReason));
            Assert.Equal(
                "wings_result_unavailable",
                unavailableReason);
        }

        [Fact]
        public void SessionOnlyResultAdapterFreezesValidatedFactsUntilBoundedExpiry()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            WingsActionIntentV1 intent =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            var bindings =
                new WingsStructuredActionIntentAndConsentTests
                    .AcceptingBindingAuthority();
            var trustDomain =
                new WingsActionReceiptTrustDomain();
            using var authority =
                new SessionOnlyTrustedWingsActionResultAuthority(
                    intent.SessionId,
                    new TrustedWingsActionReceiptAuthority(
                        trustDomain,
                        bindings),
                    clock);
            WingsBrokeredActionReceipt evidence =
                trustDomain.Seal(
                    principal,
                    intent,
                    WingsStructuredActionFixture.LeaseId,
                    Receipt(
                        intent,
                        ActionOutcome.InputDispatched));

            Assert.True(
                authority.TryRecord(
                    principal,
                    intent,
                    evidence,
                    out string receiptId,
                    out string recordReason),
                recordReason);
            Assert.Equal(1, bindings.CallCount);

            principal.State = CredentialState.Revoked;
            Assert.True(
                authority.TryResolve(
                    receiptId,
                    out TrustedActionResultFacts facts,
                    out string resolveReason),
                resolveReason);
            Assert.Equal(
                ActionOutcome.InputDispatched,
                facts.Outcome);
            Assert.Equal(
                1,
                bindings.CallCount);

            clock.Advance(TimeSpan.FromSeconds(10));
            Assert.False(
                authority.TryResolve(
                    receiptId,
                    out _,
                    out string expiredReason));
            Assert.Equal(
                "wings_result_unavailable",
                expiredReason);
            Assert.Equal(0, authority.CountForTest);
        }

        [Fact]
        public void ProjectorRejectsDifferentTrustDomainOrExactBinding()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            WingsActionIntentV1 intent =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            WingsActionIntentV1 other =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            var sealingDomain =
                new WingsActionReceiptTrustDomain();
            WingsBrokeredActionReceipt evidence =
                sealingDomain.Seal(
                    principal,
                    intent,
                    WingsStructuredActionFixture.LeaseId,
                    Receipt(
                        intent,
                        ActionOutcome.InputDispatched));

            var wrongDomainProjector =
                new TrustedWingsActionReceiptAuthority(
                    new WingsActionReceiptTrustDomain(),
                    new WingsStructuredActionIntentAndConsentTests
                        .AcceptingBindingAuthority());
            Assert.False(wrongDomainProjector.TryProject(
                principal,
                intent,
                evidence,
                out _,
                out string untrustedReason));
            Assert.Equal(
                "wings_receipt_untrusted",
                untrustedReason);

            var exactProjector =
                new TrustedWingsActionReceiptAuthority(
                    sealingDomain,
                    new WingsStructuredActionIntentAndConsentTests
                        .AcceptingBindingAuthority());
            Assert.False(exactProjector.TryProject(
                principal,
                other,
                evidence,
                out _,
                out string mismatchReason));
            Assert.Equal(
                "wings_receipt_binding_mismatch",
                mismatchReason);

            var driftProjector =
                new TrustedWingsActionReceiptAuthority(
                    sealingDomain,
                    new WingsStructuredActionIntentAndConsentTests
                        .AcceptingBindingAuthority
                    {
                        FailOnCall = 1
                    });
            Assert.False(driftProjector.TryProject(
                principal,
                intent,
                evidence,
                out _,
                out string driftReason));
            Assert.Equal(
                "wings_receipt_binding_mismatch",
                driftReason);
        }

        [Fact]
        public void SealedReceiptIsFrozenAndRawReceiptHasNoProjectionOverload()
        {
            ManualAgentRuntimeClock clock =
                WingsStructuredActionIntentAndConsentTests
                    .Clock();
            PrincipalCredential principal =
                WingsStructuredActionIntentAndConsentTests
                    .Principal();
            WingsActionIntentV1 intent =
                WingsStructuredActionIntentAndConsentTests
                    .IssueClick(clock);
            ActionReceipt receipt = Receipt(
                intent,
                ActionOutcome.InputDispatched);
            var trustDomain =
                new WingsActionReceiptTrustDomain();
            WingsBrokeredActionReceipt evidence =
                trustDomain.Seal(
                    principal,
                    intent,
                    WingsStructuredActionFixture.LeaseId,
                    receipt);
            receipt.ActionId =
                WingsStructuredActionFixture.OtherId;
            receipt.ActualTargetId =
                WingsStructuredActionFixture.OtherId;

            var projector =
                new TrustedWingsActionReceiptAuthority(
                    trustDomain,
                    new WingsStructuredActionIntentAndConsentTests
                        .AcceptingBindingAuthority());
            Assert.True(projector.TryProject(
                principal,
                intent,
                evidence,
                out TrustedWingsActionProjection projection,
                out string reason),
                reason);
            Assert.Equal(intent.ActionId, projection.ActionId);
            Assert.DoesNotContain(
                typeof(TrustedWingsActionReceiptAuthority)
                    .GetMethods(),
                method => method.GetParameters().Any(
                    parameter =>
                        parameter.ParameterType
                            == typeof(ActionReceipt)));
        }

        private static async Task<
            TrustedWingsActionAuthorization> AuthorizeAsync(
                ManualAgentRuntimeClock clock,
                PrincipalCredential principal,
                WingsActionIntentV1 intent,
                IWingsActionBindingAuthority bindings,
                WingsActionConsentTrustDomain trustDomain)
        {
            var broker = new WingsActionConsentBroker(
                clock,
                bindings,
                trustDomain,
                new WingsStructuredActionIntentAndConsentTests
                    .AllowingPresenter(),
                new WingsStructuredActionIntentAndConsentTests
                    .AcceptingReauthorizationAuthority());
            WingsActionConsentResult result =
                await broker.RequestAsync(
                    principal,
                    intent,
                    CancellationToken.None);
            Assert.True(result.Authorized, result.ReasonCode);
            return result.Authorization;
        }

        private static WingsActionIntentV1 IssueHair(
            IAgentRuntimeClock clock)
        {
            WingsHairActionBinding hair =
                WingsStructuredActionFixture.HairBinding();
            var factory =
                new WingsActionIntentV1.HostFactory(
                    clock,
                    new WingsActionTemplateCatalog(
                        new[]
                        {
                            new WingsActionTemplate(
                                "wings.action.hair.commit.v1",
                                AgentMethodsV1.HairCommit,
                                "Apply the exact reviewed hair preview.",
                                WingsActionLeaseKind
                                    .DomainTransaction,
                                30_000)
                        }));
            Assert.True(factory.TryIssue(
                "wings.action.hair.commit.v1",
                WingsStructuredActionIntentAndConsentTests
                    .Binding(hair),
                WingsStructuredActionIntentAndConsentTests
                    .Json(
                        $$"""
                        {
                            "transactionId":
                                "{{hair.TransactionId}}",
                            "previewHash":
                                "{{hair.PreviewHash}}",
                            "consentToken": "trusted-token"
                        }
                        """),
                out WingsActionIntentV1 intent,
                out string reason),
                reason);
            return intent;
        }

        private static ActionReceipt Receipt(
            WingsActionIntentV1 intent,
            ActionOutcome outcome)
        {
            var receipt = new ActionReceipt
            {
                ActionId = intent.ActionId,
                AuditSequence = 1,
                Terminal = true,
                Outcome = outcome,
                EvidenceKind = outcome switch
                {
                    ActionOutcome.InputDispatched =>
                        EvidenceKind.BrokerDispatch,
                    ActionOutcome.EffectObserved =>
                        EvidenceKind.PostObservation,
                    ActionOutcome.DomainCommitted =>
                        EvidenceKind.DomainAck,
                    ActionOutcome.Unknown =>
                        EvidenceKind.ReconciliationRequired,
                    _ => EvidenceKind.None
                },
                ReasonCode = outcome switch
                {
                    ActionOutcome.Rejected => "stale_focus",
                    ActionOutcome.Unknown =>
                        "reconcile_required",
                    _ => "none"
                },
                ReconcileKind =
                    outcome == ActionOutcome.Unknown
                        ? ReconcileKind.ManualRequired
                        : ReconcileKind.None,
                Retryable =
                    outcome == ActionOutcome.Rejected,
                ActualTargetId = outcome
                        is ActionOutcome.InputDispatched
                            or ActionOutcome.EffectObserved
                            or ActionOutcome.DomainCommitted
                    ? intent.TargetId
                    : null,
                FocusVerified =
                    outcome != ActionOutcome.Rejected,
                BeforeObservationId =
                    intent.ObservationId,
                AfterObservationId =
                    outcome == ActionOutcome.EffectObserved
                        ? WingsStructuredActionFixture
                            .AfterObservationId
                        : null,
                LeaseState = LeaseState.Consumed,
                DomainResult =
                    outcome == ActionOutcome.DomainCommitted
                        ? new HairDomainActionResult
                        {
                            TransactionId =
                                intent.HairBinding
                                    .TransactionId,
                            PreviewHash =
                                intent.HairBinding
                                    .PreviewHash
                        }
                        : null
            };
            Assert.Empty(
                AgentContractValidator.Validate(receipt));
            return receipt;
        }

        internal sealed class RecordingResources
            : IAgentConnectionResourceAuthority
        {
            private Action<string> _terminate;

            public int RegisterCount { get; private set; }
            public int AuthorizationChecks { get; private set; }
            public int RevokeCount { get; private set; }
            public bool Authorized { get; private set; } = true;

            public void RegisterConnection(
                string connectionId,
                PrincipalCredential principal,
                Action<string> terminateConnection)
            {
                RegisterCount++;
                _terminate = terminateConnection;
            }

            public bool IsDispatchAuthorized(
                string connectionId,
                PrincipalCredential principal)
            {
                AuthorizationChecks++;
                return Authorized;
            }

            public Task RevokeAsync(
                string connectionId,
                AgentConnectionTermination termination)
            {
                RevokeCount++;
                Authorized = false;
                return Task.CompletedTask;
            }

            public void Terminate(string reasonCode)
            {
                Authorized = false;
                _terminate(reasonCode);
            }
        }

        internal sealed class RecordingDispatcher
            : IAgentRuntimeMethodDispatcher
        {
            private readonly Func<
                AgentRuntimeDispatchContext,
                AgentJsonRpcRequest,
                AgentRuntimeDispatchResult> _handler;

            public RecordingDispatcher(
                Func<
                    AgentRuntimeDispatchContext,
                    AgentJsonRpcRequest,
                    AgentRuntimeDispatchResult> handler)
            {
                _handler = handler;
            }

            public int InvocationCount { get; private set; }
            public AgentRuntimeDispatchContext LastContext
            {
                get;
                private set;
            }

            public Task<AgentRuntimeDispatchResult>
                DispatchAsync(
                    AgentRuntimeDispatchContext context,
                    AgentJsonRpcRequest request,
                    CancellationToken cancellationToken)
            {
                InvocationCount++;
                LastContext = context;
                return Task.FromResult(
                    _handler(context, request));
            }
        }

        private sealed class StructuredDispatcher
            : IAgentRuntimeMethodDispatcher
        {
            private readonly ManualAgentRuntimeClock _clock;
            private readonly PrincipalCredential _principal;
            private readonly WingsActionIntentV1 _intent;

            public StructuredDispatcher(
                ManualAgentRuntimeClock clock,
                PrincipalCredential principal,
                WingsActionIntentV1 intent)
            {
                _clock = clock;
                _principal = principal;
                _intent = intent;
            }

            public bool OmitArgumentBounds { get; init; }
            public List<string> Methods { get; } = new();
            public ActionEnvelope Action { get; private set; }

            public Task<AgentRuntimeDispatchResult>
                DispatchAsync(
                    AgentRuntimeDispatchContext context,
                    AgentJsonRpcRequest request,
                    CancellationToken cancellationToken)
            {
                Methods.Add(request.Method);
                if (request.Method
                    == AgentCapabilitiesV1.LeaseAcquire)
                {
                    LeaseAcquireParametersV1 leaseRequest =
                        request.Params
                            .Deserialize<
                                LeaseAcquireParametersV1>(
                                AgentProtocolV1
                                    .JsonOptions);
                    Assert.Equal(1, leaseRequest.RequestedActionLimit);
                    Assert.Equal(
                        new[] { _intent.TargetId },
                        leaseRequest.TargetScope);
                    Assert.Equal(
                        _principal.IssuerReceipt,
                        leaseRequest.ConsentReceipt);
                    Assert.True(
                        CanonicalJsonV1
                            .FixedTimeEqualsSha256(
                                _intent.ArgumentBoundsHash,
                                leaseRequest
                                    .ArgumentBoundsHash));
                    Assert.True(
                        CanonicalJsonV1
                            .FixedTimeEqualsSha256(
                                _intent.ArgumentBoundsHash,
                                context
                                    .HostAttestedArgumentBoundsHash));
                    ulong now = checked(
                        (ulong)_clock
                            .MonotonicMilliseconds);
                    return Task.FromResult(
                        AgentRuntimeDispatchResult.Completed(
                            new LeaseDescriptor
                            {
                                LeaseId =
                                    WingsStructuredActionFixture
                                        .LeaseId,
                                OwnerClientId =
                                    _principal.ClientInstanceId,
                                SecurityPrincipalId =
                                    _principal
                                        .SecurityPrincipalId,
                                SessionMode =
                                    SessionMode.PlayerAssist,
                                Purpose =
                                    LeasePurpose.GuiInput,
                                Scope =
                                    new LeaseScopeDescriptor
                                    {
                                        Session =
                                            new SessionScopeDescriptor
                                            {
                                                SessionId =
                                                    _intent
                                                        .SessionId,
                                                LifecycleGeneration =
                                                    _intent
                                                        .LifecycleGeneration,
                                                AttemptId =
                                                    _intent
                                                        .AttemptId,
                                                AttemptGeneration =
                                                    _intent
                                                        .AttemptGeneration,
                                                CrossAttempt = false
                                            },
                                        TargetScope = new()
                                        {
                                            _intent.TargetId
                                        },
                                        OperationScope = new()
                                        {
                                            AgentCapabilitiesV1
                                                .Click
                                        },
                                        MaximumActions = 1,
                                        ArgumentBoundsHash =
                                            OmitArgumentBounds
                                                ? null
                                                : _intent
                                                    .ArgumentBoundsHash
                                    },
                                Capabilities = new()
                                {
                                    AgentCapabilitiesV1.Click
                                },
                                IssuedMonotonic = now,
                                ExpiresMonotonic =
                                    now + 20_000,
                                RenewAfter = now + 10_000,
                                ConsentReceipt =
                                    _principal.IssuerReceipt,
                                HumanOverridePolicy =
                                    HumanOverridePolicy
                                        .AlwaysPreempt,
                                State = LeaseState.Active
                            }));
                }
                if (request.Method
                    == AgentCapabilitiesV1.LeaseRelease)
                {
                    return Task.FromResult(
                        AgentRuntimeDispatchResult.Completed(
                            new { released = true }));
                }
                Assert.Equal(
                    AgentCapabilitiesV1.Click,
                    request.Method);
                Action = request.Params
                    .Deserialize<ActionEnvelope>(
                        AgentProtocolV1.JsonOptions);
                return Task.FromResult(
                    AgentRuntimeDispatchResult.Completed(
                        Receipt(
                            _intent,
                            ActionOutcome.InputDispatched)));
            }
        }
    }
}
