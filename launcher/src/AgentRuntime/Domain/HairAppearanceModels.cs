using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;

namespace CF7Launcher.AgentRuntime.Domain
{
    public static class HairAppearanceOperation
    {
        public const string Name = "appearance.hair.change.v1";
    }

    public static class HairAppearanceReasonCodes
    {
        public const string AdapterUnavailable = "adapter_unavailable";
        public const string ConsentExpired = "consent_expired";
        public const string ConsentMismatch = "consent_mismatch";
        public const string ConsentRequired = "consent_required";
        public const string ConsentReplayed = "consent_replayed";
        public const string CrossSave = "cross_save";
        public const string HairNotFound = "hair_not_found";
        public const string InvalidPayload = "invalid_payload";
        public const string MalformedAuthority = "malformed_authority";
        public const string NoChange = "no_change";
        public const string ReconcileRequired = "reconcile_required";
        public const string RestoreExpired = "restore_expired";
        public const string RestoreStoreConflict = "restore_store_conflict";
        public const string RestoreStoreUnavailable = "restore_store_unavailable";
        public const string RestoreTokenInvalid = "restore_token_invalid";
        public const string RestoreTokenReplayed = "restore_token_replayed";
        public const string StaleRevision = "stale_revision";
        public const string StaleState = "stale_state";
        public const string TransactionNotFound = "transaction_not_found";
        public const string UnknownWriteOutcome = "unknown_write_outcome";
    }

    public enum HairTransactionOutcome
    {
        Rejected = 0,
        PreviewReady = 1,
        DomainCommitted = 2,
        NotApplied = 3,
        Restored = 4,
        Unknown = 5
    }

    public enum HairRestorePointState
    {
        Prepared = 0,
        CommitUnknown = 1,
        Committed = 2,
        CommitRejected = 3,
        RestorePending = 4,
        RestoreUnknown = 5,
        RestoreRejected = 6,
        Restored = 7,
        Expired = 8
    }

    public sealed class HairSaveBinding : IEquatable<HairSaveBinding>
    {
        public HairSaveBinding(
            string sessionId,
            long lifecycleGeneration,
            string attemptId,
            long attemptGeneration,
            string slotId,
            string saveSignature)
        {
            SessionId = sessionId;
            LifecycleGeneration = lifecycleGeneration;
            AttemptId = attemptId ?? string.Empty;
            AttemptGeneration = attemptGeneration;
            SlotId = slotId;
            SaveSignature = saveSignature;
        }

        public string SessionId { get; }

        public long LifecycleGeneration { get; }

        public string AttemptId { get; }

        public long AttemptGeneration { get; }

        public string SlotId { get; }

        public string SaveSignature { get; }

        public bool Equals(HairSaveBinding other)
        {
            return other != null
                && string.Equals(SessionId, other.SessionId, StringComparison.Ordinal)
                && LifecycleGeneration == other.LifecycleGeneration
                && string.Equals(AttemptId, other.AttemptId, StringComparison.Ordinal)
                && AttemptGeneration == other.AttemptGeneration
                && string.Equals(SlotId, other.SlotId, StringComparison.Ordinal)
                && string.Equals(
                    SaveSignature,
                    other.SaveSignature,
                    StringComparison.Ordinal);
        }

        public override bool Equals(object value)
        {
            return Equals(value as HairSaveBinding);
        }

        public override int GetHashCode()
        {
            var hash = new HashCode();
            hash.Add(SessionId, StringComparer.Ordinal);
            hash.Add(LifecycleGeneration);
            hash.Add(AttemptId, StringComparer.Ordinal);
            hash.Add(AttemptGeneration);
            hash.Add(SlotId, StringComparer.Ordinal);
            hash.Add(SaveSignature, StringComparer.Ordinal);
            return hash.ToHashCode();
        }
    }

    public sealed class HairCatalogEntry
    {
        public HairCatalogEntry(string identifier, string displayName)
        {
            Identifier = identifier;
            DisplayName = displayName;
        }

        public string Identifier { get; }

        public string DisplayName { get; }
    }

    public sealed class HairAuthoritativeSnapshot
    {
        private readonly ReadOnlyCollection<HairCatalogEntry> _catalog;

        public HairAuthoritativeSnapshot(
            HairSaveBinding binding,
            long revision,
            long generation,
            string currentHair,
            IEnumerable<HairCatalogEntry> catalog)
        {
            Binding = binding;
            Revision = revision;
            Generation = generation;
            CurrentHair = currentHair;
            _catalog = new ReadOnlyCollection<HairCatalogEntry>(
                new List<HairCatalogEntry>(
                    catalog ?? Array.Empty<HairCatalogEntry>()));
        }

        public HairSaveBinding Binding { get; }

        public long Revision { get; }

        public long Generation { get; }

        public string CurrentHair { get; }

        public IReadOnlyList<HairCatalogEntry> Catalog
        {
            get { return _catalog; }
        }
    }

    public sealed class HairInspectResult
    {
        private HairInspectResult(
            bool success,
            string reasonCode,
            HairAuthoritativeSnapshot snapshot,
            string snapshotHash)
        {
            Success = success;
            ReasonCode = reasonCode;
            Snapshot = snapshot;
            SnapshotHash = snapshotHash;
        }

        public bool Success { get; }

        public string ReasonCode { get; }

        public HairAuthoritativeSnapshot Snapshot { get; }

        public string SnapshotHash { get; }

        public static HairInspectResult Succeeded(
            HairAuthoritativeSnapshot snapshot,
            string snapshotHash)
        {
            return new HairInspectResult(true, null, snapshot, snapshotHash);
        }

        public static HairInspectResult Failed(string reasonCode)
        {
            return new HairInspectResult(false, reasonCode, null, null);
        }
    }

    public sealed class HairPreviewRequest
    {
        public HairPreviewRequest(
            HairSaveBinding binding,
            string hairIdentifier,
            string expectedCurrentHair,
            long expectedRevision,
            long expectedGeneration,
            string expectedSnapshotHash)
        {
            Binding = binding;
            HairIdentifier = hairIdentifier;
            ExpectedCurrentHair = expectedCurrentHair;
            ExpectedRevision = expectedRevision;
            ExpectedGeneration = expectedGeneration;
            ExpectedSnapshotHash = expectedSnapshotHash;
        }

        public HairSaveBinding Binding { get; }

        public string HairIdentifier { get; }

        public string ExpectedCurrentHair { get; }

        public long ExpectedRevision { get; }

        public long ExpectedGeneration { get; }

        public string ExpectedSnapshotHash { get; }
    }

    public sealed class HairAppearancePreview
    {
        internal HairAppearancePreview(
            string transactionId,
            HairSaveBinding binding,
            string beforeHair,
            string afterHair,
            long expectedRevision,
            long expectedGeneration,
            string expectedSnapshotHash,
            string previewHash,
            DateTimeOffset createdAtUtc)
        {
            TransactionId = transactionId;
            Binding = binding;
            BeforeHair = beforeHair;
            AfterHair = afterHair;
            ExpectedRevision = expectedRevision;
            ExpectedGeneration = expectedGeneration;
            ExpectedSnapshotHash = expectedSnapshotHash;
            PreviewHash = previewHash;
            CreatedAtUtc = createdAtUtc;
        }

        public string Operation
        {
            get { return HairAppearanceOperation.Name; }
        }

        public string TransactionId { get; }

        public HairSaveBinding Binding { get; }

        public string BeforeHair { get; }

        public string AfterHair { get; }

        public long ExpectedRevision { get; }

        public long ExpectedGeneration { get; }

        public string ExpectedSnapshotHash { get; }

        public string PreviewHash { get; }

        public DateTimeOffset CreatedAtUtc { get; }
    }

    public sealed class HairPreviewResult
    {
        private HairPreviewResult(
            HairTransactionOutcome outcome,
            string reasonCode,
            HairAppearancePreview preview)
        {
            Outcome = outcome;
            ReasonCode = reasonCode;
            Preview = preview;
        }

        public HairTransactionOutcome Outcome { get; }

        public string ReasonCode { get; }

        public HairAppearancePreview Preview { get; }

        public static HairPreviewResult Ready(HairAppearancePreview preview)
        {
            return new HairPreviewResult(
                HairTransactionOutcome.PreviewReady,
                null,
                preview);
        }

        public static HairPreviewResult Rejected(string reasonCode)
        {
            return new HairPreviewResult(
                HairTransactionOutcome.Rejected,
                reasonCode,
                null);
        }
    }

    public sealed class HairValidationResult
    {
        private HairValidationResult(
            bool success,
            string reasonCode,
            HairInspectResult inspect)
        {
            Success = success;
            ReasonCode = reasonCode;
            Inspect = inspect;
        }

        public bool Success { get; }

        public string ReasonCode { get; }

        public HairInspectResult Inspect { get; }

        internal static HairValidationResult Valid(HairInspectResult inspect)
        {
            return new HairValidationResult(true, null, inspect);
        }

        internal static HairValidationResult Invalid(string reasonCode)
        {
            return new HairValidationResult(false, reasonCode, null);
        }
    }

    public sealed class HairAppearanceConsentToken
    {
        internal HairAppearanceConsentToken(
            string token,
            string transactionId,
            string previewHash,
            string consentReceiptId,
            DateTimeOffset expiresAtUtc)
        {
            Token = token;
            TransactionId = transactionId;
            PreviewHash = previewHash;
            ConsentReceiptId = consentReceiptId;
            ExpiresAtUtc = expiresAtUtc;
        }

        public string Token { get; }

        public string TransactionId { get; }

        public string PreviewHash { get; }

        public string ConsentReceiptId { get; }

        public DateTimeOffset ExpiresAtUtc { get; }
    }

    public sealed class HairTransactionResult
    {
        internal HairTransactionResult(
            HairTransactionOutcome outcome,
            string reasonCode,
            string reconcileKind,
            string transactionId,
            string previewHash,
            HairInspectResult authoritativeInspect,
            string restoreToken,
            DateTimeOffset? restoreExpiresAtUtc)
        {
            Outcome = outcome;
            ReasonCode = reasonCode;
            ReconcileKind = reconcileKind;
            TransactionId = transactionId;
            PreviewHash = previewHash;
            AuthoritativeInspect = authoritativeInspect;
            RestoreToken = restoreToken;
            RestoreExpiresAtUtc = restoreExpiresAtUtc;
        }

        public HairTransactionOutcome Outcome { get; }

        public string ReasonCode { get; }

        public string ReconcileKind { get; }

        public string TransactionId { get; }

        public string PreviewHash { get; }

        public HairInspectResult AuthoritativeInspect { get; }

        public string RestoreToken { get; }

        public DateTimeOffset? RestoreExpiresAtUtc { get; }

        internal static HairTransactionResult Create(
            HairTransactionOutcome outcome,
            string reasonCode,
            string reconcileKind,
            string transactionId,
            string previewHash,
            HairInspectResult authoritativeInspect = null,
            string restoreToken = null,
            DateTimeOffset? restoreExpiresAtUtc = null)
        {
            return new HairTransactionResult(
                outcome,
                reasonCode,
                reconcileKind,
                transactionId,
                previewHash,
                authoritativeInspect,
                restoreToken,
                restoreExpiresAtUtc);
        }
    }

    public sealed class HairRestorePointRecord
    {
        public HairRestorePointRecord(
            string transactionId,
            HairSaveBinding binding,
            string beforeHair,
            string afterHair,
            long beforeRevision,
            long beforeGeneration,
            string beforeSnapshotHash,
            string previewHash,
            string restoreTokenHash,
            DateTimeOffset createdAtUtc,
            DateTimeOffset expiresAtUtc,
            HairRestorePointState state,
            long storeVersion,
            long authoritativeRevision,
            long authoritativeGeneration,
            string authoritativeSnapshotHash,
            bool restoreTokenConsumed)
        {
            TransactionId = transactionId;
            Binding = binding;
            BeforeHair = beforeHair;
            AfterHair = afterHair;
            BeforeRevision = beforeRevision;
            BeforeGeneration = beforeGeneration;
            BeforeSnapshotHash = beforeSnapshotHash;
            PreviewHash = previewHash;
            RestoreTokenHash = restoreTokenHash;
            CreatedAtUtc = createdAtUtc;
            ExpiresAtUtc = expiresAtUtc;
            State = state;
            StoreVersion = storeVersion;
            AuthoritativeRevision = authoritativeRevision;
            AuthoritativeGeneration = authoritativeGeneration;
            AuthoritativeSnapshotHash = authoritativeSnapshotHash;
            RestoreTokenConsumed = restoreTokenConsumed;
        }

        public string TransactionId { get; }

        public HairSaveBinding Binding { get; }

        public string BeforeHair { get; }

        public string AfterHair { get; }

        public long BeforeRevision { get; }

        public long BeforeGeneration { get; }

        public string BeforeSnapshotHash { get; }

        public string PreviewHash { get; }

        public string RestoreTokenHash { get; }

        public DateTimeOffset CreatedAtUtc { get; }

        public DateTimeOffset ExpiresAtUtc { get; }

        public HairRestorePointState State { get; }

        public long StoreVersion { get; }

        public long AuthoritativeRevision { get; }

        public long AuthoritativeGeneration { get; }

        public string AuthoritativeSnapshotHash { get; }

        public bool RestoreTokenConsumed { get; }

        public HairRestorePointRecord With(
            HairRestorePointState state,
            long authoritativeRevision,
            long authoritativeGeneration,
            string authoritativeSnapshotHash,
            bool restoreTokenConsumed)
        {
            return new HairRestorePointRecord(
                TransactionId,
                Binding,
                BeforeHair,
                AfterHair,
                BeforeRevision,
                BeforeGeneration,
                BeforeSnapshotHash,
                PreviewHash,
                RestoreTokenHash,
                CreatedAtUtc,
                ExpiresAtUtc,
                state,
                StoreVersion,
                authoritativeRevision,
                authoritativeGeneration,
                authoritativeSnapshotHash,
                restoreTokenConsumed);
        }

        public HairRestorePointRecord WithStoreVersion(long storeVersion)
        {
            return new HairRestorePointRecord(
                TransactionId,
                Binding,
                BeforeHair,
                AfterHair,
                BeforeRevision,
                BeforeGeneration,
                BeforeSnapshotHash,
                PreviewHash,
                RestoreTokenHash,
                CreatedAtUtc,
                ExpiresAtUtc,
                State,
                storeVersion,
                AuthoritativeRevision,
                AuthoritativeGeneration,
                AuthoritativeSnapshotHash,
                RestoreTokenConsumed);
        }
    }
}
