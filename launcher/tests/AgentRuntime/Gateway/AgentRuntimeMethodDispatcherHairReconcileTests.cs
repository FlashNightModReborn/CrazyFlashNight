using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.Tests.AgentRuntime.Domain;
using CF7Launcher.Tests.AgentRuntime.Observation;
using CF7Launcher.Tests.AgentRuntime.Security;
using CF7Launcher.Tests.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class
        AgentRuntimeMethodDispatcherHairReconcileTests
    {
        [Fact]
        public async Task LeaseReleaseUntracksAndCancelsRegisteredAction()
        {
            using var fixture = new Fixture();
            var lifecycle = new RecordingLeaseLifecycle();
            AgentRuntimeMethodDispatcher dispatcher =
                fixture.CreateDispatcher(
                    fixture.Transaction,
                    fixture.OriginalPreviews,
                    lifecycle);
            string leaseId =
                await fixture.AcquireDomainLeaseAsync(
                    dispatcher,
                    requestedTtlMs: 1_000);
            using AgentRuntimeRevocationCoordinator
                .ActionCancellationRegistration action =
                    fixture.RegisterLeaseAction(leaseId);

            AgentRuntimeDispatchResult released =
                await fixture.DispatchLeaseAsync(
                    dispatcher,
                    AgentCapabilitiesV1.LeaseRelease,
                    new LeaseReleaseParametersV1
                    {
                        LeaseId = leaseId
                    });

            Assert.True(released.Success, released.ReasonCode);
            Assert.True(action.Token.IsCancellationRequested);
            Assert.Equal(
                leaseId,
                Assert.Single(lifecycle.ReleasedLeaseIds));
            Assert.Throws<InvalidOperationException>(
                () => fixture.RegisterLeaseAction(leaseId));
        }

        [Fact]
        public async Task RenewExpiredLeaseCleansTrackingAndLifecycle()
        {
            using var fixture = new Fixture();
            var lifecycle = new RecordingLeaseLifecycle();
            AgentRuntimeMethodDispatcher dispatcher =
                fixture.CreateDispatcher(
                    fixture.Transaction,
                    fixture.OriginalPreviews,
                    lifecycle);
            string leaseId =
                await fixture.AcquireDomainLeaseAsync(
                    dispatcher,
                    requestedTtlMs: 100);
            using AgentRuntimeRevocationCoordinator
                .ActionCancellationRegistration action =
                    fixture.RegisterLeaseAction(leaseId);
            fixture.Clock.Advance(
                TimeSpan.FromMilliseconds(101));

            AgentRuntimeDispatchResult renewed =
                await fixture.DispatchLeaseAsync(
                    dispatcher,
                    AgentCapabilitiesV1.LeaseRenew,
                    new LeaseRenewParametersV1
                    {
                        LeaseId = leaseId,
                        RequestedTtlMs = 1_000
                    });

            Assert.False(renewed.Success);
            Assert.Equal("lease_expired", renewed.ReasonCode);
            Assert.True(action.Token.IsCancellationRequested);
            Assert.Equal(
                leaseId,
                Assert.Single(lifecycle.ReleasedLeaseIds));
        }

        [Fact]
        public async Task
            RenewRejectedWhileActiveDoesNotUntrackOrCancel()
        {
            using var fixture = new Fixture();
            var lifecycle = new RecordingLeaseLifecycle();
            AgentRuntimeMethodDispatcher dispatcher =
                fixture.CreateDispatcher(
                    fixture.Transaction,
                    fixture.OriginalPreviews,
                    lifecycle);
            string leaseId =
                await fixture.AcquireDomainLeaseAsync(
                    dispatcher,
                    requestedTtlMs: 1_000);
            using AgentRuntimeRevocationCoordinator
                .ActionCancellationRegistration action =
                    fixture.RegisterLeaseAction(leaseId);

            AgentRuntimeDispatchResult first =
                await fixture.DispatchLeaseAsync(
                    dispatcher,
                    AgentCapabilitiesV1.LeaseRenew,
                    new LeaseRenewParametersV1
                    {
                        LeaseId = leaseId,
                        RequestedTtlMs = 1_000
                    });
            AgentRuntimeDispatchResult second =
                await fixture.DispatchLeaseAsync(
                    dispatcher,
                    AgentCapabilitiesV1.LeaseRenew,
                    new LeaseRenewParametersV1
                    {
                        LeaseId = leaseId,
                        RequestedTtlMs = 1_000
                    });

            Assert.True(first.Success, first.ReasonCode);
            Assert.False(second.Success);
            Assert.Equal(
                "operation_invalid",
                second.ReasonCode);
            Assert.False(action.Token.IsCancellationRequested);
            Assert.Empty(lifecycle.ReleasedLeaseIds);
        }

        [Fact]
        public async Task
            RenewConsumedExecutionDoesNotDropReservationTracking()
        {
            using var fixture = new Fixture();
            var lifecycle = new RecordingLeaseLifecycle();
            AgentRuntimeMethodDispatcher dispatcher =
                fixture.CreateDispatcher(
                    fixture.Transaction,
                    fixture.OriginalPreviews,
                    lifecycle);
            WriteLease lease =
                fixture.AcquireTrackedOneShotDomainLease();
            Assert.True(
                fixture.ConsumeDomainAction(
                    lease,
                    out string consumeReason),
                consumeReason);
            using AgentRuntimeRevocationCoordinator
                .ActionCancellationRegistration action =
                    fixture.RegisterLeaseAction(
                        lease.LeaseId);

            AgentRuntimeDispatchResult renewed =
                await fixture.DispatchLeaseAsync(
                    dispatcher,
                    AgentCapabilitiesV1.LeaseRenew,
                    new LeaseRenewParametersV1
                    {
                        LeaseId = lease.LeaseId,
                        RequestedTtlMs = 1_000
                    });

            Assert.False(renewed.Success);
            Assert.Equal(
                "lease_action_limit",
                renewed.ReasonCode);
            Assert.False(action.Token.IsCancellationRequested);
            Assert.Empty(lifecycle.ReleasedLeaseIds);
            Assert.True(
                fixture.AbortDomainExecution(lease));
        }

        [Fact]
        public async Task ExactOriginalPreviewReturnsEscrowedTokenOnlyOnce()
        {
            using var fixture = new Fixture();
            await fixture.PrepareEscrowAsync();
            AgentRuntimeMethodDispatcher dispatcher =
                fixture.CreateDispatcher(
                    fixture.Transaction,
                    fixture.OriginalPreviews);

            AgentRuntimeDispatchResult first =
                await fixture.ReconcileAsync(
                    dispatcher,
                    fixture.Context);
            AgentRuntimeDispatchResult second =
                await fixture.ReconcileAsync(
                    dispatcher,
                    fixture.Context);

            AssertDomainCommitted(first);
            Assert.True(
                first.Result.TryGetProperty(
                    "restoreToken",
                    out JsonElement restoreToken));
            Assert.False(
                string.IsNullOrWhiteSpace(
                    restoreToken.GetString()));
            AssertDomainCommittedWithoutToken(second);
            Assert.Equal(
                HairRestorePointState.Committed,
                fixture.Store.ReadDirect(
                    fixture.Preview.TransactionId).State);
            Assert.Single(fixture.Adapter.CommitCommands);
        }

        [Fact]
        public async Task ClonedPreviewCannotConsumeExactPreviewEscrow()
        {
            using var fixture = new Fixture();
            await fixture.PrepareEscrowAsync();
            HairAppearancePreview clone =
                ClonePreview(fixture.Preview);
            var clonedPreviews = new AgentHairPreviewStore();
            clonedPreviews.Store(
                fixture.Context,
                fixture.TargetId,
                clone);
            AgentRuntimeMethodDispatcher cloneDispatcher =
                fixture.CreateDispatcher(
                    fixture.Transaction,
                    clonedPreviews);

            AgentRuntimeDispatchResult cloneResult =
                await fixture.ReconcileAsync(
                    cloneDispatcher,
                    fixture.Context);

            Assert.NotSame(fixture.Preview, clone);
            AssertDomainCommittedWithoutToken(cloneResult);

            AgentRuntimeMethodDispatcher originalDispatcher =
                fixture.CreateDispatcher(
                    fixture.Transaction,
                    fixture.OriginalPreviews);
            AgentRuntimeDispatchResult originalResult =
                await fixture.ReconcileAsync(
                    originalDispatcher,
                    fixture.Context);

            AssertDomainCommitted(originalResult);
            Assert.True(
                originalResult.Result.TryGetProperty(
                    "restoreToken",
                    out _));
        }

        [Fact]
        public async Task NewConnectionCannotResolveOrConsumeOriginalPreview()
        {
            using var fixture = new Fixture();
            await fixture.PrepareEscrowAsync();
            AgentRuntimeMethodDispatcher dispatcher =
                fixture.CreateDispatcher(
                    fixture.Transaction,
                    fixture.OriginalPreviews);
            var foreignConnection =
                new AgentRuntimeDispatchContext(
                    Id("connection-other"),
                    fixture.Principal);

            AgentRuntimeDispatchResult foreign =
                await fixture.ReconcileAsync(
                    dispatcher,
                    foreignConnection);

            Assert.False(foreign.Success);
            Assert.Equal(
                "principal_mismatch",
                foreign.ReasonCode);

            AgentRuntimeDispatchResult original =
                await fixture.ReconcileAsync(
                    dispatcher,
                    fixture.Context);

            AssertDomainCommitted(original);
            Assert.True(
                original.Result.TryGetProperty(
                    "restoreToken",
                    out _));
        }

        [Fact]
        public async Task RestartedTransactionServiceCannotRecoverEscrowedToken()
        {
            using var fixture = new Fixture();
            await fixture.PrepareEscrowAsync();
            fixture.Transaction.Dispose();
            using HairAppearanceModifierTransaction restarted =
                fixture.CreateRestartedTransaction();
            AgentRuntimeMethodDispatcher dispatcher =
                fixture.CreateDispatcher(
                    restarted,
                    fixture.OriginalPreviews);

            AgentRuntimeDispatchResult result =
                await fixture.ReconcileAsync(
                    dispatcher,
                    fixture.Context);

            AssertDomainCommittedWithoutToken(result);
            Assert.Equal(
                HairRestorePointState.Committed,
                fixture.Store.ReadDirect(
                    fixture.Preview.TransactionId).State);
            Assert.Single(fixture.Adapter.CommitCommands);
        }

        private static void AssertDomainCommitted(
            AgentRuntimeDispatchResult result)
        {
            Assert.True(result.Success, result.ReasonCode);
            Assert.Equal(
                "domain_committed",
                result.Result
                    .GetProperty("outcome")
                    .GetString());
        }

        private static void AssertDomainCommittedWithoutToken(
            AgentRuntimeDispatchResult result)
        {
            AssertDomainCommitted(result);
            Assert.False(
                result.Result.TryGetProperty(
                    "restoreToken",
                    out _));
        }

        private static HairAppearancePreview ClonePreview(
            HairAppearancePreview preview)
        {
            return new HairAppearancePreview(
                preview.TransactionId,
                preview.Binding,
                preview.BeforeHair,
                preview.AfterHair,
                preview.ExpectedRevision,
                preview.ExpectedGeneration,
                preview.ExpectedSnapshotHash,
                preview.PreviewHash,
                preview.CreatedAtUtc);
        }

        private static string Id(string seed)
        {
            string value = seed.Replace("-", string.Empty);
            while (value.Length < 22)
                value += "A";
            return value.Substring(0, 22);
        }

        private sealed class Fixture : IDisposable
        {
            private const string BeforeHair = "光头";
            private const string AfterHair = "发型-男式-平头";

            private readonly SessionRegistryHostOwner _owner;
            private readonly SessionSurfaceHostController _controller;
            private readonly PrincipalCredentialAuthority _credentials;
            private readonly ObservationCaptureBroker _captures;
            private readonly PixelContentHandleStore _content;
            private readonly AgentObservationEnvelopeStore
                _observationStore;
            private readonly WriteLeaseBroker _leases;
            private readonly AgentRuntimeRevocationCoordinator
                _revocations;
            private readonly ActionIdempotencyLedger _ledger;
            private readonly ScopedAgentRuntimeAuditLedgerManager
                _audit;
            private readonly AgentRuntimeActionExecutionBroker
                _actions;
            private bool _prepared;

            public Fixture()
            {
                Clock = new ManualAgentRuntimeClock();
                var launcher = new SessionProcessIdentity(
                    307,
                    new DateTimeOffset(
                        2026,
                        7,
                        31,
                        1,
                        2,
                        3,
                        TimeSpan.Zero),
                    Path.GetFullPath("Launcher.Tests.exe"));
                _owner =
                    new SessionRegistryHostOwner(launcher);
                Registry = new SessionSurfaceRegistry(
                    _owner,
                    new RecordingSessionSurfaceHostValidator());
                var qualification =
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
                    qualification,
                    new string('c', 64),
                    new[]
                    {
                        AgentCapabilitiesV1
                            .AppearanceHairChange
                    });
                TargetId = Id("hair-target");
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
                        WindowHandle = 1307,
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
                _credentials =
                    new PrincipalCredentialAuthority(
                        Clock,
                        new TestPrincipalEnrollmentVerifier());
                Principal = _credentials.IssueDeveloper(
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
                    _credentials,
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

                Binding = new HairSaveBinding(
                    SessionId,
                    1,
                    Id("attempt"),
                    1,
                    "developer_slot",
                    new string('d', 64));
                Adapter =
                    new InMemoryHairdresserDomainAdapter(
                        Binding,
                        BeforeHair);
                Store = new InMemoryHairRestorePointStore();
                Consent =
                    new HairAppearanceConsentBroker(Clock);
                Transaction =
                    new HairAppearanceModifierTransaction(
                        Adapter,
                        Store,
                        Consent,
                        Clock);
                OriginalPreviews = new AgentHairPreviewStore();

                _content = new PixelContentHandleStore(
                    Clock,
                    Grants,
                    new RecordingPixelAuditSink());
                _captures = new ObservationCaptureBroker(
                    Clock,
                    Grants,
                    new SessionSurfaceObservationAuthority(
                        Registry),
                    new RecordingFrameSourceFactory(),
                    new RecordingFlashFallback(),
                    _content);
                _observationStore =
                    new AgentObservationEnvelopeStore();
                _leases = new WriteLeaseBroker(
                    Clock,
                    _credentials,
                    Registry);
                _revocations =
                    new AgentRuntimeRevocationCoordinator(
                        _credentials,
                        Grants,
                        _leases);
                _revocations.RegisterConnection(
                    Context.ConnectionId,
                    Principal);
                _ledger = new ActionIdempotencyLedger();
                _audit =
                    new ScopedAgentRuntimeAuditLedgerManager(
                        Clock,
                        _credentials,
                        new RegistryAgentAuditScopeAuthority(
                            Registry));
                Assert.True(
                    _audit.TryRegisterAuthenticatedConnection(
                        Context.ConnectionId,
                        Principal,
                        SessionId,
                        1,
                        out string auditRegisterReason),
                    auditRegisterReason);
                _actions =
                    new AgentRuntimeActionExecutionBroker(
                        _captures,
                        _observationStore,
                        _leases,
                        _ledger,
                        _revocations,
                        new RejectingActionPerformer(),
                        _audit);
            }

            public ManualAgentRuntimeClock Clock { get; }
            public SessionSurfaceRegistry Registry { get; }
            public ObservationGrantBroker Grants { get; }
            public ObservationGrant Grant { get; }
            public PrincipalCredential Principal { get; }
            public AgentRuntimeDispatchContext Context { get; }
            public HairSaveBinding Binding { get; }
            public InMemoryHairdresserDomainAdapter Adapter
            {
                get;
            }
            public InMemoryHairRestorePointStore Store { get; }
            public HairAppearanceConsentBroker Consent { get; }
            public HairAppearanceModifierTransaction Transaction
            {
                get;
            }
            public AgentHairPreviewStore OriginalPreviews { get; }
            public HairAppearancePreview Preview { get; private set; }
            public string SessionId { get; }
            public string TargetId { get; }

            public async Task PrepareEscrowAsync()
            {
                Assert.False(_prepared);
                HairInspectResult inspect =
                    await Transaction.InspectAsync(Binding);
                Assert.True(inspect.Success, inspect.ReasonCode);
                HairPreviewResult preview =
                    await Transaction.PreviewAsync(
                        new HairPreviewRequest(
                            Binding,
                            AfterHair,
                            inspect.Snapshot.CurrentHair,
                            inspect.Snapshot.Revision,
                            inspect.Snapshot.Generation,
                            inspect.SnapshotHash));
                Assert.Equal(
                    HairTransactionOutcome.PreviewReady,
                    preview.Outcome);
                Preview = preview.Preview;
                OriginalPreviews.Store(
                    Context,
                    TargetId,
                    Preview);

                HairAppearanceConsentToken consent =
                    Consent.IssueForNeutralUi(
                        Preview,
                        "dispatcher-reconcile-consent",
                        TimeSpan.FromSeconds(60));
                Store.FailUpdateOnCall =
                    Store.UpdateCalls + 1;
                HairTransactionResult committed =
                    await Transaction.CommitAsync(
                        Preview,
                        consent.Token);

                Assert.Equal(
                    HairTransactionOutcome.DomainCommitted,
                    committed.Outcome);
                Assert.Null(committed.RestoreToken);
                Assert.Equal(
                    AfterHair,
                    Adapter.CurrentSnapshot.CurrentHair);
                Assert.Equal(
                    HairRestorePointState.Prepared,
                    Store.ReadDirect(
                        Preview.TransactionId).State);
                Assert.Equal(1, Store.UpdateCalls);
                Assert.Single(Adapter.CommitCommands);
                _prepared = true;
            }

            public HairAppearanceModifierTransaction
                CreateRestartedTransaction()
            {
                return new HairAppearanceModifierTransaction(
                    Adapter,
                    Store,
                    new HairAppearanceConsentBroker(Clock),
                    Clock);
            }

            public AgentRuntimeMethodDispatcher CreateDispatcher(
                HairAppearanceModifierTransaction transaction,
                IAgentHairPreviewStore previews,
                IAgentWriteLeaseLifecycle leaseLifecycle = null)
            {
                var hairTargets =
                    new RegistryAgentHairDomainTargetAuthority(
                        Registry);
                var hairConsent =
                    new AgentHairConsentIssuanceService(
                        transaction,
                        new FailClosedAgentHairConsentPresenter(),
                        Registry,
                        Grants,
                        hairTargets);
                return new AgentRuntimeMethodDispatcher(
                    Registry,
                    new RegistryMinimalSessionReferenceProvider(
                        Registry,
                        Id("lifecycle-salt")),
                    Grants,
                    _captures,
                    _content,
                    _observationStore,
                    _leases,
                    leaseLifecycle
                        ?? new FailClosedAgentWriteLeaseLifecycle(),
                    _revocations,
                    _ledger,
                    _actions,
                    transaction,
                    previews,
                    hairTargets,
                    hairConsent,
                    new FailClosedAgentRuntimeHostMethodService(),
                    _audit);
            }

            public async Task<string> AcquireDomainLeaseAsync(
                AgentRuntimeMethodDispatcher dispatcher,
                int requestedTtlMs)
            {
                AgentRuntimeDispatchResult acquired =
                    await DispatchLeaseAsync(
                        dispatcher,
                        AgentCapabilitiesV1.LeaseAcquire,
                        new LeaseAcquireParametersV1
                        {
                            SessionId = SessionId,
                            Kind = "domain_transaction",
                            Capabilities = new()
                            {
                                AgentCapabilitiesV1
                                    .AppearanceHairChange
                            },
                            TargetScope = new()
                            {
                                TargetId
                            },
                            RequestedTtlMs =
                                requestedTtlMs,
                            RequestedActionLimit = 2,
                            PreviewHash =
                                new string('e', 64),
                            ExpectedRevision =
                                "revision-test",
                            Operation =
                                AgentCapabilitiesV1
                                    .AppearanceHairChange
                        });
                Assert.True(
                    acquired.Success,
                    acquired.ReasonCode);
                return acquired.Result
                    .GetProperty("leaseId")
                    .GetString();
            }

            public Task<AgentRuntimeDispatchResult>
                DispatchLeaseAsync(
                    AgentRuntimeMethodDispatcher dispatcher,
                    string method,
                    object parameters)
            {
                return dispatcher.DispatchAsync(
                    Context,
                    new AgentJsonRpcRequest
                    {
                        Id = Id("request-lease"),
                        Method = method,
                        Params = JsonSerializer
                            .SerializeToElement(
                                parameters,
                                AgentProtocolV1.JsonOptions)
                    },
                    CancellationToken.None);
            }

            public AgentRuntimeRevocationCoordinator
                .ActionCancellationRegistration
                RegisterLeaseAction(string leaseId)
            {
                return _revocations.RegisterAction(
                    Context.ConnectionId,
                    leaseId,
                    CancellationToken.None);
            }

            public WriteLease
                AcquireTrackedOneShotDomainLease()
            {
                Assert.True(
                    _revocations.TryCaptureSessionFence(
                        Context.ConnectionId,
                        Principal,
                        SessionId,
                        1,
                        out AgentRuntimeRevocationCoordinator
                            .SessionFenceTicket ticket,
                        out string fenceReason),
                    fenceReason);
                WriteLease lease = _leases.Acquire(
                    new WriteLeaseRequest
                    {
                        CredentialId =
                            Principal.CredentialId,
                        ClientInstanceId =
                            Principal.ClientInstanceId,
                        SessionId = SessionId,
                        LifecycleGeneration = 1,
                        Kind =
                            WriteLeaseKind
                                .DomainTransaction,
                        Capabilities = new[]
                        {
                            AgentCapabilitiesV1
                                .AppearanceHairChange
                        },
                        TargetScope =
                            new[] { TargetId },
                        RequestedLifetime =
                            TimeSpan.FromSeconds(30),
                        RequestedActionLimit = 1,
                        PreviewHash =
                            new string('e', 64),
                        ExpectedRevision =
                            "revision-test",
                        Operation =
                            AgentCapabilitiesV1
                                .AppearanceHairChange
                    });
                Assert.True(
                    _revocations.TryTrackLease(
                        ticket,
                        lease,
                        out string trackReason),
                    trackReason);
                return lease;
            }

            public bool ConsumeDomainAction(
                WriteLease lease,
                out string reasonCode)
            {
                return _leases.TryConsumeAction(
                    lease.LeaseId,
                    Principal.ClientInstanceId,
                    Principal.SecurityPrincipalId,
                    SessionId,
                    AgentCapabilitiesV1
                        .AppearanceHairChange,
                    TargetId,
                    AgentCapabilitiesV1
                        .AppearanceHairChange,
                    out _,
                    out reasonCode);
            }

            public bool AbortDomainExecution(
                WriteLease lease)
            {
                bool aborted =
                    _leases.AbortPendingActionExecution(
                        lease.LeaseId);
                _revocations
                    .UntrackLeaseAndCancelQueuedActions(
                        lease.SessionId,
                        lease.LeaseId,
                        "test_cleanup");
                return aborted;
            }

            public Task<AgentRuntimeDispatchResult>
                ReconcileAsync(
                    AgentRuntimeMethodDispatcher dispatcher,
                    AgentRuntimeDispatchContext context)
            {
                Assert.True(_prepared);
                return dispatcher.DispatchAsync(
                    context,
                    new AgentJsonRpcRequest
                    {
                        Id = Id("request"),
                        Method = AgentMethodsV1.HairReconcile,
                        Params = JsonSerializer.SerializeToElement(
                            new HairReconcileParametersV1
                            {
                                ObservationGrantId =
                                    Grant.ObservationGrantId,
                                TargetId = TargetId,
                                TransactionId =
                                    Preview.TransactionId
                            },
                            AgentProtocolV1.JsonOptions)
                    },
                    CancellationToken.None);
            }

            public void Dispose()
            {
                Transaction.Dispose();
                _captures.Dispose();
                _content.Dispose();
                _revocations.Dispose();
                _audit.Dispose();
            }
        }

        private sealed class RejectingActionPerformer
            : IAgentRuntimeActionPerformer
        {
            public Task<AgentActionPerformance> PerformAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
            {
                return Task.FromResult(
                    AgentActionPerformance.Rejected(
                        "operation_invalid"));
            }
        }

        private sealed class RecordingLeaseLifecycle
            : IAgentWriteLeaseLifecycle
        {
            public System.Collections.Generic.List<string>
                ReleasedLeaseIds { get; } = new();

            public bool TryActivate(
                WriteLease lease,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }

            public void Release(WriteLease lease)
            {
                if (lease != null)
                    ReleasedLeaseIds.Add(lease.LeaseId);
            }
        }
    }
}
