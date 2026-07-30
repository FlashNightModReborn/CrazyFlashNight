using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal sealed class ScopedAgentRuntimeTraceExporter
    {
        internal const int MaximumArtifactBytes =
            8 * 1024 * 1024;

        private const string PendingMarkerToken =
            ".jsonl.pending";
        private static readonly ConcurrentDictionary<string, byte>
            ActivePendingMarkers =
                new ConcurrentDictionary<string, byte>(
                    StringComparer.OrdinalIgnoreCase);

        private readonly ScopedAgentRuntimeAuditLedgerManager
            _ledger;
        private readonly ObservationGrantBroker _grants;
        private readonly SessionSurfaceHostController
            _sessions;
        private readonly string _directory;
        private readonly IAgentRendezvousFileProtection
            _protection;
        private readonly int _processId;
        private readonly DateTimeOffset _processStartTimeUtc;
        private readonly Func<string> _artifactIdFactory;

        public ScopedAgentRuntimeTraceExporter(
            ScopedAgentRuntimeAuditLedgerManager ledger,
            ObservationGrantBroker grants,
            SessionSurfaceHostController sessions,
            string directory,
            IAgentRendezvousFileProtection protection,
            Func<string> artifactIdFactory = null)
        {
            _ledger = ledger
                ?? throw new ArgumentNullException(
                    nameof(ledger));
            _grants = grants
                ?? throw new ArgumentNullException(
                    nameof(grants));
            _sessions = sessions
                ?? throw new ArgumentNullException(
                    nameof(sessions));
            if (string.IsNullOrWhiteSpace(directory))
            {
                throw new ArgumentException(
                    "A Runtime-owned export directory is required.",
                    nameof(directory));
            }
            _directory = Path.GetFullPath(directory);
            _protection = protection
                ?? new WindowsCurrentUserRendezvousFileProtection();
            using Process process = Process.GetCurrentProcess();
            _processId = process.Id;
            _processStartTimeUtc =
                new DateTimeOffset(
                    process.StartTime.ToUniversalTime());
            _artifactIdFactory =
                artifactIdFactory
                ?? (() => OpaqueIdGenerator.Create("trace"));
        }

        public AgentRuntimeDispatchResult Export(
            AgentRuntimeDispatchContext context,
            TraceExportParametersV1 parameters,
            CancellationToken cancellationToken)
        {
            RecoverAbandonedArtifacts();
            if (!TryAuthorize(
                    context,
                    parameters,
                    out SessionSnapshot session,
                    out ObservationGrant grant,
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    reasonCode);
            }
            if (cancellationToken.IsCancellationRequested)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "deadline_exceeded");
            }

            long fromSequence =
                checked((long)
                    parameters.FromServerSequence);
            if (!_ledger.TrySnapshotExport(
                    context.Principal,
                    session.SessionId,
                    session.LifecycleGeneration,
                    parameters.ConsentPurpose,
                    fromSequence,
                    parameters.MaximumRecords,
                    out _,
                    out reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    NormalizeAuditReason(reasonCode));
            }

            string artifactId;
            try
            {
                artifactId =
                    _artifactIdFactory();
            }
            catch
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            if (!TryResolveArtifactPaths(
                    artifactId,
                    out string fileName,
                    out string finalPath,
                    out string temporaryPath,
                    out string pendingMarkerPath,
                    out string stagingMarkerPath))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            if (!TryAppendExportFact(
                    context,
                    session,
                    parameters,
                    grant,
                    AgentRuntimeAuditEventTypes
                        .TraceExportAuthorized,
                    artifactId,
                    null,
                    null,
                    out _))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            if (!_ledger.TrySnapshotExport(
                    context.Principal,
                    session.SessionId,
                    session.LifecycleGeneration,
                    parameters.ConsentPurpose,
                    fromSequence,
                    parameters.MaximumRecords,
                    out ScopedAuditExportSnapshot snapshot,
                    out reasonCode))
            {
                TryRecordFailed(
                    context,
                    session,
                    parameters,
                    grant,
                    artifactId,
                    reasonCode);
                return AgentRuntimeDispatchResult.Rejected(
                    NormalizeAuditReason(reasonCode));
            }

            byte[] payload = null;
            bool directoryCreated = false;
            bool pendingMarkerRegistered = false;
            bool stagingMarkerOwned = false;
            bool pendingMarkerOwned = false;
            bool temporaryOwned = false;
            bool finalOwned = false;
            try
            {
                payload = SerializeBounded(
                    artifactId,
                    snapshot,
                    out int recordCount,
                    out long firstSequence,
                    out long lastSequence,
                    out string exportedFinalHash,
                    out bool hasMore);
                cancellationToken
                    .ThrowIfCancellationRequested();
                RequireAuthorityStillExact(
                    context,
                    parameters,
                    session,
                    grant);

                directoryCreated =
                    !Directory.Exists(_directory);
                Directory.CreateDirectory(_directory);
                _protection.ProtectDirectory(_directory);
                if (File.Exists(temporaryPath)
                    || File.Exists(finalPath)
                    || !ActivePendingMarkers.TryAdd(
                        pendingMarkerPath,
                        0))
                {
                    throw new IOException(
                        "trace_export_name_collision");
                }
                pendingMarkerRegistered = true;
                byte[] markerPayload =
                    Encoding.UTF8.GetBytes(
                        _processId
                        + "."
                        + _processStartTimeUtc
                            .UtcDateTime
                            .Ticks);
                using (var marker = new FileStream(
                    stagingMarkerPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    128,
                    FileOptions.WriteThrough))
                {
                    stagingMarkerOwned = true;
                    marker.Write(
                        markerPayload,
                        0,
                        markerPayload.Length);
                    marker.Flush(flushToDisk: true);
                }
                _protection.ProtectFile(
                    stagingMarkerPath);
                File.Move(
                    stagingMarkerPath,
                    pendingMarkerPath);
                stagingMarkerOwned = false;
                pendingMarkerOwned = true;
                _protection.ProtectFile(
                    pendingMarkerPath);
                cancellationToken
                    .ThrowIfCancellationRequested();
                RequireAuthorityStillExact(
                    context,
                    parameters,
                    session,
                    grant);
                using (var stream = new FileStream(
                    temporaryPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    64 * 1024,
                    FileOptions.WriteThrough))
                {
                    temporaryOwned = true;
                    stream.Write(payload, 0, payload.Length);
                    stream.Flush(flushToDisk: true);
                }
                _protection.ProtectFile(temporaryPath);
                cancellationToken
                    .ThrowIfCancellationRequested();
                File.Move(temporaryPath, finalPath);
                temporaryOwned = false;
                finalOwned = true;
                _protection.ProtectFile(finalPath);
                cancellationToken
                    .ThrowIfCancellationRequested();
                RequireAuthorityStillExact(
                    context,
                    parameters,
                    session,
                    grant);

                if (!TryAppendExportFact(
                        context,
                        session,
                        parameters,
                        grant,
                        AgentRuntimeAuditEventTypes
                            .TraceExportCompleted,
                        artifactId,
                        lastSequence,
                        null,
                        out AgentRuntimeAuditCommit commit))
                {
                    throw new InvalidOperationException(
                        "audit_append_failed");
                }
                RequireAuthorityStillExact(
                    context,
                    parameters,
                    session,
                    grant);
                AgentRuntimeDispatchResult completed =
                    AgentRuntimeDispatchResult.Completed(
                    new TraceExportResultV1
                    {
                        ArtifactId = artifactId,
                        ArtifactName = fileName,
                        ScopeId = snapshot.ScopeId,
                        ConsentPurpose =
                            parameters.ConsentPurpose,
                        RecordCount = recordCount,
                        FirstAuditSequence =
                            checked((ulong)
                                Math.Max(
                                    0,
                                    firstSequence)),
                        LastAuditSequence =
                            checked((ulong)
                                Math.Max(
                                    0,
                                    lastSequence)),
                        FinalEntryHash =
                            exportedFinalHash,
                        HasMore = hasMore,
                        ExportAuditSequence =
                            checked((ulong)
                                commit.AuditSequence)
                    });
                if (!TryDeleteFile(pendingMarkerPath))
                {
                    throw new IOException(
                        "trace_export_publication_marker_cleanup_failed");
                }
                pendingMarkerOwned = false;
                return completed;
            }
            catch (OperationCanceledException)
            {
                bool cleanupComplete = DeleteArtifact(
                    temporaryPath,
                    finalPath,
                    pendingMarkerPath,
                    stagingMarkerPath,
                    temporaryOwned,
                    finalOwned,
                    pendingMarkerOwned,
                    stagingMarkerOwned,
                    directoryCreated);
                TryRecordFailed(
                    context,
                    session,
                    parameters,
                    grant,
                    artifactId,
                    cleanupComplete
                        ? "deadline_exceeded"
                        : "trace_export_cleanup_pending");
                return AgentRuntimeDispatchResult.Rejected(
                    "deadline_exceeded");
            }
            catch
            {
                bool cleanupComplete = DeleteArtifact(
                    temporaryPath,
                    finalPath,
                    pendingMarkerPath,
                    stagingMarkerPath,
                    temporaryOwned,
                    finalOwned,
                    pendingMarkerOwned,
                    stagingMarkerOwned,
                    directoryCreated);
                TryRecordFailed(
                    context,
                    session,
                    parameters,
                    grant,
                    artifactId,
                    cleanupComplete
                        ? "trace_export_failed"
                        : "trace_export_cleanup_pending");
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            finally
            {
                if (pendingMarkerRegistered)
                {
                    ActivePendingMarkers.TryRemove(
                        pendingMarkerPath,
                        out _);
                }
                if (payload != null)
                    Array.Clear(payload, 0, payload.Length);
            }
        }

        private bool TryAuthorize(
            AgentRuntimeDispatchContext context,
            TraceExportParametersV1 parameters,
            out SessionSnapshot session,
            out ObservationGrant grant,
            out string reasonCode)
        {
            session = null;
            grant = null;
            if (context?.Principal == null
                || parameters == null
                || context.Principal.State
                    != CredentialState.Active
                || context.Principal.PrincipalKind
                    != AgentPrincipalKind.DeveloperAgent
                || context.Principal.SessionMode
                    != AgentSessionMode
                        .DeveloperInteractive
                || !context.Principal.AllowsCapability(
                    AgentCapabilitiesV1.TraceExport)
                || !context.Principal.AllowsCapability(
                    "observation.export"))
            {
                reasonCode = "capability_denied";
                return false;
            }
            if (!TraceExportConsentPurposesV1.All
                    .Contains(parameters.ConsentPurpose)
                || !context.Principal.AllowsCapability(
                    parameters.ConsentPurpose))
            {
                reasonCode = "capability_denied";
                return false;
            }
            session = _sessions.Snapshot;
            if (!string.Equals(
                    session.SessionId,
                    parameters.SessionId,
                    StringComparison.Ordinal))
            {
                reasonCode = "session_scope_mismatch";
                return false;
            }
            if (!_grants.TryAuthorizeSession(
                    parameters.ObservationGrantId,
                    context.Principal.ClientInstanceId,
                    context.Principal.SecurityPrincipalId,
                    parameters.SessionId,
                    ObservationDataScopesV1.DataExport,
                    out grant,
                    out reasonCode)
                || !grant.AllowExport
                || string.IsNullOrWhiteSpace(
                    grant.ConsentReceipt))
            {
                reasonCode =
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode
                            ?? "export_grant_required");
                return false;
            }
            reasonCode = null;
            return true;
        }

        private void RequireAuthorityStillExact(
            AgentRuntimeDispatchContext context,
            TraceExportParametersV1 parameters,
            SessionSnapshot expectedSession,
            ObservationGrant expectedGrant)
        {
            if (!TryAuthorize(
                    context,
                    parameters,
                    out SessionSnapshot currentSession,
                    out ObservationGrant currentGrant,
                    out _)
                || currentSession.LifecycleGeneration
                    != expectedSession.LifecycleGeneration
                || !ReferenceEquals(
                    currentGrant,
                    expectedGrant))
            {
                throw new InvalidOperationException(
                    "trace_export_authority_revoked");
            }
        }

        private bool TryAppendExportFact(
            AgentRuntimeDispatchContext context,
            SessionSnapshot session,
            TraceExportParametersV1 parameters,
            ObservationGrant grant,
            string eventType,
            string artifactId,
            long? exportedThroughSequence,
            string reasonCode,
            out AgentRuntimeAuditCommit commit)
        {
            return _ledger.TryAppendTrustedFact(
                new AgentRuntimeTrustedAuditFact
                {
                    Principal = context.Principal,
                    ConnectionId =
                        context.ConnectionId,
                    SessionId = session.SessionId,
                    LifecycleGeneration =
                        session.LifecycleGeneration,
                    ConsentPurpose =
                        parameters.ConsentPurpose,
                    EventType = eventType,
                    CorrelationId = artifactId,
                    ObservationGrantId =
                        grant.ObservationGrantId,
                    DataScope =
                        new[]
                        {
                            ObservationDataScopesV1
                                .DataExport
                        },
                    AllowExport = true,
                    State = grant.State.ToString(),
                    ConsentReceipt =
                        grant.ConsentReceipt,
                    ArtifactId = artifactId,
                    ExportedThroughAuditSequence =
                        exportedThroughSequence,
                    ReasonCode = reasonCode
                },
                out commit,
                out _);
        }

        private void TryRecordFailed(
            AgentRuntimeDispatchContext context,
            SessionSnapshot session,
            TraceExportParametersV1 parameters,
            ObservationGrant grant,
            string artifactId,
            string reasonCode)
        {
            TryAppendExportFact(
                context,
                session,
                parameters,
                grant,
                AgentRuntimeAuditEventTypes
                    .TraceExportFailed,
                artifactId,
                null,
                reasonCode,
                out _);
        }

        private static byte[] SerializeBounded(
            string artifactId,
            ScopedAuditExportSnapshot snapshot,
            out int recordCount,
            out long firstSequence,
            out long lastSequence,
            out string finalEntryHash,
            out bool hasMore)
        {
            var lines = new List<byte[]>();
            int bytes = 0;
            AddLine(
                lines,
                ref bytes,
                new
                {
                    recordType = "trace_header",
                    schemaVersion =
                        "cf7.agent.trace.v1",
                    artifactId,
                    scopeId = snapshot.ScopeId,
                    scope = snapshot.Scope,
                    credentialGeneration =
                        snapshot.CredentialGeneration,
                    lifecycleGeneration =
                        snapshot.LifecycleGeneration,
                    previousEntryHash =
                        snapshot.PreviousEntryHash
                },
                reserveReceiptBytes: 4096);

            var selected =
                new List<ScopedAuditExportRecord>();
            foreach (ScopedAuditExportRecord record
                in snapshot.Records)
            {
                byte[] line = JsonLine(
                    new
                    {
                        recordType = "audit_entry",
                        auditSequence =
                            record.AuditSequence,
                        segmentOrdinal =
                            record.SegmentOrdinal,
                        entry = record.Entry
                    });
                if (bytes + line.Length + 4096
                    > MaximumArtifactBytes)
                {
                    break;
                }
                lines.Add(line);
                bytes += line.Length;
                selected.Add(record);
            }
            recordCount = selected.Count;
            firstSequence =
                selected.Count == 0
                    ? snapshot.FirstAuditSequence
                    : selected[0].AuditSequence;
            lastSequence =
                selected.Count == 0
                    ? snapshot.FirstAuditSequence - 1
                    : selected[^1].AuditSequence;
            finalEntryHash =
                selected.Count == 0
                    ? AppendOnlyAuditSegment.GenesisHash
                    : selected[^1].Entry.EntryHash;
            hasMore = snapshot.HasMore
                || selected.Count < snapshot.Records.Count;
            AddLine(
                lines,
                ref bytes,
                new
                {
                    recordType = "trace_receipt",
                    artifactId,
                    recordCount,
                    firstAuditSequence =
                        firstSequence,
                    lastAuditSequence =
                        lastSequence,
                    finalEntryHash,
                    previousEntryHash =
                        snapshot.PreviousEntryHash,
                    sourceSnapshotFinalEntryHash =
                        snapshot.FinalEntryHash,
                    hasMore
                },
                reserveReceiptBytes: 0);
            if (bytes > MaximumArtifactBytes)
            {
                throw new InvalidOperationException(
                    "trace_export_too_large");
            }

            byte[] result = new byte[bytes];
            int offset = 0;
            foreach (byte[] line in lines)
            {
                Buffer.BlockCopy(
                    line,
                    0,
                    result,
                    offset,
                    line.Length);
                offset += line.Length;
            }
            return result;
        }

        private static void AddLine(
            ICollection<byte[]> lines,
            ref int bytes,
            object value,
            int reserveReceiptBytes)
        {
            byte[] line = JsonLine(value);
            if (bytes + line.Length + reserveReceiptBytes
                > MaximumArtifactBytes)
            {
                throw new InvalidOperationException(
                    "trace_export_too_large");
            }
            lines.Add(line);
            bytes += line.Length;
        }

        private static byte[] JsonLine(object value)
        {
            byte[] json =
                JsonSerializer.SerializeToUtf8Bytes(
                    value,
                    AgentProtocolV1.JsonOptions);
            byte[] line = new byte[json.Length + 1];
            Buffer.BlockCopy(
                json,
                0,
                line,
                0,
                json.Length);
            line[^1] = (byte)'\n';
            return line;
        }

        private bool DeleteArtifact(
            string temporaryPath,
            string finalPath,
            string pendingMarkerPath,
            string stagingMarkerPath,
            bool temporaryOwned,
            bool finalOwned,
            bool pendingMarkerOwned,
            bool stagingMarkerOwned,
            bool directoryCreated)
        {
            bool cleanupComplete = true;
            if (temporaryOwned)
            {
                cleanupComplete &=
                    TryDeleteFile(temporaryPath);
            }
            if (finalOwned)
            {
                cleanupComplete &=
                    TryDeleteFile(finalPath);
            }
            if (pendingMarkerOwned
                && cleanupComplete)
            {
                cleanupComplete &=
                    TryDeleteFile(pendingMarkerPath);
            }
            if (stagingMarkerOwned)
            {
                cleanupComplete &=
                    TryDeleteFile(stagingMarkerPath);
            }
            if (!directoryCreated)
                return cleanupComplete;
            try
            {
                if (Directory.Exists(
                        Path.GetDirectoryName(finalPath))
                    && !Directory.EnumerateFileSystemEntries(
                            Path.GetDirectoryName(finalPath))
                        .Any())
                {
                    Directory.Delete(
                        Path.GetDirectoryName(finalPath));
                }
            }
            catch
            {
            }
            return cleanupComplete;
        }

        private static bool TryDeleteFile(string path)
        {
            try
            {
                if (File.Exists(path))
                    File.Delete(path);
                return !File.Exists(path);
            }
            catch
            {
                return false;
            }
        }

        private bool TryResolveArtifactPaths(
            string artifactId,
            out string fileName,
            out string finalPath,
            out string temporaryPath,
            out string pendingMarkerPath,
            out string stagingMarkerPath)
        {
            fileName = null;
            finalPath = null;
            temporaryPath = null;
            pendingMarkerPath = null;
            stagingMarkerPath = null;
            if (!IsSafeArtifactId(artifactId))
                return false;
            try
            {
                fileName = artifactId + ".jsonl";
                finalPath = Path.GetFullPath(
                    Path.Combine(
                        _directory,
                        fileName));
                if (!string.Equals(
                        Path.GetDirectoryName(finalPath),
                        _directory,
                        StringComparison.OrdinalIgnoreCase)
                    || !string.Equals(
                        Path.GetFileName(finalPath),
                        fileName,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                temporaryPath = finalPath + ".tmp";
                pendingMarkerPath =
                    finalPath + ".pending";
                stagingMarkerPath =
                    StagingMarkerPath(
                        pendingMarkerPath);
                return true;
            }
            catch
            {
                fileName = null;
                finalPath = null;
                temporaryPath = null;
                pendingMarkerPath = null;
                stagingMarkerPath = null;
                return false;
            }
        }

        private string StagingMarkerPath(
            string pendingMarkerPath)
        {
            return pendingMarkerPath
                + "."
                + _processId
                + "."
                + _processStartTimeUtc
                    .UtcDateTime
                    .Ticks
                + ".tmp";
        }

        private void RecoverAbandonedArtifacts()
        {
            if (!Directory.Exists(_directory))
                return;
            string[] markers;
            try
            {
                markers = Directory.GetFiles(
                    _directory,
                    "trace_*.jsonl.pending",
                    SearchOption.TopDirectoryOnly);
            }
            catch
            {
                return;
            }
            foreach (string markerPath in markers)
            {
                try
                {
                    string fullMarkerPath =
                        Path.GetFullPath(markerPath);
                    if (ActivePendingMarkers.ContainsKey(
                            fullMarkerPath)
                        || !TryParsePendingMarker(
                            fullMarkerPath,
                            out string abandonedFinalPath,
                            out string abandonedTemporaryPath,
                            out int ownerProcessId,
                            out DateTimeOffset
                                ownerStartTimeUtc))
                    {
                        continue;
                    }
                    bool sameProcessIncarnation =
                        ownerProcessId == _processId
                        && ownerStartTimeUtc.UtcDateTime.Ticks
                            == _processStartTimeUtc
                                .UtcDateTime
                                .Ticks;
                    if (!sameProcessIncarnation
                        && !IsExactProcessDefinitelyDead(
                            ownerProcessId,
                            ownerStartTimeUtc))
                    {
                        continue;
                    }
                    bool payloadRemoved =
                        TryDeleteFile(
                            abandonedTemporaryPath);
                    payloadRemoved &=
                        TryDeleteFile(
                            abandonedFinalPath);
                    if (payloadRemoved)
                        TryDeleteFile(fullMarkerPath);
                }
                catch
                {
                }
            }
            RecoverAbandonedStagingMarkers();
            RecoverLegacyTemporaryFiles();
        }

        private bool TryParsePendingMarker(
            string markerPath,
            out string finalPath,
            out string temporaryPath,
            out int ownerProcessId,
            out DateTimeOffset ownerStartTimeUtc)
        {
            finalPath = null;
            temporaryPath = null;
            ownerProcessId = 0;
            ownerStartTimeUtc = default;
            string fileName = Path.GetFileName(markerPath);
            if (!fileName.EndsWith(
                    PendingMarkerToken,
                    StringComparison.Ordinal))
                return false;
            string artifactName =
                fileName.Substring(
                    0,
                    fileName.Length
                        - ".pending".Length);
            string artifactId =
                artifactName.Substring(
                    0,
                    artifactName.Length
                        - ".jsonl".Length);
            if (!IsSafeArtifactId(artifactId))
            {
                return false;
            }
            string owner;
            try
            {
                var markerInfo =
                    new FileInfo(markerPath);
                if (markerInfo.Length <= 0
                    || markerInfo.Length > 128)
                {
                    return false;
                }
                owner = File.ReadAllText(
                    markerPath,
                    Encoding.UTF8);
            }
            catch
            {
                return false;
            }
            if (!TryParseOwner(
                    owner,
                    out ownerProcessId,
                    out ownerStartTimeUtc))
            {
                return false;
            }
            finalPath =
                Path.Combine(_directory, artifactName);
            temporaryPath = finalPath + ".tmp";
            return true;
        }

        private void RecoverLegacyTemporaryFiles()
        {
            string[] temporaryFiles;
            try
            {
                temporaryFiles = Directory.GetFiles(
                    _directory,
                    "trace_*.jsonl.tmp",
                    SearchOption.TopDirectoryOnly);
            }
            catch
            {
                return;
            }
            foreach (string temporaryPath
                in temporaryFiles)
            {
                try
                {
                    string fileName =
                        Path.GetFileName(temporaryPath);
                    if (!fileName.EndsWith(
                            ".jsonl.tmp",
                            StringComparison.Ordinal))
                    {
                        continue;
                    }
                    string artifactName =
                        fileName.Substring(
                            0,
                            fileName.Length
                                - ".tmp".Length);
                    string artifactId =
                        artifactName.Substring(
                            0,
                            artifactName.Length
                                - ".jsonl".Length);
                    string pendingMarkerPath =
                        Path.Combine(
                            _directory,
                            artifactName
                                + ".pending");
                    if (!IsSafeArtifactId(
                            artifactId)
                        || File.Exists(
                            pendingMarkerPath))
                    {
                        continue;
                    }
                    using (new FileStream(
                        temporaryPath,
                        FileMode.Open,
                        FileAccess.ReadWrite,
                        FileShare.None))
                    {
                    }
                    TryDeleteFile(temporaryPath);
                }
                catch
                {
                }
            }
        }

        private static bool IsSafeArtifactId(
            string artifactId)
        {
            return artifactId != null
                && artifactId.StartsWith(
                    "trace_",
                    StringComparison.Ordinal)
                && artifactId.Length
                    == "trace_".Length + 24
                && !artifactId
                    .Skip("trace_".Length)
                    .Any(character =>
                        !(character >= 'a'
                            && character <= 'z')
                        && !(character >= 'A'
                            && character <= 'Z')
                        && !(character >= '0'
                            && character <= '9')
                        && character != '-'
                        && character != '_');
        }

        private void RecoverAbandonedStagingMarkers()
        {
            string[] stagingMarkers;
            try
            {
                stagingMarkers = Directory.GetFiles(
                    _directory,
                    "trace_*.jsonl.pending.*.*.tmp",
                    SearchOption.TopDirectoryOnly);
            }
            catch
            {
                return;
            }
            foreach (string stagingMarkerPath
                in stagingMarkers)
            {
                try
                {
                    string fileName =
                        Path.GetFileName(
                            stagingMarkerPath);
                    string prefix =
                        PendingMarkerToken + ".";
                    int ownerIndex =
                        fileName.IndexOf(
                            prefix,
                            StringComparison.Ordinal);
                    if (ownerIndex <= 0
                        || !fileName.EndsWith(
                            ".tmp",
                            StringComparison.Ordinal))
                    {
                        continue;
                    }
                    string owner =
                        fileName.Substring(
                            ownerIndex
                                + prefix.Length,
                            fileName.Length
                                - ownerIndex
                                - prefix.Length
                                - ".tmp".Length);
                    if (!TryParseOwner(
                            owner,
                            out int ownerProcessId,
                            out DateTimeOffset
                                ownerStartTimeUtc))
                    {
                        continue;
                    }
                    string pendingMarkerPath =
                        Path.Combine(
                            _directory,
                            fileName.Substring(
                                0,
                                ownerIndex
                                    + PendingMarkerToken
                                        .Length));
                    if (ActivePendingMarkers
                            .ContainsKey(
                                pendingMarkerPath))
                    {
                        continue;
                    }
                    bool sameProcessIncarnation =
                        ownerProcessId == _processId
                        && ownerStartTimeUtc
                            .UtcDateTime
                            .Ticks
                            == _processStartTimeUtc
                                .UtcDateTime
                                .Ticks;
                    if (!sameProcessIncarnation
                        && !IsExactProcessDefinitelyDead(
                            ownerProcessId,
                            ownerStartTimeUtc))
                    {
                        continue;
                    }
                    TryDeleteFile(stagingMarkerPath);
                }
                catch
                {
                }
            }
        }

        private static bool TryParseOwner(
            string owner,
            out int ownerProcessId,
            out DateTimeOffset ownerStartTimeUtc)
        {
            ownerProcessId = 0;
            ownerStartTimeUtc = default;
            string[] ownerParts =
                (owner ?? string.Empty).Split('.');
            if (ownerParts.Length != 2
                || !int.TryParse(
                    ownerParts[0],
                    out ownerProcessId)
                || ownerProcessId <= 0
                || !long.TryParse(
                    ownerParts[1],
                    out long startTicks)
                || startTicks
                    < DateTimeOffset.MinValue
                        .UtcDateTime
                        .Ticks
                || startTicks
                    > DateTimeOffset.MaxValue
                        .UtcDateTime
                        .Ticks)
            {
                return false;
            }
            ownerStartTimeUtc =
                new DateTimeOffset(
                    startTicks,
                    TimeSpan.Zero);
            return true;
        }

        private static bool IsExactProcessDefinitelyDead(
            int processId,
            DateTimeOffset expectedStartTimeUtc)
        {
            Process process;
            try
            {
                process =
                    Process.GetProcessById(processId);
            }
            catch (ArgumentException)
            {
                return true;
            }
            catch
            {
                return false;
            }
            using (process)
            {
                try
                {
                    if (process.HasExited)
                        return true;
                    DateTimeOffset actualStartTimeUtc =
                        new DateTimeOffset(
                            process.StartTime
                                .ToUniversalTime());
                    return actualStartTimeUtc
                            .UtcDateTime
                            .Ticks
                        != expectedStartTimeUtc
                            .UtcDateTime
                            .Ticks;
                }
                catch
                {
                    return false;
                }
            }
        }

        private static string NormalizeAuditReason(
            string reasonCode)
        {
            return reasonCode switch
            {
                "arguments_invalid" =>
                    "arguments_invalid",
                "audit_sequence_invalid" =>
                    "arguments_invalid",
                "audit_scope_incomplete" =>
                    "unsupported_for_surface",
                _ => "internal_error"
            };
        }
    }

    internal sealed class TraceExportResultV1
    {
        public string ArtifactId { get; init; }
        public string ArtifactName { get; init; }
        public string ScopeId { get; init; }
        public string ConsentPurpose { get; init; }
        public int RecordCount { get; init; }
        public ulong FirstAuditSequence { get; init; }
        public ulong LastAuditSequence { get; init; }
        public string FinalEntryHash { get; init; }
        public bool HasMore { get; init; }
        public ulong ExportAuditSequence { get; init; }
    }
}
