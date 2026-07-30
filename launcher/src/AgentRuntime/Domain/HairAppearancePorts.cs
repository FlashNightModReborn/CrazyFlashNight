using System;
using System.Threading;
using System.Threading.Tasks;

namespace CF7Launcher.AgentRuntime.Domain
{
    public sealed class HairAdapterInspectResult
    {
        private HairAdapterInspectResult(
            bool success,
            string reasonCode,
            HairAuthoritativeSnapshot snapshot)
        {
            Success = success;
            ReasonCode = reasonCode;
            Snapshot = snapshot;
        }

        public bool Success { get; }

        public string ReasonCode { get; }

        public HairAuthoritativeSnapshot Snapshot { get; }

        public static HairAdapterInspectResult Succeeded(
            HairAuthoritativeSnapshot snapshot)
        {
            return new HairAdapterInspectResult(true, null, snapshot);
        }

        public static HairAdapterInspectResult Failed(string reasonCode)
        {
            return new HairAdapterInspectResult(false, reasonCode, null);
        }
    }

    public sealed class HairDomainCommitCommand
    {
        public HairDomainCommitCommand(
            string transactionId,
            HairSaveBinding binding,
            string hairIdentifier,
            string expectedCurrentHair,
            long expectedRevision,
            long expectedGeneration,
            string expectedSnapshotHash,
            bool isRestore)
        {
            TransactionId = transactionId;
            Binding = binding;
            HairIdentifier = hairIdentifier;
            ExpectedCurrentHair = expectedCurrentHair;
            ExpectedRevision = expectedRevision;
            ExpectedGeneration = expectedGeneration;
            ExpectedSnapshotHash = expectedSnapshotHash;
            IsRestore = isRestore;
        }

        public string Operation
        {
            get { return HairAppearanceOperation.Name; }
        }

        public string TransactionId { get; }

        public HairSaveBinding Binding { get; }

        public string HairIdentifier { get; }

        public string ExpectedCurrentHair { get; }

        public long ExpectedRevision { get; }

        public long ExpectedGeneration { get; }

        public string ExpectedSnapshotHash { get; }

        public bool IsRestore { get; }
    }

    public enum HairAdapterCommitStatus
    {
        Applied = 0,
        Rejected = 1,
        Unknown = 2
    }

    public sealed class HairAdapterCommitResult
    {
        private HairAdapterCommitResult(
            HairAdapterCommitStatus status,
            string reasonCode,
            HairAuthoritativeSnapshot snapshot)
        {
            Status = status;
            ReasonCode = reasonCode;
            Snapshot = snapshot;
        }

        public HairAdapterCommitStatus Status { get; }

        public string ReasonCode { get; }

        public HairAuthoritativeSnapshot Snapshot { get; }

        public static HairAdapterCommitResult Applied(
            HairAuthoritativeSnapshot snapshot)
        {
            return new HairAdapterCommitResult(
                HairAdapterCommitStatus.Applied,
                null,
                snapshot);
        }

        public static HairAdapterCommitResult Rejected(string reasonCode)
        {
            return new HairAdapterCommitResult(
                HairAdapterCommitStatus.Rejected,
                reasonCode,
                null);
        }

        public static HairAdapterCommitResult Unknown(string reasonCode)
        {
            return new HairAdapterCommitResult(
                HairAdapterCommitStatus.Unknown,
                reasonCode,
                null);
        }
    }

    /// <summary>
    /// Production implementations must enrich HairdresserTask's authoritative
    /// snapshot with Launcher-owned save/revision generations and must route
    /// every commit through HairdresserTask.ExecuteAgentRequestAsync. Direct
    /// SOL, _root, console, or parallel Flash writes violate this port.
    /// </summary>
    public interface IHairdresserDomainAdapter
    {
        Task<HairAdapterInspectResult> InspectAsync(
            HairSaveBinding expectedBinding,
            CancellationToken cancellationToken);

        Task<HairAdapterCommitResult> CommitAsync(
            HairDomainCommitCommand command,
            CancellationToken cancellationToken);
    }

    public enum HairRestoreStoreStatus
    {
        Success = 0,
        NotFound = 1,
        Conflict = 2,
        Unavailable = 3
    }

    public sealed class HairRestoreStoreResult
    {
        private HairRestoreStoreResult(
            HairRestoreStoreStatus status,
            HairRestorePointRecord record)
        {
            Status = status;
            Record = record;
        }

        public HairRestoreStoreStatus Status { get; }

        public HairRestorePointRecord Record { get; }

        public static HairRestoreStoreResult Success(
            HairRestorePointRecord record)
        {
            return new HairRestoreStoreResult(
                HairRestoreStoreStatus.Success,
                record);
        }

        public static HairRestoreStoreResult NotFound()
        {
            return new HairRestoreStoreResult(
                HairRestoreStoreStatus.NotFound,
                null);
        }

        public static HairRestoreStoreResult Conflict(
            HairRestorePointRecord current = null)
        {
            return new HairRestoreStoreResult(
                HairRestoreStoreStatus.Conflict,
                current);
        }

        public static HairRestoreStoreResult Unavailable()
        {
            return new HairRestoreStoreResult(
                HairRestoreStoreStatus.Unavailable,
                null);
        }
    }

    /// <summary>
    /// A production store must durably create the Prepared record before the
    /// domain adapter is invoked and provide optimistic, atomic replacement.
    /// </summary>
    public interface IHairRestorePointStore
    {
        Task<HairRestoreStoreResult> TryCreateAsync(
            HairRestorePointRecord record,
            CancellationToken cancellationToken);

        Task<HairRestoreStoreResult> ReadAsync(
            string transactionId,
            CancellationToken cancellationToken);

        Task<HairRestoreStoreResult> TryUpdateAsync(
            HairRestorePointRecord record,
            long expectedStoreVersion,
            CancellationToken cancellationToken);
    }

    /// <summary>
    /// Safe placeholder for hosts that have not wired the existing
    /// HairdresserTask bridge yet. It never advertises or performs a write.
    /// </summary>
    public sealed class FailClosedHairdresserDomainAdapter
        : IHairdresserDomainAdapter
    {
        public Task<HairAdapterInspectResult> InspectAsync(
            HairSaveBinding expectedBinding,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(
                HairAdapterInspectResult.Failed(
                    HairAppearanceReasonCodes.AdapterUnavailable));
        }

        public Task<HairAdapterCommitResult> CommitAsync(
            HairDomainCommitCommand command,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(
                HairAdapterCommitResult.Rejected(
                    HairAppearanceReasonCodes.AdapterUnavailable));
        }
    }

    /// <summary>
    /// Safe placeholder for hosts without a durable restore store. Since no
    /// restore point can be proven durable, all commits fail before dispatch.
    /// </summary>
    public sealed class FailClosedHairRestorePointStore
        : IHairRestorePointStore
    {
        public Task<HairRestoreStoreResult> TryCreateAsync(
            HairRestorePointRecord record,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(HairRestoreStoreResult.Unavailable());
        }

        public Task<HairRestoreStoreResult> ReadAsync(
            string transactionId,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(HairRestoreStoreResult.Unavailable());
        }

        public Task<HairRestoreStoreResult> TryUpdateAsync(
            HairRestorePointRecord record,
            long expectedStoreVersion,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(HairRestoreStoreResult.Unavailable());
        }
    }
}
