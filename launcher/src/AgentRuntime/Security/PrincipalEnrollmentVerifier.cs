using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;

namespace CF7Launcher.AgentRuntime.Security
{
    public sealed class VerifiedPrincipalAuthorization
    {
        internal VerifiedPrincipalAuthorization(
            IEnumerable<string> allowedCapabilities,
            IEnumerable<string> allowedTargets,
            string issuerReceipt)
        {
            AllowedCapabilities = Freeze(allowedCapabilities);
            AllowedTargets = Freeze(allowedTargets);
            PrincipalCredentialAuthority.RequireValue(
                issuerReceipt,
                nameof(issuerReceipt));
            IssuerReceipt = issuerReceipt;
        }

        public ReadOnlyCollection<string> AllowedCapabilities { get; }
        public ReadOnlyCollection<string> AllowedTargets { get; }
        public string IssuerReceipt { get; }

        internal static VerifiedPrincipalAuthorization CreateTrusted(
            IEnumerable<string> allowedCapabilities,
            IEnumerable<string> allowedTargets,
            string issuerReceipt)
        {
            return new VerifiedPrincipalAuthorization(
                allowedCapabilities,
                allowedTargets,
                issuerReceipt);
        }

        private static ReadOnlyCollection<string> Freeze(
            IEnumerable<string> values)
        {
            return Array.AsReadOnly(
                (values ?? Array.Empty<string>())
                    .Where(value => !string.IsNullOrWhiteSpace(value))
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray());
        }
    }

    /// <summary>
    /// Host-owned issuer boundary. Implementations verify neutral Launcher
    /// receipts or immutable runner allow-list evidence and return the
    /// authoritative scope; request booleans are intentionally not accepted.
    /// </summary>
    public interface IPrincipalEnrollmentVerifier
    {
        bool TryVerifyDeveloper(
            DeveloperEnrollmentEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode);

        bool TryVerifyUnattended(
            UnattendedCredentialEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode);

        bool TryVerifyPlayerAssist(
            PlayerAssistCredentialEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode);
    }
}
