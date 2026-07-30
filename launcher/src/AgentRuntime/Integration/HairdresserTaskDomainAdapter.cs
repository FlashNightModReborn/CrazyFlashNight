using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal sealed class HairDomainAuthorityStamp
    {
        public HairDomainAuthorityStamp(
            HairSaveBinding binding,
            long revision,
            long generation,
            string currentHair)
        {
            Binding = binding;
            Revision = revision;
            Generation = generation;
            CurrentHair = currentHair;
        }

        public HairSaveBinding Binding { get; }
        public long Revision { get; }
        public long Generation { get; }
        public string CurrentHair { get; }
    }

    /// <summary>
    /// Launcher-owned authority for the active save binding and its monotonic
    /// hair revision. Implementations must not accept binding identity from a
    /// wire client.
    /// </summary>
    internal interface IHairDomainAuthority
    {
        bool TryValidate(
            HairSaveBinding expectedBinding,
            long expectedRevision,
            long expectedGeneration,
            string expectedCurrentHair,
            out string reasonCode);

        bool TryObserve(
            HairSaveBinding expectedBinding,
            string currentHair,
            out HairDomainAuthorityStamp stamp,
            out string reasonCode);

        bool TryApply(
            HairSaveBinding expectedBinding,
            long expectedRevision,
            long expectedGeneration,
            string expectedCurrentHair,
            string newCurrentHair,
            out HairDomainAuthorityStamp stamp,
            out string reasonCode);
    }

    /// <summary>
    /// Production domain port for the existing AS2 Hairdresser owner. No SOL,
    /// _root, console, or parallel write path exists here: every snapshot and
    /// CAS commit uses HairdresserTask's audited callId bridge.
    /// </summary>
    internal sealed class HairdresserTaskDomainAdapter
        : IHairdresserDomainAdapter
    {
        private readonly HairdresserTask _task;
        private readonly IHairDomainAuthority _authority;

        public HairdresserTaskDomainAdapter(
            HairdresserTask task,
            IHairDomainAuthority authority)
        {
            _task = task ?? throw new ArgumentNullException(nameof(task));
            _authority = authority
                ?? throw new ArgumentNullException(nameof(authority));
        }

        public async Task<HairAdapterInspectResult> InspectAsync(
            HairSaveBinding expectedBinding,
            CancellationToken cancellationToken)
        {
            if (!HairAppearanceValidation.IsValidBinding(expectedBinding))
                return HairAdapterInspectResult.Failed(
                    HairAppearanceReasonCodes.InvalidPayload);

            SnapshotPayload payload;
            try
            {
                payload = await ReadSnapshotAsync(
                    cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
                when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                return HairAdapterInspectResult.Failed(
                    HairAppearanceReasonCodes.AdapterUnavailable);
            }

            if (payload == null)
                return HairAdapterInspectResult.Failed(
                    HairAppearanceReasonCodes.AdapterUnavailable);
            if (!_authority.TryObserve(
                    expectedBinding,
                    payload.CurrentHair,
                    out HairDomainAuthorityStamp stamp,
                    out string reasonCode))
            {
                return HairAdapterInspectResult.Failed(
                    NormalizeAuthorityReason(reasonCode));
            }
            return HairAdapterInspectResult.Succeeded(
                ToSnapshot(stamp, payload.Catalog));
        }

        public async Task<HairAdapterCommitResult> CommitAsync(
            HairDomainCommitCommand command,
            CancellationToken cancellationToken)
        {
            if (command == null
                || !HairAppearanceValidation.IsValidBinding(
                    command.Binding)
                || !HairAppearanceValidation.IsSafeString(
                    command.HairIdentifier,
                    160,
                    false)
                || !HairAppearanceValidation.IsSafeString(
                    command.ExpectedCurrentHair,
                    160,
                    false)
                || command.ExpectedRevision < 0
                || command.ExpectedGeneration < 0
                || !HairAppearanceValidation.IsSha256(
                    command.ExpectedSnapshotHash))
            {
                return HairAdapterCommitResult.Rejected(
                    HairAppearanceReasonCodes.InvalidPayload);
            }
            if (!_authority.TryValidate(
                    command.Binding,
                    command.ExpectedRevision,
                    command.ExpectedGeneration,
                    command.ExpectedCurrentHair,
                    out string preflightReason))
            {
                return HairAdapterCommitResult.Rejected(
                    NormalizeAuthorityReason(preflightReason));
            }

            JObject response;
            try
            {
                response = await _task.ExecuteAgentRequestAsync(
                        "commit",
                        new JObject
                        {
                            ["v"] = 1,
                            ["hairIdentifier"] =
                                command.HairIdentifier,
                            ["expectedCurrentHair"] =
                                command.ExpectedCurrentHair
                        })
                    .WaitAsync(cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (Exception)
            {
                // Once the bridge call begins, cancellation, disconnect, or
                // acknowledgement loss cannot prove that AS2 applied nothing.
                return HairAdapterCommitResult.Unknown(
                    HairAppearanceReasonCodes.UnknownWriteOutcome);
            }

            if (response == null
                || response.Value<bool?>("success") != true)
            {
                string taskError = response?.Value<string>("error");
                if (response?.Value<bool?>("requiresReconcile") == true
                    || IsUnknownTaskError(taskError))
                {
                    return HairAdapterCommitResult.Unknown(
                        HairAppearanceReasonCodes.UnknownWriteOutcome);
                }
                return HairAdapterCommitResult.Rejected(
                    NormalizeTaskReason(taskError));
            }
            if (response.Value<long?>("v") != 1
                || !string.Equals(
                    response.Value<string>("operation"),
                    "commit",
                    StringComparison.Ordinal)
                || !string.Equals(
                    response.Value<string>("currentHair"),
                    command.HairIdentifier,
                    StringComparison.Ordinal))
            {
                return HairAdapterCommitResult.Unknown(
                    HairAppearanceReasonCodes.UnknownWriteOutcome);
            }
            if (!_authority.TryApply(
                    command.Binding,
                    command.ExpectedRevision,
                    command.ExpectedGeneration,
                    command.ExpectedCurrentHair,
                    command.HairIdentifier,
                    out HairDomainAuthorityStamp appliedStamp,
                    out string applyReason))
            {
                return HairAdapterCommitResult.Unknown(
                    HairAppearanceReasonCodes.UnknownWriteOutcome);
            }

            SnapshotPayload after;
            try
            {
                after = await ReadSnapshotAsync(
                    cancellationToken).ConfigureAwait(false);
            }
            catch (Exception)
            {
                return HairAdapterCommitResult.Unknown(
                    HairAppearanceReasonCodes.UnknownWriteOutcome);
            }
            if (after == null
                || !string.Equals(
                    after.CurrentHair,
                    command.HairIdentifier,
                    StringComparison.Ordinal)
                || !_authority.TryObserve(
                    command.Binding,
                    after.CurrentHair,
                    out HairDomainAuthorityStamp confirmedStamp,
                    out string ignoredReason)
                || confirmedStamp.Revision != appliedStamp.Revision
                || confirmedStamp.Generation != appliedStamp.Generation)
            {
                return HairAdapterCommitResult.Unknown(
                    HairAppearanceReasonCodes.UnknownWriteOutcome);
            }
            return HairAdapterCommitResult.Applied(
                ToSnapshot(confirmedStamp, after.Catalog));
        }

        private async Task<SnapshotPayload> ReadSnapshotAsync(
            CancellationToken cancellationToken)
        {
            JObject response = await _task.ExecuteAgentRequestAsync(
                    "snapshot",
                    new JObject { ["v"] = 1 })
                .WaitAsync(cancellationToken)
                .ConfigureAwait(false);
            if (response == null
                || response.Value<bool?>("success") != true
                || response.Value<long?>("v") != 1)
            {
                return null;
            }

            string currentHair = response.Value<string>("currentHair");
            JArray sourceCatalog = response["catalog"] as JArray;
            if (!HairAppearanceValidation.IsSafeString(
                    currentHair,
                    160,
                    false)
                || sourceCatalog == null
                || sourceCatalog.Count == 0
                || sourceCatalog.Count > 1024)
            {
                return null;
            }

            var catalog = new List<HairCatalogEntry>(
                sourceCatalog.Count);
            bool currentFound = false;
            foreach (JToken token in sourceCatalog)
            {
                JObject row = token as JObject;
                string identifier = row?.Value<string>("identifier");
                string name = row?.Value<string>("name");
                if (row == null
                    || row.Count != 2
                    || row.Property("identifier") == null
                    || row.Property("name") == null
                    || !HairAppearanceValidation.IsSafeString(
                        identifier,
                        160,
                        false)
                    || !HairAppearanceValidation.IsSafeString(
                        name,
                        160,
                        false))
                {
                    return null;
                }
                catalog.Add(new HairCatalogEntry(identifier, name));
                if (string.Equals(
                    identifier,
                    currentHair,
                    StringComparison.Ordinal))
                {
                    currentFound = true;
                }
            }
            return currentFound
                ? new SnapshotPayload(currentHair, catalog)
                : null;
        }

        private static HairAuthoritativeSnapshot ToSnapshot(
            HairDomainAuthorityStamp stamp,
            IReadOnlyList<HairCatalogEntry> catalog)
        {
            return new HairAuthoritativeSnapshot(
                stamp.Binding,
                stamp.Revision,
                stamp.Generation,
                stamp.CurrentHair,
                catalog);
        }

        private static bool IsUnknownTaskError(string reason)
        {
            return string.Equals(reason, "timeout", StringComparison.Ordinal)
                || string.Equals(
                    reason,
                    "disconnected",
                    StringComparison.Ordinal)
                || string.Equals(
                    reason,
                    "malformed_response",
                    StringComparison.Ordinal)
                || string.Equals(
                    reason,
                    "reconcile_required",
                    StringComparison.Ordinal)
                || string.Equals(reason, "busy", StringComparison.Ordinal);
        }

        private static string NormalizeTaskReason(string reason)
        {
            switch (reason)
            {
                case "stale_state":
                    return HairAppearanceReasonCodes.StaleState;
                case "hair_not_found":
                    return HairAppearanceReasonCodes.HairNotFound;
                case "invalid_payload":
                case "unsupported_version":
                case "unsupported_cmd":
                    return HairAppearanceReasonCodes.InvalidPayload;
                default:
                    return HairAppearanceReasonCodes.AdapterUnavailable;
            }
        }

        private static string NormalizeAuthorityReason(string reason)
        {
            switch (reason)
            {
                case HairAppearanceReasonCodes.CrossSave:
                    return HairAppearanceReasonCodes.CrossSave;
                case HairAppearanceReasonCodes.StaleRevision:
                    return HairAppearanceReasonCodes.StaleRevision;
                case HairAppearanceReasonCodes.StaleState:
                    return HairAppearanceReasonCodes.StaleState;
                default:
                    return HairAppearanceReasonCodes.AdapterUnavailable;
            }
        }

        private sealed class SnapshotPayload
        {
            public SnapshotPayload(
                string currentHair,
                IReadOnlyList<HairCatalogEntry> catalog)
            {
                CurrentHair = currentHair;
                Catalog = catalog;
            }

            public string CurrentHair { get; }
            public IReadOnlyList<HairCatalogEntry> Catalog { get; }
        }
    }
}
