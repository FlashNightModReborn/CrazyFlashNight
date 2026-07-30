using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Domain
{
    public sealed class HairAppearanceModifierTransaction
        : IDisposable
    {
        public static readonly TimeSpan DefaultRestoreTtl =
            TimeSpan.FromMinutes(15);
        public static readonly TimeSpan MaximumRestoreTtl =
            TimeSpan.FromMinutes(30);

        private const string DomainAuthoritativeReconcile =
            "domain_authoritative";
        private const string ManualRequiredReconcile = "manual_required";

        private readonly IHairdresserDomainAdapter _adapter;
        private readonly IHairRestorePointStore _restoreStore;
        private readonly HairAppearanceConsentBroker _consentBroker;
        private readonly IAgentRuntimeClock _clock;
        private readonly TimeSpan _restoreTtl;
        private readonly SemaphoreSlim _writeGate = new SemaphoreSlim(1, 1);
        private readonly Dictionary<string, RestoreCapabilityEscrow>
            _restoreCapabilityEscrows =
                new Dictionary<string, RestoreCapabilityEscrow>(
                    StringComparer.Ordinal);
        private bool _disposed;

        public HairAppearanceModifierTransaction(
            IHairdresserDomainAdapter adapter,
            IHairRestorePointStore restoreStore,
            HairAppearanceConsentBroker consentBroker,
            IAgentRuntimeClock clock,
            TimeSpan? restoreTtl = null)
        {
            _adapter = adapter ?? throw new ArgumentNullException(nameof(adapter));
            _restoreStore = restoreStore
                ?? throw new ArgumentNullException(nameof(restoreStore));
            _consentBroker = consentBroker
                ?? throw new ArgumentNullException(nameof(consentBroker));
            _clock = clock ?? throw new ArgumentNullException(nameof(clock));
            _restoreTtl = restoreTtl ?? DefaultRestoreTtl;
            if (_restoreTtl <= TimeSpan.Zero
                || _restoreTtl > MaximumRestoreTtl)
            {
                throw new ArgumentOutOfRangeException(nameof(restoreTtl));
            }
        }

        internal HairAppearanceConsentBroker ConsentBroker
        {
            get { return _consentBroker; }
        }

        public void Dispose()
        {
            _writeGate.Wait();
            try
            {
                if (_disposed)
                    return;
                _disposed = true;
                _restoreCapabilityEscrows.Clear();
            }
            finally
            {
                _writeGate.Release();
            }
        }

        public async Task<HairInspectResult> InspectAsync(
            HairSaveBinding expectedBinding,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return await InspectInternalAsync(
                expectedBinding,
                cancellationToken).ConfigureAwait(false);
        }

        public async Task<HairPreviewResult> PreviewAsync(
            HairPreviewRequest request,
            CancellationToken cancellationToken = default)
        {
            if (request == null
                || !HairAppearanceValidation.IsValidBinding(request.Binding)
                || !HairAppearanceValidation.IsSafeString(
                    request.HairIdentifier,
                    160,
                    false)
                || !HairAppearanceValidation.IsSafeString(
                    request.ExpectedCurrentHair,
                    160,
                    false)
                || request.ExpectedRevision < 0
                || request.ExpectedGeneration < 0
                || !HairAppearanceValidation.IsSha256(
                    request.ExpectedSnapshotHash))
            {
                return HairPreviewResult.Rejected(
                    HairAppearanceReasonCodes.InvalidPayload);
            }

            HairInspectResult inspect = await InspectInternalAsync(
                request.Binding,
                cancellationToken).ConfigureAwait(false);
            if (!inspect.Success)
            {
                return HairPreviewResult.Rejected(inspect.ReasonCode);
            }

            HairAuthoritativeSnapshot snapshot = inspect.Snapshot;
            if (snapshot.Revision != request.ExpectedRevision
                || snapshot.Generation != request.ExpectedGeneration)
            {
                return HairPreviewResult.Rejected(
                    HairAppearanceReasonCodes.StaleRevision);
            }
            if (!string.Equals(
                    snapshot.CurrentHair,
                    request.ExpectedCurrentHair,
                    StringComparison.Ordinal)
                || !string.Equals(
                    inspect.SnapshotHash,
                    request.ExpectedSnapshotHash,
                    StringComparison.Ordinal))
            {
                return HairPreviewResult.Rejected(
                    HairAppearanceReasonCodes.StaleState);
            }
            if (!HairAppearanceValidation.CatalogContains(
                    snapshot,
                    request.HairIdentifier))
            {
                return HairPreviewResult.Rejected(
                    HairAppearanceReasonCodes.HairNotFound);
            }
            if (string.Equals(
                snapshot.CurrentHair,
                request.HairIdentifier,
                StringComparison.Ordinal))
            {
                return HairPreviewResult.Rejected(
                    HairAppearanceReasonCodes.NoChange);
            }

            string transactionId = OpaqueIdGenerator.Create("hairtx");
            string previewHash = HairAppearanceHashing.ComputePreviewHash(
                transactionId,
                snapshot.Binding,
                snapshot.CurrentHair,
                request.HairIdentifier,
                snapshot.Revision,
                snapshot.Generation,
                inspect.SnapshotHash);
            var preview = new HairAppearancePreview(
                transactionId,
                snapshot.Binding,
                snapshot.CurrentHair,
                request.HairIdentifier,
                snapshot.Revision,
                snapshot.Generation,
                inspect.SnapshotHash,
                previewHash,
                _clock.UtcNow);
            return HairPreviewResult.Ready(preview);
        }

        public async Task<HairValidationResult> ValidateAsync(
            HairAppearancePreview preview,
            CancellationToken cancellationToken = default)
        {
            if (!HairAppearanceValidation.PreviewHashIsAuthentic(preview))
            {
                return HairValidationResult.Invalid(
                    HairAppearanceReasonCodes.InvalidPayload);
            }

            HairInspectResult inspect = await InspectInternalAsync(
                preview.Binding,
                cancellationToken).ConfigureAwait(false);
            if (!inspect.Success)
            {
                return HairValidationResult.Invalid(inspect.ReasonCode);
            }
            if (inspect.Snapshot.Revision != preview.ExpectedRevision
                || inspect.Snapshot.Generation != preview.ExpectedGeneration)
            {
                return HairValidationResult.Invalid(
                    HairAppearanceReasonCodes.StaleRevision);
            }
            if (!string.Equals(
                    inspect.Snapshot.CurrentHair,
                    preview.BeforeHair,
                    StringComparison.Ordinal)
                || !string.Equals(
                    inspect.SnapshotHash,
                    preview.ExpectedSnapshotHash,
                    StringComparison.Ordinal))
            {
                return HairValidationResult.Invalid(
                    HairAppearanceReasonCodes.StaleState);
            }
            if (!HairAppearanceValidation.CatalogContains(
                    inspect.Snapshot,
                    preview.AfterHair))
            {
                return HairValidationResult.Invalid(
                    HairAppearanceReasonCodes.HairNotFound);
            }
            return HairValidationResult.Valid(inspect);
        }

        public async Task<HairTransactionResult> CommitAsync(
            HairAppearancePreview preview,
            string consentToken,
            CancellationToken cancellationToken = default)
        {
            await _writeGate.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                ThrowIfDisposed();
                ClearExpiredEscrowsUnsafe();
                HairValidationResult validation = await ValidateAsync(
                    preview,
                    cancellationToken).ConfigureAwait(false);
                if (!validation.Success)
                {
                    RemoveEscrowUnsafe(preview?.TransactionId);
                    return Rejected(
                        preview,
                        validation.ReasonCode);
                }

                string consentFailure = _consentBroker.TryConsume(
                    consentToken,
                    preview);
                if (consentFailure != null)
                {
                    RemoveEscrowUnsafe(preview?.TransactionId);
                    return Rejected(preview, consentFailure);
                }

                DateTimeOffset createdAtUtc = _clock.UtcNow;
                DateTimeOffset expiresAtUtc = createdAtUtc.Add(_restoreTtl);
                string restoreToken = CreateRestoreToken();
                var prepared = new HairRestorePointRecord(
                    preview.TransactionId,
                    preview.Binding,
                    preview.BeforeHair,
                    preview.AfterHair,
                    preview.ExpectedRevision,
                    preview.ExpectedGeneration,
                    preview.ExpectedSnapshotHash,
                    preview.PreviewHash,
                    HairAppearanceHashing.HashOpaqueToken(restoreToken),
                    createdAtUtc,
                    expiresAtUtc,
                    HairRestorePointState.Prepared,
                    0,
                    preview.ExpectedRevision,
                    preview.ExpectedGeneration,
                    preview.ExpectedSnapshotHash,
                    false);

                HairRestoreStoreResult created = await SafeCreateAsync(
                    prepared,
                    cancellationToken).ConfigureAwait(false);
                if (created.Status != HairRestoreStoreStatus.Success
                    || !IsValidStoredRecord(created.Record))
                {
                    RemoveEscrowUnsafe(preview.TransactionId);
                    return Rejected(
                        preview,
                        created.Status == HairRestoreStoreStatus.Conflict
                            ? HairAppearanceReasonCodes.RestoreStoreConflict
                            : HairAppearanceReasonCodes.RestoreStoreUnavailable);
                }
                HairRestorePointRecord record = created.Record;

                var command = new HairDomainCommitCommand(
                    preview.TransactionId,
                    preview.Binding,
                    preview.AfterHair,
                    preview.BeforeHair,
                    preview.ExpectedRevision,
                    preview.ExpectedGeneration,
                    preview.ExpectedSnapshotHash,
                    false);
                HairAdapterCommitResult adapterResult =
                    await InvokeCommitAsync(
                        command,
                        cancellationToken).ConfigureAwait(false);

                if (adapterResult.Status == HairAdapterCommitStatus.Applied
                    && IsValidAppliedSnapshot(
                        adapterResult.Snapshot,
                        preview.Binding,
                        preview.AfterHair,
                        preview.ExpectedRevision,
                        preview.ExpectedGeneration))
                {
                    HairInspectResult authoritative =
                        ToInspect(adapterResult.Snapshot);
                    bool committedDurably =
                        await SafeTransitionAsync(
                        record,
                        HairRestorePointState.Committed,
                        authoritative,
                        false,
                        cancellationToken).ConfigureAwait(false);
                    if (!committedDurably)
                    {
                        StoreEscrowUnsafe(
                            preview,
                            restoreToken,
                            expiresAtUtc);
                    }
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.DomainCommitted,
                        null,
                        null,
                        preview.TransactionId,
                        preview.PreviewHash,
                        authoritative,
                        committedDurably
                            ? restoreToken
                            : null,
                        committedDurably
                            ? expiresAtUtc
                            : null);
                }

                if (adapterResult.Status == HairAdapterCommitStatus.Rejected)
                {
                    RemoveEscrowUnsafe(preview.TransactionId);
                    await SafeTransitionAsync(
                        record,
                        HairRestorePointState.CommitRejected,
                        validation.Inspect,
                        false,
                        cancellationToken).ConfigureAwait(false);
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Rejected,
                        NormalizeAdapterReason(adapterResult.ReasonCode),
                        null,
                        preview.TransactionId,
                        preview.PreviewHash);
                }

                await SafeTransitionAsync(
                    record,
                    HairRestorePointState.CommitUnknown,
                    validation.Inspect,
                    false,
                    cancellationToken).ConfigureAwait(false);
                StoreEscrowUnsafe(
                    preview,
                    restoreToken,
                    expiresAtUtc);
                return HairTransactionResult.Create(
                    HairTransactionOutcome.Unknown,
                    adapterResult.Status == HairAdapterCommitStatus.Applied
                        ? HairAppearanceReasonCodes.MalformedAuthority
                        : NormalizeUnknownReason(adapterResult.ReasonCode),
                    DomainAuthoritativeReconcile,
                    preview.TransactionId,
                    preview.PreviewHash);
            }
            finally
            {
                _writeGate.Release();
            }
        }

        public async Task<HairTransactionResult> ReconcileAsync(
            string transactionId,
            CancellationToken cancellationToken = default)
        {
            if (!HairAppearanceValidation.IsSafeString(
                transactionId,
                160,
                false))
            {
                return HairTransactionResult.Create(
                    HairTransactionOutcome.Rejected,
                    HairAppearanceReasonCodes.InvalidPayload,
                    null,
                    transactionId,
                    null);
            }

            await _writeGate.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                ThrowIfDisposed();
                ClearExpiredEscrowsUnsafe();
                HairRestoreStoreResult read = await SafeReadAsync(
                    transactionId,
                    cancellationToken).ConfigureAwait(false);
                if (read.Status != HairRestoreStoreStatus.Success
                    || !IsValidStoredRecord(read.Record))
                {
                    return StoreReadFailure(transactionId, read.Status);
                }
                return await ReconcileRecordAsync(
                    read.Record,
                    cancellationToken).ConfigureAwait(false);
            }
            finally
            {
                _writeGate.Release();
            }
        }

        /// <summary>
        /// Releases an escrowed restore capability only after the caller has
        /// resolved the exact in-memory preview object and authoritative
        /// reconciliation has durably reached Committed. This capability is
        /// intentionally unavailable after a transaction service restart.
        /// </summary>
        internal async Task<HairReconciledRestoreCapability>
            TryConsumeReconciledRestoreCapabilityAsync(
                HairAppearancePreview preview,
                CancellationToken cancellationToken = default)
        {
            if (preview == null
                || !HairAppearanceValidation
                    .PreviewHashIsAuthentic(preview))
            {
                return null;
            }
            await _writeGate.WaitAsync(cancellationToken)
                .ConfigureAwait(false);
            try
            {
                ThrowIfDisposed();
                ClearExpiredEscrowsUnsafe();
                if (!_restoreCapabilityEscrows.TryGetValue(
                        preview.TransactionId,
                        out RestoreCapabilityEscrow escrow)
                    || !ReferenceEquals(
                        escrow.Preview,
                        preview)
                    || !string.Equals(
                        escrow.TransactionId,
                        preview.TransactionId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        escrow.PreviewHash,
                        preview.PreviewHash,
                        StringComparison.Ordinal)
                    || _clock.UtcNow < preview.CreatedAtUtc
                    || _clock.UtcNow >= escrow.ExpiresAtUtc)
                {
                    return null;
                }

                HairRestoreStoreResult read =
                    await SafeReadAsync(
                        preview.TransactionId,
                        cancellationToken)
                    .ConfigureAwait(false);
                if (read.Status
                        != HairRestoreStoreStatus.Success
                    || !IsValidStoredRecord(read.Record)
                    || read.Record.State
                        != HairRestorePointState.Committed
                    || read.Record.RestoreTokenConsumed
                    || !IsLive(read.Record)
                    || !string.Equals(
                        read.Record.PreviewHash,
                        preview.PreviewHash,
                        StringComparison.Ordinal)
                    || !HairAppearanceHashing
                        .FixedTimeTokenMatches(
                            escrow.RestoreToken,
                            read.Record.RestoreTokenHash))
                {
                    if (read.Status
                            == HairRestoreStoreStatus.Success
                        && read.Record != null
                        && (!IsLive(read.Record)
                            || read.Record
                                .RestoreTokenConsumed
                            || read.Record.State
                                is HairRestorePointState
                                    .CommitRejected
                                or HairRestorePointState
                                    .RestorePending
                                or HairRestorePointState
                                    .RestoreUnknown
                                or HairRestorePointState
                                    .RestoreRejected
                                or HairRestorePointState
                                    .Restored
                                or HairRestorePointState
                                    .Expired))
                    {
                        RemoveEscrowUnsafe(
                            preview.TransactionId);
                    }
                    return null;
                }

                _restoreCapabilityEscrows.Remove(
                    preview.TransactionId);
                return new HairReconciledRestoreCapability(
                    escrow.RestoreToken,
                    escrow.ExpiresAtUtc);
            }
            finally
            {
                _writeGate.Release();
            }
        }

        public async Task<HairTransactionResult> RestoreAsync(
            string transactionId,
            string restoreToken,
            CancellationToken cancellationToken = default)
        {
            if (!HairAppearanceValidation.IsSafeString(
                    transactionId,
                    160,
                    false)
                || string.IsNullOrWhiteSpace(restoreToken)
                || restoreToken.Length > 256)
            {
                return HairTransactionResult.Create(
                    HairTransactionOutcome.Rejected,
                    HairAppearanceReasonCodes.InvalidPayload,
                    null,
                    transactionId,
                    null);
            }

            await _writeGate.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                ThrowIfDisposed();
                ClearExpiredEscrowsUnsafe();
                HairRestoreStoreResult read = await SafeReadAsync(
                    transactionId,
                    cancellationToken).ConfigureAwait(false);
                if (read.Status != HairRestoreStoreStatus.Success
                    || !IsValidStoredRecord(read.Record))
                {
                    return StoreReadFailure(transactionId, read.Status);
                }
                HairRestorePointRecord record = read.Record;
                if (!IsLive(record))
                {
                    RemoveEscrowUnsafe(record.TransactionId);
                    await TryMarkExpiredAsync(
                        record,
                        cancellationToken).ConfigureAwait(false);
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Rejected,
                        HairAppearanceReasonCodes.RestoreExpired,
                        null,
                        record.TransactionId,
                        record.PreviewHash);
                }
                if (record.RestoreTokenConsumed)
                {
                    RemoveEscrowUnsafe(record.TransactionId);
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Rejected,
                        HairAppearanceReasonCodes.RestoreTokenReplayed,
                        null,
                        record.TransactionId,
                        record.PreviewHash);
                }
                if (!HairAppearanceHashing.FixedTimeTokenMatches(
                    restoreToken,
                    record.RestoreTokenHash))
                {
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Rejected,
                        HairAppearanceReasonCodes.RestoreTokenInvalid,
                        null,
                        record.TransactionId,
                        record.PreviewHash);
                }
                if (record.State != HairRestorePointState.Committed)
                {
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Rejected,
                        HairAppearanceReasonCodes.ReconcileRequired,
                        DomainAuthoritativeReconcile,
                        record.TransactionId,
                        record.PreviewHash);
                }

                HairInspectResult inspect = await InspectInternalAsync(
                    record.Binding,
                    cancellationToken).ConfigureAwait(false);
                if (!inspect.Success)
                {
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Rejected,
                        inspect.ReasonCode,
                        null,
                        record.TransactionId,
                        record.PreviewHash);
                }
                if (!string.Equals(
                        inspect.Snapshot.CurrentHair,
                        record.AfterHair,
                        StringComparison.Ordinal)
                    || inspect.Snapshot.Revision !=
                        record.AuthoritativeRevision
                    || inspect.Snapshot.Generation !=
                        record.AuthoritativeGeneration
                    || !string.Equals(
                        inspect.SnapshotHash,
                        record.AuthoritativeSnapshotHash,
                        StringComparison.Ordinal))
                {
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Rejected,
                        HairAppearanceReasonCodes.StaleState,
                        null,
                        record.TransactionId,
                        record.PreviewHash,
                        inspect);
                }

                HairRestoreStoreResult pending = await SafeUpdateAsync(
                    record.With(
                        HairRestorePointState.RestorePending,
                        record.AuthoritativeRevision,
                        record.AuthoritativeGeneration,
                        record.AuthoritativeSnapshotHash,
                        true),
                    record.StoreVersion,
                    cancellationToken).ConfigureAwait(false);
                if (pending.Status != HairRestoreStoreStatus.Success
                    || !IsValidStoredRecord(pending.Record))
                {
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Rejected,
                        pending.Status == HairRestoreStoreStatus.Conflict
                            ? HairAppearanceReasonCodes.RestoreStoreConflict
                            : HairAppearanceReasonCodes.RestoreStoreUnavailable,
                        null,
                        record.TransactionId,
                        record.PreviewHash);
                }
                record = pending.Record;
                RemoveEscrowUnsafe(record.TransactionId);

                var command = new HairDomainCommitCommand(
                    record.TransactionId,
                    record.Binding,
                    record.BeforeHair,
                    record.AfterHair,
                    inspect.Snapshot.Revision,
                    inspect.Snapshot.Generation,
                    inspect.SnapshotHash,
                    true);
                HairAdapterCommitResult adapterResult =
                    await InvokeCommitAsync(
                        command,
                        cancellationToken).ConfigureAwait(false);

                if (adapterResult.Status == HairAdapterCommitStatus.Applied
                    && IsValidAppliedSnapshot(
                        adapterResult.Snapshot,
                        record.Binding,
                        record.BeforeHair,
                        inspect.Snapshot.Revision,
                        inspect.Snapshot.Generation))
                {
                    HairInspectResult authoritative =
                        ToInspect(adapterResult.Snapshot);
                    bool restoredDurably =
                        await SafeTransitionAsync(
                            record,
                            HairRestorePointState.Restored,
                            authoritative,
                            true,
                            cancellationToken).ConfigureAwait(false);
                    if (!restoredDurably)
                    {
                        return HairTransactionResult.Create(
                            HairTransactionOutcome.Unknown,
                            HairAppearanceReasonCodes
                                .RestoreStoreUnavailable,
                            DomainAuthoritativeReconcile,
                            record.TransactionId,
                            record.PreviewHash,
                            authoritative);
                    }
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Restored,
                        null,
                        null,
                        record.TransactionId,
                        record.PreviewHash,
                        authoritative);
                }
                if (adapterResult.Status == HairAdapterCommitStatus.Rejected)
                {
                    bool rejectedDurably =
                        await SafeTransitionAsync(
                            record,
                            HairRestorePointState.RestoreRejected,
                            inspect,
                            true,
                            cancellationToken).ConfigureAwait(false);
                    if (!rejectedDurably)
                    {
                        return HairTransactionResult.Create(
                            HairTransactionOutcome.Unknown,
                            HairAppearanceReasonCodes
                                .RestoreStoreUnavailable,
                            DomainAuthoritativeReconcile,
                            record.TransactionId,
                            record.PreviewHash,
                            inspect);
                    }
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Rejected,
                        NormalizeAdapterReason(adapterResult.ReasonCode),
                        null,
                        record.TransactionId,
                        record.PreviewHash);
                }

                bool unknownDurably =
                    await SafeTransitionAsync(
                        record,
                        HairRestorePointState.RestoreUnknown,
                        inspect,
                        true,
                        cancellationToken).ConfigureAwait(false);
                return HairTransactionResult.Create(
                    HairTransactionOutcome.Unknown,
                    !unknownDurably
                        ? HairAppearanceReasonCodes
                            .RestoreStoreUnavailable
                        : adapterResult.Status
                            == HairAdapterCommitStatus.Applied
                            ? HairAppearanceReasonCodes
                                .MalformedAuthority
                            : NormalizeUnknownReason(
                                adapterResult.ReasonCode),
                    DomainAuthoritativeReconcile,
                    record.TransactionId,
                    record.PreviewHash);
            }
            finally
            {
                _writeGate.Release();
            }
        }

        private async Task<HairTransactionResult> ReconcileRecordAsync(
            HairRestorePointRecord record,
            CancellationToken cancellationToken)
        {
            if (!IsLive(record))
            {
                RemoveEscrowUnsafe(record.TransactionId);
                await TryMarkExpiredAsync(
                    record,
                    cancellationToken).ConfigureAwait(false);
                return HairTransactionResult.Create(
                    HairTransactionOutcome.Rejected,
                    HairAppearanceReasonCodes.RestoreExpired,
                    null,
                    record.TransactionId,
                    record.PreviewHash);
            }

            if (record.State == HairRestorePointState.CommitRejected)
            {
                RemoveEscrowUnsafe(record.TransactionId);
                return HairTransactionResult.Create(
                    HairTransactionOutcome.NotApplied,
                    null,
                    null,
                    record.TransactionId,
                    record.PreviewHash);
            }
            if (record.State == HairRestorePointState.RestoreRejected)
            {
                RemoveEscrowUnsafe(record.TransactionId);
                return HairTransactionResult.Create(
                    HairTransactionOutcome.NotApplied,
                    null,
                    null,
                    record.TransactionId,
                    record.PreviewHash);
            }

            HairInspectResult inspect = await InspectInternalAsync(
                record.Binding,
                cancellationToken).ConfigureAwait(false);
            if (!inspect.Success)
            {
                return HairTransactionResult.Create(
                    HairTransactionOutcome.Unknown,
                    inspect.ReasonCode,
                    DomainAuthoritativeReconcile,
                    record.TransactionId,
                    record.PreviewHash);
            }

            if (record.State == HairRestorePointState.Prepared
                || record.State == HairRestorePointState.CommitUnknown)
            {
                if (string.Equals(
                        inspect.Snapshot.CurrentHair,
                        record.AfterHair,
                        StringComparison.Ordinal)
                    && inspect.Snapshot.Revision > record.BeforeRevision
                    && inspect.Snapshot.Generation == record.BeforeGeneration)
                {
                    bool committedDurably =
                        await SafeTransitionAsync(
                        record,
                        HairRestorePointState.Committed,
                        inspect,
                        false,
                        cancellationToken).ConfigureAwait(false);
                    if (!committedDurably)
                    {
                        return HairTransactionResult.Create(
                            HairTransactionOutcome.Unknown,
                            HairAppearanceReasonCodes
                                .RestoreStoreUnavailable,
                            DomainAuthoritativeReconcile,
                            record.TransactionId,
                            record.PreviewHash,
                            inspect);
                    }
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.DomainCommitted,
                        null,
                        null,
                        record.TransactionId,
                        record.PreviewHash,
                        inspect);
                }
                if (string.Equals(
                        inspect.Snapshot.CurrentHair,
                        record.BeforeHair,
                        StringComparison.Ordinal)
                    && inspect.Snapshot.Revision == record.BeforeRevision
                    && inspect.Snapshot.Generation == record.BeforeGeneration
                    && string.Equals(
                        inspect.SnapshotHash,
                        record.BeforeSnapshotHash,
                        StringComparison.Ordinal))
                {
                    RemoveEscrowUnsafe(record.TransactionId);
                    bool rejectedDurably =
                        await SafeTransitionAsync(
                            record,
                            HairRestorePointState.CommitRejected,
                            inspect,
                            false,
                            cancellationToken).ConfigureAwait(false);
                    if (!rejectedDurably)
                    {
                        return HairTransactionResult.Create(
                            HairTransactionOutcome.Unknown,
                            HairAppearanceReasonCodes
                                .RestoreStoreUnavailable,
                            DomainAuthoritativeReconcile,
                            record.TransactionId,
                            record.PreviewHash,
                            inspect);
                    }
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.NotApplied,
                        null,
                        null,
                        record.TransactionId,
                        record.PreviewHash,
                        inspect);
                }
                return UnknownManual(record, inspect);
            }

            if (record.State == HairRestorePointState.Committed)
            {
                if (MatchesLastAuthoritative(
                    record,
                    inspect,
                    record.AfterHair))
                {
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.DomainCommitted,
                        null,
                        null,
                        record.TransactionId,
                        record.PreviewHash,
                        inspect);
                }
                return UnknownManual(record, inspect);
            }

            if (record.State == HairRestorePointState.RestorePending
                || record.State == HairRestorePointState.RestoreUnknown)
            {
                RemoveEscrowUnsafe(record.TransactionId);
                if (string.Equals(
                        inspect.Snapshot.CurrentHair,
                        record.BeforeHair,
                        StringComparison.Ordinal)
                    && inspect.Snapshot.Revision >
                        record.AuthoritativeRevision
                    && inspect.Snapshot.Generation ==
                        record.AuthoritativeGeneration)
                {
                    bool restoredDurably =
                        await SafeTransitionAsync(
                            record,
                            HairRestorePointState.Restored,
                            inspect,
                            true,
                            cancellationToken).ConfigureAwait(false);
                    if (!restoredDurably)
                    {
                        return HairTransactionResult.Create(
                            HairTransactionOutcome.Unknown,
                            HairAppearanceReasonCodes
                                .RestoreStoreUnavailable,
                            DomainAuthoritativeReconcile,
                            record.TransactionId,
                            record.PreviewHash,
                            inspect);
                    }
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Restored,
                        null,
                        null,
                        record.TransactionId,
                        record.PreviewHash,
                        inspect);
                }
                if (MatchesLastAuthoritative(
                    record,
                    inspect,
                    record.AfterHair))
                {
                    bool rejectedDurably =
                        await SafeTransitionAsync(
                            record,
                            HairRestorePointState.RestoreRejected,
                            inspect,
                            true,
                            cancellationToken).ConfigureAwait(false);
                    if (!rejectedDurably)
                    {
                        return HairTransactionResult.Create(
                            HairTransactionOutcome.Unknown,
                            HairAppearanceReasonCodes
                                .RestoreStoreUnavailable,
                            DomainAuthoritativeReconcile,
                            record.TransactionId,
                            record.PreviewHash,
                            inspect);
                    }
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.NotApplied,
                        null,
                        null,
                        record.TransactionId,
                        record.PreviewHash,
                        inspect);
                }
                return UnknownManual(record, inspect);
            }

            if (record.State == HairRestorePointState.Restored)
            {
                RemoveEscrowUnsafe(record.TransactionId);
                if (MatchesLastAuthoritative(
                    record,
                    inspect,
                    record.BeforeHair))
                {
                    return HairTransactionResult.Create(
                        HairTransactionOutcome.Restored,
                        null,
                        null,
                        record.TransactionId,
                        record.PreviewHash,
                        inspect);
                }
                return UnknownManual(record, inspect);
            }

            return HairTransactionResult.Create(
                HairTransactionOutcome.Rejected,
                HairAppearanceReasonCodes.RestoreExpired,
                null,
                record.TransactionId,
                record.PreviewHash);
        }

        private async Task<HairInspectResult> InspectInternalAsync(
            HairSaveBinding expectedBinding,
            CancellationToken cancellationToken)
        {
            if (!HairAppearanceValidation.IsValidBinding(expectedBinding))
            {
                return HairInspectResult.Failed(
                    HairAppearanceReasonCodes.InvalidPayload);
            }

            HairAdapterInspectResult result;
            try
            {
                result = await _adapter.InspectAsync(
                    expectedBinding,
                    cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
                when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException)
            {
                return HairInspectResult.Failed(
                    HairAppearanceReasonCodes.AdapterUnavailable);
            }
            catch (Exception)
            {
                return HairInspectResult.Failed(
                    HairAppearanceReasonCodes.AdapterUnavailable);
            }

            cancellationToken.ThrowIfCancellationRequested();
            if (result == null || !result.Success)
            {
                return HairInspectResult.Failed(
                    NormalizeAdapterReason(result?.ReasonCode));
            }
            if (!HairAppearanceValidation.IsValidSnapshot(result.Snapshot))
            {
                return HairInspectResult.Failed(
                    HairAppearanceReasonCodes.MalformedAuthority);
            }
            if (!expectedBinding.Equals(result.Snapshot.Binding))
            {
                return HairInspectResult.Failed(
                    HairAppearanceReasonCodes.CrossSave);
            }
            return ToInspect(result.Snapshot);
        }

        private async Task<HairAdapterCommitResult> InvokeCommitAsync(
            HairDomainCommitCommand command,
            CancellationToken cancellationToken)
        {
            try
            {
                HairAdapterCommitResult result = await _adapter.CommitAsync(
                    command,
                    cancellationToken).ConfigureAwait(false);
                return result ?? HairAdapterCommitResult.Unknown(
                    HairAppearanceReasonCodes.UnknownWriteOutcome);
            }
            catch (Exception)
            {
                // Once the adapter call begins, cancellation/disconnection can
                // occur after the AS2 owner applied the CAS. Never infer zero
                // write and never replay.
                return HairAdapterCommitResult.Unknown(
                    HairAppearanceReasonCodes.UnknownWriteOutcome);
            }
        }

        private async Task<HairRestoreStoreResult> SafeCreateAsync(
            HairRestorePointRecord record,
            CancellationToken cancellationToken)
        {
            try
            {
                HairRestoreStoreResult result =
                    await _restoreStore.TryCreateAsync(
                        record,
                        cancellationToken).ConfigureAwait(false);
                return result ?? HairRestoreStoreResult.Unavailable();
            }
            catch (Exception)
            {
                return HairRestoreStoreResult.Unavailable();
            }
        }

        private async Task<HairRestoreStoreResult> SafeReadAsync(
            string transactionId,
            CancellationToken cancellationToken)
        {
            try
            {
                HairRestoreStoreResult result =
                    await _restoreStore.ReadAsync(
                        transactionId,
                        cancellationToken).ConfigureAwait(false);
                return result ?? HairRestoreStoreResult.Unavailable();
            }
            catch (Exception)
            {
                return HairRestoreStoreResult.Unavailable();
            }
        }

        private async Task<HairRestoreStoreResult> SafeUpdateAsync(
            HairRestorePointRecord record,
            long expectedStoreVersion,
            CancellationToken cancellationToken)
        {
            try
            {
                HairRestoreStoreResult result =
                    await _restoreStore.TryUpdateAsync(
                        record,
                        expectedStoreVersion,
                        cancellationToken).ConfigureAwait(false);
                return result ?? HairRestoreStoreResult.Unavailable();
            }
            catch (Exception)
            {
                return HairRestoreStoreResult.Unavailable();
            }
        }

        private async Task<bool> SafeTransitionAsync(
            HairRestorePointRecord record,
            HairRestorePointState state,
            HairInspectResult authoritative,
            bool restoreTokenConsumed,
            CancellationToken cancellationToken)
        {
            if (record == null || authoritative == null
                || !authoritative.Success)
            {
                return false;
            }
            HairRestorePointRecord replacement = record.With(
                state,
                authoritative.Snapshot.Revision,
                authoritative.Snapshot.Generation,
                authoritative.SnapshotHash,
                restoreTokenConsumed);
            HairRestoreStoreResult updated =
                await SafeUpdateAsync(
                replacement,
                record.StoreVersion,
                cancellationToken).ConfigureAwait(false);
            return updated.Status
                    == HairRestoreStoreStatus.Success
                && IsValidStoredRecord(updated.Record)
                && updated.Record.State == state
                && updated.Record.RestoreTokenConsumed
                    == restoreTokenConsumed
                && string.Equals(
                    updated.Record.TransactionId,
                    record.TransactionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    updated.Record.PreviewHash,
                    record.PreviewHash,
                    StringComparison.Ordinal);
        }

        private async Task TryMarkExpiredAsync(
            HairRestorePointRecord record,
            CancellationToken cancellationToken)
        {
            HairRestorePointRecord expired = record.With(
                HairRestorePointState.Expired,
                record.AuthoritativeRevision,
                record.AuthoritativeGeneration,
                record.AuthoritativeSnapshotHash,
                record.RestoreTokenConsumed);
            await SafeUpdateAsync(
                expired,
                record.StoreVersion,
                cancellationToken).ConfigureAwait(false);
        }

        private bool IsLive(HairRestorePointRecord record)
        {
            DateTimeOffset now = _clock.UtcNow;
            TimeSpan declaredTtl = record.ExpiresAtUtc - record.CreatedAtUtc;
            // A backwards wall-clock jump fails closed instead of extending a
            // persisted token across restart/reboot.
            return declaredTtl > TimeSpan.Zero
                && declaredTtl <= MaximumRestoreTtl
                && now >= record.CreatedAtUtc
                && now < record.ExpiresAtUtc;
        }

        private static bool IsValidStoredRecord(
            HairRestorePointRecord record)
        {
            if (record == null
                || !HairAppearanceValidation.IsSafeString(
                    record.TransactionId,
                    160,
                    false)
                || !HairAppearanceValidation.IsValidBinding(record.Binding)
                || !HairAppearanceValidation.IsSafeString(
                    record.BeforeHair,
                    160,
                    false)
                || !HairAppearanceValidation.IsSafeString(
                    record.AfterHair,
                    160,
                    false)
                || string.Equals(
                    record.BeforeHair,
                    record.AfterHair,
                    StringComparison.Ordinal)
                || record.BeforeRevision < 0
                || record.BeforeGeneration < 0
                || !HairAppearanceValidation.IsSha256(
                    record.BeforeSnapshotHash)
                || !HairAppearanceValidation.IsSha256(record.PreviewHash)
                || !HairAppearanceValidation.IsSha256(
                    record.RestoreTokenHash)
                || record.ExpiresAtUtc <= record.CreatedAtUtc
                || record.ExpiresAtUtc - record.CreatedAtUtc >
                    MaximumRestoreTtl
                || record.StoreVersion <= 0
                || record.AuthoritativeRevision < 0
                || record.AuthoritativeGeneration < 0
                || !HairAppearanceValidation.IsSha256(
                    record.AuthoritativeSnapshotHash))
            {
                return false;
            }
            if (!Enum.IsDefined(record.State))
            {
                return false;
            }
            bool restoreAttempted =
                record.State == HairRestorePointState.RestorePending
                || record.State == HairRestorePointState.RestoreUnknown
                || record.State == HairRestorePointState.RestoreRejected
                || record.State == HairRestorePointState.Restored;
            if (record.State != HairRestorePointState.Expired
                && restoreAttempted != record.RestoreTokenConsumed)
            {
                return false;
            }

            string expectedPreviewHash =
                HairAppearanceHashing.ComputePreviewHash(
                    record.TransactionId,
                    record.Binding,
                    record.BeforeHair,
                    record.AfterHair,
                    record.BeforeRevision,
                    record.BeforeGeneration,
                    record.BeforeSnapshotHash);
            return string.Equals(
                expectedPreviewHash,
                record.PreviewHash,
                StringComparison.Ordinal);
        }

        private static bool IsValidAppliedSnapshot(
            HairAuthoritativeSnapshot snapshot,
            HairSaveBinding expectedBinding,
            string expectedHair,
            long previousRevision,
            long expectedGeneration)
        {
            return HairAppearanceValidation.IsValidSnapshot(snapshot)
                && expectedBinding.Equals(snapshot.Binding)
                && string.Equals(
                    snapshot.CurrentHair,
                    expectedHair,
                    StringComparison.Ordinal)
                && snapshot.Revision > previousRevision
                && snapshot.Generation == expectedGeneration;
        }

        private static bool MatchesLastAuthoritative(
            HairRestorePointRecord record,
            HairInspectResult inspect,
            string expectedHair)
        {
            return inspect != null
                && inspect.Success
                && string.Equals(
                    inspect.Snapshot.CurrentHair,
                    expectedHair,
                    StringComparison.Ordinal)
                && inspect.Snapshot.Revision ==
                    record.AuthoritativeRevision
                && inspect.Snapshot.Generation ==
                    record.AuthoritativeGeneration
                && string.Equals(
                    inspect.SnapshotHash,
                    record.AuthoritativeSnapshotHash,
                    StringComparison.Ordinal);
        }

        private static HairInspectResult ToInspect(
            HairAuthoritativeSnapshot snapshot)
        {
            return HairInspectResult.Succeeded(
                snapshot,
                HairAppearanceHashing.ComputeSnapshotHash(snapshot));
        }

        private static HairTransactionResult Rejected(
            HairAppearancePreview preview,
            string reasonCode)
        {
            return HairTransactionResult.Create(
                HairTransactionOutcome.Rejected,
                reasonCode,
                null,
                preview?.TransactionId,
                preview?.PreviewHash);
        }

        private static HairTransactionResult StoreReadFailure(
            string transactionId,
            HairRestoreStoreStatus status)
        {
            return HairTransactionResult.Create(
                HairTransactionOutcome.Rejected,
                status == HairRestoreStoreStatus.NotFound
                    ? HairAppearanceReasonCodes.TransactionNotFound
                    : status == HairRestoreStoreStatus.Conflict
                        ? HairAppearanceReasonCodes.RestoreStoreConflict
                        : HairAppearanceReasonCodes.RestoreStoreUnavailable,
                null,
                transactionId,
                null);
        }

        private static HairTransactionResult UnknownManual(
            HairRestorePointRecord record,
            HairInspectResult inspect)
        {
            return HairTransactionResult.Create(
                HairTransactionOutcome.Unknown,
                HairAppearanceReasonCodes.StaleState,
                ManualRequiredReconcile,
                record.TransactionId,
                record.PreviewHash,
                inspect);
        }

        private static string NormalizeAdapterReason(string reasonCode)
        {
            return HairAppearanceValidation.IsSafeString(
                reasonCode,
                96,
                false)
                ? reasonCode
                : HairAppearanceReasonCodes.AdapterUnavailable;
        }

        private static string NormalizeUnknownReason(string reasonCode)
        {
            return HairAppearanceValidation.IsSafeString(
                reasonCode,
                96,
                false)
                ? reasonCode
                : HairAppearanceReasonCodes.UnknownWriteOutcome;
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
            {
                throw new ObjectDisposedException(
                    nameof(HairAppearanceModifierTransaction));
            }
        }

        private void StoreEscrowUnsafe(
            HairAppearancePreview preview,
            string restoreToken,
            DateTimeOffset expiresAtUtc)
        {
            if (preview == null
                || string.IsNullOrWhiteSpace(restoreToken)
                || expiresAtUtc <= _clock.UtcNow)
            {
                return;
            }
            _restoreCapabilityEscrows[preview.TransactionId] =
                new RestoreCapabilityEscrow(
                    preview,
                    restoreToken,
                    expiresAtUtc);
        }

        private void RemoveEscrowUnsafe(string transactionId)
        {
            if (!string.IsNullOrWhiteSpace(transactionId))
            {
                _restoreCapabilityEscrows.Remove(
                    transactionId);
            }
        }

        private void ClearExpiredEscrowsUnsafe()
        {
            if (_restoreCapabilityEscrows.Count == 0)
                return;
            DateTimeOffset now = _clock.UtcNow;
            var expired = new List<string>();
            foreach (KeyValuePair<string, RestoreCapabilityEscrow>
                pair in _restoreCapabilityEscrows)
            {
                if (now < pair.Value.Preview.CreatedAtUtc
                    || now >= pair.Value.ExpiresAtUtc)
                {
                    expired.Add(pair.Key);
                }
            }
            foreach (string transactionId in expired)
                _restoreCapabilityEscrows.Remove(transactionId);
        }

        private static string CreateRestoreToken()
        {
            byte[] bytes = new byte[32];
            System.Security.Cryptography.RandomNumberGenerator.Fill(bytes);
            return Convert.ToBase64String(bytes)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }

        private sealed class RestoreCapabilityEscrow
        {
            internal RestoreCapabilityEscrow(
                HairAppearancePreview preview,
                string restoreToken,
                DateTimeOffset expiresAtUtc)
            {
                Preview = preview;
                TransactionId = preview.TransactionId;
                PreviewHash = preview.PreviewHash;
                RestoreToken = restoreToken;
                ExpiresAtUtc = expiresAtUtc;
            }

            internal HairAppearancePreview Preview { get; }
            internal string TransactionId { get; }
            internal string PreviewHash { get; }
            internal string RestoreToken { get; }
            internal DateTimeOffset ExpiresAtUtc { get; }
        }
    }

    internal sealed class HairReconciledRestoreCapability
    {
        internal HairReconciledRestoreCapability(
            string restoreToken,
            DateTimeOffset expiresAtUtc)
        {
            RestoreToken = restoreToken;
            ExpiresAtUtc = expiresAtUtc;
        }

        internal string RestoreToken { get; }
        internal DateTimeOffset ExpiresAtUtc { get; }
    }
}
