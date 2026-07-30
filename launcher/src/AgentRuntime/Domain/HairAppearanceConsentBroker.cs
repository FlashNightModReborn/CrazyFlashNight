using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Domain
{
    public sealed class HairAppearanceConsentBroker
    {
        private sealed class Grant
        {
            public string TransactionId;
            public string PreviewHash;
            public long ExpiresAtMonotonic;
            public bool Consumed;
        }

        public static readonly TimeSpan MaximumConsentTtl =
            TimeSpan.FromSeconds(60);

        private const int DefaultMaximumActiveGrants = 256;
        private readonly IAgentRuntimeClock _clock;
        private readonly int _maximumActiveGrants;
        private readonly object _gate = new object();
        private readonly Dictionary<string, Grant> _grants =
            new Dictionary<string, Grant>(StringComparer.Ordinal);

        public HairAppearanceConsentBroker(
            IAgentRuntimeClock clock,
            int maximumActiveGrants = DefaultMaximumActiveGrants)
        {
            _clock = clock ?? throw new ArgumentNullException(nameof(clock));
            if (maximumActiveGrants <= 0 || maximumActiveGrants > 4096)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(maximumActiveGrants));
            }
            _maximumActiveGrants = maximumActiveGrants;
        }

        /// <summary>
        /// This issuer is intentionally internal. It may only be reached after
        /// the neutral Launcher consent presenter returns a trusted human
        /// approval for the exact preview. Agent request payloads and Persona
        /// output are never approval evidence.
        /// </summary>
        internal HairAppearanceConsentToken IssueForNeutralUi(
            HairAppearancePreview preview,
            string consentReceiptId,
            TimeSpan requestedTtl)
        {
            if (!HairAppearanceValidation.PreviewHashIsAuthentic(preview)
                || !HairAppearanceValidation.IsSafeString(
                    consentReceiptId,
                    160,
                    false))
            {
                throw new ArgumentException(
                    "Consent must bind an authentic preview and receipt.");
            }
            if (requestedTtl <= TimeSpan.Zero)
            {
                throw new ArgumentOutOfRangeException(nameof(requestedTtl));
            }

            TimeSpan effectiveTtl = requestedTtl <= MaximumConsentTtl
                ? requestedTtl
                : MaximumConsentTtl;
            long ttlMilliseconds = Math.Max(
                1,
                checked((long)effectiveTtl.TotalMilliseconds));
            string token = CreateToken();
            string tokenHash = HairAppearanceHashing.HashOpaqueToken(token);

            lock (_gate)
            {
                PurgeExpiredLocked();
                if (_grants.Count >= _maximumActiveGrants)
                {
                    throw new InvalidOperationException(
                        "The bounded consent grant table is full.");
                }
                _grants.Add(
                    tokenHash,
                    new Grant
                    {
                        TransactionId = preview.TransactionId,
                        PreviewHash = preview.PreviewHash,
                        ExpiresAtMonotonic = checked(
                            _clock.MonotonicMilliseconds + ttlMilliseconds)
                    });
            }

            return new HairAppearanceConsentToken(
                token,
                preview.TransactionId,
                preview.PreviewHash,
                consentReceiptId,
                _clock.UtcNow.AddMilliseconds(ttlMilliseconds));
        }

        internal string TryConsume(
            string token,
            HairAppearancePreview preview)
        {
            if (string.IsNullOrWhiteSpace(token))
            {
                return HairAppearanceReasonCodes.ConsentRequired;
            }
            if (!HairAppearanceValidation.IsSafeString(token, 256, false))
            {
                return HairAppearanceReasonCodes.ConsentMismatch;
            }
            if (!HairAppearanceValidation.PreviewHashIsAuthentic(preview))
            {
                return HairAppearanceReasonCodes.ConsentMismatch;
            }

            string tokenHash = HairAppearanceHashing.HashOpaqueToken(token);
            lock (_gate)
            {
                Grant grant;
                if (!_grants.TryGetValue(tokenHash, out grant))
                {
                    PurgeExpiredLocked();
                    return HairAppearanceReasonCodes.ConsentMismatch;
                }
                if (grant.Consumed)
                {
                    return HairAppearanceReasonCodes.ConsentReplayed;
                }
                if (_clock.MonotonicMilliseconds >= grant.ExpiresAtMonotonic)
                {
                    _grants.Remove(tokenHash);
                    return HairAppearanceReasonCodes.ConsentExpired;
                }
                if (!string.Equals(
                        grant.TransactionId,
                        preview.TransactionId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        grant.PreviewHash,
                        preview.PreviewHash,
                        StringComparison.Ordinal))
                {
                    return HairAppearanceReasonCodes.ConsentMismatch;
                }

                grant.Consumed = true;
                return null;
            }
        }

        private void PurgeExpiredLocked()
        {
            long now = _clock.MonotonicMilliseconds;
            var expired = new List<string>();
            foreach (KeyValuePair<string, Grant> pair in _grants)
            {
                if (now >= pair.Value.ExpiresAtMonotonic)
                {
                    expired.Add(pair.Key);
                }
            }
            for (int i = 0; i < expired.Count; i++)
            {
                _grants.Remove(expired[i]);
            }
        }

        private static string CreateToken()
        {
            byte[] entropy = new byte[32];
            RandomNumberGenerator.Fill(entropy);
            return Convert.ToBase64String(entropy)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }
    }
}
