using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Observation
{
    internal sealed record PixelContentAuditEvent(
        string EventType,
        string Handle,
        string SecurityPrincipalId,
        string SessionId,
        string ObservationGrantId,
        string ObservationId,
        long Offset,
        int RequestedBytes,
        int ReturnedBytes,
        bool Final,
        bool Accepted,
        string ReasonCode,
        long RecordedMonotonic,
        DateTimeOffset RecordedUtc);

    internal interface IPixelContentAuditSink
    {
        void Record(PixelContentAuditEvent auditEvent);
    }

    internal sealed class AppendOnlyPixelContentAuditSink
        : IPixelContentAuditSink
    {
        private readonly AppendOnlyAuditSegment _segment;

        public AppendOnlyPixelContentAuditSink(
            AppendOnlyAuditSegment segment)
        {
            _segment = segment
                ?? throw new ArgumentNullException(nameof(segment));
        }

        public void Record(PixelContentAuditEvent auditEvent)
        {
            if (auditEvent == null)
                throw new ArgumentNullException(nameof(auditEvent));
            string serialized = JsonSerializer.Serialize(
                auditEvent,
                AgentProtocolV1.JsonOptions);
            _segment.Append(
                auditEvent.EventType,
                CanonicalJsonV1.Canonicalize(serialized));
        }
    }

    internal sealed class PixelContentBinding
    {
        public string ClientInstanceId { get; init; }
        public string SecurityPrincipalId { get; init; }
        public string SessionId { get; init; }
        public string ObservationGrantId { get; init; }
        public string ObservationId { get; init; }
        public string TargetId { get; init; }
        public string DataScope { get; init; } =
            ObservationDataScopesV1.Pixels;
    }

    internal sealed record PixelContentHandleDescriptor(
        string Handle,
        int TotalBytes,
        string ContentHash,
        long ExpiresMonotonic);

    internal sealed class PixelContentReadRequest
    {
        public string Handle { get; init; }
        public string ClientInstanceId { get; init; }
        public string SecurityPrincipalId { get; init; }
        public string SessionId { get; init; }
        public string ObservationGrantId { get; init; }
        public string ObservationId { get; init; }
        public long Offset { get; init; }
        public int MaximumBytes { get; init; }
    }

    internal sealed class PixelContentReadOutcome
    {
        private PixelContentReadOutcome(
            byte[] content,
            long offset,
            bool final,
            string contentHash,
            int totalBytes,
            string reasonCode)
        {
            Content = content;
            Offset = offset;
            Final = final;
            ContentHash = contentHash;
            TotalBytes = totalBytes;
            ReasonCode = reasonCode;
        }

        public bool Success
        {
            get { return Content != null; }
        }

        public byte[] Content { get; }
        public long Offset { get; }
        public bool Final { get; }
        public string ContentHash { get; }
        public int TotalBytes { get; }
        public string ReasonCode { get; }

        public static PixelContentReadOutcome Read(
            byte[] content,
            long offset,
            bool final,
            string contentHash,
            int totalBytes)
        {
            return new PixelContentReadOutcome(
                content
                    ?? throw new ArgumentNullException(nameof(content)),
                offset,
                final,
                contentHash,
                totalBytes,
                null);
        }

        public static PixelContentReadOutcome Rejected(
            string reasonCode)
        {
            return new PixelContentReadOutcome(
                null,
                0,
                false,
                null,
                0,
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "content_handle_rejected"
                    : reasonCode);
        }
    }

    /// <summary>
    /// In-memory, sequential, one-shot pixel object store. It has no file,
    /// data-URL, persistence, or export API.
    /// </summary>
    internal sealed class PixelContentHandleStore : IDisposable
    {
        internal const int MaximumResidentBytes =
            AgentProtocolV1.MaximumBinaryObjectBytes * 4;

        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly ObservationGrantBroker _grants;
        private readonly IPixelContentAuditSink _audit;
        private readonly Dictionary<string, Entry> _entries =
            new Dictionary<string, Entry>(StringComparer.Ordinal);
        private int _residentBytes;
        private bool _disposed;

        public PixelContentHandleStore(
            IAgentRuntimeClock clock,
            ObservationGrantBroker grants,
            IPixelContentAuditSink audit)
        {
            _clock = clock ?? throw new ArgumentNullException(nameof(clock));
            _grants = grants
                ?? throw new ArgumentNullException(nameof(grants));
            _audit = audit ?? throw new ArgumentNullException(nameof(audit));
        }

        public bool TryCreate(
            PixelContentBinding binding,
            byte[] content,
            out PixelContentHandleDescriptor descriptor,
            out string reasonCode)
        {
            descriptor = null;
            reasonCode = ValidateBinding(binding);
            if (reasonCode == null && content == null)
                reasonCode = "capture_unavailable";
            if (reasonCode == null
                && content.Length > AgentProtocolV1.MaximumBinaryObjectBytes)
            {
                reasonCode = "capture_object_too_large";
            }
            if (reasonCode == null
                && !_grants.TryAuthorize(
                    binding.ObservationGrantId,
                    binding.ClientInstanceId,
                    binding.SecurityPrincipalId,
                    binding.SessionId,
                    binding.TargetId,
                    binding.DataScope,
                    out _,
                    out reasonCode))
            {
                reasonCode ??= "observation_grant_inactive";
            }

            lock (_sync)
            {
                ThrowIfDisposed();
                PurgeExpiredLocked();
                if (reasonCode == null
                    && content.Length
                        > MaximumResidentBytes - _residentBytes)
                {
                    reasonCode = "capture_backpressure";
                }
                if (reasonCode != null)
                {
                    try
                    {
                        AuditLocked(
                            "pixel_handle_open",
                            null,
                            binding,
                            0,
                            content?.Length ?? 0,
                            0,
                            false,
                            false,
                            reasonCode);
                    }
                    catch
                    {
                        reasonCode = "audit_unavailable";
                    }
                    return false;
                }

                string handle = OpaqueIdGenerator.Create("pixel");
                byte[] owned = content.ToArray();
                string hash = Convert.ToHexString(
                    SHA256.HashData(owned));
                long expires = checked(
                    _clock.MonotonicMilliseconds
                    + AgentProtocolV1.MaximumContentHandleTtlMs);
                var entry = new Entry(
                    handle,
                    CloneBinding(binding),
                    owned,
                    hash,
                    expires);
                try
                {
                    AuditLocked(
                        "pixel_handle_open",
                        handle,
                        binding,
                        0,
                        owned.Length,
                        0,
                        false,
                        true,
                        null);
                    _entries.Add(handle, entry);
                    _residentBytes = checked(
                        _residentBytes + owned.Length);
                    descriptor = new PixelContentHandleDescriptor(
                        handle,
                        owned.Length,
                        hash,
                        expires);
                    return true;
                }
                catch
                {
                    CryptographicOperations.ZeroMemory(owned);
                    reasonCode = "audit_unavailable";
                    descriptor = null;
                    return false;
                }
            }
        }

        public PixelContentReadOutcome Read(
            PixelContentReadRequest request)
        {
            if (request == null)
                throw new ArgumentNullException(nameof(request));

            lock (_sync)
            {
                ThrowIfDisposed();
                PurgeExpiredLocked();
                if (!_entries.TryGetValue(
                        request.Handle ?? string.Empty,
                        out Entry entry))
                {
                    return RejectReadLocked(
                        request,
                        null,
                        "content_handle_not_found");
                }
                if (entry.ExpiresMonotonic
                    <= _clock.MonotonicMilliseconds)
                {
                    ExpireLocked(entry);
                    return RejectReadLocked(
                        request,
                        entry,
                        "content_handle_expired");
                }
                if (entry.Completed)
                {
                    return RejectReadLocked(
                        request,
                        entry,
                        entry.TerminalReason
                            ?? "content_handle_replayed");
                }
                if (!BindingMatches(entry.Binding, request))
                {
                    return RejectReadLocked(
                        request,
                        entry,
                        "content_handle_binding_mismatch");
                }
                if (request.MaximumBytes <= 0)
                {
                    return RejectReadLocked(
                        request,
                        entry,
                        "binary_chunk_size_invalid");
                }
                if (request.MaximumBytes
                    > AgentProtocolV1.MaximumBinaryChunkBytes)
                {
                    return RejectReadLocked(
                        request,
                        entry,
                        "binary_chunk_too_large");
                }
                if (request.Offset != entry.NextOffset)
                {
                    return RejectReadLocked(
                        request,
                        entry,
                        "content_handle_offset_mismatch");
                }
                if (!_grants.TryAuthorize(
                        entry.Binding.ObservationGrantId,
                        entry.Binding.ClientInstanceId,
                        entry.Binding.SecurityPrincipalId,
                        entry.Binding.SessionId,
                        entry.Binding.TargetId,
                        entry.Binding.DataScope,
                        out _,
                        out string grantReason))
                {
                    return RejectReadLocked(
                        request,
                        entry,
                        grantReason
                            ?? "observation_grant_inactive");
                }

                int remaining = checked(
                    entry.TotalBytes - (int)entry.NextOffset);
                int count = Math.Min(request.MaximumBytes, remaining);
                byte[] chunk = new byte[count];
                Buffer.BlockCopy(
                    entry.Content,
                    (int)entry.NextOffset,
                    chunk,
                    0,
                    count);
                long offset = entry.NextOffset;
                long nextOffset = checked(offset + count);
                bool final = nextOffset == entry.TotalBytes;
                try
                {
                    AuditLocked(
                        "pixel_handle_read",
                        entry.Handle,
                        entry.Binding,
                        offset,
                        request.MaximumBytes,
                        count,
                        final,
                        true,
                        null);
                }
                catch
                {
                    CryptographicOperations.ZeroMemory(chunk);
                    return PixelContentReadOutcome.Rejected(
                        "audit_unavailable");
                }

                entry.NextOffset = nextOffset;
                if (final)
                {
                    entry.Completed = true;
                    entry.TerminalReason =
                        "content_handle_replayed";
                    ReleaseContentLocked(entry);
                }
                return PixelContentReadOutcome.Read(
                    chunk,
                    offset,
                    final,
                    entry.ContentHash,
                    entry.TotalBytes);
            }
        }

        public int RevokeObservation(
            string observationId,
            string reasonCode)
        {
            if (string.IsNullOrWhiteSpace(observationId))
                throw new ArgumentException(
                    "An observation ID is required.",
                    nameof(observationId));
            if (string.IsNullOrWhiteSpace(reasonCode))
                throw new ArgumentException(
                    "A reason code is required.",
                    nameof(reasonCode));
            lock (_sync)
            {
                ThrowIfDisposed();
                int revoked = 0;
                foreach (Entry entry in _entries.Values)
                {
                    if (!entry.Completed
                        && string.Equals(
                            entry.Binding.ObservationId,
                            observationId,
                            StringComparison.Ordinal))
                    {
                        AuditLocked(
                            "pixel_handle_revoke",
                            entry.Handle,
                            entry.Binding,
                            entry.NextOffset,
                            0,
                            0,
                            false,
                            true,
                            reasonCode);
                        entry.Completed = true;
                        entry.TerminalReason = reasonCode;
                        ReleaseContentLocked(entry);
                        revoked++;
                    }
                }
                return revoked;
            }
        }

        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed) return;
                foreach (Entry entry in _entries.Values)
                    ReleaseContentLocked(entry);
                _entries.Clear();
                _disposed = true;
            }
        }

        private PixelContentReadOutcome RejectReadLocked(
            PixelContentReadRequest request,
            Entry entry,
            string reasonCode)
        {
            PixelContentBinding binding = entry?.Binding
                ?? new PixelContentBinding
                {
                    ClientInstanceId = request.ClientInstanceId,
                    SecurityPrincipalId = request.SecurityPrincipalId,
                    SessionId = request.SessionId,
                    ObservationGrantId = request.ObservationGrantId,
                    ObservationId = request.ObservationId,
                    TargetId = string.Empty,
                    DataScope = string.Empty
                };
            try
            {
                AuditLocked(
                    "pixel_handle_read",
                    request.Handle,
                    binding,
                    request.Offset,
                    request.MaximumBytes,
                    0,
                    false,
                    false,
                    reasonCode);
            }
            catch
            {
                return PixelContentReadOutcome.Rejected(
                    "audit_unavailable");
            }
            return PixelContentReadOutcome.Rejected(reasonCode);
        }

        private void PurgeExpiredLocked()
        {
            foreach (Entry entry in _entries.Values)
            {
                if (!entry.Completed
                    && entry.ExpiresMonotonic
                        <= _clock.MonotonicMilliseconds)
                {
                    ExpireLocked(entry);
                }
            }
            string[] oldTombstones = _entries
                .Where(pair =>
                    pair.Value.Completed
                    && pair.Value.ExpiresMonotonic
                        + AgentProtocolV1.MaximumContentHandleTtlMs
                        <= _clock.MonotonicMilliseconds)
                .Select(pair => pair.Key)
                .ToArray();
            foreach (string handle in oldTombstones)
                _entries.Remove(handle);
        }

        private void ExpireLocked(Entry entry)
        {
            entry.Completed = true;
            entry.TerminalReason = "content_handle_expired";
            ReleaseContentLocked(entry);
        }

        private void ReleaseContentLocked(Entry entry)
        {
            byte[] content = entry.Content;
            if (content == null) return;
            entry.Content = null;
            _residentBytes = checked(
                _residentBytes - content.Length);
            CryptographicOperations.ZeroMemory(content);
        }

        private void AuditLocked(
            string eventType,
            string handle,
            PixelContentBinding binding,
            long offset,
            int requestedBytes,
            int returnedBytes,
            bool final,
            bool accepted,
            string reasonCode)
        {
            _audit.Record(
                new PixelContentAuditEvent(
                    eventType,
                    handle,
                    binding?.SecurityPrincipalId,
                    binding?.SessionId,
                    binding?.ObservationGrantId,
                    binding?.ObservationId,
                    offset,
                    requestedBytes,
                    returnedBytes,
                    final,
                    accepted,
                    reasonCode,
                    _clock.MonotonicMilliseconds,
                    _clock.UtcNow));
        }

        private static string ValidateBinding(PixelContentBinding binding)
        {
            if (binding == null
                || string.IsNullOrWhiteSpace(binding.ClientInstanceId)
                || string.IsNullOrWhiteSpace(
                    binding.SecurityPrincipalId)
                || string.IsNullOrWhiteSpace(binding.SessionId)
                || string.IsNullOrWhiteSpace(
                    binding.ObservationGrantId)
                || string.IsNullOrWhiteSpace(binding.ObservationId)
                || string.IsNullOrWhiteSpace(binding.TargetId)
                || string.IsNullOrWhiteSpace(binding.DataScope))
            {
                return "content_handle_binding_invalid";
            }
            return null;
        }

        private static bool BindingMatches(
            PixelContentBinding binding,
            PixelContentReadRequest request)
        {
            return string.Equals(
                    binding.ClientInstanceId,
                    request.ClientInstanceId,
                    StringComparison.Ordinal)
                && string.Equals(
                    binding.SecurityPrincipalId,
                    request.SecurityPrincipalId,
                    StringComparison.Ordinal)
                && string.Equals(
                    binding.SessionId,
                    request.SessionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    binding.ObservationGrantId,
                    request.ObservationGrantId,
                    StringComparison.Ordinal)
                && string.Equals(
                    binding.ObservationId,
                    request.ObservationId,
                    StringComparison.Ordinal);
        }

        private static PixelContentBinding CloneBinding(
            PixelContentBinding binding)
        {
            return new PixelContentBinding
            {
                ClientInstanceId = binding.ClientInstanceId,
                SecurityPrincipalId = binding.SecurityPrincipalId,
                SessionId = binding.SessionId,
                ObservationGrantId = binding.ObservationGrantId,
                ObservationId = binding.ObservationId,
                TargetId = binding.TargetId,
                DataScope = binding.DataScope
            };
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(GetType().Name);
        }

        private sealed class Entry
        {
            public Entry(
                string handle,
                PixelContentBinding binding,
                byte[] content,
                string contentHash,
                long expiresMonotonic)
            {
                Handle = handle;
                Binding = binding;
                Content = content;
                ContentHash = contentHash;
                TotalBytes = content.Length;
                ExpiresMonotonic = expiresMonotonic;
            }

            public string Handle { get; }
            public PixelContentBinding Binding { get; }
            public byte[] Content { get; set; }
            public string ContentHash { get; }
            public int TotalBytes { get; }
            public long ExpiresMonotonic { get; }
            public long NextOffset { get; set; }
            public bool Completed { get; set; }
            public string TerminalReason { get; set; }
        }
    }
}
