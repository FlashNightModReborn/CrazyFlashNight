using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Audit
{
    public enum AuditSegmentTerminalKind
    {
        None,
        Completed,
        Truncated
    }

    public sealed record AuditEntry(
        string SegmentId,
        long ServerSequence,
        string PreviousHash,
        DateTimeOffset RecordedUtc,
        long RecordedMonotonic,
        string EventType,
        string CanonicalPayload,
        string PayloadHash,
        AuditSegmentTerminalKind TerminalKind,
        string EntryHash);

    public sealed record AuditSegmentReceipt(
        string SegmentId,
        long FinalServerSequence,
        string FinalHash,
        AuditSegmentTerminalKind TerminalKind,
        DateTimeOffset SealedUtc);

    public sealed class AuditVerificationResult
    {
        internal AuditVerificationResult(
            bool valid,
            string reasonCode,
            long verifiedEntries,
            string finalHash,
            AuditSegmentTerminalKind terminalKind)
        {
            Valid = valid;
            ReasonCode = reasonCode;
            VerifiedEntries = verifiedEntries;
            FinalHash = finalHash;
            TerminalKind = terminalKind;
        }

        public bool Valid { get; }
        public string ReasonCode { get; }
        public long VerifiedEntries { get; }
        public string FinalHash { get; }
        public AuditSegmentTerminalKind TerminalKind { get; }
    }

    /// <summary>
    /// A bounded append-only hash-chain segment. The final receipt is intended
    /// to be anchored by the host; a segment alone cannot defend against a
    /// hostile process rewriting the entire segment and its receipt.
    /// </summary>
    public sealed class AppendOnlyAuditSegment
    {
        public const int MaximumCanonicalPayloadBytes = 64 * 1024;
        public const int MaximumEntries = 10000;
        public const string GenesisHash =
            "0000000000000000000000000000000000000000000000000000000000000000";

        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly List<AuditEntry> _entries =
            new List<AuditEntry>();
        private AuditSegmentReceipt _receipt;

        public AppendOnlyAuditSegment(
            IAgentRuntimeClock clock,
            string segmentId = null)
        {
            _clock = clock ?? throw new ArgumentNullException(nameof(clock));
            SegmentId = string.IsNullOrWhiteSpace(segmentId)
                ? OpaqueIdGenerator.Create("auditseg")
                : segmentId;
        }

        public string SegmentId { get; }

        public bool IsSealed
        {
            get
            {
                lock (_sync)
                {
                    return _receipt != null;
                }
            }
        }

        public AuditEntry Append(
            string eventType,
            string canonicalPayload)
        {
            return AppendInternal(
                eventType,
                canonicalPayload,
                AuditSegmentTerminalKind.None);
        }

        public AuditSegmentReceipt SealCompleted(string canonicalPayload)
        {
            return Seal(
                "segment_completed",
                canonicalPayload,
                AuditSegmentTerminalKind.Completed);
        }

        public AuditSegmentReceipt SealTruncated(string reasonCode)
        {
            PrincipalCredentialAuthority.RequireValue(
                reasonCode,
                nameof(reasonCode));
            string payload = "{\"reasonCode\":\""
                + EscapeJsonString(reasonCode)
                + "\"}";
            return SealTruncated(
                reasonCode,
                payload);
        }

        public AuditSegmentReceipt SealTruncated(
            string reasonCode,
            string canonicalPayload)
        {
            PrincipalCredentialAuthority.RequireValue(
                reasonCode,
                nameof(reasonCode));
            if (canonicalPayload == null)
            {
                throw new ArgumentNullException(
                    nameof(canonicalPayload));
            }
            return Seal(
                "segment_truncated",
                canonicalPayload,
                AuditSegmentTerminalKind.Truncated);
        }

        public ReadOnlyCollection<AuditEntry> Snapshot()
        {
            lock (_sync)
            {
                return Array.AsReadOnly(_entries.ToArray());
            }
        }

        public static AuditVerificationResult Verify(
            IEnumerable<AuditEntry> entries,
            string expectedSegmentId,
            AuditSegmentReceipt expectedReceipt = null)
        {
            if (entries == null)
            {
                throw new ArgumentNullException(nameof(entries));
            }
            PrincipalCredentialAuthority.RequireValue(
                expectedSegmentId,
                nameof(expectedSegmentId));

            string previous = GenesisHash;
            long expectedSequence = 1;
            AuditSegmentTerminalKind terminal =
                AuditSegmentTerminalKind.None;
            long previousMonotonic = long.MinValue;
            AuditEntry[] snapshot = entries.ToArray();

            foreach (AuditEntry entry in snapshot)
            {
                if (entry == null)
                {
                    return Invalid(
                        "null_entry",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }
                if (terminal != AuditSegmentTerminalKind.None)
                {
                    return Invalid(
                        "entry_after_terminal",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }
                if (string.IsNullOrWhiteSpace(entry.EventType)
                    || entry.CanonicalPayload == null)
                {
                    return Invalid(
                        "entry_shape_invalid",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }
                if (Encoding.UTF8.GetByteCount(entry.CanonicalPayload)
                    > MaximumCanonicalPayloadBytes)
                {
                    return Invalid(
                        "audit_payload_too_large",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }
                if (entry.RecordedMonotonic < previousMonotonic)
                {
                    return Invalid(
                        "monotonic_time_regressed",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }
                if (!string.Equals(
                        expectedSegmentId,
                        entry.SegmentId,
                        StringComparison.Ordinal))
                {
                    return Invalid(
                        "segment_id_mismatch",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }
                if (entry.ServerSequence != expectedSequence)
                {
                    return Invalid(
                        "server_sequence_mismatch",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }
                if (!string.Equals(
                        previous,
                        entry.PreviousHash,
                        StringComparison.Ordinal))
                {
                    return Invalid(
                        "previous_hash_mismatch",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }

                string payloadHash = HashUtf8(
                    entry.CanonicalPayload ?? string.Empty);
                if (!string.Equals(
                        payloadHash,
                        entry.PayloadHash,
                        StringComparison.Ordinal))
                {
                    return Invalid(
                        "payload_hash_mismatch",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }
                string entryHash = ComputeEntryHash(
                    entry.SegmentId,
                    entry.ServerSequence,
                    entry.PreviousHash,
                    entry.RecordedUtc,
                    entry.RecordedMonotonic,
                    entry.EventType,
                    entry.PayloadHash,
                    entry.TerminalKind);
                if (!string.Equals(
                        entryHash,
                        entry.EntryHash,
                        StringComparison.Ordinal))
                {
                    return Invalid(
                        "entry_hash_mismatch",
                        expectedSequence - 1,
                        previous,
                        terminal);
                }

                previous = entry.EntryHash;
                terminal = entry.TerminalKind;
                previousMonotonic = entry.RecordedMonotonic;
                expectedSequence++;
            }

            if (expectedReceipt != null)
            {
                AuditEntry finalEntry = snapshot.LastOrDefault();
                if (!string.Equals(
                        expectedReceipt.SegmentId,
                        expectedSegmentId,
                        StringComparison.Ordinal)
                    || finalEntry == null
                    || terminal == AuditSegmentTerminalKind.None
                    || expectedReceipt.TerminalKind
                        == AuditSegmentTerminalKind.None
                    || expectedReceipt.FinalServerSequence
                        != snapshot.LongLength
                    || !string.Equals(
                        expectedReceipt.FinalHash,
                        previous,
                        StringComparison.Ordinal)
                    || expectedReceipt.TerminalKind != terminal
                    || expectedReceipt.SealedUtc
                        != finalEntry.RecordedUtc)
                {
                    return Invalid(
                        "receipt_mismatch",
                        snapshot.LongLength,
                        previous,
                        terminal);
                }
            }

            return new AuditVerificationResult(
                true,
                null,
                snapshot.LongLength,
                previous,
                terminal);
        }

        private AuditSegmentReceipt Seal(
            string eventType,
            string canonicalPayload,
            AuditSegmentTerminalKind terminalKind)
        {
            lock (_sync)
            {
                if (_receipt != null)
                {
                    return _receipt;
                }
                AuditEntry terminal = AppendLocked(
                    eventType,
                    canonicalPayload,
                    terminalKind);
                _receipt = new AuditSegmentReceipt(
                    SegmentId,
                    terminal.ServerSequence,
                    terminal.EntryHash,
                    terminalKind,
                    terminal.RecordedUtc);
                return _receipt;
            }
        }

        private AuditEntry AppendInternal(
            string eventType,
            string canonicalPayload,
            AuditSegmentTerminalKind terminalKind)
        {
            lock (_sync)
            {
                if (_receipt != null)
                {
                    throw new InvalidOperationException(
                        "audit_segment_sealed");
                }
                return AppendLocked(
                    eventType,
                    canonicalPayload,
                    terminalKind);
            }
        }

        private AuditEntry AppendLocked(
            string eventType,
            string canonicalPayload,
            AuditSegmentTerminalKind terminalKind)
        {
            PrincipalCredentialAuthority.RequireValue(
                eventType,
                nameof(eventType));
            if (canonicalPayload == null)
            {
                throw new ArgumentNullException(nameof(canonicalPayload));
            }
            int payloadBytes = Encoding.UTF8.GetByteCount(
                canonicalPayload);
            if (payloadBytes > MaximumCanonicalPayloadBytes)
            {
                throw new InvalidOperationException(
                    "audit_payload_too_large");
            }
            if (_entries.Count >= MaximumEntries)
            {
                throw new InvalidOperationException(
                    "audit_segment_full");
            }
            if (terminalKind == AuditSegmentTerminalKind.None
                && _entries.Count >= MaximumEntries - 1)
            {
                throw new InvalidOperationException(
                    "audit_segment_needs_seal");
            }

            long sequence = checked(_entries.Count + 1L);
            string previousHash = _entries.Count == 0
                ? GenesisHash
                : _entries[_entries.Count - 1].EntryHash;
            DateTimeOffset utc = _clock.UtcNow;
            long monotonic = _clock.MonotonicMilliseconds;
            string payloadHash = HashUtf8(canonicalPayload);
            string entryHash = ComputeEntryHash(
                SegmentId,
                sequence,
                previousHash,
                utc,
                monotonic,
                eventType,
                payloadHash,
                terminalKind);
            AuditEntry entry = new AuditEntry(
                SegmentId,
                sequence,
                previousHash,
                utc,
                monotonic,
                eventType,
                canonicalPayload,
                payloadHash,
                terminalKind,
                entryHash);
            _entries.Add(entry);
            return entry;
        }

        private static string ComputeEntryHash(
            string segmentId,
            long sequence,
            string previousHash,
            DateTimeOffset recordedUtc,
            long recordedMonotonic,
            string eventType,
            string payloadHash,
            AuditSegmentTerminalKind terminalKind)
        {
            StringBuilder canonical = new StringBuilder();
            AppendField(canonical, "cf7-audit-v1");
            AppendField(canonical, segmentId);
            AppendField(
                canonical,
                sequence.ToString(CultureInfo.InvariantCulture));
            AppendField(canonical, previousHash);
            AppendField(
                canonical,
                recordedUtc.ToUniversalTime().ToString(
                    "O",
                    CultureInfo.InvariantCulture));
            AppendField(
                canonical,
                recordedMonotonic.ToString(
                    CultureInfo.InvariantCulture));
            AppendField(canonical, eventType);
            AppendField(canonical, payloadHash);
            AppendField(
                canonical,
                ((int)terminalKind).ToString(
                    CultureInfo.InvariantCulture));
            return HashUtf8(canonical.ToString());
        }

        private static void AppendField(
            StringBuilder builder,
            string value)
        {
            value ??= string.Empty;
            builder.Append(
                Encoding.UTF8.GetByteCount(value).ToString(
                    CultureInfo.InvariantCulture));
            builder.Append(':');
            builder.Append(value);
        }

        private static string HashUtf8(string value)
        {
            return Convert.ToHexString(
                    SHA256.HashData(Encoding.UTF8.GetBytes(value)))
                .ToLowerInvariant();
        }

        private static AuditVerificationResult Invalid(
            string reason,
            long verified,
            string finalHash,
            AuditSegmentTerminalKind terminal)
        {
            return new AuditVerificationResult(
                false,
                reason,
                verified,
                finalHash,
                terminal);
        }

        private static string EscapeJsonString(string value)
        {
            StringBuilder result = new StringBuilder(value.Length);
            foreach (char character in value)
            {
                switch (character)
                {
                    case '\\':
                        result.Append("\\\\");
                        break;
                    case '"':
                        result.Append("\\\"");
                        break;
                    case '\r':
                        result.Append("\\r");
                        break;
                    case '\n':
                        result.Append("\\n");
                        break;
                    case '\t':
                        result.Append("\\t");
                        break;
                    default:
                        if (char.IsControl(character))
                        {
                            result.Append("\\u");
                            result.Append(
                                ((int)character).ToString("x4"));
                        }
                        else
                        {
                            result.Append(character);
                        }
                        break;
                }
            }
            return result.ToString();
        }
    }
}
